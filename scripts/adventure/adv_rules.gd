extends RefCounted
class_name AdvRules
## Adventure map rules (no UI): pathing, visiting objects, day/week cycle, hero growth.
## Used by the player controller (adventure.gd) and the AI (adv_ai.gd).
##
## Visiting functions return an "event" Dictionary the UI turns into a popup:
##   {"title": String, "text": String, "icons": [[Texture2D, caption]], "sfx": String,
##    "battle": setup dict (optional), "town": uid (optional), "choice": {...} (optional)}

const TILE := WorldGen.TILE
const DIRS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var world: Dictionary
var w := 0
var h := 0
var astar := AStarGrid2D.new()
var occ := {}  # Vector2i -> {"kind": "object"|"town"|"hero", "uid": int}

func _init(wd: Dictionary) -> void:
	world = wd
	var s: Vector2i = world["size"]
	w = s.x
	h = s.y
	astar.region = Rect2i(0, 0, w, h)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var terr: PackedByteArray = world["terrain"]
	for y in h:
		for x in w:
			var t: int = terr[y * w + x]
			var cost: int = GameData.TERRAINS[WorldGen.TERRAIN_ORDER[t]]["move_cost"]
			if cost > 0:
				# (the cheapest step, road, weighs 1: the octile heuristic must not overestimate, or A* returns
				# detours off the road)
				astar.set_point_weight_scale(Vector2i(x, y), cost / 50.0)
	rebuild()

func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func terrain_at(p: Vector2i) -> int:
	return world["terrain"][p.y * w + p.x]

func walkable_ground(p: Vector2i) -> bool:
	return inside(p) and world["blocked"][p.y * w + p.x] == 0 and terrain_at(p) != WorldGen.T_WATER

## Rebuild the occupancy index + solid map. Call after any object/hero/town change.
func rebuild() -> void:
	occ.clear()
	for o in world["objects"].values():
		occ[o["pos"]] = {"kind": "object", "uid": o["uid"]}
	for t in world["towns"].values():
		occ[t["pos"]] = {"kind": "town", "uid": t["uid"]}
	for hh in world["heroes"].values():
		occ[hh["pos"]] = {"kind": "hero", "uid": hh["uid"]}
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			astar.set_point_solid(p, not walkable_ground(p) or occ.has(p) or is_guarded(p))

## Recompute occupancy + solidity of one tile (heroes take precedence over gates/objects).
func refresh_tile(p: Vector2i) -> void:
	occ.erase(p)
	for o in world["objects"].values():
		if o["pos"] == p:
			occ[p] = {"kind": "object", "uid": o["uid"]}
	for t in world["towns"].values():
		if t["pos"] == p:
			occ[p] = {"kind": "town", "uid": t["uid"]}
	for hh in world["heroes"].values():
		if hh["pos"] == p:
			occ[p] = {"kind": "hero", "uid": hh["uid"]}
	astar.set_point_solid(p, not walkable_ground(p) or occ.has(p) or is_guarded(p))

func at(p: Vector2i) -> Dictionary:
	return occ.get(p, {})

func object_at(p: Vector2i) -> Dictionary:
	var o: Dictionary = occ.get(p, {})
	if o.get("kind", "") == "object":
		return world["objects"][o["uid"]]
	return {}

func hero_at(p: Vector2i) -> Dictionary:
	var o: Dictionary = occ.get(p, {})
	if o.get("kind", "") == "hero":
		return world["heroes"][o["uid"]]
	return {}

func town_at(p: Vector2i) -> Dictionary:
	var o: Dictionary = occ.get(p, {})
	if o.get("kind", "") == "town":
		return world["towns"][o["uid"]]
	return {}

## Town whose footprint or entrance covers p.
func town_covering(p: Vector2i) -> Dictionary:
	for t in world["towns"].values():
		var d: Vector2i = p - t["pos"]
		if d.x >= -2 and d.x <= 2 and d.y >= -2 and d.y <= 0:
			return t
	return {}

