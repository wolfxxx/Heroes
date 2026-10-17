"""Render batches. In Blender (via MCP):  STEPS = ["creatures", ...]; exec(open(<this file>).read())
Steps: props, creatures (procedural), imported (library models), portraits, mapobjects, battle, icons, towns, menu. Writes a progress log next to this file."""
import os, time, traceback, json
B = os.path.dirname(os.path.abspath(r"C:\Users\PC\Documents\GITHUBprojects\Heroes2\tools\art\blender\batch.py"))
LOG = os.path.join(B, "..", "raw", "batch_log.txt")
os.makedirs(os.path.dirname(LOG), exist_ok=True)

def _load():
    for f in ("studio", "figures", "buildings", "props", "battlefield", "townscreen", "necro_town", "icons", "imported"):
        exec(open(os.path.join(B, f + ".py")).read(), globals())

def _log(msg):
    with open(LOG, "a") as fh:
        fh.write(time.strftime("%H:%M:%S ") + msg + "\n")

def run(steps):
    _load()
    studio()
    for step in steps:
        t = time.time()
        try:
            if step == "props":
                for n in JOBS_PROPS:
                    render_prop(n)
            elif step == "creatures":
                for cid in CREATURES:
                    render_creature(cid)
            elif step == "portraits":
                for hid in HERO_LOOKS:
                    render_hero_portrait(hid)
            elif step == "battle":
                for i, ter in enumerate(["grass", "dirt", "sand", "snow", "swamp"]):
                    render_battlefield(ter, i + 1)
                for k in (1, 2, 3, 4):
                    render_obstacle(k)
            elif step == "towns":
                for fac in ("haven", "necropolis"):
                    render_town(fac)
            elif step == "heroes":
                for fac in ("haven", "necropolis"):
                    render_map_hero(fac)
                    render_battle_hero(fac)
            elif step == "obstacles":
                for k in (1, 2, 3, 4):
                    render_obstacle(k)
            elif step == "necro_town":
                render_town("necropolis")
            elif step == "creature_portraits":
                for cid in CREATURES:
                    clear_objects()
                    objs = [o for o in CREATURES[cid]() if not o.hide_render]
                    shadow_catcher(40)
                    render_portrait([o for o in objs if o.get("portrait")], f"creatures/portraits/{cid}.png")
            elif step == "imported":
                # library models (tools/art/raw/models/*.glb + specs.json): creatures, hero portraits, hero sprites
                pj = os.path.join(ASSETS, "heroes", "portraits", "painted.json")
                painted = json.load(open(pj)) if os.path.exists(pj) else []  # painted over: don't clobber
                for cid in sorted(_specs()):
                    if cid not in painted:
                        render_cached(cid)
                for fac in HERO_MODELS:
                    render_hero_sprites(fac)
            elif step == "menu":
                render_menu_art()
            _log(f"{step} ok {time.time() - t:.0f}s")
        except Exception:
            _log(f"{step} FAILED\n{traceback.format_exc()}")
    _log("BATCH DONE")
