#!/usr/bin/env python3
"""Puts the fal facades (assets/art/buildings/fal/, docs/arte/fal_produccion.md: same canvas and anchor as the scale B
sprite) into the building scenes and makes their back views (docs/protocolos/generar-ciudad.md §Puertas).

  python3 tools/city/enchufar_fachadas.py      (idempotent: a scene already done is left alone)

Front scenes game/visuals/buildings/<id>.tscn (armory, forge, house, carpentry, masonry, tailor_shop):
  - Sprite gets <id>.png of fal (same offset: same canvas and anchor);
  - SpriteEscalaB (hidden) keeps the scale B texture, to go back;
  - LookConstruction and LookDamaged (hidden Sprite2D) carry <id>_construction.png and <id>_damaged.png:
    WorldView._apply_looks puts their texture on Sprite while the building is under works or damaged.
Back scenes game/visuals/buildings/<id>_back.tscn (the six + town_hall, which only has the normal back): the front's
Feet, Top, Greybox, Works and Upgrades (same canvas and silhouette: the facade overlays sit on the same visible
faces, and mirror with the scene) and Sprite with <id>_back[_construction|_damaged].png. Their Door marker is written by tools/city/marcar_puertas.py (the front's threshold reflected through
Feet, on the opposite face). Then: godot --import, python3 tools/uids.py --fix, marcar_puertas.py, sprites_catalog.py.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
B = os.path.join(ROOT, "game", "visuals", "buildings")
FAL = "res://assets/art/buildings/fal"
FRONTS = ["armory", "forge", "house", "carpentry", "masonry", "tailor_shop"]
BACKS = FRONTS + ["town_hall"]
WHEN = {"construction": "under works", "damaged": "damaged"}


def sections(text):
    """[(head line, body lines)] of a .tscn, in order."""
    out = []
    for line in text.split("\n"):
        if line.startswith("["):
            out.append([line, []])
        elif out:
            out[-1][1].append(line)
    return out


def join(secs):
    parts = []
    for head, body in secs:
        while body and body[-1] == "":
            body = body[:-1]
        parts.append("\n".join([head] + body))
    return "\n\n".join(parts) + "\n"


def node_name(head):
    m = re.match(r'\[node name="([^"]+)"', head)
    return m.group(1) if m else ""


def node_parent(head):
    m = re.search(r'parent="([^"]+)"', head)
    return m.group(1) if m else None


def ext(path, rid):
    return f'[ext_resource type="Texture2D" path="{path}" id="{rid}"]'


def fix_steps(secs):
    n = sum(1 for h, _ in secs if h.startswith("[ext_resource") or h.startswith("[sub_resource")) + 1
    h, body = secs[0]
    secs[0] = [re.sub(r"load_steps=\d+", f"load_steps={n}", h), body]
    return secs


def sprite_block(name, rid, offset, desc):
    return [f'[node name="{name}" type="Sprite2D" parent="."]',
            ["visible = false", f'editor_description = "{desc}"', "texture_filter = 1", f'texture = ExtResource("{rid}")',
             "centered = false", f"offset = {offset}"]]


def exists(rel):
    return os.path.exists(os.path.join(ROOT, rel.replace("res://", "")))


def front(bid):
    p = os.path.join(B, bid + ".tscn")
    secs = sections(open(p, encoding="utf-8").read())
    if any(node_name(h) == "SpriteEscalaB" for h, _ in secs):
        print(f"{bid}: ya enchufado")
        return
    i = next(k for k, (h, _) in enumerate(secs) if node_name(h) == "Sprite" and node_parent(h) == ".")
    body = secs[i][1]
    old_id = re.search(r'texture = ExtResource\("([^"]+)"\)', "\n".join(body)).group(1)
    offset = re.search(r"offset = (Vector2\([^)]*\))", "\n".join(body)).group(1)
    secs[i][1] = [re.sub(r'texture = ExtResource\("[^"]+"\)', 'texture = ExtResource("fal_n")', l) for l in body]
    secs[i][1] = [('editor_description = "fal facade (assets/art/buildings/fal/, docs/arte/fal_produccion.md): same '
                   'canvas and anchor as scale B. While the building is under works or damaged WorldView puts the '
                   'texture of LookConstruction / LookDamaged here. The scale B sprite is SpriteEscalaB (hidden)."')
                  if l.startswith("editor_description") else l for l in secs[i][1]]
    adds = [sprite_block("SpriteEscalaB", old_id, offset, "Scale B sprite before the fal facade. To go back: put this "
                         "texture on Sprite and delete LookConstruction / LookDamaged.")]
    exts = [ext(f"{FAL}/{bid}.png", "fal_n")]
    for state, rid, name in (("construction", "fal_c", "LookConstruction"), ("damaged", "fal_d", "LookDamaged")):
        if exists(f"{FAL}/{bid}_{state}.png"):
            exts.append(ext(f"{FAL}/{bid}_{state}.png", rid))
            adds.append(sprite_block(name, rid, offset, f"Texture of Sprite while the building is {WHEN[state]} "
                                     "(WorldView._apply_looks); never shown itself."))
    last_ext = max(k for k, (h, _) in enumerate(secs) if h.startswith("[ext_resource"))
    secs = secs[:last_ext + 1] + [[e, []] for e in exts] + secs[last_ext + 1:]
    i += len(exts)
    secs = secs[:i + 1] + adds + secs[i + 1:]
    open(p, "w", encoding="utf-8").write(join(fix_steps(secs)))
    print(f"{bid}: frente fal + {len(adds) - 1} estados")


def back(bid):
    p = os.path.join(B, bid + "_back.tscn")
    if os.path.exists(p):
        print(f"{bid}_back: ya existe")
        return
    secs = sections(open(os.path.join(B, bid + ".tscn"), encoding="utf-8").read())
    keep_nodes = {".", "Feet", "Top", "Greybox", "Sprite", "Upgrades", "Works"}
    out = [[re.sub(r' uid="uid://[a-z0-9]+"', "", secs[0][0]), []]]
    nodes = []
    for h, body in secs[1:]:
        if not h.startswith("[node"):
            continue
        name, parent = node_name(h), node_parent(h)
        top = parent is None or (parent == "." and name in keep_nodes) or \
            (parent or "").split("/")[0] in ("Greybox", "Upgrades", "Works")
        if parent is None:
            h = re.sub(r'name="([^"]+)"', lambda m: f'name="{m.group(1)}Back"', h, count=1)
            body = [('editor_description = "%s seen from behind (fal: no door on its visible faces, same canvas and '
                     'anchor as its front). WorldView._door_facing draws it when the map door is on a hidden face '
                     '(its Door marker; the front\'s metadata/back)."' % bid) if l.startswith("editor_description")
                    else l for l in body]
        if not top:
            continue
        if name == "Sprite" and parent == ".":
            body = [re.sub(r'texture = ExtResource\("[^"]+"\)', 'texture = ExtResource("fal_n")', l) for l in body]
            body = [('editor_description = "fal back view (assets/art/buildings/fal/%s_back.png); LookConstruction / '
                     'LookDamaged as on the front."' % bid) if l.startswith("editor_description") else l for l in body]
            offset = re.search(r"offset = (Vector2\([^)]*\))", "\n".join(body)).group(1)
        if name == "Door" and parent == ".":
            continue  # marcar_puertas.py writes the back's own marker
        nodes.append([h, body])
    used = {m for _, b in nodes for l in b for m in re.findall(r'ExtResource\("([^"]+)"\)', l)}
    exts = []
    for h, _ in secs[1:]:
        if h.startswith("[ext_resource"):
            rid = re.search(r' id="([^"]+)"', h).group(1)
            if rid in used and rid != "fal_n":
                exts.append([re.sub(r' uid="uid://[a-z0-9]+"', "", h), []])
    exts.append([ext(f"{FAL}/{bid}_back.png", "fal_n"), []])
    for state, rid, name in (("construction", "fal_c", "LookConstruction"), ("damaged", "fal_d", "LookDamaged")):
        if exists(f"{FAL}/{bid}_back_{state}.png"):
            exts.append([ext(f"{FAL}/{bid}_back_{state}.png", rid), []])
            nodes.append(sprite_block(name, rid, offset, f"Texture of Sprite while the building is {WHEN[state]} "
                                      "(WorldView._apply_looks); never shown itself."))
    secs2 = out + exts + nodes
    open(p, "w", encoding="utf-8").write(join(fix_steps(secs2)))
    print(f"{bid}_back: escena nueva ({len(nodes)} nodos)")


def main():
    for bid in FRONTS:
        front(bid)
    for bid in BACKS:
        back(bid)


if __name__ == "__main__":
    sys.exit(main())
