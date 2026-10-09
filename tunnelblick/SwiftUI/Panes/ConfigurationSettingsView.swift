//
//  ConfigurationSettingsView.swift
//  Tunnelblick
//
//  The per-configuration "Settings" tab of the VPN Details window. It mirrors the controls of the hidden legacy
//  Settings tab (ConfigurationsView) and changes settings by clicking them, so all the original rules apply
//  (forced preferences, admin authorization, dependent controls, "When computer starts" checks...).
//
//  This view has no scroll view of its own: the VPN Details window hosts it inside its scrolling content.
//  The Advanced sheet (AdvancedSettingsSheet) is presented from here.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct ConfigurationSettingsView: View {

    let displayName: String

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared
    @State private var showingAdvanced = false

    init(displayName: String) {
        self.displayName = displayName
    }

    var body: some View {
        let _ = model.tick &+ refresh.revision
        VStack(alignment: .leading, spacing: 18) {
            if let view = TBSwiftUIBridge.legacyDetails()?.configurationsPrefsView() {
                connectingSection(view)
                networkSection(view)
                disconnectingSection(view)
                advancedSection(view)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .tbLayoutDirection()
        .onAppear {
            prepareLegacyControls()
        }
        .onChange(of: displayName) { _ in
            showingAdvanced = false
            prepareLegacyControls()
        }
        .sheet(isPresented: $showingAdvanced) {
            AdvancedSettingsSheet(displayName: displayName)
        }
    }

    /// The hidden legacy controller must show this configuration's Settings tab: that is what its controls apply to.
    private func prepareLegacyControls() {
        TBSwiftUIBridge.showLegacyPane("Configurations")
        TBSwiftUIBridge.selectConfiguration(displayName: displayName)
        TBSwiftUIBridge.selectLogTab(false)
        LegacyRefresh.shared.bump()
    }

    private var localizedName: String {
        let name = gMC?.localizedName(forDisplayName: displayName) ?? displayName
        return (name as NSString).lastPathComponent
    }

    // MARK: Sections

    @ViewBuilder
    private func connectingSection(_ view: ConfigurationsView) -> some View {
        let versionLabel: NSTextFieldCell? = PanesLegacy.outlet(view, "perConfigOpenvpnVersionTFC")
        let connectTitle = PanesLegacy.label(view.whenToConnectTFC(), fallback: L("Connect:"))
        let versionTitle = PanesLegacy.label(versionLabel, fallback: L("OpenVPN version:"))
        let logTitle     = PanesLegacy.label(view.loggingLevelTFC(), fallback: L("VPN log level:"))
        PanesSection(L("Connecting"),
                     subtitle: LF("When and how %@ connects", localizedName as NSString),
                     help: PanesLegacy.help([
                        PanesHelpSource(connectTitle, view.whenToConnectPopUpButton()),
                        PanesHelpSource(versionTitle, view.perConfigOpenvpnVersionButton()),
                        PanesHelpSource(logTitle,     view.loggingLevelPopUpButton())
                     ])) {
            LegacyPopUpRow(title: connectTitle, popUp: view.whenToConnectPopUpButton())
            LegacyPopUpRow(title: versionTitle, popUp: view.perConfigOpenvpnVersionButton())
            LegacyPopUpRow(title: logTitle,     popUp: view.loggingLevelPopUpButton(), isLast: true)
        }
    }

    @ViewBuilder
    private func networkSection(_ view: ConfigurationsView) -> some View {
        let dnsTitle = PanesLegacy.label(view.setNameserverTFC(), fallback: L("Set DNS/WINS:"))
        PanesSection(L("Network"),
                     subtitle: L("Which traffic and DNS lookups use the VPN"),
                     help: PanesLegacy.help([
                        PanesHelpSource(dnsTitle, view.setNameserverPopUpButton()),
                        PanesHelpSource(nil, view.monitorNetworkForChangesCheckbox()),
                        PanesHelpSource(nil, view.routeAllTrafficThroughVpnCheckbox()),
                        PanesHelpSource(nil, view.disableIpv6OnTunCheckbox()),
                        PanesHelpSource(nil, view.disableSecondaryNetworkServicesCheckbox()),
                        PanesHelpSource(nil, view.checkIPAddressAfterConnectOnAdvancedCheckbox())
                     ])) {
            LegacyPopUpRow(title: dnsTitle, popUp: view.setNameserverPopUpButton())
            LegacyToggleRow(button: view.monitorNetworkForChangesCheckbox())
            LegacyToggleRow(button: view.routeAllTrafficThroughVpnCheckbox())
            LegacyToggleRow(button: view.disableIpv6OnTunCheckbox())
            LegacyToggleRow(button: view.disableSecondaryNetworkServicesCheckbox())
            LegacyToggleRow(button: view.checkIPAddressAfterConnectOnAdvancedCheckbox(), isLast: true)
        }
    }

    @ViewBuilder
    private func disconnectingSection(_ view: ConfigurationsView) -> some View {
        let expectedTitle   = PanesLegacy.label(view.uponDisconnectTFC(), fallback: L("On expected disconnect:"))
        let unexpectedTitle = PanesLegacy.label(view.uponUnexpectedDisconnectTFC(), fallback: L("On unexpected disconnect:"))
        PanesSection(L("Disconnecting"),
                     help: PanesLegacy.help([
                        PanesHelpSource(expectedTitle,   view.uponDisconnectPopUpButton()),
                        PanesHelpSource(unexpectedTitle, view.uponUnexpectedDisconnectPopUpButton())
                     ])) {
            LegacyPopUpRow(title: expectedTitle,   popUp: view.uponDisconnectPopUpButton())
            LegacyPopUpRow(title: unexpectedTitle, popUp: view.uponUnexpectedDisconnectPopUpButton(), isLast: true)
        }
    }

    @ViewBuilder
    private func advancedSection(_ view: ConfigurationsView) -> some View {
        let button = view.advancedButton()
        let buttonTitle = PanesLegacy.title(button) ?? L("Advanced...")
        let enabled = (button?.isEnabled ?? false)
            && !(button?.isHidden ?? true)
            && TBSwiftUIBridge.selectedConnection() != nil
        PanesSection(nil,
                     help: PanesLegacy.help([PanesHelpSource(PanesLegacy.stripColon(buttonTitle), button)])) {
            InsetRow(L("Advanced settings"),
                     caption: PanesLegacy.summary(button),
                     isLast: true) {
                HStack(spacing: 6) {
                    if !enabled, button != nil {
                        LockedBadge()
                    }
                    Button {
                        showingAdvanced = true
                    } label: {
                        Text(verbatim: buttonTitle)
                    }
                    .disabled(!enabled)
                }
            }
        }
    }
}
