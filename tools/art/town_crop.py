"""Crop full-frame town building layers to their content and write assets/town/layout_<faction>.json
({sprite_id: [x, y, w, h]} in the 1920x810 town view). Re-running on cropped files keeps the old layout.
python tools/art/town_crop.py"""
import os, json
from PIL import Image, ImageFilter, ImageChops

SPRITES = ["village_hall", "town_hall", "city_hall", "fort", "citadel", "tavern", "marketplace", "mage_guild_1", "mage_guild_2",
           "blacksmith"] + [f"dwelling_{k}" for k in range(1, 8)]
for f in ("haven", "necropolis"):
    lp = f"assets/town/layout_{f}.json"
    layout = json.load(open(lp)) if os.path.exists(lp) else {}
    for sid in SPRITES:
        p = f"assets/town/{f}_{sid}.png"
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA")
        if im.size != (1920, 810):
            continue  # already cropped
        # keep the building (opaque) plus a margin for its own shadow; drop faint shadow-catcher noise elsewhere
        a = im.getchannel("A")
        solid = a.point(lambda v: 255 if v > 200 else 0).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MaxFilter(9))
        for _ in range(6):
            solid = solid.filter(ImageFilter.MaxFilter(15))
        a = ImageChops.multiply(a, solid).point(lambda v: 0 if v < 22 else v)
        im.putalpha(a)
        bbox = a.getbbox()
        if not bbox:
            continue
        x0, y0, x1, y1 = bbox
        im.crop(bbox).save(p)
        layout[sid] = [x0, y0, x1 - x0, y1 - y0]
    json.dump(layout, open(lp, "w"), indent=0)
    print(f, len(layout))
