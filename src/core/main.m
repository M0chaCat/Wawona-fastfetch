#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import "WawonaCompositor.h"
#import <QuartzCore/QuartzCore.h>
// #import "WawonaKernel.h" // Removed
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <HIAHKernel/HIAHKernel.h> // HIAHKernel - iOS only
#endif
// #import "WawonaKernelTests.h" // Removed
#import "../logging/WawonaLog.h"
#import "../logging/logging.h"
#import "../ui/About/WawonaAboutPanel.h"
#import "../ui/Helpers/WawonaUIHelpers.h"
#import "../ui/Settings/WawonaPreferences.h"
#import "../ui/Settings/WawonaPreferencesManager.h"
#import "../ui/Settings/WawonaWaypipeRunner.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-server-core.h>

// Global references for signal handler
static struct wl_display *g_display = NULL;
static WawonaCompositor *g_compositor = NULL;

// Signal handler for graceful shutdown
static void signal_handler(int sig) {
  (void)sig;
  WLog(@"MAIN", @"🛑 Received signal %d, shutting down gracefully...", sig);

  // Use compositor's stop method which properly disconnects all clients
  // This ensures clients are notified and can clean up gracefully
  if (g_compositor) {
    [g_compositor stop];
    g_compositor = nil;
  }

  // Clear global display reference (compositor.stop already destroyed it)
  g_display = NULL;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // On iOS, don't call exit() immediately - let the app terminate naturally
  // This prevents crash reports. The signal will be handled by the system.
  // For SIGTERM, we'll let the app delegate handle termination.
#else
  // On macOS CLI, terminate the app gracefully
  // Give a small delay to ensure cleanup completes
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
      });
#endif
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR

//
// iOS Implementation
//

#import "../launcher/WawonaLauncherClient.h"

@interface WawonaAppDelegate : NSObject <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) WawonaCompositor *compositor;
@property(nonatomic, assign) struct wl_display *display;
@property(nonatomic, assign)
    pthread_t launcher_thread; // Thread for launcher client
@property(nonatomic, strong) UIButton *settingsButton;
@end

@implementation WawonaAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  (void)launchOptions;

  // DEBUG: Write a marker file immediately to verify we reached this point
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                       NSUserDomainMask, YES);
  NSString *documentsDirectory = [paths firstObject];

  // Ensure Documents directory exists
  [[NSFileManager defaultManager] createDirectoryAtPath:documentsDirectory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];

  NSString *markerPath =
      [documentsDirectory stringByAppendingPathComponent:@"LAUNCH_MARKER.txt"];
  [@"Launched!" writeToFile:markerPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];

  // Redirect logs to file
  NSString *logPath =
      [documentsDirectory stringByAppendingPathComponent:@"wawona.log"];
  freopen([logPath cStringUsingEncoding:NSASCIIStringEncoding], "a+", stderr);
  freopen([logPath cStringUsingEncoding:NSASCIIStringEncoding], "a+", stdout);

  NSLog(@"🎯 Wawona - Wayland Compositor for iOS");
  NSLog(@"   Using libwayland-server (no WLRoots)");
  NSLog(@"   Rendering with Metal/Surface");
  NSLog(@"");

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // Initialize HIAHKernel (iOS only)
  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  kernel.appGroupIdentifier =
      @"group.com.aspauldingcode.Wawona"; // Must match entitlements
  kernel.extensionIdentifier =
      @"com.aspauldingcode.Wawona.HIAHProcessRunner"; // Matches patched
                                                       // Info.plist

  // Setup kernel output logging
  kernel.onOutput = ^(pid_t pid, NSString *output) {
    WLog(@"KERNEL", @"[Guest %d] %@", pid, output);
  };
