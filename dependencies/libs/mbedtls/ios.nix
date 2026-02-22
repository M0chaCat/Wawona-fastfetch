{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # mbedtls source - fetch from GitHub with submodules
  src = pkgs.fetchFromGitHub {
    owner = "Mbed-TLS";
    repo = "mbedtls";
    rev = "v3.6.0";
    sha256 = "sha256-tCwAKoTvY8VCjcTPNwS3DeitflhpKHLr6ygHZDbR6wQ=";
    fetchSubmodules = true;
  };
in
pkgs.stdenv.mkDerivation {
  name = "mbedtls-ios";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    perl
  ];
  buildInputs = [ ];
  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.platform/Developer/SDKs/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.sdk"
      fi
    fi
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    
    IOS_ARCH="arm64"
    
    cat > ios-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
set(CMAKE_C_COMPILER "$IOS_CC")
set(CMAKE_CXX_COMPILER "$IOS_CXX")
set(CMAKE_SYSROOT "$SDKROOT")
set(CMAKE_OSX_SYSROOT "$SDKROOT")
set(CMAKE_C_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC")
set(CMAKE_CXX_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC")
set(BUILD_SHARED_LIBS OFF)
EOF
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DENABLE_PROGRAMS=OFF"
    "-DENABLE_TESTING=OFF"
    "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF"
    "-DUSE_STATIC_MBEDTLS_LIBRARY=ON"
  ];
}
