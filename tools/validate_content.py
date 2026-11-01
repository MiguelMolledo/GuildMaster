#!/usr/bin/env python3
"""Valida las fichas de contenido de GuildMaster (GDD 06; lección L9: nada apunta a algo que no existe).

Comprueba lo que carga el juego en data/ (los ficheros y carpetas que empiezan por _ no):
  - ids en inglés y snake_case, únicos, y que cada fichero se llame como su id;
  - objetos: categoría, peso, pila máxima por categoría, precio > 0, puesto de mercado, ranura;
  - recetas: edificio y puesto que existen, objetos de entrada y salida que existen, duración en horas > 0;
  - edificios: huella, tipo de parcela, puestos (ids únicos, tipo válido);
  - data/time.json (fases en orden, minutes_per_tile >= 1), data/targets.json ([mín, máx]) y cada escenario
    (data/scenarios/: un guardado; cada personaje con posición en una casilla transitable de su mapa; cada edificio
    de tipo conocido, con la huella sobre casillas de edificio, la puerta transitable y pegada, y los puestos de su tipo);
  - mapas (data/maps/): filas y tamaño, códigos que existen en data/tiles.json, spawns en casillas transitables y
    todas las casillas de calle, plaza y puente conectadas entre sí;
  - claves de texto (name_key) en i18n/strings.csv con inglés y español;
  - arte: un icono, sprite o escena que se pide y no existe sale como aviso (con --art-required, error).

Uso:  python3 tools/validate_content.py [--strict] [--art-required] [--quiet]
Código de salida: 0 sin errores, 1 con errores (o avisos con --strict).
"""
import argparse
import csv
import json
import os
import re
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

ID_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
KINDS = ["items", "recipes", "buildings"]
CATEGORY_STACK = {"raw": 99, "material": 50, "product": 20, "tool": 1, "equipment": 1, "consumable": 10, "special": 5}
STALLS = {"resources", "food", "materials", "armory", "clothier", "apothecary", None}
SLOTS = {"tool", "clothes", "accessory"}
PARCEL_TYPES = {"production", "rustic", "housing", "government"}
ZONE_KINDS = {"craft", "sales", "storage", "service"}
NIGHT = {"none", "manual_only", "always"}
PHASES = ["dawn", "day", "dusk", "night"]
ROAD_KINDS = {"street", "plaza", "bridge"}  # la red de calles: debe ser una sola pieza


def check_maps(rep):
    """Valida data/maps/*.json contra data/tiles.json. Devuelve {map_id: (ancho, alto, filas, transitable)}."""
    tiles = (load_json(os.path.join(DATA, "tiles.json"), rep) or {}).get("tiles", {})
    by_char = {}
    for kind, t in tiles.items():
        ch = t.get("char")
        if not (isinstance(ch, str) and len(ch) == 1):
            rep.error(f"tiles.json/{kind}", "char debe ser un solo carácter")
            continue
        if ch in by_char:
            rep.error(f"tiles.json/{kind}", f"el código '{ch}' ya lo usa {by_char[ch]}")
        wc = t.get("walk_cost")
        if wc is not None and (not isinstance(wc, int) or wc < 1):
            rep.error(f"tiles.json/{kind}", "walk_cost debe ser un entero >= 1 o null (bloqueada)")
        by_char[ch] = kind
    out = {}
    for id_, m in load_kind("maps", rep).items():
        w_ = f"maps/{id_}"
        size, rows = m.get("size"), m.get("rows")
        if not (isinstance(size, list) and len(size) == 2 and all(isinstance(x, int) and x > 0 for x in size)):
            rep.error(w_, "size debe ser [ancho, alto]")
            continue
        if not isinstance(rows, list) or len(rows) != size[1]:
            rep.error(w_, f"{len(rows) if isinstance(rows, list) else 0} filas, size dice {size[1]}")
            continue
        bad = False
        for r, row in enumerate(rows):
            if not isinstance(row, str) or len(row) != size[0]:
                rep.error(w_, f"la fila {r} no tiene {size[0]} casillas")
                bad = True
                continue
            for c, ch in enumerate(row):
                if ch not in by_char:
                    rep.error(w_, f"código de casilla desconocido '{ch}' en [{c}, {r}]")
                    bad = True
                    break
        if bad:
            continue

        def walk(c, r):
            return 0 <= c < size[0] and 0 <= r < size[1] and tiles[by_char[rows[r][c]]].get("walk_cost") is not None

        for name, pos in (m.get("spawns") or {}).items():
            if not (isinstance(pos, list) and len(pos) == 2 and all(isinstance(x, int) for x in pos)):
                rep.error(w_, f"spawn {name}: debe ser [col, fila]")
            elif not walk(*pos):
                rep.error(w_, f"spawn {name} {pos} no está en una casilla transitable")
        roads = {(c, r) for r in range(size[1]) for c in range(size[0]) if by_char[rows[r][c]] in ROAD_KINDS}
        if roads:
            first = min(roads, key=lambda t: (t[1], t[0]))
            seen, todo = {first}, [first]
            while todo:
                c, r = todo.pop()
                for n in ((c + 1, r), (c - 1, r), (c, r + 1), (c, r - 1)):
                    if n in roads and n not in seen:
                        seen.add(n)
                        todo.append(n)
            if len(seen) != len(roads):
                lost = sorted(roads - seen, key=lambda t: (t[1], t[0]))
                rep.error(w_, f"{len(lost)} casillas de calle/plaza/puente sueltas de la red (la primera, {list(lost[0])})")
        walk.kind = lambda c, r, rows=rows, size=size: (
            by_char[rows[r][c]] if 0 <= c < size[0] and 0 <= r < size[1] else None)
        out[id_] = walk
    return out


