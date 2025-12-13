#import "WawonaPreferencesManager.h"

// Preferences keys
NSString *const kWawonaPrefsUniversalClipboard = @"UniversalClipboard";
NSString *const kWawonaPrefsForceServerSideDecorations =
    @"ForceServerSideDecorations";
NSString *const kWawonaPrefsAutoRetinaScaling = @"AutoRetinaScaling"; // Legacy
NSString *const kWawonaPrefsAutoScale = @"AutoScale"; // New unified key
NSString *const kWawonaPrefsColorSyncSupport = @"ColorSyncSupport"; // Legacy
NSString *const kWawonaPrefsColorOperations = @"ColorOperations"; // New unified key
NSString *const kWawonaPrefsNestedCompositorsSupport =
    @"NestedCompositorsSupport";
NSString *const kWawonaPrefsUseMetal4ForNested = @"UseMetal4ForNested"; // Deprecated
NSString *const kWawonaPrefsRenderMacOSPointer = @"RenderMacOSPointer";
NSString *const kWawonaPrefsMultipleClients = @"MultipleClients";
NSString *const kWawonaPrefsSwapCmdAsCtrl = @"SwapCmdAsCtrl"; // Legacy
NSString *const kWawonaPrefsSwapCmdWithAlt = @"SwapCmdWithAlt"; // New unified key
NSString *const kWawonaPrefsWaypipeRSSupport = @"WaypipeRSSupport"; // Deprecated - always enabled
NSString *const kWawonaPrefsEnableTCPListener = @"EnableTCPListener"; // Deprecated - always enabled
NSString *const kWawonaPrefsTCPListenerPort = @"TCPListenerPort";
NSString *const kWawonaPrefsWaylandSocketDir = @"WaylandSocketDir";
NSString *const kWawonaPrefsWaylandDisplayNumber = @"WaylandDisplayNumber";
NSString *const kWawonaPrefsEnableVulkanDrivers = @"EnableVulkanDrivers";
NSString *const kWawonaPrefsEnableEGLDrivers = @"EnableEGLDrivers";
NSString *const kWawonaPrefsEnableDmabuf = @"EnableDmabuf";
NSString *const kWawonaPrefsRespectSafeArea = @"RespectSafeArea";
// Waypipe configuration keys
NSString *const kWawonaPrefsWaypipeDisplay = @"WaypipeDisplay";
NSString *const kWawonaPrefsWaypipeSocket = @"WaypipeSocket";
NSString *const kWawonaPrefsWaypipeCompress = @"WaypipeCompress";
NSString *const kWawonaPrefsWaypipeCompressLevel = @"WaypipeCompressLevel";
NSString *const kWawonaPrefsWaypipeThreads = @"WaypipeThreads";
NSString *const kWawonaPrefsWaypipeVideo = @"WaypipeVideo";
NSString *const kWawonaPrefsWaypipeVideoEncoding = @"WaypipeVideoEncoding";
NSString *const kWawonaPrefsWaypipeVideoDecoding = @"WaypipeVideoDecoding";
NSString *const kWawonaPrefsWaypipeVideoBpf = @"WaypipeVideoBpf";
NSString *const kWawonaPrefsWaypipeSSHEnabled = @"WaypipeSSHEnabled";
NSString *const kWawonaPrefsWaypipeSSHHost = @"WaypipeSSHHost";
NSString *const kWawonaPrefsWaypipeSSHUser = @"WaypipeSSHUser";
NSString *const kWawonaPrefsWaypipeSSHBinary = @"WaypipeSSHBinary";
NSString *const kWawonaPrefsWaypipeRemoteCommand = @"WaypipeRemoteCommand";
NSString *const kWawonaPrefsWaypipeCustomScript = @"WaypipeCustomScript";
NSString *const kWawonaPrefsWaypipeDebug = @"WaypipeDebug";
NSString *const kWawonaPrefsWaypipeNoGpu = @"WaypipeNoGpu";
NSString *const kWawonaPrefsWaypipeOneshot = @"WaypipeOneshot";
NSString *const kWawonaPrefsWaypipeUnlinkSocket = @"WaypipeUnlinkSocket";
NSString *const kWawonaPrefsWaypipeLoginShell = @"WaypipeLoginShell";
NSString *const kWawonaPrefsWaypipeVsock = @"WaypipeVsock";
NSString *const kWawonaPrefsWaypipeXwls = @"WaypipeXwls";
NSString *const kWawonaPrefsWaypipeTitlePrefix = @"WaypipeTitlePrefix";
NSString *const kWawonaPrefsWaypipeSecCtx = @"WaypipeSecCtx";

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
    [defaults setBool:NO forKey:kWawonaPrefsRenderMacOSPointer]; // Off by default on macOS
  }
  if (![defaults objectForKey:kWawonaPrefsMultipleClients]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [defaults setBool:NO forKey:kWawonaPrefsMultipleClients]; // Disabled on iOS/Android (matching Android default)
#else
    [defaults setBool:YES forKey:kWawonaPrefsMultipleClients]; // Enabled on macOS
#endif
  }
  if (![defaults objectForKey:kWawonaPrefsSwapCmdAsCtrl]) {
    [defaults setBool:NO forKey:kWawonaPrefsSwapCmdAsCtrl];
  }
  // Migration: Convert old keys to new unified keys
  if ([defaults objectForKey:kWawonaPrefsAutoRetinaScaling] && ![defaults objectForKey:kWawonaPrefsAutoScale]) {
    BOOL oldValue = [defaults boolForKey:kWawonaPrefsAutoRetinaScaling];
    [defaults setBool:oldValue forKey:kWawonaPrefsAutoScale];
  }
  if (![defaults objectForKey:kWawonaPrefsAutoScale]) {
    [defaults setBool:YES forKey:kWawonaPrefsAutoScale]; // Default on for all platforms
  }
  if ([defaults objectForKey:kWawonaPrefsColorSyncSupport] && ![defaults objectForKey:kWawonaPrefsColorOperations]) {
    BOOL oldValue = [defaults boolForKey:kWawonaPrefsColorSyncSupport];
    [defaults setBool:oldValue forKey:kWawonaPrefsColorOperations];
  }
  if (![defaults objectForKey:kWawonaPrefsColorOperations]) {
    [defaults setBool:YES forKey:kWawonaPrefsColorOperations]; // Default enabled
  }
  if ([defaults objectForKey:kWawonaPrefsSwapCmdAsCtrl] && ![defaults objectForKey:kWawonaPrefsSwapCmdWithAlt]) {
    BOOL oldValue = [defaults boolForKey:kWawonaPrefsSwapCmdAsCtrl];
    [defaults setBool:oldValue forKey:kWawonaPrefsSwapCmdWithAlt];
  }
  if (![defaults objectForKey:kWawonaPrefsSwapCmdWithAlt]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [defaults setBool:YES forKey:kWawonaPrefsSwapCmdWithAlt]; // Default on for macOS/iOS
#else
    [defaults setBool:YES forKey:kWawonaPrefsSwapCmdWithAlt]; // Default on for macOS/iOS
#endif
  }
  if (![defaults objectForKey:kWawonaPrefsRespectSafeArea]) {
    [defaults setBool:YES forKey:kWawonaPrefsRespectSafeArea]; // Default on
  }
  // Waypipe configuration defaults
  if (![defaults objectForKey:kWawonaPrefsWaypipeDisplay]) {
    [defaults setObject:@"wayland-0" forKey:kWawonaPrefsWaypipeDisplay];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSocket]) {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *defaultSocket = [tmpDir stringByAppendingPathComponent:@"waypipe"];
    [defaults setObject:defaultSocket forKey:kWawonaPrefsWaypipeSocket];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeCompress]) {
    [defaults setObject:@"lz4" forKey:kWawonaPrefsWaypipeCompress];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeCompressLevel]) {
    [defaults setObject:@"7" forKey:kWawonaPrefsWaypipeCompressLevel];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeThreads]) {
    [defaults setObject:@"0" forKey:kWawonaPrefsWaypipeThreads]; // 0 = auto
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeVideo]) {
    [defaults setObject:@"none" forKey:kWawonaPrefsWaypipeVideo];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeVideoEncoding]) {
    [defaults setObject:@"hw" forKey:kWawonaPrefsWaypipeVideoEncoding];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeVideoDecoding]) {
    [defaults setObject:@"hw" forKey:kWawonaPrefsWaypipeVideoDecoding];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeVideoBpf]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeVideoBpf];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSSHEnabled]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeSSHEnabled];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSSHHost]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeSSHHost];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSSHUser]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeSSHUser];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSSHBinary]) {
    [defaults setObject:@"ssh" forKey:kWawonaPrefsWaypipeSSHBinary];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeRemoteCommand]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeRemoteCommand];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeCustomScript]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeCustomScript];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeDebug]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeDebug];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeNoGpu]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeNoGpu];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeOneshot]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeOneshot];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeUnlinkSocket]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeUnlinkSocket];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeLoginShell]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeLoginShell];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeVsock]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeVsock];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeXwls]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeXwls]; // Disabled/unavailable
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeTitlePrefix]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeTitlePrefix];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSecCtx]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeSecCtx];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeRSSupport]) {
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeRSSupport];
  }
  if (![defaults objectForKey:kWawonaPrefsEnableTCPListener]) {
    [defaults setBool:NO forKey:kWawonaPrefsEnableTCPListener];
  }
  if (![defaults objectForKey:kWawonaPrefsTCPListenerPort]) {
    [defaults setInteger:0
                  forKey:kWawonaPrefsTCPListenerPort]; // 0 means dynamic
  }
  if (![defaults objectForKey:kWawonaPrefsWaylandSocketDir]) {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *defaultDir =
        [tmpDir stringByAppendingPathComponent:@"wayland-runtime"];
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
  if (![defaults objectForKey:kWawonaPrefsEnableDmabuf]) {
    [defaults setBool:YES forKey:kWawonaPrefsEnableDmabuf];
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
  [defaults removeObjectForKey:kWawonaPrefsEnableDmabuf];
  [defaults synchronize];
  [self setDefaultsIfNeeded];
}

// Universal Clipboard
- (BOOL)universalClipboardEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsUniversalClipboard];
}

