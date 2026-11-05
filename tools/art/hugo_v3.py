#!/usr/bin/env python3
"""Hugo (artisan_m) regenerated with PixelLab v3 «high detail» straight at scale B (docs/arte/escala.md, decision
«Personajes con más detalle a la misma escala», opción A): a 52 px canvas, the figure 51 px; nothing reduced.

The PixelLab character 2ce0e22c-cc5d-4670-8f29-7626137ab905 (8 rotations, 2 generations; «forge_east», 8 frames on a
76 px canvas, 1 generation, played as forge_se; a first south-east clip, 1 generation, faced the camera: not used) is downloaded to the raw art folder and packed like tools/art/personajes_guild.py
does: 68 px frames with the feet at (34, 58) (the Sprite offset of artisan_m.tscn), the H8 identity keyed in
(hair, skin, shirt = primary, trousers = secondary) with this sprite's own colour rules.

Source frames, in the repo: assets/art/characters/artisan_m_v3/ (rotations/<direction>.png, 52 px, and
forge_east/frame_NNN.png, 76 px; a .gdignore keeps Godot from importing them). The faces of the five directions
that show one (south, south-east, east, west, south-west) and of the eight forge frames were retouched by hand with
PixelLab's pixelart_workbench (no generations; docs/decisiones.json, 2026-11-05) so that they read at zoom 1 like the
old Hugo's: pupils almost black and both eyes white + pupil, the mouth a shade darker, the line under the chin a
shade darker than the neck. The untouched PixelLab download stays in the raw folder.

  python3 tools/art/hugo_v3.py fetch     # ZIP from PixelLab to ~/Code/GuildMaster-arte-crudos/pixellab/hugo_v3/
  python3 tools/art/hugo_v3.py strips    # idle_<dir> (the 8 rotations) and forge_se over the old strips
  python3 tools/art/hugo_v3.py preview   # keyed frames recoloured with sample identities (to the raw folder)

Not wired yet (docs/decisiones.json, 2026-11-05): with only idle and forge from v3, Hugo would change body when he
walks (the Guild Renew walk is slimmer, with a bigger head). Wire it once the walk exists (assets/art/MANIFEST.md,
PixelLab shopping list, row 13): `strips`, then personajes_guild.tres("artisan_m") and godot --import. Until then
walk, work, death and forge in the other directions are the Guild Renew ones (the interior plays forge only facing
south-east: interior_view.gd STAND).
"""
import colorsys
import glob
import os
import subprocess
import sys
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fal_rutas as fr_  # noqa: E402
import personajes_guild as pg  # noqa: E402

CHAR_ID = "2ce0e22c-cc5d-4670-8f29-7626137ab905"
RAW = os.path.join(fr_.CRUDOS, "pixellab", "hugo_v3")
OUT = os.path.join(pg.ART, "artisan_m")
SRC = os.path.join(pg.ART, "artisan_m_v3")  # the source frames, retouched (see the module doc)
FEET = (34, 58)  # in a 68 px frame (artisan_m.tscn: Sprite offset (-34, -58))
BODY_X = (24, 41)  # the body's columns in the 68 px forge frames (the shirt, x 26-40); the hammer swings outside
GDIRS = {"south": "s", "south-east": "se", "east": "e", "north-east": "ne", "north": "n", "north-west": "nw",
         "west": "w", "south-west": "sw"}


def is_skin(h, s, v, rel):
    # the apron's highlights are skin-coloured too (h 20, s 0.5, v 0.8): skin is the lighter, less saturated tone
    return (h <= 28 or h >= 350) and 0.12 <= s <= 0.45 and v >= 0.84


def region(h, s, v, rel):
    if is_skin(h, s, v, rel):
        return pg.SKIN
    if rel < 0.23 and (h <= 40 or h >= 340) and 0.25 <= s <= 0.75 and 0.1 <= v <= 0.45:
        return pg.HAIR        # (to 0.23: the retouched jaw line, at 0.25, is skin shadow, not hair)
    if rel > 0.15 and ((15 <= h <= 70 and s < 0.2 and v > 0.25) or (s < 0.04 and v > 0.85)):
        return pg.PRIMARY      # the linen shirt, with its warm grey shadows (the hammer's greys are cool: h 200-220)
    if 195 <= h <= 235 and s > 0.25 and v > 0.15:
        return pg.SECONDARY    # the trousers
    return 0