#endif

  // Kernel Tests: Run comprehensive tests if enabled
  // BUT: Only run if explicitly requested AND not running normal waypipe
  const char *kernelTest = getenv("WAWONA_KERNEL_TEST");
  // const char *skipTests = getenv("WAWONA_SKIP_KERNEL_TESTS");
  const char *sshTest = getenv("WAWONA_SSH_TEST");
  const char *waypipeTest = getenv("WAWONA_WAYPIPE_TEST");

  #if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // SSH Connection Test: Test actual SSH connection with hardcoded or env
  // credentials (iOS only)
  if (sshTest && strcmp(sshTest, "1") == 0) {
    WLog(@"MAIN", @"========================================");
    WLog(@"MAIN", @"🧪 SSH Connection Test mode enabled");
    WLog(@"MAIN", @"🧪 Running SSH connection test");
    WLog(@"MAIN", @"========================================");

    // Run SSH connection test using HIAHKernel
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    // Check possible locations for SSH binary
    NSString *sshPath = [bundlePath stringByAppendingPathComponent:@"bin/ssh"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:sshPath]) {
      // Try dylib extension (common in iOS builds)
      NSString *sshDylib =
          [bundlePath stringByAppendingPathComponent:@"bin/ssh.dylib"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:sshDylib]) {
        sshPath = sshDylib;
      }
    }

    WLog(@"MAIN", @"[HIAHKernel] Spawning SSH binary at: %@", sshPath);

    // Get credentials from env (or use defaults)
    const char *envHost = getenv("SIMCTL_CHILD_WAWONA_SSH_HOST");
    const char *envUser = getenv("SIMCTL_CHILD_WAWONA_SSH_USER");

    NSString *host =
        envHost ? [NSString stringWithUTF8String:envHost] : @"10.0.0.87";
    NSString *user =
        envUser ? [NSString stringWithUTF8String:envUser] : @"alex";
    NSString *destination = [NSString stringWithFormat:@"%@@%@", user, host];

    // Command arguments: ssh user@host id
    NSArray *args = @[ destination, @"id" ];

    [kernel
        spawnVirtualProcessWithPath:sshPath
                          arguments:args
                        environment:@{@"TERM" : @"xterm-256color"}
                         completion:^(pid_t pid, NSError *error) {
                           if (error) {
                             WLog(@"MAIN",
                                  @"❌ [HIAHKernel] SSH Spawn failed: %@",
                                  error);
                             dispatch_async(dispatch_get_main_queue(), ^{
                               UIAlertController *alert = [UIAlertController
                                   alertControllerWithTitle:@"SSH Spawn Failed"
                                                    message:
                                                        error
                                                            .localizedDescription
                                             preferredStyle:
                                                 UIAlertControllerStyleAlert];
                               [alert
                                   addAction:
                                       [UIAlertAction
                                           actionWithTitle:@"Copy Error"
                                                     style:
                                                         UIAlertActionStyleDefault
                                                   handler:^(
                                                       UIAlertAction *action) {
                                                     [UIPasteboard
                                                         generalPasteboard]
                                                         .string =
                                                         error
                                                             .localizedDescription;
                                                   }]];
                               [alert
                                   addAction:
                                       [UIAlertAction
                                           actionWithTitle:@"OK"
                                                     style:
                                                         UIAlertActionStyleCancel
                                                   handler:nil]];
                               [self.window.rootViewController
                                   presentViewController:alert
                                                animated:YES
                                              completion:nil];
                             });
                           } else {
                             WLog(@"MAIN",
                                  @"✅ [HIAHKernel] SSH Spawned "
                                  @"successfully with PID %d",
                                  pid);
                           }
                         }];
  }
  // Waypipe Test: Similar to SSH test but with full Waypipe integration
  else if (waypipeTest && strcmp(waypipeTest, "1") == 0) {
    WLog(@"MAIN", @"========================================");
    WLog(@"MAIN", @"🧪 Waypipe Test mode enabled");
    WLog(@"MAIN", @"🧪 Running Waypipe SSH connection test");
    WLog(@"MAIN", @"========================================");

    // Run SSH connection test (Waypipe uses SSH internally)
    // [WawonaKernel runSSHConnectionTest]; // REPLACED logic needed?
    NSLog(@"[Main] Waypipe Test not implemented with HIAHKernel yet");
  }
  // Regular Kernel Tests
  else if (kernelTest && strcmp(kernelTest, "1") == 0) {
    WLog(@"MAIN", @"========================================");
    WLog(@"MAIN", @"🧪 Kernel test mode enabled");
    WLog(@"MAIN", @"🧪 Running comprehensive kernel tests");
    WLog(@"MAIN", @"========================================");

    // Run kernel tests
    // [WawonaKernel runKernelTests];
    NSLog(@"[Main] Kernel Test not implemented with HIAHKernel yet");
  }
#else
  // macOS: HIAHKernel tests not available
  if (sshTest && strcmp(sshTest, "1") == 0) {
    NSLog(@"[Main] SSH Test not available on macOS");
  }
  if (waypipeTest && strcmp(waypipeTest, "1") == 0) {
    NSLog(@"[Main] Waypipe Test not available on macOS");
  }
  if (kernelTest && strcmp(kernelTest, "1") == 0) {
    NSLog(@"[Main] Kernel Test not available on macOS");
  }
