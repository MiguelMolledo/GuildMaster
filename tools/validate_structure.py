#!/usr/bin/env python3
"""Comprobaciones de estructura (docs/protocolos/editar-a-mano.md), llamadas desde tools/validate_content.py:

  - data/ guarda ids y cifras, nunca rutas: error si un JSON de data/ (plantillas incluidas) tiene un texto que es
    una ruta a fichero (res://, uid://, user://, assets/, game/, .png, .ogg, .tscn...). Los textos de las claves que
    empiezan por _ (documentación) no cuentan. Excepciones justificadas, con su motivo: EXCEPTIONS.
  - nombres de assets en minúsculas: assets/art/, assets/audio/ y game/visuals/ (el juego exportado distingue
    mayúsculas aunque macOS no);
  - inventario: un asset en estado >= sprite (audio: >= generado) tiene su fichero, con las mayúsculas exactas;
  - escenas visuales (game/visuals/<tipo>/<id>.tscn): cada edificio tiene la suya; cada edificio con puestos, su
    interior con un Marker2D Stations/<puesto> por puesto (también los que añaden sus mejoras, new_zone) y un nodo
    bajo Upgrades por cada visual.interior_node de su árbol; cada visual.exterior_overlay, un nodo bajo Upgrades de
    la escena exterior; cada tipo con su _generic.tscn; puestos del mercado y tablón con escena (si no, aviso: salen
    con la genérica); los personajes de VisualPaths.character_id;
  - audio: data/audio.json (secciones, buses que existen en default_bus_layout.tres, volumen, música y ambiente por fase,
    ambiente por tipo de edificio que existe, sonidos de eventos y de la UI que existen, paneles que son escenas de
    game/ui/, cooldown_s); un id sin fichero es una nota
    (silencio), con otras mayúsculas, error;
  - uid: cada .tscn/.tres con uid en la cabecera y en cada ext_resource (tools/uids.py).
"""
import json
import os
import re

import uids

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
VISUALS = os.path.join(ROOT, "game", "visuals")
KINDS = ["buildings", "interiors", "stations", "props", "characters"]
CHARACTERS = [f"{r}_{s}" for r in ("artisan", "worker", "townsfolk") for s in ("m", "f")]
AUDIO_SECTIONS = {"music": "Music", "sfx": "Sfx", "ambient": "Ambient", "voice": "Voice"}
AUDIO_EXT = (".ogg", ".wav")
PHASES = ["dawn", "day", "dusk", "night"]
PATH_RE = re.compile(r"^(res|uid|user)://|(^|/)(assets|game|data)/|\.(png|jpe?g|webp|svg|ogg|wav|mp3|tscn|tres|scn|res|gd|"
                     r"gdshader|import|uid|ttf|otf)$", re.IGNORECASE)
# Rutas permitidas dentro de data/, con su motivo: {(carpeta de data/, clave con puntos): "por qué"}.
EXCEPTIONS = {
    ("scenarios", "meta.origin"): "procedencia: la herramienta que generó el escenario; el juego no la carga",
}
NAME_RE = re.compile(r"^[a-z0-9_.\-]+$")
ID_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")


def exists_exact(path):
    """Como os.path.exists pero distinguiendo mayúsculas en cada tramo de la ruta (macOS no lo hace)."""
    rel = os.path.relpath(path, ROOT)
    cur = ROOT
    for part in [p for p in rel.split(os.sep) if p]:
        try:
            names = os.listdir(cur)
        except OSError:
            return False
        if part not in names:
            return False
        cur = os.path.join(cur, part)
    return True


def _json(path, rep):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        rep.error(os.path.relpath(path, ROOT), f"no se puede leer: {e}")
        return None


