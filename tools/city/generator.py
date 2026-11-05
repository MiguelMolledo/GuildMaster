"""Town generator (docs/protocolos/generar-ciudad.md §Generar). Offline, deterministic (seed -> same map).

  python3 tools/city/ciudad.py generar --id <id> --layout <calle|plaza|cruce|rio|aldea|abadia> --seed <n>
                                       [--size 40x40] [--start artisan_blacksmith] [--out DIR] [--households N]
                                       [--fields N] [--reach N] [--filler N] [--trees X]

Steps: 1 streets and plaza (the layout), 2 the plaza's market (the template of town_e: stalls, board, well, benches,
chat and dice points), the town hall and the armory around it, 3 parcels along the streets (door always on the
street side), 4 buildings by priority (workshops on the main streets, houses on the secondary ones, the rest filler
blocks), 5 fields, a pond and trees outside, 6 sites, spawns, workplaces and population in the format of
data/maps, 7 the decor by rules (citylib.dress), 8 validation (citylib.validate, strict) and the preview PNG.

A layout is a function (rng, w, h) -> Plan (the streets drawn in the grid, which road tiles are "main", where the
plaza goes, optional river). Add one to LAYOUTS (docs/protocolos/generar-ciudad.md §Añadir un trazado).
"""
import argparse
import json
import os
import random

import citylib
from citylib import DIRS, VISIBLE

PLAZA_W, PLAZA_H = 10, 12
# The plaza's market and meeting points, relative to the plaza's top-left tile: the layout of town_e, which the bots
# and the targets were tuned on (stalls along the top and the west side, the board, the well in the middle).
TEMPLATE = {
    "stalls": {"resources": ((1, 1), (1, 2)), "food": ((4, 1), (4, 2)), "materials": ((7, 1), (7, 2)),
               "clothier": ((0, 3), (1, 3)), "goods": ((0, 7), (1, 7))},
    "board": ((1, 9), (1, 8)),
    "well": (4, 5),
    "social_points": [
        {"id": "bench_w", "kind": "bench", "slots": [(0, 10), (0, 11)]},
        {"id": "bench_e", "kind": "bench", "slots": [(9, 9), (9, 10)]},
        {"id": "bench_n", "kind": "bench", "slots": [(9, 0), (9, 1)]},
        {"id": "chat_well", "kind": "chat", "slots": [(3, 4), (5, 4), (6, 5)]},
        {"id": "chat_board", "kind": "chat", "slots": [(2, 8), (2, 9), (3, 9)]},
        {"id": "dice_plaza", "kind": "dice", "slots": [(6, 9), (7, 9), (7, 10)]},
    ],
    "spawns": {"player": (5, 8), "market": (4, 3)},
    "workplaces_plaza": [("stall_food", "stall", (4, 0), "food"), ("stall_materials", "stall", (7, 0), "materials"),
                         ("well", "tile", (5, 6), None), ("stall_resources", "stall", (1, 0), "resources")],
}
# Workplaces in the hand-out order of town_e (TownLife.assign_occupations gives them in this order).
WORKPLACE_ORDER = ["gate_west", "stall_food", "field_a", "field_b", "river_bank", "stall_materials", "gate_east",
                   "well", "church_a", "stall_resources", "armory", "church_b", "field_c", "field_d", "townhall_a",
                   "townhall_b"]


class Plan:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [["." for _ in range(w)] for _ in range(h)]
        self.main = set()  # road tiles of the main streets (workshops go there)
        self.plaza = (0, 0)  # top-left tile of the plaza
        self.gates = []  # (name, tile) where the main street leaves the map
        self.reserved = set()  # tiles no parcel may take (the plaza's surroundings...)

    def inside(self, c, r):
        return 0 <= c < self.w and 0 <= r < self.h

    def put(self, c, r, ch, main=False):
        if ch == "," and self.at(c, r) in ("=", "b", "P"):
            return  # a dirt lane never cuts a street: where they cross, the street goes on
        if self.inside(c, r):
            self.g[r][c] = ch
            if main:
                self.main.add((c, r))

    def rect(self, c0, r0, c1, r1, ch, main=False):
        for r in range(min(r0, r1), max(r0, r1) + 1):
            for c in range(min(c0, c1), max(c0, c1) + 1):
                self.put(c, r, ch, main)

    def at(self, c, r):
        return self.g[r][c] if self.inside(c, r) else ""


# --- layouts ---------------------------------------------------------------------------------------------------

