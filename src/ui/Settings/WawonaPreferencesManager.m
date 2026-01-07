#import "WawonaPreferencesManager.h"
#import <Security/Security.h>

// Preferences keys
NSString *const kWawonaPrefsUniversalClipboard = @"UniversalClipboard";
NSString *const kWawonaPrefsForceServerSideDecorations =
    @"ForceServerSideDecorations";
NSString *const kWawonaPrefsAutoRetinaScaling = @"AutoRetinaScaling"; // Legacy
NSString *const kWawonaPrefsAutoScale = @"AutoScale"; // New unified key
NSString *const kWawonaPrefsColorSyncSupport = @"ColorSyncSupport"; // Legacy
NSString *const kWawonaPrefsColorOperations =
    @"ColorOperations"; // New unified key
NSString *const kWawonaPrefsNestedCompositorsSupport =
    @"NestedCompositorsSupport";
NSString *const kWawonaPrefsUseMetal4ForNested =
    @"UseMetal4ForNested"; // Deprecated
NSString *const kWawonaPrefsRenderMacOSPointer = @"RenderMacOSPointer";
NSString *const kWawonaPrefsMultipleClients = @"MultipleClients";
NSString *const kWawonaPrefsEnableLauncher = @"EnableLauncher";
NSString *const kWawonaPrefsSwapCmdAsCtrl = @"SwapCmdAsCtrl"; // Legacy
NSString *const kWawonaPrefsSwapCmdWithAlt =
    @"SwapCmdWithAlt"; // New unified key
NSString *const kWawonaPrefsTouchInputType = @"TouchInputType";
NSString *const kWawonaPrefsWaypipeRSSupport =
    @"WaypipeRSSupport"; // Deprecated - always enabled
NSString *const kWawonaPrefsEnableTCPListener =
    @"EnableTCPListener"; // Deprecated - always enabled
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
NSString *const kWawonaPrefsWaypipeSSHAuthMethod = @"WaypipeSSHAuthMethod";
NSString *const kWawonaPrefsWaypipeSSHKeyPath = @"WaypipeSSHKeyPath";
NSString *const kWawonaPrefsWaypipeSSHKeyPassphrase =
    @"WaypipeSSHKeyPassphrase";
NSString *const kWawonaPrefsWaypipeSSHPassword = @"WaypipeSSHPassword";
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
// SSH configuration keys (separate from Waypipe)
NSString *const kWawonaPrefsSSHHost = @"SSHHost";
NSString *const kWawonaPrefsSSHUser = @"SSHUser";
NSString *const kWawonaPrefsSSHAuthMethod = @"SSHAuthMethod";
NSString *const kWawonaPrefsSSHPassword = @"SSHPassword";
NSString *const kWawonaPrefsSSHKeyPath = @"SSHKeyPath";
NSString *const kWawonaPrefsSSHKeyPassphrase = @"SSHKeyPassphrase";
NSString *const kWawonaPrefsWaypipeUseSSHConfig = @"WaypipeUseSSHConfig";
NSString *const kWawonaForceSSDChangedNotification =
    @"WawonaForceSSDChangedNotification";

