{ lib, pkgs, buildModule, wawonaSrc, androidSDK ? null }:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  androidToolchain = import ./common/android-toolchain.nix { inherit lib pkgs; };

  # Read version from VERSION file
  versionString = lib.fileContents (wawonaSrc + "/VERSION");
  versionMatch = builtins.match "^([0-9]+)\\.([0-9]+)\\.([0-9]+)" (lib.removeSuffix "\n" versionString);
  projectVersion = if versionMatch != null then
    "${lib.elemAt versionMatch 0}.${lib.elemAt versionMatch 1}.${lib.elemAt versionMatch 2}"
  else "0.0.1";
  projectVersionMajor = if versionMatch != null then lib.elemAt versionMatch 0 else "0";
  projectVersionMinor = if versionMatch != null then lib.elemAt versionMatch 1 else "0";
  projectVersionPatch = if versionMatch != null then lib.elemAt versionMatch 2 else "1";

  # Common dependencies
  commonDeps = [ "libwayland" "waypipe" "libffi" "expat" "libxml2" "zstd" "lz4" "ffmpeg" ];
  
  # Platform specific dependencies
  macosDeps = commonDeps ++ [ "kosmickrisp" "epoll-shim" ];
  # For iOS Simulator, use macOS waypipe since simulator runs on macOS
  # Rust's aarch64-apple-ios target compiles for device, not simulator, so use macOS waypipe
  iosDeps = commonDeps ++ [ "kosmickrisp" "epoll-shim" "libclc" "spirv-llvm-translator" "spirv-tools" "zlib" "pixman" ];
  androidDeps = commonDeps ++ [ "swiftshader" "pixman" ];

  getDeps = platform: depNames:
    map (name: 
      if name == "pixman" then 
        # Pixman needs to be built for the target platform
        if platform == "ios" then
          buildModule.ios.pixman
        else if platform == "android" then
          buildModule.android.pixman
        else
          pkgs.pixman  # macOS can use nixpkgs pixman
      else if name == "waypipe" then
        # Use iOS waypipe built with aarch64-apple-ios-sim target
        buildModule.${platform}.${name}
      else if name == "vulkan-headers" then pkgs.vulkan-headers
      else if name == "vulkan-loader" then pkgs.vulkan-loader
      else buildModule.${platform}.${name}
    ) depNames;

  # Source files list (from CMakeLists.txt)
  commonSources = [
    # Core compositor
    "src/core/main.m"
    "src/core/WawonaCompositor.m"
    "src/core/WawonaCompositor.h"
    
    # Logging
    "src/logging/logging.c"
    "src/logging/logging.h"
    
    # Wayland protocol implementations
    "src/wayland/wayland_output.c"
    "src/wayland/wayland_output.h"
    "src/wayland/wayland_shm.c"
    "src/wayland/wayland_shm.h"
    "src/wayland/wayland_subcompositor.c"
    "src/wayland/wayland_subcompositor.h"
    "src/wayland/wayland_data_device_manager.c"
    "src/wayland/wayland_data_device_manager.h"
    "src/wayland/wayland_primary_selection.c"
    "src/wayland/wayland_primary_selection.h"
    "src/wayland/wayland_protocol_stubs.c"
    "src/wayland/wayland_protocol_stubs.h"
    "src/wayland/wayland_viewporter.c"
    "src/wayland/wayland_viewporter.h"
    "src/wayland/wayland_fullscreen_shell.c"
    "src/wayland/wayland_fullscreen_shell.h"
    "src/wayland/wayland_shell.c"
    "src/wayland/wayland_shell.h"
    "src/wayland/wayland_gtk_shell.c"
    "src/wayland/wayland_gtk_shell.h"
    "src/wayland/wayland_plasma_shell.c"
    "src/wayland/wayland_plasma_shell.h"
    "src/wayland/wayland_qt_extensions.c"
    "src/wayland/wayland_qt_extensions.h"
    "src/wayland/wayland_screencopy.c"
    "src/wayland/wayland_screencopy.h"
    "src/wayland/wayland_presentation.c"
    "src/wayland/wayland_presentation.h"
    "src/wayland/wayland_color_management.c"
    "src/wayland/wayland_color_management.h"
    "src/wayland/wayland_linux_dmabuf.c"
    "src/wayland/wayland_linux_dmabuf.h"
    "src/wayland/wayland_drm.c"
    "src/wayland/wayland_drm.h"
    "src/wayland/wayland_idle_inhibit.c"
    "src/wayland/wayland_idle_inhibit.h"
    "src/wayland/wayland_pointer_gestures.c"
    "src/wayland/wayland_pointer_gestures.h"
    "src/wayland/wayland_relative_pointer.c"
    "src/wayland/wayland_relative_pointer.h"
    "src/wayland/wayland_pointer_constraints.c"
    "src/wayland/wayland_pointer_constraints.h"
    "src/wayland/wayland_tablet.c"
    "src/wayland/wayland_tablet.h"
    "src/wayland/wayland_idle_manager.c"
    "src/wayland/wayland_idle_manager.h"
    "src/wayland/wayland_keyboard_shortcuts.c"
    "src/wayland/wayland_keyboard_shortcuts.h"
    "src/wayland/xdg_shell.c"
    "src/wayland/xdg_shell.h"
    
    # Wayland protocol definitions (generated)
    "src/protocols/primary-selection-protocol.c"
    "src/protocols/primary-selection-protocol.h"
    "src/protocols/xdg-activation-protocol.c"
    "src/protocols/xdg-activation-protocol.h"
    "src/protocols/fractional-scale-protocol.c"
    "src/protocols/fractional-scale-protocol.h"
    "src/protocols/cursor-shape-protocol.c"
    "src/protocols/cursor-shape-protocol.h"
    "src/protocols/text-input-v3-protocol.c"
    "src/protocols/text-input-v3-protocol.h"
    "src/protocols/text-input-v1-protocol.c"
    "src/protocols/text-input-v1-protocol.h"
    "src/protocols/xdg-decoration-protocol.c"
    "src/protocols/xdg-decoration-protocol.h"
    "src/protocols/xdg-toplevel-icon-protocol.c"
    "src/protocols/xdg-toplevel-icon-protocol.h"
    "src/protocols/fullscreen-shell-unstable-v1-protocol.c"
    "src/protocols/fullscreen-shell-unstable-v1-protocol.h"
    "src/protocols/linux-dmabuf-unstable-v1-protocol.c"
    "src/protocols/linux-dmabuf-unstable-v1-protocol.h"
    "src/protocols/xdg-shell-protocol.c"
    "src/protocols/xdg-shell-protocol.h"
    "src/protocols/viewporter-protocol.c"
    "src/protocols/viewporter-protocol.h"
    "src/protocols/presentation-time-protocol.h"
    "src/protocols/color-management-v1-protocol.h"
    "src/protocols/tablet-stub.c"
    
    # Rendering
    "src/rendering/surface_renderer.m"
    "src/rendering/surface_renderer.h"
    "src/rendering/metal_renderer.m"
    "src/rendering/metal_renderer.h"
    "src/rendering/metal_dmabuf.m"
    "src/rendering/metal_dmabuf.h"
    "src/rendering/metal_waypipe.m"
    "src/rendering/metal_waypipe.h"
    "src/rendering/rendering_backend.m"
    "src/rendering/rendering_backend.h"
    
    # Input handling
    "src/input/input_handler.m"
    "src/input/input_handler.h"
    "src/input/wayland_seat.c"
    "src/input/wayland_seat.h"
    "src/input/cursor_shape_bridge.m"
    
    # UI components
    "src/ui/WawonaUIHelpers.m"
    "src/ui/WawonaUIHelpers.h"
    "src/ui/WawonaPreferences.m"
    "src/ui/WawonaPreferences.h"
    "src/ui/WawonaPreferencesManager.m"
    "src/ui/WawonaPreferencesManager.h"
    "src/ui/WawonaAboutPanel.m"
    "src/ui/WawonaAboutPanel.h"
    
    # Stubs
    "src/stubs/egl_buffer_handler.h"
  ];

  iosSources = commonSources ++ [
    "src/ui/ios_launcher_client.m"
    "src/ui/ios_launcher_client.h"
    "src/protocols/color-management-v1-protocol.c"
  ];

  # macOS sources - exclude Vulkan renderer for now (Metal is primary, Vulkan linking issues)
  macosSources = lib.filter (f: 
    f != "src/rendering/vulkan_renderer.m" &&
    f != "src/rendering/vulkan_renderer.h"
  ) commonSources;

  # Android sources - only C files, no Objective-C (no Apple frameworks)
  # Exclude Apple-specific files that use TargetConditionals.h or Apple frameworks
  androidSources = lib.filter (f: 
    !(lib.hasSuffix ".m" f) &&  # No Objective-C files
    f != "src/wayland/wayland_color_management.c" &&  # Uses TargetConditionals.h
    f != "src/wayland/wayland_color_management.h" &&  # Uses TargetConditionals.h
    f != "src/stubs/egl_buffer_handler.h" &&  # Header for Apple-specific implementation
    f != "src/core/main.m"  # Use Android-specific entry point
  ) commonSources ++ [
    "src/stubs/egl_buffer_handler.c"  # Android has its own EGL implementation
    "src/android/android_jni.c"  # Android JNI bridge
    "src/rendering/android_dmabuf.c"  # Android implementation of dmabuf stubs
  ];

  # Helper to filter source files that exist (evaluated at Nix time)
  filterSources = sources: lib.filter (f: lib.pathExists (wawonaSrc + "/" + f)) sources;
  
  # Filtered source lists (evaluated at Nix time)
  macosSourcesFiltered = filterSources macosSources;
  iosSourcesFiltered = filterSources iosSources;
  androidSourcesFiltered = filterSources androidSources;

  # Compiler flags from CMakeLists.txt
  commonCFlags = [
    "-Wall" "-Wextra" "-Wpedantic" "-Werror"
    "-Wstrict-prototypes" "-Wmissing-prototypes"
    "-Wold-style-definition" "-Wmissing-declarations"
    "-Wuninitialized" "-Winit-self"
    "-Wpointer-arith" "-Wcast-qual"
    "-Wwrite-strings" "-Wconversion" "-Wsign-conversion"
    "-Wformat=2" "-Wformat-security"
    "-Wundef" "-Wshadow" "-Wstrict-overflow=5"
    "-Wswitch-default" "-Wswitch-enum"
    "-Wunreachable-code" "-Wfloat-equal"
    "-Wstack-protector" "-fstack-protector-strong"
    "-fPIC"
    "-D_FORTIFY_SOURCE=2"
    # Suppress warnings
    "-Wno-unused-parameter" "-Wno-unused-function" "-Wno-unused-variable"
    "-Wno-sign-conversion" "-Wno-implicit-float-conversion"
    "-Wno-missing-field-initializers" "-Wno-format-nonliteral"
    "-Wno-deprecated-declarations" "-Wno-cast-qual"
    "-Wno-empty-translation-unit" "-Wno-format-pedantic"
  ];

  commonObjCFlags = [
    "-Wall" "-Wextra" "-Wpedantic"
    "-Wuninitialized" "-Winit-self"
    "-Wpointer-arith" "-Wcast-qual"
    "-Wformat=2" "-Wformat-security"
    "-Wundef" "-Wshadow"
    "-Wstack-protector" "-fstack-protector-strong"
    "-fobjc-arc"
    "-Wno-unused-parameter" "-Wno-unused-function" "-Wno-unused-variable"
    "-Wno-implicit-float-conversion" "-Wno-deprecated-declarations"
    "-Wno-cast-qual" "-Wno-format-nonliteral" "-Wno-format-pedantic"
  ];

  releaseCFlags = [ "-O3" "-DNDEBUG" "-flto" ];
  releaseObjCFlags = [ "-O3" "-DNDEBUG" "-flto" ];

