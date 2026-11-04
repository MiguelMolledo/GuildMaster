#!/usr/bin/env python3
"""Piezas del mapa regional (docs/gdd/09b_region.md §9b.5) con fal: la ficha de la familia que viaja y el carro de
caravana, a la densidad del pergamino (assets/art/region/valldaura_map.png está pintado a 480×270 y doblado ×2: cada
píxel de arte son 2×2 de pantalla). Una rejilla 2×2 con nano-banana-2/edit (ref: el pergamino), cada pieza dibujada en
una rejilla de 32; image2pixel a escala 16, contorno oscuro y doblado ×2.

La ficha lleva la ropa de la familia codificada como los personajes (alfa 254, azul 150 = color principal, 200 =
secundario; brillo en el rojo): se pinta con game/visuals/characters/identity_swap.gdshader y los colores de la familia.

Salida: assets/art/region/family_token.png (y _shield, variante), caravan.png (y _cart, variante), todas ×2.
Uso: FAL_TANDA=duelo_region python3 tools/art/fal_region_piezas.py gen|proc
"""
import colorsys
import os
import subprocess
import sys
from types import SimpleNamespace

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fal_iconos as fic  # noqa: E402
import fal_procesar as fp  # noqa: E402
import fal_rutas as fr_  # noqa: E402

ROOT = fr_.ROOT
P = fr_.produccion("region_piezas")
OUT = os.path.join(ROOT, "assets", "art", "region")
MAP = os.path.join(OUT, "valldaura_map.png")
CELLS = ["family_token", "family_token_shield", "caravan", "caravan_cart"]
KEYED = {"family_token", "family_token_shield"}
PROMPT = ("The attached image is the illustrated parchment map of our medieval game's region, in 16-bit pixel art. "
          "Create ONE square image that is a 2x2 grid of four small game pieces to be placed ON this map, in exactly "
          "its painted pixel-art style, palette and light, each centred in its own cell on a plain flat white "
          "background, drawn on a 32x32 pixel grid (every art pixel is a 16x16 block of its 512x512 cell), with a "
          "1-pixel dark brown outline. Top-left: a family banner marker, a short wooden pole stuck in a small earth "
          "mound with a swallow-tailed cloth banner, the cloth in deep red with one mustard gold stripe. Top-right: "
          "the same pole holding a heraldic shield, deep red with a mustard gold chevron. Bottom-left: an ox-drawn "
          "covered merchant wagon, side view facing right, cream canvas top and brown wood. Bottom-right: a small "
          "two-wheeled cart pulled by a mule, loaded with crates and a barrel, side view facing right. No text, no "
          "letters, no grid lines, no shadow on the background.")


def gen():
    raw = os.path.join(P, "crudo", "piezas.png")
    if os.path.exists(raw):
        return
    ref = os.path.join(P, "ref_mapa.png")
    os.makedirs(P, exist_ok=True)
    Image.open(MAP).convert("RGB").resize((960, 540), Image.NEAREST).save(ref)
    cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "region_piezas",
           "--aspect", "1:1", "--name", "piezas", "--ref", ref, "--prompt", PROMPT]
    if subprocess.run(cmd, cwd=ROOT).returncode:
        sys.exit(1)


def key_family(im):
    """Rojo de la tela -> color principal (150) y dorado -> secundario (200), con su brillo relativo."""
    im = im.copy()
    px = im.load()
    regions = {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if not a:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            h *= 360
            if s > 0.45 and v > 0.25 and (h < 15 or h > 340):
                regions[(x, y)] = 3
            elif s > 0.45 and v > 0.4 and 30 <= h <= 60:
                regions[(x, y)] = 4
    lums = {k: sorted(0.299 * px[q][0] + 0.587 * px[q][1] + 0.114 * px[q][2] for q, kk in regions.items() if kk == k)
            for k in (3, 4)}
    ref = {k: (v[len(v) // 2] if v else 128.0) for k, v in lums.items()}
    for (x, y), k in regions.items():
        r, g, b, a = px[x, y]
        shade = min(2.0, 1.0 + ((0.299 * r + 0.587 * g + 0.114 * b) / max(1.0, ref[k]) - 1.0) * 0.8)
        px[x, y] = (int(round(shade * 127.5)), 0, k * 50, 254)
    return im, len(regions)


def proc():
    raw = os.path.join(P, "crudo", "piezas.png")
    im = Image.open(raw).convert("RGBA").resize((1024, 1024))
    os.makedirs(OUT, exist_ok=True)
    for k, name in enumerate(CELLS):
        cell = im.crop(((k % 2) * 512, (k // 2) * 512, (k % 2 + 1) * 512, (k // 2 + 1) * 512))
        keyed = fp.key_background(cell, "white", 28)
        src = os.path.join(P, "celdas", name + ".png")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        keyed.save(src)
        dst = os.path.join(P, "i2p", name + "_s16.png")
        if not os.path.exists(dst):
            import fal_piloto
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            fal_piloto.pixel(SimpleNamespace(piece="region_piezas", src=src, dst=dst, colors=16, scale=16, palette="",
                                             transparent=True))
        up = Image.open(dst).convert("RGBA")
        nat = up.resize((up.width // 16, up.height // 16), Image.NEAREST)
        nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
        c = nat.crop(nat.getchannel("A").getbbox())
        c = fic.outline(c)
        os.makedirs(os.path.join(P, "natural"), exist_ok=True)
        c.resize((c.width * 2, c.height * 2), Image.NEAREST).save(os.path.join(P, "natural", name + ".png"))
        n_key = 0
        if name in KEYED:
            c, n_key = key_family(c)
        c.resize((c.width * 2, c.height * 2), Image.NEAREST).save(os.path.join(OUT, name + ".png"))
        print(f"{name}: {c.width}×{c.height} de arte -> {c.width * 2}×{c.height * 2} en el mapa"
              + (f" · {n_key} px con colores de familia" if name in KEYED else ""))


def main():
    {"gen": gen, "proc": proc}[sys.argv[1] if len(sys.argv) > 1 else "proc"]()


if __name__ == "__main__":
    main()
