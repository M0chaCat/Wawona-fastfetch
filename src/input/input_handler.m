#import "input_handler.h"
#include "../compositor_implementations/xdg_shell.h"
#import "../input/wayland_seat.h"
#import "../logging/WawonaLog.h"
#import "../platform/macos/WawonaCompositor.h" // For wl_get_all_surfaces and wl_surface_impl
#import "../platform/macos/WawonaSurfaceManager.h"
#include <stdint.h>
#include <time.h>
#include <wayland-server-protocol.h>
#include <wayland-server.h>
#include <wayland-util.h>

// Helper to check if a surface is part of a surface tree rooted at root
static bool surface_is_in_tree(struct wl_surface_impl *surface,
                               struct wl_surface_impl *root) {
  if (!surface || !root)
    return false;
  if (surface == root)
    return true;

  // Check subsurfaces (not implemented in this simplified check, assuming
  // single surface for now or explicit parent links) Real implementation would
  // need to check wl_subsurface roles. For now, let's assume if we are in the
  // window, we are targeting the main surface.
  // TODO: Implement proper subsurface hit testing
  return false;
}

// Key code mapping: macOS key codes to Linux keycodes
// Reference: /usr/include/linux/input-event-codes.h
// Linux keycodes: Q=16, W=17, E=18, R=19, T=20, Y=21, U=22, I=23, O=24, P=25
//                  A=30, S=31, D=32, F=33, G=34, H=35, J=36, K=37, L=38
//                  Z=44, X=45, C=46, V=47, B=48, N=49, M=50

@interface InputHandler ()
@property(nonatomic, assign) struct wl_surface_impl *lastPointerSurface;
@property(nonatomic, assign) struct wl_surface_impl *lastKeyboardSurface;
@end

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static uint32_t macKeyCodeToLinuxKeyCode(unsigned short macKeyCode) {
  // Basic mapping - can be expanded
  switch (macKeyCode) {
  case 0x00:
    return 30; // A
  case 0x01:
    return 31; // S
  case 0x02:
    return 32; // D
  case 0x03:
    return 33; // F
  case 0x04:
    return 35; // H
  case 0x05:
    return 34; // G
  case 0x06:
    return 44; // Z
  case 0x07:
    return 45; // X
  case 0x08:
    return 46; // C
  case 0x09:
    return 47; // V
  case 0x0A:
    return 49; // N
  case 0x0B:
    return 48; // B
  case 0x0C:
    return 16; // Q
  case 0x0D:
    return 17; // W
  case 0x0E:
    return 18; // E
  case 0x0F:
    return 19; // R
  case 0x10:
    return 21; // Y
  case 0x11:
    return 20; // T
  case 0x12:
    return 2; // 1 (Linux KEY_1 = 2)
  case 0x13:
    return 3; // 2 (Linux KEY_2 = 3)
  case 0x14:
    return 4; // 3 (Linux KEY_3 = 4)
  case 0x15:
    return 5; // 4 (Linux KEY_4 = 5)
  case 0x16:
    return 6; // 5 (Linux KEY_5 = 6)
  case 0x17:
    return 7; // 6 (Linux KEY_6 = 7)
  case 0x18:
    return 8; // 7 (Linux KEY_7 = 8)
  case 0x19:
    return 9; // 8 (Linux KEY_8 = 9)
  case 0x1A:
    return 10; // 9 (Linux KEY_9 = 10)
  case 0x1B:
    return 11; // 0 (Linux KEY_0 = 11)
  case 0x1C:
    return 12; // - (Linux KEY_MINUS = 12)
  case 0x1D:
    return 13; // = (Linux KEY_EQUAL = 13)
  case 0x1E:
    return 27; // ] (Linux KEY_RIGHTBRACE = 27)
  case 0x1F:
    return 24; // O (macOS kVK_ANSI_O = 0x1F)
  case 0x20:
    return 22; // U (macOS kVK_ANSI_U = 0x20)
  case 0x21:
    return 26; // [ (Linux KEY_LEFTBRACE = 26)
  case 0x22:
    return 23; // I (macOS kVK_ANSI_I = 0x22)
  case 0x23:
    return 25; // P (macOS kVK_ANSI_P = 0x23)
  case 0x24:
    return 28; // Return/Enter (macOS kVK_Return = 0x24)
  case 0x25:
    return 38; // L (macOS kVK_ANSI_L = 0x25)
  case 0x26:
    return 36; // J (macOS kVK_ANSI_J = 0x26)
  case 0x27:
    return 41; // ` (KEY_GRAVE, macOS kVK_ANSI_Grave = 0x27)
  case 0x28:
    return 37; // K (macOS kVK_ANSI_K = 0x28)
  case 0x29:
    return 51; // ; (Linux KEY_SEMICOLON = 51)
  case 0x2A:
    return 43; // \ (Linux KEY_BACKSLASH = 43)
  case 0x2B:
    return 51; // Comma (KEY_COMMA = 51)
  case 0x2C:
    return 53; // Slash (KEY_SLASH = 53)
  case 0x2D:
    return 49; // N (macOS kVK_ANSI_N = 0x2D)
  case 0x2E:
    return 50; // M (macOS kVK_ANSI_M = 0x2E)
  case 0x2F:
    return 52; // Period (KEY_DOT = 52)
  case 0x30:
    return 57; // Space (KEY_SPACE) - alternate
  case 0x31:
    return 57; // Space (KEY_SPACE) - primary
  case 0x32:
    return 105; // Left (KEY_LEFT)
  case 0x34:
    return 103; // Up (KEY_UP)
  case 0x33:
    return 14; // Backspace (macOS kVK_Delete = 0x33)
  case 0x35:
    return 1; // Escape (KEY_ESC)
  case 0x37:
    return 125; // Left Command/Super (KEY_LEFTMETA)
  case 0x38:
    return 56; // Left Shift (KEY_LEFTSHIFT)
  case 0x39:
    return 58; // Caps Lock (KEY_CAPSLOCK)
  case 0x3A:
    return 29; // Left Alt (KEY_LEFTALT)
  case 0x3B:
    return 42; // Left Control (KEY_LEFTCTRL)
  case 0x3C:
    return 54; // Right Shift (KEY_RIGHTSHIFT)
  case 0x3D:
    return 100; // Right Alt (KEY_RIGHTALT)
  case 0x3E:
    return 97; // Right Control (KEY_RIGHTCTRL)
  case 0x3F:
    return 126; // Right Command/Super (KEY_RIGHTMETA)

  case 0x7A:
    return 59; // F1
  case 0x78:
    return 60; // F2
  case 0x63:
    return 61; // F3
  case 0x76:
    return 62; // F4
  case 0x60:
    return 63; // F5
  case 0x61:
    return 64; // F6
  case 0x62:
    return 65; // F7
  case 0x64:
    return 66; // F8
  case 0x65:
    return 67; // F9
  case 0x6D:
    return 68; // F10
  case 0x67:
    return 87; // F11
  case 0x6F:
    return 88; // F12

  case 0x52:
    return 82; // Numpad 0
  case 0x53:
    return 79; // Numpad 1
  case 0x54:
    return 80; // Numpad 2
  case 0x55:
    return 81; // Numpad 3
  case 0x56:
    return 75; // Numpad 4
  case 0x57:
    return 76; // Numpad 5
  case 0x58:
    return 77; // Numpad 6
  case 0x59:
    return 71; // Numpad 7
  case 0x5B:
    return 72; // Numpad 8
  case 0x5C:
    return 73; // Numpad 9
  case 0x41:
    return 98; // Numpad Decimal
  case 0x4C:
    return 96; // Numpad Enter
  case 0x51:
    return 104; // Numpad Equals
  case 0x45:
    return 78; // Numpad Plus
  case 0x4E:
    return 74; // Numpad Minus
  case 0x43:
    return 55; // Numpad Multiply
  case 0x4B:
    return 83; // Numpad Divide
  case 0x47:
    return 69; // Num Lock

  case 0x7E:
    return 103; // Up Arrow
  case 0x7D:
    return 108; // Down Arrow
  case 0x7B:
    return 105; // Left Arrow
  case 0x7C:
    return 106; // Right Arrow

  case 0x66:
    return 102; // Help
  case 0x72:
    return 111; // Insert
  case 0x73:
    return 110; // Home
  case 0x74:
    return 115; // Page Up
  case 0x75:
    return 119; // Delete/Forward Delete
  case 0x77:
    return 116; // End
  case 0x79:
    return 109; // Page Down
  case 0x6A:
    return 113; // Clear

  case 0x48:
    return 15; // Tab
  case 0x49:
    return 41; // `/~

  default:
    return 0;
  }
}
#endif

