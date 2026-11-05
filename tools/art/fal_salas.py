#!/usr/bin/env python3
"""Fondos pintados de los interiores por datos (docs/gdd/04g_interiores.md §4.6.5.1, camino C de
docs/arte/interiores.md): uno por planta con fal (nano-banana-2/edit) sobre la plantilla exacta de su geometría que
saca tools/interiors/interiores.py (suelo de cada sala, fosos y tarimas, paredes exteriores del fondo, la puerta de la
calle; sin paredes entre salas, que son piezas), con una referencia como dirección de arte. Se reduce a ×1 con
48 colores y se corta en un fondo por sala: assets/art/interiors/<edificio>/room_<planta>_<sala>.png, del tamaño de
toda la planta (transparente fuera de la sala), que el montador pone en Backdrops.

Uso:
  python3 tools/art/fal_salas.py gen <edificio> <planta> [--tag v1] [--model nano2]
  python3 tools/art/fal_salas.py proc <edificio> <planta> [--tag v1]
  python3 tools/art/fal_salas.py ver <edificio> <planta> [--tag v1]       # plantilla y crudo superpuestos (encaje)
Cada llamada se apunta en assets/art/fal_piloto/gasto.json (tanda «interiores»).
"""
import argparse
import datetime
import os
import sys
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "interiors"))
os.environ.setdefault("FAL_TANDA", "h16")
import fal_piloto as fpi  # noqa: E402
import fal_rutas as fr_  # noqa: E402
import interiores as I  # noqa: E402

fpi.TANDA = "interiores"
ROOT = fr_.ROOT
RAW = fr_.produccion("salas")
REFS = os.path.join(ROOT, "assets", "art", "interiors", "_referencias")
MODELS = {"nano2": ("fal-ai/nano-banana-2/edit", 0.08), "nanopro": ("fal-ai/nano-banana-pro/edit", 0.15)}
K = 3                       # la plantilla va a ×3
CANVAS = (1920, 1080)       # en un lienzo 16:9 (lo que devuelve el modelo se lleva a este tamaño)

FLOORS = {"flagstone": "worn grey flagstones", "planks": "warm wooden floorboards", "earth": "packed earth with a "
          "little straw", "stone": "big stone slabs", "rug": "wooden floorboards with a woven rug"}
WALLS = {"stone": "rough stone blocks with soot stains", "timber": "dark timber frame (posts, a top beam, braces) filled "
         "with warm plaster"}
FLOOR_COLOR = {"flagstone": "grey", "planks": "reddish brown", "earth": "pale ochre", "stone": "dark blue-grey",
               "rug": "crimson"}
HANG = {  # lo que cuelga de las paredes exteriores del fondo, por tipo de sala
    "workshop": "racks of tongs and hammers, horseshoes on nails, a lantern, a sooty patch above the hearth",
    "shop": "a leaded window with daylight, a shelf with a few jars, a hanging lantern, a painted sign board "
            "with no letters",
    "storage": "a small barred window, some hooks with rope and a sack",
    "kitchen": "strings of onions and garlic, bunches of herbs, a plate rack, a small window",
    "bedroom": "a small window with a curtain, a wooden peg with a cloak, a small shelf with a candle",
    "hall": "banners, a lantern, a window", "office": "a shelf of ledgers, a window", "yard": "a fence of planks",
    "cellar": "barrel racks, cobwebs", "chapel": "a small cross and candles",
}
REF_OF = {"forge": {0: "forge_b", 1: "house_b"}, "armory": {0: "armory_a"}, "carpentry": {0: "carpentry_b", 1: "house_b"},
          "masonry": {0: "masonry_a"}, "tailor_shop": {0: "tailor_shop_b", 1: "house_b"}, "house": {0: "house_b", 1: "house_a"},
          "town_hall": {0: "town_hall_b"}, "court": {0: "court_a"},
          "tavern_inn": {-1: "tavern_b", 0: "tavern_a", 1: "house_b"}}


def template_path(b, floor):
    return os.path.join(RAW, "ref", f"{b}_{floor}_plantilla.png")


