#!/usr/bin/env python3
"""Fachadas de los 6 edificios de data/buildings redibujadas con fal (2026-11-03), estado normal.

Una sola referencia por edificio: su sprite actual de escala B (assets/art/buildings/escala_b/<id>.png), centrado en
un lienzo blanco de 256×256 y ampliado ×4 (1024×1024): la salida cae en la misma rejilla, 4 px de imagen = 1 px de
arte. Proceso: image2pixel a escala 4 con fondo transparente, se recorta el rectángulo del sprite viejo y se ajusta
la posición (±8 px) para que la silueta case con la vieja. Resultado con el mismo lienzo y ancla que escala B
(assets/art/buildings/fal/<id>.png): se cambia en la escena poniendo esa textura en el nodo Sprite, sin mover Feet.

Obras y dañado (--estado construction|damaged): /edit sobre la fachada nueva, mismo lienzo:
assets/art/buildings/fal/<id>_construction.png y <id>_damaged.png (contrato de docs/ASSETS.md).

De espaldas (--estado back, y back_construction / back_damaged sobre la de espaldas): el mismo edificio visto desde
el otro lado, sin puerta en las caras visibles, para la puerta del sim en una cara oculta (el constructor de
ciudades usa <edificio>_back si existe). assets/art/buildings/fal/<id>_back.png (+ _back_construction, _back_damaged).

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
import fal_rutas as fr_  # noqa: E402  (crudos fuera del repo)
P = fr_.produccion("fachadas")
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
    "town_hall": "the town hall: a noble stone house with a tower and a banner",
    "tavern_inn": "a two-storey timber-framed TAVERN-INN: whitewashed walls, terracotta roof, warm light in the "
                  "windows, a wide open door at the same place as the reference's door, a hanging wooden sign with a "
                  "painted tankard (no letters), barrels and a bench outside, upper-floor windows for the rooms and a "
                  "small stable lean-to on one side",
    "bank": "a money-changer's BANK: a two-storey house of dressed pale stone with a dark slate roof, a heavy iron-bound "
            "door, barred windows, a hanging sign with a gold coin (no letters) and a small coat of arms over the door",
    "clinic": "a physician's practice: a timber-framed house with whitewashed plaster and a terracotta roof, bundles "
              "of herbs drying under the eaves, a small bench by the door and a hanging sign with a mortar and pestle "
              "(no letters on the sign)",
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


BACK = ("the SAME building seen from the OPPOSITE side, as if it were turned 180 degrees on its footprint: we now "
        "see its back wall and its other side wall, with the same materials, roof, chimney and base. The entrance "
        "door, the gate, the shop front and the sign are on the far side and must NOT be visible: the two visible "
        "walls are closed walls with NO doors, NO gates, NO big openings and NO wooden door panels; they only have windows, timber or stone, and back details (a woodpile, barrels or crates; no shed, no small doors or openings of any kind)")


# Edificios nuevos sin sprite de escala B: parten del de otro con el mismo lienzo, ancla y puerta (la Taberna-Posada,
# 3×4 casillas como la carpintería: Sprite offset (-104, -138), Door (-40, 12)).
NEW_FROM = {"tavern_inn": os.path.join(OUT, "carpentry.png")}


def base_of(bid, state=""):
    """Sprite del que parte cada estado: la fachada fal (o la de escala B si no hay), o la de espaldas fal."""
    if not state and bid in NEW_FROM:
        return NEW_FROM[bid]
    if state.startswith("back_"):
        return os.path.join(OUT, bid + "_back.png")
    if state:
        p = os.path.join(OUT, bid + ".png")
        return p if os.path.exists(p) or state != "back" else os.path.join(OLD, bid + ".png")
    return os.path.join(OLD, bid + ".png")


def grid(bid, state=""):
    """(lienzo, escala): 256 a ×4 o, si el sprite pasa de 240 px, 512 a ×2; la imagen siempre es de 1024."""
    im = Image.open(base_of(bid, state))
    if max(im.size) > 240:
        return (512, 2)
    return (CANVAS, 4)


def ref(bid, state=""):
    base = base_of(bid, state)
    im = Image.open(base).convert("RGBA")
    cv, k = grid(bid, state)
    ox, oy = (cv - im.width) // 2, (cv - im.height) // 2
    if bid in NEW_FROM and state in ("", "back"):  # un edificio nuevo puede ser más alto: la referencia, abajo
        oy = cv - im.height - 4
    c = Image.new("RGBA", (cv, cv), (255, 255, 255, 255))
    c.alpha_composite(im, (ox, oy))
    p = os.path.join(P, "ref", bid + ("_" + state if state else "") + ".png")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    c.convert("RGB").resize((cv * k, cv * k), Image.NEAREST).save(p)
    return p, (ox, oy, im.width, im.height)


def prompt(bid):
    if bid in NEW_FROM:  # un edificio nuevo sobre la misma huella, lienzo y puerta que la referencia
        return ("The attached image is a building sprite from our isometric 2:1 pixel art game, shown enlarged 4x on "
                "white (every art pixel is a 4x4 block). Draw a DIFFERENT building on EXACTLY the same footprint, "
                "base, position in the frame, 2:1 projection and camera, with its entrance door at the same place "
                "and about the same overall size (it may be one storey taller): " + BUILDINGS[bid] + ". Same clean "
                "1-pixel dark outline, warm 16-bit SNES palette, light from the top-left, 4x4 pixel blocks. No text, "
                "letters or words anywhere. Keep the plain flat white background, no ground shadow outside the base.")
    return ("The attached image is the current sprite of a building in our isometric 2:1 pixel art game, shown "
            "enlarged 4x on white (every art pixel is a 4x4 block). Redraw it as a finished, higher-quality sprite "
            "of the SAME building: keep EXACTLY the same position in the frame, the same footprint and base, the "
            "same overall size, wall height, roof shape and height, the same door position and the same 2:1 "
            "projection and camera; only improve the drawing: a clean 1-pixel dark outline, richer shading with "
            "light from the top-left, a consistent warm 16-bit SNES palette and crisp detail (timber, stones, "
            "tiles), keeping the 4x4 pixel blocks. The building: " + BUILDINGS[bid] + ". No text, letters or words "
            "anywhere. Keep the plain flat white background, no ground shadow outside the base.")


def state_prompt(bid, state):
    k = grid(bid, state)[1]
    if state == "back":
        what = BACK
    elif state.startswith("back_"):
        what = (STATES[state[5:]].replace("a broken door", "a broken window shutter") +
                ", seen from the back: no door, gate, shop front or sign on the visible walls; the scaffolding stays "
                "inside the same outline as the building, not wider")
    else:
        what = STATES[state]
    return ("The attached image is a finished building sprite from our isometric 2:1 pixel art game, shown enlarged "
            f"{k}x on white (every art pixel is a {k}x{k} block). Draw " + what + ". Keep EXACTLY the same "
            f"position in the frame, footprint, base, size, projection, palette, outline and {k}x{k} pixel blocks, so it "
            "can replace the sprite in place: do not zoom in or move the building; it must occupy exactly the same "
            "area as in the reference, with the same wide white margin around it. No text. Keep the plain flat "
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
    cv, k = grid(bid, state)
    im = Image.open(raw).convert("RGBA").resize((cv * k, cv * k))
    keyed = fp.key_background(im, "white", 22)
    if state in ("construction", "back_construction", "back"):
        keyed = holes(keyed)
    src = os.path.join(P, "celdas", name + ".png")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    keyed.save(src)
    dst = os.path.join(P, "i2p", name + "_s4.png")
    if not os.path.exists(dst):
        import fal_piloto
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fal_piloto.pixel(SimpleNamespace(piece="fachadas", src=src, dst=dst, colors=48, scale=k, palette="",
                                         transparent=True))
    up = Image.open(dst).convert("RGBA")
    meta = json.load(open(dst + ".json"))
    s = int(meta.get("pixel_scale") or k)
    nat = up.resize((up.width // s, up.height // s), Image.NEAREST)
    full = Image.new("RGBA", (cv, cv), (0, 0, 0, 0))
    full.alpha_composite(nat, (0, 0))
    full.putalpha(full.getchannel("A").point(lambda v: 255 if v > 127 else 0))
    old = Image.open(base_of(bid, state)).convert("RGBA")
    oldc = Image.new("RGBA", (cv, cv), (0, 0, 0, 0))
    oldc.alpha_composite(old, (ox, oy))
    best = max(((iou(oldc, full, dx, dy), dx, dy) for dy in range(-8, 9) for dx in range(-8, 9)))
    score, dx, dy = best
    shifted = Image.new("RGBA", (cv, cv), (0, 0, 0, 0))
    shifted.alpha_composite(full, (dx, dy))
    grow = 0
    if bid in NEW_FROM:  # un edificio nuevo puede ser más alto: el lienzo crece hacia arriba (pies y puerta quietos)
        bb = shifted.crop((ox, 0, ox + w, oy + h)).getchannel("A").getbbox()
        grow = max(0, oy - bb[1]) if bb else 0
    out = shifted.crop((ox, oy - grow, ox + w, oy + h))
    if grow:
        print(f"  {name}: el lienzo crece {grow} px hacia arriba: {w}×{h + grow}, offset del Sprite y {-grow} "
              "respecto al de su referencia")
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
    ap.add_argument("--estado", default="", choices=["", "construction", "damaged", "back", "back_construction",
                                                     "back_damaged"])
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
