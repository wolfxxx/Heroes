# Handoff — where the project stands and how to carry on

Read this first, then `ARCHITECTURE.md` (code map), `ASSETS.md` (every asset path and the art pipeline) and
`CREDITS.md`. This file is written so that another person or another AI assistant can pick the work up exactly
where it stopped. Last updated 2026-10-20, at commit `59129b0` (round 40), branch `main`, remote
`https://github.com/wolfxxx/Heroes.git` (public repo).

## 1. The project in one paragraph

"Heroes of the Shattered Crown" is a Heroes of Might and Magic III–style game in Godot 4.7 (GDScript): a random
adventure map with heroes, mines, monsters and fog; two factions (Haven, Necropolis) with painted town screens,
building and recruiting; hex battles with 14 creatures, war machines, spells and sieges; a computer opponent;
music and sound. All art is 3D library models rendered in Blender and then painted over by an image model, plus
painted icons and UI. The work has gone in **rounds**: an independent judge agent scores 32 screenshots against
the look and feel of HoMM3, and each round fixes what the judge found.

## 2. Status at round 40

- Everything is committed and pushed. All tests pass (see section 5).
- Judge 40 scores: menu 9.2, adventure 9.2, town 9.4, dialogs 9.5, battle 8.9, **overall 9.2**.
- Rounds 31–40 were run as one uninterrupted loop on the user's instruction ("build, commit and push, judge cycle
  until level 40 judge has run"). That authorisation ended with round 40: **from now on, commit and push only when
  the user asks.**
- The last thing discussed with the user (not yet started): four bigger topics — war-machine wreck graphics,
  multiplayer, AI quality, and artifacts with combinations. My recommendations are in section 8. The open question
  to the user was: *"Should I start on artifacts? I'd write up the proposed list and the combination sets for you
  to approve before building anything."*

## 3. Standing rules from the user (keep to them)

1. **Stay true to HoMM3.** Prefer the classic mechanics and look. When an idea deviates from HoMM3, say so clearly
   and ask before doing it. (The user rejected a "free unit order" option for that reason. The user did approve
   one non-HoMM3 aid: in battle, a figure standing in front of the stack in play fades so that stack can be seen.)
2. **One session, no teams of parallel agents** (they used up the user's quota). One background judge agent per
   round is fine.
3. **Commit or push only when asked.** Commit messages are one descriptive paragraph (see `git log`) and end with
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the equivalent line for whatever assistant is
   working).
4. **Always run `git checkout -- project.godot` after running Godot with a window** — Godot rewrites it. The test
   and judge scripts do it for you.
5. **Secrets**: the ElevenLabs key is only read from the env var `ELEVENLABS_API_KEY` and never printed; the
   Sketchfab key is read inside Blender and never printed; the Google Cloud (Vertex) project id lives in
   `imagegen/vertex_project.txt`, which is git-ignored — never put it in the repo (the repo is public). Don't go
   searching for other credentials.
6. The user's email is for git attribution only.
7. Don't use the phrase "Heroes of Might and Magic" in image-generator prompts.

## 4. Environment

- Windows 11, Git Bash for shell scripts. Godot console exe:
  `C:\Users\PC\Documents\Godot\Godot_v4.7.2-stable_win64_console.exe` (scripts use `$GODOT` if set).
