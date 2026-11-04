#!/usr/bin/env python3
"""Efectos del duelo (docs/gdd/04e_combate.md §4e.8) hechos con vfx_workbench de PixelLab (gratis, sin generaciones):
golpe (tajo), parada (chispas), finta (estela azul) y toque (estrella roja), alrededor de un personaje de 48 px
mirando al este. Este script baja el «game pack» de cada efecto (a los crudos, fuera del repo), toma su pieza
«whole» (el efecto sin el sprite) y la deja en el juego como una tira horizontal y su ficha:

  assets/art/vfx/<id>/<id>.png    tira de fotogramas (de izquierda a derecha), fondo transparente
  assets/art/vfx/<id>/<id>.json   {frames, frame_w, frame_h, fps, loop, offset}: offset = posición de la esquina de
                                  arriba a la izquierda del fotograma respecto a los PIES del personaje que lo hace
                                  (golpe, parada, finta) o lo recibe (toque), con el personaje mirando al ESTE;
                                  mirando al oeste, reflejar el fotograma y usar x = -(offset.x + frame_w)

Uso: python3 tools/art/vfx_duelo.py   (vuelve a bajar los paquetes si no están en los crudos)
"""
import json
import os
import sys
import urllib.request
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fal_rutas as fr_  # noqa: E402

ROOT = fr_.ROOT
RAW = os.path.join(fr_.CRUDOS, "vfx_duelo")
OUT = os.path.join(ROOT, "assets", "art", "vfx")
BASE = "https://api.pixellab.ai/mcp/pixel-tools/"
# id del asset -> (id de la exportación de PixelLab, nombre del paquete, id del efecto en «My effects»)
EFFECTS = {
    "duel_strike": ("d96d552e-6689-49f3-8e8d-70e176150094", "guildmaster-duel-strike-game.zip",
                    "a051f66b-c74a-4659-8b4d-bb7a6847f10b"),
    "duel_parry": ("a1bb8cfd-1c33-4aec-ab46-9139524b4ee5", "guildmaster-duel-parry-game.zip",
                   "c796cf0d-77fc-4a01-a8a9-dd0b5829f9a5"),
    "duel_feint": ("128adf57-6af3-46d6-8c23-6f917200ef34", "guildmaster-duel-feint-game.zip",
                   "19726734-c906-4662-9372-f72ea3016029"),
    "duel_hit": ("806d89e8-2e63-4e88-9a64-ca7ead06caa9", "guildmaster-duel-hit-game.zip",
                 "3347bbaf-d1b0-4ccc-9ee9-c1eccbdc5425"),
}


def pack(vid):
    """Baja y abre el paquete (con cuidado: nada fuera de su carpeta)."""
    job, name, _ = EFFECTS[vid]
    d = os.path.join(RAW, vid)
    z = os.path.join(d, name)
    os.makedirs(d, exist_ok=True)
    if not os.path.exists(z):
        urllib.request.urlretrieve(BASE + job + "/" + name, z)
    x = os.path.join(d, "x")
    with zipfile.ZipFile(z) as zf:
        for n in zf.namelist():
            if n.startswith("/") or ".." in n:
                raise SystemExit(f"{vid}: ruta rara en el paquete: {n}")
        zf.extractall(x)
    return x


def build(vid):
    x = pack(vid)
    man = json.load(open(os.path.join(x, "manifest.json")))
    clip = next(c for c in man["clips"] if c["name"] == "whole")
    fw, fh = clip["frame"]["w"], clip["frame"]["h"]
    frames = []
    for sh in clip["sheets"]:
        im = Image.open(os.path.join(x, sh["file"])).convert("RGBA")
        for i in range(sh["frames"]):
            c, r = i % sh["columns"], i // sh["columns"]
            frames.append(im.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)))
    strip = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.alpha_composite(f, (i * fw, 0))
    d = os.path.join(OUT, vid)
    os.makedirs(d, exist_ok=True)
    strip.save(os.path.join(d, vid + ".png"))
    meta = {"frames": len(frames), "frame_w": fw, "frame_h": fh, "fps": man["fps"], "loop": bool(clip["loop"]),
            "start_frame": clip.get("start_frame", 0), "offset": clip["offset"], "facing": "e",
            "made_with": "PixelLab vfx_workbench (My effects " + EFFECTS[vid][2] + ")"}
    with open(os.path.join(d, vid + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
        f.write("\n")
    print(f"{vid}: {len(frames)} fotogramas {fw}×{fh} @ {man['fps']} fps, offset {clip['offset']}")


def main():
    for vid in EFFECTS:
        build(vid)


if __name__ == "__main__":
    main()
