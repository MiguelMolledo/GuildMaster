#!/usr/bin/env python3
"""Crea una ficha de contenido desde su plantilla (data/_templates/) y deja lista su clave de texto.

Nunca pisa nada: si el id ya existe, sale con 1 sin escribir. Después valida el contenido y recuerda los pasos del
protocolo (docs/protocolos/).

Uso:
  python3 tools/new_content.py objeto   --id iron_nail --en "Iron nail" --es "Clavo de hierro"
  python3 tools/new_content.py receta   --id forge_nail --en "Forge nails" --es "Forjar clavos"
  python3 tools/new_content.py edificio --id carpentry --en "Carpentry" --es "Carpintería"
(también en inglés: item, recipe, building)  Opciones: --dry-run
"""
import argparse
import csv
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TYPES = {"objeto": "item", "item": "item", "receta": "recipe", "recipe": "recipe",
         "edificio": "building", "building": "building"}
FOLDER = {"item": "items", "recipe": "recipes", "building": "buildings"}
PROTOCOL = {"item": "crear-objeto.md", "recipe": "crear-receta.md", "building": "crear-edificio.md"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tipo", choices=sorted(TYPES))
    ap.add_argument("--id", required=True)
    ap.add_argument("--en", default="")
    ap.add_argument("--es", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    kind = TYPES[a.tipo]
    if not re.match(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$", a.id):
        print(f"el id «{a.id}» debe ir en inglés y snake_case")
        return 1
    path = os.path.join(ROOT, "data", FOLDER[kind], a.id + ".json")
    if os.path.exists(path):
        print(f"ya existe {os.path.relpath(path, ROOT)}")
        return 1
    with open(os.path.join(ROOT, "data", "_templates", f"_{kind}.json"), encoding="utf-8") as f:
        card = json.load(f)
    card["id"] = a.id
    card["name_key"] = f"{kind}.{a.id}"
    text = json.dumps(card, ensure_ascii=False, indent=2) + "\n"
    en = a.en or a.id.replace("_", " ").capitalize()
    es = a.es or f"TODO: {en}"
    if a.dry_run:
        print(text)
        print(f"i18n: {card['name_key']},{en},{es}")
        return 0
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    with open(os.path.join(ROOT, "i18n", "strings.csv"), "a", encoding="utf-8", newline="") as f:
        csv.writer(f, lineterminator="\n").writerow([card["name_key"], en, es])
    print(f"creada {os.path.relpath(path, ROOT)} (rellena los TODO de la plantilla)")
    subprocess.call([sys.executable, os.path.join(ROOT, "tools", "validate_content.py"), "--quiet"])
    print(f"\nSiguiente: docs/protocolos/{PROTOCOL[kind]} · registra su arte en assets/inventario.json "
          "· python3 tools/arte.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
