#!/usr/bin/env python3
"""Corre todos los rituales que existen (GDD 07 §7.1) y escribe un informe.

  python3 tools/qa/run_all.py [--only=a,b] [--skip=a,b] [--visual] [--night]

Pasos: tests (reglas), content (validador), art (inventario), ciudad (coherencia de los mapas, tools/city/), town_e (tools/maps/make_town_e.py --check: el script reproduce el mapa y su escenario), boot (arranque sin ventana con cada escenario),
bench (coste del sim), sim (bots contra data/targets.json en el arenero), sim2 (random_clicker e idle_rival a 10 días),
novice (partida nueva real en Normal: artisan_novice e idle, 10 semillas: con 5 la media del novato queda al borde
de su diana por ruido de semillas; las 30 semillas y las tres dificultades se
corren a mano, ver CLAUDE.md), expert (H5: artisan_expert en una partida nueva real, versión corta de 2 semillas × 12
días; las dianas goldflow de días 9-24 se corren a mano con 30 semillas), town (H7: microeventos y mostrador en 30 días,
idle_town, 2 semillas), kin (H14: un familiar con Comerciar aprovisiona la forja, 3 semillas), events (H13: 10 años,
80 días, de artisan_expert con estaciones y eventos globales, sin bloqueos; 2 semillas), carpenter / mason /
tailor (H12: el novato de cada oficio del Artesano en su partida nueva real en Normal, 10 semillas × 10 días; las 30
semillas y las tres dificultades, a mano), rogue (H12: el ladrón del Pícaro, rogue_novice en su partida nueva, 10 semillas × 10 días), spy (H12: el espía del Pícaro, spy_novice en rogue_spy, 10 semillas × 10 días), scholar (H12.2: el médico del Erudito, scholar_novice en su partida nueva,
10 semillas × 10 días), cast (población: el novato con repartos generados, --cast=random, 10
semillas × 10 días; las demás pasos de partida nueva usan el reparto fijo), duel (duelo: el bot duelista desde
duel_ready, 3 semillas × 8 días), merchant (viajes: el bot comerciante en travel_start, 10 semillas × 16 días), gambler (juegos: el bot jugador en
games_gambler, 3 semillas × 8 días: pierde lo que marca el margen de la casa), life
(vida, 04f 4.28.4: el bot guard_watch en life_bandits, 3 semillas × 16 días; las dianas de antes corren con la vida
apagada, data/targets.json _no_life), festive (fiestas: un año con el calendario de fiestas, 3 semillas × 8 días), fest_ai
(idle_titles_fest: el año 1 con fiestas, ninguna familia IA más de 2 días sin oro, 5 semillas) y
bench_fair (el coste del sim el día de la feria), full y chaos (07 §7.4: el jugador completo y el caótico con todo
encendido, 1 año y 1 semilla; las corridas largas, de noche con tools/qa/noche.py), full_html (su resumen), inn
(posada: el bot posadero en innkeeper_start, 5 semillas × 16 días), broke (equilibrio: la forja sin blanca de
broke_forge sale con el préstamo de urgencia, 3 semillas × 6 días), counter (equilibrio: el mostrador con un
empleado y la clientela de comarca, 3 semillas × 24 días) y ui (los flujos "quick" de data/flows jugados por
la interfaz con ratón y teclado, con ventana, cada uno por `grimoire heavy`: 07 §7.6; con --night, todos los flujos y
el informe en Grimoire). Con
--visual, además smoke (capturas con ventana, por
`grimoire heavy`). Escribe reports/qa/QA.md y los logs en reports/qa/logs/. Sale con 1 si algún paso falla.
bench y bench_fair (coste del sim): si uno falla, se repite una vez al final; si la repetición pasa, queda «ok (repetido)»
con las dos medidas en su log y en QA.md (con la máquina cargada fallan sin regresión real); si vuelve a fallar, falla.
"""
import os
import re
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
    ("town_e", [sys.executable, "tools/maps/make_town_e.py", "--check"]),
    ("boot", ["zsh", "tools/qa/boot_check.sh"]),
    ("bench", G + ["-s", "tools/sim_bench.gd", "--", "--runs=3"]),  # best of 3 per step: the machine is shared by several QA runs
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
     for p in ("carpenter", "mason", "tailor")] + [
    ("scholar", G + ["-s", "tools/sim_runner.gd", "--", "--start=scholar_physician", "--bots=scholar_novice", "--days=10",
                     "--seeds=10"]),
    ("rogue", G + ["-s", "tools/sim_runner.gd", "--", "--start=rogue_thief", "--bots=rogue_novice", "--days=10",
                   "--seeds=10"]),
    ("spy", G + ["-s", "tools/sim_runner.gd", "--", "--start=rogue_spy", "--bots=spy_novice", "--days=10",
                 "--seeds=10"]),
] + [
    ("cast", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=artisan_novice", "--days=10",
                  "--seeds=10", "--cast=random", "--tag=cast_random"]),
    ("duel", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=duel_ready", "--bots=duelist", "--days=8", "--seeds=3"]),
    ("merchant", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=travel_start", "--bots=merchant", "--days=16",
                      "--seeds=10"]),
    ("pacing", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=pacing", "--days=8",
                    "--seeds=5"]),
    ("gambler", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=games_gambler", "--bots=gambler", "--days=8",
                     "--seeds=3"]),
    ("life", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=life_bandits", "--bots=guard_watch", "--days=16",
                  "--seeds=3"]),
    ("festive", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=festive", "--days=8",
                     "--seeds=3"]),
    ("fest_ai", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=idle_titles_fest",
                     "--days=8", "--seeds=5"]),
    ("bench_fair", G + ["-s", "tools/sim_bench.gd", "--", "--at-day=3", "--days=1", "--runs=3"]),
    ("inn", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=innkeeper_start", "--bots=innkeeper", "--days=16",
                 "--seeds=5"]),
    ("broke", G + ["-s", "tools/sim_runner.gd", "--", "--scenario=broke_forge", "--bots=broke", "--days=6",
                   "--seeds=3"]),  # equilibrio (Equilibrio 2): the emergency loan gets a broke forge going again
    ("counter", G + ["-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith", "--bots=counter_shop",
                     "--days=24", "--seeds=3"]),  # equilibrio (Equilibrio 8, 14): the counter and the comarca's clientele
    ("full", G + ["-s", "tools/full_player.gd", "--", "--years=1", "--seed-list=1", "--tag=qa"]),
    ("chaos", G + ["-s", "tools/full_player.gd", "--", "--bot=chaos_player", "--years=1", "--seed-list=1", "--tag=qa"]),
    ("full_html", [sys.executable, "tools/full_report.py", "reports/full_player_qa", "reports/chaos_player_qa"]),
]
# The interface (docs/gdd/07_testing.md §7.6): the "quick" flows played with real mouse and keyboard events, with a
# window, each one through the queue of `grimoire heavy`; --night plays every flow and publishes the report.
UI = [("ui", [sys.executable, "tools/verifica/verifica.py", "--window", "--flows=quick", "--timeout=300"])]
NIGHT = [("ui_all", [sys.executable, "tools/verifica/verifica.py", "--window", "--flows=all", "--both", "--artifact"])]
VISUAL = [("smoke", ["grimoire", "heavy", "--timeout", "3m", "--", GODOT, "--audio-driver", "Dummy", "--always-on-top", "--path", ROOT,
                     "--", "--smoke", "--shots=2", "--shot-every=2"])]


