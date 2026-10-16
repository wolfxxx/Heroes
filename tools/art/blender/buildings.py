"""Buildings & map objects for the adventure map (3/4 map camera). Requires studio.py + figures.py.

Coordinates: x east, y north (away from the camera), z up; 1 tile = 2 units. The world origin is the
sprite anchor = bottom-centre of the object's action tile. Towns occupy x[-5,5] y[0,6] (5x3 tiles,
gate in front-centre); 3x2 buildings occupy x[-3,3] y[0,4]; pickups sit on their own tile around (0,1).
"""

def mats():
    return {
        "hwall": ph_material("castle_brick_02_white", 0.7, sat=0.75, bright=1.15),
        "hroof": ph_material("grey_roof_tiles", 0.9, tint=(0.3, 0.45, 1.0), tint_k=0.9, sat=1.4, bright=1.1),
        "rroof": ph_material("clay_roof_tiles", 0.9, sat=1.2),
        "plaster": ph_material("grey_plaster", 0.8, tint=(1.0, 0.9, 0.75), tint_k=0.6),
        "wood": ph_material("brown_planks_05", 1.0),
        "nwall": ph_material("dark_brick_wall", 0.7, sat=0.6, bright=0.75),
        "nroof": ph_material("roof_slates_02", 0.9, tint=(0.4, 0.33, 0.5), tint_k=0.7, bright=0.55),
        "rock": ph_material("rock_face_03", 0.5, sat=0.85),
        "thatch": ph_material("thatch_roof_angled", 0.8, sat=1.1),
        "stone": ph_material("castle_brick_07", 0.8, sat=0.7),
        "cobble": ph_material("cobblestone_floor_08", 0.8),
    }

# ---------------------------------------------------------------------------------------------
# Kit
# ---------------------------------------------------------------------------------------------
def box(center, size, mat, rot_z=0.0):
    o = prim("cube", tuple(center), (size[0] / 2, size[1] / 2, size[2] / 2), mat=mat, bake=True)
    o.rotation_euler = (0, 0, rot_z)
    return o

def merlons(x0, y0, x1, y1, z, thick, mat, step=0.36):
    out = []
    a = Vector((x0, y0)); b = Vector((x1, y1))
    n = max(1, int((b - a).length / step))
    d = (b - a) / n
    ang = math.atan2(d.y, d.x)
    for i in range(n):
        if i % 2 == 0:
            c = a + d * (i + 0.5)
            out.append(box((c.x, c.y, z + 0.13), (d.length, thick, 0.26), mat, ang))
    return out

def wall(x0, y0, x1, y1, height, mat, thick=0.38, crenel=True):
    a = Vector((x0, y0)); b = Vector((x1, y1))
    c = (a + b) / 2
    ang = math.atan2(b.y - a.y, b.x - a.x)
    out = [box((c.x, c.y, height / 2), ((b - a).length, thick, height), mat, ang)]
    if crenel:
        out += merlons(x0, y0, x1, y1, height, thick, mat)
    return out

def round_tower(x, y, r, h, wall_m, roof_m=None, roof_h=None, crenel=False, flag=None, spire=False):
    out = [prim("cyl", (x, y, h / 2), (r, r, h / 2), mat=wall_m, vertices=24, bake=True)]
    if roof_m is not None:
        rh = roof_h or r * 2.2
        rr = r * (1.25 if not spire else 1.1)
        cone = prim("cone", (x, y, h + rh / 2), (1, 1, 1), mat=roof_m, vertices=24, radius1=rr, radius2=0.0, depth=rh)
        out.append(cone)
        top = h + rh
    else:
        top = h
        if crenel:
            for k in range(8):
                a = k * math.pi / 4
                out.append(box((x + math.cos(a) * r * 0.92, y + math.sin(a) * r * 0.92, h + 0.13), (0.22, 0.22, 0.26), wall_m, a))
    if flag:
        out += banner(x, y, top, flag)
    return out

def square_tower(x, y, w, d, h, wall_m, roof_m, roof_h=None, flag=None):
    out = [box((x, y, h / 2), (w, d, h), wall_m)]
    rh = roof_h or max(w, d) * 0.9
    pyr = prim("cone", (x, y, h + rh / 2), (1, 1, 1), mat=roof_m, vertices=4, radius1=max(w, d) * 0.78, radius2=0.0, depth=rh)
    pyr.rotation_euler = (0, 0, math.radians(45))
    pyr.scale = (w / max(w, d), d / max(w, d), 1)
    bake_scale(pyr)
    out.append(pyr)
    if flag:
        out += banner(x, y, h + rh, flag)
    return out

