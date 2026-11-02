#!/usr/bin/env python3
"""Prueba sin créditos (docs/arte/kits.md): ¿se puede sacar un kit de casa de entramado de la lámina de fal
assets/concept/ciudades2/kit_entramado/kit_entramado.jpg a la densidad del juego?

1. Recorta las piezas de la lámina (muros de planta baja y alta, postes, piñones, tejado, chimenea, buhardilla,
   contraventanas, letrero) y les quita el fondo gris y la sombra (relleno desde el borde).
2. Las reduce a la densidad del juego: la figura de la lámina mide 152 px y el personaje del juego 48, así que todo
   se divide por 152 / 48 = 3,17 (BOX, sin suavizado al ampliar).
3. Las limpia: paleta común sacada de los sprites del juego (casas de entramado, forja, ayuntamiento), alfa binaria,
   píxeles sueltos fuera y contorno de 1 px en el borde de la silueta.
4. Monta casas con las piezas limpias (apilando muros por la esquina delantera) junto al personaje de 48 px.

Uso: python3 tools/art/kit_prueba.py  -> docs/arte/kits/*.png y tmp/kit_prueba/piezas/*.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import escala_b as ops  # noqa: E402  (grow_u / grow_v: alargar una fachada sin reescalar)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "concept", "ciudades2", "kit_entramado", "kit_entramado.jpg")
OUT = os.path.join(ROOT, "docs", "arte", "kits")
TMP = os.path.join(ROOT, "tmp", "kit_prueba")
FIG_CONCEPT = 152.0   # alto de la figura de la lámina (y 1260 -> 1412)
FIG_GAME = 48.0
F = FIG_CONCEPT / FIG_GAME
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"

PIECES = {  # nombre: caja en la lámina (x0, y0, x1, y1)
    "muro_bajo_esquina": (75, 450, 720, 905),
    "muro_bajo_abierto": (75, 880, 720, 1440),
    "muro_alto_esquina": (480, 60, 975, 460),
    "poste": (795, 550, 870, 895),
    "pinon_entramado": (80, 60, 440, 400),
    "pinon_liso": (1160, 70, 1490, 380),
    "faldones": (1200, 120, 2040, 520),
    "cumbrera": (1620, 570, 1770, 690),
    "chimenea": (1930, 90, 2120, 270),
    "buhardilla": (2160, 80, 2460, 500),
    "contraventanas": (2505, 100, 2690, 340),
    "letrero": (2495, 415, 2690, 640),
    "casa_lamina_1": (975, 630, 1730, 1420),
    "casa_lamina_2": (1730, 570, 2720, 1420),
}


def is_bg(p):
    """Fondo gris claro o sombra gris: poco saturado y claro."""
    r, g, b = p[:3]
    return max(r, g, b) - min(r, g, b) < 18 and (r + g + b) / 3 > 140


def remove_bg(im):
    """Quita el fondo y la sombra por relleno desde el borde (lo encerrado por el contorno se queda)."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    stack = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + \
        [(w - 1, y) for y in range(h)]
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        seen[y * w + x] = 1
        if not is_bg(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return im


def reduce(im):
    """A la densidad del juego: BOX (media de cada bloque de 3,17 px) y alfa binaria."""
    w, h = round(im.width / F), round(im.height / F)
    # el canal de color se promedia solo con píxeles opacos (premultiplicado) para no ensuciar el borde de gris
    pre = Image.new("RGBA", im.size)
    pre.paste(im)
    small = pre.resize((w, h), Image.BOX)
    px = small.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    return small


def game_palette(n=32):
    """Paleta común: la de los sprites de edificio del juego (casas de entramado, forja, ayuntamiento)."""
    names = ["house_b", "house_c", "house", "house_a", "forge", "armory", "town_hall"]
    tiles = [Image.open(os.path.join(ROOT, "assets", "art", "buildings", nm + ".png")).convert("RGBA") for nm in names]
    mosaic = Image.new("RGB", (192 * len(tiles), 192), (0, 0, 0))
    for i, t in enumerate(tiles):
        bg = Image.new("RGB", t.size, (0, 0, 0))
        bg.paste(t, mask=t.getchannel("A"))
        mosaic.paste(bg, (192 * i, 0))
    pal = mosaic.quantize(colors=n + 1, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    cols = pal.getpalette()[: 3 * (n + 1)]
    out = [tuple(cols[i:i + 3]) for i in range(0, len(cols), 3)]
    return [c for c in out if c != (0, 0, 0)][:n]


def kit_palette(pieces, game, n=32, snap=12):
    """Paleta común del kit: n colores (median cut) de todas las piezas reducidas juntas; cada uno se cambia por el
    del juego más cercano si están a menos de `snap` (así el kit comparte colores con los sprites que ya hay)."""
    W = sum(p.width for p in pieces)
    H = max(p.height for p in pieces)
    mosaic = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = 0
    for p in pieces:
        mosaic.alpha_composite(p, (x, 0))
        x += p.width
    opaque = [px[:3] for px in mosaic.getdata() if px[3]]
    strip = Image.new("RGB", (len(opaque), 1))
    strip.putdata(opaque)
    q = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    cols = q.getpalette()[: 3 * n]
    out = []
    for i in range(0, len(cols), 3):
        c = tuple(cols[i:i + 3])
        g = nearest(c, game)
        d = sum((a - b) ** 2 for a, b in zip(c, g)) ** 0.5
        out.append(g if d < snap else c)
    return out


def drop_bits(im, frac=0.08):
    """Quita los trozos sueltos (componentes de menos de frac × el mayor): restos de otras piezas del recorte."""
    w, h = im.size
    px = im.load()
    seen = set()
    comps = []
    for y in range(h):
        for x in range(w):
            if not px[x, y][3] or (x, y) in seen:
                continue
            comp, stack = [], [(x, y)]
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][3]:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            comps.append(comp)
    big = max((len(c) for c in comps), default=0)
    for comp in comps:
        if len(comp) < frac * big:
            for cx, cy in comp:
                px[cx, cy] = (0, 0, 0, 0)
    bb = im.getchannel("A").getbbox()
    return im.crop(bb) if bb else im


def nearest(c, pal):
    return min(pal, key=lambda q: (q[0] - c[0]) ** 2 * 3 + (q[1] - c[1]) ** 2 * 4 + (q[2] - c[2]) ** 2 * 2)


def clean(im, pal, outline):
    """Paleta común, píxeles sueltos fuera, contorno de 1 px por dentro del borde de la silueta."""
    im = im.copy()
    px = im.load()
    w, h = im.size
    cache = {}
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3]:
                k = p[:3]
                if k not in cache:
                    cache[k] = nearest(k, pal)
                px[x, y] = cache[k] + (255,)
    # píxeles opacos sueltos (sin vecinos opacos en cruz) fuera; huecos de 1 px dentro, rellenos
    for y in range(h):
        for x in range(w):
            n = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                    if 0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][3])
            if px[x, y][3] and n == 0:
                px[x, y] = (0, 0, 0, 0)
            elif not px[x, y][3] and n == 4:
                px[x, y] = px[x - 1, y]
    # contorno: todo píxel opaco que toca el transparente (en cruz) pasa al color de contorno
    edge = []
    for y in range(h):
        for x in range(w):
            if not px[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < w and 0 <= yy < h) or not px[xx, yy][3]:
                    edge.append((x, y))
                    break
    for x, y in edge:
        px[x, y] = outline + (255,)
    return im


