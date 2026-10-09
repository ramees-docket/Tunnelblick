//
//  AdvancedSettingsSheet.swift
//  Tunnelblick
//
//  The "Advanced" settings of a configuration, presented as a sheet from the Settings tab. It mirrors the controls of the
//  hidden legacy SettingsSheetWindowController (whose window is loaded but never shown) and changes settings by clicking
//  them. Like the original window, changes apply to the configuration selected in the (hidden) configurations list.
//
//  The four tabs and the controls in each follow the original window (SettingsSheet.xib); the tab labels are the
//  original, localized tab labels. The selected tab is remembered in the "AdvancedWindowTabIdentifier" preference,
//  like the original window does.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct AdvancedSettingsSheet: View {

    let displayName: String

    enum AdvancedTab: String, CaseIterable, Identifiable {
        case connecting     = "connectingAndDisconnecting"
        case whileConnected = "whileConnected"
        case credentials    = "vpnCredentials"
        case sounds         = "sounds"

        var id: String { rawValue }
    }

    /// One row of the DNS/WINS grid on the "While Connected" tab.
    private struct DnsWinsRow: Identifiable {
        let id: String          // Outlet base name, e.g. "dnsServers"
        let fallbackTitle: String
    }

    private static let dnsWinsRows: [DnsWinsRow] = [
        DnsWinsRow(id: "dnsServers",   fallbackTitle: "DNS servers:"),
        DnsWinsRow(id: "domain",       fallbackTitle: "Domain:"),
        DnsWinsRow(id: "searchDomain", fallbackTitle: "Search domain:"),
        DnsWinsRow(id: "winsServers",  fallbackTitle: "WINS servers:"),
        DnsWinsRow(id: "netBiosName",  fallbackTitle: "NetBIOS name:"),
        DnsWinsRow(id: "workgroup",    fallbackTitle: "Workgroup:")
    ]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared

    @State private var controller: SettingsSheetWindowController?
    @State private var tab: AdvancedTab = .connecting
    @State private var savedTabIdentifier: String?
    @State private var newCredentialsName = ""

    init(displayName: String) {
        self.displayName = displayName
    }

    private var localizedName: String {
        let name = gMC?.localizedName(forDisplayName: displayName) ?? displayName
        return (name as NSString).lastPathComponent
    }

    var body: some View {
        let _ = model.tick &+ refresh.revision
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: LF("Advanced settings for “%@”", localizedName as NSString))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            if let controller {
                Picker(selection: tabBinding(controller)) {
                    ForEach(AdvancedTab.allCases) { item in
                        Text(verbatim: label(of: item, controller)).tag(item)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                ScrollView {
                    tabContent(controller)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 1)
                }
            } else {
                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(verbatim: L("Done"))
                        .frame(minWidth: 60)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 580)
        .tbLayoutDirection()
        .onAppear {
            load()
        }
        .onDisappear {
            saveSelectedTab()
        }
    }

    // MARK: Legacy controller and tabs

    private func load() {
        TBSwiftUIBridge.selectConfiguration(displayName: displayName)
        guard let legacy = TBSwiftUIBridge.legacyAdvancedForSelectedConfiguration() else {
            controller = nil
            return
        }
        let saved = gTbDefaults?.string(forKey: "AdvancedWindowTabIdentifier")
        let initialTab = saved.flatMap { AdvancedTab(rawValue: $0) } ?? .connecting
        selectLegacyTab(initialTab, legacy)
        savedTabIdentifier = saved
        tab = initialTab
        controller = legacy
        LegacyRefresh.shared.bump()
    }

    private func legacyTabItem(_ item: AdvancedTab, _ legacy: SettingsSheetWindowController) -> NSTabViewItem? {
        switch item {
        case .connecting:     return legacy.connectingAndDisconnectingTabViewItem()
        case .whileConnected: return legacy.whileConnectedTabViewItem()
        case .credentials:    return legacy.credentialsTabViewItem()
        case .sounds:         return legacy.soundTabViewItem()
        }
    }

    /// Keeps the hidden window's tab in step (the legacy code reads its selected tab when it is closed).
    private func selectLegacyTab(_ item: AdvancedTab, _ legacy: SettingsSheetWindowController) {
        guard let tabViewItem = legacyTabItem(item, legacy),
              let tabView = tabViewItem.tabView else {
            return
        }
        if tabView.selectedTabViewItem !== tabViewItem {
            tabView.selectTabViewItem(tabViewItem)
        }
    }

    private func tabBinding(_ legacy: SettingsSheetWindowController) -> Binding<AdvancedTab> {
        Binding(
            get: { tab },
            set: { newValue in
                selectLegacyTab(newValue, legacy)
                withAnimation(Theme.motion(Theme.quick)) {
                    tab = newValue
                }
                LegacyRefresh.shared.bump()
            })
    }

    private func label(of item: AdvancedTab, _ legacy: SettingsSheetWindowController) -> String {
        let legacyLabel = LegacyCheckboxState.clean(legacyTabItem(item, legacy)?.label ?? "")
        if !legacyLabel.isEmpty {
            return legacyLabel
        }
        switch item {
        case .connecting:     return L("Connecting & Disconnecting")
        case .whileConnected: return L("While Connected")
        case .credentials:    return L("VPN Credentials")
        case .sounds:         return L("Sounds")
        }
    }

    /// Same as -[SettingsSheetWindowController windowWillClose:]: remember the selected tab.
    private func saveSelectedTab() {
        guard let legacy = controller,
              let identifier = legacyTabItem(tab, legacy)?.identifier as? String,
              identifier != savedTabIdentifier else {
            return
        }
        PanesLegacy.setPreference(identifier, forKey: "AdvancedWindowTabIdentifier")
        savedTabIdentifier = identifier
    }

    @ViewBuilder
    private func tabContent(_ legacy: SettingsSheetWindowController) -> some View {
        switch tab {
        case .connecting:     connectingTab(legacy)
        case .whileConnected: whileConnectedTab(legacy)
        case .credentials:    credentialsTab(legacy)
        case .sounds:         soundsTab(legacy)
        }
    }

    // MARK: Connecting & Disconnecting

    @ViewBuilder
    private func connectingTab(_ legacy: SettingsSheetWindowController) -> some View {
        let flushDns: NSButton?           = PanesLegacy.outlet(legacy, "flushDnsCacheCheckbox")
        let prependDomain: NSButton?      = PanesLegacy.outlet(legacy, "prependDomainNameCheckbox")
        let routeUp: NSButton?            = PanesLegacy.outlet(legacy, "useRouteUpInsteadOfUpCheckbox")
        let allowManual: NSButton?        = PanesLegacy.outlet(legacy, "allowManualNetworkSettingsOverrideCheckbox")
        let ipv6OnTap: NSButton?          = PanesLegacy.outlet(legacy, "enableIpv6OnTapCheckbox")
        let keepConnected: NSButton?      = PanesLegacy.outlet(legacy, "keepConnectedCheckbox")
        let authenticate: NSButton?       = PanesLegacy.outlet(legacy, "authenticateOnConnectCheckbox")
        let switchOut: NSButton?          = PanesLegacy.outlet(legacy, "disconnectWhenUserSwitchesOutCheckbox")
        let switchIn: NSButton?           = PanesLegacy.outlet(legacy, "reconnectWhenUserSwitchesInCheckbox")
        let sleep: NSButton?              = PanesLegacy.outlet(legacy, "disconnectOnSleepCheckbox")
        let wake: NSButton?               = PanesLegacy.outlet(legacy, "reconnectOnWakeFromSleepCheckbox")
        let loadTun: NSPopUpButton?       = PanesLegacy.outlet(legacy, "loadTunPopUpButton")
        let loadTap: NSPopUpButton?       = PanesLegacy.outlet(legacy, "loadTapPopUpButton")
        let userSwitchBox: NSBox?         = PanesLegacy.outlet(legacy, "fastUserSwitchingBox")
        let sleepWakeBox: NSBox?          = PanesLegacy.outlet(legacy, "sleepWakeBox")
        let switchedOutNote: NSTextFieldCell? = PanesLegacy.outlet(legacy, "ifConnectedWhenUserSwitchedOutTFC")
        let wentToSleepNote: NSTextFieldCell? = PanesLegacy.outlet(legacy, "ifConnectedWhenComputerWentToSleepTFC")

        VStack(alignment: .leading, spacing: 18) {
            PanesSection(nil,
                         help: PanesLegacy.help([
                            PanesHelpSource(nil, flushDns),
                            PanesHelpSource(nil, prependDomain),
                            PanesHelpSource(nil, routeUp),
                            PanesHelpSource(nil, allowManual),
                            PanesHelpSource(nil, ipv6OnTap)
                         ])) {
                LegacyToggleRow(button: flushDns)
                LegacyToggleRow(button: prependDomain)
                LegacyToggleRow(button: routeUp)
                LegacyToggleRow(button: allowManual)
                LegacyToggleRow(button: ipv6OnTap, isLast: true)
            }

            PanesSection(nil,
                         help: PanesLegacy.help([
                            PanesHelpSource(nil, keepConnected),
                            PanesHelpSource(nil, authenticate)
                         ])) {
                LegacyToggleRow(button: keepConnected)
                LegacyToggleRow(button: authenticate, isLast: true)
            }

            PanesSection(boxTitle(userSwitchBox, fallback: L("Fast User Switching")),
                         help: PanesLegacy.help([
                            PanesHelpSource(nil, switchOut),
                            PanesHelpSource(nil, switchIn)
                         ])) {
                LegacyToggleRow(button: switchOut)
                LegacyToggleRow(button: switchIn,
                                caption: PanesLegacy.withoutParentheses(switchedOutNote?.title),
                                isLast: true)
            }

            PanesSection(boxTitle(sleepWakeBox, fallback: L("Computer sleep/wake")),
                         help: PanesLegacy.help([
                            PanesHelpSource(nil, sleep),
                            PanesHelpSource(nil, wake)
                         ])) {
                LegacyToggleRow(button: sleep)
                LegacyToggleRow(button: wake,
                                caption: PanesLegacy.withoutParentheses(wentToSleepNote?.title),
                                isLast: true)
            }

            PanesSection(L("Tun and tap drivers"),
                         help: PanesLegacy.help([
                            PanesHelpSource(L("Tun driver"), loadTun),
                            PanesHelpSource(L("Tap driver"), loadTap)
                         ])) {
                LegacyPopUpRow(title: L("Tun driver"), popUp: loadTun)
                LegacyPopUpRow(title: L("Tap driver"), popUp: loadTap, isLast: true)
            }
        }
    }

    private func boxTitle(_ box: NSBox?, fallback: String) -> String {
        let title = PanesLegacy.stripColon(box?.title ?? "")
        return title.isEmpty ? fallback : title
    }

    // MARK: While Connected

    @ViewBuilder
    private func whileConnectedTab(_ legacy: SettingsSheetWindowController) -> some View {
        let monitor: NSButton? = PanesLegacy.outlet(legacy, "monitorNetworkForChangesCheckbox")
        let mtuTest: NSButton? = PanesLegacy.outlet(legacy, "runMtuTestCheckbox")
        let settingHeader: NSTextField? = PanesLegacy.outlet(legacy, "networkSettingTF")
        let preVpnHeader: NSTextField?  = PanesLegacy.outlet(legacy, "whenChangesToPreVpnValueTF")
        let otherHeader: NSTextField?   = PanesLegacy.outlet(legacy, "whenChangesToAnythingElseTF")

        VStack(alignment: .leading, spacing: 18) {
            PanesSection(nil,
                         help: PanesLegacy.help([
                            PanesHelpSource(nil, monitor),
                            PanesHelpSource(nil, mtuTest)
                         ])) {
                LegacyToggleRow(button: monitor)
                LegacyToggleRow(button: mtuTest, isLast: true)
            }

            PanesSection(L("When network settings change"),
                         footer: L("Changes are watched for only while “Monitor network settings” is on.")) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text(verbatim: PanesLegacy.text(settingHeader, fallback: L("Network setting")))
                            .font(Theme.rowCaption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: PanesLegacy.text(preVpnHeader, fallback: L("When changes to pre-VPN value")))
                            .font(Theme.rowCaption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: PanesLegacy.text(otherHeader, fallback: L("When changes to anything else")))
                            .font(Theme.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    ForEach(Self.dnsWinsRows) { row in
                        GridRow {
                            Text(verbatim: dnsWinsTitle(row, legacy))
                                .font(Theme.rowTitle)
                            PanesPopUpMenu(popUp: PanesLegacy.outlet(legacy, row.id + "PopUpButton"))
                            PanesPopUpMenu(popUp: PanesLegacy.outlet(legacy, "other" + row.id + "PopUpButton"))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func dnsWinsTitle(_ row: DnsWinsRow, _ legacy: SettingsSheetWindowController) -> String {
        let cell: NSTextFieldCell? = PanesLegacy.outlet(legacy, row.id + "TFC")
        return PanesLegacy.label(cell, fallback: L(row.fallbackTitle))
    }

    // MARK: VPN Credentials

    @ViewBuilder
    private func credentialsTab(_ legacy: SettingsSheetWindowController) -> some View {
        let allUseSame = legacy.allConfigurationsUseTheSameCredentialsCheckbox()
        let groupPopUp = legacy.credentialsGroupButton() as? NSPopUpButton
        let addField: NSTextField? = PanesLegacy.outlet(legacy, "addNamedCredentialsTF")
        let addButton = legacy.addNamedCredentialsButton()
        let removePullDown = legacy.removeNamedCredentialsButton() as? NSPopUpButton
        let namedTitle = PanesLegacy.stripColon(legacy.namedCredentialsBox()?.title ?? "")

        VStack(alignment: .leading, spacing: 18) {
            PanesSection(nil,
                         help: PanesLegacy.help([PanesHelpSource(nil, allUseSame)])) {
                LegacyToggleRow(button: allUseSame, isLast: true)
            }

            PanesSection(namedTitle.isEmpty ? L("Named Credentials") : namedTitle) {
                LegacyPopUpRow(title: label(of: .credentials, legacy), popUp: groupPopUp)
                addCredentialsRow(legacy, field: addField, button: addButton)
                removeCredentialsRow(removePullDown)
            }
        }
    }

    private func canAddCredentials(field: NSTextField?) -> Bool {
        let name = newCredentialsName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (field?.isEnabled ?? false)
            && !name.isEmpty
            && name.count <= 200    // MAX_LENGTH_OF_CREDENTIALS_NAME
    }

    @ViewBuilder
    private func addCredentialsRow(_ legacy: SettingsSheetWindowController, field: NSTextField?, button: NSButton?) -> some View {
        if let field, let button {
            InsetRow(PanesLegacy.title(button) ?? L("Add Credentials")) {
                HStack(spacing: 6) {
                    TextField(L("Name"), text: $newCredentialsName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .disabled(!field.isEnabled)
                        .onSubmit {
                            addCredentials(legacy, field: field, button: button)
                        }
                    Button {
                        addCredentials(legacy, field: field, button: button)
                    } label: {
                        Text(verbatim: L("Add"))
                    }
                    .disabled(!canAddCredentials(field: field))
                }
            }
        }
    }

    /// Types the name into the hidden text field (and tells the controller, which enables its button), then clicks
    /// "Add Credentials". The legacy code validates the name and shows any error.
    private func addCredentials(_ legacy: SettingsSheetWindowController, field: NSTextField, button: NSButton) {
        guard canAddCredentials(field: field) else {
            return
        }
        let textDidChange = NSSelectorFromString("controlTextDidChange:")
        field.stringValue = newCredentialsName.trimmingCharacters(in: .whitespacesAndNewlines)
        if legacy.responds(to: textDidChange) {
            _ = legacy.perform(textDidChange, with: Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        TBSwiftUIBridge.click(button)
        field.stringValue = ""
        if legacy.responds(to: textDidChange) {
            _ = legacy.perform(textDidChange, with: Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        newCredentialsName = ""
        LegacyRefresh.shared.bump()
    }

    @ViewBuilder
    private func removeCredentialsRow(_ pullDown: NSPopUpButton?) -> some View {
        if let pullDown {
            // A pull-down button: the first item is its title ("Remove Credentials"), the others are the groups.
            let items = Array(pullDown.itemArray.dropFirst())
            let title = LegacyCheckboxState.clean(pullDown.itemArray.first?.title ?? "")
            InsetRow(title.isEmpty ? L("Remove Credentials") : title, isLast: true) {
                Menu {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button {
                            _ = TBSwiftUIBridge.perform(item)
                            LegacyRefresh.shared.bump()
                        } label: {
                            Text(verbatim: item.title)
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!pullDown.isEnabled || items.isEmpty)
                .accessibilityLabel(Text(verbatim: title.isEmpty ? L("Remove Credentials") : title))
            }
        }
    }

    // MARK: Sounds

    @ViewBuilder
    private func soundsTab(_ legacy: SettingsSheetWindowController) -> some View {
        let boxTitle = PanesLegacy.stripColon(legacy.alertSoundsBox()?.title ?? "")
        PanesSection(boxTitle.isEmpty ? L("Alert sounds") : boxTitle) {
            LegacyPopUpRow(title: PanesLegacy.label(legacy.connectionAlertSoundTFC(), fallback: L("Connection:")),
                           popUp: legacy.soundOnConnectButton() as? NSPopUpButton)
            LegacyPopUpRow(title: PanesLegacy.label(legacy.disconnectionAlertSoundTFC(), fallback: L("Unexpected disconnection:")),
                           popUp: legacy.soundOnDisconnectButton() as? NSPopUpButton,
                           isLast: true)
        }
    }
}
