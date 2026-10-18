extends RefCounted
class_name TownLogic
## Pure rules for towns (no UI). Used by the town screen AND the adventure map (new day/week, AI).
##
## town dict: {"uid": int, "name": String, "faction": String, "owner": int (-1 neutral),
##             "pos": Vector2i (entrance tile on the adventure map),
##             "buildings": Array[String], "available": Array[int] (7 entries, recruitable count per tier),
##             "garrison": army (7 slots), "built_today": bool, "mage_spells": Array[String]}
## player dict: {"index": int, "name": String, "color": Color, "is_ai": bool, "faction": String,
##               "resources": {res: int}, "heroes": Array[int uid], "towns": Array[int uid], "alive": bool}

const TOWN_NAMES := {
	"haven": ["Stormhold", "Brightwater", "Valoria", "Kingsbridge", "Aurelia"],
	"necropolis": ["Gravenmoor", "Ashenveil", "Mortholme", "Duskhaven", "Blackfen"],
}

static func make_town(faction: String, owner: int, pos: Vector2i, name := "", developed := true) -> Dictionary:
	if name == "":
		name = TOWN_NAMES[faction].pick_random()
	var b: Array = ["village_hall"]
	if developed:
		b = ["town_hall", "fort", "tavern", "dwelling_1", "dwelling_2"]
	var t := {"uid": GameState.next_uid(), "name": name, "faction": faction, "owner": owner, "pos": pos,
		"buildings": b, "available": [0, 0, 0, 0, 0, 0, 0],
		"garrison": [null, null, null, null, null, null, null], "built_today": false, "mage_spells": []}
	weekly_growth(t)
	return t

static func has_building(town: Dictionary, id: String) -> bool:
	if id in town["buildings"]:
		return true
	# Upgraded versions satisfy requirements of their base building.
	for b in town["buildings"]:
		var cur: String = b
		while GameData.BUILDINGS[cur].has("replaces"):
			cur = GameData.BUILDINGS[cur]["replaces"]
			if cur == id:
				return true
	return false

static func can_afford(player: Dictionary, cost: Dictionary, times := 1) -> bool:
	for r in cost:
		if player["resources"].get(r, 0) < cost[r] * times:
			return false
	return true

static func pay(player: Dictionary, cost: Dictionary, times := 1) -> void:
	for r in cost:
		player["resources"][r] = player["resources"].get(r, 0) - cost[r] * times

## Returns "" if buildable, otherwise a human readable reason.
static func build_block_reason(town: Dictionary, player: Dictionary, id: String) -> String:
	var b: Dictionary = GameData.BUILDINGS[id]
	if has_building(town, id):
		return "Already built"
	if town["built_today"]:
		return "Already built today"
	for req in b["requires"]:
		if not has_building(town, req):
			return "Requires " + GameData.building_name(town["faction"], req)
	if not can_afford(player, b["cost"]):
		return "Not enough resources"
	return ""

static func buildable_list(town: Dictionary) -> Array:
	## All buildings not yet built whose base (if upgrade) is built or which aren't upgrades.
	var out := []
	for id in GameData.BUILDINGS:
		if has_building(town, id):
			continue
		var b: Dictionary = GameData.BUILDINGS[id]
		if b.has("replaces") and not has_building(town, b["replaces"]):
			continue
		out.append(id)
	return out

static func build(town: Dictionary, player: Dictionary, id: String) -> bool:
	if build_block_reason(town, player, id) != "":
		return false
	var b: Dictionary = GameData.BUILDINGS[id]
	pay(player, b["cost"])
	if b.has("replaces"):
		town["buildings"].erase(b["replaces"])
	town["buildings"].append(id)
	town["built_today"] = true
	if b.has("dwelling_tier") and not b.has("replaces"):  # (an upgrade keeps the base dwelling's stock)
		var tier: int = b["dwelling_tier"]
		var cid := GameData.faction_creature(town["faction"], tier)
		town["available"][tier - 1] += GameData.CREATURES[cid]["growth"]
	if id.begins_with("mage_guild"):
		learn_guild_spells(town)
	return true

