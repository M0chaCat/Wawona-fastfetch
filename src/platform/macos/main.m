#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#endif
#import <QuartzCore/QuartzCore.h>

// Rust Compositor Bridge (PRIMARY INTERFACE)
#import "WawonaCompositorBridge.h"

// Platform Adapters
#import "../platform/macos/WawonaPlatformCallbacks.h"

// UI and Settings
#import "../ui/About/WawonaAboutPanel.h"
#import "../ui/Settings/WawonaPreferences.h"
#import "../ui/Settings/WawonaPreferencesManager.h"
#import "../ui/Settings/WawonaWaypipeRunner.h"

// Legacy components (will be moved to platform-specific code later)
#import "../../logging/WawonaLog.h"
#import "WawonaWindow.h"

#include "../logging/logging.h"
#include "../rendering/renderer_apple.h"
#include "WawonaSettings.h"

// C FFI for Rust Compositor window events
typedef struct CWindowInfo {
  uint64_t window_id;
  uint32_t width;
  uint32_t height;
  char *title;
} CWindowInfo;

extern uint32_t wawona_core_pending_window_count(const void *core);
extern CWindowInfo *wawona_core_pop_pending_window(void *core);
extern void wawona_window_info_free(CWindowInfo *info);

// Global references for signal handler (Rust-only build)
extern volatile pid_t g_active_waypipe_pgid;

// Global cleanup for atexit
static void cleanup_on_exit(void) {
  static int cleaning_up = 0;
  if (cleaning_up) {
    return;
  }
  cleaning_up = 1;

  WLog(@"MAIN", @"Performing final cleanup on exit...");

  // Stop any active waypipe session
  [[WawonaWaypipeRunner sharedRunner] stopWaypipe];

  // Stop Rust compositor
  [[WawonaCompositorBridge sharedBridge] stop];
}

// Emergency crash handler - must be strictly async-signal-safe
static void crash_handler(int sig) {
  // Use write() directly for safety
  const char *msg = "\nCRITICAL: Wawona crashed. Emergency cleanup...\n";
  write(STDERR_FILENO, msg, strlen(msg));

  // Kill waypipe process group if active
  pid_t pgid = g_active_waypipe_pgid;
  if (pgid > 0) {
    kill(-pgid, SIGKILL);
  }

  _exit(128 + sig);
}

// Raw signal handler for graceful termination
static void raw_signal_handler(int sig) {
  // We use write() because it's async-signal-safe, preventing deadlocks if
  // malloc/objc runtime is locked
  const char *msg;
  if (sig == SIGINT) {
    msg = "\n\nReceived SIGINT (Ctrl+C), shutting down gracefully...\n";
  } else if (sig == SIGTERM) {
    msg = "\n\nReceived SIGTERM, shutting down gracefully...\n";
  } else {
    msg = "\n\nReceived signal, shutting down...\n";
  }
  write(STDERR_FILENO, msg, strlen(msg));

  // exit() will call atexit() handlers (cleanup_on_exit) which performs cleanup
  // This properly disconnects clients before exiting
  exit(0);
}

// Simple signal setup
static void setup_signal_sources(void) {
  signal(SIGTERM, raw_signal_handler);
  signal(SIGINT, raw_signal_handler);
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

  WLog(@"MAIN", @"Wawona - Wayland Compositor for iOS");
  WLog(@"MAIN", @"Using libwayland-server (no WLRoots)");
  WLog(@"MAIN", @"Rendering with Metal/Surface");
  WLog(@"MAIN", @"");

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#if 0 // HIAHKernel upstream is broken - comment out for now
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
    WLog(@"MAIN", @"SSH Connection Test mode enabled");
    WLog(@"MAIN", @"Running SSH connection test");
    WLog(@"MAIN", @"[HIAHKernel] DISABLED - Upstream broken");
    WLog(@"MAIN", @"========================================");

#if 0 // HIAHKernel upstream is broken - comment out for now
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
                                  @"[HIAHKernel] SSH Spawn failed: %@",
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
                                  @"[HIAHKernel] SSH Spawned "
                                  @"successfully with PID %d",
                                  pid);
                           }
                         }];
