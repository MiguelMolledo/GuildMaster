#!/usr/bin/env python3
"""Retratos de GuildMaster con fal (producción 2026-11-03): reparto de tipos de personaje, generación por rejillas 2×2
con nano-banana-2/edit (una sola referencia: la rejilla buena del piloto) y, por cada rejilla, su mapa de regiones
(pelo, piel, ropa principal, ropa secundaria) pedido como /edit sobre la propia rejilla.

Ids: <grupo>_<etapa>_<m|f>[_<n>] con grupo artisan | patron | scholar | rogue (familia del jugador por clase),
worker (empleados), townsfolk (vecinos), rival (cabeza y pareja de las familias rivales) y los cargos y únicos por su
id (mayor, judge, priest, constable, tax_collector, market_inspector, councillor, captain, dignitary, foreigner).
Etapas (data/family.json): child 0-7, youth 8-15, adult 16-44, mature 45-54, elder 55+.

Uso: FAL_TANDA=produccion python3 tools/art/fal_retratos.py gen [--solo g01,g02] [--sin-mascara]
     python3 tools/art/fal_retratos.py lista
"""
import argparse
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "art", "fal_produccion", "retratos", "crudo")
REF = os.path.join(ROOT, "assets", "art", "fal_piloto", "retratos", "crudo", "grid_nano2_v1.png")

# Ropa: la principal en rojo oscuro y la secundaria en dorado mostaza (colores por defecto de la familia; el shader
# de identidad las cambia). Los cargos y únicos llevan su ropa propia (solo se marcan pelo y piel).
ARTISAN = "a craftsman's family: plain linen shirt and wool tunic, adults with a leather work apron"
PATRON = "a prosperous farmer-innkeeper family: good wool tunic or kirtle, felt cap or linen wimple, no apron"
SCHOLAR = "a learned family of physicians and scribes: long scholar's robe with a hood, linen coif, ink-stained fingers"
ROGUE = "a family of rogues and fences: hooded short cloak over a leather jerkin, sly watchful look"
TOWN = "a humble townsfolk neighbour: plain worn wool clothes"
WORKER = "a hired workman or workwoman: rolled sleeves, plain work clothes, leather apron"
RIVAL = "head or spouse of a RIVAL dynasty, proud and well dressed for their station"

