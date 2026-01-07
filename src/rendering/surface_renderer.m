#import "surface_renderer.h"
#include "WawonaCompositor.h"
#include "apple_backend.h"
#include "metal_dmabuf.h"
#include "wayland_linux_dmabuf.h"
#include "wayland_viewporter.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#include "egl_buffer_handler.h"
#endif
#include <time.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <wayland-server.h>

// Forward declaration for global compositor instance
extern WawonaCompositor *g_wl_compositor_instance;

// Helper for timestamp
static uint32_t get_time_in_milliseconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

// Surface image data - stores CGImage and position for drawing
// OPTIMIZED: Cache CGImage to avoid recreating on every frame
@interface SurfaceImage : NSObject
@property(nonatomic, assign) CGImageRef image;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property(nonatomic, assign) CGRect frame;
#else
@property(nonatomic, assign) CGRect frame;
#endif
@property(nonatomic, assign) struct wl_surface_impl *surface;
@property(nonatomic, assign)
    void *lastBufferData; // Track buffer to avoid unnecessary recreations
@property(nonatomic, assign) int32_t lastWidth;
@property(nonatomic, assign) int32_t lastHeight;
@property(nonatomic, assign) uint32_t lastFormat;
@end

@implementation SurfaceImage
- (void)dealloc {
  if (_image) {
    CGImageRelease(_image);
    _image = NULL;
  }
#if !__has_feature(objc_arc)
  [super dealloc];
#endif
}
@end

// Helper to convert raw pixel data to CGImage
static CGImageRef createCGImageFromData(void *data, int32_t width,
                                        int32_t height, int32_t stride,
                                        uint32_t format) {
  if (!data || width <= 0 || height <= 0 || stride <= 0) {
    return NULL;
  }

  // Convert format to CGImage format
  // Note: macOS is little-endian, so ARGB8888/XRGB8888 formats are stored as
  // BGRA in memory
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGBitmapInfo bitmapInfo = 0;

  // DRM Formats (Little Endian definitions)
  // DRM_FORMAT_ARGB8888 = 0x34325241 ('AR24')
  // DRM_FORMAT_XRGB8888 = 0x34325258 ('XR24')
  // DRM_FORMAT_ABGR8888 = 0x34324241 ('AB24')
  // DRM_FORMAT_XBGR8888 = 0x34324258 ('XB24')

  if (format == WL_SHM_FORMAT_ARGB8888 || format == WL_SHM_FORMAT_XRGB8888 ||
      format == 0x34325241 /* DRM_FORMAT_ARGB8888 */ ||
      format == 0x34325258 /* DRM_FORMAT_XRGB8888 */) {
    // ARGB8888/XRGB8888: Alpha/Red/Green/Blue logical order
    // On little-endian (macOS), bytes in memory are BGRA (blue byte first)
    // Use little-endian byte order with alpha first (most significant byte)
    bitmapInfo = kCGBitmapByteOrder32Little;
    if (format == WL_SHM_FORMAT_ARGB8888 || format == 0x34325241) {
      bitmapInfo |= kCGImageAlphaPremultipliedFirst;
    } else {
      bitmapInfo |= kCGImageAlphaNoneSkipFirst; // XRGB8888 has no alpha
    }
  } else if (format == WL_SHM_FORMAT_RGBA8888 ||
             format == WL_SHM_FORMAT_RGBX8888) {
    // RGBA8888/RGBX8888: Red/Green/Blue/Alpha logical order
    // On little-endian, bytes in memory are ABGR (alpha byte first, but alpha
    // is last logically)
    bitmapInfo = kCGBitmapByteOrder32Little;
    if (format == WL_SHM_FORMAT_RGBA8888) {
      bitmapInfo |= kCGImageAlphaPremultipliedLast;
    } else {
      bitmapInfo |= kCGImageAlphaNoneSkipLast; // RGBX8888 has no alpha
    }
  } else if (format == WL_SHM_FORMAT_ABGR8888 ||
             format == WL_SHM_FORMAT_XBGR8888 ||
             format == 0x34324241 /* DRM_FORMAT_ABGR8888 */ ||
             format == 0x34324258 /* DRM_FORMAT_XBGR8888 */) {
    // ABGR8888/XBGR8888: Alpha/Blue/Green/Red logical order
    // On little-endian, bytes in memory are RGBA
    bitmapInfo = kCGBitmapByteOrder32Little;
    if (format == WL_SHM_FORMAT_ABGR8888 || format == 0x34324241) {
      bitmapInfo |= kCGImageAlphaPremultipliedFirst;
    } else {
      bitmapInfo |= kCGImageAlphaNoneSkipFirst;
    }
  } else if (format == WL_SHM_FORMAT_BGRA8888 ||
             format == WL_SHM_FORMAT_BGRX8888) {
    // BGRA8888/BGRX8888: Blue/Green/Red/Alpha logical order
    // On little-endian, bytes in memory are ARGB
    bitmapInfo = kCGBitmapByteOrder32Little;
    if (format == WL_SHM_FORMAT_BGRA8888) {
      bitmapInfo |= kCGImageAlphaPremultipliedLast;
    } else {
      bitmapInfo |= kCGImageAlphaNoneSkipLast;
    }
  } else {
    // Default: assume ARGB8888-like format
    bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
  }

  // Create a copy of the data managed by CFData
  // FIX: Copy data to avoid use-after-free when buffer is released
  // The previous implementation used CGDataProviderCreateWithData with NULL
  // destructor, which led to crashes if the underlying buffer was destroyed
  // while the image was still alive.

  // Log before accessing memory to debug crashes
  NSLog(@"[RENDERER] Creating CFData from %p, size %d (stride %d * height %d)",
        data, stride * height, stride, height);

  // Create a copy of the data managed by CFData
  CFDataRef cfData = CFDataCreate(NULL, data, stride * height);
  if (!cfData) {
    NSLog(@"[RENDERER] ❌ CFDataCreate failed");
    CGColorSpaceRelease(colorSpace);
    return NULL;
  }
  NSLog(@"[RENDERER] CFData created successfully");

  CGDataProviderRef provider = CGDataProviderCreateWithCFData(cfData);
  CFRelease(cfData); // Provider retains it

  if (!provider) {
    CGColorSpaceRelease(colorSpace);
    return NULL;
  }

  // Create CGImage from data provider
  CGImageRef image =
      CGImageCreate(width, height, 8, 32, stride, colorSpace, bitmapInfo,
                    provider, NULL, NO, kCGRenderingIntentDefault);

  CGDataProviderRelease(provider);
  CGColorSpaceRelease(colorSpace);

  return image;
}

