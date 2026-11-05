#!/usr/bin/env python3
"""El informe de la verificación por la interfaz (docs/gdd/07_testing.md §7.6).

Lee reports/verifica/<fecha>/<flujo>/result.json (los escribe game/smoke/flow/flow_runner.gd), la lista de órdenes de
sim/core/orders.gd, dónde las da la UI (game/), los motivos apuntados en data/flows/_coverage.json y los informes de
los bots (reports/sim/*.json), y escribe:
  reports/verifica/<fecha>/index.html     el informe completo (capturas a tamaño real, para mirar en local)
  reports/verifica/<fecha>/artifact.html  lo mismo con miniaturas JPEG incrustadas (< ~0,9 MB, para Grimoire)
  reports/verifica/<fecha>/coverage.json  la tabla de cobertura de controles

  python3 tools/verifica/report.py [<dir de la fecha>] [--sim-dir=<dir>] [--artifact]
"""
import base64
import datetime
import glob
import html
import io
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEV = {"bloquea": 0, "fallo": 1, "aviso": 2, "info": 3}
KIND_NAME = {"cut": "texto cortado", "outside": "fuera de su caja o de la pantalla", "small_font": "letra pequeña",
             "bad_size": "tamaño de letra que no es el suyo", "font": "fuente fuera del theme",
             "contrast": "poco contraste", "overlap": "controles o textos solapados", "i18n": "clave sin traducir",
             "covered": "aviso tapado por un panel", "placeholder": "rótulo de greybox (falta arte)"}
STYLE_QUESTIONS = ["¿Se lee el título?", "¿Encaja la ventana con el resto?", "¿Se entiende qué hacer?"]
MAX_ARTIFACT = 900 * 1024


def esc(s):
    return html.escape(str(s), quote=True)


def load_results(day_dir):
    out = []
    for p in sorted(glob.glob(os.path.join(day_dir, "*", "result.json"))):
        try:
            with open(p, encoding="utf-8") as f:
                r = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        r["_dir"] = os.path.dirname(p)
        out.append(r)
    return out


# --- coverage ---------------------------------------------------------------------------------------------------------

def order_types():
    """The order types of Orders.apply (the match of sim/core/orders.gd)."""
    with open(os.path.join(ROOT, "sim", "core", "orders.gd"), encoding="utf-8") as f:
        src = f.read()
    out = []
    lines = src[src.index("match type:"):].splitlines()[1:]
    for line in lines:
        if line.strip() and not line.startswith("\t\t"):
            break   # the match ends where the indentation goes back
        m = re.match(r'^\t\t"([a-z_]+)":', line)
        if m:
            out.append(m.group(1))
    return out


def ui_sources():
    """order type -> [file:line] of game/ that give it (not the smoke scripts)."""
    out = {}
    for p in glob.glob(os.path.join(ROOT, "game", "**", "*.gd"), recursive=True):
        rel = os.path.relpath(p, ROOT)
        if rel.startswith("game/smoke"):
            continue
        with open(p, encoding="utf-8") as f:
            for i, line in enumerate(f, 1):
                for m in re.finditer(r'"type":\s*"([a-z_]+)"', line):
                    out.setdefault(m.group(1), []).append(f"{rel}:{i}")
                for m in re.finditer(r'"type":\s*"([a-z_]+_)"\s*\+', line):   # "npc_" + act: every order of that prefix
                    for t in order_types():
                        if t.startswith(m.group(1)):
                            out.setdefault(t, []).append(f"{rel}:{i}")
    return out


