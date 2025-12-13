#include "wayland_linux_dmabuf.h"
#include "protocols/linux-dmabuf-unstable-v1-protocol.h"
#include "metal_dmabuf.h"
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <assert.h>

struct params {
    struct wl_resource *resource;
    uint32_t width;
    uint32_t height;
    uint32_t format;
    uint32_t flags;
    
    int fd[4];
    uint32_t offset[4];
    uint32_t stride[4];
    uint64_t modifier[4];
    int n_planes;
};

static void
buffer_destroy(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static const struct wl_buffer_interface buffer_interface = {
    .destroy = buffer_destroy,
};

static void
buffer_resource_destroy(struct wl_resource *resource)
{
    struct metal_dmabuf_buffer *buffer = wl_resource_get_user_data(resource);
    if (buffer) {
        metal_dmabuf_destroy_buffer(buffer);
    }
}

static void
params_destroy(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static void
params_resource_destroy(struct wl_resource *resource)
{
    struct params *params = wl_resource_get_user_data(resource);
    int i;
    
    for (i = 0; i < params->n_planes; i++) {
        if (params->fd[i] != -1) {
            close(params->fd[i]);
        }
    }
    free(params);
}

static void
params_add(struct wl_client *client, struct wl_resource *resource,
           int32_t fd, uint32_t plane_idx, uint32_t offset, uint32_t stride,
           uint32_t modifier_hi, uint32_t modifier_lo)
{
    struct params *params = wl_resource_get_user_data(resource);
    uint64_t modifier = ((uint64_t)modifier_hi << 32) | modifier_lo;

    if (plane_idx >= 4) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_IDX,
                               "plane index %u out of bounds", plane_idx);
        close(fd);
        return;
    }

    if (params->fd[plane_idx] != -1) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_SET,
                               "plane index %u already set", plane_idx);
        close(fd);
        return;
    }

    params->fd[plane_idx] = fd;
    params->offset[plane_idx] = offset;
    params->stride[plane_idx] = stride;
    params->modifier[plane_idx] = modifier;
    params->n_planes++;
}

static void
params_create_common(struct wl_client *client, struct wl_resource *resource,
                     uint32_t buffer_id, int32_t width, int32_t height,
                     uint32_t format, uint32_t flags)
{
    struct params *params = wl_resource_get_user_data(resource);
    struct wl_resource *buffer_resource;
    struct metal_dmabuf_buffer *buffer;
    int fd;
    uint32_t stride;
    int import_fd;

    if (params->n_planes == 0) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INCOMPLETE,
                               "no planes added");
        return;
    }

    // Currently only support 1 plane for simplified IOSurface mapping
    // If multi-planar support is needed, we would need to handle it in metal_dmabuf
    if (params->n_planes > 1) {
        printf("Warning: Multi-planar dmabuf not fully supported yet, using plane 0\n");
    }
    
    fd = params->fd[0];
    stride = params->stride[0];
    
    // Duplicate FD because import takes ownership or we need to keep it if import fails?
    // metal_dmabuf_import closes the FD.
    // So we should duplicate if we want to keep params valid?
    // But params are destroyed after create usually.
    // However, if we pass params->fd[0], metal_dmabuf_import closes it.
    // We should mark it as closed in params to avoid double close in destroy.
    
    import_fd = dup(fd);
    if (import_fd < 0) {
        goto err_out;
    }

    buffer = metal_dmabuf_import(import_fd, width, height, format, stride);
    if (!buffer) {
        goto err_out;
    }

    buffer_resource = wl_resource_create(client, &wl_buffer_interface, 1, buffer_id);
    if (!buffer_resource) {
        metal_dmabuf_destroy_buffer(buffer);
        wl_resource_post_no_memory(resource);
        return;
    }

    wl_resource_set_implementation(buffer_resource, &buffer_interface, buffer, buffer_resource_destroy);

    // If create request (not immediate), send success event
    if (wl_resource_get_version(resource) < ZWP_LINUX_BUFFER_PARAMS_V1_CREATE_IMMED_SINCE_VERSION) {
        zwp_linux_buffer_params_v1_send_created(resource, buffer_resource);
    }

    return;

err_out:
    if (wl_resource_get_version(resource) < ZWP_LINUX_BUFFER_PARAMS_V1_CREATE_IMMED_SINCE_VERSION) {
        zwp_linux_buffer_params_v1_send_failed(resource);
    } else {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER,
                               "failed to import dmabuf");
    }
}

static void
params_create(struct wl_client *client, struct wl_resource *resource,
              int32_t width, int32_t height, uint32_t format, uint32_t flags)
{
    params_create_common(client, resource, 0, width, height, format, flags);
}