// Mouse button mapping
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static uint32_t macButtonToWaylandButton(NSEventType eventType,
                                         NSEvent *event) {
  (void)event;
  switch (eventType) {
  case NSEventTypeLeftMouseDown:
  case NSEventTypeLeftMouseUp:
    return 272; // BTN_LEFT
  case NSEventTypeRightMouseDown:
  case NSEventTypeRightMouseUp:
    return 273; // BTN_RIGHT
  case NSEventTypeOtherMouseDown:
  case NSEventTypeOtherMouseUp:
    return 274; // BTN_MIDDLE
  default:
    return 0;
  }
}
#endif

@implementation InputHandler

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithSeat:(struct wl_seat_impl *)seat
                      window:(UIWindow *)window
                  compositor:(id)compositor {
#else
- (instancetype)initWithSeat:(struct wl_seat_impl *)seat
                      window:(NSWindow *)window
                  compositor:(id)compositor {
#endif
  self = [super init];
  if (self) {
    _seat = seat;
    _window = window;
    _compositor = compositor;
  }
  return self;
}

static uint32_t getWaylandTime(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)((ts.tv_sec * 1000) + (ts.tv_nsec / 1000000));
}

- (void)setupInputHandling {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (_seat) {
    struct wl_seat_impl *seat_impl = _seat;
    // Enable both TOUCH and POINTER to support desktop apps that only handle
    // mouse
    seat_impl->capabilities =
        WL_SEAT_CAPABILITY_TOUCH | WL_SEAT_CAPABILITY_POINTER;
    WLog(@"INPUT",
         @"iOS input handling configured (Touch + Pointer emulation)");
  }
  // Use direct touch handling in CompositorView instead of gesture recognizers
  // [self setupGestureRecognizers];
#else
  NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
      initWithRect:[_window.contentView bounds]
           options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow |
                    NSTrackingInVisibleRect)
             owner:self
          userInfo:nil];
  [_window.contentView addTrackingArea:trackingArea];
  [_window setAcceptsMouseMovedEvents:YES];
#endif
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)setupGestureRecognizers {
  UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleTapGesture:)];
  [_window addGestureRecognizer:tapGesture];

  UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handlePanGesture:)];
  [_window addGestureRecognizer:panGesture];

  UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handlePinchGesture:)];
  [_window addGestureRecognizer:pinchGesture];

  WLog(@"INPUT", @"iOS gesture recognizers configured");
}

- (void)handleTouchEvent:(UIEvent *)event {
  NSSet<UITouch *> *touches = [event allTouches];
  UIView *view = self.targetView ? self.targetView : _window;

  for (UITouch *touch in touches) {
    CGPoint location = [touch locationInView:view];

    switch (touch.phase) {
    case UITouchPhaseBegan:
      [self sendTouchDown:location touch:touch];
      break;
    case UITouchPhaseMoved:
      [self sendTouchMotion:location touch:touch];
      break;
    case UITouchPhaseEnded:
      [self sendTouchUp:location touch:touch];
      break;
    case UITouchPhaseCancelled:
      [self sendTouchCancel:touch];
      break;
    default:
      break;
    }
  }
}
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// macOS hit-testing helper
#endif

