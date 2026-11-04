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


# --- doors (docs/protocolos/generar-ciudad.md §Puertas) ------------------------------------------------------------
# The door of a drawn building is the Door marker of its scene (tools/city/marcar_puertas.py), exported to
# data/building_sprites.json (tools/city/sprites_catalog.py). Sides by the face of the footprint: SW looks to +row,
# SE to +col (the two the camera sees), NE to -row, NW to -col. Mirroring (x -> -x) swaps cols and rows: SW <-> SE,
# NE <-> NW, and a w x h drawing covers h x w.
SIDES = {"SW": (0, 1), "SE": (1, 0), "NE": (0, -1), "NW": (-1, 0)}
SIDE_OF = {v: k for k, v in SIDES.items()}
MIRRORED = {"SW": "SE", "SE": "SW", "NE": "NW", "NW": "NE"}


def px_to_rel(px):
    """A point of a scene (pixels from Feet, the footprint's centre) as tiles from that centre (col, row)."""
    return (px[0] / 64.0 + px[1] / 32.0, px[1] / 32.0 - px[0] / 64.0)


def _half_up(v):
    return int(v + 0.5) if v >= 0 else -int(-v + 0.5)


def door_tile(side, px, footprint):
    """The door's tile (from the footprint's origin) of a threshold `px` on face `side` of a w x h footprint."""
    w, h = footprint
    fc, fr = px_to_rel(px)
    c, r = fc + (w - 1) / 2.0, fr + (h - 1) / 2.0
    if side == "SW":
        return (max(0, min(w - 1, _half_up(c))), h)
    if side == "NE":
        return (max(0, min(w - 1, _half_up(c))), -1)
    if side == "SE":
        return (w, max(0, min(h - 1, _half_up(r))))
    return (-1, max(0, min(h - 1, _half_up(r))))


def sprites():
    p = os.path.join(DATA, "building_sprites.json")
    return load_json(p).get("scenes", {}) if os.path.exists(p) else {}


def drawn_door(entry, flip, footprint):
    """(side, tile from the origin) where a scene draws its door on a footprint, mirrored or not."""
    px = entry["door"]["px"]
    side = entry["door"]["side"]
    if flip:
        px, side = (-px[0], px[1]), MIRRORED[side]
    return side, door_tile(side, px, footprint)


def looks_for(spr, kind, scene, side):
    """The (scene, flip) of `scene` or its back view whose drawn door is on `side`, in order of preference (as drawn,
    mirrored, back, back mirrored); [] if none."""
    out = []
    e = spr.get(f"{kind}/{scene}")
    if not e:
        return out
    for sc in [scene] + ([e["back"]] if e.get("back") else []):
        ee = spr.get(f"{kind}/{sc}")
        if not ee:
            continue
        if ee["door"]["side"] == side:
            out.append((sc, False))
        if ee.get("mirror") and MIRRORED[ee["door"]["side"]] == side:
            out.append((sc, True))
    return out


def building_scene(cat, site):
    """What WorldView draws for a site (WorldView._door_facing): (look, drawn scene, flip, map door side) with look
    = data/view.json building_variants by its origin; the drawn scene and flip put the drawn door on the map door's
    side when a look can (as drawn, mirrored, back, back mirrored), else the look as drawn."""
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
    if side is None:
        return scene, scene, False, side
    got = looks_for(cat.sprites, "buildings", scene, SIDE_OF[side])
    if got:
        return scene, got[0][0], got[0][1], side
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
        self.sprites = sprites()  # data/building_sprites.json: the Door marker of each scene


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
        # sites on the same plot (one inside another's footprint): alternatives no start builds together (H12: the
        # rival of the player's own trade takes the forge's plot when the player is not the smith); the plot belongs
        # to the largest one (then by id)
        self.alt_of = {}
        plots = []
        for sid in sorted(self.sites, key=lambda k: (-len(self.sites[k]["tiles"]), k)):
            host = next((p for p in plots if self.sites[sid]["tiles"] <= self.sites[p]["tiles"]), "")
            if host:
                self.alt_of[sid] = host
            else:
                plots.append(sid)
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