- (void)setUniversalClipboardEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWawonaPrefsUniversalClipboard];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Window Decorations
- (BOOL)forceServerSideDecorations {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsForceServerSideDecorations];
}

- (void)setForceServerSideDecorations:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWawonaPrefsForceServerSideDecorations];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Display
- (BOOL)autoRetinaScalingEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsAutoRetinaScaling];
}

- (void)setAutoRetinaScalingEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsAutoRetinaScaling];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Color Management
- (BOOL)colorSyncSupportEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsColorSyncSupport];
}

- (void)setColorSyncSupportEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsColorSyncSupport];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Nested Compositors
- (BOOL)nestedCompositorsSupportEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsNestedCompositorsSupport];
}

- (void)setNestedCompositorsSupportEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWawonaPrefsNestedCompositorsSupport];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)useMetal4ForNested {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsUseMetal4ForNested];
}

- (void)setUseMetal4ForNested:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWawonaPrefsUseMetal4ForNested];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Input
- (BOOL)renderMacOSPointer {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsRenderMacOSPointer];
}

- (void)setRenderMacOSPointer:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWawonaPrefsRenderMacOSPointer];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)swapCmdAsCtrl {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsSwapCmdAsCtrl];
}

- (void)setSwapCmdAsCtrl:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsSwapCmdAsCtrl];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Client Management
- (BOOL)multipleClientsEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsMultipleClients];
}