def make_template(b, floor):
    """La plantilla a ×3, centrada en el lienzo 16:9. Devuelve (ruta, desplazamiento del lienzo de la planta). Las
    tarimas no se marcan (el modelo no las respeta): las dibuja dais() encima del fondo, exactas."""
    t = I.template(b, floor, K, steps=False) if _has_dais(b, floor) else I.template(b, floor, K)
    canvas = Image.new("RGB", CANVAS, (0, 0, 0))
    off = ((CANVAS[0] - t.width) // 2, (CANVAS[1] - t.height) // 2)
    canvas.paste(t, off)
    os.makedirs(os.path.dirname(template_path(b, floor)), exist_ok=True)
    canvas.save(template_path(b, floor))
    return template_path(b, floor), off


def _has_dais(b, floor):
    return any(lv["floor"] == floor and lv["step"] > 0 for lv in I.load(b).get("levels", []))


def dais(b, floor, im):
    """Las tarimas de la planta, exactas, sobre el fondo a ×1: tablas un escalón (8 px) más altas y su canto de
    madera en los bordes de delante, con contorno."""
    from PIL import ImageDraw
    d = I.load(b)
    cw, ch, ox, oy = I.canvas_box(d)
    lay = I.Layout(d, I.catalog(), upgrades=False)
    tiles = {t for (f, t), st in lay.step.items() if f == floor and st > 0}
    if not tiles:
        return im
    sys.path.insert(0, HERE)
    import props_estructura as pe
    plank = pe.floor_tile("planks")
    out = im.convert("RGBA")
    dr = ImageDraw.Draw(out)
    side_dark, side_mid = (70, 46, 28, 255), (92, 62, 38, 255)
    for (c, r) in sorted(tiles, key=lambda t: t[0] + t[1]):
        x, y = I.world(c, r)
        x, y = ox + x, oy + y
        for nb, a, b2 in (((c, r + 1), (x - 32, y), (x, y + 16)), ((c + 1, r), (x, y + 16), (x + 32, y))):
            if nb not in tiles:  # el canto de delante
                dr.polygon([a, b2, (b2[0], b2[1] - 8), (a[0], a[1] - 8)], fill=side_mid if nb == (c + 1, r) else side_dark)
                dr.line([a, b2], fill=pe.INK + (255,))
        out.alpha_composite(plank, (int(x - 32), int(y - 16 - 8)))
    for (c, r) in tiles:  # contorno del borde de arriba
        x, y = I.world(c, r)
        x, y = ox + x, oy + y - 8
        for nb, a, b2 in (((c, r + 1), (x - 32, y), (x, y + 16)), ((c + 1, r), (x, y + 16), (x + 32, y)),
                          ((c - 1, r), (x - 32, y), (x, y - 16)), ((c, r - 1), (x, y - 16), (x + 32, y))):
            if nb not in tiles:
                dr.line([a, b2], fill=pe.INK + (255,))
    return out.convert("RGB")


def prompt(b, floor):
    d = I.load(b)
    rooms = [r for r in d["rooms"] if r["floor"] == floor]
    pits = [lv for lv in d.get("levels", []) if lv["floor"] == floor]
    parts = []
    for r in rooms:
        fk = r.get('floor_kind', 'planks')
        parts.append(f"the {r['type']} ({r['id']}, the {FLOOR_COLOR[fk]} area): floor of {FLOORS[fk]}, its back walls "
                     f"of {WALLS[r.get('wall_style', 'timber')]} with {HANG.get(r['type'], 'a lantern')}")
    pit = (" The darker floor rectangle in the back corner is the forge pit: that WHOLE rectangle is the same stone "
           "floor, sunk just one step lower (about a hand) than the rest, with a single stone kerb along its front "
           "edges, and soot and coal dust on it. It is not a hole, it has no stairs and no opening: the hearth will "
           "stand in it." if any(lv["step"] < 0 for lv in pits) else "")
    dais = ""  # las tarimas las dibuja dais() encima, exactas
    door = " The dark door on a back wall is the street door: a wooden plank door with iron hinges." if \
        d.get("entrance", {}).get("floor") == floor else ""
    return (
        "Image 1 is an exact layout template of one floor of a building in our isometric 2:1 medieval pixel-art game: "
        "the floor of each room in a flat colour, and the outer back walls. Image 2 is the art direction. Repaint image "
        "1 as the EMPTY shell of these rooms in exactly the 16-bit pixel art style of image 2 (Graveyard Keeper: warm "
        "palette, light from the top-left, crisp pixels, dark outlines on details): keep every edge, corner and the wall "
        "height EXACTLY where they are in image 1, nothing outside them, plain flat black background. The thin dark "
        "lines on the floor are the borders between rooms: change the floor material there, but do NOT draw any wall, "
        "door or post on them (the inner walls are separate pieces). The rooms are: " + "; ".join(parts) + "." + pit
        + dais + door + " The floors must stay EMPTY: no furniture, no hearth, no tables, no barrels, no people, only "
        "flat things lying on them (a few stains, worn paths, straw, small scraps), soft warm light pools and a little "
        "shadow along the walls. No text, no letters, no UI."
    )


def gen(b, floor, tag, model):
    endpoint, unit = MODELS[model]
    raw = os.path.join(RAW, "crudo", f"{b}_{floor}_{tag}.png")
    if os.path.exists(raw):
        print("ya está", raw)
        return raw
    tpl, _ = make_template(b, floor)
    ref = REF_OF.get(b, {}).get(floor, "forge_b")
    fpi.guard(unit)
    import fal_client
    args = {"prompt": prompt(b, floor), "num_images": 1, "aspect_ratio": "16:9", "output_format": "png",
            "image_urls": [fal_client.upload_file(tpl), fal_client.upload_file(os.path.join(REFS, ref + ".png"))]}
    print(f"{endpoint} | sala {b} planta {floor} ({tag}) | {unit:.3f} USD (interiores: {fpi.total():.3f})")
    res = fal_client.subscribe(endpoint, arguments=args)
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    urllib.request.urlretrieve(res["images"][0]["url"], raw)
    fpi.note("interiores", endpoint, 1, unit, f"fondo {b} planta {floor} ({tag})")
    with open(os.path.join(RAW, "crudo", "prompts.log"), "a") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {b}_{floor}_{tag} | {endpoint} | ref=plantilla,{ref}\n"
                f"  {args['prompt']}\n\n")
    print("  ->", raw)
    return raw