def house_scene(cat, base, d):
    """Scene id and mirror for a filler house whose door must look to d: the look of the house (as drawn, mirrored,
    seen from behind, behind and mirrored) whose Door marker (data/building_sprites.json) is on that side."""
    got = looks_for(cat.sprites, "props", base, SIDE_OF[d])
    return got[0] if got else (base, False)


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

    planned = planned_lots(m.d)  # organic towns (tools/city/organic.py): the house lots the generator drew
    roofs = {d["id"]: d.get("roof", "") for d in (m.d.get("generated") or {}).get("districts", [])}

    def dress_planned(group, out):
        """The planned house lots of one block (mixed sizes: 3x3 a sprite house, any other size a house block of
        its district's roof colour), then the yards."""
        block = set(group)
        left = set(group)
        for (c, r, w, h, dist) in planned:
            tiles = [(c + dc, r + dr) for dr in range(h) for dc in range(w)]
            if not all(u in left for u in tiles):
                continue
            lot = (c, r, w, h)
            f = lot_facing(m, lot, block, reach)
            if f is None:
                continue
            for u in tiles:
                left.discard(u)
            if (w, h) == (lw, lh):
                k = tile_hash(c, r) % len(houses)
                touching = {b for (pl, b) in placed if _touch(pl, lot)}
                for _ in range(len(houses)):
                    if houses[k] not in touching:
                        break
                    k = (k + 1) % len(houses)
                placed.append((lot, houses[k]))
                sid, flip = house_scene(m.cat, houses[k], f[1])
                out.append({"kind": "house", "id": sid, "at": [c, r], "size": [w, h], "flip": flip,
                            "facing": list(f[1])})
            else:
                it = {"kind": "house", "id": BLOCK_HOUSE, "at": [c, r], "size": [w, h], "facing": list(f[1]),
                      "height": 26 + 6 * min(w, h) + tile_hash(c, r, 9) % 12}
                if roofs.get(dist):
                    it["color"] = roofs[dist]
                out.append(it)
        return left

    def dress_group(group, out, site=""):
        """House lots and yards of one block (a group of building tiles) into `out`; site: the alternative look of a
        map site's footprint, drawn only in a game without that building."""
        block = set(group)
        extra = {"site": site} if site else {}
        if len(group) == 1 and single and not site:
            out.append({"kind": "single", "id": single, "at": list(group[0])})
            return
        left = set(group)
        if planned and not site:
            left = dress_planned(group, out)
        while not (planned and not site):
            best = None
            for t in group:
                lot = (t[0], t[1], lw, lh)
                tiles = [(t[0] + dc, t[1] + dr) for dr in range(lh) for dc in range(lw)]
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
            sid, flip = house_scene(m.cat, base, f[1])
            out.append(dict({"kind": "house", "id": sid, "at": [lot[0], lot[1]], "size": [lot[2], lot[3]],
                             "flip": flip, "facing": list(f[1])}, **extra))
        # yards: what is left of the block (behind or beside the houses), one theme per block
        if themes and left:
            theme = themes[tile_hash(group[0][0] * 3 + 1, group[0][1] * 3 + 7) % len(themes)]
            seen_y = set()
            for t in sorted(left, key=lambda t: (t[1], t[0])):
                y = theme[tile_hash(*t) % len(theme)]
                if y in seen_y:
                    y = theme[0]
                seen_y.add(y)
                out.append(dict({"kind": "yard", "id": y, "at": list(t)}, **extra))

    for group in groups_of(free):
        dress_group(group, items)
    for it_i, it in enumerate(items):
        w, h = it.get("size", [1, 1])
        for dr in range(h):
            for dc in range(w):
                used[(it["at"][0] + dc, it["at"][1] + dr)] = it_i
    # the footprint of each site dressed like filler too, for a game where that building is not there (a scenario
    # that leaves a workshop out): WorldView draws these only when the site's tiles are free
    alt = []
    for sid, s in sorted(m.sites.items()):
        if sid != "town_hall" and sid not in m.alt_of:  # one dressing per plot (alternatives share it)
            dress_group(sorted(s["tiles"], key=lambda t: (t[1], t[0])), alt, sid)
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

    def add_prop(kind, sid, t, toward=None, frac=0.0, flip=False, site=""):
        off = [0, 0]
        if toward is not None:
            a, b = to_world(*t), to_world(*toward)
            off = [round((b[0] - a[0]) * frac), round((b[1] - a[1]) * frac)]
        it = {"kind": kind, "id": sid, "at": list(t)}
        if off != [0, 0]:
            it["off"] = off
        if flip:
            it["flip"] = True
        if site:
            it["site"] = site  # only with that building in the game (its props by the door)
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
            add_prop("prop", kinds[n], t, toward=toward, frac=frac, site=sid)
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
    # 6. the landmarks (map "landmarks") and the boats (map "boats"): blocks of their footprint, purely cosmetic
    for e in m.d.get("landmarks") or []:
        it = {"kind": "landmark", "id": e["type"], "at": list(e["origin"]), "size": list(e["size"]),
              "height": e.get("height", 48), "color": e.get("color", "#9a7a5a")}
        if e.get("label"):
            it["label"] = e["label"]
        items.append(it)
    for e in m.d.get("boats") or []:
        items.append({"kind": "boat", "id": e["type"], "at": list(e["origin"]), "size": list(e["size"]),
                      "color": e.get("color", "#6b4a2a")})
    return {"_doc": rl["_decor_doc"], "items": items + alt}


