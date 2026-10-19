"""Capitol, Castle and the faction special buildings: town sprites and building cards, painted by an image model in
the style of the existing ones.
python tools/art/special_paint.py paint [names...]  ->  imagegen/batch26/out/{town,card}__<faction>__<id>.png
python tools/art/special_paint.py ingest            ->  assets/town/<faction>_<id>.png (+ town/layout_<faction>.json),
                                                        assets/icons/building_<faction>_<id>.png

The Capitol and the Castle are repaints of the City Hall and Citadel sprites (same place in the town, grander); the
specials are new buildings painted beside a reference sprite (the tavern) on magenta, keyed out and fitted into a
free spot of the town picture (SPOTS: x, y, w, h in the 1920x810 town)."""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks
import vertex_paint as vp

BATCH = "imagegen/batch26"

DESC = {
    ("haven", "capitol"): "a grand Capitol: a magnificent white marble palace with a great golden dome, tall colonnades, "
                          "blue slate roofs, gold trim and blue-and-gold banners",
    ("necropolis", "capitol"): "a grand necromancer Capitol: a towering black basalt palace with a great dark ribbed dome "
                               "crowned by a tall needle spire with a green flame at its tip (no skull on top), bone "
                               "buttresses, violet roofs and green ghost-light in the windows",
    ("haven", "castle"): "a mighty Castle: the same long white curtain wall grown into a great fortress: every tower "
                         "twice as tall and thicker, with tall blue conical roofs and gold finials, double crenellated "
                         "battlements, two massive round gate towers in the middle, and many more blue-and-gold banners",
    ("necropolis", "castle"): "a mighty necromancer Castle: the same long black curtain wall grown into a great fortress: "
                              "every tower twice as tall with tall black spires, higher battlements set with bone "
                              "ornaments and skulls, two massive gate towers in the middle, and green ghost-light in "
                              "many windows",
    ("haven", "stables"): "Stables: a long timber-framed stable with a blue slate roof, open stalls with two horses looking "
                          "out, hay bales, a water trough and a small fenced paddock",
    ("haven", "brotherhood"): "the Brotherhood of the Sword: a grand, tall white-stone guild hall of knights with a steep "
                              "blue slate roof and a tall bell tower spire, a huge golden sword-and-shield emblem "
                              "above a tall arched double door at the top of stone steps, long blue-and-gold banners "
                              "down the facade, and weapon racks by the steps",
    ("necropolis", "necromancy_amplifier"): "a Necromancy Amplifier: a tall dark stone obelisk-shrine with bone "
                                            "ornaments, green necromantic energy swirling around a glowing green crystal "
                                            "at its top, small skulls around its base",
    ("necropolis", "skeleton_transformer"): "a Skeleton Transformer: a grim black-iron machine like a huge funnel over "
                                            "a grinding wheel on a stone platform, bones spilling from a chute, chains, "
                                            "a faint green glow",
}
BASE = {"capitol": "city_hall", "castle": "citadel"}  # repaints of these (same spot); the rest are new
SPOTS = {
    ("haven", "stables"): (0, 600, 310, 210),
    ("haven", "brotherhood"): (1440, 420, 200, 360),  # (between the smithy and the stone house: off the plaza)
    ("necropolis", "necromancy_amplifier"): (350, 530, 240, 280),
    ("necropolis", "skeleton_transformer"): (1475, 580, 250, 230),
}

TOWN_REPAINT = ("This is a town building from a fantasy strategy game on a flat magenta background, seen from a high "
                "three-quarter angle. Repaint it as {desc}. " + vp.STYLE + "\nKeep the same camera angle, the same place "
                "and about the same size in the frame (a little grander is fine), standing on the same ground line. "
                "The background must stay a perfectly flat, pure magenta (#FF00FF) everywhere around the building: no "
                "ground, no grass, no cast shadow, no scenery, no text.")
TOWN_NEW = ("This is a town building from a fantasy strategy game on a flat magenta background, only as an example of the "
            "art style, scale and camera angle. Paint a NEW, different building in its place in exactly the same "
            "style: {desc}. " + vp.STYLE + "\nThe same high three-quarter angle, about the same size in the frame, the "
            "whole building inside the frame. The background must be a perfectly flat, pure magenta (#FF00FF) "
            "everywhere around the building: no ground, no grass, no cast shadow, no scenery, no text.")
WALL_REPAINT = ("This is the long outer wall of a town in a fantasy strategy game, on a flat magenta background, seen "
                "from a high three-quarter angle. Repaint it as {desc}. " + vp.STYLE + "\nKeep the same camera "
                "angle and the same long, wide shape spanning the whole width of the frame: the wall runs from the "
                "left edge to the right edge at the same height in the frame, standing on the same ground line, with "
                "the towers in about the same places. The background must stay a perfectly flat, pure magenta "
                "(#FF00FF) everywhere around it: no ground, no grass, no cast shadow, no scenery, no text.")
CARD = ("This is a picture of a single town building for the building screen of a fantasy strategy game. Paint a NEW "
        "picture in exactly the same style, setting, landscape, lighting and camera angle, with the building in the same "
        "place at about the same size, but showing {desc}. No people, no text, no border.")


