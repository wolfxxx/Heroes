"""Building pictures for the build / recruit dialogs, like the hall screen of the classics.
python tools/art/building_cards.py           ->  assets/icons/building_<faction>_<sprite id>.png (320x200)
python tools/art/building_cards.py prep-edge ->  imagegen/batch9/in/card__<faction>__<id>.png for buildings cut off
                                                 by the screen edge; paint them with vertex_paint.py, then run
python tools/art/building_cards.py ingest-edge

Each card is the painted town backdrop with only that building on it, cropped around the building. Buildings the
town render cut off at the left/right edge would show as slivers, so those cards are repainted whole by the image
model from the partial view plus a description."""
import os, sys, json
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from imagegen_prep import town_view, VIEW_H, PAD_W

OUT = "assets/icons"
CARD = (320, 200)
BATCH = "imagegen/batch9"
DESC = {  # what the cut-off buildings are, for the painter
    ("haven", "dwelling_1"): "a guardhouse: a small fortified stone gatehouse with a tower and blue roof, pikemen's barracks",
    ("haven", "dwelling_2"): "an archers' tower: a tall round stone tower with arrow slits, a blue conical roof and banners",
    ("haven", "dwelling_4"): "a barracks: a long half-timbered and stone hall with a blue slate roof, a training yard with weapon racks",
    ("necropolis", "dwelling_1"): "a cursed temple: a small dark stone temple with a skull over the door and green ghost-light",
    ("necropolis", "dwelling_2"): "a graveyard: crooked gravestones, a rusted iron fence, dead trees and green mist",
    ("necropolis", "dwelling_4"): "a vampire estate: a gothic black manor with pointed towers, red-lit windows and bats",
}

def _edge_ids(fac, layout):
    """Buildings cut off by the screen edge so badly that their card would be a sliver (decided by eye)."""
    return [sid for sid in ("dwelling_1", "dwelling_4") if sid in layout]

def crop_for(rect, aspect=CARD[0] / CARD[1]):
    x, y, w, h = rect
    cw = max(w * 1.25, h * 1.15 * aspect, 260)
    ch = cw / aspect
    if ch > VIEW_H:  # very wide buildings (citadel): the view is not tall enough, crop narrower
        ch, cw = VIEW_H, VIEW_H * aspect
    cx, cy = x + w / 2, y + h * 0.55
    x0 = min(max(0, cx - cw / 2), PAD_W - cw)
    y0 = min(max(0, cy - ch / 2), VIEW_H - ch)
    return (int(x0), int(y0), int(x0 + cw), int(y0 + ch))

def cards():
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for fac in ("haven", "necropolis"):
        layout = json.load(open(f"assets/town/layout_{fac}.json"))
        edge = _edge_ids(fac, layout)
        for sid, rect in layout.items():
            dst = f"{OUT}/building_{fac}_{sid}.png"
            if sid in edge and os.path.exists(f"{BATCH}/out/card__{fac}__{sid}.png"):
                continue  # repainted whole by ingest_edge
            view = town_view(fac, [sid]).convert("RGB")
            view.crop(crop_for(rect)).resize(CARD, Image.LANCZOS).save(dst)
            n += 1
    print(n, "cards; edge buildings:", {f: _edge_ids(f, json.load(open(f"assets/town/layout_{f}.json"))) for f in ("haven", "necropolis")})

def prep_edge():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    for fac in ("haven", "necropolis"):
        layout = json.load(open(f"assets/town/layout_{fac}.json"))
        for sid in _edge_ids(fac, layout):
            x, y, w, h = layout[sid]
            view = town_view(fac, [sid]).convert("RGB")
            # 16:10 window around the building, pushed against the edge it's cut by
            cw, ch = 760, 475
            x0 = 0 if x <= 2 else PAD_W - cw
            y0 = min(max(0, y + h - ch + 40), VIEW_H - ch)
            view.crop((x0, y0, x0 + cw, y0 + ch)).save(f"{BATCH}/in/card__{fac}__{sid}.png")
    print("edge refs in", BATCH)

def ingest_edge():
    for f in sorted(os.listdir(f"{BATCH}/out")):
        if f.startswith("card__") and f.endswith(".png"):
            _, fac, sid = f[:-4].split("__")
            Image.open(f"{BATCH}/out/{f}").convert("RGB").resize(CARD, Image.LANCZOS).save(f"{OUT}/building_{fac}_{sid}.png")
            print("  card", fac, sid)

if __name__ == "__main__":
    {"prep-edge": prep_edge, "ingest-edge": ingest_edge}.get(sys.argv[1] if len(sys.argv) > 1 else "", cards)()
