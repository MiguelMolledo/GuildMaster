#!/usr/bin/env python3
"""A top-down semantic town plan (an image in the colours of tools/city/paleta_planos.json, made with fal by
tools/city/fal_planos.py or drawn by hand) read into the tile grid (docs/protocolos/generar-ciudad.md §1e).

  python3 tools/city/desde_imagen.py <image> --size 48x48 [--classes a,b,...] [--out reports/ciudad/fal/x_rejilla.png]

Each pixel goes to the nearest colour of the palette (only the classes the town uses); each tile to a class by its
share of pixels, with priorities, because the thin things of a plan (streets, walls, piers) never fill a tile:

  water  >= 0.45 · wall >= 0.12 · a landmark >= 0.35 · dock >= 0.22 · street >= 0.28 · plaza >= 0.4 ·
  else the class with most pixels (houses, grass, fields, woods, rock)

The town builder (tools/city/organic.py, a plan with "skeleton") takes from this grid the skeleton of the town (the
water, the streets, the squares, the walls, the landmarks, the fields, the woods, the rock and where the houses
stand) and puts the sim's sites, the house lots, the doors and the dressing by its own rules.
"""
import argparse
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citylib  # noqa: E402

ROOT = citylib.ROOT
PALETTE_PATH = os.path.join(ROOT, "tools", "city", "paleta_planos.json")
SHARE = {"water": 0.45, "wall": 0.12, "dock": 0.22, "street": 0.28, "plaza": 0.4}
LANDMARK_SHARE = 0.35
ORDER = ["water", "wall", "LANDMARK", "dock", "street", "plaza"]


def palette():
    return citylib.load_json(PALETTE_PATH)


def classify(path, size, classes=None):
    """{(c, r): class} for a w x h grid over the whole image, and the share of every class in every tile."""
    from PIL import Image
    pal = palette()
    cls = classes or list(pal["classes"])
    cols = [tuple(pal["classes"][k]["rgb"]) for k in cls]
    landmark = {k for k in cls if pal["classes"][k].get("landmark")}
    im = Image.open(path).convert("RGB")
    w, h = size
    # a small working size: about 12 px per tile is enough to measure the shares
    k = 12
    im = im.resize((w * k, h * k), Image.BOX)
    px = im.load()
    lut = {}

    def nearest(rgb):
        got = lut.get(rgb)
        if got is None:
            best, bd = 0, 1e9
            for i, c in enumerate(cols):
                d = (rgb[0] - c[0]) ** 2 + (rgb[1] - c[1]) ** 2 + (rgb[2] - c[2]) ** 2
                if d < bd:
                    best, bd = i, d
            got = best
            lut[rgb] = got
        return got

    grid = {}
    shares = {}
    for r in range(h):
        for c in range(w):
            n = [0] * len(cls)
            for y in range(r * k, (r + 1) * k):
                for x in range(c * k, (c + 1) * k):
                    n[nearest(px[x, y])] += 1
            tot = float(k * k)
            share = {cls[i]: n[i] / tot for i in range(len(cls)) if n[i]}
            shares[(c, r)] = share
            grid[(c, r)] = pick(share, landmark)
    return grid, shares


def pick(share, landmark):
    for key in ORDER:
        if key == "LANDMARK":
            best = max(((v, k) for k, v in share.items() if k in landmark), default=(0, ""))
            if best[0] >= LANDMARK_SHARE:
                return best[1]
            continue
        if share.get(key, 0) >= SHARE[key]:
            return key
    rest = {k: v for k, v in share.items() if k not in SHARE and k not in landmark}
    return max(rest, key=rest.get) if rest else max(share, key=share.get)


def render(grid, size, out, px=12):
    from PIL import Image, ImageDraw
    pal = palette()["classes"]
    w, h = size
    img = Image.new("RGB", (w * px, h * px))
    d = ImageDraw.Draw(img)
    for (c, r), k in grid.items():
        d.rectangle([c * px, r * px, (c + 1) * px - 1, (r + 1) * px - 1], fill=tuple(pal[k]["rgb"]))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    return out


def main(argv):
    ap = argparse.ArgumentParser(prog="desde_imagen.py")
    ap.add_argument("image")
    ap.add_argument("--size", default="48x48")
    ap.add_argument("--classes", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args(argv)
    size = tuple(int(x) for x in a.size.lower().split("x"))
    grid, _ = classify(os.path.join(ROOT, a.image), size, a.classes.split(",") if a.classes else None)
    out = a.out or os.path.join(ROOT, "reports", "ciudad", "fal",
                                os.path.splitext(os.path.basename(a.image))[0] + "_rejilla.png")
    print(os.path.relpath(render(grid, size, out), ROOT))
    counts = {}
    for k in grid.values():
        counts[k] = counts.get(k, 0) + 1
    print(", ".join(f"{k} {v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
