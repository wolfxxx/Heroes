"""The castle wall, moat and keep of a siege painted into the battle backdrop (as the classic game does), plus a
ruined copy of it from which the breaches are cut.
python tools/art/siege_wall_paint.py mock               ->  imagegen/batch25/in/mock_<faction>.png (layout sketch)
python tools/art/siege_wall_paint.py paint [names...]   ->  imagegen/batch25/out/{wall,ruin}_<faction>.png
python tools/art/siege_wall_paint.py breach [names...]  ->  imagegen/batch25/out/breach_<faction>_<segment>.png
python tools/art/siege_wall_paint.py ingest             ->  assets/battle/bg_siege_<faction>.png,
                                                            assets/battle/siege_<faction>_ruin_<segment>.png (+ siege.json)

The sketch draws plain grey shapes over the open siege backdrop exactly where the battle grid puts the wall (column 11),
the moat (column 10, a bridge before the gate on row 5), the corner towers (rows 0 and 10) and the keep (beyond the
grid); the model repaints them. The ruined copy is a repaint of the finished backdrop with every piece smashed; ingest
cuts one feathered overlay per wall segment out of it, shown when that segment falls."""
import os, sys, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import vertex_paint as vp

BATCH = "imagegen/batch25"
FACTIONS = ["haven", "necropolis"]

# battle.gd geometry (1920x1080)
HEX_W, ROW_STEP, X0, Y0 = 96.0, 68.0, 264.0, 272.0
WALL_X, MOAT_X = 11, 10
SEGMENTS = [[0], [1, 2], [3, 4], [5], [6, 7], [8, 9], [10]]  # battle_logic.gd SEGMENTS
BANDS = [(0, 270), (270, 400), (400, 470), (470, 645), (645, 750), (750, 885), (885, 1080)]  # (screen y, per segment)
FEATHER = 24


def hex_pos(x, y):
    return X0 + x * HEX_W + (HEX_W * 0.5 if y % 2 else 0.0), Y0 + y * ROW_STEP


STONE = {"haven": ((206, 196, 172), (160, 150, 130), (110, 102, 90), (70, 96, 150)),
         "necropolis": ((92, 88, 96), (64, 60, 70), (40, 38, 46), (96, 60, 130))}


def mock(fac):
    bg = Image.open(f"imagegen/batch24/out/bg__siege_{fac}.png").convert("RGB").resize((1920, 1080))  # (the open backdrop)
    d = ImageDraw.Draw(bg)
    face, side, dark, roof = STONE[fac]
    # moat: a channel of dark water before the wall, bridge before the gate
    for y in range(-1, 12):
        cx, cy = hex_pos(MOAT_X, y)
        d.ellipse((cx - 58, cy - 40, cx + 50, cy + 52), fill=(38, 70, 82))
    gx, gy = hex_pos(MOAT_X, 5)
    d.rectangle((gx - 70, gy - 22, gx + 60, gy + 40), fill=(120, 84, 50))
    for k in range(6):
        d.line((gx - 70 + k * 26, gy - 22, gx - 70 + k * 26, gy + 40), fill=(80, 55, 32), width=3)
    # the curtain wall straight along the column: an outer face towards the attackers, the wall walk with merlons
    xs = [hex_pos(WALL_X, y)[0] for y in range(11)]
    xm = sum(xs) / len(xs)
    H = 150
    top, bot = Y0 - 20, Y0 + 10 * ROW_STEP + 30
    d.rectangle((xm - 55, top - H, xm + 5, bot), fill=face)            # outer face
    d.rectangle((xm + 5, top - H, xm + 55, bot - H + 40), fill=side)   # wall walk
    for y in range(int(top - H), int(bot), 22):
        d.line((xm - 55, y, xm + 5, y), fill=dark, width=2)
    for y in range(int(top - H), int(bot - H + 30), 30):
        d.rectangle((xm - 4, y, xm + 14, y + 16), fill=face, outline=dark)
        d.rectangle((xm + 46, y, xm + 62, y + 16), fill=face, outline=dark)
    # gatehouse on row 5
    gx, gy = hex_pos(WALL_X, 5)
    gx = xm
    d.rectangle((gx - 75, gy - 200, gx + 70, gy + 30), fill=face, outline=dark, width=3)
    d.rectangle((gx + 30, gy - 210, gx + 70, gy + 30), fill=side)
    d.chord((gx - 65, gy - 110, gx + 15, gy - 30), 180, 360, fill=(60, 40, 25))
    d.rectangle((gx - 65, gy - 70, gx + 15, gy + 30), fill=(60, 40, 25))
    for k in range(5):
        d.rectangle((gx - 75 + k * 30, gy - 225, gx - 57 + k * 30, gy - 200), fill=face, outline=dark)
    # corner towers on rows 0 and 10, and the keep beyond the grid
    for (tx, ty), h, r in [((xm, hex_pos(WALL_X, 0)[1]), 210, 80), ((xm, hex_pos(WALL_X, 10)[1]), 210, 80),
                           ((1800, 900), 330, 105)]:
        d.rectangle((tx - r, ty - h, tx + r, ty + 20), fill=face, outline=dark, width=3)
        d.ellipse((tx - r, ty - 10, tx + r, ty + 40), fill=face, outline=dark, width=3)
        d.rectangle((tx + r * 0.4, ty - h, tx + r, ty + 25), fill=side)
        d.polygon([(tx - r - 10, ty - h), (tx, ty - h - r * 1.3), (tx + r + 10, ty - h)], fill=roof)
        for k in range(2):
            d.rectangle((tx - 8, ty - h + 50 + k * 70, tx + 4, ty - h + 80 + k * 70), fill=(30, 25, 22))
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    bg.save(f"{BATCH}/in/mock_{fac}.png")


