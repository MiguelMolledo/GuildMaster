#!/usr/bin/env python3
"""Biblioteca de props de interior (docs/gdd/04g_interiores.md §4.6.5.1): piezas sueltas sacadas de las referencias
de assets/art/interiors/_referencias/ con fal (nano-banana-2/edit), en rejillas de varias piezas por llamada:

  xs  4×4 celdas de 256 px: atrezo pequeño (~32 px), image2pixel a bloques de 4   (16 piezas / 0,08 USD)
  s   3×3 celdas de 341 px: muebles y piezas de una casilla (~64 px), bloques de 5 (9 piezas / 0,08 USD)
  l   2×2 celdas de 512 px: piezas grandes de 2×1 casillas (~128 px), bloques de 4  (4 piezas / 0,08 USD)
  w   3×3 celdas de 341 px: piezas de pared (tapices, escudos, ristras), bloques de 5

Cada rejilla lleva dos referencias: el render de la sala de donde salen sus piezas y la hoja de las piezas buenas de
la forja ×4 (escala, contorno y proyección). El pixelado va con una paleta fija de interiores (PALETTE, sacada de
los fondos y las referencias) para que todas casen entre sí y con los fondos. Lo exacto (paredes interiores, zócalos,
puertas, suelos, escalón) se dibuja con Pillow en tools/art/props_estructura.py.

Salida: assets/art/props/interior/<id>.png (recortada a su caja) + la ficha de cada pieza en assets/inventario.json
(campo "prop": categoría, huella, ancla, altura, si se pisa, pared, encima, oficios, estilo). El catálogo
data/props/interior.json lo exporta tools/interiors/props_catalog.py.

Uso:
  python3 tools/art/fal_props.py list                      # las rejillas y sus piezas
  python3 tools/art/fal_props.py gen [--only g1,g2]        # genera las rejillas que falten (gasto en gasto.json)
  python3 tools/art/fal_props.py proc [--only g1,g2]       # recorta, pixela y escribe piezas + inventario
  python3 tools/art/fal_props.py hoja [--only g1,g2] [--out p.png]   # hoja de contacto
"""
import argparse
import datetime
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault("FAL_TANDA", "h16")
import fal_piloto as fpi  # noqa: E402
import fal_rutas as fr_  # noqa: E402

fpi.TANDA = "interiores"
ROOT = fr_.ROOT
import fal_client  # noqa: E402

RAW = fr_.produccion("props_interior")
REFS = os.path.join(ROOT, "assets", "art", "interiors", "_referencias")
OUT = os.path.join(ROOT, "assets", "art", "props", "interior")
INV = os.path.join(ROOT, "assets", "inventario.json")
ENDPOINT, UNIT = "fal-ai/nano-banana-2/edit", 0.08

GRIDS = {  # kind -> (cols, rows, image2pixel block, art grid of a cell)
    "xs": (4, 4, 4, 64),
    "s": (3, 3, 5, 68),
    "l": (2, 2, 4, 128),
    "w": (3, 3, 5, 68),
}
LIGHTS = {"candle", "candlestick", "lantern_small", "candle_stand", "standing_lantern", "candelabra_tall", "fireplace",
          "kitchen_hearth", "hall_firepit", "hall_brazier"}  # dan luz: categoría «light» (el montador les pone su halo)
CATEGORIES = ["structure", "furniture", "trade", "container", "light", "small", "textile"]
STYLES = ["poor", "common", "rich"]

# id, rejilla, categoría, huella, oficios/salas, estilo, banderas, descripción
# banderas: top = puede ir encima de una mesa o un mostrador · wall = contra la pared (o colgada, en las w) ·
#           walk = se pisa (alfombra, virutas) · flat = plana en el suelo
P = []


def add(grid, ref, cat, items, tags, style="common"):
    for it in items:
        pid, fp, flags, desc = it
        P.append({"id": pid, "grid": grid, "ref": ref, "category": cat, "footprint": fp, "tags": tags,
                  "style": style, "flags": flags, "desc": desc})


