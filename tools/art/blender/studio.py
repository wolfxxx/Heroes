"""Sprite studio for Blender (run inside Blender via the MCP: exec(open(path).read())).

Provides: a clean 'Studio' scene, painterly lighting, orthographic cameras for the adventure-map
(3/4 top-down) and battle (side) views, auto-framing, transparent PNG renders, cached Poly Haven
PBR materials and small mesh helpers used by the builders in props.py / buildings.py.
"""
import bpy, bmesh, math, os, random, json, urllib.request
from mathutils import Vector, Matrix, Euler

ROOT = r"C:\Users\PC\Documents\GITHUBprojects\Heroes2"
TEX_CACHE = os.path.join(ROOT, "tools", "art", "raw", "textures")
ASSETS = os.path.join(ROOT, "assets")
os.makedirs(TEX_CACHE, exist_ok=True)

# ---------------------------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------------------------
def studio(name="Studio"):
    sc = bpy.data.scenes.get(name) or bpy.data.scenes.new(name)
    bpy.context.window.scene = sc
    # batch_remove: removing IDs one by one rescans every user each time and takes minutes for big imports
    bpy.data.batch_remove(list(sc.objects))
    bpy.data.batch_remove([m for m in bpy.data.materials if not m.name.startswith("PH_")] + list(bpy.data.textures))
    bpy.data.batch_remove([d for block in (bpy.data.meshes, bpy.data.curves, bpy.data.lights, bpy.data.cameras)
                           for d in block if d.users == 0])
    r = sc.render
    r.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        sc.cycles.device = "GPU"
    except Exception:
        pass
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.resolution_percentage = 100
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        try:
            sc.view_settings.view_transform = "Filmic"
            sc.view_settings.look = "Medium High Contrast"
        except Exception:
            pass
    try:
        sc.eevee.taa_render_samples = 64
        sc.eevee.use_shadows = True
    except Exception:
        pass
    _world(sc)
    _lights(sc)
    return sc

def _world(sc):
    w = bpy.data.worlds.get("StudioWorld") or bpy.data.worlds.new("StudioWorld")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    bg = nt.nodes.new("ShaderNodeBackground")
    sky = nt.nodes.new("ShaderNodeTexGradient")  # cheap vertical sky/ground ambient split
    coord = nt.nodes.new("ShaderNodeTexCoord")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    ramp.color_ramp.elements[0].color = (0.32, 0.27, 0.2, 1)    # warm bounce from the ground
    ramp.color_ramp.elements[1].color = (0.55, 0.65, 0.85, 1)   # cool sky
    nt.links.new(ramp.outputs[0], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.9
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs[0], out.inputs[0])
    nt.nodes.remove(sky)

def _lights(sc):
    # Key: warm sun from the top-left (as seen by the map camera looking north).
    sun = bpy.data.lights.new("Key", "SUN")
    sun.energy = 4.2
    sun.color = (1.0, 0.93, 0.8)
    sun.angle = math.radians(3)
    o = bpy.data.objects.new("Key", sun)
    sc.collection.objects.link(o)
    o.rotation_euler = Euler((math.radians(-38), 0, math.radians(72)), "XYZ")
    # Rim: cool light from behind for silhouettes.
    rim = bpy.data.lights.new("Rim", "SUN")
    rim.energy = 1.4
    rim.color = (0.7, 0.8, 1.0)
    o2 = bpy.data.objects.new("Rim", rim)
    sc.collection.objects.link(o2)
    o2.rotation_euler = Euler((math.radians(-60), 0, math.radians(160)), "XYZ")

def set_key(azimuth_deg=-40, elevation_deg=50, energy=4.2):
    k = bpy.data.objects["Key"]
    k.rotation_euler = Euler((math.radians(90 - elevation_deg), 0, math.radians(azimuth_deg)), "XYZ")
    k.data.energy = energy

# ---------------------------------------------------------------------------------------------
# Camera + rendering
# ---------------------------------------------------------------------------------------------
def camera(view="map"):
    """map: 3/4 top-down looking north (+Y) from 40 deg elevation; side: battle view looking +Y."""
    sc = bpy.context.scene
    cam = bpy.data.objects.get("SpriteCam")
    if cam is None:
        cam = bpy.data.objects.new("SpriteCam", bpy.data.cameras.new("SpriteCam"))
        sc.collection.objects.link(cam)
    elif cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    elev = {"map": 40.0, "side": 12.0, "portrait": 8.0, "top": 89.9}[view]
    cam.rotation_euler = Euler((math.radians(90 - elev), 0, 0), "XYZ")
    sc.camera = cam
    return cam

def objects_bbox(objs):
    pts = []
    for o in objs:
        if o.type in ("MESH", "CURVE"):
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    return pts

