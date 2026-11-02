#!/usr/bin/env python3
"""Logotipo «GuildMaster» en pixel art, dibujado con Pillow sobre la letra gótica pixel Jacquard 24 (OFL) a su tamaño
nativo (43 px, sin suavizado): relleno de oro en tres franjas, contorno de 1 px, sombra de madera y una regla con
rombos debajo. Es el único texto dentro de una imagen (el nombre del juego); el resto sale de i18n.

  python3 tools/ui/logo.py      → assets/art/ui/logo/guildmaster_logo.png (1×) y _x2.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art", "ui", "logo")
FONT = os.path.join(ROOT, "assets", "art", "ui", "fonts", "jacquard_24.ttf")


def hexc(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


GOLD_LIGHT, GOLD, GOLD_DARK = hexc("f2d880"), hexc("c8a84e"), hexc("8a7032")
INK, SHADOW, WOOD = hexc("1a1209"), hexc("3e2814"), hexc("5c3a1e")


def grow(mask, n=1):
    """Dilata una máscara 1-bit n píxeles en cruz (contorno de pixel art, sin esquinas redondeadas)."""
    w, h = mask.size
    src = mask.load()
    out = Image.new("1", (w, h), 0)
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y]:
                for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                    if 0 <= x + dx < w and 0 <= y + dy < h:
                        dst[x + dx, y + dy] = 1
    return grow(out, n - 1) if n > 1 else out


def logo(text="GuildMaster"):
    f = ImageFont.truetype(FONT, 43)
    l, t, r, b = f.getbbox(text)
    pad = 6
    w, h = r - l + pad * 2, b - t + pad * 2 + 10
    mask = Image.new("1", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.fontmode = "1"
    d.text((pad - l, pad - t), text, font=f, fill=1)
    top, bottom = pad, pad + (b - t)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px, m = img.load(), mask.load()
    outline = grow(mask, 1)
    shadow = Image.new("1", (w, h), 0)
    shadow.paste(outline, (2, 2))
    sh, ol = shadow.load(), outline.load()
    for y in range(h):
        for x in range(w):
            if sh[x, y]:
                px[x, y] = SHADOW
    for y in range(h):
        for x in range(w):
            if ol[x, y]:
                px[x, y] = INK
    for y in range(h):
        k = (y - top) / max(1, bottom - top)
        band = GOLD_LIGHT if k < 0.36 else (GOLD if k < 0.74 else GOLD_DARK)
        for x in range(w):
            if m[x, y]:
                px[x, y] = band
    # brillo de 1 px en el borde de arriba de cada trazo
    for y in range(1, h):
        for x in range(w):
            if m[x, y] and not m[x, y - 1] and y < (top + bottom) // 2:
                px[x, y] = hexc("fff0b8")
    # regla con rombos bajo el texto
    ry = bottom + 4
    x0, x1 = pad + 8, w - pad - 8
    for x in range(x0, x1):
        px[x, ry] = GOLD_DARK
        px[x, ry - 1] = INK
        px[x, ry + 1] = INK
    for cx in (x0, (x0 + x1) // 2, x1 - 1):
        for dx, dy, c in ((0, -2, INK), (-1, -1, INK), (1, -1, INK), (-2, 0, INK), (2, 0, INK), (-1, 1, INK), (1, 1, INK),
                          (0, 2, INK), (0, -1, GOLD_LIGHT), (-1, 0, GOLD), (0, 0, GOLD_LIGHT), (1, 0, GOLD), (0, 1, GOLD_DARK)):
            px[cx + dx, ry + dy] = c
    return img.crop(img.getbbox())


def main():
    os.makedirs(OUT, exist_ok=True)
    img = logo()
    img.save(os.path.join(OUT, "guildmaster_logo.png"))
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(os.path.join(OUT, "guildmaster_logo_x2.png"))
    print(f"  assets/art/ui/logo/guildmaster_logo.png {img.width}×{img.height} (+ _x2)")


if __name__ == "__main__":
    main()
