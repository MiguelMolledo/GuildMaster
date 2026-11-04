#!/usr/bin/env python3
"""Procesado local (Pillow, sin créditos) de las piezas del piloto de fal: cortar rejillas, quitar fondo plano,
reducir a la medida del juego y a una paleta limitada. Lo compara con fal-ai/image2pixel (tools/art/fal_piloto.py).

Uso:
  python3 tools/art/fal_procesar.py grid SRC DSTDIR NAME [--cols 2 --rows 2]
  python3 tools/art/fal_procesar.py pixel SRC DST --size WxH [--colors 32] [--mode box|dominant] [--bg white|green|none]
  python3 tools/art/fal_procesar.py native SRC DST --scale N          # baja una salida de image2pixel a su rejilla
  python3 tools/art/fal_procesar.py key SRC DST                       # retrato con los colores clave de 4.10.9
"""
import argparse
import colorsys
import os
import sys
from collections import Counter

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))


def split_grid(src, dst_dir, name, cols=2, rows=2, inset=0):
    im = Image.open(src).convert("RGBA")
    cw, ch = im.width // cols, im.height // rows
    os.makedirs(dst_dir, exist_ok=True)
    out = []
    for r in range(rows):
        for c in range(cols):
            cell = im.crop((c * cw + inset, r * ch + inset, (c + 1) * cw - inset, (r + 1) * ch - inset))
            p = os.path.join(dst_dir, f"{name}_{r * cols + c + 1}.png")
            cell.save(p)
            out.append(p)
    return out


