extends Node
## Battle-rules soak test: AI against AI with every creature (large ones included), checking after every action
## that no two stacks share a hex, nobody stands on an obstacle or off the field, and the battle ends.
##   Godot_console.exe --headless --path . res://tools/battle_test.tscn

func _ready() -> void:
	var fails := 0
	var ends := 0
	for seed in 40:
		var armies := []
		for f in ["haven", "necropolis"]:
			var c: Array = GameData.FACTIONS[f]["creatures"]
			var a := []
			for i in 7:
				a.append({"id": c[(i + seed) % 7] if seed % 3 == 0 else c[i], "count": [30, 18, 9, 6, 4, 2, 1][i] + seed % 5})
			armies.append(a)
		var L := BattleLogic.new()
		L.setup({"attacker_army": armies[seed % 2], "defender_army": armies[1 - seed % 2], "seed": seed,
			"attacker_ai": true, "defender_ai": true})
		var steps := 0
		while L.is_over() < 0 and steps < 600:
			steps += 1
			var s = L.current()
			if s != null and L.check_bad_morale(s):
				L.finish_turn(s)
				continue
			if s == null:
				break
			var act := BattleAI.decide(L, s)
			match act["type"]:
				"shoot": L.do_shoot(s, act["target"])
				"melee": L.do_melee(s, act["target"], act["from"])
				"move": L.do_move(s, act["hex"])
				_: L.do_defend(s)
			L.roll_good_morale(s)
			var err := _check(L)
			if err != "":
				print("FAIL seed %d step %d: %s" % [seed, steps, err])
				fails += 1
				break
		if L.is_over() >= 0:
			ends += 1
	print("BATTLE TEST: %d battles ended of 40, failures: %d" % [ends, fails])
	get_tree().quit()

func _check(L: BattleLogic) -> String:
	var seen := {}
	for s in L.alive_stacks():
		for c in L.cells(s):
			if not BattleLogic.in_bounds(c):
				return "%s off the field at %s" % [s["id"], c]
			if L.obstacles.has(c):
				return "%s on an obstacle at %s" % [s["id"], c]
			if seen.has(c):
				return "%s and %s share %s" % [s["id"], seen[c], c]
			seen[c] = s["id"]
	return ""
