extends CanvasLayer
class_name AdventureHUD
## Adventure screen HUD: right panel (minimap, heroes, towns, selected hero, buttons) + resource bar.

const PANEL_X := 1544.0
const MINI := 316.0
const PAD := 30.0
const COL_W := 155.0       # hero and town list columns, side by side
const COL_GAP := 6
const SLOT_H := 66.0
const BTN := Vector2(76, 62)
const TERRAIN_COLORS := [Color(0.30, 0.50, 0.17), Color(0.47, 0.37, 0.22), Color(0.85, 0.75, 0.48), Color(0.9, 0.92, 0.96),
	Color(0.27, 0.33, 0.22), Color(0.12, 0.30, 0.52), Color(0.62, 0.52, 0.38)]

var adv
var world: Dictionary
var root: Control
var _mini_img: Image
var _mini_tex: ImageTexture
var _mini_k := 1          # minimap pixels per tile (terrain is blended between tiles, markers stay crisp)
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
var _sleep_btn: Button
var _info_box: VBoxContainer

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
	_mini_k = clampi(int(ceil(MINI / float(maxi(size.x, size.y)))) + 1, 2, 9)
	_mini_tex = ImageTexture.create_from_image(Image.create(size.x * _mini_k, size.y * _mini_k, false, Image.FORMAT_RGBA8))
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
	_mini_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mini_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_mini_rect.gui_input.connect(_on_minimap_input)
	root.add_child(_mini_rect)
	_mini_view = _MiniView.new()
	_mini_view.position = _mini_rect.position
	_mini_view.size = _mini_rect.size
	_mini_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_mini_view)

	# heroes and towns side by side (as the classic adventure panel), the selected hero below, then the buttons
	# (one column of lists, then the selected hero, flowing down: only filled slots are shown)
	var v := VBoxContainer.new()
	v.position = Vector2(PANEL_X + PAD, MINI + PAD + 10)
	v.size = Vector2(MINI, 0)
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", COL_GAP)
	v.add_child(cols)
	for k in 2:
		var cv := VBoxContainer.new()
		cv.custom_minimum_size = Vector2(COL_W, 0)
		cv.add_theme_constant_override("separation", 4)
		cv.add_child(UI.label("Heroes" if k == 0 else "Towns", 21, UI.GOLD, true))
		var lst := VBoxContainer.new()
		lst.add_theme_constant_override("separation", 4)
		cv.add_child(lst)
		cols.add_child(cv)
		if k == 0:
			_hero_list = lst
		else:
			_town_list = lst
	v.add_child(HSeparator.new())
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	v.add_child(_detail)

	# the status window over the buttons (as the classic panel): the date, and the kingdom at a glance
	var sp := PanelContainer.new()
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0.03, 0.02, 0.015, 0.85)
	sst.border_color = Color(UI.GOLD_DARK, 0.85)
	sst.set_border_width_all(1)
	sst.set_corner_radius_all(4)
	sst.content_margin_left = 10
	sst.content_margin_right = 10
	sst.content_margin_top = 4
	sst.content_margin_bottom = 4
	sp.add_theme_stylebox_override("panel", sst)
	sp.position = Vector2(PANEL_X + PAD, 1036 - PAD - 2 * BTN.y - 6 - 10 - 64)
	sp.size = Vector2(MINI, 64)
	root.add_child(sp)
	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", -2)
	sp.add_child(_info_box)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(PANEL_X + PAD, 1036 - PAD - 2 * BTN.y - 6)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)
	for e in [["kingdom", "Kingdom overview (K)", func(): open_kingdom()],
			["hero", "Hero screen (I)", func(): _with_hero(open_hero_screen)],
			["sleep", "Put the hero to sleep, or wake it (Z): sleeping heroes are skipped by Next Hero", func(): adv.toggle_sleep()],
			["move", "Continue moving along the planned route (M)", func(): adv.continue_move()],
			["spellbook", "Spellbook (C)", func(): _with_hero(func(h): SpellBook.open(adv, h))],
			["next_hero", "Next hero (H)", func(): adv.next_hero()],
			["system", "Game menu: save, load, quit (Esc)", open_system_menu],
			["end_turn", "End turn (E)", func(): adv.end_turn()]]:
		var b := _icon_button(e[0], e[1], e[2])
		grid.add_child(b)
		if e[0] == "end_turn":
			_end_turn_btn = b
		elif e[0] == "sleep":
			_sleep_btn = b

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
	for i in mini(3, me["heroes"].size()):
		_hero_list.add_child(_hero_card(world["heroes"][me["heroes"][i]]))
	for c in _town_list.get_children():
		c.queue_free()
	for i in mini(3, me["towns"].size()):
		_town_list.add_child(_town_card(world["towns"][me["towns"][i]]))
	if me["towns"].is_empty():
		_town_list.add_child(_empty_slot(SLOT_H))
	# status window: the day, and income / heroes / towns
	for c in _info_box.get_children():
		c.queue_free()
	var d: int = world["day"]
	_info_box.add_child(UI.label("Month %d · Week %d · Day %d" % [(d - 1) / 28 + 1, ((d - 1) / 7) % 4 + 1, (d - 1) % 7 + 1], 18, UI.GOLD))
	var inc := 0
	for tid in me["towns"]:
		inc += TownLogic.daily_income(world["towns"][tid])
	for o in world["objects"].values():
		if o["type"] == "mine" and o["owner"] == adv._human() and GameData.MINES[o["mine"]]["resource"] == "gold":
			inc += GameData.MINES[o["mine"]]["amount"]
	_info_box.add_child(UI.label("+%d gold a day   ·   %d hero%s, %d town%s" % [inc, me["heroes"].size(),
		"" if me["heroes"].size() == 1 else "es", me["towns"].size(), "" if me["towns"].size() == 1 else "s"], 16, Color(0.85, 0.8, 0.68)))
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
		# its secondary skills as small framed icons (hover for name and level)
		var sk := HBoxContainer.new()
		sk.add_theme_constant_override("separation", 3)
		var lv := ["", "Basic", "Advanced", "Expert"]
		for id in hero["skills"]:
			var n := int(hero["skills"][id])
			if n <= 0 or not GameData.SKILLS.has(id):
				continue
			var ic := UI.icon(Assets.tex("icons/skill_%s.png" % id), Vector2(41, 41))
			ic.tooltip_text = "%s %s" % [lv[clampi(n, 0, 3)], GameData.SKILLS[id]["name"]]
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			sk.add_child(ic)
		if sk.get_child_count() > 0:
			_detail.add_child(sk)
	if _sleep_btn:
		_sleep_btn.disabled = hero.is_empty()
	_mini_view.queue_redraw()

