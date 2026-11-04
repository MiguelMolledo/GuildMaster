"""Preview PNG of a map without the game (docs/protocolos/generar-ciudad.md §Vista previa).

Two panels side by side: the plan (top-down, one square per tile: the tile kinds in their data/tiles.json colours,
the sites outlined with their id, the doors as a white dot with a tick towards the building, the filler houses as
a dark square with an arrow to their door, yards dotted, lanterns yellow, props orange, benches violet, fences as
brown lines on the field edges) and a small isometric sketch (2:1 diamonds, heights by kind) to see the town as the
camera does. python3 tools/city/ciudad.py vista <map> -> reports/ciudad/<map>.png
"""
import os

from PIL import Image, ImageDraw, ImageFont

import citylib

T = 14  # px per tile in the plan
FONTS = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]


def _font(size=10):
    """A font with accents (the default bitmap one has none), else the default."""
    for f in FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def _hex(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def render(map_id, out=None):
    cat = citylib.Catalog()
    data = citylib.load_json(os.path.join(citylib.DATA, "maps", map_id + ".json"))
    return render_data(data, cat, out or os.path.join(citylib.ROOT, "reports", "ciudad", map_id + ".png"))


def render_data(data, cat, out):
    m = citylib.Map(data, cat)
    tiles = citylib.load_json(os.path.join(citylib.DATA, "tiles.json"))["tiles"]
    color = {k: _hex(v["color"]) for k, v in tiles.items()}
    W, H = m.w * T, m.h * T
    hw = 12 if max(m.w, m.h) <= 48 else 9
    iso_w, iso_h = (m.w + m.h) * hw + 16, (m.w + m.h) * hw // 2 + 120
    img = Image.new("RGBA", (W + iso_w + 30, max(H, iso_h) + 40), (43, 34, 27, 255))
    d = ImageDraw.Draw(img)
    font = _font(10)
    ox, oy = 10, 30
    for t in m.all_tiles():
        k = m.kind(t)
        x, y = ox + t[0] * T, oy + t[1] * T
        d.rectangle([x, y, x + T - 1, y + T - 1], fill=color.get(k, (255, 0, 255, 255)))
    # sites
    for sid, s in sorted(m.sites.items()):
        xs = [t[0] for t in s["tiles"]]
        ys = [t[1] for t in s["tiles"]]
        x0, y0 = ox + min(xs) * T, oy + min(ys) * T
        x1, y1 = ox + (max(xs) + 1) * T - 1, oy + (max(ys) + 1) * T - 1
        fill = (150, 60, 40, 255) if s["type"] not in ("house",) else (120, 80, 60, 255)
        if s["type"] == "town_hall":
            fill = (200, 170, 90, 255)
        d.rectangle([x0, y0, x1, y1], fill=fill, outline=(20, 12, 8, 255))
        d.text((x0 + 2, y0 + 1), _short(sid), fill=(255, 245, 220, 255), font=font)
        if s["door"]:
            dc, dr = s["door"]
            cx, cy = ox + dc * T + T // 2, oy + dr * T + T // 2
            d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(255, 255, 255, 255), outline=(0, 0, 0, 255))
    # services
    for kind, sid, tile, svc in m.services():
        cx, cy = ox + svc[0] * T + T // 2, oy + svc[1] * T + T // 2
        d.rectangle([cx - 2, cy - 2, cx + 2, cy + 2], outline=(255, 255, 255, 255))
    # decor
    for it in (data.get("decor") or {}).get("items", []):
        k = it["kind"]
        c, r = it["at"]
        x, y = ox + c * T, oy + r * T
        if k == "house":
            w, h = it.get("size", [3, 3])
            fill = _hex(it["color"]) if it.get("color") else (70, 45, 35, 255)
            if it.get("color"):
                fill = tuple(int(v * 0.75) for v in fill[:3]) + (255,)
            d.rectangle([x + 1, y + 1, x + w * T - 2, y + h * T - 2], fill=fill, outline=(15, 10, 8, 255))
            fx, fy = it.get("facing", [0, 1])
            cx, cy = x + w * T / 2, y + h * T / 2
            ex, ey = cx + fx * (w * T / 2 - 2), cy + fy * (h * T / 2 - 2)
            d.line([cx, cy, ex, ey], fill=(255, 230, 120, 255), width=2)
            d.ellipse([ex - 2, ey - 2, ex + 2, ey + 2], fill=(255, 230, 120, 255))
        elif k == "yard":
            for i in range(2, T - 1, 4):
                for j in range(2, T - 1, 4):
                    d.point((x + i, y + j), fill=(60, 40, 25, 255))
        elif k == "single":
            d.ellipse([x + 3, y + 3, x + T - 4, y + T - 4], fill=(90, 110, 140, 255))
        elif k == "lantern":
            off = it.get("off", [0, 0])
            px, py = x + T // 2 + off[0] / 64.0 * T + off[1] / 32.0 * T, y + T // 2 + off[1] / 32.0 * T - off[0] / 64.0 * T
            d.ellipse([px - 3, py - 3, px + 3, py + 3], fill=(255, 220, 60, 255), outline=(60, 40, 0, 255))
        elif k == "fence":
            off = it.get("off", [0, 0])
            dc = off[0] / 64.0 + off[1] / 32.0
            dr = off[1] / 32.0 - off[0] / 64.0
            if abs(dr) > abs(dc):
                yy = y + (T - 1 if dr > 0 else 0)
                d.line([x, yy, x + T - 1, yy], fill=(110, 70, 35, 255), width=2)
            else:
                xx = x + (T - 1 if dc > 0 else 0)
                d.line([xx, y, xx, y + T - 1], fill=(110, 70, 35, 255), width=2)
        elif k == "prop":
            col = (170, 110, 200, 255) if it["id"] == "bench" else (240, 140, 40, 255)
            d.rectangle([x + 4, y + 4, x + T - 5, y + T - 5], fill=col, outline=(30, 20, 10, 255))
        elif k == "landmark":
            w, h = it.get("size", [1, 1])
            d.rectangle([x, y, x + w * T - 1, y + h * T - 1], fill=_hex(it.get("color", "#9a7a5a")),
                        outline=(255, 240, 200, 255))
            if w * h > 1 and it.get("label"):
                d.text((x + 2, y + 1), _label(it), fill=(20, 12, 6, 255), font=font)
        elif k == "boat":
            w, h = it.get("size", [2, 1])
            d.rounded_rectangle([x + 2, y + 2, x + w * T - 3, y + h * T - 3], radius=5, fill=_hex(it.get("color", "#6b4a2a")),
                                outline=(240, 230, 210, 255))
            if it["id"] == "ship":
                mx, my = x + w * T // 2, y + h * T // 2
                d.ellipse([mx - 2, my - 2, mx + 2, my + 2], fill=(240, 230, 210, 255))
    gen = data.get("generated") or {}
    title = f"{data['id']}  {m.w}x{m.h}" + (f"  trazado {gen.get('layout')} semilla {gen.get('seed')}" if gen else "")
    d.text((10, 8), title, fill=(255, 240, 200, 255), font=font)
    d.text((W + 40, 8), "boceto isométrico (2:1)", fill=(255, 240, 200, 255), font=font)
    _iso(img, m, data, color, W + 30, 100, hw)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.convert("RGB").save(out)
    return os.path.relpath(out, citylib.ROOT)


