"""Icon renders (transparent, square). Requires studio.py, figures.py, buildings.py loaded.

icons/res_*.png (resource piles, close-up), icons/stat_*.png, icons/skill_*.png, icons/artifact_*.png.
Backgrounds for skills/artifacts are added afterwards by tools/art/icon_bg.py.
"""

def _sword(gold=False, glow=None):
    a = Vector((0, 0, 0))
    objs = sword(a, 1.0, up=(0.0, 0, 1.0), length=1.1, mat=M("gold") if gold else M("steel"), glow=glow)
    for o in objs:
        o.rotation_euler.y += math.radians(-35)
    return objs

def _shield(color=(0.12, 0.25, 0.75), emblem="gold"):
    return shield({"hand_n": Vector((0, 0.07, 0.0))}, color, emblem, 1.6)

def _orb(c=(0.5, 0.7, 1.0)):
    return [ball((0, 0, 0.45), 0.32, M("glow", c)), prim("cyl", (0, 0, 0.1), (0.22, 0.22, 0.1), mat=M("gold"), vertices=24, bake=True),
            prim("torus", (0, 0, 0.45), (1, 1, 1), mat=M("gold"), major_radius=0.36, minor_radius=0.025, rot=(math.radians(75), 0, 0))]

def _book(color=(0.45, 0.08, 0.06)):
    cover = M("leather", color)
    out = [box((0, 0, 0.12), (0.9, 0.65, 0.06), cover), box((0, 0, 0.2), (0.86, 0.6, 0.12), flat_material("pages", (0.92, 0.88, 0.75), 0.8)),
           box((0, 0, 0.28), (0.9, 0.65, 0.05), cover), box((0, -0.12, 0.31), (0.22, 0.22, 0.02), M("gold"))]
    for o in out:
        o.rotation_euler = (math.radians(-20), math.radians(10), math.radians(25))
    return out

def _banner():
    return banner(0, 0, 0.0, (0.12, 0.25, 0.75), 0.9)

def _scroll():
    p = flat_material("parchment", (0.9, 0.82, 0.6), 0.8)
    return [rod((-0.5, 0, 0.6), (0.5, 0, 0.6), 0.12, p), box((0, 0, 0.3), (0.85, 0.02, 0.6), p), rod((-0.5, 0, 0.0), (0.5, 0, 0.0), 0.12, p),
            ball((0.55, 0, 0.6), 0.06, M("gold")), ball((-0.55, 0, 0.6), 0.06, M("gold"))]

def _bow():
    a = {"hand_f": Vector((0.3, 0, 0.5)), "hand_n": Vector((-0.05, 0, 0.5)), "chest": Vector((-5, 0, 0))}
    objs = bow(a, 1.4)
    return objs[:2] + objs[3:]

def _axe():
    return [rod((0, 0, -0.5), (0, 0, 0.7), 0.04, M("wood")), arc((0.0, 0, 0.45), 0.3, 0.06, -70, 70, M("steel"), "Y")]

def _breastplate():
    return [ball((0, 0, 0.4), 0.45, M("steel"), 0.7, 1.0, 1.1), ball((0, -0.42, 0.75), 0.17, M("steel"), 1.0, 1.0, 0.8), ball((0, 0.42, 0.75), 0.17, M("steel"), 1.0, 1.0, 0.8)]

def _skull(eyes=(0.3, 1.0, 0.45)):
    bm = M("bone")
    return [ball((0, 0, 0.4), 0.4, bm, 1.05, 0.9, 1.0), ball((0.18, 0, 0.12), 0.22, bm, 1.0, 0.85, 0.6),
            ball((0.33, -0.15, 0.45), 0.08, M("glow", eyes)), ball((0.33, 0.15, 0.45), 0.08, M("glow", eyes))]

def _boot(winged=False):
    lm = M("leather", (0.4, 0.25, 0.12))
    out = [skin_body("boot", [(Vector((0, 0, 0.9)), 0.17), (Vector((0, 0, 0.25)), 0.16), (Vector((0.35, 0, 0.08)), 0.13)], [(0, 1), (1, 2)], lm)]
    if winged:
        out += feather_wings({"chest": Vector((-0.05, 0, 0.55))}, M("cloth", (0.95, 0.95, 0.92)), 0.6, span=0.9)
    return out

def _clover():
    g = flat_material("clover", (0.15, 0.6, 0.15), 0.5)
    out = [rod((0, 0, -0.5), (0.05, 0, 0.2), 0.03, g)]
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        out.append(ball((math.cos(a) * 0.25, math.sin(a) * 0.25 * 0.2, 0.3 + math.sin(a) * 0.25), 0.2, g, 1.0, 0.25, 1.0))
    return out

def _ring():
    r = prim("torus", (0, 0, 0.3), (1, 1, 1), mat=M("gold"), major_radius=0.35, minor_radius=0.07, rot=(math.radians(70), 0, 0))
    gem = prim("ico", (0, -0.05, 0.68), (0.13, 0.13, 0.13), mat=flat_material("ruby", (0.9, 0.05, 0.1), 0.05, 0.0, emit=0.5), subdivisions=1)
    return [r, gem]

def _crown():
    return helmet({"head": Vector((0, 0, -0.1))}, "crown", M("gold"), 3.0) + [ball((0.36, 0, 0.25), 0.07, flat_material("ruby", (0.9, 0.05, 0.1), 0.05, 0.0, emit=0.5))]

def _helm():
    return helmet({"head": Vector((0, 0, 0.3))}, "great", M("steel"), 3.0, plume=(0.95, 0.8, 0.25))

def _horse_shoe():
    return [arc((0, 0, 0.4), 0.35, 0.07, -120, 120, M("steel"), "Y")]

ICONS = {
    "stat_attack": lambda: _sword(), "stat_defense": lambda: _shield(), "stat_power": lambda: _orb(), "stat_knowledge": lambda: _book(),
    "skill_leadership": _banner, "skill_wisdom": _scroll, "skill_archery": _bow, "skill_offense": _axe, "skill_armorer": _breastplate,
    "skill_necromancy": _skull, "skill_logistics": lambda: _boot(), "skill_luck": _clover, "skill_sorcery": lambda: _orb((0.8, 0.4, 1.0)),
    "artifact_sword_of_valor": lambda: _sword(glow=(1.0, 0.75, 0.3)), "artifact_shield_of_dawn": lambda: _shield((0.95, 0.75, 0.25), (0.95, 0.95, 0.9)),
    "artifact_helm_of_wisdom": _helm, "artifact_orb_of_power": lambda: _orb((1.0, 0.45, 0.2)), "artifact_boots_of_speed": lambda: _boot(True),
    "artifact_ring_of_vitality": _ring, "artifact_clover_of_fortune": _clover, "artifact_crown_of_command": _crown,
}

def render_icon(name, objs_fn, size=128, view=(62, 0, 30)):
    clear_objects()
    sc = bpy.context.scene
    sc.render.film_transparent = True
    objs = objs_fn()
    cam = camera("map")
    cam.rotation_euler = Euler((math.radians(view[0]), 0, math.radians(view[2])), "XYZ")
    set_key(azimuth_deg=-120, elevation_deg=50, energy=4.0)
    frame(objs, (size, size), margin=0.1, shadow=False)
    return render(f"icons/{name}.png")

def render_all_icons():
    for name, fn in ICONS.items():
        render_icon(name, fn)
    for r in ("wood", "ore", "gold", "mercury", "sulfur", "crystal", "gems"):
        render_icon(f"res_{r}", lambda r=r: pile(r), 96, (55, 0, 20))
