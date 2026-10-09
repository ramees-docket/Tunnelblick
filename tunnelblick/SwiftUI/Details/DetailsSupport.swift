//
//  DetailsSupport.swift
//  Tunnelblick
//
//  Helpers for the VPN Details window:
//    * ConfigurationActions: +, −, the actions (⋯) menu, Import…, drop to install, help, diagnostic info.
//      Everything goes through the hidden legacy controls so the original rules and code apply.
//    * ConfigurationInfoCache: what each configuration file says (server, protocol, port), read at most every 30 s.
//    * ConnectDurationTracker: how long the last connection attempt took ("Connected in 3.1 s").
//    * TunnelInterfaces / OpenVPNLogReader: the VPN address and pushed DNS servers.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Actions

@MainActor
enum ConfigurationActions {

    /// The hidden legacy configurations pane (its controls are what the SwiftUI views mirror and click).
    static func legacyConfigurationsView() -> ConfigurationsView? {
        TBSwiftUIBridge.legacyDetails()?.configurationsPrefsView()
    }

    /// "+": the original "Add a Configuration" guide.
    static func addConfiguration() {
        guard let button = legacyConfigurationsView()?.addConfigurationButton() else { return }
        TBSwiftUIBridge.click(button)
        LegacyRefresh.shared.bump()
    }

    /// "−": the original remove button (it confirms and asks for authorization when needed).
    static func removeSelectedConfiguration() {
        guard let button = legacyConfigurationsView()?.removeConfigurationButton() else { return }
        TBSwiftUIBridge.click(button)
        LegacyRefresh.shared.bump()
    }

    static var removeIsEnabled: Bool {
        guard let button = legacyConfigurationsView()?.removeConfigurationButton() else { return false }
        return button.isEnabled && !button.isHidden
    }

    /// The "?" button of the configurations pane (opens the VPN Details help page).
    static func showHelp() {
        guard let button = legacyConfigurationsView()?.configurationsHelpButton() else { return }
        TBSwiftUIBridge.click(button)
    }

    /// Asks for .ovpn, .conf or .tblk files and installs them the way a double-click in Finder does.
    static func importConfigurationFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true           // A .tblk is a folder when it is not registered as a package
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = ["ovpn", "conf", "tblk"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = L("Import")
        panel.message = L("Choose OpenVPN configuration files (.ovpn or .conf) or Tunnelblick VPN Configurations (.tblk).")

        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.filter(isInstallable).map { $0.path }
        if paths.isEmpty {
            NSSound.beep()
            return
        }
        open(paths: paths)
    }

    static func isInstallable(_ url: URL) -> Bool {
        ["ovpn", "conf", "tblk"].contains(url.pathExtension.lowercased())
    }

