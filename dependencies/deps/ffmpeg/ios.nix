{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  ffmpegSource = {
    source = "github";
    owner = "FFmpeg";
    repo = "FFmpeg";
    tag = "n7.1";
    sha256 = "sha256-erTkv156VskhYEJWjpWFvHjmcr2hr6qgUi28Ho8NFYk=";
  };
  src = fetchSource ffmpegSource;
in
pkgs.stdenv.mkDerivation {
  name = "ffmpeg-ios";
  inherit src;
  
  # We need to access /Applications/Xcode.app for the SDK and toolchain
  __noChroot = true; 

  nativeBuildInputs = with buildPackages; [
    pkg-config
    nasm
    yasm
  ];
  
  buildInputs = [];
  
  # Configure phase to set up the environment
  preConfigure = ''
    # Find Xcode path dynamically
    if [ -d "/Applications/Xcode.app" ]; then
      export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    elif [ -d "/Applications/Xcode-beta.app" ]; then
      export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
    else
      # Fallback to xcode-select
      export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    fi
    
    echo "Using Developer Dir: $DEVELOPER_DIR"
    
    export IOS_SDK_PATH="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
    export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    
    if [ ! -d "$IOS_SDK_PATH" ]; then
      echo "Error: iOS SDK not found at $IOS_SDK_PATH"
      exit 1
    fi
    
    echo "Using iOS SDK: $IOS_SDK_PATH"
    
    # Use the toolchain from Xcode
    export TOOLCHAIN_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    export CC="$TOOLCHAIN_BIN/clang"
    export CXX="$TOOLCHAIN_BIN/clang++"
    export AR="$TOOLCHAIN_BIN/ar"
    export RANLIB="$TOOLCHAIN_BIN/ranlib"
    export STRIP="$TOOLCHAIN_BIN/strip"
    export NM="$TOOLCHAIN_BIN/nm"
    
    # HOST compiler (runs on macOS)
    export HOST_CC="/usr/bin/clang"
    
    # Flags for TARGET (iOS)
    export CFLAGS="-arch arm64 -isysroot $IOS_SDK_PATH -mios-simulator-version-min=26.0 -fembed-bitcode"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch arm64 -isysroot $IOS_SDK_PATH -mios-simulator-version-min=26.0"
  '';
  
  configurePhase = ''
    runHook preConfigure
    
    # Explicitly disable programs and runtime checks
    # Note: We set --host-cc to the macOS compiler to allow building helper tools
    ./configure \
      --prefix=$out \
      --libdir=$out/lib \
      --shlibdir=$out/lib \
      --enable-cross-compile \
      --target-os=darwin \
      --arch=arm64 \
      --cc="$CC" \
      --cxx="$CXX" \
      --host-cc="$HOST_CC" \
      --ar="$AR" \
      --ranlib="$RANLIB" \
      --strip="$STRIP" \
      --nm="$NM" \
      --sysroot="$IOS_SDK_PATH" \
      --extra-cflags="$CFLAGS" \
      --extra-ldflags="$LDFLAGS" \
      --enable-rpath \
      --install-name-dir=$out/lib \
      --disable-runtime-cpudetect \
      --disable-programs \
      --disable-doc \
      --disable-debug \
      --enable-shared \
      --disable-static \
      --disable-avdevice \
      --disable-indevs \
      --disable-outdevs \
      --enable-videotoolbox \
      --enable-hwaccel=h264_videotoolbox \
      --enable-hwaccel=hevc_videotoolbox \
      --enable-encoder=h264_videotoolbox \
      --enable-encoder=hevc_videotoolbox \
      --enable-encoder=libx264 \
      --enable-decoder=h264 \
      --enable-decoder=hevc
      
    runHook postConfigure
  '';
  
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    make install || echo "make install failed, continuing with manual installation"
    
    # Ensure include directory exists
    if [ ! -d "$out/include" ] || [ -z "$(ls -A $out/include 2>/dev/null)" ]; then
      echo "Warning: include directory missing or empty, copying headers from source"
      mkdir -p "$out/include"
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter; do
        if [ -d "$libdir" ]; then
          find "$libdir" -name "*.h" -exec install -D {} "$out/include/{}" \; 2>/dev/null || true
        fi
      done
      # Also copy top-level headers if they exist
      if [ -f "libavcodec/avcodec.h" ]; then
        mkdir -p "$out/include/libavcodec"
        cp libavcodec/*.h "$out/include/libavcodec/" 2>/dev/null || true
      fi
      if [ -f "libavutil/avutil.h" ]; then
        mkdir -p "$out/include/libavutil"
        cp libavutil/*.h "$out/include/libavutil/" 2>/dev/null || true
      fi
    fi

    # Ensure lib directory exists
    if [ ! -d "$out/lib" ] || [ -z "$(ls -A $out/lib 2>/dev/null)" ]; then
      echo "Warning: lib directory missing or empty, copying libraries from source"
      mkdir -p "$out/lib"
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter; do
        if [ -d "$libdir" ]; then
          echo "Copying libraries from $libdir..."
          find "$libdir" -name "*.dylib*" -exec cp -v {} "$out/lib/" \; 2>/dev/null || true
        fi
      done
      
      # Fix install names and dependencies for dylibs
      if [ -n "$(ls -A $out/lib/*.dylib 2>/dev/null)" ]; then
        echo "Fixing install names and dependencies for dylibs..."
        for dylib in $out/lib/*.dylib; do
          # Fix ID
          libname=$(basename "$dylib")
          install_name_tool -id "$out/lib/$libname" "$dylib" || true
          
          # Fix dependencies
          otool -L "$dylib" | grep ".dylib" | grep -v ":" | while read -r dep rest; do
            depname=$(basename "$dep")
            if [ -f "$out/lib/$depname" ] && [ "$dep" != "$out/lib/$depname" ]; then
              echo "Changing dependency $dep to $out/lib/$depname in $libname"
              install_name_tool -change "$dep" "$out/lib/$depname" "$dylib" || true
            fi
          done
        done
      fi
    fi
    
    runHook postInstall
  '';
  
  postInstall = ''
    # FFmpeg should generate .pc files, verify they exist
    if [ ! -f "$out/lib/pkgconfig/libavcodec.pc" ]; then
      echo "Warning: libavcodec.pc not found, creating minimal version"
      mkdir -p "$out/lib/pkgconfig"
      cat > "$out/lib/pkgconfig/libavcodec.pc" <<EOF
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include

Name: libavcodec
Description: FFmpeg codec library
Version: 7.1
Requires: libavutil
Libs: -L\''${libdir} -lavcodec
Cflags: -I\''${includedir}
EOF
    fi
    
    if [ ! -f "$out/lib/pkgconfig/libavutil.pc" ]; then
      echo "Warning: libavutil.pc not found, creating minimal version"
      cat > "$out/lib/pkgconfig/libavutil.pc" <<EOF
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include

Name: libavutil
Description: FFmpeg utility library
Version: 7.1
Libs: -L\''${libdir} -lavutil
Cflags: -I\''${includedir}
EOF
    fi
  '';
}
