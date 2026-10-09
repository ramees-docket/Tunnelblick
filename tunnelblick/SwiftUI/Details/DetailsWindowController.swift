//
//  DetailsWindowController.swift
//  Tunnelblick
//
//  The SwiftUI "VPN Details" window: a System Settings style window with a vibrant sidebar (configurations and the
//  Tunnelblick panes) and a detail area, plus the admin-mode lock in the toolbar.
//
//  The original MyPrefsWindowController is loaded (hidden) by TBSwiftUIBridge.legacyDetails(); this window mirrors and
//  drives its controls. See TBSwiftUIBridge.h.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class DetailsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {

    static let shared = DetailsWindowController(singleton: true)

    private static let frameAutosaveName = "TBSwiftUIDetailsWindow"
    private static let lockItemIdentifier = NSToolbarItem.Identifier("net.tunnelblick.swiftui.adminModeLock")

    private let lockButton = NSButton(title: "", target: nil, action: nil)
    private var lockSymbolName = ""
    private var subscriptions: Set<AnyCancellable> = []

    // A distinct signature, so that it can never be taken for an override of an inherited init().
    private init(singleton: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        window.title = L("Tunnelblick")
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)

        super.init(window: window)

        window.delegate = self
        window.contentViewController = Self.makeSplitViewController()
        window.contentMinSize = NSSize(width: 860, height: 560)
        window.setContentSize(NSSize(width: 1000, height: 680))

        let toolbar = NSToolbar(identifier: "net.tunnelblick.swiftui.detailsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        _ = window.setFrameAutosaveName(Self.frameAutosaveName)

        configureLockButton()
        observeModel()
    }

    required init?(coder: NSCoder) {
        return nil     // Created only in code
    }

    private static func makeSplitViewController() -> NSSplitViewController {
        let split = NSSplitViewController()

        let sidebar = NSHostingController(rootView: DetailsSidebarView())
        sidebar.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 340
        sidebarItem.canCollapse = false
        sidebarItem.allowsFullHeightLayout = true

        let content = NSHostingController(rootView: DetailsContentView())
        content.sizingOptions = []
        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = 620

        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        split.splitView.autosaveName = "TBSwiftUIDetailsSplitView"
        return split
    }

    // MARK: Showing

    func show(selecting displayName: String?) {
        _ = TBSwiftUIBridge.legacyDetails()        // Loads the hidden legacy controller
        let model = AppModel.shared
        model.start()
        model.refreshConfigurations()

        let navigation = DetailsNavigation.shared
        let names = model.displayNames

        if let displayName, names.contains(displayName) {
            navigation.select(.configuration(displayName), force: true)
        } else if let selected = navigation.selection {
            switch selected {
            case .configuration(let previous) where names.contains(previous):
                navigation.select(selected, force: true)
            case .pane:
                navigation.select(selected, force: true)
            default:
                selectDefaultConfiguration(names)
            }
        } else {
            selectDefaultConfiguration(names)
        }

        navigation.setWindowIsVisible(true)
        updateLockButton()
        updateTitle()

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        gMC?.activateIgnoringOtherApps()
    }

    private func selectDefaultConfiguration(_ names: [String]) {
        let navigation = DetailsNavigation.shared
        if let current = AppModel.shared.selectedDisplayName, names.contains(current) {
            navigation.select(.configuration(current), force: true)
        } else if let first = names.first {
            navigation.select(.configuration(first), force: true)
        } else {
            navigation.select(nil, force: true)
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        DetailsNavigation.shared.setWindowIsVisible(false)
        TBSwiftUIBridge.detailsWindowDidClose()
        LegacyRefresh.shared.bump()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        DetailsNavigation.shared.setWindowIsVisible(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        DetailsNavigation.shared.setWindowIsVisible(true)
    }

    // MARK: Model observation

    private func observeModel() {
        // Publishers emit before the value changes; hop to a new main-actor turn to read the new values.
        AppModel.shared.$tick
            .sink { _ in
                Task { @MainActor in DetailsWindowController.shared.tickDidChange() }
            }
            .store(in: &subscriptions)

        LegacyRefresh.shared.$revision
            .sink { _ in
                Task { @MainActor in DetailsWindowController.shared.tickDidChange() }
            }
            .store(in: &subscriptions)

        AppModel.shared.$snapshots
            .sink { snapshots in
                Task { @MainActor in
                    ConnectDurationTracker.shared.update(snapshots)
                    DetailsWindowController.shared.updateTitle()
                }
            }
            .store(in: &subscriptions)

        AppModel.shared.$displayNames
            .sink { _ in
                Task { @MainActor in DetailsWindowController.shared.configurationsDidChange() }
            }
            .store(in: &subscriptions)

        DetailsNavigation.shared.$selection
            .sink { _ in
                Task { @MainActor in DetailsWindowController.shared.updateTitle() }
            }
            .store(in: &subscriptions)
    }

    private func tickDidChange() {
        guard window?.isVisible == true else { return }
        updateLockButton()
    }

    private func configurationsDidChange() {
        guard window?.isVisible == true else { return }
        DetailsNavigation.shared.reconcile(with: AppModel.shared.displayNames)
    }

    private func updateTitle() {
        guard let window else { return }
        let title: String
        switch DetailsNavigation.shared.selection {
        case .configuration(let displayName)?:
            title = AppModel.shared.snapshots[displayName]?.localizedName
                ?? gMC?.localizedName(forDisplayName: displayName)
                ?? displayName
        case .pane(let pane)?:
            title = pane.title
        case nil:
            title = L("Tunnelblick")
        }
        if window.title != title {
            window.title = title
        }
    }

    // MARK: Admin mode lock (toolbar)

    private func configureLockButton() {
        lockButton.bezelStyle = .texturedRounded
        lockButton.setButtonType(.momentaryPushIn)
        lockButton.imagePosition = .imageLeading
        lockButton.imageHugsTitle = true
        lockButton.target = self
        lockButton.action = #selector(lockButtonWasClicked(_:))
        lockButton.title = L("Enter admin mode")
        lockButton.image = NSImage(systemSymbolName: "lock", accessibilityDescription: nil)
        lockSymbolName = "lock"
        lockButton.sizeToFit()
    }

    @objc private func lockButtonWasClicked(_ sender: Any?) {
        TBSwiftUIBridge.toggleAdminMode()
        LegacyRefresh.shared.bump()
        updateLockButton()
    }

    private func updateLockButton() {
        let isOn = TBSwiftUIBridge.adminModeIsOn()
        let label = TBSwiftUIBridge.adminModeLabel()
        let symbol = isOn ? "lock.open" : "lock"
        if lockButton.title != label {
            lockButton.title = label
            lockButton.sizeToFit()
        }
        if lockSymbolName != symbol {
            lockSymbolName = symbol
            lockButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        lockButton.isEnabled = TBSwiftUIBridge.adminModeToggleIsEnabled()
        lockButton.toolTip = isOn
            ? L("Tunnelblick will not ask for an administrator password again until admin mode ends")
            : L("Authorize once for changes that need an administrator password")
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, Self.lockItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, Self.lockItemIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.lockItemIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = lockButton
        item.label = L("Enter admin mode")
        item.paletteLabel = L("Enter admin mode")
        return item
    }
}
