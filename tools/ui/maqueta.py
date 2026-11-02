#!/usr/bin/env python3
"""Maquetas de la UI a 960×540 (y ×2) con las piezas REALES del kit: los 9-patch de assets/art/ui/theme/ (los mismos
del theme del juego), las fuentes pixel de assets/art/ui/fonts/ y los colores de tools/ui/tokens.json. Sin créditos.

  python3 tools/ui/maqueta.py tools/ui/ejemplos/hud_ejemplo.json      → docs/ui/maquetas/hud_ejemplo.png (+ _x2.png)
  python3 tools/ui/maqueta.py a.json b.py --out /tmp/x --rejilla      → varias; --rejilla pinta la rejilla de 4/16 px
  python3 tools/ui/maqueta.py --piezas                                → lista de piezas, fuentes y colores

Entrada: un .json con una maqueta (o una lista), o un .py que define MAQUETA (dict) o MAQUETAS (lista). Desde Python:
  sys.path.insert(0, "tools/ui"); import maqueta; maqueta.render({"id": ..., "fondo": ..., "elementos": [...]})

Una maqueta: {"id", "fondo", "elementos": [...]}. fondo: {"color": token|#hex} o {"captura": ruta, "oscurecer": 0-1,
"desaturar": 0-1} (las capturas de docs/novedades/ son de 1920×1080 y se reducen a la mitad, píxel a píxel).
Cada elemento: {"tipo", "rect": [x, y, w, h], ...}; en el README están todos los tipos con sus claves.
Imágenes: "guild:<ruta>" = arte de Guild Renew (~/Code/guild/assets/sprites/ui, solo lectura; otra raíz con la
variable GUILD_UI), "icono:<id>" = assets/art/icons/<id>.png, "ui:<ruta>" = assets/art/ui/<ruta>.png (marks/seal,
cursor/cursor_arrow...), "pieza:<id>" = assets/art/ui/theme/<id>.png, y si no, ruta desde la raíz del repo.
"""
import argparse
import json
import os
import runpy
import sys

from PIL import Image, ImageDraw, ImageFont

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
THEME = os.path.join(ROOT, "assets", "art", "ui", "theme")
FONTS = os.path.join(ROOT, "assets", "art", "ui", "fonts")
OUT = os.path.join(ROOT, "docs", "ui", "maquetas")
GUILD_UI = os.environ.get("GUILD_UI", os.path.expanduser("~/Code/guild/assets/sprites/ui"))
W, H = 960, 540

sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
from dibujar_ui import PIECES  # noqa: E402  (margen 9-patch de cada pieza: una sola fuente de verdad)

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tokens.json"), encoding="utf-8") as _f:
    TOKENS = json.load(_f)

WARNINGS = []
_cache = {}


# ---------------------------------------------------------------- colores, fuentes, imágenes

def color(c, alpha=255):
    """Token de tokens.json ("oro"), "#rrggbb" o "#rrggbbaa"."""
    if isinstance(c, (list, tuple)):
        return tuple(c) if len(c) == 4 else tuple(c) + (alpha,)
    c = TOKENS["color"].get(c, c)
    h = c.lstrip("#")
    a = int(h[6:8], 16) if len(h) == 8 else alpha
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def font(role):
    """(ImageFont, alto de línea) de un papel de tokens.json ("cuerpo", "titulo"...) o de "fichero.ttf:tam"."""
    key = ("f", role)
    if key in _cache:
        return _cache[key]
    if ":" in role:
        name, size = role.rsplit(":", 1)
        spec = {"fichero": name, "tam": int(size), "alto_linea": int(size) + 2}
    else:
        spec = TOKENS["fuente"][role]
    f = ImageFont.truetype(os.path.join(FONTS, spec["fichero"]), spec["tam"])
    cap = -f.getbbox("H", anchor="ls")[1]   # altura de mayúscula sobre la línea base
    _cache[key] = (f, spec["alto_linea"], cap)
    return _cache[key]