def prism_roof(cx, cy, w, d, z, rh, mat, rot_z=0.0, overhang=0.12):
    """Gable roof along x (ridge parallel to x)."""
    w2 = w / 2 + overhang; d2 = d / 2 + overhang
    verts = [(-w2, -d2, 0), (w2, -d2, 0), (w2, d2, 0), (-w2, d2, 0), (-w2, 0, rh), (w2, 0, rh)]
    faces = [(0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    me = bpy.data.meshes.new("roof")
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new("roof", me)
    link(o)
    o.location = (cx, cy, z)
    o.rotation_euler = (0, 0, rot_z)
    o.data.materials.append(mat)
    so = o.modifiers.new("sol", "SOLIDIFY"); so.thickness = 0.06
    return o

def house(cx, cy, w, d, h, wall_m, roof_m, rot_z=0.0, windows=None):
    out = [box((cx, cy, h / 2), (w, d, h), wall_m, rot_z), prism_roof(cx, cy, w, d, h, min(w, d) * 0.6, roof_m, rot_z)]
    if windows:
        wm = M("glow", windows)
        for k in (-0.25, 0.25):
            p = Vector((cx, cy)) + Vector((k * w, -d / 2 - 0.01)).rotated(rot_z) if False else None
            out.append(box((cx + k * w * math.cos(rot_z), cy + k * w * math.sin(rot_z) - d / 2 * math.cos(rot_z) - 0.01, h * 0.55), (0.14, 0.03, 0.22), wm, rot_z))
    return out

def banner(x, y, z, color, size=0.45):
    pole = rod((x, y, z - 0.05), (x, y, z + 0.75), 0.025, M("wood"))
    rows = []
    for r in range(3):
        row = []
        for c in range(4):
            u = c / 3; t = r / 2
            row.append(Vector((x + u * size * 1.3, y + math.sin(u * 3.0) * 0.05, z + 0.72 - t * size * 0.7)))
        rows.append(row)
    return [pole, sheet(rows, M("cloth", color), 0.01, "banner")]

def gate(x, y, w, h, wall_m):
    """Gatehouse block with a dark arched opening facing south (-y)."""
    out = [box((x, y, h / 2), (w, 0.7, h), wall_m)]
    dark = flat_material("gate_dark", (0.03, 0.025, 0.02), 0.9)
    out.append(box((x, y - 0.33, h * 0.32), (w * 0.45, 0.06, h * 0.64), dark))
    arch = prim("cyl", (x, y - 0.33, h * 0.64), (w * 0.225, w * 0.225, 0.03), mat=dark, vertices=24, bake=True)
    arch.rotation_euler = (math.radians(90), 0, 0)
    out.append(arch)
    door = box((x, y - 0.36, h * 0.3), (w * 0.4, 0.04, h * 0.6), M("wood"))
    out.append(door)
    out += merlons(x - w / 2, y - 0.3, x + w / 2, y - 0.3, h, 0.12, wall_m)
    return out

def ground_patch(r, mat, cx=0.0, cy=0.0, squash=1.0):
    p = prim("cyl", (cx, cy, 0.015), (r, r * squash, 0.03), mat=mat, vertices=48, bake=True)
    return [p]

# ---------------------------------------------------------------------------------------------
# Towns
# ---------------------------------------------------------------------------------------------
def town_haven():
    m = mats()
    W, R = m["hwall"], m["hroof"]
    BLUE = (0.12, 0.25, 0.75); GOLD = (0.95, 0.75, 0.2)
    out = ground_patch(5.2, m["cobble"], 0, 3.2, 0.62)
    out += wall(-4.2, 1.3, -1.25, 1.3, 1.2, W) + wall(1.25, 1.3, 4.2, 1.3, 1.2, W)
    out += wall(-4.2, 1.3, -4.2, 5.4, 1.2, W) + wall(4.2, 1.3, 4.2, 5.4, 1.2, W) + wall(-4.2, 5.4, 4.2, 5.4, 1.2, W)
    for (x, y) in ((-4.2, 1.3), (4.2, 1.3), (-4.2, 5.4), (4.2, 5.4)):
        out += round_tower(x, y, 0.55, 2.0, W, R, 1.3)
    out += gate(0, 1.3, 2.0, 1.7, W)
    out += round_tower(-1.15, 1.2, 0.5, 2.3, W, R, 1.2, flag=BLUE) + round_tower(1.15, 1.2, 0.5, 2.3, W, R, 1.2, flag=BLUE)
    out += square_tower(0, 4.1, 2.4, 1.9, 3.3, W, R, 1.6)
    out += round_tower(1.7, 4.7, 0.55, 4.6, W, R, 1.8, flag=GOLD, spire=True)
    out += round_tower(-1.6, 4.6, 0.45, 3.8, W, R, 1.5)
    # cathedral nave + steeple
    out += house(-2.7, 3.5, 1.4, 2.2, 1.7, m["plaster"], m["rroof"], math.radians(90))
    out += square_tower(-2.7, 2.35, 0.7, 0.7, 2.6, W, R, 1.4)
    out += house(2.7, 2.6, 1.5, 1.1, 1.1, m["plaster"], m["rroof"], 0.0, windows=(1.0, 0.8, 0.4))
    out += house(2.8, 4.2, 1.2, 1.0, 1.0, m["plaster"], R, math.radians(90))
    out += house(-2.6, 2.0, 1.0, 0.9, 0.9, m["plaster"], m["rroof"])
    return out

def town_necropolis():
    m = mats()
    W, R = m["nwall"], m["nroof"]
    GREEN = (0.35, 1.0, 0.45); PURP = (0.3, 0.05, 0.35)
    out = ground_patch(5.2, ph_material("brown_mud_leaves_01", 0.8, sat=0.6, bright=0.7), 0, 3.2, 0.62)
    out += wall(-4.2, 1.3, -1.25, 1.3, 1.3, W) + wall(1.25, 1.3, 4.2, 1.3, 1.3, W)
    out += wall(-4.2, 1.3, -4.2, 5.4, 1.3, W) + wall(4.2, 1.3, 4.2, 5.4, 1.3, W) + wall(-4.2, 5.4, 4.2, 5.4, 1.3, W)
    for (x, y) in ((-4.2, 1.3), (4.2, 1.3), (-4.2, 5.4), (4.2, 5.4)):
        out += round_tower(x, y, 0.55, 2.3, W, R, 2.3, spire=True)
    out += gate(0, 1.3, 2.0, 1.8, W)
    out += round_tower(-1.15, 1.2, 0.5, 2.5, W, R, 2.0, flag=PURP, spire=True) + round_tower(1.15, 1.2, 0.5, 2.5, W, R, 2.0, flag=PURP, spire=True)
    # gothic cathedral
    out.append(box((0, 4.2, 1.7), (2.6, 1.8, 3.4), W))
    out.append(prism_roof(0, 4.2, 2.6, 1.8, 3.4, 1.6, R))
    for x in (-1.4, 1.4):
        out += round_tower(x, 3.3, 0.42, 4.4, W, R, 2.6, spire=True)
    out += round_tower(0, 3.2, 0.5, 5.5, W, R, 3.2, spire=True, flag=PURP)
    glow = M("glow", GREEN)
    out.append(prim("cyl", (0, 3.28 - 0.53, 3.8), (0.3, 0.3, 0.02), mat=glow, vertices=24, bake=True, rot=(math.radians(90), 0, 0)))
    for x in (-0.9, -0.45, 0.45, 0.9):
        out.append(box((x, 3.28, 1.6), (0.18, 0.04, 0.6), glow))
    # crypts, tombstones, braziers
    out += house(-2.7, 3.2, 1.4, 1.8, 1.2, m["stone"], R, math.radians(90))
    out += house(2.7, 3.3, 1.3, 1.6, 1.1, m["stone"], R, math.radians(90))
    for (x, y) in ((-3.2, 2.0), (-2.6, 1.9), (2.5, 1.95), (3.2, 2.0)):
        out.append(box((x, y, 0.25), (0.28, 0.12, 0.5), m["stone"]))
    for x in (-1.9, 1.9):
        out.append(rod((x, 0.7, 0), (x, 0.7, 0.8), 0.05, M("darksteel")))
        out.append(ball((x, 0.7, 0.92), 0.14, M("glow", GREEN)))
    return out

# ---------------------------------------------------------------------------------------------
# Mines & 3x2 buildings
# ---------------------------------------------------------------------------------------------
def rock_hill(cx, cy, rx, ry, h, mat, seed=1):
    o = prim("sphere", (cx, cy, 0), (rx, ry, h), mat=mat, segments=32, ring_count=16, bake=True)
    displace(o, strength=0.35, scale=0.6, seed=seed, subdiv=1)
    smooth(o)
    return [o]

def mine_entrance(x, y, w=0.9, h=1.0):
    wood = M("wood")
    dark = flat_material("gate_dark", (0.03, 0.025, 0.02), 0.9)
    return [box((x, y, h / 2), (w, 0.15, h), dark),
            rod((x - w / 2, y - 0.1, 0), (x - w / 2, y - 0.1, h + 0.05), 0.07, wood),
            rod((x + w / 2, y - 0.1, 0), (x + w / 2, y - 0.1, h + 0.05), 0.07, wood),
            rod((x - w / 2 - 0.12, y - 0.1, h + 0.05), (x + w / 2 + 0.12, y - 0.1, h + 0.05), 0.08, wood)]

def cart(x, y, load_mat):
    wood = M("wood")
    out = [box((x, y, 0.32), (0.7, 0.45, 0.3), wood)]
    out.append(ball((x, y, 0.5), 0.3, load_mat, 1.1, 0.75, 0.45))
    for dx in (-0.22, 0.22):
        w = prim("cyl", (x + dx, y - 0.24, 0.14), (0.14, 0.14, 0.03), mat=M("darksteel"), vertices=16, bake=True)
        w.rotation_euler = (math.radians(90), 0, 0)
        out.append(w)
    return out

def crystals(cx, cy, n, color, size=0.6, seed=1):
    rng = random.Random(seed)
    m = flat_material(f"crystal_{color}", color, 0.08, 0.0, emit=0.8)
    try:
        bsdf = next(nd for nd in m.node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Transmission Weight"].default_value = 0.4
    except Exception:
        pass
    out = []
    for i in range(n):
        a = rng.uniform(0, 6.28); r = rng.uniform(0, size * 0.8)
        base = Vector((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.7, 0))
        tip = base + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.2, 0.2), rng.uniform(0.5, 1.0))) * size * 1.3
        out.append(rod(base, tip, size * rng.uniform(0.12, 0.2), m, 0.0, 6))
    return out

