"""Measure the solid figure (alpha > 200, i.e. without the soft cast shadow) of each battle creature sprite.
python tools/art/sprite_sizes.py  ->  assets/creatures/sizes.json  {"pikeman.png": [w, h], ...} in texture pixels.
battle.gd scales units to a per-tier on-screen figure height using these. Re-run after re-rendering creatures."""
import os, json
import numpy as np
from PIL import Image

D = "assets/creatures"
out = {}
for f in sorted(os.listdir(D)):
    if f.endswith(".png"):
        a = np.asarray(Image.open(f"{D}/{f}").convert("RGBA"))[..., 3]
        ys, xs = np.nonzero(a > 200)
        out[f] = [int(xs.max() - xs.min()), int(ys.max() - ys.min())]
json.dump(out, open(f"{D}/sizes.json", "w"), indent=0, sort_keys=True)
print(out)
