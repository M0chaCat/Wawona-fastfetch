#import "WawonaCompositor.h"
#include "WawonaSettings.h"
#ifdef __APPLE__
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import "WawonaPreferencesManager.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <libproc.h>
#endif
#endif
#include "logging.h"
#include "wayland_fullscreen_shell.h"
#include "wayland_linux_dmabuf.h"
#include <arpa/inet.h>
#include <assert.h>
#ifdef __APPLE__
#include <dispatch/dispatch.h>
#endif
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <wayland-server.h>
// --- Forward Declarations ---

static struct wl_surface_impl *g_surface_list = NULL;
static struct wl_compositor_impl *g_compositor = NULL;

#ifdef __APPLE__
static WawonaCompositor *g_compositor_instance;
#else
struct WawonaCompositor {
    struct wl_display *display;
    int tcp_listen_fd;
    int connectedClientCount;
    // Add other fields as needed
};
static struct WawonaCompositor *g_compositor_instance;
#endif

// Timer callback to check for TCP connections
static int tcp_accept_timer_handler(void *data) {
#ifdef __APPLE__
  WawonaCompositor *compositor = (__bridge WawonaCompositor *)data;
  int listen_fd = compositor.tcp_listen_fd;
#else
  WawonaCompositor *compositor = (WawonaCompositor *)data;
  int listen_fd = compositor->tcp_listen_fd;
#endif

  if (!compositor || listen_fd < 0) {
    return 0; // Stop timer
  }

  // Accept all pending connections (non-blocking socket, so this won't block)
  // Accept multiple connections per timer tick to handle connection bursts
  int accepted_count = 0;
  const int max_accept_per_tick = 10; // Limit to avoid blocking the event loop

  // Use select() to check if socket has pending connections (non-blocking)
  fd_set read_fds;
  FD_ZERO(&read_fds);
  FD_SET(listen_fd, &read_fds);
  struct timeval timeout = {0, 0}; // Non-blocking check
  int ret =
      select(listen_fd + 1, &read_fds, NULL, NULL, &timeout);

  if (ret < 0) {
    // Select error
    static int logged_select_error = 0;
    if (!logged_select_error) {
      log_printf("[COMPOSITOR] ", "⚠️ TCP select() failed: %s\n",
                 strerror(errno));
      logged_select_error = 1;
    }
    return 50; // Continue timer
  }

  if (ret == 0) {
    // No pending connections
    return 50; // Continue timer
  }

  // Socket has pending connections, accept them
  for (int i = 0; i < max_accept_per_tick; i++) {
    // Check again if socket is still readable
    FD_ZERO(&read_fds);
    FD_SET(listen_fd, &read_fds);
    timeout.tv_sec = 0;
    timeout.tv_usec = 0;
    ret = select(listen_fd + 1, &read_fds, NULL, NULL, &timeout);

    if (ret <= 0 || !FD_ISSET(listen_fd, &read_fds)) {
      // No more pending connections
      break;
    }

    // Accept one connection
    struct sockaddr_in client_addr;
    socklen_t client_len = sizeof(client_addr);
    int client_fd = accept(listen_fd,
                           (struct sockaddr *)&client_addr, &client_len);

    if (client_fd >= 0) {
      int flags = fcntl(client_fd, F_GETFL, 0);
      if (flags >= 0) {
        fcntl(client_fd, F_SETFL, flags | O_NONBLOCK);
      }
      BOOL allowMultiple = WawonaSettings_GetMultipleClientsEnabled();
#ifdef __APPLE__
      if (!allowMultiple && g_compositor_instance &&
          g_compositor_instance.connectedClientCount > 0) {
#else
      if (!allowMultiple && g_compositor_instance &&
          g_compositor_instance->connectedClientCount > 0) {
#endif
        log_printf("[COMPOSITOR] ",
                   "🚫 TCP client rejected: multiple clients disabled\n");
        close(client_fd);
        continue;
      }
#ifdef __APPLE__
      struct wl_client *client =
          wl_client_create(compositor.display, client_fd);
#else
      struct wl_client *client =
          wl_client_create(compositor->display, client_fd);
#endif
      if (!client) {
        log_printf("[COMPOSITOR] ",
                   "⚠️ Failed to create Wayland client for TCP connection "
                   "(fd=%d): %s\n",
                   client_fd, strerror(errno));
        close(client_fd);
      } else {
        accepted_count++;
        log_printf("[COMPOSITOR] ",
                   "✅ Accepted TCP connection (fd=%d from %s:%d), created "
                   "Wayland client %p\n",
                   client_fd, inet_ntoa(client_addr.sin_addr),
                   ntohs(client_addr.sin_port), client);
      }
    } else {
      // Accept error
      int err = errno;
      if (err == EAGAIN || err == EWOULDBLOCK || err == EINTR) {
        // No more connections available right now
        break;
      } else {
        // Real error
        static int logged_accept_error = 0;
        if (!logged_accept_error || err != EINVAL) {
          log_printf("[COMPOSITOR] ", "⚠️ TCP accept() failed: %s (errno=%d)\n",
                     strerror(err), err);
          if (err == EINVAL) {
            logged_accept_error = 1;
          }
        }
        break;
      }
    }
  }

  if (accepted_count > 0) {
    log_printf("[COMPOSITOR] ", "✅ Accepted %d TCP connection(s) this tick\n",
               accepted_count);
  }

  // Reschedule timer for 50ms
  return 50;
}

static void surface_destroy_resource(struct wl_resource *resource);
static void region_destroy_resource(struct wl_resource *resource);

// --- Region Implementation ---

struct wl_region_impl {
  struct wl_resource *resource;
};

static void region_destroy(struct wl_client *client,
                           struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void region_add(struct wl_client *client, struct wl_resource *resource,
                       int32_t x, int32_t y, int32_t width, int32_t height) {
  (void)client;
  (void)resource;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
}

static void region_subtract(struct wl_client *client,
                            struct wl_resource *resource, int32_t x, int32_t y,
                            int32_t width, int32_t height) {
  (void)client;
  (void)resource;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
}

static const struct wl_region_interface region_interface = {
    region_destroy, region_add, region_subtract};

static void region_destroy_resource(struct wl_resource *resource) {
  struct wl_region_impl *region = wl_resource_get_user_data(resource);
  free(region);
}

static void compositor_destroy_bound_resource(struct wl_resource *resource) {
  (void)resource;
  macos_compositor_handle_client_disconnect();
}

// --- Surface Implementation ---

static void surface_destroy(struct wl_client *client,
                            struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void surface_attach(struct wl_client *client,
                           struct wl_resource *resource,
                           struct wl_resource *buffer, int32_t x, int32_t y) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  // CRITICAL: Release old buffer if a new one is being attached
  // This is required by Wayland protocol - when a new buffer is attached,
  // the old one must be released (unless it's NULL, which means detach)
  if (surface->buffer_resource && surface->buffer_resource != buffer && !surface->buffer_release_sent) {
    struct wl_client *old_buffer_client = wl_resource_get_client(surface->buffer_resource);
    if (old_buffer_client) {
      wl_buffer_send_release(surface->buffer_resource);
      surface->buffer_release_sent = true;
    }
  }

  // Pending state update
  surface->buffer_resource = buffer;
  // Reset release sent flag for the new buffer (or re-attached buffer)
  // If buffer is NULL (detach), keep the flag as-is
  if (buffer) {
    surface->buffer_release_sent = false;
  }
  surface->x = x;
  surface->y = y;
}

static void surface_damage(struct wl_client *client,
                           struct wl_resource *resource, int32_t x, int32_t y,
                           int32_t width, int32_t height) {
  (void)client;
  (void)resource;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
}

static void surface_frame(struct wl_client *client,
                          struct wl_resource *resource, uint32_t callback) {
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  struct wl_resource *callback_resource =
      wl_resource_create(client, &wl_callback_interface, 1, callback);
  if (!callback_resource) {
    wl_resource_post_no_memory(resource);
    return;
  }

  // Store callback to be fired on next frame
  // Simple implementation: replace existing (should be a list)
  // For now, we just keep one.
  // Ideally, we should append to a list.
  // Given the header structure: struct wl_resource *frame_callback;
  // It seems it only stores one? Or maybe it's a list head?
  // Let's assume it's a single callback for now or I should change header to
  // support list. But header is fixed.

  if (surface->frame_callback) {
    wl_resource_destroy(surface->frame_callback);
  }
  surface->frame_callback = callback_resource;

  // Notify compositor to ensure frame callback timer is running
  if (g_compositor && g_compositor->frame_callback_requested) {
    g_compositor->frame_callback_requested();
  }
}

static void surface_set_opaque_region(struct wl_client *client,
                                      struct wl_resource *resource,
                                      struct wl_resource *region_resource) {
  (void)client;
  (void)resource;
  (void)region_resource;
}

static void surface_set_input_region(struct wl_client *client,
                                     struct wl_resource *resource,
                                     struct wl_resource *region_resource) {
  (void)client;
  (void)resource;
  (void)region_resource;
}

static void surface_commit(struct wl_client *client,
                           struct wl_resource *resource) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  surface->committed = true;

  // Update buffer dimensions if we have a buffer
  if (surface->buffer_resource) {
    // Query buffer details if shm
    struct wl_shm_buffer *shm_buffer =
        wl_shm_buffer_get(surface->buffer_resource);
    if (shm_buffer) {
      surface->buffer_width = wl_shm_buffer_get_width(shm_buffer);
      surface->buffer_height = wl_shm_buffer_get_height(shm_buffer);
      surface->width = surface->buffer_width;
      surface->height = surface->buffer_height;
    } else {
      // Check for dmabuf buffer first (before EGL)
      // This is critical for waypipe which uses dmabuf buffers
      if (is_dmabuf_buffer(surface->buffer_resource)) {
        struct metal_dmabuf_buffer *dmabuf_buffer = dmabuf_buffer_get(surface->buffer_resource);
        if (dmabuf_buffer) {
          // Update surface dimensions from dmabuf buffer
          surface->buffer_width = dmabuf_buffer->width;
          surface->buffer_height = dmabuf_buffer->height;
          surface->width = dmabuf_buffer->width;
          surface->height = dmabuf_buffer->height;
        }
      }
      // EGL or other buffer. Width/height should be known or queried via EGL.
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
      else {
        struct egl_buffer_handler *egl_handler =
            macos_compositor_get_egl_buffer_handler();
        if (egl_handler) {
          int32_t width, height;
          EGLint format;
          if (egl_buffer_handler_query_buffer(egl_handler,
                                              surface->buffer_resource, &width,
                                              &height, &format) == 0) {
            surface->buffer_width = width;
            surface->buffer_height = height;
            surface->width = width;
            surface->height = height;
          }
        }
      }
#endif
    }
  }

  // Notify compositor to render
  if (g_compositor && g_compositor->render_callback) {
    g_compositor->render_callback(surface);
  }
}

static void surface_set_buffer_transform(struct wl_client *client,
                                         struct wl_resource *resource,
                                         int32_t transform) {
  (void)client;
  (void)resource;
  (void)transform;
}

static void surface_set_buffer_scale(struct wl_client *client,
                                     struct wl_resource *resource,
                                     int32_t scale) {
  (void)client;
  (void)resource;
  (void)scale;
}

static void surface_damage_buffer(struct wl_client *client,
                                  struct wl_resource *resource, int32_t x,
                                  int32_t y, int32_t width, int32_t height) {
  (void)client;
  (void)resource;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
}

static const struct wl_surface_interface surface_interface = {
    surface_destroy,
    surface_attach,
    surface_damage,
    surface_frame,
    surface_set_opaque_region,
    surface_set_input_region,
    surface_commit,
    surface_set_buffer_transform,
    surface_set_buffer_scale,
    surface_damage_buffer};

static void surface_destroy_resource(struct wl_resource *resource) {
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  // CRITICAL: Notify renderer to remove this surface before we free it
  // This prevents Use-After-Free crashes in the renderer loop
  remove_surface_from_renderer(surface);

  // Remove from global list
  if (g_surface_list == surface) {
    g_surface_list = surface->next;
  } else {
    struct wl_surface_impl *prev = g_surface_list;
    while (prev && prev->next != surface) {
      prev = prev->next;
    }
    if (prev) {
      prev->next = surface->next;
    }
  }

  free(surface);
}

// --- Compositor Implementation ---

static void compositor_create_surface(struct wl_client *client,
                                      struct wl_resource *resource,
                                      uint32_t id) {
  (void)client;
  (void)resource;
  (void)id;

  struct wl_surface_impl *surface = calloc(1, sizeof(struct wl_surface_impl));
  if (!surface) {
    wl_resource_post_no_memory(resource);
    return;
  }

  surface->resource = wl_resource_create(client, &wl_surface_interface,
                                         wl_resource_get_version(resource), id);
  if (!surface->resource) {
    free(surface);
    wl_resource_post_no_memory(resource);
    return;
  }

  wl_resource_set_implementation(surface->resource, &surface_interface, surface,
                                 surface_destroy_resource);

  // Add to global list
  surface->next = g_surface_list;
  g_surface_list = surface;
}

static void compositor_create_region(struct wl_client *client,
                                     struct wl_resource *resource,
                                     uint32_t id) {
  struct wl_region_impl *region = calloc(1, sizeof(struct wl_region_impl));
  if (!region) {
    wl_resource_post_no_memory(resource);
    return;
  }

  region->resource = wl_resource_create(client, &wl_region_interface,
                                        wl_resource_get_version(resource), id);
  if (!region->resource) {
    free(region);
    wl_resource_post_no_memory(resource);
    return;
  }

  wl_resource_set_implementation(region->resource, &region_interface, region,
                                 region_destroy_resource);
}

static const struct wl_compositor_interface compositor_interface = {
    compositor_create_surface, compositor_create_region};

static void compositor_bind(struct wl_client *client, void *data,
                            uint32_t version, uint32_t id) {
  struct wl_compositor_impl *compositor = data;
  BOOL allowMultiple = NO;
#ifdef __APPLE__
  @try {
    WawonaPreferencesManager *prefsManager = [WawonaPreferencesManager sharedManager];
    if (prefsManager) {
      allowMultiple = [prefsManager multipleClientsEnabled];
    }
  } @catch (NSException *exception) {
    NSLog(@"⚠️ Failed to read multipleClientsEnabled preference: %@", exception);
    allowMultiple = NO;
  }
  if (!allowMultiple && g_compositor_instance &&
      g_compositor_instance.connectedClientCount > 0) {
#else
  allowMultiple = WawonaSettings_GetMultipleClientsEnabled();
  if (!allowMultiple && g_compositor_instance &&
      g_compositor_instance->connectedClientCount > 0) {
#endif
    NSLog(
        @"🚫 Additional client connection rejected: multiple clients disabled");
    wl_client_destroy(client);
    return;
  }
  struct wl_resource *resource =
      wl_resource_create(client, &wl_compositor_interface, version, id);
  if (!resource) {
    wl_client_post_no_memory(client);
    return;
  }
  wl_resource_set_implementation(resource, &compositor_interface, compositor,
                                 compositor_destroy_bound_resource);
  macos_compositor_handle_client_connect();
}

// --- Public API ---

struct wl_compositor_impl *wl_compositor_create(struct wl_display *display) {
  struct wl_compositor_impl *compositor =
      calloc(1, sizeof(struct wl_compositor_impl));
  if (!compositor)
    return NULL;

  compositor->display = display;
  compositor->global = wl_global_create(display, &wl_compositor_interface, 4,
                                        compositor, compositor_bind);

  if (!compositor->global) {
    free(compositor);
    return NULL;
  }

  g_compositor = compositor;
  return compositor;
}

void wl_compositor_destroy(struct wl_compositor_impl *compositor) {
  if (!compositor)
    return;
  if (g_compositor == compositor)
    g_compositor = NULL;
  wl_global_destroy(compositor->global);
  free(compositor);
}

void wl_compositor_set_render_callback(struct wl_compositor_impl *compositor,
                                       wl_surface_render_callback_t callback) {
  if (compositor)
    compositor->render_callback = callback;
}

void wl_compositor_set_title_update_callback(
    struct wl_compositor_impl *compositor,
    wl_title_update_callback_t callback) {
  if (compositor)
    compositor->update_title_callback = callback;
}

void wl_compositor_set_frame_callback_requested(
    struct wl_compositor_impl *compositor,
    wl_frame_callback_requested_t callback) {
  if (compositor)
    compositor->frame_callback_requested = callback;
}

void wl_compositor_set_seat(struct wl_seat_impl *seat) { (void)seat; }

void wl_compositor_for_each_surface(wl_surface_iterator_func_t iterator,
                                    void *data) {
  struct wl_surface_impl *s = g_surface_list;
  while (s) {
    iterator(s, data);
    s = s->next;
  }
}

void wl_compositor_lock_surfaces(void) {
  // TODO: Mutex
}

void wl_compositor_unlock_surfaces(void) {
  // TODO: Mutex
}

struct wl_surface_impl *wl_surface_from_resource(struct wl_resource *resource) {
  if (wl_resource_instance_of(resource, &wl_surface_interface,
                              &surface_interface)) {
    return wl_resource_get_user_data(resource);
  }
  return NULL;
}

void wl_surface_damage(struct wl_surface_impl *surface, int32_t x, int32_t y,
                       int32_t width, int32_t height) {
  (void)surface;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
  // Internal damage
}

void wl_surface_commit(struct wl_surface_impl *surface) {
  // Internal commit
  surface->committed = true;
}

void wl_surface_attach_buffer(struct wl_surface_impl *surface,
                              struct wl_resource *buffer) {
  surface->buffer_resource = buffer;
}

void *wl_buffer_get_shm_data(struct wl_resource *buffer, int32_t *width,
                             int32_t *height, int32_t *stride) {
  struct wl_shm_buffer *shm_buffer = wl_shm_buffer_get(buffer);
  if (!shm_buffer)
    return NULL;

  if (width)
    *width = wl_shm_buffer_get_width(shm_buffer);
  if (height)
    *height = wl_shm_buffer_get_height(shm_buffer);
  if (stride)
    *stride = wl_shm_buffer_get_stride(shm_buffer);

  wl_shm_buffer_begin_access(shm_buffer);
  return wl_shm_buffer_get_data(shm_buffer);
}

void wl_buffer_end_shm_access(struct wl_resource *buffer) {
  struct wl_shm_buffer *shm_buffer = wl_shm_buffer_get(buffer);
  if (shm_buffer) {
    wl_shm_buffer_end_access(shm_buffer);
  }
}

struct wl_surface_impl *wl_get_all_surfaces(void) { return g_surface_list; }

// Update compositor_create_surface to use g_surface_list
// Re-implementing parts of compositor_create_surface here to ensure correct
// linking (Code above was simplified)
#include "metal_waypipe.h"
#include "wayland_drm.h"
#include "wayland_gtk_shell.h"
#include "wayland_idle_inhibit.h"
#include "wayland_idle_manager.h"
#include "wayland_keyboard_shortcuts.h"
#include "wayland_linux_dmabuf.h"
#include "wayland_plasma_shell.h"
#include "wayland_pointer_constraints.h"
#include "wayland_pointer_gestures.h"
#include "wayland_primary_selection.h"
#include "wayland_protocol_stubs.h"
#include "wayland_qt_extensions.h"
#include "wayland_relative_pointer.h"
#include "wayland_screencopy.h"
#include "wayland_shell.h"
#include "wayland_tablet.h"
#include "wayland_viewporter.h"
#include "xdg-shell-protocol.h"

#include "metal_renderer.h"
#include "surface_renderer.h"
#import <MetalKit/MetalKit.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#include "metal_renderer.h"
// iOS: Use UIView instead of NSView
@interface CompositorView : UIView
@property(nonatomic, assign) InputHandler *inputHandler;
@property(nonatomic, strong) id<RenderingBackend> renderer;
@property(nonatomic, strong) MTKView *metalView;
@property(nonatomic, weak) WawonaCompositor *compositor;
@end

@implementation CompositorView
- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    // Ensure background is transparent so window's black background shows
    // through in unsafe areas
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;

    // Listen for settings changes
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(defaultsChanged:)
               name:NSUserDefaultsDidChangeNotification
             object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)defaultsChanged:(NSNotification *)note {
  // Trigger layout update when settings change
  [self setNeedsLayout];
}

- (void)safeAreaInsetsDidChange {
  [super safeAreaInsetsDidChange];
  [self setNeedsLayout];
  if (self.compositor) {
    // Force update when safe area changes (e.g. startup, rotation)
    [self.compositor updateOutputSize:self.bounds.size];
  }
}

- (void)layoutSubviews {
  [super layoutSubviews];

  BOOL respectSafeArea =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"RespectSafeArea"];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"RespectSafeArea"] ==
      nil) {
    respectSafeArea = YES;
  }

  if (respectSafeArea) {
    // Respect Safe Area: manually constrain frame
    CGRect targetFrame = self.superview.bounds;
    if (self.window) {
      UIEdgeInsets insets = self.window.safeAreaInsets;
      if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
          insets.right != 0) {
        targetFrame = UIEdgeInsetsInsetRect(self.superview.bounds, insets);
      }
    } else {
      // Fallback if window not available
      UIEdgeInsets insets = self.safeAreaInsets;
      if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
          insets.right != 0) {
        targetFrame = UIEdgeInsetsInsetRect(self.superview.bounds, insets);
      }
    }

    if (!CGRectEqualToRect(self.frame, targetFrame)) {
      self.autoresizingMask = UIViewAutoresizingNone;
      self.frame = targetFrame;
      NSLog(
          @"🔵 CompositorView constrained to safe area: (%.0f, %.0f) %.0fx%.0f",
          targetFrame.origin.x, targetFrame.origin.y, targetFrame.size.width,
          targetFrame.size.height);
    }
  } else {
    // Full Screen: match superview
    CGRect targetFrame = self.superview.bounds;
    if (!CGRectEqualToRect(self.frame, targetFrame)) {
      self.frame = targetFrame;
      self.autoresizingMask =
          UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      NSLog(
          @"🔵 CompositorView expanded to full screen: (%.0f, %.0f) %.0fx%.0f",
          targetFrame.origin.x, targetFrame.origin.y, targetFrame.size.width,
          targetFrame.size.height);
    } else if (self.autoresizingMask != (UIViewAutoresizingFlexibleWidth |
                                         UIViewAutoresizingFlexibleHeight)) {
      self.autoresizingMask =
          UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
  }

  if (self.compositor) {
    [self.compositor updateOutputSize:self.bounds.size];
  }
}

