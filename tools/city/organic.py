"""Organic towns (docs/protocolos/generar-ciudad.md §Ciudades orgánicas). Offline, deterministic (same plan -> same map).

  python3 tools/city/ciudad.py generar --plan region_capital      one town of tools/city/ciudades.json
  python3 tools/city/ciudad.py region [id...]                       every town of ciudades.json (or the given ones)

The plan of a town is data (tools/city/ciudades.json): the terrain (river, stream, pond, the sierra), the plaza, the
main roads from the gates, the walls, the districts (each with its own street mesh and density), the port and the
landmarks. The steps, in order:

 1 terrain: the sierra (R), the river or the stream (w) as a curve with its width, a pond.
 2 the plaza (the 10x12 market of town_e that the bots were tuned on) grown into an irregular square, the town hall
   north of it and the armory west of it, as in generator.py.
 3 the main roads (=): smooth curves from the gates to the plaza, 2-3 tiles wide; stone bridges (b) where they cross
   water; dirt lanes (,) with fords (v) where they cross a stream.
 4 the walls (M): a wobbly ring round the old town, open where the main roads pass (the gates, with their towers) and
   ending on the river bank; towers every few tiles.
 5 the port: the quay (=) along the bank, the piers (m, walkable over the water), and the boats (decor on the water).
 6 the landmarks (H): blocks with a footprint that the sim never reads (cathedral, exchange, warehouses, crane, mine,
   quarry, mill...), near where the plan says, fronting a road; a parvis (P) before the church if asked.
 7 the streets of each district, grown from the ones there are: branches off a street every few tiles at a slant,
   bending a little as they go, stopping at another street (a crossing), the district's edge, water, a wall or a
   landmark, never closer than `clear` to a street they run beside; then the alleys off those streets.
 8 the sim's sites (workshops, houses) by the rules of generator.py, then the filler: house lots of mixed sizes along
   every street front, by the district's density (fill, gaps, lot sizes, back yards, patios).
 9 fields (irregular cells outside the town, with dirt lanes round them), woods, gardens; pockets that cannot be
   reached become trees, loose street bits become dirt.
10 the map in the format of data/maps, with "landmarks", "boats" and "generated" (the plan, the river, the lots), the
   decor by rules (citylib.dress) and the strict validation (citylib.validate).
"""
import json
import math
import os
import random

import citylib
import generator as gen
from citylib import DIRS, VISIBLE

PLANS_PATH = os.path.join(citylib.ROOT, "tools", "city", "ciudades.json")
ROADS = ("=", ",", "b", "P", "m", "v")  # what counts as a way in front of a lot or a door
STREETS = ("=", "b", "P")  # the street network (one piece)
WAYS = ("=", ",", "b")  # streets and lanes for the lots' fronts
LAND = (".",)


def load_plans():
    return citylib.load_json(PLANS_PATH)


# --- small geometry ------------------------------------------------------------------------------------------------

class Noise:
    """Value noise in [0, 1) from tile_hash: smooth, the same for the same salt."""

    def __init__(self, salt):
        self.salt = salt

    def _v(self, i, j):
        return citylib.tile_hash(i, j, self.salt) / 1000003.0

    def at(self, x, y, scale=6.0):
        x, y = x / scale, y / scale
        i, j = math.floor(x), math.floor(y)
        fx, fy = x - i, y - j
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a, b = self._v(i, j), self._v(i + 1, j)
        c, d = self._v(i, j + 1), self._v(i + 1, j + 1)
        return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def spline(pts, step=0.25):
    """Catmull-Rom through the control points, sampled every ~step tiles."""
    if len(pts) < 2:
        return [tuple(map(float, p)) for p in pts]
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        seg = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        n = max(2, int(seg / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    out.append(tuple(map(float, pts[-1])))
    return out


def jitter(rng, pts, amount):
    """Moves the inner control points a little (the same plan with another seed bends another way)."""
    out = [tuple(pts[0])]
    for p in pts[1:-1]:
        out.append((p[0] + rng.uniform(-amount, amount), p[1] + rng.uniform(-amount, amount)))
    out.append(tuple(pts[-1]))
    return out


def line4(a, b):
    """4-connected tiles from tile a to tile b (a diagonal step gets the tile beside it)."""
    (c0, r0), (c1, r1) = a, b
    out = [(c0, r0)]
    dc, dr = c1 - c0, r1 - r0
    n = max(abs(dc), abs(dr))
    c, r = c0, r0
    for k in range(1, n + 1):
        nc, nr = c0 + round(dc * k / n), r0 + round(dr * k / n)
        if nc != c and nr != r:
            out.append((nc, r))
        out.append((nc, nr))
        c, r = nc, nr
    return out


def path4(samples):
    """The 4-connected tiles a sampled curve goes through."""
    tiles = []
    last = None
    for x, y in samples:
        t = (int(round(x)), int(round(y)))
        if last is None:
            tiles.append(t)
        elif t != last:
            for u in line4(last, t)[1:]:
                tiles.append(u)
        last = t
    return tiles


def dist_to_polyline(x, y, pts):
    best = 1e9
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        vx, vy = bx - ax, by - ay
        L = vx * vx + vy * vy
        t = 0.0 if L == 0 else max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / L))
        px, py = ax + t * vx, ay + t * vy
        best = min(best, math.hypot(x - px, y - py))
    return best


# --- the town ------------------------------------------------------------------------------------------------------

