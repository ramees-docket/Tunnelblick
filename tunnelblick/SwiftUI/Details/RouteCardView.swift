//
//  RouteCardView.swift
//  Tunnelblick
//
//  The Route card: where this Mac's traffic goes. Four nodes (This Mac → Wi‑Fi/Ethernet → VPN server → Internet)
//
//   * Not connected: a dashed line and a dashed bypass arc from the network straight to the internet.
//   * Connecting: the line draws in node by node as OpenVPN advances through its phases; the phase being worked on
//     has a tick under the part of the route it belongs to, and the node doing the work pulses.
//   * Connected: a solid accent line inside an "ENCRYPTED TUNNEL" band from this Mac to the server, packets flowing
//     both ways (accent while encrypted, grey after the server), and the public IP rolling from before to after.
//   * Warnings: the traffic the VPN does not route takes the bypass; DNS lookups leaving outside the VPN are drawn as
//     an amber dashed path, and an unchanged public IP marks the Internet node amber.
//   * Authorization failed: the line stops at the server with a red break mark.
//
//  Reduce Motion: no flowing packets or pulses, and changes are instant.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

// MARK: - Card

struct RouteCardView: View {
    let displayName: String
    let snapshot: ConnectionSnapshot?
    @ObservedObject var live: ConfigurationLiveModel

    @ObservedObject private var durations = ConnectDurationTracker.shared
    @ObservedObject private var navigation = DetailsNavigation.shared

    @State private var lingerTicks = false
    @State private var lastMode: RouteModel.Mode?

    // Explicit: the private stored properties would make the synthesized memberwise initializer private.
    init(displayName: String, snapshot: ConnectionSnapshot?, live: ConfigurationLiveModel) {
        self.displayName = displayName
        self.snapshot = snapshot
        _live = ObservedObject(wrappedValue: live)
    }

    var body: some View {
        let route = RouteModel(snapshot: snapshot,
                               info: live.fileInfo,
                               local: live.local,
                               tunnelAddress: live.tunnelAddress,
                               connectDuration: durations.durations[displayName])
        VStack(alignment: .leading, spacing: 6) {
            RouteHeader(route: route)
            RouteFigure(route: route,
                        showTicks: route.showsTicks || lingerTicks,
                        animate: navigation.windowIsVisible)
                .frame(height: RouteGeometry.height)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 8, trailing: 14))
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.groupBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: route.accessibilityText))
        .task(id: route.mode) {
            await modeDidChange(to: route.mode)
        }
    }

    /// Keeps the phase ticks visible for a moment after connecting, so the last step can be seen completing.
    private func modeDidChange(to mode: RouteModel.Mode) async {
        let previous = lastMode
        lastMode = mode
        guard mode == .connected, let previous, previous != .connected, !Theme.reduceMotion else {
            lingerTicks = false
            return
        }
        lingerTicks = true
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        if !Task.isCancelled {
            lingerTicks = false
        }
    }
}

struct RouteHeader: View {
    let route: RouteModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: L("Route"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            caption
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .id(route.captionKey)
                .transition(.opacity)
            Spacer(minLength: 8)
            Text(verbatim: route.stepText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(height: 18)
        .animation(Theme.motion(Theme.quick), value: route.captionKey)
    }

    private var caption: Text {
        let boldColor: Color
        switch route.captionTone {
        case .normal:  boldColor = .primary
        case .warning: boldColor = Theme.warning
        case .failure: boldColor = Theme.failure
        }
        let bold = Text(verbatim: route.captionBold)
            .fontWeight(.semibold)
            .foregroundColor(boldColor)
        guard let rest = route.captionRest, !rest.isEmpty else {
            return bold
        }
        return bold + Text(verbatim: " — " + rest).foregroundColor(.secondary)
    }
}

// MARK: - What the route shows

struct RouteModel {

    enum Mode: Equatable {
        case idle, connecting, connected, disconnecting, failed
    }

    enum Tone {
        case normal, warning, failure
    }

    enum TickState: Equatable {
        case hidden, done, current
    }

    struct Tick: Identifiable {
        let phase: ConnectionPhase
        let state: TickState
        let designX: CGFloat
        let row: Int
        let label: String
        var id: Int { phase.rawValue }
    }

