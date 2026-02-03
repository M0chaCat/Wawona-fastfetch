#import "WawonaPreferences.h"
#import "../../logging/WawonaLog.h"
#import "../Helpers/WawonaImageLoader.h"
#import "WawonaPreferencesManager.h"
#import "WawonaSettingsModel.h"
#import "WawonaWaypipeRunner.h"
// #if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// #import <HIAHKernel/HIAHKernel.h>
// #endif
//  #import "../../core/WawonaKernel.h" // Removed
#import <Network/Network.h>
#import <objc/runtime.h>

// System headers removed as they are now used in WawonaWaypipeRunner or unused
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif
#import <arpa/inet.h>
#import <errno.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <spawn.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <unistd.h>

#ifndef WAWONA_WAYLAND_VERSION
#define WAWONA_WAYLAND_VERSION "Bundled"
#endif
#ifndef WAWONA_XKBCOMMON_VERSION
#define WAWONA_XKBCOMMON_VERSION "Bundled"
#endif
#ifndef WAWONA_LZ4_VERSION
#define WAWONA_LZ4_VERSION "Bundled"
#endif
#ifndef WAWONA_ZSTD_VERSION
#define WAWONA_ZSTD_VERSION "Bundled"
#endif
#ifndef WAWONA_LIBFFI_VERSION
#define WAWONA_LIBFFI_VERSION "Bundled"
#endif
#ifndef WAWONA_SSHPASS_VERSION
#define WAWONA_SSHPASS_VERSION "unknown"
#endif
#ifndef WAWONA_WAYPIPE_VERSION
#define WAWONA_WAYPIPE_VERSION "unknown"
#endif
#ifndef WAWONA_VERSION
#define WAWONA_VERSION "0.0.0-unknown"
#endif

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

@interface WawonaPreferences () <WawonaWaypipeRunnerDelegate,
                                 NSTextFieldDelegate
#if !TARGET_OS_IPHONE
                                 ,
                                 NSToolbarDelegate
#endif
                                 >
@property(nonatomic, strong, readwrite)
    NSArray<WawonaPreferencesSection *> *sections;
@property(nonatomic, strong) NSMutableString *waypipeStatusText;
@property(nonatomic, assign) BOOL waypipeMarkedConnected;
#if TARGET_OS_IPHONE
@property(nonatomic, strong) UIAlertController *waypipeStatusAlert;
#else
@property(nonatomic, strong) NSSplitViewController *splitVC;
@property(nonatomic, strong) WawonaPreferencesSidebar *sidebar;
@property(nonatomic, strong) WawonaPreferencesContent *content;
@property(nonatomic, strong) NSWindowController *winController;
@property(nonatomic, strong) NSPanel *waypipeStatusPanel;
@property(nonatomic, strong) NSTextView *waypipeStatusTextView;
@property(nonatomic, strong) NSButton *waypipeStopButton;
#endif
- (NSArray<WawonaPreferencesSection *> *)buildSections;
- (void)runWaypipe;
- (NSString *)localIPAddress;
- (void)pingHost;
- (void)pingSSHHost;
- (void)testSSHConnection;
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
  self = [super init];
  if (self) {
    [WawonaWaypipeRunner sharedRunner].delegate = self;
    self.sections = [self buildSections];
  }
  return self;
}
#else
- (instancetype)init {
  self = [super initWithStyle:UITableViewStyleInsetGrouped];
  if (self) {
    self.title = @"Settings";
    [WawonaWaypipeRunner sharedRunner].delegate = self;
    self.sections = [self buildSections];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(dismissSelf)];
  }
  return self;
}
#endif

#define ITEM(t, k, ty, def, d)                                                 \
  [WawonaSettingItem itemWithTitle:t key:k type:ty default:(def)desc:(d)]

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
  NSMutableArray *displayItems = [NSMutableArray arrayWithArray:@[
    ITEM(@"Force Server-Side Decorations", @"ForceServerSideDecorations",
         WSettingSwitch, @NO, @"Forces macOS-style window decorations."),
    ITEM(@"Auto Scale", @"AutoScale", WSettingSwitch, @NO,
         @"Matches macOS UI Scaling.")
  ]];

#if TARGET_OS_IPHONE
  // Respect Safe Area only makes sense on iOS (notch, Dynamic Island, etc.)
  [displayItems addObject:ITEM(@"Respect Safe Area", @"RespectSafeArea",
                               WSettingSwitch, @NO, @"Avoids notch areas.")];
#else
  // Show macOS Cursor option only on macOS
  [displayItems insertObject:ITEM(@"Show macOS Cursor", @"RenderMacOSPointer",
                                  WSettingSwitch, @NO,
                                  @"Toggles macOS cursor visibility.")
                     atIndex:1];
#endif

  display.items = displayItems;
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
  WawonaSettingItem *touchInputItem =
      ITEM(@"Touch Input Type", @"TouchInputType", WSettingPopup,
           @"Multi-Touch", @"Input method for touch interactions.");
  touchInputItem.options = @[ @"Multi-Touch", @"Trackpad" ];

  input.items = @[
    touchInputItem,
    ITEM(@"Swap CMD with ALT", @"SwapCmdWithAlt", WSettingSwitch, @NO,
         @"Swaps Command and Alt keys."),
    ITEM(@"Universal Clipboard", @"UniversalClipboard", WSettingSwitch, @YES,
         @"Syncs clipboard with macOS.")
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
    ITEM(@"Enable Vulkan Drivers", @"VulkanDriversEnabled", WSettingSwitch,
         @YES, @"Experimental Vulkan support."),
    ITEM(@"Enable DMABUF", @"DmabufEnabled", WSettingSwitch, @YES,
         @"Zero-copy texture sharing.")
  ];
  [sects addObject:graphics];

  // CONNECTION
  WawonaPreferencesSection *connection =
      [[WawonaPreferencesSection alloc] init];
  connection.title = @"Connection";
  connection.icon = @"network";
#if TARGET_OS_IPHONE
  connection.iconColor = [UIColor systemOrangeColor];
#else
  connection.iconColor = [NSColor systemOrangeColor];
#endif
  connection.items = @[
    ITEM(@"TCP Port", @"TCPListenerPort", WSettingNumber, @6000,
         @"Port for TCP listener."),
#if TARGET_OS_IPHONE
    ITEM(@"Socket Directory", @"WaylandSocketDir", WSettingInfo, @"/tmp",
         @"Directory for sockets (tap to copy).")
#else
    ITEM(@"Socket Directory", @"WaylandSocketDir", WSettingText,
         @"/tmp/wawona-501", @"Directory for Wayland sockets.")
#endif
  ];
  [sects addObject:connection];

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
    ITEM(@"Color Operations", @"ColorOperations", WSettingSwitch, @NO,
         @"Color profiles and HDR."),
    ITEM(@"Nested Compositors", @"NestedCompositorsSupport", WSettingSwitch,
         @YES, @"Support for nested compositors."),
    ITEM(@"Multiple Clients", @"MultipleClients", WSettingSwitch, @NO,
         @"Allow multiple clients."),
    ITEM(@"Enable Launcher", @"EnableLauncher", WSettingSwitch, @NO,
         @"Start the built-in Wayland Launcher.")
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

  __weak typeof(self) weakSelf = self;
  WawonaSettingItem *previewBtn =
      ITEM(@"Preview Command", @"WaypipePreview", WSettingButton, nil,
           @"View and copy the generated command.");
  previewBtn.actionBlock = ^{
    [weakSelf previewWaypipeCommand];
  };

  WawonaSettingItem *runBtn =
      ITEM(@"Run Waypipe", @"WaypipeRun", WSettingButton, nil,
           @"Launch waypipe with current settings.");
  runBtn.actionBlock = ^{
    [weakSelf runWaypipe];
  };

  WawonaSettingItem *compressItem =
      ITEM(@"Compression", @"WaypipeCompress", WSettingPopup, @"lz4",
           @"Compression method.");
  compressItem.options = @[ @"none", @"lz4", @"zstd" ];

  WawonaSettingItem *videoItem =
      ITEM(@"Video Codec", @"WaypipeVideo", WSettingPopup, @"none",
           @"Lossy video codec.");
  videoItem.options = @[ @"none", @"h264", @"vp9", @"av1" ];

  WawonaSettingItem *vEnc =
      ITEM(@"Encoding", @"WaypipeVideoEncoding", WSettingPopup, @"hw",
           @"Hardware vs Software.");
  vEnc.options = @[ @"hw", @"sw", @"hwenc", @"swenc" ];

  WawonaSettingItem *vDec =
      ITEM(@"Decoding", @"WaypipeVideoDecoding", WSettingPopup, @"hw",
           @"Hardware vs Software.");
  vDec.options = @[ @"hw", @"sw", @"hwdec", @"swdec" ];

  waypipe.items = @[
    ITEM(@"Waypipe Version", nil, WSettingInfo, [self getWaypipeVersion],
         @"Bundled waypipe version."),
    ITEM(@"Local IP", nil, WSettingInfo, [self localIPAddress], nil),
    ITEM(@"Display Number", @"WaylandDisplayNumber", WSettingNumber, @0,
         @"Display number for socket and waypipe (e.g., 0 = wayland-0)."),
    compressItem,
    ITEM(@"Comp. Level", @"WaypipeCompressLevel", WSettingNumber, @7,
         @"Zstd level (1-22)."),
    ITEM(@"Threads", @"WaypipeThreads", WSettingNumber, @0, @"0 = auto."),
    videoItem,
    vEnc,
    vDec,
    ITEM(@"Bits Per Frame", @"WaypipeVideoBpf", WSettingNumber, @"",
         @"Target bit rate per frame for video encoding. Recommended range: "
         @"1000-10000 bits per frame. Higher values provide better quality but "
         @"use more bandwidth. Leave empty for automatic bit rate."),
    ITEM(@"Use SSH Config", @"WaypipeUseSSHConfig", WSettingSwitch, @YES,
         @"Use SSH configuration from OpenSSH section."),
    ITEM(@"Remote Command", @"WaypipeRemoteCommand", WSettingText, @"",
         @"Command to run remotely."),
    ITEM(@"Debug Mode", @"WaypipeDebug", WSettingSwitch, @NO,
         @"Print debug logs."),
    ITEM(@"Disable GPU", @"WaypipeNoGpu", WSettingSwitch, @NO,
         @"Block GPU protocols."),
    ITEM(@"One-shot", @"WaypipeOneshot", WSettingSwitch, @NO,
         @"Exit when client disconnects."),
    ITEM(@"Unlink Socket", @"WaypipeUnlinkSocket", WSettingSwitch, @NO,
         @"Unlink socket on exit."),
    ITEM(@"Login Shell", @"WaypipeLoginShell", WSettingSwitch, @NO,
         @"Run in login shell."),
    ITEM(@"VSock", @"WaypipeVsock", WSettingSwitch, @NO, @"Use VSock."),
    ITEM(@"XWayland", @"WaypipeXwls", WSettingSwitch, @NO,
         @"Enable XWayland support."),
    ITEM(
        @"Title Prefix", @"WaypipeTitlePrefix", WSettingText, @"",
        @"Prefix added to window titles. Example: \"Remote:\" will show "
        @"windows as \"Remote: Application Name\". Leave empty for no prefix."),
    ITEM(@"Sec Context", @"WaypipeSecCtx", WSettingText, @"",
         @"SELinux security context for waypipe processes. This is a Linux "
         @"security feature that labels processes with security attributes "
         @"(e.g., \"system_u:system_r:waypipe_t:s0\"). Only needed if SELinux "
         @"is enabled on the remote system. Leave empty to use default "
         @"context."),
    previewBtn,
    runBtn
  ];
  [sects addObject:waypipe];

  // SSH (OpenSSH)
  WawonaPreferencesSection *ssh = [[WawonaPreferencesSection alloc] init];
  ssh.title = @"OpenSSH";
  ssh.icon = @"lock.shield";
#if TARGET_OS_IPHONE
  ssh.iconColor = [UIColor systemBlueColor];
#else
  ssh.iconColor = [NSColor systemBlueColor];
#endif

  WawonaSettingItem *sshAuthMethodItem =
      ITEM(@"Auth Method", @"SSHAuthMethod", WSettingPopup, @"Password",
           @"Authentication method.");
  sshAuthMethodItem.options = @[ @"Password", @"Public Key" ];

  WawonaSettingItem *sshPingBtn =
      ITEM(@"Ping Host", @"SSHPingHost", WSettingButton, nil,
           @"Test network connectivity to SSH host (no authentication).");
  sshPingBtn.actionBlock = ^{
    [weakSelf pingSSHHost];
  };

  WawonaSettingItem *sshTestBtn =
      ITEM(@"Test SSH Connection", @"SSHTestConnection", WSettingButton, nil,
           @"Test SSH connection with authentication (password or key).");
  sshTestBtn.actionBlock = ^{
    [weakSelf testSSHConnection];
  };

  // Build items list based on current auth method
  NSMutableArray *sshItems = [NSMutableArray array];

  // Version info
  [sshItems addObject:ITEM(@"OpenSSH Version", nil, WSettingInfo,
                           [self getOpenSSHVersion], @"Bundled SSH version.")];
#if !TARGET_OS_IPHONE
  [sshItems addObject:ITEM(@"sshpass Version", nil, WSettingInfo,
                           [self getSshpassVersion],
                           @"For non-interactive password auth.")];
#endif

  // Basic connection settings (always shown)
  [sshItems addObject:ITEM(@"SSH Host", @"SSHHost", WSettingText, @"",
                           @"Remote host address.")];
  [sshItems addObject:ITEM(@"SSH User", @"SSHUser", WSettingText, @"",
                           @"SSH username.")];
  [sshItems addObject:sshAuthMethodItem];

  // Get current auth method to show appropriate nested options
  NSInteger authMethod =
      [[NSUserDefaults standardUserDefaults] integerForKey:@"SSHAuthMethod"];

  if (authMethod == 0) {
    // Password authentication
    [sshItems addObject:ITEM(@"Password", @"SSHPassword", WSettingPassword, @"",
                             @"SSH password (stored securely in Keychain).")];
  } else {
    // Public Key authentication
#if TARGET_OS_IPHONE
    // iOS/Android: Bundled OpenSSH - use key management instead of path
    WawonaSettingItem *keyInfoItem =
        ITEM(@"SSH Key", @"SSHKeyInfo", WSettingInfo, @"",
             @"Tap to view or manage SSH keys.");
    // Get the public key fingerprint or status
    NSString *keyStatus = @"Not configured";
    NSString *keyPath =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"SSHKeyPath"];
    if (keyPath.length > 0) {
      keyStatus = [keyPath lastPathComponent];
    }
    keyInfoItem.defaultValue = keyStatus;
    [sshItems addObject:keyInfoItem];

    // Still allow setting a key path for advanced users (e.g., imported keys)
    [sshItems addObject:ITEM(@"Key Path", @"SSHKeyPath", WSettingText, @"",
                             @"Path to private key (relative to app documents "
                             @"or absolute).")];
#else
    // macOS: Use system SSH - allow key path
    [sshItems
        addObject:ITEM(@"Key Path", @"SSHKeyPath", WSettingText,
                       @"~/.ssh/id_ed25519",
                       @"Path to private key file (e.g., ~/.ssh/id_ed25519).")];