static NSString *WawonaPreferredSharedRuntimeDir(void) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSURL *groupURL = [[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:
          @"group.com.aspauldingcode.Wawona"];
  if (groupURL) {
    NSString *candidate = [groupURL.path stringByAppendingPathComponent:@"w"];
    if (candidate.length > 0 && candidate.length <= 90) {
      return candidate;
    }
  }
  return @"/tmp/wawona-ios";
#else
  NSURL *groupURL = [[NSFileManager defaultManager]
      containerURLForSecurityApplicationGroupIdentifier:
          @"group.com.aspauldingcode.Wawona"];
  if (groupURL) {
    return [groupURL.path stringByAppendingPathComponent:@"w"];
  }
  NSString *tmpDir = NSTemporaryDirectory();
  return tmpDir.length > 0 ? tmpDir : @"/tmp";
#endif
}

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
    [defaults setBool:NO forKey:kWawonaPrefsForceServerSideDecorations];
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
    [defaults
        setBool:NO
         forKey:kWawonaPrefsRenderMacOSPointer]; // Off by default on macOS
  }
  if (![defaults objectForKey:kWawonaPrefsMultipleClients]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [defaults
        setBool:NO
         forKey:kWawonaPrefsMultipleClients]; // Disabled on iOS/Android
                                              // (matching Android default)
#else
    [defaults setBool:YES
               forKey:kWawonaPrefsMultipleClients]; // Enabled on macOS
#endif
  }
  if (![defaults objectForKey:kWawonaPrefsEnableLauncher]) {
    [defaults setBool:NO forKey:kWawonaPrefsEnableLauncher];
  }
  if (![defaults objectForKey:kWawonaPrefsSwapCmdAsCtrl]) {
    [defaults setBool:NO forKey:kWawonaPrefsSwapCmdAsCtrl];
  }
  // Migration: Convert old keys to new unified keys
  if ([defaults objectForKey:kWawonaPrefsAutoRetinaScaling] &&
      ![defaults objectForKey:kWawonaPrefsAutoScale]) {
    BOOL oldValue = [defaults boolForKey:kWawonaPrefsAutoRetinaScaling];
    [defaults setBool:oldValue forKey:kWawonaPrefsAutoScale];
  }
  if (![defaults objectForKey:kWawonaPrefsAutoScale]) {
    [defaults setBool:YES
               forKey:kWawonaPrefsAutoScale]; // Default on for all platforms
  }
  if ([defaults objectForKey:kWawonaPrefsColorSyncSupport] &&
      ![defaults objectForKey:kWawonaPrefsColorOperations]) {
    BOOL oldValue = [defaults boolForKey:kWawonaPrefsColorSyncSupport];
    [defaults setBool:oldValue forKey:kWawonaPrefsColorOperations];
  }
  if (![defaults objectForKey:kWawonaPrefsColorOperations]) {
    [defaults setBool:YES
               forKey:kWawonaPrefsColorOperations]; // Default enabled
  }
  if ([defaults objectForKey:kWawonaPrefsSwapCmdAsCtrl] &&
      ![defaults objectForKey:kWawonaPrefsSwapCmdWithAlt]) {
    BOOL oldValue = [defaults boolForKey:kWawonaPrefsSwapCmdAsCtrl];
    [defaults setBool:oldValue forKey:kWawonaPrefsSwapCmdWithAlt];
  }
  if (![defaults objectForKey:kWawonaPrefsSwapCmdWithAlt]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [defaults setBool:YES
               forKey:kWawonaPrefsSwapCmdWithAlt]; // Default on for macOS/iOS
#else
    [defaults setBool:YES
               forKey:kWawonaPrefsSwapCmdWithAlt]; // Default on for macOS/iOS
#endif
  }
  if (![defaults objectForKey:kWawonaPrefsRespectSafeArea]) {
    [defaults setBool:YES forKey:kWawonaPrefsRespectSafeArea]; // Default on
  }
  // Waypipe configuration defaults
  if (![defaults objectForKey:kWawonaPrefsWaypipeDisplay]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [defaults setObject:@"wayland-0" forKey:kWawonaPrefsWaypipeDisplay];
#else
    [defaults setObject:@"wayland-0" forKey:kWawonaPrefsWaypipeDisplay];
#endif
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSocket]) {
    NSString *runtimeDir = WawonaPreferredSharedRuntimeDir();
    NSString *display = [defaults stringForKey:kWawonaPrefsWaypipeDisplay];
    if (display.length == 0) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      display = @"wayland-0";
#else
      display = @"wayland-0";
#endif
    }
    NSString *defaultSocket =
        [runtimeDir stringByAppendingPathComponent:display];
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
  // SSH is always enabled on iOS/macOS, so set it to YES by default
  if (![defaults objectForKey:kWawonaPrefsWaypipeSSHEnabled]) {
    [defaults setBool:YES forKey:kWawonaPrefsWaypipeSSHEnabled];
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
  if (![defaults objectForKey:kWawonaPrefsWaypipeSSHAuthMethod]) {
    [defaults
        setInteger:0
            forKey:kWawonaPrefsWaypipeSSHAuthMethod]; // Default to password
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSSHKeyPath]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeSSHKeyPath];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeRemoteCommand]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeRemoteCommand];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeCustomScript]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeCustomScript];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeDebug]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [defaults setBool:YES forKey:kWawonaPrefsWaypipeDebug];
#else
    [defaults setBool:NO forKey:kWawonaPrefsWaypipeDebug];
