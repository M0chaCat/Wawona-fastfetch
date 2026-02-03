//
//  WawonaMacOSPopup.m
//  Wawona
//
//  Created by Wawona Agent.
//

#import "WawonaMacOSPopup.h"
#import "../../logging/WawonaLog.h"
#import "WawonaWindow.h"

@interface WawonaPopupViewController : NSViewController
@end

@implementation WawonaPopupViewController
- (void)loadView {
  WawonaView *v = [[WawonaView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
  v.wantsLayer = YES;
  v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  v.layer.backgroundColor = [NSColor clearColor].CGColor;
  v.layer.contentsGravity = kCAGravityResize;
  self.view = v;
}
@end

@implementation WawonaMacOSPopup {
  WawonaNativeView *_parentView;
  WawonaPopupViewController *_contentViewController;
}

@synthesize contentView = _contentView;
@synthesize parentView = _parentView;
@synthesize onDismiss = _onDismiss;

- (instancetype)initWithParentView:(WawonaNativeView *)parentView {
  self = [super init];
  if (self) {
    _parentView = parentView;
    _popover = [[NSPopover alloc] init];
    _popover.behavior = NSPopoverBehaviorTransient; // Dismiss on click outside
    _popover.delegate = self;
    _popover.hasFullSizeContent = NO;
    _popover.animates = NO; // Avoid layout lag during transition
    _popover.appearance =
        [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];

    _contentViewController = [[WawonaPopupViewController alloc] init];
    _popover.contentViewController = _contentViewController;

    // Expose the view controller's view as our content view for surface
    // attachment
    _contentView = _contentViewController.view;
  }
  return self;
}

- (void)setWindowId:(uint64_t)windowId {
  if ([_contentView isKindOfClass:[WawonaView class]]) {
    [(WawonaView *)_contentView setOverrideWindowId:windowId];
  }
}

- (void)showRelativeToRect:(CGRect)rect
                    ofView:(WawonaNativeView *)view
             preferredEdge:(WawonaPopupEdge)edge {

  NSRectEdge nsEdge =
      NSRectEdgeMinY; // Default to bottom edge of anchor (popup appears below)

  switch (edge) {
  case WawonaPopupEdgeTop:
    nsEdge = NSRectEdgeMaxY;
    break; // Popup above anchor
  case WawonaPopupEdgeBottom:
    nsEdge = NSRectEdgeMinY;
    break; // Popup below anchor
  case WawonaPopupEdgeLeft:
    nsEdge = NSRectEdgeMinX;
    break; // Popup to left
  case WawonaPopupEdgeRight:
    nsEdge = NSRectEdgeMaxX;
    break; // Popup to right
  default:
    nsEdge = NSRectEdgeMinY;
    break;
  }

  // In Wayland top-left coords, Y is down.
  // In AppKit bottom-left coords, Y is up.
  // However, NSPopover showRelativeToRect takes a rect in the view's coordinate
  // system. If the view is flipped (isFlipped = YES), then we match Wayland
  // mostly.

  WLog(@"POPUP", @"Showing popup relative to rect: %@ preferredEdge: %lu",
       NSStringFromRect(rect), (unsigned long)edge);

  [_popover showRelativeToRect:rect ofView:view preferredEdge:nsEdge];
}

- (void)dismiss {
  if (_popover.shown) {
    [_popover performClose:nil];
  }
}

- (void)setContentSize:(CGSize)size {
  _popover.contentSize = size;
  _contentViewController.preferredContentSize = size;
}

// MARK: - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
  WLog(@"POPUP", @"Popover did close");
  if (self.onDismiss) {
    self.onDismiss();
  }
}

- (void)popoverWillClose:(NSNotification *)notification {
  //
}

- (BOOL)popoverShouldDetach:(NSPopover *)popover {
  return NO; // Don't let user drag it away to become a window
}

@end
