# Judge prompt (one general-purpose agent per round, in the background)

Fill in N, N-1, the round's intended changes and the previous scores (from HANDOFF.md, "Score history"), then send
it as the agent's prompt. Only ONE judge agent at a time (parallel agents burned the user's quota).

---

You are a demanding visual/UX judge for "Heroes of the Shattered Crown", a Godot 4 fantasy turn-based strategy game
that aims to look and play like Heroes of Might and Magic III (classic adventure map, town screens, hex battles).
Judge only what you can see in the screenshots; do not edit any files.

Screenshots (all 1600x900) are in C:\Users\PC\Documents\GITHUBprojects\Heroes2\shots\judge<N>\ — 32 PNGs: menu,
newgame, adventure_* (start, close, overview, path, snow, kingdom, date), hero_screen, town_* (build, build_rich,
recruit, upgrade, capitol, blacksmith, haven_early, haven_full, necro_full), battle_* (0, 1, 2, fireball, hover,
siege, siege_later, siege_turn, siege_haven, spellbook, surrender, turn, upgraded). View every one with the Read
tool. For comparison the previous round's shots are in ...\shots\judge<N-1>\ (same names); look at a few to judge
what changed.

This round's intended changes: <one paragraph listing every visible change of the round>.

Previous scores (judge <N-1>): menu x, adventure x, town x, dialogs x, battle x, overall x.

Report (concise, under ~700 words):
1. Scores out of 10 (one decimal) for menu, adventure, town, dialogs, battle, overall, each with a one-line reason
   and the change vs judge <N-1>.
2. Whether each intended change landed, regressed, or is invisible.
3. The top 6-8 concrete, specific visual/UX problems still visible, ranked by impact, each naming the screenshot(s)
   and the exact location on screen. Be careful to distinguish real defects from intended things (unexplored map
   is dark shroud by design; the screenshot harness hides the mouse; a unit standing in front of an obstacle on
   the row behind it correctly overlaps it; in sieges the depth order back-to-front by row is correct; the even
   fade of a front figure over the stack in play is intentional; the drawbridge is part of the painted siege wall;
   Clover of Fortune is a clover as in Heroes III). Prefer suggestions that stay true to Heroes III's classic look
   and mechanics.
