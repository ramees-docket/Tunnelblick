/*
 * Copyright 2026 Tunnelblick contributors
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 */

// This file uses manual retain/release, like the rest of Tunnelblick.

#import "TBSwiftUIBridge.h"

#import <math.h>

#import "defines.h"
#import "helper.h"

#import "AppearanceView.h"
#import "ConfigurationsView.h"
#import "GeneralView.h"
#import "InfoView.h"
#import "UtilitiesView.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "SettingsSheetWindowController.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern MenuController * gMC;
extern TBUserDefaults * gTbDefaults;
extern NSArray        * gRateUnits;
extern NSArray        * gTotalUnits;

NSString * const TBUIConnectionStateDidChangeNotification    = @"TBUIConnectionStateDidChangeNotification";
NSString * const TBUIConfigurationsDidChangeNotification     = @"TBUIConfigurationsDidChangeNotification";
NSString * const TBUIConnectionWarningsDidChangeNotification = @"TBUIConnectionWarningsDidChangeNotification";

NSString * const TBUIWarningKindKey    = @"kind";
NSString * const TBUIWarningAddressKey = @"address";
NSString * const TBUIWarningLogLineKey = @"logLine";

// Methods that exist in the legacy classes but are not declared in their headers
@interface MenuController (TBSwiftUIBridgePrivate)
-(void) createPreferencesWindow;
@end

@interface DBPrefsWindowController (TBSwiftUIBridgePrivate)
-(void) setupToolbar;
-(void) windowWillAppear;
-(void) displayViewForIdentifier: (NSString *) identifier animate: (BOOL) animate;
@end

@interface MyPrefsWindowController (TBSwiftUIBridgePrivate)
-(void) selectLeftNavName: (NSString *) name;
-(void) toggleLockItem;
@end

@interface MyPrefsWindowController (TBSwiftUIBridge)
-(void)            tbsui_loadHidden;
-(void)            tbsui_displayPaneWithIdentifier: (NSString *) identifier;
-(BOOL)            tbsui_lockIsUnlocked;
-(NSToolbarItem *) tbsui_lockItem;
-(SettingsSheetWindowController *) tbsui_advancedControllerCreatingIfNeeded;
-(GeneralView *)    tbsui_generalView;
-(AppearanceView *) tbsui_appearanceView;
-(UtilitiesView *)  tbsui_utilitiesView;
-(InfoView *)       tbsui_infoView;
@end

@implementation MyPrefsWindowController (TBSwiftUIBridge)

-(void) tbsui_loadHidden {

    // Same as -[DBPrefsWindowController showWindow:] but without showing the window

    (void) [self window];

    if (  [[self window] toolbar] == nil  ) {
        [self setupToolbar];
        NSToolbar * toolbar = [[NSToolbar alloc] initWithIdentifier: @"DBPreferencesToolbar"];
        [toolbar setAllowsUserCustomization: NO];
        [toolbar setAutosavesConfiguration:  NO];
        [toolbar setSizeMode:    NSToolbarSizeModeDefault];
        [toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
        [toolbar setDelegate: self];
        [[self window] setToolbar: toolbar];
        [toolbar release];

        NSString * configurationsIdentifier = NSLocalizedString(@"Configurations", @"Window title");
        [[[self window] toolbar] setSelectedItemIdentifier: configurationsIdentifier];
        [self displayViewForIdentifier: configurationsIdentifier animate: NO];

        [self windowWillAppear];
    }
}

-(void) tbsui_displayPaneWithIdentifier: (NSString *) identifier {

    if (  [toolbarIdentifiers containsObject: identifier]  ) {
        [[[self window] toolbar] setSelectedItemIdentifier: identifier];
        [self displayViewForIdentifier: identifier animate: NO];
    } else {
        NSLog(@"TBSwiftUIBridge: no pane with identifier '%@'", identifier);
    }
}

-(GeneralView *)    tbsui_generalView    { return generalPrefsView;    }
-(AppearanceView *) tbsui_appearanceView { return appearancePrefsView; }
-(UtilitiesView *)  tbsui_utilitiesView  { return utilitiesPrefsView;  }
-(InfoView *)       tbsui_infoView       { return infoPrefsView;       }

-(BOOL) tbsui_lockIsUnlocked {
    return lockIconIsUnlocked;
}

-(NSToolbarItem *) tbsui_lockItem {
    return [toolbarItems objectForKey: @"lockIcon"];
}

-(SettingsSheetWindowController *) tbsui_advancedControllerCreatingIfNeeded {

    // Same as -advancedButtonWasClicked: but does not show the window

    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        return nil;
    }

    if (  settingsSheetWindowController == nil  ) {
        settingsSheetWindowController = [[SettingsSheetWindowController alloc] init];
    }

    [settingsSheetWindowController setConfigurationName: [connection displayName]];
    (void) [settingsSheetWindowController window]; // Loads the nib; -awakeFromNib sets up the controls
    [settingsSheetWindowController setupSettingsFromPreferences];

    return settingsSheetWindowController;
}

