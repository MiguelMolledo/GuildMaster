#!/usr/bin/env python3
"""The illustrated parchment map of the region (docs/gdd/09b_region.md, the «Mapa de la región» screen) with fal.

Only the land is drawn (mountains in the north, the river along the south, the forest in the east, fields in the
middle): the screen draws the settlements, the routes and the names over it from data/world/region.json, so the
positions are exact and the names follow the language. nano-banana-2/edit with the title at dawn as the style
reference, then image2pixel for the palette and a box reduction to 480x270, doubled to 960x540 (like the screens of
tools/art/fal_ilustraciones.py). Every call is noted in assets/art/fal_piloto/gasto.json (tanda «mundo»).

  FAL_TANDA=mundo python3 tools/art/fal_region.py gen [--name region_map_v1]
  FAL_TANDA=mundo python3 tools/art/fal_region.py proc --name region_map_v1
Output: assets/art/region/valldaura_map.png (960x540), <region id>_map.png.
"""
import argparse
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import fal_rutas as fr_  # noqa: E402

P = fr_.produccion("region")
TITLE = os.path.join(fr_.PILOTO, "titulo", "crudo", "titulo_alba_v1.png")
OUT = os.path.join(ROOT, "assets", "art", "region", "valldaura_map.png")  # <region id>_map.png (VisualPaths.region_map)
PROMPT = (
    "Using the attached image only as STYLE reference (same 16-bit SNES pixel art, same warm earthy palette, outline "
    "and pixel size), paint an ILLUSTRATED MEDIEVAL MAP drawn on an old parchment sheet, seen from straight above "
    "like a hand-painted chart of a valley, wide 16:9 landscape. The whole picture is the parchment: aged tan paper "
    "(#d4b896) with darker stains and burnt, slightly torn edges all round. Geography, all painted in muted ink "
    "and watercolour on the paper: a range of grey-brown mountains with small snowy peaks across the whole top third "
    "(a lower saddle pass in the upper left-centre); a blue river that enters at the left edge at about two thirds of "
    "the height and winds to the right edge near the bottom right corner; a dark green forest of little round trees "
    "filling the right side between the mountains and the river; patches of golden wheat fields and hedges in the "
    "centre and the lower left; a few small hills. A small compass rose in the bottom left corner, drawn in ink, made only of pointed star rays with NO letters at all around it. "
    "IMPORTANT: NO towns, NO houses, NO castles, NO roads, NO paths, NO text, NO letters, NO labels, NO numbers, NO "
    "frame of UI: only the land, the river, the mountains, the forest and the fields, with calm empty areas where "
    "towns will be drawn later.")


# Boxes (x0, y0, x1, y1 at 480x270) painted over with the paper round them: the compass letters fal drew anyway
# (N, W, E, S in English), so the map carries no text.
ERASE = {"region_map_v1": [(40, 196, 51, 207), (15, 223, 27, 235), (66, 223, 78, 235), (41, 248, 52, 259)]}


def _erase(im, box):
    """Fills the box with the most common colour of a 3 px ring round it (the parchment)."""
    x0, y0, x1, y1 = box
    ring = {}
    for x in range(x0 - 3, x1 + 4):
        for y in range(y0 - 3, y1 + 4):
            if x0 <= x <= x1 and y0 <= y <= y1:
                continue
            c = im.getpixel((x, y))
            ring[c] = ring.get(c, 0) + 1
    fill = max(ring, key=ring.get)
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            im.putpixel((x, y), fill)


def raw(name):
    return os.path.join(P, "crudo", name + ".png")


def gen(name):
    if os.path.exists(raw(name)):
        print("ya existe", raw(name))
        return
    cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "region",
           "--aspect", "16:9", "--name", name, "--ref", TITLE, "--prompt", PROMPT]
    if subprocess.run(cmd, cwd=ROOT).returncode:
        sys.exit(1)


def proc(name, colors=40):
    from types import SimpleNamespace
    import fal_piloto
    src = raw(name)
    dst = os.path.join(P, "i2p", name + "_i2p.png")
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fal_piloto.pixel(SimpleNamespace(piece="region", src=src, dst=dst, colors=colors, scale=0, palette="",
                                         transparent=False))
    pal = Image.open(dst).convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                                                  dither=Image.Dither.NONE)
    small = Image.open(src).convert("RGB").resize((480, 270), Image.BOX).quantize(palette=pal,
                                                                               dither=Image.Dither.NONE)
    small = small.convert("RGB")
    for box in ERASE.get(name, []):
        _erase(small, box)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    small.resize((960, 540), Image.NEAREST).save(OUT)
    print("ok", os.path.relpath(OUT, ROOT))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["gen", "proc"])
    ap.add_argument("--name", default="region_map_v1")
    a = ap.parse_args()
    gen(a.name) if a.cmd == "gen" else proc(a.name)


if __name__ == "__main__":
    main()
