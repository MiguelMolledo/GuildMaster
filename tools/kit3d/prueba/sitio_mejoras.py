"""The table of docs/interior3d.md, «Mejoras colocadas», from the measure of the test bench:
  godot --headless --path . res://interiores.tscn -- --mejoras-tabla   ->  out/int_mejoras.json
  python3 tools/sitio_mejoras.py [--detalle]                            ->  prints the Markdown tables
Every interior is mounted with all its upgrades bought (the auto pieces get the same place bought or not, so the
measure with all of them is the measure of any subset). For each type and level an upgrade of the sim is:
  cabe       its piece stands inside (placed, a swap, on top of another, or the house of that level already has it)
  ampliación it is not inside this house but would be with more house: an annex, the yard, a floor, a cellar, the
             next level (it has no room here and the same type places it at a higher level)
  sin sitio  no room here nor in any higher level of the type
  fuera      it changes the facade or is an effect: nothing inside"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
me = json.load(open(os.path.join(ROOT, "reports", "kit3d", "int_mejoras.json")))
NAMES = {"house_humble": "Casa humilde", "house_well": "Casa acomodada", "house_noble": "Casa noble", "tavern_inn": "Taberna",
         "tailor_shop": "Sastrería", "carpentry": "Carpintería", "bakery": "Panadería", "bank": "Banco", "clinic": "Clínica",
         "armory": "Armería", "masonry": "Cantería", "den": "Guarida", "farm": "Granja", "forge": "Forja", "town_hall": "Ayuntamiento"}
NEEDS = {"anexo": "anexo", "patio": "patio", "planta": "planta más", "sótano": "sótano", "nivel": "nivel siguiente", "fuera": "fuera de la casa"}


def kind(type_, lv, node):
    st = me["%s:%d" % (type_, lv)]["nodes"][node]
    s = st["status"]
    if s in ("placed", "base", "fits"):
        return "cabe", st
    if s == "needs":
        return "ampliación", st
    if s == "no_room":
        for up in (lv + 1, lv + 2):
            k = "%s:%d" % (type_, up)
            if k in me and me[k]["nodes"].get(node, {}).get("status") in ("placed", "base", "fits"):
                return "ampliación", dict(st, note="nivel %d" % up)
        return "sin sitio", st
    return "sin sitio", st


def main():
    detail = "--detalle" in sys.argv
    print("| Edificio | Mejoras de la sim | Caben | Piden ampliación | Sin sitio ni ampliando | Fuera (fachada o efecto) | Casillas libres sin mejoras → con todas |")
    print("|---|---|---|---|---|---|---|")
    rows = []
    for k in me:
        t, lv = k.split(":")
        rows.append((list(NAMES).index(t) if t in NAMES else 99, int(lv), t))
    for _, lv, t in sorted(rows):
        v = me["%s:%d" % (t, lv)]
        ids, outside = v["ids"], v["out"]
        n = len(ids) + len(outside)
        if n == 0:
            print("| %s N%d | 0 | — | — | — | — | %s |" % (NAMES.get(t, t), lv, " + ".join(map(str, v["free_none"]))))
            continue
        groups = {"cabe": [], "ampliación": [], "sin sitio": []}
        for sim_id, node in sorted(ids.items()):
            g, st = kind(t, lv, node)
            why = st.get("note", "")
            if g == "ampliación" and st["status"] == "needs":
                why = NEEDS.get(why.split(":")[0], why.split(":")[0])
            groups[g].append((sim_id, node, why))
        amp = {}
        for _, _, why in groups["ampliación"]:
            amp[why] = amp.get(why, 0) + 1
        amp_txt = ", ".join("%d %s" % (c, w) for w, c in sorted(amp.items(), key=lambda x: -x[1]))
        sin = ", ".join(node for _, node, _ in groups["sin sitio"])
        free = "%s → %s" % (" + ".join(map(str, v["free_none"])), " + ".join(map(str, v["free_all"])))
        if v["isolated"]:
            free += " (sin acceso: %s)" % v["isolated"]
        print("| %s N%d | %d | %d | %d%s | %d%s | %d | %s |" % (NAMES.get(t, t), lv, n, len(groups["cabe"]), len(groups["ampliación"]),
              (" (%s)" % amp_txt) if amp_txt else "", len(groups["sin sitio"]), (": " + sin) if sin else "", len(outside), free))
        if detail:
            for g in groups:
                for sim_id, node, why in groups[g]:
                    print("|  | %s | %s | %s | %s | | |" % (sim_id, node, g, why))


main()