def coverage(results):
    motives_path = os.path.join(ROOT, "data", "flows", "_coverage.json")
    motives = {}
    if os.path.exists(motives_path):
        with open(motives_path, encoding="utf-8") as f:
            motives = json.load(f).get("orders", {})
    seen = {}
    for r in results:
        for o in r.get("orders", []):
            d = seen.setdefault(o["type"], {"mouse": set(), "key": set()})
            if o.get("via") in ("mouse", "key"):
                d[o["via"]].add(r["id"])
    src = ui_sources()
    rows = []
    for t in order_types():
        d = seen.get(t, {"mouse": set(), "key": set()})
        m = motives.get(t, {})
        row = {"order": t, "mouse": sorted(d["mouse"]), "key": sorted(d["key"]), "ui": src.get(t, [])[:4],
               "why_mouse": m.get("mouse", ""), "why_key": m.get("key", "")}
        gaps = []
        if not row["mouse"] and not row["why_mouse"]:
            gaps.append("ratón" + (" (hay UI, ningún flujo la pasa)" if row["ui"] else " (sin UI)"))
        if not row["key"] and not row["why_key"]:
            gaps.append("teclado")
        row["gaps"] = gaps
        rows.append(row)
    keys = []
    esc_rows = []
    for r in results:
        for k in r.get("keys", []):
            keys.append(k)
        if r["id"] == "esc":
            for s in r.get("steps", []):
                if s["id"].startswith("esc_"):
                    esc_rows.append({"what": s["say"], "ok": s["ok"], "error": s["error"], "status": s["status"]})
    clashes = static_clashes()
    return {"orders": rows, "keys": keys, "esc": esc_rows, "clashes": clashes}


def static_clashes():
    """Actions of the input map with the same key (project.godot + HudKeys)."""
    acts = {}
    with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
        txt = f.read()
    for m in re.finditer(r'^([a-z_]+)=\{\n"deadzone".*?\n"events": \[(.*?)\]\n\}', txt, re.M | re.S):
        for k in re.finditer(r'"shift_pressed":(true|false).*?"physical_keycode":(\d+)', m.group(2)):
            if int(k.group(2)) > 0:
                acts.setdefault((int(k.group(2)), k.group(1) == "true"), []).append(m.group(1))
    with open(os.path.join(ROOT, "game", "ui", "hud_keys.gd"), encoding="utf-8") as f:
        hk = f.read()
    codes = {"KEY_" + chr(c): c for c in range(ord("A"), ord("Z") + 1)}
    codes.update({f"KEY_{i}": 48 + i for i in range(10)})
    codes.update({"KEY_F1": 4194332, "KEY_ENTER": 4194309})
    for m in re.finditer(r'"([a-z_0-9]+)": \[(KEY_[A-Z0-9]+), (true|false)\]', hk):
        c = codes.get(m.group(2))
        if c is not None:
            lst = acts.setdefault((c, m.group(3) == "true"), [])
            if m.group(1) not in lst:
                lst.append(m.group(1))
    out = []
    for (c, shift), names in sorted(acts.items()):
        if len(names) > 1:
            label = ("Mayús+" if shift else "") + (chr(c) if 32 < c < 127 else str(c))
            out.append({"key": label, "actions": names})
    return out


# --- balance ----------------------------------------------------------------------------------------------------------

