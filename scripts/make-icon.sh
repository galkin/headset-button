#!/bin/bash
# Builds Resources/AppIcon.icns with the built-in sips and iconutil from two
# exports of design/headset-button.pen ("App icon" board):
#   design/app-icon-1024.png  — 1024 master, used for 128 px and up
#   design/app-icon-small.png — 64 × 64 heavier-stroke variant, used for
#                               16, 16@2x, 32 and 32@2x
# Usage: scripts/make-icon.sh [path/to/1024.png] [path/to/small-64.png]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="${1:-$ROOT/design/app-icon-1024.png}"
SMALL="${2:-$ROOT/design/app-icon-small.png}"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
trap 'rm -rf "$WORK"' EXIT

mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    if [ "$size" -le 32 ]; then src="$SMALL"; else src="$MASTER"; fi
    sips -z "$size" "$size" "$src" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$src" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Built $ROOT/Resources/AppIcon.icns"
