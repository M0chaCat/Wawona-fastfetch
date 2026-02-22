# pixman for macOS - low-level pixel manipulation library
# Used by Wayland compositors and terminals for rendering
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # Use pixman source from nixpkgs
  src = pkgs.pixman.src;
in
pkgs.stdenv.mkDerivation {
  pname = "pixman";
  version = pkgs.pixman.version;
  inherit src;
  
  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    (python3.withPackages (ps: with ps; [
      setuptools
      pip
      packaging
      mako
      pyyaml
    ]))
  ];
  
  buildInputs = [ ];
  
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
    
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
  '';
  
  mesonFlags = [
    # Disable auto features to prevent architecture-specific checks
    "-Dauto_features=disabled"
    # Disable optional features
    "-Dgtk=disabled"
    "-Dlibpng=disabled"
    "-Dtests=disabled"
    "-Ddemos=disabled"
    # Disable all architecture-specific optimizations (use C fallbacks)
    # macOS aarch64 has different ASM syntax that pixman doesn't support
    "-Dloongson-mmi=disabled"
    "-Dvmx=disabled"
    "-Darm-simd=disabled"
    "-Dmips-dspr2=disabled"
    "-Dneon=disabled"
    "-Da64-neon=disabled"
    "-Dsse2=disabled"
    "-Dssse3=disabled"
  ];
  
  meta = with lib; {
    description = "Low-level library for pixel manipulation";
    homepage = "http://pixman.org/";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