def bottom_vertex(im):
    a = im.getchannel("A").load()
    w, h = im.size
    for y in range(h - 1, -1, -1):
        xs = [x for x in range(w) if a[x, y]]
        if xs:
            return (min(xs) + max(xs)) // 2, y
    return w // 2, h


def top_at(im, x):
    a = im.getchannel("A").load()
    for y in range(im.height):
        if a[x, y]:
            return y
    return im.height


def person():
    im = Image.open(os.path.join(ROOT, "assets", "art", "characters", "artisan_m", "idle_s.png")).convert("RGBA").crop((0, 0, 68, 68))
    px = im.load()
    look = ((70, 46, 28), (226, 180, 140), (150, 52, 40), (196, 160, 90))
    for y in range(68):
        for x in range(68):
            r, g, b, a = px[x, y]
            if a == 254:
                base = look[min(max(int(round(b / 50.0)), 1), 4) - 1]
                k = r / 127.5
                px[x, y] = (min(255, int(base[0] * k)), min(255, int(base[1] * k)), min(255, int(base[2] * k)), 255)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(TMP, "piezas"), exist_ok=True)
    src = Image.open(SRC).convert("RGB")
    game = game_palette()
    big, red, cln = {}, {}, {}
    for name, box in PIECES.items():
        b = remove_bg(src.crop(box))
        big[name] = b
        red[name] = drop_bits(reduce(b))
    pal = kit_palette([red[n] for n in red], game)
    outline = (30, 24, 18)  # el contorno de los personajes y marcas del juego (data/view.json character.outline)
    print("factor %.3f, paleta del kit %d colores (%d del juego), contorno %s" % (
        F, len(pal), sum(1 for c in pal if c in game), outline))
    for name in PIECES:
        cln[name] = clean(red[name], pal, outline)
        cln[name].save(os.path.join(TMP, "piezas", name + ".png"))
        red[name].save(os.path.join(TMP, "piezas", name + "_sin_limpiar.png"))
        print("  %-20s %4dx%-4d -> %3dx%-3d" % (name, big[name].width, big[name].height, *red[name].size))
    comparison(big, red, cln)
    houses(cln, red)


