// iOS Launcher Client - Wayland client implementation
// This file is isolated to avoid conflicts between wayland-client and wayland-server headers
// It only includes wayland-client.h, not wayland-server headers

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <time.h>
#include <fcntl.h>
#include <sys/select.h>
#include <sys/mman.h> // For mmap
#include "ios_launcher_client.h"
#include "xdg-shell-client-protocol.h"

// Internal: Set client_display on delegate using runtime
static void setClientDisplay(WawonaAppDelegate *delegate, struct wl_display *display) {
    objc_setAssociatedObject(delegate, @selector(client_display), [NSValue valueWithPointer:display], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Internal: Get client_display from delegate using runtime
static struct wl_display *getClientDisplay(WawonaAppDelegate *delegate) {
    NSValue *value = objc_getAssociatedObject(delegate, @selector(client_display));
    return value ? [value pointerValue] : NULL;
}

// Launcher client state
struct launcher_client_state {
    struct wl_compositor *compositor;
    struct wl_shm *shm;
    struct xdg_wm_base *xdg_wm_base;
    struct wl_seat *seat;
    struct wl_touch *touch;
    struct wl_surface *surface;
    struct xdg_surface *xdg_surface;
    struct xdg_toplevel *xdg_toplevel;
    int width;
    int height;
    int ready;
    int configured;
    bool needs_redraw;
};

// Registry listener callbacks for launcher client
static void launcher_registry_handle_global(void *data, struct wl_registry *registry,
                                           uint32_t name, const char *interface, uint32_t version) {
    struct launcher_client_state *state = (struct launcher_client_state *)data;
    (void)state;
    
    NSLog(@"🎯 Launcher: Found global interface: %s (version %u, name %u)", interface, version, name);
    
    if (strcmp(interface, "wl_compositor") == 0) {
        // Bind to compositor interface (minimum version 4)
        uint32_t bind_version = version < 4 ? version : 4;
        state->compositor = (struct wl_compositor *)wl_registry_bind(registry, name, &wl_compositor_interface, bind_version);
        if (state->compositor) {
            NSLog(@"✅ Launcher: Bound to wl_compositor (version %u)", bind_version);
            
            // Create a surface for the launcher
            if (!state->surface) {
                state->surface = wl_compositor_create_surface(state->compositor);
                if (state->surface) {
                    NSLog(@"✅ Launcher: Created Wayland surface");
                    state->ready = 1;
                } else {
                    NSLog(@"❌ Launcher: Failed to create surface");
                }
            }
        } else {
            NSLog(@"❌ Launcher: Failed to bind to wl_compositor");
        }
    } else if (strcmp(interface, "wl_shm") == 0) {
        state->shm = (struct wl_shm *)wl_registry_bind(registry, name, &wl_shm_interface, 1);
        NSLog(@"✅ Launcher: Bound to wl_shm");
    } else if (strcmp(interface, "xdg_wm_base") == 0) {
        state->xdg_wm_base = (struct xdg_wm_base *)wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        NSLog(@"✅ Launcher: Bound to xdg_wm_base");
    } else if (strcmp(interface, "wl_seat") == 0) {
        state->seat = (struct wl_seat *)wl_registry_bind(registry, name, &wl_seat_interface, 7);
        NSLog(@"✅ Launcher: Bound to wl_seat");
    }
}

static void launcher_registry_handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
    NSLog(@"⚠️ Launcher: Global interface removed: %u", name);
}

static const struct wl_registry_listener launcher_registry_listener = {
    launcher_registry_handle_global,
    launcher_registry_handle_global_remove
};

// Arguments for the launcher thread
typedef struct {
    __unsafe_unretained WawonaAppDelegate *delegate;
    int client_fd;
} LauncherThreadArgs;

// XDG Shell Listeners
static void xdg_wm_base_ping(void *data, struct xdg_wm_base *xdg_wm_base, uint32_t serial) {
    xdg_wm_base_pong(xdg_wm_base, serial);
}

static const struct xdg_wm_base_listener xdg_wm_base_listener = {
    .ping = xdg_wm_base_ping,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(xdg_surface, serial);
}
    // If we have a buffer and we are configured, we might want to commit
    // But usually we wait for toplevel configure
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_configure,
};

