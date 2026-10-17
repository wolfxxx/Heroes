extends Node
## Hover-panel "visited" status test: for each kind of revisitable map site, prints the status line of its hover
## panel before and after the selected hero visits it.
##   Godot_console.exe --path . res://tools/visit_test.tscn

func _ready() -> void:
	var w := Watcher.new()
	get_tree().root.add_child.call_deferred(w)

class Watcher extends Node:
	func _ready() -> void:
		var s := GameState.new_game_settings.duplicate()
		s["seed"] = 12345
		GameState.world = WorldGen.generate(s)
		get_tree().change_scene_to_file("res://scenes/adventure.tscn")
		await get_tree().create_timer(1.5).timeout
		var adv = get_tree().current_scene
		var hero: Dictionary = adv.selected_hero()
		var done := {}
		for o in adv.world["objects"].values():
			var k: String = o["type"]
			if done.has(k) or not k in ["learning_stone", "windmill", "watchtower", "shrine", "dwelling"]:
				continue
			done[k] = true
			adv.human_player()["explored"].fill(1)
			var before := _status(adv._tile_info(o["pos"]))
			adv.rules.visit(hero, o)
			var after := _status(adv._tile_info(o["pos"]))
			print("VISIT %s: before '%s' -> after '%s'" % [k, before, after])
		get_tree().quit()

	## Text of the last label in the panel (the status line).
	func _status(c) -> String:
		if c == null:
			return "<none>"
		var labels: Array = c.find_children("*", "Label", true, false)
		var t: String = labels[labels.size() - 1].text if labels.size() > 0 else ""
		c.free()
		return t
