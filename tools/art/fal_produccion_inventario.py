#!/usr/bin/env python3
"""Da de alta en assets/inventario.json los retratos (assets/art/portraits/) y las ilustraciones
(assets/art/illustrations/) de la producción con fal del 2026-11-03. Solo los que tienen fichero. Idempotente: si la
entrada ya existe, la actualiza. Uso: python3 tools/art/fal_produccion_inventario.py
"""
import json
import os
import sys

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import fal_ilustraciones as fi  # noqa: E402
import fal_retratos as fr  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
INV = os.path.join(ROOT, "assets", "inventario.json")

STAGE = {"child": "niño (0-7)", "youth": "escuela y aprendiz (8-15)", "adult": "adulto (16-44)",
         "mature": "maduro (45-54)", "elder": "anciano (55+)"}
GROUP = {"artisan": (["H8", "familia"], "familia del jugador · Artesano"),
         "patron": (["H12", "familia"], "familia del jugador · Patrón (4.22)"),
         "scholar": (["H12", "familia"], "familia del jugador · Erudito (4.22)"),
         "rogue": (["H12", "familia"], "familia del jugador · Pícaro (4.22)"),
         "worker": (["H4", "empleados"], "empleado"),
         "townsfolk": (["H8", "vecinos"], "vecino"),
         "rival": (["H8", "rivales"], "cabeza o pareja de una familia rival (4.21)")}
OWN = {"mayor": ["H10", "cargos"], "judge": ["H11", "tribunal"], "priest": ["H12", "iglesia"],
       "constable": ["H10", "cargos"], "tax_collector": ["H10", "cargos"], "market_inspector": ["H10", "cargos"],
       "councillor": ["H10", "cargos"], "captain": ["H3", "encargos"], "dignitary": ["H13", "eventos"],
       "foreigner": ["H12", "forasteros"]}
CARD_FOR = {"card_wedding": ["H8", "boda"], "card_birth": ["H8", "familia"], "card_death": ["H8", "familia"],
            "card_trial": ["H11", "tribunal"], "card_verdict": ["H11", "tribunal"], "card_election": ["H10", "cargos"],
            "card_title": ["H9", "títulos"]}
KEY_NOTE = ("Colores clave de GDD 4.10.9 codificados como los sprites de personaje (alfa 254, región en el azul: 50 "
            "pelo con barba y cejas, 100 piel con labios y cuello, 150 ropa principal, 200 ropa secundaria; brillo en "
            "el rojo): se pinta con game/visuals/characters/identity_swap.gdshader. Fondo transparente (lo pone el "
            "marco). 64 = busto (fichas y cartas), <id>_32.png = cara (HUD y árbol).")


def portrait_entry(pid, grid):
    path = f"assets/art/portraits/{pid}.png"
    if pid in OWN:
        para, what = OWN[pid], "cargo o personaje único, con su ropa propia (solo se marcan pelo y piel)"
    else:
        g, st, sx = pid.split("_")[:3]
        para, what = GROUP[g]
        sex = "hombre" if sx == "m" else "mujer"
        what = f"{what}, {STAGE.get(st, st)}, {sex}"
    return {"id": "portrait_" + pid, "tipo": "retrato", "estado": "sprite", "para": para, "ruta": path,
            "origen": f"fal: nano-banana-2/edit, rejilla {grid} (ref: rejilla del piloto) + mapa de regiones por /edit "
                      "+ image2pixel (tools/art/fal_retratos.py, fal_retratos_proc.py)",
            "coste_gen": 0, "coste_usd": 0.04,
            "notas": f"Retrato de tipo de personaje: {what}. {KEY_NOTE} Sin cablear en escenas. Crudo y vista sin "
                     f"codificar en ~/Code/GuildMaster-arte-crudos/fal_produccion/retratos/."}


def illus_entry(pid):
    kind = fi.PIECES[pid][0] if pid in fi.PIECES else fi.FROM_PILOT[pid][0]
    if kind == "event":
        para = ["H13", "eventos"]
        size = "240×135 (libro y cartas) y <id>_192.png a 192×108 (aviso)"
        what = "Evento global " + pid[len("event_"):] + " (data/events.json)"
    elif kind == "season":
        para = ["H13", "estaciones"]
        size = "240×135 y <id>_192.png a 192×108"
        what = "Estación " + pid[len("season_"):] + " (data/seasons.json)"
    elif kind == "card":
        para = CARD_FOR[pid]
        size = "240×135"
        what = "Ilustración de carta (" + pid[len("card_"):] + ")"
    else:
        para = ["UI", "pantallas"]
        size = "960×540 (dibujada a 480×270 y doblada ×2 entero)"
        what = "Fondo de pantalla (" + pid[len("screen_"):] + ", docs/ui/02_menu_inicial.md)"
    src = "del piloto" if pid in fi.FROM_PILOT else "nano-banana-2/edit"
    return {"id": ("ui_" if kind == "screen" else "illus_") + pid,
            "tipo": "ui", "estado": "sprite", "para": para, "ruta": f"assets/art/illustrations/{pid}.png",
            "origen": f"fal: {src} (ref: lámina de título al alba del piloto o la pieza de la que deriva) + paleta de "
                      "image2pixel y reducción con caja (tools/art/fal_ilustraciones.py)",
            "coste_gen": 0, "coste_usd": 0.08 if pid not in fi.FROM_PILOT else 0.0,
            "notas": f"{what}. {size}. Sin cablear en escenas. Crudo en ~/Code/GuildMaster-arte-crudos/fal_produccion/ilustraciones/ "
                     f"(o ~/Code/GuildMaster-arte-crudos/fal_piloto/)."}