def mine(kind):
    m = mats()
    out = []
    if kind in ("ore_mine", "gold_mine"):
        out += rock_hill(0, 3.0, 2.4, 1.3, 2.6, m["rock"], 3 if kind == "ore_mine" else 4)
        out += rock_hill(-1.9, 2.0, 0.8, 0.7, 0.9, m["rock"], 13)
        out += mine_entrance(0, 1.75, 1.2, 1.4)
        out += [rod((-0.5, 1.6, 0.0), (0.5, 0.6, 0.02), 0.035, M("darksteel")), rod((-0.3, 1.75, 0.0), (0.7, 0.75, 0.02), 0.035, M("darksteel"))]
        load = M("steel", (0.35, 0.33, 0.32)) if kind == "ore_mine" else M("gold")
        out += cart(1.5, 1.0, load)
        if kind == "gold_mine":
            out += [ball((-1.3 + i * 0.2, 1.0, 0.1), 0.12, M("gold"), 1, 1, 0.6) for i in range(5)]
    elif kind == "sawmill":
        out += house(0.2, 2.8, 2.6, 1.6, 1.4, m["wood"], m["rroof"], windows=(1.0, 0.75, 0.35))
        for i in range(3):
            for j in range(3 - i):
                lg = rod((-2.4, 1.0 + j * 0.28 + i * 0.14, 0.14 + i * 0.25), (-1.0, 1.0 + j * 0.28 + i * 0.14, 0.14 + i * 0.25), 0.13, ph_material("bark_brown_02", 2.0))
                out.append(lg)
        blade = prim("cyl", (1.7, 1.6, 0.8), (0.55, 0.55, 0.03), mat=M("steel"), vertices=32, bake=True)
        blade.rotation_euler = (math.radians(90), 0, 0)
        out.append(blade)
    elif kind == "crystal_cavern":
        out += rock_hill(0, 3.0, 2.4, 1.3, 2.3, m["rock"], 5)
        out += mine_entrance(0, 1.75, 1.2, 1.4)
        out += crystals(-1.6, 1.4, 6, (0.95, 0.2, 0.25), 0.6, 2) + crystals(1.5, 1.6, 5, (0.95, 0.25, 0.3), 0.5, 3)
    elif kind == "gem_pond":
        water = flat_material("pond", (0.08, 0.3, 0.45), 0.05)
        out += [prim("cyl", (0, 2.2, 0.06), (2.2, 1.4, 0.06), mat=water, vertices=48, bake=True)]
        for k in range(14):
            a = k * 6.283 / 14
            out += [ball((math.cos(a) * 2.35, 2.2 + math.sin(a) * 1.55, 0.12), 0.32, m["rock"], 1.2, 1.0, 0.7, 2)]
        for i, c in enumerate([(0.2, 0.9, 0.3), (0.3, 0.4, 1.0), (1.0, 0.85, 0.2), (0.9, 0.2, 0.9)]):
            out += crystals(-1.2 + i * 0.8, 1.7 + (i % 2) * 0.6, 2, c, 0.35, 10 + i)
    elif kind == "alchemist_lab":
        out += round_tower(0, 2.8, 1.0, 2.6, m["stone"], m["rroof"], 1.4)
        out += house(1.6, 2.4, 1.4, 1.1, 1.0, m["plaster"], m["rroof"], windows=(0.5, 1.0, 0.5))
        out.append(rod((-0.6, 2.9, 2.0), (-0.6, 2.9, 3.6), 0.15, m["stone"]))
        for i, c in enumerate([(0.85, 0.85, 0.9), (0.4, 1.0, 0.5), (0.9, 0.4, 0.9)]):
            out.append(ball((-1.5 + i * 0.35, 1.2, 0.18), 0.17, M("glow", c)))
    elif kind == "sulfur_dune":
        sand = ph_material("sand_01", 0.7, tint=(1.0, 0.85, 0.3), tint_k=0.7, sat=1.5)
        out += rock_hill(0, 2.4, 2.6, 1.7, 1.2, sand, 7)
        out += crystals(-1.0, 1.4, 5, (1.0, 0.85, 0.1), 0.5, 4) + crystals(1.2, 1.7, 4, (1.0, 0.8, 0.1), 0.45, 5)
        smoke = M("ghost", (0.95, 0.9, 0.5))
        out += [ball((0.3 + i * 0.15, 2.6, 1.4 + i * 0.4), 0.3 + i * 0.1, smoke) for i in range(3)]
    return out

