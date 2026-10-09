//
//  LogTabView.swift
//  Tunnelblick
//
//  The Log tab. The original log code (LogDisplay) writes into the NSTextStorage of the hidden legacy log view; this
//  tab shows that same storage in its own NSTextView by adding a second NSLayoutManager to it, so nothing about how
//  the log is produced changes.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct LogTabView: View {
    let displayName: String

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared
    @ObservedObject private var navigation = DetailsNavigation.shared

    // Explicit: the private stored properties would make the synthesized memberwise initializer private.
    init(displayName: String) {
        self.displayName = displayName
    }

    var body: some View {
        let _ = model.tick + refresh.revision
        let view = ConfigurationActions.legacyConfigurationsView()
        let isLoading = !(view?.logDisplayProgressIndicator()?.isHidden ?? true)
        let showLogItem = view?.showOpenvpnLogMenuItem()
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text(verbatim: L("Loading the log…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let showLogItem, !showLogItem.isHidden {
                    Button {
                        _ = TBSwiftUIBridge.perform(showLogItem)
                    } label: {
                        Label {
                            Text(verbatim: showLogItem.title)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                    .disabled(!TBSwiftUIBridge.isEnabled(showLogItem))
                }
                DiagnosticInfoButton()
            }
            .controlSize(.small)

            SharedLogTextView(focusText: navigation.logFocusText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                )
                .accessibilityLabel(Text(verbatim: L("Log")))
        }
    }
}

/// A read-only NSTextView that displays the legacy log NSTextStorage.
struct SharedLogTextView: NSViewRepresentable {

    /// When set, the text is searched for, selected and scrolled to (then DetailsNavigation's focus is cleared).
    var focusText: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let contentSize = scrollView.contentSize
        let container = NSTextContainer(size: NSSize(width: max(contentSize.width, 100), height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.addTextContainer(container)

        // Attach to the shared storage before creating the text view so it never creates a storage of its own.
        let storage = TBSwiftUIBridge.logTextStorage() ?? NSTextStorage()
        storage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.setAccessibilityLabel(L("Log"))

        scrollView.documentView = textView

        context.coordinator.attach(storage: storage, layoutManager: layoutManager, textView: textView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let focusText, !focusText.isEmpty {
            context.coordinator.reveal(focusText)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {

        private var storage: NSTextStorage?
        private var layoutManager: NSLayoutManager?
        private weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?
        private let fontApplier = LogFontApplier()
        private var installedFontApplier = false
        private var observers: [NSObjectProtocol] = []
        private var followsTail = true
        private var scrollIsScheduled = false
        private var revealingText: String?

        func attach(storage: NSTextStorage, layoutManager: NSLayoutManager, textView: NSTextView, scrollView: NSScrollView) {
            self.storage = storage
            self.layoutManager = layoutManager
            self.textView = textView
            self.scrollView = scrollView

            // Monospaced 11 pt. The legacy code adds lines without a font attribute; give them one as they arrive.
            if storage.delegate == nil {
                storage.delegate = fontApplier
                installedFontApplier = true
            }
            fontApplier.applyFont(to: storage)

            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                object: storage,
                                                queue: .main) { [weak self] _ in
                Task { @MainActor in self?.textDidChange() }
            })

            scrollView.contentView.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
                                                object: scrollView.contentView,
                                                queue: .main) { [weak self] _ in
                Task { @MainActor in self?.boundsDidChange() }
            })

            scheduleScrollToEnd()
        }

        func detach() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers = []
            if let storage, let layoutManager {
                storage.removeLayoutManager(layoutManager)
            }
            if installedFontApplier, let storage, storage.delegate === fontApplier {
                storage.delegate = nil
            }
            installedFontApplier = false
            storage = nil
            layoutManager = nil
        }

        // MARK: Autoscroll

        private func textDidChange() {
            guard revealingText == nil, followsTail else { return }
            scheduleScrollToEnd()
        }

        private func scheduleScrollToEnd() {
            guard !scrollIsScheduled else { return }
            scrollIsScheduled = true
            Task { @MainActor in
                self.scrollIsScheduled = false
                self.scrollToEnd()
            }
        }

        private func scrollToEnd() {
            guard let textView, let storage else { return }
            textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
            followsTail = true
        }

        /// The view follows new text while the user is at (or near) the bottom.
        private func boundsDidChange() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let visible = scrollView.contentView.bounds
            followsTail = documentView.frame.height - visible.maxY < 40
        }

        // MARK: Reveal a line

        func reveal(_ text: String) {
            guard revealingText != text else { return }
            revealingText = text
            Task { @MainActor in
                await self.performReveal(text)
            }
        }

        private func performReveal(_ text: String) async {
            // The log may still be loading; look for the line a few times.
            for attempt in 0..<8 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                guard let storage, let textView else { break }
                let range = (storage.string as NSString).range(of: text, options: .backwards)
                if range.location != NSNotFound {
                    followsTail = false
                    textView.setSelectedRange(range)
                    textView.scrollRangeToVisible(range)
                    textView.showFindIndicator(for: range)
                    break
                }
            }
            revealingText = nil
            DetailsNavigation.shared.clearLogFocus()
        }
    }
}

/// Gives the log text a monospaced font as the legacy code inserts it. Attribute changes are allowed in
/// textStorage(_:willProcessEditing:range:changeInLength:) (before fixAttributes and layout); characters are not changed.
final class LogFontApplier: NSObject, NSTextStorageDelegate {

    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    func applyFont(to storage: NSTextStorage) {
        let length = storage.length
        guard length > 0 else { return }
        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: length))
        storage.endEditing()
    }

    func textStorage(_ textStorage: NSTextStorage,
                     willProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters),
              editedRange.location != NSNotFound,
              editedRange.length > 0,
              NSMaxRange(editedRange) <= textStorage.length else {
            return
        }
        textStorage.addAttribute(.font, value: font, range: editedRange)
    }
}
