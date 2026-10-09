//
//  L10n.swift
//  Tunnelblick
//
//  Localization helpers.
//
//  Tunnelblick localizes with NSLocalizedString and the English text as the key, in Localizable.strings files that are
//  copied as folder references (no String Catalog: BuildAppsAndDmgs.sh fails if the .lproj folders change).
//
//  Rules for the SwiftUI code:
//   * Use L("exact English key") for every user-visible string, and Text(verbatim:) to display it.
//     Never use Text("literal") or string interpolation inside Text, because SwiftUI would look up a different key.
//   * Reuse existing keys from en.lproj/Localizable.strings whenever the wording matches.
//   * New strings fall back to English until they are added to the .strings files.
//   * Titles of legacy controls (buttons, pop-up items) are already localized by the original code; use them as they are.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import Foundation
import SwiftUI

/// Localized string for an English key.
func L(_ key: String) -> String {
    return Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
}

/// Localized format string for an English key, filled in with String(format:).
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    return String(format: L(key), arguments: arguments)
}

/// Localized connection state, e.g. "CONNECTED" -> "Connected", "AUTH" -> "Authorizing".
func localizedState(_ state: String) -> String {
    return localizeNonLiteral(state, "Connection status")
}

extension View {
    /// Right-to-left layout when Tunnelblick was launched in a right-to-left language (or the useRtlLayout pref is set).
    func tbLayoutDirection() -> some View {
        environment(\.layoutDirection, (gMC?.languageAtLaunchWasRTL() ?? false) ? .rightToLeft : .leftToRight)
    }
}
