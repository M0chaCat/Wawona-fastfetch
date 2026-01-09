// renderer_macos_helpers.m - Rendering helper functions for macOS Wayland
// compositor This file contains the rendering pipeline logic moved from
// WawonaCompositor.m

#include "../compositor_implementations/wayland_compositor.h"
#include "../compositor_implementations/xdg_shell.h"
#import "../core/WawonaSurfaceManager.h"
#include "WawonaCompositor.h"
#import "renderer_macos.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>

// Forward declarations for external symbols
extern struct xdg_toplevel_impl *
xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *wl_surface);
extern WawonaCompositor *g_wl_compositor_instance;

// Forward declaration for CompositorView (defined in WawonaCompositor.m)
@interface CompositorView : NSView
@property(nonatomic, strong) id<RenderingBackend> renderer;
@end

//==============================================================================
// MARK: - Public C API for Compositor Integration
//==============================================================================

// Helper function to find the appropriate renderer for a surface
id<RenderingBackend>
wawona_find_renderer_for_surface(struct wl_surface_impl *surface) {
  if (!g_wl_compositor_instance || !surface) {
    return nil;
  }

  // Get the toplevel for this surface
  struct xdg_toplevel_impl *toplevel =
      xdg_surface_get_toplevel_from_wl_surface(surface);

  [g_wl_compositor_instance.mapLock lock];
  NSLog(
      @"[RENDER] findRendererForSurface: surface=%p, toplevel=%p, mapCount=%lu",
      (void *)surface, (void *)toplevel,
      (unsigned long)g_wl_compositor_instance.windowToToplevelMap.count);

  if (toplevel && g_wl_compositor_instance.toplevelToRendererMap) {
    // Fast thread-safe lookup without iterating windows or accessing AppKit
    NSValue *toplevelKey = [NSValue valueWithPointer:toplevel];
    id<RenderingBackend> renderer =
        [g_wl_compositor_instance.toplevelToRendererMap
            objectForKey:toplevelKey];

    if (renderer) {
      NSLog(
          @"[RENDER] findRendererForSurface: Found renderer %p for toplevel %p",
          renderer, toplevel);
      [g_wl_compositor_instance.mapLock unlock];
      return renderer;
    }
  }

  // No specific window found, use main compositor renderer fallback
  NSLog(@"[RENDER] findRendererForSurface: Falling back to main "
        @"renderingBackend %p",
        g_wl_compositor_instance.renderingBackend);
  [g_wl_compositor_instance.mapLock unlock];
  return g_wl_compositor_instance.renderingBackend;
}

