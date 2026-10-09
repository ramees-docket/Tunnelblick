/*
 * Copyright 2026 Tunnelblick contributors
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 */

// TBSwiftUIBridge connects the SwiftUI interface (tunnelblick/SwiftUI/*.swift) to the existing Objective-C code.
//
// Design: "SwiftUI skin over the legacy controllers"
//
//     The original VPN Details window controller (MyPrefsWindowController, [gMC logScreen]) and its Advanced sheet
//     (SettingsSheetWindowController) are still created and their nibs are still loaded, but their windows are never shown
//     when the new interface is in use. The SwiftUI views read the state of the legacy AppKit controls (checkbox state,
//     enabled/disabled, pop-up items) and change settings by "clicking" those controls through this bridge. That way every
//     rule in the original code (forced/locked preferences, admin authorization, validation, side effects) still applies,
//     and the VPN/preferences logic is unchanged.
//
//     The pref "useClassicInterface" (default NO) switches back to the original windows.
//
// All methods must be called on the main thread.

#import <Cocoa/Cocoa.h>

@class AppearanceView;
@class GeneralView;
@class InfoView;
@class MyPrefsWindowController;
@class UtilitiesView;
@class SettingsSheetWindowController;
@class VPNConnection;

NS_ASSUME_NONNULL_BEGIN

// Posted (object = the VPNConnection) after every connection state change. Main thread.
extern NSString * const TBUIConnectionStateDidChangeNotification;

// Posted after configurations have been added, removed, renamed or moved. Main thread.
extern NSString * const TBUIConfigurationsDidChangeNotification;

// Posted (object = the VPNConnection) when a connection warning (DNS leak / public IP unchanged) is recorded or cleared. Main thread.
extern NSString * const TBUIConnectionWarningsDidChangeNotification;

// Keys in the warning dictionaries returned by +warningsForDisplayName:
extern NSString * const TBUIWarningKindKey;        // NSString: "dnsNotRoutedThroughVpn" or "publicIpUnchanged"
extern NSString * const TBUIWarningAddressKey;     // NSString: the DNS server address or the unchanged public IP address
extern NSString * const TBUIWarningLogLineKey;     // NSString: the exact log text

@interface TBSwiftUIBridge : NSObject

// YES unless the "useClassicInterface" preference is set.
+(BOOL) useNewInterface NS_SWIFT_NAME(useNewInterface());

// ---- Legacy VPN Details controller (loaded but never shown) ----

// Creates [gMC logScreen] if necessary and loads its views and toolbar WITHOUT showing its window.
+(nullable MyPrefsWindowController *) legacyDetails NS_SWIFT_NAME(legacyDetails());

// Makes the hidden legacy controller "display" one of its panes so that its setup code runs.
// pane: one of @"Configurations", @"Appearance", @"Preferences", @"Utilities", @"Info" (English, not localized).
+(void) showLegacyPane: (NSString *) pane NS_SWIFT_NAME(showLegacyPane(_:));

// The legacy pane views (their controls are reachable through their TBPROPERTY accessors)
+(nullable GeneralView *)    legacyGeneralView NS_SWIFT_NAME(legacyGeneralView());     // The "Preferences" pane
+(nullable AppearanceView *) legacyAppearanceView NS_SWIFT_NAME(legacyAppearanceView());
+(nullable UtilitiesView *)  legacyUtilitiesView NS_SWIFT_NAME(legacyUtilitiesView());
+(nullable InfoView *)       legacyInfoView NS_SWIFT_NAME(legacyInfoView());

// The names shown in the configurations list: configuration display names (e.g. "Work/dev") and empty folders (ending in "/").
+(NSArray<NSString *> *) leftNavDisplayNames NS_SWIFT_NAME(leftNavDisplayNames());

// Selects a configuration in the hidden list (this is what the settings controls apply to).
+(void) selectConfigurationWithDisplayName: (NSString *) displayName NS_SWIFT_NAME(selectConfiguration(displayName:));

+(nullable VPNConnection *) selectedConnection NS_SWIFT_NAME(selectedConnection());

