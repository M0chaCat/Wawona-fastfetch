#include "wayland_color_management.h"
#include "color-management-v1-protocol.h"
#include "WawonaCompositor.h"
#include <TargetConditionals.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

uint32_t g_image_description_identity_counter = 1;

static void
wp_color_manager_destroy_resource(struct wl_resource *resource)
{
    struct wp_color_manager_impl *manager = wl_resource_get_user_data(resource);
    (void)manager;
    // Don't free manager here as it's owned by the compositor
}

static void
wp_color_manager_destroy_request(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static void
wp_color_manager_get_output(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *output)
{
    (void)client; (void)resource; (void)id; (void)output;
    // Implementation for get_output
    // TODO: Connect output to color management
}

static void
wp_color_manager_get_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface)
{
    (void)client; (void)resource; (void)id; (void)surface;
    // Implementation for get_surface
    // TODO: Connect surface to color management
}

static void
wp_color_manager_create_icc_creator(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    (void)client; (void)resource; (void)id;
    // Implementation for create_icc_creator
}

static void
wp_color_manager_create_parametric_creator(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    (void)client; (void)resource; (void)id;
    // Implementation for create_parametric_creator
}

static const struct wp_color_manager_v1_interface color_manager_impl = {
    .destroy = wp_color_manager_destroy_request,
    .get_output = wp_color_manager_get_output,
    .get_surface = wp_color_manager_get_surface,
    .create_icc_creator = wp_color_manager_create_icc_creator,
    .create_parametric_creator = wp_color_manager_create_parametric_creator,
};

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
static void
bind_color_manager(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wp_color_manager_impl *manager = data;
    struct wl_resource *resource = wl_resource_create(client, &wp_color_manager_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &color_manager_impl, manager, wp_color_manager_destroy_resource);
}
#endif

struct wp_color_manager_impl *
wp_color_manager_create(struct wl_display *display, struct wl_output_impl *output)
{
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    struct wp_color_manager_impl *manager = calloc(1, sizeof(struct wp_color_manager_impl));
    if (!manager) return NULL;

    manager->display = display;
    manager->output = output;
    
    manager->display_color_space = get_display_color_space();
    manager->hdr_supported = detect_hdr_support();
    
    manager->global = wl_global_create(display, &wp_color_manager_v1_interface, 1, manager, bind_color_manager);
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    return manager;
#else
    (void)display; (void)output;
    return NULL;
#endif
}

void
wp_color_manager_destroy(struct wp_color_manager_impl *manager)
{
    if (!manager) return;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (manager->global) wl_global_destroy(manager->global);
#endif
    if (manager->display_color_space) CGColorSpaceRelease(manager->display_color_space);
    free(manager);
}

// ColorSync Integration Helpers

CGColorSpaceRef
get_display_color_space(void)
{
#if !TARGET_OS_IPHONE
    // Get the main display color space
    CGColorSpaceRef space = CGDisplayCopyColorSpace(CGMainDisplayID());
    if (space) return space;
#endif
    
    // Fallback to sRGB
    return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
}

bool
detect_hdr_support(void)
{
#if !TARGET_OS_IPHONE
#if defined(MAC_OS_X_VERSION_10_15) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_15
    // Simple check for HDR support
    // In a real implementation, we would check the specific display capabilities
    // For now, we assume modern Macs might support it if the OS is new enough
    return true; 
#else
    return false;
#endif
#else
    // iOS: HDR support depends on device, for now assume false or check specific APIs
    return false;
#endif
}

CGColorSpaceRef
create_colorspace_from_image_description(struct wp_image_description_impl *desc)
{
    if (!desc) return NULL;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (desc->is_icc && desc->icc_data) {
        return CGColorSpaceCreateWithICCProfile(desc->icc_data);
    }
    if (desc->is_parametric) {
        if (desc->tf_named == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ) {
             return CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020_PQ_EOTF);
        } else if (desc->primaries_named == WP_COLOR_MANAGER_V1_PRIMARIES_BT2020) {
            return CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020);
        } else if (desc->primaries_named == WP_COLOR_MANAGER_V1_PRIMARIES_DCI_P3) {
             return CGColorSpaceCreateWithName(kCGColorSpaceDCIP3);
        }
    }
#endif
    return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
}
