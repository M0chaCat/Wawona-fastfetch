{ lib, pkgs, wawonaSrc, ... }:

rec {
  # Common dependencies
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

  # Source files list (from CMakeLists.txt)
  commonSources = [
    # macOS/iOS platform files
    "src/platform/macos/main.m"
    "src/platform/macos/WawonaCompositor.m"
    "src/platform/macos/WawonaCompositor.h"
    "src/platform/macos/WawonaCompositorBridge.m"
    "src/platform/macos/WawonaCompositorBridge.h"
    "src/platform/macos/WawonaCompositorView_macos.m"
    "src/platform/macos/WawonaCompositorView_macos.h"
    "src/platform/ios/WawonaCompositorView_ios.m"
    "src/platform/ios/WawonaCompositorView_ios.h"
    "src/platform/macos/WawonaCompositor_macos.m"
    "src/platform/macos/WawonaCompositor_macos.h"
    "src/platform/macos/WawonaFrameCallbackManager.m"
    "src/platform/macos/WawonaFrameCallbackManager.h"
    "src/platform/macos/WawonaProtocolSetup.m"
    "src/platform/macos/WawonaProtocolSetup.h"
    "src/platform/macos/WawonaClientManager.m"
    "src/platform/macos/WawonaClientManager.h"
    "src/platform/macos/WawonaEventLoopManager.m"
    "src/platform/macos/WawonaEventLoopManager.h"
    "src/platform/macos/WawonaWindowLifecycle_macos.m"
    "src/platform/macos/WawonaWindowLifecycle_macos.h"
    "src/platform/macos/WawonaDisplayLinkManager.m"
    "src/platform/macos/WawonaDisplayLinkManager.h"
    "src/platform/macos/WawonaBackendManager.m"
    "src/platform/macos/WawonaBackendManager.h"
    "src/platform/macos/WawonaWindowManager.m"
    "src/platform/macos/WawonaWindowManager.h"
    "src/platform/macos/WawonaRenderManager.m"
    "src/platform/macos/WawonaRenderManager.h"
    "src/platform/macos/WawonaStartupManager.m"
    "src/platform/macos/WawonaStartupManager.h"
    "src/platform/macos/WawonaShutdownManager.m"
    "src/platform/macos/WawonaShutdownManager.h"
    "src/platform/macos/WawonaSettings.h"
    "src/platform/macos/WawonaSettings.m"
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
    # "src/compositor_implementations/wayland_primary_selection.c"
    # "src/compositor_implementations/wayland_primary_selection.h"
    "src/compositor_implementations/wayland_protocol_stubs.c"
    "src/compositor_implementations/wayland_protocol_stubs.h"
    # "src/compositor_implementations/wayland_viewporter.c"
    # "src/compositor_implementations/wayland_viewporter.h"
    # Removed: Legacy fullscreen_shell (using Rust protocols)
    # Removed: wayland_fullscreen_shell (uses C protocol constants)
    # "src/compositor_implementations/wayland_fullscreen_shell.c"
    # "src/compositor_implementations/wayland_fullscreen_shell.h"
    # Removed: Legacy wayland_shell (using Rust protocols)
    # "src/compositor_implementations/wayland_shell.c"
    # "src/compositor_implementations/wayland_shell.h"
    # Removed dead code: wayland_gtk_shell, wayland_plasma_shell, wayland_qt_extensions
    # (stubs for these protocols are in wayland_protocol_stubs.c)
    # "src/compositor_implementations/wayland_screencopy.c"
    # "src/compositor_implementations/wayland_screencopy.h"
    # "src/compositor_implementations/wayland_presentation.c"
    # "src/compositor_implementations/wayland_presentation.h"
    # Removed: wayland_color_management (uses C protocol constants)
    # Color management will be handled by Rust protocols
    # "src/compositor_implementations/wayland_color_management.c"
    # "src/compositor_implementations/wayland_color_management.h"
    # Removed: wayland_linux_dmabuf (uses C protocol constants)
    # "src/compositor_implementations/wayland_linux_dmabuf.c"
    # "src/compositor_implementations/wayland_linux_dmabuf.h"
    # Removed: wayland_drm (uses C protocol constants)
    # "src/compositor_implementations/wayland_drm.c"
    # "src/compositor_implementations/wayland_drm.h"
    # "src/compositor_implementations/wayland_idle_inhibit.c"
    # "src/compositor_implementations/wayland_idle_inhibit.h"
    # "src/compositor_implementations/wayland_pointer_gestures.c"
    # "src/compositor_implementations/wayland_pointer_gestures.h"
    # "src/compositor_implementations/wayland_relative_pointer.c"
    # "src/compositor_implementations/wayland_relative_pointer.h"
    # "src/compositor_implementations/wayland_pointer_constraints.c"
    # "src/compositor_implementations/wayland_pointer_constraints.h"
    # "src/compositor_implementations/wayland_tablet.c"
    # "src/compositor_implementations/wayland_tablet.h"
    # "src/compositor_implementations/wayland_idle_manager.c"
    # "src/compositor_implementations/wayland_idle_manager.h"
    # "src/compositor_implementations/wayland_keyboard_shortcuts.c"
    # "src/compositor_implementations/wayland_keyboard_shortcuts.h"
    # Removed: Legacy C protocol files (using Rust protocols instead)
    # "src/compositor_implementations/wayland_decoration.c"
    # "src/compositor_implementations/wayland_decoration.h"
    "src/compositor_implementations/xdg_shell.c"
    "src/compositor_implementations/xdg_shell.h"

    # Removed: Legacy C protocol definitions (using Rust crate re-exports instead)
    # All Wayland protocols now accessed via src/core/wayland/protocol/
    # "src/protocols/primary-selection-protocol.c"
    # "src/protocols/primary-selection-protocol.h"
    # "src/protocols/xdg-activation-protocol.c"
    # "src/protocols/xdg-activation-protocol.h"
    # "src/protocols/fractional-scale-protocol.c"
    # "src/protocols/fractional-scale-protocol.h"
    # "src/protocols/cursor-shape-protocol.c"
    # "src/protocols/cursor-shape-protocol.h"
    # "src/protocols/text-input-v3-protocol.c"
    # "src/protocols/text-input-v3-protocol.h"
    # "src/protocols/text-input-v1-protocol.c"
    # "src/protocols/text-input-v1-protocol.h"
    # "src/protocols/xdg-decoration-protocol.c"
    # "src/protocols/xdg-decoration-protocol.h"
    # "src/protocols/xdg-toplevel-icon-protocol.c"
    # "src/protocols/xdg-toplevel-icon-protocol.h"
    # "src/protocols/fullscreen-shell-unstable-v1-protocol.c"
    # "src/protocols/fullscreen-shell-unstable-v1-protocol.h"
    # "src/protocols/linux-dmabuf-unstable-v1-protocol.c"
    # "src/protocols/linux-dmabuf-unstable-v1-protocol.h"
    # "src/protocols/xdg-shell-protocol.c"
    # "src/protocols/xdg-shell-protocol.h"
    # "src/protocols/viewporter-protocol.c"
    # "src/protocols/viewporter-protocol.h"
    # "src/protocols/presentation-time-protocol.h"
    # "src/protocols/color-management-v1-protocol.c"
    # "src/protocols/color-management-v1-protocol.h"
    # "src/protocols/tablet-stub.c"

    # Rendering (platform-specific Metal code)
    "src/platform/macos/metal_dmabuf.m"
    "src/platform/macos/metal_dmabuf.h"
    "src/platform/macos/metal_waypipe.m"
    "src/platform/macos/metal_waypipe.h"
    "src/platform/macos/RenderingBackend.m"
    "src/platform/macos/RenderingBackend.h"
    "src/platform/macos/WawonaSurfaceManager.m"
    "src/platform/macos/WawonaSurfaceManager.h"
    "src/rendering/renderer_apple.m"
    "src/rendering/renderer_apple.h"
    "src/rendering/renderer_apple_helpers.m"

    # Input handling
    "src/input/input_handler.m"
    "src/input/input_handler.h"
    "src/input/wayland_seat.c"
    "src/input/wayland_seat.h"
    "src/input/cursor_shape_bridge.m"

    # UI components
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
    
    # Platform Adapters (macOS/iOS)
    "src/platform/macos/WawonaPlatformCallbacks.m"
    "src/platform/macos/WawonaPlatformCallbacks.h"
    "src/platform/macos/WawonaRustBridge.h"

    # Stubs
    "src/stubs/egl_buffer_handler.h"
  ];

  # Helper to filter source files that exist
  filterSources = sources: lib.filter (f: 
    if lib.hasPrefix "/" f then lib.pathExists f
    else lib.pathExists (wawonaSrc + "/" + f)
  ) sources;

  # Compiler flags from CMakeLists.txt
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
    "-mmacosx-version-min=26.0"
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
    "-mmacosx-version-min=26.0"
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

  debugCFlags = [
    "-g"
    "-O0"
    "-fno-omit-frame-pointer"
  ];
}