- (void)drawRect:(CGRect)rect {
  if (self.metalView && self.metalView.superview == self) {
    return;
  }
  if (self.renderer) {
    [self.renderer drawSurfacesInRect:rect];
  } else {
    [[UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0] setFill];
    UIRectFill(rect);
  }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleTouchEvent:event];
  }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleTouchEvent:event];
  }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleTouchEvent:event];
  }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event {
  if (self.inputHandler) {
    [self.inputHandler handleTouchEvent:event];
  }
}

@end
#else
// macOS: Use NSView
@interface CompositorView : NSView
@property(nonatomic, assign)
    InputHandler *inputHandler; // assign for MRC compatibility
@property(nonatomic, assign)
    SurfaceRenderer *renderer; // assign for MRC compatibility
@property(nonatomic, strong)
    MTKView *metalView; // Metal view for full compositor rendering
@end

@implementation CompositorView
- (BOOL)isFlipped {
  return YES;
}

- (BOOL)mouseDownCanMoveWindow {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)becomeFirstResponder {
  NSLog(@"[COMPOSITOR VIEW] Became first responder - ready for keyboard input");
  BOOL result = [super becomeFirstResponder];
  // Send keyboard enter to focused surface when view becomes first responder
  if (result && self.inputHandler && self.inputHandler.seat) {
    struct wl_surface_impl *surface = wl_get_all_surfaces();
    // Find the first valid surface
    while (surface && (!surface->resource || !self.inputHandler.seat->keyboard_resource)) {
      surface = surface->next;
    }
    if (surface && surface->resource && self.inputHandler.seat->keyboard_resource) {
      uint32_t serial = wl_seat_get_serial(self.inputHandler.seat);
      struct wl_array keys;
      wl_array_init(&keys);
      wl_seat_send_keyboard_enter(self.inputHandler.seat, surface->resource, serial, &keys);
      wl_array_release(&keys);
      wl_seat_send_keyboard_modifiers(self.inputHandler.seat, serial);
    }
  }
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
#endif

// Static reference to compositor instance for C callback
static WawonaCompositor *g_compositor_instance = NULL;

// Forward declarations
static int send_frame_callbacks_timer(void *data);
__attribute__((unused)) static void send_frame_callbacks_timer_idle(void *data);
static BOOL ensure_frame_callback_timer_on_event_thread(
    WawonaCompositor *compositor, uint32_t delay_ms, const char *reason);
static void ensure_frame_callback_timer_idle(void *data);
static void trigger_first_frame_callback_idle(void *data);

// C function for frame callback requested callback
// Called from event thread when a client requests a frame callback
static void wawona_compositor_frame_callback_requested(void) {
  if (!g_compositor_instance)
    return;

  // This runs on the event thread - safe to create timer directly
  if (g_compositor_instance.display) {
    BOOL timer_was_missing =
        (g_compositor_instance.frame_callback_source == NULL);

    // Ensure timer exists - if it was missing, create it with delay 1ms to fire
    // almost immediately Using 1ms instead of 0ms because Wayland timers might
    // not fire with delay=0 Otherwise, if timer already exists, don't modify it
    // (let it fire at its scheduled time) This prevents infinite loops where
    // sending callbacks triggers immediate requests
    if (timer_was_missing) {
      log_printf("[COMPOSITOR] ", "wawona_compositor_frame_callback_requested: "
                                  "Creating timer (first frame request)\n");
      // Create timer with 16ms delay for continuous operation
      if (!ensure_frame_callback_timer_on_event_thread(
              g_compositor_instance, 16, "first frame request")) {
        log_printf("[COMPOSITOR] ", "wawona_compositor_frame_callback_"
                                    "requested: Failed to create timer\n");
      } else {
        log_printf("[COMPOSITOR] ",
                   "wawona_compositor_frame_callback_requested: Timer created "
                   "successfully. Scheduling immediate fire via idle.\n");
        // Use idle callback to trigger first frame callback immediately
        // This avoids waiting 16ms for the first frame and ensures start-up is
        // snappy
        struct wl_event_loop *eventLoop =
            wl_display_get_event_loop(g_compositor_instance.display);
        wl_event_loop_add_idle(eventLoop, trigger_first_frame_callback_idle,
                               (__bridge void *)g_compositor_instance);
      }
    }
    // If timer already exists, do nothing - it will fire at its scheduled
    // interval
  }
}

// C function to update window title when focus changes
void wawona_compositor_update_title(struct wl_client *client) {
  if (g_compositor_instance) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [g_compositor_instance updateWindowTitleForClient:client];
    });
  }
}

