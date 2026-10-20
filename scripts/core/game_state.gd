extends Node
## Global game state + scene flow.
##
## Data model (plain Dictionaries so they serialise easily):
##   army  : Array of 7 slots, each null or {"id": String, "count": int}
##   hero  : {"uid": int, "id": String, "name": String, "faction": String, "class": String, "owner": int,
##            "attack": int, "defense": int, "power": int, "knowledge": int,
##            "level": int, "xp": int, "mana": int, "movement": int, "max_movement": int,
##            "army": army, "spells": Array[String], "skills": {skill_id: level},
##            "artifacts": Array[String] (worn), "backpack": Array[String], "pos": Vector2i}
##   world : owned by the adventure map (scripts/adventure/*). Stored here so it survives scene changes.
##
## Battle handoff:
##   GameState.start_battle({attacker_army, defender_army, attacker_hero (or null), defender_hero (or null),
##                           terrain, attacker_player, defender_player, context})
##   -> switches to res://scenes/battle.tscn. The battle reads GameState.pending_battle.
##   When finished, battle calls GameState.finish_battle(result) where result =
##     {"winner": "attacker"|"defender", "attacker_army": army, "defender_army": army,
##      "xp": int, "context": <passed through>, "retreated": bool}
##   -> returns to the scene stored in return_scene (adventure map by default), which reads
##      GameState.battle_result in _ready() and applies it, then clears it.

signal battle_finished(result: Dictionary)

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_ADVENTURE := "res://scenes/adventure.tscn"
const SCENE_BATTLE := "res://scenes/battle.tscn"
const SCENE_TOWN := "res://scenes/town.tscn"

var world: Dictionary = {}          # adventure world state (see scripts/adventure/world.gd)
var pending_battle: Dictionary = {}
var battle_result: Dictionary = {}
var pending_town: Dictionary = {}   # {"town_uid": int}
var return_scene := SCENE_ADVENTURE
## adventure map zoom: a wide view of the world by default (as the classic scale), kept between scenes
var map_zoom := 0.8
var battle_speed := 1.0  # battle: how fast it plays (combat options), applied as the engine's time scale
var show_grid := false  # battle: the whole hex grid (G), or only where the active stack can go (the default)
var new_game_settings := {"faction": "haven", "hero": "sir_aldric", "difficulty": 1, "map_size": 48, "seed": 0}
var _uid := 1000

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var transitioning := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)

func next_uid() -> int:
	_uid += 1
	return _uid

func change_scene(path: String, fade := 0.35) -> void:
	while transitioning:
		await get_tree().process_frame
	transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, fade)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade_rect, "color:a", 0.0, fade)
	await tw2.finished
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transitioning = false

func start_battle(setup: Dictionary) -> void:
	pending_battle = setup
	battle_result = {}
	change_scene(SCENE_BATTLE, 0.5)

func finish_battle(result: Dictionary) -> void:
	result["context"] = pending_battle.get("context", {})
	battle_result = result
	pending_battle = {}
	battle_finished.emit(result)
	change_scene(return_scene, 0.5)

func open_town(town_uid: int) -> void:
	pending_town = {"town_uid": town_uid}
	change_scene(SCENE_TOWN)

# ---------------------------------------------------------------------------------------------
# Hero helpers
# ---------------------------------------------------------------------------------------------
func make_hero(hero_id: String, owner: int) -> Dictionary:
	var d: Dictionary = GameData.HEROES[hero_id]
	var faction: String = d["faction"]
	var army: Array = [null, null, null, null, null, null, null]
	var c: Array = GameData.FACTIONS[faction]["creatures"]
	army[0] = {"id": c[0], "count": randi_range(18, 28)}
	army[1] = {"id": c[1], "count": randi_range(6, 10)}
	if randf() < 0.6:
		army[2] = {"id": c[2], "count": randi_range(2, 4)}
	var h := {
		"uid": next_uid(), "id": hero_id, "name": d["name"], "faction": faction, "class": d["class"],
		"owner": owner, "attack": d["attack"], "defense": d["defense"], "power": d["power"],
		"knowledge": d["knowledge"], "level": 1, "xp": 0, "mana": 0, "movement": 1500, "max_movement": 1500,
		"army": army, "spells": d.get("spells", []).duplicate(), "skills": d.get("skills", {}).duplicate(),
		"artifacts": [], "backpack": [], "pos": Vector2i.ZERO,
		# might heroes march with a ballista, magic heroes with a first aid tent (more at a Blacksmith)
		"machines": ["ballista"] if d["class"] in ["Knight", "Death Knight"] else ["first_aid_tent"],
	}
	h["max_movement"] = hero_max_movement(h)
	h["movement"] = h["max_movement"]
	h["mana"] = max_mana(h)
	return h