@end


static NSMutableDictionary * warningsByDisplayName = nil; // displayName -> NSMutableArray of NSDictionary


@implementation TBSwiftUIBridge

+(BOOL) useNewInterface {
    return ! [gTbDefaults boolForKey: @"useClassicInterface"];
}

// ---- Legacy VPN Details controller

+(MyPrefsWindowController *) legacyDetails {

    if (  ! [gMC logScreen]  ) {
        [gMC createPreferencesWindow];
    }

    MyPrefsWindowController * details = [gMC logScreen];
    [details tbsui_loadHidden];
    return details;
}

+(void) showLegacyPane: (NSString *) pane {

    // pane is the English name. The toolbar identifiers are the localized names (see -[MyPrefsWindowController setupToolbar]).
    NSString * identifier = nil;
    if (        [pane isEqualToString: @"Configurations"]  ) {
        identifier = NSLocalizedString(@"Configurations", @"Window title");
    } else if ( [pane isEqualToString: @"Appearance"]  ) {
        identifier = NSLocalizedString(@"Appearance",     @"Window title");
    } else if ( [pane isEqualToString: @"Preferences"]  ) {
        identifier = NSLocalizedString(@"Preferences",    @"Window title");
    } else if ( [pane isEqualToString: @"Utilities"]  ) {
        identifier = NSLocalizedString(@"Utilities",      @"Window title");
    } else if ( [pane isEqualToString: @"Info"]  ) {
        identifier = NSLocalizedString(@"Info",           @"Window title");
    } else {
        NSLog(@"TBSwiftUIBridge: unknown pane '%@'", pane);
        return;
    }

    [[self legacyDetails] tbsui_displayPaneWithIdentifier: identifier];
}

+(GeneralView *)    legacyGeneralView    { return [[self legacyDetails] tbsui_generalView];    }
+(AppearanceView *) legacyAppearanceView { return [[self legacyDetails] tbsui_appearanceView]; }
+(UtilitiesView *)  legacyUtilitiesView  { return [[self legacyDetails] tbsui_utilitiesView];  }
+(InfoView *)       legacyInfoView       { return [[self legacyDetails] tbsui_infoView];       }

+(NSArray<NSString *> *) leftNavDisplayNames {
    NSArray * names = [[self legacyDetails] leftNavDisplayNames];
    return (  names
            ? names
            : [NSArray array]);
}

+(void) selectConfigurationWithDisplayName: (NSString *) displayName {

    MyPrefsWindowController * details = [self legacyDetails];
    if (  [[[details selectedConnection] displayName] isEqualToString: displayName]  ) {
        return;
    }

    [details selectLeftNavName: displayName];
}

+(VPNConnection *) selectedConnection {
    return [[self legacyDetails] selectedConnection];
}

