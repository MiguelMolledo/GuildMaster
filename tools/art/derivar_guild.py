#!/usr/bin/env python3
"""Derived art from the Guild Renew sprites (docs/arte/reuso_guild.md): local edits with Pillow, no credits spent.

  python3 tools/art/derivar_guild.py [--guild ~/Code/guild] [--only tiles,props,board,icons]

Reads the originals from the guild repo (read only) and writes copies into assets/art/:
  tiles   street.png / plaza.png  cobblestone recoloured towards the warm stone grey of the style bible
          dirt.png                dirt recoloured from pink to brown, with the dark rim that drew the grid softened
          building.png            yard ground under the town's filler lots (grass with trodden dirt)
  props   barrel, crate, grain_sack, cart, bench, well at half size (the originals were drawn for 68 px people;
          ours are 48 px), with a pixel-art-aware 2:1 reduction (keeps the black outline, no new colours);
          furrows.png             a ploughed tile for the vegetable plots
  board   board.png               the contract board: the frame of the shop sign on two posts, with pinned notes
  icons   icons/small/<id>.png    16×16 versions of the 32×32 item icons for the UI lists (10 px font)
  houses  buildings/house_e.png, house_f.png  recoloured copies of house_a / house_c (slate + whitewash, clay + ochre)
Re-running overwrites the outputs. Never writes into the guild repo.
"""
import argparse
import colorsys
import os
import sys

from PIL import Image

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "assets", "art")


def src(guild, rel):
    return Image.open(os.path.join(guild, "assets", "sprites", rel)).convert("RGBA")


