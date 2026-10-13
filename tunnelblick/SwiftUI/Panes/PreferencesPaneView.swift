//
//  PreferencesPaneView.swift
//  Tunnelblick
//
//  The "Preferences" pane. Mirrors the controls of the hidden legacy GeneralView and changes settings by clicking them
//  (see TBSwiftUIBridge.h), plus the switch back to the classic Tunnelblick windows ("useClassicInterface").
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct PreferencesPaneView: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared

    init() {}

    var body: some View {
        let _ = model.tick &+ refresh.revision
        PanesPage(title: L("Preferences"),
                  subtitle: L("Updates, administrator authorization, keyboard shortcut and other program-wide settings")) {
            if let view = TBSwiftUIBridge.legacyGeneralView() {
                updatesSection(view)
                configurationChangesSection(view)
                internetUseSection(view)
                keyboardAndLogSection(view)
                warningsSection(view)
            }
            screenLockSection()
            interfaceSection()
        }
        .onAppear {
            TBSwiftUIBridge.showLegacyPane("Preferences")
            LegacyRefresh.shared.bump()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func updatesSection(_ view: GeneralView) -> some View {
        let checkNow: NSButton? = PanesLegacy.outlet(view, "updatesCheckNowButton")
        let lastChecked = LegacyCheckboxState.clean(view.updatesLastCheckedTFC()?.title ?? "")
        PanesSection(PanesLegacy.label(view.updatesUpdatesTFC(), fallback: L("Tunnelblick updates:")),
                     help: PanesLegacy.help([
                        PanesHelpSource(nil, view.updatesCheckAutomaticallyCheckbox()),
                        PanesHelpSource(nil, view.updatesCheckOnlyWhenInVPNCheckbox()),
                        PanesHelpSource(nil, view.updatesCheckForBetaUpdatesCheckbox()),
                        PanesHelpSource(nil, view.updatesDownloadWhenAvailableCheckbox()),
                        PanesHelpSource(nil, checkNow),
                        PanesHelpSource(nil, view.updatesAdminApprovalForAppUpdatesCheckbox())
                     ])) {
            LegacyToggleRow(button: view.updatesCheckAutomaticallyCheckbox())
            LegacyToggleRow(button: view.updatesCheckOnlyWhenInVPNCheckbox())
            LegacyToggleRow(button: view.updatesCheckForBetaUpdatesCheckbox())
            LegacyToggleRow(button: view.updatesDownloadWhenAvailableCheckbox())
            if checkNow != nil {
                InsetRow(L("Check for updates now"), caption: lastChecked.isEmpty ? nil : lastChecked) {
                    LegacyButton(button: checkNow)
                }
            }
            LegacyToggleRow(button: view.updatesAdminApprovalForAppUpdatesCheckbox(), isLast: true)
        }
    }

    @ViewBuilder
    private func configurationChangesSection(_ view: GeneralView) -> some View {
        PanesSection(PanesLegacy.label(view.generalConfigurationChangesTFC(), fallback: L("Configuration changes:")),
                     help: PanesLegacy.help([
                        PanesHelpSource(nil, view.generalAdminApprovalForKeyAndCertificateChangesCheckbox())
                     ])) {
            LegacyToggleRow(button: view.generalAdminApprovalForKeyAndCertificateChangesCheckbox(), isLast: true)
        }
    }

    @ViewBuilder
    private func internetUseSection(_ view: GeneralView) -> some View {
        PanesSection(PanesLegacy.label(view.tbInternetAccessTFC(), fallback: L("Tunnelblick Internet Use:")),
                     help: PanesLegacy.help([
                        PanesHelpSource(nil, view.inhibitOutboundTBTrafficCheckbox())
                     ])) {
            LegacyToggleRow(button: view.inhibitOutboundTBTrafficCheckbox(), isLast: true)
        }
    }

    @ViewBuilder
    private func keyboardAndLogSection(_ view: GeneralView) -> some View {
        let shortcutLabel: NSTextFieldCell? = PanesLegacy.outlet(view, "keyboardShortcutTFC")
        let logSizeLabel: NSTextFieldCell?  = PanesLegacy.outlet(view, "maxLogDisplaySizeTFC")
        let shortcutTitle = PanesLegacy.label(shortcutLabel, fallback: L("Keyboard shortcut:"))
        let logSizeTitle  = PanesLegacy.label(logSizeLabel, fallback: L("Maximum log display size:"))
        PanesSection(L("Keyboard and log"),
                     help: PanesLegacy.help([
                        PanesHelpSource(shortcutTitle, view.keyboardShortcutButton()),
                        PanesHelpSource(logSizeTitle,  view.maximumLogSizeButton())
                     ])) {
            LegacyPopUpRow(title: shortcutTitle, popUp: view.keyboardShortcutButton())
            LegacyPopUpRow(title: logSizeTitle,  popUp: view.maximumLogSizeButton(), isLast: true)
        }
    }

    @ViewBuilder
    private func warningsSection(_ view: GeneralView) -> some View {
        let warningsLabel: NSTextFieldCell? = PanesLegacy.outlet(view, "warningsTFC")
        let resetButton: NSButton? = PanesLegacy.outlet(view, "resetDisabledWarningsButton")
        if resetButton != nil {
            PanesSection(PanesLegacy.label(warningsLabel, fallback: L("Warnings:")),
                         help: PanesLegacy.help([PanesHelpSource(nil, resetButton)])) {
                InsetRow(PanesLegacy.summary(resetButton) ?? L("Show the warnings you asked not to see again"),
                         isLast: true) {
                    LegacyButton(button: resetButton)
                }
            }
        }
    }

    // MARK: Screen lock

    private static let screenLockKey = "disconnectOnScreenLockAndDoNotReconnect"

    private var disconnectsOnScreenLock: Bool {
        gTbDefaults?.bool(forKey: Self.screenLockKey) ?? false
    }

    private var screenLockCanChange: Bool {
        gTbDefaults?.canChangeValue(forKey: Self.screenLockKey) ?? false
    }

    @ViewBuilder
    private func screenLockSection() -> some View {
        PanesSection(L("Screen lock")) {
            InsetRow(L("Disconnect when the screen locks and stay disconnected"),
                     caption: L("Also stays disconnected after the computer wakes from sleep. Reconnect from the menu when you need the VPN."),
                     isLast: true) {
                HStack(spacing: 6) {
                    if !screenLockCanChange {
                        LockedBadge()
                    }
                    Toggle("", isOn: Binding(
                        get: { disconnectsOnScreenLock },
                        set: { newValue in
                            guard newValue != disconnectsOnScreenLock else { return }
                            PanesLegacy.setPreference(NSNumber(value: newValue), forKey: Self.screenLockKey)
                            LegacyRefresh.shared.bump()
                        }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!screenLockCanChange)
                }
            }
            .opacity(screenLockCanChange ? 1 : 0.6)
        }
    }

    // MARK: Classic interface

    private var usesClassicInterface: Bool {
        !TBSwiftUIBridge.useNewInterface()
    }

    private var classicInterfaceCanChange: Bool {
        gTbDefaults?.canChangeValue(forKey: "useClassicInterface") ?? false
    }

    @ViewBuilder
    private func interfaceSection() -> some View {
        PanesSection(L("Windows")) {
            InsetRow(L("Use the classic Tunnelblick windows"),
                     caption: L("Takes effect the next time you open the VPN Details window."),
                     isLast: true) {
                HStack(spacing: 6) {
                    if !classicInterfaceCanChange {
                        LockedBadge()
                    }
                    Toggle("", isOn: Binding(
                        get: { usesClassicInterface },
                        set: { newValue in
                            guard newValue != usesClassicInterface else { return }
                            PanesLegacy.setPreference(NSNumber(value: newValue), forKey: "useClassicInterface")
                            LegacyRefresh.shared.bump()
                        }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!classicInterfaceCanChange)
                }
            }
            .opacity(classicInterfaceCanChange ? 1 : 0.6)
        }
    }
}
