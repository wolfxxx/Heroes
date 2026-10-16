"""Procedural creatures & heroes for battle / map sprites. Requires studio.py loaded first.

Characters face +X (screen right in the side camera). Bodies are skin-modifier meshes (smooth
limbs from a joint graph) dressed with primitive armour, cloth, weapons, wings and mounts.
Objects tagged obj["portrait"] = True define the portrait framing.
"""

# ---------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------
def _textured_metal(name, pid, color, rough=0.3):
    """Poly Haven plate texture as wear/roughness detail on a coloured metal."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = ph_material(pid, 2.5, tint=color, tint_k=1.0, sat=0.0, bright=1.6).copy()
    m.name = name
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = 0.65  # full metal reflects the dim studio sky as black
    if not bsdf.inputs["Roughness"].links:
        bsdf.inputs["Roughness"].default_value = rough
    return m

def _textured_cloth(name, pid, color, scale=3.0, bright=1.7):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = ph_material(pid, scale, tint=color, tint_k=1.0, sat=1.3, bright=bright).copy()
    m.name = name
    return m

def M(kind, color=None):
    c = color
    # (Poly Haven fabric/metal textures were tried: rough_linen is blue-tinted and metal_plate
    # renders near-black at sprite scale, so materials stay procedural.)
    if kind == "steel":
        return flat_material(f"steel_{c}", c or (0.66, 0.68, 0.72), 0.3, 0.85)
    if kind == "darksteel":
        return flat_material(f"dsteel_{c}", c or (0.1, 0.1, 0.12), 0.35, 0.85)
    if kind == "gold":
        return flat_material("gold", (0.95, 0.68, 0.22), 0.25, 1.0)
    if kind == "cloth":
        return noise_material(f"cloth_{c}", tuple(x * 0.62 for x in c), c, scale=18, rough=0.85, bump=0.25)
    if kind == "skin":
        m = flat_material(f"skin_{c}", c or (0.86, 0.6, 0.46), 0.55)
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        try:
            bsdf.inputs["Subsurface Weight"].default_value = 0.25
        except Exception:
            pass
        return m
    if kind == "bone":
        return noise_material("bone", (0.62, 0.56, 0.42), (0.92, 0.88, 0.76), scale=22, rough=0.6, bump=0.3)
    if kind == "leather":
        return noise_material(f"leather_{c}", (0.18, 0.1, 0.05), c or (0.42, 0.26, 0.13), scale=14, rough=0.7, bump=0.2)
    if kind == "wood":
        return noise_material("wood", (0.25, 0.14, 0.06), (0.45, 0.28, 0.13), scale=30, rough=0.7, bump=0.1)
    if kind == "glow":
        return flat_material(f"glow_{c}", c, 0.3, 0.0, emit=2.6)
    if kind == "fur":
        return noise_material(f"fur_{c}", tuple(x * 0.65 for x in c), c, scale=40, rough=0.9, bump=0.5)
    if kind == "ghost":
        name = f"ghost_{c}"
        m = bpy.data.materials.get(name)
        if m:
            return m
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        for n in list(nt.nodes):
            if n.type != "OUTPUT_MATERIAL":
                nt.nodes.remove(n)
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (*c, 1)
        em.inputs["Strength"].default_value = 1.6
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.45
        inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
        nt.links.new(lw.outputs["Facing"], inv.inputs[1])
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 0.85
        nt.links.new(inv.outputs[0], mul.inputs[0])
        nt.links.new(mul.outputs[0], mix.inputs[0])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
        return m
    if kind == "membrane":
        return flat_material(f"membrane_{c}", c, 0.7)
    raise ValueError(kind)

# ---------------------------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------------------------
def V(*a):
    return Vector(a)

def skin_body(name, joints, edges, mat, subdiv=2, root=0):
    """joints: list of (Vector, radius) ; edges: list of index pairs."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([j[0] for j in joints], edges, [])
    o = bpy.data.objects.new(name, me)
    link(o)
    o.modifiers.new("skin", "SKIN")
    for i, (p, r) in enumerate(joints):
        rr = r if isinstance(r, (tuple, list)) else (r, r)
        me.skin_vertices[0].data[i].radius = rr
    me.skin_vertices[0].data[root].use_root = True
    s = o.modifiers.new("sub", "SUBSURF")
    s.levels = subdiv
    s.render_levels = subdiv
    o.data.materials.append(mat)
    try:
        o.modifiers["skin"].use_smooth_shade = True
    except Exception:
        pass
    return o

def rod(a, b, r, mat, r2=None, verts=12):
    a = Vector(a); b = Vector(b)
    d = b - a
    o = prim("cone", (a + b) / 2, (1, 1, 1), mat=mat, vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=d.length)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    smooth(o)
    return o

def ball(c, r, mat, sx=1, sy=1, sz=1, subd=3):
    o = prim("ico", tuple(c), (r * sx, r * sy, r * sz), mat=mat, subdivisions=subd)
    smooth(o)
    return o

def arc(center, radius, thick, a0, a1, mat, axis="Y", segs=24):
    """Curved tube (part of a torus) in the plane perpendicular to axis; angles in degrees."""
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thick, major_segments=segs, minor_segments=8)
    o = bpy.context.active_object
    bm = bmesh.new(); bm.from_mesh(o.data)
    dead = [v for v in bm.verts if not (math.radians(a0) <= (math.atan2(v.co.y, v.co.x) % (2 * math.pi)) <= math.radians(a1))]
    bmesh.ops.delete(bm, geom=dead, context="VERTS")
    bm.to_mesh(o.data); bm.free()
    if axis == "Y":
        o.rotation_euler = (math.radians(90), 0, 0)
    elif axis == "X":
        o.rotation_euler = (0, math.radians(90), 0)
    o.location = tuple(center)
    assign(o, mat)
    smooth(o)
    return o

def sheet(points_rows, mat, thickness=0.02, name="sheet"):
    """Quad sheet from a grid of points (rows of equal length) + solidify (capes, membranes)."""
    rows = len(points_rows); cols = len(points_rows[0])
    verts = [p for row in points_rows for p in row]
    faces = []
    for r in range(rows - 1):
        for c in range(cols - 1):
            i = r * cols + c
            faces.append((i, i + 1, i + cols + 1, i + cols))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new(name, me)
    link(o)
    so = o.modifiers.new("sol", "SOLIDIFY"); so.thickness = thickness
    sb = o.modifiers.new("sub", "SUBSURF"); sb.levels = 2; sb.render_levels = 2
    o.data.materials.append(mat)
    smooth(o)
    return o

