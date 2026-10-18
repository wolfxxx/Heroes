#!/bin/sh
# Screenshot set for a judge round (compare with the classic game):  sh tools/judge_shots.sh shots/judge6
# Uses the Shot harness (scripts/core/shot.gd); coordinates are in 1920x1080 viewport space.
D=${1:-shots/judge}
G=${GODOT:-/c/Users/PC/Documents/Godot/Godot_v4.7.2-stable_win64_console.exe}
mkdir -p "$D"
run() { timeout 150 "$G" --path . -- "$@" 2>&1 | grep -E 'SHOT|SCRIPT ERROR' | sed "s|.*$D/||"; }
run --shot=$D/menu.png --delay=3
run --shot=$D/newgame.png --delay=3 --setup=new_game
run --shot=$D/adventure_start.png --scene=res://scenes/adventure.tscn --delay=4 --setup=demo
run --shot=$D/adventure_overview.png --scene=res://scenes/adventure.tscn --delay=4 --setup=x --reveal --cam=20,20 --zoom=0.7
run --shot=$D/adventure_close.png --scene=res://scenes/adventure.tscn --delay=4 --setup=x --seed=4242 --faction=necropolis --reveal --cam=12,12 --zoom=1.0
run --shot=$D/adventure_snow.png --scene=res://scenes/adventure.tscn --delay=4 --setup=rich --reveal --cam=9,17 --zoom=1.3
# one click on a road tile plans the route (arrows), a second would walk it
run --shot=$D/adventure_path.png --scene=res://scenes/adventure.tscn --delay=4 --setup=demo --click=810,598
run --shot=$D/hero_screen.png --scene=res://scenes/adventure.tscn --delay=3 --setup=all_spells --click=426,475
run --shot=$D/town_haven_early.png --scene=res://scenes/town.tscn --delay=3 --setup=demo
run --shot=$D/town_haven_full.png --scene=res://scenes/town.tscn --delay=3 --setup=rich
run --shot=$D/town_necro_full.png --scene=res://scenes/town.tscn --delay=3 --setup=necro_rich
run --shot=$D/town_build.png --scene=res://scenes/town.tscn --delay=3 --setup=demo --keys=B
run --shot=$D/town_build_rich.png --scene=res://scenes/town.tscn --delay=3 --setup=rich --keys=B
# right click the hero's pikemen: the upgraded guardhouse offers to upgrade them
run --shot=$D/town_upgrade.png --scene=res://scenes/town.tscn --delay=3 --setup=rich --click=r528,966
# click the smithy: war machines for the visiting hero
run --shot=$D/town_blacksmith.png --scene=res://scenes/town.tscn --delay=3 --setup=rich --click=1320,540
run --shot=$D/town_recruit.png --scene=res://scenes/town.tscn --delay=3 --setup=rich --keys=R
run --shot=$D/battle.png --scene=res://scenes/battle.tscn --delay=2 --setup=demo --shots=3 --interval=5 --keys=A
run --shot=$D/battle_upgraded.png --scene=res://scenes/battle.tscn --delay=3 --setup=upgraded
# a siege: walls, gate, moat and towers; auto combat, the catapult at work a few turns in
run --shot=$D/bs.png --scene=res://scenes/battle.tscn --delay=3 --setup=siege --seed=5 --shots=2 --interval=12 --keys=A
mv -f $D/bs_0.png $D/battle_siege.png; mv -f $D/bs_1.png $D/battle_siege_later.png
# hover twice: the first hover panel of a run can be mispositioned; keep the second
run --shot=$D/hv.png --scene=res://scenes/battle.tscn --delay=3 --setup=demo --hover="264,410;270,412" --shots=2 --interval=0.5
mv -f $D/hv_1.png $D/battle_hover.png; rm -f $D/hv_0.png
# open the book (S), pick Fireball, cast it on the ghosts; keep the frame with the explosion
run --shot=$D/fx.png --scene=res://scenes/battle.tscn --delay=3 --setup=demo --click="960,60;733,694;1596,576" --keys=S --shots=3 --interval=0.3
mv -f $D/fx_2.png $D/battle_fireball.png; rm -f $D/fx_0.png $D/fx_1.png
run --shot=$D/battle_spellbook.png --scene=res://scenes/battle.tscn --delay=3 --setup=all_spells --keys=S
