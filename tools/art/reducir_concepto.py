#!/usr/bin/env python3
"""Prueba sin créditos (docs/arte/ciudad_con_pixellab.md): una casa recortada de la lámina E de fal, llevada a la
densidad del juego (la lámina se pintó sobre una maqueta de 960 px de ancho: 2752 / 960 = 2,87 px de lámina por píxel
de juego) con dos reducciones ingenuas, junto a un sprite del juego a 1:1. Enseña por qué reducir no basta.

Uso: python3 tools/art/reducir_concepto.py -> docs/arte/escala/15_prueba_reducir_concepto.png
"""
import glob
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "docs", "arte", "escala")
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"


def main():
    src = Image.open(glob.glob(os.path.join(ROOT, "assets", "concept", "ciudades2", "E_pueblo_calle",
                                            "E_pueblo_calle.png"))[0]).convert("RGBA")
    factor = src.width / 960.0
    crop = src.crop((1100, 690, 1670, 1420))  # la casa de dos plantas del centro
    gw, gh = round(crop.width / factor), round(crop.height / factor)
    near = crop.resize((gw, gh), Image.NEAREST)
    box = crop.resize((gw, gh), Image.BOX).convert("RGB").quantize(colors=24, method=Image.Quantize.MEDIANCUT,
                                                                  dither=Image.Dither.NONE).convert("RGBA")
    game = Image.open(os.path.join(ROOT, "assets", "art", "buildings", "house_b.png")).convert("RGBA")
    z = 3
    tiles = [("lámina fal (recorte, reducido para caber)", crop.resize((gw * z, gh * z), Image.LANCZOS)),
             (f"a densidad de juego, vecino más cercano ({gw}×{gh}) ×3", near.resize((gw * z, gh * z), Image.NEAREST)),
             ("a densidad de juego, caja + 24 colores ×3", box.resize((gw * z, gh * z), Image.NEAREST)),
             ("sprite del juego (house_b) ×3", game.resize((game.width * z, game.height * z), Image.NEAREST))]
    W = sum(t[1].width for t in tiles) + 50 * len(tiles)
    H = max(t[1].height for t in tiles) + 60
    sheet = Image.new("RGBA", (W, H), (43, 34, 27, 255))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(FONT, 15)
    x = 20
    for t, im in tiles:
        bg = Image.new("RGBA", im.size, (60, 60, 60, 255))
        bg.alpha_composite(im)
        sheet.alpha_composite(bg, (x, 40))
        d.text((x, 12), t, font=f, fill=(240, 228, 200))
        x += im.width + 50
    sheet.save(os.path.join(OUT, "15_prueba_reducir_concepto.png"))
    print("ok", gw, gh)


if __name__ == "__main__":
    main()