def tag_portrait(*objs):
    for o in objs:
        o["portrait"] = True
    return objs

# ---------------------------------------------------------------------------------------------
# Humanoid
# ---------------------------------------------------------------------------------------------
POSES = {
    #          near hand (y<0)          far hand (y>0)        stride
    "idle":   ((0.05, -0.27, 0.95), (0.05, 0.27, 0.95), 0.12),
    "pike":   ((0.32, -0.2, 1.12), (0.12, 0.18, 1.22), 0.22),
    "sword":  ((0.3, -0.32, 1.12), (0.22, 0.26, 1.62), 0.2),
    "bow":    ((-0.05, -0.18, 1.42), (0.55, 0.12, 1.42), 0.22),
    "staff":  ((0.3, -0.25, 1.12), (0.12, 0.25, 1.0), 0.15),
    "claw":   ((0.55, -0.2, 1.28), (0.5, 0.2, 1.22), 0.3),
    "cast":   ((0.42, -0.25, 1.45), (0.1, 0.27, 1.05), 0.18),
    "ride":   ((0.35, -0.22, 1.12), (0.3, 0.22, 1.12), 0.0),
}

def humanoid(p):
    """p: dict(h, bulk, pose, skin, skeleton, hunch, legs=True). Returns (objects, anchors)."""
    h = p.get("h", 1.0); bk = p.get("bulk", 1.0)
    pose = POSES[p.get("pose", "idle")]
    hunch = p.get("hunch", 0.0)
    bone = p.get("skeleton", False)
    skin_m = M("bone") if bone else M("skin", p.get("skin"))
    mat = skin_m if bone or not p.get("clothes") else M("cloth", p["clothes"])
    lr = 0.05 if bone else 0.088  # limb radius (chunky, heroic proportions)
    def S(v):
        return Vector((v[0] * h, v[1] * h, v[2] * h))
    pelvis = S((0, 0, 0.98)); spine = S((0.02 + hunch * 0.1, 0, 1.2)); chest = S((0.04 + hunch * 0.25, 0, 1.42))
    neck = S((0.06 + hunch * 0.35, 0, 1.58))
    stride = pose[2]
    j = [(pelvis, 0.13 * bk), (spine, 0.12 * bk if not bone else 0.05), (chest, 0.16 * bk if not bone else 0.06), (neck, 0.06)]
    e = [(0, 1), (1, 2), (2, 3)]
    sh_n = chest + S((0, -0.19 * bk, 0.06)); sh_f = chest + S((0, 0.19 * bk, 0.06))
    anchors = {"pelvis": pelvis, "chest": chest, "neck": neck}
    for side, hand, sh in (("n", Vector(pose[0]), sh_n), ("f", Vector(pose[1]), sh_f)):
        hand = S(hand)
        hand = sh + (hand - sh) * 1.0
        elbow = (sh + hand) / 2 + S((-0.1, 0, -0.08))
        base = len(j)
        j += [(sh, lr * 1.1 * bk), (elbow, lr * bk), (hand, lr * 0.85)]
        e += [(2, base), (base, base + 1), (base + 1, base + 2)]
        anchors["hand_" + side] = hand
        anchors["shoulder_" + side] = sh
    if p.get("legs", True):
        for side, y, dx in (("n", -0.1, stride), ("f", 0.1, -stride * 0.7)):
            hip = pelvis + S((0, y * bk, -0.04))
            ankle = S((dx, y * 1.1 * bk, 0.08))
            knee = (hip + ankle) / 2 + S((0.06, 0, 0))
            toe = ankle + S((0.14, 0, -0.06))
            base = len(j)
            j += [(hip, lr * 1.5 * bk), (knee, lr * 1.15 * bk), (ankle, lr * 0.9), (toe, lr * 0.75)]
            e += [(0, base), (base, base + 1), (base + 1, base + 2), (base + 2, base + 3)]
            anchors["knee_" + side] = knee
            anchors["ankle_" + side] = ankle
    body = skin_body("Body", j, e, mat)
    head_c = neck + S((0.03, 0, 0.14))
    anchors["head"] = head_c
    objs = [body]
    if bone:
        skull = ball(head_c, 0.12 * h, mat, 1.05, 0.9, 1.1)
        jaw = ball(head_c + S((0.05, 0, -0.08)), 0.07 * h, mat, 1.2, 0.85, 0.6)
        eye_m = M("glow", (0.3, 1.0, 0.4)) if p.get("eyes") else flat_material("socket", (0.02, 0.02, 0.02), 0.9)
        eyes = [ball(head_c + S((0.1, y, 0.02)), 0.028 * h, eye_m) for y in (-0.045, 0.045)]
        # ribs
        for k in range(4):
            z = chest.z - 0.02 * h - k * 0.065 * h
            r = (0.14 - k * 0.012) * h
            objs.append(arc(Vector((chest.x, 0, z)), r, 0.012 * h, 200, 520 % 360 if False else 340, mat, axis="Z"))
        objs += [skull, jaw] + eyes
        tag_portrait(skull, jaw, *eyes)
    else:
        head = ball(head_c, 0.13 * h, skin_m, 1.0, 0.92, 1.1)
        nose = ball(head_c + S((0.115, 0, -0.01)), 0.03 * h, skin_m, 1.2, 0.7, 1.0)
        objs += [ball(anchors["hand_" + sd], 0.06 * h, skin_m) for sd in "nf"]
        if p.get("boots", True) and p.get("legs", True):
            bm_ = M("leather", (0.25, 0.15, 0.08))
            objs += [ball(anchors["ankle_" + sd] + S((0.05, 0, -0.03)), 0.075 * h, bm_, 1.5, 0.9, 0.9) for sd in "nf"]
        eye_m = M("glow", p["eyes"]) if p.get("eyes") else flat_material("eye", (0.05, 0.04, 0.03), 0.3)
        eyes = [ball(head_c + S((0.1, y, 0.025)), 0.017 * h, eye_m) for y in (-0.045, 0.045)]
        brow_m = flat_material("brow", (0.12, 0.07, 0.04), 0.8)
        brows = [ball(head_c + S((0.11, y, 0.06)), 0.03 * h, brow_m, 0.5, 1.3, 0.35) for y in (-0.05, 0.05)]
        mouth = ball(head_c + S((0.115, 0, -0.06)), 0.03 * h, flat_material("mouth", (0.35, 0.12, 0.1), 0.6), 0.4, 1.2, 0.3)
        objs += [head, nose, mouth] + eyes + brows
        tag_portrait(mouth, *brows)
        tag_portrait(head, nose, *eyes)
    return objs, anchors