    let mode: Mode
    let phases: [ConnectionPhase]
    let phase: ConnectionPhase?
    let phaseIndex: Int                 // Index of `phase` in `phases`; -1 when unknown
    let isTCP: Bool

    let warningCount: Int
    let dnsAddresses: [String]
    let dnsLeak: Bool
    let ipUnchanged: Bool
    let split: Bool                     // Some traffic does not go through the tunnel

    let inRate: Double
    let outRate: Double

    let macTitle: String
    let macDetail: String
    let networkTitle: String
    let networkDetail: String
    let networkSymbol: String
    let serverTitle: String
    let serverDetail: String
    let internetTitle: String
    let internetDetail: String

    let captionBold: String
    let captionRest: String?
    let captionTone: Tone
    let stepText: String
    let footerMeta: String

    init(snapshot: ConnectionSnapshot?,
         info: ConfigurationFileInfo,
         local: LocalNetworkInfo,
         tunnelAddress: String?,
         connectDuration: TimeInterval?) {

        let status = snapshot?.status ?? .disconnected
        let mode: Mode
        switch status {
        case .disconnected:                         mode = .idle
        case .connecting, .waitingForCredentials:   mode = .connecting
        case .connected:                            mode = .connected
        case .disconnecting:                        mode = .disconnecting
        case .authFailed:                           mode = .failed
        }

        let isTCP = info.isTCP || snapshot?.state == "TCP_CONNECT"
        let phases = ConnectionPhase.sequence(isTCP: isTCP)
        let phase: ConnectionPhase? = (mode == .connecting) ? snapshot?.phase : nil
        var phaseIndex = -1
        if let phase {
            if let index = phases.firstIndex(of: phase) {
                phaseIndex = index
            } else if let index = phases.lastIndex(where: { $0 < phase }) {
                phaseIndex = index      // e.g. UDP_CONNECT, which is not one of the UDP phases
            }
        }

        let warnings = (mode == .connected) ? (snapshot?.warnings ?? []) : []
        var dnsAddresses: [String] = []
        for warning in warnings where warning.kind.isDNS && !warning.address.isEmpty && !dnsAddresses.contains(warning.address) {
            dnsAddresses.append(warning.address)
        }
        let dnsLeak = warnings.contains { $0.kind.isDNS }
        let ipUnchanged = warnings.contains { $0.kind == .publicIpUnchanged }

        let networkName = local.interfaceName ?? L("the local network")
        let reachedAssignIP = Self.reached(.assignIP, phases: phases, index: phaseIndex)

        self.mode = mode
        self.phases = phases
        self.phase = phase
        self.phaseIndex = phaseIndex
        self.isTCP = isTCP
        self.warningCount = warnings.count
        self.dnsAddresses = dnsAddresses
        self.dnsLeak = dnsLeak
        self.ipUnchanged = ipUnchanged
        self.split = !warnings.isEmpty
        self.inRate = snapshot?.inRate ?? 0
        self.outRate = snapshot?.outRate ?? 0

        // Labels
        self.macTitle = L("This Mac")
        if let tunnelAddress, mode == .connected || (mode == .connecting && reachedAssignIP) {
            self.macDetail = tunnelAddress
        } else {
            self.macDetail = local.address ?? ""
        }
        self.networkTitle = local.interfaceName ?? L("Network")
        self.networkDetail = local.bsdName ?? ""
        if local.isWiFi {
            self.networkSymbol = "wifi"
        } else if local.interfaceName != nil {
            self.networkSymbol = "cable.connector"
        } else {
            self.networkSymbol = "network"
        }
        self.serverTitle = info.remoteHost ?? L("VPN server")
        self.serverDetail = info.fileName != nil ? info.protocolAndPort : ""
        self.internetTitle = L("Internet")
        if mode == .connected {
            self.internetDetail = snapshot?.publicIPAfter ?? snapshot?.publicIPBefore ?? ""
        } else {
            self.internetDetail = snapshot?.publicIPBefore ?? ""
        }

        // Caption ("Connected — encrypted to the VPN server, then out as 198.51.100.7")
        switch mode {
        case .idle:
            captionBold = L("Not connected")
            captionRest = LF("traffic goes straight from %@ to the internet", networkName)
            captionTone = .normal
        case .connecting:
            captionBold = L("Connecting")
            captionRest = phase?.title ?? snapshot?.localizedStateText
            captionTone = .normal
        case .disconnecting:
            captionBold = localizedState("DISCONNECTING")
            captionRest = L("closing the tunnel")
            captionTone = .normal
        case .failed:
            captionBold = L("Couldn’t connect")
            captionRest = L("the server did not accept the credentials")
            captionTone = .failure
        case .connected:
            if warnings.isEmpty {
                captionBold = localizedState("CONNECTED")
                if let after = snapshot?.publicIPAfter {
                    captionRest = LF("encrypted to the VPN server, then out as %@", after)
                } else {
                    captionRest = L("encrypted to the VPN server")
                }
                captionTone = .normal
            } else {
                captionBold = warnings.count == 1
                    ? L("Connected with a warning")
                    : LF("Connected with %ld warnings", warnings.count)
                captionRest = dnsLeak
                    ? L("DNS and most traffic skip the tunnel")
                    : L("the public IP address did not change")
                captionTone = .warning
            }
        }

        // Right side: "3 of 7", "Connected in 3.1 s"
        switch mode {
        case .connecting where phaseIndex >= 0:
            stepText = LF("%ld of %ld", phaseIndex + 1, phases.count)
        case .connected:
            if let connectDuration {
                stepText = String(format: L("Connected in %.1f s"), locale: Locale.current, connectDuration)
            } else {
                stepText = ""
            }
        case .failed:
            stepText = "AUTH_FAILED"
        default:
            stepText = ""
        }

        var meta: [String] = []
        if let cipher = info.cipher, !cipher.isEmpty {
            meta.append(cipher.uppercased())
        }
        if info.fileName != nil {
            meta.append(info.protocolAndPort)
        }
        footerMeta = meta.joined(separator: " · ")
    }

