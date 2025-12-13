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
        (import ./deps/libwayland/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "expat" then
        (import ./deps/expat/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "libffi" then
        (import ./deps/libffi/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "libxml2" then
        (import ./deps/libxml2/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "waypipe" then
        (import ./deps/waypipe/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else if name == "pixman" then
        (import ./deps/pixman/android.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = androidModuleSelf;
        }
      else
        (import ./platforms/android.nix {
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
      if name == "libwayland" then
        (import ./deps/libwayland/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "expat" then
        (import ./deps/expat/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "libffi" then
        (import ./deps/libffi/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "libxml2" then
        (import ./deps/libxml2/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "waypipe" then
        (import ./deps/waypipe/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "kosmickrisp" then
        (import ./deps/kosmickrisp/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "epoll-shim" then
        (import ./deps/epoll-shim/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else if name == "pixman" then
        (import ./deps/pixman/ios.nix) {
          inherit
            lib
            pkgs
            buildPackages
            common
            ;
          buildModule = iosModuleSelf;
        }
      else
        (import ./platforms/ios.nix {
          inherit
            lib
            pkgs
            buildPackages
            common
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
        (import ./deps/libwayland/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "expat" then
        (import ./deps/expat/macos.nix) { inherit lib pkgs common; }
      else if name == "libffi" then
        (import ./deps/libffi/macos.nix) { inherit lib pkgs common; }
      else if name == "libxml2" then
        (import ./deps/libxml2/macos.nix) { inherit lib pkgs common; }
      else if name == "epoll-shim" then
        (import ./deps/epoll-shim/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "waypipe" then
        (import ./deps/waypipe/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "kosmickrisp" then
        (import ./deps/kosmickrisp/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "spirv-tools" then
        (import ./deps/spirv-tools/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else if name == "spirv-llvm-translator" then
        (import ./deps/spirv-llvm-translator/macos.nix) {
          inherit lib pkgs common;
          buildModule = macosModuleSelf;
        }
      else
        (import ./platforms/macos.nix {
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
            "kosmickrisp" = iosModule.buildForIOS "kosmickrisp" { };
            "epoll-shim" = iosModule.buildForIOS "epoll-shim" { };
            zlib = iosModule.buildForIOS "zlib" { };
            zstd = iosModule.buildForIOS "zstd" { };
            lz4 = iosModule.buildForIOS "lz4" { };
            ffmpeg = iosModule.buildForIOS "ffmpeg" { };
            "spirv-llvm-translator" = iosModule.buildForIOS "spirv-llvm-translator" { };
            "spirv-tools" = iosModule.buildForIOS "spirv-tools" { };
            libclc = iosModule.buildForIOS "libclc" { };
            pixman = iosModule.buildForIOS "pixman" { };
            test-toolchain = pkgs.callPackage ./utils/test-ios-toolchain.nix { };
            test-toolchain-cross = pkgs.callPackage ./utils/test-ios-toolchain-cross.nix { };
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
