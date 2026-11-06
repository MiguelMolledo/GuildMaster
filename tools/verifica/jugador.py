#!/usr/bin/env python3
"""La pasada de jugador por la interfaz: el primer año de la partida por defecto, jugado como un jugador nuevo con el
tutorial, por bloques cortos (data/flows/jugador/NN_*.json, en orden). Cada bloque es un flujo del conductor de
interfaz (game/smoke/flow/); todos van en la misma sesión de juego (un solo Godot: el bloque 2 y los siguientes
empiezan con start {"keep": true}, la partida como la dejó el anterior). Ajustes y partidas en tmp/jugador_home
(limpio en cada pasada: un jugador nuevo).

  python3 tools/verifica/jugador.py [--window] [--from=N] [--to=N] [--timeout=S]

Con --window la sesión va por la cola de `grimoire heavy` (una ventana a la vez). Escribe reports/jugador/<fecha>/: por
bloque su result.json y sus capturas, y ritmo.json (los tramos sin decisión, medidos como 03b §3b.6).
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verifica  # noqa: E402

ROOT = verifica.ROOT
FLOWS = os.path.join(ROOT, "data", "flows", "jugador")
HOME = os.path.join(ROOT, "tmp", "jugador_home")
REAL_S_PER_GAME_MIN = 300.0 / 1440.0   # 03b: 1 día = 5 min reales a ×1


def blocks():
    return sorted(f[:-5] for f in os.listdir(FLOWS) if f.endswith(".json"))


def pacing(out_dir, ids):
    """Los tramos sin decisión: pasos que solo esperan (sin clic ni tecla del jugador), en segundos reales a la
    velocidad que llevaba el juego. Juntados mientras no hay decisión entre medias."""
    rows = []
    run = None
    for b in ids:
        p = os.path.join(out_dir, "jugador", b, "result.json")
        if not os.path.exists(p):
            continue
        with open(p, encoding="utf-8") as f:
            res = json.load(f)
        for s in res.get("steps", []):
            acts = [x for x in s.get("input", []) if str(x.get("kind", x.get("type", ""))) not in ("move",)]
            mins = int(s.get("game_minutes", 0))
            speed = max(1, int(s.get("speed", 1)))
            secs = mins * REAL_S_PER_GAME_MIN / speed
            if not acts and mins > 0:
                if run is None:
                    run = {"block": b, "from": s["id"], "to": s["id"], "clock": s.get("clock", ""), "minutes": 0,
                           "seconds": 0.0, "why": []}
                run["to"] = s["id"]
                run["minutes"] += mins
                run["seconds"] += secs
                if s.get("say"):
                    run["why"].append(s["say"])
            else:
                if run is not None and run["seconds"] > 0:
                    rows.append(run)
                run = None
    if run is not None:
        rows.append(run)
    for r in rows:
        r["seconds"] = round(r["seconds"], 1)
    return rows


def main():
    args = sys.argv[1:]
    window = "--window" in args
    first = 1
    last = 999
    timeout = 900
    for a in args:
        if a.startswith("--from="):
            first = int(a[7:])
        elif a.startswith("--to="):
            last = int(a[5:])
        elif a.startswith("--timeout="):
            timeout = int(a[10:])
    date = datetime.date.today().isoformat()
    out_dir = os.path.join(ROOT, "reports", "jugador", date)
    os.makedirs(out_dir, exist_ok=True)
    if os.path.isdir(HOME):
        shutil.rmtree(HOME)
    os.makedirs(HOME, exist_ok=True)
    ids = [b for b in blocks() if first <= int(b.split("_")[0]) <= last]
    flows = ",".join("jugador/" + b for b in ids)
    game = [verifica.GODOT, "--audio-driver", "Dummy"] + (["--always-on-top"] if window else ["--headless"]) + \
        ["--path", ROOT, "--", f"--flows={flows}", "--seed=11", f"--verifica-out={out_dir}", f"--flow-timeout={timeout}"]
    cmd = ["env", f"HOME={HOME}"] + game
    total = timeout * len(ids)
    if window:
        cmd = ["grimoire", "heavy", "--timeout", f"{int(total / 60) + 5}m", "--"] + cmd
    os.makedirs(os.path.join(out_dir, "jugador"), exist_ok=True)
    log_path = os.path.join(out_dir, "jugador", "godot.log")
    t0 = time.time()
    with open(log_path, "w", encoding="utf-8") as log:
        try:
            rc = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=total + 600).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    with open(log_path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    for l in lines:
        if l.startswith("[Flow] === jugador/") and (" OK " in l or " FALLA " in l):
            print("  " + l[10:], flush=True)
    errors = [l for l in lines if l.startswith("SCRIPT ERROR") or l.startswith("ERROR")]
    print(f"jugador: {time.time() - t0:.0f} s, salida {rc}, {len(errors)} errores del motor", flush=True)
    ok = rc == 0
    runs = pacing(out_dir, blocks())
    with open(os.path.join(out_dir, "ritmo.json"), "w", encoding="utf-8") as f:
        json.dump(runs, f, ensure_ascii=False, indent=2)
    long_runs = [r for r in runs if r["seconds"] > 30]
    print(f"jugador: {len(runs)} tramos sin decisión, {len(long_runs)} de más de 30 s -> {out_dir}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
