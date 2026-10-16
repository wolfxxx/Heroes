"""Adventure-map props: trees, rocks, mountains, bushes, flowers. Requires studio.py loaded first."""

def leaf_material(name, dark, light, hi):
    """Foliage: voronoi leaf clumps with dark crevices and sunlit tips."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 26
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 4
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.0; els[0].color = (*light, 1)
    els[1].position = 0.75; els[1].color = (*dark, 1)
    e = els.new(0.35); e.color = (*hi, 1)
    nt.links.new(vor.outputs["Distance"], ramp.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 0.5
    nt.links.new(ramp.outputs[0], mix.inputs[6])
    nt.links.new(noise.outputs["Color"], mix.inputs[7])
    hsv = nt.nodes.new("ShaderNodeHueSaturation")
    hsv.inputs["Value"].default_value = 1.25
    hsv.inputs["Saturation"].default_value = 1.25
    nt.links.new(mix.outputs[2], hsv.inputs["Color"])
    nt.links.new(hsv.outputs[0], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.9
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.8
    try:
        bsdf.inputs["Subsurface Weight"].default_value = 0.15
    except Exception:
        pass
    return m

def _canopy(center, radius, n, rng, mat, squash=0.8):
    parts = []
    for i in range(n):
        a = rng.uniform(0, 6.283)
        r = radius * rng.uniform(0.15, 0.8)
        c = (center[0] + math.cos(a) * r, center[1] + math.sin(a) * r, center[2] + rng.uniform(-0.35, 0.5) * radius)
        s = radius * rng.uniform(0.32, 0.5)
        o = prim("ico", c, (s, s, s * squash), mat=mat, subdivisions=3)
        displace(o, strength=s * 0.45, scale=0.18, seed=rng.randint(1, 999), subdiv=1, kind="VORONOI")
        smooth(o)
        parts.append(o)
    return parts

def _trunk(height, r0, mat, lean=(0, 0)):
    o = prim("cone", (0, 0, height / 2), (1, 1, 1), mat=mat, vertices=10, radius1=r0, radius2=r0 * 0.45, depth=height)
    o.rotation_euler = (lean[0], lean[1], 0)
    smooth(o)
    return o

def tree_oak(seed):
    rng = random.Random(seed)
    bark = ph_material("bark_brown_02", 2.0, sat=0.9)
    tones = [(0.1, 0.33, 0.05), (0.15, 0.38, 0.06), (0.08, 0.3, 0.07)]
    leaves = leaf_material(f"oak_leaves_{seed % 3}", (0.015, 0.07, 0.01), tones[seed % 3], (0.45, 0.6, 0.12))
    h = rng.uniform(1.6, 2.2)
    objs = [_trunk(h, 0.22, bark, (rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08)))]
    objs += _canopy((0, 0, h + 0.55), rng.uniform(1.1, 1.4), rng.randint(14, 20), rng, leaves)
    return objs

def tree_pine(seed, snowy=False):
    rng = random.Random(seed)
    bark = ph_material("bark_brown_02", 2.0, sat=0.8)
    if snowy:
        needles = _snow_mix_material(f"pine_snow_{seed % 2}", (0.05, 0.16, 0.08))
    else:
        needles = noise_material(f"pine_needles_{seed % 2}", (0.03, 0.12, 0.05), (0.1, 0.28, 0.1) if seed % 2 else (0.12, 0.3, 0.08), scale=14, bump=0.8)
    h = rng.uniform(3.2, 4.0)
    objs = [_trunk(h * 0.5, 0.16, bark)]
    tiers = rng.randint(4, 5)
    for i in range(tiers):
        f = i / tiers
        r = (1.25 - f * 0.95) * rng.uniform(0.9, 1.05)
        z = 0.7 + f * (h - 0.9)
        o = prim("cone", (0, 0, z + r * 0.5), (1, 1, 1), mat=needles, vertices=14, radius1=r, radius2=0.02, depth=r * 1.25)
        displace(o, strength=0.12, scale=0.25, seed=rng.randint(1, 999), subdiv=2)
        smooth(o)
        objs.append(o)
    return objs

def tree_dead(seed):
    rng = random.Random(seed)
    bark = ph_material("bark_willow_02", 2.0, sat=0.5, bright=0.8)
    objs = []
    def branch(base, direction, length, radius, depth):
        end = base + direction.normalized() * length
        mid = (base + end) / 2
        o = prim("cone", mid, (1, 1, 1), mat=bark, vertices=8, radius1=radius, radius2=radius * 0.55, depth=length)
        o.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
        smooth(o)
        objs.append(o)
        if depth > 0:
            for k in range(rng.randint(2, 3)):
                nd = (direction.normalized() + Vector((rng.uniform(-0.9, 0.9), rng.uniform(-0.9, 0.9), rng.uniform(0.0, 0.6)))).normalized()
                branch(end, nd, length * rng.uniform(0.5, 0.7), radius * 0.55, depth - 1)
    branch(Vector((0, 0, 0)), Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), 1)), 1.8, 0.2, 3)
    return objs

def _snow_mix_material(name, base):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 12
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(sep.outputs["Z"], add.inputs[0])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 0.4
    nt.links.new(noise.outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], add.inputs[1])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.55
    ramp.color_ramp.elements[0].color = (*base, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.92, 0.95, 1.0, 1)
    nt.links.new(add.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    return m

def rock(seed, size=1.0, mossy=False):
    rng = random.Random(seed)
    mat = ph_material("rock_face_03" if not mossy else "mossy_rock", 1.5, sat=0.9)
    objs = []
    for i in range(rng.randint(1, 3)):
        s = size * rng.uniform(0.4, 0.8) * (1.0 if i == 0 else 0.6)
        c = (rng.uniform(-0.5, 0.5) * size * (i > 0), rng.uniform(-0.4, 0.4) * size * (i > 0), s * 0.35)
        o = prim("ico", c, (s * rng.uniform(1.0, 1.4), s * rng.uniform(0.8, 1.2), s * rng.uniform(0.6, 0.9)), mat=mat, subdivisions=3)
        o.rotation_euler = (0, 0, rng.uniform(0, 6.28))
        displace(o, strength=s * 0.35, scale=0.6, seed=rng.randint(1, 999), subdiv=1, kind="VORONOI")
        objs.append(o)
    return objs

def mountain(seed, snowy=False):
    import mathutils.noise as mn
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=120, y_subdivisions=90, size=1)
    o = bpy.context.active_object
    o.scale = (8, 6, 1)
    bpy.ops.object.transform_apply(scale=True)
    me = o.data
    peaks = [(rng.uniform(-2.2, 2.2), rng.uniform(-0.4, 1.2), rng.uniform(4.5, 7.0), rng.uniform(1.3, 1.9)) for _ in range(rng.randint(3, 4))]
    for v in me.vertices:
        x, y = v.co.x, v.co.y
        hgt = 0.0
        for (px, py, ph, pr) in peaks:
            d = math.hypot((x - px) / 1.15, (y - py))
            hgt = max(hgt, ph * max(0.0, 1.0 - d / (pr * 1.6)) ** 1.15)
        ridge = 1.0 - abs(mn.noise(Vector((x * 1.1 + seed, y * 1.1, 0))))
        hgt *= 0.65 + 0.55 * ridge ** 2
        hgt += mn.noise(Vector((x * 3.0 + seed, y * 3.0, 1))) * 0.45 * min(1.0, hgt / 2)
        edge = min(1.0, (4.0 - abs(x)) / 1.0, (3.0 - abs(y)) / 1.0)
        v.co.z = max(0.0, hgt * max(0.0, edge))
    smooth(o)
    assign(o, _mountain_material(f"mountain_mat_{int(snowy)}", snowy))
    o.name = "Mountain"
    bm = bmesh.new(); bm.from_mesh(me)
    flat = [f for f in bm.faces if all(v.co.z < 0.12 for v in f.verts)]
    bmesh.ops.delete(bm, geom=flat, context="FACES")
    bm.to_mesh(me); bm.free()
    return [o]

def _mountain_material(name, snowy):
    m = bpy.data.materials.get(name)
    if m:
        return m
    rockm = ph_material("rock_face_03", 0.6, sat=0.8)
    m = rockm.copy()
    m.name = name
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    rock_col = bsdf.inputs["Base Color"].links[0].from_socket
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    sepn = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sepn.inputs[0])
    grass_mix = nt.nodes.new("ShaderNodeMix"); grass_mix.data_type = "RGBA"
    gr = nt.nodes.new("ShaderNodeMapRange")
    gr.inputs["From Min"].default_value = 0.1; gr.inputs["From Max"].default_value = 0.9
    gr.inputs["To Min"].default_value = 1.0; gr.inputs["To Max"].default_value = 0.0
    nt.links.new(sep.outputs["Z"], gr.inputs["Value"])
    nt.links.new(gr.outputs[0], grass_mix.inputs[0])
    nt.links.new(rock_col, grass_mix.inputs[6])
    grass_mix.inputs[7].default_value = (0.12, 0.2, 0.06, 1) if not snowy else (0.45, 0.47, 0.5, 1)
    col = grass_mix.outputs[2]
    snow_amt = nt.nodes.new("ShaderNodeMath"); snow_amt.operation = "MULTIPLY"
    hz = nt.nodes.new("ShaderNodeMapRange")
    hz.inputs["From Min"].default_value = 3.6 if not snowy else 1.0
    hz.inputs["From Max"].default_value = 4.6 if not snowy else 2.0
    nt.links.new(sep.outputs["Z"], hz.inputs["Value"])
    nz = nt.nodes.new("ShaderNodeMapRange")
    nz.inputs["From Min"].default_value = 0.45; nz.inputs["From Max"].default_value = 0.7
    nt.links.new(sepn.outputs["Z"], nz.inputs["Value"])
    nt.links.new(hz.outputs[0], snow_amt.inputs[0]); nt.links.new(nz.outputs[0], snow_amt.inputs[1])
    snow_mix = nt.nodes.new("ShaderNodeMix"); snow_mix.data_type = "RGBA"
    nt.links.new(snow_amt.outputs[0], snow_mix.inputs[0])
    nt.links.new(col, snow_mix.inputs[6])
    snow_mix.inputs[7].default_value = (0.93, 0.95, 1.0, 1)
    nt.links.new(snow_mix.outputs[2], bsdf.inputs["Base Color"])
    return m

def bush(seed):
    rng = random.Random(seed)
    leaves = leaf_material(f"bush_leaves_{seed % 2}", (0.015, 0.07, 0.01), (0.2, 0.42, 0.06) if seed % 2 else (0.28, 0.4, 0.08), (0.45, 0.6, 0.15))
    return _canopy((0, 0, 0.35), 0.75, rng.randint(8, 11), rng, leaves, squash=0.7)

def flowers(seed):
    rng = random.Random(seed)
    grass = noise_material("tuft", (0.1, 0.3, 0.05), (0.3, 0.55, 0.1), scale=10, bump=0.2)
    cols = [(0.95, 0.85, 0.2), (0.9, 0.25, 0.25), (0.95, 0.95, 0.95), (0.6, 0.35, 0.9)]
    objs = []
    base = prim("ico", (0, 0, 0.0), (0.9, 0.7, 0.18), mat=grass, subdivisions=3)
    displace(base, strength=0.08, scale=0.2, seed=rng.randint(1, 99), subdiv=1)
    objs.append(base)
    fm = [flat_material(f"flower_{i}", c, 0.5) for i, c in enumerate(cols)]
    pick = rng.sample(range(4), 2)
    for i in range(28):
        a = rng.uniform(0, 6.28); r = rng.uniform(0, 0.8)
        o = prim("ico", (math.cos(a) * r, math.sin(a) * r * 0.75, 0.15), (0.07, 0.07, 0.05), mat=fm[pick[i % 2]], subdivisions=1)
        objs.append(o)
    return objs

# ---------------------------------------------------------------------------------------------
JOBS = {
    "tree_oak_1": lambda: tree_oak(1), "tree_oak_2": lambda: tree_oak(2), "tree_oak_3": lambda: tree_oak(3), "tree_oak_4": lambda: tree_oak(4),
    "tree_pine_1": lambda: tree_pine(1), "tree_pine_2": lambda: tree_pine(2), "tree_pine_3": lambda: tree_pine(3),
    "snow_pine_1": lambda: tree_pine(11, True), "snow_pine_2": lambda: tree_pine(12, True),
    "tree_dead_1": lambda: tree_dead(1), "tree_dead_2": lambda: tree_dead(2),
    "rock_1": lambda: rock(1, 1.0), "rock_2": lambda: rock(2, 1.1, True), "rock_3": lambda: rock(3, 0.8),
    "bush_1": lambda: bush(1), "bush_2": lambda: bush(2),
    "flowers_1": lambda: flowers(1), "flowers_2": lambda: flowers(2),
    "mountain_1": lambda: mountain(1), "mountain_2": lambda: mountain(2), "mountain_3": lambda: mountain(3),
    "mountain_snow_1": lambda: mountain(4, True), "mountain_snow_2": lambda: mountain(5, True),
}

JOBS_PROPS = JOBS

def render_prop(name, size=None):
    clear_objects()
    objs = JOBS_PROPS[name]()
    camera("map")
    shadow_catcher(40)
    frame_fixed(objs)
    return render(f"map/{name}.png")
