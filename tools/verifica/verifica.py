#!/usr/bin/env python3
"""Verificación de una rama por la interfaz (docs/gdd/07_testing.md §7.6).

Juega los flujos de data/flows/ con eventos reales de ratón y teclado (game/smoke/flow/), un proceso de Godot por
flujo, y escribe el informe para revisar reports/verifica/<fecha>/index.html (+ artifact en Grimoire con --artifact).

  python3 tools/verifica/verifica.py [--flows=all|quick|a,b] [--window] [--report-only] [--artifact]
                                     [--sim-dir=<reports/sim de otra copia>] [--timeout=<s por flujo>]

  --window       con ventana y capturas (cada flujo por la cola de `grimoire heavy`, uno a la vez); sin él, sin
                 ventana: los mismos pasos y comprobaciones, sin capturas ni contraste.
  --flows=quick  los flujos marcados "quick" (primer día, contratar y cola, deuda, guardar y cargar): el paso `ui`
                 de tools/qa/run_all.py. --flows=all es el modo completo (para la noche).
  --keys / --both  los mismos flujos con el teclado (cada clic sobre un control: Tab hasta él y Enter; el mapa y las
                 salas siguen siendo del ratón), solos o además de los de ratón: la cobertura por teclado.
  --report-only  no juega: rehace el informe con los result.json que haya.
  --artifact     registra el informe en Grimoire (artifact.create; HTML con miniaturas por debajo de ~0,9 MB).

Sale con 1 si algún flujo falla. Los ajustes y partidas guardadas van a tmp/verifica_home (no toca los del owner).
"""
import datetime
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = "/opt/homebrew/bin/godot"
HOME = os.path.join(ROOT, "tmp", "verifica_home")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import report  # noqa: E402


def flow_ids(which):
    d = os.path.join(ROOT, "data", "flows")
    ids = sorted(f[:-5] for f in os.listdir(d) if f.endswith(".json") and not f.startswith("_"))
    if which == "all":
        return ids
    if which == "quick":
        out = []
        for i in ids:
            with open(os.path.join(d, i + ".json"), encoding="utf-8") as f:
                if json.load(f).get("quick"):
                    out.append(i)
        return out
    return [x for x in which.split(",") if x]


def run_flow(fid, window, out_dir, timeout, keys=False):
    """One Godot process for one flow. Returns (returncode, seconds, log tail)."""
    os.makedirs(HOME, exist_ok=True)
    os.makedirs(os.path.join(out_dir, fid), exist_ok=True)
    game = [GODOT, "--audio-driver", "Dummy"] + (["--always-on-top"] if window else ["--headless"]) + \
        ["--path", ROOT, "--", f"--flow={fid}", f"--verifica-out={out_dir}", f"--flow-timeout={timeout}"] + \
        (["--flow-input=keys"] if keys else [])
    cmd = ["env", f"HOME={HOME}"] + game
    if window:
        cmd = ["grimoire", "heavy", "--timeout", f"{int(timeout / 60) + 2}m", "--"] + cmd
    t0 = time.time()
    sub = fid + ("__teclado" if keys else "")
    os.makedirs(os.path.join(out_dir, sub), exist_ok=True)
    log_path = os.path.join(out_dir, sub, "godot.log")
    with open(log_path, "w", encoding="utf-8") as log:
        try:
            p = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=timeout + 240)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            rc = 124
    with open(log_path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    errors = [l for l in lines if l.startswith("SCRIPT ERROR") or l.startswith("ERROR")]
    if errors:
        res_path = os.path.join(out_dir, sub, "result.json")
        if os.path.exists(res_path):
            with open(res_path, encoding="utf-8") as f:
                res = json.load(f)
            res["engine_errors"] = errors[:20]
            with open(res_path, "w", encoding="utf-8") as f:
                json.dump(res, f, ensure_ascii=False, indent=1)
    tail = [l for l in lines if l.startswith("[Flow] ===")][-1:] or lines[-1:] or [""]
    return rc, time.time() - t0, tail[0]


def main(argv):
    which = next((a[8:] for a in argv if a.startswith("--flows=")), "all")
    window = "--window" in argv
    timeout = float(next((a[10:] for a in argv if a.startswith("--timeout=")), "600"))
    sim_dir = next((a[10:] for a in argv if a.startswith("--sim-dir=")), os.path.join(ROOT, "reports", "sim"))
    date = datetime.date.today().isoformat()
    out_dir = os.path.join(ROOT, "reports", "verifica", date)
    os.makedirs(out_dir, exist_ok=True)
    failed = 0
    if "--report-only" not in argv:
        ids = flow_ids(which)
        print(f"verifica: {len(ids)} flujos {'con ventana' if window else 'sin ventana'} -> {out_dir}")
        keys = "--keys" in argv or "--both" in argv
        mouse = "--keys" not in argv
        for fid in ids:
            for k in ([False] if mouse else []) + ([True] if keys else []):
                rc, secs, tail = run_flow(fid, window, out_dir, timeout, k)
                bad = rc != 0
                failed += bad
                name = fid + (" (teclado)" if k else "")
                print(f"  {'FALLA' if bad else 'ok   '} {name:<30} {secs:6.1f} s  {tail[:100]}")
    path, size = report.build(out_dir, sim_dir)
    print(f"verifica: informe {path} ({size / 1024:.0f} KB)")
    if "--artifact" in argv:
        report.publish(out_dir)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
