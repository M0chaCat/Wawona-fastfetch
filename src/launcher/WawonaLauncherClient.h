// Wawona Launcher Client - Header
// A GUI Launcher for bundled Wayland client applications
// Supports iOS, macOS, and Android

#import <Foundation/Foundation.h>
#include <pthread.h>

@class WawonaAppDelegate;

// Forward declare wayland-client types
struct wl_display;

// Application metadata for launcher display
@interface WawonaLauncherApp : NSObject
@property (nonatomic, strong) NSString *appId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, strong) NSString *iconPath;
@property (nonatomic, strong) NSString *description;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, assign) BOOL isBlacklisted;
@end

// Start the launcher client thread with a pre-connected socket file descriptor
pthread_t startLauncherClientThread(WawonaAppDelegate *delegate, int client_fd);

// Get the client display (returns wayland-client wl_display*, not wayland-server)
struct wl_display *getLauncherClientDisplay(WawonaAppDelegate *delegate);

// Disconnect and cleanup the launcher client
void disconnectLauncherClient(WawonaAppDelegate *delegate);

// Get list of available applications (excluding blacklisted)
NSArray<WawonaLauncherApp *> *getLauncherApplications(void);

// Launch an application by app ID
BOOL launchLauncherApplication(NSString *appId);

// Refresh the application list
void refreshLauncherApplicationList(void);

