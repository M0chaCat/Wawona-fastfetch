#import "litehook/litehook.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <mach-o/dyld.h>
#import <pthread.h>
#import <spawn.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <sys/wait.h>
#import <unistd.h>

/**
 * Robust hooks for posix_spawn and exec* family.
 * Intercepts process creation and forwards to the host virtual kernel or runs
 * in-process.
 */

// --- File Actions Tracking ---

typedef enum { WActionClose, WActionDup2, WActionOpen } WActionType;

typedef struct {
  WActionType type;
  int fd;
  int new_fd;
  char *path;
  int oflag;
  mode_t mode;
} WAction;

// Forward declaration for thread args (defined later)
typedef struct WawonaThreadArgs WawonaThreadArgs;
struct WawonaThreadArgs {
  char *path;
  int argc;
  char **argv;
  NSArray *actions;
};

// Forward declaration for guest thread function
static void *WawonaGuestThread(void *data);

static NSMutableDictionary<NSValue *, NSMutableArray *> *g_actions_map = nil;
static NSLock *g_actions_lock = nil;

static void WawonaInitActions(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    g_actions_map = [[NSMutableDictionary alloc] init];
    g_actions_lock = [[NSLock alloc] init];
  });
}

// Hook file action functions to track what needs to be done
typedef int (*ps_fa_adddup2_t)(posix_spawn_file_actions_t *, int, int);
typedef int (*ps_fa_addclose_t)(posix_spawn_file_actions_t *, int);

DEFINE_HOOK(posix_spawn_file_actions_adddup2, int,
            (posix_spawn_file_actions_t * fa, int fd, int new_fd)) {
  WawonaInitActions();
  [g_actions_lock lock];
  NSValue *key = [NSValue valueWithPointer:fa];
  if (!g_actions_map[key])
    g_actions_map[key] = [NSMutableArray array];

  WAction *a = calloc(1, sizeof(WAction));
  a->type = WActionDup2;
  a->fd = fd;
  a->new_fd = new_fd;
  [g_actions_map[key] addObject:[NSValue valueWithPointer:a]];
  NSLog(@"[WawonaHook] Captured file action: dup2(%d, %d) for pointer %p", fd,
        new_fd, fa);
  [g_actions_lock unlock];

  return ORIG_FUNC(posix_spawn_file_actions_adddup2)(fa, fd, new_fd);
}

DEFINE_HOOK(posix_spawn_file_actions_addclose, int,
            (posix_spawn_file_actions_t * fa, int fd)) {
  WawonaInitActions();
  [g_actions_lock lock];
  NSValue *key = [NSValue valueWithPointer:fa];
  if (!g_actions_map[key])
    g_actions_map[key] = [NSMutableArray array];

  WAction *a = calloc(1, sizeof(WAction));
  a->type = WActionClose;
  a->fd = fd;
  [g_actions_map[key] addObject:[NSValue valueWithPointer:a]];
  [g_actions_lock unlock];

  return ORIG_FUNC(posix_spawn_file_actions_addclose)(fa, fd);
}

// --- Main Hooks ---

typedef int (*posix_spawn_t)(pid_t *__restrict, const char *__restrict,
                             const posix_spawn_file_actions_t *__restrict,
                             const posix_spawnattr_t *__restrict,
                             char *const[__restrict], char *const[__restrict]);
typedef int (*execve_t)(const char *, char *const[], char *const[]);
typedef pid_t (*waitpid_t)(pid_t, int *, int);

DEFINE_HOOK(posix_spawn, int,
            (pid_t *__restrict pid, const char *__restrict path,
             const posix_spawn_file_actions_t *__restrict file_actions,
             const posix_spawnattr_t *__restrict attr,
             char *const argv[__restrict], char *const envp[__restrict]));

DEFINE_HOOK(execve, int,
            (const char *path, char *const argv[], char *const envp[]));
DEFINE_HOOK(waitpid, pid_t, (pid_t pid, int *stat_loc, int options));

static __thread BOOL gInHook = NO;

// Forward declarations
static int WawonaForwardSpawn(pid_t *pid, const char *path, char *const argv[],
                              char *const envp[]);
static int WawonaInProcessSpawn(pid_t *pid, const char *path,
                                const posix_spawn_file_actions_t *file_actions,
                                const posix_spawnattr_t *attr,
                                char *const argv[], char *const envp[]);

