"""Upgraded creatures and dwellings, painted by an image model from the base ones.
python tools/art/upgrade_paint.py prep    ->  imagegen/batch23/in/{upg,uport,udw,ucard}__*.png + upgrades.json
python tools/art/vertex_paint.py --batch imagegen/batch23
python tools/art/upgrade_paint.py ingest  ->  assets/creatures/<uid>.png (+ anchors), creatures/portraits/<uid>.png,
                                              town/<faction>_dwelling_<t>u.png (+ layout), icons/building_*_dwelling_<t>u.png
Then the poses and move cycles of the new creatures come from the usual tools:
python tools/art/pose_paint.py prep <uids> / cycle_paint.py prep <uids>, vertex_paint on batch6 / batch8, ingest, and
python tools/art/sprite_sizes.py.

upg__<uid>   the base idle figure on magenta; the model redraws it as the upgraded creature in the same pose
uport__<uid> the base portrait; repainted as the upgraded creature, same framing
udw__<fac>__<t>   the base dwelling's town sprite on a flat backdrop; repainted grander inside the same silhouette
ucard__<fac>__<t> the base dwelling's building card; repainted with the upgraded building"""
import os, sys, json
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out, drop_specks, shadow, figure, feet, RATIOS, LONG

BATCH = "imagegen/batch23"
D = "assets/creatures"
BG = (148, 140, 124)

# upgraded id -> (base id, what changes)
UPGRADES = {
    "halberdier": ("pikeman", "an elite Halberdier: a veteran with a long halberd (axe blade and spike) instead of the plain pike, "
                   "heavier polished plate with gold trim and a richer red-and-white tabard"),
    "marksman": ("archer", "an elite Marksman: a heavier recurve longbow, a hooded dark-green cloak with gold trim, a studded "
                 "leather brigandine and a full quiver"),
    "royal_griffin": ("griffin", "a Royal Griffin: larger and more majestic, golden-white plumage, a crest of royal blue and gold "
                      "feathers and gilded armour plates on its chest"),
    "crusader": ("swordsman", "an elite Crusader: polished plate armour with gold edging, a white surcoat with a golden sun "
                 "emblem, a plumed great helm and a longer broadsword"),
    "zealot": ("monk", "a Zealot: a battle priest in rich crimson-and-gold robes with a gold-trimmed hood, a golden holy symbol "
               "on the chest and hands glowing with warm holy light"),
    "champion": ("cavalier", "a Champion: a grand cavalry knight in gilded full plate with a tall blue plume and a gold-banded "
                 "lance, the horse in rich royal-blue barding with gold trim and a gold chanfron"),
    "archangel": ("angel", "an Archangel: a mightier angel with larger golden-white wings, ornate golden armour, a sword wreathed "
                  "in flame and a faint golden glow around the head"),
    "skeleton_warrior": ("skeleton", "a Skeleton Warrior: an armoured skeleton with a rusted iron helm, a dented breastplate, a "
                         "round shield and a heavy notched sword, tattered dark-red cloth"),
    "plague_zombie": ("zombie", "a Plague Zombie: bigger, bloated and mutated, sickly green-grey skin, exposed ribs, festering "
                      "sores and broken shackles on its wrists, still in torn medieval rags"),
    "wraith": ("ghost", "a Wraith: darker and more menacing, tattered black-violet robes, a glowing violet face under the hood "
               "and long spectral claws"),
    "vampire_lord": ("vampire", "a Vampire Lord: regal, with a high-collared black-and-crimson cloak with gold clasps, larger "
                     "bat wings and a silver circlet"),
    "arch_lich": ("lich", "an Arch Lich: rich purple-and-black robes with gold embroidery, a bone crown and a staff topped by a "
                  "glowing green skull"),
    "doom_rider": ("dread_knight", "a Doom Rider: a mightier death knight with a horned helm and spiked blackened armour with "
                   "glowing green runes, riding a skeletal horse in black barding with green ghost-fire at its hooves; keep "
                   "it as dark as the original, not bronze or gold"),
    "ghost_dragon": ("bone_dragon", "a Ghost Dragon: the same skeletal dragon made spectral, wrapped in translucent pale "
                     "blue-green ghostly flesh around the bones, glowing cyan eyes and wisps of spectral mist"),
}

