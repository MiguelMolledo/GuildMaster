#!/usr/bin/env python3
"""Escenas de Godot del arte del rediseño de la ciudad (tools/art/fal_rediseno.py): una por pieza, copiadas del
patrón de game/visuals/props/tree.tscn (Feet, Top, Greybox oculto, Sprite a escala 1 con la base sobre Feet).

El ancla se mide en el PNG:
  - árboles, postes y piezas sueltas: el pie es la fila opaca más baja (sin la sombra translúcida) y su centro;
  - piezas de casilla (seto, valla, abrevadero, fuente, puestos, monumentos): la maqueta puso el vértice de abajo de
    su huella (c×r casillas, o 1,4×1 en los puestos) en la fila de abajo; Feet va en el centro de la huella:
    (c - r)·16 px a la izquierda y (c + r)·8 px por encima de ese vértice.

Puestos: el arte nuevo sustituye al de assets/art/buildings/stall_<id>.png (misma ruta y uid; las escenas
props/stall_<id>.tscn solo cambian el desplazamiento). La feria de ganado deja el corral dibujado por código.
Monumentos: game/visuals/props/<tipo>.tscn (WorldView._add_mark los usa en vez del bloque gris) con la huella para la
que están dibujados en los metadatos (`footprint`); el tramo de muralla sustituye al bloque de props/wall.tscn.

Uso: python3 tools/art/escenas_rediseno.py      (después: godot --headless --path . --import y tools/uids.py --fix)
"""
import os
import re
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "assets", "art")
PROPS = os.path.join(ROOT, "game", "visuals", "props")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fal_rediseno import PIECES  # noqa: E402

# piezas de casilla: id -> huella (c, r) de la maqueta
TILE_FOOT = {"hedge_1": (1, 1), "planter": (1, 1), "trough": (1, 1), "wattle_fence": (1, 1), "fence_gate": (1, 1),
             "hay_cart": (1, 1), "barrel_stack": (1, 1), "crate_stack": (1, 1), "woodpile": (1, 1),
             "clothesline": (1, 1), "fountain": (1.2, 1.2)}
LANDMARKS = ["cathedral", "church", "customs", "warehouse", "exchange", "wall_tower", "gate_tower", "crane"]
STALLS = ["stall_food", "stall_goods", "stall_materials", "stall_clothier", "stall_resources", "stall_apothecary",
          "stall_livestock"]
SKIP = {"tree_willow_1", "wall_1", "stall_spare"}


def pascal(s):
    return "".join(w.capitalize() for w in s.split("_"))


def bottom_anchor(im, solid=250):
    """(x, y) del pie: la fila más baja con píxeles opacos (alfa >= solid: sin la sombra) y el centro de esos píxeles
    en sus 4 filas más bajas."""
    a = im.getchannel("A")
    w, h = im.size
    px = a.load()
    rows = [y for y in range(h) if any(px[x, y] >= solid for x in range(w))]
    yb = rows[-1]
    xs = [x for y in range(max(0, yb - 3), yb + 1) for x in range(w) if px[x, y] >= solid]
    return (sum(xs) / len(xs), yb + 1)


def feet_of(pid, im):
    """El punto del PNG que va sobre Feet."""
    x, y = bottom_anchor(im)
    foot = TILE_FOOT.get(pid)
    if pid in LANDMARKS or pid == "wall_2":
        foot = PIECES[pid]["foot"]
    if pid.startswith("stall_"):
        foot = (1.4, 1.0)
    if foot:
        c, r = foot
        return (x - (c - r) * 16, y - (c + r) * 8)
    return (x, y)


def top_of(im, feet):
    a = im.getchannel("A")
    bb = a.getbbox()
    return round(feet[1] - bb[1])


def write_scene(path, node, tex_res, off, top, note, meta=None):
    meta_lines = ""
    for k, v in (meta or {}).items():
        meta_lines += f"metadata/{k} = {v}\n"
    text = f"""[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://game/world/block_view.gd" id="1_block"]
[ext_resource type="Texture2D" path="{tex_res}" id="2_sprite"]

[node name="{node}" type="Node2D"]
editor_description = "{note}"
{meta_lines}
[node name="Feet" type="Marker2D" parent="."]

[node name="Top" type="Marker2D" parent="."]
position = Vector2(0, {-top})

[node name="Greybox" type="Node2D" parent="."]
visible = false
script = ExtResource("1_block")
height = {min(60, top)}.0
color = Color(0.4, 0.45, 0.3, 1)

[node name="Sprite" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_sprite")
centered = false
offset = Vector2({off[0]}, {off[1]})
"""
    old_uid = None
    if os.path.exists(path):
        m = re.search(r'\[gd_scene[^\]]*uid="(uid://[a-z0-9]+)"', open(path).read())
        old_uid = m.group(1) if m else None
    if old_uid:
        text = text.replace("[gd_scene load_steps=3 format=3]", f'[gd_scene load_steps=3 format=3 uid="{old_uid}"]')
    with open(path, "w") as f:
        f.write(text)


