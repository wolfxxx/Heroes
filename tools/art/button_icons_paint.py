"""Panel button icons painted as sheets on magenta in the style of the stat icons: the adventure panel (kingdom
overview, hero, sleep, move, spellbook, next hero, end turn, system; 4x2) and the battle bar (retreat, auto,
defend; the battle reuses the spellbook and the hourglass).
python tools/art/button_icons_paint.py paint [adventure|battle]   ->  imagegen/batch20/out/<sheet>.png
python tools/art/button_icons_paint.py ingest [adventure|battle]  ->  assets/ui/btn_<name>.png (128 px, transparent)
(the "retreat", "retreat2", "retreat3" and "retreat4" sheets paint eight takes of the retreat icon; the best is kept as btn_retreat.png by hand;
"conditions" paints takes of the scenario win and loss icons, kept as ui/cond_win.png and ui/cond_lose.png, and the Offense skill,
kept as icons/skill_offense.png)"""
import os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks

BATCH = "imagegen/batch20"
COLS, ROWS = 4, 2
W, H = 2048, 1024
SIZE = 128
SHEETS = {"adventure": [
    ("kingdom", "a small castle keep with a golden crown floating above it"),
    ("hero", "a knight's steel helmet with a red plume, seen from the side"),
    ("sleep", "a pale golden crescent moon with three small stars"),
    ("move", "a galloping horse's hoof with a horseshoe and three motion streaks behind it"),
    ("spellbook", "an open leather spellbook with glowing blue runes rising from its pages"),
    ("next_hero", "a knight's steel helmet with a golden curved arrow sweeping around it to the right"),
    ("end_turn", "an ornate brass hourglass with golden sand"),
    ("system", "a rolled parchment scroll with a red wax seal and a quill"),
], "battle": [
    ("retreat", "a tattered white flag on a broken spear shaft"),
    ("auto", "two crossed steel swords with a golden circular arrow around them"),
    ("defend", "a heavy steel kite shield with a gold rim and a red cross"),
    ("surrender", "a small leather purse of gold coins tied with a cord"),
    ("options", "a small ornate brass astrolabe"),
    ("ballista", "a wooden siege ballista on wheels, side view"),
    ("catapult", "a wooden siege catapult with a stone in its bucket, side view"),
    ("first_aid", "a small canvas field tent with a red cross on it"),
], "retreat": [  # (the retreat icon again, not a white flag: that reads as surrender; one of these is kept)
    (f"retreat_{k}", "a knight on a galloping horse riding away to the left, seen from the side, a small cloud of "
     "dust behind the hooves") for k in "abcdefgh"
], "retreat2": [  # (bolder takes that fill a square button: the first round's rider was thin and wide)
    (f"retreat2_{k}", "an armoured knight on a rearing, galloping warhorse turning away to the left, drawn large and "
     "bold so it fills the cell, the horse's mane and the knight's red cape streaming, a compact square composition, "
     "no ground and no dust") for k in "abcd"
] + [
    (f"retreat2_{k}", "the head, neck and front legs of an armoured warhorse galloping away to the left, mane "
     "flying, a red and gold caparison, three golden motion streaks behind it, drawn large and bold, a compact square "
     "composition") for k in "efgh"
], "retreat3": [  # (the rearing rider read as a charge: one fleeing, looking back, the dust of its flight behind it)
    (f"retreat3_{k}", "a knight galloping away to the left on a frightened horse, the knight twisted round in the "
     "saddle looking back over his shoulder, his shield slung on his back, a big cloud of dust kicked up behind the "
     "horse, drawn large and bold so it fills the cell, a compact square composition") for k in "abcd"
] + [
    (f"retreat3_{k}", "a knight galloping away to the left on his horse, seen from the side, with a big bold golden "
     "arrow curving back to the left over them, drawn large so it fills the cell, a compact square composition")
    for k in "efgh"
], "retreat4": [  # (the arrow read well, but a brown rider blurred into the wooden bar: a bright steel one)
    (f"retreat4_{k}", "a knight in bright polished silver plate armour on a white horse, galloping away to the left, "
     "seen from the side, with a big bold golden arrow curving back to the left over them, light and bright colours "
     "so it stands out on dark wood, drawn large so it fills the cell, a compact square composition") for k in "abcdefgh"
], "conditions": [  # (scenario win / loss pictures and the Offense skill, each its own icon: none reuses a button's)
    (f"win_{k}", "a golden laurel wreath around an upright steel sword, drawn large and bold, a compact square "
     "composition") for k in "abc"
] + [
    (f"lose_{k}", "a ruined stone castle tower, cracked and broken at the top, with a torn red banner hanging from it, "
     "drawn large and bold, a compact square composition") for k in "abc"
] + [
    (f"offense_{k}", "a steel sword swinging down with a bright red curved slash trail behind its blade, drawn large "
     "and bold, a compact square composition") for k in "ab"
]}
PROMPT = ("This is a blank icon sheet for a fantasy strategy game's interface: a flat magenta (#FF00FF) background "
          "divided into a 4 x 2 grid of equal square cells (4 columns, 2 rows). Paint exactly one icon in the centre of "
          "each cell, in reading order (left to right, top row first):\n{items}\n"
          "Paint them in the same style as the icons in the second image: hand-painted fantasy game icons with rich "
          "colours, strong light from the upper left, a crisp dark outline, a bold readable silhouette at small size. "
          "Draw only the object: no background disc, no frame, no button, no text or letters. Keep each icon well "
          "inside its cell with magenta around it, and keep the background pure flat magenta everywhere else.")


