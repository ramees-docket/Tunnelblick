//
//  OverviewTabView.swift
//  Tunnelblick
//
//  The Overview tab of a configuration: warnings (with the fix), connection details and traffic.
//  ConfigurationLiveModel keeps what the configuration's views need between AppModel ticks: the configuration file
//  info, this Mac's network, the VPN address and DNS servers, and the traffic history for the sparklines.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

// MARK: - Live model (one per shown configuration)

/// Number of traffic samples kept for the sparklines (one per second). A global constant so that the nonisolated
/// Shape code can read it.
let liveTrafficSampleCount = 60

@MainActor
final class ConfigurationLiveModel: ObservableObject {

    let displayName: String

    @Published private(set) var fileInfo = ConfigurationFileInfo()
    @Published private(set) var local = LocalNetworkInfo()
    @Published private(set) var tunnelAddress: String?
    @Published private(set) var dnsServerAddresses: [String] = []
    @Published private(set) var inSamples: [Double] = []
    @Published private(set) var outSamples: [Double] = []

    private var tickCount = 0
    private var addressSession: Date?           // connectedSinceDate of the connection the address was found for

    init(displayName: String) {
        self.displayName = displayName
    }

    func start(snapshot: ConnectionSnapshot?) {
        let entry = ConfigurationInfoCache.shared.entry(for: displayName, maxAge: 0)
        if entry.info != fileInfo {
            fileInfo = entry.info
        }
        refreshNetwork()
        refreshAddresses(snapshot: snapshot, force: true)
    }

    /// Called every second (AppModel.tick).
    func tick(snapshot: ConnectionSnapshot?) {
        tickCount &+= 1

        if let snapshot, snapshot.isConnected {
            append(snapshot.inRate, to: &inSamples)
            append(snapshot.outRate, to: &outSamples)
        } else if !inSamples.isEmpty || !outSamples.isEmpty {
            inSamples = []
            outSamples = []
        }

        if tickCount % 5 == 0 {
            refreshNetwork()
        }
        if tickCount % 3 == 0 {
            refreshAddresses(snapshot: snapshot, force: false)
        }
        if tickCount % 30 == 0 {
            let info = ConfigurationInfoCache.shared.entry(for: displayName).info
            if info != fileInfo {
                fileInfo = info
            }
        }
    }

    func stateChanged(snapshot: ConnectionSnapshot?) {
        refreshNetwork()
        refreshAddresses(snapshot: snapshot, force: true)
    }

    private func append(_ value: Double, to samples: inout [Double]) {
        samples.append(max(0, value))
        if samples.count > liveTrafficSampleCount {
            samples.removeFirst(samples.count - liveTrafficSampleCount)
        }
    }

    private func refreshNetwork() {
        let current = LocalNetworkInfo.current()
        if current != local {
            local = current
        }
    }

    /// Finds the VPN address and the DNS servers the server pushed, from the OpenVPN log (or the log shown in the
    /// window when this configuration is selected). Shows nothing when they cannot be known.
    private func refreshAddresses(snapshot: ConnectionSnapshot?, force: Bool) {
        guard let snapshot, snapshot.isConnected || snapshot.isBusy,
              let connection = AppModel.shared.connection(for: displayName) else {
            setAddresses(nil, [])
            addressSession = nil
            return
        }

        let session = connection.connectedSinceDate()
        if !force, tunnelAddress != nil, addressSession == session {
            return      // Already known for this connection
        }

        var address: String?
        var dns: [String] = []

        if let path = connection.openvpnLogPath(), !path.isEmpty,
           let text = OpenVPNLogReader.head(ofFileAtPath: path) {
            address = vpnAddress(fromLog: text)
            dns = pushedDNSServers(fromLog: text)
        }

        if (address == nil || dns.isEmpty),
           TBSwiftUIBridge.selectedConnection()?.displayName() == displayName,
           let text = TBSwiftUIBridge.logTextStorage()?.string {
            if address == nil {
                address = vpnAddress(fromLog: text)
            }
            if dns.isEmpty {
                dns = pushedDNSServers(fromLog: text)
            }
        }

        // With a single Tunnelblick connection up, the only tunnel interface address is this connection's.
        if address == nil, snapshot.isConnected {
            let connectedCount = AppModel.shared.snapshots.values.filter { $0.isConnected }.count
            let addresses = TunnelInterfaces.ipv4Addresses()
            if connectedCount == 1, addresses.count == 1 {
                address = addresses.first
            }
        }

        if !snapshot.isConnected {
            address = nil
        }

        setAddresses(address, dns)
        addressSession = (address != nil) ? session : nil
    }

    private func setAddresses(_ address: String?, _ dns: [String]) {
        if address != tunnelAddress {
            tunnelAddress = address
        }
        if dns != dnsServerAddresses {
            dnsServerAddresses = dns
        }
    }
}

