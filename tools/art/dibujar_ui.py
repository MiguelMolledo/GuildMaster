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
PIECES (below) is the 9-patch margin of every piece: tools/ui/maqueta.py reads it, the theme uses the same numbers.
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
}


def h32(*v):
    x = 2166136261
    for n in v:
        x = ((x ^ (n & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
        x ^= x >> 13
    return x


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))
    print(f"  assets/art/ui/theme/{name} {img.size[0]}×{img.size[1]}")


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
