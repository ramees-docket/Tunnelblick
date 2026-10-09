//
//  AppModel.swift
//  Tunnelblick
//
//  The single source of truth for the SwiftUI interface: the configuration list (with folders), the selected
//  configuration, and a snapshot of every connection's live state, refreshed from the Objective-C objects.
//
//  Refresh triggers:
//   * TBUIConnectionStateDidChangeNotification  (every -[VPNConnection setState:])
//   * TBUIConfigurationsDidChangeNotification   (configurations added/removed/renamed)
//   * TBUIConnectionWarningsDidChangeNotification
//   * a 1-second timer (elapsed time, rates)
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Connection phases (the real OpenVPN states, in order)

enum ConnectionPhase: Int, CaseIterable, Identifiable, Comparable {
    case resolve, tcpConnect, wait, auth, getConfig, assignIP, addRoutes, connected

    var id: Int { rawValue }

    static func < (lhs: ConnectionPhase, rhs: ConnectionPhase) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The OpenVPN/Tunnelblick state string for this phase.
    var stateString: String {
        switch self {
        case .resolve:    return "RESOLVE"
        case .tcpConnect: return "TCP_CONNECT"
        case .wait:       return "WAIT"
        case .auth:       return "AUTH"
        case .getConfig:  return "GET_CONFIG"
        case .assignIP:   return "ASSIGN_IP"
        case .addRoutes:  return "ADD_ROUTES"
        case .connected:  return "CONNECTED"
        }
    }

    /// Localized name, e.g. "Resolving domain name".
    var title: String { localizedState(stateString) }

    /// The phase for a state string, or nil for states that are not part of the sequence
    /// (EXITING, SLEEP, PASSWORD_WAIT, PRIVATE_KEY_WAIT, RECONNECTING, DISCONNECTING, NETWORK_ACCESS...).
    init?(state: String) {
        switch state {
        case "RESOLVE":                      self = .resolve
        case "TCP_CONNECT", "UDP_CONNECT":   self = .tcpConnect
        case "WAIT":                         self = .wait
        case "AUTH", "PASSWORD_WAIT", "PRIVATE_KEY_WAIT": self = .auth
        case "GET_CONFIG":                   self = .getConfig
        case "ASSIGN_IP":                    self = .assignIP
        case "ADD_ROUTES":                   self = .addRoutes
        case "CONNECTED":                    self = .connected
        default:                             return nil
        }
    }

    /// The phases that apply to a configuration (TCP connections have "Making TCP connection").
    static func sequence(isTCP: Bool) -> [ConnectionPhase] {
        isTCP ? allCases : allCases.filter { $0 != .tcpConnect }
    }
}

// MARK: - Warnings recorded by VPNConnection (see TBSwiftUIBridge)

struct ConnectionWarning: Identifiable, Equatable, Hashable {
    enum Kind: String {
        case dnsKnownPublicNotRoutedThroughVpn
        case dnsPrivateNotRoutedThroughVpn
        case dnsUnknownNotRoutedThroughVpn
        case publicIpUnchanged
        case other

        var isDNS: Bool { self != .publicIpUnchanged && self != .other }
    }

    let kind: Kind
    let address: String
    let logLine: String

    var id: String { kind.rawValue + "|" + address }

    init(dictionary: [String: String]) {
        kind    = Kind(rawValue: dictionary[TBUIWarningKindKey] ?? "") ?? .other
        address = dictionary[TBUIWarningAddressKey] ?? ""
        logLine = dictionary[TBUIWarningLogLineKey] ?? ""
    }
}

// MARK: - Connection snapshot

/// Everything the views need about one configuration's connection, copied out of VPNConnection.
struct ConnectionSnapshot: Equatable {

    enum Status: Equatable {
        case disconnected
        case connecting(ConnectionPhase?)   // nil phase: waiting (daemon, network, reconnecting...)
        case waitingForCredentials          // PASSWORD_WAIT / PRIVATE_KEY_WAIT
        case connected
        case disconnecting
        case authFailed
    }

    let displayName: String
    let localizedName: String
    let state: String                 // Raw state string (e.g. "AUTH")
    let localizedStateText: String    // e.g. "Authorizing"
    let status: Status
    let phase: ConnectionPhase?
    let elapsed: String               // "00:11", "1:02:03"; empty when disconnected
    let inRate: Double
    let outRate: Double
    let inTotal: Double
    let outTotal: Double
    let warnings: [ConnectionWarning]
    let isShared: Bool                // Installed for all users
    let isDeployed: Bool
    let publicIPBefore: String?
    let publicIPAfter: String?        // Only while connected
    let canConnect: Bool
    let canDisconnect: Bool

    var isConnected: Bool { status == .connected }
    var isDisconnected: Bool { status == .disconnected || status == .authFailed }
    var isBusy: Bool {
        switch status {
        case .connecting, .waitingForCredentials, .disconnecting: return true
        default: return false
        }
    }
    var hasWarnings: Bool { isConnected && !warnings.isEmpty }

