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
var _scen_buttons := {}
var _bonus_buttons := {}
var _scen_title: Label
var _scen_desc: Label
var _scen_info: Label
var _vic_row: HBoxContainer
var _loss_row: HBoxContainer
var _random_opts: Control
var _preview: TextureRect   # the chosen scenario's map in miniature (as the classic scenario screen)
var _preview_info: Label    # the land, then the towns and mines (the line under it)
var _preview_info2: Label
var _preview_box: Control
var _preview_cache := {}    # "scenario/faction" -> [texture, text]
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
## The classic New Game screen: the chosen scenario's details and the player's choices on the left, the list of
## scenarios on the right.
func _build_setup() -> void:
	_setup_panel = PanelContainer.new()
	_setup_panel.position = Vector2(80, 246)
	_setup_panel.custom_minimum_size = Vector2(1760, 0)
	_setup_panel.visible = false
	add_child(_setup_panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	_setup_panel.add_child(cols)

	# left: the scenario, its conditions, then faction, hero, starting bonus and difficulty
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 1010
	v.add_theme_constant_override("separation", 7)
	cols.add_child(v)
	_scen_title = UI.label("", 34, UI.GOLD, true)
	v.add_child(_scen_title)
	_scen_desc = UI.label("", 20)
	_scen_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scen_desc.custom_minimum_size = Vector2(1000, 54)
	v.add_child(_scen_desc)
	_scen_info = UI.label("", 19, Color(0.85, 0.8, 0.68))
	v.add_child(_scen_info)
	var cond := HBoxContainer.new()
	v.add_child(cond)
	_vic_row = HBoxContainer.new()
	_loss_row = HBoxContainer.new()
	for r in [_vic_row, _loss_row]:  # (side by side, Defeat just after Victory)
		r.add_theme_constant_override("separation", 10)
		cond.add_child(r)
	_vic_row.custom_minimum_size.x = 340
	cond.add_theme_constant_override("separation", 40)
	v.add_child(_rule())

	v.add_child(UI.label("Choose your faction", 24, UI.GOLD))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 20)
	v.add_child(frow)
	for f in GameData.FACTIONS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(495, 96)
		_card(b, Assets.tex("map/town_%s.png" % f), 120, GameData.FACTIONS[f]["name"], GameData.FACTIONS[f]["desc"], 23, 17)
		b.pressed.connect(_select_faction.bind(f))
		frow.add_child(b)
		_faction_buttons[f] = b

	v.add_child(UI.label("Choose your hero", 24, UI.GOLD))
	_hero_row = HBoxContainer.new()
	_hero_row.add_theme_constant_override("separation", 16)
	v.add_child(_hero_row)
	_hero_desc = UI.label("", 18)
	_hero_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_desc.custom_minimum_size.x = 1000
	v.add_child(_hero_desc)

	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 40)
	v.add_child(orow)
	var bv := VBoxContainer.new()
	bv.add_child(UI.label("Starting bonus", 22, UI.GOLD))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bv.add_child(bh)
	for k in GameData.START_BONUSES:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(196, 84)
		var tex: Texture2D = Assets.res_icon("gold") if k == "gold" else (Assets.tex("icons/artifact_sword_of_valor.png")
			if k == "artifact" else Assets.res_icon("wood"))
		_card(b, tex, 44, GameData.START_BONUSES[k][0], GameData.START_BONUSES[k][1], 20, 16)
		var bk: String = k
		b.pressed.connect(func():
			Audio.sfx("click", -6)
			_settings["bonus"] = bk
			_refresh_options())
		bh.add_child(b)
		_bonus_buttons[k] = b
	orow.add_child(bv)
	orow.add_child(_option_group("Difficulty", DIFFICULTIES, "difficulty", [0, 1, 2], 100))

	# right: the scenarios (size, rivals, victory and loss at a glance), the random map's options, the buttons
	var rv := VBoxContainer.new()
	rv.custom_minimum_size.x = 680
	rv.add_theme_constant_override("separation", 6)
	cols.add_child(rv)
	var t := UI.label("Select a scenario", 30, UI.GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(t)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	for hc in [["Size", 60], ["Name", 354], ["Rivals", 70], ["Win", 66], ["Lose", 66]]:
		var hl := UI.label(hc[0], 17, Color(0.8, 0.72, 0.55))
		hl.custom_minimum_size.x = hc[1]
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if hc[0] != "Name" else HORIZONTAL_ALIGNMENT_LEFT
		head.add_child(hl)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 12)
	hm.add_child(head)
	rv.add_child(hm)
	for sc in GameData.SCENARIOS:
		var b := _scenario_row(sc)
		rv.add_child(b)
		_scen_buttons[sc["id"]] = b
	_random_opts = HBoxContainer.new()
	_random_opts.add_theme_constant_override("separation", 30)
	_random_opts.add_child(_option_group("Map size", MAP_SIZES.map(func(m): return m[0]), "map_size",
		MAP_SIZES.map(func(m): return m[1]), 100))
	_random_opts.add_child(_option_group("Rivals", ["1", "2", "3"], "opponents", [1, 2, 3], 100))
	rv.add_child(_random_opts)
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 12)
	pm.add_theme_constant_override("margin_top", 2)
	var pb := HBoxContainer.new()
	pb.add_theme_constant_override("separation", 18)
	pm.add_child(pb)
	var fr := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color.BLACK
	fs.border_color = UI.GOLD_DARK
	fs.set_border_width_all(3)
	fr.add_theme_stylebox_override("panel", fs)
	pb.add_child(fr)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(172, 172)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fr.add_child(_preview)
	var pv := VBoxContainer.new()  # beside the map: a heading and the two lines together
	pv.add_theme_constant_override("separation", 4)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_child(pv)
	pv.add_child(UI.label("The land", 20, UI.GOLD))
	_preview_info = UI.label("", 20, UI.TEXT)
	_preview_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_info.custom_minimum_size.x = 420
	pv.add_child(_preview_info)
	_preview_info2 = UI.label("", 20, UI.TEXT)
	pv.add_child(_preview_info2)
	_preview_box = pm
	rv.add_child(pm)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(spacer)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 30)
	rv.add_child(brow)
	var back := UI.button("Back", _close_setup, 26)
	back.custom_minimum_size = Vector2(220, 60)
	brow.add_child(back)
	var start := UI.button("Begin", _start_game, 30)
	start.custom_minimum_size = Vector2(280, 64)
	brow.add_child(start)

	if not _settings.has("opponents"):
		_settings["opponents"] = 1
	if not _settings.has("bonus"):
		_settings["bonus"] = "gold"
	_select_faction(_settings.get("faction", "haven"))
	_select_scenario(_settings.get("scenario", GameData.SCENARIOS[0]["id"]))

