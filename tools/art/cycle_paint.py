"""4-frame movement cycles for battle creatures (walk / wing-flap / gallop / glide), like the map hero gallop.
python tools/art/cycle_paint.py prep [cids...]  ->  imagegen/batch8/in/cycle__<cid>.png (2x2 sheet of the idle figure)
python tools/art/vertex_paint.py --batch imagegen/batch8
python tools/art/cycle_paint.py ingest          ->  assets/creatures/<cid>_move0..3.png + creatures/anchors.json

Walkers are anchored on their lowest foot (with a synthetic cast shadow). Flyers are anchored so the body's centre
of mass sits where the idle sprite's does, which keeps the flapping figure steady; they get no cast shadow (the
battle scene draws the ground shadow)."""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks, shadow, figure, CREATURES

BATCH = "imagegen/batch8"
D = "assets/creatures"
CELL_W, CELL_H = 1376, 768
KIND = {"griffin": "fly", "angel": "fly", "vampire": "fly", "bone_dragon": "fly", "ghost": "glide",
        "cavalier": "gallop", "dread_knight": "gallop"}  # everything else walks

def kind(cid):
    from upgrade_paint import UPGRADES  # (an upgraded creature moves like its base one)
    return KIND.get(UPGRADES.get(cid, (cid,))[0], "walk")

def prep(cids):
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    pj = f"{BATCH}/in/cycles.json"
    info = json.load(open(pj)) if os.path.exists(pj) else {}
    for cid in cids:
        _, fig, box = figure(cid)
        fig = fig.crop(box)
        s = min(CELL_W * 0.5 / fig.width, CELL_H * 0.62 / fig.height)
        big = fig.resize((int(fig.width * s), int(fig.height * s)), Image.LANCZOS)
        sheet = Image.new("RGBA", (CELL_W * 2, CELL_H * 2), (255, 0, 255, 255))
        for k in range(4):
            cx, cy = (k % 2) * CELL_W, (k // 2) * CELL_H
            sheet.alpha_composite(big, (cx + (CELL_W - big.width) // 2, cy + int(CELL_H * 0.84) - big.height))
        sheet.convert("RGB").save(f"{BATCH}/in/cycle__{cid}.png")
        info[f"cycle__{cid}"] = {"cid": cid, "scale": s, "kind": kind(cid)}
    json.dump(info, open(pj, "w"), indent=1)
    print(len(info), "cycle sheets")

def ingest():
    info = json.load(open(f"{BATCH}/in/cycles.json"))
    anchors = json.load(open(f"{D}/anchors.json"))
    for name, d in info.items():
        src = f"{BATCH}/out/{name}.png"
        if not os.path.exists(src):
            continue
        cid, s, kd = d["cid"], d["scale"], d["kind"]
        im, fig, _ = figure(cid)
        fa_idle = np.asarray(fig)[..., 3] > 128
        idle_area = fa_idle.sum()
        ys0, xs0 = np.nonzero(fa_idle)
        ax, ay = anchors[f"{cid}.png"]
        idle_feet = np.array([ax * im.width, ay * im.height])
        idle_com = np.array([xs0.mean(), ys0.mean()])
        sheet = Image.open(src).convert("RGB").resize((CELL_W * 2, CELL_H * 2), Image.LANCZOS)
        for k in range(4):
            cx, cy = (k % 2) * CELL_W, (k // 2) * CELL_H
            cell = drop_specks(key_out(sheet.crop((cx + 4, cy + 4, cx + CELL_W - 4, cy + CELL_H - 4))))
            cell = cell.resize((max(1, int(cell.width / s)), max(1, int(cell.height / s))), Image.LANCZOS)
            a = np.asarray(cell)[..., 3]
            if (a > 128).sum() < 50:
                print(f"  {name} frame {k}: empty, skipped"); continue
            f = float(np.clip(np.sqrt(idle_area / (a > 128).sum()), 0.75, 1.35))
            cell = cell.resize((int(cell.width * f), int(cell.height * f)), Image.LANCZOS)
            cell = cell.crop(cell.getbbox())
            a = np.asarray(cell)[..., 3]
            ys, xs = np.nonzero(a > 128)
            pad = 10
            if kd in ("fly", "glide"):
                # centre of mass where the idle's is: anchor = COM + (idle feet - idle COM)
                com = np.array([xs.mean(), ys.mean()])
                W, H = cell.width + 2 * pad, cell.height + 2 * pad
                out = Image.new("RGBA", (W, H))
                out.alpha_composite(cell, (pad, pad))
                anc = (com + pad + (idle_feet - idle_com))
            else:
                fx, fy = float(xs[ys >= np.percentile(ys, 85)].mean()), float(ys.max())
                sh_w = int(cell.height * 0.2) + 24
                W, H = cell.width + 2 * pad + sh_w, cell.height + 2 * pad
                fa = np.zeros((H, W), np.uint8)
                fa[pad:pad + cell.height, pad:pad + cell.width] = a
                sha = shadow(fa, pad + fx, pad + fy)
                out = Image.fromarray(np.dstack([np.full((H, W, 3), (12, 10, 8), np.uint8), (sha * 255).astype(np.uint8)]), "RGBA")
                out.alpha_composite(cell, (pad, pad))
                anc = np.array([pad + fx, pad + fy])
            out.save(f"{D}/{cid}_move{k}.png")
            anchors[f"{cid}_move{k}.png"] = [round(float(anc[0]) / W, 4), round(float(anc[1]) / H, 4)]
        print("  cycle", cid, kd)
    json.dump(anchors, open(f"{D}/anchors.json", "w"), indent=0, sort_keys=True)

if __name__ == "__main__":
    if sys.argv[1] == "prep":
        prep(sys.argv[2:] or CREATURES)
    else:
        ingest()
