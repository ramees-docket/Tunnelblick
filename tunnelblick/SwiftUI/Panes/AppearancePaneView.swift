//
//  AppearancePaneView.swift
//  Tunnelblick
//
//  The "Appearance" pane. Mirrors the controls of the hidden legacy AppearanceView and changes settings by clicking
//  them (see TBSwiftUIBridge.h). The menu bar icon sets are shown as visual choices, using the icon set files.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import SwiftUI

struct AppearancePaneView: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var refresh = LegacyRefresh.shared

    init() {}

    var body: some View {
        let _ = model.tick &+ refresh.revision
        PanesPage(title: L("Appearance"),
                  subtitle: L("How Tunnelblick looks in the menu bar and on the screen")) {
            if let view = TBSwiftUIBridge.legacyAppearanceView() {
                iconSection(view)
                menuSection(view)
                statusWindowsSection(view)
                startupSection(view)
            }
        }
        .onAppear {
            TBSwiftUIBridge.showLegacyPane("Appearance")
            LegacyRefresh.shared.bump()
        }
    }

    @ViewBuilder
    private func iconSection(_ view: AppearanceView) -> some View {
        let iconLabel: NSTextFieldCell? = PanesLegacy.outlet(view, "appearanceIconTFC")
        let title = PanesLegacy.label(iconLabel, fallback: L("Icon:"))
        PanesSection(title,
                     subtitle: L("The Tunnelblick icon in the menu bar"),
                     help: PanesLegacy.help([PanesHelpSource(title, view.appearanceIconSetButton())])) {
            PanesIconSetPicker(title: title,
                               popUp: view.appearanceIconSetButton(),
                               arrayController: view.appearanceIconSetArrayController())
        }
    }

    @ViewBuilder
    private func menuSection(_ view: AppearanceView) -> some View {
        let menuLabel: NSTextFieldCell? = PanesLegacy.outlet(view, "appearanceMenuTFC")
        PanesSection(PanesLegacy.label(menuLabel, fallback: L("Menu:")),
                     help: PanesLegacy.help([
                        PanesHelpSource(nil, view.appearanceDisplayConnectAndDisconnectPrefixesCheckbox()),
                        PanesHelpSource(nil, view.appearanceDisplayConnectionSubmenusCheckbox()),
                        PanesHelpSource(nil, view.appearanceDisplayConnectionTimersCheckbox()),
                        PanesHelpSource(nil, view.appearanceDisplayConnectedIndicatorCheckbox()),
                        PanesHelpSource(nil, view.appearanceDisplayWarningIndicatorCheckbox())
                     ])) {
            LegacyToggleRow(button: view.appearanceDisplayConnectAndDisconnectPrefixesCheckbox())
            LegacyToggleRow(button: view.appearanceDisplayConnectionSubmenusCheckbox())
            LegacyToggleRow(button: view.appearanceDisplayConnectionTimersCheckbox())
            LegacyToggleRow(button: view.appearanceDisplayConnectedIndicatorCheckbox())
            LegacyToggleRow(button: view.appearanceDisplayWarningIndicatorCheckbox(), isLast: true)
        }
    }

    @ViewBuilder
    private func statusWindowsSection(_ view: AppearanceView) -> some View {
        let criteriaLabel: NSTextFieldCell? = PanesLegacy.outlet(view, "appearanceConnectionWindowDisplayCriteriaTFC")
        PanesSection(PanesLegacy.label(criteriaLabel, fallback: L("VPN status windows:")),
                     help: PanesLegacy.help([
                        PanesHelpSource(L("Show"), view.appearanceConnectionWindowDisplayCriteriaButton()),
                        PanesHelpSource(L("Screen"), view.appearanceConnectionWindowScreenButton()),
                        PanesHelpSource(nil, view.appearanceDisplayStatisticsWindowsCheckbox()),
                        PanesHelpSource(nil, view.appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox())
                     ])) {
            LegacyPopUpRow(title: L("Show"), popUp: view.appearanceConnectionWindowDisplayCriteriaButton())
            LegacyPopUpRow(title: L("Screen"), popUp: view.appearanceConnectionWindowScreenButton())
            LegacyToggleRow(button: view.appearanceDisplayStatisticsWindowsCheckbox())
            LegacyToggleRow(button: view.appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox(), isLast: true)
        }
    }

    @ViewBuilder
    private func startupSection(_ view: AppearanceView) -> some View {
        let splashLabel: NSTextFieldCell? = PanesLegacy.outlet(view, "appearanceSplashTFC")
        PanesSection(PanesLegacy.label(splashLabel, fallback: L("Startup window:")),
                     help: PanesLegacy.help([PanesHelpSource(nil, view.appearanceDisplaySplashScreenCheckbox())])) {
            LegacyToggleRow(button: view.appearanceDisplaySplashScreenCheckbox(), isLast: true)
        }
    }
}