# ---------------------------------------------------------------------------------------------
# Clothing / armour
# ---------------------------------------------------------------------------------------------
def torso_cover(a, mat, h=1.0, bk=1.0, skirt=0.35, flare=1.35):
    """Tabard/robe: chest + belly volume and a flared skirt down toward the knees."""
    c = a["chest"]; p = a["pelvis"]
    t = ball((c + p) / 2 + Vector((0.01, 0, 0.04 * h)), 0.2 * h * bk, mat, 0.9, 1.0, 1.35)
    t["portrait"] = True
    sk = prim("cone", (p.x, 0, p.z - skirt * h / 2), (1, 1, 1), mat=mat, vertices=24, radius1=0.2 * h * bk * flare, radius2=0.15 * h * bk, depth=skirt * h)
    smooth(sk)
    tag_portrait(t)
    return [t, sk]

def robe(a, mat, h=1.0, length=0.95, flare=2.0):
    c = a["chest"]; p = a["pelvis"]
    top = ball((c + p) / 2 + Vector((0.01, 0, 0.05 * h)), 0.19 * h, mat, 0.95, 1.05, 1.4)
    r = prim("cone", (p.x - 0.02, 0, p.z - (length * h) / 2 + 0.05), (1, 1, 1), mat=mat, vertices=28, radius1=0.17 * h * flare, radius2=0.16 * h, depth=length * h)
    displace(r, strength=0.03, scale=0.15, seed=5, subdiv=1)
    smooth(r)
    tag_portrait(top)
    return [top, r]

def breastplate(a, mat, h=1.0, bk=1.0):
    c = a["chest"]
    o = ball(c + Vector((0.02 * h, 0, -0.03 * h)), 0.19 * h * bk, mat, 0.95, 1.05, 1.15)
    pa = [ball(a["shoulder_" + s] + Vector((0, 0, 0.02 * h)), 0.085 * h * bk, mat, 1.1, 1.0, 0.85) for s in "nf"]
    tag_portrait(o, *pa)
    return [o] + pa

def greaves(a, mat, h=1.0):
    return [rod(a["knee_" + s] + Vector((0, 0, 0.02)), a["ankle_" + s], 0.07 * h, mat, 0.06 * h) for s in "nf"]

def gauntlets(a, mat, h=1.0):
    return [ball(a["hand_" + s], 0.055 * h, mat) for s in "nf"]

def helmet(a, kind, mat, h=1.0, plume=None):
    c = a["head"]
    out = []
    if kind == "kettle":
        dome = ball(c + Vector((0, 0, 0.04 * h)), 0.14 * h, mat, 1.0, 1.0, 0.85)
        brim = prim("cyl", tuple(c + Vector((0, 0, 0.02 * h))), (0.24 * h, 0.24 * h, 0.012 * h), mat=mat, vertices=32)
        out = [dome, brim]
    elif kind == "great":
        cyl = prim("cyl", tuple(c + Vector((0, 0, 0.02 * h))), (0.14 * h, 0.13 * h, 0.15 * h), mat=mat, vertices=24)
        top = ball(c + Vector((0, 0, 0.16 * h)), 0.14 * h, mat, 1.0, 0.93, 0.45)
        slit = prim("cube", tuple(c + Vector((0.135 * h, 0, 0.04 * h))), (0.01 * h, 0.09 * h, 0.012 * h), mat=flat_material("slit", (0.01, 0.01, 0.01), 0.9))
        out = [cyl, top, slit]
    elif kind == "sallet":
        dome = ball(c + Vector((-0.01 * h, 0, 0.03 * h)), 0.145 * h, mat, 1.1, 1.0, 0.95)
        tail = ball(c + Vector((-0.11 * h, 0, -0.04 * h)), 0.08 * h, mat, 1.3, 1.1, 0.5)
        out = [dome, tail]
    elif kind == "hood":
        hood = ball(c + Vector((-0.015 * h, 0, 0.02 * h)), 0.155 * h, mat, 1.05, 1.0, 1.15)
        tip = rod(c + Vector((-0.1 * h, 0, 0.08 * h)), c + Vector((-0.25 * h, 0, -0.05 * h)), 0.07 * h, mat, 0.01)
        face = ball(c + Vector((0.07 * h, 0, -0.01 * h)), 0.1 * h, flat_material("hood_dark", (0.02, 0.02, 0.025), 0.9), 0.6, 0.9, 1.0)
        out = [hood, tip, face]
    elif kind == "crown":
        band = prim("cyl", tuple(c + Vector((0, 0, 0.1 * h))), (0.12 * h, 0.12 * h, 0.03 * h), mat=mat, vertices=24)
        out = [band] + [prim("cone", tuple(c + Vector((math.cos(k) * 0.11 * h, math.sin(k) * 0.11 * h, 0.16 * h))), (1, 1, 1), mat=mat, vertices=6, radius1=0.025 * h, radius2=0, depth=0.08 * h) for k in [i * 1.047 for i in range(6)]]
    elif kind == "horned":
        dome = ball(c + Vector((0, 0, 0.03 * h)), 0.15 * h, mat, 1.0, 1.0, 1.0)
        horn_m = M("bone")
        out = [dome] + [rod(c + Vector((0, y * h, 0.1 * h)), c + Vector((-0.12 * h, y * 2.2 * h, 0.3 * h)), 0.03 * h, horn_m, 0.004) for y in (-0.1, 0.1)]
    if plume:
        out.append(ball(c + Vector((-0.06 * h, 0, 0.2 * h)), 0.08 * h, M("cloth", plume), 1.6, 0.5, 0.8))
    tag_portrait(*out)
    return out

def cape(a, mat, h=1.0, length=1.05, width=0.42):
    s_n = a["shoulder_n"]; s_f = a["shoulder_f"]
    rows = []
    for r in range(6):
        t = r / 5
        row = []
        for c in range(5):
            u = c / 4
            y = (u - 0.5) * width * h * (1 + t * 0.7)
            x = -0.14 * h - t * 0.28 * h + math.sin(u * 3.1 + t * 2) * 0.03 * h
            z = s_n.z + 0.02 * h - t * length * h
            row.append(Vector((x, y, z)))
        rows.append(row)
    return [sheet(rows, mat, 0.015 * h, "Cape")]

