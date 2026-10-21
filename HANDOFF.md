# Handoff — where the project stands and how to carry on

Read this first, then `ARCHITECTURE.md` (code map), `ASSETS.md` (every asset path and the art pipeline) and
`CREDITS.md`. This file is written so that another person or another AI assistant can pick the work up exactly
where it stopped. Last updated 2026-10-20 (round 47, battle readability, committed and pushed; judge 47 not run yet), branch `main`, remote
`https://github.com/wolfxxx/Heroes.git` (public repo).

## 1. The project in one paragraph

"Heroes of the Shattered Crown" is a Heroes of Might and Magic III–style game in Godot 4.7 (GDScript): a random
adventure map with heroes, mines, monsters and fog; two factions (Haven, Necropolis) with painted town screens,
building and recruiting; hex battles with 14 creatures, war machines, spells and sieges; a computer opponent;
music and sound. All art is 3D library models rendered in Blender and then painted over by an image model, plus
painted icons and UI. The work has gone in **rounds**: an independent judge agent scores 32 screenshots against
the look and feel of HoMM3, and each round fixes what the judge found.

## 2. Status

- **Artifacts and combination artifacts are built** (the user approved `docs/ARTIFACTS_PROPOSAL.md` as proposed:
  merging as in HoMM3, relics also on random maps, our own names). 41 artifacts in four tiers plus three
  combinations, effects in battle and on the map, tiered placement with guards, the hero screen (tier-coloured
  sockets, combinations across their slots, right-click to split or join), each artifact's own picture on the map,
  30 new painted icons, AI valuation, and `tools/artifact_test` (307 checks). Committed and pushed; judge 41 ran on
  it (scores in section 7). Next step of the plan: the AI work (section 8).
- Found and fixed on the way: the all-computer simulation could overflow Godot's message queue once one computer
  player had beaten the others (the AI turn loop never waited a frame); `_run_ai_turns` now waits one frame per turn.
- Round 47 (battle readability) committed and pushed; judge 47 not run yet. Root cause of the siege-gate knot found: while a stack's blow is
  still being animated the rules have already moved on (`L.current()` is the next stack), so the see-through fade,
  the halo and the stack's emphasis followed the wrong stack. `_see_through` now uses the stack the screen shows
  acting (`_grid.active`). Also: that stack is drawn over its neighbours while it acts (`z_index` 2), never gets
  feet-holes cut in itself, and a big figure just behind it fades to 0.3; a struck stack no longer fades the figures
  in front of it (its ring flare and label mark it — those fades made living figures look like corpses); corpses
  mid-grey (0.74) and slightly translucent; the lightning cloud dropped — the bolt falls from the sky just under the
  turn queue, behind the figures it passes (wherever the cloud formed it sat on another stack); the showcase
  artifacts kept further from the castle (the cape read as a flag on its tower). Checked over several siege runs:
  the active stack is on top and lit in each; when it lunges into a big target the two still overlap (the attack
  pose itself), and the behind-fade shows in some runs and not others (it eases in over a fraction of a second).
