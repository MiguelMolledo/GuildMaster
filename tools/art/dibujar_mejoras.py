#!/usr/bin/env python3
"""Pixel art of the forge's interior upgrades (docs/arte/reuso_guild.md, fourth batch), drawn with Pillow (iso boxes
in the style bible palette, dark outline, light from the top left) or cut from guild's props. No credits spent.

  python3 tools/art/dibujar_mejoras.py [--guild ~/Code/guild] [--preview DIR]

Writes assets/art/interiors/forge/upg_<id>.png, all on an 80×72 canvas whose point (40, 56) is the centre of the
tile the object stands on (its scene puts a Sprite2D with offset (-40, -56) on the upgrade's node).
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from derivar_guild import half, src  # noqa: E402
from dibujar_pixel import (EARTH, GOLD, IRON, OUTLINE, RED, STONE, WATER, WOOD, h32, outline,  # noqa: E402
                           save, OUT)

W, H = 80, 72
AX, AY = 40, 56   # where the tile's centre falls on the canvas


def canvas():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def box(d, cx, cy, a, b, h, top, left, right, lift=0):
    """An iso box whose footprint (a px along the back-right axis, b px along the back-left one) is centred on
    (cx, cy), raised `lift` px, `h` px high. Faces: top, left (front-left, lit) and right (front-right, shade)."""
    bx = cx - (a - b) / 2.0
    by = cy + (a + b) / 4.0 - lift
    B = (bx, by)
    R = (bx + a, by - a / 2.0)
    L = (bx - b, by - b / 2.0)
    K = (R[0] - b, R[1] - b / 2.0)
    up = lambda p: (p[0], p[1] - h)  # noqa: E731
    d.polygon([L, B, up(B), up(L)], fill=left)
    d.polygon([B, R, up(R), up(B)], fill=right)
    d.polygon([up(L), up(B), up(R), up(K)], fill=top)
    return {"B": B, "R": R, "L": L, "K": K, "top": [up(L), up(B), up(R), up(K)]}


def finish(img, rel):
    save(outline(img), rel)


def legs(d, cx, cy, a, b, h, color):
    for (dx, dy) in ((-(b - 2), -(b - 2) / 2.0), (a - 2, -(a - 2) / 2.0), (0, 0), (a - b, -(a + b) / 2.0 + 2)):
        x = cx - (a - b) / 2.0 + dx
        y = cy + (a + b) / 4.0 + dy
        d.rectangle([x - 1, y - h, x, y], fill=color)


def on_face(p0, p1, u, v):
    """A point on a vertical face whose bottom edge runs from p0 to p1: u along it (0..1), v px up."""
    return (p0[0] + (p1[0] - p0[0]) * u, p0[1] + (p1[1] - p0[1]) * u - v)


def sales_counter():
    """The sales counter (forge_commerce_1): panelled front with iron corners, a top with a scale, coins, a cloth
    and a sword for sale."""
    img = canvas()
    d = ImageDraw.Draw(img)
    g = box(d, AX, AY, 30, 12, 12, WOOD[3], WOOD[3], WOOD[2])
    L, B, R = g["L"], g["B"], g["R"]
    for p0, p1, n, dark in ((L, B, 2, WOOD[1]), (B, R, 3, WOOD[1])):  # sunken panels on both faces
        for k in range(n):
            a0, a1 = (k + 0.18) / n, (k + 0.82) / n
            q = [on_face(p0, p1, a0, 2), on_face(p0, p1, a1, 2), on_face(p0, p1, a1, 9), on_face(p0, p1, a0, 9)]
            d.polygon(q, fill=WOOD[2] if p0 is B else WOOD[4])
            d.line([q[3], q[2]], fill=dark)
            d.line([q[0], q[3]], fill=dark)
    for p in (L, B, R):  # iron corners
        d.line([(p[0], p[1] - 1), (p[0], p[1] - 11)], fill=IRON[2])
    box(d, AX, AY, 32, 14, 2, WOOD[5], WOOD[4], WOOD[3], lift=12)
    # the top runs from the front-left corner up to the right: things along it
    tl = on_face(L, B, 0.5, 14)
    tr = on_face(B, R, 1.0, 14)
    at = lambda u, dy=0: (tl[0] + (tr[0] - tl[0]) * u, tl[1] + (tr[1] - tl[1]) * u + dy)  # noqa: E731
    cx, cy = at(0.18, 1)
    d.polygon([(cx - 5, cy), (cx, cy + 2), (cx + 5, cy - 1), (cx, cy - 3)], fill=RED[2])  # cloth
    d.line([(cx - 5, cy), (cx, cy + 2)], fill=RED[1])
    for k in range(3):  # coins
        x, y = at(0.38, 1)
        d.rectangle([x, y - k, x + 2, y - k], fill=GOLD[3 if k % 2 else 2])
    x0, y0 = at(0.5, 1)
    d.line([(x0, y0), (x0 + 9, y0 - 4)], fill=IRON[4])  # sword
    d.line([(x0 + 1, y0 + 1), (x0 + 10, y0 - 3)], fill=IRON[2])
    d.line([(x0 - 1, y0 - 2), (x0, y0 + 1)], fill=GOLD[2])
    sx, sy = at(0.86, 1)
    d.line([(sx, sy), (sx, sy - 8)], fill=WOOD[1])  # scale: post, beam, pans
    d.line([(sx - 5, sy - 7), (sx + 5, sy - 9)], fill=GOLD[1])
    d.rectangle([sx - 6, sy - 5, sx - 4, sy - 4], fill=GOLD[2])
    d.rectangle([sx + 4, sy - 7, sx + 6, sy - 6], fill=GOLD[2])
    finish(img, "interiors/forge/upg_counter.png")


def shelves():
    """Open shelving (forge_capacity_2) standing along the wall: a back of planks, a side panel, three boards with
    ingots, jars, a coil of rope and tools along the open front, posts at the front corners."""
    img = canvas()
    d = ImageDraw.Draw(img)
    a, b, h = 34, 9, 26
    g = box(d, AX, AY, a, b, 0, WOOD[3], WOOD[3], WOOD[3])
    L, B, R, K = g["L"], g["B"], g["R"], g["K"]
    d.polygon([L, K, (K[0], K[1] - h), (L[0], L[1] - h)], fill=WOOD[1])  # back, along the wall
    for k in range(1, 6):
        p = on_face(L, K, k / 6.0, 0)
        d.line([p, (p[0], p[1] - h)], fill=WOOD[0])
    items = [[IRON[3], IRON[4], IRON[3], IRON[4]], [EARTH[3], RED[2], EARTH[2], GOLD[2]], [GOLD[2], IRON[2], EARTH[3], RED[1]]]
    for k, lift in enumerate((1, 10, 19)):
        box(d, AX, AY, a, b, 2, WOOD[4], WOOD[3], WOOD[2], lift=lift)
        for j in range(4):  # things on the board, between the back and the front edge
            x, y = on_face(B, R, (j + 0.5) / 4.0, lift + 2)
            x -= 3
            y -= 2
            col = items[k][j]
            if k == 0:   # ingots: two stacked bars
                d.polygon([(x - 3, y), (x, y + 1), (x + 3, y - 1), (x, y - 2)], fill=col)
                d.polygon([(x - 3, y - 2), (x, y - 1), (x + 3, y - 3), (x, y - 4)], fill=IRON[5])
            elif k == 1:  # jars with lids
                d.rectangle([x - 1, y - 5, x + 1, y], fill=col)
                d.line([(x - 2, y - 6), (x + 2, y - 6)], fill=EARTH[1])
                d.point((x - 1, y - 4), fill=EARTH[4])
            else:        # a coil of rope, a hammer, a pouch, a book
                if j == 0:
                    d.ellipse([x - 3, y - 4, x + 2, y], outline=GOLD[1], fill=GOLD[2])
                elif j == 1:
                    d.line([(x - 2, y), (x + 2, y - 2)], fill=WOOD[3])
                    d.rectangle([x + 1, y - 4, x + 3, y - 2], fill=IRON[2])
                elif j == 2:
                    d.ellipse([x - 2, y - 4, x + 2, y], fill=EARTH[2])
                    d.point((x, y - 4), fill=EARTH[4])
                else:
                    d.rectangle([x - 1, y - 5, x + 1, y], fill=col)
                    d.line([(x + 1, y - 5), (x + 1, y)], fill=GOLD[2])
    d.polygon([L, B, (B[0], B[1] - h), (L[0], L[1] - h)], fill=WOOD[3])  # the near side panel
    d.line([(L[0] + 2, L[1] - 3), (B[0] - 2, B[1] - 3)], fill=WOOD[2])
    for p in (B, R):  # front posts
        d.rectangle([p[0] - 1, p[1] - h, p[0], p[1]], fill=WOOD[4])
    box(d, AX, AY, a + 2, b + 2, 2, WOOD[4], WOOD[3], WOOD[2], lift=h)  # the top board
    finish(img, "interiors/forge/upg_shelves.png")


def bellows():
    img = canvas()
    d = ImageDraw.Draw(img)
    box(d, AX, AY + 2, 26, 12, 3, WOOD[4], WOOD[3], WOOD[2])
    # the leather fold, then the tilted top board and the handles
    d.polygon([(AX - 14, AY - 3), (AX + 6, AY + 4), (AX + 16, AY - 4), (AX + 2, AY - 14)], fill=EARTH[1])
    d.polygon([(AX - 14, AY - 6), (AX + 5, AY - 0), (AX + 16, AY - 8), (AX - 2, AY - 16)], fill=WOOD[4])
    d.line([(AX - 14, AY - 6), (AX + 5, AY)], fill=WOOD[3])
    d.line([(AX + 14, AY - 9), (AX + 22, AY - 13)], fill=WOOD[2], width=2)
    d.polygon([(AX - 16, AY - 4), (AX - 24, AY - 8), (AX - 22, AY - 11), (AX - 14, AY - 7)], fill=IRON[2])  # nozzle
    finish(img, "interiors/forge/upg_bellows.png")


def cylinder(d, cx, cy, rx, ry, h, staves, band, top):
    for x in range(cx - rx, cx + rx + 1):
        t = (x - cx) / float(rx)
        yb = cy + ry * (1 - t * t) ** 0.5
        col = staves[(x - cx + rx) // 3 % 2] if x < cx + rx // 2 else staves[2]
        d.line([(x, yb - h), (x, yb)], fill=col)
        for k in (0.25, 0.75):
            d.point((x, yb - h * k), fill=band)
    d.ellipse([cx - rx, cy - h - ry, cx + rx, cy - h + ry], fill=staves[1])
    d.ellipse([cx - rx + 2, cy - h - ry + 1, cx + rx - 2, cy - h + ry - 1], fill=top)


def tub():
    img = canvas()
    d = ImageDraw.Draw(img)
    cylinder(d, AX, AY, 13, 6, 13, [WOOD[3], WOOD[4], WOOD[2]], IRON[1], WATER[2])
    d.line([(AX - 6, AY - 14), (AX + 2, AY - 16)], fill=WATER[4])
    finish(img, "interiors/forge/upg_tub.png")


def trough():
    img = canvas()
    d = ImageDraw.Draw(img)
    g = box(d, AX, AY, 44, 14, 10, STONE[4], STONE[3], STONE[2])
    t = g["top"]
    inner = [(t[0][0] + 3, t[0][1]), (t[1][0], t[1][1] - 2), (t[2][0] - 3, t[2][1]), (t[3][0], t[3][1] + 2)]
    d.polygon(inner, fill=WATER[2])
    d.line([inner[0], inner[1]], fill=STONE[1])
    d.line([(AX - 4, AY - 12), (AX + 8, AY - 18)], fill=WATER[4])
    finish(img, "interiors/forge/upg_trough.png")


def table_with(things, a=32, b=14, h=13, rel=""):
    img = canvas()
    d = ImageDraw.Draw(img)
    legs(d, AX, AY, a, b, h, WOOD[1])
    box(d, AX, AY, a, b, 3, WOOD[4], WOOD[3], WOOD[2], lift=h)
    things(d)
    finish(img, rel)


def engraving(d):
    d.line([(AX - 10, AY - 18), (AX - 4, AY - 21)], fill=IRON[4])   # chisels
    d.line([(AX - 8, AY - 16), (AX - 2, AY - 19)], fill=IRON[3])
    d.rectangle([AX + 4, AY - 22, AX + 9, AY - 19], fill=IRON[2])  # a plate being engraved
    d.point((AX + 6, AY - 21), fill=GOLD[3])
    d.line([(AX + 12, AY - 23), (AX + 16, AY - 25)], fill=WOOD[2])  # a mallet
    d.rectangle([AX + 15, AY - 27, AX + 18, AY - 25], fill=WOOD[3])


def ledger(d):
    d.polygon([(AX - 9, AY - 20), (AX + 1, AY - 16), (AX + 9, AY - 21), (AX - 1, AY - 25)], fill=RED[1])  # cover
    d.polygon([(AX - 8, AY - 21), (AX, AY - 18), (AX, AY - 23), (AX - 7, AY - 26)], fill=(236, 222, 186, 255))
    d.polygon([(AX, AY - 18), (AX + 8, AY - 22), (AX + 7, AY - 27), (AX, AY - 23)], fill=(222, 206, 170, 255))
    for k in range(3):
        d.line([(AX - 6, AY - 24 + k * 1.5), (AX - 2, AY - 22 + k * 1.5)], fill=EARTH[2])
        d.line([(AX + 2, AY - 23 + k * 1.5), (AX + 6, AY - 25 + k * 1.5)], fill=EARTH[2])
    d.rectangle([AX + 11, AY - 24, AX + 13, AY - 21], fill=OUTLINE)  # inkwell
    d.line([(AX + 12, AY - 25), (AX + 15, AY - 31)], fill=(236, 236, 230, 255))  # quill


def seal():
    img = canvas()
    d = ImageDraw.Draw(img)
    box(d, AX, AY, 14, 14, 16, STONE[4], STONE[3], STONE[2])
    d.ellipse([AX - 6, AY - 30, AX + 6, AY - 20], fill=GOLD[2])
    d.ellipse([AX - 4, AY - 28, AX + 4, AY - 22], fill=GOLD[3])
    d.point((AX, AY - 25), fill=GOLD[1])
    d.polygon([(AX - 2, AY - 21), (AX - 5, AY - 14), (AX - 2, AY - 16)], fill=RED[2])  # ribbon
    d.polygon([(AX + 2, AY - 21), (AX + 5, AY - 14), (AX + 2, AY - 16)], fill=RED[1])
    finish(img, "interiors/forge/upg_seal.png")


def place(img, sprite, foot):
    """Pastes `sprite` so its point `foot` lands on the canvas anchor."""
    img.alpha_composite(sprite, (AX - foot[0], AY - foot[1]))


def from_guild(guild):
    def put(rel_src, foot, rel_out, shrink=False):
        img = canvas()
        sp = src(guild, rel_src)
        if shrink:
            sp = half(sp)
        place(img, sp, foot(sp))
        save(img, rel_out)
    bottom = lambda sp: (sp.width // 2, sp.getbbox()[3] - 8)  # noqa: E731
    put("buildings/forge/interior/workzone_horno_sw.png", lambda sp: (32, 50), "interiors/forge/upg_master_furnace.png")
    put("props/hidden_passage.png", lambda sp: (sp.width // 2 + 6, sp.getbbox()[3] - 2), "interiors/forge/upg_passage.png", True)
    put("props/safe_box.png", bottom, "interiors/forge/upg_strongbox.png", True)
    put("props/dormitory_bed.png", lambda sp: (32, 34), "interiors/forge/upg_bunks.png")
    put("props/dining_table.png", lambda sp: (40, 44), "interiors/forge/upg_dining.png")
    put("props/anvil.png", lambda sp: (32, 50), "interiors/forge/upg_master_bench.png")
    # the smugglers' cache: crates and a sack from the town's props (already at our scale)
    art = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "art")
    img = canvas()
    crate = Image.open(os.path.join(art, "props", "crate.png")).convert("RGBA")
    sack = Image.open(os.path.join(art, "props", "grain_sack.png")).convert("RGBA")
    barrel = Image.open(os.path.join(art, "props", "barrel.png")).convert("RGBA")
    for sp, (x, y) in ((crate, (AX - 16, AY - 26)), (barrel, (AX + 2, AY - 30)), (crate, (AX - 6, AY - 20)),
                       (sack, (AX + 6, AY - 18))):
        img.alpha_composite(sp, (x, y))
    save(img, "interiors/forge/upg_cache.png")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--guild", default=os.path.expanduser("~/Code/guild"))
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    sales_counter()
    shelves()
    bellows()
    tub()
    trough()
    table_with(engraving, rel="interiors/forge/upg_engraving.png")
    table_with(ledger, a=26, b=14, rel="interiors/forge/upg_ledger.png")
    seal()
    from_guild(a.guild)
    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        art = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "art")
        cols = 6
        sheet = Image.new("RGBA", (cols * W * 3, ((len(OUT) + cols - 1) // cols) * H * 3), (110, 100, 88, 255))
        for n, rel in enumerate(OUT):
            im = Image.open(os.path.join(art, rel)).convert("RGBA")
            dd = ImageDraw.Draw(im)
            dd.point((AX, AY), fill=(255, 0, 255, 255))
            sheet.alpha_composite(im.resize((W * 3, H * 3), Image.NEAREST), ((n % cols) * W * 3, (n // cols) * H * 3))
        p = os.path.join(a.preview, "mejoras.png")
        sheet.save(p)
        print("preview", p)


if __name__ == "__main__":
    main()