def _floor_image(b, floor, tag):
    """El crudo llevado al lienzo de la planta a ×1 (BOX)."""
    d = I.load(b)
    _, off = make_template(b, floor)
    cw, ch, _, _ = I.canvas_box(d)
    im = Image.open(os.path.join(RAW, "crudo", f"{b}_{floor}_{tag}.png")).convert("RGB").resize(CANVAS, Image.LANCZOS)
    return im.crop((off[0], off[1], off[0] + cw * K, off[1] + ch * K)).resize((cw, ch), Image.BOX)


def proc(b, floor, tag, colors=48):
    d = I.load(b)
    room = dais(b, floor, _floor_image(b, floor, tag))
    full = Image.new("L", room.size, 0)
    for r in d["rooms"]:
        if r["floor"] == floor:
            full = Image.composite(Image.new("L", room.size, 255), full, I.room_mask(d, floor, r["id"]))
    q = room.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    out_dir = os.path.join(ROOT, "assets", "art", "interiors", b)
    os.makedirs(out_dir, exist_ok=True)
    for r in d["rooms"]:
        if r["floor"] != floor:
            continue
        piece = q.copy()
        piece.putalpha(I.room_mask(d, floor, r["id"]))
        p = I.backdrop_path(b, floor, r["id"])
        piece.save(p, optimize=True)
        print(f"  sala {r['id']}: {os.path.relpath(p, ROOT)}")
    walls(b, floor, q, d)