    /// Installs configuration files (same as dropping them on the original VPN Details window).
    static func open(paths: [String]) {
        // Like DropConfigsView: let the drag (or the open panel) finish before the installer shows its dialogs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task { @MainActor in
                _ = gMC?.openFiles(paths)
            }
        }
    }

    /// Handles files dropped on the window. Returns false if nothing droppable was offered.
    static func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let batch = DropBatch(expected: fileProviders.count)
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    batch.add(url)
                }
            }
        }
        return true
    }

    /// Copy Diagnostic Info to Clipboard (the legacy button reads the log of the selected configuration).
    static func copyDiagnosticInfo() {
        guard let button = legacyConfigurationsView()?.diagnosticInfoToClipboardButton() else { return }
        TBSwiftUIBridge.click(button)
        LegacyRefresh.shared.bump()
    }

    // MARK: The actions (⋯) menu

    /// Shows the actions menu (built from the legacy gear menu) at the mouse location. The selected configuration in
    /// the hidden list is the one the items act on.
    static func showActionsMenu() {
        let menu = actionsMenu()
        guard !menu.items.isEmpty else {
            NSSound.beep()
            return
        }
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    static func actionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let view = legacyConfigurationsView() else { return menu }

        // Same order and separators as the original gear menu (Preferences.xib)
        let groups: [[NSMenuItem?]] = [
            [view.renameConfigurationMenuItem(),
             view.duplicateConfigurationMenuItem(),
             view.makePrivateMenuItem(),
             view.makeSharedMenuItem(),
             view.revertToShadowMenuItem()],
            [view.c_o_p_yConfigurationsIntoNewFolderMenuItem(),
             view.moveConfigurationsIntoNewFolderMenuItem()],
            [view.showOnTbMenuMenuItem(),
             view.doNotShowOnTbMenuMenuItem()],
            [view.editOpenVPNConfigurationFileMenuItem(),
             view.showOpenvpnLogMenuItem()],
            [view.removeCredentialsMenuItem()],
        ]

        let target = LegacyMenuTarget.shared
        for group in groups {
            let visible = group.compactMap { $0 }.filter { !$0.isHidden && !$0.isSeparatorItem }
            if visible.isEmpty {
                continue
            }
            if !menu.items.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            for legacyItem in visible {
                let item = NSMenuItem(title: legacyItem.title,
                                      action: #selector(LegacyMenuTarget.performLegacyItem(_:)),
                                      keyEquivalent: "")
                item.target = target
                item.representedObject = legacyItem
                item.isEnabled = TBSwiftUIBridge.isEnabled(legacyItem)
                menu.addItem(item)
            }
        }
        return menu
    }

    /// Performs a legacy menu item. "Rename" is handled here because the original starts an in-place edit in the
    /// hidden list; the rename itself uses the same validation and ConfigurationManager call as the original.
    static func performLegacyItem(_ legacyItem: NSMenuItem) {
        if let view = legacyConfigurationsView(), legacyItem === view.renameConfigurationMenuItem() {
            if TBSwiftUIBridge.isEnabled(legacyItem) {
                renameSelectedConfiguration()
            }
        } else {
            _ = TBSwiftUIBridge.perform(legacyItem)
        }
        LegacyRefresh.shared.bump()
        AppModel.shared.refreshConnections()
    }

    /// Same as committing an in-place rename in the original list (-[LeftNavDataSource outlineView:setObjectValue:...]).
    static func renameSelectedConfiguration() {
        guard let displayName = AppModel.shared.selectedDisplayName,
              let connection = AppModel.shared.connection(for: displayName),
              let sourcePath = connection.configPath() else {
            return
        }

        let oldName = (displayName as NSString).lastPathComponent

        let field = NSTextField(string: oldName)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.lineBreakMode = .byTruncatingMiddle

        let alert = NSAlert()
        alert.messageText = L("Rename Configuration")
        alert.informativeText = LF("Enter a new name for \"%@\":", connection.localizedName() ?? oldName)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != oldName else { return }

        if newName.hasSuffix(".tblk") {
            let warning = NSAlert()
            warning.messageText = L("Tunnelblick")
            warning.informativeText = L("A folder name cannot end in '.tblk'")
            _ = warning.runModal()
            return
        }

        guard displayNameIsValid(newName, true) else { return }   // Shows its own alert

        let targetPath = (((sourcePath as NSString).deletingLastPathComponent as NSString)
                          .appendingPathComponent(newName) as NSString)
                          .appendingPathExtension("tblk") ?? ""
        guard !targetPath.isEmpty else { return }

        _ = (ConfigurationManager.self as AnyObject).perform(NSSelectorFromString("renameConfigurationInNewThreadAtPath:toPath:"),
                                                             with: sourcePath,
                                                             with: targetPath)
    }
}

/// Target of the actions menu items built from the legacy menu.
@MainActor
final class LegacyMenuTarget: NSObject {
    static let shared = LegacyMenuTarget()

    @objc func performLegacyItem(_ sender: NSMenuItem) {
        guard let legacyItem = sender.representedObject as? NSMenuItem else { return }
        ConfigurationActions.performLegacyItem(legacyItem)
    }
}

/// Collects the URLs of a drop (they load asynchronously) and installs them together.
@MainActor
final class DropBatch {
    private var remaining: Int
    private var paths: [String] = []

    init(expected: Int) {
        remaining = expected
    }

    func add(_ url: URL?) {
        if let url, ConfigurationActions.isInstallable(url) {
            paths.append(url.path)
        }
        remaining -= 1
        guard remaining == 0 else { return }
        if paths.isEmpty {
            NSSound.beep()
        } else {
            ConfigurationActions.open(paths: paths)
        }
    }
}

// MARK: - What the configuration files say

@MainActor
final class ConfigurationInfoCache {

    struct Entry {
        let info: ConfigurationFileInfo
        let path: String?
        let fileExtension: String?      // "ovpn", "conf" or "tblk"
        let loaded: Date

