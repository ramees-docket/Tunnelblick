//
//  LegacyControls.swift
//  Tunnelblick
//
//  SwiftUI controls that mirror the hidden legacy AppKit controls (see TBSwiftUIBridge.h for the design).
//
//  Each control reads the legacy control's title, state, enabled and hidden flags when the view renders, and changes it
//  the same way a user click would. All the original rules (locked/forced preferences, admin authorization, validation,
//  dependent controls) therefore still apply. Views that show legacy controls should observe AppModel.shared (its `tick`
//  re-renders them every second) or call `LegacyRefresh.shared.bump()` after an action.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

/// Re-renders views that mirror legacy controls. Call bump() after anything that may change legacy control state.
@MainActor
final class LegacyRefresh: ObservableObject {
    static let shared = LegacyRefresh()
    @Published private(set) var revision = 0

    func bump() {
        revision &+= 1
        // Some legacy actions finish asynchronously (admin authorization, operations queue); look again shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            Task { @MainActor in self?.revision &+= 1 }
        }
    }
}

// MARK: - Plain values read from AppKit controls

struct LegacyCheckboxState {
    let title: String
    let isOn: Bool
    let isEnabled: Bool
    let isHidden: Bool

    init(_ button: NSButton) {
        title     = Self.clean(button.title)
        isOn      = button.state == .on
        isEnabled = button.isEnabled
        isHidden  = button.isHidden || button.superview == nil
    }

    /// Legacy titles sometimes end with a colon or have doubled spaces for layout; tidy them for SwiftUI rows.
    static func clean(_ title: String) -> String {
        title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LegacyPopUpState {
    let titles: [String]
    let selectedIndex: Int
    let isEnabled: Bool
    let isHidden: Bool
    let itemIsEnabled: [Bool]
    let itemIsHidden: [Bool]

    init(_ popUp: NSPopUpButton) {
        let items = popUp.itemArray
        titles        = items.map { LegacyCheckboxState.clean($0.title) }
        selectedIndex = popUp.indexOfSelectedItem
        isEnabled     = popUp.isEnabled
        isHidden      = popUp.isHidden || popUp.superview == nil
        itemIsEnabled = items.map { TBSwiftUIBridge.isEnabled($0) }
        itemIsHidden  = items.map { $0.isHidden || $0.isSeparatorItem }
    }

    var selectedTitle: String {
        titles.indices.contains(selectedIndex) ? titles[selectedIndex] : ""
    }
}

// MARK: - SwiftUI controls

/// A toggle row that mirrors a legacy checkbox. Hidden when the legacy checkbox is hidden.
struct LegacyToggleRow: View {
    let button: NSButton?
    var title: String? = nil          // Overrides the legacy title (use the same English key so it stays localized)
    var caption: String? = nil
    var isLast: Bool = false
    var onChange: (() -> Void)? = nil

    @ObservedObject private var refresh = LegacyRefresh.shared
    @ObservedObject private var model = AppModel.shared

    // Explicit: the private stored properties would make the synthesized memberwise initializer private.
    init(button: NSButton?, title: String? = nil, caption: String? = nil, isLast: Bool = false,
         onChange: (() -> Void)? = nil) {
        self.button = button
        self.title = title
        self.caption = caption
        self.isLast = isLast
        self.onChange = onChange
    }

    var body: some View {
        if let button {
            let state = LegacyCheckboxState(button)
            let _ = refresh.revision + model.tick   // Re-render when these change
            if !state.isHidden {
                InsetRow(title ?? state.title, caption: caption, isLast: isLast) {
                    HStack(spacing: 6) {
                        if !state.isEnabled {
                            LockedBadge()
                        }
                        Toggle("", isOn: Binding(
                            get: { state.isOn },
                            set: { newValue in
                                guard newValue != state.isOn else { return }
                                TBSwiftUIBridge.click(button)
                                LegacyRefresh.shared.bump()
                                onChange?()
                            }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!state.isEnabled)
                    }
                }
                .opacity(state.isEnabled ? 1 : 0.6)
            }
        }
    }
}

/// A pop-up row that mirrors a legacy pop-up button.
struct LegacyPopUpRow: View {
    let title: String
    let popUp: NSPopUpButton?
    var caption: String? = nil
    var isLast: Bool = false
    var onChange: (() -> Void)? = nil

    @ObservedObject private var refresh = LegacyRefresh.shared
    @ObservedObject private var model = AppModel.shared

    init(title: String, popUp: NSPopUpButton?, caption: String? = nil, isLast: Bool = false,
         onChange: (() -> Void)? = nil) {
        self.title = title
        self.popUp = popUp
        self.caption = caption
        self.isLast = isLast
        self.onChange = onChange
    }

    var body: some View {
        if let popUp {
            let state = LegacyPopUpState(popUp)
            let _ = refresh.revision + model.tick
            if !state.isHidden {
                InsetRow(title, caption: caption, isLast: isLast) {
                    HStack(spacing: 6) {
                        if !state.isEnabled {
                            LockedBadge()
                        }
                        Menu {
                            ForEach(Array(state.titles.enumerated()), id: \.offset) { index, itemTitle in
                                if !state.itemIsHidden[index] {
                                    Button {
                                        guard index != state.selectedIndex else { return }
                                        TBSwiftUIBridge.choose(popUp, index: index)
                                        LegacyRefresh.shared.bump()
                                        onChange?()
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
                    }
                }
                .opacity(state.isEnabled ? 1 : 0.6)
            }
        }
    }
}

/// A push button that clicks a legacy button (e.g. "Check Now", "Quit All OpenVPN Processes").
struct LegacyButton: View {
    let button: NSButton?
    var title: String? = nil
    var role: ButtonRole? = nil
    var onClick: (() -> Void)? = nil

    @ObservedObject private var refresh = LegacyRefresh.shared
    @ObservedObject private var model = AppModel.shared

    init(button: NSButton?, title: String? = nil, role: ButtonRole? = nil, onClick: (() -> Void)? = nil) {
        self.button = button
        self.title = title
        self.role = role
        self.onClick = onClick
    }

    var body: some View {
        if let button {
            let state = LegacyCheckboxState(button)
            let _ = refresh.revision + model.tick
            if !state.isHidden {
                Button(role: role) {
                    TBSwiftUIBridge.click(button)
                    LegacyRefresh.shared.bump()
                    onClick?()
                } label: {
                    Text(verbatim: title ?? state.title)
                }
                .disabled(!state.isEnabled)
            }
        }
    }
}

/// Shown next to a control that is locked (forced by a computer administrator, or needs admin mode).
struct LockedBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .help(L("Enter admin mode to change"))
            .accessibilityLabel(Text(verbatim: L("Locked")))
    }
}