def check_scenario_buildings(where, d, buildings, walk, rep):
    """Cada edificio del escenario: tipo conocido, huella sobre casillas de edificio del mapa, puerta transitable y
    pegada a la huella (sin diagonal), y los mismos puestos que su tipo."""
    for bid, b in (d.get("buildings") or {}).items():
        w = f"{where} {bid}"
        typ = buildings.get(b.get("type"))
        if typ is None:
            rep.error(w, f"tipo de edificio desconocido {b.get('type')}")
            continue
        origin, fp, door = b.get("origin"), b.get("footprint"), b.get("door")
        if not all(isinstance(v, list) and len(v) == 2 and all(isinstance(x, int) for x in v) for v in (origin, fp, door)):
            rep.error(w, "origin, footprint y door deben ser [col, fila]")
            continue
        if fp != typ.get("footprint"):
            rep.error(w, f"huella {fp} distinta de la de su tipo {typ.get('footprint')}")
        cells = {(origin[0] + dc, origin[1] + dr) for dc in range(fp[0]) for dr in range(fp[1])}
        if walk is not None:
            bad = sorted((c for c in cells if walk.kind(*c) != "building"), key=lambda t: (t[1], t[0]))
            if bad:
                rep.error(w, f"{len(bad)} casillas de la huella no son de edificio en el mapa (la primera, {list(bad[0])})")
            if not walk(*door):
                rep.error(w, f"la puerta {door} no es transitable")
        near = {(c + dc, r + dr) for c, r in cells for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1))} - cells
        if tuple(door) not in near:
            rep.error(w, f"la puerta {door} no está pegada a la huella")
        want = {z.get("id") for z in typ.get("zones", [])}
        got = set((b.get("zones") or {}).keys())
        if got != want:
            rep.error(w, f"puestos {sorted(got)} distintos de los de su tipo {sorted(want)}")


class Report:
    def __init__(self, art_required):
        self.errors, self.warnings, self.notes = [], [], []
        self.art_required = art_required

    def error(self, where, msg):
        self.errors.append(f"{where}: {msg}")

    def warn(self, where, msg):
        self.warnings.append(f"{where}: {msg}")

    def art(self, where, path):
        if path and not os.path.exists(os.path.join(ROOT, path.replace("res://", ""))):
            (self.error if self.art_required else self.warn)(where, f"falta el arte {path}")


def load_json(path, rep):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        rep.error(os.path.relpath(path, ROOT), f"no se puede leer: {e}")
        return None


def load_kind(kind, rep):
    out = {}
    folder = os.path.join(DATA, kind)
    if not os.path.isdir(folder):
        return out
    for name in sorted(os.listdir(folder)):
        if name.startswith("_") or not name.endswith(".json"):
            continue
        where = f"{kind}/{name}"
        d = load_json(os.path.join(folder, name), rep)
        if not isinstance(d, dict):
            continue
        id_ = d.get("id", "")
        if not ID_RE.match(str(id_)):
            rep.error(where, f"id «{id_}» no es inglés en snake_case")
        if id_ != name[:-5]:
            rep.error(where, f"el id «{id_}» no coincide con el nombre del fichero")
            continue
        out[id_] = d
    return out


