#import <Foundation/Foundation.h>
// #import "WawonaKernel.h"
#import "../ui/Settings/WawonaPreferencesManager.h"
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <HIAHKernel/HIAHKernel.h>
#endif

int main(int argc, char *argv[]) {
  @autoreleasepool {
    NSLog(@"🔐 OpenSSH Test for iOS");
    NSLog(@"========================");

    // Get preferences
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];

    // Build SSH arguments similar to waypipe
    NSMutableArray *sshArgs = [NSMutableArray array];
    [sshArgs addObject:@"-vvv"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"StrictHostKeyChecking=no"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"UserKnownHostsFile=/dev/null"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"ConnectTimeout=10"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"NumberOfPasswordPrompts=1"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"ServerAliveInterval=5"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"ServerAliveCountMax=3"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"LogLevel=DEBUG3"];
    [sshArgs addObject:@"-4"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"ControlMaster=no"];
    [sshArgs addObject:@"-o"];
    [sshArgs addObject:@"ControlPath=none"];

    if (prefs.waypipeSSHPassword.length > 0) {
      [sshArgs addObject:@"-o"];
      [sshArgs
          addObject:@"PreferredAuthentications=password,keyboard-interactive"];
      [sshArgs addObject:@"-o"];
      [sshArgs addObject:@"PubkeyAuthentication=no"];
    } else if (prefs.waypipeSSHKeyPath.length > 0) {
      [sshArgs addObject:@"-i"];
      [sshArgs addObject:prefs.waypipeSSHKeyPath];
      [sshArgs addObject:@"-o"];
      [sshArgs addObject:@"PreferredAuthentications=publickey"];
    }

    // Build target
    NSString *sshTarget = nil;
    if (prefs.waypipeSSHEnabled) {
      if (prefs.waypipeSSHUser.length > 0 && prefs.waypipeSSHHost.length > 0) {
        sshTarget = [NSString stringWithFormat:@"%@@%@", prefs.waypipeSSHUser,
                                               prefs.waypipeSSHHost];
      } else if (prefs.waypipeSSHHost.length > 0) {
        sshTarget = prefs.waypipeSSHHost;
      }
    }

    if (!sshTarget || sshTarget.length == 0) {
      NSLog(@"❌ Error: SSH target not configured");
      NSLog(@"   Set WaypipeSSHHost and WaypipeSSHUser in preferences");
      return 1;
    }

    [sshArgs addObject:sshTarget];
    [sshArgs addObject:@"echo 'SSH connection test successful!'"];

    // Find SSH binary
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSArray<NSString *> *candidates = @[
      [bundlePath stringByAppendingPathComponent:@"bin/ssh"],
      [bundlePath stringByAppendingPathComponent:@"ssh"],
    ];

    NSString *sshPath = nil;
    for (NSString *candidate in candidates) {
      if ([fm fileExistsAtPath:candidate] &&
          [fm isExecutableFileAtPath:candidate]) {
        sshPath = candidate;
        break;
      }
    }

    if (!sshPath) {
      NSLog(@"❌ Error: SSH binary not found in bundle");
      NSLog(@"   Looked in: %@", candidates);
      return 1;
    }

    NSLog(@"✓ Found SSH binary at: %@", sshPath);
    NSLog(@"✓ SSH target: %@", sshTarget);
    NSLog(@"✓ SSH arguments: %@", [sshArgs componentsJoinedByString:@" "]);

    // Set up environment
    NSMutableDictionary *env =
        [[[NSProcessInfo processInfo] environment] mutableCopy]
            ?: [NSMutableDictionary dictionary];
    if (prefs.waypipeSSHUser.length > 0) {
      env[@"USER"] = prefs.waypipeSSHUser;
      env[@"LOGNAME"] = prefs.waypipeSSHUser;
    }
    if (prefs.waypipeSSHPassword.length > 0) {
      // Our patched iOS SSH reads password from SSH_ASKPASS_PASSWORD or SSHPASS
      env[@"SSH_ASKPASS_PASSWORD"] = prefs.waypipeSSHPassword;
      env[@"SSHPASS"] = prefs.waypipeSSHPassword;
      env[@"WAWONA_SSH_PASSWORD"] = prefs.waypipeSSHPassword;
    }

    // Use HIAHKernel to spawn SSH
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    kernel.appGroupIdentifier = @"group.com.aspauldingcode.Wawona";
    kernel.extensionIdentifier = @"com.aspauldingcode.Wawona.WawonaSSHRunner";

    __block int exitCode = -1;
    __block BOOL completed = NO;

    kernel.onOutput = ^(pid_t pid, NSString *output) {
      printf("%s", [output UTF8String]);
      fflush(stdout);
    };

    NSLog(@"🚀 Spawning SSH via HIAHKernel...");
    [kernel spawnVirtualProcessWithPath:sshPath
                              arguments:sshArgs
                            environment:env
                             completion:^(pid_t pid, NSError *_Nullable error) {
                               if (error) {
                                 NSLog(@"❌ Kernel spawn failed: %@", error);
                                 exitCode = 1;
                               } else {
                                 NSLog(@"✓ SSH spawned successfully (PID: %d)",
                                       pid);
                                 // Wait for process to complete
                                 // In a real scenario, we'd monitor the process
                                 exitCode = 0;
                               }
                               completed = YES;
                             }];

    // Wait for completion (simple timeout)
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!completed && [timeout timeIntervalSinceNow] > 0) {
      [[NSRunLoop currentRunLoop]
          runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    if (!completed) {
      NSLog(@"⏱️  Timeout waiting for SSH to complete");
      return 124; // Timeout exit code
    }

    return exitCode;
  }
}
