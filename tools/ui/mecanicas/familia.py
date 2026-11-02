"""Maquetas de docs/ui/mecanicas/familia.md.  python3 tools/ui/maqueta.py tools/ui/mecanicas/familia.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (FONDO_AYTO, I, TAR_X, TAR_Y, bandera, barra, btn, caja, ico, insignia, llamada, panel,  # noqa
                         ret, sep, t, velo)

NW, NH = 112, 42


def nodo(x, y, who, nombre, edad, insignias=(), marco="normal", corona=False, muerto=False, elegido=False):
    e = [caja(x, y, NW, NH, "madera" if elegido else "fila"),
         caja(x, y, NW, 1, "oro" if elegido else "madera_oscura"), caja(x, y + NH - 1, NW, 1, "madera_oscura"),
         ret(x + 5, y + 5, who, 32, "herrero", "muerto" if muerto else marco, corona=corona),
         t(x + 42, y + 4, 68, 12, nombre, "negrita", "texto_apagado" if muerto else ("oro_claro" if elegido else "texto")),
         t(x + 42, y + 16, 68, 12, edad, "cuerpo", "texto_apagado" if muerto else "texto_tenue")]
    for i, (letra, col) in enumerate(insignias):
        e += insignia(x + 42 + i * 11, y + 30, letra, col)
    return e


def linea(x, y, w, h):
    return caja(x, y, max(w, 2), max(h, 2), "oro_oscuro")


def stat(x, y, nombre, v):
    return [t(x, y, 84, 12, nombre, "cuerpo", "texto_tenue"), barra(x + 86, y + 3, 100, 6, v / 10.0, "oro"),
            t(x + 190, y, 20, 12, str(v), "cuerpo", "texto", "der")]


def arbol():
    e = [velo(0.35), panel(4, 52, 952, 468, None, True)]
    e += bandera(14, 60, 16, 30, "herrero", "herrero2")
    e += [t(36, 60, 300, 14, "Familia Herrero", "titulo", "oro"),
          t(36, 76, 400, 12, "Ciudadanos · generación 1 · 340 puntos", "cuerpo", "texto_tenue"),
          {"tipo": "pestanas", "rect": [520, 64, 0, 16], "textos": ["Árbol", "Dinastía"], "activa": 0},
          btn(880, 60, "-", 16), btn(900, 60, "+", 16),
          sep(12, 96, 936)]
    # árbol (x 12..700)
    hx, ay, by = 60, 130, 220
    e += [linea(hx + NW, ay + 20, 60, 2), caja(hx + NW + 26, ay + 16, 8, 8, "oro"), caja(hx + NW + 28, ay + 18, 4, 4,
          "fila"), linea(hx + NW + 30, ay + 24, 2, 40), linea(hx + 56, ay + 64, 400, 2)]
    for cx in (hx + 56, hx + 56 + 200, hx + 56 + 400):
        e.append(linea(cx, ay + 64, 2, by - ay - 64))
    e += nodo(hx, ay, "hugo", "Hugo", "60 años", [("1", "oro"), ("C", "info")], marco="activo")
    e += nodo(hx + NW + 60, ay, "agnes", "Agnès", "56 años", [])
    e += nodo(hx, by, "pere", "Pere", "16 años", [("2", "oro")], corona=True, elegido=True)
    e += nodo(hx + 200, by, "clara", "Clara", "8 años", [("!", "aviso")])
    e += nodo(hx + 400, by, "diego", "Marc", "† 3 años", [], muerto=True)
    e += [{"tipo": "tooltip", "rect": [hx + 2 * NW + 76, ay + 4, 250, 0], "titulo": "Hugo · cabeza de familia",
           "lineas": ["60 años · riesgo de muerte este año: medio"]}]
    e += [t(12, 480, 690, 12, "1-2-3 tecla del grupo · C cargo · ! escuela pendiente · corona: heredero",
            "cuerpo", "texto_apagado"),
          btn(12, 496, "Centrar en el cabeza", 140)]
    # ficha lateral (x 708..948)
    fx = 712
    e += [caja(fx - 6, 100, 1, 412, "oro_oscuro"),
          ret(fx, 104, "pere", 64, "herrero", corona=True),
          t(fx + 72, 106, 160, 14, "Pere", "titulo", "oro"),
          t(fx + 72, 124, 160, 12, "16 años · Herrero"),
          t(fx + 72, 138, 160, 12, "heredero", "negrita", "oro_claro"),
          t(fx + 72, 152, 160, 12, "en tu grupo (tecla 2)", "cuerpo", "texto_tenue")]
    y = 176
    for n, v in [("Carisma", 3), ("Empatía", 3), ("Negociación", 7), ("Arcano", 2), ("Destreza", 6),
                 ("Artesanía", 6), ("Arte marcial", 2), ("Constitución", 4), ("Retórica", 4), ("Sigilo", 3)]:
        e += stat(fx, y, n, v)
        y += 13
    e += [sep(fx, y + 4, 236),
          t(fx, y + 10, 70, 12, "Trabaja en"), {"tipo": "campo", "rect": [fx + 72, y + 8, 164, 16], "texto": "Forja  v"},
          btn(fx, y + 30, "Cambiar a él", 116), btn(fx + 120, y + 30, "Rutina", 116),
          btn(fx, y + 50, "Designar heredero", 236, estado="desactivado"),
          t(fx, y + 68, 236, 12, "Ya es el heredero", "cuerpo", "texto_apagado"),
          btn(fx, y + 84, "Cortejar", 236)]
    e += [llamada(4, 58, 1), llamada(hx - 14, by, 2), llamada(fx - 18, 104, 3), llamada(fx - 18, y + 30, 4),
          llamada(508, 64, 5)]
    return {"id": "familia_arbol", "fondo": FONDO_AYTO, "elementos": e}


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
    x, y, w = TAR_X, TAR_Y, 300
    e = [panel(x, y, w, 64, "Ha nacido Clara", False),
         ret(x + 8, y + 26, "clara", 32, "herrero"),
         t(x + 46, y + 28, 246, 30, "Hija de Hugo y Agnès. Tiene el pelo de su madre.")]
    y2 = y + 70
    e += [panel(x, y2, w, 132, "Clara va a la escuela", False),
          ret(x + 8, y2 + 26, "clara", 32, "herrero"),
          t(x + 46, y2 + 28, 246, 24, "Cumple 8 años: elige un atributo que sube +1 (para siempre).")]
    stats = ["Carisma", "Empatía", "Negoc.", "Arcano", "Destreza", "Artesan.", "Marcial", "Const.",
             "Retórica", "Sigilo"]
    for i, s in enumerate(stats):
        bx = x + 8 + (i % 5) * 57
        by = y2 + 62 + (i // 5) * 20
        e.append(btn(bx, by, s, 55, 16, "encima" if s == "Artesan." else "normal", fuente="pequena"))
    e += [t(x + 8, y2 + 106, 200, 12, "Artesanía 3 → 4 al confirmar", "cuerpo", "positivo"),
          t(x + 200, y2 + 106, 92, 12, "Más tarde", "cuerpo", "oro", "der")]
    e += [llamada(x + w + 2, y, 1), llamada(x + w + 2, y2, 2)]
    return {"id": "familia_tarjetas_vida", "fondo": FONDO_AYTO, "elementos": e}


MAQUETAS = [arbol(), sucesion(), tarjetas_vida()]