#endif
  }
  // Waypipe Test: Similar to SSH test but with full Waypipe integration
  else if (waypipeTest && strcmp(waypipeTest, "1") == 0) {
    WLog(@"MAIN", @"========================================");
    WLog(@"MAIN", @"Waypipe Test mode enabled");
    WLog(@"MAIN", @"Running Waypipe SSH connection test");
    WLog(@"MAIN", @"========================================");

    // Run SSH connection test (Waypipe uses SSH internally)
    // [WawonaKernel runSSHConnectionTest]; // REPLACED logic needed?
    WLog(@"MAIN", @"Waypipe Test not implemented with HIAHKernel yet");
  }
  // Regular Kernel Tests
  else if (kernelTest && strcmp(kernelTest, "1") == 0) {
    WLog(@"MAIN", @"========================================");
    WLog(@"MAIN", @"Kernel test mode enabled");
    WLog(@"MAIN", @"Running comprehensive kernel tests");
    WLog(@"MAIN", @"========================================");

    // Run kernel tests
    // [WawonaKernel runKernelTests];
    WLog(@"MAIN", @"Kernel Test not implemented with HIAHKernel yet");
  }
#else
  // macOS: HIAHKernel tests not available
  if (sshTest && strcmp(sshTest, "1") == 0) {
    WLog(@"MAIN", @"SSH Test not available on macOS");
  }
  if (waypipeTest && strcmp(waypipeTest, "1") == 0) {
    WLog(@"MAIN", @"Waypipe Test not available on macOS");
  }
  if (kernelTest && strcmp(kernelTest, "1") == 0) {
    WLog(@"MAIN", @"Kernel Test not available on macOS");
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
        WLog(@"MAIN", @"NSTemporaryDirectory() returned nil");
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
      WLog(@"MAIN", @"Error: Failed to create runtime directory at %@: %@",
           runtimePath, error.localizedDescription);
      return NO;
    }

    if (![fm isWritableFileAtPath:runtimePath]) {
      WLog(@"MAIN", @"Error: Runtime directory is not writable: %@",
           runtimePath);
      return NO;
    }

    setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
    runtime_dir = [runtimePath UTF8String];
    WLog(@"MAIN", @"Set XDG_RUNTIME_DIR to: %@", runtimePath);
  } else {
    runtimePath = [NSString stringWithUTF8String:runtime_dir];
    // Verify the existing directory is writable
    if (![fm isWritableFileAtPath:runtimePath]) {
      WLog(@"MAIN", @"Error: XDG_RUNTIME_DIR is not writable: %@", runtimePath);
      return NO;
    }
  }

  // ============================================================================
  // RUST COMPOSITOR INITIALIZATION
  // ============================================================================

  WLog(@"MAIN", @"Starting Rust-based Wawona compositor...");

  // Get compositor bridge singleton
  WawonaCompositorBridge *compositor = [WawonaCompositorBridge sharedBridge];

  // Set output configuration
  NSScreen *mainScreen = [NSScreen mainScreen];
  CGSize screenSize = mainScreen.frame.size;
  CGFloat scale = mainScreen.backingScaleFactor;

  [compositor setOutputWidth:(uint32_t)screenSize.width
                      height:(uint32_t)screenSize.height
                       scale:(float)scale];

  WLog(@"MAIN", @"Output configured: %.0fx%.0f @ %.1fx", screenSize.width,
       screenSize.height, scale);

  // Start the Rust compositor
  BOOL started = [compositor startWithSocketName:@"wayland-0"];
  if (!started) {
    WLog(@"MAIN", @"Error: Failed to start Rust compositor");
    return NO;
  }

  NSString *socketPath = [compositor socketPath];
  NSString *socketName = [compositor socketName];

  WLog(@"MAIN", @"Rust compositor started successfully");
  WLog(@"MAIN", @"Socket: %@", socketPath);
  WLog(@"MAIN", @"WAYLAND_DISPLAY=%@", socketName);

  // Set environment for clients
  setenv("WAYLAND_DISPLAY", [socketName UTF8String], 1);

  // Note: TCP listener support will be added to Rust compositor later
  // For now, Unix socket only (which is the standard Wayland approach)
  // Compositor is now running via Rust
  // Event loop and rendering handled below

  enable_tcp_pref = NO;
  tcp_port_pref = 0;
}
BOOL use_tcp = enable_tcp_pref;
int tcp_listen_fd = -1;
int wayland_port = 0;

