#!/usr/bin/env python3
"""Escala B (docs/arte/escala.md, decisión del 2026-11-02): los edificios exteriores de Guild Renew con puerta ~52,
planta baja ~64 y plantas altas ~48, a densidad 1:1 y sin reescalar nunca.

Dos operaciones, las dos copian píxeles enteros:
- rows: sube una altura duplicando filas a lo largo de la diagonal 2:1 de la base del muro (en V con vértice en la
  esquina delantera). Elige las filas más uniformes de cada tramo (las que más se parecen a su vecina: tablas de la
  puerta, cristal, revoco), así las vigas y los marcos no se engordan.
- grow_u / grow_v: alarga el edificio a lo largo de un eje de la rejilla repitiendo una crujía (la franja de fachada
  justo antes del corte), para que un edificio de 192 px llene un solar más grande sin escalarlo.

Uso: python3 tools/art/escala_b.py          -> assets/art/buildings/escala_b/<id>.png + escala_b.json (anclas, Top)
     python3 tools/art/escala_b.py --sheet  -> además tmp/escala_b/revision.png (antes / después junto al personaje)
     python3 tools/art/escala_b.py --scenes -> apunta las escenas (SCENES) a escala_b: textura, ancla, Top, y deja
                                               el sprite de antes como nodo oculto SpriteAntes (para volver atrás);
                                               luego: godot --headless --path . --import && python3 tools/uids.py --fix

Las recetas (RECIPES) dicen, por sprite: la esquina delantera de la base del muro, los tramos de altura en los que
añadir filas, los alargamientos y los parches a mano. Los sprites originales no se tocan (assets/art/buildings/).
"""
import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "art", "buildings")
DST = os.path.join(SRC, "escala_b")


# --- operaciones ------------------------------------------------------------------------------------------------
def _cut(cx, apex, x):
    return apex - abs(x - cx) // 2


def _diff(a, b):
    if a[3] < 8 and b[3] < 8:
        return 0
    if (a[3] < 8) != (b[3] < 8):
        return 255 * 3
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def row_cost(im, cx, apex):
    """Lo que se nota duplicar la fila justo encima del corte en V con vértice (cx, apex)."""
    px = im.load()
    w, h = im.size
    total = 0
    for x in range(w):
        yc = _cut(cx, apex, x)
        if yc < 2 or yc >= h:
            continue
        r = px[x, yc - 1]
        total += min(_diff(r, px[x, yc - 2]), _diff(r, px[x, yc]))
    return total


def insert_row(im, cx, apex):
    """Duplica la fila de encima del corte en V: lo de arriba se queda, lo de abajo baja 1 (la imagen crece 1)."""
    w, h = im.size
    out = Image.new("RGBA", (w, h + 1), (0, 0, 0, 0))
    src = im.load()
    dst = out.load()
    for x in range(w):
        yc = max(1, min(h, _cut(cx, apex, x)))
        for y in range(yc):
            dst[x, y] = src[x, y]
        dst[x, yc] = src[x, yc - 1]
        for y in range(yc, h):
            dst[x, y + 1] = src[x, y]
    return out


def add_rows(im, cx, base_y, lo, hi, n, spacing=2, log=None):
    """Añade n filas entre las alturas lo..hi (sobre la base del muro, base_y = fila de la esquina). Si caben menos
    filas que n con la separación pedida, hace varias pasadas (cada una vuelve a medir sobre la imagen ya estirada)."""
    done = []
    left = n
    while left > 0:
        cands = sorted(((row_cost(im, cx, base_y - hh), hh) for hh in range(lo + 1, hi)), key=lambda t: t[0])
        chosen = []
        for c, hh in cands:
            if all(abs(hh - o) >= spacing for o in chosen):
                chosen.append(hh)
            if len(chosen) == left:
                break
        if not chosen:
            break
        for hh in sorted(chosen, reverse=True):  # de arriba abajo: insertar en una altura no mueve las de debajo
            im = insert_row(im, cx, base_y - hh)
            base_y += 1
        done += chosen
        left -= len(chosen)
        hi += len(chosen)
    if log is not None:
        log.append("filas %d-%d: +%d" % (lo, hi, len(done)))
    return im, base_y, sorted(done)