def belt(a, mat, h=1.0):
    p = a["pelvis"]
    return [prim("cyl", (p.x, 0, p.z + 0.06 * h), (0.17 * h, 0.17 * h, 0.03 * h), mat=mat, vertices=24)]

# ---------------------------------------------------------------------------------------------
# Weapons & gear
# ---------------------------------------------------------------------------------------------
def pike(a, h=1.0):
    hn, hf = a["hand_n"], a["hand_f"]
    d = Vector((1.0, 0.0, 0.42)).normalized()
    base = hn - d * 1.0 * h
    tip = hn + d * 1.7 * h
    shaft = rod(base, tip, 0.022 * h, M("wood"))
    head = rod(tip, tip + d * 0.28 * h, 0.04 * h, M("steel"), 0.0, 4)
    return [shaft, head]

def sword(hand, h=1.0, up=(0.35, 0, 1.0), length=0.85, mat=None, glow=None):
    d = Vector(up).normalized()
    grip = rod(hand - d * 0.1 * h, hand + d * 0.08 * h, 0.022 * h, M("leather"))
    side = d.cross(Vector((0, 1, 0))).normalized()
    guard = rod(hand + d * 0.08 * h - Vector((0, 0.11 * h, 0)), hand + d * 0.08 * h + Vector((0, 0.11 * h, 0)), 0.02 * h, M("gold"))
    bm = M("glow", glow) if glow else (mat or M("steel"))
    blade = prim("cube", tuple(hand + d * (0.08 + length / 2) * h), (0.012 * h, 0.04 * h, length / 2 * h), mat=bm)
    blade.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    tip = rod(hand + d * (0.08 + length) * h, hand + d * (0.08 + length + 0.1) * h, 0.04 * h, bm, 0.0, 4)
    tip.scale = (0.3, 1, 1)
    return [grip, guard, blade, tip]

def shield(a, color, emblem=None, h=1.0, kind="kite"):
    hn = a["hand_n"]
    c = hn + Vector((0.04 * h, -0.07 * h, 0.0))
    if kind == "round":
        s = prim("cyl", tuple(c), (0.26 * h, 0.26 * h, 0.025 * h), mat=M("cloth", color) if color else M("wood"), vertices=32)
        boss = ball(c + Vector((0, -0.03 * h, 0)), 0.06 * h, M("steel"))
        rim = prim("torus", tuple(c), (1, 1, 1), mat=M("steel"), major_radius=0.26 * h, minor_radius=0.015 * h)
        for o in (s, rim):
            o.rotation_euler = (math.radians(90), 0, math.radians(15))
        return [s, boss, rim]
    s = prim("cyl", tuple(c), (0.2 * h, 0.3 * h, 0.025 * h), mat=M("cloth", color), vertices=32)
    s.rotation_euler = (math.radians(90), 0, math.radians(12))
    tipo = prim("cone", tuple(c + Vector((0, 0, -0.3 * h))), (1, 1, 1), mat=M("cloth", color), vertices=24, radius1=0.2 * h, radius2=0.0, depth=0.3 * h)
    tipo.scale = (1, 0.12, 1)
    tipo.rotation_euler = (math.radians(180), 0, math.radians(12))
    out = [s, tipo]
    if emblem:
        e1 = prim("cube", tuple(c + Vector((0, -0.03 * h, -0.05 * h))), (0.025 * h, 0.01 * h, 0.2 * h), mat=M("gold") if emblem == "gold" else M("cloth", emblem))
        e2 = prim("cube", tuple(c + Vector((0, -0.03 * h, 0.04 * h))), (0.13 * h, 0.01 * h, 0.025 * h), mat=e1.data.materials[0])
        for e in (e1, e2):
            e.rotation_euler = (0, 0, math.radians(12))
        out += [e1, e2]
    return out

def bow(a, h=1.0):
    hf = a["hand_f"]
    b = arc(hf + Vector((-0.28 * h, 0, 0)), 0.42 * h, 0.018 * h, -55, 55, M("wood"), axis="Y")
    b.rotation_euler = (math.radians(90), 0, 0)
    top = hf + Vector((-0.28 * h + 0.42 * h * math.cos(math.radians(55)), 0, 0.42 * h * math.sin(math.radians(55))))
    bot = Vector((top.x, top.y, 2 * hf.z - top.z))
    string = [rod(top, a["hand_n"], 0.004 * h, flat_material("string", (0.85, 0.85, 0.8))), rod(a["hand_n"], bot, 0.004 * h, flat_material("string", (0.85, 0.85, 0.8)))]
    arrow = rod(a["hand_n"], hf + Vector((0.12 * h, 0, 0)), 0.008 * h, M("wood"))
    quiver = rod(a["chest"] + Vector((-0.18 * h, 0.05 * h, -0.2 * h)), a["chest"] + Vector((-0.25 * h, 0.05 * h, 0.2 * h)), 0.06 * h, M("leather"))
    return [b, arrow, quiver] + string

def staff(a, h=1.0, orb=(0.6, 0.85, 1.0), top_skull=False):
    hn = a["hand_n"]
    base = Vector((hn.x + 0.05 * h, hn.y, 0.02))
    top = Vector((hn.x + 0.08 * h, hn.y, 1.85 * h))
    out = [rod(base, top, 0.025 * h, M("wood"))]
    if top_skull:
        out.append(ball(top + Vector((0, 0, 0.08 * h)), 0.08 * h, M("bone"), 1.1, 0.9, 1.0))
        out += [ball(top + Vector((0.07 * h, y * h, 0.09 * h)), 0.02 * h, M("glow", orb)) for y in (-0.03, 0.03)]
        out.append(ball(top + Vector((0, 0, 0.08 * h)), 0.14 * h, M("ghost", orb)))
    else:
        out.append(ball(top + Vector((0, 0, 0.07 * h)), 0.07 * h, M("glow", orb)))
    return out

def scythe(a, h=1.0):
    hn, hf = a["hand_n"], a["hand_f"]
    base = Vector((hn.x - 0.2 * h, hn.y, 0.5 * h))
    top = Vector((hn.x + 0.25 * h, hn.y, 2.1 * h))
    blade = arc(top + Vector((-0.35 * h, 0, -0.05 * h)), 0.4 * h, 0.025 * h, 10, 90, M("darksteel"), axis="Y")
    blade.scale = (1, 1, 2.2)
    return [rod(base, top, 0.025 * h, M("wood")), blade]

