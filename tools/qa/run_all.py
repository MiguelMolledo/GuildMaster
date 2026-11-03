#!/usr/bin/env python3
"""Corre todos los rituales que existen (GDD 07 §7.1) y escribe un informe.

  python3 tools/qa/run_all.py [--only=a,b] [--skip=a,b] [--visual]

Pasos: tests (reglas), content (validador), art (inventario), ciudad (coherencia de los mapas, tools/city/), boot (arranque sin ventana con cada escenario),
bench (coste del sim), sim (bots contra data/targets.json en el arenero), sim2 (random_clicker e idle_rival a 10 días),
novice (partida nueva real en Normal: artisan_novice e idle, 10 semillas: con 5 la media del novato queda al borde
de su diana por ruido de semillas; las 30 semillas y las tres dificultades se
corren a mano, ver CLAUDE.md), expert (H5: artisan_expert en una partida nueva real, versión corta de 2 semillas × 12
días; las dianas goldflow de días 9-24 se corren a mano con 30 semillas), town (H7: microeventos y mostrador en 30 días,
idle_town, 2 semillas), kin (H14: un familiar con Comerciar aprovisiona la forja, 3 semillas), events (H13: 10 años,
80 días, de artisan_expert con estaciones y eventos globales, sin bloqueos; 2 semillas), carpenter / mason /
tailor (H12: el novato de cada oficio del Artesano en su partida nueva real en Normal, 10 semillas × 10 días; las 30
semillas y las tres dificultades, a mano). Con --visual, además smoke (capturas con ventana, por
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
    ("ciudad", [sys.executable, "tools/city/ciudad.py", "validar", "--quiet"]),
    ("boot", ["zsh", "tools/qa/boot_check.sh"]),
    ("bench", G + ["-s", "tools/sim_bench.gd"]),
    ("sim", G + ["-s", "tools/sim_runner.gd", "--", "--bots=idle,wanderer,smith", "--days=3", "--seeds=5"]),
    ("sim2", G + ["-s", "tools/sim_runner.gd", "--", "--bots=random_clicker,idle_rival", "--days=10", "--seeds=3"]),
    ("novice", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=artisan_novice,idle",
                    "--days=10", "--seeds=10"]),
    ("expert", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=artisan_expert",
                    "--days=12", "--seeds=2"]),
    ("town", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=town_microevents", "--bots=idle_town", "--days=30",
                  "--seeds=2"]),
    ("kin", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=kin_trader", "--bots=kin_trader", "--days=2",
                 "--seeds=3"]),
    ("events", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=events", "--days=80",
                    "--seeds=2"]),
] + [(p, G + ["-s", "tools/sim_runner.gd", "--", f"--start=artisan_{p}", f"--bots={p}_novice", "--days=10", "--seeds=10"])
     for p in ("carpenter", "mason", "tailor")]
VISUAL = [("smoke", ["grimoire", "heavy", "--timeout", "3m", "--", GODOT, "--audio-driver", "Dummy", "--always-on-top", "--path", ROOT,
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
