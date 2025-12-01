#include "egl_buffer_handler.h"
int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) { (void)handler; (void)display; return -1; }
void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) { (void)handler; }
int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler, struct wl_resource *buffer_resource, int32_t *width, int32_t *height, EGLint *texture_format) { (void)handler; (void)buffer_resource; if (width) *width = 0; if (height) *height = 0; if (texture_format) *texture_format = 0; return -1; }
EGLImageKHR egl_buffer_handler_create_image(struct egl_buffer_handler *handler, struct wl_resource *buffer_resource) { (void)handler; (void)buffer_resource; return (EGLImageKHR)0; }
bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler, struct wl_resource *buffer_resource) { (void)handler; (void)buffer_resource; return false; }
