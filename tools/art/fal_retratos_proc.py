#!/usr/bin/env python3
"""Procesa los retratos de fal (tools/art/fal_retratos.py) a los del juego:

1. corta cada rejilla 2×2 y su mapa de regiones en celdas de 512;
2. 64 = busto: image2pixel a escala 8 de la celda; 32 = cara: image2pixel a escala 12 del recorte de cara
   (x 64-448, y 0-384 de la celda);
3. alinea la rejilla de image2pixel con la celda (busca el desfase que mejor casa) y vota la región de cada píxel en
   su bloque del mapa (pelo con barba y cejas, piel con labios y cuello, ropa principal, ropa secundaria, nada);
4. fondo transparente (lo pone el marco del retrato) y colores clave de GDD 4.10.9 codificados como en
   tools/art/personajes_guild.py: alfa 254, región en el azul (50 pelo, 100 piel, 150 ropa 1, 200 ropa 2) y brillo
   relativo en el rojo. El shader game/visuals/characters/identity_swap.gdshader los pinta. Los cargos y únicos solo
   marcan pelo y piel (su ropa es la suya).

Salida: assets/art/portraits/<id>.png (64) y <id>_32.png (32), y vistas sin codificar en
$GUILDMASTER_ARTE_CRUDOS/fal_produccion/retratos/natural/ para revisar.

Uso: python3 tools/art/fal_retratos_proc.py [--solo id1,id2] [--sin-i2p]
"""
import argparse
import colorsys
import os
import shutil
import sys
from types import SimpleNamespace

from PIL import Image

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import fal_retratos as fr  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import fal_rutas as fr_  # noqa: E402  (crudos fuera del repo)
P = fr_.produccion("retratos")
PILOT = fr_.piloto("retratos")
OUT = os.path.join(ROOT, "assets", "art", "portraits")
HAIR, SKIN, PRIMARY, SECONDARY = 1, 2, 3, 4
# Colores del mapa -> región. El mapa se cuantiza a las 8 esquinas del cubo RGB.
MASK_COLORS = {(255, 0, 255): HAIR, (255, 255, 0): SKIN, (0, 255, 255): PRIMARY, (0, 255, 0): SECONDARY}
CUBE = [(r, g, b) for r in (0, 255) for g in (0, 255) for b in (0, 255)]
FACE = (64, 0, 448, 384)


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def labels(mask):
    """Imagen 'P' con el índice del color del cubo más cercano."""
    pal = Image.new("P", (1, 1))
    flat = [v for c in CUBE for v in c] + [0] * (768 - 3 * len(CUBE))
    pal.putpalette(flat)
    return mask.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE)


def vote(lab, box, size):
    """Región ganadora de cada bloque: por cada región, su fracción en el bloque (reducción BOX) y la mayor."""
    crop = lab.crop(box)
    crop = Image.frombytes("L", crop.size, crop.tobytes())  # los índices de la paleta, no sus colores
    best = [[0] * size[0] for _ in range(size[1])]
    score = [[0] * size[0] for _ in range(size[1])]
    for idx, c in enumerate(CUBE):
        reg = MASK_COLORS.get(c, 0)
        frac = crop.point(lambda i, idx=idx: 255 if i == idx else 0).resize(size, Image.BOX)
        fp = frac.load()
        for y in range(size[1]):
            for x in range(size[0]):
                if fp[x, y] > score[y][x]:
                    score[y][x], best[y][x] = fp[x, y], reg
    return best


