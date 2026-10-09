//
//  DetailsContentView.swift
//  Tunnelblick
//
//  The right side of the VPN Details window: a configuration (header, Route card, Overview / Log / Settings tabs and
//  the bottom bar), one of the Tunnelblick panes, or an empty state.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DetailsContentView: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var navigation = DetailsNavigation.shared

    init() {}

    var body: some View {
        Group {
            switch navigation.selection {
            case .configuration(let displayName)?:
                if model.displayNames.contains(displayName) {
                    ConfigurationDetailView(displayName: displayName)
                        .id(displayName)
                } else {
                    NoSelectionView()
                }
            case .pane(let pane)?:
                paneView(pane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case nil:
                if model.displayNames.isEmpty {
                    NoConfigurationsView()
                } else {
                    NoSelectionView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .tbLayoutDirection()
    }

    @ViewBuilder
    private func paneView(_ pane: DetailsPane) -> some View {
        switch pane {
        case .appearance:  AppearancePaneView()
        case .preferences: PreferencesPaneView()
        case .utilities:   UtilitiesPaneView()
        case .info:        InfoPaneView()
        }
    }
}

// MARK: - Configuration

struct ConfigurationDetailView: View {

    let displayName: String

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var navigation = DetailsNavigation.shared
    @StateObject private var live: ConfigurationLiveModel

    init(displayName: String) {
        self.displayName = displayName
        _live = StateObject(wrappedValue: ConfigurationLiveModel(displayName: displayName))
    }

    var body: some View {
        let snapshot = model.snapshots[displayName]
        VStack(spacing: 0) {
            ConfigurationHeaderView(displayName: displayName, snapshot: snapshot, live: live)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 12)

            RouteCardView(displayName: displayName, snapshot: snapshot, live: live)
                .padding(.horizontal, 22)

            Picker(selection: Binding(get: { navigation.tab }, set: { navigation.setTab($0) })) {
                ForEach(ConfigurationTab.allCases) { tab in
                    Text(verbatim: tab.title).tag(tab)
                }
            } label: {
                Text(verbatim: L("Configuration views"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)
            .padding(.bottom, 10)

            tabContent(snapshot: snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            ConfigurationBottomBar(snapshot: snapshot)
        }
        .onAppear {
            live.start(snapshot: model.snapshots[displayName])
        }
        .onChange(of: model.tick) { _ in
            live.tick(snapshot: model.snapshots[displayName])
        }
        .onChange(of: snapshot?.state) { _ in
            live.stateChanged(snapshot: model.snapshots[displayName])
        }
    }

    @ViewBuilder
    private func tabContent(snapshot: ConnectionSnapshot?) -> some View {
        switch navigation.tab {
        case .overview:
            ScrollView {
                OverviewTabView(displayName: displayName, snapshot: snapshot, live: live)
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .padding(.bottom, 18)
            }
        case .log:
            LogTabView(displayName: displayName)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
        case .settings:
            ScrollView {
                ConfigurationSettingsView(displayName: displayName)
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .padding(.bottom, 18)
            }
        }
    }
}

// MARK: - Header

struct ConfigurationHeaderView: View {
    let displayName: String
    let snapshot: ConnectionSnapshot?
    @ObservedObject var live: ConfigurationLiveModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TunnelTile(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(verbatim: snapshot?.localizedName ?? (displayName as NSString).lastPathComponent)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    SharingBadge(isShared: snapshot?.isShared ?? false, isDeployed: snapshot?.isDeployed ?? false)
                }
                Text(verbatim: subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Button {
                ConfigurationActions.showActionsMenu()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.groupBackground))
                    .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L("Configuration actions"))
            .accessibilityLabel(Text(verbatim: L("Configuration actions")))

            ConnectButton(displayName: displayName, snapshot: snapshot)
        }
    }

    /// "Work · OpenVPN · UDP 1194 · Office.tblk"
    private var subtitle: String {
        var parts: [String] = []
        let folder = (displayName as NSString).deletingLastPathComponent
        if !folder.isEmpty {
            parts.append(folder)
        }
        parts.append("OpenVPN")
        if live.fileInfo.fileName != nil {
            parts.append(live.fileInfo.protocolAndPort)
        }
        if let fileName = live.fileInfo.fileName {
            parts.append(fileName)
        }
        return parts.joined(separator: " · ")
    }
}

struct SharingBadge: View {
    let isShared: Bool
    let isDeployed: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isShared || isDeployed ? "person.2" : "person")
                .font(.system(size: 9.5, weight: .medium))
            Text(verbatim: isShared || isDeployed ? L("All users") : L("Only me"))
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .help(isShared || isDeployed
              ? L("This configuration is available to all users of this Mac")
              : L("This configuration is available only to you"))
    }
}