def _on_magenta(p, ratio, fill=0.8):
    sp = Image.open(p).convert("RGBA")
    sp = sp.crop(sp.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox())
    W = 1400
    H = int(W / ratio)
    c = Image.new("RGBA", (W, H), (255, 0, 255, 255))
    s = min(W * fill / sp.width, H * 0.8 / sp.height)
    sp = sp.resize((int(sp.width * s), int(sp.height * s)), Image.LANCZOS)
    c.alpha_composite(sp, ((W - sp.width) // 2, int(H * 0.9) - sp.height))
    return c.convert("RGB")


def jobs():
    out = {}
    for (fac, bid), desc in DESC.items():
        if bid == "castle":  # the whole curtain wall, wide
            src = f"assets/town/{fac}_citadel.png"
            out[f"town__{fac}__{bid}"] = (src, WALL_REPAINT.format(desc=desc), "21:9")
            out[f"card__{fac}__{bid}"] = (f"assets/icons/building_{fac}_citadel.png", CARD.format(desc=desc), "16:9")
        elif bid in BASE:
            src = f"assets/town/{fac}_{BASE[bid]}.png"
            w, h = Image.open(src).size
            ar = "16:9" if w / h > 1.5 else ("4:3" if w / h > 1.1 else "1:1")
            out[f"town__{fac}__{bid}"] = (src, TOWN_REPAINT.format(desc=desc), ar)
            out[f"card__{fac}__{bid}"] = (f"assets/icons/building_{fac}_{BASE[bid]}.png", CARD.format(desc=desc), "16:9")
        else:
            x, y, w, h = SPOTS[(fac, bid)]
            ar = "9:16" if h > w * 1.6 else ("3:4" if h > w * 1.2 else ("1:1" if h > w * 0.8 else "4:3"))
            out[f"town__{fac}__{bid}"] = (f"assets/town/{fac}_tavern.png", TOWN_NEW.format(desc=desc), ar)
            out[f"card__{fac}__{bid}"] = (f"assets/icons/building_{fac}_tavern.png", CARD.format(desc=desc), "16:9")
    return out


RATIO = {"21:9": 21 / 9, "16:9": 16 / 9, "4:3": 4 / 3, "1:1": 1.0, "3:4": 3 / 4, "9:16": 9 / 16}


def paint(names):
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    for n, (src, prompt, ar) in jobs().items():
        if names and n not in names:
            continue
        dst = f"{BATCH}/out/{n}.png"
        if os.path.exists(dst) and not names:
            print("skip", n); continue
        ref = f"{BATCH}/in/{n}.png"
        if n.startswith("town__"):
            _on_magenta(src, RATIO[ar], 0.94 if ar == "21:9" else 0.8).save(ref)
        else:
            Image.open(src).convert("RGB").resize((1376, 860), Image.LANCZOS).save(ref)
        img = vp.paint(client, "gemini-nano-banana-2.1", ref, prompt, ar, "2K")
        if img:
            img.save(dst); print("done", n, flush=True)
        else:
            print("FAILED", n, flush=True)


def _cut(p):
    cut = drop_specks(key_out(Image.open(p).convert("RGB")))
    return cut.crop(cut.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox())


def ingest():
    lays = {}
    for (fac, bid) in DESC:
        lp = f"assets/town/layout_{fac}.json"
        lay = lays.setdefault(fac, json.load(open(lp)))
        t = f"{BATCH}/out/town__{fac}__{bid}.png"
        if os.path.exists(t):
            fig = _cut(t)
            if bid == "castle":  # as wide as the Citadel's wall, on its ground line; taller towers run off the top
                x, y, w, h = lay["citadel"]
                fig = fig.resize((w, int(fig.height * w / fig.width)), Image.LANCZOS)
                if fig.height > y + h:
                    fig = fig.crop((0, fig.height - (y + h), w, fig.height))
                W, H = w, fig.height
                nx, ny = x, y + h - H
            elif bid in BASE:  # in the base building's place: same canvas, bottom-centred, as wide as the base
                x, y, w, h = lay[BASE[bid]]
                s = min(w * 1.04 / fig.width, (y + h) / fig.height)
                fig = fig.resize((int(fig.width * s), int(fig.height * s)), Image.LANCZOS)
                W, H = max(w, fig.width), max(h, fig.height)
                nx, ny = x + w // 2 - W // 2, y + h - H
            else:
                x, y, w, h = SPOTS[(fac, bid)]
                s = min(w / fig.width, h / fig.height)
                fig = fig.resize((int(fig.width * s), int(fig.height * s)), Image.LANCZOS)
                W, H = w, h
                nx, ny = x, y
            canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            canvas.alpha_composite(fig, ((W - fig.width) // 2, H - fig.height))
            canvas.save(f"assets/town/{fac}_{bid}.png")
            lay[bid] = [int(nx), int(ny), int(W), int(H)]
            print("  town", fac, bid, lay[bid])
        c = f"{BATCH}/out/card__{fac}__{bid}.png"
        if os.path.exists(c):
            sz = Image.open(f"assets/icons/building_{fac}_tavern.png").size
            Image.open(c).convert("RGB").resize(sz, Image.LANCZOS).save(f"assets/icons/building_{fac}_{bid}.png")
    for fac, lay in lays.items():
        json.dump(lay, open(f"assets/town/layout_{fac}.json", "w"), indent=0)


if __name__ == "__main__":
    if sys.argv[1] == "paint":
        paint(sys.argv[2:])
    else:
        ingest()