# --- atrezo pequeño (xs) ---------------------------------------------------------------------------------------
add("xs", "forge_b", "small", [
    ("ingot_pile", "1x1", "top", "a small pile of three iron ingots"),
    ("smith_hammer", "1x1", "top", "a blacksmith's hammer lying down"),
    ("tongs", "1x1", "top", "a pair of iron smithing tongs lying down"),
    ("horseshoes", "1x1", "top", "three iron horseshoes in a little heap"),
    ("nail_box", "1x1", "top", "a small open wooden box of iron nails"),
    ("sword_blank", "1x1", "top", "an unfinished sword blade lying down"),
    ("balance_scale", "1x1", "top", "a small brass merchant's balance scale"),
    ("ledger_book", "1x1", "top", "a closed leather ledger book"),
    ("coin_pile", "1x1", "top", "a small pile of gold and silver coins"),
    ("coin_purse", "1x1", "top", "a leather coin purse tied with a string"),
    ("dagger_cloth", "1x1", "top", "a dagger lying on a folded red cloth"),
    ("helmet_small", "1x1", "top", "an iron helmet standing on its own"),
    ("water_pail", "1x1", "", "a small wooden water pail with an iron band"),
    ("charcoal_basket", "1x1", "", "a small wicker basket of charcoal"),
    ("file_rasp", "1x1", "top", "a metal file and a whetstone"),
    ("chain_coil", "1x1", "top", "a coil of iron chain"),
], ["forge", "armory"])
add("xs", "house_b", "small", [
    ("jug", "1x1", "top", "a clay water jug"),
    ("mugs", "1x1", "top", "two wooden mugs"),
    ("plate_bread", "1x1", "top", "a wooden plate with bread and cheese"),
    ("bowl_stew", "1x1", "top", "a clay bowl of hot stew with a spoon"),
    ("cheese_wheel", "1x1", "top", "a wheel of yellow cheese with a slice cut"),
    ("bread_loaves", "1x1", "top", "three round bread loaves"),
    ("apple_basket", "1x1", "top", "a small basket of red apples"),
    ("candle", "1x1", "top", "a lit tallow candle on a small iron holder"),
    ("cooking_pot", "1x1", "top", "a small iron cooking pot with a lid"),
    ("tankards", "1x1", "top", "two pewter tankards of ale with foam"),
    ("wine_bottle", "1x1", "top", "a green glass wine bottle and a cup"),
    ("plate_roast", "1x1", "top", "a plate with a roast chicken leg and vegetables"),
    ("lute", "1x1", "top", "a wooden lute lying down"),
    ("dice_cup", "1x1", "top", "a leather dice cup and two bone dice"),
    ("flower_vase", "1x1", "top", "a clay vase with wild flowers"),
    ("key_ring", "1x1", "top", "an iron ring with three big keys"),
], ["house", "tavern"])
add("xs", "tailor_shop_a", "small", [
    ("scissors_chalk", "1x1", "top", "a pair of tailor's shears and a piece of chalk"),
    ("cloth_roll_red", "1x1", "top", "a small roll of red cloth"),
    ("cloth_roll_blue", "1x1", "top", "a small roll of blue cloth"),
    ("thread_spools", "1x1", "top", "three wooden spools of coloured thread"),
    ("pincushion", "1x1", "top", "a red pincushion with needles"),
    ("open_book", "1x1", "top", "an open book with writing (no readable letters)"),
    ("scroll_pile", "1x1", "top", "a pile of rolled parchment scrolls"),
    ("quill_inkwell", "1x1", "top", "a quill pen in an inkwell"),
    ("wax_seal", "1x1", "top", "a sealed letter with a red wax seal"),
    ("candlestick", "1x1", "top", "a tall brass candlestick with a lit candle"),
    ("chisel_set", "1x1", "top", "a set of woodworking chisels in a cloth roll"),
    ("wood_mallet", "1x1", "top", "a wooden carpenter's mallet"),
    ("stone_chisels", "1x1", "top", "a stonemason's iron chisels and a small hammer"),
    ("herb_bundle", "1x1", "top", "a tied bundle of dried herbs"),
    ("lantern_small", "1x1", "top", "a small lit iron lantern"),
    ("offering_bowl", "1x1", "top", "a small brass offering bowl"),
], ["tailor_shop", "town_hall", "court", "church", "carpentry", "masonry"])
# --- piezas de una casilla (s) ---------------------------------------------------------------------------------
add("s", "forge_b", "trade", [
    ("bellows", "1x1", "", "a big leather forge bellows on a wooden stand"),
    ("quench_tub", "1x1", "", "a wooden quenching tub full of water with steam rising"),
    ("water_barrel", "1x1", "", "an open water barrel with a ladle"),
    ("tool_rack", "1x1", "wall", "a standing wooden rack with hanging tongs and hammers"),
    ("ingot_stack", "1x1", "", "a neat stack of iron ingots on a low wooden pallet"),
    ("sword_rack", "1x1", "wall", "a wooden rack holding four upright swords (a shop display)"),
    ("horseshoe_crate", "1x1", "", "an open wooden crate full of horseshoes"),
    ("coal_sack", "1x1", "", "an open sack of charcoal"),
    ("armor_stand_forge", "1x1", "", "a wooden stand with a half-finished breastplate"),
], ["forge"])
add("s", "armory_a", "furniture", [
    ("weapon_display", "1x1", "wall", "a wooden display rack with six slots for weapons, two swords on it"),
    ("shield_stand", "1x1", "", "a wooden stand with two round painted shields"),
    ("armor_mannequin", "1x1", "", "a wooden mannequin wearing a full suit of plate armour"),
    ("helmet_shelf", "1x1", "wall", "a small wooden shelf with three iron helmets"),
    ("mail_chest", "1x1", "", "an open wooden chest with chainmail spilling out"),
    ("banner_stand", "1x1", "", "a pole with a red heraldic banner on a wooden foot"),
    ("spear_rack", "1x1", "wall", "an upright rack of spears and halberds"),
    ("candle_stand", "1x1", "", "a tall iron floor candle stand with three lit candles"),
    ("strongbox", "1x1", "", "an iron-bound strongbox with a big padlock"),
], ["armory", "forge", "shop"], "rich")
add("s", "house_b", "furniture", [
    ("chest", "1x1", "wall", "a wooden chest with iron bands"),
    ("wardrobe", "1x1", "wall", "a tall plain wooden wardrobe"),
    ("cradle", "1x1", "", "a wooden baby cradle on rockers with a blanket"),
    ("stool", "1x1", "", "a three-legged wooden stool"),
    ("chair", "1x1", "", "a simple wooden chair with a straight back"),
    ("kitchen_hearth", "1x1", "wall", "a stone cooking hearth with fire and an iron cauldron hanging over it"),
    ("crockery_shelf", "1x1", "wall", "a wooden shelf with clay plates, bowls and jugs"),
    ("washtub", "1x1", "", "a round wooden washtub with water and a scrubbing board"),
    ("pantry_shelf", "1x1", "wall", "a pantry shelf with sacks, jars, onions and a ham"),
], ["house", "home"], "poor")
add("s", "tavern_a", "furniture", [
    ("cask_tap", "1x1", "", "a big wine cask lying on a wooden cradle with a tap"),
    ("bar_stool", "1x1", "", "a tall wooden bar stool"),
    ("tavern_chair", "1x1", "", "a sturdy tavern chair"),
    ("fireplace", "1x1", "wall", "a stone fireplace with a crackling fire and a mantel"),
    ("keg_stack", "1x1", "", "three small kegs stacked in a pyramid"),
    ("round_table", "1x1", "", "a small round wooden table"),
    ("bench_short", "1x1", "", "a short wooden bench for two"),
    ("standing_lantern", "1x1", "", "a lantern hanging from a wooden post"),
    ("coat_rack", "1x1", "wall", "a wooden peg rack with a cloak and a hat"),
], ["tavern"])
add("s", "house_a", "container", [
    ("barrel", "1x1", "", "a closed wooden barrel standing up"),
    ("crate", "1x1", "", "a closed wooden crate"),
    ("crate_stack", "1x1", "", "two wooden crates stacked with a sack on top"),
    ("sack", "1x1", "", "a full grain sack tied at the top"),
    ("sack_pile", "1x1", "", "a pile of four grain sacks"),
    ("wicker_basket", "1x1", "", "a big wicker basket with a lid"),
    ("firewood_pile", "1x1", "wall", "a neat pile of split firewood"),
    ("big_jar", "1x1", "", "a big clay storage jar"),
    ("bucket", "1x1", "", "a wooden bucket with a rope handle"),
], ["all"])
add("s", "carpentry_b", "trade", [
    ("sawhorse", "1x1", "", "a wooden sawhorse with a plank on it"),
    ("plank_stack", "1x1", "", "a stack of sawn wooden planks"),
    ("log_pile", "1x1", "", "a pile of three logs"),
    ("half_chair", "1x1", "", "a half-built wooden chair without its back"),
    ("unfinished_barrel", "1x1", "", "an unfinished barrel with loose staves"),
    ("tool_pegboard", "1x1", "wall", "a standing pegboard with saws, planes and squares"),
    ("chopping_block", "1x1", "", "a chopping block with an axe stuck in it"),
    ("glue_pot", "1x1", "", "a small brazier warming a glue pot"),
    ("shavings_heap", "1x1", "walk", "a heap of curly wood shavings on the floor"),
], ["carpentry"])
add("s", "masonry_a", "trade", [
    ("stone_block", "1x1", "", "a rough grey stone block"),
    ("ashlar_stack", "1x1", "", "a stack of three dressed stone blocks"),
    ("small_crane", "1x1", "", "a small wooden hoisting crane with a rope and hook"),
    ("rubble_pile", "1x1", "walk", "a pile of stone rubble and chips"),
    ("template_rack", "1x1", "wall", "a rack of wooden templates and a big square"),
    ("statue_unfinished", "1x1", "", "a half-carved stone statue on a plinth"),
    ("column_drum", "1x1", "", "a carved stone column drum"),
    ("stone_trough", "1x1", "", "a stone water trough"),
    ("mason_toolbox", "1x1", "", "an open wooden toolbox with mallets and chisels"),
], ["masonry"])
add("s", "tailor_shop_b", "trade", [
    ("dress_form", "1x1", "", "a dress form mannequin with a half-sewn green gown"),
    ("spinning_wheel", "1x1", "", "a wooden spinning wheel with wool"),
    ("cloth_shelf", "1x1", "wall", "a shelf full of folded bolts of coloured cloth"),
    ("mirror_standing", "1x1", "", "a tall standing mirror in a wooden frame"),
    ("thread_basket", "1x1", "", "a basket of wool balls and thread"),
    ("fabric_stack", "1x1", "", "a stack of folded fabrics on a stool"),
    ("hat_stand", "1x1", "", "a wooden stand with two hats"),
    ("sewing_chair", "1x1", "", "a low chair with a cushion and a sewing basket"),
    ("fitting_screen", "1x1", "", "a folding screen with a red curtain (a fitting booth)"),
], ["tailor_shop"])
add("s", "town_hall_b", "furniture", [
    ("mayor_chair", "1x1", "", "a high-backed carved wooden chair with a red cushion"),
    ("archive_cabinet", "1x1", "wall", "a tall cabinet full of scrolls and ledgers"),
    ("lectern", "1x1", "", "a wooden lectern with an open book"),
    ("witness_stand", "1x1", "", "a small wooden witness box with a rail"),
    ("pulpit", "1x1", "", "a carved wooden pulpit"),
    ("baptismal_font", "1x1", "", "a stone baptismal font with water"),
    ("candelabra_tall", "1x1", "", "a tall iron candelabra with five lit candles"),
    ("town_banner", "1x1", "", "a tall banner of the town arms on a pole"),
    ("heraldic_stand", "1x1", "", "a wooden stand with a heraldic shield"),
], ["town_hall", "court", "church"], "rich")
# --- piezas grandes de 2×1 (l) ---------------------------------------------------------------------------------
add("l", "armory_a", "furniture", [
    ("shop_counter", "2x1", "", "a long wooden shop counter with a top board and panels at the front"),
    ("display_shelf", "2x1", "wall", "a long low wooden display shelf with three empty slots for wares"),
    ("bar_counter", "2x1", "", "a long tavern bar counter with a brass rail"),
    ("weapon_panoply", "2x1", "wall", "a long standing wooden panoply with crossed swords, axes and a shield"),
], ["forge", "armory", "shop", "tavern"])
add("l", "house_b", "furniture", [
    ("bed_single", "2x1", "wall", "a simple single bed with a straw mattress and a wool blanket"),
    ("bed_double", "2x1", "wall", "a double bed with a wooden headboard and a red blanket"),
    ("dining_table", "2x1", "", "a long rustic dining table"),
    ("kitchen_table", "2x1", "", "a long kitchen work table with a knife and vegetables"),
], ["house", "home", "inn"])
add("l", "tavern_b", "furniture", [
    ("tavern_table", "2x1", "", "a long tavern table with two candles"),
    ("tavern_bench", "2x1", "", "a long tavern bench"),
    ("minstrel_stage", "2x1", "", "a small low wooden stage with a stool and a drum"),
    ("staircase", "2x1", "", "a wooden staircase going up (seen in isometric, rising towards the back)"),
], ["tavern", "house", "forge"])
add("l", "carpentry_a", "trade", [
    ("carpenter_bench", "2x1", "", "a long carpenter's workbench with a vice and tools on it"),
    ("loom", "2x1", "", "a big wooden weaving loom with blue cloth"),
    ("cutting_table", "2x1", "", "a large tailor's cutting table with cloth, shears and chalk"),
    ("council_table", "2x1", "", "a long council table with parchments and a quill"),
], ["carpentry", "tailor_shop", "town_hall"])
add("l", "court_b", "furniture", [
    ("judge_bench", "2x1", "", "a raised wooden judge's bench with a carved front"),
    ("dock_rail", "2x1", "", "a wooden dock for the accused: a low railed enclosure"),
    ("pew", "2x1", "", "a long wooden church pew"),
    ("altar", "2x1", "", "a stone altar with a white cloth, two candles and a cross"),
], ["court", "church"], "rich")
add("l", "masonry_b", "trade", [
    ("stone_bench", "2x1", "", "a stone cutting bench with a block on it"),
    ("pit_hearth", "2x1", "", "a large blacksmith's forge hearth of stone with a hood and glowing coals"),
    ("market_shelf", "2x1", "wall", "a long shelf with sacks, jars and baskets for sale"),
    ("bunk_bed", "2x1", "wall", "a wooden bunk bed for apprentices"),
], ["masonry", "forge", "shop", "home"])
# --- piezas de pared (w): de frente sobre la pared del fondo derecha, en 2:1 --------------------------------------
add("w", "town_hall_a", "textile", [
    ("tapestry_red", "1x1", "wall", "a red woven tapestry with a gold border"),
    ("tapestry_green", "1x1", "wall", "a green tapestry with a hunting scene (no faces)"),
    ("shield_crest", "1x1", "wall", "a heraldic shield hanging on the wall"),
    ("banner_wall", "1x1", "wall", "a long blue banner hanging from a pole"),
    ("herbs_hanging", "1x1", "wall", "bunches of dried herbs hanging from a peg rail"),
    ("onion_string", "1x1", "wall", "strings of onions and garlic hanging"),
    ("tool_board_wall", "1x1", "wall", "a board of hanging hammers and tongs"),
    ("wall_shelf_jars", "1x1", "wall", "a small wall shelf with jars and a candle"),
    ("horseshoe_nails", "1x1", "wall", "three horseshoes nailed on the wall"),
], ["all"])