def check_no_paths(rep):
    for d, dirs, files in os.walk(DATA):
        dirs.sort()
        for f in sorted(files):
            if not f.endswith(".json"):
                continue
            rel = os.path.relpath(os.path.join(d, f), DATA)
            doc = _json(os.path.join(d, f), rep)
            folder = rel.split(os.sep)[0] if os.sep in rel else ""

            def walk(v, where):
                if isinstance(v, dict):
                    for k, x in v.items():
                        if not str(k).startswith("_"):
                            walk(x, f"{where}.{k}")
                elif isinstance(v, list):
                    for i, x in enumerate(v):
                        walk(x, f"{where}[{i}]")
                elif isinstance(v, str) and PATH_RE.search(v) and (folder, where.lstrip(".")) not in EXCEPTIONS:
                    rep.error(f"data/{rel}", f"{where.lstrip('.')} = «{v}» es una ruta a fichero: data/ guarda ids y "
                                             "cifras (la ruta sale del id por convención, game/visuals/visual_paths.gd)")
            walk(doc, "")


def check_names(rep):
    for base in ("assets/art", "assets/audio", "game/visuals"):
        top = os.path.join(ROOT, base)
        for d, dirs, files in os.walk(top):
            dirs.sort()
            for n in dirs + files:
                if n.endswith(".md") or n.startswith("."):
                    continue
                if not NAME_RE.match(n):
                    rep.error(os.path.relpath(os.path.join(d, n), ROOT),
                              "nombre con mayúsculas o caracteres raros: usa minúsculas y snake_case (el id)")


def check_inventory(rep):
    inv = _json(os.path.join(ROOT, "assets", "inventario.json"), rep) or {}
    states, audio_states = inv.get("estados", []), inv.get("estados_audio", [])
    for a in inv.get("assets", []):
        audio = a.get("tipo") in inv.get("tipos_audio", [])
        scale = audio_states if audio else states
        st, ruta = a.get("estado"), a.get("ruta") or ""
        if st not in scale:
            continue
        need = scale.index(st) >= scale.index("generado" if audio else "sprite")
        if need and not exists_exact(os.path.join(ROOT, ruta.rstrip("/"))):
            rep.error(f"assets/inventario.json/{a.get('id')}",
                      f"estado {st} pero no existe {ruta} (con esas mayúsculas exactas)")


