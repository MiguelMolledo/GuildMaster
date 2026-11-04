"""Juegos y competiciones (docs/gdd/04f_vida_y_fiestas.md §4.26; docs/contratos/juegos.md): data/games.json.

Lo llama tools/validate_content.py (check_games). Comprueba: apuestas enteras y crecientes con el tope (O-V8) entre
ellas; la casa con un margen en [0, 1); los temperamentos y las fichas de jugadores (atributos conocidos, temperamento
conocido, texto de su nombre); y, de cada juego que exista, sus cifras: los números de azar del «azar», jugadores y
dados de «a la mayor», el triángulo del pulso (cada acción gana a otra distinta, un ciclo, una acción que no cuesta),
lecturas con 0 <= min <= base <= max <= 1, y los textos de cada acción, pista y fase que enseña la pantalla.
"""
import json
import os

STATS = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution", "rhetoric",
         "stealth"]
TEMPERS = {"prudent", "even", "boastful", "cheat"}
GAMES = ["azar", "mayor", "pulso", "envite", "tourney", "joust", "sortija", "race", "bulls"]


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def _read(w, key, r, rep):
    try:
        if not (0 <= float(r["min"]) <= float(r["base"]) <= float(r["max"]) <= 1 and float(r["step"]) >= 0):
            rep.error(w, f"{key}: 0 <= min <= base <= max <= 1 y step >= 0")
    except (KeyError, TypeError, ValueError):
        rep.error(w, f"{key}: base, step, min y max")


def _triangle(w, key, acts, rep):
    if len(acts) != 3:
        rep.error(w, f"{key}.actions: tres acciones")
        return
    if {a.get("beats") for a in acts.values()} != set(acts) or any(k == a.get("beats") for k, a in acts.items()):
        rep.error(w, f"{key}.actions.beats: cada acción gana a otra distinta y las tres forman un ciclo")
    if any(not isinstance(a.get("cost"), int) for a in acts.values()):
        rep.error(w, f"{key}.actions.cost: enteros (negativo = recupera)")
    elif not any(a["cost"] <= 0 for a in acts.values()):
        rep.error(w, f"{key}.actions: una acción que no cueste (sin fuerza siempre se puede elegir)")


