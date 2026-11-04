#!/usr/bin/env python3
"""Iconos de 32 con fal (2026-11-03): los de objeto en greybox o que faltan (assets/inventario.json), los de UI que
faltan según docs/ui/00_lenguaje_visual.md §7 y las 4 burbujas de emoción (GDD 4.11.5).

Rejillas 2×2 con nano-banana-2/edit y una sola referencia: 8 iconos buenos del juego ampliados ×4 (las burbujas: las
6 burbujas del juego). Cada icono se pide sobre una rejilla de 32 (un píxel de arte = un bloque de 16 de la celda de
512), con más volumen y contorno oscuro de 1 px como los de Guild Renew. Proceso: fondo blanco fuera, image2pixel a
escala 16 (sale a 32×32), contorno oscuro donde falte y la versión de 16 con la half() de derivar_guild.py.

Uso: FAL_TANDA=extra python3 tools/art/fal_iconos.py gen|proc [--solo id,id]
"""
import argparse
import os
import subprocess
import sys
from types import SimpleNamespace

from PIL import Image

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import derivar_guild as dg  # noqa: E402
import fal_procesar as fp  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import fal_rutas as fr_  # noqa: E402  (crudos fuera del repo)
P = fr_.produccion("iconos")
ART = os.path.join(ROOT, "assets", "art")
REF_ITEMS = ["armor", "barrel", "iron_ingot", "planks", "wood", "stone", "work_clothes", "sword"]
REF_BUBBLES = ["chat", "dice", "rest", "shop", "think", "wave"]

# id -> (ruta de 32 relativa a assets/art, descripción)
ICONS = {
    "saw": ("icons/saw.png", "a carpenter's hand saw, wooden handle with a hole, long toothed steel blade, diagonal"),
    "steel": ("icons/steel.png", "a polished steel bar ingot, cool bluish grey, a bright shine streak; clearly "
                                 "lighter and bluer than a dark iron ingot"),
    "chest": ("icons/chest.png", "a wooden chest with a domed lid, iron bands and a brass lock, three-quarter view"),
    "cabinet": ("icons/cabinet.png", "a tall wooden cabinet with two doors and brass knobs, three-quarter view"),
    "cart_wheel": ("icons/cart_wheel.png", "a spoked wooden cart wheel with an iron rim, seen slightly from the side"),
    "ashlar": ("icons/ashlar.png", "a single squared ashlar stone block of light sandstone, chisel marks, "
                                   "three-quarter view"),
    "grindstone": ("icons/grindstone.png", "a round sandstone grinding wheel on a small wooden frame with a crank "
                                           "handle"),
    "trough": ("icons/trough.png", "a rectangular carved stone trough filled with blue water, three-quarter view"),
    "millstone": ("icons/millstone.png", "a big round flat millstone with a square hole in the centre and carved "
                                         "radial grooves, three-quarter view"),
    "statue": ("icons/statue.png", "a small carved stone statue of a robed saint with hands joined, on a square "
                                   "pedestal, using the full height of the icon"),
    "gavel": ("ui/icons/icon_gavel.png", "a judge's wooden gavel lying diagonally on a small round wooden block"),
    "ballot_box": ("ui/icons/icon_ballot_box.png", "a wooden ballot box with a slot on the lid and a round wooden "
                                                   "token dropping into it"),
    "reputation": ("ui/icons/icon_reputation.png", "a golden laurel wreath around a small bright star"),
    "menu": ("ui/icons/icon_menu.png", "an iron cogwheel with eight teeth and a hole in the middle"),
    "save": ("ui/icons/icon_save.png", "a closed leather-bound ledger with a red wax seal on the cover"),
    "load": ("ui/icons/icon_load.png", "an open book with cream pages and a red ribbon bookmark"),
    "parcels": ("ui/icons/icon_parcels.png", "a small parchment map showing a square plot of land outlined in red "
                                             "with a tiny red flag on it"),
    "emotion_grateful": ("ui/bubbles/emotion_grateful.png", "speech bubble with a small red heart inside"),
    "emotion_offended": ("ui/bubbles/emotion_offended.png", "speech bubble with a small grey storm cloud inside"),
    "emotion_angry": ("ui/bubbles/emotion_angry.png", "speech bubble with a red anger symbol (four curved red marks "
                                                      "like a cross-popping vein) inside"),
    "emotion_scared": ("ui/bubbles/emotion_scared.png", "speech bubble with a blue sweat drop and a small white "
                                                        "exclamation mark inside"),
}
# Duelo (docs/gdd/04e_combate.md §4e.8, docs/ui/mecanicas/combate.md §8): assets/art/ui/icons/duel/icon_<acción>.png
DUEL = {
    "duel_strike": ("ui/icons/duel/icon_strike.png", "a sword slashing diagonally down with a short motion arc"),
    "duel_parry": ("ui/icons/duel/icon_parry.png", "a round wooden buckler shield with an iron boss blocking a sword "
                                                  "blade, a small spark where they meet"),
    "duel_feint": ("ui/icons/duel/icon_feint.png", "a sword drawn with a curved dotted arrow looping back around it, "
                                                  "a deceptive move"),
    "duel_surrender": ("ui/icons/duel/icon_surrender.png", "a small white cloth flag on a short wooden stick"),
    "duel_auto": ("ui/icons/duel/icon_auto.png", "a brass hourglass with two small crossed swords behind it"),
    "duel_breath": ("ui/icons/duel/icon_breath.png", "a puff of pale blue breath with two curling wind lines"),
    "duel_touch": ("ui/icons/duel/icon_touch.png", "a red drop of blood above a short sword tip"),
    "duel_challenge": ("ui/icons/duel/icon_challenge.png", "a thrown leather gauntlet glove lying on the ground"),
}
# Región y viajes (docs/gdd/09b_region.md §9b.5): assets/art/ui/icons/icon_<nombre>.png
REGION = {
    "tariff": ("ui/icons/icon_tariff.png", "a toll: a small striped wooden barrier with a stack of gold coins"),
    "treaty": ("ui/icons/icon_treaty.png", "a rolled parchment treaty with a red wax seal and a ribbon"),
    "caravan": ("ui/icons/icon_caravan.png", "a covered merchant wagon with a canvas top and two wooden wheels, "
                                             "side view"),
    "city_reputation": ("ui/icons/icon_city_reputation.png", "a small stone town gate tower with a gold star above "
                                                             "it"),
}
ICONS.update(DUEL)
ICONS.update(REGION)