static void xdg_toplevel_configure(void *data, struct xdg_toplevel *xdg_toplevel,
                                  int32_t width, int32_t height, struct wl_array *states) {
    struct launcher_client_state *state = (struct launcher_client_state *)data;
    
    NSLog(@"ℹ️ Launcher: xdg_toplevel_configure received (w=%d, h=%d)", width, height);
    
    if (width > 0 && height > 0) {
        if (state->width != width || state->height != height) {
            state->width = width;
            state->height = height;
            NSLog(@"📏 Launcher: Resizing to %dx%d", width, height);
            state->needs_redraw = true;
        }
    }
    state->configured = 1;
}

static void xdg_toplevel_close(void *data, struct xdg_toplevel *xdg_toplevel) {
    NSLog(@"🛑 Launcher: Window closed by compositor");
    // Exit loop logic here
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    .configure = xdg_toplevel_configure,
    .close = xdg_toplevel_close,
};

// UI State
typedef struct {
    int x, y, w, h;
    uint32_t color;
    uint32_t pressed_color;
    bool pressed;
    const char *label;
} Button;

#define BUTTON_COUNT 2
static Button buttons[BUTTON_COUNT] = {
    {50, 50, 200, 80, 0xFF00FF00, 0xFF00AA00, false, "Green"},
    {300, 50, 200, 80, 0xFF0000FF, 0xFF0000AA, false, "Blue"}
};

// Input Listeners
static void touch_down(void *data, struct wl_touch *wl_touch, uint32_t serial, uint32_t time,
                      struct wl_surface *surface, int32_t id, wl_fixed_t x_w, wl_fixed_t y_w) {
    struct launcher_client_state *state = (struct launcher_client_state *)data;
    double x = wl_fixed_to_double(x_w);
    double y = wl_fixed_to_double(y_w);
    NSLog(@"👇 Launcher: Touch down at (%.1f, %.1f)", x, y);
    
    bool changed = false;
    for (int b = 0; b < BUTTON_COUNT; b++) {
        Button *btn = &buttons[b];
        if (x >= btn->x && x < btn->x + btn->w && y >= btn->y && y < btn->y + btn->h) {
            if (!btn->pressed) {
                btn->pressed = true;
                NSLog(@"👇 Button %d pressed!", b);
                changed = true;
            }
        }
    }
    
    if (changed) {
        state->needs_redraw = true;
    }
}

static void touch_up(void *data, struct wl_touch *wl_touch, uint32_t serial, uint32_t time, int32_t id) {
    struct launcher_client_state *state = (struct launcher_client_state *)data;
    NSLog(@"👆 Launcher: Touch up");
    
    bool changed = false;
    for (int b = 0; b < BUTTON_COUNT; b++) {
        if (buttons[b].pressed) {
            buttons[b].pressed = false;
            NSLog(@"👆 Button %d released!", b);
            changed = true;
            
            // Action logic could go here
            if (b == 0) NSLog(@"🟢 Green Action!");
            if (b == 1) NSLog(@"🔵 Blue Action!");
        }
    }
    
    if (changed) {
        state->needs_redraw = true;
    }
}

static void touch_motion(void *data, struct wl_touch *wl_touch, uint32_t time, int32_t id, wl_fixed_t x_w, wl_fixed_t y_w) {
    // Motion
}

static void touch_frame(void *data, struct wl_touch *wl_touch) {}
static void touch_cancel(void *data, struct wl_touch *wl_touch) {}
static void touch_shape(void *data, struct wl_touch *wl_touch, int32_t id, wl_fixed_t major, wl_fixed_t minor) {}
static void touch_orientation(void *data, struct wl_touch *wl_touch, int32_t id, wl_fixed_t orientation) {}

static const struct wl_touch_listener touch_listener = {
    .down = touch_down,
    .up = touch_up,
    .motion = touch_motion,
    .frame = touch_frame,
    .cancel = touch_cancel,
    .shape = touch_shape,
    .orientation = touch_orientation,
};

