extends CanvasLayer
class_name AdventureHUD
## Adventure screen HUD: right panel (minimap, heroes, towns, selected hero, buttons) + resource bar.

const PANEL_X := 1544.0
const MINI := 316.0
const PAD := 30.0
const TERRAIN_COLORS := [Color(0.30, 0.50, 0.17), Color(0.47, 0.37, 0.22), Color(0.85, 0.75, 0.48), Color(0.9, 0.92, 0.96),
	Color(0.27, 0.33, 0.22), Color(0.12, 0.30, 0.52), Color(0.62, 0.52, 0.38)]

var adv
var world: Dictionary
var root: Control
var _mini_img: Image
var _mini_tex: ImageTexture
var _mini_rect: TextureRect
var _mini_view: Control
var _hero_list: VBoxContainer
var _town_list: VBoxContainer
var _detail: VBoxContainer
var _res_labels := {}
var _date_label: Label
var _status: Label
var _toast: Label
var _turn_label: Label
var _turn_panel: PanelContainer
var _end_turn_btn: Button

func setup(a) -> void:
	adv = a
	world = a.world
	layer = 10
	root = Control.new()
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_panel()
	_build_bar()
	var size: Vector2i = world["size"]
	_mini_img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	_mini_tex = ImageTexture.create_from_image(_mini_img)
	_mini_rect.texture = _mini_tex
	refresh_minimap()
	refresh()

# ---------------------------------------------------------------------------------------------
func _build_panel() -> void:
	var panel := Panel.new()
	panel.position = Vector2(PANEL_X, 0)
	panel.size = Vector2(1920 - PANEL_X, 1036)
	root.add_child(panel)

	var frame := Panel.new()
	frame.position = Vector2(PANEL_X + PAD - 4, PAD - 4)
	frame.size = Vector2(MINI + 8, MINI + 8)
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color.BLACK
	fs.border_color = UI.GOLD_DARK
	fs.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", fs)
	root.add_child(frame)
	_mini_rect = TextureRect.new()
	_mini_rect.position = Vector2(PANEL_X + PAD, PAD)
	_mini_rect.size = Vector2(MINI, MINI)
	_mini_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mini_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mini_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_mini_rect.gui_input.connect(_on_minimap_input)
	root.add_child(_mini_rect)
	_mini_view = _MiniView.new()
	_mini_view.position = _mini_rect.position
	_mini_view.size = _mini_rect.size
	_mini_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_mini_view)

	var v := VBoxContainer.new()
	v.position = Vector2(PANEL_X + PAD, MINI + PAD + 14)
	v.size = Vector2(MINI, 1036 - MINI - 130)
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	v.add_child(UI.label("Heroes", 22, UI.GOLD, true))
	_hero_list = VBoxContainer.new()
	_hero_list.add_theme_constant_override("separation", 4)
	v.add_child(_hero_list)
	v.add_child(UI.label("Towns", 22, UI.GOLD, true))
	_town_list = VBoxContainer.new()
	_town_list.add_theme_constant_override("separation", 4)
	v.add_child(_town_list)
	var sep := HSeparator.new()
	v.add_child(sep)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	v.add_child(_detail)

	var brow := HBoxContainer.new()
	brow.position = Vector2(PANEL_X + PAD - 2, 1036 - 88)
	brow.size = Vector2(MINI + 4, 60)
	brow.add_theme_constant_override("separation", 8)
	root.add_child(brow)
	var nb := UI.button("Next Hero", func(): adv.next_hero(), 19)
	nb.custom_minimum_size = Vector2(110, 56)
	nb.tooltip_text = "Select the next hero (H)"
	brow.add_child(nb)
	_end_turn_btn = UI.button("End Turn", func(): adv.end_turn(), 19)
	_end_turn_btn.custom_minimum_size = Vector2(110, 56)
	_end_turn_btn.tooltip_text = "End your turn (E)"
	brow.add_child(_end_turn_btn)
	var sb := UI.button("Menu", open_system_menu, 19)
	sb.custom_minimum_size = Vector2(88, 56)
	brow.add_child(sb)

	_turn_panel = PanelContainer.new()
	_turn_panel.position = Vector2(520, 20)
	_turn_panel.custom_minimum_size = Vector2(500, 0)
	_turn_panel.visible = false
	root.add_child(_turn_panel)
	_turn_label = UI.label("", 26, UI.GOLD, true)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_panel.add_child(_turn_label)

