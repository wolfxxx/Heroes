extends RefCounted
class_name BattleAI
## Combat AI: scores every shot / melee option by expected value killed minus expected retaliation;
## otherwise advances on the most valuable enemy. Heroes cast the best-scoring spell once per round.

static func _value_of_damage(L: BattleLogic, t: Dictionary, dmg: float) -> float:
	var c := L.cdata(t)
	var dealt := minf(dmg, float(L.total_hp(t)))
	var v := dealt / float(L.max_hp(t)) * float(c["ai_value"])
	if dealt >= L.total_hp(t):
		v *= 1.3  # finishing a stack removes its retaliation and its turn
	return v

static func _avg(r: Array) -> float:
	return (r[0] + r[1]) * 0.5

static func decide(L: BattleLogic, s: Dictionary) -> Dictionary:
	var enemies := L.alive_stacks(1 - s["side"])
	if enemies.is_empty():
		return {"type": "defend"}
	if L.can_shoot(s):
		var best := {}
		var bv := -1.0
		for e in enemies:
			var v := _value_of_damage(L, e, _avg(L.damage_range(s, e, true)))
			if L.cdata(e)["shots"] > 0:
				v *= 1.25  # silence enemy shooters first
			if v > bv:
				bv = v
				best = e
		return {"type": "shoot", "target": best}
	var reach := L.reachable(s)
	var best_act := {}
	var best_score := -1e9
	for e in enemies:
		for h in L.attack_positions(s, e, reach):
			var moved: int = reach.get(h, 0)
			var dmg := _avg(L.damage_range(s, e, false, moved))
			var score := _value_of_damage(L, e, dmg)
			# estimated retaliation
			if not L.has_ab(s, "no_retaliation") and dmg < L.total_hp(e):
				var left_frac := 1.0 - dmg / float(L.total_hp(e))
				var tmp: Dictionary = e.duplicate()
				tmp["count"] = maxi(1, int(e["count"] * left_frac))
				score -= 0.6 * _value_of_damage(L, s, _avg(L.damage_range(tmp, s, false)))
			# prefer staying put when already adjacent
			if h == s["hex"]:
				score += 5.0
			score -= _stage_cost(L, s, e, h)
			if score > best_score:
				best_score = score
				best_act = {"type": "melee", "target": e, "from": h}
	if not best_act.is_empty():
		return best_act
	# Advance toward the juiciest enemy.
	var target: Dictionary = enemies[0]
	var tv := -1.0
	for e in enemies:
		var v: float = L.cdata(e)["ai_value"] * e["count"] / (1.0 + L.stack_distance(s, e))
		if v > tv:
			tv = v
			target = e
	var best_h: Vector2i = s["hex"]
	var bd := L.distance(s["hex"], target["hex"])
	for h in reach:
		var d := L.distance(h, target["hex"])
		if d < bd or (d == bd and reach[h] < reach.get(best_h, 99)):
			bd = d
			best_h = h
	if best_h == s["hex"]:
		return {"type": "defend"}
	return {"type": "move", "hex": best_h}

## Staging of a melee (a tie-break between spots to strike the same target from): side by side in the target's row
## reads best, as in the classics; a spot right above or below other stacks piles the figures on each other.
static func _stage_cost(L: BattleLogic, s: Dictionary, e: Dictionary, h: Vector2i) -> float:
	var cost := 0.0 if h.y == e["hex"].y else 3.0
	var mine: Array = L.cells(s, h)
	for o in L.alive_stacks(0) + L.alive_stacks(1):
		if o == s:
			continue
		var near := false
		for c in L.cells(o):
			for m in mine:
				if absi(c.y - m.y) == 1 and absf(_col(c) - _col(m)) <= 0.5:
					near = true
		if near:
			cost += 2.0
	return cost

static func _col(h: Vector2i) -> float:
	return h.x + (0.5 if h.y % 2 == 1 else 0.0)

static func decide_spell(L: BattleLogic, side: int) -> Dictionary:
	if not L.can_cast(side):
		return {}
	var h = L.heroes[side]
	var best := {}
	var bv := 0.0
	var enemies := L.alive_stacks(1 - side)
	var allies := L.alive_stacks(side)
	for sp in h["spells"]:
		var d: Dictionary = GameData.SPELLS[sp]
		if d["mana"] > h["mana"]:
			continue
		match d["target"]:
			"enemy":
				for e in enemies:
					if L.immune(e["side"], sp):  # (protected by a combination artifact)
						continue
					var v := 0.0
					if d.has("damage"):
						v = _value_of_damage(L, e, L.spell_damage(side, sp))
					elif sp == "slow" and not e["effects"].has("slow"):
						v = L.cdata(e)["ai_value"] * e["count"] * 0.12
					elif sp in ["curse", "weakness"] and not e["effects"].has(sp):
						v = L.cdata(e)["ai_value"] * e["count"] * 0.1
					if v > bv:
						bv = v
						best = {"spell": sp, "hex": e["hex"]}
			"ally":
				for a in allies:
					if L.immune(a["side"], sp):
						continue
					var v := 0.0
					if sp in ["bless", "haste", "shield", "stone_skin"] and not a["effects"].has(sp):
						v = L.cdata(a)["ai_value"] * a["count"] * (0.15 if sp in ["bless", "haste"] else 0.08)
					elif sp in ["cure", "resurrection"]:
						var lost: int = L.start_counts.get(a["uid"], a["count"]) - a["count"]
						if lost > 0 or sp == "cure":
							v = minf(lost * L.cdata(a)["ai_value"], (40.0 + 20 * L.spell_power(side)) / L.max_hp(a) * L.cdata(a)["ai_value"]) if sp == "resurrection" else (60.0 if a["effects"].has("curse") or a["effects"].has("slow") else 0.0)
					if v > bv:
						bv = v
						best = {"spell": sp, "hex": a["hex"]}
			"area":
				for e in enemies:
					var v := 0.0
					for s in L.stacks_on([e["hex"]] + BattleLogic.neighbors(e["hex"])):
						if L.immune(s["side"], sp):
							continue
						var val := _value_of_damage(L, s, L.spell_damage(side, sp))
						v += val if s["side"] != side else -1.2 * val
					if v > bv:
						bv = v
						best = {"spell": sp, "hex": e["hex"]}
			"all_living":
				var v := 0.0
				for s in L.alive_stacks():
					if not L.has_ab(s, "undead") and not L.immune(s["side"], sp):
						var val := _value_of_damage(L, s, L.spell_damage(side, sp))
						v += val if s["side"] != side else -1.0 * val
				if v > bv:
					bv = v
					best = {"spell": sp, "hex": Vector2i(7, 5)}
	return best if bv > 40.0 else {}