    var inRateText: String   { TBSwiftUIBridge.formatted(inRate,   rate: true)  }
    var outRateText: String  { TBSwiftUIBridge.formatted(outRate,  rate: true)  }
    var inTotalText: String  { TBSwiftUIBridge.formatted(inTotal,  rate: false) }
    var outTotalText: String { TBSwiftUIBridge.formatted(outTotal, rate: false) }

    /// The color that represents this state everywhere (sidebar dot, status window, route).
    var tint: Color {
        switch status {
        case .connected:     return hasWarnings ? Theme.warning : Theme.connected
        case .authFailed:    return Theme.failure
        case .disconnected:  return Theme.faint
        default:             return Theme.tunnel
        }
    }
}

// MARK: - Configuration list

/// A row in the configuration list: a folder or a configuration.
struct ConfigNode: Identifiable, Hashable {
    let id: String              // Full name: "Work/dev" for a configuration, "Work/" for a folder
    let name: String            // Last path component, localized for configurations
    let displayName: String?    // nil for folders
    var children: [ConfigNode]? // nil for configurations

    var isFolder: Bool { displayName == nil }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {

    static let shared = AppModel()

    /// Display names of all configurations (e.g. "Work/dev"), sorted like the original list.
    @Published private(set) var displayNames: [String] = []

    /// The configuration list as a tree (folders first level, like the original outline view).
    @Published private(set) var tree: [ConfigNode] = []

    /// The configuration selected in the VPN Details window.
    @Published private(set) var selectedDisplayName: String?

    /// Live state of every configuration, keyed by display name.
    @Published private(set) var snapshots: [String: ConnectionSnapshot] = [:]

    /// Increments every second while anything is shown; views that read legacy AppKit controls observe it to re-render.
    @Published private(set) var tick: Int = 0

    private var started = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        // Callbacks hop to the main actor with Task { @MainActor in }; they are already on the main thread.
        observers.append(center.addObserver(forName: NSNotification.Name(rawValue: "TBUIConnectionStateDidChangeNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshConnections() }
        })
        observers.append(center.addObserver(forName: NSNotification.Name(rawValue: "TBUIConfigurationsDidChangeNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshConfigurations() }
        })
        observers.append(center.addObserver(forName: NSNotification.Name(rawValue: "TBUIConnectionWarningsDidChangeNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshConnections() }
        })

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tick &+= 1
                self.refreshConnections()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refreshConfigurations()
    }

    // MARK: Configurations

    func refreshConfigurations() {
        let names = TBSwiftUIBridge.leftNavDisplayNames()
        displayNames = names.filter { !$0.hasSuffix("/") }
        tree = Self.buildTree(from: names)

        if let selected = selectedDisplayName, !displayNames.contains(selected) {
            selectedDisplayName = nil
        }
        if selectedDisplayName == nil, let current = TBSwiftUIBridge.selectedConnection()?.displayName() {
            selectedDisplayName = current
        }
        refreshConnections()
    }

    /// Builds the folder tree from names like "Work/dev" and empty folders like "Archive/".
    static func buildTree(from names: [String]) -> [ConfigNode] {

        final class Folder {
            var folders: [String: Folder] = [:]
            var folderOrder: [String] = []
            var configurations: [(name: String, displayName: String)] = []
        }

        let root = Folder()

        for full in names {
            let isEmptyFolder = full.hasSuffix("/")
            var components = full.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            let leaf = isEmptyFolder ? nil : components.removeLast()

            var folder = root
            for component in components {
                if let existing = folder.folders[component] {
                    folder = existing
                } else {
                    let new = Folder()
                    folder.folders[component] = new
                    folder.folderOrder.append(component)
                    folder = new
                }
            }
            if let leaf {
                folder.configurations.append((leaf, full))
            }
        }

        func nodes(_ folder: Folder, prefix: String) -> [ConfigNode] {
            var result: [ConfigNode] = []
            for name in folder.folderOrder.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                let path = prefix + name + "/"
                result.append(ConfigNode(id: path, name: name, displayName: nil,
                                         children: nodes(folder.folders[name]!, prefix: path)))
            }
            for configuration in folder.configurations.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                let localized = gMC?.localizedName(forDisplayName: configuration.displayName) ?? configuration.name
                let name = (localized as NSString).lastPathComponent
                result.append(ConfigNode(id: configuration.displayName, name: name, displayName: configuration.displayName, children: nil))
            }
            return result
        }

        return nodes(root, prefix: "")
    }

    func connection(for displayName: String) -> VPNConnection? {
        gMC?.connection(forDisplayName: displayName)
    }

    /// Path of the .tblk for a configuration.
    func configurationPath(for displayName: String) -> String? {
        gMC?.myConfigDictionary()?[displayName] as? String
    }

    // MARK: Selection

    func select(_ displayName: String?) {
        guard let displayName else {
            selectedDisplayName = nil
            return
        }
        TBSwiftUIBridge.selectConfiguration(displayName: displayName)
        selectedDisplayName = displayName
        refreshConnections()
    }

    // MARK: Connect / disconnect (same as the original VPN Details and status windows)

    func connect(_ displayName: String) {
        guard let connection = connection(for: displayName) else { return }
        connection.connect(self, userKnows: true)
        refreshConnections()
    }

    func disconnect(_ displayName: String) {
        guard let connection = connection(for: displayName) else { return }
        connection.perform(NSSelectorFromString("addToLog:"), with: "Disconnecting; VPN Details… window disconnect button pressed")
        let oldRequestedState = connection.requestedState()
        connection.performSelector(onMainThread: NSSelectorFromString("startDisconnectingUserKnows:"),
                                   with: NSNumber(value: true),
                                   waitUntilDone: false)
        if oldRequestedState == "EXITING" {
            connection.displaySlowDisconnectionDialogLater()
        }
        refreshConnections()
    }

    /// Disconnects (if needed) and connects again, e.g. after changing a setting that takes effect on the next connection.
    func reconnect(_ displayName: String) {
        guard let connection = connection(for: displayName) else { return }
        if connection.isDisconnected() {
            connect(displayName)
            return
        }
        disconnect(displayName)
        connectWhenDisconnected(displayName, attemptsLeft: 60)
    }

    private func connectWhenDisconnected(_ displayName: String, attemptsLeft: Int) {
        guard attemptsLeft > 0, let connection = connection(for: displayName) else { return }
        if connection.isDisconnected() {
            connect(displayName)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in self?.connectWhenDisconnected(displayName, attemptsLeft: attemptsLeft - 1) }
        }
    }

