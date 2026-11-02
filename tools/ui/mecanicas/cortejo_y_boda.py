"""Maquetas de docs/ui/mecanicas/cortejo_y_boda.md.  python3 tools/ui/maqueta.py tools/ui/mecanicas/cortejo_y_boda.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from social_base import (FONDO_PLAZA, I, LAT_X, bandera, barra, btn, caja, ico, lateral, llamada, motivo, panel,  # noqa
                         ret, sep, t, velo)

X = LAT_X + 8
W = 336


def fila(y, who, fam, nombre, linea2, afinidad, estado=None, estado_col="texto_tenue", icono=None, puede=(1, 1, 0),
         bloqueada=False, titulo=None):
    e = [caja(X, y, W, 50, "#3a2418" if bloqueada else "fila"),
         ret(X + 4, y + 4, who, 32, fam),
         t(X + 42, y + 3, 230, 12, nombre, "negrita"),
         t(X + 42, y + 15, 230, 12, linea2, "cuerpo", "texto_tenue")]
    if titulo:
        e.append(t(X + 230, y + 3, 102, 12, titulo, "cuerpo", "oro", "der"))
    e += [barra(X + 42, y + 30, 118, 6, afinidad / 100.0, "#d07090", 0.8),
          t(X + 162, y + 27, 22, 12, str(afinidad), "negrita", "texto", "der")]
    bx = X + 190
    for i, (n, w) in enumerate([("Hablar", 46), ("Regalar", 52), ("Pedir", 44)]):
        e.append(btn(bx, y + 25, n, w, 14, "normal" if puede[i] else "desactivado", fuente="cuerpo"))
        bx += w + 2
    if estado:
        e += [t(X + 4, y + 38, 36, 12, "", "cuerpo")]
        if icono:
            e.append(ico(X + 42, y + 38, icono, 12))
        e.append(t(X + 56 if icono else X + 42, y + 38, 170, 12, estado, "cuerpo", estado_col))
    return e


def panel_cortejo():
    e = [lateral("Cortejo", 330)]
    e += [ret(X, 124, "hugo", 32, "herrero", "activo"),
          t(X + 40, 125, 200, 12, "Hugo · Carisma 4", "negrita"),
          t(X + 40, 138, 200, 12, "×0,9 a lo que gane la afinidad", "cuerpo", "texto_tenue"),
          t(X + 220, 125, 116, 12, "1 lista", "negrita", "positivo", "der"),
          {"tipo": "pestanas", "rect": [X, 160, 0, 14], "textos": ["Todos", "Cerca", "Listos"], "activa": 0}]
    e += fila(178, "agnes", "soler", "Agnès · 23", "Soler", 84, "lista para pedir su mano", "positivo",
              puede=(1, 1, 1), titulo="Ciudadanos")
    e += fila(232, "marta", "puig", "Marta · 19", "Puig", 52, "ya hablasteis hoy · mañana", "texto_tenue",
              I + "icon_pending.png", puede=(0, 1, 0))
    e += fila(286, "isabel", "ferrer", "Elena · 25", "Ferrer (rival)", 20, "cabreada contigo · 2 d", "negativo",
              I + "state_angry.png", puede=(0, 0, 0), bloqueada=True)
    e += [t(X, 342, W, 12, "3 más ↓", "cuerpo", "oro", "centro"),
          t(X, 360, W, 40, "La línea en la barra es 80: desde ahí puedes pedir su mano. Hablar cada día y regalar la "
                           "suben.", "cuerpo", "texto_apagado")]
    e += [llamada(LAT_X - 6, 124, 1), llamada(LAT_X - 6, 206, 2), llamada(LAT_X - 6, 300, 3)]
    return {"id": "cortejo_panel", "fondo": FONDO_PLAZA, "elementos": e}


def propuesta():
    x, y, w, h = 240, 200, 340, 150
    e = [velo(0.5), panel(x, y, w, h, "¿Pedir la mano de Agnès?", False)]
    e += [ret(x + 10, y + 30, "agnes", 32, "soler"),
          t(x + 50, y + 30, 280, 60, "· Se casa con Hugo y pasa a la familia Herrero.\n· Deja su trabajo en el Puesto "
                                     "de comida.\n· Vivirá en vuestra casa (la Forja)."),
          t(x + 50, y + 80, 280, 24, "El primer hijo puede llegar en 1 estación.", "cuerpo", "texto_tenue"),
          sep(x + 10, y + 104, w - 20),
          btn(x + 50, y + 118, "Pedir la mano", 120, 18, "encima"), btn(x + 190, y + 118, "Ahora no", 100, 18)]
    # la sección de cortejo dentro de la ficha de vecino
    fx = LAT_X + 8
    e += [panel(LAT_X, 96, 352, 120, "Agnès · Soler", True),
          ret(fx, 124, "agnes", 32, "soler"), t(fx + 40, 124, 290, 12, "Puesto de comida · Aprendiz · 23 años"),
          sep(fx, 162, 336), t(fx, 166, 200, 12, "Cortejo", "negrita", "#d07090"),
          t(fx + 200, 166, 136, 12, "afinidad 84", "cuerpo", "texto", "der"),
          barra(fx, 180, 336, 6, 0.84, "#d07090", 0.8),
          btn(fx, 192, "Hablar", 80), btn(fx + 84, 192, "Regalar", 80), btn(fx + 168, 192, "Pedir la mano", 110,
                                                                              estado="pulsado")]
    e += [llamada(LAT_X - 6, 166, 1), llamada(x - 6, y, 2)]
    return {"id": "cortejo_propuesta", "fondo": FONDO_PLAZA, "elementos": e}


def boda():
    x, y, w, h = 290, 150, 380, 218
    e = [velo(0.55), panel(x, y, w, h, None, False)]
    e += bandera(x + 14, y + 10, 16, 30, "herrero", "herrero2")
    e += bandera(x + w - 30, y + 10, 16, 30, "soler", "soler2")
    e += [t(x, y + 14, w, 14, "Una boda en la ciudad", "titulo", "oro", "centro"),
          ret(x + 96, y + 40, "hugo", 64, "herrero"), ret(x + 220, y + 40, "agnes", 64, "soler"),
          ico(x + 174, y + 62, I + "icon_ring.png", 32),
          t(x, y + 110, w, 12, "¡Hugo y Agnès se casan!", "negrita", "oro_claro", "centro"),
          sep(x + 16, y + 128, w - 32),
          t(x + 24, y + 134, w - 48, 12, "· Agnès vive ahora en vuestra casa."),
          t(x + 24, y + 148, w - 48, 12, "· Deja su trabajo en el Puesto de comida."),
          t(x + 24, y + 162, w - 48, 12, "· El primer hijo puede llegar desde el día 12.", "cuerpo", "texto_tenue"),
          btn(x + 100, y + 186, "¡Que vivan los novios!", 180, 20)]
    return {"id": "cortejo_boda", "fondo": FONDO_PLAZA, "elementos": e}


MAQUETAS = [panel_cortejo(), propuesta(), boda()]
