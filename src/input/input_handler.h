#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#include "wayland_seat.h"

struct wl_surface_impl;

// Input Handler - Converts NSEvent/UIEvent to Wayland events
@interface InputHandler : NSObject

@property(nonatomic, assign) struct wl_seat_impl *seat;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak)
    UIView *targetView; // Optional: View to convert coordinates relative to
                        // (e.g. safe area view)
@property(nonatomic, weak)
    id compositor; // Reference to MacOSCompositor to trigger redraws

- (instancetype)initWithSeat:(struct wl_seat_impl *)seat
                      window:(UIWindow *)window
                  compositor:(id)compositor;
- (void)handleTouchEvent:(UIEvent *)event;
- (void)setupInputHandling;
#else
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, weak)
    id compositor; // Reference to MacOSCompositor to trigger redraws

- (instancetype)initWithSeat:(struct wl_seat_impl *)seat
                      window:(NSWindow *)window
                  compositor:(id)compositor;
- (void)handleMouseEvent:(NSEvent *)event;
- (void)handleKeyboardEvent:(NSEvent *)event;
- (void)setupInputHandling;
- (struct wl_surface_impl *)pickSurfaceAt:(CGPoint)location;
#endif

@end
