"""The skeleton of a town taken from a semantic plan (tools/city/desde_imagen.py), for tools/city/organic.py: a plan
with "skeleton" gets its water, streets, squares, walls, landmarks, fields, woods, rock and where the houses stand
from the image; the sim's market, the sites, the house lots, the doors and the dressing stay with the generator
(docs/protocolos/generar-ciudad.md §1e).

  "skeleton": {"image": "docs/arte/ciudades_v2/fal/region_port.png", "types": {"church": "cathedral"},
               "districts": [{"id": ..., "when": "inside|outside|dense|loose|any", "roof": ..., "density": {...}}],
               "towers_every": 10, "boats": 4, "rowboats": 3, "crane": {...}, "trees": 0.05}

Clean-up of the grid read from the image: walls only in pieces of 12 tiles or more (the thin plot lines of the
drawing go), streets in pieces of 4 or more, joined to the plaza's network by the shortest way over open ground
(else dropped); a river's course (its centre line and width, measured column by column) closed where the drawing
left a gap; a street over the water is a bridge; a pier off the water is quay; the gates on the map's edges.
"""
import math
import os

import citylib
import desde_imagen
import generator as gen
from citylib import DIRS

PASS = (".", "T", "f", ",")  # open ground a street may be laid over when joining two pieces


