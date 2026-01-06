# foot - Fast, lightweight Wayland terminal emulator (Android port)
# https://codeberg.org/dnkl/foot
#
# NOTE: This is a placeholder for the Android port.
# Similar to iOS, foot needs significant adaptation for Android.

{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  
  footSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "foot";
    tag = "1.18.1";
    sha256 = "sha256-7tTaXd/jTrFxXxYFt9mTx0dIaGa3vnJfZ5wXjX0HBDA=";
  };
  src = fetchSource footSource;
in
pkgs.stdenv.mkDerivation {
  pname = "foot-android";
  version = "1.18.1";
  inherit src;
  
  # Mark as broken until full port is complete
  meta.broken = true;
  
  buildPhase = ''
    echo "=========================================="
    echo "FOOT TERMINAL Android PORT - NOT YET COMPLETE"
    echo "=========================================="
    echo ""
    echo "Foot terminal requires these adaptations for Android:"
    echo ""
    echo "1. NDK CROSS-COMPILATION"
    echo "   - Build with Android NDK toolchain"
    echo "   - Target arm64-v8a and x86_64 ABIs"
    echo ""
    echo "2. PROCESS MODEL"
    echo "   - Android supports fork() but with limitations"
    echo "   - Consider JNI integration for better lifecycle"
    echo ""
    echo "3. FONT RENDERING"
    echo "   - Use Android's Skia or FreeType"
    echo "   - Font discovery through Android APIs"
    echo ""
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/wawona
    cat > $out/share/wawona/app.json << 'EOF'
{
  "id": "org.codeberg.dnkl.foot",
  "name": "Foot Terminal",
  "description": "Fast, lightweight Wayland terminal (Android port in progress)",
  "version": "1.18.1",
  "status": "not_ported",
  "platform": "android"
}
EOF
    runHook postInstall
  '';
}

