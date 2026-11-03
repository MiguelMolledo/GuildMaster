"""Láminas de docs/ui/00_lenguaje_visual.md: tipografía, colores, componentes y estados, iconos.
python3 tools/ui/maqueta.py docs/ui/maquetas/src/laminas_00.py   → docs/ui/maquetas/lamina_*.png
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
GUILD_UI = os.environ.get("GUILD_UI", os.path.expanduser("~/Code/guild/assets/sprites/ui"))
TOKENS = json.load(open(os.path.join(ROOT, "tools", "ui", "tokens.json"), encoding="utf-8"))

OBJ_TITLE = "Cumple un encargo de calidad «buena»"
OBJ_BODY = "Acepta en el tablón un encargo de calidad «buena». Trabaja con cuidado y haz clic en el puesto mientras parpadea."
NUMBERS = "Deuda 190 · quedan 6 días · 10 de oro · ×2 · −16 → 42"


# ------------------------------------------------------------------ tipografía

def font_row(y, h, name, lic, verdict, ok, title_f, body_f, button_f, body_lh=None):
    el = [
        {"tipo": "texto", "rect": [8, y + 4, 224, 13], "texto": name, "fuente": "negrita", "color": "oro_claro"},
        {"tipo": "texto", "rect": [8, y + 18, 224, 13], "texto": lic, "fuente": "cuerpo", "color": "texto_tenue"},
        {"tipo": "texto", "rect": [8, y + 34, 224, h - 36], "texto": verdict, "fuente": "cuerpo",
         "color": "positivo" if ok else "texto"},
        {"tipo": "panel", "rect": [236, y, 716, h - 4]},
        {"tipo": "texto", "rect": [246, y + 8, 440, 16], "texto": OBJ_TITLE, "fuente": title_f, "color": "oro"},
        {"tipo": "texto", "rect": [246, y + 26, 440, h - 34], "texto": OBJ_BODY + "\n" + NUMBERS, "fuente": body_f},
        {"tipo": "boton", "rect": [700, y + 10, 120, 18], "texto": "Libro (L)", "fuente": button_f},
        {"tipo": "boton", "rect": [826, y + 10, 118, 18], "texto": "Gestionar", "fuente": button_f, "estado": "encima"},
        {"tipo": "boton", "rect": [700, y + 34, 244, 18], "texto": "Pagar la deuda", "fuente": button_f,
         "estado": "desactivado"},
        {"tipo": "texto", "rect": [700, y + 56, 244, 12], "texto": "Te faltan 160 de oro", "fuente": body_f,
         "color": "negativo"},
    ]
    return el


def lamina_fuentes():
    el = [{"tipo": "texto", "rect": [8, 4, 940, 16], "fuente": "titulo", "color": "oro",
           "texto": "Tipografía · candidatas con texto real del juego, a tamaño 1:1 (960×540)"}]
    y = 26
    # hoy: recorte de una captura real (×2 reducida a la mitad)
    el += [
        {"tipo": "texto", "rect": [8, y + 4, 224, 13], "texto": "Hoy", "fuente": "negrita", "color": "oro_claro"},
        {"tipo": "texto", "rect": [8, y + 18, 224, 60], "fuente": "cuerpo", "color": "texto",
         "texto": "Fuente lisa por defecto de Godot en el cuerpo + Silkscreen en botones. Dos voces que no casan; la lisa se suaviza."},
        {"tipo": "imagen", "rect": [236, y, 0, 0], "imagen": "docs/novedades/ui_mapa_despues.png",
         "recorte": [1482, 248, 424, 236], "escala": 0.5},
        {"tipo": "imagen", "rect": [452, y + 2, 0, 0], "imagen": "docs/novedades/ui_mapa_despues.png",
         "recorte": [522, 14, 876, 60], "escala": 0.5},
    ]
    y += 124
    el += font_row(y, 100, "A · Pixel Operator 16", "CC0 · títulos: Jacquarda (OFL)",
                   "Recomendada. Nítida, minúsculas claras, ñ y acentos; una sola familia (normal, negrita y 8).",
                   True, "titulo", "cuerpo", "boton")
    y += 100
    el += font_row(y, 96, "B · Tiny5 8", "OFL · todo",
                   "Muy compacta: cabe mucho, pero a 960×540 cansa leer párrafos (mayúscula de 5 px).",
                   False, "tiny5.ttf:8", "tiny5.ttf:8", "tiny5.ttf:8")
    y += 96
    el += font_row(y, 100, "C · VT323 16", "OFL · todo",
                   "Legible pero de terminal: suena a ordenador, no a gremio. Ocupa más alto y no trae →.",
                   False, "vt323.ttf:16", "vt323.ttf:16", "vt323.ttf:16")
    y += 100
    el += font_row(y, 96, "D · Silkscreen 8", "OFL · como los botones de hoy",
                   "Solo mayúsculas y muy ancha; sin − ni →. Vale para rótulos cortos, no para frases.",
                   False, "silkscreen_regular.ttf:8", "silkscreen_regular.ttf:8", "silkscreen_regular.ttf:8")
    return {"id": "lamina_fuentes", "fondo": {"color": "hueco"}, "elementos": el}


def lamina_titulos():
    """Escala tipográfica de la recomendada: qué papel tiene cada tamaño."""
    rows = [
        ("titulo", "Título de panel · Jacquarda Bastarda 9 a 13", "Libro de cuentas · Árbol de la familia · Forja de Hugo"),
        ("negrita", "Énfasis, cifras, botones · Pixel Operator Bold 16", "30 de oro   +42   −16   Pagar   Gestionar"),
        ("cuerpo", "Cuerpo · Pixel Operator 16", "Acepta en el tablón un encargo de calidad «buena». ¿Pagar ahora? ¡Ruina!"),
        ("pequena", "Pequeña · Pixel Operator 8 (teclas, contadores, notas)", "L  F1  ×2  1/3  Día 3 · Verano · año 1  ÁÉÍÓÚ Ñ"),
    ]
    el = [{"tipo": "panel", "rect": [4, 4, 952, 152], "titulo": "Escala tipográfica (la recomendada)"}]
    for i, (role, label, sample) in enumerate(rows):
        y = 32 + i * 30
        el += [{"tipo": "texto", "rect": [14, y, 300, 13], "texto": label, "fuente": "cuerpo", "color": "texto_tenue"},
               {"tipo": "texto", "rect": [330, y, 616, 16], "texto": sample, "fuente": role,
                "color": "oro" if role == "titulo" else "texto"}]
    return el


# ------------------------------------------------------------------ colores

def lamina_colores():
    el = [{"tipo": "texto", "rect": [8, 4, 940, 16], "fuente": "titulo", "color": "oro",
           "texto": "Tokens de color (tools/ui/tokens.json) · los de la biblia van marcados con ●"}]
    biblia = {"madera", "remache", "pergamino", "seccion", "oro", "hueco", "positivo", "negativo"}
    for i, (name, hexv) in enumerate(TOKENS["color"].items()):
        x, y = 8 + (i % 4) * 238, 28 + (i // 4) * 36
        el += [{"tipo": "caja", "rect": [x, y, 30, 30], "color": "texto_tenue"},
               {"tipo": "caja", "rect": [x + 1, y + 1, 28, 28], "color": hexv},
               {"tipo": "texto", "rect": [x + 36, y + 2, 196, 13], "texto": ("● " if name in biblia else "") + name,
                "fuente": "negrita"},
               {"tipo": "texto", "rect": [x + 36, y + 16, 196, 13], "texto": hexv, "fuente": "cuerpo",
                "color": "texto_tenue"}]
    y = 28 + ((len(TOKENS["color"]) + 3) // 4) * 36 + 8
    el += lamina_titulos_at(y)
    return {"id": "lamina_colores", "fondo": {"color": "seccion"}, "elementos": el}


def lamina_titulos_at(y):
    out = []
    for e in lamina_titulos():
        e = dict(e)
        r = list(e["rect"])
        r[1] += y - 4
        e["rect"] = r
        out.append(e)
    return out


# ------------------------------------------------------------------ componentes y estados

def lamina_estados():
    el = [{"tipo": "texto", "rect": [8, 4, 940, 16], "fuente": "titulo", "color": "oro",
           "texto": "Componentes y estados (piezas reales: assets/art/ui/theme, marks, cursor)"}]
    # botones
    el.append({"tipo": "texto", "rect": [8, 26, 200, 13], "texto": "Botón", "fuente": "negrita", "color": "oro_claro"})
    for i, (st, lab) in enumerate([("normal", "Normal"), ("encima", "Encima"), ("pulsado", "Pulsado"),
                                   ("desactivado", "Desactivado")]):
        el += [{"tipo": "boton", "rect": [8 + i * 100, 42, 92, 18], "texto": "Gestionar", "estado": st},
               {"tipo": "texto", "rect": [8 + i * 100, 62, 92, 9], "texto": lab, "fuente": "pequena",
                "color": "texto_tenue", "alinear": "centro"}]
    el += [{"tipo": "boton", "rect": [408, 42, 0, 18], "texto": "Pagar", "icono": "guild:icons/icon_oro.png"},
           {"tipo": "boton", "rect": [480, 42, 0, 18], "texto": "Libro", "tecla": "L"},
           {"tipo": "boton", "rect": [548, 42, 18, 18], "texto": "×", "fuente": "negrita"},
           {"tipo": "texto", "rect": [408, 62, 220, 9], "texto": "con icono · con tecla · cerrar", "fuente": "pequena",
            "color": "texto_tenue"},
           {"tipo": "boton", "rect": [640, 42, 120, 18], "texto": "Pagar la deuda", "estado": "desactivado"},
           {"tipo": "texto", "rect": [640, 62, 300, 13], "texto": "Te faltan 160 de oro (motivo siempre visible)",
            "fuente": "cuerpo", "color": "negativo"}]
    # pestañas, campos, checks, slider
    el += [{"tipo": "texto", "rect": [8, 82, 200, 13], "texto": "Pestañas", "fuente": "negrita", "color": "oro_claro"},
           {"tipo": "panel", "rect": [8, 112, 300, 40]},
           {"tipo": "pestanas", "rect": [16, 98, 0, 15], "textos": ["Hoy", "Por día", "Deudas", "Avisos"], "activa": 1},
           {"tipo": "texto", "rect": [18, 124, 280, 13], "texto": "La activa se abre al panel.", "color": "texto_tenue"},
           {"tipo": "texto", "rect": [330, 82, 200, 13], "texto": "Campo", "fuente": "negrita", "color": "oro_claro"},
           {"tipo": "campo", "rect": [330, 98, 100, 16], "texto": "", "vacio": "Cantidad"},
           {"tipo": "campo", "rect": [440, 98, 100, 16], "texto": "20", "cursor": True},
           {"tipo": "texto", "rect": [330, 118, 220, 9], "texto": "vacío · escribiendo", "fuente": "pequena",
            "color": "texto_tenue"},
           {"tipo": "texto", "rect": [570, 82, 200, 13], "texto": "Casilla y deslizador", "fuente": "negrita",
            "color": "oro_claro"},
           {"tipo": "imagen", "rect": [570, 101, 0, 0], "imagen": "pieza:check_off"},
           {"tipo": "texto", "rect": [584, 99, 120, 13], "texto": "Auto-repetir"},
           {"tipo": "imagen", "rect": [570, 119, 0, 0], "imagen": "pieza:check_on"},
           {"tipo": "texto", "rect": [584, 117, 120, 13], "texto": "Pantalla completa"},
           {"tipo": "pieza", "pieza": "slider_track", "rect": [720, 104, 160, 6]},
           {"tipo": "caja", "rect": [721, 105, 96, 4], "color": "oro"},
           {"tipo": "imagen", "rect": [814, 101, 0, 0], "imagen": "pieza:slider_grabber"},
           {"tipo": "texto", "rect": [886, 99, 70, 13], "texto": "60 %"},
           {"tipo": "texto", "rect": [720, 117, 220, 9], "texto": "volumen de música", "fuente": "pequena",
            "color": "texto_tenue"}]
    # barras
    el += [{"tipo": "texto", "rect": [8, 160, 200, 13], "texto": "Barras", "fuente": "negrita", "color": "oro_claro"},
           {"tipo": "barra", "rect": [8, 178, 140, 8], "valor": 0.65},
           {"tipo": "texto", "rect": [154, 176, 150, 13], "texto": "progreso", "color": "texto_tenue"},
           {"tipo": "barra", "rect": [8, 192, 140, 8], "valor": 0.85, "color": "positivo"},
           {"tipo": "texto", "rect": [154, 190, 150, 13], "texto": "lealtad alta", "color": "texto_tenue"},
           {"tipo": "barra", "rect": [8, 206, 140, 8], "valor": 0.05, "color": "negativo", "marca": 0.5},
           {"tipo": "texto", "rect": [154, 204, 150, 13], "texto": "deuda, con umbral", "color": "texto_tenue"},
           {"tipo": "barra", "rect": [8, 220, 140, 12], "valor": 0.4, "texto": "3 h 54"},
           {"tipo": "texto", "rect": [154, 220, 150, 13], "texto": "con texto", "color": "texto_tenue"}]
    # retratos
    el.append({"tipo": "texto", "rect": [330, 160, 200, 13], "texto": "Retratos", "fuente": "negrita",
               "color": "oro_claro"})
    for i, (m, lab, extra) in enumerate([("activo", "activo", {"tecla": "1", "familia": "#a03030"}),
                                         ("normal", "tuyo", {"tecla": "2", "familia": "#a03030", "cola": 3}),
                                         ("apagado", "ajeno", {"familia": "#3060a0"}),
                                         ("muerto", "muerto", {"familia": "#a03030"}),
                                         ("normal", "heredero", {"familia": "#a03030", "corona": True})]):
        img = ["guild:portraits/portrait_artesano.png", "guild:portraits/portrait_artesana.png",
               "guild:portraits/portrait_mercader.png", "guild:portraits/portrait_aldeano.png",
               "guild:portraits/portrait_nino.png"][i]
        el += [dict({"tipo": "retrato", "rect": [330 + i * 54, 182, 40, 40], "imagen": img, "marco": m}, **extra),
               {"tipo": "texto", "rect": [324 + i * 54, 226, 52, 9], "texto": lab, "fuente": "pequena",
                "color": "texto_tenue", "alinear": "centro"}]
    # insignias
    el.append({"tipo": "texto", "rect": [600, 160, 340, 13], "texto": "Insignias: título · cargo · rango · sello",
               "fuente": "negrita", "color": "oro_claro"})
    for i, t in enumerate(["common", "citizen", "patrician", "baron", "noble"]):
        el.append({"tipo": "imagen", "rect": [600 + i * 18, 182, 0, 0], "imagen": f"ui:marks/badge_title_{t}"})
    for i, o in enumerate(["mayor", "councillor", "judge", "constable", "collector", "inspector"]):
        el.append({"tipo": "imagen", "rect": [600 + i * 18, 202, 0, 0], "imagen": f"ui:marks/badge_office_{o}"})
    for i in range(3):
        el.append({"tipo": "imagen", "rect": [700 + i * 14, 184, 0, 0], "imagen": f"ui:marks/rank_{i + 1}"})
    el += [{"tipo": "imagen", "rect": [750, 180, 0, 0], "imagen": "ui:marks/seal"},
           {"tipo": "texto", "rect": [600, 222, 350, 9], "fuente": "pequena", "color": "texto_tenue",
            "texto": "común ciudadano patricio barón nobleza · alcalde concejal juez alguacil recaudador inspector"}]
    # listas, avisos, tooltip, pergamino, cursores
    el += [{"tipo": "texto", "rect": [8, 244, 200, 13], "texto": "Lista", "fuente": "negrita", "color": "oro_claro"},
           {"tipo": "lista", "rect": [8, 260, 300, 0], "seleccionada": 1, "filas": [
               {"texto": "Venta de espada", "icono": "icono:sword", "valor": "+42", "color_valor": "positivo"},
               {"texto": "Compra de hierro ×4", "icono": "icono:iron", "valor": "−16", "color_valor": "negativo"},
               {"texto": "Salario de Inés (mañana)", "valor": "−6", "color_valor": "negativo", "apagada": True}]},
           {"tipo": "texto", "rect": [8, 324, 300, 9], "texto": "normal · seleccionada · apagada", "fuente": "pequena",
            "color": "texto_tenue"},
           {"tipo": "texto", "rect": [330, 244, 200, 13], "texto": "Avisos", "fuente": "negrita", "color": "oro_claro"}]
    for i, (g, t, ic) in enumerate([("info", "Inés ha llegado a la forja.", "guild:icons/icon_working.png"),
                                    ("bien", "Objetivo cumplido: vende la espada.", "guild:icons/icon_completed.png"),
                                    ("aviso", "Faltan materiales en el almacén.", "guild:icons/icon_pending.png"),
                                    ("urgente", "La deuda vence en 2 días.", "guild:icons/icon_warning.png")]):
        el.append({"tipo": "aviso", "rect": [330, 260 + i * 26, 250, 24], "gravedad": g, "texto": t, "icono": ic})
    el += [{"tipo": "texto", "rect": [600, 244, 200, 13], "texto": "Tooltip y documento", "fuente": "negrita",
            "color": "oro_claro"},
           {"tipo": "tooltip", "rect": [600, 260, 170, 0], "titulo": "Hierro",
            "texto": "Compra 4 · vende 2. Demanda alta."},
           {"tipo": "panel", "rect": [780, 260, 170, 104], "estilo": "parchment"},
           {"tipo": "texto", "rect": [790, 266, 150, 14], "texto": "Encargo", "fuente": "titulo",
            "color": "texto_tinta"},
           {"tipo": "texto", "rect": [790, 282, 150, 60], "texto": "2 martillos para el carpintero en 2 días. Prima: 12.",
            "color": "texto_tinta"},
           {"tipo": "imagen", "rect": [924, 340, 0, 0], "imagen": "ui:marks/seal"},
           {"tipo": "texto", "rect": [600, 330, 170, 13], "texto": "Cursores", "fuente": "negrita",
            "color": "oro_claro"},
           {"tipo": "imagen", "rect": [604, 346, 0, 0], "imagen": "ui:cursor/cursor_arrow"},
           {"tipo": "imagen", "rect": [624, 347, 0, 0], "imagen": "ui:cursor/cursor_hand"},
           {"tipo": "imagen", "rect": [646, 349, 0, 0], "imagen": "ui:cursor/cursor_wait"}]
    # scroll y separador
    el += [{"tipo": "texto", "rect": [8, 346, 300, 13], "texto": "Scroll y separador", "fuente": "negrita",
            "color": "oro_claro"},
           {"tipo": "pieza", "pieza": "scroll_track", "rect": [8, 362, 6, 60]},
           {"tipo": "pieza", "pieza": "scroll_grabber", "rect": [8, 372, 6, 20]},
           {"tipo": "pieza", "pieza": "divider", "rect": [24, 390, 280, 3]},
           {"tipo": "texto", "rect": [24, 398, 280, 13], "texto": "Separador con rombos en las puntas.",
            "color": "texto_tenue"}]
    # modal de confirmación
    el += [{"tipo": "texto", "rect": [330, 370, 400, 13], "texto": "Confirmación (lo caro o irreversible)",
            "fuente": "negrita", "color": "oro_claro"},
           {"tipo": "panel", "rect": [330, 386, 280, 120], "titulo": "¿Construir la Taberna?"},
           {"tipo": "texto", "rect": [340, 414, 260, 40], "color": "texto",
            "texto": "Cuesta 600 de oro y tarda 3 días. Te quedan 140."},
           {"tipo": "texto", "rect": [340, 444, 260, 13], "color": "aviso",
            "texto": "No se puede deshacer."},
           {"tipo": "boton", "rect": [340, 480, 120, 18], "texto": "Cancelar"},
           {"tipo": "boton", "rect": [480, 480, 120, 18], "texto": "Construir", "estado": "encima",
            "icono": "guild:icons/icon_build_mode.png"}]
    return {"id": "lamina_estados", "fondo": {"color": "seccion"}, "elementos": el}


# ------------------------------------------------------------------ iconos

ICON_USES = {   # icono de Guild Renew → uso en la UI (los objetos van por su id)
    "icon_oro": "oro", "icon_sun": "reloj: día", "icon_moon": "reloj: noche", "icon_libro": "libro de cuentas",
    "icon_contrato": "encargos", "icon_documento": "crónica, documentos", "icon_crown": "heredero, títulos",
    "icon_ring": "boda, pareja", "icon_deceased": "fallecido", "icon_controllable": "controlable",
    "icon_backpack": "inventario", "icon_build_mode": "construir", "icon_demolish": "demoler",
    "icon_warning": "aviso urgente", "icon_completed": "hecho", "icon_pending": "pendiente",
    "icon_in_progress": "en curso", "icon_working": "trabajando", "icon_idle": "parado", "icon_locked": "bloqueado",
    "icon_loop": "auto-repetir", "icon_close": "cerrar", "icon_sound_on": "sonido", "icon_sound_off": "silencio",
    "icon_llave": "propiedad, llaves", "icon_profesion_herrero": "herrero", "icon_serving": "mostrador",
}


def lamina_iconos():
    el = [{"tipo": "texto", "rect": [8, 4, 940, 16], "fuente": "titulo", "color": "oro",
           "texto": "Iconos de Guild Renew: a 32 (tal cual) y a 16 (mitad, vecino más cercano) · nombre y uso"}]
    names = sorted(n[:-4] for n in os.listdir(os.path.join(GUILD_UI, "icons")) if n.endswith(".png"))
    names = [n for n in names if not n.startswith("bubble_")]
    cols = 6
    for i, n in enumerate(names):
        x, y = 6 + (i % cols) * 158, 24 + (i // cols) * 40
        use = ICON_USES.get(n, "")
        el += [{"tipo": "caja", "rect": [x, y, 154, 38], "color": "fila"},
               {"tipo": "icono", "rect": [x + 2, y + 3, 32, 32], "icono": f"guild:icons/{n}.png"},
               {"tipo": "icono", "rect": [x + 36, y + 11, 16, 16], "icono": f"guild:icons/{n}.png"},
               {"tipo": "texto", "rect": [x + 56, y + 4, 98, 9], "texto": n.replace("icon_", ""), "fuente": "pequena",
                "color": "texto"},
               {"tipo": "texto", "rect": [x + 56, y + 16, 98, 20], "texto": use, "fuente": "pequena",
                "color": "oro_claro"}]
    rows = (len(names) + cols - 1) // cols
    return {"id": "lamina_iconos", "tam": [960, 24 + rows * 40 + 6], "fondo": {"color": "hueco"}, "elementos": el}


MAQUETAS = [lamina_fuentes(), lamina_colores(), lamina_estados(), lamina_iconos()]
