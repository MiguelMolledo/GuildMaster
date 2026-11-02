"""Maquetas de docs/ui/mecanicas/forja_interior.md.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/forja_interior.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from economia_base import (CW, text_size, hud_interior, FAM_HERRERO, FONDO_FORJA, I, IT, LAT_X, X, barra, barra_ventana, btn, caja, filete,  # noqa
                           ico, insignia, lateral, llamada, motivo, panel, pestanas, ret, selector, sep, t, tooltip,
                           tramos)


def menu_puesto():
    x, y, w = 520, 124, 300
    e = [panel(x, y, w, 226, "Yunque", False)]
    e.append(t(x + 90, y + 7, w - 98, 12, "Hugo · Artesanía 7", color="texto_tenue", alinear="der"))
    e += selector(x + 8, y + 28, ["Rápido", "Normal", "Con cuidado"], 1)
    e.append(t(x + 8, y + 46, w - 16, 12, "×1,0 tiempo · calidad con Artesanía 7", color="texto_tenue"))
    e.append(sep(x + 8, y + 62, w - 16))
    rows = [
        (IT + "sword", "Forjar espada", [(IT + "iron_ingot", "2/2", True), (IT + "coal", "1/1", True)], "3 h 54", None),
        (IT + "hammer", "Forjar martillo", [(IT + "iron_ingot", "2/1", True), (IT + "coal", "1/1", True)], "2 h 36",
         None),
        (IT + "armor", "Forjar armadura", [(IT + "iron_ingot", "2/3", False), (IT + "coal", "1/1", True)], "6 h 30",
         "Falta 1 lingote de hierro"),
    ]
    yy = y + 66
    for k, (icon, name, inputs, dur, why) in enumerate(rows):
        e.append(caja(x + 6, yy, w - 12, 18, "madera" if k == 0 else "fila"))
        if k == 0:
            e += filete(x + 6, yy, w - 12, 18)
        e += [ico(x + 8, yy + 1, icon), t(x + 26, yy + 3, 112, 12, name, ajustar=False, color="texto_apagado" if why else
                                         ("oro_claro" if k == 0 else "texto"))]
        ix = x + 140
        for ic, n, ok in inputs:
            e += [ico(ix, yy + 1, ic), t(ix + 16, yy + 3, 22, 12, n, color="texto_tenue" if ok else "negativo")]
            ix += 44
        e.append(t(x + w - 50, yy + 3, 42, 12, dur, color="texto_tenue", alinear="der"))
        yy += 19
        if why:
            e.append(motivo(x + 26, yy, w - 34, why))
            yy += 13
    e += [caja(x + 6, yy, w - 12, 18, "fila"), ico(x + 8, yy + 1, I + "icon_locked.png"),
          t(x + 26, yy + 3, 90, 12, "Forjar acero", color="texto_apagado", ajustar=False),
          t(x + 104, yy + 3, w - 112, 12, "Necesita Forja de maestro", color="negativo", alinear="der")]
    yy += 23
    e.append(sep(x + 8, yy, w - 16))
    yy += 5
    e.append(t(x + 8, yy, 120, 12, "Calidad (espada)", color="texto_tenue"))
    e.append(t(x + 120, yy, w - 128, 12, "20 · 50 · 30 %", color="texto", alinear="der"))
    yy += 14
    e += tramos(x + 8, yy, w - 16, 7, [(0.2, "texto_apagado"), (0.5, "#c4c4b4"), (0.3, "oro_claro")])
    yy += 10
    e.append(t(x + 8, yy, w - 16, 12, "+ martillo: +10 % de subir un escalón", color="positivo"))
    yy += 16
    e += [btn(x + 8, yy, "Parar", 56), t(x + 70, yy + 2, w - 78, 12, "Trabajando: espada 40 %", color="texto_tenue",
                                         alinear="der")]
    return e


def interior():
    e = hud_interior(cola=2, pausa=True, estado="Hugo en el yunque · cola parada",
                     insignias={0: ("!", "negativo"), 2: ("1", "oro")})
    # barra del puesto (sobre el yunque) con el tramo del toque encendido, y su icono de estado
    e += barra_ventana(440, 238, 50, 6, 0.55, 0.45, 0.62, encendida=True)
    e += [ico(494, 233, I + "icon_martillo.png"), caja(492, 231, 20, 20, "oro", 0.0)]
    e += filete(492, 231, 20, 20)
    # icono de estado del horno (libre) y del almacén
    e += [ico(360, 196, I + "icon_idle.png")]
    # pausa activa: órdenes encoladas sobre sus destinos
    e += insignia(392, 214, "1", "oro") + insignia(402, 352, "2", "oro")
    e += menu_puesto()
    e += [llamada(240, 490, 1), llamada(326, 504, 2), llamada(434, 232, 3), llamada(514, 124, 4), llamada(386, 210, 5), llamada(240, 112, 6)]
    return {"id": "forja_interior", "fondo": FONDO_FORJA, "elementos": e}


def rutina():
    e = hud_interior(estado="Hugo en el yunque")
    e.append(lateral("Hugo", 262))
    yy = 58 + 26
    e += [ret(X, yy, "portrait_artesano.png", 48, FAM_HERRERO, "activo"),
          t(X + 56, yy, 200, 12, "20 años · Herrero · Plebeyo", color="texto_tenue"),
          ico(X + 56, yy + 15, I + "icon_oro.png"), t(X + 74, yy + 17, 120, 12, "65 de la familia", "negrita",
                                                       "oro_claro"),
          t(X + CW - 70, yy + 17, 70, 12, "Ficha → F", color="info", alinear="der")]
    yy += 54
    e.append(pestanas(X, yy, ["Inventario", "Rutina"], 1))
    yy += 20
    e += [t(X, yy, 250, 12, "Ahora (Día): trabajar en la Forja", "negrita", ajustar=False),
          btn(X + CW - 70, yy - 2, "Activada", 70, 14, "pulsado", fuente="cuerpo")]
    yy += 16
    nx = X + int(CW * 0.24)
    e.append(t(nx - 14, yy, 30, 9, "11:17", "pequena", "oro_claro", "centro"))
    yy += 10
    # tira del día (primavera 10/50/10/30)
    parts = [("Amanecer", 0.10, "icon_pending.png", None), ("Día", 0.50, "icon_martillo.png", "Trabajar"),
             ("Atardecer", 0.10, "icon_pending.png", None), ("Noche", 0.30, "bubble_rest.png", "Descansar")]
    cx = X
    for k, (name, f, acti, label) in enumerate(parts):
        pw = int(CW * f) if k < 3 else X + CW - cx
        sel = name == "Día"
        e.append(caja(cx, yy, pw - 1, 24, "madera" if sel else "fila"))
        if sel:
            e += filete(cx, yy, pw - 1, 24)
        if label:
            e += [ico(cx + 4, yy + 4, I + acti), t(cx + 24, yy + 6, pw - 28, 12, label, "negrita",
                                                   "oro_claro" if sel else "texto", ajustar=False)]
        else:
            e.append(ico(cx + (pw - 17) // 2, yy + 4, I + acti))
        e.append(t(cx - 6, yy + 27, pw + 12, 9, name, "pequena", "texto_tenue", "centro"))
        cx += pw
    e.append(caja(nx, yy - 2, 1, 28, "oro_claro"))
    yy += 42
    e.append(sep(X, yy, CW))
    yy += 6
    e += [t(X, yy + 1, 40, 12, "Día", "negrita")] + selector(X + 40, yy, ["Trabajar", "Descansar", "Libre"], 0)
    yy += 20
    e += [t(X, yy + 2, 56, 12, "Receta", color="texto_tenue"),
          btn(X + 52, yy, "Automática  v", 110, 14, fuente="cuerpo"),
          t(X + 176, yy + 2, 40, 12, "Modo", color="texto_tenue")] + selector(X + 212, yy, ["R", "N", "C"], 1, 22)
    yy += 20
    e.append(t(X, yy, CW, 12, "Trabaja en: Forja (se cambia en el árbol, F)", color="texto_tenue"))
    yy += 18
    e.append({"tipo": "aviso", "rect": [X, yy, CW, 22], "gravedad": "aviso", "icono": I + "icon_warning.png",
              "texto": "Manda una orden manual: 2 en cola."})
    e += [llamada(LAT_X - 6, 164, 1), llamada(LAT_X - 6, 226, 2), llamada(LAT_X - 6, 304, 3)]
    return {"id": "forja_interior_rutina", "fondo": FONDO_FORJA, "elementos": e}


MAQUETAS = [interior(), rutina()]