BLOCK_HOUSE = "house_block"  # a filler house of any size but 3x3: a greybox block until its sprite exists
LANDMARK_SCENE = "hito"  # the generic block of a landmark without its own scene (game/visuals/props/<type>.tscn)
BOAT_SCENE = "boat"


def planned_lots(d):
    """[(c, r, w, h, district)] of "generated".lots ("c,r,w,h,district;..."), in the generator's order."""
    raw = (d.get("generated") or {}).get("lots", "")
    out = []
    for part in raw.split(";") if raw else []:
        c, r, w, h, dist = part.split(",")
        out.append((int(c), int(r), int(w), int(h), dist))
    return out


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


def starts_of(m):
    """{start id: set of map sites it builds} for the starts of data/starts that play on this map (their "map") or
    that a generated map was made for ("generated.starts")."""
    out = {}
    sdir = os.path.join(DATA, "starts")
    wanted = set((m.d.get("generated") or {}).get("starts", []))
    for f in sorted(os.listdir(sdir)):
        if not f.endswith(".json") or f.startswith("_"):
            continue
        st = load_json(os.path.join(sdir, f))
        if st.get("map") != m.d.get("id") and st.get("id") not in wanted:
            continue
        used = {st["building"]["site"]}
        if st.get("rival", {}).get("building"):
            used.add(st["rival"]["building"]["site"])
        for cp in st.get("competitors", []):
            used.add(cp["building"]["site"])
        out[st["id"]] = used
    return out


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


