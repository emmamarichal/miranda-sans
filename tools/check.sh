#!/usr/bin/env bash
set -euo pipefail

# Activate venv if present
if [ -d ".venv" ]; then
  source .venv/bin/activate
fi

GFT="$(command -v gftools)"
FB="$(command -v fontbakery)"

echo "Using gftools: $GFT"
echo "Using fontbakery: $FB"

shopt -s nullglob

for f in fonts/ttf/MirandaSans-*.ttf; do
  case "$f" in
    *backup*|*.tmp.ttf) continue ;;
  esac

  "$GFT" fix-fstype "$f"
  "$GFT" fix-dsig "$f"
  "$GFT" fix-nonhinting "$f"
done

rm -f fonts/ttf/*backup-fonttools-prep-gasp*.ttf fonts/ttf/*.tmp.ttf

"$FB" check-googlefonts fonts/ttf/MirandaSans-*.ttf --skip-network --json report.json

echo "Done. report.json created."

