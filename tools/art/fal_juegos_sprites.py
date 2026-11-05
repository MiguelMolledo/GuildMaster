#!/usr/bin/env python3
"""Piezas de los minijuegos (docs/gdd/04f_vida_y_fiestas.md §4.26), de perfil mirando al este, a su tamaño de
pantalla (1:1), en assets/art/ui/games/<juego>/:

- joust/horse.png (48×32): caballo de justa con gualdrapa y jinete con la lanza en ristre; joust/horse_fallen.png
  (48×32): el caballo sin jinete y el jinete en el suelo.
- bulls/bull.png y bulls/bull_charge.png (36×24): el toro, y el toro embistiendo con la cabeza baja.
- race/horse_run.png (112×18): el caballo al galope con jinete, tira de 4 fotogramas de 28×18; race/horse.png es el
  primer fotograma suelto (el tablero de hoy dibuja horse.png a 28×18). La ropa del jinete va en gris neutro (r=g=b)
  para teñirla por código.

Son sprites de la pantalla del minijuego (fal); los animales del mundo esperan a PixelLab.
fal nano-banana-2/edit con una referencia (6 props del juego ×4), rejillas 2×2: bloques de 8 (rejilla de 64) para la
justa y los toros, de 16 (rejilla de 32) para el galope; image2pixel a esa escala.

Uso: FAL_TANDA=h16 python3 tools/art/fal_juegos_sprites.py gen|proc
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
import fal_props_fiesta as fpf  # noqa: E402
import fal_rutas as fr_  # noqa: E402

ROOT = fr_.ROOT
P = fr_.produccion("juegos_sprites")
OUT = os.path.join(ROOT, "assets", "art", "ui", "games")
# id -> (lienzo, descripción)
PIECES = {
    "joust_horse": ((48, 32), "a jousting warhorse with a long blue and gold caparison down to its legs, walking, "
                              "carrying an armoured knight with a plumed helm who holds a long striped lance couched "
                              "level pointing forward to the right"),
    "joust_fallen": ((48, 32), "the same caparisoned jousting horse standing without its rider, and the armoured knight "
                               "fallen flat on his back on the ground in front of it, his broken lance beside him"),
    "bull": ((36, 24), "a big black fighting bull standing, with pale curved horns, sturdy body"),
    "bull_charge": ((36, 24), "the same black fighting bull charging, head lowered with the horns forward, front legs "
                              "stretched, a puff of dust behind"),
    "race_1": ((28, 18), "frame 1 of a gallop: a brown racing horse with a small rider in a plain light grey tunic "
                         "and grey cap leaning forward; all four legs gathered under the body"),
    "race_2": ((28, 18), "frame 2 of the same gallop: the same horse and grey rider; front legs reaching forward, back "
                         "legs pushing back"),
    "race_3": ((28, 18), "frame 3 of the same gallop: the same horse and grey rider; fully stretched, front legs far "
                         "forward and back legs far back"),
    "race_4": ((28, 18), "frame 4 of the same gallop: the same horse and grey rider; front legs coming down under the "
                         "chest, back legs swinging forward"),
}
GRIDS = {"s1": (8, ["joust_horse", "joust_fallen", "bull", "bull_charge"]),
         "s2": (16, ["race_1", "race_2", "race_3", "race_4"])}
DEST = {"joust_horse": "joust/horse.png", "joust_fallen": "joust/horse_fallen.png", "bull": "bulls/bull.png",
        "bull_charge": "bulls/bull_charge.png"}
POS = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]


def prompt(block, ids):
    n = 512 // block
    what = " ".join(f"{pos}: {PIECES[i][1]} (about {PIECES[i][0][0]}x{PIECES[i][0][1]} art pixels)."
                    for pos, i in zip(POS, ids))
    same = (" The four cells are consecutive animation frames of ONE horse and rider: identical size, colours and "
            "position in the cell, only the legs and a slight bob change." if ids[0].startswith("race") else "")
    return ("The attached image shows prop sprites from our medieval town game, enlarged 4x, for the style. Create "
            "ONE square image that is a 2x2 grid of NEW sprites for a minigame screen in exactly this pixel art style: "
            "same dark 1-pixel outline, same warm palette and shading with light from the top-left. Every sprite is "
            "seen exactly from the side, in profile, facing RIGHT, standing on the bottom of its cell, centred, on a "
            f"plain flat white background. Each sprite is drawn on a {n}x{n} pixel grid (every art pixel is a "
            f"{block}x{block} block of its 512x512 cell). " + what + same +
            " No text, no letters, no ground, no grid lines, no shadow on the background.")


def gen():
    ref = fpf.ref_sheet()
    for g, (block, ids) in GRIDS.items():
        if os.path.exists(os.path.join(P, "crudo", g + ".png")):
            continue
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece",
               "juegos_sprites", "--aspect", "1:1", "--name", g, "--ref", ref, "--prompt", prompt(block, ids)]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


def grey_rider(im):
    """La ropa del jinete en gris neutro: los píxeles claros y poco saturados pasan a r=g=b (se tiñen por código)."""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if not a:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < 0.22 and v > 0.35:
                lum = int(0.299 * r + 0.587 * g + 0.114 * b)
                px[x, y] = (lum, lum, lum, a)
    return im


def piece(g, block, k, pid, im):
    import fal_fachadas
    cell = im.crop(((k % 2) * 512, (k // 2) * 512, (k % 2 + 1) * 512, (k // 2 + 1) * 512))
    keyed = fpf.no_grid_lines(fal_fachadas.holes(fp.key_background(cell, "white", 28)))
    src = os.path.join(P, "celdas", f"{g}_{pid}.png")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    keyed.save(src)
    dst = os.path.join(P, "i2p", f"{g}_{pid}_s{block}.png")
    if not os.path.exists(dst):
        import fal_piloto
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fal_piloto.pixel(SimpleNamespace(piece="juegos_sprites", src=src, dst=dst, colors=24, scale=block,
                                         palette="", transparent=True))
    up = Image.open(dst).convert("RGBA")
    nat = up.resize((up.width // block, up.height // block), Image.NEAREST)
    nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
    c = fic.outline(nat.crop(nat.getchannel("A").getbbox()))
    w, h = PIECES[pid][0]
    if c.width > w or c.height > h:
        kk = min(w / c.width, h / c.height)
        c = c.resize((max(1, int(c.width * kk)), max(1, int(c.height * kk))), Image.NEAREST)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.alpha_composite(c, ((w - c.width) // 2, h - c.height))
    return canvas, c.size


def proc():
    for g, (block, ids) in GRIDS.items():
        raw = os.path.join(P, "crudo", g + ".png")
        if not os.path.exists(raw):
            print("falta", raw)
            continue
        im = Image.open(raw).convert("RGBA").resize((1024, 1024))
        frames = []
        for k, pid in enumerate(ids):
            out, size = piece(g, block, k, pid, im)
            if pid.startswith("race"):
                frames.append(grey_rider(out))
            else:
                dst = os.path.join(OUT, DEST[pid])
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                out.save(dst)
            print(f"{pid}: {size[0]}×{size[1]} en {out.width}×{out.height}")
        if frames:
            d = os.path.join(OUT, "race")
            os.makedirs(d, exist_ok=True)
            strip = Image.new("RGBA", (28 * len(frames), 18), (0, 0, 0, 0))
            for i, f in enumerate(frames):
                strip.alpha_composite(f, (28 * i, 0))
            strip.save(os.path.join(d, "horse_run.png"))
            frames[0].save(os.path.join(d, "horse.png"))
            print(f"race/horse_run.png {strip.width}×18 y race/horse.png (fotograma 1)")


def main():
    {"gen": gen, "proc": proc}[sys.argv[1] if len(sys.argv) > 1 else "proc"]()


if __name__ == "__main__":
    main()