# The timing steps: with the machine loaded (several QA runs at once) they can miss their mark with no real regression.
# One that fails is run once more at the end of the run; if that one passes, the step is «ok (repetido)» with both
# measures in its log and in QA.md; if it fails again, it fails. Only these steps.
RETRY_ONCE = ("bench", "bench_fair")


def _measure(out):
    """La medida de un paso de coste («mean 1.44 ms, p99 5.89 ms, worst 19.2 ms»), o "" si no la hay."""
    m = re.search(r"mean [0-9.]+ ms, p99 [0-9.]+ ms, worst [0-9.]+ ms", out)
    return m.group(0) if m else ""


def _run(name, cmd, env):
    t0 = time.time()
    p = subprocess.run(cmd, cwd=ROOT, env=env if cmd[0] == GODOT else None, capture_output=True, text=True)
    out = p.stdout + p.stderr
    bad = p.returncode != 0 or (cmd[0] == GODOT and ("SCRIPT ERROR" in out or "\nERROR" in out))
    last = [l for l in out.strip().splitlines() if l.strip() and not l.startswith("[")][-1:] or [""]
    return out, bad, time.time() - t0, last[0]


def main(argv):
    only = next((a[7:].split(",") for a in argv if a.startswith("--only=")), None)
    skip = next((a[7:].split(",") for a in argv if a.startswith("--skip=")), [])
    steps = STEPS + (NIGHT if "--night" in argv else UI) + (VISUAL if "--visual" in argv else [])
    os.makedirs(os.path.join(ROOT, "reports", "qa", "logs"), exist_ok=True)
    os.makedirs(HOME, exist_ok=True)
    env = dict(os.environ, HOME=HOME)
    rows, failed, again = [], 0, []
    for name, cmd in steps:
        if (only and name not in only) or name in skip:
            continue
        out, bad, secs, last = _run(name, cmd, env)
        with open(os.path.join(ROOT, "reports", "qa", "logs", name + ".log"), "w", encoding="utf-8") as f:
            f.write(out)
        if bad and name in RETRY_ONCE:
            again.append((name, cmd, out, secs, last))
            rows.append((name, "repetir", f"{secs:.1f} s", last[:140]))
            print(f"  ¿?    {name:<8} {secs:>6.1f} s  {last[:110]} (se repite al final)")
            continue
        failed += bad
        rows.append((name, "FALLA" if bad else "ok", f"{secs:.1f} s", last[:140]))
        print(f"  {'FALLA' if bad else 'ok   '} {name:<8} {rows[-1][2]:>7}  {last[:110]}")
    for name, cmd, out1, secs1, last1 in again:
        out2, bad, secs2, last2 = _run(name, cmd, env)
        m1, m2 = _measure(out1) or last1, _measure(out2) or last2
        with open(os.path.join(ROOT, "reports", "qa", "logs", name + ".log"), "w", encoding="utf-8") as f:
            f.write(f"# 1.ª corrida (falló): {m1}\n# 2.ª corrida ({'falló' if bad else 'pasó'}): {m2}\n\n"
                    f"## 1.ª corrida\n{out1}\n## 2.ª corrida\n{out2}")
        failed += bad
        i = next(k for k, r in enumerate(rows) if r[0] == name)
        rows[i] = (name, "FALLA" if bad else "ok (repetido)", f"{secs1:.1f} + {secs2:.1f} s", f"1.ª {m1} · 2.ª {m2}"[:200])
        print(f"  {'FALLA' if bad else 'ok (repetido)'} {name:<8} 1.ª {m1} · 2.ª {m2}")
    md = ["# QA", "", "| Paso | Resultado | Tiempo | Última línea |", "|---|---|---|---|"]
    md += [f"| {a} | {b} | {c} | `{d}` |" for a, b, c, d in rows]
    with open(os.path.join(ROOT, "reports", "qa", "QA.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print("qa: todo bien" if not failed else f"qa: {failed} pasos fallan")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
