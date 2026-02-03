#import "WawonaWindow.h"
#import "../../logging/WawonaLog.h"
#import "WawonaCompositorBridge.h"

//
// WawonaView Implementation
//
@implementation WawonaView {
  CALayer *_contentLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    _contentLayer = [CALayer layer];
    _contentLayer.contentsGravity = kCAGravityResize;
    _contentLayer.masksToBounds = YES;
    _contentLayer.autoresizingMask =
        kCALayerWidthSizable | kCALayerHeightSizable;
    [self.layer addSublayer:_contentLayer];
    [self updateTrackingAreas];
  }
  return self;
}

- (CALayer *)contentLayer {
  if (!_contentLayer) {
    _contentLayer = [CALayer layer];
    _contentLayer.contentsGravity = kCAGravityResize;
    _contentLayer.masksToBounds = YES;
    _contentLayer.autoresizingMask =
        kCALayerWidthSizable | kCALayerHeightSizable;
    if (self.layer) {
      [self.layer addSublayer:_contentLayer];
    }
  }
  return _contentLayer;
}

- (void)setFrame:(NSRect)frame {
  [super setFrame:frame];
  _contentLayer.frame = self.bounds;
}

- (void)setBounds:(NSRect)bounds {
  [super setBounds:bounds];
  _contentLayer.frame = self.bounds;
}

- (void)layout {
  [super layout];
  _contentLayer.frame = self.bounds;
}

- (void)updateLayer {
  [super updateLayer];
  _contentLayer.frame = self.bounds;
}

- (void)updateTrackingAreas {
  // Clear existing tracking areas
  for (NSTrackingArea *area in self.trackingAreas) {
    [self removeTrackingArea:area];
  }

  // Create new tracking area for entire bounds
  NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
      initWithRect:self.bounds
           options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                   NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect |
                   NSTrackingActiveAlways
             owner:self
          userInfo:nil];

  [self addTrackingArea:trackingArea];
  [super updateTrackingAreas];
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)isFlipped {
  return YES;
}

// Helper to get window ID
- (uint64_t)wawonaWindowId {
  if (self.overrideWindowId != 0) {
    return self.overrideWindowId;
  }
  if ([self.window isKindOfClass:[WawonaWindow class]]) {
    return [(WawonaWindow *)self.window wawonaWindowId];
  }
  return 0;
}

//
// Input Handling
//

