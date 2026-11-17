#!/usr/bin/env python3
"""Characters redrawn with PixelLab (2026-11-17, MANIFEST «Lista de la compra · PixelLab» #14): the downloads of each
character (ZIP of get_character, unpacked in pixellab-pip-generations/personajes2d/<name>/) aligned onto the 68×68
frame of the game (feet at y=58, like the Guild Renew sprites they replace), keyed for the H8 identity shader and packed
into strips; then the SpriteFrames with personajes_guild.py's writer.

  python3 tools/art/personajes_pixellab.py strips [--only artisan_m,...]   # PNG strips (then: godot --import)
  python3 tools/art/personajes_pixellab.py frames [--only ...]             # game/visuals/characters/<id>_frames.tres
  python3 tools/art/personajes_pixellab.py regions OUT.png                 # every strip's regions in flat colours

Keying (same contract as personajes_guild.py and identity_swap.gdshader): a pixel of hair, skin, primary or secondary
clothes gets alpha 254, its region in blue (50/100/150/200) and its shade in red (brightness over the region's
reference, ×127.5). The new characters were drawn with key colours on purpose: the primary clothes green, the
secondary blue; skin by its warm light ramp; hair by being brown in the head band of the upright figure (the leather
shares the hair's browns, so position decides). Everything else keeps its colour (outline, leather, boots, tools).
"""
import argparse
import colorsys
import json
import os
import shutil
import sys

from PIL import Image

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import personajes_guild as pg  # noqa: E402  (tres writer, FPS, LOOP, region ids)

ROOT = pg.ROOT
RAW = os.path.join(ROOT, "pixellab-pip-generations", "personajes2d")
ART = pg.ART
FRAME, FEET = 68, 58
HAIR, SKIN, PRIMARY, SECONDARY = pg.HAIR, pg.SKIN, pg.PRIMARY, pg.SECONDARY
DIRS = pg.DIRS  # PixelLab direction -> our suffix

# visual id -> raw folder, PixelLab ids (for the inventory) and anim -> (PixelLab animation folder, frames to drop)
SOURCES = json.load(open(os.path.join(HERE, "personajes_pixellab.json")))["characters"]


def hsv(c):
    h, s, v = colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)
    return h * 360.0, s, v


def region_of(c, y, hair_until, x=0, head=None):
    h, s, v = hsv(c)
    if v < 0.12:
        return 0                                     # outline and the darkest folds stay as drawn
    # skin: the light of the ramp (warm, not too saturated) or its mid shadow (redder hue); the reddish-brown hair,
    # boots and belts of the same hue sit at h >= 18 with mid values, the gold of buckles is too saturated
    if (15 <= h <= 30 and 0.3 <= s <= 0.6 and v >= 0.75) or (8 <= h <= 17 and 0.5 <= s <= 0.69 and 0.55 <= v < 0.75):
        return SKIN
    if 60 <= h <= 170 and s >= 0.12 and v >= 0.12:
        return PRIMARY
    if 200 <= h <= 262 and s >= 0.2 and v >= 0.12:   # not the steel of a hammer (h<200)
        return SECONDARY
    if y <= hair_until and (h <= 40 or h >= 330) and s >= 0.3 and (head is None or head[0] <= x <= head[1]):
        return HAIR
    return 0


