#!/usr/bin/env python3
"""Pool grande de retratos (2026-11-03): sexo × franja de edad × tipo social, ~6 caras por combinación, para que las
familias y los vecinos cambien entre partidas. Formato y reglas: assets/art/portraits/README.md (index.json v1).

Mismo método que tools/art/fal_retratos.py: rejillas 2×2 con nano-banana-2/edit (una sola referencia: la rejilla del
piloto), un mapa de regiones por /edit de cada rejilla, y tools/art/fal_retratos_proc.py build() para pixelar
(image2pixel), alinear, votar regiones, quitar el fondo y codificar los colores clave de GDD 4.10.9.

Uso:
  python3 tools/art/fal_pool.py lista                      # combinaciones y caras
  FAL_TANDA=pool python3 tools/art/fal_pool.py gen [--hilos 4] [--solo p001,p002]
  FAL_TANDA=pool python3 tools/art/fal_pool.py proc [--hilos 6]
  FAL_TANDA=pool python3 tools/art/fal_pool.py remascara --solo <id>,<id>   # repite el mapa de una celda
  python3 tools/art/fal_pool.py indice                     # index.json + copia de los 80 de la primera tanda
"""
import argparse
import json
import os
import random
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
P = os.path.join(ROOT, "assets", "art", "fal_produccion", "pool")
OUT = os.path.join(ROOT, "assets", "art", "portraits")
REF = os.path.join(ROOT, "assets", "art", "fal_piloto", "retratos", "crudo", "grid_nano2_v1.png")

AGES = {"child": (6, 11), "youth": (12, 17), "adult": (18, 44), "mature": (45, 59), "elder": (60, None)}
TYPES = ["artisan", "commoner", "merchant", "noble", "clergy", "guard", "scholar", "farmer", "rogue"]
ALL = list(AGES)
VALID = {  # tipo -> sexo -> franjas con retrato propio
    "artisan": {"m": ALL, "f": ALL}, "commoner": {"m": ALL, "f": ALL}, "merchant": {"m": ALL, "f": ALL},
    "noble": {"m": ALL, "f": ALL}, "farmer": {"m": ALL, "f": ALL}, "rogue": {"m": ALL, "f": ALL},
    "clergy": {"m": ALL[1:], "f": ALL[1:]}, "scholar": {"m": ALL[1:], "f": ALL[1:]},
    "guard": {"m": ["youth", "adult", "mature"], "f": ["adult", "mature"]},
}
# Lo que no tiene retrato propio (README: fallback[tipo][edad]); el sexo que falte usa el fallback igual.
FALLBACK = {"clergy": {"child": "commoner"}, "scholar": {"child": "merchant"},
            "guard": {"child": "commoner", "youth": "commoner", "elder": "commoner"}}
FACES = 6
FIXED_CLOTHES = {"clergy", "guard"}  # su ropa no lleva los colores de la familia: solo pelo y piel

AGE_TXT = {"child": "a child of about 8", "youth": "a teenager of about 15", "adult": "an adult of about 30",
           "mature": "a person of about 52", "elder": "an elderly person of about 70"}
SEX_TXT = {"m": "male", "f": "female"}
TYPE_TXT = {
    "artisan": "a craftsperson: linen shirt and wool tunic{apron}",
    "commoner": "a humble townsfolk neighbour: plain, worn and patched wool clothes",
    "merchant": "a wealthy merchant: fine wool and velvet with fur trim, a ring or a purse",
    "noble": "a noble: rich embroidered velvet, a fur-lined mantle and a jewelled clasp",
    "clergy": "{clergy}",
    "guard": "{guard}",
    "scholar": "a learned physician or scribe: long scholar's robe with a hood",
    "farmer": "a farmer or peasant: rough linen and wool, sunburnt, work-worn",
    "rogue": "a rogue or street thief: hooded short cloak over a leather jerkin",
}