static struct wl_surface_impl *
pick_surface_recursive(struct wl_surface_impl *surface, double px, double py,
                       int32_t absX, int32_t absY) {
  if (!surface)
    return NULL;

  int32_t currentAbsX = absX + surface->x;
  int32_t currentAbsY = absY + surface->y;

  // Search for subsurfaces first (top-most in Wayland Z-order are usually
  // at the end of the list, but Wawona list order might be different).
  // For now, we iterate the global list and find surfaces where parent ==
  // surface.
  struct wl_surface_impl *child = g_wl_surface_list;
  struct wl_surface_impl *bestMatch = NULL;

  while (child) {
    if (child->parent == surface && child->resource) {
      struct wl_surface_impl *match =
          pick_surface_recursive(child, px, py, currentAbsX, currentAbsY);
      if (match) {
        // In Wayland, subsurfaces can be stacked. This simple implementation
        // might need to handle Z-order better. For now, we take the last one
        // found (likely top-most).
        bestMatch = match;
      }
    }
    child = child->next;
  }

  if (bestMatch)
    return bestMatch;

  // Check if point is in this surface
  if (px >= (double)currentAbsX && px < (double)currentAbsX + surface->width &&
      py >= (double)currentAbsY && py < (double)currentAbsY + surface->height) {
    return surface;
  }

  return NULL;
}

- (struct wl_surface_impl *)pickSurfaceAt:(CGPoint)location {
  // Lookup toplevel for this window
  WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
  if (!compositor)
    return NULL;

  if (!_window)
    return NULL;

  struct xdg_toplevel_impl *toplevel = NULL;
  NSValue *toplevelValue = [compositor.windowToToplevelMap
      objectForKey:[NSValue valueWithPointer:(__bridge void *)_window]];
  if (toplevelValue) {
    toplevel = [toplevelValue pointerValue];
  }

  if (!toplevel || !toplevel->xdg_surface ||
      !toplevel->xdg_surface->wl_surface) {
    return NULL;
  }

  struct wl_surface_impl *root_surface = toplevel->xdg_surface->wl_surface;
  if (!root_surface->resource)
    return NULL;

  // Check if we should ignore clicks in the CSD shadow area
  int32_t gx = 0, gy = 0, gw = root_surface->width, gh = root_surface->height;
  if (toplevel && toplevel->decoration_mode == 1 && toplevel->xdg_surface &&
      toplevel->xdg_surface->has_geometry) {
    gx = toplevel->xdg_surface->geometry_x;
    gy = toplevel->xdg_surface->geometry_y;
    gw = toplevel->xdg_surface->geometry_width;
    gh = toplevel->xdg_surface->geometry_height;
  }

  // Location is in points (logical macOS units).
  // Wayland coordinates should be in logical units (points) to match macOS
  // scaling.
  double px = (double)location.x;
  double py = (double)location.y;

  // CRITICAL: Offset coordinates for CSD shadow margin
  // With separate Shadow Window, the Main Window coordinate space is EXACTLY
  // the surface space. No offsets needed anymore.
  /*
  if (toplevel && toplevel->decoration_mode == 1) {
    CGFloat expansionPerSide = kCSDShadowMargin * 2.0;
    px -= expansionPerSide;
    py -= expansionPerSide;
  }
  */

  // Boundary check against logical window geometry with leeway for resize
  // handles. We allow clicks within 20px of the edge to be captured for CSD
  // resize handles (consistent with WawonaSurfaceManager.m's threshold).
  CGFloat leeway = 20.0;
  if (px < -leeway || px >= (double)gw + leeway || py < -leeway ||
      py >= (double)gh + leeway) {
    // If we are in CSD mode, ignore clicks in the deep shadow area
    if (toplevel->decoration_mode == 1) {
      // Use NSLog for debugging shadow clicks
      WLog(@"INPUT",
           @"Deep shadow area click (passed through)! px=%.1f py=%.1f, "
           @"geometry=(%d,%d %dx%d)",
           px, py, gx, gy, gw, gh);
      return NULL;
    }
  }

  // Find the actual surface (root or subsurface) at this location
  struct wl_surface_impl *result =
      pick_surface_recursive(root_surface, px, py, 0, 0);
  if (result) {
    WLog(@"INPUT", @"Picked surface %p at (%.1f, %.1f)", (void *)result, px,
         py);
  }
  return result;
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)sendTouchDown:(CGPoint)location touch:(UITouch *)touch {
  if (_seat) {
    struct wl_seat_impl *seat_impl = _seat;
    struct wl_surface_impl *surface = [self pickSurfaceAt:location];

    if (!surface || !surface->resource) {
      // No surface found - can't send event
      WLog(@"INPUT",
           @"Warning: No surface found at touch location (%.1f, %.1f)",
           location.x, location.y);
      return;
    }

    // Convert view points to surface-local coordinates (pixels)
    // Location is already relative to targetView (CompositorView's metalView)
    // We need to convert from points to pixels using the screen scale
    UIView *targetView = self.targetView ? self.targetView : _window;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    CGFloat scale = targetView.window.screen.scale;
    if (scale <= 0) {
      scale = [UIScreen mainScreen].scale; // Fallback
    }
#else
    CGFloat scale = _window.backingScaleFactor;
#endif

    // Location is in points relative to targetView
    // Convert to pixels for Wayland (which uses pixel coordinates)
    wl_fixed_t x = wl_fixed_from_double(location.x * scale);
    wl_fixed_t y = wl_fixed_from_double(location.y * scale);

    WLog(@"INPUT",
         @"Touch down: view coords (%.1f, %.1f) points, scale %.0fx = Wayland "
         @"(%.1f, %.1f) pixels",
         location.x, location.y, scale, wl_fixed_to_double(x),
         wl_fixed_to_double(y));

    // Dispatch touch down to event thread
    struct wl_surface_impl *target_surface = surface;
    struct wl_seat_impl *seat_impl_copy = seat_impl;
    int32_t touch_id = (int32_t)(intptr_t)touch;
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;

    [compositor dispatchToEventThread:^{
      wl_seat_send_touch_down(seat_impl_copy,
                              wl_seat_get_serial(seat_impl_copy),
                              getWaylandTime(),         // timestamp
                              target_surface->resource, // Valid surface!
                              touch_id, x, y);
      wl_seat_send_touch_frame(seat_impl_copy); // REQUIRED: Group events

      // Also send pointer events for desktop apps compatibility (emulate mouse
      // click)
      wl_seat_send_pointer_enter(seat_impl_copy, target_surface->resource,
                                 wl_seat_get_serial(seat_impl_copy), x, y);
      wl_seat_send_pointer_frame(seat_impl_copy);

      // Send explicit motion to ensure client updates cursor position before
      // click
      wl_seat_send_pointer_motion(seat_impl_copy, getWaylandTime(), x, y);
      wl_seat_send_pointer_frame(seat_impl_copy);

      wl_seat_send_pointer_button(seat_impl_copy,
                                  wl_seat_get_serial(seat_impl_copy),
                                  getWaylandTime(), 272, 1); // BTN_LEFT down
      wl_seat_send_pointer_frame(seat_impl_copy);
    }];

    WLog(@"INPUT", @"Touch down at (%.1f, %.1f) on surface %p", location.x,
         location.y, (void *)surface);
  }
}