// MARK: - Overview

struct OverviewTabView: View {
    let displayName: String
    let snapshot: ConnectionSnapshot?
    @ObservedObject var live: ConfigurationLiveModel

    @ObservedObject private var refresh = LegacyRefresh.shared

    // Explicit: the private stored property would make the synthesized memberwise initializer private.
    init(displayName: String, snapshot: ConnectionSnapshot?, live: ConfigurationLiveModel) {
        self.displayName = displayName
        self.snapshot = snapshot
        _live = ObservedObject(wrappedValue: live)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let snapshot, snapshot.hasWarnings {
                WarningsSection(displayName: displayName, snapshot: snapshot, live: live)
            }
            if let snapshot, snapshot.status == .authFailed {
                failureSection
            }
            connectionSection
            trafficSection
        }
    }

    private var isConnected: Bool { snapshot?.isConnected ?? false }

    private var failureSection: some View {
        InsetSection {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(Theme.failure)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: L("The server did not accept the credentials."))
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: L("Check the username and password (or certificate) and try again. If they are correct, ask your network manager whether your account is active."))
                        .font(Theme.rowCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        AppModel.shared.connect(displayName)
                    } label: {
                        Text(verbatim: L("Try again"))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!(snapshot?.canConnect ?? false))
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private var connectionSection: some View {
        InsetSection(L("Connection")) {
            InsetRow(L("Status")) {
                HStack(spacing: 6) {
                    StateDot(color: snapshot?.tint ?? Theme.faint, pulsing: snapshot?.isBusy ?? false)
                    Text(verbatim: snapshot?.localizedStateText ?? localizedState("EXITING"))
                        .font(.system(size: 13, weight: .medium))
                }
            }
            InsetRow(L("Connected for")) {
                valueText((isConnected && !(snapshot?.elapsed.isEmpty ?? true)) ? snapshot?.elapsed : nil, monospaced: false)
            }
            InsetRow(L("VPN address")) {
                valueText(isConnected ? live.tunnelAddress : nil)
            }
            InsetRow(L("DNS servers"), caption: nameserverSetting) {
                valueText((isConnected && !live.dnsServerAddresses.isEmpty)
                          ? live.dnsServerAddresses.joined(separator: ", ")
                          : nil)
            }
            InsetRow(L("Public IP address"), isLast: true) {
                valueText(publicIPText)
            }
        }
    }

    /// The "Set DNS/WINS" setting of this configuration (the legacy pop-up applies to the selected configuration).
    private var nameserverSetting: String? {
        let _ = refresh.revision
        guard TBSwiftUIBridge.selectedConnection()?.displayName() == displayName else { return nil }
        return ConfigurationActions.legacyConfigurationsView()?.setNameserverPopUpButton()?.titleOfSelectedItem
    }

    private var publicIPText: String? {
        guard let snapshot else { return nil }
        let before = snapshot.publicIPBefore
        let after = snapshot.publicIPAfter
        switch (before, after) {
        case let (before?, after?) where isConnected:
            return before == after ? before : before + " → " + after
        case let (nil, after?) where isConnected:
            return after
        case let (before?, _):
            return before
        default:
            return nil
        }
    }

    private func valueText(_ value: String?, monospaced: Bool = true) -> some View {
        Text(verbatim: value ?? "—")
            .font(monospaced && value != nil ? Theme.mono(12) : .system(size: 13).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var trafficSection: some View {
        InsetSection(L("Traffic")) {
            InsetRow(L("In")) {
                trafficValue(samples: live.inSamples,
                             rate: isConnected ? snapshot?.inRateText : nil,
                             total: hasTotals ? snapshot?.inTotalText : nil,
                             color: Theme.tunnel)
            }
            InsetRow(L("Out"), isLast: true) {
                trafficValue(samples: live.outSamples,
                             rate: isConnected ? snapshot?.outRateText : nil,
                             total: hasTotals ? snapshot?.outTotalText : nil,
                             color: Theme.connected)
            }
        }
    }

    private var hasTotals: Bool {
        guard let snapshot else { return false }
        return snapshot.isConnected || snapshot.inTotal > 0 || snapshot.outTotal > 0
    }

    private func trafficValue(samples: [Double], rate: String?, total: String?, color: Color) -> some View {
        HStack(spacing: 12) {
            Sparkline(values: samples)
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 72, height: 20)
                .opacity(samples.count > 1 ? 1 : 0)
                .accessibilityHidden(true)
            Text(verbatim: rate ?? "—")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .frame(minWidth: 86, alignment: .trailing)
            Text(verbatim: total ?? "—")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
    }
}

/// A line through the last samples, scaled to the largest one.
struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let maximum = max(values.max() ?? 0, 1)
        let step = rect.width / CGFloat(liveTrafficSampleCount - 1)
        let start = rect.maxX - step * CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: start + step * CGFloat(index),
                                y: rect.maxY - CGFloat(value / maximum) * (rect.height - 1))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

