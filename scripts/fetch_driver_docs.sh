#!/usr/bin/env bash
set -e

# Run from repo root
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUTDIR="docs/drivers-how-to/downloaded"
mkdir -p "$OUTDIR"

urls=(
	"https://docs.vulkan.org/guide/latest/platforms.html"
	"https://vulkan.lunarg.com/doc/view/1.4.341.1/mac/getting_started.html"
	"https://github.com/KhronosGroup/MoltenVK"
	"https://docs.mesa3d.org/drivers/kosmickrisp.html"
	"https://source.android.com/docs/core/graphics/implement-vulkan"
	"https://developer.android.com/games/develop/vulkan/overview"
	"https://www.lunarg.com/vulkan-sdk/"
)

for u in "${urls[@]}"; do
	echo "Downloading $u ..."
	sanitized=$(echo "$u" | sed -E 's|^https?://||; s|[:/]+|_|g; s|\.html$||; s|[^a-zA-Z0-9_-]|_|g' | head -c 120)
	curl -L -sS "$u" -o "$OUTDIR/${sanitized}.html" || echo "  (fetch failed, skipping)"
done

echo "Done. Files in $ROOT/$OUTDIR"