#endif
    // Key passphrase (for encrypted keys)
    [sshItems
        addObject:
            ITEM(@"Key Passphrase", @"SSHKeyPassphrase", WSettingPassword, @"",
                 @"Passphrase for encrypted private key (stored securely).")];
  }

  // Action buttons (always shown)
  [sshItems addObject:sshPingBtn];
  [sshItems addObject:sshTestBtn];

  ssh.items = sshItems;
  [sects addObject:ssh];

  // ABOUT
  WawonaPreferencesSection *about = [[WawonaPreferencesSection alloc] init];
  about.title = @"About";
  about.icon = @"info.circle";
#if TARGET_OS_IPHONE
  about.iconColor = [UIColor systemPurpleColor];
#else
  about.iconColor = [NSColor systemPurpleColor];
#endif

  WawonaSettingItem *headerItem =
      ITEM(@"Wawona", nil, WSettingHeader, nil,
           @"A Wayland Compositor for macOS, iOS & Android");
  headerItem.imageURL = @"./gallery/Wawona-iOS-Dark-1024x1024@1x.png";

  WawonaSettingItem *sourceItem =
      ITEM(@"Source Code", nil, WSettingLink, nil, @"View on GitHub");
  sourceItem.urlString = @"https://github.com/aspauldingcode/Wawona";
  sourceItem.iconURL = @"https://github.githubassets.com/images/modules/logos_"
                       @"page/GitHub-Mark.png";

  WawonaSettingItem *donateItem =
      ITEM(@"GitHub Sponsors", nil, WSettingLink, nil, @"Sponsor on GitHub");
  donateItem.urlString = @"https://github.com/sponsors/aspauldingcode";
  donateItem.iconURL = @"https://encrypted-tbn0.gstatic.com/images?q=tbn:"
                       @"ANd9GcRp_gdQoe-SxKGw3IvS-1G_JPsMY70HkqxAPg&s";

  WawonaSettingItem *authorItem =
      ITEM(@"Author", nil, WSettingInfo, @"Alex Spaulding", nil);

  WawonaSettingItem *githubItem =
      ITEM(@"GitHub", nil, WSettingLink, nil, @"View GitHub Profile");
  githubItem.urlString = @"https://github.com/aspauldingcode";
  githubItem.iconURL = @"https://github.githubassets.com/images/modules/logos_"
                       @"page/GitHub-Mark.png";

  WawonaSettingItem *xItem = ITEM(@"X", nil, WSettingLink, nil, @"Follow on X");
  xItem.urlString = @"https://x.com/aspauldingcode";
  xItem.iconURL = @"https://x.com/favicon.ico";

  WawonaSettingItem *linkedinItem =
      ITEM(@"LinkedIn", nil, WSettingLink, nil, @"Connect on LinkedIn");
  linkedinItem.urlString = @"https://www.linkedin.com/in/aspauldingcode/";
  linkedinItem.iconURL = @"https://upload.wikimedia.org/wikipedia/commons/c/"
                         @"ca/LinkedIn_logo_initials.png";

  WawonaSettingItem *websiteItem =
      ITEM(@"Portfolio", nil, WSettingLink, nil, @"Visit Website");
  websiteItem.urlString = @"https://aspauldingcode.com";
  websiteItem.iconURL = @"https://aspauldingcode.com/favicon.ico";

  WawonaSettingItem *kofiItem =
      ITEM(@"Ko-fi", nil, WSettingLink, nil, @"Buy me a coffee ☕");
  kofiItem.urlString = @"https://ko-fi.com/aspauldingcode";
  kofiItem.iconURL = @"https://ko-fi.com/android-icon-192x192.png";

  about.items = @[
    headerItem,
    ITEM(@"Version", nil, WSettingInfo, [self getWawonaVersion], nil),
    ITEM(@"Platform", nil, WSettingInfo,
#if TARGET_OS_IPHONE
         @"iOS / iPadOS",
#else
         @"macOS",
#endif
         nil),
    authorItem, websiteItem, githubItem, xItem, linkedinItem, kofiItem,
    donateItem
  ];
  [sects addObject:about];

  // DEPENDENCIES
  WawonaPreferencesSection *deps = [[WawonaPreferencesSection alloc] init];
  deps.title = @"Dependencies";
  deps.icon = @"shippingbox";
#if TARGET_OS_IPHONE
  deps.iconColor = [UIColor systemBrownColor];
#else
  deps.iconColor = [NSColor systemBrownColor];
#endif

  NSMutableArray *depItems = [NSMutableArray array];

  // Core dependencies
  [depItems
      addObject:ITEM(@"Waypipe", nil, WSettingInfo, [self getWaypipeVersion],
                     @"Remote Wayland display proxy")];
  [depItems addObject:ITEM(@"OpenSSH", nil, WSettingInfo,
                           [self getOpenSSHVersion], @"Secure shell client")];
#if !TARGET_OS_IPHONE
  [depItems
      addObject:ITEM(@"sshpass", nil, WSettingInfo, [self getSshpassVersion],
                     @"Non-interactive SSH password auth")];
#endif
  [depItems
      addObject:ITEM(@"libwayland", nil, WSettingInfo,
                     [self getLibwaylandVersion], @"Wayland protocol library")];
  [depItems
      addObject:ITEM(@"xkbcommon", nil, WSettingInfo,
                     [self getXkbcommonVersion], @"Keyboard handling library")];

  // Compression
  [depItems addObject:ITEM(@"LZ4", nil, WSettingInfo, [self getLz4Version],
                           @"Fast compression algorithm")];
  [depItems addObject:ITEM(@"Zstd", nil, WSettingInfo, [self getZstdVersion],
                           @"Zstandard compression")];

  // Other libraries
  [depItems
      addObject:ITEM(@"libffi", nil, WSettingInfo, [self getLibffiVersion],
                     @"Foreign function interface")];

#if TARGET_OS_IPHONE
  // iOS-specific dependencies
  [depItems addObject:ITEM(@"kosmickrisp", nil, WSettingInfo,
                           [self getKosmickrispVersion],
                           @"Mesa Vulkan driver for iOS")];
  [depItems
      addObject:ITEM(@"epoll-shim", nil, WSettingInfo,
                     [self getEpollShimVersion], @"epoll compatibility layer")];
#endif

  deps.items = depItems;
  [sects addObject:deps];

  return sects;
}

- (NSString *)findWaypipeBinary {
  return [[WawonaWaypipeRunner sharedRunner] findWaypipeBinary];
}

- (NSString *)localIPAddress {
  NSString *address = @"Not available";
  struct ifaddrs *interfaces = NULL;
  struct ifaddrs *temp_addr = NULL;
  int success = 0;

  // Retrieve the current interfaces - returns 0 on success
  success = getifaddrs(&interfaces);
  if (success == 0) {
    // Loop through linked list of interfaces
    temp_addr = interfaces;
    while (temp_addr != NULL) {
      if (temp_addr->ifa_addr->sa_family == AF_INET) {
        // Check if interface is en0 (WiFi) or en1 (Ethernet) or similar
        NSString *ifname = [NSString stringWithUTF8String:temp_addr->ifa_name];
        if ([ifname hasPrefix:@"en"] || [ifname hasPrefix:@"eth"]) {
          // Get NSString from C String
          char *ipCString =
              inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr);
          NSString *ipString = [NSString stringWithUTF8String:ipCString];

          // Skip localhost
          if (![ipString isEqualToString:@"127.0.0.1"]) {
            address = ipString;
            break;
          }
        }
      }
      temp_addr = temp_addr->ifa_next;
    }
  }

  // Free memory
  freeifaddrs(interfaces);
  return address;
}

- (NSString *)cleanVersion:(NSString *)raw {
  if (!raw || raw.length == 0)
    return @"v0.0.0";

  NSMutableString *clean = [NSMutableString stringWithString:@"v"];
  NSCharacterSet *digitsAndDots =
      [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];

  // Find numeric content
  BOOL foundStart = NO;
  for (NSUInteger i = 0; i < raw.length; i++) {
    unichar c = [raw characterAtIndex:i];
    if ([digitsAndDots characterIsMember:c]) {
      [clean appendFormat:@"%C", c];
      foundStart = YES;
    } else if (foundStart) {
      // Stop at first non-numeric char after finding some numbers
      break;
    }
  }

  if (clean.length == 1)
    return @"v0.0.0";
  return clean;
}

- (NSString *)getOpenSSHVersion {
  NSString *sshPath = nil;
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
  NSFileManager *fm = [NSFileManager defaultManager];

#if TARGET_OS_IPHONE
  // iOS: Check bundled ssh
  NSArray *candidates = @[
    [bundlePath stringByAppendingPathComponent:@"bin/ssh"],
    [bundlePath stringByAppendingPathComponent:@"ssh"]
  ];
  for (NSString *path in candidates) {
    if ([fm fileExistsAtPath:path]) {
      sshPath = path;
      break;
    }
  }
  if (!sshPath)
    return @"Not bundled";
  // On iOS, we can't easily run ssh -V, so return "Bundled" indicator
  return @"Bundled (patched)";
#else
  // macOS: Use system ssh and run ssh -V
  sshPath = @"/usr/bin/ssh";
  if (![fm fileExistsAtPath:sshPath])
    return @"Not found";

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = sshPath;
  task.arguments = @[ @"-V" ];

  NSPipe *pipe = [NSPipe pipe];
  task.standardError = pipe; // ssh -V outputs to stderr

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Parse "OpenSSH_X.Xp2, ..." to just "OpenSSH X.X"
    if ([output hasPrefix:@"OpenSSH_"]) {
      NSRange commaRange = [output rangeOfString:@","];
      if (commaRange.location != NSNotFound) {
        output = [output substringToIndex:commaRange.location];
      }

      // Preserve "OpenSSH" at the start
      NSString *versionPart =
          [output substringFromIndex:8]; // Length of "OpenSSH_"
      versionPart = [versionPart stringByReplacingOccurrencesOfString:@"p"
                                                           withString:@"."];
      versionPart = [versionPart stringByReplacingOccurrencesOfString:@"_"
                                                           withString:@" "];

      NSString *finalVer =
          [versionPart stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      return [self cleanVersion:finalVer];
    }
    return [self cleanVersion:output];
  } @catch (NSException *e) {
    return @"v0.0.0";
  }
#endif
}

- (NSString *)getWaypipeVersion {
#if TARGET_OS_IPHONE
  return @"Bundled";
#else
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    NSString *ver = [NSString stringWithUTF8String:WAWONA_WAYPIPE_VERSION];
    return [self cleanVersion:ver];
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = waypipePath;
  task.arguments = @[ @"--version" ];

  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Parse "waypipe X.X.X" or similar
    output = [output
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (output.length > 0) {
      // If it contains "waypipe", extract version number
      NSRange waypipeRange =
          [output rangeOfString:@"waypipe" options:NSCaseInsensitiveSearch];
      if (waypipeRange.location != NSNotFound) {
        NSString *afterWaypipe = [output
            substringFromIndex:waypipeRange.location + waypipeRange.length];
        afterWaypipe = [afterWaypipe
            stringByTrimmingCharactersInSet:[NSCharacterSet
                                                whitespaceCharacterSet]];
        // Take first word (version number)
        NSArray *parts = [afterWaypipe
            componentsSeparatedByCharactersInSet:[NSCharacterSet
                                                     whitespaceCharacterSet]];
        if (parts.count > 0 && [parts[0] length] > 0) {
          return [self cleanVersion:parts[0]];
        }
      }
      return output;
    }
    return @"v0.0.0";
  } @catch (NSException *e) {
    return @"v0.0.0";
  }
#endif
}

