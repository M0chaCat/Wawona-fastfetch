{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # Use pixman from nixpkgs source
  pixmanSource = pkgs.pixman.src;
  src = pixmanSource;
  buildFlags = [ ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "pixman-ios";
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
  ];
  buildInputs = [ ];
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
        
        export NIX_CFLAGS_COMPILE=""
        export NIX_CXXFLAGS_COMPILE=""
        if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
          IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
          IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
        else
          IOS_CC="${buildPackages.clang}/bin/clang"
          IOS_CXX="${buildPackages.clang}/bin/clang++"
        fi
        
        # Create iOS cross-file for Meson
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
    c_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0', '-fPIC']
    cpp_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0', '-fPIC']
    c_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0']
    cpp_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0']
    EOF
  '';
  configurePhase = ''
    runHook preConfigure
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=ios-cross-file.txt \
      --buildtype=release \
      -Ddefault_library=static \
      ${lib.concatMapStringsSep " " (flag: flag) buildFlags}
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