#endif

  // Set up XDG_RUNTIME_DIR
  const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
  NSString *runtimePath = nil;
  NSFileManager *fm = [NSFileManager defaultManager];

  if (!runtime_dir) {
    @try {
      WawonaPreferencesManager *prefsManager =
          [WawonaPreferencesManager sharedManager];
      if (prefsManager) {
        NSString *preferred = [prefsManager waylandSocketDir];
        if (preferred.length > 0) {
          runtimePath = preferred;
        }
      }
    } @catch (NSException *exception) {
      runtimePath = nil;
    }

    if (!runtimePath) {
#if TARGET_OS_SIMULATOR
      // On Simulator, use a short path in /tmp to avoid socket path length
      // limits This maps to /tmp on the macOS host
      runtimePath = [NSString stringWithFormat:@"/tmp/wawona_sim_%d", getuid()];
#else
      NSString *tmpDir = NSTemporaryDirectory();
      if (tmpDir.length > 0) {
        runtimePath = tmpDir;
      } else {
        NSLog(@"❌ NSTemporaryDirectory() returned nil");
        return NO;
      }
#endif
    }

    NSError *error = nil;
    BOOL created = [fm createDirectoryAtPath:runtimePath
                 withIntermediateDirectories:YES
                                  attributes:@{NSFilePosixPermissions : @0700}
                                       error:&error];
    if (!created && ![fm fileExistsAtPath:runtimePath]) {
      NSLog(@"❌ Failed to create runtime directory at %@: %@", runtimePath,
            error.localizedDescription);
      return NO;
    }

    // Verify directory is writable
    if (![fm isWritableFileAtPath:runtimePath]) {
      NSLog(@"❌ Runtime directory is not writable: %@", runtimePath);
      return NO;
    }

    setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
    runtime_dir = [runtimePath UTF8String];
    NSLog(@"   Set XDG_RUNTIME_DIR to: %@", runtimePath);
  } else {
    runtimePath = [NSString stringWithUTF8String:runtime_dir];
    // Verify the existing directory is writable
    if (![fm isWritableFileAtPath:runtimePath]) {
      NSLog(@"❌ XDG_RUNTIME_DIR is not writable: %@", runtimePath);
      return NO;
    }
  }

  // Create Wayland display
  struct wl_display *display = wl_display_create();
  if (!display) {
    NSLog(@"❌ Failed to create wl_display");
    return NO;
  }

  const char *socket_name = "wayland-0";
  // Safely get preferences with fallback defaults
  BOOL enable_tcp_pref = NO;
  NSInteger tcp_port_pref = 0;
  @try {
    WawonaPreferencesManager *prefsManager =
        [WawonaPreferencesManager sharedManager];
    if (prefsManager) {
      enable_tcp_pref = [prefsManager enableTCPListener];
      tcp_port_pref = [prefsManager tcpListenerPort];
    }
  } @catch (NSException *exception) {
    NSLog(@"⚠️ Failed to read preferences, using defaults: %@", exception);
    enable_tcp_pref = NO;
    tcp_port_pref = 0;
  }
  BOOL use_tcp = enable_tcp_pref;
  int tcp_listen_fd = -1;
  int wayland_port = 0;

  if (use_tcp) {
    if (enable_tcp_pref) {
      NSLog(@"ℹ️ TCP Listener enabled via preferences (allowing external "
            @"connections)");
    }

    // Create TCP socket
    tcp_listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (tcp_listen_fd < 0) {
      NSLog(@"❌ Failed to create TCP socket: %s", strerror(errno));
      wl_display_destroy(display);
      return NO;
    }

    // Set socket options
    int reuse = 1;
    if (setsockopt(tcp_listen_fd, SOL_SOCKET, SO_REUSEADDR, &reuse,
                   sizeof(reuse)) < 0) {
      NSLog(@"⚠️ Failed to set SO_REUSEADDR: %s", strerror(errno));
    }

    // Bind to address
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;

    // If enabled via pref, bind to all interfaces (0.0.0.0) to allow external
    // connections Otherwise (fallback only), bind to localhost (127.0.0.1) for
    // security
    if (enable_tcp_pref) {
      addr.sin_addr.s_addr = htonl(INADDR_ANY);
    } else {
      addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    }

    // Use preferred port if set and enabled, otherwise dynamic (0)
    if (enable_tcp_pref && tcp_port_pref > 0 && tcp_port_pref < 65536) {
      addr.sin_port = htons((uint16_t)tcp_port_pref);
    } else {
      addr.sin_port = 0; // Let OS choose port
    }

    if (bind(tcp_listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
      NSLog(@"❌ Failed to bind TCP socket: %s", strerror(errno));
      close(tcp_listen_fd);
      wl_display_destroy(display);
      return NO;
    }

    // Set socket to non-blocking mode (required for event loop)
    int flags = fcntl(tcp_listen_fd, F_GETFL, 0);
    if (flags < 0 || fcntl(tcp_listen_fd, F_SETFL, flags | O_NONBLOCK) < 0) {
      NSLog(@"❌ Failed to set TCP socket to non-blocking: %s",
            strerror(errno));
      close(tcp_listen_fd);
      wl_display_destroy(display);
      return NO;
    }

    // Listen on socket
    if (listen(tcp_listen_fd, 128) < 0) {
      NSLog(@"❌ Failed to listen on TCP socket: %s", strerror(errno));
      close(tcp_listen_fd);
      wl_display_destroy(display);
      return NO;
    }

    // Get the port number that was assigned
    socklen_t addr_len = sizeof(addr);
    if (getsockname(tcp_listen_fd, (struct sockaddr *)&addr, &addr_len) < 0) {
      NSLog(@"❌ Failed to get TCP socket port: %s", strerror(errno));
      close(tcp_listen_fd);
      wl_display_destroy(display);
      return NO;
    }
    wayland_port = ntohs(addr.sin_port);

    // Note: We'll handle TCP accept() manually in the event loop
    // wl_display_add_socket_fd doesn't work with listening sockets

    // Set WAYLAND_DISPLAY to TCP address format: "wayland-0" (clients will use
    // WAYLAND_DISPLAY env var) For TCP, we'll use a special format or clients
    // can connect directly via the port
    char tcp_display[64];
    snprintf(tcp_display, sizeof(tcp_display), "wayland-0");
    setenv("WAYLAND_DISPLAY", tcp_display, 1);
    // Also set WAYLAND_SOCKET_FD for compatibility (though not standard)
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", wayland_port);
    setenv("WAYLAND_TCP_PORT", port_str, 1);

    NSString *bindAddr = enable_tcp_pref ? @"0.0.0.0" : @"127.0.0.1";
    NSLog(@"✅ Wayland TCP socket listening on port %d (%@:%d)", wayland_port,
          bindAddr, wayland_port);
    NSLog(@"   Clients can connect via: WAYLAND_DISPLAY=wayland-0 "
          @"WAYLAND_TCP_PORT=%d",
          wayland_port);

    {
      int cwd_ret = chdir(runtime_dir);
      if (cwd_ret == 0) {
        int ufd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (ufd >= 0) {
          struct sockaddr_un uaddr;
          memset(&uaddr, 0, sizeof(uaddr));
          uaddr.sun_family = AF_UNIX;
          strncpy(uaddr.sun_path, socket_name, sizeof(uaddr.sun_path) - 1);
          unlink(socket_name);
          if (bind(ufd, (struct sockaddr *)&uaddr, sizeof(uaddr)) == 0) {
            if (listen(ufd, 128) == 0) {
              if (wl_display_add_socket_fd(display, ufd) == 0) {
                setenv("WAYLAND_DISPLAY", socket_name, 1);
                NSLog(@"✅ Wayland Unix socket ALSO created: %s (cwd: %s)",
                      socket_name, runtime_dir);
              }
            }
          }
        }
      }
    }
  } else {
    int cwd_ret = chdir(runtime_dir);
    if (cwd_ret != 0) {
      NSLog(@"❌ Failed to chdir to runtime dir: %s", runtime_dir);
      wl_display_destroy(display);
      return NO;
    }
    int ufd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (ufd < 0) {
      NSLog(@"❌ Failed to create Unix socket: %s", strerror(errno));
      wl_display_destroy(display);
      return NO;
    }
    struct sockaddr_un uaddr;
    memset(&uaddr, 0, sizeof(uaddr));
    uaddr.sun_family = AF_UNIX;
    strncpy(uaddr.sun_path, socket_name, sizeof(uaddr.sun_path) - 1);
    unlink(socket_name);
    if (bind(ufd, (struct sockaddr *)&uaddr, sizeof(uaddr)) < 0) {
      NSLog(@"❌ Failed to bind Unix socket '%s': %s", socket_name,
            strerror(errno));
      close(ufd);
      wl_display_destroy(display);
      return NO;
    }
    if (listen(ufd, 128) < 0) {
      NSLog(@"❌ Failed to listen on Unix socket '%s': %s", socket_name,
            strerror(errno));
      close(ufd);
      wl_display_destroy(display);
      return NO;
    }
    if (wl_display_add_socket_fd(display, ufd) < 0) {
      NSLog(@"❌ Failed to add Unix socket FD to Wayland display");
      close(ufd);
      wl_display_destroy(display);
      return NO;
    }
    setenv("WAYLAND_DISPLAY", socket_name, 1);
    NSLog(@"✅ Wayland Unix socket created: %s (cwd: %s)", socket_name,
          runtime_dir);
  }

  // Store globals
  g_display = display;
  self.display = display;

  // Create iOS window
  CGRect screenBounds = [[UIScreen mainScreen] bounds];
  self.window = [[UIWindow alloc] initWithFrame:screenBounds];
  // Use black background to create "letterboxing" effect for safe area
  // rendering
  self.window.backgroundColor = [UIColor blackColor];

  // Root view controller
  UIViewController *rootViewController = [[UIViewController alloc] init];
  rootViewController.view = [[UIView alloc] initWithFrame:screenBounds];
  rootViewController.view.backgroundColor = [UIColor clearColor];
  self.window.rootViewController = rootViewController;

  // Create compositor backend with error handling
  WawonaCompositor *compositor = nil;
  @try {
    compositor =
        [[WawonaCompositor alloc] initWithDisplay:display window:self.window];
    if (!compositor) {
      NSLog(@"❌ Failed to create compositor");
      wl_display_destroy(display);
      return NO;
    }
    g_compositor = compositor;
    self.compositor = compositor;

    // Store TCP listening socket in compositor for manual accept() handling
    if (use_tcp && tcp_listen_fd >= 0) {
      compositor.tcp_listen_fd = tcp_listen_fd;
    }
  } @catch (NSException *exception) {
    NSLog(@"❌ Exception creating compositor: %@", exception);
    NSLog(@"   Call stack: %@", [exception callStackSymbols]);
    if (display) {
      wl_display_destroy(display);
    }
    return NO;
  }

  // Signal handlers
  signal(SIGTERM, signal_handler);
  signal(SIGINT, signal_handler);

  @try {
    if (![compositor start]) {
      NSLog(@"❌ Failed to start compositor backend");
      wl_display_destroy(display);
      return NO;
    }
  } @catch (NSException *exception) {
    NSLog(@"❌ Exception starting compositor: %@", exception);
    NSLog(@"   Call stack: %@", [exception callStackSymbols]);
    wl_display_destroy(display);
    return NO;
  }

  NSLog(@"🚀 Compositor running!");

  // Launch launcher client app only if enabled
  BOOL enableLauncher = NO;
  @try {
    WawonaPreferencesManager *prefsManager =
        [WawonaPreferencesManager sharedManager];
    if (prefsManager) {
      enableLauncher = [prefsManager enableLauncher];
    }
  } @catch (NSException *exception) {
    NSLog(@"⚠️ Failed to read enableLauncher preference, defaulting to NO: %@",
          exception);
    enableLauncher = NO;
  }

  if (enableLauncher) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          int sv[2];
          if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
            NSLog(@"❌ Failed to create socketpair: %s", strerror(errno));
            return;
          }
          struct wl_client *client = wl_client_create(self.display, sv[0]);
          if (!client) {
            NSLog(@"❌ Failed to create Wayland client on server side");
            close(sv[0]);
            close(sv[1]);
            return;
          }
          NSLog(@"✅ Created in-process Wayland client via socketpair");
          self.launcher_thread = startLauncherClientThread(self, sv[1]);
        });
  } else {
    NSLog(@"ℹ️ Single-client mode: in-process launcher client disabled");
  }

  @try {
    [self setupSettingsButtonIfNeeded];
  } @catch (NSException *exception) {
    NSLog(@"⚠️ Exception setting up settings button: %@", exception);
    // Continue anyway - settings button is optional
  }

  @
  try {
    [self.window makeKeyAndVisible];
  } @catch (NSException *exception) {
    NSLog(@"❌ Exception making window key and visible: %@", exception);
    NSLog(@"   Call stack: %@", [exception callStackSymbols]);
    // This is critical, but try to continue
  }

  const char *autorun = getenv("WAWONA_AUTORUN_WAYPIPE");
  WLog(@"MAIN", @"🔧 WAWONA_AUTORUN_WAYPIPE=%s", autorun ? autorun : "(null)");
  if (autorun && strcmp(autorun, "0") != 0) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          WawonaPreferencesManager *prefs =
              [WawonaPreferencesManager sharedManager];

          // Check which SSH config to use
          BOOL useSSHConfig = prefs.waypipeUseSSHConfig;
          NSString *sshHost =
              useSSHConfig ? prefs.sshHost : prefs.waypipeSSHHost;
          NSString *remoteCommand = prefs.waypipeRemoteCommand;

          WLog(@"MAIN", @"🔧 Autorun prefs: useSSHConfig=%d host=%@ cmd=%@",
               useSSHConfig, sshHost, remoteCommand);

          // Only autorun if SSH host and remote command are configured
          if (sshHost.length == 0 || remoteCommand.length == 0) {
            WLog(@"MAIN", @"⏭️ Autorun skipped (missing host or command)");
            return;
          }
          WLog(@"MAIN", @"🚀 Autorun launching waypipe");
          [[WawonaWaypipeRunner sharedRunner] launchWaypipe:prefs];
        });
  }

  NSLog(@"✅ iOS app initialization complete");
  return YES;
}

