{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  androidSDK ? null,
  hiahkernel,
}:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  # Define patched HIAHKernel package
  hiahkernelPackage = hiahkernel.packages.${pkgs.system}.hiah-kernel.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ../scripts/patches/hiahkernel-socket-path.patch ];
  });

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

  iosInfoPlist = pkgs.writeText "Info.plist" ''
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
        <key>NSLocalNetworkUsageDescription</key>
        <string>Wawona needs access to your local network to connect to SSH hosts.</string>
        <key>NSAppTransportSecurity</key>
        <dict>
            <key>NSAllowsArbitraryLoads</key>
            <true/>
            <key>NSAllowsLocalNetworking</key>
            <true/>
        </dict>
    </dict>
    </plist>
  '';

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
    "sshpass"
  ];
  # For iOS Simulator, use macOS waypipe since simulator runs on macOS
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
      else if name == "hiahkernel" then
        hiahkernelPackage
      else
        buildModule.${platform}.${name}
    ) depNames;

  # Source files list (from CMakeLists.txt)
  commonSources = [
    # Core compositor
    "src/core/main.m"
    "src/core/WawonaCompositor.m"
    "src/core/WawonaCompositor.h"
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
    "src/ui/Helpers/WawonaUIHelpers.m"
    "src/ui/Helpers/WawonaUIHelpers.h"
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

  # macOS sources - include Vulkan renderer using KosmicKrisp as libvulkan
  macosSources = commonSources ++ [
    "src/rendering/vulkan_renderer.m"
    "src/rendering/vulkan_renderer.h"
  ];

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

  # Helper to filter source files that exist
  # Should handle both relative paths (in wawonaSrc) and absolute store paths
  filterSources = sources: lib.filter (f: 
    if lib.hasPrefix "/" f then lib.pathExists f
    else lib.pathExists (wawonaSrc + "/" + f)
  ) sources;

  # Filtered source lists (evaluated at Nix time)
  macosSourcesFiltered = filterSources macosSources;
  iosSourcesFiltered = filterSources iosSources;
  extensionSourcesFiltered = filterSources (lib.filter (f: lib.hasSuffix ".m" f) extensionSources);
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
            
            # VulkanRenderer is now enabled for macOS using KosmicKrisp ICD
            
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
         -Isrc/logging -Isrc/stubs -Isrc/protocols -Isrc/launcher \
         -Imacos-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonCFlags} \
         ${lib.concatStringsSep " " releaseCFlags} \
         src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
         -o gbm-wrapper.o

      $CC -c src/rendering/metal_dmabuf.m \
         -Isrc -Isrc/core -Isrc/compositor_implementations \
         -Isrc/rendering -Isrc/input -Isrc/ui \
         -Isrc/logging -Isrc/stubs -Isrc/protocols -Isrc/launcher \
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
               -Isrc/logging -Isrc/stubs -Isrc/protocols -Isrc/launcher \
               -Imacos-dependencies/include \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " commonObjCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -DHAVE_VULKAN=1 \
               -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/protocols -Isrc/launcher \
               -Imacos-dependencies/include \
               -fPIC \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " releaseCFlags} \
               -DHAVE_VULKAN=1 \
               -o "$obj_file"
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done

      # Link executable
      # Use Vulkan loader, which will load KosmicKrisp ICD
      VULKAN_LIB=""
      if [ -f macos-dependencies/lib/libvulkan.dylib ]; then
        VULKAN_LIB="-Lmacos-dependencies/lib -lvulkan"
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
           -framework VideoToolbox -framework AVFoundation -framework Network -framework Security \
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
             -framework VideoToolbox -framework AVFoundation -framework Network -framework Security \
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
           -framework VideoToolbox -framework AVFoundation -framework Network -framework Security \
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
            
            # Copy sshpass binary for non-interactive SSH password auth (rebuild marker 1)
            echo "DEBUG: Looking for sshpass binary in buildInputs..."
            echo "DEBUG: buildInputs = $buildInputs"
            SSHPASS_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/sshpass" ]; then
                SSHPASS_BIN="$dep/bin/sshpass"
                echo "Found sshpass binary at: $SSHPASS_BIN"
                break
              fi
            done
            
            if [ -n "$SSHPASS_BIN" ] && [ -f "$SSHPASS_BIN" ]; then
              echo "DEBUG: Copying sshpass to app bundle"
              # Copy to Contents/MacOS (next to main executable)
              install -m 755 "$SSHPASS_BIN" $out/Applications/Wawona.app/Contents/MacOS/sshpass
              echo "Copied sshpass to Contents/MacOS/"
              
              # Also copy to Contents/Resources/bin for alternate lookup
              mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
              install -m 755 "$SSHPASS_BIN" $out/Applications/Wawona.app/Contents/Resources/bin/sshpass
              echo "Copied sshpass to Contents/Resources/bin/"
              
              # Code sign sshpass
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/MacOS/sshpass" 2>/dev/null || echo "Warning: Failed to code sign sshpass"
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Resources/bin/sshpass" 2>/dev/null || true
                echo "sshpass binary code signed"
              fi
            else
              echo "Warning: sshpass binary not found in buildInputs"
            fi
            
            # Copy waypipe binary for remote Wayland display (rebuild marker 2)
            echo "DEBUG: Looking for waypipe binary in buildInputs..."
            WAYPIPE_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/waypipe" ]; then
                WAYPIPE_BIN="$dep/bin/waypipe"
                echo "Found waypipe binary at: $WAYPIPE_BIN"
                break
              fi
            done
            
            if [ -n "$WAYPIPE_BIN" ] && [ -f "$WAYPIPE_BIN" ]; then
              echo "DEBUG: Copying waypipe to app bundle"
              # Copy to Contents/MacOS (next to main executable)
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/Contents/MacOS/waypipe
              echo "Copied waypipe to Contents/MacOS/"
              
              # Also copy to Contents/Resources/bin for alternate lookup
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/Contents/Resources/bin/waypipe
              echo "Copied waypipe to Contents/Resources/bin/"
              
              # Code sign waypipe
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/MacOS/waypipe" 2>/dev/null || echo "Warning: Failed to code sign waypipe"
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Resources/bin/waypipe" 2>/dev/null || true
                echo "waypipe binary code signed"
              fi
            else
              echo "Warning: waypipe binary not found in buildInputs"
            fi
            
            # Generate Info.plist
            cat > $out/Applications/Wawona.app/Contents/Info.plist <<PLIST_EOF
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
          <key>NSLocalNetworkUsageDescription</key>
          <string>Wawona needs access to your local network to connect to SSH hosts.</string>
          <key>NSAppTransportSecurity</key>
          <dict>
              <key>NSAllowsArbitraryLoads</key>
              <true/>
              <key>NSAllowsLocalNetworking</key>
              <true/>
          </dict>
      </dict>
      </plist>
      PLIST_EOF
            
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

      # Extension headers are now minimal - no need to copy separate headers

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
            # Note: libssh2 removed - using OpenSSH binary instead
            $CC -c "$src_file" \
               -Isrc -Isrc/core -Isrc/compositor_implementations \
               -Isrc/rendering -Isrc/input -Isrc/ui \
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
               -Isrc/rendering -Isrc/input -Isrc/ui \
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
             -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
             -DTARGET_OS_IPHONE=1 \
             -o $abs_obj_file)
          if [ ! -f $obj_file ]; then
            echo "Error: Object file $obj_file was not created at $abs_obj_file!"
            exit 1
          fi
          echo "Added litehook object file: $obj_file"
          EXTENSION_OBJ_FILES="$EXTENSION_OBJ_FILES $obj_file"
      else
          echo "Warning: $litehook_src not found, skipping litehook compilation"
      fi
      echo "Extension object files: $EXTENSION_OBJ_FILES"
      
      # Link extension binary
      echo "Linking extension with object files: $EXTENSION_OBJ_FILES"
      echo "Checking object files exist:"
      for obj in $EXTENSION_OBJ_FILES; do
        if [ -f "$obj" ]; then
          echo "  ✓ $obj exists"
        else
          echo "  ✗ $obj MISSING!"
        fi
      done
      $CC $EXTENSION_OBJ_FILES \
         -Lios-dependencies/lib \
         -lHIAHKernel \
         -framework Foundation -framework UIKit \
         -fobjc-arc -flto -O3 -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -Wl,-export_dynamic -e _NSExtensionMain \
         -o WawonaSSHRunner || {
        echo "Linking failed. Object files:"
        ls -la ext_*.o 2>&1 || true
        exit 1
      }
      
      # Build WawonaHooks dylib
      echo "Building WawonaHooks.dylib..."
      # Compile litehook.c for the dylib
      litehook_dylib_obj="litehook_dylib.o"
      abs_litehook_dylib_obj=$(pwd)/$litehook_dylib_obj
      (cd src/extensions/WawonaSSHRunner/litehook && \
       $CC -c litehook.c \
         -I. -I../../src -I../../src/core -I../../src/extensions \
         -I${hiahkernel}/src \
         -I../../../ios-dependencies/include \
         -Wno-error -Wno-gnu-statement-expression-from-macro-expansion -Wno-sign-compare -Wno-gnu-statement-expression \
         $(echo "${lib.concatStringsSep " " commonCFlags}" | sed 's/-Werror//g') \
         ${lib.concatStringsSep " " releaseCFlags} \
         -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -DTARGET_OS_IPHONE=1 \
         -o $abs_litehook_dylib_obj)
      if [ ! -f $litehook_dylib_obj ]; then
        echo "Error: litehook_dylib object file not created!"
        exit 1
      fi
      $CC -dynamiclib src/extensions/WawonaSSHRunner/WawonaGuestHooks.m $litehook_dylib_obj \
         -Isrc -Isrc/extensions/WawonaSSHRunner -Isrc/extensions/WawonaSSHRunner/litehook \
         -Iios-dependencies/include \
         -fobjc-arc -fPIC \
         ${lib.concatStringsSep " " commonObjCFlags} \
         -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -install_name @executable_path/WawonaHooks.dylib \
         -framework Foundation \
         -o WawonaHooks.dylib

      # Build hello_world (Binary and Dylib for nested spawning test)
      echo "Building hello_world binary and dylib..."
      $CC -x objective-c src/bin/hello_world.c \
         -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -fobjc-arc -framework Foundation \
         -o hello_world
      $CC -x objective-c src/bin/hello_world.c \
         -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
         -fobjc-arc -framework Foundation \
         -dynamiclib \
         -o hello_world.dylib
      
      # Build openssh_test_ios (SSH connection test)
      if [ -f src/bin/openssh_test_ios.m ]; then
        echo "Building openssh_test_ios..."
        # Find required object files from main app build
        KERNEL_OBJ=""
        PREFS_MGR_OBJ=""
        echo "Searching for object files..."
        echo "OBJ_FILES contains $(echo $OBJ_FILES | wc -w) files"
        for obj in $OBJ_FILES; do
          if [[ "$obj" == *"WawonaKernel"* ]] || [[ "$obj" == *"core_WawonaKernel"* ]] || [[ "$obj" == *"Kernel"* ]]; then
            if [[ "$obj" == *.o ]] && [ -f "$obj" ]; then
              KERNEL_OBJ="$obj"
              echo "    Found KERNEL_OBJ: $KERNEL_OBJ"
            fi
          fi
          if [[ "$obj" == *"WawonaPreferencesManager"* ]] || [[ "$obj" == *"Settings_WawonaPreferencesManager"* ]] || [[ "$obj" == *"PreferencesManager"* ]]; then
            if [[ "$obj" == *.o ]] && [ -f "$obj" ]; then
              PREFS_MGR_OBJ="$obj"
              echo "    Found PREFS_MGR_OBJ: $PREFS_MGR_OBJ"
            fi
          fi
        done
        
        # Also try to find by listing .o files directly
        if [ -z "$KERNEL_OBJ" ] || [ -z "$PREFS_MGR_OBJ" ]; then
          echo "Trying alternative search in current directory..."
          for obj_file in *.o; do
            if [ -f "$obj_file" ]; then
              if [[ "$obj_file" == *"Kernel"* ]] && [ -z "$KERNEL_OBJ" ]; then
                KERNEL_OBJ="$obj_file"
                echo "    Found KERNEL_OBJ (alt): $KERNEL_OBJ"
              fi
              if [[ "$obj_file" == *"PreferencesManager"* ]] && [ -z "$PREFS_MGR_OBJ" ]; then
                PREFS_MGR_OBJ="$obj_file"
                echo "    Found PREFS_MGR_OBJ (alt): $PREFS_MGR_OBJ"
              fi
            fi
          done
        fi
        
        # Compile test binary
        TEST_OBJ="openssh_test_ios.o"
        echo "Compiling test binary source..."
        $CC -c src/bin/openssh_test_ios.m \
           -Isrc -Isrc/core -Isrc/ui/Settings \
           -Iios-dependencies/include \
           -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
           -fobjc-arc ${lib.concatStringsSep " " commonObjCFlags} \
           -DTARGET_OS_IPHONE=1 \
           -o $TEST_OBJ || {
          echo "Error: Failed to compile openssh_test_ios.m"
          exit 1
        }
        
        # Link test binary with required objects
        # Link test binary with required objects and HIAHKernel library
        if [ -n "$PREFS_MGR_OBJ" ] && [ -f "$PREFS_MGR_OBJ" ]; then
          echo "Linking test binary with $PREFS_MGR_OBJ and HIAHKernel library"
          $CC $TEST_OBJ $PREFS_MGR_OBJ \
             -Lios-dependencies/lib \
             -lHIAHKernel \
             -arch $SIMULATOR_ARCH -isysroot "$SDKROOT" -mios-simulator-version-min=15.0 \
             -fobjc-arc -framework Foundation -framework Security \
             -Wl,-rpath,@executable_path/../Frameworks \
             -o openssh_test_ios || {
            echo "Error: Failed to link openssh_test_ios"
            exit 1
          }
          echo "✓ Built openssh_test_ios"
        else
          echo "Warning: Required object files not found, skipping openssh_test_ios"
          echo "  PREFS_MGR_OBJ=$PREFS_MGR_OBJ (exists: $([ -f "$PREFS_MGR_OBJ" ] && echo yes || echo no))"
          echo "  Available object files:"
          ls -1 *.o 2>/dev/null | grep -i "prefs" | head -10 || echo "  (none found)"
        fi
      else
        echo "Note: src/bin/openssh_test_ios.m not found, skipping test binary"
      fi
  
      # Create extension bundle structure
      mkdir -p HIAHProcessRunner.appex/bin
      cp WawonaSSHRunner HIAHProcessRunner.appex/HIAHProcessRunner
      cp WawonaHooks.dylib HIAHProcessRunner.appex/
      install -m 755 hello_world HIAHProcessRunner.appex/bin/
      cp hello_world.dylib HIAHProcessRunner.appex/
      cp src/extensions/WawonaSSHRunner/Info.plist HIAHProcessRunner.appex/
      cp src/extensions/WawonaSSHRunner/Entitlements.plist HIAHProcessRunner.appex/
      
      # Copy HIAHKernel library to extension Frameworks folder
      mkdir -p HIAHProcessRunner.appex/Frameworks
      cp ios-dependencies/lib/libHIAHKernel.dylib HIAHProcessRunner.appex/Frameworks/

      # Patch Info.plist to match new name and standard extension point
      /usr/libexec/PlistBuddy -c "Set :CFBundleName HIAHProcessRunner" HIAHProcessRunner.appex/Info.plist
      /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable HIAHProcessRunner" HIAHProcessRunner.appex/Info.plist
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.aspauldingcode.Wawona.HIAHProcessRunner" HIAHProcessRunner.appex/Info.plist
      /usr/libexec/PlistBuddy -c "Set :NSExtension:NSExtensionPointIdentifier com.apple.services" HIAHProcessRunner.appex/Info.plist
      
      # Add required attributes for com.apple.services
      /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes dict" HIAHProcessRunner.appex/Info.plist || true
      /usr/libexec/PlistBuddy -c "Delete :NSExtension:NSExtensionAttributes:NSExtensionActivationRule" HIAHProcessRunner.appex/Info.plist || true
      /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes:NSExtensionActivationRule dict" HIAHProcessRunner.appex/Info.plist
      /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsFileWithMaxCount integer 1" HIAHProcessRunner.appex/Info.plist
      
      # Put hello_world in main app bin too
      mkdir -p bin
      install -m 755 hello_world bin/
      
      echo "Extension binary created: $(ls -lh WawonaSSHRunner | awk '{print $5}')"

      runHook postBuild
    '';

    installPhase = ''
            echo "Force rebuild 6"
            set -e
            echo "DEBUG: Starting installPhase"
            
            # Define temp dir for signing artifacts
            SIGNING_TEMP_DIR=$(mktemp -d)
            
            runHook preInstall
            
            # Create app bundle structure
            echo "DEBUG: Creating app bundle structure"
            mkdir -p $out/Applications/Wawona.app
            
            # Copy executable
            echo "DEBUG: Copying executable"
            cp Wawona $out/Applications/Wawona.app/
            
            # Copy hello_world to bin/
            mkdir -p $out/Applications/Wawona.app/bin
            install -m 755 hello_world $out/Applications/Wawona.app/bin/
            
            # Copy openssh_test_ios if built
            if [ -f openssh_test_ios ]; then
              install -m 755 openssh_test_ios $out/Applications/Wawona.app/bin/
              echo "✓ Copied openssh_test_ios to bin/"
            fi
            
            # Copy Metal shader library
            if [ -f metal_shaders.metallib ]; then
              echo "DEBUG: Copying Metal shaders"
              cp metal_shaders.metallib $out/Applications/Wawona.app/
            fi
            
            # Generate Info.plist
            echo "DEBUG: Generating Info.plist"
            cp ${iosInfoPlist} $out/Applications/Wawona.app/Info.plist
            chmod 644 $out/Applications/Wawona.app/Info.plist
            
            # Generate icons using shared logic
            echo "DEBUG: Generating icons"
            ${generateIcons "ios"}
            echo "DEBUG: Icons generated"
            
            # Copy Settings.bundle if it exists
            if [ -d $src/src/resources/Settings.bundle ]; then
              echo "DEBUG: Copying Settings.bundle"
              cp -r $src/src/resources/Settings.bundle $out/Applications/Wawona.app/
            fi
            
            # Install WawonaSSHRunner app extension (as HIAHProcessRunner.appex to match kernel expectations)
            echo "DEBUG: Installing HIAHProcessRunner.appex"
            mkdir -p $out/Applications/Wawona.app/PlugIns
            cp -r HIAHProcessRunner.appex $out/Applications/Wawona.app/PlugIns/
            chmod -R 755 $out/Applications/Wawona.app/PlugIns/HIAHProcessRunner.appex
            
            # Code sign extension with entitlements
            if command -v codesign >/dev/null 2>&1; then
              echo "DEBUG: Code signing extension with entitlements"
              
              # Create explicit entitlements for extension
              cat > "$SIGNING_TEMP_DIR/extension-entitlements.plist" <<EXT_ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.aspauldingcode.Wawona</string>
    </array>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
