"""Plots of a town (docs/gdd/04_diseno_de_juego.md §4.9, §4.9.1): free lots inside and outside the town, ruins and the
NPC businesses, each with its situation (location 0-1), by the rules of tools/city/reglas.json "plots".

  add_plots(d, cat)        puts "plots" in map dict d (replacing any) and takes out of its decor the filler houses
                           that became a lot or a ruin; returns a summary
  validate_plots(m, rep)   the coherence of the plots of a Map (citylib.validate calls it)

The sim never reads plots (H6, buying and building, waits for its Gate): the rows, the sites and the meeting points of
the map do not move, so neither does any target. Free lots and ruins inside the town take filler lots (blocked # tiles
dressed as houses, never a site); free lots outside take open grass beside a road. The view draws a lot as bare ground
with stakes, a ruin as broken walls and a business for sale with a «Se vende» sign (game/world/plot_layer.gd).

A plot: {id, state: lot|ruin|business, side: inside|outside, zone: rustic|production|housing, origin [c, r],
size [w, h], front [c, r] (the walkable tile it is entered from: its door for a business), location 0-1} plus, for a
business, site (the map site, the largest of its plot) and for_sale.
"""
import json
import math

import citylib
from citylib import DIRS

STATES = ("lot", "ruin", "business")
SIDES = ("inside", "outside")
ZONES = ("rustic", "production", "housing")
WORKSHOPS = ("forge", "carpentry", "masonry", "tailor_shop")


def cfg():
    return citylib.rules().get("plots", {})


# --- Situation ------------------------------------------------------------------------------------------------------

def _bfs_dist(m, starts):
    """Steps over walkable tiles (4-neighbourhood) from any of `starts` to every tile reached."""
    dist = {}
    q = []
    for s in starts:
        s = tuple(s)
        if m.walkable(s) and s not in dist:
            dist[s] = 0
            q.append(s)
    i = 0
    while i < len(q):
        t = q[i]
        i += 1
        for d in DIRS:
            v = (t[0] + d[0], t[1] + d[1])
            if v not in dist and m.walkable(v):
                dist[v] = dist[t] + 1
                q.append(v)
    return dist


def _paths_traffic(m, plaza_dist, sources):
    """How many of the walks from `sources` (doors, gates) to the plaza pass by each tile (down the plaza distance)."""
    count = {}
    for s in sources:
        t = tuple(s)
        if t not in plaza_dist:
            continue
        seen = 0
        while plaza_dist.get(t, 0) > 0 and seen < 400:
            count[t] = count.get(t, 0) + 1
            best = None
            for d in DIRS:
                v = (t[0] + d[0], t[1] + d[1])
                if v in plaza_dist and plaza_dist[v] < plaza_dist[t] and (best is None or (v[1], v[0]) < (best[1], best[0])):
                    best = v
            if best is None:
                break
            t = best
            seen += 1
    return count