def comparison(big, red, cln):
    """Lámina: concepto (reducido a ×1 de la lámina para caber), piezas a la densidad del juego sin limpiar y limpias,
    las dos a 1:1 y a ×4."""
    names = ["muro_bajo_esquina", "muro_alto_esquina", "pinon_entramado", "buhardilla", "chimenea", "letrero",
             "casa_lamina_1"]
    font = ImageFont.truetype(FONT, 14)
    z = 4
    rows = []
    for n in names:
        a = big[n]
        b, c = red[n], cln[n]
        cell_h = max(b.height * z, 40)
        a_fit = a.resize((round(a.width * cell_h / a.height), cell_h), Image.LANCZOS)
        row = [("concepto (lámina, %dx%d)" % a.size, a_fit), ("sin limpiar ×%d (%dx%d)" % (z, *b.size),
               b.resize((b.width * z, b.height * z), Image.NEAREST)),
               ("limpia ×%d" % z, c.resize((c.width * z, c.height * z), Image.NEAREST)), ("sin limpiar 1:1", b),
               ("limpia 1:1", c)]
        rows.append((n, row))
    W = 40 + max(sum(im.width + 30 for _, im in row) for _, row in rows)
    H = 20 + sum(max(im.height for _, im in row) + 50 for _, row in rows)
    sheet = Image.new("RGBA", (W, H), (60, 58, 56, 255))
    d = ImageDraw.Draw(sheet)
    y = 20
    for n, row in rows:
        x = 20
        d.text((x, y), n, font=font, fill=(255, 230, 160))
        for label, im in row:
            sheet.alpha_composite(im, (x, y + 22))
            d.text((x, y + 24 + im.height), label, font=font, fill=(220, 210, 190))
            x += im.width + 30
        y += max(im.height for _, im in row) + 50
    sheet.save(os.path.join(OUT, "01_concepto_reducida_limpia.png"))


def stack(base, top, at=None):
    """Pone `top` sobre `base` con el vértice inferior de top en lo alto de la esquina de base (o en `at`)."""
    bx, by = bottom_vertex(base)
    ty = top_at(base, bx) if at is None else at[1]
    tx, tby = bottom_vertex(top)
    ox, oy = bx - tx, ty - tby + 1
    left = min(0, ox)
    up = min(0, oy)
    W = max(base.width, ox + top.width) - left
    H = max(base.height, oy + top.height) - up
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(base, (-left, -up))
    out.alpha_composite(top, (ox - left, oy - up))
    return out


def roof_of(house):
    """El tejado de una casa montada: los píxeles de tono teja y su contorno (lo oscuro que toca teja)."""
    im = house.copy()
    px = im.load()
    w, h = im.size

    def tile(p):
        r, g, b, a = p
        return a and r > 165 and r > g + 45 and r > b + 70  # teja naranja, no la viga marrón

    keep = set((x, y) for y in range(h) for x in range(w) if tile(px[x, y]))
    ring = set()
    for x, y in keep:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if 0 <= q[0] < w and 0 <= q[1] < h and q not in keep and px[q][3] and sum(px[q][:3]) < 200:
                    ring.add(q)
    keep |= ring
    keep |= enclosed(keep, w, h)
    for y in range(h):
        for x in range(w):
            if (x, y) not in keep:
                px[x, y] = (0, 0, 0, 0)
    return drop_bits(im)


