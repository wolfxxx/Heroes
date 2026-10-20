"""Artifacts as they lie on the adventure map (as the classic map shows the item itself, not a card): each painted
artifact (imagegen/batch27/out, from artifact_icons.py) keyed off its dark wine-red ground, cropped to the item and
given a soft cast shadow.
python tools/art/artifact_map_sprites.py [ids...]   ->  assets/map/art_<id>.png (about 96 px tall, transparent)"""
import os, sys, glob
import numpy as np
from PIL import Image, ImageFilter

SRC = "imagegen/batch27/out"
OUT = "assets/map"
H = 96


def key(img):
    a = np.asarray(img.convert("RGB")).astype(float)
    hh, ww, _ = a.shape
    # the ground: a vertical gradient, sampled per row from the left and right edges
    edge = np.concatenate([a[:, :ww // 14], a[:, -ww // 14:]], axis=1)
    bg = np.median(edge, axis=1)[:, None, :]
    d = np.sqrt(((a - bg) ** 2).sum(axis=2))
    # how far a pixel is from the ground colour; dark pixels near it are ground, bright or saturated ones the item
    lum = a.mean(axis=2)
    alpha = np.clip((d - 26.0) / 30.0, 0.0, 1.0)
    alpha = np.maximum(alpha, np.clip((lum - 120.0) / 40.0, 0.0, 1.0))
    m = Image.fromarray((alpha * 255).astype(np.uint8))
    m = m.filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    # the item's dark parts are close to the ground colour: everything inside its outline is solid (holes filled by a
    # flood of the outside from the border), only the rim stays soft
    solid = (np.asarray(m) > 90).astype(np.uint8) * 255
    sm = Image.fromarray(solid).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    from PIL import ImageDraw
    flood = sm.copy()
    fw, fh = flood.size
    for x in range(0, fw, 4):  # (the outside, from every free border pixel: a light beam may touch a corner)
        for y in (0, fh - 1):
            if flood.getpixel((x, y)) == 0:
                ImageDraw.floodfill(flood, (x, y), 128)
    for y in range(0, fh, 4):
        for x in (0, fw - 1):
            if flood.getpixel((x, y)) == 0:
                ImageDraw.floodfill(flood, (x, y), 128)
    # small enclosed holes are the item's own dark parts (filled); large ones are real openings, a ring's middle (kept)
    arr = np.asarray(flood).copy()
    holes = np.argwhere(arr == 0)
    for (y, x) in holes:
        if flood.getpixel((int(x), int(y))) != 0:
            continue
        ImageDraw.floodfill(flood, (int(x), int(y)), 64)
        region = np.asarray(flood) == 64
        # (a real opening shows the plain ground: smooth and close to its colour; the item's dark parts have detail)
        keep = region.sum() > fw * fh * 0.012 and float(d[region].mean()) < 16.0 and float(d[region].std()) < 9.0
        flood.paste(Image.fromarray(np.where(region, 128 if keep else 255, np.asarray(flood)).astype(np.uint8)))
    inside = (np.asarray(flood) != 128)
    am = np.maximum(np.asarray(m).astype(float), np.asarray(Image.fromarray((inside * 255).astype(np.uint8))
                                                             .filter(ImageFilter.MinFilter(3))).astype(float))
    m = Image.fromarray(am.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))
    out = img.convert("RGBA")
    out.putalpha(m)
    return out


def sprite(a):
    src = f"{SRC}/artifact_{a}.png"
    if not os.path.exists(src):
        print("  no painting:", a); return
    item = key(Image.open(src))
    box = item.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    if not box:
        print("  empty:", a); return
    item = item.crop(box)
    s = H / max(item.width, item.height)
    item = item.resize((max(1, round(item.width * s)), max(1, round(item.height * s))), Image.LANCZOS)
    pad = 10
    canvas = Image.new("RGBA", (item.width + pad * 2, item.height + pad * 2 + 8))
    # a soft shadow on the ground under it
    sh = Image.new("L", canvas.size, 0)
    from PIL import ImageDraw
    ImageDraw.Draw(sh).ellipse([pad + item.width * 0.12, canvas.height - 20, pad + item.width * 0.88, canvas.height - 6], fill=120)
    sh = sh.filter(ImageFilter.GaussianBlur(4))
    canvas.paste((0, 0, 0, 255), (0, 0), sh)
    canvas.alpha_composite(item, (pad, pad))
    canvas.save(f"{OUT}/art_{a}.png")
    print("  map/art_%s.png" % a)


if __name__ == "__main__":
    ids = sys.argv[1:] or [os.path.basename(p)[9:-4] for p in sorted(glob.glob(f"{SRC}/artifact_*.png"))]
    for a in ids:
        sprite(a)