- (void)setMultipleClientsEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsMultipleClients];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Waypipe
- (BOOL)waypipeRSSupportEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeRSSupport];
}

- (void)setWaypipeRSSupportEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeRSSupport];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Network / Remote Access
- (BOOL)enableTCPListener {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsEnableTCPListener];
}

- (void)setEnableTCPListener:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsEnableTCPListener];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)tcpListenerPort {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:kWawonaPrefsTCPListenerPort];
}

- (void)setTCPListenerPort:(NSInteger)port {
  [[NSUserDefaults standardUserDefaults]
      setInteger:port
          forKey:kWawonaPrefsTCPListenerPort];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Wayland Configuration
- (NSString *)waylandSocketDir {
  NSString *dir = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaylandSocketDir];
  if (!dir) {
    const char *envDir = getenv("XDG_RUNTIME_DIR");
    if (envDir) {
        dir = [NSString stringWithUTF8String:envDir];
    } else {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        NSString *tmpDir = NSTemporaryDirectory();
        dir = [tmpDir stringByAppendingPathComponent:@"wayland-runtime"];
#else
        dir = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
#endif
    }
  }
  return dir;
}

- (void)setWaylandSocketDir:(NSString *)dir {
  [[NSUserDefaults standardUserDefaults]
      setObject:dir
         forKey:kWawonaPrefsWaylandSocketDir];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)waylandDisplayNumber {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:kWawonaPrefsWaylandDisplayNumber];
}