def _plaza_centre(p, rng, cx, cy):
    """Puts the plaza (PLAZA_W x PLAZA_H) with its middle near (cx, cy), main street through rows +5/+6."""
    px = max(6, min(p.w - PLAZA_W - 6, cx - PLAZA_W // 2 + rng.randint(-1, 1)))
    py = max(7, min(p.h - PLAZA_H - 6, cy - PLAZA_H // 2 + rng.randint(-1, 1)))
    p.plaza = (px, py)
    return px, py


def layout_calle(rng, w, h):
    """Pueblo-calle (like town_e): a main street across the map through the plaza, two lanes across it, back
    lanes of dirt along the top and the bottom."""
    p = Plan(w, h)
    px, py = _plaza_centre(p, rng, w // 2, h // 2)
    y0 = py + 5
    p.rect(0, y0, w - 1, y0 + 1, "=", main=True)
    p.gates = [("west_gate", (0, y0 + 1)), ("east_gate", (w - 1, y0))]
    lw = max(2, px - 8 + rng.randint(-1, 1))
    le = min(w - 3, px + PLAZA_W + 7 + rng.randint(-1, 1))
    top = max(2, y0 - 12 + rng.randint(0, 1))
    bot = min(h - 3, y0 + 14 + rng.randint(-1, 0))
    for x in (lw, le):
        p.rect(x, top, x, bot, "=")
    p.rect(lw, top, le, top, ",")
    p.rect(lw, bot, le, bot, ",")
    return p


def layout_plaza(rng, w, h):
    """Plaza mayor with radial streets: four main streets from the middle of each side of the plaza to the edges
    of the map and a ring lane of dirt round the centre that joins them."""
    p = Plan(w, h)
    px, py = _plaza_centre(p, rng, w // 2, h // 2)
    y0 = py + 5
    p.rect(0, y0, px - 1, y0 + 1, "=", main=True)  # west
    p.rect(px + PLAZA_W, y0, w - 1, y0 + 1, "=", main=True)  # east
    p.rect(px + 4, py + PLAZA_H, px + 5, h - 1, "=", main=True)  # south
    p.rect(px + 8, 0, px + 9, py - 1, "=", main=True)  # north (the town hall stands west of it)
    p.gates = [("west_gate", (0, y0 + 1)), ("east_gate", (w - 1, y0)), ("south_gate", (px + 4, h - 1)),
               ("north_gate", (px + 9, 0))]
    ring = 8 + rng.randint(0, 1)
    c0, r0 = max(1, px - ring), max(1, py - ring + 1)
    c1, r1 = min(w - 2, px + PLAZA_W - 1 + ring), min(h - 2, py + PLAZA_H - 1 + ring - 1)
    for c in range(c0, c1 + 1):
        for r in (r0, r1):
            if p.at(c, r) == ".":
                p.put(c, r, ",")
    for r in range(r0, r1 + 1):
        for c in (c0, c1):
            if p.at(c, r) == ".":
                p.put(c, r, ",")
    # a big town (60 tiles or more, the capital): more rings of streets round the first, every 9 tiles, while they
    # fit; the 40x40 towns never get here (same file as before)
    k = 1
    while w >= 60 and h >= 60:
        g = ring + 9 * k
        c0, r0 = px - g, py - g + 1
        c1, r1 = px + PLAZA_W - 1 + g, py + PLAZA_H - 1 + g - 1
        if c0 < 3 or r0 < 3 or c1 > w - 4 or r1 > h - 4:
            break
        ch = "=" if k == 1 else ","
        for c in range(c0, c1 + 1):
            for r in (r0, r1):
                if p.at(c, r) in (".", ","):
                    p.put(c, r, ch)
        for r in range(r0, r1 + 1):
            for c in (c0, c1):
                if p.at(c, r) in (".", ","):
                    p.put(c, r, ch)
        k += 1
    return p


def layout_cruce(rng, w, h):
    """Crossroads: two main roads cross the whole map; the plaza sits in the north-west corner of the crossing
    (the east-west road runs through it); dirt lanes parallel to both roads."""
    p = Plan(w, h)
    px, py = _plaza_centre(p, rng, w // 2 - 6, h // 2)
    y0 = py + 5
    x0 = px + PLAZA_W + 3 + rng.randint(0, 1)
    p.rect(0, y0, w - 1, y0 + 1, "=", main=True)
    p.rect(x0, 0, x0 + 1, h - 1, "=", main=True)
    p.gates = [("west_gate", (0, y0 + 1)), ("east_gate", (w - 1, y0)), ("north_gate", (x0 + 1, 0)),
               ("south_gate", (x0, h - 1))]
    # dirt lanes: one parallel to each road, on the side away from the plaza
    ys = min(h - 3, y0 + 10 + rng.randint(0, 1))
    xs = min(w - 3, x0 + 10 + rng.randint(0, 1))
    p.rect(max(1, px - 6), ys, min(w - 2, xs), ys, ",")
    p.rect(xs, max(1, py - 8), xs, min(h - 2, ys), ",")
    # a lane west of the plaza joining the road to the south lane
    xw = max(2, px - 6)
    p.rect(xw, max(1, py - 4), xw, ys, ",")
    return p


def layout_rio(rng, w, h):
    """River village with a bridge: a river from north to south in the east third, the main street crosses it on
    a bridge; the town on the west bank with lanes, the fields on the east bank; a dirt path along the river."""
    p = Plan(w, h)
    rx = w * 3 // 4 - 1 + rng.randint(-1, 1)
    p.rect(rx, 0, rx + 1, h - 1, "w")
    px, py = _plaza_centre(p, rng, (rx - 2) // 2 + 1, h // 2)
    y0 = py + 5
    p.rect(0, y0, w - 1, y0 + 1, "=", main=True)
    p.rect(rx, y0, rx + 1, y0 + 1, "b", main=True)
    p.gates = [("west_gate", (0, y0 + 1)), ("east_gate", (w - 1, y0))]
    p.rect(rx - 2, 1, rx - 2, h - 2, ",")  # the towpath on the west bank
    lw = max(2, px - 7 + rng.randint(-1, 0))
    p.rect(lw, max(1, py - 8), lw, min(h - 2, py + PLAZA_H + 6), "=")
    top = max(1, py - 8)
    p.rect(lw, top, rx - 2, top, ",")
    bot = min(h - 2, py + PLAZA_H + 6)
    p.rect(lw, bot, rx - 2, bot, ",")
    return p


def layout_aldea(rng, w, h):
    """Hamlet (aldea, small maps from 30x30): one main road across the map through the plaza (the village green with
    its stalls), two short dirt lanes across it on either side that lead to the fields; nothing else."""
    p = Plan(w, h)
    px, py = _plaza_centre(p, rng, w // 2, h // 2)
    y0 = py + 5
    p.rect(0, y0, w - 1, y0 + 1, "=", main=True)
    p.gates = [("west_gate", (0, y0 + 1)), ("east_gate", (w - 1, y0))]
    lw = max(2, px - 6 + rng.randint(-1, 0))
    le = min(w - 3, px + PLAZA_W + 5 + rng.randint(0, 1))
    for x in (lw, le):
        p.rect(x, max(1, py - 6), x, min(h - 2, y0 + 10), ",")
    return p


def layout_abadia(rng, w, h):
    """Abbey (abadia): the plaza is the open court before the abbey church (the town hall north of it is the chapter
    house); a precinct lane (=) runs round the plaza at a short distance, the abbey's buildings and gardens fill the
    ring between them; the road comes in from the west gate to the plaza and a dirt lane leaves by the east gate;
    outside the precinct, orchards (trees) and fields."""
    p = Plan(w, h)
    px, py = _plaza_centre(p, rng, w // 2, h // 2)
    y0 = py + 5
    g = 5 + rng.randint(0, 1)
    c0, r0 = max(2, px - g), max(2, py - g - 1)
    c1, r1 = min(w - 3, px + PLAZA_W - 1 + g), min(h - 3, py + PLAZA_H - 1 + g)
    p.rect(0, y0, px - 1, y0 + 1, "=", main=True)  # the road from the west gate to the plaza
    for c in range(c0, c1 + 1):
        for r in (r0, r1):
            if p.at(c, r) == ".":
                p.put(c, r, "=")
    for r in range(r0, r1 + 1):
        for c in (c0, c1):
            if p.at(c, r) == ".":
                p.put(c, r, "=")
    p.rect(c1 + 1, y0, w - 1, y0, ",")  # the lane out by the east gate
    p.rect(px + PLAZA_W, y0, c1 - 1, y0, ",")  # and from the plaza to the precinct lane
    p.gates = [("west_gate", (0, y0 + 1)), ("east_gate", (w - 1, y0))]
    return p


LAYOUTS = {"calle": layout_calle, "plaza": layout_plaza, "cruce": layout_cruce, "rio": layout_rio,
           "aldea": layout_aldea, "abadia": layout_abadia}


# --- the town --------------------------------------------------------------------------------------------------

def _required(cat, start_ids):
    """The sites the starts ask for: {site: (type, set of the starts that build it)} (player, rival and competitors'
    buildings)."""
    out = {}

    def add(site, typ, st):
        out.setdefault(site, (typ, set()))[1].add(st)

    for sid in start_ids:
        s = citylib.load_json(os.path.join(citylib.DATA, "starts", sid + ".json"))
        add(s["building"]["site"], s["building"]["type"], sid)
        rv = s.get("rival", {}).get("building")
        if rv:
            add(rv["site"], rv["type"], sid)
        for cp in s.get("competitors", []):
            add(cp["building"]["site"], cp["building"]["type"], sid)
    return out


def _flush(plot, foot, d):
    """A footprint inside a plot rect, flush with the plot's street side d (its door on the same street)."""
    c, r, w, h = plot
    fw, fh = foot
    if d == (0, 1):
        return (c, r + h - fh, fw, fh)
    if d == (1, 0):
        return (c + w - fw, r, fw, fh)
    return (c, r, fw, fh)


def _tiles(rect):
    c, r, w, h = rect
    return [(c + dc, r + dr) for dr in range(h) for dc in range(w)]


def _ring(rect):
    c, r, w, h = rect
    out = []
    for dc in range(-1, w + 1):
        out += [(c + dc, r - 1), (c + dc, r + h)]
    for dr in range(h):
        out += [(c - 1, r + dr), (c + w, r + dr)]
    return out


def _candidates(p, taken, along, depth, roads):
    """Every free parcel (along x depth) whose whole front line is road and whose ring (but the front) has no road
    and no other parcel: [(rect, d, front tiles)], in reading order."""
    out = []
    for r in range(p.h):
        for c in range(p.w):
            for d in DIRS:
                if True:
                    if (c, r) not in roads:
                        continue
                    # the road line in front: along the road from (c, r)
                    step = (1, 0) if d[1] != 0 else (0, 1)
                    front = [(c + step[0] * i, r + step[1] * i) for i in range(along)]
                    if not all(t in roads for t in front):
                        continue
                    first = (front[0][0] - d[0], front[0][1] - d[1])
                    rect = _parcel_rect_from_first(first, d, along, depth)
                    tiles = _tiles(rect)
                    if not all(p.inside(*t) and 1 <= t[0] < p.w - 1 and 1 <= t[1] < p.h - 1 for t in tiles):
                        continue
                    if not all(p.at(*t) == "." and t not in taken and t not in p.reserved for t in tiles):
                        continue
                    fl = set(front)
                    ok = True
                    for t in _ring(rect):
                        # the front line and its two ends (the road goes on past the parcel) may be road
                        on_front = (t[1] == front[0][1]) if d[1] != 0 else (t[0] == front[0][0])
                        if t in fl or (on_front and t in roads):
                            continue
                        if t in taken or (p.inside(*t) and p.at(*t) not in (".", "T")):
                            # a corner of the ring touching the same road is fine (a parcel at a crossing is not)
                            ok = False
                            break
                    if ok:
                        out.append((rect, d, front))
    return out


def _parcel_rect_from_first(first, d, along, depth):
    """The parcel rect from its first tile next to the road (the one behind front[0])."""
    c, r = first
    if d == (0, 1):
        return (c, r - depth + 1, along, depth)
    if d == (0, -1):
        return (c, r, along, depth)
    if d == (1, 0):
        return (c - depth + 1, r, depth, along)
    return (c, r, depth, along)


def _door(rect, d):
    """The middle of the side d of a rect: the door of a building whose scene has no Door marker for that side."""
    c, r, w, h = rect
    if d == (0, 1):
        return (c + w // 2, r + h)
    if d == (0, -1):
        return (c + w // 2, r - 1)
    if d == (1, 0):
        return (c + w, r + h // 2)
    return (c - 1, r + h // 2)


def site_door(cat, typ, rect, d):
    """(door tile, drawn): the door of a building of type `typ` on `rect` with its street on side d, where its
    scene draws it (the Door marker of the look WorldView will draw, data/building_sprites.json, as drawn, mirrored or
    seen from behind); drawn = False if no look draws a door on that side (then the middle of the side)."""
    look = typ
    looks = cat.view.get("building_variants", {}).get(typ)
    if isinstance(looks, list) and looks:
        look = looks[citylib.gd_tile_hash(rect[0], rect[1]) % len(looks)]
    got = citylib.looks_for(cat.sprites, "buildings", look, citylib.SIDE_OF[d])
    if not got:
        return _door(rect, d), False
    scene, flip = got[0]
    _, tile = citylib.drawn_door(cat.sprites["buildings/" + scene], flip, (rect[2], rect[3]))
    return (rect[0] + tile[0], rect[1] + tile[1]), True


def build(map_id, layout, seed, w=40, h=40, start_ids=None, cat=None, households=None, profile=None):
    """profile: overrides of reglas.json generator (fields, town_reach, max_filler, tree_density) for this town;
    households: how many households live in it (default: as many as population_from has)."""
    cat = cat or citylib.Catalog()
    rl = citylib.rules()
    gen = dict(rl.get("generator", {}))
    gen.update(profile or {})
    rng = random.Random(f"{layout}:{seed}:{w}x{h}")
    p = LAYOUTS[layout](rng, w, h)
    px, py = p.plaza
    # 2. the plaza, its market and the buildings round it
    p.rect(px, py, px + PLAZA_W - 1, py + PLAZA_H - 1, "P")
    stalls = {}
    for sid, (t, s) in TEMPLATE["stalls"].items():
        p.put(px + t[0], py + t[1], "S")
        stalls[sid] = {"tile": [px + t[0], py + t[1]], "service": [px + s[0], py + s[1]]}
    bt, bs = TEMPLATE["board"]
    p.put(px + bt[0], py + bt[1], "N")
    board = {"tile": [px + bt[0], py + bt[1]], "service": [px + bs[0], py + bs[1]]}
    p.put(px + TEMPLATE["well"][0], py + TEMPLATE["well"][1], "#")
    sites = {}
    # the town hall north of the plaza (door on its visible +row face, onto the grass row before the plaza)
    th_o = (px + 1, py - 5)
    p.rect(th_o[0], th_o[1], th_o[0] + 5, th_o[1] + 3, "#")
    (sc, sr), _ = site_door(cat, "town_hall", (th_o[0], th_o[1], 6, 4), (0, 1))
    town_hall = {"origin": list(th_o), "footprint": [6, 4], "tile": [sc, sr - 1], "service": [sc, sr]}
    # the armory west of the plaza, its door (+col, visible) on the grass column by the plaza
    ar_o = (px - 4, py + 8)
    p.rect(ar_o[0], ar_o[1], ar_o[0] + 2, ar_o[1] + 3, "#")
    a_door, _ = site_door(cat, "armory", (ar_o[0], ar_o[1], 3, 4), (1, 0))
    sites["armory"] = {"type": "armory", "origin": list(ar_o), "door": list(a_door), "owner": ""}
    # keep a grass ring round the plaza, the town hall and the armory (no parcels glued to them)
    for (c0, r0, ww, hh) in ((px, py, PLAZA_W, PLAZA_H), (th_o[0], th_o[1], 6, 5), (ar_o[0], ar_o[1], 4, 4)):
        for c in range(c0 - 1, c0 + ww + 1):
            for r in range(r0 - 1, r0 + hh + 1):
                p.reserved.add((c, r))
    # 3-4. parcels along the streets, buildings by priority
    roads = {(c, r) for r in range(h) for c in range(w) if p.at(c, r) in ("=", ",", "b")}
    taken = set()
    pc = (px + PLAZA_W / 2.0, py + PLAZA_H / 2.0)

    def dist(rect):
        c, r, ww, hh = rect
        return max(abs(c + ww / 2.0 - pc[0]), abs(r + hh / 2.0 - pc[1]))

    def place(foot, prefer_main, prefer_visible=True, typ=""):
        fw, fh = foot
        best = None
        for d in DIRS:
            along, depth = (fw, fh) if d[1] != 0 else (fh, fw)
            for rect, dd, front in _candidates(p, taken, along, depth, roads):
                if dd != d:
                    continue
                main = all(t in p.main for t in front)
                # the camera sees the door and the scene draws it there (its Door marker, mirrored if it may be)
                vis = d in VISIBLE and site_door(cat, typ, rect, d)[1]
                # a door on a face the camera sees and that its sprite draws comes first; then the street class
                key = (0 if (vis or not prefer_visible) else 1, 0 if main == prefer_main else 1, round(dist(rect), 1),
                       rect[1], rect[0])
                if best is None or key < best[0]:
                    best = (key, rect, d)
        if best is None:
            return None
        _, rect, d = best
        for t in _tiles(rect):
            taken.add(t)
            p.put(t[0], t[1], "#")
        return rect, d

    req = _required(cat, start_ids or ["artisan_blacksmith", "artisan_carpenter", "artisan_mason", "artisan_tailor"])
    order = sorted(req.items(), key=lambda kv: (0 if kv[0] == "player_forge" else 1, kv[0]))
    plots = []  # [rect, street side, set of the starts that build something on it]
    for sid, (typ, used_by) in order:
        foot = cat.footprints[typ]
        # a site no start builds together with what a plot already has goes on that plot (H12: the rival of the
        # player's own trade on the player forge's plot), flush with its street, if it fits and its scene draws its
        # door towards that street
        host = next((pl for pl in plots if not (pl[2] & used_by) and foot[0] <= pl[0][2] and foot[1] <= pl[0][3]
                     and site_door(cat, typ, _flush(pl[0], foot, pl[1]), pl[1])[1]), None)
        if host is not None:
            rect = _flush(host[0], foot, host[1])
            d = host[1]
            host[2] |= used_by
        else:
            got = place(foot, prefer_main=True, typ=typ)
            if got is None:
                raise SystemExit(f"generar: no cabe {sid} ({typ}) en el trazado {layout}")
            rect, d = got
            plots.append([rect, d, set(used_by)])
        sites[sid] = {"type": typ, "origin": [rect[0], rect[1]], "door": list(site_door(cat, typ, rect, d)[0])}
    pop = citylib.load_json(os.path.join(citylib.DATA, "maps", gen.get("population_from", "town_e") + ".json"))
    households = population_of(pop.get("population", []), households)
    n_houses = len(households) if profile and "households" in profile else max(len(households),
                                                                                int(gen.get("houses", 8)))
    homes = []
    for i in range(n_houses):
        got = place(cat.footprints["house"], prefer_main=False, typ="house")
        if got is None:
            raise SystemExit(f"generar: solo caben {i} casas de vecinos de {n_houses} en {layout}")
        rect, d = got
        sid = f"house_{i + 1:02d}"
        sites[sid] = {"type": "house", "origin": [rect[0], rect[1]], "door": list(site_door(cat, "house", rect, d)[0])}
        homes.append(sid)
    reach = int(gen.get("town_reach", 16))
    # 5. fields outside the town, a pond if there is no river, trees
    fields = _fields(p, rng, taken, roads, pc, reach, int(gen.get("fields", 4)))
    # the rest of the frontage: filler blocks (house lots and yards), as far as the town reaches
    fill = 0
    while fill < int(gen.get("max_filler", 40)):
        best = None
        for along, depth in ((4, 4), (3, 3)):
            for rect, d, front in _candidates(p, taken, along, depth, roads):
                if dist(rect) > reach:
                    continue
                key = (round(dist(rect), 1), -along, rect[1], rect[0], DIRS.index(d))
                if best is None or key < best[0]:
                    best = (key, rect)
        if best is None:
            break
        for t in _tiles(best[1]):
            taken.add(t)
            p.put(t[0], t[1], "#")
        fill += 1
    water = any(p.at(c, r) == "w" for r in range(h) for c in range(w))
    if not water:
        _pond(p, rng, taken, roads, pc)
    _trees(p, rng, taken, roads, pc, reach, float(gen.get("tree_density", 0.08)))
    _close_pockets(p, cat)
    # 6. the map in the format of data/maps
    spawns = {k: [px + v[0], py + v[1]] for k, v in TEMPLATE["spawns"].items()}
    for name, t in p.gates:
        spawns[name] = list(t)
    social = [{"id": s["id"], "kind": s["kind"], "slots": [[px + a, py + b] for a, b in s["slots"]]}
              for s in TEMPLATE["social_points"]]
    wps = _workplaces(p, sites, town_hall, fields, px, py)
    population = []
    for i, hh in enumerate(households):
        e = json.loads(json.dumps(hh))
        e["home"] = homes[i]
        population.append(e)
    rows = ["".join(r) for r in p.g]
    data = {"id": map_id, "name_key": f"map.{map_id}", "size": [w, h], "rows": rows, "spawns": spawns,
            "stalls": stalls, "board": board, "town_hall": town_hall,
            "buildings": {k: sites[k] for k in sorted(sites)}, "social_points": social, "workplaces": wps,
            "population": population,
            "generated": {"layout": layout, "seed": seed, "size": [w, h], "tool": "tools/city/ciudad.py generar",
                          "starts": start_ids or ["artisan_blacksmith", "artisan_carpenter", "artisan_mason",
                                                  "artisan_tailor"]}}
    if profile:
        data["generated"]["profile"] = {k: profile[k] for k in sorted(profile)}
    m = citylib.Map(data, cat)
    data["decor"] = citylib.dress(m, rl)
    citylib.add_life(data, cat)  # 04f 4.24: meeting points and patrols, after the decor (never on it)
    return data


def population_of(base, n):
    """The households of a generated town: the first n of `base` (population_from's, copied as they are); past its
    end, `base` again in its order with only what weighs on the balance (rank, stats, the household's gold): the cast
    (sim/meta/cast.gd, docs/contratos/poblacion.md) gives them name, sex, age and look, in the fixed cast too."""
    if n is None:
        return [json.loads(json.dumps(hh)) for hh in base]
    out = []
    for i in range(n):
        hh = base[i % len(base)]
        if i < len(base):
            out.append(json.loads(json.dumps(hh)))
            continue
        e = {"gold": hh.get("gold", 0),
             "members": [{"rank": m["rank"], "stats": json.loads(json.dumps(m["stats"]))} for m in hh["members"]]}
        out.append(e)
    return out


def fill_members(households, per_house):
    """Every household up to per_house members (data/life/life.json population.per_house, 04f 4.24.3): past the ones
    it has, the members of all the households in their order again, with only rank and stats (the cast gives name,
    sex, age and look, in the fixed cast too: docs/contratos/poblacion.md «Varias ciudades»). In place."""
    pool = [m for hh in households for m in hh.get("members", [])]
    if not pool or not per_house:
        return households
    k = 0
    for hh in households:
        members = hh.setdefault("members", [])
        while len(members) < per_house:
            m = pool[k % len(pool)]
            members.append({"rank": m["rank"], "stats": json.loads(json.dumps(m["stats"]))})
            k += 1
    return households


def _fields(p, rng, taken, roads, pc, reach, n):
    """Up to n fields (rects of f) outside the town, each touching a road (so its workers get there): first far
    from the plaza and three tiles from any building, then closer if the map is small."""
    out = []
    for dmin, gap in ((reach - 6, 3), (reach - 9, 2), (0, 1)):
        _fields_pass(p, rng, taken, roads, pc, dmin, gap, n, out)
        if len(out) >= min(n, 2):
            break
    return out


def _fields_pass(p, rng, taken, roads, pc, dmin, gap, n, out):
    sizes = [(6, 4), (5, 4), (4, 5), (4, 4), (5, 3)]
    tries = []
    for r in range(1, p.h - 1):
        for c in range(1, p.w - 1):
            for (fw, fh) in sizes:
                rect = (c, r, fw, fh)
                cx, cy = c + fw / 2.0, r + fh / 2.0
                d = max(abs(cx - pc[0]), abs(cy - pc[1]))
                if d < dmin:
                    continue
                tries.append((round(-fw * fh + d * 0.3 + rng.random(), 3), rect))
    tries.sort()
    for _, rect in tries:
        if len(out) >= n:
            break
        tiles = _tiles(rect)
        if not all(1 <= t[0] < p.w - 1 and 1 <= t[1] < p.h - 1 and p.at(*t) == "." and t not in taken
                   and t not in p.reserved for t in tiles):
            continue
        ring = _ring(rect)
        if any(t in taken or p.at(*t) in ("f", "#", "S", "N", "P") for t in ring):
            continue
        near = [(t[0] + dc, t[1] + dr) for t in tiles for dc in (-gap, 0, gap) for dr in (-gap, 0, gap)]
        if any(p.at(*u) in ("#", "P", "S", "N") for u in near):
            continue
        if not any(t in roads for t in ring):
            continue
        for t in tiles:
            p.put(t[0], t[1], "f")
            taken.add(t)
        out.append(rect)


def _pond(p, rng, taken, roads, pc):
    best = None
    for r in range(2, p.h - 4):
        for c in range(2, p.w - 4):
            tiles = [(c + i, r + j) for j in range(2) for i in range(3)]
            ring = _ring((c, r, 3, 2))
            if not all(p.at(*t) == "." and t not in taken for t in tiles):
                continue
            if any(p.at(*t) not in (".",) or t in taken for t in ring):
                continue
            ring2 = _ring((c - 1, r - 1, 5, 4))
            near_road = any(t in roads for t in ring2)
            if not near_road and not any(t in roads for t in _ring((c - 3, r - 3, 9, 8))):
                continue
            d = abs(c - pc[0]) + abs(r - pc[1])
            key = (0 if near_road else 1, -d, r, c)
            if best is None or key < best[0]:
                best = (key, tiles)
    if best:
        for t in best[1]:
            p.put(t[0], t[1], "w")
            taken.add(t)


def _trees(p, rng, taken, roads, pc, reach, density):
    """Trees on the grass away from roads and buildings (two tiles), denser outside the town."""
    for r in range(p.h):
        for c in range(p.w):
            if p.at(c, r) != "." or (c, r) in taken or (c, r) in p.reserved:
                continue
            near = False
            for dr in range(-2, 3):
                for dc in range(-2, 3):
                    t = (c + dc, r + dr)
                    if p.inside(*t) and (p.at(*t) not in (".", "T") or t in roads):
                        near = True
            if near:
                continue
            d = max(abs(c - pc[0]), abs(r - pc[1]))
            k = density * (3.0 if d > reach else 0.6)
            if citylib.tile_hash(c, r, 11) % 1000 < k * 1000:
                p.put(c, r, "T")


def _close_pockets(p, cat):
    """Grass that cannot be reached from the plaza (a pocket shut in by trees, buildings or water) becomes trees:
    every walkable tile of a generated town is reachable (the wanderer bot walks to any of them)."""
    walk = {ch for ch, k in cat.kind_of.items() if cat.walk.get(k) is not None}
    start = p.plaza
    seen = {start}
    todo = [start]
    while todo:
        c, r = todo.pop()
        for d in DIRS:
            t = (c + d[0], r + d[1])
            if t not in seen and p.inside(*t) and p.at(*t) in walk:
                seen.add(t)
                todo.append(t)
    for r in range(p.h):
        for c in range(p.w):
            if p.at(c, r) in walk and (c, r) not in seen:
                if p.at(c, r) != ".":
                    raise SystemExit(f"generar: la casilla {(c, r)} ({p.at(c, r)}) queda aislada de la plaza")
                p.put(c, r, "T")


def _workplaces(p, sites, th, fields, px, py):
    wp = {}
    for wid, kind, rel, stall in TEMPLATE["workplaces_plaza"]:
        e = {"id": wid, "kind": kind, "tile": [px + rel[0], py + rel[1]]}
        if stall:
            e["stall"] = stall
        wp[wid] = e
    gw = next((t for n, t in p.gates if n == "west_gate"), p.gates[0][1])
    ge = next((t for n, t in p.gates if n == "east_gate"), p.gates[-1][1])
    wp["gate_west"] = {"id": "gate_west", "kind": "tile", "tile": [gw[0] + 1, gw[1]]}
    wp["gate_east"] = {"id": "gate_east", "kind": "tile", "tile": [ge[0] - 1, ge[1]]}
    for i, name in enumerate(["field_a", "field_b", "field_c", "field_d"]):
        f = fields[i % len(fields)] if fields else None
        if f is None:
            raise SystemExit("generar: ningún campo cabe en el trazado")
        k = i // max(1, len(fields))
        wp[name] = {"id": name, "kind": "tile", "tile": [f[0] + 1 + k, f[1] + 1]}
    water = [(c, r) for r in range(p.h) for c in range(p.w) if p.at(c, r) == "w"]
    bank = None
    for (c, r) in sorted(water, key=lambda t: (abs(t[1] - (py + 2)), t[1], t[0])):
        for d in DIRS:
            t = (c + d[0], r + d[1])
            if p.at(*t) in (".", ",") and bank is None:
                bank = t
        if bank:
            break
    if bank is None:
        raise SystemExit("generar: sin agua para el oficio river_bank (ni río ni estanque)")
    wp["river_bank"] = {"id": "river_bank", "kind": "tile", "tile": list(bank)}
    a = sites["armory"]
    wp["armory"] = {"id": "armory", "kind": "shop", "tile": list(a["door"]), "building": "armory", "stall": "armory"}
    s = th["service"]
    wp["townhall_a"] = {"id": "townhall_a", "kind": "tile", "tile": [s[0] - 2, s[1]]}
    wp["townhall_b"] = {"id": "townhall_b", "kind": "tile", "tile": [s[0] + 2, s[1]]}
    # the church of town_e has no building here: its two trades stand by the town hall's corners
    o = th["origin"]
    wp["church_a"] = {"id": "church_a", "kind": "tile", "tile": [o[0] - 1, o[1] + 1]}
    wp["church_b"] = {"id": "church_b", "kind": "tile", "tile": [o[0] + 6, o[1] + 1]}
    return [wp[k] for k in WORKPLACE_ORDER]


def main(argv):
    ap = argparse.ArgumentParser(prog="ciudad.py generar")
    ap.add_argument("--id", required=True)
    ap.add_argument("--layout", required=True, choices=sorted(LAYOUTS))
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--size", default="40x40")
    ap.add_argument("--start", action="append", default=[])
    ap.add_argument("--out", default="")
    ap.add_argument("--households", type=int, default=None, help="households (one house each); default: town_e's")
    ap.add_argument("--fields", type=int, default=None)
    ap.add_argument("--reach", type=int, default=None, help="how far from the plaza filler blocks go (tiles)")
    ap.add_argument("--filler", type=int, default=None, help="most filler blocks")
    ap.add_argument("--trees", type=float, default=None, help="tree density")
    a = ap.parse_args(argv)
    w, h = (int(x) for x in a.size.lower().split("x"))
    profile = {k: v for k, v in (("households", a.households), ("fields", a.fields), ("town_reach", a.reach),
                                 ("max_filler", a.filler), ("tree_density", a.trees)) if v is not None}
    cat = citylib.Catalog()
    data = build(a.id, a.layout, a.seed, w, h, a.start or None, cat, a.households, profile or None)
    if a.out:
        os.makedirs(a.out, exist_ok=True)
        path = os.path.join(a.out, a.id + ".json")
        with open(path, "w", encoding="utf-8") as f:
            f.write(citylib.dumps_map(data))
    else:
        path = citylib.save_map(data)
    m = citylib.Map(data, cat)
    rep = citylib.validate(m, strict=True)
    print(f"generar {a.id} ({a.layout}, semilla {a.seed}, {w}x{h}) -> {os.path.relpath(path, citylib.ROOT)}: "
          f"{len(rep.errors)} errores, {len(rep.warnings)} avisos")
    for e in rep.errors:
        print("  ERROR", e)
    for x in rep.warnings:
        print("  aviso", x)
    for n in rep.info:
        print("  ·", n)
    import preview
    print("  vista:", preview.render_data(data, cat, os.path.join(a.out or os.path.join(citylib.ROOT, "reports",
                                                                                         "ciudad"), a.id + ".png")))
    return 1 if rep.errors else 0
