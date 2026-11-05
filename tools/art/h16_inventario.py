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


def games_and_forge():
    out = []
    G = "assets/art/ui/games/"
    if os.path.exists(os.path.join(ROOT, G + "naipes/oros_1.png")):
        out.append({"id": "ui_game_naipes", "tipo": "ui", "estado": "sprite", "para": ["H16", "juegos"],
                    "ruta": G + "naipes/",
                    "origen": "fal: nano-banana-2/edit (los 4 palos y 12 figuras) + image2pixel; cartas compuestas con "
                              "Pillow (tools/art/juegos_taberna.py)", "coste_gen": 0, "coste_usd": 0.32,
                    "notas": "Baraja de 40 de 4 palos (04f §4.26.8), al estilo de los naipes antiguos: "
                             "<oros|copas|espadas|bastos>_<1-7|10|11|12>.png (48×72, número en las esquinas, la "
                             "disposición de los palos de la baraja española; 10 sota, 11 caballo, 12 rey), back.png "
                             "(reverso), slot.png (hueco), suit_<palo>.png (32) y small/ (16)."})
    if os.path.exists(os.path.join(ROOT, G + "dados/d1.png")):
        out.append({"id": "ui_game_dados", "tipo": "ui", "estado": "sprite", "para": ["H16", "juegos"],
                    "ruta": G + "dados/", "origen": "dibujado (Pillow, tools/art/juegos_taberna.py dados)",
                    "coste_gen": 0, "notas": "Dados de hueso (04f §4.26.7): d1-d6.png (24×24, cara de arriba, "
                                             "puntos exactos) y shadow.png."})
    if os.path.exists(os.path.join(ROOT, G + "mesa/mesa.png")):
        out.append({"id": "ui_game_mesa", "tipo": "ui", "estado": "sprite", "para": ["H16", "juegos"],
                    "ruta": G + "mesa/mesa.png",
                    "origen": "fal: nano-banana-2/edit (ref: el título al alba) + paleta de image2pixel",
                    "coste_gen": 0, "coste_usd": 0.08,
                    "notas": "Fondo de mesa de taberna para dados y naipes, visto desde arriba, el centro libre: "
                             "960×540 (480×270 ×2)."})
    F = "assets/art/ui/forge/"
    if os.path.exists(os.path.join(ROOT, F + "iron_cherry.png")):
        out.append({"id": "ui_forge_live", "tipo": "ui", "estado": "sprite", "para": ["H17", "forja"],
                    "ruta": F,
                    "origen": "fal: nano-banana-2/edit (ref: el kit de la forja ×4) + image2pixel "
                              "(tools/art/fal_forja_viva.py); calores y golpes, con Pillow", "coste_gen": 0,
                    "coste_usd": 0.16,
                    "notas": "Forja viva (03b §3b.2). Calentar: iron_cold y iron_<dark_red|cherry|orange|yellow|"
                             "white>.png (64×64, la misma barra con rampas fijas) y hearth.png (la fragua). Batir: "
                             "strike_<strong|measured|finish>.png (80×96: el martillo arriba, a media altura o en la "
                             "barra, con chispas según el golpe), anvil.png y hammer.png sueltos para animarlos. "
                             "Templar: quench_<water|oil|air>.png (64×64)."})
        out.append({"id": "ui_icon_forge_traits", "tipo": "ui", "estado": "sprite", "para": ["H17", "forja"],
                    "ruta": F + "trait_oil_tempered.png",
                    "origen": "fal: nano-banana-2/edit (ref: 8 iconos del juego) + image2pixel (tools/art/fal_iconos.py)",
                    "coste_gen": 0, "coste_usd": 0.08,
                    "notas": "Iconos de rasgos de pieza (03b §3b.2): trait_<oil_tempered|water_tempered|air_cooled|"
                             "fine_edge|master_mark|masterwork>.png (32×32) y small/ (16×16): templada al aceite, "
                             "templada al agua, enfriada al aire, filo fino, marca del maestro y obra maestra."})
    return out


def props():
    sys.path.insert(0, HERE)
    import fal_props_fiesta as fpf
    out = []
    for pid, ((fw, fh), _, what) in fpf.PROPS.items():
        png = f"assets/art/props/fiesta/{pid}.png"
        if not os.path.exists(os.path.join(ROOT, png)):
            continue
        out.append({"id": "prop_fiesta_" + pid, "tipo": "prop", "estado": "sprite", "para": ["H16", "fiestas"],
                    "ruta": png,
                    "origen": "fal: nano-banana-2/edit (ref: 6 props del juego ×4) + image2pixel (tools/art/"
                              "fal_props_fiesta.py)", "coste_gen": 0, "coste_usd": 0.02,
                    "notas": f"Decoración de fiesta (04f §4.25.3): {what}. Huella {fw}×{fh} casillas. Escena "
                             f"game/visuals/props/fiesta/{pid}.tscn (Feet en el centro de la huella, Top, Sprite; "
                             f"metadata/footprint en la raíz)."})
    return out


