#import "WawonaPreferences.h"
#import "WawonaPreferencesManager.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <string.h>
#import <errno.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

// MARK: - Data Models

typedef NS_ENUM(NSInteger, WawonaSettingType) {
  WawonaSettingTypeSwitch,
  WawonaSettingTypeText,
  WawonaSettingTypeNumber,
  WawonaSettingTypePopup,
  WawonaSettingTypeButton,
  WawonaSettingTypeInfo
};

@interface WawonaSettingItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *desc;
@property(nonatomic, assign) WawonaSettingType type;
@property(nonatomic, strong) id defaultValue;
@property(nonatomic, strong) NSArray *options;
@property(nonatomic, copy) void (^actionBlock)(void);
+ (instancetype)itemWithTitle:(NSString *)title
                          key:(NSString *)key
                         type:(WawonaSettingType)type
                      default:(id)def
                         desc:(NSString *)desc;
@end

@implementation WawonaSettingItem
+ (instancetype)itemWithTitle:(NSString *)title
                          key:(NSString *)key
                         type:(WawonaSettingType)type
                      default:(id)def
                         desc:(NSString *)desc {
  WawonaSettingItem *item = [[WawonaSettingItem alloc] init];
  item.title = title;
  item.key = key;
  item.type = type;
  item.defaultValue = def;
  item.desc = desc;
  return item;
}
@end

@interface WawonaPreferencesSection : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *icon;
#if TARGET_OS_IPHONE
@property(nonatomic, strong) UIColor *iconColor;
#else
@property(nonatomic, strong) NSColor *iconColor;
#endif
@property(nonatomic, strong) NSArray<WawonaSettingItem *> *items;
@end

@implementation WawonaPreferencesSection
@end

// MARK: - Helper Class Interfaces

#if !TARGET_OS_IPHONE
@interface WawonaPreferencesSidebar
    : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property(nonatomic, weak) WawonaPreferences *parent;
@property(nonatomic, strong) NSOutlineView *outlineView;
@end

@interface WawonaPreferencesContent
    : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) WawonaPreferencesSection *section;
@property(nonatomic, strong) NSTableView *tableView;
@end
#endif

// MARK: - Main Class Extension

@interface WawonaPreferences ()
#if !TARGET_OS_IPHONE
<NSToolbarDelegate>
#endif
@property(nonatomic, strong) NSArray<WawonaPreferencesSection *> *sections;
#if !TARGET_OS_IPHONE
@property(nonatomic, strong) NSSplitViewController *splitVC;
@property(nonatomic, strong) WawonaPreferencesSidebar *sidebar;
@property(nonatomic, strong) WawonaPreferencesContent *content;
@property(nonatomic, strong) NSWindowController *winController;
#endif
- (NSArray<WawonaPreferencesSection *> *)buildSections;
- (void)runWaypipe;
- (void)handleSSHPasswordPrompt:(NSString *)prompt;
- (void)handleSSHError:(NSString *)error;
#if !TARGET_OS_IPHONE
- (void)showSection:(NSInteger)idx;
#endif
@end

// MARK: - Main Implementation

@implementation WawonaPreferences

+ (instancetype)sharedPreferences {
  static WawonaPreferences *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

#if !TARGET_OS_IPHONE
- (instancetype)init {
  if (self = [super init]) {
    self.sections = [self buildSections];
  }
  return self;
}
#else
- (instancetype)init {
  if (self = [super initWithStyle:UITableViewStyleInsetGrouped]) {
    self.title = @"Settings";
    self.sections = [self buildSections];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(dismissSelf)];
  }
  return self;
}
#endif

- (NSString *)localIPAddress {
  struct ifaddrs *interfaces = NULL;
  struct ifaddrs *temp_addr = NULL;
  NSString *address = @"Unavailable";
  if (getifaddrs(&interfaces) == 0) {
    temp_addr = interfaces;
    while (temp_addr != NULL) {
      if (temp_addr->ifa_addr->sa_family == AF_INET) {
        NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
        if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
          address =
              [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)
                                                            temp_addr->ifa_addr)
                                                           ->sin_addr)];
          break;
        }
      }
      temp_addr = temp_addr->ifa_next;
    }
  }
  freeifaddrs(interfaces);
  return address;
}