- (void)setupSettingsButtonIfNeeded {
  WLog(@"MAIN", @"⚙️ setupSettingsButtonIfNeeded called");
  UIView *containerView = self.window.rootViewController.view;
  if (!self.settingsButton) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration
        configurationWithPointSize:24
                            weight:UIImageSymbolWeightRegular];
    UIImage *gearImage =
        [UIImage systemImageNamed:@"gear" withConfiguration:config];
    self.settingsButton = [WawonaUIHelpers
        createLiquidGlassButtonWithImage:gearImage
                                  target:self
                                  action:@selector(showSettings:)];
    self.settingsButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.settingsButton.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
    [containerView addSubview:self.settingsButton];
    [NSLayoutConstraint activateConstraints:@[
      [self.settingsButton.topAnchor
          constraintEqualToAnchor:containerView.safeAreaLayoutGuide.topAnchor
                         constant:20],
      [self.settingsButton.trailingAnchor
          constraintEqualToAnchor:containerView.safeAreaLayoutGuide
                                      .trailingAnchor
                         constant:-20],
      [self.settingsButton.widthAnchor constraintEqualToConstant:50],
      [self.settingsButton.heightAnchor constraintEqualToConstant:50],
    ]];
    WLog(@"MAIN", @"✅ Created settings button");
  } else if (self.settingsButton.superview != containerView) {
    [self.settingsButton removeFromSuperview];
    [containerView addSubview:self.settingsButton];
    [NSLayoutConstraint activateConstraints:@[
      [self.settingsButton.topAnchor
          constraintEqualToAnchor:containerView.safeAreaLayoutGuide.topAnchor
                         constant:20],
      [self.settingsButton.trailingAnchor
          constraintEqualToAnchor:containerView.safeAreaLayoutGuide
                                      .trailingAnchor
                         constant:-20],
      [self.settingsButton.widthAnchor constraintEqualToConstant:50],
      [self.settingsButton.heightAnchor constraintEqualToConstant:50],
    ]];
    WLog(@"MAIN", @"🔄 Re-added settings button to containerView");
  }
  [containerView bringSubviewToFront:self.settingsButton];

  self.settingsButton.hidden = NO;
  self.settingsButton.alpha = 1.0;

  [containerView layoutIfNeeded];
  WLog(@"MAIN", @"📐 Settings button frame: %@",
       NSStringFromCGRect(self.settingsButton.frame));
}