# Rasgos por sexo; cada cara toma una combinación distinta (semilla fija por combinación).
HAIR_M = ["short cropped hair", "curly hair", "long hair tied back", "a bowl cut", "tousled messy hair",
          "wavy shoulder-length hair", "short hair with a side parting", "thick spiky hair"]
HAIR_M_OLD = ["a receding hairline", "a bald crown with hair at the sides", "a shaved head", "thinning hair"]
HAIR_F = ["a long braid over the shoulder", "a neat bun", "loose long wavy hair", "two braids", "curly hair tied up",
          "hair in a low knot", "short-ish curly hair", "hair pinned in coils over the ears"]
BEARD = ["clean-shaven", "stubble", "a short trimmed beard", "a full thick beard", "a moustache", "a goatee",
         "sideburns and a moustache"]
BEARD_OLD = ["a long beard", "a white moustache", "a full grey beard"]
HAIR_COL = ["black", "dark brown", "brown", "auburn", "red", "blond", "light brown", "sandy"]
HAIR_COL_OLD = {"mature": ["greying dark", "salt-and-pepper", "greying brown", "grey-blond"],
                "elder": ["white", "grey", "silver", "snow-white"]}
SKIN = ["fair skin", "pale freckled skin", "olive skin", "tanned skin", "light brown skin", "dark brown skin",
        "ruddy skin", "deep dark skin"]
FEATURE = ["a scar on the cheek", "freckles", "a broken nose", "a mole on the cheek", "thick eyebrows",
           "rosy cheeks", "a gap-toothed grin", "a dimpled chin", "high cheekbones", "a hooked nose",
           "deep-set eyes", "big ears"]
FEATURE_OLD = ["deep wrinkles", "crow's feet", "sagging jowls", "a wart on the nose"]
EXPR = ["smiling warmly", "serious", "tired", "proud", "suspicious", "kind", "stern", "amused", "worried",
        "thoughtful", "cheeky", "calm"]
BUILD = ["thin face", "round face", "square jaw", "long face", "chubby face", "angular face"]

HEAD = {
    "artisan": ["", "", "a felt cap", "a leather headband", "a linen coif", "a kerchief"],
    "commoner": ["", "", "a wool hood", "a felt cap", "a linen coif", "a straw hat"],
    "merchant": ["", "a velvet beret", "a fur hat", "a chaperon hood-hat", "", "a jewelled hairnet"],
    "noble": ["", "a gold circlet", "a velvet hat with a feather", "", "a jewelled hairnet", "a thin coronet"],
    "scholar": ["a linen coif", "", "a scholar's cap", "the hood up", "", "a skullcap"],
    "farmer": ["a straw hat", "", "a wool hood", "a kerchief", "", "a felt cap"],
    "rogue": ["the hood up", "the hood down", "a bandana", "", "the hood up", ""],
    "clergy": ["", "", "", "", "", ""],
    "guard": ["", "", "", "", "", ""],
}
HEAD_F = {"artisan": ["", "a headscarf", "a linen wimple", "a kerchief", "", "a hairnet"],
          "commoner": ["a headscarf", "", "a linen wimple", "a kerchief", "a hood", ""],
          "farmer": ["a headscarf", "a straw hat", "", "a kerchief", "a linen wimple", ""]}
GUARD_M = ["a padded gambeson and a steel kettle helmet", "a mail coif and a town-livery surcoat",
           "a leather jerkin and a simple steel cap", "a mail shirt and a nasal helmet",
           "a quilted gambeson, bare-headed", "a brigandine and an open-faced helmet"]
GUARD_F = ["a padded gambeson, bare-headed with braided hair", "a mail coif and a livery surcoat",
           "a leather jerkin and a steel cap", "a quilted gambeson and a hood"]
CLERGY_M = ["a black cassock with a white collar band, tonsured", "a brown monk's habit with the hood down, tonsured",
            "a black cassock and a wooden cross", "a white Dominican habit with a black cape",
            "a grey friar's habit with a rope belt", "a parish priest's black cassock and a stole"]
