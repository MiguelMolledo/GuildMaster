#!/usr/bin/env python3
"""Piezas de la «Forja viva» (docs/gdd/03b_diversion_y_ritmo.md §3b.2) en assets/art/ui/forge/:

- iron_<heat>.png: la barra de hierro en los 5 colores de calor (dark_red, cherry, orange, yellow, white) y en frío
  (iron_cold.png). fal dibuja la barra en frío; Pillow la recolorea con rampas fijas (el calor tiene que ser exacto
  y legible, no al gusto del modelo).
- anvil_strike_1..3.png: el yunque con el martillo en 3 golpes (arriba, a medio camino, golpe con chispas).
- hearth.png: la fragua con las brasas (fondo del paso «Calentar»).
- quench_water.png, quench_oil.png, quench_air.png: el cubo de agua (vapor), el de aceite (llama) y el soporte para
  enfriar al aire.
Todo en una rejilla de 64 (bloques de 8) con nano-banana-2/edit y una referencia (el kit de interior de la forja ×4).
Uso: FAL_TANDA=h16 python3 tools/art/fal_forja_viva.py gen|proc
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
import fal_taberna as ft  # noqa: E402

ROOT = fr_.ROOT
P = fr_.produccion("forja_viva")
OUT = os.path.join(ROOT, "assets", "art", "ui", "forge")
PIECES = {
    "iron_cold": "a straight bar of dark grey iron, a rough sword blank, lying diagonally, cold",
    "anvil_strike_1": "a black iron anvil on a tree stump with a smith's hammer held high above it, ready to strike",
    "anvil_strike_2": "the same black iron anvil on a tree stump with the hammer halfway down, motion lines",
    "anvil_strike_3": "the same black iron anvil on a tree stump with the hammer striking a glowing bar, bright "
                      "orange sparks flying",
    "hearth": "a smith's brick forge hearth full of glowing red and orange coals, bellows at the side",
    "quench_water": "a wooden bucket of water with white steam rising from it",
    "quench_oil": "an iron pot of dark golden oil with small flames licking the surface",
    "quench_air": "a small iron rack where a blade cools in the air, a faint heat shimmer",
}
GRIDS = {"g1": ["iron_cold", "anvil_strike_1", "anvil_strike_2", "anvil_strike_3"],
         "g2": ["hearth", "quench_water", "quench_oil", "quench_air"]}
# rampas de calor: oscuro, medio, claro, brillo (03b §3b.2: rojo oscuro, cereza, naranja, amarillo y blanco)
HEAT = {"dark_red": [(58, 10, 8), (110, 22, 14), (150, 36, 20), (178, 58, 30)],
        "cherry": [(96, 14, 12), (176, 30, 24), (222, 58, 40), (246, 104, 72)],
        "orange": [(140, 46, 8), (222, 104, 20), (250, 150, 40), (255, 196, 96)],
        "yellow": [(170, 104, 20), (242, 196, 52), (255, 230, 120), (255, 250, 200)],
        "white": [(214, 198, 170), (246, 238, 220), (255, 252, 244), (255, 255, 255)]}


def prompt(ids):
    what = " ".join(f"{pos}: {PIECES[i]}." for pos, i in zip(ft.POS, ids))
    return ("The attached image shows isometric interior sprites of a medieval forge from our game, enlarged 4x. "
            "Create ONE square image that is a 2x2 grid of four NEW pieces for a forging minigame in exactly this "
            "style: same dark 1-pixel outline, warm palette and shading with light from the top-left, three-quarter "
            "view. Each piece is drawn on a 64x64 pixel grid (every art pixel is an 8x8 block of its 512x512 cell), "
            "centred, on a plain flat white background. " + what +
            " No text, no letters, no grid lines, no shadow on the background.")


def gen():
    ref = ft.ref_sheet()
    for g, ids in GRIDS.items():
        if os.path.exists(os.path.join(P, "crudo", g + ".png")):
            continue
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece",
               "forja_viva", "--aspect", "1:1", "--name", g, "--ref", ref, "--prompt", prompt(ids)]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


def heat(im, ramp):
    """La barra en frío recoloreada: el contorno se queda, el resto toma la rampa por su brillo."""
    out = im.copy()
    px = out.load()
    lums = sorted(0.299 * r + 0.587 * g + 0.114 * b for r, g, b, a in im.getdata() if a and max(r, g, b) > 40)
    if not lums:
        return out
    lo, hi = lums[len(lums) // 10], lums[-1]
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if not a or max(r, g, b) <= 40:  # contorno
                continue
            t = (0.299 * r + 0.587 * g + 0.114 * b - lo) / max(1.0, hi - lo)
            c = ramp[min(3, max(0, int(t * 4)))]
            px[x, y] = c + (255,)
    return out


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
            src = os.path.join(P, "celdas", pid + ".png")
            os.makedirs(os.path.dirname(src), exist_ok=True)
            keyed.save(src)
            dst = os.path.join(P, "i2p", pid + "_s8.png")
            if not os.path.exists(dst):
                import fal_piloto
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                fal_piloto.pixel(SimpleNamespace(piece="forja_viva", src=src, dst=dst, colors=24, scale=8,
                                                 palette="", transparent=True))
            up = Image.open(dst).convert("RGBA")
            nat = up.resize((up.width // 8, up.height // 8), Image.NEAREST)
            nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
            c = fic.outline(nat.crop(nat.getchannel("A").getbbox()))
            canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            canvas.alpha_composite(c, ((64 - c.width) // 2, 64 - c.height - 1))
            canvas.save(os.path.join(OUT, pid + ".png"))
            if pid == "iron_cold":
                for name, ramp in HEAT.items():
                    heat(canvas, ramp).save(os.path.join(OUT, f"iron_{name}.png"))
            print(f"{pid}: {c.width}×{c.height}")


def strikes():
    """Los 3 golpes de «Batir» (03b §3b.2: fuerte, medido y de acabado), compuestos con Pillow para que se
    distingan: el yunque del kit de la forja con la barra al rojo (anvil.png), el martillo (hammer.png) a tres
    alturas y ángulos, y chispas grandes, medianas o ninguna. Sustituyen a los anvil_strike_1..3 de fal, cuyo
    martillo casi no se movía."""
    import random
    anvil = Image.open(os.path.join(ROOT, "assets", "art", "interiors", "forge", "anvil.png")).convert("RGBA")
    bar = Image.open(os.path.join(OUT, "iron_orange.png")).convert("RGBA")
    bar = bar.crop(bar.getchannel("A").getbbox())
    bar = bar.resize((max(1, bar.width * 2 // 3), max(1, bar.height * 2 // 3)), Image.NEAREST)
    base = Image.new("RGBA", (80, 96), (0, 0, 0, 0))
    base.alpha_composite(anvil, (8, 96 - 64))
    base.alpha_composite(bar, (40 - bar.width // 2, 96 - 64 + 10 - bar.height // 2))
    base.save(os.path.join(OUT, "anvil.png"))
    ham = Image.open(os.path.join(ROOT, "assets", "art", "icons", "hammer.png")).convert("RGBA")
    ham.save(os.path.join(OUT, "hammer.png"))
    # (ángulo del martillo, dónde va el centro de la cabeza, chispas): la cabeza baja hacia la barra (40, 42)
    poses = {"strong": (20, (34, 10), 14), "measured": (60, (30, 26), 7), "finish": (95, (34, 38), 0)}

    def head_centre(im):  # la cabeza es la parte gris (no marrón) del icono
        xs, ys = [], []
        for y in range(im.height):
            for x in range(im.width):
                r, g, b, a = im.getpixel((x, y))
                if a > 127 and abs(r - b) < 25 and max(r, g, b) > 50:
                    xs.append(x)
                    ys.append(y)
        return (sum(xs) // len(xs), sum(ys) // len(ys)) if xs else (im.width // 2, im.height // 2)

    for name, (angle, head_at, sparks) in poses.items():
        im = base.copy()
        h = ham.rotate(angle, resample=Image.NEAREST, expand=True)
        hx, hy = head_centre(h)
        im.alpha_composite(h, (head_at[0] - hx, max(0, head_at[1] - hy)))
        rnd = random.Random(name)
        px = im.load()
        for _ in range(sparks):  # chispas: puntos de 1-2 px alrededor del golpe
            x, y = 40 + rnd.randint(-18, 18), 96 - 64 + 8 + rnd.randint(-12, 2)
            c = rnd.choice([(255, 240, 160, 255), (255, 196, 64, 255), (240, 120, 30, 255)])
            for dx, dy in ((0, 0), (1, 0)) if sparks > 8 else ((0, 0),):
                if 0 <= x + dx < 80 and 0 <= y + dy < 96:
                    px[x + dx, y + dy] = c
        im.save(os.path.join(OUT, f"strike_{name}.png"))
    for i in (1, 2, 3):
        p = os.path.join(OUT, f"anvil_strike_{i}.png")
        if os.path.exists(p):
            os.remove(p)
            if os.path.exists(p + ".import"):
                os.remove(p + ".import")
    print("golpes: strike_strong, strike_measured, strike_finish (80×96), anvil.png y hammer.png")


def main():
    {"gen": gen, "proc": proc, "golpes": strikes}[sys.argv[1] if len(sys.argv) > 1 else "proc"]()


if __name__ == "__main__":
    main()
