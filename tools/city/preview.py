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
    iso_w, iso_h = (m.w + m.h) * 8 + 16, (m.w + m.h) * 4 + 60
    img = Image.new("RGBA", (W + iso_w + 30, max(H, iso_h) + 40), (43, 34, 27, 255))
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default()
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
            d.rectangle([x + 1, y + 1, x + w * T - 2, y + h * T - 2], fill=(70, 45, 35, 255), outline=(15, 10, 8, 255))
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
    gen = data.get("generated") or {}
    title = f"{data['id']}  {m.w}x{m.h}" + (f"  trazado {gen.get('layout')} semilla {gen.get('seed')}" if gen else "")
    d.text((10, 8), title, fill=(255, 240, 200, 255), font=font)
    d.text((W + 40, 8), "boceto isométrico (2:1)", fill=(255, 240, 200, 255), font=font)
    _iso(img, m, data, color, W + 30, 40)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.convert("RGB").save(out)
    return os.path.relpath(out, citylib.ROOT)


def _short(sid):
    return {"player_forge": "forja", "rival_forge": "forja R", "workshop_carpentry": "carp", "workshop_masonry": "cant",
            "workshop_tailor": "sast", "armory": "armer", "town_hall": "ayunt"}.get(sid, sid.replace("house_", "c"))


HEIGHT = {"building": 10, "tree": 9, "stall": 4, "board": 5}


def _iso(img, m, data, color, ox, oy):
    """Tiles as 16x8 diamonds; buildings and trees as raised blocks, painted back to front."""
    d = ImageDraw.Draw(img)
    hw, hh = 8, 4
    x0 = ox + m.h * hw
    sites = m.site_tiles()
    house_tiles = set()
    for it in (data.get("decor") or {}).get("items", []):
        if it["kind"] == "house":
            w, h = it.get("size", [3, 3])
            for dr in range(h):
                for dc in range(w):
                    house_tiles.add((it["at"][0] + dc, it["at"][1] + dr))
    order = sorted(m.all_tiles(), key=lambda t: (t[0] + t[1], t[0]))
    for (c, r) in order:
        k = m.kind((c, r))
        sx, sy = x0 + (c - r) * hw, oy + (c + r) * hh
        col = color.get(k, (255, 0, 255, 255))
        top = 0
        if k == "building":
            top = HEIGHT["building"] if ((c, r) in sites or (c, r) in house_tiles) else 2
            col = (150, 70, 50, 255) if (c, r) in sites else ((110, 80, 60, 255) if (c, r) in house_tiles else (95, 120, 60, 255))
        elif k in HEIGHT:
            top = HEIGHT[k]
        dia = [(sx, sy - hh - top), (sx + hw, sy - top), (sx, sy + hh - top), (sx - hw, sy - top)]
        if top:
            dark = tuple(int(v * 0.6) for v in col[:3]) + (255,)
            mid = tuple(int(v * 0.8) for v in col[:3]) + (255,)
            d.polygon([(sx - hw, sy - top), (sx, sy + hh - top), (sx, sy + hh), (sx - hw, sy)], fill=mid)
            d.polygon([(sx + hw, sy - top), (sx, sy + hh - top), (sx, sy + hh), (sx + hw, sy)], fill=dark)
        d.polygon(dia, fill=col)
    for it in (data.get("decor") or {}).get("items", []):
        if it["kind"] == "lantern":
            c, r = it["at"]
            sx, sy = x0 + (c - r) * hw, oy + (c + r) * hh
            d.line([sx, sy, sx, sy - 9], fill=(40, 30, 20, 255))
            d.point((sx, sy - 10), fill=(255, 220, 60, 255))
