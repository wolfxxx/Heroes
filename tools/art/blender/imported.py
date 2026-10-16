"""Library models (Sketchfab / Poly Pizza) -> game sprites.

Workflow per creature (in Blender via MCP, after exec'ing studio.py + figures.py + this file):
  1. begin_import()                         clears the scene, keeps lights + camera
  2. MCP import_asset(...)                  model lands at the origin
  3. adopt(cid, turn_deg, ...)              parents everything to an empty, faces +X, feet on z=0,
                                            saves tools/art/raw/models/<cid>.glb for batch re-renders
  4. render_imported(cid)                   battle sprite + portrait (same camera/light as figures.py)
Re-render later without the MCP: render_cached(cid) re-imports the saved .glb.
"""
import bpy, os, math, json
from mathutils import Vector, Euler

MODELS = os.path.join(ROOT, "tools", "art", "raw", "models")
SPECS = os.path.join(ROOT, "tools", "art", "imported_specs.json")  # tracked; the .glb cache is not

SKETCHFAB_CACHE = os.path.join(ROOT, "tools", "art", "raw", "sketchfab")

def _sketchfab_key():
    """The key the user stored in the Blender MCP addon (prefs -> scene -> env). Never printed."""
    for mod, addon in bpy.context.preferences.addons.items():
        if "mcp" in mod.lower():
            v = getattr(addon.preferences, "sketchfab_api_key", "")
            if v:
                return v
    return getattr(bpy.context.scene, "blendermcp_sketchfab_api_key", "") or os.getenv("BLENDERMCP_SKETCHFAB_API_KEY", "")

def sketchfab_fetch(uid):
    """Download (once) a Sketchfab model's glTF zip into SKETCHFAB_CACHE/<uid>/ and return the .gltf path."""
    import requests, zipfile, io
    d = os.path.join(SKETCHFAB_CACHE, uid)
    if not os.path.isdir(d) or not any(f.endswith((".gltf", ".glb")) for f in os.listdir(d)):
        r = requests.get(f"https://api.sketchfab.com/v3/models/{uid}/download",
                         headers={"Authorization": f"Token {_sketchfab_key()}"}, timeout=30)
        r.raise_for_status()
        z = requests.get(r.json()["gltf"]["url"], timeout=120)
        z.raise_for_status()
        os.makedirs(d, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(z.content)) as zf:
            for n in zf.namelist():
                if ".." in n or os.path.isabs(n):
                    raise ValueError("unsafe path in zip")
            zf.extractall(d)
    return os.path.join(d, next(f for f in os.listdir(d) if f.endswith((".gltf", ".glb"))))

def sketchfab_import(uid, **opts):
    """Import a cached Sketchfab model; opts go to the glTF importer (e.g. bone_heuristic, guess_original_bind_pose)."""
    path = sketchfab_fetch(uid)
    bpy.ops.import_scene.gltf(filepath=path, **opts)
    # normalise: the zips are often in cm/mm with a large root scale; adopt() sets the final height
    return path

def _specs():
    return json.load(open(SPECS)) if os.path.exists(SPECS) else {}

def begin_import():
    studio()
    clear_objects()
    # glTF imports add a scene + collection per glTF scene in the file. They piled up into thousands, which made
    # every operation slow and the old one-by-one collections.remove() loop look like a hang. Remove in one batch.
    cur = bpy.context.window.scene
    bpy.data.batch_remove([s for s in bpy.data.scenes if s != cur and s.name != "Scene" and not s.objects])
    bpy.data.batch_remove([c for c in cur.collection.children if not c.all_objects])
    # every import leaves meshes/images/materials behind; without this Blender grows to many GB
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

def _meshes(root):
    out = []
    def walk(o):
        if o.type == "MESH" and not o.hide_render:
            out.append(o)
        for ch in o.children:
            walk(ch)
    walk(root)
    return out

