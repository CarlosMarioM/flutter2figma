#!/usr/bin/env bash
# Renders the Figma Community listing images from the SVG sources.
# Requires ImageMagick 7 (`magick`) and the macOS system fonts below.
# Shapes come from the SVGs; text is drawn by ImageMagick, because its
# built-in SVG renderer has no font configuration.
set -euo pipefail
cd "$(dirname "$0")"

F=/System/Library/Fonts/Supplemental
MONO=/System/Library/Fonts/SFNSMono.ttf

# Icon: 128×128 for Figma, 512×512 as a high-resolution source.
magick -background none -density 192 icon.svg -resize 512x512 -depth 8 icon-512.png
magick icon-512.png -resize 128x128 -depth 8 icon.png

# Cover: 1920×1080. -density 72 after reading makes point sizes = pixels.
magick -background none -density 96 cover.svg -density 72 \
  -font "$F/Arial Bold.ttf" -fill white -pointsize 112 -gravity northwest \
  -annotate +112+190 'Flutter2Figma' \
  -font "$F/Arial.ttf" -fill '#A9B4C8' -pointsize 44 \
  -annotate +116+340 'Your Flutter UI as an editable' \
  -annotate +116+396 'Figma design. No screenshots.' \
  -fill white -pointsize 36 \
  -annotate +170+565 'Auto-layout frames from your widgets' \
  -annotate +170+645 'Light & Dark color variables' \
  -annotate +170+725 'Text styles and components' \
  -font "$MONO" -fill '#4FC3F7' -pointsize 28 \
  -annotate +144+881 '$ flutter2figma export  ->  design.json' \
  -font "$F/Arial.ttf" -fill '#8A96AD' -pointsize 22 \
  -annotate +1030+872 'Light' -annotate +1196+872 'Dark' \
  -flatten -depth 8 cover.png

echo "icon.png icon-512.png cover.png"
