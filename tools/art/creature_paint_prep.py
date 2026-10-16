"""Batch 3 of the paint-over: the 14 creature portraits.
python tools/art/creature_paint_prep.py  ->  imagegen/batch3/in/creature_<cid>.png

Reference = imagegen/batch3/in/raw_<cid>.png (1024px render from imported.render_imported, portrait_size=1024)
when present, else the clean 256px portrait render upscaled. Composited on the creature portrait background.
Paint with tools/art/vertex_paint.py --batch imagegen/batch3, then tools/art/imagegen_ingest.py imagegen/batch3."""
import os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from portrait_bg import background, PAL

IN = "imagegen/batch3/in"
CLEAN = "tools/art/raw/clean_portraits"

def main():
    os.makedirs(IN, exist_ok=True)
    for f in sorted(os.listdir("assets/creatures/portraits")):
        if not f.endswith(".png"):
            continue
        cid = f[:-4]
        raw = f"{IN}/raw_{cid}.png"
        if os.path.exists(raw):
            fg = Image.open(raw).convert("RGBA")
        else:
            fg = Image.open(f"{CLEAN}/assets_creatures_portraits_{f}").convert("RGBA").resize((1024, 1024), Image.LANCZOS)
        bg = background(fg.width, PAL["creature"], hash(cid) % 1000)
        bg.alpha_composite(fg)
        bg.convert("RGB").save(f"{IN}/creature_{cid}.png")
        print("creature", cid, "(1024 render)" if os.path.exists(raw) else "(upscaled)")

if __name__ == "__main__":
    main()
