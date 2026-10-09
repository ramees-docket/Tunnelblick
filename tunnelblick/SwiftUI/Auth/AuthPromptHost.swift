//
//  AuthPromptHost.swift
//  Tunnelblick
//
//  SwiftUI skin for the login (username/password) and passphrase prompts.
//
//  LoginWindowController and PassphraseWindowController still load their nibs and keep all of their logic: prefill from
//  the Keychain, checkbox rules, validation, stopModal/abortModal, and the values AuthAgent reads afterwards. When the new
//  interface is in use, -awakeFromNib calls +[TBAuthPromptHost installInController:], which puts a SwiftUI view over the
//  window's whole content. The original content view stays in the window (hidden), so its controls keep their state:
//
//   * Text fields write through to the hidden NSTextField/NSSecureTextField on every keystroke.
//   * Checkboxes mirror the hidden checkboxes and change them with TBSwiftUIBridge.click (so their actions run).
//   * "Connect" sends the controller's OKButtonWasClicked:, "Cancel" its cancelButtonWasClicked:.
//   * When validation fails, the controller calls +shakeController: and the SwiftUI form shakes.
//
//  The prompts run inside -[NSApp runModalForWindow:], so nothing here depends on the default run loop mode
//  (timers are added in the common modes).
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

@objc(TBAuthPromptHost)
@MainActor
final class AuthPromptHost: NSObject {

    /// One host per controller (controllers are reused for later prompts). Weak keys: entries go away with the controller.
    private static let hosts = NSMapTable<NSWindowController, AuthPromptHost>.weakToStrongObjects()

    let model: AuthPromptModel
    private let hostingController: NSHostingController<AnyView>

    private init(model: AuthPromptModel, rootView: AnyView) {
        self.model = model
        self.hostingController = NSHostingController(rootView: rootView)
        super.init()
    }

    // MARK: Called from Objective-C

    /// Called from -awakeFromNib of LoginWindowController or PassphraseWindowController (new interface only).
    @objc(installInController:)
    static func install(in controller: NSWindowController) {
        guard hosts.object(forKey: controller) == nil,
              let window = controller.window,
              let originalContent = window.contentView else {
            return
        }

        let model: AuthPromptModel
        let root: AnyView
        if controller is LoginWindowController {
            model = AuthPromptModel(controller: controller, kind: .login)
            root = AnyView(LoginPromptView(model: model))
        } else if controller is PassphraseWindowController {
            model = AuthPromptModel(controller: controller, kind: .passphrase)
            root = AnyView(PassphrasePromptView(model: model))
        } else {
            return
        }

        let host = AuthPromptHost(model: model, rootView: root)
        hosts.setObject(host, forKey: controller)

        // The legacy buttons must not answer Return/Esc any more: the SwiftUI buttons do.
        model.okButton?.keyEquivalent = ""
        model.cancelButton?.keyEquivalent = ""

        // Keep the original content view (and all of its controls) in the window, hidden.
        let container = NSView(frame: originalContent.frame)
        window.contentView = container
        originalContent.isHidden = true
        container.addSubview(originalContent)

        let hostingView = host.hostingController.view
        host.hostingController.sizingOptions = []
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        host.fitWindow(window)
    }

    /// Called at the end of -redisplay (the window has just been shown, prefilled, or reset for another prompt).
    @objc(controllerDidRedisplay:)
    static func controllerDidRedisplay(_ controller: NSWindowController) {
        guard let host = hosts.object(forKey: controller), let window = controller.window else { return }
        host.fitWindow(window)
        window.center()
        // -redisplay selects one of the hidden legacy fields; give the keyboard to the SwiftUI form instead.
        let hostingView = host.hostingController.view
        window.initialFirstResponder = hostingView
        window.makeFirstResponder(hostingView)
        host.model.didRedisplay()
    }

    /// Called by the controller instead of +[UIHelper shakeWindow:] when OK is pressed but the input is not valid.
    /// Returns NO if no SwiftUI prompt is installed (the caller then shakes the window as before).
    @objc(shakeController:)
    static func shake(_ controller: NSWindowController) -> Bool {
        guard let host = hosts.object(forKey: controller) else { return false }
        host.model.shake()
        return true
    }

    // MARK: Private

    private func fitWindow(_ window: NSWindow) {
        model.reload()
        let size = hostingController.sizeThatFits(in: CGSize(width: AuthPromptModel.width, height: 2000))
        let height = max(120, ceil(size.height))
        let current = window.contentRect(forFrameRect: window.frame).size
        if abs(current.width - AuthPromptModel.width) > 0.5 || abs(current.height - height) > 0.5 {
            window.setContentSize(NSSize(width: AuthPromptModel.width, height: height))
        }
    }
}

