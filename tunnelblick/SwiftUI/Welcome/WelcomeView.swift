//
//  WelcomeView.swift
//  Tunnelblick
//
//  Content of the first-run window (see WelcomeWindowController).
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {

    static let size = NSSize(width: 600, height: 460)

    @ObservedObject var model: WelcomeModel

    var body: some View {
        ZStack {
            switch model.step {
            case .intro:
                WelcomeIntroStep(model: model)
                    .transition(stepTransition)
            case .haveFiles:
                WelcomeHaveFilesStep(model: model)
                    .transition(stepTransition)
            case .noFiles:
                WelcomeNoFilesStep(model: model)
                    .transition(stepTransition)
            case .sampleCreated:
                WelcomeSampleCreatedStep(model: model)
                    .transition(stepTransition)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.windowBackground)
        .tbLayoutDirection()
    }

    private var stepTransition: AnyTransition {
        let edge: Edge = model.forward ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .opacity)
    }
}

// MARK: - Step 0: welcome

private struct WelcomeIntroStep: View {

    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
            Text(verbatim: L("Welcome to Tunnelblick"))
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 14)
            Text(verbatim: L("There are no VPN configurations installed. Tunnelblick connects this Mac to a VPN using a configuration file from your network manager or VPN provider — a file ending in .tblk, .ovpn, or .conf."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
                .padding(.top, 8)
            Text(verbatim: L("Do you have any configuration files?"))
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 22)
            HStack(alignment: .top, spacing: 12) {
                WelcomeChoiceCard(symbol: "doc",
                                  title: L("I have configuration files"),
                                  detail: L("Install a .tblk, .ovpn, or .conf file")) {
                    model.go(.haveFiles)
                }
                WelcomeChoiceCard(symbol: "questionmark.circle",
                                  title: L("I DO NOT have configuration files"),
                                  detail: L("Find out where they come from, or try a sample")) {
                    model.go(.noFiles)
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 12)
            HStack {
                Button {
                    model.quit()
                } label: {
                    Text(verbatim: L("Quit"))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L("Quit Tunnelblick"))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }
}

/// One of the two big choices on the welcome step.
private struct WelcomeChoiceCard: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 250, alignment: .leading)
            .frame(minHeight: 96, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.groupBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hovering ? Color.accentColor.opacity(0.8) : Theme.separator,
                                  lineWidth: hovering ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(WelcomePressStyle())
        .onHover { hovering = $0 }
        .animation(Theme.motion(Theme.quick), value: hovering)
    }
}

private struct WelcomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Theme.reduceMotion ? 0.985 : 1)
    }
}

// MARK: - Step 1: "I have configuration files"

private struct WelcomeHaveFilesStep: View {

    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: L("Add your configuration file"))
                .font(.system(size: 18, weight: .semibold))
            Text(verbatim: L("Drag the file you received onto the area below. Tunnelblick installs a copy, so the original can stay where it is."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            WelcomeDropZone(model: model)
                .padding(.top, 16)
            if !model.installingNames.isEmpty {
                installingLine
                    .padding(.top, 12)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
            WelcomeFooter {
                Button {
                    model.go(.intro, forward: false)
                } label: {
                    Text(verbatim: L("Back"))
                }
            } trailing: {
                EmptyView()
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 20)
    }

    private var installingLine: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: LF("Installing “%@”…", model.installingNames.joined(separator: "”, “")))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Text(verbatim: L("Answer Tunnelblick’s questions to finish. This window closes when the configuration is installed."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Accepts dropped .tblk/.ovpn/.conf files; its dashed border marches while a file is over it.
private struct WelcomeDropZone: View {

    @ObservedObject var model: WelcomeModel
    @State private var targeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.10) : Color.clear)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !targeted || Theme.reduceMotion)) { context in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.55),
                                  style: StrokeStyle(lineWidth: targeted ? 2 : 1.5,
                                                     dash: [7, 6],
                                                     dashPhase: marchingPhase(context.date)))
            }
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
                    .scaleEffect(targeted ? 1.08 : 1)
                    .offset(y: targeted ? -6 : 0)
                    .accessibilityHidden(true)
                Text(verbatim: L("Drop a .tblk, .ovpn, or .conf file here"))
                    .font(.system(size: 13, weight: .medium))
                Button {
                    model.chooseFiles()
                } label: {
                    Text(verbatim: L("Choose File…"))
                }
                .padding(.top, 2)
                if let error = model.dropError {
                    Text(verbatim: error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.failure)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .frame(height: 210)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            model.receive(providers)
            return true
        }
        .animation(Theme.motion(Theme.spring), value: targeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: L("Drop a .tblk, .ovpn, or .conf file here")))
    }

    private func marchingPhase(_ date: Date) -> CGFloat {
        guard targeted, !Theme.reduceMotion else { return 0 }
        let phase = (date.timeIntervalSinceReferenceDate * 22).truncatingRemainder(dividingBy: 13)
        return CGFloat(-phase)
    }
}