def shrine():
    m = mats()
    out = [prim("cyl", (0, 2.2, 0.15), (1.6, 1.6, 0.15), mat=m["stone"], vertices=32, bake=True)]
    for k in range(8):
        a = k * math.pi / 4
        out.append(rod((math.cos(a) * 1.3, 2.2 + math.sin(a) * 1.3, 0.3), (math.cos(a) * 1.3, 2.2 + math.sin(a) * 1.3, 2.0), 0.12, ph_material("marble_01", 1.0)))
    out.append(prim("cyl", (0, 2.2, 2.1), (1.5, 1.5, 0.12), mat=m["stone"], vertices=32, bake=True))
    dome = prim("sphere", (0, 2.2, 2.2), (1.45, 1.45, 1.0), mat=m["hroof"], segments=32, ring_count=16, bake=True)
    out.append(dome)
    out.append(ball((0, 2.2, 1.1), 0.35, M("glow", (0.4, 0.7, 1.0))))
    return out

def windmill():
    m = mats()
    out = [prim("cone", (0, 2.4, 1.4), (1, 1, 1), mat=m["stone"], vertices=24, radius1=1.0, radius2=0.7, depth=2.8)]
    out.append(prim("cone", (0, 2.4, 3.2), (1, 1, 1), mat=m["thatch"], vertices=24, radius1=0.95, radius2=0.0, depth=1.2))
    hub = Vector((0, 1.6, 2.6))
    for k in range(4):
        a = math.radians(20 + k * 90)
        d = Vector((math.cos(a), 0, math.sin(a)))
        out.append(rod(hub, hub + d * 2.2, 0.05, M("wood")))
        sail = box(tuple(hub + d * 1.3 + Vector((0, -0.05, 0))), (1.6, 0.03, 0.42), M("cloth", (0.9, 0.86, 0.75)), 0)
        sail.rotation_euler = (0, -a, 0)
        out.append(sail)
    out.append(box((0, 1.65, 0.45), (0.5, 0.1, 0.9), M("wood")))
    return out

