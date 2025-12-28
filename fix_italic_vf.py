from fontTools.ttLib import TTFont
import os

# Sökvägar till dina mappar
vf_file = "ofl/mirandasans/MirandaSans-Italic[wght].ttf"
static_dir = "ofl/mirandasans/static"

def fix_font_metadata(path, is_vf=False):
    font = TTFont(path)
    name_table = font['name']
    filename = os.path.basename(path)
    
    # Grundinställningar
    family_base = "Miranda Sans"
    
    # Analysera stil baserat på filnamn
    is_italic = "Italic" in filename
    is_bold = "Bold" in filename
    is_semibold = "SemiBold" in filename
    is_medium = "Medium" in filename

    # --- LOGIK FÖR NAMNGIVNING ---
    
    if is_vf:
        # Variabel Italic ska ALLTID ha ID 1: "Miranda Sans" och ID 2: "Italic"
        family_name = family_base
        subfamily_name = "Italic"
    else:
        # Statiska fonter
        if is_semibold:
            family_name = f"{family_base} SemiBold"
            subfamily_name = "Italic" if is_italic else "Regular"
        elif is_medium:
            family_name = f"{family_base} Medium"
            subfamily_name = "Italic" if is_italic else "Regular"
        elif is_bold and is_italic:
            family_name = family_base
            subfamily_name = "Bold Italic"
        elif is_italic:
            family_name = family_base
            subfamily_name = "Italic"
        else:
            family_name = family_base
            subfamily_name = "Regular"

    # --- APPLICERA ÄNDRINGAR ---
    
    # Rensa Typographic Names (16/17) för att undvika konflikter i standardstilar
    if not (is_semibold or is_medium):
        name_table.removeNames(nameID=16)
        name_table.removeNames(nameID=17)

    # Uppdatera Name Records (ID 1, 2, 4, 6)
    for record in list(name_table.names):
        if record.nameID == 1:
            record.string = family_name.encode(record.getEncoding())
        elif record.nameID == 2:
            record.string = subfamily_name.encode(record.getEncoding())
        elif record.nameID == 4:
            # Full Name (ID 4) ska vara hela namnet
            full_name = f"{family_name} {subfamily_name}".replace(" Regular", "")
            record.string = full_name.encode(record.getEncoding())
        elif record.nameID == 6:
            # Postscript Name (ID 6) inga mellanslag
            ps_name = f"{family_name}-{subfamily_name}".replace(" ", "").replace("Regular", "")
            if ps_name.endswith("-"): ps_name = ps_name[:-1]
            record.string = ps_name.encode(record.getEncoding())

    font.save(path)
    print(f"Klar med: {filename} -> ID1: {family_name}, ID2: {subfamily_name}")

# 1. Fixa variabel-fonten
if os.path.exists(vf_file):
    fix_font_metadata(vf_file, is_vf=True)

# 2. Fixa alla statiska i mappen
if os.path.exists(static_dir):
    for f in os.listdir(static_dir):
        if f.endswith(".ttf") and "Italic" in f:
            fix_font_metadata(os.path.join(static_dir, f), is_vf=False)

def fix_technical_errors(path):
    font = TTFont(path)  # Här definieras 'font'
    
    # 1. Fixa Italic Angle (Löser FAIL: post.italicAngle should be non-zero)
    if "Italic" in path:
        font['post'].italicAngle = -10.0 
        
    # 2. Fixa STAT Flags (Löser FAIL: STAT table 'ital' axis with wrong flags)
    if 'STAT' in font:
        stat = font['STAT'].table
        if hasattr(stat, 'AxisValueArray') and stat.AxisValueArray:
            for val in stat.AxisValueArray.AxisValue:
                # Om värdet är 1.0 (Italic), ska Flags vara 0
                if hasattr(val, 'Value') and val.Value == 1.0:
                    val.Flags = 0
                # Om värdet är 0.0 (Upright), ska Flags vara 2 (Elidable)
                elif hasattr(val, 'Value') and val.Value == 0.0:
                    val.Flags = 2

    font.save(path)
    print(f"Tekniska fixar klara för: {os.path.basename(path)}")
    

# Kör fixen på din VF Italic
vf_italic_path = "ofl/mirandasans/MirandaSans-Italic[wght].ttf"
if os.path.exists(vf_italic_path):
    fix_technical_errors(vf_italic_path)