// C function to detect full compositors and switch to Metal backend
// OPTIMIZED: Only switch to Metal for actual nested compositors, not proxies
// like waypipe
void wawona_compositor_detect_full_compositor(struct wl_client *client) {
  if (!g_compositor_instance) {
    NSLog(@"⚠️ g_compositor_instance is NULL, cannot detect compositor");
    return;
  }

  // Try to get PID for detection
  pid_t client_pid = 0;
  uid_t client_uid = 0;
  gid_t client_gid = 0;
  wl_client_get_credentials(client, &client_pid, &client_uid, &client_gid);

  BOOL shouldSwitchToMetal = NO;
  NSString *processName = nil;

  // Check backend preference
  // 0 = Automatic (default)
  // 1 = Metal (Vulkan)
  // 2 = Cocoa (Surface)
  NSInteger backendPref =
      [[NSUserDefaults standardUserDefaults] integerForKey:@"RenderingBackend"];

  if (backendPref == 1) {
    // Force Metal
    shouldSwitchToMetal = YES;
    NSLog(@"ℹ️ Rendering Backend preference set to Metal (Vulkan) - forcing "
          @"switch");
  } else if (backendPref == 2) {
    // Force Cocoa
    shouldSwitchToMetal = NO;
    NSLog(@"ℹ️ Rendering Backend preference set to Cocoa (Surface) - preventing "
          @"switch");
  } else {
    // Automatic mode (existing logic)
    if (client_pid > 0) {
      // Check process name to determine if this is a nested compositor
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
      char proc_path[PROC_PIDPATHINFO_MAXSIZE] = {0};
      int ret = proc_pidpath(client_pid, proc_path, sizeof(proc_path));
      if (ret > 0) {
        NSString *processPath = [NSString stringWithUTF8String:proc_path];
#else
      // iOS: Process name detection not available
      NSString *processPath = nil;
      if (0) {
#endif
        processName = [processPath lastPathComponent];
        NSLog(@"🔍 Client binding to wl_compositor: %@ (PID: %d)", processName,
              client_pid);

        // Known nested compositors that should use Metal backend
        // Includes: Weston, wlroots-based (Sway, River, Hyprland), GNOME
        // (Mutter), KDE (KWin)
        NSArray<NSString *> *nestedCompositors = @[
          @"weston", @"weston-desktop-shell", @"mutter", @"gnome-shell",
          @"gnome-session", @"kwin_wayland", @"kwin", @"plasmashell", @"sway",
          @"river", @"hyprland", @"niri", @"cage", @"wayfire", @"hikari",
          @"orbital"
        ];

        NSString *lowercaseName = [processName lowercaseString];
        for (NSString *compositor in nestedCompositors) {
          if ([lowercaseName containsString:compositor]) {
            shouldSwitchToMetal = YES;
            NSLog(@"✅ Detected nested compositor: %@ - switching to Metal "
                  @"backend",
                  processName);
            break;
          }
        }

        // waypipe is a proxy/tunnel, NOT a compositor - don't switch backend
        if ([lowercaseName containsString:@"waypipe"]) {
          shouldSwitchToMetal = NO;
          NSLog(@"ℹ️ Detected waypipe proxy - keeping Cocoa backend for regular "
                @"clients");
        }
      }
    } else {
      // PID unavailable - likely forwarded through waypipe or similar proxy
      // On iOS, we assume this is a forwarded session (Weston/etc) and use
      // Metal for performance
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      NSLog(@"🔍 Client PID unavailable (likely forwarded through waypipe) - "
            @"switching to Metal backend on iOS");
      shouldSwitchToMetal = YES;
#else
      // On macOS, waypipe might be individual windows, so keep Cocoa
      NSLog(@"🔍 Client PID unavailable (likely forwarded through waypipe) - "
            @"keeping Cocoa backend");
      shouldSwitchToMetal = NO;
#endif
    }
  }

  // Only switch to Metal if we detected an actual nested compositor or forced
  // via prefs
  if (shouldSwitchToMetal) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [g_compositor_instance switchToMetalBackend];
    });
  } else {
    NSLog(@"ℹ️ Client binding to wl_compositor but not a nested compositor - "
          @"using Cocoa backend");
  }

  // Update window title with client name (regardless of backend)
  dispatch_async(dispatch_get_main_queue(), ^{
    [g_compositor_instance updateWindowTitleForClient:client];
  });
}

// Forward declaration
static void renderSurfaceImmediate(struct wl_surface_impl *surface);

// C wrapper function for render callback
static void render_surface_callback(struct wl_surface_impl *surface) {
  if (!surface)
    return;

  // CRITICAL: Validate surface is still valid before dispatching async render
  // The surface may be destroyed between commit and async render execution
  if (!surface->resource)
    return;

  // SAFETY: Check user_data FIRST before calling wl_resource_get_client
  // This is safer because user_data access doesn't dereference as many internal
  // fields
  struct wl_surface_impl *surface_check =
      wl_resource_get_user_data(surface->resource);
  if (!surface_check || surface_check != surface)
    return;

  // Now verify resource is still valid by checking if we can get the client
  struct wl_client *client = wl_resource_get_client(surface->resource);
  if (!client)
    return;

  if (g_compositor_instance && g_compositor_instance.renderingBackend) {
    // CRITICAL: Render SYNCHRONOUSLY on main thread for immediate updates
    // Wayland compositors MUST repaint immediately when clients commit buffers
    // Async dispatch causes race conditions and delays that break nested
    // compositors
    if ([NSThread isMainThread]) {
      renderSurfaceImmediate(surface);
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        renderSurfaceImmediate(surface);
      });
    }
  }
}

// Helper function to render surface immediately on main thread
static void renderSurfaceImmediate(struct wl_surface_impl *surface) {
  if (!g_compositor_instance || !surface)
    return;

  // Check if window needs to be shown and sized for first client
  if (!g_compositor_instance.windowShown && surface->buffer_resource) {
    // Get buffer size to size window appropriately
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
      [g_compositor_instance showAndSizeWindowForFirstClient:buf_data->width
                                                      height:buf_data->height];
    }
  }

  // Render surface immediately
  if ([g_compositor_instance.renderingBackend
          respondsToSelector:@selector(renderSurface:)]) {
    [g_compositor_instance.renderingBackend renderSurface:surface];
  }

  // CRITICAL: Trigger IMMEDIATE redraw after rendering surface
  // This ensures nested compositors (like Weston) see updates immediately
  // Wayland spec requires compositors to repaint immediately on surface commit
  if ([g_compositor_instance.renderingBackend
          respondsToSelector:@selector(setNeedsDisplay)]) {
    [g_compositor_instance.renderingBackend setNeedsDisplay];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  } else if (g_compositor_instance.window &&
             g_compositor_instance.window.rootViewController.view) {
    // iOS: Fallback for Cocoa backend
    dispatch_async(dispatch_get_main_queue(), ^{
      [g_compositor_instance.window.rootViewController.view setNeedsDisplay];
    });
#else
  } else if (g_compositor_instance.window &&
             g_compositor_instance.window.contentView) {
    // macOS: Fallback for Cocoa backend - force immediate redraw
    dispatch_async(dispatch_get_main_queue(), ^{
      NSView *contentView = g_compositor_instance.window.contentView;
      [contentView setNeedsDisplay:YES];
      // Force immediate display update
      [contentView displayIfNeeded];
    });
#endif
  }
}

// C wrapper function to remove surface (for cleanup)
void remove_surface_from_renderer(struct wl_surface_impl *surface) {
  if (!g_compositor_instance) {
    return;
  }

  // CRITICAL: Use dispatch_sync to ensure surface is removed from renderer
  // BEFORE the surface struct is freed by the caller (surface_destroy).
  // Using dispatch_async causes a race condition where the block runs after
  // the surface is freed, leading to Use-After-Free crashes.
  if ([NSThread isMainThread]) {
    // Remove from renderer if active
    if (g_compositor_instance.renderingBackend &&
        [g_compositor_instance.renderingBackend
            respondsToSelector:@selector(removeSurface:)]) {
      [g_compositor_instance.renderingBackend removeSurface:surface];
    }
  } else {
    dispatch_sync(dispatch_get_main_queue(), ^{
      // Remove from renderer if active
      if (g_compositor_instance.renderingBackend &&
          [g_compositor_instance.renderingBackend
              respondsToSelector:@selector(removeSurface:)]) {
        [g_compositor_instance.renderingBackend removeSurface:surface];
      }
    });
  }
}

// C function to check if window should be hidden after client disconnects
// Called from client_destroy_listener after removing all surfaces
void macos_compositor_check_and_hide_window_if_needed(void) {
  if (!g_compositor_instance) {
    return;
  }

  // Check if there are any remaining surfaces
  // We need to check the surfaces list from wayland_compositor.c
  // Since we can't directly access it, we'll use a callback mechanism
  // For now, we'll check if the window is shown and hide it
  // The actual surface count check will be done in client_destroy_listener
#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_compositor_instance.windowShown && g_compositor_instance.window) {
      NSLog(@"[WINDOW] All clients disconnected - hiding window");
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      g_compositor_instance.window.hidden = YES;
#else
            [g_compositor_instance.window orderOut:nil];
#endif
      g_compositor_instance.windowShown = NO;
    }
  });
#else
  // Android specific implementation if needed
#endif
}

@implementation WawonaCompositor

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithDisplay:(struct wl_display *)display
                         window:(UIWindow *)window {
#else
- (instancetype)initWithDisplay:(struct wl_display *)display
                         window:(NSWindow *)window {
#endif
  self = [super init];
  if (self) {
    _display = display;
    _window = window;
    _eventLoop = wl_display_get_event_loop(display);
    _shouldStopEventThread = NO;
    _frame_callback_source = NULL;
    _pending_resize_width = 0;
    _pending_resize_height = 0;
    _needs_resize_configure = NO;
    _windowShown =
        NO; // Track if window has been shown (delayed until first client)
    _isFullscreen = NO; // Track if window is in fullscreen mode
    _fullscreenExitTimer =
        nil; // Timer to exit fullscreen after client disconnects
    _connectedClientCount = 0; // Track number of connected clients

    // Create custom view that accepts first responder and handles drawing
    CompositorView *compositorView;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // On iOS, check if window already has a rootViewController (set in main.m)
    // If it does, use that view; otherwise create a new one
    UIView *containerView = nil;
    if (window.rootViewController && window.rootViewController.view) {
        // Use existing root view controller's view
        containerView = window.rootViewController.view;
        // Ensure it fills the window properly
        containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // Force layout to ensure bounds are correct
        [containerView setNeedsLayout];
        [containerView layoutIfNeeded];
        NSLog(@"✅ Using existing root view controller for compositor view (bounds=%@)",
              NSStringFromCGRect(containerView.bounds));
    } else {
        // Create new root view controller (fallback)
        UIViewController *rootVC = [[UIViewController alloc] init];
        // Don't manually set frame - let UIKit handle it with proper autoresizing
        containerView = rootVC.view;
        containerView.backgroundColor =
            [UIColor blackColor]; // Black background for unsafe areas
        // Ensure the view properly fills the window using autoresizing masks
        containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        window.rootViewController = rootVC;
        // Force layout to ensure bounds are correct
        [containerView setNeedsLayout];
        [containerView layoutIfNeeded];
        NSLog(@"✅ Created new root view controller for compositor view (bounds=%@)",
              NSStringFromCGRect(containerView.bounds));
    }

    // Create CompositorView as a subview with flexible sizing (full screen by
    // default) Layout will be handled in CompositorView's layoutSubviews to
    // respect safe area setting
    // Use window bounds instead of containerView.bounds since containerView might
    // not be laid out yet (bounds could be CGRectZero or incorrect)
    CGRect initialFrame = window.bounds;
    compositorView =
        [[CompositorView alloc] initWithFrame:initialFrame];
    compositorView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    compositorView.backgroundColor = [UIColor clearColor];
    [containerView addSubview:compositorView];
    
    NSLog(@"🔵 CompositorView initialized: window.bounds=%@, compositorView.frame=%@",
          NSStringFromCGRect(window.bounds), NSStringFromCGRect(compositorView.frame));

    // Note: Safe area constraints are now handled dynamically in CompositorView
    // layoutSubviews

#else
    NSRect contentRect = NSMakeRect(0, 0, 800, 600);
    compositorView = [[CompositorView alloc] initWithFrame:contentRect];
    [window setContentView:compositorView];
    [window setDelegate:self];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidEnterFullScreen:)
               name:NSWindowDidEnterFullScreenNotification
             object:window];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidExitFullScreen:)
               name:NSWindowDidExitFullScreenNotification
             object:window];
    [window setAcceptsMouseMovedEvents:YES];
    [window setCollectionBehavior:NSWindowCollectionBehaviorDefault];
    [window setStyleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskMiniaturizable)];
    [window makeFirstResponder:compositorView];
#endif

    // Create surface renderer with NSView (like OWL compositor)
    // Start with Cocoa renderer, will switch to Metal if full compositor
    // detected
    SurfaceRenderer *renderer =
        [[SurfaceRenderer alloc] initWithCompositorView:compositorView];
    _renderingBackend = renderer;
    _backendType = 0; // RENDERING_BACKEND_COCOA

    // Set renderer reference in view for drawRect: calls
    compositorView.renderer = renderer;

    // Store global reference for C callbacks (MUST be set before clients
    // connect)
    g_compositor_instance = self;
    NSLog(@"   Global compositor instance set for client detection: %p",
          (__bridge void *)self);

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    NSLog(@"🚀 iOS Wayland Compositor initialized");
#else
    NSLog(@"🚀 macOS Wayland Compositor initialized");
    NSLog(@"   Window: %@", window.title);
#endif
    NSLog(@"   Display: %p", (void *)display);
    NSLog(@"   Initial backend: Cocoa (will auto-switch to Metal for full "
          @"compositors)");
  }
  return self;
}

// Implementation of wayland frame callback functions
int wl_send_frame_callbacks(void) {
  if (!g_compositor_instance || !g_surface_list) {
    return 0;
  }

  int count = 0;
  struct wl_surface_impl *surface = g_surface_list;
  while (surface) {
    if (surface->frame_callback) {
      // Get current time in milliseconds (wayland time is in milliseconds since
      // epoch)
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC, &ts);
      uint32_t time = (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);

      // Send frame callback done event
      wl_callback_send_done(surface->frame_callback, time);
      wl_resource_destroy(surface->frame_callback);
      surface->frame_callback = NULL;
      count++;
    }
    surface = surface->next;
  }
  return count;
}

bool wl_has_pending_frame_callbacks(void) {
  if (!g_surface_list) {
    return false;
  }

  struct wl_surface_impl *surface = g_surface_list;
  while (surface) {
    if (surface->frame_callback) {
      return true;
    }
    surface = surface->next;
  }
  return false;
}

- (void)setupInputHandling {
  if (_seat && _window) {
    _inputHandler = [[InputHandler alloc] initWithSeat:_seat
                                                window:_window
                                            compositor:self];
    [_inputHandler setupInputHandling];

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Set input handler reference in compositor view
    UIView *contentView = _window.rootViewController.view;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      ((CompositorView *)contentView).inputHandler = _inputHandler;
    }
    // iOS: Touch events are handled via UIKit gesture recognizers
    // Keyboard events are handled via UIResponder chain
#else
    // macOS: Set input handler reference in compositor view for keyboard event
    // handling
    NSView *contentView = _window.contentView;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      CompositorView *compositorView = (CompositorView *)contentView;
      compositorView.inputHandler = _inputHandler;
    }

    // Mouse events are now handled via NSResponder methods in CompositorView
    // (mouseMoved, mouseDown, etc.) which forward to inputHandler
    // We still set acceptsMouseMovedEvents on the window
    [_window setAcceptsMouseMovedEvents:YES];

    NSLog(@"   ✓ Input handling set up (macOS)");
#endif
  }
}