#if !TARGET_OS_IPHONE
- (NSString *)getSshpassVersion {
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
  NSString *execPath = [[NSBundle mainBundle] executablePath];
  NSString *execDir = [execPath stringByDeletingLastPathComponent];
  NSFileManager *fm = [NSFileManager defaultManager];

  NSArray *candidates = @[
    [bundlePath stringByAppendingPathComponent:@"Contents/MacOS/sshpass"],
    [bundlePath
        stringByAppendingPathComponent:@"Contents/Resources/bin/sshpass"],
    [execDir stringByAppendingPathComponent:@"sshpass"]
  ];

  NSString *sshpassPath = nil;
  for (NSString *path in candidates) {
    if ([fm isExecutableFileAtPath:path]) {
      sshpassPath = path;
      break;
    }
  }

  if (!sshpassPath) {
    NSString *ver = [NSString stringWithUTF8String:WAWONA_SSHPASS_VERSION];
    return [self cleanVersion:ver];
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = sshpassPath;
  task.arguments = @[ @"-V" ];

  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Parse "sshpass X.X" or similar
    output = [output
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if ([output containsString:@"sshpass"]) {
      // Extract version number
      NSRange spaceRange = [output rangeOfString:@" "];
      if (spaceRange.location != NSNotFound) {
        NSString *version = [output substringFromIndex:spaceRange.location + 1];
        version =
            [version stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Take first word/line
        NSRange newlineRange = [version
            rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
        if (newlineRange.location != NSNotFound) {
          version = [version substringToIndex:newlineRange.location];
        }
        return [self cleanVersion:version];
      }
    }
    return [self cleanVersion:output];
  } @catch (NSException *e) {
    return @"v0.0.0";
  }
}
#endif

- (NSString *)getWawonaVersion {
  // Use Nix-sourced version if available
  NSString *version = @WAWONA_VERSION;

  // If macro is default or unknown, fall back to bundle info
  if ([version isEqualToString:@"0.0.0-unknown"] ||
      [version containsString:@"unknown"]) {
    version = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  }

  // Ensure 'v' prefix
  if (version && ![version hasPrefix:@"v"]) {
    version = [@"v" stringByAppendingString:version];
  }

  return version ?: @"v0.0.0";
}

- (NSString *)getLibffiVersion {
  return
      [self cleanVersion:[NSString stringWithUTF8String:WAWONA_LIBFFI_VERSION]];
}

- (NSString *)getLz4Version {
  return [self cleanVersion:[NSString stringWithUTF8String:WAWONA_LZ4_VERSION]];
}

- (NSString *)getZstdVersion {
  return
      [self cleanVersion:[NSString stringWithUTF8String:WAWONA_ZSTD_VERSION]];
}

- (NSString *)getXkbcommonVersion {
  return [self
      cleanVersion:[NSString stringWithUTF8String:WAWONA_XKBCOMMON_VERSION]];
}

- (NSString *)getLibwaylandVersion {
  return [self
      cleanVersion:[NSString stringWithUTF8String:WAWONA_WAYLAND_VERSION]];
}

#if TARGET_OS_IPHONE
- (NSString *)getKosmickrispVersion {
  // kosmickrisp (Mesa/Vulkan) is bundled for iOS
  return @"Bundled";
}

- (NSString *)getEpollShimVersion {
  return @"Bundled";
}
#endif

- (void)openURL:(NSString *)urlString {
#if TARGET_OS_IPHONE
  NSURL *url = [NSURL URLWithString:urlString];
  if (url) {
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:nil];
  }
#else
  NSURL *url = [NSURL URLWithString:urlString];
  if (url) {
    [[NSWorkspace sharedWorkspace] openURL:url];
  }
#endif
}

- (void)runWaypipe {
  // Save any pending text field changes first (macOS only - iOS uses alerts)
#if !TARGET_OS_IPHONE
  // On macOS, text fields might have unsaved changes
  // Force end editing to commit any pending changes
  [self.window makeFirstResponder:nil];
#endif

  // Ensure all settings are saved before running waypipe
  [[NSUserDefaults standardUserDefaults] synchronize];

  // Initialize status text
  if (!self.waypipeStatusText) {
    self.waypipeStatusText = [NSMutableString string];
  }
  [self.waypipeStatusText setString:@"Starting waypipe...\n"];
  self.waypipeMarkedConnected = NO;

#if TARGET_OS_IPHONE
  if (self.waypipeStatusAlert) {
    [self.waypipeStatusAlert dismissViewControllerAnimated:YES completion:nil];
    self.waypipeStatusAlert = nil;
  }

  UIAlertController *statusAlert =
      [UIAlertController alertControllerWithTitle:@"Waypipe"
                                          message:self.waypipeStatusText
                                   preferredStyle:UIAlertControllerStyleAlert];
  __weak typeof(self) weakSelf = self;
  [statusAlert addAction:[UIAlertAction
                             actionWithTitle:@"Copy Log"
                                       style:UIAlertActionStyleDefault
                                     handler:^(__unused UIAlertAction *action) {
                                       [UIPasteboard generalPasteboard].string =
                                           weakSelf.waypipeStatusText ?: @"";
                                     }]];
  [statusAlert addAction:[UIAlertAction
                             actionWithTitle:@"Dismiss"
                                       style:UIAlertActionStyleCancel
                                     handler:^(__unused UIAlertAction *action) {
                                       weakSelf.waypipeStatusAlert = nil;
                                     }]];
  self.waypipeStatusAlert = statusAlert;
  [self presentViewController:statusAlert animated:YES completion:nil];
#else
  // macOS: Show status panel
  [self showWaypipeStatusPanel];
#endif

  // Launch waypipe
  [[WawonaWaypipeRunner sharedRunner]
      launchWaypipe:[WawonaPreferencesManager sharedManager]];

  // Note: We do NOT automatically dismiss the settings view here.
  // Waypipe launch might require user interaction (e.g., password prompt)
  // or show errors that the user needs to see.
  // The user can manually dismiss the settings when they are ready.
}

#if !TARGET_OS_IPHONE
- (void)showWaypipeStatusPanel {
  // Close existing panel if any
  if (self.waypipeStatusPanel) {
    [self.waypipeStatusPanel close];
    self.waypipeStatusPanel = nil;
  }

  // Create a floating panel for waypipe status
  NSRect panelRect = NSMakeRect(0, 0, 500, 350);
  NSPanel *panel = [[NSPanel alloc]
      initWithContentRect:panelRect
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskUtilityWindow
                  backing:NSBackingStoreBuffered
                    defer:NO];
  panel.title = @"Waypipe Status";
  panel.floatingPanel = YES;
  panel.becomesKeyOnlyIfNeeded = YES;
  panel.level = NSFloatingWindowLevel;
  panel.releasedWhenClosed = NO;

  // Create scroll view for text
  NSScrollView *scrollView =
      [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, 480, 290)];
  scrollView.hasVerticalScroller = YES;
  scrollView.hasHorizontalScroller = NO;
  scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scrollView.borderType = NSBezelBorder;

  // Create text view
  NSTextView *textView =
      [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 480, 290)];
  textView.editable = NO;
  textView.selectable = YES;
  textView.font =
      [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
  textView.backgroundColor = [NSColor colorWithCalibratedWhite:0.1 alpha:1.0];
  textView.textColor = [NSColor colorWithCalibratedRed:0.0
                                                 green:1.0
                                                  blue:0.0
                                                 alpha:1.0]; // Terminal green
  textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [textView.textStorage
      setAttributedString:[[NSAttributedString alloc]
                              initWithString:self.waypipeStatusText
                                  attributes:@{
                                    NSFontAttributeName : textView.font,
                                    NSForegroundColorAttributeName :
                                        textView.textColor
                                  }]];

  scrollView.documentView = textView;
  [panel.contentView addSubview:scrollView];
  self.waypipeStatusTextView = textView;

  // Create buttons at bottom
  NSButton *copyButton = [NSButton buttonWithTitle:@"Copy Log"
                                            target:self
                                            action:@selector(copyWaypipeLog:)];
  copyButton.frame = NSMakeRect(10, 10, 100, 30);
  copyButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
  [panel.contentView addSubview:copyButton];

  NSButton *stopButton = [NSButton buttonWithTitle:@"Stop Waypipe"
                                            target:self
                                            action:@selector(stopWaypipe:)];
  stopButton.frame = NSMakeRect(120, 10, 120, 30);
  stopButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
  [panel.contentView addSubview:stopButton];
  self.waypipeStopButton = stopButton;

  NSButton *closeButton =
      [NSButton buttonWithTitle:@"Close"
                         target:self
                         action:@selector(closeWaypipePanel:)];
  closeButton.frame = NSMakeRect(390, 10, 100, 30);
  closeButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [panel.contentView addSubview:closeButton];

  self.waypipeStatusPanel = panel;

  // Position near settings window
  if (self.window) {
    NSRect settingsFrame = self.window.frame;
    NSRect panelFrame = panel.frame;
    panelFrame.origin.x = NSMaxX(settingsFrame) + 20;
    panelFrame.origin.y = NSMinY(settingsFrame);
    [panel setFrame:panelFrame display:YES];
  } else {
    [panel center];
  }

  [panel makeKeyAndOrderFront:nil];
}

- (void)updateWaypipeStatusPanel {
  if (self.waypipeStatusTextView && self.waypipeStatusText) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSDictionary *attrs = @{
        NSFontAttributeName : self.waypipeStatusTextView.font
            ?: [NSFont monospacedSystemFontOfSize:11
                                           weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : self.waypipeStatusTextView.textColor
            ?: [NSColor greenColor]
      };
      [self.waypipeStatusTextView.textStorage
          setAttributedString:[[NSAttributedString alloc]
                                  initWithString:self.waypipeStatusText
                                      attributes:attrs]];
      // Auto-scroll to bottom
      [self.waypipeStatusTextView
          scrollRangeToVisible:NSMakeRange(self.waypipeStatusText.length, 0)];

      // Update panel title based on connection status
      if (self.waypipeMarkedConnected && self.waypipeStatusPanel) {
        self.waypipeStatusPanel.title = @"Waypipe - Connected";
      }
    });
  }
}

- (void)copyWaypipeLog:(id)sender {
  if (self.waypipeStatusText) {
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:self.waypipeStatusText
                                        forType:NSPasteboardTypeString];
  }
}

- (void)stopWaypipe:(id)sender {
  [[WawonaWaypipeRunner sharedRunner] stopWaypipe];
  [self.waypipeStatusText appendString:@"\n[User requested stop]\n"];
  [self updateWaypipeStatusPanel];
}

- (void)closeWaypipePanel:(id)sender {
  if (self.waypipeStatusPanel) {
    [self.waypipeStatusPanel close];
    self.waypipeStatusPanel = nil;
  }
}
#endif

- (void)testSSHConnection {
  WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
  NSString *host = prefs.sshHost;
  NSString *user = prefs.sshUser;

  WLog(@"SSH", @"Attempting to test SSH connection to: '%@%@'",
       user ?: @"(nil)", host ?: @"(nil)");

  if (!host || host.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No Host Specified"
                         message:@"Please enter an SSH host address first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No Host Specified";
    alert.informativeText = @"Please enter an SSH host address first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

  if (!user || user.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No User Specified"
                         message:@"Please enter an SSH username first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No User Specified";
    alert.informativeText = @"Please enter an SSH username first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

#if TARGET_OS_IPHONE
  UIAlertController *progressAlert = [UIAlertController
      alertControllerWithTitle:@"Testing SSH Connection"
                       message:[NSString
                                   stringWithFormat:@"Connecting to %@@%@...",
                                                    user, host]
                preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:progressAlert animated:YES completion:nil];

  // Find SSH dylib - use ssh.dylib for dlopen (more reliable on iOS than
  // posix_spawn)
  NSString *sshPath = [[[NSBundle mainBundle] bundlePath]
      stringByAppendingPathComponent:@"bin/ssh.dylib"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:sshPath]) {
    // Fall back to ssh executable if dylib doesn't exist
    sshPath = [[NSBundle mainBundle] pathForResource:@"ssh" ofType:nil];
    if (!sshPath) {
      sshPath = [[[NSBundle mainBundle] bundlePath]
          stringByAppendingPathComponent:@"bin/ssh"];
    }
  }

  if (!sshPath || ![[NSFileManager defaultManager] fileExistsAtPath:sshPath]) {
    [progressAlert
        dismissViewControllerAnimated:YES
                           completion:^{
                             UIAlertController *errorAlert = [UIAlertController
                                 alertControllerWithTitle:
                                     @"SSH Binary Not Found"
                                                  message:
                                                      @"SSH binary not found "
                                                      @"in app bundle."
                                           preferredStyle:
                                               UIAlertControllerStyleAlert];
                             [errorAlert
                                 addAction:
                                     [UIAlertAction
                                         actionWithTitle:@"OK"
                                                   style:
                                                       UIAlertActionStyleDefault
                                                 handler:nil]];
                             [self presentViewController:errorAlert
                                                animated:YES
                                              completion:nil];
                           }];
    return;
  }

  WLog(@"SSH", @"Using SSH at: %@", sshPath);

  // Build SSH command for connection test
  NSMutableArray *sshArgs = [NSMutableArray array];
  [sshArgs addObject:@"-vvv"]; // Verbose for debugging
  [sshArgs addObject:@"-o"];
  [sshArgs addObject:@"ConnectTimeout=10"];
  [sshArgs addObject:@"-o"];
  [sshArgs addObject:@"StrictHostKeyChecking=no"];
  [sshArgs addObject:@"-o"];
  [sshArgs addObject:@"UserKnownHostsFile=/dev/null"];
  [sshArgs addObject:@"-o"];
  [sshArgs addObject:@"NumberOfPasswordPrompts=1"];

  // Add authentication method specific options
  if (prefs.sshAuthMethod == 1) { // Public Key
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"PreferredAuthentications=publickey"];
    if (prefs.sshKeyPath.length > 0) {
      [sshArgs addObject:@"-i"];
      [sshArgs addObject:prefs.sshKeyPath];
    }
  } else { // Password auth
    [sshArgs addObject:@"-o"];
    [sshArgs
        addObject:@"PreferredAuthentications=password,keyboard-interactive"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"PubkeyAuthentication=no"];
  }

  [sshArgs addObject:@"-4"]; // IPv4 only for faster connection

  NSString *target = [NSString stringWithFormat:@"%@@%@", user, host];
  [sshArgs addObject:target];
  [sshArgs addObject:@"uname -a"];

  // Set up environment with password if needed
  // Our patched iOS SSH reads password from SSH_ASKPASS_PASSWORD or SSHPASS env
  // vars
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy]
          ?: [NSMutableDictionary dictionary];
  if (prefs.sshAuthMethod == 0 &&
      prefs.sshPassword.length > 0) { // Password auth
    env[@"SSH_ASKPASS_PASSWORD"] = prefs.sshPassword;
    env[@"SSHPASS"] = prefs.sshPassword;
    env[@"WAWONA_SSH_PASSWORD"] = prefs.sshPassword;
    WLog(@"SSH", @"Password set in environment (length=%lu)",
         (unsigned long)prefs.sshPassword.length);
  }