## A hero hired from a tavern: one who fled or surrendered comes back as they left (see AdvRules._kill_hero), any
## other fresh.
func tavern_hero(hero_id: String, owner: int) -> Dictionary:
	var keep: Dictionary = world.get("tavern_keep", {})
	if not keep.has(hero_id):
		return make_hero(hero_id, owner)
	var h: Dictionary = keep[hero_id]
	keep.erase(hero_id)
	h["uid"] = next_uid()
	h["owner"] = owner
	h["max_movement"] = hero_max_movement(h)
	h["movement"] = h["max_movement"]
	if GameState.army_is_empty(h["army"]):  # (a hero who fled comes with a few troops, as a fresh one)
		h["army"] = make_hero(hero_id, owner)["army"]
	return h

func hero_stat(h: Dictionary, stat: String) -> int:
	var v: int = h.get(stat, 0)
	for a in h.get("artifacts", []):
		v += GameData.ARTIFACTS[a]["bonus"].get(stat, 0)
	return v

## The listed flags of what a hero wears, merged (immune_school, immune_spells, raise).
func hero_flags(h, key: String) -> Array:
	var out := []
	if h == null:
		return out
	for a in h.get("artifacts", []):
		for v in GameData.ARTIFACTS[a].get("flags", {}).get(key, []):
			if not v in out:
				out.append(v)
	return out

## The body slots an artifact fills: its own, or for a combination every slot of its parts.
func artifact_slots(a: String) -> Array:
	var d: Dictionary = GameData.ARTIFACTS[a]
	if d.has("parts"):
		return d["parts"].map(func(p): return GameData.ARTIFACTS[p]["slot"])
	return [d["slot"]]

func _slot_use(h: Dictionary) -> Dictionary:
	var use := {}
	for w in h.get("artifacts", []):
		for sl in artifact_slots(w):
			use[sl] = use.get(sl, 0) + 1
	return use

## Whether the hero has free body slots for the artifact (worn ones count, the backpack does not).
func can_wear(h: Dictionary, a: String) -> bool:
	var use := _slot_use(h)
	var need := {}
	for sl in artifact_slots(a):
		need[sl] = need.get(sl, 0) + 1
	for sl in need:
		if use.get(sl, 0) + need[sl] > int(GameData.ARTIFACT_SLOTS.get(sl, 1)):
			return false
	return true

## A found or won artifact: worn if its slots are free, else into the backpack (as the classic game). Returns the
## name of a combination its arrival completed ("" if none).
func give_artifact(h: Dictionary, a: String) -> String:
	if not h.has("backpack"):
		h["backpack"] = []
	if can_wear(h, a):
		h["artifacts"].append(a)
	else:
		h["backpack"].append(a)
	var merged := merge_combinations(h)
	h["max_movement"] = hero_max_movement(h)
	return merged

## Takes a worn artifact off into the backpack, or puts one from the backpack on (moving to the backpack what wears
## the slots it needs). Movement left today never grows from it. Returns the name of a combination it completed.
func swap_artifact(h: Dictionary, a: String, worn: bool) -> String:
	if not h.has("backpack"):
		h["backpack"] = []
	var merged := ""
	if worn:
		h["artifacts"].erase(a)
		h["backpack"].append(a)
		var cs: String = GameData.ARTIFACTS[a].get("set", "")
		h.get("apart", []).erase(cs)  # (a split set taken apart further merges again once complete)
	else:
		var i: int = h["backpack"].find(a)
		if i < 0:
			return ""
		h["backpack"].remove_at(i)
		for sl in artifact_slots(a):
			if not can_wear(h, a):
				for w in h["artifacts"]:
					if sl in artifact_slots(w):
						h["artifacts"].erase(w)
						h["backpack"].insert(i, w)
						break
		h["artifacts"].append(a)
		merged = merge_combinations(h)
	h["max_movement"] = hero_max_movement(h)
	h["movement"] = mini(h["movement"], h["max_movement"])
	return merged

