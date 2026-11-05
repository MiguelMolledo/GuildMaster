#!/usr/bin/env python3
"""Las corridas largas del jugador completo y del caótico, para la noche (docs/gdd/07_testing.md §7.4).

  python3 tools/qa/noche.py [--seeds=5] [--gen-seeds=2] [--chaos-seeds=3] [--skip=full,gen,chaos]

full:  full_player 3 años × --seeds semillas        → reports/full_player/
gen:   full_player una generación × --gen-seeds      → reports/full_player_generation/ (la muerte del fundador y la herencia)
chaos: chaos_player 3 años × --chaos-seeds           → reports/chaos_player/ (guarda y carga cada día)
Después, el resumen HTML de cada carpeta (tools/full_report.py) y reports/qa/noche.md. Sin ventana: no hace falta
`grimoire heavy`, pero son horas de CPU (una generación ≈ 25-40 min por semilla): mejor de noche y sola.
Sale con 1 si alguna corrida falla sus dianas (data/targets.json full_player / chaos_player).
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = "/opt/homebrew/bin/godot"
G = [GODOT, "--headless", "--path", ROOT, "-s", "tools/full_player.gd", "--"]


def opt(argv, name, default):
    return next((a.split("=", 1)[1] for a in argv if a.startswith(f"--{name}=")), default)


def main(argv):
    seeds = int(opt(argv, "seeds", "5"))
    gen = int(opt(argv, "gen-seeds", "2"))
    chaos = int(opt(argv, "chaos-seeds", "3"))
    skip = opt(argv, "skip", "").split(",")
    runs = [("full", G + ["--years=3", f"--seeds={seeds}"], "reports/full_player"),
            ("gen", G + ["--generation", f"--seeds={gen}", "--tag=generation"], "reports/full_player_generation"),
            ("chaos", G + ["--bot=chaos_player", "--years=3", f"--seeds={chaos}"], "reports/chaos_player")]
    os.makedirs(os.path.join(ROOT, "reports", "qa", "logs"), exist_ok=True)
    rows, failed = [], 0
    for name, cmd, out in runs:
        if name in skip:
            continue
        t0 = time.time()
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                           env=dict(os.environ, HOME=os.path.join(ROOT, "tmp", "qa_home")))
        text = p.stdout + p.stderr
        with open(os.path.join(ROOT, "reports", "qa", "logs", f"noche_{name}.log"), "w", encoding="utf-8") as f:
            f.write(text)
        subprocess.run([sys.executable, "tools/full_report.py", out], cwd=ROOT)
        bad = p.returncode != 0 or "SCRIPT ERROR" in text
        failed += bad
        last = [l for l in text.splitlines() if l.startswith("full_player:")][-1:] or [""]
        misses = [l.strip() for l in text.splitlines() if l.strip().startswith("MISS")]
        rows.append((name, "FALLA" if bad else "ok", f"{(time.time() - t0) / 60:.1f} min", last[0][:160], misses))
        print(f"  {'FALLA' if bad else 'ok   '} {name:<6} {rows[-1][2]:>9}  {last[0][:120]}")
    md = ["# Noche: jugador completo y caótico", "", "| Corrida | Resultado | Tiempo | Última línea |", "|---|---|---|---|"]
    md += [f"| {a} | {b} | {c} | `{d}` |" for a, b, c, d, _ in rows]
    for a, _, _, _, m in rows:
        if m:
            md += ["", f"## {a}: dianas fallidas", ""] + [f"- {x}" for x in m]
    md += ["", "Resúmenes: reports/full_player/index.html, reports/full_player_generation/index.html, "
           "reports/chaos_player/index.html."]
    with open(os.path.join(ROOT, "reports", "qa", "noche.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print("noche: todo bien" if not failed else f"noche: {failed} corridas fallan")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
