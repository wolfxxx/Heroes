"""Small adventure-map ground details (stumps, logs, mushrooms, reeds, cacti...) painted as sprite sheets.
python tools/art/decor_paint.py prep     ->  imagegen/batch12/in/decor__<sheet>.png + style ref
python tools/art/decor_paint.py paint    ->  imagegen/batch12/out/decor__<sheet>.png (Vertex image model)
python tools/art/decor_paint.py ingest   ->  assets/map/decor_<name>.png + anchors.json entries

Each sheet is a 4x3 grid on flat magenta. The model paints one object per cell, matching a crop of the current map
(second image) for style and viewing angle. Ingest keys out the magenta, cuts each cell's object, scales it to its
map size and adds a soft cast shadow leaning back-right like the rendered map sprites."""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks, shadow

BATCH = "imagegen/batch12"
D = "assets/map"
COLS, ROWS = 4, 3
W, H = 2048, 1536
# sheet -> [(name, what to paint, width in texture px (drawn at half size on the map), upright?)]
SHEETS = {
    "green": [
        ("stump", "a cut tree stump with spreading roots and a little moss", 118, True),
        ("log", "a fallen mossy log lying diagonally, with a broken end", 170, True),
        ("toadstools", "a little cluster of red-capped white-spotted toadstools among a few grass blades", 84, False),
        ("tuft", "a clump of tall wild grass with a few seed heads", 92, False),
        ("boulders", "three small grey boulders with moss, grouped together", 130, True),
        ("wildflowers", "a loose clump of blue and white wildflowers on their own stems with leaves", 96, False),
        ("fern", "a lush green fern clump", 104, False),
        ("twigs", "a scatter of dead branches and twigs", 112, False),
        ("pillar", "a broken, weathered stone column stump with ivy, an ancient ruin", 104, True),
        ("bones", "a bleached animal skull with a few scattered bones", 92, False),
        ("thorns", "a dry brown thorn bush", 112, True),
        ("menhir", "a small mossy standing stone, slightly leaning", 74, True),
    ],
    "wild": [
        ("snow_rock", "a grey boulder capped with snow", 128, True),
        ("ice", "a few jagged pale-blue ice crystals poking up", 96, True),
        ("snow_stump", "a tree stump capped with snow", 112, True),
        ("frost_shrub", "a frozen dead shrub with frost on its twigs", 104, True),
        ("cactus", "a small branching desert cactus", 84, True),
        ("horn_skull", "a sun-bleached horned cattle skull", 96, False),
        ("dry_grass", "a clump of dry straw-yellow desert grass", 92, False),
        ("sandstone", "a cluster of weathered orange sandstone rocks", 128, True),
        ("reeds", "a clump of cattails and reeds", 96, True),
        ("swamp_caps", "a cluster of pale greenish swamp mushrooms on a twisted root", 88, False),
        ("mossy_log", "a rotten log covered in thick green moss", 160, True),
        ("swamp_shrub", "a twisted dark swamp shrub with hanging grey moss", 112, True),
    ],
}

PROMPT = ("This is a blank sprite sheet for a fantasy strategy game's adventure map: a flat magenta (#FF00FF) "
          "background divided into a 4 x 3 grid of equal cells (4 columns, 3 rows). Paint exactly one small object in "
          "the centre of each cell, in reading order (left to right, top row first):\n{items}\n"
          "Every object is seen from the same high three-quarter top-down view as the map in the second image, and "
          "painted in the same hand-painted style: rich colours, soft light from the upper left, crisp dark outline. "
          "Draw only the object itself: no ground under it, no grass patch, no cast shadow, no frame or grid lines, no "
          "text or labels. Keep each object well inside its cell with plenty of magenta around it, and keep the "
          "background pure flat magenta everywhere else.")

def prep():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    for sheet in SHEETS:
        Image.new("RGB", (W, H), (255, 0, 255)).save(f"{BATCH}/in/decor__{sheet}.png")
    print("blank sheets written; style ref:", f"{BATCH}/in/style.png", "exists" if os.path.exists(f"{BATCH}/in/style.png") else "MISSING")

def paint(sheets):
    import vertex_paint as vp
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    style = Image.open(f"{BATCH}/in/style.png").convert("RGB")
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    for sheet in sheets:
        items = "\n".join(f"{i + 1}. {d}" for i, (_, d, _, _) in enumerate(SHEETS[sheet]))
        img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/decor__{sheet}.png", PROMPT.format(items=items), "4:3", "2K", style)
        if img:
            img.save(f"{BATCH}/out/decor__{sheet}.png")
            print("done", sheet, img.size)
        else:
            print("FAILED", sheet)

def ingest(sheets):
    anchors = json.load(open(f"{D}/anchors.json"))
    for sheet in sheets:
        src = f"{BATCH}/out/decor__{sheet}.png"
        if not os.path.exists(src):
            continue
        cut = key_out(Image.open(src).convert("RGB").resize((W, H), Image.LANCZOS))
        cw, ch = W // COLS, H // ROWS
        for k, (name, _, width, upright) in enumerate(SHEETS[sheet]):
            cx, cy = (k % COLS) * cw, (k // COLS) * ch
            cell = drop_specks(cut.crop((cx, cy, cx + cw, cy + ch)), keep=0.04)
            a = np.asarray(cell)[..., 3]
            ys, xs = np.nonzero(a > 24)
            if len(xs) < 200:
                print(f"  {name}: empty cell, skipped"); continue
            obj = cell.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            s = width / obj.width
            obj = obj.resize((width, max(1, int(round(obj.height * s)))), Image.LANCZOS)
            oa = np.asarray(obj)[..., 3]
            # ground point: bottom centre of the solid pixels (a little up for flat things lying on the ground)
            ys, xs = np.nonzero(oa > 128)
            fx = float(xs[ys >= np.percentile(ys, 80)].mean())
            fy = float(ys.max()) - (0.0 if upright else 0.25 * (ys.max() - ys.min()))
            pad = 10
            sh_w = int(obj.height * 0.55 * 0.32) + 20 if upright else 14
            OW, OH = obj.width + 2 * pad + sh_w, obj.height + 2 * pad
            fa = np.zeros((OH, OW), np.uint8)
            fa[pad:pad + obj.height, pad:pad + obj.width] = oa
            sha = shadow(fa, pad + fx, pad + fy) if upright else _drop(fa)
            out = Image.fromarray(np.dstack([np.zeros((OH, OW, 3), np.uint8) + np.array([12, 10, 8], np.uint8),
                                             (sha * 255).astype(np.uint8)]), "RGBA")
            out.alpha_composite(obj, (pad, pad))
            out.save(f"{D}/decor_{name}.png")
            anchors[f"decor_{name}.png"] = [round((pad + fx) / OW, 4), round((pad + fy) / OH, 4)]
            print(f"  decor_{name}: {OW}x{OH}")
    json.dump(anchors, open(f"{D}/anchors.json", "w"), indent=0, sort_keys=True)

def _drop(fa):
    """Low objects: a short soft offset shadow instead of a long cast one."""
    from PIL import ImageFilter
    sh = Image.fromarray(fa).transform(fa.shape[::-1], Image.AFFINE, (1, 0, -6, 0, 1, 3)).filter(ImageFilter.GaussianBlur(3))
    return np.asarray(sh, dtype=np.float32) / 255 * 0.35

if __name__ == "__main__":
    cmd, names = sys.argv[1], sys.argv[2:] or list(SHEETS)
    {"prep": lambda: prep(), "paint": lambda: paint(names), "ingest": lambda: ingest(names)}[cmd]()
