#!/usr/bin/env python3
"""Kit de página (docs/ui/04_kit_de_pagina.md): genera con fal, pasa a píxel, dibuja las máscaras, mide y escribe
assets/art/ui/page_kit/kit.json. Las ideas y los algoritmos vienen del kit de Publicación de RolApp
(src/lib/publication/: kit-slots, nine-slice, safe-area, masks, veil, kit-variants), pasados a pixel art.

Uso:
  python3 tools/art/kit_pagina.py ref                         # hoja de referencia con el kit actual a ×8
  python3 tools/art/kit_pagina.py gen SLOT NAME [--count 1] [--aspect 4:3] [--extra "..."]   # nano-banana-2/edit
  python3 tools/art/kit_pagina.py tile SLOT NAME [--extra "..."]                            # z-image/turbo/tiling
  python3 tools/art/kit_pagina.py pixel SLOT RAW N [--crop x0,y0,x1,y1]   # crudo → <slot>_<N>.png a su tamaño
  python3 tools/art/kit_pagina.py masks                       # máscaras de pincel y velo (Pillow, gratis)
  python3 tools/art/kit_pagina.py measure                     # mide cada pieza y escribe kit.json
  python3 tools/art/kit_pagina.py sheet [--out tmp/kit_pagina/galeria.png]
  python3 tools/art/kit_pagina.py total                       # gasto de fal apuntado

Cada llamada a fal se apunta en assets/art/ui/page_kit/gasto.json (fecha, hueco, modelo, imágenes, coste) y su
prompt en assets/art/ui/page_kit/prompts.log. La clave sale de .env (FAL_KEY) y no se imprime nunca. El crudo va a
tmp/kit_pagina/crudo/ (fuera de git: se regenera con el prompt apuntado).
"""
import argparse
import datetime
import json
import math
import os
import random
import sys
import time
import urllib.request
from collections import Counter

from PIL import Image

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art", "ui", "page_kit")
RAW = os.path.join(ROOT, "tmp", "kit_pagina", "crudo")
LEDGER = os.path.join(OUT, "gasto.json")
PROMPTS = os.path.join(OUT, "prompts.log")
KIT = os.path.join(OUT, "kit.json")
THEME = os.path.join(ROOT, "assets", "art", "ui", "theme")
MARKS = os.path.join(ROOT, "assets", "art", "ui", "marks")

NANO_EDIT = "fal-ai/nano-banana-2/edit"
TILING = "fal-ai/z-image/turbo/tiling"
I2P = "fal-ai/image2pixel"
# nano por imagen; z-image 0,02 USD/MP a 1024×1024; image2pixel por segundo de cómputo (cota alta: con la cola)
PRICE = {NANO_EDIT: 0.08, TILING: 0.02 * 1.048576, I2P: 0.00017}

# --- Huecos (kit-slots.ts en píxel) ------------------------------------------------------------------------------------
# size: tamaño de referencia (las piezas generadas salen a la rejilla nativa del modelo: ver kit.json) · bg: opaque | transparent · measure: qué se mide · rotation: page | element |
# image (kit-variants.ts) · aspect: el que se pide a nano-banana.
SLOTS = {
    "page_bg": {"size": (512, 384), "bg": "opaque", "measure": "page", "rotation": "page", "aspect": "4:3"},
    "page_bg_tall": {"size": (384, 512), "bg": "opaque", "measure": "page", "rotation": "page", "aspect": "3:4"},
    "page_bg_dark": {"size": (512, 384), "bg": "opaque", "measure": "page", "rotation": "page", "aspect": "4:3"},
    "plate_frame": {"size": (200, 148), "bg": "transparent", "measure": "nine", "rotation": "element",
                    "aspect": "4:3"},
    "box_frame": {"size": (200, 148), "bg": "transparent", "measure": "nine", "rotation": "element", "aspect": "4:3"},
    "page_corner": {"size": (32, 32), "bg": "transparent", "measure": "bbox", "rotation": "page", "aspect": "1:1"},
    "ribbon": {"size": (224, 32), "bg": "transparent", "measure": "ribbon", "rotation": "element", "aspect": "21:9"},
    "divider": {"size": (192, 12), "bg": "transparent", "measure": "bbox", "rotation": "element", "aspect": "21:9"},
    "tile_light": {"size": (64, 64), "bg": "opaque", "measure": "none", "rotation": "element"},
    "tile_dark": {"size": (64, 64), "bg": "opaque", "measure": "none", "rotation": "element"},
    "folio": {"size": (96, 24), "bg": "transparent", "measure": "folio", "rotation": "page", "aspect": "21:9"},
    "mask_foot_240": {"size": (240, 135), "bg": "mask", "measure": "none", "rotation": "image"},
    "mask_foot_192": {"size": (192, 108), "bg": "mask", "measure": "none", "rotation": "image"},
    "mask_corner": {"size": (64, 64), "bg": "mask", "measure": "none", "rotation": "image"},
    "mask_side": {"size": (64, 64), "bg": "mask", "measure": "none", "rotation": "image"},
    "veil": {"size": (480, 96), "bg": "mask", "measure": "none", "rotation": "image"},
}

STYLE = ("16-bit SNES era pixel art, crisp hard-edged pixels, no anti-aliasing, no blur, limited warm palette of the "
         "reference sheet: dark brown ink #2a1f14, wood browns #3e2814 #5c3a1e #7a5230, parchment #d4b896 #b89a72, "
         "gold #8a7032 #c8a84e #f2d880, wax red #9a2a22. Medieval guild account book, illuminated manuscript "
         "ornament. Match the pixel style of the reference sheet (the game's current UI kit)")
