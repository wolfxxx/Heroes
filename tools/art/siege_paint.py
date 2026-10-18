"""War machines and siege pieces, painted by an image model in the style of the existing battle art.
python tools/art/siege_paint.py paint [names...]   ->  imagegen/batch24/out/<name>.png
python tools/art/siege_paint.py ingest             ->  assets/creatures/<machine>.png (+ anchors), portraits,
                                                       assets/battle/siege_<faction>_<piece>.png (+ anchors), bg_siege_<faction>.png

Machines and wall pieces are painted on flat magenta next to a reference sprite (a battle unit, a piece of the town's
castle) that sets the style and scale; ingest keys the magenta out. The siege backdrops repaint the grass battlefield
with the faction's town rising behind the castle wall on the right."""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks, shadow, figure, feet
import vertex_paint as vp

BATCH = "imagegen/batch24"
STYLE = vp.STYLE

MACHINES = {
    "ballista": "a ballista: a huge mounted crossbow of dark oak and iron on a wheeled wooden carriage, a long bolt "
                "loaded, aimed to the right",
    "first_aid_tent": "a field hospital tent: a small square canvas tent in cream and red with a red healing symbol "
                      "(not a cross: a red heart inside a circle), the front flap open, a bench and bandage rolls beside it",
    "ammo_cart": "an ammunition cart: a two-wheeled wooden cart loaded with quivers, bundles of arrows and crossbow bolts "
                 "and a few barrels, with shafts for a horse resting on the ground",
    "catapult": "a siege catapult: a heavy wooden throwing-arm catapult on a sturdy wheeled frame, iron fittings, a "
                "stone boulder in its sling, facing right",
}

FACTION = {
    "haven": "pale cream limestone blocks, blue slate roofs and gold trim, blue-and-gold banners",
    "necropolis": "black basalt blocks with bone ornaments, dark violet roofs, small green ghost-light in the slits",
}

PIECES = {
    "wall": "one block of crenellated castle curtain wall, as wide as it is tall, seen from the front-left at the same "
            "high three-quarter angle as the battle units, standing on the ground",
    "wall_broken": "the ruin of one block of castle curtain wall smashed by a catapult: a low heap of broken stone "
                   "blocks and rubble with a jagged stump of wall, seen from the front-left at a high three-quarter angle",
    "tower": "one round castle defence tower with arrow slits and a crenellated top (and a small conical roof), about "
             "twice as tall as it is wide, seen from the front-left at a high three-quarter angle, standing on the ground",
    "tower_broken": "the ruin of a round castle tower smashed by a catapult: a broken stump of round wall with jagged "
                    "top and rubble heaped around it, seen from the front-left at a high three-quarter angle",
    "gate": "a castle gatehouse: a squat square tower with a large arched gateway closed by a heavy wooden door with "
            "iron bands, crenellated top, seen from the front-left at a high three-quarter angle, standing on the ground",
    "gate_broken": "a smashed castle gatehouse: the arched gateway with its wooden door broken and hanging in splinters, "
                   "stones fallen from the top, seen from the front-left at a high three-quarter angle",
}

MACHINE_PROMPT = ("The first image shows a battle unit sprite from a fantasy strategy game, only as an example of the "
                  "art style and scale. Paint a NEW battle sprite in exactly the same hand-painted style and lighting "
                  "(warm light from the upper left): {desc}. Side view, about as large in the frame as the example unit, "
                  "the whole object inside the frame, standing on the same ground line. Nobody operating it.\n"
                  "The background must be a perfectly flat, pure magenta (#FF00FF) everywhere around the object: no "
                  "ground, no cast shadow, no scenery, no text.")

PORTRAIT_PROMPT = ("The first image is a creature portrait from a fantasy strategy game, only as an example of the art "
                   "style. Paint a NEW portrait in exactly the same style, framing and soft warm brown-and-amber painted "
                   "background: {desc}, shown large and centred. " + STYLE + "\nSquare image. No people, no text, no "
                   "border, no frame, no signature.")

PIECE_PROMPT = ("The first image shows part of a fantasy castle from a strategy game, only as an example of its stone, "
                "roofs, colours and painted style. Paint a single NEW sprite for the siege battle screen: {piece}. "
                "Materials and colours: {fac}. " + STYLE + "\nThe whole piece inside the frame, centred. The background "
                "must be a perfectly flat, pure magenta (#FF00FF) everywhere around it: no ground, no grass, no cast "
                "shadow, no scenery, no text.")

BG_PROMPT = ("Repaint this battlefield background of a fantasy strategy game as the battlefield of a CASTLE SIEGE. "
             + STYLE + "\nKeep the same camera, the same horizon height, the same sky and the same grassy ground in the "
             "left two thirds of the picture. In the right third, behind where the castle wall will stand, paint the "
             "town inside the walls rising in the distance: {town}. Do NOT paint the castle wall itself, any units, "
             "a grid or text; the ground in front stays open grass.")

TOWN = {
    "haven": "the white towers, blue slate roofs and golden domes of a noble city, banners flying",
    "necropolis": "the black spires, crypts and violet roofs of a necromancer citadel under a darker sky with green "
                  "ghost-light",
}


