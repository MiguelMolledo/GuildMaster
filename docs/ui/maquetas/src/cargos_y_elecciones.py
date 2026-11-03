"""Maquetas de docs/ui/mecanicas/cargos_y_elecciones.md (sobre la rama h10-cargos).
python3 tools/ui/maqueta.py docs/ui/maquetas/src/cargos_y_elecciones.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (con_hud, a_lateral, oficio, titulo_ins, RET, MODAL, FONDO_AYTO, FONDO_PLAZA, FAM, I, LAT_X, bandera, barra, btn, caja, ico, insignia, lateral,  # noqa
                         llamada, motivo, panel, ret, sep, t, velo)

X = 480      # columna derecha del modal grande (detalle, campaña, poderes)
W = 440
CX = 36      # columna izquierda: el organigrama, siempre a la vista
SW = 204     # ancho de un asiento
RANGO = {"mayor": "oro", "major": "oro_oscuro", "middle": "remache", "minor": "#9a6a3a"}


def asiento(x, y, w, cargo, rango, who=None, fam=None, linea="VACANTE", sub="", elegido=False, urna=False,
            tuyo=False, oid=None):
    e = [caja(x, y, w, 36, "madera" if elegido else "fila"), caja(x, y, w, 2, RANGO[rango]),
         caja(x, y + 35, w, 1, "oro" if elegido else "madera_oscura")]
    if who:
        e.append(ret(x + 3, y + 3, who, 30, fam))
    else:
        e += [caja(x + 3, y + 3, 30, 30, "hueco"), t(x + 3, y + 3, 30, 30, "?", "negrita", "texto_apagado", "centro",
                                                       "centro")]
    e += [t(x + 37, y + 4, w - 40, 12, cargo, "negrita", "oro_claro" if elegido else "oro", ajustar=False),
          t(x + 37, y + 17, w - 40, 12, linea, "cuerpo", "texto" if who else "texto_tenue", ajustar=False)]
    if oid:
        e.append({"tipo": "imagen", "rect": [x + w - 16, y + 4, 12, 12], "imagen": oficio(oid)})
    if urna:
        e += insignia(x + w - 28, y + 5, "U", "aviso")
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


def modal_cargos(activa):
    """Modal grande 912×440 (01_hud §4.7: el organigrama es una pantalla grande); el organigrama a la izquierda y la
    pestaña elegida a la derecha."""
    x, y, w, h = MODAL
    e = [velo(0.45, 58), panel(x, y, w, h, "Cargos del pueblo", True),
         {"tipo": "pestanas", "rect": [X, y + 26, 0, 15], "textos": ["Cargos", "Campaña", "Poderes"], "activa": activa},
         {"tipo": "imagen", "rect": [x + w - 150, y + 28, 12, 12], "imagen": titulo_ins("citizen")},
         t(x + w - 136, y + 27, 124, 12, "Hugo · Ciudadano", "cuerpo", "texto_tenue")]
    e += asiento(CX + (2 * SW + 12 - SW) // 2, 110, SW, "Alcalde", "mayor", linea="VACANTE · voto día 9", urna=True,
                 oid="mayor")
    e += asiento(CX, 154, SW, "Concejal", "major", linea="VACANTE · voto día 9", oid="councillor")
    e += asiento(CX + SW + 12, 154, SW, "Concejal", "major", linea="VACANTE · voto día 9", oid="councillor")
    e += asiento(CX, 198, SW, "Juez", "middle", "agnes", "soler", "Agnès Soler · día 17", oid="judge")
    e += asiento(CX + SW + 12, 198, SW, "Alguacil", "middle", "joan", "soler", "Joan Soler · día 17", oid="constable")
    e += asiento(CX, 242, SW, "Recaudador", "minor", linea="VACANTE · voto día 9", urna=True, oid="tax_collector")
    insp = ("Hugo Herrero · día 17", "hugo", "herrero") if activa == 2 else ("VACANTE · voto día 9", None, None)
    e += asiento(CX + SW + 12, 242, SW, "Inspector", "minor", insp[1], insp[2], insp[0], urna=activa != 2,
                 elegido=True, tuyo=activa == 2, oid="market_inspector")
    e += [sep(CX, 290, 2 * SW + 12),
          t(CX, 296, 2 * SW + 12, 36, "Filete: oro alcalde · bronce concejal · plata medio · cobre menor. "
                                      "U: elección abierta. H: de tu familia.", "cuerpo", "texto_apagado"),
          caja(X - 12, 104, 1, 384, "oro_oscuro")]
    return e


def organigrama():
    e = modal_cargos(0)
    e += [t(X, 110, W, 12, "Inspector de mercado · 2 de oro/día · 1 año", "negrita"),
          t(X, 124, W, 12, "Regula un precio ±10 % · multa a un comerciante", "cuerpo", "texto_tenue"),
          t(X, 138, W, 12, "Pide: Ciudadano (lo tienes)", "cuerpo", "positivo")]
    e += calendario(X, 160, W, 0.45)
    e += [t(X, 188, 80, 12, "Candidatos", "negrita"), ret(X + 84, 185, "bernat", 18, "ferrer"),
          t(X + 106, 188, 300, 12, "Bernat Ferrer · campaña media", "cuerpo", "texto_tenue"),
          t(X, 214, 60, 12, "Campaña"), {"tipo": "campo", "rect": [X + 64, 211, 140, 16], "texto": "Media · 50  v"},
          btn(X + 214, 210, "Presentarse", 160, 18, "encima"),
          t(X, 236, W, 12, "Básica gratis (+5 %) · Media 50 (+15 %) · Alta 200 (+30 %)", "cuerpo", "texto_apagado")]
    e += [{"tipo": "tooltip", "rect": [CX + 120, 330, 220, 0], "titulo": "Inspector · historial",
           "lineas": ["Año 1: vacante (sin titulares)"]}]
    e += [llamada(CX - 12, 110, 1), llamada(CX + SW + 12 + SW - 6, 236, 2), llamada(X - 10, 160, 3),
          llamada(X - 10, 210, 4)]
    return {"id": "cargos_y_elecciones_organigrama", "fondo": FONDO_AYTO, "elementos": e, "_obj": False}


def campana():
    e = modal_cargos(1)
    r = [t(X, 144, 220, 12, "Inspector de mercado", "negrita", "oro"),
         t(X + 200, 144, W - 200, 12, "quedan 1 d 30 min", "cuerpo", "aviso", "der")]
    r += calendario(X, 162, W, 0.74, ("inscripción", "campaña", "voto día 9"))
    r += [t(X, 188, 120, 12, "Cómo vas", "negrita"),
          caja(X + 120, 186, 90, 16, "aviso"), t(X + 120, 186, 90, 16, "Reñido", "negrita", "texto_tinta", "centro",
                                                 "centro"),
          t(X + 214, 188, W - 214, 12, "sondeo al alba", "cuerpo", "texto_apagado", "der")]
    for i, (who, fam, nombre, nivel, hecho) in enumerate([
            ("hugo", "herrero", "Hugo · Herrero", "media", "discurso hoy: sí · 2 visitas · 1 soborno"),
            ("bernat", "ferrer", "Bernat · Ferrer", "media", "le han visto visitar a los Puig")]):
        y = 210 + i * 40
        r += [caja(X, y, W, 36, "fila"), ret(X + 3, y + 3, who, 30, fam),
              t(X + 38, y + 4, 200, 12, nombre, "negrita"), t(X + 240, y + 4, W - 244, 12, "campaña " + nivel, "cuerpo",
                                                              "texto_tenue", "der"),
              t(X + 38, y + 18, W - 42, 12, hecho, "cuerpo", "texto_tenue")]
    r += [sep(X, 294, W),
          btn(X, 300, "Discurso público", 150, 18, "desactivado"),
          motivo(X + 158, 303, W - 158, "Ya diste uno hoy · mañana"),
          t(X, 326, W, 12, "Visitar, sobornar y difamar: desde la ficha de un vecino.", "cuerpo", "texto_tenue"),
          btn(X, 344, "Elegir vecino en el mapa", 210, 16),
          llamada(X - 10, 162, 1), llamada(X - 10, 186, 2), llamada(X - 10, 210, 3)]
    e += a_lateral(r, -34)
    return {"id": "cargos_y_elecciones_campana", "fondo": FONDO_AYTO, "elementos": e, "_obj": False}


def soborno():
    """Ficha de vecino (zona 5) con las acciones de campaña y la confirmación del soborno (280 de ancho)."""
    fx = LAT_X + 8
    lat = [panel(LAT_X, 96, 356, 150, "Sança · Serra", True),
           ret(fx, 124, "marta", 32, "serra"), t(fx + 40, 124, 290, 12, "Puesto de recursos · 24 años"),
           t(fx + 40, 137, 290, 12, "Vota: es de familia Ciudadana", "cuerpo", "texto_tenue"),
           sep(fx, 162, 336), t(fx, 166, 200, 12, "Campaña · Inspector", "negrita", "oro"),
           btn(fx, 182, "Visitar a la familia", 160), btn(fx + 166, 182, "Sobornar (20)", 120, estado="pulsado"),
           t(fx, 204, 336, 24, "Difamar: solo a otro candidato.", "cuerpo", "texto_apagado"),
           llamada(LAT_X - 6, 166, 1)]
    e = a_lateral(lat)
    x, y, w, h = 340, 190, 280, 150
    e += [velo(0.5), panel(x, y, w, h, "¿Sobornar a Sança?", False),
          ret(x + 8, y + 30, "marta", 32, "serra"),
          t(x + 46, y + 28, w - 54, 36, "20 de oro. Te asegura su voto."),
          t(x + 8, y + 66, w - 16, 12, "Escándalo: Sigilo 2 contra Empatía 5", "cuerpo", "texto_tenue"),
          caja(x + 8, y + 82, 56, 14, "negativo"), t(x + 8, y + 82, 56, 14, "Difícil", "negrita", "texto", "centro",
                                                     "centro"),
          t(x + 70, y + 83, w - 78, 12, "si sale mal: −10 de reputación", "cuerpo", "negativo"),
          sep(x + 8, y + 112, w - 16),
          btn(x + 8, y + 122, "Cancelar", 100, 18, "encima"), btn(x + w - 128, y + 122, "Sobornar", 120, 18),
          llamada(x - 6, y, 2)]
    return {"id": "cargos_y_elecciones_soborno", "fondo": FONDO_PLAZA, "elementos": e,
            "_sel": ("Sança Serra", "Vecina · en el puesto de recursos", "texto_tenue", (("Ficha", "pulsado"),),
                     RET["marta"])}


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
            e += [{"tipo": "imagen", "rect": [x + 196, yy - 2, 16, 16], "imagen": "ui:marks/seal"},
                  {"tipo": "imagen", "rect": [x + 216, yy + 1, 12, 12], "imagen": oficio("market_inspector")}]
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
    e = [caja(X, y, W, 46, "fila"), t(X + 4, y + 3, 240, 12, nombre, "negrita",
                                      "texto" if estado != "desactivado" else "texto_apagado"),
         t(X + 4, y + 16, W - 8, 12, que, "cuerpo", "texto_tenue")]
    if hito:
        e += [t(X + 240, y + 3, W - 244, 12, hito, "cuerpo", "texto_apagado", "der")]
        return e
    cx = X + 4
    for a in args:
        e.append({"tipo": "campo", "rect": [cx, y + 28, a[1], 14], "texto": a[0]})
        cx += a[1] + 4
    e.append(btn(X + W - 84, y + 28, boton, 80, 14, estado))
    if cd is not None:
        e += [barra(cx + 2, y + 32, X + W - 90 - cx - 4, 6, cd, "info"),
              t(X + 240, y + 3, W - 244, 12, "lista en 1 d 6 h", "cuerpo", "info", "der")]
    return e


def poderes():
    e = modal_cargos(2)
    r = [{"tipo": "imagen", "rect": [X, 145, 12, 12], "imagen": oficio("market_inspector")},
         t(X + 16, 144, W - 16, 12, "Hugo · Inspector de mercado hasta el día 17", "negrita", "oro"),
         caja(X, 160, W, 30, "seccion"), caja(X, 160, 3, 30, "positivo"),
         t(X + 8, 163, W - 12, 12, "En vigor: Espada +10 % hasta el día 12", "cuerpo", "positivo"),
         t(X + 8, 176, W - 12, 12, "el mercado paga 50 y vende a 72", "cuerpo", "texto_tenue")]
    r += poder(196, "Regular un precio", "±10 % al precio de un objeto durante 2 días.", [("Espada  v", 100),
                                                                                         ("+10 %  v", 70)],
               "Regular", 0.35, "desactivado")
    r += poder(246, "Multar a un comerciante", "20 de oro a una familia con negocio (pide confirmación).",
               [("Ferrer  v", 100)], "Multar", None)
    r += poder(296, "Arrestar · investigar", "Abre un juicio.", [], "", None, "desactivado", "llega con H11")
    r += poder(346, "Fijar el impuesto", "Solo el Recaudador.", [], "", None, "desactivado", "no es tu cargo")
    r += [llamada(X - 10, 160, 1), llamada(X - 10, 196, 2), llamada(X - 10, 296, 3)]
    e += a_lateral(r, -34)
    return {"id": "cargos_y_elecciones_poderes", "fondo": FONDO_AYTO, "elementos": e, "_obj": False}


MAQUETAS = con_hud([organigrama(), campana(), soborno(), recuento(), poderes()])
