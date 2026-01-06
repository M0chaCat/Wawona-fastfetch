# foot - Fast, lightweight Wayland terminal emulator
# https://codeberg.org/dnkl/foot
{
  lib,
  pkgs,
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
  
  # Dependencies
  libwayland = if buildModule != null 
    then buildModule.buildForMacOS "libwayland" {} 
    else pkgs.wayland;
  pixman = if buildModule != null
    then buildModule.buildForMacOS "pixman" {}
    else pkgs.pixman;
  xkbcommon = if buildModule != null
    then buildModule.buildForMacOS "xkbcommon" {}
    else pkgs.libxkbcommon;
  fcft = if buildModule != null
    then buildModule.buildForMacOS "fcft" {}
    else (throw "fcft not available in nixpkgs, use buildModule");
  tllist = if buildModule != null
    then buildModule.buildForMacOS "tllist" {}
    else pkgs.tllist or (throw "tllist not available");
  utf8proc = if buildModule != null
    then buildModule.buildForMacOS "utf8proc" {}
    else pkgs.utf8proc;
  fontconfig = if buildModule != null
    then buildModule.buildForMacOS "fontconfig" {}
    else pkgs.fontconfig;
  freetype = if buildModule != null
    then buildModule.buildForMacOS "freetype" {}
    else pkgs.freetype;
in
pkgs.stdenv.mkDerivation {
  pname = "foot";
  version = "1.18.1";
  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    scdoc
    wayland-scanner
    python3
  ];

  buildInputs = [
    libwayland
    pixman
    xkbcommon
    fcft
    tllist
    utf8proc
    fontconfig
    freetype
  ];

  mesonFlags = [
    "-Ddocs=disabled"
    "-Dthemes=false"
    "-Dime=false"
    "-Dterminfo=disabled"
    "-Dtests=false"
    # Disable grapheme/run shaping that requires harfbuzz
    "-Dgrapheme-shaping=disabled" 
    "-Drun-shaping=disabled"
  ];

  postPatch = ''
    # Patch for macOS compatibility
    # foot uses Linux-specific APIs that need adaptation
    
    # Create a config.h if needed
    if [ ! -f config.h ]; then
      touch config.h
    fi
  '';

  # Environment setup for Wayland
  postInstall = ''
    # Create wrapper script that sets up Wayland environment
    mv $out/bin/foot $out/bin/.foot-wrapped
    cat > $out/bin/foot << 'EOF'
#!/bin/sh
# Foot terminal wrapper for Wawona
export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-0}
export XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}
exec "$(dirname "$0")/.foot-wrapped" "$@"
EOF
    chmod +x $out/bin/foot
    
    # Create .desktop file for launcher
    mkdir -p $out/share/applications
    cat > $out/share/applications/foot.desktop << 'EOF'
[Desktop Entry]
Name=Foot Terminal
Comment=Fast, lightweight Wayland terminal
Exec=foot
Icon=foot
Type=Application
Categories=System;TerminalEmulator;
Terminal=false
EOF

    # Create app metadata for Wawona launcher
    mkdir -p $out/share/wawona
    cat > $out/share/wawona/app.json << 'EOF'
{
  "id": "org.codeberg.dnkl.foot",
  "name": "Foot Terminal",
  "description": "Fast, lightweight Wayland terminal emulator",
  "version": "1.18.1",
  "icon": "foot.png",
  "executable": "foot",
  "categories": ["Terminal", "System"]
}
EOF
  '';

  meta = with lib; {
    description = "Fast, lightweight and minimalistic Wayland terminal emulator";
    homepage = "https://codeberg.org/dnkl/foot";
    license = licenses.mit;
    platforms = platforms.darwin;
    mainProgram = "foot";
  };
}