# Tamaño objetivo de cada pieza en el juego (px de arte; el personaje mide 48, ~27 px por metro más la base): la
# altura del sprite en las s, w y xs (en las xs, el lado mayor) y el ancho en las l (una huella de 2×1 mide 96).
TARGET = {
    "bellows": 30, "quench_tub": 26, "water_barrel": 30, "tool_rack": 44, "ingot_stack": 20, "sword_rack": 40,
    "horseshoe_crate": 24, "coal_sack": 26, "armor_stand_forge": 46, "weapon_display": 44, "shield_stand": 34,
    "armor_mannequin": 52, "helmet_shelf": 30, "mail_chest": 26, "banner_stand": 56, "spear_rack": 54,
    "candle_stand": 44, "strongbox": 24, "chest": 24, "wardrobe": 56, "cradle": 26, "stool": 16, "chair": 30,
    "kitchen_hearth": 50, "crockery_shelf": 48, "washtub": 24, "pantry_shelf": 50, "cask_tap": 32, "bar_stool": 26,
    "tavern_chair": 30, "fireplace": 56, "keg_stack": 30, "round_table": 22, "bench_short": 20,
    "standing_lantern": 54, "coat_rack": 50, "barrel": 30, "crate": 22, "crate_stack": 36, "sack": 22,
    "sack_pile": 26, "wicker_basket": 22, "firewood_pile": 26, "big_jar": 30, "bucket": 18, "sawhorse": 24,
    "plank_stack": 18, "log_pile": 22, "half_chair": 26, "unfinished_barrel": 30, "tool_pegboard": 46,
    "chopping_block": 26, "glue_pot": 24, "shavings_heap": 12, "stone_block": 26, "ashlar_stack": 36,
    "small_crane": 60, "rubble_pile": 14, "template_rack": 44, "statue_unfinished": 50, "column_drum": 30,
    "stone_trough": 20, "mason_toolbox": 22, "dress_form": 48, "spinning_wheel": 36, "cloth_shelf": 50,
    "mirror_standing": 50, "thread_basket": 20, "fabric_stack": 28, "hat_stand": 46, "sewing_chair": 30,
    "fitting_screen": 48, "mayor_chair": 46, "archive_cabinet": 58, "lectern": 36, "witness_stand": 34,
    "pulpit": 52, "baptismal_font": 30, "candelabra_tall": 54, "town_banner": 60, "heraldic_stand": 40,
    # l: ancho
    "shop_counter": 96, "display_shelf": 96, "bar_counter": 110, "weapon_panoply": 96, "bed_single": 88,
    "bed_double": 96, "dining_table": 90, "kitchen_table": 90, "tavern_table": 96, "tavern_bench": 90,
    "minstrel_stage": 100, "staircase": 96, "carpenter_bench": 96, "loom": 80, "cutting_table": 96,
    "council_table": 110, "judge_bench": 100, "dock_rail": 90, "pew": 96, "altar": 90, "stone_bench": 96,
    "pit_hearth": 100, "market_shelf": 96, "bunk_bed": 90,
    # w: alto
    "tapestry_red": 40, "tapestry_green": 40, "shield_crest": 22, "banner_wall": 40, "herbs_hanging": 20,
    "onion_string": 26, "tool_board_wall": 28, "wall_shelf_jars": 22, "horseshoe_nails": 12,
    # xs: lado mayor
    "coin_pile": 10, "ledger_book": 12, "open_book": 14, "wax_seal": 10, "tankards": 14, "mugs": 14, "candle": 14,
    "sword_blank": 22, "tongs": 18, "smith_hammer": 16, "file_rasp": 16, "chain_coil": 14, "key_ring": 12,
    "lute": 22, "dice_cup": 12, "pincushion": 12, "thread_spools": 14, "quill_inkwell": 14, "scroll_pile": 16,
}
DEFAULT_TARGET = {"xs": 16, "s": 40, "l": 96, "w": 30}


