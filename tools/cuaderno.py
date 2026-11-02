#!/usr/bin/env python3
"""Regenera el cuaderno del juego (página de Grimoire «GuildMaster · cuaderno») a partir del repo.

Junta en una página: estado de los hitos (docs/hitos.json), estado del arte y del audio (assets/inventario.json vía
tools/arte.py), novedades con capturas (docs/novedades.json) y decisiones (docs/decisiones.json).
La primera vez crea la página en Grimoire y apunta su id en docs/paginas.json.

Uso: python3 tools/cuaderno.py [--thread <id del hilo de Grimoire>]
"""
import html
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import arte  # noqa: E402
import paginas  # noqa: E402

TITLE = "GuildMaster · cuaderno"
DESCRIPTION = "Cuaderno de GuildMaster: hitos, estado del arte, novedades con capturas y decisiones. Se regenera con python3 tools/cuaderno.py."
ARTIFACTS = os.path.expanduser("~/.grimoire/workspace/artifacts")
DEFAULT_THREAD = "th_01m6abhw3p14d9ywct08"

# (qué hace, tecla). Se rellena cuando el juego tenga controles.
CONTROLS = []

E = html.escape
MARK = {"hecho": "✔", "en_curso": "◐", "pendiente": "·"}


def load(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return json.load(f)


def git_head():
    try:
        return subprocess.check_output(["git", "-C", ROOT, "log", "-1", "--format=%h · %s"], text=True,
                                       stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "sin commits"


def table(headers, rows):
    out = ["<table><thead><tr>"] + [f"<th>{E(h)}</th>" for h in headers] + ["</tr></thead><tbody>"]
    out += ["<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows]
    return "".join(out) + "</tbody></table>"


def milestones_html():
    out = []
    for h in load("docs/hitos.json")["hitos"]:
        crit = h["criterios"]
        done = sum(c["estado"] == "hecho" for c in crit)
        items = "".join(
            f"<li class='{c['estado']}'><span class='mk'>{MARK.get(c['estado'], '·')}</span> {E(c['texto'])}"
            + (f" <span class='muted'>· {E(c['prueba'])} ({E(c['fecha'] or '')})</span>" if c.get("prueba") else "")
            + "</li>" for c in crit)
        out.append(f"<details class='hito {h['estado']}'{' open' if h['estado'] == 'en_curso' else ''}>"
                   f"<summary><b>{E(h['id'])}</b> {E(h['nombre'])} <span class='pill {h['estado']}'>{E(h['estado'].replace('_', ' '))}</span>"
                   f" <span class='muted'>{done}/{len(crit)}</span></summary>"
                   f"<p class='muted'>{E(h['entregable'])}</p><ul class='crit'>{items}</ul></details>")
    return "".join(out)


def art_html():
    r = arte.analyse()
    states = r["estados"]
    head = "".join(f"<div class='stat'><b>{r['por_estado'].get(s, 0)}</b><span>{E(s)}</span></div>" for s in states)
    by_type = table(["Tipo"] + states + ["audio"], [
        [E(k)] + [str(v.get(s, "")) for s in states] + [str(sum(n for s, n in v.items() if s not in states) or "")]
        for k, v in sorted(r["por_tipo"].items())])
    by_m = table(["Hito", "Assets", "En final"], [
        [E(m), str(c["total"]), str(c["hechos"])]
        for m, c in sorted(r["por_hito"].items(), key=lambda x: int(re.sub(r"\D", "", x[0]) or 0))])
    todo = table(["Asset", "Tipo", "Estado", "Para", "Falta"], [
        [f"<code>{E(t['id'])}</code>", E(t["tipo"]), E(t["estado"]), E(", ".join(t["para"])),
         E(", ".join(t["faltan_animaciones"]) or t["notas"])] for t in r["todo"]])
    errs = "".join(f"<p class='bad'>✖ {E(e)}</p>" for e in r["errors"])
    missing = "".join(f"<li><code>{E(s['id'])}</code> · {E(s['que'])} de {E(s['de'])}</li>" for s in r["sin_entrada"])
    return (f"<div class='stats'>{head}</div>{errs}<div class='grid2'><div>{by_type}</div><div>{by_m}</div></div>"
            + (f"<h3>El contenido lo pide y no está en el inventario</h3><ul>{missing}</ul>" if missing else "")
            + f"<details><summary>Lista de trabajo ({len(r['todo'])})</summary><div class='tablewrap'>{todo}</div></details>")


def news_html(art_dir):
    out = []
    os.makedirs(os.path.join(art_dir, "img"), exist_ok=True)
    for n in load("docs/novedades.json"):
        imgs = []
        for c in n.get("capturas", []):
            src = os.path.join(ROOT, c)
            if os.path.exists(src):
                name = os.path.basename(c)
                shutil.copyfile(src, os.path.join(art_dir, "img", name))
                imgs.append(f"<a href='img/{E(name)}'><img src='img/{E(name)}' alt='{E(n['titulo'])}' loading='lazy'></a>")
        out.append(f"<article><div class='muted'>{E(n['fecha'])}</div><h3>{E(n['titulo'])}</h3><p>{E(n['que'])}</p>"
                   + (f"<p class='muted'><b>Cómo probarlo:</b> {E(n['como_probar'])}</p>" if n.get("como_probar") else "")
                   + (f"<div class='shots'>{''.join(imgs)}</div>" if imgs else "") + "</article>")
    return "".join(out) or "<p class='muted'>Sin novedades todavía.</p>"


def decisions_html():
    d = load("docs/decisiones.json")
    taken = table(["Fecha", "Tema", "Decisión", "Por qué"], [
        [E(x["fecha"]), f"<b>{E(x['tema'])}</b>", E(x["decision"]), f"<span class='muted'>{E(x['por_que'])}</span>"]
        for x in reversed(d["tomadas"])])
    pending = "".join(f"<div class='card'><h3>{E(p['tema'])}</h3><p>{E(p['detalle'])}</p>"
                      + (f"<p class='muted'>{E(p['opciones'])}</p>" if p.get("opciones") else "") + "</div>"
                      for p in d["pendientes"])
    steps = "".join(f"<li>{E(s)}</li>" for s in d["proximos_pasos"])
    return (f"<h3>Próximos pasos</h3><ol>{steps}</ol><h3>Pendientes</h3><div class='grid'>{pending}</div>"
            f"<details><summary>Tomadas ({len(d['tomadas'])})</summary><div class='tablewrap'>{taken}</div></details>")


def build(art_dir):
    controls = ""
    if CONTROLS:
        controls = "<h2 id='controles'>Controles</h2>" + table(["Qué hace", "Tecla"], [[E(a), f"<code>{E(b)}</code>"] for a, b in CONTROLS])
    now = datetime.now().strftime("%d/%m/%Y %H:%M")
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>GuildMaster · cuaderno</title>
<style>
:root{{--bg:#f6efe1;--bg2:#efe4cf;--card:#fffaf0;--line:#dccbaa;--ink:#2a1f14;--muted:#7a6a55;--gold:#8a6420;--good:#3f8a4f;--bad:#b04040;--run:#b07a20}}
@media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{--bg:#17120c;--bg2:#211910;--card:#261d13;--line:#3a2d1e;--ink:#ecdfc6;--muted:#a8977c;--gold:#d9b46a;--good:#7ec87e;--bad:#e07a6a;--run:#e0b060}}}}
:root[data-theme="dark"]{{--bg:#17120c;--bg2:#211910;--card:#261d13;--line:#3a2d1e;--ink:#ecdfc6;--muted:#a8977c;--gold:#d9b46a;--good:#7ec87e;--bad:#e07a6a;--run:#e0b060}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 system-ui,sans-serif}}
.wrap{{max-width:1080px;margin:0 auto;padding:0 16px 64px}}header{{padding:32px 0 12px}}
h1,h2{{font-family:Georgia,serif;color:var(--gold);font-weight:600}}h1{{margin:0;font-size:clamp(28px,5vw,40px)}}h2{{margin:36px 0 10px;font-size:24px}}h3{{font-size:16px;margin:16px 0 6px}}
.muted{{color:var(--muted)}}code{{font:12.5px ui-monospace,Menlo,monospace;background:var(--bg2);padding:1px 5px;border-radius:4px}}
nav{{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}}nav a{{color:var(--muted);text-decoration:none;border:1px solid var(--line);padding:3px 10px;border-radius:20px;font-size:13px}}
table{{width:100%;border-collapse:collapse;font-size:14px;margin:6px 0}}th,td{{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}}th{{color:var(--muted)}}
.tablewrap{{overflow-x:auto}}.grid{{display:grid;gap:12px;grid-template-columns:repeat(auto-fill,minmax(280px,1fr))}}.grid2{{display:grid;gap:16px;grid-template-columns:repeat(auto-fit,minmax(300px,1fr))}}
.card,article,details.hito{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px;margin:8px 0}}
summary{{cursor:pointer}}.pill{{font-size:12px;padding:1px 8px;border-radius:10px;border:1px solid var(--line);margin-left:6px}}
.pill.hecho{{color:var(--good);border-color:var(--good)}}.pill.en_curso{{color:var(--run);border-color:var(--run)}}
ul.crit{{list-style:none;padding-left:4px}}ul.crit li.hecho .mk{{color:var(--good)}}ul.crit li.en_curso .mk{{color:var(--run)}}.mk{{display:inline-block;width:1.2em}}
.stats{{display:flex;flex-wrap:wrap;gap:10px}}.stat{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:8px 14px;min-width:96px}}.stat b{{display:block;font-size:22px;color:var(--gold)}}.stat span{{color:var(--muted);font-size:13px}}
.shots{{display:flex;flex-wrap:wrap;gap:8px}}.shots img{{max-width:min(100%,420px);border-radius:6px;border:1px solid var(--line);image-rendering:pixelated}}
.bad{{color:var(--bad)}}
</style></head><body><div class="wrap">
<header><h1>GuildMaster · cuaderno</h1><div class="muted">Actualizado {now} · {E(git_head())}</div>
<nav><a href="#hitos">Hitos</a><a href="#arte">Arte y audio</a><a href="#novedades">Novedades</a><a href="#decisiones">Decisiones</a>{'<a href="#controles">Controles</a>' if CONTROLS else ''}</nav></header>
<h2 id="hitos">Hitos</h2>{milestones_html()}
<h2 id="arte">Arte y audio</h2><p class="muted">Escala: falta → greybox → concepto → sprite → animado → final (audio: falta → provisional → generado → final). Fuente: <code>assets/inventario.json</code>.</p>{art_html()}
<h2 id="novedades">Novedades</h2>{news_html(art_dir)}
<h2 id="decisiones">Decisiones</h2>{decisions_html()}
{controls}
</div></body></html>"""


def ensure_page(thread):
    aid = paginas.id_de(TITLE)
    if aid and os.path.isdir(os.path.join(ARTIFACTS, aid)):
        return aid
    args = json.dumps({"title": TITLE, "html": "<p>Generando…</p>", "description": DESCRIPTION, "threadId": thread})
    out = subprocess.check_output(["grimoire", "cmd", "artifact.create", args], text=True)
    m = re.search(r"art_[0-9a-z]+", out)
    if not m:
        raise SystemExit(f"cuaderno: Grimoire no devolvió un id: {out[:200]}")
    paginas.guardar(TITLE, m.group(0), "tools/cuaderno.py")
    return m.group(0)


def touch_meta(art_dir):
    """Marks the page as updated in artifact.json so Grimoire lists it as recent and reloads it."""
    meta_path = os.path.join(art_dir, "artifact.json")
    if not os.path.isfile(meta_path):
        return
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
    meta["updatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    tmp = meta_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    os.replace(tmp, meta_path)


def main(argv):
    thread = argv[argv.index("--thread") + 1] if "--thread" in argv else DEFAULT_THREAD
    aid = ensure_page(thread)
    art_dir = os.path.join(ARTIFACTS, aid)
    os.makedirs(art_dir, exist_ok=True)
    page = build(art_dir)
    tmp = os.path.join(art_dir, "index.html.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(page)
    os.replace(tmp, os.path.join(art_dir, "index.html"))
    touch_meta(art_dir)
    print(f"cuaderno: {aid} · {len(page) // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