- (void)mouseEntered:(NSEvent *)event {
  NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
  double y = loc.y;

  [[WawonaCompositorBridge sharedBridge]
      injectPointerEnterForWindow:[self wawonaWindowId]
                                x:loc.x
                                y:y
                        timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)mouseExited:(NSEvent *)event {
  [[WawonaCompositorBridge sharedBridge]
      injectPointerLeaveForWindow:[self wawonaWindowId]
                        timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)mouseMoved:(NSEvent *)event {
  NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
  double y = loc.y;

  [[WawonaCompositorBridge sharedBridge]
      injectPointerMotionForWindow:[self wawonaWindowId]
                                 x:loc.x
                                 y:y
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)mouseDragged:(NSEvent *)event {
  [self mouseMoved:event];
}

- (void)mouseDown:(NSEvent *)event {
  [[WawonaCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wawonaWindowId]
                            button:0x110 // BTN_LEFT
                           pressed:YES
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)mouseUp:(NSEvent *)event {
  [[WawonaCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wawonaWindowId]
                            button:0x110 // BTN_LEFT
                           pressed:NO
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)rightMouseDown:(NSEvent *)event {
  [[WawonaCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wawonaWindowId]
                            button:0x111 // BTN_RIGHT
                           pressed:YES
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

- (void)rightMouseUp:(NSEvent *)event {
  [[WawonaCompositorBridge sharedBridge]
      injectPointerButtonForWindow:[self wawonaWindowId]
                            button:0x111 // BTN_RIGHT
                           pressed:NO
                         timestamp:(uint32_t)(event.timestamp * 1000)];
}

// Helper to translate macOS keycodes to XKB/Evdev keycodes (offset by 8)
static uint32_t macos_to_xkb_keycode(unsigned short mac_code) {
  // Common mappings (incomplete, based on standard US layout)
  // Uses Apple's standard US layout keycodes mapped to Linux Evdev codes
  // (offset by 8 for XKB) Source:
  // https://github.com/torvalds/linux/blob/master/drivers/hid/hid-apple.c
  // (reverse engineered) and
  // https://github.com/freebsd/freebsd-src/blob/main/sys/dev/usb/usb_hid.c

  switch (mac_code) {
  case 0:
    return 30; // A -> KEY_A
  case 1:
    return 31; // S -> KEY_S
  case 2:
    return 32; // D -> KEY_D
  case 3:
    return 33; // F -> KEY_F
  case 4:
    return 35; // H -> KEY_H
  case 5:
    return 34; // G -> KEY_G
  case 6:
    return 44; // Z -> KEY_Z
  case 7:
    return 45; // X -> KEY_X
  case 8:
    return 46; // C -> KEY_C
  case 9:
    return 47; // V -> KEY_V
  case 11:
    return 48; // B -> KEY_B
  case 12:
    return 16; // Q -> KEY_Q
  case 13:
    return 17; // W -> KEY_W
  case 14:
    return 18; // E -> KEY_E
  case 15:
    return 19; // R -> KEY_R
  case 16:
    return 21; // Y -> KEY_Y
  case 17:
    return 20; // T -> KEY_T
  case 18:
    return 2; // 1 -> KEY_1
  case 19:
    return 3; // 2 -> KEY_2
  case 20:
    return 4; // 3 -> KEY_3
  case 21:
    return 5; // 4 -> KEY_4
  case 22:
    return 7; // 6 -> KEY_6
  case 23:
    return 6; // 5 -> KEY_5
  case 24:
    return 13; // = -> KEY_EQUAL
  case 25:
    return 10; // 9 -> KEY_9
  case 26:
    return 8; // 7 -> KEY_7
  case 27:
    return 12; // - -> KEY_MINUS
  case 28:
    return 9; // 8 -> KEY_8
  case 29:
    return 11; // 0 -> KEY_0
  case 30:
    return 27; // ] -> KEY_RIGHTBRACE
  case 31:
    return 24; // O -> KEY_O
  case 32:
    return 22; // U -> KEY_U
  case 33:
    return 26; // [ -> KEY_LEFTBRACE
  case 34:
    return 23; // I -> KEY_I
  case 35:
    return 25; // P -> KEY_P
  case 36:
    return 28; // Return -> KEY_ENTER
  case 37:
    return 38; // L -> KEY_L
  case 38:
    return 36; // J -> KEY_J
  case 39:
    return 40; // ' -> KEY_APOSTROPHE
  case 40:
    return 37; // K -> KEY_K
  case 41:
    return 39; // ; -> KEY_SEMICOLON
  case 42:
    return 43; // \ -> KEY_BACKSLASH
  case 43:
    return 51; // , -> KEY_COMMA
  case 44:
    return 53; // / -> KEY_SLASH
  case 45:
    return 49; // N -> KEY_N
  case 46:
    return 50; // M -> KEY_M
  case 47:
    return 52; // . -> KEY_DOT
  case 48:
    return 15; // Tab -> KEY_TAB
  case 49:
    return 57; // Space -> KEY_SPACE
  case 50:
    return 41; // ` -> KEY_GRAVE
  case 51:
    return 14; // Delete (Backspace) -> KEY_BACKSPACE
  case 53:
    return 1; // Esc -> KEY_ESC
  case 55:
    return 125; // Command -> KEY_LEFTMETA (Super)
  case 54:
    return 126; // Right Command -> KEY_RIGHTMETA (Super_R)
  case 63:
    return 464; // Fn -> KEY_FN (0x1d0)
  case 56:
    return 42; // Shift Left -> KEY_LEFTSHIFT
  case 57:
    return 58; // Caps Lock -> KEY_CAPSLOCK
  case 58:
    return 56; // Option Left -> KEY_LEFTALT
  case 59:
    return 29; // Control Left -> KEY_LEFTCTRL
  case 60:
    return 54; // Shift Right -> KEY_RIGHTSHIFT
  case 61:
    return 100; // Option Right -> KEY_RIGHTALT
  case 62:
    return 97; // Control Right -> KEY_RIGHTCTRL
  case 123:
    return 105; // Left -> KEY_LEFT
  case 124:
    return 106; // Right -> KEY_RIGHT
  case 125:
    return 108; // Down -> KEY_DOWN
  case 126:
    return 103; // Up -> KEY_UP
  case 115:
    return 102; // Home -> KEY_HOME
  case 119:
    return 107; // End -> KEY_END
  case 116:
    return 104; // Page Up -> KEY_PAGEUP
  case 121:
    return 109; // Page Down -> KEY_PAGEDOWN
  case 117:
    return 111; // Forward Delete -> KEY_DELETE
  case 96:
    return 63; // F5 -> KEY_F5
  case 97:
    return 64; // F6 -> KEY_F6
  case 98:
    return 65; // F7 -> KEY_F7
  case 99:
    return 61; // F3 -> KEY_F3
  case 100:
    return 66; // F8 -> KEY_F8
  case 101:
    return 67; // F9 -> KEY_F9
  case 109:
    return 68; // F10 -> KEY_F10
  case 103:
    return 87; // F11 -> KEY_F11
  case 111:
    return 88; // F12 -> KEY_F12
  case 105:
    return 183; // F13
  case 107:
    return 184; // F14
  case 113:
    return 185; // F15
  case 122:
    return 59; // F1 -> KEY_F1
  case 120:
    return 60; // F2 -> KEY_F2
  case 118:
    return 62; // F4 -> KEY_F4
  default:
    return 0;
  }
}

- (void)keyDown:(NSEvent *)event {
  WLog(@"INPUT", @"keyDown: keyCode=%d", event.keyCode);
  uint32_t keycode = macos_to_xkb_keycode(event.keyCode);
  if (keycode > 0) {
    [[WawonaCompositorBridge sharedBridge]
        injectKeyWithKeycode:keycode
                     pressed:YES
                   timestamp:(uint32_t)(event.timestamp * 1000)];
  }
}

- (void)keyUp:(NSEvent *)event {
  uint32_t keycode = macos_to_xkb_keycode(event.keyCode);
  if (keycode > 0) {
    [[WawonaCompositorBridge sharedBridge]
        injectKeyWithKeycode:keycode
                     pressed:NO
                   timestamp:(uint32_t)(event.timestamp * 1000)];
  }
}

- (void)flagsChanged:(NSEvent *)event {
  WLog(@"INPUT", @"flagsChanged: keyCode=%hu flags=0x%lx", event.keyCode,
       (unsigned long)event.modifierFlags);

  static NSMutableSet *pressedModifiers = nil;
  if (!pressedModifiers) {
    pressedModifiers = [NSMutableSet set];
  }

  uint32_t keycode = macos_to_xkb_keycode(event.keyCode);
  if (keycode > 0) {
    // Track physical key state
    BOOL isPressed = NO;
    NSNumber *keyObj = @(keycode);

    // Caps Lock special handling? No, simple toggle tracking is ambiguous.
    // Better: if it's already in the set, it's a release.
    // Most modifiers work this way (press -> flagsChanged, release ->
    // flagsChanged).
    if ([pressedModifiers containsObject:keyObj]) {
      [pressedModifiers removeObject:keyObj];
      isPressed = NO;
    } else {
      [pressedModifiers addObject:keyObj];
      isPressed = YES;
    }

    WLog(@"INPUT", @"Determined modifier key state: keycode=%u isPressed=%d",
         keycode, isPressed);

    [[WawonaCompositorBridge sharedBridge]
        injectKeyWithKeycode:keycode
                     pressed:isPressed
                   timestamp:(uint32_t)(event.timestamp * 1000)];
  }

  NSUInteger flags = [event modifierFlags];
  uint32_t depressed = 0;
  uint32_t locked = 0;

  if (flags & NSEventModifierFlagShift) {
    depressed |= 1;
  }
  if (flags & NSEventModifierFlagControl) {
    depressed |= 4;
  }
  if (flags & NSEventModifierFlagOption) {
    depressed |= 8;
  }
  if (flags & NSEventModifierFlagCommand) {
    depressed |= 64;
  }
  if (flags & NSEventModifierFlagCapsLock) {
    locked |= 2;
  }

  WLog(@"INPUT", @"Injecting modifiers state: depressed=%u locked=%u",
       depressed, locked);

  [[WawonaCompositorBridge sharedBridge] injectModifiersWithDepressed:depressed
                                                              latched:0
                                                               locked:locked
                                                                group:0];
}

@end

//
// WawonaWindow Implementation
//
@implementation WawonaWindow

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backingStoreType
                              defer:(BOOL)flag {
  self = [super initWithContentRect:contentRect
                          styleMask:style
                            backing:backingStoreType
                              defer:flag];
  if (self) {
    [self setDelegate:self];
    // AppKit will automatically apply Liquid Glass styling on macOS Tahoe
  }
  return self;
}

// Setup macOS 26 Tahoe Liquid Glass effect
// Removed: managed by configureWindowAppearance now

- (void)windowDidResize:(NSNotification *)notification {
  if (self.processingResize) {
    return;
  }

  NSSize size = [self.contentView bounds].size;
  // Convert to pixels (handling retina scale if needed, though Wayland handles
  // scale separate) For now just passing points as that's what we likely
  // initialized with, but we should probably use backingAlignedRect to get
  // pixels if we want pixel perfect. The compositor expects logical or physical
  // size depending on how we configured it. api.rs resize_window takes u32.

  // Let's use backing scale factor to get physical pixels if high dpi
  // Or just logical if that's what we want.
  // xdg_shell usually works in logical coordinates.

  [[WawonaCompositorBridge sharedBridge]
      injectWindowResize:self.wawonaWindowId
                   width:(uint32_t)size.width
                  height:(uint32_t)size.height];
}

- (BOOL)canBecomeKeyWindow {
  return YES;
}

- (BOOL)canBecomeMainWindow {
  return YES;
}

- (void)becomeKeyWindow {
  [super becomeKeyWindow];

  WLog(@"INPUT", @"Window %llu became key - setting keyboard focus",
       self.wawonaWindowId);

  // Make sure the content view gets key events
  [self makeFirstResponder:self.contentView];

  // 1. Activate window (visual state)
  [[WawonaCompositorBridge sharedBridge] setWindowActivated:self.wawonaWindowId
                                                     active:YES];

  // 2. Give keyboard focus
  WLog(@"INPUT", @"Calling injectKeyboardEnterForWindow for window %llu",
       self.wawonaWindowId);
  [[WawonaCompositorBridge sharedBridge]
      injectKeyboardEnterForWindow:self.wawonaWindowId
                              keys:@[]];
}

- (void)resignKeyWindow {
  [super resignKeyWindow];

  WLog(@"INPUT", @"Window %llu resigned key - removing keyboard focus",
       self.wawonaWindowId);

  // 1. Deactivate window
  [[WawonaCompositorBridge sharedBridge] setWindowActivated:self.wawonaWindowId
                                                     active:NO];

  // 2. Remove keyboard focus
  [[WawonaCompositorBridge sharedBridge]
      injectKeyboardLeaveForWindow:self.wawonaWindowId];
}

@end
