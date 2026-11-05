#!/usr/bin/env python3
"""Personajes nuevos de H16 (docs/gdd/04f_vida_y_fiestas.md §4.28.3) como PALETAS para el shader de identidad
(game/visuals/characters/identity_swap.gdshader) sobre los sprites que ya hay, hasta que PixelLab haga los suyos
(ciclo del 15-nov; la lista está en assets/art/MANIFEST.md, «Lista de la compra · PixelLab»).

Escribe assets/art/characters/looks.json:
  {"version": 1, "looks": {<id>: {"base": {"m": <id de sprite>, "f": <id de sprite>}, "primary": "#rrggbb",
   "secondary": "#rrggbb", "hair": "#rrggbb" | null, "note": "..."}}}
- base: el sprite de personaje de hoy que se tiñe (assets/art/characters/<base>/), según el sexo;
- primary / secondary: la ropa (en lugar de los colores de la familia);
- hair: null = el de la persona; un color = se fuerza (el mendigo, canoso y sucio).
La piel y el pelo siguen siendo los de la persona. Saca también una hoja de muestra a los crudos.
Uso: python3 tools/art/looks_h16.py
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fal_rutas as fr_  # noqa: E402
import personajes_guild as pg  # noqa: E402

ROOT = fr_.ROOT
OUT = os.path.join(ROOT, "assets", "art", "characters", "looks.json")
TOWN = {"m": "townsfolk_m", "f": "townsfolk_f"}
WORK = {"m": "worker_m", "f": "worker_f"}
LOOKS = {
    "guard": (WORK, "#33508a", "#c8a84e", None, "guardia de la villa: librea azul del concejo con ribete dorado "
                                               "(sin armadura hasta PixelLab)"),
    "bandit": (TOWN, "#3a362c", "#5c4630", None, "bandido: ropa parda y oscura"),
    "minstrel": (TOWN, "#c04040", "#e2c040", None, "juglar: rojo y amarillo, de colores vivos"),
    "foreign_merchant": (TOWN, "#5e3a80", "#d8bc8c", None, "mercader forastero: morado y tostado, ropa de otra "
                                                           "ciudad"),
    "pilgrim": (TOWN, "#7c6c52", "#d8d0b8", None, "peregrino: capa parda y esclavina clara"),
    "noble": (WORK, "#861a28", "#e2c070", None, "noble: carmesí y oro"),
    "retinue": (WORK, "#24448a", "#e6e6e6", None, "séquito del noble: librea azul y blanca"),
    "beggar": (TOWN, "#5e5440", "#4c4434", "#8a8478", "mendigo: harapos pardos y pelo gris"),
    "crier": (TOWN, "#2a6a3a", "#e2c040", None, "pregonero: verde de la villa con ribete amarillo"),
    "bookmaker": (TOWN, "#5a2a2a", "#c8a84e", None, "corredor de apuestas: granate con dorado"),
}


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def main():
    looks = {}
    for lid, (base, prim, sec, hair, note) in LOOKS.items():
        looks[lid] = {"base": base, "primary": prim, "secondary": sec, "hair": hair, "note": note}
    with open(OUT, "w") as f:
        json.dump({"version": 1, "_doc": __doc__.split("\n\n")[0].strip(), "looks": looks}, f, indent=1,
                  ensure_ascii=False)
        f.write("\n")
    # muestra: cada aspecto, hombre y mujer, de frente (idle_s, primer fotograma), ×3
    S = Image.new("RGBA", (len(LOOKS) * 2 * 72, 72), (62, 40, 20, 255))
    for i, (lid, e) in enumerate(looks.items()):
        for j, sx in enumerate(("m", "f")):
            st = Image.open(os.path.join(ROOT, "assets", "art", "characters", e["base"][sx], "idle_s.png"))
            fr = st.convert("RGBA").crop((0, 0, 68, 68))
            col = {1: hexrgb(e["hair"]) if e["hair"] else (92, 60, 34), 2: (224, 181, 140),
                   3: hexrgb(e["primary"]), 4: hexrgb(e["secondary"])}
            S.alpha_composite(pg.unkey(fr, col), ((i * 2 + j) * 72 + 2, 2))
    d = fr_.produccion("looks")
    os.makedirs(d, exist_ok=True)
    S.resize((S.width * 3, S.height * 3), Image.NEAREST).save(os.path.join(d, "looks.png"))
    print(f"looks.json: {len(looks)} aspectos; muestra en {os.path.join(d, 'looks.png')}")


if __name__ == "__main__":
    main()
