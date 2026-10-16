"""Extra battle poses (attack, hit, dead) for each creature, drawn by an image model from the painted idle sprite.
python tools/art/pose_paint.py prep [cids...]   ->  imagegen/batch6/in/pose__<cid>__<pose>.png + poses.json
python tools/art/vertex_paint.py --batch imagegen/batch6
python tools/art/pose_paint.py ingest           ->  assets/creatures/<cid>_<pose>.png + anchors.json entries

Most library models have no rig, so poses can't be rendered in Blender. Instead the idle sprite (figure only, no cast
shadow) is placed on a flat magenta backdrop and the model redraws the same character in a new pose. Ingest keys out
the magenta, lines the figure's feet up with the idle sprite at the same scale, adds a soft cast shadow like the
rendered ones, and writes a sprite whose anchor (feet point) is stored in assets/creatures/anchors.json."""
import os, sys, json
import numpy as np
from PIL import Image, ImageFilter

BATCH = "imagegen/batch6"
D = "assets/creatures"
KEY = np.array([255, 0, 255], np.float32)
POSES = ["attack", "hit", "dead"]
CREATURES = ["pikeman", "archer", "griffin", "swordsman", "monk", "cavalier", "angel",
             "skeleton", "zombie", "ghost", "vampire", "lich", "dread_knight", "bone_dragon"]
RATIOS = {"1:1": 1.0, "4:3": 4 / 3, "3:2": 1.5, "16:9": 16 / 9, "3:4": 0.75, "5:4": 1.25, "4:5": 0.8}
LONG = 1536

def _anchors():
    return json.load(open(f"{D}/anchors.json"))

def figure(cid):
    """Idle sprite without its cast shadow (soft alpha) as RGBA, plus its solid bbox."""
    im = Image.open(f"{D}/{cid}.png").convert("RGBA")
    a = np.asarray(im, dtype=np.float32)
    alpha = np.clip((a[..., 3] - 150) / 80, 0, 1) * 255
    fig = Image.fromarray(np.dstack([a[..., :3], alpha]).astype(np.uint8), "RGBA")
    ys, xs = np.nonzero(alpha > 200)
    return im, fig, (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)

def prep(cids):
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    pj = f"{BATCH}/in/poses.json"
    info = json.load(open(pj)) if os.path.exists(pj) else {}
    for cid in cids:
        im, fig, (x0, y0, x1, y1) = figure(cid)
        fw, fh = x1 - x0, y1 - y0
        # room for raised weapons, lunges and a body lying flat
        cx0, cx1 = x0 - fw * 0.6, x1 + fw * 0.6
        cy0, cy1 = y0 - fh * 0.3, y1 + fh * 0.08
        w, h = cx1 - cx0, cy1 - cy0
        r = min(RATIOS, key=lambda k: abs(np.log(RATIOS[k] / (w / h))))
        if w / h > RATIOS[r]:
            h2 = w / RATIOS[r]; cy0 -= (h2 - h); h = h2  # extra room goes above
        else:
            w2 = h * RATIOS[r]; cx0 -= (w2 - w) / 2; w = w2
        s = LONG / max(w, h)
        W, H = int(round(w * s)), int(round(h * s))
        canvas = Image.new("RGBA", (W, H), (255, 0, 255, 255))
        big = fig.resize((int(round(fig.width * s)), int(round(fig.height * s))), Image.LANCZOS)
        canvas.alpha_composite(big, (int(round(-cx0 * s)), int(round(-cy0 * s))))
        for p in POSES:
            name = f"pose__{cid}__{p}"
            canvas.convert("RGB").save(f"{BATCH}/in/{name}.png")
            info[name] = {"cid": cid, "pose": p, "origin": [cx0, cy0], "scale": s, "ratio": r}
    json.dump(info, open(pj, "w"), indent=1)
    print(len(info), "pose references")

