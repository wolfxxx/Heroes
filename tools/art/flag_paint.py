"""Adventure-map ownership banner: a painted white banner on a pole, 4 frames waving, tinted per player in game.
python tools/art/flag_paint.py paint    ->  imagegen/batch16/out/flag.png (Vertex image model, 2x2 sheet on magenta)
python tools/art/flag_paint.py ingest   ->  assets/map/flag_pole.png + assets/map/flag_cloth.png (4 frames side by side)

Ingest keys out the magenta, lines the frames up on the pole's foot, and splits each frame into the pole (wood and
gold, drawn as is) and the cloth (white, kept as grey shading so the game can multiply it by the player colour)."""
import os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks

BATCH = "imagegen/batch16"
FH = 112  # frame height in the game texture
PROMPT = ("This is a blank 2 x 2 sprite sheet on flat magenta (#FF00FF) for a fantasy strategy game's adventure map. In "
          "each of the four cells paint the same small ownership banner: a short dark wooden pole standing upright with "
          "a small gold spear-tip finial, and a swallow-tailed pennant of plain pure white cloth attached at the top of "
          "the pole and flying to the right. The four cells are four frames of the cloth waving in the wind, in reading "
          "order, so they loop smoothly; the pole stays exactly the same in every frame. Hand-painted, crisp dark "
          "outline, soft light from the upper left, the cloth plain white with soft grey folds and no pattern or emblem. "
          "Each banner centred in its cell with plenty of magenta around it. No ground, no shadow, no text, no grid lines.")


def paint():
    import vertex_paint as vp
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    Image.new("RGB", (2048, 2048), (255, 0, 255)).save(f"{BATCH}/in/flag.png")
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/flag.png", PROMPT, "1:1", "2K")
    if img:
        img.save(f"{BATCH}/out/flag.png")
        print("done", img.size)


def ingest():
    sheet = key_out(Image.open(f"{BATCH}/out/flag.png").convert("RGB").resize((2048, 2048), Image.LANCZOS))
    frames = []
    for i in range(4):
        cell = drop_specks(sheet.crop(((i % 2) * 1024, (i // 2) * 1024, (i % 2 + 1) * 1024, (i // 2 + 1) * 1024)), 0.05)
        a = np.asarray(cell).astype(np.float32)
        al = a[..., 3] / 255
        rgb = a[..., :3] / 255
        lum = rgb.mean(2)
        sat = rgb.max(2) - rgb.min(2)
        # the pole: the column with the most dark opaque pixels
        dark = (al > 0.5) & (lum < 0.35)
        px = int(np.argmax(dark.sum(0)))
        ys = np.nonzero(al.max(1) > 0.5)[0]
        frames.append((cell, px, ys[0], ys[-1], lum, sat, al))
    top = min(f[2] for f in frames)
    bot = max(f[3] for f in frames)
    h = bot - top + 1
    s = FH / h
    left = max(f[1] for f in frames) - min(np.nonzero(f[6].max(0) > 0.5)[0][0] for f in frames)
    right = max(np.nonzero(f[6].max(0) > 0.5)[0][-1] - f[1] for f in frames)
    fw = int((left + right + 8) * s)
    pole_sheet = Image.new("RGBA", (fw * 4, FH))
    cloth_sheet = Image.new("RGBA", (fw * 4, FH))
    for i, (cell, px, _, _, lum, sat, al) in enumerate(frames):
        # cloth = bright and unsaturated; everything else (wood, gold, outline) stays in the pole layer
        m = np.clip((lum - 0.42) / 0.2, 0, 1) * np.clip((0.22 - sat) / 0.12, 0, 1)
        m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize(cell.size)) / 255.0
        c = np.asarray(cell).astype(np.float32)
        cloth = np.dstack([np.repeat((lum * 255)[..., None], 3, 2), c[..., 3] * m]).astype(np.uint8)
        pole = np.dstack([c[..., :3], c[..., 3] * (1 - m)]).astype(np.uint8)
        box = (px - left - 4, top, px + right + 4, bot + 1)
        for arr, dst in ((pole, pole_sheet), (cloth, cloth_sheet)):
            im = Image.fromarray(arr, "RGBA").crop(box).resize((fw, FH), Image.LANCZOS)
            dst.alpha_composite(im, (i * fw, 0))
    pole_sheet.save("assets/map/flag_pole.png")
    cloth_sheet.save("assets/map/flag_cloth.png")
    print("  flag frames %dx%d, pole at x=%d" % (fw, FH, int((left + 4) * s)))


if __name__ == "__main__":
    {"paint": paint, "ingest": ingest}[sys.argv[1]]()
