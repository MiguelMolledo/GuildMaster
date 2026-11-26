#!/usr/bin/env python3
"""El kit 3D en el repo (docs/3d/plan.md §5): en git solo lo que el juego carga; los packs completos, por script.

  python3 tools/kit3d/kit.py recoger [--rapido]      corre el juego sin ventana con --verbose (partida nueva y cada
                                                     escenario) y guarda los registros en tmp/kit3d/logs/
  python3 tools/kit3d/kit.py usados [logs...]        de los registros (por defecto tmp/kit3d/logs/*.log) saca cada
                                                     fichero de kit/ que el motor cargó, cierra sus dependencias
                                                     (.bin e imágenes de cada .gltf, los .import) y añade los catálogos
                                                     (kit/**/*.json): escribe tools/kit3d/usados.txt
  python3 tools/kit3d/kit.py medir                   ficheros y MB de usados.txt y del kit entero; falla si alguno
                                                     pasa de 50 MB
  python3 tools/kit3d/kit.py sellar                  git add -f de usados.txt (kit/ está en .gitignore); lo que ya no
                                                     se usa queda fuera de git (git rm --cached)
  python3 tools/kit3d/kit.py instalar [--desde=DIR]  copia los packs completos a kit/ (por defecto desde
                                                     ~/Code/Prueba3D/kit) sin pisar lo sellado

La lista usados.txt es la que manda: lo que no está en ella no entra en git.
"""
import glob
import json
import os
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KIT = os.path.join(ROOT, "kit")
USADOS = os.path.join(ROOT, "tools", "kit3d", "usados.txt")
LOGS = os.path.join(ROOT, "tmp", "kit3d", "logs")
GODOT = "/opt/homebrew/bin/godot"
MAX_MB = 50
LOAD_RE = re.compile(r"Loading resource: res://(kit/[^\n]+?)(?: remapped: |\s*$)")


def rel(p):
    return os.path.relpath(p, ROOT)


def recoger(rapido):
    os.makedirs(LOGS, exist_ok=True)
    home = os.path.join(ROOT, "tmp", "kit3d", "home")
    os.makedirs(home, exist_ok=True)
    runs = [("partida_nueva", ["--new-game"]), ("titulo", [])]
    if not rapido:
        for f in sorted(glob.glob(os.path.join(ROOT, "data", "scenarios", "*.json"))):
            n = os.path.basename(f)[:-5]
            if not n.startswith("_"):
                runs.append((n, [f"--scenario={n}"]))
        runs.append(("capital", ["--start-city=capital"]))
    for name, args in runs:
        out = os.path.join(LOGS, f"{name}.log")
        cmd = [GODOT, "--headless", "--verbose", "--path", ROOT, "--quit-after", "120", "--"] + args
        with open(out, "w") as f:
            subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=dict(os.environ, HOME=home), timeout=300)
        print(f"  {name}: {out}")


def gltf_deps(path):
    """Ficheros que un .gltf necesita a su lado: sus buffers y sus imágenes (uris relativas)."""
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return []
    out = []
    for key in ("buffers", "images"):
        for b in d.get(key, []):
            uri = b.get("uri", "")
            if uri and not uri.startswith("data:"):
                out.append(os.path.normpath(os.path.join(os.path.dirname(path), unquote(uri))))
    return out


def usados(logs):
    logs = logs or sorted(glob.glob(os.path.join(LOGS, "*.log")))
    if not logs:
        sys.exit("kit.py usados: no hay registros (python3 tools/kit3d/kit.py recoger)")
    seen = set()
    for lg in logs:
        with open(lg, errors="ignore") as f:
            for m in LOAD_RE.finditer(f.read()):
                seen.add(os.path.join(ROOT, m.group(1).strip()))
    todo = list(seen)
    files = set()
    while todo:
        p = todo.pop()
        if p in files or not os.path.isfile(p):
            continue
        files.add(p)
        if os.path.isfile(p + ".import"):
            files.add(p + ".import")
        if p.endswith(".gltf"):
            todo.extend(gltf_deps(p))
    for p in glob.glob(os.path.join(KIT, "**", "*.json"), recursive=True):
        files.add(p)
    for p in glob.glob(os.path.join(KIT, "**", ".gdignore"), recursive=True):
        files.add(p)
    missing = sorted(p for p in seen if not os.path.isfile(p))
    with open(USADOS, "w") as f:
        f.write("".join(rel(p) + "\n" for p in sorted(files)))
    print(f"kit.py usados: {len(seen)} cargados en {len(logs)} registros -> {len(files)} ficheros en {rel(USADOS)}")
    for p in missing[:20]:
        print(f"  ! cargado pero no está en disco: {rel(p)}")


def lista():
    if not os.path.isfile(USADOS):
        sys.exit("kit.py: falta tools/kit3d/usados.txt (python3 tools/kit3d/kit.py usados)")
    with open(USADOS) as f:
        return [l.strip() for l in f if l.strip()]


def medir():
    files = lista()
    total = 0
    big = []
    by_dir = {}
    for r in files:
        p = os.path.join(ROOT, r)
        s = os.path.getsize(p) if os.path.isfile(p) else 0
        total += s
        d = "/".join(r.split("/")[:2])
        by_dir[d] = by_dir.get(d, 0) + s
        if s > MAX_MB * 1e6:
            big.append((r, s))
    full = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(KIT) for f in fs)
    print(f"kit.py medir: {len(files)} ficheros, {total / 1e6:.1f} MB en git (kit entero en disco: {full / 1e6:.1f} MB)")
    for d, s in sorted(by_dir.items(), key=lambda x: -x[1]):
        print(f"  {d:<28} {s / 1e6:8.1f} MB")
    for r, s in big:
        print(f"  ! {r}: {s / 1e6:.1f} MB (más de {MAX_MB} MB)")
    return 1 if big else 0


def sellar():
    files = lista()
    if medir():
        sys.exit("kit.py sellar: hay ficheros de más de 50 MB")
    for i in range(0, len(files), 200):
        subprocess.run(["git", "-C", ROOT, "add", "-f", "--"] + files[i:i + 200], check=True)
    tracked = subprocess.run(["git", "-C", ROOT, "ls-files", "kit"], capture_output=True, text=True).stdout.split("\n")
    keep = set(files)
    gone = [t for t in tracked if t and t not in keep]
    for i in range(0, len(gone), 200):
        subprocess.run(["git", "-C", ROOT, "rm", "--cached", "-q", "--"] + gone[i:i + 200], check=True)
    print(f"kit.py sellar: {len(files)} ficheros en el índice, {len(gone)} fuera")


def instalar(src):
    src = os.path.expanduser(src)
    if not os.path.isdir(src):
        sys.exit(f"kit.py instalar: no existe {src}")
    subprocess.run(["rsync", "-a", "--ignore-existing", src.rstrip("/") + "/", KIT + "/"], check=True)
    print(f"kit.py instalar: {src} -> kit/ (sin pisar lo que ya había); después: godot --headless --path . --import")


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    if cmd == "recoger":
        recoger("--rapido" in rest)
    elif cmd == "usados":
        usados(rest)
    elif cmd == "medir":
        return medir()
    elif cmd == "sellar":
        sellar()
    elif cmd == "instalar":
        src = next((a.split("=", 1)[1] for a in rest if a.startswith("--desde=")), "~/Code/Prueba3D/kit")
        instalar(src)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