GRIDS = {
    "g01": [("artisan_child_m", ARTISAN, "boy of 5, round face, messy brown hair"),
            ("artisan_child_f", ARTISAN, "girl of 5, chubby cheeks, brown hair with a short braid"),
            ("artisan_youth_m", ARTISAN, "apprentice boy of 13, freckles, short brown hair"),
            ("artisan_mature_m", ARTISAN, "man of 50, greying brown hair and short beard, strong and tired")],
    "g02": [("artisan_mature_f", ARTISAN, "woman of 50, brown hair with grey streaks in a bun, kind lines"),
            ("artisan_elder_m", ARTISAN, "old man of 68, bald crown with white hair at the sides, white moustache"),
            ("artisan_elder_f", ARTISAN, "old woman of 68, white hair under a small linen cap, wrinkles"),
            ("worker_adult_f", WORKER, "woman of 28, dark blond hair tied back, determined")],
    "g03": [("patron_child_m", PATRON, "boy of 6, well fed, short fair hair"),
            ("patron_child_f", PATRON, "girl of 6, fair hair in two braids"),
            ("patron_youth_m", PATRON, "boy of 14, curly light-brown hair, confident"),
            ("patron_youth_f", PATRON, "girl of 14, light-brown hair under a little cap")],
    "g04": [("patron_adult_m", PATRON, "man of 32, broad face, fair hair, trimmed fair beard, felt cap"),
            ("patron_adult_f", PATRON, "woman of 30, fair hair under a linen wimple, rosy cheeks"),
            ("patron_mature_m", PATRON, "man of 50, portly, receding fair-grey hair, double chin"),
            ("patron_mature_f", PATRON, "woman of 50, wimple, greying fair hair, shrewd")],
    "g05": [("patron_elder_m", PATRON, "old man of 70, white hair, white stubble, ruddy nose"),
            ("patron_elder_f", PATRON, "old woman of 70, white hair under a wimple, warm smile"),
            ("scholar_child_m", SCHOLAR, "boy of 6, neat dark hair, serious"),
            ("scholar_child_f", SCHOLAR, "girl of 6, dark hair with a fringe, curious")],
    "g06": [("scholar_youth_m", SCHOLAR, "boy of 14, thin, dark hair, a quill behind his ear"),
            ("scholar_youth_f", SCHOLAR, "girl of 14, dark hair in a plait, thoughtful"),
            ("scholar_adult_m", SCHOLAR, "man of 33, thin face, short black beard, linen coif"),
            ("scholar_adult_f", SCHOLAR, "woman of 31, black hair under a white coif, calm and clever")],
    "g07": [("scholar_mature_m", SCHOLAR, "man of 52, grey goatee, deep-set eyes, hood up behind the head"),
            ("scholar_mature_f", SCHOLAR, "woman of 50, grey-black hair in a coif, stern"),
            ("scholar_elder_m", SCHOLAR, "old man of 72, long white beard, bushy eyebrows, round spectacles"),
            ("scholar_elder_f", SCHOLAR, "old woman of 70, white hair, thin, sharp eyes")],
    "g08": [("rogue_child_m", ROGUE, "boy of 6, dirty face, unkempt red-brown hair"),
            ("rogue_child_f", ROGUE, "girl of 6, tangled red-brown hair, cheeky grin"),
            ("rogue_youth_m", ROGUE, "boy of 14, lean, red-brown hair, smirk"),
            ("rogue_youth_f", ROGUE, "girl of 14, red-brown hair, hood down, quick eyes")],
    "g09": [("rogue_adult_m", ROGUE, "man of 32, stubble, scar through an eyebrow, red-brown hair"),
            ("rogue_adult_f", ROGUE, "woman of 30, red-brown hair, narrow eyes, faint smile"),
            ("rogue_mature_m", ROGUE, "man of 50, broken nose, grizzled red-grey beard"),
            ("rogue_mature_f", ROGUE, "woman of 50, red-grey hair, hard face")],
    "g10": [("rogue_elder_m", ROGUE, "old man of 70, eye patch, white stubble"),
            ("rogue_elder_f", ROGUE, "old woman of 70, white hair, crooked knowing smile"),
            ("worker_mature_m", WORKER, "man of 50, bald, thick grey moustache"),
            ("worker_mature_f", WORKER, "woman of 50, greying hair tied in a kerchief, strong arms")],
    "g11": [("townsfolk_child_m", TOWN, "boy of 6, bowl-cut brown hair"),
            ("townsfolk_child_f", TOWN, "girl of 6, black hair, shy"),
            ("townsfolk_youth_m", TOWN, "boy of 14, sandy hair, gap-toothed grin"),
            ("townsfolk_youth_f", TOWN, "girl of 14, auburn hair in a kerchief")],
    "g12": [("townsfolk_adult_m_1", TOWN, "man of 30, long dark hair, thin beard"),
            ("townsfolk_adult_m_2", TOWN, "man of 35, blond, clean shaven, big ears"),
            ("townsfolk_adult_f_1", TOWN, "woman of 28, black curly hair, olive skin"),
            ("townsfolk_adult_f_2", TOWN, "woman of 34, red hair, pale freckled skin")],
    "g13": [("townsfolk_mature_m_1", TOWN, "man of 50, dark skin, short grey beard"),
            ("townsfolk_mature_m_2", TOWN, "man of 48, balding, brown moustache"),
            ("townsfolk_mature_f_1", TOWN, "woman of 50, plump, greying brown hair in a bun"),
            ("townsfolk_mature_f_2", TOWN, "woman of 47, thin, dark hair under a headscarf")],
    "g14": [("townsfolk_elder_m_2", TOWN, "old man of 72, white wispy hair, toothless smile"),
            ("townsfolk_elder_f_2", TOWN, "old woman of 70, dark skin, white hair in a headscarf"),
            ("foreigner", "a FOREIGN travelling merchant (own clothes, not family colours): striped turban-like "
                          "travel hood, embroidered caftan", "man of 40, dark beard, olive skin"),
            ("captain", "the town guard CAPTAIN who gives contracts (own clothes): mail coif and a surcoat",
             "man of 45, square jaw, short grey hair")],
    "g15": [("rival_adult_m_2", RIVAL + " (rich merchant)", "man of 45, portly, fur collar, oiled black hair"),
            ("rival_adult_f_2", RIVAL + " (rich merchant's wife)", "woman of 42, jewelled hairnet, cold eyes"),
            ("rival_adult_m_3", RIVAL + " (banker)", "man of 50, thin, grey pointed beard, sly"),
            ("rival_adult_f_3", RIVAL + " (banker's wife)", "woman of 45, grey-blond hair, pearl necklace")],
    "g16": [("rival_adult_m_4", RIVAL + " (crime boss)", "man of 40, shaved head, scarred cheek, gold earring"),
            ("rival_adult_f_4", RIVAL + " (crime boss's wife)", "woman of 38, black hair, sharp smile"),
            ("rival_adult_m_5", RIVAL + " (master mason)", "man of 48, huge build, brown beard, dusty"),
            ("rival_adult_f_5", RIVAL + " (master mason's wife)", "woman of 44, brown hair in a braid crown")],
    "g17": [("mayor", "the MAYOR (own clothes): fur-trimmed blue robe and a golden chain of office",
             "man of 55, grey hair, double chin, self-important"),
            ("judge", "the JUDGE (own clothes): black robe and white coif", "man of 60, severe, white eyebrows"),
            ("priest", "the parish PRIEST (own clothes): black cassock with a white collar band and a wooden "
                       "cross, tonsured", "man of 50, kindly, round face"),
            ("constable", "the town CONSTABLE (own clothes): padded gambeson and a steel kettle helmet",
             "man of 38, broken nose, brown stubble")],
    "g18": [("tax_collector", "the TAX COLLECTOR (own clothes): dark green doublet and a ledger",
             "man of 45, thin, beady eyes, pinched mouth"),
            ("market_inspector", "the MARKET INSPECTOR (own clothes): brown coat with a brass badge and a "
                                 "measuring rod", "woman of 45, sharp nose, grey hair under a coif"),
            ("councillor", "a town COUNCILLOR (own clothes): burgundy houppelande with a fur collar",
             "man of 50, neat white beard"),
            ("dignitary", "a visiting noble DIGNITARY (own clothes): purple velvet and a gold circlet",
             "woman of 40, regal, auburn hair")],
}

