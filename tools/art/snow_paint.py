"""Adventure-map snow ground: a painted, crisp snow texture in place of the soft graded photo (which read as cloud).
python tools/art/snow_paint.py paint    ->  imagegen/batch15/out/snow.png (Vertex image model, over the old texture)
python tools/art/snow_paint.py ingest   ->  assets/terrain/snow.png (512x512, made seamless)

Seamless: the painting is blended with a copy of itself rolled by half its size, using a weight that is 1 in the
middle and 0 at the borders, so the borders come from the rolled copy's (continuous) middle."""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
BATCH = "imagegen/batch15"
PROMPT = ("Paint over this image a seamless top-down ground texture of snow-covered land for a fantasy strategy game's "
          "adventure map, seen from straight above: bright white packed snow with crisp pale-blue shadows in shallow "
          "wind-blown ripples and small drifts, fine sparkling crystals, and here and there a tiny dark pebble or a few "
          "dry grass blades poking through. Even light from the upper left, the same density of detail everywhere, no "
          "large features, no objects, no trees, no footprints, no horizon. Hand-painted, crisp and detailed, high "
          "contrast between the bright white and the cool blue shadows.")


def paint():
    import vertex_paint as vp
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    Image.open("assets/terrain/snow.png").convert("RGB").resize((1024, 1024), Image.LANCZOS).save(f"{BATCH}/in/snow.png")
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/snow.png", PROMPT, "1:1", "1K")
    if img:
        img.save(f"{BATCH}/out/snow.png")
        print("done", img.size)


def seamless(a):
    n = a.shape[0]
    t = np.minimum(np.arange(n), np.arange(n)[::-1]) / (n / 2)  # 0 at the borders, 1 in the middle
    w1 = np.clip((t - 0.15) / 0.5, 0, 1)
    w = np.minimum.outer(w1, w1)[..., None]
    rolled = np.roll(a, (n // 2, n // 2), (0, 1))
    return a * w + rolled * (1 - w)


def ingest():
    a = np.asarray(Image.open(f"{BATCH}/out/snow.png").convert("RGB").resize((1024, 1024), Image.LANCZOS), np.float32)
    s = seamless(a)
    Image.fromarray(np.clip(s, 0, 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS) \
        .filter(ImageFilter.UnsharpMask(1.2, 60, 2)).save("assets/terrain/snow.png")
    print("  terrain/snow.png")


if __name__ == "__main__":
    {"paint": paint, "ingest": ingest}[sys.argv[1]]()
