"""Paint over the reference renders with Gemini image models on Vertex AI (instead of doing it by hand in a chat app).
python tools/art/vertex_paint.py [names...] [--model M] [--batch DIR] [--force]

Reads <batch>/in/<name>.png, sends it with the prompt from PROMPTS.md, writes <batch>/out/<name>.png.
Existing outputs are skipped unless --force. Needs Application Default Credentials for the Vertex project.
Then run tools/art/imagegen_ingest.py to bring the results into the game."""
import os, sys, io, glob, argparse, time, json
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
    "dread_knight": "A sinister undead death knight: keep the armour and horse barding blackened dark steel with a cold "
                    "violet sheen, as dark as in the original, with faint purple-green glints. Not bronze or gold.",
}

SPRITE = ("Repaint this object as a hand-painted {what} for a fantasy strategy game, seen from the same high "
          "three-quarter angle. " + STYLE + "\n"
          "VERY IMPORTANT: keep exactly the same object with the same outline, silhouette, proportions, size and position "
          "in the frame and the same camera angle. Do not add, remove or move any part. Only improve the painting: "
          "detailed materials (stone, timber, roof tiles, bark, leaves, rock, metal, cloth), crisp highlights, rich colour.\n"
          "Keep the background a perfectly plain, flat grey-beige colour exactly like the original: no ground, grass, "
          "cast shadows, scenery, frame or text.")

SPRITE_NOTES = {
    "town_haven": "A noble castle of white stone with blue roofs and gold trim.",
    "town_necropolis": "A dark necromancer citadel of black stone with green ghost-light in the windows.",
    "res_gold": "A pile of gold coins and ingots.", "res_wood": "A stack of cut logs.", "res_ore": "A heap of iron ore.",
    "res_crystal": "Glowing red crystals.", "res_gems": "Colourful cut gemstones.", "res_mercury": "A flask of mercury.",
    "res_sulfur": "A heap of yellow sulfur.", "artifact": "A treasure artifact on a small pedestal.",
}

UNIT = ("Repaint this figure as a hand-painted {what} for a fantasy strategy game, in exactly the same view and pose. "
        + STYLE + "\n"
        "VERY IMPORTANT: keep exactly the same character with the same outline, silhouette, pose, proportions, weapon, "
        "size and position in the frame. Do not add, remove or move any part, and do not change its colours much. Only "
        "improve the painting: detailed armour, cloth folds, fur, feathers, bone, a characterful face, crisp highlights.\n"
        "Keep the background a perfectly plain, flat grey-beige colour exactly like the original: no ground, grass, "
        "cast shadows, scenery, frame or text.")

HERO_NOTES = {
    "haven": "A noble knight in polished steel plate on an armoured warhorse.",
    "necropolis": "A sinister undead death knight in blackened steel with a cold violet sheen on a dark armoured horse; "
                  "keep it as dark as in the original, not bronze or gold.",
}

BATTLE_BG = ("Repaint this as the battlefield background of a fantasy strategy game; armies and the hex grid are drawn "
             "on top of it later. " + STYLE + "\n"
             "Keep the same camera, the horizon at the same height and the same kind of terrain and sky. Make it a rich, "
             "detailed painting: {terrain}. Everything below the upper fifth of the image is the battlefield, across the FULL "
             "width from the left edge to the right edge: keep it open, fairly flat and evenly lit, with only small, low "
             "painted detail (grass tufts, pebbles, soil patches). No trees, bushes, rocks or tall plants anywhere in it, "
             "not even at the left and right sides, because the armies stand there. Trees, hills and scenery only in the "
             "distance along the horizon.\n"
             "16:9. No creatures, no people, no text, no border.")

MENU_BG = ("Repaint this as the title-screen backdrop of a fantasy strategy game. " + STYLE + "\n"
           "A majestic castle of white stone with blue slate roofs, gold trim and fluttering banners on a hill, at golden "
           "dusk: dramatic glowing sky with warm clouds, snowy peaks behind, rolling green hills, a winding road leading "
           "up to the gate, small torches lit along the walls. Keep the same composition and camera: castle centred in "
           "the upper middle, open meadow in the foreground. The game title is drawn over the top quarter and a menu "
           "panel over the centre, so keep the upper sky calm and the centre free of fine clutter. A rich, detailed, "
           "atmospheric painting with depth and light. 16:9. No text, no logo, no border, no people.")

BG_TERRAIN = {
    "grass": "lush green meadow under a bright blue sky with white clouds, distant snowy peaks and oak trees",
    "dirt": "dry brown earth and rough trodden ground, distant hills and sparse trees under a warm hazy sky",
    "sand": "golden desert sand with dunes and wind ripples, distant rocky mesas under a hot pale sky",
    "snow": "snowy tundra with drifts and icy patches, distant frozen peaks and snow-covered pines under a cold sky",
    "swamp": "murky green-brown marsh with reeds, small dark pools and dead trees under a gloomy overcast sky",
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

def _sprite_ratio(name):
    return json.load(open("imagegen/batch4/in/sprites.json"))[name]["ratio"]

def prompt_for(name):
    if name.startswith("portrait_"):
        return PORTRAIT, "1:1"
    if name == "menu__bg":  # batch 5: title screen
        return MENU_BG, "16:9"
    if name.startswith("bg__"):  # batch 4: battle backgrounds
        return BATTLE_BG.format(terrain=BG_TERRAIN[name[4:]]), "16:9"
    if name.startswith(("creatures__", "heroes__")):  # batch 4 (1c): battle units and mounted heroes
        kind, obj = name.split("__", 1)
        what = "battle unit sprite" if kind == "creatures" else "mounted hero sprite"
        note = CREATURE_NOTES.get(obj, "") or HERO_NOTES.get(obj.split("_")[-1], "")
        return UNIT.format(what=what) + ("\n" + note if note else ""), _sprite_ratio(name)
    if name.startswith(("map__", "battle__")):  # batch 4: transparent sprites on a flat backdrop
        kind, obj = name.split("__", 1)
        what = "battlefield obstacle" if kind == "battle" else "adventure-map object"
        note = SPRITE_NOTES.get(obj, "")
        return SPRITE.format(what=what) + ("\n" + note if note else ""), _sprite_ratio(name)
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