#if 0 // HIAHKernel upstream is broken - disabled for now
  // Use HIAHKernel to spawn SSH, then monitor for completion (iOS only)
  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  __block pid_t testPid = -1;
  __block NSUUID *testRequestId = nil;

  // Set up output handler to capture SSH output
  // Note: kernel.onOutput passes PID 0 for all output, so we capture everything
  // during the test and filter by content instead
  void (^originalOnOutput)(pid_t, NSString *) = kernel.onOutput;
  __block NSMutableString *sshOutput = [NSMutableString string];
  kernel.onOutput = ^(pid_t pid, NSString *output) {
    // Capture all output - we're running a single SSH test
    @synchronized(sshOutput) {
      [sshOutput appendString:output];
    }
    if (originalOnOutput) {
      originalOnOutput(pid, output);
    }
  };

  [kernel
      spawnVirtualProcessWithPath:sshPath
                        arguments:sshArgs
                      environment:env
                       completion:^(pid_t pid, NSError *_Nullable error) {
                         if (error) {
                           kernel.onOutput = originalOnOutput;
                           dispatch_async(dispatch_get_main_queue(), ^{
                             [progressAlert
                                 dismissViewControllerAnimated:YES
                                                    completion:^{
                                                      UIAlertController
  *errorAlert = [UIAlertController alertControllerWithTitle:
                                                              @"SSH Spawn "
                                                              @"Failed"
                                                                           message:
                                                                               [NSString
                                                                                   stringWithFormat:
                                                                                       @"Failed to spawn SSH process: %@",
                                                                                       error
                                                                                           .localizedDescription]
                                                                    preferredStyle:
                                                                        UIAlertControllerStyleAlert];
                                                      [errorAlert
                                                          addAction:
                                                              [UIAlertAction
                                                                  actionWithTitle:
                                                                      @"OK"
                                                                            style:
                                                                                UIAlertActionStyleDefault
                                                                          handler:
                                                                              nil]];
                                                      [self
                                                          presentViewController:
                                                              errorAlert
                                                                       animated:
                                                                           YES
                                                                     completion:
                                                                         nil];
                                                    }];
                           });
                           return;
                         }

                         testPid = pid;
                         WLog(@"SSH", @"SSH spawned with PID: %d, ",
                               @"monitoring for completion via output...",
                               pid);

                         // Monitor process completion via output patterns
                         // instead of waitpid Extension processes are not
                         // children of this process, so waitpid doesn't work
                         dispatch_async(
                             dispatch_get_global_queue(
                                 DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                             ^{
                               int exitCode = -1;
                               BOOL found = NO;

                               NSDate *startTime = [NSDate date];
                               NSTimeInterval timeout =
                                   15.0; // 15 second timeout

                               while (!found &&
                                      [[NSDate date]
                                          timeIntervalSinceDate:startTime] <
                                          timeout) {
                                 // Check output for completion indicators
                                 @synchronized(sshOutput) {
                                   // Check for success - uname -a outputs
                                   // kernel name which typically starts with
                                   // Linux/Darwin/etc Look for patterns that
                                   // indicate successful uname output
                                   if ([sshOutput containsString:@"Linux "] ||
                                       [sshOutput containsString:@"Darwin "] ||
                                       [sshOutput containsString:@"FreeBSD "] ||
                                       [sshOutput containsString:
                                                      @"#"] || // kernel version
                                                               // usually has #
                                       ([sshOutput containsString:@"@"] &&
                                        [sshOutput containsString:@"x86_64"]) ||
                                       ([sshOutput containsString:@"@"] &&
                                        [sshOutput
                                            containsString:@"aarch64"]) ||
                                       ([sshOutput containsString:@"@"] &&
                                        [sshOutput containsString:@"arm64"])) {
                                     exitCode = 0;
                                     found = YES;
                                     WLog(
                                         @"SSH", @"Detected uname output in "
                                         @"SSH output");
                                     break;
                                   }

                                   // Check for ssh_main exit message from our
                                   // patched OpenSSH
                                   NSRange exitRange = [sshOutput
                                       rangeOfString:
                                           @"[ssh_main] SSH exited with code "];
                                   if (exitRange.location != NSNotFound) {
                                     NSString *afterExit = [sshOutput
                                         substringFromIndex:exitRange.location +
                                                            exitRange.length];
                                     NSScanner *scanner = [NSScanner
                                         scannerWithString:afterExit];
                                     int parsedCode = 0;
                                     if ([scanner scanInt:&parsedCode]) {
                                       exitCode = parsedCode;
                                       found = YES;
                                       WLog(
                                           @"SSH", @"Detected ssh_main exit "
                                           @"code: %d",
                                           exitCode);
                                       break;
                                     }
                                   }

                                   // Check for authentication failure
                                   if ([sshOutput containsString:
                                                      @"Permission denied"]) {
                                     exitCode = 255;
                                     found = YES;
                                     WLog(@"SSH", @"Detected permission "
                                           @"denied");
                                     break;
                                   }

                                   // Check for connection refused
                                   if ([sshOutput containsString:
                                                      @"Connection refused"] ||
                                       [sshOutput
                                           containsString:
                                               @"Connection timed out"]) {
                                     exitCode = 255;
                                     found = YES;
                                     WLog(@"SSH", @"Detected connection "
                                           @"failure");
                                     break;
                                   }
                                 }

                                 // Also check kernel's process table
                                 // HIAHKernel doesn't expose process table
                                 // publicly currently So we rely on output
                                 // parsing
                                 /*
                                 id proc = [kernel
                                 performSelector:@selector(processForPID:)
                                 withObject:@(pid)]; if (proc && [proc
                                 respondsToSelector:@selector(isExited)] &&
                                 [proc isExited]) { exitCode = [[proc
                                  valueForKey:@"exitCode"] intValue];
                                 found = YES;
                                 WLog(@"SSH", @"Process marked as exited in "
                                              @"kernel with code: %d",
                                      exitCode);
                                   break;
                                 }
                                 */

  usleep(100000); // Sleep 100ms between checks
}

kernel.onOutput = originalOnOutput;

dispatch_async(dispatch_get_main_queue(), ^{
  [progressAlert
      dismissViewControllerAnimated:YES
                         completion:^{
                            if (!found) {
                              UIAlertController *errorAlert = [UIAlertController
                                  alertControllerWithTitle:@"SSH Connection "
                                                           @"Timeout"
                                                   message:
                                                       [NSString
                                                           stringWithFormat:
                                                               @"SSH connection "
                                                               @"test timed out "
                                                               @"after 10 "
                                                               @"seconds."
                                                               @"\n\nPID: "
                                                               @"%d\n\nThis may "
                                                               @"indicate:\n- "
                                                               @"Network "
                                                               @"connectivity "
                                                               @"issues\n- SSH "
                                                               @"server not "
                                                               @"responding\n- "
                                                               @"Authentication "
                                                               @"hanging",
                                                               pid]
                                            preferredStyle:
                                                UIAlertControllerStyleAlert];
                             [errorAlert
                                 addAction:
                                     [UIAlertAction
                                         actionWithTitle:@"OK"
                                                   style:
                                                       UIAlertActionStyleDefault
                                                 handler:nil]];
                             [self presentViewController:errorAlert
                                                animated:YES
                                              completion:nil];
                           } else if (exitCode == 0) {
                             // Extract
                             // uname
                             // output
                             // from the
                             // captured
                             // output
                             // (filter
                             // out debug
                             // lines)
                             NSString *unameOutput = @"";
                             NSArray *outputLines =
                                 [sshOutput componentsSeparatedByString:@"\n"];
                             for (NSString *line in outputLines) {
                               // uname
                               // output
                               // typically
                               // contains
                               // kernel
                               // info -
                               // look for
                               // lines
                               // with OS
                               // names
                               if ([line containsString:@"Linux "] ||
                                   [line containsString:@"Darwin "] ||
                                   [line containsString:@"FreeBSD "] ||
                                   [line containsString:@"#"]) {
                                 if (![line hasPrefix:@"debug"] &&
                                     ![line hasPrefix:@"["]) {
                                   unameOutput = [line
                                       stringByTrimmingCharactersInSet:
                                           [NSCharacterSet
                                               whitespaceAndNewlineCharacterSet]];
                                   break;
                                 }
                               }
                             }

                             NSString *message;
                             if (unameOutput.length > 0) {
                               message =
                                   [NSString stringWithFormat:
                                                 @"Connected to "
                                                 @"%@@%@\n\nRemote system:\n%@",
                                                 user, host, unameOutput];
                             } else {
                               message =
                                   [NSString stringWithFormat:
                                                 @"Successfully connected and "
                                                 @"authenticated to %@@%@",
                                                 user, host];
                             }

                             UIAlertController *successAlert =
                                 [UIAlertController
                                     alertControllerWithTitle:@"SS"
                                                              @"H "
                                                              @"Co"
                                                              @"nn"
                                                              @"ec"
                                                              @"ti"
                                                              @"on"
                                                              @" S"
                                                              @"uc"
                                                              @"ce"
                                                              @"ss"
                                                              @"fu"
                                                              @"l"
                                                      message:message
                                               preferredStyle:
                                                   UIAlertControllerStyleAlert];
                             [successAlert
                                 addAction:
                                     [UIAlertAction
                                         actionWithTitle:@"OK"
                                                   style:
                                                       UIAlertActionStyleDefault
                                                 handler:nil]];
                             [self presentViewController:successAlert
                                                animated:YES
                                              completion:nil];
                           } else {
                             NSString *errorDetails = @"";
                             if (sshOutput.length > 0) {
                               // Extract
                               // last few
                               // lines of
                               // SSH
                               // output
                               // for
                               // error
                               // details
                               NSArray *lines = [sshOutput
                                   componentsSeparatedByString:@"\n"];
                               NSArray *lastLines =
                                   lines.count > 5
                                       ? [lines
                                             subarrayWithRange:NSMakeRange(
                                                                   lines.count -
                                                                       5,
                                                                   5)]
                                       : lines;
                               errorDetails = [NSString
                                   stringWithFormat:
                                       @"\n\nLast output:\n%@",
                                       [lastLines
                                           componentsJoinedByString:@"\n"]];
                             }

                             UIAlertController *errorAlert = [UIAlertController
                                 alertControllerWithTitle:@"SS"
                                                          @"H "
                                                          @"Co"
                                                          @"nn"
                                                          @"ec"
                                                          @"ti"
                                                          @"on"
                                                          @" F"
                                                          @"ai"
                                                          @"le"
                                                          @"d"
                                                  message:
                                                      [NSString
                                                          stringWithFormat:
                                                              @"SSH connection "
                                                              @"failed (exit "
                                                              @"code "
                                                              @"%d)."
                                                              @"\n\nPossible "
                                                              @"reasons:\n- "
                                                              @"Invalid "
                                                              @"username or "
                                                              @"password\n- "
                                                              @"Invalid SSH "
                                                              @"key\n- Host "
                                                              @"unreachable\n- "
                                                              @"Authentication "
                                                              @"method "
                                                              @"mismatch%@",
                                                              exitCode,
                                                              errorDetails]
                                           preferredStyle:
                                               UIAlertControllerStyleAlert];
                             [errorAlert
                                 addAction:
                                     [UIAlertAction
                                         actionWithTitle:@"OK"
                                                   style:
                                                       UIAlertActionStyleDefault
                                                 handler:nil]];
                             [self presentViewController:errorAlert
                                                animated:YES
                                              completion:nil];
                           }
                         }];
});
});
}];
#endif
  [progressAlert
      dismissViewControllerAnimated:YES
                         completion:^{
                           UIAlertController *alert = [UIAlertController
                               alertControllerWithTitle:@"SSH Test Disabled"
                                                message:@"SSH testing via "
                                                        @"HIAHKernel is "
                                                        @"currently disabled."
                                         preferredStyle:
                                             UIAlertControllerStyleAlert];
                           [alert
                               addAction:
                                   [UIAlertAction
                                       actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
                           [self presentViewController:alert
                                              animated:YES
                                            completion:nil];
                         }];
#else
  // macOS implementation using sshpass (if available) or expect-like pty
  // approach Run the SSH test asynchronously to avoid blocking UI
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        WLog(@"SSH", @"Starting SSH test to %@@%@ (macOS)", user, host);

        NSString *password = prefs.sshPassword;
        BOOL usePasswordAuth =
            (prefs.sshAuthMethod == 0 && password.length > 0);

        // Check if sshpass is available for password auth
        NSString *sshpassPath = nil;
        if (usePasswordAuth) {
          NSFileManager *fm = [NSFileManager defaultManager];
          NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
          NSString *execPath = [[NSBundle mainBundle] executablePath];
          NSString *execDir = [execPath stringByDeletingLastPathComponent];

          WLog(@"SSH", @"Bundle path: %@", bundlePath);
          WLog(@"SSH", @"Executable path: %@", execPath);

          // Check for bundled sshpass first (Nix-built), then fallback to
          // system locations macOS bundle structure:
          // Wawona.app/Contents/MacOS/sshpass or Contents/Resources/bin/sshpass
          // iOS bundle structure: Wawona.app/bin/sshpass
          // Nix store structure: The binary at /nix/store/.../bin/Wawona is a
          // symlink,
          //   actual app bundle is at /nix/store/.../Applications/Wawona.app/
          NSString *nixStoreBase = [[execDir stringByDeletingLastPathComponent]
              stringByDeletingLastPathComponent];
          NSString *nixAppPath =
              [[nixStoreBase stringByAppendingPathComponent:@"Applications"]
                  stringByAppendingPathComponent:@"Wawona.app"];

          NSArray *sshpassPaths = @[
            // Nix: App bundle in same store path as binary symlink
            [[nixAppPath stringByAppendingPathComponent:@"Contents/MacOS"]
                stringByAppendingPathComponent:@"sshpass"],
            [[nixAppPath
                stringByAppendingPathComponent:@"Contents/Resources/bin"]
                stringByAppendingPathComponent:@"sshpass"],
            // Also check parent's parent (for
            // /nix/store/xxx-wawona-macos/bin/Wawona ->
            // ../Applications/Wawona.app)
            [[[[execDir stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:
                    @"Applications/Wawona.app/Contents/MacOS"]
                stringByAppendingPathComponent:@"sshpass"]
                stringByStandardizingPath],
            // macOS: Same directory as executable (Contents/MacOS/)
            [execDir stringByAppendingPathComponent:@"sshpass"],
            // macOS: Resources bin directory
            [[[NSBundle mainBundle] resourcePath]
                stringByAppendingPathComponent:@"bin/sshpass"],
            // macOS: Bundle resource lookup
            [[NSBundle mainBundle] pathForResource:@"sshpass" ofType:nil]
                ?: @"",
            // iOS: Flat app bundle structure
            [bundlePath stringByAppendingPathComponent:@"bin/sshpass"],
            [bundlePath stringByAppendingPathComponent:@"sshpass"],
            // Fallback: relative paths
            [execDir stringByAppendingPathComponent:@"../bin/sshpass"],
            [[execDir stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:@"bin/sshpass"],
            // System locations (Homebrew, etc.)
            @"/opt/homebrew/bin/sshpass", @"/usr/local/bin/sshpass",
            @"/usr/bin/sshpass"
          ];

          WLog(@"SSH", @"Searching for sshpass in %lu paths...",
               (unsigned long)sshpassPaths.count);
          for (NSString *path in sshpassPaths) {
            if (path.length > 0) {
              BOOL exists = [fm fileExistsAtPath:path];
              BOOL executable = [fm isExecutableFileAtPath:path];
              NSLog(
                  @"[SSH Test macOS]   Checking: %@ (exists=%d, executable=%d)",
                  path, exists, executable);
              if (executable) {
                sshpassPath = path;
                WLog(@"SSH", @"Found sshpass at: %@", sshpassPath);
                break;
              }
            }
          }

          if (!sshpassPath) {
            WLog(@"SSH",
                 @"sshpass not found in any location. Password auth may fail.");
            WLog(@"SSH", @"To install sshpass: brew install "
                         @"hudochenkov/sshpass/sshpass");
          }
        }

        // Build SSH command arguments
        NSMutableArray *sshArgs = [NSMutableArray array];
        NSString *executablePath = @"/usr/bin/ssh";

        if (usePasswordAuth && sshpassPath) {
          // Use sshpass for password authentication
          executablePath = sshpassPath;
          [sshArgs addObject:@"-p"];
          [sshArgs addObject:password];
          [sshArgs addObject:@"ssh"];
          WLog(@"SSH", @"Using sshpass at: %@", sshpassPath);
        }

        [sshArgs addObject:@"-v"]; // Verbose for debugging
        [sshArgs addObject:@"-o"];
        [sshArgs addObject:@"ConnectTimeout=10"];
        [sshArgs addObject:@"-o"];
        [sshArgs addObject:@"StrictHostKeyChecking=no"];
        [sshArgs addObject:@"-o"];
        [sshArgs addObject:@"UserKnownHostsFile=/dev/null"];

        // Only use BatchMode if we're NOT doing password auth
        // Note: sshpass requires password prompts to work, so we cannot use
        // BatchMode with it
        if (!usePasswordAuth) {
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"BatchMode=yes"];
        }

        // Add authentication method specific options
        if (prefs.sshAuthMethod == 1) { // Public Key
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"PreferredAuthentications=publickey"];
          if (prefs.sshKeyPath.length > 0) {
            [sshArgs addObject:@"-i"];
            [sshArgs addObject:prefs.sshKeyPath];
          }
        } else { // Password auth
          [sshArgs addObject:@"-o"];
          [sshArgs
              addObject:
                  @"PreferredAuthentications=password,keyboard-interactive"];
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"PubkeyAuthentication=no"];
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"NumberOfPasswordPrompts=1"];
        }

        [sshArgs addObject:@"-4"]; // IPv4 only for faster connection

        NSString *target = [NSString stringWithFormat:@"%@@%@", user, host];
        [sshArgs addObject:target];
        [sshArgs addObject:@"uname -a"];

        WLog(@"SSH", @"Running: %@ %@", executablePath,
             [sshArgs componentsJoinedByString:@" "]);

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = executablePath;
        task.arguments = sshArgs;

        NSMutableDictionary *env =
            [[[NSProcessInfo processInfo] environment] mutableCopy];
        task.environment = env;

        NSPipe *outputPipe = [NSPipe pipe];
        NSPipe *errorPipe = [NSPipe pipe];
        NSPipe *inputPipe = nil;

        task.standardOutput = outputPipe;
        task.standardError = errorPipe;

        // If password auth without sshpass, we'll need to provide password via
        // stdin
        if (usePasswordAuth && !sshpassPath) {
          inputPipe = [NSPipe pipe];
          task.standardInput = inputPipe;
          NSLog(@"[SSH Test macOS] Will attempt to provide password via stdin "
                @"(may not work without PTY)");
        }

        NSError *launchError = nil;
        [task launchAndReturnError:&launchError];

        if (launchError) {
          WLog(@"SSH", @"Launch error: %@", launchError);
          dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"SSH Launch Failed";
            errorAlert.informativeText =
                [NSString stringWithFormat:@"Failed to launch SSH: %@",
                                           launchError.localizedDescription];
            [errorAlert addButtonWithTitle:@"OK"];
            [errorAlert runModal];
          });
          return;
        }

        // If we're providing password via stdin (fallback without sshpass)
        if (inputPipe && usePasswordAuth && !sshpassPath) {
          // Give SSH time to prompt for password, then send it
          dispatch_after(
              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
              dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *passwordWithNewline =
                    [password stringByAppendingString:@"\n"];
                NSData *passwordData = [passwordWithNewline
                    dataUsingEncoding:NSUTF8StringEncoding];
                @try {
                  [inputPipe.fileHandleForWriting writeData:passwordData];
                  [inputPipe.fileHandleForWriting closeFile];
                } @catch (NSException *e) {
                  NSLog(
                      @"[SSH Test macOS] Failed to write password to stdin: %@",
                      e);
                }
              });
        }

        // Wait for task with timeout
        dispatch_semaphore_t taskSemaphore = dispatch_semaphore_create(0);
        dispatch_async(
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
              [task waitUntilExit];
              dispatch_semaphore_signal(taskSemaphore);
            });

        dispatch_time_t taskTimeout =
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC));
        BOOL timedOut =
            (dispatch_semaphore_wait(taskSemaphore, taskTimeout) != 0);

        if (timedOut) {
          [task terminate];
          WLog(@"SSH", @"Timed out after 15 seconds");
          dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"SSH Connection Timeout";
            errorAlert.informativeText =
                @"SSH connection test timed out after 15 seconds.\n\nThis may "
                @"indicate:\n- Network connectivity issues\n- SSH server not "
                @"responding\n- Authentication hanging";
            [errorAlert addButtonWithTitle:@"OK"];
            [errorAlert runModal];
          });
          return;
        }

        int exitCode = task.terminationStatus;
        NSData *outputData =
            [outputPipe.fileHandleForReading readDataToEndOfFile];
        NSData *errorData =
            [errorPipe.fileHandleForReading readDataToEndOfFile];
        NSString *outputString =
            [[NSString alloc] initWithData:outputData
                                  encoding:NSUTF8StringEncoding]
                ?: @"";
        NSString *errorString =
            [[NSString alloc] initWithData:errorData
                                  encoding:NSUTF8StringEncoding]
                ?: @"";

        WLog(@"SSH", @"Exit code: %d", exitCode);
        WLog(@"SSH", @"Output: %@", outputString);
        WLog(@"SSH", @"Stderr: %@", errorString);

        dispatch_async(dispatch_get_main_queue(), ^{
          NSAlert *resultAlert = [[NSAlert alloc] init];

          if (exitCode == 0) {
            resultAlert.messageText = @"SSH Connection Successful";
            NSString *unameOutput = [outputString
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (unameOutput.length > 0) {
              resultAlert.informativeText = [NSString
                  stringWithFormat:@"Connected to %@@%@\n\nRemote system:\n%@",
                                   user, host, unameOutput];
            } else {
              resultAlert.informativeText = [NSString
                  stringWithFormat:
                      @"Successfully connected and authenticated to %@@%@",
                      user, host];
            }
            resultAlert.alertStyle = NSAlertStyleInformational;
          } else {
            resultAlert.messageText = @"SSH Connection Failed";
            NSMutableString *details = [NSMutableString
                stringWithFormat:@"SSH connection failed (exit code %d).\n\n",
                                 exitCode];

            // Parse common errors
            if ([errorString containsString:@"Permission denied"]) {
              [details appendString:
                           @"Authentication failed. Please check:\n- Username "
                           @"is correct\n- Password/key is correct\n- Auth "
                           @"method matches server config\n"];

              // Add specific note about sshpass for password auth
              if (usePasswordAuth && !sshpassPath) {
                [details appendString:@"\n⚠️ Password auth on macOS requires "
                                      @"'sshpass'.\nInstall via: brew install "
                                      @"hudochenkov/sshpass/sshpass\n"];
              }
            } else if ([errorString containsString:@"Connection refused"]) {
              [details appendString:@"Connection refused. Please check:\n- SSH "
                                    @"server is running on the host\n- Port 22 "
                                    @"is open\n- Firewall settings\n"];
            } else if ([errorString
                           containsString:@"Host key verification failed"]) {
              [details appendString:@"Host key verification failed.\n"];
            } else if ([errorString containsString:@"No route to host"]) {
              [details appendString:@"Network error: No route to host.\n"];
            } else if ([errorString containsString:@"Connection timed out"]) {
              [details appendString:@"Connection timed out.\n"];
            } else {
              // Show last few lines of error
              NSArray *lines = [errorString componentsSeparatedByString:@"\n"];
              if (lines.count > 3) {
                NSArray *lastLines =
                    [lines subarrayWithRange:NSMakeRange(lines.count - 4, 3)];
                [details
                    appendFormat:@"Last output:\n%@",
                                 [lastLines componentsJoinedByString:@"\n"]];
              } else {
                [details appendString:errorString];
              }
            }

            resultAlert.informativeText = details;
            resultAlert.alertStyle = NSAlertStyleWarning;
          }

          [resultAlert addButtonWithTitle:@"OK"]; // First: OK (Right/Default)
          [resultAlert
              addButtonWithTitle:@"Copy Log"]; // Second: Copy Log (Left)

          NSModalResponse response = [resultAlert runModal];
          if (response == NSAlertSecondButtonReturn) {
            // Copy log to clipboard
            NSString *fullLog =
                [NSString stringWithFormat:
                              @"SSH Test Log\n============\nHost: %@@%@\nExit "
                              @"Code: %d\n\nOutput:\n%@\n\nStderr:\n%@",
                              user, host, exitCode, outputString, errorString];
            NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
            [pasteboard clearContents];
            [pasteboard setString:fullLog forType:NSPasteboardTypeString];
          }
        });
      });