- (void)sendTouchMotion:(CGPoint)location touch:(UITouch *)touch {
  if (_seat) {
    struct wl_seat_impl *seat_impl = _seat;

    // Convert to pixels (location is already relative to targetView)
    UIView *targetView = self.targetView ? self.targetView : _window;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    CGFloat scale = targetView.window.screen.scale;
    if (scale <= 0) {
      scale = [UIScreen mainScreen].scale; // Fallback
    }
#else
    CGFloat scale = _window.backingScaleFactor;
#endif
    wl_fixed_t x = wl_fixed_from_double(location.x * scale);
    wl_fixed_t y = wl_fixed_from_double(location.y * scale);

    // Dispatch touch motion to event thread
    struct wl_seat_impl *seat_impl_copy = seat_impl;
    int32_t touch_id = (int32_t)(intptr_t)touch;
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;

    [compositor dispatchToEventThread:^{
      wl_seat_send_touch_motion(seat_impl_copy,
                                getWaylandTime(), // timestamp
                                touch_id, x, y);
      wl_seat_send_touch_frame(seat_impl_copy); // REQUIRED

      // Send pointer motion
      wl_seat_send_pointer_motion(seat_impl_copy, getWaylandTime(), x, y);
      wl_seat_send_pointer_frame(seat_impl_copy);
    }];

    // Reduce log spam for motion
    // NSLog(@"📱 Touch motion at (%.1f, %.1f)", location.x, location.y);
  }
}

- (void)sendTouchUp:(CGPoint)location touch:(UITouch *)touch {
  if (_seat) {
    struct wl_seat_impl *seat_impl = _seat;
    // Dispatch touch up to event thread
    struct wl_seat_impl *seat_impl_copy = seat_impl;
    int32_t touch_id = (int32_t)(intptr_t)touch;
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;

    [compositor dispatchToEventThread:^{
      wl_seat_send_touch_up(seat_impl_copy, wl_seat_get_serial(seat_impl_copy),
                            getWaylandTime(), // timestamp
                            touch_id);
      wl_seat_send_touch_frame(seat_impl_copy); // REQUIRED

      // Send pointer button up
      wl_seat_send_pointer_button(seat_impl_copy,
                                  wl_seat_get_serial(seat_impl_copy),
                                  getWaylandTime(), 272, 0); // BTN_LEFT up
      wl_seat_send_pointer_frame(seat_impl_copy);
    }];

    WLog(@"INPUT", @"Touch up at (%.1f, %.1f)", location.x, location.y);
  }
}

- (void)sendTouchCancel:(UITouch *)touch {
  if (_seat) {
    struct wl_seat_impl *seat_impl = _seat;
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;

    // Dispatch touch cancel to event thread
    [compositor dispatchToEventThread:^{
      wl_seat_send_touch_cancel(seat_impl);
      wl_seat_send_touch_frame(seat_impl); // REQUIRED
    }];

    WLog(@"INPUT", @"Touch cancelled");
  }
}

- (void)handleTapGesture:(UITapGestureRecognizer *)gesture {
  UIView *view = self.targetView ? self.targetView : _window;
  CGPoint location = [gesture locationInView:view];
  WLog(@"INPUT", @"Tap gesture at (%.1f, %.1f)", location.x, location.y);
  if (_seat) {
    UITouch *syntheticTouch = (__bridge UITouch *)((void *)gesture.hash);
    [self sendTouchDown:location touch:syntheticTouch];
    [self sendTouchUp:location touch:syntheticTouch];
  }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
  if (_seat && gesture.state == UIGestureRecognizerStateChanged) {
    UIView *view = self.targetView ? self.targetView : _window;
    CGPoint location = [gesture locationInView:view];
    [self sendTouchMotion:location touch:nil];
  }
}

