#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Preferences keys
extern NSString * const kWawonaPrefsUniversalClipboard;
extern NSString * const kWawonaPrefsForceServerSideDecorations;
extern NSString * const kWawonaPrefsAutoRetinaScaling;
extern NSString * const kWawonaPrefsColorSyncSupport;
extern NSString * const kWawonaPrefsNestedCompositorsSupport;
extern NSString * const kWawonaPrefsUseMetal4ForNested;
extern NSString * const kWawonaPrefsRenderMacOSPointer;
extern NSString * const kWawonaPrefsMultipleClients;
extern NSString * const kWawonaPrefsSwapCmdAsCtrl;
extern NSString * const kWawonaPrefsWaypipeRSSupport;
extern NSString * const kWawonaPrefsEnableTCPListener;
extern NSString * const kWawonaPrefsTCPListenerPort;
extern NSString * const kWawonaPrefsWaylandSocketDir;
extern NSString * const kWawonaPrefsWaylandDisplayNumber;
extern NSString * const kWawonaPrefsEnableVulkanDrivers;
extern NSString * const kWawonaPrefsEnableEGLDrivers;

@interface WawonaPreferencesManager : NSObject

+ (instancetype)sharedManager;

// Universal Clipboard
- (BOOL)universalClipboardEnabled;
- (void)setUniversalClipboardEnabled:(BOOL)enabled;

// Window Decorations
- (BOOL)forceServerSideDecorations;
- (void)setForceServerSideDecorations:(BOOL)enabled;

// Display
- (BOOL)autoRetinaScalingEnabled;
- (void)setAutoRetinaScalingEnabled:(BOOL)enabled;

// Color Management
- (BOOL)colorSyncSupportEnabled;
- (void)setColorSyncSupportEnabled:(BOOL)enabled;

// Nested Compositors
- (BOOL)nestedCompositorsSupportEnabled;
- (void)setNestedCompositorsSupportEnabled:(BOOL)enabled;
- (BOOL)useMetal4ForNested;
- (void)setUseMetal4ForNested:(BOOL)enabled;

// Input
- (BOOL)renderMacOSPointer;
- (void)setRenderMacOSPointer:(BOOL)enabled;
- (BOOL)swapCmdAsCtrl;
- (void)setSwapCmdAsCtrl:(BOOL)enabled;

// Client Management
- (BOOL)multipleClientsEnabled;
- (void)setMultipleClientsEnabled:(BOOL)enabled;

// Waypipe
- (BOOL)waypipeRSSupportEnabled;
- (void)setWaypipeRSSupportEnabled:(BOOL)enabled;

// Network / Remote Access
- (BOOL)enableTCPListener;
- (void)setEnableTCPListener:(BOOL)enabled;
- (NSInteger)tcpListenerPort;
- (void)setTCPListenerPort:(NSInteger)port;

// Wayland Configuration
- (NSString *)waylandSocketDir;
- (void)setWaylandSocketDir:(NSString *)dir;
- (NSInteger)waylandDisplayNumber;
- (void)setWaylandDisplayNumber:(NSInteger)number;

// Rendering Backend Flags
- (BOOL)vulkanDriversEnabled;
- (void)setVulkanDriversEnabled:(BOOL)enabled;
- (BOOL)eglDriversEnabled;
- (void)setEglDriversEnabled:(BOOL)enabled;

// Reset to defaults
- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
