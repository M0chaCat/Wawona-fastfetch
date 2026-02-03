#import "WawonaWaypipeRunner.h"
#import "../../logging/WawonaLog.h"
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
#if !TARGET_OS_IPHONE
@property(nonatomic, strong) NSTask *currentTask;
#endif
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
  // Resolve symlinks because Nix often launches via a symlink in bin/
  NSString *realExecPath =
      [[NSBundle mainBundle].executablePath stringByResolvingSymlinksInPath];
  NSString *execDir = [realExecPath stringByDeletingLastPathComponent];
  NSString *path = [execDir stringByAppendingPathComponent:@"waypipe"];

  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }

  // Also check Resources/bin/waypipe as user requested resource-based bundling
  NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"waypipe"
                                                           ofType:nil
                                                      inDirectory:@"bin"];
  if (resourcePath &&
      [[NSFileManager defaultManager] isExecutableFileAtPath:resourcePath]) {
    return resourcePath;
  }

#if TARGET_OS_IPHONE
  // On iOS check bundle root
  NSString *bundlePath =
      [[NSBundle mainBundle].bundlePath stringByResolvingSymlinksInPath];
  path = [bundlePath stringByAppendingPathComponent:@"waypipe"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }
#endif

  return nil;
}

- (NSString *)findSshpassBinary {
  NSString *realExecPath =
      [[NSBundle mainBundle].executablePath stringByResolvingSymlinksInPath];
  NSString *execDir = [realExecPath stringByDeletingLastPathComponent];
  NSString *path = [execDir stringByAppendingPathComponent:@"sshpass"];

  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }

#if TARGET_OS_IPHONE
  NSString *bundlePath =
      [[NSBundle mainBundle].bundlePath stringByResolvingSymlinksInPath];
  path = [bundlePath stringByAppendingPathComponent:@"sshpass"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }
#endif

  return nil;
}

- (NSArray<NSString *> *)buildWaypipeArguments:
    (WawonaPreferencesManager *)prefs {
  NSMutableArray *args = [NSMutableArray array];

  // 1. Waypipe Global Options (MUST come before 'ssh')
  if (prefs.waypipeCompress &&
      ![prefs.waypipeCompress isEqualToString:@"none"]) {
    [args addObject:@"--compress"];
    [args addObject:prefs.waypipeCompress];
  }

  if (prefs.waypipeDebug) {
    [args addObject:@"--debug"];
  }

  // SSH Destination
  NSString *sshTarget = nil;
  NSString *targetHost =
      prefs.waypipeSSHHost.length > 0 ? prefs.waypipeSSHHost : prefs.sshHost;
  NSString *targetUser =
      prefs.waypipeSSHUser.length > 0 ? prefs.waypipeSSHUser : prefs.sshUser;

  if (prefs.waypipeSSHEnabled && targetHost.length > 0) {
    // 2. SSH Subcommand (Only if we have a target)
    [args addObject:@"ssh"];

    // SSH Safety options
    [args addObject:@"-o"];
    [args addObject:@"StrictHostKeyChecking=accept-new"];
    [args addObject:@"-o"];
    [args addObject:@"BatchMode=no"];

    if (targetUser.length > 0) {
      sshTarget = [NSString stringWithFormat:@"%@@%@", targetUser, targetHost];
    } else {
      sshTarget = targetHost;
    }
    [args addObject:sshTarget];
  }

  // 3. Remote Command
  if (prefs.waypipeRemoteCommand.length > 0) {
    [args addObject:prefs.waypipeRemoteCommand];
  } else {
    [args addObject:@"weston-terminal"]; // Default remote command
  }

  return args;
}

- (NSString *)generateWaypipePreviewString:(WawonaPreferencesManager *)prefs {
  NSString *bin = [self findWaypipeBinary] ?: @"waypipe";
  NSArray *args = [self buildWaypipeArguments:prefs];

  NSString *cmd = [NSString
      stringWithFormat:@"%@ %@", bin, [args componentsJoinedByString:@" "]];

  NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                             ? prefs.waypipeSSHPassword
                             : prefs.sshPassword;

  if (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0) {
    NSString *sshpass = [self findSshpassBinary];
    if (sshpass) {
      cmd = [NSString stringWithFormat:@"SSHPASS=**** %@ -e %@",
                                       [sshpass lastPathComponent], cmd];
    }
  }

  return cmd;
}

