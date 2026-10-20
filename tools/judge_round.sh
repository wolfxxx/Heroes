#!/bin/sh
# Takes the judge screenshot set for round N into shots/judgeN, restores project.godot and checks that all 32 shots
# are 1600x900. Then launch ONE judge agent with the prompt in tools/judge_prompt.md (see HANDOFF.md).
#   sh tools/judge_round.sh 41
cd "$(dirname "$0")/.."
N=${1:?usage: sh tools/judge_round.sh N}
sh tools/judge_shots.sh shots/judge$N >/dev/null 2>&1
git checkout -- project.godot
python -c "
import glob
from PIL import Image
fs = glob.glob('shots/judge$N/*.png')
print(len(fs), 'shots (want 33), wrong size:', [f for f in fs if Image.open(f).size != (1600, 900)])"
git status --short
