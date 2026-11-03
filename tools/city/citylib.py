"""Town builder library (docs/protocolos/generar-ciudad.md): the map model, the dressing rules (filler houses facing
the street, yards behind, lanterns, workshop props, carts, benches, fences) and the coherence validator.

Pure Python, no engine: the same code dresses town_e, dresses the generated towns and checks them. Deterministic: the
order of every loop is fixed and the only "random" source is tile_hash (same map, same decor).

Iso convention (game/iso.gd): tile (col, row) -> pixel ((col - row) * 32, (col + row) * 16). On screen the camera
sees the faces of a building that look to +row (lower-left face) and to +col (lower-right face); the -row and -col
faces are hidden behind it.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "data")
RULES_PATH = os.path.join(ROOT, "tools", "city", "reglas.json")

DIRS = [(0, 1), (1, 0), (0, -1), (-1, 0)]  # +row, +col, -row, -col
VISIBLE = {(0, 1), (1, 0)}
ROAD_KINDS = ("street", "plaza", "dirt", "bridge")
PATH_KINDS = ("street", "dirt", "bridge")  # nothing of the decor may stand on these ("camino")


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def rules():
    return load_json(RULES_PATH)


def tile_hash(c, r, salt=0):
    """A well-mixed number from a tile (neighbours get unrelated values), always >= 0."""
    h = (c * 374761393 + r * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return h % 1000003


def _i64(x):
    x &= 0xFFFFFFFFFFFFFFFF
    return x - (1 << 64) if x >> 63 else x


def gd_tile_hash(c, r):
    """WorldView._tile_hash (GDScript, 64-bit ints): which look of a building type a site gets."""
    h = _i64(c * 374761393 + r * 668265263)
    h = _i64((h ^ (h >> 13)) * 1274126177)
    h = h ^ (h >> 16)
    return abs(h) % 1000003


def building_scene(cat, site):
    """The scene WorldView draws for a site (data/view.json building_variants) and the one it uses for its door
    side (building_door_face, <scene>_back): (scene, drawn scene, flip, door side)."""
    scene = site["type"]
    looks = cat.view.get("building_variants", {}).get(scene)
    if isinstance(looks, list) and looks:
        scene = looks[gd_tile_hash(*site["origin"]) % len(looks)]
    d = site["door"]
    side = None
    if d:
        for dd in DIRS:
            if (d[0] - dd[0], d[1] - dd[1]) in site["tiles"]:
                side = dd
                break
    faces = cat.view.get("building_door_face", {}).get("faces", {})
    face = faces.get(scene, faces.get(site["type"], "row"))
    drawn = (0, 1) if face == "row" else (1, 0)
    if side is None:
        return scene, scene, False, side
    if side in VISIBLE:
        no_mirror = cat.view.get("building_door_face", {}).get("no_mirror", [])
        if side != drawn and (scene in no_mirror or site["type"] in no_mirror):
            return scene, scene, None, side  # it would need mirroring and must not be: the drawn door looks away
        return scene, scene, side != drawn, side
    back = scene + "_back"
    if os.path.exists(os.path.join(ROOT, "game", "visuals", "buildings", back + ".tscn")):
        return scene, back, side != (-drawn[0], -drawn[1]), side
    return scene, scene, False, side


def to_world(c, r):
    return ((c - r) * 32.0, (c + r) * 16.0)


def to_tile(x, y):
    col = x / 64.0 + y / 32.0
    row = y / 32.0 - x / 64.0
    return (int(round(col)), int(round(row)))


class Catalog:
    """The bits of data/ the builder reads: tile kinds and building footprints."""

    def __init__(self):
        t = load_json(os.path.join(DATA, "tiles.json"))["tiles"]
        self.kind_of = {v["char"]: k for k, v in t.items()}
        self.char_of = {k: v["char"] for k, v in t.items()}
        self.walk = {k: v.get("walk_cost") for k, v in t.items()}
        self.footprints = {}
        bdir = os.path.join(DATA, "buildings")
        for f in sorted(os.listdir(bdir)):
            if f.endswith(".json") and not f.startswith("_"):
                b = load_json(os.path.join(bdir, f))
                self.footprints[b["id"]] = tuple(b.get("footprint", [1, 1]))
        self.view = load_json(os.path.join(DATA, "view.json"))
        self.town = load_json(os.path.join(DATA, "town.json"))


class Map:
    """A data/maps/<id>.json with helpers. Tiles are (col, row)."""

    def __init__(self, data, cat):
        self.d = data
        self.cat = cat
        self.rows = data["rows"]
        self.h = len(self.rows)
        self.w = len(self.rows[0]) if self.rows else 0
        self.sites = {}  # site id -> {"type", "tiles": set, "door": (c, r) | None}
        for sid, b in sorted((data.get("buildings") or {}).items()):
            fw, fh = cat.footprints.get(b["type"], (1, 1))
            o = b["origin"]
            tiles = {(o[0] + dc, o[1] + dr) for dr in range(fh) for dc in range(fw)}
            self.sites[sid] = {"type": b["type"], "tiles": tiles, "door": tuple(b["door"]) if b.get("door") else None,
                               "origin": tuple(o), "footprint": (fw, fh)}
        th = data.get("town_hall") or {}
        if th:
            o, f = th["origin"], th["footprint"]
            self.sites["town_hall"] = {"type": "town_hall", "door": tuple(th["service"]), "origin": tuple(o),
                                       "footprint": tuple(f),
                                       "tiles": {(o[0] + dc, o[1] + dr) for dr in range(f[1]) for dc in range(f[0])}}

    def inside(self, t):
        return 0 <= t[0] < self.w and 0 <= t[1] < self.h

    def kind(self, t):
        if not self.inside(t):
            return ""
        return self.cat.kind_of.get(self.rows[t[1]][t[0]], "")

    def walkable(self, t):
        k = self.kind(t)
        return k != "" and self.cat.walk.get(k) is not None

    def is_road(self, t):
        return self.kind(t) in ROAD_KINDS

    def is_path(self, t):
        return self.kind(t) in PATH_KINDS

    def all_tiles(self):
        for r in range(self.h):
            for c in range(self.w):
                yield (c, r)

    def site_tiles(self):
        out = {}
        for sid, s in self.sites.items():
            for t in s["tiles"]:
                out[t] = sid
        return out

    def doors(self):
        return {s["door"]: sid for sid, s in self.sites.items() if s["door"]}

    def services(self):
        """[(kind, id, tile, service)] of the stalls, the board and the town hall."""
        out = []
        for sid, s in sorted((self.d.get("stalls") or {}).items()):
            out.append(("stall", sid, tuple(s["tile"]), tuple(s["service"])))
        b = self.d.get("board") or {}
        if b:
            out.append(("board", "board", tuple(b["tile"]), tuple(b["service"])))
        th = self.d.get("town_hall") or {}
        if th:
            out.append(("town_hall", "town_hall", tuple(th["tile"]), tuple(th["service"])))
        return out

    def protected(self):
        """Tiles no decor may stand on: doors, service, stall and board tiles, social seats, spawns, workplaces."""
        p = {}
        for t, sid in self.doors().items():
            p[t] = "puerta de " + sid
        for kind, sid, tile, svc in self.services():
            p[tile] = f"{kind} {sid}"
            p[svc] = f"servicio de {sid}"
        for sp in self.d.get("social_points") or []:
            for s in sp.get("slots", []):
                p[tuple(s)] = "punto social " + sp["id"]
        for name, s in (self.d.get("spawns") or {}).items():
            p[tuple(s)] = "spawn " + name
        for w in self.d.get("workplaces") or []:
            p[tuple(w["tile"])] = "oficio " + w["id"]
        return p

    def free_filler(self):
        """The building tiles (#) no site of the map owns: what the filler dresses."""
        owned = self.site_tiles()
        stall_tiles = {tile for _, _, tile, _ in self.services()}
        return {t for t in self.all_tiles() if self.kind(t) == "building" and t not in owned and t not in stall_tiles}


def groups_of(tiles):
    """Connected groups (4-neighbourhood) of a set of tiles, each sorted in reading order; groups in reading order."""
    seen, out = set(), []
    for t in sorted(tiles, key=lambda t: (t[1], t[0])):
        if t in seen:
            continue
        g, stack = [], [t]
        seen.add(t)
        while stack:
            u = stack.pop()
            g.append(u)
            for d in DIRS:
                v = (u[0] + d[0], u[1] + d[1])
                if v in tiles and v not in seen:
                    seen.add(v)
                    stack.append(v)
        out.append(sorted(g, key=lambda t: (t[1], t[0])))
    return out


def front_line(lot, d):
    """The tiles just outside the w x h lot (c, r, w, h) on side d."""
    c, r, w, h = lot
    if d == (0, 1):
        return [(c + i, r + h) for i in range(w)]
    if d == (0, -1):
        return [(c + i, r - 1) for i in range(w)]
    if d == (1, 0):
        return [(c + w, r + i) for i in range(h)]
    return [(c - 1, r + i) for i in range(h)]


def road_reach(m, start, d, reach, block):
    """Steps from `start` (the first tile out of a lot) along d until a road, through open ground (not the block,
    not a site, not water); None if no road within `reach` steps."""
    t = start
    owned = m._owned if hasattr(m, "_owned") else m.site_tiles()
    for k in range(1, reach + 1):
        if not m.inside(t) or t in block or t in owned:
            return None
        if m.is_road(t):
            return k
        if m.kind(t) in ("water", "tree", "stall", "board", "building"):
            return None
        t = (t[0] + d[0], t[1] + d[1])
    return None


def lot_facing(m, lot, block, reach):
    """The best side of a lot for its door: (score, d, dist, road kind) or None if no side gives to a road."""
    best = None
    rank = {"street": 3, "plaza": 2, "bridge": 2, "dirt": 1}
    for d in DIRS:
        dists = []
        kinds = []
        for t in front_line(lot, d):
            k = road_reach(m, t, d, reach, block)
            if k is not None:
                dists.append(k)
                end = (t[0] + d[0] * (k - 1), t[1] + d[1] * (k - 1))
                kinds.append(rank.get(m.kind(end), 0))
        need = max(2, (lot[2] if d[1] else lot[3]) - 1)
        if len(dists) < need:
            continue
        score = len(dists) * 100 - min(dists) * 20 + max(kinds) * 5 + (1 if d in VISIBLE else 0)
        cand = (score, d, min(dists), max(kinds))
        if best is None or cand[0] > best[0]:
            best = cand
    return best


def house_scene(base, d, rl):
    """Scene id and mirror for a filler house whose door looks to d (docs: 4 orientations from 2 sprites)."""
    back = rl["filler"]["back"].get(base, "")
    if d == (0, 1):
        return base, False
    if d == (1, 0):
        return base, True
    if d == (0, -1):
        return (back or base), False
    return (back or base), True


def dress(m, rl=None):
    """The decor of a map by rules: returns {"_doc", "items": [...]} (data/maps "decor", read by WorldView)."""
    rl = rl or rules()
    m._owned = m.site_tiles()
    items = []
    used = {}  # tile -> item index (lots, props)
    free = m.free_filler()
    prot = m.protected()
    fcfg = m.cat.view.get("filler", {})
    houses = list(fcfg.get("houses", []))
    themes = fcfg.get("yard_themes", [])
    single = fcfg.get("single", "")
    lw, lh = rl["filler"]["lot"]
    reach = rl["filler"]["street_reach"]
    placed = []  # (lot, base)
    for gi, group in enumerate(groups_of(free)):
        block = set(group)
        if len(group) == 1 and single:
            t = group[0]
            items.append({"kind": "single", "id": single, "at": list(t)})
            used[t] = len(items) - 1
            block.clear()
            continue
        left = set(group)
        while True:
            best = None
            for t in group:
                for (w, h) in ((lw, lh),):
                    lot = (t[0], t[1], w, h)
                    tiles = [(t[0] + dc, t[1] + dr) for dr in range(h) for dc in range(w)]
                    if not all(u in left for u in tiles):
                        continue
                    f = lot_facing(m, lot, block, reach)
                    if f is None:
                        continue
                    key = (f[0], -t[1], -t[0])
                    if best is None or key > best[0]:
                        best = (key, lot, tiles, f)
            if best is None:
                break
            _, lot, tiles, f = best
            for u in tiles:
                left.discard(u)
            k = tile_hash(lot[0], lot[1]) % len(houses)
            touching = {b for (pl, b) in placed if _touch(pl, lot)}
            for _ in range(len(houses)):
                if houses[k] not in touching:
                    break
                k = (k + 1) % len(houses)
            base = houses[k]
            placed.append((lot, base))
            sid, flip = house_scene(base, f[1], rl)
            items.append({"kind": "house", "id": sid, "at": [lot[0], lot[1]], "size": [lot[2], lot[3]], "flip": flip,
                          "facing": list(f[1])})
            for u in tiles:
                used[u] = len(items) - 1
        # yards: what is left of the block (behind or beside the houses), one theme per block
        if themes and left:
            theme = themes[tile_hash(group[0][0] * 3 + 1, group[0][1] * 3 + 7) % len(themes)]
            seen_y = set()
            for t in sorted(left, key=lambda t: (t[1], t[0])):
                y = theme[tile_hash(*t) % len(theme)]
                if y in seen_y:
                    y = theme[0]
                seen_y.add(y)
                items.append({"kind": "yard", "id": y, "at": list(t)})
                used[t] = len(items) - 1
    yard_tiles = {tuple(it["at"]) for it in items if it["kind"] == "yard"}

    def open_spot(t, allow_yard=True, allow_plaza=False, allow_site=False):
        if not m.inside(t) or t in prot:
            return False
        if t in used and not (allow_yard and t in yard_tiles):
            return False
        if t in m._owned and not allow_site:
            return False
        k = m.kind(t)
        if k == "grass":
            return True
        if k == "building" and t in yard_tiles and allow_yard:
            return True
        if k == "plaza" and allow_plaza:
            return True
        if k == "building" and allow_site and t in m._owned:
            return True
        return False

    props = []  # (tile, item)

    def add_prop(kind, sid, t, toward=None, frac=0.0, flip=False):
        off = [0, 0]
        if toward is not None:
            a, b = to_world(*t), to_world(*toward)
            off = [round((b[0] - a[0]) * frac), round((b[1] - a[1]) * frac)]
        it = {"kind": kind, "id": sid, "at": list(t)}
        if off != [0, 0]:
            it["off"] = off
        if flip:
            it["flip"] = True
        items.append(it)
        props.append(t)
        if t not in used:
            used[t] = len(items) - 1
        return it

    doors = m.doors()
    near_door = set()
    for d0 in doors:
        for dc in (-1, 0, 1):
            for dr in (-1, 0, 1):
                near_door.add((d0[0] + dc, d0[1] + dr))
    # 1. lanterns along the main streets and at the crossings
    lcfg = rl["lanterns"]
    every = lcfg["every"]
    streets = [t for t in m.all_tiles() if m.kind(t) in lcfg["streets"]]

    def crossing(t):
        h = any(m.is_road((t[0] + dx, t[1])) for dx in (-1, 1))
        v = any(m.is_road((t[0], t[1] + dy)) for dy in (-1, 1))
        hs = sum(1 for dx in (-1, 1) if m.kind((t[0] + dx, t[1])) in lcfg["streets"])
        vs = sum(1 for dy in (-1, 1) if m.kind((t[0], t[1] + dy)) in lcfg["streets"])
        return h and v and (hs + vs) >= 3

    order = sorted(streets, key=lambda t: (0 if crossing(t) else 1, t[1], t[0]))
    anchors = []
    for s in order:
        if any(abs(s[0] - a[0]) + abs(s[1] - a[1]) < every for a in anchors):
            continue
        spot = None
        for d in sorted(DIRS, key=lambda d: (0 if d in VISIBLE else 1, d)):
            t = (s[0] + d[0], s[1] + d[1])
            if t in near_door or t in props:
                continue
            if open_spot(t, allow_yard=True) and not m.is_road(t):
                spot = t
                break
        if spot is None:
            continue
        anchors.append(s)
        add_prop("lantern", lcfg["id"], spot, toward=s, frac=lcfg["curb"])
    # 2. barrels and crates by the doors of the workshops
    wcfg = rl["workshops"]
    for sid, s in sorted(m.sites.items()):
        kinds = wcfg["props"].get(s["type"])
        if not kinds or not s["door"]:
            continue
        door = s["door"]
        inner = next(((door[0] + d[0], door[1] + d[1]) for d in DIRS if (door[0] + d[0], door[1] + d[1]) in s["tiles"]),
                     None)
        if inner is None:
            continue
        out_d = (door[0] - inner[0], door[1] - inner[1])
        perp = (out_d[1], out_d[0])
        cands = []
        if out_d in VISIBLE:  # against the wall, beside the door: the footprint's edge tiles, pushed to the street
            for sgn in (1, -1):
                t = (inner[0] + perp[0] * sgn, inner[1] + perp[1] * sgn)
                if t in s["tiles"]:
                    cands.append((t, (t[0] + out_d[0], t[1] + out_d[1]), wcfg["wall"]))
        for d in DIRS + [(1, 1), (-1, -1), (1, -1), (-1, 1)]:
            t = (door[0] + d[0], door[1] + d[1])
            if t not in s["tiles"]:
                cands.append((t, None, 0.0))
        n = 0
        for t, toward, frac in cands:
            if n >= len(kinds):
                break
            if t in props or t in prot:
                continue
            if toward is not None:
                if t in used and t not in yard_tiles:
                    continue
            elif not open_spot(t, allow_yard=True):
                continue
            add_prop("prop", kinds[n], t, toward=toward, frac=frac)
            n += 1
    # 3. a cart by each market stall (behind or beside it, never in front of its service tile)
    scfg = rl["stalls"]
    for kind, sid, tile, svc in m.services():
        if kind != "stall":
            continue
        back = (2 * tile[0] - svc[0], 2 * tile[1] - svc[1])
        cands = [back] + [(tile[0] + dc, tile[1] + dr) for dr in (-1, 0, 1) for dc in (-1, 0, 1)]
        for t in cands:
            if t == tile or t in props or abs(t[0] - svc[0]) + abs(t[1] - svc[1]) <= 1:
                continue
            if any(abs(t[0] - p[0]) + abs(t[1] - p[1]) <= 1 for p in props):
                continue
            if open_spot(t, allow_yard=True, allow_plaza=True) and not _near_service(m, t):
                add_prop("prop", scfg["props"].get(sid, scfg["default"]), t)
                break
    # 4. benches on the edge of the plaza (backs to the houses), spaced
    bcfg = rl["plaza_benches"]
    seats = []
    edge = []
    for t in m.all_tiles():
        if m.kind(t) != "plaza":
            continue
        for d in DIRS:
            nb = (t[0] + d[0], t[1] + d[1])
            if m.inside(nb) and not m.is_road(nb):
                edge.append((t, d))
                break
    edge.sort(key=lambda e: (tile_hash(e[0][0], e[0][1], 5), e[0]))
    for t, d in edge:
        if len(seats) >= bcfg["count"]:
            break
        if t in props or t in prot or _near_service(m, t) or t in near_door:
            continue
        if any(abs(t[0] - s[0]) + abs(t[1] - s[1]) < bcfg["spacing"] for s in seats + props):
            continue
        if not open_spot(t, allow_yard=False, allow_plaza=True):
            continue
        seats.append(t)
        add_prop("prop", bcfg["id"], t, toward=(t[0] + d[0], t[1] + d[1]), frac=bcfg["edge"], flip=d[0] == 0)
    # 5. fences round the fields (a gate on the trades' tiles and every few tiles along a road)
    fcfg2 = rl["fences"]
    work_tiles = {tuple(w["tile"]) for w in m.d.get("workplaces") or []}
    run = 0
    for t in m.all_tiles():
        if m.kind(t) != "field" or t in work_tiles or t in prot:
            continue
        for d in DIRS:
            nb = (t[0] + d[0], t[1] + d[1])
            nk = m.kind(nb)
            if nk in ("field", "water", "") or nb in work_tiles:
                continue
            if m.is_road(nb):
                run += 1
                if run % fcfg2["gate_every"] == 0:
                    continue
            # the fence id is drawn "\" (an edge between rows); the edges between cols are mirrored
            it = {"kind": "fence", "id": fcfg2["id"], "at": list(t)}
            a, b = to_world(*t), to_world(*nb)
            it["off"] = [round((b[0] - a[0]) * fcfg2["edge"]), round((b[1] - a[1]) * fcfg2["edge"])]
            if d[1] == 0:
                it["flip"] = True
            items.append(it)
    return {"_doc": rl["_decor_doc"], "items": items}


def _touch(a, b):
    """Two lots (c, r, w, h) that share an edge or overlap."""
    return not (a[0] + a[2] < b[0] or b[0] + b[2] < a[0] or a[1] + a[3] < b[1] or b[1] + b[3] < a[1])


def _near_service(m, t):
    for kind, sid, tile, svc in m.services():
        if abs(t[0] - svc[0]) + abs(t[1] - svc[1]) <= 1:
            return True
    return False


# --- validator -----------------------------------------------------------------------------------------------------

class Report:
    def __init__(self, map_id):
        self.map_id = map_id
        self.errors = []
        self.warnings = []
        self.info = []

    def error(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)

    def note(self, msg):
        self.info.append(msg)


def bfs(m, start):
    seen = {start}
    q = [start]
    while q:
        t = q.pop()
        for d in DIRS:
            v = (t[0] + d[0], t[1] + d[1])
            if v not in seen and m.walkable(v):
                seen.add(v)
                q.append(v)
    return seen


DOOR_FACE = None


def door_faces(cat):
    """Which face of each building scene carries the drawn door: "row" (lower-left, default) or "col"."""
    return cat.view.get("building_door_face", {}).get("faces", {})


def validate(m, strict=False, hand_decor=None):
    """Coherence of a map (docs/protocolos/generar-ciudad.md §Reglas). strict: the generated towns, where every
    rule is an error; town_e (hand-made, the targets depend on it) gets the old-layout ones as warnings."""
    rep = Report(m.d.get("id", "?"))
    rl = rules()
    soft = rep.warn if not strict else rep.error
    owned = m.site_tiles()
    # sites: inside, on building tiles, no overlap
    seen = {}
    for sid, s in sorted(m.sites.items()):
        for t in sorted(s["tiles"]):
            if not m.inside(t):
                rep.error(f"{sid}: casilla {t} fuera del mapa")
            elif m.kind(t) != "building":
                rep.error(f"{sid}: casilla {t} de la huella no es de edificio ({m.kind(t)})")
            if t in seen:
                rep.error(f"{sid} se solapa con {seen[t]} en {t}")
            seen[t] = sid
    for kind, sid, tile, svc in m.services():
        if kind != "town_hall" and tile in seen:
            rep.error(f"{kind} {sid} en {tile} encima de {seen[tile]}")
    # doors give to a walkable tile next to the footprint, on a street
    faces = door_faces(m.cat)
    for sid, s in sorted(m.sites.items()):
        d = s["door"]
        if d is None:
            continue
        if not m.walkable(d):
            rep.error(f"{sid}: la puerta {d} da a una casilla no transitable ({m.kind(d)})")
            continue
        inner = [(d[0] + dd[0], d[1] + dd[1]) for dd in DIRS if (d[0] + dd[0], d[1] + dd[1]) in s["tiles"]]
        if not inner:
            rep.error(f"{sid}: la puerta {d} no toca la huella")
            continue
        if not (m.is_road(d) or any(m.is_road((d[0] + dd[0], d[1] + dd[1])) for dd in DIRS)):
            soft(f"{sid}: la puerta {d} no da a una calle ni a un camino ({m.kind(d)})")
        if sid == "town_hall":
            scene, drawn, flip, out_d = "town_hall", "town_hall", False, (d[0] - inner[0][0], d[1] - inner[0][1])
        else:
            scene, drawn, flip, out_d = building_scene(m.cat, s)
        face = faces.get(scene, faces.get(s["type"], "row"))
        if flip is None:
            soft(f"{sid} ({scene}): la puerta {d} da hacia {_dir_name(out_d)} y su sprite (con texto, no se refleja) "
                 f"la dibuja en la otra cara visible")
        elif out_d not in VISIBLE and drawn == scene:
            rep.warn(f"{sid} ({scene}): la puerta {d} queda en una cara oculta (hacia {_dir_name(out_d)}) y no hay "
                 f"{scene}_back; el sprite dibuja la puerta en la cara "
                 f"{'inferior izquierda' if face == 'row' else 'inferior derecha'}")
        elif drawn != scene or flip:
            rep.note(f"{sid}: puerta hacia {_dir_name(out_d)} -> {drawn}{' girado' if flip else ''}")
    # connectivity from the plaza
    plaza = next((t for t in m.all_tiles() if m.kind(t) == "plaza"), None)
    start = plaza or tuple((m.d.get("spawns") or {}).get("player", (0, 0)))
    reach = bfs(m, start) if m.walkable(start) else set()
    must = []
    for sid, s in m.sites.items():
        if s["door"]:
            must.append((s["door"], "puerta de " + sid))
    for kind, sid, tile, svc in m.services():
        must.append((svc, f"servicio de {sid}"))
    for sp in m.d.get("social_points") or []:
        for t in sp.get("slots", []):
            must.append((tuple(t), "punto social " + sp["id"]))
    for name, t in (m.d.get("spawns") or {}).items():
        must.append((tuple(t), "spawn " + name))
    for w in m.d.get("workplaces") or []:
        must.append((tuple(w["tile"]), "oficio " + w["id"]))
    for t, what in must:
        if t not in reach:
            rep.error(f"{what} en {t} no se alcanza desde la plaza")
    islands = sorted((t for t in m.all_tiles() if m.walkable(t) and t not in reach), key=lambda t: (t[1], t[0]))
    if islands:
        soft(f"{len(islands)} casillas transitables aisladas de la plaza (la primera {islands[0]})")
    net = [t for t in m.all_tiles() if m.kind(t) in ("street", "plaza", "bridge")]
    if net:
        seen_n, todo = {net[0]}, [net[0]]
        while todo:
            t = todo.pop()
            for dd in DIRS:
                v = (t[0] + dd[0], t[1] + dd[1])
                if v not in seen_n and m.kind(v) in ("street", "plaza", "bridge"):
                    seen_n.add(v)
                    todo.append(v)
        if len(seen_n) != len(net):
            rep.error(f"{len(net) - len(seen_n)} casillas de calle, plaza o puente sueltas de la red")
    # stalls give to the plaza
    for kind, sid, tile, svc in m.services():
        if abs(tile[0] - svc[0]) + abs(tile[1] - svc[1]) != 1:
            rep.error(f"{kind} {sid}: el servicio {svc} no está pegado a {tile}")
        if kind == "stall" and m.kind(svc) != "plaza":
            soft(f"puesto {sid}: su servicio {svc} no está en la plaza ({m.kind(svc)})")
    # population fits in the houses
    cap = int(m.cat.town.get("population", {}).get("house_capacity", 5))
    homes = {}
    people = 0
    for i, hh in enumerate(m.d.get("population") or []):
        home = hh.get("home")
        if home not in m.sites or m.sites[home]["type"] != "house":
            rep.error(f"population[{i}]: home {home} no es una casa del mapa")
        if home in homes:
            rep.error(f"population[{i}]: la casa {home} ya es de population[{homes[home]}]")
        homes[home] = i
        n = len(hh.get("members") or [])
        people += n
        if n > cap:
            rep.error(f"population[{i}]: {n} miembros en {home} (caben {cap})")
    n_houses = sum(1 for s in m.sites.values() if s["type"] == "house")
    if people > n_houses * cap:
        rep.error(f"población {people} > {n_houses} casas × {cap}")
    max_total = int(m.cat.town.get("population", {}).get("max_total", 0))
    if max_total > n_houses * cap and m.d.get("population"):
        soft(f"la ciudad puede crecer a {max_total} vecinos y solo caben {n_houses * cap} en {n_houses} casas")
    rep.note(f"{len(m.d.get('population') or [])} hogares, {people} vecinos, {n_houses} casas (caben {n_houses * cap})")
    # the decor
    decor = (m.d.get("decor") or {}).get("items")
    if decor is None:
        soft("sin decor (el juego usa el relleno de antes: casas giradas al azar)")
        return rep
    prot = m.protected()
    free = m.free_filler()
    covered = {}
    n_kind = {}
    lantern_at = []
    for i, it in enumerate(decor):
        k = it.get("kind", "")
        n_kind[k] = n_kind.get(k, 0) + 1
        at = tuple(it["at"])
        w, h = it.get("size", [1, 1])
        tiles = [(at[0] + dc, at[1] + dr) for dr in range(h) for dc in range(w)]
        if not os.path.exists(os.path.join(ROOT, "game", "visuals", "props", it["id"] + ".tscn")):
            rep.error(f"decor[{i}]: no hay escena game/visuals/props/{it['id']}.tscn")
        if k in ("house", "yard", "single"):
            for t in tiles:
                if t not in free:
                    rep.error(f"decor[{i}] {it['id']}: {t} no es una casilla de relleno libre ({m.kind(t)})")
                if t in covered:
                    rep.error(f"decor[{i}] {it['id']}: {t} ya lo cubre decor[{covered[t]}]")
                covered[t] = i
            if k == "house":
                f = tuple(it.get("facing", (0, 1)))
                lot = (at[0], at[1], w, h)
                fr = lot_facing_dir(m, lot, f, set(free), rl["filler"]["street_reach"])
                if not fr:
                    rep.error(f"decor[{i}] casa {it['id']} en {at}: su puerta (hacia {_dir_name(f)}) no da a una calle")
                exp_id, exp_flip = house_scene(_base_of(it["id"], rl), f, rl)
                if (exp_id, exp_flip) != (it["id"], bool(it.get("flip", False))):
                    rep.error(f"decor[{i}] casa {it['id']} en {at}: el sprite y el giro no casan con su puerta "
                              f"(hacia {_dir_name(f)}: {exp_id}{' girada' if exp_flip else ''})")
        else:
            x, y = to_world(*at)
            off = it.get("off", [0, 0])
            real = to_tile(x + off[0], y + off[1])
            for t in {at, real}:
                if t in prot and "puerta" in prot[t]:
                    rep.error(f"decor[{i}] {it['id']} en {t}: encima de la {prot[t]}")
                elif t in prot:
                    rep.error(f"decor[{i}] {it['id']} en {t}: encima de {prot[t]}")
                if m.is_path(t):
                    rep.error(f"decor[{i}] {it['id']} en {t}: encima de un camino ({m.kind(t)})")
                if t in covered and decor[covered[t]]["kind"] == "house":
                    rep.error(f"decor[{i}] {it['id']} en {t}: encima de una casa de relleno")
            if it["id"] == rl["lanterns"]["id"]:
                lantern_at.append(at)
    missing = sorted(free - set(covered))
    if missing:
        soft(f"{len(missing)} casillas de relleno sin vestir (la primera {missing[0]}): el juego las rellena como antes")
    # lanterns every N along the main streets
    every = rl["lanterns"]["every"]
    streets = [t for t in m.all_tiles() if m.kind(t) in rl["lanterns"]["streets"]]
    gaps = [t for t in streets if not any(max(abs(t[0] - a[0]), abs(t[1] - a[1])) <= every for a in lantern_at)]
    if streets:
        cover = 100.0 * (len(streets) - len(gaps)) / len(streets)
        rep.note(f"farolas: {len(lantern_at)}; {cover:.0f}% de las casillas de calle con una a {every} o menos")
        if gaps:
            soft(f"{len(gaps)} casillas de calle sin farola a {every} o menos (la primera {gaps[0]})")
    rep.note("decor: " + ", ".join(f"{k} {v}" for k, v in sorted(n_kind.items())))
    # the hand-placed decoration of game/visuals/towns/<id>.tscn
    for name, (x, y) in (hand_decor or []):
        t = to_tile(x, y)
        if t in prot:
            rep.error(f"towns/{rep.map_id}.tscn {name} en {t}: encima de {prot[t]}")
        if m.is_path(t):
            rep.error(f"towns/{rep.map_id}.tscn {name} en {t}: encima de un camino")
    return rep


def lot_facing_dir(m, lot, d, block, reach):
    m._owned = m.site_tiles()
    hits = [road_reach(m, t, d, reach, block) for t in front_line(lot, d)]
    need = max(2, (lot[2] if d[1] else lot[3]) - 1)
    return sum(1 for k in hits if k is not None) >= need


def _base_of(sid, rl):
    for base, back in rl["filler"]["back"].items():
        if sid == back:
            return base
    return sid


def _dir_name(d):
    return {(0, 1): "+fila (abajo izquierda)", (1, 0): "+columna (abajo derecha)", (0, -1): "-fila (arriba derecha)",
            (-1, 0): "-columna (arriba izquierda)"}.get(tuple(d), str(d))


def hand_decor(map_id):
    """[(node name, (x, y))] of game/visuals/towns/<map id>.tscn (root at the origin)."""
    p = os.path.join(ROOT, "game", "visuals", "towns", map_id + ".tscn")
    if not os.path.exists(p):
        return []
    out = []
    name = None
    with open(p, encoding="utf-8") as f:
        for line in f:
            mm = re.match(r'\[node name="([^"]+)" parent="\."', line)
            if mm:
                name = mm.group(1)
                continue
            mp = re.match(r"position = Vector2\(([-\d.]+), ([-\d.]+)\)", line)
            if mp and name:
                out.append((name, (float(mp.group(1)), float(mp.group(2)))))
                name = None
    return out


def load_map(map_id, cat=None):
    cat = cat or Catalog()
    return Map(load_json(os.path.join(DATA, "maps", map_id + ".json")), cat)


def save_map(data):
    """data/maps/<id>.json with the house style of the repo (one row per line, compact lists)."""
    p = os.path.join(DATA, "maps", data["id"] + ".json")
    with open(p, "w", encoding="utf-8") as f:
        f.write(dumps_map(data))
    return p


def dumps_map(data):
    """json.dump(indent=1) like tools/maps/make_town_e.py, with the decor one item per line at the end."""
    base = {k: v for k, v in data.items() if k != "decor"}
    text = json.dumps(base, indent=1, ensure_ascii=False)
    if "decor" not in data:
        return text + "\n"
    v = data["decor"]
    lines = [' "decor": {', f'  "_doc": {json.dumps(v["_doc"], ensure_ascii=False)},', '  "items": [']
    for j, it in enumerate(v["items"]):
        lines.append(f'   {json.dumps(it, ensure_ascii=False)}{"," if j < len(v["items"]) - 1 else ""}')
    lines += ["  ]", " }"]
    return text[:-2] + ",\n" + "\n".join(lines) + "\n}\n"
