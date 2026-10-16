"""Prepare reference images for painting over in an image generator (ChatGPT / Gemini).
python tools/art/imagegen_prep.py  ->  imagegen/batch1/in/*.png   (see imagegen/batch1/PROMPTS.md)

Portraits: 1024px renders (tools/art/blender/imported.py, portrait_size=1024) on the faction background.
Towns: the 1920x810 town view composited from the layered sprites, padded to 3:2 (1920x1280) because the
generators only output 3:2 / square; ingest crops the band back out. Variants A/B/C cover the upgrade slots."""
import os, json, sys
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from portrait_bg import background, FACTION, PAL

IN = "imagegen/batch1/in"
PAD_W, PAD_H, VIEW_H = 1920, 1280, 810
TOP = (PAD_H - VIEW_H) // 2

OTHERS = ["tavern", "marketplace", "blacksmith"] + [f"dwelling_{k}" for k in range(1, 8)]
VARIANTS = {  # variant -> the buildings shown (upgrade slots + everything else)
    "A": ["village_hall", "fort", "mage_guild_1"] + OTHERS,
    "B": ["town_hall", "citadel", "mage_guild_2"] + OTHERS,
    "C": ["city_hall", "citadel", "mage_guild_2"] + OTHERS,
}

def town_view(faction, ids):
    """Composite like town_screen.gd: background, then built sprites far-to-near by their rect's bottom edge."""
    img = Image.open(f"assets/town/{faction}_bg.png").convert("RGBA")
    layout = json.load(open(f"assets/town/layout_{faction}.json"))
    for sid in sorted([i for i in ids if i in layout], key=lambda i: layout[i][1] + layout[i][3]):
        x, y, w, h = layout[sid]
        spr = Image.open(f"assets/town/{faction}_{sid}.png").convert("RGBA").resize((w, h))
        img.alpha_composite(spr, (x, y))
    return img

def _fill(view, rows, h, lift):
    """Smooth sky/ground fill: the edge rows' colour, averaged and blurred sideways so towers don't streak."""
    band = np.asarray(view.convert("RGB").crop((0, rows[0], PAD_W, rows[1])), dtype=np.float32).mean(axis=0)
    k = 301
    padded = np.pad(band, ((k // 2, k // 2), (0, 0)), mode="edge")
    smooth = np.stack([np.convolve(padded[:, c], np.ones(k) / k, mode="valid") for c in range(3)], axis=1)
    t = np.linspace(0, 1, h)[:, None, None]  # 0 at the outer edge -> 1 next to the scene
    col = smooth[None, :, :] * (lift + (1 - lift) * t)
    return Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB")

def pad(view):
    """Extend the 1920x810 view to 1920x1280 (3:2) with plain sky above and ground below."""
    out = Image.new("RGB", (PAD_W, PAD_H))
    out.paste(_fill(view, (0, 40), TOP, 1.12), (0, 0))
    bot_h = PAD_H - TOP - VIEW_H
    out.paste(_fill(view, (VIEW_H - 40, VIEW_H), bot_h, 0.8).transpose(Image.FLIP_TOP_BOTTOM), (0, TOP + VIEW_H))
    out.paste(view.convert("RGB"), (0, TOP))
    return out

def main():
    os.makedirs(IN, exist_ok=True)
    for hid, fac in FACTION.items():
        raw = f"{IN}/raw_{hid}.png"
        if not os.path.exists(raw):
            print("missing", raw); continue
        fg = Image.open(raw).convert("RGBA")
        bg = background(fg.width, PAL[fac], hash(hid) % 1000)
        bg.alpha_composite(fg)
        bg.convert("RGB").save(f"{IN}/portrait_{hid}.png")
        print("portrait", hid)
    for fac in ("haven", "necropolis"):
        pad(Image.open(f"assets/town/{fac}_bg.png").convert("RGBA")).save(f"{IN}/town_{fac}_bg.png")
        for v, ids in VARIANTS.items():
            pad(town_view(fac, ids)).save(f"{IN}/town_{fac}_{v}.png")
        print("town", fac)

if __name__ == "__main__":
    main()
