#!/usr/bin/env python3
"""The catalogue of drawn doors: data/building_sprites.json, exported from the Door marker of each scene
(docs/protocolos/generar-ciudad.md §Puertas). The generator and the validator read the catalogue, never the scenes;
tests/test_ciudad_sprites.gd checks that the catalogue and the markers match.

  python3 tools/city/sprites_catalog.py            write data/building_sprites.json from the scenes
  python3 tools/city/sprites_catalog.py --check    exit 1 if the catalogue is not what the scenes say, a scene that
                                                   must have a door has no marker, or a marker is inconsistent

Scenes that must carry a Door marker: every game/visuals/buildings/*.tscn (not the _ ones) and the filler houses
game/visuals/props/lot_house_*.tscn. Any other scene with a Door marker (a yard gate, a field entrance...) joins the
catalogue too. Consistency: side is SW/SE/NE/NW, tile is the one door_tile() gives for the position, back/front name
scenes that exist and point back.
"""
import json
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citylib  # noqa: E402

VIS = os.path.join(citylib.ROOT, "game", "visuals")
OUT = os.path.join(citylib.DATA, "building_sprites.json")
DOC = ("Where each building and house scene draws its door (docs/protocolos/generar-ciudad.md §Puertas), exported "
       "from the Door marker of the scene by tools/city/sprites_catalog.py: do not edit by hand, move the marker in "
       "Godot and re-export (tests/test_ciudad_sprites.gd checks they match). Key = <kind>/<scene id>. door.side = "
       "face of the footprint (SW looks to +row, SE to +col, NE to -row, NW to -col), door.tile = the door's tile from "
       "the footprint's origin, door.px = the threshold in pixels from Feet; mirror = may be mirrored (x -> -x swaps "
       "SW/SE and NE/NW); back / front = the same building seen from the other side. Read by tools/city/ "
       "(generator, validator); the game reads the marker of the scene it draws.")


def must_have():
    out = []
    for f in sorted(os.listdir(os.path.join(VIS, "buildings"))):
        if f.endswith(".tscn") and not f.startswith("_"):
            out.append("buildings/" + f[:-5])
    for f in sorted(os.listdir(os.path.join(VIS, "props"))):
        if f.startswith("lot_house_") and f.endswith(".tscn"):
            out.append("props/" + f[:-5])
    return out


def read_marker(scene):
    text = open(os.path.join(VIS, scene + ".tscn"), encoding="utf-8").read()
    m = re.search(r'\[node name="Door" type="Marker2D" parent="\."\]\n((?:[^\[\n][^\n]*\n?)*)', text)
    if not m:
        return None
    body = m.group(1)

    def meta(k, default=None):
        mm = re.search(rf"^metadata/{k} = (.+)$", body, re.M)
        return mm.group(1).strip() if mm else default

    pos = re.search(r"^position = Vector2\(([-\d.]+), ([-\d.]+)\)$", body, re.M)
    px = [float(pos.group(1)), float(pos.group(2))] if pos else [0.0, 0.0]
    px = [int(v) if v == int(v) else v for v in px]

    def v2i(t):
        mm = re.match(r"Vector2i\((-?\d+), (-?\d+)\)", t or "")
        return [int(mm.group(1)), int(mm.group(2))] if mm else None

    return {"footprint": v2i(meta("footprint")), "door": {"side": (meta("side") or "").strip('"'),
                                                           "tile": v2i(meta("tile")), "px": px},
            "mirror": meta("mirror") == "true", "back": (meta("back") or '""').strip('"'),
            "front": (meta("front") or '""').strip('"')}


def scan():
    scenes, problems = {}, []
    for kind in ("buildings", "props"):
        for f in sorted(os.listdir(os.path.join(VIS, kind))):
            if not f.endswith(".tscn"):
                continue
            scene = f"{kind}/{f[:-5]}"
            e = read_marker(scene)
            if e is not None:
                scenes[scene] = e
    for scene in must_have():
        if scene not in scenes:
            problems.append(f"{scene}: sin marcador Door")
    for scene, e in sorted(scenes.items()):
        d = e["door"]
        if d["side"] not in citylib.SIDES:
            problems.append(f"{scene}: side {d['side']!r} no es SW, SE, NE ni NW")
            continue
        if not e["footprint"]:
            problems.append(f"{scene}: sin metadata/footprint")
            continue
        want = list(citylib.door_tile(d["side"], d["px"], e["footprint"]))
        if d["tile"] != want:
            problems.append(f"{scene}: tile {d['tile']} no casa con la posición {d['px']} en {d['side']} ({want})")
        kind = scene.split("/")[0]
        for k, other in (("back", "front"), ("front", "back")):
            if e[k]:
                o = scenes.get(f"{kind}/{e[k]}")
                if o is None:
                    problems.append(f"{scene}: {k} {e[k]} no es una escena con marcador")
                elif o[other] != scene.split("/")[1]:
                    problems.append(f"{scene}: {k} {e[k]} no apunta de vuelta ({other} = {o[other]!r})")
    return scenes, problems


def dumps(scenes):
    lines = ["{", f'  "_doc": {json.dumps(DOC, ensure_ascii=False)},', '  "scenes": {']
    keys = sorted(scenes)
    for i, k in enumerate(keys):
        lines.append(f'    {json.dumps(k)}: {json.dumps(scenes[k], ensure_ascii=False)}{"," if i < len(keys) - 1 else ""}')
    lines += ["  }", "}"]
    return "\n".join(lines) + "\n"


def check():
    """Problems of the scenes and of the catalogue against them ([] = all good)."""
    scenes, problems = scan()
    text = dumps(scenes)
    if not os.path.exists(OUT):
        problems.append("falta data/building_sprites.json (python3 tools/city/sprites_catalog.py)")
    elif open(OUT, encoding="utf-8").read() != text:
        problems.append("data/building_sprites.json no es lo que dicen los marcadores (python3 tools/city/sprites_catalog.py)")
    return problems


def main(argv):
    if "--check" in argv:
        problems = check()
        for p in problems:
            print("  ERROR", p)
        print(f"sprites_catalog: {len(problems)} problemas")
        return 1 if problems else 0
    scenes, problems = scan()
    for p in problems:
        print("  ERROR", p)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(dumps(scenes))
    print(f"sprites_catalog: {len(scenes)} escenas -> {os.path.relpath(OUT, citylib.ROOT)} ({len(problems)} problemas)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
