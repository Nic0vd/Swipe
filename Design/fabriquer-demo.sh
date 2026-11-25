#!/bin/bash
# Fabrique les GIF de démonstration du README à partir du dessin de l'app
# (Glisse/GestureDemo.swift) :
#   Design/demo.gif     légendes en français (README.fr.md)
#   Design/demo-en.gif  légendes en anglais  (README.md)
set -euo pipefail
cd "$(dirname "$0")"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
swiftc -O -parse-as-library -module-cache-path "$WORK/mc" ../Glisse/GestureDemo.swift animation-demo.swift -o "$WORK/anim"

make_gif() {   # $1 = fichier de sortie, $2 = langue (vide = français)
  rm -rf "$WORK/frames"; mkdir "$WORK/frames"
  if [ -n "$2" ]; then
    "$WORK/anim" "$WORK/frames" "$2" ../Glisse/Localizable.xcstrings
  else
    "$WORK/anim" "$WORK/frames"
  fi
  ffmpeg -loglevel error -y -framerate 15 -i "$WORK/frames/f%04d.png" \
    -vf "palettegen=max_colors=128:stats_mode=diff" "$WORK/palette.png"
  ffmpeg -loglevel error -y -framerate 15 -i "$WORK/frames/f%04d.png" -i "$WORK/palette.png" \
    -lavfi "paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" -loop 0 "$1"
  echo "✓ $1 ($(du -h "$1" | cut -f1))"
}

make_gif demo.gif ""
make_gif demo-en.gif en
