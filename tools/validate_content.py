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
DIFFICULTIES = ["easy", "normal", "hard"]
DIFF_LEVERS = {"start_debt": int, "rival_craft": int, "rival_sell_min_demand": (int, float), "buy_price_mult": (int, float)}
STATS = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution", "rhetoric", "stealth"]
MATCH_OPS = {"gte", "lte", "ne"}
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

    contract_tables = load_kind("contracts", rep)
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
            if not (isinstance(hh.get("family_name"), str) and hh["family_name"].strip()):
                rep.error(wh, "family_name: texto")
            if not isinstance(hh.get("gold"), int) or hh["gold"] < 0:
                rep.error(wh, "gold: entero >= 0")
            if not all(re.fullmatch(r"#[0-9a-fA-F]{6}", str((hh.get("colors") or {}).get(k, ""))) for k in ("primary", "secondary")):
                rep.error(wh, "colors: primary y secondary en #rrggbb")
            if not hh.get("members"):
                rep.error(wh, "una casa sin vecinos")
            for p in hh.get("members") or []:
                wp_ = f"{wh} {p.get('name')}"
                if not (isinstance(p.get("name"), str) and p["name"].strip() and isinstance(p.get("female"), bool)):
                    rep.error(wp_, "name (texto) y female (bool)")
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
        if b.get("market_stall") is not None and b["market_stall"] not in STALLS:
            rep.error(w, f"market_stall desconocido {b['market_stall']}")
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
    check_map_buildings(maps, buildings, rep)
    check_h3(items, recipes, buildings, maps, strings, rep)
    ranks, roles = check_h4(buildings, recipes, maps, strings, rep)

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
