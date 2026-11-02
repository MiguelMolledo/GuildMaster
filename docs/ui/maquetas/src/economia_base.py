"""Ayudas de las maquetas de las mecánicas de economía (docs/ui/mecanicas/_comun.md).

Regenerar todas: python3 tools/ui/maqueta.py docs/ui/maquetas/src/{forja_interior,produccion,almacen_y_personaje,mercado_y_libro,empleados,mejoras,parcelas_y_construccion}.py

Solo construyen listas de elementos para tools/ui/maqueta.py; no dibujan nada por su cuenta. Lo que el kit aún no
tiene (pieza de kit pendiente) se aproxima con cajas y textos y se nombra en el documento de cada mecánica.
Zonas (960×540): panel lateral x 600..952 · y 96..516 (352 de ancho); panel ancho (mejoras) x 396..952.
"""

import os as _os
import sys as _sys

_ROOT = _os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))))
_sys.path.insert(0, _os.path.join(_ROOT, "tools", "ui"))
from maqueta import text_size  # noqa: E402,F401

FONDO_FORJA = {"captura": "docs/novedades/ui_forja_despues.png", "oscurecer": 0.25, "desaturar": 0.2}
FONDO_MAPA = {"captura": "docs/ui/maquetas/fondos/mapa_dia.png", "oscurecer": 0.25, "desaturar": 0.2}

LAT_X, LAT_Y, LAT_W = 600, 96, 352
X = LAT_X + 8          # columna de contenido del panel lateral
CW = LAT_W - 16        # ancho de contenido (336)
ANCHO_X, ANCHO_W = 396, 556

I = "guild:icons/"
IT = "icono:"          # iconos de objeto del juego (assets/art/icons/<id>.png)
FAM_HERRERO = "#8b2e2e"
FAM_FERRER = "#3f6b3a"


def t(x, y, w, h, txt, fuente="cuerpo", color="texto", alinear="izq", valign="arriba", ajustar=True):
    return {"tipo": "texto", "rect": [x, y, w, h], "texto": txt, "fuente": fuente, "color": color,
            "alinear": alinear, "valign": valign, "ajustar": ajustar}


def ico(x, y, ref, s=16):
    return {"tipo": "icono", "rect": [x, y, s, s], "icono": ref}


def img(x, y, ref, w=0, h=0, escala=1):
    return {"tipo": "imagen", "rect": [x, y, w, h], "imagen": ref, "escala": escala}


def ret(x, y, ref, s=32, familia=None, marco="normal", tecla=None, cola=None):
    e = {"tipo": "retrato", "rect": [x, y, s, s], "imagen": "guild:portraits/" + ref, "marco": marco}
    if familia:
        e["familia"] = familia
    if tecla:
        e["tecla"] = tecla
    if cola:
        e["cola"] = cola
    return e


def btn(x, y, txt, w=0, h=16, estado="normal", icono=None, fuente="boton", tecla=None):
    e = {"tipo": "boton", "rect": [x, y, w, h], "texto": txt, "estado": estado, "fuente": fuente}
    if icono:
        e["icono"] = icono
    if tecla:
        e["tecla"] = tecla
    return e


def barra(x, y, w, h, v, color="oro", marca=None, texto=None):
    e = {"tipo": "barra", "rect": [x, y, w, h], "valor": v, "color": color}
    if marca is not None:
        e["marca"] = marca
    if texto:
        e["texto"] = texto
    return e


def caja(x, y, w, h, color="seccion", opacidad=1.0):
    return {"tipo": "caja", "rect": [x, y, w, h], "color": color, "opacidad": opacidad}


def sep(x, y, w, color="oro_oscuro"):
    return {"tipo": "separador", "rect": [x, y, w, 1], "color": color}


def panel(x, y, w, h, titulo=None, cerrar=True, estilo="madera"):
    e = {"tipo": "panel", "rect": [x, y, w, h], "estilo": estilo, "cerrar": cerrar}
    if titulo:
        e["titulo"] = titulo
    return e


def lateral(titulo, h=400, y=LAT_Y):
    return panel(LAT_X, y, LAT_W, h, titulo)


def pestanas(x, y, textos, activa=0):
    return {"tipo": "pestanas", "rect": [x, y, 0, 14], "textos": textos, "activa": activa}


def aviso(x, y, w, h, txt, gravedad="urgente", icono=None):
    e = {"tipo": "aviso", "rect": [x, y, w, h], "gravedad": gravedad, "texto": txt}
    if icono:
        e["icono"] = icono
    return e


def tooltip(x, y, w, titulo, lineas):
    return {"tipo": "tooltip", "rect": [x, y, w, 0], "titulo": titulo, "lineas": lineas}


def llamada(x, y, n):
    return {"tipo": "llamada", "pos": [x, y], "n": n}


def velo(op=0.55, rect=None):
    e = {"tipo": "velo", "opacidad": op}
    if rect:
        e["rect"] = rect
    return e


def motivo(x, y, w, txt):
    return t(x, y, w, 12, txt, "cuerpo", "negativo")


def filete(x, y, w, h, color="oro"):
    """Contorno de 1 px (pieza de kit pendiente: filete dorado de selección)."""
    return [caja(x, y, w, 1, color), caja(x, y + h - 1, w, 1, color), caja(x, y, 1, h, color),
            caja(x + w - 1, y, 1, h, color)]


