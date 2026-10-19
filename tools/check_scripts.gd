extends Node
## Loads every script under res://scripts so parse/compile errors surface (autoloads available).
##   Godot_console.exe --headless --path . res://tools/check_scripts.tscn
func _ready() -> void:
	var bad := 0
	for p in _scan("res://scripts"):
		var s = load(p)
		if s == null or not s.can_instantiate():
			print("FAILED: ", p)
			bad += 1
	bad += _artifact_rules()
	print("CHECK DONE, failures: ", bad)
	get_tree().quit()

func _scan(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _scan(dir + "/" + sub)
	return out

## Worn artifacts fill their body slots (two rings, five misc), the rest go into the backpack and give nothing;
## putting one on from a full slot swaps the worn one out.
func _artifact_rules() -> int:
	var h := {"artifacts": [], "backpack": [], "attack": 1, "skills": {}, "movement": 1500, "max_movement": 1500}
	var bad := 0
	for a in ["sword_of_valor", "ring_of_vitality", "ring_of_vitality", "ring_of_vitality", "sword_of_valor"]:
		GameState.give_artifact(h, a)
	var ok := [h["artifacts"].size() == 3, h["backpack"].size() == 2, GameState.hero_stat(h, "attack") == 4]
	GameState.swap_artifact(h, "sword_of_valor", true)
	ok.append(GameState.hero_stat(h, "attack") == 1 and h["backpack"].size() == 3)
	GameState.swap_artifact(h, "ring_of_vitality", false)  # (both rings worn: one comes off in its place)
	ok.append(h["artifacts"].count("ring_of_vitality") == 2 and h["backpack"].count("ring_of_vitality") == 1)
	GameState.give_artifact(h, "boots_of_speed")
	ok.append(h["max_movement"] == 2100)
	GameState.swap_artifact(h, "boots_of_speed", true)
	ok.append(h["max_movement"] == 1500 and h["movement"] <= 1500)
	for i in ok.size():
		if not ok[i]:
			print("FAILED: artifact rule ", i)
			bad += 1
	return bad
