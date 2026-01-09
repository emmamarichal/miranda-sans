#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Miranda Sans – Build & QA Pipeline (Repo Structure)
#
# Repo structure (expected):
# documentation/
#   article/ARTICLE.en_us.html
#   article/hero.png
#
# fonts/
#   ttf/
#   otf/
#   variable/
#   webfonts/
#
# scripts/
#   build_fonts.sh
#   patch_italic_vf_metadata.py
#   patch_static_names.py
#   patch_static_italic_stat.py
#
# sources/
#   config.yaml
#   (glyphs + instance_ufos etc)
#
# This script:
# 1) Runs gftools builder sources/config.yaml
# 2) Moves outputs into fonts/{variable,static,webfonts}
# 3) Runs gftools fix-font on all TTFs
# 4) Runs your patch scripts
# 5) Runs FontBakery offline reports
###############################################################################

# ---------------------------------------------------------------------------
# Always run from repo root (even if called from scripts/)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Paths (new structure)
# ---------------------------------------------------------------------------
CONFIG="sources/config.yaml"

OUT_ROOT="fonts"
OUT_TTF="$OUT_ROOT/ttf"
OUT_VF="$OUT_ROOT/variable"
OUT_WEB="$OUT_ROOT/webfonts"
OUT_OTF="$OUT_ROOT/otf"

PATCH_ITALIC_VF="scripts/patch_italic_vf_metadata.py"
PATCH_STATIC_NAMES="scripts/patch_static_names.py"
PATCH_STATIC_ITALIC_STAT="scripts/patch_static_italic_stat.py"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

ensure_dirs() {
  mkdir -p "$OUT_TTF" "$OUT_VF" "$OUT_OTF" "$OUT_WEB"
}

