{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  fetchSource = common.fetchSource;
  # Pin to a specific commit for reproducible builds
  # Using branch = "main" is not reproducible as it changes over time
  mesaSource = {
    source = "gitlab";
    owner = "mesa";
    repo = "mesa";
    rev = "9994db58b3afe385724cfb3562b9fc0a7fb82723";
    sha256 = "sha256-lgsYsJNepGTEWDPmD7H6teijULlxyPl9akcDXvSAU60=";
  };
  src = fetchSource mesaSource;
  buildFlags = [
    "-Dvulkan-drivers=kosmickrisp"
    "-Dgallium-drivers="
    "-Dplatforms="
    "-Dglx=disabled"
    "-Degl=disabled"
    "-Dgbm=disabled"
    "-Dtools="
    "-Dvulkan-beta=true"
    "-Dbuildtype=release"
    "-Dglvnd=disabled"
    "-Dgallium-va=disabled"
  ];
  patches = [ ];
  getDeps =
    depNames:
    map (
      depName:
      if depName == "zlib" then
        pkgs.zlib
      else if depName == "zstd" then
        pkgs.zstd
      else if depName == "expat" then
        pkgs.expat
      else if depName == "llvm" then
        pkgs.llvmPackages.llvm
      else if depName == "clang" then
        pkgs.llvmPackages.clang-unwrapped.lib # Clang libraries
      else if depName == "clang-dev" then
        pkgs.llvmPackages.clang-unwrapped.dev # Clang headers
      else if depName == "spirv-llvm-translator" then
        pkgs.spirv-llvm-translator
      else if depName == "spirv-tools" then
        pkgs.spirv-tools
      else if depName == "spirv-headers" then
        pkgs.spirv-headers
      else if depName == "libclc" then
        pkgs.libclc
      # Lua is optional - only needed for Freedreno tools, not kosmickrisp
      # else if depName == "lua" then pkgs.lua5_4
      else
        throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [
    "zlib"
    "zstd"
    "expat"
    "llvm"
    "clang"
    "clang-dev"
    "spirv-llvm-translator"
    "spirv-tools"
    "spirv-headers"
    "libclc"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "kosmickrisp-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    (python3.withPackages (
      ps: with ps; [
        setuptools
        pip
        packaging
        mako
        pyyaml
      ]
    ))
    bison
    flex
    pkgs.apple-sdk_26 # macOS SDK 26+
  ];
  # Metal frameworks are linked via -framework flags, not as buildInputs
  # Mesa's meson.build will find them via pkg-config or direct linking
  buildInputs = depInputs;
  postPatch = ''
        echo "=== Patching Mesa meson.build for Clang library detection ==="
        # Fix Clang library detection: Mesa expects Clang libraries in LLVM libdir
        # but in Nixpkgs, Clang libraries are in a separate package (clang-unwrapped.lib)
        # Write patch lines to a temp file to avoid Nix string escaping issues
        # Use $TMPDIR instead of /tmp for Nix sandbox compatibility
        CLANG_PATCH_FILE="$TMPDIR/clang_patch.txt"
        cat > "$CLANG_PATCH_FILE" <<ENDPATCH
      # Try multiple locations for Clang libraries
      # On some systems (like Nix), Clang libraries may be in a separate location
      clang_libdirs = [llvm_libdir]
      # Also check common alternative locations
      clang_libdirs += [join_paths(llvm_libdir, '..', 'clang', 'lib')]
      # In Nixpkgs, Clang libraries are in clang-unwrapped.lib, not LLVM libdir
      clang_libdirs += ['${pkgs.llvmPackages.clang-unwrapped.lib}/lib']
    ENDPATCH
        
        # Insert after llvm_libdir line
        sed -i '/llvm_libdir = dep_llvm.get_variable/r '"$CLANG_PATCH_FILE" meson.build
        
        # Replace dep_clang line to use clang_libdirs instead of llvm_libdir
        substituteInPlace meson.build \
          --replace \
          "dep_clang = cpp.find_library('clang-cpp', dirs : llvm_libdir, required : false)" \
          "dep_clang = cpp.find_library('clang-cpp', dirs : clang_libdirs, required : false)"
        
        # Replace the foreach loop to use clang_libdirs instead of llvm_libdir
        substituteInPlace meson.build \
          --replace \
          "dep_clang += cpp.find_library(m, dirs : llvm_libdir, required : true)" \
          "dep_clang += cpp.find_library(m, dirs : clang_libdirs, required : true)"
        
        echo "Applied Clang library detection patch"
        echo "Verifying patch was applied:"
        grep -A 7 "clang_libdirs = \[llvm_libdir\]" meson.build || echo "WARNING: Patch may not have been applied correctly"
  '';
  configurePhase = ''
    runHook preConfigure
    # Ensure we build as .dylib (shared library) for macOS
    # Use latest macOS SDK (26+)
    MACOS_SDK="${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    MACOS_VERSION_MIN="26.0"

    # Link Metal frameworks and LLVM/Clang libraries explicitly
    # Dependencies (zlib, zstd, expat) are in buildInputs, so Meson will find them automatically
    # But we can add explicit library paths to ensure proper linking
    LLVM_LIBDIR="${pkgs.llvmPackages.llvm.lib}/lib"
    export LDFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=$MACOS_VERSION_MIN -framework Metal -framework MetalKit -framework Foundation -framework IOKit -L$LLVM_LIBDIR"
    # Clang headers are available via buildInputs (clang-unwrapped.dev)
    export CPPFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=$MACOS_VERSION_MIN -I${pkgs.llvmPackages.llvm.dev}/include"
    export CFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=$MACOS_VERSION_MIN"
    export CXXFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=$MACOS_VERSION_MIN"

    # Set PKG_CONFIG_PATH for SPIRV dependencies and LLVM
    # zlib, zstd, expat are in buildInputs and Meson will find them automatically
    # Lua is optional and not needed for kosmickrisp
    export PKG_CONFIG_PATH="${pkgs.spirv-llvm-translator}/lib/pkgconfig:${pkgs.spirv-tools}/lib/pkgconfig:${pkgs.spirv-headers}/lib/pkgconfig:${pkgs.llvmPackages.llvm.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    # Ensure llvm-config is in PATH (Mesa uses this to get LLVM_LIBRARY_DIR)
    export PATH="${pkgs.llvmPackages.llvm.dev}/bin:''${PATH}"

    # Set SDKROOT for Meson to find Metal frameworks
    export SDKROOT="$MACOS_SDK"

    # Our patch allows specifying clang-libdir via meson option if needed
    # For now, let Mesa search in LLVM libdir (our patch makes it more flexible)
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --default-library=shared \
      ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    meson install -C build

    # Ensure ICD JSON manifest exists for the Vulkan loader
    mkdir -p $out/share/vulkan/icd.d
    if [ ! -f $out/share/vulkan/icd.d/kosmickrisp_icd.json ] && \
       [ ! -f $out/share/vulkan/icd.d/kosmickrisp_icd.*.json ]; then
      # Mesa did not generate a manifest — create one manually
      # Find the actual .dylib name (may be libvulkan_kosmickrisp.dylib or similar)
      VK_LIB=$(find $out/lib -name "libvulkan_kosmickrisp*.dylib" -o -name "libVkICD_kosmickrisp*.dylib" | head -1)
      if [ -z "$VK_LIB" ]; then
        VK_LIB=$(find $out/lib -name "*.dylib" | head -1)
      fi
      if [ -n "$VK_LIB" ]; then
        cat > $out/share/vulkan/icd.d/kosmickrisp_icd.json <<ICDJSON
    {
        "file_format_version": "1.0.1",
        "ICD": {
            "library_path": "$VK_LIB",
            "api_version": "1.3.0",
            "is_portability_driver": true
        }
    }
    ICDJSON
        echo "Generated ICD manifest pointing to $VK_LIB"
      else
        echo "WARNING: No kosmickrisp .dylib found in $out/lib — ICD manifest not created"
      fi
    else
      echo "Mesa-generated ICD manifest found"
      # Patch library_path to use absolute nix store path
      for f in $out/share/vulkan/icd.d/*.json; do
        sed -i "s|\"library_path\": \"\.\./\.\./|\"library_path\": \"$out/|g" "$f"
        sed -i "s|\"library_path\": \"lib/|\"library_path\": \"$out/lib/|g" "$f"
      done
    fi

    runHook postInstall
  '';
}
