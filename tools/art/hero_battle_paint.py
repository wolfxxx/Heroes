"""Necropolis battle hero: a necromancer lord on a skeletal horse (it was a recoloured copy of the Haven knight).
python tools/art/hero_battle_paint.py paint   ->  imagegen/batch18/out/battle_necropolis.png (over the old rider on magenta)
python tools/art/hero_battle_paint.py ingest  ->  assets/heroes/battle_necropolis.png (same canvas and feet line as before;
                                                  the old sprite is kept in tools/art/raw/heroes/)"""
import os, sys, shutil
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks

BATCH = "imagegen/batch18"
SRC = "assets/heroes/battle_necropolis.png"
OLD = "tools/art/raw/heroes/battle_necropolis_knight.png"
PROMPT = ("Repaint this rider as the lord of an undead army in a fantasy strategy game, same side view facing right, "
          "same size, same position and same pose: a gaunt necromancer lord in a tattered black and deep purple hooded "
          "cloak over dark bone-trimmed armour, a pale skull-like face under the hood, holding upright a tall black "
          "staff topped with a horned skull and a faint green glow, riding a skeletal undead war horse with bare "
          "ribs and leg bones, ragged black barding, and small glowing green eyes. Hand-painted fantasy game art with "
          "crisp edges and rich detail, lit from the upper left. Keep the background flat pure magenta (#FF00FF), "
          "no ground, no shadow, no text.")


def _figure():
    im = Image.open(OLD if os.path.exists(OLD) else SRC).convert("RGBA")
    return im


def paint():
    import vertex_paint as vp
    from google import genai
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    os.makedirs(os.path.dirname(OLD), exist_ok=True)
    if not os.path.exists(OLD):
        shutil.copy(SRC, OLD)
    im = _figure()
    a = np.asarray(im).copy()
    a[..., 3] = np.where(a[..., 3] > 200, 255, 0)  # the rider only, not its cast shadow
    fig = Image.fromarray(a)
    x0, y0, x1, y1 = fig.getbbox()
    pad = 60
    crop = fig.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad))
    bg = Image.new("RGBA", crop.size, (255, 0, 255, 255))
    bg.alpha_composite(crop)
    bg.convert("RGB").save(f"{BATCH}/in/battle_necropolis.png")
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    w, h = crop.size
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/battle_necropolis.png", PROMPT,
                   "3:4" if w / h < 0.85 else ("1:1" if w / h < 1.15 else "4:3"), "1K")
    if img:
        img.save(f"{BATCH}/out/battle_necropolis.png")
        print("done", img.size, "from", crop.size)


def ingest():
    old = _figure()
    a = np.asarray(old)
    ys, xs = np.nonzero(a[..., 3] > 200)
    ox0, oy0, ox1, oy1 = xs.min(), ys.min(), xs.max(), ys.max()
    new = drop_specks(key_out(Image.open(f"{BATCH}/out/battle_necropolis.png")))
    new = new.crop(new.getbbox())
    # same figure height and feet line as the old rider, centred on it
    sc = (oy1 - oy0) / new.height
    new = new.resize((max(1, round(new.width * sc)), oy1 - oy0), Image.LANCZOS)
    out = Image.new("RGBA", old.size, (0, 0, 0, 0))
    cx = (ox0 + ox1) // 2
    out.alpha_composite(new, (max(0, cx - new.width // 2), int(oy0)))
    out.save(SRC)
    print("  heroes/battle_necropolis.png", new.size)


if __name__ == "__main__":
    {"paint": paint, "ingest": ingest}[sys.argv[1]]()
