#!/usr/bin/env python3
"""Catálogo de la biblioteca de props de interior (docs/gdd/04g_interiores.md §4.6.5.1): data/props/interior.json
desde las fichas «prop» de assets/inventario.json (las escribe tools/art/fal_props.py y, para las piezas exactas,
tools/art/props_estructura.py).

  python3 tools/interiors/props_catalog.py           # escribe data/props/interior.json
  python3 tools/interiors/props_catalog.py --check   # sale con 1 si no coincide con el inventario

Lleva ids y cifras, sin rutas (la vista saca el fichero del id: game/visuals/visual_paths.gd interior_prop).
"""
import json
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INV = os.path.join(ROOT, "assets", "inventario.json")
OUT = os.path.join(ROOT, "data", "props", "interior.json")
CATEGORIES = ["structure", "furniture", "trade", "container", "light", "small", "textile"]
STYLES = ["poor", "common", "rich"]
KEYS = ["category", "footprint", "size", "feet", "height", "walkable", "wall", "on_top", "hangs", "mirror", "trades",
        "style"]
DOC = ("Interior prop library (docs/gdd/04g_interiores.md 4.6.5.1), exported from the \"prop\" field of "
       "assets/inventario.json by tools/interiors/props_catalog.py: do not edit by hand. Per id: category; footprint "
       "[cols, rows] in tiles (its long axis rises to the right on screen; mirror = it may be flipped for the other "
       "diagonal); size [w, h] of its sprite and feet [x, y], the anchor inside it (where it stands); height = px above "
       "the feet (draw order, what it hides); walkable (flat: people walk over it), wall (stands against a wall), "
       "on_top (may go on a table or a counter), hangs (hangs on a wall); trades and style, for the builder's rules. "
       "The sprite is assets/art/props/interior/<id>.png (game/visuals/visual_paths.gd).")


def build(inv):
    props = {}
    for a in inv.get("assets", []):
        p = a.get("prop")
        if not isinstance(p, dict) or not a["id"].startswith("iprop_"):
            continue
        props[a["id"][len("iprop_"):]] = {k: p[k] for k in KEYS if k in p}
    return {"_doc": DOC, "categories": CATEGORIES, "styles": STYLES, "count": len(props),
            "props": {k: props[k] for k in sorted(props)}}


def dump(d):
    """Una línea por pieza (el fichero se lee y se compara a ojo)."""
    lines = ["{"]
    lines.append(f'  "_doc": {json.dumps(d["_doc"], ensure_ascii=False)},')
    lines.append(f'  "categories": {json.dumps(d["categories"])},')
    lines.append(f'  "styles": {json.dumps(d["styles"])},')
    lines.append(f'  "count": {d["count"]},')
    lines.append('  "props": {')
    ids = list(d["props"])
    for i, k in enumerate(ids):
        lines.append(f'    {json.dumps(k)}: {json.dumps(d["props"][k], ensure_ascii=False)}' + ("," if i < len(ids) - 1 else ""))
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def check(inv, cat):
    """Errores del catálogo: que coincida con el inventario y que cada pieza tenga valores válidos y su sprite."""
    errs = []
    want = build(inv)
    if cat != want:
        errs.append("data/props/interior.json no coincide con assets/inventario.json: python3 tools/interiors/props_catalog.py")
    for pid, p in cat.get("props", {}).items():
        w = f"props/interior.{pid}"
        if p.get("category") not in CATEGORIES:
            errs.append(f"{w}: categoría desconocida {p.get('category')}")
        if p.get("style") not in STYLES:
            errs.append(f"{w}: estilo desconocido {p.get('style')}")
        fp = p.get("footprint")
        if not (isinstance(fp, list) and len(fp) == 2 and all(isinstance(v, int) and 1 <= v <= 4 for v in fp)):
            errs.append(f"{w}: huella inválida {fp}")
        size, feet = p.get("size"), p.get("feet")
        if not (isinstance(size, list) and isinstance(feet, list) and 0 <= feet[0] <= size[0] and 0 <= feet[1] <= size[1]):
            errs.append(f"{w}: ancla {feet} fuera del sprite {size}")
        if not os.path.exists(os.path.join(ROOT, "assets", "art", "props", "interior", pid + ".png")):
            errs.append(f"{w}: falta su sprite assets/art/props/interior/{pid}.png")
    return errs


def main():
    inv = json.load(open(INV, encoding="utf-8"))
    if "--check" in sys.argv:
        cat = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
        errs = check(inv, cat)
        for e in errs:
            print("ERROR", e)
        print(f"props_catalog: {len(cat.get('props', {}))} piezas · {len(errs)} errores")
        sys.exit(1 if errs else 0)
    d = build(inv)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write(dump(d))
    print(f"props_catalog: {d['count']} piezas -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