// MARK: - Model

/// Reads and changes the hidden legacy controls of one prompt window.
@MainActor
final class AuthPromptModel: ObservableObject {

    enum Kind { case login, passphrase }
    enum Field: Hashable { case username, password, token, passphrase }

    static let width: CGFloat = 440

    let kind: Kind
    private weak var controller: NSWindowController?

    @Published private(set) var revision = 0
    @Published private(set) var shakes: CGFloat = 0
    @Published private(set) var problem: String?
    @Published private(set) var focusRequest = 0
    private(set) var focusTarget: Field

    init(controller: NSWindowController, kind: Kind) {
        self.controller = controller
        self.kind = kind
        self.focusTarget = (kind == .login) ? .username : .passphrase
    }

    // MARK: Legacy controls

    private var login: LoginWindowController? { controller as? LoginWindowController }
    private var passphraseController: PassphraseWindowController? { controller as? PassphraseWindowController }

    private func outlet<T>(_ key: String) -> T? {
        controller?.value(forKey: key) as? T
    }

    var okButton: NSButton?     { outlet("OKButton") }
    var cancelButton: NSButton? { outlet("cancelButton") }

    var usernameField: NSTextField?   { login?.username() }
    var passwordField: NSTextField?   { login?.password() }
    var tokenField: NSTextField?      { login?.securityToken() }
    var passphraseField: NSTextField? { passphraseController?.passphrase() }

    var saveUsernameCheckbox: NSButton?   { login?.saveUsernameInKeychainCheckbox() }
    var savePasswordCheckbox: NSButton?   { login?.savePasswordInKeychainCheckbox() }
    // KVC on an outlet the controller does not have would raise NSUndefinedKeyException, so check the kind first.
    var useTokenCheckbox: NSButton?       { kind == .login      ? outlet("useSecurityTokenCheckbox") : nil }
    var savePassphraseCheckbox: NSButton? { kind == .passphrase ? outlet("saveInKeychainCheckbox")   : nil }

    private var eyeButton: NSButton? {
        switch kind {
        case .login:      return login?.eyeButton()
        case .passphrase: return passphraseController?.eyeButton()
        }
    }

    private var securityTokenView: NSView? { kind == .login ? outlet("securityTokenView") : nil }

    private var agent: AuthAgent? {
        switch kind {
        case .login:      return login?.delegate() as? AuthAgent
        case .passphrase: return passphraseController?.delegate() as? AuthAgent
        }
    }

    // MARK: Values for the views

    var displayName: String { agent?.displayName() ?? "" }

    var localName: String {
        let name = displayName
        guard !name.isEmpty else { return "" }
        return gMC?.localizedName(forDisplayName: name) ?? name
    }

    /// The VPN server from the configuration file, if it can be read (shared configurations may not be readable).
    /// Read once per configuration: the views ask for it on every keystroke.
    var server: String? {
        let name = displayName
        if let cached = serverCache, cached.displayName == name { return cached.server }
        var server: String? = nil
        if !name.isEmpty, let path = AppModel.shared.configurationPath(for: name) {
            let host = ConfigurationFileInfo.read(configurationPath: path).remoteHost
            server = (host?.isEmpty ?? true) ? nil : host
        }
        serverCache = (name, server)
        return server
    }

    private var serverCache: (displayName: String, server: String?)?

