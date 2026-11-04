#!/usr/bin/env python3
"""Town builder (docs/protocolos/generar-ciudad.md). Offline: writes data/maps/<id>.json; the game loads it as is.

  python3 tools/city/ciudad.py vestir <map>            dress a map by rules (data/maps/<map>.json "decor")
  python3 tools/city/ciudad.py validar [map...]        coherence of every map (or the given ones); exit 1 on errors
  python3 tools/city/ciudad.py vista <map> [--out PNG] preview PNG (reports/ciudad/<map>.png) without the game
  python3 tools/city/ciudad.py generar --id <id> --layout <calle|plaza|cruce|rio|aldea|abadia> --seed <n> [--size 40x40] [--households N] ...
                                                       generate a town (generator.py), dress it, validate, preview
  python3 tools/city/ciudad.py region [id...] [--out DIR]
                                                       the organic towns of tools/city/ciudades.json (organic.py)

Maps whose id is in STRICT (or any map made by `generar`: "generated" in the map) get every rule as an error; the
hand-made town_e keeps the rules its old layout breaks (sim doors on hidden faces) as warnings: the targets of the
bots depend on its sites.
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citylib  # noqa: E402


def vestir(map_id):
    cat = citylib.Catalog()
    m = citylib.load_map(map_id, cat)
    m.d["decor"] = citylib.dress(m)
    p = citylib.save_map(m.d)
    kinds = {}
    for it in m.d["decor"]["items"]:
        kinds[it["kind"]] = kinds.get(it["kind"], 0) + 1
    print(f"vestir {map_id}: {len(m.d['decor']['items'])} piezas ({', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))})"
          f" -> {os.path.relpath(p, citylib.ROOT)}")
    return m


def validar(ids, quiet=False):
    cat = citylib.Catalog()
    mdir = os.path.join(citylib.DATA, "maps")
    ids = ids or sorted(f[:-5] for f in os.listdir(mdir) if f.endswith(".json") and not f.startswith("_"))
    bad = 0
    for mid in ids:
        m = citylib.load_map(mid, cat)
        rep = citylib.validate(m, strict=bool(m.d.get("generated")), hand_decor=citylib.hand_decor(mid))
        bad += len(rep.errors)
        print(f"== {mid}: {len(rep.errors)} errores, {len(rep.warnings)} avisos")
        for e in rep.errors:
            print("  ERROR", e)
        if not quiet:
            for w in rep.warnings:
                print("  aviso", w)
            for n in rep.info:
                print("  ·", n)
    return 1 if bad else 0


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd, rest = argv[0], argv[1:]
    if cmd == "vestir":
        vestir(rest[0])
        return validar([rest[0]])
    if cmd == "validar":
        quiet = "--quiet" in rest
        return validar([a for a in rest if not a.startswith("--")], quiet)
    if cmd == "vista":
        import preview
        out = rest[rest.index("--out") + 1] if "--out" in rest else None
        print(preview.render(rest[0], out))
        return 0
    if cmd == "generar":
        import generator
        return generator.main(rest)
    if cmd == "region":
        import organic
        out = rest[rest.index("--out") + 1] if "--out" in rest else ""
        ids = [a for a in rest if not a.startswith("--") and a != out]
        return organic.main(ids, out)
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