    private static func reached(_ target: ConnectionPhase, phases: [ConnectionPhase], index: Int) -> Bool {
        guard let targetIndex = phases.firstIndex(of: target) else { return false }
        return index >= targetIndex
    }

    func reached(_ target: ConnectionPhase) -> Bool {
        Self.reached(target, phases: phases, index: phaseIndex)
    }

    var captionKey: String { captionBold + "|" + (captionRest ?? "") }

    var accessibilityText: String {
        var text = captionBold
        if let captionRest, !captionRest.isEmpty {
            text += " — " + captionRest
        }
        if !stepText.isEmpty {
            text += ". " + stepText
        }
        return text
    }

    // Segments and tunnel
    var segment1: Bool { mode == .connected || mode == .failed || (mode == .connecting && phaseIndex >= 0) }
    var segment2: Bool { mode == .connected || mode == .failed || (mode == .connecting && reached(isTCP ? .tcpConnect : .wait)) }
    var segment3: Bool { mode == .connected && !split }
    var tunnel: Bool { mode == .connected }
    var showsTicks: Bool { mode == .connecting || mode == .failed }

    /// How long a segment takes to draw in (roughly how long the phase usually takes).
    var segmentDuration: Double {
        if mode == .disconnecting {
            return 0.32
        }
        switch phase {
        case .resolve?:    return 0.43
        case .tcpConnect?: return 0.40
        case .wait?:       return 0.47
        case .auth?:       return 0.56
        case .getConfig?:  return 0.54
        case .assignIP?:   return 0.40
        case .addRoutes?:  return 0.45
        default:           return 0.52
        }
    }

    // Nodes
    var macLit: Bool      { mode == .connected || (mode == .connecting && reached(.assignIP)) }
    var macPing: Bool     { mode == .connecting && (phase == .assignIP || phase == .addRoutes) }
    var networkLit: Bool  { mode == .connected || mode == .connecting || mode == .failed }
    var networkPing: Bool { mode == .connecting && (phase == nil || phase == .resolve) }
    var serverLit: Bool   { mode == .connected || (mode == .connecting && segment2) }
    var serverPing: Bool {
        guard mode == .connecting, let phase else { return false }
        return [ConnectionPhase.tcpConnect, .wait, .auth, .getConfig].contains(phase)
    }
    var internetLit: Bool { mode == .connected && !split && !ipUnchanged }

