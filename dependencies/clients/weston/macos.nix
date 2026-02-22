{ lib, stdenv, fetchurl, meson, ninja, pkg-config, wayland, wayland-scanner, wayland-protocols, libxkbcommon, cairo, pango, libpng, libjpeg, mesa, pixman, python3, libinput, libevdev, seatd, pam, openssl, epoll-shim, ... }:

stdenv.mkDerivation rec {
  pname = "weston";
  version = "13.0.0";

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };
  
  # Fetch linux input headers for macOS shim
  linux_input_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/master/include/uapi/linux/input.h";
    sha256 = "sha256-ciO4IN6ANMgnw/yBe2dApcUcqDMkgLhtagwUJzD7I54="; 
  };
  linux_input_event_codes_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/master/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-ORbz0jviAG+Hqy5+4vVqyGSWax9lDHaJwMpDUTSGHsk=";
  };
  libdrm_fourcc_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/main/include/drm/drm_fourcc.h";
    sha256 = "sha256-qFbvL2tD6PeyaHFZThkYZMVAoDcg1xwT7opFDSarxi0=";
  };
  libdrm_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/main/include/drm/drm.h";
    sha256 = "sha256-+erb+g+eGurMJ/XJMco717RpdNutgXzQL+YBzLXN8I0=";
  };
  libdrm_mode_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/main/include/drm/drm_mode.h";
    sha256 = "sha256-7kBowCbftshcZoy05B/5y/MOmcEMXn7yrRx4cNP5o78=";
  };
  libdrm_xf86drm_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/main/xf86drm.h";
    sha256 = "sha256-X62GrL3cw7amhWkNoMfeWUEtNU0TdWRHNGcvXGvfQgI=";
  };

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner python3 ];

  buildInputs = [
    wayland
    wayland-protocols
    libxkbcommon
    cairo
    pango
    libpng
    epoll-shim
    libjpeg
    mesa
    pixman
    openssl
  ];

  mesonFlags = [
    "-Dbackend-drm=false"
    "-Dbackend-headless=true"
    "-Dbackend-rdp=false"
    "-Dbackend-vnc=false"
    "-Dbackend-pipewire=false"
    "-Dbackend-wayland=false"
    "-Dbackend-x11=false"
    "-Dxwayland=false"
    "-Dbackend-default=headless"
    "-Drenderer-gl=false"
    "-Dimage-jpeg=true"
    "-Dimage-webp=false"
    "-Ddemo-clients=true"
    "-Dsimple-clients=damage,im,shm,touch"
    "-Dtest-junit-xml=false"
    "-Ddoc=false"
    "-Dpipewire=false"
    "-Dsystemd=false"
    "-Dcolor-management-lcms=false"
  ] ++ lib.optionalString stdenv.isDarwin [
    "-Dremoting=false"
    "-Dshell-fullscreen=false"
    "-Dshell-ivi=false"
    "-Dshell-kiosk=false"
  ];

  preConfigure = ''
    # Create the polyfill header
    mkdir -p include
    cat > include/weston-macos-polyfills.h <<'EOF'
#ifndef WESTON_MACOS_POLYFILLS_H
#define WESTON_MACOS_POLYFILLS_H
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

#ifdef __APPLE__
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};

#define WESTON_HOWMANY(x, y) (((int)(x) + (int)(y) - 1) / (int)(y))

static inline int pipe2(int fds[2], int flags) {
    if (pipe(fds) != 0) return -1;
    if (flags & O_CLOEXEC) {
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    }
    if (flags & O_NONBLOCK) {
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);
    }
    return 0;
}

