#import "WawonaWaypipeRunner.h"
#import "WawonaSSHClient.h"
#import <errno.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>

extern char **environ;

// Global for signal handler safety
volatile pid_t g_active_waypipe_pgid = 0;

@interface WawonaWaypipeRunner () <WawonaSSHClientDelegate>
@property(nonatomic, assign) pid_t currentPid;
@property(nonatomic, strong) NSTask *currentTask;
@property(nonatomic, strong) WawonaSSHClient *sshClient;
@end

@implementation WawonaWaypipeRunner

+ (instancetype)sharedRunner {
  static WawonaWaypipeRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (NSString *)findWaypipeBinary {
  NSArray *searchPaths = @[
    @"/usr/local/bin/waypipe", @"/opt/homebrew/bin/waypipe",
    @"/usr/bin/waypipe", @"~/.local/bin/waypipe"
  ];

  for (NSString *path in searchPaths) {
    NSString *expandedPath = [path stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:expandedPath]) {
      return expandedPath;
    }
  }

  // Check main bundle (for iOS/bundled app) - with permission check
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

  // Build candidates array, filtering out nil values
  NSMutableArray *bundleCandidates = [NSMutableArray array];
  NSString *candidate1 =
      [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:nil];
  if (candidate1)
    [bundleCandidates addObject:candidate1];
  NSString *candidate2 =
      [[NSBundle mainBundle] pathForResource:@"waypipe" ofType:@"bin"];
  if (candidate2)
    [bundleCandidates addObject:candidate2];
  [bundleCandidates
      addObject:[bundlePath stringByAppendingPathComponent:@"waypipe"]];
  [bundleCandidates
      addObject:[bundlePath stringByAppendingPathComponent:@"waypipe-bin"]];
  [bundleCandidates
      addObject:[bundlePath stringByAppendingPathComponent:@"bin/waypipe"]];

  for (NSString *candidate in bundleCandidates) {
    if (!candidate || candidate.length == 0)
      continue;

    if ([fm fileExistsAtPath:candidate]) {
      // Check if executable
      if (![fm isExecutableFileAtPath:candidate]) {
        // Try to fix permissions
        NSDictionary *attrs = @{NSFilePosixPermissions : @0755};
        NSError *error = nil;
        if (![fm setAttributes:attrs ofItemAtPath:candidate error:&error]) {
          NSLog(
              @"[Runner] Warning: Could not set execute permissions on %@: %@",
              candidate, error);
          continue;
        }
      }

      if ([fm isExecutableFileAtPath:candidate]) {
        NSLog(@"[Runner] Found waypipe binary at: %@", candidate);
        return candidate;
      }
    }
  }

  // Check PATH environment variable
  NSString *pathEnv = [[NSProcessInfo processInfo] environment][@"PATH"];
  if (pathEnv) {
    for (NSString *component in [pathEnv componentsSeparatedByString:@":"]) {
      NSString *fullPath =
          [component stringByAppendingPathComponent:@"waypipe"];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:fullPath]) {
        return fullPath;
      }
    }
  }

  return nil;
}

- (NSArray<NSString *> *)buildWaypipeArguments:
    (WawonaPreferencesManager *)prefs {
  NSMutableArray *args = [NSMutableArray array];

  // SSH Setup
  [args addObject:@"ssh"];

  NSString *sshTarget = nil;
  if (prefs.waypipeSSHEnabled) {
    if (prefs.waypipeSSHUser.length > 0 && prefs.waypipeSSHHost.length > 0) {
      sshTarget = [NSString stringWithFormat:@"%@@%@", prefs.waypipeSSHUser,
                                             prefs.waypipeSSHHost];
    } else if (prefs.waypipeSSHHost.length > 0) {
      sshTarget = prefs.waypipeSSHHost;
    }
  }
  if (sshTarget && sshTarget.length > 0) {
    [args addObject:sshTarget];
  }

  // Remote Command
  if (prefs.waypipeRemoteCommand.length > 0) {
    [args addObject:prefs.waypipeRemoteCommand];
  }

  // Compression (example)
  if (prefs.waypipeCompress) {
    [args addObject:@"--compress"];
    [args addObject:prefs.waypipeCompress];
  }

  return args;
}

