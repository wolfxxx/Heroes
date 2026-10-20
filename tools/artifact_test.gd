extends Node
## Artifact rules test: every artifact's effect, wearing and slots, the three combinations merging, splitting and
## joining, battle effects (health, speed, school damage, immunities, necromancy flag), the daily and weekly ones,
## and the tiered placement on generated maps. Prints one line per failure and a summary.
##   Godot_console.exe --headless --path . res://tools/artifact_test.tscn

var fails := 0
var checks := 0

func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)

func _hero() -> Dictionary:
	var h := GameState.make_hero("sir_aldric", 0)
	h["artifacts"] = []
	h["backpack"] = []
	return h

func _ready() -> void:
	# every artifact: data complete, its bonus counted when worn
	for a in GameData.ARTIFACTS:
		var d: Dictionary = GameData.ARTIFACTS[a]
		_ok(d.has("name") and d.has("slot") and d.has("tier") and d.has("bonus") and d.has("desc"), "data of " + a)
		_ok(GameData.ARTIFACT_TIERS.has(d["tier"]), "tier of " + a)
		_ok(GameData.ARTIFACT_SLOTS.has(d["slot"]), "slot of " + a)
		var h := _hero()
		GameState.give_artifact(h, a)
		_ok(a in h["artifacts"], "%s worn on an empty hero" % a)
		for k in d["bonus"]:
			_ok(GameState.hero_stat(h, k) == int(h.get(k, 0)) + int(d["bonus"][k]), "%s gives %s" % [a, k])
	# slots: two rings, one weapon; the second weapon goes to the backpack
	var h := _hero()
	GameState.give_artifact(h, "sword_of_valor")
	GameState.give_artifact(h, "ogre_hewn_cleaver")
	_ok(h["artifacts"] == ["sword_of_valor"] and h["backpack"] == ["ogre_hewn_cleaver"], "one weapon worn")
	GameState.give_artifact(h, "ring_of_vitality")
	GameState.give_artifact(h, "ring_of_swiftness")
	_ok("ring_of_swiftness" in h["artifacts"], "two rings worn")
	GameState.swap_artifact(h, "ogre_hewn_cleaver", false)
	_ok("ogre_hewn_cleaver" in h["artifacts"] and "sword_of_valor" in h["backpack"], "swap puts the worn one away")
	# combinations: merge on the last part, fill every part's slot, split, join, taking a part off
	for c in GameData.combinations():
		var parts: Array = GameData.ARTIFACTS[c]["parts"]
		h = _hero()
		var made := ""
		for p in parts:
			made = GameState.give_artifact(h, p)
		_ok(made == GameData.ARTIFACTS[c]["name"] and h["artifacts"] == [c], "%s merges when its parts are worn" % c)
		for k in GameData.ARTIFACTS[c]["bonus"]:
			_ok(GameState.hero_stat(h, k) == int(h.get(k, 0)) + int(GameData.ARTIFACTS[c]["bonus"][k]), "%s gives %s" % [c, k])
		GameState.give_artifact(h, parts[0])  # (its slot is taken by the combination: the backpack)
		_ok(h["backpack"] == [parts[0]], "%s fills its parts' slots" % c)
		h["backpack"] = []
		GameState.split_combination(h, c)
		_ok(not c in h["artifacts"] and parts.all(func(p): return p in h["artifacts"]), "%s splits" % c)
		_ok(GameState.merge_combinations(h) == "", "%s stays apart once split" % c)
		_ok(GameState.join_combination(h, c) == GameData.ARTIFACTS[c]["name"] and c in h["artifacts"], "%s joins" % c)
		GameState.split_combination(h, c)
		GameState.swap_artifact(h, parts[1], true)
		_ok(GameState.swap_artifact(h, parts[1], false) == GameData.ARTIFACTS[c]["name"], "%s merges again when re-worn" % c)
		GameState.swap_artifact(h, c, true)
		_ok(h["backpack"] == [c] and h["artifacts"].is_empty(), "%s goes to the backpack whole" % c)
		var h2 := _hero()
		for p in parts:
			GameState.give_artifact(h2, p)
		GameState.give_artifact(h2, "sword_of_valor")
		_ok("sword_of_valor" in h2["backpack"] or not GameData.ARTIFACTS[c]["slot"] == "weapon", "%s keeps its slots" % c)
	# battle
	var att := _hero()
	var def := GameState.make_hero("lord_morthis", 1)
	def["artifacts"] = []
	for a in ["ring_of_vitality", "ring_of_swiftness", "orb_of_embers"]:
		GameState.give_artifact(att, a)
	for p in GameData.ARTIFACTS["dragonheart_arms"]["parts"] + GameData.ARTIFACTS["seraphs_covenant"]["parts"]:
		GameState.give_artifact(def, p)
	_ok("dragonheart_arms" in def["artifacts"] and "seraphs_covenant" in def["artifacts"], "two combinations at once")
	att["spells"] = ["fireball", "curse", "magic_arrow"]
	def["spells"] = ["magic_arrow"]
	att["mana"] = 100
	var L := BattleLogic.new()
	L.setup({"attacker_army": [{"id": "pikeman", "count": 10}, null, null, null, null, null, null],
		"defender_army": [{"id": "skeleton", "count": 10}, null, null, null, null, null, null], "seed": 3,
		"attacker_ai": true, "defender_ai": true, "attacker_hero": att, "defender_hero": def})
	var pk = null
	var sk = null
	for s in L.stacks:
		if s["id"] == "pikeman":
			pk = s
		if s["id"] == "skeleton":
			sk = s
	_ok(L.max_hp(pk) == GameData.CREATURES["pikeman"]["hp"] + 1 and pk["hp_top"] == L.max_hp(pk), "ring of vitality: +1 health")
	_ok(L.total_hp(pk) == 10 * L.max_hp(pk), "total health counts the ring")
	_ok(L.speed(pk) == GameData.CREATURES["pikeman"]["speed"] + 1, "ring of swiftness: +1 speed")
	var base: float = (GameData.SPELLS["fireball"]["damage"][0] + GameData.SPELLS["fireball"]["damage"][1] * L.spell_power(0)) \
		* (1.0 + 0.1 * L.hero_skill(0, "sorcery"))
	_ok(L.spell_damage(0, "fireball") == int(base * 1.5), "orb of embers: fire +50%")
	_ok(L.immune(1, "fireball") and not L.immune(1, "magic_arrow"), "dragonheart arms: fire immunity only")
	_ok(L.immune(1, "curse") and not L.spell_target_ok(0, "curse", sk["hex"]), "seraph's covenant: no curse")
	var ev: Array = L.cast(0, "fireball", sk["hex"])
	_ok(ev[0]["targets"].is_empty() and sk["count"] == 10, "fireball hurts nobody under dragonheart arms")
	var nh := _hero()
	for p in GameData.ARTIFACTS["mantle_of_the_lich_king"]["parts"]:
		GameState.give_artifact(nh, p)
	_ok(GameState.hero_flags(nh, "raise") == ["zombie"] and GameState.hero_stat(nh, "necromancy") == 25, "lich king's mantle")
	# map: scouting, daily gold and mana, weekly growth
	var world := WorldGen.generate({"seed": 7, "map_size": 48, "opponents": 1, "faction": "haven"})
	var R := AdvRules.new(world)
	var p0: Dictionary = world["players"][0]
	var hero: Dictionary = world["heroes"][p0["heroes"][0]]
	hero["artifacts"] = []
	hero["backpack"] = []
	_ok(R.hero_scout_radius(hero) == 7, "scouting radius without artifacts")
	for a in ["seers_spyglass", "wayfarers_cloak", "bottomless_purse", "signet_of_coin", "pendant_of_clarity", "banner_of_the_muster"]:
		GameState.give_artifact(hero, a)
	_ok(R.hero_scout_radius(hero) == 10, "spyglass + cloak: +3 scouting")
	var town: Dictionary = world["towns"][p0["towns"][0]]
	if not TownLogic.has_building(town, "dwelling_1"):
		town["buildings"].append("dwelling_1")
	var gold0: int = p0["resources"]["gold"]
	var income := 0
	for tid in p0["towns"]:
		income += TownLogic.daily_income(world["towns"][tid])
	for o in world["objects"].values():
		if o["type"] == "mine" and o["owner"] == 0:
			if GameData.MINES[o["mine"]]["resource"] == "gold":
				income += GameData.MINES[o["mine"]]["amount"]
	hero["mana"] = 0
	world["day"] = 7  # (the next day starts a week)
	var avail0: int = town["available"][0]
	R.new_day()
	_ok(p0["resources"]["gold"] - gold0 == income + 1000, "purse + signet: +1000 gold a day")
	_ok(hero["mana"] == 1 + GameState.hero_stat(hero, "knowledge") / 4 + 3, "pendant of clarity: +3 mana a day")
	var grown: int = town["available"][0] - avail0
	_ok(grown >= 3 + int(GameData.CREATURES[TownLogic.dwelling_creature(town, 1)]["growth"]), "muster banner: +3 first-level growth")
	# placement: tiers on generated maps, relics never on small maps, one set's parts on medium maps
	var tiers := {}
	var setparts := 0
	for size in [36, 48, 64]:
		var wd := WorldGen.generate({"seed": 11, "map_size": size, "opponents": 1, "faction": "haven"})
		for o in wd["objects"].values():
			if o["type"] == "artifact":
				var d: Dictionary = GameData.ARTIFACTS[o["artifact"]]
				tiers["%d_%s" % [size, d["tier"]]] = tiers.get("%d_%s" % [size, d["tier"]], 0) + 1
				if d.has("set") and size == 48:
					setparts += 1
				_ok(d["tier"] != "combo", "no combination lies on a map")
	_ok(not tiers.has("36_relic"), "no relic on a small map")
	_ok(tiers.get("48_treasure", 0) >= 3 and tiers.get("48_major", 0) >= 1, "tiers on a medium map: %s" % str(tiers))
	_ok(setparts == 3, "one set's three parts on a medium map (%d)" % setparts)
	print("ARTIFACT TEST: %d checks, failures: %d" % [checks, fails])
	get_tree().quit()
