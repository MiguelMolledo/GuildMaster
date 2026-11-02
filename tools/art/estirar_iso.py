#!/usr/bin/env python3
"""Prueba de escala sin créditos (docs/arte/escala.md): sube las plantas de una casa isométrica existente duplicando una
franja de filas que sigue la diagonal 2:1 de la base. No reescala: cada píxel sigue siendo un píxel del original.

Uso: python3 tools/art/estirar_iso.py   -> docs/arte/escala/14_prueba_estirar_plantas.png (+ los PNG sueltos en tmp/)
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "assets", "art")
OUT = os.path.join(ROOT, "docs", "arte", "escala")
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"


def insert_band(im, corner, h0, k):
    """Duplica k filas justo por debajo de la altura h0 (medida sobre la base de los muros), siguiendo la 2:1.

    corner: (x, y) de la esquina delantera de la base de los muros. Devuelve (imagen, nueva esquina)."""
    cx, cy = corner
    w, h = im.size
    out = Image.new("RGBA", (w, h + k), (0, 0, 0, 0))
    src = im.load()
    dst = out.load()
    for x in range(w):
        yc = cy - h0 - abs(x - cx) // 2
        yc = max(k, min(h, yc))
        col = [src[x, y] for y in range(h)]
        new = col[:yc] + col[yc - k:yc] + col[yc:]
        for y, p in enumerate(new):
            dst[x, y] = p
    return out, (cx, cy + k)


def unkey(im):
    px = im.load()
    look = ((70, 46, 28), (226, 180, 140), (150, 52, 40), (196, 160, 90))
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 254:
                base = look[min(max(int(round(b / 50.0)), 1), 4) - 1]
                kf = r / 127.5
                px[x, y] = (min(255, int(base[0] * kf)), min(255, int(base[1] * kf)), min(255, int(base[2] * kf)), 255)
    return im


def main():
    person = unkey(Image.open(os.path.join(ART, "characters", "artisan_m", "idle_s.png")).convert("RGBA").crop((0, 0, 68, 68)))
    cases = []
    # house_b: dos plantas de 34 px y puerta de 40 -> planta baja 50, alta 48, puerta 56
    hb = Image.open(os.path.join(ART, "buildings", "house_b.png")).convert("RGBA")
    a, c = insert_band(hb, (96, 167), 16, 16)
    a, c = insert_band(a, c, 66, 14)
    cases.append(("house_b hoy: plantas 34 + 34, puerta 40", hb, (96, 167), "estirada: plantas 50 + 48, puerta 56", a, c))
    # house (cabaña): muro 72, puerta 43 -> puerta 57
    h1 = Image.open(os.path.join(ART, "buildings", "house.png")).convert("RGBA")
    b, c2 = insert_band(h1, (91, 176), 18, 14)
    cases.append(("house hoy: puerta 43", h1, (91, 176), "estirada: puerta 57, muro 86", b, c2))
    tmpd = os.path.join(ROOT, "tmp", "estirar_iso")
    os.makedirs(tmpd, exist_ok=True)
    a.save(os.path.join(tmpd, "house_b_estirada.png"))
    b.save(os.path.join(tmpd, "house_estirada.png"))

    W, H = 1320, 300
    sheet = Image.new("RGBA", (W, H + 470), (43, 34, 27, 255))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(FONT, 13)
    x = 20
    base = H - 30
    for t1, i1, c1, t2, i2, cc in cases:
        for t, im, cr in ((t1, i1, c1), (t2, i2, cc)):
            sheet.alpha_composite(im, (x, base - cr[1]))
            sheet.alpha_composite(person, (x + cr[0] + 40, base - 58))
            d.text((x, base + 8), t, font=f, fill=(240, 228, 200))
            x += 300
    d.text((20, 10), "1:1 · se duplican filas a lo largo de la 2:1 (sin reescalar). Personaje de 48 px al lado.", font=f,
           fill=(240, 228, 200))
    # detalle ×3 de house_b estirada
    z = a.crop((20, 40, 180, a.height - 10))
    z = z.resize((z.width * 3, z.height * 3), Image.NEAREST)
    bg = Image.new("RGBA", z.size, (60, 60, 60, 255))
    bg.alpha_composite(z)
    sheet = sheet.crop((0, 0, max(W, bg.width + 40), H + bg.height + 30))
    full = Image.new("RGBA", sheet.size, (43, 34, 27, 255))
    full.alpha_composite(sheet)
    full.alpha_composite(bg, (20, H + 20))
    ImageDraw.Draw(full).text((bg.width + 30, H + 30), "detalle ×3 de la\nhouse_b estirada", font=f, fill=(240, 228, 200))
    full.save(os.path.join(OUT, "14_prueba_estirar_plantas.png"))
    print("ok")


if __name__ == "__main__":
    main()
