"""Maquetas de docs/ui/mecanicas/cargos_y_elecciones.md (sobre la rama h10-cargos).
python3 tools/ui/maqueta.py docs/ui/maquetas/src/cargos_y_elecciones.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (con_hud, FONDO_AYTO, FONDO_PLAZA, FAM, I, LAT_X, bandera, barra, btn, caja, ico, insignia, lateral,  # noqa
                         llamada, motivo, panel, ret, sep, t, velo)

X = LAT_X + 8
W = 336
RANGO = {"mayor": "oro", "major": "oro_oscuro", "middle": "remache", "minor": "#9a6a3a"}


def asiento(x, y, w, cargo, rango, who=None, fam=None, linea="VACANTE", sub="", elegido=False, urna=False,
            tuyo=False):
    e = [caja(x, y, w, 36, "madera" if elegido else "fila"), caja(x, y, w, 2, RANGO[rango]),
         caja(x, y + 35, w, 1, "oro" if elegido else "madera_oscura")]
    if who:
        e.append(ret(x + 3, y + 3, who, 30, fam))
    else:
        e += [caja(x + 3, y + 3, 30, 30, "hueco"), t(x + 3, y + 3, 30, 30, "?", "negrita", "texto_apagado", "centro",
                                                       "centro")]
    e += [t(x + 37, y + 4, w - 40, 12, cargo, "negrita", "oro_claro" if elegido else "oro", ajustar=False),
          t(x + 37, y + 17, w - 40, 12, linea, "cuerpo", "texto" if who else "texto_tenue", ajustar=False)]
    if urna:
        e += insignia(x + w - 12, y + 4, "U", "aviso")
    if tuyo:
        e += insignia(x + w - 24, y + 4, "H", "#c86060")
    return e


def calendario(x, y, w, hoy_frac, tramos=("inscripción · días 1-6", "campaña 7-8", "voto 9")):
    a, b = int(w * 0.55), int(w * 0.25)
    c = w - a - b
    e = [caja(x, y, a - 2, 8, "positivo"), caja(x + a, y, b - 2, 8, "aviso"), caja(x + a + b, y, c, 8, "info"),
         caja(x + int(w * hoy_frac), y - 3, 2, 14, "texto"),
         t(x, y + 10, a, 12, tramos[0], "pequena", "texto_tenue", ajustar=False),
         t(x + a, y + 10, b, 12, tramos[1], "pequena", "texto_tenue", ajustar=False),
         t(x + a + b, y + 10, c, 12, tramos[2], "pequena", "texto_tenue", ajustar=False)]
    return e


def organigrama():
    e = [lateral("Cargos del pueblo", 416),
         {"tipo": "pestanas", "rect": [X, 122, 0, 14], "textos": ["Cargos", "Campaña", "Poderes"], "activa": 0},
         t(X + 170, 123, 166, 12, "Hugo · Ciudadano", "cuerpo", "texto_tenue", "der")]
    cw = 162
    e += asiento(X + (W - cw) // 2, 142, cw, "Alcalde", "mayor", linea="VACANTE · voto día 9", urna=True)
    e += asiento(X, 182, cw, "Concejal", "major", linea="VACANTE · voto día 9")
    e += asiento(X + cw + 12, 182, cw, "Concejal", "major", linea="VACANTE · voto día 9")
    e += asiento(X, 222, cw, "Juez", "middle", "agnes", "soler", "Agnès Soler · d.17")
    e += asiento(X + cw + 12, 222, cw, "Alguacil", "middle", "joan", "soler", "Joan Soler · d.17")
    e += asiento(X, 262, cw, "Recaudador", "minor", linea="VACANTE · voto día 9", urna=True)
    e += asiento(X + cw + 12, 262, cw, "Inspector", "minor", linea="VACANTE · voto día 9", urna=True, elegido=True)
    e += [sep(X, 304, W),
          t(X, 309, W, 12, "Inspector de mercado · 2 de oro/día · 1 año", "negrita"),
          t(X, 322, W, 12, "Regula un precio ±10 % · multa a un comerciante", "cuerpo", "texto_tenue"),
          t(X, 335, W, 12, "Pide: Ciudadano (lo tienes)", "cuerpo", "positivo")]
    e += calendario(X, 352, W, 0.45)
    e += [t(X, 378, 80, 12, "Candidatos", "negrita"), ret(X + 80, 375, "bernat", 18, "ferrer"),
          t(X + 102, 378, 230, 12, "Bernat Ferrer · campaña media", "cuerpo", "texto_tenue"),
          t(X, 400, 60, 12, "Campaña"), {"tipo": "campo", "rect": [X + 60, 397, 120, 16], "texto": "Media · 50  v"},
          btn(X + 190, 396, "Presentarse", 146, 18, "encima")]
    e += [{"tipo": "tooltip", "rect": [LAT_X - 210, 300, 206, 0], "titulo": "Inspector · historial",
           "lineas": ["Año 1: vacante", "(sin titulares todavía)"]}]
    e += [llamada(LAT_X - 6, 142, 1), llamada(LAT_X - 6, 262, 2), llamada(LAT_X - 6, 352, 3),
          llamada(LAT_X - 6, 396, 4)]
    return {"id": "cargos_y_elecciones_organigrama", "fondo": FONDO_AYTO, "elementos": e}


def campana():
    e = [lateral("Cargos del pueblo", 330),
         {"tipo": "pestanas", "rect": [X, 122, 0, 14], "textos": ["Cargos", "Campaña", "Poderes"], "activa": 1}]
    e += [t(X, 144, 220, 12, "Inspector de mercado", "negrita", "oro"),
          t(X + 200, 144, 136, 12, "quedan 1 d 30 min", "cuerpo", "aviso", "der")]
    e += calendario(X, 162, W, 0.74, ("inscripción", "campaña", "voto día 9"))
    e += [t(X, 188, 120, 12, "Cómo vas", "negrita"),
          caja(X + 120, 186, 90, 16, "aviso"), t(X + 120, 186, 90, 16, "Reñido", "negrita", "texto_tinta", "centro",
                                                 "centro"),
          t(X + 214, 188, 122, 12, "sondeo al alba", "cuerpo", "texto_apagado", "der")]
    for i, (who, fam, nombre, nivel, hecho) in enumerate([
            ("hugo", "herrero", "Hugo · Herrero", "media", "discurso hoy: sí · 2 visitas · 1 soborno"),
            ("bernat", "ferrer", "Bernat · Ferrer", "media", "le han visto visitar a los Puig")]):
        y = 210 + i * 40
        e += [caja(X, y, W, 36, "fila"), ret(X + 3, y + 3, who, 30, fam),
              t(X + 38, y + 4, 200, 12, nombre, "negrita"), t(X + 230, y + 4, 102, 12, "campaña " + nivel, "cuerpo",
                                                              "texto_tenue", "der"),
              t(X + 38, y + 18, 296, 12, hecho, "cuerpo", "texto_tenue")]
    e += [sep(X, 294, W),
          btn(X, 300, "Discurso público", 140, 18, "desactivado"),
          motivo(X + 146, 303, 190, "Ya diste uno hoy · mañana"),
          t(X, 324, W, 24, "Visitar, sobornar y difamar: desde la ficha de un vecino.", "cuerpo", "texto_tenue"),
          btn(X, 352, "Elegir vecino en el mapa", 200, 16)]
    # ficha de vecino con la sección de campaña y la confirmación del soborno
    x, y, w = 230, 210, 330
    e += [velo(0.0), panel(x, y, w, 132, "¿Sobornar a Sança Serra?", False),
          ret(x + 10, y + 30, "marta", 32, "serra"),
          t(x + 50, y + 30, 270, 36, "20 de oro. Te asegura su voto.\nRiesgo de escándalo: Sigilo 2 contra Empatía 5."),
          caja(x + 50, y + 70, 60, 14, "negativo"), t(x + 50, y + 70, 60, 14, "Difícil", "negrita", "texto", "centro",
                                                       "centro"),
          t(x + 116, y + 71, 200, 12, "si sale mal: −10 de reputación", "cuerpo", "negativo"),
          btn(x + 40, y + 102, "Sobornar (20)", 120, 18), btn(x + 180, y + 102, "Ahora no", 100, 18, "encima")]
    e += [llamada(LAT_X - 6, 162, 1), llamada(LAT_X - 6, 186, 2), llamada(LAT_X - 6, 210, 3), llamada(x - 6, y, 4)]
    return {"id": "cargos_y_elecciones_campana", "fondo": FONDO_PLAZA, "elementos": e}


def recuento():
    x, y, w, h = 280, 130, 400, 250
    e = [velo(0.55), panel(x, y, w, h, None, False)]
    e += [t(x, y + 12, w, 14, "Votación · Inspector de mercado", "titulo", "oro", "centro"), sep(x + 20, y + 30, w - 40)]
    rows = [("hugo", "herrero", "Hugo · Herrero", 6, True), ("bernat", "ferrer", "Bernat · Ferrer", 4, False)]
    for i, (who, fam, n, v, win) in enumerate(rows):
        yy = y + 40 + i * 40
        e += [ret(x + 16, yy, who, 32, fam), t(x + 54, yy + 2, 140, 12, n, "negrita", "oro_claro" if win else "texto"),
              barra(x + 54, yy + 18, 260, 10, v / 10.0, FAM[fam]), t(x + 320, yy + 15, 60, 12, "%d votos" % v, "negrita",
                                                                      "texto", "der")]
        if win:
            e += [caja(x + 196, yy - 2, 18, 18, "#5a1612"), caja(x + 197, yy - 1, 16, 16, "lacre"),
                  t(x + 197, yy - 1, 16, 16, "I", "negrita", "pergamino", "centro", "centro")]
    e += [sep(x + 20, y + 124, w - 40), t(x + 20, y + 130, w - 40, 12, "Por familias", "negrita", "texto_tenue")]
    fams = [("Soler", 2, 0), ("Puig", 2, 0), ("Vidal", 1, 1), ("Serra", 1, 1), ("Font", 0, 2)]
    for i, (f, a, b) in enumerate(fams):
        fx = x + 20 + i * 74
        e += [t(fx, y + 146, 70, 12, f, "cuerpo", "texto", "centro"),
              caja(fx + 10, y + 162, a * 12, 8, FAM["herrero"]), caja(fx + 10 + a * 12, y + 162, b * 12, 8,
                                                                       FAM["ferrer"]),
              t(fx, y + 172, 70, 12, "%d · %d" % (a, b), "pequena", "texto_tenue", "centro")]
    e += [t(x, y + 192, w, 12, "Hugo es el nuevo Inspector de mercado · votaron 10 vecinos", "cuerpo", "oro_claro",
            "centro"),
          btn(x + 130, y + 218, "¡Viva la familia!", 140, 20)]
    return {"id": "cargos_y_elecciones_recuento", "fondo": FONDO_AYTO, "elementos": e}


def poder(y, nombre, que, args, boton, cd, estado="normal", hito=None):
    e = [caja(X, y, W, 46, "fila"), t(X + 4, y + 3, 200, 12, nombre, "negrita",
                                      "texto" if estado != "desactivado" else "texto_apagado"),
         t(X + 4, y + 16, 328, 12, que, "cuerpo", "texto_tenue")]
    if hito:
        e += [t(X + 200, y + 3, 132, 12, hito, "cuerpo", "texto_apagado", "der")]
        return e
    cx = X + 4
    for a in args:
        e.append({"tipo": "campo", "rect": [cx, y + 28, a[1], 14], "texto": a[0]})
        cx += a[1] + 4
    e.append(btn(X + W - 84, y + 28, boton, 80, 14, estado))
    if cd is not None:
        e += [barra(cx + 2, y + 32, X + W - 90 - cx - 4, 6, cd, "info"),
              t(X + 200, y + 3, 132, 12, "lista en 1 d 6 h", "cuerpo", "info", "der")]
    return e


def poderes():
    e = [lateral("Cargos del pueblo", 330),
         {"tipo": "pestanas", "rect": [X, 122, 0, 14], "textos": ["Cargos", "Campaña", "Poderes"], "activa": 2}]
    e += [t(X, 144, W, 12, "Hugo · Inspector de mercado hasta el día 17", "negrita", "oro"),
          caja(X, 160, W, 30, "seccion"), caja(X, 160, 3, 30, "positivo"),
          t(X + 8, 163, 324, 12, "En vigor: Espada +10 % hasta el día 12", "cuerpo", "positivo"),
          t(X + 8, 176, 324, 12, "el mercado paga 50 y vende a 72", "cuerpo", "texto_tenue")]
    e += poder(196, "Regular un precio", "±10 % al precio de un objeto durante 2 días.", [("Espada  v", 90),
                                                                                         ("+10 %  v", 60)],
               "Regular", 0.35, "desactivado")
    e += poder(246, "Multar a un comerciante", "20 de oro a una familia con negocio.", [("Ferrer  v", 90)], "Multar",
               None)
    e += poder(296, "Arrestar · investigar", "Abre un juicio.", [], "", None, "desactivado", "llega con H11")
    e += [{"tipo": "tooltip", "rect": [LAT_X - 220, 236, 216, 0], "titulo": "¿Multar a los Ferrer?",
           "lineas": ["Pagan 20 de oro. Es público:", "lo sabrá todo el pueblo."]}]
    e += [llamada(LAT_X - 6, 160, 1), llamada(LAT_X - 6, 196, 2), llamada(LAT_X - 6, 296, 3)]
    return {"id": "cargos_y_elecciones_poderes", "fondo": FONDO_AYTO, "elementos": e}


MAQUETAS = con_hud([organigrama(), campana(), recuento(), poderes()])
