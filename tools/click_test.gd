extends Node
## Map click test: clicks every visible monster / pickup near the selected hero (on its tile and on the sprite
## above it), one after another, and reports clicks that did not show a path.
##   Godot_console.exe --path . res://tools/click_test.tscn

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
		var bad := 0
		var n := 0
		for dy in [0, -1]:  # each object's own tile, then the sprite above it
			for o in adv.world["objects"].values():
				var d: Vector2i = o["pos"] - hero["pos"]
				if absi(d.x) > 9 or absi(d.y) > 7 or not adv.rules.is_explored(adv.human_player(), o["pos"]):
					continue
				var t: Vector2i = o["pos"] + Vector2i(0, dy)
				if adv._pick(t) == adv._plan_target:
					continue  # a second click on the planned target walks there
				adv.center_on(hero["pos"], true)
				await get_tree().process_frame
				var world_p: Vector2 = adv.view.tile_center(t)
				var screen: Vector2 = get_viewport().get_canvas_transform() * world_p
				if screen.x < 0 or screen.y < 0 or screen.x > adv.MAP_VIEW_W or screen.y > adv.MAP_VIEW_H:
					continue
				_click(screen)
				await get_tree().process_frame
				await get_tree().process_frame
				n += 1
				var shown: bool = adv.view.path_points.size() > 0
				var expect: bool = not adv.rules.plan(hero, adv._pick(t))["path"].is_empty()
				if expect and not shown:
					bad += 1
					print("NO PATH: %s at %s clicked %s (picked %s) plan_target=%s busy=%s" % [o["type"], o["pos"], t,
						adv._pick(t), adv._plan_target, adv.busy])
		print("CLICK TEST: %d clicks, %d without a path" % [n, bad])
		# drag: press, move 300 px, release -> the camera pans and no new path is planned
		adv.center_on(hero["pos"], true)
		await get_tree().process_frame
		var before: Vector2 = adv.cam.position
		var plan_before = adv._plan_target
		var xf := get_viewport().get_final_transform()
		_button(Vector2(700, 500), true)
		for k in 10:
			var m := InputEventMouseMotion.new()
			m.position = xf * Vector2(700 - k * 30, 500)
			m.relative = xf.basis_xform(Vector2(-30, 0))
			Input.parse_input_event(m)
			await get_tree().process_frame
		_button(Vector2(400, 500), false)
		await get_tree().process_frame
		print("DRAG TEST: camera moved %.0f px, plan unchanged: %s" % [adv.cam.position.distance_to(before), adv._plan_target == plan_before])
		# a click while the hero walks is planned when it stops
		adv.center_on(hero["pos"], true)
		await get_tree().process_frame
		var far := Vector2i(-1, -1)
		var other := Vector2i(-1, -1)
		for d in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(3, 2), Vector2i(-3, 2), Vector2i(2, -3)]:
			var q: Vector2i = hero["pos"] + d
			if adv.rules.walkable_ground(q) and adv.rules.at(q).is_empty() and not adv.rules.is_guarded(q) 					and adv.rules.plan(hero, q)["reach"] == adv.rules.plan(hero, q)["path"].size() - 1:
				if far == Vector2i(-1, -1):
					far = q
				elif other == Vector2i(-1, -1) and (q - far).length() > 2:
					other = q
		adv._make_plan(far)
		adv._execute_move()
		await get_tree().process_frame
		print("  busy while walking: ", adv.busy)
		_click(get_viewport().get_canvas_transform() * adv.view.tile_center(other))
		var waited := 0
		while adv.busy and waited < 600:
			waited += 1
			await get_tree().process_frame
		await get_tree().process_frame
		print("PENDING TEST: path after the walk ends at %s (clicked %s), shown: %s" % [adv._plan_target, other, adv.view.path_points.size() > 0])
		get_tree().quit()

	func _button(p: Vector2, down: bool) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = get_viewport().get_final_transform() * p
		Input.parse_input_event(e)

	func _click(p: Vector2) -> void:
		var xf := get_viewport().get_final_transform()
		var m := InputEventMouseMotion.new()
		m.position = xf * p
		Input.parse_input_event(m)
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.position = xf * p
			Input.parse_input_event(e)
