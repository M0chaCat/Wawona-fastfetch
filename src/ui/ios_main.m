#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "apple_backend.h"
#import "Settings/WawonaPreferences.h"
#import "About/WawonaAboutPanel.h"
#include <wayland-server-core.h>
#include <signal.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

static struct wl_display *g_display = NULL;
static MacOSCompositor *g_compositor = NULL;

// Signal handler for graceful shutdown
static void signal_handler(int sig) {
    (void)sig;
    NSLog(@"\n🛑 Received signal %d, shutting down gracefully...", sig);
    
    // Use compositor's stop method which properly disconnects all clients
    if (g_compositor) {
        [g_compositor stop];
        g_compositor = nil;
    }
    
    // Clear global display reference (compositor.stop already destroyed it)
    g_display = NULL;
    
    // Don't call exit() immediately - let the app terminate naturally
    // This prevents crash reports on iOS/macOS
    // The signal will be handled by the system and the app will terminate gracefully
}


@interface WawonaAppDelegate : NSObject <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) MacOSCompositor *compositor;
@property (nonatomic, assign) struct wl_display *display;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIView *chromeOverlay;
@property (nonatomic, strong) UIWindow *chromeWindow;
@end

@implementation WawonaAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    
    NSLog(@"🎯 Wawona - Wayland Compositor for iOS");
    NSLog(@"   Using libwayland-server (no WLRoots)");
    NSLog(@"   Rendering with Metal");
    NSLog(@"");
    
    NSString *runtimePath = nil;
    NSFileManager *fm = [NSFileManager defaultManager];

#if TARGET_OS_SIMULATOR
    runtimePath = @"/tmp/wawona-ios";
    NSError *tmpError = nil;
    BOOL createdTmp = [fm createDirectoryAtPath:runtimePath
                   withIntermediateDirectories:YES
                                    attributes:@{NSFilePosixPermissions: @0700}
                                         error:&tmpError];
    if (!(createdTmp || [fm fileExistsAtPath:runtimePath])) {
        runtimePath = nil;
    }
