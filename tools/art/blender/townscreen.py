"""Town screen art: one 3D town per faction rendered as a backdrop + one cropped transparent layer per
building (same camera), plus assets/town/layout_<faction>.json = {sprite_id: [x, y, w, h]} in 1920x810.
Requires studio.py, props.py, figures.py, buildings.py, battlefield.py.
"""
VIEW_W, VIEW_H = 1920, 810

# slot -> (x, y) world position (y = depth). Camera looks north from y=-24.
SLOTS = {
    "fort": (0, 15), "hall": (0, 6), "mage_guild": (9.5, 9.5), "tavern": (-9, 3.5), "marketplace": (-4.5, 0.5),
    "blacksmith": (5.5, 1.0), "dwelling_1": (-16.5, 3.0), "dwelling_2": (-11.5, -0.5), "dwelling_3": (12.5, 5.0),
    "dwelling_4": (16.5, 0.0), "dwelling_5": (6.5, 8.0), "dwelling_6": (-6.5, 8.5), "dwelling_7": (16, 12),
}

def town_camera():
    sc = bpy.context.scene
    cam = bpy.data.objects.get("TownCam") or bpy.data.objects.new("TownCam", bpy.data.cameras.new("TownCam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.data.type = "PERSP"
    cam.data.lens = 30
    cam.data.clip_end = 2000
    cam.location = (0, -22, 8.0)
    cam.rotation_euler = Euler((math.radians(79), 0, 0), "XYZ")
    sc.camera = cam
    sc.render.resolution_x = VIEW_W
    sc.render.resolution_y = VIEW_H
    return cam

def S_(f):
    """Faction style materials."""
    m = mats()
    if f == "haven":
        return {"wall": m["hwall"], "roof": m["hroof"], "roof2": m["rroof"], "plaster": m["plaster"], "wood": m["wood"],
                "stone": m["stone"], "accent": (0.12, 0.25, 0.75), "glow": (1.0, 0.8, 0.4), "metal": M("gold")}
    return {"wall": m["nwall"], "roof": m["nroof"], "roof2": m["nroof"], "plaster": m["stone"], "wood": M("wood"),
            "stone": m["stone"], "accent": (0.3, 0.05, 0.35), "glow": (0.35, 1.0, 0.45), "metal": M("darksteel")}

def at(objs, x, y, rot=0.0, s=1.0):
    c, sn = math.cos(rot), math.sin(rot)
    for o in objs:
        lx, ly = o.location.x * s, o.location.y * s
        o.location = (x + lx * c - ly * sn, y + lx * sn + ly * c, o.location.z * s)
        o.rotation_euler.z += rot
        if s != 1.0:
            o.scale = (o.scale[0] * s, o.scale[1] * s, o.scale[2] * s)
    return objs

def windows(objs_list, cx, y_front, z, n, spacing, col, w=0.22, h=0.4):
    for k in range(n):
        x = cx + (k - (n - 1) / 2) * spacing
        objs_list.append(box((x, y_front - 0.02, z), (w, 0.05, h), M("glow", col)))

# ---------------------------------------------------------------------------------------------
# Building recipes (local coords: x east, y north, origin at ground centre)
# ---------------------------------------------------------------------------------------------
def b_hall(f, level):
    st = S_(f)
    out = []
    if level == 1:
        out += house(0, 0, 3.2, 2.2, 2.2, st["plaster"], st["roof2"])
        windows(out, 0, -1.1, 1.2, 3, 0.9, st["glow"])
    elif level == 2:
        out += house(0, 0, 4.2, 2.6, 2.8, st["wall"], st["roof"])
        out += square_tower(0, 0.2, 1.4, 1.4, 4.6, st["wall"], st["roof"], 1.8, flag=st["accent"])
        windows(out, 0, -1.3, 1.5, 4, 0.9, st["glow"])
    else:
        out.append(box((0, 0, 1.8), (5.4, 3.2, 3.6), st["wall"]))
        out.append(prim("sphere", (0, 0.2, 3.6), (1.7, 1.7, 1.6), mat=st["roof"], segments=32, ring_count=16, bake=True))
        out.append(prim("cone", (0, 0.2, 5.5), (1, 1, 1), mat=st["metal"], vertices=16, radius1=0.25, radius2=0.0, depth=1.0))
        for x in (-2.7, 2.7):
            out += round_tower(x, -1.2, 0.7, 4.4, st["wall"], st["roof"], 1.8, flag=st["accent"])
        for k in range(6):
            out.append(rod((-2.0 + k * 0.8, -1.75, 0), (-2.0 + k * 0.8, -1.75, 3.0), 0.15, ph_material("marble_01", 1.0)))
        out.append(box((0, -1.75, 3.15), (5.0, 0.4, 0.3), st["wall"]))
        windows(out, 0, -1.62, 2.0, 5, 0.9, st["glow"])
    return out

def b_fort(f, citadel):
    st = S_(f)
    W, R = st["wall"], st["roof"]
    spire = f == "necropolis"
    out = []
    w = 26 if citadel else 22
    h = 3.4 if citadel else 2.8
    out += wall(-w / 2, 0, w / 2, 0, h, W, 0.8)
    for x in [(-w / 2) + k * (w / 4) for k in range(5)]:
        out += round_tower(x, 0, 1.1, h + 1.6, W, R, 3.0 if spire else 2.2, spire=spire, flag=st["accent"] if abs(x) < 1 else None)
    if citadel:
        out += square_tower(-4.5, 3, 3.2, 3.2, 9.0, W, R, 3.5, flag=st["accent"])
        out += round_tower(4.5, 3, 1.5, 10.5, W, R, 4.5 if spire else 3.4, spire=True, flag=st["accent"])
        out += round_tower(0, 5, 1.8, 12, W, R, 5.0, spire=True, flag=st["accent"])
    else:
        out += square_tower(0, 3, 3.6, 3.0, 7.0, W, R, 3.0, flag=st["accent"])
    return out

def b_tavern(f):
    st = S_(f)
    out = house(0, 0, 3.4, 2.4, 2.0, st["wood"] if f == "haven" else st["plaster"], st["roof2"])
    out.append(box((0, 0.3, 2.9), (2.2, 1.6, 1.2), st["plaster"]))
    out.append(prism_roof(0, 0.3, 2.2, 1.6, 3.5, 1.0, st["roof2"]))
    windows(out, 0, -1.22, 1.0, 3, 1.0, (1.0, 0.7, 0.3))
    out.append(rod((1.9, -1.4, 0), (1.9, -1.4, 2.4), 0.06, M("wood")))
    out.append(rod((1.9, -1.4, 2.3), (2.6, -1.4, 2.3), 0.05, M("wood")))
    out.append(box((2.45, -1.4, 1.95), (0.6, 0.06, 0.5), M("cloth", st["accent"])))
    out += [prim("cyl", (-1.2 + k * 0.6, -1.7, 0.35), (0.25, 0.25, 0.35), mat=M("wood"), vertices=16, bake=True) for k in range(2)]
    return out

def b_market(f):
    st = S_(f)
    cols = [(0.8, 0.15, 0.1), (0.9, 0.75, 0.2), st["accent"], (0.2, 0.55, 0.25)] if f == "haven" else [(0.3, 0.05, 0.35), (0.15, 0.3, 0.15), (0.35, 0.05, 0.05), (0.1, 0.1, 0.12)]
    out = []
    for k, (x, y) in enumerate(((-1.8, 0), (0, 0.4), (1.8, 0), (0.9, -1.6))):
        out += [rod((x + dx, y + dy, 0), (x + dx, y + dy, 1.6), 0.05, M("wood")) for dx in (-0.6, 0.6) for dy in (-0.5, 0.5)]
        aw = prim("cube", (x, y, 1.75), (0.75, 0.62, 0.1), mat=M("cloth", cols[k % 4]), bake=True)
        aw.rotation_euler = (math.radians(-12), 0, 0)
        out.append(aw)
        out.append(box((x, y - 0.3, 0.45), (1.2, 0.5, 0.9), M("wood")))
        out += [ball((x - 0.3 + i * 0.3, y - 0.3, 0.98), 0.12, M("cloth", (0.9, 0.5 - i * 0.1, 0.1 + i * 0.2))) for i in range(3)]
    return out

def b_guild(f, level):
    st = S_(f)
    tiers = 2 if level == 1 else 4
    out = []
    r = 1.3
    z = 0
    for t in range(tiers):
        hh = 1.8
        out.append(prim("cyl", (0, 0, z + hh / 2), (r, r, hh / 2), mat=st["wall"], vertices=24, bake=True))
        out.append(prim("torus", (0, 0, z + hh), (1, 1, 1), mat=st["metal"], major_radius=r * 1.02, minor_radius=0.07))
        windows(out, 0, -r - 0.01, z + hh * 0.5, 2, 0.7, (0.6, 0.7, 1.0) if f == "haven" else st["glow"], 0.18, 0.5)
        z += hh
        r *= 0.82
    out.append(prim("cone", (0, 0, z + 1.6), (1, 1, 1), mat=st["roof"], vertices=24, radius1=r * 1.4, radius2=0.0, depth=3.2))
    out.append(ball((0, 0, z + 3.4), 0.2, M("glow", (0.35, 0.55, 1.0) if f == "haven" else (0.2, 0.8, 0.3))))
    return out

def b_smith(f):
    st = S_(f)
    out = house(0, 0.3, 3.0, 2.0, 1.8, st["stone"], st["roof2"])
    out.append(rod((1.0, 0.8, 1.5), (1.0, 0.8, 3.8), 0.3, st["stone"]))
    out.append(box((-0.5, -1.0, 0.7), (0.9, 0.05, 0.9), M("glow", (0.55, 0.18, 0.04))))
    out.append(box((0.9, -1.6, 0.3), (0.5, 0.3, 0.6), M("darksteel")))
    out.append(box((0.9, -1.6, 0.65), (0.8, 0.35, 0.15), M("darksteel")))
    return out

def b_dwelling(f, tier):
    st = S_(f)
    W, R = st["wall"], st["roof"]
    out = []
    if f == "haven":
        if tier == 1:
            out += house(0, 0, 2.6, 1.8, 1.8, st["stone"], st["roof2"])
            out += banner(1.5, -0.9, 1.0, st["accent"])
        elif tier == 2:
            out += [rod((x, y, 0), (x * 0.6, y * 0.6, 4.2), 0.12, M("wood")) for x in (-0.9, 0.9) for y in (-0.9, 0.9)]
            out.append(box((0, 0, 4.3), (2.0, 2.0, 0.2), M("wood")))
            out += merlons(-1.0, -1.0, 1.0, -1.0, 4.4, 0.12, M("wood"), 0.3)
            out.append(prim("cone", (0, 0, 5.4), (1, 1, 1), mat=R, vertices=4, radius1=1.6, radius2=0, depth=1.6, rot=(0, 0, math.radians(45))))
        elif tier == 3:
            out += round_tower(0, 0, 1.2, 5.2, W, None, crenel=True)
            out.append(ball((0, 0, 5.5), 1.0, ph_material("bark_brown_02", 2.0), 1.3, 1.3, 0.35))
            out.append(ball((0.2, 0, 6.1), 0.4, M("fur", (0.72, 0.52, 0.25)), 1.4, 0.8, 0.8))
        elif tier == 4:
            out += house(0, 0, 4.4, 2.0, 2.0, W, R)
            out += banner(-2.2, -1.0, 1.4, st["accent"]) + banner(2.2, -1.0, 1.4, st["accent"])
            windows(out, 0, -1.02, 1.1, 4, 0.9, st["glow"])
        elif tier == 5:
            out += house(0, 0.4, 2.4, 4.0, 2.6, st["plaster"], st["roof2"], math.radians(90))
            out += square_tower(0, -1.6, 1.2, 1.2, 4.6, W, R, 2.0)
            glass = flat_material("stained_glass", (0.15, 0.25, 0.75), 0.2, 0.0, emit=0.8)
            out.append(prim("cyl", (0, -2.22, 3.4), (0.35, 0.35, 0.02), mat=glass, vertices=24, bake=True, rot=(math.radians(90), 0, 0)))
            out.append(prim("torus", (0, -2.24, 3.4), (1, 1, 1), mat=st["metal"], major_radius=0.36, minor_radius=0.04, rot=(math.radians(90), 0, 0)))
        elif tier == 6:
            out += house(0, 1.0, 3.4, 1.8, 1.8, M("wood"), st["roof2"])
            for x in (-2.0, -1.0, 0.0, 1.0, 2.0):
                out.append(rod((x, -1.2, 0), (x, -1.2, 0.8), 0.06, M("wood")))
            out.append(rod((-2.0, -1.2, 0.6), (2.0, -1.2, 0.6), 0.04, M("wood")))
            out.append(rod((-2.0, -1.2, 0.3), (2.0, -1.2, 0.3), 0.04, M("wood")))
            out.append(rod((-1.0, -0.4, 0), (-1.0, -0.4, 1.6), 0.08, M("wood")))
            out.append(ball((-1.0, -0.4, 1.45), 0.25, M("cloth", (0.8, 0.7, 0.5)), 1.0, 1.0, 1.4))
        else:
            gold = M("gold")
            out += [rod((x, 0, 0), (x, 0, 4.0), 0.35, ph_material("marble_01", 1.0)) for x in (-1.6, 1.6)]
            out.append(prim("torus", (0, 0, 4.0), (1, 1, 1), mat=gold, major_radius=1.6, minor_radius=0.25, rot=(math.radians(90), 0, 0)))
            portal = flat_material("portal", (0.25, 0.45, 0.95), 0.2, 0.0, emit=1.2)
            out.append(prim("cyl", (0, 0.05, 2.4), (1.25, 1.25, 0.05), mat=portal, vertices=32, bake=True, rot=(math.radians(90), 0, 0)))
            out.append(box((0, 0, 0.2), (4.4, 1.6, 0.4), ph_material("marble_01", 1.0)))
            out += feather_wings({"chest": Vector((0, 0.1, 4.0))}, M("cloth", (0.97, 0.96, 0.93)), 1.8, span=1.4)
    else:
        G = st["glow"]
        if tier == 1:
            out += house(0, 0, 2.6, 2.4, 2.2, W, R)
            out.append(prim("cone", (0, -0.5, 3.6), (1, 1, 1), mat=R, vertices=6, radius1=0.6, radius2=0, depth=2.2))
            windows(out, 0, -1.22, 1.2, 2, 1.0, G, 0.2, 0.6)
        elif tier == 2:
            for k in range(7):
                x = -2.0 + (k % 4) * 1.3 + (0.6 if k >= 4 else 0)
                y = -0.8 + (k // 4) * 1.2
                out.append(box((x, y, 0.4), (0.5, 0.18, 0.8), st["stone"]))
                out.append(prim("cyl", (x, y, 0.8), (0.25, 0.25, 0.09), mat=st["stone"], vertices=16, bake=True, rot=(math.radians(90), 0, 0)))
            for x in (-2.6, -1.3, 0, 1.3, 2.6):
                out.append(rod((x, -1.6, 0), (x, -1.6, 1.0), 0.04, M("darksteel")))
            out.append(rod((-2.6, -1.6, 0.85), (2.6, -1.6, 0.85), 0.03, M("darksteel")))
            out += tree_dead(7)
        elif tier == 3:
            out.append(box((0, 0, 1.4), (2.6, 2.6, 2.8), st["stone"]))
            out.append(prim("cone", (0, 0, 3.6), (1, 1, 1), mat=R, vertices=4, radius1=2.1, radius2=0, depth=1.6, rot=(0, 0, math.radians(45))))
            out.append(box((0, -1.32, 0.9), (0.9, 0.05, 1.6), M("glow", (0.6, 0.9, 1.0))))
            out += [ball((x, -1.6, 1.8), 0.4, M("ghost", (0.55, 0.85, 1.0))) for x in (-0.8, 0.9)]
        elif tier == 4:
            out += house(0, 0, 4.2, 2.6, 3.0, W, R)
            out += round_tower(-2.1, -1.0, 0.6, 4.8, W, R, 2.4, spire=True) + round_tower(2.1, -1.0, 0.6, 4.8, W, R, 2.4, spire=True)
            windows(out, 0, -1.32, 1.8, 3, 1.0, (0.9, 0.2, 0.2))
        elif tier == 5:
            out.append(prim("cone", (0, 0, 2.0), (1, 1, 1), mat=st["stone"], vertices=4, radius1=3.0, radius2=0.3, depth=4.0, rot=(0, 0, math.radians(45))))
            out.append(box((0, -1.6, 0.8), (1.0, 0.1, 1.6), M("glow", G)))
            out += [rod((x, -2.2, 0), (x, -2.2, 1.0), 0.05, M("darksteel")) for x in (-1.2, 1.2)] + [ball((x, -2.2, 1.12), 0.15, M("glow", G)) for x in (-1.2, 1.2)]
        elif tier == 6:
            out.append(box((0, 0, 2.0), (4.4, 2.8, 4.0), W))
            out.append(prism_roof(0, 0, 4.4, 2.8, 4.0, 2.0, R))
            for x in (-1.6, 0, 1.6):
                out += round_tower(x, -1.4, 0.4, 5.0 + (1.2 if x == 0 else 0), W, R, 2.4, spire=True)
            windows(out, 0, -1.42, 2.0, 4, 0.9, (0.6, 0.2, 0.8))
        else:
            out += rock_hill(0, 0.5, 3.2, 2.2, 3.6, mats()["rock"], 9)
            out.append(prim("sphere", (0, -1.6, 1.1), (1.3, 0.3, 1.2), mat=flat_material("gate_dark", (0.03, 0.025, 0.02), 0.9), segments=24, ring_count=12, bake=True))
            sk = ball((0, -1.9, 2.5), 0.7, M("bone"), 1.3, 0.8, 0.9)
            out.append(sk)
            out += [ball((x, -2.45, 2.6), 0.12, M("glow", G)) for x in (-0.28, 0.28)]
            out += [rod((x, -1.8, 0), (x * 1.4, -2.3, 1.6), 0.12, M("bone"), 0.04) for x in (-1.3, 1.3)]
    return out

def building(f, sid):
    if sid in ("village_hall", "town_hall", "city_hall"):
        return b_hall(f, {"village_hall": 1, "town_hall": 2, "city_hall": 3}[sid]), "hall"
    if sid in ("fort", "citadel"):
        return b_fort(f, sid == "citadel"), "fort"
    if sid == "tavern":
        return b_tavern(f), "tavern"
    if sid == "marketplace":
        return b_market(f), "marketplace"
    if sid.startswith("mage_guild"):
        return b_guild(f, 1 if sid == "mage_guild_1" else 2), "mage_guild"
    if sid == "blacksmith":
        return b_smith(f), "blacksmith"
    tier = int(sid.split("_")[1])
    return b_dwelling(f, tier), sid

SPRITES = ["village_hall", "town_hall", "city_hall", "fort", "citadel", "tavern", "marketplace", "mage_guild_1", "mage_guild_2",
           "blacksmith"] + [f"dwelling_{k}" for k in range(1, 8)]

# ---------------------------------------------------------------------------------------------
def town_backdrop(f):
    clear_objects(keep=("Key", "Rim"))
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.cycles.samples = 96
    terrain = "grass" if f == "haven" else "swamp"
    set_key(azimuth_deg=-130, elevation_deg=38, energy=4.0 if f == "haven" else 3.6)
    if f == "necropolis":
        bpy.data.objects["Key"].data.color = (0.85, 0.9, 1.0)
    ground(terrain, (200, 160))
    rng = random.Random(3 if f == "haven" else 4)
    trees = ["tree_oak_1", "tree_oak_2", "tree_pine_1", "tree_pine_2"] if f == "haven" else ["tree_dead_1", "tree_dead_2", "tree_pine_3"]
    # trees around the edges and on the far hills
    pts = [(rng.uniform(-40, 40), rng.uniform(24, 60)) for _ in range(30)] + [(s * rng.uniform(18, 30), rng.uniform(-8, 20)) for s in (-1, 1) for _ in range(6)]
    scatter(trees, pts, rng, (1.6, 2.4))
    for i, x in enumerate((-60, -25, 15, 50)):
        objs = JOBS["mountain_2" if i % 2 else "mountain_3"]()
        haze = noise_material("far_mtn", (0.36, 0.42, 0.55), (0.6, 0.66, 0.78), scale=3, bump=0.2)
        for o in objs:
            o.data.materials.clear(); o.data.materials.append(haze)
            o.scale = (5, 5, 5.5)
            o.location = (x + rng.uniform(-6, 6), 140 + rng.uniform(0, 20), -1)
    # irregular cobbled plaza with dirt paths and props
    plaza = prim("cyl", (0, 6, 0.02), (15, 8.5, 0.03), mat=mats()["cobble"] if f == "haven" else mats()["stone"], vertices=96, bake=True)
    import mathutils.noise as mn
    for v in plaza.data.vertices:
        r = math.hypot(v.co.x / 15, (v.co.y) / 8.5)
        if r > 0.9:
            k = 1.0 + 0.12 * mn.noise(Vector((v.co.x * 0.3, v.co.y * 0.3, 0)))
            v.co.x *= k; v.co.y *= k
    dirt = ph_material("grass_path_2", 0.6, sat=0.9)
    for (x0, y0, x1, y1) in ((0, -2, 0, -14), (-13, 3, -24, -6), (13, 3, 24, -6)):
        path = prim("cube", ((x0 + x1) / 2, (y0 + y1) / 2, 0.015), (1, 1, 1), mat=dirt)
        path.scale = (math.hypot(x1 - x0, y1 - y0) / 2, 1.6, 0.02)
        path.rotation_euler = (0, 0, math.atan2(y1 - y0, x1 - x0))
        bake_scale(path)
    rng2 = random.Random(9)
    if f == "haven":
        for k in range(8):
            x, y = rng2.uniform(-12, 12), rng2.uniform(-2.5, -0.5) if k < 5 else rng2.uniform(9, 11)
            if rng2.random() < 0.5:
                prim("cyl", (x, y, 0.35), (0.3, 0.3, 0.35), mat=M("wood"), vertices=14, bake=True)
            else:
                box((x, y, 0.3), (0.6, 0.6, 0.6), M("wood"), rng2.uniform(0, 1))
        for x in (-6.5, 6.5, -12, 12):
            rod((x, -2.2, 0), (x, -2.2, 2.2), 0.06, M("darksteel"))
            ball((x, -2.2, 2.3), 0.16, M("glow", (1.0, 0.75, 0.4)))
        for (x, y) in ((-17, -3), (17, -3), (-3, -3.5), (3, -3.5)):
            scatter(["flowers_1", "flowers_2", "bush_1"], [(x, y)], rng2, (1.2, 1.6))
    else:
        for (x, y) in ((-15, 1), (15, 1), (-8, 11), (8, 11)):
            scatter(["tree_dead_1", "tree_dead_2"], [(x, y)], rng2, (1.4, 1.9))
        for x in (-6.5, 6.5, -12, 12):
            rod((x, -2.2, 0), (x, -2.2, 2.0), 0.06, M("darksteel"))
            ball((x, -2.2, 2.1), 0.17, M("glow", (0.35, 1.0, 0.45)))
        for k in range(9):
            x = rng2.uniform(-14, 14); y = rng2.uniform(-3.5, -1.0)
            box((x, y, 0.3), (0.35, 0.14, 0.6), mats()["stone"], rng2.uniform(-0.3, 0.3))
        for x in range(-18, 19, 2):
            if abs(x) > 3:
                rod((x, -4.2, 0), (x, -4.2, 1.1), 0.04, M("darksteel"))
        rod((-18, -4.2, 0.9), (-4, -4.2, 0.9), 0.03, M("darksteel"))
        rod((4, -4.2, 0.9), (18, -4.2, 0.9), 0.03, M("darksteel"))
    town_camera()

def render_town(f):
    town_backdrop(f)
    render(f"town/{f}_bg.png")
    layout = {}
    base_objs = set(o.name for o in bpy.context.scene.objects)
    # buildings render alone, but the ground/plaza still catch their shadows: hide everything else from camera
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.is_shadow_catcher = True
    for sid in SPRITES:
        objs, slot = building(f, sid)
        x, y = SLOTS[slot]
        at(objs, x, y, 0.0, 1.0)
        for o in bpy.context.scene.objects:
            if o.name not in base_objs and o not in objs and o.type == "MESH":
                o.hide_render = True
        render(f"town/{f}_{sid}.png")
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        for o in list(bpy.context.scene.objects):
            if o.name not in base_objs:
                bpy.data.objects.remove(o, do_unlink=True)
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.is_shadow_catcher = False
    return True  # cropping + layout json: tools/art/town_crop.py


# ---------------------------------------------------------------------------------------------
# Main menu key art: Haven citadel at golden hour, a hero and soldiers on a ridge in the foreground.
# ---------------------------------------------------------------------------------------------
def render_menu_art():
    town_backdrop("haven")
    for sid in ("citadel", "city_hall", "mage_guild_2", "dwelling_5", "dwelling_6", "dwelling_7", "tavern"):
        objs, slot = building("haven", sid)
        x, y = SLOTS[slot]
        at(objs, x, y)
    # foreground ridge
    prim("plane", (0, -32, 0.0), (60, 20, 1), mat=ground_material("grass"), bake=True)
    ridge = prim("sphere", (-7, -17, -2.6), (9, 4.5, 3.2), mat=ground_material("grass"), segments=48, ring_count=24, bake=True)
    # (foreground kept clear: figures and banners read poorly at this size)
    sc = bpy.context.scene
    set_key(azimuth_deg=-150, elevation_deg=14, energy=4.8)
    bpy.data.objects["Key"].data.color = (1.0, 0.72, 0.45)
    cam = town_camera()
    cam.location = (-2, -30, 6.5)
    cam.rotation_euler = Euler((math.radians(84), 0, math.radians(-4)), "XYZ")
    cam.data.lens = 28
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    sc.cycles.samples = 160
    return render("ui/main_menu_bg.png")
