{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  androidSDK ? null,
}:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  androidToolchain = import ./common/android-toolchain.nix { inherit lib pkgs; };
  gradleDeps = pkgs.callPackage ./gradle-deps.nix {
    inherit wawonaSrc androidSDK;
    inherit (pkgs) gradle jdk17;
  };

  # Read version from VERSION file
  versionString = lib.fileContents (wawonaSrc + "/VERSION");
  versionMatch = builtins.match "^([0-9]+)\\.([0-9]+)\\.([0-9]+)" (
    lib.removeSuffix "\n" versionString
  );
  projectVersion =
    if versionMatch != null then
      "${lib.elemAt versionMatch 0}.${lib.elemAt versionMatch 1}.${lib.elemAt versionMatch 2}"
    else
      "0.0.1";
  projectVersionMajor = if versionMatch != null then lib.elemAt versionMatch 0 else "0";
  projectVersionMinor = if versionMatch != null then lib.elemAt versionMatch 1 else "0";
  projectVersionPatch = if versionMatch != null then lib.elemAt versionMatch 2 else "1";

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

  # Platform specific dependencies
  macosDeps = commonDeps ++ [
    "kosmickrisp"
    "epoll-shim"
    "xkbcommon"
  ];
  # For iOS Simulator, use macOS waypipe since simulator runs on macOS
  # Rust's aarch64-apple-ios target compiles for device, not simulator, so use macOS waypipe
  iosDeps = commonDeps ++ [
    "kosmickrisp"
    "epoll-shim"
    "libclc"
    "spirv-llvm-translator"
    "spirv-tools"
    "zlib"
    "pixman"
    "xkbcommon"
  ];
  androidDeps = commonDeps ++ [
    "swiftshader"
    "pixman"
  ];

  getDeps =
    platform: depNames:
    map (
      name:
      if name == "pixman" then
        # Pixman needs to be built for the target platform
        if platform == "ios" then
          buildModule.ios.pixman
        else if platform == "android" then
          buildModule.android.pixman
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
      else
        buildModule.${platform}.${name}
    ) depNames;

  # Source files list (from CMakeLists.txt)
  commonSources = [
    # Core compositor
    "src/core/main.m"
    "src/core/WawonaCompositor.m"
    "src/core/WawonaCompositor.h"
    "src/core/WawonaSettings.c"
    "src/core/WawonaSettings.h"
    "src/core/WawonaSettings.m"

    # Logging
    "src/logging/logging.c"
    "src/logging/logging.h"

    # Wayland protocol implementations
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
    "src/compositor_implementations/wayland_gtk_shell.c"
    "src/compositor_implementations/wayland_gtk_shell.h"
    "src/compositor_implementations/wayland_plasma_shell.c"
    "src/compositor_implementations/wayland_plasma_shell.h"
    "src/compositor_implementations/wayland_qt_extensions.c"
    "src/compositor_implementations/wayland_qt_extensions.h"
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

  iosSources = (lib.filter (f: f != "src/core/WawonaSettings.c") commonSources) ++ [
    "src/ui/ios_launcher_client.m"
    "src/ui/ios_launcher_client.h"
    "src/protocols/color-management-v1-protocol.c"
  ];

  # macOS sources - exclude Vulkan renderer for now (Metal is primary, Vulkan linking issues)
  macosSources = lib.filter (
    f:
    f != "src/rendering/vulkan_renderer.m"
    && f != "src/rendering/vulkan_renderer.h"
    && f != "src/core/WawonaSettings.c"
  ) commonSources;

  # Android sources - only C files, no Objective-C (no Apple frameworks)
  # Exclude Apple-specific files that use TargetConditionals.h or Apple frameworks
  androidSources =
    lib.filter (
      f:
      (!(lib.hasSuffix ".m" f) || f == "src/core/WawonaCompositor.m")
      # Allow WawonaCompositor.m (dual C/ObjC)
      && f != "src/compositor_implementations/wayland_color_management.c"
      # Uses TargetConditionals.h
      && f != "src/compositor_implementations/wayland_color_management.h"
      # Uses TargetConditionals.h
      && f != "src/stubs/egl_buffer_handler.h"
      # Header for Apple-specific implementation
      && f != "src/core/main.m" # Use Android-specific entry point
    ) commonSources
    ++ [
      "src/stubs/egl_buffer_handler.c" # Android has its own EGL implementation
      "src/android/android_jni.c" # Android JNI bridge
      "src/rendering/android_dmabuf.c" # Android implementation of dmabuf stubs
    ];

  # Helper to filter source files that exist (evaluated at Nix time)
  filterSources = sources: lib.filter (f: lib.pathExists (wawonaSrc + "/" + f)) sources;

  # Filtered source lists (evaluated at Nix time)
  macosSourcesFiltered = filterSources macosSources;
  iosSourcesFiltered = filterSources iosSources;
  androidSourcesFiltered = filterSources androidSources;

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

  debugCFlags = [
    "-g"
    "-O0"
    "-fno-omit-frame-pointer"
  ];

  # Shared icon generation logic
  generateIcons = platform: ''
        # Locate source icon
        ICON_SOURCE="$src/src/resources/Wawona.icon/Assets/wayland.png"
        if [ ! -f "$ICON_SOURCE" ]; then
          ICON_SOURCE="$src/src/resources/wayland.png"
        fi
        
        if [ ! -f "$ICON_SOURCE" ]; then
          echo "Error: Source icon not found!"
        else
          echo "Generating icons for ${platform}..."
          
          # Prepare directory structure
          TMP_ASSETS="TempAssets.xcassets"
          ICONSET_DIR="$TMP_ASSETS/AppIcon.appiconset"
          mkdir -p "$ICONSET_DIR"
          
          # Determine sizes and contents based on platform
          if [ "${platform}" == "macos" ]; then
             # Generate macOS icon sizes
             sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" 2>/dev/null || true
             sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" 2>/dev/null || true
             sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" 2>/dev/null || true
             sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" 2>/dev/null || true
             sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" 2>/dev/null || true
             sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null || true
             sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" 2>/dev/null || true
             sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null || true
             sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" 2>/dev/null || true
             sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" 2>/dev/null || true
             
             # Write Contents.json for macOS
             cat > "$ICONSET_DIR/Contents.json" <<EOF
    {
      "images" : [
        { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16.png", "scale" : "1x" },
        { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16@2x.png", "scale" : "2x" },
        { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "1x" },
        { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32@2x.png", "scale" : "2x" },
        { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png", "scale" : "1x" },
        { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png", "scale" : "2x" },
        { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "1x" },
        { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png", "scale" : "2x" },
        { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "1x" },
        { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png", "scale" : "2x" }
      ],
      "info" : { "version" : 1, "author" : "xcode" }
    }
    EOF
             
             # Compile with actool
             ACTOOL_CMD=""
             if command -v actool >/dev/null 2>&1; then
               ACTOOL_CMD="actool"
             elif command -v xcrun >/dev/null 2>&1; then
               ACTOOL_CMD="xcrun actool"
             fi
             
             if [ -n "$ACTOOL_CMD" ]; then
               echo "Compiling Assets.car for macOS using $ACTOOL_CMD..."
               mkdir -p "$out/Applications/Wawona.app/Contents/Resources"
               
               # Run actool with verbose output and capture errors
               set +e
               $ACTOOL_CMD "$TMP_ASSETS" --compile "$out/Applications/Wawona.app/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist "$TMP_ASSETS/partial.plist" 2>&1 | tee actool_output.log
               ACTOOL_EXIT=$?
               set -e
               
               if [ $ACTOOL_EXIT -ne 0 ]; then
                 echo "actool failed with exit code $ACTOOL_EXIT"
                 cat actool_output.log
                 echo "Warning: Assets.car generation failed, but continuing build..."
               elif [ ! -f "$out/Applications/Wawona.app/Contents/Resources/Assets.car" ]; then
                 echo "Warning: Assets.car was not created at expected location"
                 echo "Checking for Assets.car in other locations..."
                 find "$out" -name "Assets.car" -type f || echo "Assets.car not found anywhere"
                 echo "actool output:"
                 cat actool_output.log || true
                 echo "Warning: Continuing build without Assets.car (app may work without it)"
               else
                 echo "Successfully created Assets.car"
               fi
               rm -f actool_output.log
             else
               echo "Warning: actool not found, skipping Assets.car generation"
             fi
             
             # Also generate .icns for fallback
             if command -v iconutil >/dev/null 2>&1; then
                mkdir -p "$TMP_ASSETS/AppIcon.iconset"
                cp "$ICONSET_DIR/icon_16x16.png" "$TMP_ASSETS/AppIcon.iconset/icon_16x16.png"
                cp "$ICONSET_DIR/icon_16x16@2x.png" "$TMP_ASSETS/AppIcon.iconset/icon_16x16@2x.png"
                cp "$ICONSET_DIR/icon_32x32.png" "$TMP_ASSETS/AppIcon.iconset/icon_32x32.png"
                cp "$ICONSET_DIR/icon_32x32@2x.png" "$TMP_ASSETS/AppIcon.iconset/icon_32x32@2x.png"
                cp "$ICONSET_DIR/icon_128x128.png" "$TMP_ASSETS/AppIcon.iconset/icon_128x128.png"
                cp "$ICONSET_DIR/icon_128x128@2x.png" "$TMP_ASSETS/AppIcon.iconset/icon_128x128@2x.png"
                cp "$ICONSET_DIR/icon_256x256.png" "$TMP_ASSETS/AppIcon.iconset/icon_256x256.png"
                cp "$ICONSET_DIR/icon_256x256@2x.png" "$TMP_ASSETS/AppIcon.iconset/icon_256x256@2x.png"
                cp "$ICONSET_DIR/icon_512x512.png" "$TMP_ASSETS/AppIcon.iconset/icon_512x512.png"
                cp "$ICONSET_DIR/icon_512x512@2x.png" "$TMP_ASSETS/AppIcon.iconset/icon_512x512@2x.png"
                
                iconutil -c icns "$TMP_ASSETS/AppIcon.iconset" -o "$out/Applications/Wawona.app/Contents/Resources/AppIcon.icns" 2>/dev/null || true
             fi

          else # iOS
             # Generate iOS icon sizes
             # iPhone
             sips -z 40 40 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_20pt@2x.png" 2>/dev/null || true
             sips -z 60 60 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_20pt@3x.png" 2>/dev/null || true
             sips -z 58 58 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_29pt@2x.png" 2>/dev/null || true
             sips -z 87 87 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_29pt@3x.png" 2>/dev/null || true
             sips -z 80 80 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_40pt@2x.png" 2>/dev/null || true
             sips -z 120 120 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_40pt@3x.png" 2>/dev/null || true
             sips -z 120 120 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_60pt@2x.png" 2>/dev/null || true
             sips -z 180 180 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_60pt@3x.png" 2>/dev/null || true
             
             # iPad
             sips -z 20 20 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_20pt.png" 2>/dev/null || true
             sips -z 29 29 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_29pt.png" 2>/dev/null || true
             sips -z 40 40 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_40pt.png" 2>/dev/null || true
             sips -z 76 76 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_76pt.png" 2>/dev/null || true
             sips -z 152 152 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_76pt@2x.png" 2>/dev/null || true
             sips -z 167 167 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_83.5pt@2x.png" 2>/dev/null || true
             
             # App Store
             sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_1024x1024.png" 2>/dev/null || true
             
             # Write Contents.json for iOS
             cat > "$ICONSET_DIR/Contents.json" <<EOF
    {
      "images" : [
        { "size" : "20x20", "idiom" : "iphone", "filename" : "icon_20pt@2x.png", "scale" : "2x" },
        { "size" : "20x20", "idiom" : "iphone", "filename" : "icon_20pt@3x.png", "scale" : "3x" },
        { "size" : "29x29", "idiom" : "iphone", "filename" : "icon_29pt@2x.png", "scale" : "2x" },
        { "size" : "29x29", "idiom" : "iphone", "filename" : "icon_29pt@3x.png", "scale" : "3x" },
        { "size" : "40x40", "idiom" : "iphone", "filename" : "icon_40pt@2x.png", "scale" : "2x" },
        { "size" : "40x40", "idiom" : "iphone", "filename" : "icon_40pt@3x.png", "scale" : "3x" },
        { "size" : "60x60", "idiom" : "iphone", "filename" : "icon_60pt@2x.png", "scale" : "2x" },
        { "size" : "60x60", "idiom" : "iphone", "filename" : "icon_60pt@3x.png", "scale" : "3x" },
        { "size" : "20x20", "idiom" : "ipad", "filename" : "icon_20pt.png", "scale" : "1x" },
        { "size" : "20x20", "idiom" : "ipad", "filename" : "icon_20pt@2x.png", "scale" : "2x" },
        { "size" : "29x29", "idiom" : "ipad", "filename" : "icon_29pt.png", "scale" : "1x" },
        { "size" : "29x29", "idiom" : "ipad", "filename" : "icon_29pt@2x.png", "scale" : "2x" },
        { "size" : "40x40", "idiom" : "ipad", "filename" : "icon_40pt.png", "scale" : "1x" },
        { "size" : "40x40", "idiom" : "ipad", "filename" : "icon_40pt@2x.png", "scale" : "2x" },
        { "size" : "76x76", "idiom" : "ipad", "filename" : "icon_76pt.png", "scale" : "1x" },
        { "size" : "76x76", "idiom" : "ipad", "filename" : "icon_76pt@2x.png", "scale" : "2x" },
        { "size" : "83.5x83.5", "idiom" : "ipad", "filename" : "icon_83.5pt@2x.png", "scale" : "2x" },
        { "size" : "1024x1024", "idiom" : "ios-marketing", "filename" : "icon_1024x1024.png", "scale" : "1x" }
      ],
      "info" : { "version" : 1, "author" : "xcode" }
    }
    EOF

             # Compile with actool
             ACTOOL_CMD=""
             if command -v actool >/dev/null 2>&1; then
               ACTOOL_CMD="actool"
             elif command -v xcrun >/dev/null 2>&1; then
               ACTOOL_CMD="xcrun actool"
             fi

             if [ -n "$ACTOOL_CMD" ]; then
               echo "Compiling Assets.car for iOS using $ACTOOL_CMD..."
               mkdir -p "$out/Applications/Wawona.app"
               
               # Determine platform based on SDKROOT (iphonesimulator for simulator, iphoneos for device)
               PLATFORM="iphoneos"
               if [ -n "$SDKROOT" ] && echo "$SDKROOT" | grep -q "iPhoneSimulator"; then
                 PLATFORM="iphonesimulator"
               fi
               
               echo "Using platform: $PLATFORM"
               
               # Run actool with verbose output and capture errors
               set +e
               $ACTOOL_CMD "$TMP_ASSETS" --compile "$out/Applications/Wawona.app" --platform "$PLATFORM" --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist "$TMP_ASSETS/partial.plist" 2>&1 | tee actool_output.log
               ACTOOL_EXIT=$?
               set -e
               
               if [ $ACTOOL_EXIT -ne 0 ]; then
                 echo "actool failed with exit code $ACTOOL_EXIT"
                 cat actool_output.log
                 echo "Warning: Assets.car generation failed, but continuing build..."
               elif [ ! -f "$out/Applications/Wawona.app/Assets.car" ]; then
                 echo "Warning: Assets.car was not created at expected location"
                 echo "Checking for Assets.car in other locations..."
                 find "$out" -name "Assets.car" -type f || echo "Assets.car not found anywhere"
                 echo "actool output:"
                 cat actool_output.log || true
                 echo "Warning: Continuing build without Assets.car (app may work without it)"
               else
                 echo "Successfully created Assets.car"
               fi
               rm -f actool_output.log
             else
               echo "Warning: actool not found, skipping Assets.car generation"
             fi
          fi
          
          rm -rf "$TMP_ASSETS"
        fi
  '';

in
{
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
      pkgs.libxkbcommon
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
         -Isrc -Isrc/core -Isrc/compositor_implementations \
         -Isrc/rendering -Isrc/input -Isrc/ui \
         -Isrc/logging -Isrc/stubs -Isrc/protocols \
         -Imacos-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonCFlags} \
         ${lib.concatStringsSep " " releaseCFlags} \
         src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
         -o gbm-wrapper.o

      $CC -c src/rendering/metal_dmabuf.m \
         -Isrc -Isrc/core -Isrc/compositor_implementations \
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
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Imacos-dependencies/include \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " commonObjCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -DHAVE_VULKAN=0 \
               -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Imacos-dependencies/include \
               -fPIC \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " releaseCFlags} \
               -DHAVE_VULKAN=0 \
               -o "$obj_file"
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
      elif pkg-config --exists vulkan; then
        VULKAN_LIB=$(pkg-config --libs vulkan)
      fi

      # Try linking with Vulkan first, fall back to without if it fails
      if [ -n "$VULKAN_LIB" ] && echo "$OBJ_FILES" | grep -q "vulkan_renderer"; then
        set +e
        # Get xkbcommon libs explicitly
        XKBCOMMON_LIBS=$(pkg-config --libs libxkbcommon 2>/dev/null || echo "-Lmacos-dependencies/lib -lxkbcommon")
        $CC $OBJ_FILES libgbm.a \
           -Lmacos-dependencies/lib \
           -framework Cocoa -framework QuartzCore -framework CoreVideo \
           -framework CoreMedia -framework CoreGraphics -framework ColorSync \
           -framework Metal -framework MetalKit -framework IOSurface \
           -framework VideoToolbox -framework AVFoundation \
           $(pkg-config --libs wayland-server wayland-client pixman-1) \
           $XKBCOMMON_LIBS \
           $VULKAN_LIB \
           -fobjc-arc -flto -O3 \
           -Wl,-rpath,\$PWD/macos-dependencies/lib \
           -o Wawona 2>&1
        LINK_RESULT=$?
        set -e
        if [ $LINK_RESULT -ne 0 ]; then
          # Remove vulkan_renderer object file and link without it
          OBJ_FILES_NO_VULKAN=$(echo "$OBJ_FILES" | sed 's/rendering_vulkan_renderer\.m\.o//g')
          # Get xkbcommon libs explicitly
          XKBCOMMON_LIBS=$(pkg-config --libs libxkbcommon 2>/dev/null || echo "-Lmacos-dependencies/lib -lxkbcommon")
          $CC $OBJ_FILES_NO_VULKAN libgbm.a \
             -Lmacos-dependencies/lib \
             -framework Cocoa -framework QuartzCore -framework CoreVideo \
             -framework CoreMedia -framework CoreGraphics -framework ColorSync \
             -framework Metal -framework MetalKit -framework IOSurface \
             -framework VideoToolbox -framework AVFoundation \
             $(pkg-config --libs wayland-server wayland-client pixman-1) \
             $XKBCOMMON_LIBS \
             -fobjc-arc -flto -O3 \
             -Wl,-rpath,\$PWD/macos-dependencies/lib \
             -o Wawona
        fi
      else
        # No Vulkan needed
        # Get xkbcommon libs explicitly
        XKBCOMMON_LIBS=$(pkg-config --libs libxkbcommon 2>/dev/null || echo "-Lmacos-dependencies/lib -lxkbcommon")
        $CC $OBJ_FILES libgbm.a \
           -Lmacos-dependencies/lib \
           -framework Cocoa -framework QuartzCore -framework CoreVideo \
           -framework CoreMedia -framework CoreGraphics -framework ColorSync \
           -framework Metal -framework MetalKit -framework IOSurface \
           -framework VideoToolbox -framework AVFoundation \
           $(pkg-config --libs wayland-server wayland-client pixman-1) \
           $XKBCOMMON_LIBS \
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
          <key>CFBundleIcons</key>
          <dict>
              <key>CFBundlePrimaryIcon</key>
              <dict>
                  <key>CFBundleIconName</key>
                  <string>AppIcon</string>
              </dict>
          </dict>
          <key>CFBundleIconFile</key>
          <string>AppIcon.icns</string>
      </dict>
      </plist>
      EOF
            
            # Copy Assets.xcassets (asset catalog) for app icon
            # Note: We now generate icons using a shared logic and compile them
            ${generateIcons "macos"}
            
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
         -Isrc -Isrc/core -Isrc/compositor_implementations \
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
         -Isrc -Isrc/core -Isrc/compositor_implementations \
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
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Iios-dependencies/include \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " commonObjCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
               -DTARGET_OS_IPHONE=1 \
               -DHAVE_VULKAN=0 \
               -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols \
               -Iios-dependencies/include \
               -fPIC \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
               -DHAVE_VULKAN=0 \
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
      
      # Link executable
      $CC $OBJ_FILES libgbm.a \
         -Lios-dependencies/lib \
         -framework Foundation -framework UIKit -framework QuartzCore \
         -framework CoreVideo -framework CoreMedia -framework CoreGraphics \
         -framework Metal -framework MetalKit -framework IOSurface \
         -framework VideoToolbox -framework AVFoundation \
         $(pkg-config --libs wayland-server wayland-client pixman-1) \
         $XKBCOMMON_LIBS \
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
          <key>UILaunchScreen</key>
          <dict/>
          <key>CFBundleIcons</key>
          <dict>
              <key>CFBundlePrimaryIcon</key>
              <dict>
                  <key>CFBundleIconFiles</key>
                  <array>
                      <string>AppIcon</string>
                  </array>
                  <key>CFBundleIconName</key>
                  <string>AppIcon</string>
              </dict>
          </dict>
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
            
            # Generate icons using shared logic
            ${generateIcons "ios"}
            
            # Copy Settings.bundle if it exists
            if [ -d $src/src/resources/Settings.bundle ]; then
              cp -r $src/src/resources/Settings.bundle $out/Applications/Wawona.app/
            fi
            
            # Copy dynamic libraries to Frameworks
            mkdir -p $out/Applications/Wawona.app/Frameworks
            if [ -d ios-dependencies/lib ]; then
              # Copy dylibs
              find ios-dependencies/lib -name "*.dylib" -exec cp -L {} $out/Applications/Wawona.app/Frameworks/ \;
              
              # Fix dylib paths
              cd $out/Applications/Wawona.app/Frameworks
              for lib in *.dylib; do
                if [ -f "$lib" ]; then
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
              EXECUTABLE="$out/Applications/Wawona.app/Wawona"
              otool -L "$EXECUTABLE" | grep ".dylib" | while read -r line; do
                dep_path=$(echo $line | awk '{print $1}')
                dep_name=$(basename "$dep_path")
                if [ -f "$out/Applications/Wawona.app/Frameworks/$dep_name" ]; then
                  install_name_tool -change "$dep_path" "@rpath/$dep_name" "$EXECUTABLE"
                fi
              done
            fi
            
            # Copy Waypipe binary into app bundle
            # Find waypipe in buildInputs
            WAYPIPE_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/waypipe" ]; then
                WAYPIPE_BIN="$dep/bin/waypipe"
                echo "Found Waypipe binary at: $WAYPIPE_BIN"
                break
              fi
            done
            
            if [ -n "$WAYPIPE_BIN" ] && [ -f "$WAYPIPE_BIN" ]; then
              # Copy to multiple locations for maximum compatibility
              # 1. In bin/ subdirectory (preferred location)
              mkdir -p $out/Applications/Wawona.app/bin
              cp "$WAYPIPE_BIN" $out/Applications/Wawona.app/bin/waypipe
              chmod +x $out/Applications/Wawona.app/bin/waypipe
              
              # 2. In bundle root (fallback for iOS Simulator)
              cp "$WAYPIPE_BIN" $out/Applications/Wawona.app/waypipe
              chmod +x $out/Applications/Wawona.app/waypipe
              
              # 3. Next to executable (another fallback)
              cp "$WAYPIPE_BIN" $out/Applications/Wawona.app/waypipe-bin
              chmod +x $out/Applications/Wawona.app/waypipe-bin
              
              echo "Copied Waypipe binary to app bundle (bin/, root, and waypipe-bin)"
              echo "Waypipe binary size: $(ls -lh "$WAYPIPE_BIN" | awk '{print $5}')"
            else
              echo "Warning: Waypipe binary not found in buildInputs"
              echo "Searched in: $buildInputs"
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
        exit 1
      fi

      # Check if xcrun is available
      if ! command -v xcrun >/dev/null 2>&1; then
        exit 1
      fi

      # Check if iOS Simulator runtime is installed
      RUNTIMES=$(xcrun simctl list runtimes available 2>/dev/null | grep -i "iOS" | head -n 1 || true)

      if [ -z "$RUNTIMES" ]; then
        if xcodebuild -downloadPlatform iOS 2>&1; then
          sleep 2
        else
          exit 1
        fi
      fi

      # Find an iOS simulator (prefer iPhone, then iPad)
      DEVICE_ID=$(xcrun simctl list devices available 2>/dev/null | grep -iE "(iPhone|iPad)" | grep -v "unavailable" | head -n 1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' | head -n 1)

      if [ -z "$DEVICE_ID" ]; then
        # Try to create a simulator if none exists
        RUNTIME=$(xcrun simctl list runtimes available 2>/dev/null | grep -i "iOS" | head -n 1 | sed -E 's/.*\(([^)]+)\).*/\1/' | head -n 1)
        
        if [ -z "$RUNTIME" ]; then
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
          DEVICE_ID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME" 2>/dev/null || true)
          
          if [ -z "$DEVICE_ID" ]; then
            exit 1
          fi
        else
          exit 1
        fi
      fi

      DEVICE_NAME=$(xcrun simctl list devices available | grep "$DEVICE_ID" | sed -E 's/.*- (.*) \(.*/\1/' | head -n 1)

      # Check if simulator is booted
      BOOTED=$(xcrun simctl list devices | grep "$DEVICE_ID" | grep -c "Booted" || true)
      if [ "$BOOTED" -eq 0 ]; then
        xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
        sleep 5
      fi

      # Open Simulator app and bring it to the foreground
      # Use 'open -a' which brings the app forward even if already running
      open -a Simulator
      sleep 2

      # Ensure Simulator is in the foreground (macOS focuses it)
      osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
      sleep 3

      # Copy app bundle to a writable location (simulator can't install from read-only Nix store)
      TEMP_APP_DIR=$(mktemp -d)
      TEMP_APP_BUNDLE="$TEMP_APP_DIR/Wawona.app"
      cp -R "$APP_BUNDLE" "$TEMP_APP_BUNDLE" || {
        rm -rf "$TEMP_APP_DIR"
        exit 1
      }

      # Fix permissions - make all files writable (simulator needs to modify them during install)
      chmod -R u+w "$TEMP_APP_BUNDLE" || true

      # Ad-hoc sign the app bundle for Simulator (required for Apple Silicon)
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
            codesign --force --sign - --timestamp=none "$fw" || true
          done
        fi
        
        # Sign main executable
        codesign --force --sign - --timestamp=none --entitlements "$TEMP_APP_DIR/entitlements.plist" "$TEMP_APP_BUNDLE" 2>/dev/null || \
        codesign --force --sign - --timestamp=none "$TEMP_APP_BUNDLE" || true
      fi

      # Cleanup function - use force removal to handle permission issues
      cleanup() {
        chmod -R u+w "$TEMP_APP_DIR" 2>/dev/null || true
        rm -rf "$TEMP_APP_DIR" 2>/dev/null || true
      }
      trap cleanup EXIT

      # Uninstall existing app if present (to avoid conflicts)
      BUNDLE_ID="com.aspauldingcode.Wawona"
      xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true

      # Install the app from the temporary location
      xcrun simctl install "$DEVICE_ID" "$TEMP_APP_BUNDLE" || {
        exit 1
      }

      # Verify app was installed
      INSTALLED=$(xcrun simctl listapps "$DEVICE_ID" 2>/dev/null | grep -c "$BUNDLE_ID" || echo "0")

      # Launch the app
      xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" 2>&1 || true

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
      jdk17 # Full JDK needed for Gradle
      gradle
      unzip
      zip
      patchelf
      file
      util-linux # Provides setsid for creating new process groups
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

      # Compile C/C++ code for Android (native library)
      OBJ_FILES=""
      for src_file in ${lib.concatStringsSep " " androidSourcesFiltered}; do
        if [[ "$src_file" == *.c ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if $CC -c "$src_file" \
             -Isrc -Isrc/core -Isrc/compositor_implementations \
             -Isrc/rendering -Isrc/input -Isrc/ui \
             -Isrc/logging -Isrc/stubs -Isrc/protocols \
             -Iandroid-dependencies/include \
             -fPIC \
             ${lib.concatStringsSep " " commonCFlags} \
             ${lib.concatStringsSep " " debugCFlags} \
             --target=${androidToolchain.androidTarget} \
             -o "$obj_file"; then
            OBJ_FILES="$OBJ_FILES $obj_file"
          else
            exit 1
          fi
        fi
      done

      # Link shared library
      $CC -shared $OBJ_FILES \
         -Landroid-dependencies/lib \
         $(pkg-config --libs wayland-server wayland-client pixman-1) \
         -llog -landroid -lvulkan \
         -g --target=${androidToolchain.androidTarget} \
         -o libwawona.so
         
      # Setup Gradle and dependencies
      export GRADLE_USER_HOME=$(pwd)/.gradle_home
      export ANDROID_USER_HOME=$(pwd)/.android_home
      mkdir -p $ANDROID_USER_HOME

      # Copy gradleDeps to writable location
      cp -r ${gradleDeps} $GRADLE_USER_HOME
      chmod -R u+w $GRADLE_USER_HOME

      export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
      export ANDROID_HOME="$ANDROID_SDK_ROOT"

      # Place native libs where Gradle expects them
      # Gradle sourceSets point to src/android/java, so jniLibs should be at src/android/jniLibs/arm64-v8a
      mkdir -p src/android/jniLibs/arm64-v8a
      cp libwawona.so src/android/jniLibs/arm64-v8a/

      # Copy other shared libs (dependencies)
      if [ -d android-dependencies/lib ]; then
        find android-dependencies/lib -name "*.so*" -exec cp -L {} src/android/jniLibs/arm64-v8a/ \;
      fi

      # Also copy libc++_shared.so
      NDK_ROOT="${androidToolchain.androidndkRoot}"
      LIBCPP_SHARED=$(find "$NDK_ROOT" -name "libc++_shared.so" | grep "aarch64" | head -n 1)
      if [ -f "$LIBCPP_SHARED" ]; then
        cp "$LIBCPP_SHARED" src/android/jniLibs/arm64-v8a/
      fi

      # Fix SONAMEs in copied libs (same logic as before, but in jniLibs)
      cd src/android/jniLibs/arm64-v8a
      chmod +w *
      for lib in *.so*; do
          if [[ "$lib" =~ \.so\.[0-9]+ ]]; then
             newname=$(echo "$lib" | sed -E 's/\.so\.[0-9.]*$/.so/')
             if [ "$lib" != "$newname" ]; then
               mv "$lib" "$newname"
               patchelf --set-soname "$newname" "$newname"
             fi
          fi
      done

      # Fix dependencies
      for lib in *.so; do
         needed=$(patchelf --print-needed "$lib")
         for n in $needed; do
           if [[ "$n" =~ \.so\.[0-9]+ ]]; then
             newn=$(echo "$n" | sed -E 's/\.so\.[0-9.]*$/.so/')
             if [ -f "$newn" ]; then
                patchelf --replace-needed "$n" "$newn" "$lib"
             fi
           fi
         done
      done
      # Return to src/android directory (we were in jniLibs/arm64-v8a)
      cd "$(pwd | sed 's|/jniLibs/arm64-v8a.*||')"

      # We should now be in src/android, verify and build APK with Gradle
      if [ ! -f "build.gradle.kts" ]; then
        echo "Error: build.gradle.kts not found. Current directory: $(pwd)"
        ls -la
        exit 1
      fi

      gradle assembleDebug --offline --no-daemon

      runHook postBuild
    '';

    installPhase = ''
            runHook preInstall
            
            mkdir -p $out/bin
            mkdir -p $out/lib
            
            # Copy APK - APK is built in src/android/build/outputs/apk/debug/
            # We're in source root, so check both possible locations
            APK_PATH=""
            if [ -f "src/android/build/outputs/apk/debug/Wawona-debug.apk" ]; then
              APK_PATH="src/android/build/outputs/apk/debug/Wawona-debug.apk"
            elif [ -f "src/android/app/build/outputs/apk/debug/app-debug.apk" ]; then
              APK_PATH="src/android/app/build/outputs/apk/debug/app-debug.apk"
            else
              echo "APK not found in expected locations, searching..."
              APK_PATH=$(find . -name "*.apk" -type f | head -1)
              if [ -z "$APK_PATH" ]; then
                echo "Error: No APK found!"
                exit 1
              fi
              echo "Found APK at: $APK_PATH"
            fi
            
            cp "$APK_PATH" $out/bin/Wawona.apk
            echo "Copied APK to $out/bin/Wawona.apk"
            
            # Copy runtime shared libraries (still useful for debugging or other purposes, 
            # though they are now inside the APK)
            if [ -d android-dependencies/lib ]; then
              find android-dependencies/lib -name "*.so*" -exec cp -L {} $out/lib/ \;
            fi
            
            # Create wrapper script that uses Nix-provided Android emulator
            cat > $out/bin/wawona-android-run <<EOF
      #!/usr/bin/env bash
      # Don't use set -e here - we want to handle errors gracefully
      set +e

      # Setup environment from Nix build
      export PATH="${
        lib.makeBinPath [
          androidSDK.platform-tools
          androidSDK.emulator
          androidSDK.androidsdk
          pkgs.util-linux
        ]
      }:\$PATH"
      export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
      export ANDROID_HOME="\$ANDROID_SDK_ROOT"

      APK_PATH="\$1"
      if [ -z "\$APK_PATH" ]; then
        APK_PATH="\$(dirname "\$0")/Wawona.apk"
      fi

      if [ ! -f "\$APK_PATH" ]; then
        exit 1
      fi

      # Tools are provided via Nix runtimeInputs - they should be in PATH
      if ! command -v adb >/dev/null 2>&1; then
        exit 1
      fi

      if ! command -v emulator >/dev/null 2>&1; then
        exit 1
      fi

      # Set up AVD home in a user-writable directory (use local directory to avoid permission issues)
      export ANDROID_USER_HOME="\$(pwd)/.android_home"
      export ANDROID_AVD_HOME="\$ANDROID_USER_HOME/avd"
      mkdir -p "\$ANDROID_AVD_HOME"

      AVD_NAME="WawonaEmulator_API36"
      SYSTEM_IMAGE="system-images;android-36;google_apis_playstore;arm64-v8a"

      # Check if AVD exists
      if ! emulator -list-avds | grep -q "^\$AVD_NAME\$"; then
        
        if ! command -v avdmanager >/dev/null 2>&1; then
          exit 1
        fi
        
        # Create AVD
        echo "no" | avdmanager create avd -n "\$AVD_NAME" -k "\$SYSTEM_IMAGE" --device "pixel" --force
        
      fi

      # Check for running emulators
      # Ensure adb server is running
      adb start-server

      # Check for running emulators by both adb and process name
      # This ensures we catch emulators even if adb hasn't fully detected them yet
      # We check for ANY emulator process first, then verify it's the right AVD
      EMULATOR_PROCESS=\$(pgrep -f "emulator.*\$AVD_NAME" | head -n 1)

      # If we found an emulator process, check if adb can see it
      if [ -n "\$EMULATOR_PROCESS" ]; then
        # Wait a bit for adb to detect the emulator
        sleep 2
        RUNNING_EMULATORS=\$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')
        
        # If adb still doesn't see it, check if the process is actually running
        if [ "\$RUNNING_EMULATORS" -eq 0 ]; then
          # Check if process is still alive
          if kill -0 "\$EMULATOR_PROCESS" 2>/dev/null; then
            # Process is running but adb hasn't detected it yet - wait longer
            sleep 3
            RUNNING_EMULATORS=\$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')
          else
            # Process died, reset
            EMULATOR_PROCESS=""
          fi
        fi
      else
        # No emulator process found, check adb anyway
        RUNNING_EMULATORS=\$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')
      fi

      if [ "\$RUNNING_EMULATORS" -gt 0 ]; then
        EMULATOR_SERIAL=\$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | head -n 1 | awk '{print \$1}')
      else
        
        # Start emulator in a completely detached way that survives SIGTERM
        # Use setsid (from util-linux) to create a new session and process group
        # This isolates the emulator from this script's process group, preventing SIGTERM propagation
        # setsid creates a new session, making the emulator immune to signals sent to the parent
        setsid nohup emulator -avd "\$AVD_NAME" -no-snapshot-load -gpu auto < /dev/null >>/tmp/emulator.log 2>&1 &
        
        # Give emulator a moment to start
        sleep 3
        
        # Find the emulator PID by process name (should now be child of init, not this script)
        # Try multiple times as emulator takes time to fully start
        EMULATOR_PID=""
        for i in 1 2 3 4 5; do
          EMULATOR_PID=\$(pgrep -f "emulator.*\$AVD_NAME" | head -n 1)
          if [ -n "\$EMULATOR_PID" ]; then
            break
          fi
          sleep 1
        done
        
        if [ -z "\$EMULATOR_PID" ]; then
          echo "Warning: Could not find emulator PID, but it should be running"
          echo "Check /tmp/emulator.log for details"
        else
          echo "Emulator started with PID: \$EMULATOR_PID (running independently)"
          echo "Emulator will continue running even if this script receives SIGTERM"
        fi
        
        # Handle signals gracefully - don't kill emulator on SIGTERM/SIGINT
        # The emulator is already disowned, so it will survive script termination
        cleanup() {
          # Don't kill the emulator - it should continue running independently
          # Just exit the script gracefully
          exit 0
        }
        trap cleanup SIGTERM SIGINT
        
        TIMEOUT=300
        ELAPSED=0
        BOOTED=false
        
        while [ \$ELAPSED -lt \$TIMEOUT ]; do
          # Check if emulator process is still running (but don't fail if it's not our direct child)
          if ! kill -0 \$EMULATOR_PID 2>/dev/null; then
             # Emulator might have exited, check if it's actually running via adb
             if ! adb devices | grep -E "emulator-[0-9]+" | grep -q "device$"; then
               cat /tmp/emulator.log
               exit 1
             fi
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
        done
        
        if [ "\$BOOTED" = "true" ]; then
          sleep 5
        else
          # Check one more time if emulator is actually running
          if adb devices | grep -E "emulator-[0-9]+" | grep -q "device$"; then
            # Emulator is running, just took longer to boot
            BOOTED=true
          else
            cat /tmp/emulator.log
            exit 1
          fi
        fi
        
        # Clear the trap since emulator is booted and independent
        trap - SIGTERM SIGINT
      fi

      # Set up a signal handler for graceful exit during app installation/logcat
      # The emulator will continue running even if script is terminated
      graceful_exit() {
        echo ""
        echo "Script terminated. Emulator continues running in background."
        echo "To stop the emulator later, use: adb emu kill"
        exit 0
      }
      trap graceful_exit SIGTERM SIGINT

      # Uninstall existing app if present
      adb uninstall com.aspauldingcode.wawona || true

      # Clear logcat
      adb logcat -c || true

      # Install APK
      adb install -r "\$APK_PATH"

      # Launch Activity
      echo "Launching Wawona app..."
      adb shell am start -n com.aspauldingcode.wawona/.MainActivity

      # Wait a moment for the app to start
      sleep 5

      # Get crash logs first - show everything related to Wawona and crashes
      echo "=== Recent crash logs ==="
      adb logcat -d -v time | grep -i -E "(wawona|androidruntime|fatal|exception|error.*3995)" | tail -200

      # Stream logs to stdout - show Wawona logs, AndroidRuntime errors, and system crashes
      # This will run until interrupted (SIGTERM/SIGINT), at which point the emulator continues running
      echo ""
      echo "=== Starting live logcat stream ==="
      echo "Showing: Wawona, WawonaJNI, WawonaNative, AndroidRuntime errors"
      echo "Press Ctrl+C to stop logcat (emulator will continue running)"
      adb logcat -v time -s Wawona:D WawonaJNI:D WawonaNative:D AndroidRuntime:E

      EOF
            chmod +x $out/bin/wawona-android-run
            
            runHook postInstall
    '';
  };
}
