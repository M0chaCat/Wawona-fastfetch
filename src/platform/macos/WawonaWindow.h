#pragma once

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <Cocoa/Cocoa.h>

@interface WawonaWindow : NSWindow <NSWindowDelegate>
@property(nonatomic, assign) uint64_t wawonaWindowId;
@property(nonatomic, assign) BOOL processingResize;
@end

@interface WawonaView : NSView
@property(nonatomic, assign) uint64_t overrideWindowId;
@property(nonatomic, strong, readonly) CALayer *contentLayer;
@end
#endif