- (NSArray<WawonaPreferencesSection *> *)buildSections {
  NSMutableArray *sects = [NSMutableArray array];

  // DISPLAY
  WawonaPreferencesSection *display = [[WawonaPreferencesSection alloc] init];
  display.title = @"Display";
  display.icon = @"display";
#if TARGET_OS_IPHONE
  display.iconColor = [UIColor systemBlueColor];
#else
  display.iconColor = [NSColor systemBlueColor];
#endif
  display.items = @[
    [WawonaSettingItem itemWithTitle:@"Force Server-Side Decorations"
                                 key:@"ForceServerSideDecorations"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Forces macOS-style window decorations."],
    [WawonaSettingItem itemWithTitle:@"Show macOS Cursor"
                                 key:@"RenderMacOSPointer"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Toggles macOS cursor visibility."],
    [WawonaSettingItem itemWithTitle:@"Auto Scale"
                                 key:@"AutoScale"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Matches macOS UI Scaling."],
    [WawonaSettingItem itemWithTitle:@"Respect Safe Area"
                                 key:@"RespectSafeArea"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Avoids notch areas."]
  ];
  [sects addObject:display];

  // INPUT
  WawonaPreferencesSection *input = [[WawonaPreferencesSection alloc] init];
  input.title = @"Input";
  input.icon = @"keyboard";
#if TARGET_OS_IPHONE
  input.iconColor = [UIColor systemPurpleColor];
#else
  input.iconColor = [NSColor systemPurpleColor];
#endif
  input.items = @[
    [WawonaSettingItem itemWithTitle:@"Swap CMD with ALT"
                                 key:@"SwapCmdWithAlt"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Swaps Command and Alt keys."],
    [WawonaSettingItem itemWithTitle:@"Universal Clipboard"
                                 key:@"UniversalClipboardEnabled"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Syncs clipboard with macOS."]
  ];
  [sects addObject:input];

  // GRAPHICS
  WawonaPreferencesSection *graphics = [[WawonaPreferencesSection alloc] init];
  graphics.title = @"Graphics";
  graphics.icon = @"cpu";
#if TARGET_OS_IPHONE
  graphics.iconColor = [UIColor systemRedColor];
#else
  graphics.iconColor = [NSColor systemRedColor];
#endif
  graphics.items = @[
    [WawonaSettingItem itemWithTitle:@"Enable Vulkan Drivers"
                                 key:@"VulkanDriversEnabled"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Experimental Vulkan support."],
    [WawonaSettingItem itemWithTitle:@"Enable EGL Drivers"
                                 key:@"EglDriversEnabled"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"EGL hardware acceleration."],
    [WawonaSettingItem itemWithTitle:@"Enable DMABUF"
                                 key:@"DmabufEnabled"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Zero-copy texture sharing."]
  ];
  [sects addObject:graphics];

  // NETWORK
  WawonaPreferencesSection *network = [[WawonaPreferencesSection alloc] init];
  network.title = @"Network";
  network.icon = @"network";
#if TARGET_OS_IPHONE
  network.iconColor = [UIColor systemOrangeColor];
#else
  network.iconColor = [NSColor systemOrangeColor];
#endif
  network.items = @[
    [WawonaSettingItem itemWithTitle:@"TCP Port"
                                 key:@"TCPListenerPort"
                                type:WawonaSettingTypeNumber
                             default:@6000
                                desc:@"Port for TCP listener."],
    [WawonaSettingItem itemWithTitle:@"Socket Directory"
                                 key:@"WaylandSocketDir"
                                type:WawonaSettingTypeInfo
                             default:@"/tmp"
                                desc:@"Directory for sockets (tap to copy)."],
    [WawonaSettingItem itemWithTitle:@"Display Number"
                                 key:@"WaylandDisplayNumber"
                                type:WawonaSettingTypeNumber
                             default:@0
                                desc:@"Display number (e.g., 0)."]
  ];
  [sects addObject:network];

  // ADVANCED
  WawonaPreferencesSection *advanced = [[WawonaPreferencesSection alloc] init];
  advanced.title = @"Advanced";
  advanced.icon = @"gearshape.2";
#if TARGET_OS_IPHONE
  advanced.iconColor = [UIColor systemGrayColor];
#else
  advanced.iconColor = [NSColor systemGrayColor];
#endif
  advanced.items = @[
    [WawonaSettingItem itemWithTitle:@"Color Operations"
                                 key:@"ColorOperations"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Color profiles and HDR."],
    [WawonaSettingItem itemWithTitle:@"Nested Compositors"
                                 key:@"NestedCompositorsSupportEnabled"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Support for nested compositors."],
    [WawonaSettingItem itemWithTitle:@"Multiple Clients"
                                 key:@"MultipleClientsEnabled"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Allow multiple clients."]
  ];
  [sects addObject:advanced];

  // WAYPIPE
  WawonaPreferencesSection *waypipe = [[WawonaPreferencesSection alloc] init];
  waypipe.title = @"Waypipe";
  waypipe.icon = @"arrow.triangle.2.circlepath";
#if TARGET_OS_IPHONE
  waypipe.iconColor = [UIColor systemGreenColor];
#else
  waypipe.iconColor = [NSColor systemGreenColor];
#endif

  WawonaSettingItem *runBtn = [WawonaSettingItem
      itemWithTitle:@"Run Waypipe"
                key:@"WaypipeRun"
               type:WawonaSettingTypeButton
            default:nil
               desc:@"Launch waypipe with current settings."];
  __weak typeof(self) weakSelf = self;
  runBtn.actionBlock = ^{
    [weakSelf runWaypipe];
  };

  WawonaSettingItem *ipInfo =
      [WawonaSettingItem itemWithTitle:@"Local IP"
                                   key:nil
                                  type:WawonaSettingTypeInfo
                               default:[self localIPAddress]
                                  desc:nil];

  WawonaSettingItem *compressItem =
      [WawonaSettingItem itemWithTitle:@"Compression"
                                   key:@"WaypipeCompress"
                                  type:WawonaSettingTypePopup
                               default:@"lz4"
                                  desc:@"Compression method."];
  compressItem.options = @[ @"none", @"lz4", @"zstd" ];

  WawonaSettingItem *videoItem =
      [WawonaSettingItem itemWithTitle:@"Video Codec"
                                   key:@"WaypipeVideo"
                                  type:WawonaSettingTypePopup
                               default:@"none"
                                  desc:@"Lossy video codec."];
  videoItem.options = @[ @"none", @"h264", @"vp9", @"av1" ];

  WawonaSettingItem *vEnc =
      [WawonaSettingItem itemWithTitle:@"Encoding"
                                   key:@"WaypipeVideoEncoding"
                                  type:WawonaSettingTypePopup
                               default:@"hw"
                                  desc:@"Hardware vs Software."];
  vEnc.options = @[ @"hw", @"sw", @"hwenc", @"swenc" ];

  WawonaSettingItem *vDec =
      [WawonaSettingItem itemWithTitle:@"Decoding"
                                   key:@"WaypipeVideoDecoding"
                                  type:WawonaSettingTypePopup
                               default:@"hw"
                                  desc:@"Hardware vs Software."];
  vDec.options = @[ @"hw", @"sw", @"hwdec", @"swdec" ];

  waypipe.items = @[
    ipInfo,
    [WawonaSettingItem itemWithTitle:@"Display"
                                 key:@"WaypipeDisplay"
                                type:WawonaSettingTypeText
                             default:@"wayland-0"
                                desc:@"Socket name."],
    compressItem,
    [WawonaSettingItem itemWithTitle:@"Comp. Level"
                                 key:@"WaypipeCompressLevel"
                                type:WawonaSettingTypeNumber
                             default:@7
                                desc:@"Zstd level (1-22)."],
    [WawonaSettingItem itemWithTitle:@"Threads"
                                 key:@"WaypipeThreads"
                                type:WawonaSettingTypeNumber
                             default:@0
                                desc:@"0 = auto."],
    videoItem,
    vEnc,
    vDec,
    [WawonaSettingItem itemWithTitle:@"Bits Per Frame"
                                 key:@"WaypipeVideoBpf"
                                type:WawonaSettingTypeNumber
                             default:@""
                                desc:@"Target bit rate."],
    [WawonaSettingItem itemWithTitle:@"Enable SSH"
                                 key:@"WaypipeSSHEnabled"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Use SSH."],
    [WawonaSettingItem itemWithTitle:@"SSH Host"
                                 key:@"WaypipeSSHHost"
                                type:WawonaSettingTypeText
                             default:@""
                                desc:@"Remote host."],
    [WawonaSettingItem itemWithTitle:@"SSH User"
                                 key:@"WaypipeSSHUser"
                                type:WawonaSettingTypeText
                             default:@""
                                desc:@"SSH Username."],
    [WawonaSettingItem itemWithTitle:@"Remote Command"
                                 key:@"WaypipeRemoteCommand"
                                type:WawonaSettingTypeText
                             default:@""
                                desc:@"Command to run remotely."],
    [WawonaSettingItem itemWithTitle:@"Debug Mode"
                                 key:@"WaypipeDebug"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Print debug logs."],
    [WawonaSettingItem itemWithTitle:@"Disable GPU"
                                 key:@"WaypipeNoGpu"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Block GPU protocols."],
    [WawonaSettingItem itemWithTitle:@"One-shot"
                                 key:@"WaypipeOneshot"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Exit when client disconnects."],
    [WawonaSettingItem itemWithTitle:@"Unlink Socket"
                                 key:@"WaypipeUnlinkSocket"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Unlink socket on exit."],
    [WawonaSettingItem itemWithTitle:@"Login Shell"
                                 key:@"WaypipeLoginShell"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Run in login shell."],
    [WawonaSettingItem itemWithTitle:@"VSock"
                                 key:@"WaypipeVsock"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Use VSock."],
    [WawonaSettingItem itemWithTitle:@"XWayland"
                                 key:@"WaypipeXwls"
                                type:WawonaSettingTypeSwitch
                             default:@NO
                                desc:@"Enable XWayland support."],
    [WawonaSettingItem itemWithTitle:@"Title Prefix"
                                 key:@"WaypipeTitlePrefix"
                                type:WawonaSettingTypeText
                             default:@""
                                desc:@"Prefix for titles."],
    [WawonaSettingItem itemWithTitle:@"Sec Context"
                                 key:@"WaypipeSecCtx"
                                type:WawonaSettingTypeText
                             default:@""
                                desc:@"SELinux context."],
    runBtn
  ];
  [sects addObject:waypipe];

  return sects;
}

- (NSString *)findWaypipeBinary {
  // Check common locations for Waypipe binary
  NSMutableArray *possiblePaths = [NSMutableArray array];
  
  // Helper function to safely add path if not nil
  void (^addPathIfNotNil)(NSString *) = ^(NSString *path) {
    if (path && path.length > 0) {
      [possiblePaths addObject:path];
    }
  };
  
  // In app bundle (most common for iOS)
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
  NSString *executablePath = [[NSBundle mainBundle] executablePath];
  NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
  NSString *executableDir = executablePath ? [executablePath stringByDeletingLastPathComponent] : nil;
  
  // On iOS Simulator, bundlePath and resourcePath might be the same
  // But let's check both to be safe
  if (resourcePath && ![resourcePath isEqualToString:bundlePath]) {
    NSLog(@"[WawonaPreferences] Resource path differs from bundle path: %@", resourcePath);
  }
  
  // pathForResource:ofType: can return nil, so check before adding
  NSString *resourcePath1 = [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:nil];
  addPathIfNotNil(resourcePath1);
  
  NSString *resourcePath2 = [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:@"bin"];
  addPathIfNotNil(resourcePath2);
  
  // Check bundle root first (iOS Simulator might not preserve bin/ directory)
  addPathIfNotNil([bundlePath stringByAppendingPathComponent:@"waypipe"]);
  addPathIfNotNil([bundlePath stringByAppendingPathComponent:@"waypipe-bin"]);
  // Then check bin directory
  addPathIfNotNil([bundlePath stringByAppendingPathComponent:@"bin/waypipe"]);
  addPathIfNotNil([bundlePath stringByAppendingPathComponent:@"Frameworks/waypipe"]);
  
  // Also check resource path if different
  if (resourcePath && ![resourcePath isEqualToString:bundlePath]) {
    addPathIfNotNil([resourcePath stringByAppendingPathComponent:@"waypipe"]);
    addPathIfNotNil([resourcePath stringByAppendingPathComponent:@"waypipe-bin"]);
    addPathIfNotNil([resourcePath stringByAppendingPathComponent:@"bin/waypipe"]);
  }
  
  // Next to the app executable
  if (executableDir) {
    addPathIfNotNil([executableDir stringByAppendingPathComponent:@"waypipe"]);
    addPathIfNotNil([executableDir stringByAppendingPathComponent:@"bin/waypipe"]);
  }
  
  // System paths (for development/testing on macOS)
#if !TARGET_OS_IPHONE
  addPathIfNotNil(@"/usr/local/bin/waypipe");
  addPathIfNotNil(@"/opt/homebrew/bin/waypipe");
  addPathIfNotNil(@"/nix/var/nix/profiles/default/bin/waypipe");
#endif
  
  // Environment variable (if set)
  NSString *envPath = [[NSProcessInfo processInfo] environment][@"WAYPIPE_BIN"];
  if (envPath) {
    addPathIfNotNil([envPath stringByStandardizingPath]);
  }
  
  // Check Nix store paths from environment (for development)
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  for (NSString *key in env.allKeys) {
    if ([key hasPrefix:@"NIX_STORE"] || [key containsString:@"waypipe"]) {
      NSString *value = env[key];
      if (value && [value containsString:@"waypipe"] && [value hasPrefix:@"/"]) {
        addPathIfNotNil(value);
      }
    }
  }
  
  NSLog(@"[WawonaPreferences] Searching for Waypipe binary...");
  NSLog(@"[WawonaPreferences] Bundle path: %@", bundlePath);
  NSLog(@"[WawonaPreferences] Executable path: %@", executablePath);
  
  // Debug: List bundle contents to see what's actually there
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *bundleContents = [fm contentsOfDirectoryAtPath:bundlePath error:nil];
  NSLog(@"[WawonaPreferences] Bundle contents: %@", bundleContents);
  
  // Check if bin directory exists
  NSString *binDir = [bundlePath stringByAppendingPathComponent:@"bin"];
  BOOL binDirExists = [fm fileExistsAtPath:binDir isDirectory:nil];
  NSLog(@"[WawonaPreferences] bin directory exists: %@ at %@", binDirExists ? @"YES" : @"NO", binDir);
  if (binDirExists) {
    NSArray *binContents = [fm contentsOfDirectoryAtPath:binDir error:nil];
    NSLog(@"[WawonaPreferences] bin directory contents: %@", binContents);
  }
  
  for (NSString *path in possiblePaths) {
    BOOL exists = [fm fileExistsAtPath:path];
    BOOL isExecutable = exists ? [fm isExecutableFileAtPath:path] : NO;
    
    // Also check if it's a directory (shouldn't be, but let's be thorough)
    BOOL isDirectory = NO;
    if (exists) {
      [fm fileExistsAtPath:path isDirectory:&isDirectory];
    }
    
    NSLog(@"[WawonaPreferences] Checking: %@ (exists: %@, executable: %@, isDirectory: %@)", 
          path, exists ? @"YES" : @"NO", isExecutable ? @"YES" : @"NO", isDirectory ? @"YES" : @"NO");
    
    if (exists && !isDirectory && isExecutable) {
      NSLog(@"[WawonaPreferences] ✅ Found Waypipe at: %@", path);
      return path;
    }
    
    // If file exists but isn't executable, try to make it executable
    if (exists && !isDirectory && !isExecutable) {
      NSLog(@"[WawonaPreferences] ⚠️ Waypipe found but not executable, attempting to fix permissions...");
      
      // Try using NSFileManager first
      NSDictionary *attrs = @{NSFilePosixPermissions: @0755};
      NSError *permError = nil;
      if ([fm setAttributes:attrs ofItemAtPath:path error:&permError]) {
        isExecutable = [fm isExecutableFileAtPath:path];
        if (isExecutable) {
          NSLog(@"[WawonaPreferences] ✅ Fixed permissions via NSFileManager, found Waypipe at: %@", path);
          return path;
        }
      } else {
        NSLog(@"[WawonaPreferences] NSFileManager setAttributes failed: %@", permError.localizedDescription);
      }
      
      // Fallback: Use chmod system call
      const char *cPath = [path UTF8String];
      if (chmod(cPath, 0755) == 0) {
        isExecutable = [fm isExecutableFileAtPath:path];
        if (isExecutable) {
          NSLog(@"[WawonaPreferences] ✅ Fixed permissions via chmod, found Waypipe at: %@", path);
          return path;
        } else {
          NSLog(@"[WawonaPreferences] chmod succeeded but file still not executable");
        }
      } else {
        NSLog(@"[WawonaPreferences] chmod failed: %s", strerror(errno));
      }
    }
  }
  
  NSLog(@"[WawonaPreferences] ❌ Waypipe binary not found in any checked location");
  NSLog(@"[WawonaPreferences] Checked %lu locations", (unsigned long)possiblePaths.count);
  
  // Final attempt: search recursively in bundle
  NSLog(@"[WawonaPreferences] Attempting recursive search in bundle...");
  NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
  NSString *file;
  while ((file = [enumerator nextObject])) {
    if ([file.lastPathComponent isEqualToString:@"waypipe"] || [file.lastPathComponent isEqualToString:@"waypipe-bin"]) {
      NSString *fullPath = [bundlePath stringByAppendingPathComponent:file];
      BOOL isDirectory = NO;
      BOOL exists = [fm fileExistsAtPath:fullPath isDirectory:&isDirectory];
      BOOL isExecutable = exists && !isDirectory ? [fm isExecutableFileAtPath:fullPath] : NO;
      NSLog(@"[WawonaPreferences] Found waypipe via recursive search: %@ (exists: %@, executable: %@, isDirectory: %@)", 
            fullPath, exists ? @"YES" : @"NO", isExecutable ? @"YES" : @"NO", isDirectory ? @"YES" : @"NO");
      
      if (exists && !isDirectory && isExecutable) {
        NSLog(@"[WawonaPreferences] ✅ Found Waypipe at: %@", fullPath);
        return fullPath;
      }
      
      // Try to fix permissions if file exists but isn't executable
      if (exists && !isDirectory && !isExecutable) {
        NSLog(@"[WawonaPreferences] ⚠️ Waypipe found via recursive search but not executable, fixing permissions...");
        const char *cPath = [fullPath UTF8String];
        if (chmod(cPath, 0755) == 0) {
          isExecutable = [fm isExecutableFileAtPath:fullPath];
          if (isExecutable) {
            NSLog(@"[WawonaPreferences] ✅ Fixed permissions via chmod, found Waypipe at: %@", fullPath);
            return fullPath;
          }
        }
      }
    }
  }
  
  return nil;
}

- (NSArray *)buildWaypipeArguments:(WawonaPreferencesManager *)prefs {
  NSMutableArray *args = [NSMutableArray array];
  
  // Display socket
  NSString *display = prefs.waypipeDisplay;
  if (display && display.length > 0) {
    [args addObject:@"--display"];
    [args addObject:display];
  }
  
  // Socket path
  NSString *socket = prefs.waypipeSocket;
  if (socket && socket.length > 0) {
    [args addObject:@"--socket"];
    [args addObject:socket];
  }
  
  // Compression
  NSString *compress = prefs.waypipeCompress;
  if (compress && compress.length > 0 && ![compress isEqualToString:@"none"]) {
    [args addObject:@"--compress"];
    [args addObject:compress];
    
    if ([compress isEqualToString:@"zstd"]) {
      NSString *level = prefs.waypipeCompressLevel;
      if (level && level.length > 0) {
        [args addObject:@"--compress-level"];
        [args addObject:level];
      }
    }
  }
  
  // Threads
  NSString *threads = prefs.waypipeThreads;
  if (threads && threads.length > 0 && ![threads isEqualToString:@"0"]) {
    [args addObject:@"--threads"];
    [args addObject:threads];
  }
  
  // Video codec
  NSString *video = prefs.waypipeVideo;
  if (video && video.length > 0 && ![video isEqualToString:@"none"]) {
    [args addObject:@"--video"];
    [args addObject:video];
    
    NSString *vEnc = prefs.waypipeVideoEncoding;
    if (vEnc && vEnc.length > 0) {
      [args addObject:@"--video-encoding"];
      [args addObject:vEnc];
    }
    
    NSString *vDec = prefs.waypipeVideoDecoding;
    if (vDec && vDec.length > 0) {
      [args addObject:@"--video-decoding"];
      [args addObject:vDec];
    }
    
    NSString *bpf = prefs.waypipeVideoBpf;
    if (bpf && bpf.length > 0) {
      [args addObject:@"--video-bpf"];
      [args addObject:bpf];
    }
  }
  
  // Debug mode
  if (prefs.waypipeDebug) {
    [args addObject:@"--debug"];
  }
  
  // No GPU
  if (prefs.waypipeNoGpu) {
    [args addObject:@"--no-gpu"];
  }
  
  // One-shot
  if (prefs.waypipeOneshot) {
    [args addObject:@"--oneshot"];
  }
  
  // Unlink socket
  if (prefs.waypipeUnlinkSocket) {
    [args addObject:@"--unlink-socket"];
  }
  
  // Login shell
  if (prefs.waypipeLoginShell) {
    [args addObject:@"--login-shell"];
  }
  
  // VSock
  if (prefs.waypipeVsock) {
    [args addObject:@"--vsock"];
  }
  
  // XWayland
  if (prefs.waypipeXwls) {
    [args addObject:@"--xwls"];
  }
  
  // Title prefix
  NSString *titlePrefix = prefs.waypipeTitlePrefix;
  if (titlePrefix && titlePrefix.length > 0) {
    [args addObject:@"--title-prefix"];
    [args addObject:titlePrefix];
  }
  
  // Security context
  NSString *secCtx = prefs.waypipeSecCtx;
  if (secCtx && secCtx.length > 0) {
    [args addObject:@"--sec-ctx"];
    [args addObject:secCtx];
  }
  
  // SSH mode (always enabled on iOS/macOS)
  // Note: Waypipe uses "ssh" as a subcommand, not a binary path
  // The actual SSH binary path is handled via PATH environment variable
  NSString *host = prefs.waypipeSSHHost;
  NSString *user = prefs.waypipeSSHUser;
  NSString *command = prefs.waypipeRemoteCommand;
  
  if (host && host.length > 0) {
    // Waypipe expects "ssh" as a literal subcommand, not a path
    [args addObject:@"ssh"];
    
    // Build SSH target: user@host or just host
    NSString *sshTarget;
    if (user && user.length > 0) {
      sshTarget = [NSString stringWithFormat:@"%@@%@", user, host];
    } else {
      sshTarget = host;
    }
    [args addObject:sshTarget];
    
    // Remote command
    if (command && command.length > 0) {
      [args addObject:command];
    }
  }
  
  return args;
}

- (void)runWaypipe {
  WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
  NSString *host = prefs.waypipeSSHHost;
  
  // SSH is always enabled on iOS/macOS
  if (!host || host.length == 0) {
#if TARGET_OS_OSX
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"SSH Host Required";
    alert.informativeText = @"Please enter an SSH host in the Waypipe settings.";
    [alert runModal];
#else
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SSH Host Required"
                                                                   message:@"Please enter an SSH host in the Waypipe settings."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
#endif
    return;
  }
  
  // Find Waypipe binary
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    NSString *errorMsg = @"Waypipe binary not found. Please ensure Waypipe is bundled with the app.";
    NSLog(@"[WawonaPreferences] ERROR: %@", errorMsg);
#if TARGET_OS_OSX
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Waypipe Not Found";
    alert.informativeText = errorMsg;
    [alert runModal];
#else
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Waypipe Not Found"
                                                                   message:errorMsg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
#endif
    return;
  }
  
  // Build command arguments
  NSArray *args = [self buildWaypipeArguments:prefs];
  
  // Log the command
  NSMutableString *cmdString = [NSMutableString stringWithString:waypipePath];
  for (NSString *arg in args) {
    [cmdString appendFormat:@" %@", arg];
  }
  NSLog(@"[WawonaPreferences] Launching Waypipe: %@", cmdString);
  
#if TARGET_OS_IPHONE
  // iOS: Use posix_spawn with pipes to capture output (fork is not available in sandbox)
  const char *binaryPath = [waypipePath UTF8String];
  
  // Convert NSArray to C array
  NSMutableArray *allArgs = [NSMutableArray arrayWithObject:waypipePath];
  [allArgs addObjectsFromArray:args];
  
  const char **argv = malloc(sizeof(char *) * (allArgs.count + 1));
  for (NSUInteger i = 0; i < allArgs.count; i++) {
    argv[i] = [allArgs[i] UTF8String];
  }
  argv[allArgs.count] = NULL;
  
  // Set up environment
  extern char **environ;
  
  // Prepare environment variables for Waypipe
  NSMutableDictionary *envDict = [[[NSProcessInfo processInfo] environment] mutableCopy];
  NSString *socketDir = prefs.waylandSocketDir;
  NSString *display = prefs.waypipeDisplay;
  if (socketDir && display) {
    NSString *waylandDisplay = [NSString stringWithFormat:@"%@/%@", socketDir, display];
    envDict[@"WAYLAND_DISPLAY"] = waylandDisplay;
    NSLog(@"[WawonaPreferences] Setting WAYLAND_DISPLAY=%@", waylandDisplay);
  }
  // Set XDG_RUNTIME_DIR if not set
  if (!envDict[@"XDG_RUNTIME_DIR"]) {
    NSString *runtimeDir = NSTemporaryDirectory();
    if (runtimeDir) {
      envDict[@"XDG_RUNTIME_DIR"] = runtimeDir;
      NSLog(@"[WawonaPreferences] Setting XDG_RUNTIME_DIR=%@", runtimeDir);
    }
  }
  
#if TARGET_OS_IPHONE
  // On iOS Simulator, ensure PATH includes /usr/bin so ssh can be found
  NSString *currentPath = envDict[@"PATH"];
  if (currentPath) {
    if (![currentPath containsString:@"/usr/bin"]) {
      envDict[@"PATH"] = [NSString stringWithFormat:@"%@:/usr/bin:/bin:/usr/sbin:/sbin", currentPath];
      NSLog(@"[WawonaPreferences] Updated PATH to include /usr/bin: %@", envDict[@"PATH"]);
    }
  } else {
    envDict[@"PATH"] = @"/usr/bin:/bin:/usr/sbin:/sbin";
    NSLog(@"[WawonaPreferences] Set PATH=%@", envDict[@"PATH"]);
  }
  
  // Also try to find ssh and verify it exists
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *sshPaths = @[@"/usr/bin/ssh", @"/bin/ssh"];
  NSString *sshPath = nil;
  for (NSString *path in sshPaths) {
    if ([fm isExecutableFileAtPath:path]) {
      sshPath = path;
      NSLog(@"[WawonaPreferences] Found SSH at: %@", sshPath);
      break;
    }
  }
  
  if (!sshPath) {
    NSLog(@"[WawonaPreferences] WARNING: SSH not found in standard locations");
    // Show error to user
    dispatch_async(dispatch_get_main_queue(), ^{
      UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SSH Not Available"
                                                                     message:@"SSH binary not found. iOS Simulator may have restrictions on executing system binaries."
                                                              preferredStyle:UIAlertControllerStyleAlert];
      UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
      [alert addAction:okAction];
      [self presentViewController:alert animated:YES completion:nil];
    });
  } else {
    // Verify we can actually access it (sandbox check)
    NSLog(@"[WawonaPreferences] SSH path verified: %@", sshPath);
  }
#endif
  
  // Convert environment dictionary to C array
  NSMutableArray *envArray = [NSMutableArray array];
  for (NSString *key in envDict.allKeys) {
    NSString *value = envDict[key];
    [envArray addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    // Log PATH specifically to verify it's being set
    if ([key isEqualToString:@"PATH"]) {
      NSLog(@"[WawonaPreferences] Environment PATH=%@", value);
    }
  }
  
  NSLog(@"[WawonaPreferences] Total environment variables: %lu", (unsigned long)envArray.count);
  
  const char **envp = malloc(sizeof(char *) * (envArray.count + 1));
  for (NSUInteger i = 0; i < envArray.count; i++) {
    envp[i] = [envArray[i] UTF8String];
    // Log PATH entry to verify
    if (strncmp(envp[i], "PATH=", 5) == 0) {
      NSLog(@"[WawonaPreferences] Environment array PATH entry: %s", envp[i]);
    }
  }
  envp[envArray.count] = NULL;
  
  // Create pipes for stdout and stderr
  int stdoutPipe[2];
  int stderrPipe[2];
  if (pipe(stdoutPipe) != 0 || pipe(stderrPipe) != 0) {
    NSLog(@"[WawonaPreferences] ERROR: Failed to create pipes: %s", strerror(errno));
    free(argv);
    return;
  }
  
  // Set up file actions for posix_spawn
  posix_spawn_file_actions_t file_actions;
  posix_spawn_file_actions_init(&file_actions);
  posix_spawn_file_actions_adddup2(&file_actions, stdoutPipe[1], STDOUT_FILENO);
  posix_spawn_file_actions_adddup2(&file_actions, stderrPipe[1], STDERR_FILENO);
  posix_spawn_file_actions_addclose(&file_actions, stdoutPipe[0]);
  posix_spawn_file_actions_addclose(&file_actions, stderrPipe[1]);
  
  // Debug: Print environment variables being passed (especially PATH)
  NSLog(@"[WawonaPreferences] Environment variables being passed to Waypipe:");
  for (NSUInteger i = 0; envp[i] != NULL; i++) {
    if (strncmp(envp[i], "PATH=", 5) == 0) {
      NSLog(@"[WawonaPreferences]   %s", envp[i]);
    }
  }
  
  // Launch process with custom environment
  pid_t pid;
  int status = posix_spawn(&pid, binaryPath, &file_actions, NULL, (char *const *)argv, envp);
  
  // Clean up file actions
  posix_spawn_file_actions_destroy(&file_actions);
  
  // Close write ends of pipes (child has them now)
  close(stdoutPipe[1]);
  close(stderrPipe[1]);
  
  if (status != 0) {
    NSLog(@"[WawonaPreferences] ERROR: Failed to launch Waypipe: posix_spawn returned %d", status);
    NSString *errorMsg = [NSString stringWithFormat:@"Failed to launch Waypipe: %s", strerror(status)];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Launch Failed"
                                                                   message:errorMsg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
    
    close(stdoutPipe[0]);
    close(stderrPipe[0]);
    free(argv);
    free(envp);
    return;
  }
  
  NSLog(@"[WawonaPreferences] Waypipe launched successfully (PID: %d)", pid);
  
  // Capture file descriptors for blocks (can't capture arrays directly)
  int stdoutFd = stdoutPipe[0];
  int stderrFd = stderrPipe[0];
  
  // Read output asynchronously
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  
  // Read stdout
  dispatch_async(queue, ^{
    char buffer[4096];
    NSMutableString *output = [NSMutableString string];
    ssize_t bytesRead;
    
    while ((bytesRead = read(stdoutFd, buffer, sizeof(buffer) - 1)) > 0) {
      buffer[bytesRead] = '\0';
      NSString *chunk = [NSString stringWithUTF8String:buffer];
      [output appendString:chunk];
      NSLog(@"[Waypipe stdout] %@", chunk);
      
      // Check for password prompts
      if ([chunk containsString:@"password:"] || [chunk containsString:@"Password:"] || [chunk containsString:@"passphrase"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self handleSSHPasswordPrompt:chunk];
        });
      }
    }
    
    close(stdoutFd);
  });
  
  // Read stderr
  dispatch_async(queue, ^{
    char buffer[4096];
    NSMutableString *errorOutput = [NSMutableString string];
    ssize_t bytesRead;
    
    while ((bytesRead = read(stderrFd, buffer, sizeof(buffer) - 1)) > 0) {
      buffer[bytesRead] = '\0';
      NSString *chunk = [NSString stringWithUTF8String:buffer];
      [errorOutput appendString:chunk];
      NSLog(@"[Waypipe stderr] %@", chunk);
      
      // Check for password prompts or errors
      if ([chunk containsString:@"password:"] || [chunk containsString:@"Password:"] || [chunk containsString:@"passphrase"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self handleSSHPasswordPrompt:chunk];
        });
      } else if ([chunk containsString:@"Permission denied"] || [chunk containsString:@"Host key verification failed"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self handleSSHError:chunk];
        });
      }
    }
    
    close(stderrFd);
  });
  
  free(argv);
  
#else
  // macOS: Use NSTask
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:waypipePath];
  task.arguments = args;
  
  // Set up environment
  NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
  // Ensure WAYLAND_DISPLAY is set if needed
  NSString *socketDir = prefs.waylandSocketDir;
  NSString *display = prefs.waypipeDisplay;
  if (socketDir && display) {
    NSString *waylandDisplay = [NSString stringWithFormat:@"%@/%@", socketDir, display];
    env[@"WAYLAND_DISPLAY"] = waylandDisplay;
  }
  task.environment = env;
  
  // Set up output pipes for logging
  NSPipe *outputPipe = [NSPipe pipe];
  NSPipe *errorPipe = [NSPipe pipe];
  task.standardOutput = outputPipe;
  task.standardError = errorPipe;
  
  // Read output asynchronously
  outputPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
    NSData *data = handle.availableData;
    if (data.length > 0) {
      NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      NSLog(@"[Waypipe stdout] %@", output);
    }
  };
  
  errorPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
    NSData *data = handle.availableData;
    if (data.length > 0) {
      NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      NSLog(@"[Waypipe stderr] %@", output);
    }
  };
  
  NSError *error = nil;
  if (![task launchAndReturnError:&error]) {
    NSLog(@"[WawonaPreferences] ERROR: Failed to launch Waypipe: %@", error.localizedDescription);
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Failed to Launch Waypipe";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    [alert runModal];
    return;
  }
  
  NSLog(@"[WawonaPreferences] Waypipe launched successfully (PID: %d)", task.processIdentifier);
  
  // Don't wait for the task - let it run in background
  // The readability handlers will log output as it comes
#endif
}

- (void)handleSSHPasswordPrompt:(NSString *)prompt {
  NSLog(@"[WawonaPreferences] SSH password prompt detected: %@", prompt);
  
#if TARGET_OS_IPHONE
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SSH Password Required"
                                                                 message:@"Waypipe needs your SSH password to connect. Enter it below:"
                                                          preferredStyle:UIAlertControllerStyleAlert];
  
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.placeholder = @"Password";
    textField.secureTextEntry = YES;
  }];
  
  UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                         style:UIAlertActionStyleCancel
                                                       handler:nil];
  
  UIAlertAction *submitAction = [UIAlertAction actionWithTitle:@"Submit"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
    UITextField *passwordField = alert.textFields.firstObject;
    NSString *password = passwordField.text;
    
    if (password && password.length > 0) {
      NSLog(@"[WawonaPreferences] Password entered (length: %lu)", (unsigned long)password.length);
      // Note: We can't directly send the password to the running process easily
      // The user will need to configure SSH keys instead for a better experience
      UIAlertController *infoAlert = [UIAlertController alertControllerWithTitle:@"SSH Key Recommended"
                                                                        message:@"For better security and convenience, please configure SSH key authentication. You can add your SSH key in Settings > Waypipe."
                                                                 preferredStyle:UIAlertControllerStyleAlert];
      UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
      [infoAlert addAction:okAction];
      [self presentViewController:infoAlert animated:YES completion:nil];
    }
  }];
  
  [alert addAction:cancelAction];
  [alert addAction:submitAction];
  
  [self presentViewController:alert animated:YES completion:nil];
#else
  // macOS: Show password dialog
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"SSH Password Required";
  alert.informativeText = @"Waypipe needs your SSH password to connect.";
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  [alert runModal];
#endif
}

- (void)handleSSHError:(NSString *)error {
  NSLog(@"[WawonaPreferences] SSH error detected: %@", error);
  
#if TARGET_OS_IPHONE
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SSH Connection Error"
                                                                 message:error
                                                          preferredStyle:UIAlertControllerStyleAlert];
  
  UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
  [alert addAction:okAction];
  
  // Add action to configure SSH keys if it's a permission/key error
  if ([error containsString:@"Permission denied"] || [error containsString:@"Host key verification failed"]) {
    UIAlertAction *configureAction = [UIAlertAction actionWithTitle:@"Configure SSH Keys"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction *action) {
      // TODO: Navigate to SSH key configuration in settings
      NSLog(@"[WawonaPreferences] User wants to configure SSH keys");
    }];
    [alert addAction:configureAction];
  }
  
  [self presentViewController:alert animated:YES completion:nil];
#else
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"SSH Connection Error";
  alert.informativeText = error;
  [alert runModal];
#endif
}

#if TARGET_OS_IPHONE

- (void)showPreferences:(id)sender {
  // On iOS, showPreferences is typically called to present the view controller
  // Since WawonaPreferences is a UIViewController on iOS, this might be called
  // from elsewhere. For now, we'll ensure the view is loaded.
  [self loadViewIfNeeded];
}

- (void)dismissSelf {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
  return self.sections.count;
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
  return self.sections[sec].items.count;
}
- (NSString *)tableView:(UITableView *)tv
    titleForHeaderInSection:(NSInteger)sec {
  return self.sections[sec].title;
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {
  WawonaSettingItem *item = self.sections[ip.section].items[ip.row];
  UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"Cell"];
  if (!cell)
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                  reuseIdentifier:@"Cell"];

  cell.textLabel.text = item.title;
  cell.detailTextLabel.text = nil;
  cell.accessoryView = nil;
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  if (item.type == WawonaSettingTypeSwitch) {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
    sw.tag = (ip.section * 1000) + ip.row;
    [sw addTarget:self
                  action:@selector(swChg:)
        forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
  } else if (item.type == WawonaSettingTypeText ||
             item.type == WawonaSettingTypeNumber) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key]
                 ?: item.defaultValue;
    cell.detailTextLabel.text = [val description];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WawonaSettingTypePopup) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key]
                 ?: item.defaultValue;
    cell.detailTextLabel.text = [val description];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WawonaSettingTypeButton) {
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WawonaSettingTypeInfo) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key]
                 ?: item.defaultValue;
    cell.detailTextLabel.text = [val description];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
  }
  return cell;
}

