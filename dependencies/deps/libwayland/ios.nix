{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  waylandSource = {
    source = "gitlab";
    owner = "wayland";
    repo = "wayland";
    tag = "1.23.0";
    sha256 = "sha256-oK0Z8xO2ILuySGZS0m37ZF0MOyle2l8AXb0/6wai0/w=";
  };
  src = fetchSource waylandSource;
  # We need to build libraries for the target
  buildFlags = [ "-Dlibraries=true" "-Ddocumentation=false" "-Dtests=false" ];
  patches = [];
  getDeps = depNames:
    map (depName:
      if depName == "expat" then buildModule.buildForIOS "expat" {}
      else if depName == "libffi" then buildModule.buildForIOS "libffi" {}
      else if depName == "libxml2" then buildModule.buildForIOS "libxml2" {}
      else throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [ "expat" "libffi" "libxml2" ];
  # epoll-shim: Required for iOS Wayland builds (implements epoll on top of kqueue)
  epollShim = buildModule.buildForIOS "epoll-shim" {};

  # Build wayland-scanner for the build architecture (host)
  waylandScanner = pkgs.stdenv.mkDerivation {
    name = "wayland-scanner-host";
    inherit src;
    nativeBuildInputs = with pkgs; [ meson ninja pkg-config expat libxml2 ];
    configurePhase = ''
      meson setup build \
        --prefix=$out \
        -Dlibraries=false \
        -Ddocumentation=false \
        -Dtests=false
    '';
    buildPhase = ''
      meson compile -C build wayland-scanner
    '';
    installPhase = ''
      mkdir -p $out/bin
      SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
      if [ -z "$SCANNER_BIN" ]; then
        echo "Error: wayland-scanner binary not found"
        exit 1
      fi
      cp "$SCANNER_BIN" $out/bin/wayland-scanner
      
      mkdir -p $out/share/pkgconfig
      cat > $out/share/pkgconfig/wayland-scanner.pc <<EOF
prefix=$out
exec_prefix=$out
bindir=$out/bin
datarootdir=$out/share
pkgdatadir=$out/share/wayland

Name: Wayland Scanner
Description: Wayland scanner
Version: 1.23.0
variable=wayland_scanner
wayland_scanner=$out/bin/wayland-scanner
EOF
    '';
  };
in
pkgs.stdenv.mkDerivation {
  name = "libwayland-ios";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
    bison flex
    waylandScanner
  ];
  buildInputs = depInputs ++ [ epollShim ];
  
  postPatch = ''
    # iOS syscall compatibility
    echo "=== Applying iOS syscall compatibility patches ==="
    
    # Fix missing socket defines on iOS/Darwin (CMSG_LEN, MSG_NOSIGNAL, MSG_DONTWAIT)
    sed -i '1i\
#ifndef MSG_NOSIGNAL\
#define MSG_NOSIGNAL 0\
#endif\
#ifndef MSG_DONTWAIT\
#define MSG_DONTWAIT 0x80\
#endif\
#include <sys/socket.h>\
#ifndef AF_LOCAL\
#define AF_LOCAL AF_UNIX\
#endif\
#ifndef CMSG_LEN\
#define CMSG_LEN(len) (CMSG_DATA((struct cmsghdr *)0) - (unsigned char *)0 + (len))\
#endif\
' src/connection.c

    # Fix AF_LOCAL in wayland-client.c
    sed -i '1i\
#include <sys/socket.h>\
#ifndef AF_LOCAL\
#define AF_LOCAL AF_UNIX\
#endif\
' src/wayland-client.c

    # Fix wayland-os.c for Darwin (SOCK_CLOEXEC, MSG_CMSG_CLOEXEC, ucred)
    sed -i '1i\
#ifndef SOCK_CLOEXEC\
#define SOCK_CLOEXEC 0\
#endif\
#ifndef MSG_CMSG_CLOEXEC\
#define MSG_CMSG_CLOEXEC 0\
#endif\
' src/wayland-os.c

    # Patch ucred error in wayland-os.c to support Darwin via stub
    # The #error guards the function definition, so we must provide the function definition
    # Also provide wl_os_socket_peercred which seems to be used by wayland-server.c
    sed -i '/#error "Don.t know how to read ucred/c\
int wl_os_get_peer_credentials(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
{\
        *uid = 0; *gid = 0; *pid = 0; return 0;\
}\
int wl_os_socket_peercred(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
{\
        return wl_os_get_peer_credentials(sockfd, uid, gid, pid);\
}' src/wayland-os.c

    # Fix missing struct itimerspec on Darwin (needed by event-loop.c)
    sed -i '1i\
#if defined(__APPLE__)\
#include <time.h>\
struct itimerspec {\
    struct timespec it_interval;\
    struct timespec it_value;\
};\
#endif\
' src/event-loop.c

    # Fix mkostemp in os-compatibility.c
    sed -i 's/mkostemp(tmpname, O_CLOEXEC)/mkstemp(tmpname)/' cursor/os-compatibility.c
    
    echo "Applied iOS syscall compatibility patches"
  '';

  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
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
    
    EPOL_SHIM_PATH="${epollShim}"
    
    export CFLAGS="-D_DARWIN_C_SOURCE -I$EPOL_SHIM_PATH/include/libepoll-shim -I$EPOL_SHIM_PATH/include ''${NIX_CFLAGS_COMPILE:-}"
    export LDFLAGS="-L$EPOL_SHIM_PATH/lib -lepoll-shim ''${NIX_LDFLAGS:-}"
    export PKG_CONFIG_PATH="$EPOL_SHIM_PATH/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
    
    cat > ios-cross-file.txt <<EOF
[binaries]
c = '$IOS_CC'
cpp = '$IOS_CXX'
ar = 'ar'
strip = 'strip'
pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$EPOL_SHIM_PATH/include/libepoll-shim', '-I$EPOL_SHIM_PATH/include']
cpp_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$EPOL_SHIM_PATH/include/libepoll-shim', '-I$EPOL_SHIM_PATH/include']
c_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-L$EPOL_SHIM_PATH/lib', '-lepoll-shim']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-L$EPOL_SHIM_PATH/lib', '-lepoll-shim']
EOF
  '';

  configurePhase = ''
    runHook preConfigure
    echo "Configured epoll-shim paths for iOS: $EPOL_SHIM_PATH"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=ios-cross-file.txt \
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
    runHook postInstall
  '';
}
