"""Necropolis town screen: its own site, not Haven's plaza re-tinted. A dead town on a moor below a black crag:
the fortress walls run along the crag with a skull gate, a flagstone way climbs to it past a gothic hall, the
dwellings are tombs, crypts and a dragon's lair. Same camera and output as townscreen.render_town.
Requires studio.py, figures.py, buildings.py, props.py, battlefield.py, townscreen.py."""

NECRO_SLOTS = {
    "fort": (0, 20.5), "hall": (-3.6, 6.5), "mage_guild": (10.5, 11.0), "tavern": (13.5, 3.0),
    "marketplace": (3.5, -3.5), "blacksmith": (8.0, -1.5), "dwelling_1": (-9.5, -1.0), "dwelling_2": (-3.8, -3.8),
    "dwelling_3": (-14.5, 2.0), "dwelling_4": (15.5, 18.2), "dwelling_5": (4.5, 7.0), "dwelling_6": (-12.0, 18.8),
    "dwelling_7": (-17.0, 19.8),
}
ON_CRAG = ("dwelling_4", "dwelling_6", "dwelling_7")  # the estate, the dark hall and the vault stand up on the crag
RIDGE_Z = 2.2  # height of the crag the fortress stands on
GREEN = (0.35, 1.0, 0.45)
PURPLE = (0.3, 0.05, 0.35)

def _st():
    m = mats()
    return {"wall": m["nwall"], "roof": m["nroof"], "stone": m["stone"], "rock": m["rock"],
            "dark": flat_material("gate_dark", (0.03, 0.025, 0.02), 0.9), "bone": M("bone"), "iron": M("darksteel")}

def needle(x, y, z, r, h, mat, verts=8, rot=0.0):
    return prim("cone", (x, y, z + h / 2), (1, 1, 1), mat=mat, vertices=verts, radius1=r, radius2=0.0, depth=h,
                rot=(0, 0, rot))

def lancet(x, y, z, w, h, mat):
    """Pointed-arch opening on a south face: a slab with a diamond on top."""
    d = box((x, y, z + h * 0.78), (w * 0.71, 0.06, w * 0.71), mat)
    d.rotation_euler = (0, math.radians(45), 0)
    return [box((x, y, z + h * 0.39), (w, 0.06, h * 0.78), mat), d]

def gothic_tower(x, y, w, h, spire_h, wall_m, roof_m, flag=None):
    out = [box((x, y, h / 2), (w, w, h), wall_m)]
    out.append(needle(x, y, h, w * 0.78, spire_h, roof_m, 4, math.radians(45)))
    for dx in (-1, 1):  # corner pinnacles
        for dy in (-1, 1):
            out.append(needle(x + dx * w * 0.45, y + dy * w * 0.45, h, w * 0.12, spire_h * 0.3, roof_m, 4))
    if flag:
        out += banner(x, y, h + spire_h, flag)
    return out

def skull(x, y, z, s, eye=GREEN):
    """A skull facing the camera (-y)."""
    out = [ball((x, y, z), 0.5 * s, M("bone"), 1.0, 0.9, 1.0),
           ball((x, y - 0.15 * s, z - 0.4 * s), 0.3 * s, M("bone"), 1.15, 0.9, 0.6)]
    out += [ball((x + dx * s, y - 0.4 * s, z + 0.03 * s), 0.12 * s, M("glow", eye)) for dx in (-0.18, 0.18)]
    return out

def gravestone(x, y, s=1.0, tilt=0.0, mat=None):
    mat = mat or mats()["stone"]
    g = box((x, y, 0.32 * s), (0.42 * s, 0.14 * s, 0.64 * s), mat)
    top = prim("cyl", (x, y, 0.64 * s), (0.21 * s, 0.21 * s, 0.07 * s), mat=mat, vertices=16, bake=True,
               rot=(math.radians(90), 0, 0))
    for o in (g, top):
        o.rotation_euler = (math.radians(90) if o is top else 0, tilt, 0)
    return [g, top]

def brazier(x, y, h=1.0, s=1.0):
    st = _st()
    return [box((x, y, h / 2), (0.36 * s, 0.36 * s, h), st["stone"]),
            prim("cyl", (x, y, h + 0.08), (0.3 * s, 0.3 * s, 0.1), mat=st["iron"], vertices=12, bake=True),
            ball((x, y, h + 0.3 * s), 0.22 * s, M("glow", GREEN), 1.0, 1.0, 1.5)]