def watchtower():
    m = mats()
    out = []
    for (x, y) in ((-0.8, 1.8), (0.8, 1.8), (-0.8, 3.2), (0.8, 3.2)):
        out.append(rod((x, y, 0), (x * 0.7, 2.5 + (y - 2.5) * 0.7, 3.2), 0.1, M("wood")))
    out.append(box((0, 2.5, 3.3), (1.6, 1.6, 0.15), m["wood"]))
    out += merlons(-0.8, 1.7, 0.8, 1.7, 3.35, 0.1, m["wood"], 0.25)
    out.append(prim("cone", (0, 2.5, 4.3), (1, 1, 1), mat=m["thatch"], vertices=4, radius1=1.3, radius2=0, depth=1.2, rot=(0, 0, math.radians(45))))
    out += banner(0, 2.5, 4.9, (0.8, 0.2, 0.15))
    return out

def dwelling():
    m = mats()
    out = house(0, 2.6, 2.4, 1.6, 1.3, m["wood"], m["thatch"], windows=(1.0, 0.75, 0.35))
    for x in (-2.4, -1.6, 1.6, 2.4):
        out.append(rod((x, 1.4, 0), (x, 1.4, 0.6), 0.05, M("wood")))
    out.append(rod((-2.4, 1.4, 0.45), (-1.6, 1.4, 0.45), 0.035, M("wood")))
    out.append(rod((1.6, 1.4, 0.45), (2.4, 1.4, 0.45), 0.035, M("wood")))
    return out

def obelisk():
    m = mats()
    out = [box((0, 2.2, 0.15), (1.4, 1.4, 0.3), m["stone"])]
    ob = prim("cone", (0, 2.2, 1.9), (1, 1, 1), mat=ph_material("dark_rock", 0.8), vertices=4, radius1=0.42, radius2=0.18, depth=3.2, rot=(0, 0, math.radians(45)))
    out.append(ob)
    out.append(prim("cone", (0, 2.2, 3.65), (1, 1, 1), mat=M("glow", (0.4, 0.8, 1.0)), vertices=4, radius1=0.2, radius2=0, depth=0.35, rot=(0, 0, math.radians(45))))
    for z in (1.0, 1.6, 2.2):
        out.append(box((0, 2.2 - 0.3 + z * 0.03, z), (0.2, 0.02, 0.18), M("glow", (0.4, 0.8, 1.0))))
    return out

