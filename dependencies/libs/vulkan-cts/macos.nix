{
  lib,
  pkgs,
  common ? null,
  buildModule ? null,
  kosmickrisp ? null,
}:

let
  sources = import ./sources.nix {
    inherit (pkgs) fetchurl fetchFromGitHub;
  };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "vulkan-cts-macos";
  version = "1.4.5.0";

  src = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "VK-GL-CTS";
    rev = "vulkan-cts-${finalAttrs.version}";
    hash = "sha256-cbXSelRPCCH52xczWaxqftbimHe4PyIKZqySQSFTHos=";
  };

  prePatch = ''
    ${sources.prePatch}
  '';

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    python3
    makeWrapper
  ];

  buildInputs = with pkgs; [
    ffmpeg
    libffi
    libpng
    vulkan-headers
    vulkan-loader
    vulkan-utility-libraries
    zlib
    apple-sdk_26
  ];

  depsBuildBuild = with pkgs; [
    pkg-config
  ];

  cmakeFlags = [
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DDEQP_TARGET=osx"
    "-DSELECTED_BUILD_TARGETS=deqp-vk"
    (lib.cmakeFeature "DGLSLANG_INSTALL_DIR" "${pkgs.glslang}")
    (lib.cmakeFeature "DSPIRV_HEADERS_INSTALL_DIR" "${pkgs.spirv-headers}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${sources.shaderc-src}")
  ];

  postInstall = ''
    test ! -e $out

    mkdir -p $out/bin $out/archive-dir
    cp -a external/vulkancts/modules/vulkan/deqp-vk $out/bin/
    cp -a external/vulkancts/modules/vulkan/vulkan $out/archive-dir/
    cp -a external/vulkancts/modules/vulkan/vk-default $out/
  '';

  postFixup = let
    vulkanLoader = pkgs.vulkan-loader;
    icdPath = if kosmickrisp != null
      then "${kosmickrisp}/share/vulkan/icd.d/kosmickrisp_icd.json"
      else "";
  in ''
    install_name_tool -add_rpath "${vulkanLoader}/lib" $out/bin/deqp-vk || true
    wrapProgram $out/bin/deqp-vk \
      --add-flags "--deqp-archive-dir=$out/archive-dir" \
      ${lib.optionalString (kosmickrisp != null) ''--set VK_DRIVER_FILES "${icdPath}"''}
  '';

  meta = {
    description = "Khronos Vulkan Conformance Tests (macOS)";
    homepage = "https://github.com/KhronosGroup/VK-GL-CTS";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin;
  };
})
