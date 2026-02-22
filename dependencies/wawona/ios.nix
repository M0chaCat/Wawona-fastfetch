{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  rustBackend,
  rustBackendSim ? null,
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs; };
  xcodeEnv =
    platform: ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/${if platform == "ios" then "iPhoneOS" else "MacOSX"}.platform/Developer/SDKs/${if platform == "ios" then "iPhoneOS" else "MacOSX"}.sdk"
        fi
      fi
    '';
  copyDeps =
    dest: ''
      mkdir -p ${dest}/include ${dest}/lib ${dest}/libdata/pkgconfig
      for dep in $buildInputs; do
        if [ -d "$dep/include" ]; then cp -rn "$dep/include/"* ${dest}/include/ 2>/dev/null || true; fi
        if [ -d "$dep/lib" ]; then
          for lib in "$dep"/lib/*.a; do
            if [ -f "$lib" ]; then
              cp -n "$lib" ${dest}/lib/ 2>/dev/null || true
            fi
          done
        fi
        if [ -d "$dep/lib/pkgconfig" ]; then cp -rn "$dep/lib/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
        if [ -d "$dep/libdata/pkgconfig" ]; then cp -rn "$dep/libdata/pkgconfig/"* ${dest}/libdata/pkgconfig/ 2>/dev/null || true; fi
      done
    '';
  # HIAHKernel removed

  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;

  westonSimpleShmSrc = pkgs.callPackage ../libs/weston-simple-shm/patched-src.nix {};

  # waypipe built separately via dependencies/libs/waypipe/ios.nix (libwaypipe.a)
  # Cannot link with libwawona.a due to duplicate Rust stdlib - use nix build .#waypipe-ios
  iosDeps = [ ];

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
      else if name == "vulkan-headers" then
        pkgs.vulkan-headers
      else if name == "vulkan-loader" then
        pkgs.vulkan-loader
      else if name == "xkbcommon" then
        if platform == "ios" then
          buildModule.buildForIOS "xkbcommon" { }
        else
          pkgs.libxkbcommon
      else if name == "libssh2" then
        buildModule.ios.libssh2
      else if name == "mbedtls" then
        buildModule.ios.mbedtls
      else
        buildModule.${platform}.${name}
    ) depNames;

  iosSources = common.commonSources ++ [
    # iOS-only platform files (WWN prefix)
    "src/platform/ios/WWNCompositorView_ios.m"
    "src/platform/ios/WWNCompositorView_ios.h"
    "src/platform/ios/WWNSceneDelegate.m"
    "src/platform/ios/WWNSceneDelegate.h"
    "src/platform/ios/WWNIOSVersions.h"
    # Launcher client (requires generated Wayland headers from Nix build)
    "src/launcher/WWNLauncherClient.m"
    "src/launcher/WWNLauncherClient.h"
  ];

  iosSourcesFiltered = common.filterSources iosSources;

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

    nativeBuildInputs = with pkgs; [
      pkg-config
      xcodeUtils.findXcodeScript
      buildPackages.wayland-scanner
    ];

    buildInputs = (getDeps "ios" iosDeps) ++ [
      pkgs.vulkan-headers
      buildModule.ios.libwayland
      buildModule.ios.xkbcommon
      buildModule.ios.libffi
      buildModule.ios.pixman
      buildModule.ios.libssh2
      buildModule.ios.mbedtls
      (buildModule.buildForIOS "openssl" { })
      buildModule.ios.zstd
      buildModule.ios.lz4
      buildModule.ios.epoll-shim
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
      
      # Metal shader compilation
    '';

    # Metal shader compilation
    preBuild = ''
      ${xcodeEnv "ios"}

      if command -v metal >/dev/null 2>&1; then
        metal -c src/rendering/metal_shaders.metal -o metal_shaders.air -isysroot "$SDKROOT" -miphoneos-version-min=26.0 || true
        if [ -f metal_shaders.air ] && command -v metallib >/dev/null 2>&1; then
          metallib metal_shaders.air -o metal_shaders.metallib || true
        fi
      fi
    '';

    preConfigure = ''
      ${xcodeEnv "ios"}

      ${copyDeps "ios-dependencies"}

      # Copy waypipe protocol headers (xdg-shell-client-protocol.h etc.)
      WAYPIPE_SRC="${pkgs.fetchFromGitLab {
        owner = "mstoeckl";
        repo = "waypipe";
        rev = "v0.10.6";
        sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
      }}"
      if [ -d "$WAYPIPE_SRC/protocols" ]; then
        # Generate needed protocol headers from XML
        wayland-scanner client-header "$WAYPIPE_SRC/protocols/xdg-shell.xml" ios-dependencies/include/xdg-shell-client-protocol.h
        wayland-scanner private-code "$WAYPIPE_SRC/protocols/xdg-shell.xml" ios-dependencies/include/xdg-shell-protocol.c
        echo "Generated xdg-shell protocol headers"
      else
        echo "WARNING: waypipe protocol headers not found at $WAYPIPE_SRC/protocols"
        ls -la "$WAYPIPE_SRC/" || true
      fi

      # Setup Weston Simple SHM
      mkdir -p deps/weston-simple-shm
      cp -r ${westonSimpleShmSrc}/* deps/weston-simple-shm/
      chmod -R u+w deps/weston-simple-shm

      export PKG_CONFIG_PATH="$PWD/ios-dependencies/libdata/pkgconfig:$PWD/ios-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"
      export NIX_CFLAGS_COMPILE=""
      export NIX_CXXFLAGS_COMPILE=""

      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
        # Unset Nix wrappers so they don't interfere
        unset CC CXX AR AS LD RANLIB STRIP NM OBJCOPY OBJDUMP READELF
      else
        echo "ERROR: Xcode toolchain not found at $DEVELOPER_DIR"
        exit 1
      fi
      # App Store build target: arm64 iPhoneOS
      IOS_ARCH="arm64"
      export CC="$IOS_CC"
      export CXX="$IOS_CXX"
      export CFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -miphoneos-version-min=26.0 -fPIC"
      export CXXFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -miphoneos-version-min=26.0 -fPIC"
      export LDFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT -miphoneos-version-min=26.0 -lobjc"
    '';

    buildPhase = ''
      runHook preBuild

      # Compile generated protocols
      $CC -c ios-dependencies/include/xdg-shell-protocol.c \
          -Iios-dependencies/include -Iios-dependencies/include/wayland \
          -fPIC -arch $IOS_ARCH -isysroot "$SDKROOT" -miphoneos-version-min=26.0 \
          -o xdg-shell-protocol.o
      OBJ_FILES="xdg-shell-protocol.o"

      # Compile all source files
      for src_file in ${lib.concatStringsSep " " iosSourcesFiltered}; do
        if [[ "$src_file" == *.c ]] || [[ "$src_file" == *.m ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if [[ "$src_file" == *.m ]]; then
            $CC -c "$src_file" \
                -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
                -Isrc/platform/macos \
                -Isrc/platform/ios \
                -Isrc/logging -Isrc/launcher \
                -Isrc/extensions \
                -Iios-dependencies/include -Iios-dependencies/include/wayland \
                -fobjc-arc -fPIC \
                ${lib.concatStringsSep " " commonObjCFlags} \
                ${lib.concatStringsSep " " releaseObjCFlags} \
                -arch $IOS_ARCH -isysroot "$SDKROOT" -miphoneos-version-min=26.0 \
               -DTARGET_OS_IPHONE=1 \
               -DUSE_RUST_CORE=1 \
               -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/util -Isrc/core -Isrc/rendering -Isrc/input -Isrc/ui -Isrc/ui/Helpers \
               -Isrc/platform/macos \
               -Isrc/logging -Isrc/launcher \
               -Iios-dependencies/include -Iios-dependencies/include/wayland \
               -fPIC \
               ${lib.concatStringsSep " " commonCFlags} \
               ${lib.concatStringsSep " " releaseObjCFlags} \
               -arch $IOS_ARCH -isysroot "$SDKROOT" -miphoneos-version-min=26.0 \
               -DUSE_RUST_CORE=1 \
               -o "$obj_file"
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done

      # Compile weston-simple-shm
      for src_file in deps/weston-simple-shm/clients/simple-shm.c deps/weston-simple-shm/shared/os-compatibility.c deps/weston-simple-shm/fullscreen-shell-unstable-v1-protocol.c; do
        obj_file="''${src_file//\//_}.o"
        $CC -c "$src_file" \
           -Ideps/weston-simple-shm \
           -Ideps/weston-simple-shm/shared \
           -Ideps/weston-simple-shm/include \
           -Iios-dependencies/include -Iios-dependencies/include/wayland \
           -fPIC -arch $IOS_ARCH -isysroot "$SDKROOT" -miphoneos-version-min=26.0 \
           -o "$obj_file"
        OBJ_FILES="$OBJ_FILES $obj_file"
      done

      # Link executable with Rust backend
      $CC $OBJ_FILES \
         -Lios-dependencies/lib \
         -lxkbcommon -lwayland-client -lepoll-shim -lffi -lpixman-1 -lzstd -llz4 -lz \
         -lssh2 -lmbedcrypto -lmbedx509 -lmbedtls \
         -lssl -lcrypto \
         -framework Foundation -framework UIKit -framework QuartzCore \
         -framework CoreVideo -framework CoreMedia -framework CoreGraphics \
         -framework Metal -framework MetalKit -framework IOSurface \
         -framework VideoToolbox -framework AVFoundation \
         -framework Security -framework Network \
         ${rustBackend}/lib/libwawona.a \
         -fobjc-arc -flto -O3 -arch $IOS_ARCH -isysroot "$SDKROOT" -miphoneos-version-min=26.0 \
         -Wl,-multiply_defined,suppress \
         -o Wawona

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

      # Install app icons (light + dark) for iOS appearance support
      APPICONSET="$src/src/resources/Assets.xcassets/AppIcon.appiconset"
      if [ -d "$APPICONSET" ] && [ -f "$APPICONSET/AppIcon-Light-1024.png" ]; then
        cp "$APPICONSET/AppIcon-Light-1024.png" "$out/Applications/Wawona.app/AppIcon.png"
        echo "Installed AppIcon.png (light, opaque)"
      fi
      if [ -d "$APPICONSET" ] && [ -f "$APPICONSET/AppIcon-Dark-1024.png" ]; then
        cp "$APPICONSET/AppIcon-Dark-1024.png" "$out/Applications/Wawona.app/AppIcon-Dark.png"
        echo "Installed AppIcon-Dark.png (dark)"
      fi

      # Install modern Wawona.icon bundle (iOS 26+ Icon Composer format)
      ICON_BUNDLE="$src/src/resources/Wawona.icon"
      if [ -d "$ICON_BUNDLE" ]; then
        cp -R "$ICON_BUNDLE" "$out/Applications/Wawona.app/"
        echo "Installed Wawona.icon bundle"
      fi

      # Bundle the dark logo PNG for Settings About header
      if [ -f "$src/src/resources/Wawona-iOS-Dark-1024x1024@1x.png" ]; then
        cp "$src/src/resources/Wawona-iOS-Dark-1024x1024@1x.png" \
          "$out/Applications/Wawona.app/"
        echo "Bundled Wawona-iOS-Dark-1024x1024@1x.png"
      fi
      
      # Static-only policy for App Store-distributable iOS builds:
      # do not bundle third-party dylibs into the app.
      for dep in $buildInputs; do
         if [ -d "$dep/lib" ]; then
            found_dylib=0
            for dylib in "$dep"/lib/*.dylib; do
              if [ -f "$dylib" ]; then
                if [ "$found_dylib" -eq 0 ]; then
                  echo "ERROR: Found dynamic libraries in dependency: $dep/lib"
                  found_dylib=1
                fi
                echo "$dylib"
              fi
            done
            if [ "$found_dylib" -eq 1 ]; then
              exit 1
            fi
         fi
      done

      # No extra binaries to copy

      runHook postInstall
    '';

    passthru.automationScript = pkgs.writeShellScriptBin "wawona-ios-automat" ''
      set -e
      ${xcodeEnv "ios"}

      # Unset Nix compiler wrappers to allow xcodebuild to use the Xcode toolchain
      unset CC CXX AR AS LD RANLIB STRIP NM OBJCOPY OBJDUMP READELF
      unset NIX_CFLAGS_COMPILE NIX_CXXFLAGS_COMPILE NIX_LDFLAGS NIX_BINTOOLS

      echo "Generating Xcode project..."
      ${(pkgs.callPackage ../generators/xcodegen.nix {
         inherit pkgs;
         rustBackendIOS = rustBackend;
         rustBackendIOSSim = rustBackendSim;
         includeMacOSTarget = false;
         rustPlatform = pkgs.rustPlatform;
         wawonaVersion = projectVersion;
       }).app}/bin/xcodegen

      if [ ! -d "Wawona.xcodeproj" ]; then
        echo "Error: Wawona.xcodeproj not generated."
        exit 1
      fi

      SIM_NAME="Wawona iOS Simulator"
      DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
      RUNTIME=$(xcrun simctl list runtimes | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1)
      if [ -z "$RUNTIME" ]; then
        echo "Error: No iOS runtime found."
        exit 1
      fi

      SIM_UDID=$(xcrun simctl list devices | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
      if [ -z "$SIM_UDID" ]; then
        echo "Creating '$SIM_NAME' ($DEV_TYPE, $RUNTIME)..."
        SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
      fi

      echo "Simulator UDID: $SIM_UDID"
      xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
      open -a Simulator

      echo "Building for iOS Simulator (real Rust core backend)..."
      if ! xcodebuild -scheme Wawona-iOS \
        -project Wawona.xcodeproj \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIM_UDID" \
        -derivedDataPath build/ios_sim_build \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        build; then
        echo ""
        echo "Simulator build failed."
        exit 1
      fi

      APP_PATH="build/ios_sim_build/Build/Products/Debug-iphonesimulator/Wawona.app"
      if [ ! -d "$APP_PATH" ]; then
        echo "Error: App not found at $APP_PATH"
        exit 1
      fi

      echo "Installing app to simulator..."
      # Kill any stale simctl install from previous runs (they block the socket)
      pkill -f "simctl install" 2>/dev/null || true
      sleep 1
      # Wait for simulator to be fully booted
      xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || {
        for i in $(seq 1 30); do
          STATUS=$(xcrun simctl list devices | grep "$SIM_UDID" | grep -o "Booted" || true)
          if [ "$STATUS" = "Booted" ]; then break; fi
          echo "  Waiting for simulator ($i/30)..."
          sleep 2
        done
      }
      xcrun simctl install "$SIM_UDID" "$APP_PATH"

      # Use a single log file for a cleaner unified stream
      APP_LOG="/tmp/wawona-ios.log"
      rm -f "$APP_LOG"
      touch "$APP_LOG"
      
      # Launch via simctl with --wait-for-debugger so we can attach LLDB
      LAUNCH_OUTPUT=$(xcrun simctl launch --wait-for-debugger --stdout="$APP_LOG" --stderr="$APP_LOG" "$SIM_UDID" com.aspauldingcode.Wawona 2>&1)
      
      # Extract PID (format: "com.aspauldingcode.Wawona: 12345")
      PID=$(echo "$LAUNCH_OUTPUT" | awk '/com.aspauldingcode.Wawona:/ {print $NF}')
      
      if [ -z "$PID" ]; then
          echo "Error: Could not extract PID from launch output."
          echo "Output: $LAUNCH_OUTPUT"
          exit 1
      fi
      
      # Start log streaming
      pkill -f "tail -f $APP_LOG" 2>/dev/null || true
      echo "--- Wawona iOS Logs (PID $PID) ---"
      tail -f "$APP_LOG" &
      TAIL_PID=$!
      trap "kill $TAIL_PID 2>/dev/null || true" EXIT INT TERM
      
      # Write LLDB command script:
      #   Phase 1 — Attach silently (suppress all frame/thread/disassembly output)
      #   Phase 2 — Register stop-hooks that fire on CRASH only (not during attach)
      #   Phase 3 — Continue the process (LLDB goes silent in --batch mode)
      #
      # On crash: stop-hooks kill the tail, restore display settings, show bt.
      # --batch then drops LLDB into interactive mode at the crash site.
      cat > /tmp/wawona_debug.lldb << LLDBEOF
settings set auto-confirm true
settings set stop-line-count-before 0
settings set stop-line-count-after 0
settings set stop-disassembly-display never
settings set frame-format ""
settings set thread-stop-format ""
process attach --pid $PID
process handle SIGPIPE -n true -p true -s false
target stop-hook add --one-liner "script import os; os.kill($TAIL_PID, 15)"
target stop-hook add --one-liner "settings set stop-line-count-after 5"
target stop-hook add --one-liner "settings set stop-disassembly-display always"
target stop-hook add --one-liner "thread backtrace"
continue
LLDBEOF
      
      # --batch: runs the script then stays SILENT (no (lldb) prompt).
      #          If the process crashes, LLDB becomes interactive automatically.
      # -Q:      suppresses the welcome banner.
      # This lets tail -f own the terminal during normal execution.
      lldb --batch -Q -s /tmp/wawona_debug.lldb
      
      # Cleanup if lldb exits normally (process quit without crash)
      kill $TAIL_PID 2>/dev/null || true
    '';

  }
