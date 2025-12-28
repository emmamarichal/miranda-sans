#!/usr/bin/env bash
set -euo pipefail

# Inställningar
FAMILY_DIR="ofl/mirandasans"
STATIC_DIR="$FAMILY_DIR/static"
VF_DIR="$FAMILY_DIR"
VF_ITALIC="${FAMILY_DIR}/MirandaSans-Italic[wght].ttf"

# 1. Bygg fonterna
echo "== 1. Bygger fonter =="
gftools builder sources/config.yaml

echo "== 2. Flyttar ut variabla fonter =="
# 2. Definiera var builder brukar lägga dem
VARIABLE_TTF_DIR="$FAMILY_DIR/variable_ttf"
VARIABLE_DIR="$FAMILY_DIR/variable"

# . Kolla om 'variable_ttf' finns och flytta
if [ -d "$VARIABLE_TTF_DIR" ]; then
    echo "   Hittade $VARIABLE_TTF_DIR. Flyttar filer..."
    mv "$VARIABLE_TTF_DIR"/*.ttf "$FAMILY_DIR/"
    rmdir "$VARIABLE_TTF_DIR"
#  Kolla om 'variable' finns och flytta
elif [ -d "$VARIABLE_DIR" ]; then
    echo "   Hittade $VARIABLE_DIR. Flyttar filer..."
    mv "$VARIABLE_DIR"/*.ttf "$FAMILY_DIR/"
    rmdir "$VARIABLE_DIR"
else
    echo "   VARNING: Hittade ingen 'variable'-mapp i $FAMILY_DIR."
    echo "   Innehåll i $FAMILY_DIR just nu:"
    ls -R "$FAMILY_DIR"
fi

# Ta bort outputs du inte vill ha
rm -rf "$FAMILY_DIR/otf" "$FAMILY_DIR/webfonts"

# Byt namn på ttf → static (om den finns)
[ -d "$FAMILY_DIR/ttf" ] && mkdir -p "$FAMILY_DIR/static" && mv "$FAMILY_DIR/ttf"/*.ttf "$FAMILY_DIR/static/" && rmdir "$FAMILY_DIR/ttf"


# 3. Standard gftools fix
# Körs före vår master-fix så att vi kan skriva över eventuella fel den gör
echo "== 2. Kör gftools fix-font =="
find "$FAMILY_DIR" -name "*.ttf" -exec gftools fix-font {} -o {} \;

# 4. Generera STAT-tabell
echo "== 3. Genererar STAT-tabell =="
gftools gen-stat --inplace --src sources/stat.yaml \
  "$VF_DIR/MirandaSans[wght].ttf" \
  "$VF_DIR/MirandaSans-Italic[wght].ttf"

# 5. Master-fix för namngivning och Italic-flaggor
echo "== 4. Fixar namn och metadata (RIBBI-standard) =="
STATIC_DIR="$STATIC_DIR" VF_DIR="$VF_DIR" python3 -c "
from fontTools.ttLib import TTFont
import os

def fix_metadata(path, is_static=False):
    font = TTFont(path)
    name_table = font['name']
    os2 = font['OS/2']
    head = font['head']
    filename = os.path.basename(path)
    
    family = 'Miranda Sans'
    is_italic = 'Italic' in filename
    is_bold = 'Bold' in filename
    
    # Bestäm subfamily för RIBBI
    if is_bold and is_italic: sub = 'Bold Italic'
    elif is_bold: sub = 'Bold'
    elif is_italic: sub = 'Italic'
    else: sub = 'Regular'

    # 1. Fixa fsSelection och macStyle (Italic-flaggor)
    if is_italic:
        os2.fsSelection |= (1 << 0)   # Italic bit
        os2.fsSelection &= ~(1 << 6)  # Rensa Regular bit
        head.macStyle |= (1 << 1)     # Italic bit
    else:
        os2.fsSelection &= ~(1 << 0)
        os2.fsSelection |= (1 << 6)
        head.macStyle &= ~(1 << 1)

    # 2. För statiska filer: Tvinga RIBBI-namn (Ta bort ID 16/17)
    if is_static:
        name_table.removeNames(nameID=16)
        name_table.removeNames(nameID=17)
        
        # Plattformar: Windows (3,1,1033) och Mac (1,0,0)
        for p_id, e_id, l_id in [(3, 1, 1033), (1, 0, 0)]:
            # NameID 1: Family Name
            name_table.setName(family, 1, p_id, e_id, l_id)
            # NameID 2: Subfamily Name
            name_table.setName(sub, 2, p_id, e_id, l_id)
            # NameID 4: Full Name
            full_name = f'{family} {sub}'.replace(' Regular', '')
            name_table.setName(full_name, 4, p_id, e_id, l_id)
            # NameID 6: Postscript Name (Får inte ha mellanslag)
            ps_name = f'MirandaSans-{sub}'.replace(' ', '')
            name_table.setName(ps_name, 6, p_id, e_id, l_id)

    font.save(path)
    print(f'   Fixad: {filename} -> ({sub})')

# Kör på statics
if os.path.exists(os.environ['STATIC_DIR']):
    for f in os.listdir(os.environ['STATIC_DIR']):
        if f.endswith('.ttf'):
            fix_metadata(os.path.join(os.environ['STATIC_DIR'], f), is_static=True)

# Kör på Variable Fonts
if os.path.exists(os.environ['VF_DIR']):
    for f in os.listdir(os.environ['VF_DIR']):
        if '[wght].ttf' in f:
            fix_metadata(os.path.join(os.environ['VF_DIR'], f), is_static=False)
"


echo
echo "== Patch Italic VF names, flags, STAT strings (in-place) =="
python fix_italic_vf.py "$VF_ITALIC"


echo "== Patch static name table (GF compatible) =="

python3 - <<'PY'
from fontTools.ttLib import TTFont
import glob, os, sys

STATIC_DIR = "ofl/mirandasans/static"
FAMILY_NAME = "Miranda Sans"

def style_from_filename(path: str) -> str:
    base = os.path.splitext(os.path.basename(path))[0]
    if not base.startswith("MirandaSans-"):
        raise ValueError(f"Unexpected filename: {base}")
    token = base.replace("MirandaSans-", "")
    if token == "Regular":
        return "Regular"
    if token == "Italic":
        return "Italic"
    if token.endswith("Italic"):
        w = token[:-6].strip()
        return f"{w} Italic" if w else "Italic"
    return token

def set_name(name_table, nameID: int, value: str):
    updated = 0
    for r in name_table.names:
        if r.nameID == nameID and r.platformID == 3 and r.platEncID == 1 and r.langID == 0x0409:
            r.string = value.encode("utf-16be")
            updated += 1
    if updated == 0:
        name_table.setName(value, nameID, 3, 1, 0x0409)

ttfs = sorted(glob.glob(os.path.join(STATIC_DIR, "*.ttf")))
if not ttfs:
    print(f"No TTFs found in {STATIC_DIR}", file=sys.stderr)
    sys.exit(1)

for path in ttfs:
    font = TTFont(path)
    name = font["name"]
    style = style_from_filename(path)

    # Family must be constant for all statics
    set_name(name, 1,  FAMILY_NAME)
    set_name(name, 16, FAMILY_NAME)

    # Subfamily carries weight + italic
    set_name(name, 2,  style)
    set_name(name, 17, style)

    font.save(path)
    print(f"Patched: {os.path.basename(path)} -> {FAMILY_NAME} / {style}")
PY

echo
echo "== Patch names issues for static fonts =="
python patch_static_names.py

# 8. Kör FontBakery check
echo "== 5. Kör FontBakery check =="
# Hitta VF-filer (hanterar hakparenteser korrekt)
VF_FILES=$(find "$VF_DIR" -maxdepth 1 -name "*.ttf" | grep "\[wght\]" || true)

if [ -n "$VF_FILES" ]; then
    fontbakery check-googlefonts --skip-network --loglevel FAIL -o report-vf.md $VF_FILES || true
fi

# Kör check på statiska filer
fontbakery check-googlefonts --skip-network --loglevel FAIL -o report-static.md "$STATIC_DIR"/*.ttf || true


echo "---"
echo "KLART! Rapporter genererade:"
echo "Static: report-static.md"
echo "VF:     report-vf.md"