def rib(x, y0, y1, h, r, mat, lean=0.0):
    """A curved bone rib from the ground at x up and over, as three straight segments."""
    pts = [(x, y0, 0), (x * 0.9 + lean, (y0 * 2 + y1) / 3, h * 0.75), (x * 0.55 + lean, (y0 + y1 * 2) / 3, h),
           (x * 0.2 + lean, y1, h * 0.92)]
    return [rod(a, b, r * (1 - k * 0.22), mat, r * (1 - (k + 1) * 0.22)) for k, (a, b) in enumerate(zip(pts, pts[1:]))]

# ---------------------------------------------------------------------------------------------
# Buildings (local coords: x east, y north, origin at ground centre)
# ---------------------------------------------------------------------------------------------
def n_fort(citadel):
    st = _st()
    W, R = st["wall"], st["roof"]
    h = 3.6 if citadel else 2.8
    out = []
    # a jagged curtain wall following the crag edge, broken at the gate
    pts = [(-22, -0.8), (-15.5, 0.9), (-9, -0.5), (-3.4, 0.0), (3.4, 0.0), (9.5, -0.7), (16, 0.8), (22, -1.0)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x0 == -3.4:
            continue
        out += wall(x0, y0, x1, y1, h, W, 0.9)
    for k, (x, y) in enumerate(pts):
        if abs(x) == 3.4:
            continue
        th = h + 1.3 + (k % 3) * 0.8
        out += round_tower(x, y, 0.9, th, W, R, 3.6, spire=True, flag=PURPLE if k in (2, 5) else None)
    # the skull gate: two square gate towers, a dark pointed arch, a great skull over it and bone tusks
    gh = h + 1.8
    for x in (-3.4, 3.4):
        out += gothic_tower(x, 0, 2.0, gh + 1.2, 4.2, W, R, PURPLE)
    out.append(box((0, 0, gh / 2), (4.8, 1.2, gh), W))
    out += merlons(-2.4, -0.55, 2.4, -0.55, gh, 0.2, W, 0.5)
    out += lancet(0, -0.62, 0, 2.0, gh * 0.72, st["dark"])
    out += skull(0, -0.75, gh * 0.86, 1.5)
    for x in (-1, 1):
        out.append(rod((x * 2.2, -1.0, 0), (x * 1.3, -1.6, gh * 0.55), 0.2, st["bone"], 0.05))
    if citadel:
        # a black keep with needle spires rising behind the gate, and a lone tower on the left
        kx = 0.0
        out.append(box((kx, 3.2, 3.6), (4.0, 3.6, 7.2), W))
        out.append(needle(kx, 3.2, 7.2, 2.3, 4.6, R, 4, math.radians(45)))
        for dx in (-1, 1):
            for dy in (-1, 1):
                out += round_tower(kx + dx * 2.0, 3.2 + dy * 1.8, 0.55, 8.0, W, R, 2.8, spire=True)
        for z in (2.6, 4.8):
            out += lancet(kx, 1.37, z, 0.45, 1.2, M("glow", GREEN))
    for o in out:
        o.location.z += RIDGE_Z
    return out

def n_hall(level):
    st = _st()
    W, R = st["wall"], st["roof"]
    G = M("glow", GREEN)
    out = []
    if level == 1:  # a chapel with a steep gable facing the town
        out.append(box((0, 0.4, 1.3), (2.4, 3.4, 2.6), st["stone"]))
        out.append(prism_roof(0, 0.4, 3.4, 2.4, 2.6, 2.2, R, math.radians(90)))
        out += lancet(0, -1.32, 0, 0.8, 1.7, st["dark"])
        out += lancet(0, -1.32, 2.1, 0.35, 0.8, G)
        out.append(needle(0, -0.9, 4.6, 0.25, 1.4, R, 4))
    elif level == 2:  # a church with a spired bell tower in front
        out.append(box((0, 0.8, 1.7), (3.2, 4.2, 3.4), W))
        out.append(prism_roof(0, 0.8, 4.2, 3.2, 3.4, 2.6, R, math.radians(90)))
        out += gothic_tower(0, -1.7, 1.5, 4.8, 3.4, W, R, PURPLE)
        out += lancet(0, -2.47, 0, 0.8, 1.9, st["dark"])
        for z in (2.4, 3.7):
            out += lancet(0, -2.47, z, 0.35, 0.8, G)
        for x in (-1.0, 1.0):
            out += lancet(x, -1.22, 1.0, 0.35, 1.3, G)
    else:  # a cathedral: twin spired towers, a skull rose window, pinnacles along the nave
        out.append(box((0, 1.2, 1.9), (4.0, 5.0, 3.8), W))
        out.append(prism_roof(0, 1.2, 5.0, 4.0, 3.8, 2.4, R, math.radians(90)))
        for x in (-2.3, 2.3):
            out += gothic_tower(x, -1.7, 1.6, 5.4, 3.6, W, R, PURPLE)
            for z in (1.8, 3.6):
                out += lancet(x, -2.57, z, 0.35, 0.9, G)
        out.append(box((0, -1.55, 2.5), (3.0, 0.4, 5.0), W))  # west front between the towers
        rose = prim("cyl", (0, -1.78, 3.7), (0.7, 0.7, 0.03), mat=G, vertices=24, bake=True, rot=(math.radians(90), 0, 0))
        out.append(rose)
        out += skull(0, -1.95, 3.7, 0.85)
        out += lancet(0, -1.78, 0, 1.2, 2.3, st["dark"])
        for k in range(4):
            y = -0.6 + k * 1.3
            for x in (-2.1, 2.1):
                out.append(needle(x, y, 3.8, 0.16, 1.3, R, 4))
        for k in range(3):
            out += [box((0, -2.4 - k * 0.35, 0.1 + k * 0.1), (2.6 - k * 0.3, 0.35, 0.2 + k * 0.2), st["stone"])]
    return out

def n_guild(level):
    """A twisting black needle of stacked square tiers, a green flame floating at the top."""
    st = _st()
    tiers = 3 if level == 1 else 4
    out = []
    z, r = 0.0, 1.35
    for t in range(tiers):
        hh = 1.4
        rot = math.radians(45 + 18 * t)
        out.append(prim("cyl", (0, 0, z + hh / 2), (r, r, hh / 2), mat=st["wall"], vertices=4, bake=True, rot=(0, 0, rot)))
        out.append(prim("cyl", (0, 0, z + hh + 0.06), (r * 1.15, r * 1.15, 0.08), mat=st["stone"], vertices=4, bake=True,
                        rot=(0, 0, rot)))
        out.append(box((0, -r * 0.72, z + hh * 0.5), (0.22, 0.05, 0.6), M("glow", GREEN)))
        z += hh + 0.12
        r *= 0.8
    out.append(needle(0, 0, z, r * 1.25, 2.6, st["roof"], 4, math.radians(45 + 18 * tiers)))
    out.append(ball((0, 0, z + 3.4), 0.35, M("glow", GREEN), 1.0, 1.0, 1.4))
    for k in range(3):  # floating stones circling the flame
        a = k * 2.1
        out.append(ball((math.cos(a) * 1.0, math.sin(a) * 1.0, z + 3.0 + k * 0.25), 0.18, st["rock"], 1.2, 1.0, 0.8))
    return out

def n_tavern():
    """A crooked, top-heavy inn: jettied upper floors, a leaning chimney and a lantern sign."""
    st = _st()
    W = st["stone"]; P = mats()["plaster"]
    out = [box((0, 0, 1.0), (3.0, 2.4, 2.0), W),
           box((0.2, 0.0, 2.7), (3.4, 2.7, 1.4), P, math.radians(4))]
    out.append(prism_roof(0.2, 0.0, 3.4, 2.7, 3.4, 1.9, st["roof"], math.radians(4)))
    out.append(rod((-1.0, 0.6, 3.0), (-1.3, 0.6, 5.6), 0.26, W, 0.2))
    out.append(ball((-1.32, 0.6, 5.7), 0.22, M("glow", GREEN), 1.0, 1.0, 0.6))
    for x in (-0.8, 0.8):
        out.append(box((x, -1.22, 0.9), (0.45, 0.05, 0.6), M("glow", (1.0, 0.65, 0.3))))
        out.append(box((x + 0.15, -1.38, 2.7), (0.4, 0.05, 0.5), M("glow", (1.0, 0.65, 0.3))))
    out += lancet(0, -1.22, 0, 0.7, 1.5, st["dark"])
    out.append(rod((1.6, -1.3, 0), (1.6, -1.3, 2.4), 0.06, M("wood")))
    out.append(rod((1.6, -1.3, 2.3), (2.4, -1.3, 2.3), 0.05, st["iron"]))
    out.append(box((2.2, -1.3, 1.95), (0.55, 0.06, 0.45), M("wood")))
    out.append(ball((2.4, -1.3, 2.05), 0.12, M("glow", GREEN)))
    for k in range(3):
        out.append(prim("cyl", (-1.3 + k * 0.55, -1.75, 0.35), (0.25, 0.25, 0.35), mat=M("wood"), vertices=14, bake=True))
    return out

def n_market():
    """A black market under a stone arcade: pointed arches, coffins, cages and a lantern."""
    st = _st()
    W, R = st["stone"], st["roof"]
    out = []
    for x in (-1.8, 0.0, 1.8):
        for y in (-0.9, 0.9):
            out.append(box((x, y, 0.95), (0.3, 0.3, 1.9), W))
    out.append(box((0, 0, 2.0), (4.2, 2.3, 0.25), W))
    out.append(prism_roof(0, 0, 4.2, 2.3, 2.12, 0.9, R))
    out.append(box((-0.9, -0.2, 0.25), (1.5, 0.6, 0.5), M("wood"), math.radians(8)))  # coffins
    out.append(box((0.9, 0.2, 0.25), (1.5, 0.6, 0.5), M("wood"), math.radians(-5)))
    out.append(box((0.9, -0.4, 0.62), (1.4, 0.55, 0.25), M("wood"), math.radians(-5)))
    cage = [rod((2.9 + dx, -0.8 + dy, 0), (2.9 + dx, -0.8 + dy, 1.0), 0.03, st["iron"]) for dx in (-0.3, 0.3) for dy in (-0.3, 0.3)]
    out += cage + [box((2.9, -0.8, 1.02), (0.7, 0.7, 0.06), st["iron"])]
    out.append(box((-2.9, -0.6, 0.45), (0.9, 0.7, 0.9), M("wood"), math.radians(20)))
    out.append(rod((0, -1.0, 1.9), (0, -1.0, 1.55), 0.02, st["iron"]))
    out.append(ball((0, -1.0, 1.45), 0.13, M("glow", GREEN)))
    return out

def n_smith():
    """A squat crypt-forge with a heavy roof, a leaning chimney breathing green fire, anvil and spiked rack."""
    st = _st()
    out = [box((0, 0.3, 1.0), (3.0, 2.2, 2.0), st["stone"])]
    pyr = needle(0, 0.3, 2.0, 2.3, 1.6, st["roof"], 4, math.radians(45))
    pyr.scale = (1.0, 0.75, 1.0)
    out.append(pyr)
    out.append(rod((0.9, 0.8, 1.5), (1.2, 0.9, 4.6), 0.38, st["stone"], 0.3))
    out.append(ball((1.22, 0.9, 4.75), 0.32, M("glow", GREEN), 1.0, 1.0, 1.6))
    out += lancet(-0.5, -0.82, 0, 1.0, 1.4, M("glow", (0.9, 0.45, 0.1)))
    out.append(box((0.9, -1.6, 0.3), (0.5, 0.3, 0.6), st["iron"]))
    out.append(box((0.9, -1.6, 0.65), (0.8, 0.35, 0.15), st["iron"]))
    out.append(rod((-1.9, -1.2, 0), (-1.9, -1.2, 1.3), 0.05, M("wood")))
    out.append(rod((-1.1, -1.2, 0), (-1.1, -1.2, 1.3), 0.05, M("wood")))
    out.append(rod((-1.9, -1.2, 1.1), (-1.1, -1.2, 1.1), 0.04, M("wood")))
    out += [rod((-1.8 + k * 0.17, -1.25, 0.2), (-1.8 + k * 0.17, -1.25, 1.55), 0.025, M("steel")) for k in range(5)]
    return out

def n_dwelling(tier):
    st = _st()
    W, R, S = st["wall"], st["roof"], st["stone"]
    G = M("glow", GREEN)
    out = []
    if tier == 1:  # Cursed Temple: stepped base, steep pyramid roof, skull over the door, green braziers
        for k in range(3):
            out.append(box((0, 0, 0.12 + k * 0.24), (3.2 - k * 0.3, 3.0 - k * 0.3, 0.24), S))
        out.append(box((0, 0, 1.6), (2.2, 2.2, 1.8), W))
        out.append(needle(0, 0, 2.5, 1.9, 1.8, R, 4, math.radians(45)))
        out += lancet(0, -1.12, 0.7, 0.8, 1.4, st["dark"])
        out += skull(0, -1.2, 2.3, 0.55)
        out += brazier(-1.25, -1.45, 0.9, 0.8) + brazier(1.25, -1.45, 0.9, 0.8)
    elif tier == 2:  # Graveyard: rows of crooked stones, an iron fence, a crypt arch and a dead tree
        rng = random.Random(21)
        for k in range(9):
            x = -2.0 + (k % 5) * 1.0 + (0.5 if k >= 5 else 0)
            y = -0.5 + (k // 5) * 1.1
            out += gravestone(x, y, rng.uniform(0.8, 1.2), rng.uniform(-0.25, 0.25))
        for x in (-2.8, -1.4, 0, 1.4, 2.8):
            out.append(rod((x, -1.5, 0), (x, -1.5, 1.0), 0.04, st["iron"]))
            out.append(needle(x, -1.5, 1.0, 0.07, 0.25, st["iron"], 4))
        out.append(rod((-2.8, -1.5, 0.85), (2.8, -1.5, 0.85), 0.03, st["iron"]))
        out.append(rod((-2.8, -1.5, 0.35), (2.8, -1.5, 0.35), 0.03, st["iron"]))
        out.append(box((2.6, 1.4, 1.0), (1.6, 1.4, 2.0), S))
        out.append(prism_roof(2.6, 1.4, 1.6, 1.4, 2.0, 0.9, R))
        out += lancet(2.6, 0.68, 0, 0.6, 1.4, st["dark"])
        out += at(tree_dead(7), -2.6, 1.6)
    elif tier == 3:  # Tomb of Souls: a stepped stone pyramid, a pale glowing doorway, ghost lights
        for k in range(3):
            s = 3.0 - k * 0.8
            out.append(box((0, 0, 0.4 + k * 0.8), (s, s, 0.8), S))
        out.append(needle(0, 0, 2.4, 0.6, 1.1, R, 4, math.radians(45)))
        out += lancet(0, -1.52, 0, 0.8, 1.5, M("glow", (0.6, 0.9, 1.0)))
        out += [ball((x, -1.9, z), 0.28, M("ghost", (0.55, 0.85, 1.0))) for x, z in ((-1.1, 1.6), (1.2, 2.1), (0.3, 3.0))]
    elif tier == 4:  # Estate: a gothic manor with spired corner towers and red windows behind an iron gate
        out.append(box((0, 0.3, 1.6), (4.2, 2.6, 3.2), W))
        out.append(prism_roof(0, 0.3, 4.2, 2.6, 3.2, 2.0, R))
        out += gothic_tower(0, -1.2, 1.2, 4.4, 3.2, W, R)
        for x in (-2.3, 2.3):
            out += round_tower(x, -0.9, 0.6, 4.6, W, R, 2.8, spire=True)
        for x in (-1.3, 1.3):
            for z in (0.8, 2.1):
                out += lancet(x, -1.02, z, 0.35, 0.8, M("glow", (0.9, 0.15, 0.12)))
        out += lancet(0, -1.82, 0, 0.6, 1.4, st["dark"])
        for x in (-2.8, -1.4, 1.4, 2.8):
            out.append(rod((x, -2.4, 0), (x, -2.4, 1.2), 0.05, st["iron"]))
        out.append(rod((-2.8, -2.4, 1.0), (2.8, -2.4, 1.0), 0.03, st["iron"]))
    elif tier == 5:  # Mausoleum: a columned porch, a stepped roof under an obelisk, green-flame obelisks
        out.append(box((0, 0, 0.2), (3.8, 3.4, 0.4), S))
        out.append(box((0, 0.4, 1.7), (3.0, 2.4, 2.6), S))
        for x in (-1.2, -0.4, 0.4, 1.2):
            out.append(rod((x, -1.25, 0.4), (x, -1.25, 2.9), 0.16, S))
        out.append(box((0, -1.05, 3.05), (3.2, 0.9, 0.3), S))
        for k in range(3):
            out.append(box((0, 0.1, 3.3 + k * 0.3), (3.0 - k * 0.7, 2.8 - k * 0.6, 0.3), W))
        out.append(needle(0, 0.1, 4.2, 0.35, 2.4, S, 4, math.radians(45)))
        out += lancet(0, -0.82, 0.4, 0.9, 1.7, st["dark"])
        for x in (-2.2, 2.2):
            out.append(needle(x, -1.6, 0, 0.32, 3.0, S, 4, math.radians(45)))
            out.append(ball((x, -1.6, 3.1), 0.2, G, 1.0, 1.0, 1.6))
    elif tier == 6:  # Hall of Darkness: a long black hall with three needle towers and black banners
        out.append(box((0, 0, 2.0), (4.6, 2.8, 4.0), W))
        out.append(prism_roof(0, 0, 4.6, 2.8, 4.0, 2.2, R))
        for x in (-1.8, 0, 1.8):
            out += round_tower(x, -1.4, 0.45, 5.2 + (1.4 if x == 0 else 0), W, R, 2.8, spire=True)
        for x in (-0.9, 0.9):
            out += banner(x - 0.3, -1.45, 3.2, (0.06, 0.05, 0.07), 0.6)
        out += lancet(0, -1.85, 0, 0.8, 1.8, M("glow", (0.6, 0.2, 0.8)))
        for x in (-1.8, 1.8):
            out += lancet(x, -1.86, 1.6, 0.3, 0.9, M("glow", (0.6, 0.2, 0.8)))
    else:  # Dragon Vault: a black crag with a dragon's skull for a gateway and a great ribcage above
        out += rock_hill(0, 0.6, 3.6, 2.6, 4.2, st["rock"], 9)
        out.append(prim("sphere", (0, -1.7, 1.2), (1.5, 0.3, 1.3), mat=st["dark"], segments=24, ring_count=12, bake=True))
        out.append(ball((0, -2.2, 2.7), 1.0, st["bone"], 1.2, 1.5, 0.85))   # cranium, snout toward the camera
        out.append(ball((0, -3.2, 2.35), 0.6, st["bone"], 0.9, 1.3, 0.55))  # snout
        out += [ball((x, -2.95, 2.85), 0.16, G) for x in (-0.45, 0.45)]
        for x in (-1, 1):
            out.append(rod((x * 0.8, -1.9, 3.1), (x * 1.8, -1.3, 4.6), 0.18, st["bone"], 0.04))  # horns
            out.append(rod((x * 0.7, -3.3, 1.9), (x * 0.5, -3.6, 1.0), 0.08, st["bone"], 0.02))  # fangs
        for k in range(5):
            y = -0.3 + k * 0.6
            out += rib(1.9, y, y + 0.2, 3.6 + 2.0 - abs(k - 1.5) * 0.4, 0.13, st["bone"], 0.0)
            out += rib(-1.9, y, y + 0.2, 3.6 + 2.0 - abs(k - 1.5) * 0.4, 0.13, st["bone"], 0.0)
        out.append(rod((0, -1.0, 5.4), (0, 2.6, 5.0), 0.16, st["bone"], 0.1))  # spine
    return out

def necro_building(sid):
    if sid in ("village_hall", "town_hall", "city_hall"):
        return n_hall({"village_hall": 1, "town_hall": 2, "city_hall": 3}[sid]), "hall"
    if sid in ("fort", "citadel"):
        return n_fort(sid == "citadel"), "fort"
    if sid == "tavern":
        return n_tavern(), "tavern"
    if sid == "marketplace":
        return n_market(), "marketplace"
    if sid.startswith("mage_guild"):
        return n_guild(1 if sid == "mage_guild_1" else 2), "mage_guild"
    if sid == "blacksmith":
        return n_smith(), "blacksmith"
    objs = n_dwelling(int(sid.split("_")[1]))
    if sid in ON_CRAG:
        for o in objs:
            o.location.z += RIDGE_Z
    return objs, sid

# ---------------------------------------------------------------------------------------------
def necro_backdrop():
    """The site with no buildings: moor, the crag ridge with a ramp to the gate, a flagstone way, graves, braziers."""
    st = _st()
    clear_objects(keep=("Key", "Rim"))
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.cycles.samples = 96
    set_key(azimuth_deg=-125, elevation_deg=30, energy=3.4)
    bpy.data.objects["Key"].data.color = (0.82, 0.9, 1.0)
    ground("swamp", (200, 160))
    rng = random.Random(4)
    pts = [(rng.uniform(-40, 40), rng.uniform(26, 60)) for _ in range(26)] + \
          [(s * rng.uniform(18, 30), rng.uniform(-6, 18)) for s in (-1, 1) for _ in range(5)]
    scatter(["tree_dead_1", "tree_dead_2", "tree_pine_3"], pts, rng, (1.6, 2.4))
    for i, x in enumerate((-60, -25, 15, 50)):
        objs = JOBS["mountain_2" if i % 2 else "mountain_3"]()
        haze = noise_material("far_mtn_n", (0.3, 0.32, 0.4), (0.5, 0.52, 0.62), scale=3, bump=0.2)
        for o in objs:
            o.data.materials.clear(); o.data.materials.append(haze)
            o.scale = (5, 5, 5.5)
            o.location = (x + rng.uniform(-6, 6), 140 + rng.uniform(0, 20), -1)
    # the crag: a long plateau of black rock the fortress stands on, with a ramp up to the gate
    fy = NECRO_SLOTS["fort"][1]
    crag = prim("cube", (0, fy + 3.0, RIDGE_Z / 2), (30, 6.0, RIDGE_Z / 2), mat=st["rock"], bake=True)
    displace(crag, strength=0.45, scale=0.8, seed=5, subdiv=3)
    for k, x in enumerate(range(-30, 31, 6)):
        if abs(x) > 3:
            rock_hill(x + rng.uniform(-1, 1), fy - 2.6, 3.6, 1.6, RIDGE_Z + 0.1, st["rock"], 11 + k)
    flag = mats()["stone"]
    edge = fy - 3.0
    ramp = prim("cube", (0, edge - 3.3, RIDGE_Z / 2 - 0.15), (2.6, 3.5, 0.15), mat=flag, bake=True)
    ramp.rotation_euler = (math.atan2(RIDGE_Z, 6.6), 0, 0)
    for x in (-2.8, 2.8):
        rod((x, edge - 6.6, 0), (x, edge + 0.2, RIDGE_Z + 0.4), 0.18, st["stone"])
    # flagstone way: from the front to the hall, a small square before it, and on to the ramp
    for (x0, y0, x1, y1, w) in ((0.3, -7, -1.0, 6.0, 2.6), (-1.0, 9.5, 0, fy - 9.6, 2.4)):
        p = prim("cube", ((x0 + x1) / 2, (y0 + y1) / 2, 0.02), (1, 1, 1), mat=flag)
        p.scale = (math.hypot(x1 - x0, y1 - y0) / 2, w / 2, 0.02)
        p.rotation_euler = (0, 0, math.atan2(y1 - y0, x1 - x0))
        bake_scale(p)
    sq = prim("cyl", (-1.2, 5.0, 0.025), (4.6, 2.6, 0.03), mat=flag, vertices=8, bake=True)
    # graves, bone pikes and green braziers along the way; the low iron fence in front
    for (x, y) in ((-16, -1.0), (-15, 0.6), (-17.2, 1.8), (-11.5, -3.2), (-10.3, -3.6), (16, 9.0), (17.5, 7.5),
                   (6.5, 11.5), (8.0, 11.0), (-6.0, 13.5), (-4.6, 14.0)):
        gravestone(x, y, rng.uniform(0.9, 1.3), rng.uniform(-0.3, 0.3))
    for (x, y) in ((-2.2, -4.5), (2.6, -4.5), (-2.6, 3.0), (1.3, 3.0)):
        brazier(x, y, 1.1)
    for (x, y) in ((-6.5, 5.5), (-5.8, 6.5), (2.8, 9.5), (14, -2.5), (-15, 9.5)):
        rod((x, y, 0), (x + rng.uniform(-0.2, 0.2), y, 1.8), 0.05, st["bone"], 0.01)
        skull(x, y - 0.05, 1.95, 0.35)
    for x in range(-18, 19, 2):
        if abs(x) > 3:
            rod((x, -5.4, 0), (x, -5.4, 1.1), 0.04, st["iron"])
            needle(x, -5.4, 1.1, 0.07, 0.25, st["iron"], 4)
    rod((-18, -5.4, 0.9), (-4, -5.4, 0.9), 0.03, st["iron"])
    rod((4, -5.4, 0.9), (18, -5.4, 0.9), 0.03, st["iron"])
    town_camera(wide=True)