/* Weston provides the definition in os-compatibility.c, we just need the declaration */
char *strchrnul(const char *s, int c);
#endif
#endif
EOF

    mesonFlagsArray+=(
      "-Dc_args=-I${epoll-shim}/include/libepoll-shim -I$PWD/include -include $PWD/include/weston-macos-polyfills.h -Dprogram_invocation_short_name=getprogname() -DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC"
      "-Dc_link_args=-L${epoll-shim}/lib -lepoll-shim"
      "-Dcpp_link_args=-L${epoll-shim}/lib -lepoll-shim"
      "-Ddemo-clients=false"
    )
  '';
  
  NIX_CFLAGS_COMPILE = "-I${epoll-shim}/include/libepoll-shim -I$PWD/include";
  NIX_LDFLAGS = "-L${epoll-shim}/lib -lepoll-shim";

  postPatch = lib.optionalString stdenv.isDarwin ''
    # Skip building problematic subdirectories
    sed -i "/subdir('compositor')/d" meson.build
    sed -i "/subdir('tests')/d" meson.build
    sed -i "/subdir('desktop-shell')/d" meson.build
    
    # Remove subsurfaces client which depends heavily on GLES2
    sed -i "/'subsurfaces.c'/d" clients/meson.build
    
    # Create an empty C file to replace problematic sources while keeping Meson syntax intact
    touch include/empty.c

    # Replace libinput source files with our empty file
    sed -i "s/'libinput-device.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.h'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-device.h'/'..\/include\/empty.c'/g" libweston/meson.build

    # Patch backend default logic
    sed -i "s|message('The default backend is ' + backend_default)|message('Skipping backend validation for client-only build')|g" meson.build
    
    # Make all Linux-specific dependencies optional
    sed -i "s/dependency('libinput'/dependency('libinput', required: false/g" meson.build
    sed -i "s/dependency('libevdev'/dependency('libevdev', required: false/g" meson.build
    sed -i "s/dependency('libdrm'/dependency('libdrm', required: false/g" meson.build
    sed -i "s/cc.find_library('pam'/cc.find_library('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('pam'/dependency('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" clients/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" tests/meson.build
    
    # Downgrade errors to warnings in clients
    sed -i "s/error(/warning(/g" clients/meson.build

    # Patch terminal.c to use our safe HOWMANY macro
    sed -i "s/\bhowmany\b/WESTON_HOWMANY/g" clients/terminal.c
    
    # Create inclusive directory for shims
    mkdir -p include/sys include/libudev include/libinput include/linux include/libevdev include/GLES2 include/EGL include/KHR
    
    # Create GLES2/gl2.h shim
    cat > include/GLES2/gl2.h <<'EOF'
#ifndef _GL2_H
#define _GL2_H
#include <stdint.h>
typedef float GLfloat;
typedef int GLint;
typedef uint32_t GLuint;
typedef uint32_t GLbitfield;
typedef int GLsizei;
typedef unsigned char GLboolean;
typedef unsigned char GLubyte;
typedef float GLclampf;
typedef void GLvoid;
typedef intptr_t GLintptr;
typedef size_t GLsizeiptr;
typedef char GLchar;
typedef uint32_t GLenum;
#endif
EOF
    touch include/GLES2/glext.h

    # Create EGL shims
    cat > include/EGL/egl.h <<'EOF'
#ifndef _EGL_H
#define _EGL_H
#include <stdint.h>
#include <EGL/eglplatform.h>
typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLContext;
typedef void *EGLSurface;
typedef void *EGLClientBuffer;
typedef void (*__eglMustCastToProperFunctionPointerType)(void);
#define EGL_DEFAULT_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_RED_SIZE 0x3024
#define EGL_GREEN_SIZE 0x3023
#define EGL_BLUE_SIZE 0x3022
#define EGL_ALPHA_SIZE 0x3021
#define EGL_DEPTH_SIZE 0x3025
#define EGL_STENCIL_SIZE 0x3026
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_OPENGL_ES_API 0x30A0
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_NONE 0x3038
#define EGL_TRUE 1
#define EGL_FALSE 0
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
typedef unsigned int EGLenum;
EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list, EGLConfig *configs, EGLint config_size, EGLint *num_config);
EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *attrib_list);
EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx);
EGLDisplay eglGetDisplay(EGLNativeDisplayType display_id);
EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor);
EGLBoolean eglBindAPI(EGLenum api);
EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list);
EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface);
EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx);
EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface);
EGLBoolean eglTerminate(EGLDisplay dpy);
__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *procname);
#endif
EOF
    touch include/EGL/eglext.h
    cat > include/EGL/eglplatform.h <<'EOF'
#ifndef _EGLPLATFORM_H
#define _EGLPLATFORM_H
#include <KHR/khrplatform.h>
typedef void *EGLNativeDisplayType;
typedef void *EGLNativePixmapType;
typedef void *EGLNativeWindowType;
#endif
EOF
    cat > include/KHR/khrplatform.h <<'EOF'
#ifndef _KHRPLATFORM_H
#define _KHRPLATFORM_H
#include <stdint.h>
#endif
EOF

    # Create libudev.h shim
    cat > include/libudev.h <<'EOF'
#ifndef _LIBUDEV_H
#define _LIBUDEV_H
struct udev;
struct udev_device;
struct udev_monitor;
struct udev_enumerate;
struct udev_list_entry;
#endif
EOF

    # Create libinput.h shim
    cat > include/libinput.h <<'EOF'