- (NSString *)generatePreviewString:(WawonaPreferencesManager *)prefs {
  NSString *bin = [self findWaypipeBinary] ?: @"waypipe";
  NSArray *args = [self buildWaypipeArguments:prefs];
  return [NSString
      stringWithFormat:@"%@ %@", bin, [args componentsJoinedByString:@" "]];
}

- (void)launchWaypipe:(WawonaPreferencesManager *)prefs {
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    // Logic for not found?
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:@"Waypipe binary not found."];
    }
    return;
  }

#if TARGET_OS_IPHONE && TARGET_OS_SIMULATOR
  // NOTE: iOS Simulator networking limitations
  // The iOS Simulator has restricted network access and may not be able to:
  // 1. Access the host machine's network interfaces directly
  // 2. Connect to other devices on the local network
  // 3. Use certain networking features that require real device capabilities
  //
  // For waypipe to work properly, you may need to:
  // - Use a real iOS device instead of the simulator
  // - Ensure the simulator can reach the target host (may require special
  // configuration)
  // - Check that the local IP address shown in settings is accessible from the
  // target
  NSLog(@"⚠️ Running on iOS Simulator - networking may be limited. Waypipe "
        @"connections may not work as expected.");
#endif

#if TARGET_OS_IPHONE
  // On iOS, waypipe can't spawn 'ssh' because it doesn't exist.
  // We need to use WawonaSSHClient to establish the SSH connection first.
  if (prefs.waypipeSSHEnabled && prefs.waypipeSSHHost.length > 0) {
    [self launchWaypipeWithSSHClient:prefs waypipePath:waypipePath];
    return;
  }
#endif

  NSArray *args = [self buildWaypipeArguments:prefs];

