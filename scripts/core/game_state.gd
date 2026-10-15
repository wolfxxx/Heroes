extends Node
## Global game state + scene flow.
##
## Data model (plain Dictionaries so they serialise easily):
##   army  : Array of 7 slots, each null or {"id": String, "count": int}
##   hero  : {"uid": int, "id": String, "name": String, "faction": String, "class": String, "owner": int,
##            "attack": int, "defense": int, "power": int, "knowledge": int,
##            "level": int, "xp": int, "mana": int, "movement": int, "max_movement": int,
##            "army": army, "spells": Array[String], "skills": {skill_id: level},
##            "artifacts": Array[String], "pos": Vector2i}
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
	if transitioning:
		return
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
		"artifacts": [], "pos": Vector2i.ZERO,
	}
	h["mana"] = max_mana(h)
	return h

func hero_stat(h: Dictionary, stat: String) -> int:
	var v: int = h.get(stat, 0)
	for a in h.get("artifacts", []):
		v += GameData.ARTIFACTS[a]["bonus"].get(stat, 0)
	return v

func max_mana(h: Dictionary) -> int:
	return hero_stat(h, "knowledge") * 10

func hero_max_movement(h: Dictionary) -> int:
	var base: int = 1500 + 150 * int(h.get("skills", {}).get("logistics", 0))
	return base + hero_stat(h, "movement")

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