TOWN = {"haven": "pale cream limestone walls and towers with blue slate roofs, gold trim and blue-and-gold banners",
        "necropolis": "black basalt walls and towers with bone ornaments, dark violet roofs and faint green ghost-light "
                      "in the arrow slits"}

WALL_PROMPT = ("This is a battlefield background of a fantasy strategy game with a rough grey layout sketch painted over "
               "it. Repaint the whole picture as one finished, hand-painted CASTLE SIEGE battlefield. " + vp.STYLE + "\n"
               "Turn the sketch into: a tall continuous crenellated castle curtain wall running from the top to the bottom "
               "of the picture, its outer face turned towards the left (the attackers' side), seen from high above at the "
               "same oblique angle as the ground; a gatehouse with a heavy closed wooden gate in its middle; a round "
               "arrow tower with a conical roof at each end; a big keep beyond the wall on the far right; a moat of dark "
               "water along the foot of the wall on the left with a lowered wooden drawbridge before the gate. "
               "Materials: {town}.\nVERY IMPORTANT: keep every sketched shape exactly where it is and the same size (the "
               "wall, gate, towers, keep, moat and bridge must line up with a game grid laid over the picture later), "
               "keep the left two thirds of the picture (the open grass, the camp, the sky and the town in the distance) "
               "as it is, and the ground right of the wall an open courtyard of trodden earth and flagstones. No units, "
               "no people, no grid, no text.")

RUIN_PROMPT = ("This is a castle siege battlefield from a fantasy strategy game. Paint EXACTLY the same picture, same "
               "camera, same composition, every shape in the same place, but with the whole castle wall, the gatehouse and "
               "both round towers in front of the keep smashed by catapult fire: deep jagged breaches cut down to a "
               "low stump all along the wall, heaps of fallen blocks and rubble spilling forward to the moat, the gate "
               "smashed to splinters, the two towers broken to jagged stumps, dust. Leave the keep, the moat, the "
               "bridge, the sky, the grass and everything else exactly as it is. " + vp.STYLE + "\nNo units, no people, "
               "no text.")


_GAP = ("the stretch of curtain wall: knock a wide OPEN GAP right through it, the wall walk and its battlements "
        "completely gone in the middle, so the bare dirt ground of the courtyard behind the wall shows clearly "
        "THROUGH the gap; only the jagged broken ends of the wall stand on either side; a few fallen blocks lie low "
        "and scattered on the ground in the gap and in front of it toward the moat, no tall heap")