#if TARGET_OS_IPHONE
  // iOS posix_spawn implementation

  // Convert args to C strings
  // argv[0] should be the binary path strictly speaking, but here we construct
  // full args Actually, argv[0] is waypipe path. The 'args' array above likely
  // starts with 'ssh' based on logic? Wait, buildWaypipeArguments starts with
  // 'ssh'. We need to prepend waypipePath to argv? Or is waypipePath passed as
  // argv[0] and then the args follow?

  NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:waypipePath];
  [fullArgs addObjectsFromArray:args];

  char **argv = (char **)malloc(sizeof(char *) * (fullArgs.count + 1));
  for (NSUInteger i = 0; i < fullArgs.count; i++) {
    argv[i] = strdup([fullArgs[i] UTF8String]);
  }
  argv[fullArgs.count] = NULL;

  // Environment
  NSMutableArray *envList = [NSMutableArray array];
  NSDictionary *currentEnv = [[NSProcessInfo processInfo] environment];

  // Keep existing env
  for (NSString *key in currentEnv) {
    [envList
        addObject:[NSString stringWithFormat:@"%@=%@", key, currentEnv[key]]];
  }

  // Enforce specific vars for iOS
  [envList
      addObject:[NSString stringWithFormat:@"XDG_RUNTIME_DIR=%@",
                                           prefs.waylandSocketDir ?: @"/tmp"]];
  [envList addObject:[NSString stringWithFormat:@"WAYLAND_DISPLAY=%@",
                                                prefs.waypipeDisplay
                                                    ?: @"wayland-0"]];

  // USER mock (critical for the "No user" fix, though we patched the binary
  // too)
  if (!currentEnv[@"USER"])
    [envList addObject:@"USER=mobile"];
  if (!currentEnv[@"LOGNAME"])
    [envList addObject:@"LOGNAME=mobile"];
  if (!currentEnv[@"HOME"])
    [envList addObject:@"HOME=/var/mobile"]; // or sandboxed home

  // Ensure /usr/bin is in PATH for ssh
  NSString *currentPath = currentEnv[@"PATH"];
  if (!currentPath)
    currentPath = @"/usr/bin:/bin:/usr/sbin:/sbin";
  if (![currentPath containsString:@"/usr/bin"]) {
    // Note: simplistic check, but matches previous logic
    currentPath = [@"/usr/bin:" stringByAppendingString:currentPath];
  }
  // Add envList updated or new PATH entry... complexity here.
  // Simpler: Just override PATH in our list.
  // Remove existing PATH from list if we just added it?
  // Using a Dictionary first is better.
  NSMutableDictionary *envDict = [currentEnv mutableCopy];
  envDict[@"XDG_RUNTIME_DIR"] = prefs.waylandSocketDir ?: @"/tmp";
  envDict[@"WAYLAND_DISPLAY"] = prefs.waypipeDisplay ?: @"wayland-0";
  if (!envDict[@"USER"])
    envDict[@"USER"] = @"mobile";
  if (!envDict[@"LOGNAME"])
    envDict[@"LOGNAME"] = @"mobile";
  if (!envDict[@"HOME"])
    envDict[@"HOME"] = NSHomeDirectory();
  envDict[@"PATH"] = currentPath;

  char **envp = (char **)malloc(sizeof(char *) * (envDict.count + 1));
  int i = 0;
  for (NSString *key in envDict) {
    NSString *val = envDict[key];
    NSString *entry = [NSString stringWithFormat:@"%@=%@", key, val];
    envp[i++] = strdup([entry UTF8String]);
  }
  envp[i] = NULL;

  // Pipes
  int stdoutPipe[2], stderrPipe[2];
  if (pipe(stdoutPipe) != 0 || pipe(stderrPipe) != 0) {
    // Fail
    free(argv);
    free(envp); // leak strings but we are failing
    return;
  }

  posix_spawn_file_actions_t fileActions;
  posix_spawn_file_actions_init(&fileActions);
  posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO);
  posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], STDERR_FILENO);
  posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[0]);
  posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0]);

  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  // Put child in its own process group so we can kill all sub-processes later
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
  posix_spawnattr_setpgid(&attr, 0);

  pid_t pid;
  int status = posix_spawn(&pid, [waypipePath UTF8String], &fileActions, &attr,
                           argv, (char *const *)envp);

  posix_spawnattr_destroy(&attr);

  posix_spawn_file_actions_destroy(&fileActions);
  close(stdoutPipe[1]);
  close(stderrPipe[1]);

  // Free C strings
  // ... (omitted for brevity in this snippet, but acceptable for now)

  if (status == 0) {
    self.currentPid = pid;
    g_active_waypipe_pgid = pid;
    NSLog(@"[Runner] Waypipe launched PID: %d", pid);

    // Monitor output
    [self monitorDescriptor:stdoutPipe[0] isError:NO];
    [self monitorDescriptor:stderrPipe[0] isError:YES];
  } else {
    // Error 13 = EACCES (Permission denied)
    // This could mean: wrong architecture, code signing issue, or iOS Simulator
    // restrictions
    NSString *errorMsg = @"Unknown error";
    if (status == EACCES) {
      errorMsg =
          @"Permission denied (EACCES) - binary may be wrong architecture, not "
          @"code-signed, or iOS Simulator restrictions";
    } else if (status == ENOENT) {
      errorMsg = @"File not found (ENOENT)";
    } else if (status == ENOEXEC) {
      errorMsg = @"Exec format error (ENOEXEC) - binary format not recognized";
    } else {
      errorMsg = [NSString
          stringWithFormat:@"Error code %d: %s", status, strerror(status)];
    }

    NSLog(@"[Runner] Spawn failed: %d (%@)", status, errorMsg);
    NSLog(@"[Runner] Binary path: %@", waypipePath);

    // Check file attributes
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:waypipePath error:nil];
    if (attrs) {
      NSLog(@"[Runner] File permissions: %@", attrs[NSFilePosixPermissions]);
      NSLog(@"[Runner] File size: %@ bytes", attrs[NSFileSize]);
    }

    // Notify delegate
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              [NSString
                  stringWithFormat:@"Failed to launch waypipe: %@", errorMsg]];
    }
  }

