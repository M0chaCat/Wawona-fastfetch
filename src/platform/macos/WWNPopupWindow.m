//
//  WWNPopupWindow.m
//  WWN
//

#import "WWNPopupWindow.h"
#import "../../util/WWNLog.h"
#import "WWNWindow.h"

@implementation WWNPopupWindow {
  WWNNativeView *_parentView;
  __weak NSWindow *_parentWindow;
  CGSize _contentSize;
}

@synthesize contentView = _contentView;
@synthesize parentView = _parentView;
@synthesize onDismiss = _onDismiss;
@synthesize windowId = _windowId;

- (instancetype)initWithParentView:(WWNNativeView *)parentView {
  self = [super init];
  if (self) {
    _parentView = parentView;
    _contentSize = CGSizeMake(100, 100);

    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                          styleMask:NSWindowStyleMaskBorderless
                                            backing:NSBackingStoreBuffered
                                              defer:NO];

    _window.backgroundColor = [NSColor clearColor];
    _window.hasShadow = YES;
    _window.opaque = NO;
    _window.level = NSFloatingWindowLevel;
    _window.releasedWhenClosed = NO;

    WWNView *v = [[WWNView alloc] initWithFrame:_window.contentView.bounds];
    v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _window.contentView = v;
    _contentView = v;
  }
  return self;
}

- (void)setWindowId:(uint64_t)windowId {
  _windowId = windowId;
  if ([_contentView isKindOfClass:[WWNView class]]) {
    [(WWNView *)_contentView setOverrideWindowId:windowId];
  }
}

- (void)setContentSize:(CGSize)size {
  _contentSize = size;
  [_window setContentSize:size];
}

- (void)showAtScreenPoint:(CGPoint)point {
  NSRect frame =
      NSMakeRect(point.x, point.y, _contentSize.width, _contentSize.height);
  [_window setFrame:frame display:YES];
  [_window orderFront:nil];
  if (_parentView.window) {
    _parentWindow = _parentView.window;
    [_parentView.window addChildWindow:_window ordered:NSWindowAbove];
    WWNLog("POPUP-WIN", @"Added popup %llu as child to parent window %p",
           _windowId, _parentView.window);
  }
}

- (void)dismiss {
  if (_parentWindow) {
    [_parentWindow removeChildWindow:_window];
    _parentWindow = nil;
  }
  [_window orderOut:nil];
  if (self.onDismiss) {
    self.onDismiss();
  }
}

@end