# ---------------------------------------------------------------------------------------------
# Pickups (one tile, centred at (0,1))
# ---------------------------------------------------------------------------------------------
def pile(kind):
    rng = random.Random(hash(kind) % 1000)
    out = []
    c = Vector((0, 1.0, 0))
    if kind == "wood":
        ends = flat_material("log_end", (0.85, 0.65, 0.4), 0.8)
        d = Vector((0.85, 0.5, 0)).normalized()
        for i in range(3):
            for j in range(3 - i):
                c0 = Vector((-0.25 + j * 0.24 + i * 0.12, 1.0 + j * 0.0, 0.12 + i * 0.21))
                c0 = Vector((0, 1.0, 0.12 + i * 0.21)) + Vector((-d.y, d.x, 0)) * ((j - (2 - i) / 2) * 0.24)
                out.append(rod(c0 - d * 0.55, c0 + d * 0.55, 0.11, ph_material("bark_brown_02", 2.0)))
                cap = prim("cyl", tuple(c0 - d * 0.56), (0.105, 0.105, 0.01), mat=ends, vertices=12, bake=True)
                cap.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
                out.append(cap)
    elif kind == "ore":
        for i in range(7):
            out.append(ball(c + Vector((rng.uniform(-0.45, 0.45), rng.uniform(-0.3, 0.3), 0.15)), rng.uniform(0.18, 0.3), ph_material("rock_face_03", 1.5, sat=0.4, bright=0.8), 1.1, 1.0, 0.8, 1))
    elif kind == "gold":
        gm = M("gold")
        for i in range(30):
            a = rng.uniform(0, 6.28); r = rng.uniform(0, 0.5)
            z = max(0.02, 0.35 - r * 0.6) * rng.uniform(0.3, 1.0)
            coin = prim("cyl", (math.cos(a) * r, 1.0 + math.sin(a) * r * 0.7, z), (0.1, 0.1, 0.02), mat=gm, vertices=12, bake=True)
            coin.rotation_euler = (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0)
            out.append(coin)
        out.append(ball(c + Vector((0, 0.05, 0.05)), 0.42, gm, 1.15, 0.9, 0.8, 2))
        sack = ball(c + Vector((0.35, 0.25, 0.3)), 0.3, M("leather", (0.55, 0.42, 0.25)), 1.0, 1.0, 1.1)
        out.append(sack)
        for k in range(3):
            out.append(box((-0.35 + k * 0.12, 0.8, 0.08 + k * 0.05), (0.32, 0.14, 0.1), gm, 0.3))
    elif kind == "mercury":
        glass = flat_material("flask", (0.75, 0.8, 0.85), 0.05, 0.6)
        for i, x in enumerate((-0.25, 0.25)):
            out.append(ball(c + Vector((x, 0.05 * i, 0.3)), 0.28, glass))
            out.append(rod(c + Vector((x, 0.05 * i, 0.5)), c + Vector((x, 0.05 * i, 0.8)), 0.08, glass))
            out.append(ball(c + Vector((x, 0.05 * i, 0.25)), 0.22, M("steel", (0.8, 0.82, 0.85))))
    elif kind == "sulfur":
        out += [ball(c + Vector((0, 0, 0.05)), 0.5, ph_material("sand_01", 0.7, tint=(1.0, 0.85, 0.3), tint_k=0.8, sat=1.6), 1.2, 0.9, 0.5, 2)]
        out += crystals(0, 1.0, 5, (1.0, 0.85, 0.15), 0.35, 9)
    elif kind == "crystal":
        out += crystals(0, 1.0, 6, (0.95, 0.15, 0.2), 0.45, 11)
    elif kind == "gems":
        for i, col in enumerate([(0.2, 0.9, 0.3), (0.3, 0.4, 1.0), (1.0, 0.85, 0.2), (0.9, 0.2, 0.9), (0.95, 0.2, 0.2)]):
            g = prim("ico", (rng.uniform(-0.4, 0.4), 1.0 + rng.uniform(-0.25, 0.25), 0.15), (0.17, 0.17, 0.14), mat=flat_material(f"gem{i}", col, 0.05, 0.0, emit=0.6), subdivisions=1)
            out.append(g)
    return out

