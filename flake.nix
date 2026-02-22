{
  description = "Wawona Compositor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    hiahkernel.url = "github:aspauldingcode/HIAHKernel";

    crate2nix.url = "github:nix-community/crate2nix";
  };

  outputs = { self, nixpkgs, rust-overlay, hiahkernel, crate2nix }:
  let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [
          (import rust-overlay)
          (self: super: {
            rustToolchain = super.rust-bin.stable.latest.default.override {
              targets = [ "aarch64-apple-ios" "aarch64-apple-ios-sim" "aarch64-linux-android" ];
            };
            rustPlatform = super.makeRustPlatform {
              cargo = self.rustToolchain;
              rustc = self.rustToolchain;
            };
          })
        ];

        config = {
          allowUnfree = true;
          allowUnsupportedSystem = true;
          android_sdk.accept_license = true;
        };
      };

    srcFor = pkgs:
      pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let 
            name = builtins.baseNameOf path;
            relPath = pkgs.lib.removePrefix (toString ./.) (toString path);
            ext = pkgs.lib.last (pkgs.lib.splitString "." name);
          in 
            # Exclude obvious non-build directories
            !(name == ".git" || name == "result" || name == ".direnv" || name == "target" || 
              name == ".gemini" || name == "Inspiration" || name == ".idea" || name == ".vscode" ||
              name == ".DS_Store") &&
            # Include only what Cargo actually needs:
            #   - Cargo.toml, Cargo.lock, VERSION, build.rs (top-level build files)
            #   - src/          (Rust source code)
            #   - protocols/    (Wayland protocol XML for wayland-scanner)
            #   - scripts/      (build helper scripts referenced by build.rs)
            #   - include/      (C headers if any)
            # EXCLUDED: dependencies/ (Nix modules, .nix/.sh — injected separately by Nix)
            (
              name == "Cargo.toml" || name == "Cargo.lock" || name == "VERSION" || name == "build.rs" ||
              pkgs.lib.hasPrefix "/src" relPath ||
              pkgs.lib.hasPrefix "src" relPath ||
              pkgs.lib.hasPrefix "/protocols" relPath ||
              pkgs.lib.hasPrefix "/scripts" relPath ||
              pkgs.lib.hasPrefix "/include" relPath
            );
      };

    unixWrapper = pkgs: name: bin:
      pkgs.writeShellScriptBin name ''
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/tmp/$(id -u)-runtime}"
        export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
        exec ${bin} "$@"
      '';

    macosEnv = ''
      export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
      export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
      if [ ! -d "$XDG_RUNTIME_DIR" ]; then
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
      fi
    '';

    macosWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona" ''
      ${macosEnv}
      # Launch via the .app bundle so macOS picks up the icon
      exec open -W "${wawona}/Applications/Wawona.app" --args "$@"
    '';

    waypipeWrapper = pkgs: waypipe: pkgs.writeShellScriptBin "waypipe" ''
      ${macosEnv}
      # Point Vulkan loader at KosmicKrisp ICD if available and not overridden
      if [ -z "''${VK_DRIVER_FILES:-}" ]; then
        # Check app bundle first (when launched from Wawona.app)
        APP_ICD="$(dirname "$(dirname "$0")")/Resources/vulkan/icd.d/kosmickrisp_icd.json"
        if [ -f "$APP_ICD" ]; then
          export VK_DRIVER_FILES="$APP_ICD"
        fi
      fi
      exec "${waypipe}/bin/waypipe" "$@"
    '';

    footWrapper = pkgs: foot: pkgs.writeShellScriptBin "foot" ''
      ${macosEnv}
      
      # Check if user has a config
      if [ ! -f "$HOME/.config/foot/foot.ini" ] && [ ! -f "''${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini" ]; then
        echo "Info: No foot.ini found, using default macOS configuration (Menlo font)"
        DEFAULT_CONFIG="''${XDG_RUNTIME_DIR}/foot-default.ini"
        cat > "$DEFAULT_CONFIG" <<EOF