func object_covering(p: Vector2i) -> Dictionary:
	var o := object_at(p)
	if not o.is_empty():
		return o
	for d in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var q: Vector2i = p + d
		var oo := object_at(q)
		if not oo.is_empty():
			for f in WorldGen.footprint_for(oo["type"]):
				if q + f == p:
					return oo
	return {}

func guards(p: Vector2i) -> Array:
	var out := []
	for d in DIRS:
		var o := object_at(p + d)
		if not o.is_empty() and o["type"] == "monster":
			out.append(o)
	return out

func is_guarded(p: Vector2i) -> bool:
	if occ.has(p):
		return false
	for d in DIRS:
		var o: Dictionary = occ.get(p + d, {})
		if o.get("kind", "") == "object" and world["objects"][o["uid"]]["type"] == "monster":
			return true
	return false

func step_cost(a: Vector2i, b: Vector2i) -> int:
	var ta: String = WorldGen.TERRAIN_ORDER[terrain_at(a)]
	var tb: String = WorldGen.TERRAIN_ORDER[terrain_at(b)]
	var c: int = GameData.TERRAINS[tb]["move_cost"]
	if ta == "road" and tb == "road":
		c = 50
	elif tb == "road":
		c = 75
	if a.x != b.x and a.y != b.y:
		c = int(c * 1.414)
	return c

## Returns {"path": Array[Vector2i] (includes start), "kind": move|attack|visit|town|meet|none,
##          "target": Dictionary, "costs": Array[int] cumulative, "reach": int (steps affordable today)}
func plan(hero: Dictionary, target: Vector2i) -> Dictionary:
	var start: Vector2i = hero["pos"]
	var res := {"path": [], "kind": "none", "target": {}, "costs": [], "reach": 0}
	if not inside(target) or target == start:
		return res
	var occ_t := at(target)
	var kind := "move"
	var tgt := {}
	var dests := [target]
	match occ_t.get("kind", ""):
		"object":
			tgt = world["objects"][occ_t["uid"]]
			if tgt["type"] == "monster":
				kind = "attack"
				dests = []
				for d in DIRS:
					var q: Vector2i = target + d
					if q == start or (walkable_ground(q) and not occ.has(q)):
						dests.append(q)
			else:
				kind = "visit"
		"town":
			tgt = world["towns"][occ_t["uid"]]
			kind = "town"
		"hero":
			tgt = world["heroes"][occ_t["uid"]]
			kind = "meet" if tgt["owner"] == hero["owner"] else "attack"
			dests = []
			for d in DIRS:
				var q: Vector2i = target + d
				if q == start or (walkable_ground(q) and not occ.has(q)):
					dests.append(q)
		_:
			if not walkable_ground(target):
				var tc := town_covering(target)
				if not tc.is_empty():
					return plan(hero, tc["pos"])
				var oc := object_covering(target)
				if not oc.is_empty():
					return plan(hero, oc["pos"])
				return res
			if is_guarded(target):
				kind = "attack"
				tgt = guards(target)[0]
	var best: Array = []
	var best_cost := 1 << 30
	for dst in dests:
		var p := _path(start, dst)
		if p.is_empty():
			continue
		var c := 0
		for i in range(1, p.size()):
			c += step_cost(p[i - 1], p[i])
		if c < best_cost:
			best_cost = c
			best = p
	if best.is_empty():
		return res
	if kind in ["attack", "meet"] and best[best.size() - 1] != target and occ_t.get("kind", "") != "":
		best.append(target)  # pseudo-step onto the enemy: rendered as the attack marker
	res["path"] = best
	res["kind"] = kind
	res["target"] = tgt
	var costs := [0]
	var acc := 0
	for i in range(1, best.size()):
		if kind in ["attack", "meet"] and i == best.size() - 1 and best[i] == target and occ_t.get("kind", "") != "":
			costs.append(acc)
			continue
		acc += step_cost(best[i - 1], best[i])
		costs.append(acc)
	res["costs"] = costs
	var mp: int = hero["movement"]
	var reach := 0
	for i in range(1, costs.size()):
		if costs[i] <= mp:
			reach = i
	res["reach"] = reach
	return res

