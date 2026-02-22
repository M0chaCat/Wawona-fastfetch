//  WWNRustBridge.h
//  Objective-C bridge to Rust compositor via UniFFI
//
//  This header provides Objective-C-compatible interface to the Rust backend

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Import the generated UniFFI Swift module
// This will be available after build includes the UniFFI generated files
#if __has_include("_GEN-wawona-Swift.h")
#import "_GEN-wawona-Swift.h"
#else
// Forward declarations for development
// These will be replaced by actual UniFFI generated types
@class WWNCore;
@class WindowEvent;
@class WindowId;
@interface WWNCore : NSObject
- (instancetype)init;
- (void)start;
- (void)processEvents;
- (NSArray<WindowEvent *> *)pollWindowEvents;
@end
#endif

NS_ASSUME_NONNULL_END