def balance(sim_dir):
    rows = []
    never = {}
    for p in sorted(glob.glob(os.path.join(sim_dir, "*.json"))):
        try:
            with open(p, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        a = d.get("aggregate", {})
        if not a:
            continue
        cats = {}
        for r in d.get("runs", []):
            for k, v in (r.get("by_category_1_8") or {}).items():
                cats[k] = cats.get(k, 0) + v / max(1, len(d["runs"]))
        rows.append({"file": os.path.basename(p), "bot": d.get("bot", ""), "where": d.get("start") or d.get("scenario", ""),
                     "difficulty": d.get("difficulty", ""), "days": d.get("days", 0), "seeds": d.get("seeds", 0),
                     "gold_end": a.get("mean_gold_end"), "net_day": a.get("mean_net_day_1_8"),
                     "title_rank": a.get("max_title_rank"), "refused": a.get("mean_refused_orders"),
                     "misses": len(d.get("misses", [])), "miss_list": d.get("misses", [])[:6], "cats": cats})
        for k, v in a.items():
            if k.startswith("max_"):
                never.setdefault(k[4:], []).append(v)
    zero = sorted(k for k, v in never.items() if v and all((x or 0) == 0 for x in v)
                  and not k.startswith(("ev_", "mev_", "ledger_mismatch", "prod_gain_error", "refused", "events_overdue",
                                        "contracts_failed", "duels_lost", "duel_no_show", "duel_draws", "thefts",
                                        "trv_ambushes", "trv_caravan_ambushes", "trv_treaties_broken", "guilty",
                                        "low_morale", "ai_accusations_bad")))
    # where the money goes on average across bots: the categories that only take
    sums = {}
    for r in rows:
        for k, v in r["cats"].items():
            sums.setdefault(k, []).append(v)
    only_take = sorted(k for k, v in sums.items() if v and all(x <= 0 for x in v) and k not in ("upkeep", "wages", "loans"))
    return {"rows": rows, "never": zero, "only_take": only_take}


# --- findings ---------------------------------------------------------------------------------------------------------

def findings(results, cov):
    out = []
    for r in results:
        for s in r.get("steps", []):
            if s.get("status") in ("falla", "falla (sigue)"):
                sev = "bloquea" if s["status"] == "falla" else "fallo"
                out.append({"sev": sev, "where": f"{r['id']} · paso {s['n']} {s['id']}", "what": s["error"],
                            "shot": os.path.join(r["id"], s["shot"]) if s.get("shot") else ""})
            for n in s.get("notes", []):
                out.append({"sev": "aviso", "where": f"{r['id']} · paso {s['n']} {s['id']}", "what": n, "shot": ""})
        for e in r.get("engine_errors", []):
            out.append({"sev": "fallo", "where": f"{r['id']} · motor", "what": e, "shot": ""})
        if r.get("error"):
            out.append({"sev": "bloquea", "where": r["id"], "what": r["error"], "shot": ""})
    groups = {}
    for r in results:
        for v in r.get("visual", []):
            k = (v["kind"], v["screen"], v["severity"])
            g = groups.setdefault(k, {"n": 0, "examples": [], "flows": set(), "crop": ""})
            g["n"] += 1
            g["flows"].add(r["id"])
            if len(g["examples"]) < 3:
                g["examples"].append(f"«{v['text']}»: {v['detail']}")
            if not g["crop"] and v.get("crop"):
                g["crop"] = os.path.join(r["id"], v["crop"])
    for (kind, screen, sev), g in groups.items():
        out.append({"sev": sev, "where": f"{screen} · {KIND_NAME.get(kind, kind)} ×{g['n']}",
                    "what": " · ".join(g["examples"]) + f" (flujos: {', '.join(sorted(g['flows']))})",
                    "shot": g["crop"]})
    for row in cov["orders"]:
        if row["gaps"]:
            out.append({"sev": "aviso" if "teclado" == " ".join(row["gaps"]) else "fallo",
                        "where": f"cobertura · {row['order']}", "what": "falta camino por " + " y ".join(row["gaps"]),
                        "shot": ""})
    for c in cov["clashes"]:
        out.append({"sev": "aviso", "where": f"teclas · {c['key']}", "what": "la misma tecla para " + ", ".join(c["actions"]),
                    "shot": ""})
    out.sort(key=lambda f: (SEV.get(f["sev"], 9), f["where"]))
    return out


# --- html -------------------------------------------------------------------------------------------------------------

CSS = """
body{font:14px/1.45 -apple-system,Segoe UI,sans-serif;margin:0;background:#1d1712;color:#ece4d2}
main{max-width:1240px;margin:0 auto;padding:16px 20px 60px}
h1{font-size:22px;margin:4px 0 2px;color:#f2d880} h2{font-size:18px;color:#f2d880;border-bottom:1px solid #5c3a1e;padding-bottom:4px;margin-top:34px}
h3{font-size:15px;margin:22px 0 6px;color:#e8cf8a}
a{color:#8ab4d0} .dim{color:#a89878} .ok{color:#7ec87e} .bad{color:#e06a5a} .warn{color:#e0a040}
table{border-collapse:collapse;width:100%;margin:6px 0 12px} th,td{border-bottom:1px solid #3e2814;padding:4px 6px;text-align:left;vertical-align:top}
th{color:#c8a84e;font-weight:600;background:#2a1f14;position:sticky;top:0}
.pill{display:inline-block;padding:0 7px;border-radius:9px;font-size:12px;font-weight:600}
.s-bloquea{background:#9a2a22;color:#fff}.s-fallo{background:#c85050;color:#fff}.s-aviso{background:#e0a040;color:#1d1712}.s-info{background:#8ab4d0;color:#1d1712}
.st-ok{color:#7ec87e}.st-falla{color:#e06a5a;font-weight:700}.st-omitido{color:#a89878}
img.thumb{width:240px;image-rendering:pixelated;border:1px solid #5c3a1e;display:block}
img.crop{max-width:260px;image-rendering:pixelated;border:1px solid #9a2a22}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}
.card{background:#2a1f14;border:1px solid #5c3a1e;padding:8px;border-radius:4px}
.card img{width:100%;image-rendering:pixelated}
.q{margin:4px 0 0 0;padding-left:18px} .q li{color:#d4b896}
nav a{margin-right:12px} code{background:#120d08;padding:0 4px;border-radius:3px;font-size:12px}
details summary{cursor:pointer;color:#e8cf8a}
"""


class Images:
    """Where an image comes from: a relative path (index.html) or an embedded JPEG thumbnail (artifact.html)."""

    def __init__(self, day_dir, embed, width, budget=0):
        self.day_dir = day_dir
        self.embed = embed
        self.width = width
        self.cache = {}
        self.budget = budget   # bytes of embedded images allowed (0 = no limit); past it, images are left out
        self.used = 0

    def src(self, rel, width=None):
        if not rel:
            return ""
        if not self.embed:
            return esc(rel)
        key = (rel, width or self.width)
        if key in self.cache:
            return self.cache[key]
        p = os.path.join(self.day_dir, rel)
        if not os.path.exists(p):
            return ""
        from PIL import Image
        im = Image.open(p).convert("RGB")
        w = width or self.width
        if im.width > w:
            im = im.resize((w, max(1, im.height * w // im.width)), Image.NEAREST)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=62)
        s = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
        if self.budget and self.used + len(s) > self.budget:
            return ""
        self.used += len(s)
        self.cache[key] = s
        return s


def page(results, cov, bal, finds, imgs, full):
    date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    ok = sum(1 for r in results if r.get("ok"))
    branch = subprocess.run(["git", "-C", ROOT, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True).stdout.strip()
    commit = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    h = [f"<!doctype html><html lang=es><meta charset=utf-8><title>Verificación · {esc(branch)}</title><style>{CSS}</style><main>"]
    h.append(f"<h1>Verificación por la interfaz · rama {esc(branch)} ({esc(commit)})</h1>")
    win = any(r.get("window") for r in results)
    h.append(f"<p class=dim>{date} · {ok}/{len(results)} flujos en verde · {'con ventana y capturas' if win else 'sin ventana (sin capturas ni contraste)'}"
             f" · jugado solo con eventos de ratón y teclado (game/smoke/flow/)</p>")
    h.append("<nav><a href=#hallazgos>Hallazgos</a><a href=#estilo>Revisión de estilo</a><a href=#flujos>Flujos</a>"
             "<a href=#pantallas>Por pantalla</a><a href=#cobertura>Cobertura</a><a href=#balance>Balance</a></nav>")
    # summary
    h.append("<h2 id=flujos>Flujos</h2><table><tr><th>Flujo</th><th>Resultado</th><th>Pasos</th><th>Tiempo</th><th>Visual</th><th>Interrupciones</th></tr>")
    for r in results:
        steps = r.get("steps", [])
        good = sum(1 for s in steps if s.get("ok"))
        inter = sum(len(s.get("interruptions", []) or []) for s in steps)
        vis = r.get("visual", [])
        nf = sum(1 for v in vis if v["severity"] == "fallo")
        h.append(f"<tr><td><a href=#f-{esc(r['id'])}>{esc(r['title'])}</a> <span class=dim>{esc(r['id'])}</span></td>"
                 f"<td class={'ok' if r.get('ok') else 'bad'}>{'verde' if r.get('ok') else 'falla'}</td><td>{good}/{len(steps)}</td>"
                 f"<td>{r.get('seconds', 0)} s</td><td>{nf} fallos · {len(vis) - nf} avisos</td><td>{inter}</td></tr>")
    h.append("</table>")
    # findings
    h.append("<h2 id=hallazgos>Hallazgos, por gravedad</h2><p class=dim>bloquea = el flujo no pudo seguir · fallo = algo no "
             "funciona o se ve mal · aviso = a revisar.</p><table><tr><th></th><th>Dónde</th><th>Qué</th><th></th></tr>")
    for i, f in enumerate(finds):
        if not full and i >= 40:
            f = dict(f, shot="")
        im = f'<img class=crop src="{imgs.src(f["shot"], 320)}">' if f.get("shot") and imgs.src(f["shot"], 320) else ""
        h.append(f"<tr><td><span class='pill s-{f['sev']}'>{f['sev']}</span></td><td>{esc(f['where'])}</td><td>{esc(f['what'])}</td><td>{im}</td></tr>")
    h.append("</table>")
    # style sheet
    h.append("<h2 id=estilo>Revisión de estilo</h2><p class=dim>Una captura por pantalla, una al lado de otra. Mírala con tus ojos: "
             + " ".join(STYLE_QUESTIONS) + "</p><div class=grid>")
    seen = {}
    for r in results:
        for s in r.get("steps", []):
            if s.get("shot") and s.get("screen") and s["screen"] not in seen and s.get("ok"):
                seen[s["screen"]] = (r["id"], s)
    for screen, (fid, s) in sorted(seen.items()):
        shot = os.path.join(fid, s["shot"])
        h.append(f"<div class=card><b>{esc(screen)}</b> <span class=dim>· {esc(fid)} paso {s['n']}</span>"
                 f"<a href='{esc(shot)}'><img loading=lazy src='{imgs.src(shot, 420)}'></a><ul class=q>"
                 + "".join(f"<li>{q}</li>" for q in STYLE_QUESTIONS) + "</ul></div>")
    if not seen:
        h.append("<p class=dim>Sin capturas: corre con <code>--window</code>.</p>")
    h.append("</div>")
    # per flow
    for r in results:
        h.append(f"<h3 id=f-{esc(r['id'])}>{esc(r['title'])} <span class={'ok' if r.get('ok') else 'bad'}>"
                 f"{'verde' if r.get('ok') else 'falla'}</span> <span class=dim>· {r.get('seconds', 0)} s · empieza en "
                 f"{esc(json.dumps(r.get('start', {}), ensure_ascii=False))}</span></h3><p class=dim>{esc(r.get('about', ''))}</p>")
        h.append("<table><tr><th>#</th><th>Paso</th><th>Captura</th><th>Comprobaciones</th><th>Órdenes · sucesos</th><th>t</th></tr>")
        prev_screen = ""
        for s in r.get("steps", []):
            st = s.get("status", "")
            keep = full or not s.get("ok") or s.get("screen") != prev_screen   # the artifact: failures and new screens
            prev_screen = s.get("screen", "")
            cls = "st-ok" if st == "ok" else ("st-omitido" if st in ("omitido", "no se corrió") else "st-falla")
            shot = os.path.join(r["id"], s["shot"]) if s.get("shot") and keep else ""
            im = f'<a href="{esc(shot)}"><img class=thumb loading=lazy src="{imgs.src(shot)}"></a>' if shot and imgs.src(shot) else "<span class=dim>—</span>"
            checks = "<br>".join(f"<span class={'ok' if c['ok'] else 'bad'}>{'✓' if c['ok'] else '✗'}</span> <code>{esc(c['expr'])}</code>"
                                 for c in s.get("checks", []))
            orders = ", ".join(f"{o['type']}<span class=dim>/{o['via']}</span>" for o in s.get("orders", []))
            ev = s.get("events") if isinstance(s.get("events"), dict) else {}
            evs = ", ".join(k for k in list(ev)[:6] if k not in ("character_moved", "town_state", "character_arrived"))
            extra = ""
            if s.get("error"):
                extra += f"<div class=bad>{esc(s['error'])}</div>"
            for n in s.get("interruptions", []) or []:
                extra += f"<div class=warn>interrupción: {esc(n)}</div>"
            for n in s.get("notes", []) or []:
                extra += f"<div class=warn>{esc(n)}</div>"
            h.append(f"<tr><td>{s['n']}</td><td><b>{esc(s.get('say') or s['id'])}</b><br><span class=dim>{esc(s.get('action', ''))}</span>"
                     f"<br><span class='{cls}'>{esc(st)}</span> <span class=dim>{esc(s.get('clock', '') or '')} · {esc(s.get('screen', ''))}</span>{extra}</td>"
                     f"<td>{im}</td><td>{checks}</td><td>{orders}<br><span class=dim>{esc(evs)}</span></td><td>{s.get('seconds', '')}</td></tr>")
        h.append("</table>")
    # per screen
    h.append("<h2 id=pantallas>Fallos visuales por pantalla</h2>")
    by_screen = {}
    for r in results:
        for v in r.get("visual", []):
            by_screen.setdefault(v["screen"], []).append((r["id"], v))
    for screen in sorted(by_screen):
        items = by_screen[screen]
        nf = sum(1 for _, v in items if v["severity"] == "fallo")
        h.append(f"<details {'open' if nf else ''}><summary><b>{esc(screen)}</b> · {nf} fallos · {len(items) - nf} avisos</summary><table>"
                 "<tr><th></th><th>Qué</th><th>Texto</th><th>Detalle</th><th>Recorte</th></tr>")
        shown = 0
        for fid, v in sorted(items, key=lambda x: (SEV.get(x[1]["severity"], 9), x[1]["kind"])):
            if shown >= (60 if full else 25):
                h.append(f"<tr><td colspan=5 class=dim>… y {len(items) - shown} más</td></tr>")
                break
            shown += 1
            crop = os.path.join(fid, v["crop"]) if v.get("crop") and (full or shown <= 4) else ""
            im = f'<img class=crop src="{imgs.src(crop, 260)}">' if crop and imgs.src(crop, 260) else ""
            h.append(f"<tr><td><span class='pill s-{v['severity']}'>{v['severity']}</span></td><td>{esc(KIND_NAME.get(v['kind'], v['kind']))}"
                     f"<br><span class=dim>{esc(v['node'])}</span></td><td>{esc(v['text'])}</td><td>{esc(v['detail'])}"
                     f"<br><span class=dim>{fid} · paso {v.get('step')} · ×{v.get('count', 1)}</span></td><td>{im}</td></tr>")
        h.append("</table></details>")
    # coverage
    h.append("<h2 id=cobertura>Cobertura de controles</h2><p class=dim>Cada orden de <code>Orders.apply</code>: los flujos que la "
             "dieron con el ratón y con el teclado, dónde la da la UI y el motivo apuntado (data/flows/_coverage.json) si no hace falta.</p>")
    h.append("<table><tr><th>Orden</th><th>Ratón</th><th>Teclado</th><th>UI</th><th>Huecos</th></tr>")
    for row in cov["orders"]:
        mouse = ", ".join(row["mouse"]) or (f"<span class=dim>{esc(row['why_mouse'])}</span>" if row["why_mouse"] else "<span class=bad>—</span>")
        key = ", ".join(row["key"]) or (f"<span class=dim>{esc(row['why_key'])}</span>" if row["why_key"] else "<span class=warn>—</span>")
        ui = "<br>".join(f"<code>{esc(u)}</code>" for u in row["ui"]) or "<span class=bad>ninguna</span>"
        h.append(f"<tr><td><code>{esc(row['order'])}</code></td><td>{mouse}</td><td>{key}</td><td>{ui}</td><td class=bad>{esc(', '.join(row['gaps']))}</td></tr>")
    h.append("</table>")
    covered_m = sum(1 for r in cov["orders"] if r["mouse"])
    covered_k = sum(1 for r in cov["orders"] if r["key"])
    h.insert(h.index("<table><tr><th>Orden</th><th>Ratón</th><th>Teclado</th><th>UI</th><th>Huecos</th></tr>"),
             f"<p><b>{covered_m}/{len(cov['orders'])}</b> órdenes con camino por ratón probado · <b>{covered_k}/{len(cov['orders'])}</b> por teclado.</p>")
    h.append("<h3>Teclas (auditoría del flujo «teclas»)</h3><table><tr><th>Contexto</th><th>Tecla</th><th>Lo que hizo</th><th>Lo esperado</th><th></th></tr>")
    for k in cov["keys"]:
        eff = ", ".join(k["effects"]) or "nada"
        bad = (not k["effects"] and "nada" not in k.get("expected", "") and "solo" not in k.get("expected", "")) or k.get("clash")
        h.append(f"<tr><td>{esc(k['context'])}</td><td><code>{esc(k['key'])}</code></td><td>{esc(eff)}</td><td class=dim>{esc(k.get('expected', ''))}</td>"
                 f"<td class={'bad' if bad else 'ok'}>{'choca' if k.get('clash') else ('no hace nada' if bad else 'ok')}</td></tr>")
    h.append("</table><h3>Misma tecla para dos acciones (mapa de entrada)</h3><table><tr><th>Tecla</th><th>Acciones</th></tr>")
    for c in cov["clashes"]:
        h.append(f"<tr><td><code>{esc(c['key'])}</code></td><td>{esc(', '.join(c['actions']))}</td></tr>")
    h.append("</table><h3>Esc cierra cada pantalla (flujo «esc»)</h3><table><tr><th>Pantalla</th><th></th></tr>")
    for e in cov["esc"]:
        h.append(f"<tr><td>{esc(e['what'])}</td><td class={'ok' if e['ok'] else 'bad'}>{'sí' if e['ok'] else esc(e['error'] or e['status'])}</td></tr>")
    h.append("</table>")
    # balance
    h.append("<h2 id=balance>Balance (informes de los bots)</h2><p class=dim>reports/sim/*.json: oro al final, oro neto por día de la "
             "fase de inicio, título más alto, rechazos, dianas fallidas.</p><table><tr><th>Bot</th><th>Dónde</th><th>Días×semillas</th>"
             "<th>Oro final</th><th>Neto/día 1-8</th><th>Título</th><th>Rechazos</th><th>Dianas fallidas</th></tr>")
    for b in bal["rows"]:
        h.append(f"<tr><td>{esc(b['bot'])}</td><td>{esc(b['where'])} {esc(b['difficulty'])}</td><td>{b['days']}×{b['seeds']}</td>"
                 f"<td>{_n(b['gold_end'])}</td><td>{_n(b['net_day'])}</td><td>{_n(b['title_rank'])}</td><td>{_n(b['refused'])}</td>"
                 f"<td class={'bad' if b['misses'] else 'ok'}>{b['misses']} {esc('; '.join(map(str, b['miss_list'])))[:200]}</td></tr>")
    h.append("</table>")
    if bal["never"]:
        h.append(f"<p><b>Nunca pasa en ningún bot</b> (máximo 0 en todos): {esc(', '.join(bal['never']))}</p>")
    if bal["only_take"]:
        h.append(f"<p><b>Gastos que nunca devuelven</b> (siempre negativos en los días 1-8 de todos los bots): {esc(', '.join(bal['only_take']))}</p>")
    h.append("<h2>Cómo se lanza</h2><pre>python3 tools/verifica/verifica.py --flows=quick            # sin ventana, rápido\n"
             "python3 tools/verifica/verifica.py --window --flows=all --artifact   # completo, con capturas (por grimoire heavy)\n"
             "/opt/homebrew/bin/godot --path . -- --flow=primer_dia             # un flujo a mano</pre></main>")
    return "\n".join(h)


def _n(x):
    if x is None:
        return "—"
    return f"{x:.0f}" if isinstance(x, float) and abs(x) >= 10 else (f"{x:.1f}" if isinstance(x, float) else str(x))


def build(day_dir, sim_dir=None):
    results = load_results(day_dir)
    order = {fid: i for i, fid in enumerate(["primer_dia", "contratar_cola", "mejorar", "pagar_deuda", "cortejo_boda",
                                            "titulo", "elecciones", "tribunal", "viajes", "fiesta_boda", "duelo", "taberna",
                                            "dados", "suceso", "guardar_cargar", "opciones_tutorial", "mapa_region",
                                            "otra_ciudad", "teclas", "esc"])}
    results.sort(key=lambda r: (order.get(r["id"], 99), r["id"]))
    cov = coverage(results)
    bal = balance(sim_dir or os.path.join(ROOT, "reports", "sim"))
    finds = findings(results, cov)
    with open(os.path.join(day_dir, "coverage.json"), "w", encoding="utf-8") as f:
        json.dump(cov, f, ensure_ascii=False, indent=1)
    with open(os.path.join(day_dir, "findings.json"), "w", encoding="utf-8") as f:
        json.dump(finds, f, ensure_ascii=False, indent=1)
    full = page(results, cov, bal, finds, Images(day_dir, False, 0), True)
    path = os.path.join(day_dir, "index.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(full)
    text_only = len(page(results, cov, bal, finds, Images(day_dir, True, 160, 1), False).encode())
    budget = max(0, MAX_ARTIFACT - text_only - 20 * 1024)
    art = page(results, cov, bal, finds, Images(day_dir, True, 160, budget), False)
    with open(os.path.join(day_dir, "artifact.html"), "w", encoding="utf-8") as f:
        f.write(art)
    return path, len(art.encode())


def publish(day_dir):
    """Registers artifact.html in Grimoire (grimoire cmd artifact.create)."""
    with open(os.path.join(day_dir, "artifact.html"), encoding="utf-8") as f:
        art = f.read()
    branch = subprocess.run(["git", "-C", ROOT, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True).stdout.strip()
    args = {"title": f"GuildMaster · verificación por la interfaz ({branch})", "html": art,
            "description": "Flujos jugados con ratón y teclado: pasos, capturas, comprobaciones, cobertura de controles, balance y revisión de estilo."}
    thread = os.environ.get("GRIMOIRE_THREAD_ID", "")
    if thread:
        args["threadId"] = thread
    p = subprocess.run(["grimoire", "cmd", "artifact.create", json.dumps(args, ensure_ascii=False)], capture_output=True, text=True)
    print((p.stdout or p.stderr).strip()[:300])


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    d = a[0] if a else os.path.join(ROOT, "reports", "verifica", datetime.date.today().isoformat())
    sd = next((x[10:] for x in sys.argv if x.startswith("--sim-dir=")), None)
    p, size = build(d, sd)
    print(f"informe: {p} (artifact {size / 1024:.0f} KB)")
    if "--artifact" in sys.argv:
        publish(d)
