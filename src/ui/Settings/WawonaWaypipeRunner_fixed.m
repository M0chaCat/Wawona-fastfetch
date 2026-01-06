#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// Import Foundation for NSExtension API
#import <UIKit/UIKit.h>
// HIAHKernel handles process spawning via extension
#import <HIAHKernel/HIAHKernel.h>

// We'll use dynamic lookup for NSExtension to avoid linking issues and ensure
// correct framework loading
@protocol NSExtensionProtocol <NSObject>
- (void)beginExtensionRequestWithInputItems:(NSArray *)inputItems
                                 completion:
                                     (void (^)(NSUUID *requestIdentifier))
                                         completion;
// Helper for dynamic lookup of class method (treated as instance method on
// class object)
- (void)extensionsWithMatchingAttributes:(NSDictionary *)attributes
                              completion:
                                  (void (^)(NSArray *extensions,
                                            NSError *error))completionHandler;
@end

#else
// macOS
#import <AppKit/AppKit.h>
#endif

extern char **environ;

// Emoji prefix/suffix for waypipe logs to make them visually distinct
#define WAYPIPE_EMOJI @"🇺🇸"

@interface WawonaWaypipeRunner ()
@property(nonatomic, assign) pid_t currentPid;
@property(nonatomic, assign) int stdinWriteFd;          // For password input
@property(nonatomic, strong) NSFileHandle *stdinHandle; // For extension input
@property(nonatomic, strong)
    NSString *sshPassword; // Store password for prompt handling
@property(nonatomic, strong) id currentExtension; // Keep extension alive
@property(nonatomic, strong) NSDate *lastWaypipeActivityAt;
@property(nonatomic, strong) dispatch_source_t extensionHangMonitor;
@property(nonatomic, strong) NSDictionary *lastWaypipeEnv;
@property(nonatomic, strong) NSArray<NSString *> *lastWaypipeArgs;
- (NSString *)effectiveRemoteCommand:(WawonaPreferencesManager *)prefs;
@end

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@implementation WawonaWaypipeRunner

+ (instancetype)sharedRunner {
  static WawonaWaypipeRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _currentPid = 0;
    _stdinWriteFd = -1;
    _stdinHandle = nil;
    _sshPassword = nil;
    _currentExtension = nil;
    _lastWaypipeActivityAt = nil;
    _extensionHangMonitor = nil;
    _lastWaypipeEnv = nil;
    _lastWaypipeArgs = nil;
  }
  return self;
}

- (NSString *)findSSHBinary {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

  // For --ssh-bin, waypipe needs the actual executable (not .dylib)
  // waypipe will spawn SSH as a real process with pipes
  NSArray<NSString *> *candidates = @[
    [bundlePath stringByAppendingPathComponent:@"bin/ssh"],
    [bundlePath stringByAppendingPathComponent:@"ssh"],
    // Fallback to .dylib only if executable not found (shouldn't happen)
    [bundlePath stringByAppendingPathComponent:@"bin/ssh.dylib"],
    [bundlePath stringByAppendingPathComponent:@"ssh.dylib"],
  ];

  for (NSString *candidate in candidates) {
    if ([fm fileExistsAtPath:candidate]) {
      // Prefer executable files, but if not code-signed, still return it
      // The posix_spawn hook will handle .dylib -> executable conversion if
      // needed
      if ([candidate hasSuffix:@".dylib"]) {
        // Check if corresponding executable exists
        NSString *executableCandidate =
            [candidate stringByReplacingOccurrencesOfString:@".dylib"
                                             withString:@""];
        if ([fm fileExistsAtPath:executableCandidate]) {
          return executableCandidate;
        }
      }
      return candidate;
    }
  }

  NSLog(@"%@ [Runner] SSH binary not found in bundle", WAYPIPE_EMOJI);
  return nil;
}

- (NSString *)findWaypipeBinary {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

  NSArray<NSString *> *candidates = @[
    [bundlePath stringByAppendingPathComponent:@"bin/waypipe"],
    [bundlePath stringByAppendingPathComponent:@"waypipe"],
    [bundlePath stringByAppendingPathComponent:@"Contents/MacOS/waypipe"],
    [bundlePath stringByAppendingPathComponent:@"Contents/Resources/bin/waypipe"],
    [bundlePath stringByAppendingPathComponent:@"waypipe.bin"],
    [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:nil],
    [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:@"bin"],
  ];

  for (NSString *candidate in candidates) {
    if ([fm fileExistsAtPath:candidate]) {
      NSLog(@"%@ [Runner] Found waypipe at: %@", WAYPIPE_EMOJI, candidate);
      return candidate;
    }
  }

  NSLog(@"%@ [Runner] ERROR: Waypipe binary not found in bundle", WAYPIPE_EMOJI);
  return nil;
}