def lance(a, h=1.0):
    hn = a["hand_n"]
    d = Vector((1, 0, 0.12)).normalized()
    return [rod(hn - d * 0.6 * h, hn + d * 2.4 * h, 0.07 * h, M("cloth", (0.85, 0.75, 0.3)), 0.012 * h),
            prim("cone", tuple(hn - d * 0.0), (1, 1, 1), mat=M("steel"), vertices=16, radius1=0.12 * h, radius2=0.03 * h, depth=0.2 * h)]

def halo(a, h=1.0):
    c = a["head"] + Vector((-0.05 * h, 0, 0.22 * h))
    t = prim("torus", tuple(c), (1, 1, 1), mat=M("glow", (1.0, 0.85, 0.4)), major_radius=0.13 * h, minor_radius=0.012 * h)
    t.rotation_euler = (math.radians(70), 0, math.radians(90))
    return [t]

# ---------------------------------------------------------------------------------------------
# Wings
# ---------------------------------------------------------------------------------------------
def feather_wings(a, mat, h=1.0, span=1.3, raise_deg=55):
    """Two wings rising up/back from the shoulder blades, made of layered feathers."""
    out = []
    base = a["chest"] + Vector((-0.12 * h, 0, 0.05 * h))
    for side in (-1, 1):
        root = base + Vector((0, side * 0.08 * h, 0))
        for row, (n, length, width) in enumerate(((11, 0.55, 0.07), (9, 0.36, 0.08), (7, 0.22, 0.09))):
            for i in range(n):
                t = i / (n - 1)
                ang = math.radians(raise_deg + 70 - t * 105)
                along = span * h * (0.25 + 0.75 * t) * (1 - row * 0.12)
                p = root + Vector((-math.cos(ang) * along * 0.55, side * 0.12 * h * (1 + t), math.sin(ang) * along * 0.6 + 0.1 * h))
                f = ball(p, length * h * (0.75 + 0.35 * t), mat, 0.32, 0.05 / max(length, 0.1), 1.0, subd=2)
                f.scale = (width * h * 2.2, 0.012 * h, length * h * (0.75 + 0.4 * t))
                f.rotation_euler = (0, math.radians(-25 - t * 75 + row * 10), 0)
                out.append(f)
    return out

def bat_wings(a, bone_m, mem_m, h=1.0, span=2.2, base=None):
    out = []
    base = base if base is not None else a["chest"] + Vector((-0.1 * h, 0, 0.05 * h))
    for side in (-1, 1):
        shoulder = base + Vector((0, side * 0.12 * h, 0))
        elbow = shoulder + Vector((-0.2 * span * h, side * 0.15 * h, 0.35 * span * h))
        wrist = elbow + Vector((0.15 * span * h, side * 0.05 * h, 0.3 * span * h))
        out += [rod(shoulder, elbow, 0.035 * h, bone_m, 0.025 * h), rod(elbow, wrist, 0.025 * h, bone_m, 0.018 * h)]
        tips = []
        for k, (dx, dz) in enumerate(((-0.75, 0.05), (-0.95, -0.35), (-0.8, -0.75), (-0.5, -1.0))):
            tip = wrist + Vector((dx * 0.55 * span * h, side * 0.08 * h, dz * 0.55 * span * h))
            out.append(rod(wrist, tip, 0.016 * h, bone_m, 0.006 * h))
            tips.append(tip)
        # membrane: fan between shoulder, wrist and finger tips
        pts = [shoulder + Vector((-0.1 * h, 0, -0.25 * h))] + tips[::-1] + [wrist]
        verts = [wrist] + pts
        me = bpy.data.meshes.new("membrane")
        faces = [(0, i, i + 1) for i in range(1, len(verts) - 1)]
        me.from_pydata([tuple(v) for v in verts], [], faces)
        o = bpy.data.objects.new("membrane", me)
        link(o)
        o.data.materials.append(mem_m)
        so = o.modifiers.new("sol", "SOLIDIFY"); so.thickness = 0.01
        out.append(o)
    return out

# ---------------------------------------------------------------------------------------------
# Quadrupeds
# ---------------------------------------------------------------------------------------------
def quadruped(mat, scale=1.0, neck_up=0.55, head_len=0.32, legs_mat=None, slim=1.0, stride=0.18, tail=True, bony=False):
    """Horse/lion body facing +X. Returns (objects, anchors)."""
    s = scale
    def P(x, y, z):
        return Vector((x * s, y * s, z * s))
    rr = 0.35 if bony else 1.0
    j = [(P(-0.5, 0, 1.12), 0.28 * slim * rr), (P(0.0, 0, 1.14), 0.3 * slim * rr), (P(0.45, 0, 1.2), 0.29 * slim * rr),
         (P(0.66, 0, 1.22 + neck_up * 0.55), 0.17 * rr), (P(0.78, 0, 1.22 + neck_up), 0.12 * rr)]
    e = [(0, 1), (1, 2), (2, 3), (3, 4)]
    anchors = {"back": P(0.0, 0, 1.18 + 0.27 * slim), "withers": P(0.35, 0, 1.45), "neck_top": P(0.75, 0, 1.22 + neck_up)}
    for name, (x, y, ph) in {"fn": (0.42, -0.14, 0.0), "ff": (0.42, 0.14, 1.0), "bn": (-0.45, -0.14, 1.0), "bf": (-0.45, 0.14, 0.0)}.items():
        swing = stride if ph < 0.5 else -stride
        top = P(x, y, 1.05)
        knee = P(x + swing * 0.5 + (0.05 if x < 0 else 0), y, 0.6)
        hoof = P(x + swing, y, 0.06)
        base = len(j)
        j += [(top, 0.15 * slim * rr), (knee, 0.075 * rr), (hoof, 0.07 * rr)]
        attach = 2 if x > 0 else 0
        e += [(attach, base), (base, base + 1), (base + 1, base + 2)]
        anchors["hoof_" + name] = hoof
    if tail:
        base = len(j)
        j += [(P(-0.7, 0, 1.15), 0.06 * rr), (P(-0.9, 0, 0.8), 0.05 * rr), (P(-0.95, 0, 0.5), 0.03 * rr)]
        e += [(0, base), (base, base + 1), (base + 1, base + 2)]
    body = skin_body("Quad", j, e, mat)
    head_root = P(0.75, 0, 1.22 + neck_up)
    muzzle = head_root + P(head_len, 0, -0.22)
    head = skin_body("Head", [(head_root, 0.13 * s * (0.5 if bony else 1)), (head_root + P(head_len * 0.5, 0, -0.1), 0.1 * s), (muzzle, 0.085 * s)], [(0, 1), (1, 2)], mat)
    anchors["head"] = head_root + P(head_len * 0.6, 0, -0.1)
    out = [body, head]
    if not bony:
        out += [ball(anchors["hoof_" + k] + P(0.01, 0, -0.01), 0.075 * s, flat_material("hoof", (0.08, 0.06, 0.05), 0.5), 1.2, 1.1, 0.7) for k in ("fn", "ff", "bn", "bf")]
    tag_portrait(head)
    return out, anchors

