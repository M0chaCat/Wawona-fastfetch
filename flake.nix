{
  description = "Wawona Compositor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    hiahkernel.url = "github:aspauldingcode/HIAHKernel";
  };

  outputs = { self, nixpkgs, rust-overlay, hiahkernel }:
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
              targets = [ "aarch64-apple-ios-sim" ];
            };
            rustPlatform = super.makeRustPlatform {
              cargo = self.rustToolchain;
              rustc = self.rustToolchain;
            };
            wayland = super.wayland.overrideAttrs (old: {
              meta = old.meta // { platforms = old.meta.platforms ++ [ "aarch64-darwin" "x86_64-darwin" ]; badPlatforms = []; };
              postPatch = (old.postPatch or "") + ''
                # Create a fix header with ppoll definition
                mkdir -p src
                cat > src/macos-fix.h <<EOF
                #ifdef __APPLE__
                #define _DARWIN_C_SOURCE
                #include <poll.h>
                #include <time.h>
                #include <signal.h>
                #include <unistd.h>
                #ifndef ppoll
                static inline int ppoll(struct pollfd *fds, nfds_t nfds, const struct timespec *timeout_ts, const sigset_t *sigmask) {
                    int timeout_ms = timeout_ts ? (int)(timeout_ts->tv_sec * 1000 + timeout_ts->tv_nsec / 1000000) : -1;
                    return poll(fds, nfds, timeout_ms);
                }
                #endif
                #endif
                EOF
                
                # Helper to update file
                patch_file() {
                    echo "Patching $1 with macos-fix.h..."
                    if [ -f "$1" ]; then
                        sed -i '1s/^/#include "macos-fix.h"\n/' "$1"
                        echo "DEBUG: Head of $1 after patching:"
                        head -n 3 "$1"
                    else
                        echo "Warning: $1 not found"
                    fi
                }

                # Inject include at the top of problematic files
                for f in src/wayland-client.c src/wayland-server.c src/event-loop.c src/wayland-os.c; do
                    patch_file "$f"
                done
                
                # Check for patch success
                if grep -q "macos-fix.h" src/wayland-client.c; then
                    echo "SUCCESS: wayland-client.c patched"
                else
                    echo "FAILURE: wayland-client.c NOT patched"
                    exit 1
                fi
              '';
            });
          })
        ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

    srcFor = pkgs:
      pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: _:
          let name = builtins.baseNameOf path;
          in !(name == ".git" || name == "result" || name == ".direnv" || name == "target");
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
      exec "${wawona}/bin/Wawona" "$@"
    '';

    waypipeWrapper = pkgs: waypipe: pkgs.writeShellScriptBin "waypipe" ''
      ${macosEnv}
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

  in
  {
    packages = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
      src  = srcFor pkgs;

      # Rust compositor
      compositor = pkgs.rustPlatform.buildRustPackage {
        pname = "wawona";
        version = wawonaVersion;

        inherit src;
        cargoLock.lockFile = ./Cargo.lock;

        prePatch = ''
          echo "Patching Cargo.toml version to ${wawonaVersion}..."
          sed -i 's/^version = .*/version = "${wawonaVersion}"/' Cargo.toml
        '';
        
        # Disable tests - they require XDG_RUNTIME_DIR which isn't available in Nix sandbox
        doCheck = false;
        
        # Build library and all binaries
        cargoBuildFlags = [ "--lib" "--bins" ];

        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [
          pkgs.libxkbcommon
          pkgs.libffi
        ];

        postInstall = ''
          # Create include directory for Rust backend headers
          mkdir -p $out/include
          
          # Copy any existing headers if they exist
          if [ -d include ]; then
            cp -r include/* $out/include/ || true
          fi
          
          # Generate UniFFI bindings for Swift/Objective-C
          echo "📦 Generating UniFFI bindings..."
          mkdir -p $out/uniffi/swift
          
          # Generate Swift bindings from UDL file (must be in source dir during build)
          if [ -f "$out/bin/uniffi-bindgen" ] && [ -f "src/wawona.udl" ]; then
            echo "Found uniffi-bindgen and wawona.udl, generating bindings..."
            $out/bin/uniffi-bindgen generate \
              src/wawona.udl \
              --language swift \
              --out-dir $out/uniffi/swift 2>&1 | tee $out/uniffi/generation.log
          else
            echo "Missing: uniffi-bindgen=$(test -f $out/bin/uniffi-bindgen && echo yes || echo no), udl=$(test -f src/wawona.udl && echo yes || echo no)"
          fi
          
          # Copy UDL for reference
          cp src/wawona.udl $out/uniffi/ 2>/dev/null || true
          
          if [ -d "$out/uniffi/swift" ] && [ "$(ls -A $out/uniffi/swift)" ]; then
            echo "✅ UniFFI bindings generated in $out/uniffi/swift/"
          else
            echo "⚠️  UniFFI bindings not generated (this is OK for now)"
          fi
        '';
      };

      compositor-ios = let
        # Use Nixpkgs cross-compilation infrastructure for iOS Simulator (aarch64) dependencies
        crossPkgs = import nixpkgs {
          localSystem = system;
          crossSystem = {
            config = "aarch64-apple-darwin";
            sdk = "iPhoneSimulator";
            xcodePlatform = "iPhoneSimulator";
            rustc.config = "aarch64-apple-ios-sim";
          };
          config.allowUnfree = true;
          overlays = [
            (self: super: {
              # Fix atf configure check for cross-compilation
              atf = super.atf.overrideAttrs (old: {
                configureFlags = (old.configureFlags or []) ++ [
                  "atf_cv_prog_getopt_plus=yes"
                ];
                doCheck = false; # Cannot run tests for cross-compiled binaries
              });
              # Disable tests for libuv during cross-compilation
              libuv = super.libuv.overrideAttrs (old: {
                doCheck = false;
              });
            })
          ];
        };
      in pkgs.rustPlatform.buildRustPackage {
        pname = "wawona-ios-backend";
        version = wawonaVersion;
        inherit src;
        cargoLock.lockFile = ./Cargo.lock;

        # Target aarch64-apple-ios-sim specifically for simulator
        cargoBuildTarget = "aarch64-apple-ios-sim";

        # Disable tests as they can't run on the build host
        doCheck = false;

        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [
          crossPkgs.libxkbcommon
          crossPkgs.libffi
        ];

        # Cargo needs the linker set correctly for the cross target
        # We use the cross-compiler from crossPkgs
        CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER = "${crossPkgs.stdenv.cc.targetPrefix}cc";
        
        prePatch = ''
          echo "Patching Cargo.toml version to ${wawonaVersion}..."
          sed -i 's/^version = .*/version = "${wawonaVersion}"/' Cargo.toml
        '';

        # Patch dependencies that don't support iOS out of the box
        postPatch = ''
          # We search for it in the vendor directory
          find . -name common_poll.rs -exec sed -i 's/"macos"/"macos", target_os = "ios"/g' {} +
          find . -name handle.rs -exec sed -i 's/"macos"/"macos", target_os = "ios"/g' {} +
          
          # Socket flags: ios (like macos) doesn't have MSG_NOSIGNAL or CMSG_CLOEXEC
          find . -name socket.rs -exec sed -i 's/target_os = "macos"/any(target_os = "macos", target_os = "ios")/g' {} +
          find . -name socket.rs -exec sed -i 's/not(target_os = "macos")/not(any(target_os = "macos", target_os = "ios"))/g' {} +
        '';

        postInstall = ''
          mkdir -p $out/include
          if [ -d include ]; then
            cp -r include/* $out/include/ || true
          fi
        '';
      };

      # Platform-specific builds (macOS/iOS/Android)
      buildModule = import ./dependencies/build.nix {
        inherit (pkgs) lib pkgs stdenv buildPackages;
      };

      # Wawona system module (macOS/iOS/Android)
      wawonaSrc = src;
      
      wawona-macos = pkgs.callPackage ./dependencies/wawona-macos.nix {
        inherit buildModule wawonaSrc;
        compositor = compositor;
        wawonaVersion = wawonaVersion;
        weston = weston;
        waylandVersion = pkgs.wayland.version;
        xkbcommonVersion = pkgs.libxkbcommon.version;
        lz4Version = pkgs.lz4.version;
        zstdVersion = pkgs.zstd.version;
        libffiVersion = pkgs.libffi.version;
        sshpassVersion = pkgs.sshpass.version;
        waypipeVersion = pkgs.waypipe.version;
        waypipe = buildModule.macos.waypipe;
      };

      weston = pkgs.callPackage ./dependencies/applications/weston/macos.nix { };

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

      wawona-android = pkgs.callPackage ./dependencies/wawona-android.nix {
        inherit buildModule wawonaSrc androidSDK;
        wawonaVersion = wawonaVersion;
      };

      wawona-ios = pkgs.callPackage ./dependencies/wawona-ios.nix {
        inherit buildModule wawonaSrc hiahkernel;
        wawonaVersion = wawonaVersion;
        compositor = compositor-ios;
      };
      
      xcodegenProject = pkgs.callPackage ./dependencies/xcodegen-wawona.nix {
        inherit pkgs;
        rustPlatform = pkgs.rustPlatform;
        hiahkernel = hiahkernel;
        wawonaVersion = wawonaVersion;
        compositor = compositor-ios;
      };

      gradlegen = pkgs.callPackage ./dependencies/gradlegen-wawona.nix { };

      isDarwin = pkgs.stdenv.isDarwin;
      isLinux = pkgs.stdenv.isLinux;

      # Keyboard test client wrapper
      keyboard-test-client-macos = pkgs.writeShellScriptBin "keyboard-test-client" ''
        export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
        export WAYLAND_DISPLAY="wayland-0"
        echo "[CLIENT] Connecting to $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
        exec ${compositor}/bin/keyboard-test-client "$@"
      '';

      # Define the main package based on platform
      mainPackage = if pkgs.stdenv.isDarwin 
        then (macosWrapper pkgs wawona-macos)
        else (linuxWrapper pkgs compositor);

      # Generic keyboard test client (wrapper handles env vars)
      keyboardTestClient = keyboard-test-client-macos; 

      packagesForSystem = {
        default = mainPackage;
        wawona = mainPackage;
        wawona-macos = wawona-macos;
        
        # Mobile targets
        wawona-android = wawona-android;
        
        # Tooling
        gradlegen-android = gradlegen;
        
        # Clients
        keyboard-test-client = keyboardTestClient;
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        # macOS/iOS specific
        wawona-ios = wawona-ios;
        xcodegen-ios = xcodegenProject.project;
        waypipe = waypipeWrapper pkgs buildModule.macos.waypipe;
        foot = footWrapper pkgs buildModule.macos.foot;
        weston = weston;
        weston-terminal = westonAppWrapper pkgs weston "weston-terminal";
        weston-debug = westonAppWrapper pkgs weston "weston-debug";
        weston-simple-shm = westonAppWrapper pkgs weston "weston-simple-shm";
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
          program = "${(pkgs.callPackage ./dependencies/gradlegen-wawona.nix { }).generateScript}/bin/gradlegen";
        };

        wawona-android = {
          type = "app";
          program = "${self.packages.${system}.wawona-android}/bin/wawona-android-run";
        };
        
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        wawona-ios = {
          type = "app";
          program = "${self.packages.${system}.wawona-ios.automationScript}/bin/wawona-ios-automat";
        };

        xcodegen-ios = {
          type = "app";
          program = "${(pkgs.callPackage ./dependencies/xcodegen-wawona.nix {
            inherit pkgs;
            rustPlatform = pkgs.rustPlatform;
            hiahkernel = hiahkernel;
            wawonaVersion = wv;
          }).openScript}/bin/xcodegen-open";
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
      });
    }) systems);
    devShells = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
    in {
      name = system;
      value = {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.wayland-scanner
          ];
          buildInputs = [
            pkgs.rustToolchain  # This provides both cargo and rustc
            pkgs.libxkbcommon
            pkgs.libffi
            pkgs.wayland-protocols
          ];

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