func _path(a: Vector2i, b: Vector2i) -> Array:
	if a == b:
		return [a]
	var sa := astar.is_point_solid(a)
	var sb := astar.is_point_solid(b)
	if not walkable_ground(b):
		return []
	astar.set_point_solid(a, false)
	astar.set_point_solid(b, false)
	var p := astar.get_id_path(a, b)
	astar.set_point_solid(a, sa)
	astar.set_point_solid(b, sb)
	return Array(p)

# ---------------------------------------------------------------------------------------------
# Fog
# ---------------------------------------------------------------------------------------------
func reveal(player: Dictionary, center: Vector2i, radius: int) -> void:
	var ex: PackedByteArray = player["explored"]
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if Vector2(x - center.x, y - center.y).length() <= radius + 0.3:
				ex[y * w + x] = 1
	player["explored"] = ex

func reveal_all_for(player: Dictionary) -> void:
	for hid in player["heroes"]:
		var hh: Dictionary = world["heroes"][hid]
		reveal(player, hh["pos"], hero_scout_radius(hh))
	for tid in player["towns"]:
		reveal(player, world["towns"][tid]["pos"] + Vector2i(0, -1), 10)
	for o in world["objects"].values():
		if o["type"] == "mine" and o["owner"] == player["index"]:
			reveal(player, o["pos"], 3)

func hero_scout_radius(hero: Dictionary) -> int:
	return 7 + GameState.hero_stat(hero, "scout")

func is_explored(player: Dictionary, p: Vector2i) -> bool:
	return inside(p) and player["explored"][p.y * w + p.x] == 1

# ---------------------------------------------------------------------------------------------
# Hero helpers
# ---------------------------------------------------------------------------------------------
func player_of(hero: Dictionary) -> Dictionary:
	return world["players"][hero["owner"]]

func gain_xp(hero: Dictionary, xp: int) -> int:
	## Returns number of levels gained. Pending level-ups are stored in hero["pending_levels"].
	hero["xp"] = hero["xp"] + xp
	var gained := 0
	while hero["level"] < GameData.XP_LEVELS.size() and hero["xp"] >= GameData.XP_LEVELS[hero["level"]]:
		hero["level"] += 1
		gained += 1
		hero["pending_levels"] = int(hero.get("pending_levels", 0)) + 1
	return gained

## Rolls a level-up: returns {"stat": String, "options": Array[skill_id]} (does not apply).
func roll_level_up(hero: Dictionary, rng := RandomNumberGenerator.new()) -> Dictionary:
	rng.randomize()
	var might: bool = hero["class"] in ["Knight", "Death Knight"]
	var weights := {"attack": 35, "defense": 35, "power": 15, "knowledge": 15} if might else {"attack": 15, "defense": 15, "power": 35, "knowledge": 35}
	var roll := rng.randi_range(1, 100)
	var stat := "attack"
	for k in weights:
		roll -= weights[k]
		if roll <= 0:
			stat = k
			break
	var skills: Dictionary = hero["skills"]
	var upgradable := []
	for s in skills:
		if skills[s] < 3:
			upgradable.append(s)
	var fresh := []
	if skills.size() < 8:
		for s in GameData.SKILLS:
			if not skills.has(s):
				fresh.append(s)
	upgradable.shuffle()
	fresh.shuffle()
	var opts := []
	if upgradable.size() > 0:
		opts.append(upgradable[0])
	if fresh.size() > 0:
		opts.append(fresh[0])
	if opts.size() < 2:
		if upgradable.size() > 1:
			opts.append(upgradable[1])
		elif fresh.size() > 1:
			opts.append(fresh[1])
	return {"stat": stat, "options": opts}

func apply_level_up(hero: Dictionary, roll: Dictionary, skill: String) -> void:
	hero[roll["stat"]] = hero[roll["stat"]] + 1
	if skill != "":
		hero["skills"][skill] = int(hero["skills"].get(skill, 0)) + 1
	hero["pending_levels"] = maxi(0, int(hero.get("pending_levels", 0)) - 1)
	hero["max_movement"] = GameState.hero_max_movement(hero)

func max_spell_level(hero: Dictionary) -> int:
	return 2 + int(hero["skills"].get("wisdom", 0))