// Immediately render a surface to its associated window/renderer
void wawona_render_surface_immediate(struct wl_surface_impl *surface) {
  if (!g_wl_compositor_instance || !surface) {
    return;
  }

  // Check if window needs to be shown and sized for first client
  if (!g_wl_compositor_instance.windowShown && surface->buffer_resource) {
    // Get buffer size appropriately
    int32_t w = 0, h = 0;
    struct wl_shm_buffer *shm_buf = wl_shm_buffer_get(surface->buffer_resource);

    if (shm_buf) {
      w = wl_shm_buffer_get_width(shm_buf);
      h = wl_shm_buffer_get_height(shm_buf);
    } else {
      struct buffer_data {
        void *data;
        int32_t offset;
        int32_t width;
        int32_t height;
        int32_t stride;
        uint32_t format;
      };
      struct buffer_data *buf_data =
          wl_resource_get_user_data(surface->buffer_resource);
      if (buf_data && buf_data->width > 0 && buf_data->height > 0) {
        w = buf_data->width;
        h = buf_data->height;
      }
    }

    if (w > 0 && h > 0) {
      [g_wl_compositor_instance showAndSizeWindowForFirstClient:w height:h];
    }
  } else if (surface->buffer_resource) {
    // NOTE: Auto-resize logic removed.
    // Window should be created with the correct size from the start in
    // macos_create_window_for_toplevel. Resizing after creation causes spastic
    // behavior and infinite loops.
  }

  // Find the appropriate renderer for this surface and render
  id<RenderingBackend> renderer = wawona_find_renderer_for_surface(surface);

  // Late-Show Logic: If window was created hidden (0x0), show it now that we
  // have content
  struct xdg_toplevel_impl *toplevel =
      xdg_surface_get_toplevel_from_wl_surface(surface);
  if (toplevel && toplevel->native_window) {
    NSWindow *window = (__bridge NSWindow *)toplevel->native_window;
    if (!window.isVisible) {
      int32_t width = 0, height = 0;
      struct wl_shm_buffer *shm_buf =
          wl_shm_buffer_get(surface->buffer_resource);
      if (shm_buf) {
        width = wl_shm_buffer_get_width(shm_buf);
        height = wl_shm_buffer_get_height(shm_buf);
      }

      if (width > 0 && height > 0) {
        NSLog(@"[RENDER] First buffer committed (%dx%d). Showing window %p",
              width, height, window);
        NSRect frame = [window frame];
        NSRect contentRect = [window contentRectForFrameRect:frame];
        // Adjust frame to match new content size while preserving top-left
        // position (or centering?) Let's preserve top-left for standard window
        // behavior, or center if it was 0x0

        NSRect newContentRect = NSMakeRect(contentRect.origin.x,
                                           contentRect.origin.y, width, height);
        NSRect newFrame = [window frameRectForContentRect:newContentRect];

        // If it was at 100,100 (default), maybe we want to center it?
        // For now, just setting size is sufficient.
        [window setFrame:newFrame display:YES];
        [window makeKeyAndOrderFront:nil];
      }
    }
  }

  // Sync CALayer size with committed buffer for CSD
  // For SSD, size is managed by the window container
  if (toplevel && toplevel->decoration_mode == 1) { // 1 = CSD
    WawonaSurfaceLayer *layer =
        [[WawonaSurfaceManager sharedManager] layerForSurface:surface];
    if (layer) {
      [layer updateContentWithSize:CGSizeMake(surface->width, surface->height)];
    }
  }

  if (renderer && [renderer respondsToSelector:@selector(renderSurface:)]) {
    [renderer renderSurface:surface];
  }

  // CRITICAL: Trigger IMMEDIATE redraw after rendering surface
  // Rely on the renderer to handle setNeedsDisplay thread-safely
  if (renderer && [renderer respondsToSelector:@selector(setNeedsDisplay)]) {
    [renderer setNeedsDisplay];
  } else if ([g_wl_compositor_instance.renderingBackend
                 respondsToSelector:@selector(setNeedsDisplay)]) {
    [g_wl_compositor_instance.renderingBackend setNeedsDisplay];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  } else if (g_wl_compositor_instance.window &&
             g_wl_compositor_instance.window.rootViewController.view) {
    // iOS: Fallback for Cocoa backend
    dispatch_async(dispatch_get_main_queue(), ^{
      [g_wl_compositor_instance.window.rootViewController.view setNeedsDisplay];
    });
#else
  } else if (g_wl_compositor_instance.window &&
             g_wl_compositor_instance.window.contentView) {
    // macOS: Fallback for Cocoa backend
    dispatch_async(dispatch_get_main_queue(), ^{
      [g_wl_compositor_instance.window.contentView setNeedsDisplay];
    });
#endif
  }
}

// Callback function for Wayland surface commits
void wawona_render_surface_callback(struct wl_surface_impl *surface) {
  if (!surface) {
    return;
  }

  // CRITICAL: Validate surface is still valid before dispatching async render
  // The surface may be destroyed between commit and async render execution
  if (!surface->resource) {
    return;
  }

  // SAFETY: Check user_data FIRST before calling wl_resource_get_client
  // This is safer because user_data access doesn't dereference as many internal
  // fields
  struct wl_surface_impl *surface_check =
      wl_resource_get_user_data(surface->resource);
  if (!surface_check || surface_check != surface) {
    return;
  }

  // Now verify resource is still valid by checking if we can get the client
  struct wl_client *client = wl_resource_get_client(surface->resource);
  if (!client) {
    return;
  }

  if (g_wl_compositor_instance && g_wl_compositor_instance.renderingBackend) {
    // CRITICAL: Render SYNCHRONOUSLY on main thread for immediate updates
    // Wayland compositors MUST repaint immediately when clients commit buffers
    // Async dispatch causes race conditions and delays that break nested
    // compositors
    if ([NSThread isMainThread]) {
      wawona_render_surface_immediate(surface);
    } else {
      // Use dispatch_async to avoid deadlock when main thread is waiting for
      // lock
      dispatch_async(dispatch_get_main_queue(), ^{
        wawona_render_surface_immediate(surface);
      });
    }
  }
}
