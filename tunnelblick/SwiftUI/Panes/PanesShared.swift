//
//  PanesShared.swift
//  Tunnelblick
//
//  Building blocks shared by the SwiftUI panes (Settings tab, Advanced sheet, Appearance, Preferences, Utilities, Info):
//  access to legacy outlets that have no accessor, the legacy "info" help text attached to TBButton/TBPopUpButton,
//  section headers with a help popover, the page layout, a compact pop-up menu and a read-only rich text view.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import ObjectiveC
import SwiftUI

// MARK: - Legacy outlets and texts

@MainActor
enum PanesLegacy {

    /// Returns an outlet (instance variable) or getter of a legacy object by name, using Key-Value Coding.
    /// Returns nil (instead of raising NSUndefinedKeyException) if the object has neither an instance variable nor a
    /// getter with that name, or if the value is not of the expected type.
    static func outlet<T>(_ object: AnyObject?, _ name: String) -> T? {
        guard let object = object as? NSObject else {
            return nil
        }
        let hasIvar = class_getInstanceVariable(type(of: object), name) != nil
        guard hasIvar || object.responds(to: NSSelectorFromString(name)) else {
            return nil
        }
        return object.value(forKey: name) as? T
    }

    /// Removes a trailing colon (and extra spaces) from a legacy label such as "Connect:".
    static func stripColon(_ text: String) -> String {
        var result = LegacyCheckboxState.clean(text)
        while let last = result.last, last == ":" || last == "：" {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// The text of a legacy label cell without its trailing colon, or the fallback (also without colon).
    static func label(_ cell: NSTextFieldCell?, fallback: String) -> String {
        let text = stripColon(cell?.title ?? "")
        return text.isEmpty ? stripColon(fallback) : text
    }

    /// The text of a legacy text field (e.g. a column header), or the fallback.
    static func text(_ field: NSTextField?, fallback: String) -> String {
        let text = stripColon(field?.stringValue ?? "")
        return text.isEmpty ? stripColon(fallback) : text
    }

    /// "(if connected when user switched out)" -> "if connected when user switched out"
    static func withoutParentheses(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let trimmed = LegacyCheckboxState.clean(text).trimmingCharacters(in: CharacterSet(charactersIn: "()（）"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The title of a legacy button, tidied, or nil if it has none.
    static func title(_ button: NSButton?) -> String? {
        guard let button else {
            return nil
        }
        let title = LegacyCheckboxState.clean(button.title)
        return title.isEmpty ? nil : title
    }

    /// The help ("info") text that the original code attached to a TBButton or TBPopUpButton
    /// (-[TBButton setTitle:infoTitle:] stores it in the "titleAS" instance variable). Nil for other controls.
    static func info(_ control: AnyObject?) -> NSAttributedString? {
        guard let attached: NSAttributedString = outlet(control, "titleAS"),
              attached.length > 0 else {
            return nil
        }
        return attached
    }

    /// The first paragraph of a control's help text, as plain text (used as a short description).
    static func summary(_ control: AnyObject?) -> String? {
        guard let helpText = PanesLegacy.info(control) else {
            return nil
        }
        let paragraphs = helpText.string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paragraphs.first
    }

    /// Converts the legacy help text (HTML converted to an attributed string) to an AttributedString that SwiftUI's Text
    /// can show, keeping bold text and links. Colors and fonts are left to SwiftUI so it works in light and dark mode.
    static func richText(_ source: NSAttributedString) -> AttributedString {
        var result = AttributedString()
        let string = source.string as NSString
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length), options: []) { attributes, range, _ in
            var piece = AttributedString(string.substring(with: range))
            if let font = attributes[.font] as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.bold) {
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            if let url = attributes[.link] as? URL {
                piece.link = url
            } else if let link = attributes[.link] as? String,
                      let url = URL(string: link) {
                piece.link = url
            }
            result.append(piece)
        }
        return result
    }

    /// Help items for a section, from the controls in it (controls without help text are skipped).
    static func help(_ sources: [PanesHelpSource]) -> [PanesHelpItem] {
        var items: [PanesHelpItem] = []
        for source in sources {
            guard let helpText = PanesLegacy.info(source.control) else {
                continue
            }
            let itemTitle = source.title ?? PanesLegacy.title(source.control as? NSButton)
            items.append(PanesHelpItem(id: items.count,
                                       title: itemTitle.map { PanesLegacy.stripColon($0) },
                                       text: PanesLegacy.richText(helpText),
                                       length: helpText.length))
        }
        return items
    }

    /// Writes a program preference through -[TBUserDefaults setObject:forKey:] (forced preferences are respected).
    static func setPreference(_ value: Any, forKey key: String) {
        guard let defaults = gTbDefaults else {
            return
        }
        _ = defaults.perform(NSSelectorFromString("setObject:forKey:"), with: value, with: key)
    }
}

/// A control whose legacy help text should appear in a section's help popover.
struct PanesHelpSource {
    let title: String?
    let control: NSObject?

    init(_ title: String?, _ control: NSObject?) {
        self.title = title
        self.control = control
    }
}

struct PanesHelpItem: Identifiable {
    let id: Int
    let title: String?
    let text: AttributedString
    let length: Int
}

// MARK: - Section header with help

/// The "?" button next to a section header. Shows the legacy help text of the section's controls in a popover.
struct PanesHelpButton: View {
    let items: [PanesHelpItem]

    @State private var isShown = false

    init(items: [PanesHelpItem]) {
        self.items = items
    }

    private var estimatedHeight: CGFloat {
        let characters = items.reduce(0) { $0 + $1.length + 60 }
        let height = CGFloat(characters) / 52.0 * 16.0 + CGFloat(items.count) * 14.0 + 30.0
        return min(460, max(80, height))
    }

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(L("Help"))
        .accessibilityLabel(Text(verbatim: L("Help")))
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            if items.count > 1, let title = item.title {
                                Text(verbatim: title)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(item.text)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(14)
                .frame(width: 380, alignment: .leading)
            }
            .frame(width: 380, height: estimatedHeight)
        }
    }
}

struct PanesSectionHeader: View {
    let title: String?
    let subtitle: String?
    let help: [PanesHelpItem]

