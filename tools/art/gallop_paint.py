"""4-frame gallop cycle for the mounted hero on the adventure map.
python tools/art/gallop_paint.py prep    ->  imagegen/batch7/in/gallop__<faction>.png  (2x2 sheet of the idle sprite)
python tools/art/vertex_paint.py --batch imagegen/batch7
python tools/art/gallop_paint.py ingest  ->  assets/heroes/map_<faction>_run<0-3>.png + heroes/anchors.json

One image holds all four frames, so the model keeps the rider identical between them. Each cell is keyed, scaled to
the idle figure, given the same synthetic cast shadow as the battle poses, and anchored on a stable point (the figure's
horizontal centre and lowest hoof) so the cycle doesn't jitter."""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks, shadow

BATCH = "imagegen/batch7"
D = "assets/heroes"
FACTIONS = ["haven", "necropolis"]
CELL_W, CELL_H = 1376, 768  # 16:9 sheet of 2x2 cells, each about the sprite's own aspect

def figure(fac):
    im = Image.open(f"{D}/map_{fac}.png").convert("RGBA")
    a = np.asarray(im, dtype=np.float32)
    alpha = np.clip((a[..., 3] - 150) / 80, 0, 1) * 255
    fig = Image.fromarray(np.dstack([a[..., :3], alpha]).astype(np.uint8), "RGBA")
    return fig.crop(fig.getbbox())

def prep():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    info = {}
    for fac in FACTIONS:
        fig = figure(fac)
        s = min(CELL_W * 0.62 / fig.width, CELL_H * 0.72 / fig.height)
        big = fig.resize((int(fig.width * s), int(fig.height * s)), Image.LANCZOS)
        sheet = Image.new("RGBA", (CELL_W * 2, CELL_H * 2), (255, 0, 255, 255))
        for k in range(4):
            cx, cy = (k % 2) * CELL_W, (k // 2) * CELL_H
            sheet.alpha_composite(big, (cx + (CELL_W - big.width) // 2, cy + int(CELL_H * 0.86) - big.height))
        sheet.convert("RGB").save(f"{BATCH}/in/gallop__{fac}.png")
        info[f"gallop__{fac}"] = {"faction": fac, "scale": s}
    json.dump(info, open(f"{BATCH}/in/gallop.json", "w"), indent=1)
    print("prepared", list(info))

def ingest():
    info = json.load(open(f"{BATCH}/in/gallop.json"))
    anchors = json.load(open(f"{D}/anchors.json"))
    for name, d in info.items():
        src = f"{BATCH}/out/{name}.png"
        if not os.path.exists(src):
            continue
        fac, s = d["faction"], d["scale"]
        sheet = Image.open(src).convert("RGB").resize((CELL_W * 2, CELL_H * 2), Image.LANCZOS)
        idle_area = (np.asarray(figure(fac))[..., 3] > 128).sum()
        for k in range(4):
            cx, cy = (k % 2) * CELL_W, (k // 2) * CELL_H
            cell = drop_specks(key_out(sheet.crop((cx + 4, cy + 4, cx + CELL_W - 4, cy + CELL_H - 4))))
            cell = cell.resize((max(1, int(cell.width / s)), max(1, int(cell.height / s))), Image.LANCZOS)
            a = np.asarray(cell)[..., 3]
            f = float(np.clip(np.sqrt(idle_area / max(1, (a > 128).sum())), 0.8, 1.45))
            cell = cell.resize((int(cell.width * f), int(cell.height * f)), Image.LANCZOS)
            cell = cell.crop(cell.getbbox())
            a = np.asarray(cell)[..., 3]
            ys, xs = np.nonzero(a > 128)
            fx, fy = float(xs.mean()), float(ys.max())
            pad, sh_w = 10, int(cell.height * 0.2) + 24
            W, H = cell.width + 2 * pad + sh_w, cell.height + 2 * pad
            fa = np.zeros((H, W), np.uint8)
            fa[pad:pad + cell.height, pad:pad + cell.width] = a
            sha = shadow(fa, pad + fx, pad + fy)
            out = Image.fromarray(np.dstack([np.full((H, W, 3), (12, 10, 8), np.uint8), (sha * 255).astype(np.uint8)]), "RGBA")
            out.alpha_composite(cell, (pad, pad))
            out.save(f"{D}/map_{fac}_run{k}.png")
            anchors[f"map_{fac}_run{k}.png"] = [round((pad + fx) / W, 4), round((pad + fy) / H, 4)]
        print("  gallop", fac)
    json.dump(anchors, open(f"{D}/anchors.json", "w"), indent=0, sort_keys=True)

if __name__ == "__main__":
    {"prep": prep, "ingest": ingest}[sys.argv[1]]()
