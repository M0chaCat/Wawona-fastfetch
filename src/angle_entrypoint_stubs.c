#include <EGL/egl.h>
#include <EGL/eglext.h>
EGLDisplay eglGetPlatformDisplayEXT(EGLenum platform, void* native_display, const EGLAttrib* attrib_list) { return EGL_NO_DISPLAY; }
EGLBoolean eglSwapBuffersWithDamageEXT(EGLDisplay dpy, EGLSurface surface, const EGLint* rects, EGLint n_rects) { return EGL_FALSE; }
EGLImageKHR eglCreateImageKHR(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buffer, const EGLint* attrib_list) { return (EGLImageKHR)0; }
EGLBoolean eglDestroyImageKHR(EGLDisplay dpy, EGLImageKHR image) { return EGL_FALSE; }
EGLBoolean eglBindTexImage(EGLDisplay dpy, EGLSurface surface, EGLint buffer) { return EGL_FALSE; }
EGLBoolean eglReleaseTexImage(EGLDisplay dpy, EGLSurface surface, EGLint buffer) { return EGL_FALSE; }
