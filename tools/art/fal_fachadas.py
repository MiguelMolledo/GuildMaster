#!/usr/bin/env python3
"""Fachadas de los 6 edificios de data/buildings redibujadas con fal (2026-11-03), estado normal.

Una sola referencia por edificio: su sprite actual de escala B (assets/art/buildings/escala_b/<id>.png), centrado en
un lienzo blanco de 256×256 y ampliado ×4 (1024×1024): la salida cae en la misma rejilla, 4 px de imagen = 1 px de
arte. Proceso: image2pixel a escala 4 con fondo transparente, se recorta el rectángulo del sprite viejo y se ajusta
la posición (±8 px) para que la silueta case con la vieja. Resultado con el mismo lienzo y ancla que escala B
(assets/art/buildings/fal/<id>.png): se cambia en la escena poniendo esa textura en el nodo Sprite, sin mover Feet.

Obras y dañado (--estado construction|damaged): /edit sobre la fachada nueva, mismo lienzo:
assets/art/buildings/fal/<id>_construction.png y <id>_damaged.png (contrato de docs/ASSETS.md).

Uso: FAL_TANDA=extra python3 tools/art/fal_fachadas.py gen|proc [--solo id,id] [--modelo nano2|nanopro]
                                                       [--estado construction|damaged]
"""
import argparse
import json
import os
import subprocess
import sys
from types import SimpleNamespace

from PIL import Image

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import fal_procesar as fp  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
P = os.path.join(ROOT, "assets", "art", "fal_produccion", "fachadas")
OLD = os.path.join(ROOT, "assets", "art", "buildings", "escala_b")
OUT = os.path.join(ROOT, "assets", "art", "buildings", "fal")
CANVAS = 256

BUILDINGS = {
    "armory": "an armourer's shop of grey dressed stone with a red tile roof, painted shields with coats of arms "
              "leaning by the door and a small weapon bench",
    "forge": "a blacksmith's forge with a dark slate roof, a tall brick chimney, warm forge glow in the windows "
             "and an arched wooden door",
    "house": "a timber-framed family house with a terracotta tile roof and a dormer window",
    "carpentry": "a carpenter's workshop: a sturdy timber workshop with a big open wooden gate, stacks of planks "
                 "and a sawhorse outside, and a hanging wooden sign with a saw symbol",
    "masonry": "a stonemason's workshop of rough grey stone with a slate roof, cut stone blocks stacked outside and "
               "a hanging sign with a hammer-and-chisel symbol",
    "tailor_shop": "a tailor's shop: timber-framed with a terracotta roof, clothes hanging on a rail in the open "
                   "shop front and a hanging sign with a pair of scissors (replace the word on the sign with the "
                   "scissors symbol)",
}


STATES = {
    "construction": "the SAME building UNDER CONSTRUCTION: walls half built with the timber frame showing, wooden "
                    "scaffolding with ladders around it, the roof only rafters with a few tiles, piles of planks and "
                    "stones on the base",
    "damaged": "the SAME building DAMAGED: holes in the roof with broken tiles, cracked and scorched walls, a "
               "boarded-up window, a broken door, rubble and debris on the base",
}


def ref(bid, state=""):
    base = os.path.join(OUT, bid + ".png") if state else os.path.join(OLD, bid + ".png")
    im = Image.open(base).convert("RGBA")
    ox, oy = (CANVAS - im.width) // 2, (CANVAS - im.height) // 2
    c = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 255))
    c.alpha_composite(im, (ox, oy))
    p = os.path.join(P, "ref", bid + ("_" + state if state else "") + ".png")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    c.convert("RGB").resize((CANVAS * 4, CANVAS * 4), Image.NEAREST).save(p)
    return p, (ox, oy, im.width, im.height)


def prompt(bid):
    return ("The attached image is the current sprite of a building in our isometric 2:1 pixel art game, shown "
            "enlarged 4x on white (every art pixel is a 4x4 block). Redraw it as a finished, higher-quality sprite "
            "of the SAME building: keep EXACTLY the same position in the frame, the same footprint and base, the "
            "same overall size, wall height, roof shape and height, the same door position and the same 2:1 "
            "projection and camera; only improve the drawing: a clean 1-pixel dark outline, richer shading with "
            "light from the top-left, a consistent warm 16-bit SNES palette and crisp detail (timber, stones, "
            "tiles), keeping the 4x4 pixel blocks. The building: " + BUILDINGS[bid] + ". No text, letters or words "
            "anywhere. Keep the plain flat white background, no ground shadow outside the base.")


def state_prompt(bid, state):
    return ("The attached image is a finished building sprite from our isometric 2:1 pixel art game, shown enlarged "
            "4x on white (every art pixel is a 4x4 block). Draw " + STATES[state] + ". Keep EXACTLY the same "
            "position in the frame, footprint, base, size, projection, palette, outline and 4x4 pixel blocks, so it "
            "can replace the sprite in place: do not zoom in or move the building. No text. Keep the plain flat "
            "white background.")


