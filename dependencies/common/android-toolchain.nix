{ lib, pkgs }:

let
  # Android API level and target
  androidApiLevel = 35;
  androidTarget = "aarch64-linux-android${toString androidApiLevel}";
  androidndkPkgsMacOS = if pkgs.stdenv.isAarch64 && pkgs.stdenv.isDarwin then
    let
      ndkVersion = "27.0.12077987";
      hostTag = if pkgs.stdenv.isAarch64 then "darwin-x86_64" else "darwin-x86_64";
      ndkRoot = pkgs.stdenv.mkDerivation {
        name = "android-ndk-${ndkVersion}";
        src = pkgs.fetchzip {
          url = "https://dl.google.com/android/repository/android-ndk-r27c-darwin.zip";
          sha256 = "sha256-Z4221PHrnFk7VFrs8t9qSn6X6LoIiYMJL08XQ7p+ylA=";
        };
        installPhase = ''
          mkdir -p $out
          if [ -d android-ndk-r27c ]; then
            cp -r android-ndk-r27c/* $out/
          else
            cp -r * $out/
          fi
        '';
      };
      toolchainBase = "${ndkRoot}/toolchains/llvm/prebuilt/${hostTag}";
    in
    {
      inherit ndkRoot toolchainBase;
    }
  else
    null;
  androidndkPkgs = if pkgs.stdenv.isAarch64 && pkgs.stdenv.isDarwin then
    {
      clang = androidndkPkgsMacOS.toolchainBase;
      binutils = androidndkPkgsMacOS.toolchainBase;
    }
  else
    pkgs.androidndkPkgs;
in
{
  inherit androidApiLevel androidTarget;
  androidCC = "${androidndkPkgs.clang}/bin/clang";
  androidCXX = "${androidndkPkgs.clang}/bin/clang++";
  androidAR = "${androidndkPkgs.binutils}/bin/llvm-ar";
  androidSTRIP = "${androidndkPkgs.binutils}/bin/llvm-strip";
  androidRANLIB = "${androidndkPkgs.binutils}/bin/llvm-ranlib";
  androidndkRoot = if pkgs.stdenv.isAarch64 && pkgs.stdenv.isDarwin then
    androidndkPkgsMacOS.ndkRoot
  else
    lib.removeSuffix "/bin/clang" (toString androidndkPkgs.clang) + "/..";
}
