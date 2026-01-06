#import "WawonaAppScanner.h"
#import "../ui/Settings/WawonaPreferencesManager.h"
#include <dlfcn.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

@implementation WaylandApp
@end

// Blacklisted app identifiers (launcher itself, etc.)
static NSArray<NSString *> *_blacklistedAppIds = nil;

static void initBlacklist(void) {
    if (!_blacklistedAppIds) {
        _blacklistedAppIds = @[
            @"com.aspauldingcode.Wawona.Launcher",
            @"wawona-launcher",
            @"launcher"
        ];
    }
}

static BOOL isAppBlacklisted(NSString *appId, NSString *executableName) {
    initBlacklist();
    NSString *lowerId = appId.lowercaseString;
    NSString *lowerExec = executableName.lowercaseString;
    
    for (NSString *blacklisted in _blacklistedAppIds) {
        NSString *lowerBlack = blacklisted.lowercaseString;
        if ([lowerId containsString:lowerBlack] || [lowerExec containsString:lowerBlack]) {
            return YES;
        }
    }
    return NO;
}

@interface WawonaAppScanner ()
@property (nonatomic, strong) NSMutableArray<WaylandApp *> *availableApps;
@property (nonatomic, strong) NSMutableDictionary *runningProcesses;
@end

@implementation WawonaAppScanner

- (instancetype)initWithDisplay:(struct wl_display *)display {
    self = [super init];
    if (self) {
        _display = display;
        _availableApps = [NSMutableArray array];
        _runningProcesses = [NSMutableDictionary dictionary];
        
        [self setupWaylandEnvironment];
        [self scanForApplications];
    }
    return self;
}

+ (NSArray<NSString *> *)bundledApplicationSearchPaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSFileManager *fm = [NSFileManager defaultManager];
    
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Check inside app bundle
    NSString *bundlePath = [mainBundle bundlePath];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"Applications"]];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"apps"]];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"Frameworks/Applications"]];
    
    // Documents directory for side-loaded apps
    NSString *docsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docsPath) {
        [paths addObject:[docsPath stringByAppendingPathComponent:@"Applications"]];
    }
    
    // App group container
    NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:@"group.com.aspauldingcode.Wawona"];
    if (groupURL) {
        [paths addObject:[groupURL.path stringByAppendingPathComponent:@"Applications"]];
    }
#else
    // macOS: Check inside app bundle
    NSString *resourcePath = [mainBundle resourcePath];
    [paths addObject:[resourcePath stringByAppendingPathComponent:@"Applications"]];
    
    NSString *execPath = [[mainBundle executablePath] stringByDeletingLastPathComponent];
    [paths addObject:[execPath stringByAppendingPathComponent:@"apps"]];
    [paths addObject:[execPath stringByAppendingPathComponent:@"Applications"]];
    
    // Contents/MacOS/Applications for bundled apps
    [paths addObject:[[execPath stringByDeletingLastPathComponent] 
                      stringByAppendingPathComponent:@"Applications"]];
    
    // User-installed apps
    NSString *homeApps = [NSHomeDirectory() stringByAppendingPathComponent:@".local/share/wawona/applications"];
    [paths addObject:homeApps];
    
    // System-wide apps
    [paths addObject:@"/usr/local/share/wawona/applications"];
#endif
    
    return paths;
}

- (void)setupWaylandEnvironment {
    NSString *runtimeDir = nil;
    
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    @try {
        WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
        NSString *preferred = prefs ? [prefs waylandSocketDir] : nil;
        if (preferred.length > 0) {
            runtimeDir = preferred;
        }
    } @catch (NSException *exception) {
        runtimeDir = nil;
    }
    
    if (runtimeDir.length == 0) {
        NSURL *groupURL = [[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:@"group.com.aspauldingcode.Wawona"];
        if (groupURL) {
            runtimeDir = [groupURL.path stringByAppendingPathComponent:@"runtime"];
        } else {
            runtimeDir = NSTemporaryDirectory();
        }
    }
#else
    if (!getenv("XDG_RUNTIME_DIR")) {
        runtimeDir = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
    }
#endif
    
    if (runtimeDir.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:runtimeDir
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions: @0700}
                                                        error:nil];
        setenv("XDG_RUNTIME_DIR", [runtimeDir UTF8String], 1);
    }
    
    const char *socket_name = wl_display_add_socket_auto(_display);
    if (socket_name) {
        setenv("WAYLAND_DISPLAY", socket_name, 1);
        NSLog(@"🎯 Wayland socket: %s", socket_name);
    } else {
        NSLog(@"❌ Failed to add Wayland socket");
    }
}

