"""Battle spell effects: painted 4x4 flipbooks (16 frames) on black, played with additive blending.
python tools/art/vfx_paint.py prep      ->  imagegen/batch13/in/fx__<name>.png (black canvas)
python tools/art/vfx_paint.py paint     ->  imagegen/batch13/out/fx__<name>.png (Vertex image model)
python tools/art/vfx_paint.py ingest    ->  assets/battle/fx_<name>.png (1024x1024, 4x4 frames of 256)

Black is the background because the game draws these with additive blending: black adds nothing, so no keying is
needed and glows stay soft. Ingest fades each cell's border to black so neighbouring frames never bleed in."""
import os, sys
import numpy as np
from PIL import Image

BATCH = "imagegen/batch13"
D = "assets/battle"
SIZE = 2048
FX = {
    "fire": "a fireball explosion: a burst of orange and yellow flame that swells into a roiling fireball with "
            "flying embers, then breaks up into dark red smoke and sparks",
    "frost": "a frost explosion: pale blue ice shards and a ring of frost crystals bursting outward with a white "
             "flash, then drifting snowflakes and cold mist",
    "spark": "a lightning strike impact: a blinding white-blue flash with crackling electric arcs and sparks "
             "spraying outward, then fading electric wisps",
    "arcane": "a magic missile impact: a burst of violet and cyan arcane energy with a starry flash and little "
              "glowing runes spinning outward, then fading motes",
    "holy": "a holy blessing: a soft column of golden-white light rising with sparkles and a gentle halo ring "
            "opening at the bottom, then sparkles drifting upward and fading",
    "dark": "a dark curse: swirling purple-black smoke with sickly green wisps and a few ghostly skull-like shapes "
            "coiling outward, then dissolving into faint smoke",
}
PROMPT = ("This is a blank 4 x 4 sprite sheet for a fantasy strategy game's battle spell effect. Paint 16 animation "
          "frames of {what}, one frame per cell, in reading order (left to right, top row first): frame 1 is the very "
          "first spark, the effect grows to its brightest around frames 4-7, then dissipates, and frame 16 is almost "
          "gone. Every frame is centred in its cell, the same size scale throughout, and never touches or crosses the "
          "cell borders. Hand-painted fantasy game effect, luminous and saturated, glowing core. The background must "
          "stay pure black (#000000) everywhere: no ground, no characters, no grid lines, no text or numbers.")

def prep():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    for n in FX:
        Image.new("RGB", (SIZE, SIZE), (0, 0, 0)).save(f"{BATCH}/in/fx__{n}.png")
    print(len(FX), "blank sheets")

def paint(names):
    import vertex_paint as vp
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    for n in names:
        img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/fx__{n}.png", PROMPT.format(what=FX[n]), "1:1", "2K")
        if img:
            img.save(f"{BATCH}/out/fx__{n}.png")
            print("done", n, img.size)
        else:
            print("FAILED", n)

def ingest(names):
    cell = 256
    ramp = np.minimum(np.arange(cell), np.arange(cell)[::-1]).astype(np.float32)
    edge = np.clip((ramp - 4) / 14, 0, 1)
    mask = np.outer(edge, edge)[..., None]
    for n in names:
        src = f"{BATCH}/out/fx__{n}.png"
        if not os.path.exists(src):
            continue
        a = np.asarray(Image.open(src).convert("RGB").resize((cell * 4, cell * 4), Image.LANCZOS), np.float32)
        a = np.clip(a - 6, 0, 255) * (255 / 249)  # the model's "black" is rarely 0: pull it down so it adds nothing
        for y in range(4):
            for x in range(4):
                a[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] *= mask
        Image.fromarray(a.astype(np.uint8)).save(f"{D}/fx_{n}.png")
        print("  fx_%s" % n)

if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(__file__))
    cmd, names = sys.argv[1], sys.argv[2:] or list(FX)
    {"prep": lambda: prep(), "paint": lambda: paint(names), "ingest": lambda: ingest(names)}[cmd]()
