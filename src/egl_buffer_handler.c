#include <TargetConditionals.h>
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

#include "egl_buffer_handler.h"
#include <stdbool.h>
extern bool wawona_is_egl_enabled(void);
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Define EGL extensions prototypes to use them directly
#define EGL_EGLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>


// Fallback definition for surfaceless platform if missing
#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif
static void egl_buffer_handler_translation_unit_silence(void) {}

// Helper to check extensions
static bool has_extension(const char *extensions, const char *ext) {
    if (!extensions || !ext) return false;
    const char *start = extensions;
    while (true) {
        const char *where = strstr(start, ext);
        if (!where) return false;
        const char *term = where + strlen(ext);
        if ((where == start || *(where - 1) == ' ') &&
            (*term == ' ' || *term == '\0')) {
            return true;
        }
        start = term;
    }
}

int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
    if (!wawona_is_egl_enabled()) {
        return -1;
    }
    if (!handler || !display) return -1;
    
    handler->initialized = false;
    handler->display_bound = false;
    handler->egl_display = EGL_NO_DISPLAY;
    handler->egl_context = EGL_NO_CONTEXT;
    handler->egl_config = NULL;

    // 1. Get EGL Display
    // Try Surfaceless platform first (common for Zink/Mesa without window system)
    // We cast to void* because the signature expects void* for native display
    // But for surfaceless, the native display argument is usually NULL or specific
    
    // Check if we can use eglGetPlatformDisplay (EGL 1.5+)
    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplay = 
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
        
    if (!getPlatformDisplay) {
        getPlatformDisplay = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplay");
    }

    if (getPlatformDisplay) {
        // Try surfaceless
        handler->egl_display = getPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, NULL, NULL);
        
        // If that fails, try device platform
        if (handler->egl_display == EGL_NO_DISPLAY) {
             // Maybe try standard eglGetDisplay(EGL_DEFAULT_DISPLAY)
             handler->egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        }
    } else {
        handler->egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    }

    if (handler->egl_display == EGL_NO_DISPLAY) {
        fprintf(stderr, "[EGL] Failed to get EGL display\n");
        return -1;
    }

    // 2. Initialize EGL
    EGLint major, minor;
    if (!eglInitialize(handler->egl_display, &major, &minor)) {
        fprintf(stderr, "[EGL] Failed to initialize EGL\n");
        return -1;
    }
    printf("[EGL] Initialized EGL %d.%d\n", major, minor);
    
    const char *extensions = eglQueryString(handler->egl_display, EGL_EXTENSIONS);
    printf("[EGL] Extensions: %s\n", extensions ? extensions : "NULL");

    // 3. Bind Wayland Display
    // This allows creating EGLImages from Wayland buffers
    if (has_extension(extensions, "EGL_WL_bind_wayland_display")) {
        PFNEGLBINDWAYLANDDISPLAYWL bindWaylandDisplay = 
            (PFNEGLBINDWAYLANDDISPLAYWL)eglGetProcAddress("eglBindWaylandDisplayWL");
        
        if (bindWaylandDisplay) {
            if (bindWaylandDisplay(handler->egl_display, display)) {
                handler->display_bound = true;
                printf("[EGL] Bound Wayland display successfully\n");
            } else {
                fprintf(stderr, "[EGL] Failed to bind Wayland display\n");
            }
        }
    } else {
        fprintf(stderr, "[EGL] EGL_WL_bind_wayland_display not supported\n");
    }

    // 4. Create a context (optional, but good for verification)
    // We might need a config.
    EGLint config_attribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, // Surfaceless can use pbuffer or nothing
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    
    EGLint num_configs;
    if (eglChooseConfig(handler->egl_display, config_attribs, &handler->egl_config, 1, &num_configs) && num_configs > 0) {
        EGLint context_attribs[] = {
            EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL_NONE
        };
        
        eglBindAPI(EGL_OPENGL_ES_API);
        handler->egl_context = eglCreateContext(handler->egl_display, handler->egl_config, EGL_NO_CONTEXT, context_attribs);
        if (handler->egl_context == EGL_NO_CONTEXT) {
            fprintf(stderr, "[EGL] Failed to create EGL context\n");
        } else {
            printf("[EGL] Created EGL context\n");
        }
    } else {
        fprintf(stderr, "[EGL] Failed to choose config\n");
    }

    handler->initialized = true;
    return 0;
}

void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
    if (!handler) return;
    
    if (handler->egl_display != EGL_NO_DISPLAY) {
        if (handler->egl_context != EGL_NO_CONTEXT) {
            eglDestroyContext(handler->egl_display, handler->egl_context);
        }
        
        if (handler->display_bound) {
            // Optional: unbind Wayland display. We don't store wl_display in handler,
            // and unbinding is not strictly required during teardown.
        }
        
        eglTerminate(handler->egl_display);
    }
}

int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler, struct wl_resource *buffer_resource, int32_t *width, int32_t *height, EGLint *texture_format) {
    if (!handler || !handler->initialized || !handler->display_bound) return -1;
    
    PFNEGLQUERYWAYLANDBUFFERWL queryBuffer = 
        (PFNEGLQUERYWAYLANDBUFFERWL)eglGetProcAddress("eglQueryWaylandBufferWL");
    
    if (!queryBuffer) return -1;
    
    EGLint w, h, fmt;
    if (!queryBuffer(handler->egl_display, buffer_resource, EGL_WIDTH, &w)) return -1;
    if (!queryBuffer(handler->egl_display, buffer_resource, EGL_HEIGHT, &h)) return -1;
    if (!queryBuffer(handler->egl_display, buffer_resource, EGL_TEXTURE_FORMAT, &fmt)) return -1;
    
    if (width) *width = w;
    if (height) *height = h;
    if (texture_format) *texture_format = fmt;
    
    return 0;
}

EGLImageKHR egl_buffer_handler_create_image(struct egl_buffer_handler *handler, struct wl_resource *buffer_resource) {
    if (!wawona_is_egl_enabled()) {
        return (EGLImageKHR)NULL;
    }
    if (!handler || !handler->initialized || !handler->display_bound) return EGL_NO_IMAGE_KHR;
    
    // EGL_WAYLAND_BUFFER_WL = 0x31D5
    // We create image from the buffer resource
    EGLint attribs[] = { EGL_NONE };
    
    EGLImage image_core = eglCreateImage(handler->egl_display, EGL_NO_CONTEXT,
                                         EGL_WAYLAND_BUFFER_WL,
                                         buffer_resource, (const EGLAttrib*)attribs);
    EGLImageKHR image = (EGLImageKHR)image_core;
                                          
    return image;
}

bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler, struct wl_resource *buffer_resource) {
    if (!handler || !handler->initialized || !handler->display_bound) return false;
    
    int32_t w, h;
    EGLint fmt;
    return egl_buffer_handler_query_buffer(handler, buffer_resource, &w, &h, &fmt) == 0;
}
#endif
