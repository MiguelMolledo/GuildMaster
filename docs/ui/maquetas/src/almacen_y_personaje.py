"""Maquetas de docs/ui/mecanicas/almacen_y_personaje.md.
python3 tools/ui/maqueta.py docs/ui/maquetas/src/almacen_y_personaje.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from economia_base import (CW, FAM_HERRERO, FONDO_FORJA, I, IT, LAT_X, X, barra, btn, caja, casilla, ico, lateral,  # noqa
                           llamada, pestanas, ret, sep, t, tooltip)
from forja_interior import barra_herramientas, placa  # noqa: E402

PY = 116


def cabecera():
    return [caja(380, 34, 200, 52, "#000000"), caja(508, 88, 452, 24, "#000000")] + placa() + barra_herramientas(False)


def fila_casillas(x, y, cosas, n=10, estado="normal"):
    out = []
    for i in range(n):
        c = cosas[i] if i < len(cosas) else None
        if c:
            out += casilla(x + i * 33, y, 30, c[0], c[1], c[2] if len(c) > 2 else 0, c[3] if len(c) > 3 else estado)
        else:
            out += casilla(x + i * 33, y, 30, estado=estado)
    return out


def almacen():
    e = cabecera() + [lateral("Almacén · Forja", 292, PY)]
    yy = PY + 26
    e += [t(X, yy, 120, 12, "3/10 pilas", "negrita"),
          t(X + 120, yy, CW - 120, 12, "En camino: 6 hierro · 11:40", color="texto_tenue", alinear="der")]
    yy += 16
    e += fila_casillas(X + 2, yy, [(IT + "iron", 8), (IT + "coal", 4), (IT + "sword", 1, 1),
                                   (IT + "iron", 6, 0, "reservada")])
    yy += 34
    e += fila_casillas(X + 2, yy, [], estado="bloqueada")
    yy += 33
    e.append(t(X, yy, CW, 12, "+10 pilas con Almacén ampliado → Mejoras", color="info"))
    yy += 18
    e += [btn(X, yy, "Dejar materias", 120, 16), btn(X + CW - 130, yy, "Llevar productos", 130, 16, "encima")]
    yy += 24
    e.append(sep(X, yy, CW))
    yy += 6
    e += [ret(X, yy, "portrait_artesano.png", 24, FAM_HERRERO, "activo"),
          t(X + 30, yy + 1, 220, 12, "Hugo lleva 14 / 60 kg", "negrita", ajustar=False),
          barra(X + 30, yy + 15, 200, 6, 14 / 60.0, "positivo", 0.9)]
    yy += 30
    e += fila_casillas(X + 2, yy, [(IT + "hammer", 1), (IT + "iron_ingot", 2)])
    yy += 36
    e.append(t(X, yy, CW, 12, "Clic: mover la pila · Clic derecho: mover 1", color="texto_tenue"))
    yy += 14
    e.append(t(X, yy, CW, 12, "No caben 8 hierro: solo 3 (te quedan 6 kg)", color="negativo"))
    e.append(tooltip(LAT_X - 176, PY + 40, 172, "Espada buena ×1",
                     ["8 kg · producto", "Se vende hoy por 59", "en la Armería (demanda 1,0)."]))
    e += [llamada(LAT_X - 6, PY + 22, 1), llamada(LAT_X - 6, PY + 76, 2), llamada(LAT_X - 6, PY + 132, 3),
          llamada(LAT_X - 6, PY + 166, 4), llamada(LAT_X - 6, PY + 286, 5)]
    return {"id": "almacen_y_personaje", "fondo": FONDO_FORJA, "elementos": e}


def ficha():
    e = cabecera() + [lateral("Hugo", 318, PY)]
    yy = PY + 26
    e += [ret(X, yy, "portrait_artesano.png", 48, FAM_HERRERO, "activo"),
          t(X + 56, yy, 220, 12, "20 años · Herrero · Plebeyo", color="texto_tenue"),
          ico(X + 56, yy + 15, I + "icon_oro.png"),
          t(X + 74, yy + 17, 120, 12, "65 de la familia", "negrita", "oro_claro"),
          t(X + CW - 70, yy + 17, 70, 12, "Ficha → F", color="info", alinear="der")]
    yy += 54
    e.append(pestanas(X, yy, ["Inventario", "Rutina"], 0))
    yy += 20
    e.append(t(X, yy, 100, 12, "Equipo", "negrita", "oro"))
    yy += 15
    slots = [(IT + "hammer", "Martillo", "+10 % de subir un escalón en la Forja", "positivo"),
             (I + "slot_empty_ropa.png", "Ropa: —", "Clic en una ropa de la bolsa para ponerla", "texto_apagado"),
             (I + "slot_empty_accesorio.png", "Accesorio: —", "", "texto_apagado")]
    for icon, name, eff, col in slots:
        e += casilla(X, yy, 26, None) + [ico(X + 5, yy + 5, icon)]
        e += [t(X + 32, yy + 1, 120, 12, name, "negrita" if "Martillo" in name else "cuerpo"),
              t(X + 32, yy + 13, CW - 32, 12, eff, color=col)]
        yy += 29
    yy += 2
    e.append(sep(X, yy, CW))
    yy += 6
    e += [t(X, yy, 140, 12, "Lleva 14 / 60 kg", "negrita"), barra(X + 120, yy + 3, 216, 6, 14 / 60.0, "positivo", 0.9)]
    yy += 16
    e += fila_casillas(X + 2, yy, [(IT + "sword", 1, 1), (IT + "iron_ingot", 2)])
    yy += 36
    e += [t(X, yy, CW, 12, "Valor hoy: ~ 105 (Armería 59 · Materiales 46)", color="texto_tenue")]
    e += [llamada(LAT_X - 6, PY + 22, 1), llamada(LAT_X - 6, PY + 98, 2), llamada(LAT_X - 6, PY + 200, 3),
          llamada(LAT_X - 6, PY + 252, 4)]
    return {"id": "almacen_y_personaje_ficha", "fondo": FONDO_FORJA, "elementos": e}


MAQUETAS = [almacen(), ficha()]