static void seat_capabilities(void *data, struct wl_seat *wl_seat, uint32_t capabilities) {
    struct launcher_client_state *state = (struct launcher_client_state *)data;
    
    if (capabilities & WL_SEAT_CAPABILITY_TOUCH) {
        if (!state->touch) {
            state->touch = wl_seat_get_touch(wl_seat);
            wl_touch_add_listener(state->touch, &touch_listener, state);
            NSLog(@"✅ Launcher: Got touch device");
        }
    }
}

static void seat_name(void *data, struct wl_seat *wl_seat, const char *name) {}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

// Output listener to get screen size
static void output_geometry(void *data, struct wl_output *wl_output, int32_t x, int32_t y, int32_t physical_width, int32_t physical_height, int32_t subpixel, const char *make, const char *model, int32_t transform) {
    // Ignored
}

static void output_mode(void *data, struct wl_output *wl_output, uint32_t flags, int32_t width, int32_t height, int32_t refresh) {
    struct launcher_client_state *state = (struct launcher_client_state *)data;
    if (flags & WL_OUTPUT_MODE_CURRENT) {
        NSLog(@"🖥️ Launcher: Output mode: %dx%d", width, height);
        // Use this as default size if not explicitly configured by window manager
        if (!state->configured) {
            state->width = width;
            state->height = height;
            state->needs_redraw = true;
        }
    }
}

static void output_done(void *data, struct wl_output *wl_output) {}
static void output_scale(void *data, struct wl_output *wl_output, int32_t factor) {
    NSLog(@"🖥️ Launcher: Output scale: %d", factor);
}
static void output_name(void *data, struct wl_output *wl_output, const char *name) {}
static void output_description(void *data, struct wl_output *wl_output, const char *description) {}

static const struct wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
    .name = output_name,
    .description = output_description,
};

// Helper to create a file descriptor for shared memory
static int create_shm_file(off_t size) {
    char template[1024];
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    if (runtime_dir) {
        snprintf(template, sizeof(template), "%s/wayland-shm-XXXXXX", runtime_dir);
    } else {
        // Fallback to tmp
        snprintf(template, sizeof(template), "/tmp/wayland-shm-XXXXXX");
    }
    
    int fd = mkstemp(template);
    if (fd < 0) return -1;
    
    // Unlink immediately so it's removed when closed
    unlink(template);
    
    if (ftruncate(fd, size) < 0) {
        close(fd);
        return -1;
    }
    
    return fd;
}

// Helper to draw UI into buffer
static void draw_ui(void *data, int width, int height, int stride) {
    uint32_t *pixels = data;
    
    // Clear background (Dark Gray)
    for (int i = 0; i < width * height; ++i) {
        pixels[i] = 0xFF333333; 
    }
    
    // Draw buttons
    for (int b = 0; b < BUTTON_COUNT; b++) {
        Button *btn = &buttons[b];
        uint32_t color = btn->pressed ? btn->pressed_color : btn->color;
        
        for (int y = btn->y; y < btn->y + btn->h; y++) {
            for (int x = btn->x; x < btn->x + btn->w; x++) {
                if (x >= 0 && x < width && y >= 0 && y < height) {
                    pixels[y * width + x] = color;
                }
            }
        }
    }
}

// Helper to create an SHM buffer
static struct wl_buffer *create_shm_buffer(struct launcher_client_state *state, int width, int height, uint32_t format) {
    if (!state->shm) return NULL;

    int stride = width * 4;
    int size = stride * height;
    
    int fd = create_shm_file(size);
    if (fd < 0) {
        NSLog(@"❌ Launcher: Failed to create SHM file");
        return NULL;
    }
    
    void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        NSLog(@"❌ Launcher: Failed to mmap SHM file");
        close(fd);
        return NULL;
    }
    
    struct wl_shm_pool *pool = wl_shm_create_pool(state->shm, fd, size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, format);
    
    wl_shm_pool_destroy(pool);
    close(fd);
    
    // Draw UI
    draw_ui(data, width, height, stride);
    
    munmap(data, size);
    return buffer;
}