DWELLINGS = {  # (faction, tier) -> how the upgraded building looks
    ("haven", 1): "an Upgraded Guardhouse: a taller stone guardhouse with a second storey, gilded trim and blue-and-gold banners",
    ("haven", 2): "an Upgraded Archers' Tower: a taller tower with a crenellated gilded top, arrow slits and blue banners",
    ("haven", 3): "an Upgraded Griffin Tower: a grander tower with a golden roof, a griffin statue and royal banners",
    ("haven", 4): "Upgraded Barracks: a larger stone hall with a gold-trimmed roof, shields on the walls and banners",
    ("haven", 5): "an Upgraded Monastery: a grander monastery with a golden dome, stained-glass windows and a bell tower",
    ("haven", 6): "Upgraded Training Grounds: a grander stable and jousting hall with gilded roofs and pennants",
    ("haven", 7): "an Upgraded Portal of Glory: a radiant golden portal with brighter holy light and more ornate pillars",
    ("necropolis", 1): "an Upgraded Cursed Temple: a larger black temple with green-glowing windows and bone spires",
    ("necropolis", 2): "an Upgraded Graveyard: more crypts and headstones, a bone gate and green ghost-light",
    ("necropolis", 3): "an Upgraded Tomb of Souls: a taller tomb with violet spectral light pouring from its doors",
    ("necropolis", 4): "an Upgraded Estate: a grander dark manor with crimson banners, spires and lit windows",
    ("necropolis", 5): "an Upgraded Mausoleum: a taller mausoleum with a bone crown on its roof and green glowing runes",
    ("necropolis", 6): "an Upgraded Hall of Darkness: a larger black hall with spiked towers and green fire in braziers",
    ("necropolis", 7): "an Upgraded Dragon Vault: a grander vault with huge dragon bones over the entrance and cyan ghost-light",
}

STYLE = ("Hand-painted digital fantasy illustration in the style of classic late-1990s turn-based fantasy strategy games: "
         "rich saturated colours, visible painterly brushwork, warm golden light from the upper left.")

IDLE = ("This is a battle unit sprite from a fantasy strategy game. Redraw it as the UPGRADED, elite version of the same "
        "unit: {desc}. Keep the same species and the same kind of unit, the same side view facing right, the same pose, "
        "the same size in the frame, standing on the same ground line at the same spot, and the same hand-painted style "
        "and lighting. It must read clearly as a stronger, grander version of this unit. Keep the whole character inside "
        "the frame.\nThe background must stay a perfectly flat, pure magenta (#FF00FF) everywhere around the character: "
        "no ground, no cast shadow, no scenery, no effects, no text.")

PORT = ("This is a creature portrait from a fantasy strategy game (the unit portrait shown when recruiting). Repaint it "
        "as the UPGRADED, elite version of the same creature: {desc}. " + STYLE + "\nKeep the same framing, camera angle "
        "and pose, the head in the same place, and the same soft painted background in warm brown and amber colours. "
        "Square image. No text, no border, no frame, no signature.")

BUILDING = ("This is a town building from a fantasy strategy game, seen from a high three-quarter angle. Repaint it as "
            "{desc}. " + STYLE + "\nVERY IMPORTANT: keep the same building with the same outline, silhouette, size and "
            "position in the frame and the same camera angle; show the upgrade through materials, trim, banners, windows "
            "and light inside that silhouette. Keep the background a perfectly plain, flat grey-beige colour exactly like "
            "the original: no ground, cast shadows, scenery, frame or text.")

CARD = ("This is a picture of a single town building for the building screen of a fantasy strategy game. Repaint it as "
        "{desc}. " + STYLE + "\nKeep the same setting, landscape, lighting, camera angle and composition, with the "
        "building in the same place at the same size; show the upgrade through a grander building. No people, no text, "
        "no border.")


def prompt(name):
    kind, rest = name.split("__", 1)
    if kind == "upg":
        return IDLE.format(desc=UPGRADES[rest][1]), json.load(open(f"{BATCH}/in/upgrades.json"))[name]["ratio"]
    if kind == "uport":
        return PORT.format(desc=UPGRADES[rest][1]), "1:1"
    fac, t = rest.split("__")
    desc = DWELLINGS[(fac, int(t))]
    if kind == "udw":
        return BUILDING.format(desc=desc), json.load(open(f"{BATCH}/in/upgrades.json"))[name]["ratio"]
    return CARD.format(desc=desc), "16:9"


