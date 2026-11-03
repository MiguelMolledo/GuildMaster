"""Maquetas de docs/ui/mecanicas/mejoras.md.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/mejoras.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from economia_base import (FONDO_FORJA, I, IT, barra, btn, caja, check, confirmacion, filete, ico, llamada,  # noqa
                           motivo, panel, sep, t)
from economia_base import hud_interior  # noqa: E402

PX, PY, PW, PH = 244, 58, 712, 430   # panel ancho = vista + lateral (01_hud)
CX = PX + 8
COL = {"owned": "#7cc860", "in_works": "#f0c040", "available": "#ece4d2", "blocked": "#8a8070"}

RAMAS = [
    ("produccion", "Producción", [("Fuelle mejorado", 15, "owned"), ("Temple avanzado", 40, "falta"),
                                  ("Forja de maestro", 100, "lock")]),
    ("capacidad", "Capacidad", [("Segundo yunque", 50, "falta"), ("Almacén ampliado", 40, "lock"),
                                ("Tercer horno", 125, "lock")]),
    ("calidad", "Calidad", [("Acero templado", 25, "ok"), ("Grabado fino", 60, "lock"), ("Sello de maestro", 150, "lock")]),
    ("comercio", "Comercio", [("Mostrador de venta", 30, "falta"), ("Escaparate exterior", 75, "lock"),
                              ("Reputación comercial", 125, "lock+")]),
    ("personal", "Personal", [("Dormitorio de aprendiz", 40, "falta"), ("Comedor", 60, "lock"),
                              ("Taller de maestro", 150, "lock+")]),
    ("fachada", "Fachada", [("Fachada de piedra", 75, "falta"), ("Jardín y plantas", 100, "lock"),
                            ("Fachada noble", 200, "titulo")]),
    ("seguridad", "Seguridad", [("Cerradura reforzada", 25, "ok"), ("Guardia contratado", 75, "lock"),
                                ("Caja fuerte", 150, "lock")]),
    ("secretos", "Secretos", [("Doble contabilidad", 50, "ok"), ("Pasadizo oculto", 100, "lock+"),
                              ("Contrabando", 175, "lock")]),
]


def celda(x, y, w, h, nombre, precio, st, sel=False, obra=False):
    estado = {"owned": "owned", "ok": "available", "falta": "available", "lock": "blocked", "lock+": "blocked",
              "titulo": "blocked", "obra": "in_works", "una": "available"}[st]
    col = COL[estado]
    e = [caja(x, y, w, h, col), caja(x + 1, y + 1, w - 2, h - 2, "madera" if sel else "fila")]
    if sel:
        e += filete(x, y, w, h, "oro_claro")
    icon = {"owned": "icon_completed.png", "ok": "icon_oro.png", "lock": "icon_locked.png", "lock+": "icon_locked.png",
            "titulo": "icon_crown.png", "obra": "icon_in_progress.png"}.get(st)
    if icon:
        e.append(ico(x + 3, y + 4, I + icon, 12))
    else:
        e.append(caja(x + 7, y + 8, 3, 3, "texto_apagado"))
    tc = "texto_apagado" if estado == "blocked" else ("oro_claro" if sel else col if estado != "available" else "texto")
    e.append(t(x + 18, y + 3, w - 50, 12, nombre, color=tc, ajustar=False))
    if st != "owned":
        pc = "negativo" if st == "falta" and nombre == "Fachada de piedra" else (
            "texto_apagado" if estado == "blocked" else "oro_claro")
        e.append(t(x + w - 34, y + 3, 30, 12, str(precio), "negrita", pc, "der"))
    if st == "lock+":
        e.append(t(x + w - 46, y + 3, 12, 12, "+", "negrita", "info"))
    if obra:
        e.append(barra(x + 18, y + h - 4, w - 22, 3, 0.55, "aviso"))
    return e


def arbol(seleccion, en_obra=False):
    e = hud_interior("Mejoras", estado="Sin obras")
    e.append(panel(PX, PY, PW, PH, "Mejoras · Forja"))
    yy = PY + 26
    if en_obra:
        e += [ico(CX, yy - 1, I + "icon_in_progress.png"), t(CX + 20, yy, 230, 12, "En obra: Temple avanzado", "negrita",
                                                              "aviso"),
              barra(CX + 230, yy + 3, 250, 7, 0.55, "aviso"),
              t(CX + 486, yy, PW - 16 - 486, 12, "quedan 11 h · fin día 4, 06:00", color="texto_tenue", alinear="der")]
    else:
        e += [t(CX, yy, 480, 12, "Sin obras. Una a la vez: mientras dura, la Forja no produce.", color="texto_tenue"),
              t(CX + 480, yy, PW - 16 - 480, 12, "Hechas: 1 de 24", color="texto_tenue", alinear="der")]
    yy += 18
    lx, cw = CX + 104, 196
    for i, nv in enumerate(["NIVEL 1", "NIVEL 2", "NIVEL 3"]):
        e.append(t(lx + i * (cw + 3), yy, cw, 9, nv, "pequena", "oro", "centro"))
    yy += 11
    for rid, rname, ups in RAMAS:
        e += [ico(CX, yy + 2, I + "icon_rama_%s.png" % rid, 16), t(CX + 20, yy + 4, 84, 12, rname, "negrita")]
        for i, (n, p, st) in enumerate(ups):
            if en_obra and n == "Temple avanzado":
                st = "obra"
            e += celda(lx + i * (cw + 3), yy, cw, 20, n, p, st, sel=(n == seleccion), obra=(st == "obra"))
        yy += 22
    yy += 4
    e.append(sep(CX, yy, PW - 16))
    yy += 6
    return e, yy


def detalle_segundo_yunque(e, yy, en_obra=False):
    e += [t(CX, yy, 300, 14, "SEGUNDO YUNQUE", "negrita", "oro_claro"),
          t(CX + 140, yy + 1, 200, 12, "Capacidad · nivel 1", color="texto_tenue"),
          t(PX + PW - 160, yy + 1, 150, 12, "Una obra a la vez" if en_obra else "Falta material",
            color="aviso" if en_obra else "negativo", alinear="der")]
    yy += 16
    e.append(t(CX, yy, PW - 16, 12, "Efecto: un segundo yunque. Dos personas pueden forjar a la vez."))
    yy += 15
    e += [t(CX, yy, 50, 12, "Coste:", color="texto_tenue"), ico(CX + 50, yy - 2, I + "icon_oro.png"),
          t(CX + 68, yy, 90, 12, "50 (tienes 65)"), check(CX + 160, yy, True),
          ico(CX + 186, yy - 2, IT + "iron_ingot"), t(CX + 204, yy, 120, 12, "5 lingotes (hay 2)", color="negativo"),
          check(CX + 324, yy, False),
          ico(CX + 350, yy - 2, IT + "wood"), t(CX + 368, yy, 110, 12, "3 madera (hay 3)"), check(CX + 480, yy, True)]
    yy += 15
    e.append(t(CX, yy, PW - 16, 12, "Requisitos: ninguno", color="texto_tenue"))
    yy += 15
    e.append(t(CX, yy, PW - 16, 12, "Obra: 1 día. La Forja no produce: la cola se para; los salarios se pagan igual.",
               color="aviso"))
    yy += 15
    e.append(t(CX, yy, 400, 12, "Se verá: un yunque nuevo junto al primero.", color="texto_tenue"))
    why = "Hay otra obra en marcha (una a la vez)" if en_obra else "Falta: 3 lingotes de hierro en el almacén"
    e += [motivo(CX + 300, yy + 16, 300, why) if False else motivo(PX + PW - 420, yy + 18, 320, why),
          btn(PX + PW - 96, yy + 15, "Construir", 86, 16, "desactivado")]
    return e


def mejoras():
    e, yy = arbol("Segundo yunque")
    e = detalle_segundo_yunque(e, yy)
    e.append({"tipo": "tooltip", "rect": [PX + 320, PY + 56, 262, 0], "titulo": "Reputación comercial",
              "lineas": ["Necesita Fachada de piedra (Fachada 1)", "y Escaparate exterior (Comercio 2)."]})
    e += filete(PX + 8 + 104, PY + 55 + 22 * 5, 196, 20, "oro_claro")
    e += filete(PX + 8 + 104 + 199, PY + 55 + 22 * 3, 196, 20, "oro_claro")
    e += filete(PX + 8 + 104 + 398, PY + 55 + 22 * 3, 196, 20, "aviso")
    e += [llamada(PX - 6, PY + 24, 1), llamada(PX + 104, PY + 52, 2), llamada(PX + 600, PY + 130, 3),
          llamada(PX - 6, PY + 236, 4), llamada(PX - 6, PY + 284, 5)]
    return {"id": "mejoras", "fondo": FONDO_FORJA, "elementos": e}


def obra():
    e, yy = arbol("Segundo yunque", True)
    e = detalle_segundo_yunque(e, yy, True)
    e += [llamada(PX - 6, PY + 24, 1), llamada(PX + 300, PY + 54, 2)]
    return {"id": "mejoras_obra", "fondo": FONDO_FORJA, "elementos": e}


def confirmar():
    e, yy = arbol("Acero templado")
    e += confirmacion("Construir Acero templado", [
        ("Pagas", "25 de oro y 3 carbón (te quedan 40)", None),
        ("Obra", "1 día: hasta el día 3 a las 10:00", None),
        ("Mientras", "la Forja no produce; salarios igual", "aviso"),
        ("Efecto", "calidad +1 escalón de probabilidad", "positivo"),
        ("", None, None),
        ("La obra no se puede cancelar.", None, "negativo"),
    ], "Construir", y=170, w=400)
    return {"id": "mejoras_confirmar", "fondo": FONDO_FORJA, "elementos": e}


MAQUETAS = [mejoras(), obra(), confirmar()]
