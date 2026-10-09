//
//  DetailsNavigation.swift
//  Tunnelblick
//
//  What the VPN Details window shows: the selected configuration or Tunnelblick pane, the configuration tab
//  (Overview / Log / Settings), the sidebar search text and collapsed folders. Selecting something here also makes the
//  hidden legacy controller show the same thing, so the original logic (log monitoring, per-configuration controls,
//  pane setup code) runs exactly as it did with the original window.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

/// The Tunnelblick panes listed under the configurations.
enum DetailsPane: String, CaseIterable, Identifiable, Hashable {
    case appearance  = "Appearance"     // The raw values are the English pane names TBSwiftUIBridge.showLegacyPane expects
    case preferences = "Preferences"
    case utilities   = "Utilities"
    case info        = "Info"

    var id: String { rawValue }

    /// Localized title (the keys exist in Localizable.strings).
    var title: String { L(rawValue) }

    var symbolName: String {
        switch self {
        case .appearance:  return "circle.lefthalf.filled"
        case .preferences: return "gearshape"
        case .utilities:   return "wrench.and.screwdriver"
        case .info:        return "info.circle"
        }
    }

    /// Extra words the sidebar search matches (English, in addition to the localized title).
    var searchWords: String {
        switch self {
        case .appearance:  return "icon menu bar timer status window screen indicator startup monochrome"
        case .preferences: return "updates beta keyboard shortcut log size admin warnings internet"
        case .utilities:   return "quit openvpn console log export easy-rsa uninstall"
        case .info:        return "version openvpn license credits copyright donate about"
        }
    }
}

/// What is selected in the sidebar.
enum DetailsSelection: Hashable {
    case configuration(String)      // Display name
    case pane(DetailsPane)

    var displayName: String? {
        if case .configuration(let displayName) = self {
            return displayName
        }
        return nil
    }
}

/// The tabs of a configuration.
enum ConfigurationTab: Int, CaseIterable, Identifiable, Hashable {
    case overview, log, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Overview")
        case .log:      return L("Log")
        case .settings: return L("Settings")
        }
    }
}

@MainActor
final class DetailsNavigation: ObservableObject {

    static let shared = DetailsNavigation()

    @Published private(set) var selection: DetailsSelection?
    @Published private(set) var tab: ConfigurationTab = .overview
    @Published var searchText = ""
    @Published var collapsedFolders: Set<String> = []     // Folder ids ("Work/") the user collapsed

    /// Text of a log line the Log tab should scroll to and select (set by "Show warning lines in the log").
    @Published private(set) var logFocusText: String?

    /// True while the VPN Details window is on screen (animations pause while it is closed).
    @Published private(set) var windowIsVisible = false

    private init() {}

    // MARK: Selection

    func select(_ newSelection: DetailsSelection?, force: Bool = false) {
        if !force && newSelection == selection {
            return
        }
        selection = newSelection

        switch newSelection {
        case .configuration(let displayName)?:
            expandFolders(containing: displayName)
            // Show the legacy Configurations pane first, so the legacy selection change starts/stops log monitoring.
            TBSwiftUIBridge.showLegacyPane("Configurations")
            AppModel.shared.select(displayName)
            TBSwiftUIBridge.selectLogTab(tab == .log)
        case .pane(let pane)?:
            TBSwiftUIBridge.showLegacyPane(pane.rawValue)
        case nil:
            break
        }

        LegacyRefresh.shared.bump()
    }

    func setTab(_ newTab: ConfigurationTab) {
        guard newTab != tab else { return }
        let wasLog = (tab == .log)
        tab = newTab
        if selection?.displayName != nil && (wasLog || newTab == .log) {
            TBSwiftUIBridge.selectLogTab(newTab == .log)
        }
    }

    /// Switches to the Log tab and asks it to reveal a line.
    func showLog(revealing text: String?) {
        logFocusText = text
        setTab(.log)
    }

    func clearLogFocus() {
        if logFocusText != nil {
            logFocusText = nil
        }
    }

    func setWindowIsVisible(_ visible: Bool) {
        if windowIsVisible != visible {
            windowIsVisible = visible
        }
    }

    /// Keeps the selection valid after configurations were added, removed or renamed.
    func reconcile(with displayNames: [String]) {
        switch selection {
        case .pane?:
            return
        case .configuration(let displayName)?:
            if displayNames.contains(displayName) {
                return
            }
        case nil:
            if displayNames.isEmpty {
                return
            }
        }

        if let current = AppModel.shared.selectedDisplayName, displayNames.contains(current) {
            select(.configuration(current))
        } else if let first = displayNames.first {
            select(.configuration(first))
        } else {
            select(nil)
        }
    }

    private func expandFolders(containing displayName: String) {
        var components = displayName.split(separator: "/").map(String.init)
        guard components.count > 1 else { return }
        components.removeLast()
        var path = ""
        var newCollapsed = collapsedFolders
        for component in components {
            path += component + "/"
            newCollapsed.remove(path)
        }
        if newCollapsed != collapsedFolders {
            collapsedFolders = newCollapsed
        }
    }
}
