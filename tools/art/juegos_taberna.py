#!/usr/bin/env python3
"""Piezas de los juegos de taberna (docs/gdd/04f_vida_y_fiestas.md §4.26.7-8) en assets/art/ui/games/:

- naipes/: baraja de 40 cartas de 4 palos (oros, copas, espadas, bastos: 1-7, sota 10, caballo 11, rey 12), al
  estilo de los naipes antiguos. fal hace los 4 palos (tools/art/fal_iconos.py, rejilla s1) y las 12 figuras (aquí,
  rejillas n1-n3: sotas, caballos y reyes de cada palo); Pillow compone las cartas (48×72, con la disposición de los
  palos de la baraja española y su número en las esquinas), el reverso y un hueco de carta.
  Ficheros: <palo>_<n>.png (n = 1-7, 10, 11, 12), back.png, slot.png, suit_<palo>.png (32) y small/ (16).
- dados/: dados de hueso dibujados con Pillow (puntos exactos): d1-d6.png (24×24, cara de arriba) y shadow.png.
- mesa/: el fondo de mesa de taberna (fal), mesa.png a 960×540 (480×270 ×2), compartido por dados y naipes.

Uso: FAL_TANDA=h16 python3 tools/art/juegos_taberna.py gen|proc|cartas|dados
"""
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
P = fr_.produccion("juegos")
OUT = os.path.join(ROOT, "assets", "art", "ui", "games")
SUITS = ["oros", "copas", "espadas", "bastos"]
SUIT_EN = {"oros": "coins (round gold coins)", "copas": "cups (golden goblets)", "espadas": "swords",
           "bastos": "clubs (knotty wooden clubs)"}
FIGS = {"sota": "a young page standing, holding one {s}", "caballo": "a knight riding a horse, holding one {s}",
        "rey": "a crowned king seated on a throne, holding one {s}"}
FIG_N = {"sota": 10, "caballo": 11, "rey": 12}
CARD = (48, 72)
FIG_BOX = (40, 54)
INK = (42, 31, 20, 255)
PAPER = (236, 222, 190, 255)
PAPER_DARK = (205, 186, 148, 255)
RED = (154, 42, 34, 255)


def fig_prompt(fig):
    cells = " ".join(f"{pos}: {FIGS[fig].format(s=SUIT_EN[s])}, the {s} suit figure."
                     for pos, s in zip(["Top-left", "Top-right", "Bottom-left", "Bottom-right"], SUITS))
    return ("The attached image shows pixel art icons from our medieval game, enlarged. Create ONE square image that "
            "is a 2x2 grid of four court-card figures for an old Spanish 40-card deck from around 1400, in the flat "
            "woodcut colours of old playing cards (red, ochre yellow, blue, green and black outline) but drawn as "
            "16-bit pixel art: each figure drawn on a 64x64 pixel grid (every art pixel is an 8x8 block), full body, "
            "about 40 pixels wide and 54 tall, centred on a plain flat white background, no card border, no number, "
            "no letters. " + cells)


def gen():
    ref = fic.ref_sheet("i")
    os.makedirs(os.path.join(P, "crudo"), exist_ok=True)
    jobs = [("n1", fig_prompt("sota")), ("n2", fig_prompt("caballo")), ("n3", fig_prompt("rey")),
            ("mesa", "Using the attached image only as STYLE reference (16-bit pixel art, warm palette), paint the "
                     "background of a tavern dice and card game: a worn dark oak tavern table seen from straight "
                     "above, filling the whole image, visible planks and wood grain, a few ale stains and knife "
                     "marks, a burning candle and a clay mug at the far edges, the centre clear and calm for the "
                     "cards and dice. No text, no cards, no dice, no hands.")]
    for name, text in jobs:
        if os.path.exists(os.path.join(P, "crudo", name + ".png")):
            continue
        ref_img = ref if name != "mesa" else os.path.join(fr_.PILOTO, "titulo", "crudo", "titulo_alba_v1.png")
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "juegos",
               "--aspect", "16:9" if name == "mesa" else "1:1", "--name", name, "--ref", ref_img, "--prompt", text]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


