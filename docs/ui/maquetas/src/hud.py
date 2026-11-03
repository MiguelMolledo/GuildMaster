"""HUD propuesto (docs/ui/01_hud.md) y la lámina antes/después de docs/ui/00_lenguaje_visual.md.
python3 tools/ui/maqueta.py docs/ui/maquetas/src/hud.py   → docs/ui/maquetas/hud_*.png

Las piezas de HUD son funciones (ficha, barra_estado, reloj...) para que los documentos de mecánica puedan montar su
pantalla encima del mismo HUD: import sys; sys.path.insert(0, "docs/ui/maquetas/src"); import hud; hud.base(...)
Zonas (960×540, margen 4, separación 4): ver ZONAS.
"""

FONDO_MAPA = {"captura": "docs/ui/maquetas/fondos/mapa_dia.png"}
FONDO_PLAZA = {"captura": "docs/ui/maquetas/fondos/plaza_dia.png"}
FONDO_INTERIOR = {"captura": "docs/ui/maquetas/fondos/forja_interior.png"}

# [x, y, w, h] de cada zona fija
ZONAS = {
    "ficha": [4, 4, 236, 50],            # retratos del grupo (1-2-3) + nombre, oro, título del activo
    "estado": [244, 4, 472, 28],         # deuda, accesos a paneles con su tecla, menú
    "reloj": [720, 4, 236, 50],          # hora, fecha, fase, pausa y velocidades
    "columna": [4, 58, 236, 186],        # objetivo (plegable) y órdenes en pausa
    "lateral": [600, 58, 356, 430],      # un panel de gestión a la vez (libro, producción, mercado...)
    "seleccion": [244, 492, 472, 44],    # lo seleccionado: edificio, persona o el interior en el que estás
    "avisos": [4, 404, 236, 132],        # avisos emergentes, de abajo arriba, 3 como mucho
    "centro": [244, 58, 352, 430],       # la vista: lo que se mira; aquí solo menús contextuales y modales
}

PORTRAITS = ["guild:portraits/portrait_artesano.png", "guild:portraits/portrait_artesana.png",
             "guild:portraits/portrait_nino.png"]
FAMILIA = "#a03030"


def ficha(nombre="Hugo", oro="30", titulo="common", titulo_txt="Común", rep="rep. 6", grupo=1, activo=0, cola=None):
    x, y, w, h = ZONAS["ficha"]
    el = [{"tipo": "panel", "rect": [x, y, w, h]}]
    for i in range(grupo):
        extra = {"tecla": str(i + 1), "familia": FAMILIA}
        if cola and i == activo:
            extra["cola"] = cola
        el.append(dict({"tipo": "retrato", "rect": [x + 6 + i * 40, y + 6, 38, 38], "imagen": PORTRAITS[i],
                        "marco": "activo" if i == activo else "normal"}, **extra))
    tx = x + 6 + grupo * 40 + 2
    tw = x + w - 8 - tx
    el += [{"tipo": "texto", "rect": [tx, y + 8, tw, 13], "texto": nombre, "fuente": "negrita"},
           {"tipo": "icono", "rect": [tx, y + 24, 16, 16], "icono": "guild:icons/icon_oro.png"},
           {"tipo": "texto", "rect": [tx + 17, y + 25, 50, 13], "texto": oro, "fuente": "negrita", "color": "oro_claro"},
           {"tipo": "imagen", "rect": [tx + 50, y + 26, 0, 0], "imagen": f"ui:marks/badge_title_{titulo}"},
           {"tipo": "texto", "rect": [tx + 64, y + 25, tw - 64, 13], "texto": f"{titulo_txt} · {rep}",
            "color": "texto_tenue"}]
    return el


