# Wawona

**Wawona** is a native Wayland Compositor for macOS, iOS, and Android.
<div align="center">
  <img src="gallery/preview1.png" alt="Wawona - Wayland Compositor Preview 1" width="800"/>
  <details>
    <summary>More previews</summary>
    <img src="gallery/preview2.png" alt="Wawona - Wayland Compositor Preview 2" width="800"/>
    <img src="gallery/preview3.png" alt="Wawona - Wayland Compositor Preview 3" width="800"/>
  </details>
</div>

> **Project Vision:** Read about my long-term objectives in [Project Goals](docs/goals.md).

## FAQ

### How do I build this?

1. Use an Apple Silicon Mac.
2. Install Nix.
3. Build with the Nix flake.

> For detailed instructions and available build targets, see → [Compilation Guide](docs/compilation.md).

### "I don't have nix"

[hm. Fresh out of luck, I guess! `¯\_(ツ)_/¯`](https://www.youtube.com/watch?v=dQw4w9WgXcQ)

### Why Nix?

I use Nix to maintain a clean repository free of vendored dependency source code while ensuring hermetic, reproducible builds across all platforms. Nix allows us to define precise build environments for iOS, macOS, and Android without polluting your system.

#### Xcode Wrapper for Reproducible Builds

Cross-compiling for iOS requires Apple's proprietary SDKs and toolchains, which cannot be redistributed in the Nix store. To bridge this gap while maintaining reproducibility, we utilize a custom **Xcode Wrapper**.

This tool (`dependencies/utils/xcode-wrapper.nix`):
1.  **Dynamically Locates Xcode**: It finds your local Xcode installation (via `xcode-select` or standard paths).
2.  **Injects the Toolchain**: It exposes the official Apple clang compiler, linker, and SDKs to the Nix build sandbox in a controlled manner.
3.  **Ensures Consistency**: By wrapping the system toolchain, we ensure that builds use the correct iOS SDKs (e.g., matching our target versions) regardless of where the project is checked out, provided Xcode is installed.

This hybrid approach gives us the best of both worlds: the reliability of Nix dependency management and the necessity of Apple's official build tools.

##### Usage

The wrapper is integrated automatically into our Nix build expressions for iOS targets. You do not need to invoke it manually.

**Requirements:**
1.  **Install Xcode**: Ensure Xcode is installed (via App Store or Apple Developer).
2.  **Select Xcode**: Run `sudo xcode-select -s /Applications/Xcode.app` (or your custom path).

**Advanced:**
If you have multiple Xcode versions or a non-standard installation, you can force a specific path by setting the `XCODE_APP` environment variable before running Nix:
```bash
export XCODE_APP=/Applications/Xcode-14.app
nix build .#waypipe-ios
```

### Contributing & Supporting

Wawona is a massive undertaking to bring a native Wayland compositor to Apple platforms and Android, and **I cannot sustain this project alone**. Your support _whether through code, issues, ideas, or donations_ is essential to its progress and survival.

You can help by:

- Opening issues for bugs or feature requests
- Submitting pull requests for improvements
- Sharing ideas and suggestions
- Spreading the word to others
- Supporting ongoing development through donations if you find Wawona useful or believe in its goals

Thank you for being part of the journey!


**Donate here:**
Ko‑fi: https://ko-fi.com/aspauldingcode

Share Wawona with friends!

# Discord:
https://discord.gg/wHVSV52uw5

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

This project uses dependencies that are licensed under various open source licenses (MIT, LGPL, BSD, Apache 2.0). Please refer to their respective licenses for more information.