class Situation:
    """location(front) 0-1: near the plaza, the main street and the gates and where people pass (rules: weights)."""

    def __init__(self, m):
        self.m = m
        c = cfg().get("location", {})
        self.w = c.get("weights", {"plaza": 0.45, "main_street": 0.2, "gate": 0.1, "traffic": 0.25})
        self.main_reach = float(c.get("main_street_reach", 6))
        sp = m.d.get("spawns") or {}
        centre = tuple(sp.get("market", sp.get("player", (m.w // 2, m.h // 2))))
        self.plaza = _bfs_dist(m, [centre])
        self.far = float(max(self.plaza.values()) if self.plaza else 1) or 1.0
        gates = [tuple(v) for k, v in sorted(sp.items()) if k.endswith("_gate")]
        self.gate = _bfs_dist(m, gates) if gates else {}
        self.main = [t for t in m.all_tiles() if m.kind(t) in ("street", "plaza")]
        doors = [s["door"] for _, s in sorted(m.sites.items()) if s["door"]]
        self.traffic = _paths_traffic(m, self.plaza, doors + gates)
        self.peak = float(max(self.traffic.values()) if self.traffic else 1) or 1.0

    def of(self, front):
        f = tuple(front)
        dp = min(1.0, self.plaza.get(f, self.far) / self.far)
        dg = min(1.0, self.gate.get(f, self.far) / self.far) if self.gate else 1.0
        dm = min((max(abs(f[0] - t[0]), abs(f[1] - t[1])) for t in self.main), default=self.main_reach)
        dm = min(1.0, dm / self.main_reach)
        tr = 0
        for dc in (-1, 0, 1):
            for dr in (-1, 0, 1):
                tr = max(tr, self.traffic.get((f[0] + dc, f[1] + dr), 0))
        tr = min(1.0, tr / self.peak)
        v = (self.w["plaza"] * (1 - dp) + self.w["main_street"] * (1 - dm) + self.w["gate"] * (1 - dg)
             + self.w["traffic"] * tr)
        return round(max(0.0, min(1.0, v)), 2)


# --- Inside and outside ---------------------------------------------------------------------------------------------

class Sides:
    """Which tiles are inside the town: with a wall (M tiles), those with wall in at least 3 of the 4 directions; without
    one, those within `inside_reach` tiles of the built town (sites, filler lots, the plaza)."""

    def __init__(self, m):
        self.m = m
        self.walled = any(m.kind(t) == "wall" for t in m.all_tiles())
        reach = int(cfg().get("inside_reach", 2))
        self.near = set()
        if not self.walled:
            built = [t for t in m.all_tiles() if m.kind(t) in ("building", "plaza")]
            for (c, r) in built:
                for dr in range(-reach, reach + 1):
                    for dc in range(-reach, reach + 1):
                        self.near.add((c + dc, r + dr))

    def inside(self, t):
        if not self.walled:
            return tuple(t) in self.near
        hits = 0
        for d in DIRS:
            v = (t[0] + d[0], t[1] + d[1])
            while self.m.inside(v):
                if self.m.kind(v) == "wall":
                    hits += 1
                    break
                v = (v[0] + d[0], v[1] + d[1])
        return hits >= 3

    def side_of(self, rect):
        c, r, w, h = rect
        cells = [(c + i, r + j) for j in range(h) for i in range(w)]
        ins = sum(1 for t in cells if self.inside(t))
        return "inside" if ins * 2 > len(cells) else "outside"


# --- Candidates ------------------------------------------------------------------------------------------------------

def _rect_tiles(rect):
    c, r, w, h = rect
    return [(c + i, r + j) for j in range(h) for i in range(w)]


def _ring(rect, gap):
    c, r, w, h = rect
    out = set()
    for j in range(r - gap, r + h + gap):
        for i in range(c - gap, c + w + gap):
            if not (c <= i < c + w and r <= j < r + h):
                out.add((i, j))
    return out


def _front(m, rect, facing, reachable):
    """The walkable reachable tile the plot is entered from: on its facing side first, then any side (road first)."""
    sides = [tuple(facing)] if facing else []
    sides += [d for d in ((0, 1), (1, 0), (0, -1), (-1, 0)) if d not in sides]
    for roads_only in (True, False):
        for d in sides:
            for t in citylib.front_line(rect, d):
                if t in reachable and (m.is_road(t) or not roads_only):
                    return t
    return None


def _filler_candidates(m, decor, reachable, blocked):
    """Filler houses of the decor (kind house, no site) whose footprint is free filler: a lot or a ruin inside."""
    free = m.free_filler()
    out = []
    for i, it in enumerate(decor):
        if it.get("kind") != "house" or it.get("site"):
            continue
        (c, r), (w, h) = it["at"], it.get("size", [1, 1])
        rect = (c, r, w, h)
        tiles = _rect_tiles(rect)
        if w * h < cfg().get("min_area", 4) or any(t not in free or t in blocked for t in tiles):
            continue
        f = _front(m, rect, it.get("facing"), reachable)
        if f is None:
            continue
        out.append({"rect": rect, "front": f, "decor": i, "kind": "filler"})
    return out


def _grass_candidates(m, reachable, blocked, decor_tiles, kinds, passes):
    """Open-ground rects (tiles of `kinds`, no decor, no protected tile) entered from a reachable tile: a free lot on
    open ground. Passes from strict to loose ({sizes, gap, road}): gap = tiles clear of sites, walls, water and other
    blocks around it; road = its entrance is a road. Each rect once, in the order of the first pass that takes it."""
    out, seen = [], set()
    passes_done = []
    for ps in passes:
        sizes = [tuple(s) for s in ps.get("sizes", [[3, 3]])]
        gap = int(ps.get("gap", 1))
        road = bool(ps.get("road", True))
        for r in range(1, m.h - 1):
            for c in range(1, m.w - 1):
                for (w, h) in sizes:
                    rect = (c, r, w, h)
                    if rect in seen:
                        continue
                    tiles = _rect_tiles(rect)
                    if any(not m.inside(t) or m.kind(t) not in kinds or t in blocked or t in decor_tiles for t in tiles):
                        continue
                    if gap > 0 and any(m.inside(t) and (t in blocked or (not m.walkable(t) and m.kind(t) != "tree"))
                                       for t in _ring(rect, gap)):
                        continue
                    f = _front(m, rect, None, reachable)
                    if f is None or (road and not m.is_road(f)):
                        continue
                    seen.add(rect)
                    out.append({"rect": rect, "front": f, "decor": None, "kind": "grass", "pass": len(passes_done)})
                    break
        passes_done.append(ps)
    return out


def _overlaps(rect, taken):
    tiles = set(_rect_tiles(rect))
    return any(tiles & set(_rect_tiles(o)) or tiles & _ring(o, 1) for o in taken)


def _pick(cands, n, taken, key):
    """Up to n candidates, the strictest pass first (filler lots have none); inside each pass spread over the ranking
    `key` (best, worst, second best...), never touching each other or `taken`."""
    out = []
    for p in sorted({c.get("pass", 0) for c in cands}):
        ranked = sorted((c for c in cands if c.get("pass", 0) == p), key=key)
        order = []
        lo, hi = 0, len(ranked) - 1
        while lo <= hi:
            order.append(lo)
            if hi != lo:
                order.append(hi)
            lo += 1
            hi -= 1
        for i in order:
            if len(out) >= n:
                return out
            cand = ranked[i]
            if _overlaps(cand["rect"], taken + [o["rect"] for o in out]):
                continue
            out.append(cand)
    return out


# --- The plots of a map ----------------------------------------------------------------------------------------------

def plots(d, cat):
    """(plots, decor indices to drop) for map dict d by the rules."""
    m = citylib.Map(d, cat)
    rl = cfg()
    sit = Situation(m)
    sides = Sides(m)
    reachable = set(sit.plaza)
    decor = (d.get("decor") or {}).get("items", [])
    blocked = set(m.protected()) | set(m.site_tiles())
    for _, _, tile, svc in m.services():
        blocked |= {tile, svc}
    for p in d.get("patrols") or []:
        blocked |= {tuple(t) for t in p.get("tiles", [])}
    blocked |= {t for t in citylib._decor_tiles(d)} - m.free_filler()
    for lm in d.get("landmarks") or []:
        blocked |= set(_rect_tiles((lm["origin"][0], lm["origin"][1], lm["size"][0], lm["size"][1])))
    filler = _filler_candidates(m, decor, reachable, blocked - m.free_filler())
    for f in filler:
        f["side"] = sides.side_of(f["rect"])
        f["location"] = sit.of(f["front"])
    passes = rl.get("passes", [{"sizes": [[3, 3], [3, 2], [2, 3]], "gap": 1, "road": True},
                               {"sizes": [[3, 3], [3, 2], [2, 3], [2, 2]], "gap": 0, "road": True},
                               {"sizes": [[3, 2], [2, 3], [2, 2]], "gap": 0, "road": False}])
    decor_tiles = citylib._decor_tiles(d)
    grass = _grass_candidates(m, reachable, blocked, decor_tiles, ("grass", "field"), passes)
    for g in grass:
        g["side"] = sides.side_of(g["rect"])
        g["location"] = sit.of(g["front"])
        g["field"] = any(m.kind(t) == "field" for t in _rect_tiles(g["rect"]))
    grass = [g for g in grass if not (g["field"] and g["side"] == "inside")]
    n_ruins = max(1, min(3, int(rl.get("ruins", 2))))
    n_in = max(2, int(rl.get("lots_inside", 3)))
    n_out = max(2, int(rl.get("lots_outside", 3)))
    taken = []
    ins = [f for f in filler if f["side"] == "inside"]
    # ruins: the best-located filler lot inside (the bargain on the main street) and then spread down the ranking
    ruins = _pick(ins, n_ruins, taken, key=lambda f: (-f["location"], f["rect"][1], f["rect"][0]))
    if not ruins:  # no filler lot inside (Montsacre: the burgh is outside the precinct's wall): one outside
        ruins = _pick(filler, 1, taken, key=lambda f: (-f["location"], f["rect"][1], f["rect"][0]))
    if not ruins:  # no filler lot at all: the walls of a ruin on open ground, the best-located strict one
        ruins = _pick([g for g in grass if g.get("pass", 0) == 0 and not g["field"]], 1, taken,
                      key=lambda g: (-g["location"], g["rect"][1], g["rect"][0]))
    taken += [x["rect"] for x in ruins]
    lots_in = _pick([f for f in ins if f not in ruins], n_in, taken,
                    key=lambda f: (-f["location"], f["rect"][1], f["rect"][0]))
    if len(lots_in) < n_in:  # a town with few filler lots inside: open grass inside the town
        lots_in += _pick([g for g in grass if g["side"] == "inside"], n_in - len(lots_in),
                         taken + [x["rect"] for x in lots_in], key=lambda g: (-g["location"], g["rect"][1], g["rect"][0]))
    taken += [x["rect"] for x in lots_in]
    outs = [g for g in grass if g["side"] == "outside"]
    # outside: the rustic ones far from the town first, then one in the arrabal (the nearest)
    lots_out = _pick(outs, n_out, taken, key=lambda g: (g["location"], g["rect"][1], g["rect"][0]))
    taken += [x["rect"] for x in lots_out]
    out = []

    def add(c, state, zone):
        x, y, w, h = c["rect"]
        out.append({"id": "", "state": state, "side": c["side"], "zone": zone, "origin": [x, y], "size": [w, h],
                    "front": list(c["front"]), "location": c["location"]})

    # zones (the valve of 4.9: at least `valve` free plots of each): the free plots inside, best-located first, are
    # production then housing; the ones outside are rustic, the best-located of them housing (the arrabal) when the
    # inside left housing short and the rustic ones keep their valve
    valve = int(rl.get("valve", 2))
    inside_free = sorted(ruins + lots_in, key=lambda c: (-c["location"], c["rect"][1], c["rect"][0]))
    n = len(inside_free)
    n_prod = min(n, max(valve, (n + 1) // 2))
    if n - n_prod < valve:
        n_prod = max(min(valve, n), n - valve)
    zone_of = {id(c): ("production" if i < n_prod else "housing") for i, c in enumerate(inside_free)}
    for c in ruins:
        add(c, "ruin", zone_of[id(c)])
    for c in lots_in:
        add(c, "lot", zone_of[id(c)])
    housing = n - n_prod
    lots_out_sorted = sorted(lots_out, key=lambda g: (-g["location"], g["rect"][1], g["rect"][0]))
    for i, c in enumerate(lots_out_sorted):
        rustic_after = len(lots_out_sorted) - i - 1
        if housing < valve and rustic_after >= valve:
            add(c, "lot", "housing")
            housing += 1
        else:
            add(c, "lot", "rustic")
    # the NPC businesses: every workshop and house site (the largest of its plot), its door the front
    biz = []
    for sid, s in sorted(m.sites.items()):
        if sid in m.alt_of or s["type"] == "town_hall" or not s["door"]:
            continue
        b = (d.get("buildings") or {}).get(sid, {})
        if str(b.get("owner", "-")) == "":
            continue  # a public building (the armory): nobody's to sell
        if s["type"] not in WORKSHOPS and s["type"] != "house":
            continue
        (x, y), (w, h) = s["origin"], s["footprint"]
        biz.append({"id": "", "state": "business", "side": sides.side_of((x, y, w, h)),
                    "zone": "production" if s["type"] in WORKSHOPS else "housing", "origin": [x, y], "size": [w, h],
                    "front": list(s["door"]), "location": sit.of(s["door"]), "site": sid, "for_sale": False})
    keep = set(rl.get("never_for_sale", ["player_forge", "rival_forge"]))
    sale = sorted((b for b in biz if b["zone"] == "production" and b["site"] not in keep),
                  key=lambda b: (-b["location"], b["site"]))[: int(rl.get("for_sale", 2))]
    for b in sale:
        b["for_sale"] = True
    out += biz
    order = {"ruin": 0, "lot": 1, "business": 2}
    out.sort(key=lambda p: (order[p["state"]], p["side"], -p["location"], p["origin"][1], p["origin"][0]))
    for i, p in enumerate(out):
        p["id"] = "plot_%02d" % (i + 1)
    drop = {c["decor"] for c in ruins + lots_in if c["decor"] is not None}
    return out, drop


def add_plots(d, cat):
    """Puts the plots in map dict d and takes out of its decor the filler houses they replace. Returns a summary."""
    ps, drop = plots(d, cat)
    d["plots"] = ps
    if drop and d.get("decor"):
        d["decor"]["items"] = [it for i, it in enumerate(d["decor"]["items"]) if i not in drop]
    return summary(ps)


def summary(ps):
    s = {}
    for p in ps:
        k = p["state"] if p["state"] != "lot" else "lot_" + p["side"]
        s[k] = s.get(k, 0) + 1
    s["for_sale"] = sum(1 for p in ps if p.get("for_sale"))
    return s


# --- Validation ------------------------------------------------------------------------------------------------------

def validate_plots(m, rep, required=False):
    """Coherence of m.d["plots"] (rep: citylib.Report). required: a town of the six (rules plots.maps)."""
    ps = m.d.get("plots")
    if ps is None:
        if required:
            rep.error("plots: el mapa no tiene parcelas (python3 tools/city/ciudad.py parcelas %s)" % m.d.get("id", ""))
        return
    rl = cfg()
    sides = Sides(m)
    sit = Situation(m)
    reach = set(sit.plaza)
    owned = m.site_tiles()
    prot = m.protected()
    free = m.free_filler()
    decor_lots = set()
    for it in (m.d.get("decor") or {}).get("items", []):
        if it.get("kind") in ("house", "yard", "single") and not it.get("site"):
            decor_lots |= set(_rect_tiles((it["at"][0], it["at"][1]) + tuple(it.get("size", [1, 1]))))
    seen_ids, seen_tiles = set(), {}
    counts = {"lot_inside": 0, "lot_outside": 0, "ruin": 0}
    free_zone = {z: 0 for z in ZONES}
    for i, p in enumerate(ps):
        w = "plots[%d] %s" % (i, p.get("id", "?"))
        pid = str(p.get("id", ""))
        if not pid or pid in seen_ids:
            rep.error(f"{w}: id vacío o repetido")
        seen_ids.add(pid)
        st, side, zone = p.get("state"), p.get("side"), p.get("zone")
        if st not in STATES or side not in SIDES or zone not in ZONES:
            rep.error(f"{w}: state {st}, side {side} o zone {zone} desconocidos")
            continue
        loc = p.get("location")
        if not isinstance(loc, (int, float)) or not 0 <= loc <= 1:
            rep.error(f"{w}: location {loc} fuera de [0, 1]")
        o, sz, fr = p.get("origin", []), p.get("size", []), p.get("front", [])
        if len(o) != 2 or len(sz) != 2 or len(fr) != 2 or sz[0] < 1 or sz[1] < 1:
            rep.error(f"{w}: origin, size y front son [c, r]")
            continue
        rect = (o[0], o[1], sz[0], sz[1])
        tiles = _rect_tiles(rect)
        if any(not m.inside(t) for t in tiles):
            rep.error(f"{w}: se sale del mapa")
            continue
        if tuple(fr) not in reach:
            rep.error(f"{w}: la entrada {fr} no se alcanza desde la plaza")
        if sides.side_of(rect) != side:
            rep.error(f"{w}: dice {side} y está {sides.side_of(rect)}")
        if st == "business":
            sid = p.get("site", "")
            s = m.sites.get(sid)
            if s is None:
                rep.error(f"{w}: el solar {sid} no es un edificio del mapa")
            elif list(s["origin"]) != list(o) or list(s["footprint"]) != list(sz) or list(s["door"] or []) != list(fr):
                rep.error(f"{w}: origin, size o front no son los del solar {sid}")
            if not isinstance(p.get("for_sale"), bool):
                rep.error(f"{w}: for_sale es true o false")
            if zone == "rustic":
                rep.error(f"{w}: un negocio de la villa no es rústico")
            continue
        counts["ruin" if st == "ruin" else "lot_" + side] += 1
        free_zone[zone] += 1
        if zone == "rustic" and side != "outside":
            rep.error(f"{w}: una parcela rústica va fuera")
        if st == "ruin" and any(t not in free for t in tiles) and any(m.kind(t) != "grass" for t in tiles):
            rep.error(f"{w}: una ruina va en un solar de relleno (#) que no es de ningún edificio, o en hierba")
        for t in tiles:
            k = m.kind(t)
            if t in owned:
                rep.error(f"{w}: pisa el edificio {owned[t]} en {t}")
            elif t in prot:
                rep.error(f"{w}: pisa {prot[t]} en {t}")
            elif k not in ("building", "grass", "field") or (k == "building" and t not in free) or \
                    (k == "field" and side != "outside"):
                rep.error(f"{w}: {t} es {k}: un solar va en hierba, en un campo (fuera) o en un solar de relleno")
            if t in decor_lots:
                rep.error(f"{w}: la decoración tiene una casa de relleno en {t} (se dibujaría encima)")
            if t in seen_tiles:
                rep.error(f"{w}: se solapa con {seen_tiles[t]} en {t}")
            seen_tiles[t] = pid
    if required:
        mi = int(rl.get("min_inside", 2))
        mo = int(rl.get("min_outside", 2))
        if counts["lot_inside"] < mi:
            rep.error(f"plots: {counts['lot_inside']} solares dentro (mínimo {mi}, 4.9.1)")
        if counts["lot_outside"] < mo:
            rep.error(f"plots: {counts['lot_outside']} solares fuera (mínimo {mo}, 4.9.1)")
        if not 1 <= counts["ruin"] <= 3:
            rep.error(f"plots: {counts['ruin']} ruinas (de 1 a 3, 4.9.1)")
        valve = int(rl.get("valve", 2))
        for z, n in free_zone.items():
            if n < valve:
                rep.error(f"plots: {n} parcelas libres {z} (la válvula de 4.9 pide {valve} de cada tipo)")
    rep.note("parcelas: %s; libres por tipo %s" % (json.dumps(summary(ps)), json.dumps(free_zone)))
