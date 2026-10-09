//
//  Theme.swift
//  Tunnelblick
//
//  Colors, fonts and motion used by the SwiftUI interface. Native macOS look: system colors and materials,
//  with green reserved for "connected", amber for warnings and red for failures.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

enum Theme {

    // Semantic colors
    static let connected  = Color(nsColor: .systemGreen)
    static let warning    = Color(nsColor: .systemOrange)
    static let failure    = Color(nsColor: .systemRed)
    static let tunnel     = Color.accentColor                    // The encrypted part of the route
    static let neutral    = Color(nsColor: .secondaryLabelColor)
    static let faint      = Color(nsColor: .tertiaryLabelColor)
    static let separator  = Color(nsColor: .separatorColor)

    // Surfaces
    static let groupBackground  = Color(nsColor: .controlBackgroundColor)   // Inset grouped rows
    static let windowBackground = Color(nsColor: .windowBackgroundColor)

    // Fonts
    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let rowTitle    = Font.system(size: 13)
    static let rowCaption  = Font.system(size: 11)
    static let sectionHead = Font.system(size: 11, weight: .semibold)
    static let paneTitle   = Font.system(size: 20, weight: .semibold)

    // Metrics
    static let cornerRadius: CGFloat = 10
    static let rowHeight: CGFloat = 32

    // Motion
    static let quick  = Animation.easeOut(duration: 0.22)
    static let standard = Animation.easeInOut(duration: 0.32)
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// Returns nil when the user has asked macOS to reduce motion, so `withAnimation(Theme.motion(.quick))` does nothing.
    static func motion(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// A grouped inset section like System Settings: a small header and rounded rows with hairline separators.
struct InsetSection<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(verbatim: title)
                    .font(Theme.sectionHead)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.groupBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5)
            )
            if let footer {
                Text(verbatim: footer)
                    .font(Theme.rowCaption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A row inside an InsetSection, with an optional caption under the title and a trailing control.
struct InsetRow<Trailing: View>: View {
    let title: String
    let caption: String?
    let isLast: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, caption: String? = nil, isLast: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.caption = caption
        self.isLast = isLast
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(Theme.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption, !caption.isEmpty {
                        Text(verbatim: caption)
                            .font(Theme.rowCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: Theme.rowHeight)
            if !isLast {
                Divider().padding(.leading, 12)
            }
        }
    }
}

/// A small colored dot for connection state.
struct StateDot: View {
    let color: Color
    var pulsing: Bool = false
    @State private var pulse = false

    // Explicit: a private stored property makes the synthesized memberwise initializer private.
    init(color: Color, pulsing: Bool = false) {
        self.color = color
        self.pulsing = pulsing
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(pulsing && pulse ? 0.35 : 1)
            .onAppear {
                guard pulsing, !Theme.reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
            }
            .onChange(of: pulsing) { newValue in
                if newValue, !Theme.reduceMotion {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
                } else {
                    withAnimation(.default) { pulse = false }
                }
            }
            .accessibilityHidden(true)
    }
}
