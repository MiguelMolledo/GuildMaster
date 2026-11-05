#!/usr/bin/env python3
"""Town builder (docs/protocolos/generar-ciudad.md). Offline: writes data/maps/<id>.json; the game loads it as is.

  python3 tools/city/ciudad.py vestir <map>            dress a map by rules (data/maps/<map>.json "decor")
  python3 tools/city/ciudad.py validar [map...]        coherence of every map (or the given ones); exit 1 on errors
  python3 tools/city/ciudad.py reunion [map...]        add the meeting points and patrols of 04f 4.24 a map lacks
  python3 tools/city/ciudad.py parcelas [map...]       deal the plots of 04 §4.9.1 (lots, ruins, businesses) again
  python3 tools/city/ciudad.py vista <map> [--out PNG] preview PNG (reports/ciudad/<map>.png) without the game
  python3 tools/city/ciudad.py generar --id <id> --layout <calle|plaza|cruce|rio|aldea|abadia> --seed <n> [--size 40x40] [--households N] ...
                                                       generate a town (generator.py), dress it, validate, preview
  python3 tools/city/ciudad.py region [id...] [--out DIR] [--variante imagen|procedural]
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


def reunion(ids):
    """04f 4.24.2 / 4.24.4: the meeting points and the patrols each map lacks (town_e: tools/maps/make_town_e.py)."""
    cat = citylib.Catalog()
    mdir = os.path.join(citylib.DATA, "maps")
    ids = ids or sorted(f[:-5] for f in os.listdir(mdir) if f.endswith(".json") and not f.startswith("_") and f != "town_e.json")
    for mid in ids:
        d = citylib.load_json(os.path.join(mdir, mid + ".json"))
        added = citylib.add_life(d, cat)
        citylib.save_map(d)
        print(f"reunion {mid}: {added}")
    return validar(ids, True)


def parcelas(ids):
    """04 §4.9.1: the plots of the maps (by default the towns of reglas.json plots.maps). The towns of
    tools/city/ciudades.json are rebuilt from their plan (the same map, its plots dealt again); town_e by
    tools/maps/make_town_e.py; any other map gets them once (a map that has them is left as it is)."""
    import organic
    import plots
    cat = citylib.Catalog()
    ids = ids or [i for i in citylib.rules().get("plots", {}).get("maps", []) if i != "town_e"]
    planned = [i for i in ids if i in organic.load_plans()]
    if planned:
        organic.main(planned, "", None)
    for mid in ids:
        if mid in planned:
            continue
        if mid == "town_e":
            print("parcelas town_e: python3 tools/maps/make_town_e.py")
            continue
        d = citylib.load_json(os.path.join(citylib.DATA, "maps", mid + ".json"))
        if d.get("plots") is not None:
            print(f"parcelas {mid}: ya las tiene (regenera el mapa para repartirlas otra vez)")
            continue
        print(f"parcelas {mid}: {plots.add_plots(d, cat)}")
        citylib.save_map(d)
    return validar(ids, True)


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
    if cmd == "reunion":
        return reunion([a for a in rest if not a.startswith("--")])
    if cmd == "parcelas":
        return parcelas([a for a in rest if not a.startswith("--")])
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
        var = rest[rest.index("--variante") + 1] if "--variante" in rest else None
        ids = [a for a in rest if not a.startswith("--") and a not in (out, var)]
        return organic.main(ids, out, var)
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
