#!/usr/bin/env python3
"""Materiales del suelo de la ciudad (rama ciudad-2d), dibujados en pixel art sin rejilla de casillas.

Cada material es una textura isométrica de 64·N × 32·N px que se repite como un rectángulo (N casillas por lado):
GroundLayer la muestrea con la posición del mundo (shader game/world/ground.gdshader), así que las piedras y las matas
siguen de una casilla a la siguiente y la misma casilla no se repite cada 64 px. Las piezas se dibujan en el espacio de
la casilla vista desde arriba (U = columna, V = fila; U = x/64 + y/32, V = y/32 − x/64) y se pintan directamente al
píxel del juego, sin reescalar: el píxel queda nítido. Paletas sacadas de los tiles de PixelLab del piloto
(tmp/ciudad2d/pl_tiles, tanda ciudad2d del MANIFEST) y de la biblia (tierras cálidas, luz de arriba a la izquierda).

Uso (Python con numpy: ~/.pixellab-pip-venv/bin/python):
  python tools/art/suelos_materiales.py [--out assets/art/tiles/ground] [--tiles 8] [--only grass,street]
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def hexes(*cs):
    return np.array([[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in cs], np.uint8)


# Rampas (de oscuro a claro)
GRASS = hexes("#2c4527", "#36532c", "#416233", "#4c7138", "#5a8040", "#6a9049", "#7ea255", "#98b864")
FLOWERS = hexes("#e9dd8c", "#efe9d6", "#c9798c", "#9fb7d9")
COBBLE = hexes("#2b231b", "#3a3027", "#4f4438", "#625646", "#766a58", "#8a7e69", "#9d917a", "#b2a68d")
COBBLE_GREY = hexes("#2b231b", "#3a3027", "#4a4640", "#5d5850", "#716b61", "#857f73", "#999385", "#ada798")
MOSS = hexes("#2f3a22", "#3d4a29", "#4d5b30")
FLAG = hexes("#3e2e20", "#5e4630", "#7d6247", "#957a5b", "#a88d6b", "#b89d79", "#c8ae88", "#d8c09a")
FLAG_GREY = hexes("#3e2e20", "#5a4b3d", "#74685a", "#87796a", "#978a79", "#a79a88", "#b7ab98", "#c7bca8")
DIRT = hexes("#4a3424", "#5d4330", "#70523a", "#7f5e41", "#8c6947", "#99754f", "#a8845c", "#b9966c")
PEBBLE = hexes("#5a4c3e", "#8c7e6a", "#b4a68e")


class Canvas:
    """Rejilla de píxeles de la textura iso con sus coordenadas de casilla (U, V) en [0, N)."""

    def __init__(self, n):
        self.n = n
        self.W, self.H = 64 * n, 32 * n
        ys, xs = np.mgrid[0:self.H, 0:self.W].astype(np.float64)
        x, y = xs + 0.5, ys + 0.5
        self.U = np.mod(x / 64 + y / 32, n)
        self.V = np.mod(y / 32 - x / 64, n)

    def wrap(self, a):
        """Distancia con vuelta (período n) en el espacio de casillas."""
        return a - self.n * np.round(a / self.n)

    def to_screen(self, u, v):
        """Punto (U, V) de casilla → píxel (x, y) de la textura (con vuelta)."""
        x = (u - v) * 32
        y = (u + v) * 16
        return np.mod(x, self.W), np.mod(y, self.H)


def value_noise(cv, cells, rng, octaves=1, gain=0.5):
    """Ruido de valor periódico (período n casillas) con interpolación suave; cells = celdas por casilla."""
    out = np.zeros_like(cv.U)
    amp, tot = 1.0, 0.0
    c = cells
    for _ in range(octaves):
        g = max(1, int(round(cv.n * c)))
        grid = rng.random((g, g))
        fu, fv = cv.U / cv.n * g, cv.V / cv.n * g
        iu, iv = np.floor(fu).astype(int), np.floor(fv).astype(int)
        tu, tv = fu - iu, fv - iv
        tu, tv = tu * tu * (3 - 2 * tu), tv * tv * (3 - 2 * tv)
        a = grid[iv % g, iu % g]
        b = grid[iv % g, (iu + 1) % g]
        cc = grid[(iv + 1) % g, iu % g]
        d = grid[(iv + 1) % g, (iu + 1) % g]
        out += amp * ((a * (1 - tu) + b * tu) * (1 - tv) + (cc * (1 - tu) + d * tu) * tv)
        tot += amp
        amp *= gain
        c *= 2
    return out / tot


def voronoi(cv, per_tile, jitter, rng, stretch=(1.0, 1.0)):
    """Voronoi periódico en el espacio de casillas: id de celda, F1, F2 y el centro de la celda más cercana."""
    g = cv.n * per_tile
    su, sv = stretch
    gu, gv = int(round(g / su)), int(round(g / sv))
    seeds_u = (np.arange(gu)[None, :] + 0.5 + (rng.random((gv, gu)) - 0.5) * 2 * jitter) * cv.n / gu
    seeds_v = (np.arange(gv)[:, None] + 0.5 + (rng.random((gv, gu)) - 0.5) * 2 * jitter) * cv.n / gv
    cu, cvv = np.floor(cv.U / cv.n * gu).astype(int), np.floor(cv.V / cv.n * gv).astype(int)
    f1 = np.full(cv.U.shape, 1e9)
    f2 = np.full(cv.U.shape, 1e9)
    cid = np.zeros(cv.U.shape, int)
    cen_u = np.zeros(cv.U.shape)
    cen_v = np.zeros(cv.U.shape)
    for dv in (-1, 0, 1):
        for du in (-1, 0, 1):
            ju, jv = (cu + du) % gu, (cvv + dv) % gv
            su_ = seeds_u[jv, ju]
            sv_ = seeds_v[jv, ju]
            du_ = cv.wrap(cv.U - su_) / su
            dv_ = cv.wrap(cv.V - sv_) / sv
            d = np.sqrt(du_ * du_ + dv_ * dv_)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            f1 = np.where(closer, d, f1)
            cid = np.where(closer, jv * gu + ju, cid)
            cen_u = np.where(closer, su_, cen_u)
            cen_v = np.where(closer, sv_, cen_v)
    return cid, f1, f2, cen_u, cen_v


def lit(h):
    """Luz de arriba a la izquierda: positivo donde la superficie mira hacia la luz (sube hacia abajo-derecha)."""
    return (np.roll(h, (-1, -1), (0, 1)) - np.roll(h, (1, 1), (0, 1))) * 0.5


def boundary(cid):
    """1 donde el vecino de la derecha o el de abajo es de otra celda (junta de 1 px)."""
    return (cid != np.roll(cid, -1, 1)) | (cid != np.roll(cid, -1, 0))


def ramp_pick(ramp, idx):
    return ramp[np.clip(idx, 0, len(ramp) - 1)]


def stamp(img, x, y, glyph, colors):
    """Pega un glifo (lista de cadenas; '.' vacío, dígitos = índice en colors) con vuelta."""
    H, W = img.shape[:2]
    for j, row in enumerate(glyph):
        for i, ch in enumerate(row):
            if ch == ".":
                continue
            img[(y + j) % H, (x + i) % W] = colors[int(ch)]


# --- Materiales -----------------------------------------------------------------------------------------------------

TUFTS = [
    [".0.0.", "01010", ".222."],
    ["..0..", ".010.", "01210", ".222."],
    ["0...0", "10.01", ".121.", "..2.."],
    [".0..", "010.", "1210", "222."],
    ["..0.0", ".0101", ".1212", "..22."],
]


BLADES = [["0", "1"], ["0", "1", "2"], ["1", "2"], ["0.", "10", ".2"], [".0", "01", "2."]]


def grass(cv, rng, darken=0, flowers=True, tufts=1.0):
    lo = value_noise(cv, 0.35, rng, octaves=2)
    mid = value_noise(cv, 1.4, rng, octaves=2)
    t = lo * 0.5 + mid * 0.5
    idx = np.digitize(t, [0.40, 0.50, 0.60]) + 3 - darken  # 3..6
    img = ramp_pick(GRASS, idx).copy()
    # grano: briznas cortas de 2-3 px (claro arriba, oscuro abajo), densas, a un tono del fondo
    for _ in range(int(cv.W * cv.H * 0.075)):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        base = int(idx[y, x])
        g = BLADES[int(rng.integers(len(BLADES)))]
        up = rng.random() < 0.55
        cols = [GRASS[min(7, base + 1)] if up else GRASS[max(0, base - 1)], GRASS[base],
                GRASS[max(0, base - 1)]]
        stamp(img, x, y, g, cols)
    # matas: glifos con luz (0 = brillo, 1 = medio, 2 = sombra)
    count = int(cv.n * cv.n * 4 * tufts)
    for _ in range(count):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        base = int(np.clip(idx[y, x], 3, 6))
        cols = [GRASS[min(7, base + 2)], GRASS[min(7, base + 1)], GRASS[max(0, base - 2)]]
        stamp(img, x, y, TUFTS[int(rng.integers(len(TUFTS)))], cols)
    if flowers:
        for _ in range(int(cv.n * cv.n * 0.7)):
            x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
            c = FLOWERS[int(rng.choice(4, p=[0.45, 0.35, 0.12, 0.08]))]
            img[y % cv.H, x % cv.W] = c
            img[(y + 1) % cv.H, x % cv.W] = GRASS[2]
    return img


def cobbles(cv, rng, per_tile=3.0, grey_share=0.35, moss=0.25):
    cid, f1, f2, cu, cvv = voronoi(cv, per_tile, 0.38, rng)
    edge = f2 - f1
    h = np.clip(edge / 0.16, 0, 1) ** 0.6
    light = lit(h)
    n_cells = cid.max() + 1
    tone = rng.integers(-1, 2, n_cells)  # piedra más clara u oscura
    grey = rng.random(n_cells) < grey_share
    worn = rng.random(n_cells) < 0.06
    base = 4 + tone[cid]
    idx = base + np.where(light > 0.10, 1, 0) + np.where(light > 0.22, 1, 0) - np.where(light < -0.10, 1, 0) \
        - np.where(light < -0.22, 1, 0)
    idx = idx - (h < 0.35).astype(int)  # canto de la piedra más oscuro
    idx = np.where(worn[cid], np.minimum(idx, 4), idx)
    img = np.where(grey[cid][..., None], ramp_pick(COBBLE_GREY, idx), ramp_pick(COBBLE, idx))
    # junta: 1 px entre piedras y más ancha en los cruces
    joint = boundary(cid) | (edge < 0.028)
    m = value_noise(cv, 0.7, rng, octaves=2)
    mortar = np.where((m > 1 - moss)[..., None], MOSS[1], COBBLE[1])
    img = np.where(joint[..., None], mortar, img)
    deep = joint & (edge < 0.012)
    img[deep] = np.where((m[deep] > 1 - moss)[..., None], MOSS[0], COBBLE[0])
    return img


def flagstones(cv, rng, rows_per_tile=2, grey_share=0.18):
    """Losas en hileras escalonadas a lo largo de U, de largo variable; bisel con la luz y alguna grieta."""
    rows = int(cv.n * rows_per_tile)
    rv = cv.V / cv.n * rows
    r = np.floor(rv).astype(int) % rows
    fv = rv - np.floor(rv)
    # cortes de cada hilera: largos de 0,55 a 1,1 casillas, cerrando el período
    cuts = []
    for _ in range(rows):
        xs, u = [], 0.0
        while u < cv.n - 0.5:
            xs.append(u)
            u += rng.uniform(0.55, 1.1)
        xs = np.array(xs) + rng.uniform(0, 0.5)
        cuts.append(np.sort(np.mod(xs, cv.n)))
    sid = np.zeros(cv.U.shape, int)
    fu = np.zeros(cv.U.shape)
    flen = np.ones(cv.U.shape)
    for k in range(rows):
        mask = r == k
        c = cuts[k]
        u = cv.U[mask]
        j = np.searchsorted(c, u, side="right") - 1  # -1 = antes del primero: la última que da la vuelta
        start = np.where(j >= 0, c[j], c[-1] - cv.n)
        nxt = np.where(j + 1 < len(c), c[np.minimum(j + 1, len(c) - 1)], c[0] + cv.n)
        sid[mask] = k * 64 + (j % len(c))
        fu[mask] = u - start
        flen[mask] = nxt - start
    # distancia al borde de la losa en casillas
    du = np.minimum(fu, flen - fu)
    dv = np.minimum(fv, 1 - fv) / rows_per_tile
    e = np.minimum(du, dv)
    n_s = sid.max() + 1
    tone = rng.integers(-1, 2, n_s)
    grey = rng.random(n_s) < grey_share
    base = 4 + tone[sid]
    # bisel: lado que mira a la luz (arriba-izquierda: U o V pequeños) claro, el contrario oscuro
    near = e < 0.07
    toward = np.where(du < dv, fu < flen / 2, fv < 0.5)
    idx = base + np.where(near & toward, 1, 0) - np.where(near & ~toward, 1, 0)
    wear = value_noise(cv, 2.2, rng, octaves=2)
    idx = idx - (wear > 0.68).astype(int) + (wear < 0.25).astype(int)
    sp = rng.random(cv.U.shape)
    idx = idx - (sp < 0.04).astype(int)
    img = np.where(grey[sid][..., None], ramp_pick(FLAG_GREY, idx), ramp_pick(FLAG, idx))
    joint = boundary(sid)
    img[joint] = FLAG[1]
    # grietas cortas en algunas losas
    for _ in range(int(cv.n * cv.n * 0.6)):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        dx = int(rng.choice([-1, 1]))
        for _k in range(int(rng.integers(3, 7))):
            if joint[y % cv.H, x % cv.W]:
                break
            img[y % cv.H, x % cv.W] = FLAG[2]
            x += dx
            if rng.random() < 0.5:
                y += 1
    return img


def dirt(cv, rng, pebbles=1.0, grass_bits=0.6):
    lo = value_noise(cv, 0.5, rng, octaves=3)
    hi = value_noise(cv, 3.0, rng, octaves=1)
    t = lo * 0.6 + hi * 0.4
    idx = np.digitize(t, [0.42, 0.52, 0.60]) + 3  # 3..6
    img = ramp_pick(DIRT, idx).copy()
    # grano: terrones de 2 px con luz arriba y sombra abajo
    for _ in range(int(cv.W * cv.H * 0.05)):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        base = int(idx[y, x])
        stamp(img, x, y, ["0", "1"] if rng.random() < 0.5 else ["01"], [DIRT[min(7, base + 1)], DIRT[base - 1]])
    for _ in range(int(cv.n * cv.n * 7 * pebbles)):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        big = rng.random() < 0.3
        stamp(img, x, y, ["12", "00"] if big else ["1", "0"] if rng.random() < 0.5 else ["21"], PEBBLE)
    for _ in range(int(cv.n * cv.n * 1.2 * grass_bits)):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        stamp(img, x, y, TUFTS[int(rng.integers(len(TUFTS)))][-2:], [GRASS[5], GRASS[4], DIRT[1]])
    # grietas secas
    for _ in range(int(cv.n * cv.n * 0.8)):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        for _k in range(int(rng.integers(2, 6))):
            img[y % cv.H, x % cv.W] = DIRT[1]
            x += int(rng.choice([-1, 1]))
            y += int(rng.random() < 0.5)
    return img


def yard(cv, rng):
    """Patio de las casas: hierba pisada con calvas de tierra."""
    g = grass(cv, rng, darken=1, flowers=False, tufts=0.6)
    d = dirt(cv, rng, pebbles=0.6, grass_bits=1.5)
    m = value_noise(cv, 0.9, rng, octaves=3)
    edge = (m > 0.55) & (m < 0.585)
    out = np.where((m > 0.57)[..., None], d, g)
    out[edge] = DIRT[2]
    return out


def noise_png(path, size=64, cells=8, seed=11):
    """Ruido de bordes del shader: 4 canales de ruido de valor suave y periódico (64×64; el shader lo filtra lineal)."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:size, 0:size] / size
    chans = []
    for _ in range(4):
        acc = np.zeros((size, size))
        amp, tot, c = 1.0, 0.0, cells
        for _o in range(2):
            g = rng.random((c, c))
            fu, fv = xs * c, ys * c
            iu, iv = np.floor(fu).astype(int), np.floor(fv).astype(int)
            tu, tv = fu - iu, fv - iv
            tu, tv = tu * tu * (3 - 2 * tu), tv * tv * (3 - 2 * tv)
            a, b = g[iv % c, iu % c], g[iv % c, (iu + 1) % c]
            cc, d = g[(iv + 1) % c, iu % c], g[(iv + 1) % c, (iu + 1) % c]
            acc += amp * ((a * (1 - tu) + b * tu) * (1 - tv) + (cc * (1 - tu) + d * tu) * tv)
            tot += amp
            amp *= 0.45
            c *= 2
        acc /= tot
        acc = (acc - acc.min()) / (acc.max() - acc.min())
        chans.append(acc)
    Image.fromarray((np.stack(chans, -1) * 255).astype(np.uint8), "RGBA").save(path)
    print(path)


