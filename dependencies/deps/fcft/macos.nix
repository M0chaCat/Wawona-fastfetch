# fcft - Font loading and glyph rasterization library (used by foot terminal)
# https://codeberg.org/dnkl/fcft
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  fcftSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "fcft";
    tag = "3.1.8";
    sha256 = "sha256-bkZKmozGSzH/eJe5E7koLVPWmqSqU22xEBPy8vLvyqU=";
  };
  src = fetchSource fcftSource;
  
  # Dependencies
  freetype = if buildModule != null 
    then buildModule.buildForMacOS "freetype" {} 
    else pkgs.freetype;
  fontconfig = if buildModule != null
    then buildModule.buildForMacOS "fontconfig" {}
    else pkgs.fontconfig;
  pixman = if buildModule != null
    then buildModule.buildForMacOS "pixman" {}
    else pkgs.pixman;
  tllist = if buildModule != null
    then buildModule.buildForMacOS "tllist" {}
    else pkgs.tllist or (throw "tllist not available");
  utf8proc = if buildModule != null
    then buildModule.buildForMacOS "utf8proc" {}
    else pkgs.utf8proc;
in
pkgs.stdenv.mkDerivation {
  pname = "fcft";
  version = "3.1.8";
  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    scdoc
  ];

  buildInputs = [
    freetype
    fontconfig
    pixman
    tllist
    utf8proc
  ];

  mesonFlags = [
    "-Ddocs=disabled"
    "-Dtest-text-shaping=false"
    "-Dgrapheme-shaping=disabled"
    "-Drun-shaping=disabled"
  ];

  meta = with lib; {
    description = "Simple library for font loading and glyph rasterization";
    homepage = "https://codeberg.org/dnkl/fcft";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}