+(void) selectLogTab: (BOOL) log {

    ConfigurationsView * view = [[self legacyDetails] configurationsPrefsView];
    NSTabViewItem * item = (  log
                            ? [view logTabViewItem]
                            : [view settingsTabViewItem]);
    if (  [[view configurationsTabView] selectedTabViewItem] != item  ) {
        [[view configurationsTabView] selectTabViewItem: item]; // The tab view's delegate starts/stops log monitoring
    } else if (  log  ) {
        [[self selectedConnection] startMonitoringLogFiles];
    }
}

+(NSTextStorage *) logTextStorage {
    return [[[[self legacyDetails] configurationsPrefsView] logView] textStorage];
}

+(void) detailsWindowDidClose {

    MyPrefsWindowController * details = [gMC logScreen];
    if (  ! details  ) {
        return;
    }

    [[details selectedConnection] stopMonitoringLogFiles];

    if (  [details tbsui_lockIsUnlocked]  ) {
        [details lockTheLockIcon];
    }
}

// ---- Advanced sheet

+(SettingsSheetWindowController *) legacyAdvancedForSelectedConfiguration {
    return [[self legacyDetails] tbsui_advancedControllerCreatingIfNeeded];
}

// ---- Admin mode

+(void) toggleAdminMode {
    [[self legacyDetails] toggleLockItem];
}

+(BOOL) adminModeIsOn {
    return [[self legacyDetails] tbsui_lockIsUnlocked];
}

+(BOOL) adminModeToggleIsEnabled {
    NSToolbarItem * item = [[self legacyDetails] tbsui_lockItem];
    return (  item
            ? [item isEnabled]
            : NO);
}

+(NSString *) adminModeLabel {
    NSString * label = [[[self legacyDetails] tbsui_lockItem] label];
    return (  label
            ? label
            : NSLocalizedString(@"Enter admin mode", @"Toolbar text for 'Lock' item"));
}

// ---- Controls

+(void) clickButton: (NSButton *) button {

    if (  ! button  ) {
        NSLog(@"TBSwiftUIBridge clickButton: button is nil");
        return;
    }

    if (  ! [button isEnabled]  ) {
        return;
    }

    [button performClick: nil];
}

+(id) targetForAction: (SEL) action ofObject: (id) object fallbackFromView: (NSView *) view {

    id target = [object target];
    if (  target  ) {
        return target;
    }

    id windowController = [[view window] windowController];
    if (  [windowController respondsToSelector: action]  ) {
        return windowController;
    }

    id details = [gMC logScreen];
    if (  [details respondsToSelector: action]  ) {
        return details;
    }

    return nil;
}

+(void) choosePopUpButton: (NSPopUpButton *) popUp itemAtIndex: (NSInteger) index {

    if (  ! popUp  ) {
        NSLog(@"TBSwiftUIBridge choosePopUpButton: pop-up button is nil");
        return;
    }

    if (   ( index < 0 )
        || ( index >= [popUp numberOfItems] )  ) {
        NSLog(@"TBSwiftUIBridge choosePopUpButton: index %ld is out of range (%ld items)", (long) index, (long) [popUp numberOfItems]);
        return;
    }

    if (  ! [popUp isEnabled]  ) {
        return;
    }

    // 1. Selection bound with Cocoa Bindings: set the bound key (its setter contains the logic)
    NSDictionary * info = [popUp infoForBinding: NSSelectedIndexBinding];
    if (  info  ) {
        id         observed = [info objectForKey: NSObservedObjectKey];
        NSString * keyPath  = [info objectForKey: NSObservedKeyPathKey];
        if (   observed
            && keyPath  ) {
            [observed setValue: [NSNumber numberWithInteger: index] forKeyPath: keyPath];
            return;
        }
    }

    NSMenuItem * item = [popUp itemAtIndex: index];

    // 2. The menu item has its own action
    SEL itemAction = [item action];
    if (  itemAction  ) {
        if (  ! [self menuItemIsEnabled: item]  ) {
            return;
        }
        id target = [self targetForAction: itemAction ofObject: item fallbackFromView: popUp];
        [popUp selectItemAtIndex: index];
        [NSApp sendAction: itemAction to: target from: item];
        return;
    }

    // 3. Plain pop-up button
    [popUp selectItemAtIndex: index];
    SEL popUpAction = [popUp action];
    if (  popUpAction  ) {
        id target = [self targetForAction: popUpAction ofObject: popUp fallbackFromView: popUp];
        [NSApp sendAction: popUpAction to: target from: popUp];
    }
}