- (void)swChg:(UISwitch *)s {
  WawonaSettingItem *item = self.sections[s.tag / 1000].items[s.tag % 1000];
  [[NSUserDefaults standardUserDefaults] setBool:s.on forKey:item.key];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
  [tv deselectRowAtIndexPath:ip animated:YES];
  WawonaSettingItem *item = self.sections[ip.section].items[ip.row];
  
  if (item.type == WawonaSettingTypeText || item.type == WawonaSettingTypeNumber) {
    // Present text entry view controller
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title
                                                                     message:item.desc
                                                              preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      id currentValue = [[NSUserDefaults standardUserDefaults] objectForKey:item.key] ?: item.defaultValue;
      textField.text = [currentValue description];
      if (item.type == WawonaSettingTypeNumber) {
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
      } else {
        textField.keyboardType = UIKeyboardTypeDefault;
      }
      textField.placeholder = item.desc;
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                             style:UIAlertActionStyleCancel
                                                           handler:nil];
    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
      UITextField *textField = alert.textFields.firstObject;
      NSString *value = textField.text;
      
      if (item.type == WawonaSettingTypeNumber) {
        NSNumber *numberValue = @([value doubleValue]);
        [[NSUserDefaults standardUserDefaults] setObject:numberValue forKey:item.key];
      } else {
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:item.key];
      }
      [[NSUserDefaults standardUserDefaults] synchronize];
      
      // Reload the table view to show updated value
      [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:saveAction];
    
    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WawonaSettingTypeInfo) {
    // For info items, show copy dialog
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key] ?: item.defaultValue;
    NSString *valueString = [val description];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title
                                                                   message:[NSString stringWithFormat:@"%@\n\n%@", item.desc, valueString]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"Copy"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
      UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
      pasteboard.string = valueString;
    }];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                         style:UIAlertActionStyleCancel
                                                       handler:nil];
    
    [alert addAction:copyAction];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WawonaSettingTypePopup) {
    // Present popup selection
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title
                                                                   message:item.desc
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    id currentValue = [[NSUserDefaults standardUserDefaults] objectForKey:item.key] ?: item.defaultValue;
    NSString *currentValueString = [currentValue description];
    
    for (NSString *option in item.options) {
      NSString *optionCopy = option; // Capture for block
      UIAlertAction *optionAction = [UIAlertAction actionWithTitle:option
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *alertAction) {
        [[NSUserDefaults standardUserDefaults] setObject:optionCopy forKey:item.key];
        [[NSUserDefaults standardUserDefaults] synchronize];
        // Reload the table view to show updated value
        [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
      }];
      
      // Mark current selection with checkmark
      if ([option isEqualToString:currentValueString]) {
        [optionAction setValue:@YES forKey:@"checked"];
      }
      
      [alert addAction:optionAction];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:cancelAction];
    
    // For iPad, we need to set the popover presentation
    if (alert.popoverPresentationController) {
      UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
      alert.popoverPresentationController.sourceView = cell;
      alert.popoverPresentationController.sourceRect = cell.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.actionBlock) {
    item.actionBlock();
  }
}

