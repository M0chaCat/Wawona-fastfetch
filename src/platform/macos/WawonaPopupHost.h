//
//  WawonaPopupHost.h
//  Wawona
//
//  Created by Wawona Agent.
//

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
typedef UIView WawonaNativeView;
#else
#import <Cocoa/Cocoa.h>
typedef NSView WawonaNativeView;
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WawonaPopupEdge) {
  WawonaPopupEdgeAuto = 0,
  WawonaPopupEdgeTop = 1,
  WawonaPopupEdgeBottom = 2,
  WawonaPopupEdgeLeft = 3,
  WawonaPopupEdgeRight = 4
};

@protocol WawonaPopupHost <NSObject>

@required
// The generic content view that will host the Wayland surface
@property(nonatomic, readonly) WawonaNativeView *contentView;

// The parent view this popup is anchored to
@property(nonatomic, readonly) WawonaNativeView *parentView;

// Initialize with a parent view (the anchor view)
- (instancetype)initWithParentView:(WawonaNativeView *)parentView;

// Show the popup relative to a specific rect in the parent view
- (void)showRelativeToRect:(CGRect)rect
                    ofView:(WawonaNativeView *)view
             preferredEdge:(WawonaPopupEdge)edge;

// Dismiss the popup
- (void)dismiss;

// Update content size (Wayland configure event)
- (void)setContentSize:(CGSize)size;

// Set the window ID for content mapping
@property(nonatomic, assign) uint64_t windowId;

// Callback for when the popup is dismissed by user (e.g. click outside)
@property(nonatomic, copy, nullable) void (^onDismiss)(void);

@end

NS_ASSUME_NONNULL_END
