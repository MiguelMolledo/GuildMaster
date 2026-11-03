"""Maquetas de docs/ui/mecanicas/parcelas_y_construccion.md (H6, sin hacer).
python3 tools/ui/maqueta.py docs/ui/maquetas/src/parcelas_y_construccion.py

Las parcelas se pintan con los rombos de Guild Renew (parcels/parcel_<tipo>.png, 64×32) en posiciones de ejemplo:
encima de las manzanas de atrezo, que es justo lo que H6 convierte en parcelas. El gris de «ocupada» no existe aún
(pieza de kit pendiente): las ocupadas se marcan con el banderín de la familia.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from economia_base import (CW, hud, hud_mapa, panel, FAM_FERRER, FAM_HERRERO, FONDO_MAPA, I, LAT_X, LAT_Y, X, btn, caja, confirmacion,  # noqa
                           filete, ico, img, lateral, llamada, motivo, sep, t, tooltip, velo)

P = "guild:parcels/parcel_"


def parcela(ox, oy, cols, rows, tipo):
    """Rombos de una parcela: casilla (c, r) con su vértice de arriba en (ox + (c - r) × 32, oy + (c + r) × 16)."""
    out = []
    for r in range(rows):
        for c in range(cols):
            x = ox + (c - r) * 32
            y = oy + (c + r) * 16
            out.append(img(x - 32, y, P + tipo + ".png", 64, 32))
    return out


def contorno(ox, oy, cols, rows, color="oro_claro"):
    """Filete del rombo de la huella (pieza de kit pendiente): aquí, puntos sobre las 4 aristas."""
    out = []
    pts = [((0, 0), (cols, 0)), ((cols, 0), (cols, rows)), ((cols, rows), (0, rows)), ((0, rows), (0, 0))]
    for (c0, r0), (c1, r1) in pts:
        n = 24
        for i in range(n + 1):
            c = c0 + (c1 - c0) * i / n
            r = r0 + (r1 - r0) * i / n
            out.append(caja(int(ox + (c - r) * 32) - 1, int(oy + (c + r) * 16) - 1, 2, 2, color))
    return out


def banderin(x, y, c1, c2="oro"):
    """Banderín de familia 8×12 (pieza de kit pendiente)."""
    return [caja(x, y, 1, 16, "madera_oscura"), caja(x + 1, y, 8, 8, c1), caja(x + 1, y + 8, 4, 3, c1),
            caja(x + 4, y + 2, 2, 4, c2)]


def franja():
    """Barra del modo construcción en la zona de selección (abajo, hud.ZONAS["seleccion"])."""
    x, y, w, h = hud.ZONAS["seleccion"]
    e = [panel(x, y, w, h, None, False),
         ico(x + 8, y + 5, I + "icon_build_mode.png"), t(x + 28, y + 6, 80, 12, "CONSTRUIR", "negrita", "oro_claro"),
         img(x + 104, y + 7, "ui:marks/badge_title_citizen", 12, 12),
         t(x + 120, y + 6, 110, 12, "Edificios 1/2", "negrita"),
         t(x + 214, y + 6, 50, 12, "Libres:", color="texto_tenue")]
    cx = x + 262
    for tipo, n, col in [("production", "3", "texto"), ("housing", "4", "texto"), ("rustic", "2", "aviso")]:
        e += [img(cx, y + 8, P + tipo + ".png", 20, 10), t(cx + 22, y + 6, 14, 12, n, "negrita", col)]
        cx += 40
    e.append(btn(x + w - 64, y + 5, "Salir", 56, 16, fuente="cuerpo", tecla="B"))
    ly = y + 25
    cx = x + 10
    for tipo, txt in [("rustic", "rústica"), ("production", "producción"), ("housing", "vivienda")]:
        e += [img(cx, ly + 1, P + tipo + ".png", 20, 10), t(cx + 22, ly, 76, 12, txt, color="texto_tenue")]
        cx += 96
    e += banderin(cx + 2, ly - 3, FAM_FERRER) + [t(cx + 14, ly, 70, 12, "ocupada", color="texto_tenue")]
    e += [ico(cx + 76, ly - 2, I + "icon_contrato.png", 14), t(cx + 92, ly, 70, 12, "se vende", color="texto_tenue")]
    return e


def modo():
    e = [velo(0.25)]
    e += parcela(250, 356, 3, 4, "production") + contorno(250, 356, 3, 4)
    e += parcela(60, 300, 2, 2, "housing")
    e += parcela(548, 352, 2, 2, "rustic")
    e += banderin(446, 292, FAM_HERRERO) + banderin(640, 30, FAM_FERRER)
    e += hud_mapa(oro="185", seleccion=False)
    e += franja()
    e += hud.avisos([("info", "Los Ferrer compran una parcela en la Calle Mayor.", I + "icon_build_mode.png")])
    e.append(tooltip(40, 226, 226, "Calle del Río · producción 3×4",
                     ["Libre. Admite: Forja", "(talleres en EA). Clic: qué construir."]))
    # panel de la parcela
    e.append(lateral("Parcela · Calle del Río", 232))
    yy = LAT_Y + 26
    for r in range(4):
        for c in range(3):
            e.append(img(X + 26 + (c - r) * 8, yy + (c + r) * 4, P + "production.png", 16, 8))
    e += [t(X + 64, yy, CW - 64, 12, "Producción · 3×4 casillas · libre", "negrita"),
          t(X + 64, yy + 14, CW - 64, 12, "A 8 casillas del mercado · a 12 de tu Forja", color="texto_tenue")]
    yy += 40
    e += [sep(X, yy, CW), t(X, yy + 6, 200, 12, "Qué puedes construir", "negrita", "oro")]
    yy += 24
    e += [caja(X, yy, CW, 50, "fila"), caja(X + 2, yy + 2, 46, 46, "hueco"),
          img(X + 4, yy + 4, "assets/art/buildings/forge.png", 42, 42),
          t(X + 54, yy + 3, 80, 12, "Forja", "negrita"),
          ico(X + 108, yy + 1, I + "icon_oro.png"), t(X + 126, yy + 3, 30, 12, "100", "negrita", "oro_claro"),
          t(X + 160, yy + 3, CW - 162, 12, "obra 2 d · 20/día", color="texto_tenue"),
          t(X + 54, yy + 18, CW - 150, 12, "Hierro, lingotes, espadas…", color="texto_tenue"),
          btn(X + CW - 92, yy + 30, "Construir…", 88, 16, "encima")]
    yy += 54
    e += [caja(X, yy, CW, 26, "fila", 0.6), ico(X + 9, yy + 5, I + "icon_locked.png"),
          t(X + 54, yy + 7, CW - 56, 12, "Carpintería · llega con el contenido EA", color="texto_apagado")]
    yy += 34
    e += [sep(X, yy, CW), t(X, yy + 6, CW, 12, "Tras construir: 2/2 edificios (Ciudadano).", color="texto_tenue"),
          t(X, yy + 20, CW, 12, "Patricio permite 4 → requisitos", color="info")]
    e += [llamada(240, 490, 1), llamada(244, 352, 2), llamada(440, 288, 3), llamada(2, 500, 6), llamada(LAT_X - 6, LAT_Y + 22, 4),
          llamada(LAT_X - 6, LAT_Y + 92, 5)]
    return {"id": "parcelas_y_construccion", "fondo": FONDO_MAPA, "elementos": e}


def confirmar():
    e = modo()["elementos"]
    e = [x for x in e if x.get("tipo") != "llamada"]
    e += confirmacion("Construir Forja", [
        ("Parcela", "Calle del Río (producción, 3×4)", None),
        ("Pagas ahora", "100 de oro (te quedan 85)", None),
        ("Obra", "2 días: lista el día 12 a las 06:00", None),
        ("Mantenimiento", "20 cada alba desde que esté lista", "aviso"),
        ("Edificios", "2/2 (Ciudadano) tras esta obra", None),
        ("", None, None),
        ("La obra no se puede cancelar.", None, "negativo"),
    ], "Construir", y=160, w=400)
    return {"id": "parcelas_y_construccion_confirmar", "fondo": FONDO_MAPA, "elementos": e}


MAQUETAS = [modo(), confirmar()]
