{ lib, pkgs, common }:

let
  fetchSource = common.fetchSource;
  expatSource = {
    source = "github";
    owner = "libexpat";
    repo = "libexpat";
    tag = "R_2_7_3";
    sha256 = "sha256-dDxnAJsj515vr9+j2Uqa9E+bB+teIBfsnrexppBtdXg=";
  };
  src = fetchSource expatSource;
  buildFlags = [];
  patches = [];
in
pkgs.stdenv.mkDerivation {
  name = "expat-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [ cmake pkg-config apple-sdk_26 ];
  buildInputs = [];
  preConfigure = ''
    if [ -d expat ]; then
      cd expat
    fi
    MACOS_SDK="${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
  '';
  cmakeFlags = buildFlags ++ [
    "-DCMAKE_OSX_SYSROOT=${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0"
  ];
}