def load_strings(rep):
    path = os.path.join(ROOT, "i18n", "strings.csv")
    keys = {}
    try:
        with open(path, encoding="utf-8", newline="") as f:
            rows = list(csv.reader(f))
    except OSError as e:
        rep.error("i18n/strings.csv", str(e))
        return keys
    if not rows or rows[0][:3] != ["keys", "en", "es"]:
        rep.error("i18n/strings.csv", "la cabecera debe ser keys,en,es")
        return keys
    for i, r in enumerate(rows[1:], start=2):
        if not r:
            continue
        if r[0] in keys:
            rep.error("i18n/strings.csv", f"línea {i}: clave repetida {r[0]}")
        keys[r[0]] = r[1:3] + [""] * (2 - len(r[1:3]))
    return keys


def check_text(where, key, strings, rep):
    if not key:
        rep.error(where, "sin name_key")
    elif key not in strings:
        rep.error(where, f"la clave {key} no está en i18n/strings.csv")
    elif not strings[key][0].strip() or not strings[key][1].strip():
        rep.error(where, f"la clave {key} no tiene texto en inglés y español")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--art-required", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    rep = Report(args.art_required)
    strings = load_strings(rep)
    t = {k: load_kind(k, rep) for k in KINDS}
    items, recipes, buildings = t["items"], t["recipes"], t["buildings"]

    for id_, it in items.items():
        w = f"items/{id_}"
        check_text(w, it.get("name_key"), strings, rep)
        if it.get("gender") not in ("m", "f"):
            rep.error(w, "gender debe ser \"m\" o \"f\" (género en español para «Espada buena» / «Lingote bueno»)")
        cat = it.get("category")
        if cat not in CATEGORY_STACK:
            rep.error(w, f"categoría desconocida {cat}")
        elif it.get("max_stack") != CATEGORY_STACK[cat]:
            rep.warn(w, f"max_stack {it.get('max_stack')} distinto del de su categoría ({CATEGORY_STACK[cat]})")
        if not isinstance(it.get("weight"), (int, float)) or it["weight"] < 0:
            rep.error(w, "peso no válido")
        if not isinstance(it.get("base_price"), (int, float)) or it["base_price"] <= 0:
            rep.error(w, "base_price debe ser > 0")
        if it.get("market_stall") not in STALLS:
            rep.error(w, f"puesto de mercado desconocido {it.get('market_stall')}")
        if "slot" in it and it["slot"] not in SLOTS:
            rep.error(w, f"ranura desconocida {it['slot']}")
        if it.get("icon"):
            rep.art(w, it["icon"])

    for id_, b in buildings.items():
        w = f"buildings/{id_}"
        check_text(w, b.get("name_key"), strings, rep)
        fp = b.get("footprint")
        if not (isinstance(fp, list) and len(fp) == 2 and all(isinstance(x, int) and x > 0 for x in fp)):
            rep.error(w, "footprint debe ser [ancho, alto] en casillas")
        if b.get("parcel_type") not in PARCEL_TYPES:
            rep.error(w, f"tipo de parcela desconocido {b.get('parcel_type')}")
        if b.get("night_production") not in NIGHT:
            rep.error(w, f"night_production desconocido {b.get('night_production')}")
        seen = set()
        for z in b.get("zones", []):
            if z.get("id") in seen:
                rep.error(w, f"puesto repetido {z.get('id')}")
            seen.add(z.get("id"))
            if z.get("kind") not in ZONE_KINDS:
                rep.error(w, f"puesto {z.get('id')}: tipo desconocido {z.get('kind')}")
        if b.get("interior_scene"):
            rep.art(w, b["interior_scene"])
        if isinstance(b.get("sprite"), dict):
            rep.art(w, b["sprite"].get("texture"))

    for id_, r in recipes.items():
        w = f"recipes/{id_}"
        check_text(w, r.get("name_key"), strings, rep)
        b = buildings.get(r.get("building"))
        if b is None:
            rep.error(w, f"edificio desconocido {r.get('building')}")
        elif r.get("zone") not in {z.get("id") for z in b.get("zones", [])}:
            rep.error(w, f"el edificio {r['building']} no tiene el puesto {r.get('zone')}")
        for inp in r.get("inputs", []):
            if inp.get("item") not in items:
                rep.error(w, f"objeto de entrada desconocido {inp.get('item')}")
            if not isinstance(inp.get("qty"), int) or inp["qty"] < 1:
                rep.error(w, f"cantidad no válida para {inp.get('item')}")
        out = r.get("output", {})
        if out.get("item") not in items:
            rep.error(w, f"objeto de salida desconocido {out.get('item')}")
        if not isinstance(r.get("duration_hours"), (int, float)) or r["duration_hours"] <= 0:
            rep.error(w, "duration_hours debe ser > 0 (horas de juego, nunca segundos)")
        if not isinstance(r.get("min_craft"), int) or not 1 <= r["min_craft"] <= 10:
            rep.error(w, "min_craft debe estar entre 1 y 10")
        if r.get("requires_upgrade") and not os.path.isdir(os.path.join(DATA, "upgrades")):
            rep.notes.append(f"{w}: requires_upgrade {r['requires_upgrade']} (las mejoras llegan en H5)")

    maps = check_maps(rep)

    time = load_json(os.path.join(DATA, "time.json"), rep) or {}
    mpt = time.get("minutes_per_tile")
    if not isinstance(mpt, int) or mpt < 1:
        rep.error("time.json", "minutes_per_tile debe ser un entero >= 1 (minutos de juego por casilla)")
    for k in ["seasons", "days_per_season", "real_seconds_per_day", "phase_starts", "start_minute"]:
        if k not in time:
            rep.error("time.json", f"falta {k}")
    for s in time.get("seasons", []):
        st = time.get("phase_starts", {}).get(s)
        if not st:
            rep.error("time.json", f"faltan las fases de {s}")
            continue
        vals = [st.get(p) for p in PHASES]
        if not all(isinstance(v, int) and 0 <= v < 1440 for v in vals) or vals != sorted(vals):
            rep.error("time.json", f"{s}: las fases deben ir en orden dawn < day < dusk < night (minutos del día)")

    targets = load_json(os.path.join(DATA, "targets.json"), rep) or {}
    for bot, measures in targets.items():
        if bot.startswith("_"):
            continue
        for m, rng in measures.items():
            if not (isinstance(rng, list) and len(rng) == 2):
                rep.error("targets.json", f"{bot}.{m} debe ser [mín, máx]")

    sc_dir = os.path.join(DATA, "scenarios")
    for name in sorted(os.listdir(sc_dir)) if os.path.isdir(sc_dir) else []:
        if name.startswith("_") or not name.endswith(".json"):
            continue
        d = load_json(os.path.join(sc_dir, name), rep)
        if isinstance(d, dict) and (not isinstance(d.get("version"), int) or "minute" not in d.get("clock", {})):
            rep.error(f"scenarios/{name}", "no es un guardado (falta version o clock.minute)")
        if not isinstance(d, dict):
            continue
        map_id = d.get("map_id", "")
        if map_id and map_id not in maps:
            rep.error(f"scenarios/{name}", f"mapa desconocido {map_id}")
            continue
        check_scenario_buildings(f"scenarios/{name}", d, buildings, maps.get(map_id), rep)
        for cid, ch in (d.get("characters") or {}).items():
            pos = ch.get("position")
            if pos is None:
                continue
            if not map_id:
                rep.error(f"scenarios/{name}", f"{cid} tiene posición pero el escenario no tiene mapa")
            elif not (isinstance(pos, list) and len(pos) == 2 and all(isinstance(x, int) for x in pos)):
                rep.error(f"scenarios/{name}", f"{cid}: position debe ser [col, fila]")
            elif not maps[map_id](*pos):
                rep.error(f"scenarios/{name}", f"{cid} está en {pos}, que no es una casilla transitable de {map_id}")
            for t in (ch.get("path") or []) if map_id else []:
                if not (isinstance(t, list) and len(t) == 2 and maps[map_id](*t)):
                    rep.error(f"scenarios/{name}", f"{cid}: la ruta pasa por {t}, que no es transitable")
                    break

    if not args.quiet:
        for n in rep.notes:
            print("  ·", n)
    for w in rep.warnings:
        print("  !", w)
    for e in rep.errors:
        print("  ✖", e)
    counts = ", ".join([f"{len(t[k])} {k}" for k in KINDS] + [f"{len(maps)} maps"])
    print(f"validate_content: {counts} · {len(rep.errors)} errores, {len(rep.warnings)} avisos")
    return 1 if rep.errors or (args.strict and rep.warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
