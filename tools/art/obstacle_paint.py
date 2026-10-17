"""Battlefield obstacles, varied per terrain (the field used to show copies of one stump), painted as two 4x2 sheets
on magenta in the style and view of the old obstacle sprites.
python tools/art/obstacle_paint.py paint    ->  imagegen/batch22/out/<sheet>.png
python tools/art/obstacle_paint.py ingest   ->  assets/battle/obstacle_<name>.png (which terrain uses which:
                                                 battle.gd OBSTACLES)"""
import os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks, shadow

BATCH = "imagegen/batch22"
COLS, ROWS = 4, 2
W, H = 2048, 1024
# sheet -> [(name, what to paint, width on the 1920 battlefield)]
SHEETS = {
    "temperate": [
        ("boulders", "a heap of three large grey boulders with patches of moss", 150),
        ("dead_tree", "a gnarled dead tree, leafless, broken top, twisted roots", 150),
        ("log", "a thick fallen tree trunk lying sideways with a jagged broken end and moss", 170),
        ("crater", "a shallow scorched crater in the earth ringed with broken rocks and clods", 160),
        ("thorns", "a dense dark thorn bush with brambles", 130),
        ("pillar", "a broken, weathered ancient stone pillar with ivy, fallen chunks at its base", 110),
        ("rock_spire", "a single tall jagged grey rock spire", 110),
        ("skull_pile", "a small heap of old skulls and bones with a rusty helmet", 120),
    ],
    "harsh": [
        ("snow_boulders", "a heap of grey boulders capped with snow", 150),
        ("ice", "a cluster of tall jagged pale-blue ice crystals", 120),
        ("frozen_tree", "a dead tree covered in frost and snow", 140),
        ("sandstone", "a weathered orange sandstone rock formation", 150),
        ("cactus", "a large branching desert cactus with a few small rocks", 110),
        ("bones", "the bleached ribcage and skull of a huge beast half sunk in sand", 170),
        ("swamp_tree", "a twisted dark swamp tree with hanging grey moss and exposed roots", 140),
        ("rotten_log", "a rotten mossy log with pale swamp mushrooms growing on it", 160),
    ],
}
PROMPT = ("This is a blank sprite sheet for a fantasy strategy game's battlefield: a flat magenta (#FF00FF) background "
          "divided into a 4 x 2 grid of equal cells (4 columns, 2 rows). Paint exactly one battlefield obstacle in the "
          "centre of each cell, in reading order (left to right, top row first):\n{items}\n"
          "Every object is seen from the same slightly elevated side view as the obstacles in the second image, and "
          "painted in the same hand-painted style: rich colours, soft light from the upper left, crisp dark outline. "
          "Draw only the object itself: no ground patch, no grass under it, no cast shadow, no frame or grid lines, no "
          "text. Keep each object well inside its cell with magenta around it, and keep the background pure flat "
          "magenta everywhere else.")


def paint(sheets):
    import vertex_paint as vp
    from google import genai
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    style = Image.new("RGB", (4 * 260, 220), (96, 128, 64))
    for i in range(4):
        ob = Image.open(f"assets/battle/obstacle_{i + 1}.png").convert("RGBA")
        ob.thumbnail((240, 200))
        style.paste(ob, (i * 260 + 10, 10), ob)
    style.save(f"{BATCH}/in/style.png")
    Image.new("RGB", (W, H), (255, 0, 255)).save(f"{BATCH}/in/blank.png")
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    for sheet in sheets:
        items = "\n".join(f"{i + 1}. {d}" for i, (_, d, _) in enumerate(SHEETS[sheet]))
        img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/blank.png", PROMPT.format(items=items), "16:9", "2K", style)
        if img:
            img.save(f"{BATCH}/out/{sheet}.png")
            print("done", sheet, img.size)
        else:
            print("FAILED", sheet)


def ingest(sheets):
    for sheet in sheets:
        src = f"{BATCH}/out/{sheet}.png"
        if not os.path.exists(src):
            continue
        cut = key_out(Image.open(src).convert("RGB"))
        cw, ch = cut.width / COLS, cut.height / ROWS
        for k, (name, _, width) in enumerate(SHEETS[sheet]):
            cx, cy = (k % COLS) * cw, (k // COLS) * ch
            cell = drop_specks(cut.crop((int(cx), int(cy), int(cx + cw), int(cy + ch))), keep=0.04)
            a = np.asarray(cell)[..., 3]
            ys, xs = np.nonzero(a > 24)
            if len(xs) < 200:
                print(f"  {name}: empty cell"); continue
            obj = cell.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            # stored at twice the battlefield size (as the old obstacles), feet at the bottom centre
            s = 2 * width / obj.width
            obj = obj.resize((round(obj.width * s), round(obj.height * s)), Image.LANCZOS)
            oa = np.asarray(obj)[..., 3]
            sh_w = int(obj.height * 0.55 * 0.32) + 24
            pad = 12
            OW, OH = obj.width + 2 * pad + sh_w, obj.height + 2 * pad
            fa = np.zeros((OH, OW), np.uint8)
            fa[pad:pad + obj.height, pad:pad + obj.width] = oa
            ys, xs = np.nonzero(oa > 128)
            fx = float(xs[ys >= np.percentile(ys, 80)].mean())
            sha = shadow(fa, pad + fx, pad + float(ys.max()))
            out = Image.fromarray(np.dstack([np.zeros((OH, OW, 3), np.uint8) + np.array([12, 10, 8], np.uint8),
                                             (sha * 255).astype(np.uint8)]), "RGBA")
            out.alpha_composite(obj, (pad, pad))
            # canvas centred on the object's feet, so the sprite can be placed by its bottom centre
            cxp = pad + fx
            left, right = cxp, OW - cxp
            half = int(max(left, right)) + 1
            full = Image.new("RGBA", (2 * half, OH))
            full.alpha_composite(out, (int(half - cxp), 0))
            full = full.crop((0, 0, full.width, int(pad + ys.max()) + 6))
            full.save(f"assets/battle/obstacle_{name}.png")
            print(f"  battle/obstacle_{name}.png {full.size}")


if __name__ == "__main__":
    cmd, names = sys.argv[1], sys.argv[2:] or list(SHEETS)
    {"paint": lambda: paint(names), "ingest": lambda: ingest(names)}[cmd]()
