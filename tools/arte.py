#!/usr/bin/env python3
"""Estado del arte y del audio: assets/inventario.json contra lo que pide el contenido (docs/ASSETS.md).

  python3 tools/arte.py              resumen: cuántos assets hay en cada estado, por tipo y por hito
  python3 tools/arte.py --falta      además, la lista de trabajo: assets sin hacer, animaciones que faltan
                                     y lo que el contenido pide y no tiene entrada en el inventario
  python3 tools/arte.py --json       el resultado en JSON (lo usa tools/cuaderno.py)

Escala de estados (de menos a más): falta → greybox → concepto → sprite → animado → final.
Audio: falta → provisional → generado → final.
Comprueba: estados y tipos válidos, ids únicos, que exista la ruta desde «sprite» (audio: desde «generado»),
que un asset «animado» o «final» tenga hechas todas las animaciones que pide su tipo, y que cada objeto
(data/items) tenga icono y cada edificio (data/buildings) sprite en el inventario.
Sale con 1 si hay errores.
"""
import json
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INV = os.path.join(ROOT, "assets", "inventario.json")


def load():
    with open(INV, encoding="utf-8") as f:
        return json.load(f)


def analyse():
    inv = load()
    states = inv["estados"]
    audio_states = inv["estados_audio"]
    anims_for = inv["animaciones_por_tipo"]
    errors, todo = [], []
    by_state, by_type, by_milestone = {}, {}, {}
    seen = set()
    for a in inv["assets"]:
        aid, kind, st = a.get("id"), a.get("tipo"), a.get("estado")
        audio = kind in inv["tipos_audio"]
        scale = audio_states if audio else states
        if aid in seen:
            errors.append(f"{aid}: id repetido")
        seen.add(aid)
        if kind not in inv["tipos"] and not audio:
            errors.append(f"{aid}: tipo desconocido {kind}")
        if st not in scale:
            errors.append(f"{aid}: estado desconocido {st} (vale: {', '.join(scale)})")
            continue
        level = scale.index(st)
        by_state[st] = by_state.get(st, 0) + 1
        by_type.setdefault(kind, {}).setdefault(st, 0)
        by_type[kind][st] += 1
        for m in a.get("para", []):
            if m.startswith("H"):
                by_milestone.setdefault(m, {"total": 0, "hechos": 0})
                by_milestone[m]["total"] += 1
                by_milestone[m]["hechos"] += int(st == "final")
        needs_file = level >= scale.index("generado" if audio else "sprite")
        if needs_file and not os.path.exists(os.path.join(ROOT, a.get("ruta") or "__nada__")):
            errors.append(f"{aid}: estado {st} pero no existe {a.get('ruta')}")
        required = anims_for.get(kind, [])
        done = a.get("animaciones", {})
        missing = [x for x in required if done.get(x, "falta") == "falta"]
        if not audio and st in ("animado", "final") and missing:
            errors.append(f"{aid}: estado {st} con animaciones sin hacer: {', '.join(missing)}")
        if st != scale[-1]:
            todo.append({"id": aid, "tipo": kind, "estado": st, "para": a.get("para", []),
                         "faltan_animaciones": missing, "notas": a.get("notas", "")})
    # What the content asks for and has no entry.
    asked = []
    for folder, prefix, what in (("items", "icon_", "icono"), ("buildings", "bld_", "sprite")):
        d = os.path.join(ROOT, "data", folder)
        for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if name.endswith(".json") and not name.startswith("_"):
                aid = prefix + name[:-5]
                if aid not in seen:
                    asked.append({"id": aid, "que": what, "de": f"{folder}/{name[:-5]}"})
    return {"errors": errors, "todo": todo, "sin_entrada": asked, "por_estado": by_state, "por_tipo": by_type,
            "por_hito": by_milestone, "estados": states, "estados_audio": audio_states, "total": len(inv["assets"])}


def main(argv):
    r = analyse()
    if "--json" in argv:
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return 1 if r["errors"] else 0
    order = r["estados"] + [s for s in r["estados_audio"] if s not in r["estados"]]
    print(f"arte: {r['total']} assets · " + " · ".join(f"{s} {r['por_estado'].get(s, 0)}" for s in order))
    for kind, sts in sorted(r["por_tipo"].items()):
        print(f"  {kind:<11} " + "  ".join(f"{s}:{n}" for s, n in sts.items()))
    for m, c in sorted(r["por_hito"].items(), key=lambda x: int(x[0][1:].rstrip("+") or 0)):
        print(f"  {m:<4} {c['hechos']}/{c['total']} en final")
    if "--falta" in argv:
        print("\nPor hacer:")
        for t in r["todo"]:
            extra = f" · faltan {', '.join(t['faltan_animaciones'])}" if t["faltan_animaciones"] else ""
            print(f"  [{t['estado']:<9}] {t['id']} ({t['tipo']}, {', '.join(t['para'])}){extra}")
        if r["sin_entrada"]:
            print("\nEl contenido lo pide y no está en el inventario:")
            for s in r["sin_entrada"]:
                print(f"  {s['id']} · {s['que']} de {s['de']}")
    for e in r["errors"]:
        print("  ✖", e)
    print(f"arte: {len(r['errors'])} errores, {len(r['todo'])} por hacer, {len(r['sin_entrada'])} sin entrada")
    return 1 if r["errors"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