static void
params_create_immed(struct wl_client *client, struct wl_resource *resource,
                    uint32_t buffer_id, int32_t width, int32_t height,
                    uint32_t format, uint32_t flags)
{
    params_create_common(client, resource, buffer_id, width, height, format, flags);
}

static const struct zwp_linux_buffer_params_v1_interface params_interface = {
    .destroy = params_destroy,
    .add = params_add,
    .create = params_create,
    .create_immed = params_create_immed,
};

static void
dmabuf_destroy(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static void
dmabuf_create_params(struct wl_client *client, struct wl_resource *resource, uint32_t params_id)
{
    struct wl_resource *params_resource;
    struct params *params;
    int i;

    params = calloc(1, sizeof(*params));
    if (!params) {
        wl_resource_post_no_memory(resource);
        return;
    }

    for (i = 0; i < 4; i++) {
        params->fd[i] = -1;
    }

    params_resource = wl_resource_create(client, &zwp_linux_buffer_params_v1_interface,
                                         wl_resource_get_version(resource), params_id);
    if (!params_resource) {
        free(params);
        wl_resource_post_no_memory(resource);
        return;
    }

    params->resource = params_resource;
    wl_resource_set_implementation(params_resource, &params_interface, params, params_resource_destroy);
}

static void
dmabuf_get_default_feedback(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    // Version 4+ only
    // Stub or implement if needed
    // For now, ignore as Waypipe likely uses v3 or handles missing feedback
}

static void
dmabuf_get_surface_feedback(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface)
{
    // Version 4+ only
}

static const struct zwp_linux_dmabuf_v1_interface dmabuf_interface = {
    .destroy = dmabuf_destroy,
    .create_params = dmabuf_create_params,
    .get_default_feedback = dmabuf_get_default_feedback,
    .get_surface_feedback = dmabuf_get_surface_feedback,
};

static void
bind_dmabuf(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wl_resource *resource;

    resource = wl_resource_create(client, &zwp_linux_dmabuf_v1_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &dmabuf_interface, data, NULL);

    // Advertise formats
    // We support ARGB8888 and XRGB8888 (standard Wayland formats)
    // In drm_fourcc.h:
    // DRM_FORMAT_ARGB8888 'A', 'R', '2', '4' (little endian) -> 0x34325241
    // DRM_FORMAT_XRGB8888 'X', 'R', '2', '4' -> 0x34325258
    // Since we don't include drm_fourcc.h, we can hardcode or include it.
    // Wayland uses WL_SHM_FORMAT_* which matches DRM_FORMAT_* usually.
    
    // WL_SHM_FORMAT_ARGB8888 = 0
    // WL_SHM_FORMAT_XRGB8888 = 1
    // Wait, DRM_FORMAT is NOT same as WL_SHM_FORMAT enum values.
    // WL_SHM_FORMAT_ARGB8888 value IS 'AR24'.
    
    // Let's send standard formats.
    zwp_linux_dmabuf_v1_send_format(resource, 0x34325241); // ARGB8888
    zwp_linux_dmabuf_v1_send_format(resource, 0x34325258); // XRGB8888
    
    // Also send modifiers if version >= 3
    if (version >= 3) {
        // DRM_FORMAT_MOD_INVALID = 0x00ffffffffffffffULL
        // DRM_FORMAT_MOD_LINEAR = 0
        // We use linear buffers (IOSurface)
        zwp_linux_dmabuf_v1_send_modifier(resource, 0x34325241, 0, 0);
        zwp_linux_dmabuf_v1_send_modifier(resource, 0x34325258, 0, 0);
    }
}

struct zwp_linux_dmabuf_v1_impl *
zwp_linux_dmabuf_v1_create(struct wl_display *display)
{
    struct zwp_linux_dmabuf_v1_impl *impl;

    impl = calloc(1, sizeof(*impl));
    if (!impl) return NULL;

    impl->display = display;
    impl->global = wl_global_create(display, &zwp_linux_dmabuf_v1_interface, 3, impl, bind_dmabuf);
    
    if (!impl->global) {
        free(impl);
        return NULL;
    }

    return impl;
}

// Helpers for renderer to check if buffer is dmabuf
int
is_dmabuf_buffer(struct wl_resource *resource)
{
    if (wl_resource_instance_of(resource, &wl_buffer_interface, &buffer_interface)) {
        return 1;
    }
    return 0;
}

struct metal_dmabuf_buffer *
dmabuf_buffer_get(struct wl_resource *resource)
{
    if (is_dmabuf_buffer(resource)) {
        return wl_resource_get_user_data(resource);
    }
    return NULL;
}