@implementation SurfaceRenderer

// Safe method to trigger display update
- (void)safeSetNeedsDisplay {
  if (self.compositorView &&
      [self.compositorView respondsToSelector:@selector(setNeedsDisplay:)]) {
    [self.compositorView setNeedsDisplay:YES];
  }
}

// Helper method to check if a surface belongs to this renderer's window
- (BOOL)surfaceBelongsToThisWindow:(struct wl_surface_impl *)surface {
  if (!surface || !self.window) {
    return YES; // If no window association, render everywhere (for main
                // compositor)
  }

  // Get the toplevel for this surface
  extern struct xdg_toplevel_impl *xdg_surface_get_toplevel_from_wl_surface(
      struct wl_surface_impl * wl_surface);
  struct xdg_toplevel_impl *toplevel =
      xdg_surface_get_toplevel_from_wl_surface(surface);
  if (!toplevel) {
    return NO; // Surface doesn't belong to a toplevel
  }

  // Check if this toplevel is associated with our window
  WawonaCompositor *compositor = (WawonaCompositor *)g_wl_compositor_instance;
  if (!compositor || !compositor.windowToToplevelMap) {
    return NO;
  }

  // Check if any window in the map has this toplevel
  for (NSValue *windowValue in compositor.windowToToplevelMap) {
    NSValue *toplevelValue =
        [compositor.windowToToplevelMap objectForKey:windowValue];
    struct xdg_toplevel_impl *mappedToplevel = [toplevelValue pointerValue];
    if (mappedToplevel == toplevel) {
      NSWindow *mappedWindow = [windowValue pointerValue];
      return (mappedWindow == self.window);
    }
  }

  return NO;
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithCompositorView:(UIView *)view {
#else
- (instancetype)initWithCompositorView:(NSView *)view {
#endif
  self = [super init];
  if (self) {
    _compositorView = view;
    _surfaceImages = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)renderSurface:(struct wl_surface_impl *)surface {
  if (!surface) {
    return;
  }
  NSLog(@"[RENDER] renderSurface: %p, compositorView: %p", surface,
        self.compositorView);

  // CRITICAL: Verify the wl_surface resource is still valid before accessing it
  // The render callback is async, so the surface may have been destroyed
  if (!surface->resource) {
    // Surface was destroyed - remove image and return
    [self removeSurface:surface];
    return;
  }

  // SAFETY: Check user_data FIRST before calling wl_resource_get_client
  // This is safer because user_data access doesn't dereference as many internal
  // fields If the resource is destroyed, user_data will be NULL or point to
  // wrong object
  struct wl_surface_impl *surface_check =
      wl_resource_get_user_data(surface->resource);
  if (!surface_check || surface_check != surface) {
    // Resource was destroyed or reused - remove image and return
    surface->resource = NULL;
    [self removeSurface:surface];
    return;
  }

  // Now verify resource is still valid by checking if we can get the client
  // This prevents crashes when resource is destroyed but pointer isn't NULL yet
  // Use signal-safe approach: check user_data first, then client
  struct wl_client *client = wl_resource_get_client(surface->resource);
  if (!client) {
    // Resource is destroyed - remove image and return
    surface->resource = NULL;
    [self removeSurface:surface];
    return;
  }

  // Get compositor window bounds to clamp surface rendering
  // Use a large default size to avoid clamping issues for now
  CGRect compositorBounds = CGRectMake(0, 0, 4096, 4096);
  CGFloat maxWidth = compositorBounds.size.width;
  CGFloat maxHeight = compositorBounds.size.height;

  // Check if buffer is still attached (might have been detached between commit
  // and render)
  if (!surface->buffer_resource) {
    // No buffer - remove image but keep surface entry
    NSNumber *key =
        [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    SurfaceImage *surfaceImage = self.surfaceImages[key];
    if (surfaceImage) {
      surfaceImage.image = NULL; // Clear image but keep entry
    }
    if (self.compositorView) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      [self.compositorView setNeedsDisplay];
#else
      [self.compositorView setNeedsDisplay:YES];
#endif
    }
    return;
  }

  // Verify buffer resource is still valid before accessing it
  // SAFETY: Check user_data FIRST before calling wl_resource_get_client
  void *buffer_user_data = wl_resource_get_user_data(surface->buffer_resource);
  if (!buffer_user_data) {
    // Buffer resource was destroyed - clear image and return
    surface->buffer_resource = NULL;
    surface->buffer_release_sent = true;
    NSNumber *key =
        [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    SurfaceImage *surfaceImage = self.surfaceImages[key];
    if (surfaceImage) {
      surfaceImage.image = NULL;
    }
    if (self.compositorView) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      [self.compositorView setNeedsDisplay];
#else
      [self.compositorView setNeedsDisplay:YES];
#endif
    }
    return;
  }

  // Now verify buffer resource client is still valid
  struct wl_client *buffer_client =
      wl_resource_get_client(surface->buffer_resource);
  if (!buffer_client) {
    // Buffer resource was destroyed - clear image and return
    surface->buffer_resource = NULL;
    surface->buffer_release_sent = true;
    NSNumber *key =
        [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    SurfaceImage *surfaceImage = self.surfaceImages[key];
    if (surfaceImage) {
      surfaceImage.image = NULL;
    }
    if (self.compositorView) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      [self.compositorView setNeedsDisplay];
#else
      [self.compositorView setNeedsDisplay:YES];
#endif
    }
    return;
  }

  // Try to get buffer info - first check if it's an SHM buffer, then check for
  // custom buffer_data
  struct buffer_data {
    void *data;
    int32_t offset;
    int32_t width;
    int32_t height;
    int32_t stride;
    uint32_t format;
  };

  int32_t width, height, stride;
  uint32_t format;
  void *data = NULL;
  struct wl_shm_buffer *shm_buffer =
      wl_shm_buffer_get(surface->buffer_resource);
  NSLog(@"[RENDERER] updateSurface called. Buffer resource: %p, shm_buffer: %p",
        surface->buffer_resource, shm_buffer);

  struct buffer_data *buf_data = NULL;
  struct metal_dmabuf_buffer *dmabuf_buffer = NULL;

  // First, try to handle as SHM buffer
  if (shm_buffer) {
    // Standard Wayland SHM buffer
    NSLog(@"[RENDERER] Found SHM buffer: %p, getting properties...",
          shm_buffer);
    width = wl_shm_buffer_get_width(shm_buffer);
    height = wl_shm_buffer_get_height(shm_buffer);
    stride = wl_shm_buffer_get_stride(shm_buffer);
    format = wl_shm_buffer_get_format(shm_buffer);
    NSLog(@"[RENDERER] SHM properties: %dx%d, stride: %d, format: 0x%x", width,
          height, stride, format);

    NSLog(@"[RENDERER] Beginning access...");
    wl_shm_buffer_begin_access(shm_buffer);
    NSLog(@"[RENDERER] Getting data...");
    data = wl_shm_buffer_get_data(shm_buffer);
    NSLog(@"[RENDERER] Got data: %p", data);
  } else {
    // Not an SHM buffer - might be EGL, dmabuf, or custom buffer
    buf_data = wl_resource_get_user_data(surface->buffer_resource);

    // Check for dmabuf buffer
    if (is_dmabuf_buffer(surface->buffer_resource)) {
      dmabuf_buffer = dmabuf_buffer_get(surface->buffer_resource);
      if (dmabuf_buffer && dmabuf_buffer->iosurface) {
        // Zero-copy path: Set IOSurface directly as layer contents
        // This is much more efficient than creating a CGImage
        // CALayer supports IOSurfaceRef as contents on macOS
        NSLog(@"[RENDERER] Using zero-copy path for dmabuf (size: %dx%d)",
              dmabuf_buffer->width, dmabuf_buffer->height);

        // Update logical surface dimensions using buffer scale
        int32_t scale = surface->buffer_scale > 0 ? surface->buffer_scale : 1;
        surface->width = dmabuf_buffer->width / scale;
        surface->height = dmabuf_buffer->height / scale;
        surface->buffer_width = dmabuf_buffer->width;
        surface->buffer_height = dmabuf_buffer->height;

        // Get or create surface image entry for tracking
        NSNumber *key =
            [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
        SurfaceImage *surfaceImage = self.surfaceImages[key];
        if (!surfaceImage) {
          surfaceImage = [[SurfaceImage alloc] init];
          surfaceImage.surface = surface;
          self.surfaceImages[key] = surfaceImage;
        }

        // Update frame dimensions using logical surface size
        struct wl_viewport_impl *vp_dest = wl_viewport_from_surface(surface);
        CGFloat destW = surface->width;
        CGFloat destH = surface->height;
        if (vp_dest && vp_dest->has_destination) {
          destW = vp_dest->dst_width;
          destH = vp_dest->dst_height;
        }
        CGFloat clampedWidth = (destW < maxWidth) ? destW : maxWidth;
        CGFloat clampedHeight = (destH < maxHeight) ? destH : maxHeight;
        surfaceImage.frame =
            CGRectMake(surface->x, surface->y, clampedWidth, clampedHeight);

        // Set IOSurface as layer contents
        CALayer *layer = self.compositorView.layer;
        if (layer) {
          [CATransaction begin];
          [CATransaction setDisableActions:YES];
          // CRITICAL: Update layer contents with new IOSurface
          // This handles resize properly by setting the new IOSurface
          layer.contents = (__bridge id)dmabuf_buffer->iosurface;
          // Update layer frame to match surface dimensions
          layer.frame = surfaceImage.frame;
          [CATransaction commit];
        }

        // Update cached buffer info to detect changes
        surfaceImage.lastWidth = dmabuf_buffer->width;
        surfaceImage.lastHeight = dmabuf_buffer->height;
        surfaceImage.lastFormat = dmabuf_buffer->format;

        // Trigger redraw
        if (self.compositorView) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
          [self.compositorView setNeedsDisplay];
#else
          [self.compositorView setNeedsDisplay:YES];
#endif
        }

        // Release buffer to client and request next frame
        if (!surface->buffer_release_sent) {
          struct wl_client *release_buffer_client =
              wl_resource_get_client(surface->buffer_resource);
          if (release_buffer_client) {
            wl_buffer_send_release(surface->buffer_resource);
            surface->buffer_release_sent = true;
          }
        }

        // Send frame callback if requested
        if (surface->frame_callback) {
          wl_callback_send_done(surface->frame_callback,
                                get_time_in_milliseconds());
          wl_resource_destroy(surface->frame_callback);
          surface->frame_callback = NULL;
        }
        return;
      }
    } else if (buf_data && buf_data->data) {
      // Custom buffer with buffer_data (from wayland_shm.c)
      width = buf_data->width;
      height = buf_data->height;
      stride = buf_data->stride;
      format = buf_data->format;
      data = (char *)buf_data->data + buf_data->offset;

      if ((uintptr_t)data < (uintptr_t)buf_data->data) {
        NSLog(@"[RENDERER] ❌ Invalid data pointer calculation");
        return;
      }
    } else {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
      // Neither SHM buffer nor custom buffer_data - check if it's an EGL buffer
      struct egl_buffer_handler *egl_handler =
          macos_compositor_get_egl_buffer_handler();

      if (egl_handler && egl_buffer_handler_is_egl_buffer(
                             egl_handler, surface->buffer_resource)) {
        // This is an EGL buffer - query its properties
        int32_t egl_width, egl_height;
        EGLint texture_format;

        if (egl_buffer_handler_query_buffer(
                egl_handler, surface->buffer_resource, &egl_width, &egl_height,
                &texture_format) == 0) {
          NSLog(@"[RENDERER] ✓ EGL buffer detected (size: %dx%d, format: %d)",
                egl_width, egl_height, texture_format);

          // For now, render a placeholder until we implement full EGL image
          // rendering
          // TODO: Use eglCreateImageKHR and render the actual EGL image content
          int32_t placeholder_width =
              egl_width > 0 ? egl_width
                            : (surface->width > 0 ? surface->width : 640);
          int32_t placeholder_height =
              egl_height > 0 ? egl_height
                             : (surface->height > 0 ? surface->height : 480);
          int32_t placeholder_stride = placeholder_width * 4; // 32-bit RGBA
          size_t placeholder_size = placeholder_stride * placeholder_height;

          // Create a colored placeholder to indicate EGL buffer (blue tint)
          void *placeholder_data = calloc(1, placeholder_size);
          if (placeholder_data) {
            // Fill with blue-tinted pixels to indicate EGL buffer
            uint32_t *pixels = (uint32_t *)placeholder_data;
            for (int i = 0; i < placeholder_width * placeholder_height; i++) {
              pixels[i] = 0xFF3333AA; // Blue-tinted (RGBA)
            }

            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGBitmapInfo bitmapInfo =
                kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedLast;

            // Use CFData to manage memory properly
            CFDataRef cfData =
                CFDataCreate(NULL, placeholder_data, placeholder_size);
            free(placeholder_data); // CFData made a copy

            if (!cfData) {
              CGColorSpaceRelease(colorSpace);
              return;
            }

            CGDataProviderRef provider = CGDataProviderCreateWithCFData(cfData);
            CFRelease(cfData); // Provider retains it

            CGImageRef placeholder_image =
                CGImageCreate(placeholder_width, placeholder_height, 8, 32,
                              placeholder_stride, colorSpace, bitmapInfo,
                              provider, NULL, NO, kCGRenderingIntentDefault);

            if (placeholder_image) {
              NSNumber *key = [NSNumber
                  numberWithUnsignedLongLong:(unsigned long long)surface];
              SurfaceImage *surfaceImage = self.surfaceImages[key];
              if (!surfaceImage) {
                surfaceImage = [[SurfaceImage alloc] init];
                surfaceImage.surface = surface;
                self.surfaceImages[key] = surfaceImage;
              }

              if (surfaceImage.image) {
                CGImageRelease(surfaceImage.image);
              }
              // Apply viewporter source cropping if present
              CGImageRef finalImage = placeholder_image;
              struct wl_viewport_impl *vp_crop =
                  wl_viewport_from_surface(surface);
              if (vp_crop && vp_crop->has_source) {
                CGRect srcRect =
                    CGRectMake(vp_crop->src_x, vp_crop->src_y,
                               vp_crop->src_width, vp_crop->src_height);
                CGImageRef cropped =
                    CGImageCreateWithImageInRect(placeholder_image, srcRect);
                if (cropped) {
                  CGImageRelease(finalImage);
                  finalImage = cropped;
                  placeholder_width = (int32_t)vp_crop->src_width;
                  placeholder_height = (int32_t)vp_crop->src_height;
                }
              }
              surfaceImage.image = CGImageRetain(finalImage);

              // Update surface dimensions
              surface->width = placeholder_width;
              surface->height = placeholder_height;
              surface->buffer_width = placeholder_width;
              surface->buffer_height = placeholder_height;

              // Apply viewporter destination sizing if present
              struct wl_viewport_impl *vp_dest =
                  wl_viewport_from_surface(surface);
              CGFloat destW = placeholder_width;
              CGFloat destH = placeholder_height;
              if (vp_dest && vp_dest->has_destination) {
                destW = vp_dest->dst_width;
                destH = vp_dest->dst_height;
              }
              CGFloat clampedWidth = (destW < maxWidth) ? destW : maxWidth;
              CGFloat clampedHeight = (destH < maxHeight) ? destH : maxHeight;
              surfaceImage.frame = CGRectMake(surface->x, surface->y,
                                              clampedWidth, clampedHeight);

              CGImageRelease(placeholder_image);
              CGDataProviderRelease(provider);
              CGColorSpaceRelease(colorSpace);

              // Send buffer release to client
              if (!surface->buffer_release_sent) {
                struct wl_client *release_buffer_client =
                    wl_resource_get_client(surface->buffer_resource);
                if (release_buffer_client) {
                  wl_buffer_send_release(surface->buffer_resource);
                  surface->buffer_release_sent = true;
                }
              }

              if (self.compositorView) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
                [self.compositorView setNeedsDisplay];
#else
                [self.compositorView setNeedsDisplay:YES];
#endif
              }
              return;
            }

            CGDataProviderRelease(provider);
            CGColorSpaceRelease(colorSpace);
          }
        } else {
          NSLog(@"[RENDERER] ⚠️ EGL buffer detected but query failed");
        }
      } else {
        // Not an EGL buffer - unknown buffer type
        NSLog(
            @"[RENDERER] ⚠️ Unknown buffer type (not SHM, not custom, not EGL)");
      }
#endif // !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

      // Fallback: send buffer release
      if (!surface->buffer_release_sent) {
        struct wl_client *release_buffer_client =
            wl_resource_get_client(surface->buffer_resource);
        if (release_buffer_client) {
          wl_buffer_send_release(surface->buffer_resource);
          surface->buffer_release_sent = true;
        }
      }
      return;
    }
  }

  // Verify we have valid data
  if (!data) {
    if (shm_buffer) {
      wl_shm_buffer_end_access(shm_buffer);
    }
    if (dmabuf_buffer && dmabuf_buffer->iosurface) {
      IOSurfaceUnlock(dmabuf_buffer->iosurface, kIOSurfaceLockReadOnly, NULL);
    }
    if (self.compositorView) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      [self.compositorView setNeedsDisplay];
#else
      [self.compositorView setNeedsDisplay:YES];
#endif
    }
    return;
  }

  // Ensure buffer dimensions are stored for reference, but don't overwrite
  // logical surface dimensions which were already handled in
  // wayland_compositor.c
  surface->buffer_width = width;
  surface->buffer_height = height;

  // Validate data pointer is in reasonable address range
  uintptr_t data_addr = (uintptr_t)data;
  if (data_addr < 0x1000 || data_addr > 0x7FFFFFFFFFFF) {
    if (shm_buffer) {
      wl_shm_buffer_end_access(shm_buffer);
    }
    if (dmabuf_buffer && dmabuf_buffer->iosurface) {
      IOSurfaceUnlock(dmabuf_buffer->iosurface, kIOSurfaceLockReadOnly, NULL);
    }
    return;
  }

  // CRITICAL: Always create a new CGImage from buffer data when renderSurface
  // is called This is because renderSurface is only called on surface commit,
  // which means there's NEW CONTENT in the buffer, even if the buffer pointer
  // is the same. Waypipe and other clients reuse buffers - same pointer,
  // different content! The optimization to reuse images was causing stale
  // content to be displayed.
  NSNumber *key =
      [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
  SurfaceImage *surfaceImage = self.surfaceImages[key];

  if (!surfaceImage) {
    surfaceImage = [[SurfaceImage alloc] init];
    surfaceImage.surface = surface;
    self.surfaceImages[key] = surfaceImage;
  }

  // Always create new CGImage from current buffer data
  // This ensures we always show the latest content, even if buffer pointer is
  // reused
  CGImageRef image = createCGImageFromData(data, width, height, stride, format);

  // End access if using standard SHM buffer (must be before using image)
  if (shm_buffer) {
    wl_shm_buffer_end_access(shm_buffer);
  }
  if (dmabuf_buffer && dmabuf_buffer->iosurface) {
    IOSurfaceUnlock(dmabuf_buffer->iosurface, kIOSurfaceLockReadOnly, NULL);
  }

  // Update image (apply viewporter source crop if present) and cache buffer
  // info
  if (surfaceImage.image) {
    CGImageRelease(surfaceImage.image);
  }
  CGImageRef finalImage = image;
  struct wl_viewport_impl *vp_crop = wl_viewport_from_surface(surface);
  if (image && vp_crop && vp_crop->has_source) {
    CGRect srcRect = CGRectMake(vp_crop->src_x, vp_crop->src_y,
                                vp_crop->src_width, vp_crop->src_height);
    CGImageRef cropped = CGImageCreateWithImageInRect(image, srcRect);
    if (cropped) {
      CGImageRelease(finalImage);
      finalImage = cropped;
      width = (int32_t)vp_crop->src_width;
      height = (int32_t)vp_crop->src_height;
    }
  }
  surfaceImage.image = finalImage ? CGImageRetain(finalImage) : NULL;
  surfaceImage.lastBufferData = data;
  surfaceImage.lastWidth = width;
  surfaceImage.lastHeight = height;
  surfaceImage.lastFormat = format;

  if (surfaceImage && surfaceImage.image) {

    // Apply viewporter destination sizing if present, then clamp to compositor
    // window bounds
    struct wl_viewport_impl *vp_dest = wl_viewport_from_surface(surface);
    CGFloat destW = surface->width;
    CGFloat destH = surface->height;
    if (vp_dest && vp_dest->has_destination) {
      destW = vp_dest->dst_width;
      destH = vp_dest->dst_height;
    }
    CGFloat clampedWidth = (destW < maxWidth) ? destW : maxWidth;
    CGFloat clampedHeight = (destH < maxHeight) ? destH : maxHeight;
    // Offset the drawing based on xdg_surface geometry to align logical window
    // content with the macOS window.
    // ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE = 1
    int32_t offsetX = 0;
    int32_t offsetY = 0;
    extern struct xdg_toplevel_impl *xdg_surface_get_toplevel_from_wl_surface(
        struct wl_surface_impl * wl_surface);
    struct xdg_toplevel_impl *toplevel =
        xdg_surface_get_toplevel_from_wl_surface(surface);
    if (toplevel && toplevel->decoration_mode != 1 && toplevel->xdg_surface &&
        toplevel->xdg_surface->has_geometry) {
      // If client is doing CSD (mode 1), we don't offset here because the
      // NSWindow is already sized to the full surface (including shadows).
      // For SSD, we offset so the logical window starts at 0,0
      offsetX = -toplevel->xdg_surface->geometry_x;
      offsetY = -toplevel->xdg_surface->geometry_y;
    }

    CGRect newFrame = CGRectMake(surface->x + offsetX, surface->y + offsetY,
                                 clampedWidth, clampedHeight);

    // Only update frame if it changed (optimization)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (!CGRectEqualToRect(surfaceImage.frame, newFrame)) {
#else
    if (!NSEqualRects(surfaceImage.frame, newFrame)) {
#endif
      surfaceImage.frame = newFrame;
    }

    // Release our reference if we created a new image (SurfaceImage retains it)
    if (image) {
      CGImageRelease(image);
    }

    // Trigger redraw - force immediate display update
    if (self.compositorView &&
        [self.compositorView respondsToSelector:@selector(setNeedsDisplay:)]) {
      [self.compositorView setNeedsDisplay:YES];
    }
  } else {
    NSLog(@"[RENDER] Failed to create CGImage from buffer data: width=%d, "
          @"height=%d, stride=%d, format=0x%x",
          width, height, stride, format);
  }

  // Release the buffer for this frame if we haven't already
  // We do this REGARDLESS of whether image creation succeeded, so we don't hold
  // onto buffers forever
  if (surface->buffer_resource && !surface->buffer_release_sent) {
    // CRITICAL: Verify the buffer resource is still valid before sending
    // release If the client disconnected or buffer was destroyed, this could
    // crash
    struct wl_client *release_buffer_client =
        wl_resource_get_client(surface->buffer_resource);
    if (release_buffer_client) {
      // Buffer resource is still valid - safe to send release
      // For SHM buffers, we must always send release to let client reuse it
      // We don't check user_data here because standard SHM buffers might have
      // opaque user data or we might not have set it ourselves, but the
      // protocol requires release.
      wl_buffer_send_release(surface->buffer_resource);
      NSLog(@"[RENDERER] Released buffer %p", surface->buffer_resource);
    } else {
      // Buffer resource was destroyed (client disconnected) - just mark as
      // released
      NSLog(@"[RENDER] Buffer already destroyed (client disconnected) - "
            @"skipping release");
    }
    surface->buffer_release_sent = true;
  }
}

- (void)removeSurface:(struct wl_surface_impl *)surface {
  if (!surface)
    return;

  NSNumber *key =
      [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
  SurfaceImage *surfaceImage = self.surfaceImages[key];
  if (surfaceImage) {
    // Clear image but keep entry if surface still exists (buffer detached)
    // Only remove entry completely if surface is being destroyed (resource is
    // NULL)
    if (!surface->resource) {
      // Surface is being destroyed - remove entry completely
      [self.surfaceImages removeObjectForKey:key];
    } else {
      // Surface still exists, just clearing image (buffer detached)
      surfaceImage.image = NULL;
    }
    if (self.compositorView) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      [self.compositorView setNeedsDisplay];
#else
      [self.compositorView setNeedsDisplay:YES];
#endif
    }
  }
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)drawSurfacesInRect:(CGRect)dirtyRect {
#else
- (void)drawSurfacesInRect:(NSRect)dirtyRect {
#endif
  // Draw all surfaces using CoreGraphics (like OWL compositor)
  // This is called from CompositorView's drawRect: method

  if (!self.compositorView) {
    return;
  }

  // Draw background
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [[UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0] setFill];
  UIRectFill(dirtyRect);

  // Get graphics context
  CGContextRef cgContext = UIGraphicsGetCurrentContext();
#else
  [[NSColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0] setFill];
  NSRectFill(dirtyRect);

  // Get graphics context
  NSGraphicsContext *context = [NSGraphicsContext currentContext];
  if (!context) {
    return;
  }

  CGContextRef cgContext = [context CGContext];
#endif
  if (!cgContext) {
    return;
  }

  // Draw all surfaces that belong to this window
  for (SurfaceImage *surfaceImage in [self.surfaceImages allValues]) {
    if (!surfaceImage.image || !surfaceImage.surface) {
      NSLog(@"[DRAW] Skipping surface image: %p (image: %p, surface: %p)",
            surfaceImage, surfaceImage.image, surfaceImage.surface);
      continue;
    }

    // Filter: only draw surfaces that belong to this renderer/window
    if (![self surfaceBelongsToThisWindow:surfaceImage.surface]) {
      NSLog(@"[DRAW] Surface %p does not belong to window %p",
            surfaceImage.surface, self.window);
      continue;
    }
    CGRect frame = surfaceImage.frame;
    NSLog(@"[DRAW] Drawing surface %p in rect: %@", surfaceImage.surface,
          NSStringFromRect(frame));

    // Only draw if frame intersects dirty rect
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (!CGRectIntersectsRect(frame, dirtyRect)) {
#else
    if (!NSIntersectsRect(frame, dirtyRect)) {
#endif
      continue;
    }

    // Save graphics state
    CGContextSaveGState(cgContext);

    // CompositorView.isFlipped returns YES, so view coordinates use top-left
    // origin (like Wayland) Wayland buffers have Y=0 at top, which matches our
    // flipped view coordinate system However, CGContextDrawImage expects
    // bottom-left origin and will flip images vertically We need to flip the Y
    // coordinate to compensate

    // Calculate drawing rectangle in view coordinates (top-left origin)
    CGRect drawRect = CGRectMake(frame.origin.x, frame.origin.y,
                                 frame.size.width, frame.size.height);

    // CGContextDrawImage flips images vertically (expects bottom-left origin)
    // To compensate: translate to bottom of image, flip Y axis, then draw
    // This ensures Wayland's top-left origin image displays correctly
    CGContextTranslateCTM(cgContext, drawRect.origin.x,
                          drawRect.origin.y + drawRect.size.height);
    CGContextScaleCTM(cgContext, 1.0, -1.0);

    // Draw image at origin (0,0) after transformation
    CGRect imageRect =
        CGRectMake(0, 0, drawRect.size.width, drawRect.size.height);
    CGContextDrawImage(cgContext, imageRect, surfaceImage.image);

    // Restore graphics state
    CGContextRestoreGState(cgContext);
  }
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)setNeedsDisplay {
  if (self.compositorView) {
    [self.compositorView setNeedsDisplay];
  }
}
#else
- (void)setNeedsDisplay {
  if (self.compositorView) {
    [self.compositorView setNeedsDisplay:YES];
  }
}
#endif

@end