- (BOOL)start {
  init_compositor_logging();
  NSLog(@"✅ Starting compositor backend...");
  log_printf("[COMPOSITOR] ", "Starting compositor backend...\n");

  // Create Wayland protocol implementations
  // These globals are advertised to clients and enable EGL platform extension
  // support Clients querying the registry will see wl_compositor, which allows
  // them to create EGL surfaces using eglCreatePlatformWindowSurfaceEXT with
  // Wayland surfaces
  _compositor = wl_compositor_create(_display);
  if (!_compositor) {
    NSLog(@"❌ Failed to create wl_compositor");
    return NO;
  }
  NSLog(@"   ✓ wl_compositor created (supports EGL platform extensions)");

  // Set up render callback for immediate rendering on commit
  g_compositor_instance = self;
  wl_compositor_set_render_callback(_compositor, render_surface_callback);

  // Set up title update callback to update window title when focus changes
  wl_compositor_set_title_update_callback(_compositor,
                                          wawona_compositor_update_title);

  // Set up frame callback requested callback to ensure timer is running
  wl_compositor_set_frame_callback_requested(
      _compositor, wawona_compositor_frame_callback_requested);

  // Get window size for output
  // CRITICAL: Use actual CompositorView bounds (already constrained to safe
  // area if respecting) This ensures proper scaling from the start
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGFloat scale = [UIScreen mainScreen].scale;
  if (scale <= 0) {
    scale = 1.0; // Fallback to 1x if scale is invalid
  }

  // Find CompositorView to get actual rendering area size
  UIView *containerView = _window.rootViewController.view;
  CompositorView *compositorView = nil;
  for (UIView *subview in containerView.subviews) {
    if ([subview isKindOfClass:[CompositorView class]]) {
      compositorView = (CompositorView *)subview;
      break;
    }
  }
  if (!compositorView && [containerView isKindOfClass:[CompositorView class]]) {
    compositorView = (CompositorView *)containerView;
  }

  CGRect frame;
  if (compositorView) {
    [compositorView setNeedsLayout];
    [compositorView layoutIfNeeded];
    frame = compositorView.bounds;
  } else {
    frame = _window.bounds;
  }
#else
  NSRect frame = [_window.contentView bounds];
  CGFloat scale = _window.backingScaleFactor;
  if (scale <= 0) {
    scale = 1.0;
  }
#endif

  // Calculate pixel dimensions: points * scale = pixels
  int32_t pixelWidth = (int32_t)round(frame.size.width * scale);
  int32_t pixelHeight = (int32_t)round(frame.size.height * scale);
  int32_t scaleInt = (int32_t)scale;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  _output =
      wl_output_create(_display, pixelWidth, pixelHeight, scaleInt, "iOS");
#else
  _output =
      wl_output_create(_display, pixelWidth, pixelHeight, scaleInt, "macOS");
#endif
  if (!_output) {
    NSLog(@"❌ Failed to create wl_output");
    return NO;
  }
  NSLog(
      @"   ✓ wl_output created: %.0fx%.0f points @ %.0fx scale = %dx%d pixels",
      frame.size.width, frame.size.height, scale, pixelWidth, pixelHeight);

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (compositorView) {
    [self updateOutputSize:compositorView.bounds.size];
  } else {
    [self updateOutputSize:frame.size];
  }
#else
  [self updateOutputSize:frame.size];
#endif

  _seat = wl_seat_create(_display);
  if (!_seat) {
    NSLog(@"❌ Failed to create wl_seat");
    return NO;
  }
  NSLog(@"   ✓ wl_seat created");

  // Set seat in compositor for focus management
  wl_compositor_set_seat(_seat);

  _shm = wl_shm_create(_display);
  if (!_shm) {
    NSLog(@"❌ Failed to create wl_shm");
    return NO;
  }
  NSLog(@"   ✓ wl_shm created");

  _subcompositor = wl_subcompositor_create(_display);
  if (!_subcompositor) {
    NSLog(@"❌ Failed to create wl_subcompositor");
    return NO;
  }
  NSLog(@"   ✓ wl_subcompositor created");

  _data_device_manager = wl_data_device_manager_create(_display);
  if (!_data_device_manager) {
    NSLog(@"❌ Failed to create wl_data_device_manager");
    return NO;
  }
  NSLog(@"   ✓ wl_data_device_manager created");

  _xdg_wm_base = xdg_wm_base_create(_display);
  if (!_xdg_wm_base) {
    NSLog(@"❌ Failed to create xdg_wm_base");
    return NO;
  }
  // Set initial output size
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGRect initialFrame = _window.bounds;
#else
  NSRect initialFrame = [_window.contentView bounds];
#endif
  xdg_wm_base_set_output_size(_xdg_wm_base, (int32_t)initialFrame.size.width,
                              (int32_t)initialFrame.size.height);
  NSLog(@"   ✓ xdg_wm_base created");

  // Create optional protocol implementations to satisfy client requirements
  // These are minimal stubs - full implementations can be added later

  // Primary selection protocol
  struct zwp_primary_selection_device_manager_v1_impl *primary_selection =
      zwp_primary_selection_device_manager_v1_create(_display);
  if (primary_selection) {
    NSLog(@"   ✓ Primary selection protocol created");
  }

  // Decoration manager protocol
  struct wl_decoration_manager_impl *decoration =
      wl_decoration_create(_display);
  if (decoration) {
    NSLog(@"   ✓ Decoration manager protocol created");
  }

  // Toplevel icon protocol
  struct wl_toplevel_icon_manager_impl *toplevel_icon =
      wl_toplevel_icon_create(_display);
  if (toplevel_icon) {
    NSLog(@"   ✓ Toplevel icon protocol created");
  }

  // XDG activation protocol
  struct wl_activation_manager_impl *activation =
      wl_activation_create(_display);
  if (activation) {
    NSLog(@"   ✓ XDG activation protocol created");
  }

  // Fractional scale protocol
  struct wl_fractional_scale_manager_impl *fractional_scale =
      wl_fractional_scale_create(_display);
  if (fractional_scale) {
    NSLog(@"   ✓ Fractional scale protocol created");
  }

  // Cursor shape protocol
  struct wl_cursor_shape_manager_impl *cursor_shape =
      wl_cursor_shape_create(_display);
  if (cursor_shape) {
    NSLog(@"   ✓ Cursor shape protocol created");
  }

  // Text input protocol v3
  struct wl_text_input_manager_impl *text_input =
      wl_text_input_create(_display);
  if (text_input && text_input->global) {
    self.text_input_manager = text_input; // Store to keep it alive
    NSLog(@"   ✓ Text input protocol v3 created (global=%p)",
          (void *)text_input->global);
  } else {
    NSLog(@"   ❌ Failed to create text input protocol v3");
    self.text_input_manager = NULL;
  }

  // Text input protocol v1 (for weston-editor compatibility)
  struct wl_text_input_manager_v1_impl *text_input_v1 =
      wl_text_input_v1_create(_display);
  if (text_input_v1 && text_input_v1->global) {
    NSLog(@"   ✓ Text input protocol v1 created (global=%p)",
          (void *)text_input_v1->global);
  } else {
    NSLog(@"   ❌ Failed to create text input protocol v1");
  }

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // EGL buffer handler (for rendering EGL/OpenGL ES buffers using
  // KosmicKrisp+Zink)
  struct egl_buffer_handler *egl_handler =
      calloc(1, sizeof(struct egl_buffer_handler));
  if (egl_handler) {
    if (egl_buffer_handler_init(egl_handler, _display) == 0) {
      self.egl_buffer_handler = egl_handler;
      NSLog(@"   ✓ EGL buffer handler initialized (KosmicKrisp+Zink)");
    } else {
      NSLog(@"   ⚠️ EGL buffer handler initialization failed (EGL may not be "
            @"available)");
      free(egl_handler);
      self.egl_buffer_handler = NULL;
    }
  } else {
    NSLog(@"   ❌ Failed to allocate EGL buffer handler");
    self.egl_buffer_handler = NULL;
  }
#endif

  // Viewporter protocol (critical for Weston compatibility)
  struct wp_viewporter_impl *viewporter = wp_viewporter_create(_display);
  if (viewporter) {
    NSLog(@"   ✓ Viewporter protocol created");
  }

  // Shell protocol (legacy compatibility)
  struct wl_shell_impl *shell = wl_shell_create(_display);
  if (shell) {
    NSLog(@"   ✓ Shell protocol created");
  }

  // Screencopy protocol (screen capture)
  struct zwlr_screencopy_manager_v1_impl *screencopy =
      zwlr_screencopy_manager_v1_create(_display);
  if (screencopy) {
    NSLog(@"   ✓ Screencopy protocol created");
  }

  // Linux DMA-BUF protocol (critical for wlroots and hardware-accelerated
  // clients) Check preference - this allows toggle between IOSurface-backed
  // dmabuf (enabled) and CPU-based H264 waypipe fallback (disabled)
  WawonaPreferencesManager *prefsManager =
      [WawonaPreferencesManager sharedManager];
  if ([prefsManager dmabufEnabled]) {
    struct zwp_linux_dmabuf_v1_impl *linux_dmabuf =
        zwp_linux_dmabuf_v1_create(_display);
    if (linux_dmabuf) {
      NSLog(@"   ✓ Linux DMA-BUF protocol created (IOSurface-backed, nearly "
            @"zero-copy)");
    }
  } else {
    NSLog(@"   ⊘ Linux DMA-BUF protocol disabled (using CPU-based H264 waypipe "
          @"fallback)");
  }

  // wl_drm protocol (for EGL fallback when dmabuf feedback doesn't provide
  // render node)
  struct wl_drm_impl *wl_drm = wl_drm_create(_display);
  if (wl_drm) {
    NSLog(@"   ✓ wl_drm protocol created (stub for macOS EGL compatibility)");
  }

  // Idle inhibit protocol (prevent screensaver)
  struct zwp_idle_inhibit_manager_v1_impl *idle_inhibit =
      zwp_idle_inhibit_manager_v1_create(_display);
  if (idle_inhibit) {
    NSLog(@"   ✓ Idle inhibit protocol created");
  }

  // Pointer gestures protocol (trackpad gestures)
  struct zwp_pointer_gestures_v1_impl *pointer_gestures =
      zwp_pointer_gestures_v1_create(_display);
  if (pointer_gestures) {
    NSLog(@"   ✓ Pointer gestures protocol created");
  }

  // Relative pointer protocol (relative motion for games)
  struct zwp_relative_pointer_manager_v1_impl *relative_pointer =
      zwp_relative_pointer_manager_v1_create(_display);
  if (relative_pointer) {
    NSLog(@"   ✓ Relative pointer protocol created");
  }

  // Pointer constraints protocol (pointer locking/confining for games)
  struct zwp_pointer_constraints_v1_impl *pointer_constraints =
      zwp_pointer_constraints_v1_create(_display);
  if (pointer_constraints) {
    NSLog(@"   ✓ Pointer constraints protocol created");
  }

  // Register additional protocols
  struct zwp_tablet_manager_v2_impl *tablet =
      zwp_tablet_manager_v2_create(_display);
  (void)tablet; // Suppress unused variable warning
  NSLog(@"   ✓ Tablet protocol created");

  struct ext_idle_notifier_v1_impl *idle_manager =
      ext_idle_notifier_v1_create(_display);
  (void)idle_manager; // Suppress unused variable warning
  NSLog(@"   ✓ Idle manager protocol created");

  struct zwp_keyboard_shortcuts_inhibit_manager_v1_impl *keyboard_shortcuts =
      zwp_keyboard_shortcuts_inhibit_manager_v1_create(_display);
  (void)keyboard_shortcuts; // Suppress unused variable warning
  NSLog(@"   ✓ Keyboard shortcuts inhibit protocol created");

  // CRITICAL: Initialize fullscreen shell BEFORE xdg_wm_base
  // Weston checks for arbitrary resolution support early, so fullscreen shell
  // must be available when it connects
  wayland_fullscreen_shell_init(_display);
  NSLog(@"   ✓ Fullscreen shell protocol created (for arbitrary resolution "
        @"support)");

  // GTK Shell protocol (for GTK applications)
  struct gtk_shell1_impl *gtk_shell = gtk_shell1_create(_display);
  if (gtk_shell) {
    NSLog(@"   ✓ GTK Shell protocol created");
  }

  // Plasma Shell protocol (for KDE applications)
  struct org_kde_plasma_shell_impl *plasma_shell =
      org_kde_plasma_shell_create(_display);
  (void)plasma_shell; // Suppress unused variable warning
  if (plasma_shell) {
    NSLog(@"   ✓ Plasma Shell protocol created");
  }

  // Presentation time protocol (for accurate presentation timing feedback)
  struct wp_presentation_impl *presentation = wp_presentation_create(_display);
  if (presentation) {
    NSLog(@"   ✓ Presentation time protocol created");
  }

  // Color management protocol (for color operations and HDR support)
  _color_manager = wp_color_manager_create(_display, _output);
  if (_color_manager) {
    NSLog(@"   ✓ Color management protocol created (HDR: %s)",
          _color_manager->hdr_supported ? "yes" : "no");
  } else {
    NSLog(@"   ✗ Color management protocol creation failed");
  }

  // Qt Wayland Extensions (for QtWayland applications)
  struct qt_surface_extension_impl *qt_surface =
      qt_surface_extension_create(_display);
  if (qt_surface) {
    NSLog(@"   ✓ Qt Surface Extension protocol created");
  }
  struct qt_windowmanager_impl *qt_wm = qt_windowmanager_create(_display);
  if (qt_wm) {
    NSLog(@"   ✓ Qt Window Manager protocol created");
  } else {
    NSLog(@"   ✗ Qt Window Manager protocol creation failed");
  }

  // Start dedicated Wayland event processing thread
  NSLog(@"   ✓ Starting Wayland event processing thread");
  _shouldStopEventThread = NO;
  __unsafe_unretained WawonaCompositor *unsafeSelf = self;
  _eventThread = [[NSThread alloc] initWithBlock:^{
    WawonaCompositor *compositor = unsafeSelf;
    if (!compositor)
      return;

    log_printf("[COMPOSITOR] ", "🚀 Wayland event thread started\n");

    // Set up proper error handling for client connections
    // wl_display_run() handles client connections internally
    // NOTE: You may see "failed to read client connection (pid 0)" errors from
    // libwayland-server. These are NORMAL and EXPECTED when:
    // - waypipe clients test/check the socket connection (happens during
    // colima-client startup)
    // - Clients connect then immediately disconnect to verify connectivity
    // - "pid 0" means PID unavailable (normal for waypipe forwarded
    // connections)
    // - These are transient connection attempts, not real errors
    // - libwayland-server handles them gracefully and continues accepting
    // connections
    // - The actual connection will succeed on retry
    // This error is printed by libwayland-server to stderr and cannot be
    // suppressed from our code.
    log_printf("[COMPOSITOR] ",
               "ℹ️  Note: Transient 'failed to read client connection' errors "
               "during client setup are normal and harmless\n");

    @try {
      // Use manual event loop instead of wl_display_run() to ensure timers fire
      // wl_display_run() blocks on file descriptors and may not process timers
      // reliably
      struct wl_event_loop *eventLoop =
          wl_display_get_event_loop(compositor.display);

      // Set up TCP accept() handling if we have a listening socket
      // Use a timer to periodically check for new connections
      struct wl_event_source *tcp_accept_timer = NULL;
      if (compositor.tcp_listen_fd >= 0) {
        // Create a timer that fires every 50ms to check for new TCP connections
        tcp_accept_timer = wl_event_loop_add_timer(
            eventLoop, tcp_accept_timer_handler, (__bridge void *)compositor);

        if (tcp_accept_timer) {
          // Start timer immediately (0ms) - it will reschedule itself via
          // return value
          int ret = wl_event_source_timer_update(tcp_accept_timer, 0);
          if (ret < 0) {
            log_printf("[COMPOSITOR] ",
                       "⚠️ Failed to start TCP accept() timer: %s\n",
                       strerror(errno));
            wl_event_source_remove(tcp_accept_timer);
            tcp_accept_timer = NULL;
          } else {
            log_printf("[COMPOSITOR] ",
                       "✅ TCP accept() timer registered and started "
                       "(listen_fd=%d, ret=%d)\n",
                       compositor.tcp_listen_fd, ret);
          }
        } else {
          log_printf("[COMPOSITOR] ",
                     "⚠️ Failed to register TCP accept() timer\n");
        }
      }

      while (!compositor.shouldStopEventThread) {
        // Manually check for TCP connections if timer isn't working
        // This ensures connections are accepted even if timer has issues
        if (compositor.tcp_listen_fd >= 0) {
          fd_set read_fds;
          FD_ZERO(&read_fds);
          FD_SET(compositor.tcp_listen_fd, &read_fds);
          struct timeval timeout = {0, 0}; // Non-blocking
          int select_ret = select(compositor.tcp_listen_fd + 1, &read_fds, NULL,
                                  NULL, &timeout);
          if (select_ret > 0 && FD_ISSET(compositor.tcp_listen_fd, &read_fds)) {
            // Call timer handler directly to accept connection
            tcp_accept_timer_handler((__bridge void *)compositor);
          }
        }

        // Dispatch events with a timeout to allow timers to fire
        // Use 16ms timeout (matches frame callback timer interval)
        int ret = wl_event_loop_dispatch(eventLoop, 16);
        if (ret < 0) {
          log_printf("[COMPOSITOR] ", "⚠️ Event loop dispatch failed: %d\n",
                     ret);
          break;
        }
        // Flush clients after each dispatch
        wl_display_flush_clients(compositor.display);
      }

      // Cleanup TCP accept timer
      if (tcp_accept_timer) {
        wl_event_source_remove(tcp_accept_timer);
      }
    } @catch (NSException *exception) {
      log_printf("[COMPOSITOR] ", "⚠️ Exception in Wayland event thread: %s\n",
                 [exception.reason UTF8String]);
    }

    log_printf("[COMPOSITOR] ", "🛑 Wayland event thread stopped\n");
  }];
  _eventThread.name = @"WaylandEventThread";
  [_eventThread start];

  // Set up frame rendering using CVDisplayLink/CADisplayLink - syncs to display
  // refresh rate This automatically matches the display's refresh rate (e.g.,
  // 60Hz, 120Hz, etc.)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CADisplayLink *displayLink =
      [CADisplayLink displayLinkWithTarget:self
                                  selector:@selector(displayLinkCallback:)];
  [displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                    forMode:NSDefaultRunLoopMode];
  _displayLink = displayLink;
  double refreshRate = displayLink.preferredFramesPerSecond > 0
                           ? (double)displayLink.preferredFramesPerSecond
                           : 60.0;
  NSLog(@"   Frame rendering active (%.0fHz - synced to display)", refreshRate);
#else
  CVDisplayLinkRef displayLink = NULL;
  CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);

  if (displayLink) {
    // Set callback to renderFrame
    CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback,
                                   (__bridge void *)self);
    // Start display link - it will continue running even when window loses
    // focus This ensures Wayland clients continue to receive frame callbacks
    // and can render
    CVDisplayLinkStart(displayLink);
    _displayLink = displayLink;

    // Get actual refresh rate for logging
    CVTime time = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink);
    double refreshRate = 60.0; // Default fallback
    if (!(time.flags & kCVTimeIsIndefinite) && time.timeValue != 0) {
      refreshRate = (double)time.timeScale / (double)time.timeValue;
    }
    NSLog(@"   Frame rendering active (%.0fHz - synced to display)",
          refreshRate);
  } else {
    // Fallback to 60Hz timer if CVDisplayLink fails
    NSTimer *fallbackTimer =
        [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                         target:self
                                       selector:@selector(renderFrame)
                                       userInfo:nil
                                        repeats:YES];
    (void)fallbackTimer; // Timer is retained by the run loop, no need to store
                         // reference
    _displayLink = NULL;
    NSLog(@"   Frame rendering active (60Hz - fallback timer)");
  }
