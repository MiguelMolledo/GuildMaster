"""Fiestas (docs/gdd/04f_vida_y_fiestas.md 4.25, 4.28.1): data/festivals.json, data/contracts/festivals.json y las
patronales y ferias de data/world/region.json. Lo llama tools/validate_content.py (check_festivals).

Comprueba: cada fiesta con kind (fixed | variable) y size (big | small) conocidos; las fijas, una por día del año
(0..días-1, sin repetir); las variables con trigger (chance 0-1 o un on conocido); start_hour y hours enteros; cada
efecto de un tipo conocido con lo que necesita (grupo de data/seasons.json goods, mult > 0, ventana from_hour <
to_hour, la emoción de data/town.json, los needs que existen); la tabla de encargos que nombran; los props de la vista
(ids en snake_case, un sitio conocido) y su música en data/audio.json (o el hueco); las tablas de encargos (oficio
conocido o any, objeto que existe y alguna receta que lo fabrique en el taller de ese oficio, calidad 0-2, cliente con
texto); los textos de cada fiesta, de lo que se hace a cada hora y de cada encargo; y en la región, patron_feast y fair
de cada ciudad con su día del año, la demanda sobre objetos o grupos que existen y su texto.
"""
import json
import os
import re

ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
SIM_EFFECTS = {"demand", "price", "customers", "production", "holy_day", "tariff", "route_bonus", "stalls", "emotion",
               "reputation", "aguinaldo", "town_gift", "audience", "contest", "cattle", "gifts"}
HOOK_EFFECTS = {"service", "visitors", "routine", "need", "spectacle", "incident"}
GROUP_EFFECTS = {"demand", "price", "production"}
MULT_EFFECTS = {"demand", "price", "customers", "production", "tariff", "service", "visitors", "routine", "incident"}
TRIGGERS = {"rich_wedding", "townsfolk_wedding", "organized", "city_feast"}
WHERES = {"plaza_center", "plaza_center_side", "plaza_ring", "plaza_edge", "main_street", "town_hall", "gates", "outskirts"}
WHO = {"mayor", "sponsors", "hosts"}


