#!/usr/bin/env python3
"""Local processing (Pillow, no credits) of the town builder's sprites (docs/protocolos/generar-ciudad.md §Sprites).

  python3 tools/city/sprites_ciudad.py back <a..f> RAW      # back view of a filler house from a fal edit
  python3 tools/city/sprites_ciudad.py lantern RAW          # the street lantern from a fal generation
  python3 tools/city/sprites_ciudad.py fence                # the field fence, drawn by code (deterministic)
  python3 tools/city/sprites_ciudad.py sheet DST            # contact sheet of everything, x3

back: the fal output is the reference (the house x4 on a 64 px white margin) scaled by the model; it is scaled back
to the reference canvas, the margin cut, the white background keyed by flood fill, reduced x4 with the dominant
colour of each 4x4 block and snapped to the palette of the original house. The silhouette is the original's (same
size, same Feet), so the back view drops into the same scene offsets.
"""
import os
import sys
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "assets", "art")
PAD = 64
FACTOR = 4


def key_white(im, tol=28):
    """Flood fill from the border: near-white pixels touching it become transparent."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    seen = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        seen[y * w + x] = 1
        r, g, b, a = px[x, y]
        if not (r > 255 - tol and g > 255 - tol and b > 255 - tol):
            continue
        px[x, y] = (0, 0, 0, 0)
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return im


def dominant_reduce(im, size):
    """Each target pixel takes the most common colour of its source block (transparent if most of it is)."""
    w, h = size
    src = im.load()
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    dst = out.load()
    bw, bh = im.width / w, im.height / h
    for y in range(h):
        for x in range(w):
            x0, x1 = int(x * bw), max(int(x * bw) + 1, int((x + 1) * bw))
            y0, y1 = int(y * bh), max(int(y * bh) + 1, int((y + 1) * bh))
            # the centre of the block weighs more (block edges mix neighbours in the model's soft pixels)
            cs = Counter()
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    c = src[xx, yy]
                    cs[(c[0] // 8 * 8, c[1] // 8 * 8, c[2] // 8 * 8, 255) if c[3] > 127 else (0, 0, 0, 0)] += 1
            dst[x, y] = cs.most_common(1)[0][0]
    return out


def palette_of(im):
    return sorted({c[:3] for c in im.getdata() if c[3] > 127})


def snap(im, pal):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            best = min(pal, key=lambda p: (p[0] - r) ** 2 * 3 + (p[1] - g) ** 2 * 4 + (p[2] - b) ** 2 * 2)
            px[x, y] = best + (255,)
    return im


def back(letter, raw):
    orig_p = os.path.join(ART, "buildings", "escala_b", f"house_{letter}.png")
    orig = Image.open(orig_p).convert("RGBA")
    ref_w, ref_h = orig.width * FACTOR + 2 * PAD, orig.height * FACTOR + 2 * PAD
    ai = Image.open(raw).convert("RGBA").resize((ref_w, ref_h), Image.LANCZOS)
    ai = key_white(ai)
    ai = ai.crop((PAD, PAD, PAD + orig.width * FACTOR, PAD + orig.height * FACTOR))
    small = snap(dominant_reduce(ai, orig.size), palette_of(orig))
    # the original's silhouette: where the model left a hole or a halo, the original pixel stays
    o, s = orig.load(), small.load()
    for y in range(orig.height):
        for x in range(orig.width):
            if o[x, y][3] < 128:
                s[x, y] = (0, 0, 0, 0)
            elif s[x, y][3] == 0:
                s[x, y] = o[x, y]
    dst = os.path.join(ART, "buildings", "escala_b", f"house_{letter}_back.png")
    small.save(dst)
    a_o = sum(1 for c in orig.getdata() if c[3] > 127)
    print(f"back {letter}: {os.path.relpath(dst, ROOT)} {small.size} ({a_o} px opacos, paleta {len(palette_of(orig))})")


def lantern(raw, height=60):
    im = key_white(Image.open(raw).convert("RGBA"))
    bb = im.getbbox()
    im = im.crop(bb)
    w = max(1, round(im.width * height / im.height))
    small = dominant_reduce(im, (w, height))
    ref = Image.open(os.path.join(ART, "props", "sign_post.png")).convert("RGBA")
    torch = Image.open(os.path.join(ART, "props", "torch.png")).convert("RGBA")
    small = snap(small, sorted(set(palette_of(ref)) | set(palette_of(torch))))
    out = Image.new("RGBA", (32, 64), (0, 0, 0, 0))
    out.alpha_composite(small, ((32 - small.width) // 2, 64 - small.height - 2))
    dst = os.path.join(ART, "props", "lantern.png")
    out.save(dst)
    print(f"lantern: {os.path.relpath(dst, ROOT)} {out.size} (figura {small.size})")


# The fence: one segment along a tile edge seen as "\" (the col axis of the 2:1 projection: 32 px across, 16 down);
# the scene flips it for the "/" edges. Wood of the bench and the cart, dark outline of the style bible.
WOOD = [(0x3a, 0x26, 0x18), (0x6b, 0x47, 0x2a), (0x8f, 0x64, 0x3c), (0xb0, 0x84, 0x52)]


def fence():
    w, h = 36, 42
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()

    def put(x, y, c):
        if 0 <= x < w and 0 <= y < h:
            px[x, y] = c + (255,)

    base_y = 23  # the left post's foot; the edge drops 1 px every 2 across (2:1)
    posts = [2, 17, 32]
    for rail_h, shade in ((7, 2), (13, 2)):
        for x in range(2, 34):
            y = base_y + (x - 2) // 2 - rail_h
            put(x, y - 1, WOOD[0])
            put(x, y, WOOD[shade + 1] if x % 5 else WOOD[shade])
            put(x, y + 1, WOOD[1])
            put(x, y + 2, WOOD[0])
    for px0 in posts:
        foot = base_y + (px0 - 2) // 2
        for y in range(foot - 17, foot + 1):
            put(px0 - 1, y, WOOD[0])
            put(px0, y, WOOD[2])
            put(px0 + 1, y, WOOD[1])
            put(px0 + 2, y, WOOD[0])
        put(px0, foot - 18, WOOD[0])
        put(px0 + 1, foot - 18, WOOD[0])
        put(px0, foot - 17, WOOD[3])
    dst = os.path.join(ART, "props", "fence.png")
    im.save(dst)
    print(f"fence: {os.path.relpath(dst, ROOT)} {im.size}")


def sheet(dst):
    names = [os.path.join("props", "lantern.png"), os.path.join("props", "fence.png")]
    names += [os.path.join("buildings", "escala_b", f"house_{c}{s}.png") for c in "abcdef" for s in ("", "_back")]
    ims = [Image.open(os.path.join(ART, n)).convert("RGBA") for n in names if os.path.exists(os.path.join(ART, n))]
    W = sum(i.width for i in ims) + 8 * len(ims)
    H = max(i.height for i in ims)
    out = Image.new("RGBA", (W, H), (95, 138, 58, 255))
    x = 0
    for i in ims:
        out.alpha_composite(i, (x, H - i.height))
        x += i.width + 8
    out.resize((W * 3, H * 3), Image.NEAREST).save(dst)
    print("sheet:", dst)


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd = argv[0]
    if cmd == "back":
        back(argv[1], argv[2])
    elif cmd == "lantern":
        lantern(argv[1])
    elif cmd == "fence":
        fence()
    elif cmd == "sheet":
        sheet(argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
