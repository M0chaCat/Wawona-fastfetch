#import "WawonaPreferencesManager.h"

// Preferences keys
NSString * const kWawonaPrefsUniversalClipboard = @"UniversalClipboard";
NSString * const kWawonaPrefsForceServerSideDecorations = @"ForceServerSideDecorations";
NSString * const kWawonaPrefsAutoRetinaScaling = @"AutoRetinaScaling";
NSString * const kWawonaPrefsColorSyncSupport = @"ColorSyncSupport";
NSString * const kWawonaPrefsNestedCompositorsSupport = @"NestedCompositorsSupport";
NSString * const kWawonaPrefsUseMetal4ForNested = @"UseMetal4ForNested";
NSString * const kWawonaPrefsRenderMacOSPointer = @"RenderMacOSPointer";
NSString * const kWawonaPrefsMultipleClients = @"MultipleClients";
NSString * const kWawonaPrefsSwapCmdAsCtrl = @"SwapCmdAsCtrl";
NSString * const kWawonaPrefsWaypipeRSSupport = @"WaypipeRSSupport";
NSString * const kWawonaPrefsEnableTCPListener = @"EnableTCPListener";
NSString * const kWawonaPrefsTCPListenerPort = @"TCPListenerPort";
NSString * const kWawonaPrefsWaylandSocketDir = @"WaylandSocketDir";
NSString * const kWawonaPrefsWaylandDisplayNumber = @"WaylandDisplayNumber";
NSString * const kWawonaPrefsEnableVulkanDrivers = @"EnableVulkanDrivers";
NSString * const kWawonaPrefsEnableEGLDrivers = @"EnableEGLDrivers";

@implementation WawonaPreferencesManager

+ (instancetype)sharedManager {
    static WawonaPreferencesManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Set defaults if not already set
        [self setDefaultsIfNeeded];
    }
    return self;
}

- (void)setDefaultsIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Set defaults only if keys don't exist
    if (![defaults objectForKey:kWawonaPrefsUniversalClipboard]) {
        [defaults setBool:YES forKey:kWawonaPrefsUniversalClipboard];
    }
    if (![defaults objectForKey:kWawonaPrefsForceServerSideDecorations]) {
        [defaults setBool:YES forKey:kWawonaPrefsForceServerSideDecorations];
    }
    if (![defaults objectForKey:kWawonaPrefsAutoRetinaScaling]) {
        [defaults setBool:YES forKey:kWawonaPrefsAutoRetinaScaling];
    }
    if (![defaults objectForKey:kWawonaPrefsColorSyncSupport]) {
        [defaults setBool:YES forKey:kWawonaPrefsColorSyncSupport];
    }
    if (![defaults objectForKey:kWawonaPrefsNestedCompositorsSupport]) {
        [defaults setBool:YES forKey:kWawonaPrefsNestedCompositorsSupport];
    }
    if (![defaults objectForKey:kWawonaPrefsUseMetal4ForNested]) {
        [defaults setBool:NO forKey:kWawonaPrefsUseMetal4ForNested];
    }
    if (![defaults objectForKey:kWawonaPrefsRenderMacOSPointer]) {
        [defaults setBool:YES forKey:kWawonaPrefsRenderMacOSPointer];
    }
    if (![defaults objectForKey:kWawonaPrefsMultipleClients]) {
        [defaults setBool:NO forKey:kWawonaPrefsMultipleClients];
    }
    if (![defaults objectForKey:kWawonaPrefsSwapCmdAsCtrl]) {
        [defaults setBool:NO forKey:kWawonaPrefsSwapCmdAsCtrl];
    }
    if (![defaults objectForKey:kWawonaPrefsWaypipeRSSupport]) {
        [defaults setBool:NO forKey:kWawonaPrefsWaypipeRSSupport];
    }
    if (![defaults objectForKey:kWawonaPrefsEnableTCPListener]) {
        [defaults setBool:NO forKey:kWawonaPrefsEnableTCPListener];
    }
    if (![defaults objectForKey:kWawonaPrefsTCPListenerPort]) {
        [defaults setInteger:0 forKey:kWawonaPrefsTCPListenerPort]; // 0 means dynamic
    }
    if (![defaults objectForKey:kWawonaPrefsWaylandSocketDir]) {
        NSString *tmpDir = NSTemporaryDirectory();
        NSString *defaultDir = [tmpDir stringByAppendingPathComponent:@"wayland-runtime"];
        [defaults setObject:defaultDir forKey:kWawonaPrefsWaylandSocketDir];
    }
    if (![defaults objectForKey:kWawonaPrefsWaylandDisplayNumber]) {
        [defaults setInteger:0 forKey:kWawonaPrefsWaylandDisplayNumber];
    }
    if (![defaults objectForKey:kWawonaPrefsEnableVulkanDrivers]) {
        [defaults setBool:YES forKey:kWawonaPrefsEnableVulkanDrivers];
    }
    if (![defaults objectForKey:kWawonaPrefsEnableEGLDrivers]) {
        [defaults setBool:YES forKey:kWawonaPrefsEnableEGLDrivers];
    }
    
    [defaults synchronize];
}