in {
  macos = pkgs.stdenv.mkDerivation rec {
    name = "wawona-macos";
    version = projectVersion;
    src = wawonaSrc;
    
    nativeBuildInputs = with pkgs; [
      clang
      pkg-config
      xcodeUtils.findXcodeScript
    ];
    
    buildInputs = (getDeps "macos" macosDeps) ++ [
      pkgs.pixman
      pkgs.vulkan-headers
      pkgs.vulkan-loader
    ];
    
    # Fix gbm-wrapper.c include path and egl_buffer_handler.h for macOS
    postPatch = ''
      # Fix gbm-wrapper.c include path for metal_dmabuf.h
      substituteInPlace src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
        --replace-fail '#include "../../../../metal_dmabuf.h"' '#include "metal_dmabuf.h"'
      
      # Fix ARC bridging issues in metal_renderer.m
      substituteInPlace src/rendering/metal_renderer.m \
        --replace-fail '(void *)metalSurface' '(__bridge void *)metalSurface'
      
      # Make VulkanRenderer references conditional in metal_renderer.m for macOS
      sed -i 's|^[[:space:]]*_vulkanRenderer =|// _vulkanRenderer =|g' src/rendering/metal_renderer.m
      sed -i 's|if (_vulkanRenderer)|if (0 /* _vulkanRenderer disabled for macOS */)|g' src/rendering/metal_renderer.m
      sed -i 's|self\.vulkanRenderer|nil /* self.vulkanRenderer disabled for macOS */|g' src/rendering/metal_renderer.m
      sed -i 's|(VulkanRenderer \*)|(id /* VulkanRenderer disabled for macOS */)|g' src/rendering/metal_renderer.m
      
      # Make VulkanRenderer property conditional in metal_renderer.h
      substituteInPlace src/rendering/metal_renderer.h \
        --replace-fail '@class VulkanRenderer;' '// @class VulkanRenderer; // Disabled for macOS'
      substituteInPlace src/rendering/metal_renderer.h \
        --replace-fail '@property (nonatomic, strong) VulkanRenderer *vulkanRenderer;' '// @property (nonatomic, strong) VulkanRenderer *vulkanRenderer; // Disabled for macOS'
      
      # Create macOS-compatible egl_buffer_handler.h stub
      # macOS doesn't use EGL, so we need to stub it out
      cat > src/stubs/egl_buffer_handler.h <<'EOF'
#pragma once

#include <wayland-server-core.h>
#include <stdbool.h>

// macOS stub: EGL is not available on macOS (we use Metal instead)
// This provides stub definitions to avoid compilation errors

typedef void* EGLDisplay;
typedef void* EGLContext;
typedef void* EGLConfig;
typedef void* EGLImageKHR;
typedef int EGLint;

#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_IMAGE_KHR ((EGLImageKHR)0)

struct egl_buffer_handler {
    EGLDisplay egl_display;
    EGLContext egl_context;
    EGLConfig egl_config;
    bool initialized;
    bool display_bound;
};

// Stub functions - return failure on macOS
static inline int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
    (void)handler; (void)display;
    return -1; // EGL not available on macOS
}

static inline void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
    (void)handler;
}

static inline int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                                   struct wl_resource *buffer_resource,
                                                   int32_t *width, int32_t *height,
                                                   EGLint *texture_format) {
    (void)handler; (void)buffer_resource; (void)width; (void)height; (void)texture_format;
    return -1;
}