def target(p):
    return TARGET.get(p["id"], DEFAULT_TARGET[p["grid"]])
# --- guarida del Pícaro y bodega (04g O-I1: sótano; de momento solo piezas y plantilla) -------------------------
add("s", "court_b", "furniture", [
    ("trapdoor", "1x1", "walk", "a closed wooden trapdoor set in the floor with an iron ring, lying flat"),
    ("trapdoor_open", "1x1", "walk", "an open wooden trapdoor in the floor showing a dark hole and the top of a ladder"),
    ("ladder", "1x1", "wall", "a wooden ladder leaning against a wall"),
    ("contraband_pile", "1x1", "", "a pile of crates and sacks half covered with a tarp, smuggled goods"),
    ("fence_table", "1x1", "", "a small table with a scale, coins and stolen jewels (a fence's table)"),
    ("dice_table", "1x1", "", "a small square gaming table with dice, a dice cup and coins"),
    ("stolen_goods", "1x1", "", "a heap of stolen things: candlesticks, a silver plate and a small chest"),
    ("wine_rack", "1x1", "wall", "a wooden wine rack full of dusty bottles"),
    ("chain_post", "1x1", "", "a wooden post with iron chains and shackles"),
], ["den", "cellar", "tavern"], "poor")
add("l", "court_a", "furniture", [
    ("iron_cage", "2x1", "", "a big iron cage for prisoners with a locked door and straw inside"),
    ("cask_row", "2x1", "wall", "a row of three big casks lying on a wooden rack, in a cellar"),
    ("cellar_stairs", "2x1", "", "stone stairs going down into a cellar, seen in isometric, descending towards the back"),
    ("smuggler_table", "2x1", "", "a long rough table with a map, a lantern, coins and a dagger"),
], ["den", "cellar", "tavern"], "poor")
TARGET.update({"trapdoor": 30, "trapdoor_open": 34, "ladder": 56, "contraband_pile": 36, "fence_table": 30,
               "dice_table": 24, "stolen_goods": 26, "wine_rack": 54, "chain_post": 50, "iron_cage": 96, "cask_row": 100,
               "cellar_stairs": 96, "smuggler_table": 100})