EXT_ENTITLEMENTS

              codesign --force --sign - --timestamp=none \
                --entitlements "$SIGNING_TEMP_DIR/extension-entitlements.plist" \
                $out/Applications/Wawona.app/PlugIns/HIAHProcessRunner.appex/HIAHProcessRunner || \
                echo "Warning: Failed to code sign extension binary"
              
              # Sign the bundle itself
              codesign --force --sign - --timestamp=none \
                --entitlements $out/Applications/Wawona.app/PlugIns/HIAHProcessRunner.appex/Entitlements.plist \
                $out/Applications/Wawona.app/PlugIns/HIAHProcessRunner.appex || \
                echo "Warning: Failed to code sign extension bundle"
              
              echo "Extension installed and code signed"
            else
              echo "Warning: codesign not found, extension may not work"
            fi
            
            # Copy dynamic libraries to Frameworks
            echo "DEBUG: Processing Frameworks"
            mkdir -p $out/Applications/Wawona.app/Frameworks
            if [ -d ios-dependencies/lib ]; then
              # Copy dylibs (use install for proper permissions, not cp which inherits read-only from Nix store)
              find ios-dependencies/lib -name "*.dylib" -exec install -m 755 {} $out/Applications/Wawona.app/Frameworks/ \;
              
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
            echo "DEBUG: Looking for waypipe"
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
              echo "DEBUG: Copying waypipe to app bundle"
              mkdir -p $out/Applications/Wawona.app/bin
              # Use install to ensure execute permissions are set correctly
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/bin/waypipe
              
              # Copy waypipe dylib if it exists
              WAYPIPE_ROOT=$(dirname $(dirname "$WAYPIPE_BIN"))
              if find "$WAYPIPE_ROOT" -name "libwaypipe.dylib" -exec cp {} $out/Applications/Wawona.app/bin/waypipe.dylib \; 2>/dev/null; then
                echo "✓ Copied waypipe.dylib to bin/"
              fi
              
              # 2. In bundle root (fallback for iOS Simulator)
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/waypipe
              
              # 3. Next to executable (another fallback)
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/waypipe-bin
              
              echo "Copied Waypipe binary to app bundle (bin/, root, and waypipe-bin)"
              echo "Waypipe binary size: $(ls -lh "$WAYPIPE_BIN" | awk '{print $5}')"
              
              # Verify execute permissions
              if [ -x "$out/Applications/Wawona.app/bin/waypipe" ]; then
                echo "✓ Waypipe binary in bin/ is executable"
              else
                echo "WARNING: Waypipe binary in bin/ is NOT executable, fixing..."
                chmod +x "$out/Applications/Wawona.app/bin/waypipe"
              fi
              if [ -x "$out/Applications/Wawona.app/waypipe" ]; then
                echo "✓ Waypipe binary in root is executable"
              else
                echo "WARNING: Waypipe binary in root is NOT executable, fixing..."
                chmod +x "$out/Applications/Wawona.app/waypipe"
              fi
              
              # Code sign waypipe binary for iOS
              if command -v codesign >/dev/null 2>&1; then
                echo "DEBUG: Code signing waypipe binary with entitlements..."
                printf '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.get-task-allow</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
      <string>group.com.aspauldingcode.Wawona</string>
  </array>
  <key>com.apple.security.cs.allow-dyld-environment-variables</key>
  <true/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>\n' > "$SIGNING_TEMP_DIR/waypipe-entitlements.plist"
          
                codesign --force --sign - --timestamp=none --entitlements "$SIGNING_TEMP_DIR/waypipe-entitlements.plist" "$out/Applications/Wawona.app/bin/waypipe" 2>/dev/null || echo "Warning: Failed to code sign waypipe binary"
                codesign --force --sign - --timestamp=none --entitlements "$SIGNING_TEMP_DIR/waypipe-entitlements.plist" "$out/Applications/Wawona.app/waypipe" 2>/dev/null || echo "Warning: Failed to code sign waypipe binary (root)"
                codesign --force --sign - --timestamp=none --entitlements "$SIGNING_TEMP_DIR/waypipe-entitlements.plist" "$out/Applications/Wawona.app/waypipe-bin" 2>/dev/null || echo "Warning: Failed to code sign waypipe binary (waypipe-bin)"
                chmod +x "$out/Applications/Wawona.app/bin/waypipe" 2>/dev/null || true
                chmod +x "$out/Applications/Wawona.app/waypipe" 2>/dev/null || true
                chmod +x "$out/Applications/Wawona.app/waypipe-bin" 2>/dev/null || true
                echo "Waypipe binary code signed with entitlements"
              else
                echo "Warning: codesign not found, waypipe binary may not be executable on iOS"
              fi
            else
              echo "Warning: Waypipe binary not found in buildInputs"
              echo "Searched in: $buildInputs"
            fi
            
            # Copy kosmickrisp Vulkan driver into app bundle
            # This enables Vulkan 1.3 support on iOS via LunarG's MESA driver
            echo "DEBUG: Looking for kosmickrisp Vulkan driver"
            KOSMICKRISP_LIB=""
            KOSMICKRISP_ICD=""
            for dep in $buildInputs; do
              if [ -f "$dep/lib/libvulkan_kosmickrisp.dylib" ]; then
                KOSMICKRISP_LIB="$dep/lib/libvulkan_kosmickrisp.dylib"
                echo "Found kosmickrisp Vulkan driver at: $KOSMICKRISP_LIB"
              fi
              if [ -f "$dep/share/vulkan/icd.d/kosmickrisp_icd.arm64.json" ]; then
                KOSMICKRISP_ICD="$dep/share/vulkan/icd.d/kosmickrisp_icd.arm64.json"
                echo "Found kosmickrisp ICD manifest at: $KOSMICKRISP_ICD"
              elif [ -d "$dep/share/vulkan/icd.d" ]; then
                # Find any JSON file in the ICD directory
                KOSMICKRISP_ICD=$(find "$dep/share/vulkan/icd.d" -name "*.json" -type f | head -1)
                if [ -n "$KOSMICKRISP_ICD" ]; then
                  echo "Found kosmickrisp ICD manifest at: $KOSMICKRISP_ICD"
                fi
              fi
            done
            
            if [ -n "$KOSMICKRISP_LIB" ] && [ -f "$KOSMICKRISP_LIB" ]; then
              echo "DEBUG: Copying kosmickrisp Vulkan driver to app bundle"
              # Copy to Frameworks directory (use install for proper permissions)
              mkdir -p $out/Applications/Wawona.app/Frameworks
              # Remove existing file if present (may have been copied earlier with wrong permissions)
              rm -f $out/Applications/Wawona.app/Frameworks/libvulkan_kosmickrisp.dylib
              install -m 755 "$KOSMICKRISP_LIB" $out/Applications/Wawona.app/Frameworks/libvulkan_kosmickrisp.dylib
              
              # Fix dylib paths for iOS bundle
              install_name_tool -id "@rpath/libvulkan_kosmickrisp.dylib" \
                $out/Applications/Wawona.app/Frameworks/libvulkan_kosmickrisp.dylib
              
              # Create Vulkan ICD manifest directory
              mkdir -p $out/Applications/Wawona.app/share/vulkan/icd.d
              
              # Generate iOS-specific ICD manifest with relative path
              cat > $out/Applications/Wawona.app/share/vulkan/icd.d/kosmickrisp_icd.json <<ICD_EOF
{
    "ICD": {
        "api_version": "1.3.335",
        "library_path": "@rpath/libvulkan_kosmickrisp.dylib"
    },
    "file_format_version": "1.0.1"
}
ICD_EOF
              
              # Code sign kosmickrisp for iOS
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none \
                  $out/Applications/Wawona.app/Frameworks/libvulkan_kosmickrisp.dylib 2>/dev/null || \
                  echo "Warning: Failed to code sign kosmickrisp"
              fi
              
              echo "✓ Copied kosmickrisp Vulkan 1.3 driver to app bundle"
              echo "  Library: $out/Applications/Wawona.app/Frameworks/libvulkan_kosmickrisp.dylib"
              echo "  ICD manifest: $out/Applications/Wawona.app/share/vulkan/icd.d/kosmickrisp_icd.json"
              echo "  Size: $(ls -lh $out/Applications/Wawona.app/Frameworks/libvulkan_kosmickrisp.dylib | awk '{print $5}')"
            else
              echo "Warning: kosmickrisp Vulkan driver not found in buildInputs"
              echo "  iOS Vulkan support will not be available"
            fi
            
            # Copy OpenSSH ssh binary into app bundle
            # Find openssh in buildInputs
            echo "DEBUG: Looking for openssh"
            SSH_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/ssh" ]; then
                SSH_BIN="$dep/bin/ssh"
                echo "Found OpenSSH ssh binary at: $SSH_BIN"
                break
              fi
            done
            
            if [ -n "$SSH_BIN" ] && [ -f "$SSH_BIN" ]; then
              # Copy to multiple locations for maximum compatibility (same as waypipe)
              # 1. In bin/ subdirectory (preferred location)
              echo "DEBUG: Copying ssh to app bundle"
              mkdir -p $out/Applications/Wawona.app/bin
              # Use install to ensure execute permissions are set correctly
              install -m 755 "$SSH_BIN" $out/Applications/Wawona.app/bin/ssh
              
              # Copy ssh dylib if it exists
              SSH_ROOT=$(dirname $(dirname "$SSH_BIN"))
              if [ -f "$SSH_ROOT/lib/ssh.dylib" ]; then
                cp "$SSH_ROOT/lib/ssh.dylib" $out/Applications/Wawona.app/bin/ssh.dylib
                echo "✓ Copied ssh.dylib to bin/"
              fi
              
              # 2. In bundle root (fallback for iOS Simulator)
              install -m 755 "$SSH_BIN" $out/Applications/Wawona.app/ssh
              
              echo "Copied OpenSSH ssh binary to app bundle (bin/ and root)"
              echo "SSH binary size: $(ls -lh "$SSH_BIN" | awk '{print $5}')"
              
              # Verify execute permissions
              if [ -x "$out/Applications/Wawona.app/bin/ssh" ]; then
                echo "✓ SSH binary in bin/ is executable"
              else
                echo "WARNING: SSH binary in bin/ is NOT executable, fixing..."
                chmod +x "$out/Applications/Wawona.app/bin/ssh"
              fi
              if [ -x "$out/Applications/Wawona.app/ssh" ]; then
                echo "✓ SSH binary in root is executable"
              else
                echo "WARNING: SSH binary in root is NOT executable, fixing..."
                chmod +x "$out/Applications/Wawona.app/ssh"
              fi
              
              # Code sign ssh binary for iOS (required for execution)
              # Note: This uses ad-hoc signing which works for Simulator
              # For device builds, proper provisioning profile signing is needed
              if command -v codesign >/dev/null 2>&1; then
                echo "DEBUG: Code signing ssh binary with entitlements..."
          # Create entitlements for ssh binary (same as main app)
          printf '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.get-task-allow</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
      <string>group.com.aspauldingcode.Wawona</string>
  </array>
  <key>com.apple.security.cs.allow-dyld-environment-variables</key>
  <true/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>\n' > "$SIGNING_TEMP_DIR/ssh-entitlements.plist"
          
          codesign --force --sign - --timestamp=none --entitlements "$SIGNING_TEMP_DIR/ssh-entitlements.plist" "$out/Applications/Wawona.app/bin/ssh" 2>/dev/null || echo "Warning: Failed to code sign ssh binary"
                codesign --force --sign - --timestamp=none --entitlements "$SIGNING_TEMP_DIR/ssh-entitlements.plist" "$out/Applications/Wawona.app/ssh" 2>/dev/null || echo "Warning: Failed to code sign ssh binary (root)"
                chmod +x "$out/Applications/Wawona.app/bin/ssh" 2>/dev/null || true
                chmod +x "$out/Applications/Wawona.app/ssh" 2>/dev/null || true
                echo "SSH binary code signed with entitlements"
              else
                echo "Warning: codesign not found, ssh binary may not be executable on iOS"
              fi
            else
              echo "Warning: OpenSSH ssh binary not found in buildInputs"
              echo "Searched in: $buildInputs"
            fi
            
            # Copy sshpass binary into app bundle (for non-interactive SSH password auth)
            echo "DEBUG: Looking for sshpass"
            SSHPASS_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/sshpass" ]; then
                SSHPASS_BIN="$dep/bin/sshpass"
                echo "Found sshpass binary at: $SSHPASS_BIN"
                break
              fi
            done
            
            if [ -n "$SSHPASS_BIN" ] && [ -f "$SSHPASS_BIN" ]; then
              echo "DEBUG: Copying sshpass to app bundle"
              mkdir -p $out/Applications/Wawona.app/bin
              install -m 755 "$SSHPASS_BIN" $out/Applications/Wawona.app/bin/sshpass
              
              echo "Copied sshpass binary to app bundle (bin/)"
              echo "sshpass binary size: $(ls -lh "$SSHPASS_BIN" | awk '{print $5}')"
              
              # Verify execute permissions
              if [ -x "$out/Applications/Wawona.app/bin/sshpass" ]; then
                echo "✓ sshpass binary in bin/ is executable"
              else
                echo "WARNING: sshpass binary in bin/ is NOT executable, fixing..."
                chmod +x "$out/Applications/Wawona.app/bin/sshpass"
              fi
              
              # Code sign sshpass binary
              if command -v codesign >/dev/null 2>&1; then
                echo "DEBUG: Code signing sshpass binary..."
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/bin/sshpass" 2>/dev/null || echo "Warning: Failed to code sign sshpass binary"
                chmod +x "$out/Applications/Wawona.app/bin/sshpass" 2>/dev/null || true
                echo "sshpass binary code signed"
              fi
            else
              echo "Warning: sshpass binary not found in buildInputs"
              echo "Searched in: $buildInputs"
            fi
            
            # Create symlink for convenience
            echo "DEBUG: Creating bin symlink"
            mkdir -p $out/bin
            ln -s $out/Applications/Wawona.app/Wawona $out/bin/Wawona
            
            # Create iOS simulator launcher script
      echo "DEBUG: Creating simulator launcher script"
      cat > $out/bin/wawona-ios-simulator <<'EOF'
