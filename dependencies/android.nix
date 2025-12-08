# Android-specific dependency builds

{ lib, pkgs, buildPackages, common }:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
in

{
  # Build a dependency for Android
  # Note: Android NDK cross-compilation from macOS may not be fully supported
  buildForAndroid = name: entry:
    let
      # Android cross-compilation setup - defined inside function to avoid top-level evaluation
      androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
      
      src = fetchSource entry;
      
      buildSystem = getBuildSystem entry;
      buildFlags = entry.buildFlags.android or [];
      patches = entry.patches.android or [];
      
      # Determine build inputs based on dependency name
      # For wayland, we need expat, libffi, libxml2
      # These are target packages (built for Android)
      depInputs = if name == "wayland" then [
        androidPkgs.expat
        androidPkgs.libffi
        androidPkgs.libxml2
      ] else [];
    in
      if buildSystem == "cmake" then
        androidPkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          
          nativeBuildInputs = with androidPkgs; [
            cmake
            pkg-config
          ];
          
          buildInputs = depInputs;
          
          cmakeFlags = [
            "-DCMAKE_SYSTEM_NAME=Android"
            "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
            "-DCMAKE_ANDROID_NDK=${androidPkgs.stdenv.cc}"
          ] ++ buildFlags;
        }
      else if buildSystem == "meson" then
        # Use androidPkgs.stdenv - it handles Android cross-compilation properly
        # Access through let binding to delay evaluation and avoid recursion
        let
          stdenv' = androidPkgs.stdenv;
        in
        stdenv'.mkDerivation {
          name = "${name}-android";
          src = src;
          patches = lib.filter (p: p != null && builtins.pathExists (toString p)) patches;
          
          nativeBuildInputs = with androidPkgs; [
            meson
            ninja
            pkg-config
            python3
            bison
            flex
          ];
          
          buildInputs = depInputs;
          
          # Meson setup command
          configurePhase = ''
            runHook preConfigure
            meson setup build \
              --prefix=$out \
              --libdir=$out/lib \
              ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
            runHook postConfigure
          '';
          
          buildPhase = ''
            runHook preBuild
            meson compile -C build
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            meson install -C build
            runHook postInstall
          '';
        }
      else if buildSystem == "cargo" || buildSystem == "rust" then
        # Rust/Cargo build for Android
        androidPkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          
          # Use cargoHash (newer SRI format) or cargoSha256 (older)
          # If neither provided, use fakeHash to let Nix compute it
          cargoHash = if entry ? cargoHash && entry.cargoHash != null then entry.cargoHash else lib.fakeHash;
          cargoSha256 = entry.cargoSha256 or null;
          cargoLock = entry.cargoLock or null;
          
          nativeBuildInputs = with androidPkgs; [
            pkg-config
          ];
          
          buildInputs = depInputs;
        }
      else
        # Default to autotools
        androidPkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          
          nativeBuildInputs = with androidPkgs; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          
          buildInputs = depInputs;
          
          configureFlags = buildFlags;
        };
}
