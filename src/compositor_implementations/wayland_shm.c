#include "wayland_shm.h"
#include <wayland-server-protocol.h>
#include <stdlib.h>
#include <stdio.h>

static void
shm_create_pool(struct wl_client *client, struct wl_resource *resource, uint32_t id, int32_t fd, int32_t size)
{
    // Implementation is handled by libwayland-server internal shm implementation usually?
    // Wait, if we are implementing wl_shm global, we need to handle create_pool.
    // However, usually we use wl_display_init_shm(display) provided by libwayland-server.
    // Let's check if we can just use that.
    // But here we have our own struct wl_shm_impl.
    
    // If we use wl_display_init_shm, we don't need to implement the interface manually.
    // But maybe we are wrapping it?
    // Let's assume we use the built-in one if possible, but the header suggests we have our own.
    
    // Actually, wl_display_init_shm() handles everything including the global.
    // If we call wl_display_init_shm(display), we don't need to create a global manually.
    // So wl_shm_create might just call wl_display_init_shm(display).
}

struct wl_shm_impl *
wl_shm_create(struct wl_display *display)
{
    struct wl_shm_impl *shm = calloc(1, sizeof(struct wl_shm_impl));
    if (!shm) return NULL;

    shm->display = display;
    
    // Use libwayland's built-in shm implementation
    if (wl_display_init_shm(display) < 0) {
        free(shm);
        return NULL;
    }
    
    // We don't get a handle to the global from wl_display_init_shm easily,
    // but that's fine, we don't need to manage it if libwayland does.
    // However, our struct implies we store the global.
    // If we use built-in, we can't store the global pointer easily (it's internal).
    // So shm->global will be NULL.
    
    return shm;
}

void
wl_shm_destroy(struct wl_shm_impl *shm)
{
    if (!shm) return;
    // We can't easily destroy the built-in shm global without destroying the display?
    // Actually, libwayland doesn't expose a way to destroy shm global specifically.
    // But it cleans up on display destroy.
    
    free(shm);
}