func learn_spell(hero: Dictionary, spell: String) -> bool:
	if spell in hero["spells"]:
		return false
	if GameData.SPELLS[spell]["level"] > max_spell_level(hero):
		return false
	hero["spells"].append(spell)
	return true

## Visiting own town: learn mage guild spells, refill mana.
func hero_in_town(hero: Dictionary, town: Dictionary) -> Array:
	var learned := []
	for s in town["mage_spells"]:
		if learn_spell(hero, s):
			learned.append(s)
	if TownLogic.mage_guild_level(town) > 0:
		hero["mana"] = maxi(hero["mana"], GameState.max_mana(hero))
	return learned

# ---------------------------------------------------------------------------------------------
# Visiting
# ---------------------------------------------------------------------------------------------
func visit(hero: Dictionary, o: Dictionary) -> Dictionary:
	var player := player_of(hero)
	var ev := {"title": "", "text": "", "icons": [], "sfx": ""}
	match o["type"]:
		"resource":
			var r: String = o["res"]
			player["resources"][r] += o["amount"]
			ev["title"] = GameData.RESOURCE_NAMES[r]
			ev["text"] = "You found %d %s." % [o["amount"], GameData.RESOURCE_NAMES[r].to_lower()]
			ev["icons"] = [[Assets.res_icon(r), "+%d" % o["amount"]]]
			ev["sfx"] = "gold_pickup" if r == "gold" else "resource_pickup"
			ev["float"] = "+%d %s" % [o["amount"], GameData.RESOURCE_NAMES[r]]
			_remove_object(o)
		"campfire":
			player["resources"]["gold"] += o["gold"]
			player["resources"][o["res"]] += o["amount"]
			ev["title"] = "Campfire"
			ev["text"] = "Among the embers of an abandoned camp you find supplies."
			ev["icons"] = [[Assets.res_icon("gold"), "+%d" % o["gold"]], [Assets.res_icon(o["res"]), "+%d" % o["amount"]]]
			ev["sfx"] = "resource_pickup"
			_remove_object(o)
		"chest":
			ev["title"] = "Treasure Chest"
			ev["text"] = "After scouring the area you discover an old chest. Keep the gold, or distribute it to the peasants for experience?"
			ev["choice"] = {"kind": "chest", "gold": o["gold"], "xp": o["gold"] - 500}
			ev["sfx"] = "chest_open"
			_remove_object(o)
		"artifact":
			var a: String = o["artifact"]
			var made := GameState.give_artifact(hero, a)
			ev["title"] = GameData.ARTIFACTS[a]["name"]
			ev["text"] = "You found the %s! (%s)" % [GameData.ARTIFACTS[a]["name"], GameData.ARTIFACTS[a]["desc"]]
			if made != "":  # (its last part: the set merges, as the classic's combination artifacts)
				ev["text"] += "\n\nIts parts join into the %s!" % made
			ev["icons"] = [[Assets.artifact_icon(a), GameData.ARTIFACTS[a]["desc"]]]
			ev["sfx"] = "chest_open"
			_remove_object(o)
		"mine":
			var m: Dictionary = GameData.MINES[o["mine"]]
			if o["owner"] != hero["owner"]:
				o["owner"] = hero["owner"]
				ev["title"] = m["name"]
				ev["text"] = "You claim the %s. It will produce %d %s per day." % [m["name"], m["amount"], GameData.RESOURCE_NAMES[m["resource"]].to_lower()]
				ev["icons"] = [[Assets.res_icon(m["resource"]), "+%d / day" % m["amount"]]]
				ev["sfx"] = "mine_capture"
				ev["refresh"] = o["uid"]
				reveal(player, o["pos"], 3)
		"shrine":
			var s: String = o["spell"]
			var sp: Dictionary = GameData.SPELLS[s]
			ev["title"] = "Shrine of Magic"
			ev["icons"] = [[Assets.spell_icon(s), sp["name"]]]
			if s in hero["spells"]:
				ev["text"] = "The shrine teaches %s, which you already know." % sp["name"]
			elif learn_spell(hero, s):
				ev["text"] = "A voice whispers the secrets of %s into your mind." % sp["name"]
				ev["sfx"] = "spell_cast"
			else:
				ev["text"] = "You lack the wisdom to understand %s (level %d)." % [sp["name"], sp["level"]]
		"windmill":
			var visited: Array = o.get("visited_week", [])
			ev["title"] = "Windmill"
			if hero["owner"] in visited:
				ev["text"] = "The miller has nothing more for you this week."
			else:
				visited.append(hero["owner"])
				o["visited_week"] = visited
				var r: String = ["mercury", "sulfur", "crystal", "gems"][randi() % 4]
				var amt := randi_range(3, 5)
				player["resources"][r] += amt
				ev["text"] = "The miller shares this week's harvest."
				ev["icons"] = [[Assets.res_icon(r), "+%d" % amt]]
				ev["sfx"] = "resource_pickup"
		"watchtower":
			reveal(player, o["pos"], 14)
			var vb: Array = o.get("visited_by", [])
			if not hero["owner"] in vb:
				vb.append(hero["owner"])
				o["visited_by"] = vb
			ev["title"] = "Watchtower"
			ev["text"] = "From the top of the tower you survey the surrounding lands."
			ev["sfx"] = "flag_capture"
			ev["fog"] = true
		"learning_stone":
			var v: Array = o.get("visited", [])
			ev["title"] = "Learning Stone"
			if hero["uid"] in v:
				ev["text"] = "You have already studied the runes on this stone."
			else:
				v.append(hero["uid"])
				o["visited"] = v
				ev["text"] = "You study the ancient runes. +1000 experience."
				ev["xp"] = 1000
				ev["sfx"] = "level_up"
		"dwelling":
			ev["title"] = GameData.CREATURES[o["creature"]]["plural"]
			ev["dwelling"] = o["uid"]
			if o.get("owner", -1) != hero["owner"]:
				o["owner"] = hero["owner"]
				ev["refresh"] = o["uid"]
	if ev.has("xp"):
		ev["levels"] = gain_xp(hero, ev["xp"])
	return ev