    // MARK: Snapshots

    func refreshConnections() {
        var new: [String: ConnectionSnapshot] = [:]
        for displayName in displayNames {
            if let connection = connection(for: displayName) {
                new[displayName] = Self.snapshot(of: connection, displayName: displayName)
            }
        }
        if new != snapshots {
            snapshots = new
        }
    }

    static func snapshot(of connection: VPNConnection, displayName: String) -> ConnectionSnapshot {

        let state = connection.state() ?? "EXITING"
        let requested = connection.requestedState() ?? "EXITING"

        let status: ConnectionSnapshot.Status
        switch state {
        case "CONNECTED":
            status = .connected
        case "EXITING":
            status = connection.authFailed() ? .authFailed : .disconnected
        case "DISCONNECTING":
            status = .disconnecting
        case "PASSWORD_WAIT", "PRIVATE_KEY_WAIT":
            status = .waitingForCredentials
        default:
            status = (requested == "EXITING" && state != "RECONNECTING") ? .disconnecting : .connecting(ConnectionPhase(state: state))
        }

        let phase = ConnectionPhase(state: state)

        var elapsed = ""
        if state != "EXITING", let since = connection.connectedSinceDate() {
            elapsed = formatElapsed(Date().timeIntervalSince(since))
        }

        var inRate = 0.0, outRate = 0.0, inTotal = 0.0, outTotal = 0.0
        if state != "EXITING" || connection.logFilesMayExist() {
            let stats = TBSwiftUIBridge.statistics(for: connection)
            inRate   = stats["inRate"]?.doubleValue   ?? 0
            outRate  = stats["outRate"]?.doubleValue  ?? 0
            inTotal  = stats["inTotal"]?.doubleValue  ?? 0
            outTotal = stats["outTotal"]?.doubleValue ?? 0
        }

        let warnings = TBSwiftUIBridge.warnings(displayName: displayName).map(ConnectionWarning.init(dictionary:))

        let path = gMC?.myConfigDictionary()?[displayName] as? String ?? ""
        let isShared = path.hasPrefix("/Library/Application Support/Tunnelblick/Shared/")
        let isDeployed = path.contains("/Contents/Resources/Deploy/")

        let defaults = gTbDefaults
        let operationsAllowUI = TBOperationQueue.shouldUIBeEnabled(forDisplayName: displayName)
        let canConnect = connection.isDisconnected()
            && !(defaults?.bool(forKey: displayName + "-disableConnectButton") ?? false)
            && operationsAllowUI
        let canDisconnect = !connection.isDisconnected()
            && !(defaults?.bool(forKey: displayName + "-disableDisconnectButton") ?? false)

        let before = connection.ipAddressBeforeConnect()
        let after = state == "CONNECTED" ? gMC?.publicIPAddress() : nil

        return ConnectionSnapshot(
            displayName: displayName,
            localizedName: connection.localizedName() ?? displayName,
            state: state,
            localizedStateText: localizedState(state),
            status: status,
            phase: phase,
            elapsed: elapsed,
            inRate: inRate, outRate: outRate, inTotal: inTotal, outTotal: outTotal,
            warnings: state == "CONNECTED" ? warnings : [],
            isShared: isShared,
            isDeployed: isDeployed,
            publicIPBefore: (before?.isEmpty ?? true) ? nil : before,
            publicIPAfter: (after?.isEmpty ?? true) ? nil : after,
            canConnect: canConnect,
            canDisconnect: canDisconnect)
    }

    /// "00:11", "12:34", "1:02:03", "2 days 1:02:03" (like the original status window).
    static func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 {
            return LF("%d days %d:%02d:%02d", days, hours, minutes, seconds)
        }
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
