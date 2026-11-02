#!/usr/bin/env python3
"""Pixel art drawn by code with Pillow (docs/arte/reuso_guild.md, third batch): no credits spent, style bible palette
(warm earth tones, forest green, stone grey, sky blue), single dark outline, light from the top left, 2:1.

  python3 tools/art/dibujar_pixel.py [--guild ~/Code/guild] [--only interior,nature,works,icons] [--preview DIR]

  interior  interiors/<b>/floor.png (64×32) from guild's stone_floor_flat (1:1 diamonds squashed to 2:1), and
            interiors/<b>/wall_<ne|nw>.png, wall_door_<ne|nw>.png (32×52: one wall segment, 36 px high) for the forge
            (stone) and the armory (plaster and timber)
  nature    props/tree_oak.png, tree_round.png, tree_pine.png, tiles/tree.png (grass with the canopy's shadow);
            tiles/water.png + water_edge_<ne|nw|se|sw>.png (the
            bank, drawn where the river meets another kind); tiles/bridge.png + bridge_edge_<..>.png (the curb on the
            sides that face the water)
  works     buildings/forge_works.png (scaffold over the forge), buildings/forge_plinth.png and forge_plinth_noble.png
            (stone base of the facade upgrades), props/banner.png, and half-size overlays from guild: trade_sign,
            garden, lock, shop_window
  icons     icons/small/sword.png and needle.png redrawn by hand at 16×16
Every output is deterministic (same code, same pixels). --preview DIR writes enlarged contact sheets to look at.
"""
import argparse
import math
import os
import sys

from PIL import Image

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from derivar_guild import half, remap, src  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "assets", "art")
OUT = []


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


OUTLINE = hexc("1e1812")
STONE = [hexc(c) for c in ("4a423b", "5f564d", "776b5e", "8e8172", "a79886", "bfb19c")]
WOOD = [hexc(c) for c in ("2e1d10", "4a2f19", "5c3a1e", "7a5230", "96683c", "b07e4a")]
PLASTER = [hexc(c) for c in ("a8916e", "bca684", "cdb894", "dac8a6")]
LEAF = [hexc(c) for c in ("1c3418", "2a4d22", "3a6a2c", "4f8a36", "6aa640", "8cc152")]
PINE = [hexc(c) for c in ("15291a", "1f3d24", "2c5530", "3b6e3a", "52894a")]
WATER = [hexc(c) for c in ("27466a", "2f5684", "386897", "4579a8", "6497c2", "9cc4de")]
EARTH = [hexc(c) for c in ("3e2c1a", "5a4128", "7a5a36", "9a7a4e", "b89a68")]
RED = [hexc(c) for c in ("4a1414", "6b1f1f", "8b2e2e", "a84040")]
GOLD = [hexc(c) for c in ("7a5e20", "a8853a", "c8a84e", "e0c870")]
IRON = [hexc(c) for c in ("2a2a30", "4a4a52", "6e6e78", "9a9aa4", "c8c8d0", "eeeef2")]


