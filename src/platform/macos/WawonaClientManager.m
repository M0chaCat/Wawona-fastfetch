// WawonaClientManager.m - Client connection/disconnection and title management
// implementation Extracted from WawonaCompositor.m for better organization

#import "WawonaClientManager.h"
#include "../logging/logging.h"
#import "WawonaCompositor.h"

extern WawonaCompositor *g_wl_compositor_instance;

void macos_compositor_check_and_hide_window_if_needed(void) {
  if (!g_wl_compositor_instance) {
    return;
  }

  // Check if there are any remaining surfaces
  // We need to check the surfaces list from wayland_compositor.c
  // Since we can't directly access it, we'll use a callback mechanism
  // For now, we'll check if the window is shown and hide it
  // The actual surface count check will be done in client_destroy_listener
#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_wl_compositor_instance.windowShown &&
        g_wl_compositor_instance.window) {
      NSLog(@"[WINDOW] All clients disconnected - hiding window");
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      g_wl_compositor_instance.window.hidden = YES;
#else
            [g_wl_compositor_instance.window orderOut:nil];
#endif
      g_wl_compositor_instance.windowShown = NO;
    }
  });
#else
  // Android specific implementation if needed
#endif
}

void macos_compositor_handle_client_disconnect(void) {
  if (!g_wl_compositor_instance) {
    return;
  }

#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaCompositor *compositor = g_wl_compositor_instance;

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
                        [window performClose:nil];
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
  if (g_wl_compositor_instance->connectedClientCount > 0) {
    g_wl_compositor_instance->connectedClientCount--;
  }
  log_printf("FULLSCREEN", "Client disconnected. Connected clients: %d\n",
             g_wl_compositor_instance->connectedClientCount);
#endif
}

void macos_compositor_handle_client_connect(void) {
  if (!g_wl_compositor_instance) {
    return;
  }

#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaCompositor *compositor = g_wl_compositor_instance;

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
  g_wl_compositor_instance->connectedClientCount++;
  log_printf("FULLSCREEN", "Client connected. Connected clients: %d\n",
             g_wl_compositor_instance->connectedClientCount);
#endif
}

void macos_compositor_update_title_no_clients(void) {
  if (!g_wl_compositor_instance) {
    return;
  }

#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaCompositor *compositor = g_wl_compositor_instance;
    if (compositor.window) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      // iOS: Window titles not displayed
      (void)compositor;
#else
            [compositor.window setTitle:@"Wawona"];
#endif
      NSLog(@"[WINDOW] Updated titlebar title to: Wawona (no clients "
            @"connected)");
    }
  });
#else
  log_printf("WINDOW",
             "Updated titlebar title to: Wawona (no clients connected)\n");
#endif
}
