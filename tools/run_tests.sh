#!/bin/sh
# Full test pass for a round (about 4 minutes). Expected results:
#   CHECK DONE, failures: 0
#   BATTLE TEST: 40 battles ended of 40, failures: 0
#   CLICK TEST: 26 clicks, 0 without a path   + DRAG TEST ... plan unchanged: true   + PENDING TEST ... shown: true
#   5                                           (visit test: five VISIT lines)
#   SIM DONE                                    (no SCRIPT ERROR lines)
# "N resources still in use at exit" warnings are old and harmless.
#   sh tools/run_tests.sh
cd "$(dirname "$0")/.."
G=${GODOT:-/c/Users/PC/Documents/Godot/Godot_v4.7.2-stable_win64_console.exe}
$G --headless --path . --import >/dev/null 2>&1
sh tools/check.sh 2>&1 | grep -E "CHECK DONE|SCRIPT ERROR|Parse Error|ERROR" | head -8
echo "--battle"; timeout 300 $G --headless --path . res://tools/battle_test.tscn 2>&1 | grep -E "BATTLE TEST|SCRIPT ERROR" | tail -4
echo "--click"; timeout 300 $G --path . res://tools/click_test.tscn 2>&1 | grep -E "clicks|DRAG|PENDING|SCRIPT ERROR|FAIL" | tail -5
echo "--visit"; timeout 300 $G --headless --path . res://tools/visit_test.tscn 2>&1 | grep -cE "VISIT"
echo "--sim"; timeout 300 $G --headless --path . res://tools/sim_test.tscn 2>&1 | grep -E "SCRIPT ERROR|FAIL|DONE|done" | tail -3
# (Godot rewrites project.godot when run with a window: always restore it)
git checkout -- project.godot