## As the classic's combination artifacts: when every part of one is worn, the parts merge into it (unless the player
## split it on the hero screen and keeps it apart). Returns the name of the combination made ("" if none).
func merge_combinations(h: Dictionary) -> String:
	var made := ""
	for c in GameData.combinations():
		if c in h.get("apart", []):
			continue
		var parts: Array = GameData.ARTIFACTS[c]["parts"]
		if parts.all(func(p): return p in h["artifacts"]):
			for p in parts:
				h["artifacts"].erase(p)
			h["artifacts"].append(c)
			made = GameData.ARTIFACTS[c]["name"]
	return made

## Splits a worn combination back into its parts (worn in the same slots) and keeps them apart until joined again.
func split_combination(h: Dictionary, c: String) -> void:
	var i: int = h["artifacts"].find(c)
	if i < 0:
		return
	h["artifacts"].remove_at(i)
	for p in GameData.ARTIFACTS[c]["parts"]:
		h["artifacts"].append(p)
	if not h.has("apart"):
		h["apart"] = []
	if not c in h["apart"]:
		h["apart"].append(c)
	h["max_movement"] = hero_max_movement(h)
	h["movement"] = mini(h["movement"], h["max_movement"])

## Joins the worn parts of a combination that was split. Returns its name if it merged.
func join_combination(h: Dictionary, c: String) -> String:
	h.get("apart", []).erase(c)
	var made := merge_combinations(h)
	h["max_movement"] = hero_max_movement(h)
	return made

func max_mana(h: Dictionary) -> int:
	return hero_stat(h, "knowledge") * 10

func artifact_bonus(h: Dictionary, stat: String) -> int:
	var v := 0
	for a in h.get("artifacts", []):
		v += GameData.ARTIFACTS[a]["bonus"].get(stat, 0)
	return v

func hero_max_movement(h: Dictionary) -> int:
	# h["movement"] holds the points LEFT today, so only artifacts add to the maximum.
	var base: int = 1500 + 150 * int(h.get("skills", {}).get("logistics", 0))
	return base + artifact_bonus(h, "movement")

func army_strength(army: Array) -> int:
	var s := 0
	for slot in army:
		if slot:
			s += GameData.CREATURES[slot["id"]]["ai_value"] * slot["count"]
	return s

func army_is_empty(army: Array) -> bool:
	for slot in army:
		if slot and slot["count"] > 0:
			return false
	return true

func add_to_army(army: Array, id: String, count: int) -> bool:
	for slot in army:
		if slot and slot["id"] == id:
			slot["count"] += count
			return true
	for i in army.size():
		if army[i] == null:
			army[i] = {"id": id, "count": count}
			return true
	return false

func xp_level(xp: int) -> int:
	var lvl := 1
	for i in GameData.XP_LEVELS.size():
		if xp >= GameData.XP_LEVELS[i]:
			lvl = i + 1
	return lvl

# ---------------------------------------------------------------------------------------------
# Save / load (FileAccess.store_var keeps Vector2i, Color and packed arrays intact)
# ---------------------------------------------------------------------------------------------
const SAVE_PATH := "user://savegame.dat"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> bool:
	if world.is_empty():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var({"version": 1, "world": world, "uid": _uid})
	return true

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY or not d.has("world"):
		return false
	world = d["world"]
	_uid = int(d.get("uid", 1000))
	pending_battle = {}
	battle_result = {}
	pending_town = {}
	return_scene = SCENE_ADVENTURE
	return true

func current_player() -> Dictionary:
	if world.is_empty():
		return {}
	return world["players"][world["current_player"]]

func human_player_index() -> int:
	if world.is_empty():
		return 0
	for p in world["players"]:
		if not p["is_ai"]:
			return p["index"]
	return 0
