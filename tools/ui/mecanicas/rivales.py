"""Maquetas de docs/ui/mecanicas/rivales.md (solo la interfaz; la IA rival es 04c, sin aprobar).
python3 tools/ui/maqueta.py tools/ui/mecanicas/rivales.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (FONDO_PLAZA, FAM, I, LAT_X, TAR_X, TAR_Y, bandera, barra, btn, caja, ico, insignia,  # noqa
                         lateral, llamada, panel, ret, sep, t)

X = LAT_X + 8
W = 336
BANDA = {"Cordial": "#6a8a5a", "Neutral": "remache", "Tensa": "aviso", "Hostil": "#c87040", "Enemiga": "lacre"}
PURP = "#5a3a6a"


def chip(x, y, banda, flecha=""):
    return [caja(x, y, 70, 14, BANDA[banda]), t(x, y, 70, 14, banda + (" " + flecha if flecha else ""), "negrita",
                                                "texto_tinta" if banda in ("Tensa", "Neutral") else "texto", "centro",
                                                "centro")]


def fila_vecinos(y, fam, nombre, titulo, cargos, banda):
    e = [caja(X, y, W, 18, "fila")] + bandera(X + 3, y + 2, 8, 14, fam, FAM.get(fam + "2", "pergamino"))
    e += [t(X + 16, y + 3, 90, 12, nombre, "negrita"), t(X + 92, y + 3, 150, 12, titulo + cargos, "cuerpo",
                                                          "texto_tenue")]
    e += chip(X + W - 74, y + 2, banda)
    return e


def panel_familias():
    e = [lateral("Familias de la ciudad", 344)]
    e += [caja(X, 122, W, 16, "seccion"), caja(X, 122, 3, 16, "info"),
          t(X + 8, 124, 320, 12, "Primer año: nadie te atacará hasta el día 9", "cuerpo", "info"),
          t(X, 144, 200, 12, "Compiten contigo", "negrita", "oro")]
    e += [caja(X, 160, W, 56, "madera")] + bandera(X + 4, 164, 12, 48, "ferrer", "ferrer2")
    e += [ret(X + 20, 166, "bernat", 32, "ferrer"),
          t(X + 58, 164, 150, 12, "Ferrer", "negrita", "oro_claro"),
          t(X + 58, 177, 180, 12, "Ciudadanos · rep 72", "cuerpo", "texto"),
          ico(X + 58, 190, I + "icon_build_mode.png", 12), t(X + 72, 191, 40, 12, "1", "cuerpo"),
          ico(X + 90, 190, I + "icon_crown.png", 12), t(X + 104, 191, 80, 12, "Inspector", "cuerpo"),
          t(X + 58, 203, 274, 12, "Motivo: les quitas ventas de espada", "cuerpo", "texto_tenue")]
    e += chip(X + W - 74, 164, "Tensa", "↑")
    e += [t(X, 222, 200, 12, "Vecinos (9)", "negrita", "oro")]
    rows = [("soler", "Soler", "Patricios · ", "Juez", "Neutral"), ("puig", "Puig", "Ciudadanos", "",
                                                                              "Cordial"),
            ("vidal", "Vidal", "Ciudadanos", "", "Neutral"), ("serra", "Serra", "Ciudadanos", "", "Neutral"),
            ("mas", "Mas", "Plebeyos", "", "Neutral")]
    for i, r in enumerate(rows):
        e += fila_vecinos(238 + i * 20, *r)
    e += [t(X, 340, W, 12, "y 4 más…", "cuerpo", "texto_apagado"),
          t(X, 360, W, 60, "Los vecinos no compiten: solo viven y votan. La banda dice cómo se llevan con tu familia.",
            "cuerpo", "texto_apagado")]
    e += [llamada(LAT_X - 6, 122, 1), llamada(LAT_X - 6, 164, 2), llamada(LAT_X + W + 4, 164, 3)]
    return {"id": "rivales_panel", "fondo": FONDO_PLAZA, "elementos": e}


def ficha_familia():
    e = [lateral("‹ Familia Ferrer", 400)]
    e += bandera(X, 124, 20, 40, "ferrer", "ferrer2")
    e += [t(X + 28, 124, 200, 14, "Ferrer", "titulo", "oro"), t(X + 28, 140, 200, 12, "Ciudadanos · rep 72"),
          t(X + 28, 153, 260, 12, "«Les quitas ventas de espada»", "cuerpo", "texto_tenue")]
    e += chip(X + W - 74, 126, "Tensa", "↑")
    e += [btn(X, 172, "Regalar al cabeza", 130), btn(X + 134, 172, "Ver en el mapa", 110),
          btn(X + 248, 172, "Acusar…", 88, estado="desactivado"),
          t(X + 248, 189, 88, 12, "llega con H11", "pequena", "texto_apagado", "der"),
          sep(X, 204, W), t(X, 208, 200, 12, "Miembros", "negrita")]
    for i, (who, n, d) in enumerate([("bernat", "Bernat", "47 · Inspector"),
                                     ("isabel", "Elena", "25 · soltera"), ("diego", "Marc", "9")]):
        x = X + i * 112
        e += [ret(x, 222, who, 32, "ferrer"), t(x + 36, 224, 76, 12, n, "negrita"),
              t(x + 36, 236, 76, 24, d, "cuerpo", "texto_tenue")]
    e += [sep(X, 262, W), t(X, 266, W, 12, "Ventas públicas (último año)", "negrita"),
          ico(X, 282, I + "icon_espada.png"), t(X + 20, 283, 60, 12, "Espada"),
          caja(X + 80, 285, 150, 8, FAM["herrero"]), caja(X + 230, 285, 106, 8, FAM["ferrer"]),
          t(X + 80, 294, 256, 12, "tú 58 %  ·  Ferrer 42 %", "cuerpo", "texto_tenue"),
          ico(X, 310, I + "icon_martillo.png"), t(X + 20, 311, 60, 12, "Martillo"),
          caja(X + 80, 313, 256, 8, FAM["herrero"]), t(X + 80, 322, 256, 12, "tú 100 %", "cuerpo", "texto_tenue"),
          sep(X, 340, W), t(X, 344, 200, 12, "Hechos públicos", "negrita")]
    for i, (d, h) in enumerate([("Día 14", "Compró la parcela de la calle Mayor"), ("Día 9", "Bernat, Inspector"),
                                ("Día 6", "Subieron a Ciudadanos")]):
        e += [t(X, 360 + i * 13, 50, 12, d, "cuerpo", "texto_tenue"), t(X + 50, 360 + i * 13, 286, 12, h)]
    e += [{"tipo": "tooltip", "rect": [LAT_X - 196, 140, 190, 0], "titulo": "Oro de los Ferrer",
           "lineas": ["No sabes cuánto oro tienen."]}]
    e += [llamada(LAT_X - 6, 126, 1), llamada(LAT_X - 6, 172, 2), llamada(LAT_X - 6, 266, 3),
          llamada(LAT_X - 6, 344, 4)]
    return {"id": "rivales_ficha", "fondo": FONDO_PLAZA, "elementos": e}


def letrero(x, y, txt, fam, fam2):
    w = len(txt) * 6 + 22
    return [caja(x, y, w, 15, "madera_oscura"), caja(x + 1, y + 1, w - 2, 13, "pergamino")] + \
        bandera(x + 2, y + 1, 7, 13, fam, fam2) + [t(x + 12, y + 1, w - 14, 13, txt, "cuerpo", "texto_tinta", "izq",
                                                     "centro", False)]


def presagio():
    x, y, w = TAR_X, TAR_Y, 300
    e = [panel(x, y, w, 130, None, False), caja(x + 6, y + 6, w - 12, 118, "#2a2034"), caja(x + 6, y + 6, 3, 118, PURP),
         ico(x + 14, y + 12, I + "icon_warning.png"), t(x + 34, y + 12, 200, 14, "Rumor en el mercado", "titulo", "oro"),
         t(x + 200, y + 13, 90, 12, "12 h", "negrita", "aviso", "der"),
         t(x + 14, y + 32, 276, 12, "Los Ferrer acumulan espadas.", "negrita", "texto")]
    e += bandera(x + 270, y + 30, 10, 16, "ferrer", "ferrer2")
    e += [t(x + 14, y + 46, 276, 24, "Pueden hundir el precio de la espada durante 1 estación.", "cuerpo", "negativo"),
          t(x + 14, y + 72, 276, 24, "Vende ahora (la demanda está subiendo) o pasa a encargos u otra receta.", "cuerpo",
            "texto_tenue"),
          btn(x + 14, y + 104, "Ir al mercado", 110, 14, fuente="cuerpo"), btn(x + 130, y + 104, "Ferrer ›", 70, 14,
                                                                               fuente="cuerpo"),
          t(x + 206, y + 105, 84, 12, "Entendido", "cuerpo", "oro", "der")]
    y2 = y + 136
    e += [panel(x, y2, w, 52, None, False), caja(x + 6, y2 + 6, w - 12, 40, "#2a2034"),
          t(x + 14, y2 + 8, 276, 12, "Rumor: los Ferrer preguntan por la parcela", "cuerpo", "texto_apagado"),
          caja(x + 14, y2 + 14, 270, 1, "texto_apagado"),
          t(x + 14, y2 + 21, 276, 12, "Los Ferrer han desistido: la compraste tú", "negrita", "positivo")]
    # letreros del mapa con banderín de familia
    e += letrero(98, 50, "Forja de Ferrer", "ferrer", "ferrer2")
    e += letrero(622, 306, "Forja", "herrero", "herrero2")
    e += [llamada(x + w + 2, y, 1), llamada(x + w + 2, y2, 2), llamada(86, 50, 3), llamada(610, 306, 3)]
    return {"id": "rivales_presagio", "fondo": FONDO_PLAZA, "elementos": e}


MAQUETAS = [panel_familias(), ficha_familia(), presagio()]
