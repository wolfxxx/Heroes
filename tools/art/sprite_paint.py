"""Paint-over for transparent sprites (adventure-map objects, battle obstacles) and battle backgrounds.
python tools/art/sprite_paint.py prep     ->  imagegen/batch4/in/{map,battle}__<name>.png + sprites.json
python tools/art/vertex_paint.py --batch imagegen/batch4
python tools/art/sprite_paint.py ingest   ->  assets/{map,battle}/<name>.png (originals kept in tools/art/raw/pre_paint)

Sprites are cropped to their visible pixels and centred on a flat neutral background, padded to the nearest aspect
ratio the image models output. On ingest the painting is aligned back onto the reference (edge correlation), and
pasted into the sprite keeping the original alpha: solid pixels take the painted colour, soft pixels (shadow,
antialiased edges) keep the original, so shadows stay neutral on every terrain."""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from imagegen_ingest import original

BATCH = "imagegen/batch4"
BG = (148, 140, 124)  # flat neutral backdrop; the prompt tells the painter to keep it plain
RATIOS = {"1:1": 1.0, "4:3": 4 / 3, "3:2": 1.5, "16:9": 16 / 9, "21:9": 21 / 9, "3:4": 0.75, "2:3": 2 / 3, "5:4": 1.25, "4:5": 0.8}
LONG = 1536  # reference size (long side)

SPRITES = {"map": [  # name -> painted; foliage too, so the map reads as one painting
    "town_haven", "town_necropolis", "gold_mine", "ore_mine", "sawmill", "crystal_cavern", "gem_pond", "sulfur_dune",
    "alchemist_lab", "windmill", "watchtower", "shrine", "obelisk", "dwelling_neutral", "campfire", "chest", "artifact",
    "res_gold", "res_wood", "res_ore", "res_crystal", "res_gems", "res_mercury", "res_sulfur",
    "mountain_1", "mountain_2", "mountain_3", "mountain_snow_1", "mountain_snow_2", "rock_1", "rock_2", "rock_3",
    "tree_oak_1", "tree_oak_2", "tree_oak_3", "tree_oak_4", "tree_pine_1", "tree_pine_2", "tree_pine_3",
    "snow_pine_1", "snow_pine_2", "tree_dead_1", "tree_dead_2", "bush_1", "bush_2", "flowers_1", "flowers_2"],
    "battle": ["obstacle_1", "obstacle_2", "obstacle_3", "obstacle_4"],
    # batch 1c: battle units (side view) and mounted heroes
    "creatures": ["pikeman", "archer", "griffin", "swordsman", "monk", "cavalier", "angel",
                  "skeleton", "zombie", "ghost", "vampire", "lich", "dread_knight", "bone_dragon"],
    "heroes": ["battle_haven", "battle_necropolis", "map_haven", "map_necropolis"]}
BACKGROUNDS = ["grass", "dirt", "sand", "snow", "swamp"]

def ratio_for(w, h):
    return min(RATIOS, key=lambda k: abs(np.log(RATIOS[k] / (w / h))))

def prep():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    info = {}
    for d, names in SPRITES.items():
        for n in names:
            src = original(f"assets/{d}/{n}.png")  # always prepare from the unpainted sprite
            im = Image.open(src).convert("RGBA")
            a = np.asarray(im)[..., 3]
            ys, xs = np.nonzero(a > 10)
            box = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
            crop = im.crop(box)
            m = 0.12  # margin around the object
            w, h = crop.width * (1 + 2 * m), crop.height * (1 + 2 * m)
            r = ratio_for(w, h)
            cw, ch = (w, w / RATIOS[r]) if w / h > RATIOS[r] else (h * RATIOS[r], h)
            s = LONG / max(cw, ch)
            W, H = int(round(cw * s)), int(round(ch * s))
            big = crop.resize((max(1, int(round(crop.width * s))), max(1, int(round(crop.height * s)))), Image.LANCZOS)
            ox, oy = (W - big.width) // 2, (H - big.height) // 2
            canvas = Image.new("RGBA", (W, H), BG + (255,))
            canvas.alpha_composite(big, (ox, oy))
            name = f"{d}__{n}"
            canvas.convert("RGB").save(f"{BATCH}/in/{name}.png")
            info[name] = {"src": f"assets/{d}/{n}.png", "box": box, "scale": s, "offset": [ox, oy], "ratio": r}
    for t in BACKGROUNDS:
        name = f"bg__{t}"
        Image.open(original(f"assets/battle/bg_{t}.png")).convert("RGB").save(f"{BATCH}/in/{name}.png")
        info[name] = {"src": f"assets/battle/bg_{t}.png", "ratio": "16:9"}
    json.dump(info, open(f"{BATCH}/in/sprites.json", "w"), indent=1)
    print(len(info), "references in", BATCH + "/in")

