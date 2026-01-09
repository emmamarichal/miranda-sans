#!/usr/bin/env python3
"""
patch_static_fonts.py

What this script does (simple explanation)
------------------------------------------
This script patches your *static* TTF files in:

    fonts/ttf/

For each known filename (Regular, Italic, Bold, etc) it forces:

1) Name table values (nameIDs)
   - nameID 1, 2, 4, 6 are set exactly as defined in the WANTED mapping
   - nameID 16 and 17 are either set (for non-RIBBI weights like Medium/SemiBold)
     or removed entirely (for RIBBI styles like Regular/Bold/Italic/BoldItalic)

2) Style bits
   - OS/2.fsSelection bits (Regular/Bold/Italic)
   - head.macStyle bits (Bold/Italic)

3) A minimal STAT table
   - Adds wght axis with the correct weight name (never containing "Italic")
   - Adds ital axis with a proper linkedValue (0 <-> 1) so FontBakery stops
     complaining about missing / wrong linkedValue

IMPORTANT
---------
This is intentionally explicit: each filename has a hardcoded desired outcome.
No "smart inference", just "if the file is X, enforce Y".

Run:
    python3 patch_static_fonts.py
"""

from fontTools.ttLib import TTFont
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
STATIC_DIR = Path("fonts/ttf")

# Hardcoded desired state per file
# - w: weight value used for STAT 'wght'
# - ids: name table targets (nameIDs 1,2,4,6,16,17)
# - bits: desired style bits for Regular/Bold/Italic
WANTED = {
    "MirandaSans-Regular.ttf": {
        "w": 400,
        "ids": {1: "Miranda Sans", 2: "Regular", 4: "Miranda Sans Regular", 6: "MirandaSans-Regular", 16: None, 17: None},
        "bits": {"r": True, "b": False, "i": False},
    },
    "MirandaSans-Italic.ttf": {
        "w": 400,
        "ids": {1: "Miranda Sans", 2: "Italic", 4: "Miranda Sans Italic", 6: "MirandaSans-Italic", 16: None, 17: None},
        "bits": {"r": False, "b": False, "i": True},
    },
    "MirandaSans-Bold.ttf": {
        "w": 700,
        "ids": {1: "Miranda Sans", 2: "Bold", 4: "Miranda Sans Bold", 6: "MirandaSans-Bold", 16: None, 17: None},
        "bits": {"r": False, "b": True, "i": False},
    },
    "MirandaSans-BoldItalic.ttf": {
        "w": 700,
        "ids": {1: "Miranda Sans", 2: "Bold Italic", 4: "Miranda Sans Bold Italic", 6: "MirandaSans-BoldItalic", 16: None, 17: None},
        "bits": {"r": False, "b": True, "i": True},
    },
    "MirandaSans-Medium.ttf": {
        "w": 500,
        "ids": {1: "Miranda Sans Medium", 2: "Regular", 4: "Miranda Sans Medium", 6: "MirandaSans-Medium", 16: "Miranda Sans", 17: "Medium"},
        "bits": {"r": True, "b": False, "i": False},
    },
    "MirandaSans-MediumItalic.ttf": {
        "w": 500,
        "ids": {1: "Miranda Sans Medium", 2: "Italic", 4: "Miranda Sans Medium Italic", 6: "MirandaSans-MediumItalic", 16: "Miranda Sans", 17: "Medium Italic"},
        "bits": {"r": False, "b": False, "i": True},
    },
    "MirandaSans-SemiBold.ttf": {
        "w": 600,
        "ids": {1: "Miranda Sans SemiBold", 2: "Regular", 4: "Miranda Sans SemiBold", 6: "MirandaSans-SemiBold", 16: "Miranda Sans", 17: "SemiBold"},
        "bits": {"r": True, "b": False, "i": False},
    },
    "MirandaSans-SemiBoldItalic.ttf": {
        "w": 600,
        "ids": {1: "Miranda Sans SemiBold", 2: "Italic", 4: "Miranda Sans SemiBold Italic", 6: "MirandaSans-SemiBoldItalic", 16: "Miranda Sans", 17: "SemiBold Italic"},
        "bits": {"r": False, "b": False, "i": True},
    },
}

# Platforms we want name records for:
# - Windows Unicode BMP English (US)
# - Macintosh Roman English
PLATFORMS = [(3, 1, 0x0409), (1, 0, 0)]