def chest():
    wood = M("wood"); gold = M("gold")
    out = [box((0, 1.0, 0.3), (1.0, 0.65, 0.55), wood)]
    lid = prim("cyl", (0, 1.0, 0.58), (0.33, 0.5, 0.33), mat=wood, vertices=16, bake=True, rot=(0, math.radians(90), 0))
    out.append(lid)
    for x in (-0.35, 0.0, 0.35):
        out.append(box((x, 1.0, 0.45), (0.07, 0.68, 0.6), gold))
    out.append(box((0, 0.66, 0.5), (0.14, 0.03, 0.16), gold))
    return out

def campfire():
    out = []
    for k in range(5):
        a = k * 1.2566
        out.append(rod((math.cos(a) * 0.45, 1.0 + math.sin(a) * 0.35, 0.05), (0, 1.0, 0.35), 0.06, ph_material("bark_brown_02", 2.0)))
    for k in range(8):
        a = k * 0.785
        out.append(ball((math.cos(a) * 0.6, 1.0 + math.sin(a) * 0.45, 0.06), 0.11, ph_material("rock_face_03", 1.5), 1, 1, 0.7, 1))
    out.append(prim("cone", (0, 1.0, 0.45), (1, 1, 1), mat=M("glow", (1.0, 0.45, 0.08)), vertices=8, radius1=0.25, radius2=0, depth=0.6))
    out.append(prim("cone", (0, 1.0, 0.4), (1, 1, 1), mat=M("glow", (1.0, 0.8, 0.2)), vertices=8, radius1=0.14, radius2=0, depth=0.4))
    out.append(ball((0.7, 1.3, 0.25), 0.25, M("darksteel"), 1, 1, 0.9))
    return out

def artifact_pedestal():
    m = mats()
    out = [prim("cyl", (0, 1.0, 0.25), (0.5, 0.5, 0.25), mat=m["stone"], vertices=8, bake=True)]
    out.append(ball((0, 1.0, 0.85), 0.28, M("glow", (1.0, 0.85, 0.35))))
    out.append(prim("torus", (0, 1.0, 0.85), (1, 1, 1), mat=M("gold"), major_radius=0.38, minor_radius=0.04, rot=(math.radians(70), 0, 0)))
    return out

# ---------------------------------------------------------------------------------------------
# Map heroes (mounted, 3/4 view, facing right)
# ---------------------------------------------------------------------------------------------
def map_hero(faction):
    if faction == "haven":
        hobjs, an, saddle = horse((0.92, 0.9, 0.86), caparison=(0.12, 0.25, 0.75))
        objs, a = humanoid({"pose": "ride", "bulk": 1.1, "legs": False, "clothes": (0.5, 0.52, 0.56)})
        rider = objs + breastplate(a, M("steel"), bk=1.1) + helmet(a, "great", M("steel"), plume=(0.95, 0.8, 0.25)) + cape(a, M("cloth", (0.12, 0.25, 0.75)), length=0.7)
        rider += banner(a["hand_n"].x, a["hand_n"].y, a["hand_n"].z, (0.12, 0.25, 0.75), 0.5)[1:]
        rider.append(rod(a["hand_n"] + Vector((0, 0, -0.4)), a["hand_n"] + Vector((0, 0, 1.4)), 0.025, M("wood")))
    else:
        hobjs, an, saddle = horse((0.08, 0.07, 0.08), caparison=(0.25, 0.05, 0.3), mane=(0.02, 0.02, 0.02), eyes=(0.4, 1.0, 0.5))
        objs, a = humanoid({"pose": "ride", "bulk": 1.05, "legs": False, "clothes": (0.08, 0.06, 0.1)})
        rider = objs + helmet(a, "hood", M("cloth", (0.12, 0.05, 0.16))) + cape(a, M("cloth", (0.18, 0.04, 0.22)), length=0.8, width=0.55)
        rider += staff({"hand_n": a["hand_n"] + Vector((0, 0, -0.9))}, 0.9, orb=(0.4, 1.0, 0.5), top_skull=True)
    off = saddle - a["pelvis"] + Vector((0, 0, 0.12))
    for o in rider:
        o.location += off
    for side in (-1, 1):
        hip = a["pelvis"] + off + Vector((0.05, side * 0.13, -0.02))
        knee = hip + Vector((0.25, side * 0.12, -0.25))
        foot = knee + Vector((-0.05, 0, -0.42))
        rider += [rod(hip, knee, 0.08, M("steel" if faction == "haven" else "cloth", None if faction == "haven" else (0.08, 0.06, 0.1)), 0.07), rod(knee, foot, 0.07, M("leather"), 0.055)]
    return hobjs + rider

