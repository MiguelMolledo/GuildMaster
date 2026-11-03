#!/usr/bin/env python3
"""Piloto de arte con fal.ai (2026-11-03). Genera, pixela y quita fondos con un tope de gasto.

Cada llamada se apunta en assets/art/fal_piloto/gasto.json (fecha, pieza, modelo, imágenes, coste estimado) y se
niega a correr si el total pasaría del tope (3 USD). La clave sale de .env (FAL_KEY) y no se imprime nunca.

Uso:
  python3 tools/art/fal_piloto.py gen  --piece retratos --model nano2 --name grid_v1 --prompt "..." [--ref img]...
                                       [--aspect 1:1] [--count 1]
  python3 tools/art/fal_piloto.py pixel --piece retratos --src a.png --dst b.png [--scale 8] [--colors 32]
                                       [--transparent]
  python3 tools/art/fal_piloto.py rembg --piece paseo --src a.png --dst b.png
  python3 tools/art/fal_piloto.py total
Tanda: FAL_TANDA=piloto (por defecto, tope 3 USD) o FAL_TANDA=produccion (tope 8 USD, crudo en assets/art/fal_produccion/).
"""
import argparse
import datetime
import json
import os
import sys
import time
import urllib.request

from dotenv import load_dotenv

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
load_dotenv(os.path.join(ROOT, ".env"))
import fal_client  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "fal_piloto")
LEDGER = os.path.join(OUT, "gasto.json")
# Tope por tanda: el piloto (3 USD) y la producción de retratos, eventos, pantallas y cartas (8 USD, 2026-11-03).
TANDA = os.environ.get("FAL_TANDA", "piloto")
CAPS = {"piloto": 3.0, "produccion": 8.0, "extra": 100.0, "pool": 100.0}  # extra: sin tope del owner (2026-11-03); 100 es solo un freno
CAP = CAPS[TANDA]

MODELS = {
    "nano": ("fal-ai/nano-banana", 0.0398),
    "nano2": ("fal-ai/nano-banana-2", 0.08),
    "nanopro": ("fal-ai/nano-banana-pro", 0.15),
}
# Endpoints cobrados por segundo de cómputo: se apunta el tiempo real de la llamada (cota alta: incluye la cola).
PER_SECOND = {"fal-ai/image2pixel": 0.00017, "fal-ai/birefnet/v2": 0.000575}


def ledger():
    if os.path.exists(LEDGER):
        with open(LEDGER) as f:
            return json.load(f)
    return []


def total():
    return round(sum(r["usd"] for r in ledger() if r.get("tanda", "piloto") == TANDA), 4)


def note(piece, model, images, usd, what):
    import fcntl  # varias tandas a la vez: el gasto se escribe con cerrojo
    os.makedirs(OUT, exist_ok=True)
    with open(LEDGER + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        _note(piece, model, images, usd, what)


def _note(piece, model, images, usd, what):
    rows = ledger()
    rows.append({"fecha": datetime.datetime.now().isoformat(timespec="seconds"), "tanda": TANDA, "pieza": piece,
                 "modelo": model,
                 "imagenes": images, "usd": round(usd, 4), "que": what})
    os.makedirs(OUT, exist_ok=True)
    tmp = f"{LEDGER}.{os.getpid()}.tmp"  # escritura atómica: quien lee a la vez nunca ve el fichero a medias
    with open(tmp, "w") as f:
        json.dump(rows, f, indent=1, ensure_ascii=False)
    os.replace(tmp, LEDGER)


def guard(cost):
    t = total()
    if t + cost > CAP + 1e-9:
        print(f"TOPE ({TANDA}): gastado {t:.3f} USD + {cost:.3f} pasaría de {CAP} USD. No se genera.")
        sys.exit(2)
    return t


def gen(a):
    model_id, unit = MODELS[a.model]
    cost = unit * a.count
    t = guard(cost)
    args = {"prompt": a.prompt, "num_images": a.count, "output_format": "png"}
    if a.aspect:
        args["aspect_ratio"] = a.aspect
    if a.resolution:
        args["resolution"] = a.resolution
    if a.ref:
        args["image_urls"] = [fal_client.upload_file(r) for r in a.ref]
        model_id += "/edit"
    print(f"{model_id} | {a.count} img | {cost:.3f} USD (llevamos {t:.3f}) | refs={len(a.ref)}")
    res = fal_client.subscribe(model_id, arguments=args)
    d = os.path.join(OUT if TANDA == "piloto" else os.path.join(ROOT, "assets", "art", "fal_produccion"), a.piece, "crudo")
    os.makedirs(d, exist_ok=True)
    paths = []
    for i, im in enumerate(res.get("images", [])):
        p = os.path.join(d, f"{a.name}{'_' + str(i + 1) if a.count > 1 else ''}.png")
        urllib.request.urlretrieve(im["url"], p)
        paths.append(p)
        print("  ->", os.path.relpath(p, ROOT))
    n = len(paths)
    note(a.piece, model_id, n, unit * n, a.name)
    with open(os.path.join(d, "prompts.log"), "a") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {a.name} | {model_id} | aspect={a.aspect or '-'} | "
                f"refs={','.join(os.path.relpath(r, ROOT) if r.startswith(ROOT) else r for r in a.ref)}\n"
                f"  {a.prompt}\n\n")
    if res.get("description"):
        print("  desc:", res["description"][:200])
    print(f"Total: {total():.3f} USD")