    /// Something moves along the route (packets, the DNS leak, the configuration coming back from the server).
    var hasFlow: Bool {
        mode == .connected || (mode == .connecting && phase == .getConfig)
    }

    var ticks: [Tick] {
        let authIndex = phases.firstIndex(of: .auth) ?? 0
        return phases.enumerated().map { (index, phase) -> Tick in
            var state = TickState.hidden
            switch mode {
            case .connecting:
                state = index < phaseIndex ? .done : (index == phaseIndex ? .current : .hidden)
            case .connected:
                state = phase == .connected ? .current : .done
            case .failed:
                state = index < authIndex ? .done : (index == authIndex ? .current : .hidden)
            default:
                state = .hidden
            }
            let design = Self.tickDesign(phase)
            return Tick(phase: phase, state: state, designX: design.x, row: design.row, label: design.label)
        }
    }

    /// Where each phase's tick goes (in the 592-point design of the prototype) and its short label.
    private static func tickDesign(_ phase: ConnectionPhase) -> (x: CGFloat, row: Int, label: String) {
        switch phase {
        case .resolve:    return (112, 1, L("Resolving"))
        case .tcpConnect: return (255, 1, L("TCP"))
        case .wait:       return (330, 1, L("Waiting"))
        case .auth:       return (410, 1, localizedState("AUTH"))
        case .getConfig:  return (300, 2, L("Configuration"))
        case .assignIP:   return (220, 2, L("IP address"))
        case .addRoutes:  return (66, 2, L("Routes"))
        case .connected:  return (456, 2, localizedState("CONNECTED"))
        }
    }
}

// MARK: - Geometry (the prototype's 592 × 120 design, scaled horizontally)

struct RouteGeometry {
    static let designWidth: CGFloat = 592
    static let height: CGFloat = 120

    let width: CGFloat
    let y: CGFloat = 62

    func x(_ design: CGFloat) -> CGFloat {
        design / Self.designWidth * width
    }

    func point(_ designX: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x(designX), y: y)
    }

    var mac: CGFloat      { x(40) }
    var network: CGFloat  { x(176) }
    var server: CGFloat   { x(368) }
    var internet: CGFloat { x(540) }

    var macPoint: CGPoint      { CGPoint(x: mac, y: y) }
    var networkPoint: CGPoint  { CGPoint(x: network, y: y) }
    var serverPoint: CGPoint   { CGPoint(x: server, y: y) }
    var internetPoint: CGPoint { CGPoint(x: internet, y: y) }

    // The bypass arc: from the network node straight to the internet, under the tunnel.
    var bypassControl: CGPoint { CGPoint(x: (network + internet) / 2, y: y + 50) }

    func bypassPath() -> Path {
        var path = Path()
        path.move(to: networkPoint)
        path.addQuadCurve(to: internetPoint, control: bypassControl)
        return path
    }

    /// A point on This Mac → network → bypass arc → Internet (u from 0 to 1).
    func bypassRoutePoint(at u: Double, offset: CGFloat) -> CGPoint {
        let first = network - mac
        let arc = (internet - network) * 1.12
        let split = Double(first / max(first + arc, 1))
        if u < split {
            return CGPoint(x: mac + first * CGFloat(u / max(split, 0.0001)), y: y + offset)
        }
        let t = CGFloat((u - split) / max(1 - split, 0.0001))
        let point = Self.quadPoint(t, networkPoint, bypassControl, internetPoint)
        return CGPoint(x: point.x, y: point.y + offset * 0.7)
    }

    // The DNS leak path: This Mac → network → Internet, below the route.
    private var dnsSegments: [(CGPoint, CGPoint, CGPoint, CGPoint)] {
        [(point(40, 79), point(70, 101), point(146, 101), point(176, 79)),
         (point(176, 79), point(262, 118), point(454, 118), point(540, 79))]
    }

    func dnsPath() -> Path {
        var path = Path()
        let segments = dnsSegments
        path.move(to: segments[0].0)
        for segment in segments {
            path.addCurve(to: segment.3, control1: segment.1, control2: segment.2)
        }
        return path
    }

    func dnsPoint(at u: Double) -> CGPoint {
        let segments = dnsSegments
        let firstShare = 0.28
        if u < firstShare {
            let s = segments[0]
            return Self.cubicPoint(CGFloat(u / firstShare), s.0, s.1, s.2, s.3)
        }
        let s = segments[1]
        return Self.cubicPoint(CGFloat((u - firstShare) / (1 - firstShare)), s.0, s.1, s.2, s.3)
    }