- (void)resetToDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kWawonaPrefsUniversalClipboard];
    [defaults removeObjectForKey:kWawonaPrefsForceServerSideDecorations];
    [defaults removeObjectForKey:kWawonaPrefsAutoRetinaScaling];
    [defaults removeObjectForKey:kWawonaPrefsColorSyncSupport];
    [defaults removeObjectForKey:kWawonaPrefsNestedCompositorsSupport];
    [defaults removeObjectForKey:kWawonaPrefsUseMetal4ForNested];
    [defaults removeObjectForKey:kWawonaPrefsRenderMacOSPointer];
    [defaults removeObjectForKey:kWawonaPrefsMultipleClients];
    [defaults removeObjectForKey:kWawonaPrefsSwapCmdAsCtrl];
    [defaults removeObjectForKey:kWawonaPrefsWaypipeRSSupport];
    [defaults removeObjectForKey:kWawonaPrefsEnableTCPListener];
    [defaults removeObjectForKey:kWawonaPrefsTCPListenerPort];
    [defaults removeObjectForKey:kWawonaPrefsWaylandSocketDir];
    [defaults removeObjectForKey:kWawonaPrefsWaylandDisplayNumber];
    [defaults removeObjectForKey:kWawonaPrefsEnableVulkanDrivers];
    [defaults removeObjectForKey:kWawonaPrefsEnableEGLDrivers];
    [defaults synchronize];
    [self setDefaultsIfNeeded];
}

// Universal Clipboard
- (BOOL)universalClipboardEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsUniversalClipboard];
}

- (void)setUniversalClipboardEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsUniversalClipboard];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Window Decorations
- (BOOL)forceServerSideDecorations {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsForceServerSideDecorations];
}

- (void)setForceServerSideDecorations:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsForceServerSideDecorations];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Display
- (BOOL)autoRetinaScalingEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsAutoRetinaScaling];
}

- (void)setAutoRetinaScalingEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsAutoRetinaScaling];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Color Management
- (BOOL)colorSyncSupportEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsColorSyncSupport];
}

- (void)setColorSyncSupportEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsColorSyncSupport];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Nested Compositors
- (BOOL)nestedCompositorsSupportEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsNestedCompositorsSupport];
}

- (void)setNestedCompositorsSupportEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsNestedCompositorsSupport];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)useMetal4ForNested {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsUseMetal4ForNested];
}

- (void)setUseMetal4ForNested:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsUseMetal4ForNested];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Input
- (BOOL)renderMacOSPointer {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsRenderMacOSPointer];
}

- (void)setRenderMacOSPointer:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsRenderMacOSPointer];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)swapCmdAsCtrl {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsSwapCmdAsCtrl];
}

- (void)setSwapCmdAsCtrl:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsSwapCmdAsCtrl];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Client Management
- (BOOL)multipleClientsEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsMultipleClients];
}

- (void)setMultipleClientsEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsMultipleClients];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Waypipe
- (BOOL)waypipeRSSupportEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsWaypipeRSSupport];
}

- (void)setWaypipeRSSupportEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsWaypipeRSSupport];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Network / Remote Access
- (BOOL)enableTCPListener {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsEnableTCPListener];
}

- (void)setEnableTCPListener:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsEnableTCPListener];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)tcpListenerPort {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kWawonaPrefsTCPListenerPort];
}

- (void)setTCPListenerPort:(NSInteger)port {
    [[NSUserDefaults standardUserDefaults] setInteger:port forKey:kWawonaPrefsTCPListenerPort];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Wayland Configuration
- (NSString *)waylandSocketDir {
    NSString *dir = [[NSUserDefaults standardUserDefaults] stringForKey:kWawonaPrefsWaylandSocketDir];
    if (!dir) {
        NSString *tmpDir = NSTemporaryDirectory();
        dir = [tmpDir stringByAppendingPathComponent:@"wayland-runtime"];
    }
    return dir;
}

- (void)setWaylandSocketDir:(NSString *)dir {
    [[NSUserDefaults standardUserDefaults] setObject:dir forKey:kWawonaPrefsWaylandSocketDir];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)waylandDisplayNumber {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kWawonaPrefsWaylandDisplayNumber];
}

- (void)setWaylandDisplayNumber:(NSInteger)number {
    [[NSUserDefaults standardUserDefaults] setInteger:number forKey:kWawonaPrefsWaylandDisplayNumber];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Rendering Backend Flags
- (BOOL)vulkanDriversEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsEnableVulkanDrivers];
}

- (void)setVulkanDriversEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsEnableVulkanDrivers];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)eglDriversEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWawonaPrefsEnableEGLDrivers];
}

- (void)setEglDriversEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWawonaPrefsEnableEGLDrivers];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
