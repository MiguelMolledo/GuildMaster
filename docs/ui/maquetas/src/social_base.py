"""Ayudas compartidas por las maquetas de las mecánicas sociales (docs/ui/mecanicas/_social.md).

Solo construyen listas de elementos para tools/ui/maqueta.py; no dibujan nada por su cuenta.
Zonas: las del HUD propuesto (docs/ui/01_hud.md, hud.ZONAS). Panel de gestión = zona 5 [600, 58, 356, 430]; tarjetas
sociales en la columna izquierda (zona 4) bajo el objetivo plegado, x 4..240 desde y 112; pantallas grandes = modal
912×440 en [24, 58]; cartas y confirmaciones centradas sobre velo; la selección abajo (zona 6).
Las maquetas del panel lateral se escriben con LAT_Y = 96 (coordenada de diseño) y a_lateral() las sube a y 58.
"""

import os as _os
import sys as _sys

_ROOT = _os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))))
_sys.path.insert(0, _os.path.join(_ROOT, "tools", "ui"))
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from maqueta import text_size  # noqa: E402
import hud  # noqa: E402

FONDO_PLAZA = {"captura": "docs/ui/maquetas/fondos/plaza_dia.png", "oscurecer": 0.25, "desaturar": 0.2}
FONDO_AYTO = {"captura": "docs/ui/maquetas/fondos/mapa_dia.png", "oscurecer": 0.25, "desaturar": 0.2}

LAT_X, LAT_Y, LAT_W = 600, 96, 356
DY_LATERAL = hud.ZONAS["lateral"][1] - LAT_Y        # −38: de la coordenada de diseño a la zona 5
TAR_X, TAR_Y, TAR_W = 4, 112, 236                  # bajo el objetivo plegado (zona 4)
MODAL = [24, 58, 912, 440]                          # pantallas grandes (01_hud §4.7)

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
    return panel(LAT_X, y, LAT_W, min(h, 430), titulo)


def a_lateral(elementos, dy=None):
    """Sube los elementos de una maqueta de panel lateral de y 96 (diseño) a la zona 5 del HUD (y 58)."""
    dy = DY_LATERAL if dy is None else dy
    for e in elementos:
        if "rect" in e and e.get("tipo") != "velo":
            e["rect"] = [e["rect"][0], e["rect"][1] + dy] + list(e["rect"][2:])
        if "pos" in e:
            e["pos"] = [e["pos"][0], e["pos"][1] + dy]
    return elementos


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


def velo(op=0.55, desde=0):
    """desde=58: el velo de un modal grande deja a la vista el HUD de arriba (01_hud §4.7)."""
    return {"tipo": "velo", "opacidad": op, "rect": [0, desde, 960, 540 - desde]}


def oficio(oid):
    """Insignia de cargo del kit (12×12) por id de data/offices/."""
    alias = {"tax_collector": "collector", "market_inspector": "inspector"}
    return "ui:marks/badge_office_" + alias.get(oid, oid)


def titulo_ins(tid):
    return "ui:marks/badge_title_" + tid


SEL_HUGO = ("Hugo Herrero", "En la plaza · sin órdenes", "texto_tenue",
            (("Familia", "normal"), ("Inventario", "normal")), RET["hugo"])


def base_hud(sel=None, objetivo=True):
    """HUD propuesto (docs/ui/maquetas/src/hud.py): ficha, estado, reloj, objetivo plegado y selección."""
    el = hud.ficha(titulo="citizen", titulo_txt="Ciudadano", rep="60", oro="300") + hud.barra_estado() + hud.reloj()
    if objetivo:
        el += hud.objetivo(plegado=True)[0]
    if sel is not False:
        el += hud.seleccion(*(sel or SEL_HUGO))
    return el


def con_hud(maquetas):
    """Monta cada maqueta sobre el HUD propuesto. Claves opcionales de la maqueta: _sel (args de hud.seleccion o
    False) y _obj (objetivo plegado en la columna)."""
    for m in maquetas:
        m["elementos"] = base_hud(m.pop("_sel", None), m.pop("_obj", True)) + m["elementos"]
    return maquetas