def barra_estado(deuda="190", dias="6 días", valor=0.05, pausa=False):
    x, y, w, h = ZONAS["estado"]
    el = [{"tipo": "panel", "rect": [x, y, w, h]},
          {"tipo": "texto", "rect": [x + 9, y + 7, 60, 13], "texto": "Deuda", "color": "texto_tenue"},
          {"tipo": "texto", "rect": [x + 47, y + 7, 40, 13], "texto": deuda, "fuente": "negrita", "color": "negativo"},
          {"tipo": "barra", "rect": [x + 77, y + 11, 66, 6], "valor": valor, "color": "negativo"},
          {"tipo": "texto", "rect": [x + 148, y + 7, 70, 13], "texto": dias, "color": "texto_tenue"}]
    bx = x + 214
    for icon, key in (("guild:icons/icon_libro.png", "L"), ("guild:icons/icon_crown.png", "F"),
                      ("guild:icons/icon_backpack.png", "I"), ("guild:icons/icon_build_mode.png", "B")):
        el.append({"tipo": "boton", "rect": [bx, y + 4, 36, 20], "texto": "", "icono": icon, "tecla": key})
        bx += 38
    el += [{"tipo": "boton", "rect": [bx + 4, y + 4, 36, 20], "texto": "?", "tecla": "F1"},
           {"tipo": "boton", "rect": [x + w - 54, y + 4, 46, 20], "texto": "Menú", "fuente": "cuerpo"}]
    if pausa:
        el += [{"tipo": "caja", "rect": [x + w // 2 - 44, y + h + 2, 88, 15], "color": "hueco", "opacidad": 0.85},
               {"tipo": "texto", "rect": [x + w // 2 - 44, y + h + 3, 88, 13], "texto": "EN PAUSA", "fuente": "negrita",
                "color": "oro_claro", "alinear": "centro"}]
    return el


def reloj(hora="11:17", fecha="Día 3 · Verano · año 1", fase=0.45, velocidad=1, pausa=False, noche=False):
    x, y, w, h = ZONAS["reloj"]
    el = [{"tipo": "panel", "rect": [x, y, w, h]},
          {"tipo": "icono", "rect": [x + 8, y + 8, 16, 16],
           "icono": "guild:icons/icon_moon.png" if noche else "guild:icons/icon_sun.png"},
          {"tipo": "texto", "rect": [x + 28, y + 9, 60, 13], "texto": hora, "fuente": "negrita"},
          {"tipo": "texto", "rect": [x + 8, y + 26, 140, 13], "texto": fecha, "color": "texto_tenue"},
          {"tipo": "barra", "rect": [x + 8, y + 41, 136, 4], "valor": fase}]
    bx = x + 150
    for i, (t, sp) in enumerate((("II", 0), ("1", 1), ("2", 2), ("4", 4))):
        on = (pausa and sp == 0) or (not pausa and sp == velocidad)
        el.append({"tipo": "boton", "rect": [bx + (i % 2) * 40, y + 8 + (i // 2) * 20, 38, 18],
                   "texto": t if sp == 0 else "×" + t, "estado": "pulsado" if on else "normal"})
    return el


def objetivo(titulo="Funde dos lingotes y forja una espada", progreso="2/2 · 0/1",
             pista="Elige a tu personaje y clic derecho en tu Forja. Dentro: clic derecho en el Horno → Trabajar.",
             plegado=False):
    x, y, w, _ = ZONAS["columna"]
    h = 50 if plegado else 104
    el = [{"tipo": "panel", "rect": [x, y, w, h]},
          {"tipo": "texto", "rect": [x + 9, y + 7, 120, 9], "texto": "OBJETIVO", "fuente": "pequena", "color": "oro"},
          {"tipo": "texto", "rect": [x + w - 60, y + 7, 51, 9], "texto": progreso, "fuente": "pequena",
           "color": "positivo", "alinear": "der"},
          {"tipo": "texto", "rect": [x + 9, y + 18, w - 18, 26], "texto": titulo, "fuente": "negrita"}]
    if not plegado:
        el += [{"tipo": "separador", "rect": [x + 9, y + 47, w - 18, 1]},
               {"tipo": "texto", "rect": [x + 9, y + 51, w - 18, 50], "texto": pista, "color": "texto_tenue"}]
    return el, y + h + 4


def cola_ordenes(y, quien="Hugo", ordenes=("Toque de maestro", "Forjar espada (con cuidado)")):
    x, _, w, _ = ZONAS["columna"]
    h = 20 + 13 * len(ordenes)
    el = [{"tipo": "panel", "rect": [x, y, w, h], "estilo": "oscuro"},
          {"tipo": "texto", "rect": [x + 8, y + 4, w - 16, 9], "texto": f"EN PAUSA · ÓRDENES DE {quien.upper()}",
           "fuente": "pequena", "color": "oro"}]
    for i, o in enumerate(ordenes):
        el.append({"tipo": "texto", "rect": [x + 8, y + 15 + i * 13, w - 16, 13], "texto": f"{i + 1}. {o}"})
    return el


def seleccion(nombre="Forja de Hugo", estado="Empleados parados: faltan materiales",
              estado_color="aviso", botones=(("Gestionar", "encima"), ("Producción", "normal")),
              icono="guild:icons/icon_profesion_herrero.png"):
    x, y, w, h = ZONAS["seleccion"]
    el = [{"tipo": "panel", "rect": [x, y, w, h]},
          {"tipo": "icono", "rect": [x + 8, y + 8, 32, 32], "icono": icono},
          {"tipo": "texto", "rect": [x + 44, y + 7, 240, 14], "texto": nombre, "fuente": "titulo", "color": "oro"},
          {"tipo": "texto", "rect": [x + 44, y + 24, 270, 13], "texto": estado, "color": estado_color, "ajustar": False}]
    bx = x + w - 8
    for t, st in reversed(botones):
        from_w = max(56, 10 + 7 * len(t))
        bx -= from_w
        el.append({"tipo": "boton", "rect": [bx, y + 14, from_w, 18], "texto": t, "estado": st})
        bx -= 4
    return el


def barra_interior(nombre="Forja de Hugo", estado="Inés en el yunque · 2 en cola", activa=None):
    x, y, w, h = ZONAS["seleccion"]
    el = [{"tipo": "panel", "rect": [x, y, w, h]},
          {"tipo": "texto", "rect": [x + 9, y + 6, 200, 14], "texto": nombre, "fuente": "titulo", "color": "oro"},
          {"tipo": "texto", "rect": [x + 200, y + 7, w - 210, 13], "texto": estado, "color": "texto_tenue",
           "alinear": "der"}]
    bx = x + 9
    for t, k in (("Producción", "P"), ("Almacén", "A"), ("Empleados", "E"), ("Mejoras", "M")):
        el.append({"tipo": "boton", "rect": [bx, y + 22, 88, 16], "texto": t, "tecla": k, "fuente": "cuerpo",
                   "estado": "pulsado" if t == activa else "normal"})
        bx += 92
    el.append({"tipo": "boton", "rect": [x + w - 80, y + 22, 72, 16], "texto": "Salir", "tecla": "Esc", "fuente": "cuerpo"})
    return el


def avisos(lista):
    x, y, w, h = ZONAS["avisos"]
    el = []
    yy = y + h
    for g, t, ic in lista:
        hh = 24 if len(t) < 34 else 36
        yy -= hh
        el.append({"tipo": "aviso", "rect": [x, yy, w, hh], "gravedad": g, "texto": t, "icono": ic})
        yy -= 3
    return el


def lateral(titulo, pestanas=None, activa=0, alto=None):
    x, y, w, h = ZONAS["lateral"]
    h = alto or h
    el = [{"tipo": "panel", "rect": [x, y, w, h], "titulo": titulo, "cerrar": True}]
    if pestanas:
        el.append({"tipo": "pestanas", "rect": [x + 8, y + 26, 0, 15], "textos": pestanas, "activa": activa})
    return el


# ------------------------------------------------------------------ maquetas

def hud_mapa():
    el = ficha() + barra_estado() + reloj()
    obj, y = objetivo()
    el += obj
    el += seleccion()
    el += avisos([("bien", "Objetivo cumplido: funde dos lingotes.", "guild:icons/icon_completed.png"),
                  ("aviso", "Faltan materiales en el almacén de la forja.", "guild:icons/icon_pending.png")])
    return {"id": "hud_mapa", "fondo": FONDO_MAPA, "elementos": el}


def hud_mapa_llamadas():
    spec = hud_mapa()
    spec = dict(spec, id="hud_mapa_llamadas", fondo=dict(FONDO_MAPA, oscurecer=0.25))
    calls = [(1, 236, 2), (2, 246, 2), (3, 952, 2), (4, 236, 56), (5, 712, 488), (6, 236, 470)]
    spec["elementos"] = spec["elementos"] + [{"tipo": "llamada", "pos": [x, y], "n": n} for n, x, y in calls]
    return spec


def hud_zonas():
    names = {"ficha": "1 · Ficha y grupo (1-2-3)", "estado": "2 · Estado y accesos", "reloj": "3 · Reloj",
             "columna": "4 · Objetivo y órdenes", "lateral": "5 · Panel de gestión (uno)",
             "seleccion": "6 · Selección / edificio", "avisos": "7 · Avisos", "centro": "La vista (libre)"}
    colors = {"ficha": "oro", "estado": "oro", "reloj": "oro", "columna": "info", "lateral": "positivo",
              "seleccion": "aviso", "avisos": "negativo", "centro": "texto_tenue"}
    el = [{"tipo": "zona", "rect": r, "texto": names[k], "color": colors[k]} for k, r in ZONAS.items()]
    el += [{"tipo": "texto", "rect": [252, 230, 336, 60], "fuente": "cuerpo", "color": "texto", "contorno": "hueco",
            "alinear": "centro",
            "texto": "Modales y menús contextuales: sobre la vista.\nTooltips: junto al cursor, nunca encima de lo que señalan."}]
    return {"id": "hud_zonas", "fondo": dict(FONDO_MAPA, oscurecer=0.55, desaturar=0.6), "elementos": el}


def hud_libro():
    """El caso pendiente: el libro de cuentas abierto ya no tapa el panel del edificio."""
    el = ficha(oro="0", rep="rep. 4") + barra_estado(deuda="190", dias="4 días", valor=0.05, pausa=True)
    el += reloj(hora="08:00", fecha="Día 5 · Otoño · año 1", fase=0.1, pausa=True)
    obj, y = objetivo(titulo="Cumple un encargo de calidad «buena»", progreso="0/1", plegado=True)
    el += obj
    x, yy, w, h = ZONAS["lateral"]
    el += lateral("Libro de cuentas", ["Hoy", "Por día", "Edificios", "Deudas", "Avisos"], 3)
    el += [{"tipo": "texto", "rect": [x + 10, yy + 48, 200, 13], "texto": "Préstamo del prestamista", "fuente": "negrita"},
           {"tipo": "texto", "rect": [x + 10, yy + 62, 330, 13], "color": "texto_tenue",
            "texto": "Quedan 190 de 200 · vence el día 8 (en 4 días)"},
           {"tipo": "barra", "rect": [x + 10, yy + 80, 336, 8], "valor": 0.05, "color": "negativo"},
           {"tipo": "campo", "rect": [x + 10, yy + 96, 70, 18], "texto": "", "vacio": "Cantidad"},
           {"tipo": "boton", "rect": [x + 86, yy + 96, 0, 18], "texto": "Pagar", "icono": "guild:icons/icon_oro.png",
            "estado": "desactivado"},
           {"tipo": "texto", "rect": [x + 160, yy + 99, 190, 13], "texto": "No tienes oro", "color": "negativo"},
           {"tipo": "pieza", "pieza": "divider", "rect": [x + 10, yy + 124, 336, 3]},
           {"tipo": "texto", "rect": [x + 10, yy + 132, 200, 13], "texto": "Encargos abiertos", "fuente": "negrita"},
           {"tipo": "lista", "rect": [x + 10, yy + 148, 336, 0], "filas": [
               {"texto": "2 martillos · carpintero", "icono": "icono:hammer", "valor": "1 d 6 h"},
               {"texto": "Espada «buena» · capitán", "icono": "icono:sword", "valor": "2 d", "color_valor": "aviso"}]}]
    el += seleccion()
    return {"id": "hud_libro", "fondo": FONDO_MAPA, "elementos": el}


def hud_interior():
    el = ficha(cola=2) + barra_estado(pausa=True) + reloj(pausa=True)
    obj, y = objetivo(plegado=False)
    el += obj
    el += cola_ordenes(y)
    el += barra_interior(activa=None)
    el += [{"tipo": "tooltip", "rect": [470, 250, 190, 0], "titulo": "Yunque",
            "texto": "Clic derecho: trabajar. Ahora: libre."}]
    return {"id": "hud_interior", "fondo": FONDO_INTERIOR, "elementos": el}


def _base_plaza():
    el = ficha() + barra_estado() + reloj()
    obj, _ = objetivo(plegado=True)
    return el + obj


def hud_avisos_menu():
    """Avisos emergentes, menú contextual (clic derecho en un puesto) y tooltip."""
    el = _base_plaza()
    el += seleccion(nombre="Parcela 7 (producción)", estado="Libre · 3×3 casillas · 120 de oro",
                    estado_color="texto_tenue", botones=(("Construir…", "encima"),),
                    icono="guild:parcels/parcel_production.png")
    el += avisos([("info", "Inés ha llegado a la forja.", "guild:icons/icon_working.png"),
                  ("aviso", "El encargo del carpintero vence mañana.", "guild:icons/icon_contrato.png"),
                  ("urgente", "La deuda vence en 2 días.", "guild:icons/icon_warning.png")])
    el += [{"tipo": "panel", "rect": [262, 120, 170, 102], "estilo": "oscuro"},
           {"tipo": "texto", "rect": [270, 124, 150, 9], "texto": "PUESTO DE RECURSOS", "fuente": "pequena",
            "color": "oro"},
           {"tipo": "lista", "rect": [266, 136, 162, 0], "seleccionada": 1, "alto_fila": 16, "filas": [
               {"texto": "Ir aquí"}, {"texto": "Comprar…"}, {"texto": "Vender…"},
               {"texto": "Recado de entrega", "apagada": True}]},
           {"tipo": "texto", "rect": [270, 205, 160, 13], "texto": "Falta el título Ciudadano",
            "color": "negativo"},
           {"tipo": "imagen", "rect": [258, 116, 0, 0], "imagen": "ui:cursor/cursor_arrow"},
           {"tipo": "imagen", "rect": [744, 300, 0, 0], "imagen": "ui:cursor/cursor_hand"},
           {"tipo": "tooltip", "rect": [758, 314, 180, 0], "titulo": "Armería",
            "texto": "Compra espadas y armaduras. Abierta de 7 a 19."}]
    return {"id": "hud_avisos_menu", "fondo": FONDO_PLAZA, "elementos": el}


def hud_confirmacion():
    el = _base_plaza()
    el += seleccion(nombre="Parcela 7 (producción)", estado="Libre · 3×3 casillas · 120 de oro",
                    estado_color="texto_tenue", botones=(("Construir…", "pulsado"),),
                    icono="guild:parcels/parcel_production.png")
    el += [{"tipo": "velo", "rect": [0, 0, 960, 540], "opacidad": 0.5},
           {"tipo": "panel", "rect": [340, 200, 280, 120], "titulo": "¿Construir la Taberna?"},
           {"tipo": "texto", "rect": [350, 228, 260, 28], "texto": "Cuesta 600 de oro y tarda 3 días. Te quedan 140."},
           {"tipo": "texto", "rect": [350, 258, 260, 13], "texto": "No se puede deshacer.", "color": "aviso"},
           {"tipo": "boton", "rect": [350, 294, 120, 18], "texto": "Cancelar", "tecla": "Esc"},
           {"tipo": "boton", "rect": [490, 294, 120, 18], "texto": "Construir", "estado": "encima", "tecla": "Intro"}]
    return {"id": "hud_confirmacion", "fondo": FONDO_PLAZA, "elementos": el}


TECLAS = [
    ("En el pueblo", [("Clic izquierdo", "elegir persona o edificio"), ("Doble clic", "gestionar tu edificio"),
                      ("Clic derecho", "ir / entrar / usar"), ("WASD, flechas", "mover la cámara"),
                      ("Rueda, botón central", "acercar / arrastrar")]),
    ("Tiempo", [("Espacio", "pausa (las órdenes esperan en cola)"), ("Mayús+1 / 2 / 3", "velocidad ×1 ×2 ×4")]),
    ("Familia", [("1 / 2 / 3", "elegir familiar (doble: centrar)"), ("F", "árbol de la familia"),
                 ("I", "inventario de la persona")]),
    ("Paneles", [("L", "libro de cuentas"), ("B", "construir (desde H6)"), ("P, A, E, M", "dentro: producción, almacén, empleados, mejoras"),
                 ("Esc", "cierra lo de arriba; sin nada abierto: menú"), ("F1 o ?", "esta ayuda")]),
]


def hud_ayuda():
    el = ficha() + barra_estado(pausa=True) + reloj(pausa=True)
    el += [{"tipo": "velo", "opacidad": 0.55},
           {"tipo": "panel", "rect": [180, 60, 600, 420], "estilo": "parchment"},
           {"tipo": "texto", "rect": [196, 70, 568, 16], "texto": "Ayuda · controles", "fuente": "titulo",
            "color": "texto_tinta"},
           {"tipo": "texto", "rect": [600, 72, 164, 13], "texto": "F1, ? o Esc: cerrar", "color": "madera",
            "alinear": "der"},
           {"tipo": "pieza", "pieza": "divider", "rect": [196, 90, 568, 3]}]
    col = [196, 488]
    y = [100, 100]
    for i, (sec, rows) in enumerate(TECLAS):
        c = 0 if i in (0, 1) else 1
        el.append({"tipo": "texto", "rect": [col[c], y[c], 270, 14], "texto": sec, "fuente": "titulo",
                   "color": "madera"})
        y[c] += 18
        for k, d in rows:
            kw = max(26, 8 + 7 * len(k))
            el += [{"tipo": "pieza", "pieza": "field", "rect": [col[c], y[c], kw, 15]},
                   {"tipo": "texto", "rect": [col[c], y[c] + 1, kw, 13], "texto": k, "fuente": "negrita",
                    "color": "oro_claro", "alinear": "centro"},
                   {"tipo": "texto", "rect": [col[c] + kw + 6, y[c] + 1, 270 - kw - 6, 26], "texto": d,
                    "color": "texto_tinta"}]
            y[c] += 18 if len(d) < 30 else 30
        y[c] += 8
    el += [{"tipo": "pieza", "pieza": "divider", "rect": [196, 400, 568, 3]},
           {"tipo": "texto", "rect": [196, 410, 568, 14], "texto": "Ahora mismo", "fuente": "titulo",
            "color": "madera"},
           {"tipo": "texto", "rect": [196, 428, 568, 40], "color": "texto_tinta",
            "texto": "Objetivo: funde dos lingotes y forja una espada. Compra hierro en Recursos, funde en el horno y "
                     "forja en el yunque. La deuda vence el día 8."}]
    return {"id": "hud_ayuda", "fondo": FONDO_MAPA, "elementos": el}


def hud_antes_despues():
    """Lámina de 00: arriba el HUD de hoy (captura real), abajo el propuesto sobre el mismo pueblo."""
    after = hud_mapa()["elementos"]
    moved = []
    for e in after:
        e = dict(e)
        if "rect" in e:
            r = list(e["rect"])
            r[1] += 540
            e["rect"] = r
        if "pos" in e:
            e["pos"] = [e["pos"][0], e["pos"][1] + 540]
        moved.append(e)
    el = [{"tipo": "imagen", "rect": [0, 0, 960, 540], "imagen": "docs/novedades/ui_mapa_despues.png"},
          {"tipo": "imagen", "rect": [0, 540, 960, 540], "imagen": "docs/ui/maquetas/fondos/mapa_dia.png"}]
    el += moved
    for y, t in ((520, "HOY"), (1060, "PROPUESTO")):
        el += [{"tipo": "caja", "rect": [860, y, 96, 16], "color": "hueco", "opacidad": 0.85},
               {"tipo": "texto", "rect": [860, y + 1, 96, 13], "texto": t, "fuente": "negrita", "color": "oro_claro",
                "alinear": "centro"}]
    return {"id": "lamina_hud_antes_despues", "tam": [960, 1080], "fondo": {"color": "hueco"}, "elementos": el}


MAQUETAS = [hud_mapa(), hud_mapa_llamadas(), hud_zonas(), hud_libro(), hud_interior(), hud_avisos_menu(), hud_confirmacion(),
            hud_ayuda(), hud_antes_despues()]
