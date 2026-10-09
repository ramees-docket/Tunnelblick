//
//  StatusPanelView.swift
//  Tunnelblick
//
//  Content of the floating VPN status window (new interface): one compact row (status dot, name, status, timer,
//  chevron) that expands on click to show the In/Out rates and totals, the warning line with "Review", and the
//  Connect/Disconnect button. Fixed heights (see StatusPanelModel) so the window can be positioned in advance.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct StatusPanelView: View {

    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusPanelRow(model: model)
            if model.isExpanded {
                StatusPanelDetails(model: model)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: StatusPanelModel.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .onExitCommand { model.setExpanded(false) }
        .tbLayoutDirection()
    }
}

// MARK: - The compact row

private struct StatusPanelRow: View {

    @ObservedObject var model: StatusPanelModel
    @State private var hovering = false

    var body: some View {
        Button {
            model.toggleExpanded()
        } label: {
            HStack(spacing: 8) {
                StatusPanelDot(kind: model.dotKind)
                HStack(spacing: 5) {
                    Text(verbatim: model.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    Text(verbatim: "·")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(verbatim: model.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                Text(verbatim: model.timeText)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(model.isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(height: StatusPanelModel.collapsedHeight)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(hovering ? 0.06 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityValue(Text(verbatim: model.isExpanded ? L("Expanded") : L("Collapsed")))
    }

    private var statusColor: Color {
        switch model.dotKind {
        case .warning: return Theme.warning
        case .failed:  return Theme.failure
        default:       return Color.secondary
        }
    }

    private var accessibilityText: String {
        [model.name, model.statusText, model.timeText].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - The status dot

private struct StatusPanelDot: View {

    let kind: StatusPanelModel.DotKind

    var body: some View {
        switch kind {
        case .connected:
            StateDot(color: Theme.connected)
        case .warning:
            StateDot(color: Theme.warning)
        case .busy:
            StateDot(color: Theme.tunnel, pulsing: true)
        case .failed:
            StateDot(color: Theme.failure)
        case .idle:
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.25)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - The expanded part

private struct StatusPanelDetails: View {

    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: StatusPanelModel.detailSpacing) {
            rates
            if let warning = model.warningText {
                warningLine(warning)
            }
            actions
        }
        .padding(.leading, 28)          // Aligned with the name, after the dot
        .padding(.trailing, 12)
        .padding(.bottom, StatusPanelModel.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: StatusPanelModel.detailHeight(hasWarning: model.hasWarning), alignment: .top)
    }

    // In/Out rates and totals

    private var rates: some View {
        VStack(alignment: .leading, spacing: 2) {
            rateRow(label: L("In:"),
                    rate: model.showsRates ? model.snapshot?.inRateText : nil,
                    total: model.snapshot?.inTotalText)
            rateRow(label: L("Out:"),
                    rate: model.showsRates ? model.snapshot?.outRateText : nil,
                    total: model.snapshot?.outTotalText)
        }
        .frame(height: StatusPanelModel.ratesHeight, alignment: .top)
    }

    private func rateRow(label: String, rate: String?, total: String?) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(verbatim: rate ?? "—")
                .fontWeight(.medium)
            Spacer(minLength: 8)
            Text(verbatim: total ?? "")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
        .frame(height: 16)
    }

    // "DNS lookups are leaving outside the VPN"  Review

    private func warningLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.warning)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                model.review()
            } label: {
                Text(verbatim: L("Review"))
                    .font(.system(size: 11, weight: .semibold))
                    .underline()
            }
            .buttonStyle(.plain)
            .help(L("Show the warnings in VPN Details"))
        }
        .frame(height: StatusPanelModel.warningHeight, alignment: .top)
    }

    // Connect/Disconnect and the close button

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                model.connectOrDisconnect()
            } label: {
                Text(verbatim: model.buttonTitle)
                    .frame(minWidth: 70)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.buttonIsEnabled)

            Spacer(minLength: 8)

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help(L("Close"))
            .accessibilityLabel(Text(verbatim: L("Close")))
        }
        .frame(height: StatusPanelModel.actionsHeight)
    }
}
