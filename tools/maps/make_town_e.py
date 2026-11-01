#!/usr/bin/env python3
"""Builds data/maps/town_e.json (H1 street village, D10 style E, 40x40) and the scenario
data/scenarios/town_e_start.json. Deterministic: same script, same files. Re-run after editing the layout.

Layout (col = x, row = y; row 0 is the top-right edge on screen in 2:1 iso):
  main street rows 18-19 across the map, plaza cols 15-24 x rows 13-24, lanes at cols 7 and 31,
  terraced houses along the main street and lanes, river at cols 35-36 with a bridge on the main street,
  fields in the lower left, trees in the upper band.
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
W = H = 40

g = [["." for _ in range(W)] for _ in range(H)]

def rect(c0, r0, c1, r1, ch):
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            if 0 <= c < W and 0 <= r < H:
                g[r][c] = ch

# trees in the upper band and a grove at the bottom right
for (c, r) in [(2,1),(5,2),(9,1),(12,3),(17,1),(21,2),(26,1),(29,3),(33,2),(3,5),(24,4),(38,6),(38,30),(39,33),(37,37),(33,38)]:
    g[r][c] = "T"
# fields lower left
rect(1, 27, 12, 37, "f")
rect(1, 32, 12, 32, ",")  # a dirt track between the fields
# river with banks
rect(35, 0, 36, H - 1, "w")
# main street, plaza, lanes
rect(0, 18, W - 1, 19, "=")
rect(15, 13, 24, 24, "P")
rect(7, 6, 7, 33, "=")
rect(31, 6, 31, 33, "=")
rect(7, 6, 31, 6, ",")     # back lane (dirt) along the top
rect(7, 33, 31, 33, ",")   # back lane along the bottom
rect(35, 18, 36, 19, "b")  # bridge
rect(37, 18, 39, 19, "=")
# terraced houses along the main street (gaps every few houses for alleys)
for c0 in (1, 9, 25, 32):
    for r0 in (15, 20):
        rect(c0, r0, c0 + 4, r0 + 2, "#")
for c0 in (9, 25):
    for r0 in (8, 26):
        rect(c0, r0, c0 + 4, r0 + 3, "#")
# alleys through the house blocks
for c in (11, 27):
    rect(c, 15, c, 17, ",")
    rect(c, 20, c, 22, ",")
# church north of the plaza, town hall south of it (blocked footprints)
rect(17, 8, 22, 11, "#")
rect(17, 26, 22, 29, "#")
# well in the plaza
g[18][19] = "#"
# keep the plaza edge open to the street
rect(15, 18, 24, 19, "P")
g[18][19] = "#"

rows = ["".join(r) for r in g]

town = {
    "id": "town_e",
    "name_key": "map.town_e",
    "size": [W, H],
    "rows": rows,
    "spawns": {"player": [20, 21], "market": [19, 16], "east_gate": [39, 18], "west_gate": [0, 19]},
}
with open(os.path.join(ROOT, "data/maps/town_e.json"), "w") as f:
    json.dump(town, f, indent=1, ensure_ascii=False)
    f.write("\n")

def chr_(id_, name, female, family, ctrl, pos):
    return {"id": id_, "name": name, "female": female, "family": family, "controlled_by": ctrl,
            "alive": True, "position": pos, "path": [], "move_progress": 0}

scenario = {
    "version": 2, "seed": "1", "rng_state": "",
    "meta": {"title": "Pueblo-calle", "description": "H1: mapa town_e con la familia del jugador (3) y dos vecinos quietos."},
    "map_id": "town_e",
    "clock": {"minute": 480},
    "characters": {
        "chr_0001": chr_("chr_0001", "Hugo", False, "fam_0001", "human", [20, 21]),
        "chr_0002": chr_("chr_0002", "Elena", True, "fam_0001", "human", [21, 21]),
        "chr_0003": chr_("chr_0003", "Tomás", False, "fam_0001", "human", [19, 22]),
        "chr_0004": chr_("chr_0004", "Marta", True, "fam_0002", "ai", [8, 12]),
        "chr_0005": chr_("chr_0005", "Pere", False, "fam_0002", "ai", [30, 25]),
    },
    "families": {
        "fam_0001": {"id": "fam_0001", "name": "Herrero", "controlled_by": "human", "members": ["chr_0001", "chr_0002", "chr_0003"],
                     "colors": {"primary": "#8b2e2e", "secondary": "#c8a84e"}},
        "fam_0002": {"id": "fam_0002", "name": "Vidal", "controlled_by": "ai", "members": ["chr_0004", "chr_0005"],
                     "colors": {"primary": "#2e4f8b", "secondary": "#d4b896"}},
    },
    "buildings": {}, "parcels": {}, "market": {"demand": {}, "regulations": []},
    "offices": {}, "elections": [], "trials": [], "relationships": {}, "emotions": {},
    "events_active": [], "chronicle": [], "next_ids": {"chr": 6, "fam": 3},
}
with open(os.path.join(ROOT, "data/scenarios/town_e_start.json"), "w") as f:
    json.dump(scenario, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("\n".join(rows))
