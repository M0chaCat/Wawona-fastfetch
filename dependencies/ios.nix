# iOS-specific dependency builds

{ lib, pkgs, buildPackages, common }:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
in

{
  # Build a dependency for iOS
  buildForIOS = name: entry:
    let
      # iOS cross-compilation setup - use a function to delay evaluation
      # This prevents infinite recursion when accessing the package set
      getIosPkgs = pkgs.pkgsCross.iphone64;
      iosPkgs = getIosPkgs;
      
      src = fetchSource entry;
      
      buildSystem = getBuildSystem entry;
      buildFlags = entry.buildFlags.ios or [];
      patches = entry.patches.ios or [];
      
      # Determine build inputs based on dependency name
      # For wayland, dependencies will be found via pkg-config
      # We avoid explicit references to avoid circular dependencies
      # The cross-compilation environment should provide these
      depInputs = [];
    in
      if buildSystem == "cmake" then
        iosPkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          
          nativeBuildInputs = with iosPkgs; [
            cmake
            pkg-config
          ];
          
          buildInputs = depInputs;
          
          cmakeFlags = [
            "-DCMAKE_SYSTEM_NAME=iOS"
            "-DCMAKE_OSX_ARCHITECTURES=arm64"
            "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0"
          ] ++ buildFlags;
          
          installPhase = ''
            runHook preInstall
            make install DESTDIR=$out
            runHook postInstall
          '';
        }
      else if buildSystem == "meson" then
        # Use iosPkgs.stdenv - it handles iOS cross-compilation properly
        # Access through let binding to delay evaluation and avoid recursion
        let
          stdenv' = iosPkgs.stdenv;
        in
        stdenv'.mkDerivation {
          name = "${name}-ios";
          src = src;
          patches = lib.filter (p: p != null && builtins.pathExists (toString p)) patches;
          
          # Use buildPackages for native build tools (run on host)
          nativeBuildInputs = with buildPackages; [
            meson
            ninja
            pkg-config
            python3
            bison
            flex
          ];
          
          # Use iosPkgs for target dependencies (built for iOS)
          # Access lazily to avoid recursion
          buildInputs = depInputs;
          
          # Set cross-compilation environment
          crossConfig = "aarch64-apple-ios";
          
          # Meson setup command
          # Use environment variables set by Nix for cross-compilation
          configurePhase = ''
            runHook preConfigure
            # Create a basic iOS cross file for Meson
            # Use CC/CXX from environment (set by Nix cross-compilation)
            cat > ios-cross-file.txt <<EOF
            [binaries]
            c = '$CC'
            cpp = '$CXX'
            ar = '$AR'
            strip = '$STRIP'
            
            [host_machine]
            system = 'darwin'
            cpu_family = 'aarch64'
            cpu = 'aarch64'
            endian = 'little'
            
            [built-in options]
            c_args = ['-arch', 'arm64', '-mios-version-min=15.0']
            cpp_args = ['-arch', 'arm64', '-mios-version-min=15.0']
            EOF
            
            meson setup build \
              --prefix=$out \
              --libdir=$out/lib \
              --cross-file=ios-cross-file.txt \
              ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
            runHook postConfigure
          '';
          
          # Set CC/CXX/AR/STRIP for iOS cross-compilation
          # Use buildPackages for compiler (runs on host)
          # The target prefix is 'aarch64-apple-ios-'
          CC = "${buildPackages.clang}/bin/clang";
          CXX = "${buildPackages.clang}/bin/clang++";
          AR = "${buildPackages.binutils}/bin/ar";
          STRIP = "${buildPackages.binutils}/bin/strip";
          
          # Set iOS-specific flags
          NIX_CFLAGS_COMPILE = "-arch arm64 -mios-version-min=15.0 -isysroot ${buildPackages.darwin.iosSdkPkgs.sdk}";
          NIX_CXXFLAGS_COMPILE = "-arch arm64 -mios-version-min=15.0 -isysroot ${buildPackages.darwin.iosSdkPkgs.sdk}";
          
          # Set up cross-compilation environment
          # Dependencies will be added via buildInputs after we get the basic build working
          __impureHostDeps = [ "/bin/sh" ];
          
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
        # Rust/Cargo build for iOS
        iosPkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          
          # Use cargoHash (newer SRI format) or cargoSha256 (older)
          # If neither provided, use fakeHash to let Nix compute it
          cargoHash = if entry ? cargoHash && entry.cargoHash != null then entry.cargoHash else lib.fakeHash;
          cargoSha256 = entry.cargoSha256 or null;
          cargoLock = entry.cargoLock or null;
          
          nativeBuildInputs = with iosPkgs; [
            pkg-config
          ];
          
          buildInputs = depInputs;
        }
      else
        # Default to autotools
        iosPkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          
          nativeBuildInputs = with iosPkgs; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          
          buildInputs = depInputs;
          
          configureFlags = buildFlags;
        };
}