def enclosed(mask, w, h):
    """Los píxeles fuera de `mask` a los que no se llega desde el borde sin cruzarla (huecos de dentro)."""
    out = set()
    seen = set()
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        q = stack.pop()
        if q in seen or q in mask or not (0 <= q[0] < w and 0 <= q[1] < h):
            continue
        seen.add(q)
        x, y = q
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    for y in range(h):
        for x in range(w):
            if (x, y) not in mask and (x, y) not in seen:
                out.add((x, y))
    return out


def cover_of(house):
    """La cubierta entera de una casa montada (tejado + piñón) como una pieza: todo lo que queda por encima de lo
    alto de los muros (la línea en V desde la esquina, justo bajo el alero)."""
    vx, vy = bottom_vertex(house)
    # el alero en la columna de la esquina: la fila más baja del tejado (en coordenadas de la casa)
    roof_full = roof_of_full(house)
    ra = roof_full.load()
    eave = max(y for y in range(house.height) if ra[vx, y]) if any(ra[vx, y] for y in range(house.height)) else vy
    out = house.copy()
    px = out.load()
    for x in range(house.width):
        cut = eave - abs(x - vx) // 2 if x < vx else eave - (x - vx) // 2
        for y in range(max(0, cut + 1), house.height):
            if not ra[x, y]:
                px[x, y] = (0, 0, 0, 0)
    return out.crop(out.getchannel("A").getbbox())


def roof_of_full(house):
    """La máscara del tejado (roof_of) en las coordenadas de la casa (sin recortar)."""
    im = house.copy()
    px = im.load()
    w, h = im.size

    def tile(p):
        r, g, b, a = p
        return a and r > 165 and r > g + 45 and r > b + 70

    keep = set((x, y) for y in range(h) for x in range(w) if tile(px[x, y]))
    keep |= enclosed(keep, w, h)
    m = Image.new("L", (w, h), 0)
    ml = m.load()
    for x, y in keep:
        ml[x, y] = 255
    return m


def faces(im):
    """(vx, izquierda, derecha): la esquina delantera y lo que miden en pantalla las dos fachadas de una pieza en L."""
    vx, vy = bottom_vertex(im)
    bb = im.getchannel("A").getbbox()
    return vx, vx - bb[0], bb[2] - 1 - vx


def _col_cost(im, x0, x1):
    px = im.load()
    t = 0
    for x in range(max(1, x0), x1):
        for y in range(im.height):
            a, b = px[x, y], px[x - 1, y]
            if a[3] != b[3]:
                t += 300
            else:
                t += abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
    return t


def fit_faces(im, left, right, margin=8):
    """Alarga (nunca acorta) las fachadas de una pieza en L hasta `left` y `right` px de pantalla, metiendo franjas de
    2 px en las columnas más uniformes (revoco, no marcos ni postes). Las líneas en 2:1 siguen enteras."""
    vx, l, r = faces(im)
    while l + 1 < left:
        best = min(range(int(vx - l + margin), int(vx - margin)), key=lambda c: _col_cost(im, c - 3, c))
        im = ops.grow_u(im, best, 1)  # lo de la derecha (la esquina y la otra fachada) se corre (2, 1)
        vx, l, r = faces(im)
    while r + 1 < right:
        best = min(range(int(vx + margin), int(vx + r - margin)), key=lambda c: _col_cost(im, c, c + 3))
        im = ops.grow_v(im, best, 1)
        vx, l, r = faces(im)
    return im


