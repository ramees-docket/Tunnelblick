/*
 * Copyright 2026 Tunnelblick contributors
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 */

// Declarations of the global variables that are defined in MenuController.m.
// Before this file existed, each .m file re-declared them with "extern". This header exists so that the
// Swift bridging header (Tunnelblick-Bridging-Header.h) can see them. Objective-C files may keep their own declarations.

#import <Foundation/Foundation.h>

@class MenuController;
@class TBUserDefaults;
@class TunnelblickInfo;

extern MenuController  * gMC;
extern TBUserDefaults  * gTbDefaults;
extern TunnelblickInfo * gTbInfo;
extern NSFileManager   * gFileMgr;
extern NSString        * gPrivatePath;
extern NSString        * gShadowPath;
extern NSString        * gDeployPath;
extern NSMutableArray  * gConfigDirs;
extern NSArray         * gRateUnits;
extern NSArray         * gTotalUnits;
extern BOOL              gShuttingDownTunnelblick;