- (void)handlePinchGesture:(UIPinchGestureRecognizer *)gesture {
  // TODO: Implement pinch axis events
  WLog(@"INPUT", @"Pinch gesture: scale %.2f", gesture.scale);
}
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (void)handleMouseEvent:(NSEvent *)event {
  NSEventType type = [event type];
  if (type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown ||
      type == NSEventTypeOtherMouseDown) {
    self.lastMouseDownEvent = event;
  }

  WLog(@"INPUT",
       @"handleMouseEvent called: type=%lu, locationInWindow=(%.1f, %.1f)",
       (unsigned long)[event type], [event locationInWindow].x,
       [event locationInWindow].y);

  if (!_seat) {
    WLog(@"INPUT", @"Warning: No seat available for mouse event");
    return;
  }

  if (!_seat->pointer_resource) {
    // Log warning but don't return - the send functions will safely handle NULL
    // pointer_resource This allows us to see if events are being generated even
    // if pointer isn't requested yet
    static BOOL logged_warning = NO;
    if (!logged_warning) {
      WLog(@"INPUT", @"Warning: No pointer resource available (client hasn't "
                     @"requested pointer yet)");
      WLog(@"INPUT",
           @"Seat capabilities: 0x%x (KEYBOARD=0x%x, POINTER=0x%x, TOUCH=0x%x)",
           _seat->capabilities, WL_SEAT_CAPABILITY_KEYBOARD,
           WL_SEAT_CAPABILITY_POINTER, WL_SEAT_CAPABILITY_TOUCH);
      WLog(@"INPUT", @"Mouse events will be sent but may be ignored until "
                     @"client requests pointer");
      logged_warning = YES;
    }
    // Continue - the send functions check for pointer_resource internally
  }

  NSPoint locationInWindow = [event locationInWindow];
  NSPoint locationInView =
      [_window.contentView convertPoint:locationInWindow fromView:nil];

  // Use logical coordinates (points). Wayland clients expect logical units.
  // If we send pixels on HiDPI, clients will see double coordinates.
  double window_x = locationInView.x;
  double window_y = locationInView.y;

  // CRITICAL: Offset coordinates for CSD shadow margin
  // With separate Shadow Window, the Main Window coordinate space is EXACTLY
  // the surface space. No offsets needed anymore.
  /*
  if (toplevel && toplevel->decoration_mode == 1) {
    CGFloat expansionPerSide = kCSDShadowMargin * 2.0;
    window_x -= expansionPerSide;
    window_y -= expansionPerSide;
  }
  */

  NSEventType eventType = [event type];
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  uint32_t time = (uint32_t)((ts.tv_sec * 1000) + (ts.tv_nsec / 1000000));

  // Find the surface under the cursor
  struct wl_surface_impl *surface = [self pickSurfaceAt:locationInView];

  if (!surface || !surface->resource) {
    WLog(
        @"INPUT",
        @"Warning: No surface found at (%.1f, %.1f) - cannot send mouse events",
        locationInView.x, locationInView.y);
    return;
  }

  WLog(@"INPUT",
       @"Found surface %p at window (%.1f, %.1f), surface pos=(%d, %d), "
       @"size=(%d, %d)",
       (void *)surface, locationInView.x, locationInView.y, surface->x,
       surface->y, surface->width, surface->height);

  // CRITICAL: Convert window coordinates to surface-local coordinates.
  // Wayland protocol requires motion/enter events to use surface-local
  // coordinates (buffer-relative).
  double surface_x = window_x;
  double surface_y = window_y;

  if (surface->parent == NULL) {
    // Root surface: window-local (0,0) is geometry (0,0).
    // Add geometry offset to get buffer-local coordinates for the client.
    struct xdg_toplevel_impl *toplevel =
        xdg_surface_get_toplevel_from_wl_surface(surface);
    if (toplevel && toplevel->xdg_surface &&
        toplevel->xdg_surface->has_geometry) {
      surface_x += toplevel->xdg_surface->geometry_x;
      surface_y += toplevel->xdg_surface->geometry_y;
    }
  } else {
    // Subsurface: Position is relative to parent buffer origin.
    // SurfaceRenderer positions it relative to parent geometry as (surface->x -
    // pgx). We subtract this layer offset from the window-local coordinate to
    // get subsurface-local coordinates.
    int32_t pgx = 0, pgy = 0;
    struct xdg_toplevel_impl *parentToplevel =
        xdg_surface_get_toplevel_from_wl_surface(surface->parent);
    if (parentToplevel && parentToplevel->xdg_surface &&
        parentToplevel->xdg_surface->has_geometry) {
      pgx = parentToplevel->xdg_surface->geometry_x;
      pgy = parentToplevel->xdg_surface->geometry_y;
    }
    surface_x -= (surface->x - pgx);
    surface_y -= (surface->y - pgy);
  }

  // Ensure coordinates are non-negative (clamp to surface bounds)
  if (surface_x < 0)
    surface_x = 0;
  if (surface_y < 0)
    surface_y = 0;
  if (surface->width > 0 && surface_x > surface->width)
    surface_x = surface->width;
  if (surface->height > 0 && surface_y > surface->height)
    surface_y = surface->height;

  // Handle pointer enter/leave
  // Handle pointer enter/leave
  struct wl_surface_impl *current_surface = surface;

  // Send initial enter event if pointer hasn't entered any surface yet
  if (!self.lastPointerSurface && current_surface &&
      current_surface->resource && _seat->pointer_resource) {
    uint32_t serial = wl_seat_get_serial(_seat);
    struct wl_surface_impl *target_surface = current_surface;
    struct wl_seat_impl *seat_impl = _seat;

    // Dispatch pointer enter to event thread
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
    [compositor dispatchToEventThread:^{
      wl_seat_send_pointer_enter(seat_impl, target_surface->resource, serial,
                                 surface_x, surface_y);
      wl_seat_send_pointer_frame(seat_impl);
    }];

    WLog(@"INPUT",
         @"Pointer entered surface %p at surface-local (%.1f, %.1f) [window: "
         @"(%.1f, %.1f), surface pos: (%d, %d)]",
         (void *)current_surface, surface_x, surface_y, window_x, window_y,
         current_surface->x, current_surface->y);
    self.lastPointerSurface = current_surface;

    // Flush enter event immediately
    if (_compositor && [_compositor respondsToSelector:@selector
                                    (sendFrameCallbacksImmediately)]) {
      [_compositor sendFrameCallbacksImmediately];
    }
  } else if (current_surface != self.lastPointerSurface) {
    // Leave old surface
    if (self.lastPointerSurface && self.lastPointerSurface->resource &&
        _seat->pointer_resource) {
      uint32_t serial = wl_seat_get_serial(_seat);
      struct wl_surface_impl *old_surface = self.lastPointerSurface;
      struct wl_seat_impl *seat_impl = _seat;

      // Dispatch pointer leave to event thread
      WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
      [compositor dispatchToEventThread:^{
        wl_seat_send_pointer_leave(seat_impl, old_surface->resource, serial);
        wl_seat_send_pointer_frame(seat_impl);
      }];

      WLog(@"INPUT", @"Pointer left surface %p",
           (void *)self.lastPointerSurface);
    }
    // Enter new surface
    if (current_surface && current_surface->resource &&
        _seat->pointer_resource) {
      uint32_t serial = wl_seat_get_serial(_seat);
      struct wl_surface_impl *new_surface = current_surface;
      struct wl_seat_impl *seat_impl = _seat;

      // Dispatch pointer enter to event thread
      WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
      [compositor dispatchToEventThread:^{
        wl_seat_send_pointer_enter(seat_impl, new_surface->resource, serial,
                                   surface_x, surface_y);
        wl_seat_send_pointer_frame(seat_impl);
      }];

      WLog(@"INPUT",
           @"Pointer entered surface %p at surface-local (%.1f, %.1f) [window: "
           @"(%.1f, %.1f)]",
           (void *)current_surface, surface_x, surface_y, window_x, window_y);
    }
    self.lastPointerSurface = current_surface;

    // Flush enter/leave events immediately so clients receive them right away
    if (_compositor && [_compositor respondsToSelector:@selector
                                    (sendFrameCallbacksImmediately)]) {
      [_compositor sendFrameCallbacksImmediately];
    }
  }

  // Handle keyboard enter/leave when pointer enters/leaves surface
  // Keyboard focus follows pointer on macOS within the active window
  // Note: WawonaCompositor handles window-level focus (activiation).
  // This logic handles sub-surface focus if applicable.

  if (current_surface != self.lastKeyboardSurface) {
    // Leave old surface
    if (self.lastKeyboardSurface && self.lastKeyboardSurface->resource &&
        _seat->keyboard_resource &&
        wl_resource_get_client(_seat->keyboard_resource) &&
        wl_resource_get_client(self.lastKeyboardSurface->resource)) {
      uint32_t serial = wl_seat_get_serial(_seat);
      struct wl_surface_impl *old_keyboard_surface = self.lastKeyboardSurface;
      struct wl_seat_impl *seat_impl = _seat;

      // Dispatch keyboard leave to event thread
      WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
      [compositor dispatchToEventThread:^{
        wl_seat_send_keyboard_leave(seat_impl, old_keyboard_surface->resource,
                                    serial);
      }];

      WLog(@"INPUT", @"Keyboard left surface %p",
           (void *)self.lastKeyboardSurface);
    }
    // Enter new surface
    if (current_surface && current_surface->resource &&
        _seat->keyboard_resource &&
        wl_resource_get_client(_seat->keyboard_resource) &&
        wl_resource_get_client(current_surface->resource)) {
      uint32_t serial = wl_seat_get_serial(_seat);
      struct wl_surface_impl *new_keyboard_surface = current_surface;
      struct wl_seat_impl *seat_impl = _seat;

      // Dispatch keyboard enter to event thread
      WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
      [compositor dispatchToEventThread:^{
        // Create empty keys array for keyboard enter (no pressed keys
        // initially)
        struct wl_array keys;
        wl_array_init(&keys);
        wl_seat_send_keyboard_enter(seat_impl, new_keyboard_surface->resource,
                                    serial, &keys);
        wl_array_release(&keys);
        // Send current modifiers after enter
        wl_seat_send_keyboard_modifiers(seat_impl, serial);
      }];

      WLog(@"INPUT", @"Keyboard entered surface %p", (void *)current_surface);
    }
    self.lastKeyboardSurface = current_surface;
  }

  switch (eventType) {
  case NSEventTypeMouseMoved:
  case NSEventTypeLeftMouseDragged:
  case NSEventTypeRightMouseDragged:
  case NSEventTypeOtherMouseDragged: {
    // Use surface-local coordinates for motion events
    WLog(@"INPUT",
         @"Mouse moved to surface-local (%.1f, %.1f) [window: (%.1f, %.1f)] - "
         @"pointer_resource=%p",
         surface_x, surface_y, window_x, window_y,
         (void *)_seat->pointer_resource);

    // Dispatch pointer motion to event thread
    struct wl_seat_impl *seat_impl = _seat;
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
    [compositor dispatchToEventThread:^{
      wl_seat_send_pointer_motion(seat_impl, time, surface_x, surface_y);
      wl_seat_send_pointer_frame(seat_impl);
    }];

    // Flush mouse events immediately so clients receive them right away
    if (_compositor && [_compositor respondsToSelector:@selector
                                    (sendFrameCallbacksImmediately)]) {
      [_compositor sendFrameCallbacksImmediately];
    }

    [self triggerFrameCallback];
    break;
  }
  case NSEventTypeLeftMouseDown:
  case NSEventTypeRightMouseDown:
  case NSEventTypeOtherMouseDown: {
    uint32_t serial = wl_seat_get_serial(_seat);
    uint32_t button = macButtonToWaylandButton(eventType, event);
    WLog(@"INPUT",
         @"Mouse button down: button=%u at surface-local (%.1f, %.1f) [window: "
         @"(%.1f, %.1f)] - pointer_resource=%p",
         button, surface_x, surface_y, window_x, window_y,
         (void *)_seat->pointer_resource);

    // Dispatch pointer button down to event thread
    struct wl_seat_impl *seat_impl = _seat;
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
    [compositor dispatchToEventThread:^{
      wl_seat_send_pointer_button(seat_impl, serial, time, button,
                                  WL_POINTER_BUTTON_STATE_PRESSED);
      wl_seat_send_pointer_frame(seat_impl);
    }];

    // Flush mouse events immediately so clients receive them right away
    if (_compositor && [_compositor respondsToSelector:@selector
                                    (sendFrameCallbacksImmediately)]) {
      [_compositor sendFrameCallbacksImmediately];
    }

    [self triggerFrameCallback];
    break;
  }
  case NSEventTypeLeftMouseUp:
  case NSEventTypeRightMouseUp:
  case NSEventTypeOtherMouseUp: {
    uint32_t serial = wl_seat_get_serial(_seat);
    uint32_t button = macButtonToWaylandButton(eventType, event);
    WLog(@"INPUT",
         @"Mouse button up: button=%u at surface-local (%.1f, %.1f) [window: "
         @"(%.1f, %.1f)]",
         button, surface_x, surface_y, window_x, window_y);

    // Dispatch pointer button up to event thread
    struct wl_seat_impl *seat_impl = _seat;
    WawonaCompositor *compositor = (WawonaCompositor *)_compositor;
    [compositor dispatchToEventThread:^{
      wl_seat_send_pointer_button(seat_impl, serial, time, button,
                                  WL_POINTER_BUTTON_STATE_RELEASED);
      wl_seat_send_pointer_frame(seat_impl);
    }];

    // Flush mouse events immediately so clients receive them right away
    if (_compositor && [_compositor respondsToSelector:@selector
                                    (sendFrameCallbacksImmediately)]) {
      [_compositor sendFrameCallbacksImmediately];
    }

    [self triggerFrameCallback];
    break;
  }
  case NSEventTypeScrollWheel: {
    double deltaY = [event scrollingDeltaY];
    if (deltaY != 0) {
      // Send scroll event (axis event)
      if (wl_resource_get_version(_seat->pointer_resource) >=
          WL_POINTER_AXIS_SINCE_VERSION) {
        struct wl_seat_impl *seat_impl = _seat;
        double scroll_delta = deltaY;
        WawonaCompositor *compositor = (WawonaCompositor *)_compositor;

        // Dispatch scroll event to event thread
        [compositor dispatchToEventThread:^{
          wl_pointer_send_axis(seat_impl->pointer_resource, time,
                               WL_POINTER_AXIS_VERTICAL_SCROLL,
                               wl_fixed_from_double(scroll_delta * 10));
          wl_seat_send_pointer_frame(seat_impl);
        }];
      }

      // Flush scroll events immediately so clients receive them right away
      if (_compositor && [_compositor respondsToSelector:@selector
                                      (sendFrameCallbacksImmediately)]) {
        [_compositor sendFrameCallbacksImmediately];
      }

      [self triggerFrameCallback];
    }
    break;
  }
  default:
    break;
  }
}
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#pragma mark - NSResponder forwarding

