{
  description = "Wawona";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

      androidSDK = pkgs.androidenv.composeAndroidPackages {
        cmdLineToolsVersion = "latest";
        platformToolsVersion = "latest";
        buildToolsVersions = [ "36.0.0" ];
        platformVersions = [ "36" ];
        abiVersions = [ "arm64-v8a" ];
        includeEmulator = true;
        emulatorVersion = "36.4.2";
        includeSystemImages = true;
        systemImageTypes = [ "google_apis_playstore" ];
      };

      buildModule = import ./dependencies/build.nix {
        lib = pkgs.lib;
        inherit pkgs;
        stdenv = pkgs.stdenv;
        buildPackages = pkgs.buildPackages;
      };

      wawonaSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter =
          path: type:
          let
            base = baseNameOf path;
          in
          !(
            base == ".git"
            || base == "build"
            || base == "result"
            || base == ".direnv"
            || pkgs.lib.hasPrefix "result" base
          );
      };

      wawonaBuildModule = import ./dependencies/wawona.nix {
        lib = pkgs.lib;
        inherit
          pkgs
          buildModule
          wawonaSrc
          androidSDK
          ;
      };

      androidToolchain = import ./dependencies/common/android-toolchain.nix {
        inherit (pkgs) lib;
        inherit pkgs;
      };

      updateAndroidDeps = pkgs.writeShellScriptBin "update-android-deps" ''
        export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
        export GRADLE_USER_HOME=$(pwd)/.gradle-home
        cd src/android
        ${pkgs.gradle}/bin/gradle dependencyUpdates
      '';

      multiplexDev = pkgs.writeShellScriptBin "wawona-multiplex" ''
        tmux="${pkgs.tmux}/bin/tmux"
        $tmux new-session -d -s wawona "nix run .#wawona-macos"
        $tmux split-window -t wawona "nix run .#wawona-ios"
        $tmux split-window -t wawona "nix run .#wawona-android"
        $tmux select-layout -t wawona tiled
        $tmux attach -t wawona
      '';

      # Individual dependency packages for each platform
      iosDeps = buildModule.ios;
      macosDeps = buildModule.macos;
      androidDeps = buildModule.android;

      waypipeMacosWrapper = pkgs.writeShellScriptBin "waypipe-macos" ''
        # Force XDG_RUNTIME_DIR to match Wawona's predictable path
        # We override any existing value to ensure connection with Wawona compositor
        export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
        
        # Default to wayland-0 if not set
        if [ -z "$WAYLAND_DISPLAY" ]; then
          export WAYLAND_DISPLAY="wayland-0"
        fi

        exec "${macosDeps.waypipe}/bin/waypipe" "$@"
      '';

      wawonaMacosWrapper = pkgs.writeShellScriptBin "wawona-macos" ''
        # Force XDG_RUNTIME_DIR to match Wawona's predictable path
        # We override any existing value to ensure predictable socket location
        export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
        
        exec "${wawonaBuildModule.macos}/bin/Wawona" "$@"
      '';

    in
    {
      packages.${system} = {
        default = wawonaMacosWrapper;
        wawona-ios = wawonaBuildModule.ios;
        wawona-macos = wawonaMacosWrapper;
        wawona-android = wawonaBuildModule.android;

        # iOS dependencies
        waypipe-ios = iosDeps.waypipe;
        ffmpeg-ios = iosDeps.ffmpeg;
        "libwayland-ios" = iosDeps.libwayland;
        "kosmickrisp-ios" = iosDeps.kosmickrisp;
        "lz4-ios" = iosDeps.lz4;
        "zstd-ios" = iosDeps.zstd;
        "expat-ios" = iosDeps.expat;
        "libffi-ios" = iosDeps.libffi;
        "libxml2-ios" = iosDeps.libxml2;
        "epoll-shim-ios" = iosDeps."epoll-shim";

        # macOS dependencies
        waypipe-macos = macosDeps.waypipe;
        ffmpeg-macos = macosDeps.ffmpeg;
        "libwayland-macos" = macosDeps.libwayland;
        "kosmickrisp-macos" = macosDeps.kosmickrisp;
        "lz4-macos" = macosDeps.lz4;
        "zstd-macos" = macosDeps.zstd;
        "expat-macos" = macosDeps.expat;
        "libffi-macos" = macosDeps.libffi;
        "libxml2-macos" = macosDeps.libxml2;
        "epoll-shim-macos" = macosDeps."epoll-shim";

        # Android dependencies
        waypipe-android = androidDeps.waypipe;
        ffmpeg-android = androidDeps.ffmpeg;
        "libwayland-android" = androidDeps.libwayland;
        "swiftshader-android" = androidDeps.swiftshader;
        "lz4-android" = androidDeps.lz4;
        "zstd-android" = androidDeps.zstd;
        "expat-android" = androidDeps.expat;
        "libffi-android" = androidDeps.libffi;
        "libxml2-android" = androidDeps.libxml2;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${multiplexDev}/bin/wawona-multiplex";
        };
        wawona-ios = {
          type = "app";
          program = "${wawonaBuildModule.ios}/bin/wawona-ios-simulator";
        };
        wawona-android = {
          type = "app";
          program = "${wawonaBuildModule.android}/bin/wawona-android-run";
        };
        wawona-macos = {
          type = "app";
          program = "${wawonaMacosWrapper}/bin/wawona-macos";
        };
        update-android-deps = {
          type = "app";
          program = "${updateAndroidDeps}/bin/update-android-deps";
        };
        waypipe-macos = {
          type = "app";
          program = "${waypipeMacosWrapper}/bin/waypipe-macos";
        };
      };

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.gradle
          pkgs.jdk17
          androidSDK.androidsdk
        ];
        ANDROID_SDK_ROOT = "${androidSDK.androidsdk}/libexec/android-sdk";
        ANDROID_NDK_ROOT = "${androidToolchain.androidndkRoot}";
      };
    };
}
