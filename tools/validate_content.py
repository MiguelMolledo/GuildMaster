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
  - H3: puestos y tablón de cada mapa (casilla stall/board con su casilla de servicio transitable y pegada), edificios
    iniciales del mapa ("buildings"), data/market.json, data/difficulty.json, data/ai_profiles/, data/starts/,
    data/objectives/ y data/contracts/ (todo lo que nombran existe); en los escenarios, el oro en la familia (no en
    los personajes) y la ubicación de cada personaje en un edificio que existe;
  - H4: data/employees.json (rangos, roles, lealtad, bandas, salarios, robo, contratación, horario), la población de
    cada mapa (casas de tipo residencial del mapa, rango y atributos de cada vecino) y, en los escenarios v5, la casa,
    el rango y el empleo de cada personaje, los huecos y la cola de cada edificio;
  - H5: data/upgrade_rules.json y data/upgrades/<árbol>/ (rama y nivel, coste, requisitos que existen en su árbol,
    nivel N pide el N-1, sin ciclos, efectos de tipos conocidos, puestos nuevos como un puesto del edificio, recetas
    desbloqueadas coherentes, visuales como ids) y, en los escenarios v6, mejoras, obra en curso e inspecciones;
  - H8: data/family.json, data/goals.json, data/score.json y, en los escenarios v7, edades y parentesco;
  - H7: data/town.json (rutina, actividades, emociones, acciones, mostrador, microeventos, población), data/microevents/
    (opciones, opción por defecto, efectos y condiciones conocidos), data/social_phrases.json, la palanca
    microevent_chance, los puntos sociales y oficios de cada mapa y, en los escenarios v8, oficio, memoria de la
    ciudad, emociones y microeventos;
  - tutorial (docs/ui/05_tutorial.md): data/tutorial.json y data/tutorial/ (disparadores conocidos, textos con sus
    huecos, objetivos de resaltado con forma válida, abridores, pistas, con qué partida se prueba cada capítulo);
  - H12: data/professions/ (clase, taller, herramienta, inicio y tabla de encargos coherentes: lo que pide la tabla
    lo fabrica el taller), los competidores de cada inicio (perfil, solar del mapa de su tipo, oficio, sin repetir
    solar ni pisar otro solar usado) y que el inicio de cada oficio ponga al protagonista en su taller con su herramienta; cada puesto de
    oficio con su rol de empleado;
  - claves de texto (name_key) en i18n/strings.csv con inglés y español;
  - i18n/strings.csv leído como CSV: 3 columnas por registro y ninguna clave con salto de línea, comilla o espacios;
  - estructura (tools/validate_structure.py): data/ sin rutas a ficheros, nombres de assets en minúsculas, inventario
    (estado >= sprite con su fichero), una escena en game/visuals/ por edificio, interior con un Marker2D por puesto y
    los nodos de las mejoras, data/audio.json y sus buses, y uid en cada .tscn/.tres.