#else

// MARK: - macOS Interface

- (void)showPreferences:(id)sender {
  if (self.winController) {
    [self.winController.window makeKeyAndOrderFront:sender];
    return;
  }

  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 700, 500)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  win.title = @"Wawona Settings";
  win.titleVisibility = NSWindowTitleVisible;
  win.titlebarAppearsTransparent = YES;
  win.styleMask |= NSWindowStyleMaskFullSizeContentView;
  win.movableByWindowBackground = YES;

  // Add Toolbar (Liquid Glass Style)
  NSToolbar *toolbar =
      [[NSToolbar alloc] initWithIdentifier:@"WawonaPreferencesToolbar"];
  toolbar.delegate = self;
  toolbar.displayMode = NSToolbarDisplayModeIconOnly;
  win.toolbar = toolbar;

  NSVisualEffectView *v =
      [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 700, 500)];
  v.material = NSVisualEffectMaterialSidebar;
  v.blendingMode = NSVisualEffectBlendingModeBehindWindow;
  v.state = NSVisualEffectStateActive;
  win.contentView = v;

  self.sidebar = [[WawonaPreferencesSidebar alloc] init];
  self.sidebar.parent = self;
  self.content = [[WawonaPreferencesContent alloc] init];

  self.splitVC = [[NSSplitViewController alloc] init];
  NSSplitViewItem *sItem =
      [NSSplitViewItem sidebarWithViewController:self.sidebar];
  sItem.minimumThickness = 130;
  sItem.maximumThickness = 160;
  NSSplitViewItem *cItem =
      [NSSplitViewItem contentListWithViewController:self.content];
  [self.splitVC addSplitViewItem:sItem];
  [self.splitVC addSplitViewItem:cItem];

  // Embed SplitVC in Visual Effect View
  self.splitVC.view.frame = v.bounds;
  self.splitVC.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [v addSubview:self.splitVC.view];

  self.winController = [[NSWindowController alloc] initWithWindow:win];
  [win center];
  [win makeKeyAndOrderFront:sender];

  if (self.sections.count > 0) {
    [self.sidebar.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                          byExtendingSelection:NO];
  }
}