func _build_bar() -> void:
	var bar := Panel.new()
	bar.position = Vector2(0, 1036)
	bar.size = Vector2(1920, 44)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.07, 0.05, 0.97)
	st.border_color = UI.GOLD_DARK
	st.border_width_top = 2
	bar.add_theme_stylebox_override("panel", st)
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.position = Vector2(16, 1038)
	h.size = Vector2(1200, 40)
	h.add_theme_constant_override("separation", 28)
	root.add_child(h)
	for r in GameData.RESOURCES:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var ic := UI.icon(Assets.res_icon(r), Vector2(34, 34))
		ic.tooltip_text = GameData.RESOURCE_NAMES[r]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(ic)
		var l := UI.label("0", 22)
		l.custom_minimum_size = Vector2(70 if r == "gold" else 40, 0)
		box.add_child(l)
		_res_labels[r] = l
		h.add_child(box)
	_date_label = UI.label("", 22, UI.GOLD)
	_date_label.position = Vector2(1500, 1042)
	_date_label.size = Vector2(400, 34)
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_date_label)

	_status = UI.label("", 21)
	_status.position = Vector2(16, 994)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sbg := StyleBoxFlat.new()  # dark backing: the status line sits on top of busy map art
	sbg.bg_color = Color(0.06, 0.04, 0.03, 0.78)
	sbg.border_color = UI.GOLD_DARK
	sbg.set_border_width_all(1)
	sbg.set_corner_radius_all(4)
	sbg.content_margin_left = 12
	sbg.content_margin_right = 12
	sbg.content_margin_top = 2
	sbg.content_margin_bottom = 2
	_status.add_theme_stylebox_override("normal", sbg)
	_status.visible = false
	root.add_child(_status)

	_toast = UI.label("", 26, UI.TEXT)
	_toast.position = Vector2(0, 900)
	_toast.size = Vector2(PANEL_X, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)

# ---------------------------------------------------------------------------------------------
func refresh() -> void:
	var me: Dictionary = adv.human_player()
	for r in GameData.RESOURCES:
		_res_labels[r].text = str(me["resources"].get(r, 0))
	_date_label.text = adv.rules.date_string()
	for c in _hero_list.get_children():
		c.queue_free()
	for i in 3:
		if i < me["heroes"].size():
			_hero_list.add_child(_hero_card(world["heroes"][me["heroes"][i]]))
		else:
			_hero_list.add_child(_empty_slot(56))
	for c in _town_list.get_children():
		c.queue_free()
	for i in 2:
		if i < me["towns"].size():
			_town_list.add_child(_town_card(world["towns"][me["towns"][i]]))
		else:
			_town_list.add_child(_empty_slot(40))
	for c in _detail.get_children():
		c.queue_free()
	var hero: Dictionary = adv.selected_hero()
	if not hero.is_empty():
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		var portrait := UI.icon(Assets.hero_portrait(hero["id"]), Vector2(84, 84))
		top.add_child(portrait)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.add_child(UI.label(hero["name"], 21, UI.GOLD))
		info.add_child(UI.label("Level %d %s" % [hero["level"], hero["class"]], 17))
		info.add_child(UI.label("Move %d / %d" % [hero["movement"], hero["max_movement"]], 17, Color(0.6, 0.9, 0.55)))
		info.add_child(UI.label("Mana %d / %d" % [hero["mana"], GameState.max_mana(hero)], 17, Color(0.6, 0.75, 1.0)))
		top.add_child(info)
		_detail.add_child(top)
		var g := GridContainer.new()
		g.columns = 4
		g.add_theme_constant_override("h_separation", 12)
		for st in ["attack", "defense", "power", "knowledge"]:
			var box := HBoxContainer.new()
			box.add_child(UI.icon(Assets.tex("icons/stat_%s.png" % st), Vector2(32, 32)))
			box.add_child(UI.label(str(GameState.hero_stat(hero, st)), 21))
			box.tooltip_text = st.capitalize()
			g.add_child(box)
		_detail.add_child(g)
		var army := ArmyStrip.new()
		army.slot_size = Vector2(41, 41)
		army.editable = false
		army.bind(hero["army"], {})
		army.add_theme_constant_override("separation", 3)
		_detail.add_child(army)
	_mini_view.queue_redraw()