func _remove_object(o: Dictionary) -> void:
	world["objects"].erase(o["uid"])
	rebuild()
	world["_removed"] = world.get("_removed", []) + [o["uid"]]

func resolve_chest(hero: Dictionary, choice: String, gold: int, xp: int) -> int:
	if choice == "gold":
		player_of(hero)["resources"]["gold"] += gold
		return 0
	return gain_xp(hero, xp)

## Monster stack -> battle army (split into several stacks like HoMM).
func monster_army(o: Dictionary) -> Array:
	var army: Array = [null, null, null, null, null, null, null]
	var total: int = o["count"]
	var stacks := clampi(total / 4 + 1, 1, 5)
	if total <= 1:
		stacks = 1
	var per := total / stacks
	var rem := total - per * stacks
	var slots := [3, 1, 5, 0, 6, 2, 4]
	for i in stacks:
		var c := per + (1 if i < rem else 0)
		if c > 0:
			army[slots[i]] = {"id": o["creature"], "count": c}
	return army

func battle_vs_monster(hero: Dictionary, o: Dictionary) -> Dictionary:
	return {
		"attacker_army": hero["army"], "defender_army": monster_army(o),
		"attacker_hero": hero, "defender_hero": null,
		"terrain": _battle_terrain(o["pos"]), "attacker_player": hero["owner"], "defender_player": -1,
		"attacker_ai": player_of(hero)["is_ai"], "defender_ai": true,
		"context": {"type": "monster", "hero": hero["uid"], "object": o["uid"]},
	}

func battle_vs_hero(att: Dictionary, def: Dictionary) -> Dictionary:
	return {
		"attacker_army": att["army"], "defender_army": def["army"],
		"attacker_hero": att, "defender_hero": def,
		"terrain": _battle_terrain(def["pos"]), "attacker_player": att["owner"], "defender_player": def["owner"],
		"attacker_ai": player_of(att)["is_ai"], "defender_ai": player_of(def)["is_ai"],
		"context": {"type": "hero", "hero": att["uid"], "defender": def["uid"]},
	}