def frame(objs, size_px, margin=0.04, shadow=True):
    """Fit camera to objects (+ their projected ground shadow). Returns (width_px, height_px)."""
    sc = bpy.context.scene
    cam = sc.camera
    bpy.context.view_layer.update()
    pts = objects_bbox(objs)
    key = bpy.data.objects.get("Key")
    if shadow and key:
        ldir = key.matrix_world.to_3x3() @ Vector((0, 0, -1))  # direction light travels
        if ldir.z < -0.05:
            for p in list(pts):
                if p.z > 0.01:
                    t = -p.z / ldir.z
                    q = p + ldir * t
                    pts.append(Vector((q.x, q.y, 0.0)))
    inv = cam.matrix_world.inverted()
    local = [inv @ p for p in pts]
    xs = [p.x for p in local]; ys = [p.y for p in local]
    w = max(xs) - min(xs); h = max(ys) - min(ys)
    w *= 1 + margin * 2; h *= 1 + margin * 2
    if isinstance(size_px, (tuple, list)):
        rx, ry = size_px
    else:
        if w >= h:
            rx, ry = size_px, max(8, int(size_px * h / w))
        else:
            rx, ry = max(8, int(size_px * w / h)), size_px
    sc.render.resolution_x = rx
    sc.render.resolution_y = ry
    # ortho_scale covers the larger render dimension
    scale = max(w, h * rx / ry)
    cam.data.ortho_scale = scale
    cx = (max(xs) + min(xs)) / 2; cy = (max(ys) + min(ys)) / 2
    # shift the camera within its own plane to centre the box, then back it off along the view axis
    d = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
    plane_pt = cam.matrix_world @ Vector((cx, cy, 0))
    near = min(p.z for p in local)  # most negative = farthest; max = nearest to camera
    nearest = max(p.z for p in local)
    cam.location = plane_pt + d * (nearest - 0) * -1 - d * 20
    cam.data.clip_start = 0.1
    cam.data.clip_end = 500
    return rx, ry

PX_PER_UNIT = 64  # render resolution; the game draws map sprites at 0.5 => 32 px per unit, 2 units per tile
_anchor = None

def frame_fixed(objs, ppu=PX_PER_UNIT, pad=0.15, shadow=True):
    """Fixed world scale framing. Records the pixel anchor of the world origin (object's foot)."""
    global _anchor
    sc = bpy.context.scene
    cam = sc.camera
    bpy.context.view_layer.update()
    pts = objects_bbox(objs)
    key = bpy.data.objects.get("Key")
    if shadow and key:
        ldir = key.matrix_world.to_3x3() @ Vector((0, 0, -1))
        if ldir.z < -0.05:
            for p in list(pts):
                if p.z > 0.01:
                    q = p + ldir * (-p.z / ldir.z)
                    pts.append(Vector((q.x, q.y, 0.0)))
    inv = cam.matrix_world.inverted()
    local = [inv @ p for p in pts]
    o = inv @ Vector((0, 0, 0))
    minx = min(p.x for p in local) - pad; maxx = max(p.x for p in local) + pad
    miny = min(p.y for p in local) - pad; maxy = max(p.y for p in local) + pad
    half = max(o.x - minx, maxx - o.x)
    minx, maxx = o.x - half, o.x + half
    w = maxx - minx; h = maxy - miny
    rx = max(8, int(round(w * ppu))); ry = max(8, int(round(h * ppu)))
    sc.render.resolution_x = rx
    sc.render.resolution_y = ry
    cam.data.ortho_scale = w if rx >= ry else h
    cx = (minx + maxx) / 2; cy = (miny + maxy) / 2
    d = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
    nearest = max(p.z for p in local)
    cam.location = cam.matrix_world @ Vector((cx, cy, 0)) - d * (nearest + 20)
    cam.data.clip_start = 0.1
    cam.data.clip_end = 500
    _anchor = [round((o.x - minx) / w, 4), round((maxy - o.y) / h, 4)]
    return rx, ry

def render(path):
    global _anchor
    sc = bpy.context.scene
    full = os.path.join(ASSETS, path) if not os.path.isabs(path) else path
    os.makedirs(os.path.dirname(full), exist_ok=True)
    sc.render.filepath = full
    bpy.ops.render.render(write_still=True)
    if _anchor is not None:
        af = os.path.join(os.path.dirname(full), "anchors.json")
        data = json.load(open(af)) if os.path.exists(af) else {}
        data[os.path.basename(full)] = _anchor
        json.dump(data, open(af, "w"), indent=0, sort_keys=True)
        _anchor = None
    return full

def clear_objects(keep=("Key", "Rim", "SpriteCam")):
    bpy.data.batch_remove([o for o in bpy.context.scene.objects if o.name not in keep])

# ---------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------
def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Heroes2-art-pipeline/1.0"})
    return urllib.request.urlopen(req, timeout=60).read()

def _ph_download(pid, res="1k"):
    folder = os.path.join(TEX_CACHE, pid)
    os.makedirs(folder, exist_ok=True)
    manifest = os.path.join(folder, "maps.json")
    if os.path.exists(manifest):
        return json.load(open(manifest))
    files = json.loads(_get(f"https://api.polyhaven.com/files/{pid}"))
    maps = {}
    for key, alias in (("Diffuse", "diff"), ("nor_gl", "nor"), ("Rough", "rough"), ("AO", "ao")):
        if key in files and res in files[key]:
            fmt = "jpg" if "jpg" in files[key][res] else "png"
            url = files[key][res][fmt]["url"]
            dst = os.path.join(folder, f"{alias}.{fmt}")
            if not os.path.exists(dst):
                open(dst, "wb").write(_get(url))
            maps[alias] = dst
    json.dump(maps, open(manifest, "w"))
    return maps

