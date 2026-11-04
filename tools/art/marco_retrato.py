#!/usr/bin/env python3
"""Marco de cuadro de los retratos (PortraitFrame, docs/ui/00_lenguaje_visual.md): madera tallada con filete dorado y
tacos en las esquinas, con la paleta de plate_frame (el marco de la Lámina). Dibujado a mano con Pillow, gratis.

  python3 tools/art/marco_retrato.py [--sheet tmp/marco_retrato.png]

Escribe en assets/art/ui/portrait_frame/: frame_<tam>_<acabado>.png, tam s (38×38, listón 3, para el retrato de 32) y
l (76×76, listón 6, para el de 64); acabado gold (activo), wood (controlable) y dark (los demás). El centro es
transparente: PortraitFrame lo corta en 9 (márgenes = listón + taco) y nunca estira las esquinas.
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art", "ui", "portrait_frame")
D = "#1a1209"
FINISH = {  # moulding lit, moulding shade, wood, wood grain, liner lit, liner shade, ornament lit, ornament, shade
    "wood": ["#997651", "#5c3a1e", "#7a5230", "#5c3a1e", "#ddc067", "#a98c40", "#f2d880", "#c8a84e", "#8a7032"],
    "gold": ["#f2d880", "#a98c40", "#c8a84e", "#ddc067", "#f2d880", "#c8a84e", "#f2d880", "#ddc067", "#8a7032"],
    "dark": ["#997651", "#5c3a1e", "#6b4627", "#4d3119", "#a98c40", "#6b4627", "#c8a84e", "#a98c40", "#5c3a1e"],
}
SIZES = {"s": (38, 3), "l": (76, 6)}  # side, band
# the carved corner (top left; mirrored to the other three): D outline, H lit, G gold, s shade, . the frame below
CORNER = {
    "s": ["DDDDD",
          "DHGsD",
          "DGsD.",
          "DsD..",
          "DD..."],
    "l": ["DDDDDDDDD.",
          "DHHHGGGsD.",
          "DHGGGGsD..",
          "DHGHGsD...",
          "DGGGGD....",
          "DGGsGsD...",
          "DGsD.DsD..",
          "DsD...D...",
          "DD........",
          ".........."],
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


def frame(s, f):
    size, band = SIZES[s]
    lit, shade, wood, grain, llit, lshade, olit, omid, oshade = f
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    rings = ["outline", "moulding", "liner"] if band == 3 else ["outline", "moulding", "wood", "grain", "liner",
                                                                 "outline"]
    for k, kind in enumerate(rings):
        for x in range(k, size - k):
            for y in range(k, size - k):
                if min(x - k, y - k, size - 1 - k - x, size - 1 - k - y) != 0:
                    continue
                first = (y == k and x < size - 1 - k) or (x == k and y < size - 1 - k)  # top or left: lit
                c = {"outline": D, "moulding": lit if first else shade, "wood": wood,
                     "grain": lit if (x + y) % 6 == 0 else grain, "liner": llit if first else lshade}[kind]
                px[x, y] = rgb(c)
    pal = {"D": D, "H": olit, "G": omid, "s": oshade}
    for flip_x in (False, True):
        for flip_y in (False, True):
            for i, row in enumerate(CORNER[s]):
                for j, ch in enumerate(row):
                    if ch == ".":
                        continue
                    x = size - 1 - j if flip_x else j
                    y = size - 1 - i if flip_y else i
                    c = pal[ch]
                    if ch == "H" and (flip_x and flip_y):  # the light comes from the top left
                        c = oshade
                    px[x, y] = rgb(c)
    return im


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    made = []
    for s in SIZES:
        for name, f in FINISH.items():
            im = frame(s, f)
            p = os.path.join(OUT, f"frame_{s}_{name}.png")
            im.save(p)
            made.append(im)
    if "--sheet" in argv:
        out = argv[argv.index("--sheet") + 1]
        W = sum(m.width for m in made) + 10 * len(made)
        sh = Image.new("RGBA", (W, 80), (60, 90, 60, 255))
        x = 0
        for m in made:
            sh.alpha_composite(m, (x, 0))
            x += m.width + 10
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        sh.resize((sh.width * 4, sh.height * 4), Image.NEAREST).save(out)
    print("marco_retrato: " + ", ".join(f"frame_{s}_{n}.png" for s in SIZES for n in FINISH))


if __name__ == "__main__":
    main(sys.argv[1:])