def _ratio(w, h):
    return min(RATIOS, key=lambda k: abs(np.log(RATIOS[k] / (w / h))))


def prep(only=None):
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    pj = f"{BATCH}/in/upgrades.json"
    info = json.load(open(pj)) if os.path.exists(pj) else {}
    for uid, (base, _) in UPGRADES.items():
        if only and uid not in only:
            continue
        # idle: the base figure on magenta with room around it (upgrades may be a little bigger)
        im, fig, (x0, y0, x1, y1) = figure(base)
        fw, fh = x1 - x0, y1 - y0
        cx0, cx1 = x0 - fw * 0.25, x1 + fw * 0.25
        cy0, cy1 = y0 - fh * 0.2, y1 + fh * 0.06
        w, h = cx1 - cx0, cy1 - cy0
        r = _ratio(w, h)
        if w / h > RATIOS[r]:
            h2 = w / RATIOS[r]; cy0 -= (h2 - h); h = h2
        else:
            w2 = h * RATIOS[r]; cx0 -= (w2 - w) / 2; w = w2
        s = LONG / max(w, h)
        canvas = Image.new("RGBA", (int(round(w * s)), int(round(h * s))), (255, 0, 255, 255))
        big = fig.resize((int(round(fig.width * s)), int(round(fig.height * s))), Image.LANCZOS)
        canvas.alpha_composite(big, (int(round(-cx0 * s)), int(round(-cy0 * s))))
        canvas.convert("RGB").save(f"{BATCH}/in/upg__{uid}.png")
        info[f"upg__{uid}"] = {"uid": uid, "base": base, "origin": [cx0, cy0], "scale": s, "ratio": r}
        # portrait
        Image.open(f"{D}/portraits/{base}.png").convert("RGB").resize((1024, 1024), Image.LANCZOS).save(f"{BATCH}/in/uport__{uid}.png")
    for (fac, t) in DWELLINGS:
        if only and f"{fac}{t}" not in only and "dwellings" not in only:
            continue
        sp = Image.open(f"assets/town/{fac}_dwelling_{t}.png").convert("RGBA")
        bb = sp.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
        crop = sp.crop(bb)
        r = _ratio(crop.width * 1.15, crop.height * 1.15)
        w, h = crop.width * 1.15, crop.height * 1.15
        if w / h > RATIOS[r]:
            h = w / RATIOS[r]
        else:
            w = h * RATIOS[r]
        s = LONG / max(w, h)
        W, H = int(round(w * s)), int(round(h * s))
        canvas = Image.new("RGBA", (W, H), BG + (255,))
        big = crop.resize((int(round(crop.width * s)), int(round(crop.height * s))), Image.LANCZOS)
        ox, oy = (W - big.width) // 2, (H - big.height) // 2
        canvas.alpha_composite(big, (ox, oy))
        name = f"udw__{fac}__{t}"
        canvas.convert("RGB").save(f"{BATCH}/in/{name}.png")
        info[name] = {"fac": fac, "tier": t, "bbox": list(bb), "box": [ox, oy, big.width, big.height], "ratio": r}
        Image.open(f"assets/icons/building_{fac}_dwelling_{t}.png").convert("RGB").resize((1376, 860), Image.LANCZOS).save(
            f"{BATCH}/in/ucard__{fac}__{t}.png")
    json.dump(info, open(pj, "w"), indent=1)
    print(len(info), "references")


def _out(name):
    return next((f"{BATCH}/out/{name}.{e}" for e in ("png", "jpg", "webp") if os.path.exists(f"{BATCH}/out/{name}.{e}")), None)