def horse(color=(0.92, 0.9, 0.86), caparison=None, mane=(0.25, 0.18, 0.12), skeletal=False, eyes=None):
    mat = M("bone") if skeletal else M("fur", color)
    objs, an = quadruped(mat, 1.05, bony=skeletal, head_len=0.42)
    head = an["head"]
    objs.append(rod(an["neck_top"] + Vector((-0.08, 0, 0.05)), an["withers"] + Vector((0, 0, 0.08)), 0.05, M("fur", mane) if not skeletal else M("bone"), 0.03))
    for y in (-0.05, 0.05):
        objs.append(rod(an["neck_top"] + Vector((0.02, y, 0.06)), an["neck_top"] + Vector((-0.04, y, 0.18)), 0.025, mat, 0.005))
    if eyes:
        objs += [ball(head + Vector((0.0, y, 0.06)), 0.025, M("glow", eyes)) for y in (-0.07, 0.07)]
    if caparison:
        cm = M("cloth", caparison)
        c = ball(an["back"] + Vector((-0.02, 0, -0.17)), 0.36, cm, 1.75, 0.97, 0.62)
        skirt = prim("cone", tuple(an["back"] + Vector((-0.02, 0, -0.38))), (1, 1, 1), mat=cm, vertices=32, radius1=0.38, radius2=0.34, depth=0.3)
        skirt.scale = (1.7, 1.0, 1)
        trim = prim("torus", tuple(an["back"] + Vector((-0.02, 0, -0.53))), (1.7, 1.0, 1), mat=M("gold"), major_radius=0.38, minor_radius=0.02)
        objs += [c, skirt, trim]
    saddle = an["back"] + Vector((0.0, 0, 0.02))
    return objs, an, saddle

def rider_on(objs_horse, saddle, rider_fn):
    """Seat a humanoid built by rider_fn(anchor_offset) on the saddle (legs straddling)."""
    return rider_fn(saddle)

# ---------------------------------------------------------------------------------------------
# Creature recipes
# ---------------------------------------------------------------------------------------------
BLUE = (0.08, 0.2, 0.75)
WHITE = (0.9, 0.88, 0.82)
RED = (0.6, 0.08, 0.06)
PURPLE = (0.32, 0.06, 0.45)
BLACK = (0.04, 0.035, 0.04)

def c_pikeman():
    objs, a = humanoid({"pose": "pike", "bulk": 1.05, "clothes": (0.35, 0.3, 0.25)})
    objs += torso_cover(a, M("cloth", BLUE))
    objs += helmet(a, "kettle", M("steel"))
    objs += greaves(a, M("steel")) + gauntlets(a, M("leather")) + belt(a, M("leather"))
    objs += pike(a)
    return objs

def c_archer():
    objs, a = humanoid({"pose": "bow", "bulk": 0.95, "clothes": (0.22, 0.32, 0.15)})
    objs += torso_cover(a, M("leather", (0.38, 0.27, 0.13)), skirt=0.3, flare=1.2)
    objs += helmet(a, "hood", M("cloth", (0.15, 0.35, 0.12)))
    objs += belt(a, M("leather")) + greaves(a, M("leather", (0.3, 0.2, 0.1)))
    objs += bow(a)
    return objs

def c_swordsman():
    objs, a = humanoid({"pose": "sword", "bulk": 1.12, "clothes": (0.5, 0.52, 0.56)})
    objs += torso_cover(a, M("cloth", BLUE), bk=1.1, skirt=0.3)
    objs += breastplate(a, M("steel"), bk=1.1) + greaves(a, M("steel")) + gauntlets(a, M("steel"))
    objs += helmet(a, "great", M("steel"), plume=(0.85, 0.1, 0.1))
    objs += cape(a, M("cloth", (0.55, 0.06, 0.06)))
    objs += sword(a["hand_f"], up=(0.25, 0, 1.0))
    objs += shield(a, BLUE, "gold")
    return objs

def c_monk():
    objs, a = humanoid({"pose": "cast", "bulk": 1.0, "legs": True, "clothes": (0.5, 0.3, 0.14)})
    objs += robe(a, M("cloth", (0.5, 0.3, 0.14)), flare=1.45)
    objs += [ball(a["chest"] + Vector((0.0, 0, 0.02)), 0.17, M("cloth", (0.85, 0.75, 0.45)), 1.0, 1.05, 0.6)]  # mantle
    objs += helmet(a, "hood", M("cloth", (0.5, 0.3, 0.14)))[:1]
    objs += belt(a, M("cloth", (0.6, 0.12, 0.08)))
    objs += [ball(a["hand_n"] + Vector((0.08, 0, 0.05)), 0.07, M("glow", (1.0, 0.85, 0.45)))]
    objs += staff({"hand_n": a["hand_f"]}, orb=(1.0, 0.9, 0.5))
    return objs

def c_angel():
    objs, a = humanoid({"pose": "sword", "h": 1.25, "bulk": 1.05, "skin": (0.95, 0.8, 0.66), "clothes": (0.95, 0.94, 0.9), "boots": False})
    objs += torso_cover(a, M("cloth", (0.92, 0.9, 0.84)), h=1.25, skirt=0.55, flare=1.6)
    objs += breastplate(a, M("gold"), h=1.25, bk=1.1) + greaves(a, M("gold"), 1.25) + gauntlets(a, M("gold"), 1.25)
    objs += belt(a, M("cloth", (0.15, 0.3, 0.8)), 1.25)
    objs += [ball(a["head"] + Vector((-0.04, 0, 0.06)), 0.16, M("cloth", (0.95, 0.8, 0.35)), 1.0, 1.0, 0.9)]  # golden hair
    objs += halo(a, 1.25)
    objs += feather_wings(a, M("cloth", (0.97, 0.96, 0.93)), 1.25, span=1.9)
    objs += sword(a["hand_f"], 1.25, up=(0.3, 0, 1.0), length=1.0, glow=(1.0, 0.6, 0.2))
    return objs