SEG_WHAT = ["the round corner tower at the top", _GAP,
            "the top of the gatehouse: blow its whole crenellated top and the upper part of its front wall away, "
            "leaving a big ragged open hole down into the gatehouse through which the dirt ground of the courtyard "
            "behind is clearly visible; broken blocks fallen onto the bridge and into the moat",
            "the gatehouse's gate: smash the gate itself open, the heavy doors torn off their hinges and lying broken "
            "and splintered on the drawbridge, the archway now an open dark passage with the courtyard ground "
            "visible through it, the gatehouse's battlements cracked with a few merlons knocked off; the gatehouse "
            "itself still stands",
            "the conical roof of the lower round tower and the wall just above it: smash the roof in, half of it "
            "gone, broken rafters sticking up, a gaping open hole into the tower top, slates and blocks fallen "
            "into the moat",
            "the lower round tower's body: blast a big ragged OPEN HOLE right through the tower's wall, through "
            "which the dirt ground behind the tower is clearly visible; its blocks fallen at its foot toward the moat; "
            "its roof sagging and broken above the hole",
            "the round corner tower at the bottom"]

BREACH_PROMPT = ("This is a crop of a castle siege battlefield from a fantasy strategy game. Paint EXACTLY the same picture, "
                 "same framing, every shape in the same place, but with {what} in the MIDDLE band of the picture smashed by "
                 "catapult fire, a little dust. It must read at a glance as a hole you can walk through, not a damaged "
                 "wall. Only the middle band changes; the top and bottom edges of the "
                 "picture, the moat, the grass, the courtyard and the town behind stay exactly as they are. " + vp.STYLE +
                 "\nNo units, no people, no text.")
BOX = 460  # (square crop around each segment for its breach)