def refs(im):
    bb = im.getbbox()
    vals = {pg.HAIR: [], pg.SKIN: [], pg.PRIMARY: [], pg.SECONDARY: []}
    for y in range(bb[1], bb[3]):
        for x in range(bb[0], bb[2]):
            r, g, b, a = im.getpixel((x, y))
            if a < 128:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            k = region(h * 360, s, v, (y - bb[1]) / (bb[3] - bb[1]))
            if k:
                vals[k].append(pg.lum((r, g, b)))
    return {k: (sorted(v)[len(v) // 2] if v else 128.0) for k, v in vals.items()}


def key(im, rf, body_x=None):
    """pg.key_frame with this sprite's regions (rel measured on the figure's own height). body_x: in the forge frames
    the shirt stays within the body's columns (the hammer, swung out, has the same warm greys)."""
    out = im.copy()
    px = out.load()
    bb = im.getbbox()
    if bb is None:
        return out
    top, height = bb[1], max(1, bb[3] - bb[1])
    for y in range(bb[1], bb[3]):
        for x in range(bb[0], bb[2]):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            k = region(h * 360, s, v, (y - top) / height)
            if k == pg.PRIMARY and body_x is not None and not body_x[0] <= x <= body_x[1]:
                k = 0
            if k == 0:
                px[x, y] = (r, g, b, 255)
                continue
            shade = pg.lum((r, g, b)) / max(1.0, rf[k])
            shade = min(2.0, 1.0 + (shade - 1.0) * (0.5 if k == pg.HAIR else 0.8))
            px[x, y] = (int(round(shade * 127.5)), 0, k * 50, 254)
    return out


def to_frame(im, feet):
    """A frame of 68 with the sprite's feet (x, y in its own canvas) at FEET."""
    f = Image.new("RGBA", (pg.FRAME, pg.FRAME), (0, 0, 0, 0))
    f.paste(im, (FEET[0] - feet[0], FEET[1] - feet[1]), im)  # paste: the offset may be negative (76 px canvas)
    return f


def no_anvil(im, k):
    """Erases the anvil PixelLab drew at the hero's feet (76 px canvas: right of x 44, below y 49; in the first three
    frames, with the hammer up, from y 46: the anvil's top) and its orange sparks."""
    im = im.copy()
    px = im.load()
    floor = 46 if k <= 2 else 49
    for y in range(im.height):
        for x in range(44, im.width):
            r, g, b, a = px[x, y]
            if not a:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if y >= floor or (y >= 44 and 0.02 < h < 0.15 and s > 0.5 and v > 0.6):
                px[x, y] = (0, 0, 0, 0)
    return im


def fetch():
    os.makedirs(RAW, exist_ok=True)
    z = os.path.join(RAW, "hugo_v3.zip")
    subprocess.run(["curl", "-sL", "-o", z, f"https://api.pixellab.ai/mcp/characters/{CHAR_ID}/download"], check=True)
    zipfile.ZipFile(z).extractall(RAW)
    print("descargado en", RAW)


def strips():
    rot = {GDIRS[os.path.basename(p)[:-4]]: Image.open(p).convert("RGBA")
           for p in glob.glob(os.path.join(SRC, "rotations", "*.png"))}
    rf = refs(rot["s"])
    # feet: the bottom of the figure, centred on the canvas (PixelLab centres the character)
    for d, im in rot.items():
        feet = (im.width // 2, im.getbbox()[3])
        key(to_frame(im, feet), rf).save(os.path.join(OUT, f"idle_{d}.png"))
    # forge: the east clip (profile, facing the anvil, the hammer over the head and down onto it), without the small
    # anvil PixelLab drew into it (the room has its own). The south-east clip (group 040fc3f3) faced the camera and
    # the hammer stayed at the hip: kept in the raw folder, not used.
    frames = [no_anvil(Image.open(p).convert("RGBA"), k) for k, p in enumerate(
        sorted(glob.glob(os.path.join(SRC, "forge_east", "*.png"))))]
    if frames:
        bottom = max(f.getbbox()[3] for f in frames)
        sheet = Image.new("RGBA", (pg.FRAME * len(frames), pg.FRAME), (0, 0, 0, 0))
        for k, f in enumerate(frames):
            sheet.alpha_composite(key(to_frame(f, (f.width // 2, bottom)), rf, body_x=BODY_X), (k * pg.FRAME, 0))
        sheet.save(os.path.join(OUT, "forge_se.png"))
    print(f"artisan_m: idle_<8 dirs> (1 frame) y forge_se ({len(frames)} frames) del v3; refs "
          + ", ".join(f"{k}={v:.0f}" for k, v in rf.items()))


def preview():
    cols = [{1: (40, 28, 20), 2: (240, 200, 160), 3: (139, 46, 46), 4: (200, 168, 78)},
            {1: (150, 90, 40), 2: (150, 100, 70), 3: (40, 70, 140), 4: (60, 110, 60)}]
    names = [f"idle_{d}" for d in ("s", "se", "e", "ne", "n", "nw", "w", "sw")]
    fr = [Image.open(os.path.join(OUT, n + ".png")).convert("RGBA").crop((0, 0, 68, 68)) for n in names]
    fs = Image.open(os.path.join(OUT, "forge_se.png")).convert("RGBA")
    fr += [fs.crop((k * 68, 0, k * 68 + 68, 68)) for k in range(fs.width // 68)]
    S = Image.new("RGBA", (68 * len(fr), 68 * len(cols)), (90, 70, 50, 255))
    for j, c in enumerate(cols):
        for i, f in enumerate(fr):
            S.alpha_composite(pg.unkey(f, c), (68 * i, 68 * j))
    p = os.path.join(RAW, "preview.png")
    S.resize((S.width * 3, S.height * 3), Image.NEAREST).save(p)
    print("muestra en", p)


if __name__ == "__main__":
    {"fetch": fetch, "strips": strips, "preview": preview}[sys.argv[1] if len(sys.argv) > 1 else "strips"]()
