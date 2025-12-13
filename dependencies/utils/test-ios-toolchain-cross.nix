{
  lib,
  pkgs,
  buildPackages,
}:

let
  # Try to use the cross-compiled stdenv for iPhone
  # This should provide a compiler configured for iOS
  crossPkgs = pkgs.pkgsCross.iphone64;
  cc = crossPkgs.stdenv.cc;
in
pkgs.stdenv.mkDerivation {
  name = "test-ios-toolchain-cross";
  unpackPhase = "true";
  nativeBuildInputs = [ cc ];

  buildPhase = ''
    cat > test.c <<EOF
    int main() { return 0; }
    EOF

    echo "Testing iOS compilation with pkgsCross.iphone64..."

    # The cross compiler should be available as $CC or via the wrapper
    echo "CC is: $CC"

    $CC test.c -o test
      
    echo "Checking file type..."
    file test
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp test $out/bin/
  '';
}
