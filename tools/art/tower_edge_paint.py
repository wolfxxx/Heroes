"""Haven archers' tower (dwelling_2): its roof eave and platform were cut straight at the left screen edge in the
town render. The image model completes the cut-off left part on a padded canvas; only the new pixels left of the
old edge are kept (the rest of the sprite is untouched), and the sprite moves right so the whole roof shows.
python tools/art/tower_edge_paint.py paint   ->  imagegen/batch21/out/tower.png
python tools/art/tower_edge_paint.py ingest  ->  assets/town/haven_dwelling_2.png + its rect in layout_haven.json
                                                (the clipped sprite is kept in tools/art/raw/town/)"""
import os, sys, json, shutil
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out

BATCH = "imagegen/batch21"
DST = "assets/town/haven_dwelling_2.png"
OLD = "tools/art/raw/town/haven_dwelling_2_clipped.png"
LAYOUT = "assets/town/layout_haven.json"
PAD = 72          # new room on the left (sprite px)
CUT, FADE = 150, 14   # sprite rows taken from the repaint (roof and platform), then cross-faded into the legs
SHIFT = 48        # how far the sprite moves right on screen so the completed eave is in view
PROMPT = ("This is a sprite of a wooden archers' watchtower from a painted fantasy town, on a flat magenta background. "
          "Its blue slate pyramid roof and the wooden platform under it are cut off by a straight vertical line at the "
          "left. Complete the missing left part: the roof's lower left eave corner with its slates and wooden trim, "
          "and the left end of the platform beam, exactly matching the existing painting, perspective and lighting. "
          "Do not change anything else: every existing pixel stays the same, same size and same position. Keep the "
          "background flat pure magenta (#FF00FF), no ground, no shadow, no text.")


def _src():
    return Image.open(OLD if os.path.exists(OLD) else DST).convert("RGBA")


def paint():
    import vertex_paint as vp
    from google import genai
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    os.makedirs(os.path.dirname(OLD), exist_ok=True)
    if not os.path.exists(OLD):
        shutil.copy(DST, OLD)
    im = _src()
    a = np.asarray(im).copy()
    a[..., 3] = np.where(a[..., 3] > 160, 255, 0)
    im = Image.fromarray(a)
    # the top part only (roof and platform), square, with the room on the left
    top = im.crop((0, 0, im.width, 260))
    canvas = Image.new("RGBA", (PAD + top.width + 32, 260 + 64), (255, 0, 255, 255))
    canvas.alpha_composite(top, (PAD, 32))
    canvas.convert("RGB").save(f"{BATCH}/in/tower.png")
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/tower.png", PROMPT, "4:3", "1K")
    if img:
        img.save(f"{BATCH}/out/tower.png")
        print("done", img.size, "from", canvas.size)


def ingest():
    old = _src()
    src = Image.open(f"{BATCH}/in/tower.png").convert("RGB")
    out = key_out(Image.open(f"{BATCH}/out/tower.png").convert("RGB"))
    # the model answers at its own size and aspect: map it back onto the input canvas by the tower's apex, the
    # bottom of its legs and its right eave tip (a uniform scale and an offset)
    sa = np.asarray(src).astype(int)
    smask = ~((sa[..., 0] > 200) & (sa[..., 1] < 80) & (sa[..., 2] > 200))
    omask = np.asarray(out)[..., 3] > 128
    def feats(m):
        ys, xs = np.nonzero(m)
        return ys.min(), ys.max(), xs.max()
    st, sb, sr = feats(smask)
    ot, ob, orr = feats(omask)
    k = (ob - ot) / (sb - st)
    ox, oy = orr - sr * k, ot - st * k
    out = out.transform(src.size, Image.AFFINE, (k, 0, ox, 0, k, oy), Image.BICUBIC)
    o = np.asarray(out)
    # how well the model kept the existing pixels where they overlap (just right of the old edge)
    s = np.asarray(src).astype(np.float32)
    band = (slice(32, 32 + 200), slice(PAD, PAD + 60))
    oa = o[band][..., 3] > 128
    diff = np.abs(o[band][..., :3].astype(np.float32) - s[band])[oa].mean() if oa.any() else 999
    print("  seam colour difference:", round(float(diff), 1))
    # the repainted roof and platform replace the old ones whole (a patch only at the old edge leaves a step); the
    # legs below stay the original, cross-faded over a few rows
    W, Hh = old.width + PAD, old.height
    new = Image.new("RGBA", (W, Hh))
    new.alpha_composite(old, (PAD, 0))
    top = np.asarray(out.crop((0, 32, W, 32 + CUT + FADE))).astype(np.float32)
    top[..., 3] = (top[..., 3] > 128) * 255.0
    base = np.asarray(new).astype(np.float32)
    w = np.ones((CUT + FADE, 1, 1), np.float32)
    w[CUT:, 0, 0] = np.linspace(1, 0, FADE)
    region = base[:CUT + FADE]
    # where the repaint is empty keep the old pixels only below the cut (above it the repaint decides the shape)
    blend = top * w + region * (1 - w)
    blend[:CUT][top[:CUT, :, 3] == 0] = 0
    base[:CUT + FADE] = blend
    new = Image.fromarray(base.clip(0, 255).astype(np.uint8), "RGBA")
    bb = new.getbbox()
    new = new.crop((bb[0], 0, W, Hh))
    new.save(DST)
    lay = json.load(open(LAYOUT))
    x, y, w, h = lay["dwelling_2"]
    nx = x + SHIFT - (PAD - bb[0])
    lay["dwelling_2"] = [nx, y, new.width, h]
    json.dump(lay, open(LAYOUT, "w"), indent=0)
    print("  town/haven_dwelling_2.png", new.size, "at", lay["dwelling_2"])


if __name__ == "__main__":
    {"paint": paint, "ingest": ingest}[sys.argv[1]]()
