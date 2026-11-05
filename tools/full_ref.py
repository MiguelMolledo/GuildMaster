#!/usr/bin/env python3
"""Copia de referencia de los resúmenes del jugador completo (docs/contratos/informe_jugador_completo.md §Referencia).

  python3 tools/full_ref.py [reports/full_player ...]
  (por defecto: reports/full_player, full_player_generation, chaos_player e idle_player)

Por cada carpeta con summary.json escribe reports/full_player_ref/<carpeta>.json: el summary.json (dianas, agregado,
fallos, propuestas) con las cifras planas de cada semilla (runs) y de dónde y cuándo sale. Es pequeño y va en git,
para que otras ramas (verifica, equilibrio) lo lean sin depender del worktree que corrió las partidas. Si un
summary.json antiguo no trae runs, las toma de los <semilla>.json de la carpeta. Lo llama tools/qa/noche.py al acabar.
"""
import datetime
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = ["reports/full_player", "reports/full_player_generation", "reports/chaos_player", "reports/idle_player"]
OUT = os.path.join(ROOT, "reports", "full_player_ref")


def commit():
    p = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True)
    return p.stdout.strip()


def ref_of(d):
    sp = os.path.join(d, "summary.json")
    if not os.path.exists(sp):
        return None
    summ = json.load(open(sp, encoding="utf-8"))
    if not summ.get("runs"):
        runs = []
        for f in sorted(os.listdir(d), key=lambda x: (len(x), x)):
            if f.endswith(".json") and f[:-5].isdigit():
                runs.append(json.load(open(os.path.join(d, f), encoding="utf-8")).get("measures", {}))
        summ["runs"] = runs
    summ.setdefault("format_version", 1)  # a summary.json without it predates format 2 (no rivals, no town)
    summ["source"] = os.path.relpath(d, ROOT)
    summ["written"] = datetime.date.today().isoformat()
    summ["commit"] = commit()
    return summ


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    for d in argv or DEFAULT:
        full = d if os.path.isabs(d) else os.path.join(ROOT, d)
        if not os.path.isdir(full):
            continue
        r = ref_of(full)
        if r is None:
            continue
        p = os.path.join(OUT, os.path.basename(full.rstrip("/")) + ".json")
        with open(p, "w", encoding="utf-8") as f:
            f.write(json.dumps(r, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
        print("full_ref:", os.path.relpath(p, ROOT), f"{os.path.getsize(p) // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