- Round 46 committed and pushed, judge 46 run on it: the adventure_artifacts regression fixed (artifacts skip only tiles right under a
  tree, and the stumps, logs and flowers right beside each are removed instead, so all five show again); corpses
  grey and low in contrast (the outline shader's saturation at 0.25 on death); the hero screen's Formation toggle dims
  the option not chosen. The judge 45 "fade did not trigger" finding was checked with a debug print on that siege
  frame: battle timing varies from run to run; in that re-run the Vampires stood clear, so the rule was left as it is.
  (Judge 46 then saw the knot again in its own run: it recurs in some runs — still open, see section 8.)
- Round 45 committed and pushed, judge 45 run on it: judge 44 fixes — a big figure just behind the stack whose turn it is fades too
  (`_see_through`, the 6th info field), fades a little lighter (0.55); corpses darker and greyer; a spell's log line
  shows with its banner (`_flush_log` in `_anim_spell`); the combination's greyed copy brighter; the showcase
  artifacts keep clear of trees and stumps. Battle AI step 2, measured with the tournament: shooters weigh a target by
  its share of the enemy army (`THREAT_TARGET` 1.0), buff spells valued at half (`BUFF` 0.5: over-valuing them lost
  army), the step-away of a blocked shooter built but left off (`STEP_AWAY`, neutral). Result vs the frozen baseline:
  53% wins, +1.9 points of army kept (+-1.0), up from +1.4. The siege-gate knot in battle_siege_later is only partly
  better (the Angel behind the Vampires now fades; the Vampires in the moat are still small and half hidden).
- Round 44 (AI work begins) committed and pushed, judge 44 run on it: `tools/ai_tournament.gd` plays the current battle AI against a
  frozen copy (`tools/ai/battle_ai_baseline.gd`, class `BattleAIBaseline`) on equal-value army pairings, each fought
  twice with the AIs swapping sides on the same dice (identical AIs split exactly 50%); it prints win rate and a
  paired "army kept" difference with an error bar. First battle-AI changes (`battle_ai.gd`, constants at the end):
  no retaliation counted from a stack that has already struck back this round (a real bug), retaliation weighed
  fully, enemy shooters favoured as melee targets (blocking them), and, when no strike is possible, holding just
  outside enemy melee reach unless the enemy has the stronger shooters or we storm the walls (waiting if nothing
  better). Measured: 52% wins, +1.4 points of army kept (+-0.9) over 600 battles — real but small. The battle scene
  and battle_test handle the AI's new "wait". Also the last artifact fixes from judge 43: soft star twinkle, a pale
  light instead of the relic's red disc, a greyed copy of the combination plus interlocked chain links in its taken
  sockets, no flowers under the showcase artifacts.
- Round 43 (artifact polish after judge 42) committed and pushed, judge 43 run on it: map artifacts without the flat glow plate
  (a dark contact shadow, a faint soft light, a slow twinkle on major and relic ones) and sized by tier by area (the
  relic banner was the smallest); a combination's ghost sockets in iron frames with only a purple chain mark (redrawn so
  it no longer reads as an infinity sign) and the combination itself with a lit rim and corner studs; objects track
  every tile their building covers (`WorldGen.covered`): wandering monsters and guards never stand beside another
  building's walls. A monster right at a mine's entrance is that mine's own guard, as in HoMM3 (judges have read it
  as "pressed between objects"; now listed as intended in `tools/judge_prompt.md`).
- Round 42 (artifact polish after judge 41) committed and pushed, judge 42 run on it: a combination's linked sockets greyed out with a
  chain mark, iron frames for non-artifact and empty sockets, copper for the treasure tier, dimmed backpack arrows,
  the sulfur pile repainted (it read as a flat yellow disc; `tools/art/map_pile.py`), guards no longer placed beside
  another object, trees just below an object turned into bushes (`WorldGen._clear_view_of_objects`), and a 33rd judge
  shot `adventure_artifacts` (`--setup=artifacts`). The placement changes alter generated maps, so judge 42's adventure
  shots show different maps from judge 41's.
- Round 40 is committed and pushed.
- Judge 40 scores: menu 9.2, adventure 9.2, town 9.4, dialogs 9.5, battle 8.9, **overall 9.2**.
- Rounds 31–40 were run as one uninterrupted loop on the user's instruction ("build, commit and push, judge cycle
  until level 40 judge has run"). That authorisation ended with round 40: **from now on, commit and push only when
  the user asks.**
- The four bigger topics the user raised and my recommendations are in section 8; artifacts (the first) are done.

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

Screenshot harness flags (`scripts/core/shot.gd`, coordinates in 1920x1080 space, images saved at 1600x900;
`--setup=artifacts` lays an artifact of each tier beside the first hero):
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
| 41 | 9.2 | 9.2 | 9.4 | 9.6 | 8.9 | 9.2 |
| 42 | 9.2 | 9.3 | 9.4 | 9.7 | 8.9 | 9.3 |
| 43 | 9.2 | 9.4 | 9.4 | 9.7 | 8.9 | 9.3 |
| 44 | 9.2 | 9.4 | 9.4 | 9.7 | 8.9 | 9.3 |
| 45 | 9.2 | 9.3 | 9.4 | 9.7 | 9.0 | 9.3 |
| 46 | 9.2 | 9.4 | 9.4 | 9.7 | 9.1 | 9.4 |

Trend: gains have flattened at 9.2 for three rounds. Battle is the weakest area; the next big step most likely comes
from battle (crowded siege melees, the lightning effect) or from new gameplay (section 8), not more small polish.

## 8. What's next

### Open findings from judge 46 (overall 9.4 — a new high; battle 9.1)
1. The siege-gate knot DID recur in judge 46's run (Vampires, whose turn it is, lying across the Angel; Ghosts on the
   Angel's head; Bone Dragon over the Cavaliers). Round 46's note that it "does not recur" was wrong: it recurs in
   some runs, not all. Needs a real fix (e.g. keep a stack's figure from overlapping a neighbour's, or a stronger
   fade/outline for the stack in play), checked over several runs.
