# Architecture — Heroes of the Shattered Crown (Godot 4.7, GDScript)

Godot exe: `C:\Users\PC\Documents\Godot\Godot_v4.7.2-stable_win64_console.exe`
Design resolution 1920x1080, stretch mode canvas_items/expand. All UI coordinates assume 1920x1080.

## Autoloads (scripts/core)
- `GameData` — static tables (creatures, heroes, spells, buildings, artifacts, terrains, mines). Source of all ids.
- `Assets` — `Assets.tex("creatures/pikeman.png")` with placeholder fallback. See ASSETS.md for every asset path.
- `Audio` — `Audio.music("battle")`, `Audio.sfx("sword_hit")`.
- `GameState` — world state persistence across scenes, fade `change_scene()`, battle/town handoff, hero helpers.
- `Shot` — screenshot harness for automated visual review (see below).

## Shared classes
- `UI` (scripts/ui/ui.gd) — theme + widget factory. Set `theme = UI.theme()` on your root Control.
- `TownLogic` (scripts/town/town_logic.gd) — town/player rules + dict schemas (READ ITS HEADER).

## Scenes & ownership
| Scene | Scripts dir | Owner |
|---|---|---|
| scenes/main_menu.tscn (main scene), new-game setup | scripts/menu/ | Town&Menu agent |
| scenes/town.tscn | scripts/town/ | Town&Menu agent |
| scenes/adventure.tscn | scripts/adventure/ | Adventure agent |
| scenes/battle.tscn | scripts/battle/ | Battle agent |
| assets/** (images) | tools/art/ | Art agent |
| assets/audio/** | tools/audio/ | Audio agent |

Do not edit files owned by another agent; if you need a change in a shared core file, make a minimal additive change
and mention it in your report.

## World dict (GameState.world) — owned by adventure code
```
{ "seed": int, "size": Vector2i, "day": int (1-based total days), "current_player": int,
  "players": Array[player dict], "heroes": {uid: hero}, "towns": {uid: town},
  "objects": {uid: object dict}, "terrain": PackedByteArray (index into TERRAIN_ORDER), ... }
```
day -> week = (day-1)/7+1, day_of_week = (day-1)%7+1, month = (day-1)/28+1.

## Scene flow
Main menu -> New Game (choose faction/hero) -> sets `GameState.new_game_settings`, clears `GameState.world`,
`GameState.change_scene(GameState.SCENE_ADVENTURE)`. Adventure generates world when `GameState.world` is empty.
Adventure -> town: `GameState.open_town(uid)`; town "Exit" -> `GameState.change_scene(GameState.SCENE_ADVENTURE)`.
Adventure -> battle: `GameState.start_battle({...})`; battle -> `GameState.finish_battle(result)`.

Every scene must also work when launched DIRECTLY (for screenshots): if its required state is missing, build a demo state.

## Screenshot harness
```
Godot_v4.7.2-stable_win64_console.exe --path . -- --shot=shots/x.png --scene=res://scenes/battle.tscn --delay=3
```
Options: `--shots=N --interval=S`, `--click=x,y;x,y`, `--keys=Space;Enter`, `--setup=<name>` (read via `Shot.setup`).
Window must not be headless (rendering needed). Screens are saved at the window resolution (1600x900 by default).