static func learn_guild_spells(town: Dictionary) -> void:
	var lvl := mage_guild_level(town)
	var rng := RandomNumberGenerator.new()
	rng.seed = town["uid"] * 7919
	for l in range(1, lvl + 1):
		var pool := []
		for s in GameData.SPELLS:
			if GameData.SPELLS[s]["level"] == l and not s in town["mage_spells"]:
				pool.append(s)
		var want := 4 if l == 1 else 3
		var have := 0
		for s in town["mage_spells"]:
			if GameData.SPELLS[s]["level"] == l:
				have += 1
		while have < want and pool.size() > 0:
			var i := rng.randi_range(0, pool.size() - 1)
			town["mage_spells"].append(pool[i])
			pool.remove_at(i)
			have += 1

static func mage_guild_level(town: Dictionary) -> int:
	for l in range(4, 0, -1):
		if has_building(town, "mage_guild_%d" % l):
			return l
	return 0

static func daily_income(town: Dictionary) -> int:
	for id in ["city_hall", "town_hall", "village_hall"]:
		if id in town["buildings"]:
			return GameData.BUILDINGS[id]["income"]
	return 0

## The creature a dwelling recruits: the upgraded one once its dwelling is upgraded.
static func dwelling_creature(town: Dictionary, tier: int) -> String:
	if has_building(town, "dwelling_%du" % tier):
		return GameData.FACTIONS[town["faction"]]["upgrades"][tier - 1]
	return GameData.faction_creature(town["faction"], tier)

## What a stack of `cid` can be upgraded to in this town ("" if nothing: no upgraded dwelling, other faction, done).
static func upgrade_target(town: Dictionary, cid: String) -> String:
	var up := GameData.upgrade_of_base(cid)
	if up == "" or GameData.CREATURES[cid]["faction"] != town["faction"]:
		return ""
	return up if has_building(town, "dwelling_%du" % GameData.CREATURES[cid]["tier"]) else ""

## Price of upgrading `count` creatures: the difference in recruiting cost, per resource.
static func upgrade_cost(cid: String, up: String, count: int) -> Dictionary:
	var out := {}
	var a: Dictionary = GameData.CREATURES[cid]["cost"]
	var b: Dictionary = GameData.CREATURES[up]["cost"]
	for r in b:
		var d: int = (b[r] - a.get(r, 0)) * count
		if d > 0:
			out[r] = d
	return out

## Upgrades a whole stack in place; false when it can't be upgraded here or the player can't pay.
static func upgrade_stack(town: Dictionary, player: Dictionary, stack: Dictionary) -> bool:
	var up := upgrade_target(town, stack["id"])
	if up == "":
		return false
	var cost := upgrade_cost(stack["id"], up, stack["count"])
	if not can_afford(player, cost):
		return false
	pay(player, cost)
	stack["id"] = up
	return true

static func weekly_growth(town: Dictionary) -> void:
	var mult := 1.5 if has_building(town, "citadel") else 1.0
	for tier in range(1, 8):
		if has_building(town, "dwelling_%d" % tier):
			var cid := GameData.faction_creature(town["faction"], tier)
			town["available"][tier - 1] += int(GameData.CREATURES[cid]["growth"] * mult)

static func recruit(town: Dictionary, player: Dictionary, tier: int, count: int, army: Array) -> bool:
	var cid := dwelling_creature(town, tier)
	var cost: Dictionary = GameData.CREATURES[cid]["cost"]
	if count <= 0 or count > town["available"][tier - 1] or not can_afford(player, cost, count):
		return false
	if not GameState.add_to_army(army, cid, count):
		return false
	pay(player, cost, count)
	town["available"][tier - 1] -= count
	return true

static func max_recruitable(town: Dictionary, player: Dictionary, tier: int) -> int:
	var cid := dwelling_creature(town, tier)
	var cost: Dictionary = GameData.CREATURES[cid]["cost"]
	var n: int = town["available"][tier - 1]
	for r in cost:
		if cost[r] > 0:
			n = mini(n, player["resources"].get(r, 0) / cost[r])
	return maxi(n, 0)

## Called by the adventure map at the start of each day for the town's owner.
static func on_new_day(town: Dictionary, player: Dictionary) -> void:
	town["built_today"] = false
	player["resources"]["gold"] = player["resources"].get("gold", 0) + daily_income(town)

## Called on day 1 of each week (after on_new_day).
static func on_new_week(town: Dictionary) -> void:
	weekly_growth(town)