func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(UI.GOLD_DARK, 0.6)
	r.custom_minimum_size = Vector2(1000, 2)
	return r

## One line of the scenario list: a size badge, the name, the number of rivals, and the victory and loss icons.
func _scenario_row(sc: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(680, 60)
	var on := UI.selected_plate()
	on.set_border_width_all(3)
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, on)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var size_txt: String = "?" if sc.get("random", false) else {36: "S", 48: "M", 64: "L"}.get(int(sc["size"]), "M")
	var badge := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.16, 0.1, 0.05)
	bs.border_color = UI.GOLD_DARK
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(60, 44)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bl := UI.label(size_txt, 24, UI.GOLD, true)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(bl)
	h.add_child(badge)
	var nl := UI.label(sc["name"], 23, UI.TEXT)
	nl.custom_minimum_size.x = 354
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.size_flags_vertical = Control.SIZE_FILL
	h.add_child(nl)
	var rl := UI.label("1-3" if sc.get("random", false) else str(sc["opponents"]), 22, UI.TEXT)
	rl.custom_minimum_size.x = 70
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rl.size_flags_vertical = Control.SIZE_FILL
	h.add_child(rl)
	for ic in [_cond_icon(sc["victory"]), _cond_icon(sc["loss"])]:
		var tr := UI.icon(ic, Vector2(56, 56))  # (cut-out pictures, large enough to read in the list)
		tr.custom_minimum_size = Vector2(66, 56)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tr)
	for c in h.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sid: String = sc["id"]
	b.pressed.connect(func():
		Audio.sfx("click", -6)
		_select_scenario(sid))
	return b