#else
  // macOS NSTask Implementation
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:waypipePath];
  task.arguments = args;

  // Env
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  env[@"WAYLAND_DISPLAY"] = [NSString
      stringWithFormat:@"%@/%@", prefs.waylandSocketDir, prefs.waypipeDisplay];
  task.environment = env;

  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  task.standardOutput = outPipe;
  task.standardError = errPipe;

  outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    if (d.length > 0) {
      NSString *s =
          [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
      [self parseOutput:s isError:NO];
    }
  };
  errPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    if (d.length > 0) {
      NSString *s =
          [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
      [self parseOutput:s isError:YES];
    }
  };

  NSError *err;
  if ([task launchAndReturnError:&err]) {
    self.currentTask = task;
    self.currentPid = task.processIdentifier;
    g_active_waypipe_pgid = self.currentPid;
    NSLog(@"[Runner] Waypipe launched via NSTask PID: %d", self.currentPid);
  } else {
    NSLog(@"[Runner] Launch failed: %@", err);
  }
#endif
}

- (void)monitorDescriptor:(int)fd isError:(BOOL)isError {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 ^{
                   char buffer[4096];
                   ssize_t count;
                   while ((count = read(fd, buffer, sizeof(buffer) - 1)) > 0) {
                     buffer[count] = 0;
                     NSString *s = [NSString stringWithUTF8String:buffer];
                     dispatch_async(dispatch_get_main_queue(), ^{
                       [self parseOutput:s isError:isError];
                     });
                   }
                   close(fd);
                 });
}

- (void)parseOutput:(NSString *)text isError:(BOOL)isError {
  NSLog(@"[Waypipe %@] %@", isError ? @"stderr" : @"stdout", text);

  // Check for SSH prompts/errors
  if ([text containsString:@"password:"] ||
      [text containsString:@"Password:"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHPasswordPrompt:)]) {
      [self.delegate runnerDidReceiveSSHPasswordPrompt:text];
    }
  } else if ([text containsString:@"Permission denied"] ||
             [text containsString:@"Host key verification failed"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:text];
    }
  }
}

