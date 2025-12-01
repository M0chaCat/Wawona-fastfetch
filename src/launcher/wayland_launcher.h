#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#include <wayland-server-core.h>

// Wayland Client App Launcher
// Handles discovery and launching of Wayland client applications

@interface WaylandLauncher : NSObject

@property (nonatomic, assign) struct wl_display *display;
@property (nonatomic, strong) NSMutableArray *availableApps;
@property (nonatomic, strong) NSMutableDictionary *runningProcesses;

- (instancetype)initWithDisplay:(struct wl_display *)display;

// App discovery
- (void)scanForApplications;
- (NSArray *)availableApplications;

// App launching
- (BOOL)launchApplication:(NSString *)appId;
- (BOOL)launchApplicationWithPath:(NSString *)appPath;
- (void)terminateApplication:(NSString *)appId;

// Process management
- (BOOL)isApplicationRunning:(NSString *)appId;
- (NSArray *)runningApplications;

// Environment setup
- (void)setupWaylandEnvironment;
- (NSString *)waylandSocketPath;

@end


// App metadata
@interface WaylandApp : NSObject
@property (nonatomic, strong) NSString *appId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *description;
@property (nonatomic, strong) NSString *iconPath;
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, strong) NSArray *categories;
@property (nonatomic, assign) BOOL isRunning;
@end
