#!/usr/bin/env python3
"""Ciudad 2D (rama ciudad-2d): piezas de la parcela en ruinas y detalle suelto del suelo, isométricas 2:1 a la
densidad de los props de hoy (1 px de arte = 1 px del juego).

Misma vía que tools/art/fal_props_fiesta.py: fal nano-banana-2/edit con una referencia (6 props del juego ×4) en
rejillas 2×2 agrupadas por tamaño (cada pieza en una rejilla de píxel que da su tamaño final), image2pixel a esa
escala, contorno de 1 px. Salida:
  ruina  -> assets/art/props/ruin_wall.png (tira de 3 fotogramas, alturas distintas), ruin_rubble.png (2 fotogramas)
  suelo  -> assets/art/tiles/ground/decals/<id>.png (charco, piedras, hierbajo, paja)

Uso: FAL_TANDA=ciudad2d python3 tools/art/fal_ciudad2d.py gen|proc
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
from fal_props_fiesta import POS, no_grid_lines, ref_sheet  # noqa: E402

ROOT = fr_.ROOT
P = fr_.produccion("ciudad2d")
PROPS_OUT = os.path.join(ROOT, "assets", "art", "props")
DECALS_OUT = os.path.join(ROOT, "assets", "art", "tiles", "ground", "decals")
# id -> (tamaño máximo en px, descripción, plano: True = calcomanía sobre el suelo, sin volumen)
PIECES = {
    "ruin_wall_1": ((36, 30), "a low broken stub of an old rubble-stone wall, about knee high, jagged broken top, "
                              "grey-brown stones with mortar, a little moss, seen corner-on", False),
    "ruin_wall_2": ((36, 44), "a broken piece of an old rubble-stone house wall, about chest high, jagged top with "
                              "a few loose stones, grey-brown stones, some ivy, seen corner-on", False),
    "ruin_wall_3": ((36, 58), "a tall broken piece of an old stone house wall with a jagged top and the bottom half "
                              "of an empty window opening, grey-brown stones, ivy, seen corner-on", False),
    "ruin_rubble_1": ((40, 22), "a low flat heap of rubble lying on the ground: fallen grey stones, broken red roof "
                                "tiles, dust and weeds, no base plate, no tile under it", True),
    "puddle": ((30, 15), "a small shallow rain puddle lying flat on the ground, irregular shape, dark wet rim, pale "
                         "blue-grey sky reflection, seen at the same isometric angle as the ground", True),
    "stones": ((22, 11), "three or four small loose pebbles and stones lying on the ground, grey and brown", True),
    "weeds": ((16, 14), "a small tuft of wild weeds and dandelion leaves growing from the ground, green", True),
    "straw": ((26, 12), "a few loose wisps of yellow straw and hay scattered flat on the ground", True),
}
_BOTICA = ("an apothecary's market stall: a small wooden counter with a green and cream striped cloth awning on "
           "posts, glass jars and clay pots of herbs and remedies, bundles of dried herbs hanging, a mortar")
for _k in range(1, 5):
    PIECES[f"botica_{_k}"] = ((60, 60), _BOTICA, False)
GRIDS = {"ruina": (4, ["ruin_wall_1", "ruin_wall_2", "ruin_wall_3", "ruin_rubble_1"]),
         "suelo": (8, ["puddle", "stones", "weeds", "straw"]),
         "botica": (8, ["botica_1", "botica_2", "botica_3", "botica_4"])}
STALLS = ["stall_food", "stall_goods", "stall_materials", "stall_clothier", "stall_resources"]


def stall_ref():
    """Hoja de referencia de la botica: los 5 puestos del juego ×4 sobre blanco."""
    sheet = Image.new("RGBA", (3 * 300, 2 * 300), (255, 255, 255, 255))
    for i, n in enumerate(STALLS):
        im = Image.open(os.path.join(ROOT, "assets", "art", "buildings", n + ".png")).convert("RGBA")
        im = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
        sheet.alpha_composite(im, ((i % 3) * 300 + (300 - im.width) // 2, (i // 3) * 300 + 300 - im.height))
    out = os.path.join(P, "ref_stalls.png")
    os.makedirs(P, exist_ok=True)
    sheet.convert("RGB").save(out)
    return out


def prompt(block, ids):
    n = 512 // block
    what = " ".join(f"{pos}: {PIECES[i][1]} (at most {PIECES[i][0][0]}x{PIECES[i][0][1]} art pixels"
                    + (", flat on the ground, no volume" if PIECES[i][2] else ", standing on the ground") + ")."
                    for pos, i in zip(POS, ids))
    if ids[0].startswith("botica"):
        return ("The attached image shows the five isometric 2:1 market stall sprites of our medieval town game, "
                "enlarged 4x. Create ONE square image that is a 2x2 grid with four different versions of a NEW "
                "market stall in exactly this style (same size as those stalls, same isometric 2:1 projection and "
                "camera, same dark 1-pixel outline, same warm palette and shading with light from the top-left, the "
                f"same square wooden base on the ground), centred in its cell, on a plain flat white background. "
                f"Each stall is drawn on a {n}x{n} pixel grid (every art pixel is a {block}x{block} block of its "
                f"512x512 cell), at most 60x60 art pixels. The stall: {_BOTICA}. No text, no letters, no people, "
                "no grid lines, no shadow on the background.")
    return ("The attached image shows isometric 2:1 prop sprites from our medieval town game (a market stall, a "
            "well, a cart, a bench, a barrel and a lantern), enlarged 4x. Create ONE square image that is a 2x2 grid "
            "of NEW props in exactly this style: same isometric 2:1 projection and camera, same dark 1-pixel "
            "outline, same warm earthy palette and shading with light from the top-left, centred in its cell, on a "
            f"plain flat white background. Each piece is drawn on a {n}x{n} pixel grid (every art pixel is a "
            f"{block}x{block} block of its 512x512 cell). " + what +
            " No text, no letters, no people, no grid lines, no base plates or ground tiles under the pieces, no "
            "shadow on the background.")


def gen(only=None):
    for g, (block, ids) in GRIDS.items():
        ref = stall_ref() if g == "botica" else ref_sheet()
        if only and g not in only:
            continue
        if os.path.exists(os.path.join(P, "crudo", g + ".png")):
            continue
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece",
               "ciudad2d", "--aspect", "1:1", "--name", g, "--ref", ref, "--prompt", prompt(block, ids)]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


def piece(g, block, k, pid):
    import fal_fachadas
    im = Image.open(os.path.join(P, "crudo", g + ".png")).convert("RGBA").resize((1024, 1024))
    cell = im.crop(((k % 2) * 512, (k // 2) * 512, (k % 2 + 1) * 512, (k // 2 + 1) * 512))
    keyed = no_grid_lines(fal_fachadas.holes(fp.key_background(cell, "white", 28)))
    src = os.path.join(P, "celdas", f"{g}_{pid}.png")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    keyed.save(src)
    nat = local_pixel(keyed, block, colors=20)
    c = nat.crop(nat.getchannel("A").getbbox())
    mw, mh = PIECES[pid][0]
    k = max(c.width / mw, c.height / mh)
    if k > 1.4:  # the model drew it bigger than asked: sample its raw with a coarser pixel instead of shrinking
        nat = local_pixel(keyed, block, colors=20, mult=round(k))
        c = nat.crop(nat.getchannel("A").getbbox())
    if not PIECES[pid][2]:
        c = fic.outline(c)
    mw, mh = PIECES[pid][0]
    if c.width > mw * 1.5 or c.height > mh * 1.5:
        kk = min(mw / c.width, mh / c.height)
        c = c.resize((max(1, int(c.width * kk)), max(1, int(c.height * kk))), Image.NEAREST)
    return c


def pixel_size(im):
    """Tamaño del píxel de arte en el crudo (px, con decimales): de las rachas de color entre cambios bruscos,
    ajustando las rachas largas a múltiplos del píxel."""
    from collections import Counter
    im = im.convert("RGB")
    w, h = im.size
    px = im.load()
    runs = Counter()
    for y in range(0, h, 7):
        last = 0
        for x in range(1, w):
            a, b = px[x, y], px[x - 1, y]
            if abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) > 30:
                if 2 < x - last < 40:
                    runs[x - last] += 1
                last = x
    best = None
    for p10 in range(30, 90):
        q = p10 / 10
        err = sum(n * min(abs(r - k * q) for k in range(1, 9)) for r, n in runs.items())
        if best is None or err < best[0]:
            best = (err, q)
    return best[1]


def local_pixel(im, block, colors=20, mult=1):
    """El crudo de nano-banana ya es pixel art, con su píxel a unos `block` px (en la práctica algo más: se mide).
    Se busca el desfase de la rejilla y cada píxel de arte toma el color más frecuente del centro de su celda (y el
    alfa por mayoría); después, paleta corta. Hace en local lo que hacía fal-ai/image2pixel (ya no está en fal,
    2026-11-17)."""
    from collections import Counter
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    p = pixel_size(im) * mult

    def cell(ox, oy, x, y):
        x0, y0 = ox + x * p, oy + y * p
        m = p * 0.25
        return [px[int(i), int(j)] for j in (y0 + m, y0 + p / 2, y0 + p - m) for i in (x0 + m, x0 + p / 2, x0 + p - m)
                if int(i) < w and int(j) < h]

    best = None
    for oy10 in range(0, int(p * 10), 5):
        for ox10 in range(0, int(p * 10), 5):
            ox, oy = ox10 / 10, oy10 / 10
            err = 0
            for y in range(0, int((h - oy) / p) - 1, 3):
                for x in range(0, int((w - ox) / p) - 1, 3):
                    vals = cell(ox, oy, x, y)
                    if all(v[3] < 128 for v in vals):
                        continue
                    mean = [sum(v[c] for v in vals) / len(vals) for c in range(3)]
                    err += sum(sum((v[c] - mean[c]) ** 2 for c in range(3)) for v in vals)
            if best is None or err < best[0]:
                best = (err, ox, oy)
    _, ox, oy = best
    nw, nh = int((w - ox) / p), int((h - oy) / p)
    out = Image.new("RGBA", (nw, nh), (0, 0, 0, 0))
    op = out.load()
    for y in range(nh):
        for x in range(nw):
            vals = cell(ox, oy, x, y)
            opaque = [v[:3] for v in vals if v[3] >= 128]
            if len(opaque) * 2 < len(vals):
                continue
            op[x, y] = Counter(opaque).most_common(1)[0][0] + (255,)
    print(f"  pixel {p:.1f} px, desfase ({ox:.1f}, {oy:.1f}) -> {nw}x{nh}")
    a = out.getchannel("A")
    q = out.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    res = q.convert("RGBA")
    res.putalpha(a)
    return res


def strip(frames, w, h):
    """Fotogramas del mismo tamaño (w×h), cada pieza abajo y centrada: la base sobre los pies de la escena."""
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f, (i * w + (w - f.width) // 2, h - f.height))
    return out


def proc():
    got = {}
    for g, (block, ids) in GRIDS.items():
        if not os.path.exists(os.path.join(P, "crudo", g + ".png")):
            print("falta", g)
            continue
        for k, pid in enumerate(ids):
            got[pid] = piece(g, block, k, pid)
            print(f"{pid}: {got[pid].width}x{got[pid].height}")
    walls = [got[k] for k in ("ruin_wall_1", "ruin_wall_2", "ruin_wall_3") if k in got]
    if walls:
        w = max(f.width for f in walls) + 2
        h = max(f.height for f in walls) + 2
        strip(walls, w, h).save(os.path.join(PROPS_OUT, "ruin_wall.png"))
        print("ruin_wall.png", len(walls), "fotogramas de", w, "x", h)
    if "ruin_rubble_1" in got:
        r = got["ruin_rubble_1"]
        strip([r, r.transpose(Image.FLIP_LEFT_RIGHT)], r.width + 2, r.height + 2).save(
            os.path.join(PROPS_OUT, "ruin_rubble.png"))
    os.makedirs(DECALS_OUT, exist_ok=True)
    for pid in ("puddle", "stones", "weeds", "straw"):
        if pid in got:
            got[pid].save(os.path.join(DECALS_OUT, pid + ".png"))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "gen":
        gen(sys.argv[2:] or None)
    elif cmd == "proc":
        proc()
    else:
        print(__doc__)