def gen(bid, model, state=""):
    name = (bid if model == "nano2" else bid + "_pro") + ("_" + state if state else "")
    if os.path.exists(os.path.join(P, "crudo", name + ".png")):
        return
    src, _ = ref(bid, state)
    cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", model, "--piece", "fachadas",
           "--aspect", "1:1", "--name", name, "--ref", src,
           "--prompt", state_prompt(bid, state) if state else prompt(bid)]
    if subprocess.run(cmd, cwd=ROOT).returncode:
        sys.exit(1)


def holes(im, min_area=64):
    """Quita también el blanco del fondo que queda encerrado (entre vigas y andamios): manchas de blanco casi puro
    (>= 248) de al menos min_area píxeles de la imagen de 1024 (la ropa blanca lleva sombreado y no llega)."""
    im = im.copy()
    px = im.load()
    w, h = im.size
    seen = bytearray(w * h)
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0 * w + x0]:
                continue
            r, g, b, a = px[x0, y0]
            if not (a and r >= 248 and g >= 248 and b >= 248):
                continue
            comp, stack = [], [(x0, y0)]
            seen[y0 * w + x0] = 1
            while stack:
                x, y = stack.pop()
                comp.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                        c = px[nx, ny]
                        if c[3] and c[0] >= 248 and c[1] >= 248 and c[2] >= 248:
                            seen[ny * w + nx] = 1
                            stack.append((nx, ny))
            if len(comp) >= min_area:
                for x, y in comp:
                    px[x, y] = (0, 0, 0, 0)
    return im


def iou(a, b, dx, dy):
    """Coincidencia de siluetas (alfa) de b desplazada (dx, dy) sobre a."""
    pa, pb = a.load(), b.load()
    w, h = a.size
    inter = union = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            sx, sy = x - dx, y - dy
            va = pa[x, y][3] > 127
            vb = 0 <= sx < w and 0 <= sy < h and pb[sx, sy][3] > 127
            inter += va and vb
            union += va or vb
    return inter / max(1, union)


def proc(bid, name, state=""):
    raw = os.path.join(P, "crudo", name + ".png")
    if not os.path.exists(raw):
        print("falta", raw)
        return
    _, (ox, oy, w, h) = ref(bid, state)
    im = Image.open(raw).convert("RGBA").resize((CANVAS * 4, CANVAS * 4))
    keyed = fp.key_background(im, "white", 22)
    if state == "construction":
        keyed = holes(keyed)
    src = os.path.join(P, "celdas", name + ".png")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    keyed.save(src)
    dst = os.path.join(P, "i2p", name + "_s4.png")
    if not os.path.exists(dst):
        import fal_piloto
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fal_piloto.pixel(SimpleNamespace(piece="fachadas", src=src, dst=dst, colors=48, scale=4, palette="",
                                         transparent=True))
    up = Image.open(dst).convert("RGBA")
    meta = json.load(open(dst + ".json"))
    s = int(meta.get("pixel_scale") or 4)
    nat = up.resize((up.width // s, up.height // s), Image.NEAREST)
    full = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    full.alpha_composite(nat, (0, 0))
    full.putalpha(full.getchannel("A").point(lambda v: 255 if v > 127 else 0))
    old = Image.open(os.path.join(OUT if state else OLD, bid + ".png")).convert("RGBA")
    oldc = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    oldc.alpha_composite(old, (ox, oy))
    best = max(((iou(oldc, full, dx, dy), dx, dy) for dy in range(-8, 9) for dx in range(-8, 9)))
    score, dx, dy = best
    shifted = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shifted.alpha_composite(full, (dx, dy))
    out = shifted.crop((ox, oy, ox + w, oy + h))
    os.makedirs(OUT, exist_ok=True)
    if state:
        target = os.path.join(OUT, f"{bid}_{state}.png")
    elif name == bid or not os.path.exists(os.path.join(OUT, bid + ".png")):
        target = os.path.join(OUT, bid + ".png")
    else:
        target = os.path.join(P, "alternativas", name + ".png")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    out.save(target)
    lost = sum(1 for v in shifted.getchannel("A").getdata() if v) - sum(1 for v in out.getchannel("A").getdata() if v)
    print(f"{name}: {out.size} silueta {score:.2f} desplazamiento ({dx},{dy}) píxeles fuera del lienzo {lost} -> "
          f"{os.path.relpath(target, ROOT)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["gen", "proc"])
    ap.add_argument("--solo", default="")
    ap.add_argument("--modelo", default="nano2")
    ap.add_argument("--estado", default="", choices=["", "construction", "damaged"])
    a = ap.parse_args()
    ids = [x for x in a.solo.split(",") if x] or list(BUILDINGS)
    for bid in ids:
        name = (bid if a.modelo == "nano2" else bid + "_pro") + ("_" + a.estado if a.estado else "")
        if a.cmd == "gen":
            gen(bid, a.modelo, a.estado)
        else:
            proc(bid, name, a.estado)


if __name__ == "__main__":
    main()
