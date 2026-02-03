//
//  WawonaMacOSWindowPopup.m
//  Wawona
//
//  Created by Wawona Agent.
//

#import "WawonaMacOSWindowPopup.h"
#import "../../logging/WawonaLog.h"
#import "WawonaWindow.h"

@implementation WawonaMacOSWindowPopup {
  WawonaNativeView *_parentView;
  CGSize _contentSize;
}

@synthesize contentView = _contentView;
@synthesize parentView = _parentView;
@synthesize onDismiss = _onDismiss;
@synthesize windowId = _windowId;

- (instancetype)initWithParentView:(WawonaNativeView *)parentView {
  self = [super init];
  if (self) {
    _parentView = parentView;
    _contentSize = CGSizeMake(100, 100);

    // Create a borderless window
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                          styleMask:NSWindowStyleMaskBorderless
                                            backing:NSBackingStoreBuffered
                                              defer:NO];

    _window.backgroundColor = [NSColor clearColor];
    _window.hasShadow = YES;
    _window.opaque = NO;
    _window.level = NSStatusWindowLevel; // Stay on top
    _window.releasedWhenClosed = NO;

    // Setup contentView (WawonaView)
    WawonaView *v =
        [[WawonaView alloc] initWithFrame:_window.contentView.bounds];
    v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _window.contentView = v;
    _contentView = v;
  }
  return self;
}

- (void)setWindowId:(uint64_t)windowId {
  _windowId = windowId;
  if ([_contentView isKindOfClass:[WawonaView class]]) {
    [(WawonaView *)_contentView setOverrideWindowId:windowId];
  }
}

- (void)setContentSize:(CGSize)size {
  _contentSize = size;
  [_window setContentSize:size];
}

- (void)showRelativeToRect:(CGRect)rect
                    ofView:(WawonaNativeView *)view
             preferredEdge:(WawonaPopupEdge)edge {

  // 1. Convert anchor point to screen coordinates
  if (!view.window) {
    WLog(@"POPUP-WIN", @"Error: parent view for popup %llu has NO window yet!",
         _windowId);
  }

  NSRect windowRect = [view convertRect:rect toView:nil];
  NSRect screenRect = [view.window convertRectToScreen:windowRect];

  WLog(@"POPUP-WIN", @"Popup %llu coord: rect=%@, screenRect=%@", _windowId,
       NSStringFromRect(rect), NSStringFromRect(screenRect));

  // 2. Position the window so its TOP-LEFT is at screenRect.origin
  NSRect frame =
      NSMakeRect(screenRect.origin.x, screenRect.origin.y - _contentSize.height,
                 _contentSize.width, _contentSize.height);

  WLog(@"POPUP-WIN", @"Showing submenu %llu at screen %@", _windowId,
       NSStringFromRect(frame));

  [_window setFrame:frame display:YES];

  // Use orderFront instead of makeKeyAndOrderFront to avoid dismissing
  // the parent NSPopover (which closes if focus shifts).
  [_window orderFront:nil];

  if (view.window) {
    [view.window addChildWindow:_window ordered:NSWindowAbove];
    WLog(@"POPUP-WIN", @"Added submenu %llu as child to parent window %p",
         _windowId, view.window);
  }
}

- (void)dismiss {
  [_window orderOut:nil];
  if (self.onDismiss) {
    self.onDismiss();
  }
}

@end
