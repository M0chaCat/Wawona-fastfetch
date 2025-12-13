{
  pkgs ? import <nixpkgs> { },
}:
pkgs.runCommand "inspect-clang-out"
  {
    buildInputs = [
      pkgs.llvmPackages.clang-unwrapped
      pkgs.llvmPackages.clang-unwrapped.lib
      pkgs.llvmPackages.clang-unwrapped.dev
      pkgs.llvmPackages.libclang
      pkgs.llvmPackages.llvm
    ];
  }
  ''
    echo "Searching for libclangBasic..." > $out

    echo "--- clang-unwrapped.dev ---" >> $out
    find ${pkgs.llvmPackages.clang-unwrapped.dev} -name "*clangBasic*" >> $out || true
    find ${pkgs.llvmPackages.clang-unwrapped.dev} -name "*cmake*" >> $out || true

    echo "--- clang-unwrapped.lib ---" >> $out
    find ${pkgs.llvmPackages.clang-unwrapped} -name "*clangBasic*" >> $out || true

    echo "--- clang-unwrapped.lib ---" >> $out
    find ${pkgs.llvmPackages.clang-unwrapped.lib} -name "*clangBasic*" >> $out || true

    echo "--- libclang ---" >> $out
    find ${pkgs.llvmPackages.libclang} -name "*clangBasic*" >> $out || true

    echo "--- llvm ---" >> $out
    find ${pkgs.llvmPackages.llvm} -name "*clangBasic*" >> $out || true

    echo "Done searching." >> $out
  ''