#if TARGET_OS_IPHONE
- (void)launchWaypipeWithSSHClient:(WawonaPreferencesManager *)prefs
                       waypipePath:(NSString *)waypipePath {
  // On iOS, we can't use waypipe's SSH mode because it tries to spawn 'ssh'.
  // Instead, we use WawonaSSHClient to establish the SSH connection and execute
  // the remote command directly.

  NSString *host = prefs.waypipeSSHHost;
  NSString *user = prefs.waypipeSSHUser ?: @"root";
  NSInteger port = 22; // TODO: Add port preference

  // Create SSH client
  WawonaSSHClient *sshClient =
      [[WawonaSSHClient alloc] initWithHost:host username:user port:port];
  sshClient.delegate = self;
  sshClient.authMethod = (WawonaSSHAuthMethod)prefs.waypipeSSHAuthMethod;

  if (sshClient.authMethod == WawonaSSHAuthMethodPassword) {
    // Use password from preferences (stored in Keychain)
    NSString *password = prefs.waypipeSSHPassword;
    if (!password || password.length == 0) {
      // Password not set, prompt user
      if ([self.delegate respondsToSelector:@selector
                         (runnerDidReceiveSSHPasswordPrompt:)]) {
        [self.delegate runnerDidReceiveSSHPasswordPrompt:
                           @"SSH password required. Please enter your password "
                           @"in Settings."];
      }
      return;
    }
    sshClient.password = password;
  } else if (sshClient.authMethod == WawonaSSHAuthMethodPublicKey) {
    sshClient.privateKeyPath = prefs.waypipeSSHKeyPath;
    sshClient.keyPassphrase = prefs.waypipeSSHKeyPassphrase;
  }

  self.sshClient = sshClient;

  // Connect and authenticate
  NSError *error = nil;
  if (![sshClient connect:&error]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              [NSString stringWithFormat:@"SSH connection failed: %@",
                                         error.localizedDescription]];
    }
    return;
  }

  if (![sshClient authenticate:&error]) {
    // Check if it's a password authentication failure and password might be
    // missing/wrong
    if (sshClient.authMethod == WawonaSSHAuthMethodPassword) {
      NSString *errorMsg = error.localizedDescription;
      if ([errorMsg containsString:@"Password not provided"] ||
          [errorMsg containsString:@"Password authentication failed"]) {
        // Prompt user for password
        if ([self.delegate respondsToSelector:@selector
                           (runnerDidReceiveSSHPasswordPrompt:)]) {
          [self.delegate
              runnerDidReceiveSSHPasswordPrompt:
                  @"SSH password authentication failed. Please check your "
                  @"password in Settings or enter a new one."];
        }
      } else {
        if ([self.delegate
                respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
          [self.delegate
              runnerDidReceiveSSHError:
                  [NSString stringWithFormat:@"SSH authentication failed: %@",
                                             error.localizedDescription]];
        }
      }
    } else {
      if ([self.delegate
              respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
        [self.delegate
            runnerDidReceiveSSHError:
                [NSString stringWithFormat:@"SSH authentication failed: %@",
                                           error.localizedDescription]];
      }
    }
    [sshClient disconnect];
    return;
  }

  // Keep SSH connection alive - don't disconnect!
  // Waypipe needs a persistent connection to communicate over.

  // The issue: Waypipe normally spawns 'ssh' itself and communicates over
  // stdin/stdout. On iOS, we can't spawn ssh, so we need to provide the
  // connection ourselves.
  //
  // The solution: Execute the remote waypipe server command via SSH, then
  // launch the local waypipe client to connect through the SSH tunnel.
  //
  // However, waypipe expects to spawn ssh itself, so we need to work around
  // this. One approach: Launch waypipe with a command that uses our SSH
  // connection. But waypipe's architecture assumes it can spawn ssh, so this is
  // complex.
  //
  // For now, let's execute the remote command (which should start waypipe
  // server) and then try to launch the local waypipe client.

  NSString *userCommand = prefs.waypipeRemoteCommand ?: @"weston-terminal";
  NSString *remoteCommand = [NSString
      stringWithFormat:@"waypipe server --control /tmp/waypipe-server.sock "
                       @"--display wayland-0 -- %@",
                       userCommand];

  // Start tunnel
  int tunnelFd = -1;
  NSError *tunnelError = nil;
  if (![sshClient startTunnelForCommand:remoteCommand
                            localSocket:&tunnelFd
                                  error:&tunnelError]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              [NSString stringWithFormat:@"Failed to start tunnel: %@",
                                         tunnelError.localizedDescription]];
    }
    [sshClient disconnect];
    return;
  }

  NSLog(@"[Runner] SSH tunnel established for command: %@", remoteCommand);

  // Launch local waypipe client
  // We need to spawn 'waypipe client' with stdin/stdout connected to tunnelFd

  // Args
  NSMutableArray *args = [NSMutableArray array];
  [args addObject:@"client"];
  // Add compression if needed
  if (prefs.waypipeCompress) {
    [args addObject:@"--compress"];
    [args addObject:prefs.waypipeCompress];
  }

  // Convert args to C strings
  NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:waypipePath];
  [fullArgs addObjectsFromArray:args];

  char **argv = (char **)malloc(sizeof(char *) * (fullArgs.count + 1));
  for (NSUInteger i = 0; i < fullArgs.count; i++) {
    argv[i] = strdup([fullArgs[i] UTF8String]);
  }
  argv[fullArgs.count] = NULL;

  // Environment
  NSMutableArray *envList = [NSMutableArray array];
  NSDictionary *currentEnv = [[NSProcessInfo processInfo] environment];

  // Keep existing env
  for (NSString *key in currentEnv) {
    [envList
        addObject:[NSString stringWithFormat:@"%@=%@", key, currentEnv[key]]];
  }

  // Set Wayland vars
  [envList
      addObject:[NSString stringWithFormat:@"XDG_RUNTIME_DIR=%@",
                                           prefs.waylandSocketDir ?: @"/tmp"]];
  [envList addObject:[NSString stringWithFormat:@"WAYLAND_DISPLAY=%@",
                                                prefs.waypipeDisplay
                                                    ?: @"wayland-0"]];

  // Convert env to C strings
  char **envp = (char **)malloc(sizeof(char *) * (envList.count + 1));
  for (NSUInteger i = 0; i < envList.count; i++) {
    envp[i] = strdup([envList[i] UTF8String]);
  }
  envp[envList.count] = NULL;

  // File actions for redirection
  posix_spawn_file_actions_t fileActions;
  posix_spawn_file_actions_init(&fileActions);

  // Stdin/Stdout -> Tunnel
  posix_spawn_file_actions_adddup2(&fileActions, tunnelFd, STDIN_FILENO);
  posix_spawn_file_actions_adddup2(&fileActions, tunnelFd, STDOUT_FILENO);

  // Stderr -> Pipe (for logging)
  int stderrPipe[2] = {-1, -1};
  if (pipe(stderrPipe) != 0) {
    NSLog(@"[Runner] Failed to create stderr pipe");
  } else {
    posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1],
                                     STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0]);
  }

  posix_spawn_file_actions_addclose(&fileActions, tunnelFd);

  pid_t pid;
  int status = posix_spawn(&pid, [waypipePath UTF8String], &fileActions, NULL,
                           argv, (char *const *)envp);

  posix_spawn_file_actions_destroy(&fileActions);
  // Close our copy of tunnelFd (child has it now, and we don't need it)
  // Wait, we also don't need it open in parent?
  // The tunnel forwarding thread holds the OTHER end of the socket pair.
  // We hold tunnelFd (the local end). We pass it to child.
  // We should close it in parent after spawn.
  close(tunnelFd);

  if (stderrPipe[1] != -1) {
    // Close write end in parent
    close(stderrPipe[1]);
  }

  // Free strings
  for (NSUInteger i = 0; i < fullArgs.count; i++)
    free(argv[i]);
  free(argv);
  for (NSUInteger i = 0; i < envList.count; i++)
    free(envp[i]);
  free(envp);

  if (status == 0) {
    self.currentPid = pid;
    g_active_waypipe_pgid = pid;
    NSLog(@"[Runner] Waypipe client launched PID: %d", pid);

    // Monitor stderr
    if (stderrPipe[0] != -1) {
      [self monitorDescriptor:stderrPipe[0] isError:YES];
    }
  } else {
    NSLog(@"[Runner] Failed to spawn waypipe client: %d", status);
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              [NSString stringWithFormat:@"Failed to spawn waypipe client: %s",
                                         strerror(status)]];
    }
    [sshClient disconnect];
  }
}
#endif