func battle_vs_town(att: Dictionary, town: Dictionary) -> Dictionary:
	var def_hero := town_defender(town, att)
	var def_army: Array = town["garrison"]
	if not def_hero.is_empty():
		# Visiting hero defends; garrison joins empty slots.
		def_army = def_hero["army"]
		for i in 7:
			if def_army[i] == null and town["garrison"][i] != null:
				def_army[i] = town["garrison"][i]
				town["garrison"][i] = null
	var def_ai := true
	if town["owner"] >= 0:
		def_ai = world["players"][town["owner"]]["is_ai"]
	return {
		"attacker_army": att["army"], "defender_army": def_army,
		"attacker_hero": att, "defender_hero": def_hero if not def_hero.is_empty() else null,
		"terrain": _battle_terrain(town["pos"]), "attacker_player": att["owner"], "defender_player": town["owner"],
		"attacker_ai": player_of(att)["is_ai"], "defender_ai": def_ai,
		"context": {"type": "town", "hero": att["uid"], "town": town["uid"], "defender": def_hero.get("uid", -1)},
		"siege": TownLogic.siege_level(town),
		"siege_faction": town["faction"],
		"siege_morale": 2 if TownLogic.has_building(town, "brotherhood") else 0,
	}

## Hero defending a town: one of the owner's heroes standing in the gate (never the attacker itself,
## who is standing on the gate tile while assaulting it).
func town_defender(town: Dictionary, attacker: Dictionary) -> Dictionary:
	for hh in world["heroes"].values():
		if hh["pos"] == town["pos"] and hh["uid"] != attacker.get("uid", -1) and hh["owner"] == town["owner"]:
			return hh
	return {}

func _battle_terrain(p: Vector2i) -> String:
	var t: String = WorldGen.TERRAIN_ORDER[terrain_at(p)]
	if t in ["road", "water"]:
		for d in DIRS:
			var q: Vector2i = p + d
			if inside(q):
				var tt: String = WorldGen.TERRAIN_ORDER[terrain_at(q)]
				if not tt in ["road", "water"]:
					return tt
		return "grass"
	return t

## Instant battle resolution for battles no human takes part in.
func quick_resolve(setup: Dictionary) -> Dictionary:
	var a_army: Array = setup["attacker_army"]
	var d_army: Array = setup["defender_army"]
	var ah = setup.get("attacker_hero")
	var dh = setup.get("defender_hero")
	var sa := float(GameState.army_strength(a_army))
	var sd := float(GameState.army_strength(d_army))
	if ah:
		sa *= 1.0 + 0.05 * (GameState.hero_stat(ah, "attack") + GameState.hero_stat(ah, "defense")) + 0.02 * GameState.hero_stat(ah, "power") * ah["spells"].size()
	if dh:
		sd *= 1.0 + 0.05 * (GameState.hero_stat(dh, "attack") + GameState.hero_stat(dh, "defense")) + 0.02 * GameState.hero_stat(dh, "power") * dh["spells"].size()
	if setup.get("context", {}).get("type", "") == "town":
		sd *= 1.25
	sa *= randf_range(0.9, 1.1)
	var attacker_wins := sa > sd
	var win_army := a_army if attacker_wins else d_army
	var lose_army := d_army if attacker_wins else a_army
	var ratio := (minf(sa, sd) / maxf(maxf(sa, sd), 1.0))
	var loss := clampf(ratio * ratio * 0.85, 0.0, 0.95)
	var killed_hp := 0
	var out_win: Array = []
	for s in win_army:
		if s:
			var lost := int(ceil(s["count"] * loss)) if loss > 0.02 else 0
			var left: int = maxi(1 if s["count"] > 0 and loss < 0.9 else 0, s["count"] - lost)
			out_win.append({"id": s["id"], "count": left} if left > 0 else null)
		else:
			out_win.append(null)
	for s in lose_army:
		if s:
			killed_hp += s["count"] * GameData.CREATURES[s["id"]]["hp"]
	var empty: Array = [null, null, null, null, null, null, null]
	return {
		"winner": "attacker" if attacker_wins else "defender",
		"attacker_army": out_win if attacker_wins else empty,
		"defender_army": empty if attacker_wins else out_win,
		"xp": killed_hp, "retreated": false, "context": setup.get("context", {}),
	}

