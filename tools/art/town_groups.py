"""Batch 2 of the town paint-over: buildings in groups that don't overlap, so every building gets painted in full.
python tools/art/town_groups.py   ->  imagegen/batch2/in/group_<faction>_<k>.png + groups.json

In batch 1 the full-town paintings hid parts of the back buildings (the fort walls) behind the front ones; those
parts kept their unpainted pixels and show whenever the front buildings aren't built yet. Here the sprites are
split into groups whose outlines don't touch (greedy graph colouring), each group is drawn alone on the background
and painted, and imagegen_ingest.py cuts every building out of its group image whole."""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from imagegen_prep import town_view, pad, VIEW_H, PAD_W

OUT = "imagegen/batch2/in"

def masks(fac):
    layout = json.load(open(f"assets/town/layout_{fac}.json"))
    m = {}
    for sid, (x, y, w, h) in layout.items():
        a = np.asarray(Image.open(f"assets/town/{fac}_{sid}.png").convert("RGBA").resize((w, h)))[..., 3] > 128
        c = np.zeros((VIEW_H, PAD_W), bool)
        c[y:y + h, x:x + w] = a[:VIEW_H - y, :PAD_W - x]
        m[sid] = c
    return m

def groups(fac):
    m = masks(fac)
    # touching outlines count as overlap (a 12 px margin, so the painter can't blend neighbours together)
    k = 12
    grown = {}
    for sid, c in m.items():
        g = c.copy()
        for d in range(1, k + 1, 3):
            g[d:] |= c[:-d]; g[:-d] |= c[d:]; g[:, d:] |= c[:, :-d]; g[:, :-d] |= c[:, d:]
        grown[sid] = g
    out = []
    for sid in sorted(m, key=lambda s: -m[s].sum()):
        for grp in out:
            if not any((grown[sid] & m[o]).sum() > 0 for o in grp):
                grp.append(sid); break
        else:
            out.append([sid])
    return out

def main():
    os.makedirs(OUT, exist_ok=True)
    info = {}
    for fac in ("haven", "necropolis"):
        for k, grp in enumerate(groups(fac)):
            name = f"group_{fac}_{k}"
            pad(town_view(fac, grp)).save(f"{OUT}/{name}.png")
            info[name] = grp
            print(name, grp)
    json.dump(info, open(f"{OUT}/groups.json", "w"), indent=1)

if __name__ == "__main__":
    main()