def characters():
    """Los personajes nuevos de H16 (paletas de looks.json sobre los sprites de hoy) y los animales (sin hacer)."""
    out = []
    looks = os.path.join(ROOT, "assets/art/characters/looks.json")
    if os.path.exists(looks):
        for lid, e in json.load(open(looks))["looks"].items():
            out.append({"id": "chr_h16_" + lid, "tipo": "npc", "estado": "greybox", "para": ["H16", "fiestas"],
                        "ruta": "assets/art/characters/looks.json",
                        "origen": "paleta del shader de identidad sobre " + "/".join(sorted(set(e["base"].values())))
                                  + " (tools/art/looks_h16.py)", "coste_gen": 0,
                        "notas": f"{e['note'][0].upper() + e['note'][1:]} (04f §4.28.3). Hasta PixelLab (15-nov) es el "
                                 f"sprite de {e['base']['m']}/{e['base']['f']} teñido: primary {e['primary']}, "
                                 f"secondary {e['secondary']}" + (f", pelo {e['hair']}" if e["hair"] else "") +
                                 ". Lista para pedir: assets/art/MANIFEST.md, «Lista de la compra · PixelLab» (10)."})
    for aid, what in (("pig", "cerdo (la matanza)"), ("bull", "toro (los toros)"),
                      ("horse", "caballo (la carrera, el torneo y la liza)"), ("sheep", "oveja (la feria de ganado)")):
        out.append({"id": "chr_animal_" + aid, "tipo": "npc", "estado": "falta", "para": ["H16", "fiestas"],
                    "ruta": f"assets/art/characters/animal_{aid}/", "origen": None, "coste_gen": 0,
                    "notas": f"Animal: {what} (04f §4.25-4.26). PixelLab create_character cuadrúpedo, andar e idle "
                             "en 8 direcciones, en el ciclo del 15-nov: assets/art/MANIFEST.md, «Lista de la compra · "
                             "PixelLab» (11)."})
    return out


GAME_ILL = {"azar": "el azar", "mayor": "«a la mayor»", "pulso": "el pulso", "envite": "el envite",
            "tourney": "el torneo de lucha", "joust": "la justa", "sortija": "la sortija", "race": "la carrera",
            "bulls": "correr el toro"}
GAME_ICON = dict(GAME_ILL, bets="el corredor de apuestas")
BOARDS = {"ui_games_joust_lists": ("joust/lists.png", "la liza de la justa de lado: la tela a media altura, el "
                                   "público y los pendones detrás"),
          "ui_games_sortija_lane": ("sortija/lane.png", "la calle de la sortija de lado: el arco con el travesaño en "
                                    "el centro, sin nada colgado (la anilla la pinta el tablero), y tres postes de "
                                    "señal"),
          "ui_games_race_track": ("race/track.png", "el camino de la carrera desde arriba, a casi toda la altura (sitio "
                                  "para 6 calles): salida a la izquierda, el molino abajo a dos tercios, el palio de la "
                                  "meta a la derecha. 404×192 ×2 = 808×384, para que el recorte no se coma la salida "
                                  "ni la meta"),
          "ui_games_bulls_plaza": ("bulls/plaza.png", "la plaza cerrada con un círculo de carros desde arriba, con "
                                   "balcones alrededor; el centro, libre"),
          "ui_games_tourney_list": ("tourney/list.png", "el palenque del torneo: tierra apisonada dentro de una "
                                    "empalizada, público y pendones; el tercio izquierdo, en sombra"),
          "ui_games_fight_street": ("fight/street.png", "una calle de noche con dos antorchas, para el rescate y el "
                                    "altercado")}
FAL_GAME = "fal: nano-banana-2/edit (ref: el título al alba) + paleta de image2pixel (tools/art/fal_ilustraciones.py)"