- (void)mouseMoved:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)mouseDown:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)mouseUp:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)rightMouseDown:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)rightMouseUp:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)otherMouseDown:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)otherMouseUp:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)mouseDragged:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)rightMouseDragged:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)otherMouseDragged:(NSEvent *)event {
  [self handleMouseEvent:event];
}
- (void)scrollWheel:(NSEvent *)event {
  [self handleMouseEvent:event];
}

- (void)handleKeyboardEvent:(NSEvent *)event {
  if (!_seat) {
    WLog(@"INPUT", @"Warning: No seat available for keyboard event");
    return;
  }

  if (!_seat->keyboard_resource) {
    WLog(@"INPUT", @"Warning: No keyboard resource available (client hasn't "
                   @"requested keyboard)");
    return;
  }

  // No need to manually enforce keyboard enter here as WawonaCompositor handles
  // window activation focus, and handleMouseEvent handles pointer-follow focus.
  // We just proceed to send the key event.

  NSEventType eventType = [event type];
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  uint32_t time = (uint32_t)((ts.tv_sec * 1000) + (ts.tv_nsec / 1000000));
  unsigned short macKeyCode = [event keyCode];
  NSString *charsIgnoringModifiers = [event charactersIgnoringModifiers];
  uint32_t linuxKeyCode = 0;

  WLog(@"INPUT", @"Keyboard event: type=%lu, keyCode=%u, chars=%@",
       (unsigned long)eventType, macKeyCode, charsIgnoringModifiers);

  linuxKeyCode = macKeyCodeToLinuxKeyCode(macKeyCode);

  if (linuxKeyCode == 28) {
    // Enter key
  } else if ((linuxKeyCode == 0 || (linuxKeyCode >= 2 && linuxKeyCode <= 13)) &&
             charsIgnoringModifiers && charsIgnoringModifiers.length > 0) {
    unichar c = [charsIgnoringModifiers characterAtIndex:0];
    switch (c) {
    case ' ':
      linuxKeyCode = 57;
      break;
    case ';':
      linuxKeyCode = 39;
      break;
    case '\'':
      linuxKeyCode = 40;
      break;
    case ',':
      linuxKeyCode = 51;
      break;
    case '.':
      linuxKeyCode = 52;
      break;
    case '/':
      linuxKeyCode = 53;
      break;
    case '`':
      linuxKeyCode = 41;
      break;
    case '[':
      linuxKeyCode = 26;
      break;
    case ']':
      linuxKeyCode = 27;
      break;
    case '\\':
      linuxKeyCode = 43;
      break;
    case '-':
      linuxKeyCode = 12;
      break;
    case '=':
      linuxKeyCode = 13;
      break;
    case '\r':
      linuxKeyCode = 28;
      break;
    case '\t':
      linuxKeyCode = 15;
      break;
    case '1':
      linuxKeyCode = 2;
      break;
    case '2':
      linuxKeyCode = 3;
      break;
    case '3':
      linuxKeyCode = 4;
      break;
    case '4':
      linuxKeyCode = 5;
      break;
    case '5':
      linuxKeyCode = 6;
      break;
    case '6':
      linuxKeyCode = 7;
      break;
    case '7':
      linuxKeyCode = 8;
      break;
    case '8':
      linuxKeyCode = 9;
      break;
    case '9':
      linuxKeyCode = 10;
      break;
    case '0':
      linuxKeyCode = 11;
      break;
    default:
      if (linuxKeyCode == 0) {
        if (c >= 'a' && c <= 'z') {
          static const uint32_t letter_map[26] = {
              30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
              49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44};
          linuxKeyCode = letter_map[c - 'a'];
        }
      }
      break;
    }
  }

  if (linuxKeyCode == 0) {
    linuxKeyCode = macKeyCodeToLinuxKeyCode(macKeyCode);
  }

  NSEventModifierFlags modifierFlags = [event modifierFlags];
  uint32_t old_mods_depressed = _seat->mods_depressed;
  uint32_t shift_mask = 1 << 0;
  uint32_t lock_mask = 1 << 1;
  uint32_t control_mask = 1 << 2;
  uint32_t mod1_mask = 1 << 3;
  uint32_t mod4_mask = 1 << 6;
  uint32_t new_mods_depressed = 0;

  if (modifierFlags & NSEventModifierFlagShift)
    new_mods_depressed |= shift_mask;
  if (modifierFlags & NSEventModifierFlagCapsLock) {
    new_mods_depressed |= lock_mask;
    _seat->mods_locked |= lock_mask;
  }
  if (modifierFlags & NSEventModifierFlagControl)
    new_mods_depressed |= control_mask;
  if (modifierFlags & NSEventModifierFlagOption)
    new_mods_depressed |= mod1_mask;
  if (modifierFlags & NSEventModifierFlagCommand)
    new_mods_depressed |= mod4_mask;

  if (old_mods_depressed != new_mods_depressed) {
    _seat->mods_depressed = new_mods_depressed;
    // Send modifiers update
    uint32_t serial = wl_seat_get_serial(_seat);

    WLog(@"INPUT",
         @"Sending modifiers update: serial=%u, depressed=0x%x (was 0x%x), "
         @"latched=0x%x, locked=0x%x",
         serial, new_mods_depressed, old_mods_depressed, _seat->mods_latched,
         _seat->mods_locked);

    // Defensive check: ensure keyboard resource is still valid
    if (_seat->keyboard_resource &&
        wl_resource_get_client(_seat->keyboard_resource)) {
      wl_seat_send_keyboard_modifiers(_seat, serial);
    } else {
      WLog(@"INPUT", @"Warning: Skipping keyboard modifiers: keyboard resource "
                     @"is invalid");
    }
  }

  if (!(modifierFlags & NSEventModifierFlagCapsLock)) {
    _seat->mods_locked &= ~lock_mask;
  }

  if (linuxKeyCode == 0)
    return;

  uint32_t state;
  switch (eventType) {
  case NSEventTypeKeyDown:
    state = WL_KEYBOARD_KEY_STATE_PRESSED;
    break;
  case NSEventTypeKeyUp:
    state = WL_KEYBOARD_KEY_STATE_RELEASED;
    break;
  case NSEventTypeFlagsChanged: {
    // macOS sends FlagsChanged for modifiers. We need to determine if it's a
    // press or release.
    // We can check if the new modifiers state includes the bit corresponding to
    // this key code.
    // However, since we already calculated new_mods_depressed, we can check if
    // the semantic modifier bit for this key is set.
    // BUT, detecting which specific modifier key (Left vs Right Shift) was
    // pressed/released based just on flags is tricky.
    // A simpler heuristic: if the flag is SET in new flags but was NOT in old
    // flags (which we don't have easily here without tracking), it's a press?
    // Actually, we can check if the flag corresponding to this specific keycode
    // is set in the current event flags.

    BOOL isPressed = NO;
    switch (macKeyCode) {
    case 56: // Left Shift
    case 60: // Right Shift
      isPressed = (modifierFlags & NSEventModifierFlagShift) != 0;
      break;
    case 55: // Left Cmd
    case 54: // Right Cmd
      isPressed = (modifierFlags & NSEventModifierFlagCommand) != 0;
      break;
    case 58: // Left Alt
    case 61: // Right Alt
      isPressed = (modifierFlags & NSEventModifierFlagOption) != 0;
      break;
    case 59: // Left Ctrl
    case 62: // Right Ctrl
      isPressed = (modifierFlags & NSEventModifierFlagControl) != 0;
      break;
    case 57: // Caps Lock
      isPressed = (modifierFlags & NSEventModifierFlagCapsLock) != 0;
      break;
    default:
      // Fallback: Check if ANY modifier changed state?
      // If we can't map it, assume released if flags are empty? No, dangerous.
      // For now, assume based on new_mods_depressed diff IF we knew which bit.
      // Let's rely on the explicit key code checks above.
      break;
    }
    state = isPressed ? WL_KEYBOARD_KEY_STATE_PRESSED
                      : WL_KEYBOARD_KEY_STATE_RELEASED;
    break;
  }
  default:
    return;
  }

  uint32_t serial = wl_seat_get_serial(_seat);

  // Defensive checks to prevent crash
  if (!_seat || !_seat->keyboard_resource) {
    WLog(@"INPUT",
         @"Warning: Skipping keyboard key: invalid seat or keyboard resource");
    return;
  }

  // Additional validation - ensure surface is still valid and associated
  struct wl_surface_impl *keyboard_surface = NULL;
  if (_seat->keyboard_resource) {
    keyboard_surface = wl_resource_get_user_data(_seat->keyboard_resource);
    // Check if surface is still valid (not destroyed)
    if (keyboard_surface &&
        wl_resource_get_client(keyboard_surface->resource)) {
      // Surface is valid, proceed normally
    } else {
      // Surface is invalid or destroyed, skip this event
      WLog(@"INPUT", @"Warning: Skipping keyboard key: keyboard surface is "
                     @"invalid (likely destroyed)");
      return;
    }
  }

  WLog(@"INPUT", @"Sending keyboard key: keyCode=%u, state=%u, serial=%u",
       linuxKeyCode, state, serial);
  wl_seat_send_keyboard_key(_seat, serial, time, linuxKeyCode, state);

  // Trigger immediate frame callback so client can redraw in response to
  // keyboard input
  if (_compositor && [_compositor respondsToSelector:@selector
                                  (sendFrameCallbacksImmediately)]) {
    [_compositor sendFrameCallbacksImmediately];
  }

  [self triggerRedraw];
}
#endif