+(BOOL) menuItemIsEnabled: (NSMenuItem *) item {

    if (  ! item  ) {
        return NO;
    }

    SEL action = [item action];
    if (  ! action  ) {
        return [item isEnabled];
    }

    id target = [item target];
    if (  ! target  ) {
        target = [gMC logScreen];
    }

    if (  [target respondsToSelector: @selector(validateMenuItem:)]  ) {
        return [target validateMenuItem: item];
    }

    return [item isEnabled];
}

+(BOOL) performMenuItem: (NSMenuItem *) item {

    if (  ! [self menuItemIsEnabled: item]  ) {
        return NO;
    }

    SEL action = [item action];
    if (  ! action  ) {
        return NO;
    }

    id target = [item target];
    if (  ! target  ) {
        target = [gMC logScreen];
    }

    return [NSApp sendAction: action to: target from: item];
}

// ---- Statistics (same calculation as -[VPNConnection updateDisplayWithNewStatistics])

+(NSDictionary<NSString *, NSNumber *> *) statisticsForConnection: (VPNConnection *) connection {

    struct Statistics stats;
    [connection readStatisticsTo: &stats];

    double inTotal  = (double) (stats.totalInBytecount  + stats.totalInByteCountBeforeThisConnection);
    double outTotal = (double) (stats.totalOutBytecount + stats.totalOutByteCountBeforeThisConnection);

    double inRate  = 0.0;
    double outRate = 0.0;

    NSTimeInterval rateTimeInterval = [gTbDefaults timeIntervalForKey: @"statisticsRateTimeInterval"
                                                              default: 3.0
                                                                  min: 1.0
                                                                  max: 60.0];

    NSTimeInterval timeSinceLastSet = (  stats.lastSet
                                       ? fabs([stats.lastSet timeIntervalSinceNow])
                                       : rateTimeInterval + 1.0);

    rateTimeInterval = rateTimeInterval - timeSinceLastSet;
    if (  rateTimeInterval >= 0.0  ) {
        TBByteCount    tInBytes  = 0;
        TBByteCount    tOutBytes = 0;
        NSTimeInterval tTimeInt  = 0.0;
        int            ix        = stats.rbIx;
        int            nPulled;
        for (  nPulled=0; nPulled<RB_SIZE; nPulled++  ) {
            if (  ix == 0  ) {
                ix = RB_SIZE;
            }
            ix--;

            tTimeInt  += stats.rb[ix].lastTimeInterval;
            tInBytes  += stats.rb[ix].lastInBytecount;
            tOutBytes += stats.rb[ix].lastOutBytecount;

            if (  tTimeInt > rateTimeInterval  ) {
                break;
            }
        }

        if (  tTimeInt > 0.0  ) {
            inRate  = (double) tInBytes  / tTimeInt;
            outRate = (double) tOutBytes / tTimeInt;
        }
    }

    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithDouble: inRate],   @"inRate",
            [NSNumber numberWithDouble: outRate],  @"outRate",
            [NSNumber numberWithDouble: inTotal],  @"inTotal",
            [NSNumber numberWithDouble: outTotal], @"outTotal",
            nil];
}

