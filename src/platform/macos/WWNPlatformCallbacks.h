//  WWNPlatformCallbacks.h
//  Platform callbacks that Rust compositor calls for native operations

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// Platform callbacks interface for Rust → macOS/iOS communication
@protocol WWNPlatformCallbacksProtocol <NSObject>

// Window management
- (void)createNativeWindowWithId:(uint64_t)windowId
                           width:(int32_t)width
                          height:(int32_t)height
                           title:(NSString *_Nullable)title
                          useSSD:(BOOL)useSSD;

- (void)destroyNativeWindowWithId:(uint64_t)windowId;
- (void)setWindowTitle:(NSString *)title forWindowId:(uint64_t)windowId;
- (void)setWindowSize:(CGSize)size forWindowId:(uint64_t)windowId;

// Rendering
- (void)requestRenderForWindowId:(uint64_t)windowId;

@end

/// Implementation of platform callbacks
@interface WWNPlatformCallbacks : NSObject <WWNPlatformCallbacksProtocol>

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, NSWindow *> *windowRegistry;
#else
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, UIWindow *> *windowRegistry;
#endif

+ (instancetype)sharedCallbacks;

@end

NS_ASSUME_NONNULL_END