// MARK: - Icon set choices

/// One icon set: its pop-up item title and its "not connected" and "connected" images.
private struct PanesIconSetChoice: Identifiable {
    let id: Int             // Index of the item in the legacy pop-up button
    let title: String
    let idle: NSImage
    let connected: NSImage
    let isTemplate: Bool
}

@MainActor
private enum PanesIconSets {

    private static var imageCache: [String: NSImage] = [:]

    /// Same search order as -[MenuController loadMenuIconSet]: Deploy, Shared, then the app's Resources.
    static func directory(forIconSetNamed name: String) -> String? {
        var parents: [String] = []
        if let deploy = gDeployPath as String?, !deploy.isEmpty {
            parents.append((deploy as NSString).appendingPathComponent("IconSets"))
        }
        parents.append("/Library/Application Support/Tunnelblick/Shared/IconSets")   // L_AS_T_SHARED/IconSets
        if let resources = Bundle.main.resourcePath {
            parents.append((resources as NSString).appendingPathComponent("IconSets"))
        }
        for parent in parents {
            let path = (parent as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return path
            }
        }
        return nil
    }

    static func image(atPath path: String, template: Bool) -> NSImage? {
        let key = path + (template ? "|t" : "")
        if let cached = imageCache[key] {
            return cached
        }
        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        image.isTemplate = template
        imageCache[key] = image
        return image
    }

    /// The choices, or nil if they cannot all be shown as pictures (then the pane shows the pop-up button instead).
    static func choices(popUp: NSPopUpButton, arrayController: NSArrayController?) -> [PanesIconSetChoice]? {
        guard let arrayController,
              let entries = arrayController.arrangedObjects as? [NSDictionary] else {
            return nil
        }
        let titles = popUp.itemArray.map { LegacyCheckboxState.clean($0.title) }
        guard !entries.isEmpty, entries.count == titles.count else {
            return nil
        }

        var result: [PanesIconSetChoice] = []
        for (index, entry) in entries.enumerated() {
            guard let fileName = entry["value"] as? String,
                  !fileName.isEmpty,
                  let folder = directory(forIconSetNamed: fileName) else {
                return nil
            }
            let usesTemplates = FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent("templates.png"))
            guard let idle = image(atPath: (folder as NSString).appendingPathComponent("closed.png"), template: usesTemplates),
                  let connected = image(atPath: (folder as NSString).appendingPathComponent("open.png"), template: usesTemplates) else {
                return nil
            }
            result.append(PanesIconSetChoice(id: index, title: titles[index], idle: idle, connected: connected, isTemplate: usesTemplates))
        }
        return result
    }
}

/// The icon set chooser: one tile per icon set (falls back to the legacy pop-up when pictures are not available).
private struct PanesIconSetPicker: View {
    let title: String
    let popUp: NSPopUpButton?
    let arrayController: NSArrayController?

    @ObservedObject private var refresh = LegacyRefresh.shared
    @ObservedObject private var model = AppModel.shared

    init(title: String, popUp: NSPopUpButton?, arrayController: NSArrayController?) {
        self.title = title
        self.popUp = popUp
        self.arrayController = arrayController
    }

    var body: some View {
        let _ = refresh.revision &+ model.tick
        if let popUp, let choices = PanesIconSets.choices(popUp: popUp, arrayController: arrayController) {
            let state = LegacyPopUpState(popUp)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
                      alignment: .leading,
                      spacing: 12) {
                ForEach(choices) { choice in
                    tile(choice,
                         popUp: popUp,
                         isSelected: choice.id == state.selectedIndex,
                         isEnabled: state.isEnabled && state.itemIsEnabled[choice.id])
                }
            }
            .padding(12)
            .opacity(state.isEnabled ? 1 : 0.6)
        } else {
            LegacyPopUpRow(title: title, popUp: popUp, isLast: true)
        }
    }

    private func tile(_ choice: PanesIconSetChoice, popUp: NSPopUpButton, isSelected: Bool, isEnabled: Bool) -> some View {
        Button {
            guard !isSelected else { return }
            TBSwiftUIBridge.choose(popUp, index: choice.id)
            LegacyRefresh.shared.bump()
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 18) {
                    iconImage(choice.idle, template: choice.isTemplate)
                    iconImage(choice.connected, template: choice.isTemplate)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.windowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Theme.separator,
                                      lineWidth: isSelected ? 2 : 0.5)
                )
                Text(verbatim: choice.title)
                    .font(Theme.rowCaption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(verbatim: choice.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconImage(_ image: NSImage, template: Bool) -> some View {
        Image(nsImage: image)
            .renderingMode(template ? .template : .original)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22)
            .foregroundStyle(Color.primary)
    }
}
