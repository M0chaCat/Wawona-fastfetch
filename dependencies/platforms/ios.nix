{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
}:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs; };
in

{
  buildForIOS =
    name: entry:
    if name == "libwayland" then
      (import ../deps/libwayland/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "expat" then
      (import ../deps/expat/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "libffi" then
      (import ../deps/libffi/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "libxml2" then
      (import ../deps/libxml2/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "waypipe" then
      (import ../deps/waypipe/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "kosmickrisp" then
      (import ../deps/kosmickrisp/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "zlib" then
      (import ../deps/zlib/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "zstd" then
      (import ../deps/zstd/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "lz4" then
      (import ../deps/lz4/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "ffmpeg" then
      (import ../deps/ffmpeg/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "spirv-llvm-translator" then
      (import ../deps/spirv-llvm-translator/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "spirv-tools" then
      (import ../deps/spirv-tools/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else if name == "libclc" then
      (import ../deps/libclc/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          ;
      }
    else
      let
        src = if entry.source == "system" then null else fetchSource entry;
        buildSystem = getBuildSystem entry;
        buildFlags = entry.buildFlags.ios or [ ];
        patches = lib.filter (p: p != null && builtins.pathExists (toString p)) (entry.patches.ios or [ ]);
      in
      if buildSystem == "cmake" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            cmake
            pkg-config
          ];
          buildInputs = [ ];
          preConfigure = ''
                          if [ -z "''${XCODE_APP:-}" ]; then
                            XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
                            if [ -n "$XCODE_APP" ]; then
                              export XCODE_APP
                              export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
                              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
                              # Use iPhoneSimulator SDK for simulator builds
                              export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
                            fi
                          fi
                          if [ -d expat ]; then
                            cd expat
                          fi
                          export NIX_CFLAGS_COMPILE=""
                          export NIX_CXXFLAGS_COMPILE=""
                          if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
                            IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                            IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
                          else
                            IOS_CC="${buildPackages.clang}/bin/clang"
                            IOS_CXX="${buildPackages.clang}/bin/clang++"
                          fi
                          # Determine architecture for simulator
                          SIMULATOR_ARCH="arm64"
                          if [ "$(uname -m)" = "x86_64" ]; then
                            SIMULATOR_ARCH="x86_64"
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
            EOF
          '';
          cmakeFlags = [
            "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
          ]
          ++ buildFlags;
        }
      else if buildSystem == "meson" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            meson
            ninja
            pkg-config
            (python3.withPackages (
              ps: with ps; [
                setuptools
                pip
                packaging
                mako
                pyyaml
              ]
            ))
            bison
            flex
          ];
          buildInputs = [ ];
          preConfigure = ''
                          if [ -z "''${XCODE_APP:-}" ]; then
                            XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
                            if [ -n "$XCODE_APP" ]; then
                              export XCODE_APP
                              export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
                              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
                              # Use iPhoneSimulator SDK for simulator builds
                              export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
                            fi
                          fi
                          export NIX_CFLAGS_COMPILE=""
                          export NIX_CXXFLAGS_COMPILE=""
                          if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
                            IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                            IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
                          else
                            IOS_CC="${buildPackages.clang}/bin/clang"
                            IOS_CXX="${buildPackages.clang}/bin/clang++"
                          fi
                          # Determine architecture for simulator
                          SIMULATOR_ARCH="arm64"
                          if [ "$(uname -m)" = "x86_64" ]; then
                            SIMULATOR_ARCH="x86_64"
                          fi
                          cat > ios-cross-file.txt <<EOF
            [binaries]
            c = '$IOS_CC'
            cpp = '$IOS_CXX'
            ar = 'ar'
            strip = 'strip'
            pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

            [host_machine]
            system = 'darwin'
            cpu_family = 'aarch64'
            cpu = 'aarch64'
            endian = 'little'

            [built-in options]
            c_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0', '-fPIC']
            cpp_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0', '-fPIC']
            c_link_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0']
            cpp_link_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0']
            EOF
          '';
          configurePhase = ''
            runHook preConfigure
            meson setup build \
              --prefix=$out \
              --libdir=$out/lib \
              --cross-file=ios-cross-file.txt \
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
        pkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          cargoHash = if entry ? cargoHash && entry.cargoHash != null then entry.cargoHash else lib.fakeHash;
          cargoSha256 = entry.cargoSha256 or null;
          cargoLock = entry.cargoLock or null;
          nativeBuildInputs = with buildPackages; [ pkg-config ];
          buildInputs = [ ];
          CARGO_BUILD_TARGET = "aarch64-apple-ios";
        }
      else
        pkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          buildInputs = [ ];
          preConfigure = ''
            if [ -z "''${XCODE_APP:-}" ]; then
              XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
              if [ -n "$XCODE_APP" ]; then
                export XCODE_APP
                export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
                export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
                # Use iPhoneSimulator SDK for simulator builds
                export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
              fi
            fi
            if [ ! -f ./configure ]; then
              autoreconf -fi || autogen.sh || true
            fi
            export NIX_CFLAGS_COMPILE=""
            export NIX_CXXFLAGS_COMPILE=""
            if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
              IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
              IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
            else
              IOS_CC="${buildPackages.clang}/bin/clang"
              IOS_CXX="${buildPackages.clang}/bin/clang++"
            fi
            # Determine architecture for simulator
            SIMULATOR_ARCH="arm64"
            if [ "$(uname -m)" = "x86_64" ]; then
              SIMULATOR_ARCH="x86_64"
            fi
            export CC="$IOS_CC"
            export CXX="$IOS_CXX"
            export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
            export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
            export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0"
          '';
          configurePhase = ''
            runHook preConfigure
            ./configure --prefix=$out --host=arm-apple-darwin ${
              lib.concatMapStringsSep " " (flag: flag) buildFlags
            }
            runHook postConfigure
          '';
          configureFlags = buildFlags;
        };
}
