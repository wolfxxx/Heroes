"""Paint over the reference renders with Gemini image models on Vertex AI (instead of doing it by hand in a chat app).
python tools/art/vertex_paint.py [names...] [--model M] [--batch DIR] [--force]

Reads <batch>/in/<name>.png, sends it with the prompt from PROMPTS.md, writes <batch>/out/<name>.png.
Existing outputs are skipped unless --force. Needs Application Default Credentials for the Vertex project.
Then run tools/art/imagegen_ingest.py to bring the results into the game."""
import os, sys, io, glob, argparse, time
from PIL import Image
from google import genai
from google.genai import types

def _project():
    """GOOGLE_CLOUD_PROJECT, else the id in imagegen/vertex_project.txt (local, not in git)."""
    p = os.environ.get("GOOGLE_CLOUD_PROJECT")
    if not p and os.path.exists("imagegen/vertex_project.txt"):
        p = open("imagegen/vertex_project.txt").read().strip()
    if not p:
        sys.exit("set GOOGLE_CLOUD_PROJECT or write your project id to imagegen/vertex_project.txt")
    return p

PROJECT = _project()
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "global")

STYLE = ("Hand-painted digital fantasy illustration in the style of classic late-1990s turn-based fantasy strategy "
         "games: rich saturated colours, visible painterly brushwork, warm golden light from the upper left, crisp readable shapes.")

PORTRAIT = ("Repaint this image as a hero portrait for a fantasy strategy game. " + STYLE + "\n"
            "Keep the same character: same armour/clothes, colours, helmet or hood, weapon, pose and camera angle, and keep the "
            "head in the same place in the frame. Add fine painted detail (engraved metal, cloth folds, a characterful face where "
            "it is visible) and a soft painted background in the same colours as the original background.\n"
            "Square image. No text, no border, no frame, no signature.")

CREATURE = ("Repaint this image as a creature portrait for a fantasy strategy game (the unit portrait shown when "
            "recruiting). " + STYLE + "\n"
            "Keep the same creature: same species, anatomy, armour/clothes, colours, weapon, pose and camera angle, and keep "
            "the head in the same place in the frame. Add fine painted detail (fur, feathers, scales, bone, engraved metal, "
            "cloth folds, a characterful face) and a soft painted background in the same warm brown and amber colours as the "
            "original background.\nSquare image. No text, no border, no frame, no signature.")

# per-creature fixes for weak spots in the library models
CREATURE_NOTES = {
    "zombie": "Make it a medieval fantasy zombie: dress it in torn, rotting peasant rags and a ragged tunic (no modern "
              "clothes), with grey-green decaying skin.",
}

TOWN_BG = ("Repaint this as the background landscape of a fantasy town screen in a strategy game. " + STYLE + "\n"
           "Keep exactly the same composition: horizon, hills, mountains, trees, paths and the empty town square in the same "
           "places and sizes. Do NOT add any buildings. Extend the sky naturally into the plain band at the top and the ground "
           "into the plain band at the bottom. Landscape 3:2. No text, no border.")

TOWN = ("Repaint this fantasy town as a richly hand-painted town screen for a strategy game. " + STYLE + "\n"
        "VERY IMPORTANT: keep every building exactly where it is, with the same size, outline and roof shape. Do not add, "
        "remove, move or resize any building, tower, wall, stall or tree. Only improve the painting: detailed stone "
        "masonry, timber, roof tiles, banners, windows with warm light, foliage, sky. Extend the sky into the plain band at "
        "the top and the ground into the plain band at the bottom. Landscape 3:2. No text, no border.")

FLAVOUR = {
    ("bg", "necropolis"): " Gloomy cursed land at dusk: purple-green sky, dead trees, pale moonlight, mist.",
    ("town", "haven"): " A bright noble kingdom of white stone, blue roofs and gold trim on a sunny day.",
    ("town", "necropolis"): " A dark necromancer citadel of black stone with green ghost-light in the windows, bones and "
                            "gravestones, under a purple-green dusk sky with pale moonlight.",
}

GROUP_STYLE = ("\nThe second image is the same town already painted: match its painting style, colours, lighting, materials "
               "and level of detail exactly, so these buildings fit into it seamlessly. Paint every visible part of each "
               "building, including the plain grey stone walls.\nUse the second image ONLY as a style guide. Do NOT copy "
               "any building from it: paint only the buildings that are in the first image, and keep every empty part of "
               "the town square and landscape empty.")

def prompt_for(name):
    if name.startswith("portrait_"):
        return PORTRAIT, "1:1"
    if name.startswith("creature_"):
        cid = name[len("creature_"):]
        return CREATURE + ("\n" + CREATURE_NOTES[cid] if cid in CREATURE_NOTES else ""), "1:1"
    if name.startswith("group_"):  # batch 2: non-overlapping building groups, styled after the painted batch-1 town
        fac = name.split("_")[1]
        return TOWN + FLAVOUR.get(("town", fac), "") + GROUP_STYLE, "3:2"
    _, fac, var = name.split("_", 2)
    if var == "bg":
        return TOWN_BG + FLAVOUR.get(("bg", fac), ""), "3:2"
    return TOWN + FLAVOUR.get(("town", fac), ""), "3:2"

def style_ref(name):
    """Group images borrow the painted batch-1 town (variant B shows the most buildings) as a style reference."""
    if not name.startswith("group_"):
        return None
    p = f"imagegen/batch1/out/town_{name.split('_')[1]}_B.png"
    return Image.open(p).convert("RGB") if os.path.exists(p) else None

def paint(client, model, src, prompt, aspect, size, extra=None):
    ref = Image.open(src).convert("RGB")
    contents = [ref] + ([extra] if extra else []) + [prompt]
    for attempt in range(3):
        try:
            r = client.models.generate_content(
                model=model, contents=contents,
                config=types.GenerateContentConfig(
                    response_modalities=["IMAGE"],
                    image_config=types.ImageConfig(aspect_ratio=aspect, image_size=size)))
            for part in (r.candidates[0].content.parts if r.candidates and r.candidates[0].content else []):
                if part.inline_data:
                    return Image.open(io.BytesIO(part.inline_data.data))
            print("    no image returned:", r.candidates[0].finish_reason if r.candidates else r.prompt_feedback)
        except Exception as e:
            print(f"    error ({type(e).__name__}): {str(e)[:200]}")
        time.sleep(5 * (attempt + 1))
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--model", default="gemini-nano-banana-2.1")
    ap.add_argument("--batch", default="imagegen/batch1")
    ap.add_argument("--size", default="2K")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--note", default="", help="extra instruction appended to the prompt")
    a = ap.parse_args()
    client = genai.Client(vertexai=True, project=PROJECT, location=LOCATION)
    names = a.names or sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(f"{a.batch}/in/*.png")
                              if not os.path.basename(p).startswith("raw_"))
    os.makedirs(f"{a.batch}/out", exist_ok=True)
    for n in names:
        dst = f"{a.batch}/out/{n}.png"
        if os.path.exists(dst) and not a.force:
            print("skip", n); continue
        prompt, aspect = prompt_for(n)
        prompt += ("\n" + a.note) if a.note else ""
        t = time.time()
        img = paint(client, a.model, f"{a.batch}/in/{n}.png", prompt, aspect, a.size, style_ref(n))
        if img:
            img.save(dst)
            print(f"done {n} {img.size} {time.time() - t:.0f}s")
        else:
            print("FAILED", n)

if __name__ == "__main__":
    main()