#endif
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
    [defaults setBool:NO
               forKey:kWawonaPrefsWaypipeXwls]; // Disabled/unavailable
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeTitlePrefix]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeTitlePrefix];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeSecCtx]) {
    [defaults setObject:@"" forKey:kWawonaPrefsWaypipeSecCtx];
  }
  if (![defaults objectForKey:kWawonaPrefsWaypipeUseSSHConfig]) {
    [defaults
        setBool:YES
         forKey:kWawonaPrefsWaypipeUseSSHConfig]; // Default to using SSH config
                                                  // from OpenSSH section
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
    NSString *defaultDir = WawonaPreferredSharedRuntimeDir();
    [defaults setObject:defaultDir forKey:kWawonaPrefsWaylandSocketDir];
  }
  if (![defaults objectForKey:kWawonaPrefsWaylandDisplayNumber]) {
    [defaults setInteger:0 forKey:kWawonaPrefsWaylandDisplayNumber];
  }
  if (![defaults objectForKey:kWawonaPrefsEnableVulkanDrivers]) {
    [defaults setBool:YES forKey:kWawonaPrefsEnableVulkanDrivers];
  }
  if (![defaults objectForKey:kWawonaPrefsEnableEGLDrivers]) {
    [defaults setBool:NO forKey:kWawonaPrefsEnableEGLDrivers];
  }
  if (![defaults objectForKey:kWawonaPrefsEnableDmabuf]) {
    [defaults setBool:YES forKey:kWawonaPrefsEnableDmabuf];
  }
  if (![defaults objectForKey:kWawonaPrefsTouchInputType]) {
    [defaults setObject:@"Multi-Touch" forKey:kWawonaPrefsTouchInputType];
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

  // Post notification for hot-reload
  [[NSNotificationCenter defaultCenter]
      postNotificationName:kWawonaForceSSDChangedNotification
                    object:self];
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
- (BOOL)enableLauncher {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsEnableLauncher];
}

- (void)setEnableLauncher:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWawonaPrefsEnableLauncher];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

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
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *preferred = WawonaPreferredSharedRuntimeDir();
  if (preferred.length > 0) {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
        stringForKey:kWawonaPrefsWaylandSocketDir];
    if (![stored isEqualToString:preferred]) {
      [[NSUserDefaults standardUserDefaults]
          setObject:preferred
             forKey:kWawonaPrefsWaylandSocketDir];
      [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return preferred;
  }
#endif

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

- (NSString *)touchInputType {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsTouchInputType];
  return value ? value : @"Multi-Touch";
}

- (void)setTouchInputType:(NSString *)type {
  if (type) {
    [[NSUserDefaults standardUserDefaults]
        setObject:type
           forKey:kWawonaPrefsTouchInputType];
  } else {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kWawonaPrefsTouchInputType];
  }
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Waypipe Configuration Methods
- (NSString *)waypipeDisplay {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeDisplay];
  if ([value isEqualToString:@"w0"] || [value isEqualToString:@"w-0"]) {
    value = @"wayland-0";
    [[NSUserDefaults standardUserDefaults]
        setObject:value
           forKey:kWawonaPrefsWaypipeDisplay];
    [[NSUserDefaults standardUserDefaults] synchronize];
  }
  return value.length > 0 ? value : @"wayland-0";
#else
  NSInteger displayNumber = [self waylandDisplayNumber];
  return [NSString stringWithFormat:@"wayland-%ld", (long)displayNumber];
#endif
}

- (void)setWaypipeDisplay:(NSString *)display {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if ([display isEqualToString:@"w0"] || [display isEqualToString:@"w-0"]) {
    display = @"wayland-0";
  }
  if (display.length > 0) {
    [[NSUserDefaults standardUserDefaults]
        setObject:display
           forKey:kWawonaPrefsWaypipeDisplay];
  } else {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kWawonaPrefsWaypipeDisplay];
  }
  [[NSUserDefaults standardUserDefaults] synchronize];
#else
  if (display && display.length > 0) {
    NSInteger number = 0;
    if ([display hasPrefix:@"wayland-"]) {
      NSString *numberStr = [display substringFromIndex:8];
      number = [numberStr integerValue];
    } else {
      number = [display integerValue];
    }
    [self setWaylandDisplayNumber:number];
  }
#endif
}