- (void)showSection:(NSInteger)idx {
  self.content.section = self.sections[idx];
  [self.content.tableView reloadData];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:
    (NSToolbar *)toolbar {
  return @[
    @"com.apple.NSToolbar.toggleSidebar", NSToolbarFlexibleSpaceItemIdentifier
  ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:
    (NSToolbar *)toolbar {
  return @[ @"com.apple.NSToolbar.toggleSidebar" ];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
    willBeInsertedIntoToolbar:(BOOL)flag {
  if ([itemIdentifier isEqualToString:@"com.apple.NSToolbar.toggleSidebar"]) {
    NSToolbarItem *item =
        [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    item.label = @"Toggle Sidebar";
    item.paletteLabel = @"Toggle Sidebar";
    item.toolTip = @"Toggle Sidebar";
    item.image = [NSImage imageWithSystemSymbolName:@"sidebar.left"
                           accessibilityDescription:nil];
    item.target = nil; // First Responder
    item.action = @selector(toggleSidebar:);
    return item;
  }
  return nil;
}

- (void)toggleSidebar:(id)sender {
  [NSApp sendAction:@selector(toggleSidebar:) to:nil from:sender];
}

#endif

@end

// MARK: - Helper Implementations

#if !TARGET_OS_IPHONE

@implementation WawonaPreferencesSidebar
- (void)loadView {
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
  self.view = v;
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:v.bounds];
  sv.drawsBackground = NO;
  sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.outlineView = [[NSOutlineView alloc] initWithFrame:sv.bounds];
  self.outlineView.dataSource = self;
  self.outlineView.delegate = self;
  self.outlineView.headerView = nil;
  self.outlineView.rowHeight = 28.0; // Standard sidebar height
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"M"];
  [self.outlineView addTableColumn:col];
  self.outlineView.outlineTableColumn = col;
  sv.documentView = self.outlineView;
  [v addSubview:sv];
}
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
  return item ? 0 : self.parent.sections.count;
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
  return NO;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)idx ofItem:(id)item {
  return self.parent.sections[idx];
}
- (NSView *)outlineView:(NSOutlineView *)ov
     viewForTableColumn:(NSTableColumn *)tc
                   item:(id)item {
  WawonaPreferencesSection *s = item;
  NSTableCellView *cell = [ov makeViewWithIdentifier:@"Cell" owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)];
    cell.identifier = @"Cell";

    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSZeroRect];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:iv];
    cell.imageView = iv;

    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSZeroRect];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.bordered = NO;
    tf.drawsBackground = NO;
    tf.editable = NO;
    [tf setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                 forOrientation:
                                     NSLayoutConstraintOrientationHorizontal]; // Allow truncation if needed
    [cell addSubview:tf];
    cell.textField = tf;

    [NSLayoutConstraint activateConstraints:@[
      [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:5],
      [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
      [iv.widthAnchor constraintEqualToConstant:20],
      [iv.heightAnchor constraintEqualToConstant:20],

      [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:5],
      [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor
                                        constant:-5],
      [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
    ]];
  }
  cell.imageView.image =
      [NSImage imageWithSystemSymbolName:s.icon accessibilityDescription:nil];
  cell.imageView.contentTintColor = s.iconColor;
  cell.textField.stringValue = s.title;
  return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)n {
  NSInteger row = self.outlineView.selectedRow;
  if (row >= 0)
    [self.parent showSection:row];
}
@end