CLERGY_F = ["a black nun's habit with a white wimple and black veil", "a white habit and white veil",
            "a brown habit with a white wimple", "a grey habit and a simple veil",
            "a black habit and a wooden cross", "a novice's white veil and grey habit"]
TAGS = {"beard": "beard", "moustache": "moustache", "goatee": "beard", "stubble": "stubble",
        "bald": "bald", "shaved": "bald", "receding": "bald", "spectacles": "glasses", "a scar": "scar",
        "eye patch": "eyepatch", "freckle": "freckles", "hood": "hood", "headscarf": "headscarf", "kerchief": "headscarf",
        "wimple": "wimple", "veil": "veil", "coif": "coif", "helmet": "helmet", "cap": "hat", "hat": "hat",
        "beret": "hat", "circlet": "jewellery", "coronet": "jewellery", "hairnet": "jewellery", "apron": "apron",
        "braid": "braids", "curly": "curly", "long hair": "long_hair", "loose long": "long_hair",
        "shoulder-length": "long_hair", "long beard": "beard", "full grey beard": "beard", "tonsure": "tonsure", "bandana": "headscarf"}


def combos():
    out = []
    for t in TYPES:
        for sex in ("m", "f"):
            for age in VALID[t][sex]:
                out.append((sex, age, t))
    return out


def faces(sex, age, t):
    rnd = random.Random(f"{sex}_{age}_{t}")
    old = age in ("mature", "elder")
    res = []
    used = set()
    for n in range(1, FACES + 1):
        for _ in range(50):
            parts = []
            if sex == "m":
                pool = HAIR_M + (HAIR_M_OLD if old else [])
                if age in ("child", "youth"):  # el pelo largo hace que un chico se lea como chica
                    pool = [h for h in pool if "long" not in h and "shoulder" not in h]
                hair = rnd.choice(pool)
            else:
                hair = rnd.choice(HAIR_F)
            col = rnd.choice(HAIR_COL_OLD.get(age, HAIR_COL)) if old and rnd.random() < 0.8 or age == "elder" \
                else rnd.choice(HAIR_COL)
            if t == "clergy" and sex == "m":
                hair = "a tonsure"
            parts.append(f"{col} hair, {hair}" if "bald" not in hair and "shaved" not in hair else hair)
            if sex == "m" and age in ("adult", "mature", "elder"):
                parts.append(rnd.choice(BEARD + (BEARD_OLD if age == "elder" else [])))
            parts.append(rnd.choice(SKIN))
            parts.append(rnd.choice(BUILD))
            feat = [rnd.choice(FEATURE + (FEATURE_OLD if old else []))]
            if t in ("scholar", "merchant") and old and rnd.random() < 0.4:
                feat.append("round spectacles")
            if t in ("rogue", "guard") and sex == "m" and age != "youth" and rnd.random() < 0.2:
                feat.append("an eye patch")
            parts += feat
            parts.append(rnd.choice(EXPR))
            heads = (HEAD_F.get(t) if sex == "f" else None) or HEAD[t]
            head = heads[(n - 1) % len(heads)]
            if head:
                parts.append("wearing " + head)
            key = (hair, col, parts[1] if sex == "m" else head, head)
            if key not in used:
                used.add(key)
                break
        clothes = TYPE_TXT[t].format(
            apron=", leather work apron" if age in ("adult", "mature", "elder") and n % 2 else "",
            clergy=(CLERGY_M if sex == "m" else CLERGY_F)[(n - 1) % 6] if age != "youth" else
            ("a novice's plain brown habit" if sex == "m" else "a novice's white veil and grey habit"),
            guard=(GUARD_M if sex == "m" else GUARD_F)[(n - 1) % (6 if sex == "m" else 4)] if age != "youth" else
            "a young recruit in a padded gambeson, bare-headed")
        desc = ", ".join(parts)
        tags = sorted({v for k, v in TAGS.items() if k in (desc + " " + clothes).lower()})
        res.append({"id": f"{sex}_{age}_{t}_{n:02d}", "sex": sex, "age": age, "type": t, "look": desc,
                    "clothes": clothes, "traits": tags})
    return res


