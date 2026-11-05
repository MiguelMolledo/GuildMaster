#!/usr/bin/env python3
"""Resumen HTML del jugador completo y del caótico (docs/gdd/07_testing.md §7.4).

  python3 tools/full_report.py [reports/full_player ...]   (por defecto reports/full_player y reports/chaos_player)

Lee los <semilla>.json y summary.json que escribe tools/full_player.gd y deja index.html en la misma carpeta:
curvas de oro, deuda, reputación y título por semilla; la familia; los desbloqueos frente a su ventana de 03b;
las mecánicas usadas y las que nunca tocó con el motivo; el ritmo; las órdenes rechazadas; los atascos; los
errores del motor; el bench; el guardado del caótico; y dónde están las partidas guardadas.
"""
import html
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERIES = ["--series-1", "--series-2", "--series-3"]  # tres semillas: los tres primeros huecos valen en todos los pares

WHY = {
    "not_in_game": "aún no está en el juego", "no_occasion": "no se dio la ocasión", "title_needed": "falta el título",
    "founder_alive": "el fundador sigue vivo", "no_fact": "ningún hecho público contra otra familia",
    "market_takes_them": "el mercado del pueblo se lleva las espadas", "cart_too_dear": "el carro no compensa aún",
    "no_spare_carter": "no hay empleado libre para carretero", "debt_first": "primero la deuda",
    "gold_short": "falta oro", "forge_needs_the_head": "la forja sin empleados necesita al cabeza",
    "talked_today": "ya habló hoy", "married": "ya casado", "no_suitor": "nadie que cortejar",
    "no_candidate": "ninguna candidata", "gave_up_walking": "no llegó a tiempo", "this_season": "ya retó esta estación",
    "no_cause": "sin motivo contra nadie", "went_this_year": "ya viajó este año",
    "nothing_to_do_there": "nada que hacer en la capital", "no_swords_to_carry": "sin espadas que llevar",
    "gold_for_the_road": "falta oro para el camino", "contract_due": "un encargo vence pronto",
    "could_not_leave": "no pudo salir", "heir_courts": "corteja el heredero",
    "one_employee": "con un solo empleado no compensa", "no_time": "no llega a tiempo",
    "no_open_route": "camino cerrado", "already_there": "ya está allí", "not_enough_gold": "falta oro",
}
CAUSE = {"under_works": "obras de mejora", "empty_queue": "la cola de los empleados vacía", "no_gold": "sin oro ni materia prima", "no_materials": "sin materia prima"}
VERDICT = {"on_time": "a tiempo", "early": "pronto", "late": "tarde", "never": "nunca", "not_judged": "sin juzgar",
           "hook_missing": "falta el sistema"}


def why(r):
    if r.startswith("low_chance_"):
        return "pocas opciones (%s)" % r[11:]
    return WHY.get(r, r)


def esc(x):
    return html.escape(str(x))


