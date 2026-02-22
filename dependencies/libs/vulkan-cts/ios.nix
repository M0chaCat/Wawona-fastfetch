{
  lib,
  pkgs,
  buildPackages,
  common ? null,
  buildModule,
}:

let
  sources = import ./sources.nix {
    inherit (pkgs) fetchurl fetchFromGitHub;
  };
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  kosmickrisp = buildModule.buildForIOS "kosmickrisp" { };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "vulkan-cts-ios";
  version = "1.4.5.0";

  src = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "VK-GL-CTS";
    rev = "vulkan-cts-${finalAttrs.version}";
    hash = "sha256-cbXSelRPCCH52xczWaxqftbimHe4PyIKZqySQSFTHos=";
  };

  prePatch = ''
    ${sources.prePatch}
  '';

  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    pkg-config
    python3
  ];

  buildInputs = [
    kosmickrisp
    pkgs.vulkan-headers
    pkgs.vulkan-utility-libraries
    pkgs.zlib
    pkgs.libpng
    pkgs.libffi
  ];

  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$PATH:$DEVELOPER_DIR/usr/bin"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    fi
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""

    SIMULATOR_ARCH="arm64"
    if [ "$(uname -m)" = "x86_64" ]; then
      SIMULATOR_ARCH="x86_64"
    fi

    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi

    cat > ios-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES $SIMULATOR_ARCH)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
    set(CMAKE_C_COMPILER "$IOS_CC")
    set(CMAKE_CXX_COMPILER "$IOS_CXX")
    set(CMAKE_SYSROOT "$SDKROOT")
    set(CMAKE_OSX_SYSROOT "$SDKROOT")
    set(CMAKE_C_FLAGS "-mios-simulator-version-min=15.0")
    set(CMAKE_CXX_FLAGS "-mios-simulator-version-min=15.0")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    EOF
  '';

  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DSELECTED_BUILD_TARGETS=deqp-vk"
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${sources.shaderc-src}")
  ];

  postInstall = ''
    test ! -e $out

    mkdir -p $out/bin $out/archive-dir
    cp -a external/vulkancts/modules/vulkan/deqp-vk $out/bin/ || true
    cp -a external/vulkancts/modules/vulkan/vulkan $out/archive-dir/ || true
    cp -a external/vulkancts/modules/vulkan/vk-default $out/ || true
  '';

  meta = {
    description = "Khronos Vulkan Conformance Tests (iOS)";
    homepage = "https://github.com/KhronosGroup/VK-GL-CTS";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin;
  };
})
