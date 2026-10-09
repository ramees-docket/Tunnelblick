//
//  InfoPaneView.swift
//  Tunnelblick
//
//  The "Info" pane: the application icon, name, version, links, the credits (taken from the hidden legacy InfoView,
//  which builds them) and the copyright notice.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct InfoPaneView: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared
    @State private var credits: NSAttributedString?

    init() {}

    private var applicationName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return L("Tunnelblick")
    }

    /// The version shown by the original Info pane (with " (Deployed)" when appropriate), else the bundle's version.
    private var versionText: String {
        let legacy = LegacyCheckboxState.clean(TBSwiftUIBridge.legacyInfoView()?.infoVersionTFC()?.title ?? "")
        if !legacy.isEmpty {
            return legacy
        }
        let version: String? = tunnelblickVersion(Bundle.main)
        return version ?? ""
    }

    private var copyrightText: String {
        LegacyCheckboxState.clean(gTbInfo?.tunnelblickCopyrightNotice() ?? "")
    }

    var body: some View {
        let _ = model.tick &+ refresh.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let credits, credits.length > 0 {
                    PanesSection(L("Credits")) {
                        PanesAttributedTextView(text: credits)
                            .frame(height: 260)
                    }
                }
                if !copyrightText.isEmpty {
                    Text(verbatim: copyrightText)
                        .font(Theme.rowCaption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .tbLayoutDirection()
        .onAppear {
            TBSwiftUIBridge.showLegacyPane("Info")
            loadCredits()
            LegacyRefresh.shared.bump()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: applicationName)
                .font(Theme.paneTitle)
            if !versionText.isEmpty {
                Text(verbatim: versionText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://tunnelblick.net")!) {
                    Text(verbatim: "tunnelblick.net")
                }
                Link(destination: URL(string: "https://tunnelblick.net/cRlsNotes.html")!) {
                    Text(verbatim: L("Release Notes"))
                }
                Link(destination: URL(string: "https://tunnelblick.net/donate.html")!) {
                    Label {
                        Text(verbatim: L("Donate"))
                    } icon: {
                        Image(systemName: "heart")
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    /// The credits are built by -[InfoView awakeFromNib] into its (hidden) text view.
    private func loadCredits() {
        guard let view = TBSwiftUIBridge.legacyInfoView(),
              let textView: NSTextView = PanesLegacy.outlet(view, "infoCreditTV"),
              let storage = textView.textStorage,
              storage.length > 0 else {
            credits = nil
            return
        }
        credits = PanesAttributedTextView.adaptiveCopy(of: storage)
    }
}
