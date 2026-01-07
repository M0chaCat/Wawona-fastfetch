#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Preferences keys
extern NSString *const kWawonaPrefsUniversalClipboard;
extern NSString *const kWawonaPrefsForceServerSideDecorations;
extern NSString *const kWawonaPrefsAutoRetinaScaling; // Legacy - use AutoScale
extern NSString *const kWawonaPrefsAutoScale;         // New unified key
extern NSString
    *const kWawonaPrefsColorSyncSupport; // Legacy - use ColorOperations
extern NSString *const kWawonaPrefsColorOperations; // New unified key
extern NSString *const kWawonaPrefsNestedCompositorsSupport;
extern NSString *const kWawonaPrefsUseMetal4ForNested; // Deprecated - removed
extern NSString *const kWawonaPrefsRenderMacOSPointer;
extern NSString *const kWawonaPrefsMultipleClients;
extern NSString *const kWawonaPrefsEnableLauncher;
extern NSString *const kWawonaPrefsSwapCmdAsCtrl; // Legacy - use SwapCmdWithAlt
extern NSString *const kWawonaPrefsSwapCmdWithAlt; // New unified key
extern NSString *const kWawonaPrefsTouchInputType;
extern NSString
    *const kWawonaPrefsWaypipeRSSupport; // Deprecated - always enabled
extern NSString
    *const kWawonaPrefsEnableTCPListener; // Deprecated - always enabled
extern NSString *const kWawonaPrefsTCPListenerPort;
extern NSString *const kWawonaPrefsWaylandSocketDir;
extern NSString *const kWawonaPrefsWaylandDisplayNumber;
extern NSString *const kWawonaPrefsEnableVulkanDrivers;
extern NSString *const kWawonaPrefsEnableEGLDrivers;
extern NSString *const kWawonaPrefsEnableDmabuf;
extern NSString *const kWawonaPrefsRespectSafeArea;
// Waypipe configuration keys
extern NSString *const kWawonaPrefsWaypipeDisplay;
extern NSString *const kWawonaPrefsWaypipeSocket;
extern NSString *const kWawonaPrefsWaypipeCompress;
extern NSString *const kWawonaPrefsWaypipeCompressLevel;
extern NSString *const kWawonaPrefsWaypipeThreads;
extern NSString *const kWawonaPrefsWaypipeVideo;
extern NSString *const kWawonaPrefsWaypipeVideoEncoding;
extern NSString *const kWawonaPrefsWaypipeVideoDecoding;
extern NSString *const kWawonaPrefsWaypipeVideoBpf;
extern NSString *const kWawonaPrefsWaypipeSSHEnabled;
extern NSString *const kWawonaPrefsWaypipeSSHHost;
extern NSString *const kWawonaPrefsWaypipeSSHUser;
extern NSString *const kWawonaPrefsWaypipeSSHBinary;
extern NSString *const kWawonaPrefsWaypipeSSHAuthMethod;
extern NSString *const kWawonaPrefsWaypipeSSHKeyPath;
extern NSString *const kWawonaPrefsWaypipeSSHKeyPassphrase;
extern NSString *const kWawonaPrefsWaypipeSSHPassword;
extern NSString *const kWawonaPrefsWaypipeRemoteCommand;
extern NSString *const kWawonaPrefsWaypipeCustomScript;
extern NSString *const kWawonaPrefsWaypipeDebug;
extern NSString *const kWawonaPrefsWaypipeNoGpu;
extern NSString *const kWawonaPrefsWaypipeOneshot;
extern NSString *const kWawonaPrefsWaypipeUnlinkSocket;
extern NSString *const kWawonaPrefsWaypipeLoginShell;
extern NSString *const kWawonaPrefsWaypipeVsock;
extern NSString *const kWawonaPrefsWaypipeXwls;
extern NSString *const kWawonaPrefsWaypipeTitlePrefix;
extern NSString *const kWawonaPrefsWaypipeSecCtx;
// SSH configuration keys (separate from Waypipe)
extern NSString *const kWawonaPrefsSSHHost;
extern NSString *const kWawonaPrefsSSHUser;
extern NSString *const kWawonaPrefsSSHAuthMethod;
extern NSString *const kWawonaPrefsSSHPassword;
extern NSString *const kWawonaPrefsSSHKeyPath;
extern NSString *const kWawonaPrefsSSHKeyPassphrase;
extern NSString *const kWawonaPrefsWaypipeUseSSHConfig;
extern NSString *const kWawonaForceSSDChangedNotification;

@interface WawonaPreferencesManager : NSObject

+ (instancetype)sharedManager;

// Universal Clipboard
- (BOOL)universalClipboardEnabled;
- (void)setUniversalClipboardEnabled:(BOOL)enabled;

// Window Decorations
- (BOOL)forceServerSideDecorations;
- (void)setForceServerSideDecorations:(BOOL)enabled;

// Display
- (BOOL)autoRetinaScalingEnabled; // Legacy - use autoScale
- (void)setAutoRetinaScalingEnabled:(BOOL)enabled;
- (BOOL)autoScale; // New unified method
- (void)setAutoScale:(BOOL)enabled;
- (BOOL)respectSafeArea;
- (void)setRespectSafeArea:(BOOL)enabled;

// Color Management
- (BOOL)colorSyncSupportEnabled; // Legacy - use colorOperations
- (void)setColorSyncSupportEnabled:(BOOL)enabled;
- (BOOL)colorOperations; // New unified method
- (void)setColorOperations:(BOOL)enabled;