- (NSString *)waypipeSocket {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *runtimeDir = WawonaPreferredSharedRuntimeDir();
  if (runtimeDir.length > 0) {
    NSString *display = [self waypipeDisplay];
    if (display.length == 0) {
      display = @"wayland-0";
    }
    NSString *preferred = [runtimeDir stringByAppendingPathComponent:display];
    NSString *stored = [[NSUserDefaults standardUserDefaults]
        stringForKey:kWawonaPrefsWaypipeSocket];
    if (![stored isEqualToString:preferred]) {
      [[NSUserDefaults standardUserDefaults]
          setObject:preferred
             forKey:kWawonaPrefsWaypipeSocket];
      [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return preferred;
  }
#endif

  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeSocket];
  if (!value) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    NSString *tmpDir = NSTemporaryDirectory();
    value = [tmpDir stringByAppendingPathComponent:@"waypipe"];
#else
    value =
        [NSString stringWithFormat:@"/tmp/wawona-waypipe-%d.sock", getuid()];
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
  [[NSUserDefaults standardUserDefaults]
      setObject:level
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
  [[NSUserDefaults standardUserDefaults]
      setObject:encoding
         forKey:kWawonaPrefsWaypipeVideoEncoding];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeVideoDecoding {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeVideoDecoding];
  return value ? value : @"hw";
}

- (void)setWaypipeVideoDecoding:(NSString *)decoding {
  [[NSUserDefaults standardUserDefaults]
      setObject:decoding
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
  // SSH is always enabled on iOS/macOS
  return YES;
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
  [[NSUserDefaults standardUserDefaults]
      setObject:binary
         forKey:kWawonaPrefsWaypipeSSHBinary];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)waypipeSSHAuthMethod {
  NSInteger method = [[NSUserDefaults standardUserDefaults]
      integerForKey:kWawonaPrefsWaypipeSSHAuthMethod];
  return method; // 0 = password (default), 1 = public key
}

- (void)setWaypipeSSHAuthMethod:(NSInteger)method {
  [[NSUserDefaults standardUserDefaults]
      setInteger:method
          forKey:kWawonaPrefsWaypipeSSHAuthMethod];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeSSHKeyPath {
  return [[NSUserDefaults standardUserDefaults]
             stringForKey:kWawonaPrefsWaypipeSSHKeyPath]
             ?: @"";
}

- (void)setWaypipeSSHKeyPath:(NSString *)keyPath {
  [[NSUserDefaults standardUserDefaults]
      setObject:keyPath
         forKey:kWawonaPrefsWaypipeSSHKeyPath];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeSSHKeyPassphrase {
  // Store in Keychain for security
  NSString *service = @"com.aspauldingcode.wawona.ssh";
  NSString *account = @"ssh_key_passphrase";

  NSDictionary *query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : service,
    (__bridge id)kSecAttrAccount : account,
    (__bridge id)kSecReturnData : @YES
  };

  CFTypeRef result = NULL;
  OSStatus status =
      SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

  if (status == errSecSuccess && result) {
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  }

  return @"";
}

- (void)setWaypipeSSHKeyPassphrase:(NSString *)passphrase {
  // Store in Keychain for security
  NSString *service = @"com.aspauldingcode.wawona.ssh";
  NSString *account = @"ssh_key_passphrase";

  // Delete existing item
  NSDictionary *deleteQuery = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : service,
    (__bridge id)kSecAttrAccount : account
  };
  SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

  if (passphrase && passphrase.length > 0) {
    NSData *data = [passphrase dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *addQuery = @{
      (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService : service,
      (__bridge id)kSecAttrAccount : account,
      (__bridge id)kSecValueData : data
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
  }
}

- (NSString *)waypipeSSHPassword {
  // Try Keychain first (more secure)
  NSString *service = @"com.aspauldingcode.wawona.ssh";
  NSString *account = @"ssh_password";

  NSDictionary *query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : service,
    (__bridge id)kSecAttrAccount : account,
    (__bridge id)kSecReturnData : @YES
  };

  CFTypeRef result = NULL;
  OSStatus status =
      SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

  if (status == errSecSuccess && result) {
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  }

  // Fallback to NSUserDefaults if Keychain fails (e.g., missing entitlements in
  // Simulator) Also check if we just got no result but have a stored preference
  if (status != errSecSuccess) {
    NSString *fallback = [[NSUserDefaults standardUserDefaults]
        stringForKey:kWawonaPrefsWaypipeSSHPassword];
    return fallback ?: @"";
  }

  return @"";
}

- (void)setWaypipeSSHPassword:(NSString *)password {
#if TARGET_OS_SIMULATOR
  // Save to NSUserDefaults in Simulator where Keychain is restricted
  if (password && password.length > 0) {
    [[NSUserDefaults standardUserDefaults]
        setObject:password
           forKey:kWawonaPrefsWaypipeSSHPassword];
  } else {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kWawonaPrefsWaypipeSSHPassword];
  }
  [[NSUserDefaults standardUserDefaults] synchronize];
#endif

  // Try Keychain (more secure, works on real devices)
  NSString *service = @"com.aspauldingcode.wawona.ssh";
  NSString *account = @"ssh_password";

  // Delete existing item
  NSDictionary *deleteQuery = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : service,
    (__bridge id)kSecAttrAccount : account
  };
  OSStatus deleteStatus = SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

  if (password && password.length > 0) {
    NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *addQuery = @{
      (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService : service,
      (__bridge id)kSecAttrAccount : account,
      (__bridge id)kSecValueData : data
    };
    OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    if (addStatus != errSecSuccess) {
      NSLog(@"[WawonaPreferences] Keychain add failed: %d", (int)addStatus);
    }
  }
}

- (NSString *)waypipeRemoteCommand {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeRemoteCommand];
  return value ? value : @"";
}

- (void)setWaypipeRemoteCommand:(NSString *)command {
  [[NSUserDefaults standardUserDefaults]
      setObject:command
         forKey:kWawonaPrefsWaypipeRemoteCommand];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)waypipeCustomScript {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsWaypipeCustomScript];
  return value ? value : @"";
}

- (void)setWaypipeCustomScript:(NSString *)script {
  [[NSUserDefaults standardUserDefaults]
      setObject:script
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
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
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
  [[NSUserDefaults standardUserDefaults]
      setObject:prefix
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

- (BOOL)waypipeUseSSHConfig {
  // Default to YES if not set (use SSH config from OpenSSH section by default)
  if (![[NSUserDefaults standardUserDefaults]
          objectForKey:kWawonaPrefsWaypipeUseSSHConfig]) {
    return YES;
  }
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWawonaPrefsWaypipeUseSSHConfig];
}

- (void)setWaypipeUseSSHConfig:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWawonaPrefsWaypipeUseSSHConfig];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// SSH Configuration (separate from Waypipe)
- (NSString *)sshHost {
  NSString *value =
      [[NSUserDefaults standardUserDefaults] stringForKey:kWawonaPrefsSSHHost];
  return value ? value : @"";
}

- (void)setSshHost:(NSString *)host {
  [[NSUserDefaults standardUserDefaults] setObject:host
                                            forKey:kWawonaPrefsSSHHost];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)sshUser {
  NSString *value =
      [[NSUserDefaults standardUserDefaults] stringForKey:kWawonaPrefsSSHUser];
  return value ? value : @"";
}

- (void)setSshUser:(NSString *)user {
  [[NSUserDefaults standardUserDefaults] setObject:user
                                            forKey:kWawonaPrefsSSHUser];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)sshAuthMethod {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:kWawonaPrefsSSHAuthMethod];
}

- (void)setSshAuthMethod:(NSInteger)method {
  [[NSUserDefaults standardUserDefaults] setInteger:method
                                             forKey:kWawonaPrefsSSHAuthMethod];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

// Helper methods for secure storage (keychain)
- (NSString *)getSecureValueForKey:(NSString *)key {
  NSString *service = @"com.aspauldingcode.wawona.ssh";
  NSString *account = key;

  NSDictionary *query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : service,
    (__bridge id)kSecAttrAccount : account,
    (__bridge id)kSecReturnData : @YES
  };

  CFTypeRef result = NULL;
  OSStatus status =
      SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

  if (status == errSecSuccess && result) {
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  }

  // Fallback to NSUserDefaults if Keychain fails
  NSString *fallback = [[NSUserDefaults standardUserDefaults] stringForKey:key];
  return fallback ?: @"";
}

- (void)setSecureValue:(NSString *)value forKey:(NSString *)key {
#if TARGET_OS_SIMULATOR
  // Save to NSUserDefaults in Simulator where Keychain is restricted
  if (value && value.length > 0) {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
  } else {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
  }
  [[NSUserDefaults standardUserDefaults] synchronize];
#endif

  // Try Keychain (more secure, works on real devices)
  NSString *service = @"com.aspauldingcode.wawona.ssh";
  NSString *account = key;

  // Delete existing item
  NSDictionary *deleteQuery = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : service,
    (__bridge id)kSecAttrAccount : account
  };
  SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

  if (value && value.length > 0) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *addQuery = @{
      (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService : service,
      (__bridge id)kSecAttrAccount : account,
      (__bridge id)kSecValueData : data
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
  }
}

- (NSString *)sshPassword {
  // Use keychain for secure storage
  return [self getSecureValueForKey:kWawonaPrefsSSHPassword];
}

- (void)setSshPassword:(NSString *)password {
  [self setSecureValue:password forKey:kWawonaPrefsSSHPassword];
}

- (NSString *)sshKeyPath {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWawonaPrefsSSHKeyPath];
  return value ? value : @"";
}

- (void)setSshKeyPath:(NSString *)keyPath {
  [[NSUserDefaults standardUserDefaults] setObject:keyPath
                                            forKey:kWawonaPrefsSSHKeyPath];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)sshKeyPassphrase {
  // Use keychain for secure storage
  return [self getSecureValueForKey:kWawonaPrefsSSHKeyPassphrase];
}

- (void)setSshKeyPassphrase:(NSString *)passphrase {
  [self setSecureValue:passphrase forKey:kWawonaPrefsSSHKeyPassphrase];
}

@end
