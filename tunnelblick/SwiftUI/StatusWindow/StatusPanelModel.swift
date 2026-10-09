//
//  StatusPanelModel.swift
//  Tunnelblick
//
//  The model behind the floating VPN status window of the new interface.
//
//  StatusWindowController (Objective-C) still owns the window and all of its show/hide/fade/positioning logic. When the
//  new interface is in use it creates one StatusPanelModel per window, asks it for the panel (makePanel), forwards
//  -setStatus:forName:connectedSince: and -enableOrDisableButtons to it, and asks it for the panel's sizes when it
//  positions the window. The model reads statistics and warnings from AppModel snapshots.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import Combine
import SwiftUI

@objc(StatusPanelModel)
@MainActor
final class StatusPanelModel: NSObject, ObservableObject {

    // MARK: Layout (fixed so the Objective-C positioning code knows the sizes in advance)

    static let collapsedHeight: CGFloat = 38
    static let ratesHeight: CGFloat = 34
    static let warningHeight: CGFloat = 30
    static let actionsHeight: CGFloat = 22
    static let detailSpacing: CGFloat = 8
    static let bottomPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 12

    static func detailHeight(hasWarning: Bool) -> CGFloat {
        ratesHeight + detailSpacing
            + (hasWarning ? warningHeight + detailSpacing : 0)
            + actionsHeight + bottomPadding
    }

    // MARK: State

    let displayName: String
    private let connection: VPNConnection
    private weak var controller: NSWindowController?
    private(set) weak var panel: NSPanel?

    @Published private(set) var name: String
    @Published private(set) var state: String = "EXITING"
    @Published private(set) var pushedTime: String = ""
    @Published private(set) var snapshot: ConnectionSnapshot?
    @Published private(set) var authFailed = false
    @Published private(set) var uiEnabled = true
    @Published private(set) var isExpanded = false
    @Published private(set) var actionPending = false

    private var snapshotObserver: AnyCancellable?

    @objc init(connection: VPNConnection, controller: NSWindowController) {
        self.connection = connection
        self.controller = controller
        let displayName = connection.displayName() ?? ""
        self.displayName = displayName
        self.name = connection.localizedName() ?? displayName
        super.init()

        AppModel.shared.start()
        snapshotObserver = AppModel.shared.$snapshots.sink { [weak self] _ in
            // @Published sends before the value changes; read the new value on the next main-actor turn.
            Task { @MainActor in self?.refreshFromAppModel() }
        }
        refreshFromAppModel()
    }

    // MARK: Called from StatusWindowController

    /// Forwarded from -[StatusWindowController setStatus:forName:connectedSince:].
    @objc(updateStatus:connectedSince:)
    func updateStatus(_ status: String?, connectedSince time: String?) {
        let newState = status ?? "EXITING"
        if newState != state {
            state = newState
            actionPending = false
        }
        let newTime = (newState == "EXITING") ? "" : (time ?? "").trimmingCharacters(in: .whitespaces)
        if newTime != pushedTime {
            pushedTime = newTime
        }
        let newName = connection.localizedName() ?? displayName
        if newName != name {
            name = newName
        }
        refreshFromConnection()
    }

    /// Forwarded from -[StatusWindowController enableOrDisableButtons] (TBOperationQueue calls it when it starts or ends work).
    @objc func buttonsStateMayHaveChanged() {
        // Like the classic window, a click disables the button only until the buttons are next validated, so the button
        // cannot stay disabled when the click did not change the state (e.g. the user cancelled a dialog).
        actionPending = false
        refreshFromConnection()
    }

    /// The window was closed (after fading out, or with the close button): show it collapsed next time.
    @objc func panelDidClose() {
        isExpanded = false
        if let panel {
            var frame = panel.frame
            let top = frame.maxY
            frame.size.height = Self.collapsedHeight
            frame.origin.y = top - frame.size.height
            panel.setFrame(frame, display: false)
        }
    }