def _world_pts(objs):
    """Evaluated (armature-posed) vertex positions; falls back to bound boxes for huge meshes."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = o.matrix_world
        step = max(1, len(me.vertices) // 4000)
        pts += [mw @ me.vertices[i].co for i in range(0, len(me.vertices), step)]
        ev.to_mesh_clear()
    return pts

def _drop_helpers():
    """Stray unparented helper meshes (Icosphere/Cube) without materials that imports leave behind."""
    bpy.data.batch_remove([o for o in bpy.context.scene.objects
                           if o.type == "MESH" and o.parent is None and o.name != "ShadowCatcher" and not o.data.materials])

def adopt(cid, turn_deg=90.0, height=None, offset=(0.0, 0.0), hide=(), save=True):
    """Parent all top-level scene objects to an empty 'Creature', rotate to face +X, normalise height,
    put the lowest point on z=0 and the footprint centre at the origin."""
    sc = bpy.context.scene
    keep = {"Key", "Rim", "SpriteCam", "ShadowCatcher"}
    _drop_helpers()
    tops = [o for o in sc.objects if o.parent is None and o.name not in keep]
    root = bpy.data.objects.new("Creature", None)
    sc.collection.objects.link(root)
    for o in tops:
        o.parent = root
    for o in sc.objects:
        if any(h.lower() in o.name.lower() for h in hide):
            o.hide_render = True
            o.hide_viewport = True
    root.rotation_euler = Euler((0, 0, math.radians(turn_deg)), "XYZ")
    bpy.context.view_layer.update()
    objs = _meshes(root)
    pts = _world_pts(objs)
    if height:
        h = max(p.z for p in pts) - min(p.z for p in pts)
        root.scale = (height / h,) * 3
        bpy.context.view_layer.update()
        pts = _world_pts(objs)
    minz = min(p.z for p in pts)
    # footprint centre: centre of the lowest 15% of points (the feet), not the bbox (swords, wings)
    zs = sorted(p.z for p in pts)
    cut = zs[int(len(zs) * 0.15)]
    feet = [p for p in pts if p.z <= cut]
    cx = sum(p.x for p in feet) / len(feet)
    cy = sum(p.y for p in feet) / len(feet)
    root.location = (-cx + offset[0], -cy + offset[1], -minz)
    bpy.context.view_layer.update()
    spec = _specs()
    # merge: the entry also holds sketchfab uid, tint, make_lit and render options set elsewhere
    spec.setdefault(cid, {}).update(turn_deg=turn_deg, height=height, offset=list(offset), hide=list(hide))
    os.makedirs(MODELS, exist_ok=True)
    json.dump(spec, open(SPECS, "w"), indent=1, sort_keys=True)
    if save:
        save_model(cid, root)
    return root

def save_model(cid, root=None):
    """Export the adopted model (as posed now) to MODELS/<cid>.glb for batch re-renders. Meshes are baked to
    static world-space geometry first: skinned meshes do not survive a glTF round trip in their posed state."""
    root = root or bpy.data.objects["Creature"]
    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    bake = bpy.data.objects.new("CreatureBake", None)
    sc.collection.objects.link(bake)
    tmp = [bake]
    for o in _meshes(root):
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world)
        ob = bpy.data.objects.new(o.name + "_baked", me)
        sc.collection.objects.link(ob)
        ob.parent = bake
        tmp.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for o in tmp:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODELS, cid + ".glb"), use_selection=True, use_active_scene=True,
                              export_animations=False)  # active scene only: otherwise every scene in the session is written
    bpy.data.batch_remove(tmp)

def rebuild(cid):
    """Re-import a model from the Sketchfab cache and re-adopt it with its recorded spec (re-saves the .glb)."""
    s = _specs()[cid]
    begin_import()
    sketchfab_import(s["sketchfab"])
    adopt(cid, turn_deg=s["turn_deg"], height=s["height"], offset=tuple(s.get("offset", (0, 0))), hide=tuple(s.get("hide", ())))

def make_lit(objs, rough=0.7):
    """Unlit (KHR_materials_unlit / shadeless) materials ignore our lights and cast no shadows:
    rebuild them as a Principled BSDF fed by the same colour texture."""
    done = set()
    for o in objs:
        for m in o.data.materials:
            if not m or m.name in done or not m.use_nodes:
                continue
            done.add(m.name)
            nt = m.node_tree
            if any(n.type == "BSDF_PRINCIPLED" for n in nt.nodes):
                continue
            out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
            tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
            if not out:
                continue
            bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
            bsdf.inputs["Roughness"].default_value = rough
            if tex:
                nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
                if m.blend_method != "OPAQUE" or any(l.from_socket == tex.outputs["Alpha"] for l in nt.links):
                    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

def specgloss_fix(objs):
    """Spec/gloss (KHR_materials_pbrSpecularGlossiness) assets keep metal colour (gold trim, steel tint)
    in the specular map and leave the diffuse grey: lighten the diffuse with it before Base Color."""
    done = set()
    for o in objs:
        for m in o.data.materials:
            if not m or m.name in done or not m.use_nodes:
                continue
            done.add(m.name)
            nt = m.node_tree
            spec = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image and "specular" in n.image.name.lower()), None)
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not spec or not bsdf or not bsdf.inputs["Base Color"].is_linked:
                continue
            src = bsdf.inputs["Base Color"].links[0].from_socket
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "LIGHTEN"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(src, mix.inputs[6])
            nt.links.new(spec.outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])

def tint(objs, mult=(1, 1, 1), sat=1.0, rough=None, emit=None, metal=None):
    """Recolour imported PBR materials: base colour * mult (after a saturation change)."""
    make_lit(objs)
    done = set()
    for o in objs:
        for m in o.data.materials:
            if not m or m.name in done or not m.use_nodes:
                continue
            done.add(m.name)
            nt = m.node_tree
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            inp = bsdf.inputs["Base Color"]
            hsv = nt.nodes.new("ShaderNodeHueSaturation")
            hsv.inputs["Saturation"].default_value = sat
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (*mult, 1.0)  # B colour
            if inp.is_linked:
                src = inp.links[0].from_socket
                nt.links.new(src, hsv.inputs["Color"])
            else:
                hsv.inputs["Color"].default_value = inp.default_value
            nt.links.new(hsv.outputs["Color"], mix.inputs[6])  # A colour
            nt.links.new(mix.outputs[2], inp)
            if rough is not None:  # also resets spec/gloss imports, which come out mirror-like (black)
                for name in ("Roughness", "Specular Tint", "Specular IOR Level"):
                    for l in list(bsdf.inputs[name].links):
                        nt.links.remove(l)
                bsdf.inputs["Roughness"].default_value = rough
                bsdf.inputs["Specular IOR Level"].default_value = 0.5
                bsdf.inputs["Specular Tint"].default_value = (1, 1, 1, 1)
            if metal is not None:  # metallic scans reflect our dark studio and read as grey
                for l in list(bsdf.inputs["Metallic"].links):
                    nt.links.remove(l)
                bsdf.inputs["Metallic"].default_value = metal
            if emit:
                bsdf.inputs["Emission Color"].default_value = (*emit[:3], 1.0)
                bsdf.inputs["Emission Strength"].default_value = emit[3]

def _region_box(pts, z0, z1, name="FocusBox"):
    """Invisible mesh spanning the given height band, used to steer frame()."""
    band = [p for p in pts if z0 <= p.z <= z1] or pts
    lo = Vector((min(p.x for p in band), min(p.y for p in band), z0))
    hi = Vector((max(p.x for p in band), max(p.y for p in band), z1))
    me = bpy.data.meshes.new(name)
    me.from_pydata([(lo.x, lo.y, lo.z), (hi.x, hi.y, hi.z), (lo.x, hi.y, hi.z), (hi.x, lo.y, lo.z)], [], [])
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.hide_render = True
    return o

def render_imported(cid, portrait=True, head=(0.62, 1.0), key=(-60, 55, 4.5), portrait_turn=40.0, pick="top", radius=1.0,
                    sprite=True, portrait_path=None, remember=True, portrait_size=256):
    """Battle sprite (fixed world scale, like render_creature) + head-and-shoulders portrait.
    head: the height band (fraction of total height) the portrait frames. The framing options are
    remembered in specs.json so render_cached() reproduces them."""
    if remember:
        spec = _specs()
        spec.setdefault(cid, {})["render"] = {"portrait": portrait, "head": list(head), "portrait_turn": portrait_turn,
                                             "pick": pick, "radius": radius, "sprite": sprite, "portrait_path": portrait_path}
        json.dump(spec, open(SPECS, "w"), indent=1, sort_keys=True)
    root = bpy.data.objects["Creature"]
    objs = _meshes(root)
    if not bpy.data.objects.get("ShadowCatcher"):
        shadow_catcher(40)
    if sprite:
        camera("side")
        set_key(azimuth_deg=key[0], elevation_deg=key[1], energy=key[2])
        frame_fixed(objs, ppu=BATTLE_PPU, pad=0.08)
        render(f"creatures/{cid}.png")
    if portrait:
        # the portrait camera expects a figure facing +X (figures.py convention); turn back for it
        rz = root.rotation_euler.z
        root.rotation_euler.z = rz + math.radians(portrait_turn)
        bpy.context.view_layer.update()
        pts = _world_pts(objs)
        top = max(p.z for p in pts)
        z0 = top * head[0]
        band = [p for p in pts if p.z >= z0]
        # centre on the head, not on wide wings/weapons: median of the topmost points, then a radius
        if pick == "median":
            hi = band
        elif pick == "front":  # beasts: the head is the forward-most part of the upper body (+X)
            hi = sorted(band, key=lambda p: -p.x)[:max(8, len(band) // 15)]
        else:
            hi = sorted(band, key=lambda p: -p.z)[:max(8, len(band) // 12)]
        mx = sorted(p.x for p in hi)[len(hi) // 2]; my = sorted(p.y for p in hi)[len(hi) // 2]
        r = (top - z0) * 0.75 * radius
        if pick == "front":  # a ball around the head, in 3D
            mz = sorted(p.z for p in hi)[len(hi) // 2]
            near = [p for p in band if (p.x - mx) ** 2 + (p.y - my) ** 2 + (p.z - mz) ** 2 <= r * r] or band
            box = _region_box(near, min(p.z for p in near), max(p.z for p in near))
        else:
            near = [p for p in band if (p.x - mx) ** 2 + (p.y - my) ** 2 <= r * r] or band
            box = _region_box(near, z0, top * head[1])
        render_portrait([box], portrait_path or f"creatures/portraits/{cid}.png", portrait_size)
        bpy.data.objects.remove(box, do_unlink=True)
        root.rotation_euler.z = rz
        bpy.context.view_layer.update()

def load_cached(cid):
    begin_import()
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, cid + ".glb"))
    _drop_helpers()
    root = next(o for o in bpy.context.scene.objects if o.name.startswith("Creature"))
    root.name = "Creature"
    root.rotation_mode = "XYZ"  # glTF import uses quaternions; render_imported turns rotation_euler.z
    if _specs().get(cid, {}).get("make_lit"):
        make_lit(_meshes(root))
    if _specs().get(cid, {}).get("specgloss"):
        specgloss_fix(_meshes(root))
    t = _specs().get(cid, {}).get("tint")
    if t:  # glTF export drops the multiply nodes, so tints are re-applied from the spec
        tint(_meshes(root), mult=tuple(t["mult"]), sat=t.get("sat", 1.0), metal=t.get("metal"), rough=t.get("rough"))
    return root

HERO_MODELS = {"haven": "cavalier", "necropolis": "dread_knight"}

def render_hero_sprites(faction):
    """Adventure-map + battlefield hero sprites from the faction's mounted model."""
    root = load_cached(HERO_MODELS[faction])
    objs = _meshes(root)
    if not bpy.data.objects.get("ShadowCatcher"):
        shadow_catcher(40)
    camera("map")
    set_key(azimuth_deg=-108, elevation_deg=52, energy=4.2)
    root.location.y += 1.0  # stand in the middle of the tile (as figures.map_hero did)
    bpy.context.view_layer.update()
    frame_fixed(objs)
    render(f"heroes/map_{faction}.png")
    root.location.y -= 1.0
    bpy.context.view_layer.update()
    camera("side")
    set_key(azimuth_deg=-60, elevation_deg=55, energy=4.5)
    frame_fixed(objs, ppu=150, pad=0.08)
    render(f"heroes/battle_{faction}.png")

def render_cached(cid, **kw):
    load_cached(cid)
    opts = dict(_specs().get(cid, {}).get("render", {}))
    opts.update(kw)
    opts["head"] = tuple(opts.get("head", (0.62, 1.0)))
    render_imported(cid, remember=False, **opts)