KEY = "on a perfectly flat solid magenta #FF00FF background that fills everything around the piece"
NO_TEXT = "no text, no letters, no numbers, no watermark"
BG_RULES = ("Mandatory composition: the central area (at least 80% of the width and 80% of the height, centred) is "
            "clean, flat, light uniform parchment with only very faint fibres, NO objects, NO figures, NO strong stains "
            "and NO text, so dark body text stays perfectly readable; ageing (darker burnt edges, small stains, wear) "
            "and any small ornament stay strictly inside an outer band no wider than 10% of the width on the left and "
            "right and 10% of the height at the top and bottom; NO frame or border line enclosing the page")
PIECE = {
    "page_bg": "A single sheet of blank aged parchment paper seen flat from above, filling the whole image edge to "
               "edge, landscape. " + BG_RULES,
    "page_bg_tall": "A single sheet of blank aged parchment paper seen flat from above, filling the whole image edge to "
                    "edge, portrait. " + BG_RULES,
    "page_bg_dark": "A single sheet of blank dark brown tooled leather seen flat from above, filling the whole image "
                    "edge to edge, landscape. " + BG_RULES.replace("light uniform parchment", "dark uniform leather")
                    .replace("dark body text", "light body text"),
    "plate_frame": "A single rectangular ornamental picture frame seen perfectly front-on, perfectly symmetric, "
                   "landscape. "
                   "Carved dark wood bars with a thin gold fillet, elaborate gold filigree ornaments ONLY in the four "
                   "corners (the same motif in each corner, about 14% of the height). The four straight edges between "
                   "the corners are plain, thin and uniform (a simple double bar about 3% of the height thick), with no "
                   "ornaments in the middle of the edges. The inside of the frame is completely empty magenta",
    "box_frame": "A single thin rectangular border for a boxed note on a book page, seen perfectly front-on, perfectly "
                 "symmetric, landscape, filling the whole image. "
                 "A very thin dark brown ink line doubled by a thin gold line (together about 2% of the height), "
                 "with a small gold filigree knot ONLY in each of the four corners (the same small motif in each "
                 "corner, about 8% of the height). The four straight edges between the corners are plain, thin and "
                 "uniform, with no ornaments in the middle of the edges. The inside is completely empty magenta",
    "page_corner": "A single top-left corner ornament for an illuminated book page border: an L-shaped gold and dark "
                   "brown filigree piece whose two arms extend to the right and downwards and taper into thin lines, "
                   "with a small diamond knot at the corner joint. Only the ornament, nothing else",
    "ribbon": "A blank horizontal red cloth ribbon banner for a book chapter heading, seen front-on, very wide and "
              "thin. Folded swallow-tail end caps at both ends with a darker fold; the long middle part is flat, plain, "
              "uniform red with a thin gold edge line at the top and the bottom, so a word can sit on it. Empty",
    "divider": "A horizontal decorative divider ornament for a book, very wide and very thin, symmetric: a small gold "
               "diamond motif in the center with fine dark gold filigree lines extending left and right and tapering "
               "to points",
    "folio": "A small symmetric gold cartouche, a compact horizontal plaque with rolled scroll ends and an empty flat "
             "light parchment center where a short label goes, very wide and short",
    "tile_light": "Seamless tileable light parchment paper texture, subtle fibres and faint warm stains, even lighting, "
                  "flat top-down, no objects, no text, 16-bit pixel art with chunky pixels and a small warm palette "
                  "(#d4b896, #c6a984, #b89a72, #e2cba5)",
    "tile_dark": "Seamless tileable dark brown tooled leather texture, fine grain, even lighting, flat top-down, no "
                 "objects, no text, 16-bit pixel art with chunky pixels and a small palette (#2a1f14, #3e2814, "
                 "#5c3a1e, #33271c)",
}


