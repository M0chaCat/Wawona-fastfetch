{ lib, pkgs, common }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  libxml2Source = {
    source = "gitlab-gnome";
    owner = "GNOME";
    repo = "libxml2";
    rev = "v2.14.0";
    sha256 = "sha256-SFDNj4QPPqZUGLx4lfaUzHn0G/HhvWWXWCFoekD9lYM=";
  };
  src = fetchSource libxml2Source;
  buildFlags = [ "--without-python" ];
  patches = [];
in
pkgs.stdenv.mkDerivation {
  name = "libxml2-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [ autoconf automake libtool pkg-config ];
  buildInputs = [];
  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
      fi
    fi
    if [ ! -f ./configure ]; then
      autoreconf -fi || autogen.sh || true
    fi
    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC"
    export CXXFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0"
  '';
  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=$out --host=aarch64-apple-darwin ${lib.concatMapStringsSep " " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  configureFlags = buildFlags;
}