GRIDS = {"i1": ["saw", "steel", "chest", "cabinet"], "i2": ["cart_wheel", "ashlar", "grindstone", "trough"],
         "i3": ["millstone", "statue", "gavel", "ballot_box"], "i4": ["reputation", "menu", "save", "load"],
         "b1": ["emotion_grateful", "emotion_offended", "emotion_angry", "emotion_scared"],
         "i5": ["parcels"],
         "i6": ["grindstone"],
         "d1": ["duel_strike", "duel_parry", "duel_feint", "duel_surrender"],
         "d2": ["duel_auto", "duel_breath", "duel_touch", "duel_challenge"],
         "r1": ["tariff", "treaty", "caravan", "city_reputation"],
         "r2": ["tariff", "duel_breath"]}  # repetidas: el arancel no se leía y el aliento era una mancha  # repetida: la de i2 salió ilegible (la última rejilla manda)
REDO_2 = {
    "tariff": "a toll gate: a horizontal red and white striped wooden barrier pole on a post, with a small stack "
              "of gold coins in front of it",
    "duel_breath": "three curved pale blue wind swirls, like a gust of breath, clearly drawn lines",
}
REDO = {"grindstone": "an upright round grey grinding stone wheel mounted on its axle in a simple wooden A-frame "
                      "stand, a crank handle on the axle, seen from the side, clearly a wheel"}
POS = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]