def grow_u(im, c, m, bay=None):
    """Alarga a lo largo de u (la fachada que baja hacia la derecha, pantalla (2, 1)) con un corte vertical en x = c
    sobre esa fachada: lo que queda a la derecha se desplaza (2m, m) y el hueco repite la crujía [c - 2m, c)
    desplazada en la misma dirección (las líneas en (2, 1) y las verticales siguen enteras). Crece (2m, m)."""
    w, h = im.size
    out = Image.new("RGBA", (w + 2 * m, h + m), (0, 0, 0, 0))
    src = im.load()
    dst = out.load()
    for y in range(h + m):
        for x in range(w + 2 * m):
            sx, sy = (x, y) if x < c else (x - 2 * m, y - m)
            if 0 <= sx < w and 0 <= sy < h:
                dst[x, y] = (bay[sx, sy] if bay is not None and c <= x < c + 2 * m else src[sx, sy])
    return out


def grow_v(im, c, m):
    """Alarga a lo largo de v (la fachada que baja hacia la izquierda, pantalla (-2, 1)) con un corte vertical en
    x = c: lo que queda a la izquierda se desplaza (-2m, m) y el hueco repite la crujía [c, c + 2m). Crece (2m, m) y
    lo que no se mueve se corre 2m a la derecha."""
    w, h = im.size
    out = Image.new("RGBA", (w + 2 * m, h + m), (0, 0, 0, 0))
    src = im.load()
    dst = out.load()
    for y in range(h + m):
        for x in range(w + 2 * m):
            sx, sy = (x, y - m) if x < c + 2 * m else (x - 2 * m, y)
            if 0 <= sx < w and 0 <= sy < h:
                dst[x, y] = src[sx, sy]
    return out


def patched(im, patches):
    """Copia de im con parches (x0, x1, y0, y1, dx, dy): esos píxeles se toman de (x + dx, y + dy)."""
    out = im.copy()
    op, sp = out.load(), im.load()
    w, h = im.size
    for x0, x1, y0, y1, dx, dy in patches:
        for x in range(x0, x1):
            for y in range(max(0, y0), min(h, y1)):
                if 0 <= x + dx < w and 0 <= y + dy < h:
                    op[x, y] = sp[x + dx, y + dy]
    return out


def grow_u_steps(im, steps, patches=None):
    """Varios grow_u seguidos; con parches, la crujía que se repite sale de una copia retocada (no el original)."""
    bim = patched(im, patches) if patches else None
    for c, m in steps:
        im = grow_u(im, c, m, bim.load() if bim is not None else None)
        if bim is not None:
            bim = grow_u(bim, c, m, bim.load())
    return im


def clean_stubs(im, min_run=2):
    """Quita los «goterones»: tramos verticales de 1 px oscuros con muro claro a los dos lados (restos de duplicar
    la fila del borde inferior de una ventana). Cada píxel toma el color de su vecino izquierdo."""
    px = im.load()
    w, h = im.size

    def dark(p):
        return p[3] > 200 and p[0] + p[1] + p[2] < 200

    def light(p):  # muro claro y poco saturado (no el amarillo de los marcos)
        return p[3] > 200 and p[0] + p[1] + p[2] > 480 and max(p[:3]) - min(p[:3]) < 70

    stub = [[dark(px[x, y]) and light(px[x - 1, y]) and light(px[x + 1, y]) if 0 < x < w - 1 else False
             for y in range(h)] for x in range(w)]
    fixed = 0
    for x in range(1, w - 1):
        y = 0
        while y < h:
            if stub[x][y]:
                y1 = y
                while y1 < h and stub[x][y1]:
                    y1 += 1
                if min_run <= y1 - y <= 10:
                    for yy in range(y, y1):
                        px[x, yy] = px[x - 1, yy]
                        fixed += 1
                y = y1
            else:
                y += 1
    return fixed