- (void)setWaylandDisplayNumber:(NSInteger)number {
  [[NSUserDefaults standardUserDefaults]
      setInteger:number
          forKey:kWawonaPrefsWaylandDisplayNumber];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Rendering Backend Flags
- (BOOL)vulkanDriversEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsEnableVulkanDrivers];
}

- (void)setVulkanDriversEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWawonaPrefsEnableVulkanDrivers];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)eglDriversEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsEnableEGLDrivers];
}

- (void)setEglDriversEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsEnableEGLDrivers];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Dmabuf Support
- (BOOL)dmabufEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsEnableDmabuf];
}

- (void)setDmabufEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsEnableDmabuf];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// New unified display methods
- (BOOL)autoScale {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:kWawonaPrefsAutoScale]) {
    return [defaults boolForKey:kWawonaPrefsAutoScale];
  }
  // Migrate from legacy key
  if ([defaults objectForKey:kWawonaPrefsAutoRetinaScaling]) {
    BOOL value = [defaults boolForKey:kWawonaPrefsAutoRetinaScaling];
    [defaults setBool:value forKey:kWawonaPrefsAutoScale];
    return value;
  }
  return YES; // Default
}

- (void)setAutoScale:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsAutoScale];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)respectSafeArea {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsRespectSafeArea];
}

- (void)setRespectSafeArea:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsRespectSafeArea];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// New unified color management method
- (BOOL)colorOperations {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:kWawonaPrefsColorOperations]) {
    return [defaults boolForKey:kWawonaPrefsColorOperations];
  }
  // Migrate from legacy key
  if ([defaults objectForKey:kWawonaPrefsColorSyncSupport]) {
    BOOL value = [defaults boolForKey:kWawonaPrefsColorSyncSupport];
    [defaults setBool:value forKey:kWawonaPrefsColorOperations];
    return value;
  }
  return YES; // Default
}

- (void)setColorOperations:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsColorOperations];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// New unified input method
- (BOOL)swapCmdWithAlt {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:kWawonaPrefsSwapCmdWithAlt]) {
    return [defaults boolForKey:kWawonaPrefsSwapCmdWithAlt];
  }
  // Migrate from legacy key
  if ([defaults objectForKey:kWawonaPrefsSwapCmdAsCtrl]) {
    BOOL value = [defaults boolForKey:kWawonaPrefsSwapCmdAsCtrl];
    [defaults setBool:value forKey:kWawonaPrefsSwapCmdWithAlt];
    return value;
  }
  return YES; // Default on for macOS/iOS
}

- (void)setSwapCmdWithAlt:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsSwapCmdWithAlt];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Waypipe Configuration Methods
- (NSString *)waypipeDisplay {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeDisplay];
  return value ? value : @"wayland-0";
}

- (void)setWaypipeDisplay:(NSString *)display {
  [[NSUserDefaults standardUserDefaults] setObject:display
                                             forKey:kWawonaPrefsWaypipeDisplay];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeSocket {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeSocket];
  if (!value) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    NSString *tmpDir = NSTemporaryDirectory();
    value = [tmpDir stringByAppendingPathComponent:@"waypipe"];
#else
    value = [NSString stringWithFormat:@"/tmp/wawona-waypipe-%d.sock", getuid()];
#endif
  }
  return value;
}

- (void)setWaypipeSocket:(NSString *)socket {
  [[NSUserDefaults standardUserDefaults] setObject:socket
                                             forKey:kWawonaPrefsWaypipeSocket];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeCompress {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeCompress];
  return value ? value : @"lz4";
}

- (void)setWaypipeCompress:(NSString *)compress {
  [[NSUserDefaults standardUserDefaults] setObject:compress
                                             forKey:kWawonaPrefsWaypipeCompress];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeCompressLevel {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeCompressLevel];
  return value ? value : @"7";
}

- (void)setWaypipeCompressLevel:(NSString *)level {
  [[NSUserDefaults standardUserDefaults] setObject:level
                                             forKey:kWawonaPrefsWaypipeCompressLevel];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeThreads {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeThreads];
  return value ? value : @"0";
}

