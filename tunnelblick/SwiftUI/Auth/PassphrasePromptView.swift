//
//  PassphrasePromptView.swift
//  Tunnelblick
//
//  The private key passphrase prompt of the new interface (over PassphraseWindowController's hidden controls; see
//  AuthPromptHost).
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct PassphrasePromptView: View {

    @ObservedObject var model: AuthPromptModel
    @FocusState private var focus: AuthPromptModel.Field?

    init(model: AuthPromptModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        let _ = model.revision      // Re-render when the hidden controls may have changed
        VStack(alignment: .leading, spacing: 16) {
            AuthPromptHeader(title: model.title, subtitle: model.subtitle, caption: model.groupCaption, badge: "key.fill")

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: L("Passphrase:"))
                    .font(.system(size: 13))
                AuthSecretField(label: L("Passphrase:"),
                                text: model.text(model.passphraseField),
                                canReveal: model.canReveal,
                                field: .passphrase,
                                focus: $focus,
                                onSubmit: { model.connect() })
                saveCheckbox
            }
            .modifier(AuthShakeEffect(animatableData: model.shakes))

            if let problem = model.problem {
                AuthProblemLine(text: problem)
            }

            AuthPromptButtons(model: model)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: AuthPromptModel.width, alignment: .topLeading)
        .background(Theme.windowBackground)
        .onAppear { focus = .passphrase }
        .onChange(of: model.focusRequest) { _ in focus = model.focusTarget }
        .tbLayoutDirection()
    }

    /// "Save in Keychain": mirrors (and clicks) the hidden legacy checkbox, which is disabled for configurations that
    /// connect when the computer starts.
    @ViewBuilder
    private var saveCheckbox: some View {
        if let button = model.savePassphraseCheckbox, !button.isHidden {
            Toggle(isOn: model.checkbox(button)) {
                Text(verbatim: LegacyCheckboxState.clean(button.title))
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .disabled(!button.isEnabled)
        }
    }
}
