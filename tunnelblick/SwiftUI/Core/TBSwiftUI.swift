//
//  TBSwiftUI.swift
//  Tunnelblick
//
//  Entry points that Objective-C code calls to show the SwiftUI windows.
//  Objective-C sees this class through the generated header "Tunnelblick-Swift.h".
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import AppKit

@objc(TBSwiftUI)
@MainActor
final class TBSwiftUI: NSObject {

    /// Shows the VPN Details window (replaces -[MenuController openPreferencesWindow:] when the new interface is in use).
    @objc static func showDetailsWindow() {
        AppModel.shared.start()
        DetailsWindowController.shared.show(selecting: nil)
    }

    /// Shows the VPN Details window with a configuration selected.
    @objc static func showDetailsWindow(selectingDisplayName displayName: String?) {
        AppModel.shared.start()
        DetailsWindowController.shared.show(selecting: displayName)
    }

    /// Shows the first-run window (replaces the "There are no VPN configurations installed" guide).
    @objc static func showWelcome() {
        AppModel.shared.start()
        WelcomeWindowController.shared.show()
    }
}
