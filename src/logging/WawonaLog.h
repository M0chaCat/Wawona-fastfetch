/**
 * WawonaLog.h
 * Wawona Unified Logging System (Objective-C Interface)
 *
 * Log format: YYYY-MM-DD HH:MM:SS [MODULE] emoji message
 *
 * Usage:
 *   WLog(@"COMPOSITOR", @"✅ Server started on port %d", port);
 *   WLogWarn(@"RENDERER", @"⚠️ Fallback to software rendering");
 *   WLogError(@"KERNEL", @"❌ Failed to spawn process: %@", err);
 *
 * Module names (standardized):
 *   COMPOSITOR  - Main compositor logic
 *   RENDERER    - Metal/Vulkan/Surface rendering
 *   INPUT       - Input handling (keyboard, mouse, touch)
 *   WINDOW      - Window management
 *   KERNEL      - iOS virtual kernel (process spawning)
 *   WAYPIPE     - Waypipe runner
 *   SSH         - SSH connections
 *   SETTINGS    - Settings/preferences
 *   PROTOCOL    - Wayland protocol handling
 *   XDG         - XDG shell
 *   FULLSCREEN  - Fullscreen shell
 *   MAIN        - Application entry point
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Core logging function for Objective-C.
 * Outputs: YYYY-MM-DD HH:MM:SS [MODULE] message
 */
void WawonaLogImpl(NSString *module, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

// Main logging macro - use this for most logging
#define WLog(module, fmt, ...) WawonaLogImpl(module, fmt, ##__VA_ARGS__)

// Convenience aliases (all use the same format, just semantic hints)
#define WLogInfo(module, fmt, ...)  WawonaLogImpl(module, fmt, ##__VA_ARGS__)
#define WLogWarn(module, fmt, ...)  WawonaLogImpl(module, fmt, ##__VA_ARGS__)
#define WLogError(module, fmt, ...) WawonaLogImpl(module, fmt, ##__VA_ARGS__)
#define WLogDebug(module, fmt, ...) WawonaLogImpl(module, fmt, ##__VA_ARGS__)

NS_ASSUME_NONNULL_END