def references(frames, hair_until):
    vals = {HAIR: [], SKIN: [], PRIMARY: [], SECONDARY: []}
    for im in frames:
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                c = px[x, y]
                if c[3] >= 128:
                    r = region_of(c, y, hair_until)
                    if r:
                        vals[r].append(pg.lum(c))
    return {k: (sorted(v)[len(v) // 2] if v else 128.0) for k, v in vals.items()}


def head_span(im, hair_until):
    """x range the hair may take in this frame: the face (skin in the head band) widened by 4 px, or None (back view,
    no face: the whole band) — keeps a hammer handle or a sleeve at head height out of the hair."""
    px = im.load()
    xs = [x for y in range(hair_until + 1) for x in range(im.width)
          if px[x, y][3] >= 128 and region_of(px[x, y], y, -1) == SKIN]
    return (min(xs) - 4, max(xs) + 4) if len(xs) >= 6 else None


def key(im, refs, hair_until):
    out = im.copy()
    px = out.load()
    head = head_span(im, hair_until)
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
                continue
            reg = region_of((r, g, b), y, hair_until, x, head)
            if reg == 0:
                px[x, y] = (r, g, b, 255)
                continue
            shade = pg.lum((r, g, b)) / max(1.0, refs[reg])
            shade = min(2.0, 1.0 + (shade - 1.0) * (0.5 if reg == HAIR else 0.8))
            px[x, y] = (int(round(shade * 127.5)), 0, reg * 50, 254)
    return out


def load_dir(folder):
    files = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
    return [Image.open(os.path.join(folder, f)).convert("RGBA") for f in files]


def place(frames, anchor_bottom=None):
    """Frames of any square canvas onto 68×68: centred in x, shifted in y so frame 0's lowest pixel sits at FEET
    (or anchor_bottom of the source canvas, if given)."""
    c = frames[0].width
    ox = (FRAME - c) // 2
    bottom = anchor_bottom if anchor_bottom is not None else frames[0].getbbox()[3]
    oy = FEET - bottom
    out = []
    for f in frames:
        canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        canvas.alpha_composite(f, (max(0, ox), max(0, oy)), (max(0, -ox), max(0, -oy)))
        bb = f.getbbox()
        if bb and (bb[0] + ox < 0 or bb[2] + ox > FRAME or bb[1] + oy < 0 or bb[3] + oy > FRAME):
            print(f"    ! a frame leaves the 68 canvas (bbox {bb}, offset {ox},{oy})")
        out.append(canvas)
    return out


def hair_line(src, band=0.21):
    """Last row of the hair band: the upright figure's top + 21 % of its height, from the south rotation placed."""
    rot = Image.open(os.path.join(src, "rotations", "south.png")).convert("RGBA")
    placed = place([rot])[0]
    bb = placed.getbbox()
    return bb[1] + int(band * (bb[3] - bb[1]))


def head_swap(bad, donor, rows=14):
    """Local repair: the head (top `rows` rows of the figure) of `donor` pasted over `bad`'s, aligned by the top row and
    the head's centre — for template frames that turn the head away (walk south)."""
    def head_box(im):
        bb = im.getbbox()
        part = im.crop((0, bb[1], im.width, bb[1] + rows)).getbbox()
        return bb[1], part[0], part[2]
    bt, bx0, bx1 = head_box(bad)
    dt, dx0, dx1 = head_box(donor)
    out = bad.copy()
    px = out.load()
    for y in range(bt, bt + rows):
        for x in range(bx0, bx1):
            px[x, y] = (0, 0, 0, 0)
    head = donor.crop((dx0, dt, dx1, dt + rows))
    out.alpha_composite(head, ((bx0 + bx1) // 2 - (dx1 - dx0) // 2, bt))
    return out


def clean_specks(im):
    """Local repair: the pale grey motion streaks a template leaves (low saturation, light) made transparent."""
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            c = px[x, y]
            if c[3] >= 128:
                h, s, v = hsv(c)
                if s < 0.18 and v > 0.62:
                    px[x, y] = (0, 0, 0, 0)
    return out


def strips(only):
    for vid, cfg in SOURCES.items():
        if only and vid not in only:
            continue
        src = os.path.join(RAW, cfg["raw"], cfg.get("state", "Idle"))
        hair_until = hair_line(src, cfg.get("hair_band", 0.21))
        rot = [place([Image.open(os.path.join(src, "rotations", f"{d}.png")).convert("RGBA")])[0] for d in DIRS]
        refs = references(rot, hair_until)
        dest = os.path.join(ART, vid)
        os.makedirs(dest, exist_ok=True)
        n = 0
        for anim, spec in cfg["anims"].items():
            for pdir, d in DIRS.items():
                folder = os.path.join(src, "animations", spec.get("dir_from", {}).get(pdir, spec["from"]), pdir)
                if not os.path.isdir(folder):
                    print(f"  {vid}: no {anim} {pdir} (kept the old strip)")
                    continue
                frames = place(load_dir(folder))
                for bad, donor in spec.get("head_from", {}).get(pdir, {}).items():
                    frames[int(bad)] = head_swap(frames[int(bad)], frames[donor])
                if pdir in spec.get("clean", []):
                    frames = [clean_specks(f) for f in frames]
                drop = spec.get("drop", {}).get(pdir, [])
                frames = [f for i, f in enumerate(frames) if i not in drop]
                sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
                for k, f in enumerate(frames):
                    sheet.paste(key(f, refs, hair_until), (k * FRAME, 0))
                sheet.save(os.path.join(dest, f"{anim}_{d}.png"))
                n += 1
        for copy in cfg.get("copies", []):
            cdest = os.path.join(ART, copy)
            os.makedirs(cdest, exist_ok=True)
            for f in os.listdir(dest):
                if f.endswith(".png"):
                    shutil.copyfile(os.path.join(dest, f), os.path.join(cdest, f))
        print(f"  {vid}: {n} strips from {cfg['raw']} (hair to y={hair_until}; refs "
              f"{', '.join(f'{k}={v:.0f}' for k, v in refs.items())})" + (f"; copied to {cfg['copies']}" if cfg.get("copies") else ""))


def regions(out_path):
    flat = {HAIR: (255, 0, 255), SKIN: (255, 200, 0), PRIMARY: (0, 200, 255), SECONDARY: (0, 255, 80)}
    rows = []
    for vid in SOURCES:
        for f in sorted(os.listdir(os.path.join(ART, vid))):
            if f.endswith("_se.png") or f.endswith("_s.png"):
                im = Image.open(os.path.join(ART, vid, f)).convert("RGBA")
                px = im.load()
                for y in range(im.height):
                    for x in range(im.width):
                        r, g, b, a = px[x, y]
                        if a == 254:
                            px[x, y] = flat[int(round(b / 50.0))] + (255,)
                rows.append(im)
    w = max(r.width for r in rows)
    sheet = Image.new("RGBA", (w, FRAME * len(rows)), (60, 50, 40, 255))
    for i, r in enumerate(rows):
        sheet.alpha_composite(r, (0, i * FRAME))
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    sheet.save(out_path)
    print("regions", out_path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", choices=["strips", "frames", "regions"])
    ap.add_argument("out", nargs="?", default="")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    if a.step == "strips":
        strips(only)
    elif a.step == "frames":
        for vid, cfg in SOURCES.items():
            if only and vid not in only:
                continue
            for v in [vid] + cfg.get("copies", []):
                pg.tres(v)
    else:
        regions(a.out)


if __name__ == "__main__":
    main()