- After adding or changing assets run `Godot --headless --path . --import` (the test script does this).
- Python 3 with PIL and numpy. Windows Python cannot open `/c/...` paths — use `C:/...` paths.
- Image painting: Google Vertex AI, model `gemini-nano-banana-2.1` at location `global`, via
  `tools/art/vertex_paint.py` (project id from `GOOGLE_CLOUD_PROJECT` or `imagegen/vertex_project.txt`; uses the
  machine's application-default credentials). About 30 s per image.
- Blender with the Blender MCP addon on port 9876 (`tools/art/blender/bl.py` talks to it directly for long jobs).
- Audio: ElevenLabs via `tools/audio/gen_audio.py`.
- `shots/` and `imagegen/` are git-ignored (screenshots and painting batches stay local).

## 5. Commands

| What | Command |
|---|---|
| Run the game | `run.bat` |
| Compile-check every script | `sh tools/check.sh` → `CHECK DONE, failures: 0` |
| Full test pass (~4 min) | `sh tools/run_tests.sh` (expected output is in its header) |
| One screenshot | `Godot --path . -- --shot=shots/x.png --scene=res://scenes/battle.tscn --delay=3 --setup=demo` |
| Judge screenshot set | `sh tools/judge_round.sh N` → `shots/judgeN/` (32 shots, 1600x900) |

Screenshot harness flags (`scripts/core/shot.gd`, coordinates in 1920x1080 space, images saved at 1600x900):
`--shot --scene --delay --shots --interval --click=x,y;x,y (prefix r for right click) --keys=A;S --hover=x,y`;
scenes also read `--setup=` (`demo`, `rich`, `new_game`, `all_spells`, `upgraded`, `siege`, `siege_haven`,
`necro_rich`, `necro_max`, `x`), `--seed --faction --reveal --cam=x,y --zoom --broken=a,b`. The harness parks the
mouse before each capture (except hover and right-click shots). The window must not be headless for shots.

## 6. The round workflow

1. Report the judge's results to the user and propose fixes (flag anything un-HoMM3).
2. On approval, implement; run `sh tools/run_tests.sh`; take verification shots and look at crops of the changed
   areas (for example with a small PIL crop script) before claiming anything.
3. Ask whether to commit, push and run the next judge.
4. On yes: update the docs (below), commit, push, `sh tools/judge_round.sh N`, then launch one background judge
   agent with `tools/judge_prompt.md` filled in. Report its scores and findings, check its claims against the shots
   (judges sometimes misread things), add the scores and findings to this file, and start again at step 1.

**Keeping the docs current is part of every change** (the user asked for it): with each commit, update this file
(status and last commit in §1–2, the score history in §7, open findings and next steps in §8, new systems in §9, new
gotchas in §10), `ARCHITECTURE.md` for new scripts, systems or tools, `ASSETS.md` for new asset paths or art tools,
and `CREDITS.md` for new third-party assets.

Painting new icons: add a sheet to `SHEETS` in `tools/art/button_icons_paint.py`, then
`python tools/art/button_icons_paint.py paint <sheet>` (→ `imagegen/batch20/out/<sheet>.png`), look at it, then
`... ingest <sheet>`, keep the best take under the final name and delete the other takes. Check glows on the
magenta key for pink fringes (recolour them, as was done for the Luck clover).

## 7. Score history (overall, with the weakest area)

| Judge | Menu | Adventure | Town | Dialogs | Battle | Overall |
|---|---|---|---|---|---|---|
| 5 | 5.5 | 6.5 | 7 | 5.5 | 5.5 | 6 |
| 6 | 6 | 7 | 7 | 6.5 | 6 | 6.5 |
| 28 | 8.5 | 8.5 | 8.5 | 9.0 | 8.5 | 8.5 |
| 29 | 8.6 | 8.7 | 8.6 | 9.0 | 8.5 | 8.6 |
| 30 | 8.7 | 8.8 | 8.6 | 9.0 | 8.4 | 8.6 |
| 31 | 8.8 | 8.8 | 8.7 | 9.0 | 8.5 | 8.7 |
| 32 | 8.9 | 8.9 | 8.8 | 9.1 | 8.5 | 8.8 |
| 33 | 9.0 | 9.0 | 8.9 | 9.2 | 8.5 | 8.9 |
| 34 | 9.1 | 9.1 | 9.0 | 9.2 | 8.6 | 9.0 |
| 35 | 9.1 | 9.1 | 9.1 | 9.2 | 8.7 | 9.0 |
| 36 | 9.1 | 9.2 | 9.2 | 9.2 | 8.8 | 9.1 |
| 37 | 9.1 | 9.2 | 9.2 | 9.3 | 8.9 | 9.1 |
| 38 | 9.2 | 9.2 | 9.2 | 9.4 | 8.9 | 9.2 |
| 39 | 9.2 | 9.2 | 9.3 | 9.4 | 8.8 | 9.2 |
| 40 | 9.2 | 9.2 | 9.4 | 9.5 | 8.9 | 9.2 |

Trend: gains have flattened at 9.2 for three rounds. Battle is the weakest area; the next big step most likely comes
from battle (crowded siege melees, the lightning effect) or from new gameplay (section 8), not more small polish.

## 8. What's next

### Open findings from judge 40 (ranked)
1. Lightning storm cloud looks like a flat cartoon blob (`battle.gd` class `_Burst`, the `bolt` branch); its pale
   lit underside reads as a selection ring. Options: paint it properly, or drop the cloud and bring the bolt from
   the top of the screen as HoMM3 does.
2. The bolt's shape varies (thin S-curve in the open field, jagged in the siege) — make it consistently jagged.
3. Unreadable melee clusters at the siege gate (`battle_siege_haven`, `battle_siege_later`): the Ghost, Angel and
   Vampire overlap. Several rounds of plate moves, fades and shrinking only helped a little.
4. Build cards: a row with a two-line price has shorter pictures than other rows (`town_screen.gd` `_BuildCard`,
   `min_rows` set per row in `_open_build`).
5. Empty wood in the town bottom bar between the garrison and the dwelling portraits.
6. The enemy hero is hard to see against the dark Necropolis siege backdrop.
7. War-machine names in the turn queue come out in three sizes (the shrink-to-fit in `_QueueIcon._draw`).
8. Small New Game card text (starting-bonus captions).

The siege drawbridge reads as a stray plank, but it is part of the painted siege wall art; it was left alone.

### The four bigger topics the user raised (recommendations given, awaiting a go-ahead)
Suggested order: **artifacts → AI → hot-seat multiplayer → war-machine wrecks** (the last can go in any round).

1. **Artifacts and combinations** (high value, true to HoMM3). Today: 11 plain stat artifacts in
   `GameData.ARTIFACTS` and no tiers, sets or special effects. Proposal: about 30–40 artifacts in HoMM3's tiers
   (treasure / minor / major / relic) that let a hero specialise (might, magic schools, logistics, economy,
   necromancy), plus 2–3 **combination artifacts** the HoMM3 way: when all parts are worn they merge into one item
   with a stronger effect (for example Dragon Sword + Shield + Helm → "Dragonheart Arms"). A set bonus while the
   pieces stay separate would be the RPG way, not HoMM3's — flag it if the user prefers that. First step: write
   the list and the sets for the user to approve.
2. **Computer opponent.** `scripts/adventure/adv_ai.gd` (~220 lines) is greedy: value ÷ distance per hero this
   turn, a fixed build order, fixed strength ratios, no defending threatened towns, no multi-turn plans, no troop
   transfers between heroes, no map spells, and it likely sees through the fog (it reads the whole object list).
   `scripts/battle/battle_ai.gd` (~150 lines) scores the best strike or shot now minus the retaliation; it never
   waits or defends, doesn't block shooters and doesn't bait retaliations. First step: an AI-vs-AI tournament
   harness (extend `tools/sim_test`) that records win rates, so changes are proven; then battle AI, then map AI
   and the existing Easy/Normal/Hard setting.
3. **Multiplayer.** None today (`world_gen.gd`: `"is_ai": i != 0`). Step 1, hot-seat (players sharing one
   computer, as HoMM3): choose human/computer per player on New Game, a "pass to the next player" screen,
   human-vs-human battles. Step 2, online play, is its own large project: an authoritative host, deterministic
   seeded randomness in battle and on the map, disconnects, saving. Keep these rules from now on: all game state
   stays in saveable dictionaries, all randomness goes through a seeded generator, screens never change the rules'
   state directly (the split of `adv_rules`/`battle_logic` from the views already helps).
4. **War-machine wrecks.** The ballista, first aid tent, ammo cart and catapult have no destroyed picture. The
   battle already swaps to `creatures/<id>_dead.png` when it exists, so painting a broken version of each with
   `tools/art/pose_paint.py` is about one session.

## 9. Where the recent systems live (rounds 29–40)

- **Map edge**: `scripts/adventure/fog.gdshader` draws the shroud, the slate void past the edge and a rocky ridge
  (`rock_h` height map: warped power-diagram boulders + crags; `ridge` lighting; `band`/`enc` set how far it runs
  out and onto the map). `map_view.gd` `_build_border()` places the map's own mountain sprites around the edge
  (seeded, varied sizes, pairs, boulders), drawn over the fog at z 51 with `border_rock.gdshader` turning their
  grass skirts to ochre rock. The camera may run 2 tiles past the edge (`adventure.gd`, `margin`).
- **Battle readability** (`scripts/battle/battle.gd`):
  - `_see_through()` — feet-holes in a figure standing in front of a stack; a figure covering the stack in play
    (active / hovered / struck) fades evenly via the `body_alpha` uniform of `scripts/ui/sprite_outline.gdshader`;
    the active stack gets a pulsing halo (`team` uniform).
  - `_crowd()` — wide-winged figures and figures in 3+ / 4+ stack melees draw smaller.
  - `_settle_badges()` — count plates: front corner, moved in under their own figure when a front neighbour is
    taken, never on another stack's figure (body penalty, back-corner and raised spots).
  - `_under_figures()` — low obstacles fade where a figure stands over them.
  - `_Shadow` — rings; a struck stack's ring flares in its own side colour.
  - `_QueueIcon` — turn queue; machines and towers drawn whole with a name band.
  - `_Burst` (bolt) — lightning from a storm cloud, drawn on the rings layer, under the figures.
  - Damage labels vanish at once (no fade) — `_float_text`.
- **Rules change**: the ammo cart never takes a turn (`battle_logic.gd` `_new_round` and `upcoming`), as in HoMM3.
- **Town**: `_BuildCard` price rows (one row at one of three sizes, else two; `min_rows` per card row), the
  full-width inset treasury and date (`town_screen.gd` top), bigger price icons everywhere (`HoverInfo.cost_row`,
  `_DwellingCard`), the upgrade dialog with a drawn gilt arrow (`army_strip.gd` `_Arrow`).
- **Icons** painted this stretch (`tools/art/button_icons_paint.py` sheets `conditions`, `conditions2`, `skills`,
  `stats`, `knowledge`, `misc_stats`, `tome`): scenario conditions `ui/cond_*.png`, all secondary skills
  `icons/skill_*.png`, primary stats and morale `icons/stat_*.png` (Knowledge = lamp and scroll), health / damage /
  xp / speed `icons/stat_*.png`, the hero screen's closed spellbook `icons/spellbook_closed.png`.

## 10. Gotchas learned the hard way

- Godot shaders: no `return` inside `fragment()`. In a canvas shader, `COLOR` already holds the sampled and
  modulated texture — multiplying by `COLOR` again squares the colour.
- GDScript treats "inferred from Variant" as an error here: type such variables explicitly (`var t: String = ...`).
- The judge sees still frames at deterministic times: an effect that is mid-fade at that moment looks broken every
  round. Prefer states that read well at any moment (labels vanish instead of fading).
- A shot can be spoiled by the real OS cursor over the window; the harness ignores off-window motion and parks the
  mouse before capture.
- Painting on magenta leaves pink fringes around glows: recolour pixels where `(r+b)/2 - g` is large.
- Judges contradict each other between rounds (for example plates "on the wrong figure" vs "floating above its
  own"); check against the shots before acting.
- Blender: never remove data blocks one by one in loops (use `bpy.data.batch_remove`); MCP calls over ~2 min report
  "No data received" while the job continues.
