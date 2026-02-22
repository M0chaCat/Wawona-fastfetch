# Assembles a complete Cargo workspace source tree for crate2nix.
#
# Combines:
# 1. Filtered wawona source (no .git, target/, Inspiration/, etc.)
# 2. Pre-patched waypipe source injected at ./waypipe/
# 3. Regenerated Cargo.lock that includes waypipe's sub-crates
#
# The Cargo.lock regeneration is critical: the original lockfile doesn't
# include waypipe's internal path dependencies (wrap-ffmpeg, wrap-lz4, etc.)
# Since those paths only appear after injecting waypipe, we must regenerate
# the lock file to satisfy `cargo metadata --locked` in crate2nix.
#
{ pkgs, wawonaSrc, waypipeSrc, wawonaVersion, platform ? "ios" }:

pkgs.stdenvNoCC.mkDerivation {
  name = "wawona-workspace-src";
  
  src = wawonaSrc;

  nativeBuildInputs = [ pkgs.python3 ];

  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    # Copy the wawona source as the base
    cp -r . $out
    chmod -R u+w $out
    
    # Only remove binaries from the source tree for mobile platforms to prevent cross-compilation errors.
    # macOS needs these for utility tools like keyboard-test-client.
    if [ "${platform}" != "macos" ]; then
      echo "⚠️  Removing binaries for mobile platform: ${platform}"
      rm -rf $out/src/bin
      rm -f $out/src/main.rs
    fi


    # Inject pre-patched waypipe source
    if [ -n "${toString waypipeSrc}" ]; then
      mkdir -p $out/waypipe
      cp -r ${waypipeSrc}/* $out/waypipe/
      chmod -R u+w $out/waypipe

      echo "✓ Waypipe source injected"
    fi

    # Patch root Cargo.toml version and Cargo.lock consistency
    cd $out
    ${pkgs.python3}/bin/python3 <<'EOF'
from pathlib import Path
import re

platform = "${platform}"

p = Path("Cargo.toml")
if p.exists():
    s = p.read_text()
    
    # Only restrict binaries for mobile platforms
    if platform != "macos":
        print(f"⚠️  Disabling binaries/autobins for mobile platform: {platform}")
        # Inject autobins = false to prevent binary auto-discovery
        s = re.sub(r'(\[package\]\n)', r'\1autobins = false\n', s)
        
        # Strip all [[bin]] sections to prevent cross-compilation linking errors for unused binaries
        lines = s.split('\n')
        out_lines = []
        in_bin = False
        for line in lines:
            stripped = line.strip()
            if stripped.startswith('[[bin]]'):
                in_bin = True
                continue
            if in_bin and stripped.startswith('[') and not stripped.startswith('[[bin]]'):
                in_bin = False
            if not in_bin:
                out_lines.append(line)
        s = '\n'.join(out_lines)
    
    s = re.sub(r'^version = .*', 'version = "${wawonaVersion}"', s, flags=re.MULTILINE)
    
    p.write_text(s)
    print(f"Patched Cargo.toml version to ${wawonaVersion}")

# Android uses OpenSSH (fork/exec), not libssh2. The shared Cargo.lock
# lists ssh2 as a waypipe dep (from iOS patches). Strip it so
# `cargo metadata --locked` doesn't require ssh2 in waypipe's Cargo.toml.
if platform == "android":
    lock = Path("Cargo.lock")
    if lock.exists():
        content = lock.read_text()
        lines = content.splitlines(True)
        new_lines = []
        in_waypipe = False
        in_deps = False
        for line in lines:
            s = line.strip()
            if s == '[[package]]':
                in_waypipe = False
                in_deps = False
            if s == 'name = "waypipe"':
                in_waypipe = True
            if in_waypipe and s == 'dependencies = [':
                in_deps = True
            if in_waypipe and in_deps and '"ssh2"' in s:
                continue
            new_lines.append(line)
        lock.write_text("".join(new_lines))
        print("Stripped ssh2 from waypipe deps in Cargo.lock (Android: OpenSSH only)")
EOF
  '';
}