## An empty list slot: a shallow recess in the panel, not a black box.
func _empty_slot(h: float) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(COL_W, h)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.075, 0.05, 0.35)
	st.border_color = Color(UI.GOLD_DARK, 0.45)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", st)
	return p

## A hero in the list: portrait with its movement (green) and spell points (blue) as bars beside it, and the name.
func _hero_card(h: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(COL_W, SLOT_H)
	b.toggle_mode = true
	b.button_pressed = h["uid"] == world.get("selected_hero", -1)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s, level %d %s\nMovement %d / %d, spell points %d / %d" % [h["name"], h["level"], h["class"],
		h["movement"], h["max_movement"], h["mana"], GameState.max_mana(h)]
	b.pressed.connect(func(): adv.select_hero(h["uid"]))
	var on := UI.selected_plate(4)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	# the face band of the portrait (the name is in the tooltip and the panel below), then the two bars, thick
	var bw := 14.0
	var p := TextureRect.new()
	p.texture = Assets.hero_portrait(h["id"])
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	p.clip_contents = true
	p.position = Vector2(5, 5)
	p.size = Vector2(COL_W - 10 - 2 * bw - 8, SLOT_H - 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(p)
	var x := p.position.x + p.size.x + 4
	for bar in [[float(h["movement"]) / maxf(1.0, h["max_movement"]), Color(0.35, 0.82, 0.3)],
			[float(h["mana"]) / maxf(1.0, GameState.max_mana(h)), Color(0.35, 0.58, 1.0)]]:
		var c := _bar(bar[0], bar[1], bw)
		c.vertical = true
		c.position = Vector2(x, 5)
		c.size = Vector2(bw, SLOT_H - 10)
		b.add_child(c)
		x += bw + 4
	if h.get("asleep", false):  # dimmed, with the moon over the portrait
		p.modulate = Color(0.55, 0.55, 0.65)
		var z := UI.icon(Assets.tex("ui/btn_sleep.png"), Vector2(30, 30))
		z.position = Vector2(8, 6)
		z.size = z.custom_minimum_size
		z.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(z)
	return b

func _bar(frac: float, col: Color, width: float) -> Control:
	var c := _Bar.new()
	c.frac = clampf(frac, 0, 1)
	c.col = col
	c.custom_minimum_size = Vector2(width, 8)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## A town in the list: its picture from the map with the name on a band across the bottom.
func _town_card(t: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(COL_W, SLOT_H)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s (%s): %d gold a day" % [t["name"], GameData.FACTIONS[t["faction"]]["name"], TownLogic.daily_income(t)]
	b.pressed.connect(func():
		Audio.sfx("click", -6)
		adv.open_town(t["uid"]))
	var pic := TextureRect.new()
	pic.texture = _trimmed("map/town_%s.png" % t["faction"])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.position = Vector2(4, 4)
	pic.size = Vector2(COL_W - 8, SLOT_H - 8)
	pic.clip_contents = true
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var band := Label.new()
	band.text = t["name"]
	band.add_theme_font_size_override("font_size", 16)
	band.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.05, 0.035, 0.02, 0.85)
	bs.border_color = Color(UI.GOLD_DARK, 0.9)
	bs.border_width_top = 1
	band.add_theme_stylebox_override("normal", bs)
	band.position = Vector2(5, SLOT_H - 30)
	band.size = Vector2(COL_W - 10, 25)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(band)
	return b

## A square panel button with a painted icon (and a tooltip naming it and its key).
func _icon_button(id: String, tip: String, cb: Callable) -> Button:
	var b := UI.button("", cb)
	b.custom_minimum_size = BTN
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var ic := UI.icon(Assets.tex("ui/btn_%s.png" % id), BTN - Vector2(14, 10))
	ic.position = Vector2(7, 5)
	ic.size = ic.custom_minimum_size
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	b.draw.connect(func(): ic.modulate = Color(0.45, 0.42, 0.4) if b.disabled else Color.WHITE)
	return b

## A sprite cut to its visible pixels (map sprites have room around them for shadows), cached.
var _trims := {}
func _trimmed(path: String) -> Texture2D:
	if _trims.has(path):
		return _trims[path]
	var tex := Assets.tex(path)
	var out: Texture2D = tex
	var img := tex.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(img.get_used_rect())
		out = at
	_trims[path] = out
	return out

func _with_hero(f: Callable) -> void:
	var h: Dictionary = adv.selected_hero()
	if not h.is_empty():
		f.call(h)

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
	# terrain blended between tiles in two steps (soft shores and forest edges), with a faint painted grain
	var big := _mini_img.duplicate()
	big.resize(size.x * 2, size.y * 2, Image.INTERPOLATE_BILINEAR)
	big.resize(size.x * _mini_k, size.y * _mini_k, Image.INTERPOLATE_CUBIC)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in big.get_height():
		for x in big.get_width():
			var c: Color = big.get_pixel(x, y)
			if c.v > 0.1:
				big.set_pixel(x, y, c.darkened(rng.randf() * 0.07))
	# mines, towns and heroes as round dots in their owner's colour (neutral: a small dark dot), heroes brightest
	for o in world["objects"].values():
		if o["type"] == "mine" and ex[o["pos"].y * size.x + o["pos"].x]:
			var own: bool = o["owner"] >= 0
			_mini_dot(big, Vector2(o["pos"]) + Vector2(0.5, 0.5), 0.95 if own else 0.7,
				GameData.PLAYER_COLORS[o["owner"]] if own else Color(0.32, 0.3, 0.27))
	for t in world["towns"].values():
		if ex[t["pos"].y * size.x + t["pos"].x]:
			var c: Color = Color(0.78, 0.76, 0.7) if t["owner"] < 0 else GameData.PLAYER_COLORS[t["owner"]]
			_mini_dot(big, Vector2(t["pos"]) + Vector2(0.5, 0.0), 1.7, c)
	for hh in world["heroes"].values():
		if ex[hh["pos"].y * size.x + hh["pos"].x]:
			_mini_dot(big, Vector2(hh["pos"]) + Vector2(0.5, 0.5), 1.0, GameData.PLAYER_COLORS[hh["owner"]].lightened(0.45))
	_mini_tex.update(big)

## A round marker on the minimap with a dark rim: centre `c` and radius `r` in tiles.
func _mini_dot(img: Image, c: Vector2, r: float, col: Color) -> void:
	var k := float(_mini_k)
	var cp := c * k
	var rp := maxf(2.0, r * k)
	for y in range(int(cp.y - rp - 1), int(cp.y + rp + 2)):
		for x in range(int(cp.x - rp - 1), int(cp.x + rp + 2)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(cp)
			if d <= rp - 1.2:
				img.set_pixel(x, y, col.lightened(0.25) if d < rp * 0.4 else col)
			elif d <= rp:
				img.set_pixel(x, y, Color(0.05, 0.03, 0.02))

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

## Kingdom overview: towns with their income, heroes with their armies, the mines held and the day's income.
func open_kingdom() -> void:
	var me: Dictionary = adv.human_player()
	var idx: int = adv._human()
	var m := Modal.custom(adv, "Kingdom Overview", 1040)
	var income := {}
	for r in GameData.RESOURCES:
		income[r] = 0
	m.body.add_child(UI.label("Towns", 24, UI.GOLD, true))
	for tid in me["towns"]:
		var t: Dictionary = world["towns"][tid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var pic := UI.icon(Assets.tex("map/town_%s.png" % t["faction"]), Vector2(96, 64))
		row.add_child(pic)
		var g := TownLogic.daily_income(t)
		income["gold"] += g
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.add_child(UI.label("%s  (%s)" % [t["name"], GameData.FACTIONS[t["faction"]]["name"]], 21))
		tv.add_child(UI.label("%d gold a day" % g, 18, Color(0.95, 0.82, 0.45)))
		row.add_child(tv)
		m.body.add_child(row)
	if me["towns"].is_empty():
		m.body.add_child(UI.label("No towns.", 19, Color(0.8, 0.75, 0.62)))
	m.body.add_child(UI.label("Heroes", 24, UI.GOLD, true))
	for hid in me["heroes"]:
		var h: Dictionary = world["heroes"][hid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.add_child(UI.icon(Assets.hero_portrait(h["id"]), Vector2(64, 64)))
		var hv := VBoxContainer.new()
		hv.custom_minimum_size = Vector2(300, 0)
		hv.add_theme_constant_override("separation", -2)
		hv.add_child(UI.label(h["name"] + ("  (asleep)" if h.get("asleep", false) else ""), 21))
		hv.add_child(UI.label("Level %d %s" % [h["level"], h["class"]], 18, Color(0.85, 0.8, 0.68)))
		row.add_child(hv)
		var army := ArmyStrip.new()
		army.slot_size = Vector2(56, 56)
		army.editable = false
		army.bind(h["army"], {})
		row.add_child(army)
		m.body.add_child(row)
	m.body.add_child(UI.label("Mines", 24, UI.GOLD, true))
	var held := {}
	for o in world["objects"].values():
		if o["type"] == "mine" and o["owner"] == idx:
			var md: Dictionary = GameData.MINES[o["mine"]]
			held[md["resource"]] = held.get(md["resource"], 0) + 1
			income[md["resource"]] += md["amount"]
	var mg := HBoxContainer.new()
	mg.add_theme_constant_override("separation", 22)
	for r in GameData.RESOURCES:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.add_child(UI.icon(Assets.res_icon(r), Vector2(34, 34)))
		box.add_child(UI.label("x %d" % held.get(r, 0), 19))
		box.tooltip_text = GameData.RESOURCE_NAMES[r]
		mg.add_child(box)
	m.body.add_child(mg)
	m.body.add_child(HSeparator.new())
	var inc := HBoxContainer.new()
	inc.add_theme_constant_override("separation", 22)
	inc.add_child(UI.label("Income each day:", 21, UI.GOLD))
	for r in GameData.RESOURCES:
		if income[r] > 0:
			var box := HBoxContainer.new()
			box.add_theme_constant_override("separation", 6)
			box.add_child(UI.icon(Assets.res_icon(r), Vector2(30, 30)))
			box.add_child(UI.label("+%d" % income[r], 19, Color(0.6, 0.9, 0.55)))
			inc.add_child(box)
	m.body.add_child(inc)
	m.add_buttons([["Close", "close"]])
	m.set_meta("cancel", "close")

func open_hero_screen(h: Dictionary) -> void:
	var m := HeroScreen.open(adv, h)
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