## The picture for a victory or loss condition.
func _cond_icon(c: Dictionary) -> Texture2D:
	match c.get("type", ""):
		"capture": return Assets.tex("ui/cond_capture.png")
		"gold": return Assets.tex("ui/cond_gold.png")
		"hero": return Assets.tex("ui/cond_hero.png")
		"days": return Assets.tex("ui/btn_end_turn.png")
		"standard": return Assets.tex("ui/cond_lose.png")
	return Assets.tex("ui/cond_win.png")

func _select_scenario(id: String) -> void:
	var sc := GameData.scenario(id)
	_settings["scenario"] = sc["id"]
	for k in _scen_buttons:
		_scen_buttons[k].button_pressed = k == sc["id"]
	var random: bool = sc.get("random", false)
	if not random:
		_settings["map_size"] = sc["size"]
		_settings["opponents"] = sc["opponents"]
	_random_opts.visible = random
	_scen_title.text = sc["name"]
	_scen_desc.text = sc["desc"]
	_refresh_options()
	_refresh_preview()

const TERRAIN_WORDS := ["grassland", "dirt", "sand", "snow", "swamp", "water", "road"]

## The chosen scenario's map in miniature, made from its own seed (the map you will play, your faction's town in
## it), with the towns marked and a line on what the land holds. A random map shows only its options.
func _refresh_preview() -> void:
	if _preview_box == null:
		return
	var sc := GameData.scenario(_settings.get("scenario", ""))
	_preview_box.visible = not sc.get("random", false)
	if sc.get("random", false):
		return
	var key := "%s/%s" % [sc["id"], _settings.get("faction", "haven")]
	if not _preview_cache.has(key):
		var s := _settings.duplicate()
		s["seed"] = int(sc["seed"])
		s["map_size"] = sc["size"]
		s["opponents"] = sc["opponents"]
		var wd := WorldGen.generate(s)
		var size: Vector2i = wd["size"]
		var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var terr: PackedByteArray = wd["terrain"]
		var blk: PackedByteArray = wd["blocked"]
		var counts := {}
		for y in size.y:
			for x in size.x:
				var i := y * size.x + x
				var c: Color = AdventureHUD.TERRAIN_COLORS[terr[i]]
				img.set_pixel(x, y, c.darkened(0.35) if blk[i] else c)
				counts[terr[i]] = counts.get(terr[i], 0) + 1
		img.resize(size.x * 4, size.y * 4, Image.INTERPOLATE_NEAREST)  # (crisp map cells, smoothed only by the final scaling)
		var mines := 0
		for o in wd["objects"].values():
			if o["type"] == "mine":
				mines += 1
		for t in wd["towns"].values():  # (towns as dots in their owner's colour, neutral ones pale)
			var col: Color = Color(0.85, 0.83, 0.78) if t["owner"] < 0 else GameData.PLAYER_COLORS[t["owner"]]
			var cp: Vector2 = (Vector2(t["pos"]) + Vector2(0.5, 0.0)) * 4.0
			for yy in range(-7, 8):
				for xx in range(-7, 8):
					var d := Vector2(xx, yy).length()
					var p := Vector2i(cp) + Vector2i(xx, yy)
					if d <= 7.0 and p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
						img.set_pixel(p.x, p.y, col if d <= 5.5 else Color(0.05, 0.03, 0.02))
		var land := []
		for k in counts:
			if k != WorldGen.T_ROAD and k != WorldGen.T_WATER and counts[k] > size.x * size.y * 0.08:
				land.append(k)
		land.sort_custom(func(a, b): return counts[a] > counts[b])
		var words := land.map(func(k): return TERRAIN_WORDS[k])
		var txt := "Mostly %s" % words[0] if words.size() > 0 else "Varied land"
		if words.size() > 1:
			txt += ", with %s" % " and ".join(PackedStringArray(words.slice(1, 3)))
		if counts.get(WorldGen.T_WATER, 0) > size.x * size.y * 0.04:
			txt += "; lakes"
		txt += "."
		var txt2 := "%d towns, %d mines." % [wd["towns"].size(), mines]
		_preview_cache[key] = [ImageTexture.create_from_image(img), txt, txt2]
	_preview.texture = _preview_cache[key][0]
	_preview_info.text = _preview_cache[key][1]
	_preview_info2.text = _preview_cache[key][2]

