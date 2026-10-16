"""Bring painted-over images (ChatGPT / Gemini) back into the game.
python tools/art/imagegen_ingest.py [batch dir, default imagegen/batch1]

Reads <batch>/out/<name>.(png|jpg|jpeg|webp) for the names in <batch>/in (see PROMPTS.md):
  portrait_<hero>  -> assets/heroes/portraits/<hero>.png (256px; listed in painted.json so portrait_bg skips it)
  town_<f>_bg      -> assets/town/<f>_bg.png
  town_<f>_A/B/C   -> the building sprites of that variant, cut out with the original sprite's alpha
Each town result is first auto-aligned to its reference (generators shift/scale slightly). Originals are kept in
tools/art/raw/pre_paint/ and always used as the source of masks, so re-running is safe."""
import os, sys, json, shutil, glob
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from imagegen_prep import PAD_W, PAD_H, VIEW_H, TOP, VARIANTS, OTHERS

BACKUP = "tools/art/raw/pre_paint"
EXTRACT = {"A": ["village_hall", "fort", "mage_guild_1"] + OTHERS, "B": ["town_hall", "citadel", "mage_guild_2"], "C": ["city_hall"]}

def find_out(batch, name):
    for ext in ("png", "jpg", "jpeg", "webp", "PNG", "JPG"):
        p = f"{batch}/out/{name}.{ext}"
        if os.path.exists(p):
            return p
    return None

def original(path):
    """Clean pre-paint copy of an asset (made on first ingest)."""
    b = os.path.join(BACKUP, path.replace("/", "_"))
    if not os.path.exists(b):
        os.makedirs(BACKUP, exist_ok=True)
        shutil.copy2(path, b)
    return b

def _gray(img, w):
    g = img.convert("L").resize((w, int(round(w * img.height / img.width))), Image.BILINEAR)
    a = np.asarray(g, dtype=np.float32)
    gx = np.abs(np.diff(a, axis=1))[:-1]; gy = np.abs(np.diff(a, axis=0))[:, :-1]
    return gx + gy  # edges: robust to the repaint changing colours

def align(painted, ref):
    """Find scale + offset mapping painted onto ref (both 1920x1280) by edge correlation; return aligned image."""
    W = 384
    r = _gray(ref, W)
    rb = r[int(r.shape[0] * TOP / PAD_H):int(r.shape[0] * (TOP + VIEW_H) / PAD_H)]
    band_y = int(r.shape[0] * TOP / PAD_H)
    M = 30  # search margin (in 384px-wide units, ~150 px full size)

    cache = {}

    def score(s, dx, dy):
        key = round(s, 3)
        if key not in cache:
            p0 = _gray(painted.resize((int(PAD_W * s), int(PAD_H * s))), int(W * s))
            cache[key] = (np.pad(p0, M), p0.shape)
        p, (ph, pw) = cache[key]
        # ref pixel (i, j) <-> scaled painting pixel centred on it, shifted by (dx, dy); +M for the padding
        y0 = M + (ph - r.shape[0]) // 2 + band_y + dy
        x0 = M + (pw - r.shape[1]) // 2 + dx
        if y0 < 0 or x0 < 0 or y0 + rb.shape[0] > p.shape[0] or x0 + rb.shape[1] > p.shape[1]:
            return -1
        return np.corrcoef(p[y0:y0 + rb.shape[0], x0:x0 + rb.shape[1]].ravel(), rb.ravel())[0, 1]

    best = (-1, 1.0, 0, 0)
    for s in np.arange(0.92, 1.0801, 0.02):  # coarse
        for dy in range(-M, M + 1, 3):
            for dx in range(-M, M + 1, 3):
                c = score(s, dx, dy)
                if c > best[0]:
                    best = (c, s, dx, dy)
    _, s0, dx0, dy0 = best
    for s in np.arange(s0 - 0.02, s0 + 0.0201, 0.005):  # fine
        for dy in range(dy0 - 3, dy0 + 4):
            for dx in range(dx0 - 3, dx0 + 4):
                c = score(s, dx, dy)
                if c > best[0]:
                    best = (c, s, dx, dy)
    c, s, dx, dy = best
    k = PAD_W / W
    big = painted.resize((int(PAD_W * s), int(PAD_H * s)), Image.LANCZOS)
    ox = int(round(dx * k)) + (big.width - PAD_W) // 2
    oy = int(round(dy * k)) + (big.height - PAD_H) // 2
    print(f"    aligned: corr {c:.2f} scale {s:.2f} offset {ox},{oy}")
    if c < 0.25:
        print("    WARNING: weak match - the generator probably moved things; check this one by eye")
    return big.crop((ox, oy, ox + PAD_W, oy + PAD_H))

