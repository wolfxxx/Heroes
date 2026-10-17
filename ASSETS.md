# Asset Manifest (contract between art/audio pipeline and code)

Sprites rendered by tools/art/blender use a fixed world scale and write their foot point to `<dir>/anchors.json`
(map art: 64 px per Blender unit, drawn at 0.5 => 2 units per 64px tile; creatures: 150 px/unit). Code reads it
with `Assets.anchor()`. Extra map decor ids: `map/mountain_snow_1..2.png`; `map/obelisk.png` is the Learning Stone.

All paths relative to `res://assets/`. Code loads via `Assets.tex("<path>")` which falls back to a
generated placeholder if the file is missing, so code and art can progress independently.
**PNG with real alpha transparency** for all sprites/icons. Style: painterly high-fantasy,
rich saturated colours, warm lighting from the top-left, in the spirit of Heroes of Might and Magic III/V.

## Creatures — `creatures/<id>.png`
Side-view full-body battle sprite, **facing RIGHT**, transparent background, feet touching bottom-centre,
~512px tall canvas (square 512x512, 2-hex creatures 768x512). Ids: see `GameData.CREATURES`:
pikeman archer griffin swordsman monk cavalier angel skeleton zombie ghost vampire lich dread_knight bone_dragon
Also `creatures/portraits/<id>.png` — 128x128 bust/head close-up with painted background (used in recruit/army slots).

**Source models.** Creatures, hero portraits and mounted hero sprites are rendered from Sketchfab library models
(see `CREDITS.md`), not the procedural `figures.py` bodies. `tools/art/blender/imported.py` downloads a model
(key from the Blender MCP addon), `adopt()`s it (3/4 facing, height, feet on the ground), and renders it with the
same camera/lights/scale as before. Per-model settings (turn, height, hidden parts, tint, portrait framing) live
in `tools/art/imported_specs.json`; the posed models are cached as `tools/art/raw/models/<id>.glb` (git-ignored).
Re-render everything with batch step `"imported"`, then the usual `postfx.py` + `portrait_bg.py`.
`python tools/art/credits.py` regenerates `CREDITS.md`. The ghost model is CC-BY-NC (non-commercial only).

**Painted over.** All renders are then painted over by Gemini image models on Vertex AI (`tools/art/vertex_paint.py`,
project id from `GOOGLE_CLOUD_PROJECT` or `imagegen/vertex_project.txt`): portraits and towns via
`imagegen_prep.py` / `town_groups.py` / `imagegen_ingest.py`, sprites and battlefields via `sprite_paint.py`
(original alpha and soft shadows kept). `assets/creatures/sizes.json` (`tools/art/sprite_sizes.py`) holds each
figure's solid size; battle scales units by tier from it.

**Poses** — `creatures/<id>_attack.png`, `_hit.png`, `_dead.png` (optional; anchors in `creatures/anchors.json`).
Drawn by the image model from the painted idle sprite on a magenta backdrop (`tools/art/pose_paint.py`), keyed,
scaled to the idle figure, with a synthetic cast shadow. Battle swaps to them during attacks, on damage, and
leaves the `_dead` sprite on the hex as a corpse.

## Heroes
- `heroes/portraits/<hero_id>.png` — 256x256 painted portrait (ids in `GameData.HEROES`).
- `heroes/map_<faction>.png` — mounted hero on horse, 3/4 top-down view for the adventure map, transparent, 160x160, facing right.
- `heroes/battle_<faction>.png` — hero on horse for the battle screen corner, transparent, ~300x300, facing right.
- `heroes/flag_<color>.png` optional (color = red/blue/green/gold).

## Adventure map
- `terrain/<terrain>.png` — seamless tileable 512x512 top-down ground textures: grass dirt sand snow swamp water road.
- `map/town_<faction>.png` — town as seen on adventure map (3/4 oblique top-down), transparent, ~384x288 (occupies ~5x3 tiles at 64px; the entrance gate at bottom centre).
- `map/<mine_id>.png` — mines (ids in `GameData.MINES`), transparent, ~192x160.
- `map/res_<resource>.png` — resource pile on the ground, transparent, ~96x80.
- `map/chest.png`, `map/campfire.png`, `map/artifact.png` (generic artifact pedestal/glow), `map/shrine.png` (magic shrine),
  `map/windmill.png`, `map/obelisk.png`, `map/dwelling_neutral.png`, `map/watchtower.png`.
- Decorations, transparent: `map/tree_oak_1..4.png`, `map/tree_pine_1..3.png`, `map/tree_dead_1..2.png`,
  `map/mountain_1..3.png` (large ~256x224), `map/rock_1..3.png`, `map/bush_1..2.png`, `map/flowers_1..2.png`, `map/snow_pine_1..2.png`.
