//
//  UtilitiesPaneView.swift
//  Tunnelblick
//
//  The "Utilities" pane. Each utility clicks the corresponding button of the hidden legacy UtilitiesView, so the
//  original code does the work (and shows its own progress, results and dialogs). The two drastic ones
//  (Quit All OpenVPN Processes, Uninstall Tunnelblick) ask for confirmation inline first.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct UtilitiesPaneView: View {

    private enum Confirmation {
        case quitAllOpenVPN
        case uninstall
    }

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared
    @State private var confirming: Confirmation?

    init() {}

    var body: some View {
        let _ = model.tick &+ refresh.revision
        PanesPage(title: L("Utilities"),
                  subtitle: L("Tools for troubleshooting, backing up and removing Tunnelblick")) {
            if let view = TBSwiftUIBridge.legacyUtilitiesView() {
                troubleshootingSection(view)
                setupSection(view)
                systemExtensionsSection(view)
                tunnelblickSection(view)
            }
        }
        .onAppear {
            TBSwiftUIBridge.showLegacyPane("Utilities")
            LegacyRefresh.shared.bump()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func troubleshootingSection(_ view: UtilitiesView) -> some View {
        let quitAll = view.utilitiesQuitAllOpenVpnButton()
        let quitStatus = LegacyCheckboxState.clean(view.utilitiesQuitAllOpenVpnStatusTFC()?.title ?? "")
        let consoleLog = view.consoleLogToClipboardButton()
        let consoleLogBusy = !(view.consoleLogToClipboardProgressIndicator()?.isHidden ?? true)
        PanesSection(L("Troubleshooting"),
                     help: PanesLegacy.help([
                        PanesHelpSource(L("Quit All OpenVPN Processes"), quitAll),
                        PanesHelpSource(nil, consoleLog)
                     ])) {
            InsetRow(L("Quit All OpenVPN Processes"),
                     caption: quitStatus.isEmpty
                        ? (PanesLegacy.summary(quitAll) ?? L("Quits every OpenVPN process on this computer, including ones Tunnelblick did not start."))
                        : quitStatus) {
                quitAllControl(quitAll)
            }
            InsetRow(PanesLegacy.title(consoleLog) ?? L("Copy Console Log to Clipboard"),
                     caption: PanesLegacy.summary(consoleLog),
                     isLast: true) {
                HStack(spacing: 8) {
                    if consoleLogBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    LegacyButton(button: consoleLog, title: L("Copy"))
                }
            }
        }
    }

    @ViewBuilder
    private func setupSection(_ view: UtilitiesView) -> some View {
        let export = view.utilitiesExportTunnelblickSetupButton()
        let exportBusy = !(view.utilitiesExportTunnelblickSetupProgressIndicator()?.isHidden ?? true)
        let easyRsa = view.utilitiesRunEasyRsaButton()
        let easyRsaPathCell: NSTextFieldCell? = PanesLegacy.outlet(view, "utilitiesEasyRsaPathTFC")
        let easyRsaPath = LegacyCheckboxState.clean(easyRsaPathCell?.title ?? "")
        PanesSection(L("Setup"),
                     help: PanesLegacy.help([
                        PanesHelpSource(nil, export),
                        PanesHelpSource(nil, easyRsa)
                     ])) {
            InsetRow(PanesLegacy.title(export) ?? L("Export Tunnelblick Setup"),
                     caption: PanesLegacy.summary(export)) {
                HStack(spacing: 8) {
                    if exportBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    LegacyButton(button: export, title: L("Export…"))
                }
            }
            InsetRow(PanesLegacy.title(easyRsa) ?? L("Open easy-rsa in Terminal"),
                     caption: easyRsaPath.isEmpty ? PanesLegacy.summary(easyRsa) : easyRsaPath,
                     isLast: true) {
                LegacyButton(button: easyRsa, title: L("Open"))
            }
        }
    }

    @ViewBuilder
    private func systemExtensionsSection(_ view: UtilitiesView) -> some View {
        let kexts = view.utilitiesInstallKextsButton()
        let kextsTitle = PanesLegacy.title(kexts) ?? ""
        let isUninstall = kextsTitle == LegacyCheckboxState.clean(L("Uninstall tun and tap system extensions..."))
        if kexts != nil {
            PanesSection(L("System extensions"),
                         subtitle: L("Needed only by configurations that use Tunnelblick's tun or tap drivers"),
                         help: PanesLegacy.help([PanesHelpSource(nil, kexts)])) {
                InsetRow(kextsTitle,
                         caption: PanesLegacy.summary(kexts),
                         isLast: true) {
                    LegacyButton(button: kexts, title: isUninstall ? L("Uninstall…") : L("Install…"))
                }
            }
        }
    }

    @ViewBuilder
    private func tunnelblickSection(_ view: UtilitiesView) -> some View {
        let uninstall = view.utilitiesUninstallButton()
        PanesSection(L("Tunnelblick"),
                     help: PanesLegacy.help([PanesHelpSource(nil, uninstall)])) {
            InsetRow(PanesLegacy.title(uninstall) ?? L("Uninstall Tunnelblick..."),
                     caption: PanesLegacy.summary(uninstall),
                     isLast: true) {
                confirmingButton(uninstall, kind: .uninstall, title: L("Uninstall…"), confirmTitle: L("Uninstall"))
            }
        }
    }

    // MARK: Confirmation

    /// While OpenVPN processes are being quit, the legacy button becomes "Cancel"; that is clicked without confirmation.
    @ViewBuilder
    private func quitAllControl(_ button: NSButton?) -> some View {
        let legacyTitle = PanesLegacy.title(button) ?? ""
        if legacyTitle == LegacyCheckboxState.clean(L("Quit All OpenVPN Processes")) {
            confirmingButton(button, kind: .quitAllOpenVPN, title: L("Quit All…"), confirmTitle: L("Quit All"))
        } else {
            LegacyButton(button: button)
        }
    }

    @ViewBuilder
    private func confirmingButton(_ button: NSButton?, kind: Confirmation, title: String, confirmTitle: String) -> some View {
        let isAvailable = (button?.isEnabled ?? false) && !(button?.isHidden ?? true)
        if confirming == kind && isAvailable {
            HStack(spacing: 6) {
                Text(verbatim: L("Are you sure?"))
                    .font(Theme.rowCaption)
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(Theme.motion(Theme.quick)) {
                        confirming = nil
                    }
                } label: {
                    Text(verbatim: L("Cancel"))
                }
                LegacyButton(button: button, title: confirmTitle, role: .destructive) {
                    confirming = nil
                }
                .foregroundStyle(Theme.failure)
            }
            .transition(.opacity)
        } else {
            Button(role: .destructive) {
                withAnimation(Theme.motion(Theme.quick)) {
                    confirming = kind
                }
            } label: {
                Text(verbatim: title)
                    .foregroundStyle(isAvailable ? Theme.failure : Theme.faint)
            }
            .disabled(!isAvailable)
        }
    }
}
