{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  hiahkernel,
  compositor,
}:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  xcodeEnv =
    platform: ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/${if platform == "ios" then "iPhoneSimulator" else "MacOSX"}.platform/Developer/SDKs/${if platform == "ios" then "iPhoneSimulator" else "MacOSX"}.sdk"
        fi
      fi
    '';
  copyDeps =
    dest: ''
      mkdir -p ${dest}/include ${dest}/lib ${dest}/libdata/pkgconfig
      for dep in $buildInputs; do
        if [ -d "$dep/include" ]; then cp -rn "$dep/include/"* ${dest}/include/ 2>/dev/null || true; fi
        if [ -d "$dep/lib" ]; then cp -rn "$dep/lib/"* ${dest}/lib/ 2>/dev/null || true; fi
        if [ -d "$dep/lib/pkgconfig" ]; then cp -rn "$dep/lib/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
        if [ -d "$dep/libdata/pkgconfig" ]; then cp -rn "$dep/libdata/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
      done
    '';
  # Define patched HIAHKernel package
  hiahkernelPackage = (hiahkernel.packages.${pkgs.system}.hiah-library-ios-sim or hiahkernel.packages.${pkgs.system}.hiah-library-ios).overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ../scripts/patches/hiahkernel-socket-path.patch ];
  });

  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;

  commonDeps = [
    "libwayland"
    "waypipe"
    "libffi"
    "expat"
    "libxml2"
    "zstd"
    "lz4"
    "ffmpeg"
  ];

  # Rust's aarch64-apple-ios target compiles for device, not simulator, so use macOS waypipe
  iosDeps = commonDeps ++ [
    "kosmickrisp"
    "epoll-shim"
    "libclc"
    "spirv-llvm-translator"
    "openssh"
    "spirv-tools"
    "zlib"
    "pixman"
    "xkbcommon"
    "hiahkernel"
    # Note: libssh2 and mbedtls removed - using OpenSSH binary instead
  ];

  getDeps =
    platform: depNames:
    map (
      name:
      if name == "pixman" then
        # Pixman needs to be built for the target platform
        if platform == "ios" then
          buildModule.ios.pixman
        else
          pkgs.pixman # macOS can use nixpkgs pixman
      else if name == "waypipe" then
        # Use iOS waypipe built with aarch64-apple-ios-sim target
        buildModule.${platform}.${name}
      else if name == "vulkan-headers" then
        pkgs.vulkan-headers
      else if name == "vulkan-loader" then
        pkgs.vulkan-loader
      else if name == "xkbcommon" then
        if platform == "ios" then
          buildModule.buildForIOS "xkbcommon" { }
        else
          pkgs.libxkbcommon
      else if name == "hiahkernel" then
        hiahkernelPackage
      else
        buildModule.${platform}.${name}
    ) depNames;

  commonSources = [
    # Core compositor
    "src/core/main.m"
    "src/core/WawonaCompositor.m"
    "src/core/WawonaCompositor.h"
    "src/core/WawonaCompositorView_macos.m"
    "src/core/WawonaCompositorView_macos.h"
    "src/core/WawonaCompositorView_ios.m"
    "src/core/WawonaCompositorView_ios.h"
    "src/core/WawonaCompositor_macos.m"
    "src/core/WawonaCompositor_macos.h"
    "src/core/WawonaFrameCallbackManager.m"
    "src/core/WawonaFrameCallbackManager.h"
    "src/core/WawonaProtocolSetup.m"
    "src/core/WawonaProtocolSetup.h"
    "src/core/WawonaClientManager.m"
    "src/core/WawonaClientManager.h"
    "src/core/WawonaEventLoopManager.m"
    "src/core/WawonaEventLoopManager.h"
    "src/core/WawonaWindowLifecycle_macos.m"
    "src/core/WawonaWindowLifecycle_macos.h"
    "src/core/WawonaDisplayLinkManager.m"
    "src/core/WawonaDisplayLinkManager.h"
    "src/core/WawonaBackendManager.m"
    "src/core/WawonaBackendManager.h"
    "src/core/WawonaWindowManager.m"
    "src/core/WawonaWindowManager.h"
    "src/core/WawonaRenderManager.m"
    "src/core/WawonaRenderManager.h"
    "src/core/WawonaStartupManager.m"
    "src/core/WawonaStartupManager.h"
    "src/core/WawonaShutdownManager.m"
    "src/core/WawonaShutdownManager.h"
    "src/core/WawonaSettings.h"
    "src/core/WawonaSettings.m"
    # "src/core/WawonaKernel.h" - Removed (using HIAHKernel library)
    # "src/core/WawonaKernel.m" - Removed (using HIAHKernel library)

    # Logging
    "src/logging/logging.c"
    "src/logging/logging.h"
    "src/logging/WawonaLog.h"
    "src/logging/WawonaLog.m"

    # Wayland protocol implementations
    "src/compositor_implementations/wayland_compositor.c"
    "src/compositor_implementations/wayland_compositor.h"
    "src/compositor_implementations/wayland_output.c"
    "src/compositor_implementations/wayland_output.h"
    "src/compositor_implementations/wayland_shm.c"
    "src/compositor_implementations/wayland_shm.h"
    "src/compositor_implementations/wayland_subcompositor.c"
    "src/compositor_implementations/wayland_subcompositor.h"
    "src/compositor_implementations/wayland_data_device_manager.c"
    "src/compositor_implementations/wayland_data_device_manager.h"
    "src/compositor_implementations/wayland_primary_selection.c"
    "src/compositor_implementations/wayland_primary_selection.h"
    "src/compositor_implementations/wayland_protocol_stubs.c"
    "src/compositor_implementations/wayland_protocol_stubs.h"
    "src/compositor_implementations/wayland_viewporter.c"
    "src/compositor_implementations/wayland_viewporter.h"
    "src/compositor_implementations/wayland_fullscreen_shell.c"
    "src/compositor_implementations/wayland_fullscreen_shell.h"
    "src/compositor_implementations/wayland_shell.c"
    "src/compositor_implementations/wayland_shell.h"
    # Removed dead code: wayland_gtk_shell, wayland_plasma_shell, wayland_qt_extensions
    # (stubs for these protocols are in wayland_protocol_stubs.c)
    "src/compositor_implementations/wayland_screencopy.c"
    "src/compositor_implementations/wayland_screencopy.h"
    "src/compositor_implementations/wayland_presentation.c"
    "src/compositor_implementations/wayland_presentation.h"
    "src/compositor_implementations/wayland_color_management.c"
    "src/compositor_implementations/wayland_color_management.h"
    "src/compositor_implementations/wayland_linux_dmabuf.c"
    "src/compositor_implementations/wayland_linux_dmabuf.h"
    "src/compositor_implementations/wayland_drm.c"
    "src/compositor_implementations/wayland_drm.h"
    "src/compositor_implementations/wayland_idle_inhibit.c"
    "src/compositor_implementations/wayland_idle_inhibit.h"
    "src/compositor_implementations/wayland_pointer_gestures.c"
    "src/compositor_implementations/wayland_pointer_gestures.h"
    "src/compositor_implementations/wayland_relative_pointer.c"
    "src/compositor_implementations/wayland_relative_pointer.h"
    "src/compositor_implementations/wayland_pointer_constraints.c"
    "src/compositor_implementations/wayland_pointer_constraints.h"
    "src/compositor_implementations/wayland_tablet.c"
    "src/compositor_implementations/wayland_tablet.h"
    "src/compositor_implementations/wayland_idle_manager.c"
    "src/compositor_implementations/wayland_idle_manager.h"
    "src/compositor_implementations/wayland_keyboard_shortcuts.c"
    "src/compositor_implementations/wayland_keyboard_shortcuts.h"
    "src/compositor_implementations/wayland_decoration.c"
    "src/compositor_implementations/wayland_decoration.h"
    "src/compositor_implementations/xdg_shell.c"
    "src/compositor_implementations/xdg_shell.h"

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
    "src/protocols/color-management-v1-protocol.c"
    "src/protocols/color-management-v1-protocol.h"
    "src/protocols/tablet-stub.c"

    # Rendering (Core Utilities)
    "src/core/metal_dmabuf.m"
    "src/core/metal_dmabuf.h"
    "src/core/metal_waypipe.m"
    "src/core/metal_waypipe.h"
    "src/core/RenderingBackend.m"
    "src/core/RenderingBackend.h"
    "src/core/WawonaSurfaceManager.m"
    "src/core/WawonaSurfaceManager.h"

    # Input handling
    "src/input/input_handler.m"
    "src/input/input_handler.h"
    "src/input/wayland_seat.c"
    "src/input/wayland_seat.h"
    "src/input/cursor_shape_bridge.m"

    # UI components
    "src/ui/Helpers/WawonaUIHelpers.m"
    "src/ui/Helpers/WawonaUIHelpers.h"
    "src/ui/Helpers/WawonaImageLoader.m"
    "src/ui/Helpers/WawonaImageLoader.h"
    "src/ui/Settings/WawonaPreferences.m"
    "src/ui/Settings/WawonaPreferences.h"
    "src/ui/Settings/WawonaPreferencesManager.m"
    "src/ui/Settings/WawonaPreferencesManager.h"
    "src/ui/About/WawonaAboutPanel.m"
    "src/ui/About/WawonaAboutPanel.h"
    "src/ui/Settings/WawonaSettingsDefines.h"
    "src/ui/Settings/WawonaSettingsModel.m"
    "src/ui/Settings/WawonaSettingsModel.h"
    "src/ui/Settings/WawonaWaypipeRunner.m"
    "src/ui/Settings/WawonaWaypipeRunner.h"
    "src/ui/Settings/WawonaSSHClient.m"
    "src/ui/Settings/WawonaSSHClient.h"
    
    # Launcher
    "src/launcher/WawonaAppScanner.m"
    "src/launcher/WawonaAppScanner.h"

    # Stubs
    "src/stubs/egl_buffer_handler.h"
  ];

  iosSources = (lib.filter (f: f != "src/core/WawonaSettings.c") commonSources) ++ [
    # "src/core/WawonaKernelTests.m"
    # "src/core/WawonaKernelTests.h"
    "src/launcher/WawonaLauncherClient.m"
    "src/launcher/WawonaLauncherClient.h"
  ];

  # App extension sources (WawonaSSHRunner.appex)
  extensionSources = [
    "src/extensions/WawonaSSHRunner/WawonaSSHRunner.m"
    "src/extensions/WawonaSSHRunner/litehook/litehook.c"
    "src/extensions/WawonaSSHRunner/litehook/litehook.h"
    "src/extensions/WawonaSSHRunner/HIAHProcessRunner.m"  # Patched copy from postPatch
  ];

  # Helper to filter source files that exist
  filterSources = sources: lib.filter (f: 
    if lib.hasPrefix "/" f then lib.pathExists f
    else lib.pathExists (wawonaSrc + "/" + f)
  ) sources;

  iosSourcesFiltered = filterSources iosSources;
  extensionSourcesFiltered = filterSources (lib.filter (f: lib.hasSuffix ".m" f) extensionSources);

  commonCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Werror"
    "-Wstrict-prototypes"
    "-Wmissing-prototypes"
    "-Wold-style-definition"
    "-Wmissing-declarations"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wwrite-strings"
    "-Wconversion"
    "-Wsign-conversion"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstrict-overflow=5"
    "-Wswitch-default"
    "-Wswitch-enum"
    "-Wunreachable-code"
    "-Wfloat-equal"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fPIC"
    "-D_FORTIFY_SOURCE=2"
    "-DUSE_RUST_CORE=1"
    # Suppress warnings
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-sign-conversion"
    "-Wno-implicit-float-conversion"
    "-Wno-missing-field-initializers"
    "-Wno-format-nonliteral"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-empty-translation-unit"
    "-Wno-format-pedantic"
  ];

  commonObjCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fobjc-arc"
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-implicit-float-conversion"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-format-nonliteral"
    "-Wno-format-pedantic"
  ];

  releaseCFlags = [
    "-O3"
    "-DNDEBUG"
    "-flto"
  ];
  releaseObjCFlags = [
    "-O3"
    "-DNDEBUG"
    "-flto"
  ];