def hexc(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def _mix(a, b, t=0.5):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def palette():
    """Paleta de página: los tokens de tools/ui/tokens.json y sus tonos intermedios (sin colores nuevos)."""
    with open(os.path.join(ROOT, "tools", "ui", "tokens.json")) as f:
        c = {k: hexc(v) for k, v in json.load(f)["color"].items()}
    ramps = [
        ["hueco", "seccion", "fila", "madera_oscura", "madera", "madera_clara", "pergamino_oscuro", "pergamino",
         "texto"],
        ["oro_oscuro", "oro", "oro_claro"],
        ["remache", "texto_tenue"],
    ]
    out = list(dict.fromkeys(c[k] for k in c if k not in ("info", "positivo", "aviso")))
    for r in ramps:
        for a, b in zip(r, r[1:]):
            out.append(_mix(c[a], c[b]))
    out.append(_mix(c["lacre"], c["hueco"], 0.35))  # lacre oscuro (sombra de la cinta)
    out.append(_mix(c["lacre"], c["oro_claro"], 0.3))  # lacre claro (luz de la cinta)
    out.append(_mix(c["pergamino"], c["texto"], 0.5))  # pergamino claro
    return list(dict.fromkeys(out))


def _nearest(rgb, pal, cache):
    v = cache.get(rgb)
    if v is None:
        r, g, b = rgb
        best, bd = None, 1e18
        for p in pal:
            dr, dg, db = r - p[0], g - p[1], b - p[2]
            d = 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
            if d < bd:
                best, bd = p, d
        cache[rgb] = v = best
    return v


# --- fal --------------------------------------------------------------------------------------------------------------

def _ledger():
    if os.path.exists(LEDGER):
        with open(LEDGER) as f:
            return json.load(f)
    return []


def _note(slot, model, images, usd, what):
    rows = _ledger()
    rows.append({"fecha": datetime.datetime.now().isoformat(timespec="seconds"), "hueco": slot, "modelo": model,
                 "imagenes": images, "usd": round(usd, 4), "que": what})
    os.makedirs(OUT, exist_ok=True)
    with open(LEDGER, "w") as f:
        json.dump(rows, f, indent=1, ensure_ascii=False)


def _fal():
    from dotenv import load_dotenv
    load_dotenv(os.path.join(ROOT, ".env"))
    import fal_client
    return fal_client


def _prompt_log(name, model, prompt, extra=""):
    for path in (os.path.join(RAW, "prompts.log"), PROMPTS):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a") as f:
            f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {name} | {model} | {extra}\n  {prompt}\n\n")


def ref_sheet():
    """Hoja de referencia: el kit actual a ×8 sobre magenta (lo que nano-banana tiene que imitar)."""
    parts = [Image.open(os.path.join(THEME, n + ".png")).convert("RGBA") for n in
             ("panel", "parchment", "divider", "tab_on", "button_normal")]
    parts += [Image.open(os.path.join(MARKS, n + ".png")).convert("RGBA") for n in
              ("seal", "badge_title_noble", "badge_office_mayor")]
    k = 8
    W = sum(p.width * k for p in parts) + 16 * (len(parts) + 1)
    H = max(p.height * k for p in parts) + 32
    sheet = Image.new("RGBA", (W, H), (255, 0, 255, 255))
    x = 16
    for p in parts:
        sheet.alpha_composite(p.resize((p.width * k, p.height * k), Image.NEAREST), (x, 16))
        x += p.width * k + 16
    os.makedirs(RAW, exist_ok=True)
    path = os.path.join(RAW, "ref_kit_x8.png")
    sheet.save(path)
    return path


def gen(slot, name, count=1, aspect=None, extra=""):
    fal = _fal()
    d = SLOTS[slot]
    prompt = f"{PIECE[slot]}. Style: {STYLE}. {NO_TEXT}."
    if d["bg"] == "transparent":
        prompt += f" Isolated, {KEY}."
    if extra:
        prompt += " " + extra
    ref = ref_sheet()
    args = {"prompt": prompt, "num_images": count, "output_format": "png", "image_urls": [fal.upload_file(ref)],
            "aspect_ratio": aspect or d.get("aspect", "1:1")}
    cost = PRICE[NANO_EDIT] * count
    print(f"{NANO_EDIT} | {slot} {name} | {count} img | {cost:.3f} USD (llevamos {total():.3f})")
    res = fal.subscribe(NANO_EDIT, arguments=args)
    paths = _save(res, name, count)
    _note(slot, NANO_EDIT, len(paths), PRICE[NANO_EDIT] * len(paths), name)
    _prompt_log(name, NANO_EDIT, prompt, f"aspect={args['aspect_ratio']} ref=ref_kit_x8.png")
    return paths


def tile(slot, name, extra=""):
    fal = _fal()
    prompt = PIECE[slot] + (". " + extra if extra else "")
    args = {"prompt": prompt, "tiling_mode": "both", "image_size": {"width": 1024, "height": 1024},
            "num_inference_steps": 8, "output_format": "png", "num_images": 1}
    print(f"{TILING} | {slot} {name} | {PRICE[TILING]:.3f} USD (llevamos {total():.3f})")
    res = fal.subscribe(TILING, arguments=args)
    paths = _save(res, name, 1)
    _note(slot, TILING, len(paths), PRICE[TILING] * len(paths), name)
    _prompt_log(name, TILING, prompt, "tiling_mode=both 1024")
    return paths


def _save(res, name, count):
    os.makedirs(RAW, exist_ok=True)
    out = []
    for i, im in enumerate(res.get("images", [])):
        p = os.path.join(RAW, f"{name}{'_' + str(i + 1) if count > 1 else ''}.png")
        urllib.request.urlretrieve(im["url"], p)
        out.append(p)
        print("  ->", os.path.relpath(p, ROOT))
    return out


def total():
    return round(sum(r["usd"] for r in _ledger()), 4)


# --- Píxel ------------------------------------------------------------------------------------------------------------

def _is_key(r, g, b):
    """Magenta y su mezcla con el borde de la pieza (el modelo deja un halo rosado)."""
    return r > 110 and b > 110 and g < 0.62 * min(r, b) and abs(r - b) < 100


def key_magenta(im):
    """Magenta → transparente (todo píxel magenta, no solo el conexo: el interior del marco también es fondo)."""
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if _is_key(r, g, b):
                px[x, y] = (0, 0, 0, 0)
    return im


def key_white_outside(im, tol=30):
    """El blanco que rodea el papel rasgado (conexo con el borde) → transparente: la página es la silueta del papel."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    seen = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        seen[y * w + x] = 1
        r, g, b, a = px[x, y]
        if a > 127 and not (r > 255 - tol and g > 255 - tol and b > 255 - tol):
            continue
        px[x, y] = (0, 0, 0, 0)
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return im


def dominant(im, size):
    """Cada píxel de salida = el color más frecuente de su bloque (los transparentes cuentan como uno más)."""
    im = im.convert("RGBA")
    W, H = size
    out = Image.new("RGBA", size)
    src = im.load()
    o = out.load()
    for y in range(H):
        y0 = int(y * im.height / H)
        y1 = max(y0 + 1, int((y + 1) * im.height / H))
        for x in range(W):
            x0 = int(x * im.width / W)
            x1 = max(x0 + 1, int((x + 1) * im.width / W))
            cnt = Counter()
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    r, g, b, a = src[xx, yy]
                    cnt[(r >> 3, g >> 3, b >> 3) if a > 127 else None] += 1
            c, _ = cnt.most_common(1)[0]
            o[x, y] = (c[0] << 3 | 4, c[1] << 3 | 4, c[2] << 3 | 4, 255) if c is not None else (0, 0, 0, 0)
    return out


TILE_RAMPS = {"tile_light": ["b89a72", "c6a984", "d4b896", "e0c9a4"],
              "tile_dark": ["1a1209", "2a1f14", "33271c", "3e2814"]}


def ramp(im, colors, weights=(0.12, 0.3, 0.42, 0.16)):
    """Textura → una rampa de 4 tonos de la paleta por cuantiles de luminancia (el modelo no respeta la paleta)."""
    im = im.convert("RGB")
    lum = sorted(_lum(*p) for p in im.getdata())
    cuts, acc = [], 0.0
    for w in weights[:-1]:
        acc += w
        cuts.append(lum[min(len(lum) - 1, int(acc * len(lum)))])
    cols = [hexc(c) for c in colors]
    out = Image.new("RGBA", im.size)
    o = out.load()
    src = im.load()
    for y in range(im.height):
        for x in range(im.width):
            v = _lum(*src[x, y])
            i = sum(1 for c in cuts if v > c)
            o[x, y] = cols[i] + (255,)
    return out


def to_palette(im, pal=None):
    pal = pal or palette()
    im = im.convert("RGBA")
    px = im.load()
    cache = {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = _nearest((r, g, b), pal, cache) + (255,)
    return im


def content_box(im):
    bb = im.getchannel("A").point(lambda a: 255 if a > 127 else 0).getbbox()
    return bb or (0, 0, im.width, im.height)


def snap(raw):
    """La imagen de nano-banana ya es pixel art con su píxel a 5-8 px. fal-ai/image2pixel (snap_grid, cobrado por
    segundo) detecta ese tamaño y devuelve la imagen alineada a su rejilla; se guarda junto al crudo
    (<crudo>.i2p.png + .scale.json) para no volver a pagarla. Devuelve (ruta alineada, tamaño del píxel)."""
    side, snapped = raw + ".scale.json", raw + ".i2p.png"
    if os.path.exists(side) and os.path.exists(snapped):
        with open(side) as f:
            return snapped, int(json.load(f)["pixel_scale"])
    fal = _fal()
    args = {"image_url": fal.upload_file(raw), "max_colors": 32, "snap_grid": True, "transparent_background": False,
            "cleanup_jaggy": True, "trim_borders": False}
    t0 = time.time()
    res = fal.subscribe(I2P, arguments=args)
    secs = time.time() - t0
    _note("snap", I2P, 1, PRICE[I2P] * secs, "image2pixel " + os.path.basename(raw))
    url = (res.get("images") or [{}])[0].get("url") or (res.get("image") or {}).get("url")
    urllib.request.urlretrieve(url, snapped)
    with open(side, "w") as f:
        json.dump({"pixel_scale": res.get("pixel_scale"), "num_colors": res.get("num_colors")}, f)
    return snapped, int(res.get("pixel_scale") or 1)


def half_keep_lines(im):
    """Mitad de tamaño sin perder las líneas finas: cada bloque 2×2 con algo opaco da su color opaco más frecuente."""
    W, H = im.width // 2, im.height // 2
    out = Image.new("RGBA", (W, H))
    src, o = im.load(), out.load()
    for y in range(H):
        for x in range(W):
            cnt = Counter(src[x * 2 + i, y * 2 + j] for i in (0, 1) for j in (0, 1) if src[x * 2 + i, y * 2 + j][3] > 127)
            o[x, y] = cnt.most_common(1)[0][0] if cnt else (0, 0, 0, 0)
    return out


def native(im, s):
    """Baja una imagen alineada a su rejilla a la resolución nativa: el centro de cada bloque s×s."""
    w, h = im.width // s, im.height // s
    out = Image.new("RGBA", (w, h))
    src, o = im.load(), out.load()
    for y in range(h):
        for x in range(w):
            o[x, y] = src[x * s + s // 2, y * s + s // 2]
    return out


def pixel(slot, raw, n, crop=None, scale=None):
    """Crudo → assets/art/ui/page_kit/<slot>_<n>.png en la paleta de página. Las piezas a la rejilla nativa de la
    imagen (×1: marco, cinta, separador, esquina, cartucho; ×2 los fondos, que se ven en grande), las texturas
    reducidas a 64×64 y, si el hueco tiene tamaño fijo y la nativa no cuadra, al tamaño del hueco."""
    d = SLOTS[slot]
    im = Image.open(raw).convert("RGBA")
    if slot.startswith("tile_"):
        small = im.resize(d["size"], Image.BOX)  # 1024 → 64: factor entero, el BOX conserva el «sin costuras»
        small = ramp(small, TILE_RAMPS[slot])
        small.save(os.path.join(OUT, f"{slot}_{n}.png"))
        print("  ->", os.path.relpath(os.path.join(OUT, f"{slot}_{n}.png"), ROOT), small.size)
        return os.path.join(OUT, f"{slot}_{n}.png")
    else:
        if scale:
            s = scale
        else:
            snapped, s = snap(raw)
            im = Image.open(snapped).convert("RGBA")
        if crop:
            im = im.crop(crop)
        small = native(im, s)
        if d["bg"] == "transparent":
            small = key_magenta(small)
            small = small.crop(content_box(small))
            if slot == "page_corner" and small.width > 64:
                small = half_keep_lines(small)
        elif slot.startswith("page_bg"):
            small = key_white_outside(small)
            small = small.resize((small.width * 2, small.height * 2), Image.NEAREST)
    small = to_palette(small)
    if slot == "box_frame":
        small = normalize_frame(small)
    elif slot == "ribbon":
        small = normalize_ribbon(small)
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"{slot}_{n}.png")
    small.save(dst)
    print("  ->", os.path.relpath(dst, ROOT), small.size)
    return dst


# --- Medidas (nine-slice.ts, safe-area.ts) ----------------------------------------------------------------------------

UMBRAL = 64


def _alpha(im):
    a = im.convert("RGBA").getchannel("A")
    return a.width, a.height, list(a.getdata())


def _depth(W, H, A, side, i, th=UMBRAL):
    lim = W >> 1 if side in ("left", "right") else H >> 1
    last = -1
    for d in range(lim):
        if side == "left":
            x, y = d, i
        elif side == "right":
            x, y = W - 1 - d, i
        elif side == "top":
            x, y = i, d
        else:
            x, y = i, H - 1 - d
        if A[y * W + x] >= th:
            last = d
    return last + 1


def _median(v):
    s = sorted(v)
    return s[len(s) >> 1] if s else 0


def measure_nine(im, th=UMBRAL):
    """Corte de 9 trozos de un marco (nine-slice.ts): listón en la franja central de cada arista; esquina recorriendo la
    arista mientras el adorno sea más grueso que el listón. None si no parece un marco."""
    W, H, A = _alpha(im)
    if W < 16 or H < 16:
        return None
    tot = opq = 0
    for y in range(int(H * 0.4), math.ceil(H * 0.6)):
        for x in range(int(W * 0.4), math.ceil(W * 0.6)):
            tot += 1
            opq += A[y * W + x] >= th
    if tot == 0 or opq / tot > 0.2:
        return None

    def band(n):
        return range(int(n * 0.42), math.ceil(n * 0.58))
    bar = {"left": _median([_depth(W, H, A, "left", y) for y in band(H)]),
           "right": _median([_depth(W, H, A, "right", y) for y in band(H)]),
           "top": _median([_depth(W, H, A, "top", x) for x in band(W)]),
           "bottom": _median([_depth(W, H, A, "bottom", x) for x in band(W)])}
    if min(bar.values()) == 0:
        return None

    def ext(side, start):
        n = H if side in ("left", "right") else W
        top = bar[side] * 1.2 + 1
        last = 0
        for k in range(n >> 1):
            i = k if start else n - 1 - k
            if _depth(W, H, A, side, i) > top:
                last = k + 1
        return last
    margin = 1  # en píxel el antialias no existe: 1 px de aire basta
    sl = {"top": max(ext("left", True), ext("right", True)), "bottom": max(ext("left", False), ext("right", False)),
          "left": max(ext("top", True), ext("bottom", True)), "right": max(ext("top", False), ext("bottom", False))}
    lim = {"top": H * 45 // 100, "bottom": H * 45 // 100, "left": W * 45 // 100, "right": W * 45 // 100}
    sl = {k: min(lim[k], max(sl[k], bar[k]) + margin) for k in sl}
    return {"slice": sl, "bar": bar, "width": W, "height": H}


def normalize_frame(im):
    """Rehace las aristas del marco repitiendo su columna/fila central y vacía el centro: estirarlo no deja saltos."""
    m = measure_nine(im)
    if not m:
        return im
    s = m["slice"]
    W, H = im.size
    px = im.load()
    cx, cy = W // 2, H // 2
    for y in range(0, H):
        if s["top"] <= y < H - s["bottom"]:
            for x in range(0, s["left"]):
                px[x, y] = px[x, cy]
            for x in range(W - s["right"], W):
                px[x, y] = px[x, cy]
            for x in range(s["left"], W - s["right"]):
                px[x, y] = (0, 0, 0, 0)
    for x in range(s["left"], W - s["right"]):
        for y in range(0, s["top"]):
            px[x, y] = px[cx, y]
        for y in range(H - s["bottom"], H):
            px[x, y] = px[cx, y]
    return im


def _col(im, x):
    return [im.getpixel((x, y)) for y in range(im.height)]


def measure_ribbon(im):
    """Remates de la cinta (columnas desde cada lado que no son iguales a la columna central) y la franja del texto
    (filas opacas de la columna central entre las dos líneas de borde)."""
    W, H = im.size
    mid = _col(im, W // 2)
    left = 0
    for x in range(W * 45 // 100):
        if _col(im, x) != mid:
            left = x + 1
    right = 0
    for k in range(W * 45 // 100):
        if _col(im, W - 1 - k) != mid:
            right = k + 1
    rows = [y for y, p in enumerate(mid) if p[3] > 127]
    top, bottom = (rows[0], H - 1 - rows[-1]) if rows else (0, 0)
    # la franja del texto: el tramo más largo de un mismo color en la columna central (la tela lisa)
    best = (0, 0)
    y = 0
    while y < H:
        if mid[y][3] < 128:
            y += 1
            continue
        z = y
        while z + 1 < H and mid[z + 1][:3] == mid[y][:3]:
            z += 1
        if z - y > best[1] - best[0]:
            best = (y, z)
        y = z + 1
    return {"cap": {"left": left, "right": right}, "edge": {"top": top, "bottom": bottom},
            "text": {"top": best[0], "bottom": H - 1 - best[1]}, "width": W, "height": H}


def normalize_ribbon(im):
    m = measure_ribbon(im)
    W, H = im.size
    px = im.load()
    mid = _col(im, W // 2)
    for x in range(m["cap"]["left"], W - m["cap"]["right"]):
        for y in range(H):
            px[x, y] = mid[y]
    return im


def measure_folio(im):
    """Hueco del cartucho: el tramo del color del centro en la fila y en la columna centrales."""
    W, H = im.size
    c = im.getpixel((W // 2, H // 2))
    x0 = x1 = W // 2
    while x0 > 0 and im.getpixel((x0 - 1, H // 2)) == c:
        x0 -= 1
    while x1 < W - 1 and im.getpixel((x1 + 1, H // 2)) == c:
        x1 += 1
    y0 = y1 = H // 2
    while y0 > 0 and im.getpixel((W // 2, y0 - 1)) == c:
        y0 -= 1
    while y1 < H - 1 and im.getpixel((W // 2, y1 + 1)) == c:
        y1 += 1
    if x1 - x0 < W // 4:  # sin hueco liso: el 60 % central
        x0, x1, y0, y1 = W // 5, W - W // 5 - 1, H // 5, H - H // 5 - 1
    return {"hole": {"left": x0, "top": y0, "right": W - 1 - x1, "bottom": H - 1 - y1}, "paper": "#%02x%02x%02x" % c[:3],
            "width": W, "height": H}


def bbox_measure(im):
    bb = content_box(im)
    return {"bbox": list(bb), "width": im.width, "height": im.height}


# Zona segura (safe-area.ts): ocupación por color y por detalle en una versión reducida (≈ 96 de ancho).
UMBRAL_COLOR, UMBRAL_COLOR_ORNAMENTO, UMBRAL_DETALLE = 58, 95, 15
PERFIL_OCUPADO, BUSQUEDA_MAX, AIRE = 0.12, 0.45, 0.02


def _lum(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def occupancy(im):
    W, H = im.size
    data = list(im.convert("RGB").getdata())
    Y = [_lum(*p) for p in data]
    cs = [data[y * W + x] for y in range(int(H * 0.35), math.ceil(H * 0.65)) for x in range(int(W * 0.35),
                                                                                           math.ceil(W * 0.65))]
    paper = tuple(_median([c[i] for c in cs]) for i in range(3))
    occ, orn = [0.0] * (W * H), [0.0] * (W * H)
    for y in range(H):
        for x in range(W):
            i = y * W + x
            dr, dg, db = (data[i][k] - paper[k] for k in range(3))
            color = math.sqrt((dr * dr + dg * dg + db * db) / 3)
            s = s2 = k = 0
            for yy in range(max(0, y - 1), min(H, y + 2)):
                for xx in range(max(0, x - 1), min(W, x + 2)):
                    v = Y[yy * W + xx]
                    s += v
                    s2 += v * v
                    k += 1
            sd = math.sqrt(max(0.0, s2 / k - (s / k) ** 2))
            occ[i] = max(color / UMBRAL_COLOR, sd / UMBRAL_DETALLE)
            orn[i] = max(color / UMBRAL_COLOR_ORNAMENTO, sd / UMBRAL_DETALLE)
    return occ, orn, paper


def insets(orn, W, H):
    raw = [1 if v >= 1 else 0 for v in orn]
    occ = [0] * (W * H)
    for y in range(H):
        for x in range(W):
            s = k = 0
            for yy in range(max(0, y - 1), min(H, y + 2)):
                for xx in range(max(0, x - 1), min(W, x + 2)):
                    s += raw[yy * W + xx]
                    k += 1
            occ[y * W + x] = 1 if s * 2 > k else 0

    def col(x, y0, y1):
        return sum(occ[y * W + x] for y in range(y0, y1)) / (y1 - y0) if y1 > y0 else 0

    def row(y, x0, x1):
        return sum(occ[y * W + x] for x in range(x0, x1)) / (x1 - x0) if x1 > x0 else 0

    def frm(n, prof, inv):
        last = 0
        for k in range(int(n * BUSQUEDA_MAX)):
            i = n - 1 - k if inv else k
            if prof(i) >= PERFIL_OCUPADO:
                last = k + 1
        return last
    L = R = T = B = 0
    for _ in range(3):
        L = frm(W, lambda x: col(x, T, H - B), False)
        R = frm(W, lambda x: col(x, T, H - B), True)
        T = frm(H, lambda y: row(y, L, W - R), False)
        B = frm(H, lambda y: row(y, L, W - R), True)

    def side(px, n):
        return round(min(BUSQUEDA_MAX, px / n + AIRE), 3) if px > 0 else 0
    return {"top": side(T, H), "right": side(R, W), "bottom": side(B, H), "left": side(L, W)}


def _up4(v):
    return int(math.ceil(v / 4.0) * 4)


def measure_page(im):
    """Fondo de página: zona segura en fracciones (safe-area.ts) y, pasada a píxeles, los márgenes del 9 trozos
    (la franja con adorno, ≥ 8) y los de contenido (la franja + 4 de aire, ≥ 12), múltiplos de 4."""
    W, H = im.size
    k = 96 / W
    small = im.convert("RGB").resize((96, max(1, round(H * k))), Image.BOX)
    occ, orn, paper = occupancy(small)
    ins = insets(orn, small.width, small.height)
    busy_cells = [min(1.0, v) for v in occ]
    px = {s: ins[s] * (W if s in ("left", "right") else H) for s in ins}
    texture = {s: max(8, _up4(px[s])) for s in px}
    content = {s: max(12, _up4(px[s] + 4)) for s in px}
    decorative = max(px.values()) > 48
    return {"safe": ins, "texture_margin": texture, "content_margin": content, "paper": "#%02x%02x%02x" % paper,
            "busy": round(sum(busy_cells) / len(busy_cells), 3), "decorative_only": decorative, "width": W, "height": H}


# --- Máscaras (masks.ts, generate-masks.mjs) en 1 bit con trama Bayer --------------------------------------------------

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def _noise1d(rnd, cells, amp):
    vals = [(rnd.random() * 2 - 1) * amp for _ in range(cells + 1)]

    def f(t):
        x = min(max(t, 0.0), 0.99999) * cells
        i = int(x)
        u = (1 - math.cos((x - i) * math.pi)) / 2
        return vals[i] * (1 - u) + vals[i + 1] * u
    return f


def _brush(rnd, amp):
    """Borde de pincel: ruido de valor en tres escalas (contorno orgánico, no polígono tembloroso)."""
    fs = [_noise1d(rnd, c, a) for c, a in ((5, amp), (13, amp * 0.5), (31, amp * 0.25))]
    return lambda t: sum(f(t) for f in fs)


def brush_mask(size, bands, seed):
    """Alfa de 1 bit: visible donde la distancia al borde (con ruido de pincel por lado) supera la banda del lado;
    dentro de la banda, tramado Bayer 4×4 (el fundido del pixel art). bands: {lado: (margen, banda, ruido)}."""
    W, H = size
    rnd = random.Random(seed)
    edges = {s: _brush(rnd, bands[s][2]) for s in bands}
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    px = im.load()
    for y in range(H):
        for x in range(W):
            t = 1.0
            for s, (m, b, _) in bands.items():
                if s == "left":
                    d, u = x, y / H
                elif s == "right":
                    d, u = W - 1 - x, y / H
                elif s == "top":
                    d, u = y, x / W
                else:
                    d, u = H - 1 - y, x / W
                d = d - m - edges[s](u)
                t = min(t, 1.0 if b <= 0 else d / b)
            if t >= 1 or (t > 0 and t * 16 > BAYER4[y % 4][x % 4] + 0.5):
                px[x, y] = (255, 255, 255, 255)
    return im


def veil(size, paper, seed=0):
    """Velo de la Lámina: color del papel, alfa tramado que sube de 0 (arriba) a casi opaco a 28 px."""
    W, H = size
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    px = im.load()
    rnd = random.Random(seed)
    edge = _brush(rnd, 4.0)
    for y in range(H):
        for x in range(W):
            t = (y - 2 - edge(x / W)) / 28.0
            if t >= 1 or (t > 0 and t * 16 > BAYER4[y % 4][x % 4] + 0.5):
                px[x, y] = paper + (230,)
    return im


def masks():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for n in (1, 2, 3):
        s = 100 + n
        made.append(("mask_foot_240", n, brush_mask((240, 135), {"top": (0, 4, 1.5), "left": (1, 14, 5),
                                                                  "right": (1, 14, 5), "bottom": (2, 26, 8)}, s)))
        made.append(("mask_foot_192", n, brush_mask((192, 108), {"top": (0, 3, 1.2), "left": (1, 11, 4),
                                                                 "right": (1, 11, 4), "bottom": (2, 21, 6)}, s + 10)))
        made.append(("mask_corner", n, brush_mask((64, 64), {"top": (0, 6, 2), "left": (0, 6, 2), "right": (1, 12, 4),
                                                             "bottom": (1, 12, 4)}, s + 20)))
        made.append(("mask_side", n, brush_mask((64, 64), {"top": (0, 5, 2), "left": (0, 3, 1), "right": (1, 18, 5),
                                                           "bottom": (0, 8, 3)}, s + 30)))
    paper = hexc("d4b896")
    if os.path.exists(KIT):
        with open(KIT) as f:
            pb = json.load(f).get("slots", {}).get("page_bg", {}).get("variants", [])
            if pb:
                paper = hexc(pb[0].get("paper", "#d4b896"))
    made.append(("veil", 1, veil((480, 96), paper)))
    for slot, n, im in made:
        p = os.path.join(OUT, f"{slot}_{n}.png")
        im.save(p)
    print(f"máscaras: {len(made)} en {os.path.relpath(OUT, ROOT)}")


# --- kit.json ---------------------------------------------------------------------------------------------------------

def measure():
    """Mide cada <hueco>_<n>.png de assets/art/ui/page_kit/ y escribe kit.json. Las variantes elegidas (`chosen`) se
    conservan si ya estaban; si no, todas las que hay (menos los fondos «solo decorativos»)."""
    old = {}
    if os.path.exists(KIT):
        with open(KIT) as f:
            old = json.load(f).get("slots", {})
    slots = {}
    for slot, d in SLOTS.items():
        files = sorted((f for f in os.listdir(OUT) if f.startswith(slot + "_") and f.endswith(".png")
                        and f[len(slot) + 1:-4].isdigit()), key=lambda f: int(f[len(slot) + 1:-4]))
        if not files:
            continue
        variants = []
        for f in files:
            im = Image.open(os.path.join(OUT, f)).convert("RGBA")
            v = {"file": f, "width": im.width, "height": im.height}
            kind = d["measure"]
            if kind == "page":
                v.update(measure_page(im))
            elif kind == "nine":
                m = measure_nine(im)
                v["nine"] = m
                if m is None:
                    v["error"] = "no parece un marco (centro opaco o sin listón)"
            elif kind == "ribbon":
                v.update(measure_ribbon(im))
            elif kind == "folio":
                v.update(measure_folio(im))
            elif kind == "bbox":
                v.update(bbox_measure(im))
            variants.append(v)
        names = [v["file"] for v in variants]
        chosen = [c for c in old.get(slot, {}).get("chosen", []) if c in names]
        if not chosen:
            chosen = [v["file"] for v in variants if not v.get("decorative_only") and not v.get("error")]
        slots[slot] = {"rotation": d["rotation"], "background": d["bg"], "size": list(d["size"]), "variants": variants,
                       "chosen": chosen}
    kit = {"_doc": "Kit de página (docs/ui/04_kit_de_pagina.md). Lo escribe tools/art/kit_pagina.py measure: un hueco "
                   "por clave, sus variantes (fichero en esta carpeta y lo medido: márgenes del 9 trozos y de "
                   "contenido de los fondos, corte del marco, remates y franja de texto de la cinta, hueco del "
                   "cartucho) y las elegidas, que game/ui/page_kit.gd alterna (por página, por elemento o por imagen). "
                   "Medidas en píxeles lógicos salvo `safe` (fracciones).",
           "version": 1, "slots": slots}
    with open(KIT, "w") as f:
        json.dump(kit, f, indent=1, ensure_ascii=False)
    print(f"kit.json: {len(slots)} huecos · " + ", ".join(f"{k}×{len(v['chosen'])}" for k, v in slots.items()))
    return kit


def sheet(out):
    """Galería de las piezas a ×2 sobre gris, con su nombre debajo (sin texto en la imagen: el nombre va en el HTML)."""
    with open(KIT) as f:
        kit = json.load(f)
    tiles = []
    for slot, s in kit["slots"].items():
        for v in s["variants"]:
            tiles.append((slot, Image.open(os.path.join(OUT, v["file"])).convert("RGBA")))
    k = 2
    W = 1200
    x = y = 8
    rowh = 0
    pos = []
    for slot, im in tiles:
        w, h = im.width * k, im.height * k
        if x + w > W - 8:
            x, y, rowh = 8, y + rowh + 12, 0
        pos.append((x, y))
        x += w + 12
        rowh = max(rowh, h)
    sh = Image.new("RGBA", (W, y + rowh + 8), (58, 52, 46, 255))
    for (slot, im), (px, py) in zip(tiles, pos):
        sh.alpha_composite(im.resize((im.width * k, im.height * k), Image.NEAREST), (px, py))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sh.save(out)
    print("  ->", os.path.relpath(out, ROOT))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ref")
    g = sub.add_parser("gen")
    g.add_argument("slot", choices=[s for s in PIECE if not s.startswith("tile_")])
    g.add_argument("name")
    g.add_argument("--count", type=int, default=1)
    g.add_argument("--aspect")
    g.add_argument("--extra", default="")
    t = sub.add_parser("tile")
    t.add_argument("slot", choices=["tile_light", "tile_dark"])
    t.add_argument("name")
    t.add_argument("--extra", default="")
    p = sub.add_parser("pixel")
    p.add_argument("slot", choices=list(SLOTS))
    p.add_argument("raw")
    p.add_argument("n", type=int)
    p.add_argument("--crop")
    p.add_argument("--scale", type=int)
    sub.add_parser("masks")
    sub.add_parser("measure")
    s = sub.add_parser("sheet")
    s.add_argument("--out", default=os.path.join(ROOT, "tmp", "kit_pagina", "galeria.png"))
    sub.add_parser("total")
    a = ap.parse_args()
    if a.cmd == "ref":
        print(ref_sheet())
    elif a.cmd == "gen":
        gen(a.slot, a.name, a.count, a.aspect, a.extra)
        print(f"Total: {total():.3f} USD")
    elif a.cmd == "tile":
        tile(a.slot, a.name, a.extra)
        print(f"Total: {total():.3f} USD")
    elif a.cmd == "pixel":
        crop = tuple(int(v) for v in a.crop.split(",")) if a.crop else None
        pixel(a.slot, a.raw, a.n, crop, a.scale)
    elif a.cmd == "masks":
        masks()
    elif a.cmd == "measure":
        measure()
    elif a.cmd == "sheet":
        sheet(a.out)
    else:
        print(f"{total():.3f} USD")


if __name__ == "__main__":
    t0 = time.time()
    main()
