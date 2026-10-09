//
//  DetailsSidebarView.swift
//  Tunnelblick
//
//  The sidebar of the VPN Details window: search, the configurations (with folders), the Tunnelblick panes, and the
//  + / − / ⋯ footer. Files dropped on it are installed.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DetailsSidebarView: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var navigation = DetailsNavigation.shared
    @State private var isDropTargeted = false

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            SidebarSearchField(text: $navigation.searchText)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 6)

            List(selection: selectionBinding) {
                Section {
                    configurationRows
                } header: {
                    Text(verbatim: L("Configurations"))
                }

                if !visiblePanes.isEmpty {
                    Section {
                        ForEach(visiblePanes) { pane in
                            PaneRow(pane: pane)
                                .tag(DetailsSelection.pane(pane))
                        }
                    } header: {
                        Text(verbatim: L("Tunnelblick"))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            SidebarFooter()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.tunnel, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .padding(4)
                .opacity(isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            ConfigurationActions.handleDrop(providers)
        }
        .tbLayoutDirection()
    }

    private var selectionBinding: Binding<DetailsSelection?> {
        Binding(
            get: { navigation.selection },
            set: { newValue in
                // Clicking an empty area or a folder row deselects; keep what is shown instead.
                guard let newValue else { return }
                navigation.select(newValue)
            })
    }

    private var query: String {
        navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visiblePanes: [DetailsPane] {
        let query = self.query.lowercased()
        guard !query.isEmpty else { return DetailsPane.allCases }
        return DetailsPane.allCases.filter {
            $0.title.lowercased().contains(query) || $0.searchWords.contains(query)
        }
    }

    /// Configurations matching the search text (name, folder, server or file name).
    private var matchingDisplayNames: [String] {
        let query = self.query.lowercased()
        return model.displayNames.filter { displayName in
            let name = model.snapshots[displayName]?.localizedName ?? displayName
            if name.lowercased().contains(query) || displayName.lowercased().contains(query) {
                return true
            }
            let entry = ConfigurationInfoCache.shared.entry(for: displayName)
            if let host = entry.info.remoteHost, host.lowercased().contains(query) {
                return true
            }
            if let fileName = entry.fileName, fileName.lowercased().contains(query) {
                return true
            }
            return false
        }
    }

    @ViewBuilder
    private var configurationRows: some View {
        if model.displayNames.isEmpty {
            Text(verbatim: L("No configurations yet. Click + or drop a .tblk, .ovpn, or .conf file here."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } else if query.isEmpty {
            ForEach(model.tree) { node in
                SidebarNodeView(node: node)
            }
        } else {
            let matches = matchingDisplayNames
            if matches.isEmpty {
                Text(verbatim: LF("No configurations match “%@”", query))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(matches, id: \.self) { displayName in
                    ConfigurationRow(displayName: displayName,
                                     name: (model.snapshots[displayName]?.localizedName ?? displayName))
                        .tag(DetailsSelection.configuration(displayName))
                }
            }
        }
    }
}

// MARK: - Rows

/// A folder (with its configurations) or a configuration. Recursive for nested folders.
struct SidebarNodeView: View {
    let node: ConfigNode

    @ObservedObject private var navigation = DetailsNavigation.shared

    init(node: ConfigNode) {
        self.node = node
    }

    var body: some View {
        if let displayName = node.displayName {
            ConfigurationRow(displayName: displayName, name: node.name)
                .tag(DetailsSelection.configuration(displayName))
        } else {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(node.children ?? []) { child in
                    SidebarNodeView(node: child)
                }
            } label: {
                FolderRow(name: node.name, count: Self.configurationCount(node))
            }
        }
    }

    private var expandedBinding: Binding<Bool> {
        let id = node.id
        let navigation = self.navigation
        return Binding(
            get: { !navigation.collapsedFolders.contains(id) },
            set: { expanded in
                if expanded {
                    navigation.collapsedFolders.remove(id)
                } else {
                    navigation.collapsedFolders.insert(id)
                }
            })
    }

    private static func configurationCount(_ node: ConfigNode) -> Int {
        guard let children = node.children else { return 1 }
        return children.reduce(0) { $0 + configurationCount($1) }
    }
}

struct FolderRow: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(Theme.tunnel)
                .font(.system(size: 13))
            Text(verbatim: name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text(verbatim: String(count))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ConfigurationRow: View {
    let displayName: String
    let name: String

    @ObservedObject private var model = AppModel.shared

    init(displayName: String, name: String) {
        self.displayName = displayName
        self.name = name
    }

    var body: some View {
        let snapshot = model.snapshots[displayName]
        let entry = ConfigurationInfoCache.shared.entry(for: displayName)
        HStack(spacing: 8) {
            TunnelTile(size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: (name as NSString).lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption = entry.caption {
                    Text(verbatim: caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            StateDot(color: snapshot?.tint ?? Theme.faint, pulsing: snapshot?.isBusy ?? false)
        }
        .padding(.vertical, 1)
        .help(snapshot?.localizedStateText ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: snapshot?.localizedStateText ?? ""))
    }
}

struct PaneRow: View {
    let pane: DetailsPane

    var body: some View {
        HStack(spacing: 8) {
            SymbolTile(symbolName: pane.symbolName, size: 24)
            Text(verbatim: pane.title)
                .font(.system(size: 13))
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Search field

struct SidebarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(L("Search"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: L("Clear")))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Footer (+, −, ⋯)

struct SidebarFooter: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var navigation = DetailsNavigation.shared
    @ObservedObject private var refresh = LegacyRefresh.shared

    init() {}

    var body: some View {
        let _ = model.tick + refresh.revision     // Re-read the legacy buttons' state
        let hasConfigurationSelected = navigation.selection?.displayName != nil
        HStack(spacing: 4) {
            Menu {
                Button {
                    ConfigurationActions.addConfiguration()
                } label: {
                    Text(verbatim: (L("Add a Configuration") + "…"))
                }
                Button {
                    ConfigurationActions.importConfigurationFiles()
                } label: {
                    Text(verbatim: L("Import Configuration Files…"))
                }
            } label: {
                Image(systemName: "plus")
            } primaryAction: {
                ConfigurationActions.addConfiguration()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help((L("Add a Configuration") + "…"))
            .accessibilityLabel(Text(verbatim: (L("Add a Configuration") + "…")))

            Button {
                ConfigurationActions.removeSelectedConfiguration()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(!hasConfigurationSelected || !ConfigurationActions.removeIsEnabled)
            .help(L("Remove the selected configuration"))
            .accessibilityLabel(Text(verbatim: L("Remove the selected configuration")))

            Button {
                ConfigurationActions.showActionsMenu()
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(!hasConfigurationSelected)
            .help(L("Configuration actions"))
            .accessibilityLabel(Text(verbatim: L("Configuration actions")))

            Spacer(minLength: 6)

            Text(verbatim: L("Drop files to install"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }
}

// MARK: - Icons

/// The app-style tunnel icon used for configurations.
struct TunnelTile: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.60), Color(white: 0.42)],
                                     startPoint: .top, endPoint: .bottom))
            TunnelGlyph()
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.2, size * 0.065), lineCap: .round, lineJoin: .round))
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A gray tile with an SF Symbol, like System Settings' sidebar icons.
struct SymbolTile: View {
    let symbolName: String
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.60), Color(white: 0.42)],
                                     startPoint: .top, endPoint: .bottom))
            Image(systemName: symbolName)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// An arch (the tunnel) with an inner arch and a base line.
struct TunnelGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let k: CGFloat = 0.5523     // Cubic approximation of a quarter circle

        func addArch(radius r: CGFloat, centerX cx: CGFloat, top: CGFloat, base: CGFloat) {
            path.move(to: CGPoint(x: cx - r, y: base))
            path.addLine(to: CGPoint(x: cx - r, y: top + r))
            path.addCurve(to: CGPoint(x: cx, y: top),
                          control1: CGPoint(x: cx - r, y: top + r - k * r),
                          control2: CGPoint(x: cx - k * r, y: top))
            path.addCurve(to: CGPoint(x: cx + r, y: top + r),
                          control1: CGPoint(x: cx + k * r, y: top),
                          control2: CGPoint(x: cx + r, y: top + r - k * r))
            path.addLine(to: CGPoint(x: cx + r, y: base))
        }

        let outer = rect.width / 2
        let inner = outer * 0.48
        addArch(radius: outer, centerX: rect.midX, top: rect.minY, base: rect.maxY)
        addArch(radius: inner, centerX: rect.midX, top: rect.minY + (outer - inner) + rect.height * 0.08, base: rect.maxY)
        path.move(to: CGPoint(x: rect.minX - rect.width * 0.08, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX + rect.width * 0.08, y: rect.maxY))
        return path
    }
}
