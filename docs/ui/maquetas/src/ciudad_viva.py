"""Maquetas de docs/ui/mecanicas/ciudad_viva.md.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/ciudad_viva.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (con_hud, a_lateral, RET, FONDO_PLAZA, I, LAT_X, text_size, TAR_X, TAR_Y, bipolar, barra, btn, caja, ico, lateral, llamada,  # noqa
                         motivo, panel, ret, sep, t)

X = LAT_X + 8
W = 336


def ficha():
    e = [lateral("Agnès · Soler", 232)]
    e += [ret(X, 124, "agnes", 32, "soler"),
          t(X + 40, 122, 290, 12, "Puesto de comida · 23 años"),
          {"tipo": "imagen", "rect": [X + 40, 137, 8, 8], "imagen": "ui:marks/rank_1"},
          t(X + 52, 135, 100, 12, "Aprendiz", color="texto_tenue"),
          ico(X + 150, 133, I + "bubble_chat.png"),
          t(X + 168, 135, 160, 12, "charlando en la plaza", color="texto_tenue")]
    e += [t(X, 164, 200, 12, "Relación con Hugo", "negrita"),
          t(X + 200, 164, 136, 12, "Neutral  0", "cuerpo", "texto_tenue", "der")]
    e += bipolar(X, 178, W, 8, 0)
    e += [t(X, 187, 60, 9, "-100", "pequena", "texto_apagado"), t(X + W - 60, 187, 60, 9, "+100", "pequena",
          "texto_apagado", "der")]
    e += [sep(X, 199, W),
          t(X, 203, 200, 12, "Hacia tu familia", "negrita"),
          ico(X, 217, I + "state_angry.png"),
          t(X + 20, 218, 90, 12, "Cabreada", color="negativo"),
          barra(X + 112, 221, 170, 6, 0.8, "negativo"),
          t(X + 290, 218, 46, 12, "2 d", color="texto_tenue", alinear="der"),
          t(X + 20, 231, 316, 12, "precios +25 % · no te vende por encima de 80", color="texto_tenue"),
          t(X + 20, 244, 316, 12, "y 1 más hacia otras familias", color="texto_apagado")]
    e += [sep(X, 259, W),
          btn(X, 265, "Conversar", 84, estado="desactivado"), btn(X + 88, 265, "Regalar", 76),
          btn(X + 168, 265, "Halagar", 76, estado="encima"),
          btn(X, 285, "Insultar", 84), btn(X + 88, 285, "Amenazar", 76),
          motivo(X, 306, W, "Conversar: no quiere hablar, está cabreada (2 d)")]
    e += [{"tipo": "tooltip", "rect": [LAT_X - 196, 250, 200, 0], "titulo": "Halagar",
           "lineas": ["Carisma 4 contra Empatía 6:", "difícil. Éxito: relación +3;", "fallo: relación -2."]}]
    e += [llamada(LAT_X - 6, 120, 1), llamada(LAT_X - 6, 162, 2), llamada(LAT_X - 6, 203, 3),
          llamada(LAT_X - 6, 266, 4), llamada(LAT_X - 6, 304, 5)]
    return {"id": "ciudad_viva_ficha", "fondo": FONDO_PLAZA, "elementos": a_lateral(e),
            "_sel": ("Agnès Soler", "Vecina · charlando en la plaza", "texto_tenue", (("Ficha", "pulsado"),),
                     RET["agnes"])}


def nota(x, y, icono, que, cliente, calidad, plazo, paga, tiene=None, ok=False):
    e = [panel(x, y, 162, 92, None, False, "parchment"),
         ico(x + 6, y + 6, icono), t(x + 24, y + 6, 134, 12, que, "negrita", "texto_tinta"),
         t(x + 6, y + 22, 150, 12, cliente, color="texto_tinta"),
         t(x + 6, y + 35, 150, 12, calidad, color="texto_tinta"),
         ico(x + 6, y + 49, I + "icon_oro.png"), t(x + 24, y + 51, 50, 12, paga, "negrita", "oro_oscuro"),
         t(x + 70, y + 51, 86, 12, plazo, color="texto_tinta", alinear="der")]
    if tiene:
        e.append(t(x + 6, y + 64, 80, 12, tiene, color="positivo" if ok else "texto_tinta"))
    e.append(btn(x + 92, y + 70, "Aceptar", 64))
    return e


def tablon():
    e = [lateral("Tablón de encargos", 380)]
    e += [ico(X + 250, 101, I + "icon_oro.png"), t(X + 268, 103, 40, 12, "89", "negrita", "oro_claro")]
    e += [t(X, 126, 200, 12, "Tus encargos", "negrita", "oro")]
    e += [caja(X, 140, W, 54, "fila"),
          ico(X + 4, 144, I + "icon_martillo.png"),
          t(X + 24, 145, 220, 12, "2 × Martillo · el carpintero", "negrita"),
          ico(X + 262, 143, I + "icon_oro.png"), t(X + 280, 145, 52, 12, "70", "negrita", "oro_claro"),
          t(X + 24, 159, 200, 12, "cualquier calidad · tienes 1/2", color="texto_tenue"),
          barra(X + 230, 162, 70, 6, 0.3, "aviso"), t(X + 300, 159, 34, 12, "6 h", color="aviso", alinear="der"),
          motivo(X + 24, 177, 150, "Falta 1 martillo"),
          btn(X + 184, 175, "Entregar", 70, estado="desactivado"), btn(X + 258, 175, "Abandonar", 76)]
    e += [sep(X, 200, W), t(X, 206, 200, 12, "Nuevos", "negrita", "oro")]
    e += nota(X, 222, I + "icon_espada.png", "1 × Espada", "capitán de la guardia", "calidad buena o mejor",
              "3 días", "83", "tienes 0/1")
    e += nota(X + 172, 222, I + "icon_martillo.png", "3 × Martillo", "el tonelero", "cualquier calidad", "2 días",
              "95", "tienes 3/3", ok=True)
    e += nota(X, 320, I + "icon_armadura.png", "1 × Armadura", "el alguacil", "calidad buena o mejor", "4 días",
              "160", "tienes 0/1")
    e += [t(X + 172, 330, 160, 40, "Abandonar o no cumplir un encargo cuesta reputación.", color="texto_apagado")]
    e += [llamada(LAT_X - 6, 140, 1), llamada(X + 172 + 150, 286, 2)]
    return {"id": "ciudad_viva_tablon", "fondo": FONDO_PLAZA, "elementos": a_lateral(e),
            "_sel": ("Hugo Herrero", "En el tablón de encargos", "texto_tenue", (("Inventario", "normal"),), RET["hugo"])}


def opcion(x, y, w, titulo, efectos, defecto=False, estado="normal"):
    e = [btn(x, y, "", w, 28, estado)]
    e += [t(x + 6, y + 3, w - 80, 12, titulo, "negrita", "texto" if estado != "desactivado" else "texto_apagado")]
    if defecto:
        e += [t(x + w - 70, y + 3, 64, 12, "defecto", "cuerpo", "oro", "der")]
    cx = x + 6
    for icono, txt, col in efectos:
        if icono:
            e.append(ico(cx, y + 14, icono, 12))
            cx += 13
        e.append(t(cx, y + 15, 160, 12, txt, "cuerpo", col, ajustar=False))
        cx += text_size(txt)[0] + 8
    return e


def microevento():
    """Tarjeta en la columna izquierda (zona 4), bajo el objetivo plegado: 236 de ancho."""
    x, y, w = TAR_X, TAR_Y, 236
    e = [panel(x, y, w, 196, "Ocurre algo en la Forja", False)]
    e += [ret(x + 8, y + 26, "joan", 32, "herrero"),
          t(x + 46, y + 26, w - 54, 36, "Joan está enfermo hoy y no irá a trabajar.")]
    e += opcion(x + 6, y + 64, w - 12, "Pagar al médico", [(I + "icon_oro.png", "-10", "negativo"),
                                                           (None, "vuelve mañana", "texto_tenue"),
                                                           (None, "leal +5", "positivo")])
    e += opcion(x + 6, y + 94, w - 12, "Día libre pagado", [(None, "falta hoy · cobra", "texto_tenue"),
                                                            (None, "leal +2", "positivo")], defecto=True)
    e += opcion(x + 6, y + 124, w - 12, "Descontarle el día", [(None, "falta 1-2 días", "texto_tenue"),
                                                              (None, "leal -5", "negativo")])
    e += [ico(x + 8, y + 158, I + "icon_pending.png", 12), barra(x + 24, y + 161, 110, 6, 0.65, "aviso"),
          t(x + 138, y + 158, 40, 12, "1 h 20", color="aviso"),
          t(x + 176, y + 158, 52, 12, "+1 más", "negrita", "oro", "der"),
          t(x + 8, y + 174, w - 16, 12, "Si no eliges: Día libre pagado", "cuerpo", "texto_apagado")]
    e += [llamada(x + w + 2, y + 64, 1), llamada(x + w + 2, y + 94, 2), llamada(x + w + 2, y + 156, 3)]
    return {"id": "ciudad_viva_microevento", "fondo": FONDO_PLAZA, "elementos": e}


def bocadillo(x, y, k, borde, icono, intensidad=None):
    """Bocadillo de burbuja a escala k (la pieza real es de 20×18): borde de color de familia o neutro."""
    e = [caja(x, y, 20 * k, 16 * k, "hueco"), caja(x + k, y + k, 18 * k, 14 * k, borde),
         caja(x + 2 * k, y + 2 * k, 16 * k, 12 * k, "pergamino"),
         caja(x + 8 * k, y + 16 * k, 4 * k, k, "hueco"), caja(x + 9 * k, y + 17 * k, 2 * k, k, "hueco"),
         ico(x + 2 * k, y + 2 * k, icono, 12 * k)]
    if intensidad is not None:
        e += [caja(x + 17 * k, y + 2 * k, k, 12 * k, "hueco"),
              caja(x + 17 * k, y + 2 * k + int(12 * k * (1 - intensidad)), k, int(12 * k * intensidad), "negativo")]
    return e


def burbujas():
    e = [panel(4, 96, 520, 300, "Burbujas sobre la cabeza (×4)", False)]
    k = 4
    e += bocadillo(20, 140, k, "#8b2e2e", I + "state_angry.png", 0.8)
    e += [t(110, 140, 150, 60, "Emoción hacia TU familia: borde de tu color (Herrero) y barra de intensidad.")]
    e += bocadillo(270, 140, k, "#3f6b3a", I + "state_offended.png", 0.4)
    e += [t(360, 140, 150, 60, "Emoción hacia otra familia (Ferrer): su color.")]
    e += bocadillo(20, 240, k, "madera", I + "bubble_chat.png")
    e += [t(110, 240, 150, 60, "Actividad social: borde de madera, sin barra.")]
    e += bocadillo(270, 240, k, "madera", I + "bubble_dice.png")
    e += [t(360, 240, 150, 60, "Prioridad: emoción hacia tu familia > otra emoción > actividad.")]
    e += [t(20, 340, 490, 50, "Una sola burbuja por cabeza. La frase (social_phrases.json) solo cerca de tu personaje, "
                              "en caja de pergamino debajo de la burbuja.", color="texto_tenue")]
    return {"id": "ciudad_viva_burbujas", "fondo": FONDO_PLAZA, "elementos": a_lateral(e, -34), "_sel": False,
            "_obj": False}


MAQUETAS = con_hud([ficha(), tablon(), microevento(), burbujas()])