def offset(im, feet):
    return (-round(feet[0]), -round(feet[1]))


def main():
    n = 0
    note_prop = ("Rediseño de la ciudad (tools/art/fal_rediseno.py: fal nano-banana-2 sobre maqueta gris a escala B, "
                 "pixelado local), escala 1 con el pie sobre Feet. Escena hecha por tools/art/escenas_rediseno.py.")
    for pid, pc in PIECES.items():
        if pid in SKIP or pc["out"] != "props":
            continue
        png = os.path.join(ART, "props", pid + ".png")
        if not os.path.exists(png):
            continue
        im = Image.open(png).convert("RGBA")
        feet = feet_of(pid, im)
        write_scene(os.path.join(PROPS, pid + ".tscn"), pascal(pid), f"res://assets/art/props/{pid}.png",
                    offset(im, feet), top_of(im, feet), note_prop)
        n += 1
    note_mark = ("Hito de la ciudad con su sprite (rediseño, tools/art/fal_rediseno.py), escala 1, Feet en el centro "
                 "de la huella para la que está dibujado (metadata footprint; WorldView lo refleja si el hito va girado "
                 "y usa el bloque gris si su huella es otra).")
    for pid in LANDMARKS:
        png = os.path.join(ART, "buildings", "landmarks", pid + ".png")
        im = Image.open(png).convert("RGBA")
        feet = feet_of(pid, im)
        c, r = PIECES[pid]["foot"]
        write_scene(os.path.join(PROPS, pid + ".tscn"), pascal(pid), f"res://assets/art/buildings/landmarks/{pid}.png",
                    offset(im, feet), top_of(im, feet), note_mark, {"footprint": f"Vector2i({c}, {r})"})
        n += 1
    # the town wall: one tile of wall
    png = os.path.join(ART, "buildings", "landmarks", "wall_2.png")
    im = Image.open(png).convert("RGBA")
    feet = feet_of("wall_2", im)
    write_scene(os.path.join(PROPS, "wall.tscn"), "Wall", "res://assets/art/buildings/landmarks/wall_2.png",
                offset(im, feet), top_of(im, feet), "One tile of a town or precinct wall (tile kind wall, M): WorldView "
                "puts it on every wall tile. Sprite: rediseño (tools/art/fal_rediseno.py).")
    n += 1
    # stalls: the new art over the old path (same uid), new offsets; the cattle fair gets a sprite scene too
    for sid in STALLS:
        dst = os.path.join(ART, "buildings", sid + ".png")
        im = Image.open(dst).convert("RGBA")
        feet = feet_of(sid, im)
        path = os.path.join(PROPS, sid + ".tscn")
        if sid == "stall_livestock":
            write_scene(path, "StallLivestock", "res://assets/art/buildings/stall_livestock.png", offset(im, feet),
                        top_of(im, feet), "H12 Patrón: the cattle fair (data/market.json livestock), a pen with sheep and "
                        "a goat. Market stall of the town redesign (tools/art/fal_rediseno.py), scale 1 with the centre "
                        "of its tile on Feet.")
            n += 1
            continue
        text = open(path).read()
        off = offset(im, feet)
        text = re.sub(r"offset = Vector2\([^)]*\)", f"offset = Vector2({off[0]}, {off[1]})", text)
        text = re.sub(r'(\[node name="Top" type="Marker2D" parent="\."\]\n)position = Vector2\([^)]*\)',
                      lambda m: m.group(1) + f"position = Vector2(0, {-top_of(im, feet)})", text)
        text = re.sub(r'editor_description = "[^"]*"\n(\n?)(?=\Z)', "", text)
        text = re.sub(r'(\[node name="Sprite"[^\n]*\n(?:[^\[\n][^\n]*\n)*?)editor_description = "[^"]*"',
                      lambda m: m.group(1) + 'editor_description = "Market stall of the town redesign '
                      '(tools/art/fal_rediseno.py: one style for every stall, the awning in the guild colour), scale 1 '
                      'with the centre of its tile on Feet. WorldView mirrors it when its service tile is on the +col '
                      'side, so the counter faces the buyer."', text)
        with open(path, "w") as f:
            f.write(text)
        n += 1
    for f in ("wall_1.png",):
        p = os.path.join(ART, "buildings", "landmarks", f)
        if os.path.exists(p):
            os.remove(p)
    print(f"{n} escenas")


if __name__ == "__main__":
    main()
