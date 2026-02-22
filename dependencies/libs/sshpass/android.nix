{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
}:

let
  androidToolchain = import ../../toolchains/android.nix { inherit lib pkgs; };
  NDK_SYSROOT = "${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt/darwin-x86_64/sysroot";
in
pkgs.stdenv.mkDerivation {
  name = "sshpass-android";
  version = "1.10";

  src = pkgs.fetchurl {
    url = "https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz";
    sha256 = "sha256-rREGwgPLtWGFyjutjGzK/KO0BkaWGU2oefgcjXvf7to=";
  };

  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
  ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export AR="${androidToolchain.androidAR}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${NDK_SYSROOT} -fPIC -static"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${NDK_SYSROOT} -static"
  '';

  configurePhase = ''
    runHook preConfigure
    ac_cv_func_malloc_0_nonnull=yes \
    ./configure \
      --prefix=$out \
      --host=aarch64-linux-android
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp sshpass $out/bin/sshpass
    chmod +x $out/bin/sshpass
    runHook postInstall
  '';

  dontFixup = true;
  __noChroot = true;
}