def _short(sid):
    return {"player_forge": "forja", "rival_forge": "forja R", "workshop_carpentry": "carp", "workshop_masonry": "cant",
            "workshop_tailor": "sast", "armory": "armer", "town_hall": "ayunt"}.get(sid, sid.replace("house_", "c"))


HEIGHT = {"building": 10, "tree": 9, "stall": 4, "board": 5, "wall": 9, "rock": 12}

LABELS = {"cathedral": "catedral", "church": "iglesia", "exchange": "lonja", "customs": "aduana", "warehouse": "almacén",
          "crane": "grúa", "shipyard": "astillero", "gate_tower": "puerta", "wall_tower": "torre", "mine": "mina",
          "quarry": "cantera", "spoil": "escombrera", "mill": "molino", "threshing": "era", "cloister": "claustro",
          "abbey_church": "iglesia", "guesthouse": "hospedería", "granary": "granero", "palace": "palacio",
          "kiln": "horno", "barn": "pajar", "chapel": "ermita", "watermill": "molino", "lime_kiln": "calera",
          "dovecote": "palomar", "infirmary": "enfermería", "smelter": "fundición", "hospital": "hospital"}


def _label(it):
    return LABELS.get(it["id"], it["id"])


def _iso(img, m, data, color, ox, oy, hw=8):
    """Tiles as 2:1 diamonds; buildings, houses (by their height and district colour), landmarks, walls, rock, trees
    and boats as raised blocks, painted back to front; the landmarks' names on top."""
    d = ImageDraw.Draw(img)
    font = _font(10)
    hh = hw // 2
    k = hw / 8.0
    x0 = ox + m.h * hw
    sites = m.site_tiles()
    vol = {}  # tile -> (height, colour)
    labels = []
    items = (data.get("decor") or {}).get("items", [])
    for it in items:
        w, h = it.get("size", [1, 1])
        tiles = [(it["at"][0] + dc, it["at"][1] + dr) for dr in range(h) for dc in range(w)]
        if it["kind"] == "house":
            top = it.get("height", 34) / 4.0 * k if it["id"] == "house_block" else 12 * k
            col = _hex(it["color"]) if it.get("color") else (110, 80, 60, 255)
            for t in tiles:
                vol[t] = (top, col)
        elif it["kind"] == "landmark":
            top = it.get("height", 48) / 4.0 * k
            for t in tiles:
                vol[t] = (top, _hex(it.get("color", "#9a7a5a")))
            if w * h >= 4 and it.get("label"):
                labels.append((tiles, top, _label(it)))
        elif it["kind"] == "boat":
            for t in tiles:
                vol[t] = (3 * k, _hex(it.get("color", "#6b4a2a")))
            if it["id"] == "ship":
                labels.append((tiles, 3 * k, "|mast"))
    gc = m.cat.view.get("ground_corners", {})
    corners = {k: v for k, v in gc.get("kinds", {}).items() if not k.startswith("_")}
    fill = float(gc.get("fill", 0.75))
    order = sorted(m.all_tiles(), key=lambda t: (t[0] + t[1], t[0]))
    for (c, r) in order:
        kd = m.kind((c, r))
        sx, sy = x0 + (c - r) * hw, oy + (c + r) * hh
        col = color.get(kd, (255, 0, 255, 255))
        top = 0
        if (c, r) in vol:
            top, col = vol[(c, r)]
        elif kd == "building":
            top = HEIGHT["building"] * k if (c, r) in sites else 2 * k
            col = (150, 70, 50, 255) if (c, r) in sites else (95, 120, 60, 255)
        elif kd == "rock":
            top = (HEIGHT["rock"] + citylib.tile_hash(c, r, 4) % 6) * k
        elif kd in HEIGHT:
            top = HEIGHT[kd] * k
        if kd == "dock":
            top = 1
        dia = [(sx, sy - hh - top), (sx + hw, sy - top), (sx, sy + hh - top), (sx - hw, sy - top)]
        if top:
            dark = tuple(int(v * 0.6) for v in col[:3]) + (255,)
            mid = tuple(int(v * 0.8) for v in col[:3]) + (255,)
            d.polygon([(sx - hw, sy - top), (sx, sy + hh - top), (sx, sy + hh), (sx - hw, sy)], fill=mid)
            d.polygon([(sx + hw, sy - top), (sx, sy + hh - top), (sx, sy + hh), (sx + hw, sy)], fill=dark)
            col = tuple(min(255, int(v * 1.08)) for v in col[:3]) + (255,)
        d.polygon(dia, fill=col)
        if not top:  # the corners of data/view.json ground_corners: a diagonal stair of street drawn smooth
            for over, under in corners.items():
                if kd not in under:
                    continue
                pts = {"t": (sx, sy - hh), "r": (sx + hw, sy), "b": (sx, sy + hh), "l": (sx - hw, sy)}
                for corner, (da, db), (va, vb) in (("r", ((0, -1), (1, 0)), ("t", "b")), ("b", ((1, 0), (0, 1)), ("r", "l")),
                                                   ("l", ((0, 1), (-1, 0)), ("b", "t")), ("t", ((-1, 0), (0, -1)), ("l", "r"))):
                    if m.kind((c + da[0], r + da[1])) == over and m.kind((c + db[0], r + db[1])) == over:
                        cx_, cy_ = pts[corner]
                        tri = [pts[corner]] + [(cx_ + (pts[v][0] - cx_) * fill, cy_ + (pts[v][1] - cy_) * fill)
                                               for v in (va, vb)]
                        d.polygon(tri, fill=color.get(over, (255, 0, 255, 255)))
    for it in items:
        if it["kind"] == "lantern":
            c, r = it["at"]
            sx, sy = x0 + (c - r) * hw, oy + (c + r) * hh
            d.line([sx, sy, sx, sy - 9 * k], fill=(40, 30, 20, 255))
            d.point((sx, sy - 10 * k), fill=(255, 220, 60, 255))
    for tiles, top, text in labels:
        cx = sum(x0 + (c - r) * hw for c, r in tiles) / len(tiles)
        cy = min(oy + (c + r) * hh for c, r in tiles) - top
        if text == "|mast":
            d.line([cx, cy + hh, cx, cy - 14 * k], fill=(60, 40, 25, 255), width=max(1, int(k)))
            d.polygon([(cx + 1, cy - 13 * k), (cx + 8 * k, cy - 4 * k), (cx + 1, cy - 2 * k)], fill=(235, 225, 200, 255))
            continue
        tw = d.textlength(text, font=font)
        d.rectangle([cx - tw / 2 - 2, cy - 14, cx + tw / 2 + 2, cy - 3], fill=(30, 22, 16, 255))
        d.text((cx - tw / 2, cy - 14), text, fill=(255, 235, 190, 255), font=font)
