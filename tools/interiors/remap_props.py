#!/usr/bin/env python3
"""La misma paleta para el fondo y las piezas de cada interior (docs/gdd/04g_interiores.md §4.6.5.1): cada pieza de la
biblioteca que usa un interior se pasa a la paleta de sus fondos pintados (los room_*.png de todas sus plantas), color
a color, al más cercano en Lab si está a menos de THRESHOLD (madera, piedra, tela parda: el 85-90 % de los píxeles);
los acentos que el fondo no tiene (el rojo de un estandarte, el brillo de una armadura, la llama) se quedan como están.
Escribe assets/art/interiors/<edificio>/props/<id>.png, que el montador usa antes que la de la biblioteca
(game/visuals/visual_paths.gd interior_prop_in).

  python3 tools/interiors/remap_props.py [<edificio>...]
"""
import glob
import math
import os
import sys

from PIL import Image

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import interiores as I  # noqa: E402

ROOT = I.ROOT
THRESHOLD = 10.0


def lab(c):
    r, g, b = [v / 255 for v in c[:3]]
    f = lambda u: ((u + 0.055) / 1.055) ** 2.4 if u > 0.04045 else u / 12.92  # noqa: E731
    r, g, b = f(r), f(g), f(b)
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = r * 0.2126 + g * 0.7152 + b * 0.0722
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
    h = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116  # noqa: E731
    return (116 * h(y) - 16, 500 * (h(x) - h(y)), 200 * (h(y) - h(z)))


def used_props(d, cat):
    ids = set()
    for p in d.get("props", []) + d.get("resolved", []):
        ids.add(p["id"])
    for s in d.get("stations", {}).values():
        if s.get("prop"):
            ids.add(s["prop"])
    for ps in d.get("upgrades", {}).values():
        for p in ps:
            ids.add(p["id"])
    for s in d.get("stairs", []):
        ids.add(s["prop"])
    return sorted(i for i in ids if i in cat and cat[i]["category"] != "structure")


def remap_building(b):
    d = I.load(b)
    cat = I.catalog()
    rooms = glob.glob(os.path.join(ROOT, "assets", "art", "interiors", b, "room_*.png"))
    if not rooms:
        print(f"{b}: sin fondos pintados, nada que hacer")
        return
    cols = set()
    for p in rooms:
        for c in Image.open(p).convert("RGBA").getdata():
            if c[3] > 200:
                cols.add(c[:3])
    pal = [(c, lab(c)) for c in cols]
    cache = {}

    def near(c):
        if c not in cache:
            L = lab(c)
            best = min(pal, key=lambda q: math.dist(L, q[1]))
            cache[c] = best[0] if math.dist(L, best[1]) < THRESHOLD else c
        return cache[c]

    out_dir = os.path.join(ROOT, "assets", "art", "interiors", b, "props")
    os.makedirs(out_dir, exist_ok=True)
    moved = total = 0
    ids = used_props(d, cat)
    for pid in ids:
        im = Image.open(os.path.join(I.PROPS_ART, pid + ".png")).convert("RGBA")
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                r, g, bb, a = px[x, y]
                if a >= 128:
                    total += 1
                    c2 = near((r, g, bb))
                    if c2 != (r, g, bb):
                        moved += 1
                    px[x, y] = c2 + (a,)
        im.save(os.path.join(out_dir, pid + ".png"), optimize=True)
    for f in os.listdir(out_dir):  # las que ya no usa
        if f.endswith(".png") and f[:-4] not in ids:
            os.remove(os.path.join(out_dir, f))
            imp = os.path.join(out_dir, f + ".import")
            if os.path.exists(imp):
                os.remove(imp)
    print(f"{b}: {len(ids)} piezas con la paleta de sus fondos ({len(pal)} colores), "
          f"{100 * moved / max(1, total):.0f} % de los píxeles movidos")


def main():
    for b in sys.argv[1:] or [x for x in I.ids(templates=False)]:
        remap_building(b)


if __name__ == "__main__":
    main()