class Town:
    def __init__(self, map_id, plan, cat):
        self.id = map_id
        self.plan = plan
        self.cat = cat
        self.w, self.h = plan["size"]
        self.seed = int(plan.get("seed", 1))
        self.rng = random.Random(f"organic:{self.seed}:{self.w}x{self.h}")
        self.noise = Noise(self.seed * 7 + 3)
        self.p = gen.Plan(self.w, self.h)
        self.taken = set()  # tiles of sites, lots and landmarks
        self.keep = set()  # tiles that must stay open (doors, the tiles before a house's door)
        self.landmarks = []  # map "landmarks"
        self.boats = []  # map "boats"
        self.lots = []  # (c, r, w, h, district) house lots of the filler
        self.district_of = {}  # tile -> district index
        self.wall_inside = set()
        self.rivers = []  # [{"path": [[x, y]...], "width": w}]
        self.bridges_ok = set()  # water tiles a road may turn into a bridge
        self.log = []
        self.lot_tiles = set()  # tiles of the filler lots (houses and their yards)
        self.prefer = set()  # tiles where the drawing has houses (skeleton plans): the sites go there first
        self.stats = {}  # why the branches of the street mesh stopped (debug)
        self.lines = []  # (rank, samples) of every street drawn: main roads, quay, secondary streets, alleys
        self.quay = set()
        self.piers = []
        self.wall_ring = []

    # helpers
    def at(self, t):
        return self.p.at(*t)

    def put(self, t, ch):
        if self.p.inside(*t):
            self.p.g[t[1]][t[0]] = ch

    def inside(self, t, margin=0):
        return margin <= t[0] < self.w - margin and margin <= t[1] < self.h - margin

    def tiles(self):
        for r in range(self.h):
            for c in range(self.w):
                yield (c, r)

    def near_road(self, t, chars=ROADS):
        return any(self.at((t[0] + d[0], t[1] + d[1])) in chars for d in DIRS)

    # 1. terrain -------------------------------------------------------------------------------------------------
    def terrain(self):
        rock = self.plan.get("rock")
        if rock:
            depth, wob = rock["depth"], rock.get("wobble", 3)
            spurs = rock.get("spurs", [])
            for t in self.tiles():
                c, r = t
                d = depth + (self.noise.at(c, 0, 5) - 0.5) * 2 * wob + (self.noise.at(c, 40, 2.5) - 0.5) * 2
                for s in spurs:  # a ridge coming down the slope
                    d += s["depth"] * max(0.0, 1 - abs(c - s["at"]) / s["half"])
                if rock.get("edge", "north") == "north" and r < d:
                    self.put(t, "R")
        for rv in self.plan.get("rivers", []):
            pts = spline(jitter(self.rng, rv["path"], rv.get("jitter", 1.5)), 0.2)
            wdt = float(rv["width"])
            wob = float(rv.get("wobble", 0.6))
            for t in self.tiles():
                if self.at(t) == "R" and not rv.get("through_rock", True):
                    continue
                dd = dist_to_polyline(t[0], t[1], pts[::3] + [pts[-1]])
                half = wdt / 2.0 + (self.noise.at(t[0], t[1], 7) - 0.5) * 2 * wob
                if dd <= half:
                    self.put(t, "w")
            self.rivers.append({"path": [[round(x, 1), round(y, 1)] for x, y in pts[::12] + [pts[-1]]],
                                "width": wdt, "core": max(1.0, wdt / 2.0 - wob - 0.6)})
        pond = self.plan.get("pond")
        if pond:
            cx, cy = pond["at"]
            rx, ry = pond["size"][0] / 2.0, pond["size"][1] / 2.0
            for t in self.tiles():
                k = ((t[0] - cx) / rx) ** 2 + ((t[1] - cy) / ry) ** 2
                if k <= 1.0 + (self.noise.at(t[0], t[1], 2) - 0.5) * 0.6 and self.at(t) == ".":
                    self.put(t, "w")

    # 2. the plaza ------------------------------------------------------------------------------------------------
    def plaza(self):
        cfg = self.plan["plaza"]
        cx, cy = cfg["centre"]
        px = max(6, min(self.w - gen.PLAZA_W - 6, cx - gen.PLAZA_W // 2))
        py = max(7, min(self.h - gen.PLAZA_H - 6, cy - gen.PLAZA_H // 2))
        self.p.plaza = (px, py)
        self.px, self.py = px, py
        self.th_o = (px + 1, py - 5)
        self.ar_o = (px - 4, py + 8)
        th_zone = {(c, r) for c in range(self.th_o[0] - 1, self.th_o[0] + 7) for r in range(self.th_o[1] - 1, py)}
        ar_zone = {(c, r) for c in range(self.ar_o[0] - 1, self.ar_o[0] + 4) for r in range(self.ar_o[1] - 1,
                                                                                            self.ar_o[1] + 5)}
        # the irregular square: the market rect grown by a wobbly ellipse; its corners cut where the market leaves
        # them free
        b = float(cfg.get("bulge", 2.0))
        mx, my = px + (gen.PLAZA_W - 1) / 2.0, py + (gen.PLAZA_H - 1) / 2.0
        rx, ry = gen.PLAZA_W / 2.0 + b, gen.PLAZA_H / 2.0 + b * 0.7
        sq = set()
        for t in self.tiles():
            ang = math.atan2(t[1] - my, t[0] - mx)
            k = 0.78 + 0.5 * self.noise.at(math.cos(ang) * 3 + 50, math.sin(ang) * 3 + 50, 1.2)
            if ((t[0] - mx) / rx) ** 2 + ((t[1] - my) / ry) ** 2 <= k:
                sq.add(t)
        for r in range(py, py + gen.PLAZA_H):
            for c in range(px, px + gen.PLAZA_W):
                sq.add((c, r))
        for rel in cfg.get("cut", [[0, 0], [9, 11], [8, 11]]):
            sq.discard((px + rel[0], py + rel[1]))
        for t in sorted(sq):
            if t in th_zone or t in ar_zone or self.at(t) not in (".",):
                continue
            self.put(t, "P")
        self.square = {t for t in sq if self.at(t) == "P"}
        # the market (the template), the town hall and the armory
        p = self.p
        self.stalls = {}
        for sid, (t, s) in gen.TEMPLATE["stalls"].items():
            p.put(px + t[0], py + t[1], "S")
            self.stalls[sid] = {"tile": [px + t[0], py + t[1]], "service": [px + s[0], py + s[1]]}
        bt, bs = gen.TEMPLATE["board"]
        p.put(px + bt[0], py + bt[1], "N")
        self.board = {"tile": [px + bt[0], py + bt[1]], "service": [px + bs[0], py + bs[1]]}
        p.put(px + gen.TEMPLATE["well"][0], py + gen.TEMPLATE["well"][1], "#")
        for r in range(self.th_o[1], self.th_o[1] + 4):
            for c in range(self.th_o[0], self.th_o[0] + 6):
                self.put((c, r), "#")
        (sc, sr), _ = gen.site_door(self.cat, "town_hall", (self.th_o[0], self.th_o[1], 6, 4), (0, 1))
        self.town_hall = {"origin": list(self.th_o), "footprint": [6, 4], "tile": [sc, sr - 1], "service": [sc, sr]}
        for r in range(self.ar_o[1], self.ar_o[1] + 4):
            for c in range(self.ar_o[0], self.ar_o[0] + 3):
                self.put((c, r), "#")
        a_door, _ = gen.site_door(self.cat, "armory", (self.ar_o[0], self.ar_o[1], 3, 4), (1, 0))
        self.sites = {"armory": {"type": "armory", "origin": list(self.ar_o), "door": list(a_door), "owner": ""}}
        for (c0, r0, ww, hh) in ((px, py, gen.PLAZA_W, gen.PLAZA_H), (self.th_o[0], self.th_o[1], 6, 5),
                                 (self.ar_o[0], self.ar_o[1], 4, 4)):
            for c in range(c0 - 1, c0 + ww + 1):
                for r in range(r0 - 1, r0 + hh + 1):
                    p.reserved.add((c, r))
        for t in self.square:
            p.reserved.add(t)
        self.keep |= {tuple(a_door), (sc, sr)}
        self.protect = th_zone | ar_zone | {(px + c, py + r) for c in range(gen.PLAZA_W) for r in range(gen.PLAZA_H)}

    # 3. roads ----------------------------------------------------------------------------------------------------
    def stamp(self, samples, width, ch, main=False, bridge=True, over=None):
        half = width / 2.0 + 0.01
        out = set()
        for x, y in samples:
            for r in range(int(math.floor(y - half)), int(math.ceil(y + half)) + 1):
                for c in range(int(math.floor(x - half)), int(math.ceil(x + half)) + 1):
                    if math.hypot(c - x, r - y) <= half:
                        out.add((c, r))
        for t in path4(samples):  # never thinner than a 4-connected line
            out.add(t)
        for t in sorted(out):
            if not self.inside(t) or t in self.protect:
                continue
            cur = self.at(t)
            if over is not None and cur not in over:
                continue
            if cur == "w":
                if bridge:
                    self.put(t, "b" if ch != "," else "v")
                    if main:
                        self.p.main.add(t)
                continue
            if cur in ("P", "S", "N", "#", "b", "H"):
                continue
            if ch == "," and cur in ("=", "b", "m"):
                continue
            self.put(t, ch)
            if main:
                self.p.main.add(t)
        return out

    def roads(self):
        for rd in self.plan.get("roads", []):
            pts = jitter(self.rng, rd["path"], rd.get("jitter", 1.0))
            samples = spline(pts, 0.2)
            ch = rd.get("ch", "=")
            self.stamp(samples, rd.get("width", 2), ch, main=rd.get("main", ch == "="), bridge=rd.get("bridge", True))
            self.lines.append(("main", samples))
            g = rd.get("gate")
            if g:
                self.gate_at(g, rd["path"][0])

    def gate_at(self, name, first):
        """The gate spawn: the road tile on the map's edge nearest the road's first point (west_gate and east_gate
        also need the next tile inwards on the road: the gate trades stand there)."""
        x, y = first
        edge = []
        for t in self.tiles():
            if self.at(t) not in ("=", ","):
                continue
            c, r = t
            if name == "west_gate" and c == 0 and self.at((1, r)) in ("=", ","):
                edge.append(t)
            elif name == "east_gate" and c == self.w - 1 and self.at((c - 1, r)) in ("=", ","):
                edge.append(t)
            elif name == "north_gate" and r == 0:
                edge.append(t)
            elif name == "south_gate" and r == self.h - 1:
                edge.append(t)
        if not edge:
            raise SystemExit(f"organic: la carretera de {name} no llega al borde del mapa")
        best = min(edge, key=lambda t: (abs(t[0] - x) + abs(t[1] - y), t[1], t[0]))
        self.p.gates.append((name, best))

    # 4. walls ----------------------------------------------------------------------------------------------------
    def walls(self):
        cfg = self.plan.get("walls")
        if not cfg:
            return
        cx, cy = cfg["centre"]
        rx, ry = cfg["radius"]
        wob = cfg.get("wobble", 0.06)
        inside = set()
        for t in self.tiles():
            ang = math.atan2(t[1] - cy, t[0] - cx)
            k = 1.0 + (self.noise.at(math.cos(ang) * 4 + 9, math.sin(ang) * 4 + 9, 1.5) - 0.5) * 2 * wob
            if ((t[0] - cx) / rx) ** 2 + ((t[1] - cy) / ry) ** 2 <= k * k:
                inside.add(t)
        # what lies across the water from the plaza is outside
        land = {t for t in inside if self.at(t) not in ("w",)}
        st = tuple(cfg.get("from", cfg["centre"]))
        seen = {st}
        todo = [st]
        while todo:
            t = todo.pop()
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if u in land and u not in seen:
                    seen.add(u)
                    todo.append(u)
        self.wall_inside = seen
        ring = []
        for t in sorted(seen, key=lambda t: (t[1], t[0])):
            if any((t[0] + dc, t[1] + dr) not in seen and self.at((t[0] + dc, t[1] + dr)) != "w"
                   for dc in (-1, 0, 1) for dr in (-1, 0, 1)):
                ring.append(t)
        gates = []
        for t in ring:
            if t in self.protect or t in self.p.reserved:
                continue
            cur = self.at(t)
            if cur in ("=", ",", "b"):
                gates.append(t)
                continue
            if cur in (".", "T", "R"):
                self.put(t, "M")
        self.wall_ring = [t for t in ring if self.at(t) == "M"]
        # gate towers on both sides of each road through the wall, towers along the wall
        tw = cfg.get("tower", [2, 2])
        for g in self._groups(gates):
            ends = []
            for t in g:
                for d in DIRS:
                    u = (t[0] + d[0], t[1] + d[1])
                    if self.at(u) == "M":
                        ends.append(u)
            for e in sorted(set(ends)):
                self._tower(e, tw, "gate_tower", cfg)
        every = int(cfg.get("towers_every", 0))
        if every:
            order = self._ring_order(self.wall_ring)
            for i, t in enumerate(order):
                if i % every == every // 2:
                    self._tower(t, tw, "wall_tower", cfg)

    def _ring_order(self, ring):
        """The wall tiles in walking order round the ring (a greedy walk; good enough to space the towers)."""
        left = set(ring)
        out = []
        while left:
            t = min(left, key=lambda t: (t[1], t[0]))
            while t:
                out.append(t)
                left.discard(t)
                nxt = None
                for dc, dr in ((1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
                    u = (t[0] + dc, t[1] + dr)
                    if u in left:
                        nxt = u
                        break
                t = nxt
        return out

    def _tower(self, t, size, typ, cfg):
        tw, th = size
        for oc in range(-tw + 1, 1):
            for orr in range(-th + 1, 1):
                rect = (t[0] + oc, t[1] + orr, tw, th)
                tiles = gen._tiles(rect)
                if not all(self.inside(u, 1) and self.at(u) in ("M", ".") and u not in self.p.reserved
                           and u not in self.taken for u in tiles):
                    continue
                if not any(self.at(u) == "M" for u in tiles):
                    continue
                # a tower never closes a street: no road next to its grass tiles but the gate
                if any(self.at(u) == "." and sum(1 for d in DIRS if self.at((u[0] + d[0], u[1] + d[1])) in ROADS) > 1
                       for u in tiles):
                    continue
                self.add_landmark(typ, rect, cfg.get("tower_height", 72), cfg.get("tower_color", "#6e685e"), label=False)
                return True
        return False

    @staticmethod
    def _groups(tiles):
        return citylib.groups_of(set(tiles))

    # 5. the port -------------------------------------------------------------------------------------------------
    def port(self):
        cfg = self.plan.get("port")
        if not cfg:
            return
        x0, x1 = cfg["quay"]["cols"]
        side = cfg["quay"].get("bank", "north")
        down = (0, 1) if side == "north" else (0, -1)
        qw = int(cfg["quay"].get("width", 2))
        quay = set()
        for c in range(x0, x1 + 1):
            # the first water tile down the column from the town side
            rows = range(self.h) if side == "north" else range(self.h - 1, -1, -1)
            last_land = None
            for r in rows:
                if self.at((c, r)) == "w":
                    break
                last_land = (c, r)
            if last_land is None:
                continue
            for k in range(qw):
                t = (c, last_land[1] - down[1] * k)
                if self.inside(t) and self.at(t) in (".", "T", ",", "=") and t not in self.protect:
                    quay.add(t)
        for t in quay:
            if self.at(t) != "=":
                self.put(t, "=")
        self.quay = quay
        # piers into the water, perpendicular to the bank, leaving the channel free
        n, plen, pw, gap = cfg.get("piers", 4), cfg.get("pier_len", 3), cfg.get("pier_width", 1), cfg.get("spacing", 6)
        edge = sorted({(t[0], t[1]) for t in quay if self.at((t[0] + down[0], t[1] + down[1])) == "w"})
        piers = []
        cands = []
        for t in edge:
            if any(self.at((t[0] + dc, t[1] + dr)) == "b" for dc in range(-4, 5) for dr in range(-3, 4)):
                continue
            ok = True
            tiles = []
            for k in range(1, plen + 1):
                for j in range(pw):
                    u = (t[0] + j, t[1] + down[1] * k)
                    if self.at(u) != "w":
                        ok = False
                    tiles.append(u)
            beyond = [(t[0] + j, t[1] + down[1] * (plen + 2)) for j in range(pw)]
            if not ok or not all(self.at(u) == "w" for u in beyond):
                continue
            cands.append((abs(t[0] - (x0 + x1) / 2.0), t, tiles))
        mid = (x0 + x1) / 2.0
        # spread them along the quay: the middle first, then every `gap` columns
        for _, t, tiles in sorted(cands, key=lambda e: (e[0], e[1])):
            if len(piers) >= n:
                break
            if any(abs(t[0] - q[0][0]) < gap for q in piers):
                continue
            piers.append((t, tiles))
            for u in tiles:
                self.put(u, "m")
        self.piers = piers
        # boats moored beside the piers, rowboats out on the river
        bl, bw = cfg.get("boat", [4, 2])
        nb = int(cfg.get("boats", len(piers)))
        for t, tiles in sorted(piers, key=lambda e: abs(e[0][0] - mid)):
            if nb <= 0:
                break
            for sx in (1, -bl):
                c0 = tiles[0][0] + (pw if sx == 1 else 0) + (0 if sx == 1 else sx)
                rows = sorted({u[1] for u in tiles})
                r0 = rows[0] if down[1] > 0 else rows[-1] - bw + 1
                rect = (c0, r0 + (1 if down[1] > 0 else -1) * 0, bl, bw)
                if self._boat_fits(rect):
                    self.add_boat("ship", rect, cfg.get("boat_color", "#6b4a2a"))
                    nb -= 1
                    break
        rb = int(cfg.get("rowboats", 2))
        tries = sorted((t for t in self.tiles() if self.at(t) == "w"), key=lambda t: (citylib.tile_hash(*t, 21), t))
        for t in tries:
            if rb <= 0:
                break
            rect = (t[0], t[1], 2, 1)
            if self._boat_fits(rect, margin=2):
                self.add_boat("rowboat", rect, "#7a5a36")
                rb -= 1
        crane = cfg.get("crane")
        if crane and piers:
            t0 = sorted(piers, key=lambda e: abs(e[0][0] - mid))[0][0]
            for dc in (2, -2, 3, -3, 1, -1):
                u = (t0[0] + dc, t0[1])
                behind = (u[0], u[1] - down[1])
                if self.at(u) == "=" and self.at(behind) == "=" and self.at((u[0] + down[0], u[1] + down[1])) == "w" \
                        and not any(self.at((u[0] + e, u[1] + down[1])) == "m" for e in (-1, 0, 1)):
                    self.add_landmark("crane", (u[0], u[1], 1, 1), crane.get("height", 88), crane.get("color", "#7a5530"))
                    break

    def _boat_fits(self, rect, margin=0):
        c, r, w, h = rect
        for u in gen._tiles((c - margin, r - margin, w + 2 * margin, h + 2 * margin)):
            if not self.inside(u) or self.at(u) != "w":
                return False
        for b in self.boats:
            bc, br = b["origin"]
            bw, bh = b["size"]
            if not (c + w + 1 <= bc or bc + bw + 1 <= c or r + h + 1 <= br or br + bh + 1 <= r):
                return False
        # leave a channel: the tiles beyond the boat (away from the bank) stay water
        return True

    def add_boat(self, typ, rect, color):
        c, r, w, h = rect
        self.boats.append({"type": typ, "origin": [c, r], "size": [w, h], "color": color})

    # 6. landmarks ------------------------------------------------------------------------------------------------
    def add_landmark(self, typ, rect, height, color, label=True):
        c, r, w, h = rect
        for t in gen._tiles(rect):
            self.put(t, "H")
            self.taken.add(t)
        e = {"type": typ, "origin": [c, r], "size": [w, h], "height": height, "color": color}
        if label:
            e["label"] = "hito." + typ
        self.landmarks.append(e)
        return e

    def landmark_spots(self, lm):
        """Free rects for a landmark: (score, rect, front side) nearest its `near` point, fronting what it asks."""
        sizes = [tuple(lm["size"])]
        if lm.get("rotate", True) and lm["size"][0] != lm["size"][1]:
            sizes.append((lm["size"][1], lm["size"][0]))
        on = set(lm.get("on", ["."]))
        front = lm.get("front", "road")
        nx, ny = lm["near"]
        reach = lm.get("reach", 14)
        out = []
        for (w, h) in sizes:
            for r in range(max(1, int(ny - reach)), min(self.h - h - 1, int(ny + reach)) + 1):
                for c in range(max(1, int(nx - reach)), min(self.w - w - 1, int(nx + reach)) + 1):
                    rect = (c, r, w, h)
                    tiles = gen._tiles(rect)
                    if not all(self.at(t) in on and t not in self.p.reserved and t not in self.taken
                               and t not in self.keep for t in tiles):
                        continue
                    if lm.get("inside_wall") and not all(t in self.wall_inside for t in tiles):
                        continue
                    if lm.get("outside_wall") and any(t in self.wall_inside for t in tiles):
                        continue
                    if any(t in self.taken or self.at(t) in ("#", "S", "N") for t in gen._ring(rect)):
                        continue
                    best_side = None
                    for d in DIRS:
                        line = citylib.front_line(rect, d)
                        if front == "road":
                            k = sum(1 for t in line if self.at(t) in ROADS)
                        elif front == "water":
                            k = sum(1 for t in line if self.at(t) == "w")
                        elif front == "rock":
                            k = sum(1 for t in line if self.at(t) == "R")
                        else:
                            k = len(line)
                        need = max(1, int(len(line) * lm.get("front_share", 0.5)))
                        if k >= need and (best_side is None or k > best_side[0]):
                            best_side = (k, d)
                    if best_side is None:
                        continue
                    cx, cy = c + (w - 1) / 2.0, r + (h - 1) / 2.0
                    out.append((round(math.hypot(cx - nx, cy - ny), 2), rect, best_side[1]))
        out.sort()
        return out

    def place_landmarks(self, stage):
        for lm in self.plan.get("landmarks", []):
            if lm.get("stage", "early") != stage:
                continue
            for k in range(int(lm.get("count", 1))):
                spots = self.landmark_spots(lm)
                if not spots and self.plan.get("skeleton"):  # a drawn town is tighter: a little smaller
                    for f in (0.8, 0.65):
                        lm = dict(lm, size=[max(2, int(round(v * f))) for v in lm["size"]])
                        spots = self.landmark_spots(lm)
                        if spots:
                            break
                if not spots:
                    self.log.append(f"hito {lm['type']}: no cabe cerca de {lm['near']}")
                    break
                _, rect, d = spots[0]
                self.add_landmark(lm["type"], rect, lm.get("height", 48), lm.get("color", "#9a7a5a"),
                                  label=lm.get("label", True))
                for t in gen._ring(rect):
                    if self.at(t) == ".":
                        self.p.reserved.add(t)
                pv = lm.get("parvis")
                if pv:
                    self._parvis(rect, d, pv)

    def place_plots(self):
        """Fields placed where the plan says (the abbey's kitchen garden inside its walls): like a landmark, but their
        tiles are fields (f), walkable, fenced by the decor; they count as fields for the field trades."""
        self.plot_cells = []
        for pl in self.plan.get("plots", []):
            spots = self.landmark_spots(dict(pl, front=pl.get("front", "any")))
            if not spots:
                self.log.append(f"huerto: no cabe cerca de {pl['near']}")
                continue
            _, rect, _ = spots[0]
            tiles = gen._tiles(rect)
            for t in tiles:
                self.put(t, "f")
                self.taken.add(t)
            for t in gen._ring(rect):
                if self.at(t) == ".":
                    self.p.reserved.add(t)
            self.plot_cells.append(sorted(tiles, key=lambda t: (t[1], t[0])))

    def _parvis(self, rect, d, depth):
        c, r, w, h = rect
        line = citylib.front_line(rect, d)
        for k in range(depth):
            for t in line:
                u = (t[0] + d[0] * k, t[1] + d[1] * k)
                if self.inside(u, 1) and self.at(u) in (".", "=", ",") and u not in self.protect:
                    self.put(u, "P")
                    self.p.reserved.add(u)

    # 7. the street mesh ------------------------------------------------------------------------------------------
    def district_index(self, t):
        for i, ds in enumerate(self.plan.get("districts", [])):
            cx, cy = ds["centre"]
            rx, ry = ds["radius"]
            ang = math.atan2(t[1] - cy, t[0] - cx)
            k = 1.0 + (self.noise.at(math.cos(ang) * 3 + i * 10, math.sin(ang) * 3, 1.3) - 0.5) * 0.5
            if ((t[0] - cx) / rx) ** 2 + ((t[1] - cy) / ry) ** 2 > k:
                continue
            if ds.get("inside_wall") and t not in self.wall_inside:
                continue
            if ds.get("outside_wall") and t in self.wall_inside:
                continue
            return i
        return None

    def mesh(self):
        """The secondary streets and the alleys of each district, grown from the streets already there: a branch leaves
        a street every `every` tiles at a slant (never quite square), bends a little at each step and stops when it
        meets another street (a crossing), the district's edge, water, a wall or a landmark; one that would run beside
        another street closer than `gap` (the depth of a block) stops there. Branches shorter than `min_len` that meet
        nothing are dropped; the rest stay as dead-end lanes."""
        dists = self.plan.get("districts", [])
        for t in self.tiles():
            i = self.district_index(t)
            if i is not None:
                self.district_of[t] = i
        # streets leaving the plaza: from the middle of each side, outwards
        px, py = self.px, self.py
        exits = [((px + gen.PLAZA_W + 0.5, py + 2.0), 0.0), ((px + 3.0, py + gen.PLAZA_H + 0.5), math.pi / 2),
                 ((px - 1.0, py + 2.0), math.pi), ((px + gen.PLAZA_W + 0.5, py + gen.PLAZA_H - 1.0), 0.3)]
        for rank in ("street", "alley"):
            for i, ds in enumerate(dists):
                cfg = ds.get("streets" if rank == "street" else "alleys")
                if not cfg:
                    continue
                rng = random.Random(f"grow:{self.seed}:{i}:{rank}")
                # a queue: the streets there are, then each new one as it is drawn (alleys branch off streets only)
                queue = [ln for ln in self.lines if (ln[0] in ("main", "street") if rank == "street" else
                                                     ln[0] == "street")]
                first = True
                k = 0
                while k < len(queue) or first:
                    srcs = []
                    if first and rank == "street":
                        srcs = [(x, y, a, None) for (x, y), a in exits]
                    first = False
                    if k < len(queue):
                        srcs += self._branch_points(queue[k][1], float(cfg.get("every", 7)), rng)
                        k += 1
                    for (x, y, a, side) in srcs:
                        t = (int(round(x)), int(round(y)))
                        if self.district_of.get(t) != i and not any(
                                self.district_of.get((t[0] + d[0] * 2, t[1] + d[1] * 2)) == i for d in DIRS):
                            continue
                        if rng.random() >= float(cfg.get("p", 0.7)):
                            continue
                        for _try in range(int(cfg.get("tries", 3))):
                            if side is None:  # a plaza exit: outwards, a little askew
                                hd = a + math.radians(rng.uniform(-25, 25))
                            else:  # a branch: off the street at a slant, never quite square
                                hd = a + side * math.radians(rng.uniform(62, 118))
                            if self._grow(x, y, hd, i, cfg, rank, rng):
                                if rank == "street":
                                    queue.append(self.lines[-1])
                                break
                        if len(queue) > 400:
                            break

    def _branch_points(self, samples, every, rng):
        """(x, y, tangent angle, side) along a street every ~`every` tiles (both sides)."""
        out = []
        acc = rng.uniform(0, every)
        for k in range(1, len(samples)):
            (ax, ay), (bx, by) = samples[k - 1], samples[k]
            acc += math.hypot(bx - ax, by - ay)
            if acc >= every:
                acc = rng.uniform(-every * 0.25, every * 0.25)
                a = math.atan2(by - ay, bx - ax)
                out.append((bx, by, a, 1))
                out.append((bx, by, a, -1))
        return out

    def _dist_field(self):
        """BFS distance (4-neighbourhood) from every street, lane, plaza and bridge tile."""
        INF = 10 ** 6
        dist = [[INF] * self.w for _ in range(self.h)]
        todo = []
        for t in self.tiles():
            if self.at(t) in ("=", ",", "P", "b", "m", "v"):
                dist[t[1]][t[0]] = 0
                todo.append(t)
        k = 0
        while k < len(todo):
            t = todo[k]
            k += 1
            dv = dist[t[1]][t[0]] + 1
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if self.inside(u) and dist[u[1]][u[0]] > dv:
                    dist[u[1]][u[0]] = dv
                    todo.append(u)
        return dist

    def _grow(self, x, y, h, i, cfg, rank, rng):
        gap = float(cfg.get("gap", 6))
        max_len = float(cfg.get("max_len", 28))
        min_len = float(cfg.get("min_len", 5))
        turn = math.radians(float(cfg.get("turn", 14)))
        ch = cfg.get("ch", "=")
        dist = self._dist_field()
        step = 0.6
        pts = [(x, y)]
        own = {(int(round(x)), int(round(y)))}
        joined = False
        travelled = 0.0
        prev_d = None
        salt = rng.uniform(0, 500)
        blocked = ("w", "M", "R", "H", "#", "S", "N", "T")
        leaving = True
        hist = []
        stop = "max_len"
        bias = float(cfg.get("axis_bias", 0.55))

        def snapped(a):
            """Pulled towards the nearest axis by `bias`: streets run at gentle slants (on a tile grid a 45° street
            leaves no straight front for a house), bending a little as they go."""
            ax = round(a / (math.pi / 2)) * (math.pi / 2)
            return ax + (a - ax) * (1.0 - bias)

        h = snapped(h)
        while travelled < max_len:
            h += (self.noise.at(x + salt, y + salt, 4) - 0.5) * 2 * turn
            h = snapped(h) if bias else h
            x, y = x + math.cos(h) * step, y + math.sin(h) * step
            travelled += step
            t = (int(round(x)), int(round(y)))
            if t in own:
                pts.append((x, y))
                continue
            if not self.inside(t, 1):
                stop = "edge"
                break
            cur = self.at(t)
            if leaving:  # still on the street it branches off
                if cur in ("=", ",", "P", "b"):
                    own.add(t)
                    pts = [(x, y)]
                    travelled = 0.0
                    if len(own) > 8:
                        return self._why("stuck")
                    continue
                leaving = False
            if cur in blocked or t in self.protect:
                stop = "blocked"
                break
            if cur in ("=", ",", "P", "b") and travelled > 1.2:
                pts.append((x, y))
                joined = True
                break
            if t not in self.district_of:
                stop = "district"
                break
            dv = dist[t[1]][t[0]]
            hist.append(dv)
            pts.append((x, y))
            own.add(t)
        if not joined and travelled < min_len:
            return self._why("short:" + stop)
        if len(pts) < 2 or not hist:
            return self._why("empty")
        # between its two ends it keeps `clear` tiles from every other street: it leaves its street at once and, if
        # it meets another, it comes to it straight (a block between two streets is never thinner than that)
        clear = int(cfg.get("clear", max(2, int(gap) // 2)))
        i0 = next((k for k, v in enumerate(hist) if v >= clear), None)
        if i0 is None or i0 > clear + 3:
            return self._why("slow_exit")
        i1 = len(hist)
        if joined:
            while i1 > i0 and hist[i1 - 1] < clear:
                i1 -= 1
            if len(hist) - i1 > clear + 2:
                return self._why("oblique_join")
        if any(v < clear for v in hist[i0:i1]):
            return self._why("hugs")
        tiles = self.stamp(pts, float(cfg.get("width", 1.5)), ch, bridge=False, over=(".", "T", ",")) \
            if cfg.get("width", 1.5) > 1 else None
        if tiles is None:
            for t in path4(pts):
                if self.inside(t) and self.at(t) in (".", "T") and t not in self.protect:
                    self.put(t, ch)
        self.lines.append((rank, pts))
        self._why("ok:" + ("joined" if joined else stop))
        return True

    def _why(self, reason):
        self.stats[reason] = self.stats.get(reason, 0) + 1
        return False

    # 8. sites and filler -----------------------------------------------------------------------------------------
    def _free(self, t):
        return self.inside(t, 1) and self.at(t) == "." and t not in self.taken and t not in self.p.reserved \
            and t not in self.keep

    def place_site(self, typ, prefer_main):
        fw, fh = self.cat.footprints[typ]
        on_fields = bool(self.plan.get("skeleton"))  # a drawn town: a workshop may take the edge of a field
        pc = (self.px + gen.PLAZA_W / 2.0, self.py + gen.PLAZA_H / 2.0)
        best = None
        for r in range(1, self.h - fh):
            for c in range(1, self.w - fw):
                rect = (c, r, fw, fh)
                tiles = gen._tiles(rect)
                if not all(self._free(t) or (on_fields and self.at(t) in ("f", "T") and self.inside(t, 1)
                                             and t not in self.taken and t not in self.p.reserved) for t in tiles):
                    continue
                ring = gen._ring(rect)
                if any(t in self.taken or self.at(t) in ("#", "H") for t in ring):
                    continue
                for d in DIRS:
                    line = citylib.front_line(rect, d)
                    on = sum(1 for t in line if self.at(t) in WAYS or self.near_road(t, WAYS))
                    if on < math.ceil(len(line) * 0.6):
                        continue
                    door, drawn = gen.site_door(self.cat, typ, rect, d)
                    if self.at(door) not in ("=", ",", ".", "b", "P") or door in self.taken:
                        continue
                    if not (self.at(door) in WAYS + ("P",) or self.near_road(door, WAYS + ("P",))):
                        continue
                    main = door in self.p.main or any((door[0] + e[0], door[1] + e[1]) in self.p.main for e in DIRS)
                    vis = d in VISIBLE and drawn
                    cx, cy = c + fw / 2.0, r + fh / 2.0
                    dist = round(max(abs(cx - pc[0]), abs(cy - pc[1])), 1)
                    drawn = sum(1 for t in tiles if t in self.prefer) * 2 >= len(tiles) if self.prefer else True
                    key = (0 if vis else 1, 0 if main == prefer_main else 1, 0 if drawn else 1, dist, r, c)
                    if best is None or key < best[0]:
                        best = (key, rect, d, door)
        if best is None:
            return None
        _, rect, d, door = best
        for t in gen._tiles(rect):
            self.taken.add(t)
            self.put(t, "#")
        self.keep.add(door)
        return rect, d

    def sites_and_houses(self, start_ids, households):
        req = gen._required(self.cat, start_ids)
        order = sorted(req.items(), key=lambda kv: (0 if kv[0] == "player_forge" else 1, kv[0]))
        plots = []
        for sid, (typ, used_by) in order:
            foot = self.cat.footprints[typ]
            host = next((pl for pl in plots if not (pl[2] & used_by) and foot[0] <= pl[0][2] and foot[1] <= pl[0][3]
                         and gen.site_door(self.cat, typ, gen._flush(pl[0], foot, pl[1]), pl[1])[1]), None)
            if host is not None:
                rect = gen._flush(host[0], foot, host[1])
                d = host[1]
                host[2] |= used_by
            else:
                got = self.place_site(typ, prefer_main=True)
                if got is None:
                    raise SystemExit(f"organic: no cabe {sid} ({typ}) en {self.id}")
                rect, d = got
                plots.append([rect, d, set(used_by)])
            door = gen.site_door(self.cat, typ, rect, d)[0]
            self.sites[sid] = {"type": typ, "origin": [rect[0], rect[1]], "door": list(door)}
        self.homes = []
        for i in range(len(households)):
            got = self.place_site("house", prefer_main=False)
            if got is None:
                raise SystemExit(f"organic: solo caben {i} casas de vecinos de {len(households)} en {self.id}")
            rect, d = got
            sid = f"house_{i + 1:02d}"
            self.sites[sid] = {"type": "house", "origin": [rect[0], rect[1]],
                               "door": list(gen.site_door(self.cat, "house", rect, d)[0])}
            self.homes.append(sid)

    def filler(self):
        dists = self.plan.get("districts", [])
        pc = (self.px + gen.PLAZA_W / 2.0, self.py + gen.PLAZA_H / 2.0)
        front = []
        for t in self.tiles():
            i = self.district_of.get(t)
            if i is None or not self._free(t):
                continue
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if self.at(u) in WAYS + ("P",):
                    front.append((round(math.hypot(t[0] - pc[0], t[1] - pc[1]), 1), citylib.tile_hash(*t, 3), t, d, i))
        front.sort()
        rng = random.Random(f"filler:{self.seed}")
        for _, hsh, t, d, i in front:
            ds = dists[i]
            den = ds.get("density", {})
            if not self._free(t):
                continue
            if rng.random() >= float(den.get("fill", 0.8)):
                continue
            sizes = [tuple(s) for s in den.get("lot_sizes", [[3, 3]])]
            sizes = sizes[hsh % len(sizes):] + sizes[:hsh % len(sizes)]
            for along, depth in sizes:
                got = self._lot(t, d, along, depth, den, i)
                if got:
                    break
        # blocks: in a dense district a small block left between the houses is closed with yards (the patios and
        # gardens behind the fronts); a bigger one keeps its open middle
        free = {t for t in self.tiles() if self._free(t) and t in self.district_of}
        for g in citylib.groups_of(free):
            i = self.district_of[g[0]]
            den = dists[i].get("density", {})
            p = float(den.get("blocks", 0.0))
            if not p or len(g) > int(den.get("block_max", 30)):
                continue
            if any(self.near_road(t, WAYS + ("P",)) for t in g) and len(g) < 4:
                continue
            if citylib.tile_hash(*g[0], 23) % 1000 < p * 1000:
                for t in g:
                    if self.near_road(t, WAYS + ("P",)) and len(g) > 6:
                        continue  # the tiles on the street stay open (a gap between the fronts)
                    self.put(t, "#")
                    self.taken.add(t)
                    self.lot_tiles.add(t)
        # patios: grass shut in behind the houses of a dense district becomes yards
        for _ in range(2):
            for t in self.tiles():
                i = self.district_of.get(t)
                if i is None or not self._free(t) or self.near_road(t):
                    continue
                p = float(dists[i].get("density", {}).get("patios", 0.0))
                n = sum(1 for d in DIRS if self.at((t[0] + d[0], t[1] + d[1])) == "#"
                        and (t[0] + d[0], t[1] + d[1]) in self.lot_tiles)
                if n >= 2 and citylib.tile_hash(*t, 17) % 1000 < p * 1000:
                    self.put(t, "#")
                    self.taken.add(t)
                    self.lot_tiles.add(t)

    def _lot(self, t, d, along, depth, den, i):
        """A house lot whose front (side d) is on the street at t: tries the shifts that keep t on its front."""
        step = (1, 0) if d[1] != 0 else (0, 1)
        touch = bool(den.get("touch", False))
        back = int(den.get("backyard", 0))
        setback = int(den.get("setback", 0))
        loose = bool(self.plan.get("skeleton"))  # a drawn town: a lot may lie across two districts
        for shift in range(0, along):
            # the front tiles of the house, then the rect behind them (away from the street)
            f0 = (t[0] - step[0] * shift - d[0] * setback, t[1] - step[1] * shift - d[1] * setback)
            fronts = [(f0[0] + step[0] * k, f0[1] + step[1] * k) for k in range(along)]
            tiles = [(f[0] - d[0] * j, f[1] - d[1] * j) for f in fronts for j in range(depth)]
            if not all(self._free(u) and (self.district_of.get(u) == i or (loose and u in self.district_of))
                       for u in tiles):
                continue
            # each front tile reaches the street straight ahead within 1 + setback + slack tiles of open grass
            way = []
            hits = 0
            for f in fronts:
                u = f
                for k in range(1, setback + 3):
                    u = (f[0] + d[0] * k, f[1] + d[1] * k)
                    if self.at(u) in WAYS + ("P",):
                        hits += 1
                        break
                    if not (self._free(u) or u in self.keep) or self.at(u) != ".":
                        break
                    way.append(u)
            if hits < (along if along <= 2 else along - 1):
                continue
            mid = fronts[along // 2]
            ahead = (mid[0] + d[0], mid[1] + d[1])
            if not (self.at(ahead) in WAYS + ("P",) or ahead in way):
                continue
            cs = [u[0] for u in tiles]
            rs = [u[1] for u in tiles]
            rect = (min(cs), min(rs), max(cs) - min(cs) + 1, max(rs) - min(rs) + 1)
            ring = gen._ring(rect)
            if not touch and any(u in self.taken for u in ring if u not in way):
                continue
            # the back yard (and nothing more) behind the house
            extra = []
            for j in range(depth, depth + back):
                row = [(f[0] - d[0] * j, f[1] - d[1] * j) for f in fronts]
                if all(self._free(u) and (self.district_of.get(u) == i or (loose and u in self.district_of))
                       for u in row):
                    extra += row
                else:
                    break
            for u in tiles + extra:
                self.put(u, "#")
                self.taken.add(u)
                self.lot_tiles.add(u)
            for u in way:
                self.keep.add(u) if self.at(u) == "." else None
            self.lots.append((rect[0], rect[1], rect[2], rect[3], self.plan["districts"][i]["id"]))
            return True
        return False

    # 9. fields, woods, pockets -----------------------------------------------------------------------------------
    def fields(self):
        if self.plan.get("skeleton"):
            # the drawing's fields (its pieces of 6 tiles or more, nearest the plaza first)
            pc = (self.px + gen.PLAZA_W / 2.0, self.py + gen.PLAZA_H / 2.0)
            cells = [g for g in citylib.groups_of({t for t in self.tiles() if self.at(t) == "f"}) if len(g) >= 6]
            cells.sort(key=lambda g: (min(abs(t[0] - pc[0]) + abs(t[1] - pc[1]) for t in g), g[0]))
            self.field_cells = list(getattr(self, "plot_cells", [])) + cells
            if self.field_cells:
                return
        cfg = self.plan.get("fields", {})
        n = int(cfg.get("count", 4))
        cell = float(cfg.get("cell", 8))
        zone = [t for t in self.tiles() if self.inside(t, 1) and self.at(t) == "." and t not in self.district_of
                and t not in self.p.reserved and t not in self.taken]
        if not zone:
            raise SystemExit(f"organic: no queda sitio para los campos en {self.id}")
        rng = random.Random(f"fields:{self.seed}")
        seeds = []
        cand = sorted(zone, key=lambda t: (t[1], t[0]))
        for _ in range(len(zone) * 3 // max(1, int(cell))):
            t = cand[rng.randrange(len(cand))]
            if all(math.hypot(t[0] - s[0], t[1] - s[1]) >= cell for s in seeds):
                seeds.append(t)
        owner = {}
        for t in zone:
            x = t[0] + (self.noise.at(t[0] + 7, t[1], 6) - 0.5) * 4
            y = t[1] + (self.noise.at(t[0], t[1] + 7, 6) - 0.5) * 4
            owner[t] = min(range(len(seeds)), key=lambda k: (x - seeds[k][0]) ** 2 + (y - seeds[k][1]) ** 2)
        cells = {}
        for t, k in owner.items():
            cells.setdefault(k, []).append(t)
        pc = (self.px + gen.PLAZA_W / 2.0, self.py + gen.PLAZA_H / 2.0)
        near_x = cfg.get("near", [pc[0], pc[1]])
        scored = []
        for k, ts in cells.items():
            inner = [t for t in ts if all(owner.get((t[0] + d[0], t[1] + d[1])) == k for d in DIRS)
                     and not any(self.at((t[0] + dc, t[1] + dr)) in ("#", "H", "M", "S", "N", "P", "R")
                                 for dc in (-1, 0, 1) for dr in (-1, 0, 1))]
            if len(inner) < cfg.get("min_size", 16):
                continue
            touches = any(self.near_road(t, WAYS) for t in ts) or any(
                self.at((t[0] + dc, t[1] + dr)) in WAYS for t in ts for dc in (-2, 0, 2) for dr in (-2, 0, 2))
            if not touches:
                continue
            mx = sum(t[0] for t in ts) / len(ts)
            my = sum(t[1] for t in ts) / len(ts)
            scored.append((round(math.hypot(mx - near_x[0], my - near_x[1]), 1), k, inner, ts))
        scored.sort()
        self.field_cells = list(getattr(self, "plot_cells", []))
        for _, k, inner, ts in scored[:n]:
            for t in inner:
                self.put(t, "f")
                self.taken.add(t)
            # a dirt lane round the field where its border meets another cell
            if cfg.get("lanes", True):
                for t in ts:
                    if t in inner or self.at(t) != ".":
                        continue
                    if any(owner.get((t[0] + d[0], t[1] + d[1])) not in (k, None) for d in DIRS):
                        self.put(t, ",")
            self.field_cells.append(sorted(inner, key=lambda t: (t[1], t[0])))
        if not self.field_cells:
            raise SystemExit(f"organic: ningún campo cabe en {self.id}")

    def woods(self):
        dens = float(self.plan.get("trees", 0.1))
        garden = float(self.plan.get("gardens", 0.05))
        for t in self.tiles():
            if self.at(t) != "." or t in self.p.reserved or t in self.taken or t in self.keep:
                continue
            near = any(self.at((t[0] + dc, t[1] + dr)) not in (".", "T", "f", "R", "w")
                       for dc in (-1, 0, 1) for dr in (-1, 0, 1))
            if near:
                continue
            near2 = any(self.at((t[0] + dc, t[1] + dr)) in ROADS + ("#", "H")
                        for dc in (-2, -1, 0, 1, 2) for dr in (-2, -1, 0, 1, 2))
            if t in self.district_of:
                if not near2 and citylib.tile_hash(*t, 11) % 1000 < garden * 1000:
                    self.put(t, "T")
                continue
            if near2:
                continue
            forest = self.noise.at(t[0] + 300, t[1] + 300, 6)
            k = dens * (0.5 + 2.6 * max(0.0, forest - 0.35))
            if citylib.tile_hash(*t, 13) % 1000 < k * 1000:
                self.put(t, "T")

    def tidy(self):
        """One street network: street bits not joined to the plaza's become dirt lanes; then every walkable tile that
        cannot be reached from the plaza becomes trees (or water for a stranded pier)."""
        net = {t for t in self.tiles() if self.at(t) in STREETS}
        start = next(iter(sorted(self.square)))
        seen = {start}
        todo = [start]
        while todo:
            t = todo.pop()
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if u in net and u not in seen:
                    seen.add(u)
                    todo.append(u)
        for t in sorted(net - seen):
            if self.at(t) == "b":
                self.put(t, "w")  # a bridge that leads nowhere
            elif self.at(t) == "=":
                self.put(t, ",")
            elif self.at(t) == "P":
                self.put(t, ".")
        walk = {ch for ch, k in self.cat.kind_of.items() if self.cat.walk.get(k) is not None}
        seen = {start}
        todo = [start]
        while todo:
            t = todo.pop()
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if u not in seen and self.p.inside(*u) and self.at(u) in walk:
                    seen.add(u)
                    todo.append(u)
        for t in self.tiles():
            if self.at(t) in walk and t not in seen:
                ch = self.at(t)
                if t in self.keep:
                    raise SystemExit(f"organic: la casilla {t} ({ch}) de una puerta queda aislada en {self.id}")
                self.put(t, "w" if ch in ("m", "b", "v") else "T")

    # 10. the map -------------------------------------------------------------------------------------------------
    def workplaces(self):
        px, py = self.px, self.py
        wp = {}
        for wid, kind, rel, stall in gen.TEMPLATE["workplaces_plaza"]:
            e = {"id": wid, "kind": kind, "tile": [px + rel[0], py + rel[1]]}
            if stall:
                e["stall"] = stall
            wp[wid] = e
        gw = next(t for n, t in self.p.gates if n == "west_gate")
        ge = next(t for n, t in self.p.gates if n == "east_gate")
        wp["gate_west"] = {"id": "gate_west", "kind": "tile", "tile": [gw[0] + 1, gw[1]]}
        wp["gate_east"] = {"id": "gate_east", "kind": "tile", "tile": [ge[0] - 1, ge[1]]}
        fields = self.field_cells
        for i, name in enumerate(["field_a", "field_b", "field_c", "field_d"]):
            f = fields[i % len(fields)]
            k = i // len(fields)
            edge = [t for t in f if any(self.at((t[0] + d[0], t[1] + d[1])) in WAYS for d in DIRS)] or f
            wp[name] = {"id": name, "kind": "tile", "tile": list(edge[min(len(edge) - 1, k * 2)])}
        bank = None
        pc = (px + 5, py + 6)
        for t in sorted(self.tiles(), key=lambda t: (abs(t[0] - pc[0]) + abs(t[1] - pc[1]), t[1], t[0])):
            if self.at(t) in (".", ",") and t not in self.keep and any(self.at((t[0] + d[0], t[1] + d[1])) == "w"
                                                                        for d in DIRS):
                bank = t
                break
        if bank is None:
            raise SystemExit(f"organic: sin orilla para el oficio river_bank en {self.id}")
        wp["river_bank"] = {"id": "river_bank", "kind": "tile", "tile": list(bank)}
        a = self.sites["armory"]
        wp["armory"] = {"id": "armory", "kind": "shop", "tile": list(a["door"]), "building": "armory", "stall": "armory"}
        s = self.town_hall["service"]
        wp["townhall_a"] = {"id": "townhall_a", "kind": "tile", "tile": [s[0] - 2, s[1]]}
        wp["townhall_b"] = {"id": "townhall_b", "kind": "tile", "tile": [s[0] + 2, s[1]]}
        o = self.town_hall["origin"]
        wp["church_a"] = {"id": "church_a", "kind": "tile", "tile": [o[0] - 1, o[1] + 1]}
        wp["church_b"] = {"id": "church_b", "kind": "tile", "tile": [o[0] + 6, o[1] + 1]}
        return [wp[k] for k in gen.WORKPLACE_ORDER]


def build(map_id, plan, cat=None, variant=None):
    """variant: "imagen" (the skeleton of the plan's drawing), "procedural", or None (the plan's "use")."""
    cat = cat or citylib.Catalog()
    plan = json.loads(json.dumps(plan))
    if (variant or plan.get("use", "procedural")) != "imagen":
        plan.pop("skeleton", None)
    elif not plan.get("skeleton"):
        raise SystemExit(f"organic: {map_id} no tiene plano de imagen (\"skeleton\")")
    tw = Town(map_id, plan, cat)
    start_ids = plan.get("starts") or ["artisan_blacksmith", "artisan_carpenter", "artisan_mason", "artisan_tailor"]
    pop = citylib.load_json(os.path.join(citylib.DATA, "maps", "town_e.json"))
    households = gen.population_of(pop.get("population", []), int(plan["households"]))
    if plan.get("skeleton"):  # the skeleton from a semantic plan (an image: tools/city/esqueleto.py)
        import esqueleto
        esqueleto.apply(tw)
        tw.plaza()
        esqueleto.after_plaza(tw)
        tw.place_plots()
    else:
        tw.terrain()
        tw.plaza()
        tw.roads()
        tw.walls()
        tw.port()
        tw.place_landmarks("early")
        tw.place_plots()
        for ln in plan.get("lanes", []):
            tw.stamp(spline(jitter(tw.rng, ln["path"], ln.get("jitter", 1.0)), 0.2), ln.get("width", 1),
                     ln.get("ch", ","), bridge=ln.get("ford", True))
        tw.mesh()
        tw.place_landmarks("mid")
    tw.sites_and_houses(start_ids, households)
    tw.filler()
    tw.fields()
    tw.place_landmarks("late")
    tw.woods()
    tw.tidy()
    p = tw.p
    px, py = tw.px, tw.py
    spawns = {k: [px + v[0], py + v[1]] for k, v in gen.TEMPLATE["spawns"].items()}
    for name, t in p.gates:
        spawns[name] = list(t)
    social = [{"id": s["id"], "kind": s["kind"], "slots": [[px + a, py + b] for a, b in s["slots"]]}
              for s in gen.TEMPLATE["social_points"]]
    wps = tw.workplaces()
    population = []
    for i, hh in enumerate(households):
        e = json.loads(json.dumps(hh))
        e["home"] = tw.homes[i]
        population.append(e)
    rows = ["".join(r) for r in p.g]
    dists = [{"id": d["id"], "roof": d.get("roof", "#7a4a3a")} for d in plan.get("districts", [])]
    data = {"id": map_id, "name_key": f"map.{map_id}", "size": [tw.w, tw.h], "rows": rows, "spawns": spawns,
            "stalls": tw.stalls, "board": tw.board, "town_hall": tw.town_hall,
            "buildings": {k: tw.sites[k] for k in sorted(tw.sites)}, "social_points": social, "workplaces": wps,
            "population": population,
            "landmarks": sorted(tw.landmarks, key=lambda e: (e["origin"][1], e["origin"][0])),
            "boats": tw.boats,
            "generated": {"layout": "organic" + ("+imagen" if plan.get("skeleton") else ""), "plan": map_id, "seed": tw.seed, "size": [tw.w, tw.h],
                          "tool": "tools/city/ciudad.py generar --plan", "starts": start_ids,
                          "style": plan.get("style", ""), "rivers": tw.rivers, "districts": dists,
                          "lots": ";".join(",".join(str(x) for x in lot) for lot in tw.lots)}}
    m = citylib.Map(data, cat)
    data["decor"] = citylib.dress(m)
    citylib.add_life(data, cat)  # 04f 4.24: meeting points and patrols, after the decor (never on it)
    for line in tw.log:
        print("  aviso del plan:", line)
    return data


def main(ids, out="", variant=None):
    plans = load_plans()
    cat = citylib.Catalog()
    bad = 0
    import preview
    for mid in ids or [k for k in plans if not k.startswith("_")]:
        plan = plans[mid]
        data = build(mid, plan, cat, variant)
        if out:
            os.makedirs(out, exist_ok=True)
            path = os.path.join(out, mid + ".json")
            with open(path, "w", encoding="utf-8") as f:
                f.write(citylib.dumps_map(data))
        else:
            path = citylib.save_map(data)
        m = citylib.Map(data, cat)
        rep = citylib.validate(m, strict=True)
        print(f"generar {mid} (orgánica, semilla {plan.get('seed', 1)}, {data['size'][0]}x{data['size'][1]}) -> "
              f"{os.path.relpath(path, citylib.ROOT)}: {len(rep.errors)} errores, {len(rep.warnings)} avisos")
        for e in rep.errors:
            print("  ERROR", e)
        for x in rep.warnings:
            print("  aviso", x)
        for n in rep.info:
            print("  ·", n)
        bad += len(rep.errors)
        print("  vista:", preview.render_data(data, cat, os.path.join(out or os.path.join(citylib.ROOT, "reports",
                                                                                            "ciudad"), mid + ".png")))
    return 1 if bad else 0
