#!/usr/bin/env python3
"""Procesa las piezas crudas del piloto de fal (assets/art/fal_piloto/<pieza>/crudo/) a la medida del juego, de dos
formas para compararlas: en local con Pillow (tools/art/fal_procesar.py) y con fal-ai/image2pixel (céntimos).

Uso: python3 tools/art/fal_piloto_build.py [retratos|titulo|eventos|iconos|fachada|paseo|todo] [--sin-i2p]
Salida: assets/art/fal_piloto/<pieza>/final/ (repo) y $GUILDMASTER_ARTE_CRUDOS/fal_piloto/<pieza>/{celdas,local,i2p}/
"""
import argparse
import json
import os
import sys
from types import SimpleNamespace

from PIL import Image

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import fal_procesar as fp  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import fal_rutas as fr_  # noqa: E402  (crudos fuera del repo)
D = fr_.PILOTO  # crudos e intermedios fuera del repo; <pieza>/final/ en el repo (FINAL)
FINAL = fr_.PILOTO_REPO
USE_I2P = True


def i2p(piece, src, dst, colors=32, scale=0, transparent=False):
    """image2pixel; devuelve la imagen bajada a su rejilla (1 píxel de arte = 1 píxel)."""
    if not USE_I2P:
        return None
    if not os.path.exists(dst):
        import fal_piloto
        fal_piloto.pixel(SimpleNamespace(piece=piece, src=src, dst=dst, colors=colors, scale=scale, palette="",
                                         transparent=transparent))
    meta = json.load(open(dst + ".json"))
    s = int(meta.get("pixel_scale") or 1)
    im = Image.open(dst).convert("RGBA")
    return im.resize((max(1, im.width // s), max(1, im.height // s)), Image.NEAREST), s


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)
    return path


def fit_canvas(im, canvas, box, bottom=None, resample=Image.BOX):
    """Recorta al contenido y lo encaja en box=(w,h) dentro de canvas; bottom = y de los pies (o centrado)."""
    bb = im.getchannel("A").getbbox()
    c = im.crop(bb)
    k = min(box[0] / c.width, box[1] / c.height)
    size = (max(1, round(c.width * k)), max(1, round(c.height * k)))
    c = c.resize(size, resample)
    c.putalpha(c.getchannel("A").point(lambda v: 255 if v > 127 else 0))
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    x = (canvas[0] - size[0]) // 2
    y = (bottom - size[1]) if bottom is not None else (canvas[1] - size[1]) // 2
    out.alpha_composite(c, (x, y))
    return out


# ---------------------------------------------------------------- retratos
PORTRAITS = {"grid_nano2_v1": ["artesano", "artesana", "anciano", "rival"],
             "grid2_nano2_v1": ["nina", "trabajador", "anciana", "rival_esposa"],
             "grid_nano_v1": ["artesano", "artesana", "anciano", "rival"]}


def retratos():
    P = os.path.join(D, "retratos")
    for grid, names in PORTRAITS.items():
        tag = "nano" if grid.startswith("grid_nano_") else "nano2"
        cells = fp.split_grid(os.path.join(P, "crudo", grid + ".png"), os.path.join(P, "celdas"), grid)
        for cell, n in zip(cells, names):
            base = f"{tag}_{n}"
            im = Image.open(cell).convert("RGBA")
            # local: caja a 64 y a 32 (32 con recorte de cara: el 75 % de arriba al centro)
            save(fp.quantize(im.resize((64, 64), Image.BOX), 32), os.path.join(P, "local", base + "_64.png"))
            face = im.crop((64, 0, 448, 384))
            save(fp.quantize(face.resize((32, 32), Image.BOX), 24), os.path.join(P, "local", base + "_32.png"))
            if tag == "nano":
                continue
            r = i2p("retratos", cell, os.path.join(P, "i2p", base + "_s8.png"), 32, 8)
            if r:
                im64 = Image.new("RGBA", (64, 64), (0, 0, 0, 255))
                im64.alpha_composite(r[0].crop((0, 0, 64, 64)), (0, 0))
                save(im64, os.path.join(FINAL, os.path.basename(P), "final", base + "_64.png"))
            tmp = save(face, os.path.join(P, "celdas", base + "_cara.png"))
            r = i2p("retratos", tmp, os.path.join(P, "i2p", base + "_cara_s12.png"), 24, 12)
            if r:
                im32 = Image.new("RGBA", (32, 32), (0, 0, 0, 255))
                im32.alpha_composite(r[0].crop((0, 0, 32, 32)), (0, 0))
                save(im32, os.path.join(FINAL, os.path.basename(P), "final", base + "_32.png"))
    # identidad 4.10.9 sobre el artesano de 64
    src = os.path.join(FINAL, os.path.basename(P), "final", "nano2_artesano_64.png")
    if os.path.exists(src):
        keyed = os.path.join(FINAL, os.path.basename(P), "final", "nano2_artesano_64_clave.png")
        print("regiones clave:", fp.key_portrait(src, keyed))
        fp.preview_key(keyed, os.path.join(FINAL, os.path.basename(P), "final", "nano2_artesano_64_familias.png"), [
            {1: (92, 60, 34), 2: (224, 181, 140), 3: (140, 46, 46), 4: (200, 168, 80)},
            {1: (30, 24, 20), 2: (150, 100, 70), 3: (40, 70, 130), 4: (190, 190, 200)},
            {1: (200, 150, 60), 2: (240, 200, 170), 3: (50, 110, 60), 4: (120, 70, 40)},
        ])


# ---------------------------------------------------------------- título
def titulo():
    P = os.path.join(D, "titulo")
    logo1 = Image.open(os.path.join(ROOT, "assets", "art", "ui", "logo", "guildmaster_logo.png")).convert("RGBA")
    for n in ("titulo_alba_v1", "titulo_noche_v1"):
        src = os.path.join(P, "crudo", n + ".png")
        im = Image.open(src).convert("RGBA")
        save(fp.quantize(im.resize((960, 540), Image.BOX), 64), os.path.join(P, "local", n + "_960.png"))
        save(fp.quantize(im.resize((480, 270), Image.BOX), 48), os.path.join(P, "local", n + "_480.png"))
        r = i2p("titulo", src, os.path.join(P, "i2p", n + "_i2p.png"), 48)
        if r:
            nat, s = r
            save(nat, os.path.join(P, "i2p", n + "_nativo.png"))
            # a 480×270 (se ve ×2 en el viewport de 960×540): la rejilla nativa (~344×192) ×1,4 con vecino
            # más cercano deforma; mejor caja + paleta de la propia salida de image2pixel
            pal = nat.convert("RGB").quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
            f480 = im.convert("RGB").resize((480, 270), Image.BOX).quantize(palette=pal, dither=Image.Dither.NONE)
            f480 = save(f480.convert("RGBA"), os.path.join(FINAL, os.path.basename(P), "final", n + "_480.png"))
            small = Image.open(f480).convert("RGBA")
            small.alpha_composite(logo1, ((480 - logo1.width) // 2, 36))
            save(small, os.path.join(FINAL, os.path.basename(P), "final", n + "_480_con_logo.png"))


# ---------------------------------------------------------------- eventos
def eventos():
    P = os.path.join(D, "eventos")
    for n in ("guerra_v1", "fiesta_v1"):
        src = os.path.join(P, "crudo", n + ".png")
        im = Image.open(src).convert("RGBA")
        for w, h in ((240, 135), (192, 108)):
            save(fp.quantize(im.resize((w, h), Image.BOX), 32), os.path.join(P, "local", f"{n}_{w}.png"))
        r = i2p("eventos", src, os.path.join(P, "i2p", n + "_i2p.png"), 32)
        if r:
            nat, s = r
            save(nat, os.path.join(P, "i2p", n + "_nativo.png"))
            pal = nat.convert("RGB").quantize(colors=32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
            for w, h in ((240, 135), (192, 108)):
                f = im.convert("RGB").resize((w, h), Image.BOX).quantize(palette=pal, dither=Image.Dither.NONE)
                save(f.convert("RGBA"), os.path.join(FINAL, os.path.basename(P), "final", f"{n}_{w}.png"))


# ---------------------------------------------------------------- iconos
ICONS = ["sierra", "arcon", "estatua", "acero"]


def iconos():
    P = os.path.join(D, "iconos")
    cells = fp.split_grid(os.path.join(P, "crudo", "iconos_v1.png"), os.path.join(P, "celdas"), "iconos_v1")
    for cell, n in zip(cells, ICONS):
        keyed = fp.key_background(Image.open(cell), "white", 30)
        k = save(keyed, os.path.join(P, "celdas", n + "_sin_fondo.png"))
        save(fp.quantize(fit_canvas(keyed, (32, 32), (30, 30), resample=Image.BOX), 16),
             os.path.join(P, "local", n + "_32_caja.png"))
        save(fp.quantize(fit_canvas(fp.dominant_resize(keyed.crop(keyed.getchannel("A").getbbox()),
                                                       (30, 30)), (32, 32), (30, 30), resample=Image.NEAREST), 16),
             os.path.join(P, "local", n + "_32_dominante.png"))
        r = i2p("iconos", cell, os.path.join(P, "i2p", n + "_i2p.png"), 16, 0, True)
        if r:
            nat, s = r
            save(nat, os.path.join(P, "i2p", n + "_nativo.png"))
            bb = nat.getchannel("A").getbbox()
            c = nat.crop(bb)
            if max(c.size) <= 30:
                out = Image.new("RGBA", (32, 32))
                out.alpha_composite(c, ((32 - c.width) // 2, (32 - c.height) // 2))
            else:
                out = fit_canvas(nat, (32, 32), (30, 30), resample=Image.NEAREST)
            save(out, os.path.join(FINAL, os.path.basename(P), "final", n + "_32.png"))


# ---------------------------------------------------------------- fachada
def fachada():
    P = os.path.join(D, "fachada")
    for n in ("sastreria_v1", "sastreria_v2", "sastreria_pro_v1"):
        src = os.path.join(P, "crudo", n + ".png")
        keyed = fp.key_background(Image.open(src), "white", 24)
        save(keyed, os.path.join(P, "celdas", n + "_sin_fondo.png"))
        # mismo ancho que armory.png (182 px de contenido) y mismo suelo (pies en y=176) en un lienzo de 192×192
        save(fp.quantize(fit_canvas(keyed, (192, 192), (182, 170), bottom=176), 48),
             os.path.join(P, "local", n + "_192.png"))
        r = i2p("fachada", src, os.path.join(P, "i2p", n + "_i2p.png"), 48, 0, True)
        if r:
            nat, s = r
            save(nat, os.path.join(P, "i2p", n + "_nativo.png"))
            save(fit_canvas(nat, (192, 192), (182, 170), bottom=176, resample=Image.NEAREST),
                 os.path.join(FINAL, os.path.basename(P), "final", n + "_192.png"))


# ---------------------------------------------------------------- paseo
def paseo():
    P = os.path.join(D, "paseo")
    for n, bg in (("paseo_v1", "green"), ("paseo_v2", "white"), ("paseo_pro_v1", "white")):
        src = os.path.join(P, "crudo", n + ".png")
        if not os.path.exists(src):
            continue
        cells = fp.split_grid(src, os.path.join(P, "celdas"), n)
        frames_local, frames_i2p = [], []
        for i, cell in enumerate(cells):
            im = Image.open(cell).convert("RGBA")
            w, h = im.size
            im = im.crop((6, 6, w - 6, h - 6))  # fuera las líneas de la rejilla si las dibujó
            keyed = fp.key_background(im, bg, 40)
            save(keyed, os.path.join(P, "celdas", f"{n}_{i + 1}_sin_fondo.png"))
            # personaje de 51 px de alto con los pies en y=60, como townsfolk_m (lienzo 68×68)
            frames_local.append(fp.quantize(fit_canvas(keyed, (68, 68), (40, 51), bottom=60), 24))
        strip = Image.new("RGBA", (68 * len(frames_local), 68))
        for i, f in enumerate(frames_local):
            strip.alpha_composite(f, (i * 68, 0))
        save(strip, os.path.join(P, "local", n + "_tira.png"))
        r = i2p("paseo", src, os.path.join(P, "i2p", n + "_i2p.png"), 24, 0, True)
        if r:
            nat, s = r
            save(nat, os.path.join(P, "i2p", n + "_nativo.png"))
            cw, ch = nat.width // 2, nat.height // 2
            strip = Image.new("RGBA", (68 * 4, 68))
            for i in range(4):
                c = nat.crop(((i % 2) * cw, (i // 2) * ch, (i % 2 + 1) * cw, (i // 2 + 1) * ch))
                c = fp.key_background(c, bg, 40)
                bb = c.getchannel("A").getbbox()
                fig = c.crop(bb)
                k = max(1, round(51 / fig.height))  # escala entera más cercana a 51 px
                fig = fig.resize((fig.width * k, fig.height * k), Image.NEAREST)
                cell = Image.new("RGBA", (68, 68))
                cell.alpha_composite(fig.crop((0, max(0, fig.height - 60), min(68, fig.width), fig.height)),
                                     ((68 - min(68, fig.width)) // 2, max(0, 60 - fig.height)))
                strip.alpha_composite(cell, (i * 68, 0))
            save(strip, os.path.join(FINAL, os.path.basename(P), "final", n + "_tira_i2p.png"))
            print(n, "rejilla nativa: figura de", fig.height // k, "px, escala", k)


def main():
    global USE_I2P
    ap = argparse.ArgumentParser()
    ap.add_argument("what", nargs="?", default="todo")
    ap.add_argument("--sin-i2p", action="store_true")
    a = ap.parse_args()
    USE_I2P = not a.sin_i2p
    steps = {"retratos": retratos, "titulo": titulo, "eventos": eventos, "iconos": iconos, "fachada": fachada,
             "paseo": paseo}
    for k, f in steps.items():
        if a.what in (k, "todo"):
            print("==", k)
            f()


if __name__ == "__main__":
    main()