def apply(tw):
    """Reads the image into the grid (before the plaza)."""
    sk = tw.plan["skeleton"]
    pal = desde_imagen.palette()["classes"]
    classes = tw.plan.get("fal", {}).get("classes") or list(pal)
    grid, shares = desde_imagen.classify(os.path.join(citylib.ROOT, sk["image"]), (tw.w, tw.h), classes)
    tw.sk_grid = grid
    types = dict({k: v["landmark"] for k, v in pal.items() if v.get("landmark")}, **sk.get("types", {}))
    ch_of = {"grass": ".", "street": "=", "plaza": "P", "water": "w", "building": ".", "wall": "M", "field": "f",
             "forest": "T", "dock": "m", "rock": "R"}
    tw.sk_houses = set()
    tw.sk_blobs = {}  # landmark type -> [tiles]
    for t, k in grid.items():
        if k in types:
            tw.sk_blobs.setdefault(types[k], []).append(t)
            tw.put(t, ".")
            continue
        tw.put(t, ch_of.get(k, "."))
        if k == "building":
            tw.sk_houses.add(t)
    _wall_from_drawing(tw)
    # a pier is only a pier on the water (brown outlines of the drawing's houses read as piers too)
    for t in list(tw.tiles()):
        if tw.at(t) == "m" and not any(tw.at((t[0] + d[0], t[1] + d[1])) == "w" for d in DIRS):
            tw.put(t, ".")
            tw.sk_houses.add(t)
    _drawn_landmarks(tw)
    # the plaza: the template goes on the drawing's main square (its biggest piece), on land
    sq = citylib.groups_of({t for t in tw.tiles() if tw.at(t) == "P"})
    if sq:
        big = max(sq, key=len)
        cx = sum(t[0] for t in big) / len(big)
        cy = sum(t[1] for t in big) / len(big)
        tw.plan["plaza"] = dict(tw.plan.get("plaza", {}), centre=[int(round(cx)), int(round(cy))])
    cx, cy = tw.plan["plaza"]["centre"]
    # on dry land: the nearest spot whose market, town hall and armory have no water, rock nor wall under them
    best = None
    for py in range(7, tw.h - gen.PLAZA_H - 5):
        for px in range(6, tw.w - gen.PLAZA_W - 5):
            bad = 0
            lm = 0
            for c in range(px - 5, px + gen.PLAZA_W + 1):
                for r in range(py - 6, py + gen.PLAZA_H + 1):
                    k = tw.at((c, r))
                    if k in ("w", "R", "M", "m"):
                        bad += 1
                    elif k == "H":
                        lm += 1
            if bad:
                continue
            d = abs(px + gen.PLAZA_W / 2.0 - cx) + abs(py + gen.PLAZA_H / 2.0 - cy) + lm * 3
            if best is None or d < best[0]:
                best = (d, px, py)
    if best is None:
        raise SystemExit(f"esqueleto: la plaza no cabe en tierra en {tw.id}")
    _, px, py = best
    tw.plan["plaza"] = dict(tw.plan["plaza"], centre=[px + gen.PLAZA_W // 2, py + gen.PLAZA_H // 2])
    # a drawn landmark in the way of the market goes (the plan places it again later)
    zone = {(c, r) for c in range(px - 5, px + gen.PLAZA_W + 1) for r in range(py - 6, py + gen.PLAZA_H + 1)}
    keep = []
    for e in tw.landmarks:
        tiles = set(gen._tiles(tuple(e["origin"]) + tuple(e["size"])))
        if tiles & zone:
            for t in tiles:
                tw.put(t, ".")
                tw.taken.discard(t)
            tw.sk_done.discard(e["type"])
        else:
            keep.append(e)
    tw.landmarks = keep
    # clear the ground the market, the town hall and the armory stand on (and their rings)
    for c in range(px - 5, px + gen.PLAZA_W + 1):
        for r in range(py - 6, py + gen.PLAZA_H + 1):
            t = (c, r)
            inner = px <= c < px + gen.PLAZA_W and py <= r < py + gen.PLAZA_H
            th = px <= c <= px + 7 and py - 6 <= r < py
            ar = px - 5 <= c < px and py + 7 <= r <= py + 12
            if (inner or th or ar) and tw.inside(t) and tw.at(t) != "w":
                tw.put(t, ".")
                tw.sk_houses.discard(t)
    tw.rivers = []


def after_plaza(tw):
    """Streets, water, walls, landmarks, port and districts, once the market and the town hall stand."""
    sk = tw.plan["skeleton"]
    _drop_small(tw, "=", 4, ".")
    _fix_diagonals(tw)
    _rivers(tw)
    _docks(tw)
    _bridges(tw)
    _connect(tw)
    for name, side in (("west_gate", "w"), ("east_gate", "e")):
        _ensure_edge(tw, side)
    _edge_gates(tw)
    _bridges(tw)
    _open_gates(tw)
    _main_ways(tw)
    _wall_inside(tw)
    _towers(tw, sk)
    _landmarks(tw, sk)
    _port(tw, sk)
    _districts(tw, sk)
    _loose_bridges(tw)
    _verges(tw)


def _verges(tw):
    """A strip of grass between a field and the street beside it (where the lanterns stand)."""
    for t in list(tw.tiles()):
        if tw.at(t) == "f" and any(tw.at((t[0] + d[0], t[1] + d[1])) in ("=", "b", "P") for d in DIRS):
            tw.put(t, ".")


def _loose_bridges(tw):
    """A bridge that does not join two banks goes back to water (bits of the drawing's grey over the blue)."""
    for g in citylib.groups_of({t for t in tw.tiles() if tw.at(t) == "b"}):
        gs = set(g)
        banks = {(t[0] + d[0], t[1] + d[1]) for t in g for d in DIRS} - gs
        banks = {u for u in banks if tw.at(u) not in ("w", "b", "m", "v", "", "M", "R", "H", "#")}
        if len(citylib.groups_of8(banks)) < 2:
            for t in g:
                tw.put(t, "w")


# --- pieces -----------------------------------------------------------------------------------------------------

def _wall_from_drawing(tw):
    """The drawn wall, closed: from the centre of the wall's tiles, the distance at which the drawing has wall in
    each direction (the median of its tiles in that direction, filled in where the drawing breaks it); the ring is
    drawn on the land at that distance, ends on the river bank and opens where a street crosses it (a gate)."""
    tw.sk_gates = set()
    walls = [t for t in tw.tiles() if tw.at(t) == "M"]
    for t in walls:
        tw.put(t, ".")
    big = [g for g in citylib.groups_of8(set(walls)) if len(g) >= 4]
    pts = [t for g in big for t in g]
    if len(pts) < 16:
        return
    cx = sum(t[0] for t in pts) / len(pts)
    cy = sum(t[1] for t in pts) / len(pts)
    n = 48
    bins = [[] for _ in range(n)]
    for t in pts:
        a = math.atan2(t[1] - cy, t[0] - cx)
        bins[int((a + math.pi) / (2 * math.pi) * n) % n].append(math.hypot(t[0] - cx, t[1] - cy))
    rad = [sorted(b)[len(b) // 2] if b else None for b in bins]
    known = [i for i, v in enumerate(rad) if v is not None]
    if len(known) < n // 4:
        return
    full = []
    for i in range(n):
        if rad[i] is not None:
            full.append(rad[i])
            continue
        a = max((k for k in known if k < i), default=known[-1] - n)
        b = min((k for k in known if k > i), default=known[0] + n)
        ra, rb = rad[a % n], rad[b % n]
        full.append(ra + (rb - ra) * (i - a) / float(b - a))
    sm = [(full[(i - 1) % n] + 2 * full[i] + full[(i + 1) % n]) / 4.0 for i in range(n)]

    def radius(a):
        f = (a + math.pi) / (2 * math.pi) * n - 0.5
        i = int(math.floor(f)) % n
        k = f - math.floor(f)
        return sm[i] * (1 - k) + sm[(i + 1) % n] * k

    start = (int(round(cx)), int(round(cy)))
    inside = {t for t in tw.tiles() if tw.at(t) != "w"
              and math.hypot(t[0] - cx, t[1] - cy) <= radius(math.atan2(t[1] - cy, t[0] - cx))}
    if start not in inside:
        return
    seen = {start}
    todo = [start]
    while todo:
        t = todo.pop()
        for d in DIRS:
            u = (t[0] + d[0], t[1] + d[1])
            if u in inside and u not in seen:
                seen.add(u)
                todo.append(u)
    for t in sorted(seen, key=lambda t: (t[1], t[0])):
        if any((t[0] + dc, t[1] + dr) not in seen and tw.at((t[0] + dc, t[1] + dr)) not in ("w", "")
               for dc in (-1, 0, 1) for dr in (-1, 0, 1)):
            if tw.at(t) in (".", "T", "f", "R"):
                tw.put(t, "M")
                tw.sk_houses.discard(t)
            elif tw.at(t) in ("=", ","):
                tw.sk_gates.add(t)  # a street where the ring passes: a gate
    tw.sk_inside = seen


def _drop_small(tw, ch, n, to):
    for g in citylib.groups_of({t for t in tw.tiles() if tw.at(t) == ch}):
        if len(g) < n:
            for t in g:
                tw.put(t, to)


def _fix_diagonals(tw):
    """Two street tiles that only touch at a corner get the tile beside them (4-connected streets)."""
    for t in sorted(tw.tiles(), key=lambda t: (t[1], t[0])):
        if tw.at(t) != "=":
            continue
        for dc, dr in ((1, 1), (-1, 1)):
            u = (t[0] + dc, t[1] + dr)
            a, b = (t[0] + dc, t[1]), (t[0], t[1] + dr)
            if tw.at(u) == "=" and tw.at(a) not in ("=", "P", "b") and tw.at(b) not in ("=", "P", "b"):
                for v in (a, b):
                    if tw.at(v) in PASS and v not in tw.protect:
                        tw.put(v, "=")
                        break


def _rivers(tw):
    """Each river of the drawing (a water piece that spans the map): its course measured column by column (or row by
    row), closed where the drawing left a gap; the course goes to "generated".rivers for the validator."""
    water = {t for t in tw.tiles() if tw.at(t) == "w"}
    for g in citylib.groups_of8(water) if water else []:
        cs = [t[0] for t in g]
        rs = [t[1] for t in g]
        span_c, span_r = max(cs) - min(cs) + 1, max(rs) - min(rs) + 1
        if max(span_c, span_r) < min(tw.w, tw.h) * 0.6:
            continue  # a pond
        horiz = span_c >= span_r
        lines = {}
        for (c, r) in g:
            lines.setdefault(c if horiz else r, []).append(r if horiz else c)
        keys = sorted(lines)
        runs = sorted(max(v) - min(v) + 1 for v in lines.values())
        width = runs[len(runs) // 2]
        centre = {k: sum(v) / len(v) for k, v in lines.items()}
        pts = []
        lo, hi = 0, (tw.w if horiz else tw.h) - 1
        for k in range(lo, hi + 1):
            if k in centre:
                m = centre[k]
            else:  # a gap of the drawing: between its two neighbours
                a = max((x for x in keys if x < k), default=None)
                b = min((x for x in keys if x > k), default=None)
                if a is None and b is None:
                    continue
                m = centre[a] if b is None else centre[b] if a is None else \
                    centre[a] + (centre[b] - centre[a]) * (k - a) / (b - a)
            pts.append((k, m) if horiz else (m, k))
        # smooth the course a little
        sm = []
        for i in range(len(pts)):
            win = pts[max(0, i - 2):i + 3]
            sm.append((sum(p[0] for p in win) / len(win), sum(p[1] for p in win) / len(win)))
        core = max(0.6, width / 2.0 - 0.9)
        for t in tw.tiles():
            if citylib._dist_poly(t[0], t[1], sm[::2] + [sm[-1]]) <= core:
                cur = tw.at(t)
                if cur in ("=", "P", ","):
                    tw.put(t, "b")
                elif cur not in ("w", "b", "m", "v") and t not in tw.protect:
                    tw.put(t, "w")
                    tw.sk_houses.discard(t)
        tw.rivers.append({"path": [[round(x, 1), round(y, 1)] for x, y in sm[::4] + [sm[-1]]],
                          "width": float(width), "core": round(core, 2)})


def _docks(tw):
    for t in list(tw.tiles()):
        if tw.at(t) == "m" and not any(tw.at((t[0] + d[0], t[1] + d[1])) == "w" for d in DIRS):
            tw.put(t, "=")
    for g in citylib.groups_of({t for t in tw.tiles() if tw.at(t) == "m"}):
        land = any(tw.at((t[0] + d[0], t[1] + d[1])) in ("=", ".", "P", ",") for t in g for d in DIRS)
        if not land:
            for t in g:
                tw.put(t, "w")


def _net(tw):
    return {t for t in tw.tiles() if tw.at(t) in ("=", "P", "b")}


def _connect(tw):
    """Every street piece joined to the plaza's by the shortest way over open ground (8 tiles at most); a piece
    that cannot be joined becomes a dirt lane if it is long, or goes."""
    for _ in range(40):
        net = _net(tw)
        groups = citylib.groups_of(net)
        start = (tw.px + 2, tw.py + 2)
        main = next((g for g in groups if start in g), None)
        if main is None:
            return
        main = set(main)
        rest = sorted((g for g in groups if not set(g) <= main), key=len, reverse=True)
        if not rest:
            return
        g = rest[0]
        path = _way(tw, set(g), main, 12)
        if path is None:
            for t in g:
                tw.put(t, "," if len(g) >= 8 and tw.at(t) == "=" else (tw.at(t) if tw.at(t) == "b" else "."))
            continue
        for t in path:
            tw.put(t, "b" if tw.at(t) == "w" else "=")


def _way(tw, src, dst, limit):
    """The shortest 4-connected way of open tiles from a tile of src to one next to dst (its tiles, or None)."""
    prev = {t: None for t in src}
    frontier = list(src)
    for _ in range(limit):
        nxt = []
        for t in frontier:
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if u in prev or not tw.inside(u, 1):
                    continue
                if u in dst:
                    out = []
                    v = t
                    while v is not None and v not in src:
                        out.append(v)
                        v = prev[v]
                    return out
                if (tw.at(u) in PASS or tw.at(u) == "w") and u not in tw.protect and u not in tw.taken:
                    prev[u] = t
                    nxt.append(u)
        frontier = nxt
    return None


def _ensure_edge(tw, side):
    """A road out of the map on the west (or east) edge: if no street reaches it, one from the street nearest it."""
    col = 0 if side == "w" else tw.w - 1
    inner = 1 if side == "w" else tw.w - 2
    if any(tw.at((col, r)) == "=" and tw.at((inner, r)) == "=" for r in range(tw.h)):
        return
    best = None
    for t in _net(tw):
        if tw.at(t) != "=":
            continue
        d = t[0] if side == "w" else tw.w - 1 - t[0]
        key = (d + abs(t[1] - tw.h / 2) * 0.3, t[1])
        if best is None or key < best[0]:
            best = (key, t)
    if best is None:
        return
    c0, r = best[1]
    rng = range(c0, -1, -1) if side == "w" else range(c0, tw.w)
    for c in rng:
        for rr in (r, r + 1):
            t = (c, rr)
            if tw.at(t) in PASS + ("M",) or tw.at(t) == "=":
                tw.put(t, "=")
            elif tw.at(t) == "w":
                tw.put(t, "b")


def _edge_gates(tw):
    for name, test in (("west_gate", lambda t: t[0] == 0), ("east_gate", lambda t: t[0] == tw.w - 1),
                       ("north_gate", lambda t: t[1] == 0), ("south_gate", lambda t: t[1] == tw.h - 1)):
        edge = sorted(t for t in tw.tiles() if test(t) and tw.at(t) == "=")
        if not edge:
            continue
        if name == "west_gate":
            edge = [t for t in edge if tw.at((1, t[1])) == "="]
        if name == "east_gate":
            edge = [t for t in edge if tw.at((tw.w - 2, t[1])) == "="]
        if not edge:
            continue
        mid = (tw.w / 2.0, tw.h / 2.0)
        tw.p.gates.append((name, min(edge, key=lambda t: (abs(t[0] - mid[0]) + abs(t[1] - mid[1]), t))))


def _bridges(tw):
    """A street tile with water on two opposite sides is a bridge; a bridge tile off the water goes back to street."""
    for _ in range(3):
        for t in list(tw.tiles()):
            if tw.at(t) != "=":
                continue
            wet = lambda u: tw.at(u) in ("w", "b")
            if (wet((t[0] - 1, t[1])) and wet((t[0] + 1, t[1]))) or (wet((t[0], t[1] - 1)) and wet((t[0], t[1] + 1))):
                if any(tw.at((t[0] + d[0], t[1] + d[1])) == "w" for d in DIRS):
                    tw.put(t, "b")
    for t in list(tw.tiles()):
        if tw.at(t) == "b" and not any(tw.at((t[0] + d[0], t[1] + d[1])) in ("w",) for d in DIRS):
            tw.put(t, "=")


def _open_gates(tw):
    """A wall that shuts in ground nobody can reach gets a gate: the wall tile between the reached outside and the
    shut inside nearest a street, opened as street (a gate tower goes on each side later)."""
    walk = {ch for ch, k in tw.cat.kind_of.items() if tw.cat.walk.get(k) is not None}
    for _ in range(6):
        start = (tw.px + 2, tw.py + 2)
        seen = {start}
        todo = [start]
        while todo:
            t = todo.pop()
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if u not in seen and tw.inside(u) and tw.at(u) in walk:
                    seen.add(u)
                    todo.append(u)
        shut = {t for t in tw.tiles() if tw.at(t) in walk and t not in seen}
        if len(shut) < 6:
            return
        best = None
        for t in tw.tiles():
            if tw.at(t) != "M":
                continue
            a = [(t[0] + d[0], t[1] + d[1]) for d in DIRS]
            for d in DIRS:
                o, i = (t[0] + d[0], t[1] + d[1]), (t[0] - d[0], t[1] - d[1])
                if o in seen and i in shut:
                    near = 0 if tw.at(o) in ("=", "P") else 1
                    key = (near, abs(t[0] - start[0]) + abs(t[1] - start[1]), t)
                    if best is None or key < best[0]:
                        best = (key, t, i)
        if best is None:
            return
        _, g, i = best
        tw.put(g, "=")
        tw.sk_opened = getattr(tw, "sk_opened", set()) | {g}
        if tw.at(i) in PASS:
            tw.put(i, "=")


def _main_ways(tw):
    """The main streets: the shortest ways from each gate to the plaza (the workshops prefer them)."""
    net = _net(tw)
    start = (tw.px + 2, tw.py + 2)
    prev = {start: None}
    todo = [start]
    k = 0
    while k < len(todo):
        t = todo[k]
        k += 1
        for d in DIRS:
            u = (t[0] + d[0], t[1] + d[1])
            if u in net and u not in prev:
                prev[u] = t
                todo.append(u)
    for _, g in tw.p.gates:
        v = g if g in prev else None
        while v is not None:
            for dc in (-1, 0, 1):
                for dr in (-1, 0, 1):
                    u = (v[0] + dc, v[1] + dr)
                    if u in net:
                        tw.p.main.add(u)
            v = prev[v]


def _wall_inside(tw):
    if getattr(tw, "sk_inside", None):
        tw.wall_inside = {t for t in tw.sk_inside if tw.at(t) != "M"}
        return
    _wall_inside_rays(tw)


def _wall_inside_rays(tw):
    """Inside the walls: a tile with wall or water on its row both ways and on its column both ways, and wall in at
    least two of the four directions (the river closes the town on its side)."""
    walls = {t for t in tw.tiles() if tw.at(t) == "M"}
    if not walls:
        return
    inside = set()
    for t in tw.tiles():
        if tw.at(t) in ("M", "w"):
            continue
        hits = 0
        ok = True
        for d in DIRS:
            u = t
            found = ""
            while tw.inside(u):
                u = (u[0] + d[0], u[1] + d[1])
                k = tw.at(u)
                if k == "M" or (k == "" and False):
                    found = "M"
                    break
                if k == "w":
                    found = "w"
                    break
            if not found:
                ok = False
                break
            hits += found == "M"
        if ok and hits >= 2:
            inside.add(t)
    tw.wall_inside = inside


def _towers(tw, sk):
    walls = [t for t in tw.tiles() if tw.at(t) == "M"]
    if not walls:
        return
    tw.wall_ring = walls
    cfg = dict(sk.get("walls", {}))
    size = cfg.get("tower", [2, 2])
    # the gates: the streets where the ring passes (and those opened later), next to the wall
    gates = [t for t in getattr(tw, "sk_gates", set()) | getattr(tw, "sk_opened", set())
             if tw.at(t) in ("=", ",") and any(tw.at((t[0] + d[0], t[1] + d[1])) == "M" for d in DIRS)]
    for g in citylib.groups_of(set(gates)):
        ends = sorted({(t[0] + d[0], t[1] + d[1]) for t in g for d in DIRS if tw.at((t[0] + d[0], t[1] + d[1])) == "M"})
        for e in ends[:1] + ends[-1:]:
            tw._tower(e, size, "gate_tower", cfg)
    every = int(cfg.get("towers_every", 0))
    if every:
        order = tw._ring_order([t for t in tw.tiles() if tw.at(t) == "M"])
        for i, t in enumerate(order):
            if i % every == every // 2:
                tw._tower(t, size, "wall_tower", cfg)


def _max_rect(tiles):
    """The biggest rectangle of tiles all in `tiles` (brute force: the blobs are small)."""
    ts = set(tiles)
    best = None
    cs = [t[0] for t in ts]
    rs = [t[1] for t in ts]
    for r0 in range(min(rs), max(rs) + 1):
        for c0 in range(min(cs), max(cs) + 1):
            if (c0, r0) not in ts:
                continue
            for r1 in range(r0, max(rs) + 1):
                for c1 in range(c0, max(cs) + 1):
                    if not all((c, r) in ts for c in range(c0, c1 + 1) for r in range(r0, r1 + 1)):
                        break
                    a = (c1 - c0 + 1) * (r1 - r0 + 1)
                    if best is None or a > best[0]:
                        best = (a, (c0, r0, c1 - c0 + 1, r1 - r0 + 1))
    return best[1] if best else None


def _drawn_landmarks(tw):
    """The drawing's landmarks, before anything else takes their ground."""
    tw.sk_done = set()
    _landmarks(tw, tw.plan["skeleton"], drawn_only=True)


def _landmarks(tw, sk, drawn_only=False):
    """The drawing's landmarks: each blob of a landmark colour is the landmark of the plan of that type (its height
    and colour): its own biggest rectangle if it is about the plan's size, else the plan's size placed by its
    centre. The plan's landmarks of the types the drawing has not are placed as in the procedural towns."""
    by_type = {}
    for lm in tw.plan.get("landmarks", []):
        by_type.setdefault(lm["type"], []).append(lm)
    done = tw.sk_done
    for typ, tiles in sorted(tw.sk_blobs.items()) if drawn_only else []:
        cap = max(1, len(by_type.get(typ, [])) * max(1, int((by_type.get(typ) or [{}])[0].get("count", 1))))
        for blob in sorted(citylib.groups_of(set(tiles)), key=len, reverse=True)[:cap]:
            spec = dict((by_type.get(typ) or [{"type": typ, "size": [3, 3], "height": 48, "color": "#9a7a5a"}])[0])
            spec.pop("inside_wall", None)  # the drawing already says where it stands
            spec.pop("outside_wall", None)
            free = [t for t in blob if tw.at(t) in (".", "P") and t not in tw.taken and t not in tw.p.reserved
                    and t not in tw.keep]
            want = spec["size"][0] * spec["size"][1]
            rect = _max_rect(free) if free else None
            if rect and rect[2] * rect[3] >= max(2, int(want * 0.5)):
                tw.add_landmark(typ, rect, spec.get("height", 48), spec.get("color", "#9a7a5a"),
                                label=spec.get("label", True))
            else:
                cx = sum(t[0] for t in blob) / len(blob)
                cy = sum(t[1] for t in blob) / len(blob)
                spots = []
                for k in (1.0, 0.8, 0.65):  # its size from the plan, a little smaller if it does not fit
                    size = [max(2, int(round(spec["size"][0] * k))), max(2, int(round(spec["size"][1] * k)))]
                    s = dict(spec, size=size, near=[cx, cy], reach=10, front=spec.get("front", "any"),
                             on=sorted(set(spec.get("on", ["."])) | {".", "P"}))
                    spots = tw.landmark_spots(s)
                    if spots:
                        break
                if not spots:
                    tw.log.append(f"hito {typ} del dibujo: no cabe cerca de ({cx:.0f}, {cy:.0f})")
                    continue
                tw.add_landmark(typ, spots[0][1], spec.get("height", 48), spec.get("color", "#9a7a5a"),
                                label=spec.get("label", True))
            for t in gen._ring(tw.landmarks[-1]["origin"] + tw.landmarks[-1]["size"]):
                if tw.at(t) == ".":
                    tw.p.reserved.add(t)
            done.add(typ)
    if drawn_only:
        return
    tw.plan = dict(tw.plan, landmarks=[lm for lm in tw.plan.get("landmarks", []) if lm["type"] not in done])
    tw.place_landmarks("early")
    tw.place_landmarks("mid")


def _port(tw, sk):
    """Boats by the drawing's piers, rowboats on the river, the crane by the busiest pier."""
    piers = citylib.groups_of({t for t in tw.tiles() if tw.at(t) == "m"})
    bl, bw = sk.get("boat", [4, 2])
    n = int(sk.get("boats", 0))
    mid = tw.w / 2.0
    for g in sorted(piers, key=lambda g: abs(g[0][0] - mid)):
        if n <= 0:
            break
        cs = [t[0] for t in g]
        rs = [t[1] for t in g]
        cands = []
        for (w_, h_) in ((bl, bw), (bw, bl)):
            for c in range(min(cs) - w_ - 1, max(cs) + 2):
                for r in range(min(rs) - h_ - 1, max(rs) + 2):
                    rect = (c, r, w_, h_)
                    ring = gen._ring(rect)
                    if any(u in g for u in ring) and tw._boat_fits(rect):
                        cands.append((abs(c - min(cs)) + abs(r - min(rs)), rect))
        if cands:
            tw.add_boat("ship", sorted(cands)[0][1], sk.get("boat_color", "#6b4a2a"))
            n -= 1
    rb = int(sk.get("rowboats", 0))
    for t in sorted((t for t in tw.tiles() if tw.at(t) == "w"), key=lambda t: (citylib.tile_hash(*t, 21), t)):
        if rb <= 0:
            break
        rect = (t[0], t[1], 2, 1)
        if tw._boat_fits(rect, margin=2):
            tw.add_boat("rowboat", rect, "#7a5a36")
            rb -= 1
    crane = sk.get("crane")
    if crane and piers:
        for g in sorted(piers, key=lambda g: -len(g)):
            root = [(t[0] + d[0], t[1] + d[1]) for t in g for d in DIRS if tw.at((t[0] + d[0], t[1] + d[1])) == "="]
            done = False
            for r0 in sorted(set(root)):
                for d in DIRS:
                    u = (r0[0] + d[0], r0[1] + d[1])
                    side = [(u[0] + e[0], u[1] + e[1]) for e in DIRS]
                    if tw.at(u) == "=" and any(tw.at(s) == "w" for s in side) and \
                            sum(1 for s in side if tw.at(s) in ("=", "P")) >= 3:
                        tw.add_landmark("crane", (u[0], u[1], 1, 1), crane.get("height", 88),
                                        crane.get("color", "#7a5530"))
                        done = True
                        break
                if done:
                    break
            if done:
                break


def _districts(tw, sk):
    """Where the houses go: the drawing's houses and two tiles round them (over open ground), in the district of
    the plan whose `when` fits (inside / outside the walls; dense / loose by how packed the drawing is there)."""
    dists = sk.get("districts", [])
    tw.plan = dict(tw.plan, districts=dists)
    zone = set(tw.sk_houses)
    for _ in range(int(sk.get("reach", 3))):
        grow = set()
        for t in zone:
            for d in DIRS:
                u = (t[0] + d[0], t[1] + d[1])
                if tw.inside(u) and tw.at(u) in (".", "f") and u not in zone and u not in tw.p.reserved:
                    grow.add(u)
        zone |= grow
    rad = float(sk.get("around_plaza", 0))  # and round the plaza (the market took the drawing's houses there)
    if rad:
        pc = (tw.px + gen.PLAZA_W / 2.0, tw.py + gen.PLAZA_H / 2.0)
        zone |= {t for t in tw.tiles() if tw.at(t) in (".", "f") and t not in tw.p.reserved
                 and math.hypot(t[0] - pc[0], t[1] - pc[1]) <= rad}
    for t in zone:  # the fields next to the houses become their gardens (and room for the sim's sites)
        if tw.at(t) == "f":
            tw.put(t, ".")
    for t in zone:
        if tw.at(t) != ".":
            continue
        n = sum(1 for dc in range(-3, 4) for dr in range(-3, 4) if (t[0] + dc, t[1] + dr) in tw.sk_houses)
        packed = n >= 12
        for i, ds in enumerate(dists):
            w = ds.get("when", "any")
            ok = (w == "any" or (w == "inside" and t in tw.wall_inside) or (w == "outside" and t not in tw.wall_inside)
                  or (w == "dense" and packed) or (w == "loose" and not packed))
            if ok:
                tw.district_of[t] = i
                break
    tw.prefer = set(tw.sk_houses)
