#!/usr/bin/env python3
"""Characters from Guild Renew (docs/arte/reuso_guild.md): PixelLab frames (68×68, 8 directions) packed into strips with
the H8 identity keyed in, and their Godot SpriteFrames. No credits spent.

  python3 tools/art/personajes_guild.py strips [--guild ~/Code/guild]   # PNG strips (then: godot --import)
  python3 tools/art/personajes_guild.py frames                          # game/visuals/characters/<id>_frames.tres
  python3 tools/art/personajes_guild.py preview DIR                     # keyed frames recoloured, to look at

Strips: assets/art/characters/<id>/<anim>_<dir>.png (one row, 68 px frames; dirs s se e ne n nw w sw). The palette
swap of H8 (GDD 4.10.9: hair, skin and the family's two colours) is keyed into the pixels: a pixel of one of those
regions gets alpha 254, its region in blue (50 hair, 100 skin, 150 primary clothes, 200 secondary clothes) and its
shade in red (its brightness over the region's reference, ×127.5); every other pixel keeps its colour (outline, apron,
boots, tools). The shader game/visuals/characters/identity_swap.gdshader paints the keyed pixels with the person's
colours. The regions come from per-sprite rules (hue, saturation, value and how high on the figure the pixel is).
"""
import argparse
import colorsys
import os
import re
import sys

from PIL import Image

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "assets", "art", "characters")
VIS = os.path.join(ROOT, "game", "visuals", "characters")
DIRS = {"south": "s", "south-east": "se", "east": "e", "north-east": "ne", "north": "n", "north-west": "nw",
        "west": "w", "south-west": "sw"}
HAIR, SKIN, PRIMARY, SECONDARY = 1, 2, 3, 4


def is_skin(h, s, v):
    return (h <= 28 or h >= 350) and 0.12 <= s <= 0.6 and v >= 0.78


# Per sprite: which pixels are hair, primary and secondary clothes (h in degrees, rel = 0 at the top of the figure,
# 1 at its feet). Skin is common. Anything else keeps its colour.
def rules_artesano(h, s, v, rel):
    if rel < 0.3 and v < 0.4 and s < 0.35 and v > 0.08 and not is_skin(h, s, v):
        return HAIR
    if rel > 0.2 and s < 0.12 and v > 0.72:
        return PRIMARY       # the linen tunic
    if 190 <= h <= 220 and s > 0.6 and v > 0.12:
        return SECONDARY     # the trousers
    return 0


def rules_artesana(h, s, v, rel):
    if rel < 0.34 and v < 0.52 and v > 0.1 and (h < 30 or h > 340) and not is_skin(h, s, v):
        return HAIR
    if rel > 0.22 and 28 <= h <= 48 and 0.18 <= s <= 0.42 and v > 0.6:
        return PRIMARY       # the dress
    if 220 <= h <= 270 and s > 0.3 and v > 0.15:
        return SECONDARY     # sleeves and belt
    return 0


def rules_aldeano(h, s, v, rel):
    if rel < 0.27 and 0.18 < v < 0.42 and (h < 30 or h > 340) and not is_skin(h, s, v):
        return HAIR
    if rel > 0.25 and (h < 25 or h > 345) and 0.38 <= s <= 0.62 and 0.4 <= v <= 0.62:
        return PRIMARY       # the tunic
    if rel > 0.25 and 10 <= h <= 30 and 0.18 <= s <= 0.32 and v > 0.6:
        return SECONDARY     # the shirt and hose
    return 0


def rules_aldeana(h, s, v, rel):
    if rel < 0.3 and 0.18 < v < 0.42 and s < 0.48 and (h < 20 or h > 330) and not is_skin(h, s, v):
        return HAIR
    if rel > 0.25 and (h < 10 or h > 350) and 0.45 <= s <= 0.7 and 0.42 <= v <= 0.8:
        return PRIMARY       # the red dress
    if rel > 0.25 and s < 0.14 and v > 0.88:
        return SECONDARY     # the apron
    return 0