def line_chart(title, runs, key, step=False, fmt="{:.0f}"):
    """Una línea por semilla, un solo eje. Pasar el ratón muestra el valor del día."""
    pts = [[(c["day"], float(c.get(key, 0))) for c in r["curve"]] for r in runs]
    xs = [x for p in pts for x, _ in p] or [0, 1]
    ys = [y for p in pts for _, y in p] or [0, 1]
    x0, x1 = min(xs), max(max(xs), min(xs) + 1)
    y0, y1 = min(0.0, min(ys)), max(max(ys), 1.0)
    w, h, l, b, t = 520, 180, 44, 22, 10
    sx = lambda x: l + (x - x0) / (x1 - x0) * (w - l - 8)
    sy = lambda y: t + (1 - (y - y0) / (y1 - y0)) * (h - t - b)
    out = [f'<figure class="chart"><figcaption>{esc(title)}</figcaption>',
           f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">']
    for frac in (0, 0.5, 1):
        yv = y0 + frac * (y1 - y0)
        out.append(f'<line class="grid" x1="{l}" x2="{w - 8}" y1="{sy(yv):.1f}" y2="{sy(yv):.1f}"/>'
                   f'<text class="tick" x="{l - 6}" y="{sy(yv) + 4:.1f}" text-anchor="end">{yv:.4g}</text>')
    out.append(f'<text class="tick" x="{l}" y="{h - 4}">día {x0}</text>'
               f'<text class="tick" x="{w - 8}" y="{h - 4}" text-anchor="end">día {x1}</text>')
    for i, p in enumerate(pts):
        if not p:
            continue
        d = []
        for j, (x, y) in enumerate(p):
            if step and j:
                d.append(f"L{sx(x):.1f},{sy(p[j - 1][1]):.1f}")
            d.append(("M" if j == 0 else "L") + f"{sx(x):.1f},{sy(y):.1f}")
        col = SERIES[i % 3]
        out.append(f'<path d="{" ".join(d)}" fill="none" stroke="var({col})" stroke-width="2" '
                   f'stroke-linejoin="round" stroke-linecap="round"/>')
        for x, y in p:
            out.append(f'<circle class="hit" cx="{sx(x):.1f}" cy="{sy(y):.1f}" r="7" '
                       f'data-tip="semilla {runs[i]["seed"]} · día {x}: {fmt.format(y)}"/>')
    out.append("</svg></figure>")
    return "".join(out)


def table(head, rows, cls=""):
    h = "".join(f"<th>{esc(x)}</th>" for x in head)
    b = "".join("<tr>" + "".join(f"<td>{x}</td>" for x in r) + "</tr>" for r in rows)
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>'


def section(title, body):
    return f"<section><h2>{esc(title)}</h2>{body}</section>"


def render(d):
    runs = []
    for f in sorted(os.listdir(d)):
        if f.endswith(".json") and f[:-5].isdigit():
            runs.append(json.load(open(os.path.join(d, f), encoding="utf-8")))
    if not runs:
        return None
    runs.sort(key=lambda r: r["seed"])
    summ = json.load(open(os.path.join(d, "summary.json"), encoding="utf-8")) if os.path.exists(
        os.path.join(d, "summary.json")) else {}
    bot = runs[0]["bot"] if isinstance(runs[0]["bot"], str) else runs[0]["measures"].get("bot", "full_player")
    legend = "".join(f'<span class="key"><i style="background:var({SERIES[i % 3]})"></i>semilla {r["seed"]}</span>'
                     for i, r in enumerate(runs))
    parts = []
    misses = summ.get("misses", [])
    parts.append(f'<p class="lead">{esc(bot)} · {esc(runs[0].get("horizon", ""))} · {esc(runs[0].get("difficulty", ""))}'
                 f' · {len(runs)} semillas · {len(misses)} dianas fallidas</p>')
    if misses:
        parts.append('<ul class="miss">' + "".join(f"<li>{esc(m)}</li>" for m in misses) + "</ul>")
    keys = ["days", "gold_end", "gold_min", "net_year_1", "net_year_2", "net_year_3", "debt_paid_day",
            "title_citizen_day", "title_patrician_day", "office_won_day", "wedding_day", "first_child_day", "children",
            "inherit_day", "founder_death_day", "hired", "upgrades_done", "contracts_done", "contracts_failed",
            "festival_contracts", "counter_sold", "trips", "caravans", "treaties", "duels_fought", "duels_won",
            "trials_as_accuser", "trials_against", "incidents", "mechanics_used", "mechanics_in_game", "refused_orders",
            "stalls", "engine_errors", "engine_warnings", "step_ms_mean", "step_ms_max", "bot_ms_mean", "gap_median_s",
            "gap_p90_s", "gap_max_s", "y1_gap_median_s", "y1_gap_max_s", "unlocks_off", "roundtrips", "roundtrip_mismatch", "gold_negative", "off_map",
            "hangs", "ledger_mismatch"]
    rows = [[esc(k)] + [esc(r["measures"].get(k, "—")) for r in runs] for k in keys
            if any(k in r["measures"] for r in runs)]
    parts.append(section("Cifras", table(["medida"] + [f"semilla {r['seed']}" for r in runs], rows, "num")))
    parts.append(section("Curvas", f'<div class="legend">{legend}</div><div class="grid2">'
                         + line_chart("Oro de la familia", runs, "gold")
                         + line_chart("Deuda pendiente", runs, "debt")
                         + line_chart("Reputación", runs, "reputation")
                         + line_chart("Título (rango)", runs, "title_rank", step=True)
                         + line_chart("Empleados", runs, "staff", step=True)
                         + line_chart("Familia (vivos)", runs, "members", step=True) + "</div>"))
    fam_rows = []
    for r in runs:
        f = r["family"]
        ev = [f"día {w['day']}: boda de {w['character']} con {w['spouse']}" for w in f["weddings"]]
        ev += [f"día {x['day']}: nace {x['child']}" for x in f["births"]]
        ev += [f"día {x['day']}: muere {x['character']} ({x['age']} años, {x['cause']})" for x in f["deaths"]]
        ev += [f"día {x['day']}: hereda {x['heir']} de {x['from']} (generación {x['generation']})" for x in f["inheritance"]]
        ev += [f"día {x['day']}: heredero designado {x['heir']}" for x in f["heir"][:3]]
        ev += [f"día {x['day']}: título {x['title']}" for x in r["titles"]]
        ev += [f"día {x['day']}: cargo {x['office']}" for x in r["offices"]]
        fam_rows.append([esc(r["seed"]), "<br>".join(esc(e) for e in ev) or "—"])
    parts.append(section("Familia, títulos y cargos", table(["semilla", "hitos"], fam_rows)))
    if any(r.get("unlocks") for r in runs):
        ids = [u["id"] for u in runs[0]["unlocks"]]
        rows = []
        for i, uid in enumerate(ids):
            row = [esc(uid), esc(runs[0]["unlocks"][i]["window"])]
            for r in runs:
                u = next((x for x in r["unlocks"] if x["id"] == uid), {})
                v = u.get("verdict", "")
                row.append(f'<span class="v-{esc(v)}">{esc(u.get("day", "—"))} · {esc(VERDICT.get(v, v))}</span>')
            rows.append(row)
        parts.append(section("Desbloqueos frente a su ventana de 03b (día índice, ±1)",
                             table(["desbloqueo", "ventana"] + [f"semilla {r['seed']}" for r in runs], rows)))
    else:
        parts.append(section("Desbloqueos", "<p>El juego no tiene aún data/unlocks.json (llega con la forja).</p>"))
    mechs = list(runs[0]["mechanics"].keys())
    rows = []
    for k in mechs:
        row = [esc(k)]
        for r in runs:
            m = r["mechanics"][k]
            row.append(f'<span class="ok">sí</span> · día {m["first_day"]} · '
                       + (f'{m["orders"]} órdenes' if m["orders"] else f'{m["events"]} sucesos')
                       + (f', {m["refused"]} rechazadas' if m["refused"] else "")
                       if m["used"] else f'<span class="no">no</span> · {esc(why(m.get("why", "")))}')
        rows.append(row)
    parts.append(section("Mecánicas usadas y nunca tocadas", table(["mecánica"] + [f"semilla {r['seed']}" for r in runs], rows)))
    rows = [[esc(r["seed"])] + [esc(r["pacing"].get(k, "")) for k in
                                ("decisions", "gap_median_s", "gap_p90_s", "gap_max_s", "y1_gap_median_s", "y1_gap_max_s",
                                 "real_minutes")] for r in runs]
    parts.append(section("Ritmo (segundos reales entre decisiones, ×8 al saltar como el bot pacing)",
                         table(["semilla", "decisiones", "mediana s", "p90 s", "máx s", "año 1 mediana s",
                               "año 1 máx s", "minutos reales"], rows, "num")))
    rows = []
    for r in runs:
        for k, n in sorted(r["refused"].items(), key=lambda x: -x[1]):
            rows.append([esc(r["seed"]), esc(k.split("|")[0]), esc(k.split("|")[1]), esc(n)])
    parts.append(section("Órdenes rechazadas (las del bot)", table(["semilla", "orden", "motivo", "veces"], rows)
                         if rows else "<p>Ninguna.</p>"))
    rows = [[esc(r["seed"]), esc(s["kind"]), esc(s.get("name", s.get("who", ""))), esc(s.get("role", "")),
             esc(s["from_day"]), esc(s["hours"]), esc(s.get("where", "")) + (f' · <b>{esc(CAUSE.get(s.get("cause", ""), s.get("cause", "")))}</b>'
             if s.get("cause") else "")] for r in runs for s in r["stalls"]]
    rows += [[esc(r["seed"]), "encargo fallido", esc(c.get("item", "")), "", esc(c["day"]), "", esc(c["contract"])]
             for r in runs for c in r["contracts_failed"]]
    parts.append(section("Atascos y encargos fallidos", table(["semilla", "tipo", "quién", "papel", "desde el día",
                                                               "horas", "dónde"], rows) if rows else "<p>Ninguno.</p>"))
    rows = []
    for r in runs:
        e = r["engine"]
        rows.append([esc(r["seed"]), esc(e["errors"]), esc(e["warnings"]), "<br>".join(esc(x) for x in e["lines"][:8]) or "—"])
    parts.append(section("Errores y avisos del motor", table(["semilla", "errores", "avisos", "primeros"], rows)))
    rows = [[esc(r["seed"])] + [esc(r["bench"].get(k, "")) for k in
                                ("steps", "step_ms_mean", "step_ms_p99", "step_ms_max", "bot_ms_mean", "slow_steps", "hangs")]
            for r in runs]
    parts.append(section("Bench con todo encendido", table(["semilla", "pasos", "media ms", "p99 ms", "peor ms",
                                                            "bot ms", "> 50 ms", "> 2 s"], rows, "num")))
    rows = []
    for r in runs:
        c = r["chaos"]
        if c.get("roundtrips"):
            rows.append([esc(r["seed"]), esc(c["roundtrips"]), esc(c["roundtrip_mismatch"]), esc(c["load_errors"]),
                         esc(c["gold_negative"]), esc(c["off_map"]), "<br>".join(esc(x) for x in c["examples"][:6]) or "—"])
    if rows:
        parts.append(section("Guardar y cargar cada día · estados imposibles",
                             table(["semilla", "idas y vueltas", "hash distinto", "no carga", "oro < 0", "fuera del mapa",
                                    "ejemplos"], rows)))
    rows = [[esc(r["seed"]), esc(r["saves"].get("end", "")), esc(r["saves"].get("first_stall", "—"))] for r in runs]
    parts.append(section("Partidas guardadas", table(["semilla", "al final", "primer atasco"], rows)
                         + "<p>Para abrirlas: copiar el fichero a la carpeta de guardado del juego como "
                           "<code>slot_3.json</code> (macOS: ~/Library/Application Support/Godot/app_userdata/"
                           "&lt;custom_user_dir_name de project.godot&gt;/saves/) y cargar la ranura 3 desde el menú.</p>"))
    dec_rows = [[esc(r["seed"]), "<br>".join(esc(f"día {x['day']} {x['minute'] // 60:02d}:{x['minute'] % 60:02d} {x['what']}: {x['detail']}")
                                             for x in r.get("bot_report", r.get("bot", {})).get("decisions", [])[:60])] for r in runs]
    parts.append(section("Decisiones del bot (las primeras 60)", table(["semilla", "decisión"], dec_rows)))
    css = """
.viz-root{color-scheme:light;--surface-1:#fcfcfb;--text-primary:#0b0b0b;--text-secondary:#52514e;--grid:#e4e3df;
--series-1:#2a78d6;--series-2:#eb6834;--series-3:#1baf7a;--good:#008300;--bad:#c62828;
font:14px/1.45 system-ui,sans-serif;background:var(--surface-1);color:var(--text-primary);margin:0;padding:24px}
@media (prefers-color-scheme:dark){.viz-root{color-scheme:dark;--surface-1:#1a1a19;--text-primary:#f0efec;
--text-secondary:#c3c2b7;--grid:#3a3a37;--series-1:#3987e5;--series-2:#d95926;--series-3:#199e70;--good:#4caf50;--bad:#ef5350}}
h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 8px}.lead{color:var(--text-secondary)}
table{border-collapse:collapse;margin:4px 0;font-size:13px}th,td{border-bottom:1px solid var(--grid);padding:4px 10px;
text-align:left;vertical-align:top}th{color:var(--text-secondary);font-weight:600}.num td{font-variant-numeric:tabular-nums}
.grid2{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:12px}
.chart{margin:0}.chart figcaption{font-weight:600;margin-bottom:2px}.chart svg{width:100%;height:auto}
.grid{stroke:var(--grid);stroke-width:1}.tick{fill:var(--text-secondary);font-size:11px}
.hit{fill:transparent;cursor:crosshair}.legend{margin:4px 0 8px}.key{margin-right:16px;color:var(--text-secondary)}
.key i{display:inline-block;width:14px;height:3px;border-radius:2px;margin-right:6px;vertical-align:middle}
.ok{color:var(--good);font-weight:600}.no{color:var(--text-secondary)}.miss{color:var(--bad)}
.v-early,.v-late,.v-never{color:var(--bad);font-weight:600}
#tip{position:fixed;pointer-events:none;background:var(--text-primary);color:var(--surface-1);padding:3px 7px;
border-radius:4px;font-size:12px;display:none}code{font-size:12px}
"""
    js = """const t=document.getElementById('tip');document.querySelectorAll('[data-tip]').forEach(e=>{
e.addEventListener('mousemove',v=>{t.textContent=e.dataset.tip;t.style.display='block';t.style.left=(v.clientX+12)+'px';
t.style.top=(v.clientY+12)+'px'});e.addEventListener('mouseleave',()=>t.style.display='none')});"""
    title = {"full_player": "Jugador completo", "chaos_player": "Jugador caótico"}.get(bot, bot)
    return (f'<!doctype html><html lang="es"><meta charset="utf-8"><title>{esc(title)}</title><style>{css}</style>'
            f'<body class="viz-root"><h1>{esc(title)}</h1>{"".join(parts)}<div id="tip"></div><script>{js}</script></body></html>')


def main(argv):
    dirs = argv or [os.path.join(ROOT, "reports", "full_player"), os.path.join(ROOT, "reports", "chaos_player")]
    for d in dirs:
        d = os.path.join(ROOT, d) if not os.path.isabs(d) else d
        if not os.path.isdir(d):
            continue
        out = render(d)
        if out is None:
            continue
        p = os.path.join(d, "index.html")
        with open(p, "w", encoding="utf-8") as f:
            f.write(out)
        print("full_report:", p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