static inline EGLImageKHR egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                                          struct wl_resource *buffer_resource) {
    (void)handler; (void)buffer_resource;
    return EGL_NO_IMAGE_KHR;
}

static inline bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                                     struct wl_resource *buffer_resource) {
    (void)handler; (void)buffer_resource;
    return false;
}
EOF
    '';
    
    # Metal shader compilation
    preBuild = ''
      # Find Metal compiler
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        fi
      fi
      
      # Compile Metal shaders
      if command -v metal >/dev/null 2>&1; then
        echo "Compiling Metal shaders..."
        metal -c src/rendering/metal_shaders.metal -o metal_shaders.air || true
        if [ -f metal_shaders.air ] && command -v metallib >/dev/null 2>&1; then
          metallib metal_shaders.air -o metal_shaders.metallib || true
        fi
      fi
    '';
    
    # Setup dependencies
    preConfigure = ''
      # Xcode setup for macOS
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        fi
      fi

      mkdir -p macos-dependencies/include
      mkdir -p macos-dependencies/lib
      mkdir -p macos-dependencies/libdata/pkgconfig
      
      # Copy dependencies to local folder
      for dep in $buildInputs; do
        if [ -d "$dep/include" ]; then
          cp -rn "$dep/include/"* macos-dependencies/include/ 2>/dev/null || true
        fi
        if [ -d "$dep/lib" ]; then
          cp -rn "$dep/lib/"* macos-dependencies/lib/ 2>/dev/null || true
        fi
        if [ -d "$dep/lib/pkgconfig" ]; then
          cp -rn "$dep/lib/pkgconfig/"* macos-dependencies/libdata/pkgconfig/ 2>/dev/null || true
        fi
        if [ -d "$dep/libdata/pkgconfig" ]; then
          cp -rn "$dep/libdata/pkgconfig/"* macos-dependencies/libdata/pkgconfig/ 2>/dev/null || true
        fi
      done
      
      export PKG_CONFIG_PATH="$PWD/macos-dependencies/libdata/pkgconfig:$PWD/macos-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"
    '';
    
    # Build libgbm wrapper
    buildPhase = ''
      runHook preBuild
      
      # Get wayland-server and pixman paths
      WAYLAND_SERVER_INC=$(pkg-config --cflags-only-I wayland-server | sed 's/-I//g' | tr ' ' '\n' | head -1)
      PIXMAN_INC=$(pkg-config --cflags-only-I pixman-1 | sed 's/-I//g' | tr ' ' '\n' | head -1)
      
      # Compile libgbm wrapper (use patched file from build directory, not $src)
      $CC -c \
         -I''${WAYLAND_SERVER_INC} -I''${PIXMAN_INC} \
         -Isrc/compat/macos/stubs/libinput-macos \
         -Isrc -Isrc/core -Isrc/wayland \
         -Isrc/rendering -Isrc/input -Isrc/ui \
         -Isrc/logging -Isrc/stubs -Isrc/protocols \
         -Imacos-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonCFlags} \
         ${lib.concatStringsSep " " releaseCFlags} \
         src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
         -o gbm-wrapper.o
      
      $CC -c src/rendering/metal_dmabuf.m \
         -Isrc -Isrc/core -Isrc/wayland \
         -Isrc/rendering -Isrc/input -Isrc/ui \
         -Isrc/logging -Isrc/stubs -Isrc/protocols \
         -Imacos-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonObjCFlags} \
         ${lib.concatStringsSep " " releaseObjCFlags} \
         -o metal_dmabuf.o
      
      ar rcs libgbm.a gbm-wrapper.o metal_dmabuf.o
      
      # Compile all source files
      OBJ_FILES=""
      for src_file in ${lib.concatStringsSep " " macosSourcesFiltered}; do
        if [[ "$src_file" == *.c ]] || [[ "$src_file" == *.m ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if [[ "$src_file" == *.m ]]; then
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/wayland \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Imacos-dependencies/include \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " commonObjCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -DHAVE_VULKAN=0 \
               -o "$obj_file" || true
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/wayland \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Imacos-dependencies/include \
               -fPIC \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " releaseCFlags} \
               -DHAVE_VULKAN=0 \
               -o "$obj_file" || true
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done
      
      # Link executable
      # Find Vulkan library - try multiple approaches
      VULKAN_LIB=""
      if [ -f macos-dependencies/lib/libvulkan.dylib ]; then
        VULKAN_LIB="-Lmacos-dependencies/lib -lvulkan"
      elif [ -f macos-dependencies/lib/libvulkan_kosmickrisp.dylib ]; then
        # Try linking directly with full path
        VULKAN_LIB_PATH="$(pwd)/macos-dependencies/lib/libvulkan_kosmickrisp.dylib"
        VULKAN_LIB="$VULKAN_LIB_PATH"
        echo "Linking Vulkan library from: $VULKAN_LIB_PATH"
      elif pkg-config --exists vulkan; then
        VULKAN_LIB=$(pkg-config --libs vulkan)
      fi
      
      # Check if Vulkan symbols are actually needed (only if vulkan_renderer is compiled)
      if echo "$OBJ_FILES" | grep -q "vulkan_renderer"; then
        echo "Vulkan renderer detected, linking Vulkan library..."
        if [ -z "$VULKAN_LIB" ]; then
          echo "WARNING: Vulkan library not found but vulkan_renderer is being linked!"
          echo "Attempting to continue without Vulkan (Metal will be used as fallback)..."
        fi
      fi
      
      # Try linking with Vulkan first, fall back to without if it fails
      if [ -n "$VULKAN_LIB" ] && echo "$OBJ_FILES" | grep -q "vulkan_renderer"; then
        echo "Attempting to link with Vulkan support..."
        set +e
        $CC $OBJ_FILES libgbm.a \
           -Lmacos-dependencies/lib \
           -framework Cocoa -framework QuartzCore -framework CoreVideo \
           -framework CoreMedia -framework CoreGraphics -framework ColorSync \
           -framework Metal -framework MetalKit -framework IOSurface \
           -framework VideoToolbox -framework AVFoundation \
           $(pkg-config --libs wayland-server wayland-client pixman-1) \
           $VULKAN_LIB \
           -fobjc-arc -flto -O3 \
           -Wl,-rpath,\$PWD/macos-dependencies/lib \
           -o Wawona 2>&1
        LINK_RESULT=$?
        set -e
        if [ $LINK_RESULT -ne 0 ]; then
          echo "Vulkan linking failed, building without Vulkan (Metal will be used)..."
          # Remove vulkan_renderer object file and link without it
          OBJ_FILES_NO_VULKAN=$(echo "$OBJ_FILES" | sed 's/rendering_vulkan_renderer\.m\.o//g')
          $CC $OBJ_FILES_NO_VULKAN libgbm.a \
             -Lmacos-dependencies/lib \
             -framework Cocoa -framework QuartzCore -framework CoreVideo \
             -framework CoreMedia -framework CoreGraphics -framework ColorSync \
             -framework Metal -framework MetalKit -framework IOSurface \
             -framework VideoToolbox -framework AVFoundation \
             $(pkg-config --libs wayland-server wayland-client pixman-1) \
             -fobjc-arc -flto -O3 \
             -Wl,-rpath,\$PWD/macos-dependencies/lib \
             -o Wawona
        else
          echo "Successfully linked with Vulkan support"
        fi
      else
        # No Vulkan needed
        $CC $OBJ_FILES libgbm.a \
           -Lmacos-dependencies/lib \
           -framework Cocoa -framework QuartzCore -framework CoreVideo \
           -framework CoreMedia -framework CoreGraphics -framework ColorSync \
           -framework Metal -framework MetalKit -framework IOSurface \
           -framework VideoToolbox -framework AVFoundation \
           $(pkg-config --libs wayland-server wayland-client pixman-1) \
           -fobjc-arc -flto -O3 \
           -Wl,-rpath,\$PWD/macos-dependencies/lib \
           -o Wawona
      fi
      
      runHook postBuild
    '';
    
    # Create app bundle
    installPhase = ''
      runHook preInstall
      
      # Create app bundle structure
      mkdir -p $out/Applications/Wawona.app/Contents/MacOS
      mkdir -p $out/Applications/Wawona.app/Contents/Resources
      
      # Copy executable
      cp Wawona $out/Applications/Wawona.app/Contents/MacOS/
      
      # Copy Metal shader library
      if [ -f metal_shaders.metallib ]; then
        cp metal_shaders.metallib $out/Applications/Wawona.app/Contents/MacOS/
      fi
      
      # Generate Info.plist
      cat > $out/Applications/Wawona.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Wawona</string>
    <key>CFBundleIdentifier</key>
    <string>com.aspauldingcode.Wawona</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Wawona</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${projectVersion}</string>
    <key>CFBundleVersion</key>
    <string>${projectVersionPatch}</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Alex Spaulding. All rights reserved.</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon.png</string>
</dict>
</plist>
EOF
      
      # Copy AppIcon
      if [ -f $src/src/resources/Wawona@2x/Wawona-iOS-Default-1024x1024@2x.png ]; then
        cp $src/src/resources/Wawona@2x/Wawona-iOS-Default-1024x1024@2x.png \
           $out/Applications/Wawona.app/Contents/Resources/AppIcon.png
      fi
      
      runHook postInstall
    '';
    
    # Also create bin output for convenience
    postInstall = ''
      mkdir -p $out/bin
      ln -s $out/Applications/Wawona.app/Contents/MacOS/Wawona $out/bin/Wawona
    '';
  };

  ios = pkgs.stdenv.mkDerivation rec {
    name = "wawona-ios";
    version = projectVersion;
    src = wawonaSrc;
    
    nativeBuildInputs = with pkgs; [
      clang
      pkg-config
      xcodeUtils.findXcodeScript
    ];
    
    buildInputs = (getDeps "ios" iosDeps) ++ [
      pkgs.vulkan-headers
    ];
    
    # Fix gbm-wrapper.c include path and egl_buffer_handler.h for iOS
    postPatch = ''
      # Fix gbm-wrapper.c include path for metal_dmabuf.h
      substituteInPlace src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
        --replace-fail '#include "../../../../metal_dmabuf.h"' '#include "metal_dmabuf.h"'
      
      # Fix ARC bridging issues in metal_renderer.m
      substituteInPlace src/rendering/metal_renderer.m \
        --replace-fail '(void *)metalSurface' '(__bridge void *)metalSurface'
      
      # Make VulkanRenderer references conditional in metal_renderer.m for iOS
      sed -i 's|^[[:space:]]*_vulkanRenderer =|// _vulkanRenderer =|g' src/rendering/metal_renderer.m
      sed -i 's|if (_vulkanRenderer)|if (0 /* _vulkanRenderer disabled for iOS */)|g' src/rendering/metal_renderer.m
      sed -i 's|self\.vulkanRenderer|nil /* self.vulkanRenderer disabled for iOS */|g' src/rendering/metal_renderer.m
      sed -i 's|(VulkanRenderer \*)|(id /* VulkanRenderer disabled for iOS */)|g' src/rendering/metal_renderer.m
      
      # Make VulkanRenderer property conditional in metal_renderer.h
      substituteInPlace src/rendering/metal_renderer.h \
        --replace-fail '@class VulkanRenderer;' '// @class VulkanRenderer; // Disabled for iOS' \
        --replace-fail '@property (nonatomic, strong) VulkanRenderer *vulkanRenderer;' '// @property (nonatomic, strong) VulkanRenderer *vulkanRenderer; // Disabled for iOS'
      
      # Create iOS-compatible egl_buffer_handler.h stub
      # iOS doesn't use EGL, so we need to stub it out
      cat > src/stubs/egl_buffer_handler.h <<'EOF'
#pragma once

#include <wayland-server-core.h>
#include <stdbool.h>

// iOS stub: EGL is not available on iOS (we use Metal instead)
// This provides stub definitions to avoid compilation errors

typedef void* EGLDisplay;
typedef void* EGLContext;
typedef void* EGLConfig;
typedef void* EGLImageKHR;
typedef int EGLint;

#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_IMAGE_KHR ((EGLImageKHR)0)

struct egl_buffer_handler {
    EGLDisplay egl_display;
    EGLContext egl_context;
    EGLConfig egl_config;
    bool initialized;
    bool display_bound;
};

// Stub functions - return failure on iOS
static inline int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
    (void)handler; (void)display;
    return -1; // EGL not available on iOS
}

static inline void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
    (void)handler;
}

