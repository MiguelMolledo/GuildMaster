#!/usr/bin/env python3
"""Altas en assets/inventario.json del arte del duelo y de la región (2026-11-04): efectos (vfx_workbench, gratis),
iconos, ilustraciones de carta y de ciudad, la ficha de la familia y el carro del mapa regional. Idempotente.
Uso: python3 tools/art/fal_duelo_region_inventario.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fal_rutas as fr_  # noqa: E402

ROOT = fr_.ROOT
INV = os.path.join(ROOT, "assets", "inventario.json")
FAL = "fal: nano-banana-2/edit"
CITIES = {"villa": "Vilarrasa (villa del jugador, pueblo-calle)", "capital": "Bellcaire (capital, mercado y catedral)",
          "port": "Portvell (puerto de río)", "quarry": "Peñarroja (mina y cantera)",
          "hamlet": "Vilablat (aldea de trigo y molino)", "abbey": "Montsacre (abadía en la sierra)"}


def main():
    raw = open(INV).read()
    d = json.loads(raw)
    by = {a["id"]: a for a in d["assets"]}
    upd = {}
    for vid, what in (("duel_strike", "Tajo del golpe"), ("duel_parry", "Chispa de la parada"),
                      ("duel_feint", "Estela de la finta"), ("duel_hit", "Toque recibido")):
        meta = json.load(open(os.path.join(ROOT, "assets", "art", "vfx", vid, vid + ".json")))
        upd["vfx_" + vid] = {"estado": "animado", "animaciones": {"loop": "animado"}, "origen": "pixellab vfx_workbench",
                             "coste_gen": 0, "notas": f"{what}: tira {vid}.png de {meta['frames']} fotogramas de "
                             f"{meta['frame_w']}×{meta['frame_h']} a {meta['fps']} fps, una vez (no en bucle), y "
                             f"{vid}.json con el desplazamiento respecto a los pies mirando al este (al oeste, "
                             f"reflejado). Gratis, sin generaciones; editable en «My effects» de pixellab.ai "
                             f"(tools/art/vfx_duelo.py). Sin cablear (DuelArena lo dibuja hoy por código)."}
    upd["icon_duel_actions"] = {"estado": "sprite", "origen": FAL + " (ref: 8 iconos del juego) + image2pixel "
                                "(tools/art/fal_iconos.py)", "coste_gen": 0, "coste_usd": 0.2,
                                "notas": "icon_<strike|parry|feint|surrender|auto|breath|touch|challenge>.png "
                                         "(32×32) y small/ (16×16): Golpe, Parada, Finta, Rendirse, Resolver sin "
                                         "jugar, aliento, toque y reto. Sin cablear (hoy, texto y cuadros)."}
    upd["ill_duel_result"] = {"estado": "sprite", "origen": FAL + " (ref: el título al alba) + paleta de image2pixel "
                              "(tools/art/fal_ilustraciones.py)", "coste_gen": 0, "coste_usd": 0.4,
                              "notas": "victory, defeat, draw (carta de resultado) y challenge (carta de reto), "
                                       "cada una a 240×135 (<nombre>.png) y 192×108 (<nombre>_192.png). Sin cablear."}
    old = by["chr_duel_poses"]["notas"]
    if "§8 de docs/ui/mecanicas/combate.md" not in old:
        upd["chr_duel_poses"] = {"notas": old + " Lista para pedir (personajes de PixelLab, plantillas y acciones a "
                                 "medida, ~40 generaciones) en §8 de docs/ui/mecanicas/combate.md."}
    for aid, fields in upd.items():
        by[aid].update(fields)
    new = []
    for cid, what in CITIES.items():
        new.append({"id": "illus_city_" + cid, "tipo": "ui", "estado": "sprite", "para": ["region", "ciudades"],
                    "ruta": f"assets/art/illustrations/city_{cid}.png",
                    "origen": FAL + " (ref: el título al alba) + paleta de image2pixel (tools/art/fal_ilustraciones.py)",
                    "coste_gen": 0, "coste_usd": 0.08,
                    "notas": f"Ilustración de la página de ciudad de {what} (data/world/region.json, id {cid}), "
                             "240×135. Sin cablear."})
    for tid, what in (("tariff", "arancel"), ("treaty", "tratado"), ("caravan", "caravana"),
                      ("city_reputation", "reputación de ciudad")):
        new.append({"id": "ui_icon_" + tid, "tipo": "ui", "estado": "sprite", "para": ["region", "viajes"],
                    "ruta": f"assets/art/ui/icons/icon_{tid}.png",
                    "origen": FAL + " (ref: 8 iconos del juego) + image2pixel (tools/art/fal_iconos.py)",
                    "coste_gen": 0, "coste_usd": 0.02,
                    "notas": f"Icono de {what} (docs/gdd/09b_region.md §9b.5), 32×32 y small/ (16×16). Sin cablear."})
    new.append({"id": "ui_region_family_token", "tipo": "ui", "estado": "sprite", "para": ["region", "viajes"],
                "ruta": "assets/art/region/family_token.png",
                "origen": FAL + " (ref: el pergamino de Valldaura) + image2pixel (tools/art/fal_region_piezas.py)",
                "coste_gen": 0, "coste_usd": 0.04,
                "notas": "Ficha de la familia que viaja por el mapa regional: estandarte de tela en un mástil, 24×44 a "
                         "la densidad del pergamino (12×22 de arte ×2), pies abajo en el centro. La tela lleva los "
                         "colores de la familia codificados (alfa 254, azul 150 principal y 200 secundario): se pinta "
                         "con identity_swap.gdshader. Variante family_token_shield.png (escudo). Sin cablear."})
    new.append({"id": "ui_region_caravan", "tipo": "ui", "estado": "sprite", "para": ["region", "viajes"],
                "ruta": "assets/art/region/caravan.png",
                "origen": FAL + " (ref: el pergamino de Valldaura) + image2pixel (tools/art/fal_region_piezas.py)",
                "coste_gen": 0, "coste_usd": 0.04,
                "notas": "Carro de caravana de bueyes, de perfil mirando al este (al oeste, reflejado), 56×34 a la "
                         "densidad del pergamino. Variante caravan_cart.png (carreta de mula, 48×24). Sin cablear."})
    n_new = 0
    for e in new:
        if e["id"] in by:
            by[e["id"]].update(e)
        else:
            d["assets"].append(e)
            n_new += 1
    with open(INV, "w") as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
    print(f"inventario: {len(upd)} actualizadas, {n_new} nuevas")


if __name__ == "__main__":
    main()
