{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # SPIRV-LLVM-Translator source - same as ios.nix
  src = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-LLVM-Translator";
    rev = "v21.1.0";
    sha256 = "sha256-kk8BbPl/UBW1gaO/cuOQ9OsiNTEk0TkvRDLKUAh6exk=";
  };
  spirvToolsMacOS = buildModule.buildForMacOS "spirv-tools" { };
in
pkgs.stdenv.mkDerivation {
  name = "spirv-llvm-translator-macos";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    ninja
  ];
  buildInputs = [
    pkgs.llvmPackages.llvm.dev
    spirvToolsMacOS
  ];

  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        
        # Use Apple Clang to avoid Nix libc++ / SDK header conflicts
        export CC="$XCODE_APP/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        export CXX="$XCODE_APP/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      fi
    fi

    # Symlink SPIRV-Headers to expected location to bypass download/lookup issues
    mkdir -p build/SPIRV-Headers
    ln -s ${pkgs.spirv-headers.src}/include build/SPIRV-Headers/include
  '';

  configurePhase = ''
    runHook preConfigure

    cmake . -B build -GNinja \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_OSX_SYSROOT="$SDKROOT" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="26.0" \
      -DLLVM_DIR=${pkgs.llvmPackages.llvm.dev}/lib/cmake/llvm \
      -DSPIRV-Headers_SOURCE_DIR=${pkgs.spirv-headers.src} \
      -DSPIRV_HEADERS_SOURCE_DIR=${pkgs.spirv-headers.src} \
      -DFETCHCONTENT_SOURCE_DIR_SPIRV-HEADERS=${pkgs.spirv-headers.src} \
      -DSPIRV_HEADERS_INCLUDE_DIR=${pkgs.spirv-headers.src}/include \
      -DSPIRV_INCLUDE_DIR=${pkgs.spirv-headers.src}/include \
      -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_CXX_COMPILER="$CXX"
      
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build
    runHook postInstall
  '';
}