2. In battle_siege_haven the living Bone Dragon and the Angel are drawn semi-transparent while the stack in play is far
   away; they now look like the grey corpses. Find which fade rule fires there.
3. Corpses are too dark (charcoal): raise them to mid-grey near the ground's brightness.
4. adventure_artifacts: the cape lies right behind the castle's tallest tower and reads as a flag on it.
5. Lightning: the cloud forms over the top-row stack; the bolt passes two stacks to reach its target.
6. adventure_overview: about 20 wandering monsters on one screen — denser than HoMM3.
7. battle_spellbook: the two page headings differ in size and colour.
8. hero_screen: the dimmed backpack arrows nearly vanish.

### Open findings from judge 45 (overall 9.3; battle up to 9.0, adventure down to 9.3)
Landed: spell log line with its banner, darker corpses, recognisable greyed combination copy.
1. The "big figure behind the stack in play fades" rule did NOT trigger in battle_siege_later (the judge
   pixel-diffed: the Angel behind the active Vampires is unchanged). Debug `_see_through` on that exact frame.
2. Regression: adventure_artifacts shows only 2 of its 5 artifacts — the tree/stump clearance in
   `_shot_artifacts` pushed three out of view; place them on clear grass near the hero instead.
3. Corpses are darker but warm sepia and upright (the Bone Dragon corpse still reads as a figure): desaturate
   much more and lower the contrast.
4. Lightning cloud over the top-row Skeletons; the bolt passes three stacks (reads as a chain hit).
5. Siege-gate knot (Angel, Ghosts, Vampires; Bone Dragon fused with the Cavaliers).
6. Hero-screen Formation toggle: the selected option is unclear.

### Open findings from judge 44 (first battle-AI round; overall 9.3)
The AI's choices read as sensible on screen (holding back, hitting the Angel after it retaliated, focusing targets).
1. battle_siege_later: the stack in play (Vampires) is buried under the Angel's wings and the Ghosts in a four-stack
   knot; the front-figure fade did not fire for it.
2. Corpses read as living units (battle_2, battle_1): darken/desaturate them more and keep them under the rings.
3. adventure_artifacts: the relic's pale light reads as a dark stain under the banner (drop it or make it warm
   white); a tree stump butts against the cape.
4. hero_screen: the greyed copy in a combination's taken sockets is too dark (~15%): lift it to 40-50%.
5. battle_siege_haven: the living Bone Dragon is drawn semi-transparent while it is not in front of the stack in
   play; its badge sits detached.
6. A spell banner is on screen with no log line yet (battle_0, battle_siege): log the cast when it is announced.
7. town_build_rich: a two-line price shifts that row's caption baseline.
8. adventure_overview: the map reads busier with wandering monsters than HoMM3's typical density.

### Open findings from judge 43 (second artifact polish round; overall 9.3, adventure 9.4)
1. Siege-gate pile-ups (battle_siege_haven, battle_siege_later) — unchanged, the main battle problem.
2. The map artifacts' twinkle shows as a hard white "+" in a still (looks like a debug mark): soft 4-point star with
   falloff, or hidden in its off phase.
3. The relic banner's baked shadow is a reddish disc offset from the pole's foot (`art_banner_of_the_muster.png`):
   a neutral dark ellipse centred under the foot.
4. The chain mark on a combination's taken sockets reads as an orbit symbol: two clearly interlocked links, or a
   greyed copy of the artifact behind the mark, as HoMM3.
5. Lightning cloud covers the top-row stack and the enemy hero (battle_0, battle_siege).
6. Ground flowers ring an artifact (adventure_artifacts, the cape): keep flat decor off artifact tiles.
7. Hero-screen Formation toggle: the selected option is unclear.
8. New Game starting-bonus card text is cramped.

### Open findings from judge 42 (artifact polish round; overall 9.3)
1. Siege-gate melee clusters still unreadable (battle_siege_haven, battle_siege_later); badges drift from their stacks.
2. Lightning: the storm cloud caps the back-row stack; in battle_siege the bolt zig-zags at a slant across other
   stacks instead of dropping straight onto the target.
3. Map artifact glow reads as a flat painted plate (worst: the relic's red disc); HoMM3 shows only a ground shadow —
   use a faint soft glow and a dark contact shadow; the relic banner is the smallest item, scale it up.
4. Hero screen: a combination's ghost sockets share its purple frame — give them iron frames (only the link mark in
   purple) and the combination a strong lit rim; the link mark reads a little like an infinity sign.
