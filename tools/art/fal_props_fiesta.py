#!/usr/bin/env python3
"""Props de fiesta (docs/gdd/04f_vida_y_fiestas.md §4.25.3, §4.28.3), isométricos 2:1 a la densidad de los props de
hoy (1 px de arte = 1 px del juego), en assets/art/props/fiesta/<id>.png con su escena
game/visuals/props/fiesta/<id>.tscn (Feet, Top, Sprite y la huella en metadata/footprint del nodo raíz).

fal (nano-banana-2/edit, una referencia: 6 props del juego ×4) en rejillas 2×2 agrupadas por tamaño, para que cada
pieza se dibuje en una rejilla de píxel que da su tamaño final: bloques de 8 (rejilla de 64), de 4 (128) o de 2
(256); image2pixel a esa escala.

Uso: FAL_TANDA=h16 python3 tools/art/fal_props_fiesta.py gen|proc|tscn
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
P = fr_.produccion("props_fiesta")
OUT = os.path.join(ROOT, "assets", "art", "props", "fiesta")
SCN = os.path.join(ROOT, "game", "visuals", "props", "fiesta")
# id -> (huella en casillas, tamaño máximo en px, descripción)
PROPS = {
    "banderola": ((1, 1), (24, 56), "a tall thin wooden pole with a long swallow-tailed pennant in red and yellow"),
    "pendon": ((1, 1), (24, 48), "a vertical cloth banner in deep red with a gold border hanging from a short wooden "
                                 "crossbar, to hang on a wall"),
    "farolillo": ((1, 1), (24, 48), "a small wooden post with a glowing paper festival lantern hanging from it"),
    "hoguera": ((1, 1), (56, 56), "a festival bonfire: a stack of logs with big orange flames and sparks"),
    "mayo": ((1, 1), (40, 104), "a tall maypole: a straight tree trunk with a green leafy crown at the top and long "
                                "coloured ribbons hanging down"),
    "guirnalda": ((2, 1), (128, 56), "a festive garland of small triangular coloured flags strung between two short "
                                     "wooden posts"),
    "mesa_larga": ((3, 1), (128, 64), "a long wooden banquet table with two benches, bread, jugs and plates on it"),
    "puesto_feria": ((2, 2), (100, 100), "a fair market stall with a striped red and yellow cloth awning, a wooden "
                                         "counter with goods"),
    "cerco_carros": ((2, 1), (128, 72), "a barrier of two wooden farm carts tipped on their sides and tied together, "
                                        "a section of the ring for a bull run"),
    "belen": ((2, 2), (100, 88), "a nativity scene: a small wooden stable with straw, figures of Mary, Joseph and "
                                 "the child in the manger, an ox and a donkey"),
    "tablado": ((3, 2), (128, 100), "a raised wooden theatre stage of planks for travelling players, with a painted "
                                    "cloth backdrop on poles"),
    "arco_triunfal": ((3, 1), (200, 136), "a festive triumphal arch over a street, made of wooden posts covered with "
                                          "green branches, flowers and banners, wide enough for a cart"),
    "liza": ((4, 1), (232, 72), "a jousting tilt barrier: a long low wooden fence painted in stripes with small "
                                "pennants, the list for a joust"),
    "corral": ((3, 3), (200, 104), "a square livestock pen of wooden rails with a gate and some straw inside, empty"),
}
GRIDS = {"q8": (8, ["banderola", "pendon", "farolillo", "hoguera"]),
         "q4a": (4, ["mayo", "guirnalda", "mesa_larga", "puesto_feria"]),
         "q4b": (4, ["cerco_carros", "belen", "tablado"]),
         "q2": (2, ["arco_triunfal", "liza", "corral"]),
         # repetidas: en q2 la liza y el corral salieron a la mitad, y el tablado corto (ancho = (cols+filas)×32)
         "q2b": (2, ["liza", "corral", "tablado"])}
PREFER = {"tablado": "q4b", "liza": "q2b", "corral": "q2b"}  # qué rejilla manda para las repetidas
FILL = {"liza": "spanning about 3/5 of the cell width", "corral": "spanning about 3/4 of the cell width",
        "tablado": "spanning about 5/8 of the cell width"}
POS = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]
REF = ["stall_food", "well", "cart", "bench", "barrel", "lantern"]


def ref_sheet():
    sheet = Image.new("RGBA", (3 * 300, 2 * 300), (255, 255, 255, 255))
    for i, n in enumerate(REF):
        p = os.path.join(ROOT, "assets", "art", "props", n + ".png")
        if not os.path.exists(p):
            p = os.path.join(ROOT, "assets", "art", "buildings", n + ".png")
        im = Image.open(p).convert("RGBA")
        im = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
        sheet.alpha_composite(im, ((i % 3) * 300 + (300 - im.width) // 2, (i // 3) * 300 + 300 - im.height))
    out = os.path.join(P, "ref_props.png")
    os.makedirs(P, exist_ok=True)
    sheet.convert("RGB").save(out)
    return out


def prompt(block, ids):
    n = 512 // block
    what = " ".join(f"{pos}: {PROPS[i][2]} (at most {PROPS[i][1][0]}x{PROPS[i][1][1]} art pixels, footprint "
                    f"{PROPS[i][0][0]}x{PROPS[i][0][1]} isometric tiles"
                    + (f", {FILL[i]}" if block == 2 and i in FILL else "") + ")." for pos, i in zip(POS, ids))
    if len(ids) < 4:
        what += " The remaining cells stay plain white."
    return ("The attached image shows isometric 2:1 prop sprites from our medieval town game (a market stall, a "
            "well, a cart, a bench, a barrel and a lantern), enlarged 4x. Create ONE square image that is a 2x2 grid "
            "of NEW festival decoration props in exactly this style: same isometric 2:1 projection and camera, same "
            "dark 1-pixel outline, same warm palette and shading with light from the top-left, standing on the "
            f"ground at the bottom of its cell, centred, on a plain flat white background. Each prop is drawn on a "
            f"{n}x{n} pixel grid (every art pixel is a {block}x{block} block of its 512x512 cell). " + what +
            " No text, no letters, no people, no grid lines, no shadow on the background.")


def gen():
    ref = ref_sheet()
    for g, (block, ids) in GRIDS.items():
        if os.path.exists(os.path.join(P, "crudo", g + ".png")):
            continue
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece",
               "props_fiesta", "--aspect", "1:1", "--name", g, "--ref", ref, "--prompt", prompt(block, ids)]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


def proc():
    import fal_fachadas
    os.makedirs(OUT, exist_ok=True)
    for g, (block, ids) in GRIDS.items():
        raw = os.path.join(P, "crudo", g + ".png")
        if not os.path.exists(raw):
            print("falta", raw)
            continue
        im = Image.open(raw).convert("RGBA").resize((1024, 1024))
        for k, pid in enumerate(ids):
            if PREFER.get(pid, g) != g:
                continue
            cell = im.crop(((k % 2) * 512, (k // 2) * 512, (k % 2 + 1) * 512, (k // 2 + 1) * 512))
            keyed = no_grid_lines(fal_fachadas.holes(fp.key_background(cell, "white", 28)))
            src = os.path.join(P, "celdas", f"{g}_{pid}.png")
            os.makedirs(os.path.dirname(src), exist_ok=True)
            keyed.save(src)
            dst = os.path.join(P, "i2p", f"{g}_{pid}_s{block}.png")
            if not os.path.exists(dst):
                import fal_piloto
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                fal_piloto.pixel(SimpleNamespace(piece="props_fiesta", src=src, dst=dst, colors=24, scale=block,
                                                 palette="", transparent=True))
            up = Image.open(dst).convert("RGBA")
            nat = up.resize((up.width // block, up.height // block), Image.NEAREST)
            nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
            c = fic.outline(nat.crop(nat.getchannel("A").getbbox()))
            mw, mh = PROPS[pid][1]
            if c.width > mw * 1.5 or c.height > mh * 1.5:  # solo si se pasa mucho: reducir cambia la densidad
                kk = min(mw / c.width, mh / c.height)
                c = c.resize((max(1, int(c.width * kk)), max(1, int(c.height * kk))), Image.NEAREST)
            canvas = Image.new("RGBA", (c.width + 2, c.height + 2), (0, 0, 0, 0))
            canvas.alpha_composite(c, (1, 1))
            canvas.save(os.path.join(OUT, pid + ".png"))
            print(f"{pid}: {canvas.width}×{canvas.height}, huella {PROPS[pid][0]}")


def no_grid_lines(im):
    """Borra las rayas de la rejilla que a veces dibuja el modelo: filas o columnas casi enteras de píxeles opacos
    con 1-3 de grosor en el borde de la celda (no tocan el prop)."""
    im = im.copy()
    a = im.getchannel("A")
    w, h = im.size
    px = im.load()
    edge = 10  # solo cerca del borde de la celda: un mástil o un poste en medio no es una raya
    rows = [y for y in list(range(edge)) + list(range(h - edge, h))
            if sum(1 for x in range(w) if a.getpixel((x, y)) > 127) > 0.85 * w]
    cols = [x for x in list(range(edge)) + list(range(w - edge, w))
            if sum(1 for y in range(h) if a.getpixel((x, y)) > 127) > 0.85 * h]
    for y in rows:
        for yy in range(max(0, y - 1), min(h, y + 2)):
            for x in range(w):
                px[x, yy] = (0, 0, 0, 0)
    for x in cols:
        for xx in range(max(0, x - 1), min(w, x + 2)):
            for y in range(h):
                px[xx, y] = (0, 0, 0, 0)
    return im


def pascal(s):
    return "".join(w.capitalize() for w in s.split("_"))


def tscn():
    """Escena de cada prop: los pies en el centro del rombo de la huella (los pequeños, en su base)."""
    os.makedirs(SCN, exist_ok=True)
    for pid, ((fw, fh), _, what) in PROPS.items():
        png = os.path.join(OUT, pid + ".png")
        imp = png + ".import"
        if not (os.path.exists(png) and os.path.exists(imp)):
            print("falta", pid, "(¿importado?)")
            continue
        uid = next(l.split('"')[1] for l in open(imp) if l.startswith("uid="))
        im = Image.open(png)
        w, h = im.size
        lift = 3 if w < 48 else (fw + fh) * 8  # del borde de abajo al centro del rombo de la huella
        offset = (-(w // 2), -(h - lift))
        top = -(h - lift) + 2
        body = (f'[gd_scene load_steps=2 format=3]\n\n'
                f'[ext_resource type="Texture2D" uid="{uid}" path="res://assets/art/props/fiesta/{pid}.png" '
                f'id="1_tex"]\n\n'
                f'[node name="{pascal(pid)}" type="Node2D"]\n'
                f'editor_description = "Festival prop (docs/gdd/04f_vida_y_fiestas.md §4.25.3; tools/art/'
                f'fal_props_fiesta.py): {what}. Feet = the centre of its footprint (metadata/footprint, in tiles: '
                f'columns x rows); small props stand on their base. Move or swap the sprite here."\n'
                f'metadata/footprint = Vector2i({fw}, {fh})\n\n'
                f'[node name="Feet" type="Marker2D" parent="."]\n\n'
                f'[node name="Top" type="Marker2D" parent="."]\n'
                f'position = Vector2(0, {top})\n\n'
                f'[node name="Sprite" type="Sprite2D" parent="."]\n'
                f'texture_filter = 1\n'
                f'texture = ExtResource("1_tex")\n'
                f'centered = false\n'
                f'offset = Vector2({offset[0]}, {offset[1]})\n')
        with open(os.path.join(SCN, pid + ".tscn"), "w") as f:
            f.write(body)
        print(f"{pid}.tscn: offset {offset}, huella {fw}×{fh}")


def main():
    {"gen": gen, "proc": proc, "tscn": tscn}[sys.argv[1] if len(sys.argv) > 1 else "proc"]()


if __name__ == "__main__":
    main()
