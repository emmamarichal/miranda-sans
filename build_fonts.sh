#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Miranda Sans – Build & QA Pipeline
#
# This script:
# 1. Builds variable and static fonts using gftools + config.yaml
# 2. Normalizes the output folder structure to Google Fonts expectations
# 3. Removes unwanted build artifacts (OTF, webfonts, temp dirs)
# 4. Applies standard gftools fixes
# 5. Generates and patches STAT tables
# 6. Enforces correct RIBBI-style naming and flags
# 7. Runs FontBakery checks (offline-safe)
#
# The end result is a GF-ready folder structure:
# ofl/mirandasans/
# ├── MirandaSans[wght].ttf
# ├── MirandaSans-Italic[wght].ttf
# └── static/
#     ├── MirandaSans-Regular.ttf
#     ├── MirandaSans-Italic.ttf
#     ├── MirandaSans-Medium.ttf
#     ├── MirandaSans-MediumItalic.ttf
#     ├── MirandaSans-SemiBold.ttf
#     ├── MirandaSans-SemiBoldItalic.ttf
#     ├── MirandaSans-Bold.ttf
#     └── MirandaSans-BoldItalic.ttf
###############################################################################

# ---------------------------------------------------------------------------
# Global paths
# ---------------------------------------------------------------------------
FAMILY_DIR="ofl/mirandasans"
STATIC_DIR="$FAMILY_DIR/static"
VF_DIR="$FAMILY_DIR"
VF_ITALIC="$FAMILY_DIR/MirandaSans-Italic[wght].ttf"

# ---------------------------------------------------------------------------
# 1. Build fonts using gftools builder
# ---------------------------------------------------------------------------
echo "== 1. Building fonts via gftools builder (sources/config.yaml) =="
gftools builder sources/config.yaml

# ---------------------------------------------------------------------------
# 2. Normalize builder output
#
# gftools builder may place variable fonts in:
# - ofl/mirandasans/variable_ttf
# - ofl/mirandasans/variable
#
# We move all variable TTFs into the family root.
# ---------------------------------------------------------------------------
echo "== 2. Normalizing variable font output locations =="

VARIABLE_TTF_DIR="$FAMILY_DIR/variable_ttf"
VARIABLE_DIR="$FAMILY_DIR/variable"

