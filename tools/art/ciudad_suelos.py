#!/usr/bin/env python3
"""Suelos de la ciudad en 2D (rama ciudad-2d): texturas de material continuas en el espacio del mundo.

Cada material (hierba, adoquín de calle, losas de plaza, tierra, campo...) es una textura isométrica que se repite
como un rectángulo de 64·N × 32·N px (N casillas por lado): GroundLayer la muestrea con la posición del mundo, así que
no se ve la rejilla de casillas ni la misma casilla repetida. Se sacan de una textura cuadrada sin costuras vista
desde arriba (fal z-image/turbo/tiling) proyectada a 2:1 (el cuadrado de arriba pasa a ser el rombo de N×N casillas)
y pasada a una paleta corta por material.

Uso:
  python3 tools/art/ciudad_suelos.py fal NAME "prompt"     # z-image/turbo/tiling 1024² → tmp/ciudad2d/crudo/NAME.png
  python3 tools/art/ciudad_suelos.py iso RAW OUT --tiles N --colors K [--sat S] [--val V]
  python3 tools/art/ciudad_suelos.py total                 # gasto de fal de la tanda ciudad2d

Cada llamada a fal se apunta en assets/art/fal_piloto/gasto.json (tanda «ciudad2d») y su prompt en
tmp/ciudad2d/crudo/prompts.log. La clave sale de .env (FAL_KEY; si el worktree no la tiene, la del repo principal)
y no se imprime nunca.
"""
import argparse
import datetime
import json
import os
import sys
import urllib.request

from PIL import Image

try:  # numpy: ~/.pixellab-pip-venv/bin/python (the fal calls run with the system python3, which has fal_client)
    import numpy as np
except ImportError:
    np = None

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(ROOT, "tmp", "ciudad2d", "crudo")
LEDGER = os.path.join(ROOT, "assets", "art", "fal_piloto", "gasto.json")
TILING = "fal-ai/z-image/turbo/tiling"
NANO_EDIT = "fal-ai/nano-banana-2/edit"
PRICE = {TILING: 0.02 * 1.048576, NANO_EDIT: 0.08}
TANDA = "ciudad2d"


def _fal():
    from dotenv import load_dotenv
    for env in (os.path.join(ROOT, ".env"), os.path.expanduser("~/Code/GuildMaster/.env")):
        if os.path.exists(env):
            load_dotenv(env)
            break
    import fal_client
    return fal_client


def _note(pieza, model, n, usd, que):
    import fcntl  # several calls may run at once: one writer at a time
    os.makedirs(RAW, exist_ok=True)
    with open(os.path.join(RAW, "gasto.lock"), "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        _note_locked(pieza, model, n, usd, que)


def _note_locked(pieza, model, n, usd, que):
    data = json.load(open(LEDGER))
    data.append({"fecha": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"), "tanda": TANDA, "pieza": pieza,
                 "modelo": model, "imagenes": n, "usd": round(usd, 4), "que": que})
    with open(LEDGER, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


def total():
    return sum(float(e.get("usd", 0)) for e in json.load(open(LEDGER)) if e.get("tanda") == TANDA)


def _log(name, model, prompt, extra=""):
    os.makedirs(RAW, exist_ok=True)
    with open(os.path.join(RAW, "prompts.log"), "a") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {name} | {model} | {extra}\n  {prompt}\n\n")


def fal_tiling(name, prompt, size=1024):
    fal = _fal()
    args = {"prompt": prompt, "tiling_mode": "both", "image_size": {"width": size, "height": size},
            "num_inference_steps": 8, "output_format": "png", "num_images": 1}
    print(f"{TILING} | {name} | {PRICE[TILING]:.3f} USD (llevamos {total():.3f})")
    res = fal.subscribe(TILING, arguments=args)
    os.makedirs(RAW, exist_ok=True)
    out = os.path.join(RAW, name + ".png")
    urllib.request.urlretrieve(res["images"][0]["url"], out)
    _note("suelos", TILING, 1, PRICE[TILING], name)
    _log(name, TILING, prompt, f"tiling_mode=both {size}")
    print("  ->", os.path.relpath(out, ROOT))
    return out


def fal_edit(name, prompt, refs, aspect="1:1"):
    """nano-banana-2/edit con referencias locales (se suben a fal)."""
    fal = _fal()
    urls = [fal.upload_file(r) for r in refs]
    args = {"prompt": prompt, "image_urls": urls, "num_images": 1, "aspect_ratio": aspect, "output_format": "png"}
    print(f"{NANO_EDIT} | {name} | {PRICE[NANO_EDIT]:.3f} USD (llevamos {total():.3f})")
    res = fal.subscribe(NANO_EDIT, arguments=args)
    os.makedirs(RAW, exist_ok=True)
    out = os.path.join(RAW, name + ".png")
    urllib.request.urlretrieve(res["images"][0]["url"], out)
    _note("fachadas", NANO_EDIT, 1, PRICE[NANO_EDIT], name)
    _log(name, NANO_EDIT, prompt, "refs=" + ",".join(os.path.basename(r) for r in refs))
    print("  ->", os.path.relpath(out, ROOT))
    return out


def iso_project(src, tiles, ss=4):
    """Textura cuadrada sin costuras (vista desde arriba) → textura iso de 64·tiles × 32·tiles que se repite como
    rectángulo. Cada píxel de salida (x, y) mira el punto (s, t) del cuadrado: s = x/W + y/H, t = y/H − x/W (mod 1);
    supermuestreo ss×ss y media (el crudo es más fino que el píxel del juego)."""
    a = np.asarray(src.convert("RGB"), dtype=np.float32)
    sh, sw = a.shape[:2]
    W, H = 64 * tiles, 32 * tiles
    acc = np.zeros((H, W, 3), np.float32)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    for j in range(ss):
        for i in range(ss):
            x = xs + (i + 0.5) / ss
            y = ys + (j + 0.5) / ss
            s = np.mod(x / W + y / H, 1.0)
            t = np.mod(y / H - x / W, 1.0)
            acc += a[(t * sh).astype(int) % sh, (s * sw).astype(int) % sw]
    return acc / (ss * ss)


def quantize(arr, colors, sat=1.0, val=1.0, seed=7):
    """Paleta corta propia del material (k-means en RGB, determinista) tras ajustar saturación y brillo."""
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    if sat != 1.0 or val != 1.0:
        hsv = np.asarray(img.convert("HSV"), dtype=np.float32)
        hsv[..., 1] = np.clip(hsv[..., 1] * sat, 0, 255)
        hsv[..., 2] = np.clip(hsv[..., 2] * val, 0, 255)
        img = Image.fromarray(hsv.astype(np.uint8), "HSV").convert("RGB")
    q = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    return q.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fal")
    f.add_argument("name")
    f.add_argument("prompt")
    i = sub.add_parser("iso")
    i.add_argument("raw")
    i.add_argument("out")
    i.add_argument("--tiles", type=int, default=4)
    i.add_argument("--colors", type=int, default=12)
    i.add_argument("--sat", type=float, default=1.0)
    i.add_argument("--val", type=float, default=1.0)
    sub.add_parser("total")
    a = ap.parse_args()
    if a.cmd == "fal":
        fal_tiling(a.name, a.prompt)
    elif a.cmd == "iso":
        arr = iso_project(Image.open(a.raw), a.tiles)
        out = quantize(arr, a.colors, a.sat, a.val)
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        out.save(a.out)
        print(a.out, out.size)
    else:
        print(f"{total():.3f} USD")


if __name__ == "__main__":
    main()
