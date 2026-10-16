"""Painted-looking 3D battlefields (1920x1080) and town-screen backdrops. Requires studio.py, props.py, figures.py.

The hex grid is drawn by the game over the open middle of the image: keep x in [-12, 12], y in [-7, 9]
free of props. Sky comes from a Poly Haven pure-sky HDRI.
"""

TERRAIN_TEX = {"grass": ("leafy_grass", (60, 125, 35), 0.5), "dirt": ("dirt_floor", (125, 95, 62), 0.35),
               "sand": ("sand_01", (235, 200, 130), 0.35), "snow": ("snow_02", (235, 242, 255), 0.3),
               "swamp": ("brown_mud_leaves_01", (70, 90, 45), 0.45)}
SKIES = {"grass": "kloofendal_48d_partly_cloudy_puresky", "dirt": "citrus_orchard_road_puresky", "sand": "sunflowers_puresky",
         "snow": "overcast_soil_puresky", "swamp": "mud_road_puresky", "haven": "kloofendal_48d_partly_cloudy_puresky",
         "necropolis": "belfast_sunset_puresky"}

def hdri(pid, strength=1.0, res="2k"):
    folder = os.path.join(TEX_CACHE, "hdri")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{pid}_{res}.hdr")
    if not os.path.exists(path):
        files = json.loads(_get(f"https://api.polyhaven.com/files/{pid}"))
        open(path, "wb").write(_get(files["hdri"][res]["hdr"]["url"]))
    w = bpy.context.scene.world
    nt = w.node_tree
    nt.nodes.clear()
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(path, check_existing=True)
    mp = None  # default vector input = view direction
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    nt.links.new(env.outputs[0], bg.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs[0], out.inputs[0])
    return mp

