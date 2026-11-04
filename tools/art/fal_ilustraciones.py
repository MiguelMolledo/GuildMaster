#!/usr/bin/env python3
"""Ilustraciones de GuildMaster con fal (producción 2026-11-03): eventos globales (data/events.json), estaciones,
cartas y pantallas. nano-banana-2/edit con una sola referencia (la lámina de título al alba del piloto, o la pieza de
la que deriva) y pixelado con la paleta de image2pixel + reducción local con caja.

Medidas (docs/ui, decididas por el owner): eventos, estaciones y cartas a 240×135 (libro y cartas) y eventos y
estaciones también a 192×108 (aviso, <id>_192.png). Pantallas a 960×540: dibujadas a 480×270 y doblado ×2 entero.
Salida: assets/art/illustrations/<id>.png.

Uso: FAL_TANDA=produccion python3 tools/art/fal_ilustraciones.py gen [--solo id,id]
     FAL_TANDA=produccion python3 tools/art/fal_ilustraciones.py proc [--solo id,id]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from types import SimpleNamespace

from PIL import Image

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import fal_rutas as fr_  # noqa: E402  (crudos fuera del repo)
P = fr_.produccion("ilustraciones")
PILOT = fr_.PILOTO
OUT = os.path.join(ROOT, "assets", "art", "illustrations")
TITLE = os.path.join(PILOT, "titulo", "crudo", "titulo_alba_v1.png")
LOGO = os.path.join(ROOT, "assets", "art", "ui", "logo", "guildmaster_logo.png")

STYLE = ("Using the attached image only as STYLE reference (same 16-bit SNES pixel art, same warm earthy palette, "
         "outline and pixel size), paint ")
SMALL = (" Simple strong composition with a few large shapes and clear silhouettes, because it will be shown small "
         "(240x135 pixels). 14th-century Central European town. No text, no UI, no border.")
SCREEN = (" It is a full-screen background behind game menus: keep the central area calm and low in contrast so "
          "panels can sit on top, interesting detail towards the edges. 14th-century Central Europe. No text, no "
          "logo, no UI, no border.")


def ev(what):
    return STYLE + "an event illustration for a medieval town life-sim: " + what + SMALL


def card(what):
    return STYLE + "a story card illustration for a medieval dynasty life-sim: " + what + SMALL


# id -> (tipo, referencia, prompt). La referencia es una ruta o el id de otra pieza (se genera antes).
PIECES = {
    # eventos globales (data/events.json); war y festival salen del piloto
    "event_famine": ("event", TITLE, ev("FAMINE. A withered brown wheat field under a pale harsh sky, a gaunt farmer "
                                        "kneeling with an empty basket, an empty granary with its door open, crows.")),
    "event_epidemic": ("event", TITLE, ev("EPIDEMIC. A narrow street at dusk, doors marked with chalk crosses, a plague "
                                          "doctor in a beaked mask, a sick person wrapped in a blanket on a cart, "
                                          "sickly greenish mist.")),
    "event_good_harvest": ("event", TITLE, ev("GOOD HARVEST. A golden wheat field, peasants with sickles tying sheaves, "
                                              "a wooden cart piled high with golden sheaves (all of them golden and lit, no dark "
                                              "shapes), bright late-summer sun, the town behind.")),
    "event_religious_feast": ("event", TITLE, ev("RELIGIOUS FEAST. A procession leaving the stone church: a priest "
                                                 "carrying a cross, banners with saints, townsfolk holding candles, "
                                                 "flower petals on the street.")),
    "event_dignitary_visit": ("event", TITLE, ev("VISIT OF A DIGNITARY. A noble on a white horse with a retinue and "
                                                 "heraldic banners entering the market square, trumpeters, townsfolk "
                                                 "bowing.")),
    "event_riot": ("event", TITLE, ev("RIOT. Angry townsfolk with torches and pitchforks in the square at night, a "
                                      "smashed shop window, an overturned cart, smoke.")),
    "event_political_crisis": ("event", TITLE, ev("POLITICAL CRISIS. The town council chamber: councillors arguing and "
                                                  "pointing across a long table, a toppled chair, the mayor's gold chain "
                                                  "lying on the table, tense candlelight.")),
    "event_discovery": ("event", TITLE, ev("DISCOVERY. A workshop at night: a master craftsman unveils a new "
                                           "ingenious machine of gears and wood to amazed artisans, drawings pinned on "
                                           "the wall, warm lamplight.")),
    # estaciones: primavera con el título de referencia; las otras tres, la primavera redibujada
    "season_spring": ("season", TITLE, STYLE + "a season illustration: SPRING in the town. A close view of the main "
                      "street with timber-framed houses, blossoming trees, green fields and a ploughed field beyond, "
                      "a farmer sowing, swallows, fresh morning light." + SMALL),
    "season_summer": ("season", "season_spring", "Redraw this exact same view and composition in SUMMER: lush deep "
                      "green trees, tall green wheat, strong warm sun, a few people in the shade. Same pixel art style "
                      "and pixel size. No text."),
    "season_autumn": ("season", "season_spring", "Redraw this exact same view and composition in AUTUMN: orange and "
                      "red trees, falling leaves, golden stubble fields, a cart with pumpkins and apples, low golden "
                      "light. Same pixel art style and pixel size. No text."),
    "season_winter": ("season", "season_spring", "Redraw this exact same view and composition in WINTER: snow on the "
                      "roofs and street, bare trees, smoke from the chimneys, a person carrying firewood, grey-blue "
                      "sky. Same pixel art style and pixel size. No text."),
    # cartas
    "card_wedding": ("card", TITLE, card("WEDDING. A young couple joining hands at the church door, a priest blessing "
                                         "them, guests throwing petals, the bride with a flower crown.")),
    "card_birth": ("card", TITLE, card("BIRTH. A cosy bedroom by the hearth: a mother in bed holding a swaddled "
                                       "newborn, the proud father, a midwife, warm firelight. Every face is lit "
                                       "and clearly visible with eyes and features; no black silhouettes.")),
    "card_death": ("card", TITLE, card("DEATH. A funeral: a wooden coffin carried by four men towards the churchyard, "
                                       "mourners in dark cloaks with candles, grey sky, a bare tree.")),
    "card_trial": ("card", TITLE, card("TRIAL. A courtroom in the town hall: a judge in a black robe at a high bench, "
                                       "the accused standing between two guards, witnesses on benches.")),
    "card_verdict": ("card", TITLE, card("VERDICT. The judge stands raising a parchment scroll with a red wax seal, "
                                         "the hall holds its breath, the accused looks up; neutral, it can be guilty "
                                         "or innocent.")),
    "card_election": ("card", TITLE, card("ELECTION. In the town hall, burghers drop wooden tokens into a big urn one "
                                          "by one while councillors at a table count and record them.")),
    "card_title": ("card", TITLE, card("TITLE CEREMONY. A person kneels before the mayor, who lays a sword flat on "
                                       "their shoulder, heraldic banners, a crowd applauding, golden light.")),
    # tanda 4 (2026-11-04): cartas que pedían los documentos de UI y variantes aprobadas
    "card_succession": ("card", TITLE, card("SUCCESSION. In a candlelit bedroom the dying head of the family, in bed, "
                                            "hands the family ring and the account ledger to the kneeling heir, the "
                                            "rest of the family gathered around; every face lit and visible.")),
    "card_proposal": ("card", TITLE, card("MARRIAGE PROPOSAL. In a small garden by a stone well, a suitor on one knee "
                                          "offers a ring to a young woman; her family watches smiling from a doorway; "
                                          "faces lit and visible.")),
    "card_accusation": ("card", TITLE, card("ACCUSATION. The town constable nails a parchment summons with a red wax "
                                            "seal to the door of a workshop, while neighbours whisper and point.")),
    "card_title_citizen": ("card", TITLE, card("CITIZENSHIP. In the guild hall a craftsman signs the town register "
                                               "with a quill before the guild masters, who shake his hand.")),
    "card_title_patrician": ("card", TITLE, card("PATRICIAN RANK. A rich banquet hall: a merchant family is toasted at "
                                                 "the head of a long table full of food, under their banner.")),
    "card_title_baron": ("card", TITLE, card("BARONY. Investiture: a person kneels before a lord on a throne who lays "
                                             "a sword on their shoulder, knights and heraldic banners around.")),
    "card_title_noble": ("card", TITLE, card("NOBILITY. A royal court: a new noble in a fur mantle receives a "
                                             "parchment charter with a heavy gold seal before the crowned king, both in warm "
                                             "light with clearly visible faces and features; no black silhouettes.")),
    "card_verdict_guilty": ("card", TITLE, card("GUILTY VERDICT. Outside the town hall the condemned is led away in "
                                                "chains between two guards, the crowd jeering, grey sky; faces "
                                                "visible.")),
    "card_verdict_innocent": ("card", TITLE, card("ACQUITTAL. The acquitted steps out of the town hall into warm "
                                                  "sunlight, family embracing them, neighbours applauding; faces "
                                                  "visible.")),
    "screen_ending_ruin": ("screen", TITLE, STYLE + "the end screen of a dynasty RUINED by debt: an emptied workshop, "
                           "creditors carrying out the furniture and tools, a blank wooden shop sign (no lettering) "
                           "broken on the floor, grey cold light through the door. Absolutely no words or letters "
                           "anywhere." + SCREEN),
    "screen_ending_retire": ("screen", TITLE, STYLE + "the end screen of a dynasty that RETIRES in peace: an old "
                             "couple sitting by a warm fireside, the account ledger closed on the table, the town at "
                             "dusk through the window, a sleeping dog. No banners, no signs, no scrolls with writing: "
                             "absolutely no words or letters anywhere." + SCREEN),
    "screen_new_game": ("screen", TITLE, STYLE + "the background of the NEW GAME screen: a scribe's oak desk seen from "
                        "above at an angle, a blank parchment family charter, a quill and inkpot, sealing wax and a "
                        "seal, a candle, a few coins." + SCREEN),
    # duelo (docs/gdd/04e_combate.md §4e.8; carta de resultado y carta de reto): assets/art/ui/illustrations/duel/
    "duel_victory": ("duel", TITLE, card("DUEL WON. In the town square at dawn, a victorious duellist lowers his sword "
                                         "and offers a hand to the kneeling opponent, townsfolk cheering at the "
                                         "edges; faces lit and visible.")),
    "duel_defeat": ("duel", TITLE, card("DUEL LOST. In the town square at dawn, a duellist on one knee clutches a "
                                        "bleeding arm, his sword on the cobbles, the rival standing over him in warm "
                                        "dawn light, every figure fully lit with visible faces and clothes (no dark "
                                        "silhouettes), onlookers murmuring.")),
    "duel_draw": ("duel", TITLE, card("DUEL DRAWN. In the town square at dawn, two exhausted duellists stand apart, "
                                      "swords lowered, breathing hard, a judge raising both hands between them; "
                                      "faces lit and visible.")),
    "duel_challenge": ("duel", TITLE, card("CHALLENGE TO A DUEL. In a tavern, a man throws a leather gauntlet onto "
                                           "the table in front of his rival, who stands up, drinkers turning to "
                                           "look; faces lit and visible.")),
    # asentamientos de Valldaura (docs/gdd/09b_region.md §9b.3): su página de ciudad, assets/art/illustrations/
    "city_villa": ("city", TITLE, card("VILARRASA, a modest village strung along one main street on a flat plain: "
                                       "timber-framed houses, a smithy with smoke, a carpenter's yard and a small "
                                       "stone town hall, wheat fields around.")),
    "city_capital": ("city", TITLE, card("BELLCAIRE, the regional capital at the crossing of the royal road and the "
                                         "river: a busy market square with stalls, rich merchant houses, a cathedral "
                                         "under scaffolding, town walls and a stone bridge.")),
    "city_port": ("city", TITLE, card("PORTVELL, a river port: wooden quays on the wide river Daura, flat barges "
                                      "loaded with timber and barrels, a cooper's workshop, boatmen with poles, "
                                      "riverside houses.")),
    "city_quarry": ("city", TITLE, card("PEÑARROJA, a mining and quarry town of grey stone houses at the foot of a "
                                        "mountain of red rock: a mine entrance with a cart track, a stone quarry with "
                                        "cut blocks, charcoal smoke, a small baron's tower.")),
    "city_hamlet": ("city", TITLE, card("VILABLAT, a tiny farming hamlet among golden wheat fields: a few farmhouses, "
                                        "a windmill or watermill, a bakery oven, sheep in a pen, a dirt road.")),
    "city_abbey": ("city", TITLE, card("MONTSACRE, a walled abbey high on a mountain slope: a stone church with a "
                                       "bell tower, a cloister under construction with scaffolding, herb gardens, "
                                       "monks in brown habits, a path up from the forest.")),
    # pantallas (960×540)
    "screen_loading_1": ("screen", TITLE, STYLE + "a loading screen illustration: a guild master's desk seen from above "
                         "at an angle, an open ledger, a quill and inkpot, a candle, stacks of coins and a hand-drawn "
                         "map of the town." + SCREEN),
    "screen_loading_2": ("screen", TITLE, STYLE + "a loading screen illustration: the town's main road at sunset, a "
                         "merchant's cart arriving at the gate, long shadows, birds." + SCREEN),
    "screen_saves": ("screen", TITLE, STYLE + "the background of the saved-games menu: a quiet guild archive, tall "
                     "shelves of ledgers and rolled charters, a long oak table, warm candlelight, dark and cosy."
                     + SCREEN),
    "screen_ending_victory": ("screen", TITLE, STYLE + "the end screen of a triumphant dynasty: a great hall with the "
                              "family banners, a grand painted portrait of the founder, golden light through tall "
                              "windows with the town below at sunset, laurel garlands, a chest of gold." + SCREEN),
    "screen_ending_extinction": ("screen", TITLE, STYLE + "the end screen of an extinct dynasty: a quiet churchyard at "
                                 "dusk, the family crypt with a broken coat of arms, a single candle burning out, "
                                 "falling leaves, cold blue light." + SCREEN),
    "screen_title_night": ("screen", os.path.join(PILOT, "titulo", "crudo", "titulo_noche_v1.png"),
                           "Keep this exact image, same town, composition and pixel art, but move the crescent moon to "
                           "the upper-left corner of the sky, so the upper-central third of the sky is empty of moon "
                           "and has only a few small stars. No text, no logo."),
}
# Del piloto, sin generar de nuevo.
FROM_PILOT = {"event_war": ("event", os.path.join(PILOT, "eventos", "crudo", "guerra_v1.png")),
              "event_festival": ("event", os.path.join(PILOT, "eventos", "crudo", "fiesta_v1.png")),
              "screen_title_dawn": ("screen", TITLE)}


def raw(pid):
    if pid in FROM_PILOT:
        return FROM_PILOT[pid][1]
    return os.path.join(P, "crudo", pid + ".png")


def gen(pid):
    kind, ref, prompt = PIECES[pid]
    if ref in PIECES:
        if not os.path.exists(raw(ref)):
            gen(ref)
        ref = raw(ref)
    if os.path.exists(raw(pid)):
        return
    cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "ilustraciones",
           "--aspect", "16:9", "--name", pid, "--ref", ref, "--prompt", prompt]
    if subprocess.run(cmd, cwd=ROOT).returncode:
        sys.exit(1)


def i2p_palette(src, pid, colors):
    dst = os.path.join(P, "i2p", pid + "_i2p.png")
    if not os.path.exists(dst):
        import fal_piloto
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fal_piloto.pixel(SimpleNamespace(piece="ilustraciones", src=src, dst=dst, colors=colors, scale=0, palette="",
                                         transparent=False))
    nat = Image.open(dst).convert("RGB")
    return nat.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def reduce(im, size, pal):
    return im.convert("RGB").resize(size, Image.BOX).quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")


def proc(pid):
    kind = PIECES[pid][0] if pid in PIECES else FROM_PILOT[pid][0]
    src = raw(pid)
    if not os.path.exists(src):
        print("falta", pid)
        return
    im = Image.open(src)
    os.makedirs(OUT, exist_ok=True)
    if kind == "screen":
        pal = i2p_palette(src, pid, 48)
        small = reduce(im, (480, 270), pal)
        small.resize((960, 540), Image.NEAREST).save(os.path.join(OUT, pid + ".png"))
        if pid.startswith("screen_title"):  # vista previa con el logotipo del kit (no es el asset)
            prev = small.convert("RGBA")
            logo = Image.open(LOGO).convert("RGBA")
            prev.alpha_composite(logo, ((480 - logo.width) // 2, 36))
            os.makedirs(os.path.join(P, "vista"), exist_ok=True)
            prev.resize((960, 540), Image.NEAREST).save(os.path.join(P, "vista", pid + "_con_logo.png"))
    elif kind == "duel":  # la ruta que ya tenía el inventario (ill_duel_result): ui/illustrations/duel/<nombre>
        pal = i2p_palette(src, pid, 32)
        d = os.path.join(ROOT, "assets", "art", "ui", "illustrations", "duel")
        os.makedirs(d, exist_ok=True)
        name = pid[len("duel_"):]
        reduce(im, (240, 135), pal).save(os.path.join(d, name + ".png"))
        reduce(im, (192, 108), pal).save(os.path.join(d, name + "_192.png"))
    else:
        pal = i2p_palette(src, pid, 32)
        reduce(im, (240, 135), pal).save(os.path.join(OUT, pid + ".png"))
        if kind in ("event", "season"):
            reduce(im, (192, 108), pal).save(os.path.join(OUT, pid + "_192.png"))
    print("ok", pid)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["gen", "proc", "lista"])
    ap.add_argument("--solo", default="")
    a = ap.parse_args()
    ids = [x for x in a.solo.split(",") if x]
    if a.cmd == "lista":
        for k in list(PIECES) + list(FROM_PILOT):
            print(k)
    elif a.cmd == "gen":
        for pid in ids or list(PIECES):
            gen(pid)
    else:
        for pid in ids or (list(PIECES) + list(FROM_PILOT)):
            proc(pid)


if __name__ == "__main__":
    main()
