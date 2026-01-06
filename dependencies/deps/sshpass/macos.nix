{
  lib,
  pkgs,
  common,
}:

let
  # sshpass source - fetch from SourceForge mirror via GitHub
  src = pkgs.fetchurl {
    url = "https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz";
    sha256 = "sha256-rREGwgPLtWGFyjutjGzK/KO0BkaWGU2oefgcjXvf7to=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "sshpass-macos";
  version = "1.10";
  
  inherit src;
  
  # No patches needed for sshpass
  patches = [ ];
  
  nativeBuildInputs = with pkgs; [
    autoconf
    automake
  ];
  
  buildInputs = [ ];

  MACOS_SDK = "${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  
  preConfigure = ''
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
  '';

  configureFlags = [
    "--prefix=${placeholder "out"}"
  ];

  NIX_CFLAGS_COMPILE = "-mmacosx-version-min=26.0";
  NIX_LDFLAGS = "";

  meta = with lib; {
    description = "Non-interactive SSH password authentication";
    homepage = "https://sourceforge.net/projects/sshpass/";
    license = licenses.gpl2Plus;
    platforms = platforms.darwin;
  };
}

