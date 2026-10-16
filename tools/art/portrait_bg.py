"""Composite transparent portrait renders onto painted faction backgrounds (in place, from clean copies).
python tools/art/portrait_bg.py"""
import os, json
import numpy as np
from PIL import Image, ImageFilter

FACTION = {"sir_aldric": "haven", "lady_seraphine": "haven", "lord_gareth": "haven", "brother_tomas": "haven",
           "lord_morthis": "necropolis", "vesna_nightshade": "necropolis", "kragor_the_pale": "necropolis", "ilsa_grimveil": "necropolis"}
PAL = {"haven": ((0.98, 0.85, 0.55), (0.2, 0.32, 0.6)), "necropolis": ((0.45, 0.75, 0.45), (0.12, 0.05, 0.16)),
       "creature": ((0.75, 0.62, 0.42), (0.18, 0.12, 0.08))}

def background(size, pal, seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size] / size
    d = np.sqrt((xx - 0.42) ** 2 + (yy - 0.35) ** 2)
    t = np.clip(d / 0.8, 0, 1)[..., None]
    c0 = np.array(pal[0]); c1 = np.array(pal[1])
    img = c0 * (1 - t) + c1 * t
    n = Image.fromarray((rng.random((size // 8, size // 8)) * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(6))
    img *= (0.85 + 0.3 * np.asarray(n)[..., None] / 255.0)
    vig = np.clip(1.15 - d * 0.9, 0.5, 1.0)[..., None]
    return Image.fromarray((np.clip(img * vig, 0, 1) * 255).astype(np.uint8)).convert("RGBA")

def composite(path, pal, seed):
    """The marker stores the mtime we wrote; any other mtime means a fresh render to keep as the clean copy."""
    clean = os.path.join("tools/art/raw/clean_portraits", path.replace("/", "_"))
    os.makedirs(os.path.dirname(clean), exist_ok=True)
    marker = clean + ".mtime"
    written = open(marker).read() if os.path.exists(marker) else ""
    if written != str(os.path.getmtime(path)) or not os.path.exists(clean):
        Image.open(path).save(clean)
    fg = Image.open(clean).convert("RGBA")
    bg = background(fg.width, pal, seed)
    bg.alpha_composite(fg)
    bg.convert("RGB").save(path)
    open(marker, "w").write(str(os.path.getmtime(path)))

if __name__ == "__main__":
    pj = "assets/heroes/portraits/painted.json"  # painted-over portraits already have their background
    painted = json.load(open(pj)) if os.path.exists(pj) else []
    for i, (hid, f) in enumerate(FACTION.items()):
        p = f"assets/heroes/portraits/{hid}.png"
        if os.path.exists(p) and hid not in painted:
            composite(p, PAL[f], i)
            print("bg", p)
    d = "assets/creatures/portraits"
    cpj = f"{d}/painted.json"
    cpainted = json.load(open(cpj)) if os.path.exists(cpj) else []
    for i, f in enumerate(sorted(os.listdir(d))):
        if f.endswith(".png") and f[:-4] not in cpainted:
            composite(f"{d}/{f}", PAL["creature"], 100 + i)
            print("bg", f)