    init(title: String?, subtitle: String? = nil, help: [PanesHelpItem] = []) {
        self.title = title
        self.subtitle = subtitle
        self.help = help
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let title {
                Text(verbatim: title)
                    .font(Theme.sectionHead)
                    .foregroundStyle(.secondary)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(Theme.rowCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if !help.isEmpty {
                PanesHelpButton(items: help)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// An InsetSection with a header that can have a subtitle and a help button.
struct PanesSection<Content: View>: View {
    let title: String?
    let subtitle: String?
    let help: [PanesHelpItem]
    let footer: String?
    let content: () -> Content

    init(_ title: String?,
         subtitle: String? = nil,
         help: [PanesHelpItem] = [],
         footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.help = help
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if title != nil || !help.isEmpty {
                PanesSectionHeader(title: title, subtitle: subtitle, help: help)
            }
            InsetSection(nil, footer: footer, content: content)
        }
    }
}

// MARK: - Page layout

/// A pane: title and one-line description at the top, then sections, in a scroll view with a readable width.
struct PanesPage<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: () -> Content

    init(title: String, subtitle: String?, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(Theme.paneTitle)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .tbLayoutDirection()
    }
}

// MARK: - Compact pop-up (for grids)

/// A pop-up menu that mirrors a legacy pop-up button, without a row around it (LegacyPopUpRow is the row version).
struct PanesPopUpMenu: View {
    let popUp: NSPopUpButton?

    @ObservedObject private var refresh = LegacyRefresh.shared
    @ObservedObject private var model = AppModel.shared

    init(popUp: NSPopUpButton?) {
        self.popUp = popUp
    }

    var body: some View {
        if let popUp {
            let state = LegacyPopUpState(popUp)
            let _ = refresh.revision &+ model.tick
            if !state.isHidden {
                Menu {
                    ForEach(Array(state.titles.enumerated()), id: \.offset) { index, itemTitle in
                        if !state.itemIsHidden[index] {
                            Button {
                                guard index != state.selectedIndex else { return }
                                TBSwiftUIBridge.choose(popUp, index: index)
                                LegacyRefresh.shared.bump()
                            } label: {
                                if index == state.selectedIndex {
                                    Label(itemTitle, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: itemTitle)
                                }
                            }
                            .disabled(!state.itemIsEnabled[index])
                        }
                    }
                } label: {
                    Text(verbatim: state.selectedTitle)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!state.isEnabled)
                .opacity(state.isEnabled ? 1 : 0.6)
            }
        }
    }
}

// MARK: - Read-only rich text

/// Shows an attributed string (with working links) in a scrollable, selectable, read-only text view.
struct PanesAttributedTextView: NSViewRepresentable {
    let text: NSAttributedString

    init(text: NSAttributedString) {
        self.text = text
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textStorage?.setAttributedString(text)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              let storage = textView.textStorage else {
            return
        }
        if !storage.isEqual(to: text) {
            storage.setAttributedString(text)
        }
    }

    /// A copy of a legacy attributed string with colors that work in light and dark mode
    /// (the legacy code converts to RTF, which stores fixed colors).
    static func adaptiveCopy(of source: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: source)
        let all = NSRange(location: 0, length: copy.length)
        copy.removeAttribute(.backgroundColor, range: all)
        copy.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
        return copy
    }
}