def _edges(img, w):
    g = img.convert("L").resize((w, max(2, int(round(w * img.height / img.width)))), Image.BILINEAR)
    a = np.asarray(g, dtype=np.float32)
    return np.abs(np.diff(a, axis=1))[:-1] + np.abs(np.diff(a, axis=0))[:, :-1]

def align(painted, ref, W=256, M=16):
    """Scale (0.92-1.08) + shift that best maps the painting onto the reference; returns the aligned painting."""
    r = _edges(ref, W)
    best = (-2, 1.0, 0, 0)
    cache = {}
    def score(s, dx, dy):
        k = round(s, 3)
        if k not in cache:
            p = _edges(painted.resize((int(ref.width * s), int(ref.height * s))), int(W * s))
            cache[k] = np.pad(p, M)
        p = cache[k]
        y0 = M + (p.shape[0] - 2 * M - r.shape[0]) // 2 + dy
        x0 = M + (p.shape[1] - 2 * M - r.shape[1]) // 2 + dx
        if y0 < 0 or x0 < 0 or y0 + r.shape[0] > p.shape[0] or x0 + r.shape[1] > p.shape[1]:
            return -2
        return np.corrcoef(p[y0:y0 + r.shape[0], x0:x0 + r.shape[1]].ravel(), r.ravel())[0, 1]
    for s in np.arange(0.92, 1.0801, 0.02):
        for dy in range(-M, M + 1, 2):
            for dx in range(-M, M + 1, 2):
                c = score(s, dx, dy)
                if c > best[0]:
                    best = (c, s, dx, dy)
    _, s0, dx0, dy0 = best
    for s in np.arange(s0 - 0.015, s0 + 0.016, 0.005):
        for dy in range(dy0 - 2, dy0 + 3):
            for dx in range(dx0 - 2, dx0 + 3):
                c = score(s, dx, dy)
                if c > best[0]:
                    best = (c, s, dx, dy)
    c, s, dx, dy = best
    k = ref.width / W
    big = painted.resize((int(ref.width * s), int(ref.height * s)), Image.LANCZOS)
    ox = int(round(dx * k)) + (big.width - ref.width) // 2
    oy = int(round(dy * k)) + (big.height - ref.height) // 2
    return big.crop((ox, oy, ox + ref.width, oy + ref.height)), c

def ingest():
    info = json.load(open(f"{BATCH}/in/sprites.json"))
    for name, d in info.items():
        out = next((f"{BATCH}/out/{name}.{e}" for e in ("png", "jpg", "webp") if os.path.exists(f"{BATCH}/out/{name}.{e}")), None)
        if not out:
            continue
        ref = Image.open(f"{BATCH}/in/{name}.png").convert("RGB")
        painted = Image.open(out).convert("RGB").resize(ref.size, Image.LANCZOS)
        if name.startswith("bg__"):  # backgrounds are repainted freely (the grid is drawn on top): no alignment
            painted.save(d["src"])
            print(f"  {name}")
            continue
        aligned, c = align(painted, ref)
        flag = "  <-- weak match, check by eye" if c < 0.3 else ""
        orig = Image.open(original(d["src"])).convert("RGBA")
        x0, y0, x1, y1 = d["box"]
        s, (ox, oy) = d["scale"], d["offset"]
        bw, bh = x1 - x0, y1 - y0
        bigw, bigh = max(1, int(round(bw * s))), max(1, int(round(bh * s)))
        patch = aligned.crop((ox, oy, ox + bigw, oy + bigh)).resize((bw, bh), Image.LANCZOS)
        o = np.asarray(orig, dtype=np.float32)
        p = np.asarray(patch, dtype=np.float32)
        a = o[y0:y1, x0:x1, 3:4] / 255
        wgt = np.clip((a - 0.55) / 0.35, 0, 1)  # solid -> painted, soft (shadow / edge) -> original
        o[y0:y1, x0:x1, :3] = p * wgt + o[y0:y1, x0:x1, :3] * (1 - wgt)
        Image.fromarray(np.clip(o, 0, 255).astype(np.uint8), "RGBA").save(d["src"])
        print(f"  {name}: corr {c:.2f}{flag}")

if __name__ == "__main__":
    {"prep": prep, "ingest": ingest}[sys.argv[1]]()