def games_p6():
    """Prioridad 6: lo que pidieron los workers de juegos y de la forja (entradas «falta» suyas, se rellenan)."""
    out = []
    E = "assets/art/illustrations/events/"
    for g, what in GAME_ILL.items():
        if os.path.exists(os.path.join(ROOT, E + f"game_{g}.png")):
            out.append({"id": "ill_game_" + g, "tipo": "ui", "estado": "sprite", "para": ["juegos", "H16"],
                        "ruta": E + f"game_{g}.png", "origen": FAL_GAME, "coste_gen": 0, "coste_usd": 0.08,
                        "notas": f"Lámina del resultado de {what} (04f §4.26), 240×135, y game_{g}_192.png a 192×108. "
                                 f"VisualPaths.game_illustration(\"game_{g}\")."})
    for g, what in GAME_ICON.items():
        if os.path.exists(os.path.join(ROOT, f"assets/art/ui/icons/game_{g}.png")):
            out.append({"id": "icon_game_" + g, "tipo": "icono", "estado": "sprite", "para": ["juegos", "H16"],
                        "ruta": f"assets/art/ui/icons/game_{g}.png", "origen": FAL_ICON, "coste_gen": 0,
                        "coste_usd": 0.02, "notas": f"Icono de {what}, 32×32 y small/game_{g}.png 16×16. "
                                                    f"VisualPaths.game_icon(\"{g}\")."})
    G = "assets/art/ui/games/"
    for iid, (rel, what) in BOARDS.items():
        if os.path.exists(os.path.join(ROOT, G + rel)):
            size = "808×384" if "race" in rel else "880×384 (440×192 ×2)"
            out.append({"id": iid, "tipo": "ui", "estado": "sprite", "para": ["juegos", "H16"], "ruta": G + rel,
                        "origen": FAL_GAME.replace("título al alba)", "título al alba; 21:9)"), "coste_gen": 0,
                        "coste_usd": 0.08,
                        "notas": f"Fondo de tablero (04f §4.26): {what}. {size}: el tablero recorta abajo y en el "
                                 "centro a ½ (404×180 como mínimo); lo importante, abajo y en el centro. Sin texto."})
    FS = "fal: nano-banana-2/edit (ref: 6 props del juego ×4) + image2pixel (tools/art/fal_juegos_sprites.py)"
    if os.path.exists(os.path.join(ROOT, G + "joust/horse.png")):
        out.append({"id": "ui_games_joust_horse", "tipo": "ui", "estado": "sprite", "para": ["juegos", "H16"],
                    "ruta": G + "joust/horse.png", "origen": FS, "coste_gen": 0, "coste_usd": 0.04,
                    "notas": "Caballo de justa con gualdrapa azul y oro y el caballero con la lanza en ristre, de perfil "
                             "al este (al oeste se refleja), 48×32, y horse_fallen.png (48×32): el caballo sin jinete "
                             "y el caballero en el suelo. Los pies, abajo; la figura ocupa ~35 de ancho, centrada."})
    if os.path.exists(os.path.join(ROOT, G + "race/horse_run.png")):
        out.append({"id": "ui_games_race_horse", "tipo": "ui", "estado": "sprite", "para": ["juegos", "H16"],
                    "ruta": G + "race/horse.png", "origen": FS, "coste_gen": 0, "coste_usd": 0.08,
                    "notas": "Caballo al galope con jinete, de perfil al este: horse_run.png es la tira de 4 fotogramas "
                             "(112×18, 28×18 cada uno) y horse.png el primero suelto (28×18, lo que dibuja el tablero "
                             "de hoy). La ropa y la gorra del jinete, en gris neutro (r=g=b) para teñirla por código."})
    if os.path.exists(os.path.join(ROOT, G + "bulls/bull.png")):
        out.append({"id": "ui_games_bulls_bull", "tipo": "ui", "estado": "sprite", "para": ["juegos", "H16"],
                    "ruta": G + "bulls/bull.png", "origen": FS, "coste_gen": 0, "coste_usd": 0.04,
                    "notas": "El toro negro de perfil al este, 36×24, y bull_charge.png (36×24): embistiendo con la "
                             "cabeza baja. Los pies, abajo."})
    if os.path.exists(os.path.join(ROOT, G + "dados/cup.png")):
        out.append({"id": "ui_games_dice_cup", "tipo": "ui", "estado": "sprite", "para": ["juegos", "H16"],
                    "ruta": G + "dados/cup.png", "origen": "dibujado (Pillow, tools/art/juegos_taberna.py cubilete)",
                    "coste_gen": 0, "notas": "El cubilete de cuero boca abajo que tapa el dado oculto de «a la "
                                             "mayor» (04f §4.26.7), 24×24 como los dados, la boca abajo."})
    if os.path.exists(os.path.join(ROOT, E + "masterwork.png")):
        out.append({"id": "illus_masterwork", "tipo": "ui", "estado": "sprite", "para": ["H17", "forja"],
                    "ruta": E + "masterwork.png", "origen": FAL_ILL, "coste_gen": 0, "coste_usd": 0.08,
                    "notas": "Lámina de la carta «Obra maestra» de la Forja viva (03b §3b.2): el maestro alza la "
                             "espada recién hecha a la luz de la fragua, los aprendices miran. 240×135 y "
                             "masterwork_192.png a 192×108."})
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
    apply(illustrations() + tavern() + games_and_forge() + props() + characters() + games_p6())


if __name__ == "__main__":
    main()
