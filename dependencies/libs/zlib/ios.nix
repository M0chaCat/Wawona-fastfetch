{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  src = pkgs.fetchurl {
    url = "https://zlib.net/zlib-1.3.1.tar.gz";
    sha256 = "08yzf8xz0q7vxs8mnn74xmpxsrs6wy0aan55lpmpriysvyvv54ws";
  };
in
pkgs.stdenv.mkDerivation {
  name = "zlib-ios";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [ ];
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
  '';
  configurePhase = ''
    runHook preConfigure
    # zlib uses configure script
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export CFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
    ./configure --prefix=$out --static
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    make
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install
    runHook postInstall
  '';
}