def per_second(endpoint, args, piece, what):
    guard(0.01)
    t0 = time.time()
    res = fal_client.subscribe(endpoint, arguments=args)
    secs = time.time() - t0
    note(piece, endpoint, 1, PER_SECOND[endpoint] * secs, what)
    return res


def pixel(a):
    args = {"image_url": fal_client.upload_file(a.src), "max_colors": a.colors, "snap_grid": True,
            "transparent_background": a.transparent, "cleanup_jaggy": True, "trim_borders": False}
    if a.scale:
        args["scale"] = a.scale
    if a.palette:
        args["fixed_palette"] = a.palette.split(",")
    res = per_second("fal-ai/image2pixel", args, a.piece, "image2pixel " + os.path.basename(a.dst))
    keys = {k: (v if not isinstance(v, (dict, list)) else type(v).__name__) for k, v in res.items()}
    print("  resp:", keys)
    url = None
    for k in ("image", "images"):
        v = res.get(k)
        if isinstance(v, dict):
            url = v.get("url")
        elif isinstance(v, list) and v:
            url = v[0].get("url")
        if url:
            break
    os.makedirs(os.path.dirname(a.dst), exist_ok=True)
    urllib.request.urlretrieve(url, a.dst)
    print("  ->", os.path.relpath(a.dst, ROOT))
    with open(a.dst + ".json", "w") as f:
        json.dump({k: v for k, v in res.items() if k not in ("image", "images")}, f, indent=1)


def rembg(a):
    args = {"image_url": fal_client.upload_file(a.src), "model": "General Use (Heavy)", "output_format": "png",
            "operating_resolution": "1024x1024", "refine_foreground": True}
    res = per_second("fal-ai/birefnet/v2", args, a.piece, "birefnet " + os.path.basename(a.dst))
    os.makedirs(os.path.dirname(a.dst), exist_ok=True)
    urllib.request.urlretrieve(res["image"]["url"], a.dst)
    print("  ->", os.path.relpath(a.dst, ROOT))


def main():
    if not os.environ.get("FAL_KEY"):
        print("Falta FAL_KEY en .env")
        sys.exit(1)
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gen")
    g.add_argument("--piece", required=True)
    g.add_argument("--model", choices=list(MODELS), default="nano")
    g.add_argument("--name", required=True)
    g.add_argument("--prompt", required=True)
    g.add_argument("--ref", action="append", default=[])
    g.add_argument("--aspect", default="")
    g.add_argument("--resolution", default="")
    g.add_argument("--count", type=int, default=1)
    x = sub.add_parser("pixel")
    x.add_argument("--piece", required=True)
    x.add_argument("--src", required=True)
    x.add_argument("--dst", required=True)
    x.add_argument("--scale", type=int, default=0)
    x.add_argument("--colors", type=int, default=32)
    x.add_argument("--palette", default="")
    x.add_argument("--transparent", action="store_true")
    r = sub.add_parser("rembg")
    r.add_argument("--piece", required=True)
    r.add_argument("--src", required=True)
    r.add_argument("--dst", required=True)
    sub.add_parser("total")
    a = p.parse_args()
    {"gen": gen, "pixel": pixel, "rembg": rembg, "total": lambda _: print(f"{TANDA}: {total():.4f} USD")}[a.cmd](a)


if __name__ == "__main__":
    main()
