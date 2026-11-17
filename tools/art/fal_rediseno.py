#!/usr/bin/env python3
"""Rediseño de la ciudad (rama rediseno-ciudad): árboles, decoración de calle, puestos del mercado y monumentos de la
capital, a la escala B (personaje 48 px, casa de 2 plantas 176 px) y a densidad 1:1.

Misma vía que la tanda ciudad2d (la que mejor salió): cada lámina es una maqueta gris a la escala del juego (las
siluetas de lo que se pide, en su sitio y a su tamaño, ampliadas ×block) más una hoja de estilo con sprites del
juego; fal nano-banana-2/edit la repinta y se pasa a pixel art en local (fal_ciudad2d.local_pixel, el píxel medido),
con el tamaño final forzado al de la maqueta, contorno de 1 px y, en árboles y piezas altas, sombra al pie (luz de
arriba a la izquierda: la sombra cae abajo a la derecha).

Uso: FAL_TANDA=rediseno python3 tools/art/fal_rediseno.py ref|gen|proc|hoja [lámina ...]
  ref   maquetas y hoja de estilo (gratis)            -> $CRUDOS/fal_produccion/rediseno/
  gen   genera las láminas que falten (0,08 USD cada una a 1K; 0,12 a 2K)
  proc  recorta, pixela y guarda en assets/art/      (props/, buildings/stalls/, buildings/landmarks/)
  hoja  hoja de revisión con todo junto al personaje  -> $CRUDOS/fal_produccion/rediseno/hoja.png
  gen_espaldas|proc_espaldas house_<c>x<r>_<k> ...   vista de espaldas de las casas de lote (sin la puerta delantera)
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
from fal_casas_bloque import largest  # noqa: E402
from fal_ciudad2d import local_pixel  # noqa: E402
from fal_props_fiesta import no_grid_lines  # noqa: E402

ROOT = fr_.ROOT
P = fr_.produccion("rediseno")
ART = os.path.join(ROOT, "assets", "art")
GREY_L, GREY_D, GREY_M = (205, 205, 205), (150, 150, 150), (178, 178, 178)
OUT_C = (60, 60, 60)

# ---------------------------------------------------------------------------------------------------------------
# Piezas: id -> (carpeta de salida, (ancho, alto) objetivo en px de arte, forma de la maqueta, descripción, opciones)
# opciones: shadow (sombra al pie), fit ("h" alto | "w" ancho | "box" cabe), whole (solo la mancha mayor)
# ---------------------------------------------------------------------------------------------------------------
TREE = "props"
PIECES = {}


def piece(pid, out, size, shape, desc, **kw):
    PIECES[pid] = dict(out=out, size=size, shape=shape, desc=desc, **kw)


# Árboles (luz de arriba a la izquierda, tamaños frente a la casa de 176 px)
_OAK = ("a broad old oak tree: thick gnarled brown trunk, a wide rounded crown of dense dark and mid green leaf "
        "clumps, lit from the top-left")
piece("tree_oak_1", TREE, (104, 124), ("crown", 104, 86, 10, 40), _OAK + ", full and round", shadow=True, fit="h")
piece("tree_oak_2", TREE, (110, 118), ("crown", 110, 80, 11, 40), _OAK + ", wider and slightly lopsided to one side",
      shadow=True, fit="h")
piece("tree_oak_3", TREE, (96, 128), ("crown", 96, 92, 10, 38), _OAK + ", taller, with two big clumps of leaves",
      shadow=True, fit="h")
piece("tree_oak_4", TREE, (80, 96), ("crown", 80, 66, 8, 32), "a young oak tree, slimmer trunk, a smaller rounded "
      "crown of fresh green leaves, lit from the top-left", shadow=True, fit="h")
_CHESTNUT = ("a sweet chestnut tree: straight furrowed brown trunk, a tall dome-shaped crown of long serrated "
             "leaves in deep green with lighter yellow-green tips")
piece("tree_chestnut_1", TREE, (92, 120), ("crown", 92, 88, 9, 36), _CHESTNUT, shadow=True, fit="h")
piece("tree_chestnut_2", TREE, (100, 112), ("crown", 100, 80, 10, 36), _CHESTNUT + ", broader", shadow=True, fit="h")
piece("tree_chestnut_3", TREE, (84, 124), ("crown", 84, 94, 9, 34), _CHESTNUT + ", taller and narrower",
      shadow=True, fit="h")
piece("tree_willow_1", TREE, (100, 108), ("willow", 100, 84, 10, 30), "a weeping willow by a river: short thick "
      "trunk, long hanging curtains of thin pale green leaves drooping to the ground", shadow=True, fit="h")
_POPLAR = ("a tall slender Lombardy poplar tree by a river: a narrow upright column-shaped crown of small "
           "shimmering green leaves, thin grey-brown trunk")
piece("tree_poplar_1", TREE, (40, 150), ("column", 40, 128, 6, 26), _POPLAR, shadow=True, fit="h")
piece("tree_poplar_2", TREE, (46, 140), ("column", 46, 118, 6, 26), _POPLAR + ", a little wider", shadow=True,
      fit="h")
piece("tree_poplar_3", TREE, (36, 128), ("column", 36, 106, 5, 24), _POPLAR + ", younger", shadow=True, fit="h")
piece("tree_willow_2", TREE, (88, 96), ("willow", 88, 74, 9, 26), "a smaller weeping willow, hanging curtains of "
      "thin pale green leaves", shadow=True, fit="h")
_PINE = "a Scots pine tree: tall straight orange-brown trunk, a flat-topped irregular crown of dark blue-green needles"
_FIR = "a dark green fir tree: a tall pointed cone of layered needle branches, short brown trunk"
piece("tree_pine_1", TREE, (68, 132), ("umbrella", 68, 64, 7, 68), _PINE, shadow=True, fit="h")
piece("tree_pine_2", TREE, (74, 120), ("umbrella", 74, 56, 7, 64), _PINE + ", with two layers of crown",
      shadow=True, fit="h")
piece("tree_fir_1", TREE, (60, 128), ("cone", 60, 116, 6, 12), _FIR, shadow=True, fit="h")
piece("tree_fir_2", TREE, (52, 108), ("cone", 52, 98, 5, 10), _FIR + ", a bit smaller", shadow=True, fit="h")
# Frutales y arbustos
piece("tree_apple_1", TREE, (64, 74), ("crown", 64, 50, 6, 26), "a small apple tree in an orchard: short crooked "
      "trunk, a rounded crown of green leaves dotted with red apples", shadow=True, fit="h")
piece("tree_apple_2", TREE, (70, 70), ("crown", 70, 46, 6, 26), "a small apple tree in white and pink spring "
      "blossom, short crooked trunk, a rounded crown", shadow=True, fit="h")
piece("tree_pear_1", TREE, (56, 80), ("crown", 56, 56, 6, 26), "a small pear tree: upright oval crown of glossy "
      "green leaves with a few yellow-green pears, slim trunk", shadow=True, fit="h")
piece("tree_cherry_1", TREE, (66, 72), ("crown", 66, 48, 6, 26), "a small cherry tree with dark red cherries in "
      "a rounded crown of green leaves, reddish-brown trunk", shadow=True, fit="h")
piece("bush_1", "props", (34, 24), ("bush", 34, 22), "a round green shrub, dense leaves", shadow=True, fit="h")
piece("bush_2", "props", (32, 24), ("bush", 32, 22), "a green shrub with small pink and white flowers",
      shadow=True, fit="h")
piece("bush_3", "props", (40, 26), ("bush", 40, 24), "a low wild bramble bush with dark leaves and a few berries",
      shadow=True, fit="h")
piece("hedge_1", "props", (48, 34), ("hedge",), "a short straight segment of a neatly trimmed green box hedge, "
      "running diagonally along the isometric grid, about knee high", fit="w")

# Decoración de calle
piece("planter", "props", (34, 26), ("box", 0.55, 0.25, 12), "a long wooden planter box full of red and yellow "
      "flowers and green leaves", fit="w")
piece("flower_pots", "props", (28, 22), ("pots",), "three terracotta clay pots of different sizes with red "
      "geraniums and green herbs", fit="box", whole=False)
piece("beehive", "props", (22, 30), ("post", 16, 28), "a domed straw bee skep on a small wooden stand", fit="h")
piece("trough", "props", (44, 24), ("box", 0.8, 0.3, 12), "a long wooden water trough for horses, full of water",
      fit="w")
piece("wattle_fence", "props", (36, 30), ("fence",), "a short straight segment of a woven wattle fence of brown "
      "hazel branches between stakes, running diagonally along the isometric grid", fit="w")
piece("fence_gate", "props", (36, 34), ("fence",), "a small wooden garden gate between two posts, running "
      "diagonally along the isometric grid", fit="w")
piece("hay_cart", "props", (58, 46), ("box", 1.0, 0.5, 26), "a two-wheeled wooden farm cart loaded high with "
      "golden hay", fit="w")
piece("scarecrow", "props", (26, 52), ("post", 24, 50), "a scarecrow on a pole: straw head with a battered hat, "
      "an old patched brown coat on a cross stick", fit="h")
piece("barrel_stack", "props", (40, 38), ("box", 0.6, 0.45, 26), "three wooden barrels with iron hoops, two "
      "standing and one lying on top", fit="w", whole=False)
piece("crate_stack", "props", (36, 38), ("box", 0.55, 0.45, 28), "a stack of three wooden crates, some with "
      "apples and cabbages", fit="w", whole=False)
piece("woodpile", "props", (48, 32), ("box", 0.8, 0.35, 20), "a neat pile of chopped firewood logs stacked "
      "against a wall, with an axe stuck in a chopping block beside it", fit="w", whole=False)
piece("haystack", "props", (46, 44), ("dome", 46, 40), "a round golden haystack with a pole in the middle",
      shadow=True, fit="w")
piece("stone_cross", "props", (24, 60), ("post", 22, 58), "a medieval stone wayside cross on a stepped stone "
      "base, grey weathered granite with a little moss", shadow=True, fit="h")
piece("fountain", "props", (78, 64), ("fountain",), "a medieval town fountain: a wide octagonal stone basin full of "
      "blue water with a carved stone pillar in the middle and small spouts pouring water", fit="w")
piece("well_roof", "props", (44, 66), ("post", 40, 62), "a village well: round stone wall, a small wooden "
      "pitched roof with dark shingles on two posts, a crank, a rope and a wooden bucket", fit="h")
piece("pillory_post", "props", (30, 56), ("post", 26, 54), "a wooden market notice post with a small pitched "
      "roof and blank pinned papers (no writing)", fit="h")
piece("clothesline", "props", (64, 50), ("line",), "a clothesline between two wooden posts with white, blue and "
      "red laundry hanging, running diagonally along the isometric grid", fit="w", whole=False)
piece("market_banner", "props", (22, 80), ("post", 18, 78), "a tall wooden pole with a long hanging swallow-tailed "
      "red and gold cloth banner (no emblem with letters)", fit="h")
piece("hens", "props", (34, 20), ("blobs", 3), "three brown and white hens pecking on the ground", fit="w",
      whole=False)
piece("dog", "props", (28, 18), ("blobs", 1), "a brown and white farm dog lying curled on the ground", fit="w")
for _k, (_what, _sym) in enumerate([("forge", "a black anvil"), ("tailor", "a pair of scissors and a spool"),
                                     ("carpenter", "a saw and a hammer"), ("inn", "a foaming tankard")]):
    piece(f"sign_{_what}", "props", (30, 54), ("sign",), "a wooden sign post with an iron bracket and a hanging "
          f"wooden signboard painted with {_sym} (a picture only, no letters or words)", fit="h")

# Puestos del mercado: misma maqueta (mostrador, cuatro postes y toldo), cada gremio con su color de toldo
_STALL = ("a medieval market stall in a common style: a sturdy wooden counter facing the viewer (front-left), four "
          "wooden posts, a sloping cloth awning with a scalloped edge; ")
STALL_LOOK = {
    "stall_food": "red and white striped awning; on the counter round loaves of bread, cheese wheels, cabbages, "
                  "onions and baskets of apples",
    "stall_goods": "green and white striped awning; on the counter clay jugs and pots, woven baskets, wooden bowls "
                   "and spoons, a lantern",
    "stall_materials": "blue and white striped awning; on the counter iron bars, a box of nails, coils of rope, "
                       "stacked planks leaning on it and a folded leather hide",
    "stall_clothier": "purple and white striped awning; on the counter folded bolts of coloured cloth, a tunic and a "
                      "cloak hanging from the awning rail",
    "stall_resources": "ochre and brown striped awning; on the counter and around it sacks of grain, a basket of "
                       "coal, lumps of ore and bundles of firewood",
    "stall_apothecary": "teal and cream striped awning; on the counter glass jars and clay pots of remedies, a "
                        "mortar and pestle, bundles of dried herbs hanging from the awning rail",
    "stall_livestock": "no counter: a small square wooden pen with two white sheep and a goat inside, a hay rack, and "
                       "one post with a small plain brown cloth awning over a stool",
    "stall_spare": "orange and white striped awning; on the counter wooden toys, ribbons and trinkets",
}
for _sid, _look in STALL_LOOK.items():
    piece(_sid, None if _sid == "stall_spare" else "buildings", (80, 100), ("stall", _sid == "stall_livestock"), _STALL + _look, fit="w")

# Monumentos de la capital (huella en casillas y altura de muros/torres a la escala B)
piece("cathedral", "buildings/landmarks", None, ("cathedral",), "a gothic cathedral of warm grey limestone: two tall "
      "square west towers with pointed slate spires facing front-right, a high nave with a steep blue-grey slate "
      "roof, flying buttresses, tall pointed stained-glass windows along the nave, a big rose window and a carved "
      "pointed portal between the towers", fit="w", foot=(10, 6), whole=True)
piece("church", "buildings/landmarks", None, ("church",), "a romanesque parish church of warm grey stone: a nave "
      "with a red clay tile roof, small round-arched windows, a square bell tower with a pyramid slate roof at "
      "the front-right end, a round apse at the back", fit="w", foot=(5, 3), whole=True)
piece("customs", "buildings/landmarks", None, ("hall", 2, "hip"), "the customs house of a river port: a two-storey "
      "building of ochre stone, an arcade of round arches on the ground floor, upper floor with small windows and a "
      "hipped red tile roof, a coat of arms shield without letters over the arcade", fit="w", foot=(4, 3),
      whole=True)
piece("warehouse", "buildings/landmarks", None, ("hall", 3, "gable"), "a three-storey merchant warehouse of red "
      "brick and dark timber: big wooden loading doors on every floor, a hoist beam with a pulley under the gable, "
      "a steep brown tile roof", fit="w", foot=(5, 3), whole=True)
piece("exchange", "buildings/landmarks", None, ("hall", 1, "flat"), "a gothic merchants' exchange hall (lonja): one "
      "tall storey of pale golden stone with big pointed arched windows, a crenellated parapet with small corner "
      "turrets, a carved portal", fit="w", foot=(5, 3), whole=True)
piece("wall_tower", "buildings/landmarks", None, ("tower", False), "a square stone tower of a town wall: grey "
      "rubble stone, narrow arrow slits, a crenellated top with a small wooden hoarding", fit="w", foot=(2, 2),
      whole=True)
piece("gate_tower", "buildings/landmarks", None, ("tower", True), "a square stone gate tower of a town wall: grey "
      "stone, a tall pointed arch gateway with an open wooden gate at the bottom, a pointed slate roof on top and "
      "a red and gold banner", fit="w", foot=(2, 2), whole=True)
piece("crane", "buildings/landmarks", None, ("crane",), "a medieval wooden harbour treadwheel crane: a square timber "
      "tower with a small shingled roof and a long jib arm with a rope and hook", fit="h", foot=(1, 1), whole=True)
piece("wall_1", "buildings/landmarks", None, ("wall",), "one block of a medieval town wall of grey rubble stone "
      "with crenellations on top", fit="w", foot=(1, 1), whole=True)
piece("wall_2", "buildings/landmarks", None, ("wall",), "one block of a medieval town wall of grey rubble stone "
      "with crenellations on top and a little ivy", fit="w", foot=(1, 1), whole=True)

# Láminas: nombre -> (block, lado del lienzo en px de la imagen, resolución, celdas [(id, x, y, w, h) en px de arte])
def grid4(ids, block, side=1024):
    n = side // block // 2
    return [(i, (k % 2) * n, (k // 2) * n, n, n) for k, i in enumerate(ids)]


SHEETS = {
    "arboles_roble": (3, 1024, "", grid4(["tree_oak_1", "tree_oak_2", "tree_oak_3", "tree_oak_4"], 3)),
    "arboles_castano": (3, 1024, "", grid4(["tree_chestnut_1", "tree_chestnut_2", "tree_chestnut_3",
                                            "tree_willow_1"], 3)),
    "arboles_rio": (3, 1024, "", grid4(["tree_poplar_1", "tree_poplar_2", "tree_poplar_3", "tree_willow_2"], 3)),
    "arboles_pino": (3, 1024, "", grid4(["tree_pine_1", "tree_pine_2", "tree_fir_1", "tree_fir_2"], 3)),
    "frutales": (4, 1024, "", grid4(["tree_apple_1", "tree_apple_2", "tree_pear_1", "tree_cherry_1"], 4)),
    "arbustos": (6, 1024, "", grid4(["bush_1", "bush_2", "bush_3", "hedge_1"], 6)),
    "deco_huerto": (6, 1024, "", grid4(["planter", "flower_pots", "beehive", "trough"], 6)),
    "deco_campo": (5, 1024, "", grid4(["wattle_fence", "fence_gate", "hay_cart", "scarecrow"], 5)),
    "deco_patio": (5, 1024, "", grid4(["barrel_stack", "crate_stack", "woodpile", "haystack"], 5)),
    "deco_plaza": (4, 1024, "", grid4(["stone_cross", "fountain", "well_roof", "pillory_post"], 4)),
    "deco_vida": (5, 1024, "", grid4(["clothesline", "market_banner", "hens", "dog"], 5)),
    "deco_carteles": (5, 1024, "", grid4(["sign_forge", "sign_tailor", "sign_carpenter", "sign_inn"], 5)),
    "puestos_1": (4, 1024, "", grid4(["stall_food", "stall_goods", "stall_materials", "stall_clothier"], 4)),
    "puestos_2": (4, 1024, "", grid4(["stall_resources", "stall_apothecary", "stall_livestock", "stall_spare"], 4)),
    "catedral": (4, 2048, "2K", [("cathedral", 0, 0, 512, 512)]),
    "iglesia": (2, 1024, "", [("church", 0, 0, 512, 512)]),
    "aduana": (3, 1024, "", [("customs", 0, 0, 341, 341)]),
    "almacen": (3, 1024, "", [("warehouse", 0, 0, 341, 341)]),
    "lonja": (3, 1024, "", [("exchange", 0, 0, 341, 341)]),
    "torres": (3, 1024, "", [("wall_tower", 0, 0, 170, 341), ("gate_tower", 170, 0, 171, 341)]),
    "muralla_grua": (4, 1024, "", [("crane", 0, 0, 128, 256), ("wall_1", 128, 0, 128, 128),
                                   ("wall_2", 128, 128, 128, 128)]),
}
POS4 = ["top-left", "top-right", "bottom-left", "bottom-right"]


# --- Maquetas ------------------------------------------------------------------------------------------------
def foot_iso(cw, ch, c, r, margin=4):
    """Iso con la huella c×r abajo y centrada en una celda de cw×ch px de arte."""
    oy = ch - margin - (c + r) * 16
    return escala.Iso(round(cw / 2 - (c - r) * 16), oy)


def _ellipse(d, box, fill):
    d.ellipse(box, fill=fill, outline=OUT_C)


def draw_shape(pid, cw, ch):
    """La silueta gris de la pieza en una celda de cw×ch px de arte (base abajo y centrada)."""
    pc = PIECES[pid]
    img = Image.new("RGBA", (cw, ch), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    s = pc["shape"]
    bx, by = cw // 2, ch - 6
    kind = s[0]
    if kind in ("crown", "willow", "column", "umbrella"):
        _, w, hc, tw, th = s
        top = by - th - hc + 8
        d.rectangle([bx - tw // 2, by - th - 6, bx + tw // 2, by], fill=GREY_D, outline=OUT_C)
        if kind == "umbrella":
            _ellipse(d, [bx - w // 2, top, bx + w // 2, top + hc], GREY_M)
        elif kind == "willow":
            d.rounded_rectangle([bx - w // 2, top, bx + w // 2, by - 2], radius=w // 2, fill=GREY_M, outline=OUT_C)
        else:
            _ellipse(d, [bx - w // 2, top, bx + w // 2, top + hc], GREY_M)
        _ellipse(d, [bx - w // 2 + w // 8, top + hc // 10, bx, top + hc // 2], GREY_L)
    elif kind == "cone":
        _, w, hc, tw, th = s
        d.rectangle([bx - tw // 2, by - th - 4, bx + tw // 2, by], fill=GREY_D, outline=OUT_C)
        d.polygon([(bx, by - th - hc), (bx + w // 2, by - th), (bx - w // 2, by - th)], fill=GREY_M, outline=OUT_C)
    elif kind in ("bush", "dome"):
        _, w, h = s
        _ellipse(d, [bx - w // 2, by - h, bx + w // 2, by], GREY_M)
    elif kind == "hedge":
        iso = foot_iso(cw, ch, 1, 1)
        escala.box(d, iso, 0.0, 0.35, 1.0, 0.3, 20, (GREY_L, GREY_D))
    elif kind == "box":
        _, a, b, h = s
        iso = foot_iso(cw, ch, 1, 1)
        escala.box(d, iso, 0.5 - a / 2, 0.5 - b / 2, a, b, h, (GREY_L, GREY_D))
    elif kind == "fence":
        iso = foot_iso(cw, ch, 1, 1)
        escala.box(d, iso, 0.0, 0.45, 1.0, 0.1, 26, (GREY_L, GREY_D))
    elif kind == "line":
        iso = foot_iso(cw, ch, 1, 1)
        for u in (0.0, 0.9):
            escala.box(d, iso, u, 0.45, 0.1, 0.1, 44, (GREY_L, GREY_D))
        d.line([iso.p(0.05, 0.5, 40), iso.p(0.95, 0.5, 40)], fill=OUT_C)
    elif kind in ("post", "sign"):
        w, h = (s[1], s[2]) if kind == "post" else (28, 52)
        d.rectangle([bx - 2, by - h, bx + 2, by], fill=GREY_D, outline=OUT_C)
        if kind == "sign":
            d.rectangle([bx, by - h + 2, bx + 18, by - h + 6], fill=GREY_D, outline=OUT_C)
            d.rectangle([bx + 4, by - h + 8, bx + 22, by - h + 26], fill=GREY_L, outline=OUT_C)
        else:
            d.rectangle([bx - w // 2, by - h, bx + w // 2, by - h // 2], fill=GREY_M, outline=OUT_C)
    elif kind == "pots":
        for dx, r in ((-8, 6), (3, 5), (10, 4)):
            d.rectangle([bx + dx - r, by - 2 * r - 2, bx + dx + r, by], fill=GREY_M, outline=OUT_C)
    elif kind == "blobs":
        n = s[1]
        for k in range(n):
            x = bx + (k - (n - 1) / 2) * 11
            _ellipse(d, [x - 6, by - 10 - (k % 2) * 2, x + 6, by - (k % 2) * 2], GREY_M)
    elif kind == "fountain":
        iso = foot_iso(cw, ch, 1.2, 1.2)
        escala.box(d, iso, 0.0, 0.0, 1.2, 1.2, 14, (GREY_L, GREY_D), top=(120, 140, 170))
        escala.box(d, iso, 0.5, 0.5, 0.2, 0.2, 44, (GREY_L, GREY_D))
    elif kind == "stall":
        pen = s[1]
        iso = foot_iso(cw, ch, 1.4, 1.0)
        if pen:
            for (u, v, a, b) in ((0, 0, 1.4, 0.06), (0, 0, 0.06, 1.0), (1.34, 0, 0.06, 1.0), (0, 0.94, 1.4, 0.06)):
                escala.box(d, iso, u, v, a, b, 16, (GREY_L, GREY_D))
            escala.box(d, iso, 1.15, 0.1, 0.08, 0.08, 64, (GREY_L, GREY_D))
        else:
            escala.box(d, iso, 0.1, 0.1, 1.2, 0.4, 24, (GREY_L, GREY_D))
            escala.box(d, iso, 0.15, 0.55, 1.1, 0.35, 26, (GREY_L, GREY_D))
            for (u, v) in ((0.05, 0.05), (1.27, 0.05), (0.05, 0.87), (1.27, 0.87)):
                escala.box(d, iso, u, v, 0.08, 0.08, 66 if v < 0.5 else 60, (GREY_L, GREY_D))
            P_ = iso.p
            escala.poly(d, [P_(0.0, 0.0, 74), P_(1.4, 0.0, 74), P_(1.4, 1.05, 58), P_(0.0, 1.05, 58)], GREY_M)
    elif kind in ("cathedral", "church", "hall", "tower", "crane", "wall"):
        c, r = pc["foot"]
        iso = foot_iso(cw, ch, c, r)
        W, D = (GREY_L, GREY_D), (GREY_L, GREY_D)
        R = ((170, 170, 170), (125, 125, 125))
        if kind == "cathedral":
            # nave along u (10), west front with two towers on the +u end (seen front-right); back to front
            escala.box(d, iso, 7.8, 0.0, 2.2, 2.2, 300, W, top=False)
            escala.pyramid(d, iso, 7.8, 0.0, 2.2, 2.2, 300, 96, R)
            escala.box(d, iso, 0, 0, 8, 0.8, 90, W, top=False)
            escala.box(d, iso, 0, 0.8, 8, 4.4, 150, W, top=False)
            escala.gable(d, iso, 0, 0.8, 8, 4.4, 150, 70, "u", R, W)
            escala.box(d, iso, 3.5, 0.0, 1.6, 6.0, 150, W, top=False)
            escala.gable(d, iso, 3.5, 0.0, 1.6, 6.0, 150, 60, "v", R, W)
            escala.box(d, iso, 0, 5.2, 3.5, 0.8, 90, W, top=False)
            escala.box(d, iso, 5.1, 5.2, 2.7, 0.8, 90, W, top=False)
            for k in (1, 2, 6):
                escala.face_v(d, iso, k - 0.2, k + 0.3, 6.0, 20, 76, (110, 110, 120))
            escala.box(d, iso, 8.6, 2.2, 1.4, 1.6, 170, W, top=False)
            escala.gable(d, iso, 8.6, 2.2, 1.4, 1.6, 170, 40, "v", R, W)
            escala.face_u(d, iso, 10.0, 2.5, 3.5, 0, 70, (90, 90, 90))
            escala.face_u(d, iso, 10.0, 2.6, 3.4, 100, 150, (110, 110, 120))
            escala.box(d, iso, 7.8, 3.8, 2.2, 2.2, 300, W, top=False)
            escala.pyramid(d, iso, 7.8, 3.8, 2.2, 2.2, 300, 96, R)
        elif kind == "church":
            escala.box(d, iso, 0.6, 0.3, 3.0, 2.4, 110, W, top=False)
            escala.gable(d, iso, 0.6, 0.3, 3.0, 2.4, 110, 56, "u", R, W)
            escala.box(d, iso, 0.0, 0.8, 0.7, 1.4, 90, W, top=False)
            escala.pyramid(d, iso, 0.0, 0.8, 0.7, 1.4, 90, 30, R)
            escala.box(d, iso, 3.5, 0.6, 1.5, 1.8, 240, W, top=False)
            escala.pyramid(d, iso, 3.5, 0.6, 1.5, 1.8, 240, 80, R)
            escala.face_u(d, iso, 5.0, 1.2, 1.8, 0, 56, (90, 90, 90))
            for k in range(1, 3):
                escala.face_v(d, iso, 0.6 + k, 0.9 + k, 2.7, 56, 90, (110, 110, 120))
        elif kind == "hall":
            floors, roof = s[1], s[2]
            h = 64 + 48 * (floors - 1) if floors > 1 else 110
            escala.box(d, iso, 0.1, 0.1, c - 0.2, r - 0.2, h, W, top=roof != "flat")
            if roof == "hip":
                escala.pyramid(d, iso, 0.1, 0.1, c - 0.2, r - 0.2, h, 60, R)
            elif roof == "gable":
                escala.gable(d, iso, 0.1, 0.1, c - 0.2, r - 0.2, h, 70, "v", R, W)
            else:
                escala.merlons(d, iso, 0.1, 0.1, c - 0.2, r - 0.2, h, W)
            for k in range(int(c) - 1):
                escala.face_v(d, iso, 0.5 + k, 0.9 + k, r - 0.1, 0, 52, (100, 100, 100))
        elif kind == "tower":
            gate = s[1]
            h = 230
            escala.box(d, iso, 0.1, 0.1, 1.8, 1.8, h, W, top=not gate)
            if gate:
                escala.pyramid(d, iso, 0.1, 0.1, 1.8, 1.8, h, 70, R)
                escala.face_v(d, iso, 0.6, 1.4, 1.9, 0, 80, (90, 90, 90))
            else:
                escala.merlons(d, iso, 0.1, 0.1, 1.8, 1.8, h, W)
        elif kind == "crane":
            escala.box(d, iso, 0.2, 0.2, 0.6, 0.6, 140, W, top=False)
            escala.pyramid(d, iso, 0.2, 0.2, 0.6, 0.6, 140, 20, R)
            d.line([iso.p(0.5, 0.5, 130), iso.p(1.6, 0.5, 170)], fill=OUT_C, width=3)
        elif kind == "wall":
            escala.box(d, iso, 0.0, 0.0, 1.0, 1.0, 56, W)
            escala.merlons(d, iso, 0.0, 0.0, 1.0, 1.0, 56, W)
    return img


def target_size(pid):
    pc = PIECES[pid]
    if pc["size"]:
        return pc["size"]
    c, r = pc["foot"]
    return ((c + r) * 32, None)


def maquette(sheet):
    block, side, _, cells = SHEETS[sheet]
    n = side // block
    canvas = Image.new("RGBA", (n, n), (255, 255, 255, 255))
    for pid, x, y, w, h in cells:
        canvas.alpha_composite(draw_shape(pid, w, h), (x, y))
    big = canvas.resize((n * block, n * block), Image.NEAREST)
    return big.convert("RGB")


def style_sheet():
    """Sprites del juego a ×2 sobre blanco: dos casas, un puesto, pozo, carro, barril, farola y el personaje."""
    items = [("buildings/escala_b/house_b.png", 2), ("buildings/escala_b/house_c.png", 2),
             ("buildings/stall_food.png", 2), ("props/well.png", 2), ("props/cart.png", 2), ("props/barrel.png", 2),
             ("props/lantern.png", 2)]
    sheet = Image.new("RGBA", (1024, 640), (255, 255, 255, 255))
    x = 8
    for rel, k in items:
        im = Image.open(os.path.join(ART, rel)).convert("RGBA")
        im = im.crop(im.getchannel("A").getbbox())
        im = im.resize((im.width * k, im.height * k), Image.NEAREST)
        if x + im.width > 1024:
            break
        sheet.alpha_composite(im, (x, 620 - im.height))
        x += im.width + 10
    return sheet.convert("RGB")


def ref():
    os.makedirs(P, exist_ok=True)
    style_sheet().save(os.path.join(P, "estilo.png"))
    for s in SHEETS:
        maquette(s).save(os.path.join(P, f"maqueta_{s}.png"))
    print("refs en", P)


def prompt(sheet):
    block, side, _, cells = SHEETS[sheet]
    n = side // block
    if len(cells) == 4 and all(c[3] == cells[0][3] for c in cells):
        where = POS4
    elif len(cells) == 1:
        where = ["the model"]
    elif sheet == "torres":
        where = ["left", "right"]
    else:
        where = ["left half", "top-right", "bottom-right"]
    what = " ".join(f"{pos.capitalize()}: {PIECES[pid]['desc']}." for pos, (pid, *_r) in zip(where, cells))
    return ("Image 1 is a grey block model drawn at " + str(block) + "x scale (every art pixel is a " + str(block) +
            "x" + str(block) + " block; the art is " + str(n) + "x" + str(n) + " pixels). Image 2 shows sprites of our "
            "medieval town game (houses, a market stall, a well, a cart, a barrel, a lantern) at 2x. Repaint every "
            "grey shape of image 1 as a finished object in exactly the pixel art style of image 2: 16-bit SNES pixel "
            "art, the same isometric 2:1 projection and camera, the same dark 1-pixel outline, the same warm earthy "
            "palette (browns, tans, terracotta, forest green, stone grey, gold, deep red, sky blue) and shading with "
            "light from the top-left. Keep each object exactly where its grey shape is, with the same size, height "
            "and silhouette, on the same " + str(block) + "x" + str(block) + " pixel grid. " + what + " Plain flat "
            "white background, no ground tile, no grass under the objects, no base plate, no cast shadow on the "
            "background, no people, no text, letters or labels, no grid lines. The grey model is only a guide: nothing of "
            "it may stay visible (no grey ovals, halos or blocks around the objects).")


def gen(names):
    for s in names:
        raw = os.path.join(P, "crudo", s + ".png")
        if os.path.exists(raw):
            continue
        block, side, res, _ = SHEETS[s]
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "rediseno",
               "--aspect", "1:1", "--name", s, "--ref", os.path.join(P, f"maqueta_{s}.png"), "--ref",
               os.path.join(P, "estilo.png"), "--prompt", prompt(s)]
        if res:
            cmd += ["--resolution", res]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


# --- Proceso ---------------------------------------------------------------------------------------------------
def shadow(im, w_frac=0.6):
    """Sombra al pie: elipse 2:1 oscura y translúcida, desplazada abajo a la derecha (luz de arriba a la izquierda),
    debajo del sprite. Devuelve un lienzo algo mayor con la base del objeto en la misma fila de abajo."""
    w, h = im.size
    sw = max(8, int(w * w_frac))
    sh = max(4, sw // 2)
    pad_r, pad_b = sw // 5, sh // 4
    out = Image.new("RGBA", (w + pad_r, h + pad_b), (0, 0, 0, 0))
    sh_img = Image.new("RGBA", out.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh_img)
    cx = w // 2 + pad_r // 2
    cy = h - 1
    d.ellipse([cx - sw // 2, cy - sh // 2, cx + sw // 2, cy + sh // 2], fill=(20, 26, 12, 72))
    out.alpha_composite(sh_img)
    out.alpha_composite(im, (0, 0))
    return out


def degrey(im):
    """Quita lo que queda de la maqueta gris (gris neutro claro) en árboles y arbustos, que no tienen gris."""
    im = im.copy()
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and max(r, g, b) - min(r, g, b) < 14 and 120 < r < 235:
                px[x, y] = (0, 0, 0, 0)
    return fp.key_background(im, "white", 28)


def retouch(pid, im):
    """Arreglos locales de lo que el modelo hizo mal: el sauce trae una franja de agua (fuera el azul claro) y los
    pinos salen turquesa con el tronco naranja (copa a verde oscuro, tronco a pardo rojizo)."""
    import colorsys
    if not (pid == "tree_willow_1" or pid.startswith(("tree_pine", "tree_fir"))):
        return im
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if not a:
                continue
            if pid == "tree_willow_1":
                if b > g + 15 and b > r + 30:
                    px[x, y] = (0, 0, 0, 0)
                continue
            h, sat, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if 0.40 < h < 0.62 and sat > 0.12:  # turquesa / azul -> verde pino
                h, sat, v = 0.33 + (h - 0.40) * 0.15, min(1.0, sat * 0.9), v * 0.85
            elif 0.03 < h < 0.11 and sat > 0.45:  # naranja -> pardo rojizo
                h, sat, v = h * 0.8, sat * 0.6, v * 0.72
            else:
                continue
            rr, gg, bb = colorsys.hsv_to_rgb(h, sat, v)
            px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), a)
    return im


def cell_image(sheet, cell):
    block, side, _, cells = SHEETS[sheet]
    pid, x, y, w, h = cell
    raw = Image.open(os.path.join(P, "crudo", sheet + ".png")).convert("RGBA")
    if raw.size != (side, side):
        raw = raw.resize((side, side), Image.LANCZOS)
    return raw.crop((x * block, y * block, (x + w) * block, (y + h) * block))


def pixelate(sheet, cell):
    block = SHEETS[sheet][0]
    pid = cell[0]
    pc = PIECES[pid]
    keyed = no_grid_lines(fal_fachadas.holes(fp.key_background(cell_image(sheet, cell), "white", 28)))
    if PIECES[pid]["out"] == "props" and (pid.startswith(("tree_", "bush_", "hedge"))):
        keyed = degrey(keyed)
    nat = local_pixel(keyed, block, colors=24 if pc["size"] else 32)
    bb = nat.getchannel("A").getbbox()
    if not bb:
        print("  vacío:", pid)
        return None
    cut = nat.crop(bb)
    tw, th = target_size(pid)
    fit = pc.get("fit", "w")
    if fit == "h" and th:
        ratio = cut.height / th
    elif fit == "box" and th:
        ratio = max(cut.width / tw, cut.height / th)
    else:
        ratio = cut.width / tw
    if abs(ratio - 1) > 0.08:
        nat = local_pixel(keyed, block, colors=24 if pc["size"] else 32, mult=ratio)
        cut = nat.crop(nat.getchannel("A").getbbox())
    cut = retouch(pid, cut)
    if pc.get("whole", True):
        cut = largest(cut)
    cut = fic.outline(cut)
    if pc.get("shadow"):
        cut = shadow(cut)
    return cut


def proc(names):
    for s in names:
        if not os.path.exists(os.path.join(P, "crudo", s + ".png")):
            print("falta", s)
            continue
        for cell in SHEETS[s][3]:
            pid = cell[0]
            if PIECES[pid]["out"] is None:
                continue
            im = pixelate(s, cell)
            if im is None:
                continue
            d = os.path.join(ART, PIECES[pid]["out"])
            os.makedirs(d, exist_ok=True)
            im.save(os.path.join(d, pid + ".png"))
            print(f"{PIECES[pid]['out']}/{pid}.png: {im.width}x{im.height}")


def scale_refs():
    """La casa de 2 plantas y el personaje (primer fotograma de idle_s) para medir al lado."""
    house = Image.open(os.path.join(ART, "buildings", "escala_b", "house_b.png")).convert("RGBA")
    house = house.crop(house.getchannel("A").getbbox())
    ch = Image.open(os.path.join(ART, "characters", "artisan_m", "idle_s.png")).convert("RGBA").crop((0, 0, 68, 68))
    ch = ch.crop(ch.getchannel("A").getbbox())
    return [("casa", house), ("persona", ch)]


def hoja(names, out=None, bg=(78, 104, 52, 255), width=1000):
    """Hoja de revisión a ×2: la casa de 2 plantas y el personaje y luego cada pieza, a su tamaño de juego."""
    ids = [c[0] for s in names for c in SHEETS[s][3]]
    imgs = []
    for pid in ids:
        p = os.path.join(ART, PIECES[pid]["out"] or "-", pid + ".png")
        if os.path.exists(p):
            imgs.append((pid, Image.open(p).convert("RGBA")))
    refs = scale_refs()
    rows, row, x, rh = [], [], 0, 0
    for pid, im in imgs:
        if x + im.width > width - 20 and row:
            rows.append((row, rh))
            row, x, rh = [], 0, 0
        if not row:
            for rid, rim in refs[1:]:
                row.append((rid, rim, x))
                x += rim.width + 10
                rh = max(rh, rim.height)
        row.append((pid, im, x))
        x += im.width + 10
        rh = max(rh, im.height)
    if row:
        rows.append((row, rh))
    house = refs[0][1]
    H = sum(rh + 16 for _, rh in rows) + house.height + 40
    sheet = Image.new("RGBA", (width, H), bg)
    d = ImageDraw.Draw(sheet)
    sheet.alpha_composite(house, (10, 10))
    sheet.alpha_composite(refs[1][1], (20 + house.width, 10 + house.height - refs[1][1].height))
    d.text((24 + house.width + refs[1][1].width, 10 + house.height - 12), "casa 2 plantas y personaje 48 px",
           fill=(240, 230, 200))
    y = house.height + 30
    for row, rh in rows:
        for pid, im, x in row:
            sheet.alpha_composite(im, (10 + x, y + rh - im.height))
        y += rh + 16
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    out = out or os.path.join(P, "hoja.png")
    sheet.save(out)
    print(out)


# --- Espaldas de las casas de lote (assets/art/buildings/block/house_<c>x<r>_<k>.png) ------------------------------
BLOCK = os.path.join(ART, "buildings", "block")


def back_ref(name):
    """La casa del juego ×4, centrada abajo en un lienzo blanco de 1024."""
    im = Image.open(os.path.join(BLOCK, name + ".png")).convert("RGBA")
    big = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
    canvas = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
    canvas.alpha_composite(big, ((1024 - big.width) // 2, 1024 - big.height - 8))
    out = os.path.join(P, "espaldas", "ref_" + name + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.convert("RGB").save(out)
    return out


BACK_PROMPT = ("Image 1 is a house sprite of our medieval town game, enlarged 4x (every art pixel is a 4x4 block). "
               "Repaint the SAME house as its back side: exactly the same silhouette, footprint, wall heights, roof, "
               "chimney, timber frame, colours, isometric 2:1 projection, dark 1-pixel outline, light from the top-left, "
               "position in the image and 4x4 pixel grid. Only the details of the two visible walls change: there is NO "
               "front door any more (where the door was, a plain wall with a small shuttered window), and the walls "
               "show the back of a house: small windows with shutters, a narrow low back door at most, a rain barrel or "
               "a little woodpile against the wall is fine. Plain flat white background, no ground, no grass, no text, "
               "no people, no shadow on the background.")


def gen_backs(names):
    for n in names:
        if os.path.exists(os.path.join(P, "crudo", n + "_back.png")):
            continue
        cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "rediseno",
               "--aspect", "1:1", "--name", n + "_back", "--ref", back_ref(n), "--prompt", BACK_PROMPT]
        if subprocess.run(cmd, cwd=ROOT).returncode:
            sys.exit(1)


def proc_backs(names):
    for n in names:
        raw = os.path.join(P, "crudo", n + "_back.png")
        if not os.path.exists(raw):
            print("falta", raw)
            continue
        front = Image.open(os.path.join(BLOCK, n + ".png")).convert("RGBA")
        keyed = fal_fachadas.holes(fp.key_background(Image.open(raw).convert("RGBA").resize((1024, 1024)), "white", 28))
        nat = local_pixel(keyed, 4, colors=32)
        cut = nat.crop(nat.getchannel("A").getbbox())
        ratio = cut.width / front.width
        if abs(ratio - 1) > 0.04:
            nat = local_pixel(keyed, 4, colors=32, mult=ratio)
            cut = nat.crop(nat.getchannel("A").getbbox())
        cut = fic.outline(largest(cut))
        if cut.size != front.size:  # the same box as the front: base on the same bottom row, centred
            box = Image.new("RGBA", front.size, (0, 0, 0, 0))
            box.alpha_composite(cut, ((front.width - cut.width) // 2, front.height - cut.height)) \
                if cut.width <= front.width and cut.height <= front.height else None
            if cut.width > front.width or cut.height > front.height:
                cut = cut.resize(front.size, Image.NEAREST)
            else:
                cut = box
        out = os.path.join(BLOCK, n + "_back.png")
        cut.save(out)
        print(f"{os.path.relpath(out, ROOT)}: {cut.width}x{cut.height} (frente {front.width}x{front.height})")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    names = sys.argv[2:] or list(SHEETS)
    {"ref": lambda n: ref(), "gen": gen, "proc": proc, "hoja": hoja, "gen_espaldas": gen_backs,
     "proc_espaldas": proc_backs}.get(cmd, lambda n: print(__doc__))(names)