    static func quadPoint(_ t: CGFloat, _ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> CGPoint {
        let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, d = t * t
        return CGPoint(x: a * p0.x + b * c.x + d * p1.x, y: a * p0.y + b * c.y + d * p1.y)
    }

    static func cubicPoint(_ t: CGFloat, _ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
    }
}

// MARK: - Figure

struct RouteFigure: View {
    let route: RouteModel
    let showTicks: Bool
    let animate: Bool

    var body: some View {
        GeometryReader { proxy in
            let g = RouteGeometry(width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                RouteLinesLayer(route: route, g: g)
                RouteTicksLayer(route: route, g: g, visible: showTicks)
                RouteFlowLayer(route: route, g: g, animate: animate)
                RouteNodesLayer(route: route, g: g)
                RouteLabelsLayer(route: route, g: g)
                RouteAnnotationsLayer(route: route, g: g, showTicks: showTicks)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }
}

private let routeBaseColor  = Color.primary.opacity(0.30)
private let routeFaintColor = Color.primary.opacity(0.13)
private let routeDashed     = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])

struct RouteSegmentShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

struct RouteLinesLayer: View {
    let route: RouteModel
    let g: RouteGeometry

    var body: some View {
        let failed = route.mode == .failed
        let lineColor = failed ? routeBaseColor : Theme.tunnel
        let bandWidth = g.server - g.mac + 52
        let breakX = g.x(399)
        ZStack(alignment: .topLeading) {
            // The plain route, always under everything
            Path { path in
                path.move(to: g.macPoint)
                path.addLine(to: g.networkPoint)
            }
            .stroke(routeBaseColor, style: routeDashed)
            Path { path in
                path.move(to: g.networkPoint)
                path.addLine(to: g.internetPoint)
            }
            .stroke(routeFaintColor, style: routeDashed)

            // Straight from the network to the internet: dashed when not connected, solid grey for traffic that
            // skips the tunnel.
            g.bypassPath()
                .stroke(route.split ? Theme.neutral.opacity(0.75) : routeBaseColor,
                        style: route.split ? StrokeStyle(lineWidth: 1.5, lineCap: .round) : routeDashed)
                .opacity(route.mode == .idle || route.split ? 1 : 0)
                .animation(Theme.motion(Theme.standard), value: route.split)
                .animation(Theme.motion(Theme.standard), value: route.mode)

            // The encrypted tunnel band
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.tunnel.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.tunnel.opacity(0.35), lineWidth: 1)
                )
                .frame(width: bandWidth, height: 24)
                .scaleEffect(x: route.tunnel ? 1 : 0.02, y: 1, anchor: .leading)
                .opacity(route.tunnel ? 1 : 0)
                .position(x: g.mac - 26 + bandWidth / 2, y: g.y)
                .animation(Theme.motion(.spring(response: 0.55, dampingFraction: 0.9)), value: route.tunnel)
            Text(verbatim: L("ENCRYPTED TUNNEL"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.tunnel)
                .fixedSize()
                .position(x: (g.network + g.server) / 2, y: g.y - 20)
                .opacity(route.tunnel ? 0.9 : 0)
                .animation(Theme.motion(Animation.easeOut(duration: 0.4).delay(0.35)), value: route.tunnel)

            // The route drawing in
            segment(from: g.macPoint, to: g.networkPoint, on: route.segment1, color: lineColor)
            segment(from: g.networkPoint, to: g.serverPoint, on: route.segment2, color: lineColor)
            segment(from: g.serverPoint, to: g.internetPoint, on: route.segment3, color: Theme.neutral.opacity(0.8))

            // Authorization failed: the route stops at the server
            Path { path in
                path.move(to: CGPoint(x: breakX - 4.5, y: g.y - 7))
                path.addLine(to: CGPoint(x: breakX - 1.5, y: g.y + 7))
                path.move(to: CGPoint(x: breakX + 1.5, y: g.y - 7))
                path.addLine(to: CGPoint(x: breakX + 4.5, y: g.y + 7))
            }
            .stroke(Theme.failure, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .scaleEffect(failed ? 1 : 0.4,
                         anchor: UnitPoint(x: breakX / max(g.width, 1), y: g.y / RouteGeometry.height))
            .opacity(failed ? 1 : 0)
            .animation(Theme.motion(.spring(response: 0.35, dampingFraction: 0.55)), value: failed)
        }
    }

