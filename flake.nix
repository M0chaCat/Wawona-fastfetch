{
  description = "Wawona Multiplex Runner";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  
  outputs = { self, nixpkgs, rust-overlay }: let
    systems = [ "aarch64-darwin" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs { 
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      
      # Define androidSDK for build module
      androidSDK = if pkgs ? androidenv && pkgs.androidenv ? composeAndroidPackages then
        pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "latest";
          platformToolsVersion = "latest";
          buildToolsVersions = [ "35.0.0" ];
          platformVersions = [ "35" ];  # Android 15
          abiVersions = [ "arm64-v8a" ];  # ARM64 for our target
          includeEmulator = true;
          emulatorVersion = "35.3.11";  # Use a valid available version
          includeSystemImages = true;
          systemImageTypes = [ "google_apis_playstore" ];
        }
      else null;
      
      # Import dependencies module
      depsModule = import ./dependencies/common/common.nix {
        lib = pkgs.lib;
        inherit pkgs;
      };
      
      # Import build module
      buildModule = import ./dependencies/build.nix {
        lib = pkgs.lib;
        inherit pkgs;
        stdenv = pkgs.stdenv;
        buildPackages = pkgs.buildPackages;
      };
      
      # Import Wawona build module
      # Filter source to exclude build artifacts and other files
      wawonaSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let
            baseName = baseNameOf path;
            relPath = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
          in
            !(
              baseName == ".git" ||
              baseName == "build" ||
              baseName == "result" ||
              baseName == ".direnv" ||
              pkgs.lib.hasPrefix "result" baseName ||
              pkgs.lib.hasPrefix ".git" baseName
            );
      };
      
      wawonaBuildModule = import ./dependencies/wawona.nix {
        lib = pkgs.lib;
        inherit pkgs buildModule wawonaSrc;
        inherit androidSDK;
      };
      
      # Get registry for building individual dependencies
      registry = depsModule.registry;
      
      # Build all dependencies for each platform
      iosDeps = buildModule.ios;
      macosDeps = buildModule.macos;
      androidDeps = buildModule.android;
      
      # Create individual dependency packages for each platform
      # Format: <dependency-name>-<platform>
      dependencyPackages = let
        # Helper to create packages for a platform
        createPlatformPackages = platform: deps:
          pkgs.lib.mapAttrs' (name: pkg: {
            name = "${name}-${platform}";
            value = pkg;
          }) deps;
        
        iosPkgs = createPlatformPackages "ios" iosDeps;
        macosPkgs = createPlatformPackages "macos" macosDeps;
        androidPkgs = createPlatformPackages "android" androidDeps;
        
        # libwayland is handled directly in platform dispatchers, not via registry
        directPkgs = {
          "libwayland-ios" = buildModule.buildForIOS "libwayland" {};
          "libwayland-macos" = buildModule.buildForMacOS "libwayland" {};
          "libwayland-android" = buildModule.buildForAndroid "libwayland" {};
          "expat-ios" = buildModule.buildForIOS "expat" {};
          "expat-macos" = buildModule.buildForMacOS "expat" {};
          "expat-android" = buildModule.buildForAndroid "expat" {};
          "libffi-ios" = buildModule.buildForIOS "libffi" {};
          "libffi-macos" = buildModule.buildForMacOS "libffi" {};
          "libffi-android" = buildModule.buildForAndroid "libffi" {};
          "libxml2-ios" = buildModule.buildForIOS "libxml2" {};
          "libxml2-macos" = buildModule.buildForMacOS "libxml2" {};
          "libxml2-android" = buildModule.buildForAndroid "libxml2" {};
          "waypipe-ios" = buildModule.buildForIOS "waypipe" {};
          "waypipe-macos" = buildModule.buildForMacOS "waypipe" {};
          "waypipe-android" = buildModule.buildForAndroid "waypipe" {};
          "swiftshader-android" = buildModule.buildForAndroid "swiftshader" {};
          "kosmickrisp-ios" = buildModule.buildForIOS "kosmickrisp" {};
          "kosmickrisp-macos" = buildModule.buildForMacOS "kosmickrisp" {};
          "epoll-shim-ios" = buildModule.buildForIOS "epoll-shim" {};
          "epoll-shim-macos" = buildModule.buildForMacOS "epoll-shim" {};
          "zstd-ios" = buildModule.buildForIOS "zstd" {};
          "zstd-macos" = buildModule.buildForMacOS "zstd" {};
          "zstd-android" = buildModule.buildForAndroid "zstd" {};
          "lz4-ios" = buildModule.buildForIOS "lz4" {};
          "lz4-macos" = buildModule.buildForMacOS "lz4" {};
          "lz4-android" = buildModule.buildForAndroid "lz4" {};
          "ffmpeg-ios" = buildModule.buildForIOS "ffmpeg" {};
          "ffmpeg-macos" = buildModule.buildForMacOS "ffmpeg" {};
          "ffmpeg-android" = buildModule.buildForAndroid "ffmpeg" {};
          "test-ios-toolchain" = pkgs.callPackage ./dependencies/utils/test-ios-toolchain.nix {};
          "test-ios-toolchain-cross" = pkgs.callPackage ./dependencies/utils/test-ios-toolchain-cross.nix {};
        };
      in
        iosPkgs // macosPkgs // androidPkgs // directPkgs;
      
      wawonaBuildInputs = with pkgs; [
        cmake meson ninja pkg-config
        autoconf automake libtool texinfo
        git python3 direnv gnumake patch
        bison flex shaderc mesa
        tmux sqlite
      ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
        # Xcode tools are system-provided usually
      ];
    in {
      default = pkgs.writeShellApplication {
        name = "wawona-multiplex";
        runtimeInputs = wawonaBuildInputs;
        text = ''
          set -euo pipefail
          session="wawona-build"
          if tmux has-session -t "$session" 2>/dev/null; then
            tmux kill-session -t "$session"
          fi
          
          # Get the flake path (current directory)
          FLAKE_PATH="$(pwd)"
          
          # Fix SQLite database busy errors by ensuring WAL (Write-Ahead Logging) mode
          # This allows multiple Nix processes to access the evaluation cache concurrently
          EVAL_CACHE_DIR="$HOME/.cache/nix/eval-cache-v6"
          if [ -d "$EVAL_CACHE_DIR" ]; then
            for db in "$EVAL_CACHE_DIR"/*.sqlite; do
              if [ -f "$db" ]; then
                # Check if database is already in WAL mode, if not convert it
                CURRENT_MODE=$(sqlite3 "$db" "PRAGMA journal_mode;" 2>/dev/null || echo "unknown")
                if [ "$CURRENT_MODE" != "wal" ] && [ "$CURRENT_MODE" != "unknown" ]; then
                  echo "Converting $(basename "$db") to WAL mode..."
                  sqlite3 "$db" "PRAGMA journal_mode=WAL;" 2>/dev/null || true
                fi
              fi
            done
          fi
          
          # Build all packages in parallel AND multithreaded with a SINGLE nix build command
          # This avoids lock contention that occurs when multiple separate nix commands
          # try to build the same shared dependencies. Nix can parallelize optimally
          # when all targets are specified together.
          # 
          # -j auto: Build multiple derivations in parallel (uses all CPU cores for parallelism)
          # --cores 0: Let each individual build use all available CPU cores (multithreading)
          # 
          # Note: Nix intelligently manages resources to avoid oversubscription
          echo "🔨 Building all platforms in parallel with multithreading..."
          echo "   This builds wawona-ios, wawona-android, and wawona-macos simultaneously"
          echo "   Each build can utilize multiple CPU cores for compilation"
          echo ""
          
          nix build --show-trace -j auto --cores 0 \
            .#wawona-ios \
            .#wawona-android \
            .#wawona-macos
          
          echo ""
          echo "✅ All builds complete! Starting tmux session to run each platform..."
          echo ""
          
          # Now run each app in separate tmux panes (builds are already done)
          # Start session (pane 0) - iOS simulator
          tmux new-session -d -s "$session" -c "$FLAKE_PATH" \
            "echo '🍎 Launching iOS Simulator...' && nix run .#wawona-ios"
          
          # Split horizontally (pane 1) - Android emulator
          tmux split-window -h -t "$session":0 -c "$FLAKE_PATH"
          tmux send-keys -t "$session":0.1 \
            "echo '🤖 Launching Android Emulator...' && nix run .#wawona-android" C-m
          
          # Split pane 1 vertically (pane 2) - macOS app
          tmux split-window -v -t "$session":0.1 -c "$FLAKE_PATH"
          tmux send-keys -t "$session":0.2 \
            "echo '🖥️  Launching macOS App...' && nix run .#wawona-macos" C-m
          
          # Select first pane
          tmux select-pane -t "$session":0.0
          
          # Attach
          tmux attach-session -t "$session"
        '';
      };
      
      # Add Wawona build packages
      wawona-ios = wawonaBuildModule.ios;
      wawona-macos = wawonaBuildModule.macos;
      wawona-android = wawonaBuildModule.android;
      
      # Add dependency packages
      # Format: <dependency-name>-<platform> (e.g., wayland-ios, kosmickrisp-macos)
    } // dependencyPackages);
    
    apps = forAllSystems (system: let
      pkgs = import nixpkgs { 
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      # Use androidenv.composeAndroidPackages to get Android SDK tools via Nix
      # This provides platform-tools (adb), emulator, and system images
      androidSDK = if pkgs ? androidenv && pkgs.androidenv ? composeAndroidPackages then
        pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "latest";
          platformToolsVersion = "latest";
          buildToolsVersions = [ "35.0.0" ];
          platformVersions = [ "35" ];  # Android 15
          abiVersions = [ "arm64-v8a" ];  # ARM64 for our target
          includeEmulator = true;
          emulatorVersion = "35.3.11";  # Use a valid available version
          includeSystemImages = true;
          systemImageTypes = [ "google_apis_playstore" ];
        }
      else null;
      
      # Get tools from the SDK
      androidTools = if androidSDK != null then [
        androidSDK.platform-tools  # Provides adb
        androidSDK.emulator       # Provides emulator
        androidSDK.androidsdk     # Provides avdmanager
      ] else if pkgs ? android-tools then [
        pkgs.android-tools  # Fallback
      ] else [];
    in {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/wawona-multiplex";
      };
      
      # Individual platform apps
      "wawona-macos" = {
        type = "app";
        # Use bin symlink for macOS (more reliable than app bundle path)
        program = "${self.packages.${system}.wawona-macos}/bin/Wawona";
      };
      
      "wawona-ios" = {
        type = "app";
        program = "${self.packages.${system}.wawona-ios}/bin/wawona-ios-simulator";
      };
      
      "wawona-android" = let
        # Create a wrapper that uses Nix-provided Android tools
        # Tools are provided via runtimeInputs and should be in PATH
        androidWrapper = pkgs.writeShellScriptBin "wawona-android-wrapper" ''
          set -e
          # Add Android tools to PATH
          export PATH="${pkgs.lib.makeBinPath androidTools}:$PATH"
          
          # Set ANDROID_SDK_ROOT to the Nix-provided SDK
          export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
          export ANDROID_HOME="$ANDROID_SDK_ROOT"
          
          exec "${self.packages.${system}.wawona-android}/bin/wawona-android-run" "$@"
        '';
in {
        type = "app";
        program = "${androidWrapper}/bin/wawona-android-wrapper";
        # Provide Android tools via Nix
        runtimeInputs = androidTools;
      };
    });
    
    devShells = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };
    in {
      default = pkgs.mkShell {
        name = "wawona-dev";
        buildInputs = with pkgs; [
          cmake
          meson
          ninja
          pkg-config
          autoconf
          automake
          libtool
          texinfo
          git
          python3
          direnv
          gnumake
          patch
          bison
          flex
          shaderc
          mesa
          dialog
        ];
        shellHook = ''
            echo "🔨 Wawona Development Environment"
            echo "Run 'nix run' to build Wawona for all platforms (iOS, macOS, Android)"
            echo ""
            echo "Available builds:"
            echo "  - nix build .#wawona-ios      (iOS)"
            echo "  - nix build .#wawona-macos   (macOS)"
            echo "  - nix build .#wawona-android (Android)"
            echo ""
            echo "Dependencies are automatically built as needed."
        '';
      };
    });
  };
}