# Los 8 del piloto (assets/art/fal_piloto/retratos/), con su id de producción.
PILOT = {"grid_nano2_v1": ["artisan_adult_m", "artisan_adult_f", "townsfolk_elder_m_1", "rival_adult_m_1"],
         "grid2_nano2_v1": ["artisan_youth_f", "worker_adult_m", "townsfolk_elder_f_1", "rival_adult_f_1"]}

# Cargos y únicos: solo se marcan pelo y piel (su ropa no lleva los colores de una familia).
OWN_CLOTHES = {"foreigner", "captain", "mayor", "judge", "priest", "constable", "tax_collector", "market_inspector",
               "councillor", "dignitary"}

POS = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]


def prompt(cells):
    lines = []
    for pos, (pid, who, look) in zip(POS, cells):
        family = pid not in OWN_CLOTHES
        cloth = (" Main garment deep red, secondary cloth (collar, trim, scarf, hood lining, vest or headscarf) "
                 "mustard gold." if family else "")
        lines.append(f"{pos}: {look}; {who}.{cloth}")
    return ("Using the attached 2x2 grid of portraits as the exact style, framing, background, light and pixel-size "
            "reference, create ONE new square image with a 2x2 grid of four NEW portraits of the same set: 16-bit "
            "pixel art, head and shoulders, three-quarter view facing slightly right, the eyes at the same height in "
            "every cell, the same plain very dark brown background, the same chunky pixel size. Hair, skin and "
            "clothes must be clearly separate areas with a dark outline; the neck is visible. " + " ".join(lines) +
            " 14th-century Central Europe. No text, no borders, no grid lines.")