[main]
font=Menlo:size=12,Monaco:size=12,monospace:size=12
dpi-aware=yes
EOF
        exec "${foot}/bin/foot" -c "$DEFAULT_CONFIG" "$@"
      else
        exec "${foot}/bin/foot" "$@"
      fi
    '';

    westonAppWrapper = pkgs: weston: binName: pkgs.writeShellScriptBin binName ''
      ${macosEnv}
      exec "${weston}/bin/${binName}" "$@"
    '';

    iosWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona-ios" ''
      export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
      exec "${wawona}/bin/wawona-ios-simulator" "$@"
    '';

    androidWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona-android" ''
      export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
      exec "${wawona}/bin/wawona-android-run" "$@"
    '';

    linuxWrapper = pkgs: wawona: pkgs.writeShellScriptBin "wawona" ''
      export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
      exec "${wawona}/bin/wawona" "$@"
    '';


    # Calculate wawonaVersion once at the top level
    # Use a default system to get lib and src for version calculation
    defaultSystem = "x86_64-linux";
    defaultPkgs = pkgsFor defaultSystem;
    globalSrc = srcFor defaultPkgs;
    wawonaVersion = defaultPkgs.lib.removeSuffix "\n" (defaultPkgs.lib.fileContents (globalSrc + "/VERSION"));

    # Centralized waypipe source
    waypipe-src = defaultPkgs.fetchFromGitLab {
      owner = "mstoeckl";
      repo = "waypipe";
      rev = "v0.10.6";
      sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
    };

  in
  {
    packages = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
      src  = srcFor pkgs;

      # ── Pre-patched waypipe source derivations (cached separately) ──
      # Changing the patch script only invalidates these + their dependents,
      # NOT the entire Rust build.
      waypipe-patched-ios = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
        inherit waypipe-src;
        patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh;
        platform = "ios";
      };

      waypipe-patched-macos = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
        inherit waypipe-src;
        patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh;
        platform = "macos";
      };

      waypipe-patched-android = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
        inherit waypipe-src;
        patchScript = ./dependencies/libs/waypipe/patch-waypipe-android.sh;
        platform = "android";
      };

      # ── Workspace source assembly (wawona src + waypipe) ──
      # iOS device and simulator share the same workspace source (same waypipe patches).
      workspace-src-ios = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
        wawonaSrc = src;
        waypipeSrc = waypipe-patched-ios;
        platform = "ios";
        inherit wawonaVersion;
      };

      workspace-src-macos = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
        wawonaSrc = src;
        waypipeSrc = waypipe-patched-macos;
        platform = "macos";
        inherit wawonaVersion;
      };

      workspace-src-android = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
        wawonaSrc = src;
        waypipeSrc = waypipe-patched-android;
        platform = "android";
        inherit wawonaVersion;
      };

      # ── crate2nix Rust backends (per-crate caching!) ──
      backend-macos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
        inherit crate2nix wawonaVersion toolchains nixpkgs;
        workspaceSrc = workspace-src-macos;
        platform = "macos";
        nativeDeps = {
          libwayland = toolchains.macos.libwayland;
        };
      };

      backend-ios = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
        inherit crate2nix wawonaVersion toolchains nixpkgs;
        workspaceSrc = workspace-src-ios;
        platform = "ios";
        nativeDeps = {
          xkbcommon = toolchains.ios.xkbcommon;
          libffi = toolchains.ios.libffi;
          libwayland = toolchains.ios.libwayland;
          zstd = toolchains.ios.zstd;
          lz4 = toolchains.ios.lz4;
          zlib = toolchains.buildForIOS "zlib" {};
          libssh2 = toolchains.ios.libssh2;
          mbedtls = toolchains.ios.mbedtls;
          openssl = toolchains.buildForIOS "openssl" {};
          kosmickrisp = toolchains.buildForIOS "kosmickrisp" {};
          ffmpeg = toolchains.buildForIOS "ffmpeg" {};
          epoll-shim = toolchains.buildForIOS "epoll-shim" {};
        };
      };

      backend-ios-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
        inherit crate2nix wawonaVersion toolchains nixpkgs;
        workspaceSrc = workspace-src-ios;
        platform = "ios";
        simulator = true;
        nativeDeps = {
          xkbcommon = toolchains.ios.xkbcommon;
          libffi = toolchains.ios.libffi;
          libwayland = toolchains.ios.libwayland;
          zstd = toolchains.ios.zstd;
          lz4 = toolchains.ios.lz4;
          zlib = toolchains.buildForIOS "zlib" { simulator = true; };
          libssh2 = toolchains.ios.libssh2;
          mbedtls = toolchains.ios.mbedtls;
          openssl = toolchains.buildForIOS "openssl" { simulator = true; };
          kosmickrisp = toolchains.buildForIOS "kosmickrisp" { simulator = true; };
          ffmpeg = toolchains.buildForIOS "ffmpeg" { simulator = true; };
          epoll-shim = toolchains.buildForIOS "epoll-shim" { simulator = true; };
        };
      };

      backend-android = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
        inherit crate2nix wawonaVersion toolchains nixpkgs;
        workspaceSrc = workspace-src-android;
        platform = "android";
        nativeDeps = {
          xkbcommon = toolchains.android.xkbcommon;
          libwayland = toolchains.android.libwayland;
          zstd = toolchains.android.zstd;
          lz4 = toolchains.android.lz4;
          pixman = toolchains.android.pixman;
          openssl = toolchains.android.openssl;
          libffi = toolchains.android.libffi;
          expat = toolchains.android.expat;
          libxml2 = toolchains.android.libxml2;
        };
      };

      # Toolchains for cross-compilation
      toolchains = import ./dependencies/toolchains {
        inherit (pkgs) lib pkgs stdenv buildPackages;
      };

      # Wawona system module (macOS/iOS/Android)
      wawonaSrc = src;
      
      libwayland-macos = toolchains.macos.libwayland;
      
      # wawona-macos is defined via wawonaModules below


      weston = pkgs.callPackage ./dependencies/clients/weston/macos.nix {
        wayland = libwayland-macos;
        wayland-scanner = libwayland-macos;
      };

      androidSDK = pkgs.androidenv.composeAndroidPackages {
        cmdLineToolsVersion = "8.0";
        buildToolsVersions = [ "36.0.0" ];
        platformToolsVersion = "35.0.2";
        platformVersions = [ "36" ];
        abiVersions = [ "arm64-v8a" ];
        systemImageTypes = [ "google_apis_playstore" ];
        includeEmulator = true;
        emulatorVersion = "35.1.4";
        includeSystemImages = true;
        useGoogleAPIs = false;
        includeNDK = true;
        ndkVersions = ["27.0.12077973"];
      };

      # Android needs full src/ including platform C files; use cleanSource for that
      androidSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let name = builtins.baseNameOf path;
          in !(name == ".git" || name == "result" || name == ".direnv" || name == "target" ||
               name == ".gemini" || name == "Inspiration" || name == ".idea" || name == ".vscode" ||
               name == ".DS_Store");
      };

      # Central app builds and generators
      wawonaApps = pkgs.callPackage ./dependencies/wawona {
        buildModule = toolchains;
        inherit wawonaSrc wawonaVersion androidSDK weston androidSrc;
        waypipe = toolchains.macos.waypipe;
        rustBackendMacOS = backend-macos;
        rustBackendIOS = backend-ios;
        rustBackendIOSSim = backend-ios-sim;
        rustBackendAndroid = backend-android;
      };

      wawona-android = wawonaApps.android;
      wawona-ios = wawonaApps.ios;
      wawona-macos = wawonaApps.macos;


      # generators are in wawonaModules.generators


      isDarwin = pkgs.stdenv.isDarwin;
      isLinux = pkgs.stdenv.isLinux;

      # Keyboard test client wrapper
      keyboard-test-client-macos = pkgs.writeShellScriptBin "keyboard-test-client" ''
        export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
        export WAYLAND_DISPLAY="wayland-0"
        echo "[CLIENT] Connecting to $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
        exec ${backend-macos}/bin/keyboard-test-client "$@"
      '';

      # Define the main package based on platform
      mainPackage = if pkgs.stdenv.isDarwin 
        then (macosWrapper pkgs wawona-macos)
        else (linuxWrapper pkgs backend-macos);

      # Generic keyboard test client (wrapper handles env vars)
      keyboardTestClient = keyboard-test-client-macos; 

      # Vulkan CTS (Conformance Test Suite)
      vulkan-cts-android = pkgs.callPackage ./dependencies/libs/vulkan-cts/android.nix {
        lib = pkgs.lib;
        buildPackages = pkgs.buildPackages;
      };

      packagesForSystem = {
        default = mainPackage;
        wawona = mainPackage;
        wawona-macos = wawona-macos;
        wawona-macos-backend = backend-macos;
        wawona-ios-backend = backend-ios;
        wawona-ios-sim-backend = backend-ios-sim;
        wawona-android-backend = backend-android;
        
        # Mobile targets
        wawona-android = wawona-android;
        
        # Tooling
        gradlegen-android = wawonaApps.generators.gradlegen.generateScript;
        gradlegen = wawonaApps.generators.gradlegen.generateScript;
        
        # Clients
        keyboard-test-client = keyboardTestClient;

        # Vulkan CTS
        vulkan-cts-android = vulkan-cts-android;
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        wawona-ios = wawona-ios;
        # Full Xcode project with both iOS + macOS targets
        xcodegen = wawonaApps.generators.xcodegen.app;
        # iOS-only Xcode project (does not build macOS dependencies)
        xcodegen-ios = (pkgs.callPackage ./dependencies/generators/xcodegen.nix {
          inherit wawonaVersion;
          rustBackendIOS = backend-ios;
          rustBackendIOSSim = backend-ios-sim;
          includeMacOSTarget = false;
          rustPlatform = pkgs.rustPlatform;
        }).app;
        waypipe = waypipeWrapper pkgs toolchains.macos.waypipe;
        waypipe-ios = toolchains.ios.waypipe;
        waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
        foot = footWrapper pkgs toolchains.macos.foot;
        weston = weston;
        weston-terminal = westonAppWrapper pkgs weston "weston-terminal";
        weston-debug = westonAppWrapper pkgs weston "weston-debug";
        weston-simple-shm = westonAppWrapper pkgs weston "weston-simple-shm";

        # Vulkan CTS for macOS (uses KosmicKrisp Vulkan driver)
        vulkan-cts = pkgs.callPackage ./dependencies/libs/vulkan-cts/macos.nix {
          lib = pkgs.lib;
          kosmickrisp = toolchains.macos.kosmickrisp;
        };

        # Vulkan CTS for iOS (cross-compiled for simulator)
        vulkan-cts-ios = pkgs.callPackage ./dependencies/libs/vulkan-cts/ios.nix {
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
          buildModule = toolchains;
        };
      });

    in {
      name = system;
      value = packagesForSystem;
    }) systems);

    apps = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
      src = srcFor pkgs;
      wv = wawonaVersion; # Use centralization
      

    in {
      name = system;
      value = {
        gradlegen-android = {
          type = "app";
          program = "${self.packages.${system}.gradlegen-android}/bin/gradlegen";
        };
        gradlegen = {
          type = "app";
          program = "${self.packages.${system}.gradlegen}/bin/gradlegen";
        };

        wawona-android = {
          type = "app";
          program = "${self.packages.${system}.wawona-android}/bin/wawona-android-run";
        };

        vulkan-cts-android = {
          type = "app";
          program = "${self.packages.${system}.vulkan-cts-android}/bin/vulkan-cts-android-run";
        };
        
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        wawona-ios = {
          type = "app";
          program = "${self.packages.${system}.wawona-ios.automationScript}/bin/wawona-ios-automat";
        };

        xcodegen = {

          type = "app";
          program = "${self.packages.${system}.xcodegen}/bin/xcodegen";
        };

        foot = {
          type = "app";
          program = "${self.packages.${system}.foot}/bin/foot";
        };

        weston-terminal = {
          type = "app";
          program = "${self.packages.${system}.weston-terminal}/bin/weston-terminal";
        };

        weston-debug = {
          type = "app";
          program = "${self.packages.${system}.weston-debug}/bin/weston-debug";
        };

        weston-simple-shm = {
          type = "app";
          program = "${self.packages.${system}.weston-simple-shm}/bin/weston-simple-shm";
        };

        vulkan-cts = {
          type = "app";
          program = "${self.packages.${system}.vulkan-cts}/bin/deqp-vk";
        };
      });
    }) systems);
    devShells = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
      toolchains = import ./dependencies/toolchains {
        inherit (pkgs) lib pkgs stdenv buildPackages;
      };
    in {
      name = system;
      value = {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.pkg-config
          ];

          buildInputs = [
            pkgs.rustToolchain  # This provides both cargo and rustc
            pkgs.libxkbcommon
            pkgs.libffi
            pkgs.wayland-protocols
            pkgs.openssl
          ] ++ (pkgs.lib.optional pkgs.stdenv.isDarwin toolchains.macos.libwayland);

          # Read TEAM_ID from .envrc if it exists, otherwise use default
          shellHook = ''
            export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
            export WAYLAND_DISPLAY="wayland-0"
            mkdir -p $XDG_RUNTIME_DIR
            chmod 700 $XDG_RUNTIME_DIR
            
            # Load TEAM_ID from .envrc if it exists
            if [ -f .envrc ]; then
              TEAM_ID=$(grep '^export TEAM_ID=' .envrc | cut -d'=' -f2 | tr -d '"')
              if [ -n "$TEAM_ID" ]; then
                export TEAM_ID="$TEAM_ID"
                echo "Loaded TEAM_ID from .envrc."
              else
                echo "Warning: TEAM_ID not found in .envrc"
              fi
            else
              echo "Warning: .envrc not found. Create one with 'export TEAM_ID=\"your_team_id\"'"
            fi
          '';
        };
      };
    }) systems);
  };
}