        /// The file could be read (shared configurations can be readable only by root).
        var isReadable: Bool { info.fileName != nil }

        /// "UDP 1194 · .ovpn"
        var caption: String? {
            var parts: [String] = []
            if isReadable {
                parts.append(info.protocolAndPort)
            }
            if let fileExtension {
                parts.append("." + fileExtension)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        /// "Office.tblk"
        var fileName: String? {
            path.map { ($0 as NSString).lastPathComponent }
        }
    }

    static let shared = ConfigurationInfoCache()

    private var entries: [String: Entry] = [:]

    private init() {}

    func entry(for displayName: String, maxAge: TimeInterval = 30) -> Entry {
        let path = AppModel.shared.configurationPath(for: displayName)
        let key = displayName + "\u{0}" + (path ?? "")
        if let existing = entries[key], Date().timeIntervalSince(existing.loaded) < maxAge {
            return existing
        }
        let info = path.map { ConfigurationFileInfo.read(configurationPath: $0) } ?? ConfigurationFileInfo()
        let entry = Entry(info: info,
                          path: path,
                          fileExtension: path.flatMap(Self.configurationFileExtension(path:)),
                          loaded: Date())
        entries[key] = entry
        return entry
    }

    /// The extension of the OpenVPN configuration file inside a .tblk ("ovpn" or "conf"), else of the path itself.
    private static func configurationFileExtension(path: String) -> String? {
        if path.hasSuffix(".tblk") {
            let resources = (path as NSString).appendingPathComponent("Contents/Resources")
            if let names = try? FileManager.default.contentsOfDirectory(atPath: resources) {
                if names.contains("config.ovpn") {
                    return "ovpn"
                }
                if let name = names.sorted().first(where: { $0.hasSuffix(".ovpn") || $0.hasSuffix(".conf") }) {
                    return (name as NSString).pathExtension
                }
            }
            return "tblk"
        }
        let pathExtension = (path as NSString).pathExtension
        return pathExtension.isEmpty ? nil : pathExtension
    }
}

// MARK: - Connect duration

/// Measures how long each connection attempt takes, from the first non-disconnected state to CONNECTED.
@MainActor
final class ConnectDurationTracker: ObservableObject {

    static let shared = ConnectDurationTracker()

    @Published private(set) var durations: [String: TimeInterval] = [:]

    private var startedAt: [String: Date] = [:]
    private var lastStatus: [String: ConnectionSnapshot.Status] = [:]

    private init() {}

    func update(_ snapshots: [String: ConnectionSnapshot]) {
        let now = Date()
        var newDurations = durations

        for (displayName, snapshot) in snapshots {
            let previous = lastStatus[displayName]
            lastStatus[displayName] = snapshot.status

            switch snapshot.status {
            case .connecting, .waitingForCredentials:
                // A new attempt starts when we saw it disconnected (or connected, for a reconnect) just before.
                if let previous, startedAt[displayName] == nil {
                    switch previous {
                    case .disconnected, .authFailed, .connected:
                        startedAt[displayName] = now
                        newDurations[displayName] = nil
                    default:
                        break
                    }
                }
            case .connected:
                if let start = startedAt[displayName] {
                    newDurations[displayName] = now.timeIntervalSince(start)
                    startedAt[displayName] = nil
                }
            case .disconnected, .authFailed, .disconnecting:
                startedAt[displayName] = nil
                if snapshot.status != .disconnecting {
                    newDurations[displayName] = nil
                }
            }
        }

        if newDurations != durations {
            durations = newDurations
        }
    }
}

// MARK: - VPN address and DNS servers

enum TunnelInterfaces {

    /// IPv4 addresses of tunnel interfaces (utun, tun, tap).
    static func ipv4Addresses() -> [String] {
        var result: [String] = []
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let entry = current.pointee
            let name = String(cString: entry.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("tun") || name.hasPrefix("tap"),
               let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: host)
                    if !result.contains(address) {
                        result.append(address)
                    }
                }
            }
            pointer = entry.ifa_next
        }
        return result
    }
}

enum OpenVPNLogReader {

    /// The beginning of a log file (the PUSH_REPLY with the VPN address and DNS servers is near the start).
    static func head(ofFileAtPath path: String, maxBytes: Int = 512 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
