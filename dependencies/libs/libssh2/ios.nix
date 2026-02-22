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
  # libssh2 source
  src = pkgs.fetchFromGitHub {
    owner = "libssh2";
    repo = "libssh2";
    rev = "libssh2-1.11.1";
    sha256 = "sha256-yz97oqqN+NJTDL/HPJe3niFynbR8QXHuuiKr+uuKJtw=";
  };
  # Use OpenSSL instead of mbedTLS: mbedTLS bundled entropy source lacks iOS
  # support (NULL callback → crash in mbedtls_ctr_drbg_reseed_internal during
  # SSH handshake). OpenSSL uses SecRandomCopyBytes on iOS which works correctly.
  openssl-ios = buildModule.buildForIOS "openssl" { inherit simulator; };
in
pkgs.stdenv.mkDerivation {
  name = "libssh2-ios";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
  ];
  buildInputs = [ openssl-ios ];
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
    "-DCRYPTO_BACKEND=OpenSSL"
    "-DENABLE_ZLIB_COMPRESSION=ON"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DBUILD_EXAMPLES=OFF"
    "-DBUILD_TESTING=OFF"
    "-DOPENSSL_ROOT_DIR=${openssl-ios}"
    "-DOPENSSL_CRYPTO_LIBRARY=${openssl-ios}/lib/libcrypto.a"
    "-DOPENSSL_SSL_LIBRARY=${openssl-ios}/lib/libssl.a"
    "-DOPENSSL_INCLUDE_DIR=${openssl-ios}/include"
  ];
}
