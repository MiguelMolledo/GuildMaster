#!/usr/bin/env python3
"""Formatea data/flows/*.json: un paso por línea (fácil de leer y de comparar en git).

  python3 tools/verifica/fmt_flows.py [ids...]
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIR = os.path.join(ROOT, "data", "flows")


def dump(d):
    head = {k: v for k, v in d.items() if k != "steps"}
    lines = ["{"]
    for k, v in head.items():
        lines.append(f"  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)},")
    lines.append('  "steps": [')
    steps = d.get("steps", [])
    for i, s in enumerate(steps):
        lines.append("    " + json.dumps(s, ensure_ascii=False) + ("," if i < len(steps) - 1 else ""))
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(ids):
    for f in sorted(os.listdir(DIR)):
        if not f.endswith(".json") or (ids and f[:-5] not in ids):
            continue
        p = os.path.join(DIR, f)
        with open(p, encoding="utf-8") as fh:
            d = json.load(fh)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(dump(d))


if __name__ == "__main__":
    main(sys.argv[1:])