def h32(*v):
    """A well-mixed deterministic number from integers."""
    x = 2166136261
    for n in v:
        x = ((x ^ (n & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
        x ^= x >> 13
    return x


def save(img, rel):
    p = os.path.join(ART, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    OUT.append(rel)
    print(f"  {rel} {img.size[0]}×{img.size[1]}")


def outline(img, color=OUTLINE):
    """A one-pixel dark outline around the opaque shape (4-neighbours), inside the canvas."""
    w, h = img.size
    px = img.load()
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 0 and px[nx, ny] != color:
                        edge.append((x, y))
                        break
    for x, y in edge:
        px[x, y] = color
    return img


def mirror_light(img, k):
    out = img.transpose(Image.FLIP_LEFT_RIGHT)
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)), a)
    return out


# --- interior ----------------------------------------------------------------------------------------------------------

WALL_H = 36


def squash(im):
    """A 1:1 diamond squashed to 2:1 (keeps the first opaque pixel of each pair of rows)."""
    w, h = im.size
    out = Image.new("RGBA", (w, h // 2), (0, 0, 0, 0))
    s, o = im.load(), out.load()
    for y in range(h // 2):
        for x in range(w):
            a, b = s[x, 2 * y], s[x, 2 * y + 1]
            c = a if a[3] >= 128 else b
            o[x, y] = c if c[3] >= 128 else (0, 0, 0, 0)
    return out


def wall_segment(style, door=False):
    """One back-right ("ne") wall segment seen from inside: 32 px along the wall, WALL_H high, top edge from (0,0) to
    (32,16). Stone courses (forge) or plaster with timber (armory); a cap beam on top."""
    w, h = 32, 16 + WALL_H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for x in range(w):
        top = x // 2
        for y in range(top, top + WALL_H):
            v = y - top  # 0 at the top of the wall, WALL_H-1 at the floor
            u = x
            if v == 0:
                c = OUTLINE
            elif v <= 3:
                c = WOOD[3] if v == 1 else WOOD[2] if v == 2 else WOOD[1]
            elif v >= WALL_H - 2:
                c = WOOD[1] if style == "plaster" else STONE[0]
            elif style == "stone":
                course, length = 6, 16
                row = (v - 4) // course
                off = 8 if row % 2 else 0
                vb = (v - 4) % course
                ub = (u + off) % length
                if vb == course - 1 or ub == length - 1:
                    c = STONE[0]
                else:
                    base = 2 + h32(row, (u + off) // length, 7) % 3
                    if vb == 0 or ub == 0:
                        base = min(base + 1, 5)
                    elif vb == course - 2:
                        base = max(base - 1, 1)
                    if base == 2 + 1 and h32(x, y, 3) % 11 == 0:
                        base -= 1
                    c = STONE[base]
            else:  # plaster and timber
                if v in (18, 19):
                    c = WOOD[2] if v == 18 else WOOD[1]
                elif u <= 2:
                    c = WOOD[3] if u == 1 else WOOD[2] if u == 2 else WOOD[1]
                else:
                    k = 2 if h32(x, y, 5) % 9 else (1 if h32(x, y, 6) % 2 else 3)
                    if v in (4, 20):
                        k = 1  # shadow under the beams
                    c = PLASTER[k]
            px[x, y] = c
    if door:
        for x in range(8, 25):
            top = x // 2
            for y in range(top + 9, top + WALL_H - 2):
                v = y - top
                frame = x in (8, 24) or v == 9
                if frame:
                    px[x, y] = OUTLINE
                elif x in (9, 23) or v == 10:
                    px[x, y] = WOOD[1]
                else:
                    plank = (x - 10) // 3
                    shade = 3 if plank % 2 else 2
                    if (x - 10) % 3 == 2:
                        shade = 1
                    px[x, y] = WOOD[shade]
        for x, vv in ((11, 15), (12, 15), (13, 15), (11, 28), (12, 28), (13, 28), (21, 21)):
            px[x, x // 2 + vv] = IRON[2] if x != 21 else GOLD[2]
    return img


def interior(guild):
    floors = {
        "forge": (squash(src(guild, "tiles/stone_floor_flat/tile_4.png")), None),
        "armory": (squash(src(guild, "tiles/stone_floor_flat/tile_11.png")), lambda h, s, v: (34.0, s * 0.45 + 0.04, v * 0.98)),
    }
    for b, (im, fn) in floors.items():
        save(remap(im, fn) if fn else im, f"interiors/{b}/floor.png")
    for b, style in (("forge", "stone"), ("armory", "plaster")):
        ne = wall_segment(style)
        dne = wall_segment(style, door=True)
        save(ne, f"interiors/{b}/wall_ne.png")
        save(mirror_light(ne, 1.08), f"interiors/{b}/wall_nw.png")
        save(dne, f"interiors/{b}/wall_door_ne.png")
        save(mirror_light(dne, 1.08), f"interiors/{b}/wall_door_nw.png")


# --- nature ------------------------------------------------------------------------------------------------------------

def blob_tree(w, h, blobs, trunk, palette, seed):
    """A canopy made of circles, shaded by the light from the top left (4 tones + highlight), with a trunk."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    tx, ty0, ty1, tw = trunk
    for y in range(ty0, ty1):
        for x in range(tx - tw // 2, tx - tw // 2 + tw):
            k = 3 if x == tx - tw // 2 else 1 if x == tx - tw // 2 + tw - 1 else 2
            px[x, y] = WOOD[k]
    cx0 = sum(b[0] for b in blobs) / len(blobs)
    cy0 = sum(b[1] for b in blobs) / len(blobs)
    for y in range(h):
        for x in range(w):
            inside = None
            for bx, by, r in blobs:
                d = math.hypot(x + 0.5 - bx, y + 0.5 - by)
                if d <= r:
                    # light: how far towards the top left of its own blob, and of the whole canopy
                    lx = ((bx - x) + (by - y)) / (r * 1.6) + ((cx0 - x) + (cy0 - y)) / 60.0
                    inside = max(inside if inside is not None else -9, lx - d / (r * 3.0))
            if inside is None:
                continue
            n = (h32(x, y, seed) % 100) / 100.0 - 0.5
            t = inside + n * 0.35
            k = 1 if t < -0.25 else 2 if t < 0.15 else 3 if t < 0.5 else 4
            if t > 0.8 and h32(x, y, seed + 1) % 3 == 0:
                k = 5
            px[x, y] = palette[k]
    return outline(img)


def pine_tree(w, h, seed):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    cx = w // 2
    for y in range(40, h - 1):
        for x in range(cx - 2, cx + 2):
            px[x, y] = WOOD[3] if x == cx - 2 else WOOD[2] if x < cx + 1 else WOOD[1]
    tiers = [(4, 18, 9), (12, 30, 13), (22, 44, 16)]  # (top y, bottom y, half width at the bottom)
    for top, bot, hw in tiers:
        for y in range(top, bot):
            f = (y - top) / max(1, bot - top - 1)
            half_w = 1 + f * hw
            for x in range(w):
                dx = x + 0.5 - cx
                if abs(dx) <= half_w:
                    edge = (abs(dx) / half_w)
                    t = (-dx / half_w) * 0.6 + (1 - f) * 0.3 - (0.25 if y > bot - 3 else 0)
                    t += ((h32(x, y, seed) % 100) / 100.0 - 0.5) * 0.3
                    k = 0 if t < -0.45 else 1 if t < -0.05 else 2 if t < 0.3 else 3
                    if edge < 0.4 and t > 0.45 and h32(x, y, seed + 2) % 3 == 0:
                        k = 4
                    px[x, y] = PINE[k]
    return outline(img)


def water_tile(seed):
    img = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    px = img.load()
    for y in range(32):
        for x in range(64):
            if abs(x + 0.5 - 32) / 2 + abs(y + 0.5 - 16) <= 16:
                k = 2 if (h32(x, y, seed) % 7) else 1
                px[x, y] = WATER[k]
    # wave dashes along the flow (the river runs along the rows: screen direction (-2, 1))
    for i in range(14):
        x0 = 6 + h32(i, seed) % 52
        y0 = 4 + h32(i, seed, 9) % 24
        ln = 3 + h32(i, 3) % 4
        for j in range(ln):
            for dx, col in ((0, WATER[4]), (1, WATER[3])):
                x, y = x0 - 2 * j + dx, y0 + j
                if 0 <= x < 64 and 0 <= y < 32 and abs(x + 0.5 - 32) / 2 + abs(y + 0.5 - 16) <= 14.5:
                    px[x, y] = col
        if h32(i, 77) % 4 == 0:
            x, y = x0 + 1, y0 - 1
            if abs(x + 0.5 - 32) / 2 + abs(y + 0.5 - 16) <= 14:
                px[x, y] = WATER[5]
    return img


EDGES = {  # outward normal of each edge of the 64×32 diamond, as the neighbour's tile offset (col, row)
    "ne": (0, -1), "se": (1, 0), "sw": (0, 1), "nw": (-1, 0),
}


def edge_dist(x, y, side):
    """Distance (px, about) from (x, y) to the given edge of the diamond, inside it."""
    cx, cy = x + 0.5 - 32, y + 0.5 - 16
    if side == "ne":
        return (16 - (cx / 2 - cy)) if cx >= -0.5 and cy <= 0.5 else 99
    if side == "se":
        return (16 - (cx / 2 + cy)) if cx >= -0.5 and cy >= -0.5 else 99
    if side == "sw":
        return (16 - (-cx / 2 + cy)) if cx <= 0.5 and cy >= -0.5 else 99
    return (16 - (-cx / 2 - cy)) if cx <= 0.5 and cy <= 0.5 else 99


def edge_overlay(side, bands, seed, ragged=True):
    """A strip along one edge of the diamond: bands = [(max distance, palette list)], from the edge inwards."""
    img = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    px = img.load()
    for y in range(32):
        for x in range(64):
            if abs(x + 0.5 - 32) / 2 + abs(y + 0.5 - 16) > 16:
                continue
            d = edge_dist(x, y, side)
            j = (h32(x, y, seed) % 3) * 0.5 if ragged else 0
            prev = 0
            for lim, pal in bands:
                if prev <= d < lim + j:
                    px[x, y] = pal[h32(x, y, seed + 1) % len(pal)]
                    break
                prev = lim + j
    return img


def bridge_tile(seed):
    img = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    px = img.load()
    for y in range(32):
        for x in range(64):
            if abs(x + 0.5 - 32) / 2 + abs(y + 0.5 - 16) > 16:
                continue
            # planks run across the street (along the rows: screen direction (-2, 1)); count them along the columns
            s = (x / 2 + y)  # constant along a plank
            plank = int(s // 4)
            pos = s % 4
            if pos < 0.5:
                c = WOOD[1]
            else:
                c = WOOD[3] if plank % 2 else WOOD[4]
                if h32(x, y, seed) % 13 == 0:
                    c = WOOD[2]
            px[x, y] = c
    return img


def tree_ground():
    """The grass tile with the canopy's shadow (dithered, darker, no alpha blending) under the tree tiles."""
    img = Image.open(os.path.join(ART, "tiles", "grass.png")).convert("RGBA")
    px = img.load()
    for y in range(32):
        for x in range(64):
            r, g, b, a = px[x, y]
            if not a:
                continue
            e = ((x + 0.5 - 30) / 17.0) ** 2 + ((y + 0.5 - 17) / 7.0) ** 2
            if e < 1.0 and (e < 0.6 or (x + y) % 2 == 0):
                px[x, y] = (int(r * 0.72), int(g * 0.76), int(b * 0.72), a)
    return img


def nature(_guild):
    save(blob_tree(46, 58, [(23, 20, 15), (13, 28, 10), (33, 28, 11), (22, 33, 11), (28, 13, 9)],
                   (23, 34, 56, 5), LEAF, 11), "props/tree_oak.png")
    save(blob_tree(36, 52, [(18, 18, 12), (12, 26, 8), (25, 25, 8), (18, 28, 9)],
                   (18, 30, 50, 4), [LEAF[0], LEAF[1], LEAF[2], LEAF[3], LEAF[4], LEAF[5]], 23), "props/tree_round.png")
    save(pine_tree(34, 56, 37), "props/tree_pine.png")
    save(tree_ground(), "tiles/tree.png")
    save(water_tile(5), "tiles/water.png")
    bank = [(1.5, [EARTH[1]]), (3.0, [EARTH[2], EARTH[3]]), (4.2, [WATER[5], WATER[4]])]
    for side in EDGES:
        save(edge_overlay(side, bank, 40 + len(side) + ord(side[0])), f"tiles/water_edge_{side}.png")
    save(bridge_tile(9), "tiles/bridge.png")
    curb = [(1.0, [OUTLINE]), (3.0, [WOOD[1], WOOD[2]]), (4.0, [WOOD[3]])]
    for side in EDGES:
        save(edge_overlay(side, curb, 70, ragged=False), f"tiles/bridge_edge_{side}.png")


# --- works and facades -------------------------------------------------------------------------------------------------

def thick_line(px, w, h, p0, p1, color, width=1):
    n = int(max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1]))) + 1
    for i in range(n):
        t = i / max(1, n - 1)
        x = round(p0[0] + (p1[0] - p0[0]) * t)
        y = round(p0[1] + (p1[1] - p0[1]) * t)
        for k in range(width):
            if 0 <= x < w and 0 <= y + k < h:
                px[x, y + k] = color


def scaffold(base_l, base_r, height, ox, oy, w, h):
    """Poles and planks along two front edges of a footprint. base_l / base_r: the left and right ends of the front
    edges relative to the front corner (0, 0); (ox, oy) = where (0, 0) falls in the image."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    poles = [base_l, ((base_l[0]) / 2, base_l[1] / 2), (0, 0), (base_r[0] / 2, base_r[1] / 2), base_r]
    for bx, by in poles:
        x, y0 = round(ox + bx), round(oy + by)
        for y in range(y0 - height, y0 + 1):
            for dx, c in ((-1, OUTLINE), (0, WOOD[4]), (1, WOOD[2]), (2, OUTLINE)):
                if 0 <= x + dx < w and 0 <= y < h:
                    px[x + dx, y] = c
    for lift in (height * 0.38, height * 0.72):
        for a, b in ((base_l, (0, 0)), ((0, 0), base_r)):
            p0 = (ox + a[0], oy + a[1] - lift)
            p1 = (ox + b[0], oy + b[1] - lift)
            thick_line(px, w, h, (p0[0], p0[1] - 1), (p1[0], p1[1] - 1), OUTLINE)
            thick_line(px, w, h, p0, p1, WOOD[4])
            thick_line(px, w, h, (p0[0], p0[1] + 1), (p1[0], p1[1] + 1), WOOD[3])
            thick_line(px, w, h, (p0[0], p0[1] + 2), (p1[0], p1[1] + 2), OUTLINE)
    for a, b in ((base_l, (0, 0)), ((0, 0), base_r)):  # cross braces
        p0 = (ox + a[0], oy + a[1] - height * 0.38)
        p1 = (ox + b[0], oy + b[1] - height * 0.72)
        thick_line(px, w, h, p0, p1, WOOD[2])
    for i in range(0, int(height * 0.72), 4):  # a ladder at the front corner
        y = round(oy - i)
        for x in range(round(ox) + 4, round(ox) + 10):
            if 0 <= x < w and 0 <= y < h:
                px[x, y] = WOOD[3]
    for y in range(round(oy - height * 0.72), round(oy) + 1):
        for x in (round(ox) + 4, round(ox) + 9):
            if 0 <= y < h:
                px[x, y] = WOOD[1]
    return img


def plinth(base_l, base_r, height, ox, oy, w, h, light=False):
    """A low stone base along the two front edges (left face darker, right face lighter), with a cap."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    pal = STONE if not light else [hexc(c) for c in ("5c564e", "7e7468", "9e9282", "bcb09c", "d2c8b4", "e6ddca")]
    for face, (a, b) in (("l", (base_l, (0, 0))), ("r", ((0, 0), base_r))):
        x0, x1 = sorted((round(ox + a[0]), round(ox + b[0])))
        for x in range(x0, x1 + 1):
            t = (x - (ox + a[0])) / ((b[0] - a[0]) or 1)
            yb = round(oy + a[1] + (b[1] - a[1]) * t)
            for v in range(height):
                y = yb - v
                if not (0 <= y < h):
                    continue
                u = x - x0
                if v == height - 1:
                    c = OUTLINE
                elif v == height - 2:
                    c = pal[5] if face == "r" else pal[4]
                elif v == 0:
                    c = OUTLINE
                else:
                    row = (v - 1) // 4
                    off = 5 if row % 2 else 0
                    if (v - 1) % 4 == 3 or (u + off) % 10 == 9:
                        c = pal[0]
                    else:
                        k = 2 + h32(row, (u + off) // 10, 1 if face == "l" else 2) % 2
                        c = pal[k + (1 if face == "r" else 0)]
                px[x, y] = c
    return img


def banner(seed=0):
    w, h = 10, 34
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(0, h):
        px[1, y] = WOOD[3]
        px[2, y] = WOOD[1]
    for x in range(1, 9):
        px[x, 1] = WOOD[2]
    for y in range(2, 22):
        for x in range(3, 9):
            tail = y > 17 and abs(x - 5.5) < (y - 17) * 0.8
            if tail:
                continue
            c = RED[2] if x < 7 else RED[1]
            if x in (3,) or y == 2:
                c = GOLD[2]
            if 8 <= y <= 11 and 4 <= x <= 7:
                c = GOLD[3] if (x + y) % 3 else GOLD[1]
            px[x, y] = c
    for y in range(h - 2, h):
        for x in range(0, 4):
            px[x, y] = STONE[2]
    return outline(img)


FORGE_SPRITE_BASE = 92  # half the width of the base of buildings/forge.png (anchor (96, 139), base 184 px)


def works(guild):
    # the footprint's front edges, relative to its front corner: 3 tiles along the columns (left), 4 along the rows (right)
    # the scaffold hugs the sprite's base too (front corner 47 px under the anchor), not the wider footprint
    save(scaffold((-90, -45), (90, -45), 104, 94, 166, 190, 172), "buildings/forge_works.png")
    # the facade plinth hugs the base of the sprite (184 px wide, front corner 47 px under the anchor)
    bl, br = (-FORGE_SPRITE_BASE + 2, -45), (FORGE_SPRITE_BASE - 2, -45)
    save(plinth(bl, br, 9, 92, 50, 186, 54), "buildings/forge_plinth.png")
    save(plinth(bl, br, 11, 92, 50, 186, 54, light=True), "buildings/forge_plinth_noble.png")
    save(banner(), "props/banner.png")
    save(half(src(guild, "buildings/overlays/shop_sign.png")), "props/trade_sign.png")
    save(half(src(guild, "buildings/overlays/garden_plants.png")), "props/garden.png")
    save(half(src(guild, "buildings/overlays/lock_reinforced.png")), "props/lock.png")
    save(half(src(guild, "buildings/market/interior/stall_armeria.png")), "props/shop_window.png")


# --- icons -------------------------------------------------------------------------------------------------------------

SWORD = [
    "...............o",
    "..............ow",
    ".............owl",
    "............owl.",
    "...........owl..",
    "..........owl...",
    ".........owl....",
    "........owl.....",
    "..g....owl......",
    "..gg..owl.......",
    "...gGowl........",
    "....gGl.........",
    "...bbgGG........",
    "..bbo.gg........",
    ".bbo....g.......",
    "oo..............",
]
NEEDLE = [
    "...........ooo..",
    "..........owWo..",
    "..........o.lo..",
    ".........owlo...",
    "........owlo....",
    ".......owlo.....",
    "......owlo......",
    ".....owlo.......",
    "....owlo....r...",
    "...owlo....rR...",
    "..owlo.....r....",
    "..olo....rr.....",
    ".olo...rr.......",
    ".oo..rrR........",
    "..rrrR..........",
    "................",
]


def draw_icon(rows, palette):
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in palette:
                px[x, y] = palette[ch]
    return img


def icons(_guild):
    save(draw_icon(SWORD, {"o": OUTLINE, "w": IRON[5], "l": IRON[3], "g": GOLD[2], "G": GOLD[1], "b": WOOD[3]}),
         "icons/small/sword.png")
    save(draw_icon(NEEDLE, {"o": OUTLINE, "w": IRON[5], "W": IRON[4], "l": IRON[3], "r": RED[2], "R": RED[3]}),
         "icons/small/needle.png")


# --- preview -----------------------------------------------------------------------------------------------------------

def preview(folder):
    os.makedirs(folder, exist_ok=True)
    ims = [(r, Image.open(os.path.join(ART, r)).convert("RGBA")) for r in OUT]
    scale = 3
    cell = max(max(i.size) for _, i in ims) * scale + 6
    cols = max(1, 1800 // cell)
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (96, 104, 92, 255))
    for n, (_, im) in enumerate(ims):
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        sheet.alpha_composite(im, ((n % cols) * cell + 3, (n // cols) * cell + 3))
    p = os.path.join(folder, "dibujar_pixel.png")
    sheet.save(p)
    print("preview", p)


JOBS = {"interior": interior, "nature": nature, "works": works, "icons": icons}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--guild", default=os.path.expanduser("~/Code/guild"))
    ap.add_argument("--only", default=",".join(JOBS))
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    for job in a.only.split(","):
        print(job)
        JOBS[job](a.guild)
    if a.preview:
        preview(a.preview)


if __name__ == "__main__":
    main()
