#!/usr/bin/env python3
"""Galería de la producción con fal (2026-11-03), en tres páginas (el servidor de Grimoire acepta como mucho 1 MB por
petición): retratos, ilustraciones (eventos, estaciones y cartas) y pantallas. Las imágenes van en hojas compuestas
(PNG de paleta) y se amplían con vecino más cercano en el navegador.

Uso: python3 tools/art/fal_produccion_galeria.py [--publicar]
  -> assets/art/fal_produccion/galeria_<pagina>.html; con --publicar las registra en Grimoire (artifact.create).
"""
import argparse
import base64
import html
import io
import json
import os
import sys
import urllib.request

from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import fal_ilustraciones as fi  # noqa: E402
import fal_retratos as fr  # noqa: E402
import personajes_guild as pg  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PROD = os.path.join(ROOT, "assets", "art", "fal_produccion")
PORTRAITS = os.path.join(ROOT, "assets", "art", "portraits")
ILLUS = os.path.join(ROOT, "assets", "art", "illustrations")
LEDGER = os.path.join(ROOT, "assets", "art", "fal_piloto", "gasto.json")
BG = (62, 40, 20)
FAMILY_B = {1: (30, 24, 20), 2: (150, 100, 70), 3: (40, 70, 130), 4: (190, 190, 200)}
FAMILY_C = {1: (200, 150, 60), 2: (240, 200, 170), 3: (50, 110, 60), 4: (120, 70, 40)}
GROUPS = [("Familia del jugador · Artesano", "artisan_"), ("Familia del jugador · Patrón", "patron_"),
          ("Familia del jugador · Erudito", "scholar_"), ("Familia del jugador · Pícaro", "rogue_"),
          ("Empleados", "worker_"), ("Vecinos", "townsfolk_"), ("Familias rivales", "rival_"),
          ("Cargos y personajes únicos", None)]
STAGES = ["child", "youth", "adult", "mature", "elder"]


