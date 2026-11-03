"""Maquetas de docs/ui/mecanicas/produccion.md.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/produccion.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from economia_base import (CW, FAM_HERRERO, FONDO_FORJA, I, IT, LAT_X, X, aviso, barra, barra_ventana, btn, caja,  # noqa
                           filete, ico, lateral, llamada, motivo, pestanas, ret, sep, t)
from economia_base import hud_interior  # noqa: E402

PY = 58


def base(titulo, h, activa):
    e = hud_interior("Producción", estado="Cola parada: falta hierro", insignias={0: ("!", "negativo")})
    e.append(lateral(titulo, h, PY))
    e.append(pestanas(X, PY + 26, ["Ahora", "Cola", "Recetas"], activa))
    return e


def pips(x, y, hechas, total):
    out = []
    for i in range(total):
        out += [caja(x + i * 7, y, 6, 6, "madera_oscura"), caja(x + i * 7 + 1, y + 1, 4, 4,
                                                                "positivo" if i < hechas else "hueco")]
    return out


def cola():
    e = base("Producción · Forja", 300, 1)
    e += [btn(X + CW - 150, PY + 25, "Bucle: no", 72, 14, fuente="cuerpo", icono=I + "icon_loop.png"),
          btn(X + CW - 74, PY + 25, "Pausar", 74, 14, fuente="cuerpo")]
    yy = PY + 48
    entradas = [
        (IT + "sword", "1  Espada", "2/5", 2, 5, "Trabajando", "positivo",
         ("antes: 2 lingotes (se funden en el horno)", "texto_apagado")),
        (IT + "hammer", "2  Martillo", "0/siempre", 0, 0, "En espera", "texto_tenue", None),
        (IT + "armor", "3  Armadura", "0/1", 0, 1, "Saltada", "negativo",
         ("Artesanía del empleado: necesita 6 (Joan 5)", "negativo")),
    ]
    for k, (icon, name, qty, done, tot, st, stc, sub) in enumerate(entradas):
        e.append(caja(X, yy, CW, 20, "madera" if k == 0 else "fila"))
        e += [ico(X + 3, yy + 2, icon), t(X + 22, yy + 4, 72, 12, name, "negrita" if k == 0 else "cuerpo",
                                          "oro_claro" if k == 0 else "texto", ajustar=False),
              t(X + 92, yy + 4, 62, 12, qty, color="texto_tenue", alinear="der", ajustar=False)]
        if tot:
            e += pips(X + 160, yy + 7, done, tot)
        e.append(t(X + 200, yy + 4, 72, 12, st, color=stc, ajustar=False))
        e += [btn(X + CW - 60, yy + 3, "↑", 18, 14, "desactivado" if k == 0 else "normal", fuente="cuerpo"),
              btn(X + CW - 40, yy + 3, "↓", 18, 14, "desactivado" if k == 2 else "normal", fuente="cuerpo"),
              btn(X + CW - 20, yy + 3, "x", 18, 14, fuente="cuerpo")]
        yy += 21
        if sub:
            e += [t(X + 12, yy, 12, 12, "→", color="texto_apagado"), t(X + 24, yy, CW - 24, 12, sub[0], color=sub[1])]
            yy += 15
        yy += 2
    yy += 6
    e.append(sep(X, yy, CW))
    yy += 8
    e.append(t(X, yy + 5, 50, 12, "Añadir:", "negrita"))
    recetas = [(IT + "iron_ingot", False, False), (IT + "sword", True, False), (IT + "hammer", False, False),
               (IT + "armor", False, False), (I + "icon_locked.png", False, True)]
    rx = X + 54
    for icon, sel, lock in recetas:
        e += [caja(rx, yy, 22, 22, "madera_oscura"), caja(rx + 1, yy + 1, 20, 20, "madera" if sel else "hueco"),
              ico(rx + 3, yy + 3, icon)]
        if sel:
            e += filete(rx, yy, 22, 22)
        if lock:
            e.append(caja(rx + 1, yy + 1, 20, 20, "velo", 0.4))
        rx += 25
    e += [t(rx + 6, yy + 1, CW - (rx - X) - 6, 12, "Forjar espada", "negrita", "oro_claro", ajustar=False),
          t(rx + 6, yy + 12, CW - (rx - X) - 6, 12, "3 h 54 · yunque", color="texto_tenue", ajustar=False)]
    yy += 28
    bx = X + 54
    for q in ["+1", "+5", "+10", "+siempre"]:
        qw = 44 if len(q) < 4 else 70
        e.append(btn(bx, yy, q, qw, 16))
        bx += qw + 4
    yy += 24
    e.append(t(X, yy, CW, 26, "Los empleados hacen la cola en orden; tú trabajas con clic derecho en un puesto.",
               color="texto_tenue"))
    e += [llamada(LAT_X - 6, PY + 50, 1), llamada(LAT_X - 6, PY + 72, 2), llamada(LAT_X - 6, PY + 108, 3),
          llamada(LAT_X - 6, yy - 52, 4), llamada(X + CW - 156, PY + 22, 5)]
    return {"id": "produccion", "fondo": FONDO_FORJA, "elementos": e}


def ahora():
    e = base("Producción · Forja", 236, 0)
    yy = PY + 46
    e.append(aviso(X, yy, CW, 22, "Cola parada: falta hierro. Cómpralo en Recursos.", "urgente",
                   I + "icon_warning.png"))
    yy += 30
    filas = [
        ("HORNO", "portrait_aldeano.png", IT + "iron_ingot", "Fundir lingote", "0 h 42", 0.6, None, "oficial ×2"),
        ("YUNQUE", "portrait_artesano.png", IT + "sword", "Espada · con cuidado", "2 h 10", 0.25, (0.45, 0.62),
         "toque en 1 h 30"),
        ("YUNQUE 2", None, None, "libre", "", 0, None, ""),
        ("MOSTRADOR", None, None, "libre (abre con Mostrador de venta)", "", 0, None, ""),
    ]
    for zona, who, icon, rec, dur, prog, ventana, nota in filas:
        e.append(caja(X, yy, CW, 34 if who else 20, "fila"))
        e.append(t(X + 4, yy + 4, 80, 12, zona, "negrita", "texto_tenue", ajustar=False))
        if who:
            e += [ret(X + 86, yy + 1, who, 18, FAM_HERRERO if "artesano" in who else None), ico(X + 108, yy + 2, icon),
                  t(X + 126, yy + 4, 130, 12, rec, ajustar=False), t(X + CW - 92, yy + 4, 48, 12, dur,
                                                                     color="texto_tenue", alinear="der"),
                  btn(X + CW - 40, yy + 2, "Parar", 40, 14, fuente="cuerpo")]
            if ventana:
                e += barra_ventana(X + 86, yy + 23, 150, 6, prog, ventana[0], ventana[1])
            else:
                e.append(barra(X + 86, yy + 23, 150, 6, prog, "positivo"))
            e.append(t(X + 240, yy + 20, CW - 240, 12, nota, color="oro" if ventana else "texto_tenue", alinear="der"))
            yy += 36
        else:
            e.append(t(X + 86, yy + 4, CW - 90, 12, rec, color="texto_apagado", ajustar=False))
            yy += 22
    yy += 4
    e.append(sep(X, yy, CW))
    yy += 6
    e += [t(X, yy, 60, 12, "Hoy", "negrita"), ico(X + 40, yy - 2, IT + "iron_ingot"),
          t(X + 58, yy, 40, 12, "3"), ico(X + 80, yy - 2, IT + "sword"), t(X + 98, yy, 140, 12, "1 buena")]
    yy += 16
    e.append(t(X, yy, CW, 12, "Con lo que hay en el almacén: da para 0 espadas.", color="negativo"))
    e += [llamada(LAT_X - 6, PY + 50, 1), llamada(LAT_X - 6, PY + 80, 2), llamada(LAT_X - 6, PY + 118, 3),
          llamada(LAT_X - 6, yy - 16, 4)]
    return {"id": "produccion_ahora", "fondo": FONDO_FORJA, "elementos": e}


MAQUETAS = [cola(), ahora()]