#endif

  // Add a heartbeat timer to show compositor is alive (every 5 seconds)
  static int heartbeat_count = 0;
  [NSTimer
      scheduledTimerWithTimeInterval:5.0
                             repeats:YES
                               block:^(NSTimer *timer) {
                                 heartbeat_count++;
                                 log_printf(
                                     "[COMPOSITOR] ",
                                     "💓 Compositor heartbeat #%d - window "
                                     "visible, event thread running\n",
                                     heartbeat_count);
                                 // Stop after 12 heartbeats (1 minute) to
                                 // reduce log spam
                                 if (heartbeat_count >= 12) {
                                   [timer invalidate];
                                   log_printf("[COMPOSITOR] ",
                                              "💓 Heartbeat logging stopped "
                                              "(compositor still running)\n");
                                 }
                               }];

  // Set up input handling
  [self setupInputHandling];

  NSLog(@"✅ Compositor backend started");
  NSLog(@"   Wayland event processing thread active");
  NSLog(@"   Input handling active");

  return YES;
}

- (BOOL)processWaylandEvents {
  // DEPRECATED: Event processing is now handled by the dedicated event thread
  // This method is kept for compatibility but should not be used
  // The event thread handles all Wayland event processing with blocking
  // dispatch
  return NO;
}

// DisplayLink callback - called at display refresh rate
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)displayLinkCallback:(CADisplayLink *)displayLink {
  (void)displayLink;
  [self renderFrame];
}
#else
static CVReturn
displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow,
                    const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn,
                    CVOptionFlags *flagsOut, void *displayLinkContext) {
  (void)displayLink;
  (void)inNow;
  (void)inOutputTime;
  (void)flagsIn;
  (void)flagsOut;
  WawonaCompositor *compositor =
      (__bridge WawonaCompositor *)displayLinkContext;
  if (compositor) {
    // Render on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      [compositor renderFrame];
    });
  }
  return kCVReturnSuccess;
}
#endif

// Show and size window when first client connects
- (void)showAndSizeWindowForFirstClient:(int32_t)width height:(int32_t)height {
  if (_windowShown) {
    return; // Already shown
  }

  NSLog(@"[WINDOW] First client connected - showing window with size %dx%d",
        width, height);

  // Resize window to match client surface size
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: Window is always fullscreen, ignore client requested size
  // We will verify output size respects Safe Area at the end
#else
  // macOS: frameRectForContentRect automatically accounts for window frame
  // (titlebar, borders)
  NSRect contentRect = NSMakeRect(0, 0, width, height);
  NSRect windowFrame = [_window frameRectForContentRect:contentRect];

  // Center window on screen
  NSScreen *screen = [NSScreen mainScreen];
  NSRect screenFrame =
      screen ? screen.visibleFrame : NSMakeRect(0, 0, 1920, 1080);
  CGFloat x = screenFrame.origin.x +
              (screenFrame.size.width - windowFrame.size.width) / 2;
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: Ensure view matches window (respecting safe area if enabled)
  UIView *contentView = _window.rootViewController.view;

  // Check if we should respect safe area
  BOOL respectSafeArea =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"RespectSafeArea"];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"RespectSafeArea"] ==
      nil) {
    respectSafeArea = YES; // Default to YES
  }

  if (respectSafeArea && [contentView isKindOfClass:[CompositorView class]]) {
    CompositorView *compositorView = (CompositorView *)contentView;
    [compositorView setNeedsLayout];
    [compositorView layoutIfNeeded];

    // Calculate safe area frame
    CGRect windowBounds = _window.bounds;
    CGRect safeAreaFrame = windowBounds;

    if (@available(iOS 11.0, *)) {
      UILayoutGuide *safeArea = _window.safeAreaLayoutGuide;
      safeAreaFrame = safeArea.layoutFrame;
      if (CGRectIsEmpty(safeAreaFrame)) {
        UIEdgeInsets insets = compositorView.safeAreaInsets;
        if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
            insets.right != 0) {
          safeAreaFrame = UIEdgeInsetsInsetRect(windowBounds, insets);
        }
      }
    } else {
      UIEdgeInsets insets = compositorView.safeAreaInsets;
      if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
          insets.right != 0) {
        safeAreaFrame = UIEdgeInsetsInsetRect(windowBounds, insets);
      }
    }

    compositorView.frame = safeAreaFrame;
    compositorView.autoresizingMask = UIViewAutoresizingNone;
    NSLog(@"🔵 CompositorView frame set to safe area in "
          @"showAndSizeWindowForFirstClient: (%.0f, %.0f) %.0fx%.0f",
          safeAreaFrame.origin.x, safeAreaFrame.origin.y,
          safeAreaFrame.size.width, safeAreaFrame.size.height);
  } else {
    contentView.frame = _window.bounds;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      CompositorView *compositorView = (CompositorView *)contentView;
      compositorView.autoresizingMask =
          (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    }
  }
#else
  CGFloat y = screenFrame.origin.y +
              (screenFrame.size.height - windowFrame.size.height) / 2;
  windowFrame.origin = NSMakePoint(x, y);

  // Set window frame
  [_window setFrame:windowFrame
            display:YES]; // Use display:YES to ensure immediate update

  // CRITICAL: Ensure content view frame matches window content rect
  // The content view might have been initialized with a different size
  // (800x600)
  NSView *contentView = _window.contentView;
  NSRect contentViewFrame = [_window contentRectForFrameRect:windowFrame];
  contentViewFrame.origin =
      NSMakePoint(0, 0); // Content view origin is always (0,0)
  contentView.frame = contentViewFrame;
#endif
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  NSLog(@"[WINDOW] Content view resized to: %.0fx%.0f",
        contentViewFrame.size.width, contentViewFrame.size.height);
#endif

  // Ensure Metal view (if exists) matches window size before showing
  if ([contentView isKindOfClass:[CompositorView class]]) {
    CompositorView *compositorView = (CompositorView *)contentView;

    // If Metal view exists, ensure it matches the window content size
    if (_backendType == 1 && compositorView.metalView) {
      // Metal view frame should match content view bounds (in points)
      // CRITICAL: Do NOT manually set bounds - MTKView handles this
      // automatically Setting bounds manually interferes with MTKView's Retina
      // scaling logic
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      CGRect contentBounds = compositorView.bounds;
      compositorView.metalView.frame = contentBounds;
      [compositorView.metalView setNeedsDisplay];
#else
      NSRect contentBounds = compositorView.bounds;
      compositorView.metalView.frame = contentBounds;
      [compositorView.metalView setNeedsDisplay:YES];
#endif
      // MTKView automatically sets bounds to match frame - don't override!
      // The drawableSize will be automatically calculated based on frame size
      // and Retina scale
      NSLog(@"[WINDOW] Metal view sized to match window content: "
            @"frame=%.0fx%.0f (MTKView handles bounds/drawable automatically)",
            contentBounds.size.width, contentBounds.size.height);
    }
  }

  // Update output size (respecting Safe Area on iOS)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // Use the actual contentView size (which may be safe area if respecting)
  UIView *contentViewForSize = _window.rootViewController.view;
  [self updateOutputSize:contentViewForSize.bounds.size];
#else
  [self updateOutputSize:_window.contentView.bounds.size];
#endif

  if (_xdg_wm_base) {
    xdg_wm_base_set_output_size(_xdg_wm_base, width, height);
  }

  // Show window and make it key
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  _window.hidden = NO;
  [_window makeKeyWindow];
#else
  [_window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [_window becomeKeyWindow];
  
  // Make the compositor view first responder to receive keyboard events
  // (contentView already declared above)
  if ([contentView isKindOfClass:[CompositorView class]]) {
    [_window makeFirstResponder:contentView];
    NSLog(@"[INPUT] View set as first responder when window shown");
  }
#endif

  _windowShown = YES;

  NSLog(@"[WINDOW] Window shown and sized to %dx%d", width, height);
}