## Applies a finished battle to the world. Returns an event dict for the UI.
func apply_battle(result: Dictionary) -> Dictionary:
	var ctx: Dictionary = result.get("context", {})
	var ev := {"title": "", "text": "", "levels": 0, "hero": -1}
	var att: Dictionary = world["heroes"].get(ctx.get("hero", -1), {})
	var att_won: bool = result["winner"] == "attacker"
	var fled: int = result.get("fled", -1)  # (the side whose hero retreated or surrendered: it keeps what it carries)
	if not att.is_empty():
		_set_army(att["army"], result["attacker_army"])
	if result.get("surrendered", false):
		var payer = att if fled == 0 else world["heroes"].get(ctx.get("defender", -1), {})
		if not payer.is_empty():
			var res: Dictionary = world["players"][payer["owner"]]["resources"]
			res["gold"] = maxi(0, res["gold"] - int(result.get("surrender_gold", 0)))
	match ctx.get("type", ""):
		"monster":
			var o: Dictionary = world["objects"].get(ctx["object"], {})
			if att_won:
				if not o.is_empty():
					world["objects"].erase(o["uid"])
			elif not o.is_empty():
				var left := 0
				for s in result["defender_army"]:
					if s:
						left += s["count"]
				o["count"] = maxi(1, left)
		"hero":
			var def: Dictionary = world["heroes"].get(ctx["defender"], {})
			if not def.is_empty():
				_set_army(def["army"], result["defender_army"])
				if att_won:
					if fled != 1:
						_loot(att, def)
					_kill_hero(def, fled == 1)
		"town":
			var town: Dictionary = world["towns"].get(ctx["town"], {})
			var def: Dictionary = world["heroes"].get(ctx.get("defender", -1), {})
			if not def.is_empty():
				_set_army(def["army"], result["defender_army"])
			elif not town.is_empty():
				_set_army(town["garrison"], result["defender_army"])
			if att_won and not town.is_empty():
				if not def.is_empty():
					if fled != 1:
						_loot(att, def)
					_kill_hero(def, fled == 1)
				for i in 7:
					town["garrison"][i] = null
				capture_town(town, att["owner"])
	if att_won and not att.is_empty():
		ev["hero"] = att["uid"]
		ev["levels"] = gain_xp(att, int(result.get("xp", 0)))
		if result.has("raised") and result["raised"] > 0:
			GameState.add_to_army(att["army"], result.get("raised_id", "skeleton"), result["raised"])
	elif not att.is_empty():
		var winner_uid: int = ctx.get("defender", -1)
		var dh: Dictionary = world["heroes"].get(winner_uid, {})
		if not dh.is_empty():
			ev["hero"] = dh["uid"]
			ev["levels"] = gain_xp(dh, int(result.get("xp", 0)))
			if fled != 0:
				_loot(dh, att)
		_kill_hero(att, fled == 0)
	rebuild()
	check_eliminations()
	return ev

## The winner of a battle between heroes takes the loser's artifacts, worn and carried (as the classic game).
func _loot(winner: Dictionary, loser: Dictionary) -> void:
	if winner.is_empty():
		return
	for a in loser.get("artifacts", []) + loser.get("backpack", []):
		GameState.give_artifact(winner, a)
	loser["artifacts"] = []
	loser["backpack"] = []

func _set_army(dst: Array, src: Array) -> void:
	for i in 7:
		var s = src[i] if i < src.size() else null
		dst[i] = s if s and s["count"] > 0 else null

