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
  # libclc is part of LLVM project - fetch from LLVM monorepo
  # Using same source structure as nixpkgs
  src = pkgs.fetchFromGitHub {
    owner = "llvm";
    repo = "llvm-project";
    rev = "llvmorg-21.1.2";
    sha256 = "0mmh84yzkd3dkvmgm2vsdd7ym7i37vs9hal1zzxgpg92pl25s1ja";
  };
in
pkgs.stdenv.mkDerivation {
  name = "libclc-ios";
  # libclc is in libclc subdirectory of llvm-project
  src = pkgs.runCommand "libclc-src" { } ''
    mkdir -p $out
    cp -r ${src}/libclc/. $out/
  '';
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
    ninja
    clang
    llvm
    spirv-tools
    spirv-llvm-translator
  ];
  buildInputs = [
    pkgs.llvmPackages.llvm.dev
    pkgs.llvmPackages.clang-unwrapped.dev
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

        # Patch CMakeLists.txt to avoid building prepare_builtins (which fails to link on iOS)
        # We define it as an imported target pointing to a dummy location.
        # Since we are building spirv targets which don't seem to use prepare_builtins, this bypasses the build error.
        sed -i 's|add_llvm_executable( prepare_builtins utils/prepare-builtins.cpp )|add_executable( prepare_builtins IMPORTED GLOBAL )\nset_target_properties( prepare_builtins PROPERTIES IMPORTED_LOCATION "''${CMAKE_CURRENT_SOURCE_DIR}/prepare_builtins_dummy" )|' CMakeLists.txt
        
        # Remove target_compile_* for prepare_builtins to avoid errors on imported target
        sed -i 's|target_compile_definitions( prepare_builtins|# target_compile_definitions( prepare_builtins|' CMakeLists.txt
        sed -i 's|target_compile_options( prepare_builtins|# target_compile_options( prepare_builtins|' CMakeLists.txt
        
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
    cmakeFlagsArray+=("-DLLVM_DIR=${pkgs.llvmPackages.llvm.dev}/lib/cmake/llvm")
    cmakeFlagsArray+=("-DCLANG_DIR=${pkgs.llvmPackages.clang-unwrapped.dev}/lib/cmake/clang")
    # Use unwrapped clang to avoid wrapper injecting host flags when compiling for GPU targets
    cmakeFlagsArray+=("-DLLVM_TOOL_clang=${pkgs.llvmPackages.clang-unwrapped}/bin/clang")
    # Only build SPIR-V targets for Mesa/Vulkan
    cmakeFlagsArray+=("-DLIBCLC_TARGETS_TO_BUILD=spirv-mesa3d-;spirv64-mesa3d-")

    echo "Running cmake with flags: -DCMAKE_INSTALL_PREFIX=$out ''${cmakeFlagsArray[@]}"
    cmake . -GNinja -DCMAKE_INSTALL_PREFIX=$out "''${cmakeFlagsArray[@]}"

    runHook postConfigure
  '';
  cmakeFlags = [ ];
}