if [ -d "$VARIABLE_TTF_DIR" ]; then
    echo "   Found $VARIABLE_TTF_DIR, moving variable fonts..."
    mv "$VARIABLE_TTF_DIR"/*.ttf "$FAMILY_DIR/"
    rmdir "$VARIABLE_TTF_DIR"

elif [ -d "$VARIABLE_DIR" ]; then
    echo "   Found $VARIABLE_DIR, moving variable fonts..."
    mv "$VARIABLE_DIR"/*.ttf "$FAMILY_DIR/"
    rmdir "$VARIABLE_DIR"

else
    echo "   WARNING: No variable font directory found."
    echo "   Current contents of $FAMILY_DIR:"
    ls -R "$FAMILY_DIR"
fi

# ---------------------------------------------------------------------------
# 3. Remove unwanted build artifacts
#
# Google Fonts does not want:
# - OTF output
# - Webfont output
# 
# Deactivate this if you want otf or webfonts to be generated
# ---------------------------------------------------------------------------
echo "== 3. Remove unwanted build artifacts =="
rm -rf "$FAMILY_DIR/otf" "$FAMILY_DIR/webfonts"

# ---------------------------------------------------------------------------
# 4. Move static TTFs into /static
#
# If builder produced a /ttf folder, convert it to /static
# ---------------------------------------------------------------------------
echo "== 4. Move static TTFs into /static =="
if [ -d "$FAMILY_DIR/ttf" ]; then
    mkdir -p "$STATIC_DIR"
    mv "$FAMILY_DIR/ttf"/*.ttf "$STATIC_DIR/"
    rmdir "$FAMILY_DIR/ttf"
fi

# ---------------------------------------------------------------------------
# 5. Apply standard gftools fix-font
#
# This fixes DSIG, fstype, gasp, and other low-level issues.
# We run this early so later steps can safely override metadata.
# ---------------------------------------------------------------------------
echo "== 5. Running gftools fix-font on all TTFs =="
find "$FAMILY_DIR" -name "*.ttf" -exec gftools fix-font {} -o {} \;

# ---------------------------------------------------------------------------
# 6. Generate STAT tables for variable fonts
# ---------------------------------------------------------------------------
echo "== 6. Generating STAT tables for variable fonts =="
gftools gen-stat --inplace --src sources/stat.yaml \
  "$VF_DIR/MirandaSans[wght].ttf" \
  "$VF_DIR/MirandaSans-Italic[wght].ttf"

# ---------------------------------------------------------------------------
# 7. Enforce correct metadata, flags, and naming
#
# - Fix fsSelection + macStyle bits
# - Force RIBBI naming for static fonts
# - Remove typographic name IDs (16/17) from statics
# ---------------------------------------------------------------------------
echo "== 7. Fixing names, flags, and metadata (RIBBI-compliant) =="

STATIC_DIR="$STATIC_DIR" VF_DIR="$VF_DIR" python3 - <<'PY'
from fontTools.ttLib import TTFont
import os

def fix_metadata(path, is_static=False):
    font = TTFont(path)
    name = font["name"]
    os2 = font["OS/2"]
    head = font["head"]
    filename = os.path.basename(path)

    family = "Miranda Sans"
    is_italic = "Italic" in filename
    is_bold = "Bold" in filename

    # Determine RIBBI subfamily
    if is_bold and is_italic:
        sub = "Bold Italic"
    elif is_bold:
        sub = "Bold"
    elif is_italic:
        sub = "Italic"
    else:
        sub = "Regular"

    # Fix fsSelection + macStyle bits
    if is_italic:
        os2.fsSelection |= (1 << 0)
        os2.fsSelection &= ~(1 << 6)
        head.macStyle |= (1 << 1)
    else:
        os2.fsSelection &= ~(1 << 0)
        os2.fsSelection |= (1 << 6)
        head.macStyle &= ~(1 << 1)

    # Static fonts must use pure RIBBI naming
    if is_static:
        name.removeNames(nameID=16)
        name.removeNames(nameID=17)

        for p, e, l in [(3, 1, 1033), (1, 0, 0)]:
            name.setName(family, 1, p, e, l)
            name.setName(sub, 2, p, e, l)
            full = f"{family} {sub}".replace(" Regular", "")
            name.setName(full, 4, p, e, l)
            ps = f"MirandaSans-{sub}".replace(" ", "")
            name.setName(ps, 6, p, e, l)

    font.save(path)
    print(f"   Fixed: {filename} → {sub}")

# Run on statics
if os.path.isdir(os.environ["STATIC_DIR"]):
    for f in os.listdir(os.environ["STATIC_DIR"]):
        if f.endswith(".ttf"):
            fix_metadata(os.path.join(os.environ["STATIC_DIR"], f), True)

# Run on variable fonts
for f in os.listdir(os.environ["VF_DIR"]):
    if "[wght].ttf" in f:
        fix_metadata(os.path.join(os.environ["VF_DIR"], f), False)
PY

# ---------------------------------------------------------------------------
# 8. Patch Italic variable font specifics
# ---------------------------------------------------------------------------
echo
echo "== 6. Patching Italic variable font (names, flags, STAT) =="
python patch_italic_vf_metadata.py "$VF_ITALIC"

# ---------------------------------------------------------------------------
# 9. Final static name normalization (GF compatibility)
# ---------------------------------------------------------------------------
echo
echo "== 9A. Final static name table cleanup =="
python patch_static_names.py
echo "== 9B. Final static name table cleanup =="
python patch_static_italic_stat.py

# ---------------------------------------------------------------------------
# 10. FontBakery checks (offline)
# ---------------------------------------------------------------------------
echo "== 10. Running FontBakery checks =="

VF_FILES=$(find "$VF_DIR" -maxdepth 1 -name "*[[]wght[]].ttf" || true)

if [ -n "$VF_FILES" ]; then
    fontbakery check-googlefonts --skip-network --loglevel WARN \
        -o report-vf.md $VF_FILES || true
fi

fontbakery check-googlefonts --skip-network --loglevel WARN \
    -o report-static.md "$STATIC_DIR"/*.ttf || true

echo
echo "---------------------------------------------"
echo "DONE!"
echo "Reports generated:"
echo "• Static fonts: report-static.md"
echo "• Variable fonts: report-vf.md"
