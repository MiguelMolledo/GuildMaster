#!/usr/bin/env python3
"""One-off: writes the Door marker (Marker2D "Door" with its metadata) into the building and house scenes
(docs/protocolos/generar-ciudad.md §Puertas). The thresholds below were read by eye on each sprite (helped by
tools/city/proponer_puerta.py, reviewed on a grid) on 2026-11-04 (re-checked on the fal facades the same day: the thresholds did not move). From now on the marker in the scene is the source:
move it in Godot and run `python3 tools/city/sprites_catalog.py` to refresh data/building_sprites.json.

  python3 tools/city/marcar_puertas.py            adds the marker where it is missing; leaves existing ones alone
  python3 tools/city/marcar_puertas.py --update   also rewrites the existing ones from the table below

Metadata of the marker: side (SW = lower-left face, looks to +row; SE = lower-right, +col; NE = -row; NW = -col,
the two hidden ones), tile (the door's tile relative to the footprint's origin, outside the footprint on that side),
footprint (the one the sprite is drawn for), mirror (may be mirrored: no text on it), back / front (the scene seen
from the other side, "" if none). The position is the threshold in the scene (pixels from Feet = the footprint's
centre). The mirror needs no marker of its own: x -> -x swaps the side (SW <-> SE, NE <-> NW).
"""
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citylib  # noqa: E402

VIS = os.path.join(citylib.ROOT, "game", "visuals")

# scene: (side, threshold px from Feet, footprint, mirror, back scene)
FRONT = {
    "buildings/armory": ("SW", (-8, 0), (3, 4), True, "armory_back"),
    "buildings/carpentry": ("SW", (-40, 12), (3, 4), True, "carpentry_back"),
    "buildings/forge": ("SE", (24, 12), (3, 4), True, "forge_back"),
    "buildings/house": ("SW", (-39, 8), (3, 3), True, "house_back"),
    "buildings/house_slate": ("SW", (-29, 18), (3, 3), True, "house_slate_back"),
    "buildings/house_ochre": ("SW", (-42, 15), (3, 3), True, "house_ochre_back"),
    "buildings/house_tall": ("SW", (-25, 13), (3, 3), True, "house_tall_back"),
    "buildings/masonry": ("SW", (-25, 20), (3, 4), True, "masonry_back"),
    "buildings/tailor_shop": ("SE", (39, 6), (3, 3), True, "tailor_shop_back"),  # fal: scissors, no text
    "buildings/town_hall": ("SW", (-64, 9), (6, 4), False, "town_hall_back"),
    "props/lot_house_a": ("SW", (-29, 18), (3, 3), True, "lot_house_a_back"),
    "props/lot_house_b": ("SW", (-25, 13), (3, 3), True, "lot_house_b_back"),
    "props/lot_house_c": ("SW", (-42, 15), (3, 3), True, "lot_house_c_back"),
    "props/lot_house_d": ("SW", (-26, 15), (3, 3), True, "lot_house_d_back"),
    "props/lot_house_e": ("SW", (-29, 18), (3, 3), True, "lot_house_e_back"),
    "props/lot_house_f": ("SW", (-42, 15), (3, 3), True, "lot_house_f_back"),
}
OPPOSITE = {"SW": "NE", "SE": "NW", "NE": "SW", "NW": "SE"}


def entries():
    out = {}
    for scene, (side, px, foot, mirror, back) in FRONT.items():
        out[scene] = {"side": side, "px": px, "footprint": foot, "mirror": mirror, "back": back, "front": ""}
        if back:
            kind = scene.split("/")[0]
            # seen from behind: the door is on the opposite face, its threshold mirrored through the centre
            out[f"{kind}/{back}"] = {"side": OPPOSITE[side], "px": (-px[0], -px[1]), "footprint": foot,
                                     "mirror": mirror, "back": "", "front": scene.split("/")[1]}
    return out


def node_text(e):
    tile = citylib.door_tile(e["side"], e["px"], e["footprint"])
    return (f'[node name="Door" type="Marker2D" parent="."]\n'
            f'editor_description = "Threshold of the drawn door (docs/protocolos/generar-ciudad.md §Puertas): the '
            f'generator, the validator and WorldView read where the door is from here (data/building_sprites.json '
            f'is exported from it: python3 tools/city/sprites_catalog.py). side = face of the footprint (SW, SE, '
            f'NE, NW), tile = door tile from the footprint origin."\n'
            f'position = Vector2({e["px"][0]}, {e["px"][1]})\n'
            f'metadata/side = "{e["side"]}"\n'
            f'metadata/tile = Vector2i({tile[0]}, {tile[1]})\n'
            f'metadata/footprint = Vector2i({e["footprint"][0]}, {e["footprint"][1]})\n'
            f'metadata/mirror = {"true" if e["mirror"] else "false"}\n'
            f'metadata/back = "{e["back"]}"\n'
            f'metadata/front = "{e["front"]}"\n')


def main():
    n = 0
    for scene, e in sorted(entries().items()):
        p = os.path.join(VIS, scene + ".tscn")
        s = open(p, encoding="utf-8").read()
        has = re.search(r'\[node name="Door" type="Marker2D" parent="\."\]\n(?:[^\[\n][^\n]*\n)*\n?', s)
        if has and "--update" not in sys.argv[1:]:
            print(f"{scene}: ya tiene Door")
            continue
        if has:
            s = s[:has.start()] + node_text(e) + "\n" + s[has.end():]
            open(p, "w", encoding="utf-8").write(s)
            print(f"{scene}: Door reescrito {e['side']} {e['px']} back={e['back']!r} mirror={e['mirror']}")
            n += 1
            continue
        m = re.search(r'(\[node name="Top" type="Marker2D" parent="\."\]\n(?:[^\[\n][^\n]*\n)*)', s)
        if not m:
            print(f"{scene}: sin Top, no sé dónde ponerlo")
            continue
        block = m.group(1)
        if not block.endswith("\n\n"):
            block_new = block + "\n" + node_text(e) + "\n"
        else:
            block_new = block + node_text(e) + "\n"
        s = s.replace(block, block_new, 1)
        open(p, "w", encoding="utf-8").write(s)
        print(f"{scene}: Door {e['side']} {e['px']} -> {citylib.door_tile(e['side'], e['px'], e['footprint'])}")
        n += 1
    print(f"{n} escenas con marcador nuevo")


if __name__ == "__main__":
    main()