#endif
}

- (void)pingSSHHost {
  WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
  NSString *host = prefs.sshHost;

  WLog(@"SSH", @"Attempting to ping SSH host: '%@'", host ?: @"(nil)");

  if (!host || host.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No Host Specified"
                         message:@"Please enter an SSH host address first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No Host Specified";
    alert.informativeText = @"Please enter an SSH host address first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

#if TARGET_OS_IPHONE
  UIAlertController *progressAlert = [UIAlertController
      alertControllerWithTitle:@"Pinging SSH Host"
                       message:[NSString
                                   stringWithFormat:
                                       @"Testing network connectivity to %@...",
                                       host]
                preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:progressAlert animated:YES completion:nil];
#endif

  // Use Network framework for ping asynchronously
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    __block BOOL success = NO;
    __block double latency = 0.0;
    __block NSString *errorMessage = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSDate *startTime = [NSDate date];

    nw_endpoint_t endpoint = nw_endpoint_create_host([host UTF8String], "22");
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_connection_t connection = nw_connection_create(endpoint, parameters);

    if (!connection) {
      errorMessage = @"Failed to create Network.framework connection";
      dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
        [progressAlert
            dismissViewControllerAnimated:YES
                               completion:^{
                                 UIAlertController *resultAlert = [UIAlertController
                                     alertControllerWithTitle:@"Ping Failed"
                                                      message:
                                                          [NSString
                                                              stringWithFormat:
                                                                  @"Failed to "
                                                                  @"reach "
                                                                  @"%@\n%@",
                                                                  host,
                                                                  errorMessage]
                                               preferredStyle:
                                                   UIAlertControllerStyleAlert];
                                 [resultAlert
                                     addAction:
                                         [UIAlertAction
                                             actionWithTitle:@"OK"
                                                       style:
                                                           UIAlertActionStyleDefault
                                                     handler:nil]];
                                 [self presentViewController:resultAlert
                                                    animated:YES
                                                  completion:nil];
                               }];
#else
        NSAlert *resultAlert = [[NSAlert alloc] init];
        resultAlert.messageText = @"Ping Failed";
        resultAlert.informativeText = [NSString stringWithFormat:@"Failed to reach %@\n%@", host, errorMessage];
        [resultAlert addButtonWithTitle:@"OK"];
        [resultAlert runModal];
#endif
      });
      return;
    }

    dispatch_queue_t connectionQueue = dispatch_queue_create(
        "com.aspauldingcode.wawona.sshping", DISPATCH_QUEUE_SERIAL);
    nw_connection_set_queue(connection, connectionQueue);

    nw_connection_set_state_changed_handler(
        connection, ^(nw_connection_state_t state, nw_error_t nw_error) {
          switch (state) {
          case nw_connection_state_ready: {
            success = YES;
            latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
            nw_connection_cancel(connection);
            dispatch_semaphore_signal(semaphore);
            break;
          }
          case nw_connection_state_failed:
          case nw_connection_state_cancelled: {
            if (nw_error) {
              nw_error_domain_t domain = nw_error_get_error_domain(nw_error);
              int error_code = nw_error_get_error_code(nw_error);
              errorMessage = [NSString
                  stringWithFormat:@"Connection failed: %s error %d",
                                   domain == nw_error_domain_dns   ? "DNS"
                                   : domain == nw_error_domain_tls ? "TLS"
                                                                   : "POSIX",
                                   error_code];
            } else {
              errorMessage = @"Connection failed";
            }
            dispatch_semaphore_signal(semaphore);
            break;
          }
          default:
            break;
          }
        });

    nw_connection_start(connection);

    // Wait for connection with timeout
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
      // Timeout
      if (!success) {
        errorMessage = @"Connection timeout after 5 seconds";
      }
      nw_connection_cancel(connection);
    } else {
      nw_connection_cancel(connection);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
      [progressAlert
          dismissViewControllerAnimated:YES
                             completion:^{
                               UIAlertController *resultAlert = [UIAlertController
                                   alertControllerWithTitle:
                                       success ? @"Ping Successful"
                                               : @"Ping Failed"
                                                    message:
                                                        success
                                                            ? [NSString
                                                                  stringWithFormat:
                                                                      @"Success"
                                                                      @"fully "
                                                                      @"reached"
                                                                      @" %@"
                                                                      @"\nLaten"
                                                                      @"cy: "
                                                                      @"%.0f "
                                                                      @"ms",
                                                                      host,
                                                                      latency]
                                                            : [NSString
                                                                  stringWithFormat:
                                                                      @"Failed "
                                                                      @"to "
                                                                      @"reach "
                                                                      @"%@\n%@",
                                                                      host,
                                                                      errorMessage
                                                                          ? errorMessage
                                                                          : @"U"
                                                                            @"n"
                                                                            @"k"
                                                                            @"n"
                                                                            @"o"
                                                                            @"w"
                                                                            @"n"
                                                                            @" "
                                                                            @"e"
                                                                            @"r"
                                                                            @"r"
                                                                            @"o"
                                                                            @"r"]
                                             preferredStyle:
                                                 UIAlertControllerStyleAlert];
                               [resultAlert
                                   addAction:
                                       [UIAlertAction
                                           actionWithTitle:@"OK"
                                                     style:
                                                         UIAlertActionStyleDefault
                                                   handler:nil]];
                               [self presentViewController:resultAlert
                                                  animated:YES
                                                completion:nil];
                             }];
#else
      NSAlert *resultAlert = [[NSAlert alloc] init];
      resultAlert.messageText = success ? @"Ping Successful" : @"Ping Failed";
      resultAlert.informativeText = success ?
        [NSString stringWithFormat:@"Successfully reached %@\nLatency: %.0f ms", host, latency] :
        [NSString stringWithFormat:@"Failed to reach %@\n%@", host, errorMessage ? errorMessage : @"Unknown error"];
      [resultAlert addButtonWithTitle:@"OK"];       // First: OK (Right/Default)
      [resultAlert addButtonWithTitle:@"Copy Log"]; // Second: Copy Log (Left)

      NSModalResponse response = [resultAlert runModal];
      if (response == NSAlertSecondButtonReturn) {
          // Copy log
          NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
          [pasteboard clearContents];
          NSString *log = [NSString stringWithFormat:@"Ping Host: %@\nStatus: %@\nDetails: %@",
                           host, success ? @"Success" : @"Failed", resultAlert.informativeText];
          [pasteboard setString:log forType:NSPasteboardTypeString];
      }
#endif
    });
  });
}

- (void)pingHost {
  WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
  NSString *host = prefs.waypipeSSHHost ?: prefs.sshHost;

  WLog(@"MAIN", @"Attempting to ping host: '%@'", host ?: @"(nil)");

  if (!host || host.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No Host Specified"
                         message:@"Please enter an SSH host address first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No Host Specified";
    alert.informativeText = @"Please enter an SSH host address first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

#if TARGET_OS_IPHONE
  UIAlertController *progressAlert = [UIAlertController
      alertControllerWithTitle:@"Pinging Host"
                       message:[NSString
                                   stringWithFormat:
                                       @"Testing connectivity to %@...", host]
                preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:progressAlert animated:YES completion:nil];
#endif

  // Perform ping on background thread using Network.framework
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSDate *startTime = [NSDate date];
    __block BOOL success = NO;
    __block NSString *errorMessage = nil;
    __block NSTimeInterval latency = 0;

    // Use Network.framework to test connectivity
    WLog(@"MAIN", @"Creating endpoint for host: '%@'", host);
    nw_endpoint_t endpoint = nw_endpoint_create_host([host UTF8String], "22");

    // Explicitly configure for TCP without TLS, and enable local network access
    // Note: Using insecure TCP for ping test (not secure_tcp)
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_include_peer_to_peer(parameters, true);

    WLog(@"MAIN", @"Starting connection test...");

    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    if (!connection) {
      errorMessage = @"Failed to create Network.framework connection";
      WLog(@"MAIN", @"Ping error: %@", errorMessage);
    } else {
      dispatch_queue_t connectionQueue = dispatch_queue_create(
          "com.aspauldingcode.wawona.ping", DISPATCH_QUEUE_SERIAL);
      nw_connection_set_queue(connection, connectionQueue);

      // Use semaphore to wait for connection synchronously
      dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

      nw_connection_set_state_changed_handler(
          connection, ^(nw_connection_state_t state, nw_error_t nw_error) {
            switch (state) {
            case nw_connection_state_ready: {
              success = YES;
              latency = [[NSDate date] timeIntervalSinceDate:startTime] *
                        1000; // Convert to ms
              nw_connection_cancel(connection);
              dispatch_semaphore_signal(semaphore);
              break;
            }
            case nw_connection_state_failed:
            case nw_connection_state_cancelled: {
              if (nw_error) {
                nw_error_domain_t domain = nw_error_get_error_domain(nw_error);
                int error_code = nw_error_get_error_code(nw_error);

                // Provide more user-friendly error messages
                NSString *domainName = @"Unknown";
                NSString *codeDescription = @"";

                if (domain == nw_error_domain_dns) {
                  domainName = @"DNS";
                  if (error_code == 1) { // kDNSServiceErr_NoSuchRecord
                    codeDescription = @" (Host not found)";
                  } else if (error_code == -65554) { // kDNSServiceErr_NoAuth
                    codeDescription = @" (DNS authentication failed)";
                  }
                } else if (domain == nw_error_domain_tls) {
                  domainName = @"TLS";
                } else if (domain == nw_error_domain_posix) {
                  domainName = @"POSIX";
                  if (error_code == 61) { // ECONNREFUSED
                    codeDescription = @" (Connection refused - host may not be "
                                      @"listening on port 22)";
                  } else if (error_code == 51) { // ENETUNREACH
                    codeDescription = @" (Network unreachable)";
                  } else if (error_code == 65) { // ENETDOWN
                    codeDescription = @" (Network is down)";
                  } else {
                    codeDescription = [NSString
                        stringWithFormat:@" (%s)", strerror(error_code)];
                  }
                }

                errorMessage = [NSString
                    stringWithFormat:@"Connection failed: %@ error %d%@",
                                     domainName, error_code, codeDescription];
                NSLog(@"Ping failed: %@", errorMessage);
              } else {
                errorMessage = @"Connection failed";
                NSLog(@"Ping failed: %@", errorMessage);
              }
              dispatch_semaphore_signal(semaphore);
              break;
            }
            default:
              break;
            }
          });

      nw_connection_start(connection);

      // Wait for connection with 10 second timeout (increased for simulator)
      dispatch_time_t timeout =
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC));
      if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        // Timeout
        errorMessage = @"Connection timeout after 10 seconds";
        WLog(@"MAIN", @"Ping timeout");
        nw_connection_cancel(connection);
      }
    }

    // Show results on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
      [progressAlert
          dismissViewControllerAnimated:YES
                             completion:^{
                               UIAlertController *resultAlert = [UIAlertController
                                   alertControllerWithTitle:
                                       success ? @"Ping Successful"
                                               : @"Ping Failed"
                                                    message:
                                                        success
                                                            ? [NSString
                                                                  stringWithFormat:
                                                                      @"Host "
                                                                      @"%@ is "
                                                                      @"reachab"
                                                                      @"le."
                                                                      @"\nLaten"
                                                                      @"cy: "
                                                                      @"%.0f "
                                                                      @"ms",
                                                                      host,
                                                                      latency]
                                                            : [NSString
                                                                  stringWithFormat:
                                                                      @"Could "
                                                                      @"not "
                                                                      @"reach "
                                                                      @"%@.\n%"
                                                                      @"@",
                                                                      host,
                                                                      errorMessage
                                                                          ?: @"Unknown error"]
                                             preferredStyle:
                                                 UIAlertControllerStyleAlert];
                               [resultAlert
                                   addAction:
                                       [UIAlertAction
                                           actionWithTitle:@"OK"
                                                     style:
                                                         UIAlertActionStyleDefault
                                                   handler:nil]];
                               [self presentViewController:resultAlert
                                                  animated:YES
                                                completion:nil];
                             }];