- (NSArray<NSString *> *)buildWaypipeArguments:(WawonaPreferencesManager *)prefs {
  NSMutableArray *args = [NSMutableArray array];

  // Build SSH command first
  NSString *sshHost = prefs.waypipeSSHHost ?: prefs.sshHost;
  NSString *sshUser = prefs.waypipeSSHUser ?: prefs.sshUser;

  if (sshHost.length == 0) {
    NSLog(@"%@ [Runner] ERROR: SSH host not configured", WAYPIPE_EMOJI);
    return @[];
  }

  // Remote command handling
  NSString *remoteCommand = [self effectiveRemoteCommand:prefs];
  if (remoteCommand.length == 0) {
    NSLog(@"%@ [Runner] ERROR: Remote command not configured", WAYPIPE_EMOJI);
    return @[];
  }

  // Build waypipe command
  [args addObject:@"--video"]; // Always enable video for better performance
  [args addObject:@"--compress"];
  [args addObject:@"lz4"];
  [args addObject:@"--compress-level"];
  [args addObject:@"7"];
  [args addObject:@"--threads"];
  [args addObject:@"0"]; // Auto-detect threads

  // SSH arguments (after --)
  [args addObject:@"--"];
  [args addObject:@"ssh"];
  [args addObject:@"-4"]; // IPv4 only for faster connection

  // SSH authentication
  if (prefs.sshAuthMethod == 0) { // Password auth
    [args addObject:@"-o"];
    [args addObject:@"PasswordAuthentication=yes"];
    [args addObject:@"-o"];
    [args addObject:@"PubkeyAuthentication=no"];
  } else { // Key auth
    [args addObject:@"-o"];
    [args addObject:@"PasswordAuthentication=no"];
    [args addObject:@"-o"];
    [args addObject:@"PubkeyAuthentication=yes"];
    
    NSString *keyPath = prefs.sshKeyPath ?: prefs.waypipeSSHKeyPath;
    if (keyPath.length > 0) {
      [args addObject:@"-i"];
      [args addObject:keyPath];
    }
  }

  // User and host
  [args addObject:[NSString stringWithFormat:@"%@@%@", sshUser, sshHost]];

  // Remote command
  [args addObject:remoteCommand];

  NSLog(@"%@ [Runner] Built %lu waypipe arguments", WAYPIPE_EMOJI,
        (unsigned long)args.count);
  return args;
}

- (NSString *)effectiveRemoteCommand:(WawonaPreferencesManager *)prefs {
  NSString *command = prefs.waypipeRemoteCommand ?: @"";
  if ([command isEqualToString:@"NOT_CONFIGURED"] || [command isEqualToString:@"NOT_SET"]) {
    return @"";
  }
  return command;
}