def tramos(x, y, w, h, partes):
    """Barra de varios tramos [(fracción, color)] (pieza de kit pendiente: barra de calidad, previsión)."""
    out = [caja(x, y, w, h, "madera"), caja(x + 1, y + 1, w - 2, h - 2, "hueco")]
    cx = x + 1
    for i, (f, col) in enumerate(partes):
        pw = int(round((w - 2) * f)) if i < len(partes) - 1 else x + w - 1 - cx
        out.append(caja(cx, y + 1, max(0, pw), h - 2, col))
        cx += pw
    return out


def barra_ventana(x, y, w, h, progreso, desde, hasta, encendida=False, tocada=False):
    """Barra de ciclo con el tramo del toque de maestro (pieza de kit pendiente)."""
    out = [caja(x, y, w, h, "madera_oscura"), caja(x + 1, y + 1, w - 2, h - 2, "hueco")]
    iw = w - 2
    out.append(caja(x + 1 + int(iw * desde), y + 1, max(1, int(iw * (hasta - desde))), h - 2,
                    "oro_claro" if encendida else ("positivo" if tocada else "oro_oscuro")))
    out.append(caja(x + 1, y + 1, int(iw * progreso), h - 2, "positivo"))
    if progreso > desde:
        out.append(caja(x + 1 + int(iw * desde), y + 1, max(1, int(iw * (min(progreso, hasta) - desde))), h - 2,
                        "oro_claro" if encendida else "oro"))
    return out


def casilla(x, y, s=30, icono=None, n=None, calidad=0, estado="normal"):
    """Casilla de inventario (pieza de kit pendiente): vacía, con objeto, bloqueada o reservada."""
    out = [caja(x, y, s, s, "madera_oscura")]
    if estado == "reservada":
        for i in range(0, s, 4):
            out += [caja(x + i, y, 2, 1, "oro"), caja(x + i, y + s - 1, 2, 1, "oro"),
                    caja(x, y + i, 1, 2, "oro"), caja(x + s - 1, y + i, 1, 2, "oro")]
    out.append(caja(x + 1, y + 1, s - 2, s - 2, "hueco" if estado != "bloqueada" else "seccion"))
    if estado == "bloqueada":
        out.append(ico(x + (s - 16) // 2, y + (s - 16) // 2, I + "icon_locked.png"))
        out.append(caja(x + 1, y + 1, s - 2, s - 2, "velo", 0.45))
    if icono:
        out.append(ico(x + (s - 16) // 2, y + 3, icono))
        if estado == "reservada":
            out.append(caja(x + 1, y + 1, s - 2, s - 2, "velo", 0.35))
    if n is not None:
        out.append(t(x + 2, y + s - 10, s - 4, 9, str(n), "pequena", "texto", "der", "arriba", False))
    if calidad:
        col = "#c4c4b4" if calidad == 1 else "oro_claro"
        out += [caja(x + 2, y + 2, 4, 4, "hueco"), caja(x + 3, y + 3, 2, 2, col)]
    return out


def demanda(x, y, nivel, palabra, numero=None):
    """Indicador de demanda de 5 escalones (pieza de kit pendiente). nivel 1..5."""
    cols = {1: "negativo", 2: "aviso", 3: "pergamino", 4: "positivo", 5: "positivo"}
    out = []
    for i in range(5):
        hh = 2 + i * 2
        out.append(caja(x + i * 4, y + 10 - hh, 3, hh, cols[nivel] if i < nivel else "madera_oscura"))
    txt = palabra if numero is None else "%s %s" % (numero, palabra)
    out.append(t(x + 22, y, 90, 12, txt, "cuerpo", cols[nivel] if nivel != 3 else "texto_tenue"))
    return out


def selector(x, y, textos, activo, w=None, h=14):
    """Selector de N (pieza de kit pendiente): botones pegados, el activo pulsado con filete dorado."""
    out = []
    cx = x
    for i, s in enumerate(textos):
        bw = w if w else text_size(s, "cuerpo")[0] + 12
        out.append(btn(cx, y, s, bw, h, "pulsado" if i == activo else "normal", fuente="cuerpo"))
        if i == activo:
            out += filete(cx, y, bw, h)
        cx += bw + 1
    return out


def insignia(x, y, letra, color="negativo"):
    """Insignia de 9×9 sobre un botón (pieza de kit pendiente)."""
    return [caja(x, y, 9, 9, "hueco"), caja(x + 1, y + 1, 7, 7, color),
            t(x, y, 9, 9, letra, "pequena", "texto", "centro", "centro", False)]


def check(x, y, ok):
    """✓ / ✗ de requisito (pieza de kit pendiente), como texto coloreado."""
    if ok:
        return ico(x, y, I + "icon_completed.png", 12)
    return t(x + 2, y, 10, 12, "x", "negrita", "negativo")


def confirmacion(titulo, filas, boton, y=180, w=300):
    """Caja de confirmación centrada (280-300 de ancho) sobre velo; filas = [(etiqueta, valor, color)]."""
    x = (960 - w) // 2
    h = 34 + len(filas) * 14 + 30
    e = [velo(0.5), panel(x, y, w, h, titulo, False)]
    yy = y + 28
    for et, val, col in filas:
        if val is None:
            e.append(t(x + 10, yy, w - 20, 12, et, color=col or "texto"))
        else:
            e += [t(x + 10, yy, 116, 12, et, color="texto_tenue", ajustar=False),
                  t(x + 126, yy, w - 136, 12, val, "negrita", col or "texto", ajustar=False)]
        yy += 14
    e += [btn(x + w - 186, y + h - 24, boton, 96, estado="encima"), btn(x + w - 86, y + h - 24, "Cancelar", 76)]
    return e