#else
      NSAlert *resultAlert = [[NSAlert alloc] init];
      resultAlert.messageText = success ? @"Ping Successful" : @"Ping Failed";
      resultAlert.informativeText = success
          ? [NSString stringWithFormat:@"Host %@ is reachable.\nLatency: %.0f ms", host, latency]
          : [NSString stringWithFormat:@"Could not reach %@.\n%@", host, errorMessage ?: @"Unknown error"];
      [resultAlert addButtonWithTitle:@"OK"];
      [resultAlert runModal];
#endif
    });
  });
}

#pragma mark - WawonaWaypipeRunnerDelegate

- (void)runnerDidReceiveSSHPasswordPrompt:(NSString *)prompt {
  WLog(@"PREFS", @"SSH password prompt: %@", prompt);
#if TARGET_OS_IPHONE
  if (self.waypipeStatusAlert) {
    [self.waypipeStatusAlert dismissViewControllerAnimated:YES completion:nil];
    self.waypipeStatusAlert = nil;
  }
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"SSH Password Required"
                       message:prompt ? prompt : @"Enter your SSH password:"
                preferredStyle:UIAlertControllerStyleAlert];

  __block UITextField *passwordField = nil;
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    passwordField = textField;
    textField.placeholder = @"Enter a Password...";
    textField.secureTextEntry = YES;

    // Add show/hide toggle button
    UIButton *toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [toggleButton setImage:[UIImage systemImageNamed:@"eye"]
                  forState:UIControlStateNormal];
    [toggleButton setImage:[UIImage systemImageNamed:@"eye.slash"]
                  forState:UIControlStateSelected];
    toggleButton.frame = CGRectMake(0, 0, 30, 30);
    toggleButton.contentMode = UIViewContentModeCenter;
    [toggleButton addTarget:self
                     action:@selector(togglePasswordVisibility:)
           forControlEvents:UIControlEventTouchUpInside];

    // Store reference to text field in button for toggling
    objc_setAssociatedObject(toggleButton, "passwordField", textField,
                             OBJC_ASSOCIATION_ASSIGN);

    textField.rightView = toggleButton;
    textField.rightViewMode = UITextFieldViewModeAlways;
  }];

  UIAlertAction *cancel =
      [UIAlertAction actionWithTitle:@"Cancel"
                               style:UIAlertActionStyleCancel
                             handler:nil];
  UIAlertAction *submit = [UIAlertAction
      actionWithTitle:@"Save & Connect"
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {
                NSString *password = passwordField.text;
                if (password && password.length > 0) {
                  // Save password to Keychain
                  WawonaPreferencesManager *prefs =
                      [WawonaPreferencesManager sharedManager];
                  prefs.waypipeSSHPassword = password;

                  // Retry waypipe connection
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                               (int64_t)(0.1 * NSEC_PER_SEC)),
                                 dispatch_get_main_queue(), ^{
                                   [self runWaypipe];
                                 });
                } else {
                  UIAlertController *errorAlert = [UIAlertController
                      alertControllerWithTitle:@"Password Required"
                                       message:@"Please enter a password."
                                preferredStyle:UIAlertControllerStyleAlert];
                  [errorAlert
                      addAction:[UIAlertAction
                                    actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
                  [self presentViewController:errorAlert
                                     animated:YES
                                   completion:nil];
                }
              }];
  [alert addAction:cancel];
  [alert addAction:submit];
  [self presentViewController:alert animated:YES completion:nil];
#else
  // macOS: Use NSAlert with secure text field and eyeball toggle
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"SSH Password Required";
  alert.informativeText = prompt ? prompt : @"Enter your SSH password:";
  [alert addButtonWithTitle:@"Save & Connect"];
  [alert addButtonWithTitle:@"Cancel"];
  alert.alertStyle = NSAlertStyleInformational;

  // Create container view with password field and toggle button
  NSView *containerView =
      [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];

  // Create secure text field (hidden by default)
  NSSecureTextField *secureField =
      [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  secureField.placeholderString = @"Enter a Password...";
  secureField.stringValue = @"";
  [containerView addSubview:secureField];

  // Create plain text field (for showing password)
  NSTextField *plainField =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  plainField.placeholderString = @"Enter a Password...";
  plainField.stringValue = @"";
  plainField.hidden = YES;
  [containerView addSubview:plainField];

  // Create eyeball toggle button
  NSButton *toggleButton =
      [[NSButton alloc] initWithFrame:NSMakeRect(255, 2, 20, 20)];
  toggleButton.bezelStyle = NSBezelStyleInline;
  toggleButton.bordered = NO;
  toggleButton.image = [NSImage imageWithSystemSymbolName:@"eye"
                                 accessibilityDescription:@"Show password"];

  // Store references for toggle action
  objc_setAssociatedObject(toggleButton, "secureField", secureField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "plainField", plainField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "isSecure", @YES,
                           OBJC_ASSOCIATION_RETAIN);

  toggleButton.target = self;
  toggleButton.action = @selector(toggleMacOSPasswordVisibility:);

  [containerView addSubview:toggleButton];

  alert.accessoryView = containerView;

  // Make the secure field first responder
  [alert.window makeFirstResponder:secureField];

  NSModalResponse response = [alert runModal];
  if (response == NSAlertFirstButtonReturn) {
    // Get password from whichever field is visible
    NSNumber *isSecureNum = objc_getAssociatedObject(toggleButton, "isSecure");
    NSString *password = isSecureNum.boolValue ? secureField.stringValue
                                               : plainField.stringValue;
    if (password && password.length > 0) {
      WawonaPreferencesManager *prefs =
          [WawonaPreferencesManager sharedManager];
      prefs.waypipeSSHPassword = password;

      // Retry waypipe connection
      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            [self runWaypipe];
          });
    }
  }
#endif
}

- (void)runnerDidReceiveSSHError:(NSString *)error {
  // Log error to status text
  NSString *errorLine =
      [NSString stringWithFormat:@"\n[SSH ERROR] %@\n", error];
  [self.waypipeStatusText appendString:errorLine];

#if TARGET_OS_IPHONE
  if (self.waypipeStatusAlert) {
    [self.waypipeStatusAlert dismissViewControllerAnimated:YES completion:nil];
    self.waypipeStatusAlert = nil;
  }
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"SSH/Waypipe Error"
                                          message:error
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Copy Error"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                 [UIPasteboard generalPasteboard].string =
                                     error;
                               }]];

  [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
#else
  dispatch_async(dispatch_get_main_queue(), ^{
    // Update status panel with error
    if (self.waypipeStatusPanel) {
      self.waypipeStatusPanel.title = @"Waypipe - Error";
    }
    [self updateWaypipeStatusPanel];

    // Also show an alert
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"SSH/Waypipe Error";
    alert.informativeText = error;
    alert.alertStyle = NSAlertStyleCritical;
    [alert addButtonWithTitle:@"Copy Error"];
    [alert addButtonWithTitle:@"OK"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
      [[NSPasteboard generalPasteboard] clearContents];
      [[NSPasteboard generalPasteboard] setString:error
                                          forType:NSPasteboardTypeString];
    }
  });
#endif
}

- (void)runnerDidFinishWithExitCode:(int)exitCode {
  NSString *line =
      [NSString stringWithFormat:@"\n[Exited with code %d]\n", exitCode];
  [self.waypipeStatusText appendString:line];

#if TARGET_OS_IPHONE
  if (self.waypipeStatusAlert) {
    NSString *title = exitCode == 0 ? @"Waypipe Exited" : @"Waypipe Error";
    self.waypipeStatusAlert.title = title;
    self.waypipeStatusAlert.message = self.waypipeStatusText;
  }
#else
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.waypipeStatusPanel) {
      NSString *title =
          exitCode == 0 ? @"Waypipe - Exited" : @"Waypipe - Error";
      self.waypipeStatusPanel.title = title;
    }
    [self updateWaypipeStatusPanel];
  });
#endif
}

- (void)runnerDidReceiveOutput:(NSString *)output isError:(BOOL)isError {
  if (!output || output.length == 0)
    return;

  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.waypipeStatusText) {
      self.waypipeStatusText = [NSMutableString string];
    }

    // Prefix errors for clarity in the log
    NSString *formattedOutput =
        isError ? [NSString stringWithFormat:@"[ERROR] %@", output] : output;
    [self.waypipeStatusText appendString:formattedOutput];

    // Limit log size
    NSUInteger maxLen = 50000;
    if (self.waypipeStatusText.length > maxLen) {
      [self.waypipeStatusText
          deleteCharactersInRange:NSMakeRange(0, self.waypipeStatusText.length -
                                                     maxLen)];
    }

    // Update text view if visible
    if (self.waypipeStatusTextView) {
      [self.waypipeStatusTextView.textStorage.mutableString
          setString:self.waypipeStatusText];
      [self.waypipeStatusTextView
          scrollRangeToVisible:NSMakeRange(self.waypipeStatusText.length, 0)];
    }

    // Re-use existing checks for connection success
    [self checkWaypipeSuccessIndicators:output];
  });
}

- (void)checkWaypipeSuccessIndicators:(NSString *)s {
  if (!self.waypipeMarkedConnected) {
    if ([s containsString:@"Authenticated to"] ||
        [s containsString:@"Entering interactive session"] ||
        [s containsString:@"Entering session"] ||
        [s containsString:@"debug1: Authentication succeeded"] ||
        [s containsString:@"Connection established"]) {
      self.waypipeMarkedConnected = YES;
      if (self.waypipeStatusPanel) {
        self.waypipeStatusPanel.title = @"Waypipe - Connected";
      }
    }
  }
}

- (void)runnerDidReadData:(NSData *)data {
  if (!data || data.length == 0) {
    return;
  }
  NSString *s =
      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!s) {
    s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
  }
  [self runnerDidReceiveOutput:s isError:NO];
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
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                  reuseIdentifier:@"Cell"];
  }

  cell.textLabel.text = item.title;
  cell.textLabel.textColor =
      [UIColor labelColor]; // Reset to default color (not blue)
  cell.detailTextLabel.text = nil;
  cell.accessoryView = nil;
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  if (item.type == WSettingSwitch) {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
    sw.tag = (ip.section * 1000) + ip.row;
    [sw addTarget:self
                  action:@selector(swChg:)
        forControlEvents:UIControlEventValueChanged];

    // No info buttons for switches - removed per user request
    cell.accessoryView = sw;
  } else if (item.type == WSettingText || item.type == WSettingNumber) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }

    // Special handling for Display Number: show computed wayland-X value
    if ([item.key isEqualToString:@"WaylandDisplayNumber"]) {
      NSInteger displayNum =
          [val isKindOfClass:[NSNumber class]] ? [val integerValue] : 0;
      cell.detailTextLabel.text =
          [NSString stringWithFormat:@"%ld (wayland-%ld)", (long)displayNum,
                                     (long)displayNum];
    } else {
      cell.detailTextLabel.text = [val description];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingPassword) {
    // For password fields, show dots if password exists, otherwise show
    // placeholder
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
    NSString *password = nil;
    if ([item.key isEqualToString:@"WaypipeSSHPassword"] ||
        [item.key isEqualToString:@"SSHPassword"]) {
      password = prefs.waypipeSSHPassword ?: prefs.sshPassword;
    } else if ([item.key isEqualToString:@"WaypipeSSHKeyPassphrase"] ||
               [item.key isEqualToString:@"SSHKeyPassphrase"]) {
      password = prefs.waypipeSSHKeyPassphrase ?: prefs.sshKeyPassphrase;
    }
    if (password && password.length > 0) {
      cell.detailTextLabel.text = @"Change";
    } else {
      cell.detailTextLabel.text = @"Set";
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingPopup) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }

    // Special handling for Auth Method: convert integer to string
    if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
        [item.key isEqualToString:@"SSHAuthMethod"]) {
      NSInteger methodIndex =
          [val isKindOfClass:[NSNumber class]] ? [val integerValue] : 0;
      if (methodIndex >= 0 && methodIndex < (NSInteger)item.options.count) {
        cell.detailTextLabel.text = item.options[methodIndex];
      } else {
        cell.detailTextLabel.text = item.options[0]; // Default to "Password"
      }
    } else {
      cell.detailTextLabel.text = [val description];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingButton) {
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingInfo) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }
    cell.detailTextLabel.text = [val description];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
  } else if (item.type == WSettingLink) {
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.detailTextLabel.text = item.desc;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingHeader) {
    // Special header cell with centered content
    cell.textLabel.font = [UIFont boldSystemFontOfSize:20];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.detailTextLabel.text = item.desc;
    cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;

    // Load profile image if URL provided
    if (item.imageURL) {
      dispatch_async(
          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *imageData = [NSData
                dataWithContentsOfURL:[NSURL URLWithString:item.imageURL]];
            if (imageData) {
              UIImage *image = [UIImage imageWithData:imageData];
              dispatch_async(dispatch_get_main_queue(), ^{
                cell.imageView.image = image;
                cell.imageView.layer.cornerRadius = 30;
                cell.imageView.clipsToBounds = YES;
                [cell setNeedsLayout];
              });
            }
          });
    }
  }
  return cell;
}

- (void)swChg:(UISwitch *)s {
  WawonaSettingItem *item = self.sections[s.tag / 1000].items[s.tag % 1000];
  [[NSUserDefaults standardUserDefaults] setBool:s.on forKey:item.key];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)showHelpForSetting:(UIButton *)button {
  NSInteger section = button.tag / 1000;
  NSInteger row = button.tag % 1000;
  WawonaSettingItem *item = self.sections[section].items[row];
  [self showHelpForSettingWithItem:item];
}