def uri(im, jpeg=False):
    buf = io.BytesIO()
    im = im.convert("RGB")
    if jpeg:
        im.save(buf, "JPEG", quality=60)
        return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    cols = im.getcolors(256)
    im = im.quantize(colors=len(cols) if cols else 256, method=Image.Quantize.FASTOCTREE if cols else
                     Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def tag(im, z=1, cap="", jpeg=False, width=0):
    style = f"width:{width}px" if width else f"width:{im.width * z}px;height:{im.height * z}px"
    return (f"<figure><img class='px' style='{style}' src='{uri(im, jpeg)}'>"
            f"<figcaption>{html.escape(cap)}</figcaption></figure>")


def row(cells):
    return "<div class='row'>" + "".join(cells) + "</div>"


def order(pid):
    parts = pid.split("_")
    return (STAGES.index(parts[1]) if len(parts) > 1 and parts[1] in STAGES else 9, pid)


def on_bg(im):
    out = Image.new("RGBA", im.size, BG + (255,))
    out.alpha_composite(im.convert("RGBA"))
    return out


def portrait_sheet(ids):
    """Por columna un tipo: natural, familia azul, familia verde, cara de 32 (×2) y de 32 real; con su nombre."""
    W, gap = 64, 4
    sheet = Image.new("RGBA", (len(ids) * (W + gap), 4 * (W + gap) + 32 + gap), BG + (255,))
    for c, pid in enumerate(ids):
        x = c * (W + gap)
        k = Image.open(os.path.join(PORTRAITS, pid + ".png")).convert("RGBA")
        n = Image.open(os.path.join(PROD, "retratos", "natural", pid + ".png")).convert("RGBA")
        n32 = Image.open(os.path.join(PROD, "retratos", "natural", pid + "_32.png")).convert("RGBA")
        sheet.alpha_composite(n, (x, 0))
        sheet.alpha_composite(pg.unkey(k, FAMILY_B), (x, W + gap))
        sheet.alpha_composite(pg.unkey(k, FAMILY_C), (x, 2 * (W + gap)))
        sheet.alpha_composite(n32.resize((64, 64), Image.NEAREST), (x, 3 * (W + gap)))
        sheet.alpha_composite(n32, (x + 16, 4 * (W + gap)))
    return sheet


CSS = """body{background:#1a1209;color:#ece4d2;font:14px/1.45 system-ui,sans-serif;margin:24px;max-width:1600px}
h1{color:#f2d880} h2{color:#c8a84e;border-bottom:1px solid #8a7032;padding-bottom:4px;margin-top:36px}
h3{color:#a89878;font-size:13px;font-weight:600;margin:16px 0 6px}
.v{background:#2a1f14;border-left:3px solid #c8a84e;padding:8px 12px}
.row{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end;margin:6px 0}
figure{margin:0} figcaption{font-size:11px;color:#a89878;max-width:520px;overflow-wrap:anywhere}
img.px{image-rendering:pixelated;display:block}
table{border-collapse:collapse} td,th{border:1px solid #5c3a1e;padding:3px 10px}
code{color:#f2d880}"""


def page(title, intro, body):
    return (f"<!doctype html><html lang='es'><meta charset='utf-8'><title>{html.escape(title)}</title>"
            f"<style>{CSS}</style><h1>{html.escape(title)}</h1>{intro}{body}</html>")


def spend():
    rows = [r for r in json.load(open(LEDGER)) if r.get("tanda") == "produccion"]
    by = {}
    for r in rows:
        k = r["pieza"] + (" · image2pixel" if "image2pixel" in r["modelo"] else " · nano-banana-2")
        by[k] = by.get(k, 0) + r["usd"]
    total = sum(by.values())
    t = "".join(f"<tr><td>{html.escape(k)}</td><td>{v:.3f}</td></tr>" for k, v in sorted(by.items()))
    return total, f"<table><tr><th>Partida</th><th>USD</th></tr>{t}<tr><th>Total</th><th>{total:.3f}</th></tr></table>"


def retratos(total, table):
    ids = sorted(f[:-4] for f in os.listdir(PORTRAITS) if f.endswith(".png") and not f.endswith("_32.png"))
    body = ["<h2>Rejillas crudas y su mapa de regiones</h2>"]
    cells = []
    for g in fr.GRIDS:
        src = os.path.join(PROD, "retratos", "crudo", g + ".png")
        if os.path.exists(src):
            pair = Image.new("RGB", (240, 120))
            pair.paste(Image.open(src).convert("RGB").resize((120, 120)), (0, 0))
            pair.paste(Image.open(os.path.join(PROD, "retratos", "crudo", g + "_mascara.png")).convert("RGB")
                       .resize((120, 120)), (120, 0))
            cells.append(tag(pair, 1, g, jpeg=True))
    body.append(row(cells))
    for title, prefix in GROUPS:
        mine = sorted([i for i in ids if (i.startswith(prefix) if prefix else i in fr.OWN_CLOTHES)], key=order)
        if not mine:
            continue
        body.append(f"<h3>{html.escape(title)} · {len(mine)}</h3>")
        body.append(row([tag(portrait_sheet(mine), 2, " · ".join(mine))]))
    flat = [i for i in ("artisan_adult_m", "townsfolk_adult_f_1", "rival_adult_m_4", "scholar_elder_m", "priest")
            if i in ids]
    strip = Image.new("RGBA", (len(flat) * 68, 64), BG + (255,))
    for c, pid in enumerate(flat):
        strip.alpha_composite(pg.unkey(Image.open(os.path.join(PORTRAITS, pid + ".png")).convert("RGBA"), None),
                              (c * 68, 0))
    body.append("<h3>Regiones codificadas: pelo magenta, piel amarilla, ropa principal cian y secundaria verde</h3>")
    body.append(row([tag(strip, 3, " · ".join(flat))]))
    intro = (f"<p>2026-11-03 · rama <code>arte-fal</code> · <b>{len(ids)} retratos</b> en "
             f"<code>assets/art/portraits/</code> (64 busto y <code>_32</code> cara), estado «sprite», sin cablear. "
             f"Gasto de la tanda <b>{total:.2f} USD</b> de 8.</p>{table}"
             "<p class='v'>Cada columna es un <b>tipo de personaje</b>. De arriba abajo: natural; con dos familias "
             "más (el shader de identidad cambia pelo, piel y los dos colores de ropa, GDD 4.10.9); la cara de 32 "
             "ampliada ×2; y la cara de 32 a tamaño real. Hoja ampliada ×2. Fondo transparente: lo pone el marco. "
             "Los cargos y únicos solo cambian pelo y piel.</p>")
    return page("Arte fal · retratos (producción)", intro, "".join(body)), len(ids)


def ilustraciones(kinds, title, total, table):
    allids = list(fi.PIECES) + list(fi.FROM_PILOT)
    body, n = [], 0
    for sect, prefix in kinds:
        mine = sorted(i for i in allids if i.startswith(prefix) and os.path.exists(os.path.join(ILLUS, i + ".png")))
        if not mine:
            continue
        n += len(mine)
        body.append(f"<h2>{html.escape(sect)} · {len(mine)}</h2>")
        for i in mine:
            im = Image.open(os.path.join(ILLUS, i + ".png")).convert("RGB")
            if prefix == "screen_":
                prev = os.path.join(PROD, "ilustraciones", "vista", i + "_con_logo.png")
                src = Image.open(prev) if os.path.exists(prev) else im
                half = src.convert("RGB").resize((480, 270), Image.NEAREST)
                cap = f"{i} · 960×540 (480×270 ×2)" + (" · con el logotipo del kit" if os.path.exists(prev) else "")
                body.append(row([tag(half, 2, cap)]))
            else:
                cells = [tag(im, 2, f"{i} · 240×135 ×2"), tag(im, 1, "real")]
                small = os.path.join(ILLUS, i + "_192.png")
                if os.path.exists(small):
                    cells.append(tag(Image.open(small), 1, "192×108 (aviso)"))
                body.append(row(cells))
    intro = (f"<p>2026-11-03 · rama <code>arte-fal</code> · <b>{n}</b> piezas en "
             f"<code>assets/art/illustrations/</code>, estado «sprite», sin cablear. Gasto de la tanda "
             f"<b>{total:.2f} USD</b> de 8.</p>{table}")
    return page(title, intro, "".join(body)), n


def publish(title, html_page, description):
    port = os.environ.get("GRIMOIRE_PORT", "4317")
    ws = os.environ.get("GRIMOIRE_WORKSPACE", os.path.expanduser("~/.grimoire/workspace"))
    with open(os.path.join(ws, ".runtime", "auth", "token")) as f:
        tok = f.read().strip()
    thread = os.environ.get("GRIMOIRE_THREAD_ID", "th_01m6he5ytc9e1bm7hf78")
    args = {"title": title, "html": html_page, "description": description, "threadId": thread}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/api/cmd/artifact.create",
                                 data=json.dumps({"args": args}).encode(), method="POST",
                                 headers={"authorization": "Bearer " + tok, "content-type": "application/json",
                                          "x-grimoire-source": "agent", "x-grimoire-thread": thread})
    res = json.load(urllib.request.urlopen(req))
    return (res.get("result") or res).get("id") if isinstance(res, dict) else res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--publicar", action="store_true")
    a = ap.parse_args()
    total, table = spend()
    pages = []
    p, n = retratos(total, table)
    pages.append(("retratos", "Arte fal · retratos (producción)", p, f"GuildMaster · {n} retratos de tipo de "
                  f"personaje con fal, con colores de familia. {total:.2f} USD de 8."))
    p, n = ilustraciones([("Eventos globales (data/events.json)", "event_"), ("Estaciones", "season_"),
                          ("Cartas", "card_")], "Arte fal · eventos, estaciones y cartas (producción)", total, table)
    pages.append(("ilustraciones", "Arte fal · eventos, estaciones y cartas (producción)", p,
                  f"GuildMaster · {n} ilustraciones a 240×135 y 192×108 con fal."))
    p, n = ilustraciones([("Pantallas", "screen_")], "Arte fal · pantallas (producción)", total, table)
    pages.append(("pantallas", "Arte fal · pantallas (producción)", p,
                  f"GuildMaster · {n} fondos de pantalla a 960×540 con fal."))
    for key, title, html_page, desc in pages:
        out = os.path.join(PROD, f"galeria_{key}.html")
        with open(out, "w") as f:
            f.write(html_page)
        size = len(html_page.encode())
        print(out, round(size / 1024), "KB")
        if size > 990_000:
            print("  ! pasa de 1 MB: no se puede publicar")
            continue
        if a.publicar:
            print("  artifact:", publish(title, html_page, desc))


if __name__ == "__main__":
    main()
