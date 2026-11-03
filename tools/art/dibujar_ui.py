#!/usr/bin/env python3
"""Pixel art pieces of the UI theme (game/ui/greybox_theme.tres), drawn with Pillow in the style bible's UI palette
(docs/style/biblia.md: wood #5c3a1e, rivets #8a8a7a, parchment #d4b896, dark section #2a1f14, gold fillet #c8a84e,
empty slot #1a1209). No credits spent.

  python3 tools/art/dibujar_ui.py [--preview DIR]

Writes assets/art/ui/theme/:
  panel.png          32×32 9-patch (margins 6): wooden frame with rivets and a gold fillet around the dark section
  button_<state>.png 12×12 9-patch (margins 3): normal, hover (gold edge), pressed (sunk), disabled (faded)
  field.png          12×12 9-patch (margins 3): sunken slot for text fields and spin boxes
  tooltip.png        12×12 9-patch (margins 3): parchment with a dark edge
  tab_<on|off>.png   12×12 9-patch (margins 3): tab of a tabbed panel; the active one opens into the panel below
  portrait_<normal|active|dim>.png 8×8 9-patch (margins 3): frame of a portrait (wood, gold when active, grey when not
                     controllable or dead)
  parchment.png      24×24 9-patch (margins 6): a document (contracts, decrees, the chronicle at the end)
  check_<off|on>.png 10×10: check box
  slider_track.png / slider_grabber.png, scroll_track.png / scroll_grabber.png: slider and scroll bar
  divider.png        16×3 9-patch (margins 3×1): a gold rule with a small diamond at each end
Writes assets/art/ui/marks/ (not 9-patch, drawn at 1×):
  badge_title_<common|citizen|patrician|baron|noble>.png 12×12: shields, one per social title (data/titles)
  badge_office_<mayor|councillor|judge|constable|collector|inspector>.png 12×12: the six offices (GDD 4.12.3)
  rank_<1|2|3>.png   8×8: chevrons of an employee's rank (apprentice, journeyman, master)
  seal.png           16×16: wax seal (signed, done, official)
Writes assets/art/ui/cursor/: cursor_arrow.png, cursor_hand.png, cursor_wait.png (hotspot at the top-left pixel).
PIECES (below) is the 9-patch margin of every piece (one number, or (x, y)): tools/ui/maqueta.py reads it, the theme
uses the same numbers.
The fonts are not drawn here: assets/art/ui/fonts/silkscreen_regular.ttf comes from Guild Renew (SIL OFL 1.1).
"""
import argparse
import os
import sys

from PIL import Image

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art", "ui", "theme")


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


EMPTY = hexc("1a1209")
DARK = hexc("2a1f14")
WOOD = hexc("5c3a1e")
WOOD_LIGHT = hexc("7a5230")
WOOD_DARK = hexc("3e2814")
RIVET = hexc("8a8a7a")
RIVET_LIGHT = hexc("c4c4b4")
GOLD = hexc("c8a84e")
GOLD_DARK = hexc("8a7032")
PARCHMENT = hexc("d4b896")
PARCHMENT_DARK = hexc("b89a72")


# 9-patch margin of every piece in assets/art/ui/theme/ (the same texture_margin_* as game/ui/greybox_theme.tres).
PIECES = {
    "panel": 6,
    "button_normal": 3, "button_hover": 3, "button_pressed": 3, "button_disabled": 3,
    "field": 3,
    "tooltip": 3,
    "tab_on": 3, "tab_off": 3,
    "portrait_normal": 3, "portrait_active": 3, "portrait_dim": 3,
    "parchment": 6,
    "slider_track": 3, "scroll_track": 3, "scroll_grabber": 3,
    "divider": (3, 1),
}
MARKS = os.path.join(ROOT, "assets", "art", "ui", "marks")
CURSOR = os.path.join(ROOT, "assets", "art", "ui", "cursor")