- (void)showHelpForSettingWithItem:(WawonaSettingItem *)item {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:item.title
                                          message:item.desc
                                   preferredStyle:UIAlertControllerStyleAlert];

  UIAlertAction *okAction =
      [UIAlertAction actionWithTitle:@"OK"
                               style:UIAlertActionStyleDefault
                             handler:nil];
  [alert addAction:okAction];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
  [tv deselectRowAtIndexPath:ip animated:YES];
  WawonaSettingItem *item = self.sections[ip.section].items[ip.row];

  // For switch items with help buttons, show help when row is tapped
  // Info buttons removed from waypipe switches per user request
  // No action needed for switches - they're handled by swChg:

  if (item.type == WSettingText || item.type == WSettingNumber) {
    // Present text entry view controller
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:item.desc
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      id currentValue =
          [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
      if (!currentValue) {
        currentValue = item.defaultValue;
      }
      textField.text = [currentValue description];
      if (item.type == WSettingNumber) {
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
      } else {
        textField.keyboardType = UIKeyboardTypeDefault;
      }
      // Set placeholder text - special case for Remote Command
      if ([item.key isEqualToString:@"WaypipeRemoteCommand"]) {
        textField.placeholder = @"e.g. weston-terminal";
      } else {
        textField.placeholder = item.desc;
      }
    }];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil];
    UIAlertAction *saveAction = [UIAlertAction
        actionWithTitle:@"Save"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  UITextField *textField = alert.textFields.firstObject;
                  NSString *value = textField.text;

                  if (item.type == WSettingNumber) {
                    NSNumber *numberValue = @([value doubleValue]);
                    [[NSUserDefaults standardUserDefaults] setObject:numberValue
                                                              forKey:item.key];
                  } else {
                    [[NSUserDefaults standardUserDefaults] setObject:value
                                                              forKey:item.key];
                  }
                  [[NSUserDefaults standardUserDefaults] synchronize];

                  // Reload the table view to show updated value
                  [tv reloadRowsAtIndexPaths:@[ ip ]
                            withRowAnimation:UITableViewRowAnimationNone];
                }];

    [alert addAction:cancelAction];
    [alert addAction:saveAction];

    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WSettingPassword) {
    // Single modal for password entry - always show entry field
    // Saving a new password automatically overwrites any existing one
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:item.desc
                  preferredStyle:UIAlertControllerStyleAlert];

    __block UITextField *passwordField = nil;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      passwordField = textField;
      textField.secureTextEntry = YES;
      textField.placeholder = @"Enter a Password...";
      textField.text = @"";

      // Add show/hide toggle button
      UIButton *toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
      [toggleButton setImage:[UIImage systemImageNamed:@"eye"]
                    forState:UIControlStateNormal];
      [toggleButton setImage:[UIImage systemImageNamed:@"eye.slash"]
                    forState:UIControlStateSelected];
      toggleButton.frame = CGRectMake(0, 0, 30, 30);
      toggleButton.contentMode = UIViewContentModeCenter;
      [toggleButton addTarget:self
                       action:@selector(togglePasswordVisibility:)
             forControlEvents:UIControlEventTouchUpInside];

      // Store reference to text field in button for toggling
      objc_setAssociatedObject(toggleButton, "passwordField", textField,
                               OBJC_ASSOCIATION_ASSIGN);

      textField.rightView = toggleButton;
      textField.rightViewMode = UITextFieldViewModeAlways;
    }];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil];

    UIAlertAction *saveAction = [UIAlertAction
        actionWithTitle:@"Save"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  NSString *value = passwordField.text;

                  // Save password (overwrites existing if any)
                  if ([item.key isEqualToString:@"WaypipeSSHPassword"]) {
                    prefs.waypipeSSHPassword = value;
                  } else if ([item.key
                                 isEqualToString:@"WaypipeSSHKeyPassphrase"]) {
                    prefs.waypipeSSHKeyPassphrase = value;
                  } else if ([item.key isEqualToString:@"SSHPassword"]) {
                    prefs.sshPassword = value;
                  } else if ([item.key isEqualToString:@"SSHKeyPassphrase"]) {
                    prefs.sshKeyPassphrase = value;
                  }

                  // Reload the table view to show updated value
                  [tv reloadRowsAtIndexPaths:@[ ip ]
                            withRowAnimation:UITableViewRowAnimationNone];
                }];

    [alert addAction:cancelAction];
    [alert addAction:saveAction];

    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WSettingLink) {
    // Open URL in browser
    if (item.urlString) {
      [self openURL:item.urlString];
    }
  } else if (item.type == WSettingHeader) {
    // Header cells are not tappable
    return;
  } else if (item.type == WSettingInfo) {
    // For info items, show copy dialog
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }
    NSString *valueString = [val description];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:[NSString stringWithFormat:@"%@\n\n%@",
                                                            item.desc,
                                                            valueString]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *copyAction = [UIAlertAction
        actionWithTitle:@"Copy"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                  pasteboard.string = valueString;
                }];

    UIAlertAction *okAction =
        [UIAlertAction actionWithTitle:@"OK"
                                 style:UIAlertActionStyleCancel
                               handler:nil];

    [alert addAction:copyAction];
    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WSettingPopup) {
    // Present popup selection
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:item.desc
                  preferredStyle:UIAlertControllerStyleActionSheet];

    id currentValue =
        [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!currentValue) {
      currentValue = item.defaultValue;
    }

    // Special handling for Auth Method: convert integer to string for
    // comparison
    NSString *currentValueString = nil;
    NSInteger currentIndex = -1;
    if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
        [item.key isEqualToString:@"SSHAuthMethod"]) {
      currentIndex = [currentValue isKindOfClass:[NSNumber class]]
                         ? [currentValue integerValue]
                         : 0;
      if (currentIndex >= 0 && currentIndex < (NSInteger)item.options.count) {
        currentValueString = item.options[currentIndex];
      } else {
        currentValueString = item.options[0]; // Default to "Password"
        currentIndex = 0;
      }
    } else {
      currentValueString = [currentValue description];
    }

    for (NSInteger i = 0; i < (NSInteger)item.options.count; i++) {
      NSString *option = item.options[i];
      NSString *optionCopy = option; // Capture for block
      NSInteger optionIndex = i;     // Capture index for block
      UIAlertAction *optionAction = [UIAlertAction
          actionWithTitle:option
                    style:UIAlertActionStyleDefault
                  handler:^(UIAlertAction *alertAction) {
                    // For Auth Method, store as integer index
                    if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
                        [item.key isEqualToString:@"SSHAuthMethod"]) {
                      [[NSUserDefaults standardUserDefaults]
                          setInteger:optionIndex
                              forKey:item.key];
                      [[NSUserDefaults standardUserDefaults] synchronize];
                      // Auth method changed - rebuild sections to show
                      // appropriate nested options
                      self.sections = [self buildSections];
                      [tv reloadData];
                    } else {
                      [[NSUserDefaults standardUserDefaults]
                          setObject:optionCopy
                             forKey:item.key];
                      [[NSUserDefaults standardUserDefaults] synchronize];
                      // Reload the table view to show updated value
                      [tv reloadRowsAtIndexPaths:@[ ip ]
                                withRowAnimation:UITableViewRowAnimationNone];
                    }
                  }];

      // Mark current selection with checkmark
      if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
          [item.key isEqualToString:@"SSHAuthMethod"]) {
        if (i == currentIndex) {
          [optionAction setValue:@YES forKey:@"checked"];
        }
      } else {
        if ([option isEqualToString:currentValueString]) {
          [optionAction setValue:@YES forKey:@"checked"];
        }
      }

      [alert addAction:optionAction];
    }

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:@"Cancel"
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
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskFullSizeContentView
                  backing:NSBackingStoreBuffered
                    defer:NO];
  win.title = @"Wawona Settings";
  win.movableByWindowBackground = YES;

  // Add Toolbar (Liquid Glass Style)
  NSToolbar *toolbar =
      [[NSToolbar alloc] initWithIdentifier:@"WawonaPreferencesToolbar"];
  toolbar.delegate = self;
  toolbar.displayMode = NSToolbarDisplayModeIconOnly;
  win.toolbar = toolbar;

  // Use the glass content view we just configured
  NSView *v = win.contentView;

  self.sidebar = [[WawonaPreferencesSidebar alloc] init];
  self.sidebar.parent = self;
  self.content = [[WawonaPreferencesContent alloc] init];

  self.splitVC = [[NSSplitViewController alloc] init];
  NSSplitViewItem *sItem =
      [NSSplitViewItem sidebarWithViewController:self.sidebar];
  sItem.minimumThickness = 160; // Ensure enough width for "Connection" text
  sItem.maximumThickness = 220;
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

#if TARGET_OS_IPHONE
- (void)togglePasswordVisibility:(UIButton *)sender {
  UITextField *textField = objc_getAssociatedObject(sender, "passwordField");
  if (textField) {
    textField.secureTextEntry = !textField.secureTextEntry;
    sender.selected = !textField.secureTextEntry;
  }
}
#endif

- (void)previewWaypipeCommand {
  id runner = [WawonaWaypipeRunner sharedRunner];
  WLog(@"PREFS", @"previewWaypipeCommand: runner=%@, class=%@", runner,
       [runner class]);
  NSString *cmdString = [runner
      generateWaypipePreviewString:[WawonaPreferencesManager sharedManager]];

#if TARGET_OS_OSX
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Waypipe Command Preview";
  alert.informativeText = cmdString;
  [alert addButtonWithTitle:@"OK"];       // First button: FirstButtonReturn
                                          // (Default/Right)
  [alert addButtonWithTitle:@"Copy Log"]; // Second button: SecondButtonReturn
                                          // (Left)
  NSModalResponse response = [alert runModal];

  if (response == NSAlertSecondButtonReturn) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:cmdString forType:NSPasteboardTypeString];
  }
#else
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"Waypipe Command Preview"
                                          message:cmdString
                                   preferredStyle:UIAlertControllerStyleAlert];

  UIAlertAction *copyAction = [UIAlertAction
      actionWithTitle:@"Copy"
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *_Nonnull action) {
                UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                pasteboard.string = cmdString;
              }];

  UIAlertAction *okAction =
      [UIAlertAction actionWithTitle:@"OK"
                               style:UIAlertActionStyleCancel
                             handler:nil];

  [alert addAction:copyAction];
  [alert addAction:okAction];

  [self presentViewController:alert animated:YES completion:nil];
#endif
}

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
  self.outlineView.rowHeight = 24.0; // Standard sidebar height
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"M"];
  col.width = 180;    // Ensure column is wide enough for sidebar text
  col.minWidth = 100; // Minimum width to prevent text wrapping
  col.resizingMask = NSTableColumnAutoresizingMask; // Auto-resize with sidebar
  [self.outlineView addTableColumn:col];
  self.outlineView.outlineTableColumn = col;
  self.outlineView.autoresizesOutlineColumn = YES; // Auto-size outline column
  sv.documentView = self.outlineView;
  sv.hasHorizontalScroller = NO; // No horizontal scroll in sidebar
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
    tf.maximumNumberOfLines = 1; // Single line only - no wrapping
    tf.lineBreakMode =
        NSLineBreakByTruncatingTail; // Truncate with ellipsis if needed
    tf.cell.truncatesLastVisibleLine = YES;
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
@interface WawonaPreferenceCell : NSTableCellView <NSTextFieldDelegate>
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *descLabel;
@property(nonatomic, strong) NSSwitch *switchControl;
@property(nonatomic, strong) NSTextField *textControl;
@property(nonatomic, strong) NSButton *buttonControl;
@property(nonatomic, strong) NSPopUpButton *popupControl;
@property(nonatomic, strong) NSImageView *iconView; // For link icons
@property(nonatomic, strong)
    NSImageView *headerImageView; // For large logos/avatars
@property(nonatomic, strong)
    NSLayoutConstraint *leadingConstraint; // New: for layout
