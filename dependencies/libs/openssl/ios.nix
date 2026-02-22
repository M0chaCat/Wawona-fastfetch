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
in
pkgs.stdenv.mkDerivation {
  name = "openssl-ios";
  src = pkgs.fetchurl {
    url = "https://www.openssl.org/source/openssl-3.3.1.tar.gz";
    sha256 = "sha256-d3zVlihMiDN1oqehG/XSeG/FQTJV76sgxQ1v/m0CC34=";
  };

  nativeBuildInputs = with buildPackages; [ perl ];
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
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    export CC="$IOS_CC"
    export CFLAGS="-arch arm64 -target arm64-apple-ios26.0${if simulator then "-simulator" else ""} -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export LDFLAGS="-arch arm64 -target arm64-apple-ios26.0${if simulator then "-simulator" else ""} -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
    ./Configure ${if simulator then "iossimulator-xcrun" else "ios64-cross"} no-shared no-dso --prefix=$out --openssldir=$out/etc/ssl
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install_sw install_ssldirs
    runHook postInstall
  '';

  __noChroot = true;
}