SOURCES = {  # visual id -> (guild folder, rules, {our anim: guild anim folder})
    "artisan_m": ("characters/artesano", rules_artesano, {"idle": "idle", "walk": "walk", "work": "work", "forge": "forge", "death": "death"}),
    "artisan_f": ("characters/artesana", rules_artesana, {"idle": "idle", "walk": "walk", "work": "work", "forge": "forge", "death": "death"}),
    "worker_m": ("characters/artesano", rules_artesano, {"idle": "idle", "walk": "walk", "work": "work", "forge": "forge", "death": "death"}),
    "worker_f": ("characters/artesana", rules_artesana, {"idle": "idle", "walk": "walk", "work": "work", "forge": "forge", "death": "death"}),
    "townsfolk_m": ("npcs/aldeano_hombre", rules_aldeano, {"idle": "idle", "walk": "walk"}),
    "townsfolk_f": ("npcs/aldeana_mujer", rules_aldeana, {"idle": "idle", "walk": "walk"}),
}
FPS = {"idle": 5.0, "walk": 9.0, "work": 8.0, "forge": 8.0, "death": 7.0}
LOOP = {"idle": True, "walk": True, "work": True, "forge": True, "death": False}
FRAME = 68


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def frames_of(guild, folder, anim):
    out = {}
    base = os.path.join(guild, "assets", "sprites", folder, "animations", anim)
    for gdir, d in DIRS.items():
        p = os.path.join(base, gdir)
        if not os.path.isdir(p):
            continue
        files = sorted(f for f in os.listdir(p) if re.match(r"frame_\d+\.png$", f))
        out[d] = [Image.open(os.path.join(p, f)).convert("RGBA") for f in files]
    return out


def key_frame(im, rules, refs):
    """The frame with its identity regions keyed (see the module doc). refs: region -> reference brightness."""
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
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            h *= 360.0
            region = SKIN if is_skin(h, s, v) else rules(h, s, v, (y - top) / height)
            if region == 0:
                px[x, y] = (r, g, b, 255)
                continue
            shade = lum((r, g, b)) / max(1.0, refs[region])
            shade = min(2.0, 1.0 + (shade - 1.0) * (0.5 if region == HAIR else 0.8))  # softer: light targets do not burn
            px[x, y] = (int(round(shade * 127.5)), 0, region * 50, 254)
    return out


def references(guild, folder, rules):
    """Reference brightness of each region: the median over the south rotation."""
    im = Image.open(os.path.join(guild, "assets", "sprites", folder, "rotations", "south.png")).convert("RGBA")
    bb = im.getbbox()
    px = im.load()
    vals = {HAIR: [], SKIN: [], PRIMARY: [], SECONDARY: []}
    for y in range(bb[1], bb[3]):
        for x in range(bb[0], bb[2]):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            h *= 360.0
            region = SKIN if is_skin(h, s, v) else rules(h, s, v, (y - bb[1]) / (bb[3] - bb[1]))
            if region:
                vals[region].append(lum((r, g, b)))
    return {k: (sorted(v)[len(v) // 2] if v else 128.0) for k, v in vals.items()}


def strips(guild):
    for vid, (folder, rules, anims) in SOURCES.items():
        refs = references(guild, folder, rules)
        d = os.path.join(ART, vid)
        os.makedirs(d, exist_ok=True)
        n = 0
        for anim, gname in anims.items():
            for direction, frames in frames_of(guild, folder, gname).items():
                sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
                for k, f in enumerate(frames):
                    sheet.paste(key_frame(f, rules, refs), (k * FRAME, 0))
                sheet.save(os.path.join(d, f"{anim}_{direction}.png"))
                n += 1
        print(f"  {vid}: {n} strips from guild:{folder} (refs {', '.join(f'{k}={v:.0f}' for k, v in refs.items())})")


def tres(vid):
    """The SpriteFrames of `vid`: <anim>_<dir> for every strip, plus <anim> (= its south strip) for every anim, and the
    contract's empty anims (carry, talk, sit) so callers can ask for them."""
    d = os.path.join(ART, vid)
    strips_ = sorted(f[:-4] for f in os.listdir(d) if f.endswith(".png"))
    ext, subs, anims = [], [], []
    for i, name in enumerate(strips_):
        imp = open(os.path.join(d, name + ".png.import")).read()
        uid = re.search(r'uid="(uid://[^"]+)"', imp).group(1)
        ext.append(f'[ext_resource type="Texture2D" uid="{uid}" path="res://assets/art/characters/{vid}/{name}.png" id="{i + 1}_{name}"]')
    sub_n = 0
    entries = []
    for i, name in enumerate(strips_):
        w = Image.open(os.path.join(d, name + ".png")).size[0]
        ids = []
        for k in range(w // FRAME):
            sub_n += 1
            sid = f"a{sub_n}"
            subs.append(f'[sub_resource type="AtlasTexture" id="{sid}"]\natlas = ExtResource("{i + 1}_{name}")\n'
                        f'region = Rect2({k * FRAME}, 0, {FRAME}, {FRAME})')
            ids.append(sid)
        anim = name.rsplit("_", 1)[0]
        entries.append((name, anim, ids))
        if name.endswith("_s"):
            entries.append((anim, anim, ids))
    have = {e[0] for e in entries}
    for extra in ("idle", "walk", "work", "carry", "talk", "sit", "death"):
        if extra not in have:
            entries.append((extra, extra, entries[[e[0] for e in entries].index("idle_s")][2] if extra in ("carry", "talk", "sit") else []))
    for name, anim, ids in sorted(entries):
        frames = ",\n".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % s for s in ids)
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}' % (
            ("\n" + frames + "\n") if ids else "", "true" if LOOP.get(anim, True) else "false", name, FPS.get(anim, 6.0)))
    old = open(os.path.join(VIS, f"{vid}_frames.tres")).readline()
    head_uid = re.search(r'uid="(uid://[^"]+)"', old).group(1)
    body = (f'[gd_resource type="SpriteFrames" load_steps={len(ext) + sub_n + 1} format=3 uid="{head_uid}"]\n\n'
            + "\n".join(ext) + "\n\n" + "\n\n".join(subs) + "\n\n[resource]\nanimations = [" + ", ".join(anims) + "]\n")
    open(os.path.join(VIS, f"{vid}_frames.tres"), "w").write(body)
    print(f"  {vid}_frames.tres: {len(entries)} animations, {sub_n} frames")