#!/usr/bin/env bash
set -e

APP_BUNDLE=""
FOLLOW_LOGS="''${WAWONA_IOS_FOLLOW_LOGS:-1}"
LOG_LEVEL="''${WAWONA_IOS_LOG_LEVEL:-}"

if [ -z "$LOG_LEVEL" ]; then
  if [ "$FOLLOW_LOGS" = "1" ]; then
    LOG_LEVEL=debug
  else
    LOG_LEVEL=info
  fi
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --follow-logs)
      FOLLOW_LOGS=1
      ;;
    --no-logs)
      FOLLOW_LOGS=0
      ;;
    --log-level)
      shift
      LOG_LEVEL="''${1:-$LOG_LEVEL}"
      ;;
    --app)
      shift
      APP_BUNDLE="''${1:-$APP_BUNDLE}"
      ;;
    *)
      if [ -z "$APP_BUNDLE" ] && [ -d "$1" ]; then
        APP_BUNDLE="$1"
      fi
      ;;
  esac
  shift || true
done

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
      # Also make them executable so codesign can process them correctly
      chmod -R u+w "$TEMP_APP_BUNDLE" || true
      chmod -R +x "$TEMP_APP_BUNDLE" || true

      # Ad-hoc sign the app bundle for Simulator (required for Apple Silicon)
      if command -v codesign >/dev/null 2>&1; then
        codesign_item() {
          local item="$1"
          shift
          local out
          if ! out=$(codesign --force --sign - --timestamp=none "$@" "$item" 2>&1); then
            printf '%s\n' "$out" >&2
            return 1
          fi
          return 0
        }

        # Create minimal entitlements for Simulator
        # Note: keychain-access-groups removed - iOS Simulator may not require it
        # If Keychain access fails, we'll handle it gracefully in code
        # IMPORTANT: get-task-allow is required for debugging and for spawning child processes
        cat > "$TEMP_APP_DIR/entitlements.plist" <<ENTITLEMENTS
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>com.apple.security.get-task-allow</key>
        <true/>
        <key>com.apple.security.application-groups</key>
        <array>
            <string>group.com.aspauldingcode.Wawona</string>
        </array>
        <key>com.apple.security.cs.allow-dyld-environment-variables</key>
        <true/>
        <key>com.apple.security.cs.disable-library-validation</key>
        <true/>
      </dict>
      </plist>