// Update output size and notify clients
- (void)updateOutputSize:(CGSize)size {
  CompositorView *compositorView = nil;
  CGRect outputRect;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *containerView = _window.rootViewController.view;
  for (UIView *subview in containerView.subviews) {
    if ([subview isKindOfClass:[CompositorView class]]) {
      compositorView = (CompositorView *)subview;
      break;
    }
  }
  if (!compositorView && [containerView isKindOfClass:[CompositorView class]]) {
    compositorView = (CompositorView *)containerView;
  }
  if (compositorView) {
    [compositorView setNeedsLayout];
    [compositorView layoutIfNeeded];
    outputRect = compositorView.bounds;
  } else {
    outputRect = CGRectMake(0, 0, size.width, size.height);
  }
#else
  NSView *contentView = _window.contentView;
  if ([contentView isKindOfClass:[CompositorView class]]) {
    compositorView = (CompositorView *)contentView;
    outputRect = compositorView.bounds;
  } else {
    outputRect = CGRectMake(0, 0, size.width, size.height);
  }
#endif

  // Convert points to pixels for Retina displays
  // CRITICAL: Use the screen's actual scale factor for proper DPI/Retina
  // scaling
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGFloat scale = [UIScreen mainScreen].scale;
  if (scale <= 0) {
    scale = 1.0;
  }
#else
  CGFloat scale = _window.backingScaleFactor;
  if (scale <= 0) {
    scale = 1.0;
  }
#endif

  // Calculate pixel dimensions: points * scale = pixels
  // Example: 375 points * 3 scale = 1125 pixels (iPhone 14 Pro)
  int32_t pixelWidth = (int32_t)round(outputRect.size.width * scale);
  int32_t pixelHeight = (int32_t)round(outputRect.size.height * scale);
  int32_t scaleInt = (int32_t)scale;

  NSLog(@"🔵 Output scaling: %.0fx%.0f points @ %.0fx scale = %dx%d pixels",
        outputRect.size.width, outputRect.size.height, scale, pixelWidth,
        pixelHeight);

  // Store for resize handling on event thread to avoid race conditions
  _pending_resize_width = pixelWidth;
  _pending_resize_height = pixelHeight;
  _pending_resize_scale = scaleInt;
  _needs_resize_configure = YES;
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// NSWindowDelegate method - called when window close button (X) is clicked
- (BOOL)windowShouldClose:(NSWindow *)sender {
  (void)sender;

  NSLog(
      @"[WINDOW] Window close button clicked - sending close event to client");

  // Use compositor's seat to find the focused surface
  struct wl_seat_impl *seat_ref = _seat;
  if (!seat_ref || !seat_ref->focused_surface) {
    NSLog(@"[WINDOW] No focused surface - closing window");
    return YES; // Allow window to close
  }

  // Get the focused surface
  struct wl_surface_impl *focused_surface =
      (struct wl_surface_impl *)seat_ref->focused_surface;
  if (!focused_surface || !focused_surface->resource) {
    NSLog(@"[WINDOW] Focused surface is invalid - closing window");
    return YES; // Allow window to close
  }

  // Find the toplevel associated with this surface
  extern struct xdg_toplevel_impl *xdg_surface_get_toplevel_from_wl_surface(
      struct wl_surface_impl * wl_surface);
  struct xdg_toplevel_impl *toplevel =
      xdg_surface_get_toplevel_from_wl_surface(focused_surface);

  if (!toplevel || !toplevel->resource) {
    NSLog(@"[WINDOW] No toplevel found for focused surface - closing window");
    return YES; // Allow window to close
  }

  // Verify the toplevel resource is still valid
  struct wl_client *client = wl_resource_get_client(toplevel->resource);
  if (!client || wl_resource_get_user_data(toplevel->resource) == NULL) {
    NSLog(@"[WINDOW] Toplevel resource is invalid - closing window");
    return YES; // Allow window to close
  }

  // Send close event to the client
  NSLog(@"[WINDOW] Sending close event to client (toplevel=%p, client=%p)",
        (void *)toplevel, (void *)client);

  // Use the xdg_toplevel_send_close function from xdg-shell-protocol.h
  // This sends the XDG_TOPLEVEL_CLOSE event to the client
  wl_resource_post_event(toplevel->resource, XDG_TOPLEVEL_CLOSE);

  // Flush the client connection to ensure the close event is sent
  wl_display_flush_clients(_display);

  // Disconnect the client after a short delay to allow it to handle the close
  // event This gives well-behaved clients a chance to clean up gracefully Store
  // the client pointer in a local variable for the block
  struct wl_client *client_to_disconnect = client;
  struct wl_resource *toplevel_resource = toplevel->resource;

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        // Check if client is still connected by verifying the toplevel resource
        // still belongs to it
        if (client_to_disconnect && toplevel_resource) {
          struct wl_client *current_client =
              wl_resource_get_client(toplevel_resource);
          if (current_client == client_to_disconnect) {
            // Client is still connected - disconnect it
            NSLog(@"[WINDOW] Client did not close gracefully - disconnecting");
            wl_client_destroy(client_to_disconnect);
          }
        }
      });

  // Don't close the window immediately - let the client handle the close event
  // The window will be closed when the client disconnects
  return NO; // Prevent window from closing immediately
}
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// NSWindowDelegate method - called when window becomes key
- (void)windowDidBecomeKey:(NSNotification *)notification {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  (void)notification;
  NSLog(@"[WINDOW] Window became key - accepting keyboard input");

  // Ensure compositor view is first responder when window becomes key
  NSView *contentView = _window.contentView;
  if ([contentView isKindOfClass:[CompositorView class]] &&
      _window.firstResponder != contentView) {
    [_window makeFirstResponder:contentView];
  }
#else
  (void)notification;
#endif
}

// NSWindowDelegate method - called when window enters fullscreen
- (void)windowDidEnterFullScreen:(NSNotification *)notification {
  (void)notification;
  _isFullscreen = YES;
  NSLog(@"[FULLSCREEN] Window entered fullscreen");
}

// NSWindowDelegate method - called when window exits fullscreen
- (void)windowDidExitFullScreen:(NSNotification *)notification {
  (void)notification;
  _isFullscreen = NO;

  // Cancel any pending exit timer
  if (_fullscreenExitTimer) {
    [_fullscreenExitTimer invalidate];
    _fullscreenExitTimer = nil;
  }

  // Ensure titlebar is visible after exiting fullscreen (especially if client
  // disconnected) This allows users to interact with the window even if no
  // clients are connected
  if (_window && _connectedClientCount == 0) {
    NSWindowStyleMask titlebarStyle =
        (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
         NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable);
    if (_window.styleMask != titlebarStyle) {
      _window.styleMask = titlebarStyle;
      NSLog(@"[FULLSCREEN] Restored titlebar after exiting fullscreen (no "
            @"clients connected)");
    }
  }

  NSLog(@"[FULLSCREEN] Window exited fullscreen");
}
#endif

// NSWindowDelegate method - called when window is resized
- (void)windowDidResize:(NSNotification *)notification {
  int32_t width = 0, height = 0;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: Handle resize differently
  (void)notification;
  CGRect frame = _window.bounds;
  width = (int32_t)frame.size.width;
  height = (int32_t)frame.size.height;
#else
  NSWindow *window = notification.object;
  NSRect frame = [window.contentView bounds];
  width = (int32_t)frame.size.width;
  height = (int32_t)frame.size.height;

  NSLog(@"[WINDOW] Window resized to %dx%d", width, height);

  // Update Metal view frame to match window size if Metal backend is active
  NSView *contentView = window.contentView;
  if ([contentView isKindOfClass:[CompositorView class]]) {
    CompositorView *compositorView = (CompositorView *)contentView;

    // If Metal view exists, ensure it matches the window size
    if (_backendType == 1 && compositorView.metalView) {
      NSRect metalFrame = compositorView.bounds;
      compositorView.metalView.frame = metalFrame;
      // CRITICAL: Do NOT manually set bounds - MTKView handles this
      // automatically MTKView automatically sets bounds to match frame and
      // calculates drawableSize Manually setting bounds interferes with Retina
      // scaling
      NSLog(@"[WINDOW] Metal view resized to match window: frame=%.0fx%.0f "
            @"(MTKView handles bounds/drawable automatically)",
            metalFrame.size.width, metalFrame.size.height);

      // Trigger Metal view to update its drawable size
      [compositorView.metalView setNeedsDisplay:YES];
    } else {
      // Cocoa backend - trigger redraw
      [contentView setNeedsDisplay:YES];
    }
  }
#endif

  if (_output) {
    int32_t scale = 1;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    scale = (int32_t)[UIScreen mainScreen].scale;
#else
    scale = (int32_t)_window.backingScaleFactor;
#endif
    wl_output_update_size(_output, width, height, scale);
  }

  // Update xdg_wm_base output size immediately
  if (_xdg_wm_base) {
    xdg_wm_base_set_output_size(_xdg_wm_base, width, height);
  }

  // Schedule configure events to be sent from the Wayland event thread
  // Wayland server functions must be called from the event thread
  _pending_resize_width = width;
  _pending_resize_height = height;
  _needs_resize_configure = YES;

  // Trigger the idle callback immediately to send configure events
  if (_eventLoop) {
    // Kick the timer from the event loop thread to send configure + frame
    // callbacks quickly
    wl_event_loop_add_idle(_eventLoop, ensure_frame_callback_timer_idle,
                           (__bridge void *)self);
  }
}

// DEPRECATED: This function is no longer used - it caused infinite loops
// Frame callbacks are now handled entirely by the timer mechanism
static void send_frame_callbacks_timer_idle(void *data) {
  // Do nothing - this function should never be called
  // If it is called, it means there's a bug somewhere adding idle callbacks
  (void)data;
  log_printf("[COMPOSITOR] ", "ERROR: send_frame_callbacks_timer_idle called - "
                              "this should not happen!\n");
}

// Ensure the frame callback timer exists and is scheduled (must run on event
// thread)
static BOOL ensure_frame_callback_timer_on_event_thread(
    WawonaCompositor *compositor, uint32_t delay_ms, const char *reason) {
  if (!compositor || !compositor.display) {
    return NO;
  }

  struct wl_event_loop *eventLoop =
      wl_display_get_event_loop(compositor.display);
  if (!eventLoop) {
    log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: "
                                "event loop unavailable\n");
    return NO;
  }

  if (!compositor.frame_callback_source) {
    compositor.frame_callback_source = wl_event_loop_add_timer(
        eventLoop, send_frame_callbacks_timer, (__bridge void *)compositor);
    if (!compositor.frame_callback_source) {
      log_printf("[COMPOSITOR] ",
                 "ensure_frame_callback_timer_on_event_thread: Failed to "
                 "create timer (%s)\n",
                 reason ? reason : "no reason");
      return NO;
    }
    log_printf("[COMPOSITOR] ",
               "ensure_frame_callback_timer_on_event_thread: Created timer "
               "(%s, delay=%ums)\n",
               reason ? reason : "no reason", delay_ms);
  }

  // CRITICAL: Always update timer delay to schedule it
  // If delay is 0, we want immediate execution - but Wayland timers might not
  // fire immediately So use a small delay (1ms) to ensure it fires in the next
  // event loop iteration
  uint32_t actual_delay = (delay_ms == 0) ? 1 : delay_ms;
  int ret = wl_event_source_timer_update(compositor.frame_callback_source,
                                         actual_delay);
  if (ret < 0) {
    int err = errno;
    log_printf("[COMPOSITOR] ",
               "ensure_frame_callback_timer_on_event_thread: timer update "
               "failed (%s, delay=%ums) - recreating\n",
               strerror(err), delay_ms);
    wl_event_source_remove(compositor.frame_callback_source);
    compositor.frame_callback_source = NULL;

    compositor.frame_callback_source = wl_event_loop_add_timer(
        eventLoop, send_frame_callbacks_timer, (__bridge void *)compositor);
    if (!compositor.frame_callback_source) {
      log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread:"
                                  " Failed to recreate timer after error\n");
      return NO;
    }

    ret = wl_event_source_timer_update(compositor.frame_callback_source,
                                       delay_ms);
    if (ret < 0) {
      err = errno;
      log_printf("[COMPOSITOR] ",
                 "ensure_frame_callback_timer_on_event_thread: Second timer "
                 "update failed (%s)\n",
                 strerror(err));
      wl_event_source_remove(compositor.frame_callback_source);
      compositor.frame_callback_source = NULL;
      return NO;
    }

    log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: "
                                "Timer recreated successfully\n");
  } else {
    // Timer update succeeded - verify timer is actually scheduled
    // Log for verification - this confirms the timer should fire
    log_printf("[COMPOSITOR] ",
               "ensure_frame_callback_timer_on_event_thread: Timer updated "
               "successfully (delay=%ums, will fire in %ums, timer=%p)\n",
               delay_ms, actual_delay,
               (void *)compositor.frame_callback_source);
    // Force flush to ensure log is visible immediately
    fflush(stdout);
  }
  return YES;
}

// Idle helper to flush input events and trigger frame callback immediately
// This is safe because it runs on the event thread
static void flush_input_and_send_frame_callbacks_idle(void *data) {
  WawonaCompositor *compositor = (__bridge WawonaCompositor *)data;
  if (compositor) {
    // CRITICAL: Flush clients immediately so they receive keyboard/input events
    // This wakes up clients waiting on wl_display_dispatch() so they can process input
    wl_display_flush_clients(compositor.display);
    
    // Send frame callbacks immediately if any are pending
    // This allows clients to render immediately after processing input
    if (wl_has_pending_frame_callbacks()) {
      log_printf("[COMPOSITOR] ", "flush_input_and_send_frame_callbacks_idle: "
                                  "Flushing input and sending frame callbacks immediately\n");
      send_frame_callbacks_timer(data);
    } else {
      log_printf("[COMPOSITOR] ", "flush_input_and_send_frame_callbacks_idle: "
                                  "Flushed input events (no pending frame callbacks)\n");
    }
  }
}

// Idle helper to trigger first frame callback immediately
// This is safe because it runs on the event thread and only fires once
static void trigger_first_frame_callback_idle(void *data) {
  WawonaCompositor *compositor = (__bridge WawonaCompositor *)data;
  if (compositor) {
    log_printf("[COMPOSITOR] ", "trigger_first_frame_callback_idle: Manually "
                                "triggering first frame callback via idle\n");
    // Manually call the timer function
    // This will send callbacks and re-arm the timer for the next frame (16ms
    // later)
    send_frame_callbacks_timer(data);
  }
}

// Idle helper to (re)arm the timer from threads other than the event thread
static void ensure_frame_callback_timer_idle(void *data) {
  WawonaCompositor *compositor = (__bridge WawonaCompositor *)data;
  if (compositor) {
    ensure_frame_callback_timer_on_event_thread(compositor, 16, "idle kick");
  }
}

