# FreeType - Font rendering library
# https://freetype.org/
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  freetypeSource = {
    source = "savannah";
    project = "freetype";
    repo = "freetype2";
    tag = "VER-2-13-2";
    sha256 = "sha256-EEQ/SJpXqVbJa+nZhxBXp3C1pT6pXr6JGKU0W/eOjX4=";
  };
in
pkgs.stdenv.mkDerivation rec {
  pname = "freetype";
  version = "2.13.2";

  src = pkgs.fetchurl {
    url = "https://download.savannah.gnu.org/releases/freetype/freetype-${version}.tar.xz";
    sha256 = "sha256-EEQ/SJpXqVbJa+nZhxBXp3C1pT6pXr6JGKU0W/eOjX4=";
  };

  nativeBuildInputs = with pkgs; [
    pkg-config
    meson
    ninja
  ];

  buildInputs = with pkgs; [
    zlib
    bzip2
    libpng
  ];

  mesonFlags = [
    "-Dbrotli=disabled"
    "-Dharfbuzz=disabled"
    "-Dtests=disabled"
  ];

  meta = with lib; {
    description = "A font rendering library";
    homepage = "https://freetype.org/";
    license = licenses.ftl;
    platforms = platforms.darwin;
  };
}