def check_games(root, strings, rep, check_text):
    w = "games.json"
    path = os.path.join(root, "data", "games.json")
    try:
        with open(path, encoding="utf-8") as f:
            g = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        rep.error(w, f"no se puede leer: {e}")
        return
    stakes = g.get("stakes") or []
    cap = g.get("cap")
    if not stakes or any(not isinstance(s, int) or s <= 0 for s in stakes) or stakes != sorted(set(stakes)):
        rep.error(w, "stakes: enteros > 0, crecientes y sin repetir")
    if not isinstance(cap, int) or (stakes and max(stakes) > cap):
        rep.error(w, "cap: entero y ninguna apuesta por encima (O-V8)")
    rake = (g.get("house") or {}).get("rake")
    if not _num(rake) or not 0 <= rake < 1:
        rep.error(w, "house.rake en [0, 1)")
    if not isinstance(g.get("warn_loss"), int) or g["warn_loss"] <= 0:
        rep.error(w, "warn_loss: entero > 0")
    crit = g.get("critical") or {}
    if not (isinstance(crit.get("success"), int) and isinstance(crit.get("fail"), int) and crit["success"] < crit["fail"]):
        rep.error(w, "critical: success < fail (enteros)")
    tempers = g.get("tempers") or {}
    if set(tempers) != TEMPERS:
        rep.error(w, f"tempers: {sorted(TEMPERS)}")
    for k, t in tempers.items():
        for x, v in t.items():
            if x == "stay_always":
                if not isinstance(v, bool):
                    rep.error(w, f"tempers.{k}.stay_always: true o false")
            elif not _num(v) or not -1 <= v <= 1:
                rep.error(w, f"tempers.{k}.{x}: número en [-1, 1]")
        check_text(w, f"games.temper.{k}", strings, rep)
    for k, p in (g.get("presets") or {}).items():
        if p.get("temper") not in TEMPERS:
            rep.error(w, f"presets.{k}.temper: temperamento desconocido")
        for s, v in (p.get("stats") or {}).items():
            if s not in STATS or not isinstance(v, int) or not 0 <= v <= 10:
                rep.error(w, f"presets.{k}.stats.{s}: atributo conocido, entero 0-10")
        check_text(w, p.get("name_key", ""), strings, rep)
    for k in GAMES:
        if k not in g:
            rep.error(w, f"falta el juego {k}")
            continue
        check_text(w, f"games.{k}.name", strings, rep)
        check_text(w, f"games.{k}.rules", strings, rep)
    a = g.get("azar") or {}
    nums = a.get("azar") or []
    if a.get("dice") != 3 or not nums or any(not isinstance(x, int) or not 3 <= x <= 18 for x in nums):
        rep.error(w, "azar: tres dados y números de azar entre 3 y 18")
    if not isinstance(a.get("max_throws"), int) or a["max_throws"] < 10:
        rep.error(w, "azar.max_throws: entero >= 10")
    ld = a.get("loaded") or {}
    if not isinstance(ld.get("below"), int) or not 1 <= ld["below"] <= 6 or not _num(ld.get("again")) \
            or not 0 <= ld["again"] <= 1:
        rep.error(w, "azar.loaded: below entero 1-6, again en [0, 1]")
    for x in ("double", "pass", "accept", "refuse"):
        check_text(w, f"games.azar.action.{x}", strings, rep)
    for x in ("offer", "answer"):
        check_text(w, f"games.azar.prompt.{x}", strings, rep)
    for x in ("azar", "reazar", "chance", "refused", "stuck"):
        check_text(w, f"games.azar.how.{x}", strings, rep)
    m = g.get("mayor") or {}
    pl = m.get("players") or []
    if len(pl) != 2 or not 2 <= pl[0] <= pl[1] <= 4:
        rep.error(w, "mayor.players: [mín, máx] entre 2 y 4")
    if m.get("dice") != 3 or not isinstance(m.get("hidden"), int) or not 0 < m["hidden"] < 3:
        rep.error(w, "mayor: tres dados y 1-2 bajo el cubilete")
    if not _num(m.get("retire_keep")) or not 0 <= m["retire_keep"] <= 1:
        rep.error(w, "mayor.retire_keep en [0, 1]")
    for x in ("stay", "retire"):
        check_text(w, f"games.mayor.action.{x}", strings, rep)
    check_text(w, "games.mayor.prompt", strings, rep)
    for x in ("alone", "tie", "highest", "all_retired"):
        check_text(w, f"games.mayor.how.{x}", strings, rep)
    p = g.get("pulso") or {}
    acts = p.get("actions") or {}
    _triangle(w, "pulso", acts, rep)
    for x in acts:
        check_text(w, f"games.pulso.action.{x}", strings, rep)
        check_text(w, f"games.pulso.action.{x}.hint", strings, rep)
        check_text(w, f"games.pulso.cue.{x}", strings, rep)
    for x in ("blind", "lead", "read"):
        check_text(w, f"games.pulso.prompt.{x}", strings, rep)
    _read(w, "pulso.read", p.get("read") or {}, rep)
    for k in ("win", "tie"):
        t = p.get(k) or {}
        if any(not isinstance(t.get(x), int) for x in ("base", "step")):
            rep.error(w, f"pulso.{k}: base y step enteros")
    if not isinstance((p.get("win") or {}).get("advantage"), int):
        rep.error(w, "pulso.win.advantage entero")
    if not (isinstance(p.get("pushes"), int) and isinstance(p.get("to_win"), int) and 0 < p["to_win"] <= p["pushes"]):
        rep.error(w, "pulso: 0 < to_win <= pushes")
    if not isinstance(p.get("blind"), int) or p["blind"] < 0:
        rep.error(w, "pulso.blind entero >= 0")
    ai = p.get("ai") or {}
    if not _num(ai.get("habit")) or not 0 <= ai["habit"] <= 1 or not isinstance(ai.get("min_history"), int):
        rep.error(w, "pulso.ai: habit en [0, 1] y min_history entero")
    e = g.get("envite") or {}
    order = e.get("order") or []
    ranks = {"1", "2", "3", "4", "5", "6", "7", "10", "11", "12"}
    suits = {"oros", "copas", "espadas", "bastos"}
    named = set()
    for c in order:
        s_, _, r_ = str(c).partition("_")
        if r_ not in ranks or (s_ != "*" and s_ not in suits):
            rep.error(w, f"envite.order: carta desconocida {c}")
        named.add(c)
    if not ranks <= {str(c).partition("_")[2] for c in order if str(c).startswith("*_")}:
        rep.error(w, "envite.order: cada número tiene su «*_n» (las cartas no nombradas)")
    _read(w, "envite.read", e.get("read") or {}, rep)
    eai = e.get("ai") or {}
    for x in ("raise_at", "reraise_at", "bluff_below"):
        if not _num(eai.get(x)) or not 0 <= eai[x] <= 1:
            rep.error(w, f"envite.ai.{x} en [0, 1]")
    for x in ("raise", "pass", "want", "reraise", "fold"):
        check_text(w, f"games.envite.action.{x}", strings, rep)
        check_text(w, f"games.envite.action.{x}.hint", strings, rep)
        check_text(w, f"games.envite.say.{x}", strings, rep)
    for x in ("bet", "bet2", "answer", "answer2"):
        check_text(w, f"games.envite.prompt.{x}", strings, rep)
    for x in ("pleased", "uneasy"):
        check_text(w, f"games.envite.cue.{x}", strings, rep)
    for x in suits:
        check_text(w, f"games.envite.suit.{x}", strings, rep)
    for x in ranks:
        check_text(w, f"games.envite.rank.{x}", strings, rep)
    presets = g.get("presets") or {}
    t = g.get("tourney") or {}
    for o in t.get("outsiders") or []:
        if o not in presets:
            rep.error(w, f"tourney.outsiders: ficha desconocida {o}")
    if not isinstance(t.get("size"), int) or t.get("size") not in (4, 8, 16):
        rep.error(w, "tourney.size: 4, 8 o 16")
    try:
        combat = json.load(open(os.path.join(root, "data", "combat.json"), encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        combat = {}
    if t.get("weapon") not in (combat.get("weapons") or {}):
        rep.error(w, "tourney.weapon: un arma de data/combat.json")
    for k in ("tourney", "tourney_sudden"):
        if k not in (combat.get("kinds") or {}):
            rep.error(w, f"data/combat.json kinds.{k}: el combate del torneo")
    for x in ("points", "sudden", "judges", "final"):
        check_text(w, f"games.tourney.how.{x}", strings, rep)
    j = g.get("joust") or {}
    st = j.get("stances") or {}
    aims = j.get("aims") or {}
    if set(st) != set(aims) or any(v.get("aim") not in aims or v.get("covers") not in aims for v in st.values()):
        rep.error(w, "joust.stances: cada postura apunta y cubre un blanco de aims")
    else:
        beats = {a: [b for b in st if st[b]["covers"] != st[a]["aim"] and st[a]["covers"] == st[b]["aim"]] for a in st}
        if any(len(v) != 1 for v in beats.values()):
            rep.error(w, "joust.stances: cada postura gana exactamente a otra (un triángulo)")
    for k, a in aims.items():
        if not isinstance(a.get("mod"), int) or not _num(a.get("points")) or not _num(a.get("safe")) \
                or not isinstance(a.get("unhorses"), bool):
            rep.error(w, f"joust.aims.{k}: mod entero, points y safe números, unhorses true/false")
    _read(w, "joust.read", j.get("read") or {}, rep)
    for x in st:
        check_text(w, f"games.joust.action.{x}", strings, rep)
        check_text(w, f"games.joust.action.{x}.hint", strings, rep)
        check_text(w, f"games.joust.cue.{x}", strings, rep)
    for x in ("blind", "lead", "read"):
        check_text(w, f"games.joust.prompt.{x}", strings, rep)
    for x in ("unhorsed", "points", "draw"):
        check_text(w, f"games.joust.how.{x}", strings, rep)
    if (j.get("requires") or {}).get("title") not in (None, "", "common", "citizen", "patrician", "baron", "noble"):
        rep.error(w, "joust.requires.title: un título")
    so = g.get("sortija") or {}
    for k, pc in (so.get("paces") or {}).items():
        if not isinstance(pc.get("points"), int) or not isinstance(pc.get("window"), int) or not _num(pc.get("read")) \
                or not 0 <= pc["read"] <= 1:
            rep.error(w, f"sortija.paces.{k}: points y window enteros, read en [0, 1]")
        check_text(w, f"games.sortija.action.{k}", strings, rep)
        check_text(w, f"games.sortija.action.{k}.hint", strings, rep)
    if set(so.get("paces") or {}) != {"prudent", "firm", "gallop"}:
        rep.error(w, "sortija.paces: prudent, firm y gallop")
    for k, v in (so.get("rings") or {}).items():
        if not isinstance(v, int):
            rep.error(w, f"sortija.rings.{k}: entero")
        check_text(w, f"games.sortija.ring.{k}", strings, rep)
    for x in ("first", "second", "third"):
        check_text(w, f"games.sortija.cue.{x}", strings, rep)
        check_text(w, f"games.sortija.action.{x}", strings, rep)
    for r_ in so.get("riders") or []:
        if r_ not in presets:
            rep.error(w, f"sortija.riders: ficha desconocida {r_}")
    ra = g.get("race") or {}
    if set(ra.get("paces") or {}) != {"reserve", "keep", "press"}:
        rep.error(w, "race.paces: reserve, keep y press")
    for k, pc in (ra.get("paces") or {}).items():
        if not isinstance(pc.get("wind"), int) or not _num(pc.get("factor")) or not isinstance(pc.get("risky"), bool):
            rep.error(w, f"race.paces.{k}: wind entero, factor número, risky true/false")
        check_text(w, f"games.race.action.{k}", strings, rep)
        check_text(w, f"games.race.action.{k}.hint", strings, rep)
    if not any((pc.get("wind") or 0) <= 0 for pc in (ra.get("paces") or {}).values()):
        rep.error(w, "race.paces: un ritmo que no gaste fuelle")
    for x in ra.get("stretches") or []:
        check_text(w, f"games.race.stretch.{x}", strings, rep)
    if ra.get("risky") not in (ra.get("stretches") or []):
        rep.error(w, "race.risky: uno de los tramos")
    horses = ra.get("horses") or {}
    if ra.get("rented") not in horses:
        rep.error(w, "race.rented: un caballo de horses")
    for k, h in horses.items():
        if not _num(h.get("speed")) or h["speed"] <= 0 or not isinstance(h.get("wind"), int) or h["wind"] < 3:
            rep.error(w, f"race.horses.{k}: speed > 0 y wind entero >= 3")
    for r_ in ra.get("riders") or []:
        if r_ not in presets:
            rep.error(w, f"race.riders: ficha desconocida {r_}")
        elif (presets[r_].get("horse") or "") not in ("", *horses):
            rep.error(w, f"presets.{r_}.horse: un caballo de race.horses")
    bu = g.get("bulls") or {}
    acts_b = {"cite", "break", "safe"}
    bull_acts = {"charge", "feint", "hook"}
    if set(bu.get("payoff") or {}) != acts_b or any(set(v) != bull_acts for v in (bu.get("payoff") or {}).values()):
        rep.error(w, "bulls.payoff: cite, break y safe contra charge, feint y hook")
    for k, b in (bu.get("bulls") or {}).items():
        if set(b.get("weights") or {}) != bull_acts or not isinstance(b.get("bravery"), int):
            rep.error(w, f"bulls.bulls.{k}: weights de charge, feint y hook y bravery entero")
        check_text(w, f"games.bulls.bull.{k}", strings, rep)
    if bu.get("bull") not in (bu.get("bulls") or {}):
        rep.error(w, "bulls.bull: un toro de bulls")
    for x in acts_b:
        check_text(w, f"games.bulls.action.{x}", strings, rep)
        check_text(w, f"games.bulls.action.{x}.hint", strings, rep)
    for x in bull_acts:
        check_text(w, f"games.bulls.cue.{x}", strings, rep)
        check_text(w, f"games.bulls.what.{x}", strings, rep)
    _read(w, "bulls.read", bu.get("read") or {}, rep)
    for r_ in bu.get("mozos") or []:
        if r_ not in presets:
            rep.error(w, f"bulls.mozos: ficha desconocida {r_}")
    for x in ("unknown_game", "bad_players", "bad_stake", "over_cap", "bad_move", "unfinished", "unknown_house", "bad_bet", "bad_option", "no_loaded_dice", "no_title"):
        check_text(w, f"reason.{x}", strings, rep)
    check_text(w, "notice.games_losses", strings, rep)
