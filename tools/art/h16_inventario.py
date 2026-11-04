#!/usr/bin/env python3
"""Altas en assets/inventario.json del arte de H16 y H17 (docs/gdd/04f_vida_y_fiestas.md §4.28.3, 03b §3b.2):
ilustraciones de fiestas, eventos y sucesos, y lo que se vaya añadiendo por prioridades. Si otro worker dejó una
entrada «falta» con el mismo id, se rellena esa. Idempotente.
Uso: python3 tools/art/h16_inventario.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fal_rutas as fr_  # noqa: E402

ROOT = fr_.ROOT
INV = os.path.join(ROOT, "assets", "inventario.json")
FAL_ILL = "fal: nano-banana-2/edit (ref: el título al alba) + paleta de image2pixel (tools/art/fal_ilustraciones.py)"
FIESTAS = {"semana_santa": "Semana Santa", "mayos_corpus": "los Mayos y el Corpus", "san_juan": "San Juan",
           "siega_feria": "la siega y la feria", "san_miguel": "San Miguel y la vendimia",
           "matanza": "Todos los Santos y San Martín (la matanza)", "navidad": "Navidad", "carnaval": "Carnaval"}
EVENTOS = {"visita_marques": "la visita del marqués", "boda_rica": "la boda de una familia noble o rica",
           "boda_vecinos": "la boda de vecinos", "torneo": "el torneo", "comicos": "la compañía de cómicos",
           "predicador": "el predicador", "romeria": "la romería a Montsacre", "rogativa": "la rogativa",
           "feria_ganado": "la feria de ganado"}
SUCESOS = {"altercado": "el altercado", "asalto_bandidos": "el asalto de bandidos", "secuestro": "el secuestro",
           "rescate": "el rescate", "ladron": "el ladrón nocturno"}


def illustrations():
    out = []
    for group, items, para, sec in (("fiesta", FIESTAS, ["H16", "fiestas"], "§4.25.1"),
                                    ("evento", EVENTOS, ["H16", "fiestas"], "§4.25.2"),
                                    ("suceso", SUCESOS, ["H16", "sucesos"], "§4.24.5")):
        for iid, what in items.items():
            path = f"assets/art/illustrations/events/{iid}.png"
            if not os.path.exists(os.path.join(ROOT, path)):
                continue
            out.append({"id": "illus_" + iid, "tipo": "ui", "estado": "sprite", "para": para, "ruta": path,
                        "origen": FAL_ILL, "coste_gen": 0, "coste_usd": 0.08,
                        "notas": f"Ilustración de {what} (04f {sec}), 240×135, y {iid}_192.png a 192×108 (aviso). "
                                 "Para la carta del kit de página; se lee por VisualPaths."})
    return out


FOOD = {"beer": "cerveza", "strong_beer": "cerveza fuerte", "wine": "vino", "good_wine": "vino bueno",
        "cider": "sidra", "bread": "pan", "garlic_soup": "sopa de ajo", "empanada": "empanada", "stew": "olla",
        "roast_lamb": "cordero asado", "sausage": "embutido", "sweets": "dulces de Navidad"}
FAL_ICON = "fal: nano-banana-2/edit (ref: 8 iconos del juego) + image2pixel (tools/art/fal_iconos.py)"


def tavern():
    out = []
    if os.path.exists(os.path.join(ROOT, "assets/art/buildings/fal/tavern_inn.png")):
        out.append({"id": "bld_tavern_inn", "tipo": "edificio", "estado": "sprite", "para": ["H17", "posada"],
                    "ruta": "assets/art/buildings/fal/tavern_inn.png",
                    "origen": "fal: nano-banana-2/edit (ref: la fachada fal de la carpintería, mismo lienzo y puerta) + "
                              "image2pixel (tools/art/fal_fachadas.py)", "coste_gen": 0, "coste_usd": 0.24,
                    "notas": "Taberna-Posada (04f §4.27): dos plantas con entramado, cartel con una jarra (sin letras), "
                             "toneles, banco y un cobertizo de establo. Huella 3×4 como la carpintería. Lienzo 192×230 "
                             "(20 px más alto que el de la carpintería): en la escena, Sprite offset (-104, -158) y "
                             "Door (-40, 12), los pies como la carpintería. 2 intentos descartados (tejado cortado; "
                             "la referencia grande, ampliada)."})
    if os.path.exists(os.path.join(ROOT, "assets/art/buildings/fal/tavern_inn_back.png")):
        out.append({"id": "bld_tavern_inn_back", "tipo": "edificio", "estado": "sprite", "para": ["H17", "posada"],
                    "ruta": "assets/art/buildings/fal/tavern_inn_back.png",
                    "origen": "fal: nano-banana-2/edit (ref: tavern_inn.png) + image2pixel (tools/art/fal_fachadas.py "
                              "--estado back)", "coste_gen": 0, "coste_usd": 0.08,
                    "notas": "La Taberna-Posada de espaldas, sin puerta en las caras visibles (para la puerta del sim en "
                             "una cara oculta). Mismo lienzo y ancla que tavern_inn.png."})
    if os.path.exists(os.path.join(ROOT, "assets/art/interiors/tavern/bar.png")):
        out.append({"id": "int_tavern", "tipo": "interior", "estado": "sprite", "para": ["H17", "posada"],
                    "ruta": "assets/art/interiors/tavern/",
                    "origen": "fal: nano-banana-2/edit (ref: el kit de la forja ×4) + image2pixel (tools/art/"
                              "fal_taberna.py); suelo con Pillow; paredes, copia de la carpintería",
                    "coste_gen": 0, "coste_usd": 0.16,
                    "notas": "Kit de interior de la Taberna-Posada (04f §4.27.4): bar (80×72), table, bench, barrel, "
                             "kitchen, fireplace, minstrel_corner (64×64), bed (80×72), con los pies abajo en el centro "
                             "como los de la forja; floor.png (tablas, 64×32, tesela) y wall_ne/nw, wall_door_ne/nw "
                             "(32×52, de la carpintería)."})
    for fid, what in FOOD.items():
        path = f"assets/art/ui/icons/food_{fid}.png"
        if os.path.exists(os.path.join(ROOT, path)):
            out.append({"id": "ui_icon_food_" + fid, "tipo": "ui", "estado": "sprite", "para": ["H17", "posada"],
                        "ruta": path, "origen": FAL_ICON, "coste_gen": 0, "coste_usd": 0.02,
                        "notas": f"Icono de la carta de la taberna: {what} (04f §4.27.3), 32×32 y small/ (16×16). "
                                 "Para el bocadillo del pedido y la carta."})
    return out


def apply(entries):
    raw = open(INV).read()
    d = json.loads(raw)
    by = {a["id"]: a for a in d["assets"]}
    by_path = {a["ruta"]: a for a in d["assets"]}
    added = filled = 0
    for e in entries:
        old = by.get(e["id"]) or by_path.get(e["ruta"])
        if old is not None:  # la entrada «falta» de otro worker (mismo id o misma ruta): se rellena esa
            keep_id = old["id"]
            old.update({k: v for k, v in e.items() if k != "id"})
            old["id"] = keep_id
            filled += 1
        else:
            d["assets"].append(e)
            added += 1
    with open(INV, "w") as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
    print(f"inventario: {added} nuevas, {filled} rellenadas o actualizadas")


def main():
    apply(illustrations() + tavern())


if __name__ == "__main__":
    main()
