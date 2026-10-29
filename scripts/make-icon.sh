#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
setdir="$tmp/AppIcon.iconset"
mkdir -p "$setdir"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$repo/Assets/AppIcon.png" --out "$setdir/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$repo/Assets/AppIcon.png" --out "$setdir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$setdir" -o "$repo/Assets/AppIcon.icns"