def key_out(img):
    """Magenta backdrop -> alpha, with despill on the soft edge."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mag = np.clip((np.minimum(r, b) - g) / 255.0, 0, 1)  # how magenta a pixel is
    alpha = 1 - np.clip((mag - 0.18) / 0.32, 0, 1)
    # despill: remove the magenta contribution from partly keyed pixels
    k = (1 - alpha)[..., None]
    rgb = np.clip((a - k * KEY) / np.maximum(alpha[..., None], 0.05), 0, 255)
    spill = np.maximum(0, np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1])
    rgb[..., 0] -= spill * 0.5
    rgb[..., 2] -= spill * 0.5
    al = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.asarray(al)]).astype(np.uint8), "RGBA")

def drop_specks(img, keep=0.015):
    """Remove detached blobs smaller than `keep` of the figure (stray feathers, sparks the model left floating)."""
    a = np.asarray(img).copy()
    mask = a[..., 3] > 40
    h, w = mask.shape
    label = np.zeros((h, w), np.int32)
    sizes = [0]
    for y0, x0 in zip(*np.nonzero(mask)):
        if label[y0, x0]:
            continue
        n = len(sizes)
        label[y0, x0] = n
        stack, count = [(y0, x0)], 0
        while stack:
            y, x = stack.pop()
            count += 1
            for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not label[yy, xx]:
                    label[yy, xx] = n
                    stack.append((yy, xx))
        sizes.append(count)
    sizes = np.array(sizes)
    small = sizes < keep * sizes.sum()
    small[0] = False
    a[small[label] & mask, 3] = 0
    return Image.fromarray(a, "RGBA")

def feet(alpha, lying=False):
    """Feet point of a figure mask: bottom row of the solid pixels, x = centre of the lowest 15% (whole body if lying)."""
    ys, xs = np.nonzero(alpha > 128)
    bottom = ys.max()
    if lying:
        return float(np.median(xs)), float(bottom)
    cut = np.percentile(ys, 85)
    return float(xs[ys >= cut].mean()), float(bottom)

def shadow(fig_alpha, fx, fy):
    """Soft cast shadow like the Blender renders: the figure squashed onto the ground, leaning back-right."""
    h, w = fig_alpha.shape
    src = Image.fromarray(fig_alpha)
    # affine: shadow point (u, v) samples figure point (u - shear * (fy - y), fy - (fy - v) / squash)
    squash, shear = 0.32, 0.55
    coeffs = (1, shear / squash, -shear / squash * fy, 0, 1 / squash, fy - fy / squash)
    sh = src.transform((w, h), Image.AFFINE, coeffs, Image.BILINEAR).filter(ImageFilter.GaussianBlur(5))
    return np.asarray(sh, dtype=np.float32) / 255 * 0.42

def ingest():
    info = json.load(open(f"{BATCH}/in/poses.json"))
    anchors = _anchors()
    for name, d in info.items():
        src = next((f"{BATCH}/out/{name}.{e}" for e in ("png", "jpg", "webp") if os.path.exists(f"{BATCH}/out/{name}.{e}")), None)
        if not src:
            continue
        cid, pose, s = d["cid"], d["pose"], d["scale"]
        ref = Image.open(f"{BATCH}/in/{name}.png")
        cut = key_out(Image.open(src).convert("RGB").resize(ref.size, Image.LANCZOS))
        # back to sprite scale (texture pixels of the idle sprite)
        cut = cut.resize((max(1, int(round(cut.width / s))), max(1, int(round(cut.height / s)))), Image.LANCZOS)
        cut = drop_specks(cut)
        ca = np.asarray(cut)[..., 3]
        if (ca > 128).sum() < 50:
            print(f"  {name}: nothing left after keying, skipped"); continue
        im, fig, _ = figure(cid)
        # the model tends to draw new poses a little larger: match the idle figure's painted area
        f = float(np.clip(np.sqrt((np.asarray(fig)[..., 3] > 128).sum() / (ca > 128).sum()), 0.75, 1.1))
        if abs(f - 1) > 0.02:
            cut = cut.resize((max(1, int(round(cut.width * f))), max(1, int(round(cut.height * f)))), Image.LANCZOS)
            ca = np.asarray(cut)[..., 3]
        ax, ay = anchors[f"{cid}.png"]
        idle_feet = np.array([ax * im.width, ay * im.height])
        px, py = feet(ca, lying=pose == "dead")
        ys, xs = np.nonzero(ca > 20)
        x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
        fig_rgba = cut.crop((x0, y0, x1, y1))
        fx, fy = px - x0, py - y0
        # output canvas: figure plus room for the shadow (back-right) and a small margin
        pad = 12
        sh_w = int((y1 - y0) * 0.55 * 0.32) + 30
        W, H = int(fig_rgba.width + 2 * pad + sh_w), int(fig_rgba.height + 2 * pad + 10)
        out = Image.new("RGBA", (W, H))
        ox, oy = pad, pad
        fa = np.zeros((H, W), np.uint8)
        fa[oy:oy + fig_rgba.height, ox:ox + fig_rgba.width] = np.asarray(fig_rgba)[..., 3]
        sha = shadow(fa, ox + fx, oy + fy)
        out = Image.fromarray(np.dstack([np.zeros((H, W, 3), np.uint8) + np.array([12, 10, 8], np.uint8),
                                         (sha * 255).astype(np.uint8)]), "RGBA")
        out.alpha_composite(fig_rgba, (ox, oy))
        dst = f"{D}/{cid}_{pose}.png"
        out.save(dst)
        anchors[f"{cid}_{pose}.png"] = [round((ox + fx) / W, 4), round((oy + fy) / H, 4)]
        print(f"  {name}: {W}x{H} feet {anchors[f'{cid}_{pose}.png']} (idle feet at {idle_feet.round()})")
    json.dump(anchors, open(f"{D}/anchors.json", "w"), indent=0, sort_keys=True)

if __name__ == "__main__":
    if sys.argv[1] == "prep":
        prep(sys.argv[2:] or CREATURES)
    else:
        ingest()