@property(nonatomic, strong) NSLayoutConstraint *trailingConstraint;
@property(nonatomic, strong) WawonaSettingItem *item;
@property(nonatomic, assign) id delegate; // MRC: use assign for delegates
- (void)configureWithItem:(WawonaSettingItem *)item
                   target:(id)target
                   action:(SEL)action;
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
    _titleLabel.maximumNumberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.cell.truncatesLastVisibleLine = YES;
    [_titleLabel
        setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                 forOrientation:
                                     NSLayoutConstraintOrientationVertical];
    [_titleLabel
        setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                 forOrientation:
                                     NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_titleLabel];

    _descLabel = [NSTextField labelWithString:@""];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.font = [NSFont systemFontOfSize:11];
    _descLabel.textColor = [NSColor secondaryLabelColor];
    _descLabel.maximumNumberOfLines = 1;
    _descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _descLabel.cell.truncatesLastVisibleLine = YES;
    [_descLabel
        setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                 forOrientation:
                                     NSLayoutConstraintOrientationVertical];
    [_descLabel
        setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                 forOrientation:
                                     NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_descLabel];

    // Initialize all potential controls hidden
    _switchControl = [[NSSwitch alloc] init];
    _switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    _switchControl.hidden = YES;
    [self addSubview:_switchControl];

    // Text Field (standard AppKit)
    _textControl = [[NSTextField alloc] init];
    _textControl.placeholderString = @"";
    _textControl.delegate = self; // Cell handles own delegate events
    _textControl.translatesAutoresizingMaskIntoConstraints = NO;
    _textControl.hidden = YES;
    [self addSubview:_textControl];

    // Button (standard AppKit)
    _buttonControl = [[NSButton alloc] init];
    _buttonControl.title = @"Run";
    _buttonControl.bezelStyle = NSBezelStyleRounded;
    _buttonControl.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonControl.hidden = YES;
    [self addSubview:_buttonControl];

    _popupControl =
        [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _popupControl.translatesAutoresizingMaskIntoConstraints = NO;
    _popupControl.hidden = YES;
    [self addSubview:_popupControl];

    _iconView = [[NSImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.hidden = YES;
    _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_iconView];

    _headerImageView = [[NSImageView alloc] init];
    _headerImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _headerImageView.hidden = YES;
    _headerImageView.wantsLayer = YES;
    _headerImageView.layer.masksToBounds = YES;
    _headerImageView.layer.cornerRadius = 0.0;
    _headerImageView.layer.contentsGravity = kCAGravityResizeAspect;
    [self addSubview:_headerImageView];

    // Static Auto Layout - Two column design:
    // Left column (labels): leading to ~55% of width
    // Right column (controls): ~45% of width, right-aligned
    CGFloat controlAreaWidth = 160; // Fixed width for control area
    CGFloat spacing = 16;           // Space between labels and controls

    [NSLayoutConstraint activateConstraints:@[
      // Title label - left column
      (_leadingConstraint =
           [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:20]),
      [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
      (_trailingConstraint = [_titleLabel.trailingAnchor
           constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                    constant:-(controlAreaWidth + spacing +
                                               20)]),

      // Description label - below title, same width constraints
      [_descLabel.leadingAnchor
          constraintEqualToAnchor:_titleLabel.leadingAnchor],
      [_descLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                           constant:2],
      [_descLabel.trailingAnchor
          constraintEqualToAnchor:_titleLabel.trailingAnchor],

      // Switch control - right column
      [_switchControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                    constant:-20],
      [_switchControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

      // Text control - right column with fixed width
      [_textControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                  constant:-20],
      [_textControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_textControl.widthAnchor constraintEqualToConstant:controlAreaWidth],

      // Button control - right column
      [_buttonControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                    constant:-20],
      [_buttonControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_buttonControl.widthAnchor constraintGreaterThanOrEqualToConstant:80],

      // Popup control - right column with fixed width
      [_popupControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                   constant:-20],
      [_popupControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_popupControl.widthAnchor constraintEqualToConstant:controlAreaWidth],

      // Icon view (for links, etc.)
      [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                              constant:20],
      [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_iconView.widthAnchor constraintEqualToConstant:24],
      [_iconView.heightAnchor constraintEqualToConstant:24],

      // Header image view
      [_headerImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:20],
      [_headerImageView.centerYAnchor
          constraintEqualToAnchor:self.centerYAnchor],
      [_headerImageView.widthAnchor constraintEqualToConstant:48],
      [_headerImageView.heightAnchor constraintEqualToConstant:48],
    ]];
  }
  return self;
}

- (void)configureWithItem:(WawonaSettingItem *)item
                   target:(id)target
                   action:(SEL)action {
  self.item = item;
  self.delegate = target; // Store controller as delegate
  self.titleLabel.stringValue = item.title ?: @"";
  self.descLabel.stringValue = item.desc ?: @"";

  // Reset Visibility
  self.switchControl.hidden = YES;
  self.textControl.hidden = YES;
  self.buttonControl.hidden = YES;
  self.popupControl.hidden = YES;
  self.headerImageView.hidden = YES;
  self.headerImageView.image = nil;

  NSControl *active = nil;

  // Base leading constraint
  self.leadingConstraint.constant = 20;

  // Icon logic
  if (item.iconURL) {
    self.iconView.hidden = NO;
    [[WawonaImageLoader sharedLoader]
        loadImageFromURL:item.iconURL
              completion:^(WImage _Nullable image) {
                if (image) {
                  self.iconView.image = image;
                }
              }];
    self.leadingConstraint.constant = 48; // Space for 24x24 icon + margin
  } else {
    self.iconView.hidden = YES;
  }

  if (item.type == WSettingSwitch) {
    self.switchControl.hidden = NO;
    self.switchControl.state =
        [[NSUserDefaults standardUserDefaults] boolForKey:item.key]
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    self.switchControl.target = target;
    self.switchControl.action = action;
    active = self.switchControl;
  } else if (item.type == WSettingText || item.type == WSettingNumber) {
    self.textControl.hidden = NO;
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    self.textControl.stringValue =
        val ? val : ([item.defaultValue description] ?: @"");
    self.textControl.target = target;
    self.textControl.action = action;

    // Configure as editable text field
    self.textControl.editable = YES;
    self.textControl.selectable = YES;
    self.textControl.bezeled = YES;
    self.textControl.bezelStyle = NSTextFieldRoundedBezel;
    self.textControl.bordered = NO;
    self.textControl.drawsBackground =
        YES; // Needs background for rounded bezel
    self.textControl.backgroundColor = [NSColor controlBackgroundColor];

    // Set placeholder text for empty fields
    if ([item.key isEqualToString:@"WaypipeRemoteCommand"]) {
      self.textControl.placeholderString = @"e.g. weston-terminal";
    } else if ([item.key containsString:@"Host"]) {
      self.textControl.placeholderString = @"Remote host address";
    } else if ([item.key containsString:@"User"]) {
      self.textControl.placeholderString = @"SSH username";
    } else if ([item.key containsString:@"Path"]) {
      self.textControl.placeholderString = @"Enter path...";
    } else {
      self.textControl.placeholderString = nil;
    }

    // Use middle truncation for path-like fields (like Socket Directory)
    if ([item.key isEqualToString:@"WaylandSocketDir"] ||
        [item.key containsString:@"Dir"] || [item.key containsString:@"Path"]) {
      self.textControl.lineBreakMode = NSLineBreakByTruncatingMiddle;
      self.textControl.cell.truncatesLastVisibleLine = YES;
    } else {
      self.textControl.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    active = self.textControl;
  } else if (item.type == WSettingPassword) {
    // For password fields, show a button that opens a password entry dialog
    self.buttonControl.hidden = NO;
    // For password fields, get from Keychain to show status
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
    NSString *password = nil;
    if ([item.key isEqualToString:@"WaypipeSSHPassword"] ||
        [item.key isEqualToString:@"SSHPassword"]) {
      password = prefs.waypipeSSHPassword ?: prefs.sshPassword;
    } else if ([item.key isEqualToString:@"WaypipeSSHKeyPassphrase"] ||
               [item.key isEqualToString:@"SSHKeyPassphrase"]) {
      password = prefs.waypipeSSHKeyPassphrase ?: prefs.sshKeyPassphrase;
    }
    // Show button text based on whether password exists
    if (password && password.length > 0) {
      self.buttonControl.title = @"Change";
    } else {
      self.buttonControl.title = @"Set";
    }
    self.buttonControl.target = target;
    self.buttonControl.action = action;
    active = self.buttonControl;
  } else if (item.type == WSettingButton) {
    self.buttonControl.hidden = NO;
    self.buttonControl.target = target;
    self.buttonControl.action = action;
    active = self.buttonControl;
  } else if (item.type == WSettingPopup) {
    self.popupControl.hidden = NO;
    [self.popupControl removeAllItems];
    [self.popupControl addItemsWithTitles:item.options];

    // Handle SSHAuthMethod specially - stored as integer index
    if ([item.key isEqualToString:@"SSHAuthMethod"] ||
        [item.key isEqualToString:@"WaypipeSSHAuthMethod"]) {
      NSInteger methodIndex =
          [[NSUserDefaults standardUserDefaults] integerForKey:item.key];
      if (methodIndex >= 0 && methodIndex < (NSInteger)item.options.count) {
        [self.popupControl selectItemAtIndex:methodIndex];
      } else {
        [self.popupControl selectItemAtIndex:0]; // Default to Password
      }
    } else {
      NSString *val =
          [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
      [self.popupControl selectItemWithTitle:val ? val : item.defaultValue];
    }

    self.popupControl.target = target;
    self.popupControl.action = action;
    active = self.popupControl;
  } else if (item.type == WSettingInfo) {
    // Info type: show read-only text with copy button
    self.textControl.hidden = NO;
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    self.textControl.stringValue =
        val ? val : ([item.defaultValue description] ?: @"");
    self.textControl.editable = NO;
    self.textControl.selectable = YES;
    self.textControl.bezeled = NO;
    self.textControl.bordered = NO;
    self.textControl.backgroundColor = [NSColor clearColor];
    self.textControl.drawsBackground = NO;

    // Use middle truncation for path-like fields (Finder-style truncation)
    if ([item.key isEqualToString:@"WaylandSocketDir"] ||
        [item.key containsString:@"Dir"] || [item.key containsString:@"Path"]) {
      self.textControl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    } else {
      self.textControl.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    active = self.textControl;
  } else if (item.type == WSettingLink) {
    // Show a small icon and description for the link
    self.titleLabel.textColor = [NSColor linkColor];
    self.buttonControl.hidden = NO;
    self.buttonControl.title = item.desc ?: @"Open";
    self.buttonControl.target = target;
    self.buttonControl.action = action;
    active = self.buttonControl;
  } else if (item.type == WSettingHeader) {
    // Header type: show centered title with image
    self.titleLabel.font = [NSFont boldSystemFontOfSize:16];
    self.titleLabel.alignment = NSTextAlignmentLeft;
    self.descLabel.stringValue = item.desc ?: @"";
    self.descLabel.textColor = [NSColor secondaryLabelColor];

    if (item.imageURL || item.imageName) {
      self.headerImageView.hidden = NO;
      NSString *img = item.imageURL ?: item.imageName;
      [[WawonaImageLoader sharedLoader]
          loadImageFromURL:img
                completion:^(WImage _Nullable image) {
                  if (image) {
                    self.headerImageView.image = image;
                  }
                }];

      // Shift text labels to the right if image is present
      self.leadingConstraint.constant = 80;
    }
    active = nil; // Headers never have a right-side control
  }

  // Final layout refinement:
  // If we have an active control (switch, text, button, etc.), we need to
  // leave space for it on the right. Otherwise, use full width.
  if (active) {
    self.trailingConstraint.constant =
        -(160 + 16 + 20); // Control + Spacing + Margin
  } else {
    self.trailingConstraint.constant = -20; // Full width
  }
}

- (void)controlTextDidChange:(NSNotification *)obj {
  NSTextField *tf = [obj object];
  if (tf == self.textControl) {
    // Forward to act: with tag
    if ([self.delegate respondsToSelector:@selector(act:)]) {
      [self.delegate performSelector:@selector(act:) withObject:tf];
    }
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
  self.tableView.columnAutoresizingStyle =
      NSTableViewUniformColumnAutoresizingStyle;

  NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"C"];
  c.width = sv.bounds.size.width;                 // Match scroll view width
  c.minWidth = 300;                               // Minimum column width
  c.resizingMask = NSTableColumnAutoresizingMask; // Auto-resize with window
  [self.tableView addTableColumn:c];
  sv.documentView = self.tableView;
  sv.hasHorizontalScroller = NO; // No horizontal scroll - content should fit
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
  NSInteger row = (NSInteger)[sender tag];
  if (row < 0 || row >= (NSInteger)self.section.items.count) {
    return;
  }

  WawonaSettingItem *item = self.section.items[row];

  // Handle password fields - show a dialog for password entry
  if (item.type == WSettingPassword) {
    [self showPasswordDialogForItem:item row:row];
    return;
  }

  if (item.type == WSettingButton) {
    if (item.actionBlock) {
      item.actionBlock();
    }
    return;
  }

  if (item.type == WSettingInfo) {
    // For Info type, copy to clipboard on click
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    NSString *valueString = val ? val : [item.defaultValue description];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:valueString forType:NSPasteboardTypeString];
    return;
  }

  if (item.type == WSettingLink) {
    // For Link type, open URL in browser
    if (item.urlString) {
      NSURL *url = [NSURL URLWithString:item.urlString];
      if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
      }
    }
    return;
  }

  if (item.type == WSettingHeader) {
    // Header is not clickable
    return;
  }

  id val = nil;
  if ([sender isKindOfClass:[NSSwitch class]]) {
    val = @([(NSSwitch *)sender state] == NSControlStateValueOn);
  } else if ([sender isKindOfClass:[NSTextField class]]) {
    val = [(NSTextField *)sender stringValue];
    // For text fields, save immediately when value changes
    if (val && item.key) {
      [[NSUserDefaults standardUserDefaults] setObject:val forKey:item.key];
      [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return; // Return early for text fields - they save on each change
  } else if ([sender isKindOfClass:[NSPopUpButton class]]) {
    // Handle SSHAuthMethod specially - store as integer index
    if ([item.key isEqualToString:@"SSHAuthMethod"] ||
        [item.key isEqualToString:@"WaypipeSSHAuthMethod"]) {
      NSInteger selectedIndex = [(NSPopUpButton *)sender indexOfSelectedItem];
      [[NSUserDefaults standardUserDefaults] setInteger:selectedIndex
                                                 forKey:item.key];
      [[NSUserDefaults standardUserDefaults] synchronize];

      // Auth method changed - rebuild sections to show appropriate nested
      // options
      WawonaPreferences *prefs = [WawonaPreferences sharedPreferences];
      prefs.sections = [prefs buildSections];
      [self.tableView reloadData];

      [[NSNotificationCenter defaultCenter]
          postNotificationName:@"WawonaPreferencesChanged"
                        object:nil];
      return;
    }
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

- (void)showPasswordDialogForItem:(WawonaSettingItem *)item row:(NSInteger)row {
  // Single modal for password entry - always show entry field
  // Saving a new password automatically overwrites any existing one
  WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = item.title;
  alert.informativeText = item.desc ?: @"Enter password:";
  [alert addButtonWithTitle:@"Save"];
  [alert addButtonWithTitle:@"Cancel"];

  // Create container view with password field and toggle button
  NSView *containerView =
      [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];

  // Create secure text field (hidden by default)
  NSSecureTextField *secureField =
      [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  secureField.placeholderString = @"Enter a Password...";
  secureField.stringValue = @"";
  [containerView addSubview:secureField];

  // Create plain text field (for showing password)
  NSTextField *plainField =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  plainField.placeholderString = @"Enter a Password...";
  plainField.stringValue = @"";
  plainField.hidden = YES;
  [containerView addSubview:plainField];

  // Create eyeball toggle button
  NSButton *toggleButton =
      [[NSButton alloc] initWithFrame:NSMakeRect(255, 2, 20, 20)];
  toggleButton.bezelStyle = NSBezelStyleInline;
  toggleButton.bordered = NO;
  toggleButton.image = [NSImage imageWithSystemSymbolName:@"eye"
                                 accessibilityDescription:@"Show password"];

  // Store references for toggle action
  objc_setAssociatedObject(toggleButton, "secureField", secureField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "plainField", plainField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "isSecure", @YES,
                           OBJC_ASSOCIATION_RETAIN);

  toggleButton.target = self;
  toggleButton.action = @selector(toggleMacOSPasswordVisibility:);

  [containerView addSubview:toggleButton];

  alert.accessoryView = containerView;

  // Make the secure field first responder when alert appears
  [alert.window makeFirstResponder:secureField];

  NSModalResponse response = [alert runModal];

  if (response == NSAlertFirstButtonReturn) {
    // Save button clicked - get password from whichever field is visible
    NSNumber *isSecureNum = objc_getAssociatedObject(toggleButton, "isSecure");
    NSString *enteredPassword = isSecureNum.boolValue ? secureField.stringValue
                                                      : plainField.stringValue;

    // Save password (overwrites existing if any)
    if ([item.key isEqualToString:@"WaypipeSSHPassword"]) {
      prefs.waypipeSSHPassword = enteredPassword;
    } else if ([item.key isEqualToString:@"WaypipeSSHKeyPassphrase"]) {
      prefs.waypipeSSHKeyPassphrase = enteredPassword;
    } else if ([item.key isEqualToString:@"SSHPassword"]) {
      prefs.sshPassword = enteredPassword;
    } else if ([item.key isEqualToString:@"SSHKeyPassphrase"]) {
      prefs.sshKeyPassphrase = enteredPassword;
    }

    // Update the button text to reflect new state
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                              columnIndexes:[NSIndexSet indexSetWithIndex:0]];
  }
  // Cancel = do nothing
}

- (void)toggleMacOSPasswordVisibility:(NSButton *)sender {
  NSSecureTextField *secureField =
      objc_getAssociatedObject(sender, "secureField");
  NSTextField *plainField = objc_getAssociatedObject(sender, "plainField");
  NSNumber *isSecureNum = objc_getAssociatedObject(sender, "isSecure");
  BOOL isSecure = isSecureNum ? isSecureNum.boolValue : YES;

  if (isSecure) {
    // Switch to plain text (show password)
    plainField.stringValue = secureField.stringValue;
    secureField.hidden = YES;
    plainField.hidden = NO;
    [plainField.window makeFirstResponder:plainField];
    sender.image = [NSImage imageWithSystemSymbolName:@"eye.slash"
                             accessibilityDescription:@"Hide password"];
    objc_setAssociatedObject(sender, "isSecure", @NO, OBJC_ASSOCIATION_RETAIN);
  } else {
    // Switch to secure (hide password)
    secureField.stringValue = plainField.stringValue;
    plainField.hidden = YES;
    secureField.hidden = NO;
    [secureField.window makeFirstResponder:secureField];
    sender.image = [NSImage imageWithSystemSymbolName:@"eye"
                             accessibilityDescription:@"Show password"];
    objc_setAssociatedObject(sender, "isSecure", @YES, OBJC_ASSOCIATION_RETAIN);
  }
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
  return 50.0;
}

@end

#endif
