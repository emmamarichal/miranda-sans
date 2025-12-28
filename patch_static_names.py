#!/usr/bin/env python3
from fontTools.ttLib import TTFont
from pathlib import Path

# ---- KONFIG ----
STATIC_DIR = Path("ofl/mirandasans/static")

WANTED = {
    "MirandaSans-Regular.ttf":       {"w": 400, "ids": {1: "Miranda Sans", 2: "Regular", 4: "Miranda Sans Regular", 6: "MirandaSans-Regular", 16: None, 17: None}, "bits": {"r": True, "b": False, "i": False}},
    "MirandaSans-Italic.ttf":        {"w": 400, "ids": {1: "Miranda Sans", 2: "Italic", 4: "Miranda Sans Italic", 6: "MirandaSans-Italic", 16: None, 17: None}, "bits": {"r": False, "b": False, "i": True}},
    "MirandaSans-Bold.ttf":          {"w": 700, "ids": {1: "Miranda Sans", 2: "Bold", 4: "Miranda Sans Bold", 6: "MirandaSans-Bold", 16: None, 17: None}, "bits": {"r": False, "b": True, "i": False}},
    "MirandaSans-BoldItalic.ttf":    {"w": 700, "ids": {1: "Miranda Sans", 2: "Bold Italic", 4: "Miranda Sans Bold Italic", 6: "MirandaSans-BoldItalic", 16: None, 17: None}, "bits": {"r": False, "b": True, "i": True}},
    "MirandaSans-Medium.ttf":        {"w": 500, "ids": {1: "Miranda Sans Medium", 2: "Regular", 4: "Miranda Sans Medium", 6: "MirandaSans-Medium", 16: "Miranda Sans", 17: "Medium"}, "bits": {"r": True, "b": False, "i": False}},
    "MirandaSans-MediumItalic.ttf":  {"w": 500, "ids": {1: "Miranda Sans Medium", 2: "Italic", 4: "Miranda Sans Medium Italic", 6: "MirandaSans-MediumItalic", 16: "Miranda Sans", 17: "Medium Italic"}, "bits": {"r": False, "b": False, "i": True}},
    "MirandaSans-SemiBold.ttf":      {"w": 600, "ids": {1: "Miranda Sans SemiBold", 2: "Regular", 4: "Miranda Sans SemiBold", 6: "MirandaSans-SemiBold", 16: "Miranda Sans", 17: "SemiBold"}, "bits": {"r": True, "b": False, "i": False}},
    "MirandaSans-SemiBoldItalic.ttf":{"w": 600, "ids": {1: "Miranda Sans SemiBold", 2: "Italic", 4: "Miranda Sans SemiBold Italic", 6: "MirandaSans-SemiBoldItalic", 16: "Miranda Sans", 17: "SemiBold Italic"}, "bits": {"r": False, "b": False, "i": True}},
}

def set_name(name_table, name_id, value):
    for p, e, l in [(3, 1, 0x409), (1, 0, 0)]:
        name_table.setName(value, name_id, p, e, l)

def build_simple_stat(font, wght_val: float, is_italic: bool, weight_name: str):
    """
    Bygger en minimal STAT med:
    - wght axis: en value (t.ex. 500 -> "Medium"), aldrig "Italic" i namnet
    - ital axis: en value (0 eller 1) med linkedValue satt till motsatsen (0<->1)
      så FontBakery får expected linkedValue och slutar klaga.
    """
    from fontTools.otlLib.builder import buildStatTable

    ital_val = 1.0 if is_italic else 0.0
    linked = 0.0 if is_italic else 1.0  # viktigt: Roman pekar mot Italic, Italic pekar mot Roman

    axes = [
        dict(
            tag="wght",
            name="Weight",
            values=[
                dict(
                    value=float(wght_val),
                    name=weight_name.replace(" Italic", ""),  # säkerhetsbälte
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
                    linkedValue=linked,                        # detta gör AxisValue format 3
                    name=("Italic" if is_italic else "Roman"),
                    flags=(0x2 if not is_italic else 0x0),     # Roman elidable
                )
            ],
        ),
    ]

    buildStatTable(font, axes)


def patch_one_font(path: Path):
    filename = path.name
    spec = WANTED[filename]
    font = TTFont(str(path))
    
    # 1) Namn-tabell
    name_table = font["name"]
    for nid in (1, 2, 4, 6, 16, 17):
        val = spec["ids"].get(nid)
        name_table.removeNames(nameID=nid)
        if val is not None:
            set_name(name_table, nid, val)

    # 2) Bitar (fsSelection & macStyle)
    b, i, r = spec["bits"]["b"], spec["bits"]["i"], spec["bits"]["r"]
    
    # OS/2 fsSelection
    fs = font['OS/2'].fsSelection
    if r: fs = (fs | (1 << 6)) & ~((1 << 0) | (1 << 5))
    else:
        fs &= ~(1 << 6)
        if b: fs |= (1 << 5)
        else: fs &= ~(1 << 5)
        if i: fs |= (1 << 0)
        else: fs &= ~(1 << 0)
    font['OS/2'].fsSelection = fs

    # head macStyle
    ms = font['head'].macStyle
    if b: ms |= (1 << 0)
    else: ms &= ~(1 << 0)
    if i: ms |= (1 << 1)
    else: ms &= ~(1 << 1)
    font['head'].macStyle = ms

    # 3) STAT (måste vara kompatibelt)
    # Vikt-namnet tar vi från nameID17 om det finns, annars nameID2.
    # Men om nameID17 är None (RIBBI), då tar vi nameID2.
    raw = spec["ids"].get(17) or spec["ids"][2]
    weight_name = raw.replace(" Italic", "")  # wght får aldrig ha "Italic" i namnet

    build_simple_stat(font, spec["w"], i, weight_name)


    font.save(str(path))
    print(f"✅ Klart: {filename}")

def main():
    if not STATIC_DIR.exists():
        print(f"Hittar inte {STATIC_DIR}"); return
    for fn in sorted(WANTED.keys()):
        p = STATIC_DIR / fn
        if p.exists(): patch_one_font(p)

if __name__ == "__main__":
    main()