if (use_tcp) {
  if (enable_tcp_pref) {
    WLog(@"MAIN", @"TCP Listener enabled (allowing external connections)");
  }

  // Create TCP socket
  tcp_listen_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (tcp_listen_fd < 0) {
    WLog(@"MAIN", @"Error: Failed to create TCP socket: %s", strerror(errno));
    wl_display_destroy(display);
    return NO;
  }

  // Set socket options
  int reuse = 1;
  if (setsockopt(tcp_listen_fd, SOL_SOCKET, SO_REUSEADDR, &reuse,
                 sizeof(reuse)) < 0) {
    WLog(@"MAIN", @"Warning: Failed to set SO_REUSEADDR: %s", strerror(errno));
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
    WLog(@"MAIN", @"Error: Failed to bind TCP socket: %s", strerror(errno));
    close(tcp_listen_fd);
    wl_display_destroy(display);
    return NO;
  }

  // Set socket to non-blocking mode (required for event loop)
  int flags = fcntl(tcp_listen_fd, F_GETFL, 0);
  if (flags < 0 || fcntl(tcp_listen_fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    WLog(@"MAIN", @"Error: Failed to set TCP socket to non-blocking: %s",
         strerror(errno));
    close(tcp_listen_fd);
    wl_display_destroy(display);
    return NO;
  }

  // Listen on socket
  if (listen(tcp_listen_fd, 128) < 0) {
    WLog(@"MAIN", @"Error: Failed to listen on TCP socket: %s",
         strerror(errno));
    close(tcp_listen_fd);
    wl_display_destroy(display);
    return NO;
  }

  // Get the port number that was assigned
  socklen_t addr_len = sizeof(addr);
  if (getsockname(tcp_listen_fd, (struct sockaddr *)&addr, &addr_len) < 0) {
    WLog(@"MAIN", @"Error: Failed to get TCP socket port: %s", strerror(errno));
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
  WLog(@"MAIN", @"Wayland TCP socket listening on port %d (%@:%d)",
       wayland_port, bindAddr, wayland_port);
  WLog(
      @"MAIN",
      @"Clients can connect via: WAYLAND_DISPLAY=wayland-0 WAYLAND_TCP_PORT=%d",
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
              WLog(@"MAIN", @"Wayland Unix socket ALSO created: %s (cwd: %s)",
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
    WLog(@"MAIN", @"Error: Failed to chdir to runtime dir: %s", runtime_dir);
    wl_display_destroy(display);
    return NO;
  }
  int ufd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (ufd < 0) {
    WLog(@"MAIN", @"Error: Failed to create Unix socket: %s", strerror(errno));
    wl_display_destroy(display);
    return NO;
  }
  struct sockaddr_un uaddr;
  memset(&uaddr, 0, sizeof(uaddr));
  uaddr.sun_family = AF_UNIX;
  strncpy(uaddr.sun_path, socket_name, sizeof(uaddr.sun_path) - 1);
  unlink(socket_name);
  if (bind(ufd, (struct sockaddr *)&uaddr, sizeof(uaddr)) < 0) {
    WLog(@"MAIN", @"Error: Failed to bind Unix socket '%s': %s", socket_name,
         strerror(errno));
    close(ufd);
    wl_display_destroy(display);
    return NO;
  }
  if (listen(ufd, 128) < 0) {
    WLog(@"MAIN", @"Error: Failed to listen on Unix socket '%s': %s",
         socket_name, strerror(errno));
    close(ufd);
    wl_display_destroy(display);
    return NO;
  }
  if (wl_display_add_socket_fd(display, ufd) < 0) {
    WLog(@"MAIN", @"Error: Failed to add Unix socket FD to Wayland display");
    close(ufd);
    wl_display_destroy(display);
    return NO;
  }
  setenv("WAYLAND_DISPLAY", socket_name, 1);
  WLog(@"MAIN", @"Wayland Unix socket created: %s (cwd: %s)", socket_name,
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
    WLog(@"MAIN", @"Failed to create compositor");
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
  WLog(@"MAIN", @"Exception creating compositor: %@", exception);
  WLog(@"MAIN", @"Call stack: %@", [exception callStackSymbols]);
  if (display) {
    wl_display_destroy(display);
  }
  return NO;
}

// Signal handlers
signal(SIGTERM, raw_signal_handler);
signal(SIGINT, raw_signal_handler);

@try {
  if (![compositor start]) {
    WLog(@"MAIN", @"Failed to start compositor backend");
    wl_display_destroy(display);
    return NO;
  }
} @catch (NSException *exception) {
  WLog(@"MAIN", @"Exception starting compositor: %@", exception);
  WLog(@"MAIN", @"Call stack: %@", [exception callStackSymbols]);
  wl_display_destroy(display);
  return NO;
}

WLog(@"MAIN", @"Compositor running!");

// Launch launcher client app only if enabled
BOOL enableLauncher = NO;
@try {
  WawonaPreferencesManager *prefsManager =
      [WawonaPreferencesManager sharedManager];
  if (prefsManager) {
    enableLauncher = [prefsManager enableLauncher];
  }
} @catch (NSException *exception) {
  WLog(@"MAIN",
       @"Failed to read enableLauncher preference, defaulting to NO: %@",
       exception);
  enableLauncher = NO;
}

if (enableLauncher) {
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        int sv[2];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
          WLog(@"MAIN", @"Failed to create socketpair: %s", strerror(errno));
          return;
        }
        struct wl_client *client = wl_client_create(self.display, sv[0]);
        if (!client) {
          WLog(@"MAIN", @"Failed to create Wayland client on server side");
          close(sv[0]);
          close(sv[1]);
          return;
        }
        WLog(@"MAIN", @"Created in-process Wayland client via socketpair");
        self.launcher_thread = startLauncherClientThread(self, sv[1]);
      });
} else {
  WLog(@"MAIN", @"Single-client mode: in-process launcher client disabled");
}

@try {
  [self setupSettingsButtonIfNeeded];
} @catch (NSException *exception) {
  WLog(@"MAIN", @"Exception setting up settings button: %@", exception);
  // Continue anyway - settings button is optional
}

@
try {
  [self.window makeKeyAndVisible];
} @catch (NSException *exception) {
  WLog(@"MAIN", @"Exception making window key and visible: %@", exception);
  WLog(@"MAIN", @"Call stack: %@", [exception callStackSymbols]);
  // This is critical, but try to continue
}

const char *autorun = getenv("WAWONA_AUTORUN_WAYPIPE");
WLog(@"MAIN", @"WAWONA_AUTORUN_WAYPIPE=%s", autorun ? autorun : "(null)");
if (autorun && strcmp(autorun, "0") != 0) {
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        WawonaPreferencesManager *prefs =
            [WawonaPreferencesManager sharedManager];

        // Check which SSH config to use
        BOOL useSSHConfig = prefs.waypipeUseSSHConfig;
        NSString *sshHost = useSSHConfig ? prefs.sshHost : prefs.waypipeSSHHost;
        NSString *remoteCommand = prefs.waypipeRemoteCommand;

        WLog(@"MAIN", @"Autorun prefs: useSSHConfig=%d host=%@ cmd=%@",
             useSSHConfig, sshHost, remoteCommand);

        // Only autorun if SSH host and remote command are configured
        if (sshHost.length == 0 || remoteCommand.length == 0) {
          WLog(@"MAIN", @"Autorun skipped (missing host or command)");
          return;
        }
        WLog(@"MAIN", @"Autorun launching waypipe");
        [[WawonaWaypipeRunner sharedRunner] launchWaypipe:prefs];
      });
}

