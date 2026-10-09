# Tunnelblick SwiftUI interface (branch `swiftui-ui`)

This branch replaces Tunnelblick's windows with a SwiftUI interface in the "Route" design:

- **VPN Details window**: a sidebar with the configurations (folders included) plus Appearance, Preferences, Utilities and Info. Each configuration has a Route card (This Mac → Wi‑Fi → VPN server → Internet) that draws itself while connecting and shows DNS leaks, then Overview, Log and Settings tabs, and an Advanced sheet.
- **Floating status window**: one compact line (name, status, timer) that expands on click to show speeds, warnings and Disconnect.
- **Sign-in prompts**: the username/password and passphrase prompts.
- **First-run window**: replaces the "There are no VPN configurations installed" dialogs.

The VPN engine is unchanged.

## How it works

The original controllers are still created and their nibs still loaded, but their windows are never shown:
`MyPrefsWindowController` (VPN Details), `SettingsSheetWindowController` (Advanced), `LoginWindowController`,
`PassphraseWindowController`. The SwiftUI views read the state of those hidden AppKit controls and change settings by
clicking them through `TBSwiftUIBridge`. Every original rule still applies, including:

- forced and locked preferences;
- admin authorization;
- validation;
- side effects.

| File(s) | What it is |
|---|---|
| `tunnelblick/TBSwiftUIBridge.h/.m` | The Objective-C bridge. Read the header first. |
| `tunnelblick/Tunnelblick-Bridging-Header.h`, `tunnelblick/TBGlobals.h` | What Swift can see. |
| `tunnelblick/SwiftUI/Core` | App model, legacy-control mirrors, theme, localization helpers. |
| `tunnelblick/SwiftUI/Details` | VPN Details window, sidebar, Route card, Overview and Log. |
| `tunnelblick/SwiftUI/Panes` | Settings tab, Advanced sheet, Appearance, Preferences, Utilities and Info. |
| `tunnelblick/SwiftUI/StatusWindow`, `Auth`, `Welcome` | The other windows. |

Small hooks were added to existing files. Each one is guarded so the classic interface is unaffected:

- **`MenuController.m`**: `openPreferencesWindow:` and `checkNoConfigurations` open the SwiftUI windows. It also posts the state-change and configuration-change notifications.
- **`VPNConnection.m`**: records the DNS-leak and unchanged-public-IP warnings so the interface can show them.
- **`StatusWindowController`, `LoginWindowController`, `PassphraseWindowController`**: host the SwiftUI content when the new interface is on.

## Switching back to the classic windows

You can do this in either of two ways:

- Turn on **Preferences → Use the classic Tunnelblick windows**.
- Run `defaults write net.tunnelblick.tunnelblick useClassicInterface -bool YES` in Terminal, then quit and relaunch Tunnelblick.

## Building

Build as described in "Building Tunnelblick from Source Code.markdown": Xcode 26.0.1, the Legacy build location, and the Manual Order scheme. The Tunnelblick target now compiles Swift:

- `SWIFT_VERSION` is 5.0.
- The bridging header is `Tunnelblick-Bridging-Header.h`.
- The deployment target is still macOS 13.

## Known limitations

- **Untranslated text**: new strings that are not yet in `Localizable.strings` show in English.
- **Legacy alerts**: blocking alerts raised by the legacy code (`TBRunAlertPanel`) still use the system alert style.
