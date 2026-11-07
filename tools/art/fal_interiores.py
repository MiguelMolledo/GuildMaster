#!/usr/bin/env python3
"""Referencias de interiores con fal (docs/arte/interiores.md): vistas isométricas en corte, como un diorama, de cada
interior de negocio, con la cámara y la proyección del juego (rombo 2:1 de 64×32, las dos paredes del fondo, sin las
del frente).

La referencia de cámara es la forja de hoy compuesta con Pillow a partir de su escena (game/visuals/interiors/forge.tscn:
suelo, paredes, puestos y mejoras en su sitio, con un personaje de 48 px para la escala), sin rótulos ni interfaz.
Las imágenes van a assets/art/interiors/_referencias/<interior>_<variante>.png; los crudos, fuera del repo
($GUILDMASTER_ARTE_CRUDOS/fal_produccion/interiores/). Cada llamada se apunta en assets/art/fal_piloto/gasto.json
(tanda «interiores») con su coste.

Uso:
  python3 tools/art/fal_interiores.py ref                      # compone las referencias de cámara
  python3 tools/art/fal_interiores.py gen --room forge --model nano2 --variant a
  python3 tools/art/fal_interiores.py tanda --model nano2      # las dos variantes de todos los interiores que falten
  python3 tools/art/fal_interiores.py total
"""
import argparse
import datetime
import os
import re
import sys
import time
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault("FAL_TANDA", "h16")  # fal_piloto solo para sus utilidades; el gasto se apunta como «interiores»
import fal_piloto as fpi  # noqa: E402
import fal_rutas as fr_  # noqa: E402

fpi.TANDA = "interiores"
ROOT = fr_.ROOT
import fal_client  # noqa: E402

RAW = fr_.produccion("interiores")
OUT = os.path.join(ROOT, "assets", "art", "interiors", "_referencias")
ART = os.path.join(ROOT, "assets", "art")
SCENE = os.path.join(ROOT, "game", "visuals", "interiors", "forge.tscn")

# id del modelo de fal -> (endpoint, USD por imagen; consultado en api.fal.ai/v1/models/pricing el 2026-11-04)
MODELS = {
    "nano2": ("fal-ai/nano-banana-2/edit", 0.08),
    "nanopro": ("fal-ai/nano-banana-pro/edit", 0.15),
    "seedream45": ("fal-ai/bytedance/seedream/v4.5/edit", 0.04),
}

STYLE = (
    "16-bit SNES-era pixel art in the style of Graveyard Keeper and Stardew Valley: crisp visible pixels, a dark "
    "one-colour outline, medium shading, light from the top-left, a warm earthy palette (browns, tans, terracotta, "
    "forest green, stone grey, gold, deep red) with warm orange firelight and cool blue shadows. "
)
CAMERA = (
    "The attached image is our game's current interior seen with the game camera: a 2:1 isometric diamond floor grid "
    "(tiles 64x32), only the two back walls (back-left and back-right) standing, the front walls cut away like a "
    "dollhouse diorama, the room floating on a plain flat black background, and a 48-pixel-tall person for scale. "
    "Keep EXACTLY this camera, projection, angle, room shape and scale (same floor diamond, same wall height, same size "
    "of the person), but repaint the room as a beautiful, cosy, richly detailed medieval interior. "
)
RULES = (
    " Walls: timber beams and plaster or stone with a window letting in light, shelves and hanging things on them. "
    "Floor: varied (planks, flagstones, packed earth, worn paths, a rug or straw), with small props scattered around. "
    "Soft drop shadows under the furniture, warm layered lighting with light pools on the floor. Everything stays on "
    "the isometric grid. No text, no letters, no UI, no labels, no people other than the one for scale, nothing outside "
    "the room, plain black background around it."
)