#endif

    if (!runtimePath) {
        NSURL *groupURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.com.aspauldingcode.Wawona"];
        if (groupURL) {
            runtimePath = [groupURL.path stringByAppendingPathComponent:@"w"];
            NSError *groupError = nil;
            BOOL createdGroup = [fm createDirectoryAtPath:runtimePath
                           withIntermediateDirectories:YES
                                            attributes:@{NSFilePosixPermissions: @0700}
                                                 error:&groupError];
            if (!(createdGroup || [fm fileExistsAtPath:runtimePath])) {
                runtimePath = nil;
            }
        }
    }

    if (!runtimePath) {
        NSString *tmpDir = NSTemporaryDirectory();
        if (tmpDir) {
            runtimePath = tmpDir;
        } else {
            return NO;
        }
    }

    setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
    setenv("WAYLAND_DISPLAY", "wayland-0", 1);
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    NSLog(@"   Using XDG_RUNTIME_DIR: %@", runtimePath);
    NSLog(@"   Using WAYLAND_DISPLAY: wayland-0");
    
    // Verify directory exists and is writable
    BOOL isDir = NO;
    BOOL exists = [fm fileExistsAtPath:runtimePath isDirectory:&isDir];
    if (!exists || !isDir) {
        NSLog(@"❌ XDG_RUNTIME_DIR does not exist or is not a directory: %@", runtimePath);
        return NO;
    }
    if (![fm isWritableFileAtPath:runtimePath]) {
        NSLog(@"❌ XDG_RUNTIME_DIR is not writable: %@", runtimePath);
        return NO;
    }
    
    // Create Wayland display
    struct wl_display *display = wl_display_create();
    if (!display) {
        NSLog(@"❌ Failed to create wl_display");
        return NO;
    }
    
    // Add Wayland socket (Unix domain socket) with explicit short name
    // Use wl_display_add_socket() with explicit name instead of wl_display_add_socket_auto()
    // to ensure we use the short socket name
    const char *wayland_display_env = getenv("WAYLAND_DISPLAY");
    const char *socket_name = wayland_display_env ? wayland_display_env : "wayland-0";
    
    // Check path length
    NSString *socketName = [NSString stringWithUTF8String:socket_name];
    NSString *fullSocketPath = [runtimePath stringByAppendingPathComponent:socketName];
    NSUInteger pathLength = [fullSocketPath lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (pathLength > 107) { // 108 - 1 for null terminator
        NSLog(@"⚠️ Warning: Socket path may exceed 108-byte limit: %@ (%lu bytes)", 
              fullSocketPath, (unsigned long)pathLength);
    }
    int ret = wl_display_add_socket(display, socket_name);
    const char *socket = socket_name;
    if (ret < 0) {
        NSLog(@"❌ Failed to create WAYLAND_DISPLAY socket");
        NSLog(@"   XDG_RUNTIME_DIR: %s", runtime_dir);
        NSLog(@"   Socket name: %s", socket_name);
        NSLog(@"   Full path: %@", fullSocketPath);
        NSLog(@"   Path length: %lu bytes", (unsigned long)[fullSocketPath lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
        NSLog(@"   Directory exists: %@", exists ? @"yes" : @"no");
        NSLog(@"   Directory writable: %@", [fm isWritableFileAtPath:runtimePath] ? @"yes" : @"no");
        NSLog(@"   Error: %s", strerror(errno));
        wl_display_destroy(display);
        return NO;
    }
    
    // Verify socket file was created
    NSString *socketPath = [runtimePath stringByAppendingPathComponent:[NSString stringWithUTF8String:socket]];
    if (![fm fileExistsAtPath:socketPath]) {
        NSLog(@"⚠️ Socket file not found immediately after creation: %@", socketPath);
        NSLog(@"   This may be normal - socket will be created when event loop starts");
    } else {
        NSLog(@"✅ Wayland socket file created: %@", socketPath);
    }
    
    NSLog(@"✅ Wayland socket created: %s", socket);
    NSLog(@"   Clients can connect with: export WAYLAND_DISPLAY=%s", socket);
    NSLog(@"");
    
    // Store globals for signal handler
    g_display = display;
    self.display = display;
    
    // Create iOS window - explicitly use main screen bounds to ensure correct sizing
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGRect screenBounds = mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:screenBounds];
    self.window.screen = mainScreen; // Explicitly set screen
    self.window.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0];
    
    NSLog(@"🔵 Window created: screen.bounds=%@, window.frame=%@",
          NSStringFromCGRect(screenBounds), NSStringFromCGRect(self.window.frame));
    
    // Create compositor backend
    MacOSCompositor *compositor = [[MacOSCompositor alloc] initWithDisplay:display window:self.window];
    g_compositor = compositor;
    self.compositor = compositor;
    
    // Set up signal handlers for graceful shutdown
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    
    if (![compositor start]) {
        NSLog(@"❌ Failed to start compositor backend");
        wl_display_destroy(display);
        return NO;
    }
    
    NSLog(@"🚀 Compositor running!");
    NSLog(@"   Ready for Wayland clients to connect");
    NSLog(@"");
    
    // Create root view controller - let UIKit handle view sizing automatically
    UIViewController *rootViewController = [[UIViewController alloc] init];
    // Don't manually set frame - let UIKit handle it with proper autoresizing
    rootViewController.view.backgroundColor = [UIColor clearColor];
    // Ensure the view properly fills the window using autoresizing masks
    rootViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.window.rootViewController = rootViewController;
    
    [self teardownChromeWindowIfPresent];
    [self setupChromeOverlayIfNeeded];
    [self setupSettingsButtonIfNeeded];
    
    // Make window key and visible
    [self.window makeKeyAndVisible];
    
    // Force layout update after window is visible to ensure proper sizing
    // This must happen after makeKeyAndVisible so the window is connected to the screen
    [rootViewController.view setNeedsLayout];
    [rootViewController.view layoutIfNeeded];
    
    // Update compositor output size after layout to ensure correct dimensions
    // Use a small delay to ensure the compositor view has been added to the hierarchy
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.compositor) {
            CGSize viewSize = rootViewController.view.bounds.size;
            [self.compositor updateOutputSize:viewSize];
            NSLog(@"🔵 Updated compositor output size to: %.0fx%.0f", viewSize.width, viewSize.height);
        }
    });
    
    // Log screen information for debugging
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGRect screenBounds = mainScreen.bounds;
    CGFloat screenScale = mainScreen.scale;
    NSLog(@"📱 Screen info: bounds=%@, scale=%.0fx, nativeSize=%.0fx%.0f",
          NSStringFromCGRect(screenBounds), screenScale,
          screenBounds.size.width * screenScale, screenBounds.size.height * screenScale);
    NSLog(@"   Window bounds: %@", NSStringFromCGRect(self.window.bounds));
    NSLog(@"   Root view bounds: %@", NSStringFromCGRect(rootViewController.view.bounds));
    
    return YES;
}