- Ground details `map/decor_<name>.png` (stump, log, toadstools, tuft, boulders, wildflowers, fern, twigs, pillar, bones,
  thorns, menhir, snow_rock, ice, snow_stump, frost_shrub, cactus, horn_skull, dry_grass, sandstone, reeds, swamp_caps,
  mossy_log, swamp_shrub): painted as two 4x3 sheets on magenta by `tools/art/decor_paint.py` (imagegen/batch12),
  keyed, cut, given a cast shadow and an anchor. Which terrain gets which: `WorldGen.DECOR_KINDS`.
- Roads are not a texture of their own: `MapView` turns road tiles into smoothed polylines and a distance field, and
  `terrain.gdshader` paints cobbles there (gravel shoulder from `terrain/road.png`).
- `map/monster_<creature_id>.png` optional — default is to reuse the creature sprite scaled.

## Battle
- `battle/bg_<terrain>.png` — 1920x1080 painted battlefield backdrop (side/elevated view, open flat ground in the
  middle where the hex grid goes, horizon/scenery in the top ~25%). terrains: grass dirt sand snow swamp.
- `battle/obstacle_1..4.png` — rocks/stumps/skulls placed on hexes, transparent, ~160x128.

## Town screens
- `town/<faction>_bg.png` — 1920x1080 painted landscape backdrop of the town site (sky + ground, no buildings, or only the
  base walls/hill).
- `town/<faction>_<building>.png` — each building as a separate transparent sprite to composite on the backdrop.
  building ids: village_hall (also used for town_hall/city_hall with `town_hall`, `city_hall` variants), fort, citadel,
  tavern, marketplace, mage_guild_1, mage_guild_2 (also shown for guild levels 3-4), blacksmith, dwelling_1 .. dwelling_7.
  Rendered buildings are cropped layers of one 1920x810 scene; their pixel rects live in
  `town/layout_<faction>.json` (written by tools/art/town_crop.py). `scripts/town/town_layout.gd` is the fallback.
  Each faction has its own site: Haven is `tools/art/blender/townscreen.py` (round plaza before a white castle),
  Necropolis is `tools/art/blender/necro_town.py` (a moor below a black crag, skull gate, its own slots and buildings).
  The blockouts are painted over in non-overlapping groups (`tools/art/town_groups.py <faction> --out ... --full ...`,
  which also writes notes.json telling the painter what each building is).

## Icons & UI
- `icons/res_<resource>.png` — 64x64 resource icons.
- `icons/spell_<spell_id>.png` — 96x96 spell icons.
- `icons/artifact_<artifact_id>.png` — 96x96.
- `icons/skill_<skill_id>.png` — 64x64 secondary skills.
- `icons/stat_attack.png stat_defense.png stat_power.png stat_knowledge.png` 64x64.
- `icons/building_<faction>_<building>.png` — 160x100 thumbnails for the build screen (can be auto-cropped from town sprites).
- `ui/panel.png` — 9-slice ornate stone/wood panel texture (256x256, 48px border).
- `ui/button.png`, `ui/button_hover.png`, `ui/button_pressed.png` — 9-slice buttons (192x64, 20px border).
- `ui/frame_portrait.png` — ornate gold frame 160x160 (transparent centre).
- `ui/main_menu_bg.png` — 1920x1080 epic key art.
- `ui/logo.png` — game title logo "Heroes of the Shattered Crown", transparent.
- `ui/cursor_*.png` — 32x32: normal, move, attack, shoot, horse, spell, blocked.
- `ui/parchment.png` — parchment texture for dialogs.
- `ui/hex.png`, `ui/hex_hover.png` optional.

## Audio — `audio/`
- Music (`.mp3`): `music/menu.mp3`, `music/adventure_grass.mp3`, `music/adventure_dirt.mp3`, `music/town_haven.mp3`,
  `music/town_necropolis.mp3`, `music/battle.mp3`, `music/victory.mp3` (short sting), `music/defeat.mp3` (short sting).
- SFX (`.mp3`) in `sfx/`: click, build, recruit, gold_pickup, resource_pickup, chest_open, footstep_horse,
  new_day, new_week, level_up, spell_cast, magic_arrow, lightning, fireball, bless, curse, heal, meteor,
  arrow_shot, arrow_hit, sword_hit, blunt_hit, claw_hit, magic_hit, death_human, death_undead, death_beast,
  wings, battle_start, victory_cheer, defeat, move_step, retaliate, miss, flag_capture, mine_capture, error.
- Per-creature (optional): `sfx/<creature_id>_attack.mp3`, `sfx/<creature_id>_death.mp3`.
- Voice (optional): `voice/<line_id>.mp3` narrator lines: intro, victory, defeat, new_week.