    private func segment(from start: CGPoint, to end: CGPoint, on: Bool, color: Color) -> some View {
        RouteSegmentShape(from: start, to: end)
            .trim(from: 0, to: on ? 1 : 0)
            .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .butt))
            .animation(Theme.motion(.timingCurve(0.5, 0, 0.25, 1, duration: route.segmentDuration)), value: on)
    }
}

struct RouteTicksLayer: View {
    let route: RouteModel
    let g: RouteGeometry
    let visible: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(route.ticks) { tick in
                let x = g.x(tick.designX)
                let shown = visible && tick.state != .hidden
                let isCurrent = tick.state == .current
                let currentColor = route.mode == .failed ? Theme.failure : Theme.tunnel
                Path { path in
                    path.move(to: CGPoint(x: x, y: g.y + 5))
                    path.addLine(to: CGPoint(x: x, y: tick.row == 1 ? 81 : 99))
                }
                .stroke(routeFaintColor, lineWidth: 1)
                .opacity(shown ? 1 : 0)
                Circle()
                    .fill(isCurrent ? currentColor : Theme.tunnel)
                    .frame(width: 5.2, height: 5.2)
                    .position(x: x, y: g.y)
                    .opacity(shown ? (isCurrent ? 1 : 0.55) : 0)
                Text(verbatim: tick.label)
                    .font(.system(size: 10.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? currentColor : Color.secondary)
                    .fixedSize()
                    .position(x: x, y: (tick.row == 1 ? 84 : 102) + 7)
                    .offset(y: shown ? 0 : 3)
                    .opacity(shown ? 1 : 0)
            }
        }
        .animation(Theme.motion(Theme.quick), value: route.phaseIndex)
        .animation(Theme.motion(Theme.quick), value: visible)
        .animation(Theme.motion(Theme.quick), value: route.mode)
    }
}

struct RouteNodesLayer: View {
    let route: RouteModel
    let g: RouteGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            RouteNodeView(symbolName: "laptopcomputer", lit: route.macLit, ping: route.macPing)
                .position(g.macPoint)
            RouteNodeView(symbolName: route.networkSymbol, lit: route.networkLit, ping: route.networkPing)
                .position(g.networkPoint)
            RouteNodeView(symbolName: "server.rack",
                          lit: route.serverLit,
                          bad: route.mode == .failed,
                          ping: route.serverPing,
                          dim: route.mode == .idle)
                .position(g.serverPoint)
            RouteNodeView(symbolName: "globe",
                          lit: route.internetLit,
                          warn: route.ipUnchanged)
                .position(g.internetPoint)
        }
    }
}

struct RouteNodeView: View {
    let symbolName: String
    var lit = false
    var bad = false
    var warn = false
    var ping = false
    var dim = false

    var body: some View {
        let edge: Color = bad ? Theme.failure : (warn ? Theme.warning : (lit ? Theme.tunnel : Theme.separator))
        let glyph: Color = bad ? Theme.failure : (lit ? Theme.tunnel : Color.primary.opacity(0.72))
        let emphasized = lit || bad || warn
        ZStack {
            if ping {
                PulseRing(color: Theme.tunnel)
            }
            Circle()
                .fill(Theme.groupBackground)
            Circle()
                .strokeBorder(edge, lineWidth: emphasized ? 1.5 : 1)
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(glyph)
        }
        .frame(width: 34, height: 34)
        .opacity(dim ? 0.5 : 1)
        .animation(Theme.motion(Theme.standard), value: emphasized)
        .animation(Theme.motion(Theme.standard), value: dim)
    }
}

/// The ring that expands from the node doing the work.
struct PulseRing: View {
    let color: Color

    var body: some View {
        if Theme.reduceMotion {
            Circle()
                .stroke(color.opacity(0.45), lineWidth: 1.5)
                .scaleEffect(1.3)
        } else {
            TimelineView(.animation) { timeline in
                let period = 1.1
                let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .scaleEffect(1 + 0.7 * progress)
                    .opacity(0.9 * (1 - progress))
            }
        }
    }
}

