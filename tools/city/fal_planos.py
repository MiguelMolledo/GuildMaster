#!/usr/bin/env python3
"""Top-down town plans with fal.ai as references for the organic towns (docs/protocolos/generar-ciudad.md §1e).

The plan is semantic: flat colours that mean something (tools/city/paleta_planos.json: streets grey, squares beige,
water blue, houses red, walls black, fields yellow, woods dark green, each landmark its own colour), so
tools/city/desde_imagen.py can read it back into the grid.

  python3 tools/city/fal_planos.py semantico <map> [--px 16]      our map in the palette (reports/ciudad/fal/<map>_semantico.png)
  python3 tools/city/fal_planos.py gen <map> --name v1 [--ref semantico|<png>] [--model nano2] [--count 1]
  python3 tools/city/fal_planos.py total

The prompt of each town is its "fal" block in tools/city/ciudades.json (brief, landmarks). Every paid call goes to
tools/city/fal_gasto.json (as tools/city/fal_ciudad.py); raw images and prompts.log to tmp/fal_planos/<map>/ (outside
git). The key comes from .env (FAL_KEY) and is never printed.
"""
import argparse
import datetime
import json
import os
import sys
import urllib.request

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citylib  # noqa: E402
import fal_ciudad  # noqa: E402

ROOT = citylib.ROOT
PALETTE_PATH = os.path.join(ROOT, "tools", "city", "paleta_planos.json")
RAW = os.path.join(ROOT, "tmp", "fal_planos")
OUT = os.path.join(ROOT, "reports", "ciudad", "fal")
# landmark types of the maps -> class of the palette (the rest are drawn as houses, the towers as wall)
LANDMARK_CLASS = {"cathedral": "church", "church": "church", "abbey_church": "church", "exchange": "exchange",
                  "customs": "exchange", "warehouse": "warehouse", "mine": "mine", "quarry": "quarry",
                  "cloister": "cloister", "watermill": "mill", "gate_tower": "wall", "wall_tower": "wall"}
TILE_CLASS = {".": "grass", "=": "street", ",": "street", "b": "street", "v": "street", "P": "plaza", "S": "plaza",
              "N": "plaza", "w": "water", "#": "building", "M": "wall", "f": "field", "T": "forest", "m": "dock",
              "R": "rock", "H": "building"}


def palette():
    return citylib.load_json(PALETTE_PATH)


def semantic(map_id, px=16, out=None):
    """A map of data/maps drawn in the semantic palette, one px x px square per tile."""
    from PIL import Image, ImageDraw
    pal = palette()["classes"]
    d = citylib.load_json(os.path.join(citylib.DATA, "maps", map_id + ".json"))
    rows = d["rows"]
    h, w = len(rows), len(rows[0])
    cls = [[TILE_CLASS.get(ch, "grass") for ch in row] for row in rows]
    for e in d.get("landmarks", []):
        k = LANDMARK_CLASS.get(e["type"], "building")
        c, r = e["origin"]
        for dr in range(e["size"][1]):
            for dc in range(e["size"][0]):
                cls[r + dr][c + dc] = k
    img = Image.new("RGB", (w * px, h * px))
    dr = ImageDraw.Draw(img)
    for r in range(h):
        for c in range(w):
            dr.rectangle([c * px, r * px, (c + 1) * px - 1, (r + 1) * px - 1], fill=tuple(pal[cls[r][c]]["rgb"]))
    out = out or os.path.join(OUT, f"{map_id}_semantico.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    return out


def prompt_for(map_id, with_ref):
    plan = citylib.load_json(os.path.join(ROOT, "tools", "city", "ciudades.json"))[map_id]
    fal = plan.get("fal", {})
    pal = palette()["classes"]
    use = fal.get("classes") or list(pal)
    code = "; ".join(f"{pal[k]['words']} (#{''.join(f'{v:02x}' for v in pal[k]['rgb'])})" for k in use)
    w, h = plan["size"]
    square = (f" The main market square is large and roughly rectangular: about {round(1000 / w)}% of the image wide "
              f"and {round(1200 / h)}% tall, on dry land well away from the water, with a block of buildings just "
              f"above it (the town hall) and the main streets arriving at its corners and sides.")
    head = ("Redraw this schematic town plan as a real, organic medieval town, keeping the same colour code, the same "
            "river, the same square position and the same overall extent. " if with_ref else
            "A top-down town plan of a medieval town, seen straight from above like an old cadastral map. ")
    return (head + "Flat solid colours only: no shading, no texture, no shadows, no outlines, no text, no labels, no "
            "legend, no grid, no frame, no perspective. Use exactly this colour code and no other colour: " + code +
            ". The town: " + fal.get("brief", "") + square + " Organic medieval street pattern: the streets curve and follow "
            "the river and the old roads, they meet at uneven angles, a main street runs from each gate to the market "
            "square, narrow alleys run between the blocks, the houses stand in long narrow plots with their fronts on "
            "the street and gardens behind, the blocks are irregular. The whole town fits in the square image with "
            "countryside around it.")


def gen(a):
    from dotenv import load_dotenv
    load_dotenv(os.path.join(ROOT, ".env"))
    import fal_client
    model_id, unit = fal_ciudad.MODELS[a.model]
    ref = None
    if a.ref == "semantico":
        ref = semantic(a.map)
    elif a.ref:
        ref = os.path.join(ROOT, a.ref)
    prompt = a.prompt or prompt_for(a.map, bool(ref))
    args = {"prompt": prompt, "num_images": a.count, "output_format": "png", "aspect_ratio": "1:1"}
    if ref:
        args["image_urls"] = [fal_client.upload_file(ref)]
        model_id += "/edit"
    print(f"{model_id} | {a.count} img | {unit * a.count:.3f} USD (llevamos {fal_ciudad.total():.3f})")
    res = fal_client.subscribe(model_id, arguments=args)
    d = os.path.join(RAW, a.map)
    os.makedirs(d, exist_ok=True)
    n = 0
    for i, im in enumerate(res.get("images", [])):
        p = os.path.join(d, f"{a.name}{'_' + str(i + 1) if a.count > 1 else ''}.png")
        urllib.request.urlretrieve(im["url"], p)
        print("  ->", os.path.relpath(p, ROOT))
        n += 1
    fal_ciudad.note("plano_" + a.map, model_id, n, unit * n, a.name)
    with open(os.path.join(d, "prompts.log"), "a", encoding="utf-8") as f:
        f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} | {a.name} | {model_id} | ref={a.ref or '-'}\n  {prompt}\n\n")
    print(f"Total: {fal_ciudad.total():.3f} USD")


def main(argv):
    ap = argparse.ArgumentParser(prog="fal_planos.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("semantico")
    s.add_argument("map")
    s.add_argument("--px", type=int, default=16)
    g = sub.add_parser("gen")
    g.add_argument("map")
    g.add_argument("--name", required=True)
    g.add_argument("--ref", default="")
    g.add_argument("--prompt", default="")
    g.add_argument("--model", default="nano2", choices=list(fal_ciudad.MODELS))
    g.add_argument("--count", type=int, default=1)
    sub.add_parser("total")
    a = ap.parse_args(argv)
    if a.cmd == "semantico":
        print(os.path.relpath(semantic(a.map, a.px), ROOT))
    elif a.cmd == "gen":
        gen(a)
    else:
        print(f"{fal_ciudad.total():.3f} USD en {len(fal_ciudad.ledger())} llamadas")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