- (void)showSettings:(id)sender {
  WawonaPreferences *prefs = [[WawonaPreferences alloc] init];
  UIViewController *rootViewController = self.window.rootViewController;
  UINavigationController *navController =
      [[UINavigationController alloc] initWithRootViewController:prefs];
  navController.modalPresentationStyle = UIModalPresentationPageSheet;
  [rootViewController presentViewController:navController
                                   animated:YES
                                 completion:nil];
}

- (void)applicationWillResignActive:(UIApplication *)application {
  // Ensure settings are persisted when app goes to background
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
  // Ensure settings are persisted when app enters background
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillTerminate:(UIApplication *)application {
  (void)application;
  NSLog(@"👋 Application will terminate - shutting down gracefully");

  // Ensure settings are persisted before termination
  [[NSUserDefaults standardUserDefaults] synchronize];

  // Disconnect launcher client if still connected
  disconnectLauncherClient(self);

  // Use compositor's stop method which properly disconnects all clients
  // This ensures clients are notified and can clean up gracefully
  if (self.compositor) {
    [self.compositor stop];
    self.compositor = nil;
  }

  // Clear references (compositor.stop already destroyed the display)
  self.display = NULL;
  g_compositor = nil;
  g_display = NULL;

  NSLog(@"✅ Graceful shutdown complete");
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    // Test main function execution
    NSArray *testPaths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    if ([testPaths count] > 0) {
      NSString *testDocDir = [testPaths firstObject];

      // Ensure Documents directory exists (it might not on fresh install)
      [[NSFileManager defaultManager] createDirectoryAtPath:testDocDir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];

      NSString *testFile =
          [testDocDir stringByAppendingPathComponent:@"MAIN_TEST.txt"];
      [[@"Main function executed" dataUsingEncoding:NSUTF8StringEncoding]
          writeToFile:testFile
           atomically:YES];
    }

    // DEBUG: Write a marker file in main
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    if ([paths count] > 0) {
      NSString *documentsDirectory = [paths firstObject];
      NSString *markerPath = [documentsDirectory
          stringByAppendingPathComponent:@"MAIN_MARKER.txt"];
      [@"Main reached!" writeToFile:markerPath
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:nil];
    }

    return UIApplicationMain(argc, argv, nil,
                             NSStringFromClass([WawonaAppDelegate class]));
  }
}

