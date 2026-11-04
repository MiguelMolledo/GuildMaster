#!/usr/bin/env python3
"""One-off help when a building or house sprite is imported (docs/protocolos/generar-ciudad.md §Puertas): proposes
where its door is drawn, so the Door marker of its scene can be placed and reviewed. It is NOT used by the game, the
generator or the validator: they read the marker (catalogue data/building_sprites.json, tools/city/sprites_catalog.py).

  python3 tools/city/proponer_puerta.py buildings/forge props/lot_house_a ... [--sheet reports/ciudad/puertas.png]

How: in the lower half of the sprite it looks for the largest blob of dark pixels (a door is a dark opening or dark
wood) whose bottom touches the building's base, and proposes its bottom middle as the threshold. The face is the side
of the sprite's middle the blob sits on (left = SW, right = SE). The sheet draws the proposal (red) and the scene's
current marker if it has one (green) on each sprite, x3, to check by eye before writing the marker.
"""
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VIS = os.path.join(ROOT, "game", "visuals")


def scene_sprite(scene):
    """(texture path, offset (x, y), Door marker position or None) of game/visuals/<scene>.tscn."""
    text = open(os.path.join(VIS, scene + ".tscn"), encoding="utf-8").read()
    res = dict(re.findall(r'\[ext_resource type="Texture2D"[^\]]*path="res://([^"]+)"[^\]]*id="([^"]+)"\]', text))
    res = {v: k for k, v in res.items()}
    m = re.search(r'\[node name="Sprite" type="Sprite2D" parent="\."\](.*?)(?=\n\[|\Z)', text, re.S)
    body = m.group(1)
    tex = res[re.search(r'texture = ExtResource\("([^"]+)"\)', body).group(1)]
    off = re.search(r"offset = Vector2\(([-\d.]+), ([-\d.]+)\)", body)
    door = None
    d = re.search(r'\[node name="Door" type="Marker2D" parent="\."\](.*?)(?=\n\[|\Z)', text, re.S)
    if d:
        p = re.search(r"position = Vector2\(([-\d.]+), ([-\d.]+)\)", d.group(1))
        door = (float(p.group(1)), float(p.group(2))) if p else (0.0, 0.0)
    return os.path.join(ROOT, tex), (float(off.group(1)), float(off.group(2))), door


def propose(png, offset):
    im = Image.open(png).convert("RGBA")
    w, h = im.size
    px = im.load()
    base = {}
    for x in range(w):
        ys = [y for y in range(h) if px[x, y][3] > 127]
        base[x] = max(ys) if ys else -1
    dark = set()
    for y in range(h // 2, h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 127 and (0.3 * r + 0.59 * g + 0.11 * b) < 75:
                dark.add((x, y))
    best = None
    seen = set()
    for t in sorted(dark):
        if t in seen:
            continue
        comp, todo = [], [t]
        seen.add(t)
        while todo:
            u = todo.pop()
            comp.append(u)
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                v = (u[0] + d[0], u[1] + d[1])
                if v in dark and v not in seen:
                    seen.add(v)
                    todo.append(v)
        xs = [c[0] for c in comp]
        ys = [c[1] for c in comp]
        cw, ch = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        if not (5 <= cw <= 40 and 12 <= ch <= 70) or len(comp) < 60:
            continue
        cx = (min(xs) + max(xs)) // 2
        gap = min(abs(base.get(x, -1) - max(ys)) for x in range(min(xs), max(xs) + 1))
        if gap > 22:
            continue
        score = len(comp) - gap * 8
        if best is None or score > best[0]:
            best = (score, cx, max(ys))
    if best is None:
        return None
    _, cx, by = best
    side = "SW" if cx < w / 2 else "SE"
    return side, (round(cx + offset[0]), round(by + 1 + offset[1]))


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    tiles = []
    for scene in argv:
        png, off, door = scene_sprite(scene)
        p = propose(png, off)
        print(f"{scene}: propuesta {p} · marcador actual {door}")
        tiles.append((scene, png, off, p, door))
    if sheet:
        ims = []
        for scene, png, off, p, door in tiles:
            im = Image.open(png).convert("RGBA")
            bg = Image.new("RGBA", im.size, (95, 138, 58, 255))
            bg.alpha_composite(im)
            big = bg.resize((im.width * 3, im.height * 3), Image.NEAREST)
            d = ImageDraw.Draw(big)
            for pt, col in ((p[1] if p else None, (255, 40, 40, 255)), (door, (40, 255, 80, 255))):
                if pt is None:
                    continue
                x, y = (pt[0] - off[0]) * 3, (pt[1] - off[1]) * 3
                d.ellipse([x - 6, y - 6, x + 6, y + 6], outline=col, width=3)
            d.text((4, 4), scene, fill=(255, 255, 255, 255))
            ims.append(big)
        W = sum(i.width for i in ims[:5]) + 10 * 5
        rows = [ims[i:i + 5] for i in range(0, len(ims), 5)]
        H = sum(max(i.height for i in r) for r in rows) + 10 * len(rows)
        out = Image.new("RGBA", (W, H), (30, 24, 18, 255))
        y = 0
        for r in rows:
            x = 0
            for i in r:
                out.alpha_composite(i, (x, y))
                x += i.width + 10
            y += max(i.height for i in r) + 10
        os.makedirs(os.path.dirname(os.path.abspath(sheet)), exist_ok=True)
        out.convert("RGB").save(sheet)
        print("hoja:", sheet)


if __name__ == "__main__":
    main(sys.argv[1:])