# --- las piezas de antes de las mejoras (Guild Renew y Pillow), repintadas con la referencia de su sala: la lupa vio
# que no casaban (ΔE medio 10,5 a la paleta del fondo frente a 7,1 de las de fal; otro contorno y otro sombreado) ----
add("s", "forge_a", "trade", [
    ("engraving_bench", "1x1", "", "an engraver's workbench with small burins, a vice and a half-engraved blade"),
    ("master_seal", "1x1", "", "a stone block with a big master smith's seal stamp and red wax"),
    ("hidden_passage", "1x1", "walk", "a secret hatch in the floor with an iron ring, half hidden under straw"),
    ("smuggler_cache", "1x1", "", "a pried-open floor plank showing hidden bundles of goods"),
    ("double_ledger", "1x1", "", "a small desk with two ledger books, a quill and a candle"),
    ("master_bench", "1x1", "", "a heavy master's workbench with fine tools laid out on it"),
], ["forge", "all"])
add("s", "carpentry_a", "trade", [
    ("frame_saw", "1x1", "", "a big wooden frame saw standing on its stand"),
    ("planes_rack", "1x1", "wall", "a wall rack with wood planes of several sizes"),
    ("gouges", "1x1", "", "a stool with a cloth roll of carving gouges"),
    ("carpenter_mark", "1x1", "", "a branding iron and a stamp for marking wood on a block"),
    ("master_carpenter_bench", "1x1", "", "a fine master carpenter's bench with a carved chair leg on it"),
    ("vice_bench", "1x1", "", "a sturdy short bench with a big wooden vice"),
], ["carpentry"])
add("s", "masonry_b", "trade", [
    ("mason_chisels", "1x1", "", "an open box of mason's chisels, points and a mallet"),
    ("mason_crane", "1x1", "", "a small wooden hoist with a rope and a stone block hanging"),
    ("mason_mark", "1x1", "", "a dressed stone with a carved mason's mark"),
    ("master_yard", "1x1", "", "a master mason's tracing board with drawings on two trestles"),
    ("mason_templates", "1x1", "", "wooden templates leaning on a trestle"),
    ("mason_wedges", "1x1", "", "iron wedges and feathers by a half-split stone"),
], ["masonry"])
add("s", "tailor_shop_a", "trade", [
    ("tailor_dyes", "1x1", "", "two dye vats, one red and one blue, with dripping cloth"),
    ("tailor_master_table", "1x1", "", "a fine small cutting table with a measuring rod and silk"),
    ("tailor_seal", "1x1", "", "a small table with the tailors' guild seal and wax"),
    ("tailor_shears", "1x1", "", "big tailor's shears hanging on a wooden stand"),
    ("tailor_shuttle", "1x1", "", "a rack of loom shuttles and bobbins of thread"),
    ("tailor_treadle", "1x1", "", "a treadle spinning wheel with wool"),
], ["tailor_shop"])
# --- la Taberna-Posada grande (barra larga, fogón del salón) ----------------------------------------------------
add("s", "tavern_b", "furniture", [
    ("bar_shelf", "1x1", "wall", "a tall wooden shelf behind a tavern bar, full of clay jugs, pewter tankards and bottles"),
    ("cask_stand_big", "1x1", "wall", "a big wine cask lying on a wooden cradle, with a brass tap"),
    ("tankard_rack", "1x1", "wall", "a low wooden rack with pegs and hanging pewter tankards and clay jugs"),
], ["tavern"])
add("s", "tavern_b", "light", [
    ("hall_firepit", "1x1", "", "an open round hearth of grey stones on the floor, with a burning log fire and an iron tripod with a pot"),
    ("hall_brazier", "1x1", "", "an iron brazier on three legs with glowing coals and small flames"),
], ["tavern", "house"])
add("s", "tavern_b", "container", [
    ("jug_crate", "1x1", "", "a wooden crate full of clay jugs and bottles"),
], ["tavern"])
# --- la Consulta médica (H12.2, el Erudito: 04d 4.22.5.1) ------------------------------------------------------------
add("s", "clinic_a", "trade", [
    ("mortar_table", "1x1", "", "a small wooden table with a big stone mortar and pestle and fresh herbs"),
    ("apothecary_shelf", "1x1", "wall", "a tall wooden apothecary shelf full of glass jars, bottles and clay pots"),
    ("bandage_basket", "1x1", "", "a wicker basket full of rolled white linen bandages"),
    ("washbasin_stand", "1x1", "", "a wooden stand with a copper washbasin, a jug and a towel"),
    ("instrument_tray", "1x1", "", "a small table with a cloth and a physician's instruments: a bone saw, knives, pliers"),
    ("medicine_chest", "1x1", "", "an open wooden chest with brass corners and small vials inside"),
    ("folding_screen", "1x1", "", "a folding screen of linen panels in a wooden frame"),
    ("leech_jars", "1x1", "", "a small table with three tall glass jars and a stack of old books"),
    ("herb_drying_frame", "1x1", "", "a wooden frame with bundles of drying herbs hanging from it"),
], ["clinic"])
add("l", "clinic_a", "trade", [
    ("examination_cot", "2x1", "", "a wooden examination cot with a white linen sheet and a pillow"),
    ("operating_table", "2x1", "", "a sturdy wooden operating table with leather straps and a white cloth"),
    ("apothecary_counter", "2x1", "", "a long wooden counter with jars, a small brass scale and a mortar"),
    ("waiting_bench", "2x1", "", "a long simple wooden bench for people to wait on"),
], ["clinic"])
add("w", "clinic_a", "textile", [
    ("anatomy_chart", "1x1", "wall", "a parchment chart of the human body (a simple drawing, no gore) pinned on the wall"),
    ("medical_diploma", "1x1", "wall", "a framed parchment scroll with a red wax seal"),
    ("herb_shelf_wall", "1x1", "wall", "a small wall shelf with bunches of dried herbs and two small jars"),
], ["clinic"])
TARGET.update({"mortar_table": 30, "apothecary_shelf": 56, "bandage_basket": 20, "washbasin_stand": 32,
               "instrument_tray": 28, "medicine_chest": 24, "folding_screen": 46, "leech_jars": 30,
               "herb_drying_frame": 44, "examination_cot": 92, "operating_table": 92, "apothecary_counter": 96,
               "waiting_bench": 90, "anatomy_chart": 36, "medical_diploma": 24, "herb_shelf_wall": 24})
# --- el Banco (H12.2, el Banquero: 04d 4.22.5.6) -------------------------------------------------------------------
add("l", "bank_a", "trade", [
    ("bank_counter", "2x1", "", "a long carved wooden banking counter with a brass balance scale and stacks of coins"),
    ("ledger_cabinet", "2x1", "wall", "a tall wide carved cabinet full of ledgers and rolled contracts"),
    ("vault_door_wall", "2x1", "wall", "a heavy iron vault door with rivets and a big ring handle, set in a stone wall"),
    ("client_bench", "2x1", "", "a carved wooden bench with a back, for clients to wait"),
], ["bank"], "rich")
add("s", "bank_a", "trade", [
    ("banker_desk", "1x1", "", "a small writing desk with a quill, an inkwell, a candle and a parchment"),
    ("coin_chest", "1x1", "", "an open wooden chest full of gold coins"),
    ("iron_strongbox", "1x1", "", "a heavy grey iron strongbox with locks"),
    ("balance_table", "1x1", "", "a small table with a brass balance scale and small weights"),
    ("scroll_basket", "1x1", "", "a wooden bucket full of rolled parchment scrolls"),
    ("money_bags", "1x1", "", "three leather money bags tied with string, on the floor"),
], ["bank"], "rich")
TARGET.update({"bank_counter": 100, "ledger_cabinet": 96, "vault_door_wall": 92, "client_bench": 88, "banker_desk": 30,
               "coin_chest": 22, "iron_strongbox": 26, "balance_table": 30, "scroll_basket": 24, "money_bags": 18})