    /// "using Work credentials." when the configuration uses named (group) credentials.
    var groupCaption: String? {
        guard !displayName.isEmpty, let group = credentialsGroupFromDisplayName(displayName), !group.isEmpty else { return nil }
        return LF("\nusing %@ credentials.", group).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var title: String {
        switch kind {
        case .login:      return LF("Connect to %@", localName)
        case .passphrase: return LF("Enter the passphrase for %@", localName)
        }
    }

    var subtitle: String {
        switch kind {
        case .login:
            if let server { return LF("Enter your username and password for %@.", server) }
            return L("Enter your username and password.")
        case .passphrase:
            return L("The private key of this configuration is protected with a passphrase.")
        }
    }

    /// The token row is hidden by the "-loginWindowSecurityTokenIsHidden" preference (the controller hides its view).
    var showsSecurityToken: Bool {
        guard kind == .login, let view = securityTokenView, useTokenCheckbox != nil else { return false }
        return !view.isHidden
    }

    var tokenIsOn: Bool { useTokenCheckbox?.state == .on }

    /// The legacy window lets the user reveal a password only when it did not come from the Keychain.
    var canReveal: Bool { !(eyeButton?.isHidden ?? true) }

    var buttonsEnabled: Bool { okButton?.isEnabled ?? true }

    // MARK: Bindings

    func text(_ field: NSTextField?) -> Binding<String> {
        Binding(
            get: { field?.stringValue ?? "" },
            set: { [weak self] newValue in
                guard let field, field.stringValue != newValue else { return }
                field.stringValue = newValue        // Write through on every keystroke
                self?.problem = nil
                self?.objectWillChange.send()
            })
    }

    func checkbox(_ button: NSButton?) -> Binding<Bool> {
        Binding(
            get: { button?.state == .on },
            set: { [weak self] newValue in
                guard let button, (button.state == .on) != newValue else { return }
                TBSwiftUIBridge.click(button)       // Runs the controller's action (dependent checkboxes, token field)
                self?.reload()
            })
    }

    // MARK: Actions

    func connect() {
        guard let controller, buttonsEnabled else { return }
        controller.perform(NSSelectorFromString("OKButtonWasClicked:"), with: nil)
        reload()
    }

    func cancel() {
        guard let controller, cancelButton?.isEnabled ?? true else { return }
        controller.perform(NSSelectorFromString("cancelButtonWasClicked:"), with: nil)
        reload()
    }

    func reload() {
        revision &+= 1
    }

    func shake() {
        switch kind {
        case .login:
            problem = (usernameField?.stringValue ?? "").isEmpty ? L("Enter your username.") : L("The username, password or security code is too long.")
        case .passphrase:
            problem = (passphraseField?.stringValue ?? "").isEmpty ? L("Enter the passphrase.") : L("The passphrase is too long.")
        }
        reload()
        guard !Theme.reduceMotion else { return }
        withAnimation(.linear(duration: 0.5)) {
            shakes += 1
        }
    }

    func didRedisplay() {
        problem = nil
        reload()
        // AuthAgent clears the passphrase field just after -redisplay, and -redisplay may move the keyboard focus to a
        // hidden field; look again a moment later. (A common-modes timer, because the prompt runs in a modal session.)
        let timer = Timer(timeInterval: 0.05, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.focusFirstEmptyField() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func focusFirstEmptyField() {
        switch kind {
        case .login:
            if (usernameField?.stringValue ?? "").isEmpty {
                focusTarget = .username
            } else if (passwordField?.stringValue ?? "").isEmpty || !(showsSecurityToken && tokenIsOn) {
                focusTarget = .password
            } else {
                focusTarget = .token
            }
        case .passphrase:
            focusTarget = .passphrase
        }
        reload()
        focusRequest &+= 1
    }
}

// MARK: - Shared pieces

/// Horizontal shake, like the original +[UIHelper shakeWindow:] but for the form only.
struct AuthShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = 9 * sin(animatableData * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// Icon, title and explanation at the top of a prompt.
struct AuthPromptHeader: View {
    let title: String
    let subtitle: String
    let caption: String?
    var badge: String? = nil        // SF Symbol shown on the app icon

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 4, y: 4)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(verbatim: caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The red message under the form after a failed validation.
struct AuthProblemLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.failure)
        .accessibilityElement(children: .combine)
    }
}

/// Cancel and Connect. Return = Connect, Esc = Cancel.
struct AuthPromptButtons: View {
    @ObservedObject var model: AuthPromptModel

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            Button {
                model.cancel()
            } label: {
                Text(verbatim: L("Cancel"))
                    .frame(minWidth: 64)
            }
            .keyboardShortcut(.cancelAction)
            .disabled(!(model.cancelButton?.isEnabled ?? true))

            Button {
                model.connect()
            } label: {
                Text(verbatim: L("Connect"))
                    .frame(minWidth: 64)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.buttonsEnabled)
        }
        .controlSize(.large)
    }
}

/// A secure field with an optional "show" button.
struct AuthSecretField: View {
    let label: String
    let text: Binding<String>
    let canReveal: Bool
    let field: AuthPromptModel.Field
    var focus: FocusState<AuthPromptModel.Field?>.Binding
    let onSubmit: () -> Void

    @State private var revealed = false

    init(label: String,
         text: Binding<String>,
         canReveal: Bool,
         field: AuthPromptModel.Field,
         focus: FocusState<AuthPromptModel.Field?>.Binding,
         onSubmit: @escaping () -> Void) {
        self.label = label
        self.text = text
        self.canReveal = canReveal
        self.field = field
        self.focus = focus
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if revealed && canReveal {
                    TextField(label, text: text)
                } else {
                    SecureField(label, text: text)
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .focused(focus, equals: field)
            .onSubmit(onSubmit)

            if canReveal {
                Button {
                    revealed.toggle()
                    focus.wrappedValue = field
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .help(revealed ? L("Hide") : L("Show"))
                .accessibilityLabel(Text(verbatim: revealed ? L("Hide") : L("Show")))
            }
        }
        .onChange(of: canReveal) { newValue in
            if !newValue { revealed = false }
        }
    }
}
