#!/usr/bin/env python3
"""Láminas del rediseño de la ciudad: antes y después con la misma cámara (reports/shots/rediseno_<antes|despues>_
<sitio>_<dia|tarde>.png de --smoke-script=rediseno) y la hoja del arte nuevo junto al personaje y una casa.

Uso: python3 tools/art/laminas_rediseno.py <carpeta de salida> [--novedades]
  -> rediseno_pueblo_dia.png, rediseno_pueblo_tarde.png, rediseno_capital_dia.png, rediseno_capital_tarde.png,
     rediseno_hoja_arte.png, rediseno_hoja_monumentos.png
  --novedades: además, copias reducidas en docs/novedades/ (rediseno_*.png).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHOTS = os.path.join(ROOT, "reports", "shots")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PUEBLO = [("pueblo_general", "vista general"), ("pueblo_plaza", "plaza y mercado"), ("pueblo_barrio", "un barrio"),
          ("pueblo_rio", "río y puente"), ("pueblo_afueras", "afueras")]
CAPITAL = [("capital_general", "capital: vista general"), ("capital_plaza", "capital: plaza"),
           ("capital_catedral", "capital: catedral y muralla")]
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def pairs(places, when, out):
    w, h = 960, 540
    bar = 40
    sheet = Image.new("RGB", (2 * w + 20, len(places) * (h + bar)), (26, 20, 15))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(FONT, 26)
    for i, (place, label) in enumerate(places):
        y = i * (h + bar)
        for j, tag in enumerate(("antes", "despues")):
            p = os.path.join(SHOTS, f"rediseno_{tag}_{place}_{when}.png")
            im = Image.open(p).convert("RGB").resize((w, h), Image.LANCZOS)
            sheet.paste(im, (j * (w + 20), y + bar))
            d.text((j * (w + 20) + 10, y + 6), f"{'ANTES' if j == 0 else 'DESPUÉS'} · {label} · "
                   f"{'día' if when == 'dia' else 'atardecer'}", fill=(240, 228, 200), font=f)
    sheet.save(out)
    print(out)


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    made = []
    for when in ("dia", "tarde"):
        for name, places in (("pueblo", PUEBLO), ("capital", CAPITAL)):
            p = os.path.join(out_dir, f"rediseno_{name}_{when}.png")
            pairs(places, when, p)
            made.append(p)
    import fal_rediseno as fr
    groups = [s for s in fr.SHEETS if not s.startswith(("catedral", "iglesia", "aduana", "almacen", "lonja", "torres",
                                                         "muralla"))]
    p = os.path.join(out_dir, "rediseno_hoja_arte.png")
    fr.hoja(groups, out=p)
    made.append(p)
    p = os.path.join(out_dir, "rediseno_hoja_monumentos.png")
    fr.hoja(["catedral", "iglesia", "aduana", "almacen", "lonja", "torres", "muralla_grua"], out=p, width=1400)
    made.append(p)
    if "--novedades" in sys.argv:
        nd = os.path.join(ROOT, "docs", "novedades")
        for p in made:
            im = Image.open(p)
            k = min(1.0, 1600 / im.width)
            im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS if k < 1 else Image.NEAREST)
            dst = os.path.join(nd, os.path.basename(p))
            im.convert("RGB").save(dst, optimize=True)
            print(dst)


if __name__ == "__main__":
    main()
