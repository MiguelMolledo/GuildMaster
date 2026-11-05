#!/usr/bin/env python3
"""Piezas exactas de la biblioteca de interiores (docs/gdd/04g_interiores.md §4.6.5.1, «estructura»), dibujadas con
Pillow porque tienen que encajar al píxel en la rejilla 2:1 (64×32) y en la altura de pared del montador:

  wall_<estilo>_<ne|nw>        tramo de pared interior de 32 px de ancho y WALL_H de alto (entramado y yeso, o piedra)
  wall_<estilo>_door_<ne|nw>   el mismo tramo con el vano de una puerta abierta (se ve lo de detrás)
  wall_low_<ne|nw>             zócalo de las paredes del frente (12 px), para leer el interior como un diorama
  railing_<ne|nw>              barandilla de madera (escalera, foso, borde de la planta alta)
  floor_<flagstone|planks|earth>  suelo de respaldo (rombo de 64×32) para las salas sin fondo pintado
  y las piezas «de antes» de las mejoras que aún no tienen pieza nueva (copias de assets/art/interiors/<oficio>/upg_*).

Geometría de un tramo (como KitWall): lienzo de 32 × (16 + alto); en «ne» el borde de abajo va de (0, alto) a
(32, alto + 16) y el de arriba de (0, 0) a (32, 16); en «nw», al revés. Escribe también su ficha «prop» en
assets/inventario.json (como tools/art/fal_props.py). Uso: python3 tools/art/props_estructura.py
"""
import json
import os
import random
import shutil

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "art", "props", "interior")
INV = os.path.join(ROOT, "assets", "inventario.json")
WALL_H = 64
LOW_H = 12

INK = (20, 13, 8)
TIMBER = [(58, 36, 22), (82, 54, 32), (110, 76, 46), (138, 98, 62)]
PLASTER = [(150, 124, 92), (176, 148, 112), (198, 172, 134), (214, 192, 156)]
STONE = [(70, 64, 62), (96, 88, 84), (122, 114, 106), (146, 138, 128)]


def _inside(side, x, y, h):
    """¿(x, y) del lienzo 32 × (16 + h) está en la cara del tramo?"""
    t = x / 2 if side == "ne" else (31 - x) / 2  # el borde de arriba baja 1 px cada 2
    return t <= y <= t + h


def wall(style, side, door=False, h=WALL_H, seed=0):
    W, H = 32, 16 + h
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    rnd = random.Random(f"{style}{side}{door}{seed}")
    fill = PLASTER if style == "timber" else STONE
    for y in range(H):
        for x in range(W):
            if not _inside(side, x, y, h):
                continue
            t = x / 2 if side == "ne" else (31 - x) / 2
            v = y - t  # altura en la cara (0 = arriba)
            c = fill[1] if rnd.random() < 0.7 else fill[2]
            if style == "stone":
                row = int(v // 8)
                if int(v) % 8 == 0 or (int(x + row * 9) % 16 == 0):
                    c = fill[0]
            if (x + int(v)) % 7 == 0 and rnd.random() < 0.3:
                c = fill[0] if style == "stone" else fill[0]
            # entramado: viga de arriba, solera, poste en la punta lejana y una riostra
            if style == "timber":
                if v < 4:
                    c = TIMBER[2] if v < 1 else TIMBER[1]
                elif v > h - 4:
                    c = TIMBER[1]
                elif (side == "ne" and x < 3) or (side == "nw" and x > 28):
                    c = TIMBER[2] if (side == "ne" and x == 2) or (side == "nw" and x == 29) else TIMBER[1]
                elif seed % 2 == 1:
                    # riostra en diagonal (de arriba a la punta cercana)
                    bx = x if side == "ne" else 31 - x
                    if abs((v - 4) - bx * (h - 8) / 32) < 2.0:
                        c = TIMBER[1]
            px[x, y] = c + (255,)
    # luz: la mitad de arriba un poco más clara (luz de arriba a la izquierda), la de abajo más oscura
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if not a:
                continue
            t = x / 2 if side == "ne" else (31 - x) / 2
            v = y - t
            k = 1.06 if v < h * 0.35 else (0.88 if v > h * 0.8 else 1.0)
            if side == "nw":
                k *= 0.92  # la pared izquierda, algo más en sombra
            px[x, y] = (min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)), a)
    if door:  # vano abierto con marco: 20-80 % del tramo, 52 px de alto
        d = ImageDraw.Draw(im)
        for x in range(W):
            t = x / 2 if side == "ne" else (31 - x) / 2
            if 6 <= x <= 25:
                for y in range(H):
                    v = y - t
                    if h - 52 <= v <= h and _inside(side, x, y, h):
                        px[x, y] = (0, 0, 0, 0)
            if x in (5, 26):  # jambas
                for y in range(H):
                    v = y - t
                    if h - 54 <= v <= h and _inside(side, x, y, h):
                        px[x, y] = TIMBER[1] + (255,)
        for x in range(5, 27):  # dintel
            t = x / 2 if side == "ne" else (31 - x) / 2
            for v in (h - 54, h - 53):
                y = int(round(t + v))
                if 0 <= y < H:
                    px[x, y] = TIMBER[2] + (255,)
    _outline(im)
    return im


