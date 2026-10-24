#!/usr/bin/env bash
# Writes the window's icons as 64x64 32-bit TGA, white on transparent (the kit tints them with
# SetVertexColor), from Lucide's SVGs (lucide-static, ISC; the web app's playground uses the same set).
#   tools/icons.sh <lucide-static directory>
# e.g. the web repository's frontend/node_modules/lucide-static. Needs ImageMagick with an SVG renderer.
set -euo pipefail
src="${1:?the lucide-static directory}"
out="$(dirname "$0")/../GoldForever/Media/Icons"
mkdir -p "$out"
ICONS=(coins users trending-up book-open skull package settings palette search chevron-down check x rotate-ccw timer gavel tag backpack flask-conical circle-help)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for name in "${ICONS[@]}"; do
  sed 's/currentColor/#ffffff/g' "$src/icons/$name.svg" > "$tmp/$name.svg"
  magick -background none -density 384 "$tmp/$name.svg" -resize 64x64 -type TrueColorAlpha -compress none "$out/$name.tga"
done
cp "$src/LICENSE" "$out/Lucide-LICENSE.txt"
echo "wrote ${#ICONS[@]} icons to $out"
