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
in

{
  buildForAndroid =
    name: entry:
    if name == "libwayland" then
      (import ../deps/libwayland/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "expat" then
      (import ../deps/expat/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "libffi" then
      (import ../deps/libffi/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "libxml2" then
      (import ../deps/libxml2/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "waypipe" then
      (import ../deps/waypipe/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "swiftshader" then
      (import ../deps/swiftshader/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "zstd" then
      (import ../deps/zstd/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "lz4" then
      (import ../deps/lz4/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else if name == "ffmpeg" then
      (import ../deps/ffmpeg/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = buildModule;
      }
    else
      let
        androidToolchain = import ../common/android-toolchain.nix { inherit lib pkgs; };
        src = fetchSource entry;
        buildSystem = getBuildSystem entry;
        buildFlags = entry.buildFlags.android or [ ];
        patches = lib.filter (p: p != null && builtins.pathExists (toString p)) (
          entry.patches.android or [ ]
        );
      in
      if buildSystem == "cmake" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            cmake
            pkg-config
          ];
          buildInputs = [ ];
          preConfigure = ''
            if [ -d expat ]; then
              cd expat
            fi
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
            "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
            "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
            "-DCMAKE_C_FLAGS=--target=${androidToolchain.androidTarget}"
            "-DCMAKE_CXX_FLAGS=--target=${androidToolchain.androidTarget}"
          ]
          ++ buildFlags;
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
          CARGO_BUILD_TARGET = "aarch64-linux-android";
          CC = androidToolchain.androidCC;
          CXX = androidToolchain.androidCXX;
        }
      else
        pkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            autoconf
            automake
            libtool
            pkg-config
            texinfo
          ];
          buildInputs = [ ];
          preConfigure = ''
            if [ ! -f ./configure ]; then
              autoreconf -fi || autogen.sh || true
            fi
            export CC="${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}"
            export CXX="${androidToolchain.androidCXX} --target=${androidToolchain.androidTarget}"
            export AR="${androidToolchain.androidAR}"
            export STRIP="${androidToolchain.androidSTRIP}"
            export RANLIB="${androidToolchain.androidRANLIB}"
            export CFLAGS="-fPIC"
            export CXXFLAGS="-fPIC"
          '';
          configurePhase = ''
            runHook preConfigure
            ./configure --prefix=/usr --host=${androidToolchain.androidTarget} ${
              lib.concatMapStringsSep " " (flag: flag) buildFlags
            }
            runHook postConfigure
          '';
          buildPhase = ''
            runHook preBuild
            make -j$NIX_BUILD_CORES
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            make install DESTDIR=$out || make install-data-am install-exec-am DESTDIR=$out || true
            if [ -d "$out/usr" ]; then
              if [ -d "$out/usr/lib" ]; then
                mkdir -p $out/lib
                cp -r $out/usr/lib/* $out/lib/ 2>/dev/null || true
              fi
              if [ -d "$out/usr/lib/pkgconfig" ]; then
                mkdir -p $out/lib/pkgconfig
                cp -r $out/usr/lib/pkgconfig/* $out/lib/pkgconfig/ || true
              fi
              if [ -d "$out/usr/include" ]; then
                mkdir -p $out/include
                cp -r $out/usr/include/* $out/include/ || true
              fi
            fi
            runHook postInstall
          '';
          CC = "${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}";
          CXX = "${androidToolchain.androidCXX} --target=${androidToolchain.androidTarget}";
          NIX_CFLAGS_COMPILE = "-fPIC";
          NIX_CXXFLAGS_COMPILE = "-fPIC";
          __impureHostDeps = [ "/bin/sh" ];
        };
}