def low_wall(side):
    return wall("timber", side, h=LOW_H, seed=0)


def railing(side):
    h = 20
    W, H = 32, 16 + h
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pts = lambda x: (x, (x / 2 if side == "ne" else (31 - x) / 2))  # noqa: E731
    for x in range(W):
        t = pts(x)[1]
        for v in (0, 1):  # pasamanos
            d.point((x, round(t + v)), fill=TIMBER[2] if v == 0 else TIMBER[1])
        if x % 8 in (1, 2):  # balaustres
            for v in range(2, h):
                d.point((x, round(t + v)), fill=TIMBER[1] if x % 8 == 1 else TIMBER[0])
    _outline(im)
    return im


def floor_tile(kind):
    W, H = 64, 32
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    rnd = random.Random(kind)
    for y in range(H):
        for x in range(W):
            if abs(x - 31.5) / 32 + abs(y - 15.5) / 16 > 1.0:
                continue
            if kind == "earth":
                base = [(104, 80, 56), (116, 90, 62), (96, 74, 52)]
                c = base[0] if rnd.random() < 0.6 else rnd.choice(base)
            elif kind == "planks":
                u, v = x / 2 + y, x / 2 - y
                plank = int((v + 64) // 8) % 4
                c = [(122, 82, 48), (110, 72, 42), (132, 90, 54), (116, 77, 45)][plank]
                if int(v + 64) % 8 == 0:
                    c = (70, 44, 26)
            else:  # flagstone
                u, v = x / 2 + y, x / 2 - y
                c = (112, 104, 96) if (int(u // 10) + int((v + 64) // 10)) % 2 else (100, 94, 88)
                if int(u) % 10 == 0 or int(v + 64) % 10 == 0:
                    c = (64, 58, 54)
            px[x, y] = c + (255,)
    return im


def _outline(im):
    """Contorno de 1 px del color de tinta alrededor de lo opaco (como fal_iconos.outline)."""
    a = im.getchannel("A")
    px = im.load()
    ap = a.load()
    w, h = im.size
    edge = []
    for y in range(h):
        for x in range(w):
            if not ap[x, y]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or not ap[nx, ny]:
                    edge.append((x, y))
                    break
    for x, y in edge:
        px[x, y] = INK + (255,)


# piezas de antes que todavía no tienen pieza nueva: (id nuevo, fichero de antes, huella, banderas, oficios)
LEGACY = [
    ("engraving_bench", "forge/upg_engraving.png", "forge"), ("master_seal", "forge/upg_seal.png", "forge"),
    ("hidden_passage", "forge/upg_passage.png", "all"), ("smuggler_cache", "forge/upg_cache.png", "all"),
    ("double_ledger", "forge/upg_ledger.png", "all"), ("master_bench", "forge/upg_master_bench.png", "all"),
    ("frame_saw", "carpentry/upg_frame_saw.png", "carpentry"), ("planes_rack", "carpentry/upg_planes.png", "carpentry"),
    ("gouges", "carpentry/upg_gouges.png", "carpentry"), ("carpenter_mark", "carpentry/upg_mark.png", "carpentry"),
    ("master_carpenter_bench", "carpentry/upg_master_bench.png", "carpentry"),
    ("vice_bench", "carpentry/upg_vice_bench.png", "carpentry"),
    ("mason_chisels", "masonry/upg_chisels.png", "masonry"), ("mason_crane", "masonry/upg_crane.png", "masonry"),
    ("mason_mark", "masonry/upg_mark.png", "masonry"), ("master_yard", "masonry/upg_master_yard.png", "masonry"),
    ("mason_templates", "masonry/upg_templates.png", "masonry"), ("mason_wedges", "masonry/upg_wedges.png", "masonry"),
    ("tailor_dyes", "tailor_shop/upg_dyes.png", "tailor_shop"), ("tailor_master_table", "tailor_shop/upg_master_table.png", "tailor_shop"),
    ("tailor_seal", "tailor_shop/upg_seal.png", "tailor_shop"), ("tailor_shears", "tailor_shop/upg_shears.png", "tailor_shop"),
    ("tailor_shuttle", "tailor_shop/upg_shuttle.png", "tailor_shop"), ("tailor_treadle", "tailor_shop/upg_treadle.png", "tailor_shop"),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for style in ("timber", "stone"):
        for side in ("ne", "nw"):
            for door in (False, True):
                for seed in ((0, 1) if not door else (0,)):
                    pid = f"wall_{style}{'_door' if door else ''}_{side}{'_b' if seed else ''}"
                    wall(style, side, door, seed=seed).save(os.path.join(OUT, pid + ".png"))
                    made[pid] = ("structure", [1, 1], {"wall": True}, f"tramo de pared {style} ({side}"
                                 f"{', puerta abierta' if door else ''}{', con riostra' if seed else ''}), 32×{16 + WALL_H}")
    for side in ("ne", "nw"):
        low_wall(side).save(os.path.join(OUT, f"wall_low_{side}.png"))
        made[f"wall_low_{side}"] = ("structure", [1, 1], {"wall": True}, f"zócalo de la pared del frente ({side}), 32×{16 + LOW_H}")
        railing(side).save(os.path.join(OUT, f"railing_{side}.png"))
        made[f"railing_{side}"] = ("structure", [1, 1], {}, f"barandilla de madera ({side})")
    for kind in ("flagstone", "planks", "earth"):
        floor_tile(kind).save(os.path.join(OUT, f"floor_{kind}.png"))
        made[f"floor_{kind}"] = ("structure", [1, 1], {"walkable": True}, f"suelo de respaldo {kind} (rombo 64×32)")
    legacy = {}
    for pid, src, trade in LEGACY:
        s = os.path.join(ROOT, "assets", "art", "interiors", src)
        shutil.copy(s, os.path.join(OUT, pid + ".png"))
        legacy[pid] = (src, trade)
    inv = json.load(open(INV, encoding="utf-8"))
    by = {a["id"]: a for a in inv["assets"]}
    ids = [a["id"] for a in inv["assets"]]
    anchor = max(i for i, a in enumerate(ids) if a.startswith("iprop_") or a == "int_referencias")

    def put(pid, entry):
        nonlocal anchor
        e = by.get("iprop_" + pid)
        if e is None:
            e = {"id": "iprop_" + pid}
            anchor += 1
            inv["assets"].insert(anchor, e)
            by[e["id"]] = e
        e.clear()
        e.update(entry)

    for pid, (cat, fp, flags, desc) in made.items():
        im = Image.open(os.path.join(OUT, pid + ".png"))
        w, h = im.size
        feet = [32, 16] if pid.startswith("floor_") else [0, h - 16] if pid.endswith("ne") or pid.endswith("ne_b") else [32, h - 16]
        if pid.startswith("railing_"):
            feet = [0, h - 16] if pid.endswith("ne") else [32, h - 16]
        put(pid, {"id": "iprop_" + pid, "tipo": "prop", "estado": "sprite", "para": ["interiores"],
                  "ruta": f"assets/art/props/interior/{pid}.png", "origen": "dibujado (Pillow, tools/art/props_estructura.py)",
                  "coste_gen": 0, "coste_usd": 0, "notas": desc,
                  "prop": {"category": cat, "footprint": fp, "size": [w, h], "feet": feet, "height": feet[1],
                           "walkable": bool(flags.get("walkable")), "wall": bool(flags.get("wall")), "on_top": False,
                           "hangs": False, "mirror": False, "trades": ["all"], "style": "common"}})
    for pid, (src, trade) in legacy.items():
        im = Image.open(os.path.join(OUT, pid + ".png"))
        w, h = im.size
        feet = [40, 56] if (w, h) == (80, 72) else [w // 2, h - 16]  # como el offset (-40, -56) de las escenas de antes
        put(pid, {"id": "iprop_" + pid, "tipo": "prop", "estado": "sprite", "para": ["interiores"],
                  "ruta": f"assets/art/props/interior/{pid}.png",
                  "origen": f"copia de assets/art/interiors/{src} (pieza de antes de una mejora; tools/art/props_estructura.py)",
                  "coste_gen": 0, "coste_usd": 0,
                  "notas": "Pieza de antes (Guild Renew o Pillow) para la mejora, hasta que tenga una nueva de la biblioteca.",
                  "prop": {"category": "trade", "footprint": [1, 1], "size": [w, h], "feet": feet, "height": feet[1],
                           "walkable": False, "wall": False, "on_top": False, "hangs": False, "mirror": True,
                           "trades": [trade], "style": "common"}})
    json.dump(inv, open(INV, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    open(INV, "a").write("\n")
    print(f"estructura: {len(made)} piezas dibujadas y {len(legacy)} de antes -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