def _out(sheet):
    return f"{BATCH}/out/{'buttons' if sheet == 'adventure' else sheet}.png"


def paint(sheet):
    ICONS = SHEETS[sheet]
    import vertex_paint as vp
    from google import genai
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    Image.new("RGB", (W, H), (255, 0, 255)).save(f"{BATCH}/in/buttons.png")
    style = Image.new("RGB", (4 * 140, 140), (40, 32, 24))
    for i, st in enumerate(["attack", "defense", "power", "knowledge"]):
        ic = Image.open(f"assets/icons/stat_{st}.png").convert("RGBA").resize((128, 128), Image.LANCZOS)
        style.paste(ic, (i * 140 + 6, 6), ic)
    style.save(f"{BATCH}/in/style.png")
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    items = "\n".join(f"{i + 1}. {d}" for i, (_, d) in enumerate(ICONS))
    img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/buttons.png", PROMPT.format(items=items), "16:9", "2K", style)
    if img:
        img.save(_out(sheet))
        print("done", img.size)


def ingest(sheet):
    ICONS = SHEETS[sheet]
    src = Image.open(_out(sheet)).convert("RGB")
    cut = key_out(src)
    cw, ch = cut.width / COLS, cut.height / ROWS
    for k, (name, _) in enumerate(ICONS):
        cx, cy = (k % COLS) * cw, (k // COLS) * ch
        cell = drop_specks(cut.crop((int(cx), int(cy), int(cx + cw), int(cy + ch))), keep=0.04)
        a = np.asarray(cell)[..., 3]
        ys, xs = np.nonzero(a > 24)
        if len(xs) < 200:
            print(f"  {name}: empty cell"); continue
        obj = cell.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        s = (SIZE - 8) / max(obj.width, obj.height)
        obj = obj.resize((max(1, round(obj.width * s)), max(1, round(obj.height * s))), Image.LANCZOS)
        out = Image.new("RGBA", (SIZE, SIZE))
        out.alpha_composite(obj, ((SIZE - obj.width) // 2, (SIZE - obj.height) // 2))
        out.save(f"assets/ui/btn_{name}.png")
        print(f"  ui/btn_{name}.png")


if __name__ == "__main__":
    {"paint": paint, "ingest": ingest}[sys.argv[1]](sys.argv[2] if len(sys.argv) > 2 else "adventure")