-(void)setupSettingsButtonIfNeeded {
    if (!self.chromeOverlay) {
        [self setupChromeOverlayIfNeeded];
    }
    if (!self.settingsButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *gearImage = [UIImage systemImageNamed:@"gearshape.fill"];
        [button setImage:gearImage forState:UIControlStateNormal];
        button.tintColor = [UIColor whiteColor];
        button.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
        button.layer.cornerRadius = 25.0;
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.layer.shadowOpacity = 0.5;
        button.layer.shadowRadius = 4.0;
        [button addTarget:self action:@selector(showSettings:) forControlEvents:UIControlEventTouchUpInside];
        self.settingsButton = button;
        [self.chromeOverlay addSubview:self.settingsButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.settingsButton.topAnchor constraintEqualToAnchor:self.chromeOverlay.safeAreaLayoutGuide.topAnchor constant:20],
            [self.settingsButton.trailingAnchor constraintEqualToAnchor:self.chromeOverlay.safeAreaLayoutGuide.trailingAnchor constant:-20],
            [self.settingsButton.widthAnchor constraintEqualToConstant:50],
            [self.settingsButton.heightAnchor constraintEqualToConstant:50],
        ]];
    } else if (self.settingsButton.superview != self.chromeOverlay) {
        [self.settingsButton removeFromSuperview];
        [self.chromeOverlay addSubview:self.settingsButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.settingsButton.topAnchor constraintEqualToAnchor:self.chromeOverlay.safeAreaLayoutGuide.topAnchor constant:20],
            [self.settingsButton.trailingAnchor constraintEqualToAnchor:self.chromeOverlay.safeAreaLayoutGuide.trailingAnchor constant:-20],
            [self.settingsButton.widthAnchor constraintEqualToConstant:50],
            [self.settingsButton.heightAnchor constraintEqualToConstant:50],
        ]];
    }
}

- (void)teardownChromeWindowIfPresent {
    if (self.chromeWindow) {
        self.chromeWindow.hidden = YES;
        self.chromeWindow.rootViewController = nil;
        self.chromeWindow = nil;
    }
}

- (void)setupChromeOverlayIfNeeded {
    UIView *targetView = self.window.rootViewController ? self.window.rootViewController.view : nil;
    if (targetView) {
        if (self.chromeOverlay && self.chromeOverlay != targetView) {
            [self.chromeOverlay removeFromSuperview];
        }
        self.chromeOverlay = targetView;
    } else {
        self.chromeOverlay = self.window;
    }
}

- (void)showSettings:(id)sender {
    WawonaPreferences *prefs = [[WawonaPreferences alloc] init];
    
    // Ensure we have a root view controller
    UIViewController *rootViewController = self.window.rootViewController;
    if (!rootViewController) {
        rootViewController = [[UIViewController alloc] init];
        rootViewController.view = [[UIView alloc] init];
        self.window.rootViewController = rootViewController;
    }
    
    // Present settings modally
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:prefs];
    navController.modalPresentationStyle = UIModalPresentationPageSheet;
    
    // If we're already presenting something, dismiss it first
    if (rootViewController.presentedViewController) {
        [rootViewController dismissViewControllerAnimated:NO completion:^{
            [rootViewController presentViewController:navController animated:YES completion:nil];
        }];
    } else {
        [rootViewController presentViewController:navController animated:YES completion:nil];
    }
}

- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    NSLog(@"⚠️ Application will resign active");
    // Ensure settings are persisted
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    NSLog(@"⚠️ Application entered background");
    // Ensure settings are persisted when app enters background
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    NSLog(@"⚠️ Application will enter foreground");
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    NSLog(@"✅ Application became active");
    
    // Force layout update to ensure views are properly sized
    if (self.window && self.window.rootViewController) {
        UIView *rootView = self.window.rootViewController.view;
        [rootView setNeedsLayout];
        [rootView layoutIfNeeded];
        
        // Update compositor output size if compositor exists
        if (self.compositor) {
            [self.compositor updateOutputSize:rootView.bounds.size];
        }
        
        NSLog(@"   Window bounds after active: %@", NSStringFromCGRect(self.window.bounds));
        NSLog(@"   Root view bounds after active: %@", NSStringFromCGRect(rootView.bounds));
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    NSLog(@"👋 Application will terminate - shutting down gracefully");
    
    // Ensure settings are persisted before termination
    [[NSUserDefaults standardUserDefaults] synchronize];
    
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
    (void)argc;
    (void)argv;
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([WawonaAppDelegate class]));
    }
}