def _magenta_canvas(fig_rgba, ratio=(4, 3), long=1536, scale=1.0):
    W, H = (long, int(long * ratio[1] / ratio[0])) if ratio[0] >= ratio[1] else (int(long * ratio[0] / ratio[1]), long)
    c = Image.new("RGBA", (W, H), (255, 0, 255, 255))
    f = fig_rgba.copy()
    s = min(W * 0.6 / f.width, H * 0.7 / f.height) * scale
    f = f.resize((int(f.width * s), int(f.height * s)), Image.LANCZOS)
    c.alpha_composite(f, ((W - f.width) // 2, int(H * 0.85) - f.height))
    return c.convert("RGB")


def refs():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    _, fig, box = figure("cavalier")
    _magenta_canvas(fig.crop(box)).save(f"{BATCH}/in/ref_unit.png")
    Image.open("assets/creatures/portraits/cavalier.png").convert("RGB").resize((1024, 1024)).save(f"{BATCH}/in/ref_portrait.png")
    for fac in FACTION:
        fort = Image.open(f"assets/town/{fac}_fort.png").convert("RGBA")
        # the right half of the fortress: a tower and a stretch of wall
        part = fort.crop((fort.width // 2, 0, fort.width, fort.height))
        part = part.crop(part.getchannel("A").getbbox())
        _magenta_canvas(part, (3, 2)).save(f"{BATCH}/in/ref_fort_{fac}.png")
    Image.open("assets/battle/bg_grass.png").convert("RGB").save(f"{BATCH}/in/ref_bg.png")


def jobs():
    out = {}
    for m, d in MACHINES.items():
        out[f"machine__{m}"] = ("ref_unit", MACHINE_PROMPT.format(desc=d), "4:3")
        out[f"mport__{m}"] = ("ref_portrait", PORTRAIT_PROMPT.format(desc=d), "1:1")
    for fac, fd in FACTION.items():
        for p, pd in PIECES.items():
            ar = "3:4" if p.startswith("tower") else "1:1"
            out[f"piece__{fac}__{p}"] = (f"ref_fort_{fac}", PIECE_PROMPT.format(piece=pd, fac=fd), ar)
        out[f"bg__siege_{fac}"] = ("ref_bg", BG_PROMPT.format(town=TOWN[fac]), "16:9")
    return out


def paint(names):
    refs()
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    for n, (ref, prompt, ar) in jobs().items():
        if names and n not in names:
            continue
        dst = f"{BATCH}/out/{n}.png"
        if os.path.exists(dst) and not names:
            print("skip", n); continue
        img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/{ref}.png", prompt, ar, "2K")
        if img:
            img.save(dst); print("done", n, flush=True)
        else:
            print("FAILED", n, flush=True)


def _cut(src, height):
    """Key out the magenta, drop specks, crop to the figure and scale it to `height` pixels of solid figure."""
    cut = drop_specks(key_out(Image.open(src).convert("RGB")))
    a = np.asarray(cut)[..., 3]
    ys, xs = np.nonzero(a > 20)
    cut = cut.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    ys2, _ = np.nonzero(np.asarray(cut)[..., 3] > 200)
    s = height / max(1, ys2.max() - ys2.min())
    return cut.resize((max(1, int(cut.width * s)), max(1, int(cut.height * s))), Image.LANCZOS)


def _with_shadow(fig):
    ca = np.asarray(fig)[..., 3]
    px, py = feet(ca)
    pad = 12
    sh_w = int(fig.height * 0.55 * 0.32) + 30
    W, H = fig.width + 2 * pad + sh_w, fig.height + 2 * pad + 10
    fa = np.zeros((H, W), np.uint8)
    fa[pad:pad + fig.height, pad:pad + fig.width] = ca
    sha = shadow(fa, pad + px, pad + py)
    out = Image.fromarray(np.dstack([np.zeros((H, W, 3), np.uint8) + np.array([12, 10, 8], np.uint8),
                                     (sha * 255).astype(np.uint8)]), "RGBA")
    out.alpha_composite(fig, (pad, pad))
    return out, [round((pad + px) / W, 4), round((pad + py) / H, 4)]


def ingest():
    anchors = json.load(open("assets/creatures/anchors.json"))
    banch_p = "assets/battle/anchors.json"
    banch = json.load(open(banch_p)) if os.path.exists(banch_p) else {}
    heights = {"ballista": 230, "first_aid_tent": 260, "ammo_cart": 220, "catapult": 300}  # (sprite pixels, like the units)
    for m in MACHINES:
        src = f"{BATCH}/out/machine__{m}.png"
        if os.path.exists(src):
            out, anc = _with_shadow(_cut(src, heights[m]))
            out.save(f"assets/creatures/{m}.png")
            anchors[f"{m}.png"] = anc
            print("  machine", m, out.size)
        ps = f"{BATCH}/out/mport__{m}.png"
        if os.path.exists(ps):
            Image.open(ps).convert("RGB").resize((256, 256), Image.LANCZOS).save(f"assets/creatures/portraits/{m}.png")
    for fac in FACTION:
        for p in PIECES:
            src = f"{BATCH}/out/piece__{fac}__{p}.png"
            if not os.path.exists(src):
                continue
            h = {"tower": 420, "tower_broken": 200, "wall": 250, "wall_broken": 120, "gate": 290, "gate_broken": 260}[p]
            fig = _cut(src, h)
            fig.save(f"assets/battle/siege_{fac}_{p}.png")
            a = np.asarray(fig)[..., 3]
            px, py = feet(a, lying=True)
            banch[f"siege_{fac}_{p}.png"] = [round(px / fig.width, 4), round(py / fig.height, 4)]
            print("  piece", fac, p, fig.size)
        bs = f"{BATCH}/out/bg__siege_{fac}.png"
        if os.path.exists(bs):
            Image.open(bs).convert("RGB").resize((1920, 1080), Image.LANCZOS).save(f"assets/battle/bg_siege_{fac}.png")
    json.dump(anchors, open("assets/creatures/anchors.json", "w"), indent=0, sort_keys=True)
    json.dump(banch, open(banch_p, "w"), indent=0, sort_keys=True)


if __name__ == "__main__":
    if sys.argv[1] == "paint":
        paint(sys.argv[2:])
    else:
        ingest()