# ---------------------------------------------------------------------------
# Name table helpers
# ---------------------------------------------------------------------------
def set_name(name_table, name_id: int, value: str) -> None:
    """Set a nameID value for Windows + Mac platforms."""
    for platform_id, enc_id, lang_id in PLATFORMS:
        name_table.setName(value, name_id, platform_id, enc_id, lang_id)


def patch_names(font: TTFont, ids_spec: dict) -> None:
    """
    Remove and re-add nameIDs according to ids_spec.
    If value is None -> the nameID is removed (and not re-added).
    """
    name_table = font["name"]

    for nid in (1, 2, 4, 6, 16, 17):
        val = ids_spec.get(nid)
        name_table.removeNames(nameID=nid)
        if val is not None:
            set_name(name_table, nid, val)


# ---------------------------------------------------------------------------
# Style bit helpers
# ---------------------------------------------------------------------------
def patch_style_bits(font: TTFont, r: bool, b: bool, i: bool) -> None:
    """
    Patch:
    - OS/2.fsSelection bits:
        bit0 = Italic
        bit5 = Bold
        bit6 = Regular
    - head.macStyle bits:
        bit0 = Bold
        bit1 = Italic
    """
    os2 = font["OS/2"]
    head = font["head"]

    IT = 1 << 0
    BO = 1 << 5
    RE = 1 << 6

    # OS/2 fsSelection
    fs = os2.fsSelection

    if r:
        # Regular means: set Regular, clear Italic + Bold
        fs = (fs | RE) & ~(IT | BO)
    else:
        # Not Regular: clear Regular, set/clear Bold+Italic
        fs &= ~RE
        fs = (fs | BO) if b else (fs & ~BO)
        fs = (fs | IT) if i else (fs & ~IT)

    os2.fsSelection = fs

    # head.macStyle (only Bold/Italic in the lowest two bits)
    ms = head.macStyle
    ms = (ms | 0b01) if b else (ms & ~0b01)
    ms = (ms | 0b10) if i else (ms & ~0b10)
    head.macStyle = ms


# ---------------------------------------------------------------------------
# STAT helper
# ---------------------------------------------------------------------------
def build_simple_stat(font: TTFont, wght_val: float, is_italic: bool, weight_name: str) -> None:
    """
    Build a minimal STAT table that is FontBakery-friendly.

    - wght axis:
        uses a clean weight name (never includes "Italic")
        makes Regular (400) elidable

    - ital axis:
        is boolean (0 or 1)
        uses linkedValue so Roman points to Italic and vice versa
        makes Roman elidable
    """
    from fontTools.otlLib.builder import buildStatTable

    ital_val = 1.0 if is_italic else 0.0
    linked = 0.0 if is_italic else 1.0  # key detail: always provide the opposite

    axes = [
        dict(
            tag="wght",
            name="Weight",
            values=[
                dict(
                    value=float(wght_val),
                    name=weight_name.replace(" Italic", ""),  # safety belt
                    flags=(0x2 if float(wght_val) == 400.0 else 0x0),  # Regular elidable
                )
            ],
        ),
        dict(
            tag="ital",
            name="Italic",
            values=[
                dict(
                    value=ital_val,
                    linkedValue=linked,                     # forces AxisValue format 3
                    name=("Italic" if is_italic else "Roman"),
                    flags=(0x2 if not is_italic else 0x0),  # Roman elidable
                )
            ],
        ),
    ]

    buildStatTable(font, axes)


# ---------------------------------------------------------------------------
# Patch one font
# ---------------------------------------------------------------------------
def patch_one_font(path: Path) -> None:
    filename = path.name
    spec = WANTED[filename]

    font = TTFont(str(path))

    # 1) Name table
    patch_names(font, spec["ids"])

    # 2) Style bits
    bits = spec["bits"]
    patch_style_bits(font, r=bits["r"], b=bits["b"], i=bits["i"])

    # 3) STAT
    # Weight name comes from nameID 17 if it exists, otherwise nameID 2.
    # For RIBBI fonts, nameID17 is None, so we fall back to nameID2.
    raw = spec["ids"].get(17) or spec["ids"][2]
    weight_name = raw.replace(" Italic", "")  # wght must never contain "Italic"
    build_simple_stat(font, spec["w"], bits["i"], weight_name)

    font.save(str(path))
    print(f"✅ Done: {filename}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    if not STATIC_DIR.exists():
        print(f"ERROR: Cannot find {STATIC_DIR}")
        return

    for fn in sorted(WANTED.keys()):
        p = STATIC_DIR / fn
        if p.exists():
            patch_one_font(p)
        else:
            print(f"⚠️  Missing file (skipped): {fn}")


if __name__ == "__main__":
    main()