def walls(b, floor, q, d):
    """Las paredes entre salas y los zócalos de cada sala, sacados de su propia pared pintada: el tramo de 32 px más
    liso (menos detalle) de cada lado; un lado sin pared pintada sale del otro en espejo. Escribe
    wall_<planta>_<sala>_<ne|nw>[_door].png y low_<planta>_<sala>_<ne|nw>.png junto a los fondos."""
    import statistics
    sys.path.insert(0, HERE)
    import props_estructura as pe
    lay = I.Layout(d, I.catalog(), upgrades=False)
    cw, ch, ox, oy = I.canvas_box(d)
    wh = lay.wall_h
    out_dir = os.path.join(ROOT, "assets", "art", "interiors", b)
    ent = lay.entrance
    for r in d["rooms"]:
        if r["floor"] != floor:
            continue
        best = {}
        for kind, t, side, behind, front in lay.walls(floor):
            if kind != "back" or front != r["id"] or (ent and ent == (floor, t, side)):
                continue
            x, y = I.world(*t)
            left = int(ox + x) if side == "ne" else int(ox + x - 32)
            top = int(oy + y - 16 - wh)
            seg = q.crop((left, top, left + 32, top + 16 + wh))
            px = [c for i, c in enumerate(seg.convert("RGB").getdata()) if pe._inside(side, i % 32, i // 32, wh)]
            lum = [0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] for c in px]
            dark = sum(1 for v in lum if v < 28) / max(1, len(lum))
            score = statistics.pstdev(lum) if len(lum) > 1 and dark < 0.04 else 999  # fuera lo que el modelo dejó en negro
            if side not in best or score < best[side][0]:
                best[side] = (score, seg)
        if not best:
            continue
        for side in ("ne", "nw"):
            if side in best:
                seg = best[side][1]
            else:
                seg = best["nw" if side == "ne" else "ne"][1].transpose(Image.FLIP_LEFT_RIGHT)
            seg = seg.convert("RGBA")
            pxl = seg.load()
            for yy in range(seg.height):  # fuera de la cara, transparente
                for xx in range(32):
                    if not pe._inside(side, xx, yy, wh):
                        pxl[xx, yy] = (0, 0, 0, 0)
            plain = seg.copy()
            pe._outline(plain)
            plain.save(os.path.join(out_dir, f"wall_{floor}_{r['id']}_{side}.png"))
            door = seg.copy()
            dp = door.load()
            for xx in range(32):
                t2 = xx / 2 if side == "ne" else (31 - xx) / 2
                for yy in range(door.height):
                    v = yy - t2
                    if 6 <= xx <= 25 and wh - 52 <= v <= wh and pe._inside(side, xx, yy, wh):
                        dp[xx, yy] = (0, 0, 0, 0)
                    elif xx in (5, 26) and wh - 54 <= v <= wh and pe._inside(side, xx, yy, wh):
                        dp[xx, yy] = pe.TIMBER[1] + (255,)
                    elif 5 <= xx <= 26 and wh - 54 <= v <= wh - 53 and pe._inside(side, xx, yy, wh):
                        dp[xx, yy] = pe.TIMBER[2] + (255,)
            pe._outline(door)
            door.save(os.path.join(out_dir, f"wall_{floor}_{r['id']}_{side}_door.png"))
            # zócalo: los 12 px de abajo de la cara, a lo alto del lienzo del zócalo (16 + 12)
            low = Image.new("RGBA", (32, 16 + pe.LOW_H), (0, 0, 0, 0))
            lp, sp = low.load(), seg.load()
            for xx in range(32):
                t2 = xx / 2 if side == "ne" else (31 - xx) / 2
                for v in range(pe.LOW_H + 1):
                    yy_src = int(round(t2 + wh - pe.LOW_H + v))
                    yy_dst = int(round(t2 + v))
                    if 0 <= yy_src < seg.height and 0 <= yy_dst < low.height:
                        lp[xx, yy_dst] = sp[xx, yy_src]
            pe._outline(low)
            low.save(os.path.join(out_dir, f"low_{floor}_{r['id']}_{side}.png"))
        print(f"  paredes de {r['id']}: de su pared pintada ({', '.join(sorted(best))})")


def ver(b, floor, tag):
    t = I.template(b, floor, 1).convert("RGB")
    room = _floor_image(b, floor, tag)
    out = os.path.join(RAW, "vista", f"{b}_{floor}_{tag}_encaje.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    Image.blend(room, t, 0.35).resize((t.width * 2, t.height * 2), Image.NEAREST).save(out)
    print("encaje ->", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["gen", "proc", "ver", "plantilla"])
    ap.add_argument("building")
    ap.add_argument("floor", type=int)
    ap.add_argument("--tag", default="v1")
    ap.add_argument("--model", choices=list(MODELS), default="nano2")
    a = ap.parse_args()
    if a.cmd == "gen":
        gen(a.building, a.floor, a.tag, a.model)
    elif a.cmd == "proc":
        proc(a.building, a.floor, a.tag)
    elif a.cmd == "ver":
        ver(a.building, a.floor, a.tag)
    else:
        print(make_template(a.building, a.floor)[0])


if __name__ == "__main__":
    main()