- (void)triggerFrameCallback {
  [self triggerRedraw];
}

- (void)triggerRedraw {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (!_window || !_window.rootViewController.view) {
#else
  if (!_window || !_window.contentView) {
#endif
    return;
  }

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *contentView = _window.rootViewController.view;
#else
  NSView *contentView = _window.contentView;
#endif

  if ([contentView respondsToSelector:@selector(metalView)]) {
    id metalView = [contentView performSelector:@selector(metalView)];
    if (metalView) {
      dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        if ([metalView respondsToSelector:@selector(setNeedsDisplay)]) {
          [metalView performSelector:@selector(setNeedsDisplay)];
        }
#else
                if ([metalView respondsToSelector:@selector(setNeedsDisplay:)]) {
                    [metalView performSelector:@selector(setNeedsDisplay:) withObject:@YES];
                }
#endif
      });
    }
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      [contentView setNeedsDisplay];
#else
            [contentView setNeedsDisplay:YES];
#endif
    });
  }

  id compositor = _compositor;
  if (compositor != nil) {
    SEL sendFrameCallbacksSelector = @selector(sendFrameCallbacksImmediately);
    if ([compositor respondsToSelector:sendFrameCallbacksSelector]) {
      dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [compositor performSelector:sendFrameCallbacksSelector];
#pragma clang diagnostic pop
      });
    }

    SEL renderFrameSelector = @selector(renderFrame);
    if ([compositor respondsToSelector:renderFrameSelector]) {
      dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [compositor performSelector:renderFrameSelector];
#pragma clang diagnostic pop
      });
    }
  }
}

@end
