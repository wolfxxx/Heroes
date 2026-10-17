"""Haven guardhouse (dwelling_1): the town render cut it off at the left edge of the screen, behind the archers'
tower, so only a sliver showed. It is repainted whole, in the style of the tavern, and stands on the open lawn at
the front right of the town instead.
python tools/art/town_edge_paint.py paint   ->  imagegen/batch19/out/guardhouse.png (on magenta)
python tools/art/town_edge_paint.py ingest  ->  assets/town/haven_dwelling_1.png + its rect in layout_haven.json
                                                (the clipped sprite is kept in tools/art/raw/town/)"""
import os, sys, json, shutil
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks, shadow

BATCH = "imagegen/batch19"
DST = "assets/town/haven_dwelling_1.png"
OLD = "tools/art/raw/town/haven_dwelling_1_clipped.png"
LAYOUT = "assets/town/layout_haven.json"
HEIGHT = 262            # building height on the 1920x810 town scene (the tavern is ~300)
FOOT = (1738, 780)      # bottom centre on the front-right lawn, clear of the plaza and the lamp posts
PROMPT = ("The first image shows one building from a painted fantasy town. Paint a DIFFERENT building for the same "
          "town, in exactly the same art style, palette, line work, lighting from the upper left and the same "
          "elevated three-quarter view: a small guardhouse of the pikemen, a sturdy ground floor of pale cut stone "
          "with a heavy wooden door facing the viewer, a half-timbered upper floor with two small lit windows, a "
          "steep blue slate roof with gold trim like the reference, a squat round corner watch turret with a blue "
          "conical roof, a wooden rack of long pikes leaning by the door and a small blue and gold pennant. The whole "
          "building fits inside the frame with a margin all round. Flat pure magenta (#FF00FF) background, no ground, "
          "no grass, no cobbles, no cast shadow, no text.")


def paint():
    import vertex_paint as vp
    from google import genai
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    ref = Image.open("assets/town/haven_tavern.png").convert("RGBA")
    a = np.asarray(ref).copy()
    a[..., 3] = np.where(a[..., 3] > 200, 255, 0)  # the building, not its soft shadow
    ref = Image.fromarray(a)
    ref = ref.crop(ref.getbbox())
    pad = 50
    bg = Image.new("RGBA", (ref.width + 2 * pad, ref.height + 2 * pad), (255, 0, 255, 255))
    bg.alpha_composite(ref, (pad, pad))
    bg.convert("RGB").save(f"{BATCH}/in/tavern_ref.png")
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/tavern_ref.png", PROMPT, "1:1", "1K")
    if img:
        img.save(f"{BATCH}/out/guardhouse.png")
        print("done", img.size)


def ingest():
    os.makedirs(os.path.dirname(OLD), exist_ok=True)
    if not os.path.exists(OLD):
        shutil.copy(DST, OLD)
    b = drop_specks(key_out(Image.open(f"{BATCH}/out/guardhouse.png")))
    b = b.crop(b.getbbox())
    sc = HEIGHT / b.height
    b = b.resize((round(b.width * sc), HEIGHT), Image.LANCZOS)
    # room for the cast shadow, which leans back to the right
    padr, padt = int(HEIGHT * 0.45), 4
    W, H = b.width + padr, b.height + padt
    fa = np.zeros((H, W), np.uint8)
    fa[padt:, :b.width] = np.asarray(b)[..., 3]
    sh = shadow(fa, b.width * 0.5, H - 1)
    out = np.zeros((H, W, 4), np.float32)
    out[..., 3] = sh
    canvas = Image.fromarray((out * [0, 0, 0, 255]).clip(0, 255).astype(np.uint8), "RGBA")
    canvas.alpha_composite(b, (0, padt))
    canvas.save(DST)
    lay = json.load(open(LAYOUT))
    lay["dwelling_1"] = [int(FOOT[0] - b.width / 2), int(FOOT[1] - H), W, H]
    json.dump(lay, open(LAYOUT, "w"), indent=0)
    print("  town/haven_dwelling_1.png", canvas.size, "at", lay["dwelling_1"])


if __name__ == "__main__":
    {"paint": paint, "ingest": ingest}[sys.argv[1]]()