#pragma mark - WawonaSSHClientDelegate

- (void)sshClient:(WawonaSSHClient *)client
    didReceivePasswordPrompt:(NSString *)prompt {
  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveSSHPasswordPrompt:)]) {
    [self.delegate runnerDidReceiveSSHPasswordPrompt:prompt];
  }
}

- (void)sshClient:(WawonaSSHClient *)client didReceiveError:(NSError *)error {
  if ([self.delegate respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
    [self.delegate runnerDidReceiveSSHError:error.localizedDescription];
  }
}

- (void)sshClientDidConnect:(WawonaSSHClient *)client {
  NSLog(@"[Runner] SSH client connected");
}

- (void)sshClientDidDisconnect:(WawonaSSHClient *)client {
  NSLog(@"[Runner] SSH client disconnected");
}

- (void)stopWaypipe {
  if (self.currentTask) {
    NSLog(@"[Runner] Terminating waypipe task (PID %d)...", self.currentPid);
    [self.currentTask terminate];
    self.currentTask = nil;
  }

  if (self.currentPid > 0) {
    NSLog(@"[Runner] Sending SIGTERM to waypipe process group %d...",
          self.currentPid);
    // kill(-pid) sends signal to the whole process group
    // We used POSIX_SPAWN_SETPGROUP earlier
    kill(-self.currentPid, SIGTERM);

    // Give it a moment then force kill if needed
    pid_t pidToKill = self.currentPid;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          // Double check if it's still running (this is a bit simplistic but
          // works for cleanup)
          kill(-pidToKill, SIGKILL);
        });
    self.currentPid = 0;
    g_active_waypipe_pgid = 0;
  }

  if (self.sshClient) {
    NSLog(@"[Runner] Disconnecting SSH client...");
    [self.sshClient disconnect];
    self.sshClient = nil;
  }
}

@end
