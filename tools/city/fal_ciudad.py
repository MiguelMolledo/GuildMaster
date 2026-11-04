#!/usr/bin/env python3
"""Sprites of the town builder with fal.ai (docs/protocolos/generar-ciudad.md §Sprites): the street lantern and the
back views of the filler houses. Flow of the fal pilot (rama arte-fal, assets/art/fal_piloto/INFORME.md):
fal-ai/nano-banana-2/edit with ONE reference (the neighbour sprite enlarged x4, nearest), flat white background,
local key of the background, reduction to the size and palette of the reference sprite.

Every paid call is written to tools/city/fal_gasto.json (date, piece, model, images, estimated USD). The key comes
from .env (FAL_KEY) and is never printed. Raw outputs go to tmp/fal_ciudad/ (outside git).

  python3 tools/city/fal_ciudad.py gen --piece lantern --name v1 --ref assets/art/props/torch.png --prompt "..."
  python3 tools/city/fal_ciudad.py total
"""
import argparse
import datetime
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEDGER = os.path.join(ROOT, "tools", "city", "fal_gasto.json")
RAW = os.path.join(ROOT, "tmp", "fal_ciudad")
MODELS = {"nano": ("fal-ai/nano-banana", 0.0398), "nano2": ("fal-ai/nano-banana-2", 0.08),
          "nanopro": ("fal-ai/nano-banana-pro", 0.15)}


def ledger():
    if os.path.exists(LEDGER):
        with open(LEDGER, encoding="utf-8") as f:
            return json.load(f)
    return []


def total():
    return round(sum(float(r["usd"]) for r in ledger()), 4)


def note(piece, model, images, usd, what):
    rows = ledger()
    rows.append({"fecha": datetime.datetime.now().isoformat(timespec="seconds"), "pieza": piece, "modelo": model,
                 "imagenes": images, "usd": round(usd, 4), "que": what})
    with open(LEDGER, "w", encoding="utf-8") as f:
        json.dump(rows, f, indent=1, ensure_ascii=False)
        f.write("\n")


def enlarge(src, factor, bg=(255, 255, 255)):
    """The reference sprite x`factor` (nearest) on a flat background, as the pilot recommends."""
    from PIL import Image
    im = Image.open(src).convert("RGBA")
    big = im.resize((im.width * factor, im.height * factor), Image.NEAREST)
    pad = 64
    out = Image.new("RGBA", (big.width + 2 * pad, big.height + 2 * pad), bg + (255,))
    out.alpha_composite(big, (pad, pad))
    os.makedirs(RAW, exist_ok=True)
    p = os.path.join(RAW, "ref_" + os.path.basename(src))
    out.convert("RGB").save(p)
    return p


def gen(a):
    from dotenv import load_dotenv
    load_dotenv(os.path.join(ROOT, ".env"))
    import fal_client
    model_id, unit = MODELS[a.model]
    refs = [enlarge(os.path.join(ROOT, r), a.factor) for r in a.ref]
    args = {"prompt": a.prompt, "num_images": a.count, "output_format": "png"}
    if a.aspect:
        args["aspect_ratio"] = a.aspect
    if refs:
        args["image_urls"] = [fal_client.upload_file(r) for r in refs]
        model_id += "/edit"
    print(f"{model_id} | {a.count} img | {unit * a.count:.3f} USD (llevamos {total():.3f})")
    res = fal_client.subscribe(model_id, arguments=args)
    d = os.path.join(RAW, a.piece)
    os.makedirs(d, exist_ok=True)
    n = 0
    for i, im in enumerate(res.get("images", [])):
        p = os.path.join(d, f"{a.name}{'_' + str(i + 1) if a.count > 1 else ''}.png")
        urllib.request.urlretrieve(im["url"], p)
        print("  ->", os.path.relpath(p, ROOT))
        n += 1
    note(a.piece, model_id, n, unit * n, a.name)
    with open(os.path.join(d, "prompts.log"), "a", encoding="utf-8") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {a.name} | {model_id} | refs={','.join(a.ref)}\n"
                f"  {a.prompt}\n\n")
    print(f"Total: {total():.3f} USD")


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gen")
    g.add_argument("--piece", required=True)
    g.add_argument("--name", required=True)
    g.add_argument("--prompt", required=True)
    g.add_argument("--ref", action="append", default=[])
    g.add_argument("--model", default="nano2", choices=list(MODELS))
    g.add_argument("--count", type=int, default=1)
    g.add_argument("--aspect", default="")
    g.add_argument("--factor", type=int, default=4)
    sub.add_parser("total")
    a = ap.parse_args(argv)
    if a.cmd == "gen":
        gen(a)
    else:
        print(f"{total():.3f} USD en {len(ledger())} llamadas")


if __name__ == "__main__":
    main(sys.argv[1:])
