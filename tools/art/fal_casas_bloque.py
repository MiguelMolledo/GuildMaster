#!/usr/bin/env python3
"""Casas de relleno de las ciudades orgánicas en lotes de 2×2, 2×3, 2×4 y 3×4 (rama ciudad-2d): hoy son el bloque
greybox de game/visuals/props/house_block.tscn. Los lotes girados (3×2, 4×2, 4×3) usan el mismo sprite en espejo.

Cada casa sale de una maqueta gris a la escala B (tools/art/escala.py house: planta baja 64 px, alta 48, tejado a dos
aguas con la cumbrera a lo largo del lado largo) que ocupa el lote entero, ampliada ×4, y de dos casas del juego ×4
como referencia de estilo; fal nano-banana-2/edit la repinta y se pasa a pixel art en local (fal_ciudad2d.local_pixel)
con el píxel medido. Salida: assets/art/buildings/block/house_<c>x<r>_<k>.png, la base del lote abajo y centrada.

Uso: FAL_TANDA=ciudad2d python3 tools/art/fal_casas_bloque.py ref|gen|proc [tamaño ...]
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import escala  # noqa: E402
import fal_fachadas  # noqa: E402
import fal_iconos as fic  # noqa: E402
import fal_procesar as fp  # noqa: E402
import fal_rutas as fr_  # noqa: E402
from fal_ciudad2d import local_pixel  # noqa: E402

ROOT = fr_.ROOT
P = fr_.produccion("ciudad2d_bloque")
OUT = os.path.join(ROOT, "assets", "art", "buildings", "block")
SCALE = 4
# tamaño -> plantas
SIZES = {"2x2": 2, "2x3": 2, "2x4": 2, "3x4": 2}
LOOKS = [
    "a half-timbered townhouse: dark oak timber frame with cream plaster panels, red clay tile roof, small leaded "
    "windows with wooden shutters, a brick chimney",
    "a stone townhouse: grey-brown rubble stone ground floor and plastered upper floor, blue-grey slate roof, arched "
    "wooden door, small windows, a stone chimney",
    "a plastered townhouse painted warm ochre with a timber jetty on the upper floor, brown weathered tile roof, a "
    "flower box under a window, a small chimney",
    "a narrow whitewashed house with dark timber posts, a purple-grey slate roof, a green wooden door and shutters",
]
LOOKS_BY_SIZE = {"2x2": 4, "2x3": 4}  # the most common lots get a fourth look
STYLE_REFS = ["escala_b/house_b.png", "escala_b/house_c.png", "escala_b/house_e.png"]


def maquette(size):
    c, r = (int(x) for x in size.split("x"))
    floors = SIZES[size]
    w = (c + r) * 32 + 16
    h = 300
    img = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    iso = escala.Iso(w / 2 - (c - r) * 16 * 0, 0)
    # bottom vertex of the lot at the bottom of the canvas
    oy = h - 6 - (c + r) * 16
    iso = escala.Iso(round(w / 2 - (c - r) * 16), oy)
    along = "v" if r > c else "u"
    escala.house(d, iso, 0.05, 0.05, c - 0.1, r - 0.1, floors, along=along, wall=((205, 205, 205), (160, 160, 160)),
                 roof=((150, 150, 150), (115, 115, 115)), details=True)
    return img


def ref():
    os.makedirs(P, exist_ok=True)
    for size in SIZES:
        m = maquette(size)
        m = m.resize((m.width * SCALE, m.height * SCALE), Image.NEAREST)
        canvas = Image.new("RGB", (1024, 1024), (255, 255, 255))
        canvas.paste(m.convert("RGB"), ((1024 - m.width) // 2, 1024 - m.height - 8))
        canvas.save(os.path.join(P, f"maqueta_{size}.png"))
    sheet = Image.new("RGBA", (3 * 220, 240), (255, 255, 255, 255))
    for i, rel in enumerate(STYLE_REFS):
        im = Image.open(os.path.join(ROOT, "assets", "art", "buildings", rel)).convert("RGBA")
        sheet.alpha_composite(im, (i * 220 + (220 - im.width) // 2, 240 - im.height))
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    sheet.convert("RGB").save(os.path.join(P, "estilo.png"))
    print("refs en", P)


def prompt(size, k):
    c, r = size.split("x")
    return ("Image 1 is a grey block model of a medieval town house on a lot of " + c + "x" + r + " isometric tiles, "
            "drawn at 4x scale (every art pixel is a 4x4 block). Image 2 shows three houses of our game. Repaint the "
            "grey model as ONE finished house in exactly the pixel art style of image 2: same isometric 2:1 projection "
            "and camera, same dark 1-pixel outline, same warm earthy palette and shading with light from the top-left. "
            "Keep exactly the model's footprint, wall heights, roof shape, ridge direction and position in the image, "
            "and the same 4x4 pixel grid. The house: " + LOOKS[k] + ". Plain flat white background, no ground tile, "
            "no grass, no paving, no base plate, no people, no text or labels, no shadow on the background. The house "
            "fills the whole width of the grey model.")


def gen(sizes):
    for size in sizes:
        for k in range(LOOKS_BY_SIZE.get(size, 3)):
            name = f"house_{size}_{k + 1}"
            if os.path.exists(os.path.join(P, "crudo", name + ".png")):
                continue
            cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece",
                   "ciudad2d_bloque", "--aspect", "1:1", "--name", name, "--ref",
                   os.path.join(P, f"maqueta_{size}.png"), "--ref", os.path.join(P, "estilo.png"), "--prompt",
                   prompt(size, k)]
            if subprocess.run(cmd, cwd=ROOT).returncode:
                sys.exit(1)


def largest(im):
    """Solo la mancha opaca conexa más grande (fuera letras o motas sueltas que dibuje el modelo)."""
    a = im.getchannel("A").load()
    w, h = im.size
    seen = set()
    best = []
    for y in range(h):
        for x in range(w):
            if a[x, y] > 127 and (x, y) not in seen:
                comp, st = [], [(x, y)]
                seen.add((x, y))
                while st:
                    cx, cy = st.pop()
                    comp.append((cx, cy))
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and a[nx, ny] > 127:
                            seen.add((nx, ny))
                            st.append((nx, ny))
                if len(comp) > len(best):
                    best = comp
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    src = im.load()
    dst = out.load()
    for x, y in best:
        dst[x, y] = src[x, y]
    return out.crop(out.getchannel("A").getbbox())


def proc(sizes):
    os.makedirs(OUT, exist_ok=True)
    for size in sizes:
        c, r = (int(x) for x in size.split("x"))
        target_w = (c + r) * 32
        for k in range(LOOKS_BY_SIZE.get(size, 3)):
            raw = os.path.join(P, "crudo", f"house_{size}_{k + 1}.png")
            if not os.path.exists(raw):
                continue
            keyed = fal_fachadas.holes(fp.key_background(Image.open(raw).convert("RGBA").resize((1024, 1024)),
                                                          "white", 28))
            nat = local_pixel(keyed, SCALE, colors=32)
            cut = nat.crop(nat.getchannel("A").getbbox())
            # the model may drift from the 4x grid: sample again so the house is as wide as its lot
            ratio = cut.width / target_w
            if abs(ratio - 1) > 0.08:
                nat = local_pixel(keyed, SCALE, colors=32, mult=ratio)
                cut = nat.crop(nat.getchannel("A").getbbox())
            cut = fic.outline(largest(cut))
            out = os.path.join(OUT, f"house_{size}_{k + 1}.png")
            cut.save(out)
            print(f"{os.path.relpath(out, ROOT)}: {cut.width}x{cut.height} (lote {target_w} px de ancho)")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    sizes = sys.argv[2:] or list(SIZES)
    {"ref": lambda s: ref(), "gen": gen, "proc": proc}.get(cmd, lambda s: print(__doc__))(sizes)
