extends RefCounted
class_name AdvAI
## Computer opponent for the adventure map: builds, recruits, hires, and sends heroes after the
## most valuable target it can safely take (value / distance).

const BUILD_ORDER := ["tavern", "dwelling_1", "dwelling_2", "town_hall", "dwelling_3", "fort", "mage_guild_1",
	"dwelling_4", "marketplace", "citadel", "blacksmith", "dwelling_5", "city_hall", "stables", "dwelling_6", "mage_guild_2",
	"brotherhood", "necromancy_amplifier", "dwelling_7", "castle", "dwelling_1u", "dwelling_2u", "dwelling_3u", "dwelling_4u",
	"capitol", "mage_guild_3", "dwelling_5u", "dwelling_6u", "dwelling_7u", "mage_guild_4"]

var rules: AdvRules
var world: Dictionary

func _init(r: AdvRules) -> void:
	rules = r
	world = r.world

func run_turn(adv, player: Dictionary) -> String:
	if player.get("ai_day", -1) != world["day"]:
		player["ai_day"] = world["day"]
		manage_towns(player)
		adv.view.rebuild_objects()
	var guard := 0
	for hid in player["heroes"].duplicate():
		var steps := 0
		while steps < 8:
			steps += 1
			guard += 1
			if guard > 60:
				return ""
			var hero: Dictionary = world["heroes"].get(hid, {})
			if hero.is_empty() or hero["movement"] < 50:
				break
			var choice := choose(hero)
			if choice.is_empty():
				hero["movement"] = 0
				break
			var before: int = hero["movement"]
			var r: String = await adv.move_hero(hero, choice, false)
			if r == "battle":
				return "battle"
			if not adv.is_inside_tree():
				return "battle"
			if world["heroes"].has(hid) and world["heroes"][hid]["movement"] == before:
				hero["movement"] = 0
				break
			# Hero standing in own town: reinforce.
			if world["heroes"].has(hid):
				for town in world["towns"].values():
					if town["pos"] == hero["pos"] and town["owner"] == hero["owner"]:
						_reinforce(hero, town, player)
						rules.hero_in_town(hero, town)
	return ""

# ---------------------------------------------------------------------------------------------
func manage_towns(player: Dictionary) -> void:
	var week := rules.week_of(world["day"])
	var want_heroes := mini(3, 1 + week / 2)
	# Heroes first: a player without heroes can neither expand nor defend.
	for tid in player["towns"]:
		var town: Dictionary = world["towns"][tid]
		if player["heroes"].size() < want_heroes and TownLogic.has_building(town, "tavern") \
				and player["resources"]["gold"] >= 2500 and rules.hero_at(town["pos"]).is_empty() and world["tavern"].size() > 0:
			hire_hero(player, town)
	var reserve := 2500 if player["heroes"].size() < want_heroes else 0
	var day_of_week: int = (world["day"] - 1) % 7 + 1
	for tid in player["towns"]:
		var town: Dictionary = world["towns"][tid]
		if not town["built_today"]:
			for b in BUILD_ORDER:
				if TownLogic.has_building(town, b):
					continue
				var reason := TownLogic.build_block_reason(town, player, b)
				if reason == "":
					TownLogic.build(town, player, b)
					break
				if reason == "Not enough resources" and not b.begins_with("mage"):
					break  # save up for it
		# recruit into garrison, best first, keeping the hiring reserve and (early in the week)
		# saving for the next building on the list
		var save := reserve
		if day_of_week < 6:
			for b in BUILD_ORDER:
				if not TownLogic.has_building(town, b):
					save += int(GameData.BUILDINGS[b]["cost"].get("gold", 0))
					break
		for tier in range(7, 0, -1):
			var n := TownLogic.max_recruitable(town, player, tier)
			var cid := TownLogic.dwelling_creature(town, tier)
			var price: int = GameData.CREATURES[cid]["cost"].get("gold", 0)
			if price > 0:
				n = mini(n, maxi(0, (player["resources"]["gold"] - save) / price))
			if n > 0:
				TownLogic.recruit(town, player, tier, n, town["garrison"])
		var visitor := rules.hero_at(town["pos"])
		if not visitor.is_empty() and visitor["owner"] == player["index"]:
			_reinforce(visitor, town, player)

func hire_hero(player: Dictionary, town: Dictionary) -> Dictionary:
	var cands := []
	for hid in world["tavern"]:
		if GameData.HEROES[hid]["faction"] == town["faction"]:
			cands.append(hid)
	if cands.is_empty():
		cands = world["tavern"].duplicate()
	if cands.is_empty():
		return {}
	var hid: String = cands[randi() % cands.size()]
	world["tavern"].erase(hid)
	player["resources"]["gold"] -= 2500
	var hero := GameState.make_hero(hid, player["index"])
	hero["pos"] = town["pos"]
	hero["movement"] = 0 if player["is_ai"] == false else hero["movement"]
	world["heroes"][hero["uid"]] = hero
	player["heroes"].append(hero["uid"])
	_reinforce(hero, town, player)
	rules.rebuild()
	return hero