def _nodes(tscn):
    """[(nombre, tipo, padre)] de los nodos de una .tscn."""
    try:
        with open(tscn, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return []
    out = []
    for m in re.finditer(r'^\[node name="([^"]+)"([^\]]*)\]', text, re.M):
        t = re.search(r'type="([^"]+)"', m.group(2))
        p = re.search(r'parent="([^"]+)"', m.group(2))
        out.append((m.group(1), t.group(1) if t else "", p.group(1) if p else ""))
    return out


def scene(kind, id_):
    return os.path.join(VISUALS, kind, id_ + ".tscn")


def check_visuals(rep):
    for kind in KINDS:
        if not exists_exact(scene(kind, "_generic")):
            rep.error(f"game/visuals/{kind}", "falta _generic.tscn (lo que se ve cuando un id no tiene escena)")
    buildings = {}
    bdir = os.path.join(DATA, "buildings")
    for f in sorted(os.listdir(bdir)) if os.path.isdir(bdir) else []:
        if f.endswith(".json") and not f.startswith("_"):
            b = _json(os.path.join(bdir, f), rep)
            if isinstance(b, dict):
                buildings[b.get("id", f[:-5])] = b
    upgrades = []
    udir = os.path.join(DATA, "upgrades")
    for d, _, files in os.walk(udir):
        for f in sorted(files):
            if f.endswith(".json") and not f.startswith("_"):
                u = _json(os.path.join(d, f), rep)
                if isinstance(u, dict):
                    upgrades.append(u)
    for bid, b in sorted(buildings.items()):
        w = f"buildings/{bid}"
        if not exists_exact(scene("buildings", bid)):
            rep.error(w, f"falta su escena game/visuals/buildings/{bid}.tscn")
        tree = b.get("upgrade_tree")
        mine = [u for u in upgrades if tree and u.get("tree") == tree]
        ext_nodes = {n for n, _, p in _nodes(scene("buildings", bid)) if p == "Upgrades"}
        for u in mine:
            ov = (u.get("visual") or {}).get("exterior_overlay")
            if ov and ov not in ext_nodes:
                rep.error(w, f"la mejora {u.get('id')} pide el nodo Upgrades/{ov} en game/visuals/buildings/{bid}.tscn")
        zones = [z.get("id") for z in b.get("zones", [])]
        zones += [e.get("zone") for u in mine for e in u.get("effects", []) if e.get("kind") == "new_zone"]
        inner = [u for u in mine if (u.get("visual") or {}).get("interior_node")]
        if not zones and not inner:
            continue
        path = scene("interiors", bid)
        if not exists_exact(path):
            rep.error(w, f"tiene puestos y falta su interior game/visuals/interiors/{bid}.tscn")
            continue
        nodes = _nodes(path)
        markers = {n for n, t, p in nodes if p == "Stations" and t == "Marker2D"}
        for z in zones:
            if z not in markers:
                rep.error(w, f"falta el Marker2D Stations/{z} en game/visuals/interiors/{bid}.tscn")
        if not any(n == "Kit" and p == "." for n, _, p in nodes):
            rep.error(w, f"game/visuals/interiors/{bid}.tscn sin nodo Kit (tamaño y puerta de la sala)")
        up_nodes = {n for n, _, p in nodes if p == "Upgrades"}
        for u in inner:
            node = u["visual"]["interior_node"]
            if node not in up_nodes:
                rep.error(w, f"la mejora {u.get('id')} pide el nodo Upgrades/{node} en game/visuals/interiors/{bid}.tscn")
    for m in sorted(os.listdir(os.path.join(DATA, "maps"))) if os.path.isdir(os.path.join(DATA, "maps")) else []:
        if not m.endswith(".json") or m.startswith("_"):
            continue
        mp = _json(os.path.join(DATA, "maps", m), rep) or {}
        for sid in sorted((mp.get("stalls") or {}).keys()):
            if not exists_exact(scene("props", f"stall_{sid}")):
                rep.warn(f"maps/{m}", f"el puesto {sid} no tiene game/visuals/props/stall_{sid}.tscn (sale el genérico)")
        if mp.get("board") and not exists_exact(scene("props", "board")):
            rep.warn(f"maps/{m}", "el tablón no tiene game/visuals/props/board.tscn (sale el genérico)")
    for cid in CHARACTERS:
        if not exists_exact(scene("characters", cid)):
            rep.warn("game/visuals/characters", f"falta {cid}.tscn (sale el genérico)")


def _buses():
    try:
        with open(os.path.join(ROOT, "default_bus_layout.tres"), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return set()
    return set(re.findall(r'^bus/\d+/name = &"([^"]+)"', text, re.M)) | {"Master"}


def check_audio(rep):
    w = "audio.json"
    a = _json(os.path.join(DATA, "audio.json"), rep)
    if not isinstance(a, dict):
        return
    buses = _buses()
    for b in AUDIO_SECTIONS.values():
        if b not in buses:
            rep.error("default_bus_layout.tres", f"falta el bus {b}")
    ids = {}
    for sec, bus in AUDIO_SECTIONS.items():
        entries = a.get(sec, {})
        if not isinstance(entries, dict):
            rep.error(w, f"{sec} debe ser {{id: {{bus, volume_db, pitch_jitter}}}}")
            continue
        for id_, e in entries.items():
            if not ID_RE.match(id_):
                rep.error(w, f"{sec}.{id_}: el id debe ir en inglés y snake_case")
            if id_ in ids:
                rep.error(w, f"{id_} está en {ids[id_]} y en {sec}")
            ids[id_] = sec
            if not isinstance(e, dict):
                rep.error(w, f"{sec}.{id_} debe ser un objeto")
                continue
            if e.get("bus", bus) not in buses:
                rep.error(w, f"{sec}.{id_}: el bus {e.get('bus')} no está en default_bus_layout.tres")
            if not isinstance(e.get("volume_db", 0.0), (int, float)):
                rep.error(w, f"{sec}.{id_}: volume_db debe ser un número (dB)")
            cd = e.get("cooldown_s", 0.0)
            if not isinstance(cd, (int, float)) or cd < 0:
                rep.error(w, f"{sec}.{id_}: cooldown_s debe ser un número >= 0 (segundos reales)")
            j = e.get("pitch_jitter", 0.0)
            if not isinstance(j, (int, float)) or not 0 <= j <= 0.5:
                rep.error(w, f"{sec}.{id_}: pitch_jitter entre 0 y 0,5")
            folder = os.path.join(ROOT, "assets", "audio", sec)
            names = os.listdir(folder) if os.path.isdir(folder) else []
            exact = [n for n in names if n.endswith(AUDIO_EXT) and re.match(rf"^{id_}(_\d\d)?\.", n)]
            loose = [n for n in names if n.lower().endswith(AUDIO_EXT) and re.match(rf"^{id_}(_\d\d)?\.", n.lower())]
            if loose and not exact:
                rep.error(w, f"{id_}: el fichero {loose[0]} tiene otras mayúsculas (debe ser {id_}.ogg / .wav)")
            elif not exact:
                rep.notes.append(f"audio {id_}: sin fichero aún (assets/audio/{sec}/{id_}.ogg o .wav): suena silencio")
    for ph, id_ in (a.get("phase_music") or {}).items():
        if ph not in PHASES:
            rep.error(w, f"phase_music: fase desconocida {ph}")
        if id_ and ids.get(id_) != "music":
            rep.error(w, f"phase_music.{ph}: {id_} no es una música de audio.json")
    for ph, id_ in (a.get("phase_ambient") or {}).items():
        if ph not in PHASES:
            rep.error(w, f"phase_ambient: fase desconocida {ph}")
        if id_ and ids.get(id_) != "ambient":
            rep.error(w, f"phase_ambient.{ph}: {id_} no es un ambiente de audio.json")
    types = {n[:-5] for n in os.listdir(os.path.join(DATA, "buildings")) if n.endswith(".json") and not n.startswith("_")}
    for bt, id_ in (a.get("interior_ambient") or {}).items():
        if bt not in types:
            rep.error(w, f"interior_ambient: tipo de edificio desconocido {bt} (data/buildings/)")
        if id_ and ids.get(id_) != "ambient":
            rep.error(w, f"interior_ambient.{bt}: {id_} no es un ambiente de audio.json")
    for ev, v in (a.get("events") or {}).items():
        for id_ in (v if isinstance(v, list) else [v]):
            if id_ not in ids:
                rep.error(w, f"events.{ev}: sonido desconocido {id_}")
    for ev in a.get("selected_only") or []:
        if not any(k == ev or k.startswith(ev + ".") for k in (a.get("events") or {})):
            rep.error(w, f"selected_only: {ev} no está en events")
    ui = a.get("ui") or {}
    for k in ("button", "pause", "resume", "panel_open", "panel_close"):
        if ui.get(k) and ui[k] not in ids:
            rep.error(w, f"ui.{k}: sonido desconocido {ui[k]}")
    ui_dir = os.path.join(ROOT, "game", "ui")
    for pn in list(ui.get("panels") or []) + list((ui.get("panel_open_by") or {}).keys()):
        if not os.path.exists(os.path.join(ui_dir, f"{pn}.tscn")):
            rep.error(w, f"ui: el panel {pn} no es una escena de game/ui/")
    for sc, id_ in (ui.get("screen_music") or {}).items():
        if not os.path.exists(os.path.join(ui_dir, f"{sc}.tscn")):
            rep.error(w, f"ui.screen_music: {sc} no es una escena de game/ui/")
        if ids.get(id_) != "music":
            rep.error(w, f"ui.screen_music.{sc}: {id_} no es una música de audio.json")
    for pn, id_ in (ui.get("panel_open_by") or {}).items():
        if id_ not in ids:
            rep.error(w, f"ui.panel_open_by.{pn}: sonido desconocido {id_}")


def check_uids(rep):
    for rel, what in uids.problems(ROOT):
        rep.error(rel, f"{what} (python3 tools/uids.py --fix)")


def check(rep):
    check_no_paths(rep)
    check_names(rep)
    check_inventory(rep)
    check_visuals(rep)
    check_audio(rep)
    check_uids(rep)
