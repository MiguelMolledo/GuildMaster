#!/usr/bin/env python3
"""Antes y después de dos corridas del jugador completo (docs/contratos/informe_jugador_completo.md).

  python3 tools/full_compare.py <antes.json> <después.json> [--md=<salida.md>]

Lee dos copias de referencia (reports/full_player_ref/*.json, o dos summary.json con runs) y escribe una tabla en
Markdown con, para cada medida de las dianas de full_player (y las propuestas), la media y el rango antes y después,
la banda de data/targets.json y si cada lado la cumple. Sirve para proponer bandas nuevas tras un cambio de reglas
(el equilibrio) con su medida delante, antes de tocar data/targets.json.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXTRA = ["net_year_1", "net_year_2", "net_year_3", "gold_end", "gold_min", "wedding_day", "children",
         "title_citizen_day", "masterworks", "hired", "upgrades_done", "contracts_done", "contracts_failed", "stalls",
         "y1_gap_median_s", "y1_gap_max_s", "step_ms_mean", "ai_broke_days_max", "ai_titled_families",
         "staff_hungry_share_max", "child_hungry_share_max", "visitors_per_day", "townsfolk_end", "unlocks_off"]


def stats(runs, key):
    vals = [float(r[key]) for r in runs if isinstance(r.get(key), (int, float))]
    if not vals:
        return None
    return sum(vals) / len(vals), min(vals), max(vals), vals


def inside(v, band):
    lo, hi = band
    return (lo is None or v >= lo) and (hi is None or v <= hi)


def fmt(s):
    if s is None:
        return "—"
    m, lo, hi, _ = s
    return f"{m:.2f} [{lo:g}-{hi:g}]"


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    out = next((a[5:] for a in argv if a.startswith("--md=")), "")
    if len(args) != 2:
        print(__doc__)
        return 2
    a = json.load(open(args[0], encoding="utf-8"))
    b = json.load(open(args[1], encoding="utf-8"))
    targets = json.load(open(os.path.join(ROOT, "data", "targets.json"), encoding="utf-8")).get("full_player", {})
    rows = ["| Medida | Banda | Antes | Después | Antes cumple | Después cumple |", "|---|---|---|---|---|---|"]
    seen = set()

    def row(key, band, kind):
        if key in seen:
            return
        seen.add(key)
        sa, sb = stats(a.get("runs", []), key), stats(b.get("runs", []), key)
        need = int(targets.get("_needs_days", {}).get(key, 0))
        def ok(s, runs):
            if s is None or band is None:
                return "—"
            if runs and need > min(int(r.get("days", 0)) for r in runs):
                return "no se juzga"  # _needs_days: the run is too short for it
            if kind in ("run", "propuesta"):
                return "sí" if all(inside(v, band) for v in s[3]) else "no"
            if kind == "mean":
                return "sí" if inside(s[0], band) else "no"
            share = sum(1 for v in s[3] if v == 1) / len(s[3])
            return f"{'sí' if inside(share, band) else 'no'} ({share:.2f})"
        label = "" if band is None else f"{kind} {band}"
        rows.append(f"| `{key}` | {label} | {fmt(sa)} | {fmt(sb)} | {ok(sa, a.get("runs", []))} | {ok(sb, b.get("runs", []))} |")

    for k, v in targets.items():
        if not k.startswith("_") and isinstance(v, list):
            row(k, v, "run")
    for kind, block in (("mean", "_mean"), ("share", "_share"), ("run", "_proposed")):
        for k, v in targets.get(block, {}).items():
            if isinstance(v, list):
                row(k, v, kind if block != "_proposed" else "propuesta")
    for k in EXTRA:
        row(k, None, "")
    head = [f"# full_player: antes y después", "",
            f"Antes: `{args[0]}` ({a.get('horizon', '')}, {len(a.get('runs', []))} semillas, commit {a.get('commit', '?')}). "
            f"Después: `{args[1]}` ({b.get('horizon', '')}, {len(b.get('runs', []))} semillas, commit {b.get('commit', '?')}).", ""]
    text = "\n".join(head + rows) + "\n"
    if out:
        with open(out, "w", encoding="utf-8") as f:
            f.write(text)
        print("full_compare:", out)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
