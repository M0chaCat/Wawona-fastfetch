// WawonaCompositorView_macos.m - macOS compositor view implementation
// Extracted from WawonaCompositorView.m for platform separation

#import "WawonaCompositorView_macos.h"
#import "../compositor_implementations/xdg_shell.h"
#import "../input/input_handler.h"
#import "RenderingBackend.h"
#import "WawonaCompositor.h"
#import "WawonaSurfaceManager.h"
#import <MetalKit/MetalKit.h>

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

// Forward declaration
extern WawonaCompositor *g_wl_compositor_instance;

@implementation CompositorView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.wantsLayer = YES;
    self.layer.opaque = NO;
    self.layer.backgroundColor = [NSColor clearColor].CGColor;
    self.layer.masksToBounds = NO; // Allow CSD shadows to bleed out
  }
  return self;
}

- (NSView *)hitTest:(NSPoint)point {
  // NSView hitTest: expects point in the superview's coordinate system.
  // Convert it to local coordinates for pickSurfaceAt:
  // This ensures robust coordinate handling for macOS
  NSPoint localPoint = [self convertPoint:point fromView:self.superview];

  if (self.inputHandler) {
    // pickSurfaceAt: returns NULL if the point is in the shadow region
    // (outside the window geometry but inside the surface buffer)
    if ([self.inputHandler pickSurfaceAt:localPoint] == NULL) {
      // If we are over a shadow area (no surface picked), return nil to allow
      // click passthrough to underlying macOS windows.
      return nil;
    }
  }
  return [super hitTest:point];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)mouseDownCanMoveWindow {
  // For CSD windows, let the client handle window movement/resizing
  // For SSD windows, allow macOS to move the window
  NSWindow *window = self.window;
  if (window) {
    NSValue *toplevelValue = [g_wl_compositor_instance.windowToToplevelMap
        objectForKey:[NSValue valueWithPointer:(__bridge void *)window]];

    if (toplevelValue) {
      struct xdg_toplevel_impl *toplevel = [toplevelValue pointerValue];
      if (toplevel->decoration_mode == 1) { // CLIENT_SIDE
        return NO; // Let CSD client handle window movement/resizing
      }
    }
  }
  return YES; // Allow macOS to move SSD windows
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)becomeFirstResponder {
  NSLog(@"[COMPOSITOR VIEW] Became first responder - ready for keyboard input");
  BOOL result = [super becomeFirstResponder];
  // TODO: Send keyboard enter to focused surface when view becomes first
  // responder For now, skip this to avoid crashes during client window setup
  return result;
}

- (void)mouseMoved:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)mouseDown:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)mouseUp:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)rightMouseDown:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)rightMouseUp:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)otherMouseDown:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)otherMouseUp:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)mouseDragged:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)rightMouseDragged:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)otherMouseDragged:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (void)scrollWheel:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleMouseEvent:event];
  }
}

- (BOOL)resignFirstResponder {
  NSLog(@"[COMPOSITOR VIEW] Resigned first responder");
  return [super resignFirstResponder];
}

- (void)drawRect:(NSRect)dirtyRect {
  if (self.metalView && self.metalView.superview == self) {
    return;
  }
  if (self.renderer) {
    [self.renderer drawSurfacesInRect:dirtyRect];
  } else {
    [[NSColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0] setFill];
    NSRectFill(dirtyRect);
  }
}

- (void)keyDown:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleKeyboardEvent:event];
  } else {
    [super keyDown:event];
  }
}

- (void)keyUp:(NSEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleKeyboardEvent:event];
  } else {
    [super keyUp:event];
  }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
  if (self.inputHandler && self.inputHandler.seat &&
      self.inputHandler.seat->focused_surface) {
    [self.inputHandler handleKeyboardEvent:event];
    return YES;
  }
  return [super performKeyEquivalent:event];
}

@end

#endif // !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
