#!/usr/bin/env python3
"""Art of the H12 artisan trades (carpenter, mason, tailor), derived with Pillow from what the project already has and
from the Guild Renew sprites (read only). No credits spent: everything here is a placeholder or a derived sprite until
the PixelLab batch of the shopping list (assets/art/MANIFEST.md).

  python3 tools/art/oficios_h12.py [--guild ~/Code/guild] [--preview DIR]

Writes:
  buildings/escala_b/<building>.png   exteriors at scale B (tools/art/escala_b.py add_rows), with a trade sign and a
                                      yard prop: carpentry = guild's market "materiales" barn + a carpenter's bench;
                                      masonry = house_d (stone cottage) + a stone pile; tailor_shop = guild's "roperia"
  interiors/<building>/               floor and walls (the forge's kit recoloured: planks, grey stone, plaster), the two
                                      stations of the trade and the six Production / Quality upgrade visuals (iso boxes,
                                      80×72 canvas, tile centre at (40, 56), like tools/art/dibujar_mejoras.py)
  icons/<item>.png, icons/small/      the new items (32×32 and 16×16)
  buildings/stall_<clothier|goods>.png  the two new plaza stalls (stall_materials recoloured, with goods on it)
"""
import argparse
import colorsys
import os
import sys

from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from derivar_guild import half, pad_to, remap  # noqa: E402
from dibujar_pixel import EARTH, GOLD, IRON, OUTLINE, PLASTER, RED, STONE, WATER, WOOD, hexc, outline  # noqa: E402
from dibujar_mejoras import AX, AY, box, canvas, legs  # noqa: E402
from escala_b import add_rows  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "assets", "art")
CLOTH = [hexc(c) for c in ("3a1f3a", "5a2e5a", "7a3e72", "9a5a8e", "c08ab0")]
BLUE = [hexc(c) for c in ("1f2e4a", "2e4a6b", "3e6290", "5a80b0")]
WOOL = [hexc(c) for c in ("8a7f70", "b0a690", "d8cfb8", "efe8d6")]


