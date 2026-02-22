{ lib, pkgs, wawonaSrc, ... }:

rec {
  # Common dependencies
  commonDeps = [
    "waypipe"
    "zstd"
    "lz4"
  ];

  # Source files shared across macOS AND iOS builds.
  # All ObjC filenames use the WWN prefix (global rename from Wawona* in 2026).
  # macOS-only files (WWNWindow*, WWNMacOS*, WWNPopupHost*) live in macos.nix.
  # iOS-only files (WWNCompositorView_ios*, WWNSceneDelegate*) live in ios.nix.
  commonSources = [
    # Platform bridge (shared between macOS and iOS)
    "src/platform/macos/main.m"
    "src/platform/macos/WWNCompositorBridge.m"
    "src/platform/macos/WWNCompositorBridge.h"
    "src/platform/macos/WWNSettings.h"
    "src/platform/macos/WWNSettings.m"
    "src/platform/macos/WWNSettings.c"
    "src/platform/macos/WWNPlatformCallbacks.m"
    "src/platform/macos/WWNPlatformCallbacks.h"
    "src/platform/macos/WWNRustBridge.h"
    "src/platform/macos/RenderingBackend.m"
    "src/platform/macos/RenderingBackend.h"

    # Rendering
    "src/rendering/renderer_apple.m"
    "src/rendering/renderer_apple.h"

    # UI components
    "src/ui/Helpers/WWNImageLoader.m"
    "src/ui/Helpers/WWNImageLoader.h"
    "src/ui/Settings/WWNPreferences.m"
    "src/ui/Settings/WWNPreferences.h"
    "src/ui/Settings/WWNPreferencesManager.m"
    "src/ui/Settings/WWNPreferencesManager.h"
    "src/ui/About/WWNAboutPanel.m"
    "src/ui/About/WWNAboutPanel.h"
    "src/ui/Settings/WWNSettingsDefines.h"
    "src/ui/Settings/WWNSettingsModel.m"
    "src/ui/Settings/WWNSettingsModel.h"
    "src/ui/Settings/WWNWaypipeRunner.m"
    "src/ui/Settings/WWNWaypipeRunner.h"
    "src/ui/Settings/WWNSSHClient.m"
    "src/ui/Settings/WWNSSHClient.h"
    "src/ui/Settings/WWNSettingsSplitViewController.m"
    "src/ui/Settings/WWNSettingsSplitViewController.h"
    "src/ui/Settings/WWNSettingsSidebarViewController.m"
    "src/ui/Settings/WWNSettingsSidebarViewController.h"

    # Launcher (shared)
    "src/launcher/WWNAppScanner.m"
    "src/launcher/WWNAppScanner.h"

    # Top-level headers
    "src/apple_backend.h"
    "src/config.h"
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
  ];

  # Apple-only deployment target flag (not valid for Android)
  appleCFlags = [ "-mmacosx-version-min=26.0" ];

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

  debugCFlags = [
    "-g"
    "-O0"
    "-fno-omit-frame-pointer"
  ];
}