5. A few guards still stand pressed between objects (adventure_overview archer between the mound and hut,
   adventure_close wraith between hut and lake) — the new spacing rule did not catch these (decor or footprints).
6. Lakes look like decals (flat blue with a blurred brown halo); HoMM3 shores have a crisp sand or rock rim.
7. Battle figures small for their hexes (battle_turn, battle_upgraded).
8. Build cards with two-line prices make rows ragged (town_build_rich).

### Open findings from judge 41 (artifacts round, mostly fixed in round 42)
1. No artifact appears in any judge screenshot, so the map half of the feature was not judged: add a judge shot
   framed on placed artifacts (`tools/judge_shots.sh`).
2. A combination's linked sockets read as copies of the item: fade/desaturate them much harder and mark them
   (HoMM3 greys out the slots a combination takes); the Dragonheart Arms icon is low-contrast on the maroon ground.
3. Non-artifact sockets (war machines, spellbook, empty backpack cells) use a gold frame that reads as the "major"
   tier: give them a neutral dark-iron frame.
4. Bronze (treasure) and gold (major) tier frames are too close: push bronze toward copper and duller.
5. A flat gold oval on the map (adventure_snow ~1057,357; adventure_overview ~455,282) reads as a placeholder.
6. Map objects on neighbouring tiles overlap (two knights by the mine in adventure_snow; a gold pile inside a tree in
   adventure_close).
7. Backpack page arrows look active when everything fits on one page.
8. Still open from judge 40: storm cloud on the top-row stack, faint open-field bolt, siege-gate pile-ups.

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

1. **Artifacts and combinations — BUILT 2026-10-20** (see section 2 and `docs/ARTIFACTS_PROPOSAL.md`). Today: 11 plain stat artifacts in
   `GameData.ARTIFACTS` and no tiers, sets or special effects. Proposal: about 30–40 artifacts in HoMM3's tiers
   (treasure / minor / major / relic) that let a hero specialise (might, magic schools, logistics, economy,
   necromancy), plus 2–3 **combination artifacts** the HoMM3 way: when all parts are worn they merge into one item
   with a stronger effect (for example Dragon Sword + Shield + Helm → "Dragonheart Arms"). A set bonus while the
   pieces stay separate would be the RPG way, not HoMM3's — flag it if the user prefers that. The proposal
   (38 artifacts in four tiers, three combinations) is in `docs/ARTIFACTS_PROPOSAL.md`, **awaiting the user's
   answers to its four questions** before anything is built.
2. **Computer opponent — IN PROGRESS (round 44: tournament harness + first battle-AI changes, see section 2).** `scripts/adventure/adv_ai.gd` (~220 lines) is greedy: value ÷ distance per hero this
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
- **Artifacts** (2026-10-20): data `GameData.ARTIFACTS` / `ARTIFACT_TIERS`; rules `GameState.hero_stat`,
  `hero_flags`, `artifact_slots`, `can_wear`, `give_artifact`, `swap_artifact`, `merge_combinations`,
  `split_combination`, `join_combination`; battle `BattleLogic.max_hp / speed / spell_damage / immune`, necromancy in
  `battle.gd`; map `AdvRules.hero_scout_radius`, `new_day` (gold, mana, muster growth); placement
  `WorldGen._place_artifacts`; hero screen `hero_screen.gd` (`_placed`, `_artifact_tip`, `_Socket.tier_col / linked /
  rpressed`); map picture `MapView._object_node` + `_ArtifactGlow`; test `tools/artifact_test.gd`.
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
- Battle shots are not reproducible frame for frame (animation and AI timing vary between runs): a judge's finding
  about one stack's position in an auto-battle shot may not recur; check the rule, not just the frame.
- The judge sees still frames at deterministic times: an effect that is mid-fade at that moment looks broken every
  round. Prefer states that read well at any moment (labels vanish instead of fading).
- A shot can be spoiled by the real OS cursor over the window; the harness ignores off-window motion and parks the
  mouse before capture.
- Painting on magenta leaves pink fringes around glows: recolour pixels where `(r+b)/2 - g` is large.
- Judges contradict each other between rounds (for example plates "on the wrong figure" vs "floating above its
  own"); check against the shots before acting.
- The screenshot harness's `--hover` did not bring up the adventure map's hover panel for objects (tested on an
  artifact); battle and town hover shots work. Not investigated.
- Blender: never remove data blocks one by one in loops (use `bpy.data.batch_remove`); MCP calls over ~2 min report
  "No data received" while the job continues.