- (void)launchWaypipe:(WawonaPreferencesManager *)prefs {
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              @"Waypipe binary not found. Please ensure it is installed."];
    }
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:@"Error: Waypipe binary not found.\n"
                         isError:YES];
    }
    return;
  }

  WLog(@"WAYPIPE", @"Using waypipe binary at: %@", waypipePath);

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
  WLog(@"WAYPIPE",
       @"Running on iOS Simulator - networking may be limited. Waypipe "
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

  // Enforce specific vars for iOS/macOS
  NSString *socketDir = prefs.waylandSocketDir;
  if (socketDir.length == 0) {
    socketDir = @"/tmp";
  }
  NSString *display = prefs.waypipeDisplay;
  if (display.length == 0) {
    display = @"wayland-0";
  }

  [envList
      addObject:[NSString stringWithFormat:@"XDG_RUNTIME_DIR=%@", socketDir]];
  [envList
      addObject:[NSString stringWithFormat:@"WAYLAND_DISPLAY=%@", display]];

  // USER mock (critical for the "No user" fix, though we patched the binary
  // too)
  if (!currentEnv[@"USER"]) {
    [envList addObject:@"USER=mobile"];
  }
  if (!currentEnv[@"LOGNAME"]) {
    [envList addObject:@"LOGNAME=mobile"];
  }
  if (!currentEnv[@"HOME"]) {
    [envList addObject:@"HOME=/var/mobile"]; // or sandboxed home
  }

  // Ensure /usr/bin is in PATH for ssh
  NSString *currentPath = currentEnv[@"PATH"];
  if (!currentPath) {
    currentPath = @"/usr/bin:/bin:/usr/sbin:/sbin";
  }
  if (![currentPath containsString:@"/usr/bin"]) {
    currentPath = [@"/usr/bin:" stringByAppendingString:currentPath];
  }

  // Create environment bridge dictionary for robust handling
  NSMutableDictionary *finalEnv = [currentEnv mutableCopy];
  finalEnv[@"XDG_RUNTIME_DIR"] = socketDir;
  finalEnv[@"WAYLAND_DISPLAY"] = display;
  finalEnv[@"PATH"] = currentPath;
  if (!finalEnv[@"USER"]) {
    finalEnv[@"USER"] = @"mobile";
  }
  if (!finalEnv[@"LOGNAME"]) {
    finalEnv[@"LOGNAME"] = @"mobile";
  }
  if (!finalEnv[@"HOME"]) {
    finalEnv[@"HOME"] = NSHomeDirectory();
  }

  char **envp = (char **)malloc(sizeof(char *) * (finalEnv.count + 1));
  int j = 0;
  for (NSString *key in finalEnv) {
    NSString *val = finalEnv[key];
    NSString *entry = [NSString stringWithFormat:@"%@=%@", key, val];
    envp[j++] = strdup([entry UTF8String]);
  }
  envp[j] = NULL;

  // Pipes
  int stdoutPipe[2], stderrPipe[2];
  if (pipe(stdoutPipe) != 0 || pipe(stderrPipe) != 0) {
    free(argv);
    free(envp);
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
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
  posix_spawnattr_setpgroup(&attr, 0);

  pid_t pid;
  int status = posix_spawn(&pid, [waypipePath UTF8String], &fileActions, &attr,
                           argv, (char *const *)envp);

  posix_spawnattr_destroy(&attr);
  posix_spawn_file_actions_destroy(&fileActions);
  close(stdoutPipe[1]);
  close(stderrPipe[1]);

  if (status == 0) {
    self.currentPid = pid;
    g_active_waypipe_pgid = pid;
    WLog(@"WAYPIPE", @"Waypipe launched PID: %d", pid);
    [self monitorDescriptor:stdoutPipe[0] isError:NO];
    [self monitorDescriptor:stderrPipe[0] isError:YES];
  } else {
    NSString *errorMsg = [NSString
        stringWithFormat:@"Error code %d: %s", status, strerror(status)];
    WLog(@"WAYPIPE", @"Spawn failed: %d (%@)", status, errorMsg);
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

  NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                             ? prefs.waypipeSSHPassword
                             : prefs.sshPassword;
  BOOL useSshpass = (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0);
  NSString *sshpassPath = useSshpass ? [self findSshpassBinary] : nil;

  if (sshpassPath) {
    task.executableURL = [NSURL fileURLWithPath:sshpassPath];
    NSMutableArray *sshpassArgs = [NSMutableArray arrayWithObject:@"-e"];
    [sshpassArgs addObject:waypipePath];
    [sshpassArgs addObjectsFromArray:args];
    task.arguments = sshpassArgs;
  } else {
    task.executableURL = [NSURL fileURLWithPath:waypipePath];
    task.arguments = args;
  }

  // Env
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];

  // Waypipe needs to know where the socket IS, and it needs to be an absolute
  // path. We prioritize the environment because main.m sets it correctly.
  const char *envRuntime = getenv("XDG_RUNTIME_DIR");
  NSString *socketDirTask =
      (envRuntime) ? [NSString stringWithUTF8String:envRuntime] : nil;

  if (!socketDirTask || socketDirTask.length == 0) {
    socketDirTask = prefs.waylandSocketDir;
  }

  if (!socketDirTask || socketDirTask.length == 0) {
    socketDirTask = @"/tmp/wawona-503"; // Match what the compositor uses
    WLog(@"WAYPIPE", @"waylandSocketDir was empty, using default: %@",
         socketDirTask);
  }

  const char *envDisplay = getenv("WAYLAND_DISPLAY");
  NSString *displayNameTask =
      (envDisplay) ? [NSString stringWithUTF8String:envDisplay] : nil;

  if (!displayNameTask || displayNameTask.length == 0) {
    displayNameTask = prefs.waypipeDisplay;
  }

  if (!displayNameTask || displayNameTask.length == 0) {
    displayNameTask = @"wayland-0";
    WLog(@"WAYPIPE", @"waypipeDisplay was empty, using default: %@",
         displayNameTask);
  }

  WLog(@"WAYPIPE",
       @"Setting environment: XDG_RUNTIME_DIR=%@, WAYLAND_DISPLAY=%@, "
       @"XDG_CURRENT_DESKTOP=Wawona",
       socketDirTask, displayNameTask);

  env[@"XDG_RUNTIME_DIR"] = socketDirTask;
  env[@"WAYLAND_DISPLAY"] = displayNameTask;
  env[@"XDG_CURRENT_DESKTOP"] = @"Wawona";

  // Sanitize PATH to ensure /usr/bin is available for ssh
  NSString *currentPath = env[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
  if (![currentPath containsString:@"/usr/bin"]) {
    currentPath = [@"/usr/bin:" stringByAppendingString:currentPath];
  }
  env[@"PATH"] = currentPath;

  if (useSshpass) {
    env[@"SSHPASS"] = targetPass;
  }

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
    self.currentPid = task.processIdentifier;
    self.currentTask = task;
    g_active_waypipe_pgid = self.currentPid;
    WLog(@"WAYPIPE", @"Waypipe launched via NSTask PID: %d", self.currentPid);
  } else {
    WLog(@"WAYPIPE", @"Launch failed: %@", err);
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:
              [NSString stringWithFormat:@"Failed to launch waypipe: %@\n",
                                         err.localizedDescription]
                         isError:YES];
    }
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
  WLog(@"WAYPIPE", @"[Waypipe %@] %@", isError ? @"stderr" : @"stdout", text);

  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
    [self.delegate runnerDidReceiveOutput:text isError:isError];
  }

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
  NSString *host =
      prefs.waypipeSSHHost.length > 0 ? prefs.waypipeSSHHost : prefs.sshHost;
  NSString *user =
      prefs.waypipeSSHUser.length > 0 ? prefs.waypipeSSHUser : prefs.sshUser;
  if (user.length == 0)
    user = @"root";
  NSInteger port = 22;

  WawonaSSHClient *sshClient =
      [[WawonaSSHClient alloc] initWithHost:host username:user port:port];
  sshClient.delegate = self;
  sshClient.authMethod = (WawonaSSHAuthMethod)prefs.waypipeSSHAuthMethod;

  if (sshClient.authMethod == WawonaSSHAuthMethodPassword) {
    NSString *password = prefs.waypipeSSHPassword.length > 0
                             ? prefs.waypipeSSHPassword
                             : prefs.sshPassword;
    if (password.length == 0) {
      if ([self.delegate respondsToSelector:@selector
                         (runnerDidReceiveSSHPasswordPrompt:)]) {
        [self.delegate
            runnerDidReceiveSSHPasswordPrompt:@"SSH password required."];
      }
      return;
    }
    sshClient.password = password;
  } else if (sshClient.authMethod == WawonaSSHAuthMethodPublicKey) {
    sshClient.privateKeyPath = prefs.waypipeSSHKeyPath;
    sshClient.keyPassphrase = prefs.waypipeSSHKeyPassphrase;
  }

  self.sshClient = sshClient;

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
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              [NSString stringWithFormat:@"SSH authentication failed: %@",
                                         error.localizedDescription]];
    }
    [sshClient disconnect];
    return;
  }

  NSString *userCommand = prefs.waypipeRemoteCommand.length > 0
                              ? prefs.waypipeRemoteCommand
                              : @"weston-terminal";
  NSString *remoteCommand = [NSString
      stringWithFormat:@"waypipe server --control /tmp/waypipe-server-%d.sock "
                       @"--display wayland-0 -- %@",
                       (int)getpid(), userCommand];

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

  NSMutableArray *args = [NSMutableArray arrayWithObject:@"client"];
  if (prefs.waypipeCompress) {
    [args addObject:@"--compress"];
    [args addObject:prefs.waypipeCompress];
  }

  NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:waypipePath];
  [fullArgs addObjectsFromArray:args];
  char **argv = (char **)malloc(sizeof(char *) * (fullArgs.count + 1));
  for (NSUInteger i = 0; i < fullArgs.count; i++) {
    argv[i] = strdup([fullArgs[i] UTF8String]);
  }
  argv[fullArgs.count] = NULL;

  NSMutableArray *envList = [NSMutableArray array];
  NSDictionary *currentEnv = [[NSProcessInfo processInfo] environment];
  for (NSString *key in currentEnv) {
    [envList
        addObject:[NSString stringWithFormat:@"%@=%@", key, currentEnv[key]]];
  }

  NSString *socketDirSsh = prefs.waylandSocketDir;
  if (socketDirSsh.length == 0)
    socketDirSsh = @"/tmp";
  NSString *displaySsh = prefs.waypipeDisplay;
  if (displaySsh.length == 0)
    displaySsh = @"wayland-0";

  [envList addObject:[NSString
                         stringWithFormat:@"XDG_RUNTIME_DIR=%@", socketDirSsh]];
  [envList
      addObject:[NSString stringWithFormat:@"WAYLAND_DISPLAY=%@", displaySsh]];

  char **envp = (char **)malloc(sizeof(char *) * (envList.count + 1));
  for (NSUInteger i = 0; i < envList.count; i++) {
    envp[i] = strdup([envList[i] UTF8String]);
  }
  envp[envList.count] = NULL;

  posix_spawn_file_actions_t fileActions;
  posix_spawn_file_actions_init(&fileActions);
  posix_spawn_file_actions_adddup2(&fileActions, tunnelFd, STDIN_FILENO);
  posix_spawn_file_actions_adddup2(&fileActions, tunnelFd, STDOUT_FILENO);

  int stderrPipe[2] = {-1, -1};
  if (pipe(stderrPipe) == 0) {
    posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1],
                                     STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0]);
  }

  pid_t pid;
  int status = posix_spawn(&pid, [waypipePath UTF8String], &fileActions, NULL,
                           argv, (char *const *)envp);

  posix_spawn_file_actions_destroy(&fileActions);
  close(tunnelFd);
  if (stderrPipe[1] != -1)
    close(stderrPipe[1]);

  if (status == 0) {
    self.currentPid = pid;
    g_active_waypipe_pgid = pid;
    if (stderrPipe[0] != -1)
      [self monitorDescriptor:stderrPipe[0] isError:YES];
  } else {
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

- (void)stopWaypipe {
#if !TARGET_OS_IPHONE
  if (self.currentTask) {
    [self.currentTask terminate];
    self.currentTask = nil;
  }
#endif

  if (self.currentPid > 0) {
    kill(-self.currentPid, SIGTERM);
    pid_t pidToKill = self.currentPid;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          kill(-pidToKill, SIGKILL);
        });
    self.currentPid = 0;
    g_active_waypipe_pgid = 0;
  }

  if (self.sshClient) {
    [self.sshClient disconnect];
    self.sshClient = nil;
  }
}

@end
