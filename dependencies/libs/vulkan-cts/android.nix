{
  lib,
  pkgs,
  buildPackages,
  common ? null,
  buildModule ? null,
}:

let
  sources = import ./sources.nix {
    inherit (pkgs) fetchurl fetchFromGitHub;
  };
  androidToolchain = import ../../toolchains/android.nix { inherit lib pkgs; };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "vulkan-cts-android";
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
    makeWrapper
  ];

  buildInputs = with pkgs; [
    vulkan-headers
    vulkan-utility-libraries
    zlib
    libpng
  ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
    export LDFLAGS="--target=${androidToolchain.androidTarget}"
  '';

  cmakeFlags = [
    "-DCMAKE_SYSTEM_NAME=Android"
    "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
    "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
    "-DCMAKE_ANDROID_API=${toString androidToolchain.androidNdkApiLevel}"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    "-DCMAKE_C_FLAGS=--target=${androidToolchain.androidTarget}"
    "-DCMAKE_CXX_FLAGS=--target=${androidToolchain.androidTarget}"
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

  postFixup = ''
    mkdir -p $out/bin
    cat > $out/bin/vulkan-cts-android-run <<'SCRIPT'
    #!/usr/bin/env bash
    set -euo pipefail
    DEQP_DIR="$(cd "$(dirname "$0")/.." && pwd)"

    echo "=== Vulkan CTS Android Runner ==="
    echo "Pushing deqp-vk to device..."
    adb push "$DEQP_DIR/bin/deqp-vk" /data/local/tmp/deqp-vk
    adb push "$DEQP_DIR/archive-dir/" /data/local/tmp/archive-dir/
    adb shell chmod +x /data/local/tmp/deqp-vk

    echo "Running deqp-vk on device..."
    adb shell "cd /data/local/tmp && ./deqp-vk --deqp-archive-dir=./archive-dir $*"
    SCRIPT
    chmod +x $out/bin/vulkan-cts-android-run
  '';

  meta = {
    description = "Khronos Vulkan Conformance Tests (Android)";
    homepage = "https://github.com/KhronosGroup/VK-GL-CTS";
    license = lib.licenses.asl20;
  };
})
