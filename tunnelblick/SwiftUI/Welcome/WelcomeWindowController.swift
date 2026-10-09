//
//  WelcomeWindowController.swift
//  Tunnelblick
//
//  The first-run window of the new interface. It replaces the "There are no VPN configurations installed" guide
//  (+[ConfigurationManager guideState:]) that -[MenuController checkNoConfigurations] showed as a series of alerts.
//
//   * "I have configuration files": a drop zone and "Choose File…". The files go to -[MenuController openFiles:], so the
//     existing install flow (Only Me / All Users question, admin authorization, messages) does the work.
//   * "I DO NOT have configuration files": where configuration files come from, and "Create sample configuration and
//     edit it", which does exactly what the guide's stateMakeSampleConfiguration did.
//   * "Quit", as the guide offered.
//
//  The window closes by itself as soon as a configuration is installed (by any means) and opens VPN Details with the new
//  configuration selected.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {

    static let shared = WelcomeWindowController(model: WelcomeModel())

    private var window: NSWindow?
    private let model: WelcomeModel
    private var namesObserver: AnyCancellable?
    private var namesWhenShown: Set<String> = []

    // A distinct signature (not an override of the nonisolated -[NSObject init]).
    private init(model: WelcomeModel) {
        self.model = model
        super.init()
    }

    func show() {
        AppModel.shared.start()

        let window = self.window ?? makeWindow()
        self.window = window

        if !window.isVisible {
            model.reset()
            namesWhenShown = Set(AppModel.shared.displayNames)
            window.center()
        }
        startObserving()

        window.makeKeyAndOrderFront(nil)
        gMC?.activateIgnoringOtherApps()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        namesObserver = nil
    }

    // MARK: Private

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: WelcomeView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: WelcomeView.size.width, height: WelcomeView.size.height),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.contentViewController = hosting
        window.setContentSize(WelcomeView.size)
        window.title = L("Welcome to Tunnelblick")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.delegate = self
        model.window = window
        return window
    }

    private func startObserving() {
        guard namesObserver == nil else { return }
        namesObserver = AppModel.shared.$displayNames.sink { [weak self] _ in
            // @Published sends before the value changes; look at the new value on the next main-actor turn.
            guard let controller = self else { return }
            Task { @MainActor in controller.checkForNewConfiguration() }
        }
    }

    /// Closes the window and shows the new configuration in VPN Details once one has been installed.
    private func checkForNewConfiguration() {
        guard let window, window.isVisible else { return }
        let names = AppModel.shared.displayNames
        guard let newName = names.first(where: { !namesWhenShown.contains($0) }) else { return }
        namesObserver = nil
        window.close()
        TBSwiftUI.showDetailsWindow(selectingDisplayName: newName)
    }
}

// MARK: - Model

/// File extensions the welcome window installs (lowercased). One .tblkSetup can also be installed, by itself.
let welcomeConfigurationExtensions = ["tblk", "ovpn", "conf"]
let welcomeSetupExtension = "tblksetup"

@MainActor
final class WelcomeModel: ObservableObject {

    enum Step: Equatable {
        case intro, haveFiles, noFiles, sampleCreated
    }

    @Published private(set) var step: Step = .intro
    @Published private(set) var forward = true            // Direction of the step transition
    @Published private(set) var dropError: String?
    @Published private(set) var installingNames: [String] = []
    @Published private(set) var confirmReplace = false
    @Published private(set) var sampleError: String?

    weak var window: NSWindow?
    private var openPanelFilter: ConfigurationFileFilter?

    let sampleFolderName = L("Sample Tunnelblick VPN Configuration")

    func reset() {
        step = .intro
        forward = true
        dropError = nil
        installingNames = []
        confirmReplace = false
        sampleError = nil
    }

    func go(_ newStep: Step, forward isForward: Bool = true) {
        forward = isForward
        withAnimation(Theme.motion(Theme.standard)) {
            step = newStep
            dropError = nil
            confirmReplace = false
            sampleError = nil
        }
    }

    func quit() {
        gMC?.terminateBecause(terminatingBecauseOfQuit)
    }

    // MARK: Installing configuration files

