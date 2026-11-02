"""Maquetas de docs/ui/mecanicas/mercado_y_libro.md.  python3 tools/ui/maqueta.py docs/ui/maquetas/src/mercado_y_libro.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from economia_base import (CW, FONDO_MAPA, I, IT, LAT_X, LAT_Y, X, barra, btn, caja, check, confirmacion, demanda,  # noqa
                           ico, lateral, llamada, motivo, pestanas, sep, t, text_size, tramos)


def oro(x, y, n):
    return [ico(x, y, I + "icon_oro.png"), t(x + 18, y + 2, 50, 12, str(n), "negrita", "oro_claro")]


def cabecera(nombre, sub, gold, h, pest):
    e = [lateral(nombre, h)]
    e += oro(X + CW - 76, LAT_Y + 4, gold)
    e.append(t(X, LAT_Y + 24, CW, 12, sub, color="texto_tenue"))
    e.append(pestanas(X, LAT_Y + 40, pest[0], pest[1]))
    return e


def vender():
    e = cabecera("Armería", "Abierta hasta las 21:00", 30, 236, (["Comprar", "Vender"], 1))
    yy = LAT_Y + 60
    e += [caja(X, yy, CW, 64, "fila"), ico(X + 3, yy + 3, IT + "sword"),
          t(X + 22, yy + 4, 120, 12, "Espada buena ×3", "negrita"), t(X + 150, yy + 4, 60, 12, "59 /u", "negrita",
                                                                       "oro_claro")]
    e += demanda(X + 214, yy + 3, 3, "normal", "1,00")
    e += [btn(X + 22, yy + 22, "Vender 1 · 59", 100, 16),
          btn(X + 128, yy + 22, "Vender 3 · 59+57+54 = 170", 200, 16, "encima")]
    e += [t(X + 22, yy + 44, 140, 12, "Tras vender 3:", color="texto_tenue")]
    e += demanda(X + 120, yy + 43, 2, "baja", "0,88")
    e.append(t(X + 230, yy + 44, CW - 232, 12, "al alba, 1,0", color="texto_tenue", alinear="der"))
    yy += 68
    e += [caja(X, yy, CW, 44, "fila"), ico(X + 3, yy + 3, IT + "hammer"),
          t(X + 22, yy + 4, 120, 12, "Martillo ×1", "negrita"), t(X + 150, yy + 4, 60, 12, "17 /u", "negrita",
                                                                   "oro_claro")]
    e += demanda(X + 214, yy + 3, 1, "muy baja", "0,68")
    e += [btn(X + 22, yy + 22, "Vender 1 · 17", 100, 16),
          t(X + 130, yy + 24, CW - 132, 12, "Mañana valdrá ~ 25", color="aviso")]
    yy += 52
    e.append(sep(X, yy, CW))
    e.append(t(X, yy + 6, CW, 12, "Cada unidad que vende alguien baja la demanda.", color="texto_tenue"))
    e += [llamada(LAT_X - 6, LAT_Y + 22, 1), llamada(LAT_X - 6, LAT_Y + 62, 2), llamada(LAT_X - 6, LAT_Y + 82, 3),
          llamada(LAT_X - 6, LAT_Y + 104, 4), llamada(LAT_X - 6, LAT_Y + 150, 5)]
    return {"id": "mercado_y_libro", "fondo": FONDO_MAPA, "elementos": e}


def comprar():
    e = cabecera("Recursos", "Abierto hasta las 21:00", 139, 300, (["Comprar", "Vender"], 0))
    yy = LAT_Y + 60
    filas = [(IT + "iron", "Hierro", 7, 4, "alta", "1,40", 6, 42, 8, "Lleva 14/60 kg: caben 23 (peso)", "texto_tenue"),
             (IT + "coal", "Carbón", 4, 3, "normal", "1,00", 2, 8, 2, None, None),
             (IT + "wood", "Madera", 6, 3, "normal", "1,00", 1, 6, 1, None, None),
             (IT + "stone", "Piedra", 4, 3, "normal", "1,00", 1, 4, 1, None, None)]
    for icon, name, pu, niv, pal, num, q, tot, sc, lim, limc in filas:
        h = 50 if lim else 38
        e += [caja(X, yy, CW, h, "fila"), ico(X + 3, yy + 2, icon), t(X + 22, yy + 3, 70, 12, name, "negrita"),
              t(X + 84, yy + 3, 50, 12, "%d /u" % pu, "negrita", "oro_claro")]
        e += demanda(X + 132, yy + 2, niv, pal)
        e += [btn(X + 232, yy + 1, "-", 16, 14, fuente="cuerpo"), t(X + 250, yy + 3, 20, 12, str(q), alinear="centro"),
              btn(X + 272, yy + 1, "+", 16, 14, fuente="cuerpo"),
              t(X + 290, yy + 3, CW - 292, 12, "= %d" % tot, alinear="der")]
        e += [btn(X + 22, yy + 19, "Comprar", 76, 15),
              btn(X + 104, yy + 19, "Enviar → Forja  +%d · 2 h" % sc, 180, 15, icono=I + "icon_in_progress.png")]
        if lim:
            e.append(t(X + 22, yy + 36, CW - 24, 12, lim, color=limc))
        yy += h + 3
    e.append(t(X, yy + 2, CW, 12, "El recado llega solo al almacén: +20 % y 2 h.", color="texto_tenue"))
    e.append(motivo(X, yy + 16, CW, "Enviar madera: el almacén de la Forja está lleno (10/10)"))
    e += [llamada(LAT_X - 6, LAT_Y + 22, 1), llamada(LAT_X - 6, LAT_Y + 60, 2), llamada(LAT_X - 6, LAT_Y + 78, 3),
          llamada(LAT_X - 6, LAT_Y + 96, 4)]
    return {"id": "mercado_y_libro_recado", "fondo": FONDO_MAPA, "elementos": e}


def deuda():
    e = [lateral("Libro de cuentas · Herrero", 300)]
    e += oro(X + CW - 76, LAT_Y + 4, 75)
    e.append(pestanas(X, LAT_Y + 26, ["Hoy", "Por día", "Por edificio", "Deudas", "Avisos 3"], 3))
    yy = LAT_Y + 46
    e += [caja(X, yy, CW, 150, "fila"), t(X + 6, yy + 4, 200, 12, "DEUDA · El prestamista", "negrita", "oro"),
          t(X + 6, yy + 20, 160, 12, "Debes 190 de 200", "negrita"),
          barra(X + 150, yy + 23, 130, 6, 0.05, "positivo"), t(X + 284, yy + 20, 50, 12, "5 %", color="texto_tenue",
                                                                  alinear="der"),
          t(X + 6, yy + 35, CW - 12, 12, "Vence: día 8 a las 23:59 · quedan 7 días"),
          t(X + 6, yy + 52, CW - 12, 12, "A tu ritmo (+42/día, últimos 3 días) llegas", color="texto_tenue"),
          t(X + 6, yy + 65, 200, 12, "al día 8 con ~ 370 →", color="texto_tenue"),
          check(X + 140, yy + 65, True), t(X + 156, yy + 65, 80, 12, "te da", "negrita", "positivo"),
          t(X + 6, yy + 82, CW - 12, 26, "Si vence: reputación -10 y prórroga de 1 estación con +25 % (238). "
                                         "Si vence la prórroga: embargo.", color="aviso")]
    e += [t(X + 6, yy + 114, 40, 12, "Pagar"), btn(X + 46, yy + 112, "-", 16, 14, fuente="cuerpo"),
          {"tipo": "campo", "rect": [X + 64, yy + 111, 40, 16], "texto": "50"},
          btn(X + 106, yy + 112, "+", 16, 14, fuente="cuerpo"),
          btn(X + 128, yy + 111, "Pagar 50", 70, 16), btn(X + 204, yy + 111, "Pagar todo · 190", 126, 16,
                                                          "desactivado"),
          motivo(X + 128, yy + 131, CW - 134, "Te faltan 115")]
    yy += 158
    e += [t(X, yy, 220, 12, "Encargos aceptados (1/2)", "negrita", "oro"), caja(X, yy + 16, CW, 22, "fila"),
          ico(X + 3, yy + 19, IT + "hammer"), t(X + 22, yy + 20, 150, 12, "2 martillos · carpintero"),
          t(X + 180, yy + 20, 20, 12, "42", "negrita", "oro_claro"),
          barra(X + 204, yy + 24, 60, 6, 0.6, "aviso"), t(X + 268, yy + 20, CW - 270, 12, "1 d 4 h",
                                                           color="texto_tenue", alinear="der")]
    e += [llamada(LAT_X - 6, LAT_Y + 50, 1), llamada(LAT_X - 6, LAT_Y + 98, 2), llamada(LAT_X - 6, LAT_Y + 128, 3),
          llamada(LAT_X - 6, LAT_Y + 158, 4), llamada(LAT_X - 6, LAT_Y + 206, 5)]
    # ficha de deuda del HUD (del kit) en ámbar, solo para señalar el umbral
    e += [caja(828, 14, 4, 4, "aviso")]
    return {"id": "mercado_y_libro_deuda", "fondo": FONDO_MAPA, "elementos": e}


def confirmar_pago():
    e = deuda()["elementos"]
    e += confirmacion("Pagar 65 de la deuda", [
        ("Te quedarán", "10", "negativo"),
        ("Mañana al alba", "se cobran 40 (20 + 20 salarios)", None),
        ("Si no llegas", "gracia de 1 día; después -5 lealtad", "aviso"),
    ], "Pagar 65", y=200, w=380)
    return {"id": "mercado_y_libro_confirmar", "fondo": FONDO_MAPA, "elementos": e}


MAQUETAS = [vender(), comprar(), deuda(), confirmar_pago()]
