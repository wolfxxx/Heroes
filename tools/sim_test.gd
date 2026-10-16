extends Node
## Soak test: every player is AI, game runs fast; prints a summary each new day.
##   Godot_console.exe --path . res://tools/sim_test.tscn -- --seconds=60
## The watcher lives under the tree root so it survives scene changes.

func _ready() -> void:
	var w := Watcher.new()
	get_tree().root.add_child.call_deferred(w)

class Watcher extends Node:
	var _t := 0.0
	var _limit := 60.0
	var _last := -1

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_setup()

	func _setup() -> void:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--seconds="):
				_limit = float(a.split("=")[1])
		var s := GameState.new_game_settings.duplicate()
		s["seed"] = 777
		s["opponents"] = 2
		s["map_size"] = 48
		GameState.world = WorldGen.generate(s)
		for p in GameState.world["players"]:
			p["is_ai"] = true
		Engine.time_scale = 30.0
		GameState.change_scene.call_deferred(GameState.SCENE_ADVENTURE, 0.01)

	func _process(delta: float) -> void:
		_t += delta / Engine.time_scale
		_report()
		if _t > _limit:
			_report()
			print("SIM DONE")
			get_tree().quit()

	func _report() -> void:
		var w := GameState.world
		if w.is_empty():
			print("SIM world empty (game over?)")
			return
		var day: int = w["day"]
		if day == _last:
			return
		_last = day
		var parts := []
		for p in w["players"]:
			var army := 0
			for hid in p["heroes"]:
				army += GameState.army_strength(w["heroes"][hid]["army"])
			var blds := 0
			for tid in p["towns"]:
				blds += w["towns"][tid]["buildings"].size()
			parts.append("P%d alive=%s towns=%d heroes=%d army=%d blds=%d gold=%d" % [p["index"], p["alive"], p["towns"].size(), p["heroes"].size(), army, blds, p["resources"]["gold"]])
		print("SIM day %d objs=%d | %s" % [day, w["objects"].size(), " | ".join(parts)])
