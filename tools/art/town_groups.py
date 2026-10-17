"""Batch 2 of the town paint-over: buildings in groups that don't overlap, so every building gets painted in full.
python tools/art/town_groups.py   ->  imagegen/batch2/in/group_<faction>_<k>.png + groups.json

In batch 1 the full-town paintings hid parts of the back buildings (the fort walls) behind the front ones; those
parts kept their unpainted pixels and show whenever the front buildings aren't built yet. Here the sprites are
split into groups whose outlines don't touch (greedy graph colouring), each group is drawn alone on the background
and painted, and imagegen_ingest.py cuts every building out of its group image whole."""
import os, sys, json, argparse
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from imagegen_prep import town_view, pad, VIEW_H, PAD_W

OUT = "imagegen/batch2/in"

# What each building is, for the painter (the renders are simple blockouts); written into notes.json per image.
DESC = {
    "necropolis": {
        "village_hall": "a small gothic chapel of dark stone with a steep slate roof and a pointed-arch door",
        "town_hall": "a gothic church of black stone with a tall spired bell tower in front and green-lit lancet windows",
        "city_hall": "a great gothic cathedral of black stone: twin towers with needle spires, a glowing green rose "
                     "window with a skull in it, a pointed-arch portal",
        "fort": "the fortress wall of black stone running along the top of the crag: round towers with needle spires and "
                "a skull gate in the middle (a great skull over a pointed arch, bone tusks beside it)",
        "citadel": "the fortress wall of black stone along the crag with needle-spired towers and the skull gate, and a tall "
                   "black keep with needle spires rising behind the gate",
        "tavern": "a crooked, leaning two-storey inn of dark stone and grey plaster, a slate roof, a leaning chimney with a "
                  "green flame, warm lit windows and a hanging sign",
        "marketplace": "a black market under a low stone arcade with a slate roof: coffins, crates, an iron cage and a "
                       "green lantern",
        "mage_guild_1": "a twisting black stone mage tower of square tiers that turn as they rise, green-lit windows, a "
                        "floating green flame with orbiting stones at the top",
        "mage_guild_2": "a tall twisting black stone mage tower of square tiers that turn as they rise, green-lit windows, "
                        "a floating green flame with orbiting stones at the top",
        "blacksmith": "a squat stone crypt-forge with a heavy slate roof, a leaning chimney breathing green fire, a glowing "
                      "forge mouth, an anvil and a rack of spears",
        "dwelling_1": "the Cursed Temple: a small dark stone temple on stepped foundations with a pyramid roof, a skull "
                      "above the door and two green-flame braziers",
        "dwelling_2": "the Graveyard: crooked gravestones, an iron spike fence, a small stone crypt and a dead tree",
        "dwelling_3": "the Tomb of Souls: a stepped stone pyramid tomb with a pale blue glowing doorway and floating "
                      "ghost lights",
        "dwelling_4": "the Estate: a gothic vampire manor of black stone with spired towers and red-lit windows behind "
                      "an iron fence",
        "dwelling_5": "the Mausoleum: a pale stone mausoleum with a columned porch, a stepped roof under an obelisk and "
                      "two obelisks topped with green flames",
        "dwelling_6": "the Hall of Darkness: a long black hall with three needle-spired towers, black banners and "
                      "violet-lit windows",
        "dwelling_7": "the Dragon Vault: a black rock crag whose cave entrance is a giant dragon skull with glowing green "
                      "eyes, horns and fangs, a great bone ribcage arching over the rock",
    },
}

def note(fac, ids):
    """What the buildings in an image are, left to right, for the ids that have a description."""
    d = DESC.get(fac, {})
    layout = json.load(open(f"assets/town/layout_{fac}.json"))
    parts = []
    for sid in sorted([i for i in ids if i in d and i in layout], key=lambda i: layout[i][0]):
        x, y, w, h = layout[sid]
        cx = (x + w / 2) / PAD_W
        where = "left" if cx < 0.36 else ("right" if cx > 0.64 else "centre")
        parts.append(f"- {where}: {d[sid]}")
    if not parts:
        return ""
    return ("The buildings in this picture are simple 3D blockouts; paint each one as described, keeping its outline, "
            "position and size:" + chr(10) + chr(10).join(parts))

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
    ap = argparse.ArgumentParser()
    ap.add_argument("factions", nargs="*", default=["haven", "necropolis"])
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--full", help="also write the backdrop and the full town (the groups' style reference) to this dir")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    info, notes, full_notes = {}, {}, {}
    for fac in a.factions:
        for k, grp in enumerate(groups(fac)):
            name = f"group_{fac}_{k}"
            pad(town_view(fac, grp)).save(f"{a.out}/{name}.png")
            info[name] = grp
            notes[name] = note(fac, grp)
            print(name, grp)
        if a.full:
            from imagegen_prep import VARIANTS
            os.makedirs(a.full, exist_ok=True)
            pad(Image.open(f"assets/town/{fac}_bg.png").convert("RGBA")).save(f"{a.full}/town_{fac}_bg.png")
            pad(town_view(fac, VARIANTS["B"])).save(f"{a.full}/town_{fac}_B.png")
            full_notes[f"town_{fac}_B"] = note(fac, VARIANTS["B"])
    json.dump(info, open(f"{a.out}/groups.json", "w"), indent=1)
    json.dump(notes, open(f"{a.out}/notes.json", "w"), indent=1)
    if a.full:
        json.dump(full_notes, open(f"{a.full}/notes.json", "w"), indent=1)

if __name__ == "__main__":
    main()