def check_festivals(data_dir, items, recipes, strings, check_text, load_json, rep):
    fest = load_json(os.path.join(data_dir, "festivals.json"), rep) or {}
    w0 = "festivals.json"
    if not fest:
        rep.error(w0, "falta o está vacío")
        return
    time = load_json(os.path.join(data_dir, "time.json"), rep) or {}
    days = len(time.get("seasons", [])) * int(time.get("days_per_season", 2))
    goods = (load_json(os.path.join(data_dir, "seasons.json"), rep) or {}).get("goods", {})
    emotions = (load_json(os.path.join(data_dir, "town.json"), rep) or {}).get("emotions", {})
    audio = load_json(os.path.join(data_dir, "audio.json"), rep) or {}
    music = dict(audio.get("music") or {}, **(audio.get("pending_music") or {}))
    ctr = load_json(os.path.join(data_dir, "contracts", "festivals.json"), rep) or {}
    life_dir = os.path.join(data_dir, "life")  # vida (04f 4.24): the ids of its agenda and its incidents
    acts = {k for k in (load_json(os.path.join(life_dir, "activities.json"), rep) or {}) if not k.startswith("_")} \
        if os.path.exists(os.path.join(life_dir, "activities.json")) else None
    _inc = load_json(os.path.join(life_dir, "incidents.json"), rep) or {}
    incs = {k for k in (_inc.get("incidents") or _inc) if not k.startswith("_")} \
        if os.path.exists(os.path.join(life_dir, "incidents.json")) else None
    tables = ctr.get("tables") or {}
    rules = fest.get("rules") or {}
    parts = set((rules.get("sponsor") or {}).get("parts", {})) | set((rules.get("organize") or {}).get("parts", []))
    looks = set(rules.get("view_looks") or {})
    for k in ("first_day", "eve_hour", "history_size"):
        if not isinstance(rules.get(k), int):
            rep.error(w0, f"rules.{k} debe ser un entero")
    by_day = {}
    defs = fest.get("festivals") or {}
    for fid, d in sorted(defs.items()):
        w = f"festivals.json {fid}"
        if not ID_RE.match(fid):
            rep.error(w, "id no es inglés en snake_case")
        check_text(w, "festival." + fid, strings, rep)
        check_text(w, f"festival.{fid}.story", strings, rep)
        kind = d.get("kind")
        if kind not in ("fixed", "variable"):
            rep.error(w, f"kind desconocido {kind}")
        if d.get("size") not in ("big", "small"):
            rep.error(w, f"size desconocido {d.get('size')}")
        if kind == "fixed":
            doy = d.get("day_of_year")
            if not isinstance(doy, int) or not 0 <= doy < max(1, days):
                rep.error(w, f"day_of_year debe estar entre 0 y {days - 1}")
            elif doy in by_day:
                rep.error(w, f"day_of_year {doy} repetido (también {by_day[doy]})")
            else:
                by_day[doy] = fid
        else:
            t = d.get("trigger") or {}
            on = t.get("on")
            if on is not None and on not in TRIGGERS:
                rep.error(w, f"trigger.on desconocido {on}")
            if on is None and not (isinstance(t.get("chance"), (int, float)) and 0 < t["chance"] <= 1):
                rep.error(w, "trigger.chance debe estar en (0, 1] (o un trigger.on)")
            for a in t.get("avoid", []):
                if a not in ("big", "small", "fair"):
                    rep.error(w, f"trigger.avoid desconocido {a}")
            if not isinstance(d.get("notice_days", 1), int) or d.get("notice_days", 1) < 1:
                rep.error(w, "notice_days debe ser un entero >= 1")
        for k in ("start_hour", "hours"):
            if not isinstance(d.get(k), int) or d[k] < (1 if k == "hours" else 0):
                rep.error(w, f"{k} debe ser un entero (horas)")
        for s in d.get("schedule", []):
            check_text(w, "festival.what." + str(s.get("what")), strings, rep)
            if s.get("needs") and s["needs"] not in parts:
                rep.error(w, f"schedule {s.get('what')}: needs desconocido {s['needs']}")
        for e in d.get("effects", []):
            k = e.get("kind")
            we = f"{w} efecto {k}"
            if k not in SIM_EFFECTS | HOOK_EFFECTS:
                rep.error(we, "tipo de efecto desconocido")
                continue
            if k in GROUP_EFFECTS and e.get("group") not in goods:
                rep.error(we, f"grupo desconocido {e.get('group')} (data/seasons.json goods)")
            if k in MULT_EFFECTS and not (isinstance(e.get("mult"), (int, float)) and e["mult"] >= 0):
                rep.error(we, "mult debe ser un número >= 0")
            if k == "holy_day" and not (isinstance(e.get("work_mult"), (int, float)) and 0 <= e["work_mult"] <= 1):
                rep.error(we, "work_mult entre 0 y 1")
            if k == "emotion" and e.get("id") not in emotions:
                rep.error(we, f"emoción desconocida {e.get('id')} (data/town.json emotions)")
            if k in ("reputation",) and e.get("who") not in WHO:
                rep.error(we, f"who desconocido {e.get('who')}")
            if k == "emotion" and e.get("toward", "sponsors") not in WHO:
                rep.error(we, f"toward desconocido {e.get('toward')}")
            if k == "stalls" and not (isinstance(e.get("count"), int) and e["count"] >= 1):
                rep.error(we, "count debe ser un entero >= 1")
            if k == "stalls" and any(g not in goods for g in e.get("groups", [])):
                rep.error(we, "groups: grupo desconocido")
            if k == "spectacle" and not isinstance(e.get("hour"), int):
                rep.error(we, "hour debe ser un entero")
            if "from_hour" in e and "to_hour" in e and not e["from_hour"] < e["to_hour"]:
                rep.error(we, "from_hour debe ser menor que to_hour")
            if e.get("needs") and e["needs"] not in parts:
                rep.error(we, f"needs desconocido {e['needs']}")
            if k == "routine" and acts is not None and e.get("activity") not in acts:
                rep.error(we, f"actividad desconocida {e.get('activity')} (data/life/activities.json)")
            if k == "incident" and incs is not None and e.get("id") not in incs and e.get("id") != "fire":
                rep.error(we, f"suceso desconocido {e.get('id')} (data/life/incidents.json; fire espera a O-V6)")
        tab = d.get("contracts", "")
        if tab and tab not in tables:
            rep.error(w, f"tabla de encargos desconocida {tab} (data/contracts/festivals.json)")
        for p in d.get("organizable", []):
            if p not in parts:
                rep.error(w, f"organizable: parte desconocida {p}")
        v = d.get("view") or {}
        for dd in v.get("decor", []):
            if not ID_RE.match(str(dd.get("prop", ""))):
                rep.error(w, f"decor: prop {dd.get('prop')} no es un id")
            if dd.get("where") not in WHERES:
                rep.error(w, f"decor {dd.get('prop')}: sitio desconocido {dd.get('where')}")
            if dd.get("needs") and dd["needs"] not in parts:
                rep.error(w, f"decor {dd.get('prop')}: needs desconocido {dd['needs']}")
            if dd.get("needs_contract") and dd["needs_contract"] not in items:
                rep.error(w, f"decor {dd.get('prop')}: needs_contract no es un objeto")
        if v.get("clothes") and v["clothes"] not in looks:
            rep.error(w, f"clothes desconocido {v['clothes']} (rules.view_looks)")
        if v.get("music") and v["music"] not in music:
            rep.error(w, f"música {v['music']} sin entrada en data/audio.json music ni pending_music")
    if days and len(by_day) and sorted(by_day) != list(range(days)):
        rep.warn(w0, f"las fijas no cubren todos los días del año ({sorted(by_day)})")
    rep.notes.append(f"fiestas: {len(defs)} ({len(by_day)} fijas), {len(tables)} tablas de encargos")

    # data/contracts/festivals.json
    wc = "contracts/festivals.json"
    profs = {}
    pdir = os.path.join(data_dir, "professions")
    for n in sorted(os.listdir(pdir)) if os.path.isdir(pdir) else []:
        if n.endswith(".json") and not n.startswith("_"):
            pf = load_json(os.path.join(pdir, n), rep) or {}
            profs[pf.get("id")] = pf.get("building")
    if ctr.get("kind") != "festival":
        rep.error(wc, "kind debe ser festival (no es una tabla del tablón de cada día)")
    for cl in ctr.get("clients", []):
        check_text(f"{wc} client {cl.get('id')}", cl.get("name_key"), strings, rep)
    for tid, rows in sorted(tables.items()):
        for i, r in enumerate(rows):
            wr = f"{wc} {tid}[{i}]"
            prof = r.get("profession")
            item = r.get("item")
            if prof != "any" and prof not in profs:
                rep.error(wr, f"oficio desconocido {prof}")
            if item not in items:
                rep.error(wr, f"objeto desconocido {item}")
            elif prof in profs and not any(rc.get("output", {}).get("item") == item and rc.get("building") == profs[prof]
                                           for rc in recipes.values()):
                rep.error(wr, f"el {profs[prof]} no fabrica {item}")
            if not (isinstance(r.get("qty"), int) and r["qty"] >= 1):
                rep.error(wr, "qty debe ser un entero >= 1")
            if r.get("min_quality", 0) not in (0, 1, 2):
                rep.error(wr, "min_quality 0, 1 o 2")
            check_text(wr, "client." + str(r.get("client", "")), strings, rep)
            if r.get("what"):
                check_text(wr, "festival_contract." + r["what"], strings, rep)
            if r.get("needs") and r["needs"] not in parts:
                rep.error(wr, f"needs desconocido {r['needs']}")

    # data/world/region.json: patron_feast y fair
    region = load_json(os.path.join(data_dir, "world", "region.json"), rep) or {}
    for s in region.get("settlements", []):
        ws = f"world/region.json {s.get('id')}"
        pf = s.get("patron_feast")
        if pf is None:
            rep.warn(ws, "sin patron_feast (4.25.6)")
        else:
            check_text(ws, "region.feast." + str(pf.get("id")), strings, rep)
            if not (isinstance(pf.get("day_of_year"), int) and 0 <= pf["day_of_year"] < max(1, days)):
                rep.error(ws, "patron_feast.day_of_year fuera del año")
            for g in pf.get("games", []):
                check_text(ws, "region.game." + g, strings, rep)
        for what, blk in (("patron_feast", pf or {}), ("fair", s.get("fair") or {})):
            for k in (blk.get("demand") or {}):
                if k not in items and k not in goods:
                    rep.error(ws, f"{what}.demand: {k} no es un objeto ni un grupo")
        fair = s.get("fair")
        if fair is not None:
            if not (isinstance(fair.get("day_of_year"), int) and 0 <= fair["day_of_year"] < max(1, days)):
                rep.error(ws, "fair.day_of_year fuera del año")
            if fair.get("festival") and fair["festival"] not in defs:
                rep.error(ws, f"fair.festival desconocida {fair['festival']}")