## A hero leaves the map: slain, dismissed, or (`kept`) fled or surrendered, when they wait in the taverns as they
## left, with their skills and artifacts (and, surrendered, their army) to be hired again.
func _kill_hero(hero: Dictionary, kept := false) -> void:
	if not world["heroes"].has(hero["uid"]):
		return
	if kept:
		if not world.has("tavern_keep"):
			world["tavern_keep"] = {}
		hero.erase("asleep")
		world["tavern_keep"][hero["id"]] = hero
	world["heroes"].erase(hero["uid"])
	var p: Dictionary = world["players"][hero["owner"]]
	p["heroes"].erase(hero["uid"])
	if not hero["id"] in world["tavern"]:
		world["tavern"].append(hero["id"])
	if world.get("selected_hero", -1) == hero["uid"]:
		world["selected_hero"] = p["heroes"][0] if p["heroes"].size() > 0 else -1

func capture_town(town: Dictionary, new_owner: int) -> void:
	if town["owner"] >= 0:
		world["players"][town["owner"]]["towns"].erase(town["uid"])
	town["owner"] = new_owner
	if not town["uid"] in world["players"][new_owner]["towns"]:
		world["players"][new_owner]["towns"].append(town["uid"])

func check_eliminations() -> void:
	for p in world["players"]:
		if p["alive"] and p["heroes"].is_empty() and p["towns"].is_empty():
			p["alive"] = false
			for o in world["objects"].values():
				if o["type"] in ["mine", "dwelling"] and o.get("owner", -1) == p["index"]:
					o["owner"] = -1

# ---------------------------------------------------------------------------------------------
# Day / week
# ---------------------------------------------------------------------------------------------
func week_of(day: int) -> int:
	return (day - 1) / 7 + 1

func date_string() -> String:
	var d: int = world["day"]
	return "Month %d, Week %d, Day %d" % [(d - 1) / 28 + 1, ((d - 1) / 7) % 4 + 1, (d - 1) % 7 + 1]

## Advances the calendar. Returns {"new_week": bool, "week_creature": id}
func new_day() -> Dictionary:
	world["day"] += 1
	var d: int = world["day"]
	var new_week := (d - 1) % 7 == 0
	for p in world["players"]:
		if not p["alive"]:
			continue
		for tid in p["towns"]:
			TownLogic.on_new_day(world["towns"][tid], p)
		for hid in p["heroes"]:
			var hh: Dictionary = world["heroes"][hid]
			hh["max_movement"] = GameState.hero_max_movement(hh)
			hh["movement"] = hh["max_movement"]
			for tid in p["towns"]:  # Stables: +400 movement for a hero starting the day in the town
				var tt: Dictionary = world["towns"][tid]
				if tt["pos"] == hh["pos"] and TownLogic.has_building(tt, "stables"):
					hh["movement"] += 400
			hh["mana"] = mini(GameState.max_mana(hh), hh["mana"] + 1 + GameState.hero_stat(hh, "knowledge") / 4
				+ GameState.hero_stat(hh, "mana_day"))
			p["resources"]["gold"] += GameState.hero_stat(hh, "gold_day")  # (a purse or a signet)
	for o in world["objects"].values():
		if o["type"] == "mine" and o["owner"] >= 0:
			var m: Dictionary = GameData.MINES[o["mine"]]
			world["players"][o["owner"]]["resources"][m["resource"]] += m["amount"]
	var info := {"new_week": new_week, "week_creature": ""}
	if new_week:
		for t in world["towns"].values():
			TownLogic.on_new_week(t)
		for p in world["players"]:  # (a muster banner worn by any of a player's heroes: more first-level recruits)
			var extra := 0
			for hid in p["heroes"]:
				extra += GameState.hero_stat(world["heroes"][hid], "growth1")
			if extra > 0:
				for tid in p["towns"]:
					if TownLogic.has_building(world["towns"][tid], "dwelling_1"):
						world["towns"][tid]["available"][0] += extra
		for o in world["objects"].values():
			match o["type"]:
				"windmill":
					o["visited_week"] = []
				"dwelling":
					o["available"] = o["available"] + GameData.CREATURES[o["creature"]]["growth"]
				"monster":
					o["count"] = int(ceil(o["count"] * 1.1))
		var ids := GameData.CREATURES.keys().filter(func(c): return GameData.CREATURES[c]["tier"] > 0)
		info["week_creature"] = ids[randi() % ids.size()]
		world["week_creature"] = info["week_creature"]
	return info