WLog(@"MAIN", @"iOS app initialization complete");
return YES;
}

- (void)setupSettingsButtonIfNeeded {
  WLog(@"MAIN", @"setupSettingsButtonIfNeeded called");
  UIView *containerView = self.window.rootViewController.view;
  if (!self.settingsButton) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration
        configurationWithPointSize:24
                            weight:UIImageSymbolWeightRegular];
    UIImage *gearImage =
        [UIImage systemImageNamed:@"gear" withConfiguration:config];

    // Create standard UIButton with custom styling
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.settingsButton setImage:gearImage forState:UIControlStateNormal];
    self.settingsButton.tintColor = [UIColor whiteColor];

    // Add target-action
    [self.settingsButton addTarget:self
                            action:@selector(showSettings:)
                  forControlEvents:UIControlEventTouchUpInside];
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
    WLog(@"MAIN", @"Created settings button");
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
    WLog(@"MAIN", @"Re-added settings button to containerView");
  }
  [containerView bringSubviewToFront:self.settingsButton];

  self.settingsButton.hidden = NO;
  self.settingsButton.alpha = 1.0;

  [containerView layoutIfNeeded];
  WLog(@"MAIN", @"Settings button frame: %@",
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
  WLog(@"MAIN", @"Application will terminate - shutting down gracefully");

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

  WLog(@"MAIN", @"Graceful shutdown complete");
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

@interface WawonaMacAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation WawonaMacAppDelegate

- (void)applicationWillTerminate:(NSNotification *)notification {
  WLog(@"MAIN", @"macOS application will terminate - shutting down gracefully");
  cleanup_on_exit();
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender {
  return NSTerminateNow;
}

// CRITICAL: Prevent macOS from terminating the app when windows close
// The compositor should stay running even with no windows open
// This allows multiple clients to connect/disconnect without killing the
// compositor
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)sender {
  (void)sender;
  WLog(@"MAIN", @"Window closed, but compositor will continue running");
  return NO; // Do NOT terminate when last window closes
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    // Set process name for Menu Bar
    [[NSProcessInfo processInfo] setProcessName:@"Wawona"];

    // Set default output behavior
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
      if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-v") == 0) {
#ifdef WAWONA_VERSION
        printf("Wawona v%s\n", WAWONA_VERSION);
#else
        printf("Wawona unknown\n");
#endif

        // Use sw_vers for clean macOS version output
        FILE *sw_vers_f = popen("sw_vers -productVersion", "r");
        if (sw_vers_f) {
          char ver_buf[64];
          if (fgets(ver_buf, sizeof(ver_buf), sw_vers_f)) {
            size_t len = strlen(ver_buf);
            if (len > 0 && ver_buf[len - 1] == '\n')
              ver_buf[len - 1] = '\0';
            printf("macOS v%s\n", ver_buf);
          }
          pclose(sw_vers_f);
        } else {
          // Fallback to NSProcessInfo
          NSOperatingSystemVersion v =
              [[NSProcessInfo processInfo] operatingSystemVersion];
          printf("macOS v%ld.%ld.%ld\n", (long)v.majorVersion,
                 (long)v.minorVersion, (long)v.patchVersion);
        }

        // Use uname for architecture
        FILE *uname_f = popen("uname -m", "r");
        if (uname_f) {
          char arch_buf[64];
          if (fgets(arch_buf, sizeof(arch_buf), uname_f)) {
            printf("%s", arch_buf); // uname -m includes newline
          }
          pclose(uname_f);
        } else {
#if defined(__arm64__) || defined(__aarch64__)
          printf("arm64\n");
#else
          printf("x86_64\n");
#endif
        }
        return 0;
      }
    }

    WLog(@"MAIN", @"Wawona - Wayland Compositor for macOS (Debug Mode)");
    WLog(@"MAIN", @"macOS Version: %@",
         [[NSProcessInfo processInfo] operatingSystemVersionString]);

    // Disable automatic termination
    [[NSProcessInfo processInfo] disableAutomaticTermination:@"KeepAlive"];
    [[NSProcessInfo processInfo] disableSuddenTermination];

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
        WLog(@"MAIN",
             @"Found existing Wawona instance (PID %d), terminating...",
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
          WLog(@"MAIN", @"Existing Wawona did not terminate gracefully, force "
                        @"killing...");
          [app forceTerminate];
          // Wait a bit more
          usleep(500000); // 500ms
        }
        WLog(@"MAIN", @"Previous Wawona instance terminated");
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
            WLog(@"MAIN", @"Cleaning up stale Wayland socket: %@", socketPath);
            [staleFm removeItemAtPath:socketPath error:nil];
            // Also remove lock file if present
            NSString *lockPath = [socketPath stringByAppendingString:@".lock"];
            [staleFm removeItemAtPath:lockPath error:nil];
            WLog(@"MAIN", @"Cleaned up lock file: %@", lockPath);
          }
          close(testFd);
        }
      }
    }

    // Set up NSApplication
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // Set delegate for cleanup
    WawonaMacAppDelegate *delegate = [[WawonaMacAppDelegate alloc] init];
    [NSApp setDelegate:delegate];

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

    // Wawona is now headless - no main compositor window
    // Only Wayland client windows will be created
    NSWindow *window = nil;

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
      WLog(@"MAIN", @"Using XDG_RUNTIME_DIR: %@", runtimePath);
      // Ensure directory exists with correct permissions (0700)
      NSDictionary *attrs = @{NSFilePosixPermissions : @0700};
      NSError *error = nil;
      BOOL isDir = NO;
      if (![fm fileExistsAtPath:runtimePath isDirectory:&isDir]) {
        if (![fm createDirectoryAtPath:runtimePath
                withIntermediateDirectories:YES
                                 attributes:attrs
                                      error:&error]) {
          WLog(@"MAIN", @"Failed to create XDG_RUNTIME_DIR at %@: %@",
               runtimePath, error);
          return -1;
        }
        WLog(@"MAIN", @"Created XDG_RUNTIME_DIR at %@", runtimePath);
      } else if (!isDir) {
        WLog(@"MAIN", @"XDG_RUNTIME_DIR exists but is not a directory: %@",
             runtimePath);
        return -1;
      } else {
        // Check permissions/ownership if possible, or just ensure it's writable
        if (![fm isWritableFileAtPath:runtimePath]) {
          WLog(@"MAIN", @"XDG_RUNTIME_DIR is not writable: %@", runtimePath);
          return -1;
        }
      }
    } else {
      WLog(@"MAIN", @"Failed to determine XDG_RUNTIME_DIR");
      return -1;
    }

    // Create Wayland display
    // ============================================================================
    // RUST COMPOSITOR INITIALIZATION (macOS)
    // ============================================================================

    WLog(@"MAIN", @"Starting Rust-based Wawona compositor (macOS)...");

    NSScreen *mainScreen = [NSScreen mainScreen];
    CGSize screenSize = mainScreen.frame.size;
    CGFloat scale = mainScreen.backingScaleFactor;

    WawonaCompositorBridge *rustCompositor =
        [WawonaCompositorBridge sharedBridge];
    [rustCompositor setOutputWidth:(uint32_t)screenSize.width
                            height:(uint32_t)screenSize.height
                             scale:(float)scale];

    BOOL started = [rustCompositor startWithSocketName:@"wayland-0"];
    if (!started) {
      WLog(@"MAIN", @"Failed to start Rust compositor");
      return 1;
    }

    NSString *socketPath = [rustCompositor socketPath];
    NSString *socketName = [rustCompositor socketName];

    WLog(@"MAIN", @"Rust compositor started successfully (macOS)");
    WLog(@"MAIN", @"   Socket: %@", socketPath);
    WLog(@"MAIN", @"   WAYLAND_DISPLAY=%@", socketName);
    WLog(@"MAIN", @"   XDG_CURRENT_DESKTOP=Wawona");

    setenv("WAYLAND_DISPLAY", [socketName UTF8String], 1);
    setenv("XDG_CURRENT_DESKTOP", "Wawona", 1);

    // Setup signal handlers
    atexit(cleanup_on_exit);
    setup_signal_sources();
    signal(SIGSEGV, crash_handler);
    signal(SIGABRT, crash_handler);
    signal(SIGBUS, crash_handler);
    signal(SIGILL, crash_handler);

    WLog(@"MAIN", @"Rust Compositor running!");

    [NSApp run];

    // Cleanup
    [rustCompositor stop];
  }
  return 0;
}

#endif