- (NSString *)waylandSocketPath {
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    const char *socket_name = getenv("WAYLAND_DISPLAY");
    
    if (runtime_dir && socket_name) {
        return [NSString stringWithFormat:@"%s/%s", runtime_dir, socket_name];
    }
    return nil;
}

- (void)refreshApplicationList {
    [self scanForApplications];
}

- (void)scanForApplications {
    [self.availableApps removeAllObjects];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *searchPaths = [WawonaAppScanner bundledApplicationSearchPaths];
    
    NSLog(@"🔍 Scanning %lu paths for bundled Wayland applications", (unsigned long)searchPaths.count);
    
    for (NSString *searchPath in searchPaths) {
        if (![fm fileExistsAtPath:searchPath]) {
            continue;
        }
        
        NSLog(@"🔍 Scanning: %@", searchPath);
        [self scanDirectory:searchPath];
    }
    
    NSLog(@"🎯 Found %lu Wayland applications", (unsigned long)self.availableApps.count);
}

- (void)scanDirectory:(NSString *)directory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    NSArray *contents = [fm contentsOfDirectoryAtPath:directory error:&error];
    if (error) return;
    
    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        
        NSString *itemPath = [directory stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        
        if (![fm fileExistsAtPath:itemPath isDirectory:&isDir]) continue;
        
        if (isDir) {
            // Look for app metadata
            WaylandApp *app = [self discoverAppInDirectory:itemPath];
            if (app && !app.isBlacklisted) {
                [self.availableApps addObject:app];
                NSLog(@"✅ Found app: %@ (%@)", app.name, app.appId);
            }
        }
    }
}

- (WaylandApp *)discoverAppInDirectory:(NSString *)directory {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Try various metadata file locations
    NSArray<NSString *> *metadataPaths = @[
        [directory stringByAppendingPathComponent:@"share/wawona/app.json"],
        [directory stringByAppendingPathComponent:@"app.json"],
        [directory stringByAppendingPathComponent:@"metadata.json"],
        [directory stringByAppendingPathComponent:@"share/applications/app.desktop"]
    ];
    
    for (NSString *metadataPath in metadataPaths) {
        if ([fm fileExistsAtPath:metadataPath]) {
            if ([metadataPath hasSuffix:@".json"]) {
                return [self parseJsonMetadata:metadataPath basePath:directory];
            } else if ([metadataPath hasSuffix:@".desktop"]) {
                return [self parseDesktopFile:metadataPath basePath:directory];
            }
        }
    }
    
    // Auto-discover from bin/ directory
    NSString *binPath = [directory stringByAppendingPathComponent:@"bin"];
    if ([fm fileExistsAtPath:binPath]) {
        NSArray *binContents = [fm contentsOfDirectoryAtPath:binPath error:nil];
        for (NSString *binItem in binContents) {
            if ([binItem hasPrefix:@"."]) continue;
            
            NSString *execPath = [binPath stringByAppendingPathComponent:binItem];
            if ([fm isExecutableFileAtPath:execPath]) {
                NSString *appId = [NSString stringWithFormat:@"auto.%@", binItem];
                
                if (!isAppBlacklisted(appId, binItem)) {
                    WaylandApp *app = [[WaylandApp alloc] init];
                    app.appId = appId;
                    app.name = [binItem capitalizedString];
                    app.executablePath = execPath;
                    app.appDescription = @"Auto-discovered Wayland application";
                    app.categories = @[@"Utility"];
                    app.isBlacklisted = NO;
                    return app;
                }
            }
        }
    }
    
    return nil;
}