def houses(cln, red):
    """Casas montadas con piezas limpias junto al personaje (1:1 y ×3). Las fachadas de los muros se igualan a las de
    la casa de la lámina (el tejado sale de ella) y al piñón; el piñón va sobre la fachada derecha y el tejado encima."""
    p = person()
    roof = roof_of(cln["casa_lamina_1"])
    cover = cover_of(cln["casa_lamina_1"])
    cover.save(os.path.join(TMP, "piezas", "cubierta.png"))
    _, hl, hr = faces(cln["casa_lamina_1"])
    gable = cln["pinon_entramado"]
    low = fit_faces(cln["muro_bajo_esquina"], hl - 4, hr - 2)
    up = fit_faces(cln["muro_alto_esquina"], hl - 4, hr - 2)
    print("  fachadas: lámina izq %d der %d; bajo %s; alto %s; piñón suelto %d" % (
        hl, hr, faces(low)[1:], faces(up)[1:], gable.width))
    two = stack(low, up)
    h1 = paste_cover(two, cover)
    h2 = paste_cover(low, cover)
    h3 = paste_cover(two, cover)
    h3 = add_at(h3, cln["chimenea"], (0.36, 0.0))
    h3 = add_at(h3, cln["letrero"], (0.08, 0.66))
    h3 = add_at(h3, cln["contraventanas"], (0.70, 0.62))
    bad = finish(fit_faces(stack(cln["muro_bajo_esquina"], cln["muro_alto_esquina"]), 0, 0), gable, roof)
    built = [("2 plantas", h1), ("1 planta", h2), ("2 plantas + chimenea, letrero, contraventanas", h3),
             ("piñón suelto + tejado: no casan", bad)]
    lam = [("casa de la lámina, reducida", red["casa_lamina_1"]), ("ídem, limpia", cln["casa_lamina_1"]),
           ("casa del juego hoy (house_c, escala B)", Image.open(os.path.join(
               ROOT, "assets", "art", "buildings", "escala_b", "house_c.png")).convert("RGBA"))]
    font = ImageFont.truetype(FONT, 13)
    allh = built + lam
    W = 40 + sum(im.width + 90 for _, im in allh)
    H = max(im.height for _, im in allh) + 80
    sheet = Image.new("RGBA", (W, H), (60, 58, 56, 255))
    d = ImageDraw.Draw(sheet)
    base = H - 40
    x = 20
    for label, im in allh:
        vx, vy = bottom_vertex(im)
        sheet.alpha_composite(im, (x, base - vy))
        sheet.alpha_composite(p, (x + vx + 40 - 34, base - 58 + 6))
        d.text((x, base + 10), label, font=font, fill=(230, 220, 200))
        x += im.width + 90
    sheet.save(os.path.join(OUT, "02_casas_montadas_1a1.png"))
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(os.path.join(OUT, "03_casas_montadas_x3.png"))
    for i, (_, im) in enumerate(built):
        im.save(os.path.join(TMP, "casa_%d.png" % (i + 1)))


def paste_cover(walls, cover):
    """La cubierta (tejado + piñón) con su esquina delantera inferior sobre lo alto de la esquina de los muros."""
    vx, vy = bottom_vertex(walls)
    top = top_at(walls, vx)
    out, _ = paste_at(walls, cover, (vx, top + 2), bottom_vertex(cover))
    return out


def finish(walls, gable, roof):
    """Piñón sobre la fachada derecha (su esquina inferior izquierda en lo alto de la esquina) y tejado encima (su
    punto más bajo, el alero de la esquina, sobre la misma esquina)."""
    vx, vy = bottom_vertex(walls)
    top = top_at(walls, vx)
    out, (ox, oy) = paste_at(walls, gable, (vx, top + 1), corner_of_gable(gable))
    vx, top = vx - ox, top - oy
    out, _ = paste_at(out, roof, (vx, top + 3), bottom_vertex(roof))
    return out


def corner_of_gable(g):
    """La esquina inferior izquierda del piñón (el píxel opaco más bajo de su columna más a la izquierda)."""
    a = g.getchannel("A").load()
    for x in range(g.width):
        ys = [y for y in range(g.height) if a[x, y]]
        if ys:
            return x, max(ys)
    return 0, g.height


def paste_at(base, piece, at, anchor):
    """Pega `piece` con su punto `anchor` en el punto `at` de `base`, agrandando el lienzo si hace falta. Devuelve
    también cuánto se ha corrido el origen de base (para seguir usando sus coordenadas)."""
    ox, oy = at[0] - anchor[0], at[1] - anchor[1]
    left, up = min(0, ox), min(0, oy)
    W = max(base.width, ox + piece.width) - left
    H = max(base.height, oy + piece.height) - up
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(base, (-left, -up))
    out.alpha_composite(piece, (ox - left, oy - up))
    return out, (left, up)


def add_at(base, piece, rel):
    out = base.copy()
    out.alpha_composite(piece, (int(base.width * rel[0]), int(base.height * rel[1])))
    return out


if __name__ == "__main__":
    main()
