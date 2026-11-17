#!/usr/bin/env python3
"""Casas de la ciudad (rama ciudad-2d): retoques locales de las fachadas, sin cambiar lienzo, ancla ni huella.

  regrass   la hierba lima horneada en el zócalo de algunos edificios pasa a la rampa de la hierba del suelo
            nuevo (tools/art/suelos_materiales.py GRASS), con el mismo sombreado (por orden de luminancia).
  temper    house_f (ocre muy saturado) y house_c (tejado rosado): paredes y tejado más terrosos, ventanas de
            cian a azul pizarra.
  roofs     variantes de color de tejado (y de pared) de las casas de relleno: el tejado se encuentra rellenando
            desde la cumbrera (vecinos de color parecido, sin cruzar el contorno oscuro) y se pasa a otra rampa por
            orden de luminancia. Cada variante tiene su espalda (<id>_back) con la misma receta.
  sheet     lámina de comprobación en tmp/ciudad2d/casas.png.

Uso: ~/.pixellab-pip-venv/bin/python tools/art/ciudad_casas.py regrass|temper|roofs|sheet [--dry]
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from suelos_materiales import GRASS, hexes  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
B = os.path.join(ROOT, "assets", "art", "buildings")
PROPS = os.path.join(ROOT, "assets", "art", "props")

REGRASS = ["escala_b/town_hall.png", "fal/town_hall_back.png", "town_hall.png",
           "escala_b/house_a.png", "escala_b/house_a_back.png", "escala_b/house_e.png", "escala_b/house_e_back.png",
           "escala_b/house_b.png", "escala_b/house_b_back.png", "escala_b/forge.png", "forge.png",
           "fal/forge.png", "fal/forge_back.png", "fal/forge_construction.png", "fal/forge_back_construction.png",
           "fal/forge_damaged.png", "fal/forge_back_damaged.png", "house_a.png", "house_e.png", "house_b.png"]
REGRASS_PROPS = ["well.png", "lantern.png", "sign_post.png"]

# rampas de tejado (oscuro -> claro)
SLATE = hexes("#1c1f27", "#2b303b", "#3a4150", "#4b5363", "#5d6677", "#717b8c", "#8792a2", "#a2adbb")
SLATE_PURPLE = hexes("#1f1a26", "#2f2738", "#3f354b", "#50445e", "#615571", "#756885", "#8b7e9a", "#a597b2")
TILE_BROWN = hexes("#2a1710", "#40241a", "#572f22", "#6e3d2b", "#844c35", "#995c40", "#ad6e4f", "#c18562")
TILE_RED = hexes("#2b1210", "#451a16", "#5f231d", "#7a2d24", "#93382b", "#aa4733", "#c05a3f", "#d4714f")
TERRACOTTA = hexes("#2e1510", "#4a2016", "#66301f", "#80412a", "#985233", "#ad633d", "#c0774b", "#d18c5d")
OCHRE_WALL = hexes("#4a3420", "#6a4c2c", "#87633a", "#a07a4a", "#b48f5c", "#c4a26f", "#d3b583", "#e0c899")
WINDOW = hexes("#141a22", "#1f2a36", "#2c3b4a", "#3b4f61", "#4e6577", "#657d8e")

# variantes: id nuevo -> (sprite base de escala_b, cambios). Cambios: ("roof", rampa) y ("wall", rampa).
VARIANTS = {
    "house_g": ("house_c", [("roof", SLATE)]),
    "house_h": ("house_a", [("roof", TILE_BROWN)]),
    "house_i": ("house_b", [("roof", SLATE_PURPLE)]),
    "house_j": ("house_f", [("roof", TILE_RED)]),
}
MASK_FROM = {"house_f": "house_c"}  # the same house recoloured: house_c's roof is the clean one


def load(p):
    return np.asarray(Image.open(p).convert("RGBA")).copy()


def hsv(rgb):
    r, g, b = [rgb[..., i].astype(float) / 255 for i in range(3)]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    return h * 60, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0), mx


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def remap(img, mask, ramp, lo=0, hi=None):
    """Los colores de `mask` pasan a `ramp` por orden de luminancia (cada color distinto a su peldaño)."""
    hi = len(ramp) - 1 if hi is None else hi
    cols = np.unique(img[mask][:, :3], axis=0)
    if len(cols) == 0:
        return img
    order = np.argsort(lum(cols.astype(float)))
    ls = lum(cols.astype(float))
    lmin, lmax = ls.min(), ls.max()
    out = img.copy()
    for c in cols[order]:
        t = 0.0 if lmax - lmin < 1 else (lum(c.astype(float)) - lmin) / (lmax - lmin)
        k = int(round(lo + t * (hi - lo)))
        sel = mask & np.all(img[..., :3] == c, axis=-1)
        out[sel, :3] = ramp[k]
    return out


def grass_mask(img):
    h, s, v = hsv(img[..., :3])
    return (img[..., 3] > 127) & (h > 65) & (h < 160) & (s > 0.28) & (v > 0.3)


def regrass(dry=False):
    for rel in REGRASS + ["../props/" + p for p in REGRASS_PROPS]:
        p = os.path.normpath(os.path.join(B, rel))
        if not os.path.exists(p):
            continue
        img = load(p)
        m = grass_mask(img)
        if m.sum() < 10:
            continue
        out = remap(img, m, GRASS, 1, 6)
        print(f"regrass {os.path.relpath(p, ROOT)}: {int(m.sum())} px")
        if not dry:
            Image.fromarray(out, "RGBA").save(p)


def roof_mask(img, hue_tol=16):
    """Relleno desde la cumbrera: semillas en las filas de arriba; se extiende a los vecinos opacos del mismo tono
    que la cumbrera (± hue_tol grados, saturados) sin pasar por el contorno (luminancia < 40). La chimenea y el
    remate, si son de otro tono, se quedan fuera."""
    a = img[..., 3] > 127
    L = lum(img[..., :3].astype(float))
    h, s, v = hsv(img[..., :3])
    H, W = a.shape
    rows = np.where(a.any(1))[0]
    top = rows[0]
    band = np.zeros_like(a)
    band[top:top + 30] = True
    cand = a & band & (L > 45) & (s > 0.25)
    hs = h[cand]
    # tono medio circular de la franja de arriba
    ang = np.deg2rad(hs)
    hue0 = np.rad2deg(np.arctan2(np.sin(ang).mean(), np.cos(ang).mean())) % 360
    dh = np.abs(((h - hue0) + 180) % 360 - 180)
    ok = a & (L > 40) & (dh < hue_tol) & (s > 0.2)
    seeds = list(zip(*np.where(cand & ok)))
    mask = np.zeros_like(a)
    q = deque(seeds)
    for sd in seeds:
        mask[sd] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and not mask[ny, nx] and ok[ny, nx]:
                mask[ny, nx] = True
                q.append((ny, nx))
    # por columna: el tejado está por encima de la primera pared clara (crema u ocre); las vigas y los marcos de
    # puerta del mismo tono que salen más abajo se quedan fuera
    wall = a & (h > 28) & (h < 62) & (s > 0.15) & (v > 0.55) & ~mask
    for x in range(W):
        ys = np.where(wall[:, x])[0]
        if len(ys):
            mask[ys[0]:, x] = False
    # fuera los postes: rachas horizontales de 1-2 px que siguen en la misma columna 2 filas más arriba (un canto
    # inclinado 2:1 se corre 4 px en 2 filas y se queda)
    for _ in range(2):
        run = np.zeros(mask.shape, int)
        for y in range(H):
            x = 0
            while x < W:
                if mask[y, x]:
                    x0 = x
                    while x < W and mask[y, x]:
                        x += 1
                    run[y, x0:x] = x - x0
                else:
                    x += 1
        thin = mask & (run <= 2)
        post = thin & np.roll(thin, 2, 0)
        post[:2] = False
        mask &= ~(post | np.roll(post, -2, 0) & thin | np.roll(post, -1, 0) & thin)
    return mask


def open_mask(mask, min_area=120):
    """Apertura (erosión en cruz y dilatación dentro de la máscara): fuera las vigas y cantos de 1-2 px que tienen
    el tono del tejado; después, solo las manchas de al menos min_area px."""
    m = mask
    er = m & np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1)
    dil = er | np.roll(er, 1, 0) | np.roll(er, -1, 0) | np.roll(er, 1, 1) | np.roll(er, -1, 1)
    dil = dil | np.roll(dil, 1, 0) & m | np.roll(dil, -1, 0) & m  # recupera el borde de teja de 1 px
    out = dil & m
    # componentes
    H, W = out.shape
    seen = np.zeros_like(out)
    keep = np.zeros_like(out)
    for y in range(H):
        for x in range(W):
            if out[y, x] and not seen[y, x]:
                comp = []
                q = deque([(y, x)])
                seen[y, x] = True
                while q:
                    cy, cx = q.popleft()
                    comp.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and out[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
                if len(comp) >= min_area:
                    for c in comp:
                        keep[c] = True
    return keep


def roof_colors_mask(img, mask):
    """Todos los píxeles del sprite cuyo color sale en el tejado encontrado (incluye las tejas sueltas aisladas
    por el contorno), menos los que están por debajo del alero más bajo del relleno."""
    cols = set(map(tuple, img[mask][:, :3]))
    m = np.zeros(mask.shape, bool)
    ys = np.where(mask.any(1))[0]
    bottom = ys[-1] if len(ys) else img.shape[0]
    flat = img[..., :3]
    for c in cols:
        m |= np.all(flat == c, axis=-1)
    m &= img[..., 3] > 127
    m[bottom + 1:] = False
    return m


def window_mask(img):
    h, s, v = hsv(img[..., :3])
    return (img[..., 3] > 127) & (h > 165) & (h < 200) & (s > 0.3)


def recolor(img, changes, mask_from=None):
    out = img
    for what, ramp in changes:
        if what == "roof":
            m = roof_mask(mask_from if mask_from is not None else out)
            out = remap(out, m, ramp, 1, 7)
        elif what == "wall":
            h, s, v = hsv(out[..., :3])
            m = (out[..., 3] > 127) & (h > 30) & (h < 60) & (s > 0.45) & (v > 0.55)
            out = remap(out, m, ramp, 2, 7)
        elif what == "windows":
            out = remap(out, window_mask(out), ramp, 0, 5)
    return out


def temper(dry=False):
    for base, changes in (("house_f", [("wall", OCHRE_WALL), ("windows", WINDOW)]),
                          ("house_c", [("roof", TERRACOTTA), ("windows", WINDOW)])):
        for suffix in ("", "_back"):
            p = os.path.join(B, "escala_b", base + suffix + ".png")
            mf = MASK_FROM.get(base)
            out = recolor(load(p), changes, load(os.path.join(B, "escala_b", mf + suffix + ".png")) if mf else None)
            print("temper", os.path.relpath(p, ROOT))
            if not dry:
                Image.fromarray(out, "RGBA").save(p)


def roofs(dry=False):
    for vid, (base, changes) in VARIANTS.items():
        for suffix in ("", "_back"):
            src = os.path.join(B, "escala_b", base + suffix + ".png")
            dst = os.path.join(B, "escala_b", vid + suffix + ".png")
            mf = MASK_FROM.get(base)
            out = recolor(load(src), changes, load(os.path.join(B, "escala_b", mf + suffix + ".png")) if mf else None)
            print("roof", os.path.relpath(dst, ROOT), "from", base + suffix)
            if not dry:
                Image.fromarray(out, "RGBA").save(dst)


def sheet():
    names = ["house_a", "house_b", "house_c", "house_d", "house_e", "house_f"] + list(VARIANTS)
    ims = [Image.open(os.path.join(B, "escala_b", n + ".png")).convert("RGBA") for n in names]
    ims += [Image.open(os.path.join(B, "escala_b", n + "_back.png")).convert("RGBA") for n in list(VARIANTS)]
    W = sum(i.width + 6 for i in ims)
    H = max(i.height for i in ims)
    grass = Image.open(os.path.join(ROOT, "assets", "art", "tiles", "ground", "grass.png")).convert("RGBA")
    S = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    for x in range(0, W, grass.width):
        S.alpha_composite(grass.crop((0, 0, min(grass.width, W - x), min(grass.height, H))), (x, 0))
    x = 0
    for i in ims:
        S.alpha_composite(i, (x, H - i.height))
        x += i.width + 6
    os.makedirs(os.path.join(ROOT, "tmp", "ciudad2d"), exist_ok=True)
    S.save(os.path.join(ROOT, "tmp", "ciudad2d", "casas.png"))
    print("tmp/ciudad2d/casas.png", S.size)


def debug_masks():
    out = []
    for n in ["house_a", "house_b", "house_c", "house_f", "house_a_back", "house_b_back", "house_c_back"]:
        img = load(os.path.join(B, "escala_b", n + ".png"))
        m = roof_mask(load(os.path.join(B, "escala_b", MASK_FROM.get(n.replace("_back", ""), n.replace("_back", "")) + ("_back" if n.endswith("_back") else "") + ".png")))
        vis = img.copy()
        vis[m, :3] = [255, 0, 255]
        out.append(Image.fromarray(vis, "RGBA"))
    W = sum(i.width for i in out)
    S = Image.new("RGBA", (W, max(i.height for i in out)), (40, 40, 40, 255))
    x = 0
    for i in out:
        S.alpha_composite(i, (x, 0))
        x += i.width
    S.resize((S.width * 2, S.height * 2), Image.NEAREST).save(os.path.join(ROOT, "tmp", "ciudad2d", "roof_masks.png"))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    dry = "--dry" in sys.argv
    {"regrass": regrass, "temper": temper, "roofs": roofs}.get(cmd, lambda dry=False: None)(dry=dry) \
        if cmd in ("regrass", "temper", "roofs") else (sheet() if cmd == "sheet" else
                                                        debug_masks() if cmd == "masks" else print(__doc__))
