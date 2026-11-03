"""Maquetas de docs/ui/02_menu_inicial.md: título, partida nueva, cargar y guardar, opciones, créditos, pausa, salir y
final de partida.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/menu.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud  # noqa: E402

LOGO = "assets/art/ui/logo/guildmaster_logo_x2.png"
FAM = "#a03030"
FAM2 = "#c8a84e"


def banda_izquierda(w=300):
    """Velo de la izquierda en tres escalones (sin degradado suave, biblia)."""
    return [{"tipo": "caja", "rect": [0, 0, w, 540], "color": "velo", "opacidad": 0.72},
            {"tipo": "caja", "rect": [w, 0, 16, 540], "color": "velo", "opacidad": 0.5},
            {"tipo": "caja", "rect": [w + 16, 0, 16, 540], "color": "velo", "opacidad": 0.28}]


def menu_titulo():
    el = banda_izquierda()
    el += [{"tipo": "imagen", "rect": [40, 40, 0, 0], "imagen": LOGO}]
    y = 150
    items = [("Continuar", "encima", "Los Herrero · día 5, otoño, año 1"),
             ("Partida nueva", "normal", None), ("Cargar partida", "normal", None), ("Opciones", "normal", None),
             ("Créditos", "normal", None), ("Salir", "normal", None)]
    for t, st, sub in items:
        el.append({"tipo": "boton", "rect": [56, y, 200, 22], "texto": t, "estado": st})
        y += 26
        if sub:
            el.append({"tipo": "texto", "rect": [58, y - 2, 240, 13], "texto": sub, "color": "texto_tenue"})
            y += 16
    el += [{"tipo": "texto", "rect": [56, 512, 240, 9], "texto": "v0.10 · rebanada vertical", "fuente": "pequena",
            "color": "texto_tenue"},
]
    return {"id": "menu_titulo", "fondo": {"captura": "docs/ui/maquetas/fondos/titulo_atardecer.png"}, "elementos": el}


STATS = [("Carisma", 5, True), ("Empatía", 3, False), ("Negociación", 6, False), ("Arcano", 1, False),
         ("Destreza", 4, False), ("Artesanía", 9, True), ("Marcial", 3, False), ("Constitución", 5, False),
         ("Retórica", 3, False), ("Sigilo", 2, False)]
PALETTE = ["#8c2a2a", "#2a4a8c", "#3a6a3a", "#5a3a7a", "#8a6a2a", "#2a6a6a", "#c8a84e", "#d4b896", "#a8a8a0",
           "#e0dcc8", "#5a3a2a", "#20202a"]


def swatches(x, y, sel):
    el = []
    for i, c in enumerate(PALETTE):
        cx = x + i * 18
        if i == sel:
            el.append({"tipo": "caja", "rect": [cx - 2, y - 2, 18, 18], "color": "oro_claro"})
        el += [{"tipo": "caja", "rect": [cx - 1, y - 1, 16, 16], "color": "hueco"},
               {"tipo": "caja", "rect": [cx, y, 14, 14], "color": c}]
    return el


def escudo_familia(x, y, c1, c2):
    """Escudo de la familia con sus dos colores (para la vista previa; en el juego, una escena con el shader)."""
    el = [{"tipo": "imagen", "rect": [x, y, 36, 36], "imagen": "ui:marks/badge_title_common"}]
    el += [{"tipo": "caja", "rect": [x + 6, y + 3, 12, 21], "color": c1},
           {"tipo": "caja", "rect": [x + 18, y + 3, 12, 21], "color": c2},
           {"tipo": "caja", "rect": [x + 9, y + 24, 18, 3], "color": c1},
           {"tipo": "caja", "rect": [x + 12, y + 27, 12, 3], "color": c2}]
    return el


def menu_partida_nueva():
    x, y, w, h = 104, 20, 752, 500
    el = [{"tipo": "panel", "rect": [x, y, w, h], "titulo": "Partida nueva"},
          {"tipo": "texto", "rect": [x + 160, y + 7, 300, 13], "texto": "Artesano · herrero", "color": "texto_tenue"}]
    lx = x + 12
    # dificultad
    el += [{"tipo": "texto", "rect": [lx, y + 32, 200, 13], "texto": "Dificultad", "fuente": "negrita", "color": "oro"}]
    for i, (t, st) in enumerate((("Fácil", "normal"), ("Normal", "pulsado"), ("Difícil", "normal"))):
        el.append({"tipo": "boton", "rect": [lx + i * 116, y + 48, 112, 20], "texto": t, "estado": st})
    el += [{"tipo": "texto", "rect": [lx, y + 72, 350, 13], "color": "texto_tenue",
            "texto": "Deuda 200 de oro · rival con Artesanía 5 · precios 100 %"}]
    # nombre y familia
    el += [{"tipo": "texto", "rect": [lx, y + 96, 120, 13], "texto": "Nombre", "fuente": "negrita", "color": "oro"},
           {"tipo": "campo", "rect": [lx, y + 112, 200, 18], "texto": "Hugo", "cursor": True},
           {"tipo": "boton", "rect": [lx + 208, y + 112, 70, 18], "texto": "Hombre", "estado": "pulsado"},
           {"tipo": "boton", "rect": [lx + 282, y + 112, 64, 18], "texto": "Mujer"},
           {"tipo": "texto", "rect": [lx, y + 138, 120, 13], "texto": "Familia", "fuente": "negrita", "color": "oro"},
           {"tipo": "campo", "rect": [lx, y + 154, 200, 18], "texto": "Herrero"},
           {"tipo": "texto", "rect": [lx + 208, y + 157, 150, 13], "texto": "Los Herrero", "color": "texto_tenue"}]
    # colores
    el += [{"tipo": "texto", "rect": [lx, y + 182, 200, 13], "texto": "Color principal", "fuente": "negrita",
            "color": "oro"}]
    el += swatches(lx + 2, y + 200, 0)
    el += [{"tipo": "texto", "rect": [lx, y + 222, 200, 13], "texto": "Color secundario", "fuente": "negrita",
            "color": "oro"}]
    el += swatches(lx + 2, y + 240, 6)
    # vista previa
    el += [{"tipo": "panel", "rect": [lx, y + 266, 346, 112], "estilo": "oscuro"},
           {"tipo": "retrato", "rect": [lx + 8, y + 274, 70, 70], "imagen": "guild:portraits/portrait_artesano.png",
            "marco": "activo", "familia": FAM},
           {"tipo": "texto", "rect": [lx + 88, y + 276, 200, 14], "texto": "Hugo de los Herrero", "fuente": "titulo",
            "color": "oro"},
           {"tipo": "texto", "rect": [lx + 88, y + 294, 200, 13], "texto": "20 años · herrero · Común",
            "color": "texto_tenue"},
           {"tipo": "texto", "rect": [lx + 88, y + 310, 210, 40], "color": "texto",
            "texto": "Forja con vivienda, 30 de oro y 200 de deuda con el prestamista."}]
    el += escudo_familia(lx + 300, y + 276, FAM, FAM2)
    el += [{"tipo": "texto", "rect": [lx + 8, y + 352, 330, 22], "fuente": "pequena", "color": "texto_tenue",
            "texto": "EL COLOR PRINCIPAL VISTE A LOS TUYOS EN EL PUEBLO Y BORDEA SUS RETRATOS."}]
    # atributos
    rx = x + 384
    el += [{"tipo": "texto", "rect": [rx, y + 32, 200, 13], "texto": "Atributos", "fuente": "negrita", "color": "oro"},
           {"tipo": "texto", "rect": [rx + 160, y + 32, 196, 13], "texto": "Puntos libres: 2 de 5", "fuente": "negrita",
            "color": "oro_claro", "alinear": "der"}]
    for i, (n, v, up) in enumerate(STATS):
        ry = y + 50 + i * 21
        sel = n == "Artesanía"
        el += [{"tipo": "fila", "rect": [rx, ry, 356, 19], "texto": n, "seleccionada": sel},
               {"tipo": "boton", "rect": [rx + 260, ry + 1, 18, 17], "texto": "−",
                "estado": "normal" if up else "desactivado"},
               {"tipo": "texto", "rect": [rx + 280, ry + 3, 30, 13], "texto": str(v), "fuente": "negrita",
                "color": "positivo" if up else "texto", "alinear": "centro"},
               {"tipo": "boton", "rect": [rx + 312, ry + 1, 18, 17], "texto": "+"}]
    el += [{"tipo": "panel", "rect": [rx, y + 266, 356, 112], "estilo": "oscuro"},
           {"tipo": "texto", "rect": [rx + 8, y + 272, 340, 14], "texto": "Artesanía", "fuente": "titulo",
            "color": "oro"},
           {"tipo": "texto", "rect": [rx + 8, y + 290, 340, 80], "color": "texto",
            "texto": "Calidad y rapidez en el horno y el yunque. Es lo que más rinde para un herrero al empezar. "
                     "Los puntos solo suben (de 1 a 10)."}]
    # pie
    el += [{"tipo": "pieza", "pieza": "divider", "rect": [x + 12, y + 388, w - 24, 3]},
           {"tipo": "texto", "rect": [x + 12, y + 398, 520, 26], "color": "texto_tenue",
            "texto": "Empiezas al amanecer del día 1 de primavera del año 1. Podrás cambiar a quién controlas, no los atributos."},
           {"tipo": "boton", "rect": [x + 12, y + h - 34, 120, 22], "texto": "Volver", "tecla": "Esc"},
           {"tipo": "boton", "rect": [x + w - 172, y + h - 34, 160, 22], "texto": "Empezar", "estado": "encima",
            "tecla": "Intro"}]
    return {"id": "menu_partida_nueva", "fondo": {"captura": "docs/ui/maquetas/fondos/titulo_dia.png", "oscurecer": 0.6,
                                                  "desaturar": 0.4}, "elementos": el}


SLOTS = [
    ("Autoguardado", "Hugo, herrero · Día 5, otoño, año 1", "1.250 de oro · Ciudadano · deuda pagada", "hoy, 18:42",
     "docs/ui/maquetas/fondos/mapa_dia.png", "ok"),
    ("Ranura 1", "Hugo, herrero · Día 3, verano, año 1", "30 de oro · Común · deuda 190", "ayer, 22:10",
     "docs/ui/maquetas/fondos/plaza_dia.png", "ok"),
    ("Ranura 2", "", "", "", None, "vacia"),
    ("Ranura 3", "No se puede leer: es de una versión más nueva del juego.", "", "1 nov, 12:03", None, "rota"),
]


def lista_ranuras(x, y, w, modo):
    el = []
    for i, (name, l1, l2, when, thumb, st) in enumerate(SLOTS):
        if modo == "guardar" and name == "Autoguardado":
            continue
        cy = y + len(el and [0]) * 0
        el_y = y + (i if modo == "cargar" else i - 1) * 86
        sel = (modo == "cargar" and i == 1) or (modo == "guardar" and i == 1)
        el += [{"tipo": "fila", "rect": [x, el_y, w, 80], "seleccionada": sel, "texto": ""}]
        if thumb:
            el += [{"tipo": "caja", "rect": [x + 6, el_y + 6, 122, 70], "color": "hueco"},
                   {"tipo": "imagen", "rect": [x + 7, el_y + 7, 120, 68], "imagen": thumb, "recorte": [240, 135, 480, 272]}]
        else:
            el += [{"tipo": "pieza", "pieza": "field", "rect": [x + 6, el_y + 6, 122, 70]},
                   {"tipo": "texto", "rect": [x + 6, el_y + 33, 122, 13], "texto": "—" if st == "vacia" else "?",
                    "color": "texto_apagado", "alinear": "centro"}]
        el += [{"tipo": "texto", "rect": [x + 138, el_y + 8, 240, 14], "texto": name, "fuente": "titulo",
                "color": "oro_claro" if sel else "oro"}]
        if st == "ok":
            el += [{"tipo": "texto", "rect": [x + 138, el_y + 26, 300, 13], "texto": l1},
                   {"tipo": "texto", "rect": [x + 138, el_y + 41, 300, 13], "texto": l2, "color": "texto_tenue"},
                   {"tipo": "texto", "rect": [x + 138, el_y + 58, 300, 13], "texto": "Guardada " + when,
                    "color": "texto_tenue"}]
        elif st == "vacia":
            el += [{"tipo": "texto", "rect": [x + 138, el_y + 30, 300, 13], "texto": "Vacía", "color": "texto_apagado"}]
        else:
            el += [{"tipo": "texto", "rect": [x + 138, el_y + 26, 300, 30], "texto": l1, "color": "negativo"},
                   {"tipo": "texto", "rect": [x + 138, el_y + 58, 300, 13], "texto": "Guardada " + when,
                    "color": "texto_tenue"}]
        bx = x + w - 96
        if modo == "cargar":
            el += [{"tipo": "boton", "rect": [bx, el_y + 14, 88, 20], "texto": "Cargar",
                    "estado": "encima" if sel else ("normal" if st == "ok" else "desactivado")},
                   {"tipo": "boton", "rect": [bx, el_y + 44, 88, 20], "texto": "Borrar", "fuente": "cuerpo",
                    "estado": "desactivado" if st == "vacia" or name == "Autoguardado" else "normal"}]
        else:
            el += [{"tipo": "boton", "rect": [bx, el_y + 28, 88, 20], "texto": "Guardar aquí", "fuente": "cuerpo",
                    "estado": "encima" if sel else ("normal" if st != "rota" else "normal")}]
    return el


def menu_cargar():
    x, y, w, h = 160, 30, 640, 480
    el = [{"tipo": "panel", "rect": [x, y, w, h], "titulo": "Cargar partida", "cerrar": True}]
    el += lista_ranuras(x + 10, y + 32, w - 20, "cargar")
    el += [{"tipo": "texto", "rect": [x + 12, y + h - 30, 400, 13], "color": "texto_tenue",
            "texto": "El autoguardado se hace solo al amanecer de cada día."},
           {"tipo": "boton", "rect": [x + w - 132, y + h - 34, 120, 22], "texto": "Volver", "tecla": "Esc"}]
    return {"id": "menu_cargar", "fondo": {"captura": "docs/ui/maquetas/fondos/titulo_atardecer.png", "oscurecer": 0.6,
                                           "desaturar": 0.4}, "elementos": el}


def menu_guardar():
    el = hud.ficha() + hud.barra_estado(pausa=True) + hud.reloj(pausa=True)
    x, y, w, h = 160, 60, 640, 400
    el += [{"tipo": "velo", "opacidad": 0.55},
           {"tipo": "panel", "rect": [x, y, w, h], "titulo": "Guardar partida", "cerrar": True}]
    el += lista_ranuras(x + 10, y + 32, w - 20, "guardar")
    el += [{"tipo": "boton", "rect": [x + w - 132, y + h - 34, 120, 22], "texto": "Volver", "tecla": "Esc"},
           {"tipo": "velo", "opacidad": 0.4},
           {"tipo": "panel", "rect": [340, 200, 280, 120], "titulo": "¿Sobrescribir la ranura 1?"},
           {"tipo": "texto", "rect": [350, 228, 260, 40], "texto": "Se pierde la partida del día 3, verano, año 1."},
           {"tipo": "boton", "rect": [350, 294, 120, 18], "texto": "Cancelar", "tecla": "Esc"},
           {"tipo": "boton", "rect": [490, 294, 120, 18], "texto": "Sobrescribir", "estado": "encima", "tecla": "Intro"}]
    return {"id": "menu_guardar", "fondo": hud.FONDO_MAPA, "elementos": el}


BUSES = [("General", 0.8, "Master"), ("Música", 0.6, "Music"), ("Efectos", 0.8, "Sfx"), ("Ambiente", 0.7, "Ambient"),
         ("Voces", 0.8, "Voice"), ("Interfaz", 0.5, "Ui")]


def slider(x, y, w, v):
    return [{"tipo": "pieza", "pieza": "slider_track", "rect": [x, y + 3, w, 6]},
            {"tipo": "caja", "rect": [x + 1, y + 4, int((w - 2) * v), 4], "color": "oro"},
            {"tipo": "imagen", "rect": [x + int((w - 2) * v) - 3, y, 0, 0], "imagen": "pieza:slider_grabber"}]


def opcion_botones(x, y, textos, activo, ancho=60):
    return [{"tipo": "boton", "rect": [x + i * (ancho + 4), y, ancho, 18], "texto": t,
             "estado": "pulsado" if i == activo else "normal", "fuente": "cuerpo"} for i, t in enumerate(textos)]


def menu_opciones():
    x, y, w, h = 120, 90, 720, 360
    el = [{"tipo": "panel", "rect": [x, y, w, h], "titulo": "Opciones", "cerrar": True}]
    lx, rx = x + 14, x + 372
    el += [{"tipo": "texto", "rect": [lx, y + 32, 300, 14], "texto": "Sonido", "fuente": "titulo", "color": "oro"}]
    for i, (n, v, bus) in enumerate(BUSES):
        ry = y + 54 + i * 26
        el += [{"tipo": "texto", "rect": [lx, ry, 90, 13], "texto": n},
               {"tipo": "texto", "rect": [lx + 280, ry, 40, 13], "texto": f"{int(v * 100)} %", "alinear": "der",
                "color": "texto_tenue"}]
        el += slider(lx + 92, ry, 180, v)
    el += [{"tipo": "imagen", "rect": [lx, y + 216, 0, 0], "imagen": "pieza:check_on"},
           {"tipo": "texto", "rect": [lx + 14, y + 214, 300, 13], "texto": "Bajar el sonido si la ventana no está activa"},
           {"tipo": "texto", "rect": [lx, y + 244, 300, 14], "texto": "Idioma", "fuente": "titulo", "color": "oro"}]
    el += opcion_botones(lx, y + 264, ["Español", "English"], 0, 80)
    el += [{"tipo": "texto", "rect": [rx, y + 32, 300, 14], "texto": "Pantalla", "fuente": "titulo", "color": "oro"},
           {"tipo": "imagen", "rect": [rx, y + 56, 0, 0], "imagen": "pieza:check_on"},
           {"tipo": "texto", "rect": [rx + 14, y + 54, 300, 13], "texto": "Pantalla completa (F11)"},
           {"tipo": "texto", "rect": [rx, y + 78, 140, 13], "texto": "Escala"}]
    el += opcion_botones(rx + 120, y + 76, ["×2", "×3", "×4"], 0, 44)
    el += [{"tipo": "texto", "rect": [rx + 120, y + 96, 220, 9], "fuente": "pequena", "color": "texto_tenue",
            "texto": "SOLO LAS QUE CABEN ENTERAS"},
           {"tipo": "texto", "rect": [rx, y + 112, 140, 13], "texto": "Tamaño del texto"}]
    el += opcion_botones(rx + 120, y + 110, ["Normal", "Grande"], 0, 70)
    el += [{"tipo": "texto", "rect": [rx + 120, y + 130, 220, 9], "fuente": "pequena", "color": "texto_tenue",
            "texto": "GRANDE: NEGRITA, MÁS AIRE"},
           {"tipo": "texto", "rect": [rx, y + 152, 300, 14], "texto": "Juego", "fuente": "titulo", "color": "oro"},
           {"tipo": "texto", "rect": [rx, y + 174, 140, 13], "texto": "Velocidad al cargar"}]
    el += opcion_botones(rx + 140, y + 172, ["×1", "×2", "×4"], 0, 40)
    el += [{"tipo": "texto", "rect": [rx, y + 198, 140, 13], "texto": "Avisos que saltan"}]
    el += opcion_botones(rx + 140, y + 196, ["Urgentes", "Todos"], 1, 72)
    el += [{"tipo": "imagen", "rect": [rx, y + 224, 0, 0], "imagen": "pieza:check_on"},
           {"tipo": "texto", "rect": [rx + 14, y + 222, 300, 13], "texto": "Pausar al perder el foco"},
           {"tipo": "imagen", "rect": [rx, y + 242, 0, 0], "imagen": "pieza:check_off"},
           {"tipo": "texto", "rect": [rx + 14, y + 240, 300, 13], "texto": "Mostrar la línea de ayuda abajo"},
           {"tipo": "imagen", "rect": [rx, y + 260, 0, 0], "imagen": "pieza:check_on"},
           {"tipo": "texto", "rect": [rx + 14, y + 258, 300, 13], "texto": "Pistas de los objetivos"}]
    el += [{"tipo": "pieza", "pieza": "divider", "rect": [x + 12, y + h - 46, w - 24, 3]},
           {"tipo": "boton", "rect": [x + 12, y + h - 34, 150, 22], "texto": "Valores por defecto", "fuente": "cuerpo"},
           {"tipo": "texto", "rect": [x + 180, y + h - 30, 300, 13], "texto": "Los cambios se aplican al momento.",
            "color": "texto_tenue"},
           {"tipo": "boton", "rect": [x + w - 132, y + h - 34, 120, 22], "texto": "Volver", "tecla": "Esc"}]
    return {"id": "menu_opciones", "fondo": {"captura": "docs/ui/maquetas/fondos/titulo_atardecer.png", "oscurecer": 0.6,
                                             "desaturar": 0.4}, "elementos": el}


CREDITS = [
    ("Diseño, dirección y juego", ["Miguel Molledo"]),
    ("Hecho con", ["Godot 4.7 · GDScript", "Claude Code (agentes de Grimoire)"]),
    ("Arte", ["PixelLab y piezas a mano (Pillow)", "Arte reutilizado de Guild Renew"]),
    ("Sonido y voces", ["ElevenLabs"]),
    ("Letras", ["Pixel Operator · Jayvee Enaguas (CC0)", "Jacquarda Bastarda 9 y Jacquard 24 · The Soft Type Project (OFL)",
                "Silkscreen · Jason Kottke (OFL)"]),
]


def menu_creditos():
    x, y, w, h = 230, 20, 500, 500
    el = [{"tipo": "velo", "opacidad": 0.35},
          {"tipo": "panel", "rect": [x, y, w, h], "estilo": "parchment"},
          {"tipo": "imagen", "rect": [x + (w - 374) // 2, y + 14, 0, 0], "imagen": LOGO},
          {"tipo": "pieza", "pieza": "divider", "rect": [x + 20, y + 92, w - 40, 3]}]
    cy = y + 104
    for sec, lines in CREDITS:
        el.append({"tipo": "texto", "rect": [x + 20, cy, w - 40, 14], "texto": sec, "fuente": "titulo",
                   "color": "madera", "alinear": "centro"})
        cy += 17
        for l in lines:
            el.append({"tipo": "texto", "rect": [x + 20, cy, w - 40, 13], "texto": l, "color": "texto_tinta",
                       "alinear": "centro"})
            cy += 14
        cy += 8
    el += [{"tipo": "imagen", "rect": [x + w // 2 - 8, y + h - 66, 0, 0], "imagen": "ui:marks/seal"},
           {"tipo": "texto", "rect": [x + 20, y + h - 44, w - 40, 13], "texto": "Gracias por jugar.",
            "color": "texto_tinta", "alinear": "centro"},
           {"tipo": "boton", "rect": [x + w // 2 - 60, y + h - 28, 120, 20], "texto": "Volver", "tecla": "Esc"}]
    return {"id": "menu_creditos", "fondo": {"captura": "docs/ui/maquetas/fondos/rio_atardecer.png", "oscurecer": 0.3},
            "elementos": el}


def menu_pausa():
    el = hud.ficha() + hud.barra_estado(pausa=True) + hud.reloj(pausa=True)
    obj, _ = hud.objetivo(plegado=True)
    el += obj + hud.seleccion()
    x, y, w, h = 370, 92, 220, 334
    el += [{"tipo": "velo", "opacidad": 0.6},
           {"tipo": "panel", "rect": [x, y, w, h], "titulo": "Pausa"}]
    items = [("Seguir", "encima", "Esc"), ("Guardar", "normal", "F5"), ("Cargar", "normal", "F9"),
             ("Opciones", "normal", None), ("Ayuda", "normal", "F1"), (None, None, None),
             ("Cerrar la dinastía…", "normal", None), ("Salir al título", "normal", None), ("Salir del juego", "normal", None)]
    by = y + 32
    for t, st, k in items:
        if t is None:
            el.append({"tipo": "pieza", "pieza": "divider", "rect": [x + 12, by + 2, w - 24, 3]})
            by += 12
            continue
        e = {"tipo": "boton", "rect": [x + 14, by, w - 28, 22], "texto": t, "estado": st}
        if k:
            e["tecla"] = k
        el.append(e)
        by += 28
    el += [{"tipo": "texto", "rect": [x + 14, y + h - 22, w - 28, 13], "texto": "Último guardado: hace 12 min",
            "color": "texto_tenue", "alinear": "centro"}]
    return {"id": "menu_pausa", "fondo": hud.FONDO_MAPA, "elementos": el}


def menu_salir():
    el = hud.ficha() + hud.barra_estado(pausa=True) + hud.reloj(pausa=True)
    el += [{"tipo": "velo", "opacidad": 0.6},
           {"tipo": "panel", "rect": [320, 196, 320, 128], "titulo": "¿Salir del juego?"},
           {"tipo": "texto", "rect": [330, 224, 300, 40],
            "texto": "Se pierde lo jugado desde el último guardado (hace 12 min)."},
           {"tipo": "boton", "rect": [330, 294, 92, 20], "texto": "Cancelar", "fuente": "cuerpo", "tecla": "Esc"},
           {"tipo": "boton", "rect": [426, 294, 100, 20], "texto": "Sin guardar", "fuente": "cuerpo"},
           {"tipo": "boton", "rect": [530, 294, 100, 20], "texto": "Guardar y salir", "fuente": "cuerpo",
            "estado": "encima"}]
    return {"id": "menu_salir", "fondo": hud.FONDO_MAPA, "elementos": el}


SCORE = [("Nacimientos", "1", "10"), ("Bodas", "1", "20"), ("Títulos: Ciudadano", "1", "25"),
         ("Edificios construidos", "1", "15"), ("Patrimonio máximo (1.350)", "", "13")]


def menu_fin():
    x, y, w, h = 120, 40, 720, 400
    el = [{"tipo": "velo", "opacidad": 0.45},
          {"tipo": "panel", "rect": [x, y - 24, w, h + 24], "estilo": "parchment"},
          {"tipo": "texto", "rect": [x + 20, y - 18, w - 40, 30], "texto": "Fin de la dinastía", "fuente": "jacquard_24.ttf:43",
           "color": "lacre", "alinear": "centro"},
          {"tipo": "texto", "rect": [x + 20, y + 22, w - 40, 13], "color": "texto_tinta", "alinear": "centro",
           "texto": "El cabeza de los Herrero ha muerto sin heredero: la dinastía termina aquí."},
          {"tipo": "texto", "rect": [x + 20, y + 37, w - 40, 13], "color": "madera", "alinear": "centro",
           "texto": "Día 9, primavera, año 2 · 00:00"},
          {"tipo": "imagen", "rect": [x + w - 44, y - 10, 0, 0], "imagen": "ui:marks/seal"},
          {"tipo": "pieza", "pieza": "divider", "rect": [x + 20, y + 58, w - 40, 3]}]
    y -= 6
    lx, rx = x + 20, x + 380
    el += [{"tipo": "texto", "rect": [lx, y + 76, 320, 14], "texto": "Crónica", "fuente": "titulo", "color": "madera"},
           {"tipo": "retrato", "rect": [lx, y + 96, 38, 38], "imagen": "guild:portraits/portrait_artesano.png",
            "marco": "muerto", "familia": FAM},
           {"tipo": "texto", "rect": [lx + 46, y + 98, 290, 13], "texto": "Hugo de los Herrero", "fuente": "negrita",
            "color": "texto_tinta"},
           {"tipo": "texto", "rect": [lx + 46, y + 112, 290, 26], "color": "texto_tinta",
            "texto": "Cabeza del día 1 al 9 · † a los 75 años"}]
    facts = [("ui:marks/badge_title_citizen", "Ciudadano el día 6"), ("guild:icons/icon_ring.png", "Casado con Elvira el día 4"),
             ("guild:icons/icon_build_mode.png", "Construyó la Taberna el día 7"),
             ("guild:icons/icon_oro.png", "Patrimonio máximo: 1.350 de oro")]
    for i, (ic, t) in enumerate(facts):
        fy = y + 148 + i * 20
        el += [{"tipo": "icono", "rect": [lx, fy, 16, 16], "icono": ic},
               {"tipo": "texto", "rect": [lx + 22, fy + 2, 300, 13], "texto": t, "color": "texto_tinta"}]
    el += [{"tipo": "texto", "rect": [lx, y + 236, 320, 14], "texto": "Metas de dinastía", "fuente": "titulo",
            "color": "madera"}]
    for i, (t, ok) in enumerate((("Alcalde", False), ("Cinco generaciones", False), ("Fortuna (20.000)", False))):
        el += [{"tipo": "imagen", "rect": [lx, y + 258 + i * 18, 0, 0], "imagen": "pieza:check_on" if ok else "pieza:check_off"},
               {"tipo": "texto", "rect": [lx + 16, y + 256 + i * 18, 300, 13], "texto": t, "color": "texto_tinta"}]
    el += [{"tipo": "texto", "rect": [rx, y + 76, 320, 14], "texto": "Puntuación", "fuente": "titulo", "color": "madera"}]
    for i, (t, n, p) in enumerate(SCORE):
        fy = y + 98 + i * 18
        el += [{"tipo": "texto", "rect": [rx, fy, 230, 13], "texto": t, "color": "texto_tinta"},
               {"tipo": "texto", "rect": [rx + 230, fy, 30, 13], "texto": n, "color": "madera", "alinear": "der"},
               {"tipo": "texto", "rect": [rx + 270, fy, 50, 13], "texto": p, "fuente": "negrita", "color": "texto_tinta",
                "alinear": "der"}]
    ty = y + 98 + len(SCORE) * 18 + 4
    el += [{"tipo": "caja", "rect": [rx, ty, 320, 1], "color": "madera"},
           {"tipo": "texto", "rect": [rx, ty + 6, 200, 14], "texto": "Total", "fuente": "titulo", "color": "madera"},
           {"tipo": "texto", "rect": [rx + 200, ty + 5, 120, 13], "texto": "83 puntos", "fuente": "negrita",
            "color": "lacre", "alinear": "der"}]
    el += [{"tipo": "pieza", "pieza": "divider", "rect": [x + 20, y + h - 52, w - 40, 3]},
           {"tipo": "boton", "rect": [x + 20, y + h - 38, 150, 22], "texto": "Ver el pueblo"},
           {"tipo": "boton", "rect": [x + w // 2 - 75, y + h - 38, 150, 22], "texto": "Partida nueva", "estado": "encima"},
           {"tipo": "boton", "rect": [x + w - 170, y + h - 38, 150, 22], "texto": "Salir al título"}]
    return {"id": "menu_fin", "fondo": {"captura": "docs/ui/maquetas/fondos/rio_atardecer.png", "oscurecer": 0.4,
                                        "desaturar": 0.5}, "elementos": el}


MAQUETAS = [menu_titulo(), menu_partida_nueva(), menu_cargar(), menu_guardar(), menu_opciones(), menu_creditos(),
            menu_pausa(), menu_salir(), menu_fin()]