def _catalog_problems():
    """The catalogue of drawn doors against the Door markers of the scenes (tools/city/sprites_catalog.py)."""
    import sprites_catalog
    return sprites_catalog.check()


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
        alt = m.alt_of.get(sid, "")
        if alt:
            both = [st for st, used in starts_of(m).items() if sid in used and alt in used]
            if both:
                rep.error(f"{sid} está dentro del solar de {alt} y el inicio {both[0]} construye los dos")
            else:
                rep.note(f"{sid}: alternativa de {alt} en el mismo solar (ningún inicio construye los dos)")
        for t in sorted(s["tiles"]):
            if not m.inside(t):
                rep.error(f"{sid}: casilla {t} fuera del mapa")
            elif m.kind(t) != "building":
                rep.error(f"{sid}: casilla {t} de la huella no es de edificio ({m.kind(t)})")
            if alt:
                continue
            if t in seen:
                rep.error(f"{sid} se solapa con {seen[t]} en {t}")
            seen[t] = sid
    for kind, sid, tile, svc in m.services():
        if kind != "town_hall" and tile in seen:
            rep.error(f"{kind} {sid} en {tile} encima de {seen[tile]}")
    # doors give to a walkable tile next to the footprint, on a street, and the drawn door (Door marker) is there
    for prob in _catalog_problems():
        rep.error(prob)
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
        scene, drawn, flip, out_d = building_scene(m.cat, s)
        e = m.cat.sprites.get("buildings/" + drawn)
        if e is None:
            rep.error(f"{sid}: la escena buildings/{drawn} no tiene marcador Door (data/building_sprites.json)")
            continue
        dside, dtile = drawn_door(e, flip, s["footprint"])
        rel = (d[0] - s["origin"][0], d[1] - s["origin"][1])
        look = f"{drawn}{' reflejado' if flip else ''}"
        if dside != SIDE_OF[out_d]:
            why = "no hay vista de espaldas" if out_d not in VISIBLE else "no se puede reflejar (lleva texto)"
            soft(f"{sid} ({look}): la puerta del mapa {d} da a {SIDE_OF[out_d]} y el sprite la dibuja en {dside} "
                 f"({why})")
        elif tuple(dtile) != rel:
            soft(f"{sid} ({look}): la puerta del mapa está en la casilla {list(rel)} de la huella y la dibujada en "
                 f"{list(dtile)}")
        elif drawn != scene or flip:
            rep.note(f"{sid}: puerta hacia {SIDE_OF[out_d]} -> {look}")
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
    if strict:  # the hand-made town_e keeps its old bridge as it is
        _check_water(m, rep, soft)
    # the decor
    decor = (m.d.get("decor") or {}).get("items")
    if decor is None:
        soft("sin decor (el juego usa el relleno de antes: casas giradas al azar)")
        return rep
    prot = m.protected()
    free = m.free_filler()
    covered = {}
    alt_covered = {}  # site -> {tile: item}: the footprint of a site dressed for a game without that building
    n_kind = {}
    lantern_at = []
    decor_marks = []
    for i, it in enumerate(decor):
        k = it.get("kind", "")
        n_kind[k] = n_kind.get(k, 0) + 1
        at = tuple(it["at"])
        w, h = it.get("size", [1, 1])
        tiles = [(at[0] + dc, at[1] + dr) for dr in range(h) for dc in range(w)]
        scene_ok = os.path.exists(os.path.join(ROOT, "game", "visuals", "props", it["id"] + ".tscn"))
        if k in ("landmark", "boat"):  # their own scene when the sprite exists, else the generic block
            fallback = LANDMARK_SCENE if k == "landmark" else BOAT_SCENE
            scene_ok = scene_ok or os.path.exists(os.path.join(ROOT, "game", "visuals", "props", fallback + ".tscn"))
        if not scene_ok:
            rep.error(f"decor[{i}]: no hay escena game/visuals/props/{it['id']}.tscn")
        if k in ("landmark", "boat"):
            decor_marks.append((i, it))
            continue
        if k in ("house", "yard", "single"):
            site = it.get("site", "")
            area = m.sites[site]["tiles"] if site in m.sites else free
            cov = alt_covered.setdefault(site, {}) if site else covered
            for t in tiles:
                if t not in area:
                    where = f"del solar {site}" if site else "de relleno libre"
                    rep.error(f"decor[{i}] {it['id']}: {t} no es una casilla {where} ({m.kind(t)})")
                if t in cov:
                    rep.error(f"decor[{i}] {it['id']}: {t} ya lo cubre decor[{cov[t]}]")
                cov[t] = i
            if k == "house":
                f = tuple(it.get("facing", (0, 1)))
                lot = (at[0], at[1], w, h)
                fr = lot_facing_dir(m, lot, f, set(area), rl["filler"]["street_reach"])
                if not fr:
                    rep.error(f"decor[{i}] casa {it['id']} en {at}: su puerta (hacia {_dir_name(f)}) no da a una calle")
                if it["id"] == BLOCK_HOUSE:  # a block: its door is the middle of its street side
                    fl = front_line(lot, f)
                    dt = fl[len(fl) // 2]
                    if not m.walkable(dt):
                        rep.error(f"decor[{i}] casa {it['id']} en {at}: delante de su puerta, {dt}, no se puede pasar "
                                  f"({m.kind(dt)})")
                    continue
                e = m.cat.sprites.get("props/" + it["id"])
                if e is None:
                    rep.error(f"decor[{i}] casa {it['id']}: su escena no tiene marcador Door")
                    continue
                dside, dtile = drawn_door(e, bool(it.get("flip", False)), (w, h))
                if dside != SIDE_OF[f]:
                    rep.error(f"decor[{i}] casa {it['id']} en {at}: dibuja la puerta en {dside} y la calle le queda "
                              f"en {SIDE_OF[f]}")
                dt = (at[0] + dtile[0], at[1] + dtile[1])
                if not m.walkable(dt) and dt not in area:
                    rep.error(f"decor[{i}] casa {it['id']} en {at}: delante de su puerta, {dt}, no se puede pasar "
                              f"({m.kind(dt)})")
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
    for sid, cov in sorted(alt_covered.items()):
        rest = sorted(m.sites[sid]["tiles"] - set(cov))
        if rest:
            rep.error(f"el vestido de reserva del solar {sid} no cubre {rest[0]} (y {len(rest) - 1} más)")
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
    _check_marks(m, rep, decor, decor_marks, covered, soft)
    # the hand-placed decoration of game/visuals/towns/<id>.tscn
    for name, (x, y) in (hand_decor or []):
        t = to_tile(x, y)
        if t in prot:
            rep.error(f"towns/{rep.map_id}.tscn {name} en {t}: encima de {prot[t]}")
        if m.is_path(t):
            rep.error(f"towns/{rep.map_id}.tscn {name} en {t}: encima de un camino")
    return rep


def _land(m, t):
    """Walkable ground that is not water, a pier, a bridge nor a ford."""
    return m.walkable(t) and m.kind(t) not in ("dock", "bridge", "ford")


def _check_water(m, rep, soft):
    """The water rules (docs/protocolos/generar-ciudad.md §Reglas): the river is crossed only by bridges and fords
    (its core, the tiles within "generated".rivers core of its course, is water, bridge, ford or pier), every bridge
    and ford joins two banks, every pier stands in the water and touches the land."""
    for rv in (m.d.get("generated") or {}).get("rivers", []):
        pts = [tuple(p) for p in rv["path"]]
        core = float(rv.get("core", 1.0))
        bad = []
        for t in m.all_tiles():
            if _dist_poly(t[0], t[1], pts) <= core and m.kind(t) not in ("water", "bridge", "ford", "dock"):
                bad.append(t)
        if bad:
            rep.error(f"el río se cruza sin puente ni vado: {len(bad)} casillas de su cauce son {m.kind(bad[0])} "
                      f"(la primera {bad[0]})")
    for kind, what in (("bridge", "puente"), ("ford", "vado")):
        tiles = {t for t in m.all_tiles() if m.kind(t) == kind}
        for g in groups_of(tiles):
            gs = set(g)
            if not any(m.kind((t[0] + d[0], t[1] + d[1])) == "water" for t in g for d in DIRS):
                soft(f"el {what} de {g[0]} no pasa sobre el agua")
            banks = {(t[0] + d[0], t[1] + d[1]) for t in g for d in DIRS} - gs
            banks = {u for u in banks if _land(m, u)}
            if len(groups_of8(banks)) < 2:
                rep.error(f"el {what} de {g[0]} no une dos orillas")
    docks = {t for t in m.all_tiles() if m.kind(t) == "dock"}
    for g in groups_of(docks):
        if not any(m.kind((t[0] + d[0], t[1] + d[1])) == "water" for t in g for d in DIRS):
            rep.error(f"el muelle de {g[0]} no toca el agua")
        if not any(_land(m, (t[0] + d[0], t[1] + d[1])) for t in g for d in DIRS):
            rep.error(f"el muelle de {g[0]} no toca la tierra")
        for t in g:
            if not any(m.kind((t[0] + dc, t[1] + dr)) == "water" for dc in (-1, 0, 1) for dr in (-1, 0, 1)):
                rep.error(f"la casilla {t} del muelle no está sobre el agua")


def _check_marks(m, rep, decor, marks, covered, soft):
    """Landmarks and boats: each landmark of the map (its "landmarks") on "H" tiles drawn once by the decor, nothing
    of the map or the decor on its footprint; every "H" tile in a landmark; boats on the water only, apart."""
    lm_tiles = {}
    for j, e in enumerate(m.d.get("landmarks") or []):
        c, r = e["origin"]
        w, h = e["size"]
        for t in [(c + dc, r + dr) for dr in range(h) for dc in range(w)]:
            if t in lm_tiles:
                rep.error(f"hito {e['type']} en {e['origin']}: pisa la huella del hito {lm_tiles[t]}")
            lm_tiles[t] = f"{e['type']} {e['origin']}"
            if m.kind(t) != "landmark":
                rep.error(f"hito {e['type']} en {e['origin']}: su casilla {t} es {m.kind(t)}, no H")
    stray = sorted(t for t in m.all_tiles() if m.kind(t) == "landmark" and t not in lm_tiles)
    if stray:
        rep.error(f"{len(stray)} casillas H sin hito (la primera {stray[0]})")
    drawn = {}
    for i, it in marks:
        if it["kind"] != "landmark":
            continue
        drawn[(tuple(it["at"]), tuple(it.get("size", [1, 1])))] = i
    for e in m.d.get("landmarks") or []:
        if (tuple(e["origin"]), tuple(e["size"])) not in drawn:
            soft(f"hito {e['type']} en {e['origin']}: el decor no lo dibuja (python3 tools/city/ciudad.py vestir)")
    for i, it in enumerate(decor):
        if it["kind"] in ("landmark", "boat"):
            continue
        x, y = to_world(*it["at"])
        off = it.get("off", [0, 0])
        w, h = it.get("size", [1, 1])
        tiles = {(it["at"][0] + dc, it["at"][1] + dr) for dr in range(h) for dc in range(w)}
        tiles.add(to_tile(x + off[0], y + off[1]))
        hit = sorted(t for t in tiles if t in lm_tiles)
        if hit:
            rep.error(f"decor[{i}] {it['id']} en {hit[0]}: pisa la huella del hito {lm_tiles[hit[0]]}")
    for sid, s in sorted(m.sites.items()):
        hit = sorted(t for t in s["tiles"] if t in lm_tiles)
        if hit:
            rep.error(f"{sid}: su huella pisa el hito {lm_tiles[hit[0]]} en {hit[0]}")
    for kind, sid, tile, svc in m.services():
        if tile in lm_tiles or svc in lm_tiles:
            rep.error(f"{kind} {sid}: encima del hito {lm_tiles.get(tile) or lm_tiles.get(svc)}")
    boat_at = {}
    for j, e in enumerate(m.d.get("boats") or []):
        c, r = e["origin"]
        w, h = e["size"]
        for t in [(c + dc, r + dr) for dr in range(h) for dc in range(w)]:
            if m.kind(t) != "water":
                rep.error(f"barco {e['type']} en {e['origin']}: su casilla {t} no es agua ({m.kind(t) or 'fuera'})")
            if t in boat_at:
                rep.error(f"barco {e['type']} en {e['origin']}: se cruza con el barco {boat_at[t]}")
            boat_at[t] = f"{e['type']} {e['origin']}"
    n_lm, n_b = len(m.d.get("landmarks") or []), len(m.d.get("boats") or [])
    if n_lm or n_b:
        rep.note(f"hitos: {n_lm}; barcos: {n_b}")


def groups_of8(tiles):
    """Connected groups (8-neighbourhood) of a set of tiles."""
    seen, out = set(), []
    for t in sorted(tiles, key=lambda t: (t[1], t[0])):
        if t in seen:
            continue
        g, stack = [], [t]
        seen.add(t)
        while stack:
            u = stack.pop()
            g.append(u)
            for dc in (-1, 0, 1):
                for dr in (-1, 0, 1):
                    v = (u[0] + dc, u[1] + dr)
                    if v in tiles and v not in seen:
                        seen.add(v)
                        stack.append(v)
        out.append(g)
    return out


def _dist_poly(x, y, pts):
    best = 1e9
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        vx, vy = bx - ax, by - ay
        L = vx * vx + vy * vy
        t = 0.0 if L == 0 else max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / L))
        best = min(best, ((x - ax - t * vx) ** 2 + (y - ay - t * vy) ** 2) ** 0.5)
    return best


def lot_facing_dir(m, lot, d, block, reach):
    m._owned = m.site_tiles()
    hits = [road_reach(m, t, d, reach, block) for t in front_line(lot, d)]
    need = max(2, (lot[2] if d[1] else lot[3]) - 1)
    return sum(1 for k in hits if k is not None) >= need


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