/// Connect, Disconnect, or Cancel (while connecting). Both disconnect paths use the same code as the original window.
struct ConnectButton: View {
    let displayName: String
    let snapshot: ConnectionSnapshot?

    private enum Kind {
        case connect, disconnect, cancel
    }

    var body: some View {
        let resolved = resolve()
        let kind = resolved.kind
        Group {
            if kind == .connect {
                Button {
                    AppModel.shared.connect(displayName)
                } label: {
                    Text(verbatim: L("Connect"))
                        .frame(minWidth: 92)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    AppModel.shared.disconnect(displayName)
                } label: {
                    Text(verbatim: kind == .cancel ? L("Cancel") : L("Disconnect"))
                        .frame(minWidth: 92)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(!resolved.enabled)
    }

    private func resolve() -> (kind: Kind, enabled: Bool) {
        guard let snapshot else { return (.connect, false) }
        switch snapshot.status {
        case .connected:
            return (.disconnect, snapshot.canDisconnect)
        case .connecting, .waitingForCredentials:
            return (.cancel, snapshot.canDisconnect)
        case .disconnecting:
            return (.disconnect, false)
        case .disconnected, .authFailed:
            return (.connect, snapshot.canConnect)
        }
    }
}

// MARK: - Bottom bar

struct ConfigurationBottomBar: View {
    let snapshot: ConnectionSnapshot?

    var body: some View {
        HStack(spacing: 10) {
            HelpButton {
                ConfigurationActions.showHelp()
            }
            .frame(width: 22, height: 22)
            DiagnosticInfoButton()
            Spacer(minLength: 8)
            if let snapshot {
                Text(verbatim: snapshot.isDeployed
                     ? L("Deployed configuration")
                     : (snapshot.isShared ? L("Shared configuration") : L("Private configuration")))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
    }
}

/// "Copy Diagnostic Info to Clipboard": clicks the legacy button (which reads the log of the selected configuration)
/// and shows a spinner while the legacy progress indicator is visible.
struct DiagnosticInfoButton: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared

    init() {}

    var body: some View {
        let _ = model.tick + refresh.revision
        let view = ConfigurationActions.legacyConfigurationsView()
        let isEnabled = view?.diagnosticInfoToClipboardButton()?.isEnabled ?? false
        let isWorking = !(view?.diagnosticInfoToClipboardProgressIndicator()?.isHidden ?? true)
        HStack(spacing: 6) {
            Button {
                ConfigurationActions.copyDiagnosticInfo()
            } label: {
                Label {
                    Text(verbatim: L("Copy Diagnostic Info to Clipboard"))
                } icon: {
                    Image(systemName: "doc.on.clipboard")
                }
            }
            .disabled(!isEnabled)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

/// The round "?" help button.
struct HelpButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.buttonWasClicked(_:)))
        button.bezelStyle = .helpButton
        button.setAccessibilityLabel(L("Help"))
        button.toolTip = L("Help")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonWasClicked(_ sender: Any?) {
            action()
        }
    }
}

// MARK: - Empty states

struct NoConfigurationsView: View {
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            TunnelTile(size: 64)
            Text(verbatim: L("No VPN configurations"))
                .font(.system(size: 20, weight: .semibold))
            Text(verbatim: L("Drop a .tblk, .ovpn, or .conf file from your network manager or VPN provider onto this window, or import one."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    ConfigurationActions.importConfigurationFiles()
                } label: {
                    Text(verbatim: L("Import…"))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    ConfigurationActions.addConfiguration()
                } label: {
                    Text(verbatim: (L("Add a Configuration") + "…"))
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.top, 4)
            Label {
                Text(verbatim: L("Drop files here to install them"))
            } icon: {
                Image(systemName: "arrow.down.doc")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.tunnel, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .padding(16)
                .opacity(isDropTargeted ? 1 : 0)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            ConfigurationActions.handleDrop(providers)
        }
    }
}

struct NoSelectionView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(verbatim: L("Choose a configuration"))
                .font(.system(size: 17, weight: .semibold))
            Text(verbatim: L("Select a configuration in the sidebar to see its connection, log and settings."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
