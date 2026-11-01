#!/usr/bin/env python3
"""Las páginas de Grimoire del juego: docs/paginas.json (título, id y el guion que la hace), en git, en vez de ids
sueltos en reports/ (que no va a git) o escritos en cada guion.

    python3 tools/paginas.py                   la lista: título, id y guion
    python3 tools/paginas.py "<título>"        su id (sale con 1 si no está)
    python3 tools/paginas.py --check           ¿existe cada id en ~/.grimoire/workspace/artifacts? (sale con 1 si falta alguno)

Desde un guion de Python (tools/sim_report.py, tools/net_spike/report.py, tools/design_probe/…):
    import paginas                              # (con tools/ en sys.path)
    aid = paginas.id_de(TITLE, antes=ID_FILE)   # el de docs/paginas.json; si no está, el del fichero de antes
    paginas.guardar(TITLE, aid, "tools/sim_report.py")   # una página nueva: queda apuntada aquí
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "docs", "paginas.json")
ARTIFACTS = os.path.expanduser("~/.grimoire/workspace/artifacts")


def _load() -> dict:
    if not os.path.exists(PATH):
        return {"paginas": []}
    with open(PATH, encoding="utf-8") as f:
        return json.load(f)


def todas() -> list:
    return _load().get("paginas", [])


def id_de(titulo: str, antes: str = "") -> str:
    """El id de la página `titulo` ("" si no hay): el de docs/paginas.json, si no el del fichero `antes`."""
    for p in todas():
        if p.get("titulo") == titulo:
            return p.get("id", "")
    if antes and os.path.exists(antes):
        with open(antes, encoding="utf-8") as f:
            return f.read().strip()
    return ""


def guardar(titulo: str, aid: str, guion: str = "") -> None:
    """Apunta (o pone al día) la página `titulo` con su id y su guion en docs/paginas.json."""
    doc = _load()
    pags = doc.setdefault("paginas", [])
    for p in pags:
        if p.get("titulo") == titulo:
            if p.get("id") == aid and (not guion or p.get("guion") == guion):
                return
            p["id"] = aid
            if guion:
                p["guion"] = guion
            break
    else:
        pags.append({"titulo": titulo, "id": aid, "guion": guion or None})
    tmp = PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    os.replace(tmp, PATH)


def main(argv: list) -> int:
    if "--check" in argv:
        falta = [p for p in todas() if not os.path.isdir(os.path.join(ARTIFACTS, p.get("id", "")))]
        for p in falta:
            print(f"falta {p['id']} · {p['titulo']}")
        print(f"paginas: {len(todas())}, {len(falta)} sin carpeta en {ARTIFACTS}")
        return 1 if falta else 0
    if argv:
        aid = id_de(argv[0])
        if not aid:
            print(f"no hay página «{argv[0]}» en docs/paginas.json", file=sys.stderr)
            return 1
        print(aid)
        return 0
    for p in todas():
        print(f"{p['id']}  {p['titulo']}  ·  {p.get('guion') or 'a mano'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