# ---------------------------------------------------------------------------------------------
JOBS = {
    "map/town_haven.png": town_haven, "map/town_necropolis.png": town_necropolis,
    "map/sawmill.png": lambda: mine("sawmill"), "map/ore_mine.png": lambda: mine("ore_mine"), "map/gold_mine.png": lambda: mine("gold_mine"),
    "map/crystal_cavern.png": lambda: mine("crystal_cavern"), "map/gem_pond.png": lambda: mine("gem_pond"),
    "map/alchemist_lab.png": lambda: mine("alchemist_lab"), "map/sulfur_dune.png": lambda: mine("sulfur_dune"),
    "map/shrine.png": shrine, "map/windmill.png": windmill, "map/watchtower.png": watchtower,
    "map/dwelling_neutral.png": dwelling, "map/obelisk.png": obelisk,
    "map/chest.png": chest, "map/campfire.png": campfire, "map/artifact.png": artifact_pedestal,
}
for _r in ("wood", "ore", "gold", "mercury", "sulfur", "crystal", "gems"):
    JOBS[f"map/res_{_r}.png"] = (lambda r=_r: pile(r))

def render_map_object(path):
    clear_objects()
    objs = JOBS[path]()
    camera("map")
    set_key(azimuth_deg=-108, elevation_deg=52, energy=4.2)
    shadow_catcher(40)
    frame_fixed(objs)
    return render(path)

def render_map_hero(faction):
    clear_objects()
    objs = map_hero(faction)
    for o in objs:
        o.location.y += 1.0  # stand in the middle of the tile
    camera("map")
    set_key(azimuth_deg=-108, elevation_deg=52, energy=4.2)
    shadow_catcher(40)
    frame_fixed(objs)
    return render(f"heroes/map_{faction}.png")

def render_battle_hero(faction):
    clear_objects()
    objs = map_hero(faction)
    camera("side")
    set_key(azimuth_deg=-60, elevation_deg=55, energy=4.5)
    shadow_catcher(40)
    frame_fixed(objs, ppu=150, pad=0.08)
    return render(f"heroes/battle_{faction}.png")

# ---------------------------------------------------------------------------------------------
# Hero portraits (helmed / hooded busts)
# ---------------------------------------------------------------------------------------------
HERO_LOOKS = {
    "sir_aldric":       {"armor": "steel", "helm": "great", "plume": (0.95, 0.8, 0.25), "cape": (0.12, 0.25, 0.75)},
    "lady_seraphine":   {"armor": None, "robe": (0.95, 0.93, 0.88), "helm": "hood", "hood": (0.95, 0.93, 0.88), "crown": True, "eyes": (0.6, 0.85, 1.0)},
    "lord_gareth":      {"armor": "steel", "helm": "sallet", "cape": (0.6, 0.08, 0.08)},
    "brother_tomas":    {"armor": None, "robe": (0.45, 0.3, 0.16), "helm": "hood", "hood": (0.45, 0.3, 0.16), "eyes": (1.0, 0.85, 0.5)},
    "lord_morthis":     {"armor": "darksteel", "helm": "horned", "cape": (0.35, 0.02, 0.04), "eyes": (1.0, 0.2, 0.1)},
    "vesna_nightshade": {"armor": None, "robe": (0.25, 0.06, 0.3), "helm": "hood", "hood": (0.25, 0.06, 0.3), "eyes": (0.4, 1.0, 0.5)},
    "kragor_the_pale":  {"armor": "darksteel", "helm": "great", "plume": (0.6, 0.05, 0.05), "cape": (0.1, 0.1, 0.12), "eyes": (1.0, 0.3, 0.1)},
    "ilsa_grimveil":    {"armor": None, "robe": (0.06, 0.05, 0.08), "helm": "hood", "hood": (0.06, 0.05, 0.08), "crown": True, "eyes": (0.8, 0.4, 1.0)},
}

def hero_bust(hid):
    lk = HERO_LOOKS[hid]
    objs, a = humanoid({"pose": "idle", "legs": False, "bulk": 1.1, "clothes": lk.get("robe", (0.3, 0.3, 0.32))})
    if lk.get("armor"):
        objs += breastplate(a, M(lk["armor"]), bk=1.15)
    else:
        objs += robe(a, M("cloth", lk["robe"]), length=0.6, flare=1.3)
    hm = M(lk["armor"]) if lk.get("armor") else M("cloth", lk["hood"])
    objs += helmet(a, lk["helm"], hm, plume=lk.get("plume"))
    if lk.get("crown"):
        objs += helmet(a, "crown", M("gold"))
    if lk.get("cape"):
        objs += cape(a, M("cloth", lk["cape"]), length=0.6, width=0.5)
    if lk.get("eyes"):
        objs += [ball(a["head"] + Vector((0.13, y, 0.02)), 0.02, M("glow", lk["eyes"])) for y in (-0.045, 0.045)]
        for o in objs[-2:]:
            o["portrait"] = True
    return objs

def render_hero_portrait(hid):
    clear_objects()
    objs = hero_bust(hid)
    shadow_catcher(40)
    return render_portrait([o for o in objs if o.get("portrait")], f"heroes/portraits/{hid}.png", 256)