    /// Width of the panel: wide enough for the configuration name and a status, within limits.
    @objc var panelWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let nameWidth = (name as NSString).size(withAttributes: [.font: font]).width
        return min(max(272, ceil(nameWidth) + 196), 440)
    }

    /// Height of the panel now (collapsed or expanded).
    @objc var currentHeight: CGFloat {
        isExpanded ? Self.collapsedHeight + Self.detailHeight(hasWarning: hasWarning) : Self.collapsedHeight
    }

    /// Height reserved for the panel's position slot: the largest expanded size, so stacked panels never overlap.
    @objc var slotHeight: CGFloat {
        Self.collapsedHeight + Self.detailHeight(hasWarning: true)
    }

    /// Creates the borderless, non-activating floating panel that StatusWindowController uses as its window.
    @objc func makePanel() -> NSPanel {
        let width = panelWidth
        let frame = NSRect(x: 0, y: 0, width: width, height: currentHeight)
        let panel = StatusHUDPanel(contentRect: frame,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: true)
        panel.model = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0      // fadeIn animates it to 1
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.title = L("Tunnelblick")

        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        effect.autoresizingMask = [.width, .height]

        let hosting = StatusHostingView(rootView: StatusPanelView(model: self))
        hosting.sizingOptions = []
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        panel.contentView = effect
        self.panel = panel
        return panel
    }

    // MARK: User actions

    func toggleExpanded() {
        setExpanded(!isExpanded)
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        guard let panel else {
            isExpanded = expanded
            return
        }
        let newHeight = expanded ? Self.collapsedHeight + Self.detailHeight(hasWarning: hasWarning) : Self.collapsedHeight
        resize(to: newHeight, animated: true) {
            self.isExpanded = expanded
        }
        if expanded {
            // Now that it is expanded it can become key, so Esc collapses it. The panel is non-activating, so
            // Tunnelblick does not become the active app.
            panel.makeKey()
        }
    }

    func connectOrDisconnect() {
        guard let controller, buttonIsEnabled else { return }
        actionPending = true
        let selector = (state == "EXITING") ? "connectButtonWasClicked:" : "disconnectButtonWasClicked:"
        controller.perform(NSSelectorFromString(selector), with: nil)
    }

    func review() {
        TBSwiftUI.showDetailsWindow(selectingDisplayName: displayName)
    }

    /// Same as the red dot of the classic status window: hides it until the user connects this configuration again.
    func close() {
        guard let controller else { return }
        controller.perform(NSSelectorFromString("closeButtonWasClicked:"), with: nil)
    }

    // MARK: Derived values for the view

    var hasWarning: Bool {
        state == "CONNECTED" && !(snapshot?.warnings.isEmpty ?? true)
    }

    var warningCount: Int {
        state == "CONNECTED" ? (snapshot?.warnings.count ?? 0) : 0
    }

    enum DotKind { case connected, warning, busy, failed, idle }

    var dotKind: DotKind {
        if state == "CONNECTED" { return hasWarning ? .warning : .connected }
        if state == "EXITING" { return authFailed ? .failed : .idle }
        return .busy
    }

    var statusText: String {
        switch state {
        case "CONNECTED":
            let count = warningCount
            if count == 1 { return L("Connected · 1 warning") }
            if count > 1 { return LF("Connected · %ld warnings", count) }
            return localizedState("CONNECTED")
        case "EXITING":
            return authFailed ? L("Authorization failed") : localizedState("EXITING")
        default:
            let text = localizedState(state)
            if text.hasSuffix("…") || text.hasSuffix("...") { return text }
            return text + "…"
        }
    }

    var timeText: String {
        guard state != "EXITING" else { return "" }
        if let elapsed = snapshot?.elapsed, !elapsed.isEmpty { return elapsed }
        return pushedTime
    }

    var warningText: String? {
        guard hasWarning, let first = snapshot?.warnings.first else { return nil }
        if first.kind.isDNS { return L("DNS lookups are leaving outside the VPN") }
        if first.kind == .publicIpUnchanged { return L("Your public IP address didn’t change") }
        return L("Tunnelblick found problems with this connection")
    }

    /// "Connect" when disconnected, otherwise "Disconnect" (like the two buttons of the classic window).
    var buttonTitle: String {
        state == "EXITING" ? L("Connect") : L("Disconnect")
    }

    /// The same rules as -[StatusWindowController enableOrDisableButtons].
    var buttonIsEnabled: Bool {
        if actionPending { return false }
        if !uiEnabled { return state != "EXITING" }     // Connect disabled, Disconnect enabled
        return true                                      // EXITING: Connect enabled; otherwise Disconnect enabled
    }

    var showsRates: Bool { state != "EXITING" }

    // MARK: Private

    private func refreshFromAppModel() {
        let new = AppModel.shared.snapshots[displayName]
        if new != snapshot {
            snapshot = new
        }
        refreshFromConnection()
        // A warning can appear or go away while expanded: keep the panel's height in step, top edge fixed.
        if isExpanded, let panel {
            let wanted = currentHeight
            if abs(panel.frame.size.height - wanted) > 0.5 {
                resize(to: wanted, animated: true, then: nil)
            }
        }
    }

    private func refreshFromConnection() {
        let failed = connection.authFailed()
        if failed != authFailed {
            authFailed = failed
        }
        let enabled = TBOperationQueue.shouldUIBeEnabled(forDisplayName: displayName)
        if enabled != uiEnabled {
            uiEnabled = enabled
        }
    }

    private func resize(to height: CGFloat, animated: Bool, then update: (() -> Void)?) {
        guard let panel else {
            update?()
            return
        }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height

        if !animated || Theme.reduceMotion {
            update?()
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            return
        }

        if let update {
            withAnimation(.easeInOut(duration: 0.22)) {
                update()
            }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.panel?.invalidateShadow() }
        })
    }

    /// A stretchable rounded-rectangle mask, so the vibrancy and the window shadow have rounded corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Panel and hosting view

/// Borderless panel that can become key only while expanded (so showing it never takes the keyboard from another app),
/// and collapses on Esc.
final class StatusHUDPanel: NSPanel {

    weak var model: StatusPanelModel?

    override var canBecomeKey: Bool {
        model?.isExpanded ?? false
    }

    override var canBecomeMain: Bool { false }

    /// StatusWindowController shows the panel with -makeKeyAndOrderFront: (in -fadeIn). Appearing must never take the
    /// keyboard from the app the user is working in, even if the panel is still expanded, so only order it front.
    /// (Expanding it on a click makes it key explicitly, with makeKey().)
    override func makeKeyAndOrderFront(_ sender: Any?) {
        orderFront(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        model?.setExpanded(false)
    }
}

/// Accepts the first click even though the panel is not key (the panel never activates Tunnelblick).
final class StatusHostingView: NSHostingView<StatusPanelView> {

    required init(rootView: StatusPanelView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