def split_slab(im, cx, cy):
    """(edificio, losa): la losa es lo que queda por debajo de la base del muro (en V desde la esquina)."""
    w, h = im.size
    bld = im.copy()
    slab = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    b, s_ = bld.load(), slab.load()
    src = im.load()
    for x in range(w):
        base = cy - abs(x - cx) // 2
        for y in range(max(0, base + 1), h):
            s_[x, y] = src[x, y]
            b[x, y] = (0, 0, 0, 0)
    return bld, slab


def bottom_vertex(im):
    """El vértice inferior del diamante de la base (la fila opaca más baja, su centro)."""
    a = im.getchannel("A").load()
    w, h = im.size
    for y in range(h - 1, -1, -1):
        xs = [x for x in range(w) if a[x, y] > 8]
        if xs:
            return (min(xs) + max(xs)) / 2.0, y
    return w / 2.0, h


# --- recetas ----------------------------------------------------------------------------------------------------
# corner: esquina delantera de la base del muro (x, y) en el PNG original; anchor: el píxel que cae en Feet hoy;
# rows: (desde, hasta, filas) en alturas sobre esa esquina; top: Top de hoy (px sobre Feet).
RECIPES = {
    "house": {"corner": (91, 176), "anchor": (96, 141), "top": 72, "rows": [(2, 43, 10), (44, 70, 6)]},
    "house_a": {"corner": (90, 157), "anchor": (96, 136), "top": 72, "rows": [(2, 37, 16)]},
    "house_b": {"corner": (96, 167), "anchor": (96, 142), "top": 72, "rows": [(2, 40, 14), (41, 67, 16)]},
    "house_c": {"corner": (87, 178), "anchor": (96, 142), "top": 72, "rows": [(2, 38, 14), (39, 92, 18)]},
    "house_d": {"corner": (108, 168), "anchor": (96, 145), "top": 72, "rows": [(2, 45, 10), (46, 60, 6)]},
    "house_e": {"same": "house_a"},
    "house_f": {"same": "house_c"},
    "forge": {"corner": (92, 165), "anchor": (96, 139), "top": 72, "rows": [(2, 43, 12), (44, 64, 8)]},
    "armory": {"corner": (128, 152), "anchor": (96, 130), "top": 72, "rows": [(2, 44, 8), (45, 90, 12)]},
    "forge_works": {"corner": (94, 166), "anchor": (94, 166), "top": 0, "rows": [(4, 60, 20)]},
    # H9: house_noble_2 de Guild Renew. Antes, escala 1,6 sobre el solar de 6×4; ahora 1:1: la fachada larga (u) se
    # alarga repitiendo 4 veces la crujía de ventanas junto a la esquina (x 86-105) y se suben sus tres plantas. El
    # ancla es el centro del solar de 6×4 con la base alineada a su esquina delantera (lot).
    "town_hall": {"corner": (110, 158), "anchor": None, "lot": (6, 4), "top": 0,
                  "grow_u": [(106, 10)] * 4, "rows": [(2, 27, 16), (28, 72, 50)],
                  "bay_patch": [(86, 91, 119, 153, 18, 9)], "clean_stubs": True,
                  "slab": {"grow_u": [(94, 10)] * 4, "bay_patch": [(74, 94, 128, 158, 0, 12)]}},
}