// Timer callback to send frame callbacks from Wayland event thread
// This fires every ~16ms (60Hz) to match display refresh rate
static int send_frame_callbacks_timer(void *data) {
  WawonaCompositor *compositor = (__bridge WawonaCompositor *)data;
  if (!compositor) {
    log_printf(
        "[COMPOSITOR] ",
        "ERROR: send_frame_callbacks_timer called with NULL compositor!\n");
    return 0;
  }

  // This runs on the Wayland event thread - safe to call Wayland server
  // functions

  // Timer fires every 16ms - log calls to verify operation
  static int timer_call_count = 0;
  timer_call_count++;

  // Always log first call to verify timer fired
  if (timer_call_count == 1) {
    log_printf("[COMPOSITOR] ",
               "✅ send_frame_callbacks_timer() FIRED! (call #%d) - Timer is "
               "working!\n",
               timer_call_count);
    fflush(stdout);
  }

  // Log every 60 calls (approx every 1 second) to keep liveliness check
  if (timer_call_count <= 30 || timer_call_count % 60 == 0) {
    log_printf("[COMPOSITOR] ",
               "send_frame_callbacks_timer() called (call #%d)\n",
               timer_call_count);
    fflush(stdout); // Force flush to ensure log is visible
  }

  // Handle pending resize configure events first
  if (compositor.needs_resize_configure) {
    // Update wl_output mode/geometry (must be done on event thread to avoid
    // races)
    if (compositor.output) {
      wl_output_update_size(compositor.output, compositor.pending_resize_width,
                            compositor.pending_resize_height,
                            compositor.pending_resize_scale);
    }

    if (compositor.xdg_wm_base) {
      // Pass actual output size for storage (clients can use as hint)
      // But configure events send 0x0 to signal arbitrary resolution support
      xdg_wm_base_send_configure_to_all_toplevels(
          compositor.xdg_wm_base, compositor.pending_resize_width,
          compositor.pending_resize_height);
    }
    compositor.needs_resize_configure = NO;
  }

  // Send frame callbacks
  int sent_count = wl_send_frame_callbacks();
  if (sent_count > 0) {
    log_printf("[COMPOSITOR] ",
               "send_frame_callbacks_timer: Sent %d frame callback(s)\n",
               sent_count);
    fflush(stdout);
  }

  // CRITICAL: Flush clients to ensure frame callbacks are sent immediately
  // This wakes up clients waiting on wl_display_dispatch()
  wl_display_flush_clients(compositor.display);

  // CRITICAL: Re-arm timer for next frame (16ms = 60Hz)
  // Always re-arm to keep timer firing continuously
  if (compositor.frame_callback_source) {
    int ret =
        wl_event_source_timer_update(compositor.frame_callback_source, 16);
    if (ret < 0) {
      int err = errno;
      log_printf("[COMPOSITOR] ",
                 "send_frame_callbacks_timer: Failed to re-arm timer: %s\n",
                 strerror(err));
      // Timer update failed - recreate it
      wl_event_source_remove(compositor.frame_callback_source);
      compositor.frame_callback_source = NULL;
      ensure_frame_callback_timer_on_event_thread(
          compositor, 16, "recreate after update failure");
    } else {
      // Log first 10 re-arms to verify timer is working continuously
      static int rearm_count = 0;
      rearm_count++;
      if (rearm_count <= 10) {
        log_printf("[COMPOSITOR] ",
                   "send_frame_callbacks_timer: Re-armed timer successfully "
                   "(rearm #%d, next fire in 16ms)\n",
                   rearm_count);
      }
    }
  } else {
    // Timer was removed - recreate it immediately
    log_printf("[COMPOSITOR] ",
               "send_frame_callbacks_timer: Timer was removed, recreating\n");
    ensure_frame_callback_timer_on_event_thread(compositor, 16,
                                                "recreate after removal");
  }

  // Return 0 to indicate timer callback completed
  // We manually re-arm above, so timer will continue firing
  return 0;
}

- (void)sendFrameCallbacksImmediately {
  // Force immediate flush of input events and frame callback dispatch
  // This allows clients to receive keyboard events and render immediately
  // NOTE: Must be called from main thread, but the callback will run on event thread
  if (_eventLoop) {
    // Flush input events AND send frame callbacks immediately via idle callback
    // This ensures:
    // 1. Clients receive keyboard/input events immediately (via flush)
    // 2. Clients can render immediately if they have pending frame callbacks
    wl_event_loop_add_idle(_eventLoop, flush_input_and_send_frame_callbacks_idle,
                           (__bridge void *)self);
  }
}

// Render context for thread-safe iteration
struct RenderContext {
  __unsafe_unretained WawonaCompositor *compositor;
  BOOL surfacesWereRendered;
};

// Iterator function for rendering surfaces
static void render_surface_iterator(struct wl_surface_impl *surface,
                                    void *data) {
  struct RenderContext *ctx = (struct RenderContext *)data;
  WawonaCompositor *self = ctx->compositor;

  // Only render if surface is still valid and has committed buffer
  if (surface->committed && surface->buffer_resource && surface->resource) {
    // Verify resource is still valid before rendering
    struct wl_client *client = wl_resource_get_client(surface->resource);
    if (client) {
      // Use active rendering backend (Cocoa or Metal)
      // Render regardless of window focus state - clients need updates
      if (self.renderingBackend) {
        if ([self.renderingBackend
                respondsToSelector:@selector(renderSurface:)]) {
          [self.renderingBackend renderSurface:surface];
          ctx->surfacesWereRendered = YES;
        } else if (self.renderingBackend) {
          // Fallback to rendering backend
          [self.renderingBackend renderSurface:surface];
          ctx->surfacesWereRendered = YES;
        }
      }
    }
    surface->committed = false;
  }
}

- (void)renderFrame {
  // Render callback - called at display refresh rate (via CVDisplayLink)
  // Event processing is handled by the dedicated Wayland event thread
  // This ensures smooth rendering updates synced to display refresh
  // NOTE: This continues to run even when the window loses focus, ensuring
  // Wayland clients continue to receive frame callbacks and can render updates

  // Note: Frame callback timer is now created automatically when clients
  // request frame callbacks via the macos_compositor_frame_callback_requested
  // callback. This ensures the timer is created on the event thread and starts
  // firing immediately. We don't need to check here anymore - the timer will be
  // created when needed.

  // Check for any committed surfaces and render them
  // Note: The event thread also triggers rendering, but this ensures
  // we catch any surfaces that might have been committed between thread
  // dispatches Continue rendering even when window isn't focused - clients need
  // frame callbacks

  struct RenderContext ctx;
  ctx.compositor = self;
  ctx.surfacesWereRendered = NO;

  // Use thread-safe iteration to render surfaces
  // This locks the surfaces mutex to prevent race conditions with the event
  // thread
  wl_compositor_for_each_surface(render_surface_iterator, &ctx);

  BOOL surfacesWereRendered = ctx.surfacesWereRendered;

  // Trigger view redraw if surfaces were rendered
  // CRITICAL: Even with Metal backend continuous rendering, we must trigger
  // redraw when surfaces are updated to ensure immediate display of nested
  // compositor updates
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *contentView = _window.rootViewController.view;
  if (surfacesWereRendered && _window && contentView) {
    if (_backendType == 1) {
      // Metal backend - trigger redraw using renderer's setNeedsDisplay method
      // This ensures nested compositors (like Weston) see updates immediately
      if ([self->_renderingBackend
              respondsToSelector:@selector(setNeedsDisplay)]) {
        [self->_renderingBackend setNeedsDisplay];
      }
    } else {
      // Cocoa backend - needs explicit redraw
      [contentView setNeedsDisplay];
    }
  } else if (_window && contentView && _backendType != 1) {
    // Cocoa backend always needs redraw for frame callbacks
    [contentView setNeedsDisplay];
  }
#else
  if (surfacesWereRendered && _window && _window.contentView) {
    if (_backendType == 1) {
      // Metal backend - trigger redraw using renderer's setNeedsDisplay method
      // This ensures nested compositors (like Weston) see updates immediately
      if ([self->_renderingBackend
              respondsToSelector:@selector(setNeedsDisplay)]) {
        [self->_renderingBackend setNeedsDisplay];
      }
    } else {
      // Cocoa backend - needs explicit redraw
      [_window.contentView setNeedsDisplay:YES];
    }
  } else if (_window && _window.contentView && _backendType != 1) {
    // Cocoa backend always needs redraw for frame callbacks
    [_window.contentView setNeedsDisplay:YES];
  }
#endif
}

// Helper function to disconnect all clients gracefully
static void disconnect_all_clients(struct wl_display *display) {
  if (!display)
    return;

  log_printf("[COMPOSITOR] ", "🔌 Disconnecting all clients...\n");

  // Terminate display to stop accepting new connections first
  wl_display_terminate(display);

  // Flush once to send termination signal
  wl_display_flush_clients(display);

  // Process a few events to let termination propagate
  struct wl_event_loop *eventLoop = wl_display_get_event_loop(display);
  for (int i = 0; i < 5; i++) {
    int ret = wl_event_loop_dispatch(eventLoop, 10);
    if (ret < 0)
      break;
    wl_display_flush_clients(display);
  }

  // Use the official Wayland server API to destroy all clients
  // This is the proper protocol-compliant way to disconnect all clients
  wl_display_destroy_clients(display);

  // Process events multiple times AFTER destroying clients
  // This gives clients (like waypipe) time to detect the disconnect and exit
  // gracefully
  for (int i = 0; i < 30; i++) {
    // Dispatch events with a short timeout
    int ret = wl_event_loop_dispatch(eventLoop, 50);
    if (ret < 0) {
      // Error or no more events - continue a bit more to ensure cleanup
      if (i < 15) {
        // Still process a few more times even on error to let waypipe detect
        // disconnect
        continue;
      } else {
        break;
      }
    }
    // Flush all client connections to send pending messages
    wl_display_flush_clients(display);
  }

  // Small delay to allow waypipe and other clients to fully detect disconnect
  // and exit This helps prevent "Broken pipe" errors from appearing after
  // shutdown
  usleep(100000); // 100ms delay

  // Final flush to ensure all messages are sent
  wl_display_flush_clients(display);

  log_printf("[COMPOSITOR] ", "✅ Client disconnection complete\n");
}

- (void)stop {
  NSLog(@"🛑 Stopping compositor backend...");

  // Clear global reference
  if (g_compositor_instance == self) {
    g_compositor_instance = NULL;
  }

  // CRITICAL: Disconnect clients FIRST while event thread is still running
  // This ensures the event loop can properly process disconnection events
  // and send them to clients (like waypipe) so they can detect the disconnect
  if (_display) {
    disconnect_all_clients(_display);
  }

  // Now signal event thread to stop (after clients are disconnected)
  _shouldStopEventThread = YES;

  // Wait for event thread to finish (with timeout)
  if (_eventThread && [_eventThread isExecuting]) {
    // Give thread up to 1 second to finish
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while ([_eventThread isExecuting] && [timeout timeIntervalSinceNow] > 0) {
      [NSThread sleepForTimeInterval:0.01];
    }

    if ([_eventThread isExecuting]) {
      NSLog(@"⚠️ Event thread did not stop gracefully, forcing termination");
    }
  }
  _eventThread = nil;

  // Stop display link
  if (_displayLink) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [_displayLink invalidate];
#else
    CVDisplayLinkStop(_displayLink);
    CVDisplayLinkRelease(_displayLink);
#endif
    _displayLink = NULL;
  }

  // Stop frame callback timer
  if (_frame_callback_source) {
    wl_event_source_remove(_frame_callback_source);
    _frame_callback_source = NULL;
  }

  // Clean up Wayland resources
  if (_xdg_wm_base) {
    xdg_wm_base_destroy(_xdg_wm_base);
    _xdg_wm_base = NULL;
  }

  if (_shm) {
    wl_shm_destroy(_shm);
    _shm = NULL;
  }

  if (_seat) {
    wl_seat_destroy(_seat);
    _seat = NULL;
  }

  if (_output) {
    wl_output_destroy(_output);
    _output = NULL;
  }

  if (_compositor) {
    wl_compositor_destroy(_compositor);
    _compositor = NULL;
  }

  // CRITICAL: Close TCP listening socket if it exists
  // This prevents new connections from being accepted
  if (_tcp_listen_fd >= 0) {
    close(_tcp_listen_fd);
    _tcp_listen_fd = -1;
    log_printf("[COMPOSITOR] ", "🔌 Closed TCP listening socket\n");
  }

  // CRITICAL: Destroy the display to properly close sockets and clean up resources
  // This ensures waypipe and other clients detect the disconnect
  if (_display) {
    // Destroy display (this closes all sockets and frees resources)
    wl_display_destroy(_display);
    _display = NULL;
  }

  // Clean up Unix socket file if it exists
  // This ensures waypipe doesn't think the compositor is still running
  // Note: wl_display_destroy() should close the socket, but we unlink the file
  // to ensure it's removed from the filesystem
  const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
  const char *socket_name = getenv("WAYLAND_DISPLAY");
  if (runtime_dir && socket_name) {
    char socket_path[512];
    snprintf(socket_path, sizeof(socket_path), "%s/%s", runtime_dir, socket_name);
    if (unlink(socket_path) == 0) {
      log_printf("[COMPOSITOR] ", "🗑️ Removed socket file: %s\n", socket_path);
    } else if (errno != ENOENT) {
      // ENOENT means file doesn't exist, which is fine (might have been cleaned up already)
      log_printf("[COMPOSITOR] ", "⚠️ Failed to remove socket file %s: %s\n", 
                 socket_path, strerror(errno));
    }
  }

  cleanup_logging();
  NSLog(@"🛑 Compositor backend stopped");
}

- (void)switchToMetalBackend {
  // Switch from Cocoa to Metal rendering backend for full compositors
  if (_backendType == 1) { // Already using Metal
    return;
  }

  NSLog(@"🔄 Switching to Metal rendering backend for full compositor support");

  // Check Safe Area setting (used throughout this function)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  BOOL respectSafeArea =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"RespectSafeArea"];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"RespectSafeArea"] ==
      nil) {
    respectSafeArea = YES;
  }
#else
  BOOL respectSafeArea = NO;
#endif

  // Get the compositor view
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *contentView = _window.rootViewController.view;
  CGRect windowBounds;
#else
  NSView *contentView = _window.contentView;
  NSRect windowBounds;