// MARK: - WawonaPreferenceCell
// A robust, statically laid-out cell to prevent visual corruption and reduce
// LOC.
@interface WawonaPreferenceCell : NSTableCellView
@property(strong) NSTextField *titleLabel;
@property(strong) NSTextField *descLabel;
@property(strong) NSSwitch *switchControl;
@property(strong) NSTextField *textControl;
@property(strong) NSButton *buttonControl;
@property(strong) NSPopUpButton *popupControl;
@property(strong) WawonaSettingItem *item;
@end

@implementation WawonaPreferenceCell
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.identifier = @"PCell";

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:13];
    _titleLabel.textColor = [NSColor labelColor];
    [_titleLabel
        setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                 forOrientation:
                                     NSLayoutConstraintOrientationVertical];
    [self addSubview:_titleLabel];

    _descLabel = [NSTextField labelWithString:@""];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.font = [NSFont systemFontOfSize:11];
    _descLabel.textColor = [NSColor secondaryLabelColor];
    [_descLabel
        setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                 forOrientation:
                                     NSLayoutConstraintOrientationVertical];
    [self addSubview:_descLabel];

    // Initialize all potential controls hidden
    _switchControl = [[NSSwitch alloc] init];
    _switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    _switchControl.hidden = YES;
    [self addSubview:_switchControl];

    _textControl = [[NSTextField alloc] init];
    _textControl.translatesAutoresizingMaskIntoConstraints = NO;
    _textControl.hidden = YES;
    [self addSubview:_textControl];

    _buttonControl = [NSButton buttonWithTitle:@"Run" target:nil action:nil];
    _buttonControl.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonControl.bezelStyle = NSBezelStyleRounded;
    _buttonControl.hidden = YES;
    [self addSubview:_buttonControl];

    _popupControl =
        [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _popupControl.translatesAutoresizingMaskIntoConstraints = NO;
    _popupControl.hidden = YES;
    [self addSubview:_popupControl];

    // Static Auto Layout
    [NSLayoutConstraint activateConstraints:@[
      [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:20],
      [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],

      [_descLabel.leadingAnchor
          constraintEqualToAnchor:_titleLabel.leadingAnchor],
      [_descLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                           constant:2],

      // Anchoring controls to trailing edge
      [_switchControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                    constant:-20],
      [_switchControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

      [_textControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                  constant:-20],
      [_textControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_textControl.widthAnchor constraintEqualToConstant:120],

      [_buttonControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                    constant:-20],
      [_buttonControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

      [_popupControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                   constant:-20],
      [_popupControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_popupControl.widthAnchor constraintEqualToConstant:100],

      // Prevent Overlap (Leading <-> Control)
      [_titleLabel.trailingAnchor
          constraintLessThanOrEqualToAnchor:_switchControl.leadingAnchor
                                   constant:-10],
      [_titleLabel.trailingAnchor
          constraintLessThanOrEqualToAnchor:_textControl.leadingAnchor
                                   constant:-10],
      [_titleLabel.trailingAnchor
          constraintLessThanOrEqualToAnchor:_buttonControl.leadingAnchor
                                   constant:-10],
      [_titleLabel.trailingAnchor
          constraintLessThanOrEqualToAnchor:_popupControl.leadingAnchor
                                   constant:-10],
    ]];
  }
  return self;
}

- (void)configureWithItem:(WawonaSettingItem *)item
                   target:(id)target
                   action:(SEL)action {
  self.item = item;
  self.titleLabel.stringValue = item.title;
  self.descLabel.stringValue = item.desc ? item.desc : @"";

  // Reset Visibility
  self.switchControl.hidden = YES;
  self.textControl.hidden = YES;
  self.buttonControl.hidden = YES;
  self.popupControl.hidden = YES;

  NSControl *active = nil;

  if (item.type == WawonaSettingTypeSwitch) {
    self.switchControl.hidden = NO;
    self.switchControl.state =
        [[NSUserDefaults standardUserDefaults] boolForKey:item.key]
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    self.switchControl.target = target;
    self.switchControl.action = action;
    active = self.switchControl;
  } else if (item.type == WawonaSettingTypeText ||
             item.type == WawonaSettingTypeNumber) {
    self.textControl.hidden = NO;
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    self.textControl.stringValue = val ? val : [item.defaultValue description];
    self.textControl.target = target;
    self.textControl.action = action;
    active = self.textControl;
  } else if (item.type == WawonaSettingTypeButton) {
    self.buttonControl.hidden = NO;
    self.buttonControl.target = target;
    self.buttonControl.action = action;
    active = self.buttonControl;
  } else if (item.type == WawonaSettingTypePopup) {
    self.popupControl.hidden = NO;
    [self.popupControl removeAllItems];
    [self.popupControl addItemsWithTitles:item.options];
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    [self.popupControl selectItemWithTitle:val ? val : item.defaultValue];
    self.popupControl.target = target;
    self.popupControl.action = action;
    active = self.popupControl;
  } else if (item.type == WawonaSettingTypeInfo) {
    // Info type: show read-only text with copy button
    self.textControl.hidden = NO;
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    self.textControl.stringValue = val ? val : [item.defaultValue description];
    self.textControl.editable = NO;
    self.textControl.selectable = YES;
    self.textControl.bezeled = NO;
    self.textControl.bordered = NO;
    self.textControl.backgroundColor = [NSColor clearColor];
    self.textControl.drawsBackground = NO;
    // Add copy button functionality via right-click or double-click
    active = self.textControl;
  }
}
@end

@interface WawonaSeparatorRowView : NSTableRowView
@end
@implementation WawonaSeparatorRowView
- (void)drawSeparatorInRect:(NSRect)dirtyRect {
  // Draw custom iOS-style separator
  NSRect sRect =
      NSMakeRect(20, 0, self.bounds.size.width - 20, 1.0); // Inset left
  [[NSColor separatorColor] setFill];
  NSRectFill(sRect);
}
@end

@implementation WawonaPreferencesContent
- (void)loadView {
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
  self.view = v;
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:v.bounds];
  sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  sv.drawsBackground = NO; // Fix Unified Background

  self.tableView = [[NSTableView alloc] initWithFrame:sv.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.headerView = nil;
  self.tableView.backgroundColor =
      [NSColor clearColor];                           // Fix Unified Background
  self.tableView.gridStyleMask = NSTableViewGridNone; // Custom separators
  self.tableView.intercellSpacing =
      NSMakeSize(0, 0); // Tight packing for custom rows

  NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"C"];
  c.width = 380;
  [self.tableView addTableColumn:c];
  sv.documentView = self.tableView;
  [v addSubview:sv];
}

