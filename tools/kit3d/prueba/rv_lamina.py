"""Sheets of the clean renders of `interiores.tscn -- --rv` (docs/interior3d.md, «Revisión de los edificios de oficio»):
  python3 tools/rv_lamina.py <shots folder>
    rv_<type>.png              a row per level: the ground floor and each floor above (rv_<type>_n<level>_p<floor>.png)
    rv_antes_despues_<type>.png  a row per level: before (rv_antes_...) and after, ground floor and first floor
Each cell carries its label (type, level, floor) in a band above the picture."""
import glob, os, re, sys
from PIL import Image, ImageDraw, ImageFont

folder = sys.argv[1]
CELL = (800, 450)
BAND = 34
NAMES = {"forge": "Forja", "carpentry": "Carpintería", "tailor_shop": "Sastrería", "bakery": "Panadería", "tavern_inn": "Taberna", "masonry": "Cantería",
         "bank": "Banco", "clinic": "Clínica", "armory": "Armería", "farm": "Granja", "den": "Guarida",
         "house_humble": "Casa humilde", "house_well": "Casa acomodada", "house_noble": "Casa noble", "town_hall": "Ayuntamiento"}
try:
    FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 22)
except OSError:
    FONT = ImageFont.load_default()


def shots(pre):
    """{type: {level: {floor: path}}}"""
    out = {}
    for f in glob.glob(os.path.join(folder, pre + "*_n?_p?.png")):
        m = re.match(re.escape(pre) + r"(.+)_n(\d)_p(\d)\.png$", os.path.basename(f))
        if not m or (pre == "rv_" and m.group(1).startswith("antes_")):
            continue
        out.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {})[int(m.group(3))] = f
    return out


def cell(sheet, path, x, y, label):
    d = ImageDraw.Draw(sheet)
    d.rectangle([x, y, x + CELL[0], y + BAND], fill=(28, 24, 20))
    d.text((x + 12, y + 5), label, fill=(240, 228, 205), font=FONT)
    if path and os.path.exists(path):
        sheet.paste(Image.open(path).convert("RGB").resize(CELL, Image.LANCZOS), (x, y + BAND))


after = shots("rv_")
before = shots("rv_antes_")
for t, levels in sorted(after.items()):
    name = NAMES.get(t, t)
    cols = max(len(fl) for fl in levels.values())
    lv = sorted(levels)
    sheet = Image.new("RGB", (CELL[0] * cols, (CELL[1] + BAND) * len(lv)), (20, 18, 16))
    for r, l in enumerate(lv):
        for c in range(cols):
            p = levels[l].get(c)
            if p:
                cell(sheet, p, c * CELL[0], r * (CELL[1] + BAND), "%s · nivel %d · %s" % (name, l, "planta baja" if c == 0 else "planta %d" % c))
    out = os.path.join(folder, "rv_%s.png" % t)
    sheet.save(out)
    print(out, sheet.size)
    if t in before:
        sheet = Image.new("RGB", (CELL[0] * 4, (CELL[1] + BAND) * len(lv)), (20, 18, 16))
        for r, l in enumerate(lv):
            for c, (src, fl, tag) in enumerate([(before, 0, "antes"), (after, 0, "después"), (before, 1, "antes"), (after, 1, "después")]):
                p = src.get(t, {}).get(l, {}).get(fl)
                if p:
                    cell(sheet, p, c * CELL[0], r * (CELL[1] + BAND), "%s · nivel %d · %s · %s" % (name, l, "planta baja" if fl == 0 else "planta 1", tag))
        out = os.path.join(folder, "rv_antes_despues_%s.png" % t)
        sheet.save(out)
        print(out, sheet.size)