struct RouteLabelsLayer: View {
    let route: RouteModel
    let g: RouteGeometry

    var body: some View {
        let edgeWidthLeft = min(140, 2 * (g.mac + 12))
        let edgeWidthRight = min(140, 2 * (g.width - g.internet + 12))
        let middleWidth = max(60, min(180, g.server - g.network - 12))
        ZStack(alignment: .topLeading) {
            RouteLabel(title: route.macTitle, detail: route.macDetail)
                .frame(width: edgeWidthLeft)
                .position(x: g.mac, y: 15)
            RouteLabel(title: route.networkTitle, detail: route.networkDetail)
                .frame(width: middleWidth)
                .position(x: g.network, y: 15)
            RouteLabel(title: route.serverTitle, detail: route.serverDetail, dim: route.mode == .idle)
                .frame(width: middleWidth)
                .position(x: g.server, y: 15)
            RouteLabel(title: route.internetTitle, detail: route.internetDetail, showsWarning: route.ipUnchanged)
                .frame(width: edgeWidthRight)
                .position(x: g.internet, y: 15)
        }
    }
}

struct RouteLabel: View {
    let title: String
    let detail: String
    var dim = false
    var showsWarning = false

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 3) {
                Text(verbatim: detail)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.numericText())
                    .animation(Theme.motion(.spring(response: 0.52, dampingFraction: 0.8)), value: detail)
                if showsWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.warning)
                }
            }
            .frame(minHeight: 14)
        }
        .opacity(dim ? 0.55 : 1)
        .animation(Theme.motion(Theme.standard), value: dim)
    }
}

struct RouteAnnotationsLayer: View {
    let route: RouteModel
    let g: RouteGeometry
    let showTicks: Bool

    var body: some View {
        let showsFooter = route.mode == .connected && route.warningCount == 0 && !showTicks
        ZStack(alignment: .topLeading) {
            // "DNS 8.8.8.8 · 8.8.4.4 outside VPN" on the amber leak path
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(verbatim: LF("DNS %@ outside VPN", route.dnsAddresses.joined(separator: " · ")))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.warning)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.groupBackground)
            )
            .fixedSize()
            .position(x: (g.network + g.internet) / 2, y: 97)
            .opacity(route.dnsLeak ? 1 : 0)

            // Footer: cipher and protocol, and the legend
            HStack(spacing: 5) {
                Text(verbatim: route.footerMeta)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 8)
                Circle().fill(Theme.tunnel).frame(width: 6, height: 6)
                Text(verbatim: L("Encrypted"))
                Circle().fill(Theme.neutral).frame(width: 6, height: 6)
                    .padding(.leading, 6)
                Text(verbatim: L("Not encrypted"))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .frame(width: g.width + 4)
            .position(x: g.width / 2, y: 106)
            .opacity(showsFooter ? 1 : 0)
            .offset(y: showsFooter ? 0 : 3)
        }
        .animation(Theme.motion(Animation.easeOut(duration: 0.4)), value: showsFooter)
        .animation(Theme.motion(Theme.standard), value: route.dnsLeak)
    }
}

// MARK: - Flow (packets, DNS leak, configuration coming back)

struct RouteFlowLayer: View {
    let route: RouteModel
    let g: RouteGeometry
    let animate: Bool

    var body: some View {
        let moving = animate && !Theme.reduceMotion && route.hasFlow
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !moving)) { timeline in
            Canvas { context, _ in
                let painter = RouteFlowPainter(route: route,
                                               g: g,
                                               time: timeline.date.timeIntervalSinceReferenceDate,
                                               moving: moving)
                painter.draw(in: &context)
            }
        }
        .allowsHitTesting(false)
    }
}

struct RouteFlowPainter {
    let route: RouteModel
    let g: RouteGeometry
    let time: Double
    let moving: Bool

    private enum Kind {
        case full       // This Mac → server (encrypted) → Internet
        case tunnel     // This Mac → server only (split tunnel)
        case bypass     // This Mac → network → Internet, outside the tunnel
    }

