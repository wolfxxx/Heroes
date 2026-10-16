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
	if Assets.has("ui/main_menu_bg.png"):
		var bg := TextureRect.new()
		bg.texture = Assets.tex("ui/main_menu_bg.png")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://scripts/menu/menu_bg.gdshader")
		bg.material = mat
		add_child(bg)
	# Vignette for legibility.
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://scripts/ui/vignette.gdshader")
	vig.material = vm
	add_child(vig)

	# darken the sky behind the title so it reads over the castle silhouette
	var band := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.7))
	grad.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	band.texture = gt
	band.position = Vector2.ZERO
	band.size = Vector2(1920, 400)
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	if Assets.has("ui/logo.png"):
		var logo := TextureRect.new()
		logo.texture = Assets.tex("ui/logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.position = Vector2(510, 12)
		logo.size = Vector2(900, 270)
		add_child(logo)
	else:
		var t := UI.label("Heroes of the", 44, UI.GOLD, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.position = Vector2(0, 90)
		t.size = Vector2(1920, 60)
		add_child(t)
		var t2 := UI.label("SHATTERED CROWN", 96, UI.GOLD, true)
		t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t2.position = Vector2(0, 140)
		t2.size = Vector2(1920, 130)
		t2.add_theme_constant_override("shadow_offset_x", 4)
		t2.add_theme_constant_override("shadow_offset_y", 4)
		add_child(t2)

func _build_menu() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(760, 420)
	panel.custom_minimum_size = Vector2(400, 0)
	add_child(panel)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 14)
	panel.add_child(_menu_box)
	var entries := [["New Game", _open_setup], ["Load Game", _load_game], ["Quick Battle", _quick_battle], ["Quit", func(): get_tree().quit()]]
	for e in entries:
		var b := UI.button(e[0], e[1], 30)
		b.custom_minimum_size = Vector2(360, 64)
		if e[0] == "Load Game":
			b.disabled = not GameState.has_save()
		_menu_box.add_child(b)
	_menu_box.set_meta("panel", panel)

# ---------------------------------------------------------------------------------------------
# New game setup
# ---------------------------------------------------------------------------------------------
func _build_setup() -> void:
	_setup_panel = PanelContainer.new()
	_setup_panel.position = Vector2(310, 300)
	_setup_panel.custom_minimum_size = Vector2(1300, 700)
	_setup_panel.visible = false
	add_child(_setup_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
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
		b.custom_minimum_size = Vector2(620, 130)
		b.add_theme_font_size_override("font_size", 22)
		b.icon = Assets.tex("map/town_%s.png" % f)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 150)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s\n%s" % [GameData.FACTIONS[f]["name"], GameData.FACTIONS[f]["desc"]]
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
		b.custom_minimum_size = Vector2(300, 150)
		b.icon = Assets.hero_portrait(hid)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%s" % [h["name"], h["class"]]
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_constant_override("icon_max_width", 120)
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

func _close_setup() -> void:
	_setup_panel.visible = false
	_menu_box.get_meta("panel").visible = true

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
