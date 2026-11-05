#!/usr/bin/env python3
"""Interiores por datos (docs/gdd/04g_interiores.md §4.6.5.2): data/interiors/<edificio>.json.

  python3 tools/interiors/interiores.py validar [<edificio>...]     # errores de cada interior (0 = bien)
  python3 tools/interiors/interiores.py reglas [<edificio>...]      # resuelve las reglas de decoración → "resolved"
  python3 tools/interiors/interiores.py vista <edificio> [--out p.png] [--sin-mejoras] [--marcas]
  python3 tools/interiors/interiores.py plantilla <edificio> <planta> [--out p.png]   # para pintar su fondo con fal

`center_offset` [x, y] (px, opcional) mueve la sala en pantalla (una sala ancha deja sitio a los paneles).
Un interior es una rejilla de `size` casillas (col, fila) con varias plantas (-1 sótano, 0 baja, 1 alta). Cada sala
es una lista de rectángulos [c0, f0, c1, f1] (incluidos) de una planta. Las paredes salen solas:
- borde de atrás de una sala (lado nw: col − 1; lado ne: fila − 1) sin otra sala detrás → pared exterior del fondo,
  pintada en el fondo de la sala (fal);
- borde entre dos salas → tramo de pared interior (pieza wall_<estilo>_<lado>, que se transparenta), o puerta si
  hay una en `doors` ({floor, tile, side}: el tramo del lado `side` de esa casilla);
- borde de delante sin sala → zócalo (wall_low_*).
Desniveles (`levels`: {floor, rect, step}) de un escalón (step −1 = foso, +1 = tarima), que se salvan andando.
Escaleras (`stairs`): una pieza de 2×1 con su rellano abajo (`from`) y su llegada (`to_floor`, `to`).
Piezas (`props`, `stations`, `upgrades`, y lo que dejan las reglas en `resolved`): {id, floor, tile, flip}; una pieza
de N×1 ocupa su casilla y las N − 1 de detrás a lo largo de su eje (hacia la fila − 1; con flip, hacia la col − 1).
Las reglas (`rules`) son deterministas con la semilla del interior: esta herramienta las resuelve y Godot solo lee
las piezas ya colocadas, así hay un solo motor de reglas.
"""
import argparse
import json
import os
import random
import sys
from collections import deque

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.environ.get("GM_INTERIORS_DIR") or os.path.join(ROOT, "data", "interiors")  # otra carpeta: borradores
CATALOG = os.path.join(ROOT, "data", "props", "interior.json")
PROPS_ART = os.path.join(ROOT, "assets", "art", "props", "interior")
ROOM_TYPES = ["workshop", "shop", "storage", "kitchen", "bedroom", "hall", "office", "yard", "cellar", "chapel"]
FLOOR_KINDS = ["flagstone", "planks", "earth", "stone", "rug"]
WALL_STYLES = ["timber", "stone"]
TW, TH = 64, 32


# --- carga ------------------------------------------------------------------------------------------------------
def catalog():
    return json.load(open(CATALOG, encoding="utf-8"))["props"]


def ids(templates=True):
    """Los interiores (y, con templates, las plantillas _<id>.json de lo que aún no es un edificio: la guarida)."""
    return sorted(n[:-5] for n in os.listdir(DATA) if n.endswith(".json") and n != "lights.json"
                  and (templates or not n.startswith("_")))


def load(b):
    return json.load(open(os.path.join(DATA, b + ".json"), encoding="utf-8"))


