"""A resource pile for the adventure map from a painted, keyed take (button_icons_paint.py sheet "sulfur"): the
magenta-tinted smoke dropped, scaled to the old sprite's size, a soft cast shadow added; the anchor in
assets/map/anchors.json is kept (the pile's foot at the canvas bottom).
python tools/art/map_pile.py imagegen/batch20/out/sulfur_a.png res_sulfur"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

src, name = sys.argv[1], sys.argv[2]
old = Image.open(f"assets/map/{name}.png")
im = Image.open(src).convert("RGBA")
a = np.asarray(im).astype(float)
pink = (a[..., 0] > a[..., 1] + 10) & (a[..., 2] > a[..., 1] - 25) & (a[..., 2] > 90)  # (the smoke, tinted by the magenta ground)
a[pink, 3] = 0
a[a[..., 3] < 170, 3] = 0  # (and its faint remains: the pile itself is opaque)
im = Image.fromarray(a.astype(np.uint8))
im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())
W, H = old.size
s = min((W - 12) / im.width, (H - 6) / im.height)
im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
canvas = Image.new("RGBA", (W, H))
sh = Image.new("L", (W, H), 0)
x0 = (W - im.width) // 2
ImageDraw.Draw(sh).ellipse([x0 + im.width * 0.1, H - 16, x0 + im.width * 1.05, H - 2], fill=110)
canvas.paste((0, 0, 0, 255), (5, 0), sh.filter(ImageFilter.GaussianBlur(4)))
canvas.alpha_composite(im, (x0, H - im.height - 3))
canvas.save(f"assets/map/{name}.png")
print("assets/map/%s.png" % name, canvas.size)
