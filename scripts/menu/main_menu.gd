extends Control
## Main menu + new game setup. Built entirely in code.

const MAP_SIZES := [["Small", 36], ["Medium", 48], ["Large", 64]]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

var _menu_box: VBoxContainer
var _setup_panel: PanelContainer
var _settings := {}
var _hero_row: HBoxContainer
var _hero_desc: Label
var _faction_buttons := {}
var _option_buttons := {}
var _logo: Control
var _menu_band: Control

# Torch flames in the painted backdrop (1920x1080 space): lamp posts, then wall and tower torches.
const TORCHES := [[308, 606, 1.0], [613, 601, 1.0], [1302, 593, 1.0], [471, 473, 0.7], [480, 346, 0.7], [699, 471, 0.7],
	[703, 347, 0.7], [819, 514, 0.8], [1062, 515, 0.8], [1139, 342, 0.7], [1139, 468, 0.7], [1349, 344, 0.7], [1355, 467, 0.7]]
# Title: right-hand column above the menu (main menu), or centred over the new-game panel.
const LOGO_MENU := Rect2(1318, 70, 604, 170)
const LOGO_SETUP := Rect2(510, 12, 900, 240)

func _ready() -> void:
	theme = UI.theme()
	_settings = GameState.new_game_settings.duplicate()
	_build_background()
	_build_menu()
	_build_setup()
	Audio.music("menu")
	if Shot.setup == "new_game":
		_open_setup()

# ---------------------------------------------------------------------------------------------
func _build_background() -> void:
	# the painted scene drifts slowly (with its torch glows), like a camera breathing over the castle
	var scene := Control.new()
	scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene.pivot_offset = Vector2(900, 560)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scene)
	if Assets.has("ui/main_menu_bg.png"):
		var bg := TextureRect.new()
		bg.texture = Assets.tex("ui/main_menu_bg.png")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.add_child(bg)
		var glow := _soft_dot(Color(1, 1, 1))
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		for tch in TORCHES:
			var g := _TorchGlow.new()
			g.texture = glow
			g.material = add
			g.position = Vector2(tch[0], tch[1])
			g.strength = tch[2]
			scene.add_child(g)
	else:
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://scripts/menu/menu_bg.gdshader")
		bg.material = mat
		scene.add_child(bg)
	var drift := scene.create_tween().set_loops()
	drift.tween_property(scene, "scale", Vector2(1.045, 1.045), 26.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(scene, "scale", Vector2.ONE, 26.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fireflies()
	# Vignette for legibility.
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://scripts/ui/vignette.gdshader")
	vig.material = vm
	add_child(vig)

	# darken the right-hand column behind the title and the menu so both read over the painting
	var band := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.02, 0.01, 0.0, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	band.texture = gt
	band.position = Vector2(1180, 0)
	band.size = Vector2(740, 1080)
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	_menu_band = band
	if Assets.has("ui/logo.png"):
		var logo := TextureRect.new()
		logo.texture = Assets.tex("ui/logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_logo = logo
	else:
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UI.label("Heroes of the", 40, UI.GOLD, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		var t2 := UI.label("SHATTERED CROWN", 72, UI.GOLD, true)
		t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t2)
		_logo = v
	_logo.position = LOGO_MENU.position
	_logo.size = LOGO_MENU.size
	_logo.pivot_offset = LOGO_MENU.size * 0.5
	add_child(_logo)
	# intro: the title rises out of a soft glow
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(0.92, 0.92)
	var tw := _logo.create_tween().set_parallel(true)
	tw.tween_property(_logo, "modulate:a", 1.0, 1.4).set_delay(0.2)
	tw.tween_property(_logo, "scale", Vector2.ONE, 1.6).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## A soft round glow texture (white; tinted by modulate).
func _soft_dot(c: Color) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	g.add_point(0.35, Color(c.r, c.g, c.b, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

## Fireflies drifting over the meadow and a few embers rising from the torches' side of the square.
func _fireflies() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var p := CPUParticles2D.new()
	p.texture = _soft_dot(Color.WHITE)
	p.material = add
	p.amount = 46
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.position = Vector2(700, 860)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(760, 170)
	p.direction = Vector2(0.3, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, -4)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.45, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.9, 0.45, 0.9))
	ramp.add_point(0.55, Color(0.85, 1.0, 0.45, 0.3))
	ramp.add_point(0.75, Color(1.0, 0.9, 0.45, 0.85))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.85, 0.4, 0.0))
	p.color_ramp = ramp
	add_child(p)

func _build_menu() -> void:
	var panel := PanelContainer.new()
	# right-hand column, as in the classics: the painted castle stays visible in the centre
	panel.position = Vector2(1400, 330)
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 18)
	panel.add_child(_menu_box)
	var entries := [["New Game", _open_setup], ["Load Game", _load_game], ["Quick Battle", _quick_battle], ["Quit", func(): get_tree().quit()]]
	for e in entries:
		var b := UI.button(e[0], e[1], 34)
		b.custom_minimum_size = Vector2(400, 78)
		if e[0] == "Load Game":
			b.disabled = not GameState.has_save()
		_menu_box.add_child(b)
	_menu_box.set_meta("panel", panel)
	# intro: the buttons slide in one after another
	for i in _menu_box.get_child_count():
		var b: Control = _menu_box.get_child(i)
		b.modulate.a = 0.0
		var tw := b.create_tween().set_parallel(true)
		tw.tween_property(b, "modulate:a", 1.0, 0.45).set_delay(0.7 + i * 0.12)
	var pt := panel.create_tween()
	panel.modulate.a = 0.0
	pt.tween_property(panel, "modulate:a", 1.0, 0.5).set_delay(0.5)

