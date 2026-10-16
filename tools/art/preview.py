"""Composite sprites onto a terrain tile for review: python tools/art/preview.py out.png bg_terrain a.png b.png ..."""
import sys
from PIL import Image
out, bg = sys.argv[1], sys.argv[2]
files = sys.argv[3:]
cell = 300
sheet = Image.new("RGBA", (cell * max(1, len(files)), cell), (0, 0, 0, 255))
tile = Image.open(f"assets/terrain/{bg}.png").convert("RGBA").resize((cell, cell))
for i, f in enumerate(files):
    sheet.paste(tile, (i * cell, 0))
    im = Image.open(f).convert("RGBA")
    im.thumbnail((cell - 10, cell - 10))
    sheet.alpha_composite(im, (i * cell + (cell - im.width) // 2, cell - im.height - 5))
sheet.save(out)