// Nested Compositors
- (BOOL)nestedCompositorsSupportEnabled;
- (void)setNestedCompositorsSupportEnabled:(BOOL)enabled;
- (BOOL)useMetal4ForNested;
- (void)setUseMetal4ForNested:(BOOL)enabled;

// Input
- (BOOL)renderMacOSPointer;
- (void)setRenderMacOSPointer:(BOOL)enabled;
- (BOOL)swapCmdAsCtrl; // Legacy - use swapCmdWithAlt
- (void)setSwapCmdAsCtrl:(BOOL)enabled;
- (BOOL)swapCmdWithAlt; // New unified method
- (void)setSwapCmdWithAlt:(BOOL)enabled;
- (NSString *)touchInputType;
- (void)setTouchInputType:(NSString *)type;

// Client Management
- (BOOL)multipleClientsEnabled;
- (void)setMultipleClientsEnabled:(BOOL)enabled;

- (BOOL)enableLauncher;
- (void)setEnableLauncher:(BOOL)enabled;

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

// Dmabuf Support (IOSurface-backed)
- (BOOL)dmabufEnabled;
- (void)setDmabufEnabled:(BOOL)enabled;

// Waypipe Configuration
- (NSString *)waypipeDisplay;
- (void)setWaypipeDisplay:(NSString *)display;
- (NSString *)waypipeSocket;
- (void)setWaypipeSocket:(NSString *)socket;
- (NSString *)waypipeCompress;
- (void)setWaypipeCompress:(NSString *)compress;
- (NSString *)waypipeCompressLevel;
- (void)setWaypipeCompressLevel:(NSString *)level;
- (NSString *)waypipeThreads;
- (void)setWaypipeThreads:(NSString *)threads;
- (NSString *)waypipeVideo;
- (void)setWaypipeVideo:(NSString *)video;
- (NSString *)waypipeVideoEncoding;
- (void)setWaypipeVideoEncoding:(NSString *)encoding;
- (NSString *)waypipeVideoDecoding;
- (void)setWaypipeVideoDecoding:(NSString *)decoding;
- (NSString *)waypipeVideoBpf;
- (void)setWaypipeVideoBpf:(NSString *)bpf;
- (BOOL)waypipeSSHEnabled;
- (void)setWaypipeSSHEnabled:(BOOL)enabled;
- (NSString *)waypipeSSHHost;
- (void)setWaypipeSSHHost:(NSString *)host;
- (NSString *)waypipeSSHUser;
- (void)setWaypipeSSHUser:(NSString *)user;
- (NSString *)waypipeSSHBinary;
- (void)setWaypipeSSHBinary:(NSString *)binary;
- (NSInteger)waypipeSSHAuthMethod; // 0 = password, 1 = public key
- (void)setWaypipeSSHAuthMethod:(NSInteger)method;
- (NSString *)waypipeSSHKeyPath;
- (void)setWaypipeSSHKeyPath:(NSString *)keyPath;
- (NSString *)waypipeSSHKeyPassphrase;
- (void)setWaypipeSSHKeyPassphrase:(NSString *)passphrase;
- (NSString *)waypipeSSHPassword;
- (void)setWaypipeSSHPassword:(NSString *)password;
- (NSString *)waypipeRemoteCommand;
- (void)setWaypipeRemoteCommand:(NSString *)command;
- (NSString *)waypipeCustomScript;
- (void)setWaypipeCustomScript:(NSString *)script;
- (BOOL)waypipeDebug;
- (void)setWaypipeDebug:(BOOL)enabled;
- (BOOL)waypipeNoGpu;
- (void)setWaypipeNoGpu:(BOOL)enabled;
- (BOOL)waypipeOneshot;
- (void)setWaypipeOneshot:(BOOL)enabled;
- (BOOL)waypipeUnlinkSocket;
- (void)setWaypipeUnlinkSocket:(BOOL)enabled;
- (BOOL)waypipeLoginShell;
- (void)setWaypipeLoginShell:(BOOL)enabled;
- (BOOL)waypipeVsock;
- (void)setWaypipeVsock:(BOOL)enabled;
- (BOOL)waypipeXwls;
- (void)setWaypipeXwls:(BOOL)enabled;
- (NSString *)waypipeTitlePrefix;
- (void)setWaypipeTitlePrefix:(NSString *)prefix;
- (NSString *)waypipeSecCtx;
- (void)setWaypipeSecCtx:(NSString *)secCtx;
- (BOOL)waypipeUseSSHConfig;
- (void)setWaypipeUseSSHConfig:(BOOL)enabled;

// SSH Configuration (separate from Waypipe)
- (NSString *)sshHost;
- (void)setSshHost:(NSString *)host;
- (NSString *)sshUser;
- (void)setSshUser:(NSString *)user;
- (NSInteger)sshAuthMethod; // 0 = password, 1 = public key
- (void)setSshAuthMethod:(NSInteger)method;
- (NSString *)sshPassword;
- (void)setSshPassword:(NSString *)password;
- (NSString *)sshKeyPath;
- (void)setSshKeyPath:(NSString *)keyPath;
- (NSString *)sshKeyPassphrase;
- (void)setSshKeyPassphrase:(NSString *)passphrase;

// Reset to defaults
- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