ROOMS = {
    "forge": ("a blacksmith's forge", "a big stone forge hearth with glowing coals and a leather bellows, a heavy anvil "
              "on a tree stump, a quenching tub of water with steam, a wall rack of tongs and hammers, a coal bin, a "
              "stack of iron ingots, a grindstone, orange sparks and a warm glow from the forge on the floor and walls"),
    "armory": ("an armourer's shop", "a long wooden sales counter with a ledger and a small scale, wall panoplies of "
               "swords, spears and shields, a wooden mannequin wearing a full suit of plate armour, a rack of helmets, "
               "chests of chainmail, banners, a lit candle stand"),
    "carpentry": ("a carpenter's workshop", "a big carpenter's workbench with a vice, a frame saw hanging on the wall, "
                  "stacked planks and logs, curly wood shavings and sawdust on the floor, a foot-powered pole lathe, "
                  "sawhorses, chairs and barrels half built, hand tools on a pegboard"),
    "masonry": ("a stonemason's yard workshop", "rough stone blocks and dressed ashlars, a carving bench with a half-"
                "carved statue, mallets and chisels, wooden templates and a square hanging on the wall, a small "
                "wooden crane with a rope, stone dust in the air and on the floor, rubble and chips"),
    "tailor_shop": ("a tailor's shop", "a large cutting table with fabric, shears and chalk, a spinning wheel and a "
                    "small loom, a dress form mannequin with a half-sewn gown, rolls and bolts of coloured cloth on "
                    "shelves, a fitting corner with a curtain and a mirror, thread spools, a candle"),
    "tavern": ("a tavern-inn common room", "a long wooden bar counter with casks of cider behind it, a big "
               "stone fireplace with a fire, rustic wooden tables with benches and mugs, a minstrel's corner with a "
               "small stage, a stool and a lute, a wooden staircase going up to the rooms, hanging lanterns and herbs"),
    "town_hall": ("a medieval town hall council chamber", "a long council table with chairs, parchments and a quill, "
                  "the mayor's carved high-backed bench on a low dais, coats of arms and heraldic shields on the walls, "
                  "a tall archive cabinet with scrolls and ledgers, banners, candelabras, a woven rug"),
    "court": ("a small medieval courtroom", "a raised judge's bench (dais) with a carved chair, the dock where the "
              "accused stands behind a wooden rail, a witness stand, benches for the public, a scribe's desk, a "
              "banner with the town's arms, candles; a solemn, slightly darker mood"),
    "house": ("a medieval family home", "a stone hearth with a cooking pot over the fire, a rustic dining table with "
              "stools and bread, two simple beds with wool blankets, a wooden chest at the foot of a bed, a cradle, "
              "hanging herbs and onions, a shelf with crockery"),
    "clinic": ("a medieval physician's practice", "a wooden examination cot with a white linen sheet, a small table "
               "with a big stone mortar and pestle and herbs, a tall apothecary shelf of glass jars, bottles and clay "
               "pots, a wicker basket of rolled linen bandages, a copper washbasin on a stand, bundles of herbs drying "
               "from the beams, a parchment chart of the human body on the wall, a waiting bench by the door"),
    "bank": ("a medieval money-changer's bank", "a long carved wooden banking counter with a brass balance scale, stacks "
             "of coins and an open ledger, a heavy iron-bound strongbox and an iron vault door in the back, a tall "
             "cabinet of ledgers and rolled contracts, a writing desk with a quill and a candle, a bench for the clients "
             "to wait, a rich rug, a banner with a coin emblem"),
    "church": ("the interior of a small village church", "a stone altar with a white cloth, candles and a cross, rows "
               "of wooden pews, a pulpit, a stained glass window casting coloured light, stone columns, a baptismal "
               "font, flowers"),
}
# variante -> lo que cambia del encargo
VARIANTS = {
    "a": "Daytime: sunlight from the window mixes with the warm interior light.",
    "b": "Evening: the room is lit only by its fires, candles and lanterns; deep warm glow and long soft shadows.",
}


# --- referencia de cámara (la forja de hoy, compuesta desde su escena) -------------------------------------------
TILE_W, TILE_H = 64, 32


