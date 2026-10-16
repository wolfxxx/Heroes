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
