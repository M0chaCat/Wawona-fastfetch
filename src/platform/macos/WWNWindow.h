#pragma once

#import <Cocoa/Cocoa.h>

@interface WWNWindow : NSWindow <NSWindowDelegate>
@property(nonatomic, assign) uint64_t wwnWindowId;
@property(nonatomic, assign) BOOL processingResize;
@end

@interface WWNView : NSView <NSTextInputClient>
@property(nonatomic, assign) uint64_t overrideWindowId;
@property(nonatomic, strong, readonly) CALayer *contentLayer;
@end