#ifndef _LIBINPUT_H
#define _LIBINPUT_H
#include <stdint.h>
struct libinput;
struct libinput_device;
struct libinput_event;
struct libinput_event_keyboard;
struct libinput_event_pointer;
struct libinput_seat;
enum libinput_led { LIBINPUT_LED_NUM_LOCK, LIBINPUT_LED_CAPS_LOCK, LIBINPUT_LED_SCROLL_LOCK };
enum libinput_key_state { LIBINPUT_KEY_STATE_RELEASED, LIBINPUT_KEY_STATE_PRESSED };
enum libinput_device_capability { LIBINPUT_DEVICE_CAP_POINTER };
static inline void* libinput_device_get_user_data(struct libinput_device *d) { return (void*)0; }
static inline int libinput_device_has_capability(struct libinput_device *d, int c) { return 0; }
static inline int libinput_event_keyboard_get_key_state(struct libinput_event_keyboard *e) { return 0; }
static inline int libinput_event_keyboard_get_seat_key_count(struct libinput_event_keyboard *e) { return 0; }
static inline uint64_t libinput_event_keyboard_get_time_usec(struct libinput_event_keyboard *e) { return 0; }
static inline uint32_t libinput_event_keyboard_get_key(struct libinput_event_keyboard *e) { return 0; }
static inline void libinput_device_led_update(struct libinput_device *d, int l) {}
static inline void* libinput_event_keyboard_get_device(struct libinput_event_keyboard *e) { return (void*)0; }
#endif
EOF

    # Create gbm.h shim
    cat > include/gbm.h <<'EOF'
#ifndef _GBM_H
#define _GBM_H
#include <stdint.h>
struct gbm_device;
struct gbm_bo;
struct gbm_surface;
#endif
EOF

    # Create pty.h shim
    cat > include/pty.h <<'EOF'
#ifndef _PTY_H
#define _PTY_H
#include <util.h>
#endif
EOF

    # Create values.h shim for legacy code
    cat > include/values.h <<'EOF'
#ifndef _VALUES_H
#define _VALUES_H
#include <limits.h>
#include <float.h>
#endif
EOF

    # Create endian.h shim
    cat > include/endian.h <<'EOF'
#ifndef _ENDIAN_H
#define _ENDIAN_H
#include <machine/endian.h>
#define __BYTE_ORDER BYTE_ORDER
#define __LITTLE_ENDIAN LITTLE_ENDIAN
#define __BIG_ENDIAN BIG_ENDIAN
#endif
EOF

    # Create alloca.h shim
    cat > include/alloca.h <<'EOF'
#ifndef _ALLOCA_H
#define _ALLOCA_H
#include <stdlib.h>
#endif
EOF
    
    # Inject linux/input.h shims
    cp ${linux_input_h} include/linux/input.h
    cp ${linux_input_event_codes_h} include/linux/input-event-codes.h
    cat > include/linux/ioctl.h <<'EOF'
#ifndef _LINUX_IOCTL_H
#define _LINUX_IOCTL_H
#include <sys/ioctl.h>
#endif
EOF
    
    # Create linux/types.h shim
    cat > include/linux/types.h <<'EOF'
#ifndef _LINUX_TYPES_H
#define _LINUX_TYPES_H
#include <stdint.h>
typedef uint8_t __u8;
typedef uint16_t __u16;
typedef uint32_t __u32;
typedef uint64_t __u64;
typedef int8_t __s8;
typedef int16_t __s16;
typedef int32_t __s32;
typedef int64_t __s64;
typedef uint16_t __le16;
typedef uint32_t __le32;
typedef uint64_t __le64;
typedef uint16_t __be16;
typedef uint32_t __be32;
typedef uint64_t __be64;
#define __user
#define __BITS_PER_LONG 64
#endif
EOF
    
    # Inject DRM and xf86drm shims
    cp ${libdrm_fourcc_h} include/drm_fourcc.h
    cp ${libdrm_h} include/drm.h
    cp ${libdrm_mode_h} include/drm_mode.h
    # Create xf86drm.h shim with macro-based stubs to avoid symbol conflicts
    cat > include/xf86drm.h <<'EOF'
#ifndef _XF86DRM_H
#define _XF86DRM_H
#include <stdint.h>
#define drmGetFormatModifierName(m) "INVALID"
#define drmGetFormatModifierVendor(m) "INVALID"
#endif
EOF
  '';

  meta = with lib; {
    description = "Weston compositor client applications (macOS port)";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
