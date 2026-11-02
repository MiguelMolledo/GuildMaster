"""Maquetas de docs/ui/mecanicas/empleados.md.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/empleados.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from economia_base import (CW, text_size, FONDO_FORJA, I, IT, LAT_X, X, barra, btn, caja, filete, ico, insignia, lateral,  # noqa
                           llamada, motivo, pestanas, ret, selector, sep, t)
from forja_interior import barra_herramientas, placa  # noqa: E402

PY = 116
RANGO = {"A": ("Aprendiz", "texto_tenue"), "O": ("Oficial", "info"), "M": ("Maestro", "oro")}


def cabecera(activa, huecos, extra):
    e = [caja(380, 34, 200, 52, "#000000"), caja(508, 88, 452, 24, "#000000")] + placa() + barra_herramientas()
    e.append(lateral("Empleados · Forja", 396 if activa else 300, PY))
    e.append(pestanas(X, PY + 26, ["Plantilla", "Contratar"], activa))
    e.append(t(X + 150, PY + 27, CW - 150, 12, huecos + extra, color="texto_tenue", alinear="der"))
    return e


def rango(x, y, r):
    """Insignia de rango (pieza de kit pendiente). Devuelve elementos; ancho ~ 12 + texto."""
    nombre, col = RANGO[r]
    return [caja(x, y, 9, 9, "hueco"), caja(x + 1, y + 1, 7, 7, col),
            t(x, y, 9, 9, r, "pequena", "texto_tinta", "centro", "centro", False),
            t(x + 12, y - 1, 60, 12, nombre.upper(), "pequena", col, ajustar=False)]


def pasos(x, y, v, n=10, w=5):
    out = []
    for i in range(n):
        out.append(caja(x + i * (w + 1), y, w, 6, "positivo" if i < v else "madera_oscura"))
    return out


def contratar():
    e = cabecera(1, "Huecos 0/1 · ", "65 de oro")
    yy = PY + 46
    e += [caja(X, yy, CW, 50, "seccion"), t(X + 4, yy + 2, 100, 12, "RANGOS", "negrita", "oro")]
    tabla = [("A", "7 /día", "×1", "50 %", "muchos", None), ("O", "20 /día", "×2", "100 %", "algunos", None),
             ("M", "40 /día", "×3", "150 %", "", "Taller de maestro")]
    ry = yy + 4
    for r, sal, vel, efi, disp, lock in tabla:
        e += rango(X + 64, ry + 2, r)
        e += [t(X + 140, ry, 56, 12, sal, "negrita", "oro_claro", "der"), t(X + 204, ry, 30, 12, vel, color="texto"),
              t(X + 230, ry, 40, 12, efi, color="texto", alinear="der")]
        if lock:
            e += [ico(X + 276, ry - 1, I + "icon_locked.png", 12), t(X + 290, ry, CW - 292, 12, "Taller", color="negativo")]
        else:
            e.append(t(X + 276, ry, CW - 278, 12, disp, color="texto_tenue"))
        ry += 15
    yy += 56
    cands = [("portrait_aldeana.png", "Margarida", "O", 20, 4, 5, 5, ["iron_ingot", "hammer", "sword"], ["armor"]),
             ("portrait_aldeano.png", "Guillem", "O", 20, 6, 4, 6, ["iron_ingot", "hammer", "sword", "armor"], []),
             ("portrait_mercader.png", "Agnès", "A", 7, 2, 3, 4, ["iron_ingot", "hammer"], ["sword", "armor"])]
    for k, (por, name, r, wage, art, car, con, puede, no) in enumerate(cands):
        nw = text_size(name, "negrita")[0]
        e += [caja(X, yy, CW, 58, "fila"), ret(X + 2, yy + 2, por, 32),
              t(X + 40, yy + 3, nw + 2, 12, name, "negrita", ajustar=False)]
        e += rango(X + 46 + nw, yy + 5, r)
        bw = 130 if k == 1 else 84
        e += [t(X + CW - bw - 60, yy + 3, 54, 12, "%d /día" % wage, "negrita", "oro_claro", "der"),
              btn(X + CW - bw - 2, yy + 2, "¿Contratar? %d/día" % wage if k == 1 else "Contratar", bw, 16,
                  "encima" if k == 1 else "normal", fuente="cuerpo")]
        e += [t(X + 40, yy + 19, 60, 12, "Artesanía", color="texto_tenue")] + pasos(X + 100, yy + 22, art)
        e += [t(X + 162, yy + 19, 12, 12, str(art), "negrita"),
              t(X + 180, yy + 19, CW - 182, 12, "Carisma %d · Const. %d" % (car, con), color="texto_tenue")]
        e.append(t(X + 40, yy + 37, 40, 12, "Puede:", color="texto_tenue"))
        px = X + 84
        for it in puede:
            e.append(ico(px, yy + 35, IT + it))
            px += 18
        for it in no:
            e += [ico(px, yy + 35, IT + it), caja(px, yy + 35, 16, 16, "velo", 0.55), ico(px + 6, yy + 41, I +
                                                                                     "icon_locked.png", 10)]
            px += 18
        yy += 61
    e.append(t(X, yy + 2, CW, 12, "Empiezan mañana al alba; cobran cada alba.", color="texto_tenue"))
    e.append(t(X, yy + 18, CW, 12, "↓ 3 candidatos más", color="texto_apagado", alinear="centro"))
    e += [llamada(LAT_X - 6, PY + 48, 1), llamada(LAT_X - 6, PY + 106, 2), llamada(X + 80, PY + 140, 3),
          llamada(X + CW - 98, PY + 166, 4)]
    return {"id": "empleados", "fondo": FONDO_FORJA, "elementos": e}


def plantilla():
    e = cabecera(0, "Huecos 2/2 · 27/día · ", "65 de oro")
    yy = PY + 46
    # ascenso pendiente, arriba y con filete dorado
    e += [caja(X, yy, CW, 50, "madera")] + filete(X, yy, CW, 50)
    e += [ret(X + 3, yy + 3, "portrait_aldeano.png", 32), t(X + 40, yy + 3, 40, 12, "Joan", "negrita", "oro_claro")]
    e += rango(X + 80, yy + 5, "A") + [t(X + 160, yy + 3, 14, 12, "→", "negrita", "oro_claro")] + rango(X + 176, yy + 5, "O")
    e += [t(X + 40, yy + 17, CW - 44, 12, "Salario 7 → 20 · velocidad ×1 → ×2", color="texto"),
          btn(X + 40, yy + 31, "Aceptar · +15 lealtad", 140, 15, "encima", fuente="cuerpo"),
          btn(X + 186, yy + 31, "Rechazar · -10 lealtad", 146, 15, fuente="cuerpo")]
    yy += 56
    e += [caja(X, yy, CW, 112, "fila"), ret(X + 3, yy + 3, "portrait_aldeana.png", 32),
          t(X + 40, yy + 3, 80, 12, "Margarida", "negrita")]
    e += rango(X + 118, yy + 5, "O")
    e += [t(X + 176, yy + 3, 60, 12, "20 /día", "negrita", "oro_claro"),
          ico(X + 40, yy + 17, IT + "sword"), t(X + 58, yy + 18, CW - 60, 12, "Yunque · Forjar espada 40 %")]
    # lealtad con marcas de tramo 20 / 40 / 70
    bx, bw = X + 112, 130
    e += [t(X + 40, yy + 34, 72, 12, "Lealtad 62", color="texto_tenue", ajustar=False),
          barra(bx, yy + 37, bw, 7, 0.62, "aviso")]
    for m in (0.2, 0.4, 0.7):
        e.append(caja(bx + int(bw * m), yy + 35, 1, 11, "texto"))
    e += [t(bx + bw + 6, yy + 34, CW - (bx + bw + 6 - X), 12, "descontenta", "negrita", "aviso"),
          t(X + 40, yy + 48, CW - 44, 12, "-20 % de eficiencia y rumores (-1 reputación)", color="aviso"),
          t(X + 40, yy + 62, CW - 44, 12, "Ascenso a maestro: 3/16 días · lealtad > 70", color="texto_tenue"),
          t(X + 40, yy + 78, 50, 12, "Puesto", color="texto_tenue")]
    e += selector(X + 84, yy + 76, ["Horno", "Yunque", "Mostr.", "Cualquiera"], 1)
    e += [btn(X + 40, yy + 94, "Gratificar 5 · +5 lealtad", 170, 15, fuente="cuerpo"),
          btn(X + CW - 76, yy + 94, "Despedir", 72, 15, fuente="cuerpo")]
    yy += 118
    e += [caja(X, yy, CW, 34, "fila"), ret(X + 3, yy + 1, "portrait_aldeano.png", 32, marco="apagado"),
          t(X + 40, yy + 3, 80, 12, "Guillem", "negrita", "texto_apagado")]
    e += rango(X + 100, yy + 5, "O")
    e += [t(X + 40, yy + 18, CW - 44, 12, "Llega mañana (día 3) al alba", color="texto_tenue")]
    yy += 40
    e += [sep(X, yy, CW), t(X, yy + 6, CW, 12, "Salarios de mañana: 47 · tienes 65", color="texto_tenue")]
    e += [llamada(LAT_X - 6, PY + 48, 1), llamada(LAT_X - 6, PY + 120, 2), llamada(LAT_X - 6, PY + 138, 3),
          llamada(LAT_X - 6, PY + 180, 4), llamada(LAT_X - 6, PY + 208, 5)]
    return {"id": "empleados_plantilla", "fondo": FONDO_FORJA, "elementos": e}


MAQUETAS = [contratar(), plantilla()]
