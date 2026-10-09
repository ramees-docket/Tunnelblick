//
//  LoginPromptView.swift
//  Tunnelblick
//
//  The username/password prompt of the new interface (over LoginWindowController's hidden controls; see AuthPromptHost).
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct LoginPromptView: View {

    @ObservedObject var model: AuthPromptModel
    @FocusState private var focus: AuthPromptModel.Field?

    init(model: AuthPromptModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        let _ = model.revision      // Re-render when the hidden controls may have changed
        VStack(alignment: .leading, spacing: 16) {
            AuthPromptHeader(title: model.title, subtitle: model.subtitle, caption: model.groupCaption)

            form
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
        .onAppear { focus = model.focusTarget }
        .onChange(of: model.focusRequest) { _ in focus = model.focusTarget }
        .tbLayoutDirection()
    }

    private var form: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                fieldLabel(L("Username:"))
                TextField(L("Username:"), text: model.text(model.usernameField))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .focused($focus, equals: .username)
                    .onSubmit { model.connect() }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                checkbox(model.saveUsernameCheckbox)
            }
            GridRow {
                fieldLabel(L("Password:"))
                AuthSecretField(label: L("Password:"),
                                text: model.text(model.passwordField),
                                canReveal: model.canReveal,
                                field: .password,
                                focus: $focus,
                                onSubmit: { model.connect() })
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                checkbox(model.savePasswordCheckbox)
            }
            if model.showsSecurityToken {
                GridRow {
                    tokenCheckbox
                        .gridColumnAlignment(.trailing)
                    AuthSecretField(label: tokenTitle,
                                    text: model.text(model.tokenField),
                                    canReveal: model.tokenIsOn,
                                    field: .token,
                                    focus: $focus,
                                    onSubmit: { model.connect() })
                        .disabled(!model.tokenIsOn)
                        .opacity(model.tokenIsOn ? 1 : 0.5)
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .gridColumnAlignment(.trailing)
    }

    /// A checkbox that mirrors (and clicks) a hidden legacy checkbox. Its title is the legacy, already localized title.
    @ViewBuilder
    private func checkbox(_ button: NSButton?) -> some View {
        if let button, !button.isHidden {
            Toggle(isOn: model.checkbox(button)) {
                Text(verbatim: LegacyCheckboxState.clean(button.title))
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .disabled(!button.isEnabled)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private var tokenTitle: String {
        LegacyCheckboxState.clean(model.useTokenCheckbox?.title ?? L("Security code:"))
    }

    /// "Security code:" checkbox: enables the security code field (the code is added to the password and never saved).
    private var tokenCheckbox: some View {
        Toggle(isOn: model.checkbox(model.useTokenCheckbox)) {
            Text(verbatim: tokenTitle)
                .font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
        .disabled(!(model.useTokenCheckbox?.isEnabled ?? false))
        .onChange(of: model.tokenIsOn) { isOn in
            if isOn { focus = .token }
        }
    }
}