def roster():
    return [f for c in combos() for f in faces(*c)]


def grids():
    r = roster()
    return {f"p{i // 4 + 1:03d}": r[i:i + 4] for i in range(0, len(r), 4)}


POS = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]


def prompt(cells):
    lines = []
    for pos, c in zip(POS, cells):
        family = c["type"] not in FIXED_CLOTHES
        cloth = (" Main garment deep red, secondary cloth (collar, trim, scarf, hood lining, vest or headscarf) "
                 "mustard gold." if family else " Their clothes keep their own colours.")
        lines.append(f"{pos}: {SEX_TXT[c['sex']]}, {AGE_TXT[c['age']]}, {c['clothes']}; {c['look']}.{cloth}")
    if len(cells) < 4:
        lines.append("The remaining cells are plain dark background.")
    return ("Using the attached 2x2 grid of portraits as the exact style, framing, background, light and pixel-size "
            "reference, create ONE new square image with a 2x2 grid of four NEW, clearly different people of the "
            "same set: 16-bit pixel art, head and shoulders, three-quarter view facing slightly right, the eyes at "
            "the same height in every cell, the same plain very dark brown background, the same chunky pixel size. "
            "Hair, skin and clothes are clearly separate areas with a dark outline; the neck is visible. "
            + " ".join(lines) + " 14th-century Central Europe. No text, no borders, no grid lines.")


def run_gen(name, ref, text):
    cmd = [sys.executable, os.path.join(HERE, "fal_piloto.py"), "gen", "--model", "nano2", "--piece", "pool",
           "--aspect", "1:1", "--name", name, "--ref", ref, "--prompt", text]
    for attempt in range(3):
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if r.returncode == 0:
            return True
        if "TOPE" in r.stdout:
            print(r.stdout.strip())
            return False
        print(f"  {name}: intento {attempt + 1} falló: {(r.stderr or r.stdout).strip().splitlines()[-1][:160]}")
    return False


def gen_grid(g, cells):
    import fal_retratos as fr
    raw = os.path.join(P, "crudo", g + ".png")
    ok = os.path.exists(raw) or run_gen(g, REF, prompt(cells))
    if ok and not os.path.exists(os.path.join(P, "crudo", g + "_mascara.png")):
        ok = run_gen(g + "_mascara", raw, fr.MASK)
    print(("ok " if ok else "FALLO ") + g, flush=True)
    return ok


def proc_cell(item):
    import fal_retratos_proc as frp
    g, k, c, cell, mask = item
    pid = c["id"]
    d = os.path.join(OUT, c["sex"], c["age"], c["type"])
    own_mask = os.path.join(P, "crudo", pid + "_mascara.png")
    if os.path.exists(own_mask):
        mask = Image.open(own_mask).convert("RGBA").resize((512, 512), Image.NEAREST)
    nat64 = frp.i2p_native(cell, os.path.join(P, "i2p", pid + "_s8.png"), 8, 32)
    n64, k64, c64 = frp.build(cell, mask, 8, 64, nat64, c["type"] in FIXED_CLOTHES)
    face, fmask = cell.crop(frp.FACE), mask.crop(frp.FACE)
    nat32 = frp.i2p_native(face, os.path.join(P, "i2p", pid + "_cara_s12.png"), 12, 24)
    n32, k32, c32 = frp.build(face, fmask, 12, 32, nat32, c["type"] in FIXED_CLOTHES)
    os.makedirs(d, exist_ok=True)
    k64.save(os.path.join(d, pid + ".png"))
    k32.save(os.path.join(d, pid + "_32.png"))
    os.makedirs(os.path.join(P, "natural"), exist_ok=True)
    n64.save(os.path.join(P, "natural", pid + ".png"))
    n32.save(os.path.join(P, "natural", pid + "_32.png"))
    return pid, c64


