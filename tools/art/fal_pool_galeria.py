#!/usr/bin/env python3
"""Galería del pool de retratos (assets/art/portraits/index.json): una hoja por sexo y tipo (filas por edad, columnas
por cara), natural, y una fila de muestra teñida con otra familia. Las hojas se reparten en páginas de menos de 1 MB
(límite del servidor de Grimoire). Uso: python3 tools/art/fal_pool_galeria.py [--publicar]
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import personajes_guild as pg  # noqa: E402
from fal_produccion_galeria import BG, FAMILY_B, page, publish, row, tag  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import fal_rutas as fr_  # noqa: E402  (crudos fuera del repo)
PORT = os.path.join(ROOT, "assets", "art", "portraits")
NAT = fr_.produccion("pool", "natural")
AGES = ["child", "youth", "adult", "mature", "elder"]
LIMIT = 900_000


def natural(e):
    p = os.path.join(NAT, e["id"] + ".png")
    if os.path.exists(p):
        return Image.open(p).convert("RGBA")
    return pg.unkey(Image.open(os.path.join(PORT, e["file"])).convert("RGBA"),
                    {1: (92, 60, 34), 2: (224, 181, 140), 3: (140, 46, 46), 4: (200, 168, 80)})


def sheet(es):
    by_age = {a: sorted([e for e in es if e["age"] == a], key=lambda e: e["id"]) for a in AGES}
    rows = [a for a in AGES if by_age[a]]
    cols = max(len(v) for v in by_age.values())
    W = 66
    im = Image.new("RGBA", (cols * W + 4, len(rows) * (W + 46) + 4), BG + (255,))
    d = ImageDraw.Draw(im)
    for r, a in enumerate(rows):
        y = r * (W + 46)
        d.text((2, y), f"{a} · {len(by_age[a])}", fill=(200, 168, 78))
        for c, e in enumerate(by_age[a]):
            im.alpha_composite(natural(e), (c * W + 2, y + 10))
            face = Image.open(os.path.join(PORT, e["face"])).convert("RGBA")
            im.alpha_composite(pg.unkey(face, FAMILY_B) if "skin" in e["recolor"] else face, (c * W + 18, y + 75))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--publicar", action="store_true")
    a = ap.parse_args()
    idx = json.load(open(os.path.join(PORT, "index.json")))
    ps = idx["portraits"]
    blocks = []
    for t in idx["types"]:
        for sex in ("m", "f"):
            es = [e for e in ps if e["type"] == t and e["sex"] == sex]
            if es:
                cap = f"{'Hombres' if sex == 'm' else 'Mujeres'} · {t} · {len(es)}"
                blocks.append((cap, f"<h3>{cap}</h3>" + row([tag(sheet(es), 2, "natural ×2; debajo, la cara de 32 "
                                                                     "teñida con otra familia")])))
    pages, cur, size = [], [], 0
    for cap, html_block in blocks:
        b = len(html_block.encode())
        if cur and size + b > LIMIT:
            pages.append(cur)
            cur, size = [], 0
        cur.append((cap, html_block))
        size += b
    pages.append(cur)
    intro = (f"<p>Pool de retratos · <code>assets/art/portraits/index.json</code> versión {idx['version']} · "
             f"<b>{len(ps)} retratos</b> en {len({(e['sex'], e['age'], e['type']) for e in ps})} combinaciones. "
             "Fondo transparente (aquí, el del marco). Formato y reglas: <code>assets/art/portraits/README.md"
             "</code>.</p>")
    for i, pg_ in enumerate(pages, 1):
        title = f"Arte fal · pool de retratos ({i}/{len(pages)})"
        html_page = page(title, intro + f"<p class='v'>{' · '.join(c for c, _ in pg_)}</p>",
                         "".join(h for _, h in pg_))
        out = fr_.produccion(f"galeria_pool_{i}.html")
        with open(out, "w") as f:
            f.write(html_page)
        print(out, round(len(html_page.encode()) / 1024), "KB")
        if a.publicar:
            print("  artifact:", publish(title, html_page, f"GuildMaster · pool de retratos, página {i} de "
                                                           f"{len(pages)}: " + ", ".join(c for c, _ in pg_)))


if __name__ == "__main__":
    main()