def ph_material(pid, scale=1.0, tint=None, tint_k=0.0, sat=1.0, bright=1.0):
    """Poly Haven PBR material with box-projected object coords (no UVs needed)."""
    name = f"PH_{pid}_{scale}_{tint}_{tint_k}_{sat}_{bright}"
    m = bpy.data.materials.get(name)
    if m:
        return m
    maps = _ph_download(pid)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    def tex(path, non_color=False):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(path, check_existing=True)
        if non_color:
            t.image.colorspace_settings.name = "Non-Color"
        t.projection = "BOX"
        t.projection_blend = 0.3
        nt.links.new(mapping.outputs[0], t.inputs[0])
        return t
    if "diff" in maps:
        d = tex(maps["diff"])
        col = d.outputs[0]
        hsv = nt.nodes.new("ShaderNodeHueSaturation")
        hsv.inputs["Saturation"].default_value = sat
        hsv.inputs["Value"].default_value = bright
        nt.links.new(col, hsv.inputs["Color"])
        col = hsv.outputs[0]
        if tint is not None and tint_k > 0:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = tint_k
            nt.links.new(col, mix.inputs[6])
            mix.inputs[7].default_value = (*tint, 1)
            col = mix.outputs[2]
        nt.links.new(col, bsdf.inputs["Base Color"])
    if "rough" in maps:
        r = tex(maps["rough"], True)
        nt.links.new(r.outputs[0], bsdf.inputs["Roughness"])
    if "nor" in maps:
        n = tex(maps["nor"], True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs[0], nm.inputs["Color"])
        nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
    return m

def flat_material(name, color, rough=0.7, metal=0.0, emit=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = emit
    return m

def noise_material(name, c1, c2, scale=6.0, rough=0.8, bump=0.3):
    """Two-tone procedural material (foliage, painted surfaces)."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 6
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c1, 1)
    ramp.color_ramp.elements[1].color = (*c2, 1)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.7
    nt.links.new(noise.outputs["Fac"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    if bump > 0:
        b = nt.nodes.new("ShaderNodeBump")
        b.inputs["Strength"].default_value = bump
        nt.links.new(noise.outputs["Fac"], b.inputs["Height"])
        nt.links.new(b.outputs[0], bsdf.inputs["Normal"])
    return m

# ---------------------------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------------------------
def link(o):
    bpy.context.scene.collection.objects.link(o)
    return o

def assign(o, mat):
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o

def bake_scale(o):
    """Apply object scale into the mesh so box-projected textures keep a constant density."""
    if o.type == "MESH" and tuple(o.scale) != (1.0, 1.0, 1.0):
        o.data.transform(Matrix.Diagonal((*o.scale, 1.0)))
        o.scale = (1, 1, 1)
    return o

def prim(kind, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), mat=None, name=None, bake=False, **kw):
    fn = {"cube": bpy.ops.mesh.primitive_cube_add, "cyl": bpy.ops.mesh.primitive_cylinder_add,
          "cone": bpy.ops.mesh.primitive_cone_add, "sphere": bpy.ops.mesh.primitive_uv_sphere_add,
          "ico": bpy.ops.mesh.primitive_ico_sphere_add, "plane": bpy.ops.mesh.primitive_plane_add,
          "torus": bpy.ops.mesh.primitive_torus_add}[kind]
    fn(location=loc, rotation=rot, **kw)
    o = bpy.context.active_object
    o.scale = scale
    if bake:
        bake_scale(o)
    if name:
        o.name = name
    if mat:
        assign(o, mat)
    return o

def displace(o, strength=0.3, scale=1.5, seed=0, subdiv=2, kind="CLOUDS"):
    if subdiv:
        s = o.modifiers.new("sub", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    tex = bpy.data.textures.new(f"disp_{o.name}_{seed}", kind)
    if hasattr(tex, "noise_scale"):
        tex.noise_scale = scale
    d = o.modifiers.new("disp", "DISPLACE")
    d.texture = tex
    d.strength = strength
    d.texture_coords = "GLOBAL" if seed == 0 else "OBJECT"
    if seed:
        e = bpy.data.objects.new(f"disp_off_{o.name}", None)
        link(e)
        e.location = (seed * 13.1, seed * 7.7, seed * 3.3)
        d.texture_coords_object = e
        d.texture_coords = "OBJECT"
    return o

def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True
    return o

def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        for m in o.modifiers:
            try:
                bpy.ops.object.modifier_apply({"object": o}, modifier=m.name)
            except Exception:
                pass
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o

def shadow_catcher(size=20):
    """Ground plane that only receives shadows (transparent film keeps the shadow)."""
    p = prim("plane", (0, 0, 0), (size, size, 1), name="ShadowCatcher")
    p.is_shadow_catcher = True
    m = flat_material("Catcher", (0.5, 0.5, 0.5))
    assign(p, m)
    return p