# ---------------------------------------------------------------------------------------------
# New game setup
# ---------------------------------------------------------------------------------------------
func _build_setup() -> void:
	_setup_panel = PanelContainer.new()
	_setup_panel.position = Vector2(310, 262)
	_setup_panel.custom_minimum_size = Vector2(1300, 0)
	_setup_panel.visible = false
	add_child(_setup_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_setup_panel.add_child(v)

	var title := UI.label("New Campaign", 40, UI.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	# Faction choice
	v.add_child(UI.label("Choose your faction", 26, UI.GOLD))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 20)
	v.add_child(frow)
	for f in GameData.FACTIONS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(620, 118)
		_card(b, Assets.tex("map/town_%s.png" % f), 150, GameData.FACTIONS[f]["name"], GameData.FACTIONS[f]["desc"])
		b.pressed.connect(_select_faction.bind(f))
		frow.add_child(b)
		_faction_buttons[f] = b

	# Hero choice
	v.add_child(UI.label("Choose your hero", 26, UI.GOLD))
	_hero_row = HBoxContainer.new()
	_hero_row.add_theme_constant_override("separation", 16)
	v.add_child(_hero_row)
	_hero_desc = UI.label("", 20)
	v.add_child(_hero_desc)

	# Options
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 40)
	v.add_child(orow)
	orow.add_child(_option_group("Map size", MAP_SIZES.map(func(m): return m[0]), "map_size",
		MAP_SIZES.map(func(m): return m[1])))
	orow.add_child(_option_group("Difficulty", DIFFICULTIES, "difficulty", [0, 1, 2]))
	orow.add_child(_option_group("Opponents", ["1", "2", "3"], "opponents", [1, 2, 3]))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 30)
	v.add_child(brow)
	var back := UI.button("Back", _close_setup, 26)
	back.custom_minimum_size = Vector2(220, 60)
	brow.add_child(back)
	var start := UI.button("Begin", _start_game, 30)
	start.custom_minimum_size = Vector2(280, 64)
	brow.add_child(start)

	if not _settings.has("opponents"):
		_settings["opponents"] = 1
	_select_faction(_settings.get("faction", "haven"))
	_refresh_options()

## Selected toggles sit on the bright gold texture: force dark ink text in every pressed/focus state, no focus ring.
func _ink(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	for c in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color(0.16, 0.08, 0.02))
	b.add_theme_color_override("font_outline_color", Color(1, 0.9, 0.6, 0.0))

## A big choice card (faction, hero): picture + gold title + wrapped text. The selected card keeps light text on a
## dark panel and is marked by a bright gold frame and glow (dark ink on the gold toggle texture read poorly).
func _card(b: Button, tex: Texture2D, pic_w: float, title: String, sub: String, title_size := 25) -> void:
	b.focus_mode = Control.FOCUS_NONE
	var on := StyleBoxFlat.new()
	on.bg_color = Color(0.2, 0.13, 0.06, 0.97)
	on.border_color = Color(1.0, 0.82, 0.38)
	on.set_border_width_all(4)
	on.set_corner_radius_all(6)
	on.shadow_color = Color(1.0, 0.75, 0.3, 0.45)
	on.shadow_size = 10
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, on)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.offset_top = 8
	h.offset_bottom = -8
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(pic_w, 0)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := UI.label(title, title_size, UI.GOLD, true)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := UI.label(sub, 19, UI.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)

func _option_group(label: String, names: Array, key: String, values: Array) -> Control:
	var v := VBoxContainer.new()
	v.add_child(UI.label(label, 22, UI.GOLD))
	var h := HBoxContainer.new()
	v.add_child(h)
	var btns := []
	for i in names.size():
		var b := Button.new()
		b.toggle_mode = true
		b.text = names[i]
		b.custom_minimum_size = Vector2(110, 48)
		_ink(b)
		var val = values[i]
		b.pressed.connect(func():
			Audio.sfx("click", -6)
			_settings[key] = val
			_refresh_options())
		b.set_meta("value", val)
		h.add_child(b)
		btns.append(b)
	_option_buttons[key] = btns
	return v

func _refresh_options() -> void:
	for key in _option_buttons:
		for b in _option_buttons[key]:
			b.button_pressed = b.get_meta("value") == _settings.get(key)