def image(ref):
    if ref in _cache:
        return _cache[ref]
    if ref.startswith("guild:"):
        path = os.path.join(GUILD_UI, ref[6:])
    elif ref.startswith("icono:"):
        path = os.path.join(ROOT, "assets", "art", "icons", ref[6:] + ".png")
    elif ref.startswith("pieza:"):
        path = os.path.join(THEME, ref[6:] + ".png")
    elif ref.startswith("ui:"):
        path = os.path.join(ROOT, "assets", "art", "ui", ref[3:] + ".png")
    else:
        path = ref if os.path.isabs(ref) else os.path.join(ROOT, ref)
    if not os.path.exists(path):
        WARNINGS.append(f"no existe {ref} ({path}): dibujo un hueco con «?»")
        _cache[ref] = None
        return None
    _cache[ref] = Image.open(path).convert("RGBA")
    return _cache[ref]


def fit(img, w, h):
    """Escala píxel a píxel (NEAREST) a w×h."""
    return img if img.size == (w, h) else img.resize((max(1, w), max(1, h)), Image.NEAREST)


# ---------------------------------------------------------------- primitivas

def nine(canvas, piece, rect):
    """Dibuja una pieza 9-patch del kit estirando bordes y centro como StyleBoxTexture (modo STRETCH)."""
    img = image("pieza:" + piece)
    x, y, w, h = [int(v) for v in rect]
    if img is None:
        canvas.alpha_composite(Image.new("RGBA", (w, h), color("negativo")), (x, y))
        return
    m = PIECES.get(piece, max(1, min(img.size) // 4))
    mx, my = (m, m) if isinstance(m, int) else m
    iw, ih = img.size
    xs = [(0, mx, 0, mx), (mx, iw - mx, mx, w - mx), (iw - mx, iw, w - mx, w)]
    ys = [(0, my, 0, my), (my, ih - my, my, h - my), (ih - my, ih, h - my, h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            if dx1 > dx0 and dy1 > dy0 and sx1 > sx0 and sy1 > sy0:
                part = img.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST)
                canvas.alpha_composite(part, (x + dx0, y + dy0))


def fill(canvas, rect, c):
    x, y, w, h = [int(v) for v in rect]
    if w > 0 and h > 0:
        canvas.alpha_composite(Image.new("RGBA", (w, h), color(c) if not isinstance(c, tuple) else c), (x, y))


def wrap(text, f, width):
    lines = []
    for para in str(text).split("\n"):
        line = ""
        for word in para.split(" "):
            probe = (line + " " + word) if line else word
            if width <= 0 or f.getlength(probe) <= width or not line:
                line = probe
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def text(canvas, rect, txt, role="cuerpo", col="texto", align="izq", valign="arriba", wrap_=True, outline=None):
    """Texto nítido (sin suavizado) dentro de rect. Devuelve el alto usado."""
    f, lh, cap = font(role)
    x, y, w, h = [int(v) for v in rect]
    lines = wrap(txt, f, w if wrap_ else 0)
    total = lh * len(lines)
    if valign == "centro" and h > 0:
        top = y + (h - total) // 2
    elif valign == "abajo" and h > 0:
        top = y + h - total
    else:
        top = y
    d = ImageDraw.Draw(canvas)
    d.fontmode = "1"
    for i, line in enumerate(lines):
        base = top + i * lh + (lh + cap) // 2
        lw = f.getlength(line)
        lx = x + (w - lw) // 2 if align == "centro" else (x + w - lw if align == "der" else x)
        if outline:
            for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                d.text((lx + ox, base + oy), line, font=f, fill=color(outline), anchor="ls")
        d.text((lx, base), line, font=f, fill=color(col), anchor="ls")
    return total


def text_size(txt, role="cuerpo"):
    f, lh, _ = font(role)
    return int(f.getlength(txt)), lh


def paste(canvas, ref, rect):
    x, y, w, h = [int(v) for v in rect]
    img = image(ref)
    if img is None:
        fill(canvas, rect, "hueco")
        text(canvas, rect, "?", "negrita", "negativo", "centro", "centro")
        return
    canvas.alpha_composite(fit(img, w, h), (x, y))


# ---------------------------------------------------------------- elementos

def el_panel(c, e):
    style = e.get("estilo", "madera")
    r = e["rect"]
    if style == "madera":
        nine(c, "panel", r)
    elif style in ("pergamino", "parchment"):
        nine(c, "parchment", r)
    elif style == "oscuro":
        fill(c, r, "seccion")
        x, y, w, h = r
        fill(c, (x, y, w, 1), "madera_oscura")
        fill(c, (x, y + h - 1, w, 1), "madera_oscura")
        fill(c, (x, y, 1, h), "madera_oscura")
        fill(c, (x + w - 1, y, 1, h), "madera_oscura")
    elif style == "fila":
        fill(c, r, "fila")
    else:
        nine(c, style, r)
    if e.get("titulo"):
        x, y, w, _ = r
        ink = "texto_tinta" if style in ("pergamino", "parchment") else "oro"
        text(c, (x + 8, y + 6, w - 16, 14), e["titulo"], "titulo", ink)
        fill(c, (x + 8, y + 21, w - 16, 1), "oro_oscuro")
    if e.get("cerrar"):
        x, y, w, _ = r
        el_boton(c, {"rect": [x + w - 20, y + 5, 14, 14], "texto": "×", "fuente": "negrita"})


def el_boton(c, e):
    state = {"normal": "normal", "encima": "hover", "pulsado": "pressed", "desactivado": "disabled",
             "hover": "hover", "pressed": "pressed", "disabled": "disabled"}[e.get("estado", "normal")]
    x, y, w, h = e["rect"]
    role = e.get("fuente", "boton")
    if w <= 0:
        w = text_size(e.get("texto", ""), role)[0] + 12 + (18 if e.get("icono") else 0) + \
            (text_size(e["tecla"], "pequena")[0] + 3 if e.get("tecla") else 0)
    if h <= 0:
        h = TOKENS["medida"]["alto_boton"]
    nine(c, "button_" + state, (x, y, w, h))
    dy = 1 if state == "pressed" else 0
    ink = {"normal": "texto", "hover": "oro_claro", "pressed": "oro_claro", "disabled": "texto_apagado"}[state]
    kw = text_size(e["tecla"], "pequena")[0] + 3 if e.get("tecla") else 0
    ix = x + 6
    if e.get("icono"):
        s = min(16, h - 2)
        paste(c, e["icono"], (ix, y + (h - s) // 2 + dy, s, s))
        tx, tw = ix + s + 2, w - (ix + s + 2 - x) - 6
        text(c, (tx, y + dy, tw, h), e.get("texto", ""), role, ink, e.get("alinear", "izq"), "centro", False)
    else:
        text(c, (x, y + dy, w - kw, h), e.get("texto", ""), role, ink, "centro", "centro", False)
    if e.get("tecla"):   # atajo en la esquina de abajo a la derecha, p. ej. "L"
        text(c, (x + w - kw - 2, y + h - 11, kw, 9), e["tecla"], "pequena", "oro", "der", "arriba", False)
    return w


def el_pestana(c, e):
    x, y, w, h = e["rect"]
    on = bool(e.get("activa", False))
    if w <= 0:
        w = text_size(e.get("texto", ""), "cuerpo")[0] + 14
    nine(c, "tab_on" if on else "tab_off", (x, y, w, h if on else h - 1))
    text(c, (x, y + (0 if on else 1), w, h), e.get("texto", ""), "negrita" if on else "cuerpo",
         "oro_claro" if on else "texto_tenue", "centro", "centro", False)
    return w


def el_pestanas(c, e):
    """Fila de pestañas: {"rect": [x, y, 0, alto], "textos": [...], "activa": i}."""
    x, y, _, h = e["rect"]
    for i, t in enumerate(e["textos"]):
        x += el_pestana(c, {"rect": [x, y, 0, h], "texto": t, "activa": i == e.get("activa", 0)}) + 1


def el_barra(c, e):
    x, y, w, h = e["rect"]
    v = max(0.0, min(1.0, float(e.get("valor", 0.5))))
    fill(c, (x, y, w, h), "madera")
    fill(c, (x + 1, y + 1, w - 2, h - 2), "hueco")
    fw = int(round((w - 2) * v))
    col = e.get("color", "oro")
    fill(c, (x + 1, y + 1, fw, h - 2), col)
    if h >= 5 and fw > 0:   # brillo de un píxel arriba
        light = tuple(min(255, int(ch * 1.25)) for ch in color(col)[:3]) + (255,)
        fill(c, (x + 1, y + 1, fw, 1), light)
    if e.get("marca") is not None:   # una muesca (umbral, objetivo)
        mx = x + 1 + int(round((w - 2) * float(e["marca"])))
        fill(c, (mx, y, 1, h), "texto")
    if e.get("texto"):
        text(c, (x, y, w, h), e["texto"], e.get("fuente", "pequena"), "texto", "centro", "centro", False, "hueco")


def el_campo(c, e):
    x, y, w, h = e["rect"]
    nine(c, "field", e["rect"])
    t = e.get("texto", "")
    ink = "texto"
    if not t and e.get("vacio"):
        t, ink = e["vacio"], "texto_apagado"
    text(c, (x + 4, y, w - 8, h), t, "cuerpo", ink, e.get("alinear", "izq"), "centro", False)
    if e.get("cursor"):
        tw = text_size(t, "cuerpo")[0]
        fill(c, (x + 5 + tw, y + 3, 1, h - 6), "oro_claro")


def el_tooltip(c, e):
    x, y, w, h = e["rect"]
    f, lh, _ = font("cuerpo")
    lines = []
    for part in e.get("lineas", [e.get("texto", "")]):
        lines.append(part)
    body = "\n".join(lines)
    if h <= 0:
        h = len(wrap(body, f, w - 10)) * lh + 6 + (lh if e.get("titulo") else 0)
    nine(c, "tooltip", (x, y, w, h))
    ty = y + 3
    if e.get("titulo"):
        text(c, (x + 5, ty, w - 10, lh), e["titulo"], "negrita", "texto_tinta")
        ty += lh
    text(c, (x + 5, ty, w - 10, h - 6), body, "cuerpo", "texto_tinta")


def el_retrato(c, e):
    x, y, w, h = e["rect"]
    frame = {"normal": "portrait_normal", "activo": "portrait_active", "apagado": "portrait_dim",
             "muerto": "portrait_dim"}[e.get("marco", "normal")]
    fill(c, (x + 3, y + 3, w - 6, h - 6), e.get("fondo", "seccion"))
    if e.get("imagen"):
        paste(c, e["imagen"], (x + 3, y + 3, w - 6, h - 6))
    if e.get("familia"):   # color de la familia: un borde de 1 px por dentro del marco
        fc = color(e["familia"])
        fill(c, (x + 3, y + 3, w - 6, 1), fc)
        fill(c, (x + 3, y + h - 4, w - 6, 1), fc)
        fill(c, (x + 3, y + 3, 1, h - 6), fc)
        fill(c, (x + w - 4, y + 3, 1, h - 6), fc)
    if e.get("marco") == "muerto":
        fill(c, (x + 3, y + 3, w - 6, h - 6), color("velo", 140))
    nine(c, frame, (x, y, w, h))
    if e.get("tecla"):
        fill(c, (x + w - 9, y + h - 10, 8, 9), "hueco")
        text(c, (x + w - 9, y + h - 10, 8, 9), e["tecla"], "pequena", "oro_claro", "centro", "centro", False)
    if e.get("corona"):
        paste(c, "guild:icons/icon_crown.png", (x + w - 12, y - 6, 16, 16))
    if e.get("cola"):   # órdenes en cola (pausa activa): número sobre el retrato
        fill(c, (x - 1, y - 1, 10, 10), "oro")
        text(c, (x - 1, y - 1, 10, 10), str(e["cola"]), "pequena", "texto_tinta", "centro", "centro", False)


def el_icono(c, e):
    paste(c, e["icono"], e["rect"])


def el_imagen(c, e):
    """Cualquier PNG; "recorte": [x, y, w, h] en píxeles de la imagen; "escala" si w/h = 0 (0.5 para capturas ×2)."""
    x, y, w, h = e["rect"]
    img = image(e["imagen"])
    if img is None:
        paste(c, e["imagen"], (x, y, max(w, 16), max(h, 16)))
        return
    if e.get("recorte"):
        rx, ry, rw, rh = e["recorte"]
        img = img.crop((rx, ry, rx + rw, ry + rh))
    if w <= 0 or h <= 0:
        k = float(e.get("escala", 1))
        w, h = int(img.width * k), int(img.height * k)
    c.alpha_composite(fit(img, w, h), (int(x), int(y)))


def el_texto(c, e):
    text(c, e["rect"], e.get("texto", ""), e.get("fuente", "cuerpo"), e.get("color", "texto"), e.get("alinear", "izq"),
         e.get("valign", "arriba"), e.get("ajustar", True), e.get("contorno"))


def el_separador(c, e):
    x, y, w, _ = e["rect"]
    fill(c, (x, y, w, 1), e.get("color", "oro_oscuro"))


def el_fila(c, e):
    """Fila de lista: icono · texto · valor a la derecha. seleccionada → fondo de madera y texto oro."""
    x, y, w, h = e["rect"]
    sel = e.get("seleccionada", False)
    if sel:
        fill(c, e["rect"], "madera")
        fill(c, (x, y, 1, h), "oro")
    elif e.get("fondo", True):
        fill(c, e["rect"], "fila")
    tx = x + 3
    if e.get("icono"):
        s = min(16, h - 2)
        paste(c, e["icono"], (tx, y + (h - s) // 2, s, s))
        tx += s + 3
    ink = "texto_apagado" if e.get("apagada") else ("oro_claro" if sel else e.get("color", "texto"))
    if e.get("valor") is not None:
        vw = text_size(str(e["valor"]), "cuerpo")[0]
        text(c, (x + w - vw - 4, y, vw + 1, h), str(e["valor"]), e.get("fuente_valor", "cuerpo"),
             e.get("color_valor", "texto"), "der", "centro", False)
        text(c, (tx, y, w - (tx - x) - vw - 8, h), e.get("texto", ""), "cuerpo", ink, "izq", "centro", False)
    else:
        text(c, (tx, y, w - (tx - x) - 3, h), e.get("texto", ""), "cuerpo", ink, "izq", "centro", False)


def el_lista(c, e):
    x, y, w, _ = e["rect"]
    icons = any(isinstance(r, dict) and r.get("icono") for r in e["filas"])
    rh = e.get("alto_fila", TOKENS["medida"]["alto_fila_icono" if icons else "alto_fila"])
    for i, row in enumerate(e["filas"]):
        row = row if isinstance(row, dict) else {"texto": row}
        el_fila(c, dict(row, rect=[x, y + i * (rh + 1), w, rh], seleccionada=i == e.get("seleccionada", -1)))


def el_aviso(c, e):
    """Aviso emergente (toast): panel oscuro con franja de gravedad a la izquierda e icono."""
    x, y, w, h = e["rect"]
    g = e.get("gravedad", "info")
    col = {"info": "info", "aviso": "aviso", "urgente": "negativo", "bien": "positivo"}[g]
    fill(c, (x, y, w, h), "hueco")
    fill(c, (x + 1, y + 1, w - 2, h - 2), "seccion")
    fill(c, (x + 1, y + 1, 3, h - 2), col)
    tx = x + 8
    if e.get("icono"):
        paste(c, e["icono"], (tx, y + (h - 16) // 2, 16, 16))
        tx += 20
    text(c, (tx, y + 2, w - (tx - x) - 4, h - 4), e.get("texto", ""), "cuerpo", "texto", "izq", "centro")


def el_velo(c, e):
    fill(c, e.get("rect", [0, 0, W, H]), color(e.get("color", "velo"), int(255 * float(e.get("opacidad", 0.6)))))


def el_caja(c, e):
    fill(c, e["rect"], color(e.get("color", "seccion"), int(255 * float(e.get("opacidad", 1.0)))))


def el_pieza(c, e):
    nine(c, e["pieza"], e["rect"])


def el_zona(c, e):
    """Zona de pantalla para diagramas: relleno translúcido, borde punteado y nombre."""
    x, y, w, h = e["rect"]
    col = color(e.get("color", "info"))
    fill(c, (x, y, w, h), col[:3] + (60,))
    for i in range(0, w, 4):
        fill(c, (x + i, y, 2, 1), col)
        fill(c, (x + i, y + h - 1, 2, 1), col)
    for i in range(0, h, 4):
        fill(c, (x, y + i, 1, 2), col)
        fill(c, (x + w - 1, y + i, 1, 2), col)
    if e.get("texto"):
        text(c, (x + 3, y + 2, w - 6, h - 4), e["texto"], e.get("fuente", "negrita"), "texto", "izq", "arriba", True, "hueco")


def el_llamada(c, e):
    """Número de referencia para el texto del documento (círculo de oro)."""
    x, y = e["pos"] if "pos" in e else e["rect"][:2]
    n = str(e["n"])
    w = 11 if len(n) == 1 else 15
    fill(c, (x + 1, y, w - 2, 11), "hueco")
    fill(c, (x, y + 1, w, 9), "hueco")
    fill(c, (x + 2, y + 1, w - 4, 9), "oro")
    fill(c, (x + 1, y + 2, w - 2, 7), "oro")
    text(c, (x, y, w, 11), n, "pequena", "texto_tinta", "centro", "centro", False)


TYPES = {
    "panel": el_panel, "boton": el_boton, "pestana": el_pestana, "pestanas": el_pestanas, "barra": el_barra,
    "campo": el_campo, "tooltip": el_tooltip, "retrato": el_retrato, "icono": el_icono, "imagen": el_imagen,
    "texto": el_texto, "separador": el_separador, "fila": el_fila, "lista": el_lista, "aviso": el_aviso,
    "velo": el_velo, "caja": el_caja, "pieza": el_pieza, "zona": el_zona, "llamada": el_llamada,
}


# ---------------------------------------------------------------- maqueta

def background(spec):
    bg = spec.get("fondo", {"color": "hueco"})
    if isinstance(bg, str):
        bg = {"captura": bg} if bg.endswith(".png") else {"color": bg}
    if "captura" in bg:
        img = image(bg["captura"])
        if img is None:
            return Image.new("RGBA", (W, H), color("hueco"))
        if bg.get("recorte"):
            x, y, w, h = bg["recorte"]
            img = img.crop((x, y, x + w, y + h))
        img = img.resize((W, H), Image.NEAREST) if img.size == (W * 2, H * 2) else fit(img, W, H)
        if bg.get("desaturar"):
            gray = img.convert("L").convert("RGBA")
            img = Image.blend(img, gray, float(bg["desaturar"]))
        if bg.get("oscurecer"):
            img.alpha_composite(Image.new("RGBA", (W, H), color("velo", int(255 * float(bg["oscurecer"])))))
        return img.copy()
    return Image.new("RGBA", (W, H), color(bg.get("color", "hueco")))


def grid(canvas):
    for x in range(0, W, 4):
        fill(canvas, (x, 0, 1, H), (255, 255, 255, 40 if x % 16 == 0 else 14))
    for y in range(0, H, 4):
        fill(canvas, (0, y, W, 1), (255, 255, 255, 40 if y % 16 == 0 else 14))


def render(spec, out=OUT, show_grid=False, save=True):
    """Compone una maqueta. Devuelve la imagen (960×540, u otro "tam": [w, h] para láminas); con save escribe
    <out>/<id>.png y <id>_x2.png."""
    global W, H
    W, H = spec.get("tam", [960, 540])
    canvas = background(spec)
    for e in spec.get("elementos", []):
        kind = e.get("tipo")
        if kind not in TYPES:
            raise SystemExit(f"{spec.get('id')}: tipo desconocido «{kind}» (vale: {', '.join(sorted(TYPES))})")
        TYPES[kind](canvas, e)
    if show_grid:
        grid(canvas)
    if save:
        os.makedirs(out, exist_ok=True)
        base = os.path.join(out, spec["id"])
        canvas.convert("RGB").save(base + ".png")
        canvas.convert("RGB").resize((W * 2, H * 2), Image.NEAREST).save(base + "_x2.png")
        print(f"  {os.path.relpath(base, ROOT)}.png (+ _x2)")
    return canvas


def load(path):
    if path.endswith(".py"):
        ns = runpy.run_path(path)
        return ns["MAQUETAS"] if "MAQUETAS" in ns else [ns["MAQUETA"]]
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, list) else [data]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("entradas", nargs="*")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--rejilla", action="store_true")
    ap.add_argument("--piezas", action="store_true")
    a = ap.parse_args()
    if a.piezas:
        print("piezas 9-patch:", ", ".join(f"{k} ({v})" for k, v in PIECES.items()))
        print("fuentes:", ", ".join(f"{k}={v['fichero']}:{v['tam']}" for k, v in TOKENS["fuente"].items()))
        print("colores:", ", ".join(TOKENS["color"]))
        print("tipos:", ", ".join(sorted(TYPES)))
        return
    if not a.entradas:
        ap.error("falta al menos una maqueta (.json o .py)")
    for p in a.entradas:
        for spec in load(p):
            render(spec, a.out, a.rejilla)
    for w in dict.fromkeys(WARNINGS):
        print("aviso:", w)


if __name__ == "__main__":
    main()