ENTITLEMENTS

        # Sign frameworks first
        if [ -d "$TEMP_APP_BUNDLE/Frameworks" ]; then
          find "$TEMP_APP_BUNDLE/Frameworks" -name "*.dylib" -o -name "*.framework" | while read -r fw; do
            codesign_item "$fw" || true
          done
        fi
        
        # Sign PlugIns (Extensions) - WITH ENTITLEMENTS
        if [ -d "$TEMP_APP_BUNDLE/PlugIns" ]; then
          find "$TEMP_APP_BUNDLE/PlugIns" -name "*.appex" | while read -r appex; do
            echo "Signing extension $(basename "$appex") with entitlements..."
            codesign_item "$appex" --entitlements "$TEMP_APP_DIR/entitlements.plist" || true
          done
        fi

        # Sign binaries in bin/ directory (waypipe, ssh, etc.) - WITH ENTITLEMENTS
        # Ensure they are executable first so find can see them
        if [ -d "$TEMP_APP_BUNDLE/bin" ]; then
          chmod -R +x "$TEMP_APP_BUNDLE/bin" || true
          find "$TEMP_APP_BUNDLE/bin" -type f | while read -r bin; do
            BIN_NAME=$(basename "$bin")
            echo "Signing $BIN_NAME with identifier and entitlements..."
            codesign_item "$bin" --identifier "com.aspauldingcode.Wawona.bin.$BIN_NAME" --entitlements "$TEMP_APP_DIR/entitlements.plist" || true
          done
        fi
        
        # Sign binaries in extensions' bin/ directory
        if [ -d "$TEMP_APP_BUNDLE/PlugIns/WawonaSSHRunner.appex/bin" ]; then
          chmod -R +x "$TEMP_APP_BUNDLE/PlugIns/WawonaSSHRunner.appex/bin" || true
          find "$TEMP_APP_BUNDLE/PlugIns/WawonaSSHRunner.appex/bin" -type f | while read -r bin; do
            BIN_NAME=$(basename "$bin")
            echo "Signing extension bin: $BIN_NAME with entitlements and identifier..."
            codesign_item "$bin" --identifier "com.aspauldingcode.Wawona.extbin.$BIN_NAME" --entitlements "$TEMP_APP_DIR/entitlements.plist" || true
          done
        fi
        
        # Sign binaries in bundle root (waypipe, ssh fallback locations) - WITH ENTITLEMENTS
        for bin in "$TEMP_APP_BUNDLE/waypipe" "$TEMP_APP_BUNDLE/waypipe-bin" "$TEMP_APP_BUNDLE/ssh"; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            echo "Signing $(basename "$bin") (root) with entitlements..."
            codesign_item "$bin" --entitlements "$TEMP_APP_DIR/entitlements.plist" || true
          fi
        done
        
        # Sign main executable
        codesign_item "$TEMP_APP_BUNDLE" --entitlements "$TEMP_APP_DIR/entitlements.plist" || \
        codesign_item "$TEMP_APP_BUNDLE" || true
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

      # Stream logs to stdout or file
      if [ "$FOLLOW_LOGS" = "1" ]; then
        LOG_FILE="''${WAWONA_IOS_LOG_FILE:-}"
        if [ -n "$LOG_FILE" ]; then
          echo "Redirecting logs to $LOG_FILE (overwriting)"
          # Truncate log file
          > "$LOG_FILE"
          
          # Background log stream
          xcrun simctl spawn "$DEVICE_ID" log stream --predicate 'processImagePath contains "Wawona" OR processImagePath endswith "Wawona"' --level "$LOG_LEVEL" --style compact >> "$LOG_FILE" 2>&1 &
          LOG_PID=$!
          
          echo "Log stream started (PID: $LOG_PID). Instructions for LLDB:"
          echo "  xcrun simctl spawn booted lldb"
          echo "  (lldb) process attach -n Wawona"
          echo "  (lldb) process attach -n WawonaSSHRunner"
          
          # Monitoring loop for termination
          echo "Waiting for tests to complete..."
          while sleep 2; do
            if grep -q "ALL TESTS COMPLETED" "$LOG_FILE"; then
              echo "✅ Kernel tests finished. Terminating..."
              kill $LOG_PID 2>/dev/null || true
              break
            fi
            # Check if log stream is still alive
            if ! kill -0 $LOG_PID 2>/dev/null; then
               echo "❌ Log stream terminated unexpectedly."
               break
            fi
          done
        else
          xcrun simctl spawn "$DEVICE_ID" log stream --predicate 'processImagePath contains "Wawona" OR processImagePath endswith "Wawona"' --level "$LOG_LEVEL" --style compact
        fi
      else
        echo "Launched $BUNDLE_ID on simulator $DEVICE_NAME ($DEVICE_ID)."
        echo "To stream logs: WAWONA_IOS_FOLLOW_LOGS=1 nix run .#wawona-ios"
      fi
EOF
      chmod 755 $out/bin/wawona-ios-simulator
      ls -l $out/bin/wawona-ios-simulator
      echo "DEBUG: installPhase finished"
    '';

    meta = {
      mainProgram = "wawona-ios-simulator";
      description = "Wawona iOS App";
      platforms = pkgs.lib.platforms.darwin;
    };
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
