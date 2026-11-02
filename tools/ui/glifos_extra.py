#!/usr/bin/env python3
"""Añade a Pixel Operator (CC0, se puede modificar) los glifos que usan los textos del juego y no trae: → ← ↑ ↓ − †.
Se dibujan píxel a píxel en su rejilla (100 unidades = 1 px). Idempotente: si el glifo ya está, no lo toca.

  python3 -m pip install fonttools      (solo para esta herramienta)
  python3 tools/ui/glifos_extra.py      → reescribe assets/art/ui/fonts/pixel_operator{,_bold,_8}.ttf

Para comprobar qué falta: python3 tools/ui/glifos_extra.py --falta "texto con los caracteres"
"""
import argparse
import os
import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(ROOT, "assets", "art", "ui", "fonts")
U = 100   # unidades por píxel

# Mapas de bits: filas de arriba abajo; "base" = fila (en píxeles sobre la línea base) de la fila de abajo.
REGULAR = {
    0x2192: (["...#..", "....#.", "######", "....#.", "...#.."], 2),   # →
    0x2190: (["..#...", ".#....", "######", ".#....", "..#..."], 2),   # ←
    0x2191: (["..#..", ".###.", "#.#.#", "..#..", "..#..", "..#..", "..#.."], 1),   # ↑
    0x2193: (["..#..", "..#..", "..#..", "..#..", "#.#.#", ".###.", "..#.."], 1),   # ↓
    0x2212: (["#####"], 4),   # − (signo menos, ancho de cifra)
    0x2020: (["..#..", "#####", "..#..", "..#..", "..#..", "..#..", "..#.."], 0),   # † (fallecido)
}
BOLD = {
    0x2192: (["..##..", "...##.", "######", "...##.", "..##.."], 2),
    0x2190: (["..##..", ".##...", "######", ".##...", "..##.."], 2),
    0x2191: (["..##..", ".####.", "##..##", "..##..", "..##..", "..##..", "..##.."], 1),
    0x2193: (["..##..", "..##..", "..##..", "..##..", "##..##", ".####.", "..##.."], 1),
    0x2212: (["#####"], 4),
    0x2020: (["..##..", "######", "..##..", "..##..", "..##..", "..##..", "..##.."], 0),
}
SMALL = {   # pixel_operator_8: mayúscula de 7 px, guion en la fila 3
    0x2192: (["..#..", "...#.", "#####", "...#.", "..#.."], 1),
    0x2190: (["..#..", ".#...", "#####", ".#...", "..#.."], 1),
    0x2191: (["..#..", ".###.", "..#..", "..#..", "..#.."], 1),
    0x2193: (["..#..", "..#..", "..#..", ".###.", "..#.."], 1),
    0x2212: (["####"], 3),
    0x2020: (["..#..", "#####", "..#..", "..#..", "..#.."], 0),
}


def outline(cells):
    """Contornos de la unión de celdas (x, y) en sentido horario con y hacia arriba (TrueType): un contorno por
    región, sin cuadrados solapados (el rasterizador de FreeType deforma glifos hechos de cuadrados sueltos)."""
    edges = {}
    for x, y in cells:   # cada celda en sentido horario: arriba por la izquierda, derecha por arriba...
        for a, b in (((x, y), (x, y + 1)), ((x, y + 1), (x + 1, y + 1)), ((x + 1, y + 1), (x + 1, y)), ((x + 1, y), (x, y))):
            if (b, a) in edges:
                del edges[(b, a)]   # borde compartido con la celda vecina: se va
            else:
                edges[(a, b)] = True
    out = {}
    for a, b in edges:
        out.setdefault(a, []).append(b)
    loops = []
    while out:
        start = next(iter(out))
        loop, cur, prev = [start], start, None
        while True:
            nexts = out[cur]
            if len(nexts) > 1 and prev is not None:   # vértice en diagonal: gira a la derecha para separar regiones
                dx, dy = cur[0] - prev[0], cur[1] - prev[1]
                right = (cur[0] + dy, cur[1] - dx)
                nxt = right if right in nexts else nexts[0]
            else:
                nxt = nexts[0]
            nexts.remove(nxt)
            if not nexts:
                del out[cur]
            prev, cur = cur, nxt
            if cur == start:
                break
            loop.append(cur)
        clean = [p for i, p in enumerate(loop)   # sin puntos en medio de un tramo recto
                 if (loop[i - 1][0] - p[0]) * (loop[(i + 1) % len(loop)][1] - p[1])
                 != (loop[i - 1][1] - p[1]) * (loop[(i + 1) % len(loop)][0] - p[0])]
        loops.append(clean)
    return loops


def glyph(rows, base, left=1):
    h = len(rows)
    cells = [(left + c, base + h - 1 - r) for r, line in enumerate(rows) for c, ch in enumerate(line) if ch == "#"]
    pen = TTGlyphPen(None)
    for loop in outline(cells):
        pen.moveTo((loop[0][0] * U, loop[0][1] * U))
        for x, y in loop[1:]:
            pen.lineTo((x * U, y * U))
        pen.closePath()
    width = (left + max(len(line) for line in rows) + 1) * U
    return pen.glyph(), width


def patch(name, table, a_force=False):
    path = os.path.join(FONTS, name)
    font = TTFont(path)
    cmap = font.getBestCmap()
    added = []
    for cp, (rows, base) in table.items():
        if cp in cmap and not (a_force and cmap[cp] == f"uni{cp:04X}"):
            continue
        gname = f"uni{cp:04X}"
        g, width = glyph(rows, base)
        font["glyf"][gname] = g
        font["hmtx"][gname] = (width, 1 * U)
        for sub in font["cmap"].tables:
            if sub.isUnicode():
                sub.cmap[cp] = gname
        added.append(chr(cp))
    if added:
        font.setGlyphOrder(font["glyf"].glyphOrder)   # glyf ya añadió los nombres nuevos a su orden
        font.save(path)
    print(f"  {name}: {'añadidos ' + ' '.join(added) if added else 'ya los tenía'}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--falta", default="")
    ap.add_argument("--rehacer", action="store_true", help="vuelve a dibujar los glifos que añadió esta herramienta")
    a = ap.parse_args()
    if a.falta:
        for n in sorted(os.listdir(FONTS)):
            if n.endswith(".ttf"):
                cm = TTFont(os.path.join(FONTS, n)).getBestCmap()
                print(f"  {n}: falta {''.join(sorted(set(c for c in a.falta if ord(c) not in cm and c != ' '))) or '-'}")
        return
    patch("pixel_operator.ttf", REGULAR, a.rehacer)
    patch("pixel_operator_bold.ttf", BOLD, a.rehacer)
    patch("pixel_operator_8.ttf", SMALL, a.rehacer)


if __name__ == "__main__":
    sys.exit(main())
