"""Maquetas de docs/ui/mecanicas/tribunal.md (H11, sin implementar: nombres propuestos).
python3 tools/ui/maqueta.py docs/ui/maquetas/src/tribunal.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (con_hud, FONDO_AYTO, FAM, I, TAR_X, TAR_Y, bandera, barra, btn, caja, ico, llamada, panel, ret,  # noqa
                         sep, t, velo)

PURP = "#2a2034"      # sección del tribunal (paleta secundaria de la biblia)
PURP_FILA = "#352a40"
ORO_AP = "#a08a4a"    # oro apagado


def juicio_marco(titulo, sub):
    e = [velo(0.45), panel(4, 52, 952, 468, None, True), caja(12, 60, 936, 452, PURP),
         caja(12, 60, 936, 1, ORO_AP), caja(12, 511, 936, 1, ORO_AP)]
    e += [ico(20, 66, I + "icon_documento.png"), t(40, 66, 600, 14, titulo, "titulo", "oro"),
          t(640, 67, 290, 12, sub, "negrita", "aviso", "der")]
    return e


def cabecera():
    return [ret(20, 88, "hugo", 32, "herrero"), t(56, 90, 200, 12, "Hugo Herrero", "negrita"),
            t(56, 103, 200, 12, "acusado", "cuerpo", "texto_tenue"),
            t(380, 96, 200, 12, "contra", "cuerpo", "texto_tenue", "centro"),
            ret(906, 88, "bernat", 32, "ferrer"), t(700, 90, 200, 12, "Bernat Ferrer", "negrita", "texto", "der"),
            t(700, 103, 200, 12, "acusador", "cuerpo", "texto_tenue", "der"),
            t(20, 126, 900, 12, "Si pierdes (MEDIA): confiscación de la Forja o de su mercancía.", "cuerpo", "negativo")]


def balanza(y, d, a, a_txt="40 + ?", sub=("Retórica 3×2 = 6 · a favor 2×15 = 30 · reputación 60×0,1 = 6",
                                         "Retórica 5×2 = 10 · en contra 2×15 = 30 · pruebas ?")):
    tot = 100.0
    return [t(20, y, 300, 12, "Balanza", "negrita", ORO_AP),
            t(20, y + 16, 110, 12, "Defensa %d" % d, "negrita", "positivo"),
            caja(130, y + 16, 680, 12, "madera"), caja(131, y + 17, 678, 10, "hueco"),
            caja(470 - int(339 * d / tot), y + 17, int(339 * d / tot), 10, "positivo"),
            caja(471, y + 17, int(339 * a / tot), 10, "negativo"), caja(470, y + 13, 2, 18, "oro_claro"),
            t(810, y + 16, 136, 12, "Acusación " + a_txt, "negrita", "negativo", "der"),
            t(20, y + 34, 450, 12, sub[0], "cuerpo", "texto_tenue"),
            t(490, y + 34, 450, 12, sub[1], "cuerpo", "texto_tenue", "der")]


DISP = {"for": ("A favor", "positivo"), "neutral": ("Neutral", "aviso"), "against": ("En contra", "negativo")}


def testigo(y, who, fam, nombre, rol, disp, acciones=None, tachado=False):
    lab, col = DISP[disp]
    e = [caja(20, y, 920, 36, PURP_FILA), caja(20, y, 3, 36, col), ret(26, y + 2, who, 32, fam),
         t(64, y + 4, 220, 12, nombre, "negrita"), t(64, y + 18, 220, 12, rol, "cuerpo", "texto_tenue"),
         caja(290, y + 10, 76, 16, col), t(290, y + 10, 76, 16, lab, "negrita", "texto_tinta", "centro", "centro")]
    if acciones:
        x = 380
        for txt, w, est in acciones:
            e.append(btn(x, y + 10, txt, w, 16, est, fuente="cuerpo"))
            x += w + 6
    return e


def acusacion():
    x, y, w = TAR_X, TAR_Y, 300
    e = [panel(x, y, w, 136, "Te acusan", False), caja(x + 6, y + 24, w - 12, 106, PURP)]
    e += [ret(x + 12, y + 30, "bernat", 32, "ferrer"), t(x + 50, y + 34, 60, 12, "acusan a", "cuerpo", "texto_tenue",
                                                        "centro"),
          ret(x + 112, y + 30, "hugo", 32, "herrero"),
          t(x + 150, y + 30, 144, 36, "Los Ferrer acusan a Hugo", "negrita"),
          t(x + 12, y + 68, 280, 12, "Fraude en el mercado · gravedad MEDIA", "cuerpo", "aviso"),
          t(x + 12, y + 81, 280, 12, "Puedes perder la Forja o su mercancía", "cuerpo", "negativo"),
          t(x + 12, y + 94, 280, 12, "Preparación: 2 días (hasta el día 23)", "cuerpo", "texto_tenue"),
          btn(x + 12, y + 110, "Preparar la defensa", 160, 16, "encima"),
          t(x + 180, y + 112, 108, 12, "Más tarde", "cuerpo", "oro", "der")]
    return {"id": "tribunal_acusacion", "fondo": FONDO_AYTO, "elementos": e}


def preparacion():
    e = juicio_marco("Juicio · fraude en el mercado", "quedan 1 d 14 h")
    e += cabecera()
    e += [sep(20, 142, 920, ORO_AP)]
    e += balanza(148, 42, 40)
    e += [sep(20, 198, 920, ORO_AP), t(20, 204, 200, 12, "Testigos", "negrita", ORO_AP)]
    e += testigo(222, "agnes", "soler", "Agnès Soler", "vecina", "for")
    e += testigo(262, "joan", "herrero", "Joan", "tu empleado", "for")
    e += testigo(302, "marta", "puig", "Marta Puig", "clienta", "neutral",
                 [("Convencer · dudoso", 130, "encima"), ("Sobornar · 35", 110, "normal"), ("Amenazar", 80, "normal")])
    e += testigo(342, "isabel", "ferrer", "Elena Ferrer", "de la familia rival", "against",
                 [("Convencer · difícil", 130, "normal"), ("Sobornar · 60", 110, "desactivado"),
                  ("Amenazar", 80, "normal")])
    e += [t(560, 352, 360, 12, "Sobornar: te faltan 10 de oro", "cuerpo", "negativo", "der")]
    e += testigo(382, "elvira", "mas", "Pons Mas", "vecino", "against",
                 [("Convencer · fácil", 130, "normal"), ("Sobornar · 20", 110, "normal"), ("Amenazar", 80, "normal")])
    e += [{"tipo": "tooltip", "rect": [380, 424, 300, 0], "titulo": "Convencer a Marta",
           "lineas": ["Retórica 3 contra Empatía 3: dudoso.", "Éxito: pasa a favor (+15 a la defensa).",
                      "Una vez al día por testigo."]}]
    e += [llamada(8, 88, 1), llamada(8, 150, 2), llamada(8, 222, 3), llamada(368, 312, 4)]
    return {"id": "tribunal_preparacion", "fondo": FONDO_AYTO, "elementos": e}


def vista():
    e = juicio_marco("Vista oral · fraude en el mercado", "en pausa durante la vista")
    # estrado
    e += [caja(380, 88, 200, 44, PURP_FILA), ret(462, 92, "erudito", 36, "soler"),
          t(380, 132, 200, 12, "Juez: Agnès Soler", "cuerpo", "texto_tenue", "centro"),
          ret(60, 150, "hugo", 64, "herrero"), t(20, 218, 144, 12, "Hugo (acusado)", "negrita", "texto", "centro"),
          ret(836, 150, "bernat", 64, "ferrer"), t(796, 218, 144, 12, "Bernat (acusador)", "negrita", "texto",
                                                   "centro")]
    e += balanza(240, 30, 45, "45", ("Hasta ahora: 2 testigos a favor (30) · falta tu alegato",
                                      "alegato 10 · pruebas 20 · 1 testigo en contra 15"))
    # testigo declarando
    e += [caja(300, 150, 360, 80, PURP_FILA), caja(300, 150, 3, 80, "negativo"),
          ret(310, 158, "elvira", 32, "mas"), t(350, 158, 300, 12, "Declara Pons Mas (en contra)", "negrita"),
          t(350, 172, 300, 36, "«Le vi vender espadas malas como buenas en la plaza.»", "cuerpo", "texto_tenue"),
          btn(350, 206, "Interrogar · dudoso", 150, 18, "encima"), btn(510, 206, "Dejarlo", 80, 18)]
    # crónica del juicio
    e += [sep(20, 290, 920, ORO_AP), t(20, 296, 300, 12, "Lo que va pasando", "negrita", ORO_AP)]
    pasos = [("Alegato de la acusación", "+10", "negativo"), ("Pruebas presentadas: 1", "+20", "negativo"),
             ("Agnès Soler declara a favor", "+15", "positivo"), ("Joan declara a favor", "+15", "positivo"),
             ("Elena Ferrer declara en contra", "+15", "negativo"), ("Pons Mas declara...", "", "texto_tenue")]
    for i, (p, v, c) in enumerate(pasos):
        y = 314 + i * 16
        e += [t(30, y, 400, 12, "%d. %s" % (i + 1, p), "cuerpo", "texto" if v else "texto_tenue"),
              t(430, y, 60, 12, v, "negrita", c, "der")]
    e += [t(520, 314, 410, 60, "Interrogar (opción (b), decisión del owner): Retórica contra la Empatía del testigo. "
                               "Si sale bien, su testimonio no cuenta; si sale mal, pesa doble.", "cuerpo",
            "texto_apagado")]
    e += [llamada(8, 150, 1), llamada(288, 206, 2), llamada(8, 314, 3)]
    return {"id": "tribunal_vista", "fondo": FONDO_AYTO, "elementos": e}


def veredicto():
    x, y, w, h = 280, 130, 400, 250
    e = [velo(0.6), panel(x, y, w, h, None, False), caja(x + 8, y + 8, w - 16, h - 16, PURP)]
    e += [t(x, y + 16, w, 14, "Veredicto", "titulo", ORO_AP, "centro"),
          caja(x + 120, y + 40, 160, 34, "#5a1612"), caja(x + 122, y + 42, 156, 30, "lacre"),
          t(x + 122, y + 42, 156, 30, "CULPABLE", "negrita", "pergamino", "centro", "centro"),
          t(x, y + 84, w, 12, "Hugo Herrero · fraude en el mercado (media)", "negrita", "texto", "centro"),
          t(x, y + 98, w, 12, "Defensa 42 · Acusación 60", "cuerpo", "texto_tenue", "centro"),
          sep(x + 20, y + 116, w - 40, ORO_AP),
          t(x + 30, y + 124, w - 60, 12, "Condena: confiscación de mercancía", "negrita", "negativo"),
          t(x + 30, y + 138, w - 60, 48, "· Se confiscan las 8 espadas del almacén de la Forja.\n"
                                         "· Reputación −30.\n· Queda en la crónica (−60 puntos)."),
          btn(x + 140, y + 214, "Aceptar", 120, 20)]
    return {"id": "tribunal_veredicto", "fondo": FONDO_AYTO, "elementos": e}


MAQUETAS = con_hud([acusacion(), preparacion(), vista(), veredicto()])
