"""Maquetas de docs/ui/mecanicas/familia.md.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/familia.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (con_hud, oficio, titulo_ins, FONDO_AYTO, I, TAR_X, TAR_Y, bandera, barra, btn, caja, ico, insignia, llamada, panel,  # noqa
                         ret, sep, t, velo)

NW, NH = 112, 42


def nodo(x, y, who, nombre, edad, insignias=(), marco="normal", corona=False, muerto=False, elegido=False):
    e = [caja(x, y, NW, NH, "madera" if elegido else "fila"),
         caja(x, y, NW, 1, "oro" if elegido else "madera_oscura"), caja(x, y + NH - 1, NW, 1, "madera_oscura"),
         ret(x + 5, y + 5, who, 32, "herrero", "muerto" if muerto else marco, corona=corona),
         t(x + 42, y + 4, 68, 12, nombre, "negrita", "texto_apagado" if muerto else ("oro_claro" if elegido else "texto")),
         t(x + 42, y + 16, 68, 12, edad, "cuerpo", "texto_apagado" if muerto else "texto_tenue")]
    for i, (letra, col) in enumerate(insignias):
        if letra.startswith("ui:"):   # insignia del kit (cargo, título)
            e.append({"tipo": "imagen", "rect": [x + 42 + i * 13, y + 29, 12, 12], "imagen": letra})
        else:
            e += insignia(x + 42 + i * 13, y + 30, letra, col)
    return e


def linea(x, y, w, h):
    return caja(x, y, max(w, 2), max(h, 2), "oro_oscuro")


def stat(x, y, nombre, v):
    return [t(x, y, 84, 12, nombre, "cuerpo", "texto_tenue"), barra(x + 86, y + 3, 100, 6, v / 10.0, "oro"),
            t(x + 190, y, 20, 12, str(v), "cuerpo", "texto", "der")]


def arbol():
    """Modal grande 912×440 (01_hud §4.7): el HUD de arriba sigue a la vista."""
    e = [velo(0.45, 58), panel(24, 58, 912, 440, None, True)]
    e += bandera(34, 66, 16, 30, "herrero", "herrero2")
    e += [t(56, 66, 300, 14, "Familia Herrero", "titulo", "oro"),
          {"tipo": "imagen", "rect": [56, 83, 12, 12], "imagen": titulo_ins("citizen")},
          t(72, 82, 400, 12, "Ciudadanos · generación 1 · 340 puntos", "cuerpo", "texto_tenue"),
          {"tipo": "pestanas", "rect": [520, 70, 0, 16], "textos": ["Árbol", "Dinastía"], "activa": 0},
          btn(842, 63, "-", 16), btn(862, 63, "+", 16),
          sep(32, 102, 896)]
    hx, ay, by = 80, 128, 214
    e += [linea(hx + NW, ay + 20, 60, 2), caja(hx + NW + 26, ay + 16, 8, 8, "oro"), caja(hx + NW + 28, ay + 18, 4, 4,
          "fila"), linea(hx + NW + 30, ay + 24, 2, 40), linea(hx + 56, ay + 64, 400, 2)]
    for cx in (hx + 56, hx + 56 + 200, hx + 56 + 400):
        e.append(linea(cx, ay + 64, 2, by - ay - 64))
    e += nodo(hx, ay, "hugo", "Hugo", "60 años", [("1", "oro"), (oficio("market_inspector"), "")], marco="activo")
    e += nodo(hx + NW + 60, ay, "agnes", "Agnès", "56 años", [])
    e += nodo(hx, by, "pere", "Pere", "16 años", [("2", "oro")], corona=True, elegido=True)
    e += nodo(hx + 200, by, "clara", "Clara", "8 años", [("!", "aviso")])
    e += nodo(hx + 400, by, "diego", "Marc", "† 3 años", [], muerto=True)
    e += [{"tipo": "tooltip", "rect": [hx + 2 * NW + 76, ay + 4, 250, 0], "titulo": "Hugo · cabeza de familia",
           "lineas": ["60 años · Inspector de mercado", "riesgo de muerte este año: medio"]}]
    e += [btn(32, 474, "Centrar en el cabeza", 150, 16),
          t(190, 476, 490, 12, "1-2-3 tecla · insignia de cargo · ! escuela pendiente · corona: heredero",
            "cuerpo", "texto_apagado")]
    fx = 696
    e += [caja(fx - 8, 106, 1, 384, "oro_oscuro"),
          ret(fx, 108, "pere", 64, "herrero", corona=True),
          t(fx + 72, 110, 160, 14, "Pere", "titulo", "oro"),
          t(fx + 72, 128, 160, 12, "16 años · Herrero"),
          t(fx + 72, 142, 160, 12, "heredero", "negrita", "oro_claro"),
          t(fx + 72, 156, 160, 12, "en tu grupo (tecla 2)", "cuerpo", "texto_tenue")]
    y = 180
    for n, v in [("Carisma", 3), ("Empatía", 3), ("Negociación", 7), ("Arcano", 2), ("Destreza", 6),
                 ("Artesanía", 6), ("Arte marcial", 2), ("Constitución", 4), ("Retórica", 4), ("Sigilo", 3)]:
        e += stat(fx, y, n, v)
        y += 13
    e += [sep(fx, y + 4, 232),
          t(fx, y + 10, 70, 12, "Trabaja en"), {"tipo": "campo", "rect": [fx + 72, y + 8, 160, 16], "texto": "Forja  v"},
          btn(fx, y + 30, "Cambiar a él", 114), btn(fx + 118, y + 30, "Rutina", 114),
          btn(fx, y + 50, "Designar heredero", 232, estado="desactivado"),
          t(fx, y + 68, 232, 12, "Ya es el heredero", "cuerpo", "texto_apagado"),
          btn(fx, y + 84, "Cortejar", 232)]
    e += [llamada(24, 64, 1), llamada(hx - 14, by, 2), llamada(fx - 20, 108, 3), llamada(fx - 20, y + 30, 4),
          llamada(508, 70, 5)]
    return {"id": "familia_arbol", "fondo": FONDO_AYTO, "elementos": e, "_obj": False}


def sucesion():
    x, y, w, h = 270, 140, 420, 262
    e = [velo(0.6), panel(x, y, w, h, None, False)]
    e += bandera(x + 12, y + 10, 14, 26, "herrero", "herrero2")
    e += [t(x, y + 12, w, 14, "La familia Herrero", "titulo", "oro", "centro"), sep(x + 40, y + 30, w - 80),
          ret(x + 70, y + 40, "hugo", 64, "herrero", "muerto"),
          t(x + 40, y + 108, 124, 12, "Hugo", "negrita", "texto_tenue", "centro"),
          t(x + 40, y + 120, 124, 12, "† a los 75 años", "cuerpo", "texto_apagado", "centro"),
          t(x + 180, y + 64, 60, 14, "→", "negrita", "oro", "centro"),
          ret(x + 286, y + 40, "pere", 64, "herrero", corona=True),
          t(x + 256, y + 108, 124, 12, "Pere", "negrita", "oro_claro", "centro"),
          t(x + 236, y + 120, 164, 12, "cabeza · generación 2", "cuerpo", "texto", "centro"),
          sep(x + 12, y + 138, w - 24),
          t(x + 16, y + 144, 70, 12, "Hereda", "negrita", "positivo"),
          t(x + 90, y + 144, w - 106, 24, "Forja (3 mejoras, 2 empleados) · 1.250 de oro · título Ciudadano"),
          t(x + 16, y + 170, 70, 12, "No hereda", "negrita", "negativo"),
          t(x + 90, y + 170, w - 106, 12, "Inspector de mercado: queda vacante"),
          t(x + 16, y + 186, 70, 12, "Regente", "negrita", "texto_tenue"),
          t(x + 90, y + 186, w - 106, 12, "— (Pere ya es mayor de edad)", "cuerpo", "texto_tenue"),
          sep(x + 12, y + 204, w - 24),
          t(x + 16, y + 210, w - 32, 12, "En pausa hasta que continúes.", "cuerpo", "texto_apagado", "centro"),
          btn(x + 110, y + 230, "Continuar con Pere", 200, 20, "encima"),
          t(x + 320, y + 234, 90, 12, "Ver el árbol", "cuerpo", "oro", "der")]
    return {"id": "familia_sucesion", "fondo": FONDO_AYTO, "elementos": e}


def tarjetas_vida():
    """Tarjetas en la columna izquierda (zona 4), bajo el objetivo plegado."""
    x, y, w = TAR_X, TAR_Y, 236
    e = [panel(x, y, w, 70, "Ha nacido Clara", False),
         ret(x + 8, y + 28, "clara", 32, "herrero"),
         t(x + 46, y + 26, w - 54, 40, "Hija de Hugo y Agnès. Tiene el pelo de su madre.")]
    y2 = y + 76
    e += [panel(x, y2, w, 124, "Clara va a la escuela", False),
          ret(x + 8, y2 + 28, "clara", 32, "herrero"),
          t(x + 46, y2 + 26, w - 54, 40, "Cumple 8 años: un atributo sube +1 para siempre."),
          {"tipo": "campo", "rect": [x + 8, y2 + 70, 130, 16], "texto": "Artesanía  v"},
          btn(x + 144, y2 + 70, "Elegir", 84, 16, "encima"),
          t(x + 8, y2 + 90, 150, 12, "Artesanía 3 → 4", "cuerpo", "positivo"),
          t(x + 8, y2 + 104, w - 16, 12, "Más tarde (no caduca)", "cuerpo", "oro", "der")]
    e += [llamada(x + w + 2, y, 1), llamada(x + w + 2, y2, 2)]
    return {"id": "familia_tarjetas_vida", "fondo": FONDO_AYTO, "elementos": e}


MAQUETAS = con_hud([arbol(), sucesion(), tarjetas_vida()])