static int
hook_posix_spawn(pid_t *__restrict pid, const char *__restrict path,
                 const posix_spawn_file_actions_t *__restrict file_actions,
                 const posix_spawnattr_t *__restrict attr,
                 char *const argv[__restrict], char *const envp[__restrict]) {

  if (gInHook || getenv("WAWONA_NO_HOOKS")) {
    return ORIG_FUNC(posix_spawn)(pid, path, file_actions, attr, argv, envp);
  }

  gInHook = YES;
  NSLog(@"[WawonaHook] Intercepted posix_spawn for: %s", path);

  // ========================================
  // SSH Handling: Prefer ssh.dylib (dlopen) over executable (posix_spawn)
  // The SSH executable crashes (SIGSEGV) when spawned via posix_spawn on iOS
  // Instead, we dlopen ssh.dylib and call ssh_main() - same pattern as waypipe
  // ========================================
  if (path && (strstr(path, "ssh") != NULL ||
               (argv && argv[0] && strstr(argv[0], "ssh") != NULL))) {
    NSLog(@"[WawonaHook] SSH detected in posix_spawn - using in-process dlopen "
          @"approach");

    // Find ssh.dylib in the bundle
    NSBundle *extensionBundle = [NSBundle mainBundle];
    NSString *extensionPath = [extensionBundle bundlePath];
    NSString *mainAppPath = [[extensionPath stringByDeletingLastPathComponent]
        stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSLog(@"[WawonaHook] Extension path: %@", extensionPath);
    NSLog(@"[WawonaHook] Main app path: %@", mainAppPath);

    // Look for ssh.dylib in order of preference
    NSArray<NSString *> *dylibCandidates = @[
      [mainAppPath stringByAppendingPathComponent:@"bin/ssh.dylib"],
      [mainAppPath stringByAppendingPathComponent:@"lib/ssh.dylib"],
      [mainAppPath stringByAppendingPathComponent:@"ssh.dylib"],
    ];

    NSString *sshDylibPath = nil;
    for (NSString *candidate in dylibCandidates) {
      if ([fm fileExistsAtPath:candidate]) {
        sshDylibPath = candidate;
        NSLog(@"[WawonaHook] ✓ Found ssh.dylib at: %@", sshDylibPath);
        break;
      }
    }

    if (sshDylibPath) {
      // Use in-process spawn via dlopen - this works reliably on iOS
      NSLog(@"[WawonaHook] Using in-process SSH via dlopen(%@)", sshDylibPath);

      // Create thread args
      WawonaThreadArgs *targs = calloc(1, sizeof(WawonaThreadArgs));
      targs->path = strdup([sshDylibPath UTF8String]);
      int argc = 0;
      while (argv[argc])
        argc++;
      targs->argc = argc;
      targs->argv = malloc(sizeof(char *) * (argc + 1));
      for (int i = 0; i < argc; i++)
        targs->argv[i] = strdup(argv[i]);
      targs->argv[argc] = NULL;

      // Copy file actions for pipe setup
      WawonaInitActions();
      [g_actions_lock lock];
      NSValue *key = [NSValue valueWithPointer:file_actions];
      if (g_actions_map[key]) {
        targs->actions = [g_actions_map[key] copy];
        NSLog(@"[WawonaHook] Captured %lu file actions for SSH",
              (unsigned long)targs->actions.count);
      }
      [g_actions_lock unlock];

      // Spawn SSH in a thread
      pthread_t thread;
      if (pthread_create(&thread, NULL, WawonaGuestThread, targs) != 0) {
        NSLog(@"[WawonaHook] ❌ Failed to create SSH thread");
        gInHook = NO;
        return EAGAIN;
      }

      if (pid)
        *pid = (pid_t)thread;
      NSLog(@"[WawonaHook] ✓ SSH started in thread (pseudo-PID: %lu)",
            (unsigned long)thread);
      gInHook = NO;
      return 0;
    }

    // Fallback: Try executable if dylib not found
    NSLog(@"[WawonaHook] ⚠️ ssh.dylib not found, falling back to executable "
          @"spawn");

    // Find ssh executable
    const char *actualPath = path;
    char *convertedPath = NULL;

    // If path is .dylib, convert to executable path
    if (strstr(path, ".dylib") != NULL) {
      convertedPath = malloc(strlen(path) + 1);
      strcpy(convertedPath, path);
      char *dylibExt = strstr(convertedPath, ".dylib");
      if (dylibExt) {
        *dylibExt = '\0';
        actualPath = convertedPath;
      }
    }

    // Try to find ssh executable in bundle
    NSArray<NSString *> *exeCandidates = @[
      [mainAppPath stringByAppendingPathComponent:@"bin/ssh"],
      [mainAppPath stringByAppendingPathComponent:@"ssh"],
    ];

    for (NSString *candidate in exeCandidates) {
      if ([fm fileExistsAtPath:candidate]) {
        if (convertedPath)
          free(convertedPath);
        convertedPath = strdup([candidate UTF8String]);
        actualPath = convertedPath;
        NSLog(@"[WawonaHook] Found SSH executable at: %s", actualPath);
        break;
      }
    }

    // Verify and ensure permissions
    struct stat st;
    if (stat(actualPath, &st) != 0) {
      NSLog(@"[WawonaHook] ❌ SSH binary not found at: %s", actualPath);
      if (convertedPath)
        free(convertedPath);
      gInHook = NO;
      return ENOENT;
    }

    // Add execute permissions if needed
    if ((st.st_mode & S_IXUSR) == 0) {
      chmod(actualPath, st.st_mode | S_IXUSR | S_IXGRP | S_IXOTH);
      NSLog(@"[WawonaHook] Added execute permissions to SSH");
    }

    // Try posix_spawn (may crash with SIGSEGV, but worth trying as fallback)
    NSLog(@"[WawonaHook] Attempting posix_spawn for SSH at: %s", actualPath);
    gInHook = NO;
    int result =
        ORIG_FUNC(posix_spawn)(pid, actualPath, file_actions, attr, argv, envp);

    if (result != 0) {
      NSLog(@"[WawonaHook] posix_spawn failed: %d (%s)", result,
            strerror(result));
    } else {
      NSLog(@"[WawonaHook] ✓ SSH spawned (PID: %d)", pid ? *pid : -1);
    }

    if (convertedPath)
      free(convertedPath);
    return result;
  }

  // Simple approach: Use in-process dylib spawning for other .dylib files
  // This works because we're already in the extension process
  if (path && strstr(path, ".dylib") != NULL) {
    int result = WawonaInProcessSpawn(pid, path, file_actions, attr,
                                      (char *const *)argv, (char *const *)envp);
    if (result == 0) {
      gInHook = NO;
      return 0;
    }
    // If in-process spawn failed, fall through to try other methods
    NSLog(@"[WawonaHook] In-process spawn failed, trying fallback");
  }

  // Fallback: If we're in the extension (no kernel socket), allow direct
  // posix_spawn This handles non-dylib executables
  const char *kernelSocketPath = getenv("WAWONA_KERNEL_SOCKET");
  if (!kernelSocketPath) {
    // We're in the extension - allow direct spawning
    NSLog(@"[WawonaHook] In extension, allowing direct posix_spawn");
    gInHook = NO;
    return ORIG_FUNC(posix_spawn)(pid, path, file_actions, attr, argv, envp);
  }

  // If we have a kernel socket, try forwarding (for guest processes)
  int result =
      WawonaForwardSpawn(pid, path, (char *const *)argv, (char *const *)envp);
  if (result == 0) {
    gInHook = NO;
    return 0;
  }

  // Last resort: direct spawn
  gInHook = NO;
  return ORIG_FUNC(posix_spawn)(pid, path, file_actions, attr, argv, envp);
}

static int hook_execve(const char *path, char *const argv[],
                       char *const envp[]) {
  if (gInHook || getenv("WAWONA_NO_HOOKS")) {
    return ORIG_FUNC(execve)(path, argv, envp);
  }

  gInHook = YES;
  NSLog(@"[WawonaHook] Intercepted execve for: %s", path);

  // For SSH, allow direct execve (don't forward via kernel socket)
  // This is needed for SSH test and direct SSH execution
  if (path && (strstr(path, "ssh") != NULL ||
               (argv && argv[0] && strstr(argv[0], "ssh") != NULL))) {
    NSLog(@"[WawonaHook] SSH detected in execve - checking permissions before "
          @"execve");

    const char *actualPath = path;
    char *convertedPath = NULL;

    // Verify file exists and check permissions
    struct stat st;
    if (stat(actualPath, &st) != 0) {
      NSLog(@"[WawonaHook] ❌ SSH binary does not exist at: %s (errno: %d)",
            actualPath, errno);
      gInHook = NO;
      return errno ? errno : ENOENT;
    }

    NSLog(@"[WawonaHook] SSH binary exists: mode=%o, size=%lld", st.st_mode,
          st.st_size);

    // Ensure file has execute permissions (required even if code signed)
    // iOS requires both code signing AND execute permissions
    if ((st.st_mode & S_IXUSR) == 0) {
      NSLog(@"[WawonaHook] SSH binary missing execute permissions (mode=%o), "
            @"fixing...",
            st.st_mode);
      mode_t newMode =
          st.st_mode | S_IXUSR | S_IXGRP | S_IXOTH; // Add execute bits
      if (chmod(actualPath, newMode) == 0) {
        // Verify it worked
        if (access(actualPath, X_OK) == 0) {
          NSLog(@"[WawonaHook] ✓ Added execute permissions (now executable)");
        } else {
          NSLog(@"[WawonaHook] ⚠️ chmod succeeded but file still not executable "
                @"(errno: %d)",
                errno);
        }
      } else {
        NSLog(@"[WawonaHook] ⚠️ Failed to add execute permissions (errno: %d)",
              errno);
      }
    } else {
      // Verify it's actually executable
      if (access(actualPath, X_OK) == 0) {
        NSLog(@"[WawonaHook] SSH binary has execute permissions");
      } else {
        NSLog(@"[WawonaHook] ⚠️ Mode shows execute bit but access() says not "
              @"executable");
      }
    }

    // Check if binary is code signed (ensure signing before spawn)
    // In Simulator, we can try ad-hoc signing if needed
    const char *codesignPath = "/usr/bin/codesign";
    if (access(codesignPath, X_OK) == 0) {
      // Check if signed - use ORIG_FUNC to avoid hook recursion
      pid_t checkPid = 0;
      char *checkArgs[] = {"codesign", "-v", (char *)actualPath, NULL};
      int checkSpawn = ORIG_FUNC(posix_spawn)(&checkPid, codesignPath, NULL,
                                              NULL, checkArgs, NULL);

      if (checkSpawn == 0) {
        int status = 0;
        ORIG_FUNC(waitpid)(checkPid, &status, 0);
        int checkResult = WIFEXITED(status) ? WEXITSTATUS(status) : -1;

        if (checkResult != 0) {
          // Binary is not signed - sign it before spawn
          NSLog(@"[WawonaHook] SSH binary not code signed, signing now...");
          pid_t signPid = 0;
          char *signArgs[] = {
              "codesign",         "--force",          "--sign", "-",
              "--timestamp=none", (char *)actualPath, NULL};
          int signSpawn = ORIG_FUNC(posix_spawn)(&signPid, codesignPath, NULL,
                                                 NULL, signArgs, NULL);

          if (signSpawn == 0) {
            int signStatus = 0;
            ORIG_FUNC(waitpid)(signPid, &signStatus, 0);
            if (WIFEXITED(signStatus) && WEXITSTATUS(signStatus) == 0) {
              NSLog(@"[WawonaHook] ✓ Successfully code signed SSH binary");
            } else {
              NSLog(@"[WawonaHook] ⚠️ Code signing failed (exit %d)",
                    WEXITSTATUS(signStatus));
            }
          } else {
            NSLog(@"[WawonaHook] ⚠️ Failed to spawn codesign (errno: %d)",
                  signSpawn);
          }
        } else {
          NSLog(@"[WawonaHook] SSH binary is already code signed");
        }
      } else {
        NSLog(@"[WawonaHook] ⚠️ Failed to check code signing status (errno: %d)",
              checkSpawn);
      }
    } else {
      NSLog(@"[WawonaHook] ⚠️ codesign not available, assuming binary is signed "
            @"by app bundle");
    }

    // IMPORTANT: Use posix_spawn instead of execve to keep extension alive
    // execve replaces the current process, which terminates the XPC connection
    // and prevents output capture. posix_spawn creates a child process.
    NSLog(@"[WawonaHook] Using posix_spawn (not execve) to keep extension "
          @"alive for output capture");

    // CRITICAL: iOS Simulator requires DYLD_ROOT_PATH and other dyld variables
    // The passed envp might not have these, so we need to merge with current
    // env
    extern char **environ;
    NSMutableDictionary *mergedEnv = [NSMutableDictionary dictionary];

    // First, copy ALL environment variables from current process
    // This ensures we inherit DYLD_ROOT_PATH if it exists
    for (int i = 0; environ[i] != NULL; i++) {
      char *entry = environ[i];
      char *eq = strchr(entry, '=');
      if (eq) {
        NSString *key = [[NSString alloc] initWithBytes:entry
                                                 length:(eq - entry)
                                               encoding:NSUTF8StringEncoding];
        NSString *val = [NSString stringWithUTF8String:eq + 1];
        if (key && val)
          mergedEnv[key] = val;
      }
    }

    // Then add all variables from the passed envp (overwriting if same key)
    if (envp) {
      for (int i = 0; envp[i] != NULL; i++) {
        char *eq = strchr(envp[i], '=');
        if (eq) {
          NSString *key = [[NSString alloc] initWithBytes:envp[i]
                                                   length:(eq - envp[i])
                                                 encoding:NSUTF8StringEncoding];
          NSString *val = [NSString stringWithUTF8String:eq + 1];
          if (key && val)
            mergedEnv[key] = val;
        }
      }
    }

    // CRITICAL: If DYLD_ROOT_PATH is not set, we need to find the iOS Simulator
    // runtime This is required for spawning binaries built for iOS Simulator
    if (!mergedEnv[@"DYLD_ROOT_PATH"]) {
      NSLog(@"[WawonaHook] DYLD_ROOT_PATH not in environment, searching for "
            @"simulator runtime...");

      // Try to find the iOS Simulator runtime root
      // The path is typically:
      // /Library/Developer/CoreSimulator/Volumes/iOS_XXXX/.../RuntimeRoot
      NSFileManager *fm = [NSFileManager defaultManager];
      NSString *coreSimPath = @"/Library/Developer/CoreSimulator/Volumes";

      if ([fm fileExistsAtPath:coreSimPath]) {
        NSError *error = nil;
        NSArray *volumes =
            [fm contentsOfDirectoryAtPath:coreSimPath error:&error];

        // Find the most recent iOS volume
        NSString *iosVolume = nil;
        for (NSString *vol in volumes) {
          if ([vol hasPrefix:@"iOS_"]) {
            iosVolume = vol;
            // Keep searching - last one is usually newest
          }
        }

        if (iosVolume) {
          // Construct the full path to RuntimeRoot
          NSString *basePath =
              [[coreSimPath stringByAppendingPathComponent:iosVolume]
                  stringByAppendingPathComponent:
                      @"Library/Developer/CoreSimulator/Profiles/Runtimes"];

          NSArray *runtimes = [fm contentsOfDirectoryAtPath:basePath error:nil];
          for (NSString *runtime in runtimes) {
            if ([runtime hasSuffix:@".simruntime"]) {
              NSString *runtimeRoot =
                  [[[basePath stringByAppendingPathComponent:runtime]
                      stringByAppendingPathComponent:@"Contents/Resources"]
                      stringByAppendingPathComponent:@"RuntimeRoot"];

              if ([fm fileExistsAtPath:runtimeRoot]) {
                mergedEnv[@"DYLD_ROOT_PATH"] = runtimeRoot;
                NSLog(@"[WawonaHook] ✓ Found DYLD_ROOT_PATH: %@", runtimeRoot);
                break;
              }
            }
          }
        }
      }

      if (!mergedEnv[@"DYLD_ROOT_PATH"]) {
        NSLog(@"[WawonaHook] ⚠️ Could not find DYLD_ROOT_PATH - SSH may fail!");
      }
    } else {
      NSLog(@"[WawonaHook] DYLD_ROOT_PATH already set: %@",
            mergedEnv[@"DYLD_ROOT_PATH"]);
    }

    // Also ensure HOME and USER are set for SSH
    if (!mergedEnv[@"HOME"]) {
      const char *home = getenv("HOME");
      if (home)
        mergedEnv[@"HOME"] = [NSString stringWithUTF8String:home];
    }
    if (!mergedEnv[@"USER"]) {
      const char *user = getenv("USER");
      if (user)
        mergedEnv[@"USER"] = [NSString stringWithUTF8String:user];
    }

    // CRITICAL: Propagate SSH password for iOS (readpassphrase uses
    // environment) Check multiple sources for the password
    if (!mergedEnv[@"SSH_ASKPASS_PASSWORD"]) {
      // Try WAWONA_SSH_PASSWORD first (set by WawonaWaypipeRunner)
      const char *wawonaPass = getenv("WAWONA_SSH_PASSWORD");
      if (wawonaPass && strlen(wawonaPass) > 0) {
        mergedEnv[@"SSH_ASKPASS_PASSWORD"] =
            [NSString stringWithUTF8String:wawonaPass];
        mergedEnv[@"SSHPASS"] = [NSString stringWithUTF8String:wawonaPass];
        NSLog(@"[WawonaHook] ✓ Set SSH_ASKPASS_PASSWORD from "
              @"WAWONA_SSH_PASSWORD");
      }
    }

    // Also check for environment test password
    if (!mergedEnv[@"SSH_ASKPASS_PASSWORD"]) {
      const char *envPass = getenv("SSH_ASKPASS_PASSWORD");
      if (envPass && strlen(envPass) > 0) {
        mergedEnv[@"SSH_ASKPASS_PASSWORD"] =
            [NSString stringWithUTF8String:envPass];
        mergedEnv[@"SSHPASS"] = [NSString stringWithUTF8String:envPass];
        NSLog(
            @"[WawonaHook] ✓ SSH_ASKPASS_PASSWORD already set in environment");
      }
    }

    if (!mergedEnv[@"SSH_ASKPASS_PASSWORD"]) {
      NSLog(@"[WawonaHook] ⚠️ No SSH password in environment - password auth "
            @"may fail");
    }

    // Convert to envp array
    NSUInteger envCount = mergedEnv.count;
    char **mergedEnvp = calloc(envCount + 1, sizeof(char *));
    NSUInteger idx = 0;
    for (NSString *key in mergedEnv) {
      NSString *entry =
          [NSString stringWithFormat:@"%@=%@", key, mergedEnv[key]];
      mergedEnvp[idx++] = strdup([entry UTF8String]);
    }
    mergedEnvp[envCount] = NULL;

    NSLog(@"[WawonaHook] Spawning SSH with %lu environment variables",
          (unsigned long)envCount);

    pid_t sshPid = 0;
    int spawnResult = ORIG_FUNC(posix_spawn)(&sshPid, actualPath, NULL, NULL,
                                             argv, mergedEnvp);

    // Free merged env
    for (NSUInteger i = 0; i < envCount; i++) {
      free(mergedEnvp[i]);
    }
    free(mergedEnvp);

    if (spawnResult != 0) {
      NSLog(@"[WawonaHook] ❌ posix_spawn failed for SSH: %d (%s)", spawnResult,
            strerror(spawnResult));
      gInHook = NO;
      errno = spawnResult;
      return -1;
    }

    NSLog(@"[WawonaHook] ✓ SSH spawned as child process with PID: %d", sshPid);

    // Wait for SSH to complete and relay its exit status
    int sshStatus = 0;
    pid_t waitedPid = ORIG_FUNC(waitpid)(sshPid, &sshStatus, 0);

    if (waitedPid == sshPid) {
      if (WIFEXITED(sshStatus)) {
        int exitCode = WEXITSTATUS(sshStatus);
        NSLog(@"[WawonaHook] SSH exited with code: %d", exitCode);
        // Exit the extension with SSH's exit code
        _exit(exitCode);
      } else if (WIFSIGNALED(sshStatus)) {
        NSLog(@"[WawonaHook] SSH killed by signal: %d", WTERMSIG(sshStatus));
        _exit(128 + WTERMSIG(sshStatus));
      }
    } else {
      NSLog(@"[WawonaHook] waitpid failed: %d (%s)", errno, strerror(errno));
    }

    // Fallback: exit with unknown status
    _exit(1);
  }

  // Try forwarding via kernel socket for other processes
  pid_t pid;
  int result =
      WawonaForwardSpawn(&pid, path, (char *const *)argv, (char *const *)envp);
  if (result == 0) {
    NSLog(@"[WawonaHook] execve forwarded, exiting current process...");
    exit(0);
  }

  // Forwarding failed - allow direct execve as fallback
  NSLog(@"[WawonaHook] Forwarding failed, allowing direct execve");
  gInHook = NO;
  return ORIG_FUNC(execve)(path, argv, envp);
}

static pid_t hook_waitpid(pid_t pid, int *stat_loc, int options) {
  if (gInHook || getenv("WAWONA_NO_HOOKS")) {
    return ORIG_FUNC(waitpid)(pid, stat_loc, options);
  }

  if (pid > 100000) {
    pthread_t thread = (pthread_t)pid;
    if (options & WNOHANG)
      return 0;
    pthread_join(thread, NULL);
    if (stat_loc)
      *stat_loc = 0;
    return pid;
  }

  return ORIG_FUNC(waitpid)(pid, stat_loc, options);
}

// --- In-Process Thread Spawning ---
// (WawonaThreadArgs is defined at the top of the file)

static void *WawonaGuestThread(void *data) {
  WawonaThreadArgs *args = (WawonaThreadArgs *)data;
  NSLog(@"[WawonaHook] Guest thread started for: %s", args->path);

  // Apply file actions FIRST - these set up stdin/stdout/stderr pipes from
  // waypipe
  if (args->actions && args->actions.count > 0) {
    NSLog(@"[WawonaHook] Applying %lu file actions to thread",
          (unsigned long)args->actions.count);
    for (NSValue *val in args->actions) {
      WAction *a = [val pointerValue];
      if (a->type == WActionDup2) {
        NSLog(@"[WawonaHook] Thread applying dup2(%d, %d)", a->fd, a->new_fd);
        if (dup2(a->fd, a->new_fd) < 0) {
          NSLog(@"[WawonaHook] dup2 failed: %s", strerror(errno));
        }
      } else if (a->type == WActionClose) {
        NSLog(@"[WawonaHook] Thread applying close(%d)", a->fd);
        close(a->fd);
      }
    }
    NSLog(@"[WawonaHook] File actions applied, stdin=%d stdout=%d stderr=%d",
          STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO);
  } else {
    // No file actions - waypipe might be using direct pipes or the file
    // descriptors are already set up correctly. Since we're in the same
    // process, stdin/stdout/stderr should already be connected to waypipe's
    // pipes. Just log current state.
    NSLog(@"[WawonaHook] No file actions to apply - using current stdin=%d "
          @"stdout=%d stderr=%d",
          STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO);

    // Ensure file descriptors are valid and not closed
    if (fcntl(STDIN_FILENO, F_GETFD) < 0) {
      NSLog(@"[WawonaHook] Warning: stdin is invalid");
    }
    if (fcntl(STDOUT_FILENO, F_GETFD) < 0) {
      NSLog(@"[WawonaHook] Warning: stdout is invalid");
    }
    if (fcntl(STDERR_FILENO, F_GETFD) < 0) {
      NSLog(@"[WawonaHook] Warning: stderr is invalid");
    }
  }

  // CRITICAL: Ensure SSH password is available in environment for our patched
  // readpassphrase Check for password from multiple sources
  const char *sshPass = getenv("SSH_ASKPASS_PASSWORD");
  const char *wawonaPass = getenv("WAWONA_SSH_PASSWORD");
  const char *sshpass = getenv("SSHPASS");

  if (!sshPass && wawonaPass) {
    setenv("SSH_ASKPASS_PASSWORD", wawonaPass, 1);
    setenv("SSHPASS", wawonaPass, 1);
    NSLog(@"[WawonaHook] Set SSH_ASKPASS_PASSWORD from WAWONA_SSH_PASSWORD");
  } else if (!sshPass && sshpass) {
    setenv("SSH_ASKPASS_PASSWORD", sshpass, 1);
    NSLog(@"[WawonaHook] Set SSH_ASKPASS_PASSWORD from SSHPASS");
  } else if (sshPass) {
    NSLog(@"[WawonaHook] SSH_ASKPASS_PASSWORD already set (length=%lu)",
          strlen(sshPass));
  } else {
    NSLog(@"[WawonaHook] ⚠️ No SSH password found - password auth will fail!");
  }

  void *handle = dlopen(args->path, RTLD_NOW | RTLD_GLOBAL);
  if (!handle) {
    NSLog(@"[WawonaHook] Guest thread failed to dlopen %s: %s", args->path,
          dlerror());
    return NULL;
  }

  int (*entry)(int, char **) = dlsym(handle, "ssh_main");
  if (!entry)
    entry = dlsym(handle, "waypipe_main");
  if (!entry)
    entry = dlsym(handle, "hello_entry");
  if (!entry)
    entry = dlsym(handle, "main");

  if (entry) {
    NSLog(@"[WawonaHook] Guest thread jumping to entry point at %p", entry);
    NSLog(@"[WawonaHook] About to call SSH with %d args", args->argc);
    for (int i = 0; i < args->argc && i < 10; i++) {
      NSLog(@"[WawonaHook]   argv[%d] = %s", i,
            args->argv[i] ? args->argv[i] : "(null)");
    }

    // Flush stdout/stderr before calling SSH to ensure any buffered output is
    // visible
    fflush(stdout);
    fflush(stderr);

    // SSH might be blocking on stdin - check if we need to handle password
    // input Since waypipe creates pipes, stdin should already be connected But
    // SSH might be waiting for password prompt

    // Run SSH in the thread - it should use the current stdin/stdout/stderr
    // which are already connected to waypipe's pipes
    int rc = entry(args->argc, args->argv);

    // Flush again after SSH returns
    fflush(stdout);
    fflush(stderr);

    NSLog(@"[WawonaHook] Guest thread finished with code: %d", rc);

    // If SSH exited with an error, it might have been a communication issue
    if (rc != 0) {
      NSLog(@"[WawonaHook] SSH exited with code %d - check if pipes were set "
            @"up correctly",
            rc);
    }
  } else {
    NSLog(@"[WawonaHook] No entry point found for %s", args->path);
  }

  for (int i = 0; i < args->argc; i++)
    free(args->argv[i]);
  free(args->argv);
  free(args->path);
  return NULL;
}

static int WawonaInProcessSpawn(pid_t *pid, const char *path,
                                const posix_spawn_file_actions_t *file_actions,
                                const posix_spawnattr_t *attr,
                                char *const argv[], char *const envp[]) {
  WawonaThreadArgs *targs = calloc(1, sizeof(WawonaThreadArgs));
  targs->path = strdup(path);
  int argc = 0;
  while (argv[argc])
    argc++;
  targs->argc = argc;
  targs->argv = malloc(sizeof(char *) * (argc + 1));
  for (int i = 0; i < argc; i++)
    targs->argv[i] = strdup(argv[i]);
  targs->argv[argc] = NULL;

  // Copy actions - these contain the pipe setup from waypipe
  WawonaInitActions();
  [g_actions_lock lock];
  NSValue *key = [NSValue valueWithPointer:file_actions];

  // Debug: print all keys we have
  NSLog(@"[WawonaHook] Looking for file_actions pointer %p", file_actions);
  NSLog(@"[WawonaHook] We have %lu file_actions entries in map",
        (unsigned long)g_actions_map.count);
  for (NSValue *k in g_actions_map.allKeys) {
    NSLog(@"[WawonaHook]   Map has key: %p", [k pointerValue]);
  }

  if (g_actions_map[key]) {
    targs->actions = [g_actions_map[key] copy];
    NSLog(@"[WawonaHook] Captured %lu file actions for in-process spawn",
          (unsigned long)targs->actions.count);
  } else {
    NSLog(@"[WawonaHook] No file actions found for file_actions pointer %p",
          file_actions);
    // Try to find a matching entry (maybe pointer changed?)
    for (NSValue *k in g_actions_map.allKeys) {
      if ([k pointerValue] == file_actions) {
        targs->actions = [g_actions_map[k] copy];
        NSLog(@"[WawonaHook] Found matching entry via iteration, %lu actions",
              (unsigned long)targs->actions.count);
        break;
      }
    }
  }
  [g_actions_lock unlock];

  pthread_t thread;
  if (pthread_create(&thread, NULL, WawonaGuestThread, targs) != 0) {
    return -1;
  }
  if (pid)
    *pid = (pid_t)thread;
  return 0;
}

static int WawonaForwardSpawn(pid_t *pid, const char *path, char *const argv[],
                              char *const envp[]) {
  const char *kernelSocketPath = getenv("WAWONA_KERNEL_SOCKET");
  if (!kernelSocketPath) {
    kernelSocketPath = getenv("HIAH_KERNEL_SOCKET");
  }
  if (!kernelSocketPath)
    return -1;

  int sock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sock < 0)
    return -1;

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, kernelSocketPath, sizeof(addr.sun_path) - 1);

  if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    return -1;
  }

  NSMutableArray *args = [NSMutableArray array];
  if (argv) {
    for (int i = 1; argv[i] != NULL; i++)
      [args addObject:[NSString stringWithUTF8String:argv[i]]];
  }
  NSMutableDictionary *env = [NSMutableDictionary dictionary];
  if (envp) {
    for (int i = 0; envp[i] != NULL; i++) {
      NSString *entry = [NSString stringWithUTF8String:envp[i]];
      NSRange range = [entry rangeOfString:@"="];
      if (range.location != NSNotFound)
        env[[entry substringToIndex:range.location]] =
            [entry substringFromIndex:range.location + 1];
    }
  }

  NSDictionary *req = @{
    @"command" : @"spawn",
    @"path" : [NSString stringWithUTF8String:path],
    @"args" : args,
    @"env" : env
  };
  NSData *reqData =
      [NSJSONSerialization dataWithJSONObject:req options:0 error:nil];
  write(sock, reqData.bytes, reqData.length);
  write(sock, "\n", 1);

  char buffer[1024];
  ssize_t n = read(sock, buffer, sizeof(buffer) - 1);
  close(sock);
  if (n > 0) {
    buffer[n] = '\0';
    NSDictionary *resp = [NSJSONSerialization
        JSONObjectWithData:[NSData dataWithBytes:buffer length:n]
                   options:0
                     error:nil];
    if ([resp[@"status"] isEqualToString:@"ok"]) {
      if (pid)
        *pid = [resp[@"pid"] intValue];
      return 0;
    }
  }
  return -1;
}

__attribute__((visibility("default"))) void WawonaInstallHooks(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    WawonaInitActions();
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, (void *)posix_spawn,
                           (void *)hook_posix_spawn, NULL);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, (void *)execve,
                           (void *)hook_execve, NULL);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, (void *)waitpid,
                           (void *)hook_waitpid, NULL);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL,
                           (void *)posix_spawn_file_actions_adddup2,
                           (void *)hook_posix_spawn_file_actions_adddup2, NULL);
    litehook_rebind_symbol(
        LITEHOOK_REBIND_GLOBAL, (void *)posix_spawn_file_actions_addclose,
        (void *)hook_posix_spawn_file_actions_addclose, NULL);
    NSLog(@"[WawonaHook] FULL VIRTUAL KERNEL HOOKS INSTALLED.");
  });
}

__attribute__((constructor)) void WawonaConstructor(void) {
  WawonaInstallHooks();
}
