#!/usr/bin/env python3
from fontTools.ttLib import TTFont

FONT_PATH = "ofl/mirandasans/static/MirandaSans-Italic.ttf"

# We will add/use this nameID for the wght label (so it won't accidentally become "Italic")
NAMEID_WEIGHT_LABEL = 259
WEIGHT_LABEL_TEXT = "Regular"  # safe label for wght=400

def set_name(name_table, name_id: int, value: str):
    """
    Write the string for:
    - Windows: platform 3, encoding 1, lang 0x0409
    - Mac:     platform 1, encoding 0, lang 0
    """
    name_table.setName(value, name_id, 3, 1, 0x0409)
    name_table.setName(value, name_id, 1, 0, 0)

def main():
    font = TTFont(FONT_PATH)

    if "name" not in font:
        raise RuntimeError("No 'name' table found.")
    if "STAT" not in font:
        raise RuntimeError("No 'STAT' table found.")

    name = font["name"]
    stat = font["STAT"].table

    # 1) Ensure the extra nameID exists and says "Regular"
    set_name(name, NAMEID_WEIGHT_LABEL, WEIGHT_LABEL_TEXT)

    # 2) Patch the wght AxisValue to NOT reference nameID 2 (which is "Italic" in this font)
    # Find AxisIndex for 'wght' (usually 0)
    axis_records = stat.DesignAxisRecord.Axis
    wght_axis_index = None
    for idx, axis in enumerate(axis_records):
        if axis.AxisTag == "wght":
            wght_axis_index = idx
            break
    if wght_axis_index is None:
        raise RuntimeError("No 'wght' axis found in STAT.")

    # Patch AxisValues for wght
    patched = 0
    for av in stat.AxisValueArray.AxisValue:
        # Format 1 has AxisIndex + ValueNameID + Value
        # Format 2/3/4 differ, but your wght is currently Format 1.
        if getattr(av, "AxisIndex", None) == wght_axis_index:
            # This is the wght AxisValue entry
            av.ValueNameID = NAMEID_WEIGHT_LABEL
            patched += 1

    if patched == 0:
        raise RuntimeError("Did not find any STAT AxisValue for wght to patch.")

    # 3) Make elided fallback NOT be nameID 2 ("Italic")
    stat.ElidedFallbackNameID = NAMEID_WEIGHT_LABEL

    font.save(FONT_PATH)
    print(f"Done. Patched STAT wght label + fallback in: {FONT_PATH}")
    print(f"wght ValueNameID -> {NAMEID_WEIGHT_LABEL} ('{WEIGHT_LABEL_TEXT}')")
    print(f"ElidedFallbackNameID -> {NAMEID_WEIGHT_LABEL} ('{WEIGHT_LABEL_TEXT}')")

if __name__ == "__main__":
    main()