// Launcher client thread function - runs as in-process Wayland client (App Store compliant)
static void *launcherClientThread(void *arg) {
    LauncherThreadArgs *args = (LauncherThreadArgs *)arg;
    WawonaAppDelegate *delegate = args->delegate;
    int client_fd = args->client_fd;
    free(args); // Free arguments
    
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    const char *wayland_display = getenv("WAYLAND_DISPLAY");
    const char *tcp_port_str = getenv("WAYLAND_TCP_PORT");
    
    // Initialize launcher client state
    struct launcher_client_state state = {0};
    state.width = 800;
    state.height = 600;
    state.ready = 0;
    
    struct wl_display *client_display = NULL;
    
    if (client_fd >= 0) {
        // Use the provided socket (e.g. from socketpair)
        NSLog(@"🔌 Launcher: Connecting using provided socket fd %d...", client_fd);
        client_display = wl_display_connect_to_fd(client_fd);
        if (!client_display) {
            NSLog(@"⚠️ Launcher: Failed to create Wayland display from provided FD");
            close(client_fd);
            return NULL;
        }
        NSLog(@"✅ Launcher: Connected via provided socket");
    } else if (tcp_port_str && tcp_port_str[0] != '\0') {
        // Connect via TCP socket (fallback)
        int port = atoi(tcp_port_str);
        if (port <= 0 || port > 65535) {
            NSLog(@"⚠️ Invalid TCP port: %s", tcp_port_str);
            return NULL;
        }
        
        // Create TCP socket
        int tcp_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (tcp_fd < 0) {
            NSLog(@"⚠️ Failed to create TCP socket: %s", strerror(errno));
            return NULL;
        }
        
        // Set socket options
        int reuse = 1;
        setsockopt(tcp_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
        
        // Connect to localhost (blocking)
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = inet_addr("127.0.0.1");
        addr.sin_port = htons(port);
        
        NSLog(@"🔌 Launcher: Connecting to TCP socket on port %d...", port);
        if (connect(tcp_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"⚠️ Failed to connect to Wayland TCP socket on port %d: %s", port, strerror(errno));
            close(tcp_fd);
            return NULL;
        }
        
        NSLog(@"✅ Launcher: TCP socket connected");
        
        // Connect Wayland display to TCP socket FD
        // wl_display_connect_to_fd takes ownership of the FD
        client_display = wl_display_connect_to_fd(tcp_fd);
        if (!client_display) {
            NSLog(@"⚠️ Failed to create Wayland display from TCP socket FD");
            close(tcp_fd);
            return NULL;
        }
        
        NSLog(@"✅ Launcher client connected via TCP (port %d)", port);
    } else {
        // Connect via Unix socket (standard Wayland)
        if (!runtime_dir || !wayland_display) {
            NSLog(@"⚠️ Wayland environment not set up for launcher client");
            return NULL;
        }
        
        // Connect to Wayland display as a client (in-process, App Store compliant)
        // wl_display_connect uses WAYLAND_DISPLAY env var or connects to default
        client_display = wl_display_connect(NULL);
        if (!client_display) {
            NSLog(@"⚠️ Failed to connect launcher client to Wayland display");
            NSLog(@"   XDG_RUNTIME_DIR=%s, WAYLAND_DISPLAY=%s", runtime_dir, wayland_display);
            return NULL;
        }
        
        NSLog(@"✅ Launcher client connected via Unix socket");
    }
    
    setClientDisplay(delegate, client_display);
    NSLog(@"✅ Launcher client connected to Wayland display");
    
    // Get registry FIRST - this triggers the initial protocol handshake
    struct wl_registry *registry = wl_display_get_registry(client_display);
    if (!registry) {
        NSLog(@"⚠️ Failed to get Wayland registry for launcher client");
        wl_display_disconnect(client_display);
        setClientDisplay(delegate, NULL);
        return NULL;
    }
    
    wl_registry_add_listener(registry, &launcher_registry_listener, &state);
    
    // Flush to send registry request
    wl_display_flush(client_display);
    
    // Small delay to ensure server processes the request
    struct timespec ts = {0, 100000000}; // 100ms
    nanosleep(&ts, NULL);
    
    // Roundtrip to receive registry events and bind to interfaces
    // wl_display_roundtrip waits for server response
    NSLog(@"🔄 Launcher: Starting registry roundtrip...");
    int roundtrip_result = wl_display_roundtrip(client_display);
    if (roundtrip_result == -1) {
        NSLog(@"⚠️ Launcher: Initial roundtrip failed, trying dispatch...");
        // Try dispatch as fallback
        int dispatch_result = wl_display_dispatch(client_display);
        if (dispatch_result == -1) {
            NSLog(@"❌ Launcher: Both roundtrip and dispatch failed");
        }
    }
    
    // Check if we got compositor
    if (!state.compositor) {
        NSLog(@"⚠️ Launcher: Compositor not found after initial handshake, retrying...");
        // Try a few more times with delays
        for (int i = 0; i < 5 && !state.compositor; i++) {
            struct timespec delay = {0, 100000000}; // 100ms
            nanosleep(&delay, NULL);
            int dispatch_result = wl_display_dispatch(client_display);
            if (dispatch_result == -1 && i == 0) {
                NSLog(@"⚠️ Launcher: Dispatch failed on retry %d", i + 1);
            }
            if (state.compositor) {
                NSLog(@"✅ Launcher: Found wl_compositor on retry %d", i + 1);
                break;
            }
        }
    }
    
    if (!state.compositor) {
        NSLog(@"❌ Launcher: Failed to bind to wl_compositor after multiple attempts");
        wl_registry_destroy(registry);
        wl_display_disconnect(client_display);
        setClientDisplay(delegate, NULL);
        return NULL;
    }
    
    // Create surface now that we have compositor
    if (!state.surface) {
        state.surface = wl_compositor_create_surface(state.compositor);
        if (state.surface) {
            if (state.xdg_wm_base) {
                state.xdg_surface = xdg_wm_base_get_xdg_surface(state.xdg_wm_base, state.surface);
                xdg_surface_add_listener(state.xdg_surface, &xdg_surface_listener, &state);
                
                state.xdg_toplevel = xdg_surface_get_toplevel(state.xdg_surface);
                xdg_toplevel_add_listener(state.xdg_toplevel, &xdg_toplevel_listener, &state);
                
                // Set title and app ID
                xdg_toplevel_set_title(state.xdg_toplevel, "Wawona Launcher");
                xdg_toplevel_set_app_id(state.xdg_toplevel, "com.aspauldingcode.Wawona.Launcher");
                
                // Commit to trigger initial configure
                wl_surface_commit(state.surface);
                NSLog(@"✅ Launcher: Created XDG surface");
            } else {
                NSLog(@"✅ Launcher: Created Wayland surface (no XDG shell)");
            }
            state.ready = 1;
        } else {
            NSLog(@"❌ Launcher: Failed to create surface");
            wl_compositor_destroy(state.compositor);
            wl_registry_destroy(registry);
            wl_display_disconnect(client_display);
            setClientDisplay(delegate, NULL);
            return NULL;
        }
    }
    
    NSLog(@"🚀 Launcher client running with surface (in-process, App Store compliant)");
    
    // Don't block waiting for configure event - just draw immediately
    // This ensures we see something even if xdg_shell handshake fails or is delayed
    /*
    if (state.xdg_wm_base) {
        while (!state.configured) {
            if (wl_display_dispatch(client_display) == -1) break;
        }
    }
    */
    
    // Set default size if not configured
    if (state.width == 0) state.width = 800;
    if (state.height == 0) state.height = 600;
    
    // Create and attach a buffer to make the surface visible
    if (state.shm) {
        struct wl_buffer *buffer = create_shm_buffer(&state, state.width, state.height, WL_SHM_FORMAT_ARGB8888);
        if (buffer) {
            wl_surface_attach(state.surface, buffer, 0, 0);
            wl_surface_damage(state.surface, 0, 0, state.width, state.height);
            wl_surface_commit(state.surface);
            // Don't destroy buffer immediately, we might need it for redraws or keep it alive
            // For SHM, we can destroy the wl_buffer handle if we don't need to reference it, 
            // but server needs it until release.
            // wl_buffer_destroy(buffer); 
            NSLog(@"✅ Launcher: Attached SHM buffer (%dx%d)", state.width, state.height);
        } else {
            NSLog(@"❌ Launcher: Failed to create SHM buffer");
        }
    } else {
        NSLog(@"⚠️ Launcher: No wl_shm global found, cannot create buffer");
    }
    
    // Flush to ensure server sees it
    wl_display_flush(client_display);
    
    // Keep the connection alive and process events
    int dispatch_result;
    while ((dispatch_result = wl_display_dispatch(client_display)) != -1) {
        // Check if redraw needed
        if (state.needs_redraw) {
            state.needs_redraw = false;
            // ... redraw logic ...
            struct wl_buffer *buffer = create_shm_buffer(&state, state.width, state.height, WL_SHM_FORMAT_ARGB8888);
            if (buffer) {
                wl_surface_attach(state.surface, buffer, 0, 0);
                wl_surface_damage(state.surface, 0, 0, state.width, state.height);
                wl_surface_commit(state.surface);
                NSLog(@"✅ Launcher: Redrawn buffer (%dx%d)", state.width, state.height);
            }
            wl_display_flush(client_display);
        }
    }
    
    // If we get here, dispatch returned -1 (error)
    NSLog(@"⚠️ Launcher: wl_display_dispatch returned error, disconnecting");
    
    NSLog(@"🛑 Launcher client disconnected");
    
    // Cleanup
    if (state.surface) {
        wl_surface_destroy(state.surface);
    }
    if (state.compositor) {
        wl_compositor_destroy(state.compositor);
    }
    wl_registry_destroy(registry);
    wl_display_disconnect(client_display);
    setClientDisplay(delegate, NULL);
    
    return NULL;
}

// Public function to start the launcher client thread
pthread_t startLauncherClientThread(WawonaAppDelegate *delegate, int client_fd) {
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    const char *wayland_display = getenv("WAYLAND_DISPLAY");
    const char *tcp_port = getenv("WAYLAND_TCP_PORT");
    
    // Check if Wayland environment is set up (either Unix socket or TCP or we have an FD)
    if (client_fd < 0 && !tcp_port && (!runtime_dir || !wayland_display)) {
        NSLog(@"⚠️ Wayland environment not set up - skipping launcher client");
        NSLog(@"   (Need either client_fd, WAYLAND_TCP_PORT or XDG_RUNTIME_DIR+WAYLAND_DISPLAY)");
        return NULL;
    }
    
    // Allocate arguments structure
    LauncherThreadArgs *args = malloc(sizeof(LauncherThreadArgs));
    if (!args) {
        NSLog(@"❌ Failed to allocate memory for launcher thread args");
        if (client_fd >= 0) close(client_fd);
        return NULL;
    }
    
    args->delegate = delegate;
    args->client_fd = client_fd;
    
    pthread_t thread;
    int ret = pthread_create(&thread, NULL, launcherClientThread, args);
    if (ret != 0) {
        NSLog(@"❌ Failed to create launcher client thread: %s", strerror(ret));
        free(args);
        if (client_fd >= 0) close(client_fd);
        return NULL;
    }
    
    // Detach thread so it cleans up automatically
    pthread_detach(thread);
    
    NSLog(@"✅ Launcher client thread started (in-process, App Store compliant)");
    return thread;
}

// Public function to get the client display from delegate
struct wl_display *getLauncherClientDisplay(WawonaAppDelegate *delegate) {
    return getClientDisplay(delegate);
}

// Public function to disconnect and cleanup the launcher client
void disconnectLauncherClient(WawonaAppDelegate *delegate) {
    struct wl_display *client_display = getClientDisplay(delegate);
    if (client_display) {
        wl_display_disconnect(client_display);
        setClientDisplay(delegate, NULL);
    }
}