Uso:  python3 tools/validate_content.py [--strict] [--art-required] [--quiet]
Código de salida: 0 sin errores, 1 con errores (o avisos con --strict).
"""
import argparse
import csv
import json
import os
import re
import sys

import validate_structure
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_games import check_games  # noqa: E402  juegos (04f §4.26)
import validate_fiestas  # fiestas (04f 4.25): data/festivals.json and its contracts

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

ID_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
KINDS = ["items", "recipes", "buildings"]
CATEGORY_STACK = {"raw": 99, "material": 50, "product": 20, "tool": 1, "equipment": 1, "consumable": 10, "special": 5}
STALLS = {"resources", "food", "materials", "armory", "clothier", "apothecary", "goods", None}  # H12: goods (enseres) [provisional]
SLOTS = {"tool", "clothes", "accessory"}
PARCEL_TYPES = {"production", "rustic", "housing", "government"}
DIFFICULTIES = ["easy", "normal", "hard"]
DIFF_LEVERS = {"start_debt": int, "rival_craft": int, "rival_sell_min_demand": (int, float), "buy_price_mult": (int, float),
               "microevent_chance": (int, float)}
STATS = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution", "rhetoric", "stealth"]
MATCH_OPS = {"gte", "lte", "ne"}
ZONE_KINDS = {"craft", "sales", "storage", "service"}
NIGHT = {"none", "manual_only", "always", "employees"}  # posada: employees = sus empleados trabajan de noche (4.22.4.5)
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

        def walk(c, r, rows=rows, size=size):  # bound now: one walk per map (data/maps has several)
            return 0 <= c < size[0] and 0 <= r < size[1] and tiles[by_char[rows[r][c]]].get("walk_cost") is not None

        for name, pos in (m.get("spawns") or {}).items():
            if not (isinstance(pos, list) and len(pos) == 2 and all(isinstance(x, int) for x in pos)):
                rep.error(w_, f"spawn {name}: debe ser [col, fila]")
            elif not walk(*pos):
                rep.error(w_, f"spawn {name} {pos} no está en una casilla transitable")
        def is_pos(p):
            return isinstance(p, list) and len(p) == 2 and all(isinstance(x, int) for x in p)

        def adjacent(a, b):
            return abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1

        services = [(f"puesto {k}", v, "stall") for k, v in (m.get("stalls") or {}).items()]
        if m.get("board") is not None:
            services.append(("tablón", m["board"], "board"))
        for name, s, kind in services:
            t, sv = (s or {}).get("tile"), (s or {}).get("service")
            if not (is_pos(t) and is_pos(sv)):
                rep.error(w_, f"{name}: tile y service deben ser [col, fila]")
                continue
            if not (0 <= t[0] < size[0] and 0 <= t[1] < size[1]) or by_char[rows[t[1]][t[0]]] != kind:
                rep.error(w_, f"{name}: la casilla {t} no es de tipo {kind}")
            if not walk(*sv):
                rep.error(w_, f"{name}: la casilla de servicio {sv} no es transitable")
            elif not adjacent(t, sv):
                rep.error(w_, f"{name}: la casilla de servicio {sv} no está pegada a {t}")
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
        walk.map = m
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
        for u in b.get("upgrades") or []:  # H5: new stations of finished upgrades (new_zone)
            want |= {e.get("zone") for e in UPGRADES.get(u, {}).get("effects", []) if e.get("kind") == "new_zone"}
        got = set((b.get("zones") or {}).keys())
        if got != want:
            rep.error(w, f"puestos {sorted(got)} distintos de los de su tipo {sorted(want)}")


def check_map_buildings(maps, buildings, rep):
    """Los edificios iniciales de cada mapa ("buildings", GDD 06): tipo conocido, huella sobre casillas de edificio y
    puerta transitable y pegada; owner, si está, "" (público) y entonces su tipo es public."""
    for id_, walk in maps.items():
        for key, b in (walk.map.get("buildings") or {}).items():
            w = f"maps/{id_} buildings.{key}"
            typ = buildings.get(b.get("type"))
            if typ is None:
                rep.error(w, f"tipo de edificio desconocido {b.get('type')}")
                continue
            if "owner" in b and (b["owner"] != "" or not typ.get("public")):
                rep.error(w, "owner solo puede ser \"\" y en un tipo public")
            check_scenario_buildings(w, {"buildings": {key: dict(b, footprint=typ.get("footprint"),
                zones={z.get("id"): {} for z in typ.get("zones", [])})}}, buildings, walk, rep)


def check_h3(items, recipes, buildings, maps, strings, rep):
    """Datos de H3 (docs/contratos/h3_mercado.md): mercado, dificultad, perfiles de IA, inicios, objetivos, encargos."""
    market = load_json(os.path.join(DATA, "market.json"), rep) or {}
    stalls = market.get("stalls") or {}
    for sid, s in stalls.items():
        w = f"market.json stalls.{sid}"
        if sid not in STALLS:
            rep.error(w, "puesto desconocido (los de data/items market_stall)")
        check_text(w, s.get("name_key"), strings, rep)
        if s.get("kind") not in ("outdoor", "shop"):
            rep.error(w, "kind debe ser outdoor o shop")
        for v in s.get("sells") or []:
            if v not in STALLS:
                rep.error(w, f"vende un market_stall desconocido {v}")
        if s.get("kind") == "shop":
            b = buildings.get(s.get("building"))
            if b is None:
                rep.error(w, f"edificio desconocido {s.get('building')}")
            elif b.get("market_stall") != sid or not b.get("public"):
                rep.error(w, f"el edificio {s['building']} debe ser public y tener market_stall {sid}")
        elif s.get("kind") == "outdoor":
            for mid, walk in maps.items():
                if sid not in (walk.map.get("stalls") or {}):
                    rep.warn(w, f"el mapa {mid} no tiene este puesto")
    for mid, walk in maps.items():
        for sid in (walk.map.get("stalls") or {}):
            if stalls.get(sid, {}).get("kind") != "outdoor":
                rep.error(f"maps/{mid}", f"puesto {sid}: no es un puesto exterior de data/market.json")
    for b_id, b in buildings.items():
        if b.get("market_stall") is not None and stalls.get(b["market_stall"], {}).get("building") != b_id:
            rep.error(f"buildings/{b_id}", f"market_stall {b['market_stall']} no apunta a este edificio en market.json")
    if any(p not in PHASES for p in market.get("open_phases", [])) or not market.get("open_phases"):
        rep.error("market.json", "open_phases: fases de data/time.json")
    dem = market.get("demand") or {}
    if not all(isinstance(dem.get(k), (int, float)) for k in ("start", "rest", "min", "max", "drop_per_unit", "recover_per_day")):
        rep.error("market.json", "demand: faltan start, rest, min, max, drop_per_unit o recover_per_day")
    elif not dem["min"] <= dem["rest"] <= dem["max"] or not dem["min"] <= dem["start"] <= dem["max"]:
        rep.error("market.json", "demand: start y rest deben estar en [min, max]")
    if not isinstance(market.get("sell_ratio"), (int, float)) or not 0 < market["sell_ratio"] <= 1:
        rep.error("market.json", "sell_ratio debe estar en (0, 1]")
    qm = market.get("quality_mult")
    if not (isinstance(qm, list) and len(qm) == 3 and all(isinstance(x, (int, float)) and x > 0 for x in qm)):
        rep.error("market.json", "quality_mult: 3 multiplicadores (normal, buena, excelente)")
    er = market.get("errand") or {}
    if not isinstance(er.get("surcharge"), (int, float)) or not isinstance(er.get("hours"), (int, float)) or er["hours"] <= 0:
        rep.error("market.json", "errand: surcharge y hours (horas de juego > 0)")
    bd = market.get("board") or {}
    for k in ("max_open", "new_per_dawn", "max_accepted_per_family"):
        if not isinstance(bd.get(k), int) or bd[k] < 0:
            rep.error("market.json", f"board.{k} debe ser un entero >= 0")

    diff = load_json(os.path.join(DATA, "difficulty.json"), rep) or {}
    levels = diff.get("levels") or {}
    if diff.get("default") not in DIFFICULTIES:
        rep.error("difficulty.json", "default debe ser easy, normal o hard")
    for lvl in DIFFICULTIES:
        L = levels.get(lvl)
        if not isinstance(L, dict):
            rep.error("difficulty.json", f"falta el nivel {lvl}")
            continue
        check_text(f"difficulty.json {lvl}", L.get("name_key"), strings, rep)
        for k, typ in DIFF_LEVERS.items():
            if not isinstance(L.get(k), typ) or L[k] < 0:
                rep.error("difficulty.json", f"{lvl}.{k} falta o no es válido")

    profiles = load_kind("ai_profiles", rep)
    for pid, pr in profiles.items():
        w = f"ai_profiles/{pid}"
        if not isinstance(pr.get("sell_min_demand"), (int, float)) or not isinstance(pr.get("gold_reserve"), int):
            rep.error(w, "sell_min_demand (número) y gold_reserve (entero) obligatorios")
        if pr.get("work_mode") not in (None, "fast", "normal", "careful"):
            rep.error(w, f"work_mode desconocido {pr.get('work_mode')}")
        for p_ in pr.get("work_phases") or []:
            if p_ not in PHASES:
                rep.error(w, f"work_phases: fase desconocida {p_}")

    objectives = load_kind("objectives", rep)
    for oid, o in objectives.items():
        w = f"objectives/{oid}"
        check_text(w, o.get("name_key"), strings, rep)
        conds = o.get("conditions")
        if not (isinstance(conds, list) and conds):
            rep.error(w, "conditions: al menos una")
            continue
        for c in conds:
            if not isinstance(c.get("event"), str) or not c["event"]:
                rep.error(w, "cada condición necesita event")
            if not isinstance(c.get("match", {}), dict):
                rep.error(w, "match debe ser un objeto")
            else:
                for k, v in c.get("match", {}).items():
                    if isinstance(v, dict) and not set(v) <= MATCH_OPS:
                        rep.error(w, f"match.{k}: operadores válidos {sorted(MATCH_OPS)}")
            if not isinstance(c.get("count"), int) or c["count"] < 1:
                rep.error(w, "count debe ser un entero >= 1")

    contract_tables = {k: v for k, v in load_kind("contracts", rep).items() if v.get("kind") != "festival"}  # 4.25.4
    for cid, ct in contract_tables.items():
        w = f"contracts/{cid}"
        clients = ct.get("clients") or []
        if not clients:
            rep.error(w, "sin clients")
        for cl in clients:
            check_text(f"{w} client {cl.get('id')}", cl.get("name_key"), strings, rep)
        for it in ct.get("items") or []:
            if it.get("item") not in items:
                rep.error(w, f"objeto desconocido {it.get('item')}")
            elif not any(r.get("output", {}).get("item") == it["item"] for r in recipes.values()):
                rep.error(w, f"ninguna receta produce {it['item']}")
            q = it.get("qty")
            if not (isinstance(q, list) and len(q) == 2 and all(isinstance(x, int) for x in q) and 1 <= q[0] <= q[1]):
                rep.error(w, f"{it.get('item')}: qty debe ser [mín, máx] con 1 <= mín <= máx")
        dd = ct.get("deadline_days")
        if not (isinstance(dd, list) and len(dd) == 2 and all(isinstance(x, int) for x in dd) and 1 <= dd[0] <= dd[1]):
            rep.error(w, "deadline_days debe ser [mín, máx] en días")
        for k in ("premium", "reward_reputation", "reward_relation", "fail_reputation", "fail_relation", "client_cooldown_days"):
            if not isinstance(ct.get(k), (int, float)):
                rep.error(w, f"falta {k}")
        if any(q not in (1, 2) for q in ct.get("min_qualities") or [None]):
            rep.error(w, "min_qualities: calidades 1 (buena) o 2 (excelente)")

    for sid, s in load_kind("starts", rep).items():
        w = f"starts/{sid}"
        check_text(w, s.get("name_key"), strings, rep)
        walk = maps.get(s.get("map"))
        if walk is None:
            rep.error(w, f"mapa desconocido {s.get('map')}")
        sites = (walk.map.get("buildings") or {}) if walk else {}
        if (s.get("start") or {}).get("phase") not in PHASES:
            rep.error(w, "start.phase debe ser una fase")
        pr = s.get("protagonist") or {}
        stats = pr.get("stats") or {}
        if sorted(stats) != sorted(STATS):
            rep.error(w, "protagonist.stats: los 10 atributos")
        if not isinstance(pr.get("free_points"), int) or pr["free_points"] < 0:
            rep.error(w, "protagonist.free_points debe ser un entero >= 0")
        if walk and pr.get("spawn") not in (walk.map.get("spawns") or {}):
            rep.error(w, f"protagonist.spawn {pr.get('spawn')} no es un spawn del mapa")
        for slot, e in (pr.get("equipment") or {}).items():
            it = items.get((e or {}).get("item"))
            if it is None or it.get("slot") != slot:
                rep.error(w, f"equipment.{slot}: objeto desconocido o de otra ranura")
        if not isinstance((s.get("family") or {}).get("gold"), int):
            rep.error(w, "family.gold debe ser un entero")
        blds = [("building", s.get("building") or {})]
        rv = s.get("rival")
        if rv:
            blds.append(("rival.building", rv.get("building") or {}))
            if rv.get("profile") not in profiles:
                rep.error(w, f"rival.profile desconocido {rv.get('profile')}")
            if sorted((rv.get("character") or {}).get("stats") or {}) != sorted(STATS):
                rep.error(w, "rival.character.stats: los 10 atributos")
        for name, b in blds:
            site = sites.get(b.get("site"))
            if site is None:
                rep.error(w, f"{name}.site {b.get('site')} no es un edificio del mapa")
            elif site.get("type") != b.get("type"):
                rep.error(w, f"{name}: tipo {b.get('type')} distinto del del mapa {site.get('type')}")
            for st in b.get("inventory") or []:
                if st.get("item") not in items:
                    rep.error(w, f"{name}: objeto desconocido {st.get('item')}")
        ln = s.get("loan") or {}
        for k in ("term_days", "extension_seasons"):
            if not isinstance(ln.get(k), int) or ln[k] < 1:
                rep.error(w, f"loan.{k} debe ser un entero >= 1")
        tables_items = {it.get("item") for ct in contract_tables.values() for it in ct.get("items") or []}
        tables_clients = {cl.get("id") for ct in contract_tables.values() for cl in ct.get("clients") or []}
        for c in s.get("contracts") or []:
            if c.get("item") not in items:
                rep.error(w, f"encargo {c.get('script')}: objeto desconocido {c.get('item')}")
            elif c["item"] not in tables_items:
                rep.warn(w, f"encargo {c.get('script')}: {c['item']} no sale en ninguna tabla de data/contracts")
            if c.get("client") not in tables_clients:
                rep.error(w, f"encargo {c.get('script')}: cliente desconocido {c.get('client')}")
        for o in s.get("objectives") or []:
            if o not in objectives:
                rep.error(w, f"objetivo desconocido {o}")
        df = s.get("defaults") or {}
        if not (isinstance(df.get("name"), str) and df["name"].strip() and isinstance(df.get("family_name"), str)
                and df["family_name"].strip() and isinstance(df.get("female"), bool)):
            rep.error(w, "defaults: name, family_name (texto) y female (bool)")
        if not all(re.fullmatch(r"#[0-9a-fA-F]{6}", str((df.get("colors") or {}).get(k, ""))) for k in ("primary", "secondary")):
            rep.error(w, "defaults.colors: primary y secondary en #rrggbb")

    # H3 · cuentas (data/accounts.json): retenciones, avisos del préstamo y mantenimiento impagado (D15)
    acc = load_json(os.path.join(DATA, "accounts.json"), rep) or {}
    for k in ("ledger_detail_years", "ledger_days_view", "notices_keep_years", "upkeep_damage_days"):
        if not isinstance(acc.get(k), int) or acc[k] < 1:
            rep.error("accounts.json", f"{k} debe ser un entero >= 1")
    wd = acc.get("loan_warn_days")
    if not (isinstance(wd, list) and wd and all(isinstance(d, int) and d >= 1 for d in wd)):
        rep.error("accounts.json", "loan_warn_days: lista de días enteros >= 1")


def check_h4(buildings, recipes, maps, strings, rep):
    """Datos de H4 (docs/contratos/h4_empleados.md): data/employees.json y la población de cada mapa.
    Devuelve (rangos, roles) para comprobar los escenarios."""
    w = "employees.json"
    emp = load_json(os.path.join(DATA, "employees.json"), rep) or {}
    ranks = emp.get("ranks") or {}
    order = emp.get("rank_order") or []
    if sorted(order) != sorted(ranks) or not order:
        rep.error(w, "rank_order debe nombrar todos los rangos de ranks, una vez cada uno")
    for rid, r in ranks.items():
        wr = f"{w} ranks.{rid}"
        check_text(wr, r.get("name_key"), strings, rep)
        if not ID_RE.match(rid):
            rep.error(wr, "id en snake_case")
        if not isinstance(r.get("wage"), int) or r["wage"] < 0:
            rep.error(wr, "wage: oro por día, entero >= 0")
        for k in ("efficiency", "speed"):
            if not isinstance(r.get(k), (int, float)) or r[k] <= 0:
                rep.error(wr, f"{k} debe ser > 0")
        nxt = r.get("next", "")
        if nxt and nxt not in ranks:
            rep.error(wr, f"next desconocido {nxt}")
        if nxt:
            if not isinstance(r.get("promote_after_days"), int) or r["promote_after_days"] < 1:
                rep.error(wr, "promote_after_days: días enteros >= 1 (1 año = 8 días)")
            if not isinstance(r.get("promote_min_loyalty"), int) or not 0 <= r["promote_min_loyalty"] <= 100:
                rep.error(wr, "promote_min_loyalty en [0, 100]")
        if not isinstance(r.get("requires_upgrade", ""), str):
            rep.error(wr, "requires_upgrade: id de mejora o \"\"")
    for a, b in zip(order, order[1:]):
        if ranks.get(a, {}).get("next") != b:
            rep.error(w, f"rank_order: {a} debería ascender a {b}")
    roles = emp.get("roles") or {}
    zones = {z.get("id") for b in buildings.values() for z in b.get("zones", [])}
    for rid, r in roles.items():
        check_text(f"{w} roles.{rid}", r.get("name_key"), strings, rep)
        if rid != "any" and rid not in zones:
            rep.error(w, f"rol {rid}: no es un puesto de ningún edificio (ni any)")
    if "any" not in roles:
        rep.error(w, "falta el rol any (cualquiera, 4.7.4)")
    if emp.get("default_role") not in roles:
        rep.error(w, "default_role debe ser un rol")
    loy = emp.get("loyalty") or {}
    for k in ("min", "max", "start", "wage_paid", "wage_unpaid", "bonus", "promotion_accepted", "promotion_refused",
              "building_damaged", "facade_upgrade", "dining_upgrade"):
        if not isinstance(loy.get(k), int):
            rep.error(w, f"loyalty.{k} debe ser un entero")
    if isinstance(loy.get("min"), int) and isinstance(loy.get("max"), int):
        if not loy["min"] <= loy.get("start", -1) <= loy["max"]:
            rep.error(w, "loyalty.start debe estar entre min y max")
        covered = set()
        for b in emp.get("bands") or []:
            wb = f"{w} bands.{b.get('id')}"
            if not (isinstance(b.get("min"), int) and isinstance(b.get("max"), int) and b["min"] <= b["max"]):
                rep.error(wb, "min y max enteros, min <= max")
                continue
            span = set(range(b["min"], b["max"] + 1))
            if span & covered:
                rep.error(wb, "se solapa con otra banda")
            covered |= span
            for k in ("quit_chance", "theft_chance"):
                if not isinstance(b.get(k), (int, float)) or not 0 <= b[k] <= 1:
                    rep.error(wb, f"{k}: probabilidad por día en [0, 1]")
            if not isinstance(b.get("efficiency_mult"), (int, float)) or b["efficiency_mult"] <= 0:
                rep.error(wb, "efficiency_mult debe ser > 0")
            if not isinstance(b.get("rumor_reputation"), int):
                rep.error(wb, "rumor_reputation debe ser un entero")
        if covered != set(range(loy["min"], loy["max"] + 1)):
            rep.error(w, "las bandas deben cubrir toda la lealtad de min a max")
    if not isinstance(emp.get("bonus_gold"), int) or emp["bonus_gold"] < 1:
        rep.error(w, "bonus_gold: entero >= 1")
    th = emp.get("theft") or {}
    u = th.get("units")
    if not (isinstance(u, list) and len(u) == 2 and all(isinstance(x, int) for x in u) and 1 <= u[0] <= u[1]):
        rep.error(w, "theft.units: [mín, máx] enteros >= 1")
    for k in ("security_divisor", "no_rehire_days"):
        if not isinstance(th.get(k), int) or th[k] < 1:
            rep.error(w, f"theft.{k}: entero >= 1")
    wg = emp.get("wages") or {}
    if not isinstance(wg.get("grace_days"), int) or wg["grace_days"] < 0:
        rep.error(w, "wages.grace_days: entero >= 0")
    if not isinstance(wg.get("unpaid_reputation"), int):
        rep.error(w, "wages.unpaid_reputation: entero")
    fi = emp.get("fire") or {}
    if not isinstance(fi.get("reputation_loyalty_over"), int) or not isinstance(fi.get("reputation"), int):
        rep.error(w, "fire: reputation_loyalty_over y reputation enteros")
    if not isinstance((emp.get("hire") or {}).get("start_after_days"), int) or emp["hire"]["start_after_days"] < 0:
        rep.error(w, "hire.start_after_days: entero >= 0")
    sch = emp.get("schedule") or {}
    for k in ("leave_home_phase", "go_home_phase"):
        if sch.get(k) not in PHASES:
            rep.error(w, f"schedule.{k}: una fase ({', '.join(PHASES)})")
    wp = sch.get("work_phases")
    if not (isinstance(wp, list) and wp and all(p in PHASES for p in wp)) or "night" in (wp or []):
        rep.error(w, "schedule.work_phases: fases sin night (los empleados nunca trabajan de noche, 4.4.3)")
    d = sch.get("leave_home_delay_minutes")
    if not (isinstance(d, list) and len(d) == 2 and all(isinstance(x, int) for x in d) and 0 <= d[0] <= d[1]):
        rep.error(w, "schedule.leave_home_delay_minutes: [mín, máx] minutos enteros >= 0")

    for id_, walk in maps.items():
        sites = walk.map.get("buildings") or {}
        homes = set()
        for i, hh in enumerate(walk.map.get("population") or []):
            wh = f"maps/{id_} population[{i}]"
            site = sites.get(hh.get("home"))
            if site is None:
                rep.error(wh, f"home {hh.get('home')} no es un edificio del mapa")
            elif buildings.get(site.get("type"), {}).get("category") != "residence":
                rep.error(wh, f"home {hh.get('home')} no es una residencia (tipo {site.get('type')})")
            if hh.get("home") in homes:
                rep.error(wh, f"la casa {hh.get('home')} ya tiene otra familia")
            homes.add(hh.get("home"))
            # docs/contratos/poblacion.md «Varias ciudades»: a household of a generated town may bring only gold and
            # its members' rank and stats; the cast gives surname, colours, names, sex, age and look (fixed cast too)
            if "family_name" in hh and not (isinstance(hh.get("family_name"), str) and hh["family_name"].strip()):
                rep.error(wh, "family_name: texto")
            if not isinstance(hh.get("gold"), int) or hh["gold"] < 0:
                rep.error(wh, "gold: entero >= 0")
            if "colors" in hh and not all(re.fullmatch(r"#[0-9a-fA-F]{6}", str((hh.get("colors") or {}).get(k, ""))) for k in ("primary", "secondary")):
                rep.error(wh, "colors: primary y secondary en #rrggbb")
            if not hh.get("members"):
                rep.error(wh, "una casa sin vecinos")
            for p in hh.get("members") or []:
                wp_ = f"{wh} {p.get('name')}"
                if ("name" in p or "female" in p) and not (isinstance(p.get("name"), str) and p["name"].strip()
                                                         and isinstance(p.get("female"), bool)):
                    rep.error(wp_, "name (texto) y female (bool), o ninguno de los dos (los pone el reparto)")
                if p.get("rank") not in ranks:
                    rep.error(wp_, f"rango desconocido {p.get('rank')}")
                stt = p.get("stats") or {}
                if sorted(stt) != sorted(STATS) or not all(isinstance(v, int) and 1 <= v <= 10 for v in stt.values()):
                    rep.error(wp_, "stats: los 10 atributos, enteros en [1, 10]")
    return ranks, roles


def check_h4_scenario(where, d, buildings, ranks, roles, recipes, rep):
    """Escenarios v5: casa, rango y empleo de cada personaje; huecos y cola de cada edificio."""
    blds = d.get("buildings") or {}
    for cid, ch in (d.get("characters") or {}).items():
        w = f"{where} {cid}"
        for k in ("home", "rank", "job", "hire_bans", "routine"):
            if k not in ch:
                rep.error(w, f"falta {k} (guardado v5)")
        home = ch.get("home", "")
        if home and (home not in blds or buildings.get(blds[home].get("type"), {}).get("category") != "residence"):
            rep.error(w, f"home {home} no es una casa del escenario")
        if ch.get("rank", "") and ch["rank"] not in ranks:
            rep.error(w, f"rango desconocido {ch['rank']}")
        job = ch.get("job")
        if job is not None:
            if not isinstance(job, dict) or job.get("building") not in blds:
                rep.error(w, "job.building no es un edificio del escenario")
                continue
            if not ch.get("rank"):
                rep.error(w, "un empleado necesita rango")
            zones = set((blds[job["building"]].get("zones") or {}).keys())
            if job.get("role") not in roles or (job.get("role") != "any" and job.get("role") not in zones):
                rep.error(w, f"job.role {job.get('role')}: ni any ni un puesto de su edificio")
            for k in ("loyalty", "hired_day", "start_day", "end_day", "days_worked", "rank_days", "unpaid_days"):
                if not isinstance(job.get(k), int):
                    rep.error(w, f"job.{k} debe ser un entero")
            if not isinstance(job.get("promotion_offered"), bool):
                rep.error(w, "job.promotion_offered debe ser bool")
    for bid, b in blds.items():
        w = f"{where} {bid}"
        n = sum(1 for ch in (d.get("characters") or {}).values()
                if isinstance(ch.get("job"), dict) and ch["job"].get("building") == bid)
        if not isinstance(b.get("employee_slots"), int) or b["employee_slots"] < 0:
            rep.error(w, "employee_slots: entero >= 0 (guardado v5)")
        elif n > b["employee_slots"]:
            rep.error(w, f"{n} empleados y solo {b['employee_slots']} huecos")
        q = b.get("queue")
        if not (isinstance(q, dict) and isinstance(q.get("entries"), list) and isinstance(q.get("loop"), bool)
                and isinstance(q.get("paused"), bool)):
            rep.error(w, "queue: {entries: [], loop: bool, paused: bool} (guardado v5)")
            continue
        for e in q["entries"]:
            r = recipes.get(e.get("recipe"))
            if r is None or r.get("building") != b.get("type"):
                rep.error(w, f"cola: receta {e.get('recipe')} no es de un {b.get('type')}")
            if not (isinstance(e.get("qty"), int) and (e["qty"] >= 1 or e["qty"] == -1)):
                rep.error(w, "cola: qty entero >= 1 o -1 (infinito)")
            if not isinstance(e.get("done"), int) or e["done"] < 0 or not isinstance(e.get("id"), str):
                rep.error(w, "cola: id (texto) y done (entero >= 0)")


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


UPGRADES = {}  # H5: id -> upgrade (data/upgrades/<tree>/<id>.json), loaded first in main()
EFFECT_VALUES = {"mult", "amount", "zone", "recipe", "rank", "flag"}
EFFECT_STACKS = {"branch_top", "all"}
EFFECT_WHEN = {"query", "complete"}
EFFECT_READERS = {"production", "market", "counter", "staff", "inspections", "inventory", "family", "none", "inn"}


def load_upgrades(rep):
    """data/upgrades/<árbol>/<id>.json: una carpeta por árbol (el nombre de la carpeta es el árbol)."""
    out = {}
    root = os.path.join(DATA, "upgrades")
    for tree in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        folder = os.path.join(root, tree)
        if tree.startswith("_") or not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if name.startswith("_") or not name.endswith(".json"):
                continue
            where = f"upgrades/{tree}/{name}"
            d = load_json(os.path.join(folder, name), rep)
            if not isinstance(d, dict):
                continue
            id_ = d.get("id", "")
            if not ID_RE.match(str(id_)):
                rep.error(where, f"id «{id_}» no es inglés en snake_case")
            if id_ != name[:-5]:
                rep.error(where, f"el id «{id_}» no coincide con el nombre del fichero")
                continue
            if d.get("tree") != tree:
                rep.error(where, f"tree {d.get('tree')} distinto de su carpeta {tree}")
                continue
            if id_ in out:
                rep.error(where, f"id repetido en otro árbol ({out[id_]['tree']})")
                continue
            out[id_] = d
    return out


PHASES = ["dawn", "day", "dusk", "night"]
STAT_IDS = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution", "rhetoric",
            "stealth"]


def check_h8(strings, rep):
    """H8 (GDD 4.2.5, 4.10, 4.17, docs/contratos/h8_familia.md): data/family.json (edades, cortejo, hijos, paleta,
    grupo, rutina, directivas, nombres), data/goals.json y data/score.json, con sus claves de texto. Devuelve los
    tonos de pelo y piel (para los escenarios)."""
    w = "family.json"
    fam = load_json(os.path.join(DATA, "family.json"), rep) or {}
    life = fam.get("life", {})
    ages = [life.get(k) for k in ("school_age", "apprentice_age", "majority_age")]
    if not all(isinstance(a, int) for a in ages) or not ages[0] < ages[1] < ages[2]:
        rep.error(w, "life: school_age < apprentice_age < majority_age (años enteros)")
    for d in life.get("decline", []):
        if not isinstance(d.get("age"), int) or any(k not in STAT_IDS or not isinstance(v, int) for k, v in d.get("stats", {}).items()):
            rep.error(w, f"life.decline: {d} debe ser {{age, stats {{atributo: entero}}}}")
    death = life.get("death", {})
    if not all(isinstance(death.get(k), (int, float)) for k in ("from_age", "base", "growth", "constitution_step", "certain_age")):
        rep.error(w, "life.death: from_age, base, growth, constitution_step, certain_age")
    if life.get("ai_school_stat") not in STAT_IDS:
        rep.error(w, "life.ai_school_stat debe ser un atributo")
    co = fam.get("courtship", {})
    talk = co.get("talk")
    if not (isinstance(talk, list) and len(talk) == 2 and all(isinstance(x, int) for x in talk) and 0 <= talk[0] <= talk[1]):
        rep.error(w, "courtship.talk debe ser [mín, máx]")
    g = co.get("gift", {})
    if not (isinstance(g.get("min"), int) and isinstance(g.get("max"), int) and g["min"] <= g["max"] and g.get("gold_per_point", 0) > 0):
        rep.error(w, "courtship.gift: min <= max y gold_per_point > 0")
    if not isinstance(co.get("propose_min"), int) or not 0 < co["propose_min"] <= co.get("affinity_max", 100):
        rep.error(w, "courtship.propose_min en (0, affinity_max]")
    ch = fam.get("children", {})
    for k in ("first_child_days", "between_days", "max_per_couple", "mother_max_age", "stat_jitter"):
        if not isinstance(ch.get(k), int) or ch[k] < 0:
            rep.error(w, f"children.{k} debe ser un entero >= 0")
    for k in ("daily_chance", "new_tone_chance"):
        if not isinstance(ch.get(k), (int, float)) or not 0 <= ch[k] <= 1:
            rep.error(w, f"children.{k} debe estar en [0, 1]")
    vis = fam.get("visual", {})
    tones = {"hair": vis.get("hair_tones"), "skin": vis.get("skin_tones")}
    if not all(isinstance(t, int) and t > 0 for t in tones.values()):
        rep.error(w, "visual.hair_tones y skin_tones deben ser enteros > 0")
        tones = {"hair": 1, "skin": 1}
    view = load_json(os.path.join(DATA, "view.json"), rep) or {}
    pal = view.get("palette", {})
    for k in ("hair", "skin"):
        if not isinstance(pal.get(k), list) or len(pal[k]) < tones[k]:
            rep.error("view.json", f"palette.{k} debe tener al menos {tones[k]} colores (data/family.json visual)")
    if not isinstance(fam.get("group", {}).get("max"), int) or fam["group"]["max"] < 1:
        rep.error(w, "group.max debe ser un entero >= 1")
    ro = fam.get("routine", {})
    acts = ro.get("actions", [])
    for a in acts:
        check_text(w, f"routine.{a}", strings, rep)
    for ph, slot in ro.get("default", {}).items():
        if ph not in PHASES or slot.get("action") not in acts:
            rep.error(w, f"routine.default.{ph}: fase y acción conocidas")
    for ph in ro.get("ai_rest_phases", []):
        if ph not in PHASES:
            rep.error(w, f"routine.ai_rest_phases: fase desconocida {ph}")
    for d in fam.get("directives", {}).get("known", []):
        check_text(w, f"directive.{d}", strings, rep)
    for k in ("male", "female"):
        if not fam.get("names", {}).get(k):
            rep.error(w, f"names.{k} vacío")
    if not isinstance(fam.get("succession", {}).get("voluntary_close"), bool):
        rep.error(w, "succession.voluntary_close debe ser true o false (D19)")
    goals = load_json(os.path.join(DATA, "goals.json"), rep) or {}
    for gl in goals.get("goals", []):
        wg = f"goals.json/{gl.get('id')}"
        if not ID_RE.match(str(gl.get("id", ""))):
            rep.error(wg, "id snake_case")
        if gl.get("kind") not in ("generation", "wealth", "office"):
            rep.error(wg, f"kind desconocido {gl.get('kind')}")
        check_text(wg, gl.get("name_key"), strings, rep)
    score = load_json(os.path.join(DATA, "score.json"), rep) or {}
    for k, v in score.get("points", {}).items():
        if not isinstance(v, int):
            rep.error("score.json", f"points.{k} debe ser entero")
        check_text("score.json", f"score.{k}", strings, rep)
    for k in score.get("by_value", {}):
        check_text("score.json", f"score.{k}", strings, rep)
    if not isinstance(score.get("wealth", {}).get("gold_per_point"), int):
        rep.error("score.json", "wealth.gold_per_point debe ser entero")
    # población: a generated cast uses the whole palette (data/cast.json look), the fixed one its first tones
    return {k: max(tones[k], len(pal.get(k, []))) for k in ("hair", "skin")}


def check_h8_scenario(w, d, buildings, tones, rep):
    """H8: en escenarios v7, edades, parentesco coherente (pareja recíproca, padres e hijos), cabeza y heredero de cada
    familia, rutina con fases y acciones conocidas y tonos dentro de la paleta."""
    chars, fams, blds = d.get("characters") or {}, d.get("families") or {}, d.get("buildings") or {}
    for cid, ch in chars.items():
        for k in ("birth_day", "death_day"):
            if not isinstance(ch.get(k), int):
                rep.error(w, f"{cid}: {k} debe ser un entero (días)")
        sp = ch.get("spouse", "")
        if sp and ch.get("alive", True) and chars.get(sp, {}).get("alive", True) and chars.get(sp, {}).get("spouse") != cid:
            rep.error(w, f"{cid}: su pareja {sp} no lo tiene como pareja")
        for p in ch.get("parents", []):
            if cid not in chars.get(p, {}).get("children", []):
                rep.error(w, f"{cid}: su padre/madre {p} no lo tiene como hijo")
        for c in ch.get("children", []):
            if cid not in chars.get(c, {}).get("parents", []):
                rep.error(w, f"{cid}: su hijo {c} no lo tiene como padre/madre")
        vis = ch.get("visual", {})
        for k in ("hair", "skin"):
            if not isinstance(vis.get(k), int) or not 0 <= vis[k] < tones[k]:
                rep.error(w, f"{cid}: visual.{k} fuera de la paleta (0..{tones[k] - 1})")
        a = ch.get("assigned", "")
        if a and a not in blds:
            rep.error(w, f"{cid}: assigned {a} no es un edificio del escenario")
        sched = ch.get("schedule")
        if sched is not None:
            if not isinstance(sched, dict):
                rep.error(w, f"{cid}: schedule debe ser null o {{fase: franja}}")
            else:
                for ph, slot in sched.items():
                    if ph not in PHASES or slot.get("action") not in ("work", "rest", "free"):
                        rep.error(w, f"{cid}: schedule.{ph} con fase o acción desconocida")
                    if slot.get("building") and slot["building"] not in blds:
                        rep.error(w, f"{cid}: schedule.{ph}.building {slot['building']} desconocido")
    for fid, f in fams.items():
        h = f.get("head", "")
        if h and (h not in chars or chars[h].get("family") != fid):
            rep.error(w, f"{fid}: head {h} no es de la familia")
        if f.get("heir") and f["heir"] not in chars:
            rep.error(w, f"{fid}: heir {f['heir']} desconocido")
        if not isinstance(f.get("generation"), int) or f["generation"] < 1:
            rep.error(w, f"{fid}: generation debe ser un entero >= 1")


HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
CAST_MIN_NAMES = 60      # por sexo: con 16 se repetían enseguida
CAST_MIN_SURNAMES = 80


def check_cast(rep):
    """Población (sim/meta/cast.gd, docs/contratos/poblacion.md): data/cast.json. Nombres por sexo (>= 60, sin
    repetir), apellidos generales (>= 80) y de oficio (por profesión conocida), sin repetir entre listas; rangos de
    edad [mín, máx] por papel (las del pueblo dentro de lo que permite la boda); personalidad sobre atributos
    conocidos; tonos de pelo y piel dentro de la paleta de data/view.json; parejas de colores de ropa válidas y
    bastantes para las familias IA de cada inicio; tipos de retrato por papel y etapas por edad ascendentes."""
    w = "cast.json"
    c = load_json(os.path.join(DATA, "cast.json"), rep)
    if c is None:
        return
    names = c.get("names", {})
    for k in ("male", "female"):
        lst = names.get(k)
        if not isinstance(lst, list) or not all(isinstance(n, str) and n.strip() == n and n for n in lst):
            rep.error(w, f"names.{k} debe ser una lista de nombres")
            continue
        if len(lst) < CAST_MIN_NAMES:
            rep.error(w, f"names.{k}: {len(lst)} nombres, hacen falta >= {CAST_MIN_NAMES}")
        dup = sorted({n for n in lst if lst.count(n) > 1})
        if dup:
            rep.error(w, f"names.{k} repetidos: {dup}")
    both = set(names.get("male", [])) & set(names.get("female", []))
    if both:
        rep.error(w, f"nombres en las dos listas: {sorted(both)}")
    sn = c.get("surnames", {})
    gen = sn.get("general", [])
    if not isinstance(gen, list) or len(gen) < CAST_MIN_SURNAMES:
        rep.error(w, f"surnames.general: hacen falta >= {CAST_MIN_SURNAMES} apellidos")
        gen = gen if isinstance(gen, list) else []
    seen = {}
    profs = set(load_kind("professions", rep))
    for where, lst in [("general", gen)] + [(f"trade.{p}", l) for p, l in sn.get("trade", {}).items()]:
        if where.startswith("trade.") and where[6:] not in profs:
            rep.error(w, f"surnames.{where}: profesión desconocida")
        for n in lst if isinstance(lst, list) else []:
            if not isinstance(n, str) or not n.strip():
                rep.error(w, f"surnames.{where}: apellido vacío")
            elif n in seen:
                rep.error(w, f"surnames: «{n}» en {seen[n]} y en {where}")
            else:
                seen[n] = where
    fam = load_json(os.path.join(DATA, "family.json"), rep) or {}
    town = load_json(os.path.join(DATA, "town.json"), rep) or {}
    ages = c.get("ages", {})
    for role in ("rival", "competitor", "competitor_spouse", "townsfolk"):
        a = ages.get(role)
        if not (isinstance(a, list) and len(a) == 2 and all(isinstance(x, int) for x in a) and 0 <= a[0] <= a[1]):
            rep.error(w, f"ages.{role} debe ser [mín, máx] en años enteros")
    tf = ages.get("townsfolk", [0, 0])
    major = fam.get("life", {}).get("majority_age", 16)
    mother_max = fam.get("children", {}).get("mother_max_age", 45) - 5
    if isinstance(tf, list) and len(tf) == 2 and (tf[0] < major or tf[1] > mother_max):
        rep.error(w, f"ages.townsfolk {tf}: fuera de [{major}, {mother_max}] (mayoría de edad; bodas del pueblo)")
    pers = c.get("personality", {})
    for k in pers.get("stats", []):
        if k not in STAT_IDS:
            rep.error(w, f"personality.stats: atributo desconocido {k}")
    if not isinstance(pers.get("jitter"), int) or pers["jitter"] < 0:
        rep.error(w, "personality.jitter debe ser un entero >= 0")
    view = load_json(os.path.join(DATA, "view.json"), rep) or {}
    pal = view.get("palette", {})
    look = c.get("look", {})
    for k in ("hair", "skin"):
        idx = look.get(k)
        n = len(pal.get(k, []))
        if not isinstance(idx, list) or not idx or not all(isinstance(i, int) and 0 <= i < n for i in idx):
            rep.error(w, f"look.{k}: índices de data/view.json palette.{k} (0..{n - 1})")
    kr = look.get("kin_resemblance")
    if not isinstance(kr, (int, float)) or not 0 <= kr <= 1:
        rep.error(w, "look.kin_resemblance debe estar en [0, 1]")
    pairs = c.get("family_colors", {}).get("pairs", [])
    if not all(isinstance(pp, list) and len(pp) == 2 and all(isinstance(x, str) and HEX_RE.match(x) for x in pp) for pp in pairs):
        rep.error(w, "family_colors.pairs: [[\"#rrggbb\", \"#rrggbb\"], ...]")
    prim = [pp[0] for pp in pairs if isinstance(pp, list) and pp]
    if len(set(prim)) != len(prim):
        rep.error(w, "family_colors.pairs: color principal repetido (las familias se distinguen por él)")
    maps = load_kind("maps", rep)
    for sid, st in load_kind("starts", rep).items():
        # fixed cast: no two families of a start (player, rival, competitors, the map's houses) share a surname
        houses = [("defaults", (st.get("defaults") or {}).get("family_name"))]
        if st.get("rival"):
            houses.append(("rival", st["rival"].get("family_name")))
        houses += [(f"competitors[{i}]", c.get("family_name")) for i, c in enumerate(st.get("competitors", []))]
        houses += [(f"casa {h.get('home')} de {st.get('map')}", h.get("family_name"))
                   for h in maps.get(st.get("map"), {}).get("population", []) if h.get("family_name")]
        seen_fam = {}
        for where, fname in houses:
            if fname in seen_fam:
                rep.error(f"starts/{sid}", f"apellido «{fname}» repetido: {seen_fam[fname]} y {where} (reparto fijo)")
            elif fname:
                seen_fam[fname] = where
        need = (1 if st.get("rival") else 0) + len(st.get("competitors", [])) + len(maps.get(st.get("map"), {}).get("population", []))
        if len(pairs) < need + 2:
            rep.error(w, f"family_colors.pairs: {len(pairs)} parejas; el inicio {sid} tiene {need} familias IA (+2 de margen por el color del jugador)")
    po = c.get("portraits", {})
    # data/portraits.json: the sim's catalog of the pool, exported from assets/art/portraits/index.json (ids, no paths)
    wp = "portraits.json"
    pool = load_json(os.path.join(DATA, "portraits.json"), rep) or {}
    if os.path.exists(os.path.join(ROOT, "assets", "art", "portraits", "index.json")):
        sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
        import portraits_catalog
        want = portraits_catalog.expected()
        if {k: v for k, v in pool.items() if k != "_doc"} != {k: v for k, v in want.items() if k != "_doc"}:
            rep.error(wp, "no coincide con assets/art/portraits/index.json: python3 tools/art/portraits_catalog.py")
    elif pool:
        rep.error(wp, "no hay assets/art/portraits/index.json del que salga")
    if pool:
        for t in po.get("types", []):
            if t not in pool.get("types", []):
                rep.error(w, f"portraits.types: {t} no es un tipo del pool")
        bands = pool.get("ages", {})
        for stg in po.get("stages", []):
            b = bands.get(stg.get("id"))
            if not b or (b[1] is not None and b[1] != stg.get("to_age")):
                rep.error(w, f"portraits.stages.{stg.get('id')}: no casa con las franjas del pool {b}")
        for sex in ("m", "f"):
            for b in bands:
                if not pool.get("by", {}).get(f"{sex}|{b}|commoner"):
                    rep.error(wp, f"falta commoner {sex} {b} (el último recurso del reparto)")
    ptypes = po.get("types", [])
    if not ptypes or not all(isinstance(t, str) and ID_RE.match(t) for t in ptypes):
        rep.error(w, "portraits.types: los tipos sociales del pool de retratos (ids snake_case)")
    if "commoner" not in ptypes:
        rep.error(w, "portraits.types debe tener commoner (existe en todas las edades y sexos del pool)")
    for role in ("rival", "competitor", "townsfolk", "newcomer"):
        if po.get("roles", {}).get(role) not in ptypes:
            rep.error(w, f"portraits.roles.{role}: un tipo de portraits.types")
    for cls in ("artisan", "patron", "scholar", "rogue"):
        if po.get("classes", {}).get(cls) not in ptypes:
            rep.error(w, f"portraits.classes.{cls}: un tipo de portraits.types")
    if [stg.get("id") for stg in po.get("stages", [])] != ["child", "youth", "adult", "mature", "elder"]:
        rep.error(w, "portraits.stages: las franjas del pool (child, youth, adult, mature, elder), en orden")
    last = -1
    for stg in po.get("stages", []):
        if not ID_RE.match(str(stg.get("id", ""))) or not isinstance(stg.get("to_age"), int) or stg["to_age"] <= last:
            rep.error(w, f"portraits.stages: {stg} debe ser {{id, to_age}} con to_age creciente")
        else:
            last = stg["to_age"]
    if last < fam.get("life", {}).get("death", {}).get("certain_age", 75):
        rep.error(w, "portraits.stages: la última etapa debe llegar a la edad de muerte segura")


EMOTIONS = {"grateful", "offended", "angry", "scared"}  # the 4 of the MVP (GDD 4.11.5)
ACTIVITIES = {"bench", "chat", "market", "greet", "observe", "dice"}  # GDD 4.11.3
ACTIVITY_SPOTS = {"bench", "chat", "dice", "stalls", "doors", "none"}
SOCIAL_KINDS = {"bench", "chat", "dice"} | {"well", "atrium", "tavern", "washhouse", "bridge", "gate", "square"}  # + 04f 4.24.2
WORKPLACE_KINDS = {"tile", "stall", "shop"}
MEV_EFFECTS = {"sell", "skill_check", "leave", "emotion", "relation", "pay", "loyalty", "absent", "refund_wage", "steal",
               "nothing", "reputation"}
MEV_CONDITIONS = {"counter_sales", "has_employees", "has_goods", "has_products"}
MEV_SCOPES = {"building", "character", "family"}
TOWN_STATES = {"home", "walking", "working", "market", "strolling", "social", "customer"} | {"guarding"}  # + 04f 4.24.4: a guard at its post or on its round


def _range_ok(v, lo=0):
    return isinstance(v, list) and len(v) == 2 and all(isinstance(x, (int, float)) for x in v) and lo <= v[0] <= v[1]


def check_h7(maps_raw, strings, rep):
    """H7 (GDD 4.11, 4.5.4, 4.20, docs/contratos/h7_ciudad.md): data/town.json, data/microevents/, data/social_phrases.json
    y los puntos sociales y oficios de los mapas. Devuelve {map_id: set(ids de oficio)} para los escenarios."""
    w = "town.json"
    town = load_json(os.path.join(DATA, "town.json"), rep) or {}
    for k in ("routine", "activities", "personality", "emotions", "actions", "skill_check", "counter", "microevents",
              "population"):
        if k not in town:
            rep.error(w, f"falta {k}")
    ro = town.get("routine", {})
    for k in ("leave_home_delay_minutes", "break_chance_per_hour", "break_minutes"):
        if not _range_ok(ro.get(k)):
            rep.error(w, f"routine.{k} debe ser [mín, máx]")
    if any(not 0 <= x <= 1 for x in ro.get("break_chance_per_hour", [0, 0])) or not 0 <= ro.get("market_visit_chance", -1) <= 1:
        rep.error(w, "routine: las probabilidades van en [0, 1]")
    acts = town.get("activities", {})
    if set(acts) != ACTIVITIES:
        rep.error(w, f"activities debe tener {sorted(ACTIVITIES)}")
    for a, d in acts.items():
        if a == "market":
            if not _range_ok(d.get("per_stall_minutes"), 1) or not _range_ok(d.get("stalls"), 1):
                rep.error(w, "activities.market: per_stall_minutes y stalls [mín, máx]")
        elif not _range_ok(d.get("minutes"), 1):
            rep.error(w, f"activities.{a}.minutes debe ser [mín, máx] en minutos de juego")
        if d.get("spot") not in ACTIVITY_SPOTS:
            rep.error(w, f"activities.{a}.spot desconocido {d.get('spot')}")
        if d.get("favored_by") and d["favored_by"] not in STATS:
            rep.error(w, f"activities.{a}.favored_by debe ser un atributo")
        if not ID_RE.match(str(d.get("bubble", ""))):
            rep.error(w, f"activities.{a}.bubble debe ser un id")
        check_text(w, f"activity.{a}", strings, rep)
    emo = town.get("emotions", {})
    if set(emo) != EMOTIONS:
        rep.error(w, f"emotions debe tener los 4 del MVP {sorted(EMOTIONS)}")
    for e, d in emo.items():
        check_text(w, d.get("name_key"), strings, rep)
        if not _range_ok(d.get("duration_days")) or d["duration_days"][0] <= 0:
            rep.error(w, f"emotions.{e}.duration_days debe ser [mín, máx] > 0 (días)")
        for k in ("buy_mult", "sell_mult", "employee_mult"):
            if not isinstance(d.get(k), (int, float)) or d[k] <= 0:
                rep.error(w, f"emotions.{e}.{k} debe ser > 0")
        if not ID_RE.match(str(d.get("icon", ""))):
            rep.error(w, f"emotions.{e}.icon debe ser un id")
    for pair in town.get("incompatible", []):
        if not (isinstance(pair, list) and len(pair) == 2 and all(x in EMOTIONS for x in pair)):
            rep.error(w, f"incompatible: {pair} no es un par de emociones del MVP")
    for a in ("talk", "gift", "flatter", "insult", "threaten"):
        if a not in town.get("actions", {}):
            rep.error(w, f"actions.{a} falta")
        check_text(w, f"npc_action.{a}", strings, rep)
    for a in ("flatter", "threaten"):
        d = town.get("actions", {}).get(a, {})
        if d.get("actor_stat") not in STATS or d.get("target_stat") not in STATS:
            rep.error(w, f"actions.{a}: actor_stat y target_stat deben ser atributos")
    for a, k in (("insult", "emotion"), ("threaten", "success_emotion"), ("threaten", "fail_emotion")):
        if town.get("actions", {}).get(a, {}).get(k) not in EMOTIONS:
            rep.error(w, f"actions.{a}.{k} debe ser una emoción del MVP")
    co = town.get("counter", {})
    if not _range_ok(co.get("interval_hours")) or co["interval_hours"][0] <= 0:
        rep.error(w, "counter.interval_hours debe ser [mín, máx] > 0 (horas de juego)")
    if any(p not in PHASES for p in co.get("phases", [])):
        rep.error(w, "counter.phases: fases del día")
    mv = town.get("microevents", {})
    if not 0 <= mv.get("base_chance", -1) <= 1 or not isinstance(mv.get("max_per_family_day"), int):
        rep.error(w, "microevents: base_chance en [0, 1] y max_per_family_day entero")
    po = town.get("population", {})
    for k in ("min_adults", "max_total", "min_singles", "marriage_min_age", "house_capacity"):
        if not isinstance(po.get(k), int) or po[k] < 0:
            rep.error(w, f"population.{k} debe ser un entero >= 0")
    if not po.get("min_adults", 0) <= po.get("max_total", 0):
        rep.error(w, "population: min_adults <= max_total")
    if not _range_ok(po.get("newcomer_age"), 16):
        rep.error(w, "population.newcomer_age debe ser [mín, máx] de adultos")
    for a, d in acts.items():
        if d.get("bubble") and not os.path.exists(os.path.join(ROOT, "game", "visuals", "bubbles", d["bubble"] + ".tscn")):
            rep.error(w, f"activities.{a}.bubble: falta game/visuals/bubbles/{d['bubble']}.tscn")
    for e, d in emo.items():
        if d.get("icon") and not os.path.exists(os.path.join(ROOT, "game", "visuals", "bubbles", d["icon"] + ".tscn")):
            rep.error(w, f"emotions.{e}.icon: falta game/visuals/bubbles/{d['icon']}.tscn")
    # microevents
    mevs = load_kind("microevents", rep)
    if not mevs:
        rep.error("microevents", "no hay microeventos (GDD 4.20: los 3 del MVP)")
    for id_, m in mevs.items():
        wm = f"microevents/{id_}"
        check_text(wm, m.get("text_key"), strings, rep)
        check_text(wm, f"notice.microevent.{id_}", strings, rep)
        if m.get("scope") not in MEV_SCOPES:
            rep.error(wm, f"scope desconocido {m.get('scope')}")
        tr = m.get("trigger", {})
        if tr.get("phase") not in PHASES:
            rep.error(wm, "trigger.phase debe ser una fase del día")
        if any(c not in MEV_CONDITIONS for c in tr.get("conditions", [])):
            rep.error(wm, f"trigger.conditions: conocidas {sorted(MEV_CONDITIONS)}")
        if not isinstance(tr.get("chance_per_day"), (int, float)) or tr["chance_per_day"] < 0:
            rep.error(wm, "trigger.chance_per_day debe ser >= 0")
        for k in ("cooldown_days", "timeout_hours"):
            if not isinstance(m.get(k), (int, float)) or m[k] <= 0:
                rep.error(wm, f"{k} debe ser > 0 (días / horas de juego)")
        ids = []
        for c in m.get("choices", []):
            ids.append(c.get("id"))
            check_text(wm, c.get("text_key"), strings, rep)
            _check_mev_effects(wm, c.get("effects", []), rep)
        _check_mev_effects(wm, m.get("unattended_effects", []), rep)
        if len(ids) != len(set(ids)) or not ids:
            rep.error(wm, "opciones con id único (al menos una)")
        if m.get("default_choice") not in ids:
            rep.error(wm, f"default_choice {m.get('default_choice')} no es una opción")
    # phrases
    ph = load_json(os.path.join(DATA, "social_phrases.json"), rep) or {}
    for group in ("activities", "phases", "professions"):
        for k, keys in ph.get(group, {}).items():
            if not keys:
                rep.error("social_phrases.json", f"{group}.{k} vacío")
            for key in keys:
                check_text("social_phrases.json", key, strings, rep)
    for a in ACTIVITIES:
        if len(ph.get("activities", {}).get(a, [])) < 10:
            rep.error("social_phrases.json", f"activities.{a}: 10-15 frases (GDD 4.11.3)")
    # maps
    out = {}
    for mid, m in maps_raw.items():
        wmap = f"maps/{mid}"
        rows = m.get("rows", [])
        walk = set("=P,fb.")
        def walkable(c, r):
            return 0 <= r < len(rows) and 0 <= c < len(rows[r]) and rows[r][c] in walk
        for sp in m.get("social_points", []):
            if sp.get("kind") not in SOCIAL_KINDS:
                rep.error(wmap, f"social_points/{sp.get('id')}: kind desconocido {sp.get('kind')}")
            if not sp.get("slots"):
                rep.error(wmap, f"social_points/{sp.get('id')}: sin huecos")
            for t in sp.get("slots", []):
                if not (isinstance(t, list) and len(t) == 2 and walkable(*t)):
                    rep.error(wmap, f"social_points/{sp.get('id')}: hueco {t} no transitable")
        for pt in m.get("patrols", []):  # 04f 4.24.4: the night watch's rounds
            if not ID_RE.match(str(pt.get("id", ""))) or len(pt.get("tiles", [])) < 2:
                rep.error(wmap, f"patrols/{pt.get('id')}: id snake_case y 2 casillas o más")
            for t in pt.get("tiles", []):
                if not (isinstance(t, list) and len(t) == 2 and walkable(*t)):
                    rep.error(wmap, f"patrols/{pt.get('id')}: casilla {t} no transitable")
        ids = set()
        for wp in m.get("workplaces", []):
            wid = wp.get("id")
            if wid in ids or not ID_RE.match(str(wid)):
                rep.error(wmap, f"workplaces/{wid}: id snake_case único")
            ids.add(wid)
            check_text(wmap, f"workplace.{wid}", strings, rep)
            if wp.get("kind") not in WORKPLACE_KINDS:
                rep.error(wmap, f"workplaces/{wid}: kind desconocido {wp.get('kind')}")
            t = wp.get("tile")
            if not (isinstance(t, list) and len(t) == 2 and walkable(*t)):
                rep.error(wmap, f"workplaces/{wid}: casilla {t} no transitable")
            if wp.get("stall") is not None and wp["stall"] not in STALLS:
                rep.error(wmap, f"workplaces/{wid}: puesto desconocido {wp['stall']}")
            if wp.get("kind") == "shop" and wp.get("building") not in m.get("buildings", {}):
                rep.error(wmap, f"workplaces/{wid}: edificio {wp.get('building')} no está en el mapa")
        if m.get("population") and len(ids) < 1:
            rep.error(wmap, "un mapa con población necesita oficios (workplaces)")
        out[mid] = ids
    return out


def _check_mev_effects(w, effects, rep):
    for e in effects:
        if e.get("kind") not in MEV_EFFECTS:
            rep.error(w, f"efecto desconocido {e.get('kind')}")
        if e.get("kind") == "skill_check":
            if e.get("actor_stat") not in STATS or (e.get("target_stat") not in STATS and not isinstance(e.get("target_value"), int)):
                rep.error(w, "skill_check: actor_stat y target_stat (atributos) o target_value (entero)")
        if e.get("kind") == "emotion" and e.get("state") not in EMOTIONS:
            rep.error(w, f"emotion: estado desconocido {e.get('state')}")
        if e.get("kind") in ("absent", "steal") and not _range_ok(e.get("days") or e.get("units")):
            rep.error(w, f"{e.get('kind')}: [mín, máx]")
        _check_mev_effects(w, e.get("success", []), rep)
        _check_mev_effects(w, e.get("fail", []), rep)


def check_h7_scenario(w, d, workplaces, rep):
    """H7: en escenarios v8, oficio (uno del mapa o ""), memoria de la ciudad, emociones (estados del MVP) y
    microeventos (activos con ficha, opciones y familia que existen)."""
    chars, fams = d.get("characters") or {}, d.get("families") or {}
    wps = workplaces.get(d.get("map_id", ""), set())
    for cid, ch in chars.items():
        occ = ch.get("occupation")
        if not isinstance(occ, str) or (occ and occ not in wps):
            rep.error(w, f"{cid}: occupation {occ!r} no es un oficio del mapa")
        if not isinstance(ch.get("town"), dict):
            rep.error(w, f"{cid}: town debe ser un diccionario")
        elif ch["town"].get("state") and ch["town"]["state"] not in TOWN_STATES:
            rep.error(w, f"{cid}: town.state desconocido {ch['town']['state']}")
    for cid, lst in (d.get("emotions") or {}).items():
        if cid not in chars:
            rep.error(w, f"emotions: {cid} no es un personaje")
        for e in lst:
            if e.get("state") not in EMOTIONS:
                rep.error(w, f"emotions/{cid}: estado desconocido {e.get('state')}")
    mv = d.get("microevents")
    if not isinstance(mv, dict) or any(k not in mv for k in ("active", "pending", "cooldowns", "last_day")):
        rep.error(w, "microevents debe ser {active, pending, cooldowns, last_day}")
        return
    for m in mv["active"]:
        if not os.path.exists(os.path.join(DATA, "microevents", str(m.get("def")) + ".json")):
            rep.error(w, f"microevents: ficha desconocida {m.get('def')}")
        if m.get("family") not in fams:
            rep.error(w, f"microevents/{m.get('id')}: familia desconocida {m.get('family')}")
        if m.get("default") not in m.get("choices", []):
            rep.error(w, f"microevents/{m.get('id')}: la opción por defecto no está entre las opciones")
    if not isinstance(d.get("town"), dict):
        rep.error(w, "town debe ser un diccionario")


H9_REQUIRES = {"businesses", "employees", "event"}
H9_RULE_EVENTS = {"market_sold", "counter_sold", "wage_paid", "npc_action"}
H9_REASONS = ["not_at_town_hall", "max_title", "wrong_title", "title_needs_reputation", "title_needs_businesses",
              "title_needs_employees", "title_needs_event", "title_not_approved"]


def check_h9(maps_raw, strings, rep):
    """H9 (GDD 4.12, docs/contratos/h9_titulos.md): data/titles (escalera = upgrade_rules.titles, cifras, requisitos y
    lo que abren), data/politics.json (clases con texto, reglas con eventos conocidos), el Ayuntamiento de cada mapa
    (huella sobre casillas de edificio, servicio transitable) y los textos de los motivos y avisos."""
    titles = load_kind("titles", rep)
    ladder = (load_json(os.path.join(DATA, "upgrade_rules.json"), rep) or {}).get("titles", [])
    by_rank = sorted(titles.values(), key=lambda t: t.get("rank", 0))
    if [t["id"] for t in by_rank] != ladder:
        rep.error("titles/", f"el orden por rank {[t['id'] for t in by_rank]} no es upgrade_rules.titles {ladder}")
    for i, t in enumerate(by_rank):
        w = f"titles/{t['id']}"
        check_text(w, t.get("name_key"), strings, rep)
        if t.get("rank") != i:
            rep.error(w, f"rank debe ser {i}")
        for k in ("cost_gold", "reputation"):
            if not isinstance(t.get(k), int) or t[k] < 0:
                rep.error(w, f"{k} debe ser un entero >= 0")
        if i > 0 and (t.get("cost_gold", 0) <= by_rank[i - 1].get("cost_gold", 0)
                      or t.get("reputation", 0) <= by_rank[i - 1].get("reputation", 0)):
            rep.error(w, "cada título cuesta más oro y pide más reputación que el anterior")
        for k, v in (t.get("requires") or {}).items():
            if k not in H9_REQUIRES:
                rep.error(w, f"requisito desconocido {k}")
            elif k != "event" and (not isinstance(v, int) or v < 1):
                rep.error(w, f"requires.{k} debe ser un entero >= 1")
        mb = (t.get("unlocks") or {}).get("max_buildings", 0)
        if mb is not None and (not isinstance(mb, int) or mb < 1):
            rep.error(w, "unlocks.max_buildings debe ser un entero >= 1 o null (sin límite)")
    pol = load_json(os.path.join(DATA, "politics.json"), rep) or {}
    rp = pol.get("reputation") or {}
    classes = rp.get("classes") or []
    for c in classes:
        check_text(f"politics.json/classes/{c}", f"class.{c}", strings, rep)
    for reason, c in (rp.get("reason_class") or {}).items():
        if c not in classes:
            rep.error("politics.json", f"reason_class.{reason}: clase desconocida {c}")
    ids = set()
    for r in rp.get("rules") or []:
        w = f"politics.json/rules/{r.get('id')}"
        if not r.get("id") or r["id"] in ids:
            rep.error(w, "id vacío o repetido")
        ids.add(r.get("id"))
        if not r.get("events") or any(e not in H9_RULE_EVENTS for e in r["events"]):
            rep.error(w, f"events debe ser una lista de {sorted(H9_RULE_EVENTS)}")
        if r.get("class") not in (None, "target") and r.get("class") not in classes:
            rep.error(w, f"clase desconocida {r.get('class')}")
        if not isinstance(r.get("cap", 0), int) or not isinstance(r.get("cap_days", 1), int) or r.get("cap_days", 1) < 1:
            rep.error(w, "cap (entero >= 0) y cap_days (entero >= 1)")
    if not isinstance((rp.get("passive") or {}).get("per_business_with_staff"), int):
        rep.error("politics.json", "passive.per_business_with_staff debe ser un entero")
    cer = pol.get("ceremony") or {}
    if not isinstance(cer.get("min_affinity"), int) or not cer.get("approvers"):
        rep.error("politics.json", "ceremony: approvers y min_affinity")
    for mid, m in maps_raw.items():
        th = m.get("town_hall")
        if th is None:
            continue
        w = f"maps/{mid}/town_hall"
        rows = m.get("rows", [])
        try:
            (c0, r0), (fw, fh) = th["origin"], th["footprint"]
            tc, tr = th["tile"]
            sc, sr = th["service"]
        except (KeyError, TypeError, ValueError):
            rep.error(w, "debe ser {origin, footprint, tile, service}")
            continue
        if any(rows[r][c] != "#" for r in range(r0, r0 + fh) for c in range(c0, c0 + fw)):
            rep.error(w, "la huella debe caer sobre casillas de edificio (#)")
        if not (c0 <= tc < c0 + fw and r0 <= tr < r0 + fh):
            rep.error(w, "tile (letrero) debe estar dentro de la huella")
        if rows[sr][sc] not in set("=P,fb."):
            rep.error(w, "service debe ser una casilla transitable")
        for b in (m.get("buildings") or {}).values():
            bc, br = b.get("origin", [-1, -1])
            if c0 <= bc < c0 + fw and r0 <= br < r0 + fh:
                rep.error(w, "se pisa con un edificio del mapa")
    for k in H9_REASONS:
        check_text("i18n/reason", "reason." + k, strings, rep)
    for k in ("notice.title_granted", "notice.rival_title"):
        check_text("i18n/notice", k, strings, rep)
    return set(titles)


def check_h9_scenario(w, d, titles, rep):
    """H9: en escenarios v9, cada familia con un título que existe, class_reputation (diccionario de enteros),
    reputation_log (lista) y reputation_caps (diccionario)."""
    for fid, f in (d.get("families") or {}).items():
        if f.get("title") not in titles:
            rep.error(w, f"{fid}: título desconocido {f.get('title')}")
        cr = f.get("class_reputation")
        if not isinstance(cr, dict) or any(not isinstance(v, int) for v in cr.values()):
            rep.error(w, f"{fid}: class_reputation debe ser {{clase: entero}}")
        if not isinstance(f.get("reputation_log"), list) or not isinstance(f.get("reputation_caps"), dict):
            rep.error(w, f"{fid}: reputation_log (lista) y reputation_caps (diccionario)")
        if not isinstance(f.get("reputation"), int):
            rep.error(w, f"{fid}: reputation debe ser un entero")


H10_RANKS = ["minor", "middle", "major", "mayor"]
H10_PASSIVES = {"class_reputation", "tax_commission", "reputation_per_day", "sees_reports", "votes_ordinances"}
H10_POWERS = {"regulate_price", "fine_merchant", "set_tax", "seize_building", "arrest", "investigate", "preside_trial",
              "pardon", "propose_ordinance", "veto", "legislate", "declare_event", "name_title",
              "organize_festival"}  # fiestas (04f 4.25.5)
H10_ACTIONS = ["visit", "bribe", "speech", "defame"]
H10_REASONS = ["unknown_office", "office_needs_title", "holds_office", "already_candidate", "no_election",
               "registration_closed", "unknown_level", "not_candidate", "campaign_not_started", "campaign_busy",
               "unknown_campaign_action", "not_a_voter", "not_a_candidate", "indoors", "not_office_holder",
               "unknown_power", "power_not_ready", "power_cooldown", "bad_args", "not_a_merchant", "already_regulated",
               "already_bribed", "unknown_target"]
H10_NOTICES = ["office_candidate", "campaign_started", "office_won", "office_lost", "rival_candidate", "rival_office",
               "price_regulated", "fined", "tax_set"]


def check_h10(titles, strings, rep):
    """H10 (GDD 4.12.3-4.12.4, docs/contratos/h10_cargos.md): data/offices (rango, título mínimo, salario, mandato,
    asientos, orden del organigrama, pasivos y poderes conocidos), data/politics.json (government, elections, taxes,
    regulation), la regla de cargos de los perfiles de IA y los textos de cargos, poderes, niveles, acciones, motivos y
    avisos."""
    offices = load_kind("offices", rep)
    orders = set()
    for oid, o in offices.items():
        w = f"offices/{oid}"
        check_text(w, o.get("name_key"), strings, rep)
        if o.get("rank") not in H10_RANKS:
            rep.error(w, f"rank debe ser uno de {H10_RANKS}")
        if o.get("min_title") not in titles:
            rep.error(w, f"min_title desconocido {o.get('min_title')}")
        for k, lo in (("salary", 0), ("term_years", 1), ("seats", 1), ("order", 0)):
            if not isinstance(o.get(k), int) or o[k] < lo:
                rep.error(w, f"{k} debe ser un entero >= {lo}")
        if o.get("order") in orders:
            rep.error(w, f"order {o.get('order')} repetido")
        orders.add(o.get("order"))
        for pa in o.get("passive") or []:
            if pa.get("kind") not in H10_PASSIVES:
                rep.error(w, f"pasivo desconocido {pa.get('kind')}")
        for pw in o.get("powers") or []:
            if pw.get("id") not in H10_POWERS:
                rep.error(w, f"poder desconocido {pw.get('id')}")
            if not isinstance(pw.get("cooldown_days"), int) or pw["cooldown_days"] < 0:
                rep.error(w, f"{pw.get('id')}: cooldown_days debe ser un entero >= 0")
            if pw.get("ready") is not True and not (isinstance(pw.get("ready"), str) and pw["ready"]):
                rep.error(w, f"{pw.get('id')}: ready debe ser true o el hito que lo trae")
            check_text(w, f"power.{pw.get('id')}", strings, rep)
    if not offices:
        return set()
    pol = load_json(os.path.join(DATA, "politics.json"), rep) or {}
    w = "politics.json"
    g = pol.get("government") or {}
    for t in g.get("household_titles") or []:
        if t not in titles:
            rep.error(w, f"government.household_titles: título desconocido {t}")
    for o in g.get("start_vacant") or []:
        if o not in offices:
            rep.error(w, f"government.start_vacant: cargo desconocido {o}")
    if set((g.get("take_reputation") or {}).keys()) != set(H10_RANKS):
        rep.error(w, f"government.take_reputation debe tener los rangos {H10_RANKS}")
    el = pol.get("elections") or {}
    levels = el.get("levels") or {}
    if not levels or set(el.get("level_order") or []) != set(levels):
        rep.error(w, "elections.levels y level_order (los mismos niveles)")
    for lv, d in levels.items():
        if not isinstance(d.get("gold"), int) or not isinstance(d.get("bonus_permil"), int):
            rep.error(w, f"elections.levels.{lv}: gold y bonus_permil enteros")
        check_text(w, f"campaign.level.{lv}", strings, rep)
    v = el.get("vote") or {}
    if abs(sum(float(v.get(k, 0)) for k in ("affinity", "reputation", "class", "campaign")) - 1.0) > 0.0001:
        rep.error(w, "elections.vote: los pesos deben sumar 1")
    for k in ("relation_norm", "reputation_norm", "class_norm", "campaign_norm"):
        if not isinstance(v.get(k), int) or v[k] < 1:
            rep.error(w, f"elections.vote.{k} debe ser un entero >= 1")
    for a in H10_ACTIONS:
        if a not in (el.get("actions") or {}):
            rep.error(w, f"elections.actions.{a} falta")
        check_text(w, f"campaign.{a}", strings, rep)
    tx = pol.get("taxes") or {}
    if not (isinstance(tx.get("min"), int) and isinstance(tx.get("max"), int) and tx["min"] <= tx.get("default_percent", -1) <= tx["max"]):
        rep.error(w, "taxes: min <= default_percent <= max (enteros)")
    rg = pol.get("regulation") or {}
    for k in ("percent", "days", "fine_gold"):
        if not isinstance(rg.get(k), int) or rg[k] < 1:
            rep.error(w, f"regulation.{k} debe ser un entero >= 1")
    for pid, prof in load_kind("ai_profiles", rep).items():
        rule = prof.get("office_rule")
        if rule is None:
            continue
        for o in rule.get("offices") or []:
            if o not in offices:
                rep.error(f"ai_profiles/{pid}", f"office_rule: cargo desconocido {o}")
        if rule.get("level") not in levels:
            rep.error(f"ai_profiles/{pid}", f"office_rule: nivel desconocido {rule.get('level')}")
    for k in H10_REASONS:
        check_text("i18n/reason", "reason." + k, strings, rep)
    for k in H10_NOTICES:
        check_text("i18n/notice", "notice." + k, strings, rep)
    return set(offices)


def check_h10_scenario(w, d, offices, rep):
    """H10: en escenarios v10, offices {cargo: {seats: [{holder, since, until, cooldowns}], settings}} con cargos que
    existen y titulares que existen; elections lista de {id, office, day, campaign_day, status, candidates, result};
    market.regulations lista."""
    chars = d.get("characters") or {}
    for oid, o in (d.get("offices") or {}).items():
        if oid not in offices:
            rep.error(w, f"offices: cargo desconocido {oid}")
            continue
        if not isinstance(o, dict) or not isinstance(o.get("seats"), list):
            rep.error(w, f"offices.{oid}: debe ser {{seats: [...], settings}}")
            continue
        for s in o["seats"]:
            if s.get("holder") and s["holder"] not in chars:
                rep.error(w, f"offices.{oid}: titular desconocido {s['holder']}")
            if not isinstance(s.get("until"), int):
                rep.error(w, f"offices.{oid}: until debe ser un día (entero)")
    for e in d.get("elections") or []:
        if e.get("office") not in offices or e.get("status") not in ("open", "done"):
            rep.error(w, f"elections: {e.get('id')} con cargo o estado desconocido")
        for c in e.get("candidates") or []:
            if c.get("character") not in chars:
                rep.error(w, f"elections.{e.get('id')}: candidato desconocido {c.get('character')}")
    if not isinstance((d.get("market") or {}).get("regulations", []), list):
        rep.error(w, "market.regulations debe ser una lista")


H11_SENTENCE_KINDS = {"fine", "confiscation", "office_loss", "banishment"}
H11_REASONS = ["banished", "already_on_trial", "unknown_trial", "not_your_trial", "trial_not_preparing",
               "trial_not_in_hearing", "unknown_witness", "unknown_fact", "fact_not_usable", "unknown_charge",
               "needs_fact", "not_against", "already_crossed", "not_the_judge", "party_to_trial", "nothing_found",
               "not_banished", "already_favor"]
H11_NOTICES = ["trial_accused", "trial_accuser", "trial_other", "trial_hearing", "trial_verdict_guilty",
               "trial_verdict_innocent", "banished", "banishment_ended", "false_accusation", "witness_denounced"]


def check_h11(strings, rep):
    """H11 (GDD 4.12.5, docs/contratos/h11_tribunal.md): data/justice.json (cargos con gravedad conocida y texto,
    condenas de cada gravedad con su tipo, hechos con cargo conocido, testigos [mín, máx], acciones), la regla de
    acusación de los perfiles de IA y los textos de motivos, avisos, gravedades y condenas."""
    w = "justice.json"
    j = load_json(os.path.join(DATA, "justice.json"), rep) or {}
    sev = j.get("severities") or []
    charges = j.get("charges") or {}
    for cid, c in charges.items():
        if c.get("severity") not in sev:
            rep.error(w, f"charges.{cid}: gravedad desconocida {c.get('severity')}")
        check_text(w, c.get("name_key"), strings, rep)
    for s in sev:
        sd = (j.get("sentences") or {}).get(s)
        if not sd or sd.get("kind") not in H11_SENTENCE_KINDS:
            rep.error(w, f"sentences.{s}: falta o tipo desconocido")
        if not isinstance((sd or {}).get("reputation", 0), int):
            rep.error(w, f"sentences.{s}.reputation debe ser un entero")
        check_text(w, f"severity.{s}", strings, rep)
        check_text(w, f"sentence.{s}", strings, rep)
    for k, c in (j.get("facts") or {}).items():
        if c not in charges:
            rep.error(w, f"facts.{k}: cargo desconocido {c}")
    t = j.get("trial") or {}
    ws = t.get("witnesses")
    if not (isinstance(ws, list) and len(ws) == 2 and all(isinstance(x, int) for x in ws) and 1 <= ws[0] <= ws[1]):
        rep.error(w, "trial.witnesses debe ser [mín, máx]")
    for k in ("prep_days", "hearing_hours", "town_rhetoric"):
        if not isinstance(t.get(k), (int, float)) or t[k] <= 0:
            rep.error(w, f"trial.{k} debe ser > 0")
    cr = j.get("cross") or {}
    if not all(isinstance(cr.get(k), int) and cr[k] >= 0 for k in ("ok_weight", "fail_weight")):
        rep.error(w, "cross.ok_weight y cross.fail_weight deben ser enteros >= 0 (decisión del owner del 2026-11-02)")
    bd = j.get("bands") or {}
    if not (isinstance(bd.get("easy"), int) and isinstance(bd.get("doubtful"), int) and bd["easy"] > bd["doubtful"]):
        rep.error(w, "bands: easy > doubtful (enteros)")
    for k in ("convince", "bribe", "threaten"):
        if k not in (j.get("witness_actions") or {}):
            rep.error(w, f"witness_actions.{k} falta")
    if not isinstance(j.get("banishment_days"), int) or j["banishment_days"] < 1:
        rep.error(w, "banishment_days debe ser un entero >= 1")
    for pid, prof in load_kind("ai_profiles", rep).items():
        rule = prof.get("accuse_rule")
        if rule is not None and rule.get("fabricate_charge") not in charges:
            rep.error(f"ai_profiles/{pid}", f"accuse_rule.fabricate_charge desconocido {rule.get('fabricate_charge')}")
    for k in H11_REASONS:
        check_text("i18n/reason", "reason." + k, strings, rep)
    for k in H11_NOTICES:
        check_text("i18n/notice", "notice." + k, strings, rep)
    check_text("i18n", "trial.town", strings, rep)


def check_h11_scenario(w, d, rep):
    """H11: en escenarios v11, familias con attitudes {honesty, generosity, diplomacy} enteros; trials lista con
    acusado y testigos que existen; justice.facts lista."""
    chars = d.get("characters") or {}
    for fid, f in (d.get("families") or {}).items():
        a = f.get("attitudes")
        if not isinstance(a, dict) or any(not isinstance(a.get(k), int) for k in ("honesty", "generosity", "diplomacy")):
            rep.error(w, f"{fid}: attitudes debe ser {{honesty, generosity, diplomacy}} enteros")
    for t in d.get("trials") or []:
        if t.get("accused") not in chars:
            rep.error(w, f"trials.{t.get('id')}: acusado desconocido")
        for x in t.get("witnesses") or []:
            if x.get("character") not in chars:
                rep.error(w, f"trials.{t.get('id')}: testigo desconocido {x.get('character')}")
    if not isinstance((d.get("justice") or {}).get("facts"), list):
        rep.error(w, "justice.facts debe ser una lista")


H14_NOTICES = ["kin_exhausted", "kin_low_morale", "forge_short", "kin_supplied"]


def check_h14(strings, rep):
    """H14 (GDD 4.10.6, 4.2.6, docs/contratos/h14_ia_familiar.md): data/family.json directivas (cada una con ready true o
    su hito y con texto), necesidades (ids, start, cambios por hora enteros, eventos, low < recover_to, critical < low),
    moral, comercio y los textos de los avisos."""
    w = "family.json"
    fam = load_json(os.path.join(DATA, "family.json"), rep) or {}
    d = fam.get("directives") or {}
    known = d.get("known") or []
    for x in known:
        r = (d.get("ready") or {}).get(x)
        if r is not True and not (isinstance(r, str) and r):
            rep.error(w, f"directives.ready.{x}: true o el hito que la trae")
        check_text(w, f"directive.{x}", strings, rep)
    for x in d.get("default") or []:
        if x not in known:
            rep.error(w, f"directives.default: {x} desconocida")
    n = fam.get("needs") or {}
    ids = n.get("ids") or []
    if set(ids) != {"hunger", "rest", "social", "fun"}:
        rep.error(w, "needs.ids: hunger, rest, social, fun (GDD 4.2.6)")
    for k in ids:
        check_text(w, f"need.{k}", strings, rep)
        for sit, v in ((n.get("per_hour") or {}).get(k) or {}).items():
            if not isinstance(v, int):
                rep.error(w, f"needs.per_hour.{k}.{sit} debe ser un entero")
    for ev, eff in (n.get("events") or {}).items():
        if any(k not in ids or not isinstance(v, int) for k, v in eff.items()):
            rep.error(w, f"needs.events.{ev}: necesidades conocidas y enteros")
    if not (isinstance(n.get("critical"), int) and isinstance(n.get("low"), int) and isinstance(n.get("recover_to"), int)
            and n["critical"] < n["low"] < n["recover_to"] <= 100):
        rep.error(w, "needs: critical < low < recover_to <= 100")
    p = (fam.get("morale") or {}).get("productivity") or {}
    if not (0 < float(p.get("min_mult", 0)) <= 1 and 0 < int(p.get("full_at", 0)) <= 100):
        rep.error(w, "morale.productivity: 0 < min_mult <= 1 y 0 < full_at <= 100")
    t = fam.get("trade") or {}
    for k in ("min_stock", "buy_up_to", "gold_reserve", "keep_products", "max_carry_units"):
        if not isinstance(t.get(k), int) or t[k] < 0:
            rep.error(w, f"trade.{k} debe ser un entero >= 0")
    for k in H14_NOTICES:
        check_text("i18n/notice", "notice." + k, strings, rep)
    check_text("i18n/reason", "reason.directive_not_ready", strings, rep)


DUEL_CAUSES = {"offense", "courtship", "rivalry"}
DUEL_REASONS = ["no_cause", "too_young", "wounded", "busy", "cooldown", "kind_locked", "too_far", "unknown_duel",
                "not_challenged", "already_answered", "bad_answer", "not_challenger", "already_fighting", "not_fighting",
                "not_your_side", "duel_over", "already_chosen", "no_breath", "cannot_yield", "bad_action"]
DUEL_NOTICES = ["duel_challenged", "duel_accepted", "duel_refused", "duel_withdrawn", "duel_call", "duel_won",
                "duel_lost", "duel_draw", "duel_yielded", "duel_no_show_you", "duel_no_show_rival", "duel_cancelled",
                "duel_brawl"]


def CHARGES_OF(rep):
    j = load_json(os.path.join(DATA, "justice.json"), rep) or {}
    return set((j.get("charges") or {}).keys())


def check_combat(items, strings, rep):
    """Duelo «a tres tiempos» (docs/gdd/04e_combate.md, borrador): data/combat.json. Las tres acciones forman un ciclo
    (cada una gana a otra distinta), costes de aliento enteros y Parada sin coste; lectura con min <= base <= max en
    [0, 1]; tiradas enteras; armas con filo conocido y cifras enteras; tipos con toques > 0 y lances >= toques; los
    objetos de items y armor_items existen y caen en un arma conocida; probabilidades de la IA en [0, 1]; textos de
    acciones, tipos y armas."""
    w = "combat.json"
    c = load_json(os.path.join(DATA, "combat.json"), rep) or {}
    acts = c.get("actions") or {}
    if set(acts) != {"strike", "parry", "feint"}:
        rep.error(w, "actions: strike, parry y feint")
        return
    if {a.get("beats") for a in acts.values()} != set(acts) or any(k == a.get("beats") for k, a in acts.items()):
        rep.error(w, "actions.beats: cada acción gana a otra distinta y las tres forman un ciclo")
    for k, a in acts.items():
        if not isinstance(a.get("breath"), int):
            rep.error(w, f"actions.{k}.breath debe ser un entero (negativo = recupera)")
        check_text(w, f"combat.action.{k}", strings, rep)
        check_text(w, f"combat.action.{k}.hint", strings, rep)
    if isinstance(acts["parry"].get("breath"), int) and acts["parry"]["breath"] > 0:
        rep.error(w, "actions.parry.breath <= 0: sin aliento siempre se puede parar")
    b = c.get("breath") or {}
    if not isinstance(b.get("base"), int) or not isinstance(b.get("per_constitution"), (int, float)):
        rep.error(w, "breath: base entero y per_constitution numérico")
    r = c.get("read") or {}
    try:
        if not (0 <= float(r["min"]) <= float(r["base"]) <= float(r["max"]) <= 1 and float(r["step"]) >= 0):
            rep.error(w, "read: 0 <= min <= base <= max <= 1 y step >= 0")
        if r.get("stat") not in STATS or r.get("against") not in STATS:
            rep.error(w, "read.stat y read.against: atributos conocidos")
    except (KeyError, TypeError, ValueError):
        rep.error(w, "read: stat, against, base, step, min y max")
    for k in ("touch", "clash"):
        t = c.get(k) or {}
        if t.get("stat") not in STATS or any(not isinstance(t.get(x), int) for x in ("base", "step")):
            rep.error(w, f"{k}: stat conocido y base, step enteros")
    if not isinstance((c.get("touch") or {}).get("advantage"), int):
        rep.error(w, "touch.advantage debe ser un entero")
    ini = c.get("initiative") or {}
    if not isinstance(ini.get("blind"), int) or ini.get("blind") < 0 or ini.get("first") not in ("challenger", "challenged"):
        rep.error(w, "initiative: blind entero >= 0 y first challenger | challenged")
    weapons = c.get("weapons") or {}
    if "fists" not in weapons:
        rep.error(w, "weapons.fists: el arma de quien no lleva nada")
    for k, wp in weapons.items():
        if wp.get("edge") not in set(acts) | {""}:
            rep.error(w, f"weapons.{k}.edge: una acción o \"\"")
        for x in ("touch", "tie", "breath"):
            if not isinstance(wp.get(x), int):
                rep.error(w, f"weapons.{k}.{x} debe ser un entero")
        check_text(w, f"combat.weapon.{k}", strings, rep)
    for x in (c.get("armor") or {}, c.get("wounded") or {}):
        if not x:
            rep.error(w, "armor y wounded")
    for k, kd in (c.get("kinds") or {}).items():
        t, l = kd.get("touches"), kd.get("lances")
        if not (isinstance(t, int) and isinstance(l, int) and 0 < t <= l):
            rep.error(w, f"kinds.{k}: 0 < touches <= lances (enteros)")
        for x in ("wound", "can_yield", "locked"):
            if not isinstance(kd.get(x), bool):
                rep.error(w, f"kinds.{k}.{x} debe ser true o false")
        check_text(w, f"combat.kind.{k}", strings, rep)
    if not any(not kd.get("locked") for kd in (c.get("kinds") or {}).values()):
        rep.error(w, "kinds: al menos un tipo sin bloquear")
    ai = c.get("ai") or {}
    for x in ("habit", "edge_weight", "yield_chance"):
        if not isinstance(ai.get(x), (int, float)) or not 0 <= ai[x] <= 1:
            rep.error(w, f"ai.{x} en [0, 1]")
    for x in ("min_history", "yield_behind"):
        if not isinstance(ai.get(x), int) or ai[x] < 0:
            rep.error(w, f"ai.{x} entero >= 0")
    for it, wp in (c.get("items") or {}).items():
        if it not in items:
            rep.error(w, f"items.{it}: objeto desconocido")
        if wp not in weapons:
            rep.error(w, f"items.{it}: arma desconocida {wp}")
    for it in c.get("armor_items") or []:
        if it not in items:
            rep.error(w, f"armor_items: objeto desconocido {it}")
    # Duelo en la partida (docs/contratos/duelo.md): el reto, la respuesta de los NPC y las consecuencias.
    ch = c.get("challenge") or {}
    for x in ch.get("causes") or []:
        if x not in DUEL_CAUSES:
            rep.error(w, f"challenge.causes: causa desconocida {x}")
        check_text(w, f"combat.cause.{x}", strings, rep)
    if not ch.get("causes"):
        rep.error(w, "challenge.causes: al menos una causa")
    for x in ("courtship_min_affinity", "min_age", "cooldown_days", "answer_hour", "hour", "call_before", "present_tiles",
              "witness_tiles", "public_witnesses", "fight_timeout", "keep_closed"):
        if not isinstance(ch.get(x), int) or ch[x] < 0:
            rep.error(w, f"challenge.{x}: entero >= 0")
    for x in ("answer_hour", "hour"):
        if isinstance(ch.get(x), int) and not 0 <= ch[x] < 1440:
            rep.error(w, f"challenge.{x}: minuto del día en [0, 1440)")
    for k in ch.get("kinds_allowed") or []:
        if k not in (c.get("kinds") or {}) or (c["kinds"][k] or {}).get("locked"):
            rep.error(w, f"challenge.kinds_allowed: {k} no existe o está bloqueado")
    for x in ch.get("weapons_order") or []:
        if x not in weapons:
            rep.error(w, f"challenge.weapons_order: arma desconocida {x}")
    if not ch.get("ground"):
        rep.error(w, "challenge.ground: los spawns del mapa donde se celebra (el primero que exista)")
    for mid, m in load_kind("maps", rep).items():
        if not any(g in (m.get("spawns") or {}) for g in ch.get("ground") or []):
            rep.error(f"maps/{mid}", f"sin sitio para los duelos: ningún spawn de {ch.get('ground')}")
    aa = c.get("ai_answer") or {}
    for x in ("accept_min", "risk_step", "near_miss"):
        if not isinstance(aa.get(x), (int, float)) or not 0 <= aa[x] <= 1:
            rep.error(w, f"ai_answer.{x} en [0, 1]")
    for x in ("samples", "title_gap_free"):
        if not isinstance(aa.get(x), int) or aa[x] < 1:
            rep.error(w, f"ai_answer.{x}: entero >= 1")
    co = c.get("consequences") or {}
    for x in ("win", "lose", "draw", "yield", "refuse", "no_show", "withdraw"):
        if not isinstance((co.get(x) or {}).get("reputation"), int) or not isinstance((co.get(x) or {}).get("relation"), int):
            rep.error(w, f"consequences.{x}: reputation y relation enteros")
        check_text(w, f"rep.reason.duel_{x}", strings, rep)
    for x in ("duel_no_show_rival", "duel_challenge_refused", "duel_brawl"):
        check_text(w, f"rep.reason.{x}", strings, rep)
    if not isinstance(co.get("public_mult"), int) or co["public_mult"] < 1:
        rep.error(w, "consequences.public_mult: entero >= 1")
    if (co.get("brawl") or {}).get("charge") not in CHARGES_OF(rep):
        rep.error(w, "consequences.brawl.charge: un cargo de data/justice.json")
    for x in DUEL_REASONS:
        check_text("i18n/reason", "reason." + x, strings, rep)
    for x in DUEL_NOTICES:
        check_text("i18n/notice", "notice." + x, strings, rep)


H13_NOTICES = ["event_started", "event_declared", "event_ended"]
H13_REASONS = ["event_active", "event_excluded", "too_many_events", "event_disabled", "unknown_event"]
H13_EFFECTS = {"price", "demand", "production", "customers", "errands", "mortality"}
H13_GROUP_EFFECTS = {"price", "demand", "production"}


def check_h13(items, strings, rep):
    """H13 (GDD 4.5.3 fase 2, 4.13): data/seasons.json (grupos de objetos conocidos, multiplicadores > 0 por estación y
    grupo, con texto) y data/events.json (scope, disparador con probabilidades en [0, 1] por estación, duración en
    estaciones o días, excludes conocidos, efectos conocidos sobre grupos conocidos, texto y frase; los desactivados
    con disabled_reason; los declarables, activos y locales)."""
    time = load_json(os.path.join(DATA, "time.json"), rep) or {}
    seasons_ids = time.get("seasons", [])
    w = "seasons.json"
    sea = load_json(os.path.join(DATA, "seasons.json"), rep) or {}
    groups = sea.get("goods") or {}
    for g, its in groups.items():
        check_text(w, f"goods.{g}", strings, rep)
        for it in its:
            if it not in items:
                rep.error(w, f"goods.{g}: objeto desconocido {it}")
    for table in ("price", "production"):
        for s_, by in (sea.get(table) or {}).items():
            if s_ not in seasons_ids:
                rep.error(w, f"{table}.{s_}: estación desconocida")
            for g, m in (by or {}).items():
                if g not in groups:
                    rep.error(w, f"{table}.{s_}.{g}: grupo desconocido")
                if not isinstance(m, (int, float)) or m <= 0:
                    rep.error(w, f"{table}.{s_}.{g}: multiplicador > 0")
    w = "events.json"
    evd = load_json(os.path.join(DATA, "events.json"), rep) or {}
    evs = evd.get("events") or {}
    rules = evd.get("rules") or {}
    for k in ("max_active", "max_local_active"):
        if not isinstance(rules.get(k), int) or rules[k] < 1:
            rep.error(w, f"rules.{k}: entero >= 1")
    for id_, ev in evs.items():
        we = f"events.json/{id_}"
        check_text(we, ev.get("text_key"), strings, rep)
        check_text(we, (ev.get("text_key") or "") + ".desc", strings, rep)
        if ev.get("scope") not in ("season", "local"):
            rep.error(we, "scope: season o local")
        if not isinstance(ev.get("enabled"), bool):
            rep.error(we, "enabled: true o false")
        elif not ev["enabled"] and not ev.get("disabled_reason"):
            rep.error(we, "desactivado: falta disabled_reason")
        trig = ev.get("trigger") or {}
        want_at = "season_start" if ev.get("scope") == "season" else "day_start"
        if trig.get("at") != want_at:
            rep.error(we, f"trigger.at: {want_at} para scope {ev.get('scope')}")
        ch = trig.get("chance") or {}
        if set(ch) != set(seasons_ids) or not all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in ch.values()):
            rep.error(we, "trigger.chance: una probabilidad en [0, 1] por estación")
        if not isinstance(trig.get("min_day", 0), int):
            rep.error(we, "trigger.min_day: entero")
        dur = ev.get("duration") or {}
        key = "seasons" if ev.get("scope") == "season" else "days"
        if not _range_ok(dur.get(key), 1):
            rep.error(we, f"duration.{key}: [mín, máx] >= 1")
        for x in ev.get("excludes") or []:
            if x not in evs:
                rep.error(we, f"excludes: evento desconocido {x}")
        if ev.get("declarable") and (not ev.get("enabled") or ev.get("scope") != "local"):
            rep.error(we, "declarable: solo eventos activos y locales (el Alcalde no declara una guerra)")
        for e in ev.get("effects") or []:
            k = e.get("kind")
            if k not in H13_EFFECTS:
                rep.error(we, f"efecto desconocido {k}")
            elif k in H13_GROUP_EFFECTS and e.get("group") not in groups:
                rep.error(we, f"efecto {k}: grupo desconocido {e.get('group')}")
            if not isinstance(e.get("mult"), (int, float)) or e["mult"] <= 0:
                rep.error(we, f"efecto {k}: mult > 0")
        if ev.get("enabled") and not ev.get("effects"):
            rep.error(we, "activo sin efectos")
    for k in H13_NOTICES:
        check_text("i18n/notice", "notice." + k, strings, rep)
    for k in H13_REASONS:
        check_text("i18n/reason", "reason." + k, strings, rep)


CLASSES = {"artisan", "patron", "scholar", "rogue"}


def check_h12(items, recipes, buildings, maps, strings, rep):
    """H12 (GDD 4.2.1): data/professions/ y los competidores de data/starts/."""
    profs = load_kind("professions", rep)
    starts = load_kind("starts", rep)
    tables = load_kind("contracts", rep)
    profiles = load_kind("ai_profiles", rep)
    emp = load_json(os.path.join(DATA, "employees.json"), rep) or {}
    roles = emp.get("roles") or {}
    orders = {}
    for pid, pf in profs.items():
        w = f"professions/{pid}"
        check_text(w, pf.get("name_key"), strings, rep)
        if pf.get("class") not in CLASSES:
            rep.error(w, f"clase desconocida {pf.get('class')} (una de {sorted(CLASSES)})")
        if not isinstance(pf.get("order"), int):
            rep.error(w, "order debe ser un entero (orden en la pantalla de partida nueva)")
        elif (pf.get("class"), pf["order"]) in orders:
            rep.error(w, f"order {pf['order']} repetido en la clase {pf.get('class')} (también {orders[(pf.get('class'), pf['order'])]})")
        else:
            orders[(pf.get("class"), pf["order"])] = pid
        b = buildings.get(pf.get("building"))
        if b is None:
            rep.error(w, f"taller desconocido {pf.get('building')}")
        elif b.get("tool") != pf.get("tool"):
            rep.error(w, f"tool {pf.get('tool')} distinta de la del edificio ({b.get('tool')})")
        if (items.get(pf.get("tool")) or {}).get("slot") != "tool":
            rep.error(w, f"tool {pf.get('tool')}: no es un objeto de la ranura tool")
        st = starts.get(pf.get("start"))
        if st is None:
            rep.error(w, f"inicio desconocido {pf.get('start')}")
        else:
            if st.get("profession") != pid or st.get("class") != pf.get("class"):
                rep.error(w, f"el inicio {pf['start']} es de {st.get('class')}/{st.get('profession')}")
            if (st.get("building") or {}).get("type") != pf.get("building"):
                rep.error(w, f"el inicio {pf['start']} no empieza en un {pf.get('building')}")
            tool = ((st.get("protagonist") or {}).get("equipment") or {}).get("tool") or {}
            if tool.get("item") != pf.get("tool"):
                rep.warn(w, f"el inicio {pf['start']} no equipa {pf.get('tool')}")
        ct = tables.get(pf.get("contracts"))
        if ct is None or ct.get("profession") != pid:
            rep.error(w, f"tabla de encargos {pf.get('contracts')}: no existe o no es de {pid}")
        else:
            made = {r.get("output", {}).get("item") for r in recipes.values() if r.get("building") == pf.get("building")}
            for it in ct.get("items") or []:
                if it.get("item") not in made:
                    rep.error(w, f"la tabla {pf['contracts']} pide {it.get('item')} y el {pf.get('building')} no lo fabrica")
        if b is not None:
            for z in b.get("zones", []):
                if z.get("kind") == "craft" and z.get("id") not in roles:
                    rep.error(w, f"el puesto {z.get('id')} no tiene rol de empleado en employees.json")
    for sid, s in starts.items():
        w = f"starts/{sid}"
        if s.get("profession") not in profs:
            rep.error(w, f"oficio sin ficha en data/professions: {s.get('profession')}")
        walk = maps.get(s.get("map"))
        sites = (walk.map.get("buildings") or {}) if walk else {}
        used = [(s.get("building") or {}).get("site"), ((s.get("rival") or {}).get("building") or {}).get("site")]
        if (s.get("rival") or {}).get("profession") not in (None,) and s["rival"]["profession"] not in profs:
            rep.error(w, f"rival.profession desconocida {s['rival']['profession']}")
        for i, cp in enumerate(s.get("competitors") or []):
            wc = f"{w} competitors[{i}]"
            if cp.get("profile") not in profiles:
                rep.error(wc, f"perfil desconocido {cp.get('profile')}")
            if cp.get("profession") not in profs:
                rep.error(wc, f"oficio desconocido {cp.get('profession')}")
            ch = cp.get("character") or {}
            if sorted(ch.get("stats") or {}) != sorted(STATS):
                rep.error(wc, "character.stats: los 10 atributos")
            if not (isinstance(ch.get("name"), str) and ch["name"].strip()):
                rep.error(wc, "character.name")
            if not isinstance(cp.get("gold"), int):
                rep.error(wc, "gold debe ser un entero")
            cb = cp.get("building") or {}
            site = sites.get(cb.get("site"))
            if site is None:
                rep.error(wc, f"building.site {cb.get('site')} no es un edificio del mapa")
            elif site.get("type") != cb.get("type"):
                rep.error(wc, f"tipo {cb.get('type')} distinto del del mapa {site.get('type')}")
            elif profs.get(cp.get("profession"), {}).get("building") != cb.get("type"):
                rep.error(wc, f"un {cp.get('profession')} en un {cb.get('type')}")
            for stk in cb.get("inventory") or []:
                if stk.get("item") not in items:
                    rep.error(wc, f"objeto desconocido {stk.get('item')}")
            used.append(cb.get("site"))
        dup = sorted({x for x in used if x and used.count(x) > 1})
        if dup:
            rep.error(w, f"solares repetidos entre protagonista, rival y competidores: {dup}")
        # a map may offer several sites on the same lot (rival_forge / rival_carpentry...): a start uses one of them
        taken = {}
        for name in [x for x in used if x in sites]:
            st_ = sites[name]
            fp = (buildings.get(st_.get("type")) or {}).get("footprint") or [1, 1]
            for dc in range(fp[0]):
                for dr in range(fp[1]):
                    cell = (st_["origin"][0] + dc, st_["origin"][1] + dr)
                    if cell in taken and taken[cell] != name:
                        rep.error(w, f"los solares {taken[cell]} y {name} se pisan en {list(cell)}")
                        break
                    taken[cell] = name
                else:
                    continue
                break


def check_h5(items, recipes, buildings, ranks, strings, rep):
    """H5 (GDD 4.8, docs/contratos/h5_mejoras.md): data/upgrade_rules.json y cada mejora (rama y nivel, coste,
    requisitos que existen en su árbol, nivel N pide el N-1, sin ciclos, efectos de tipos conocidos con su valor,
    puestos nuevos que trabajan como un puesto del edificio, recetas que se desbloquean coherentes con su requires_upgrade,
    visuales como ids), los árboles de los edificios y las claves de texto."""
    w0 = "upgrade_rules.json"
    rules = load_json(os.path.join(DATA, "upgrade_rules.json"), rep) or {}
    branches, levels = rules.get("branches", []), rules.get("levels")
    if not (isinstance(branches, list) and branches and all(isinstance(b, str) and ID_RE.match(b) for b in branches)):
        rep.error(w0, "branches debe ser una lista de ids")
        branches = []
    if not isinstance(levels, int) or levels < 1:
        rep.error(w0, "levels debe ser un entero >= 1")
        levels = 0
    for b in branches:
        check_text(w0, f"branch.{b}", strings, rep)
    kinds = rules.get("effect_kinds", {})
    for k, ek in kinds.items():
        if k.startswith("_"):
            continue
        if ek.get("value") not in EFFECT_VALUES or ek.get("stack") not in EFFECT_STACKS \
                or ek.get("when") not in EFFECT_WHEN or ek.get("reader") not in EFFECT_READERS:
            rep.error(w0, f"effect_kinds.{k}: value {sorted(EFFECT_VALUES)}, stack {sorted(EFFECT_STACKS)}, "
                          f"when {sorted(EFFECT_WHEN)}, reader {sorted(EFFECT_READERS)}")
        check_text(w0, f"effect.{k}", strings, rep)
    titles = rules.get("titles", [])
    if not (isinstance(titles, list) and titles) or rules.get("default_title") not in titles:
        rep.error(w0, "titles debe ser una lista y default_title uno de ellos")
    ins = rules.get("inspections", {})
    fine = ins.get("fine")
    if not (isinstance(fine, list) and len(fine) == 2 and all(isinstance(x, int) for x in fine) and 0 <= fine[0] <= fine[1]):
        rep.error(w0, "inspections.fine debe ser [mín, máx] en oro entero")
    for k in ("honesty_divisor", "escape_cooldown_days"):
        if not isinstance(ins.get(k), int) or ins[k] < 1:
            rep.error(w0, f"inspections.{k} debe ser un entero >= 1")
    if not isinstance(ins.get("reputation"), int):
        rep.error(w0, "inspections.reputation debe ser un entero")

    trees = {}
    for id_, u in UPGRADES.items():
        trees.setdefault(u["tree"], []).append(id_)
    slot = {}
    for id_, u in sorted(UPGRADES.items()):
        w = f"upgrades/{u['tree']}/{id_}"
        check_text(w, u.get("name_key"), strings, rep)
        br, lv = u.get("branch"), u.get("level")
        if br not in branches:
            rep.error(w, f"rama desconocida {br}")
        if not isinstance(lv, int) or not 1 <= lv <= max(levels, 1):
            rep.error(w, f"nivel {lv} fuera de 1..{levels}")
        key = (u["tree"], br, lv)
        if key in slot:
            rep.error(w, f"misma rama y nivel que {slot[key]}")
        slot[key] = id_
        cost = u.get("cost", {})
        if not isinstance(cost.get("gold"), int) or cost["gold"] < 0:
            rep.error(w, "cost.gold debe ser un entero >= 0")
        for c in cost.get("items", []):
            if c.get("item") not in items:
                rep.error(w, f"material desconocido {c.get('item')}")
            if not isinstance(c.get("qty"), int) or c["qty"] < 1:
                rep.error(w, f"cantidad no válida para {c.get('item')}")
        days = u.get("build_days")
        if not isinstance(days, (int, float)) or days <= 0:
            rep.error(w, "build_days debe ser > 0 (días de juego)")
        elif not 0.5 <= days <= 2:
            rep.warn(w, f"build_days {days} fuera de 0,5-2 días (fila H5 de 10_hitos)")
        req = u.get("requires", {})
        ups = req.get("upgrades", [])
        if not isinstance(ups, list):
            rep.error(w, "requires.upgrades debe ser una lista")
            ups = []
        for r in ups:
            if r not in UPGRADES:
                rep.error(w, f"requiere la mejora desconocida {r}")
            elif UPGRADES[r]["tree"] != u["tree"]:
                rep.error(w, f"requiere {r}, de otro árbol")
        if isinstance(lv, int) and lv > 1 and not any(
                UPGRADES.get(r, {}).get("branch") == br and UPGRADES.get(r, {}).get("level") == lv - 1 for r in ups):
            rep.error(w, f"el nivel {lv} debe requerir el {lv - 1} de su rama")
        stat = req.get("stat")
        if stat is not None and not (isinstance(stat, dict) and stat.get("id") in STATS
                                     and isinstance(stat.get("min"), int) and 1 <= stat["min"] <= 10):
            rep.error(w, "requires.stat debe ser {id, min 1-10} o null")
        if req.get("title") is not None and req["title"] not in titles:
            rep.error(w, f"título desconocido {req['title']}")
        btypes = [bid for bid, b in buildings.items() if b.get("upgrade_tree") == u["tree"]]
        for e in u.get("effects", []):
            k = e.get("kind")
            ek = kinds.get(k)
            if not isinstance(ek, dict):
                rep.error(w, f"efecto de tipo desconocido {k}")
                continue
            v = ek.get("value")
            if v != "flag" and v not in e:
                rep.error(w, f"el efecto {k} necesita {v}")
                continue
            if v == "mult" and not (isinstance(e["mult"], (int, float)) and e["mult"] > 0):
                rep.error(w, f"{k}: mult debe ser > 0")
            elif v == "amount" and not isinstance(e["amount"], (int, float)):
                rep.error(w, f"{k}: amount debe ser un número")
            elif v == "recipe":
                if e["recipe"] not in recipes:
                    rep.error(w, f"{k}: receta desconocida {e['recipe']}")
                elif recipes[e["recipe"]].get("requires_upgrade") != id_:
                    rep.error(w, f"{k}: la receta {e['recipe']} no pide esta mejora (requires_upgrade)")
            elif v == "rank" and e["rank"] not in ranks:
                rep.error(w, f"{k}: rango desconocido {e['rank']}")
            elif v == "zone":
                if not ID_RE.match(str(e["zone"])):
                    rep.error(w, f"{k}: zone debe ser un id")
                for bid in btypes:
                    b = buildings[bid]
                    own = {z.get("id") for z in b.get("zones", [])}
                    if e["zone"] in own:
                        rep.error(w, f"{k}: {bid} ya tiene el puesto {e['zone']}")
                    if e.get("like", e["zone"]) not in own:
                        rep.error(w, f"{k}: like {e.get('like')} no es un puesto de {bid}")
        vis = u.get("visual")
        if not isinstance(vis, dict) or set(vis) != {"interior_node", "exterior_overlay"}:
            rep.error(w, "visual debe ser {interior_node, exterior_overlay}")
        else:
            for k2, v2 in vis.items():
                if v2 is not None and not (isinstance(v2, str) and ID_RE.match(v2)):
                    rep.error(w, f"visual.{k2} debe ser un id de game/visuals/ (snake_case) o null, no una ruta")

    def loops(id_, seen):
        if id_ in seen:
            return True
        return any(loops(r, seen | {id_}) for r in UPGRADES.get(id_, {}).get("requires", {}).get("upgrades", [])
                   if r in UPGRADES)
    for id_ in sorted(UPGRADES):
        if loops(id_, frozenset()):
            rep.error(f"upgrades/{UPGRADES[id_]['tree']}/{id_}", "los requisitos vuelven a ella (ciclo)")
    for tree, ids in sorted(trees.items()):
        used = {UPGRADES[i]["branch"] for i in ids}  # posada: cada árbol avisa solo de las ramas que usa
        for br in branches:
            if br not in used:
                continue
            for lv in range(1, levels + 1):
                if (tree, br, lv) not in slot:
                    rep.warn(f"upgrades/{tree}", f"falta el nivel {lv} de la rama {br}")
    for bid, b in buildings.items():
        t = b.get("upgrade_tree")
        if t and t not in trees:
            rep.error(f"buildings/{bid}", f"upgrade_tree {t} sin mejoras en data/upgrades/{t}/")


def check_h5_scenario(where, d, buildings, rep):
    """Escenarios v6: mejoras terminadas de su árbol y con sus requisitos, obra en curso coherente, memoria de
    inspecciones."""
    chars = d.get("characters") or {}
    for bid, b in (d.get("buildings") or {}).items():
        w = f"{where} {bid}"
        tree = (buildings.get(b.get("type")) or {}).get("upgrade_tree")
        ups = b.get("upgrades")
        if not isinstance(ups, list):
            rep.error(w, "upgrades debe ser una lista de ids")
            ups = []
        for u in ups:
            if u not in UPGRADES or UPGRADES[u]["tree"] != tree:
                rep.error(w, f"mejora {u} desconocida o de otro árbol")
                continue
            miss = [r for r in UPGRADES[u].get("requires", {}).get("upgrades", []) if r not in ups]
            if miss:
                rep.error(w, f"{u} sin sus requisitos {miss}")
        if len(set(ups)) != len(ups):
            rep.error(w, "mejora repetida")
        wk = b.get("upgrade_work", "falta")
        if wk is not None:
            if not isinstance(wk, dict) or not all(k in wk for k in ("upgrade", "actor", "start", "end")):
                rep.error(w, "upgrade_work debe ser null o {upgrade, actor, start, end}")
            else:
                if wk["upgrade"] not in UPGRADES or UPGRADES[wk["upgrade"]]["tree"] != tree or wk["upgrade"] in ups:
                    rep.error(w, f"obra de {wk['upgrade']}: desconocida, de otro árbol o ya terminada")
                if wk["actor"] not in chars:
                    rep.error(w, f"obra: actor desconocido {wk['actor']}")
                if not (isinstance(wk["start"], int) and isinstance(wk["end"], int) and wk["start"] < wk["end"]):
                    rep.error(w, "obra: start < end en minutos enteros")
        ins = b.get("inspection")
        keys = ("last_day", "caught", "escaped", "fines", "escape_ready_day")
        if not (isinstance(ins, dict) and all(isinstance(ins.get(k), int) for k in keys)):
            rep.error(w, f"inspection debe tener {list(keys)} enteros")


TUTORIAL_RULES = os.path.join(ROOT, "game", "ui", "tutorial", "tutorial_rules.gd")
TUTORIAL_ADVANCE = {"action", "next"}
TUTORIAL_UI_NAME = re.compile(r"^[A-Za-z0-9_*]+$")


REGION_KINDS = {"villa", "capital", "port", "quarry", "hamlet", "abbey"}
REGION_TERRAINS = {"road", "royal_road", "river", "mountain", "ridge", "forest", "ford"}


def check_region(items, strings, rep):
    """data/world/region.json (docs/gdd/09b_region.md): the settlements and routes of the region. Design and view
    only (the sim does not read it), but it must hold together: unique ids, routes between settlements that exist,
    no repeated pair, the region connected, every map in data/maps, every text in i18n, positions on the map image,
    the items and goods groups of the price multipliers known, the events that cut a route known."""
    w = "world/region.json"
    path = os.path.join(DATA, "world", "region.json")
    if not os.path.exists(path):
        return
    r = load_json(path, rep)
    if not isinstance(r, dict):
        return
    check_text(w, r.get("name_key", ""), strings, rep)
    size = r.get("map", {}).get("size", [0, 0])
    img = os.path.join(ROOT, "assets", "art", "region", f"{r.get('id', '')}_map.png")
    if not os.path.exists(img):
        rep.error(w, f"falta el pergamino {os.path.relpath(img, ROOT)} (VisualPaths.region_map)")
    seasons = load_json(os.path.join(DATA, "seasons.json"), rep) or {}
    groups = set(seasons.get("goods", {}))
    events = set((load_json(os.path.join(DATA, "events.json"), rep) or {}).get("events", {}))
    trade = load_json(os.path.join(DATA, "world", "trade.json"), rep) or {}
    proposed = {k for k in trade.get("regional_events", {}) if not k.startswith("_")}
    ids = []
    for st in r.get("settlements", []):
        sid = str(st.get("id", ""))
        ws = f"{w} {sid}"
        if not ID_RE.match(sid):
            rep.error(ws, "id no es inglés en snake_case")
        if sid in ids:
            rep.error(ws, "id repetido")
        ids.append(sid)
        if st.get("kind") not in REGION_KINDS:
            rep.error(ws, f"kind desconocido {st.get('kind')}")
        for k in ("name_key", "rulers", "specialty"):
            check_text(ws, str(st.get(k, "")), strings, rep)
        mid = str(st.get("map", ""))
        mp = os.path.join(DATA, "maps", mid + ".json")
        if not os.path.exists(mp):
            rep.error(ws, f"el mapa {mid} no existe en data/maps")
        else:
            m = load_json(mp, rep) or {}
            if list(m.get("size", [])) != list(st.get("map_size", [])):
                rep.error(ws, f"map_size {st.get('map_size')} no es el tamaño del mapa {mid} ({m.get('size')})")
            if len(m.get("population", [])) != st.get("households"):
                rep.error(ws, f"households {st.get('households')}: el mapa {mid} tiene {len(m.get('population', []))}")
        pos = st.get("pos", [])
        if not (isinstance(pos, list) and len(pos) == 2 and 0 <= pos[0] < size[0] and 0 <= pos[1] < size[1]):
            rep.error(ws, f"pos {pos} fuera del mapa regional {size}")
        for side in ("cheap", "dear"):
            for k, v in st.get(side, {}).items():
                if k not in items and k not in groups:
                    rep.error(ws, f"{side}: {k} no es un objeto ni un grupo de data/seasons.json goods")
                if not isinstance(v, (int, float)) or v <= 0 or (side == "cheap" and v >= 1) or (side == "dear" and v <= 1):
                    rep.error(ws, f"{side}: {k} ×{v} (barato < 1 < caro)")
        t = st.get("tariff", 0)
        if not isinstance(t, (int, float)) or not 0 <= t < 1:
            rep.error(ws, f"tariff {t} debe estar en [0, 1)")
    if r.get("home") not in ids:
        rep.error(w, f"home {r.get('home')} no es un asentamiento")
    adj = {i: set() for i in ids}
    pairs = set()
    rids = set()
    for rt in r.get("routes", []):
        rid = str(rt.get("id", ""))
        wr = f"{w} ruta {rid}"
        if rid in rids:
            rep.error(wr, "id repetido")
        rids.add(rid)
        a, b = rt.get("a"), rt.get("b")
        if a not in adj or b not in adj:
            rep.error(wr, f"une {a} y {b}: alguno no es un asentamiento")
            continue
        if a == b:
            rep.error(wr, "une un asentamiento consigo mismo")
        pair = tuple(sorted((a, b)))
        if pair in pairs:
            rep.error(wr, f"ya hay una ruta entre {a} y {b}")
        pairs.add(pair)
        adj[a].add(b)
        adj[b].add(a)
        if not isinstance(rt.get("hours"), (int, float)) or rt["hours"] <= 0:
            rep.error(wr, "hours debe ser > 0 (horas de juego)")
        if not isinstance(rt.get("risk"), int) or not 0 <= rt["risk"] <= 5:
            rep.error(wr, "risk debe ser un entero de 0 a 5")
        if rt.get("terrain") not in REGION_TERRAINS:
            rep.error(wr, f"terrain desconocido {rt.get('terrain')}")
        check_text(wr, "region.terrain." + str(rt.get("terrain", "")), strings, rep)
        for e in rt.get("cut_by", []):
            if e not in events and e not in proposed:
                rep.error(wr, f"cut_by {e}: no es un evento de data/events.json ni de trade.json regional_events")
        if not isinstance(rt.get("toll", 0), int) or rt.get("toll", 0) < 0:
            rep.error(wr, "toll debe ser un entero >= 0 (oro por tramo)")
        for pt in rt.get("path", []):
            if not (isinstance(pt, list) and len(pt) == 2 and 0 <= pt[0] < size[0] and 0 <= pt[1] < size[1]):
                rep.error(wr, f"path {pt} fuera del mapa regional")
    check_trade(trade, items, strings, proposed, rep)
    if ids:
        seen = {ids[0]}
        todo = [ids[0]]
        while todo:
            for n in adj[todo.pop()]:
                if n not in seen:
                    seen.add(n)
                    todo.append(n)
        if len(seen) != len(ids):
            rep.error(w, f"la región no es conexa: no se llega a {sorted(set(ids) - seen)}")


VIAJES_REASONS = ["title_needed", "not_adult", "employee", "on_the_road", "unknown_city", "already_there",
                  "no_open_route", "not_in_city", "not_traded", "unknown_contract", "wrong_city", "too_many_carts",
                  "no_free_cart", "unknown_driver", "not_your_employee", "driver_away", "empty_caravan", "bad_line",
                  "too_many_stacks", "unknown_kind", "reputation_needed", "needs_item", "not_a_dear_item",
                  "already_signed", "item_taken", "not_the_head", "not_the_mayor", "away", "not_a_town_kind",
                  "council_said_no", "unknown_treaty"]
VIAJES_NOTICES = ["region_event", "trip_stopped", "trip_ambushed", "trip_arrived", "trip_returned",
                  "city_contract_failed", "cart_upkeep_unpaid", "caravan_toll_unpaid", "caravan_ambushed",
                  "caravan_arrived", "caravan_back", "treaty_signed", "treaty_ended", "treaty_broken"]


def check_trade(trade, items, strings, regional, rep):
    """data/world/trade.json (viajes, sim/region/): the rules of travel, the cities' markets, caravans, treaties and
    the regional events; and the texts of their reasons and notices."""
    w = "world/trade.json"
    titles = {n[:-5] for n in os.listdir(os.path.join(DATA, "titles")) if n.endswith(".json")}
    tr = trade.get("travel", {})
    if tr.get("unlock_title") not in titles:
        rep.error(w, f"travel.unlock_title {tr.get('unlock_title')} no es un título")
    for k in ("escort_cost", "ambush_per_risk", "escort_divisor"):
        if not isinstance(tr.get(k), (int, float)) or tr[k] < 0:
            rep.error(w, f"travel.{k} debe ser un número >= 0")
    if tr.get("escort_divisor", 1) < 1:
        rep.error(w, "travel.escort_divisor debe ser >= 1")
    kinds = trade.get("treaties", {}).get("kinds", {})
    for k in ("exemption", "exclusivity", "quota"):
        if k not in kinds:
            rep.error(w, f"falta el tratado {k}")
            continue
        d = kinds[k]
        if d.get("title") not in titles:
            rep.error(w, f"treaties.{k}.title {d.get('title')} no es un título")
        for f in ("reputation", "seasons", "fee"):
            if not isinstance(d.get(f), int) or d[f] < 0:
                rep.error(w, f"treaties.{k}.{f} debe ser un entero >= 0")
        check_text(w, "treaty." + k, strings, rep)
    for k in trade.get("treaties", {}).get("town_kinds", []):
        if k not in kinds:
            rep.error(w, f"treaties.town_kinds: {k} no es un tratado")
    seasons = load_json(os.path.join(DATA, "time.json"), rep).get("seasons", [])
    for k in regional:
        d = trade["regional_events"][k]
        check_text(f"{w} regional_events.{k}", str(d.get("text_key", "")), strings, rep)
        if sorted(d.get("chance", {})) != sorted(seasons):
            rep.error(w, f"regional_events.{k}.chance: una probabilidad por estación")
        if not all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in d.get("chance", {}).values()):
            rep.error(w, f"regional_events.{k}.chance: en [0, 1]")
        for t in d.get("cuts", []):
            if t not in REGION_TERRAINS:
                rep.error(w, f"regional_events.{k}.cuts: terreno desconocido {t}")
    cv = trade.get("caravans", {})
    for k in ("cart_price", "cart_upkeep", "capacity_stacks", "max_carts"):
        if not isinstance(cv.get(k), int) or cv[k] < 0:
            rep.error(w, f"caravans.{k} debe ser un entero >= 0")
    for k in VIAJES_REASONS:
        check_text("i18n/reason", "reason." + k, strings, rep)
    for k in VIAJES_NOTICES:
        check_text("i18n/notice", "notice." + k, strings, rep)


def _gd_const_list(src, name):
    """Las cadenas de `const NAME: Array[String] = [ ... ]` (o las claves de un Dictionary con sus listas)."""
    m = re.search(r"const %s: [A-Za-z\[\]]+ = [\[{](.*?)\n[\]}]" % name, src, re.S)
    if not m:
        return None
    body = m.group(1)
    if "{" in src[m.start():m.end()].split("=", 1)[1][:3]:
        return {k: re.findall(r'"([a-z_]+)"', v) for k, v in re.findall(r'"([a-z_]+)": \[([^\]]*)\]', body)}
    return re.findall(r'"([^"]+)"', body)


def check_tutorial(strings, starts, scenarios, items, buildings, maps_raw, rep):
    """docs/ui/05_tutorial.md: data/tutorial.json y data/tutorial/<capítulo>.json. Disparadores conocidos (los tipos
    de evento que emite el sim, los de la UI y las condiciones de game/ui/tutorial/tutorial_rules.gd), textos en i18n
    con sus {huecos}, objetivos de resaltado con forma válida, abridores y pistas."""
    w0 = "tutorial.json"
    cfg = load_json(os.path.join(DATA, "tutorial.json"), rep) if os.path.exists(os.path.join(DATA, "tutorial.json")) else None
    if cfg is None:
        return
    try:
        src = open(TUTORIAL_RULES, encoding="utf-8").read()
    except OSError:
        rep.error(w0, "falta game/ui/tutorial/tutorial_rules.gd (las listas de disparadores)")
        return
    ui_events = set(_gd_const_list(src, "UI_EVENTS") or [])
    conditions = _gd_const_list(src, "CONDITIONS") or {}
    zones = set(_gd_const_list(src, "ZONES") or [])
    world_kinds = _gd_const_list(src, "WORLD_KINDS") or {}
    symbols = set(_gd_const_list(src, "SYMBOLS") or [])
    holes = set(_gd_const_list(src, "PLACEHOLDERS") or [])
    if not (ui_events and conditions and zones and world_kinds and symbols):
        rep.error(w0, "no se pueden leer las listas de tutorial_rules.gd")
        return
    sim_events = set()
    for dp, _dn, fns in os.walk(os.path.join(ROOT, "sim")):
        for fn in fns:
            if fn.endswith(".gd"):
                sim_events.update(re.findall(r'"type": "([a-z_]+)"', open(os.path.join(dp, fn), encoding="utf-8").read()))
    panels = cfg.get("panels")
    if not (isinstance(panels, list) and all(isinstance(p, str) and TUTORIAL_UI_NAME.match(p) for p in panels)):
        rep.error(w0, "panels: lista de nombres de nodo")
        panels = []
    panels = set(panels)
    stations = {z.get("id") for b in buildings.values() for z in b.get("zones", [])}
    services = {"board", "town_hall"}
    for m in maps_raw.values():
        services.update((m.get("stalls") or {}).keys())
    item_ids = set(items)

    def text(w, key, need_holes=True):
        check_text(w, key, strings, rep)
        if key in strings:
            for lang in strings[key][:2]:
                for h in re.findall(r"\{([^}]*)\}", lang):
                    if h not in holes:
                        rep.error(w, f"{key}: hueco desconocido {{{h}}} (valen {sorted(holes)})")

    def sym_ok(w, v):
        if isinstance(v, str) and v.startswith("$") and v not in symbols and not v.startswith("$event."):
            rep.error(w, f"símbolo desconocido {v} (valen {sorted(symbols)} o $event.<campo>)")

    def match_ok(w, m):
        if not isinstance(m, dict):
            rep.error(w, "match debe ser un objeto")
            return
        for k, v in m.items():
            if isinstance(v, dict) and not set(v) <= MATCH_OPS:
                rep.error(w, f"match.{k}: operadores válidos {sorted(MATCH_OPS)}")
            sym_ok(w, v)

    def trigger(w, t, only_state=False):
        if not isinstance(t, dict):
            rep.error(w, "un disparador es un objeto {sim|ui|state: …}")
            return
        kinds = [k for k in ("sim", "ui", "state") if k in t]
        if len(kinds) != 1:
            rep.error(w, "un disparador lleva una sola de sim, ui o state")
            return
        k = kinds[0]
        if only_state and k != "state":
            rep.error(w, "aquí solo vale una condición (state)")
        v = t[k]
        if k == "sim" and v not in sim_events:
            rep.error(w, f"evento del sim desconocido {v} (no lo emite sim/)")
        elif k == "ui" and v not in ui_events:
            rep.error(w, f"evento de la UI desconocido {v} (valen {sorted(ui_events)})")
        elif k == "state":
            if v not in conditions:
                rep.error(w, f"condición desconocida {v} (valen {sorted(conditions)})")
            else:
                extra = set(t) - {"state"} - set(conditions[v])
                if extra:
                    rep.error(w, f"condición {v}: argumentos desconocidos {sorted(extra)} (valen {conditions[v]})")
                for a, av in t.items():
                    sym_ok(w, av)
                if v in ("panel_open",) and t.get("is") not in panels:
                    rep.error(w, f"panel_open: {t.get('is')} no está en panels")
                if v == "panel_prop" and t.get("panel") not in panels:
                    rep.error(w, f"panel_prop: {t.get('panel')} no está en panels")
                if v in ("storage_has", "carries") and t.get("item") not in item_ids:
                    rep.error(w, f"{v}: objeto desconocido {t.get('item')}")
        if k in ("sim", "ui"):
            if set(t) - {k, "match", "count", "anyone"}:
                rep.error(w, f"claves desconocidas {sorted(set(t) - {k, 'match', 'count', 'anyone'})}")
            match_ok(w, t.get("match", {}))
            if "count" in t and (not isinstance(t["count"], int) or t["count"] < 1):
                rep.error(w, "count debe ser un entero >= 1")
            if k == "ui" and v in ("panel_opened", "panel_closed") and t.get("match", {}).get("panel") not in panels:
                rep.error(w, f"{v}: match.panel debe ser uno de panels")

    def target(w, t):
        if not isinstance(t, dict):
            rep.error(w, "target debe ser un objeto")
            return
        if "pad" in t and not isinstance(t["pad"], (int, float)):
            rep.error(w, "pad debe ser un número")
        if "opener_text" in t:
            text(w, t["opener_text"])
            if "opener" not in t:
                rep.error(w, "opener_text sin opener")
        kinds = [k for k in ("ui", "zone", "world") if k in t]
        if len(kinds) != 1:
            rep.error(w, "target lleva una sola de ui, zone o world")
            return
        k = kinds[0]
        if k == "ui":
            if not (isinstance(t["ui"], str) and TUTORIAL_UI_NAME.match(t["ui"])):
                rep.error(w, f"ui: nombre de nodo no válido {t['ui']!r}")
            if "in" in t and not (isinstance(t["in"], str) and TUTORIAL_UI_NAME.match(t["in"])):
                rep.error(w, f"in: nombre de nodo no válido {t['in']!r}")
            if set(t) - {"ui", "in", "pad", "opener", "opener_text"}:
                rep.error(w, f"target ui: claves desconocidas {sorted(set(t) - {'ui', 'in', 'pad', 'opener', 'opener_text'})}")
            if "opener" in t:
                target(w + ".opener", t["opener"])
        elif k == "zone":
            if t["zone"] not in zones:
                rep.error(w, f"zona desconocida {t['zone']} (valen {sorted(zones)})")
        else:
            wk = t["world"]
            if wk not in world_kinds:
                rep.error(w, f"world: tipo desconocido {wk} (valen {sorted(world_kinds)})")
                return
            if "opener" in t:
                target(w + ".opener", t["opener"])
            keys = set(t) - {"world", "pad", "opener", "opener_text"}
            if len(keys) != 1 or not keys <= set(world_kinds[wk]):
                rep.error(w, f"world {wk}: lleva una de {world_kinds[wk]}")
                return
            v = t.get(next(iter(keys)))
            sym_ok(w, v)
            if wk == "tile" and not (isinstance(v, list) and len(v) == 2 and all(isinstance(x, int) for x in v)):
                rep.error(w, "tile: at = [col, fila]")
            if "type" in t and t["type"] not in buildings:
                rep.error(w, f"world {wk}: tipo de edificio desconocido {t['type']}")
            if wk == "station" and isinstance(v, str) and not v.startswith("$") and v not in stations:
                rep.error(w, f"station: ningún edificio tiene el puesto {v}")
            if wk == "service" and v not in services:
                rep.error(w, f"service: desconocido {v} (valen {sorted(services)})")

    order = cfg.get("chapters")
    if not (isinstance(order, list) and order and len(set(order)) == len(order)):
        rep.error(w0, "chapters: lista de ids sin repetir")
        order = []
    files = load_kind("tutorial", rep)
    for cid in order:
        if cid not in files:
            rep.error(w0, f"chapters: no existe data/tutorial/{cid}.json")
    for cid in files:
        if cid not in order:
            rep.error(f"tutorial/{cid}", "no está en chapters de data/tutorial.json (no saldría nunca)")
    for name, op in (cfg.get("openers") or {}).items():
        w = f"tutorial.json openers.{name}"
        if not (name in ("@interior", "@town") or TUTORIAL_UI_NAME.match(name)):
            rep.error(w, "la clave es un nombre de nodo, @interior o @town")
        if not isinstance(op, dict):
            rep.error(w, "debe ser {target, text}")
            continue
        target(w, op.get("target"))
        text(w, op.get("text"))
    for k in ("@interior", "@town"):
        if k not in (cfg.get("openers") or {}):
            rep.error(w0, f"openers: falta {k}")
    seen_h = set()
    for h in cfg.get("hints") or []:
        w = f"tutorial.json hints.{h.get('id')}"
        if not ID_RE.match(str(h.get("id", ""))) or h.get("id") in seen_h:
            rep.error(w, "id en snake_case y sin repetir")
        seen_h.add(h.get("id"))
        trigger(w + ".when", h.get("when"))
        if "until" in h:
            trigger(w + ".until", h["until"])
        if "target" in h:
            target(w + ".target", h["target"])
        text(w, h.get("text"))
        if set(h) - {"id", "when", "target", "text", "until"}:
            rep.error(w, f"claves desconocidas {sorted(set(h) - {'id', 'when', 'target', 'text', 'until'})}")
    look = cfg.get("look") or {}
    for k, v in look.items():
        if not (isinstance(v, (int, float)) or (isinstance(v, str) and re.match(r"^#[0-9a-fA-F]{6}$", v))):
            rep.error(w0, f"look.{k}: un número o un color #rrggbb")
    for cid, ch in files.items():
        w = f"tutorial/{cid}"
        text(w, ch.get("name_key"))
        text(w, ch.get("desc_key"))
        if "requires" in ch:
            trigger(w + ".requires", ch["requires"], only_state=True)
        test = ch.get("test") or {}
        if not (("start" in test) ^ ("scenario" in test)):
            rep.error(w, "test: start o scenario (con qué partida lo prueba el smoke de datos)")
        elif "start" in test and test["start"] not in starts:
            rep.error(w, f"test.start: inicio desconocido {test['start']}")
        elif "scenario" in test and test["scenario"] not in scenarios:
            rep.error(w, f"test.scenario: escenario desconocido {test['scenario']}")
        steps = ch.get("steps")
        if not (isinstance(steps, list) and steps):
            rep.error(w, "steps: al menos un paso")
            continue
        ids = set()
        for i, st in enumerate(steps):
            ws = f"{w} paso {i + 1} ({st.get('id')})"
            if not ID_RE.match(str(st.get("id", ""))) or st.get("id") in ids:
                rep.error(ws, "id en snake_case y sin repetir en el capítulo")
            ids.add(st.get("id"))
            text(ws, st.get("text"))
            extra = set(st) - {"id", "text", "target", "when", "done", "advance", "if", "pause"}
            if extra:
                rep.error(ws, f"claves desconocidas {sorted(extra)}")
            if st.get("advance") not in TUTORIAL_ADVANCE:
                rep.error(ws, f"advance debe ser {sorted(TUTORIAL_ADVANCE)}")
            if st.get("advance") == "action" and not st.get("done"):
                rep.error(ws, "advance action necesita done (la acción esperada)")
            if st.get("advance") == "next" and "done" in st:
                rep.error(ws, "advance next solo explica: sin done")
            if "target" in st:
                target(ws, st["target"])
            if "when" in st:
                trigger(ws + ".when", st["when"])
            for d in (st.get("done") if isinstance(st.get("done"), list) else [st["done"]] if "done" in st else []):
                trigger(ws + ".done", d)
            if "if" in st:
                trigger(ws + ".if", st["if"], only_state=True)
            if "pause" in st and not isinstance(st["pause"], bool):
                rep.error(ws, "pause: true o false")


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
            reader = csv.reader(f)
            rows = []
            lines = []  # the physical line where each record ends (a quoted text may span several)
            for r in reader:
                rows.append(r)
                lines.append(reader.line_num)
    except OSError as e:
        rep.error("i18n/strings.csv", str(e))
        return keys
    if not rows or rows[0][:3] != ["keys", "en", "es"]:
        rep.error("i18n/strings.csv", "la cabecera debe ser keys,en,es")
        return keys
    for i, r in enumerate(rows[1:], start=2):
        if not r:
            continue
        # every record keys,en,es: a quote left open or a line split by hand breaks the next records (posada,
        # 2026-11-05: a text joined to the next key showed raw keys in the game)
        if len(r) != 3:
            rep.error("i18n/strings.csv", f"registro {i} (línea {lines[i - 1]}): {len(r)} columnas, deben ser 3 "
                      f"(clave {r[0][:40]!r})")
        if any(c in r[0] for c in "\n\r\"") or r[0] != r[0].strip():
            rep.error("i18n/strings.csv", f"registro {i} (línea {lines[i - 1]}): clave rota {r[0][:60]!r} "
                      "(salto de línea, comilla o espacios)")
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
    UPGRADES.update(load_upgrades(rep))

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

    # plantillas: the town's watch (its name) and the faster routes of the large maps (sim/world/route_atlas.gd)
    mdir = os.path.join(DATA, "maps")
    for f in sorted(os.listdir(mdir)):
        if not f.endswith(".json") or f.startswith("_"):
            continue
        m = load_json(os.path.join(mdir, f), rep) or {}
        wm = f"maps/{f[:-5]}"
        if "watch" in m:
            check_text(wm + " watch", (m.get("watch") or {}).get("name_key"), strings, rep)
        if "routing" in m:
            k = (m.get("routing") or {}).get("landmarks")
            if not isinstance(k, int) or not 1 <= k <= 8:
                rep.error(wm, f"routing.landmarks {k}: un entero de 1 a 8")
            rp = (m.get("routing") or {}).get("replans_per_minute", -1)
            if not isinstance(rp, int) or (rp != -1 and rp < 1):
                rep.error(wm, f"routing.replans_per_minute {rp}: un entero >= 1 (o -1, sin tope)")

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
        if b.get("market_stall") is not None and b["market_stall"] not in STALLS:
            rep.error(w, f"market_stall desconocido {b['market_stall']}")

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
        if r.get("requires_upgrade") and r["requires_upgrade"] not in UPGRADES:
            rep.error(w, f"requires_upgrade {r['requires_upgrade']}: mejora desconocida")

    maps = check_maps(rep)
    check_map_buildings(maps, buildings, rep)
    check_h3(items, recipes, buildings, maps, strings, rep)
    ranks, roles = check_h4(buildings, recipes, maps, strings, rep)
    check_h5(items, recipes, buildings, ranks, strings, rep)
    tones = check_h8(strings, rep)
    check_cast(rep)
    workplaces = check_h7(load_kind("maps", rep), strings, rep)
    titles = check_h9(load_kind("maps", rep), strings, rep)
    offices = check_h10(titles, strings, rep)
    check_h11(strings, rep)
    check_h14(strings, rep)
    check_h13(items, strings, rep)
    check_combat(items, strings, rep)
    check_games(ROOT, strings, rep, check_text)  # juegos (04f §4.26): tools/validate_games.py
    check_h12(items, recipes, buildings, maps, strings, rep)
    check_region(items, strings, rep)
    validate_fiestas.check_festivals(DATA, items, recipes, strings, check_text, load_json, rep)
    sys.path.insert(0, os.path.join(ROOT, "tools", "life"))
    import validate_life  # noqa: E402 vida (04f 4.24): data/life/*.json
    validate_life.check(items, strings, rep, DATA, ROOT, SOCIAL_KINDS, check_text)
    check_tutorial(strings, set(load_kind("starts", rep)),
                   {n[:-5] for n in os.listdir(os.path.join(DATA, "scenarios")) if n.endswith(".json") and not n.startswith("_")},
                   items, buildings, load_kind("maps", rep), rep)

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
        if bot == "goldflow":  # GDD 4.19: {fase: {bot, window_days [a, b], net_per_day [mín, máx], exclude_categories}}
            for phase, g in measures.items():
                if phase.startswith("_"):
                    continue
                w, n = g.get("window_days"), g.get("net_per_day")
                if not (isinstance(w, list) and len(w) == 2 and all(isinstance(x, int) for x in w) and 1 <= w[0] <= w[1]):
                    rep.error("targets.json", f"goldflow.{phase}.window_days debe ser [día_ini, día_fin] (desde 1)")
                if not (isinstance(n, list) and len(n) == 2):
                    rep.error("targets.json", f"goldflow.{phase}.net_per_day debe ser [mín, máx]")
                if not isinstance(g.get("bot"), str) or g.get("bot") not in targets:
                    rep.error("targets.json", f"goldflow.{phase}.bot debe ser un bot con dianas")
                money = open(os.path.join(ROOT, "sim", "econ", "money.gd"), encoding="utf-8").read()
                cats = set(re.findall(r'const [A-Z_]+: String = "([a-z_]+)"', money))
                if not all(c in cats for c in g.get("exclude_categories", [])):
                    rep.error("targets.json", f"goldflow.{phase}.exclude_categories: categoría desconocida")
            continue
        for m, rng in measures.items():
            if m in ("_mean", "_share") and isinstance(rng, dict):
                for mm, r2 in rng.items():
                    if not (isinstance(r2, list) and len(r2) == 2):
                        rep.error("targets.json", f"{bot}.{m}.{mm} debe ser [mín, máx]")
                continue
            if m.startswith("_"):
                continue
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
        if d.get("version", 0) >= 5:
            check_h4_scenario(f"scenarios/{name}", d, buildings, ranks, roles, recipes, rep)
        if d.get("version", 0) >= 6:
            check_h5_scenario(f"scenarios/{name}", d, buildings, rep)
        if d.get("version", 0) >= 7:
            check_h8_scenario(f"scenarios/{name}", d, buildings, tones, rep)
        if d.get("version", 0) >= 8:
            check_h7_scenario(f"scenarios/{name}", d, workplaces, rep)
        if d.get("version", 0) >= 9:
            check_h9_scenario(f"scenarios/{name}", d, titles, rep)
        if d.get("version", 0) >= 10:
            check_h10_scenario(f"scenarios/{name}", d, offices, rep)
        if d.get("version", 0) >= 11:
            check_h11_scenario(f"scenarios/{name}", d, rep)
        if d.get("version", 0) >= 4:
            for fid, fam in (d.get("families") or {}).items():
                if not isinstance(fam.get("gold"), int) or fam["gold"] < 0:
                    rep.error(f"scenarios/{name}", f"{fid}: gold de la familia debe ser un entero >= 0")
                prof = fam.get("ai_profile", "")
                if prof and not os.path.exists(os.path.join(DATA, "ai_profiles", prof + ".json")):
                    rep.error(f"scenarios/{name}", f"{fid}: ai_profile desconocido {prof}")
            for cid, ch in (d.get("characters") or {}).items():
                if "gold" in ch:
                    rep.error(f"scenarios/{name}", f"{cid}: el oro va en la familia desde v4, no en el personaje")
                loc = ch.get("location", "")
                if loc and loc not in (d.get("buildings") or {}):
                    rep.error(f"scenarios/{name}", f"{cid}: location {loc} no es un edificio del escenario")
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
            for pt in (ch.get("path") or []) if map_id else []:  # (not t: t holds the tables, counted below)
                if not (isinstance(pt, list) and len(pt) == 2 and maps[map_id](*pt)):
                    rep.error(f"scenarios/{name}", f"{cid}: la ruta pasa por {pt}, que no es transitable")
                    break

    validate_structure.check(rep)

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