- (WaylandApp *)parseJsonMetadata:(NSString *)path basePath:(NSString *)basePath {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || !json) {
        NSLog(@"⚠️ Failed to parse %@: %@", path, error);
        return nil;
    }
    
    WaylandApp *app = [[WaylandApp alloc] init];
    app.appId = json[@"id"] ?: [[basePath lastPathComponent] lowercaseString];
    app.name = json[@"name"] ?: [basePath lastPathComponent];
    app.appDescription = json[@"description"] ?: @"";
    app.categories = json[@"categories"] ?: @[];
    
    // Resolve executable path
    NSString *executable = json[@"executable"];
    if (executable) {
        if ([executable hasPrefix:@"/"]) {
            app.executablePath = executable;
        } else {
            app.executablePath = [[basePath stringByAppendingPathComponent:@"bin"] 
                                  stringByAppendingPathComponent:executable];
        }
    }
    
    // Resolve icon path
    NSString *icon = json[@"icon"];
    if (icon) {
        if ([icon hasPrefix:@"/"]) {
            app.iconPath = icon;
        } else {
            // Try common icon locations
            NSArray *iconDirs = @[
                [basePath stringByAppendingPathComponent:@"share/icons"],
                [basePath stringByAppendingPathComponent:@"icons"],
                basePath
            ];
            for (NSString *iconDir in iconDirs) {
                NSString *iconPath = [iconDir stringByAppendingPathComponent:icon];
                if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
                    app.iconPath = iconPath;
                    break;
                }
            }
        }
    }
    
    // Check blacklist
    NSString *execName = [app.executablePath lastPathComponent] ?: @"";
    app.isBlacklisted = isAppBlacklisted(app.appId, execName);
    
    // Verify executable exists
    if (!app.executablePath || 
        ![[NSFileManager defaultManager] isExecutableFileAtPath:app.executablePath]) {
        NSLog(@"⚠️ App %@ has no valid executable at %@", app.name, app.executablePath);
        return nil;
    }
    
    return app;
}

- (WaylandApp *)parseDesktopFile:(NSString *)path basePath:(NSString *)basePath {
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) return nil;
    
    WaylandApp *app = [[WaylandApp alloc] init];
    
    NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"Name="]) {
            app.name = [line substringFromIndex:5];
        } else if ([line hasPrefix:@"Exec="]) {
            NSString *exec = [line substringFromIndex:5];
            // Remove field codes
            exec = [exec stringByReplacingOccurrencesOfString:@"%f" withString:@""];
            exec = [exec stringByReplacingOccurrencesOfString:@"%F" withString:@""];
            exec = [exec stringByReplacingOccurrencesOfString:@"%u" withString:@""];
            exec = [exec stringByReplacingOccurrencesOfString:@"%U" withString:@""];
            exec = [exec stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            
            if (![exec hasPrefix:@"/"]) {
                exec = [[basePath stringByAppendingPathComponent:@"bin"] 
                        stringByAppendingPathComponent:exec];
            }
            app.executablePath = exec;
        } else if ([line hasPrefix:@"Icon="]) {
            app.iconPath = [line substringFromIndex:5];
        } else if ([line hasPrefix:@"Comment="]) {
            app.appDescription = [line substringFromIndex:8];
        } else if ([line hasPrefix:@"Categories="]) {
            app.categories = [[line substringFromIndex:11] componentsSeparatedByString:@";"];
        }
    }
    
    if (!app.name) app.name = [basePath lastPathComponent];
    app.appId = [NSString stringWithFormat:@"desktop.%@", 
                 [[app.name lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"-"]];
    
    NSString *execName = [app.executablePath lastPathComponent] ?: @"";
    app.isBlacklisted = isAppBlacklisted(app.appId, execName);
    
    return app;
}

- (NSArray<WaylandApp *> *)availableApplications {
    return [self.availableApps copy];
}

- (BOOL)launchApplication:(NSString *)appId {
    for (WaylandApp *app in self.availableApps) {
        if ([app.appId isEqualToString:appId]) {
            return [self launchApplicationAtPath:app.executablePath];
        }
    }
    NSLog(@"⚠️ Application not found: %@", appId);
    return NO;
}

