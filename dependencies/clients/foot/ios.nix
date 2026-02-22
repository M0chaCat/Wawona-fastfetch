# foot - Fast, lightweight Wayland terminal emulator (iOS port)
# https://codeberg.org/dnkl/foot
# 
# NOTE: This is a placeholder for the iOS port.
# Foot requires significant patching for iOS due to:
# - No fork() on iOS (need to use dlopen-based process model)
# - PTY handling differences
# - Font stack needs iOS adaptation (CoreText instead of fontconfig/freetype)
#
# For now, this builds the dependencies but the actual foot port
# requires additional platform-specific work.

{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  footSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "foot";
    tag = "1.18.1";
    sha256 = "sha256-7tTaXd/jTrFxXxYFt9mTx0dIaGa3vnJfZ5wXjX0HBDA=";
  };
  src = fetchSource footSource;
  
  # iOS dependencies - these would need to be built for iOS
  # For now, reference existing iOS builds where available
  libwayland = buildModule.buildForIOS "libwayland" {};
  pixman = buildModule.buildForIOS "pixman" {};
  # xkbcommon - already ported for iOS
  # fcft, fontconfig, freetype, utf8proc - would need iOS ports
in
pkgs.stdenv.mkDerivation {
  pname = "foot-ios";
  version = "1.18.1";
  inherit src;
  
  # Mark as broken until full port is complete
  meta.broken = true;
  
  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    scdoc
    wayland-scanner
    python3
  ];
  
  # For now, just set up the source and document what's needed
  buildPhase = ''
    echo "=========================================="
    echo "FOOT TERMINAL iOS PORT - NOT YET COMPLETE"
    echo "=========================================="
    echo ""
    echo "Foot terminal requires these adaptations for iOS:"
    echo ""
    echo "1. PROCESS MODEL"
    echo "   - iOS doesn't support fork()"
    echo "   - Need to compile foot as a dynamic library (.dylib)"
    echo "   - Entry point should be a callable function, not main()"
    echo "   - WawonaKernel will dlopen() and call the entry point"
    echo ""
    echo "2. PTY HANDLING"
    echo "   - iOS has limited PTY support"
    echo "   - May need custom PTY implementation or alternative"
    echo "   - Consider using iOS pseudo-terminal APIs if available"
    echo ""
    echo "3. FONT RENDERING"
    echo "   - Replace fontconfig with iOS font discovery"
    echo "   - Use CoreText for glyph rendering instead of FreeType"
    echo "   - fcft library needs iOS backend"
    echo ""
    echo "4. KEYBOARD INPUT"
    echo "   - iOS keyboard handling through UIKit"
    echo "   - Need to bridge iOS keyboard events to xkbcommon"
    echo ""
    echo "Dependencies that need iOS ports:"
    echo "   - fcft (foot's font library)"
    echo "   - fontconfig (or CoreText replacement)"
    echo "   - freetype (or CoreText replacement)"
    echo "   - utf8proc (Unicode handling)"
    echo ""
    echo "Available iOS dependencies:"
    echo "   - libwayland: ${libwayland}"
    echo "   - pixman: ${pixman}"
    echo ""
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    
    # Create placeholder output
    mkdir -p $out/share/wawona
    cat > $out/share/wawona/app.json << 'EOF'
{
  "id": "org.codeberg.dnkl.foot",
  "name": "Foot Terminal",
  "description": "Fast, lightweight Wayland terminal (iOS port in progress)",
  "version": "1.18.1",
  "status": "not_ported",
  "platform": "ios"
}
EOF
    
    # Copy source for reference
    mkdir -p $out/src
    cp -r . $out/src/
    
    runHook postInstall
  '';
}

