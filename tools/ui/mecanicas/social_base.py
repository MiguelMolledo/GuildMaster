"""Ayudas compartidas por las maquetas de las mecánicas sociales (docs/ui/mecanicas/_social.md).

Solo construyen listas de elementos para tools/ui/maqueta.py; no dibujan nada por su cuenta.
Zonas (960×540): panel lateral x 600..952 · y 96..516; tarjetas x 4..304 desde y 96; panel grande x 4..956 · y 52..520;
cartas centradas sobre velo.
"""

import os as _os
import sys as _sys

_sys.path.insert(0, _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))))
from maqueta import text_size  # noqa: E402

FONDO_PLAZA = {"captura": "docs/ui/maquetas/ciudad_viva_hoy_plaza.png", "oscurecer": 0.30, "desaturar": 0.25}
FONDO_AYTO = {"captura": "docs/novedades/ui_mapa_despues.png", "oscurecer": 0.30, "desaturar": 0.25}

LAT_X, LAT_Y, LAT_W = 600, 96, 352
TAR_X, TAR_Y, TAR_W = 4, 96, 300

# Colores de familia del escenario town_e_start (data/scenarios/town_e_start.json)
FAM = {
    "herrero": "#8b2e2e", "herrero2": "#c8a84e",
    "vidal": "#2e4f8b", "ferrer": "#3f6b3a", "ferrer2": "#b8b8b0",
    "soler": "#7a5230", "soler2": "#d8c8a0", "puig": "#4a6a8a", "serra": "#5a3a5a", "mas": "#4a5a2a",
}

R = "guild:portraits/"
I = "guild:icons/"
RET = {
    "hugo": R + "portrait_artesano.png", "agnes": R + "portrait_artesana.png", "pere": R + "portrait_nino.png",
    "clara": R + "portrait_nina.png", "marta": R + "portrait_aldeana.png", "elena": R + "portrait_mercader.png",
    "bernat": R + "portrait_patron.png", "joan": R + "portrait_aldeano.png", "isabel": R + "family/portrait_isabel.png",
    "diego": R + "family/portrait_diego.png", "alfonso": R + "family/portrait_alfonso.png",
    "elvira": R + "family/portrait_elvira.png", "lucia": R + "family/portrait_lucia.png",
    "erudito": R + "portrait_erudito.png", "picaro": R + "portrait_picaro.png",
}


def t(x, y, w, h, txt, fuente="cuerpo", color="texto", alinear="izq", valign="arriba", ajustar=True):
    return {"tipo": "texto", "rect": [x, y, w, h], "texto": txt, "fuente": fuente, "color": color,
            "alinear": alinear, "valign": valign, "ajustar": ajustar}


def ico(x, y, ref, s=16):
    return {"tipo": "icono", "rect": [x, y, s, s], "icono": ref}


def ret(x, y, who, s=32, familia=None, marco="normal", tecla=None, corona=False):
    e = {"tipo": "retrato", "rect": [x, y, s, s], "imagen": RET.get(who, who), "marco": marco}
    if familia:
        e["familia"] = FAM.get(familia, familia)
    if tecla:
        e["tecla"] = tecla
    if corona:
        e["corona"] = True
    return e


def btn(x, y, txt, w=0, h=16, estado="normal", icono=None, fuente="boton"):
    e = {"tipo": "boton", "rect": [x, y, w, h], "texto": txt, "estado": estado, "fuente": fuente}
    if icono:
        e["icono"] = icono
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


def lateral(titulo, h=380, y=LAT_Y):
    return panel(LAT_X, y, LAT_W, h, titulo)


def llamada(x, y, n):
    return {"tipo": "llamada", "pos": [x, y], "n": n}


def bipolar(x, y, w, h, v, color="positivo"):
    """Barra −100..+100 con el cero en medio: pieza de kit pendiente, aquí con cajas para la maqueta."""
    out = [caja(x, y, w, h, "madera"), caja(x + 1, y + 1, w - 2, h - 2, "hueco")]
    mid = x + w // 2
    span = int(round((w // 2 - 1) * abs(v) / 100.0))
    if v >= 0:
        out.append(caja(mid, y + 1, span, h - 2, color))
    else:
        out.append(caja(mid - span, y + 1, span, h - 2, "negativo"))
    out.append(caja(mid, y - 1, 1, h + 2, "texto"))
    return out


def bandera(x, y, w, h, c1, c2):
    """Estandarte de familia (pieza de kit pendiente): dos franjas verticales con borde de madera y punta."""
    out = [caja(x, y, w, h, "madera_oscura"), caja(x + 1, y + 1, w - 2, h - 4, FAM.get(c1, c1))]
    out.append(caja(x + 1 + (w - 2) // 3, y + 1, max(1, (w - 2) // 3), h - 4, FAM.get(c2, c2)))
    out.append(caja(x + 1, y + h - 3, (w - 2) // 2 - 1, 2, FAM.get(c1, c1)))
    out.append(caja(x + w // 2 + 1, y + h - 3, (w - 2) // 2 - 1, 2, FAM.get(c1, c1)))
    return out


def insignia(x, y, letra, color="oro"):
    """Insignia 8×8 (pieza de kit pendiente)."""
    return [caja(x, y, 9, 9, "hueco"), caja(x + 1, y + 1, 7, 7, color),
            t(x, y, 9, 9, letra, "pequena", "texto_tinta", "centro", "centro", False)]


def motivo(x, y, w, txt):
    return t(x, y, w, 12, txt, "cuerpo", "negativo")


def velo(op=0.55):
    return {"tipo": "velo", "opacidad": op}