def key_background(im, mode, tol=40):
    """Borra el fondo plano tocando los bordes (relleno por inundación desde el marco). white | green."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size

    def is_bg(c):
        r, g, b, a = c
        if mode == "white":
            return r > 255 - tol and g > 255 - tol and b > 255 - tol
        if mode == "green":
            return g > 150 and r < 130 and b < 130 and g - max(r, b) > 60
        return False

    seen = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        seen[y * w + x] = 1
        if not is_bg(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    if mode == "green":  # derrame verde en los bordes del recorte
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a and g > r + 30 and g > b + 30:
                    px[x, y] = (r, min(g, max(r, b) + 10), b, a)
    return im


def dominant_resize(im, size):
    """Cada píxel de salida = el color más frecuente de su bloque (como downscale_method=dominant)."""
    im = im.convert("RGBA")
    W, H = size
    out = Image.new("RGBA", size)
    src = im.load()
    o = out.load()
    for y in range(H):
        y0, y1 = int(y * im.height / H), max(int(y * im.height / H) + 1, int((y + 1) * im.height / H))
        for x in range(W):
            x0, x1 = int(x * im.width / W), max(int(x * im.width / W) + 1, int((x + 1) * im.width / W))
            cnt = Counter()
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    r, g, b, a = src[xx, yy]
                    cnt[(r >> 3, g >> 3, b >> 3, 255 if a > 127 else 0)] += 1
            (r, g, b, a), _ = cnt.most_common(1)[0]
            o[x, y] = (r << 3 | 4, g << 3 | 4, b << 3 | 4, a) if a else (0, 0, 0, 0)
    return out


def quantize(im, colors):
    im = im.convert("RGBA")
    alpha = im.getchannel("A").point(lambda a: 255 if a > 127 else 0)
    rgb = im.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def trim_fit(im, size, pad=0, anchor="center"):
    """Recorta al contenido opaco y lo encaja sin deformar en size (abajo si anchor=bottom)."""
    bb = im.getchannel("A").getbbox()
    if not bb:
        return im.resize(size)
    c = im.crop(bb)
    W, H = size[0] - 2 * pad, size[1] - 2 * pad
    k = min(W / c.width, H / c.height)
    return c, (max(1, round(c.width * k)), max(1, round(c.height * k)))


def pixel(src, dst, size, colors=32, mode="box", bg="none", fit=False, pad=0, anchor="center"):
    im = Image.open(src).convert("RGBA")
    if bg != "none":
        im = key_background(im, bg)
    canvas_size = size
    if fit:
        im, size = trim_fit(im, canvas_size, pad)
    if mode == "dominant":
        small = dominant_resize(im, size)
    else:
        small = im.resize(size, Image.BOX)
        a = small.getchannel("A").point(lambda v: 255 if v > 127 else 0)
        small.putalpha(a)
    small = quantize(small, colors)
    if fit:
        out = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        x = (canvas_size[0] - size[0]) // 2
        y = canvas_size[1] - size[1] - pad if anchor == "bottom" else (canvas_size[1] - size[1]) // 2
        out.alpha_composite(small, (x, y))
        small = out
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    small.save(dst)
    return dst


def native(src, dst, scale):
    im = Image.open(src).convert("RGBA")
    im.resize((im.width // scale, im.height // scale), Image.NEAREST).save(dst)


def key_portrait(src, dst):
    """Codifica la identidad de 4.10.9 como en tools/art/personajes_guild.py (alfa 254, región en azul, brillo en
    rojo): piel, pelo (oscuro arriba, no piel), ropa principal (rojos saturados) y secundaria (dorados)."""
    import personajes_guild as pg
    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    counts = Counter()
    vals = {pg.HAIR: [], pg.SKIN: [], pg.PRIMARY: [], pg.SECONDARY: []}
    regions = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            hh, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            hd = hh * 360
            rel = y / h
            reg = None
            if pg.is_skin(hd, s, v) and 0.15 < rel < 0.75:
                reg = pg.SKIN
            elif rel < 0.45 and 0.1 < v < 0.5 and s > 0.3 and (hd < 30 or hd > 340):
                reg = pg.HAIR
            elif rel > 0.5 and (hd < 12 or hd > 335) and s > 0.45 and v > 0.2:
                reg = pg.PRIMARY
            elif rel > 0.45 and 25 < hd < 60 and s > 0.6 and v > 0.3:
                reg = pg.SECONDARY
            if reg:
                regions[(x, y)] = (reg, v)
                vals[reg].append(v)
                counts[reg] += 1
    ref = {k: (sorted(v)[len(v) // 2] if v else 0.5) for k, v in vals.items()}
    for (x, y), (reg, v) in regions.items():
        shade = max(0.0, min(2.0, v / max(ref[reg], 0.01)))
        px[x, y] = (int(shade * 127.5), 0, reg * 50, 254)
    im.save(dst)
    return {k: counts[k] for k in counts}


def preview_key(src, dst, palettes):
    import personajes_guild as pg
    im = Image.open(src).convert("RGBA")
    tiles = [pg.unkey(im, None)] + [pg.unkey(im, p) for p in palettes]
    sheet = Image.new("RGBA", (im.width * len(tiles), im.height))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(t, (i * im.width, 0))
    sheet.save(dst)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("grid")
    g.add_argument("src")
    g.add_argument("dst_dir")
    g.add_argument("name")
    g.add_argument("--cols", type=int, default=2)
    g.add_argument("--rows", type=int, default=2)
    p = sub.add_parser("pixel")
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--size", required=True)
    p.add_argument("--colors", type=int, default=32)
    p.add_argument("--mode", default="box")
    p.add_argument("--bg", default="none")
    p.add_argument("--fit", action="store_true")
    p.add_argument("--pad", type=int, default=0)
    p.add_argument("--anchor", default="center")
    n = sub.add_parser("native")
    n.add_argument("src")
    n.add_argument("dst")
    n.add_argument("--scale", type=int, required=True)
    k = sub.add_parser("key")
    k.add_argument("src")
    k.add_argument("dst")
    a = ap.parse_args()
    if a.cmd == "grid":
        print(split_grid(a.src, a.dst_dir, a.name, a.cols, a.rows))
    elif a.cmd == "pixel":
        w, h = (int(v) for v in a.size.split("x"))
        print(pixel(a.src, a.dst, (w, h), a.colors, a.mode, a.bg, a.fit, a.pad, a.anchor))
    elif a.cmd == "native":
        native(a.src, a.dst, a.scale)
    else:
        print(key_portrait(a.src, a.dst))


if __name__ == "__main__":
    main()