def h32(*v):
    x = 2166136261
    for n in v:
        x = ((x ^ (n & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
        x ^= x >> 13
    return x


def save(img, name, folder=None):
    folder = folder or OUT
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, name))
    print(f"  {os.path.relpath(os.path.join(folder, name), ROOT)} {img.size[0]}×{img.size[1]}")


INK = {
    ".": (0, 0, 0, 0), "k": EMPTY, "s": DARK, "w": WOOD, "l": WOOD_LIGHT, "d": WOOD_DARK, "g": GOLD, "G": GOLD_DARK,
    "y": hexc("f2d880"), "p": PARCHMENT, "P": PARCHMENT_DARK, "q": hexc("e8d4b0"), "r": RIVET, "R": RIVET_LIGHT,
    "x": hexc("9a2a22"), "X": hexc("6a1a14"), "z": hexc("c4503e"), "i": hexc("5a5a54"), "I": hexc("8a8a84"),
    "S": hexc("c8c8d0"), "c": hexc("ece4d2"), "b": hexc("3a3028"),
}


def bitmap(rows, ink=None):
    """A sprite from rows of characters (INK: one character per colour; "." transparent)."""
    ink = dict(INK, **(ink or {}))
    w = max(len(r) for r in rows)
    img = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px[x, y] = ink[ch]
    return img


def ring(x, y, w, h):
    """How deep (x, y) is from the image's edge (0 = outermost ring)."""
    return min(x, y, w - 1 - x, h - 1 - y)


def panel():
    w = h = 32
    img = Image.new("RGBA", (w, h), DARK)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = ring(x, y, w, h)
            top_left = (x <= y and x < w - 1 - y) or (y < x and y < h - 1 - x and y <= w - 1 - x)
            if d == 0:
                c = EMPTY
            elif d <= 3:   # wood: lit on the top/left, shaded on the bottom/right, with grain
                if d == 1:
                    c = WOOD_LIGHT if (y < h // 2 and x > y) or (x < w // 2 and y > x) else WOOD
                else:
                    c = WOOD
                if d == 3:
                    c = WOOD_DARK
                horizontal = d == y or d == h - 1 - y
                if d in (1, 2) and h32(x if horizontal else y, d, 7) % 5 == 0:
                    c = WOOD_DARK
                if (y == h - 1 - d or x == w - 1 - d) and d == 1:
                    c = WOOD_DARK
            elif d == 4:   # the gold fillet, darker on the bottom/right
                c = GOLD_DARK if (y == h - 1 - d or x == w - 1 - d) else GOLD
            elif d == 5:   # a thin shadow inside the fillet
                c = EMPTY
            else:
                c = DARK
            px[x, y] = c
    for cx, cy in ((1, 1), (w - 3, 1), (1, h - 3), (w - 3, h - 3)):   # rivets on the corners
        px[cx, cy] = RIVET_LIGHT
        px[cx + 1, cy] = RIVET
        px[cx, cy + 1] = RIVET
        px[cx + 1, cy + 1] = hexc("5a5a50")
    save(img, "panel.png")


def button(state):
    w = h = 12
    fill = {"normal": WOOD, "hover": WOOD_LIGHT, "pressed": WOOD_DARK, "disabled": hexc("3a3028")}[state]
    edge = {"normal": EMPTY, "hover": GOLD, "pressed": GOLD_DARK, "disabled": hexc("2a221c")}[state]
    img = Image.new("RGBA", (w, h), fill)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = ring(x, y, w, h)
            if d == 0:
                px[x, y] = edge
            elif d == 1 and state != "disabled":
                lit = y == 1 or x == 1
                if state == "pressed":
                    lit = not lit   # sunk: the shade on the top/left
                px[x, y] = hexc("9a6e44") if lit and state != "pressed" else (WOOD if lit else hexc("2e1d10"))
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):  # rounded by one pixel
        px[corner] = (0, 0, 0, 0)
    save(img, f"button_{state}.png")


def field():
    w = h = 12
    img = Image.new("RGBA", (w, h), EMPTY)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = ring(x, y, w, h)
            if d == 0:
                px[x, y] = WOOD_DARK if (y == 0 or x == 0) else WOOD_LIGHT
    save(img, "field.png")


def tooltip():
    w = h = 12
    img = Image.new("RGBA", (w, h), PARCHMENT)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = ring(x, y, w, h)
            if d == 0:
                px[x, y] = WOOD_DARK
            elif d == 1 and (y == h - 2 or x == w - 2):
                px[x, y] = PARCHMENT_DARK
    save(img, "tooltip.png")


def tab(on):
    """A tab: wooden top and sides, open at the bottom when active (it joins the panel's gold fillet)."""
    w = h = 12
    fill = WOOD if on else hexc("3a2716")
    img = Image.new("RGBA", (w, h), fill)
    px = img.load()
    for y in range(h):
        for x in range(w):
            top, side = y == 0, x in (0, w - 1)
            if top or side:
                px[x, y] = EMPTY
            elif y == 1 or x == 1:
                px[x, y] = (GOLD if on else WOOD) if y == 1 else (WOOD_LIGHT if on else WOOD)
            elif x == w - 2:
                px[x, y] = WOOD_DARK
            if y == h - 1 and not on and not side:
                px[x, y] = GOLD_DARK   # an inactive tab sits behind the panel's fillet
    for corner in ((0, 0), (w - 1, 0)):
        px[corner] = (0, 0, 0, 0)
    save(img, f"tab_{'on' if on else 'off'}.png")


def portrait_frame(kind):
    """Frame of a portrait: a 3 px ring; the art goes inside (the family colour is a tint the game adds on top)."""
    w = h = 8
    outer, mid, inner = {
        "normal": (EMPTY, WOOD, WOOD_DARK),
        "active": (EMPTY, GOLD, GOLD_DARK),
        "dim": (EMPTY, hexc("6a6258"), hexc("3a3530")),
    }[kind]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = ring(x, y, w, h)
            px[x, y] = (outer, mid, inner)[d] if d < 3 else (0, 0, 0, 0)
    if kind == "active":
        px[1, 1] = hexc("f2d880")
    save(img, f"portrait_{kind}.png")


def parchment():
    w = h = 24
    img = Image.new("RGBA", (w, h), PARCHMENT)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = ring(x, y, w, h)
            if d == 0:
                px[x, y] = WOOD_DARK
            elif d == 1:
                px[x, y] = PARCHMENT_DARK if (y == h - 2 or x == w - 2) else INK["q"]
            elif d == 2 and (y == h - 3 or x == w - 3) and h32(x, y, 3) % 3 == 0:
                px[x, y] = PARCHMENT_DARK
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        px[corner] = (0, 0, 0, 0)
    save(img, "parchment.png")


def check(on):
    rows = ["dddddddddl",
            "dkkkkkkkkl",
            "dkkkkkkkkl",
            "dkkkkkkkkl",
            "dkkkkkkkkl",
            "dkkkkkkkkl",
            "dkkkkkkkkl",
            "dkkkkkkkkl",
            "dkkkkkkkkl",
            "llllllllll"]
    img = bitmap(rows)
    if on:
        mark = bitmap(["......y",
                       ".....yg",
                       "g...yg.",
                       "gg.yg..",
                       ".ggg...",
                       "..g...."])
        img.alpha_composite(mark, (2, 2))
    save(img, f"check_{'on' if on else 'off'}.png")


def slider_and_scroll():
    save(bitmap(["dddddddddddd",
                 "dkkkkkkkkkkl",
                 "dkkkkkkkkkkl",
                 "dkkkkkkkkkkl",
                 "dkkkkkkkkkkl",
                 "llllllllllll"]), "slider_track.png")
    save(bitmap([".kkkkk.",
                 "kyggggk",
                 "kglllwk",
                 "kglwwwk",
                 "kglwwwk",
                 "kglwwwk",
                 "kglwwwk",
                 "kglwwdk",
                 "kgwwddk",
                 "kGGGGGk",
                 ".kkkkk."]), "slider_grabber.png")
    save(bitmap(["kkkkkk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kbbbbk",
                 "kkkkkk"]), "scroll_track.png")
    save(bitmap([".kkkk.",
                 "kllwwk",
                 "klwwdk",
                 "klwwdk",
                 "klwwdk",
                 "klgGdk",
                 "klwwdk",
                 "klwwdk",
                 "klwwdk",
                 "klwwdk",
                 "kwdddk",
                 ".kkkk."]), "scroll_grabber.png")
    save(bitmap([".k............k.",
                 "kyGGGGGGGGGGGGyk",
                 ".k............k."]), "divider.png")   # a rule with a diamond at each end


SHIELD = ["kkkkkkkkkk",
          "kHFFFFFFFk",
          "kHFFFFFFFk",
          "kHFFFFFFFk",
          "kHFFFFFFDk",
          "kHFFFFFFDk",
          "kHFFFFFFDk",
          ".kHFFFFDk.",
          ".kFFFFFDk.",
          "..kFFFDk..",
          "...kFDk...",
          "....kk...."]


def badges():
    titles = {   # fill, highlight, shade, band
        "common": ("w", "l", "d", None),
        "citizen": ("i", "I", "b", None),
        "patrician": ("S", "c", "I", "x"),
        "baron": ("g", "y", "G", "x"),
        "noble": ("g", "y", "G", "x"),
    }
    for tid, (f, hl, sh, band) in titles.items():
        rows = [r.replace("F", f).replace("H", hl).replace("D", sh) for r in SHIELD]
        if band:
            rows[4] = rows[4][:2] + band * 6 + rows[4][8:]
            rows[5] = rows[5][:2] + band * 6 + rows[5][8:]
        img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
        if tid == "noble":   # the shield is lower and a crown sits on it
            img.alpha_composite(bitmap(rows[:9] + ["..kFFDk...".replace("F", f).replace("D", sh), "...kk....."]), (1, 1))
            img.alpha_composite(bitmap(["k.k.k.k", "kykykyk", "kgggggk", "kkkkkkk"]), (2, 0))
        else:
            img.alpha_composite(bitmap(rows), (1, 0))
        save(img, f"badge_title_{tid}.png", MARKS)
    offices = {
        "mayor": ["k........k..",
                  ".k......k...",
                  "..k....k....",
                  "...g..g.....",
                  "....gg......",
                  "...kkkk.....",
                  "..kyggGk....",
                  "..kgyxGk....",
                  "..kgxxGk....",
                  "..kGGGGk....",
                  "...kkkk.....",
                  "............"],
        "councillor": [".kkkkkkkkk..",
                       "kPpppppppPk.",
                       ".kqqqqqqqk..",
                       ".kqkkkkkqk..",
                       ".kqqqqqqqk..",
                       ".kqkkkkqqk..",
                       ".kqqqqqqqk..",
                       ".kqkkkqxqk..",
                       ".kqqqqxzxk..",
                       "kPpppppxpPk.",
                       ".kkkkkkkkk..",
                       "............"],
        "judge": [".....kk.....",
                  ".....yy.....",
                  ".kggggggggk.",
                  ".g...gg...g.",
                  "g.g..gg..g.g",
                  "g..g.gg.g..g",
                  "kggk.gg.kggk",
                  ".....gg.....",
                  ".....gg.....",
                  "...kggggk...",
                  "..kGGGGGGk..",
                  "............"],
        "constable": ["..kkk.......",
                      ".kIIIk......",
                      "kIk.kIk.....",
                      "kIk.kIk.....",
                      ".kIIIk......",
                      "..kIk.......",
                      "..kIk.......",
                      "..kIIIk.....",
                      "..kIk.......",
                      "..kIIk......",
                      "..kIk.......",
                      "...k........"],
        "collector": ["....kkk.....",
                      "...kdwdk....",
                      "....kwk.....",
                      "...kwwwk....",
                      "..kwlwwwk...",
                      ".kwlwwwwwk..",
                      ".kwwwgwwwk..",
                      ".kwwgygwwk..",
                      ".kwwwgwwdk..",
                      "..kwwwwdk...",
                      "...kkkkk....",
                      "............"],
        "inspector": ["...kkkk.....",
                      "..kIIIIk....",
                      ".kISSSSIk...",
                      ".kIScSSIk...",
                      ".kISSSSIk...",
                      ".kISSSSIk...",
                      "..kIIIIk....",
                      "...kkkkdk...",
                      ".......kdk..",
                      "........kdk.",
                      ".........kd.",
                      "..........k."],
    }
    for oid, rows in offices.items():
        save(bitmap(rows), f"badge_office_{oid}.png", MARKS)
    chevron = bitmap(["yg...gy.", ".gyyyg.."])   # two rows, one row of air between chevrons
    for n, ys in ((1, (3,)), (2, (1, 5)), (3, (0, 3, 6))):
        img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        for y in ys:
            img.alpha_composite(chevron, (0, y))
        save(img, f"rank_{n}.png", MARKS)
    save(bitmap(["....kkkkk.......",
                 "..kkxxxxxkk.....",
                 ".kxzzxxxxxXk....",
                 ".kzxxxxxxxXk....",
                 "kxzxxXXXxxxXk...",
                 "kxzxXzxxXxxXk...",
                 "kxxxXxxzXxxXk...",
                 "kxxxXXXXXxxXk...",
                 "kxxxxxxxxxXXk...",
                 ".kxxxxxxxXXk....",
                 ".kXxxxxxXXXk....",
                 "..kkXXXXXkk.....",
                 "....kkkkkxk.....",
                 ".........kxk....",
                 "..........kk....",
                 "................"]), "seal.png", MARKS)


def cursors():
    save(bitmap(["k.........",
                 "kk........",
                 "kck.......",
                 "kcck......",
                 "kccck.....",
                 "kcccck....",
                 "kccccck...",
                 "kcccccck..",
                 "kccccccck.",
                 "kcccckkkkk",
                 "kcckck....",
                 "kck.kck...",
                 "kk..kck...",
                 "k....kck..",
                 ".....kk..."], {"c": hexc("ece4d2")}), "cursor_arrow.png", CURSOR)
    save(bitmap(["...kk.......",
                 "..kcck......",
                 "..kcck......",
                 "..kcckkk....",
                 "..kcckcckk..",
                 "kkkcccccckk.",
                 "kckcccccccck",
                 "kccccccccck.",
                 ".kcccccccck.",
                 "..kcccccck..",
                 "..kcccccck..",
                 "...kkkkkk..."]), "cursor_hand.png", CURSOR)
    save(bitmap(["kkkkkkkkk",
                 "kgggggggk",
                 ".kpppppk.",
                 "..kpppk..",
                 "...kpk...",
                 "..kpypk..",
                 ".kpyyypk.",
                 "kgggggggk",
                 "kkkkkkkkk"]), "cursor_wait.png", CURSOR)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    panel()
    for s in ("normal", "hover", "pressed", "disabled"):
        button(s)
    field()
    tooltip()
    tab(True)
    tab(False)
    for k in ("normal", "active", "dim"):
        portrait_frame(k)
    parchment()
    check(False)
    check(True)
    slider_and_scroll()
    badges()
    cursors()
    if a.preview:
        names = sorted(os.listdir(OUT))
        sheet = Image.new("RGBA", (len(names) * 40 * 4, 40 * 4), (96, 104, 92, 255))
        for i, n in enumerate(n for n in names if n.endswith(".png")):
            im = Image.open(os.path.join(OUT, n)).convert("RGBA")
            sheet.alpha_composite(im.resize((im.width * 4, im.height * 4), Image.NEAREST), (i * 160, 0))
        sheet.save(os.path.join(a.preview, "ui_theme.png"))
        print("preview", os.path.join(a.preview, "ui_theme.png"))


if __name__ == "__main__":
    main()