func _empty_slot(h: float) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(MINI, h)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.04, 0.03, 0.75)
	st.border_color = UI.GOLD_DARK
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", st)
	return p

func _hero_card(h: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MINI, 56)
	b.toggle_mode = true
	b.button_pressed = h["uid"] == world.get("selected_hero", -1)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): adv.select_hero(h["uid"]))
	var hb := HBoxContainer.new()
	hb.position = Vector2(6, 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var p := UI.icon(Assets.hero_portrait(h["id"]), Vector2(48, 48))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(p)
	# movement / mana as vertical bars beside the portrait (as in the classic games), name to the right
	var mv := _bar(float(h["movement"]) / maxf(1.0, h["max_movement"]), Color(0.35, 0.8, 0.3), 7)
	mv.vertical = true
	mv.custom_minimum_size = Vector2(7, 48)
	mv.tooltip_text = "Movement"
	hb.add_child(mv)
	var mn := _bar(float(h["mana"]) / maxf(1.0, GameState.max_mana(h)), Color(0.35, 0.55, 1.0), 7)
	mn.vertical = true
	mn.custom_minimum_size = Vector2(7, 48)
	hb.add_child(mn)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", -4)
	hb.add_child(v)
	var sel := b.button_pressed  # the selected card is bright gold: dark ink text, no shadow
	var l := UI.label(h["name"], 19, Color(0.16, 0.08, 0.02) if sel else UI.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	var lv := UI.label("Level %d" % h["level"], 16, Color(0.3, 0.18, 0.06) if sel else Color(0.8, 0.75, 0.62))
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lv)
	if sel:
		for x in [l, lv]:
			x.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return b

func _bar(frac: float, col: Color, width: float) -> Control:
	var c := _Bar.new()
	c.frac = clampf(frac, 0, 1)
	c.col = col
	c.custom_minimum_size = Vector2(width, 8)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _town_card(t: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MINI, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.text = "  %s  (%s)" % [t["name"], GameData.FACTIONS[t["faction"]]["name"]]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(func():
		Audio.sfx("click", -6)
		adv.open_town(t["uid"]))
	return b

func set_status(t: String) -> void:
	_status.text = t
	_status.visible = t != ""
	_status.reset_size()

func set_turn_label(t: String) -> void:
	_turn_label.text = t
	_turn_panel.visible = t != ""
	_end_turn_btn.disabled = t != ""

## Big centred announcement (new day) that fades out.
func banner(t: String) -> void:
	var p := PanelContainer.new()
	var l := UI.label(t, 44, UI.GOLD, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.custom_minimum_size = Vector2(520, 0)
	p.position = Vector2((PANEL_X - 520) * 0.5, 120)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

func toast(t: String) -> void:
	_toast.text = t
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)

func float_text(world_pos: Vector2, t: String) -> void:
	var l := UI.label(t, 26, UI.GOLD)
	var screen: Vector2 = (world_pos - adv.cam.position) * adv.cam.zoom
	l.position = screen - Vector2(100, 0)
	l.size = Vector2(200, 36)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 60, 1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

# ---------------------------------------------------------------------------------------------
# Minimap
# ---------------------------------------------------------------------------------------------
func refresh_minimap() -> void:
	var size: Vector2i = world["size"]
	var me: Dictionary = adv.human_player()
	var ex: PackedByteArray = me["explored"]
	var terr: PackedByteArray = world["terrain"]
	var blk: PackedByteArray = world["blocked"]
	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			if not ex[i]:
				_mini_img.set_pixel(x, y, Color(0.07, 0.055, 0.04))  # unexplored: dark parchment, not void black
				continue
			var c: Color = TERRAIN_COLORS[terr[i]]
			if blk[i]:
				c = c.darkened(0.35)
			_mini_img.set_pixel(x, y, c)
	for o in world["objects"].values():
		if o["type"] == "mine" and ex[o["pos"].y * size.x + o["pos"].x]:
			var c: Color = Color(0.6, 0.6, 0.6) if o["owner"] < 0 else GameData.PLAYER_COLORS[o["owner"]]
			_mini_px(o["pos"], c, 1)
	for t in world["towns"].values():
		if ex[t["pos"].y * size.x + t["pos"].x]:
			var c: Color = Color(0.75, 0.75, 0.75) if t["owner"] < 0 else GameData.PLAYER_COLORS[t["owner"]]
			for dy in range(-1, 1):
				for dx in range(-1, 2):
					_mini_px(t["pos"] + Vector2i(dx, dy), c, 0)
	for hh in world["heroes"].values():
		if ex[hh["pos"].y * size.x + hh["pos"].x]:
			_mini_px(hh["pos"], GameData.PLAYER_COLORS[hh["owner"]].lightened(0.3), 0)
	_mini_tex.update(_mini_img)

func _mini_px(p: Vector2i, c: Color, r: int) -> void:
	var size: Vector2i = world["size"]
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := p + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y:
				_mini_img.set_pixel(q.x, q.y, c)

func update_minimap_view(cam_pos: Vector2, view_size: Vector2) -> void:
	var s: Vector2 = Vector2(world["size"]) * WorldGen.TILE
	_mini_view.view_rect = Rect2(cam_pos / s * MINI, view_size / s * MINI)
	_mini_view.queue_redraw()

func _on_minimap_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var s: Vector2 = Vector2(world["size"]) * WorldGen.TILE
		adv.center_on_world(e.position / MINI * s)

# ---------------------------------------------------------------------------------------------
# Dialogs
# ---------------------------------------------------------------------------------------------
func open_system_menu() -> void:
	var m := Modal.custom(adv, "Game Menu", 420)
	for e in [["Save Game", "save"], ["Load Game", "load"], ["Main Menu", "menu"], ["Quit", "quit"], ["Return to Game", "close"]]:
		var val: String = e[1]
		var b := UI.button(e[0], func(): m.close(val), 24)
		b.custom_minimum_size = Vector2(340, 56)
		if val == "load":
			b.disabled = not GameState.has_save()
		m.body.add_child(b)
	m.set_meta("cancel", "close")
	var r = await m.closed
	match r:
		"save":
			if GameState.save_game():
				toast("Game saved")
		"load":
			if GameState.load_game():
				GameState.change_scene(GameState.SCENE_ADVENTURE)
		"menu":
			GameState.change_scene(GameState.SCENE_MENU)
		"quit":
			adv.get_tree().quit()

func open_hero_screen(h: Dictionary) -> void:
	var m := Modal.custom(adv, "", 1060)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	m.body.add_child(top)
	top.add_child(UI.icon(Assets.hero_portrait(h["id"]), Vector2(160, 160)))
	var info := VBoxContainer.new()
	top.add_child(info)
	info.add_child(UI.label(h["name"], 36, UI.GOLD, true))
	info.add_child(UI.label("Level %d %s  —  %d / %d experience" % [h["level"], h["class"], h["xp"],
		GameData.XP_LEVELS[mini(h["level"], GameData.XP_LEVELS.size() - 1)]], 21))
	info.add_child(UI.label("Specialty: %s     Movement %d / %d     Mana %d / %d" % [GameData.HEROES[h["id"]]["specialty"],
		h["movement"], h["max_movement"], h["mana"], GameState.max_mana(h)], 21))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 28)
	info.add_child(stats)
	for s in ["attack", "defense", "power", "knowledge"]:
		var v := VBoxContainer.new()
		v.add_child(UI.icon(Assets.tex("icons/stat_%s.png" % s), Vector2(56, 56)))
		var l := UI.label("%s %d" % [s.capitalize(), GameState.hero_stat(h, s)], 19)
		v.add_child(l)
		stats.add_child(v)

	m.body.add_child(UI.label("Secondary Skills", 24, UI.GOLD))
	var sk := GridContainer.new()
	sk.columns = 4
	sk.add_theme_constant_override("h_separation", 10)
	sk.add_theme_constant_override("v_separation", 8)
	m.body.add_child(sk)
	var skill_ids: Array = h["skills"].keys()
	for i in range(skill_ids.size(), 8):
		skill_ids.append("")
	for s in skill_ids:
		var v := HBoxContainer.new()
		v.custom_minimum_size = Vector2(240, 60)
		v.add_theme_constant_override("separation", 8)
		if s == "":
			var empty := PanelContainer.new()
			empty.custom_minimum_size = Vector2(240, 60)
			empty.modulate = Color(1, 1, 1, 0.35)
			sk.add_child(empty)
			continue
		var ic := UI.icon(Assets.skill_icon(s), Vector2(52, 52))
		ic.tooltip_text = GameData.SKILLS[s]["desc"]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(ic)
		v.add_child(UI.label("%s\n%s" % [["", "Basic", "Advanced", "Expert"][mini(3, h["skills"][s])], GameData.SKILLS[s]["name"]], 16))
		sk.add_child(v)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 60)
	m.body.add_child(row)
	var av := VBoxContainer.new()
	row.add_child(av)
	av.add_child(UI.label("Artifacts", 24, UI.GOLD))
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 6)
	av.add_child(ah)
	# one slot per body part, like a HoMM paperdoll
	var by_slot := {}
	var extra := []
	for a in h["artifacts"]:
		var sl: String = GameData.ARTIFACTS[a]["slot"]
		if by_slot.has(sl):
			extra.append(a)
		else:
			by_slot[sl] = a
	for sl in ["head", "weapon", "shield", "ring", "feet", "misc"]:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(66, 66)
		slot.tooltip_text = sl.capitalize()
		if by_slot.has(sl):
			var a: String = by_slot[sl]
			var ic := UI.icon(Assets.artifact_icon(a), Vector2(54, 54))
			ic.tooltip_text = "%s: %s" % [GameData.ARTIFACTS[a]["name"], GameData.ARTIFACTS[a]["desc"]]
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			slot.add_child(ic)
		else:
			var l := UI.label(sl.capitalize(), 13, Color(0.6, 0.55, 0.45))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			slot.add_child(l)
		ah.add_child(slot)
	for a in extra:
		var ic := UI.icon(Assets.artifact_icon(a), Vector2(54, 54))
		ic.tooltip_text = "%s: %s" % [GameData.ARTIFACTS[a]["name"], GameData.ARTIFACTS[a]["desc"]]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		ah.add_child(ic)
	var sv := VBoxContainer.new()
	row.add_child(sv)
	sv.add_child(UI.label("Spells", 24, UI.GOLD))
	var sh := HBoxContainer.new()
	sv.add_child(sh)
	if h["spells"].is_empty():
		sh.add_child(UI.label("None", 18))
	for s in h["spells"]:
		var ic := UI.icon(Assets.spell_icon(s), Vector2(48, 48))
		ic.tooltip_text = "%s (level %d, %d mana): %s" % [GameData.SPELLS[s]["name"], GameData.SPELLS[s]["level"], GameData.SPELLS[s]["mana"], GameData.SPELLS[s]["desc"]]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		sh.add_child(ic)

	m.body.add_child(UI.label("Army  (click to move, shift+click to split, right click for info)", 20, UI.GOLD))
	var strip := ArmyStrip.new()
	strip.bind(h["army"], {}, true)
	m.body.add_child(strip)
	var bh := m.add_buttons([["Close", "close"], ["Dismiss Hero", "dismiss"]])
	m.set_meta("default", "close")
	m.set_meta("cancel", "close")
	var r = await m.closed
	if r == "dismiss":
		var me: Dictionary = adv.human_player()
		if me["heroes"].size() <= 1 and me["towns"].is_empty():
			await Modal.message(adv, "Dismiss", "You cannot dismiss your last hero.").closed
		elif await Modal.confirm(adv, "Dismiss Hero", "Dismiss %s? The hero and the army will leave you." % h["name"]).closed:
			adv.rules._kill_hero(h)
			adv.refresh_after_change()
			adv.select_hero(adv._first_hero_with_mp())
	refresh()

