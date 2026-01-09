#!/usr/bin/env python3
"""
patch_italic_vf_metadata.py

What this script does
---------------------
This script patches Miranda Sans output fonts after build:

A) Naming (name table)
   - Ensures the Italic variable font uses:
       nameID 1 = "Miranda Sans"
       nameID 2 = "Italic"
       nameID 4 = "Miranda Sans Italic"
       nameID 6 = "MirandaSans-Italic"
   - Optionally patches static italic fonts in /static based on filename logic.
   - Removes nameID 16/17 (typographic family/subfamily) for RIBBI styles
     to avoid conflicts in app menus.

B) Italic technical fields
   - Sets post.italicAngle to a non-zero value for italic fonts.
   - Normalizes STAT AxisValue Flags for ital axis values:
       value 0.0 → Flags = 2 (Elidable)
       value 1.0 → Flags = 0

This is meant to run after:
- gftools builder
- gftools fix-font
- gftools gen-stat
As part of build_fonts.sh script
"""

from __future__ import annotations

from fontTools.ttLib import TTFont
from pathlib import Path
import os


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
FAMILY_BASE = "Miranda Sans"

VF_ITALIC_PATH = Path("fonts/variable/MirandaSans-Italic[wght].ttf")
STATIC_DIR = Path("fonts/ttf/")

ITALIC_ANGLE = -10.0  # Current angle of italics


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def patch_name_table(font: TTFont, family_name: str, subfamily_name: str, is_ribbi: bool) -> None:
    """
    Patch nameIDs (1,2,4,6) across all existing name records.

    If is_ribbi=True:
      - remove nameIDs 16/17 entirely
    """
    name_table = font["name"]

    # Remove typographic IDs to avoid clashes (RIBBI styles should not use these)
    if is_ribbi:
        name_table.removeNames(nameID=16)
        name_table.removeNames(nameID=17)

    # Update every existing record for IDs 1/2/4/6
    for record in list(name_table.names):
        if record.nameID == 1:
            record.string = family_name.encode(record.getEncoding())

        elif record.nameID == 2:
            record.string = subfamily_name.encode(record.getEncoding())

        elif record.nameID == 4:
            full_name = f"{family_name} {subfamily_name}".replace(" Regular", "")
            record.string = full_name.encode(record.getEncoding())

        elif record.nameID == 6:
            # PostScript name must not contain spaces.
            # For Regular, we drop "-Regular" style suffix where appropriate.
            ps_name = f"{family_name}-{subfamily_name}".replace(" ", "").replace("Regular", "")
            if ps_name.endswith("-"):
                ps_name = ps_name[:-1]
            record.string = ps_name.encode(record.getEncoding())


def patch_italic_technicals(font: TTFont, is_italic: bool) -> None:
    """
    Patch italicAngle and STAT flags if present.
    """
    # 1) post.italicAngle must be non-zero for italic fonts
    if is_italic and "post" in font:
        font["post"].italicAngle = ITALIC_ANGLE

    # 2) STAT flags for ital axis values
    if "STAT" in font:
        stat = font["STAT"].table
        if getattr(stat, "AxisValueArray", None) and stat.AxisValueArray.AxisValue:
            for val in stat.AxisValueArray.AxisValue:
                # Some AxisValue formats store Value on the object.
                if hasattr(val, "Value"):
                    if val.Value == 1.0:
                        val.Flags = 0  # Italic value, not elidable
                    elif val.Value == 0.0:
                        val.Flags = 2  # Upright value should be elidable


def infer_static_names_from_filename(filename: str) -> tuple[str, str, bool]:
    """
    Your existing naming logic for static fonts.
    Returns (family_name, subfamily_name, is_ribbi_style)
    """
    is_italic = "Italic" in filename
    is_bold = "Bold" in filename
    is_semibold = "SemiBold" in filename
    is_medium = "Medium" in filename

    # RIBBI styles:
    # Regular / Italic / Bold / Bold Italic
    if (not is_semibold) and (not is_medium):
        is_ribbi = True
        family_name = FAMILY_BASE

        if is_bold and is_italic:
            subfamily_name = "Bold Italic"
        elif is_bold:
            subfamily_name = "Bold"
        elif is_italic:
            subfamily_name = "Italic"
        else:
            subfamily_name = "Regular"

        return family_name, subfamily_name, is_ribbi

    # Non-RIBBI statics (Medium, SemiBold etc)
    is_ribbi = False
    if is_semibold:
        family_name = f"{FAMILY_BASE} SemiBold"
        subfamily_name = "Italic" if is_italic else "Regular"
    elif is_medium:
        family_name = f"{FAMILY_BASE} Medium"
        subfamily_name = "Italic" if is_italic else "Regular"
    else:
        # fallback
        family_name = FAMILY_BASE
        subfamily_name = "Italic" if is_italic else "Regular"

    return family_name, subfamily_name, is_ribbi


# ---------------------------------------------------------------------------
# Patching functions
# ---------------------------------------------------------------------------
def patch_one_font(path: Path, is_variable_italic: bool = False) -> None:
    """
    Patch one font file in-place.
    """
    font = TTFont(str(path))
    filename = path.name

    if is_variable_italic:
        # Variable italic: always force these names
        family_name = FAMILY_BASE
        subfamily_name = "Italic"
        is_ribbi_style = True  # treat as RIBBI-style name behavior
    else:
        family_name, subfamily_name, is_ribbi_style = infer_static_names_from_filename(filename)

    # Patch naming
    patch_name_table(font, family_name, subfamily_name, is_ribbi=is_ribbi_style)

    # Patch technical italic-related items
    is_italic = "Italic" in filename or is_variable_italic
    patch_italic_technicals(font, is_italic=is_italic)

    font.save(str(path))
    print(f"Patched: {filename} -> nameID1='{family_name}', nameID2='{subfamily_name}'")


def main() -> None:
    # 1) Patch Italic VF
    if VF_ITALIC_PATH.exists():
        patch_one_font(VF_ITALIC_PATH, is_variable_italic=True)
    else:
        print(f"WARNING: VF italic not found: {VF_ITALIC_PATH}")

    # 2) Patch static italic fonts (only italics in /static)
    if STATIC_DIR.exists():
        for p in sorted(STATIC_DIR.glob("*.ttf")):
            if "Italic" in p.name:
                patch_one_font(p, is_variable_italic=False)
    else:
        print(f"WARNING: static dir not found: {STATIC_DIR}")


if __name__ == "__main__":
    main()
