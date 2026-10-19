"""Removes the faint second shadow the tree renders cast up and to the right (it showed as a grey ghost on snow):
faint pixels in the upper part of the sprite, away from the tree itself. The ground shadow at the foot stays.
python tools/art/tree_ghost_clean.py"""
import glob
import numpy as np
from PIL import Image, ImageFilter

for f in sorted(glob.glob("assets/map/tree_*.png") + glob.glob("assets/map/snow_pine_*.png")):
    im = Image.open(f).convert("RGBA")
    px = np.asarray(im).copy()
    a = px[..., 3].astype(np.int32)
    solid = Image.fromarray(((a >= 120) * 255).astype(np.uint8))
    near = np.asarray(solid.filter(ImageFilter.MaxFilter(7))) > 0
    h = a.shape[0]
    ys = np.arange(h)[:, None] * np.ones_like(a)
    ghost = (a > 0) & (a < 120) & (~near) & (ys < h * 0.62)
    px[ghost, 3] = 0
    # and the faint haze over the whole canvas (a pale box on snow): the ground shadow keeps its body and soft edge
    low = (~near) & (ys >= h * 0.62)
    px[low, 3] = np.clip((a[low] - 22) * 1.2, 0, 255).astype(np.uint8)
    Image.fromarray(px).save(f)
    print(f, int(ghost.sum()))
