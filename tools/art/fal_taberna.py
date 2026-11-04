#!/usr/bin/env python3
"""Interior de la Taberna-Posada (docs/gdd/04f_vida_y_fiestas.md §4.27, §4.28.3) en assets/art/interiors/tavern/:
muebles con fal (nano-banana-2/edit, una referencia: el kit de la forja ×4, rejillas 2×2, cada pieza en una rejilla
de 64 = bloques de 8), suelo de tablas dibujado con Pillow (rombo 64×32 que tesela) y paredes copiadas de la
carpintería (32×52, las que ya encajan en la rejilla del interior). Cada mueble queda en su lienzo con los pies
abajo en el centro, como los de la forja (64×64 o 80×72).

Uso: FAL_TANDA=h16 python3 tools/art/fal_taberna.py gen|proc|suelo
"""
import os
import shutil
import subprocess
import sys
from types import SimpleNamespace

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fal_iconos as fic  # noqa: E402
import fal_procesar as fp  # noqa: E402
import fal_rutas as fr_  # noqa: E402

ROOT = fr_.ROOT
P = fr_.produccion("taberna")
OUT = os.path.join(ROOT, "assets", "art", "interiors", "tavern")
FORGE = os.path.join(ROOT, "assets", "art", "interiors", "forge")
# id -> (lienzo, descripción)
PIECES = {
    "bar": ((80, 72), "a long wooden tavern bar counter with two beer barrels with taps on it, clay jugs and mugs"),
    "table": ((64, 64), "a sturdy square wooden tavern table with two wooden mugs and a loaf of bread on it"),
    "bench": ((64, 64), "a long plain wooden bench"),
    "barrel": ((64, 64), "a big wooden wine barrel lying on its side on a wooden cradle, with a spigot"),
    "kitchen": ((64, 64), "a cooking hearth of stone with an iron cauldron hanging over a fire and a wooden shelf "
                          "with pots"),
    "fireplace": ((64, 64), "a stone fireplace with a warm crackling fire and a mantel"),
    "bed": ((80, 72), "a simple inn bed with a straw mattress, a wool blanket and a small chest at its foot"),
    "minstrel_corner": ((64, 64), "a minstrel's corner: a small low wooden stage with a stool, a lute leaning on it "
                                  "and a little drum"),
}
GRIDS = {"t1": ["bar", "table", "bench", "barrel"], "t2": ["kitchen", "fireplace", "bed", "minstrel_corner"]}
POS = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]


def ref_sheet():
    names = ["anvil", "counter", "furnace", "storage", "upg_dining", "upg_bunks"]
    sheet = Image.new("RGBA", (3 * 320, 2 * 320), (255, 255, 255, 255))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(FORGE, n + ".png")).convert("RGBA")
        im = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
        sheet.alpha_composite(im, ((i % 3) * 320 + (320 - im.width) // 2, (i // 3) * 320 + 320 - im.height))
    p = os.path.join(P, "ref_forja.png")
    os.makedirs(P, exist_ok=True)
    sheet.convert("RGB").save(p)
    return p


def prompt(ids):
    what = " ".join(f"{pos}: {PIECES[i][1]}." for pos, i in zip(POS, ids))
    return ("The attached image shows isometric 2:1 interior furniture sprites from our medieval game (a forge), "
            "enlarged 4x. Create ONE square image that is a 2x2 grid of four NEW pieces of furniture for a tavern-"
            "inn interior in exactly this style: same isometric 2:1 projection and camera, same dark 1-pixel "
            "outline, same warm palette and shading with light from the top-left. Each piece is drawn on a 64x64 "
            "pixel grid (every art pixel is an 8x8 block of its 512x512 cell), standing on the bottom of its cell, "
            "centred, on a plain flat white background, no floor tile under it. " + what +
            " No text, no letters, no grid lines, no shadow on the background.")


def gen():
    ref = ref_sheet()
    for g, ids in GRIDS.items():
        if os.path.exists(os.path.join(P, "crudo", g + ".png")):
            continue
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "taberna",
               "--aspect", "1:1", "--name", g, "--ref", ref, "--prompt", prompt(ids)]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


def proc():
    os.makedirs(OUT, exist_ok=True)
    for g, ids in GRIDS.items():
        raw = os.path.join(P, "crudo", g + ".png")
        if not os.path.exists(raw):
            print("falta", raw)
            continue
        im = Image.open(raw).convert("RGBA").resize((1024, 1024))
        for k, pid in enumerate(ids):
            cell = im.crop(((k % 2) * 512, (k // 2) * 512, (k % 2 + 1) * 512, (k // 2 + 1) * 512))
            keyed = fp.key_background(cell, "white", 28)
            import fal_fachadas
            keyed = fal_fachadas.holes(keyed)  # el blanco del fondo que queda encerrado (la boca del hogar)
            src = os.path.join(P, "celdas", pid + ".png")
            os.makedirs(os.path.dirname(src), exist_ok=True)
            keyed.save(src)
            dst = os.path.join(P, "i2p", pid + "_s8.png")
            if not os.path.exists(dst):
                import fal_piloto
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                fal_piloto.pixel(SimpleNamespace(piece="taberna", src=src, dst=dst, colors=24, scale=8, palette="",
                                                 transparent=True))
            up = Image.open(dst).convert("RGBA")
            nat = up.resize((up.width // 8, up.height // 8), Image.NEAREST)
            nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
            c = fic.outline(nat.crop(nat.getchannel("A").getbbox()))
            (w, h) = PIECES[pid][0]
            if c.width > w or c.height > h:
                k2 = min(w / c.width, h / c.height)
                c = c.resize((max(1, int(c.width * k2)), max(1, int(c.height * k2))), Image.NEAREST)
            canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            canvas.alpha_composite(c, ((w - c.width) // 2, h - c.height - 1))
            canvas.save(os.path.join(OUT, pid + ".png"))
            print(f"{pid}: {c.width}×{c.height} en {w}×{h}")


def floor():
    """Suelo de tablas: rombo 64×32 que tesela (las tablas van a lo largo de un eje del rombo)."""
    W, H = 64, 32
    tile = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    base = [(122, 82, 48), (110, 72, 42), (132, 90, 54), (116, 77, 45)]
    px = tile.load()
    for y in range(H):
        for x in range(W):
            # dentro del rombo
            if abs(x - 31.5) / 32 + abs(y - 15.5) / 16 > 1.0:
                continue
            u = (x / 2 + y)  # coordenada a lo largo de un eje isométrico
            v = (x / 2 - y)
            plank = int((v + 64) // 8) % 4
            c = base[plank]
            if int(v + 64) % 8 == 0:  # junta entre tablas
                c = (70, 44, 26)
            elif int(u + plank * 13) % 37 == 0:  # testa de una tabla
                c = (84, 54, 31)
            elif (x * 7 + y * 13) % 29 == 0:  # veta
                c = tuple(max(0, v2 - 10) for v2 in c)
            px[x, y] = c + (255,)
    tile.save(os.path.join(OUT, "floor.png"))
    for n in ("wall_ne", "wall_nw", "wall_door_ne", "wall_door_nw"):
        shutil.copy(os.path.join(ROOT, "assets", "art", "interiors", "carpentry", n + ".png"), os.path.join(OUT, n + ".png"))
    print("suelo de tablas 64×32 y paredes (copia de la carpintería)")


def main():
    {"gen": gen, "proc": proc, "suelo": floor}[sys.argv[1] if len(sys.argv) > 1 else "proc"]()


if __name__ == "__main__":
    main()