func open_exchange(a: Dictionary, b: Dictionary) -> void:
	var m := Modal.custom(adv, "Hero Meeting", 900)
	var g := {}
	for h in [a, b]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.add_child(UI.icon(Assets.hero_portrait(h["id"]), Vector2(92, 92)))
		var strip := ArmyStrip.new()
		strip.bind(h["army"], g, true)
		hb.add_child(strip)
		m.body.add_child(UI.label(h["name"], 24, UI.GOLD))
		m.body.add_child(hb)
	m.add_buttons([["Done", true]])
	m.set_meta("default", true)
	m.set_meta("cancel", true)
	await m.closed
	refresh()

func open_dwelling(hero: Dictionary, o: Dictionary) -> void:
	await recruit_dialog(adv, o["creature"], o["available"], adv.human_player(), hero["army"], func(n): o["available"] -= n)
	refresh()

## Shared recruit dialog (also used by the town screen). on_bought(n) is called after paying.
static func recruit_dialog(owner_node: Node, cid: String, available: int, player: Dictionary, army: Array, on_bought: Callable) -> int:
	var c: Dictionary = GameData.CREATURES[cid]
	var m := Modal.custom(owner_node, "Recruit %s" % c["plural"], 900)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 28)
	m.body.add_child(h)
	# big creature on a framed backdrop
	var art := PanelContainer.new()
	art.custom_minimum_size = Vector2(320, 320)
	h.add_child(art)
	art.add_child(UI.icon(Assets.creature(cid), Vector2(300, 300)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	h.add_child(v)
	v.add_child(UI.label("Available: %d" % available, 24, UI.GOLD))
	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", 18)
	v.add_child(stats)
	for row_d in [["stat_attack", "Attack", str(c["attack"])], ["stat_defense", "Defense", str(c["defense"])],
			["stat_power", "Damage", "%d - %d" % c["dmg"]], ["stat_knowledge", "Health", str(c["hp"])]]:
		stats.add_child(UI.icon(Assets.tex("icons/%s.png" % row_d[0]), Vector2(30, 30)))
		stats.add_child(UI.label("%s %s" % [row_d[1], row_d[2]], 19))
	v.add_child(UI.label("Speed %d%s" % [c["speed"], ("   Shots %d" % c["shots"]) if c["shots"] > 0 else ""], 19))
	var ab: Array = c["abilities"].map(func(x): return GameData.ABILITY_TEXT.get(x, x))
	if ab.size() > 0:
		var al := UI.label(", ".join(ab), 17, Color(0.85, 0.8, 0.65))
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		al.custom_minimum_size = Vector2(480, 0)
		v.add_child(al)
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 8)
	cost_row.add_child(UI.label("Cost per unit:", 20))
	for r in c["cost"]:
		cost_row.add_child(UI.icon(Assets.res_icon(r), Vector2(30, 30)))
		cost_row.add_child(UI.label(str(c["cost"][r]), 20))
	v.add_child(cost_row)
	var maxn := available
	for r in c["cost"]:
		if c["cost"][r] > 0:
			maxn = mini(maxn, player["resources"].get(r, 0) / c["cost"][r])
	maxn = maxi(0, maxn)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = maxn
	slider.value = maxn
	slider.custom_minimum_size = Vector2(480, 32)
	v.add_child(slider)
	var count_l := UI.label("", 24, UI.GOLD)
	v.add_child(count_l)
	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", 8)
	v.add_child(total_row)
	var upd := func(_x = 0):
		var n := int(slider.value)
		count_l.text = "Recruit %d %s" % [n, c["plural"] if n != 1 else c["name"]]
		for ch in total_row.get_children():
			ch.queue_free()
		total_row.add_child(UI.label("Total:", 20))
		for r in c["cost"]:
			total_row.add_child(UI.icon(Assets.res_icon(r), Vector2(30, 30)))
			var have: int = player["resources"].get(r, 0)
			total_row.add_child(UI.label("%d / %d" % [c["cost"][r] * n, have], 20, UI.TEXT if c["cost"][r] * n <= have else Color(1, 0.5, 0.4)))
	slider.value_changed.connect(upd)
	upd.call()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	m.body.add_child(row)
	for e in [["Recruit", func(): m.close("buy")], ["Max", func(): slider.value = maxn], ["Cancel", func(): m.close("cancel")]]:
		var b := UI.button(e[0], e[1], 24)
		b.custom_minimum_size = Vector2(160, 54)
		row.add_child(b)
	m.set_meta("cancel", "cancel")
	m.set_meta("default", "buy")
	var r = await m.closed
	if r == "buy" and int(slider.value) > 0:
		var n := int(slider.value)
		if GameState.add_to_army(army, cid, n):
			TownLogic.pay(player, c["cost"], n)
			on_bought.call(n)
			Audio.sfx("recruit")
			return n
		else:
			Audio.sfx("error")
	return 0

class _Bar extends Control:
	var frac := 1.0
	var col := Color.GREEN
	var vertical := false  # fills bottom-up
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		if vertical:
			draw_rect(Rect2(Vector2(0, size.y * (1.0 - frac)), Vector2(size.x, size.y * frac)), col)
		else:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * frac, size.y)), col)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8), false, 1.0)

class _MiniView extends Control:
	var view_rect := Rect2()
	func _draw() -> void:
		var r := view_rect.intersection(Rect2(Vector2.ZERO, size))
		draw_rect(r, Color(1, 1, 1, 0.9), false, 1.5)