// MARK: - Step 1 (other path): "I DO NOT have configuration files"

private struct WelcomeNoFilesStep: View {

    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: L("Where configuration files come from"))
                .font(.system(size: 18, weight: .semibold))
            Text(verbatim: L("Tunnelblick needs a configuration file before it can connect. The file usually comes with your VPN access."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 12) {
                WelcomeSourceRow(symbol: "building.2",
                                 title: L("From your workplace or school"),
                                 detail: L("Your network manager or IT team gives you a .tblk, .ovpn, or .conf file — often by email or on an internal page."))
                WelcomeSourceRow(symbol: "globe",
                                 title: L("From a VPN service"),
                                 detail: L("VPN providers offer OpenVPN configuration files on their website, usually under “Manual setup” or “OpenVPN”."))
                WelcomeSourceRow(symbol: "square.and.arrow.down",
                                 title: L("Then install it here"),
                                 detail: L("Drag the file onto this window or onto the Tunnelblick icon in the menu bar."))
            }
            .padding(.top, 16)
            Spacer(minLength: 8)
            if let error = model.sampleError {
                WelcomeErrorBox(title: L("Installation failed"), message: error)
                    .padding(.bottom, 10)
            }
            if model.confirmReplace {
                replaceQuestion
                    .transition(.opacity)
            } else {
                footer
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 20)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: L("Tunnelblick can create a sample configuration on your Desktop and open its OpenVPN configuration file in TextEdit, so you can change it to connect to your VPN."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            WelcomeFooter {
                Button {
                    model.go(.intro, forward: false)
                } label: {
                    Text(verbatim: L("Back"))
                }
                Button {
                    model.go(.haveFiles)
                } label: {
                    Text(verbatim: L("I have configuration files"))
                }
            } trailing: {
                Button {
                    model.createSampleConfiguration(replacingExisting: false)
                } label: {
                    Text(verbatim: L("Create sample configuration and edit it"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The guide's "Replace Existing File?" question, in the window.
    private var replaceQuestion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: L("Replace Existing File?"))
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: LF("'%@' already exists on the Desktop.\n\nWould you like to replace it?", model.sampleFolderName))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    model.cancelReplace()
                } label: {
                    Text(verbatim: L("Back"))
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    model.createSampleConfiguration(replacingExisting: true)
                } label: {
                    Text(verbatim: L("Replace"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.45), lineWidth: 0.5)
        )
    }
}

private struct WelcomeSourceRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.separator.opacity(0.35)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A red box with a title and a message (sample configuration errors).
private struct WelcomeErrorBox: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.failure)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                Text(verbatim: message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.failure.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Step 2 (other path): the sample configuration was created

private struct WelcomeSampleCreatedStep: View {

    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.connected)
                    .accessibilityHidden(true)
                Text(verbatim: L("Sample Configuration Created"))
                    .font(.system(size: 18, weight: .semibold))
            }
            ScrollView {
                Text(verbatim: L("The sample configuration folder has been created on your Desktop, and the OpenVPN configuration file has been opened in TextEdit so you can modify the file for your VPN setup.\n\nWhen you have finished editing the OpenVPN configuration file and saved the changes, please\n\n1. Move or copy any key or certificate files associated with the configuration into the 'Sample Tunnelblick VPN Configuration' folder on your Desktop.\n\n(This folder has been opened in a Finder window so you can drag the files to it.)\n\n2. Change the name of the configuration file to a name of your choice (do not change the file's extension). This will be the name that Tunnelblick uses for the configuration.\n\n3. To install the configuration, drag the configuration file and drop it on the Tunnelblick icon in the menu bar or on the list of configurations in the 'Configurations' tab of the 'VPN Details' window."))
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.groupBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5)
            )
            .padding(.top, 14)
            WelcomeFooter {
                Button {
                    model.go(.noFiles, forward: false)
                } label: {
                    Text(verbatim: L("Back"))
                }
            } trailing: {
                Button {
                    model.go(.haveFiles)
                } label: {
                    Text(verbatim: L("Install a Configuration…"))
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 20)
    }
}

// MARK: - Footer

/// Buttons at the bottom of a step: secondary ones on the leading side, the main one on the trailing side.
private struct WelcomeFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Spacer()
            trailing()
        }
        .controlSize(.large)
    }
}
