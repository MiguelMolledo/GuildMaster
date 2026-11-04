"""Content checks of the living town II (docs/gdd/04f_vida_y_fiestas.md §4.24; docs/contratos/vida.md): data/life/*.json.
Called by tools/validate_content.py (check). Activities: spots, kinds, groups, needs, bubbles with a scene; rumours:
sources and texts; incidents: texts, choices and nests; life.json: needs, visitors' kinds and towns, the watch."""
import json
import os

SPOTS = {"work", "stalls", "points", "home", "gate", "relative", "stroll", "spectacle"}
GROUPS = {"child", "adult", "elder"}
SOURCES = {"chronicle", "loans", "city_prices", "visitor_prices", "elections", "events", "board", "visitors", "warning"}
STATS = {"charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution", "rhetoric", "stealth"}
INCIDENT_CHOICES = {"altercation": {"separate", "watch"}, "bandit_raid": {"defend", "alarm", "hide"},
                    "kidnapping": {"pay", "negotiate", "rescue", "nothing"}}


def _load(path, rep):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        rep.error(os.path.relpath(path, os.path.dirname(os.path.dirname(path))), f"no se puede leer: {e}")
        return None


def check(items, strings, rep, data_dir, root, social_kinds, check_text):
    life_dir = os.path.join(data_dir, "life")
    life = _load(os.path.join(life_dir, "life.json"), rep) or {}
    acts = _load(os.path.join(life_dir, "activities.json"), rep) or {}
    rumors = _load(os.path.join(life_dir, "rumors.json"), rep) or {}
    incidents = _load(os.path.join(life_dir, "incidents.json"), rep) or {}
    w = "life/life.json"
    needs = set(life.get("needs", {}).get("ids", []))
    if not {"hunger", "rest", "social", "fun", "faith"} <= needs:
        rep.error(w, "needs.ids: hunger, rest, social, fun y faith (4.24.1)")
    for k in life.get("needs", {}).get("per_hour", {}):
        if k not in needs:
            rep.error(w, f"needs.per_hour.{k}: necesidad desconocida")
    for k in ("enabled", "agenda", "meeting", "population", "visitors", "watch"):
        if k not in life:
            rep.error(w, f"falta {k}")
    for kind in life.get("meeting", {}).get("kinds", {}):
        if kind not in social_kinds:
            rep.error(w, f"meeting.kinds.{kind}: kind de social_points desconocido")
    vis = life.get("visitors", {})
    for k, d in vis.get("kinds", {}).items():
        check_text(w, "visitor." + k, strings, rep)
        if not isinstance(d.get("weight"), (int, float)) or d["weight"] < 0:
            rep.error(w, f"visitors.kinds.{k}.weight >= 0")
        for st in d.get("stats", {}):
            if st not in STATS:
                rep.error(w, f"visitors.kinds.{k}.stats.{st}: stat desconocida")
        for step in d.get("plan", []):
            if not (isinstance(step, list) and len(step) == 2 and isinstance(step[1], int) and step[1] > 0):
                rep.error(w, f"visitors.kinds.{k}.plan: [spot, minutos]")
    for slot, it in life.get("watch", {}).get("equipment", {}).items():
        if it not in items:
            rep.error(w, f"watch.equipment.{slot}: objeto desconocido {it}")
    check_text(w, "family.watch", strings, rep)
    check_text(w, "family.visitors", strings, rep)
    check_text(w, "family.bandits", strings, rep)
    wa = "life/activities.json"
    for aid, d in acts.items():
        if aid.startswith("_"):
            continue
        if d.get("spot") not in SPOTS:
            rep.error(wa, f"{aid}.spot: uno de {sorted(SPOTS)}")
        for k in d.get("kinds", []):
            if k not in social_kinds:
                rep.error(wa, f"{aid}.kinds: kind desconocido {k}")
        if d.get("spot") in ("points", "stroll") and not d.get("kinds"):
            rep.error(wa, f"{aid}: points y stroll necesitan kinds")
        for g in d.get("who", {}):
            if g not in GROUPS:
                rep.error(wa, f"{aid}.who.{g}: child, adult o elder")
        for n in d.get("raises", {}):
            if n not in needs:
                rep.error(wa, f"{aid}.raises.{n}: necesidad desconocida")
        for ph in list(d.get("when", {})) + d.get("holy_phases", []):
            if ph not in ("dawn", "day", "dusk", "night"):
                rep.error(wa, f"{aid}.when: fase desconocida {ph}")
        b = d.get("bubble", "")
        if b and not os.path.exists(os.path.join(root, "game", "visuals", "bubbles", b + ".tscn")):
            rep.error(wa, f"{aid}.bubble: falta game/visuals/bubbles/{b}.tscn")
        check_text(wa, "life.activity." + aid, strings, rep)
    for must in ("work", "sleep", "shopping", "chat", "mass"):
        if must not in acts:
            rep.error(wa, f"falta la actividad {must} (4.24.1)")
    wr = "life/rumors.json"
    for rid, d in rumors.items():
        if rid.startswith("_"):
            continue
        if d.get("source") not in SOURCES:
            rep.error(wr, f"{rid}.source: uno de {sorted(SOURCES)}")
        check_text(wr, d.get("text_key", ""), strings, rep)
    wi = "life/incidents.json"
    for iid, choices in INCIDENT_CHOICES.items():
        d = incidents.get(iid)
        if not isinstance(d, dict):
            rep.error(wi, f"falta {iid} (4.24.5)")
            continue
        check_text(wi, d.get("text_key", ""), strings, rep)
        check_text(wi, d.get("text_key", "") + ".story", strings, rep)
        for c in d.get("choices", []):
            if c not in choices:
                rep.error(wi, f"{iid}.choices: {c} no es de {sorted(choices)}")
            check_text(wi, "incident.choice." + c, strings, rep)
            check_text(wi, f"incident.choice.{c}.tip", strings, rep)
        if d.get("default") not in d.get("choices", []):
            rep.error(wi, f"{iid}.default: una de sus choices")
        check_text(wi, f"notice.life.{iid}", strings, rep)
    if "fire" in incidents:
        rep.error(wi, "fire: el incendio no se construye (O-V6 b)")
    raid = incidents.get("bandit_raid", {})
    if raid.get("max_gold_share", 1) > 0.10 or raid.get("max_items", 99) > 3:
        rep.error(wi, "bandit_raid: nunca más del 10 % del oro ni más de 3 objetos (riesgo justo, 4.24.5)")
    if raid.get("min_day", 0) < 8 or incidents.get("kidnapping", {}).get("min_day", 0) < 8:
        rep.error(wi, "asaltos y secuestros nunca el primer año (min_day >= 8)")
    region = _load(os.path.join(data_dir, "world", "region.json"), rep) or {}
    routes = {r["id"] for r in region.get("routes", [])}
    for r, key in incidents.get("nests", {}).items():
        if r not in routes:
            rep.error(wi, f"nests.{r}: ruta desconocida")
        check_text(wi, key, strings, rep)