def save(img, rel):
    p = os.path.join(ART, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    print(f"  {rel} {img.size[0]}×{img.size[1]}")


# --- colour -----------------------------------------------------------------------------------------------------------

def remap(img, fn):
    """fn(h, s, v) -> (h, s, v) on every opaque pixel (h in degrees)."""
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            h, s, v = fn(h * 360.0, s, v)
            r2, g2, b2 = colorsys.hsv_to_rgb((h % 360.0) / 360.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
            px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
    return out


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


# --- 2:1 reduction for pixel art ---------------------------------------------------------------------------------------

def half(img):
    """Halves a sprite keeping it crisp: a 2×2 block is opaque if at least two of its pixels are; on the silhouette's
    edge it takes the darkest pixel (the outline survives), inside it takes the most common colour (ties: darker).
    Only colours of the original are used."""
    w, h = img.width // 2, img.height // 2
    src_px = img.load()
    alpha = [[False] * w for _ in range(h)]
    blocks = [[None] * w for _ in range(h)]
    for by in range(h):
        for bx in range(w):
            cols = [src_px[bx * 2 + dx, by * 2 + dy] for dy in (0, 1) for dx in (0, 1)]
            op = [c for c in cols if c[3] >= 128]
            blocks[by][bx] = op
            alpha[by][bx] = len(op) >= 2
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = out.load()
    for by in range(h):
        for bx in range(w):
            if not alpha[by][bx]:
                continue
            op = blocks[by][bx]
            edge = len(op) < 4 or any(
                not (0 <= bx + dx < w and 0 <= by + dy < h and alpha[by + dy][bx + dx])
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge:
                c = min(op, key=lum)
            else:
                count = {}
                for c in op:
                    k = c[:3]
                    count[k] = count.get(k, 0) + 1
                best = max(count.items(), key=lambda kv: (kv[1], -lum(kv[0])))[0]
                c = best + (255,)
            px[bx, by] = (c[0], c[1], c[2], 255)
    return out.crop(out.getbbox()) if out.getbbox() else out


def pad_to(img, w, h, anchor_bottom=True):
    """Centres `img` on a w×h canvas (bottom-aligned with 1 px margin when anchor_bottom)."""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = (w - img.width) // 2
    y = h - img.height - 1 if anchor_bottom else (h - img.height) // 2
    out.alpha_composite(img, (x, y))
    return out


# --- jobs -------------------------------------------------------------------------------------------------------------

def tiles(guild):
    cob = src(guild, "tiles/tile_cobblestone_diamond.png")
    # stone: blue grey (h≈205, s≈0.32) -> warm stone grey (h≈32, s≈0.14); mortar: blue black -> brown black
    save(remap(cob, lambda h, s, v: (32.0, s * 0.42, v * 1.04)), "tiles/street.png")
    save(remap(cob, lambda h, s, v: (38.0, s * 0.62, min(1.0, v * 1.14))), "tiles/plaza.png")
    dirt = src(guild, "tiles/diamonds/tile_dirt_block.png")
    dirt = remap(dirt, lambda h, s, v: (27.0, s * 1.05, v * 0.86))
    save(soften_rim(dirt), "tiles/dirt.png")
    save(src(guild, "tiles/test_tiles_pro_diamond/tile_12.png"), "tiles/building.png")


def soften_rim(img):
    """The dark cracks that run along the diamond's border draw a grid when tiles repeat: within 3 px of the border,
    a dark pixel takes the commonest light colour of the tile."""
    px = img.load()
    w, h = img.size
    count = {}
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if c[3] and lum(c) > 90:
                count[c] = count.get(c, 0) + 1
    base = max(count.items(), key=lambda kv: kv[1])[0]
    out = img.copy()
    opx = out.load()
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if not c[3] or lum(c) > 90:
                continue
            # distance to the diamond's border in pixels (|dx|/2 + |dy| = h/2 on the border)
            d = (h / 2.0) - (abs(x + 0.5 - w / 2.0) / 2.0 + abs(y + 0.5 - h / 2.0))
            if d < 3.0:
                opx[x, y] = base
    return out


HALF_PROPS = {
    "barrel": "props/barrel/barrel_64.png",
    "crate": "props/crate.png",
    "grain_sack": "props/grain_sack/grain_sack_48.png",
    "cart": "props/cart/cart_96.png",
    "bench": "props/bench/bench_64.png",
    "well": "props/well/well_96.png",
}


def props(guild):
    for pid, rel in HALF_PROPS.items():
        im = half(src(guild, rel))
        save(pad_to(im, im.width + 2, im.height + 2), f"props/{pid}.png")
    save(src(guild, "tiles/test_tiles_pro_diamond/tile_15.png"), "props/furrows.png")


def board(guild):
    sign = src(guild, "buildings/overlays/shop_sign.png")
    post = src(guild, "props/sign_post.png")
    frame = sign.crop((9, 17, 52, 61))           # the framed board, without the iron bracket
    frame = frame.crop(frame.getbbox())
    pole = post.crop((26, 18, 37, 48))            # a stretch of the signpost's pole
    pole = pole.crop(pole.getbbox())
    w = frame.width + 4
    h = frame.height + 16
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for x in (3, w - 3 - pole.width):             # two legs, from under the board to the ground
        leg = pole.resize((pole.width, h - 10), Image.NEAREST)
        out.alpha_composite(leg, (x, 10))
    out.alpha_composite(frame, (2, 0))
    d = out.load()
    ink, paper, paper2, seal = (43, 28, 20, 255), (236, 222, 186, 255), (214, 196, 156, 255), (160, 40, 36, 255)

    def note(x0, y0, nw, nh, with_seal=False):
        for y in range(y0, y0 + nh):
            for x in range(x0, x0 + nw):
                edge = x in (x0, x0 + nw - 1) or y in (y0, y0 + nh - 1)
                d[x, y] = ink if edge else (paper if (x + y) % 5 else paper2)
        for y in range(y0 + 2, y0 + nh - 2, 2):     # lines of writing
            for x in range(x0 + 2, x0 + nw - 2):
                if (x * 7 + y) % 4:
                    d[x, y] = (120, 100, 80, 255)
        d[x0 + nw // 2, y0] = (90, 90, 96, 255)     # the pin
        if with_seal:
            for sx, sy in ((1, 0), (0, 1), (1, 1), (2, 1), (1, 2)):
                d[x0 + nw - 4 + sx, y0 + nh - 5 + sy] = seal

    fx, fy = 2, 0
    note(fx + 7, fy + 8, 11, 13, True)
    note(fx + 21, fy + 7, 12, 10)
    note(fx + 22, fy + 20, 10, 11)
    note(fx + 9, fy + 24, 9, 9)
    save(out, "props/board.png")


ICONS = ["iron", "coal", "wood", "stone", "wheat", "wool", "herbs", "iron_ingot", "flour", "planks", "cloth", "sword",
         "bread", "common_clothes", "armor", "hammer", "needle", "hoe", "work_clothes", "travel_cloak", "bandages",
         "prepared_meal", "document", "key", "contract"]


def icons(_guild):
    for iid in ICONS:
        p = os.path.join(ART, "icons", f"{iid}.png")
        if not os.path.exists(p):
            continue
        im = half(Image.open(p).convert("RGBA"))
        save(pad_to(im, 16, 16, anchor_bottom=False) if im.width <= 16 and im.height <= 16 else im.resize((16, 16)),
             f"icons/small/{iid}.png")


def houses(_guild):
    """Two more filler houses by recolouring local copies (style bible: clay tiles and slate roofs, whitewash, ochre):
    house_e = house_a with a slate roof and whitewashed walls; house_f = house_c with brown clay tiles and ochre
    plaster."""
    def slate_whitewash(h, s, v):
        if s > 0.25 and (h >= 312 or h < 14):          # red clay roof -> blue grey slate
            return 214.0, s * 0.32, v * 0.92
        if 36 <= h < 60 and s > 0.2 and v > 0.55:        # yellow plaster -> whitewash
            return 40.0, s * 0.28, min(1.0, v * 1.06)
        return h, s, v

    def clay_ochre(h, s, v):
        if s > 0.2 and (h >= 318 or h < 8):             # crimson roof and trim -> brown clay
            return 20.0, s * 0.85, v * 0.95
        if 32 <= h < 60 and s > 0.12 and v > 0.6:        # pale plaster -> ochre
            return 38.0, min(1.0, s * 1.8 + 0.1), v * 0.97
        return h, s, v

    a = Image.open(os.path.join(ART, "buildings", "house_a.png")).convert("RGBA")
    c = Image.open(os.path.join(ART, "buildings", "house_c.png")).convert("RGBA")
    save(remap(a, slate_whitewash), "buildings/house_e.png")
    save(remap(c, clay_ochre), "buildings/house_f.png")


def dice_table(guild):
    """The plaza's dice table (H7 social point): guild's dining table at half size, with two dice and a cup on it."""
    t = half(src(guild, "props/dining_table.png"))
    t = pad_to(t, t.width + 2, t.height + 4)
    px = t.load()
    bb = t.getbbox()
    cx, cy = (bb[0] + bb[2]) // 2, bb[1] + (bb[3] - bb[1]) // 3
    white, dot, cup, rim = (236, 230, 214, 255), (30, 24, 18, 255), (110, 70, 40, 255), (70, 44, 26, 255)
    for (x0, y0) in ((cx - 5, cy), (cx - 1, cy + 2)):           # two dice
        for y in range(y0, y0 + 3):
            for x in range(x0, x0 + 3):
                px[x, y] = white
        px[x0 + 1, y0 + 1] = dot
    for y in range(cy - 3, cy + 2):                               # the cup
        for x in range(cx + 3, cx + 6):
            px[x, y] = cup if y > cy - 3 else rim
    save(t, "props/dice_table.png")


JOBS = {"tiles": tiles, "props": props, "board": board, "icons": icons, "houses": houses, "dice": dice_table}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--guild", default=os.path.expanduser("~/Code/guild"))
    ap.add_argument("--only", default=",".join(JOBS))
    a = ap.parse_args()
    for job in a.only.split(","):
        print(job)
        JOBS[job](a.guild)


if __name__ == "__main__":
    main()
