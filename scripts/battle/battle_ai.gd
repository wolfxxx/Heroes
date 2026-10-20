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
			if L.cdata(e)["shots"] > 0 and e["shots"] > 0:
				score *= SHOOTER_BLOCK  # (a shooter held in melee shoots no more and strikes at half: block it)
			# estimated retaliation
			# (none if it has already struck back this round: as the classic computer, strike it now with the stack
			# that would otherwise suffer the retaliation)
			if not L.has_ab(s, "no_retaliation") and dmg < L.total_hp(e) and e["retaliations"] > 0:
				var left_frac := 1.0 - dmg / float(L.total_hp(e))
				var tmp: Dictionary = e.duplicate()
				tmp["count"] = maxi(1, int(e["count"] * left_frac))
				score -= RETALIATION * _value_of_damage(L, s, _avg(L.damage_range(tmp, s, false)))
			# prefer staying put when already adjacent
			if h == s["hex"]:
				score += 5.0
			score -= _stage_cost(L, s, e, h)
			if score > best_score:
				best_score = score
				best_act = {"type": "melee", "target": e, "from": h}
	if not best_act.is_empty():
		return best_act
	# No strike this turn. As the classic computer: unless the enemy has the stronger shooters (or we must storm the
	# walls), hold just outside the reach of the enemy's melee stacks, so they come to us and we strike first;
	# otherwise advance, by the least exposed way.
	var hold: bool = HOLD and _shoot_power(L, s["side"]) >= _shoot_power(L, 1 - s["side"]) * HOLD_RATIO \
		and not (L.siege > 0 and s["side"] == 0)
	var threat := _threats(L, s, reach)
	# Advance toward the juiciest enemy.
	var target: Dictionary = enemies[0]
	var tv := -1.0
	for e in enemies:
		var v: float = L.cdata(e)["ai_value"] * e["count"] / (1.0 + L.stack_distance(s, e))
		if v > tv:
			tv = v
			target = e
	var best_h: Vector2i = s["hex"]
	if hold:
		# the nearest spot to the target that no enemy can reach next turn; else the least threatened
		var bkey := Vector2(threat.get(s["hex"], 0.0), L.distance(s["hex"], target["hex"]))
		for h in reach:
			var key := Vector2(threat.get(h, 0.0), L.distance(h, target["hex"]))
			if key.x < bkey.x - 0.01 or (absf(key.x - bkey.x) <= 0.01 and key.y < bkey.y):
				bkey = key
				best_h = h
		if best_h == s["hex"]:
			if WAIT and not s["waited"] and L.order.size() > 1:
				return {"type": "wait"}
			return {"type": "defend"}
		return {"type": "move", "hex": best_h}
	var bd := L.distance(s["hex"], target["hex"])
	var bt: float = threat.get(s["hex"], 0.0)
	for h in reach:
		var d := L.distance(h, target["hex"])
		var t: float = threat.get(h, 0.0)
		if d < bd or (d == bd and (t < bt - 0.01 or (absf(t - bt) <= 0.01 and reach[h] < reach.get(best_h, 99)))):
			bd = d
			bt = t
			best_h = h
	if best_h == s["hex"]:
		return {"type": "defend"}
	return {"type": "move", "hex": best_h}

## Tuning, measured with tools/ai_tournament.gd against the frozen baseline.
const SHOOTER_BLOCK := 1.4
const RETALIATION := 1.0
const HOLD := true
const HOLD_RATIO := 0.8
const WAIT := true

## Shooting strength of a side: the value of its stacks that can still shoot (towers included).
static func _shoot_power(L: BattleLogic, side: int) -> float:
	var v := 0.0
	for o in L.alive_stacks(side, true):
		if L.cdata(o)["shots"] > 0 and o["shots"] > 0:
			v += L.cdata(o)["ai_value"] * o["count"]
	return v

## For each hex the stack could stand on (and its own), the damage the enemy's melee stacks could deal it there next
## turn, valued as _value_of_damage (0: out of their reach).
static func _threats(L: BattleLogic, s: Dictionary, reach: Dictionary) -> Dictionary:
	var out := {}
	var spots: Array = reach.keys() + [s["hex"]]
	for e in L.alive_stacks(1 - s["side"]):
		if e.get("machine", false) or e.get("tower", false):
			continue
		var er := L.reachable(e)
		for c in L.cells(e):
			er[c] = 0
		var v := _value_of_damage(L, s, _avg(L.damage_range(e, s, false)))
		for h in spots:
			var hit := false
			for c in L.cells(s, h):
				for n in BattleLogic.neighbors(c):
					if er.has(n):
						hit = true
						break
				if hit:
					break
			if hit:
				out[h] = out.get(h, 0.0) + v
	return out

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