def _breach_box(i):
    y0, y1 = BANDS[i]
    cy = min(max((y0 + y1) // 2, BOX // 2), 1080 - BOX // 2)
    return (1385 - BOX // 2, cy - BOX // 2, 1385 + BOX // 2, cy + BOX // 2)


def breach(names):
    """One repaint per segment of a square crop around it, broken in the middle (sharper and better aligned than
    one ruined copy of the whole picture)."""
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    for fac in FACTIONS:
        wall = Image.open(f"{BATCH}/out/wall_{fac}.png").convert("RGB").resize((1920, 1080), Image.LANCZOS)
        for i in range(len(SEGMENTS)):
            n = f"breach_{fac}_{i}"
            if names and n not in names:
                continue
            dst = f"{BATCH}/out/{n}.png"
            if os.path.exists(dst) and not names:
                print("skip", n); continue
            src = f"{BATCH}/in/{n}.png"
            wall.crop(_breach_box(i)).resize((1024, 1024), Image.LANCZOS).save(src)
            img = vp.paint(client, "gemini-nano-banana-2.1", src, BREACH_PROMPT.format(what=SEG_WHAT[i]), "1:1", "1K")
            if img:
                img.save(dst); print("done", n, flush=True)
            else:
                print("FAILED", n, flush=True)


HAVEN_FROM_NECRO = ("Repaint this castle siege battlefield from a fantasy strategy game as the siege of a NOBLE HUMAN "
                    "CASTLE. " + vp.STYLE + "\nVERY IMPORTANT: keep the castle wall, the gatehouse and its gate, the "
                    "drawbridge, the moat, the round tower, the big keep on the right, the courtyard and the open grass "
                    "exactly where they are, the same shapes and sizes, the same camera. Only change their materials and "
                    "colours: pale cream limestone blocks, blue slate roofs with gold trim, blue-and-gold banners. Replace "
                    "the dark necromancer town behind the wall with the white towers, blue roofs and golden domes of a "
                    "noble city, and the dark green-lit sky with a bright blue sky with white clouds. Keep the left side of "
                    "the picture (the grass, the camp, the trees, the mountains) as it is. No units, no people, no text.")


def paint(names):
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    for fac in ["necropolis", "haven"]:
        for kind in ["wall", "ruin"]:
            n = f"{kind}_{fac}"
            if names and n not in names:
                continue
            dst = f"{BATCH}/out/{n}.png"
            if os.path.exists(dst) and not names:
                print("skip", n); continue
            if kind == "wall" and fac == "haven":  # (after the Necropolis castle: the same wall line)
                src = f"{BATCH}/in/wall_necropolis_1920.png"
                Image.open(f"{BATCH}/out/wall_necropolis.png").convert("RGB").resize((1920, 1080)).save(src)
                prompt = HAVEN_FROM_NECRO
            elif kind == "wall":
                src, prompt = f"{BATCH}/in/mock_{fac}.png", WALL_PROMPT.format(town=TOWN[fac])
            else:
                src = f"{BATCH}/in/wall_{fac}_1920.png"
                Image.open(f"{BATCH}/out/wall_{fac}.png").convert("RGB").resize((1920, 1080), Image.LANCZOS).save(src)
                prompt = RUIN_PROMPT
            img = vp.paint(client, "gemini-nano-banana-2.1", src, prompt, "16:9", "2K")
            if img:
                img.save(dst); print("done", n, flush=True)
            else:
                print("FAILED", n, flush=True)


def ingest():
    """The finished backdrop, and per wall segment a feathered cut of the ruined picture (a band of rows around
    the segment, from the moat to the courtyard) with its position on the screen."""
    meta = {}
    for fac in FACTIONS:
        w = f"{BATCH}/out/wall_{fac}.png"
        r = f"{BATCH}/out/ruin_{fac}.png"
        if not os.path.exists(w):
            continue
        wall = Image.open(w).convert("RGB").resize((1920, 1080), Image.LANCZOS)
        wall.save(f"assets/battle/bg_siege_{fac}.png")
        # (the whole ruined copy is only the fallback for a segment without its own breach painting)
        ruin = Image.open(r).convert("RGB").resize((1920, 1080), Image.LANCZOS) if os.path.exists(r) else wall
        segs = []
        for i, rows in enumerate(SEGMENTS):
            # the band of the picture this segment owns (the wall runs straight down the screen, so the bands
            # split it by height; the gate takes the whole gatehouse), overlapping its neighbours by the feather
            y0, y1 = BANDS[i]
            y0, y1 = max(0, y0 - FEATHER // 2), min(1080, y1 + FEATHER // 2)
            x0, x1 = 1200, 1570
            box = (x0, y0, x1, y1)
            src = ruin
            bp = f"{BATCH}/out/breach_{fac}_{i}.png"
            if os.path.exists(bp):  # the segment's own breach, put back where its crop came from
                bb = _breach_box(i)
                src = wall.copy()
                src.paste(Image.open(bp).convert("RGB").resize((bb[2] - bb[0], bb[3] - bb[1]), Image.LANCZOS), bb[:2])
            # alpha: where the ruined picture differs from the intact one, feathered, and faded at the band ends
            a = np.abs(np.asarray(src.crop(box), np.int16) - np.asarray(wall.crop(box), np.int16)).sum(2)
            # (a fallen tower or roof needs the wider margin: the soft edge must cover the old outline in the sky)
            grow = 25 if i in (0, 4, 6) else 9
            m = Image.fromarray(np.clip((a - 18) * 6, 0, 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(grow))
            m = m.filter(ImageFilter.GaussianBlur(6))
            ma = np.asarray(m, np.float32)
            h = ma.shape[0]
            ramp = np.ones(h, np.float32)
            f = FEATHER
            if i != 0:
                ramp[:f] = np.linspace(0, 1, f)
            if i != 6:
                ramp[-f:] = np.linspace(1, 0, f)
            ma = ma * ramp[:, None]
            w = ma.shape[1]  # and towards the field and the courtyard
            side = np.ones(w, np.float32)
            side[:30] = np.linspace(0, 1, 30)
            side[-70:] = np.linspace(1, 0, 70)
            ma = ma * side[None, :]
            out = src.crop(box).convert("RGBA")
            out.putalpha(Image.fromarray(ma.astype(np.uint8)))
            out.save(f"assets/battle/siege_{fac}_ruin_{i}.png")
            segs.append([x0, y0])
        meta[fac] = segs
        print("ingested", fac)
    p = "assets/battle/siege.json"
    old = json.load(open(p)) if os.path.exists(p) else {}
    old.update(meta)
    json.dump(old, open(p, "w"), indent=1)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "mock":
        for f in FACTIONS:
            mock(f)
    elif cmd == "paint":
        paint(sys.argv[2:])
    elif cmd == "breach":
        breach(sys.argv[2:])
    else:
        ingest()