def c_griffin():
    body_m = M("fur", (0.72, 0.52, 0.25))
    objs, an = quadruped(body_m, 0.95, neck_up=0.5, head_len=0.3, slim=0.95, stride=0.22)
    # eagle head + beak replace horse head: white feathered ball
    head = an["head"]
    hd = ball(head + Vector((-0.08, 0, 0.05)), 0.16, M("fur", (0.95, 0.93, 0.88)), 1.2, 0.95, 1.0)
    beak = rod(head + Vector((0.06, 0, 0.02)), head + Vector((0.24, 0, -0.07)), 0.06, M("gold"), 0.005)
    eye = [ball(head + Vector((0.0, y, 0.1)), 0.022, flat_material("eye", (0.05, 0.04, 0.03), 0.3)) for y in (-0.09, 0.09)]
    neckf = ball(an["neck_top"] + Vector((-0.12, 0, -0.2)), 0.2, M("fur", (0.95, 0.93, 0.88)), 1.1, 1.0, 1.4)
    objs = [o for o in objs if o.name != objs[1].name] if False else objs
    objs[1].hide_render = True
    objs += [hd, beak, neckf] + eye
    tag_portrait(hd, beak, neckf, *eye)
    wings = feather_wings({"chest": an["back"] + Vector((0.32, 0, 0.0))}, M("fur", (0.5, 0.33, 0.15)), 1.1, span=1.5, raise_deg=60)
    return objs + wings

def c_cavalier():
    hobjs, an, saddle = horse((0.92, 0.9, 0.86), caparison=BLUE)
    # rider: torso placed on the saddle
    objs, a = humanoid({"pose": "ride", "bulk": 1.1, "legs": False, "clothes": (0.5, 0.52, 0.56)})
    off = saddle - a["pelvis"] + Vector((0, 0, 0.12))
    rider = objs + breastplate(a, M("steel"), bk=1.1) + gauntlets(a, M("steel")) + helmet(a, "great", M("steel"), plume=(0.95, 0.85, 0.3))
    rider += cape(a, M("cloth", (0.12, 0.25, 0.65)), length=0.7)
    rider += lance(a)
    legs = []
    for side in (-1, 1):
        hip = a["pelvis"] + Vector((0.05, side * 0.13, -0.02))
        knee = hip + Vector((0.25, side * 0.12, -0.25))
        foot = knee + Vector((-0.05, 0, -0.42))
        legs += [rod(hip, knee, 0.08, M("steel"), 0.07), rod(knee, foot, 0.07, M("steel"), 0.055)]
    for o in rider + legs:
        o.location += off
    return hobjs + rider + legs

def c_skeleton():
    objs, a = humanoid({"pose": "sword", "skeleton": True, "bulk": 0.9})
    objs += sword(a["hand_f"], up=(0.3, 0, 1.0), length=0.7, mat=M("steel", (0.45, 0.35, 0.25)))
    objs += shield(a, None, kind="round")
    objs += [prim("cone", tuple(a["pelvis"] + Vector((0, 0, -0.1))), (1, 1, 1), mat=M("cloth", (0.3, 0.22, 0.15)), vertices=10, radius1=0.17, radius2=0.12, depth=0.25)]
    return objs

def c_zombie():
    objs, a = humanoid({"pose": "claw", "skin": (0.45, 0.55, 0.38), "hunch": 0.6, "bulk": 1.1, "boots": False})
    objs += torso_cover(a, M("cloth", (0.3, 0.25, 0.18)), bk=1.05, skirt=0.4, flare=1.2)
    for o in objs[-2:]:
        displace(o, strength=0.04, scale=0.08, seed=3, subdiv=1)
    return objs

def c_ghost():
    m = flat_material("ghost_robe", (0.55, 0.8, 0.95), 0.6, 0.0, emit=0.9)
    try:
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Alpha"].default_value = 0.88
    except Exception:
        pass
    objs, a = humanoid({"pose": "claw", "legs": False, "skin": (0.6, 0.8, 0.9), "eyes": (0.6, 1.0, 1.0)})
    for o in objs:
        o.data.materials.clear(); o.data.materials.append(m)
    tail = skin_body("GhostRobe", [(a["neck"], 0.13), (a["chest"], 0.22), (a["pelvis"], 0.26), (a["pelvis"] + Vector((-0.15, 0, -0.35)), 0.2),
                                   (a["pelvis"] + Vector((-0.4, 0, -0.6)), 0.1), (a["pelvis"] + Vector((-0.65, 0, -0.68)), 0.02)],
                     [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)], m)
    displace(tail, strength=0.05, scale=0.2, seed=8, subdiv=0)
    hood = helmet(a, "hood", m)
    hood[2].data.materials.clear(); hood[2].data.materials.append(flat_material("hood_dark", (0.02, 0.02, 0.025), 0.9))
    out = objs + [tail] + hood + [ball(a["head"] + Vector((0.11, y, 0.02)), 0.025, M("glow", (0.5, 1.0, 1.0))) for y in (-0.04, 0.04)]
    for o in out:
        o.location.z += 0.45
    return out

def c_vampire():
    objs, a = humanoid({"pose": "sword", "skin": (0.88, 0.82, 0.8), "bulk": 1.0, "eyes": (1.0, 0.1, 0.1), "clothes": (0.06, 0.05, 0.06)})
    objs += torso_cover(a, M("cloth", BLACK), skirt=0.3, flare=1.1)
    objs += [ball(a["chest"] + Vector((0.06, 0, -0.02)), 0.12, M("cloth", (0.5, 0.05, 0.08)), 0.8, 0.9, 1.1)]
    objs += [ball(a["head"] + Vector((-0.03, 0, 0.06)), 0.13, M("cloth", (0.03, 0.03, 0.04)), 1.0, 1.0, 0.8)]  # slick hair
    c = cape(a, M("cloth", (0.45, 0.02, 0.05)), length=1.1, width=0.7)
    objs += c
    objs += sword(a["hand_f"], up=(0.4, 0, 1.0), length=0.75)
    objs += bat_wings(a, M("cloth", BLACK), M("membrane", (0.08, 0.02, 0.04)), 1.0, 1.0)
    return objs