def lights():
    p = os.path.join(DATA, "lights.json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}


def save(b, d):
    open(os.path.join(DATA, b + ".json"), "w", encoding="utf-8").write(dump(d))


def dump(d):
    """JSON legible: una línea por pieza, por sala y por regla."""
    def line(v):
        return json.dumps(v, ensure_ascii=False)
    out = ["{"]
    keys = list(d.keys())
    for i, k in enumerate(keys):
        v = d[k]
        end = "," if i < len(keys) - 1 else ""
        if isinstance(v, list) and v and all(isinstance(x, dict) for x in v):
            out.append(f'  {line(k)}: [')
            out += [f"    {line(x)}" + ("," if j < len(v) - 1 else "") for j, x in enumerate(v)]
            out.append("  ]" + end)
        elif isinstance(v, dict) and v and k in ("stations", "upgrades", "customers"):
            out.append(f'  {line(k)}: {{')
            ks = list(v.keys())
            out += [f"    {line(x)}: {line(v[x])}" + ("," if j < len(ks) - 1 else "") for j, x in enumerate(ks)]
            out.append("  }" + end)
        else:
            out.append(f"  {line(k)}: {line(v)}{end}")
    out.append("}")
    return "\n".join(out) + "\n"


# --- geometría --------------------------------------------------------------------------------------------------
def world(c, r):
    return ((c - r) * TW / 2, (c + r) * TH / 2)


def footprint_tiles(p, cat):
    """Casillas que ocupa la pieza `p` ({id, tile, flip}) según su huella del catálogo."""
    pr = cat.get(p["id"], {})
    a, b = pr.get("footprint", [1, 1])
    c, r = p["tile"]
    if p.get("flip"):
        return [(c - i, r - j) for i in range(a) for j in range(b)]
    return [(c - j, r - i) for i in range(a) for j in range(b)]


def feet_world(p, cat):
    ts = footprint_tiles(p, cat)
    xs = [world(c, r) for c, r in ts]
    return (sum(x for x, _ in xs) / len(xs), sum(y for _, y in xs) / len(xs))


class Layout:
    """Lo que sale de los datos: casillas por sala y planta, paredes, puertas, ocupación y navegación."""

    def __init__(self, d, cat, upgrades=True):
        self.d, self.cat = d, cat
        self.W, self.H = d["size"]
        self.wall_h = d.get("wall_height", 64)
        self.floors = sorted({r["floor"] for r in d["rooms"]})
        self.room_of = {f: {} for f in self.floors}  # floor -> (c, r) -> room id
        self.rooms = {r["id"]: r for r in d["rooms"]}
        for room in d["rooms"]:
            for c0, r0, c1, r1 in room["rects"]:
                for r in range(r0, r1 + 1):
                    for c in range(c0, c1 + 1):
                        self.room_of[room["floor"]][(c, r)] = room["id"]
        self.doors = {(x["floor"], tuple(x["tile"]), x["side"]) for x in d.get("doors", [])}
        ent = d.get("entrance")
        self.entrance = (ent["floor"], tuple(ent["tile"]), ent["side"]) if ent else None
        self.step = {}
        for lv in d.get("levels", []):
            c0, r0, c1, r1 = lv["rect"]
            for r in range(r0, r1 + 1):
                for c in range(c0, c1 + 1):
                    self.step[(lv["floor"], (c, r))] = lv["step"]
        self.placed = self._placed(upgrades)
        self.blocked = {f: set() for f in self.floors}
        for p in self.placed:
            pr = cat.get(p["id"], {})
            if pr.get("walkable") or pr.get("hangs") or p.get("lift") or pr.get("category") == "small":
                continue  # lo plano, lo colgado, lo de encima de una mesa y el atrezo pequeño del suelo no cortan el paso
            for t in footprint_tiles(p, cat):
                self.blocked[p["floor"]].add(t)
        for s in d.get("stairs", []):
            for t in footprint_tiles({"id": s["prop"], "tile": s["tile"], "flip": s.get("flip", False)}, cat):
                self.blocked[s["floor"]].add(t)

    def _placed(self, upgrades):
        """Todas las piezas con su sitio: atrezo, reglas resueltas, puestos con pieza y (si se pide) mejoras."""
        out = []
        for p in self.d.get("props", []) + self.d.get("resolved", []):
            out.append(dict(p, source="props"))
        for z, s in self.d.get("stations", {}).items():
            if s.get("prop"):
                out.append({"id": s["prop"], "floor": s["floor"], "tile": s["tile"], "flip": s.get("flip", False),
                            "source": "station", "zone": z})
            else:
                out.append({"id": "_station", "floor": s["floor"], "tile": s["tile"], "source": "station", "zone": z})
        if upgrades:
            for node, ps in self.d.get("upgrades", {}).items():
                for p in ps:
                    out.append(dict(p, source="upgrade", node=node))
        return out

    def walls(self, floor):
        """[(kind, tile, side, behind_room, front_room)]: kind back | inner | door | low."""
        out = []
        rof = self.room_of[floor]
        for (c, r), room in rof.items():
            for side, nb in (("nw", (c - 1, r)), ("ne", (c, r - 1))):
                other = rof.get(nb)
                if other is None:
                    out.append(("back", (c, r), side, None, room))
                elif other != room:
                    kind = "door" if (floor, (c, r), side) in self.doors else "inner"
                    out.append((kind, (c, r), side, other, room))
            for side, nb in (("sw", (c, r + 1)), ("se", (c + 1, r))):
                if rof.get(nb) is None:
                    out.append(("low", (c, r), side, room, None))
        return out

    def passable(self, floor, a, b):
        """¿Se pasa de la casilla a a la b (vecinas) en esa planta? Mismas sala o una puerta entre ellas."""
        rof = self.room_of[floor]
        if b not in rof or b in self.blocked[floor]:
            return False
        if abs(self.step.get((floor, a), 0) - self.step.get((floor, b), 0)) > 1:
            return False
        if rof[a] == rof[b]:
            return True
        (c1, r1), (c2, r2) = a, b
        if c2 == c1 + 1:
            return (floor, b, "nw") in self.doors
        if c2 == c1 - 1:
            return (floor, a, "nw") in self.doors
        if r2 == r1 + 1:
            return (floor, b, "ne") in self.doors
        return (floor, a, "ne") in self.doors

    def reach(self, start):
        """Casillas (planta, casilla) alcanzables andando desde `start`, con las escaleras."""
        seen = {start}
        q = deque([start])
        links = {}
        for s in self.d.get("stairs", []):
            a = (s["floor"], tuple(s["from"]))
            b = (s["to_floor"], tuple(s["to"]))
            links.setdefault(a, []).append(b)
            links.setdefault(b, []).append(a)
        while q:
            f, (c, r) = q.popleft()
            for nb in ((c + 1, r), (c - 1, r), (c, r + 1), (c, r - 1)):
                if (f, nb) not in seen and self.passable(f, (c, r), nb):
                    seen.add((f, nb))
                    q.append((f, nb))
            for nxt in links.get((f, (c, r)), []):
                if nxt not in seen:
                    seen.add(nxt)
                    q.append(nxt)
        return seen

    def stand(self, zone):
        s = self.d["stations"][zone]
        if "stand" in s:
            return (s["floor"], tuple(s["stand"]))
        c, r = s["tile"]
        return (s["floor"], (c - 1, r))

    def entry_tile(self):
        f, (c, r), side = self.entrance
        return (f, (c, r))


# --- reglas -----------------------------------------------------------------------------------------------------
def resolve(d, cat):
    """Las piezas que ponen las reglas (deterministas con la semilla): [{id, floor, tile, flip, rule}]."""
    rnd = random.Random(d.get("seed", 1))
    lay = Layout(dict(d, resolved=[]), cat, upgrades=True)
    taken = {f: set(lay.blocked[f]) for f in lay.floors}
    keep = set()  # casillas que no se tapan: rellanos, sitios de pie, de clientes y de espera
    for z in d.get("stations", {}):
        keep.add(lay.stand(z))
    for spots in d.get("customers", {}).values():
        for s in spots:
            keep.add((s.get("floor", 0), tuple(s["tile"])))
    for s in d.get("idle", []) + d.get("seats", []) + d.get("beds", []):
        keep.add((s.get("floor", 0), tuple(s["tile"])))
    for s in d.get("stairs", []):
        keep.add((s["floor"], tuple(s["from"])))
        keep.add((s["to_floor"], tuple(s["to"])))
    for fl, t, side in lay.doors | ({lay.entrance} if lay.entrance else set()):
        keep.add((fl, t))
        nb = (t[0] - 1, t[1]) if side == "nw" else (t[0], t[1] - 1)
        keep.add((fl, nb))
    out = []
    placed_by_room = {}
    for p in lay.placed:
        rof = lay.room_of.get(p["floor"], {})
        placed_by_room.setdefault(rof.get(tuple(p["tile"])), []).append(p)
    for rule in d.get("rules", []):
        room = lay.rooms[rule["room"]]
        f = room["floor"]
        tiles = sorted(t for t, rid in lay.room_of[f].items() if rid == room["id"])
        kind = rule["rule"]
        if kind == "wall_fill":  # pegado a una pared del fondo (exterior o interior) y libre
            for (c, r) in tiles:
                backs = [s for s, nb in (("nw", (c - 1, r)), ("ne", (c, r - 1))) if lay.room_of[f].get(nb) != room["id"]]
                if not backs or (c, r) in taken[f] or (f, (c, r)) in keep:
                    continue
                if any((f, (c, r), s) in lay.doors for s in backs) or (lay.entrance and lay.entrance[:2] == (f, (c, r))):
                    continue
                if rnd.random() > rule.get("chance", 0.7):
                    continue
                pid = rnd.choice(rule["props"])
                p = {"id": pid, "floor": f, "tile": [c, r], "flip": rnd.random() < 0.5 and cat[pid].get("mirror", True),
                     "rule": kind}
                if any(t in taken[f] or t not in lay.room_of[f] or (f, t) in keep for t in footprint_tiles(p, cat)):
                    continue
                for t in footprint_tiles(p, cat):
                    taken[f].add(t)
                out.append(p)
        elif kind == "scatter":  # cosas planas o pequeñas por el suelo libre
            n = rule.get("count", 3)
            free = [t for t in tiles if t not in taken[f] and (f, t) not in keep]
            rnd.shuffle(free)
            for t in free[:n]:
                pid = rnd.choice(rule["props"])
                out.append({"id": pid, "floor": f, "tile": list(t), "flip": rnd.random() < 0.5, "rule": kind})
                if not cat[pid].get("walkable"):
                    taken[f].add(t)
        elif kind == "on_top":  # piezas pequeñas encima de los muebles de `under`
            for base in placed_by_room.get(room["id"], []) + [p for p in out if lay.room_of[f].get(tuple(p["tile"])) == room["id"]]:
                if base["id"] not in rule["under"] or rnd.random() > rule.get("chance", 0.8):
                    continue
                bp = cat[base["id"]]
                top = bp["feet"][1] - (bp["size"][1] - bp["feet"][1]) * 0 - bp["height"]  # y de arriba del sprite
                lift = bp["height"] - (sum(bp["footprint"]) * 8)  # la superficie: lo alto menos media huella
                k = rnd.randint(1, rule.get("max", 2))
                for i in range(k):
                    pid = rnd.choice(rule["props"])
                    span = 10 * (sum(bp["footprint"]) - 1)
                    dx = rnd.randint(-span, span) if span else rnd.randint(-4, 4)
                    out.append({"id": pid, "floor": f, "tile": list(base["tile"]), "flip": rnd.random() < 0.5,
                                "lift": max(4, lift), "shift": [dx, -abs(dx) // 2 if base.get("flip") else abs(dx) // 2 * 0],
                                "rule": kind, "over": base["id"]})
                _ = top
        elif kind == "hang":  # piezas de pared colgadas en los tramos interiores de la sala que se ven
            segs = [w for w in lay.walls(f) if w[0] == "inner" and w[4] == room["id"]]
            rnd.shuffle(segs)
            for w in segs[: rule.get("count", 2)]:
                pid = rnd.choice(rule["props"])
                out.append({"id": pid, "floor": f, "tile": list(w[1]), "flip": w[2] == "ne", "hang": w[2],
                            "rule": kind})
    return out


# --- validación -------------------------------------------------------------------------------------------------
def validate(b, d=None, cat=None):
    errs = []
    d = d or load(b)
    cat = cat or catalog()
    w = f"interiors/{b}"
    if not (isinstance(d.get("size"), list) and len(d["size"]) == 2):
        return [f"{w}: size debe ser [cols, filas]"]
    W, H = d["size"]
    ids_room = set()
    for room in d.get("rooms", []):
        if room.get("id") in ids_room:
            errs.append(f"{w}: sala repetida {room.get('id')}")
        ids_room.add(room.get("id"))
        if room.get("type") not in ROOM_TYPES:
            errs.append(f"{w}: sala {room.get('id')}: tipo desconocido {room.get('type')}")
        if room.get("floor_kind", "planks") not in FLOOR_KINDS:
            errs.append(f"{w}: sala {room.get('id')}: suelo desconocido {room.get('floor_kind')}")
        if room.get("wall_style", "timber") not in WALL_STYLES:
            errs.append(f"{w}: sala {room.get('id')}: estilo de pared desconocido {room.get('wall_style')}")
        if room.get("light") and room["light"] not in lights().get("lights", {}):
            errs.append(f"{w}: sala {room.get('id')}: luz desconocida {room.get('light')}")
        for rc in room.get("rects", []):
            c0, r0, c1, r1 = rc
            if not (0 <= c0 <= c1 < W and 0 <= r0 <= r1 < H):
                errs.append(f"{w}: sala {room['id']}: rectángulo {rc} fuera de la rejilla {d['size']}")
    if errs:
        return errs
    lay = Layout(d, cat)
    # salas que no se pisan entre sí
    seen = {}
    for room in d["rooms"]:
        for c0, r0, c1, r1 in room["rects"]:
            for r in range(r0, r1 + 1):
                for c in range(c0, c1 + 1):
                    k = (room["floor"], (c, r))
                    if k in seen and seen[k] != room["id"]:
                        errs.append(f"{w}: la casilla {k} es de {seen[k]} y de {room['id']}")
                    seen[k] = room["id"]
    for p in lay.placed:
        if p["id"] != "_station" and p["id"] not in cat:
            errs.append(f"{w}: pieza desconocida {p['id']} (no está en data/props/interior.json)")
            continue
        f = p["floor"]
        if f not in lay.room_of:
            errs.append(f"{w}: {p['id']} en una planta sin salas ({f})")
            continue
        tiles = footprint_tiles(p, cat) if p["id"] != "_station" else [tuple(p["tile"])]
        for t in tiles:
            if t not in lay.room_of[f]:
                errs.append(f"{w}: {p['id']} ({p.get('node') or p.get('zone') or p.get('rule') or 'props'}) en {t}, "
                            f"fuera de las salas de la planta {f}")
    # puertas que dan a algo
    for f, (c, r), side in lay.doors:
        nb = (c - 1, r) if side == "nw" else (c, r - 1)
        rof = lay.room_of.get(f, {})
        if (c, r) not in rof or nb not in rof or rof[(c, r)] == rof[nb]:
            errs.append(f"{w}: la puerta {f} {[c, r]} {side} no separa dos salas")
    if lay.entrance is None:
        errs.append(f"{w}: falta entrance (la puerta de la calle)")
        return errs
    f, (c, r), side = lay.entrance
    nb = (c - 1, r) if side == "nw" else (c, r - 1)
    if (c, r) not in lay.room_of.get(f, {}) or nb in lay.room_of.get(f, {}):
        errs.append(f"{w}: entrance {[c, r]} {side} tiene que estar en una pared exterior del fondo")
    # nada pisa una puerta, una escalera ni un sitio de pie
    for fl, t, side in lay.doors | {lay.entrance}:
        nb = (t[0] - 1, t[1]) if side == "nw" else (t[0], t[1] - 1)
        for tt in (t, nb):
            if tt in lay.blocked.get(fl, set()):
                errs.append(f"{w}: algo tapa la puerta {fl} {list(t)} {side} (casilla {list(tt)})")
    for s in d.get("stairs", []):
        if s["prop"] not in cat:
            errs.append(f"{w}: escalera con pieza desconocida {s['prop']}")
        for fl, t in ((s["floor"], tuple(s["from"])), (s["to_floor"], tuple(s["to"]))):
            if t not in lay.room_of.get(fl, {}) or t in lay.blocked.get(fl, set()):
                errs.append(f"{w}: el rellano {fl} {list(t)} de la escalera está fuera o tapado")
    reach = lay.reach(lay.entry_tile())
    for z in d.get("stations", {}):
        st = lay.stand(z)
        if st not in reach:
            errs.append(f"{w}: el sitio de pie del puesto {z} {st} no se alcanza desde la puerta")
    for kind, spots in d.get("customers", {}).items():
        for s in spots:
            k = (s.get("floor", 0), tuple(s["tile"]))
            if k not in reach:
                errs.append(f"{w}: el sitio de cliente {kind} {k} no se alcanza desde la puerta")
    for s in d.get("idle", []):
        if (s["floor"], tuple(s["tile"])) not in reach:
            errs.append(f"{w}: el sitio de espera {s['floor']} {s['tile']} no se alcanza")
    for kind in ("seats", "beds"):  # la Taberna-Posada (InnLayer): cada asiento y cada cama, en su sala y a mano
        for i, s in enumerate(d.get(kind, [])):
            k = (s.get("floor", 0), tuple(s["tile"]))
            if k[1] not in lay.room_of.get(k[0], {}) or k[1] in lay.blocked.get(k[0], set()):
                errs.append(f"{w}: {kind}[{i}] {k} fuera de las salas o tapado")
            elif kind == "seats" and k not in reach:
                errs.append(f"{w}: el asiento {i} {k} no se alcanza desde la puerta")
    for room in d["rooms"]:  # toda sala tiene alguna casilla a la que se llega
        fl = room["floor"]
        if not any((fl, t) in reach for t, rid in lay.room_of[fl].items() if rid == room["id"]):
            errs.append(f"{w}: no se llega a la sala {room['id']} (planta {fl}) desde la puerta")
    import glob as _glob  # la misma paleta (§4.6.5.1): con fondos pintados, cada pieza usada lleva su copia con su paleta
    if _glob.glob(os.path.join(ROOT, "assets", "art", "interiors", b, "room_*.png")):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import remap_props
        for pid in remap_props.used_props(d, cat):
            if not os.path.exists(os.path.join(ROOT, "assets", "art", "interiors", b, "props", pid + ".png")):
                errs.append(f"{w}: falta {pid} con la paleta de sus fondos: python3 tools/interiors/remap_props.py {b}")
                break
    want = resolve(d, cat)
    if want != d.get("resolved", []):
        errs.append(f"{w}: las reglas no coinciden con resolved: python3 tools/interiors/interiores.py reglas {b}")
    return errs


# --- dibujo (vista previa y plantilla) --------------------------------------------------------------------------
def canvas_box(d):
    """Lienzo de una planta (a ×1): (ancho, alto, origen x, origen y) del centro de la casilla (0, 0)."""
    W, H = d["size"]
    wh = d.get("wall_height", 64)
    return ((W + H) * 32, (W + H) * 16 + wh, H * 32, 16 + wh)


# colores planos de la plantilla, bien distintos (el modelo los lee por el nombre de color de fal_salas.FLOOR_COLOR)
FLOOR_FLAT = {"flagstone": (120, 120, 124), "planks": (140, 72, 36), "earth": (176, 150, 92), "stone": (84, 84, 96),
              "rug": (150, 40, 60)}


def _diamond(ox, oy, c, r, k=1):
    x, y = world(c, r)
    x, y = (ox + x) * k, (oy + y) * k
    return [(x, y - 16 * k), (x + 32 * k, y), (x, y + 16 * k), (x - 32 * k, y)]


def _wall_poly(ox, oy, c, r, side, h, k=1):
    x, y = world(c, r)
    x, y = ox + x, oy + y
    if side == "nw":
        a, b = (x - 32, y), (x, y - 16)
    elif side == "ne":
        a, b = (x, y - 16), (x + 32, y)
    elif side == "sw":
        a, b = (x - 32, y), (x, y + 16)
    else:
        a, b = (x, y + 16), (x + 32, y)
    pts = [a, b, (b[0], b[1] - h), (a[0], a[1] - h)]
    return [(px * k, py * k) for px, py in pts]


def template(b, floor, k=3, d=None, steps=True):
    """Plantilla de la planta para pintar su fondo: suelos por sala en colores planos (con su borde), fosos y tarimas,
    las paredes exteriores del fondo y la puerta de la calle. Sin paredes interiores (son piezas)."""
    from PIL import Image, ImageDraw
    d = d or load(b)
    lay = Layout(d, catalog(), upgrades=False)
    cw, ch, ox, oy = canvas_box(d)
    im = Image.new("RGB", (cw * k, ch * k), (0, 0, 0))
    dr = ImageDraw.Draw(im)
    wh = lay.wall_h
    for (c, r), rid in sorted(lay.room_of[floor].items()):
        room = lay.rooms[rid]
        col = FLOOR_FLAT.get(room.get("floor_kind", "planks"))
        st = lay.step.get((floor, (c, r)), 0) if steps else 0
        if st < 0:
            col = tuple(int(v * 0.62) for v in col)
        elif st > 0:
            col = tuple(min(255, int(v * 1.18)) for v in col)
        dr.polygon(_diamond(ox, oy, c, r, k), fill=col, outline=tuple(int(v * 0.85) for v in col))
    for kind, t, side, behind, front in lay.walls(floor):
        if kind == "back":
            col = (196, 176, 146) if side == "ne" else (168, 148, 118)
            if lay.rooms[front].get("wall_style") == "stone":
                col = (120, 114, 108) if side == "ne" else (104, 98, 92)
            dr.polygon(_wall_poly(ox, oy, t[0], t[1], side, wh, k), fill=col)
        elif kind in ("inner", "door"):  # la junta entre salas, solo una línea en el suelo
            x, y = world(*t)
            a = ((ox + x - 32) * k, (oy + y) * k) if side == "nw" else ((ox + x) * k, (oy + y - 16) * k)
            bb = ((ox + x) * k, (oy + y - 16) * k) if side == "nw" else ((ox + x + 32) * k, (oy + y) * k)
            dr.line([a, bb], fill=(40, 30, 22), width=2 * k)
    if lay.entrance and lay.entrance[0] == floor:
        f, (c, r), side = lay.entrance
        poly = _wall_poly(ox, oy, c, r, side, wh)
        a, b2 = poly[0], poly[1]
        pa = (a[0] + (b2[0] - a[0]) * 0.2, a[1] + (b2[1] - a[1]) * 0.2)
        pb = (a[0] + (b2[0] - a[0]) * 0.8, a[1] + (b2[1] - a[1]) * 0.8)
        door = [pa, pb, (pb[0], pb[1] - 52), (pa[0], pa[1] - 52)]
        dr.polygon([(x * k, y * k) for x, y in door], fill=(70, 44, 26), outline=(40, 24, 14))
    return im


def room_mask(d, floor, room_id):
    """La máscara (a ×1, en el lienzo de la planta) de una sala: sus casillas y sus paredes exteriores del fondo."""
    from PIL import Image, ImageDraw
    lay = Layout(d, catalog(), upgrades=False)
    cw, ch, ox, oy = canvas_box(d)
    m = Image.new("L", (cw, ch), 0)
    dr = ImageDraw.Draw(m)
    for (c, r), rid in lay.room_of[floor].items():
        if rid == room_id:
            dr.polygon(_diamond(ox, oy, c, r), fill=255)
    for kind, t, side, behind, front in lay.walls(floor):
        if kind == "back" and front == room_id:
            dr.polygon(_wall_poly(ox, oy, t[0], t[1], side, lay.wall_h), fill=255)
    return m


def backdrop_path(b, floor, room_id):
    return os.path.join(ROOT, "assets", "art", "interiors", b, f"room_{floor}_{room_id}.png")


def _sprite(pid, b=None):
    """La pieza como la usa el interior `b` (con la paleta de sus fondos, tools/interiors/remap_props.py), si existe."""
    from PIL import Image
    own = os.path.join(ROOT, "assets", "art", "interiors", b, "props", pid + ".png") if b else ""
    return Image.open(own if own and os.path.exists(own) else os.path.join(PROPS_ART, pid + ".png")).convert("RGBA")


STATION_ART = {  # puestos sin pieza de la biblioteca: el sprite de su escena (game/visuals/stations/<zona>.tscn)
    "furnace": ("assets/art/interiors/forge/hearth.png", (40, 76)),
    "anvil": ("assets/art/interiors/forge/anvil_stump.png", (32, 52)),
}


def render_floor(b, floor, d=None, upgrades=True, marks=False, dim=False):
    """Una planta a ×1 como la monta el juego: fondos (o suelos de respaldo), piezas por orden de dibujo, paredes."""
    from PIL import Image, ImageDraw
    d = d or load(b)
    cat = catalog()
    lay = Layout(d, cat, upgrades=upgrades)
    cw, ch, ox, oy = canvas_box(d)
    im = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    wh = lay.wall_h
    for room in d["rooms"]:
        if room["floor"] != floor:
            continue
        bp = backdrop_path(b, floor, room["id"])
        if os.path.exists(bp):
            im.alpha_composite(Image.open(bp).convert("RGBA"))
            continue
        tile = _sprite("floor_" + {"stone": "flagstone", "rug": "planks"}.get(room.get("floor_kind", "planks"),
                                                                             room.get("floor_kind", "planks")))
        for (c, r), rid in lay.room_of[floor].items():
            if rid == room["id"]:
                x, y = world(c, r)
                im.alpha_composite(tile, (int(ox + x - 32), int(oy + y - 16)))
        for kind, t, side, behind, front in lay.walls(floor):
            if kind == "back" and front == room["id"]:
                spr = _sprite(f"wall_{room.get('wall_style', 'timber')}_{side}")
                x, y = world(*t)
                left = x if side == "ne" else x - 32
                im.alpha_composite(spr, (int(ox + left), int(oy + y - 16 - wh)))
    draws = []  # (sort y, x, y, sprite)
    for p in lay.placed:
        if p["floor"] != floor:
            continue
        if p["id"] == "_station":
            art = STATION_ART.get(p["zone"].rstrip("_2").replace("_2", ""))
            if art is None:
                continue
            spr = Image.open(os.path.join(ROOT, art[0])).convert("RGBA")
            fx, fy = art[1]
        else:
            pr = cat[p["id"]]
            spr = _sprite(p["id"], b)
            fx, fy = pr["feet"]
            if p.get("flip"):
                spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
                fx = spr.width - fx
        wx, wy = feet_world(p, cat) if p["id"] != "_station" else world(*p["tile"])
        st = lay.step.get((floor, tuple(p["tile"])), 0)
        lift = p.get("lift", 0)
        sx, sy = p.get("shift", [0, 0])
        dy = -st * 8 - lift + sy
        if p.get("hang"):
            dy -= wh // 2
        draws.append((wy + (1 if lift else 0), int(ox + wx - fx + sx), int(oy + wy - fy + dy), spr))
    for s in d.get("stairs", []):
        if s["floor"] != floor:
            continue
        p = {"id": s["prop"], "tile": s["tile"], "flip": s.get("flip", False)}
        pr = cat[s["prop"]]
        spr = _sprite(s["prop"], b)
        fx, fy = pr["feet"]
        if p["flip"]:
            spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
            fx = spr.width - fx
        wx, wy = feet_world(p, cat)
        draws.append((wy, int(ox + wx - fx), int(oy + wy - fy), spr))
    main = main_room(d, floor)  # como en el juego (InteriorStage._main_room): sus paredes de delante, abiertas
    for kind, t, side, behind, front in lay.walls(floor):
        if kind not in ("inner", "door", "low"):
            continue
        x, y = world(*t)
        style = lay.rooms[front or behind].get("wall_style", "timber")
        own = os.path.join(ROOT, "assets", "art", "interiors", b)
        if kind == "low":
            lside = "ne" if side == "sw" else "nw"
            p_own = os.path.join(own, f"low_{floor}_{front}_{lside}.png")
            spr = Image.open(p_own).convert("RGBA") if os.path.exists(p_own) else _sprite("wall_low_" + lside)
            left = x - 32 if side == "sw" else x
            top = y - 12
            draws.append((y + 16, int(ox + left), int(oy + top), spr))
        else:
            p_own = os.path.join(own, f"wall_{floor}_{front}_{side}{'_door' if kind == 'door' else ''}.png")
            pid = f"wall_{style}{'_door' if kind == 'door' else ''}_{side}" + ("_b" if kind == "inner" and (t[0] + t[1]) % 3 == 0 else "")
            spr = Image.open(p_own).convert("RGBA") if os.path.exists(p_own) else _sprite(pid)
            if behind == main:
                spr = spr.copy()
                spr.putalpha(spr.getchannel("A").point(lambda v: v // 4))
            left = x if side == "ne" else x - 32
            draws.append((y - 8, int(ox + left), int(oy + y - 16 - wh), spr))
    for _, x, y, spr in sorted(draws, key=lambda t: (t[0], t[1])):
        im.alpha_composite(spr, (x, y))
    if marks:
        dr = ImageDraw.Draw(im)
        for z in d.get("stations", {}):
            f, (c, r) = lay.stand(z)
            if f == floor:
                x, y = world(c, r)
                dr.ellipse((ox + x - 3, oy + y - 2, ox + x + 3, oy + y + 2), outline=(240, 200, 60))
        for kind, spots in d.get("customers", {}).items():
            for s in spots:
                if s.get("floor", 0) == floor:
                    x, y = world(*s["tile"])
                    dr.ellipse((ox + x - 3, oy + y - 2, ox + x + 3, oy + y + 2),
                               outline=(90, 200, 240) if kind != "queue" else (90, 120, 240))
        for s in d.get("idle", []):
            if s["floor"] == floor:
                x, y = world(*s["tile"])
                dr.ellipse((ox + x - 3, oy + y - 2, ox + x + 3, oy + y + 2), outline=(140, 220, 120))
    if dim:
        dark = Image.new("RGBA", im.size, (10, 8, 20, 150))
        dark.putalpha(Image.eval(im.getchannel("A"), lambda v: 150 if v else 0))
        im.alpha_composite(dark)
    return im


def main_room(d, floor):
    """La sala que queda abierta sin foco (game/interior/interior_stage.gd _main_room)."""
    for t in ("workshop", "yard", "hall", "shop", "kitchen"):
        for r in d["rooms"]:
            if r["floor"] == floor and r["type"] == t:
                return r["id"]
    for r in d["rooms"]:
        if r["floor"] == floor:
            return r["id"]
    return ""


def preview(b, out, upgrades=True, marks=False, k=2):
    """Todas las plantas, de abajo arriba, una junto a otra (a ×k) con su nombre."""
    from PIL import Image, ImageDraw
    d = load(b)
    floors = sorted({r["floor"] for r in d["rooms"]})
    imgs = [render_floor(b, f, d, upgrades, marks) for f in floors]
    W = sum(i.width for i in imgs) + 16 * (len(imgs) + 1)
    H = max(i.height for i in imgs) + 40
    sheet = Image.new("RGBA", (W, H), (26, 18, 9, 255))
    x = 16
    dr = ImageDraw.Draw(sheet)
    names = {-1: "sótano", 0: "planta baja", 1: "planta alta"}
    for f, i in zip(floors, imgs):
        sheet.alpha_composite(i, (x, 30))
        dr.text((x, 8), f"{b} · {names.get(f, f)}", fill=(200, 168, 78))
        x += i.width + 16
    sheet = sheet.resize((sheet.width * k, sheet.height * k), Image.NEAREST)
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    sheet.save(out)
    print(f"vista -> {out}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("validar")
    v.add_argument("ids", nargs="*")
    r = sub.add_parser("reglas")
    r.add_argument("ids", nargs="*")
    pv = sub.add_parser("vista")
    pv.add_argument("id")
    pv.add_argument("--out", default="")
    pv.add_argument("--sin-mejoras", action="store_true")
    pv.add_argument("--marcas", action="store_true")
    t = sub.add_parser("plantilla")
    t.add_argument("id")
    t.add_argument("floor", type=int)
    t.add_argument("--out", default="")
    a = ap.parse_args()
    if a.cmd == "validar":
        errs = []
        cat = catalog()
        for b in a.ids or ids():
            e = validate(b, cat=cat)
            errs += e
            print(f"{b}: {len(e)} errores")
        for e in errs:
            print("  ✖", e)
        sys.exit(1 if errs else 0)
    if a.cmd == "reglas":
        cat = catalog()
        for b in a.ids or ids():
            d = load(b)
            d["resolved"] = resolve(d, cat)
            save(b, d)
            print(f"{b}: {len(d['resolved'])} piezas por reglas")
    elif a.cmd == "vista":
        preview(a.id, a.out or os.path.join(ROOT, "reports", "interiores", f"{a.id}.png"), not a.sin_mejoras, a.marcas)
    else:
        im = template(a.id, a.floor)
        out = a.out or os.path.join(ROOT, "reports", "interiores", f"{a.id}_plantilla_{a.floor}.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        im.save(out)
        print(f"plantilla -> {out}")


if __name__ == "__main__":
    main()