def save(img, rel):
    p = os.path.join(ART, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    print(f"  {rel} {img.size[0]}×{img.size[1]}")


def load(rel):
    return Image.open(os.path.join(ART, rel)).convert("RGBA")


def gload(guild, rel):
    return Image.open(os.path.join(guild, "assets", "sprites", rel)).convert("RGBA")


def hue_to(target_h, sat_k=1.0, val_k=1.0, keep_dark=True):
    def fn(h, s, v):
        if keep_dark and v < 0.18:
            return h, s, v
        return target_h, min(1.0, s * sat_k), min(1.0, v * val_k)
    return fn


def finish(img, rel):
    save(outline(img), rel)


# --- yard props and signs on the facades ------------------------------------------------------------------------------

def sign(icon16, board=WOOD):
    """A hanging trade sign: a bracket, a 20×16 board and the trade's 16 px icon on it."""
    img = Image.new("RGBA", (26, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.line([(1, 2), (24, 2)], fill=IRON[1], width=2)                  # bracket
    d.line([(6, 3), (6, 8)], fill=IRON[2])
    d.line([(20, 3), (20, 8)], fill=IRON[2])
    d.rectangle([2, 8, 23, 27], fill=board[2], outline=OUTLINE)
    d.rectangle([3, 9, 22, 26], fill=board[3])
    img.alpha_composite(icon16, (5, 10))
    return img


def bench_prop():
    """A carpenter's bench in the yard: a long table with a plank and a saw on it."""
    img = canvas()
    d = ImageDraw.Draw(img)
    legs(d, AX, AY, 34, 12, 11, WOOD[1])
    box(d, AX, AY, 34, 12, 3, WOOD[5], WOOD[4], WOOD[3], lift=11)
    box(d, AX - 2, AY - 15, 22, 6, 2, PLASTER[3], PLASTER[2], PLASTER[1])     # a plank
    d.polygon([(AX + 6, AY - 22), (AX + 16, AY - 27), (AX + 17, AY - 25), (AX + 7, AY - 20)], fill=IRON[4])  # saw
    d.rectangle([AX + 4, AY - 22, AX + 7, AY - 19], fill=WOOD[2])
    return outline(img)


def stone_pile():
    """Rough stone blocks stacked in the yard."""
    img = canvas()
    d = ImageDraw.Draw(img)
    for (dx, dy, a, b, h, lift) in ((-10, 4, 12, 10, 8, 0), (6, 4, 14, 10, 8, 0), (-2, -2, 12, 10, 8, 0),
                                     (-2, -6, 12, 9, 7, 8)):
        box(d, AX + dx, AY + dy, a, b, h, STONE[5], STONE[4], STONE[2], lift=lift)
    return outline(img)


def plank_stack():
    img = canvas()
    d = ImageDraw.Draw(img)
    for k in range(4):
        box(d, AX, AY, 30, 10, 2, WOOD[5], WOOD[4], WOOD[3], lift=k * 3)
    return outline(img)


def place(base, sprite, x, y):
    base.alpha_composite(sprite, (int(x), int(y)))


def exteriors(guild):
    out = {}
    # carpentry: the guild's materials barn, taller (scale B), with the bench and the sign
    barn = gload(guild, "buildings/market/exterior/building_materiales_192.png")
    im, cy, _ = add_rows(barn, 96, 148, 2, 40, 12)
    im, cy, _ = add_rows(im, 96, cy, 41, 60, 6)
    big = Image.new("RGBA", (192, im.height), (0, 0, 0, 0))
    big.alpha_composite(im)
    place(big, sign(load("icons/small/saw.png")), 118, 92)
    place(big, bench_prop(), 120, im.height - 82)
    save(big, "buildings/escala_b/carpentry.png")
    out["carpentry"] = {"anchor": [104, 120 + 18], "size": big.size}
    # masonry: house_d (stone cottage, already at scale B) recoloured towards grey stone, with stones and a sign
    hd = load("buildings/escala_b/house_d.png")
    def greyer(h, s, v):
        if 20 <= h < 60 and s > 0.2 and v > 0.4:     # straw roof -> dark slate
            return 214.0, s * 0.25, v * 0.72
        return h, s * 0.8, v
    mas = remap(hd, greyer)
    big = Image.new("RGBA", (192, mas.height), (0, 0, 0, 0))
    big.alpha_composite(mas)
    place(big, sign(load("icons/small/hammer.png"), board=STONE), 128, 96)
    place(big, stone_pile(), 112, mas.height - 78)
    place(big, stone_pile(), 6, mas.height - 92)
    save(big, "buildings/escala_b/masonry.png")
    out["masonry"] = {"anchor": [96, 145 + 16], "size": big.size}
    # tailor_shop: the guild's clothier ("roperia", already a tailor's with clothes on a line), taller
    rop = gload(guild, "buildings/market/exterior/building_roperia_192.png")
    im, cy, _ = add_rows(rop, 96, 157, 2, 40, 10)
    im, cy, _ = add_rows(im, 96, cy, 41, 70, 6)
    save(im, "buildings/escala_b/tailor_shop.png")
    out["tailor_shop"] = {"anchor": [96, 133 + 16], "size": im.size}
    return out


# --- interiors ----------------------------------------------------------------------------------------------------------

KIT_TONES = {
    "carpentry": {"floor": hue_to(28, 0.9, 1.05), "wall": hue_to(26, 1.1, 1.0)},
    "masonry": {"floor": hue_to(30, 0.25, 0.95), "wall": hue_to(214, 0.2, 0.92)},
    "tailor_shop": {"floor": hue_to(18, 0.7, 1.0), "wall": hue_to(40, 0.45, 1.12)},
}


def kits():
    for b, tones in KIT_TONES.items():
        save(remap(load("interiors/forge/floor.png"), tones["floor"]), f"interiors/{b}/floor.png")
        for w in ("wall_ne", "wall_nw", "wall_door_ne", "wall_door_nw"):
            img = load(f"interiors/forge/{w}.png")
            def keep_door(h, s, v, f=tones["wall"]):
                if 22 <= h < 40 and s > 0.45 and v < 0.7:   # the door's wood stays wood
                    return h, s, v
                return f(h, s, v)
            save(remap(img, keep_door), f"interiors/{b}/{w}.png")


def table(a=32, b=14, h=13, top=WOOD):
    img = canvas()
    d = ImageDraw.Draw(img)
    legs(d, AX, AY, a, b, h, top[1])
    box(d, AX, AY, a, b, 3, top[5] if len(top) > 5 else top[4], top[4] if len(top) > 5 else top[3], top[3] if len(top) > 5 else top[2], lift=h)
    return img, d


def sawhorse():
    img = canvas()
    d = ImageDraw.Draw(img)
    for dx in (-12, 12):  # two crossed trestles
        d.line([(AX + dx - 5, AY + 2 - dx / 2), (AX + dx + 3, AY - 16 - dx / 2)], fill=WOOD[2], width=2)
        d.line([(AX + dx + 5, AY + 2 - dx / 2), (AX + dx - 3, AY - 16 - dx / 2)], fill=WOOD[3], width=2)
    box(d, AX, AY - 2, 36, 8, 3, PLASTER[3], PLASTER[2], PLASTER[1], lift=14)      # the log being sawn
    d.polygon([(AX + 2, AY - 30), (AX + 6, AY - 32), (AX + 6, AY - 20), (AX + 2, AY - 18)], fill=IRON[4])  # saw blade
    d.rectangle([AX + 1, AY - 34, AX + 7, AY - 31], fill=WOOD[2])
    return outline(img)


def workbench():
    img, d = table(36, 14, 12)
    box(d, AX - 6, AY - 15, 14, 8, 4, WOOD[5], WOOD[4], WOOD[3])                 # a box being joined
    d.line([(AX + 6, AY - 19), (AX + 14, AY - 23)], fill=IRON[4], width=2)       # chisel
    d.rectangle([AX + 12, AY - 25, AX + 16, AY - 22], fill=WOOD[2])             # mallet
    box(d, AX + 12, AY + 0, 6, 6, 4, IRON[3], IRON[2], IRON[1], lift=12)         # vice
    return outline(img)


def cutting_bench():
    img, d = table(34, 16, 9, top=STONE)
    box(d, AX - 2, AY - 12, 16, 12, 9, STONE[5], STONE[4], STONE[2])            # a block on the bench
    d.line([(AX - 8, AY - 20), (AX + 6, AY - 27)], fill=STONE[1])               # the scored line
    d.line([(AX + 10, AY - 20), (AX + 16, AY - 28)], fill=IRON[4], width=2)      # a wedge / chisel
    return outline(img)


def carving_bench():
    img = canvas()
    d = ImageDraw.Draw(img)
    box(d, AX, AY, 22, 22, 6, WOOD[4], WOOD[3], WOOD[2])                        # wooden base
    box(d, AX, AY - 6, 14, 14, 18, STONE[5], STONE[4], STONE[2])                # the piece being carved
    d.arc([AX - 6, AY - 30, AX + 6, AY - 22], 180, 360, fill=STONE[1])
    d.line([(AX + 9, AY - 22), (AX + 15, AY - 30)], fill=IRON[4], width=2)
    d.rectangle([AX + 14, AY - 33, AX + 18, AY - 29], fill=WOOD[2])
    return outline(img)


def loom():
    img = canvas()
    d = ImageDraw.Draw(img)
    box(d, AX, AY, 30, 14, 3, WOOD[3], WOOD[2], WOOD[1])                         # base
    for (x0, y0) in ((AX - 14, AY - 6), (AX + 14, AY - 20)):                     # uprights
        d.rectangle([x0 - 1, y0 - 26, x0 + 1, y0], fill=WOOD[3])
    d.line([(AX - 14, AY - 32), (AX + 14, AY - 46)], fill=WOOD[4], width=2)      # top beam
    d.line([(AX - 14, AY - 10), (AX + 14, AY - 24)], fill=WOOD[4], width=2)      # breast beam
    for k in range(0, 26, 2):                                                    # warp threads
        x = AX - 13 + k
        d.line([(x, AY - 31 - k / 2), (x, AY - 12 - k / 2)], fill=WOOL[2] if k % 4 else WOOL[3])
    d.polygon([(AX - 13, AY - 12), (AX + 13, AY - 25), (AX + 13, AY - 31), (AX - 13, AY - 18)], fill=CLOTH[2])  # cloth
    return outline(img)


def sewing_table():
    img, d = table(32, 14, 12)
    d.polygon([(AX - 12, AY - 15), (AX + 4, AY - 23), (AX + 12, AY - 19), (AX - 4, AY - 11)], fill=BLUE[2])  # cloth
    d.line([(AX - 10, AY - 15), (AX + 2, AY - 21)], fill=BLUE[3])
    d.line([(AX + 6, AY - 17), (AX + 12, AY - 20)], fill=IRON[4])                # shears
    d.point((AX + 4, AY - 16), fill=IRON[4])
    d.ellipse([AX - 14, AY - 21, AX - 9, AY - 17], fill=RED[2])                 # spool
    return outline(img)


STATIONS = {"carpentry": {"sawhorse": sawhorse, "workbench": workbench},
            "masonry": {"cutting_bench": cutting_bench, "carving_bench": carving_bench},
            "tailor_shop": {"loom": loom, "sewing_table": sewing_table}}


def with_icon(base_fn, icon, dx=0, dy=-26):
    img = base_fn()
    img.alpha_composite(icon, (AX - 8 + dx, AY - 8 + dy))
    return img


def upgrade_visuals():
    """Production and Quality upgrades of each trade (GDD 4.6.4: the only ones with a trade variant): the station or a
    piece of furniture with the tool or the mark on it. Placeholders, honest: derived, not final."""
    small = lambda i: load(f"icons/small/{i}.png")  # noqa: E731
    ups = {
        "carpentry": {
            "carpentry_frame_saw": lambda: sawhorse(),
            "carpentry_vice_bench": lambda: workbench(),
            "carpentry_master_bench": lambda: with_icon(workbench, small("chest"), 4, -30),
            "carpentry_planes": lambda: with_icon(lambda: table(22, 12, 11)[0], small("planks"), 0, -22),
            "carpentry_gouges": lambda: with_icon(lambda: table(22, 12, 11)[0], small("saw"), 0, -22),
            "carpentry_mark": lambda: with_icon(lambda: table(18, 18, 14)[0], small("cabinet"), 0, -26),
        },
        "masonry": {
            "masonry_wedges": lambda: cutting_bench(),
            "masonry_crane": lambda: crane(),
            "masonry_master_yard": lambda: with_icon(carving_bench, small("statue"), 0, -40),
            "masonry_chisels": lambda: with_icon(lambda: table(22, 12, 11, top=STONE)[0], small("hammer"), 0, -22),
            "masonry_templates": lambda: with_icon(lambda: table(22, 12, 11)[0], small("ashlar"), 0, -22),
            "masonry_mark": lambda: with_icon(lambda: table(18, 18, 14, top=STONE)[0], small("millstone"), 0, -26),
        },
        "tailor_shop": {
            "tailor_treadle": lambda: loom(),
            "tailor_shuttle": lambda: with_icon(loom, small("wool"), 8, -44),
            "tailor_master_table": lambda: with_icon(sewing_table, small("fine_clothes"), 0, -30),
            "tailor_shears": lambda: with_icon(lambda: table(22, 12, 11)[0], small("needle"), 0, -22),
            "tailor_dyes": lambda: dyes(),
            "tailor_seal": lambda: with_icon(lambda: table(18, 18, 14)[0], small("common_clothes"), 0, -26),
        },
    }
    for b, d in ups.items():
        for vid, fn in d.items():
            save(fn(), f"interiors/{b}/upg_{vid.split('_', 1)[1]}.png")


def crane():
    img = canvas()
    d = ImageDraw.Draw(img)
    box(d, AX, AY, 12, 12, 4, WOOD[4], WOOD[3], WOOD[2])
    d.rectangle([AX - 1, AY - 44, AX + 1, AY - 4], fill=WOOD[3])
    d.line([(AX, AY - 44), (AX + 20, AY - 40)], fill=WOOD[4], width=2)
    d.line([(AX + 18, AY - 40), (AX + 18, AY - 22)], fill=IRON[2])
    box(d, AX + 18, AY - 14, 8, 8, 7, STONE[5], STONE[4], STONE[2], lift=0)
    return outline(img)


def dyes():
    img = canvas()
    d = ImageDraw.Draw(img)
    for k, col in enumerate((RED, BLUE, GOLD)):
        cx = AX - 14 + k * 14
        cy = AY - k * 3
        d.ellipse([cx - 6, cy - 12, cx + 6, cy], fill=WOOD[3])
        d.ellipse([cx - 5, cy - 13, cx + 5, cy - 8], fill=col[2])
    return outline(img)


# --- icons --------------------------------------------------------------------------------------------------------------

def icon_canvas():
    return Image.new("RGBA", (32, 32), (0, 0, 0, 0))


def icons(guild):
    out = {}
    # the saw was still missing (guild's icon_sierra is a mallet): a drawn placeholder
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.polygon([(4, 20), (24, 8), (27, 12), (7, 25)], fill=IRON[4])                # blade
    for k in range(6):
        x, y = 6 + k * 3.4, 24 - k * 2
        d.polygon([(x, y), (x + 2, y + 2), (x + 3, y - 1)], fill=IRON[2])          # teeth
    d.line([(5, 21), (24, 9)], fill=IRON[5])
    d.rectangle([23, 4, 29, 13], fill=WOOD[3]); d.rectangle([25, 6, 27, 10], fill=(0, 0, 0, 0))  # handle
    out["saw"] = outline(img)
    out["barrel"] = pad_to(half(gload(guild, "props/barrel/barrel_64.png")), 32, 32)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.rectangle([5, 12, 26, 26], fill=WOOD[3]); d.rectangle([5, 8, 26, 13], fill=WOOD[4])
    d.line([(5, 13), (26, 13)], fill=WOOD[1]); d.rectangle([14, 13, 17, 17], fill=GOLD[2])
    d.line([(9, 8), (9, 26)], fill=IRON[2]); d.line([(22, 8), (22, 26)], fill=IRON[2])
    out["chest"] = outline(img)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.rectangle([8, 3, 23, 29], fill=WOOD[3]); d.line([(15, 4), (15, 28)], fill=WOOD[1])
    d.point((13, 16), fill=GOLD[3]); d.point((18, 16), fill=GOLD[3]); d.rectangle([7, 2, 24, 4], fill=WOOD[4])
    out["cabinet"] = outline(img)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([3, 3, 28, 28], outline=WOOD[3], width=3); d.ellipse([13, 13, 18, 18], fill=WOOD[2])
    for a, b in (((16, 5), (16, 26)), ((5, 16), (26, 16)), ((8, 8), (23, 23)), ((23, 8), (8, 23))):
        d.line([a, b], fill=WOOD[4])
    d.ellipse([3, 3, 28, 28], outline=IRON[2], width=1)
    out["cart_wheel"] = outline(img)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.polygon([(4, 12), (16, 6), (28, 12), (16, 18)], fill=STONE[5]); d.polygon([(4, 12), (16, 18), (16, 27), (4, 21)], fill=STONE[3])
    d.polygon([(16, 18), (28, 12), (28, 21), (16, 27)], fill=STONE[2])
    out["ashlar"] = outline(img)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.line([(4, 28), (8, 14)], fill=WOOD[3], width=2); d.line([(27, 28), (23, 14)], fill=WOOD[3], width=2)
    d.ellipse([7, 4, 24, 21], fill=STONE[3]); d.ellipse([10, 7, 21, 18], fill=STONE[4]); d.ellipse([14, 11, 17, 14], fill=IRON[1])
    out["grindstone"] = outline(img)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.polygon([(2, 14), (20, 6), (30, 11), (12, 19)], fill=STONE[5]); d.polygon([(5, 14), (20, 8), (27, 11), (12, 17)], fill=WATER[3])
    d.polygon([(2, 14), (12, 19), (12, 27), (2, 22)], fill=STONE[3]); d.polygon([(12, 19), (30, 11), (30, 19), (12, 27)], fill=STONE[2])
    out["trough"] = outline(img)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([2, 10, 29, 26], fill=STONE[2]); d.ellipse([2, 6, 29, 22], fill=STONE[4]); d.ellipse([12, 11, 19, 16], fill=STONE[1])
    for k in range(4):
        d.line([(16, 14), (6 + k * 7, 8 + (k % 2) * 12)], fill=STONE[3])
    out["millstone"] = outline(img)
    img = icon_canvas(); d = ImageDraw.Draw(img)
    d.rectangle([9, 24, 22, 29], fill=STONE[3]); d.rectangle([12, 10, 19, 24], fill=STONE[4]); d.ellipse([11, 2, 20, 11], fill=STONE[5])
    d.line([(12, 14), (8, 20)], fill=STONE[4], width=2); d.line([(19, 14), (23, 20)], fill=STONE[4], width=2)
    out["statue"] = outline(img)
    def purple(h, s, v):
        return (300.0, min(1.0, s + 0.25), v) if s > 0.15 else (h, s, v)
    fine = remap(load("icons/common_clothes.png"), purple)
    d = ImageDraw.Draw(fine)
    d.line([(10, 9), (21, 9)], fill=GOLD[3]); d.line([(15, 10), (15, 22)], fill=GOLD[2])
    out["fine_clothes"] = fine
    for iid, im in out.items():
        save(im, f"icons/{iid}.png")
        h = half(im)
        save(pad_to(h, 16, 16, anchor_bottom=False) if h.width <= 16 and h.height <= 16 else h.resize((16, 16)),
             f"icons/small/{iid}.png")


def stalls():
    base = load("buildings/stall_materials.png")
    clothier = remap(base, lambda h, s, v: (285.0, s, v) if s > 0.35 and v > 0.35 else (h, s, v))
    clothier.alpha_composite(load("icons/small/common_clothes.png"), (18, 16))
    clothier.alpha_composite(load("icons/small/travel_cloak.png"), (32, 20))
    save(clothier, "buildings/stall_clothier.png")
    goods = remap(base, lambda h, s, v: (110.0, s * 0.8, v) if s > 0.35 and v > 0.35 else (h, s, v))
    goods.alpha_composite(load("icons/small/barrel.png"), (16, 18))
    goods.alpha_composite(load("icons/small/grindstone.png"), (32, 20))
    save(goods, "buildings/stall_goods.png")


def preview(folder):
    os.makedirs(folder, exist_ok=True)
    rels = ["buildings/escala_b/carpentry.png", "buildings/escala_b/masonry.png", "buildings/escala_b/tailor_shop.png"]
    for b in STATIONS:
        rels += [f"interiors/{b}/{z}.png" for z in STATIONS[b]] + [f"interiors/{b}/floor.png", f"interiors/{b}/wall_ne.png"]
        rels += sorted(f"interiors/{b}/{f}" for f in os.listdir(os.path.join(ART, "interiors", b)) if f.startswith("upg_") and f.endswith(".png"))
    rels += [f"icons/{i}.png" for i in ("barrel", "chest", "cabinet", "cart_wheel", "ashlar", "grindstone", "trough", "millstone", "statue", "fine_clothes")]
    rels += ["buildings/stall_clothier.png", "buildings/stall_goods.png"]
    cells = [Image.open(os.path.join(ART, r)).convert("RGBA") for r in rels]
    cols, cw, ch = 8, 200, 240
    sheet = Image.new("RGBA", (cols * cw, ((len(cells) + cols - 1) // cols) * ch), (52, 60, 48, 255))
    dr = ImageDraw.Draw(sheet)
    for i, (r, c) in enumerate(zip(rels, cells)):
        x, y = (i % cols) * cw, (i // cols) * ch
        k = 2 if c.width <= 96 else 1
        c2 = c.resize((c.width * k, c.height * k), Image.NEAREST)
        c2.thumbnail((cw - 4, ch - 16), Image.NEAREST)
        sheet.alpha_composite(c2, (x + 2, y + 2))
        dr.text((x + 2, y + ch - 13), r.split("/")[-2][:8] + "/" + r.split("/")[-1][:20], fill=(255, 240, 160, 255))
    sheet.save(os.path.join(folder, "oficios_h12.png"))
    print("  preview", os.path.join(folder, "oficios_h12.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--guild", default=os.path.expanduser("~/Code/guild"))
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    icons(a.guild)
    exteriors(a.guild)
    kits()
    for b, st in STATIONS.items():
        for z, fn in st.items():
            save(fn(), f"interiors/{b}/{z}.png")
    upgrade_visuals()
    stalls()
    if a.preview:
        preview(a.preview)


if __name__ == "__main__":
    main()