def ingest():
    info = json.load(open(f"{BATCH}/in/upgrades.json"))
    anchors = json.load(open(f"{D}/anchors.json"))
    for name, d in info.items():
        src = _out(name)
        if name.startswith("upg__") and src:
            uid, base, s = d["uid"], d["base"], d["scale"]
            ref = Image.open(f"{BATCH}/in/{name}.png")
            cut = key_out(Image.open(src).convert("RGB").resize(ref.size, Image.LANCZOS))
            cut = cut.resize((max(1, int(round(cut.width / s))), max(1, int(round(cut.height / s)))), Image.LANCZOS)
            cut = drop_specks(cut)
            ca = np.asarray(cut)[..., 3]
            if (ca > 128).sum() < 50:
                print(f"  {name}: nothing left after keying"); continue
            im, fig, _ = figure(base)
            # an upgrade may be a little grander, never smaller or much bigger than the base figure
            f = float(np.clip(np.sqrt((np.asarray(fig)[..., 3] > 128).sum() * 1.08 / (ca > 128).sum()), 0.8, 1.15))
            if abs(f - 1) > 0.02:
                cut = cut.resize((max(1, int(round(cut.width * f))), max(1, int(round(cut.height * f)))), Image.LANCZOS)
                ca = np.asarray(cut)[..., 3]
            px, py = feet(ca)
            ys, xs = np.nonzero(ca > 20)
            x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
            fig_rgba = cut.crop((x0, y0, x1, y1))
            fx, fy = px - x0, py - y0
            pad = 12
            sh_w = int((y1 - y0) * 0.55 * 0.32) + 30
            W, H = int(fig_rgba.width + 2 * pad + sh_w), int(fig_rgba.height + 2 * pad + 10)
            fa = np.zeros((H, W), np.uint8)
            fa[pad:pad + fig_rgba.height, pad:pad + fig_rgba.width] = np.asarray(fig_rgba)[..., 3]
            sha = shadow(fa, pad + fx, pad + fy)
            out = Image.fromarray(np.dstack([np.zeros((H, W, 3), np.uint8) + np.array([12, 10, 8], np.uint8),
                                             (sha * 255).astype(np.uint8)]), "RGBA")
            out.alpha_composite(fig_rgba, (pad, pad))
            out.save(f"{D}/{uid}.png")
            anchors[f"{uid}.png"] = [round((pad + fx) / W, 4), round((pad + fy) / H, 4)]
            print(f"  {uid}: {W}x{H}")
            ps = _out(f"uport__{uid}")
            if ps:
                Image.open(ps).convert("RGB").resize((256, 256), Image.LANCZOS).save(f"{D}/portraits/{uid}.png")
        elif name.startswith("udw__") and src:
            fac, t = d["fac"], d["tier"]
            base = Image.open(f"assets/town/{fac}_dwelling_{t}.png").convert("RGBA")
            ref = Image.open(f"{BATCH}/in/{name}.png")
            painted = Image.open(src).convert("RGB").resize(ref.size, Image.LANCZOS)
            ox, oy, bw, bh = d["box"]
            x0, y0, x1, y1 = d["bbox"]
            part = painted.crop((ox, oy, ox + bw, oy + bh)).resize((x1 - x0, y1 - y0), Image.LANCZOS)
            out = base.copy()
            # painted colour inside the original silhouette; the soft edge keeps the original pixels
            a = np.asarray(base)[y0:y1, x0:x1].astype(np.float32)
            p = np.asarray(part).astype(np.float32)
            k = np.clip((a[..., 3:4] - 120) / 100, 0, 1)
            a[..., :3] = a[..., :3] * (1 - k) + p * k
            out.paste(Image.fromarray(a.astype(np.uint8), "RGBA"), (x0, y0))
            out.save(f"assets/town/{fac}_dwelling_{t}u.png")
            lay_p = f"assets/town/layout_{fac}.json"
            lay = json.load(open(lay_p))
            if f"dwelling_{t}" in lay:
                lay[f"dwelling_{t}u"] = lay[f"dwelling_{t}"]
                json.dump(lay, open(lay_p, "w"), indent=0)
            cs = _out(f"ucard__{fac}__{t}")
            if cs:
                sz = Image.open(f"assets/icons/building_{fac}_dwelling_{t}.png").size
                Image.open(cs).convert("RGB").resize(sz, Image.LANCZOS).save(f"assets/icons/building_{fac}_dwelling_{t}u.png")
            print(f"  {fac} dwelling {t} upgraded")
    json.dump(anchors, open(f"{D}/anchors.json", "w"), indent=0, sort_keys=True)


if __name__ == "__main__":
    if sys.argv[1] == "prep":
        prep(sys.argv[2:] or None)
    else:
        ingest()