def ingest_portrait(batch, hid, src):
    im = Image.open(src).convert("RGB")
    s = min(im.size)
    im = im.crop(((im.width - s) // 2, (im.height - s) // 2, (im.width - s) // 2 + s, (im.height - s) // 2 + s))
    dst = f"assets/heroes/portraits/{hid}.png"
    original(dst)
    im.resize((256, 256), Image.LANCZOS).save(dst)
    pj = "assets/heroes/portraits/painted.json"
    done = json.load(open(pj)) if os.path.exists(pj) else []
    if hid not in done:
        json.dump(sorted(done + [hid]), open(pj, "w"))
    print("  portrait", hid)

def ingest_creature(batch, cid, src):
    im = Image.open(src).convert("RGB")
    s = min(im.size)
    im = im.crop(((im.width - s) // 2, (im.height - s) // 2, (im.width - s) // 2 + s, (im.height - s) // 2 + s))
    dst = f"assets/creatures/portraits/{cid}.png"
    original(dst)
    im.resize((256, 256), Image.LANCZOS).save(dst)
    pj = "assets/creatures/portraits/painted.json"
    done = json.load(open(pj)) if os.path.exists(pj) else []
    if cid not in done:
        json.dump(sorted(done + [cid]), open(pj, "w"))
    print("  creature", cid)

def ingest_town(batch, fac, var, src):
    ref = Image.open(f"{batch}/in/town_{fac}_{var}.png").convert("RGB")
    painted = Image.open(src).convert("RGB").resize((PAD_W, PAD_H), Image.LANCZOS)
    view = align(painted, ref).crop((0, TOP, PAD_W, TOP + VIEW_H))
    if var == "bg":
        dst = f"assets/town/{fac}_bg.png"
        original(dst)
        view.save(dst)
        print("  town bg", fac)
        return
    layout = json.load(open(f"assets/town/layout_{fac}.json"))
    shown = sorted([i for i in VARIANTS[var] if i in layout], key=lambda i: layout[i][1] + layout[i][3])
    pv = np.asarray(view, dtype=np.float32)
    for sid in EXTRACT[var]:
        if sid not in layout:
            continue
        x, y, w, h = layout[sid]
        dst = f"assets/town/{fac}_{sid}.png"
        orig = np.asarray(Image.open(original(dst)).convert("RGBA").resize((w, h)), dtype=np.float32)
        # parts of this building hidden behind nearer buildings in the painting keep their original pixels
        hidden = np.zeros((h, w), np.float32)
        for other in shown[shown.index(sid) + 1:]:
            ox, oy, ow, oh = layout[other]
            oa = np.asarray(Image.open(original(f"assets/town/{fac}_{other}.png")).convert("RGBA").resize((ow, oh)), dtype=np.float32)[..., 3] / 255
            canvas = np.zeros((VIEW_H, PAD_W), np.float32)
            canvas[oy:oy + oh, ox:ox + ow] = oa
            hidden = np.maximum(hidden, canvas[y:y + h, x:x + w])
        hidden = hidden[..., None]
        rgb = pv[y:y + h, x:x + w] * (1 - hidden) + orig[..., :3] * hidden
        out = np.dstack([rgb, orig[..., 3]])
        Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA").save(dst)
    print("  town", fac, var, "->", ", ".join(EXTRACT[var]))

def ingest_group(batch, name, src):
    """Batch 2: a group of non-overlapping buildings; every building is cut out whole."""
    fac = name.split("_")[1]
    ids = json.load(open(f"{batch}/in/groups.json"))[name]
    ref = Image.open(f"{batch}/in/{name}.png").convert("RGB")
    painted = Image.open(src).convert("RGB").resize((PAD_W, PAD_H), Image.LANCZOS)
    pv = np.asarray(align(painted, ref).crop((0, TOP, PAD_W, TOP + VIEW_H)), dtype=np.float32)
    layout = json.load(open(f"assets/town/layout_{fac}.json"))
    for sid in ids:
        x, y, w, h = layout[sid]
        dst = f"assets/town/{fac}_{sid}.png"
        alpha = np.asarray(Image.open(original(dst)).convert("RGBA").resize((w, h)), dtype=np.float32)[..., 3]
        rgb = np.zeros((h, w, 3), np.float32)
        vh, vw = min(h, VIEW_H - y), min(w, PAD_W - x)
        rgb[:vh, :vw] = pv[y:y + vh, x:x + vw]
        Image.fromarray(np.clip(np.dstack([rgb, alpha]), 0, 255).astype(np.uint8), "RGBA").save(dst)
    print("  group", name, "->", ", ".join(ids))

def main():
    batch = sys.argv[1] if len(sys.argv) > 1 else "imagegen/batch1"
    names = sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(f"{batch}/in/*.png") if not os.path.basename(p).startswith("raw_"))
    missing = []
    for n in names:
        src = find_out(batch, n)
        if not src:
            missing.append(n); continue
        if n.startswith("portrait_"):
            ingest_portrait(batch, n[len("portrait_"):], src)
        elif n.startswith("creature_"):
            ingest_creature(batch, n[len("creature_"):], src)
        elif n.startswith("group_"):
            ingest_group(batch, n, src)
        elif n.startswith("town_"):
            _, fac, var = n.split("_", 2)
            ingest_town(batch, fac, var, src)
    if missing:
        print("not painted yet:", ", ".join(missing))

if __name__ == "__main__":
    main()
