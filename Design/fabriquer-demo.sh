#!/bin/bash
# Fabrique Design/demo.gif à partir du dessin animation-demo.swift.
set -euo pipefail
cd "$(dirname "$0")"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
swiftc -O -parse-as-library -module-cache-path "$WORK/mc" ../Glisse/GestureDemo.swift animation-demo.swift -o "$WORK/anim"
mkdir "$WORK/frames" && "$WORK/anim" "$WORK/frames"
ffmpeg -loglevel error -y -framerate 15 -i "$WORK/frames/f%04d.png" \
  -vf "palettegen=max_colors=128:stats_mode=diff" "$WORK/palette.png"
ffmpeg -loglevel error -y -framerate 15 -i "$WORK/frames/f%04d.png" -i "$WORK/palette.png" \
  -lavfi "paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" -loop 0 demo.gif
echo "✓ demo.gif ($(du -h demo.gif | cut -f1))"