    func draw(in context: inout GraphicsContext) {
        if route.dnsLeak {
            drawDNSLeak(in: &context)
        }
        guard moving else { return }
        if route.mode == .connected {
            drawPackets(in: &context)
        } else if route.mode == .connecting && route.phase == .getConfig {
            drawConfigurationReturning(in: &context)
        }
    }

    private func drawDNSLeak(in context: inout GraphicsContext) {
        let phase = moving ? CGFloat((time * 7.8).truncatingRemainder(dividingBy: 7)) : 0
        context.stroke(g.dnsPath(),
                       with: .color(Theme.warning),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [4, 3], dashPhase: -phase))
        guard moving else { return }
        for index in 0..<3 {
            let u = Self.fraction(time / 2.4 + Double(index) / 3)
            let point = g.dnsPoint(at: index % 2 == 0 ? u : 1 - u)
            dot(&context, at: point, radius: 2, color: Theme.warning, alpha: Self.edgeFade(u))
        }
    }

    private func drawPackets(in context: inout GraphicsContext) {
        let travel = route.inRate > 1_000_000 ? 1.3 : (route.inRate > 200_000 ? 1.9 : 2.6)
        let outCount = Self.count(route.outRate, unit: 32_000, minimum: 1.2, maximum: 5.5, travel: travel)
        let inCount = Self.count(route.inRate, unit: 260_000, minimum: 1.6, maximum: 8, travel: travel)
        for index in 0..<outCount {
            packet(&context, index: index, count: outCount, outbound: true, travel: travel)
        }
        for index in 0..<inCount {
            packet(&context, index: index, count: inCount, outbound: false, travel: travel)
        }
    }

    private func packet(_ context: inout GraphicsContext, index: Int, count: Int, outbound: Bool, travel: Double) {
        let kind: Kind
        if route.split {
            kind = (index % 5 < 3) ? .bypass : .tunnel
        } else {
            kind = .full
        }
        let speed = (kind == .tunnel) ? 1.5 : 1.0
        let jitter = Self.jitter(index, outbound: outbound)
        let raw = Self.fraction(time * speed / travel + (Double(index) + jitter * 0.6) / Double(count) + (outbound ? 0 : 0.37))
        let u = outbound ? raw : 1 - raw
        let offset: CGFloat = outbound ? -3.2 : 3.2

        let point: CGPoint
        let encrypted: Bool
        switch kind {
        case .full:
            let x = g.mac + (g.internet - g.mac) * CGFloat(u)
            point = CGPoint(x: x, y: g.y + offset)
            encrypted = x < g.server
        case .tunnel:
            point = CGPoint(x: g.mac + (g.server - g.mac) * CGFloat(u), y: g.y + offset)
            encrypted = true
        case .bypass:
            point = g.bypassRoutePoint(at: u, offset: offset)
            encrypted = false
        }

        let color = encrypted ? (outbound ? Theme.tunnel : Theme.tunnel.opacity(0.7)) : Theme.neutral
        dot(&context, at: point, radius: outbound ? 1.9 : 2.1, color: color, alpha: Self.edgeFade(raw))
    }

    /// During "Getting configuration" a dot travels back from the server to this Mac.
    private func drawConfigurationReturning(in context: inout GraphicsContext) {
        let u = Self.fraction(time / 0.9)
        let x = g.server - (g.server - g.mac) * CGFloat(u)
        dot(&context, at: CGPoint(x: x, y: g.y), radius: 3.4, color: Theme.tunnel, alpha: sin(Double.pi * u))
    }

    private func dot(_ context: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, alpha: Double) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(max(0, min(1, alpha)))))
    }

    private static func count(_ rate: Double, unit: Double, minimum: Double, maximum: Double, travel: Double) -> Int {
        let perSecond = min(max(rate / unit, minimum), maximum)
        return max(1, Int((perSecond * travel).rounded()))
    }

    private static func fraction(_ value: Double) -> Double {
        value - floor(value)
    }

    private static func edgeFade(_ u: Double) -> Double {
        min(1, u * 12, (1 - u) * 12)
    }

    /// A fixed pseudo-random offset per packet so they do not march in lockstep.
    private static func jitter(_ index: Int, outbound: Bool) -> Double {
        let value = sin(Double(index) * 12.9898 + (outbound ? 78.233 : 37.719)) * 43_758.5453
        return value - floor(value)
    }
}