def i2p(name, src_im, scale, colors, transparent=True):
    src = os.path.join(P, "celdas", name + ".png")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    src_im.save(src)
    dst = os.path.join(P, "i2p", f"{name}_s{scale}.png")
    if not os.path.exists(dst):
        import fal_piloto
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fal_piloto.pixel(SimpleNamespace(piece="juegos", src=src, dst=dst, colors=colors, scale=scale, palette="",
                                         transparent=transparent))
    up = Image.open(dst).convert("RGBA")
    return up.resize((up.width // scale, up.height // scale), Image.NEAREST)


def proc():
    """Figuras (a P/figuras, para componer) y la mesa (al juego)."""
    os.makedirs(os.path.join(P, "figuras"), exist_ok=True)
    for g, fig in (("n1", "sota"), ("n2", "caballo"), ("n3", "rey")):
        raw = os.path.join(P, "crudo", g + ".png")
        if not os.path.exists(raw):
            print("falta", raw)
            continue
        im = Image.open(raw).convert("RGBA").resize((1024, 1024))
        for k, suit in enumerate(SUITS):
            cell = im.crop(((k % 2) * 512, (k // 2) * 512, (k % 2 + 1) * 512, (k // 2 + 1) * 512))
            nat = i2p(f"{fig}_{suit}", fp.key_background(cell, "white", 28), 8, 20)
            nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
            c = nat.crop(nat.getchannel("A").getbbox())
            if c.width > FIG_BOX[0] or c.height > FIG_BOX[1]:
                k2 = min(FIG_BOX[0] / c.width, FIG_BOX[1] / c.height)
                c = c.resize((max(1, int(c.width * k2)), max(1, int(c.height * k2))), Image.NEAREST)
            c.save(os.path.join(P, "figuras", f"{fig}_{suit}.png"))
    raw = os.path.join(P, "crudo", "mesa.png")
    if os.path.exists(raw):
        im = Image.open(raw).convert("RGB")
        import fal_ilustraciones as fi
        pal = fi.i2p_palette(raw, "games_mesa", 48)
        d = os.path.join(OUT, "mesa")
        os.makedirs(d, exist_ok=True)
        fi.reduce(im, (480, 270), pal).resize((960, 540), Image.NEAREST).save(os.path.join(d, "mesa.png"))
    print("figuras y mesa")


# --- cartas -----------------------------------------------------------------------------------------------------
DIGITS = {  # 3×5
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "011", "001", "111"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
}
# Posiciones de los palos (centros, en la carta de 48×72) para 1-7, como en la baraja española
PIPS = {1: [(24, 36)], 2: [(24, 18), (24, 54)], 3: [(24, 16), (24, 36), (24, 56)],
        4: [(15, 20), (33, 20), (15, 52), (33, 52)], 5: [(15, 20), (33, 20), (24, 36), (15, 52), (33, 52)],
        6: [(15, 18), (33, 18), (15, 36), (33, 36), (15, 54), (33, 54)],
        7: [(15, 16), (33, 16), (24, 26), (15, 38), (33, 38), (15, 56), (33, 56)]}


def card_base():
    im = Image.new("RGBA", CARD, (0, 0, 0, 0))
    px = im.load()
    w, h = CARD
    for y in range(h):
        for x in range(w):
            corner = (x in (0, w - 1) and y in (0, 1, h - 2, h - 1)) or (y in (0, h - 1) and x in (1, w - 2))
            if corner:
                continue
            edge = x in (0, w - 1) or y in (0, h - 1)
            px[x, y] = INK if edge else PAPER
    # marco interior con «pausas» (cortes del filete, como en los naipes españoles) y sombra abajo
    for x in range(3, w - 3):
        if not (w // 2 - 4 <= x <= w // 2 + 3):
            px[x, 3] = PAPER_DARK
            px[x, h - 4] = PAPER_DARK
    for y in range(3, h - 3):
        px[3, y] = PAPER_DARK
        px[w - 4, y] = PAPER_DARK
    for x in range(1, w - 1):
        px[x, h - 2] = PAPER_DARK
    return im


def draw_number(im, n, at, color=INK):
    px = im.load()
    x0, y0 = at
    for ch in str(n):
        for r, rowbits in enumerate(DIGITS[ch]):
            for c, b in enumerate(rowbits):
                if b == "1":
                    px[x0 + c, y0 + r] = color
        x0 += 4


def suit_small(suit, size):
    big = Image.open(os.path.join(OUT, "naipes", f"suit_{suit}.png")).convert("RGBA")
    bb = big.getchannel("A").getbbox()
    c = big.crop(bb)
    k = size / max(c.size)
    return c.resize((max(1, round(c.width * k)), max(1, round(c.height * k))), Image.NEAREST)


def cards():
    d = os.path.join(OUT, "naipes")
    fig_dir = os.path.join(P, "figuras")
    count = 0
    for suit in SUITS:
        pip = suit_small(suit, 12)
        big = suit_small(suit, 24)
        tiny = suit_small(suit, 7)
        for n in list(range(1, 8)) + [10, 11, 12]:
            im = card_base()
            col = RED if suit in ("oros", "copas") else INK
            draw_number(im, n, (5, 5), col)
            draw_number(im, n, (CARD[0] - 5 - 4 * len(str(n)) + 1, CARD[1] - 10), col)
            if n <= 7:
                pts = PIPS[n]
                sym = big if n == 1 else pip
                for (cx, cy) in pts:
                    im.alpha_composite(sym, (cx - sym.width // 2, cy - sym.height // 2))
            else:
                fig = {10: "sota", 11: "caballo", 12: "rey"}[n]
                f = Image.open(os.path.join(fig_dir, f"{fig}_{suit}.png")).convert("RGBA")
                box = (40, 48)  # sin tapar el número de la esquina de abajo
                if f.width > box[0] or f.height > box[1]:
                    k = min(box[0] / f.width, box[1] / f.height)
                    f = f.resize((max(1, round(f.width * k)), max(1, round(f.height * k))), Image.NEAREST)
                im.alpha_composite(f, ((CARD[0] - f.width) // 2, 12 + (box[1] - f.height) // 2))
                im.alpha_composite(tiny, (CARD[0] - tiny.width - 5, 5))
            im.save(os.path.join(d, f"{suit}_{n}.png"))
            count += 1
    # reverso: rombos rojos y dorados sobre papel, con el marco
    back = card_base()
    px = back.load()
    for y in range(5, CARD[1] - 5):
        for x in range(5, CARD[0] - 5):
            u, v = (x + y) % 8, (x - y) % 8
            if u == 0 or v == 0:
                px[x, y] = RED
            elif (x // 4 + y // 4) % 2 == 0:
                px[x, y] = (200, 168, 78, 255)
    back.save(os.path.join(d, "back.png"))
    slot = Image.new("RGBA", CARD, (0, 0, 0, 0))
    sp = slot.load()
    for y in range(CARD[1]):
        for x in range(CARD[0]):
            if (x in (0, CARD[0] - 1) or y in (0, CARD[1] - 1)) and (x + y) % 3:
                sp[x, y] = (236, 228, 210, 160)
    slot.save(os.path.join(d, "slot.png"))
    print(f"naipes: {count} cartas de {CARD[0]}×{CARD[1]}, reverso y hueco")


def dice():
    d = os.path.join(OUT, "dados")
    os.makedirs(d, exist_ok=True)
    S = 24
    BONE, BONE_HI, BONE_LO, PIP = (232, 220, 190, 255), (248, 242, 222, 255), (196, 180, 146, 255), (50, 34, 24, 255)
    spots = {1: [(12, 12)], 2: [(7, 7), (17, 17)], 3: [(7, 7), (12, 12), (17, 17)],
             4: [(7, 7), (17, 7), (7, 17), (17, 17)], 5: [(7, 7), (17, 7), (12, 12), (7, 17), (17, 17)],
             6: [(7, 6), (17, 6), (7, 12), (17, 12), (7, 18), (17, 18)]}
    for n, pts in spots.items():
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        px = im.load()
        for y in range(1, S - 1):
            for x in range(1, S - 1):
                if (x in (1, S - 2) and y in (1, S - 2)):
                    continue
                edge = x in (1, S - 2) or y in (1, S - 2) or (x in (2, S - 3) and y in (2, S - 3))
                if edge:
                    px[x, y] = INK
                elif x <= 3 or y <= 3:
                    px[x, y] = BONE_HI
                elif x >= S - 5 or y >= S - 5:
                    px[x, y] = BONE_LO
                else:
                    px[x, y] = BONE
        r = 2 if n == 1 else 1  # el as, más grande
        for (cx, cy) in pts:  # hoyo redondeado: centro oscuro, esquinas en un tono intermedio
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    corner = abs(dx) == r and abs(dy) == r
                    px[cx + dx, cy + dy] = (112, 84, 58, 255) if corner else PIP
        im.save(os.path.join(d, f"d{n}.png"))
    sh = Image.new("RGBA", (S, 8), (0, 0, 0, 0))
    for y in range(8):
        for x in range(S):
            if ((x - 11.5) / 11) ** 2 + ((y - 3.5) / 3.5) ** 2 <= 1 and (x + y) % 2 == 0:
                sh.putpixel((x, y), (20, 12, 8, 140))
    sh.save(os.path.join(d, "shadow.png"))
    print("dados: d1-d6 de 24×24 y sombra")


def cup():
    """El cubilete boca abajo (04f §4.26.7: tapa el dado oculto de «a la mayor»), 24×24 como los dados: un cono de
    cuero cerrado por arriba (la tapa, una elipse vista un poco desde arriba), un ribete más oscuro abajo y una
    costura; luz de arriba a la izquierda."""
    S = 24
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = im.load()
    LEATHER = [(84, 46, 24), (122, 70, 36), (156, 96, 52), (190, 128, 74)]  # oscuro → brillo
    RIM, STITCH = (66, 36, 20), (222, 196, 150)
    top_y, bot_y = 4, 21          # tapa y boca
    top_hw, bot_hw = 6.5, 9.5     # medio ancho arriba y abajo
    cx = 11.5
    for y in range(top_y, bot_y + 1):
        t = (y - top_y) / (bot_y - top_y)
        hw = top_hw + (bot_hw - top_hw) * t
        for x in range(S):
            u = (x - cx) / hw
            if abs(u) > 1:
                continue
            tone = 3 if u < -0.45 else 2 if u < 0.15 else 1 if u < 0.7 else 0
            c = LEATHER[tone]
            if y >= bot_y - 2:
                c = RIM if tone < 2 else LEATHER[1]
            elif y == top_y + 7 and int(x) % 2 == 0 and abs(u) < 0.85:
                c = STITCH if tone >= 1 else LEATHER[2]
            px[x, y] = c + (255,)
    for y in range(top_y - 2, top_y + 3):  # la tapa: elipse más clara
        for x in range(S):
            if ((x - cx) / top_hw) ** 2 + ((y - top_y) / 2.2) ** 2 <= 1:
                px[x, y] = (LEATHER[3] if x < cx else LEATHER[2]) + (255,)
    import fal_iconos as fic
    im = fic.outline(im)
    im.save(os.path.join(OUT, "dados", "cup.png"))
    print("cubilete: dados/cup.png 24×24")


def main():
    {"gen": gen, "proc": proc, "cartas": cards, "dados": dice, "cubilete": cup}[sys.argv[1] if len(sys.argv) > 1 else "proc"]()


if __name__ == "__main__":
    main()