WATER = hexes("#1f3b52", "#26475f", "#2d546f", "#356282", "#3f7193", "#5b8fab", "#8fbccf", "#c4e0e6")


def water(cv, rng):
    """Agua del río: bandas suaves de 3 tonos y destellos cortos horizontales (el shader la desplaza despacio)."""
    lo = value_noise(cv, 0.5, rng, octaves=2)
    t = lo
    idx = np.digitize(t, [0.42, 0.58]) + 2  # 2..4
    img = ramp_pick(WATER, idx).copy()
    for _ in range(int(cv.n * cv.n * 9)):
        x, y = int(rng.integers(cv.W)), int(rng.integers(cv.H))
        ln = int(rng.integers(2, 7))
        base = int(idx[y, x])
        light = rng.random() < 0.45
        c = WATER[min(7, base + (2 if light else 1))] if rng.random() < 0.8 else WATER[max(0, base - 1)]
        for k in range(ln):
            img[y % cv.H, (x + k) % cv.W] = c
        if light and ln > 3 and rng.random() < 0.4:
            img[y % cv.H, (x + ln // 2) % cv.W] = WATER[7]
    return img


SOIL = hexes("#2e2016", "#3f2c1e", "#523a27", "#654832", "#78573c")
LEAF = hexes("#26401f", "#35592a", "#4a7834", "#64963f", "#86b452")


def garden_bed(seed=5, ridges=3):
    """Bancal de huerto de una casilla (props/furrows.png, 64×32): caballones de tierra labrada a lo largo de U con
    coles y puerros encima; fuera del rombo (y un borde mordido) transparente, así se asienta sobre la hierba."""
    rng = np.random.default_rng(seed)
    W, H = 64, 32
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
    x, y = xs + 0.5 - 32, ys + 0.5 - 16
    U, V = x / 64 + y / 32 + 0.5, y / 32 - x / 64 + 0.5  # 0..1 dentro del rombo
    inside = (U > 0.06) & (U < 0.94) & (V > 0.06) & (V < 0.94)
    jag = rng.random((H, W)) < 0.35
    edge = inside & ((U < 0.1) | (U > 0.9) | (V < 0.1) | (V > 0.9))
    inside = inside & ~(edge & jag)
    ph = (V * ridges) % 1.0  # 0..1 a través de cada caballón
    idx = np.where(ph < 0.18, 0, np.where(ph < 0.35, 3, np.where(ph < 0.7, 2, 1)))  # surco, cara a la luz, lomo, sombra
    img = np.zeros((H, W, 4), np.uint8)
    img[..., :3] = SOIL[idx + 1]
    img[..., 3] = np.where(inside, 255, 0)
    sp = rng.random((H, W))
    img[inside & (sp < 0.08), :3] = SOIL[1]
    # plantas sobre el lomo de cada caballón
    for k in range(ridges):
        vc = (k + 0.5) / ridges
        u = 0.14 + rng.random() * 0.05
        while u < 0.88:
            px, py = (u - vc) * 32 + 32, (u + vc) * 16 - 16 + 16
            cx, cy = int(px), int(py) - 1
            if rng.random() < 0.6:  # col: bola de hojas con luz arriba a la izquierda
                g = [".22.", "2343", "1221", ".00."]
            else:  # puerro: hojas finas
                g = ["3.3", "232", ".1.", ".0."]
            for j, row in enumerate(g):
                for i, ch in enumerate(row):
                    if ch == ".":
                        continue
                    yy, xx = cy - 2 + j, cx - 1 + i
                    if 0 <= yy < H and 0 <= xx < W:
                        img[yy, xx, :3] = LEAF[int(ch)]
                        img[yy, xx, 3] = 255
            u += 0.13 + rng.random() * 0.05
    return img


def plot_ground(seed=9):
    """Suelo del solar libre (props/plot_ground.png, 64×32): tierra pisada con el borde mordido, guijarros y algún
    hierbajo; fuera transparente (asienta sobre la hierba)."""
    rng = np.random.default_rng(seed)
    tex = dirt(Canvas(4), np.random.default_rng(seed), pebbles=0.8, grass_bits=0.8)[:32, :64]
    ys, xs = np.mgrid[0:32, 0:64].astype(np.float64)
    x, y = xs + 0.5 - 32, ys + 0.5 - 16
    d = np.abs(x) / 32 + np.abs(y) / 16  # 1 en el borde del rombo
    # rombo entero (las casillas del solar se juntan en una sola mancha de tierra); solo el último píxel del borde
    # se muerde al azar para que el contorno exterior no sea una regla
    inside = (d < 1.0) & ~((d > 0.93) & (rng.random((32, 64)) < 0.45))
    img = np.zeros((32, 64, 4), np.uint8)
    img[..., :3] = tex
    img[..., 3] = np.where(inside, 255, 0)
    return img


def stake():
    """Estaca de esquina del solar (props/plot_stake.png, 5×16): palo con la cara a la luz, punta y cinta blanca."""
    g = ["..4..", ".343.", ".211.", ".555.", ".211.", ".211.", ".211.", ".211.", ".211.", ".211.", ".211.", ".211.",
         ".211.", ".211.", ".2.1.", "..1.."]
    cols = {"1": (92, 64, 38, 255), "2": (138, 98, 58, 255), "3": (70, 48, 30, 255), "4": (46, 32, 22, 255),
            "5": (226, 220, 196, 255)}
    img = np.zeros((16, 5, 4), np.uint8)
    for j, row in enumerate(g):
        for i, ch in enumerate(row):
            if ch != ".":
                img[j, i] = cols[ch]
    return img


MATERIALS = {"grass": grass, "street": cobbles, "plaza": flagstones, "dirt": dirt, "yard": yard, "water": water}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "art", "tiles", "ground"))
    ap.add_argument("--tiles", type=int, default=8)
    ap.add_argument("--only", default="")
    ap.add_argument("--seed", type=int, default=2026)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cv = Canvas(a.tiles)
    if not a.only:
        noise_png(os.path.join(a.out, "noise.png"))
        for name, im in (("plot_ground", plot_ground()), ("plot_stake", stake())):
            Image.fromarray(im, "RGBA").save(os.path.join(ROOT, "assets", "art", "props", name + ".png"))
        bed = os.path.join(ROOT, "assets", "art", "props", "furrows.png")
        Image.fromarray(garden_bed(), "RGBA").save(bed)
        print(bed)
    for i, (name, fn) in enumerate(MATERIALS.items()):
        if a.only and name not in a.only.split(","):
            continue
        img = fn(cv, np.random.default_rng(a.seed + i * 101))
        path = os.path.join(a.out, name + ".png")
        Image.fromarray(img.astype(np.uint8), "RGB").save(path)
        print(path, img.shape[1], "x", img.shape[0], len(np.unique(img.reshape(-1, 3), axis=0)), "colores")


if __name__ == "__main__":
    main()
