#!/usr/bin/env python3
"""Builds data/maps/town_e.json (H1 street village, D10 style E, 40x40) and the scenario
data/scenarios/town_e_start.json. Deterministic: same script, same files. Re-run after editing the layout.

Layout (col = x, row = y; row 0 is the top-right edge on screen in 2:1 iso):
  main street rows 18-19 across the map, plaza cols 15-24 x rows 13-24, lanes at cols 7 and 31,
  terraced houses along the main street and lanes, river at cols 35-36 with a bridge on the main street,
  fields in the lower left, trees in the upper band.
H2: the family forge (cols 25-27 x rows 20-23, door (26,19) on the main street).
H3: the market in the plaza (3 outdoor stalls and the contract board, blocked tiles with a service tile in front),
  the armory (public shop with interior, cols 25-27 x rows 14-17, door (24,16) on the plaza) and the rival forge
  (cols 9-11 x rows 20-23, door (10,19), symmetric to the family one). The map declares them: "stalls", "board" and
  "buildings" (the initial buildings a new game places, GDD 06).
H4: the townsfolk (GDD 4.11.1, 4.7.1): 8 houses (type house, 3x3, one per house block, door on the street or lane)
  and "population": one household family per house with 2 unemployed adults each (16 NPC: 9 apprentices,
  5 journeymen, 2 masters), the candidates to hire. NewGame.from_start and town_e_start place them.
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
# the family forge (H2): 3x4 footprint at cols 25-27, rows 20-23, door on the main street at (26, 19);
# the rest of that block stays a house
rect(25, 20, 29, 23, ".")
rect(25, 20, 27, 23, "#")
rect(28, 20, 29, 22, "#")
# the rival's forge (H3): mirror of the family forge on the west side of the plaza
rect(9, 20, 13, 23, ".")
rect(9, 20, 11, 23, "#")
rect(12, 20, 13, 22, "#")
# the armory (H3): public shop at the north-east corner of the plaza, the rest of that block stays a house
rect(25, 14, 27, 17, "#")
# church north of the plaza, town hall south of it (blocked footprints)
rect(17, 8, 22, 11, "#")
rect(17, 26, 22, 29, "#")
# well in the plaza
g[18][19] = "#"
# keep the plaza edge open to the street
rect(15, 18, 24, 19, "P")
g[18][19] = "#"

# market stalls and the contract board (H3): one blocked tile each, served from the tile in front (towards the street)
STALLS = {"resources": [16, 14], "food": [19, 14], "materials": [22, 14]}
BOARD = [16, 22]
for t in STALLS.values():
    g[t[1]][t[0]] = "S"
g[BOARD[1]][BOARD[0]] = "N"

rows = ["".join(r) for r in g]

town = {
    "id": "town_e",
    "name_key": "map.town_e",
    "size": [W, H],
    "rows": rows,
    "spawns": {"player": [20, 21], "market": [19, 16], "east_gate": [39, 18], "west_gate": [0, 19]},
    "stalls": {k: {"tile": t, "service": [t[0], t[1] + 1]} for k, t in STALLS.items()},
    "board": {"tile": BOARD, "service": [BOARD[0], BOARD[1] - 1]},
    "buildings": {
        "player_forge": {"type": "forge", "origin": [25, 20], "door": [26, 19]},
        "rival_forge": {"type": "forge", "origin": [9, 20], "door": [10, 19]},
        "armory": {"type": "armory", "origin": [25, 14], "door": [24, 16], "owner": ""},
    },
}

# H4 · townsfolk houses (3x3 at the corner of each house block) and the population that lives there.
HOUSES = {
    "house_w_north": ([1, 15], [2, 18]),
    "house_w_south": ([1, 20], [2, 19]),
    "house_e_north": ([32, 15], [33, 18]),
    "house_e_south": ([32, 20], [33, 19]),
    "house_nw": ([9, 8], [10, 7]),
    "house_ne": ([25, 8], [26, 7]),
    "house_sw": ([9, 26], [10, 25]),
    "house_se": ([25, 26], [26, 25]),
}
for key, (origin, door) in HOUSES.items():
    town["buildings"][key] = {"type": "house", "origin": origin, "door": door}

STATS = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution", "rhetoric", "stealth"]
BASE = {"charisma": 4, "empathy": 3, "negotiation": 6, "arcane": 1, "dexterity": 4, "craft": 7, "martial": 3,
        "constitution": 5, "rhetoric": 3, "stealth": 2}  # the artisan's distribution (GDD 4.2.2)

def npc(i, name, female, rank, craft):
    """A townsperson: the artisan base with a fixed spread per person (no randomness: same script, same file)."""
    st = dict(BASE)
    st["craft"] = craft
    st["charisma"] = 2 + (i * 3) % 5
    st["constitution"] = 3 + (i * 2) % 5
    st["empathy"] = 2 + (i * 5) % 4
    st["dexterity"] = 3 + (i * 7) % 4
    return {"name": name, "female": female, "rank": rank, "stats": st}

# 9 apprentices (craft 1-3), 5 journeymen (4-6), 2 masters (7-8): abundant, medium, scarce (GDD 4.7.2)
POP = [
    ("house_w_north", "Soler", "#7a5230", "#d8c8a0", [("Joan", False, "journeyman", 5), ("Agnès", True, "apprentice", 2)]),
    ("house_w_south", "Puig", "#4a6a8a", "#e0d0b0", [("Pau", False, "apprentice", 3), ("Clara", True, "apprentice", 2)]),
    ("house_e_north", "Roca", "#6a6a6a", "#c0a060", [("Arnau", False, "master", 8), ("Elisenda", True, "journeyman", 4)]),
    ("house_e_south", "Vila", "#8a7a3a", "#3a3a4a", [("Martí", False, "apprentice", 1), ("Blanca", True, "apprentice", 3)]),
    ("house_nw", "Serra", "#5a3a5a", "#d0b890", [("Guillem", False, "journeyman", 6), ("Sança", True, "apprentice", 2)]),
    ("house_ne", "Font", "#3a6a6a", "#e8d8b8", [("Jaume", False, "apprentice", 3), ("Margarida", True, "journeyman", 4)]),
    ("house_sw", "Pons", "#7a3a2a", "#b0b0a0", [("Ramon", False, "master", 7), ("Isabel", True, "apprentice", 1)]),
    ("house_se", "Mas", "#4a5a2a", "#d8b878", [("Berenguer", False, "journeyman", 5), ("Violant", True, "apprentice", 2)]),
]
town["population"] = []
n = 0
for home, fam_name, c1, c2, members in POP:
    people = []
    for name, female, rank, craft in members:
        people.append(npc(n, name, female, rank, craft))
        n += 1
    town["population"].append({"home": home, "family_name": fam_name, "gold": 20,
                               "colors": {"primary": c1, "secondary": c2}, "members": people})
with open(os.path.join(ROOT, "data/maps/town_e.json"), "w") as f:
    json.dump(town, f, indent=1, ensure_ascii=False)
    f.write("\n")

def inv(limit_kind, limit, stacks=None):
    return {"limit_kind": limit_kind, "limit": limit, "stacks": stacks or []}

def chr_(id_, name, female, family, ctrl, pos, craft=3, location="", stats=None, rank="", home=""):
    if stats is None:
        stats = {k: 3 for k in STATS}
        stats["craft"] = craft
    return {"id": id_, "name": name, "female": female, "family": family, "controlled_by": ctrl,
            "alive": True, "position": pos, "path": [], "move_progress": 0,
            "stats": stats, "inventory": inv("weight", 30.0),
            "equipment": {"tool": None, "clothes": None, "accessory": None},
            "location": location, "station": "", "order_queue": [],
            "home": home, "rank": rank, "job": None, "hire_bans": {}, "routine": {}}

def fam_(id_, name, ctrl, members, colors, gold, ai_profile=""):
    return {"id": id_, "name": name, "controlled_by": ctrl, "members": members, "colors": colors,
            "gold": gold, "reputation": 0, "ai_profile": ai_profile, "ai_state": {}}

FOOTPRINTS = {"forge": [3, 4], "armory": [3, 4], "house": [3, 3]}
SLOTS = {"forge": 1}  # data/buildings/<type>.json base_employees

def bld_(id_, key, owner, zones, stacks=10, items=None):
    b = town["buildings"][key]
    return {"id": id_, "type": b["type"], "owner": owner, "origin": b["origin"], "footprint": FOOTPRINTS[b["type"]],
            "door": b["door"], "state": "normal", "inventory": inv("stacks", stacks, items),
            "zones": {z: {"occupant": "", "job": None} for z in zones},
            "upkeep_debt": 0, "upkeep_unpaid_since": -1, "employee_slots": SLOTS.get(b["type"], 0),
            "queue": {"entries": [], "loop": False, "paused": False}}

FORGE_ZONES = ("furnace", "anvil", "counter", "storage")

scenario = {
    "version": 5, "seed": "1", "rng_state": "",
    "meta": {"title": "Pueblo-calle", "description": "Arenero de pruebas: mapa town_e con la familia del jugador (3) y su forja (bld_0001), dos vecinos, el herrero rival Bernat en su forja (bld_0002, familia IA Ferrer), la Armería pública (bld_0003) y 16 vecinos sin empleo en sus 8 casas (bld_0004-0011, candidatos a empleado). Sin préstamo."},
    "map_id": "town_e",
    "clock": {"minute": 480},
    "characters": {
        "chr_0001": chr_("chr_0001", "Hugo", False, "fam_0001", "human", [20, 21], craft=7),
        "chr_0002": chr_("chr_0002", "Elena", True, "fam_0001", "human", [21, 21], craft=4),
        "chr_0003": chr_("chr_0003", "Tomás", False, "fam_0001", "human", [19, 22], craft=2),
        "chr_0004": chr_("chr_0004", "Marta", True, "fam_0002", "ai", [8, 12]),
        "chr_0005": chr_("chr_0005", "Pere", False, "fam_0002", "ai", [30, 25]),
        "chr_0006": chr_("chr_0006", "Bernat", False, "fam_0003", "ai", [10, 19], craft=5, location="bld_0002"),
    },
    "families": {
        "fam_0001": fam_("fam_0001", "Herrero", "human", ["chr_0001", "chr_0002", "chr_0003"],
                         {"primary": "#8b2e2e", "secondary": "#c8a84e"}, 100),
        "fam_0002": fam_("fam_0002", "Vidal", "ai", ["chr_0004", "chr_0005"],
                         {"primary": "#2e4f8b", "secondary": "#d4b896"}, 50),
        "fam_0003": fam_("fam_0003", "Ferrer", "ai", ["chr_0006"],
                         {"primary": "#3f6b3a", "secondary": "#b8b8b0"}, 80, ai_profile="rival_smith"),
    },
    "buildings": {
        "bld_0001": bld_("bld_0001", "player_forge", "fam_0001", FORGE_ZONES,
                         items=[{"item": "iron", "quality": 0, "qty": 10}, {"item": "coal", "quality": 0, "qty": 6}]),
        "bld_0002": bld_("bld_0002", "rival_forge", "fam_0003", FORGE_ZONES,
                         items=[{"item": "iron", "quality": 0, "qty": 8}, {"item": "coal", "quality": 0, "qty": 4}]),
        "bld_0003": bld_("bld_0003", "armory", "", ("counter",), stacks=0),
    },
    "parcels": {}, "market": {"demand": {}, "regulations": []},
    "offices": {}, "elections": [], "trials": [], "relationships": {}, "emotions": {},
    "events_active": [], "chronicle": [], "next_ids": {"chr": 7, "fam": 4, "bld": 4},  # moved on by the population
    "ledger": {"entries": [], "summaries": {}}, "notices": [], "loans": {},
    "contracts": {"board": [], "accepted": [], "cooldowns": {}, "relations": {}}, "deliveries": [],
    "difficulty": "normal", "objectives": {}, "ending": {},
}
# H4 · the townsfolk: a household family and a house per entry of the population, its members inside (at home).
nid = scenario["next_ids"]
for hh in town["population"]:
    fid, bid = "fam_%04d" % nid["fam"], "bld_%04d" % nid["bld"]
    nid["fam"] += 1
    nid["bld"] += 1
    members = []
    for p in hh["members"]:
        cid = "chr_%04d" % nid["chr"]
        nid["chr"] += 1
        scenario["characters"][cid] = chr_(cid, p["name"], p["female"], fid, "ai", town["buildings"][hh["home"]]["door"],
                                           location=bid, stats=dict(p["stats"]), rank=p["rank"], home=bid)
        members.append(cid)
    scenario["families"][fid] = fam_(fid, hh["family_name"], "ai", members, hh["colors"], hh["gold"])
    scenario["buildings"][bid] = bld_(bid, hh["home"], fid, (), stacks=0)

with open(os.path.join(ROOT, "data/scenarios/town_e_start.json"), "w") as f:
    json.dump(scenario, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("\n".join(rows))