def proc(threads, only):
    import fal_retratos_proc as frp
    items = []
    for g, cells in grids().items():
        raw = os.path.join(P, "crudo", g + ".png")
        msk = os.path.join(P, "crudo", g + "_mascara.png")
        if not (os.path.exists(raw) and os.path.exists(msk)):
            continue
        for k, (c, cell, mask) in enumerate(zip(cells, frp.cells_of(raw), frp.cells_of(msk))):
            if only and c["id"] not in only and g not in only:
                continue
            items.append((g, k, c, cell, mask))
    os.makedirs(os.path.join(P, "i2p"), exist_ok=True)
    def safe(item):
        try:
            return proc_cell(item)
        except Exception as e:  # una celda que falla (red, fal) no para las demás; se repite con otro proc
            return item[2]["id"], f"ERROR {type(e).__name__}: {str(e)[:120]}"

    with ThreadPoolExecutor(threads) as ex:
        for pid, cnt in ex.map(safe, items):
            print(pid, cnt, flush=True)


def remask(ids):
    import fal_retratos as fr
    gr = grids()
    for pid in ids:
        g, k = next((g, i) for g, cells in gr.items() for i, c in enumerate(cells) if c["id"] == pid)
        im = Image.open(os.path.join(P, "crudo", g + ".png")).convert("RGB")
        w = im.width // 2
        cell = im.crop(((k % 2) * w, (k // 2) * w, (k % 2 + 1) * w, (k // 2 + 1) * w)).resize((1024, 1024),
                                                                                            Image.NEAREST)
        src = os.path.join(P, "crudo", pid + "_celda.png")
        cell.save(src)
        dst = os.path.join(P, "crudo", pid + "_mascara.png")
        if os.path.exists(dst):
            os.remove(dst)
        run_gen(pid + "_mascara", src, fr.MASK + " Do not add or remove anything: if there is no beard there is "
                "no magenta on the chin; a vest or scarf over the main garment is green.")
        for f in (pid + "_s8.png", pid + "_cara_s12.png"):
            pass  # el pixelado no depende del mapa: se reutiliza


# Los 80 de la primera tanda, con su tipo del pool (se copian con id nuevo, numerados después de los del pool).
OLD_TYPE = {"artisan": "artisan", "patron": "farmer", "scholar": "scholar", "rogue": "rogue", "worker": "artisan",
            "townsfolk": "commoner", "rival": "merchant"}
OLD_SPECIAL = {"mayor": ("m", "mature", "merchant"), "judge": ("m", "elder", "noble"),
               "priest": ("m", "mature", "clergy"), "constable": ("m", "adult", "guard"),
               "tax_collector": ("m", "adult", "merchant"), "market_inspector": ("f", "mature", "merchant"),
               "councillor": ("m", "mature", "merchant"), "captain": ("m", "mature", "guard"),
               "dignitary": ("f", "adult", "noble"), "foreigner": ("m", "adult", "merchant")}
OLD_AGE = {"child": "child", "youth": "youth", "adult": "adult", "mature": "mature", "elder": "elder"}


ZONES = {1: "hair", 2: "skin", 3: "primary", 4: "secondary"}


def zones_in(path):
    """Zonas codificadas de verdad en el PNG (alfa 254, región en el azul), en orden fijo."""
    im = Image.open(path).convert("RGBA")
    found = {round(b / 50) for r, g, b, a in im.getdata() if a == 254}
    return [ZONES[k] for k in sorted(ZONES) if k in found]


def index():
    import fal_retratos as fr
    entries = []
    seen = set()
    for c in roster():
        d = f"{c['sex']}/{c['age']}/{c['type']}"
        f = os.path.join(OUT, d, c["id"] + ".png")
        if not os.path.exists(f):
            continue
        rec = zones_in(f)
        entries.append({"id": c["id"], "sex": c["sex"], "age": c["age"], "type": c["type"],
                        "file": f"{d}/{c['id']}.png", "face": f"{d}/{c['id']}_32.png", "recolor": rec,
                        "traits": c["traits"]})
        seen.add(c["id"])
    # primera tanda
    counters = {}
    for e in entries:
        k = (e["sex"], e["age"], e["type"])
        counters[k] = max(counters.get(k, 0), int(e["id"].rsplit("_", 1)[1]))
    old_ids = [c[0] for g in fr.GRIDS.values() for c in g] + [i for v in fr.PILOT.values() for i in v]
    for oid in sorted(old_ids):
        if oid in OLD_SPECIAL:
            sex, age, t = OLD_SPECIAL[oid]
        else:
            g, st, sx = oid.split("_")[:3]
            sex, age, t = sx, OLD_AGE[st], OLD_TYPE[g]
            if g == "rival" and oid.endswith(("_4",)):
                t = "rogue"
        t = FALLBACK.get(t, {}).get(age, t)  # la misma regla que el README: sin retrato propio, su fallback
        k = (sex, age, t)
        counters[k] = counters.get(k, 0) + 1
        nid = f"{sex}_{age}_{t}_{counters[k]:02d}"
        d = f"{sex}/{age}/{t}"
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
        for suf in ("", "_32"):
            shutil.copy(os.path.join(OUT, oid + suf + ".png"), os.path.join(OUT, d, nid + suf + ".png"))
        rec = zones_in(os.path.join(OUT, d, nid + ".png"))
        entries.append({"id": nid, "sex": sex, "age": age, "type": t, "file": f"{d}/{nid}.png",
                        "face": f"{d}/{nid}_32.png", "recolor": rec, "traits": [], "from": oid})
    entries.sort(key=lambda e: e["id"])
    idx = {"version": 1, "sizes": {"bust": 64, "face": 32},
           "ages": {k: [a, b] for k, (a, b) in AGES.items()}, "types": TYPES, "fallback": FALLBACK,
           "regions": {"hair": 50, "skin": 100, "primary": 150, "secondary": 200}, "portraits": entries}
    with open(os.path.join(OUT, "index.json"), "w") as fh:
        json.dump(idx, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    # comprobación de la garantía del README
    count = {}
    for e in entries:
        count[(e["sex"], e["age"], e["type"])] = count.get((e["sex"], e["age"], e["type"]), 0) + 1
    holes = [(s, a, t) for t in TYPES for s in "mf" for a in AGES
             if count.get((s, a, t), 0) < 4 and a not in FALLBACK.get(t, {}) and a in VALID[t][s]]
    print(f"index.json: {len(entries)} retratos, {len(count)} combinaciones; por debajo de 4: {holes}")
    return entries


def qa(ids=None):
    """Mapas dudosos: en la ropa de familia (rojo y mostaza, pedidos así) qué parte quedó marcada como ropa."""
    import colorsys
    bad = []
    for c in roster():
        if ids and c["id"] not in ids:
            continue
        nat = os.path.join(P, "natural", c["id"] + ".png")
        key = os.path.join(OUT, c["sex"], c["age"], c["type"], c["id"] + ".png")
        if not (os.path.exists(nat) and os.path.exists(key)) or c["type"] in FIXED_CLOTHES:
            continue
        n, k = Image.open(nat).convert("RGBA").load(), Image.open(key).convert("RGBA").load()
        red = redok = mus = musok = hair = 0
        for y in range(35, 64):
            for x in range(64):
                r, g, b, a = n[x, y]
                if not a:
                    continue
                reg = round(k[x, y][2] / 50) if k[x, y][3] == 254 else 0
                h, s_, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                h *= 360
                if (h > 335 or h < 12) and s_ > 0.5 and v > 0.18:
                    red += 1
                    redok += reg in (3, 4)
                if 28 < h < 52 and s_ > 0.5 and v > 0.3:
                    mus += 1
                    musok += reg in (3, 4)
        for y in range(64):
            for x in range(64):
                hair += k[x, y][3] == 254 and round(k[x, y][2] / 50) == 1
        flag = (red > 60 and redok / red < 0.6) or (mus > 60 and musok / mus < 0.5)
        if flag:
            bad.append(c["id"])
            print(f"MAL {c['id']}: rojo {redok}/{red} mostaza {musok}/{mus} pelo {hair}")
    print(len(bad), "dudosos:", ",".join(bad))
    return bad


def inventory():
    """Una entrada por grupo (sexo/edad/tipo) en assets/inventario.json."""
    inv = os.path.join(ROOT, "assets", "inventario.json")
    raw = open(inv).read()
    d = json.loads(raw)
    by_id = {a["id"]: i for i, a in enumerate(d["assets"])}
    idx = json.load(open(os.path.join(OUT, "index.json")))
    groups = {}
    for e in idx["portraits"]:
        groups.setdefault((e["sex"], e["age"], e["type"]), []).append(e)
    para = {"artisan": ["H8", "familia"], "commoner": ["H8", "vecinos"], "merchant": ["H12", "familias"],
            "noble": ["H12", "familias"], "clergy": ["H12", "iglesia"], "guard": ["H10", "guardia"],
            "scholar": ["H12", "familias"], "farmer": ["H12", "familias"], "rogue": ["H12", "familias"]}
    n_new = 0
    keep = {f"portrait_pool_{sx}_{ag}_{tp}" for sx, ag, tp in groups}
    stale = [a["id"] for a in d["assets"] if a["id"].startswith("portrait_pool_") and a["id"] not in keep]
    d["assets"] = [a for a in d["assets"] if a["id"] not in stale]
    by_id = {a["id"]: i for i, a in enumerate(d["assets"])}
    for (sex, age, t), es in sorted(groups.items()):
        gid = f"portrait_pool_{sex}_{age}_{t}"
        e = {"id": gid, "tipo": "retrato", "estado": "sprite", "para": para[t] + ["población"],
             "ruta": f"assets/art/portraits/{sex}/{age}/{t}/",
             "origen": "fal: nano-banana-2/edit en rejillas 2×2 (ref: la rejilla del piloto) + mapa de regiones por "
                       "/edit + image2pixel (tools/art/fal_pool.py)",
             "coste_gen": 0, "coste_usd": round(0.04 * sum(1 for x in es if "from" not in x), 2),
             "notas": f"Grupo del pool de retratos: {len(es)} caras ({'hombre' if sex == 'm' else 'mujer'}, {age}, "
                      f"{t}), busto 64 y cara _32, colores clave de 4.10.9 ({', '.join(es[0]['recolor'])}). "
                      f"Lista y formato en assets/art/portraits/index.json y README.md."}
        if gid in by_id:
            d["assets"][by_id[gid]] = e
        else:
            d["assets"].append(e)
            n_new += 1
    with open(inv, "w") as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
    print(f"inventario: {len(groups)} grupos ({n_new} nuevos, {len(stale)} quitados)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["lista", "gen", "proc", "remascara", "indice", "qa", "inventario"])
    ap.add_argument("--solo", default="")
    ap.add_argument("--hilos", type=int, default=4)
    a = ap.parse_args()
    only = [x for x in a.solo.split(",") if x]
    if a.cmd == "lista":
        r = roster()
        print(len(combos()), "combinaciones,", len(r), "caras,", len(grids()), "rejillas")
        for f in r[:8] + r[-4:]:
            print(" ", f["id"], "|", f["clothes"][:50], "|", f["look"])
        return
    if a.cmd == "gen":
        gr = grids()
        todo = [(g, c) for g, c in gr.items() if not only or g in only]
        with ThreadPoolExecutor(a.hilos) as ex:
            res = list(ex.map(lambda gc: gen_grid(*gc), todo))
        print(f"rejillas: {sum(res)} de {len(res)}")
    elif a.cmd == "proc":
        proc(a.hilos, set(only))
    elif a.cmd == "remascara":
        remask(only)
    elif a.cmd == "qa":
        qa(set(only) or None)
    elif a.cmd == "inventario":
        inventory()
    else:
        index()


if __name__ == "__main__":
    main()
