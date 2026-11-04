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
    apply(illustrations())


if __name__ == "__main__":
    main()