def ref_sheet(kind):
    names, folder = (REF_BUBBLES, "ui/bubbles") if kind == "b" else (REF_ITEMS, "icons")
    cols = 3 if kind == "b" else 4
    sheet = Image.new("RGBA", (cols * 128, 2 * 128), (255, 255, 255, 255))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(ART, folder, n + ".png")).convert("RGBA").resize((128, 128), Image.NEAREST)
        sheet.alpha_composite(im, ((i % cols) * 128, (i // cols) * 128))
    p = os.path.join(P, "ref_" + kind + ".png")
    os.makedirs(P, exist_ok=True)
    sheet.convert("RGB").save(p)
    return p


def prompt(ids, bubbles):
    what = " ".join(f"{pos}: {REDO.get(i, ICONS[i][1]) if len(ids) == 1 else REDO_2.get(i, ICONS[i][1]) if len(ids) == 2 else ICONS[i][1]}." for pos, i in zip(POS, ids))
    if len(ids) < 4:
        what += " The other cells stay plain white."
    kind = "speech-bubble icons with a symbol" if bubbles else "item icons"
    return ("The attached image shows 32x32 pixel art " + kind + " from our medieval game, enlarged 4x. Create ONE "
            "square image that is a 2x2 grid of NEW icons in exactly this style. Each icon is drawn on a 32x32 pixel "
            "grid (every art pixel is a 16x16 block of its 512x512 cell), fills about 26 to 28 of the 32 pixels and "
            "is centred on a plain flat white background. A 1-pixel near-black dark brown outline around the whole "
            "silhouette; strong volume with a highlight from the top-left and shadow on the bottom-right, 3 to 4 "
            "tones per material, the same warm palette and level of detail as the reference. " + what +
            " No text, no letters, no grid lines, no drop shadow on the background.")


def gen(g):
    raw = os.path.join(P, "crudo", g + ".png")
    if os.path.exists(raw):
        return
    ref = ref_sheet(g[0])
    cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "iconos",
           "--aspect", "1:1", "--name", g, "--ref", ref, "--prompt", prompt(GRIDS[g], g.startswith("b"))]
    if subprocess.run(cmd, cwd=ROOT).returncode:
        sys.exit(1)


def outline(im):
    """Contorno de 1 px: los píxeles del borde de la silueta que no son oscuros se oscurecen (como Guild Renew)."""
    im = im.copy()
    px = im.load()
    w, h = im.size
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] < 128:
                continue
            if any(not (0 <= x + dx < w and 0 <= y + dy < h) or px[x + dx, y + dy][3] < 128
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge.append((x, y))
    for x, y in edge:
        r, g, b, a = px[x, y]
        if dg.lum((r, g, b)) > 60:
            px[x, y] = (int(r * 0.3) + 10, int(g * 0.25) + 8, int(b * 0.22) + 6, 255)
    return im


def proc(g, cell_ids):
    raw = os.path.join(P, "crudo", g + ".png")
    if not os.path.exists(raw):
        print("falta", raw)
        return
    im = Image.open(raw).convert("RGBA").resize((1024, 1024))
    for k, iid in enumerate(GRIDS[g]):
        if cell_ids and iid not in cell_ids:
            continue
        cell = im.crop(((k % 2) * 512, (k // 2) * 512, (k % 2 + 1) * 512, (k // 2 + 1) * 512))
        keyed = fp.key_background(cell, "white", 28)
        src = os.path.join(P, "celdas", f"{g}_{iid}.png")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        keyed.save(src)
        dst = os.path.join(P, "i2p", f"{g}_{iid}_s16.png")
        if not os.path.exists(dst):
            import fal_piloto
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            fal_piloto.pixel(SimpleNamespace(piece="iconos", src=src, dst=dst, colors=16, scale=16, palette="",
                                             transparent=True))
        up = Image.open(dst).convert("RGBA")
        nat = up.resize((up.width // 16, up.height // 16), Image.NEAREST)
        nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
        bb = nat.getchannel("A").getbbox()
        c = nat.crop(bb)
        if max(c.size) > 31:
            c = c.resize((min(31, c.width), min(31, c.height)), Image.NEAREST)
        out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        out.alpha_composite(c, ((32 - c.width) // 2, (32 - c.height) // 2))
        out = outline(out)
        rel = ICONS[iid][0]
        os.makedirs(os.path.join(P, "natural"), exist_ok=True)
        os.makedirs(os.path.dirname(os.path.join(ART, rel)), exist_ok=True)
        out.save(os.path.join(ART, rel))
        small = dg.half(out)
        small = dg.pad_to(small, 16, 16, anchor_bottom=False) if small.width <= 16 and small.height <= 16 else \
            small.resize((16, 16))
        d, f = os.path.split(rel)
        os.makedirs(os.path.join(ART, d, "small"), exist_ok=True)
        small.save(os.path.join(ART, d, "small", f))
        print("ok", iid, c.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["gen", "proc"])
    ap.add_argument("--solo", default="")
    a = ap.parse_args()
    ids = [x for x in a.solo.split(",") if x]
    for g in GRIDS:
        if a.cmd == "gen":
            if not ids or g in ids:
                gen(g)
        else:
            proc(g, ids)


if __name__ == "__main__":
    main()
