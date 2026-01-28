{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  compositor,
  weston,
}:

let
  common = import ./wawona-common.nix { inherit lib pkgs wawonaSrc; };
  
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  xcodeEnv =
    platform: ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
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
      
      # Copy UniFFI generated bindings from compositor output
      if [ -d "${compositor}/uniffi/swift" ]; then
        echo "📦 Copying UniFFI bindings from compositor output..."
        mkdir -p "${dest}/uniffi"
        cp -r "${compositor}/uniffi/swift"/* "${dest}/uniffi/"
        echo "✅ UniFFI bindings copied to ${dest}/uniffi/"
        ls -la "${dest}/uniffi/"
      else
        echo "⚠️  UniFFI bindings not found at ${compositor}/uniffi/swift"
      fi
    '';

  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  
  projectVersionPatch =
    let parts = lib.splitString "." projectVersion;
    in if parts == [] then "1" else lib.last parts;

  macosDeps = common.commonDeps ++ [
    "kosmickrisp"
    "epoll-shim"
    "xkbcommon"
    "sshpass"
  ];

  getDeps =
    platform: depNames:
    map (
      name:
      if name == "pixman" then
        pkgs.pixman
      else if name == "vulkan-headers" then
        pkgs.vulkan-headers
      else if name == "vulkan-loader" then
        pkgs.vulkan-loader
      else if name == "xkbcommon" then
        pkgs.libxkbcommon
      else
        buildModule.${platform}.${name}
    ) depNames;

  # macOS sources - filter out iOS specific files and add macOS specific ones
  macosSources = 
    (lib.filter 
      (f: !(lib.hasSuffix "_ios.m" f) && !(lib.hasSuffix "_ios.h" f)) 
      common.commonSources
    ) ++ [
      "src/rendering/renderer_macos.m"
      "src/rendering/renderer_macos.h"
      "src/rendering/renderer_macos_helpers.m"
      "src/platform/macos/WawonaWindow.m"
      "src/platform/macos/WawonaWindow.h"
    ];

  macosSourcesFiltered = common.filterSources macosSources;

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
            $ACTOOL_CMD "$TMP_ASSETS" --compile "$out/Applications/Wawona.app/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist "$TMP_ASSETS/partial.plist" 2>&1 | tee actool_output.log
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


      rm -rf "$TMP_ASSETS"
    fi
  '';

in
  pkgs.stdenv.mkDerivation rec {
    name = "wawona-macos";
    version = projectVersion;
    src = wawonaSrc;

    nativeBuildInputs = with pkgs; [
      clang
      pkg-config

      xcodeUtils.findXcodeScript
      compositor
    ];

    buildInputs = (getDeps "macos" macosDeps) ++ [
      pkgs.pixman
      pkgs.vulkan-headers
      pkgs.vulkan-loader
      pkgs.libxkbcommon
      compositor
      weston
    ];

    # Fix gbm-wrapper.c include path and egl_buffer_handler.h for macOS
    postPatch = ''
            # Fix gbm-wrapper.c include path for metal_dmabuf.h
            substituteInPlace src/compat/macos/stubs/libinput-macos/gbm-wrapper.c \
              --replace-fail '#include "../../../../metal_dmabuf.h"' '#include "metal_dmabuf.h"'
            
            # Create macOS-compatible egl_buffer_handler.h stub
            cat > src/stubs/egl_buffer_handler.h <<-'EOF'
      #pragma once

      #include <wayland-server-core.h>
      #include <stdbool.h>

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

      static inline int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
          (void)handler; (void)display;
          return -1; 
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

      # Create renderer_apple.h (not tracked in git, so not in nix source)
      cp ${./files/renderer_apple.h} src/rendering/renderer_apple.h
      
      # Fix include path for renderer_apple.h in WawonaCompositor.m
      sed 's|"../rendering/renderer_apple.h"|"renderer_apple.h"|g' src/platform/macos/WawonaCompositor.m > src/platform/macos/WawonaCompositor.m.tmp
      mv src/platform/macos/WawonaCompositor.m.tmp src/platform/macos/WawonaCompositor.m
    '';

    preBuild = ''
      ${xcodeEnv "macos"}

      if command -v metal >/dev/null 2>&1; then
        true
      fi
    '';

    preConfigure = ''
      ${xcodeEnv "macos"}
      ${copyDeps "macos-dependencies"}

      export PKG_CONFIG_PATH="$PWD/macos-dependencies/libdata/pkgconfig:$PWD/macos-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"
    '';

    buildPhase = ''
      

      runHook preBuild
      # Build timestamp: 2026-01-17-09:00 - Added Swift compiler!

      # PHASE 1: Compile Swift UniFFI bindings FIRST
      # This generates _GEN-wawona-Swift.h that Objective-C needs
      echo "📦 Phase 1: Compiling Swift UniFFI bindings..."
      SWIFT_OBJ=""
      if [ -f "macos-dependencies/uniffi/wawona.swift" ]; then
        echo "   Found Swift file: macos-dependencies/uniffi/wawona.swift"
        # Swift compilation with Objective-C bridge header generation
        swiftc -c "macos-dependencies/uniffi/wawona.swift" \
          -import-objc-header "src/platform/macos/Wawona-Bridging-Header.h" \
          -module-name wawona \
          -emit-objc-header \
          -emit-objc-header-path wawona-Swift.h \
          -emit-module \
          -emit-module-path wawona.swiftmodule \
          -o wawona_swift.o \
          -sdk "$SDKROOT" \
          -target arm64-apple-macos26.0 \
          -I "macos-dependencies/uniffi" \
          -I "src/platform/macos" \
          -L "${compositor}/lib" \
          -Xlinker -rpath -Xlinker "@executable_path" \
          2>&1 || echo "⚠️  Swift compilation failed"
        
        if [ -f "wawona_swift.o" ] && [ -f "wawona-Swift.h" ]; then
          # Add generation header and rename to _GEN- prefix
          cat > _GEN-wawona-Swift.h << 'GEN_HEADER'
// WARNING: This is a GENERATED file - DO NOT EDIT
// 
// Generated by: swiftc (Swift Compiler)
// Source file:  macos-dependencies/uniffi/wawona.swift
// Build script: dependencies/wawona-macos.nix (Phase 1: Swift compilation)
// Command:      swiftc -emit-objc-header
// 
// Purpose: Allows Objective-C code to call Swift classes from UniFFI bindings
// 
// To regenerate this file:
//   nix build .#wawona-macos
// 
// DO NOT manually edit - changes will be overwritten on next build
//

GEN_HEADER
          cat wawona-Swift.h >> _GEN-wawona-Swift.h
          rm wawona-Swift.h
          
          SWIFT_OBJ="wawona_swift.o"
          echo "✅ Swift bindings compiled - _GEN-wawona-Swift.h generated"
          echo "   Swift object: $(ls -lh wawona_swift.o)"
          echo "   Swift header: $(ls -lh _GEN-wawona-Swift.h)"
        else
          echo "⚠️  Swift compilation failed - will use stub mode"
          echo "   Checking what files exist:"
          ls -la *.o 2>/dev/null || echo "   No .o files"
          ls -la *.h 2>/dev/null | head -5 || echo "   No .h files"
        fi
      else
        echo "ℹ️  No Swift bindings found - using stub mode"
        echo "   Looked in: macos-dependencies/uniffi/wawona.swift"
        ls -la macos-dependencies/uniffi/ || echo "   Directory doesn't exist"
      fi
      
      echo "   SWIFT_OBJ variable: ''${SWIFT_OBJ:-EMPTY}"

      # PHASE 2: Compile Objective-C and C files
      # Now _GEN-wawona-Swift.h is available in current directory
      echo "🔨 Phase 2: Compiling Objective-C and C files..."
      OBJ_FILES="$SWIFT_OBJ"
      for src_file in ${lib.concatStringsSep " " macosSourcesFiltered}; do
        if [[ "$src_file" == *.c ]] || [[ "$src_file" == *.m ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if [[ "$src_file" == *.m ]]; then
            $CC -c "$src_file" \
               -Isrc -Isrc/platform/macos -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/launcher -Isrc/platform/macos \
               -Isrc/compositor_implementations -Isrc/protocols \
               -Imacos-dependencies/include \
               -Imacos-dependencies/uniffi \
               -I. \
               -I${compositor}/include \
               -fobjc-arc -fPIC \
               ${lib.concatStringsSep " " common.commonObjCFlags} \
               ${lib.concatStringsSep " " common.releaseObjCFlags} \
               -DUSE_RUST_CORE=1 \
               -o "$obj_file"
          else
            $CC -c "$src_file" \
               -Isrc -Isrc/platform/macos -Isrc/rendering -Isrc/input -Isrc/ui \
               -Isrc/logging -Isrc/stubs -Isrc/launcher -Isrc/platform/macos \
               -Isrc/compositor_implementations -Isrc/protocols \
               -Imacos-dependencies/include \
               -Imacos-dependencies/uniffi \
               -I${compositor}/include \
               -fPIC \
               ${lib.concatStringsSep " " common.commonCFlags} \
               ${lib.concatStringsSep " " common.releaseCFlags} \
               -DUSE_RUST_CORE=1 \
               -o "$obj_file"
          fi
          OBJ_FILES="$OBJ_FILES $obj_file"
        fi
      done

      # Debug: Show all object files before linking
      echo ""
      echo "📊 Object files summary:"
      echo "   SWIFT_OBJ: ''${SWIFT_OBJ:-EMPTY}"
      echo "   OBJ_FILES count: $(echo $OBJ_FILES | wc -w)"
      echo "   First few: $(echo $OBJ_FILES | tr ' ' '\n' | head -3 | tr '\n' ' ')"
      if [ -n "$SWIFT_OBJ" ] && [ -f "$SWIFT_OBJ" ]; then
        echo "   ✅ Swift object exists: $(ls -lh $SWIFT_OBJ)"
      else
        echo "   ❌ Swift object NOT found"
      fi
      echo ""

      # PHASE 3: Link everything together
      echo "🔗 Phase 3: Linking final binary..."

      XKBCOMMON_LIBS=$(pkg-config --libs libxkbcommon 2>/dev/null || echo "-Lmacos-dependencies/lib -lxkbcommon")
      $CC $OBJ_FILES \
         -Lmacos-dependencies/lib \
         -framework Cocoa -framework QuartzCore -framework CoreVideo \
         -framework CoreMedia -framework CoreGraphics -framework ColorSync \
         -framework Metal -framework MetalKit -framework IOSurface \
         -framework VideoToolbox -framework AVFoundation -framework Network -framework Security \
         $(pkg-config --libs wayland-server wayland-client pixman-1) \
         $XKBCOMMON_LIBS \
         ${compositor}/lib/libwawona.a \
         -fobjc-arc -flto -O3 \
         -ObjC \
         -Wl,-rpath,\$PWD/macos-dependencies/lib \
         -o Wawona

      runHook postBuild
    '';

    installPhase = ''
            runHook preInstall
            
            mkdir -p $out/Applications/Wawona.app/Contents/MacOS
            mkdir -p $out/Applications/Wawona.app/Contents/Resources
            
            cp Wawona $out/Applications/Wawona.app/Contents/MacOS/
            
            if [ -f metal_shaders.metallib ]; then
              cp metal_shaders.metallib $out/Applications/Wawona.app/Contents/MacOS/
            fi
            
            echo "DEBUG: Looking for sshpass binary in buildInputs..."
            SSHPASS_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/sshpass" ]; then
                SSHPASS_BIN="$dep/bin/sshpass"
                break
              fi
            done
            
            if [ -n "$SSHPASS_BIN" ] && [ -f "$SSHPASS_BIN" ]; then
              install -m 755 "$SSHPASS_BIN" $out/Applications/Wawona.app/Contents/MacOS/sshpass
              mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
              install -m 755 "$SSHPASS_BIN" $out/Applications/Wawona.app/Contents/Resources/bin/sshpass
              
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/MacOS/sshpass" 2>/dev/null || echo "Warning: Failed to code sign sshpass"
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Resources/bin/sshpass" 2>/dev/null || true
              fi
            fi
            
            echo "DEBUG: Looking for waypipe binary in buildInputs..."
            WAYPIPE_BIN=""
            for dep in $buildInputs; do
              if [ -f "$dep/bin/waypipe" ]; then
                WAYPIPE_BIN="$dep/bin/waypipe"
                break
              fi
            done
            
            if [ -n "$WAYPIPE_BIN" ] && [ -f "$WAYPIPE_BIN" ]; then
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/Contents/MacOS/waypipe
              install -m 755 "$WAYPIPE_BIN" $out/Applications/Wawona.app/Contents/Resources/bin/waypipe
              
              if command -v codesign >/dev/null 2>&1; then
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/MacOS/waypipe" 2>/dev/null || echo "Warning: Failed to code sign waypipe"
                codesign --force --sign - --timestamp=none "$out/Applications/Wawona.app/Contents/Resources/bin/waypipe" 2>/dev/null || true
              fi
            fi
            
            # Bundle Weston clients
            echo "DEBUG: Bundling Weston clients..."
            mkdir -p $out/Applications/Wawona.app/Contents/Resources/bin
            if [ -d "${weston}/bin" ]; then
              # Copy weston-terminal specifically
              if [ -f "${weston}/bin/weston-terminal" ]; then
                 cp "${weston}/bin/weston-terminal" $out/Applications/Wawona.app/Contents/Resources/bin/
                 chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/weston-terminal
              fi
              # Copy other useful clients
              for client in weston-simple-egl weston-simple-shm weston-flower weston-smoke weston-resizor weston-scaler; do
                 if [ -f "${weston}/bin/$client" ]; then
                   cp "${weston}/bin/$client" $out/Applications/Wawona.app/Contents/Resources/bin/
                   chmod +x $out/Applications/Wawona.app/Contents/Resources/bin/$client
                 fi
              done
            else
               echo "Warning: Weston bin directory not found at ${weston}/bin"
            fi
            
            if command -v codesign >/dev/null 2>&1; then
                find "$out/Applications/Wawona.app/Contents/Resources/bin" -type f -perm +111 -exec codesign --force --sign - --timestamp=none {} \; 2>/dev/null || true
            fi
            
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
          <string>Copyright © 2026 Alex Spaulding. All rights reserved.</string>
        <key>LSMinimumSystemVersion</key>
        <string>26.0</string>
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
            
            ${generateIcons "macos"}
            
            runHook postInstall
    '';

    postInstall = ''
      mkdir -p $out/bin
      ln -s $out/Applications/Wawona.app/Contents/MacOS/Wawona $out/bin/Wawona
      ln -s $out/Applications/Wawona.app/Contents/MacOS/Wawona $out/bin/wawona-macos
    '';
  }