- (void)setWaypipeThreads:(NSString *)threads {
  [[NSUserDefaults standardUserDefaults] setObject:threads
                                             forKey:kWawonaPrefsWaypipeThreads];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeVideo {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeVideo];
  return value ? value : @"none";
}

- (void)setWaypipeVideo:(NSString *)video {
  [[NSUserDefaults standardUserDefaults] setObject:video
                                             forKey:kWawonaPrefsWaypipeVideo];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeVideoEncoding {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeVideoEncoding];
  return value ? value : @"hw";
}

- (void)setWaypipeVideoEncoding:(NSString *)encoding {
  [[NSUserDefaults standardUserDefaults] setObject:encoding
                                             forKey:kWawonaPrefsWaypipeVideoEncoding];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeVideoDecoding {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeVideoDecoding];
  return value ? value : @"hw";
}

- (void)setWaypipeVideoDecoding:(NSString *)decoding {
  [[NSUserDefaults standardUserDefaults] setObject:decoding
                                             forKey:kWawonaPrefsWaypipeVideoDecoding];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeVideoBpf {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeVideoBpf];
  return value ? value : @"";
}

- (void)setWaypipeVideoBpf:(NSString *)bpf {
  [[NSUserDefaults standardUserDefaults] setObject:bpf
                                             forKey:kWawonaPrefsWaypipeVideoBpf];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeSSHEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeSSHEnabled];
}

- (void)setWaypipeSSHEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeSSHEnabled];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeSSHHost {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeSSHHost];
  return value ? value : @"";
}

- (void)setWaypipeSSHHost:(NSString *)host {
  [[NSUserDefaults standardUserDefaults] setObject:host
                                             forKey:kWawonaPrefsWaypipeSSHHost];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeSSHUser {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeSSHUser];
  return value ? value : @"";
}

- (void)setWaypipeSSHUser:(NSString *)user {
  [[NSUserDefaults standardUserDefaults] setObject:user
                                             forKey:kWawonaPrefsWaypipeSSHUser];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeSSHBinary {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeSSHBinary];
  return value ? value : @"ssh";
}

- (void)setWaypipeSSHBinary:(NSString *)binary {
  [[NSUserDefaults standardUserDefaults] setObject:binary
                                             forKey:kWawonaPrefsWaypipeSSHBinary];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeRemoteCommand {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeRemoteCommand];
  return value ? value : @"";
}

- (void)setWaypipeRemoteCommand:(NSString *)command {
  [[NSUserDefaults standardUserDefaults] setObject:command
                                             forKey:kWawonaPrefsWaypipeRemoteCommand];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeCustomScript {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeCustomScript];
  return value ? value : @"";
}

- (void)setWaypipeCustomScript:(NSString *)script {
  [[NSUserDefaults standardUserDefaults] setObject:script
                                             forKey:kWawonaPrefsWaypipeCustomScript];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeDebug {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeDebug];
}

- (void)setWaypipeDebug:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeDebug];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeNoGpu {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeNoGpu];
}

- (void)setWaypipeNoGpu:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeNoGpu];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeOneshot {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeOneshot];
}

- (void)setWaypipeOneshot:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeOneshot];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeUnlinkSocket {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeUnlinkSocket];
}

- (void)setWaypipeUnlinkSocket:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeUnlinkSocket];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeLoginShell {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeLoginShell];
}

- (void)setWaypipeLoginShell:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeLoginShell];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeVsock {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeVsock];
}

- (void)setWaypipeVsock:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeVsock];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)waypipeXwls {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeXwls];
}

- (void)setWaypipeXwls:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsWaypipeXwls];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeTitlePrefix {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeTitlePrefix];
  return value ? value : @"";
}

- (void)setWaypipeTitlePrefix:(NSString *)prefix {
  [[NSUserDefaults standardUserDefaults] setObject:prefix
                                             forKey:kWawonaPrefsWaypipeTitlePrefix];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeSecCtx {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeSecCtx];
  return value ? value : @"";
}

- (void)setWaypipeSecCtx:(NSString *)secCtx {
  [[NSUserDefaults standardUserDefaults] setObject:secCtx
                                             forKey:kWawonaPrefsWaypipeSecCtx];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