def c_lich():
    objs, a = humanoid({"pose": "cast", "skeleton": True, "eyes": True, "bulk": 1.0})
    objs += robe(a, M("cloth", PURPLE), length=1.0, flare=1.6)
    objs += helmet(a, "crown", M("gold"))
    objs += [ball(a["hand_n"] + Vector((0.1, 0, 0.05)), 0.09, M("glow", (0.35, 1.0, 0.45)))]
    objs += staff({"hand_n": a["hand_f"]}, orb=(0.35, 1.0, 0.45), top_skull=True)
    return objs

def c_dread_knight():
    hobjs, an, saddle = horse((0.08, 0.07, 0.08), caparison=(0.15, 0.03, 0.05), mane=(0.02, 0.02, 0.02), eyes=(1.0, 0.25, 0.1))
    objs, a = humanoid({"pose": "ride", "bulk": 1.15, "legs": False, "clothes": (0.08, 0.08, 0.09)})
    off = saddle - a["pelvis"] + Vector((0, 0, 0.12))
    rider = objs + breastplate(a, M("darksteel"), bk=1.15) + gauntlets(a, M("darksteel")) + helmet(a, "horned", M("darksteel"))
    rider += cape(a, M("cloth", (0.35, 0.02, 0.04)), length=0.8, width=0.5)
    rider += [ball(a["head"] + Vector((0.13, y, 0.03)), 0.02, M("glow", (1.0, 0.2, 0.1))) for y in (-0.04, 0.04)]
    rider += scythe(a)
    legs = []
    for side in (-1, 1):
        hip = a["pelvis"] + Vector((0.05, side * 0.13, -0.02))
        knee = hip + Vector((0.25, side * 0.12, -0.25))
        foot = knee + Vector((-0.05, 0, -0.42))
        legs += [rod(hip, knee, 0.08, M("darksteel"), 0.07), rod(knee, foot, 0.07, M("darksteel"), 0.055)]
    for o in rider + legs:
        o.location += off
    return hobjs + rider + legs

def c_bone_dragon():
    bm = M("bone")
    s = 1.6
    def P(x, y, z):
        return Vector((x * s, y * s, z * s))
    # spine from tail to skull
    spine_pts = [P(-1.9, 0, 0.5), P(-1.5, 0, 0.75), P(-1.0, 0, 0.95), P(-0.5, 0, 1.15), P(0.0, 0, 1.25), P(0.45, 0, 1.3),
                 P(0.75, 0, 1.6), P(0.95, 0, 1.95), P(1.2, 0, 2.15)]
    j = [(p, 0.07 * s) for p in spine_pts]
    e = [(i, i + 1) for i in range(len(spine_pts) - 1)]
    objs = [skin_body("Spine", j, e, bm, root=4)]
    for k, p in enumerate(spine_pts[1:-1]):
        objs.append(ball(p + P(0, 0, 0.06), 0.05 * s, bm, 0.8, 0.8, 1.6))  # vertebra spikes
    for k in range(6):
        x = -0.55 + k * 0.17
        objs.append(arc(P(x, 0, 1.0), 0.34 * s * (1 - abs(k - 2.5) * 0.1), 0.03 * s, 200, 340, bm, axis="X"))
    skull = ball(P(1.32, 0, 2.15), 0.21 * s, bm, 1.5, 0.75, 0.7)
    jaw = rod(P(1.2, 0, 2.05), P(1.65, 0, 1.98), 0.06 * s, bm, 0.02 * s)
    horns = [rod(P(1.2, y, 2.25), P(0.95, y * 1.6, 2.5), 0.04 * s, bm, 0.005) for y in (-0.08, 0.08)]
    eyes = [ball(P(1.4, y, 2.2), 0.03 * s, M("glow", (0.3, 1.0, 0.45))) for y in (-0.08, 0.08)]
    objs += [skull, jaw] + horns + eyes
    tag_portrait(skull, jaw, *horns, *eyes)
    for (x, y, ph) in ((0.35, -0.2, 0), (0.35, 0.2, 1), (-0.55, -0.2, 1), (-0.55, 0.2, 0)):
        sw = 0.15 if ph == 0 else -0.12
        top = P(x, y, 1.15); knee = P(x + sw + 0.1, y * 1.1, 0.6); foot = P(x + sw * 1.6, y * 1.1, 0.04)
        objs += [rod(top, knee, 0.07 * s, bm, 0.05 * s), rod(knee, foot, 0.05 * s, bm, 0.035 * s), ball(knee, 0.06 * s, bm)]
        for t in (-0.06, 0.0, 0.06):
            objs.append(rod(foot, foot + P(0.14, t, -0.02), 0.012 * s, bm, 0.002))
    objs += bat_wings({"chest": P(0.2, 0, 1.3)}, bm, M("membrane", (0.22, 0.2, 0.16)), s, span=1.9)
    return objs

CREATURES = {
    "pikeman": c_pikeman, "archer": c_archer, "griffin": c_griffin, "swordsman": c_swordsman, "monk": c_monk,
    "cavalier": c_cavalier, "angel": c_angel, "skeleton": c_skeleton, "zombie": c_zombie, "ghost": c_ghost,
    "vampire": c_vampire, "lich": c_lich, "dread_knight": c_dread_knight, "bone_dragon": c_bone_dragon,
}

BATTLE_PPU = 150

def render_creature(cid, portrait=True):
    clear_objects()
    objs = CREATURES[cid]()
    objs = [o for o in objs if not o.hide_render]
    camera("side")
    shadow_catcher(40)
    set_key(azimuth_deg=-60, elevation_deg=55, energy=4.5)
    frame_fixed(objs, ppu=BATTLE_PPU, pad=0.08)
    render(f"creatures/{cid}.png")
    if portrait:
        render_portrait([o for o in objs if o.get("portrait")], f"creatures/portraits/{cid}.png")

def render_portrait(objs, path, size=256):
    sc = bpy.context.scene
    cam = camera("portrait")
    cam.rotation_euler = Euler((math.radians(82), 0, math.radians(52)), "XYZ")
    for o in sc.objects:
        if o.name == "ShadowCatcher":
            o.hide_render = True
    # head-and-shoulders: keep portrait parts whose centre lies near the top of the figure
    bpy.context.view_layer.update()
    def zc(o):
        pts = objects_bbox([o])
        return sum(p.z for p in pts) / max(1, len(pts))
    top = max(max(p.z for p in objects_bbox([o])) for o in objs)
    focus = [o for o in objs if zc(o) > top - 0.42] or objs
    frame(focus, (size, size), margin=0.55, shadow=False)
    out = render(path)
    for o in sc.objects:
        if o.name == "ShadowCatcher":
            o.hide_render = False
    return out