// Shows the Log or the Settings tab of the hidden configurations pane. Selecting Log starts monitoring the log files
// of the selected configuration; selecting Settings stops it.
+(void) selectLogTab: (BOOL) log NS_SWIFT_NAME(selectLogTab(_:));

// The text storage the original log code writes into (the hidden NSTextView's storage). Can be shared with
// another NSTextView by adding a second NSLayoutManager to it.
+(nullable NSTextStorage *) logTextStorage NS_SWIFT_NAME(logTextStorage());

// Call when the SwiftUI VPN Details window closes (stops log monitoring, ends admin mode like the original window did).
+(void) detailsWindowDidClose NS_SWIFT_NAME(detailsWindowDidClose());

// ---- Advanced sheet (SettingsSheetWindowController), loaded but never shown ----

// Creates the legacy Advanced controller for the selected configuration (if needed), loads its window without
// showing it, and runs its setup for the selected configuration.
+(nullable SettingsSheetWindowController *) legacyAdvancedForSelectedConfiguration NS_SWIFT_NAME(legacyAdvancedForSelectedConfiguration());

// ---- Admin mode (the lock in the VPN Details toolbar) ----

+(void)     toggleAdminMode NS_SWIFT_NAME(toggleAdminMode());           // Same as clicking the lock
+(BOOL)     adminModeIsOn NS_SWIFT_NAME(adminModeIsOn());
+(BOOL)     adminModeToggleIsEnabled NS_SWIFT_NAME(adminModeToggleIsEnabled());  // NO while waiting for authorization
+(NSString *) adminModeLabel NS_SWIFT_NAME(adminModeLabel());          // "Enter admin mode", "Authorizing...", or the label with the time left

// ---- Controls ----

// Same as the user clicking the checkbox or button: changes its state (for checkboxes) and sends its action.
+(void) clickButton: (NSButton *) button NS_SWIFT_NAME(click(_:));

// Same as the user choosing an item in the pop-up button. Handles pop-ups whose selection is bound with Cocoa Bindings,
// pop-ups whose menu items have their own actions, and plain pop-ups.
+(void) choosePopUpButton: (NSPopUpButton *) popUp itemAtIndex: (NSInteger) index NS_SWIFT_NAME(choose(_:index:));

// YES if the item's target allows it (runs validateMenuItem: like a menu would).
+(BOOL) menuItemIsEnabled: (NSMenuItem *) item NS_SWIFT_NAME(isEnabled(_:));

// Performs the menu item's action if it is enabled. Returns NO if it is not enabled.
+(BOOL) performMenuItem: (NSMenuItem *) item NS_SWIFT_NAME(perform(_:));

// ---- Statistics ----

// Same calculation the status window uses. Keys (NSNumber): inRate, outRate (bytes/second), inTotal, outTotal (bytes).
+(NSDictionary<NSString *, NSNumber *> *) statisticsForConnection: (VPNConnection *) connection NS_SWIFT_NAME(statistics(for:));

// Formats a byte count the way Tunnelblick does (e.g. "1.23" and "MB"). rate: YES uses the rate units (KB/s...).
+(NSString *) formattedNumber: (double) value rate: (BOOL) rate NS_SWIFT_NAME(formatted(_:rate:));

// ---- Warnings recorded while connected (DNS server not routed through the VPN; public IP did not change) ----

+(NSArray<NSDictionary<NSString *, NSString *> *> *) warningsForDisplayName: (NSString *) displayName NS_SWIFT_NAME(warnings(displayName:));

// Called from VPNConnection.
+(void) recordWarningOfKind: (NSString *) kind address: (NSString *) address logLine: (NSString *) logLine forDisplayName: (NSString *) displayName NS_SWIFT_NAME(recordWarning(kind:address:logLine:displayName:));
+(void) clearWarningsForDisplayName: (NSString *) displayName NS_SWIFT_NAME(clearWarnings(displayName:));

// ---- Hooks called from MenuController ----

+(void) connectionStateDidChange: (VPNConnection *) connection NS_SWIFT_NAME(connectionStateDidChange(_:));
+(void) configurationsDidChange NS_SWIFT_NAME(configurationsDidChange());

@end

NS_ASSUME_NONNULL_END