ICON_FOR = {"gavel": ["H11", "tribunal"], "ballot_box": ["H10", "elecciones"], "reputation": ["H9", "reputación"],
            "menu": ["UI", "menú"], "save": ["UI", "partidas"], "load": ["UI", "partidas"],
            "parcels": ["H6", "construcción"]}
ICON_ORIGIN = ("fal: nano-banana-2/edit, rejilla 2×2 (ref: 8 iconos buenos del juego ×4; burbujas: las 6 del juego) "
               "+ image2pixel a escala 16 + contorno oscuro (tools/art/fal_iconos.py)")


def extras(d, by_id):
    """Iconos (objeto, UI, burbujas) y fachadas de la tanda extra."""
    import fal_iconos as fic
    import fal_fachadas as ffa
    new = []
    for iid, (rel, what) in fic.ICONS.items():
        path = "assets/art/" + rel
        if not os.path.exists(os.path.join(ROOT, path)):
            continue
        small = "/small/".join(rel.rsplit("/", 1))
        if rel.startswith("icons/"):
            e = dict(d["assets"][by_id["icon_" + iid]])
            e.update({"estado": "sprite", "origen": ICON_ORIGIN, "coste_gen": 0, "coste_usd": 0.02,
                      "notas": f"32×32 y assets/art/{small} (16×16, half() de derivar_guild.py). Sustituye al "
                               f"placeholder dibujado (en el historial de git). Crudo en "
                               f"~/Code/GuildMaster-arte-crudos/fal_produccion/iconos/."})
        elif rel.startswith("ui/bubbles/"):
            e = dict(d["assets"][by_id["bubble_" + iid]])
            e.update({"estado": "sprite", "origen": ICON_ORIGIN, "coste_gen": 0, "coste_usd": 0.02,
                      "notas": f"Burbuja de emoción (GDD 4.11.5), 32×32 y assets/art/{small}. La escena "
                               f"game/visuals/bubbles/{iid}.tscn sigue con su greybox: falta poner el sprite."})
        else:
            e = {"id": "ui_icon_" + iid, "tipo": "ui", "estado": "sprite", "para": ICON_FOR[iid], "ruta": path,
                 "origen": ICON_ORIGIN, "coste_gen": 0, "coste_usd": 0.02,
                 "notas": f"Icono de UI que faltaba (docs/ui/00_lenguaje_visual.md §7): {what}. 32×32 y "
                          f"assets/art/{small} (16×16). Sin cablear."}
        new.append(e)
    for bid in ffa.BUILDINGS:
        path = f"assets/art/buildings/fal/{bid}.png"
        if not os.path.exists(os.path.join(ROOT, path)):
            continue
        states = [s for s in ("construction", "damaged")
                  if os.path.exists(os.path.join(ROOT, f"assets/art/buildings/fal/{bid}_{s}.png"))]
        new.append({"id": f"bld_{bid}_fal", "tipo": "edificio", "estado": "sprite",
                    "para": d["assets"][by_id["bld_" + bid]]["para"], "ruta": path,
                    "origen": "fal: nano-banana-2/edit con una sola referencia (su sprite de escala B ×4) + "
                              "image2pixel a escala 4 (tools/art/fal_fachadas.py)",
                    "coste_gen": 0, "coste_usd": 0.08 * (1 + len(states)),
                    "notas": f"Fachada redibujada del edificio {bid}, estado normal, con el mismo lienzo y ancla que "
                             f"assets/art/buildings/escala_b/{bid}.png: para usarla, en "
                             f"game/visuals/buildings/{bid}.tscn poner esta textura en el nodo Sprite (sin mover "
                             f"Feet ni el offset). Estados: " + (", ".join(f"{bid}_{s}.png" for s in states) or "—") +
                             " (mismo lienzo). Sin cablear: la decide la integración."})
        base = d["assets"][by_id["bld_" + bid]]
        if "buildings/fal/" not in base["notas"]:
            base["notas"] += f" Candidata fal (2026-11-03): {path} (mismo lienzo y ancla; entrada bld_{bid}_fal)."
    return new


def main():
    raw = open(INV).read()
    d = json.loads(raw)
    by_id = {a["id"]: i for i, a in enumerate(d["assets"])}
    new = []
    grids = {pid: g for g, cells in fr.GRIDS.items() for pid, _, _ in cells}
    grids.update({pid: g for g, ids in fr.PILOT.items() for pid in ids})
    for pid, g in sorted(grids.items()):
        if os.path.exists(os.path.join(ROOT, "assets", "art", "portraits", pid + ".png")):
            new.append(portrait_entry(pid, g))
    for pid in list(fi.PIECES) + list(fi.FROM_PILOT):
        if os.path.exists(os.path.join(ROOT, "assets", "art", "illustrations", pid + ".png")):
            new.append(illus_entry(pid))
    new += extras(d, by_id)
    added = updated = 0
    for e in new:
        if e["id"] in by_id:
            d["assets"][by_id[e["id"]]] = e
            updated += 1
        else:
            d["assets"].append(e)
            added += 1
    # la pieza de retrato (marco y greybox) apunta a los retratos nuevos
    for a in d["assets"]:
        if a["id"] == "ui_portrait" and "assets/art/portraits/" not in a["notas"]:
            a["notas"] += (" Retratos de producción (fal, 2026-11-03): assets/art/portraits/<tipo>.png (64) y "
                           "<tipo>_32.png, entradas portrait_* del inventario; falta cablearlos en portrait.tscn.")
    with open(INV, "w") as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
    print(f"inventario: {added} nuevas, {updated} actualizadas")


if __name__ == "__main__":
    main()