#endif
  if (![contentView isKindOfClass:[CompositorView class]]) {
    NSLog(@"⚠️ Content view is not CompositorView, cannot switch to Metal");
    return;
  }

  CompositorView *compositorView = (CompositorView *)contentView;

  // CRITICAL: Ensure CompositorView is sized to safe area before creating Metal
  // view
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [compositorView setNeedsLayout];
  [compositorView layoutIfNeeded];

  // Update CompositorView frame to safe area if respecting

  if (respectSafeArea) {
    CGRect windowBoundsLocal = _window.bounds;
    CGRect safeAreaFrame = windowBoundsLocal;

    if (@available(iOS 11.0, *)) {
      UILayoutGuide *safeArea = _window.safeAreaLayoutGuide;
      safeAreaFrame = safeArea.layoutFrame;
      if (CGRectIsEmpty(safeAreaFrame)) {
        UIEdgeInsets insets = compositorView.safeAreaInsets;
        if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
            insets.right != 0) {
          safeAreaFrame = UIEdgeInsetsInsetRect(windowBoundsLocal, insets);
        }
      }
    } else {
      UIEdgeInsets insets = compositorView.safeAreaInsets;
      if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
          insets.right != 0) {
        safeAreaFrame = UIEdgeInsetsInsetRect(windowBoundsLocal, insets);
      }
    }

    compositorView.frame = safeAreaFrame;
    compositorView.autoresizingMask = UIViewAutoresizingNone;
  } else {
    compositorView.frame = _window.bounds;
    compositorView.autoresizingMask =
        (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
  }
#endif

  // Get current window size for Metal view
  // Note: CompositorView bounds will be safe area if respecting, or full window
  // if not
  windowBounds = compositorView.bounds;

  // Metal view should fill CompositorView (which is already sized to safe area
  // if respecting)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGRect initialFrame = compositorView.bounds;
  NSLog(@"🔵 Metal view initial frame (CompositorView bounds): (%.0f, %.0f) "
        @"%.0fx%.0f (safe area: %@)",
        initialFrame.origin.x, initialFrame.origin.y, initialFrame.size.width,
        initialFrame.size.height, respectSafeArea ? @"YES" : @"NO");
#else
  CGRect initialFrame = windowBounds;
#endif

  // Create Metal view with safe area-aware frame
  // Use a custom class that allows window dragging for proper window controls
  Class CompositorMTKViewClass = NSClassFromString(@"CompositorMTKView");
  MTKView *metalView = nil;
  if (CompositorMTKViewClass) {
    metalView = [[CompositorMTKViewClass alloc] initWithFrame:initialFrame];
  } else {
    // Fallback to regular MTKView if custom class not available
    metalView = [[MTKView alloc] initWithFrame:initialFrame];
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // CRITICAL: Disable autoresizing when safe area is enabled, otherwise it will
  // override our frame
  if (respectSafeArea) {
    metalView.autoresizingMask = UIViewAutoresizingNone;
  } else {
    metalView.autoresizingMask =
        (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
  }
#else
  metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  // Ensure Metal view is opaque and properly configured
  metalView.wantsLayer = YES;
  metalView.layer.opaque = YES;
  metalView.layerContentsRedrawPolicy =
      NSViewLayerContentsRedrawDuringViewResize;
#endif
  metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  metalView.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);

  // CRITICAL: Don't block mouse events - allow window controls to work
  // The Metal view should not intercept mouse events meant for window controls
  // Note: mouseDownCanMoveWindow is a method, not a property - handled in
  // CompositorView Don't set ignoresMouseEvents - we need to receive events for
  // Wayland clients But ensure the view doesn't block window controls

  // Frame is already set above based on safe area setting
  // metalView.frame = initialFrame; // Already set in initWithFrame

  NSLog(@"   Creating Metal view with frame: %.0fx%.0f at (%.0f, %.0f) (safe "
        @"area: %@)",
        initialFrame.size.width, initialFrame.size.height,
        initialFrame.origin.x, initialFrame.origin.y,
        respectSafeArea ? @"YES" : @"NO");

  // Create Metal renderer
  MetalRenderer *metalRenderer =
      [[MetalRenderer alloc] initWithMetalView:metalView];
  if (!metalRenderer) {
    NSLog(@"❌ Failed to create Metal renderer");
    return;
  }

  // Add Metal view as subview (on top of Cocoa view for rendering)
  // The Metal view renders content but allows events to pass through to
  // CompositorView
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [compositorView addSubview:metalView];
  compositorView.metalView = metalView;

  // CRITICAL: Update output size after Metal view is added to ensure safe area
  // is respected This will recalculate and reposition the metalView if needed
  [self updateOutputSize:compositorView.bounds.size];

  // iOS: Touch events are handled via UIKit gesture recognizers
  // Re-setup input handling if needed
  if (_inputHandler) {
    [_inputHandler setupInputHandling];
  }
#else
  [compositorView addSubview:metalView positioned:NSWindowAbove relativeTo:nil];
  compositorView.metalView = metalView;

  // Ensure CompositorView remains the responder chain - Metal view just renders
  // This allows CompositorView to handle events while Metal view displays
  // content
  [metalView setNextResponder:compositorView];

  // CRITICAL: Ensure mouse events pass through to CompositorView for tracking
  // areas The Metal view should not block mouse events - they need to reach the
  // tracking area Don't set ignoresMouseEvents - we need events for Wayland
  // clients But ensure the view hierarchy allows events to reach
  // CompositorView's tracking area

  // Update input handler's tracking area to cover the full view including Metal
  // view
  if (_inputHandler) {
    // Remove old tracking area and create new one covering full bounds
    NSView *inputContentView = _window.contentView;
    for (NSTrackingArea *area in [inputContentView trackingAreas]) {
      [inputContentView removeTrackingArea:area];
    }
    // Re-setup input handling with updated tracking area
    [_inputHandler setupInputHandling];
  }
#endif

  // Switch rendering backend
  _renderingBackend = metalRenderer;
  _backendType = 1; // RENDERING_BACKEND_METAL

  // Update render callback to use Metal backend
  // The render_surface_callback will now use the Metal backend

  NSLog(@"✅ Switched to Metal rendering backend");
  NSLog(@"   Metal view frame: %.0fx%.0f", metalView.frame.size.width,
        metalView.frame.size.height);
  NSLog(@"   Window bounds: %.0fx%.0f", windowBounds.size.width,
        windowBounds.size.height);
  NSLog(@"   Metal renderer: %@", metalRenderer);
}

- (void)updateWindowTitleForClient:(struct wl_client *)client {
  if (!_window || !client)
    return;

  NSString *windowTitle = @"Wawona"; // Default title when no clients

  // Try to get the focused surface's toplevel title/app_id
  if (_seat && _seat->focused_surface) {
    struct wl_surface_impl *surface =
        (struct wl_surface_impl *)_seat->focused_surface;
    if (surface && surface->resource) {
      struct wl_client *surface_client =
          wl_resource_get_client(surface->resource);
      if (surface_client == client) {
        // Get the toplevel for this surface
        extern struct xdg_toplevel_impl
            *xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *
                                                      wl_surface);
        struct xdg_toplevel_impl *toplevel =
            xdg_surface_get_toplevel_from_wl_surface(surface);

        if (toplevel) {
          // Prefer title over app_id, fallback to app_id if title is not set
          if (toplevel->title && strlen(toplevel->title) > 0) {
            windowTitle = [NSString stringWithUTF8String:toplevel->title];
          } else if (toplevel->app_id && strlen(toplevel->app_id) > 0) {
            // Use app_id, but make it more readable
            NSString *appId = [NSString stringWithUTF8String:toplevel->app_id];
            // Remove common prefixes like "org.freedesktop." or "com."
            appId =
                [appId stringByReplacingOccurrencesOfString:@"org.freedesktop."
                                                 withString:@""];
            appId = [appId stringByReplacingOccurrencesOfString:@"com."
                                                     withString:@""];
            // Capitalize first letter
            if (appId.length > 0) {
              appId = [[appId substringToIndex:1].uppercaseString
                  stringByAppendingString:[appId substringFromIndex:1]];
            }
            windowTitle = appId;
          }
        }

        // If we still don't have a title, try process name as fallback
        if ([windowTitle isEqualToString:@"Wawona"]) {
          pid_t client_pid = 0;
          uid_t client_uid = 0;
          gid_t client_gid = 0;
          wl_client_get_credentials(client, &client_pid, &client_uid,
                                    &client_gid);

          if (client_pid > 0) {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
            char proc_path[PROC_PIDPATHINFO_MAXSIZE] = {0};
            int ret = proc_pidpath(client_pid, proc_path, sizeof(proc_path));
            if (ret > 0) {
              NSString *processPath = [NSString stringWithUTF8String:proc_path];
#else
            // iOS: Process name detection not available
            NSString *processPath = nil;
            if (0) {
#endif
              NSString *processName = [processPath lastPathComponent];
              // Remove common suffixes and make it look nice
              processName =
                  [processName stringByReplacingOccurrencesOfString:@".exe"
                                                         withString:@""];
              windowTitle = processName;
            }
          }
        }
      }
    }
  }

  // Update window title
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: Window titles are not displayed in the same way
  (void)windowTitle;
  NSLog(@"[WINDOW] Updated title to: %@", windowTitle);
#else
  // macOS: Update titlebar title
  [_window setTitle:windowTitle];
  NSLog(@"[WINDOW] Updated titlebar title to: %@", windowTitle);
#endif
}

// C function to set CSD mode for a toplevel (hide/show macOS window
// decorations)
void macos_compositor_set_csd_mode_for_toplevel(
    struct xdg_toplevel_impl *toplevel, bool csd) {
  if (!g_compositor_instance || !toplevel) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  (void)csd; // iOS: CSD mode not applicable
#else
  // Dispatch to main thread to update UI
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = g_compositor_instance.window;
    if (!window) {
      return;
    }

    // Get current style mask
    NSWindowStyleMask currentStyle = window.styleMask;

    // CRITICAL: Cannot change styleMask while window is in fullscreen - macOS
    // throws exception We'll handle fullscreen titlebar visibility by exiting
    // fullscreen after client disconnect (see
    // macos_compositor_handle_client_disconnect)
    BOOL isFullscreen = g_compositor_instance.isFullscreen;

    // Don't change style mask while in fullscreen - wait for fullscreen to exit
    // first
    if (isFullscreen) {
      NSLog(@"[CSD] Skipping styleMask change - window is in fullscreen (will "
            @"be handled after exit)");
      return;
    }

    if (csd) {
      // CLIENT_SIDE decorations - hide macOS window decorations
      // Remove titlebar, close button, etc. - client will draw its own
      // decorations
      NSWindowStyleMask csdStyle =
          NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable;
      if (currentStyle != csdStyle) {
        window.styleMask = csdStyle;
        NSLog(
            @"[CSD] Window decorations hidden for CLIENT_SIDE decoration mode");
      }
    } else {
      // SERVER_SIDE decorations - show macOS window decorations
      // Show titlebar, close button, resize controls, etc.
      NSWindowStyleMask gsdStyle =
          (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
           NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable);
      if (currentStyle != gsdStyle) {
        window.styleMask = gsdStyle;
        NSLog(
            @"[CSD] Window decorations shown for SERVER_SIDE decoration mode");
      }
    }
  });
#endif
}

// C function to activate/raise the window (called from activation protocol)
void macos_compositor_activate_window(void) {
  if (!g_compositor_instance) {
    return;
  }
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Dispatch to main thread to raise window
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = g_compositor_instance.window;
    if (!window) {
      return;
    }

    // Raise window to front and make it key
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [window becomeKeyWindow];

    NSLog(@"[ACTIVATION] Window activated and raised to front");
  });
#endif
}

// C function to handle client disconnection (may exit fullscreen if needed)
void macos_compositor_handle_client_disconnect(void) {
  if (!g_compositor_instance) {
    return;
  }

#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaCompositor *compositor = g_compositor_instance;

    // Decrement client count
    if (compositor.connectedClientCount > 0) {
      compositor.connectedClientCount--;
    }

    NSLog(@"[FULLSCREEN] Client disconnected. Connected clients: %lu",
          (unsigned long)compositor.connectedClientCount);

    // If we're in fullscreen and have no clients, start exit timer
    // NOTE: We cannot change styleMask while in fullscreen - macOS throws an
    // exception Instead, we'll exit fullscreen after 10 seconds, which will
    // restore the titlebar
    if (compositor.isFullscreen && compositor.connectedClientCount == 0) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      // iOS: Fullscreen handling not applicable
      (void)compositor;
#else
            NSWindow *window = compositor.window;
            if (window) {
                // Cancel any existing timer
                if (compositor.fullscreenExitTimer) {
                    [compositor.fullscreenExitTimer invalidate];
                    compositor.fullscreenExitTimer = nil;
                }
                
                // Start 10-second timer to close window if no new client connects
                // If no clients are connected, there's no reason to keep the window open
                compositor.fullscreenExitTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                                                   repeats:NO
                                                                                     block:^(NSTimer *timer) {
                    (void)timer; // Unused parameter
                    // Check if we still have no clients
                    if (compositor.connectedClientCount == 0 && compositor.isFullscreen) {
                        NSLog(@"[FULLSCREEN] No clients connected after 10 seconds - closing window");
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
                        // iOS: Hide window instead of closing
                        window.hidden = YES;
#else
                        if (@available(macOS 10.12, *)) {
                            [window performClose:nil];
                        }
#endif
                    }
                    compositor.fullscreenExitTimer = nil;
                }];
                NSLog(@"[FULLSCREEN] Started 10-second timer to close window if no client connects");
            }
#endif
    }
  });
#else
  if (g_compositor_instance->connectedClientCount > 0) {
    g_compositor_instance->connectedClientCount--;
  }
  log_printf("[FULLSCREEN] Client disconnected. Connected clients: %d\n",
             g_compositor_instance->connectedClientCount);
#endif
}

// C function to handle new client connection (cancel fullscreen exit timer)
void macos_compositor_handle_client_connect(void) {
  if (!g_compositor_instance) {
    return;
  }

#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaCompositor *compositor = g_compositor_instance;

    // Increment client count
    compositor.connectedClientCount++;

    NSLog(@"[FULLSCREEN] Client connected. Connected clients: %lu",
          (unsigned long)compositor.connectedClientCount);

    // Cancel fullscreen exit timer if a client connected
    if (compositor.fullscreenExitTimer) {
      [compositor.fullscreenExitTimer invalidate];
      compositor.fullscreenExitTimer = nil;
      NSLog(@"[FULLSCREEN] Cancelled fullscreen exit timer (client connected)");
    }
  });
#else
  g_compositor_instance->connectedClientCount++;
  log_printf("[FULLSCREEN] Client connected. Connected clients: %d\n",
             g_compositor_instance->connectedClientCount);
#endif
}

// C function to update window title when no clients are connected
void macos_compositor_update_title_no_clients(void) {
  if (!g_compositor_instance) {
    return;
  }

#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaCompositor *compositor = g_compositor_instance;
    if (compositor.window) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      // iOS: Window titles not displayed
      (void)compositor;
#else
            [compositor.window setTitle:@"Wawona"];
#endif
      NSLog(
          @"[WINDOW] Updated titlebar title to: Wawona (no clients connected)");
    }
  });
#else
  log_printf("[WINDOW] Updated titlebar title to: Wawona (no clients connected)\n");
#endif
}

// C function to get EGL buffer handler (for rendering EGL buffers)
struct egl_buffer_handler *macos_compositor_get_egl_buffer_handler(void) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: EGL is disabled
  return NULL;
#else
  if (!g_compositor_instance) {
    return NULL;
  }
  return g_compositor_instance.egl_buffer_handler;
#endif
}

- (void)dealloc {
  // Remove notification observers
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  // Clean up timer
  if (_fullscreenExitTimer) {
    [_fullscreenExitTimer invalidate];
    _fullscreenExitTimer = nil;
  }

  // Clean up text input manager
  if (_text_input_manager) {
    // Text input manager cleanup is handled by wayland resource destruction
    _text_input_manager = NULL;
  }

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Clean up EGL buffer handler
  if (_egl_buffer_handler) {
    egl_buffer_handler_cleanup(_egl_buffer_handler);
    free(_egl_buffer_handler);
    _egl_buffer_handler = NULL;
  }
#endif

  [self stop];
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#if !__has_feature(objc_arc)
  [super dealloc];
#endif
#endif
}

@end
bool wawona_is_egl_enabled(void) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  return [[NSUserDefaults standardUserDefaults] boolForKey:@"EnableEGLDrivers"];
#else
  return [[NSUserDefaults standardUserDefaults] boolForKey:@"EnableEGLDrivers"];
#endif
}