+(NSString *) formattedNumber: (double) value rate: (BOOL) rate {

    // Same as -[VPNConnection setNumber:andUnits:from:unitsArray:], but returns "<number> <units>"

    NSArray * unitsArray = (  rate
                            ? gRateUnits
                            : gTotalUnits);

    if (  value < 0.0  ) {
        value = 0.0;
    }

    unsigned i = 0;
    double n = value;
    while (  n > 999.0  ) {
        i++;
        n = value / pow(10.0, (double) (i * 3));
    }

    if (  i >= [unitsArray count]  ) {
        return @"***";
    }

    NSString * units = [unitsArray objectAtIndex: i];
    NSString * number;

    if (  i == 0  ) {
        number = [NSString stringWithFormat: @"%llu", (unsigned long long) value];
    } else {
        unsigned n100 = (unsigned) round(n * 100.0);
        unsigned displayInteger  = n100 / 100u;
        unsigned displayFraction = n100 - (displayInteger * 100u);
        if (  n100 < 1000u  ) {
            number = [NSString stringWithFormat: @"%u.%02u", displayInteger, displayFraction];
        } else if (  n100 < 10000u  ) {
            number = [NSString stringWithFormat: @"%u.%01u", displayInteger, (displayFraction + 5u) / 10u];
        } else {
            if (   (displayFraction > 49u)
                && (displayInteger < 999u)  ) {
                displayInteger++;
            }
            number = [NSString stringWithFormat: @"%u", displayInteger];
        }
    }

    return [NSString stringWithFormat: @"%@ %@", number, units];
}

// ---- Warnings

+(NSArray<NSDictionary<NSString *, NSString *> *> *) warningsForDisplayName: (NSString *) displayName {

    NSArray * warnings = [warningsByDisplayName objectForKey: displayName];
    return (  warnings
            ? [NSArray arrayWithArray: warnings]
            : [NSArray array]);
}

+(void) postWarningsChangedForDisplayName: (NSString *) displayName {

    VPNConnection * connection = [gMC connectionForDisplayName: displayName];
    [[NSNotificationCenter defaultCenter] postNotificationName: TBUIConnectionWarningsDidChangeNotification object: connection];
}

+(void) recordWarningOfKind: (NSString *) kind address: (NSString *) address logLine: (NSString *) logLine forDisplayName: (NSString *) displayName {

    if (  ! [NSThread isMainThread]  ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [TBSwiftUIBridge recordWarningOfKind: kind address: address logLine: logLine forDisplayName: displayName];
        });
        return;
    }

    if (  ! displayName  ) {
        return;
    }

    if (  ! warningsByDisplayName  ) {
        warningsByDisplayName = [[NSMutableDictionary alloc] initWithCapacity: 10];
    }

    NSMutableArray * warnings = [warningsByDisplayName objectForKey: displayName];
    if (  ! warnings  ) {
        warnings = [NSMutableArray arrayWithCapacity: 4];
        [warningsByDisplayName setObject: warnings forKey: displayName];
    }

    NSDictionary * warning = [NSDictionary dictionaryWithObjectsAndKeys:
                              (kind    ? kind    : @""), TBUIWarningKindKey,
                              (address ? address : @""), TBUIWarningAddressKey,
                              (logLine ? logLine : @""), TBUIWarningLogLineKey,
                              nil];
    if (  ! [warnings containsObject: warning]  ) {
        [warnings addObject: warning];
        [self postWarningsChangedForDisplayName: displayName];
    }
}

+(void) clearWarningsForDisplayName: (NSString *) displayName {

    if (  ! [NSThread isMainThread]  ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [TBSwiftUIBridge clearWarningsForDisplayName: displayName];
        });
        return;
    }

    if (  ! displayName  ) {
        return;
    }

    if (  [[warningsByDisplayName objectForKey: displayName] count] != 0  ) {
        [warningsByDisplayName removeObjectForKey: displayName];
        [self postWarningsChangedForDisplayName: displayName];
    }
}

// ---- Hooks

+(void) connectionStateDidChange: (VPNConnection *) connection {

    // A new connection attempt starts with no warnings
    NSString * state = [connection state];
    if (   [state isEqualToString: @"RESOLVE"]
        || [state isEqualToString: @"TCP_CONNECT"]
        || [state isEqualToString: @"UDP_CONNECT"]
        || [state isEqualToString: @"SLEEP"]  ) {
        [self clearWarningsForDisplayName: [connection displayName]];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName: TBUIConnectionStateDidChangeNotification object: connection];
}

+(void) configurationsDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName: TBUIConfigurationsDidChangeNotification object: nil];
}

@end
