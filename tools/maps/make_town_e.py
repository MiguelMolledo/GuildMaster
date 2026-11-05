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
H7: the living town (GDD 4.11.3, docs/contratos/h7_ciudad.md): "social_points" (benches of 2, chat points of 3, a dice
  point of 3 in the plaza; each slot a walkable tile) and "workplaces" (the townsfolk's trades: the 3 market stalls,
  the armory, church, town hall, fields, river, well and gates; TownLife.assign_occupations gives them in this order to
  the adult townsfolk by id). town_e_start is a v8 save.
H12: the workshops of the other trades (workshop_carpentry, workshop_masonry, workshop_tailor) and the clothier's and
  goods stalls. town_e_start does not place them (it is the H7 sandbox): their footprints get the decor's lots.
Town builder: "decor", the cosmetic dressing by the rules of tools/city/reglas.json (docs/protocolos/generar-ciudad.md).
This script is the source of data/maps/town_e.json and data/scenarios/town_e_start.json and rebuilds both byte for
byte. --check writes nothing: it exits with 1 (and says which file) if either differs from what it would write, e.g.
after editing the map by hand (then bring the change here) or the town builder's rules (then re-run without --check).
"""
import json, os, sys

CHECK = "--check" in sys.argv[1:]
_DIFF = []


def _emit(rel, text):
    """Writes ROOT/rel, or with --check compares it with what is there."""
    path = os.path.join(ROOT, rel)
    if CHECK:
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if old != text:
            _DIFF.append(rel)
        return
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

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

# H12: the workshops of the other trades (carpentry and masonry 3x4 south of the bottom lane, tailor's 3x3 east of
# the town hall), doors on the lane or the grass in front
rect(14, 34, 16, 37, "#")
rect(19, 34, 21, 37, "#")
rect(23, 30, 25, 32, "#")
# Posada (docs/gdd/04f_vida_y_fiestas.md §4.27): the Taberna-Posada for sale, 3x4 (the carpentry's footprint, like its
# art) on the meadow south of the bottom lane (cols 26-28 x rows 34-37), door on the lane at (27, 33). A new game places
# it without owner (NewGame, for_sale).
rect(26, 34, 28, 37, "#")
# market stalls and the contract board (H3): one blocked tile each, served from the tile in front (towards the street);
# H12: the clothier's and the goods stalls on the west edge of the plaza, served from the tile to their east
STALLS = {"resources": ([16, 14], [16, 15]), "food": ([19, 14], [19, 15]), "materials": ([22, 14], [22, 15]),
          "clothier": ([15, 16], [16, 16]), "goods": ([15, 20], [16, 20])}
BOARD = [16, 22]
for t, _ in STALLS.values():
    g[t[1]][t[0]] = "S"
g[BOARD[1]][BOARD[0]] = "N"

rows = ["".join(r) for r in g]

town = {
    "id": "town_e",
    "name_key": "map.town_e",
    "size": [W, H],
    "rows": rows,
    "spawns": {"player": [20, 21], "market": [19, 16], "east_gate": [39, 18], "west_gate": [0, 19]},
    "stalls": {k: {"tile": t, "service": sv} for k, (t, sv) in STALLS.items()},
    "board": {"tile": BOARD, "service": [BOARD[0], BOARD[1] - 1]},
    # H9 (docs/contratos/h9_titulos.md): the town hall on the south block of the plaza; titles are asked for on its
    # service tile (like the board). A map site, not a building of the state.
    "town_hall": {"origin": [17, 26], "footprint": [6, 4], "tile": [20, 26], "service": [20, 25]},
    "buildings": {
        "player_forge": {"type": "forge", "origin": [25, 20], "door": [26, 19]},
        "rival_forge": {"type": "forge", "origin": [9, 20], "door": [10, 19]},
        # H12 (1b): the rival of the player's own trade takes the player forge's plot when the player is not the
        # smith (data/starts rival.building.site); alternatives of player_forge, never built together with it
        "rival_carpentry": {"type": "carpentry", "origin": [25, 20], "door": [26, 19]},
        "rival_masonry": {"type": "masonry", "origin": [25, 20], "door": [26, 19]},
        "rival_tailor": {"type": "tailor_shop", "origin": [25, 20], "door": [26, 19]},
        # H12: the workshops of the competitor families (data/starts competitors) and of the other trades' starts
        "workshop_carpentry": {"type": "carpentry", "origin": [14, 34], "door": [15, 33]},
        "workshop_masonry": {"type": "masonry", "origin": [19, 34], "door": [20, 33]},
        "workshop_tailor": {"type": "tailor_shop", "origin": [23, 30], "door": [24, 29]},
        "armory": {"type": "armory", "origin": [25, 14], "door": [24, 16], "owner": ""},
        # Posada: on sale until a family buys it (buy_building); new games only (the scenarios of before have none)
        "tavern_inn": {"type": "tavern_inn", "origin": [26, 34], "door": [27, 33], "for_sale": True},
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
    # H8: adults of 18-30 years and their palette tones (GDD 4.10.9; data/family.json visual: 6 hair, 4 skin)
    return {"name": name, "female": female, "rank": rank, "stats": st, "age": 18 + (i * 5) % 13,
            "visual": {"hair": (i * 5) % 6, "skin": (i * 3) % 4}}

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
# H7 · social points (GDD 4.11.3) and the townsfolk's trades (workplaces), in the order they are handed out.
town["social_points"] = [
    {"id": "bench_w", "kind": "bench", "slots": [[15, 23], [15, 24]]},
    {"id": "bench_e", "kind": "bench", "slots": [[24, 22], [24, 23]]},
    {"id": "bench_n", "kind": "bench", "slots": [[24, 13], [24, 14]]},
    {"id": "chat_well", "kind": "chat", "slots": [[18, 17], [20, 17], [21, 18]]},
    {"id": "chat_board", "kind": "chat", "slots": [[17, 21], [17, 22], [18, 22]]},
    {"id": "dice_plaza", "kind": "dice", "slots": [[21, 22], [22, 22], [22, 23]]},
]
town["workplaces"] = [
    {"id": "gate_west", "kind": "tile", "tile": [1, 19]},
    {"id": "stall_food", "kind": "stall", "tile": [19, 13], "stall": "food"},
    {"id": "field_a", "kind": "tile", "tile": [3, 28]},
    {"id": "field_b", "kind": "tile", "tile": [5, 30]},
    {"id": "river_bank", "kind": "tile", "tile": [34, 10]},
    {"id": "stall_materials", "kind": "stall", "tile": [22, 13], "stall": "materials"},
    {"id": "gate_east", "kind": "tile", "tile": [38, 19]},
    {"id": "well", "kind": "tile", "tile": [20, 19]},
    {"id": "church_a", "kind": "tile", "tile": [18, 12]},
    {"id": "stall_resources", "kind": "stall", "tile": [16, 13], "stall": "resources"},
    {"id": "armory", "kind": "shop", "tile": [24, 16], "building": "armory", "stall": "armory"},
    {"id": "church_b", "kind": "tile", "tile": [21, 12]},
    {"id": "field_c", "kind": "tile", "tile": [2, 34]},
    {"id": "field_d", "kind": "tile", "tile": [10, 35]},
    {"id": "townhall_a", "kind": "tile", "tile": [18, 25]},
    {"id": "townhall_b", "kind": "tile", "tile": [21, 25]},
]
WALK = set("=P,fb.")
for sp in town["social_points"]:
    for c, r in sp["slots"]:
        assert rows[r][c] in WALK, ("social point not walkable", sp["id"], c, r, rows[r][c])
for wp in town["workplaces"]:
    c, r = wp["tile"]
    assert rows[r][c] in WALK, ("workplace not walkable", wp["id"], c, r, rows[r][c])

town["population"] = []
n = 0
for home, fam_name, c1, c2, members in POP:
    people = []
    for name, female, rank, craft in members:
        people.append(npc(n, name, female, rank, craft))
        n += 1
    town["population"].append({"home": home, "family_name": fam_name, "gold": 20,
                               "colors": {"primary": c1, "secondary": c2}, "members": people})
# The cosmetic dressing (filler houses facing the street, yards, lanterns, props, fences), by the rules of the town
# builder (tools/city/, docs/protocolos/generar-ciudad.md): only the game draws it, the sim never reads it.
import sys  # noqa: E402
sys.path.insert(0, os.path.join(ROOT, "tools", "city"))
sys.dont_write_bytecode = True
import citylib  # noqa: E402
town["decor"] = citylib.dress(citylib.Map(town, citylib.Catalog()))
# 04f 4.24.2 / 4.24.4: the meeting points (well, atrium, washhouse, bridge, gates, open plaza) and the night watch's
# patrols, added after the decor and never on it: the dressing and H7's points (the targets) stay as they were.
citylib.add_life(town, citylib.Catalog())
# The plots of 04 §4.9.1 (tools/city/plots.py): data the sim never reads (the targets do not move), drawn by the view.
import plots  # noqa: E402
plots.add_plots(town, citylib.Catalog())
_emit("data/maps/town_e.json", citylib.dumps_map(town))

def inv(limit_kind, limit, stacks=None):
    return {"limit_kind": limit_kind, "limit": limit, "stacks": stacks or []}

def chr_(id_, name, female, family, ctrl, pos, craft=3, location="", stats=None, rank="", home="", age=25,
         visual=None, profession="blacksmith", occupation=""):
    if stats is None:
        stats = {k: 3 for k in STATS}
        stats["craft"] = craft
    n = int(id_.split("_")[1])
    return {"id": id_, "name": name, "female": female, "family": family, "controlled_by": ctrl,
            "alive": True, "position": pos, "path": [], "move_progress": 0,
            "stats": stats, "inventory": inv("weight", 30.0),
            "equipment": {"tool": None, "clothes": None, "accessory": None},
            "location": location, "station": "", "order_queue": [],
            "home": home, "rank": rank, "job": None, "hire_bans": {}, "routine": {},
            # v7 (H8, docs/contratos/h8_familia.md): born at the start of a calendar year (8 days), the scenario is day 0
            "birth_day": -age * 8, "death_day": -1, "class": "artisan", "profession": profession, "spouse": "",
            "parents": [], "children": [], "assigned": "", "directives": ["work"], "schedule": None,
            "visual": visual or {"hair": n % 6, "skin": n % 4}, "life": {},
            # v8 (H7, docs/contratos/h7_ciudad.md): the townsperson's trade and TownLife's memory
            "occupation": occupation, "town": {}}

def fam_(id_, name, ctrl, members, colors, gold, ai_profile=""):
    return {"id": id_, "name": name, "controlled_by": ctrl, "members": members, "colors": colors,
            "gold": gold, "reputation": 0, "ai_profile": ai_profile, "ai_state": {},
            # v7 (H8): the first member is the head and founder
            "head": members[0], "heir": "", "founder": members[0], "generation": 1, "regent": "",
            "class": "artisan", "goals_done": []}

FOOTPRINTS = {"forge": [3, 4], "armory": [3, 4], "house": [3, 3]}
SLOTS = {"forge": 1}  # data/buildings/<type>.json base_employees

def bld_(id_, key, owner, zones, stacks=10, items=None):
    b = town["buildings"][key]
    return {"id": id_, "type": b["type"], "owner": owner, "origin": b["origin"], "footprint": FOOTPRINTS[b["type"]],
            "door": b["door"], "state": "normal", "inventory": inv("stacks", stacks, items),
            "zones": {z: {"occupant": "", "job": None} for z in zones},
            "upkeep_debt": 0, "upkeep_unpaid_since": -1, "employee_slots": SLOTS.get(b["type"], 0),
            "queue": {"entries": [], "loop": False, "paused": False},
            "upgrades": [], "upgrade_work": None,  # v6 (H5): sim/econ/upgrades.gd new_inspection()
            "inspection": {"last_day": -1, "caught": 0, "escaped": 0, "fines": 0, "escape_ready_day": 0}}

FORGE_ZONES = ("furnace", "anvil", "counter", "storage")

scenario = {
    "version": 8, "seed": "1", "rng_state": "",
    "meta": {"title": "Pueblo-calle", "description": "Arenero de pruebas: mapa town_e con la familia del jugador (3) y su forja (bld_0001), dos vecinos, el herrero rival Bernat en su forja (bld_0002, familia IA Ferrer), la Armería pública (bld_0003) y 16 vecinos sin empleo en sus 8 casas (bld_0004-0011, candidatos a empleado). Sin préstamo."},
    "map_id": "town_e",
    "clock": {"minute": 480},
    "characters": {
        "chr_0001": chr_("chr_0001", "Hugo", False, "fam_0001", "human", [20, 21], craft=7, age=20),
        "chr_0002": chr_("chr_0002", "Elena", True, "fam_0001", "human", [21, 21], craft=4, age=24),
        "chr_0003": chr_("chr_0003", "Tomás", False, "fam_0001", "human", [19, 22], craft=2, age=18),
        "chr_0004": chr_("chr_0004", "Marta", True, "fam_0002", "ai", [8, 12], age=30, profession=""),
        "chr_0005": chr_("chr_0005", "Pere", False, "fam_0002", "ai", [30, 25], age=32, profession=""),
        "chr_0006": chr_("chr_0006", "Bernat", False, "fam_0003", "ai", [10, 19], craft=5, location="bld_0002", age=35),
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
    # v8 (H7): microevents and the shop counters
    "microevents": {"active": [], "pending": [], "cooldowns": {}, "last_day": {}}, "town": {"counters": {}},
}
# H4 · the townsfolk: a household family and a house per entry of the population, its members inside (at home).
nid = scenario["next_ids"]
widx = 0  # H7: the trades in map order to the townsfolk by id (TownLife.assign_occupations does the same)
for hh in town["population"]:
    fid, bid = "fam_%04d" % nid["fam"], "bld_%04d" % nid["bld"]
    nid["fam"] += 1
    nid["bld"] += 1
    members = []
    for p in hh["members"]:
        cid = "chr_%04d" % nid["chr"]
        nid["chr"] += 1
        scenario["characters"][cid] = chr_(cid, p["name"], p["female"], fid, "ai", town["buildings"][hh["home"]]["door"],
                                           location=bid, stats=dict(p["stats"]), rank=p["rank"], home=bid,
                                           age=p["age"], visual=dict(p["visual"]),
                                           occupation=town["workplaces"][widx]["id"])
        widx += 1
        members.append(cid)
    scenario["families"][fid] = fam_(fid, hh["family_name"], "ai", members, hh["colors"], hh["gold"])
    scenario["buildings"][bid] = bld_(bid, hh["home"], fid, (), stacks=0)

_emit("data/scenarios/town_e_start.json", json.dumps(scenario, indent=2, ensure_ascii=False) + "\n")
if CHECK:
    if _DIFF:
        print("make_town_e --check: estos ficheros no son lo que escribe este script: " + ", ".join(_DIFF) +
              ". Si el cambio es bueno, llévalo al script; si las reglas de tools/city cambiaron, ejecútalo sin --check.")
        sys.exit(1)
    print("make_town_e --check: data/maps/town_e.json y data/scenarios/town_e_start.json, idénticos")
if not CHECK:
    print("\n".join(rows))
