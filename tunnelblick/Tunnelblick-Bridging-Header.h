/*
 * Copyright 2026 Tunnelblick contributors
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 */

// Objective-C declarations visible to the Swift files in tunnelblick/SwiftUI.
//
// Many Tunnelblick headers rely on the prefix header (Tunnelblick_Prefix.pch) for Cocoa, and Swift does not see the
// prefix header, so Cocoa must be imported first.
//
// Do not import WelcomeController.h (legacy WebKit) or any VPNService*.h (compiled out).

#import <Cocoa/Cocoa.h>

#import "defines.h"
#import "helper.h"
#import "TBGlobals.h"

#import "AppearanceView.h"
#import "AuthAgent.h"
#import "ConfigurationManager.h"
#import "ConfigurationsView.h"
#import "GeneralView.h"
#import "InfoView.h"
#import "LoginWindowController.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "PassphraseWindowController.h"
#import "SettingsSheetWindowController.h"
#import "StatusWindowController.h"
#import "SystemAuth.h"
#import "TBButton.h"
#import "TBOperationQueue.h"
#import "TBPopUpButton.h"
#import "TBSwiftUIBridge.h"
#import "TBUserDefaults.h"
#import "TunnelblickInfo.h"
#import "UIHelper.h"
#import "UtilitiesView.h"
#import "VPNConnection.h"
