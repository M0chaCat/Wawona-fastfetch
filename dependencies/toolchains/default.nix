{
  lib,
  pkgs,
  stdenv,
  buildPackages,
}:

let
  common = import ./common/common.nix { inherit lib pkgs; };
  androidModuleSelf = rec {
    buildForAndroid =
      name: entry:
      if name == "libwayland" then
        (import ../libs/libwayland/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "expat" then
        (import ../libs/expat/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "libffi" then
        (import ../libs/libffi/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "libxml2" then
        (import ../libs/libxml2/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "waypipe" then
        (import ../libs/waypipe/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "pixman" then
        (import ../libs/pixman/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "xkbcommon" then
        (import ../libs/xkbcommon/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "openssl" then
        (import ../libs/openssl/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "libssh2" then
        (import ../libs/libssh2/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "mbedtls" then
        (import ../libs/mbedtls/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "openssh" then
        (import ../libs/openssh/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "sshpass" then
        (import ../libs/sshpass/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "vulkan-cts" then
        (import ../libs/vulkan-cts/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            ;
        }
      else
        (import ../platforms/android.nix {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }).buildForAndroid
          name
          entry;
  };
  androidModule = androidModuleSelf;
  iosModuleSelf = rec {
    buildForIOS =
      name: entry:
      let 
        simulator = entry.simulator or false;
      in
      if name == "libwayland" then
        (import ../libs/libwayland/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "expat" then
        (import ../libs/expat/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "libffi" then
        (import ../libs/libffi/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "libxml2" then
        (import ../libs/libxml2/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "waypipe" then
        (import ../libs/waypipe/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "kosmickrisp" then
        (import ../libs/kosmickrisp/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "epoll-shim" then
        (import ../libs/epoll-shim/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "pixman" then
        (import ../libs/pixman/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "mbedtls" then
        (import ../libs/mbedtls/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "libssh2" then
        (import ../libs/libssh2/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "openssl" then
        (import ../libs/openssl/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "openssh" then
        (import ../libs/openssh/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "vulkan-cts" then
        (import ../libs/vulkan-cts/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            ;
          buildModule = iosModuleSelf;
        }
      else
        (import ../platforms/ios.nix {
          inherit
            lib
            pkgs
            buildPackages
            common
            simulator
            ;
          buildModule = iosModuleSelf;
        }).buildForIOS
          name
          entry;
  };
  iosModule = iosModuleSelf;
  macosModuleSelf = rec {
    buildForMacOS =
      name: entry:
      if name == "libwayland" then
        (import ../libs/libwayland/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "expat" then
        (import ../libs/expat/macos.nix) { inherit lib pkgs common; }
      else if name == "libffi" then
        (import ../libs/libffi/macos.nix) { inherit lib pkgs common; }
      else if name == "libxml2" then
        pkgs.callPackage ../libs/libxml2/macos.nix { }
      else if name == "epoll-shim" then
        (import ../libs/epoll-shim/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "waypipe" then
        (import ../libs/waypipe/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "kosmickrisp" then
        (import ../libs/kosmickrisp/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "spirv-tools" then
        (import ../libs/spirv-tools/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "spirv-llvm-translator" then
        (import ../libs/spirv-llvm-translator/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "sshpass" then
        (import ../libs/sshpass/macos.nix) {
          inherit lib pkgs common;
        }
      else if name == "xkbcommon" then
        (import ../libs/xkbcommon/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "pixman" then
        (import ../libs/pixman/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      # Font stack dependencies for foot terminal
      else if name == "tllist" then
        (import ../libs/tllist/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "freetype" then
        (import ../libs/freetype/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "fontconfig" then
        (import ../libs/fontconfig/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "utf8proc" then
        (import ../libs/utf8proc/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "fcft" then
        (import ../libs/fcft/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      # Applications
      else if name == "foot" then
        (import ../clients/foot/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      # Conformance test suites
      else if name == "vulkan-cts" then
        (import ../libs/vulkan-cts/macos.nix) {
          inherit lib pkgs;
          kosmickrisp = macosModuleSelf.buildForMacOS "kosmickrisp" { };
        }
      else
        (import ../platforms/macos.nix {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }).buildForMacOS
          name
          entry;
  };
  macosModule = macosModuleSelf;
  registry = common.registry;
  buildAllForPlatform =
    platform:
    let
      filteredRegistry = lib.filterAttrs (
        _: entry:
        let
          platforms =
            entry.platforms or [
              "ios"
              "macos"
              "android"
            ];
        in
        lib.elem platform platforms
      ) registry;
      directPkgs =
        if platform == "ios" then
          {
            libwayland = iosModule.buildForIOS "libwayland" { };
            expat = iosModule.buildForIOS "expat" { };
            libffi = iosModule.buildForIOS "libffi" { };
            libxml2 = iosModule.buildForIOS "libxml2" { };
            waypipe = iosModule.buildForIOS "waypipe" { };
            "epoll-shim" = iosModule.buildForIOS "epoll-shim" { };
            zlib = iosModule.buildForIOS "zlib" { };
            zstd = iosModule.buildForIOS "zstd" { };
            lz4 = iosModule.buildForIOS "lz4" { };
            ffmpeg = iosModule.buildForIOS "ffmpeg" { };
            pixman = iosModule.buildForIOS "pixman" { };
            mbedtls = iosModule.buildForIOS "mbedtls" { };
            libssh2 = iosModule.buildForIOS "libssh2" { };
            xkbcommon = iosModule.buildForIOS "xkbcommon" { };
            "vulkan-cts" = iosModule.buildForIOS "vulkan-cts" { };
            test-toolchain = pkgs.callPackage ../utils/test-ios-toolchain.nix { };
            test-toolchain-cross = pkgs.callPackage ../utils/test-ios-toolchain-cross.nix { };
          }
        else if platform == "macos" then
          {
            libwayland = macosModule.buildForMacOS "libwayland" { };
            expat = macosModule.buildForMacOS "expat" { };
            libffi = macosModule.buildForMacOS "libffi" { };
            libxml2 = macosModule.buildForMacOS "libxml2" { };
            waypipe = macosModule.buildForMacOS "waypipe" { };
            "kosmickrisp" = macosModule.buildForMacOS "kosmickrisp" { };
            "epoll-shim" = macosModule.buildForMacOS "epoll-shim" { };
            zstd = macosModule.buildForMacOS "zstd" { };
            lz4 = macosModule.buildForMacOS "lz4" { };
            ffmpeg = macosModule.buildForMacOS "ffmpeg" { };
            "spirv-tools" = macosModule.buildForMacOS "spirv-tools" { };
            "spirv-llvm-translator" = macosModule.buildForMacOS "spirv-llvm-translator" { };
            sshpass = macosModule.buildForMacOS "sshpass" { };
            # Rendering and input dependencies
            xkbcommon = macosModule.buildForMacOS "xkbcommon" { };
            pixman = macosModule.buildForMacOS "pixman" { };
            # Font stack for foot terminal
            tllist = macosModule.buildForMacOS "tllist" { };
            freetype = macosModule.buildForMacOS "freetype" { };
            fontconfig = macosModule.buildForMacOS "fontconfig" { };
            utf8proc = macosModule.buildForMacOS "utf8proc" { };
            fcft = macosModule.buildForMacOS "fcft" { };
            # Applications
            foot = macosModule.buildForMacOS "foot" { };
            # Conformance test suites
            "vulkan-cts" = macosModule.buildForMacOS "vulkan-cts" { };
          }
        else if platform == "android" then
          {
            libwayland = androidModule.buildForAndroid "libwayland" { };
            expat = androidModule.buildForAndroid "expat" { };
            libffi = androidModule.buildForAndroid "libffi" { };
            libxml2 = androidModule.buildForAndroid "libxml2" { };
            waypipe = androidModule.buildForAndroid "waypipe" { };
            swiftshader = androidModule.buildForAndroid "swiftshader" { };
            pixman = androidModule.buildForAndroid "pixman" { };
            zstd = androidModule.buildForAndroid "zstd" { };
            lz4 = androidModule.buildForAndroid "lz4" { };
            ffmpeg = androidModule.buildForAndroid "ffmpeg" { };
            xkbcommon = androidModule.buildForAndroid "xkbcommon" { };
            openssl = androidModule.buildForAndroid "openssl" { };
            libssh2 = androidModule.buildForAndroid "libssh2" { };
            mbedtls = androidModule.buildForAndroid "mbedtls" { };
            "vulkan-cts" = androidModule.buildForAndroid "vulkan-cts" { };
          }
        else
          { };
    in
    lib.mapAttrs (
      name: entry:
      if platform == "ios" then
        iosModule.buildForIOS name entry
      else if platform == "macos" then
        macosModule.buildForMacOS name entry
      else if platform == "android" then
        androidModule.buildForAndroid name entry
      else
        throw "Unknown platform: ${platform}"
    ) filteredRegistry
    // directPkgs;
in
{
  buildForIOS = iosModuleSelf.buildForIOS;
  buildForMacOS = macosModuleSelf.buildForMacOS;
  buildForAndroid = androidModule.buildForAndroid;
  buildAllForPlatform = buildAllForPlatform;
  ios = buildAllForPlatform "ios";
  macos = buildAllForPlatform "macos";
  android = buildAllForPlatform "android";
}