## The details pane: size, rivals and the two conditions (the hero icon follows the chosen hero).
func _refresh_scenario() -> void:
	if _scen_title == null:
		return
	var sc := GameData.scenario(_settings.get("scenario", ""))
	var size_name := "Medium"
	for m in MAP_SIZES:
		if m[1] == _settings.get("map_size", 48):
			size_name = m[0]
	var n: int = int(_settings.get("opponents", 1))
	var ms: int = int(_settings.get("map_size", 48))
	_scen_info.text = "Map: %s (%d x %d)     Players: you and %d %s" % [size_name, ms, ms, n, "rival" if n == 1 else "rivals"]
	for pair in [[_vic_row, "Victory", sc["victory"], GameData.victory_text(sc["victory"])],
			[_loss_row, "Defeat", sc["loss"], GameData.loss_text(sc["loss"])]]:
		var row: HBoxContainer = pair[0]
		for c in row.get_children():
			row.remove_child(c)
			c.queue_free()
		row.add_child(UI.icon(_cond_icon(pair[2]), Vector2(56, 56)))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.add_child(UI.label(pair[1], 17, Color(0.8, 0.72, 0.55)))
		tv.add_child(UI.label(pair[3], 21, UI.TEXT))
		row.add_child(tv)

## Selected toggles sit on the bright gold texture: force dark ink text in every pressed/focus state, no focus ring.
func _ink(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	UI.plate_toggle(b)

## A big choice card (faction, hero): picture + gold title + wrapped text. The selected card keeps light text on a
## dark panel and is marked by a bright gold frame and glow (dark ink on the gold toggle texture read poorly).
func _card(b: Button, tex: Texture2D, pic_w: float, title: String, sub: String, title_size := 25, sub_size := 19) -> void:
	b.focus_mode = Control.FOCUS_NONE
	var on := UI.selected_plate()
	on.set_border_width_all(4)
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
	t.add_theme_color_override("font_outline_color", Color(0.06, 0.035, 0.01, 1.0))
	# (legible on the light wood of an unselected card too; thinner on small names, a thick one made them muddy)
	t.add_theme_constant_override("outline_size", clampi(title_size / 3, 4, 8))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := UI.label(sub, sub_size, UI.TEXT)
	d.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.85))
	d.add_theme_constant_override("outline_size", 3)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)

func _option_group(label: String, names: Array, key: String, values: Array, w := 110) -> Control:
	var v := VBoxContainer.new()
	v.add_child(UI.label(label, 22, UI.GOLD))
	var h := HBoxContainer.new()
	v.add_child(h)
	var btns := []
	for i in names.size():
		var b := Button.new()
		b.toggle_mode = true
		b.text = names[i]
		b.custom_minimum_size = Vector2(w, 48)
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
	for k in _bonus_buttons:
		_bonus_buttons[k].button_pressed = k == _settings.get("bonus", "")
	_refresh_scenario()

func _select_faction(f: String) -> void:
	_settings["faction"] = f
	_refresh_preview()
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
		b.custom_minimum_size = Vector2(238, 104)
		_card(b, Assets.hero_portrait(hid), 52, h["name"], h["class"], 17, 17)
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
	_refresh_scenario()

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
	var sc := GameData.scenario(_settings.get("scenario", ""))
	_settings["seed"] = randi() if sc.get("random", false) else int(sc["seed"])
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