#else

//
// macOS Implementation
//

int main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  @autoreleasepool {
    NSLog(@"🎯 Wawona - Wayland Compositor for macOS");

    // Prevent duplicate processes - terminate any existing Wawona instances
    pid_t currentPID = getpid();
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];

    // Find and terminate other Wawona instances
    NSArray<NSRunningApplication *> *runningApps =
        [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication *app in runningApps) {
      // Check by bundle identifier if available, or by process name
      BOOL isWawona = NO;
      if (currentBundleID && app.bundleIdentifier) {
        isWawona = [app.bundleIdentifier isEqualToString:currentBundleID];
      } else if (app.localizedName) {
        isWawona = [app.localizedName isEqualToString:processName] ||
                   [app.localizedName isEqualToString:@"Wawona"];
      }

      if (isWawona && app.processIdentifier != currentPID) {
        NSLog(@"⚠️ Found existing Wawona instance (PID %d), terminating...",
              app.processIdentifier);
        [app terminate];

        // Wait briefly for termination
        NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (!app.terminated &&
               [[NSDate date] compare:timeout] == NSOrderedAscending) {
          [[NSRunLoop currentRunLoop]
              runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }

        if (!app.terminated) {
          NSLog(@"⚠️ Existing Wawona did not terminate gracefully, force "
                @"killing...");
          [app forceTerminate];
          // Wait a bit more
          usleep(500000); // 500ms
        }
        NSLog(@"✅ Previous Wawona instance terminated");
      }
    }

    // Also check for any stale wayland sockets and clean them up
    {
      NSString *staleRuntimeDir =
          [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
      NSFileManager *staleFm = [NSFileManager defaultManager];
      NSString *socketPath =
          [staleRuntimeDir stringByAppendingPathComponent:@"wayland-0"];
      if ([staleFm fileExistsAtPath:socketPath]) {
        // Check if the socket is stale (no process listening)
        int testFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (testFd >= 0) {
          struct sockaddr_un addr;
          memset(&addr, 0, sizeof(addr));
          addr.sun_family = AF_UNIX;
          strncpy(addr.sun_path, [socketPath UTF8String],
                  sizeof(addr.sun_path) - 1);

          if (connect(testFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            // Connection failed - socket is stale, remove it
            NSLog(@"🧹 Cleaning up stale Wayland socket: %@", socketPath);
            [staleFm removeItemAtPath:socketPath error:nil];
            // Also remove lock file if present
            NSString *lockPath = [socketPath stringByAppendingString:@".lock"];
            [staleFm removeItemAtPath:lockPath error:nil];
            NSLog(@"🧹 Cleaned up lock file: %@", lockPath);
          }
          close(testFd);
        }
      }
    }

    // Set up NSApplication
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // Set up menu bar
    NSMenu *menubar = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];

    NSMenu *appMenu = [[NSMenu alloc] init];
    NSString *appName = [[NSProcessInfo processInfo] processName];

    NSMenuItem *aboutItem = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"About %@", appName]
               action:@selector(showAboutPanel:)
        keyEquivalent:@""];
    [aboutItem setTarget:[WawonaAboutPanel sharedAboutPanel]];
    [appMenu addItem:aboutItem];

    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prefsItem =
        [[NSMenuItem alloc] initWithTitle:@"Preferences..."
                                   action:@selector(showPreferences:)
                            keyEquivalent:@","];
    [prefsItem setTarget:[WawonaPreferences sharedPreferences]];
    [appMenu addItem:prefsItem];

    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
               action:@selector(terminate:)
        keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    // Create compositor window
    NSRect frame = NSMakeRect(100, 100, 1024, 768);
    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:frame
                                    styleMask:(NSWindowStyleMaskTitled |
                                               NSWindowStyleMaskClosable |
                                               NSWindowStyleMaskResizable |
                                               NSWindowStyleMaskMiniaturizable)
                                      backing:NSBackingStoreBuffered
                                        defer:NO];

    [window setTitle:@"Wawona"];

    // Set up XDG_RUNTIME_DIR
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    NSString *runtimePath = nil;
    NSFileManager *fm = [NSFileManager defaultManager];

    if (runtime_dir) {
      runtimePath = [NSString stringWithUTF8String:runtime_dir];
    } else {
      // Use a predictable path in /tmp so external tools (like waypipe) can
      // find it easily NSTemporaryDirectory() is too unpredictable and can be
      // long
      runtimePath = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
      setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
    }

    if (runtimePath) {
      NSLog(@"ℹ️ Using XDG_RUNTIME_DIR: %@", runtimePath);
      // Ensure directory exists with correct permissions (0700)
      NSDictionary *attrs = @{NSFilePosixPermissions : @0700};
      NSError *error = nil;
      BOOL isDir = NO;
      if (![fm fileExistsAtPath:runtimePath isDirectory:&isDir]) {
        if (![fm createDirectoryAtPath:runtimePath
                withIntermediateDirectories:YES
                                 attributes:attrs
                                      error:&error]) {
          NSLog(@"❌ Failed to create XDG_RUNTIME_DIR at %@: %@", runtimePath,
                error);
          return -1;
        }
        NSLog(@"✅ Created XDG_RUNTIME_DIR at %@", runtimePath);
      } else if (!isDir) {
        NSLog(@"❌ XDG_RUNTIME_DIR exists but is not a directory: %@",
              runtimePath);
        return -1;
      } else {
        // Check permissions/ownership if possible, or just ensure it's writable
        if (![fm isWritableFileAtPath:runtimePath]) {
          NSLog(@"❌ XDG_RUNTIME_DIR is not writable: %@", runtimePath);
          return -1;
        }
      }
    } else {
      NSLog(@"❌ Failed to determine XDG_RUNTIME_DIR");
      return -1;
    }

    // Create Wayland display
    struct wl_display *display = wl_display_create();
    if (!display) {
      NSLog(@"❌ Failed to create wl_display");
      return -1;
    }

    const char *socket = wl_display_add_socket_auto(display);
    if (!socket) {
      NSLog(@"❌ Failed to create WAYLAND_DISPLAY socket");
      wl_display_destroy(display);
      return -1;
    }
    NSLog(@"✅ Wayland socket created: %s", socket);

    g_display = display;

    // Create compositor backend
    WawonaCompositor *compositor =
        [[WawonaCompositor alloc] initWithDisplay:display window:window];
    g_compositor = compositor;

    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);

    if (![compositor start]) {
      NSLog(@"❌ Failed to start compositor backend");
      wl_display_destroy(display);
      return -1;
    }

    NSLog(@"🚀 Compositor running!");

    [NSApp run];

    // Cleanup after event loop exits
    // Use compositor's stop method which properly disconnects all clients
    [compositor stop];
    g_compositor = nil;
    // compositor.stop already destroyed the display, just clear the reference
    g_display = NULL;
  }
  return 0;
}

#endif