def tile(c, r):
    return ((c - r) * TILE_W // 2, (c + r) * TILE_H // 2)


def _scene_items():
    """(posición, textura, offset) de los puestos y las mejoras de forge.tscn, leídos del texto de la escena."""
    s = open(SCENE).read()
    ext = {i: p for p, i in re.findall(r'path="res://([^"]+)" id="([^"]+)"', s)}
    items = []
    # puestos: el marcador da la posición; la escena del puesto, la textura y el offset
    for name, pos, inst in re.findall(r'\[node name="(\w+)" type="Marker2D" parent="Stations"\]\nposition = '
                                      r'Vector2\(([-\d., ]+)\)\n\n\[node name="\w+" parent="Stations/\w+" instance='
                                      r'ExtResource\("(\w+)"\)\]', s):
        st = open(os.path.join(ROOT, ext[inst])).read()
        tex = re.search(r'path="res://(assets/[^"]+\.png)"', st).group(1)
        off = re.search(r'offset = Vector2\(([-\d., ]+)\)', st).group(1)
        items.append((tuple(float(v) for v in pos.split(",")), tex, tuple(float(v) for v in off.split(","))))
    for name, pos in re.findall(r'\[node name="(\w+)" type="Node2D" parent="Upgrades"\]\nvisible = false\nposition = '
                                r'Vector2\(([-\d., ]+)\)', s):
        m = re.search(r'\[node name="Sprite" type="Sprite2D" parent="Upgrades/%s"\]\ntexture_filter = 1\ntexture = '
                      r'ExtResource\("(\w+)"\)\ncentered = false\noffset = Vector2\(([-\d., ]+)\)' % name, s)
        if m:
            items.append((tuple(float(v) for v in pos.split(",")), ext[m.group(1)],
                          tuple(float(v) for v in m.group(2).split(","))))
    return items


def _hero():
    """El herrero de 48 px (idle_se, primer fotograma) con sus colores clave (R=128, G=0: el shader de familia los
    pinta en el juego) pasados a una rampa de pardos, para que el modelo lo lea como una persona."""
    im = Image.open(os.path.join(ART, "characters", "artisan_m", "idle_se.png")).convert("RGBA").crop((0, 0, 68, 68))
    ramp = [(92, 58, 34), (141, 90, 53), (196, 150, 108), (226, 186, 146), (120, 40, 30), (70, 52, 40)]
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and r == 128 and g == 0:
                c = ramp[(b // 50) % len(ramp)]
                px[x, y] = c + (255,)
    return im


def compose_forge(size=(8, 6), upgrades=True):
    """La forja de hoy a escala 1 (como en el juego), en un lienzo con el origen en el centro de la casilla (0, 0)."""
    ox, oy = 200, 60
    W, H = 460, 280
    im = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = os.path.join(ART, "interiors", "forge")
    fl = Image.open(os.path.join(d, "floor.png")).convert("RGBA")
    for r in range(size[1]):
        for c in range(size[0]):
            x, y = tile(c, r)
            im.alpha_composite(fl, (ox + x - 32, oy + y - 16))
    wne = Image.open(os.path.join(d, "wall_ne.png")).convert("RGBA")
    wnw = Image.open(os.path.join(d, "wall_nw.png")).convert("RGBA")
    dnw = Image.open(os.path.join(d, "wall_door_nw.png")).convert("RGBA")
    for c in range(size[0]):
        x, y = tile(c, 0)
        im.alpha_composite(wne, (ox + x, oy + y - 16 - 36))
    for r in range(size[1]):
        x, y = tile(0, r)
        im.alpha_composite(dnw if r == 3 else wnw, (ox + x - 32, oy + y - 16 - 36))
    items = [it for it in _scene_items() if upgrades or "upg_" not in it[1]]
    hero = _hero()
    items.append(((40.0, 120.0), None, (-34.0, -60.0)))
    for (px, py), tex, (dx, dy) in sorted(items, key=lambda t: t[0][1]):
        spr = hero if tex is None else Image.open(os.path.join(ROOT, tex)).convert("RGBA")
        im.alpha_composite(spr, (int(ox + px + dx), int(oy + py + dy)))
    return im


def ref():
    os.makedirs(os.path.join(RAW, "ref"), exist_ok=True)
    out = {}
    for name, ups in (("forge_hoy", True), ("forge_vacia", False)):
        im = compose_forge(upgrades=ups)
        p = os.path.join(RAW, "ref", name + "_x1.png")
        im.save(p)
        big = im.resize((im.width * 3, im.height * 3), Image.NEAREST)  # 1380×840: legible para el modelo
        canvas = Image.new("RGBA", (1456, 816), (0, 0, 0, 255))
        canvas.alpha_composite(big.crop((0, 12, 1380, 828)), (38, 0))
        p = os.path.join(RAW, "ref", name + ".png")
        canvas.convert("RGB").save(p)
        out[name] = p
        print("ref ->", p)
    return out


# --- generación ------------------------------------------------------------------------------------------------
def prompt(room, variant):
    what, items = ROOMS[room]
    return (CAMERA + STYLE + f"The room is {what}: {items}. " + VARIANTS[variant] + RULES)


def gen(room, model, variant, tag=""):
    endpoint, unit = MODELS[model]
    name = f"{room}_{variant}{('_' + tag) if tag else ''}"
    dst = os.path.join(OUT, name + ".png")
    if os.path.exists(dst):
        print("ya está", os.path.relpath(dst, ROOT))
        return dst
    fpi.guard(unit)
    refp = os.path.join(RAW, "ref", "forge_hoy.png" if room == "forge" else "forge_vacia.png")
    if not os.path.exists(refp):
        ref()
    args = {"prompt": prompt(room, variant), "image_urls": [fal_client.upload_file(refp)], "num_images": 1}
    if model.startswith("nano"):
        args.update({"aspect_ratio": "16:9", "output_format": "png"})
    else:
        args.update({"image_size": {"width": 2048, "height": 1152}})
    print(f"{endpoint} | {name} | {unit:.3f} USD (tanda interiores: {fpi.total():.3f})")
    t0 = time.time()
    res = fal_client.subscribe(endpoint, arguments=args)
    raw = os.path.join(RAW, "crudo", name + ".png")
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    urllib.request.urlretrieve(res["images"][0]["url"], raw)
    fpi.note("interiores", endpoint, 1, unit, f"referencia {name} ({time.time() - t0:.0f} s)")
    with open(os.path.join(RAW, "crudo", "prompts.log"), "a") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {name} | {endpoint} | ref={os.path.basename(refp)}\n"
                f"  {args['prompt']}\n\n")
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(raw).convert("RGB")
    if im.width > 1600:  # en el repo, a 1456 de ancho (basta para mirarla; el crudo queda fuera)
        im = im.resize((1456, round(im.height * 1456 / im.width)), Image.LANCZOS)
    # en el repo, en PNG de paleta (256 colores): ~0,5 MB en vez de 2; la carpeta lleva .gdignore (Godot no la importa)
    im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(dst, optimize=True)
    print("  ->", os.path.relpath(dst, ROOT), im.size)
    return dst


# --- piloto de la forja: fondo pintado (suelo + paredes) y piezas sueltas ---------------------------------------
# Geometría del fondo: la sala de forge.tscn (8×6, puerta en (0, 3) de la pared izquierda) con paredes de WALL_H px.
SIZE = (8, 6)
DOOR_ROW = 3
WALL_H = 64
BOX = (-192, -16 - WALL_H, 256, 208)  # izquierda, arriba, derecha, abajo, desde el centro de la casilla (0, 0)
TPL_K = 3                              # la plantilla va a ×3 en un lienzo 3:2
TPL_SIZE = (1500, 1000)


def room_polys():
    top, right = (0, -16), (SIZE[0] * 32, (SIZE[0] - 1) * 16 + 16 - 16 + 0)
    top = (0, -16)
    right = (SIZE[0] * 32, SIZE[0] * 16 - 16)
    bottom = ((SIZE[0] - SIZE[1]) * 32, (SIZE[0] + SIZE[1]) * 16 - 16)
    left = (-SIZE[1] * 32, SIZE[1] * 16 - 16)
    up = lambda p: (p[0], p[1] - WALL_H)  # noqa: E731
    floor = [top, right, bottom, left]
    ne = [top, right, up(right), up(top)]
    nw = [left, top, up(top), up(left)]
    # la puerta: en el tramo de la casilla (0, DOOR_ROW), del 20 al 80 %, 52 px de alto (escala B)
    a = (-(DOOR_ROW + 1) * 32, (DOOR_ROW + 1) * 16 - 16)
    b = (-DOOR_ROW * 32, DOOR_ROW * 16 - 16)
    pa = (a[0] + (b[0] - a[0]) * 0.2, a[1] + (b[1] - a[1]) * 0.2)
    pb = (a[0] + (b[0] - a[0]) * 0.8, a[1] + (b[1] - a[1]) * 0.8)
    door = [pa, pb, (pb[0], pb[1] - 52), (pa[0], pa[1] - 52)]
    return {"floor": floor, "ne": ne, "nw": nw, "door": door}


def _to_px(poly, k=1, off=(0, 0)):
    return [((x - BOX[0]) * k + off[0], (y - BOX[1]) * k + off[1]) for x, y in poly]


def template():
    """La plantilla de geometría (colores planos) a ×3 en un lienzo 3:2, y la máscara de la sala a ×1."""
    from PIL import ImageDraw
    w1, h1 = BOX[2] - BOX[0], BOX[3] - BOX[1]
    off = ((TPL_SIZE[0] - w1 * TPL_K) // 2, (TPL_SIZE[1] - h1 * TPL_K) // 2)
    im = Image.new("RGB", TPL_SIZE, (0, 0, 0))
    d = ImageDraw.Draw(im)
    P = room_polys()
    d.polygon(_to_px(P["floor"], TPL_K, off), fill=(112, 98, 82))
    for c in range(SIZE[0] + 1):  # la rejilla de casillas, tenue
        a, b = (c * 32, c * 16 - 16), (c * 32 - SIZE[1] * 32, c * 16 - 16 + SIZE[1] * 16)
        d.line(_to_px([a, b], TPL_K, off), fill=(98, 85, 71), width=2)
    for r in range(SIZE[1] + 1):
        a, b = (-r * 32, r * 16 - 16), (-r * 32 + SIZE[0] * 32, r * 16 - 16 + SIZE[0] * 16)
        d.line(_to_px([a, b], TPL_K, off), fill=(98, 85, 71), width=2)
    d.polygon(_to_px(P["ne"], TPL_K, off), fill=(196, 176, 146))
    d.polygon(_to_px(P["nw"], TPL_K, off), fill=(168, 148, 118))
    d.polygon(_to_px(P["door"], TPL_K, off), fill=(70, 44, 26), outline=(40, 24, 14))
    os.makedirs(os.path.join(RAW, "ref"), exist_ok=True)
    p = os.path.join(RAW, "ref", "forge_plantilla.png")
    im.save(p)
    mask = Image.new("L", (w1, h1), 0)
    dm = ImageDraw.Draw(mask)
    for k in ("floor", "ne", "nw"):
        dm.polygon(_to_px(P[k]), fill=255)
    mask.save(os.path.join(RAW, "ref", "forge_mascara.png"))
    print("plantilla ->", p, "offset", off)
    return p, off


FONDO_PROMPT = (
    "Image 1 is an exact layout template of a room in our isometric game: a 2:1 isometric floor of 8 by 6 tiles and "
    "its two back walls, with a door on the back-left wall. Image 2 is the art direction for this room (a blacksmith's "
    "forge). Repaint image 1 as the EMPTY shell of that forge in exactly the 16-bit pixel art style of image 2: keep "
    "every edge, corner, the wall height and the door EXACTLY where they are in image 1 (same outline, nothing outside "
    "it, plain flat black background). Back walls: dark timber frame (posts, a top beam and braces) filled with "
    "warm plaster on the right wall and old brick on the left wall, a small leaded window with daylight on the right "
    "wall, a wall rack of tongs and hammers, a shelf with jars and a candle, a hanging lantern, horseshoes on nails, "
    "a sooty patch on the wall at the back corner, a wooden plank door with iron hinges in the door opening. Floor: "
    "worn flagstones mixed with packed earth and a few old planks, a soot and coal-dust stain near the back corner, a "
    "warm light pool from the window, a worn path from the door, a straw patch, a few nails and a horseshoe lying "
    "flat. The floor must stay EMPTY: no furniture, no forge, no anvil, no barrels, no tables, no people, only flat "
    "things lying on it. Light from the top-left, warm palette, crisp pixels, dark outlines on the wall details. No "
    "text, no letters, no UI."
)


def fondo(tag, model="nano2"):
    endpoint, unit = MODELS[model]
    raw = os.path.join(RAW, "crudo", f"forge_fondo_{tag}.png")
    if os.path.exists(raw):
        print("ya está", raw)
        return raw
    tpl, _ = template()
    fpi.guard(unit)
    args = {"prompt": FONDO_PROMPT, "num_images": 1, "aspect_ratio": "3:2", "output_format": "png",
            "image_urls": [fal_client.upload_file(tpl), fal_client.upload_file(os.path.join(OUT, "forge_b.png"))]}
    print(f"{endpoint} | forge_fondo_{tag} | {unit:.3f} USD (tanda interiores: {fpi.total():.3f})")
    res = fal_client.subscribe(endpoint, arguments=args)
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    urllib.request.urlretrieve(res["images"][0]["url"], raw)
    fpi.note("interiores", endpoint, 1, unit, f"piloto forja: fondo {tag}")
    with open(os.path.join(RAW, "crudo", "prompts.log"), "a") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | forge_fondo_{tag} | {endpoint} | ref=plantilla,forge_b\n"
                f"  {FONDO_PROMPT}\n\n")
    print("  ->", raw)
    return raw


# Piezas sueltas del piloto: rejilla 2×2 de celdas de 512 (cada pieza en una rejilla de 64 = bloques de 8), como la
# taberna (tools/art/fal_taberna.py), con la referencia de la forja (estilo) y el kit de hoy ×4 (proyección y escala).
PIECES = {
    "furnace": ((80, 96), "a blacksmith's forge hearth of rough grey stone blocks, waist-high, with a bed of glowing "
                          "orange coals on top and a short stone chimney hood rising at its back, soot stains, an "
                          "iron poker leaning on it (no bellows)"),
    "anvil": ((64, 64), "a heavy black iron anvil on a thick tree stump, a hammer and tongs resting on it"),
    "coal_bin": ((64, 64), "a low wooden bin full of black coal with a shovel stuck in it, and a small stack of iron "
                           "ingots beside it"),
    "grindstone": ((64, 64), "a round grindstone wheel on a wooden frame with a crank handle and a small water trough"),
}
PIECE_GRID = ["furnace", "anvil", "coal_bin", "grindstone"]
POS = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]


def _kit_sheet():
    names = ["anvil", "furnace", "storage", "counter"]
    sheet = Image.new("RGB", (4 * 320, 320), (255, 255, 255))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(ART, "interiors", "forge", n + ".png")).convert("RGBA")
        im = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
        tmp = Image.new("RGBA", (320, 320), (255, 255, 255, 255))
        tmp.alpha_composite(im, ((320 - im.width) // 2, 320 - im.height))
        sheet.paste(tmp.convert("RGB"), (i * 320, 0))
    p = os.path.join(RAW, "ref", "kit_forja_x4.png")
    sheet.save(p)
    return p


def piezas(tag="v1", model="nano2"):
    endpoint, unit = MODELS[model]
    raw = os.path.join(RAW, "crudo", f"forge_piezas_{tag}.png")
    if os.path.exists(raw):
        print("ya está", raw)
        return raw
    what = " ".join(f"{pos}: {PIECES[i][1]}." for pos, i in zip(POS, PIECE_GRID))
    prompt = ("Image 1 is the art direction (a blacksmith's forge in our game). Image 2 shows some of our current "
              "isometric 2:1 interior sprites, enlarged 4x, for the projection, camera and pixel size. Create ONE "
              "square image that is a 2x2 grid of four NEW pieces of furniture for the forge, drawn in the style, "
              "palette and lighting of image 1 (warm, detailed 16-bit pixel art, light from the top-left, a dark "
              "1-pixel outline) and with the projection and camera of image 2. Each piece is drawn on a 64x64 pixel "
              "grid (every art pixel is an 8x8 block of its 512x512 cell), standing on the bottom of its cell, "
              "centred, on a plain flat white background, no floor tile under it. " + what +
              " No text, no letters, no grid lines, no shadow on the background.")
    fpi.guard(unit)
    args = {"prompt": prompt, "num_images": 1, "aspect_ratio": "1:1", "output_format": "png",
            "image_urls": [fal_client.upload_file(os.path.join(OUT, "forge_b.png")),
                           fal_client.upload_file(_kit_sheet())]}
    print(f"{endpoint} | forge_piezas_{tag} | {unit:.3f} USD (tanda interiores: {fpi.total():.3f})")
    res = fal_client.subscribe(endpoint, arguments=args)
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    urllib.request.urlretrieve(res["images"][0]["url"], raw)
    fpi.note("interiores", endpoint, 1, unit, f"piloto forja: piezas {tag}")
    with open(os.path.join(RAW, "crudo", "prompts.log"), "a") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | forge_piezas_{tag} | {endpoint} | ref=forge_b,kit\n"
                f"  {prompt}\n\n")
    print("  ->", raw)
    return raw


# qué rejilla da cada pieza (revisadas a ojo el 2026-11-04)
PIECE_PICK = {"furnace": "v1", "anvil": "v2", "coal_bin": "v1", "grindstone": "v2"}
# tamaño de pixelado (bloques de N px en la celda de 512): 8 = pieza de ~53 px; la fragua, a 6 (~70 px), que manda
PIECE_SCALE = {"furnace": 6}
FORGE_ART = os.path.join(ART, "interiors", "forge")


def proc_piezas():
    from types import SimpleNamespace
    import fal_fachadas
    import fal_iconos as fic
    import fal_procesar as fp
    for pid, tag in PIECE_PICK.items():
        raw = os.path.join(RAW, "crudo", f"forge_piezas_{tag}.png")
        im = Image.open(raw).convert("RGBA").resize((1024, 1024))
        k = PIECE_GRID.index(pid)
        x0, y0 = (k % 2) * 512, (k // 2) * 512
        cell = im.crop((x0 + 8, y0 + 8, x0 + 504, y0 + 504))  # fuera las líneas de la rejilla
        cell = cell.resize((512, 512), Image.LANCZOS)
        keyed = fal_fachadas.holes(fp.key_background(cell, "white", 28))
        src = os.path.join(RAW, "celdas", pid + ".png")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        keyed.save(src)
        sc = PIECE_SCALE.get(pid, 8)
        dst = os.path.join(RAW, "i2p", f"{pid}_s{sc}.png")
        if not os.path.exists(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            fpi.pixel(SimpleNamespace(piece="interiores", src=src, dst=dst, colors=24, scale=sc, palette="",
                                      transparent=True))
        up = Image.open(dst).convert("RGBA")
        nat = up.resize((up.width // sc, up.height // sc), Image.NEAREST)
        nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
        import fal_props
        c = fal_props.soft_outline(nat.crop(nat.getchannel("A").getbbox()))  # el contorno del fondo (04g §4.6.5.1)
        (w, h) = PIECES[pid][0]
        if c.width > w or c.height > h:
            k2 = min(w / c.width, h / c.height)
            c = c.resize((max(1, int(c.width * k2)), max(1, int(c.height * k2))), Image.NEAREST)
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        canvas.alpha_composite(c, ((w - c.width) // 2, h - c.height - 1))
        out = os.path.join(FORGE_ART, ("hearth" if pid == "furnace" else "anvil_stump" if pid == "anvil" else pid)
                           + ".png")
        canvas.save(out)
        print(f"{pid}: {c.width}×{c.height} en {w}×{h} -> {os.path.relpath(out, ROOT)}")


def proc_fondo(tag="v2", colors=48):
    """El fondo elegido a ×1 (448×288): de la plantilla ×3 a ×1 con BOX, paleta de `colors` y la máscara de la sala."""
    raw = os.path.join(RAW, "crudo", f"forge_fondo_{tag}.png")
    template()
    im = Image.open(raw).convert("RGB").resize(TPL_SIZE, Image.LANCZOS)
    w1, h1 = BOX[2] - BOX[0], BOX[3] - BOX[1]
    off = ((TPL_SIZE[0] - w1 * TPL_K) // 2, (TPL_SIZE[1] - h1 * TPL_K) // 2)
    room = im.crop((off[0], off[1], off[0] + w1 * TPL_K, off[1] + h1 * TPL_K)).resize((w1, h1), Image.BOX)
    q = room.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    q.putalpha(Image.open(os.path.join(RAW, "ref", "forge_mascara.png")))
    out = os.path.join(FORGE_ART, "backdrop.png")
    q.save(out)
    print(f"fondo {tag}: {w1}×{h1}, {colors} colores -> {os.path.relpath(out, ROOT)} (origen de la casilla (0, 0) en "
          f"({-BOX[0]}, {-BOX[1]}))")


def luz():
    """Las capas de luz de la forja, dibujadas con Pillow (pixel art, sin degradado suave): el halo de la fragua
    (elipse 2:1 en tres bandas con borde tramado, para sumar con blend Add) y la brasa de 1 px de las chispas."""
    W, H = 208, 104
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    bands = [(0.34, (255, 176, 84, 150)), (0.64, (245, 125, 52, 92)), (1.0, (205, 84, 32, 48))]
    for y in range(H):
        for x in range(W):
            d = ((x + 0.5 - W / 2) / (W / 2)) ** 2 + ((y + 0.5 - H / 2) / (H / 2)) ** 2
            d = d ** 0.5
            for i, (r, c) in enumerate(bands):
                edge = r - 0.06
                if d < edge or (d < r and (x + y) % 2 == 0):  # borde de cada banda tramado en damero
                    px[x, y] = c
                    break
    im.save(os.path.join(FORGE_ART, "glow_hearth.png"))
    e = Image.new("RGBA", (1, 1), (255, 255, 255, 255))
    e.save(os.path.join(FORGE_ART, "ember.png"))
    print(f"luz: glow_hearth.png {W}×{H}, ember.png 1×1")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ref")
    g = sub.add_parser("gen")
    g.add_argument("--room", choices=list(ROOMS), required=True)
    g.add_argument("--model", choices=list(MODELS), default="nano2")
    g.add_argument("--variant", choices=list(VARIANTS), default="a")
    g.add_argument("--tag", default="")
    t = sub.add_parser("tanda")
    t.add_argument("--model", choices=list(MODELS), default="nano2")
    sub.add_parser("total")
    fo = sub.add_parser("fondo")
    fo.add_argument("--tag", default="v1")
    fo.add_argument("--model", choices=list(MODELS), default="nano2")
    sub.add_parser("plantilla")
    pz = sub.add_parser("piezas")
    pz.add_argument("--tag", default="v1")
    pz.add_argument("--model", choices=list(MODELS), default="nano2")
    sub.add_parser("proc")
    sub.add_parser("luz")
    a = p.parse_args()
    if a.cmd == "ref":
        ref()
    elif a.cmd == "gen":
        gen(a.room, a.model, a.variant, a.tag)
    elif a.cmd == "tanda":
        for room in ROOMS:
            for v in VARIANTS:
                gen(room, a.model, v)
    elif a.cmd == "fondo":
        fondo(a.tag, a.model)
    elif a.cmd == "proc":
        proc_fondo()
        proc_piezas()
    elif a.cmd == "luz":
        luz()
    elif a.cmd == "piezas":
        piezas(a.tag, a.model)
    elif a.cmd == "plantilla":
        template()
    else:
        print(f"interiores: {fpi.total():.4f} USD")


if __name__ == "__main__":
    main()
