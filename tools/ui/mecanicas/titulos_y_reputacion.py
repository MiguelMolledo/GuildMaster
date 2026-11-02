"""Maquetas de docs/ui/mecanicas/titulos_y_reputacion.md.
python3 tools/ui/maqueta.py tools/ui/mecanicas/titulos_y_reputacion.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (FONDO_AYTO, I, LAT_X, bandera, barra, btn, caja, ico, lateral, llamada, motivo, panel,  # noqa
                         ret, sep, t, velo)

X = LAT_X + 8
W = 336
TITULOS = ["Plebeyo", "Ciudadano", "Patricio", "Barón", "Nobleza"]


def escalera(x, y, w, actual, siguiente_resaltado=True):
    """Pieza de kit pendiente: 5 peldaños (conseguido / actual / siguiente / lejano)."""
    e = []
    step = w // 5
    e.append(caja(x + step // 2, y + 9, step * 4, 2, "oro_oscuro"))
    for i, n in enumerate(TITULOS):
        cx = x + i * step + step // 2 - 9
        if i < actual:
            fill, border = "oro_oscuro", "oro_oscuro"
        elif i == actual:
            fill, border = "oro", "oro_claro"
        elif i == actual + 1 and siguiente_resaltado:
            fill, border = "hueco", "aviso"
        else:
            fill, border = "hueco", "madera_clara"
        e += [caja(cx - 1, y - 1, 20, 22, border), caja(cx + 1, y + 1, 16, 18, fill)]
        col = "oro_claro" if i == actual else ("aviso" if i == actual + 1 and siguiente_resaltado else "texto_tenue")
        e.append(t(x + i * step, y + 24, step, 12, n, "cuerpo", col, "centro", ajustar=False))
    return e


def req(y, nombre, have, need, ok, extra=""):
    v = min(1.0, have / float(need)) if need else 1.0
    return [t(X, y, 76, 12, nombre, "cuerpo", "texto"),
            barra(X + 78, y + 3, 150, 6, v, "positivo" if ok else "aviso"),
            t(X + 232, y, 104, 12, "%d / %d%s" % (have, need, extra), "cuerpo", "positivo" if ok else "negativo",
              "der")]


def ayuntamiento():
    e = [lateral("Ayuntamiento", 280)]
    e += bandera(X, 124, 12, 22, "herrero", "herrero2")
    e += [t(X + 18, 126, 300, 12, "Familia Herrero · reputación 60", "negrita"),
          t(X + 18, 138, 300, 12, "6 cambios hoy: +4", "cuerpo", "texto_tenue")]
    e += escalera(X, 160, W, 1)
    e += [sep(X, 200, W),
          t(X, 206, 200, 12, "Siguiente: Patricio", "negrita", "aviso"),
          ico(X + 270, 204, I + "icon_oro.png"), t(X + 288, 206, 48, 12, "500", "negrita", "oro_claro", "der")]
    e += req(222, "Reputación", 60, 200, False, "")
    e += req(236, "Empleados", 1, 2, False)
    e += req(250, "Oro", 300, 500, False)
    e += [t(X, 266, 40, 12, "Abre", "negrita", "texto_tenue"),
          ico(X + 40, 264, I + "icon_build_mode.png"), t(X + 58, 266, 120, 12, "2 → 4 edificios"),
          ico(X + 170, 264, I + "icon_crown.png"), t(X + 188, 266, 140, 12, "cargos medios"),
          t(X, 286, 60, 12, "Aprueba", "negrita", "texto_tenue"),
          ret(X + 60, 282, "joan", 32, "soler"),
          t(X + 96, 282, 240, 12, "Joan Soler, Alcalde"),
          barra(X + 96, 298, 120, 6, 0.22, "aviso", 0.30), t(X + 220, 295, 116, 12, "afinidad 22 / 30", "cuerpo",
                                                                 "negativo"),
          sep(X, 322, W),
          btn(X, 328, "Pedir el título", 130, 18, "desactivado"),
          motivo(X + 136, 331, 200, "Falta reputación (60/200)"),
          btn(X, 350, "Cargos y elecciones", 160, 16), t(X + 166, 352, 170, 12, "tecla O", "cuerpo", "texto_apagado")]
    e += [llamada(LAT_X - 6, 160, 1), llamada(LAT_X - 6, 222, 2), llamada(LAT_X - 6, 282, 3),
          llamada(LAT_X - 6, 328, 4)]
    return {"id": "titulos_y_reputacion_ayuntamiento", "fondo": FONDO_AYTO, "elementos": e}


def reputacion():
    e = [lateral("Libro de cuentas · Herrero", 376),
         {"tipo": "pestanas", "rect": [X, 124, 0, 14], "textos": ["Hoy", "Por día", "Deudas", "Avisos",
                                                                    "Reputación"], "activa": 4}]
    e += [t(X, 146, 120, 14, "Reputación", "titulo", "oro"), t(X + 120, 145, 60, 14, "60", "negrita", "oro_claro"),
          t(X + 170, 146, 166, 12, "↑ +14 en 2 días", "cuerpo", "positivo", "der")]
    y = 168
    for cls, v, mod in [("Artesanos", 63, "+3"), ("Patrones", 60, ""), ("Eruditos", 60, ""), ("Pícaros", 60, "")]:
        e += [t(X, y, 76, 12, cls), barra(X + 78, y + 3, 190, 6, v / 200.0, "oro", 0.25),
              t(X + 272, y, 64, 12, "%d %s" % (v, mod), "cuerpo", "texto", "der")]
        y += 14
    e += [t(X, y + 2, W, 12, "La marca es 50: lo que pide Ciudadano.", "cuerpo", "texto_apagado"),
          t(X, y + 18, W, 12, "Pasiva: +1/día (Forja con empleados)", "cuerpo", "texto_tenue"),
          sep(X, y + 36, W), t(X, y + 42, 200, 12, "Últimos cambios", "negrita")]
    filas = [("Día 4", "Comercio justo ×6", "+6", "positivo"), ("Día 4", "Encargo cumplido", "+2", "positivo"),
             ("Día 4", "Negocio con empleados", "+1", "positivo"), ("Día 3", "Salario impagado", "−2", "negativo"),
             ("Día 3", "Comercio justo ×3", "+3", "positivo")]
    yy = y + 58
    for d, txt, v, c in filas:
        e += [caja(X, yy, W, 16, "fila"), t(X + 4, yy + 2, 40, 12, d, "cuerpo", "texto_tenue"),
              t(X + 48, yy + 2, 230, 12, txt), t(X + 280, yy + 2, 52, 12, v, "negrita", c, "der")]
        yy += 17
    e += [llamada(LAT_X - 6, 146, 1), llamada(LAT_X - 6, 168, 2), llamada(LAT_X - 6, y + 58, 3)]
    return {"id": "titulos_y_reputacion_reputacion", "fondo": FONDO_AYTO, "elementos": e}


def ceremonia():
    x, y, w, h = 290, 140, 380, 236
    e = [velo(0.5), panel(x, y, w, h, None, False)]
    e += bandera(x + 14, y + 10, 16, 30, "herrero", "herrero2") + bandera(x + w - 30, y + 10, 16, 30, "herrero",
                                                                          "herrero2")
    e += [t(x, y + 14, w, 14, "Ceremonia en el Ayuntamiento", "titulo", "oro", "centro"),
          caja(x + w // 2 - 13, y + 38, 26, 26, "#5a1612"), caja(x + w // 2 - 11, y + 40, 22, 22, "lacre"),
          t(x + w // 2 - 11, y + 40, 22, 22, "P", "negrita", "pergamino", "centro", "centro"),
          t(x, y + 70, w, 14, "Patricio", "titulo", "oro_claro", "centro"),
          t(x + 20, y + 92, w - 40, 12, "Hugo lo recibe en nombre de la familia Herrero.", "cuerpo", "texto", "centro"),
          ico(x + 92, y + 110, I + "icon_build_mode.png"), t(x + 110, y + 112, 90, 12, "4 edificios"),
          ico(x + 196, y + 110, I + "icon_crown.png"), t(x + 214, y + 112, 110, 12, "cargos medios")]
    e += escalera(x + 20, y + 140, w - 40, 2, False)
    e += [btn(x + 120, y + 200, "¡Viva la familia!", 140, 20)]
    return {"id": "titulos_y_reputacion_ceremonia", "fondo": FONDO_AYTO, "elementos": e}


MAQUETAS = [ayuntamiento(), reputacion(), ceremonia()]