in
  pkgs.stdenv.mkDerivation rec {
    name = "wawona-ios";
    version = projectVersion;
    src = wawonaSrc;

    # Extract specific dependencies for use in installPhase
    openssh = buildModule.ios.openssh;
    waypipe = buildModule.ios.waypipe;

    nativeBuildInputs = with pkgs; [
      clang
      pkg-config
      xcodeUtils.findXcodeScript
    ];

    buildInputs = (getDeps "ios" iosDeps) ++ [
      pkgs.vulkan-headers
      hiahkernelPackage
    ];

    # Fix gbm-wrapper.c include path and egl_buffer_handler.h for iOS
    postPatch = ''
            # Fix gbm-wrapper.c include path for metal_dmabuf.h
            substituteInPlace src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
              --replace-fail '#include "../../../../metal_dmabuf.h"' '#include "metal_dmabuf.h"'
            
            
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
      
      # Copy HIAHProcessRunner.m from source to build directory
      # We use the source from HIAHKernel input directly
      if [ -f "${hiahkernel}/src/extension/HIAHProcessRunner.m" ]; then
        echo "Found HIAHProcessRunner.m, copying..."
        mkdir -p src/extensions/WawonaSSHRunner
        cp ${hiahkernel}/src/extension/HIAHProcessRunner.m src/extensions/WawonaSSHRunner/HIAHProcessRunner.m
        
        # In HIAH_LIBRARY_MODE, we don't need to patch imports as the source handles it
        # But we DO need to make sure headers are found (via -I flags or framework includes)
        
        # Ensure directory exists and is writable
        mkdir -p src/extensions/WawonaSSHRunner
        chmod -R u+w src/extensions/WawonaSSHRunner 2>/dev/null || true
        
        cp -f ${hiahkernel}/src/extension/HIAHProcessRunner.m src/extensions/WawonaSSHRunner/HIAHProcessRunner.m
        echo "Copied HIAHProcessRunner.m (will be compiled with -DHIAH_LIBRARY_MODE)"
        
        # Manually copy headers that might be missing from the framework include path
        # to ensure <HIAHKernel/...> imports work during manual compilation
        mkdir -p src/extensions/WawonaSSHRunner/headers/HIAHKernel
        chmod -R u+w src/extensions/WawonaSSHRunner/headers 2>/dev/null || true
        
        # HIAHBypassStatus.h is now in Core/Hooks
        if [ -f "${hiahkernel}/src/HIAHKernel/Core/Hooks/HIAHBypassStatus.h" ]; then
          cp -f ${hiahkernel}/src/HIAHKernel/Core/Hooks/HIAHBypassStatus.h src/extensions/WawonaSSHRunner/headers/HIAHKernel/
          echo "Manually copied HIAHBypassStatus.h"
        else
          # Fallback trying old location just in case
          if [ -f "${hiahkernel}/src/extension/HIAHBypassStatus.h" ]; then
             cp ${hiahkernel}/src/extension/HIAHBypassStatus.h src/extensions/WawonaSSHRunner/headers/HIAHKernel/
             echo "Manually copied HIAHBypassStatus.h (from extension dir)"
          fi
        fi
        
        # HIAHDyldBypass.h
        if [ -f "${hiahkernel}/src/HIAHKernel/Core/Hooks/HIAHDyldBypass.h" ]; then
          cp -f ${hiahkernel}/src/HIAHKernel/Core/Hooks/HIAHDyldBypass.h src/extensions/WawonaSSHRunner/headers/HIAHKernel/
          echo "Manually copied HIAHDyldBypass.h"
        else
          # Check Public or root
          find ${hiahkernel} -name "HIAHDyldBypass.h" -exec cp -f {} src/extensions/WawonaSSHRunner/headers/HIAHKernel/ \;
        fi
        
        # HIAHHook.h
        if [ -f "${hiahkernel}/src/HIAHKernel/Core/Hooks/HIAHHook.h" ]; then
          cp -f ${hiahkernel}/src/HIAHKernel/Core/Hooks/HIAHHook.h src/extensions/WawonaSSHRunner/headers/HIAHKernel/
          echo "Manually copied HIAHHook.h"
        else
          find ${hiahkernel} -name "HIAHHook.h" -exec cp -f {} src/extensions/WawonaSSHRunner/headers/HIAHKernel/ \;
        fi
        
        # HIAHLogging.h (Check Core/Logging or Public)
        if [ -f "${hiahkernel}/src/HIAHKernel/Core/Logging/HIAHLogging.h" ]; then
          cp -f ${hiahkernel}/src/HIAHKernel/Core/Logging/HIAHLogging.h src/extensions/WawonaSSHRunner/headers/HIAHKernel/
          echo "Manually copied HIAHLogging.h"
        else
          find ${hiahkernel} -name "HIAHLogging.h" -exec cp -f {} src/extensions/WawonaSSHRunner/headers/HIAHKernel/ \;
        fi
        
        # HIAHKernel.h (Main header)
        find ${hiahkernel} -name "HIAHKernel.h" -exec cp -f {} src/extensions/WawonaSSHRunner/headers/HIAHKernel/ \;

        # HIAHMachOUtils.h is now in Core/Utils
        if [ -f "${hiahkernel}/src/HIAHKernel/Core/Utils/HIAHMachOUtils.h" ]; then
          cp ${hiahkernel}/src/HIAHKernel/Core/Utils/HIAHMachOUtils.h src/extensions/WawonaSSHRunner/headers/HIAHKernel/
          echo "Manually copied HIAHMachOUtils.h"
        else
           # Fallback
           if [ -f "${hiahkernel}/src/HIAHDesktop/HIAHMachOUtils.h" ]; then
             cp ${hiahkernel}/src/HIAHDesktop/HIAHMachOUtils.h src/extensions/WawonaSSHRunner/headers/HIAHKernel/
             echo "Manually copied HIAHMachOUtils.h (from HIAHDesktop dir)"
           fi
        fi
      else
        echo "ERROR: HIAHProcessRunner.m not found at ${hiahkernel}/src/extension/HIAHProcessRunner.m"
        exit 1
      fi
    '';

    # Metal shader compilation
    preBuild = ''
      ${xcodeEnv "ios"}

      if command -v metal >/dev/null 2>&1; then
        metal -c src/rendering/metal_shaders.metal -o metal_shaders.air -isysroot "$SDKROOT" -mios-simulator-version-min=26.0 || true
        if [ -f metal_shaders.air ] && command -v metallib >/dev/null 2>&1; then
          metallib metal_shaders.air -o metal_shaders.metallib || true
        fi
      fi
    '';

    preConfigure = ''
      ${xcodeEnv "ios"}

      ${copyDeps "ios-dependencies"}

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
      export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC"
      export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC"
      export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0 -lobjc"
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
         -Isrc -Isrc/core -Isrc/compositor_implementations \
         -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
         -Isrc/logging -Isrc/stubs -Isrc/protocols \
         -Iios-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonCFlags} \
         ${lib.concatStringsSep " " releaseObjCFlags} \
         -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=26.0 \
         src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
         -o gbm-wrapper.o

      $CC -c src/rendering/metal_dmabuf.m \
         -Isrc -Isrc/core -Isrc/compositor_implementations \
         -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
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
            # Note: libssh2 removed - using OpenSSH binary instead
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Isrc/extensions \
               -Iios-dependencies/include \
               -I${hiahkernel}/src \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " commonObjCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
               -DTARGET_OS_IPHONE=1 \
               -DHAVE_VULKAN=1 \
               -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Iios-dependencies/include \
               -fPIC \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
               -DHAVE_VULKAN=1 \
               -o "$obj_file"
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done

      # Get xkbcommon libs explicitly
      # xkbcommon from nixpkgs is built for macOS, not iOS
      # For iOS, we need to find it in buildInputs or use pkg-config
      XKBCOMMON_LIBS=""
      for dep in $buildInputs; do
        if [ -f "$dep/lib/libxkbcommon.a" ]; then
          XKBCOMMON_LIBS="-L$dep/lib -lxkbcommon"
          echo "Found xkbcommon static library: $dep/lib/libxkbcommon.a"
          break
        elif [ -f "$dep/lib/libxkbcommon.dylib" ]; then
          XKBCOMMON_LIBS="-L$dep/lib -lxkbcommon"
          echo "Found xkbcommon dynamic library: $dep/lib/libxkbcommon.dylib"
          break
        fi
      done
      
      # Fallback to pkg-config or ios-dependencies
      if [ -z "$XKBCOMMON_LIBS" ]; then
        XKBCOMMON_LIBS=$(pkg-config --libs libxkbcommon 2>/dev/null || echo "-Lios-dependencies/lib -lxkbcommon")
      fi
      
      echo "Linking with xkbcommon: $XKBCOMMON_LIBS"
      
      # Note: libssh2 and mbedtls removed - using OpenSSH binary instead
      
      # Find zlib library
      ZLIB_LIBS=""
      for dep in $buildInputs; do
        if [ -f "$dep/lib/libz.a" ]; then
          ZLIB_LIBS="-L$dep/lib -lz"
          echo "Found zlib static library: $dep/lib/libz.a"
          break
        elif [ -f "$dep/lib/libz.dylib" ]; then
          ZLIB_LIBS="-L$dep/lib -lz"
          echo "Found zlib dynamic library: $dep/lib/libz.dylib"
          break
        fi
      done
      
      # Fallback to pkg-config or ios-dependencies
      if [ -z "$ZLIB_LIBS" ]; then
        ZLIB_LIBS=$(pkg-config --libs zlib 2>/dev/null || echo "-Lios-dependencies/lib -lz")
      fi
      
      echo "Linking with zlib: $ZLIB_LIBS"
      
      # Link executable
      $CC $OBJ_FILES libgbm.a \
         -Lios-dependencies/lib \
         -lHIAHKernel \
         -framework Foundation -framework UIKit -framework QuartzCore \
         -framework CoreVideo -framework CoreMedia -framework CoreGraphics \
         -framework Metal -framework MetalKit -framework IOSurface \
         -framework VideoToolbox -framework AVFoundation \
         -framework Security -framework Network \
         $(pkg-config --libs wayland-server wayland-client pixman-1) \
         $XKBCOMMON_LIBS \
         $ZLIB_LIBS \
         -fobjc-arc -flto -O3 -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -Wl,-rpath,@executable_path/Frameworks \
         -o Wawona

      # Build WawonaSSHRunner app extension
      echo "Building WawonaSSHRunner.appex..."
      
      # Compile extension sources
      EXTENSION_OBJ_FILES=""
      # Compile .m files
      BUILD_ROOT=$(pwd)
      for src_file in ${lib.concatStringsSep " " extensionSourcesFiltered}; do
          src_base=$(basename $src_file .m)
          obj_file="ext_$src_base.o"
          echo "Compiling $src_file -> $obj_file..."
          src_dir=$(dirname $src_file)
          src_name=$(basename $src_file)
          abs_obj_file=$(pwd)/$obj_file
          (cd $src_dir && \
           $CC -c $src_name \
             -I. -I./litehook -I$BUILD_ROOT/src/extensions/WawonaSSHRunner/litehook \
             -I$BUILD_ROOT/src -I$BUILD_ROOT/src/core -I$BUILD_ROOT/src/extensions \
             -I$BUILD_ROOT/ios-dependencies/include -I$BUILD_ROOT/ios-dependencies/include/WawonaSSHRunner \
             -I${hiahkernel}/src \
             -I${hiahkernel}/src/HIAHKernel \
             -I${hiahkernel}/src/HIAHDesktop \
             -fobjc-arc -fPIC \
             ${lib.concatStringsSep " " commonObjCFlags} \
             ${lib.concatStringsSep " " releaseObjCFlags} \
             -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
             -DTARGET_OS_IPHONE=1 \
             -o $abs_obj_file)
          if [ ! -f $obj_file ]; then
            echo "Error: Object file $obj_file was not created at $abs_obj_file!"
            exit 1
          fi
          EXTENSION_OBJ_FILES="$EXTENSION_OBJ_FILES $obj_file"
      done
      
      # Explicitly compile HIAHProcessRunner.m (created in postPatch)
      if [ -f "src/extensions/WawonaSSHRunner/HIAHProcessRunner.m" ]; then
          echo "Compiling HIAHProcessRunner.m -> ext_HIAHProcessRunner.o..."
          obj_file="ext_HIAHProcessRunner.o"
          abs_obj_file=$(pwd)/$obj_file
          (cd src/extensions/WawonaSSHRunner && \
           $CC -c HIAHProcessRunner.m \
             -I. -I./headers -I./litehook -I$BUILD_ROOT/src/extensions/WawonaSSHRunner/litehook \
             -I$BUILD_ROOT/src -I$BUILD_ROOT/src/core -I$BUILD_ROOT/src/extensions \
             -I$BUILD_ROOT/ios-dependencies/include -I$BUILD_ROOT/ios-dependencies/include/WawonaSSHRunner \
             -fobjc-arc -fPIC \
             ${lib.concatStringsSep " " commonObjCFlags} \
             ${lib.concatStringsSep " " releaseObjCFlags} \
             -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
             -DTARGET_OS_IPHONE=1 \
             -DHIAH_LIBRARY_MODE=1 \
             "-DHIAH_APP_GROUP=@\"group.com.aspauldingcode.Wawona\"" \
             -Fios-dependencies/lib \
             -o $abs_obj_file)
          if [ ! -f $obj_file ]; then
            echo "Error: ext_HIAHProcessRunner.o was not created!"
            exit 1
          fi
          EXTENSION_OBJ_FILES="$EXTENSION_OBJ_FILES $obj_file"
          echo "Added HIAHProcessRunner object file: $obj_file"
      else
          echo "WARNING: HIAHProcessRunner.m not found, skipping"
      fi
      
      # Compile additional HIAHKernel extension source files (patched copies from postPatch)
      # Extra sources loop removed - they are now linked via HIAHKernel library
      
      # Compile ZSigner.mm if present
      if [ -f "src/extensions/WawonaSSHRunner/ZSigner.mm" ]; then
          echo "Compiling ZSigner.mm -> ext_ZSigner.o..."
          obj_file="ext_ZSigner.o"
          abs_obj_file=$(pwd)/$obj_file
          
          (cd src/extensions/WawonaSSHRunner && \
           $CC -c ZSigner.mm \
            -I. -I./headers \
            -I$BUILD_ROOT/ios-dependencies/include \
            -fobjc-arc -fPIC \
            ${lib.concatStringsSep " " commonObjCFlags} \
            ${lib.concatStringsSep " " releaseObjCFlags} \
            -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
            -DTARGET_OS_IPHONE=1 \
            -o $abs_obj_file)
            
          if [ ! -f $obj_file ]; then
            echo "Error: ext_ZSigner.o was not created!"
            exit 1
          fi
          
          EXTENSION_OBJ_FILES="$EXTENSION_OBJ_FILES $obj_file"
          echo "Added ext_ZSigner.o"
      fi
      
      # Compile .c files (like litehook.c)
      litehook_src="src/extensions/WawonaSSHRunner/litehook/litehook.c"
      if [ -f "$litehook_src" ]; then
          echo "Compiling $litehook_src -> ext_litehook.o..."
          src_dir=$(dirname $litehook_src)
          src_name=$(basename $litehook_src)
          obj_file="ext_litehook.o"
          abs_obj_file=$(pwd)/$obj_file
          (cd $src_dir && \
           $CC -c $src_name \
             -I. -I../../src -I../../src/core -I../../src/extensions \
             -I../../../ios-dependencies/include \
             -Wno-error -Wno-gnu-statement-expression-from-macro-expansion -Wno-sign-compare -Wno-gnu-statement-expression \
             $(echo "${lib.concatStringsSep " " commonCFlags}" | sed 's/-Werror//g') \
             ${lib.concatStringsSep " " releaseCFlags} \
             -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=26.0 \
             -DTARGET_OS_IPHONE=1 \
             -o $abs_obj_file)
          if [ ! -f $obj_file ]; then
             echo "Error: Object file $obj_file was not created!"
             exit 1
          fi
          EXTENSION_OBJ_FILES="$EXTENSION_OBJ_FILES $obj_file"
          echo "Added litehook object file"
      fi
      
      mkdir -p WawonaSSHRunner.appex
      
      # Link app extension
      $CC $EXTENSION_OBJ_FILES \
        -Lios-dependencies/lib \
        -lHIAHKernel \
        -framework Foundation -framework Security -framework Network -framework UIKit \
        $ZLIB_LIBS \
        -fobjc-arc -flto -O3 -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
        -e _NSExtensionMain \
        -o WawonaSSHRunner.appex/WawonaSSHRunner

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/Applications/Wawona.app
      cp Wawona $out/Applications/Wawona.app/
      
      # Copy Metal shader library
      if [ -f metal_shaders.metallib ]; then
        cp metal_shaders.metallib $out/Applications/Wawona.app/
      fi
      
      # Copy app extension
      mkdir -p $out/Applications/Wawona.app/PlugIns/WawonaSSHRunner.appex
      cp WawonaSSHRunner.appex/WawonaSSHRunner $out/Applications/Wawona.app/PlugIns/WawonaSSHRunner.appex/
      
      # Copy frameworks
      mkdir -p $out/Applications/Wawona.app/Frameworks
      for dep in $buildInputs; do
         if [ -d "$dep/lib" ]; then
            for f in $dep/lib/*.dylib; do
               if [ -f "$f" ]; then
                  cp "$f" $out/Applications/Wawona.app/Frameworks/ || true
               fi
            done
         fi
         # Copy HIAH library if present
         if [ -f "$dep/lib/libHIAHKernel.dylib" ]; then
           cp "$dep/lib/libHIAHKernel.dylib" $out/Applications/Wawona.app/Frameworks/
         fi
      done

      # Copy openssh binary for SSH functionality (rebuild marker 3)
      echo "DEBUG: Looking for ssh binary in buildInputs..."
      SSH_BIN=""
      for dep in $buildInputs; do
        if [ -f "$dep/bin/ssh" ]; then
          SSH_BIN="$dep/bin/ssh"
          echo "Found ssh binary at: $SSH_BIN"
          break
        fi
      done
      
      if [ -n "$SSH_BIN" ] && [ -f "$SSH_BIN" ]; then
        echo "DEBUG: Copying ssh to app bundle"
        # Copy to app bundle root (same as main executable)
        install -m 755 "$SSH_BIN" $out/Applications/Wawona.app/ssh
        echo "Copied ssh to Application bundle root"
        
        # Code sign ssh
        if command -v codesign >/dev/null 2>&1; then
          codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/ssh" 2>/dev/null || echo "Warning: Failed to code sign ssh"
          echo "ssh binary code signed"
        fi
      else
        echo "Warning: ssh binary not found in buildInputs"
        # Try finding it in openssh input directly
        if [ -f "${openssh}/bin/ssh" ]; then
           echo "Found ssh in openssh input, copying..."
           install -m 755 "${openssh}/bin/ssh" $out/Applications/Wawona.app/ssh
        fi
      fi
      
      # Copy waypipe binary for remote Wayland display
      # Note: using macOS waypipe binary for simulator since rust target is mismatched
      echo "DEBUG: Looking for waypipe binary in buildInputs..."
      if [ -f "${waypipe}/bin/waypipe" ]; then
         echo "Found waypipe binary at: ${waypipe}/bin/waypipe"
         install -m 755 "${waypipe}/bin/waypipe" $out/Applications/Wawona.app/waypipe
         echo "Copied waypipe to Application bundle root"
         
         # Code sign
         if command -v codesign >/dev/null 2>&1; then
            codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/waypipe" 2>/dev/null || true
         fi
      else
         echo "Warning: waypipe binary not found"
      fi

      runHook postInstall
    '';

    passthru.automationScript = pkgs.writeShellScriptBin "wawona-ios-automat" ''
      set -e

      if [ -z "$TEAM_ID" ]; then
        echo "Warning: TEAM_ID is not set. Simulator builds usually work, but physical device builds will fail."
        echo "Set TEAM_ID in your environment (e.g. .envrc) for code signing."
      else
        export TEAM_ID
      fi

      echo "Generating Xcode project..."
      ${(pkgs.callPackage ./xcodegen-wawona.nix {
         inherit pkgs;
         rustPlatform = pkgs.rustPlatform;
         hiahkernel = hiahkernel;
         wawonaVersion = projectVersion;
         compositor = compositor;
       }).app}/bin/xcodegen

      if [ ! -d "Wawona.xcodeproj" ]; then
        echo "Error: Wawona.xcodeproj not generated."
        exit 1
      fi

      SIM_NAME="Wawona iOS"
    DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
    RUNTIME=$(xcrun simctl list runtimes | grep "iOS" | tail -1 | awk '{print $NF}')
    
    if [ -z "$RUNTIME" ]; then
       echo "Error: No iOS Runtime found."
       exit 1
    fi

    echo "Checking for '$SIM_NAME' simulator..."
    # Use grep to reliably extract UUID (8-4-4-4-12 hex format)
    SIM_UDID=$(xcrun simctl list devices | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)

    if [ -z "$SIM_UDID" ]; then
      echo "Creating '$SIM_NAME' ($DEV_TYPE, $RUNTIME)..."
      SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
    fi

      echo "Simulator UDID: $SIM_UDID"
      echo "Booting simulator..."
      xcrun simctl boot "$SIM_UDID" 2>/dev/null || true

      echo "Building for iOS Simulator..."
      
      # Run build directly to see error output if it fails
      xcodebuild -scheme Wawona \
        -project Wawona.xcodeproj \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIM_UDID" \
        -derivedDataPath build/ios_sim_build \
        build

      APP_PATH="build/ios_sim_build/Build/Products/Debug-iphonesimulator/Wawona.app"
      if [ ! -d "$APP_PATH" ]; then
         echo "Error: App not found at $APP_PATH"
         exit 1
      fi

      echo "Opening Simulator and Installing app..."
      open -a Simulator
      xcrun simctl install "$SIM_UDID" "$APP_PATH"

      echo "Launching com.aspauldingcode.Wawona..."
      xcrun simctl launch --console "$SIM_UDID" com.aspauldingcode.Wawona
      
      echo "Done."
    '';
  }
