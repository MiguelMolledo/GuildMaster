#!/usr/bin/env python3
"""Marco de cuadro de los retratos (PortraitFrame, docs/ui/00_lenguaje_visual.md): madera tallada con filete dorado y
tacos en las esquinas, con la paleta de plate_frame (el marco de la Lámina). Dibujado a mano con Pillow, gratis.

  python3 tools/art/marco_retrato.py [--sheet tmp/marco_retrato.png]

Escribe en assets/art/ui/portrait_frame/: frame_<tam>_<acabado>.png, tam s (38×38, listón 3, para el retrato de 32) y
l (82×82, listón 9: moldura de cuentas, media caña, doble filete y tacos con diamante y hojas, para el de 64); acabado gold (activo), wood (controlable) y dark (los demás). El centro es
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
SIZES = {"s": (38, 3), "l": (82, 9)}  # side, band
# the carved corner of the small frame (top left; mirrored to the other three): D outline, H lit, G gold, s shade,
# . the frame below. The big one is drawn by code (big_corner): a carved block with a rosette and a leaf on each bar.
CORNER = {
    "s": ["DDDDD",
          "DHGsD",
          "DGsD.",
          "DsD..",
          "DD..."],
}
BLOCK = 13   # the big frame's corner block (band 9 + 4 into the portrait's corner, its background)
LEAF = 7     # the leaf that runs from the block along each bar


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


def frame(s, f):
    size, band = SIZES[s]
    lit, shade, wood, grain, llit, lshade, olit, omid, oshade = f
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    rings = ["outline", "moulding", "liner"] if band == 3 else ["outline", "moulding", "wood", "beads", "cove",
                                                                 "wood", "liner", "liner2", "outline"]
    for k, kind in enumerate(rings):
        for x in range(k, size - k):
            for y in range(k, size - k):
                if min(x - k, y - k, size - 1 - k - x, size - 1 - k - y) != 0:
                    continue
                first = (y == k and x < size - 1 - k) or (x == k and y < size - 1 - k)  # top or left: lit
                along = x if (y == k or y == size - 1 - k) else y
                bead = [lit, wood, grain, D][along % 4]  # bead and reel carved along the moulding
                c = {"outline": D, "moulding": lit if first else shade, "wood": wood, "beads": bead, "cove": grain,
                     "liner": llit if first else lshade, "liner2": lshade if first else oshade}[kind]
                px[x, y] = rgb(c)
    pal = {"D": D, "H": olit, "G": omid, "s": oshade}
    cmap = CORNER[s] if s in CORNER else big_corner()
    for flip_x in (False, True):
        for flip_y in (False, True):
            for i, row in enumerate(cmap):
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


def big_corner():
    """The big frame's corner, top left: a carved block (bevelled, a faceted diamond) and a tapering leaf along
    each bar, over the moulding."""
    n = BLOCK + LEAF
    g = [["."] * n for _ in range(n)]
    c = (BLOCK - 1) / 2.0
    for i in range(BLOCK):
        for j in range(BLOCK):
            if i in (0, BLOCK - 1) or j in (0, BLOCK - 1):
                v = "D"
            elif i == 1 or j == 1:
                v = "H"
            elif i == BLOCK - 2 or j == BLOCK - 2:
                v = "s"
            else:
                dy, dx = i - c, j - c
                m = abs(dx) + abs(dy)  # a faceted diamond, the motif of the kit's divider
                if m > 4.0:
                    v = "G"
                elif m > 3.0:
                    v = "D"
                elif m < 1.0:
                    v = "H"
                else:
                    v = "H" if dx + dy < 0 else ("s" if dx + dy > 0 else "G")
            g[i][j] = v
    # the leaves: along the top bar and down the left bar, over the moulding, tapering to a point, with a vein
    widths = [2, 2, 2, 1, 1, 1, 0]
    mid = 4
    for t in range(LEAF):
        half = widths[t]
        for r in range(mid - half - 1, mid + half + 2):
            if r in (mid - half - 1, mid + half + 1):
                v = "D"
            elif r == mid:
                v = "s" if t > 0 else "H"
            else:
                v = "H" if r < mid else "G"
            g[r][BLOCK + t] = v
            g[BLOCK + t][r] = v
        if half == 0:  # the point
            g[mid][BLOCK + t] = "D"
            g[BLOCK + t][mid] = "D"
    return ["".join(row) for row in g]


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
        sh = Image.new("RGBA", (W, 90), (60, 90, 60, 255))
        x = 0
        for m in made:
            sh.alpha_composite(m, (x, 0))
            x += m.width + 10
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        sh.resize((sh.width * 4, sh.height * 4), Image.NEAREST).save(out)
    print("marco_retrato: " + ", ".join(f"frame_{s}_{n}.png" for s in SIZES for n in FINISH))


if __name__ == "__main__":
    main(sys.argv[1:])
