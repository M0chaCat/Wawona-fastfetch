{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # SPIRV-LLVM-Translator source - same as nixpkgs
  src = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-LLVM-Translator";
    rev = "v21.1.0";
    sha256 = "sha256-kk8BbPl/UBW1gaO/cuOQ9OsiNTEk0TkvRDLKUAh6exk=";
  };
  spirvToolsIOS = buildModule.buildForIOS "spirv-tools" { inherit simulator; };
in
pkgs.stdenv.mkDerivation {
  name = "spirv-llvm-translator-ios";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
    ninja
  ];
  buildInputs = [
    pkgs.llvmPackages.llvm.dev # LLVM headers for cross-compilation
    spirvToolsIOS
  ];
  preConfigure = ''
        if [ -z "''${XCODE_APP:-}" ]; then
          XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
          if [ -n "$XCODE_APP" ]; then
            export XCODE_APP
            export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
            export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
            export SDKROOT="$DEVELOPER_DIR/Platforms/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.platform/Developer/SDKs/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.sdk"
          fi
        fi
        # Unset macOS deployment target to prevent clang wrapper from adding -mmacos-version-min
        unset MACOSX_DEPLOYMENT_TARGET
        
        TARGET_FLAGS="-target arm64-apple-ios26.0${if simulator then "-simulator" else ""} -isysroot $SDKROOT"
        
        export NIX_CFLAGS_COMPILE="$TARGET_FLAGS"
        export NIX_CXXFLAGS_COMPILE="$TARGET_FLAGS"
        export NIX_LDFLAGS=""
        
        if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
          IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
          IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
        else
          echo "DEBUG: Using Nix clang wrapper"
          IOS_CC="${buildPackages.clang}/bin/clang"
          IOS_CXX="${buildPackages.clang}/bin/clang++"
        fi
        
        # Force usage of Xcode clang if found, bypassing Nix wrapper
        export CC="$IOS_CC"
        export CXX="$IOS_CXX"
        
        # Disable building llvm-spirv tool to avoid BUNDLE DESTINATION error
        # We only need the library for Mesa
        sed -i 's|add_subdirectory(tools/llvm-spirv)|# add_subdirectory(tools/llvm-spirv)|g' CMakeLists.txt
        
        TOOLCHAIN_FILE="$PWD/ios-toolchain.cmake"
        cat > ios-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES arm64)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
    set(CMAKE_C_COMPILER "$IOS_CC")
    set(CMAKE_CXX_COMPILER "$IOS_CXX")
    set(CMAKE_SYSROOT "$SDKROOT")
    set(BUILD_SHARED_LIBS OFF)
    set(CMAKE_BUILD_TYPE Release)
    set(CMAKE_C_FLAGS "$TARGET_FLAGS")
    set(CMAKE_CXX_FLAGS "$TARGET_FLAGS")
    set(CMAKE_C_FLAGS_INIT "$TARGET_FLAGS")
    set(CMAKE_CXX_FLAGS_INIT "$TARGET_FLAGS")
    set(CMAKE_EXE_LINKER_FLAGS "$TARGET_FLAGS")
    set(CMAKE_SHARED_LINKER_FLAGS "$TARGET_FLAGS")
    set(CMAKE_MODULE_LINKER_FLAGS "$TARGET_FLAGS")
    EOF
  '';
  configurePhase = ''
    runHook preConfigure

    NINJA_PATH="${buildPackages.ninja}/bin/ninja"
    echo "DEBUG: NINJA_PATH=$NINJA_PATH"

    TOOLCHAIN_FILE="$PWD/ios-toolchain.cmake"
    cmakeFlagsArray+=("-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE")
    cmakeFlagsArray+=("-DCMAKE_MAKE_PROGRAM=$NINJA_PATH")
    cmakeFlagsArray+=("-DCMAKE_BUILD_TYPE=Release")
    cmakeFlagsArray+=("-DBUILD_SHARED=OFF")
    cmakeFlagsArray+=("-DLLVM_DIR=${pkgs.llvmPackages.llvm.dev}/lib/cmake/llvm")
    cmakeFlagsArray+=("-DSPIRV-Headers_SOURCE_DIR=${pkgs.spirv-headers.src}")

    echo "Running cmake with flags: -DCMAKE_INSTALL_PREFIX=$out ''${cmakeFlagsArray[@]}"
    cmake . -GNinja -DCMAKE_INSTALL_PREFIX=$out "''${cmakeFlagsArray[@]}"

    runHook postConfigure
  '';
  cmakeFlags = [ ];
}
