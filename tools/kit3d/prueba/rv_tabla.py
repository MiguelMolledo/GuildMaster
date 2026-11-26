"""The table of docs/interior3d.md, «Revisión de los edificios de oficio», from the audit:
  godot --headless --path . -s tools/rv_auditoria.gd -- --salida=out/rv_auditoria_antes.json   (before the fixes)
  godot --headless --path . -s tools/rv_auditoria.gd                                            (after: out/rv_auditoria.json)
  python3 tools/rv_tabla.py [--detalle]   ->  prints the Markdown (paste it between <!-- rv:ini --> and <!-- rv:fin -->)
A finding is per building and level; [con mejoras] when it only shows with every upgrade bought, [en espejo] when only
the mirrored layout has it."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
after = json.load(open(os.path.join(ROOT, "reports", "kit3d", "rv_auditoria.json")))
bp = os.path.join(ROOT, "reports", "kit3d", "rv_auditoria_antes.json")
before = json.load(open(bp)) if os.path.exists(bp) else {}
DETAIL = "--detalle" in sys.argv
NAMES = {"forge": "Forja", "carpentry": "Carpintería", "tailor_shop": "Sastrería", "bakery": "Panadería", "tavern_inn": "Taberna", "masonry": "Cantería",
         "bank": "Banco", "clinic": "Clínica", "armory": "Armería", "farm": "Granja", "den": "Guarida",
         "house_humble": "Casa humilde", "house_well": "Casa acomodada", "house_noble": "Casa noble", "town_hall": "Ayuntamiento"}
ORDER = list(NAMES)


def key(k):
    t, lv = k.split(":")
    return (ORDER.index(t) if t in ORDER else 99, int(lv))


def norm(msg):
    """the same finding as written and mirrored: tile coordinates and the mirrored wording out"""
    return re.sub(r"\(\d+, \d+\)", "(c, r)", msg)


def tagged(fails):
    """{normalised message: (message, tag)}"""
    out = {}
    for msg, runs in fails.items():
        n = norm(msg)
        base = any(not r.startswith("espejo") for r in runs)
        plain = any(r in ("base", "espejo_base") for r in runs)
        tag = []
        if not plain:
            tag.append("con mejoras")
        if not base:
            tag.append("en espejo")
        prev = out.get(n)
        if prev is None or len(tag) < len(prev[1]):
            out[n] = (msg, tag)
    return out


def short(msg, tag):
    return msg + (" [%s]" % ", ".join(tag) if tag else "")


def group(items):
    """findings grouped by kind, counted, for the table"""
    kinds = {}
    for msg, tag in items:
        k = msg.split(":")[0] if ":" in msg else msg
        kinds.setdefault(k, []).append(short(msg, tag))
    return kinds


def kind(msg):
    if msg.startswith("escalera"):
        return "escalera"
    if "chimenea" in msg or "tiro" in msg or "mostrador" in msg.lower() or "Barra:" in msg or "cama" in msg or "lejos" in msg or "yunque" in msg or "pila" in msg:
        return "oficio"
    if "atraviesa" in msg or "flota" in msg or "hunde" in msg or "se meten" in msg:
        return "muros"
    return "paso"


KINDS = ["escalera", "paso", "oficio", "muros"]
print("| Edificio | Escaleras | Paso | Oficio | Muros y piezas | Lo que queda |")
print("|---|---|---|---|---|---|")
for k in sorted(after, key=key):
    t, lv = k.split(":")
    a = tagged(after[k]["fails"])
    b = tagged(before.get(k, {}).get("fails", {}))
    cnt = []
    for kd in KINDS:
        nb = sum(1 for n in b if kind(b[n][0]) == kd)
        na = sum(1 for n in a if kind(a[n][0]) == kd)
        cnt.append("—" if nb == na == 0 else "%d → %d" % (nb, na))
    left = "; ".join(short(m, tg) for m, tg in a.values()) or "—"
    print("| %s N%s | %s | %s |" % (NAMES.get(t, t), lv, " | ".join(cnt), left))
if DETAIL:
    print()
    for k in sorted(after, key=key):
        t, lv = k.split(":")
        a = tagged(after[k]["fails"])
        b = tagged(before.get(k, {}).get("fails", {}))
        fixed = [b[n] for n in b if n not in a]
        if fixed:
            print("- **%s N%s**, arreglado: %s" % (NAMES.get(t, t), lv, "; ".join(short(m, tg) for m, tg in fixed)))