def i2p_native(src_im, dst, scale, colors):
    """image2pixel con escala fija; devuelve la imagen a su rejilla (cacheada en dst)."""
    if not os.path.exists(dst):
        tmp = dst + ".src.png"
        src_im.save(tmp)
        import fal_piloto
        fal_piloto.pixel(SimpleNamespace(piece="retratos", src=tmp, dst=dst, colors=colors, scale=scale, palette="",
                                         transparent=False))
        os.remove(tmp)
    up = Image.open(dst).convert("RGBA")
    return up.resize((up.width // scale, up.height // scale), Image.NEAREST)


def align(src, nat, s):
    """Desfase (ox, oy) de la rejilla de image2pixel dentro de src (mínima diferencia de medias por bloque)."""
    w, h = nat.size
    best = None
    ref = nat.convert("RGB")
    for oy in range(s):
        for ox in range(s):
            if ox + w * s > src.width or oy + h * s > src.height:
                continue
            m = src.crop((ox, oy, ox + w * s, oy + h * s)).convert("RGB").resize((w, h), Image.BOX)
            d = sum(abs(a - b) for pa, pb in zip(m.getdata(), ref.getdata()) for a, b in zip(pa, pb))
            if best is None or d < best[0]:
                best = (d, ox, oy)
    return best[1], best[2]


def build(cell, mask, s, size, nat, own):
    """Retrato a size×size: natural (RGBA, fondo transparente) y codificado."""
    ox, oy = align(cell, nat, s)
    w, h = nat.size
    regions = vote(labels(mask), (ox, oy, ox + w * s, oy + h * s), (w, h))
    cx, cy = (1 if ox >= s / 2 else 0), (1 if oy >= s / 2 else 0)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    reg = [[0] * size for _ in range(size)]
    np_ = nat.load()
    cp = canvas.load()
    for y in range(size):
        for x in range(size):
            sx = min(w - 1, max(0, x - cx))
            sy = min(h - 1, max(0, y - cy))
            cp[x, y] = np_[sx, sy][:3] + (255,)
            reg[y][x] = regions[sy][sx]
    # fondo: lo que no es región, es oscuro y toca el borde de arriba o de los lados (no el de abajo: la ropa)
    seen = set()
    stack = [(x, 0) for x in range(size)] + [(0, y) for y in range(size)] + [(size - 1, y) for y in range(size)]
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < size and 0 <= y < size):
            continue
        seen.add((x, y))
        r, g, b, a = cp[x, y]
        v = max(r, g, b) / 255
        if reg[y][x] or v > 0.2:
            continue
        cp[x, y] = (0, 0, 0, 0)
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    # la ropa que el mapa deja corta: crece a vecinos sin región de color parecido (de media altura hacia abajo)
    if not own:
        for k in (PRIMARY, SECONDARY):
            cols = sorted(cp[x, y][:3] for y in range(size) for x in range(size) if reg[y][x] == k and cp[x, y][3])
            if len(cols) < 8:
                continue
            med = tuple(sorted(c[i] for c in cols)[len(cols) // 2] for i in range(3))
            changed = True
            while changed:
                changed = False
                for y in range(int(size * 0.4), size):
                    for x in range(size):
                        if reg[y][x] or not cp[x, y][3]:
                            continue
                        c = cp[x, y][:3]
                        if max(c) < 30 or sum(abs(a - b) for a, b in zip(c, med)) > 90:
                            continue
                        if any(0 <= x + dx < size and 0 <= y + dy < size and reg[y + dy][x + dx] in (PRIMARY, SECONDARY)
                               for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                            reg[y][x] = k
                            changed = True
    natural = canvas.copy()
    allowed = {HAIR, SKIN} if own else {HAIR, SKIN, PRIMARY, SECONDARY}
    opaque = [[bool(cp[x, y][3]) for x in range(size)] for y in range(size)]
    clean_regions(reg, opaque, size)
    cloth_out_of_hair(reg, cp, size, own)
    vals = {k: [] for k in allowed}
    for y in range(size):
        for x in range(size):
            if cp[x, y][3] and reg[y][x] in allowed:
                vals[reg[y][x]].append(lum(cp[x, y]))
    refs = {k: (sorted(v)[len(v) // 2] if v else 128.0) for k, v in vals.items()}
    counts = {k: 0 for k in allowed}
    # oscuros por debajo del umbral de contorno: en el borde de una zona (tocan otra zona o el fondo) son el contorno
    # y se quedan negros; dentro del pelo o de la ropa son líneas o sombra del dibujo (rizos, moños, pliegues, un pelo
    # negro entero) y se tiñen como el resto, con un brillo mínimo, para que no salgan como motas negras con un tono
    # claro
    thr = {HAIR: 18, SKIN: 18, PRIMARY: 15, SECONDARY: 15}
    DARK_LINE = 0.35

    def on_edge(x, y, k):
        return any(not (0 <= x + dx < size and 0 <= y + dy < size) or not opaque[y + dy][x + dx]
                   or reg[y + dy][x + dx] != k for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    shades = {}
    for y in range(size):
        for x in range(size):
            r, g, b, a = cp[x, y]
            k = reg[y][x]
            if not a or k not in allowed:
                continue
            L = lum((r, g, b))
            if L < thr[k] and (k == SKIN or on_edge(x, y, k)):  # contorno (y ojos y boca en la piel): negro
                continue
            shade = L / max(1.0, refs[k])
            soft = (0.5 if refs[HAIR] > 40 else 0.9) if k == HAIR else 0.8  # un pelo negro tiene poco matiz: no se aplana
            shade = min(2.0, 1.0 + (shade - 1.0) * soft)
            if L < thr[k]:  # oscuro de dentro: relativo a su zona (un pelo negro entero sale del tono de la familia)
                shade = max(DARK_LINE, shade)
            shades[(x, y)] = (k, shade)
    # luz suelta: si un píxel brilla mucho más que la mediana de sus vecinos de la misma zona, toma la mediana (las
    # motas blancas al teñir con un tono claro); los oscuros no se tocan: son el dibujo
    out = {}
    for (x, y), (k, sh) in shades.items():
        nb = sorted(shades[(x + dx, y + dy)][1] for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                    if (dx or dy) and (x + dx, y + dy) in shades and shades[(x + dx, y + dy)][0] == k)
        if len(nb) >= 4 and sh > nb[len(nb) // 2] + 0.45:  # solo las luces sueltas; los oscuros son detalle
            sh = nb[len(nb) // 2]
        out[(x, y)] = (k, sh)
    for (x, y), (k, sh) in out.items():
        cp[x, y] = (int(round(sh * 127.5)), 0, k * 50, 254)
        counts[k] += 1
    return natural, canvas, counts


def cloth_out_of_hair(reg, cp, size, own):
    """Toca o pañuelo que el mapa marcó como pelo: si el pelo es poco saturado (negro, gris, blanco), sus píxeles de
    color tela (marrón u ocre saturado y claro) pasan a ropa secundaria (o sin zona en los cargos y únicos)."""
    hair = [(x, y) for y in range(size) for x in range(size) if reg[y][x] == HAIR and cp[x, y][3]]
    if len(hair) < 20:
        return 0
    hsv = {q: colorsys.rgb_to_hsv(*(c / 255 for c in cp[q[0], q[1]][:3])) for q in hair}
    sats = sorted(v[1] for v in hsv.values())
    if sats[len(sats) // 2] > 0.3:  # pelo castaño, rubio o pelirrojo: no se distingue de la tela por el color
        return 0
    moved = 0
    for (x, y), (h, sat, v) in hsv.items():
        if sat > 0.45 and v > 0.3 and 15 <= h * 360 <= 55:
            reg[y][x] = 0 if own else SECONDARY
            moved += 1
    return moved


def clean_regions(reg, opaque, size, max_island=3, max_gap=2):
    """Islas de 1-3 px de una zona dentro de otra: pasan a la zona vecina mayoritaria (8 vecinos). Huecos sin zona
    de 1-2 px rodeados por una sola zona de pelo o ropa: pasan a esa zona (en la piel no: son ojos y boca)."""
    seen = [[False] * size for _ in range(size)]
    for y0 in range(size):
        for x0 in range(size):
            if seen[y0][x0] or not opaque[y0][x0]:
                continue
            lab = reg[y0][x0]
            comp, st = [], [(x0, y0)]
            seen[y0][x0] = True
            while st:
                x, y = st.pop()
                comp.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < size and 0 <= ny < size and not seen[ny][nx] and opaque[ny][nx] \
                            and reg[ny][nx] == lab:
                        seen[ny][nx] = True
                        st.append((nx, ny))
            limit = max_island if lab else max_gap
            if len(comp) > limit:
                continue
            cs = set(comp)
            near = {}
            for x, y in comp:
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if (dx or dy) and 0 <= nx < size and 0 <= ny < size and (nx, ny) not in cs \
                                and opaque[ny][nx]:
                            near[reg[ny][nx]] = near.get(reg[ny][nx], 0) + 1
            if not near:
                continue
            best = max(near.items(), key=lambda kv: kv[1])[0]
            if lab:
                if best != lab:
                    for x, y in comp:
                        reg[y][x] = best
            elif len(near) == 1 and best in (HAIR, PRIMARY, SECONDARY):
                for x, y in comp:
                    reg[y][x] = best


def cells_of(path):
    im = Image.open(path).convert("RGBA")
    cw, ch = im.width // 2, im.height // 2
    return [im.crop(((i % 2) * cw, (i // 2) * ch, (i % 2 + 1) * cw, (i // 2 + 1) * ch)).resize((512, 512))
            for i in range(4)]


def sources():
    """(id, celda, celda del mapa, ruta i2p 64, ruta i2p 32) de los 80 retratos."""
    out = []
    for g, cells in fr.GRIDS.items():
        src = os.path.join(P, "crudo", g + ".png")
        msk = os.path.join(P, "crudo", g + "_mascara.png")
        if not (os.path.exists(src) and os.path.exists(msk)):
            continue
        for (pid, _, _), c, m in zip(cells, cells_of(src), cells_of(msk)):
            own_mask = os.path.join(P, "crudo", pid + "_mascara.png")  # mapa repetido solo para esta celda
            if os.path.exists(own_mask):
                m = Image.open(own_mask).convert("RGBA").resize((512, 512), Image.NEAREST)
            out.append((pid, c, m, os.path.join(P, "i2p", pid + "_s8.png"), os.path.join(P, "i2p", pid + "_cara_s12.png")))
    old = {"grid_nano2_v1": ["artesano", "artesana", "anciano", "rival"],
           "grid2_nano2_v1": ["nina", "trabajador", "anciana", "rival_esposa"]}
    for g, ids in fr.PILOT.items():
        src = os.path.join(PILOT, "crudo", g + ".png")
        msk = os.path.join(P, "crudo", g + "_mascara.png")
        if not os.path.exists(msk):
            continue
        for pid, oldn, c, m in zip(ids, old[g], cells_of(src), cells_of(msk)):
            a = os.path.join(P, "i2p", pid + "_s8.png")
            b = os.path.join(P, "i2p", pid + "_cara_s12.png")
            for mine, theirs in ((a, f"nano2_{oldn}_s8.png"), (b, f"nano2_{oldn}_cara_s12.png")):
                t = os.path.join(PILOT, "i2p", theirs)
                if not os.path.exists(mine) and os.path.exists(t):
                    os.makedirs(os.path.dirname(mine), exist_ok=True)
                    shutil.copy(t, mine)
                    shutil.copy(t + ".json", mine + ".json")
            out.append((pid, c, m, a, b))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--solo", default="")
    a = ap.parse_args()
    want = set(x for x in a.solo.split(",") if x)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(P, "natural"), exist_ok=True)
    os.makedirs(os.path.join(P, "i2p"), exist_ok=True)
    for pid, cell, mask, i64, i32 in sources():
        if want and pid not in want:
            continue
        own = pid in fr.OWN_CLOTHES
        nat64 = i2p_native(cell, i64, 8, 32)
        n64, k64, c64 = build(cell, mask, 8, 64, nat64, own)
        face, fmask = cell.crop(FACE), mask.crop(FACE)
        nat32 = i2p_native(face, i32, 12, 24)
        n32, k32, c32 = build(face, fmask, 12, 32, nat32, own)
        k64.save(os.path.join(OUT, pid + ".png"))
        k32.save(os.path.join(OUT, pid + "_32.png"))
        n64.save(os.path.join(P, "natural", pid + ".png"))
        n32.save(os.path.join(P, "natural", pid + "_32.png"))
        print(f"{pid}: 64 {c64} · 32 {c32}")


if __name__ == "__main__":
    main()
