#!/usr/bin/env python3
"""Láminas del estudio de escala (docs/arte/escala.md) a densidad 1:1: un píxel de arte = un píxel lógico.

Uso: python3 tools/art/escala.py            -> docs/arte/escala/*.png
     python3 tools/art/escala.py --refs     -> además, maquetas grises ×2 para pasar a fal (tmp/escala_refs/)

No escala ningún sprite: los bloques se dibujan con la rejilla del juego (casilla 64×32) y los personajes y casas
actuales se pegan tal cual desde assets/art/.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "assets", "art")
OUT = os.path.join(ROOT, "docs", "arte", "escala")

# --- Medidas de referencia -------------------------------------------------------------------------
CHAR_PX = 48            # figura del personaje (medida: 48-49 px dentro del frame de 68)
CHAR_M = 1.7
PX_M = CHAR_PX / CHAR_M  # 28,2 px por metro en vertical
TW, TH = 64, 32          # casilla

OUTLINE = (30, 24, 18, 255)
BG = (43, 34, 27, 255)
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_B = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# Paleta de bloques (tierras cálidas de la biblia)
WALL = ((226, 205, 160), (186, 160, 118))     # luz (+v), sombra (+u)
TIMBER = (92, 58, 30)
STONE = ((178, 172, 158), (138, 132, 120))
ROOF_RED = ((176, 84, 52), (132, 58, 38))
ROOF_SLATE = ((96, 100, 118), (70, 72, 88))
WOOD = ((150, 104, 62), (112, 76, 44))
WATER = (70, 112, 150)
BRICK = ((184, 104, 76), (146, 78, 58))
GLASS = (60, 78, 96)
DOOR = (96, 62, 34)


def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)


# --- Proyección -----------------------------------------------------------------------------------
class Iso:
    """(u, v) en casillas, z en píxeles hacia arriba -> píxel de pantalla."""

    def __init__(self, ox, oy):
        self.ox, self.oy = ox, oy

    def p(self, u, v, z=0.0):
        return (round(self.ox + (u - v) * TW / 2), round(self.oy + (u + v) * TH / 2 - z))


def poly(d, pts, fill):
    d.polygon(pts, fill=fill)
    d.line(pts + [pts[0]], fill=OUTLINE, width=1)


# --- Primitivas iso -------------------------------------------------------------------------------
def box(d, iso, u0, v0, a, b, h, col=WALL, top=None, z0=0.0):
    P = iso.p
    poly(d, [P(u0, v0 + b, z0), P(u0 + a, v0 + b, z0), P(u0 + a, v0 + b, z0 + h), P(u0, v0 + b, z0 + h)], col[0])
    poly(d, [P(u0 + a, v0, z0), P(u0 + a, v0 + b, z0), P(u0 + a, v0 + b, z0 + h), P(u0 + a, v0, z0 + h)], col[1])
    if top is not False:
        t = top if top else tuple(min(255, c + 18) for c in col[0])
        poly(d, [P(u0, v0, z0 + h), P(u0 + a, v0, z0 + h), P(u0 + a, v0 + b, z0 + h), P(u0, v0 + b, z0 + h)], t)


def gable(d, iso, u0, v0, a, b, h, r, along="u", roof=ROOF_RED, wall=WALL):
    """Tejado a dos aguas sobre una caja de altura h; cumbrera a h + r."""
    P = iso.p
    if along == "u":
        vm = v0 + b / 2
        poly(d, [P(u0, v0, h), P(u0 + a, v0, h), P(u0 + a, vm, h + r), P(u0, vm, h + r)], roof[1])
        poly(d, [P(u0, vm, h + r), P(u0 + a, vm, h + r), P(u0 + a, v0 + b, h), P(u0, v0 + b, h)], roof[0])
        poly(d, [P(u0 + a, v0, h), P(u0 + a, v0 + b, h), P(u0 + a, vm, h + r)], wall[1])
    else:
        um = u0 + a / 2
        poly(d, [P(u0, v0, h), P(u0, v0 + b, h), P(um, v0 + b, h + r), P(um, v0, h + r)], roof[0])
        poly(d, [P(um, v0, h + r), P(um, v0 + b, h + r), P(u0 + a, v0 + b, h), P(u0 + a, v0, h)], roof[1])
        poly(d, [P(u0, v0 + b, h), P(u0 + a, v0 + b, h), P(um, v0 + b, h + r)], wall[0])


def pyramid(d, iso, u0, v0, a, b, h, r, roof=ROOF_SLATE):
    P = iso.p
    ap = P(u0 + a / 2, v0 + b / 2, h + r)
    poly(d, [P(u0, v0, h), P(u0, v0 + b, h), ap], roof[1])
    poly(d, [P(u0, v0, h), P(u0 + a, v0, h), ap], roof[1])
    poly(d, [P(u0, v0 + b, h), P(u0 + a, v0 + b, h), ap], roof[0])
    poly(d, [P(u0 + a, v0, h), P(u0 + a, v0 + b, h), ap], roof[1])


def merlons(d, iso, u0, v0, a, b, h, col=STONE, mh=10, step=0.5):
    """Almenas en el borde de la caja (solo las caras visibles)."""
    n = int(round(a / step))
    for i in range(0, n, 2):
        box(d, iso, u0 + i * step, v0 + b - 0.25, step, 0.25, mh, col, z0=h)
    n = int(round(b / step))
    for i in range(0, n, 2):
        box(d, iso, u0 + a - 0.25, v0 + i * step, 0.25, step, mh, col, z0=h)


def face_v(d, iso, u1, u2, v, z1, z2, fill):
    P = iso.p
    poly(d, [P(u1, v, z1), P(u2, v, z1), P(u2, v, z2), P(u1, v, z2)], fill)


def face_u(d, iso, u, v1, v2, z1, z2, fill):
    P = iso.p
    poly(d, [P(u, v1, z1), P(u, v2, z1), P(u, v2, z2), P(u, v1, z2)], fill)


# --- Piezas compuestas ----------------------------------------------------------------------------
G_FLOOR, U_FLOOR, DOOR_H = 64, 48, 52   # propuesta recomendada (B): planta baja, planta alta, puerta


def house(d, iso, u0, v0, a, b, floors, ground=G_FLOOR, upper=U_FLOOR, roof_r=None, roof=ROOF_RED, along="u", wall=WALL,
          details=True):
    """Casa por plantas: planta baja `ground` px, cada planta alta `upper` px."""
    h = ground + upper * (floors - 1)
    if roof_r is None:
        roof_r = int(16 * (b if along == "u" else a) * 1.35)
    box(d, iso, u0, v0, a, b, h, wall, top=False)
    if details:
        # entramado: línea de forjado por planta
        for f in range(1, floors):
            z = ground + upper * (f - 1)
            P = iso.p
            d.line([P(u0, v0 + b, z), P(u0 + a, v0 + b, z)], fill=TIMBER, width=2)
            d.line([P(u0 + a, v0, z), P(u0 + a, v0 + b, z)], fill=TIMBER, width=2)
        # puerta 56 px (2 m) en la cara +v, ventanas de 20 px por planta
        du = u0 + a * 0.35
        face_v(d, iso, du, du + 0.75, v0 + b, 0, DOOR_H if ground <= 64 else 56, DOOR)
        for f in range(floors):
            zb = ground - 38 if f == 0 else ground + upper * (f - 1) + 14
            for k in range(max(1, int(a))):
                uu = u0 + 0.3 + k * 1.0
                if f == 0 and abs(uu - du) < 1.0:
                    continue
                if uu + 0.45 > u0 + a:
                    break
                face_v(d, iso, uu, uu + 0.45, v0 + b, zb, zb + 22, GLASS)
            for k in range(max(1, int(b))):
                vv = v0 + 0.3 + k * 1.0
                if vv + 0.45 > v0 + b:
                    break
                face_u(d, iso, u0 + a, vv, vv + 0.45, zb, zb + 22, GLASS)
    gable(d, iso, u0, v0, a, b, h, roof_r, along, roof, wall)
    return h + roof_r


def church(d, iso, u0, v0, nave_a=9, nave_b=4, wall_h=120, roof_r=90, tower=3, tower_h=250, spire=70):
    """Iglesia: nave a lo largo de u, torre en el extremo u0 (fachada)."""
    # torre detrás-izquierda en pantalla: en u0..u0+tower; nave de u0+tower a u0+tower+nave_a
    tv = v0 + (nave_b - tower) / 2
    box(d, iso, u0, tv, tower, tower, tower_h, STONE, top=False)
    pyramid(d, iso, u0, tv, tower, tower, tower_h, spire)
    nu = u0 + tower
    box(d, iso, nu, v0, nave_a, nave_b, wall_h, STONE, top=False)
    for k in range(int(nave_a) - 1):
        face_v(d, iso, nu + 1 + k, nu + 1.35 + k, v0 + nave_b, 40, 100, GLASS)
    gable(d, iso, nu, v0, nave_a, nave_b, wall_h, roof_r, "u", ROOF_SLATE, STONE)
    # ábside
    box(d, iso, nu + nave_a, v0 + 1, 1.5, nave_b - 2, wall_h - 20, STONE, top=False)
    pyramid(d, iso, nu + nave_a, v0 + 1, 1.5, nave_b - 2, wall_h - 20, 40)
    face_v(d, iso, u0 + 1.1, u0 + 1.9, tv + tower, 0, 64, DOOR)


def cathedral(d, iso, u0, v0):
    """Catedral comprimida: dos torres de fachada, nave alta con naves laterales, crucero."""
    L, B = 13, 6          # cuerpo
    nave_h, nave_r = 170, 70
    aisle_h = 100
    tw = 2.5              # torres
    t_h, sp = 300, 100
    # naves laterales
    box(d, iso, u0 + tw, v0, L, 1.5, aisle_h, STONE, top=False)
    gable(d, iso, u0 + tw, v0, L, 1.5, aisle_h, 18, "u", ROOF_SLATE, STONE)
    # torre trasera (v0)
    box(d, iso, u0, v0, tw, tw, t_h, STONE, top=False)
    pyramid(d, iso, u0, v0, tw, tw, t_h, sp)
    # nave central
    box(d, iso, u0 + tw, v0 + 1.5, L, B - 3, nave_h, STONE, top=False)
    gable(d, iso, u0 + tw, v0 + 1.5, L, B - 3, nave_h, nave_r, "u", ROOF_SLATE, STONE)
    # crucero
    cu = u0 + tw + 8
    box(d, iso, cu, v0 - 1.5, 2.5, B + 3, nave_h, STONE, top=False)
    gable(d, iso, cu, v0 - 1.5, 2.5, B + 3, nave_h, nave_r - 10, "v", ROOF_SLATE, STONE)
    # cabecera
    box(d, iso, u0 + tw + L, v0 + 1.5, 1.5, B - 3, nave_h - 30, STONE, top=False)
    pyramid(d, iso, u0 + tw + L, v0 + 1.5, 1.5, B - 3, nave_h - 30, 40)
    # nave lateral delantera
    box(d, iso, u0 + tw, v0 + B - 1.5, L, 1.5, aisle_h, STONE, top=False)
    gable(d, iso, u0 + tw, v0 + B - 1.5, L, 1.5, aisle_h, 18, "u", ROOF_SLATE, STONE)
    for k in range(0, L - 1, 2):
        face_v(d, iso, u0 + tw + 0.6 + k, u0 + tw + 1.2 + k, v0 + B, 30, 80, GLASS)
    # torre delantera (v0 + B - tw)
    box(d, iso, u0, v0 + B - tw, tw, tw, t_h, STONE, top=False)
    pyramid(d, iso, u0, v0 + B - tw, tw, tw, t_h, sp)
    # portada entre torres (cara -u: no visible en esta vista; puerta en la torre delantera, cara +v)
    face_v(d, iso, u0 + 0.6, u0 + 1.9, v0 + B, 0, 80, DOOR)


def castle(d, iso, u0, v0, a=16, b=12, wall_h=160, tower=3, tower_h=240, keep=5, keep_h=300):
    """Recinto: muralla con torres en las esquinas y torre del homenaje en el centro."""
    th = 1.0  # grosor de muralla
    # tramos traseros
    box(d, iso, u0, v0, a, th, wall_h, STONE)
    box(d, iso, u0, v0, th, b, wall_h, STONE)
    # torre esquina trasera
    box(d, iso, u0 - 1, v0 - 1, tower, tower, tower_h, STONE)
    merlons(d, iso, u0 - 1, v0 - 1, tower, tower, tower_h)
    box(d, iso, u0 + a - 2, v0 - 1, tower, tower, tower_h, STONE)
    merlons(d, iso, u0 + a - 2, v0 - 1, tower, tower, tower_h)
    box(d, iso, u0 - 1, v0 + b - 2, tower, tower, tower_h, STONE)
    merlons(d, iso, u0 - 1, v0 + b - 2, tower, tower, tower_h)
    # torre del homenaje
    ku, kv = u0 + (a - keep) / 2, v0 + (b - keep) / 2
    box(d, iso, ku, kv, keep, keep, keep_h, STONE)
    merlons(d, iso, ku, kv, keep, keep, keep_h)
    # tramos delanteros con puerta
    box(d, iso, u0 + a - th, v0, th, b, wall_h, STONE)
    merlons(d, iso, u0 + a - th, v0, th, b, wall_h)
    box(d, iso, u0, v0 + b - th, a, th, wall_h, STONE)
    merlons(d, iso, u0, v0 + b - th, a, th, wall_h)
    gu = u0 + a / 2 - 1.5
    box(d, iso, gu, v0 + b - 1.5, 3, 2, wall_h + 40, STONE)
    merlons(d, iso, gu, v0 + b - 1.5, 3, 2, wall_h + 40)
    face_v(d, iso, gu + 0.9, gu + 2.1, v0 + b + 0.5, 0, 72, DOOR)
    box(d, iso, u0 + a - 2, v0 + b - 2, tower, tower, tower_h, STONE)
    merlons(d, iso, u0 + a - 2, v0 + b - 2, tower, tower, tower_h)


def tree(d, iso, u, v, h=70, r=26):
    x, y = iso.p(u + 0.5, v + 0.5)
    d.rectangle([x - 3, y - 26, x + 3, y], fill=(96, 62, 34), outline=OUTLINE)
    d.ellipse([x - r, y - h - r // 2, x + r, y - h + r + 6], fill=(70, 112, 52), outline=OUTLINE)
    d.ellipse([x - r + 8, y - h - r // 2 + 4, x + 4, y - h + 6], fill=(98, 140, 66))


def sprite(img, path, frame, feet_xy, anchor):
    im = Image.open(path).convert("RGBA")
    fh = im.size[1]
    if frame is not None:
        im = im.crop((frame * fh, 0, frame * fh + fh, fh))
    img.alpha_composite(im, (feet_xy[0] - anchor[0], feet_xy[1] - anchor[1]))


LOOKS = {  # pelo, piel, ropa principal, ropa secundaria (la identidad H8 va en clave dentro del sprite)
    "artisan_m": ((70, 46, 28), (226, 180, 140), (150, 52, 40), (196, 160, 90)),
    "artisan_f": ((150, 90, 40), (236, 196, 160), (60, 96, 70), (200, 180, 120)),
    "townsfolk_f": ((40, 30, 24), (200, 150, 110), (70, 90, 140), (220, 200, 160)),
    "townsfolk_m": ((120, 80, 40), (230, 186, 150), (110, 120, 60), (150, 110, 70)),
    "worker_m": ((30, 24, 20), (170, 120, 84), (120, 90, 60), (180, 150, 100)),
    "worker_f": ((200, 150, 70), (236, 196, 160), (140, 60, 90), (200, 180, 140)),
}


def unkey(im, col):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 254:
                region = int(round(b / 50.0))
                base = col[min(max(region, 1), 4) - 1]
                k = r / 127.5
                px[x, y] = (min(255, int(base[0] * k)), min(255, int(base[1] * k)), min(255, int(base[2] * k)), 255)
    return im


def person(img, iso, u, v, who="artisan_m", dirn="s", frame=0):
    im = Image.open(os.path.join(ART, "characters", who, f"idle_{dirn}.png")).convert("RGBA").crop((0, 0, 68, 68))
    im = unkey(im, LOOKS.get(who, LOOKS["artisan_m"]))
    x, y = iso.p(u + 0.5, v + 0.5)
    img.alpha_composite(im, (x - 34, y - 58))


# --- Suelo ----------------------------------------------------------------------------------------
_tiles = {}


def tile(kind):
    if kind not in _tiles:
        _tiles[kind] = Image.open(os.path.join(ART, "tiles", f"{kind}.png")).convert("RGBA")
    return _tiles[kind]


def ground(img, iso, grid):
    """grid: lista de filas (v) de cadenas (u): g hierba, s calle, p plaza, d tierra, f campo, w agua, b puente."""
    kinds = {"g": "grass", "s": "street", "p": "plaza", "d": "dirt", "f": "field_summer", "w": "water", "b": "bridge"}
    n = len(grid)
    for v in range(-24, n + 24):  # halo de hierba (o de lo que llegue al borde) para que no se vea el vacío
        for u in range(-24, n + 24):
            if 0 <= v < n and 0 <= u < len(grid[v]):
                continue
            ch = grid[min(max(v, 0), n - 1)][min(max(u, 0), len(grid[0]) - 1)]
            ch = ch if ch in "wsd" and (0 <= v < n or 0 <= u < len(grid[0])) else "g"
            x, y = iso.p(u, v)
            img.alpha_composite(tile(kinds.get(ch, "grass")), (x - 32, y))
    for v, row in enumerate(grid):
        for u, ch in enumerate(row):
            x, y = iso.p(u, v)
            img.alpha_composite(tile(kinds.get(ch, "grass")), (x - 32, y))


# --- Láminas --------------------------------------------------------------------------------------
def label(d, xy, text, size=14, fill=(240, 228, 200), bold=False, anchor="ma"):
    d.text(xy, text, font=font(size, bold), fill=fill, anchor=anchor)


def elevation_sheet():
    """01: alzado de alturas. Real a 28 px/m frente al juego de hoy y la propuesta, todo a 1:1."""
    real = [  # (nombre, alto m, ancho m, forma)
        ("persona\n1,7 m", 1.7, 0.5, "person"),
        ("casa entramado\n2-3 plantas, 9,5 m", 9.5, 7, "house"),
        ("muralla\n10 m", 10, 12, "wall"),
        ("torre del\nhomenaje 30 m", 30, 12, "keep"),
        ("iglesia de pueblo\ntorre 32 m", 32, 8, "church"),
        ("catedral gótica\ntorres 90 m", 90, 40, "cathedral"),
    ]
    prop = [  # (nombre, alto px, ancho px, forma)
        ("persona", 48, 18, "person"),
        ("casa 1 planta", 129, 110, "house"),
        ("casa 2 plantas", 176, 120, "house"),
        ("casa 3 plantas", 246, 128, "house"),
        ("muralla", 170, 200, "wall"),
        ("torre homenaje", 300, 170, "keep"),
        ("iglesia", 320, 130, "church"),
        ("catedral", 400, 260, "cathedral"),
    ]
    hoy = [("persona", 48, 18, "person"), ("casa hoy (house_b)", 158, 0, "sprite:house_b"),
           ("ayuntamiento ×1,6", 0, 0, "sprite:town_hall")]
    gap = 60
    widths_real = [max(int(w * PX_M), 18) for _, _, w, _ in real]
    W = 120 + sum(widths_real) + gap * len(real) + 160 + 700 + 160 + sum(p[2] for p in prop) + gap * len(prop) + 500
    H = int(90 * PX_M) + 260
    img = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(img)
    base = H - 90
    # líneas de pantalla
    for hpx, txt in [(540, "540 px: alto de la pantalla a zoom 1"), (270, "270 px: alto de la pantalla a zoom 2"),
                     (400, "400 px: tope propuesto para un monumento")]:
        col = (200, 80, 80, 255) if hpx != 400 else (200, 170, 70, 255)
        for x in range(0, W, 12):
            d.line([(x, base - hpx), (x + 6, base - hpx)], fill=col, width=2)
    d.line([(0, base), (W, base)], fill=(120, 100, 80, 255), width=2)

    def shape(x, w, h, kind, fill):
        y = base
        if kind == "person":
            d.ellipse([x + w // 2 - 5, y - h, x + w // 2 + 5, y - h + 10], fill=fill, outline=OUTLINE)
            d.rectangle([x + 2, y - h + 10, x + w - 2, y], fill=fill, outline=OUTLINE)
        elif kind == "house":
            wall = int(h * 0.62)
            d.rectangle([x, y - wall, x + w, y], fill=fill, outline=OUTLINE)
            poly(d, [(x - 4, y - wall), (x + w + 4, y - wall), (x + w // 2, y - h)], ROOF_RED[0])
        elif kind == "wall":
            d.rectangle([x, y - int(h * 0.9), x + w, y], fill=fill, outline=OUTLINE)
            m = max(4, w // 10)
            for k in range(0, w, 2 * m):
                d.rectangle([x + k, y - h, x + k + m, y - int(h * 0.9)], fill=fill, outline=OUTLINE)
        elif kind == "keep":
            d.rectangle([x, y - int(h * 0.94), x + w, y], fill=fill, outline=OUTLINE)
            m = max(4, w // 8)
            for k in range(0, w, 2 * m):
                d.rectangle([x + k, y - h, x + k + m, y - int(h * 0.94)], fill=fill, outline=OUTLINE)
        elif kind == "church":
            tw = w * 0.35
            nave = int(h * 0.3)
            d.rectangle([x + tw, y - nave, x + w, y], fill=fill, outline=OUTLINE)
            poly(d, [(x + tw, y - nave), (x + w, y - nave), (x + (tw + w) / 2, y - int(h * 0.47))], ROOF_SLATE[0])
            d.rectangle([x, y - int(h * 0.72), x + tw, y], fill=fill, outline=OUTLINE)
            poly(d, [(x, y - int(h * 0.72)), (x + tw, y - int(h * 0.72)), (x + tw / 2, y - h)], ROOF_SLATE[0])
        elif kind == "cathedral":
            tw = w * 0.22
            nave = int(h * 0.36)
            d.rectangle([x + tw, y - nave, x + w - tw, y], fill=fill, outline=OUTLINE)
            poly(d, [(x + tw, y - nave), (x + w - tw, y - nave), (x + w / 2, y - int(h * 0.5))], ROOF_SLATE[0])
            for tx in (x, x + w - tw):
                d.rectangle([tx, y - int(h * 0.7), tx + tw, y], fill=fill, outline=OUTLINE)
                poly(d, [(tx, y - int(h * 0.7)), (tx + tw, y - int(h * 0.7)), (tx + tw / 2, y - h)], ROOF_SLATE[0])

    x = 80
    label(d, (x, 30), "REAL a la escala del personaje (48 px = 1,7 m -> 28 px/m)", 26, bold=True, anchor="la")
    for (name, hm, wm, kind), wpx in zip(real, widths_real):
        hpx = int(hm * PX_M)
        shape(x, wpx, hpx, kind, STONE[0] if kind not in ("house", "person") else WALL[0])
        label(d, (x + wpx / 2, base + 10), name, 15)
        label(d, (x + wpx / 2, base - hpx - 26), f"{hpx} px", 16, bold=True)
        x += wpx + gap
    x += 120
    label(d, (x, 30), "HOY (sprites del juego)", 26, bold=True, anchor="la")
    hx = x
    # persona y sprites reales
    person_img = unkey(Image.open(os.path.join(ART, "characters", "artisan_m", "idle_s.png")).convert("RGBA").crop((0, 0, 68, 68)), LOOKS["artisan_m"])
    img.alpha_composite(person_img, (hx - 34 + 10, base - 58))
    label(d, (hx + 10, base + 10), "persona\n48 px", 15)
    hx += 80
    hb = Image.open(os.path.join(ART, "buildings", "house_b.png")).convert("RGBA")
    img.alpha_composite(hb, (hx, base - 166))
    label(d, (hx + 96, base + 10), "casa de 2 plantas hoy\n158 px en pantalla, ~120 de alzado\n(planta: 34 px, puerta 40)", 15)
    label(d, (hx + 96, base - 186), "158 px", 16, bold=True)
    hx += 230
    th = Image.open(os.path.join(ART, "buildings", "town_hall.png")).convert("RGBA")
    th = th.resize((int(192 * 1.6), int(192 * 1.6)), Image.NEAREST)
    img.alpha_composite(th, (hx, base - int(181 * 1.6)))
    label(d, (hx + 154, base + 10), "ayuntamiento ×1,6\n(píxel de 1,6: densidad mezclada)", 15)
    label(d, (hx + 154, base - int(171 * 1.6) - 26), f"{int(171 * 1.6)} px", 16, bold=True)
    x = hx + 360
    label(d, (x, 30), "PROPUESTA (densidad única 1:1)", 26, bold=True, anchor="la")
    for name, hpx, wpx, kind in prop:
        shape(x, wpx, hpx, kind, STONE[0] if kind not in ("house", "person") else WALL[0])
        label(d, (x + wpx / 2, base + 10), name, 15)
        label(d, (x + wpx / 2, base - hpx - 26), f"{hpx} px · {hpx / CHAR_PX:.1f}×", 16, bold=True)
        x += wpx + gap
    img = img.crop((0, 0, min(W, x + 400), H))
    d = ImageDraw.Draw(img)
    for hpx, txt in [(540, "540 px: alto de la pantalla a zoom 1"), (270, "270 px: alto de la pantalla a zoom 2"),
                     (400, "400 px: tope propuesto para un monumento")]:
        col = (200, 80, 80, 255) if hpx != 400 else (200, 170, 70, 255)
        label(d, (img.width - 20, base - hpx - 22), txt, 16, col, anchor="ra")
    img.save(os.path.join(OUT, "01_alturas_real_hoy_propuesta.png"))


def alignment_sheet():
    """02: alineación iso a 1:1: personaje, casa hoy (bloque y sprite), casa propuesta, iglesia, catedral, castillo."""
    W, H = 3300, 980
    img = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(img)
    groundy = 860
    label(d, (30, 24), "Alineación a 1:1 (1 px de arte = 1 px lógico). Mismo contorno de 1 px. Casilla 64×32.", 24,
          bold=True, anchor="la")

    # cada pieza con su origen iso; las bases quedan sobre la misma línea (esquina delantera en groundy)
    def at(x, a, b):
        # origen tal que la esquina delantera (a, b) caiga en (x, groundy)
        return Iso(x - (a - b) * TW / 2, groundy - (a + b) * TH / 2)

    x = 60
    iso = at(x, 1, 1)
    person(img, iso, 0, 0)
    label(d, (x, groundy + 20), "personaje\n48 px", 16)
    x += 170
    # casa de hoy como bloque medido: 3×3, muros 68 (2 plantas de 34), cumbrera 158
    iso = at(x, 3, 3)
    box(d, iso, 0, 0, 3, 3, 68, WALL, top=False)
    gable(d, iso, 0, 0, 3, 3, 68, 50, "v")
    for z in (34,):
        d.line([iso.p(0, 3, z), iso.p(3, 3, z)], fill=TIMBER, width=2)
    face_v(d, iso, 1.0, 1.55, 3, 0, 40, DOOR)
    person(img, at(x + 70, 1, 1), 0, 0)
    label(d, (x, groundy + 20), "casa HOY (bloque medido)\nplanta 34 px · puerta 40 px", 16)
    x += 300
    hb = Image.open(os.path.join(ART, "buildings", "house_b.png")).convert("RGBA")
    img.alpha_composite(hb, (x - 96, groundy - 166 - 0))
    person(img, at(x + 90, 1, 1), 0, 0)
    label(d, (x, groundy + 20), "casa HOY (sprite house_b)", 16)
    x += 330
    iso = at(x, 3, 3)
    top = house(d, iso, 0, 0, 3, 3, 2, along="u")
    person(img, at(x + 80, 1, 1), 0, 0)
    label(d, (x, groundy + 20), f"PROPUESTA B (recomendada)\n2 plantas 64 + 48 · puerta 52\ncumbrera {top} px", 16)
    x += 290
    iso = at(x, 3, 3)
    top = house(d, iso, 0, 0, 3, 3, 2, ground=72, upper=56, along="u")
    person(img, at(x + 80, 1, 1), 0, 0)
    label(d, (x, groundy + 20), f"propuesta C (alta)\n2 plantas 72 + 56 · puerta 56\ncumbrera {top} px", 16)
    x += 300
    iso = at(x, 4, 4)
    top = house(d, iso, 0, 0, 4, 4, 3, along="u", roof=ROOF_SLATE)
    person(img, at(x + 90, 1, 1), 0, 0)
    label(d, (x, groundy + 20), f"B: casa patricia 3 plantas\n{top} px", 16)
    x += 480
    iso = at(x, 14.5, 4)
    church(d, iso, 0, 0)
    person(img, at(x + 60, 1, 1), 0, 0)
    label(d, (x - 100, groundy + 20), "iglesia: torre 320 px, nave 120 + 90", 16)
    x += 760
    iso = at(x, 17, 6)
    cathedral(d, iso, 0, 0)
    person(img, at(x + 60, 1, 1), 0, 0)
    label(d, (x - 160, groundy + 20), "catedral: torres 400 px, nave 170 + 70", 16)
    img = img.crop((0, 0, x + 260, H))
    img.save(os.path.join(OUT, "02_alineacion.png"))

    # castillo en lámina aparte (más ancho)
    W2, H2 = 1500, 900
    c = Image.new("RGBA", (W2, H2), BG)
    d2 = ImageDraw.Draw(c)
    iso = Iso(560, 340)
    ground(c, iso, ["g" * 26 if not (12 <= v <= 14) else "g" * 6 + "s" * 20 for v in range(24)])
    castle(d2, iso, 0, 0)
    for k, (u, v) in enumerate([(7, 13), (9, 14), (12, 13.5)]):
        person(c, iso, u, v, ["artisan_m", "townsfolk_f", "worker_m"][k])
    house(d2, iso, 18, 16, 3, 3, 2)
    house(d2, iso, 13, 16, 3, 3, 1)
    label(d2, (30, 24), "Castillo a 1:1: muralla 160 px (+ almenas), torres 240, homenaje 300. Recinto 16×12 casillas.",
          22, bold=True, anchor="la")
    c.save(os.path.join(OUT, "03_castillo.png"))


# --- Maquetas de pantalla (960×540) ----------------------------------------------------------------
def scene_e(img, d, iso):
    """Pueblo-calle (E): calle de 3 casillas a lo largo de u, casas a ambos lados, forja, capilla al fondo."""
    N = 40
    grid = []
    for v in range(N):
        row = ""
        for u in range(N):
            if 13 <= v <= 15:
                row += "s" if 8 <= u <= 22 else "d"
            elif v in (4, 5, 6, 22, 23, 24) and (u < 8 or u > 26):
                row += "f"
            else:
                row += "g"
        grid.append(row)
    ground(img, iso, grid)
    objs = []
    for i, u in enumerate([1, 5, 9, 18, 22]):
        objs.append(("house", u, 9, 3, 3, [2, 1, 2, 2, 1][i]))
    objs.append(("forge", 13, 8, 4, 4, 1))
    for i, u in enumerate([2, 6, 10, 14, 18, 22]):
        objs.append(("house", u, 17, 3, 3, [1, 2, 2, 1, 2, 2][i]))
    objs.append(("chapel", 27, 12, 0, 0, 0))
    objs.append(("well", 16, 16, 1, 1, 0))
    for u, v in [(0, 19), (29, 8), (30, 19), (12, 4), (25, 21)]:
        objs.append(("tree", u, v, 1, 1, 0))
    people = [(12, 14, "artisan_m"), (16, 14, "townsfolk_f"), (20, 13, "worker_m"), (14, 15, "townsfolk_m"),
              (17, 12, "worker_f"), (24, 14, "artisan_f")]
    return objs, people


def scene_a(img, d, iso):
    """Plaza de mercado (A): plaza irregular con iglesia y ayuntamiento, casas de 2-3 plantas alrededor."""
    N = 30
    grid = []
    for v in range(N):
        row = ""
        for u in range(N):
            if 10 <= u <= 21 and 10 <= v <= 19:
                row += "p"
            elif 14 <= u <= 15 or 14 <= v <= 15:
                row += "s"
            else:
                row += "g"
        grid.append(row)
    ground(img, iso, grid)
    objs = [("church_small", 9, 4, 0, 0, 0), ("townhall", 22, 11, 4, 5, 3)]
    for u, v, fl in [(4, 10, 2), (4, 16, 3), (10, 20, 2), (16, 20, 3), (22, 17, 2), (17, 5, 2), (22, 5, 3)]:
        objs.append(("house", u, v, 3, 3, fl))
    objs += [("stall", 13, 12, 1, 1, 0), ("stall", 17, 12, 1, 1, 0), ("stall", 13, 17, 1, 1, 0)]
    people = [(15, 13, "artisan_m"), (12, 15, "townsfolk_f"), (18, 16, "worker_m"), (16, 17, "townsfolk_m"),
              (19, 11, "worker_f")]
    return objs, people


def scene_ac(img, d, iso):
    """A + C: plaza de mercado con iglesia y ayuntamiento, río con muelles, puente y casas de ladrillo."""
    N = 40
    grid = []
    for v in range(N):
        row = ""
        for u in range(N):
            if 21 <= v <= 23:
                row += "b" if 15 <= u <= 16 else "w"
            elif 9 <= u <= 19 and 8 <= v <= 16:
                row += "p"
            elif 15 <= u <= 16 or 12 <= v <= 13 or v == 20:
                row += "s"
            else:
                row += "g"
        grid.append(row)
    ground(img, iso, grid)
    objs = [("church_small", 7, 2, 0, 0, 0), ("townhall", 20, 9, 4, 5, 3)]
    for u, v, fl in [(3, 8, 2), (3, 14, 3), (20, 15, 2), (20, 2, 2)]:
        objs.append(("house", u, v, 3, 3, fl))
    for u in (4, 7, 10, 18, 21, 24):
        objs.append(("brickhouse", u, 17, 3, 3, 3))
    for u in (5, 11, 20):
        objs.append(("dock", u, 21, 2, 1, 0))
    for u in (6, 10, 19, 23):
        objs.append(("brickhouse", u, 25, 3, 3, 2))
    objs += [("stall", 11, 10, 1, 1, 0), ("stall", 13, 14, 1, 1, 0), ("stall", 17, 10, 1, 1, 0)]
    people = [(14, 12, "artisan_m"), (12, 13, "townsfolk_f"), (17, 14, "worker_m"), (15, 19, "townsfolk_m"),
              (16, 22, "worker_f"), (10, 15, "artisan_f")]
    return objs, people


def scene_cat(img, d, iso):
    """Catedral en su plaza, casas de 2-3 plantas alrededor."""
    N = 40
    grid = ["".join("p" if (4 <= u <= 28 and 3 <= v <= 18) else ("s" if v in (19, 20) else "g") for u in range(N))
            for v in range(N)]
    ground(img, iso, grid)
    objs = [("cathedral", 8, 8, 0, 0, 0)]
    for u, fl in [(3, 2), (7, 3), (11, 2), (15, 3), (19, 2), (23, 3), (27, 2)]:
        objs.append(("house", u, 21, 3, 3, fl))
    for v, fl in [(4, 2), (8, 3), (12, 2), (16, 2)]:
        objs.append(("house", 29, v, 3, 3, fl))
    objs += [("stall", 12, 16, 1, 1, 0), ("stall", 18, 17, 1, 1, 0), ("well", 24, 14, 1, 1, 0)]
    people = [(10, 17, "artisan_m"), (14, 18, "townsfolk_f"), (20, 16, "worker_m"), (25, 18, "townsfolk_m"),
              (6, 15, "worker_f")]
    return objs, people


def scene_castle(img, d, iso):
    """Castillo con muralla y torres, puerta, arrabal de casas a lo largo del camino de la puerta."""
    N = 44
    grid = ["".join("s" if (13 <= u <= 15 and v >= 17) else ("d" if (4 <= u <= 24 and 1 <= v <= 16) else "g")
                    for u in range(N)) for v in range(N)]
    ground(img, iso, grid)
    objs = [("castle", 6, 3, 0, 0, 0)]
    for v, fl in [(19, 2), (23, 1), (27, 2), (31, 2)]:
        objs.append(("house", 9, v, 3, 3, fl))
        objs.append(("house", 17, v, 3, 3, 2 if fl == 1 else 1))
    for u, v in [(2, 20), (24, 24), (27, 18), (4, 30)]:
        objs.append(("tree", u, v, 1, 1, 0))
    people = [(14, 18, "artisan_m"), (13, 22, "townsfolk_f"), (15, 25, "worker_m"), (14, 28, "townsfolk_m")]
    return objs, people


def scene_lineup(img, d, iso):
    """Catálogo: los tipos de edificio en fila sobre la misma calle, con personas delante (sin texto)."""
    N = 70
    grid = ["".join("s" if 12 <= v <= 13 else "g" for u in range(N)) for v in range(N)]
    ground(img, iso, grid)
    objs = [("house", 0, 8, 3, 3, 1), ("house", 4, 8, 3, 3, 2), ("house", 8, 7, 4, 4, 3), ("forge", 13, 7, 4, 4, 1),
            ("chapel", 18, 8, 0, 0, 0), ("wall_seg", 29, 10, 6, 1, 0), ("tower", 35, 8, 3, 3, 0),
            ("cathedral", 40, 4, 0, 0, 0)]
    people = [(2, 12, "artisan_m"), (6, 12, "townsfolk_f"), (10, 12, "worker_m"), (15, 12, "artisan_f"),
              (22, 12, "townsfolk_m"), (32, 12, "worker_f"), (37, 12, "artisan_m"), (45, 12, "townsfolk_f")]
    return objs, people


def draw_obj(img, d, iso, o):
    kind, u, v, a, b, fl = o
    if kind == "house":
        house(d, iso, u, v, a, b, fl, roof=ROOF_SLATE if fl == 3 else ROOF_RED)
    elif kind == "forge":
        house(d, iso, u, v, a, b, 1, ground=80, roof=ROOF_SLATE, wall=STONE)
        box(d, iso, u + a - 1, v + b - 1, 1, 1, 150, ((170, 84, 60), (130, 60, 44)))
    elif kind == "chapel":
        church(d, iso, u, v, nave_a=6, nave_b=3, wall_h=100, roof_r=70, tower=2, tower_h=210, spire=60)
    elif kind == "church_small":
        church(d, iso, u, v, nave_a=8, nave_b=4, wall_h=120, roof_r=90, tower=3, tower_h=250, spire=70)
    elif kind == "townhall":
        house(d, iso, u, v, a, b, fl, ground=80, upper=60, roof=ROOF_SLATE, wall=STONE)
    elif kind == "stall":
        box(d, iso, u + 0.1, v + 0.1, 0.8, 0.8, 26, WOOD)
        gable(d, iso, u, v, 1, 1, 40, 12, "u", ((200, 70, 60), (160, 50, 44)))
    elif kind == "tree":
        tree(d, iso, u, v)
    elif kind == "brickhouse":
        house(d, iso, u, v, a, b, fl, roof=ROOF_RED, along="v", wall=BRICK)
    elif kind == "dock":
        box(d, iso, u, v, a, b, 6, WOOD)
    elif kind == "cathedral":
        cathedral(d, iso, u, v)
    elif kind == "castle":
        castle(d, iso, u, v)
    elif kind == "wall_seg":
        box(d, iso, u, v, a, b, 160, STONE)
        merlons(d, iso, u, v, a, b, 160)
    elif kind == "tower":
        box(d, iso, u, v, a, b, 240, STONE)
        merlons(d, iso, u, v, a, b, 240)
    elif kind == "well":
        box(d, iso, u + 0.15, v + 0.15, 0.7, 0.7, 20, STONE)
        gable(d, iso, u + 0.1, v + 0.1, 0.8, 0.8, 52, 14, "u", ROOF_RED, WOOD)


def footprint(o):
    kind, u, v, a, b, _ = o
    if kind == "chapel":
        return u, v, 9.5, 3
    if kind == "church_small":
        return u, v, 12.5, 4
    if kind == "cathedral":
        return u, v - 1.5, 17, 9
    if kind == "castle":
        return u - 1, v - 1, 18, 14
    return u, v, max(a, 1), max(b, 1)


def depth_sort(objs):
    """Orden de dibujo: A antes que B si A queda entera detrás (u o v menores)."""
    items = list(objs)
    out = []
    while items:
        for i, a in enumerate(items):
            ua, va, aa, ba = footprint(a)
            blocked = False
            for j, b in enumerate(items):
                if i == j:
                    continue
                ub, vb, ab, bb = footprint(b)
                b_behind_a = (ub + ab <= ua) or (vb + bb <= va)
                a_behind_b = (ua + aa <= ub) or (va + ba <= vb)
                if b_behind_a and not a_behind_b:
                    blocked = True
                    break
            if not blocked:
                out.append(items.pop(i))
                break
        else:
            items.sort(key=lambda o: sum(footprint(o)[:2]))
            out.append(items.pop(0))
    return out


def render_scene(fn, center_uv, w=960, h=540, origin=(1500, 300), canvas=(3000, 2000)):
    big = Image.new("RGBA", canvas, BG)
    d = ImageDraw.Draw(big)
    iso = Iso(*origin)
    objs, people = fn(big, d, iso)
    for (u, v, who) in people:
        objs.append(("person", u, v, 1, 1, who))
    for o in depth_sort(objs):
        if o[0] == "person":
            person(big, iso, o[1], o[2], o[5])
        else:
            draw_obj(big, d, iso, o)
    cx, cy = iso.p(*center_uv)
    return big.crop((cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2))


def screen_sheets(refs):
    e = render_scene(scene_e, (18, 13), 960, 540)
    e.save(os.path.join(OUT, "04_pantalla_zoom1_pueblo_E.png"))
    z2 = e.crop((240, 135, 720, 405)).resize((960, 540), Image.NEAREST)
    z2.save(os.path.join(OUT, "05_pantalla_zoom2_pueblo_E.png"))
    a = render_scene(scene_a, (16, 14), 960, 540)
    a.save(os.path.join(OUT, "06_pantalla_zoom1_plaza_A.png"))
    # hoy: captura real del juego reducida a su tamaño lógico (1920×1080 -> 960×540, ×2 entero)
    cap = Image.open(os.path.join(ROOT, "docs", "novedades", "personajes_plaza_dia.png")).convert("RGBA")
    cap.resize((960, 540), Image.NEAREST).save(os.path.join(OUT, "07_pantalla_hoy_zoom1.png"))
    # vistas de 1920×1080 a 1:1: lo que se vería con un zoom «×½» (un píxel de arte = un píxel de pantalla a 1080p)
    ac = render_scene(scene_ac, (14, 12), 1920, 1080)
    ac.save(os.path.join(OUT, "08_vista1080_plaza_rio_AC.png"))
    cat = render_scene(scene_cat, (17, 10), 1920, 1080)
    cat.save(os.path.join(OUT, "09_vista1080_catedral.png"))
    cas = render_scene(scene_castle, (15, 11), 1920, 1080)
    cas.save(os.path.join(OUT, "10_vista1080_castillo.png"))
    # la catedral y el castillo a zoom 1 (960×540): no caben enteros
    render_scene(scene_cat, (17, 10), 960, 540).save(os.path.join(OUT, "12_pantalla_zoom1_catedral.png"))
    render_scene(scene_castle, (15, 12), 960, 540).save(os.path.join(OUT, "13_pantalla_zoom1_castillo.png"))
    lin = render_scene(scene_lineup, (27, 6), 2400, 1000, origin=(1200, 300), canvas=(5000, 2400))
    lin.save(os.path.join(OUT, "11_catalogo_edificios.png"))
    if refs:
        rd = os.path.join(ROOT, "tmp", "escala_refs")
        os.makedirs(rd, exist_ok=True)
        for n, im in [("E", e), ("A", a)]:
            im.resize((1920, 1080), Image.NEAREST).save(os.path.join(rd, f"ref_{n}.png"))
        render_scene(scene_e, (17, 13), 1920, 1080).save(os.path.join(rd, "ref_E_wide.png"))
        for n, im in [("AC", ac), ("cat", cat), ("castle", cas)]:
            im.save(os.path.join(rd, f"ref_{n}.png"))
        lin.save(os.path.join(rd, "ref_lineup.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refs", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    elevation_sheet()
    alignment_sheet()
    screen_sheets(args.refs)
    print("láminas en", OUT)


if __name__ == "__main__":
    main()
