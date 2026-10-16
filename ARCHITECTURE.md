# Architecture — Heroes of the Shattered Crown (Godot 4.7, GDScript)

Godot exe: `C:\Users\PC\Documents\Godot\Godot_v4.7.2-stable_win64_console.exe`
Design resolution 1920x1080, stretch mode canvas_items/expand. All UI coordinates assume 1920x1080.

## Autoloads (scripts/core)
- `GameData` — static tables (creatures, heroes, spells, buildings, artifacts, terrains, mines). Source of all ids.
- `Assets` — `Assets.tex("creatures/pikeman.png")` with placeholder fallback; `Assets.anchor(path)` returns the
  foot point of a Blender-rendered sprite (from `<dir>/anchors.json`). See ASSETS.md for every asset path.
- `Audio` — `Audio.music("battle")`, `Audio.sfx("sword_hit")`.
- `GameState` — world state across scenes, fade `change_scene()`, battle/town handoff, hero helpers, save/load.
- `Shot` — screenshot harness for automated visual review (see below).

## Shared classes
- `UI` (scripts/ui/ui.gd) — theme + widget factory. Set `theme = UI.theme()` on your root Control.
- `Modal` (scripts/ui/modal.gd) — awaitable dialogs: `var r = await Modal.choice(self, title, text, options).closed`.
- `ArmyStrip` (scripts/ui/army_strip.gd) — 7 army slots; strips sharing a group dict exchange stacks.
- `TownLogic` (scripts/town/town_logic.gd) — town/player rules + dict schemas (READ ITS HEADER).

## Scenes
| Scene | Scripts | Notes |
|---|---|---|
| scenes/main_menu.tscn (main) | scripts/menu/ | menu, new-game setup, quick battle |
| scenes/adventure.tscn | scripts/adventure/ | `WorldGen` (random map), `AdvRules` (pathing, visits, day/week, battles), `AdvAI`, `MapView` (terrain shader, sprites, fog), `AdventureHUD` |
| scenes/town.tscn | scripts/town/ | town screen; building art positions come from `assets/town/layout_<faction>.json` (fallback `TownLayout`) |
| scenes/battle.tscn | scripts/battle/ | `BattleLogic` (pure rules, emits events), `BattleAI`, battle.gd (animation/UI) |

## World dict (GameState.world) — owned by adventure code
```
{ "seed": int, "size": Vector2i, "day": int (1-based total days), "current_player": int,
  "players": Array[player dict], "heroes": {uid: hero}, "towns": {uid: town},
  "objects": {uid: object dict}, "terrain": PackedByteArray (index into WorldGen.TERRAIN_ORDER),
  "blocked": PackedByteArray, "decor": Array, "tavern": Array[hero id], ... }
```
day -> week = (day-1)/7+1, day_of_week = (day-1)%7+1, month = (day-1)/28+1.
Tiles are 64px; objects have an action tile `pos` and an optional footprint (WorldGen.footprint_for).

## Scene flow
Main menu -> New Game -> sets `GameState.new_game_settings`, clears `GameState.world`, changes to adventure, which
generates the world. Adventure -> town: `open_town(uid)`; town "Exit" -> adventure.
Adventure -> battle: `GameState.start_battle({...})`; battle -> `GameState.finish_battle(result)`; adventure applies
`GameState.battle_result` in `_post_ready`. Battles with no human side are resolved instantly (`AdvRules.quick_resolve`).
AI turns run inside the adventure scene and resume after a battle scene change.

Every scene also works when launched DIRECTLY (for screenshots): missing state -> demo state.

## Tools
- `sh tools/check.sh` — re-import + compile every script (prints only errors).
- `tools/sim_test.tscn` — all-AI soak test: `Godot --path . res://tools/sim_test.tscn -- --seconds=80`
  (prints `SIM day ...` summaries and `SIMBATTLE` lines).
- Screenshot harness:
```
Godot_v4.7.2-stable_win64_console.exe --path . -- --shot=shots/x.png --scene=res://scenes/battle.tscn --delay=3
```
Options: `--shots=N --interval=S`, `--click=x,y;x,y`, `--keys=Space;Enter`, `--setup=<name>` (`demo`, `rich`, `new_game`).
Window must not be headless (rendering needed). Screens are saved at the window resolution (1600x900 by default).

## Art & audio pipeline (see ASSETS.md)
- Blender (via the Blender MCP) renders all sprites: `tools/art/blender/*.py`, driven by `batch.py`
  (`run(["creatures", "battle", "towns", ...])`). Textures/HDRIs are CC0 from Poly Haven, cached in tools/art/raw/.
- Python post-processing: `tools/art/postfx.py` (ink outline, saturation), `sky.py` (painted skies),
  `portrait_bg.py`, `icons2d.py` (spell icons, icon frames), `town_crop.py` (town layers + layout json),
  `terrain.py` (terrain textures), `ui_art.py` (panels, buttons, logo).
- Audio: `tools/audio/gen_audio.py {sfx|music|voice}` — ElevenLabs (key from ELEVENLABS_API_KEY).
