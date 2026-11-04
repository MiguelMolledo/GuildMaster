#!/usr/bin/env python3
"""Catálogo de retratos para el sim: data/portraits.json desde assets/art/portraits/index.json (versión 1, su README).

  python3 tools/art/portraits_catalog.py           # escribe data/portraits.json
  python3 tools/art/portraits_catalog.py --check   # sale con 1 si data/portraits.json no coincide con el índice

El sim solo depende de data/: el reparto (sim/meta/cast.gd) elige ids de este catálogo; las rutas de los PNG se quedan
en el índice y solo las lee la vista (game/visuals/visual_paths.gd). Lleva ids, sexo, franja, tipo y fallback, sin
rutas. tools/validate_content.py comprueba que coincide (como data/building_sprites.json de ciudad).
"""
import json
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INDEX = os.path.join(ROOT, "assets", "art", "portraits", "index.json")
OUT = os.path.join(ROOT, "data", "portraits.json")
DOC = ("Portrait pool for the sim (población, docs/contratos/poblacion.md), exported from assets/art/portraits/index.json "
       "by tools/art/portraits_catalog.py: do not edit by hand, re-export when the pool changes (tools/validate_content.py "
       "checks they match). Ids only, no paths: by[\"<sex>|<age band>|<type>\"] = the portrait ids sorted; fallback[type][band] "
       "= the type used when that sex + band + type has none (then commoner, which exists in every band and sex); ages = "
       "the bands in years. Read by Catalog.portrait_pool (Cast.pick_portrait); the view turns an id into its file with the "
       "index.")


def build(index):
    by = {}
    for e in index.get("portraits", []):
        by.setdefault(f"{e['sex']}|{e['age']}|{e['type']}", []).append(e["id"])
    return {"_doc": DOC, "version": index.get("version"), "ages": index.get("ages", {}), "types": index.get("types", []),
            "fallback": index.get("fallback", {}), "count": sum(len(v) for v in by.values()),
            "by": {k: sorted(by[k]) for k in sorted(by)}}


def dump(d):
    lines = ["{"]
    keys = list(d.keys())
    for i, k in enumerate(keys):
        end = "," if i < len(keys) - 1 else ""
        if k == "by":
            lines.append('  "by": {')
            bk = list(d["by"].keys())
            for j, b in enumerate(bk):
                lines.append(f'    {json.dumps(b)}: {json.dumps(d["by"][b])}' + ("," if j < len(bk) - 1 else ""))
            lines.append("  }" + end)
        else:
            lines.append(f"  {json.dumps(k)}: {json.dumps(d[k], ensure_ascii=False)}{end}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def expected():
    with open(INDEX, encoding="utf-8") as f:
        return build(json.load(f))


def main(argv):
    if not os.path.exists(INDEX):
        print(f"portraits_catalog: falta {os.path.relpath(INDEX, ROOT)}")
        return 1
    want = expected()
    if "--check" in argv:
        have = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
        same = {k: v for k, v in have.items() if k != "_doc"} == {k: v for k, v in want.items() if k != "_doc"}
        print("portraits_catalog: coincide" if same else "portraits_catalog: data/portraits.json no coincide con el índice")
        return 0 if same else 1
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(dump(want))
    print(f"portraits_catalog: {want['count']} retratos en {len(want['by'])} combinaciones -> data/portraits.json")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