// Use custom row view for separators
- (NSTableRowView *)tableView:(NSTableView *)tableView
                rowViewForRow:(NSInteger)row {
  WawonaSeparatorRowView *rv =
      [tableView makeViewWithIdentifier:@"Row" owner:self];
  if (!rv) {
    rv = [[WawonaSeparatorRowView alloc] initWithFrame:NSZeroRect];
    rv.identifier = @"Row";
  }
  return rv;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
  return self.section.items.count;
}

- (NSView *)tableView:(NSTableView *)tv
    viewForTableColumn:(NSTableColumn *)tc
                   row:(NSInteger)row {
  WawonaPreferenceCell *cell = [tv makeViewWithIdentifier:@"PCell" owner:self];
  if (!cell) {
    cell =
        [[WawonaPreferenceCell alloc] initWithFrame:NSMakeRect(0, 0, 400, 50)];
  }
  WawonaSettingItem *item = self.section.items[row];
  [cell configureWithItem:item target:self action:@selector(act:)];

  // Ensure tags are set correctly for 'act:' lookup if needed (though we rely
  // on sender usually)
  if (!cell.switchControl.hidden)
    cell.switchControl.tag = row;
  if (!cell.textControl.hidden)
    cell.textControl.tag = row;
  if (!cell.buttonControl.hidden)
    cell.buttonControl.tag = row;
  if (!cell.popupControl.hidden)
    cell.popupControl.tag = row;

  return cell;
}

- (void)act:(id)sender {
  NSInteger row = [sender tag];
  if (row < 0 || row >= self.section.items.count)
    return;

  WawonaSettingItem *item = self.section.items[row];
  if (item.type == WawonaSettingTypeButton) {
    if (item.actionBlock)
      item.actionBlock();
    return;
  }
  
  if (item.type == WawonaSettingTypeInfo) {
    // For Info type, copy to clipboard on click
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    NSString *valueString = val ? val : [item.defaultValue description];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:valueString forType:NSPasteboardTypeString];
    return;
  }

  id val = nil;
  if ([sender isKindOfClass:[NSSwitch class]]) {
    val = @([(NSSwitch *)sender state] == NSControlStateValueOn);
  } else if ([sender isKindOfClass:[NSTextField class]]) {
    val = [(NSTextField *)sender stringValue];
  } else if ([sender isKindOfClass:[NSPopUpButton class]]) {
    val = [(NSPopUpButton *)sender titleOfSelectedItem];
  }

  if (val && item.key) {
    [[NSUserDefaults standardUserDefaults] setObject:val forKey:item.key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"WawonaPreferencesChanged"
                      object:nil];
  }
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
  return 50.0;
}

@end

#endif