TARGET.update({"bar_shelf": 54, "cask_stand_big": 36, "tankard_rack": 34, "hall_firepit": 34, "hall_brazier": 34,
               "jug_crate": 24})
TARGET.update({"engraving_bench": 34, "master_seal": 30, "hidden_passage": 30, "smuggler_cache": 26, "double_ledger": 32,
               "master_bench": 34, "frame_saw": 44, "planes_rack": 36, "gouges": 26, "carpenter_mark": 26,
               "master_carpenter_bench": 34, "vice_bench": 32, "mason_chisels": 22, "mason_crane": 56, "mason_mark": 26,
               "master_yard": 38, "mason_templates": 40, "mason_wedges": 24, "tailor_dyes": 32, "tailor_master_table": 32,
               "tailor_seal": 30, "tailor_shears": 40, "tailor_shuttle": 36, "tailor_treadle": 36})


def grids():
    """[(nombre, kind, ref, [piezas])] en el orden de P, cada una con tantas piezas como celdas."""
    out = []
    by = {}
    for p in P:
        by.setdefault((p["grid"], p["ref"]), []).append(p)
    n = 0
    for (kind, ref), ps in by.items():
        cols, rows = GRIDS[kind][:2]
        k = cols * rows
        for i in range(0, len(ps), k):
            n += 1
            out.append((f"g{n:02d}_{kind}_{ref}", kind, ref, ps[i:i + k]))
    return out


# --- paleta fija de interiores ------------------------------------------------------------------------------------
PAL_PATH = os.path.join(RAW, "paleta.json")
# Rampas de acento que los fondos cálidos no traen (telas, escudos, estandartes, vidrios, frutas): sin ellas los
# rojos, azules y verdes de las piezas se van a pardo o gris.
ACCENTS = ["#4a1612", "#8b2e2e", "#b8432f", "#e07a5a", "#1e2a4a", "#2e4f8b", "#4a78b8", "#8ab0d8",
           "#1e3a1e", "#3f6b3a", "#6a9a4a", "#a8c870", "#8a6a1e", "#c8a84e", "#e8d070", "#4a2e5a",
           "#6b4a8b", "#e0e0d0", "#b8b8b0", "#2e7a7a"]


