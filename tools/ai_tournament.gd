extends Node
## AI-vs-AI tournament: the current battle AI (scripts/battle/battle_ai.gd, BattleAI) against the frozen baseline
## (tools/ai/battle_ai_baseline.gd, BattleAIBaseline). Each pairing of armies is fought twice, the two AIs swapping
## sides, so neither army nor side favours one of them. Prints the win rate and the share of the starting army value
## each AI kept, overall and by kind of battle.
##   Godot_console.exe --headless --path . res://tools/ai_tournament.tscn -- --games=60
## Both battles of a pairing use the same dice, so two identical AIs split exactly 50%. A change counts as better
## when the paired figure (how much more of the same army it keeps) is above zero by more than its +- (two
## standard errors); use --games=300 (600 battles, about 15 seconds).

const KINDS := ["open", "heroes", "siege"]

func _ready() -> void:
	var games := 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
	var wins := {"new": 0, "base": 0, "draw": 0}
	var diffs := []
	var kept := {"new": 0.0, "base": 0.0}
	var by_kind := {}
	for k in KINDS:
		by_kind[k] = {"new": 0, "base": 0, "n": 0}
	for g in games:
		var kind: String = KINDS[g % KINDS.size()]
		var setup := _pairing(g, kind)
		var pk := [[0.0, 0.0], [0.0, 0.0]]  # [army][ai]: the share of that army each AI kept (0 current, 1 baseline)
		for swap in 2:
			var new_side := swap  # (the current AI plays side 0 in the first battle, side 1 in the second)
			var r := _fight(setup, 5000 + g, new_side)  # (the same dice both times: only the AIs differ)
			by_kind[kind]["n"] += 1
			if r["winner"] < 0:
				wins["draw"] += 1
			elif r["winner"] == new_side:
				wins["new"] += 1
				by_kind[kind]["new"] += 1
			else:
				wins["base"] += 1
				by_kind[kind]["base"] += 1
			kept["new"] += r["kept"][new_side]
			kept["base"] += r["kept"][1 - new_side]
			pk[new_side][0] = r["kept"][new_side]
			pk[1 - new_side][1] = r["kept"][1 - new_side]
		# (paired: the same army, played by each AI against the same opponent army played by the other)
		diffs.append((pk[0][0] - pk[0][1] + pk[1][0] - pk[1][1]) * 0.5)
	var n := games * 2
	print("AI TOURNAMENT: %d battles. current AI won %d (%.0f%%), baseline won %d, unfinished %d" % [n, wins["new"],
		100.0 * wins["new"] / n, wins["base"], wins["draw"]])
	print("  army value kept on average: current %.0f%%, baseline %.0f%%" % [100.0 * kept["new"] / n, 100.0 * kept["base"] / n])
	var mean := 0.0
	for d in diffs:
		mean += d
	mean /= maxf(1.0, diffs.size())
	var sd := 0.0
	for d in diffs:
		sd += (d - mean) * (d - mean)
	sd = sqrt(sd / maxf(1.0, diffs.size() - 1))
	print("  paired: the current AI keeps %+.1f points more of the same army (+-%.1f; better if clearly above 0)" % [
		100.0 * mean, 200.0 * sd / sqrt(maxf(1.0, diffs.size()))])
	for k in KINDS:
		var b: Dictionary = by_kind[k]
		print("  %-7s current %d - baseline %d (of %d)" % [k, b["new"], b["base"], b["n"]])
	get_tree().quit()

## Two armies of about equal value, one per faction (a different mix each game), with heroes, spells and war machines
## for "heroes" and "siege" games.
func _pairing(g: int, kind: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + g
	var armies := []
	var budget := 9000.0 + rng.randf() * 9000.0  # (the same for both: close battles, where the AI decides)
	for f in ["haven", "necropolis"]:
		var c: Array = GameData.FACTIONS[f]["creatures"]
		var a := [null, null, null, null, null, null, null]
		var slots := rng.randi_range(3, 7)
		for i in slots:
			var cid: String = c[rng.randi() % c.size()]
			if rng.randf() < 0.35:
				cid = GameData.FACTIONS[f]["upgrades"][GameData.CREATURES[cid]["tier"] - 1]
			var n := maxi(1, int(budget / slots / GameData.CREATURES[cid]["ai_value"]))
			a[i] = {"id": cid, "count": n}
		armies.append(a)
	var s := {"armies": armies, "kind": kind, "seed": 2000 + g}
	if kind != "open":
		s["heroes"] = ["sir_aldric", "lord_morthis"]
	return s

## One battle; `new_side` is the side the current AI plays. Returns the winner (-1 if it did not end) and, per side,
## the share of its starting army value still standing.
func _fight(p: Dictionary, seed: int, new_side: int) -> Dictionary:
	var L := BattleLogic.new()
	# (the two armies keep their own side: the AIs swap, not the armies, so a siege attacker stays the attacker)
	var setup := {"attacker_army": p["armies"][0].duplicate(true), "defender_army": p["armies"][1].duplicate(true),
		"seed": seed, "attacker_ai": true, "defender_ai": true}
	if p.has("heroes"):
		for k in 2:
			var h := GameState.make_hero(p["heroes"][k], k)
			h["machines"] = GameData.WAR_MACHINES.duplicate()
			h["spells"] = ["magic_arrow", "bless", "curse", "haste", "slow", "lightning_bolt", "fireball", "cure"]
			h["mana"] = GameState.max_mana(h) + 20
			setup["attacker_hero" if k == 0 else "defender_hero"] = h
	if p["kind"] == "siege":
		setup["siege"] = 2
	L.setup(setup)
	var start := [_value(L, 0), _value(L, 1)]
	var steps := 0
	while L.is_over() < 0 and steps < 800:
		steps += 1
		var s = L.current()
		if s == null:
			break
		if L.check_bad_morale(s) or (not s.get("machine", false) and L.check_fear(s)):
			L.finish_turn(s)
			continue
		if s.get("machine", false):
			L.machine_act(s)
			continue
		var cur: bool = s["side"] == new_side
		if not L.hero_cast[s["side"]]:
			var sp: Dictionary = BattleAI.decide_spell(L, s["side"]) if cur else BattleAIBaseline.decide_spell(L, s["side"])
			if not sp.is_empty():
				L.cast(s["side"], sp["spell"], sp["hex"])
				if L.is_over() >= 0 or not s["alive"]:
					continue
		var act: Dictionary = BattleAI.decide(L, s) if cur else BattleAIBaseline.decide(L, s)
		match act["type"]:
			"shoot": L.do_shoot(s, act["target"])
			"melee": L.do_melee(s, act["target"], act["from"])
			"move": L.do_move(s, act["hex"])
			"wait":
				if not L.do_wait(s):
					L.do_defend(s)
			_: L.do_defend(s)
		if act["type"] != "wait":
			L.roll_good_morale(s)
	return {"winner": L.is_over(), "kept": [_value(L, 0) / maxf(1.0, start[0]), _value(L, 1) / maxf(1.0, start[1])]}

func _value(L: BattleLogic, side: int) -> float:
	var v := 0.0
	for s in L.alive_stacks(side):
		if not s.get("machine", false):
			v += L.cdata(s)["ai_value"] * L.total_hp(s) / float(L.max_hp(s))
	return v