move_if_exists() {
  local src_glob="$1"
  local dst_dir="$2"
  shopt -s nullglob
  local files=( $src_glob )
  shopt -u nullglob
  if [ ${#files[@]} -gt 0 ]; then
    mv "${files[@]}" "$dst_dir/"
    return 0
  fi
  return 1
}

# Detect where gftools builder dumped output.
# Common: ofl/mirandasans/
# Fallback: find any directory holding MirandaSans*[wght].ttf
detect_builder_family_dir() {
  if [ -d "ofl/mirandasans" ]; then
    echo "ofl/mirandasans"
    return 0
  fi

  local hit
  hit="$(find . -maxdepth 5 -type f -name "MirandaSans*[[]wght[]].ttf" -print -quit || true)"
  if [ -n "$hit" ]; then
    dirname "$hit"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# 0. Prep
# ---------------------------------------------------------------------------
echo "== 0. Prep output folders =="
ensure_dirs

# Clean previous outputs in canonical folders
rm -f "$OUT_TTF"/*.ttf 2>/dev/null || true
rm -f "$OUT_VF"/*.ttf 2>/dev/null || true
rm -f "$OUT_WEB"/* 2>/dev/null || true

# Remove old builder PR-style output if it exists
rm -rf ofl 2>/dev/null || true

# Also remove stray variable fonts in repo root (keeps repo tidy)
rm -f ./*"[wght].ttf" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 1. Build
# ---------------------------------------------------------------------------
echo "== 1. Building via gftools builder ($CONFIG) =="
gftools builder "$CONFIG"

# ---------------------------------------------------------------------------
# 2. Normalize builder output into fonts/
# ---------------------------------------------------------------------------
echo "== 2. Normalizing builder output into fonts/ =="
FAMILY_DIR="$(detect_builder_family_dir || true)"
[ -n "${FAMILY_DIR:-}" ] || die "Could not find builder output. Expected ofl/mirandasans or MirandaSans*[wght].ttf."

echo "   Detected builder output at: $FAMILY_DIR"

# Variable fonts can be in:
# - $FAMILY_DIR/variable_ttf
# - $FAMILY_DIR/variable
# - $FAMILY_DIR (root)
move_if_exists "$FAMILY_DIR/variable_ttf/*.ttf" "$OUT_VF" || true
move_if_exists "$FAMILY_DIR/variable/*.ttf" "$OUT_VF" || true
move_if_exists "$FAMILY_DIR/"*"[""wght""]"".ttf" "$OUT_VF" || true

# Static fonts can be in:
# - $FAMILY_DIR/ttf
move_if_exists "$FAMILY_DIR/ttf/*.ttf" "$OUT_TTF" || true

# Webfonts can be in:
# - $FAMILY_DIR/webfonts
move_if_exists "$FAMILY_DIR/webfonts/*" "$OUT_WEB" || true

# OTFs can be in:
# - $FAMILY_DIR/otf
move_if_exists "$FAMILY_DIR/otf/*.otf" "$OUT_OTF" || true

# Remove builder output folder so repo stays clean
rm -rf ofl 2>/dev/null || true

# Safety: if builder wrote VFs to repo root anyway, move them
move_if_exists ./*"[wght].ttf" "$OUT_VF" || true

echo "   Output counts:"
echo "   - $OUT_VF:     $(ls -1 "$OUT_VF" 2>/dev/null | wc -l | tr -d ' ')"
echo "   - $OUT_TTF: $(ls -1 "$OUT_TTF" 2>/dev/null | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
# 3. gftools fix-font (all TTFs)
# ---------------------------------------------------------------------------
echo "== 3. Running gftools fix-font on all fonts =="
find "$OUT_ROOT" \( -name "*.ttf" -o -name "*.otf" \) \
  -exec gftools fix-font {} -o {} \;

# ---------------------------------------------------------------------------
# 4. Patch metadata and naming
# ---------------------------------------------------------------------------
echo "== 4. Patching metadata and naming =="

# 4A) Your existing python patch scripts (keep them authoritative)
# Patch italic VF specifics
VF_ITALIC_PATH="$(ls -1 "$OUT_VF"/*Italic*"[wght].ttf" 2>/dev/null | head -n 1 || true)"
if [ -n "$VF_ITALIC_PATH" ]; then
  echo "   Patching italic VF: $VF_ITALIC_PATH"
  python3 "$PATCH_ITALIC_VF" "$VF_ITALIC_PATH"
else
  echo "   WARNING: No italic VF found in $OUT_VF"
fi

# Patch statics naming and italic STAT cleanup
if compgen -G "$OUT_TTF/*.ttf" > /dev/null; then
  echo "   Patching static names"
  python3 "$PATCH_STATIC_NAMES"
  echo "   Patching static italic STAT"
  python3 "$PATCH_STATIC_ITALIC_STAT"
else
  echo "   WARNING: No static TTFs found in $OUT_TTF"
fi

# 4B) Add identity avar to VFs (if missing)
echo "== 4B. Ensuring identity avar for VFs (if missing) =="
python3 - <<'PY'
from fontTools.ttLib import TTFont, newTable
import glob

for path in glob.glob("fonts/variable/*.ttf"):
    f = TTFont(path)
    if "fvar" not in f:
        print("Skipping (no fvar):", path)
        continue
    if "avar" in f:
        print("OK (has avar):", path)
        continue

    avar = newTable("avar")
    avar.segments = {}
    for axis in f["fvar"].axes:
        avar.segments[axis.axisTag] = {-1.0: -1.0, 0.0: 0.0, 1.0: 1.0}

    f["avar"] = avar
    f.save(path)
    print("Added identity avar:", path)
PY

# 4C) Add meta dlng/slng for VFs
echo "== 4C. Ensuring meta dlng/slng for VFs =="
python3 - <<'PY'
from fontTools.ttLib import TTFont, newTable
import glob

DLNG = "Latn"
SLNG = "Latn"

for path in glob.glob("fonts/variable/*.ttf"):
    tt = TTFont(path)
    if "meta" not in tt:
        tt["meta"] = newTable("meta")
        tt["meta"].data = {}

    tt["meta"].data[b"dlng"] = DLNG.encode("utf-8")
    tt["meta"].data[b"slng"] = SLNG.encode("utf-8")

    tt.save(path)
    print("OK meta dlng/slng:", path)
PY

# ---------------------------------------------------------------------------
# 5. FontBakery (offline)
# ---------------------------------------------------------------------------
echo "== 5. Running FontBakery checks (offline) =="

VF_FILES=$(find "$OUT_VF" -maxdepth 1 -name "*.ttf" || true)
STATIC_FILES=$(find "$OUT_TTF" -maxdepth 1 -name "*.ttf" || true)

if [ -n "$VF_FILES" ]; then
  fontbakery check-googlefonts --skip-network --loglevel WARN \
    -o report-vf.md $VF_FILES || true
fi

if [ -n "$STATIC_FILES" ]; then
  fontbakery check-googlefonts --skip-network --loglevel WARN \
    -o report-static.md $STATIC_FILES || true
fi

echo
echo "---------------------------------------------"
echo "DONE!"
echo "Outputs:"
echo "• Variable fonts: $OUT_VF"
echo "• Static fonts:   $OUT_TTF"
echo "• Webfonts:       $OUT_WEB"
echo "Reports:"
echo "• report-static.md"
echo "• report-vf.md"
