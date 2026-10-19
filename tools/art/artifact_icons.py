"""Painted artifact icons (as the classic inventory pictures): one Gemini painting per artifact, framed like the
other icons.
python tools/art/artifact_icons.py paint [ids...]   ->  imagegen/batch27/out/artifact_<id>.png
python tools/art/artifact_icons.py ingest           ->  assets/icons/artifact_<id>.png (128x128, framed)"""
import os, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))

BATCH = "imagegen/batch27"
ARTS = {
    "sword_of_valor": "a noble longsword with a gilded cross-guard and a gleaming steel blade, held diagonally",
    "shield_of_dawn": "a kite shield of polished steel with a golden rising sun emblem and a gold rim",
    "helm_of_wisdom": "a knight's great helm of silver steel with an engraved gold brow band and a small blue gem",
    "orb_of_power": "a glowing crystal orb crackling with violet arcane light, on a small ornate gold stand",
    "boots_of_speed": "a pair of tall brown leather boots with small white feathered wings at the ankles",
    "ring_of_vitality": "a heavy gold ring set with a large glowing red ruby",
    "clover_of_fortune": "a four-leaf clover glowing with a soft golden-green light",
    "crown_of_command": "a jewelled royal gold crown with red and blue gems",
    "cape_of_courage": "a flowing deep red cape with a gold lion clasp and gold-trimmed hem",
    "amulet_of_insight": "a gold amulet on a fine chain, set with a glowing blue sapphire eye",
    "breastplate_of_ironbark": "a breastplate of dark polished wood bound with iron bands and engraved leaves",
}
PROMPT = ("Paint a single inventory icon for a fantasy strategy game: {what}, centred and filling most of the square, "
          "seen slightly from above. Hand-painted digital fantasy illustration in the style of classic late-1990s "
          "turn-based fantasy strategy games: rich saturated colours, visible painterly brushwork, crisp highlights, "
          "warm golden light from the upper left, a clear dark outline so it reads at a small size. Background: a plain "
          "dark wine-red to near-black vertical gradient like the reference icon, nothing else. Square image. No text, "
          "no border, no frame, no hands, no people.")


def paint(ids):
    import vertex_paint as vp
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    for a, what in ARTS.items():
        if ids and a not in ids:
            continue
        dst = f"{BATCH}/out/artifact_{a}.png"
        if os.path.exists(dst) and not ids:
            print("skip", a); continue
        src = f"assets/icons/artifact_{a}.png"
        if not os.path.exists(src):
            src = "assets/icons/artifact_ring_of_vitality.png"  # (the style and background of the set)
        ref = f"{BATCH}/in/artifact_{a}.png"
        Image.open(src).convert("RGB").resize((512, 512), Image.LANCZOS).save(ref)
        img = vp.paint(client, "gemini-nano-banana-2.1", ref, PROMPT.format(what=what), "1:1", "1K")
        if img:
            img.save(dst); print("done", a, flush=True)
        else:
            print("FAILED", a, flush=True)


def ingest():
    from icons2d import framed, S
    for a in ARTS:
        p = f"{BATCH}/out/artifact_{a}.png"
        if not os.path.exists(p):
            continue
        size = 128
        W = size * S
        bg = framed(size, (110, 40, 40), (35, 10, 20))
        pic = Image.open(p).convert("RGBA").resize((W - 14 * S, W - 14 * S), Image.LANCZOS)
        m = Image.new("L", pic.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, pic.width - 1, pic.height - 1], W * 0.09, fill=255)
        bg.paste(pic, (7 * S, 7 * S), m)
        d = ImageDraw.Draw(bg)  # (the frame again over the painting's edge)
        r = W * 0.12
        d.rounded_rectangle([S * 1.5, S * 1.5, W - S * 1.5, W - S * 1.5], r, outline=(214, 170, 80, 255), width=int(S * 2.5))
        d.rounded_rectangle([S * 5, S * 5, W - S * 5, W - S * 5], r * 0.8, outline=(40, 25, 10, 200), width=S)
        bg.resize((size, size), Image.LANCZOS).save(f"assets/icons/artifact_{a}.png")
        print("ingested", a)


if __name__ == "__main__":
    if sys.argv[1] == "paint":
        paint(sys.argv[2:])
    else:
        ingest()