def preview(folder, out_dir):
    """Every visual id's south idle and walk frames, recoloured with sample identities (what the shader does)."""
    os.makedirs(out_dir, exist_ok=True)
    samples = [((200, 60, 50), (230, 200, 120), (70, 45, 30), (224, 180, 140)),
               ((50, 80, 140), (220, 210, 190), (200, 170, 80), (160, 110, 80)),
               ((60, 110, 60), (140, 90, 50), (30, 25, 25), (240, 200, 170))]
    ids = list(SOURCES)
    sheet = Image.new("RGBA", (len(ids) * FRAME * 4, (len(samples) + 1) * FRAME * 2), (96, 104, 92, 255))
    for i, vid in enumerate(ids):
        im = Image.open(os.path.join(ART, vid, "walk_se.png")).convert("RGBA").crop((0, 0, FRAME, FRAME))
        sheet.alpha_composite(unkey(im, None).resize((FRAME * 2, FRAME * 2), Image.NEAREST), (i * FRAME * 4, 0))
        for j, (p, s2, hair, skin) in enumerate(samples):
            col = {HAIR: hair, SKIN: skin, PRIMARY: p, SECONDARY: s2}
            sheet.alpha_composite(unkey(im, col).resize((FRAME * 2, FRAME * 2), Image.NEAREST),
                                  (i * FRAME * 4, (j + 1) * FRAME * 2))
            s_im = Image.open(os.path.join(ART, vid, "idle_s.png")).convert("RGBA").crop((0, 0, FRAME, FRAME))
            sheet.alpha_composite(unkey(s_im, col).resize((FRAME * 2, FRAME * 2), Image.NEAREST),
                                  (i * FRAME * 4 + FRAME * 2, (j + 1) * FRAME * 2))
    p = os.path.join(out_dir, "personajes.png")
    sheet.save(p)
    print("preview", p)


def unkey(im, col):
    """Paints the keyed pixels (None = show the regions in flat test colours)."""
    out = im.copy()
    px = out.load()
    flat = {HAIR: (255, 0, 255), SKIN: (255, 200, 0), PRIMARY: (0, 200, 255), SECONDARY: (0, 255, 80)}
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 254:
                region = int(round(b / 50.0))
                base = (col or flat)[region]
                k = r / 127.5 if col else 1.0
                px[x, y] = (min(255, int(base[0] * k)), min(255, int(base[1] * k)), min(255, int(base[2] * k)), 255)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", choices=["strips", "frames", "preview"])
    ap.add_argument("out", nargs="?", default="")
    ap.add_argument("--guild", default=os.path.expanduser("~/Code/guild"))
    a = ap.parse_args()
    if a.step == "strips":
        strips(a.guild)
    elif a.step == "frames":
        for vid in SOURCES:
            tres(vid)
    else:
        preview(ART, a.out)


if __name__ == "__main__":
    main()
