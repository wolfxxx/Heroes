"""Adventure panel button icons (kingdom overview, hero, sleep, move, spellbook, next hero, end turn, system),
painted as one 4x2 sheet on magenta in the style of the stat icons.
python tools/art/button_icons_paint.py paint   ->  imagegen/batch20/out/buttons.png
python tools/art/button_icons_paint.py ingest  ->  assets/ui/btn_<name>.png (128 px, transparent)"""
import os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks

BATCH = "imagegen/batch20"
COLS, ROWS = 4, 2
W, H = 2048, 1024
SIZE = 128
ICONS = [
    ("kingdom", "a small castle keep with a golden crown floating above it"),
    ("hero", "a knight's steel helmet with a red plume, seen from the side"),
    ("sleep", "a pale golden crescent moon with three small stars"),
    ("move", "a galloping horse's hoof with a horseshoe and three motion streaks behind it"),
    ("spellbook", "an open leather spellbook with glowing blue runes rising from its pages"),
    ("next_hero", "a knight's steel helmet with a golden curved arrow sweeping around it to the right"),
    ("end_turn", "an ornate brass hourglass with golden sand"),
    ("system", "a rolled parchment scroll with a red wax seal and a quill"),
]
PROMPT = ("This is a blank icon sheet for a fantasy strategy game's interface: a flat magenta (#FF00FF) background "
          "divided into a 4 x 2 grid of equal square cells (4 columns, 2 rows). Paint exactly one icon in the centre of "
          "each cell, in reading order (left to right, top row first):\n{items}\n"
          "Paint them in the same style as the icons in the second image: hand-painted fantasy game icons with rich "
          "colours, strong light from the upper left, a crisp dark outline, a bold readable silhouette at small size. "
          "Draw only the object: no background disc, no frame, no button, no text or letters. Keep each icon well "
          "inside its cell with magenta around it, and keep the background pure flat magenta everywhere else.")


def paint():
    import vertex_paint as vp
    from google import genai
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    Image.new("RGB", (W, H), (255, 0, 255)).save(f"{BATCH}/in/buttons.png")
    style = Image.new("RGB", (4 * 140, 140), (40, 32, 24))
    for i, st in enumerate(["attack", "defense", "power", "knowledge"]):
        ic = Image.open(f"assets/icons/stat_{st}.png").convert("RGBA").resize((128, 128), Image.LANCZOS)
        style.paste(ic, (i * 140 + 6, 6), ic)
    style.save(f"{BATCH}/in/style.png")
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    items = "\n".join(f"{i + 1}. {d}" for i, (_, d) in enumerate(ICONS))
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/buttons.png", PROMPT.format(items=items), "16:9", "2K", style)
    if img:
        img.save(f"{BATCH}/out/buttons.png")
        print("done", img.size)


def ingest():
    src = Image.open(f"{BATCH}/out/buttons.png").convert("RGB")
    cut = key_out(src)
    cw, ch = cut.width / COLS, cut.height / ROWS
    for k, (name, _) in enumerate(ICONS):
        cx, cy = (k % COLS) * cw, (k // COLS) * ch
        cell = drop_specks(cut.crop((int(cx), int(cy), int(cx + cw), int(cy + ch))), keep=0.04)
        a = np.asarray(cell)[..., 3]
        ys, xs = np.nonzero(a > 24)
        if len(xs) < 200:
            print(f"  {name}: empty cell"); continue
        obj = cell.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        s = (SIZE - 8) / max(obj.width, obj.height)
        obj = obj.resize((max(1, round(obj.width * s)), max(1, round(obj.height * s))), Image.LANCZOS)
        out = Image.new("RGBA", (SIZE, SIZE))
        out.alpha_composite(obj, ((SIZE - obj.width) // 2, (SIZE - obj.height) // 2))
        out.save(f"assets/ui/btn_{name}.png")
        print(f"  ui/btn_{name}.png")


if __name__ == "__main__":
    {"paint": paint, "ingest": ingest}[sys.argv[1]]()