static inline int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                                   struct wl_resource *buffer_resource,
                                                   int32_t *width, int32_t *height,
                                                   EGLint *texture_format) {
    (void)handler; (void)buffer_resource; (void)width; (void)height; (void)texture_format;
    return -1;
}

static inline EGLImageKHR egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                                          struct wl_resource *buffer_resource) {
    (void)handler; (void)buffer_resource;
    return EGL_NO_IMAGE_KHR;
}

static inline bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                                     struct wl_resource *buffer_resource) {
    (void)handler; (void)buffer_resource;
    return false;
}
EOF
    '';
    
    # Metal shader compilation
    preBuild = ''
      # Xcode setup
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          # Use iPhoneSimulator SDK for simulator builds
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      
      # Compile Metal shaders
      if command -v metal >/dev/null 2>&1; then
        echo "Compiling Metal shaders..."
        metal -c src/rendering/metal_shaders.metal -o metal_shaders.air -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 || true
        if [ -f metal_shaders.air ] && command -v metallib >/dev/null 2>&1; then
          metallib metal_shaders.air -o metal_shaders.metallib || true
        fi
      fi
    '';
    
    preConfigure = ''
      # Xcode setup for iOS Simulator
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          # Use iPhoneSimulator SDK for simulator builds
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      
      # Prepare dependencies
      mkdir -p ios-dependencies/include
      mkdir -p ios-dependencies/lib
      mkdir -p ios-dependencies/libdata/pkgconfig
      
      for dep in $buildInputs; do
         if [ -d "$dep/include" ]; then
           cp -rn "$dep/include/"* ios-dependencies/include/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib" ]; then
           cp -rn "$dep/lib/"* ios-dependencies/lib/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib/pkgconfig" ]; then
           cp -rn "$dep/lib/pkgconfig/"* ios-dependencies/libdata/pkgconfig/ 2>/dev/null || true
         fi
         if [ -d "$dep/libdata/pkgconfig" ]; then
           cp -rn "$dep/libdata/pkgconfig/"* ios-dependencies/libdata/pkgconfig/ 2>/dev/null || true
         fi
      done
      
      export PKG_CONFIG_PATH="$PWD/ios-dependencies/libdata/pkgconfig:$PWD/ios-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"
      export NIX_CFLAGS_COMPILE=""
      export NIX_CXXFLAGS_COMPILE=""
      
      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      else
        IOS_CC="${pkgs.clang}/bin/clang"
        IOS_CXX="${pkgs.clang}/bin/clang++"
      fi
      # Use x86_64 for simulator on Intel Macs, arm64 for Apple Silicon
      # Check if we're building for simulator
      SIMULATOR_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        SIMULATOR_ARCH="x86_64"
      fi
      export CC="$IOS_CC"
      export CXX="$IOS_CXX"
      export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
      export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
      export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -lobjc"
    '';
    
    buildPhase = ''
      runHook preBuild
      
      # Get wayland-server and pixman paths
      WAYLAND_SERVER_INC=$(pkg-config --cflags-only-I wayland-server | sed 's/-I//g' | tr ' ' '\n' | head -1)
      PIXMAN_INC=$(pkg-config --cflags-only-I pixman-1 | sed 's/-I//g' | tr ' ' '\n' | head -1)
      
      # Compile libgbm wrapper (use patched file from build directory)
      $CC -c \
         -I''${WAYLAND_SERVER_INC} -I''${PIXMAN_INC} \
         -Isrc/compat/macos/stubs/libinput-macos \
         -Isrc -Isrc/core -Isrc/wayland \
         -Isrc/rendering -Isrc/input -Isrc/ui \
         -Isrc/logging -Isrc/stubs -Isrc/protocols \
         -Iios-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonCFlags} \
         ${lib.concatStringsSep " " releaseObjCFlags} \
         -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
         -o gbm-wrapper.o
      
      $CC -c src/rendering/metal_dmabuf.m \
         -Isrc -Isrc/core -Isrc/wayland \
         -Isrc/rendering -Isrc/input -Isrc/ui \
         -Isrc/logging -Isrc/stubs -Isrc/protocols \
         -Iios-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonObjCFlags} \
         ${lib.concatStringsSep " " releaseObjCFlags} \
         -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -o metal_dmabuf.o
      
      ar rcs libgbm.a gbm-wrapper.o metal_dmabuf.o
      
      # Compile all source files
      OBJ_FILES=""
      for src_file in ${lib.concatStringsSep " " iosSourcesFiltered}; do
        if [[ "$src_file" == *.c ]] || [[ "$src_file" == *.m ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if [[ "$src_file" == *.m ]]; then
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/wayland \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Iios-dependencies/include \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " commonObjCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
               -DHAVE_VULKAN=0 \
               -o "$obj_file" || true
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/wayland \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Iios-dependencies/include \
               -fPIC \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
               -DHAVE_VULKAN=0 \
               -o "$obj_file" || true
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done
      
      # Link executable
      $CC $OBJ_FILES libgbm.a \
         -Lios-dependencies/lib \
         -framework Foundation -framework UIKit -framework QuartzCore \
         -framework CoreVideo -framework CoreMedia -framework CoreGraphics \
         -framework Metal -framework MetalKit -framework IOSurface \
         -framework VideoToolbox -framework AVFoundation \
         $(pkg-config --libs wayland-server wayland-client pixman-1) \
         -fobjc-arc -flto -O3 -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -Wl,-rpath,@executable_path/Frameworks \
         -o Wawona
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      # Create app bundle structure
      mkdir -p $out/Applications/Wawona.app
      
      # Copy executable
      cp Wawona $out/Applications/Wawona.app/
      
      # Copy Metal shader library
      if [ -f metal_shaders.metallib ]; then
        cp metal_shaders.metallib $out/Applications/Wawona.app/
      fi
      
      # Generate Info.plist
      cat > $out/Applications/Wawona.app/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Wawona</string>
    <key>CFBundleIdentifier</key>
    <string>com.aspauldingcode.Wawona</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Wawona</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${projectVersion}</string>
    <key>CFBundleVersion</key>
    <string>${projectVersionPatch}</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Alex Spaulding. All rights reserved.</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIRequiresFullScreen</key>
    <false/>
    <key>CFBundleIconFile</key>
    <string>AppIcon.png</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>armv7</string>
    </array>
    <key>UIApplicationSupportsIndirectInputEvents</key>
    <true/>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>
</dict>
</plist>
EOF
      
      # Copy AppIcon
      if [ -f $src/src/resources/Wawona@2x/Wawona-iOS-Default-1024x1024@2x.png ]; then
        cp $src/src/resources/Wawona@2x/Wawona-iOS-Default-1024x1024@2x.png \
           $out/Applications/Wawona.app/AppIcon.png
      fi
      
      # Copy Settings.bundle if it exists
      if [ -d $src/src/resources/Settings.bundle ]; then
        cp -r $src/src/resources/Settings.bundle $out/Applications/Wawona.app/
      fi
      
      # Copy dynamic libraries to Frameworks
      mkdir -p $out/Applications/Wawona.app/Frameworks
      if [ -d ios-dependencies/lib ]; then
        echo "Copying dynamic libraries..."
        # Copy dylibs
        find ios-dependencies/lib -name "*.dylib" -exec cp -L {} $out/Applications/Wawona.app/Frameworks/ \;
        
        # Fix dylib paths
        cd $out/Applications/Wawona.app/Frameworks
        for lib in *.dylib; do
          if [ -f "$lib" ]; then
            echo "Fixing library: $lib"
            # Change ID
            install_name_tool -id "@rpath/$lib" "$lib"
            
            # Change dependencies
            otool -L "$lib" | grep ".dylib" | grep -v "$lib" | while read -r line; do
              dep_path=$(echo $line | awk '{print $1}')
              dep_name=$(basename "$dep_path")
              if [ -f "$dep_name" ]; then
                install_name_tool -change "$dep_path" "@rpath/$dep_name" "$lib"
              fi
            done
          fi
        done
        cd -
        
        # Fix main executable dependencies
        echo "Fixing executable dependencies..."
        EXECUTABLE="$out/Applications/Wawona.app/Wawona"
        otool -L "$EXECUTABLE" | grep ".dylib" | while read -r line; do
          dep_path=$(echo $line | awk '{print $1}')
          dep_name=$(basename "$dep_path")
          if [ -f "$out/Applications/Wawona.app/Frameworks/$dep_name" ]; then
            echo "  Relinking $dep_name in executable..."
            install_name_tool -change "$dep_path" "@rpath/$dep_name" "$EXECUTABLE"
          fi
        done
      fi
      
      runHook postInstall
    '';
    
    postInstall = ''
      # Create symlink for convenience
      mkdir -p $out/bin
      ln -s $out/Applications/Wawona.app/Wawona $out/bin/Wawona
      
      # Create iOS simulator launcher script
      cat > $out/bin/wawona-ios-simulator <<'EOF'
#!/usr/bin/env bash
set -e

APP_BUNDLE="$1"
if [ -z "$APP_BUNDLE" ]; then
  APP_BUNDLE="$(dirname "$0")/../Applications/Wawona.app"
fi

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Error: App bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

# Check if xcrun is available
if ! command -v xcrun >/dev/null 2>&1; then
  echo "Error: xcrun not found. Please install Xcode Command Line Tools." >&2
  echo "Run: xcode-select --install" >&2
  exit 1
fi

# Check if iOS Simulator runtime is installed
echo "Checking for iOS Simulator runtime..."
RUNTIMES=$(xcrun simctl list runtimes available 2>/dev/null | grep -i "iOS" | head -n 1 || true)

if [ -z "$RUNTIMES" ]; then
  echo "⚠️  No iOS Simulator runtime found."
  echo ""
  echo "To install iOS Simulator runtime:"
  echo "  1. Open Xcode"
  echo "  2. Go to Xcode > Settings > Platforms (or Components)"
  echo "  3. Download the iOS Simulator runtime for your Xcode version"
  echo ""
  echo "Or install via command line:"
  echo "  xcodebuild -downloadPlatform iOS"
  echo ""
  echo "Attempting to download iOS platform..."
  if xcodebuild -downloadPlatform iOS 2>&1; then
    echo "✅ iOS Simulator runtime download initiated."
    echo "   This may take several minutes. Please wait..."
    sleep 2
  else
    echo "❌ Failed to automatically download iOS runtime."
    echo "   Please install it manually via Xcode > Settings > Platforms"
    exit 1
  fi
fi

# Find an iOS simulator (prefer iPhone, then iPad)
echo "Finding iOS Simulator..."
DEVICE_ID=$(xcrun simctl list devices available 2>/dev/null | grep -iE "(iPhone|iPad)" | grep -v "unavailable" | head -n 1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' | head -n 1)

if [ -z "$DEVICE_ID" ]; then
  echo "⚠️  No available iOS Simulator device found."
  echo ""
  echo "Creating a default iPhone simulator..."
  
  # Try to create a simulator if none exists
  RUNTIME=$(xcrun simctl list runtimes available 2>/dev/null | grep -i "iOS" | head -n 1 | sed -E 's/.*\(([^)]+)\).*/\1/' | head -n 1)
  
  if [ -z "$RUNTIME" ]; then
    echo "Error: No iOS runtime available. Please install iOS Simulator runtime first." >&2
    exit 1
  fi
  
  # Create iPhone 15 simulator as default
  DEVICE_NAME="iPhone 15"
  DEVICE_TYPE=$(xcrun simctl list devicetypes | grep -i "iPhone 15" | head -n 1 | sed -E 's/.*\(([^)]+)\).*/\1/' | head -n 1)
  
  if [ -z "$DEVICE_TYPE" ]; then
    # Fallback to any iPhone
    DEVICE_TYPE=$(xcrun simctl list devicetypes | grep -i "iPhone" | head -n 1 | sed -E 's/.*\(([^)]+)\).*/\1/' | head -n 1)
    DEVICE_NAME=$(xcrun simctl list devicetypes | grep -i "iPhone" | head -n 1 | sed -E 's/.*- (.*) \(.*/\1/' | head -n 1)
  fi
  
  if [ -n "$DEVICE_TYPE" ] && [ -n "$RUNTIME" ]; then
    echo "Creating simulator: $DEVICE_NAME ($DEVICE_TYPE) with runtime $RUNTIME"
    DEVICE_ID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME" 2>/dev/null || true)
    
    if [ -z "$DEVICE_ID" ]; then
      echo "Error: Failed to create simulator. Please create one manually:" >&2
      echo "  Xcode > Window > Devices and Simulators > + > iPhone" >&2
      exit 1
    fi
    echo "✅ Created simulator: $DEVICE_ID"
  else
    echo "Error: Could not determine device type or runtime." >&2
    echo "Please create a simulator manually: Xcode > Window > Devices and Simulators" >&2
    exit 1
  fi
fi

DEVICE_NAME=$(xcrun simctl list devices available | grep "$DEVICE_ID" | sed -E 's/.*- (.*) \(.*/\1/' | head -n 1)
echo "Using simulator: $DEVICE_NAME ($DEVICE_ID)"

# Check if simulator is booted
BOOTED=$(xcrun simctl list devices | grep "$DEVICE_ID" | grep -c "Booted" || true)
if [ "$BOOTED" -eq 0 ]; then
  echo "Booting iOS Simulator..."
  xcrun simctl boot "$DEVICE_ID" 2>/dev/null || {
    echo "Warning: Simulator may already be booting or boot failed. Continuing..." >&2
  }
  sleep 5
fi

# Open Simulator app if not already open
if ! pgrep -x "Simulator" > /dev/null; then
  echo "Opening Simulator app..."
  open -a Simulator
  sleep 5
fi

# Copy app bundle to a writable location (simulator can't install from read-only Nix store)
TEMP_APP_DIR=$(mktemp -d)
TEMP_APP_BUNDLE="$TEMP_APP_DIR/Wawona.app"
echo "Copying app bundle to temporary location..."
cp -R "$APP_BUNDLE" "$TEMP_APP_BUNDLE" || {
  echo "Error: Failed to copy app bundle" >&2
  rm -rf "$TEMP_APP_DIR"
  exit 1
}

# Fix permissions - make all files writable (simulator needs to modify them during install)
echo "Fixing permissions..."
chmod -R u+w "$TEMP_APP_BUNDLE" || {
  echo "Warning: Failed to fix some permissions, continuing anyway..." >&2
}

# Ad-hoc sign the app bundle for Simulator (required for Apple Silicon)
echo "Signing app for Simulator (ad-hoc)..."
if command -v codesign >/dev/null 2>&1; then
  # Create minimal entitlements for Simulator
  cat > "$TEMP_APP_DIR/entitlements.plist" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

  # Sign frameworks first
  if [ -d "$TEMP_APP_BUNDLE/Frameworks" ]; then
    find "$TEMP_APP_BUNDLE/Frameworks" -name "*.dylib" -o -name "*.framework" | while read -r fw; do
      echo "  Signing $(basename "$fw")..."
      codesign --force --sign - --timestamp=none "$fw" || echo "Warning: Failed to sign $fw"
    done
  fi
  
  # Sign main executable
  echo "  Signing main bundle..."
  codesign --force --sign - --timestamp=none --entitlements "$TEMP_APP_DIR/entitlements.plist" "$TEMP_APP_BUNDLE" 2>/dev/null || \
  codesign --force --sign - --timestamp=none "$TEMP_APP_BUNDLE" || \
  echo "Warning: Failed to sign app bundle"
else
  echo "Warning: codesign command not found. App may fail to launch on Apple Silicon."
fi

# Cleanup function - use force removal to handle permission issues
cleanup() {
  chmod -R u+w "$TEMP_APP_DIR" 2>/dev/null || true
  rm -rf "$TEMP_APP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Uninstall existing app if present (to avoid conflicts)
# Uninstall existing app if present (to avoid conflicts)
BUNDLE_ID="com.aspauldingcode.Wawona"
echo "Uninstalling existing app (if present)..."
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true

# Install the app from the temporary location
echo "Installing Wawona app..."
xcrun simctl install "$DEVICE_ID" "$TEMP_APP_BUNDLE" || {
  echo "Error: Failed to install app" >&2
  exit 1
}

# Verify app was installed
echo "Verifying installation..."
INSTALLED=$(xcrun simctl listapps "$DEVICE_ID" 2>/dev/null | grep -c "$BUNDLE_ID" || echo "0")
if [ "$INSTALLED" -eq 0 ]; then
  echo "⚠️  Warning: App may not have been installed correctly."
  echo "   Check the Simulator to see if Wawona appears on the home screen."
else
  echo "✅ App installed successfully."
fi

# Launch the app
echo "Launching Wawona..."
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" 2>&1 || {
  echo "⚠️  Launch command returned an error, but the app is installed."
}

echo ""
echo "✅ iOS Simulator setup complete!"
echo "   Device: $DEVICE_NAME ($DEVICE_ID)"
echo "   App Bundle ID: $BUNDLE_ID"
echo ""
echo "📋 Streaming logs (Ctrl+C to stop)..."
echo ""

# Stream logs to stdout for debugging
xcrun simctl spawn "$DEVICE_ID" log stream --predicate 'processImagePath contains "Wawona" OR processImagePath endswith "Wawona"' --level debug --style compact
EOF
      chmod +x $out/bin/wawona-ios-simulator
    '';
  };

  android = pkgs.stdenv.mkDerivation rec {
    name = "wawona-android";
    version = projectVersion;
    src = wawonaSrc;
    
    # Skip fixup phase - Android binaries can't execute on macOS
    dontFixup = true;
    
    nativeBuildInputs = with pkgs; [
      clang
      pkg-config
      jdk17_headless  # For javac
      unzip
      zip
      patchelf
      file
    ];
    
    buildInputs = (getDeps "android" androidDeps) ++ [
      pkgs.mesa
    ];
    
    # Fix egl_buffer_handler.c for Android (create Android-compatible stub)
    postPatch = ''
      # Android doesn't have Wayland EGL extensions, so we need to create a stub
      # Replace the entire file with an Android-compatible stub
      cat > src/stubs/egl_buffer_handler.c <<'EOF'
#include "egl_buffer_handler.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Android stub: EGL Wayland extensions are not available on Android
// This provides stub implementations to avoid compilation errors

static void egl_buffer_handler_translation_unit_silence(void) {}

int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
    (void)handler; (void)display;
    // EGL Wayland extensions not available on Android
    return -1;
}

void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
    (void)handler;
}

int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                     struct wl_resource *buffer_resource,
                                     int32_t *width, int32_t *height,
                                     int *texture_format) {
    (void)handler; (void)buffer_resource; (void)width; (void)height; (void)texture_format;
    return -1;
}

void* egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                      struct wl_resource *buffer_resource) {
    (void)handler; (void)buffer_resource;
    return NULL;
}

bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                       struct wl_resource *buffer_resource) {
    (void)handler; (void)buffer_resource;
    return false;
}
EOF
    '';
    
    preConfigure = ''
      export CC="${androidToolchain.androidCC}"
      export CXX="${androidToolchain.androidCXX}"
      export AR="${androidToolchain.androidAR}"
      export STRIP="${androidToolchain.androidSTRIP}"
      export RANLIB="${androidToolchain.androidRANLIB}"
      export CFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
      export CXXFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
      export LDFLAGS="--target=${androidToolchain.androidTarget}"
      
      # Android dependencies setup
      mkdir -p android-dependencies/include
      mkdir -p android-dependencies/lib
      mkdir -p android-dependencies/lib/pkgconfig
      
      for dep in $buildInputs; do
         if [ -d "$dep/include" ]; then
           cp -rn "$dep/include/"* android-dependencies/include/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib" ]; then
           cp -rn "$dep/lib/"* android-dependencies/lib/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib/pkgconfig" ]; then
            cp -rn "$dep/lib/pkgconfig/"* android-dependencies/lib/pkgconfig/ 2>/dev/null || true
         fi
      done
      
      export PKG_CONFIG_PATH="$PWD/android-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"
    '';
    
    buildPhase = ''
      runHook preBuild
      
      # Compile all source files (Android only uses C files, no Objective-C)
      OBJ_FILES=""
      echo "=== Compiling Android sources ==="
      for src_file in ${lib.concatStringsSep " " androidSourcesFiltered}; do
        if [[ "$src_file" == *.c ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          echo "Compiling: $src_file -> $obj_file"
          
          if $CC -c "$src_file" \
             -Isrc -Isrc/core -Isrc/wayland \
             -Isrc/rendering -Isrc/input -Isrc/ui \
             -Isrc/logging -Isrc/stubs -Isrc/protocols \
             -Iandroid-dependencies/include \
             -fPIC \
             ${lib.concatStringsSep " " commonCFlags} \
             ${lib.concatStringsSep " " releaseCFlags} \
             --target=${androidToolchain.androidTarget} \
             -o "$obj_file"; then
            OBJ_FILES="$OBJ_FILES $obj_file"
            echo "  ✓ Compiled successfully"
          else
            echo "  ✗ Compilation failed!"
            exit 1
          fi
        fi
      done
      
      # Link shared library
      echo "Linking shared library libwawona.so..."
      $CC -shared $OBJ_FILES \
         -Landroid-dependencies/lib \
         $(pkg-config --libs wayland-server wayland-client pixman-1) \
         -llog -landroid -lvulkan \
         -flto -O3 --target=${androidToolchain.androidTarget} \
         -o libwawona.so
      
      echo "=== Building APK ==="
      
      # Setup build directories
      mkdir -p build/gen build/obj build/apk build/res
      
      # Find Android tools and SDK
      # We expect androidSDK to be in the environment or passed as argument
      if [ -n "${androidSDK.androidsdk}" ]; then
        export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
      fi
      
      echo "Using Android SDK at $ANDROID_SDK_ROOT"
      
      if [ -d "$ANDROID_SDK_ROOT/build-tools" ]; then
        BUILD_TOOLS_DIR=$(ls -d $ANDROID_SDK_ROOT/build-tools/* | tail -n 1)
        export PATH="$BUILD_TOOLS_DIR:$PATH"
        echo "Added build-tools to PATH: $BUILD_TOOLS_DIR"
      else
        echo "Warning: build-tools not found in SDK"
      fi
      
      if [ -d "$ANDROID_SDK_ROOT/platforms" ]; then
        if [ -d "$ANDROID_SDK_ROOT/platforms/android-35" ]; then
          PLATFORM_DIR="$ANDROID_SDK_ROOT/platforms/android-35"
        elif [ -d "$ANDROID_SDK_ROOT/platforms/android-34" ]; then
          PLATFORM_DIR="$ANDROID_SDK_ROOT/platforms/android-34"
        else
           # Fallback to any platform
           PLATFORM_DIR=$(ls -d $ANDROID_SDK_ROOT/platforms/android-* | tail -n 1)
        fi
        ANDROID_JAR="$PLATFORM_DIR/android.jar"
        echo "Using android.jar: $ANDROID_JAR"
      else
        echo "Error: Platforms not found in SDK"
        exit 1
      fi
      
      # Compile resources
      echo "Compiling resources..."
      # Create necessary directory structure if it doesn't exist
      mkdir -p src/android/res/values
      
      # Compile strings.xml
      if [ -f src/android/res/values/strings.xml ]; then
        aapt2 compile src/android/res/values/strings.xml -o build/res/
      else
        echo "Warning: strings.xml not found at src/android/res/values/strings.xml"
        # Create a dummy strings.xml if needed? No, user should have created it.
      fi
      
      # Link resources
      echo "Linking resources..."
      aapt2 link -o build/apk/resources.apk -I "$ANDROID_JAR" \
          --manifest src/android/AndroidManifest.xml \
          --java build/gen \
          --output-text-symbols build/R.txt \
          build/res/*.flat
          
      # Compile Java
      echo "Compiling Java..."
      javac -d build/obj -classpath "$ANDROID_JAR" \
          src/android/java/com/aspauldingcode/wawona/MainActivity.java \
          build/gen/com/aspauldingcode/wawona/R.java
          
      # Dexing
      echo "Dexing..."
      d8 --output build/apk --lib "$ANDROID_JAR" $(find build/obj -name "*.class")
      
      # Package APK
      echo "Packaging APK..."
      cp build/apk/resources.apk Wawona.apk
      cd build/apk
      zip -u ../../Wawona.apk classes.dex
      cd ../..
      
      # Add native libraries
      echo "Adding native libraries..."
      mkdir -p lib/arm64-v8a
      cp libwawona.so lib/arm64-v8a/
      
      # Copy dependencies (handling symlinks)
      if [ -d android-dependencies/lib ]; then
        find android-dependencies/lib -name "*.so*" -exec cp -L {} lib/arm64-v8a/ \;
      fi
      
      # Fix shared library names and SONAMEs for Android
      # Android expects libs to be named lib<name>.so and may have issues with versioned SONAMEs
      echo "Fixing shared libraries..."
      cd lib/arm64-v8a
      chmod +w *
      for lib in *.so*; do
        # Check if file is a valid ELF file
        if file "$lib" | grep -q "ELF"; then
          # Strip version number from filename if present (e.g. libpixman-1.so.0 -> libpixman-1.so)
          # Note: We need to be careful not to break dependencies
          
          # Use patchelf to set SONAME to the unversioned name
          # But first we need to decide on the unversioned name
          
          # Simple heuristic: if it ends with .so.X.Y or .so.X, rename to .so
          if [[ "$lib" =~ \.so\.[0-9]+ ]]; then
             newname=$(echo "$lib" | sed -E 's/\.so\.[0-9.]*$/.so/')
             if [ "$lib" != "$newname" ]; then
               echo "Renaming $lib -> $newname"
               mv "$lib" "$newname"
               
               # Update SONAME
               patchelf --set-soname "$newname" "$newname"
             fi
          fi
        fi
      done
      
      # Now we need to fix dependencies (DT_NEEDED) in all libs to match the new names
      for lib in *.so; do
         echo "Patching dependencies for $lib..."
         needed=$(patchelf --print-needed "$lib")
         for n in $needed; do
           # Check if this needed lib was renamed
           if [[ "$n" =~ \.so\.[0-9]+ ]]; then
             newn=$(echo "$n" | sed -E 's/\.so\.[0-9.]*$/.so/')
             # If the new name exists in our dir, update the dependency
             if [ -f "$newn" ]; then
                echo "  Replacing dependency $n -> $newn in $lib"
                patchelf --replace-needed "$n" "$newn" "$lib"
             fi
           fi
         done
      done
      cd ../..
      
      zip -u Wawona.apk lib/arm64-v8a/*.so
      
      # Sign APK
      echo "Signing APK..."
      keytool -genkey -v -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
      
      apksigner sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android Wawona.apk
      
      echo "✅ APK built successfully: Wawona.apk"
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/bin
      mkdir -p $out/lib
      
      # Copy APK
      if [ -f Wawona.apk ]; then
        cp Wawona.apk $out/bin/
      else
        echo "Error: Wawona.apk not found!"
        exit 1
      fi
      
      # Copy runtime shared libraries (still useful for debugging or other purposes, 
      # though they are now inside the APK)
      if [ -d android-dependencies/lib ]; then
        find android-dependencies/lib -name "*.so*" -exec cp -L {} $out/lib/ \;
      fi
      
      # Create wrapper script that uses Nix-provided Android emulator
      cat > $out/bin/wawona-android-run <<EOF
#!/usr/bin/env bash
set -e

# Setup environment from Nix build
export PATH="${androidSDK.androidsdk}/bin:\$PATH"
export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"

APK_PATH="\$1"
if [ -z "\$APK_PATH" ]; then
  APK_PATH="\$(dirname "\$0")/Wawona.apk"
fi

if [ ! -f "\$APK_PATH" ]; then
  echo "Error: APK not found at \$APK_PATH" >&2
  exit 1
fi

# Tools are provided via Nix runtimeInputs - they should be in PATH
if ! command -v adb >/dev/null 2>&1; then
  echo "Error: adb not found in PATH." >&2
  exit 1
fi

if ! command -v emulator >/dev/null 2>&1; then
  echo "Error: emulator not found in PATH." >&2
  exit 1
fi

echo "✅ Android tools available from Nix"
echo ""

echo "   Using SDK root: \$ANDROID_SDK_ROOT"

# Set up AVD home in a user-writable directory (use local directory to avoid permission issues)
export ANDROID_USER_HOME="\$(pwd)/.android_home"
export ANDROID_AVD_HOME="\$ANDROID_USER_HOME/avd"
mkdir -p "\$ANDROID_AVD_HOME"

AVD_NAME="WawonaEmulator_API35"
SYSTEM_IMAGE="system-images;android-35;google_apis_playstore;arm64-v8a"

# Check if AVD exists
if ! emulator -list-avds | grep -q "^\$AVD_NAME\$"; then
  echo "⚠️  AVD '\$AVD_NAME' not found. Creating it..."
  
  if ! command -v avdmanager >/dev/null 2>&1; then
    echo "Error: avdmanager not found. Cannot create AVD." >&2
    exit 1
  fi
  
  echo "Creating AVD '\$AVD_NAME' with system image '\$SYSTEM_IMAGE'..."
  # Create AVD
  echo "no" | avdmanager create avd -n "\$AVD_NAME" -k "\$SYSTEM_IMAGE" --device "pixel" --force
  
  echo "✅ AVD created."
fi

# Check for running emulators
echo "Checking for running Android emulators..."
# Ensure adb server is running
adb start-server

RUNNING_EMULATORS=\$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')

if [ "\$RUNNING_EMULATORS" -gt 0 ]; then
  echo "✅ Found \$RUNNING_EMULATORS running emulator(s)"
  EMULATOR_SERIAL=\$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | head -n 1 | awk '{print \$1}')
  echo "Using emulator: \$EMULATOR_SERIAL"
else
  echo "⚠️  No Android emulator running."
  echo ""
  echo "Starting Android emulator '\$AVD_NAME'..."
  
  # Start emulator in background
  emulator -avd "\$AVD_NAME" -no-snapshot-load -gpu auto >/tmp/emulator.log 2>&1 &
  EMULATOR_PID=\$!
  
  cleanup() {
    if [ -n "\$EMULATOR_PID" ]; then
      echo "Stopping emulator..."
      echo "   (Keeping emulator running for debugging)"
    fi
  }
  trap cleanup EXIT
  
  echo "Waiting for emulator to boot..."
  TIMEOUT=300
  ELAPSED=0
  BOOTED=false
  
  while [ \$ELAPSED -lt \$TIMEOUT ]; do
    if ! kill -0 \$EMULATOR_PID 2>/dev/null; then
       echo "❌ Emulator process died unexpectedly!"
       echo "   Logs:"
       cat /tmp/emulator.log
       exit 1
    fi

    if adb devices | grep -E "emulator-[0-9]+" | grep -q "device$"; then
      sleep 2
      BOOT_COMPLETE=\$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
      if [ "\$BOOT_COMPLETE" = "1" ]; then
        BOOTED=true
        break
      fi
    fi
    
    sleep 2
    ELAPSED=\$((ELAPSED + 2))
    if [ \$((ELAPSED % 10)) -eq 0 ]; then
      echo "   Waiting... (\''${ELAPSED}s)"
    fi
  done
  
  if [ "\$BOOTED" = "true" ]; then
    echo "✅ Emulator booted successfully!"
    sleep 5
  else
    echo "❌ Timeout waiting for emulator to boot."
    echo "   Check /tmp/emulator.log for details."
    cat /tmp/emulator.log
    exit 1
  fi
fi

echo "Deploying Wawona APK to Android Emulator..."

# Uninstall existing app if present
echo "Uninstalling existing app..."
adb uninstall com.aspauldingcode.wawona || true

# Clear logcat
adb logcat -c || true

# Install APK
echo "Installing APK..."
adb install -r "\$APK_PATH"

# Launch Activity
echo "Launching Wawona Activity..."
adb shell am start -n com.aspauldingcode.wawona/.MainActivity

echo "✅ Wawona Android app launched!"
echo "   Check the emulator screen."
echo ""
echo "📋 Streaming logs (Ctrl+C to stop)..."
echo ""

# Stream logs to stdout for debugging
adb logcat -s Wawona:D AndroidRuntime:E *:S

EOF
      chmod +x $out/bin/wawona-android-run
      
      runHook postInstall
    '';
  };
}