- (BOOL)launchApplicationAtPath:(NSString *)appPath {
    if (!appPath || ![[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
        NSLog(@"❌ Application not found: %@", appPath);
        return NO;
    }
    
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Use dlopen to load as dynamic library (App Store compliant)
    NSLog(@"🚀 Loading application as dynamic library: %@", appPath);
    
    void *handle = dlopen([appPath UTF8String], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        NSLog(@"❌ Failed to load %@: %s", appPath, dlerror());
        return NO;
    }
    
    // Look for entry point
    typedef int (*EntryFunc)(int, char**);
    EntryFunc entry = (EntryFunc)dlsym(handle, "main");
    if (!entry) {
        entry = (EntryFunc)dlsym(handle, "app_entry");
    }
    if (!entry) {
        entry = (EntryFunc)dlsym(handle, "_main");
    }
    
    if (!entry) {
        NSLog(@"❌ No entry point found in %@", appPath);
        dlclose(handle);
        return NO;
    }
    
    NSString *appName = [appPath lastPathComponent];
    
    // Launch in background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"🎯 Executing %@", appName);
        char *argv[] = { (char*)[appName UTF8String], NULL };
        int result = entry(1, argv);
        NSLog(@"🛑 %@ exited with code %d", appName, result);
    });
    
    // Track as running
    self.runningProcesses[[appPath lastPathComponent]] = @{
        @"path": appPath,
        @"handle": [NSValue valueWithPointer:handle],
        @"startTime": [NSDate date]
    };
    
    return YES;
#else
    // macOS/Android: Fork and exec
    pid_t pid = fork();
    if (pid == 0) {
        // Child process - set up environment
        const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
        const char *wayland_display = getenv("WAYLAND_DISPLAY");
        
        if (!runtime_dir) {
            char buf[256];
            snprintf(buf, sizeof(buf), "/tmp/wawona-%d", getuid());
            setenv("XDG_RUNTIME_DIR", buf, 1);
        }
        if (!wayland_display) {
            setenv("WAYLAND_DISPLAY", "wayland-0", 1);
        }
        
        NSString *appName = [appPath lastPathComponent];
        execl([appPath UTF8String], [appName UTF8String], NULL);
        _exit(1);
    } else if (pid > 0) {
        // Parent process
        NSString *processKey = [NSString stringWithFormat:@"%d", pid];
        self.runningProcesses[processKey] = @{
            @"pid": @(pid),
            @"path": appPath,
            @"startTime": [NSDate date]
        };
        
        NSLog(@"🚀 Launched %@ with PID %d", [appPath lastPathComponent], pid);
        return YES;
    } else {
        NSLog(@"❌ Fork failed for %@", appPath);
        return NO;
    }
#endif
}

- (void)terminateApplication:(NSString *)appId {
    for (NSString *processKey in [self.runningProcesses allKeys]) {
        NSDictionary *info = self.runningProcesses[processKey];
        NSString *path = info[@"path"];
        
        if ([path containsString:appId] || [processKey containsString:appId]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            // iOS: Close dlopen handle
            NSValue *handleValue = info[@"handle"];
            if (handleValue) {
                void *handle = [handleValue pointerValue];
                if (handle) {
                    dlclose(handle);
                }
            }
#else
            // macOS: Send SIGTERM
            NSNumber *pidNum = info[@"pid"];
            if (pidNum) {
                pid_t pid = [pidNum intValue];
                kill(pid, SIGTERM);
            }
#endif
            [self.runningProcesses removeObjectForKey:processKey];
            NSLog(@"🛑 Terminated: %@", appId);
            return;
        }
    }
}

- (BOOL)isApplicationRunning:(NSString *)appId {
    for (NSString *processKey in [self.runningProcesses allKeys]) {
        NSDictionary *info = self.runningProcesses[processKey];
        NSString *path = info[@"path"];
        
        if ([path containsString:appId]) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            // iOS: Check if handle is still valid
            return YES;
#else
            // macOS: Check if process is alive
            NSNumber *pidNum = info[@"pid"];
            if (pidNum) {
                pid_t pid = [pidNum intValue];
                if (kill(pid, 0) == 0) {
                    return YES;
                }
                // Process dead, clean up
                [self.runningProcesses removeObjectForKey:processKey];
            }
#endif
        }
    }
    return NO;
}

- (NSArray<NSDictionary *> *)runningApplications {
    NSMutableArray *running = [NSMutableArray array];
    
    for (NSString *processKey in [self.runningProcesses allKeys]) {
        NSDictionary *info = self.runningProcesses[processKey];
        
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        [running addObject:info];
#else
        NSNumber *pidNum = info[@"pid"];
        if (pidNum) {
            pid_t pid = [pidNum intValue];
            if (kill(pid, 0) == 0) {
                [running addObject:info];
            } else {
                [self.runningProcesses removeObjectForKey:processKey];
            }
        }
#endif
    }
    
    return running;
}

@end
