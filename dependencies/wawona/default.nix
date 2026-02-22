{ lib, pkgs, buildModule, wawonaSrc, wawonaVersion, rustBackendMacOS ? null, rustBackendIOS ? null, rustBackendIOSSim ? null, rustBackendAndroid ? null, weston ? null, waypipe ? null, androidSDK ? null, androidSrc ? null, ... }:

# Central entry point for Wawona applications.
# Returns: { ios, macos, android, common, generators }

let
  # Dependency version strings (must match the tags/versions in dependencies/libs/*)
  depVersions = {
    waylandVersion   = "1.23.0";       # dependencies/libs/libwayland/macos.nix  tag
    xkbcommonVersion = "1.7.0";        # dependencies/libs/xkbcommon/macos.nix   tag
    lz4Version       = "1.10.0";       # dependencies/libs/lz4/macos.nix         rev
    zstdVersion      = "1.5.7";        # dependencies/libs/zstd/macos.nix        rev
    libffiVersion    = "3.5.2";        # dependencies/libs/libffi/macos.nix      tag
    sshpassVersion   = "1.10";         # dependencies/libs/sshpass/macos.nix     version
    waypipeVersion   = "0.10.6";       # dependencies/libs/waypipe/macos.nix     tag
  };

  apps = {
    ios = pkgs.callPackage ./ios.nix {
      inherit buildModule wawonaSrc wawonaVersion;
      rustBackend = rustBackendIOS;
      rustBackendSim = rustBackendIOSSim;
    };

    macos = pkgs.callPackage ./macos.nix ({
      inherit buildModule wawonaSrc wawonaVersion weston waypipe;
      rustBackend = rustBackendMacOS;
    } // depVersions);

    android = pkgs.callPackage ./android.nix {
      inherit buildModule wawonaVersion androidSDK;
      wawonaSrc = if androidSrc != null then androidSrc else wawonaSrc;
      rustBackend = rustBackendAndroid;
    };

    common = import ./common.nix {
      inherit lib pkgs wawonaSrc;
    };

    generators = {
      xcodegen = pkgs.callPackage ../generators/xcodegen.nix {
         inherit wawonaVersion rustBackendIOS rustBackendIOSSim rustBackendMacOS;
         rustPlatform = pkgs.rustPlatform;
      };
      gradlegen = pkgs.callPackage ../generators/gradlegen.nix {
        wawonaAndroidProject = apps.android.project or null;
        inherit wawonaSrc;
      };
    };
  };
in
  apps
