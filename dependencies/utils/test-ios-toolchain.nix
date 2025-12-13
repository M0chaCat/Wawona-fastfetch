{
  lib,
  pkgs,
  buildPackages,
}:

let
  sdk = "${pkgs.apple-sdk_26}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk";
in
pkgs.stdenv.mkDerivation {
  name = "test-ios-toolchain";
  unpackPhase = "true";
  buildPhase = ''
    cat > test.c <<EOF
    int main() { return 0; }
    EOF

    echo "Testing iOS compilation..."
    ${pkgs.clang}/bin/clang \
      -arch arm64 \
      -isysroot ${sdk} \
      -miphoneos-version-min=26.0 \
      -fembed-bitcode \
      -std=c11 \
      test.c -o test
      
    echo "Checking file type..."
    file test
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp test $out/bin/
  '';
}