// MARK: - Warnings

struct WarningsSection: View {
    let displayName: String
    let snapshot: ConnectionSnapshot
    @ObservedObject var live: ConfigurationLiveModel

    @ObservedObject private var refresh = LegacyRefresh.shared
    @ObservedObject private var model = AppModel.shared

    init(displayName: String, snapshot: ConnectionSnapshot, live: ConfigurationLiveModel) {
        self.displayName = displayName
        self.snapshot = snapshot
        _live = ObservedObject(wrappedValue: live)
    }

    private var dnsWarnings: [ConnectionWarning] { snapshot.warnings.filter { $0.kind.isDNS } }
    private var ipWarning: ConnectionWarning? { snapshot.warnings.first { $0.kind == .publicIpUnchanged } }
    private var networkName: String { live.local.interfaceName ?? L("the local network") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: L("Warnings"))
                    .font(Theme.sectionHead)
                    .foregroundStyle(.secondary)
                Text(verbatim: String(snapshot.warnings.count))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(Theme.warning))
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                if !dnsWarnings.isEmpty {
                    OverviewWarningNote(symbolName: "exclamationmark.triangle.fill",
                                title: L("DNS lookups are leaving outside the VPN"),
                                message: dnsMessage)
                    Divider().padding(.leading, 40)
                }
                if let ipWarning {
                    OverviewWarningNote(symbolName: "globe",
                                title: L("Your public IP address didn’t change"),
                                message: LF("It is still %@. Traffic that the VPN does not route still leaves through %@, so websites see your own address.",
                                            ipWarning.address.isEmpty ? (snapshot.publicIPBefore ?? "—") : ipWarning.address,
                                            networkName))
                    Divider().padding(.leading, 40)
                }
                fixRow
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.groupBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.warning.opacity(0.5), lineWidth: 1)
            )
        }
    }

    private var dnsMessage: String {
        var seen: [String] = []
        for warning in dnsWarnings where !warning.address.isEmpty && !seen.contains(warning.address) {
            seen.append(warning.address)
        }
        let addresses = ListFormatter.localizedString(byJoining: seen)
        let name = snapshot.localizedName
        if dnsWarnings.contains(where: { $0.kind == .dnsKnownPublicNotRoutedThroughVpn }) {
            return LF("%@ tells this Mac to use %@. They are public DNS servers and the VPN doesn’t route them, so every site name you look up goes out over %@, unencrypted — this network and your internet provider can see which sites you visit.",
                      name, addresses, networkName)
        }
        return LF("%@ tells this Mac to use %@, but the VPN doesn’t route them, so the site names you look up go out over %@ instead of through the tunnel.",
                  name, addresses, networkName)
    }

    private var routeAllCheckbox: NSButton? {
        ConfigurationActions.legacyConfigurationsView()?.routeAllTrafficThroughVpnCheckbox()
    }

    private var fixRow: some View {
        let _ = refresh.revision + model.tick
        let checkbox = routeAllCheckbox
        let isSelected = TBSwiftUIBridge.selectedConnection()?.displayName() == displayName
        let canTurnOn = isSelected
            && checkbox != nil
            && checkbox?.state == .off
            && !(checkbox?.isHidden ?? true)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: L("How to fix it"))
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: L("Turn on “Route all IPv4 traffic through the VPN”, or ask your VPN admin to push DNS servers that are reachable through the tunnel."))
                    .font(Theme.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if canTurnOn {
                        Button {
                            turnOnRouteAllTraffic()
                        } label: {
                            Text(verbatim: L("Turn on Route all IPv4 traffic"))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!(checkbox?.isEnabled ?? false))
                        if !(checkbox?.isEnabled ?? false) {
                            LockedBadge()
                        }
                    }
                    Button {
                        DetailsNavigation.shared.showLog(revealing: snapshot.warnings.first?.logLine)
                    } label: {
                        Text(verbatim: L("Show warning lines in the log"))
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    /// Clicks the legacy "Route all IPv4 traffic through the VPN" checkbox (all the original rules apply), then
    /// reconnects so the setting takes effect.
    private func turnOnRouteAllTraffic() {
        guard TBSwiftUIBridge.selectedConnection()?.displayName() == displayName,
              let checkbox = routeAllCheckbox,
              checkbox.state == .off,
              checkbox.isEnabled else {
            return
        }
        TBSwiftUIBridge.click(checkbox)
        LegacyRefresh.shared.bump()
        if checkbox.state == .on {
            AppModel.shared.reconnect(displayName)
        }
    }
}

struct OverviewWarningNote: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 14))
                .foregroundStyle(Theme.warning)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: message)
                    .font(Theme.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
