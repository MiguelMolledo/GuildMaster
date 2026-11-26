"""The table of docs/interior3d.md, «Interiores por tipo», from the measures of the test bench:
  godot --headless --path . res://interiores.tscn -- --aforo      ->  out/int_aforo.json  (tiles, places, cast, capacity)
  godot --path . res://interiores.tscn -- --coste                 ->  out/int_coste.json  (draw calls, mounting time)
  python3 tools/sitio_tabla.py                                     ->  prints the Markdown tables (paste them in the doc)
Capacity («aforo») of a floor = the most people wandering it without rest who wait less than a quarter of the time and
walk through each other at most once in the test."""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
af = json.load(open(os.path.join(ROOT, "reports", "kit3d", "int_aforo.json")))
co_path = os.path.join(ROOT, "reports", "kit3d", "int_coste.json")
co = json.load(open(co_path)) if os.path.exists(co_path) else {}
NAMES = {"house_humble": "Casa humilde", "house_well": "Casa acomodada", "house_noble": "Casa noble", "tavern_inn": "Taberna", "tailor_shop": "Sastrería",
         "carpentry": "Carpintería", "bakery": "Panadería", "bank": "Banco", "clinic": "Clínica", "armory": "Armería",
         "masonry": "Cantería", "den": "Guarida", "farm": "Granja", "forge": "Forja", "town_hall": "Ayuntamiento"}
ORDER = list(NAMES)


def cap(rows):
    best = 0
    for r in rows:
        if r["wait_pct"] <= 25 and r["pushes"] <= 1:
            best = max(best, r["n"])
    return best


def key(k):
    t, lv = k.split(":")
    return (ORDER.index(t) if t in ORDER else 99, int(lv))


print("| Edificio | Casa | Casillas libres por planta | Puestos | Reparto: esperas / cruces | Aforo por planta | Montar | Draw calls abierta: planta baja / alta |")
print("|---|---|---|---|---|---|---|---|")
for k in sorted(af, key=key):
    v = af[k]
    t, lv = k.split(":")
    if v.get("why"):
        print("| %s N%s | no encaja: %s | | | | | | |" % (NAMES.get(t, t), lv, v["why"]))
        continue
    free = " + ".join("%d de %d" % (a, b) for a, b in zip(v["free"], v["tiles"]))
    run = v["cast_run"]
    afo = " / ".join(str(cap(v["aforo"][f])) for f in sorted(v["aforo"]))
    c = co.get(k, {})
    cost = ("%d" % c["dc_open_p0"] + (" / %d" % c["dc_open_p1"] if c.get("dc_open_p1") else "")) if c.get("dc_open_p0") else ""
    ms = "%.0f ms" % c["mount_ms"] if c.get("mount_ms") else ""
    print("| %s N%s | %d × %d m, %d pl. | %s | %d | %d personas: %d (%.0f s) / %d | %s | %s | %s |" % (
        NAMES.get(t, t), lv, v["w"], v["d"], v["floors"], free, v["stations"], v["cast"], run["waits"], run["wait_s"], run["pushes"], afo, ms, cost))

print()
print("| Edificio | Planta | 2 | 3 | 4 | 6 | 8 |")
print("|---|---|---|---|---|---|---|")
for k in sorted(af, key=key):
    v = af[k]
    t, lv = k.split(":")
    if v.get("why"):
        continue
    for f in sorted(v["aforo"]):
        cells = {r["n"]: "%d %% / %d" % (r["wait_pct"], r["pushes"]) for r in v["aforo"][f]}
        print("| %s N%s | %s | %s |" % (NAMES.get(t, t), lv, f, " | ".join(cells.get(n, "—") for n in (2, 3, 4, 6, 8))))
