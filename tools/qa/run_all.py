#!/usr/bin/env python3
"""Corre todos los rituales que existen (GDD 07 §7.1) y escribe un informe.

  python3 tools/qa/run_all.py [--only=a,b] [--skip=a,b] [--visual]

Pasos: tests (reglas), content (validador), art (inventario), boot (arranque sin ventana con cada escenario),
bench (coste del sim), sim (bots contra data/targets.json). Con --visual, además smoke (capturas con ventana, por
`grimoire heavy`). Escribe reports/qa/QA.md y los logs en reports/qa/logs/. Sale con 1 si algún paso falla.
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = "/opt/homebrew/bin/godot"
HOME = os.path.join(ROOT, "tmp", "qa_home")
G = [GODOT, "--headless", "--path", ROOT]
STEPS = [
    ("tests", G + ["-s", "tests/run_tests.gd"]),
    ("content", [sys.executable, "tools/validate_content.py", "--quiet"]),
    ("art", [sys.executable, "tools/arte.py"]),
    ("boot", ["zsh", "tools/qa/boot_check.sh"]),
    ("bench", G + ["-s", "tools/sim_bench.gd"]),
    ("sim", G + ["-s", "tools/sim_runner.gd", "--", "--bots=idle", "--days=3", "--seeds=5"]),
]
VISUAL = [("smoke", ["grimoire", "heavy", "--timeout", "3m", "--", GODOT, "--audio-driver", "Dummy", "--path", ROOT,
                     "--", "--smoke", "--shots=2", "--shot-every=2"])]


def main(argv):
    only = next((a[7:].split(",") for a in argv if a.startswith("--only=")), None)
    skip = next((a[7:].split(",") for a in argv if a.startswith("--skip=")), [])
    steps = STEPS + (VISUAL if "--visual" in argv else [])
    os.makedirs(os.path.join(ROOT, "reports", "qa", "logs"), exist_ok=True)
    os.makedirs(HOME, exist_ok=True)
    env = dict(os.environ, HOME=HOME)
    rows, failed = [], 0
    for name, cmd in steps:
        if (only and name not in only) or name in skip:
            continue
        t0 = time.time()
        p = subprocess.run(cmd, cwd=ROOT, env=env if cmd[0] == GODOT else None, capture_output=True, text=True)
        out = p.stdout + p.stderr
        with open(os.path.join(ROOT, "reports", "qa", "logs", name + ".log"), "w", encoding="utf-8") as f:
            f.write(out)
        bad = p.returncode != 0 or (cmd[0] == GODOT and ("SCRIPT ERROR" in out or "\nERROR" in out))
        failed += bad
        last = [l for l in out.strip().splitlines() if l.strip() and not l.startswith("[")][-1:] or [""]
        rows.append((name, "FALLA" if bad else "ok", f"{time.time() - t0:.1f} s", last[0][:140]))
        print(f"  {'FALLA' if bad else 'ok   '} {name:<8} {rows[-1][2]:>7}  {last[0][:110]}")
    md = ["# QA", "", "| Paso | Resultado | Tiempo | Última línea |", "|---|---|---|---|"]
    md += [f"| {a} | {b} | {c} | `{d}` |" for a, b, c, d in rows]
    with open(os.path.join(ROOT, "reports", "qa", "QA.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print("qa: todo bien" if not failed else f"qa: {failed} pasos fallan")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