- (void)launchWaypipeViaExtension:(WawonaPreferencesManager *)prefs {
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    NSLog(@"%@ [Runner] ERROR: Waypipe binary not found", WAYPIPE_EMOJI);
    return;
  }

  NSArray *args = [self buildWaypipeArguments:prefs];

  // Validate that SSH is configured (buildWaypipeArguments returns empty array
  // if not)
  if (args.count == 0) {
    NSLog(@"%@ [Runner] ERROR: SSH not configured - waypipe requires SSH for "
          @"remote execution",
          WAYPIPE_EMOJI);
    // Show error to user via delegate if available
    if ([self.delegate respondsToSelector:@selector(runnerDidReadData:)]) {
      NSString *errorMsg =
          @"Waypipe requires SSH configuration.\n\nPlease configure SSH Host "
          @"in Settings:\n- OpenSSH section (if 'Use SSH Config' is "
          @"enabled)\n- Waypipe section (if 'Use SSH Config' is disabled)";
      [self.delegate
          runnerDidReadData:[errorMsg dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return;
  }

  NSLog(@"%@ [Runner] Built waypipe arguments: %lu args", WAYPIPE_EMOJI,
        (unsigned long)args.count);
  if (args.count > 0 && args.count <= 10) {
    NSLog(@"%@ [Runner] Arguments: %@", WAYPIPE_EMOJI, args);
  } else if (args.count > 10) {
    NSLog(@"%@ [Runner] First 10 args: %@", WAYPIPE_EMOJI,
          [args subarrayWithRange:NSMakeRange(0, 10)]);
  }

  // Validate waypipe command structure before launching
  BOOL hasSSHSubcommand = NO;
  BOOL hasPlaceholder = NO;
  BOOL hasXwlsOneshotConflict = NO;
  BOOL hasOneshot = NO;
  BOOL hasXwls = NO;

  for (NSString *arg in args) {
    if ([arg isEqualToString:@"ssh"]) {
      hasSSHSubcommand = YES;
    }
    if ([arg containsString:@"NOT_CONFIGURED"] ||
        [arg containsString:@"NOT_SET"]) {
      hasPlaceholder = YES;
    }
    if ([arg isEqualToString:@"--oneshot"]) {
      hasOneshot = YES;
    }
    if ([arg isEqualToString:@"--xwls"]) {
      hasXwls = YES;
    }
  }

  // Check for --xwls and --oneshot conflict
  if (hasXwls && hasOneshot) {
    hasXwlsOneshotConflict = YES;
  }

  if (hasXwlsOneshotConflict) {
    NSLog(@"%@ [Runner] ERROR: --xwls cannot be used with --oneshot",
          WAYPIPE_EMOJI);
    if ([self.delegate respondsToSelector:@selector(runnerDidReadData:)]) {
      NSString *errorMsg = @"Waypipe Configuration Error:\n\n--xwls (XWayland) "
                          @"cannot be used with --oneshot mode.\n\nPlease "
                          @"disable one of these options in Settings.";
      [self.delegate
          runnerDidReadData:[errorMsg dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return;
  }

  if (!hasSSHSubcommand || hasPlaceholder) {
    NSLog(@"%@ [Runner] ERROR: Invalid waypipe command - SSH not properly "
          @"configured",
          WAYPIPE_EMOJI);
    if ([self.delegate respondsToSelector:@selector(runnerDidReadData:)]) {
      NSString *errorMsg =
          @"Waypipe requires SSH configuration.\n\nPlease configure SSH Host "
          @"in Settings:\n- OpenSSH section (if 'Use SSH Config' is "
          @"enabled)\n- Waypipe section (if 'Use SSH Config' is "
          @"disabled)\n\nAlso ensure Remote Command is set.";
      [self.delegate
          runnerDidReadData:[errorMsg dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return;
  }

  // Skip kernel tests when launching waypipe normally (they interfere)
  // Unset WAWONA_KERNEL_TEST to prevent tests from running, and set skip flag
  unsetenv("WAWONA_KERNEL_TEST");
  setenv("WAWONA_SKIP_KERNEL_TESTS", "1", 1);
  setenv("WAWONA_USER_WAYPIPE_LAUNCH", "1",
         1); // Flag to indicate user-initiated launch

  // Set up environment with SSH password if needed
  // Our patched iOS SSH reads password from SSH_ASKPASS_PASSWORD or SSHPASS env
  // vars
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy]
          ?: [NSMutableDictionary dictionary];
  
  NSString *sshUser = prefs.waypipeSSHUser ?: prefs.sshUser;
  NSString *sshPassword = (prefs.useSSHConfig 
                             ? prefs.sshPassword 
                             : prefs.waypipeSSHPassword);

  if (sshUser.length > 0) {
    env[@"USER"] = sshUser;
    env[@"LOGNAME"] = sshUser;
  }

  if (sshPassword.length > 0) {
    env[@"WAWONA_SSH_PASSWORD"] = sshPassword;
    // SSH_ASKPASS_PASSWORD is read by our patched OpenSSH readpassphrase on iOS
    env[@"SSH_ASKPASS_PASSWORD"] = sshPassword;
    // Also set SSHPASS for compatibility with sshpass tool
    env[@"SSHPASS"] = sshPassword;
  }

  // Use HIAHKernel to spawn process via extension (iOS only)
  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  // CONFIGURE KERNEL IDENTIFIERS
  kernel.appGroupIdentifier = @"group.com.aspauldingcode.Wawona";
  kernel.extensionIdentifier = @"com.aspauldingcode.Wawona.HIAHProcessRunner";

  // Forward output from kernel to our delegate (so it shows in UI alert)
  __weak typeof(self) weakSelf = self;
  kernel.onOutput = ^(pid_t pid, NSString *output) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf && [strongSelf.delegate
                          respondsToSelector:@selector(runnerDidReadData:)]) {
      [strongSelf.delegate
          runnerDidReadData:[output dataUsingEncoding:NSUTF8StringEncoding]];
    }
  };

  [kernel
      spawnVirtualProcessWithPath:waypipePath
                        arguments:args
                      environment:env
                       completion:^(pid_t pid, NSError *_Nullable error) {
                         if (error) {
                           NSLog(@"%@ [Runner] Kernel spawn failed: %@ %@",
                                 WAYPIPE_EMOJI, error, WAYPIPE_EMOJI);
                           dispatch_async(dispatch_get_main_queue(), ^{
                             UIViewController *topController =
                                 [UIApplication sharedApplication]
                                     .windows.firstObject.rootViewController;
                             while (topController.presentedViewController) {
                               topController =
                                   topController.presentedViewController;
                             }

                             UIAlertController *alert = [UIAlertController
                                 alertControllerWithTitle:@"Waypipe Spawn Failed"
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
                                                     UIAlertAction
                                                         *_Nonnull action) {
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
                             [topController presentViewController:alert
                                                         animated:YES
                                                       completion:nil];
                           });
                         } else {
                           NSLog(@"%@ [Runner] Waypipe successfully "
                                 @"spawned via Kernel (PID: %d) %@",
                                 WAYPIPE_EMOJI, pid, WAYPIPE_EMOJI);
                           self.currentPid = pid;
                         }
                       }];
}

- (void)terminateProcessWithID:(NSInteger)processID {
  kill((pid_t)processID, SIGTERM);
}

@end

#else
// macOS: Minimal implementation for waypipe (not yet implemented)
@implementation WawonaWaypipeRunner

+ (instancetype)sharedRunner {
  static WawonaWaypipeRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _currentPid = 0;
    _stdinWriteFd = -1;
    _stdinHandle = nil;
    _sshPassword = nil;
    _currentExtension = nil;
    _lastWaypipeActivityAt = nil;
    _extensionHangMonitor = nil;
    _lastWaypipeEnv = nil;
    _lastWaypipeArgs = nil;
  }
  return self;
}

- (NSString *)findSSHBinary {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

  NSArray<NSString *> *candidates = @[
    [bundlePath stringByAppendingPathComponent:@"Contents/MacOS/ssh"],
    [bundlePath stringByAppendingPathComponent:@"Contents/Resources/bin/ssh"],
    [bundlePath stringByAppendingPathComponent:@"bin/ssh"],
    [bundlePath stringByAppendingPathComponent:@"ssh"],
  ];

  for (NSString *candidate in candidates) {
    if ([fm fileExistsAtPath:candidate]) {
      return candidate;
    }
  }

  NSLog(@"%@ [Runner] SSH binary not found in bundle", WAYPIPE_EMOJI);
  return nil;
}

- (NSString *)findWaypipeBinary {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

  NSArray<NSString *> *candidates = @[
    [bundlePath stringByAppendingPathComponent:@"Contents/MacOS/waypipe"],
    [bundlePath stringByAppendingPathComponent:@"Contents/Resources/bin/waypipe"],
    [bundlePath stringByAppendingPathComponent:@"bin/waypipe"],
    [bundlePath stringByAppendingPathComponent:@"waypipe"],
    [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:nil],
    [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:@"bin"],
  ];

  for (NSString *candidate in candidates) {
    if ([fm fileExistsAtPath:candidate]) {
      NSLog(@"%@ [Runner] Found waypipe at: %@", WAYPIPE_EMOJI, candidate);
      return candidate;
    }
  }

  NSLog(@"%@ [Runner] ERROR: Waypipe binary not found in bundle", WAYPIPE_EMOJI);
  return nil;
}

- (void)launchWaypipeViaExtension:(WawonaPreferencesManager *)prefs {
  NSLog(@"%@ [Runner] Waypipe on macOS is not yet implemented", WAYPIPE_EMOJI);
  if ([self.delegate respondsToSelector:@selector(runnerDidReadData:)]) {
    NSString *errorMsg = @"Waypipe on macOS is not yet implemented.\n\nUse iOS for waypipe functionality.";
    [self.delegate runnerDidReadData:[errorMsg dataUsingEncoding:NSUTF8StringEncoding]];
  }
}

- (void)terminateProcessWithID:(NSInteger)processID {
  kill((pid_t)processID, SIGTERM);
}

@end
#endif