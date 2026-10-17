"""Hero screen paper-doll: a faint etched hero figure on dark slate; the artifact sockets are drawn over it in-game.
python tools/art/paperdoll_paint.py guide    ->  imagegen/batch17/in/paperdoll.png (a grey stand-in figure on slate)
python tools/art/paperdoll_paint.py paint    ->  imagegen/batch17/out/paperdoll.png (Vertex image model, over the guide)
python tools/art/paperdoll_paint.py ingest   ->  assets/ui/paperdoll.png (600x800)"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
BATCH = "imagegen/batch17"
W, H = 768, 1024
PROMPT = ("Paint over this image the equipment panel of a hero screen in a fantasy strategy game: a recessed niche of "
          "dark blue-grey slate with soft candle light from above. On it, a faint engraved etching in pale gold line work "
          "of an armored knight standing straight in front view, arms held a little away from the body, legs slightly "
          "apart, the whole figure from the crested helmet to the boots, centred, exactly where the grey figure is in "
          "this image. The figure must be subtle and ghostly, like a gilded engraving on stone with light hatching, "
          "low contrast against the slate, not a full-colour painting. Darker vignette at the edges. No text, no "
          "letters, no squares, no slots, no frames, no gems, no symbols.")


def guide():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    rng = np.random.default_rng(3)
    a = np.full((H, W, 3), (38, 42, 50), np.float32)
    a += rng.normal(0, 6, (H, W, 1))
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    g = (92, 92, 96)
    cx = W // 2
    d.ellipse([cx - 52, 110, cx + 52, 230], fill=g)                    # helmet
    d.polygon([(cx - 130, 260), (cx + 130, 260), (cx + 100, 560), (cx - 100, 560)], fill=g)  # torso
    d.polygon([(cx - 130, 260), (cx - 190, 300), (cx - 210, 560), (cx - 160, 570), (cx - 140, 330)], fill=g)  # arms
    d.polygon([(cx + 130, 260), (cx + 190, 300), (cx + 210, 560), (cx + 160, 570), (cx + 140, 330)], fill=g)
    d.polygon([(cx - 100, 560), (cx - 10, 560), (cx - 30, 900), (cx - 110, 900)], fill=g)    # legs
    d.polygon([(cx + 100, 560), (cx + 10, 560), (cx + 30, 900), (cx + 110, 900)], fill=g)
    d.rectangle([cx - 130, 900, cx - 20, 940], fill=g)
    d.rectangle([cx + 20, 900, cx + 130, 940], fill=g)
    im.filter(ImageFilter.GaussianBlur(3)).save(f"{BATCH}/in/paperdoll.png")
    print("guide written")


def paint():
    import vertex_paint as vp
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/paperdoll.png", PROMPT, "3:4", "1K")
    if img:
        img.save(f"{BATCH}/out/paperdoll.png")
        print("done", img.size)


def ingest():
    im = Image.open(f"{BATCH}/out/paperdoll.png").convert("RGB").resize((600, 800), Image.LANCZOS)
    im.save("assets/ui/paperdoll.png")
    print("  ui/paperdoll.png")


if __name__ == "__main__":
    {"guide": guide, "paint": paint, "ingest": ingest}[sys.argv[1]]()