MASK = ("Turn this exact image into a flat colour segmentation map. Keep every shape, outline and position EXACTLY "
        "where it is (same framing, same pixels), only replace colours with flat fills, no shading, no outlines: all "
        "hair, beards, moustaches and eyebrows = pure magenta #FF00FF; all visible skin including face, nose, ears, "
        "neck, hands and lips = pure yellow #FFFF00; the main garment (tunic, dress, robe or coat) = pure cyan "
        "#00FFFF; secondary cloth (trim, collar, scarf, headscarf, hood, vest, shirt) = pure green #00FF00; "
        "everything else (background, eyes, leather apron, straps, buckles, hats, helmets, jewellery) = pure black "
        "#000000.")


def run(*args):
    cmd = [sys.executable, os.path.join(ROOT, "tools", "art", "fal_piloto.py"), "gen", "--model", "nano2",
           "--piece", "retratos", "--aspect", "1:1"] + list(args)
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode:
        sys.exit(r.returncode)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["gen", "lista", "mascaras_piloto", "mascara_celda"])
    ap.add_argument("--solo", default="")
    ap.add_argument("--sin-mascara", action="store_true")
    a = ap.parse_args()
    if a.cmd == "lista":
        ids = [c[0] for g in GRIDS.values() for c in g] + [i for v in PILOT.values() for i in v]
        print(len(ids), "retratos")
        for i in sorted(ids):
            print(" ", i)
        return
    if a.cmd == "mascaras_piloto":
        src = os.path.join(ROOT, "assets", "art", "fal_piloto", "retratos", "crudo", "grid2_nano2_v1.png")
        if not os.path.exists(os.path.join(OUT, "grid2_nano2_v1_mascara.png")):
            run("--name", "grid2_nano2_v1_mascara", "--ref", src, "--prompt", MASK)
        return
    if a.cmd == "mascara_celda":  # repite el mapa de una sola celda (cuando el de la rejilla sale mal)
        from PIL import Image
        for pid in [x for x in a.solo.split(",") if x]:
            g, i = next((g, k) for g, cells in GRIDS.items() for k, c in enumerate(cells) if c[0] == pid)
            im = Image.open(os.path.join(OUT, g + ".png")).convert("RGB")
            w = im.width // 2
            cell = im.crop(((i % 2) * w, (i // 2) * w, (i % 2 + 1) * w, (i // 2 + 1) * w)).resize((1024, 1024),
                                                                                                Image.NEAREST)
            src = os.path.join(OUT, pid + "_celda.png")
            cell.save(src)
            if not os.path.exists(os.path.join(OUT, pid + "_mascara.png")):
                run("--name", pid + "_mascara", "--ref", src, "--prompt", MASK + " Do not add or remove anything: "
                    "if there is no beard there is no magenta on the chin; a vest or scarf over the main garment is "
                    "green.")
        return
    want = [g for g in a.solo.split(",") if g] or list(GRIDS)
    for g in want:
        if not os.path.exists(os.path.join(OUT, g + ".png")):
            run("--name", g, "--ref", REF, "--prompt", prompt(GRIDS[g]))
        if not a.sin_mascara and not os.path.exists(os.path.join(OUT, g + "_mascara.png")):
            run("--name", g + "_mascara", "--ref", os.path.join(OUT, g + ".png"), "--prompt", MASK)


if __name__ == "__main__":
    main()