func _reinforce(hero: Dictionary, town: Dictionary, _player: Dictionary) -> void:
	for i in 7:
		var s = town["garrison"][i]
		if s and GameState.add_to_army(hero["army"], s["id"], s["count"]):
			town["garrison"][i] = null

func recruit_from_dwelling(hero: Dictionary, o: Dictionary) -> void:
	var player := rules.player_of(hero)
	var c: Dictionary = GameData.CREATURES[o["creature"]]
	var n: int = o["available"]
	for r in c["cost"]:
		n = mini(n, player["resources"].get(r, 0) / c["cost"][r])
	if n > 0 and GameState.add_to_army(hero["army"], o["creature"], n):
		TownLogic.pay(player, c["cost"], n)
		o["available"] -= n

# ---------------------------------------------------------------------------------------------
func _strength(hero: Dictionary) -> float:
	var s := float(GameState.army_strength(hero["army"]))
	return s * (1.0 + 0.05 * (GameState.hero_stat(hero, "attack") + GameState.hero_stat(hero, "defense")))

func choose(hero: Dictionary) -> Dictionary:
	var me := _strength(hero)
	var player := rules.player_of(hero)
	var best := {}
	var best_score := 0.0
	var hp: Vector2i = hero["pos"]
	var cands := []
	for o in world["objects"].values():
		var d: Vector2i = o["pos"] - hp
		if absi(d.x) > 22 or absi(d.y) > 22:
			continue
		var v := _object_value(hero, player, o, me)
		if v > 0:
			cands.append([o["pos"], v])
	for t in world["towns"].values():
		var v := 0.0
		if t["owner"] != hero["owner"]:
			var def := float(GameState.army_strength(t["garrison"])) * 1.25
			var dh := rules.hero_at(t["pos"])
			if not dh.is_empty():
				def += _strength(dh)
			if me > def * 1.4:
				v = 12000.0
		elif t["pos"] != hp and GameState.army_strength(t["garrison"]) > me * 0.25:
			v = 2500.0 + GameState.army_strength(t["garrison"]) * 0.6
		if v > 0:
			cands.append([t["pos"], v])
	for e in world["heroes"].values():
		if e["owner"] != hero["owner"]:
			var es := _strength(e)
			if me > es * 1.3:
				cands.append([e["pos"], 7000.0 + es * 0.2])
	for c in cands:
		# Reaching a guarded tile means fighting its guards: only go if they are beatable.
		var guarded_ok := true
		for g in rules.guards(c[0]):
			if float(GameData.CREATURES[g["creature"]]["ai_value"] * g["count"]) * 1.6 > me:
				guarded_ok = false
		if not guarded_ok:
			continue
		var plan := rules.plan(hero, c[0])
		if plan["path"].is_empty() or plan["reach"] == 0:
			continue
		var cost: int = plan["costs"][plan["costs"].size() - 1]
		var score: float = c[1] / (1.0 + cost / 150.0)
		if score > best_score:
			best_score = score
			best = plan
	return best

func _object_value(hero: Dictionary, player: Dictionary, o: Dictionary, me: float) -> float:
	match o["type"]:
		"resource":
			return 2.5 * (float(o["amount"]) if o["res"] == "gold" else o["amount"] * (100.0 if o["res"] in ["wood", "ore"] else 250.0))
		"campfire":
			return 2000.0
		"chest":
			return 3000.0
		"artifact":
			return 2500.0
		"mine":
			if o["owner"] == hero["owner"]:
				return 0.0
			return 4000.0 if o["mine"] == "gold_mine" else 2000.0
		"shrine":
			return 700.0 if not o["spell"] in hero["spells"] and GameData.SPELLS[o["spell"]]["level"] <= rules.max_spell_level(hero) else 0.0
		"windmill":
			return 0.0 if hero["owner"] in o.get("visited_week", []) else 1000.0
		"learning_stone":
			return 0.0 if hero["uid"] in o.get("visited", []) else 1500.0
		"dwelling":
			if o["available"] <= 0:
				return 0.0
			var c: Dictionary = GameData.CREATURES[o["creature"]]
			if player["resources"]["gold"] < c["cost"].get("gold", 0) * 2:
				return 0.0
			return 1200.0 + c["ai_value"] * mini(o["available"], 10) * 0.3
		"watchtower":
			return 150.0
		"monster":
			var ms := float(GameData.CREATURES[o["creature"]]["ai_value"] * o["count"])
			if me > ms * 1.6:
				return 600.0 + ms * 0.25
	return 0.0
