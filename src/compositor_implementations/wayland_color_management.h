#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>
#include <TargetConditionals.h>
#include <CoreGraphics/CoreGraphics.h>

#if !TARGET_OS_IPHONE
#include <ColorSync/ColorSync.h>
#endif

struct wl_output_impl;
struct wl_surface_impl;

struct wp_color_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
    struct wl_output_impl *output;
    
    // ColorSync integration
    CGColorSpaceRef display_color_space;
    bool hdr_supported;
    
    // Supported features
    uint32_t supported_features;
    uint32_t supported_intents;
    uint32_t supported_tf_named;
    uint32_t supported_primaries_named;
};

struct wp_color_management_output_impl {
    struct wl_resource *resource;
    struct wp_color_manager_impl *manager;
    struct wl_output_impl *output;
    struct wl_resource *output_resource;
    
    // Current output image description
    struct wp_image_description_impl *image_description;
};

struct wp_color_management_surface_impl {
    struct wl_resource *resource;
    struct wp_color_manager_impl *manager;
    struct wl_surface_impl *surface;
    struct wl_resource *surface_resource;
    
    // Pending state (double-buffered)
    struct wp_image_description_impl *pending_image_description;
    uint32_t pending_render_intent;
    
    // Current state
    struct wp_image_description_impl *current_image_description;
    uint32_t current_render_intent;
};

struct wp_color_management_surface_feedback_impl {
    struct wl_resource *resource;
    struct wp_color_manager_impl *manager;
    struct wl_surface_impl *surface;
    struct wl_resource *surface_resource;
    
    uint32_t preferred_identity;
};

struct wp_image_description_impl {
    struct wl_resource *resource;
    struct wp_color_manager_impl *manager;
    
    // Image description state
    bool ready;
    bool failed;
    uint32_t failure_cause;
    
    // Image description data
    bool is_icc;
    bool is_parametric;
    bool is_windows_scrgb;
    
    // ICC profile data
    CFDataRef icc_data;
    
    // Parametric data
    uint32_t primaries_named;
    int32_t r_x, r_y, g_x, g_y, b_x, b_y, w_x, w_y; // chromaticity coordinates
    uint32_t tf_named;
    uint32_t tf_power_eexp;
    uint32_t min_lum, max_lum, reference_lum;
    int32_t target_r_x, target_r_y, target_g_x, target_g_y, target_b_x, target_b_y, target_w_x, target_w_y;
    uint32_t target_min_lum, target_max_lum;
    uint32_t target_max_cll, target_max_fall;
    bool target_primaries_set;
    bool target_luminance_set;
    bool target_max_cll_set;
    bool target_max_fall_set;
    
    // ColorSync representation
    CGColorSpaceRef color_space;
    
    // Identity for tracking
    uint32_t identity;
};

struct wp_image_description_creator_icc_impl {
    struct wl_resource *resource;
    struct wp_color_manager_impl *manager;
    
    CFDataRef icc_data;
    bool icc_set;
};

struct wp_image_description_creator_params_impl {
    struct wl_resource *resource;
    struct wp_color_manager_impl *manager;
    
    // Required parameters
    bool tf_set;
    bool primaries_set;
    
    // Optional parameters
    bool luminances_set;
    bool target_primaries_set;
    bool target_luminance_set;
    bool target_max_cll_set;
    bool target_max_fall_set;
    
    // Parameter values
    uint32_t tf_named;
    uint32_t tf_power_eexp;
    uint32_t primaries_named;
    int32_t r_x, r_y, g_x, g_y, b_x, b_y, w_x, w_y;
    uint32_t min_lum, max_lum, reference_lum;
    int32_t target_r_x, target_r_y, target_g_x, target_g_y, target_b_x, target_b_y, target_w_x, target_w_y;
    uint32_t target_min_lum, target_max_lum;
    uint32_t target_max_cll, target_max_fall;
};

struct wp_image_description_info_impl {
    struct wl_resource *resource;
    struct wp_image_description_impl *image_description;
};

// Global counter for image description identities
extern uint32_t g_image_description_identity_counter;

struct wp_color_manager_impl *wp_color_manager_create(struct wl_display *display, struct wl_output_impl *output);
void wp_color_manager_destroy(struct wp_color_manager_impl *manager);

// Helper functions for ColorSync integration
CGColorSpaceRef create_colorspace_from_image_description(struct wp_image_description_impl *desc);
bool detect_hdr_support(void);
CGColorSpaceRef get_display_color_space(void);