func _select_faction(f: String) -> void:
	_settings["faction"] = f
	for k in _faction_buttons:
		_faction_buttons[k].button_pressed = k == f
	for c in _hero_row.get_children():
		c.queue_free()
	var first := ""
	for hid in GameData.HEROES:
		var h: Dictionary = GameData.HEROES[hid]
		if h["faction"] != f:
			continue
		if first == "":
			first = hid
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(300, 132)
		_card(b, Assets.hero_portrait(hid), 96, h["name"], h["class"], 20)
		b.set_meta("hero", hid)
		b.pressed.connect(_select_hero.bind(hid))
		_hero_row.add_child(b)
	if _settings.get("hero", "") == "" or GameData.HEROES.get(_settings["hero"], {}).get("faction", "") != f:
		_settings["hero"] = first
	_select_hero(_settings["hero"])

func _select_hero(hid: String) -> void:
	_settings["hero"] = hid
	for b in _hero_row.get_children():
		if b.has_meta("hero"):
			b.button_pressed = b.get_meta("hero") == hid
	var h: Dictionary = GameData.HEROES[hid]
	var spells: Array = h.get("spells", [])
	_hero_desc.text = "%s — %s.  Specialty: %s.  Attack %d  Defense %d  Power %d  Knowledge %d%s" % [
		h["name"], h["class"], h["specialty"], h["attack"], h["defense"], h["power"], h["knowledge"],
		("   Spells: " + ", ".join(spells.map(func(s): return GameData.SPELLS[s]["name"]))) if spells.size() > 0 else ""]

func _open_setup() -> void:
	_menu_box.get_meta("panel").visible = false
	_setup_panel.visible = true
	_place_logo(LOGO_SETUP)
	_menu_band.visible = false

func _close_setup() -> void:
	_setup_panel.visible = false
	_menu_box.get_meta("panel").visible = true
	_place_logo(LOGO_MENU)
	_menu_band.visible = true

func _place_logo(r: Rect2) -> void:
	_logo.position = r.position
	_logo.size = r.size
	_logo.pivot_offset = r.size * 0.5

## A torch flame's glow: an additive warm halo that flickers.
class _TorchGlow extends Sprite2D:
	var strength := 1.0
	var _seed := randf() * 100.0
	func _process(_d: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0 + _seed
		var f := 0.72 + 0.14 * sin(t * 9.1) + 0.09 * sin(t * 15.7 + 1.3) + 0.05 * sin(t * 23.0)
		modulate = Color(1.0, 0.55, 0.2, 0.7 * f * strength)
		var sc := (0.75 + 0.06 * f) * strength
		scale = Vector2(sc, sc)

func _start_game() -> void:
	_settings["seed"] = randi()
	GameState.new_game_settings = _settings.duplicate()
	GameState.world = {}
	GameState.return_scene = GameState.SCENE_ADVENTURE
	Audio.sfx("battle_start", -4)
	GameState.change_scene(GameState.SCENE_ADVENTURE, 0.6)

func _load_game() -> void:
	if GameState.load_game():
		GameState.change_scene(GameState.SCENE_ADVENTURE, 0.6)

func _quick_battle() -> void:
	var factions := GameData.FACTIONS.keys()
	factions.shuffle()
	GameState.world = {}
	GameState.return_scene = GameState.SCENE_MENU
	var heroes := []
	for f in factions:
		for hid in GameData.HEROES:
			if GameData.HEROES[hid]["faction"] == f:
				heroes.append(hid)
				break
	var a := GameState.make_hero(heroes[0], 0)
	var d := GameState.make_hero(heroes[1], 1)
	for h in [a, d]:
		var c: Array = GameData.FACTIONS[h["faction"]]["creatures"]
		h["army"] = [null, null, null, null, null, null, null]
		h["army"][0] = {"id": c[0], "count": randi_range(25, 40)}
		h["army"][1] = {"id": c[1], "count": randi_range(12, 20)}
		h["army"][2] = {"id": c[2], "count": randi_range(6, 10)}
		h["army"][3] = {"id": c[3], "count": randi_range(4, 7)}
		h["army"][4] = {"id": c[4], "count": randi_range(2, 4)}
		h["army"][5] = {"id": c[5], "count": randi_range(1, 2)}
		h["level"] = 5
		h["attack"] += 2
		h["defense"] += 2
		h["power"] += 2
		h["knowledge"] += 2
		for s in ["magic_arrow", "lightning_bolt", "fireball"]:
			if not s in h["spells"]:
				h["spells"].append(s)
		h["mana"] = GameState.max_mana(h)
	var terrains := ["grass", "dirt", "sand", "snow", "swamp"]
	GameState.start_battle({
		"attacker_army": a["army"], "defender_army": d["army"],
		"attacker_hero": a, "defender_hero": d, "terrain": terrains.pick_random(),
		"attacker_player": 0, "defender_player": 1, "attacker_ai": false, "defender_ai": true,
		"context": {"type": "quick"},
	})
