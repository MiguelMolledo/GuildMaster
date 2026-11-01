#!/usr/bin/env python3
"""uid de las escenas y recursos de texto (.tscn / .tres), lo mismo que «Proyecto → Herramientas → Actualizar archivos
del proyecto» de Godot, sin abrir el editor.

  python3 tools/uids.py           lista lo que falta (sale con 1 si falta algo)
  python3 tools/uids.py --fix     pone el uid que falte: en la cabecera de cada .tscn/.tres (uno nuevo) y en cada
                                  ext_resource (el del fichero al que apunta: su cabecera, su .uid o su .import)

Con uid, Godot encuentra el recurso aunque se mueva o se renombre (en el panel FileSystem de Godot). Tras --fix,
pasa `godot --headless --path . --import` para que Godot refresque su caché. Se saltan .godot/ y las carpetas
con .gdignore. Un script sin .uid (recién creado) lo recibe con ese --import: pásalo antes de --fix.
"""
import os
import re
import secrets
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADER_RE = re.compile(r'^\[(gd_scene|gd_resource)\b([^\]]*)\]')
EXT_RE = re.compile(r'^\[ext_resource\b([^\]]*)\]$')
UID_ATTR_RE = re.compile(r'\buid="(uid://[a-z0-9]+)"')
PATH_ATTR_RE = re.compile(r'\bpath="(res://[^"]+)"')
CHARS = "abcdefghijklmnopqrstuvwxy012345678"  # ResourceUID::id_to_text: base 34 (a-y, then 0-8)


def new_uid():
    """Un uid nuevo con el formato de Godot (id aleatorio de 63 bits en base 34)."""
    n = secrets.randbits(63) or 1
    out = ""
    while n:
        out = CHARS[n % len(CHARS)] + out
        n //= len(CHARS)
    return "uid://" + out


def text_files(root=ROOT):
    """Las .tscn y .tres del proyecto (sin .godot/ ni carpetas con .gdignore), rutas relativas."""
    out = []
    for d, dirs, files in os.walk(root):
        rel = os.path.relpath(d, root)
        if os.path.exists(os.path.join(d, ".gdignore")) or rel.split(os.sep)[0] in (".godot", ".git"):
            dirs[:] = []
            continue
        dirs.sort()
        for f in sorted(files):
            if f.endswith((".tscn", ".tres")):
                out.append(os.path.normpath(os.path.join(rel, f)))
    return out


def header_uid(path):
    """El uid de la cabecera de una .tscn/.tres ("" si no tiene)."""
    try:
        with open(path, encoding="utf-8") as f:
            m = HEADER_RE.match(f.readline())
    except OSError:
        return ""
    u = UID_ATTR_RE.search(m.group(2)) if m else None
    return u.group(1) if u else ""


def target_uid(res_path, root=ROOT):
    """El uid del recurso al que apunta un ext_resource: su cabecera (.tscn/.tres), su .uid (scripts) o su .import."""
    p = os.path.join(root, res_path.replace("res://", "", 1))
    if p.endswith((".tscn", ".tres")):
        return header_uid(p)
    for side in (p + ".uid", p + ".import"):
        if os.path.exists(side):
            with open(side, encoding="utf-8") as f:
                m = UID_ATTR_RE.search(f.read()) if side.endswith(".import") else re.match(r"(uid://[a-z0-9]+)", f.read())
            if m:
                return m.group(1)
    return ""


def problems(root=ROOT):
    """[(fichero, qué falta)] de todas las .tscn/.tres."""
    out = []
    for rel in text_files(root):
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            lines = f.read().split("\n")
        if not HEADER_RE.match(lines[0]):
            out.append((rel, "no es una escena/recurso de texto de Godot"))
            continue
        if not UID_ATTR_RE.search(lines[0]):
            out.append((rel, "la cabecera no tiene uid"))
        for ln in lines:
            m = EXT_RE.match(ln)
            if m and not UID_ATTR_RE.search(m.group(1)):
                p = PATH_ATTR_RE.search(m.group(1))
                out.append((rel, f"ext_resource sin uid: {p.group(1) if p else ln}"))
    return out


def fix(root=ROOT):
    """Pone los uid que falten. Devuelve [(fichero, qué se hizo)] y [(fichero, lo que no se pudo)]."""
    done, failed = [], []
    files = text_files(root)
    for rel in files:  # 1) cabeceras: cada escena/recurso con su uid propio
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        first, rest = text.split("\n", 1) if "\n" in text else (text, "")
        m = HEADER_RE.match(first)
        if m and not UID_ATTR_RE.search(first):
            first = first[:-1] + f' uid="{new_uid()}"]'
            with open(path, "w", encoding="utf-8") as f:
                f.write(first + "\n" + rest)
            done.append((rel, "cabecera"))
    for rel in files:  # 2) ext_resource: el uid del fichero al que apuntan
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        changed = False
        for i, ln in enumerate(lines):
            m = EXT_RE.match(ln)
            if not m or UID_ATTR_RE.search(m.group(1)):
                continue
            p = PATH_ATTR_RE.search(m.group(1))
            uid = target_uid(p.group(1), root) if p else ""
            if not uid:
                failed.append((rel, f"sin uid conocido para {p.group(1) if p else ln}"))
                continue
            lines[i] = ln.replace(f' path="{p.group(1)}"', f' uid="{uid}" path="{p.group(1)}"', 1)
            changed = True
        if changed:
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
            done.append((rel, "ext_resource"))
    return done, failed


def main(argv):
    if "--fix" in argv:
        done, failed = fix()
        for rel, what in done:
            print(f"  uid: {rel} ({what})")
        for rel, what in failed:
            print(f"  ✖ {rel}: {what}")
    left = problems()
    for rel, what in left:
        print(f"  ✖ {rel}: {what}")
    print(f"uids: {len(text_files())} escenas/recursos, {len(left)} sin uid")
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
