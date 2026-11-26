#!/usr/bin/env python3
"""Trae a la rama 3d los cambios de ~/Code/Prueba3D entre dos commits (docs/3d/plan.md §2: lo nuevo se trae por hash).

  python3 tools/kit3d/traer_prueba.py <desde> <hasta> [--aplicar] [--prueba=~/Code/Prueba3D]

Para cada fichero de la prueba que cambió entre <desde> y <hasta> y que la rama ya tiene (scripts/, shaders/, data/,
tools/ de la lista TOOLS), compara la copia de aquí con la versión <desde> reescrita como se trajo (rutas
res://scripts/ → game/world3d/<zona>/, res://data/ → data/view3d/ o game/world3d/kit_data/, InteriorBuilder →
Interior3DBuilder):
  - si la copia de aquí no se ha tocado, la sustituye por la versión <hasta> reescrita (con --aplicar);
  - si se tocó aquí (costuras de GuildMaster), no la pisa: la lista para fundirla a mano.
Los ficheros nuevos de la prueba que no están aquí solo se listan (traerlos es decisión de cada tanda).
Sin --aplicar solo informa.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOWN = {"main", "pueblo", "pueblo_vivo", "house_builder", "building_types", "landmark_builder", "road_builder",
        "opt3d", "tree_far", "fiestas_pueblo", "flock", "cart_trip", "convoy", "sim3d", "sim3d_chars", "dc_prof"}
PEOPLE = {"char_builder", "char_age", "char_skirt"}
INTERIOR = {"interior3d", "interior_builder", "situ_cut", "situ_live", "situ_shell"}
WITH_PATHS = {"data/chars/kit.json", "data/chars/anims.json", "data/interiors/muebles.json",
              "data/props/ropa_muebles.json"}
# herramientas de la prueba que viven aquí (tools/kit3d/prueba/)
TOOLS = {"tools/rv_auditoria.gd", "tools/sitio_gen.py", "tools/sitio_mejoras.py", "tools/sitio_tabla.py",
         "tools/rv_tabla.py", "tools/rv_lamina.py"}


def target(rel):
    """Dónde vive aquí el fichero `rel` de la prueba ("" si no se trae)."""
    if rel.startswith("scripts/") and rel.endswith(".gd"):
        sub = rel[len("scripts/"):]
        base = os.path.basename(sub)[:-3]
        if sub.startswith("clima/"):
            return "game/world3d/light/" + os.path.basename(sub)
        if sub.startswith("audio/"):
            return "game/world3d/audio/" + os.path.basename(sub)
        for zone, names in (("town", TOWN), ("people", PEOPLE), ("interior", INTERIOR)):
            if base in names:
                return f"game/world3d/{zone}/{base}.gd"
        return ""
    if rel.startswith("shaders/") and rel.endswith(".gdshader"):
        return "game/world3d/shaders/" + os.path.basename(rel)
    if rel.startswith("data/"):
        if rel in WITH_PATHS:
            return "game/world3d/kit_data/" + rel[len("data/"):]
        return "data/view3d/" + rel[len("data/"):]
    if rel in TOOLS:
        return "tools/kit3d/prueba/" + os.path.basename(rel)
    return ""


def mapping(files):
    return {f: target(f) for f in files if target(f)}


def rewrite(s, table):
    for k in sorted(table, key=len, reverse=True):
        s = s.replace("res://" + k, "res://" + table[k])
    s = re.sub(r"res://data/(?!view3d/)", "res://data/view3d/", s)
    s = s.replace("InteriorBuilder", "Interior3DBuilder")
    return s


def show(prueba, rev, rel):
    r = subprocess.run(["git", "-C", prueba, "show", f"{rev}:{rel}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 2:
        print(__doc__)
        return 2
    a, b = args
    apply = "--aplicar" in argv
    prueba = os.path.expanduser(next((x.split("=", 1)[1] for x in argv if x.startswith("--prueba=")), "~/Code/Prueba3D"))
    all_files = subprocess.run(["git", "-C", prueba, "ls-tree", "-r", "--name-only", b], capture_output=True,
                               text=True).stdout.split()
    table = mapping(all_files)
    changed = subprocess.run(["git", "-C", prueba, "diff", "--name-only", a, b], capture_output=True,
                             text=True).stdout.split()
    done, merge, new = [], [], []
    for rel in changed:
        dst = table.get(rel, "")
        if not dst:
            continue
        here = os.path.join(ROOT, dst)
        old, cur = show(prueba, a, rel), show(prueba, b, rel)
        text = rel.endswith((".gd", ".gdshader", ".py"))
        conv = (lambda x: rewrite(x.decode("utf-8"), table).encode("utf-8")) if text else (lambda x: x)
        if not os.path.exists(here):
            new.append((rel, dst))
            continue
        mine = open(here, "rb").read()
        if old is not None and conv(old) != mine:
            merge.append((rel, dst))
            continue
        if cur is None:
            continue
        if apply:
            with open(here, "wb") as f:
                f.write(conv(cur))
        done.append((rel, dst))
    print(f"traer_prueba {a}..{b}: {len(done)} {'traídos' if apply else 'se pueden traer'}, "
          f"{len(merge)} a fundir a mano, {len(new)} nuevos sin traer")
    for rel, dst in done:
        print(f"  ok     {rel} -> {dst}")
    for rel, dst in merge:
        print(f"  FUNDIR {rel} -> {dst} (tocado aquí)")
    for rel, dst in new:
        print(f"  nuevo  {rel} -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