def build(name, log):
    r = RECIPES[name]
    src_name = name
    if "same" in r:
        r = RECIPES[r["same"]]
    im = Image.open(os.path.join(SRC, src_name + ".png")).convert("RGBA")
    cx, cy = r["corner"]
    slab = None
    if "slab" in r:
        # la losa del suelo (lo que queda por debajo de la base del muro) se alarga aparte, con su propio corte
        im, slab = split_slab(im, cx, cy)
        slab = grow_u_steps(slab, r["slab"].get("grow_u", []), r["slab"].get("bay_patch"))
    if r.get("grow_u"):
        im = grow_u_steps(im, r["grow_u"], r.get("bay_patch"))
        for c, m in r["grow_u"]:
            if cx >= c:
                cx, cy = cx + 2 * m, cy + m
        log.append("u +%d pasos" % sum(m for _, m in r["grow_u"]))
    added = 0
    cuts = []
    for lo, hi, n in sorted(r["rows"], key=lambda t: -t[0]):  # tramo más alto primero
        im, cy, chosen = add_rows(im, cx, cy, lo, hi, n, log=log)
        added += len(chosen)
        cuts += chosen
    if r.get("clean_stubs"):
        log.append("goterones: %d px" % clean_stubs(im))
    if slab is not None:
        full = Image.new("RGBA", im.size, (0, 0, 0, 0))
        full.alpha_composite(slab, (0, added))
        full.alpha_composite(im)
        im = full
    if r.get("anchor") is None:
        vx, vy = bottom_vertex(im)
        u, v = r["lot"]
        anchor = [int(round(vx - (u - v) * 16)), int(vy - (u + v) * 8)]
    else:
        anchor = [r["anchor"][0], r["anchor"][1] + added]
    a = im.getchannel("A").getbbox()
    return im, {"anchor": anchor, "added_rows": added, "cuts": sorted(cuts), "top": r["top"] + added,
                "size": list(im.size), "visual_top": anchor[1] - a[1]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--scenes", action="store_true", help="apunta las escenas de game/visuals a escala_b (una vez)")
    a = ap.parse_args()
    if a.scenes:
        update_scenes(json.load(open(os.path.join(DST, "escala_b.json"))))
        return
    os.makedirs(DST, exist_ok=True)
    meta_path = os.path.join(DST, "escala_b.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    names = [n for n in RECIPES if not a.only or n in a.only.split(",")]
    for n in names:
        log = []
        im, info = build(n, log)
        im.save(os.path.join(DST, n + ".png"))
        meta[n] = info
        print(n, info["size"], "+%d filas" % info["added_rows"], "; ".join(log))
    json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)
    if a.sheet:
        sheet(names, meta)


def sheet(names, meta):
    person = Image.open(os.path.join(ROOT, "assets", "art", "characters", "artisan_m", "idle_s.png")).convert("RGBA").crop((0, 0, 68, 68))
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
    cells = []
    for n in names:
        r = RECIPES[n] if "same" not in RECIPES[n] else RECIPES[RECIPES[n]["same"]]
        old = Image.open(os.path.join(SRC, n + ".png")).convert("RGBA")
        new = Image.open(os.path.join(DST, n + ".png")).convert("RGBA")
        oa = tuple(r["anchor"]) if r.get("anchor") else (95, 135)
        cells.append((n, old, oa, new, tuple(meta[n]["anchor"])))
    W = 30 + len(cells) * 430
    H = 330
    out = Image.new("RGBA", (W, H), (60, 60, 60, 255))
    d = ImageDraw.Draw(out)
    base = H - 30
    x = 20
    for n, old, oa, new, na in cells:
        for im, anc in ((old, oa), (new, na)):
            out.alpha_composite(im, (x + 96 - anc[0], base - anc[1]))
            out.alpha_composite(person, (x + 96 + 60 - 34, base - 58 + 30))
            x += 210
        d.text((x - 410, 4), n, font=font, fill=(255, 255, 200))
        x += 10
    p = os.path.join(ROOT, "tmp", "escala_b")
    os.makedirs(p, exist_ok=True)
    out.save(os.path.join(p, "revision.png"))
    big = out.resize((out.width * 2, out.height * 2), Image.NEAREST)
    big.save(os.path.join(p, "revision_x2.png"))
    print("hoja", os.path.join(p, "revision.png"))



# --- escenas ----------------------------------------------------------------------------------------------------
# escena -> id del sprite (assets/art/buildings/<id>.png -> escala_b/<id>.png)
SCENES = {
    "game/visuals/buildings/house.tscn": "house",
    "game/visuals/buildings/house_slate.tscn": "house_e",
    "game/visuals/buildings/house_ochre.tscn": "house_f",
    "game/visuals/buildings/house_tall.tscn": "house_b",
    "game/visuals/buildings/armory.tscn": "armory",
    "game/visuals/buildings/forge.tscn": "forge",
    "game/visuals/buildings/town_hall.tscn": "town_hall",
    "game/visuals/props/lot_house_a.tscn": "house_a",
    "game/visuals/props/lot_house_b.tscn": "house_b",
    "game/visuals/props/lot_house_c.tscn": "house_c",
    "game/visuals/props/lot_house_d.tscn": "house_d",
    "game/visuals/props/lot_house_e.tscn": "house_e",
    "game/visuals/props/lot_house_f.tscn": "house_f",
}
TOWN_HALL_TOP = 200  # sobre Feet: el letrero del ayuntamiento, encima del alero y del letrero del tablón; su punto medio no cae en el tablón


def _blocks(text):
    """Trozos del .tscn: cabecera de sección + sus líneas."""
    import re
    parts = re.split(r'(?m)^(?=\[)', text)
    return [p for p in parts if p]


def _set(block, key, value):
    import re
    if re.search(r'(?m)^%s = ' % re.escape(key), block):
        return re.sub(r'(?m)^%s = .*$' % re.escape(key), "%s = %s" % (key, value), block)
    lines = block.rstrip("\n").split("\n")
    return "\n".join([lines[0], "%s = %s" % (key, value)] + lines[1:]) + "\n" + ("\n" if block.endswith("\n\n") else "")


def _get(block, key):
    import re
    m = re.search(r'(?m)^%s = (.*)$' % re.escape(key), block)
    return m.group(1) if m else None


def _vec(s):
    import re
    inner = s[s.index("(") + 1:s.rindex(")")]
    a = re.findall(r'-?\d+(?:\.\d+)?', inner)
    return float(a[0]), float(a[1])


def forge_overlay_shift(info, recipe, pos, size_xy):
    """Cuánto sube un adorno del muro de la forja: las filas añadidas por debajo de su centro."""
    ax, ay = recipe["anchor"]
    cx, cy = recipe["corner"]
    x = ax + pos[0] + size_xy[0] / 2.0
    y = ay + pos[1] + size_xy[1] / 2.0
    h = cy - abs(int(x) - cx) // 2 - y
    return sum(1 for hh in info["cuts"] if hh < h)


def update_scenes(meta):
    import re
    for rel, sid in SCENES.items():
        path = os.path.join(ROOT, rel)
        text = open(path).read()
        if "escala_b/" in text:
            print("ya está:", rel)
            continue
        info = meta[sid]
        rec = RECIPES[sid] if "same" not in RECIPES[sid] else RECIPES[RECIPES[sid]["same"]]
        old_path = "res://assets/art/buildings/%s.png" % sid
        m = re.search(r'\[ext_resource type="Texture2D"[^\]]*path="%s" id="([^"]+)"\]' % re.escape(old_path), text)
        old_id = m.group(1)
        new_id = old_id + "_b"
        new_ext = '[ext_resource type="Texture2D" path="res://assets/art/buildings/escala_b/%s.png" id="%s"]' % (sid, new_id)
        text = text.replace(m.group(0), m.group(0) + "\n" + new_ext, 1)
        text = re.sub(r'load_steps=(\d+)', lambda mm: "load_steps=%d" % (int(mm.group(1)) + 1), text, count=1)
        blocks = _blocks(text)
        out = []
        top_old = None
        for b in blocks:
            head = b.split("\n", 1)[0]
            if head.startswith('[node name="Top"') and 'parent="."' in head:
                top_old = -_vec(_get(b, "position"))[1]
                top_new = TOWN_HALL_TOP if sid == "town_hall" else top_old + info["added_rows"]
                b = _set(b, "position", "Vector2(0, %d)" % -top_new)
            elif head.startswith('[node name="Sprite"') and 'parent="."' in head and _get(b, "texture") == 'ExtResource("%s")' % old_id:
                antes = b.replace('[node name="Sprite"', '[node name="SpriteAntes"', 1)
                antes = _set(antes, "visible", "false")
                antes = _set(antes, "editor_description", '"Building scale before B (docs/arte/escala.md). To go back: hide Sprite, show this node and put Top back at (0, -%d)."' % top_old)
                b = _set(b, "texture", 'ExtResource("%s")' % new_id)
                b = _set(b, "offset", "Vector2(%d, %d)" % (-info["anchor"][0], -info["anchor"][1]))
                b = re.sub(r'(?m)^scale = .*\n', "", b)
                b = _set(b, "editor_description", '"Scale B (docs/arte/escala.md, tools/art/escala_b.py): Guild Renew sprite with taller floors and door, 1:1, base on Feet. The sprite of before is SpriteAntes (hidden)."')
                if not b.endswith("\n\n"):
                    b = b.rstrip("\n") + "\n\n"
                b = b + antes.rstrip("\n") + "\n\n"
            out.append(b)
        text = "".join(out)
        if sid == "forge":
            text = forge_extras(text, info, rec, meta)
        open(path, "w").write(text.rstrip("\n") + "\n")
        print("escena:", rel, "Top", top_old, "->", TOWN_HALL_TOP if sid == "town_hall" else top_old + info["added_rows"])


def forge_extras(text, info, rec, meta):
    """La forja: el andamio estirado y los adornos de mejora que van en el muro, subidos."""
    import re
    # andamio
    wpath = "res://assets/art/buildings/forge_works.png"
    m = re.search(r'\[ext_resource type="Texture2D"[^\]]*path="%s" id="([^"]+)"\]' % re.escape(wpath), text)
    wid = m.group(1)
    text = text.replace(m.group(0), m.group(0) + '\n[ext_resource type="Texture2D" path="res://assets/art/buildings/escala_b/forge_works.png" id="%s_b"]' % wid, 1)
    text = re.sub(r'load_steps=(\d+)', lambda mm: "load_steps=%d" % (int(mm.group(1)) + 1), text, count=1)
    ext = dict((i, p) for p, i in re.findall(r'path="(res://[^"]+)" id="([^"]+)"', text))
    blocks = _blocks(text)
    pos_of = {}
    out = []
    for b in blocks:
        head = b.split("\n", 1)[0]
        nm = re.search(r'name="([^"]+)"', head)
        par = re.search(r'parent="([^"]+)"', head)
        if nm and par:
            key = (par.group(1) + "/" + nm.group(1)).lstrip("./")
            p = _get(b, "position")
            parent_pos = pos_of.get(par.group(1), (0.0, 0.0))
            own = _vec(p) if p else (0.0, 0.0)
            pos_of[key] = (parent_pos[0] + own[0], parent_pos[1] + own[1])
            if nm.group(1) == "Scaffold":
                b = _set(b, "texture", 'ExtResource("%s_b")' % wid)
                wa = meta["forge_works"]["anchor"]
                b = _set(b, "offset", "Vector2(%d, %d)" % (-wa[0], -wa[1]))
            elif par.group(1).startswith("Upgrades/") and "Sprite2D" in head and _get(b, "texture"):
                tid = re.search(r'ExtResource\("([^"]+)"\)', _get(b, "texture")).group(1)
                tex = os.path.join(ROOT, ext[tid].replace("res://", ""))
                sz = Image.open(tex).size
                off = _vec(_get(b, "offset") or "Vector2(0, 0)")
                abs_pos = (pos_of[key][0] + off[0], pos_of[key][1] + off[1])
                k = forge_overlay_shift(info, rec, abs_pos, sz)
                if k:
                    b = _set(b, "position", "Vector2(%d, %d)" % (own[0], own[1] - k))
                    print("  adorno %s sube %d" % (key, k))
        out.append(b)
    return "".join(out)


if __name__ == "__main__":
    main()