    func receive(_ providers: [NSItemProvider]) {
        let collector = DroppedURLCollector()
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.add(url)
                } else if let url = item as? URL {
                    collector.add(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            let urls = collector.urls
            guard let model = self else { return }
            Task { @MainActor in model.install(urls) }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true           // A .tblk configuration is a folder
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.message = L("Choose the configuration files to install (.tblk, .ovpn, or .conf).")
        panel.prompt = L("Install")
        let filter = ConfigurationFileFilter()
        openPanelFilter = filter
        panel.delegate = filter
        let response = panel.runModal()
        openPanelFilter = nil
        if response == .OK {
            install(panel.urls)
        }
    }

    /// Checks the files like the drop targets of the menu bar icon and VPN Details do (one .tblkSetup, or any number of
    /// .tblk/.ovpn/.conf files), then passes them to -[MenuController openFiles:].
    func install(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let extensions = urls.map { $0.pathExtension.lowercased() }

        if extensions.contains(welcomeSetupExtension) && urls.count > 1 {
            dropError = L("A Tunnelblick Setup (.tblkSetup) must be installed by itself.")
            return
        }
        if !(urls.count == 1 && extensions[0] == welcomeSetupExtension),
           let bad = urls.first(where: { !welcomeConfigurationExtensions.contains($0.pathExtension.lowercased()) }) {
            dropError = LF("“%@” isn’t a configuration file. Use a file that ends in .tblk, .ovpn, or .conf.", bad.lastPathComponent)
            return
        }

        let paths = urls.map { $0.path }
        dropError = nil
        if gMC?.openFiles(paths) ?? false {
            withAnimation(Theme.motion(Theme.quick)) {
                installingNames = urls.map { $0.lastPathComponent }
            }
        } else {
            dropError = L("Tunnelblick could not install these files.")
        }
    }

    // MARK: Sample configuration (what +[ConfigurationManager guideState:] did in stateMakeSampleConfiguration)

    var sampleFolderPath: String? {
        guard let desktop = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first else { return nil }
        return (desktop as NSString).appendingPathComponent(sampleFolderName)
    }

    func createSampleConfiguration(replacingExisting: Bool) {
        guard let targetPath = sampleFolderPath else { return }
        let fileManager = FileManager.default
        sampleError = nil

        if fileManager.fileExists(atPath: targetPath) {
            guard replacingExisting else {
                withAnimation(Theme.motion(Theme.quick)) { confirmReplace = true }
                return
            }
            do {
                try fileManager.removeItem(atPath: targetPath)
            } catch {
                NSLog("Unable to remove %@: %@", targetPath, error.localizedDescription)
            }
        }
        confirmReplace = false

        do {
            try fileManager.createDirectory(atPath: targetPath,
                                            withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: NSNumber(value: 0o755)])
        } catch {
            NSLog("Installation failed. Not able to create %@", targetPath)
            sampleError = L("Tunnelblick could not create the empty configuration folder")
            return
        }

        let targetConfigPath = (targetPath as NSString).appendingPathComponent("config.ovpn")
        var copied = false
        if let sourcePath = Bundle.main.path(forResource: "openvpn", ofType: "conf") {
            do {
                try fileManager.copyItem(atPath: sourcePath, toPath: targetConfigPath)
                copied = true
            } catch {
                NSLog("Installation failed. Not able to copy %@ to %@", sourcePath, targetConfigPath)
            }
        }
        guard copied else {
            sampleError = L("Tunnelblick could not create the sample configuration")
            return
        }

        let workspace = NSWorkspace.shared
        workspace.open(URL(fileURLWithPath: targetPath))     // Show the folder in the Finder

        let configURL = URL(fileURLWithPath: targetConfigPath)
        if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            workspace.open([configURL], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            workspace.open(configURL)
        }

        go(.sampleCreated)
    }

    func cancelReplace() {
        withAnimation(Theme.motion(Theme.quick)) { confirmReplace = false }
    }
}

/// Collects the file URLs of a drop (NSItemProvider calls back on other threads).
final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Lets the open panel select only configuration files (folders stay enabled so they can be opened; a .tblk is a folder).
final class ConfigurationFileFilter: NSObject, NSOpenSavePanelDelegate {

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        let ext = url.pathExtension.lowercased()
        return welcomeConfigurationExtensions.contains(ext) || ext == welcomeSetupExtension
    }
}