def palette(n=64):
    """La paleta de interiores: `n` colores de los fondos y las referencias (cálidos, con sus sombras frías)."""
    if os.path.exists(PAL_PATH):
        return json.load(open(PAL_PATH))
    srcs = [os.path.join(ROOT, "assets", "art", "interiors", "forge", "backdrop.png")]
    srcs += [os.path.join(REFS, f"{r}.png") for r in ("forge_b", "tavern_a", "house_b", "armory_a", "tailor_shop_b",
                                                      "town_hall_b", "carpentry_b", "masonry_a")]
    tiles = []
    for s in srcs:
        im = Image.open(s).convert("RGB")
        im = im.resize((im.width // 3, im.height // 3), Image.BOX)
        tiles.append(im)
    W = sum(t.width for t in tiles)
    H = max(t.height for t in tiles)
    sheet = Image.new("RGB", (W, H))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width
    # sin el negro del fondo de las referencias (pesa mucho y no es un color de pieza)
    px = [c for c in sheet.getdata() if sum(c) > 40]
    flat = Image.new("RGB", (len(px), 1))
    flat.putdata(px)
    q = flat.quantize(colors=n - 2, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[: (n - 2) * 3]
    cols = ["#%02x%02x%02x" % tuple(pal[i:i + 3]) for i in range(0, len(pal), 3)]
    cols = ["#140d08", "#f2e6c8"] + cols  # el contorno casi negro y un blanco cálido (velas, espuma, telas)
    cols += ACCENTS
    os.makedirs(RAW, exist_ok=True)
    json.dump(cols, open(PAL_PATH, "w"))
    return cols


# --- generación -----------------------------------------------------------------------------------------------------
STYLE_SHEET = os.path.join(RAW, "ref", "estilo_forja_x4.png")


def style_sheet():
    if os.path.exists(STYLE_SHEET):
        return STYLE_SHEET
    d = os.path.join(ROOT, "assets", "art", "interiors", "forge")
    names = ["hearth", "anvil_stump", "coal_bin", "grindstone"]
    sheet = Image.new("RGB", (4 * 360, 400), (255, 255, 255))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(d, n + ".png")).convert("RGBA")
        im = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
        tmp = Image.new("RGBA", (360, 400), (255, 255, 255, 255))
        tmp.alpha_composite(im, ((360 - im.width) // 2, 400 - im.height))
        sheet.paste(tmp.convert("RGB"), (i * 360, 0))
    os.makedirs(os.path.dirname(STYLE_SHEET), exist_ok=True)
    sheet.save(STYLE_SHEET)
    return STYLE_SHEET


def prompt(kind, items):
    cols, rows, _, art = GRIDS[kind]
    cell = 1024 // cols
    block = cell // art
    names = []
    for i, p in enumerate(items):
        r, c = divmod(i, cols)
        names.append(f"row {r + 1} column {c + 1}: {p['desc']}")
    if kind == "w":
        what = ("Each piece is something that HANGS ON A WALL, drawn flat against the back-right wall of the room in "
                "the same isometric 2:1 projection (its top and bottom edges slant down to the right at 26.6 degrees), "
                "with no wall behind it.")
    elif kind == "l":
        what = ("Each piece is a large piece of furniture two floor tiles long, lying along the isometric axis that "
                "goes down to the right, standing on the bottom of its cell.")
    elif kind == "xs":
        what = "Each piece is a small object (it fits on a table), centred in its cell, standing on the bottom of it."
    else:
        what = "Each piece stands on one floor tile, centred in its cell and standing on the bottom of it."
    return (
        f"Image 1 is an interior of our medieval pixel-art game. Image 2 shows some of its finished furniture sprites, "
        f"enlarged 4x, for the projection, the scale, the 1-pixel dark outline and the shading. Create ONE square image "
        f"that is a {cols}x{rows} grid of {cols * rows} separate NEW pieces in exactly that style: warm 16-bit pixel art "
        f"(Graveyard Keeper), isometric 2:1 projection, light from the top-left, dark one-colour outline, the palette of "
        f"image 1. Every art pixel is a {block}x{block} block. {what} Plain flat white background in every cell, no "
        f"floor tile, no shadow on the background, no grid lines, no text, no letters, no people. The pieces, "
        + "; ".join(names) + "."
    )


def gen_one(g):
    name, kind, ref, items = g
    raw = os.path.join(RAW, "crudo", name + ".png")
    if os.path.exists(raw):
        return f"ya está {name}"
    fpi.guard(UNIT)
    args = {"prompt": prompt(kind, items), "num_images": 1, "aspect_ratio": "1:1", "output_format": "png",
            "image_urls": [_URLS[os.path.join(REFS, ref + ".png")], _URLS[style_sheet()]]}
    t0 = time.time()
    for attempt in range(2):
        try:
            res = fal_client.subscribe(ENDPOINT, arguments=args)
            break
        except Exception as e:  # el filtro del modelo a veces no da imagen (sin cobro): un reintento
            if attempt:
                return f"FALLA {name}: {str(e)[:120]}"
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    urllib.request.urlretrieve(res["images"][0]["url"], raw)
    fpi.note("props_interior", ENDPOINT, 1, UNIT, f"rejilla {name} ({len(items)} piezas, {time.time() - t0:.0f} s)")
    with open(os.path.join(RAW, "crudo", "prompts.log"), "a") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {name} | {ENDPOINT} | ref={ref},estilo\n  {args['prompt']}\n\n")
    return f"{name}: {len(items)} piezas"


_URLS = {}  # ruta -> URL de fal (se suben antes, en serie: en paralelo fal_client falla con «Invalid storage type»)


def gen(only):
    gs = [g for g in grids() if not only or g[0] in only or any(g[0].startswith(o) for o in only)]
    for g in gs:
        for path in (os.path.join(REFS, g[2] + ".png"), style_sheet()):
            if path not in _URLS:
                _URLS[path] = fal_client.upload_file(path)
    with ThreadPoolExecutor(4) as ex:
        for msg in ex.map(gen_one, gs):
            print(msg)
    print(f"interiores: {fpi.total():.3f} USD")


# --- procesado ------------------------------------------------------------------------------------------------------
def _feet(pid, w, h, fp, small):
    """Ancla (los pies) dentro del sprite recortado: abajo en el centro, subida media huella (casillas 64×32)."""
    if small:
        return [w // 2, h - 2]
    fw, fd = [int(v) for v in fp.split("x")]
    up = min((fw + fd) * 8, h // 3)
    return [w // 2, h - 1 - up]


def proc_one(g):
    from types import SimpleNamespace
    import fal_fachadas
    import fal_iconos as fic
    import fal_procesar as fp
    name, kind, ref, items = g
    raw = os.path.join(RAW, "crudo", name + ".png")
    if not os.path.exists(raw):
        return []
    cols, rows, block, art = GRIDS[kind]
    im = Image.open(raw).convert("RGBA").resize((1024, 1024), Image.LANCZOS)
    cw = 1024 // cols
    pal = ",".join(palette())
    out = []
    for i, p in enumerate(items):
        r, c = divmod(i, cols)
        inset = max(4, cw // 64)
        cell = im.crop((c * cw + inset, r * cw + inset, (c + 1) * cw - inset, (r + 1) * cw - inset))
        cell = cell.resize((cw, cw), Image.LANCZOS)
        keyed = fal_fachadas.holes(fp.key_background(cell, "white", 30))
        if keyed.getchannel("A").getbbox() is None:
            out.append((p, None, "vacía"))
            continue
        src = os.path.join(RAW, "celdas", p["id"] + ".png")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        keyed.save(src)
        kb = keyed.getchannel("A").getbbox()
        dim = (kb[2] - kb[0]) if kind == "l" else (kb[3] - kb[1]) if kind != "xs" else max(kb[2] - kb[0], kb[3] - kb[1])
        block = max(2, round(dim / target(p)))  # el bloque que deja la pieza a su tamaño de juego
        dst = os.path.join(RAW, "i2p", f"{p['id']}_s{block}.png")
        if not os.path.exists(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            for attempt in range(3):
                try:
                    fpi.pixel(SimpleNamespace(piece="props_interior", src=src, dst=dst, colors=32, scale=block,
                                              palette=pal, transparent=True))
                    break
                except Exception as e:  # noqa: BLE001 (un fallo de red o de cola: se reintenta)
                    if attempt == 2:
                        out.append((p, None, f"image2pixel: {str(e)[:80]}"))
            if not os.path.exists(dst):
                continue
        up = Image.open(dst).convert("RGBA")
        nat = up.resize((max(1, up.width // block), max(1, up.height // block)), Image.NEAREST)
        nat.putalpha(nat.getchannel("A").point(lambda v: 255 if v > 127 else 0))
        bb = nat.getchannel("A").getbbox()
        if bb is None:
            out.append((p, None, "vacía tras pixelar"))
            continue
        spr = soft_outline(nat.crop(bb))
        spr = _shadow(spr, p)
        dstp = os.path.join(OUT, p["id"] + ".png")
        os.makedirs(OUT, exist_ok=True)
        spr.save(dstp)
        out.append((p, spr.size, ""))
    return out


# El contorno «selectivo» (04g §4.6.5.1: el mismo contorno que el fondo): el borde de la silueta toma el color de la
# propia pieza oscurecido, más claro del lado de la luz (arriba a la izquierda) que del de la sombra, y nunca más
# oscuro que lo más oscuro del fondo pintado (luminancia ~40). Con el contorno negro de antes las piezas se leían
# como pegatinas sobre el fondo (el 85 % del borde por debajo de 35).
OUTLINE_LIGHT, OUTLINE_SHADE, OUTLINE_FLOOR = 0.62, 0.42, 38.0


def soft_outline(im):
    im = im.copy()
    px = im.load()
    w, h = im.size
    out = {}
    for y in range(h):
        for x in range(w):
            if px[x, y][3] < 128:
                continue
            open_ = [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                     if not (0 <= x + dx < w and 0 <= y + dy < h) or px[x + dx, y + dy][3] < 128]
            if not open_:
                continue
            # el color de dentro: la media de los vecinos opacos que no son borde (o el propio)
            inner = [px[x - dx, y - dy] for dx, dy in open_ if 0 <= x - dx < w and 0 <= y - dy < h
                     and px[x - dx, y - dy][3] >= 128]
            base = inner[0] if inner else px[x, y]
            lit = any(d in ((-1, 0), (0, -1)) for d in open_) and not any(d in ((1, 0), (0, 1)) for d in open_)
            k = OUTLINE_LIGHT if lit else OUTLINE_SHADE
            c = [v * k for v in base[:3]]
            lum = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
            if lum < OUTLINE_FLOOR:
                f = OUTLINE_FLOOR / max(1.0, lum)
                c = [min(255.0, v * f) for v in c] if lum > 4 else [OUTLINE_FLOOR * 0.9, OUTLINE_FLOOR * 0.75, OUTLINE_FLOOR * 0.6]
            out[(x, y)] = tuple(int(v) for v in c) + (255,)
    for (x, y), c in out.items():
        px[x, y] = c
    return im


def _shadow(spr, p):
    """Una sombra suave bajo la pieza (elipse 2:1, tramada), salvo lo plano, lo que cuelga y lo pequeño."""
    if p["grid"] in ("w", "xs") or "walk" in p["flags"]:
        return spr
    w, h = spr.size
    fw, fd = [int(v) for v in p["footprint"].split("x")]
    sw = min(w + 4, (fw + fd) * 28)
    sh = sw // 2
    canvas = Image.new("RGBA", (max(w, sw), h + 3), (0, 0, 0, 0))
    sx = (canvas.width - sw) // 2
    sy = canvas.height - sh
    sd = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sd)
    d.ellipse((sx, sy, sx + sw, sy + sh), fill=(20, 12, 8, 90))
    px = sd.load()
    for y in range(sd.height):  # borde tramado
        for x in range(sd.width):
            if px[x, y][3] and (x + y) % 2 and (((x - sx - sw / 2) / (sw / 2)) ** 2 + ((y - sy - sh / 2) / (sh / 2)) ** 2) > 0.6:
                px[x, y] = (0, 0, 0, 0)
    canvas.alpha_composite(sd)
    canvas.alpha_composite(spr, ((canvas.width - w) // 2, 0))
    return canvas


def proc(only):
    gs = [g for g in grids() if not only or g[0] in only or any(g[0].startswith(o) for o in only)]
    palette()
    fal_client.upload_file(style_sheet())  # la primera subida en serie (prepara el almacén de fal para los hilos)
    done = []
    with ThreadPoolExecutor(4) as ex:
        for res in ex.map(proc_one, gs):
            done += res
    ok = [(p, s) for p, s, why in done if s]
    for p, s, why in done:
        if not s:
            print("  sin pieza:", p["id"], why)
    write_inventory([p for p, s in ok], {p["id"]: s for p, s in ok})
    print(f"{len(ok)} piezas en {os.path.relpath(OUT, ROOT)}")


def write_inventory(pieces, sizes):
    inv = json.load(open(INV, encoding="utf-8"))
    by = {a["id"]: a for a in inv["assets"]}
    grid_of = {p["id"]: g[0] for g in grids() for p in g[3]}
    for p in pieces:
        w, h = sizes[p["id"]]
        small = p["grid"] == "xs"
        feet = _feet(p["id"], w, h, p["footprint"], small)
        flags = p["flags"].split(",") if p["flags"] else []
        entry = by.get("iprop_" + p["id"])
        if entry is None:  # las fichas nuevas, juntas tras int_referencias (no al final: ahí escriben otras ramas)
            entry = {"id": "iprop_" + p["id"]}
            ids = [a["id"] for a in inv["assets"]]
            last = max([i for i, a in enumerate(ids) if a.startswith("iprop_") or a == "int_referencias"] or [len(ids) - 1])
            inv["assets"].insert(last + 1, entry)
            by[entry["id"]] = entry
        entry.update({
            "tipo": "prop", "estado": "sprite", "para": ["interiores"],
            "ruta": f"assets/art/props/interior/{p['id']}.png",
            "origen": f"fal: nano-banana-2/edit, rejilla {grid_of[p['id']]} (ref: _referencias/{p['ref']}.png y la "
                      f"forja ×4) + image2pixel con la paleta de interiores (tools/art/fal_props.py)",
            "coste_gen": 0,
            "coste_usd": round(UNIT / (GRIDS[p["grid"]][0] * GRIDS[p["grid"]][1]), 4),
            "notas": p["desc"],
            "prop": {"category": "light" if p["id"] in LIGHTS else p["category"], "footprint": [int(v) for v in p["footprint"].split("x")],
                     "size": [w, h], "feet": feet, "height": feet[1],
                     "walkable": "walk" in flags or "flat" in flags, "wall": "wall" in flags,
                     "on_top": "top" in flags, "hangs": p["grid"] == "w", "mirror": True,
                     "trades": p["tags"], "style": p["style"]},
        })
    json.dump(inv, open(INV, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    open(INV, "a").write("\n")


# --- hoja de contacto -----------------------------------------------------------------------------------------------
def hoja(only, out):
    gs = [g for g in grids() if not only or g[0] in only or any(g[0].startswith(o) for o in only)]
    items = [p for g in gs for p in g[3] if os.path.exists(os.path.join(OUT, p["id"] + ".png"))]
    cw, chh, cols = 200, 150, 9
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cw, rows * chh), (42, 31, 20))
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(items):
        im = Image.open(os.path.join(OUT, p["id"] + ".png")).convert("RGBA")
        k = 2 if im.width * 2 <= cw - 8 and im.height * 2 <= chh - 20 else 1  # ×2 (×1 si no cabe): misma escala
        im = im.resize((im.width * k, im.height * k), Image.NEAREST)
        x, y = (i % cols) * cw, (i // cols) * chh
        tile = Image.new("RGBA", (cw, chh), (58, 44, 30, 255))
        tile.alpha_composite(im, ((cw - im.width) // 2, chh - 16 - im.height))
        sheet.paste(tile.convert("RGB"), (x, y))
        d.text((x + 4, y + chh - 14), p["id"][:22], fill=(212, 184, 150))
    sheet.save(out)
    print(f"hoja: {len(items)} piezas -> {out}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    for c in ("gen", "proc", "hoja"):
        s = sub.add_parser(c)
        s.add_argument("--only", default="")
        if c == "hoja":
            s.add_argument("--out", default=os.path.join(RAW, "hoja.png"))
    a = ap.parse_args()
    only = [o for o in getattr(a, "only", "").split(",") if o]
    if a.cmd == "list":
        gs = grids()
        for g in gs:
            print(g[0], len(g[3]), ", ".join(p["id"] for p in g[3]))
        print(f"{len(gs)} rejillas, {sum(len(g[3]) for g in gs)} piezas, {len(gs) * UNIT:.2f} USD")
    elif a.cmd == "gen":
        if not os.environ.get("FAL_KEY"):
            sys.exit("Falta FAL_KEY en .env")
        gen(only)
    elif a.cmd == "proc":
        proc(only)
    else:
        hoja(only, a.out)


if __name__ == "__main__":
    main()
