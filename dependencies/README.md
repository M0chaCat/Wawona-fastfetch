# Wawona Nix Dependencies

This directory contains the Nix infrastructure for building Wawona on various platforms.

## Directory Structure

```
dependencies/
├── README.md                     # This file
│
├── toolchains/                   # Cross-compilation infrastructure
│   ├── default.nix               # Entry point for toolchains (C library builds)
│   ├── android.nix               # Android NDK toolchain setup
│   └── common/                   # Shared registry and helpers
│
├── wawona/                       # Final Wawona application builds
│   ├── default.nix               # Entry point (returns { ios, macos, android, generators })
│   ├── ios.nix                   # iOS app derivation
│   ├── macos.nix                 # macOS app derivation
│   ├── android.nix               # Android app derivation
│   └── common.nix                # Shared sources, flags, and dependencies
│
├── libs/                         # C libraries for cross-compilation
│   ├── libwayland/               # Wayland protocol library
│   ├── pixman/                   # Pixel manipulation library
│   ├── waypipe/                  # Wayland proxy for remote display
│   └── ...                       # 25+ other C dependencies
│
├── clients/                      # Bundled terminal applications
│   ├── foot/                     # Foot terminal emulator
│   └── weston/                   # Weston compositor (for weston-terminal)
│
├── platforms/                    # Cross-compilation platform helpers
│   ├── ios.nix                   # iOS SDK configuration
│   ├── macos.nix                 # macOS SDK configuration
│   └── android.nix               # Android SDK configuration
│
├── generators/                   # IDE project file generators
│   ├── xcodegen.nix              # Generates Xcode project for iOS/macOS
│   └── gradlegen.nix             # Generates Gradle build files for Android
│
└── utils/                        # Utility scripts
    └── xcode-wrapper.nix         # Xcode environment helpers
```

## How It Works

### In `flake.nix`:

```nix
# 1. Get cross-compilation toolchains
toolchains = import ./dependencies/toolchains { ... };

# 2. Get final Wawona builds and generators
wawonaApps = pkgs.callPackage ./dependencies/wawona {
  buildModule = toolchains;
  inherit wawonaSrc wawonaVersion rustBackendMacOS rustBackendIOS;
  ...
};

# 3. Use the apps
wawona-macos = wawonaApps.macos;
wawona-ios = wawonaApps.ios;
wawona-android = wawonaApps.android;

# 4. Use the generators
xcodegen-project = wawonaApps.generators.xcodegen.project;
```

## Key Concepts

| Directory | Purpose |
|-----------|---------|
| `toolchains/` | Cross-compiles C libraries for each target platform |
| `wawona/` | Builds the final Wawona application for each platform |
| `libs/` | Low-level C libraries (libwayland, pixman, etc.) |
| `clients/` | Bundled terminal apps (foot, weston-terminal) |
| `platforms/` | Platform-specific SDK configurations |
| `generators/` | Creates IDE project files (Xcode, Gradle) |
| `utils/` | Helper scripts (Xcode wrapper, etc.) |