def ground_material(terrain, scale=0.22):
    """Same graded texture as the adventure map + large-scale colour variation to hide tiling."""
    name = f"ground_{terrain}"
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(ASSETS, "terrain", f"{terrain}.png"), check_existing=True)
    img.projection = "BOX"
    nt.links.new(mp.outputs[0], img.inputs[0])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.06
    noise.inputs["Detail"].default_value = 3
    nt.links.new(tc.outputs["Object"], noise.inputs[0])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value = 0.72
    ramp.inputs["To Max"].default_value = 1.18
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(img.outputs[0], mul.inputs[6])
    nt.links.new(ramp.outputs[0], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(img.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    return m

def ground(terrain, size=(90, 70)):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=160, y_subdivisions=120, size=1)
    g = bpy.context.active_object
    g.scale = (size[0], size[1], 1)
    bake_scale(g)
    g.location = (0, size[1] / 2 - 15, 0)
    import mathutils.noise as mn
    for v in g.data.vertices:
        wy = v.co.y + g.location.y
        far = max(0.0, (wy - 22) / 25.0)
        side = max(0.0, (abs(v.co.x) - 22) / 12.0)
        v.co.z = (mn.noise(Vector((v.co.x * 0.08, wy * 0.08, 0))) * 2.5 + 1.2) * min(1.0, far + side) ** 1.5 * 1.6
    smooth(g)
    assign(g, ground_material(terrain))
    return g

def scatter(builder_names, positions, rng, scale=(0.9, 1.3)):
    out = []
    for (x, y) in positions:
        name = rng.choice(builder_names)
        objs = JOBS[name]()
        s = rng.uniform(*scale)
        for o in objs:
            o.location = Vector((o.location.x * s + x, o.location.y * s + y, o.location.z * s))
            o.scale = (o.scale[0] * s, o.scale[1] * s, o.scale[2] * s)
        out += objs
    return out

def edge_positions(rng, n_side, n_back):
    pts = []
    for i in range(n_side):
        for side in (-1, 1):
            y = rng.uniform(-6, 30)
            pts.append((side * (rng.uniform(15, 19) + max(0, y) * 0.55), y))
    for i in range(n_back):
        x = rng.uniform(-45, 45)
        pts.append((x, rng.uniform(45, 70) if abs(x) < 26 else rng.uniform(28, 60)))
    return pts

def battle_camera():
    sc = bpy.context.scene
    cam = bpy.data.objects.get("BattleCam")
    if cam is None:
        cam = bpy.data.objects.new("BattleCam", bpy.data.cameras.new("BattleCam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.data.type = "PERSP"
    cam.data.lens = 24
    cam.data.clip_end = 1000
    cam.location = (0, -20, 11.0)
    cam.rotation_euler = Euler((math.radians(90 - 19), 0, 0), "XYZ")
    sc.camera = cam
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    return cam

def build_battlefield(terrain, seed=1):
    clear_objects(keep=("Key", "Rim"))
    rng = random.Random(seed)
    sc = bpy.context.scene
    sc.render.film_transparent = True  # sky is painted in afterwards (tools/art/sky.py)
    sc.cycles.samples = 128
    hdri(SKIES[terrain], 1.0 if terrain != "swamp" else 0.7)
    set_key(azimuth_deg=-125, elevation_deg=40, energy=4.0 if terrain not in ("snow", "swamp") else 2.5)
    ground(terrain, (160, 140))
    props = {"grass": ["tree_oak_1", "tree_oak_2", "tree_oak_3", "tree_pine_1", "bush_1", "bush_2", "rock_1"],
             "dirt": ["tree_dead_1", "tree_dead_2", "rock_1", "rock_3", "tree_pine_2", "bush_2"],
             "sand": ["rock_1", "rock_2", "rock_3", "tree_dead_1"],
             "snow": ["snow_pine_1", "snow_pine_2", "rock_1"],
             "swamp": ["tree_dead_1", "tree_dead_2", "bush_1", "tree_oak_4"]}[terrain]
    scatter(props, edge_positions(rng, 7, 16), rng, (1.1, 1.8))
    flat = {"grass": ["bush_1", "bush_2", "rock_3"], "dirt": ["rock_3", "rock_1"], "sand": ["rock_3"],
            "snow": ["rock_3"], "swamp": ["bush_2", "bush_1"]}[terrain]
    field = [(rng.uniform(-14, 14), rng.uniform(-6, 14)) for _ in range(7)]
    scatter(flat, field, rng, (0.6, 0.9))
    # ground variety: soft patches of another surface across the field
    patch_m = {"grass": ph_material("grass_path_2", 0.5, sat=0.8), "dirt": ph_material("brown_mud_leaves_01", 0.5),
               "sand": ph_material("rock_face_03", 0.4, sat=0.4, bright=1.3), "snow": ph_material("rock_face_03", 0.4, sat=0.5),
               "swamp": ph_material("brown_mud_leaves_01", 0.5, bright=0.7)}[terrain]
    import mathutils.noise as mn
    for k in range(9):
        x, y = rng.uniform(-15, 15), rng.uniform(-5, 18)
        p = prim("cyl", (x, y, 0.012), (rng.uniform(1.2, 3.0), rng.uniform(0.8, 1.8), 0.01), mat=patch_m, vertices=40, bake=True)
        for v in p.data.vertices:
            kk = 1.0 + 0.35 * mn.noise(Vector((v.co.x * 0.9 + k * 7, v.co.y * 0.9, 0)))
            v.co.x *= kk; v.co.y *= kk
    if terrain == "swamp":
        water = flat_material("swamp_water", (0.05, 0.08, 0.05), 0.05)
        for (x, y, r) in ((-17, 2, 3.5), (18, -3, 3.0), (6, 15, 4.0)):
            p = prim("cyl", (x, y, 0.02), (r, r * 0.7, 0.02), mat=water, vertices=40, bake=True)
    # distant mountains
    mtn = "mountain_snow_1" if terrain == "snow" else "mountain_1"
    for i, x in enumerate((-45, -22, 0, 25, 48)):
        objs = JOBS["mountain_snow_2" if terrain == "snow" and i % 2 else mtn]()
        haze = noise_material("far_mtn", (0.28, 0.33, 0.45), (0.45, 0.5, 0.62), scale=3, bump=0.2)
        for o in objs:
            o.data.materials.clear(); o.data.materials.append(haze)
        s = rng.uniform(3.0, 4.2)
        for o in objs:
            o.scale = (s, s, s * rng.uniform(0.9, 1.3))
            o.location = (x * 2.2 + rng.uniform(-8, 8), 95 + rng.uniform(0, 20), -1)
    battle_camera()

def render_battlefield(terrain, seed=1):
    build_battlefield(terrain, seed)
    return render(f"battle/bg_{terrain}.png")

# ---------------------------------------------------------------------------------------------
# Battle obstacles (side camera, transparent)
# ---------------------------------------------------------------------------------------------
def obstacle(kind):
    if kind == 1:
        return rock(21, 1.4)
    if kind == 2:
        bark = ph_material("bark_brown_02", 2.0)
        st = prim("cyl", (0, 0, 0.4), (0.55, 0.55, 0.4), mat=bark, vertices=16, bake=True)
        top = prim("cyl", (0, 0, 0.81), (0.53, 0.53, 0.01), mat=flat_material("log_end", (0.85, 0.65, 0.4), 0.8), vertices=16, bake=True)
        roots = [rod((0, 0, 0.15), (math.cos(a) * 0.9, math.sin(a) * 0.9, 0.0), 0.13, bark, 0.05) for a in (0.3, 2.0, 3.6, 5.0)]
        return [st, top] + roots
    if kind == 3:
        bark = ph_material("bark_willow_02", 2.0, sat=0.5, bright=0.8)
        out = [prim("cyl", (0, 0, 0.3), (0.45, 0.45, 0.3), mat=bark, vertices=14, bake=True)]
        out += [rod((0, 0, 0.5), (0.5, 0.2, 1.3), 0.14, bark, 0.04), rod((0, 0, 0.5), (-0.4, -0.1, 1.1), 0.12, bark, 0.03)]
        out += [rod((0, 0, 0.1), (math.cos(a) * 0.8, math.sin(a) * 0.8, 0.0), 0.12, bark, 0.04) for a in (0.5, 2.3, 4.0)]
        out += rock(35, 0.6)
        for o in out[-1:]:
            o.location.x += 0.7
        return out
    return rock(33, 1.2, True) + rock(34, 0.7)

def render_obstacle(kind):
    clear_objects()
    sc = bpy.context.scene
    sc.render.film_transparent = True
    objs = obstacle(kind)
    camera("side")
    bpy.data.objects["SpriteCam"].rotation_euler = Euler((math.radians(55), 0, 0), "XYZ")
    set_key(azimuth_deg=-60, elevation_deg=55, energy=4.5)
    shadow_catcher(40)
    frame_fixed(objs, ppu=110, pad=0.1)
    return render(f"battle/obstacle_{kind}.png")
