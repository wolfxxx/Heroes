extends Node
## Automated screenshot harness (used by dev + judge agents).
## Usage (from project dir):
##   Godot_console.exe --path . -- --shot=shots/battle.png --scene=res://scenes/battle.tscn --delay=2.5 [--setup=demo]
## Multiple shots: --shots=3 --interval=1.5 -> writes shots/battle_0.png, _1, _2
## --setup=<name> is exposed as Shot.setup so scenes can build a demo state when launched directly.
## --click=x,y;x,y simulates left clicks (in 1920x1080 viewport coords) one per interval before each shot.
## --hover=x,y;x,y moves the mouse there (after that shot's click, if any) before each shot; "-" skips one.

var setup := ""
var active := false
var args := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	setup = args.get("setup", "")
	if args.has("shot"):
		active = true
		_run.call_deferred()

func _run() -> void:
	if args.has("scene"):
		get_tree().change_scene_to_file(args["scene"])
	var delay := float(args.get("delay", "2.5"))
	var count := int(args.get("shots", "1"))
	var interval := float(args.get("interval", "1.5"))
	var clicks: PackedStringArray = args.get("click", "").split(";", false)
	var keys: PackedStringArray = args.get("keys", "").split(";", false)
	var hovers: PackedStringArray = args.get("hover", "").split(";", false)
	# the real pointer may rest over the window: park the game's mouse off the screen, so no stray hover (a lit hex,
	# a tooltip) shows in a shot that does not ask for one
	await get_tree().process_frame
	var park := InputEventMouseMotion.new()
	park.position = Vector2(-400, -400)
	Input.parse_input_event(park)
	await get_tree().create_timer(delay).timeout
	var base: String = args["shot"]
	for i in count:
		if i < clicks.size():
			var right := clicks[i].begins_with("r")  # "r960,540": a right click
			var xy := clicks[i].trim_prefix("r").split(",")
			_click(Vector2(float(xy[0]), float(xy[1])), MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT)
			await get_tree().create_timer(0.6).timeout
		if i < hovers.size() and hovers[i] != "-":
			var hp := hovers[i].split(",")
			var m := InputEventMouseMotion.new()
			m.position = get_viewport().get_final_transform() * Vector2(float(hp[0]), float(hp[1]))
			Input.parse_input_event(m)
			await get_tree().create_timer(0.8).timeout
		if i < keys.size() and keys[i] != "":
			_key(keys[i])
			await get_tree().create_timer(0.6).timeout
		# (the window was now and then grown to nearly the whole screen mid-run, from outside the game: back to the
		# shot size before each capture, so every shot is 1600x900)
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if DisplayServer.window_get_size() != Vector2i(1600, 900):
			print("SHOT window was ", DisplayServer.window_get_size(), ": resized")
			DisplayServer.window_set_size(Vector2i(1600, 900))
			for f in 3:
				await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var out := base if count == 1 else base.get_basename() + "_%d.png" % i
		var abs_path := out if out.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		img.save_png(abs_path)
		print("SHOT saved ", abs_path)
		if i < count - 1:
			await get_tree().create_timer(interval).timeout
	get_tree().quit()

func _click(pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var vp := get_viewport()
	# Convert from 1920x1080 design coordinates into the window's coordinates.
	var xf := vp.get_final_transform()
	var p: Vector2 = xf * pos
	var m := InputEventMouseMotion.new()
	m.position = p
	Input.parse_input_event(m)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = p
		Input.parse_input_event(e)

func _key(name: String) -> void:
	var code := OS.find_keycode_from_string(name)
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
