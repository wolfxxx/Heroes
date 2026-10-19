extends CanvasLayer
class_name AdventureHUD
## Adventure screen HUD: right panel + resource bar. The panel as the classic one: the minimap; the hero list (portraits
## with movement and spell point bars) and the town list in two scrolling columns with the buttons between them; and
## under them the status window, which shows the selected hero, the kingdom or the date (click it to cycle).

const PANEL_X := 1544.0
const MINI := 316.0
const PAD := 30.0
const COL_W := 98.0        # hero and town list columns, the buttons between them
const SLOT_H := 52.0
const SLOTS := 5           # list slots shown; the arrows scroll the rest
const ARROW_H := 22.0
const LIST_Y := MINI + PAD + 12
const LIST_H := ARROW_H * 2 + SLOTS * SLOT_H + (SLOTS + 1) * 4
const BTN := Vector2(51, 56)
const STATUS_Y := LIST_Y + LIST_H + 10
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
var _hero_off := 0
var _town_off := 0
var _view := 0             # status window: 0 the hero, 1 the kingdom, 2 the date
var _view_dots: Control
var _res_labels := {}
var _date_label: Label
var _status: Label
var _toast: Label
var _turn_label: Label
var _turn_panel: PanelContainer
var _end_turn_btn: Button
var _sleep_btn: Button

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

	# the hero list (left) and the town list (right), each scrolling, with the buttons between them
	var x0 := PANEL_X + PAD
	for k in 2:
		var lst := VBoxContainer.new()
		lst.position = Vector2(x0 + (0.0 if k == 0 else MINI - COL_W), LIST_Y)
		lst.size = Vector2(COL_W, LIST_H)
		lst.add_theme_constant_override("separation", 4)
		root.add_child(lst)
		if k == 0:
			_hero_list = lst
		else:
			_town_list = lst
	var grid := GridContainer.new()
	grid.columns = 2
	var gw := BTN.x * 2 + 4
	grid.position = Vector2(x0 + (MINI - gw) * 0.5, LIST_Y + (LIST_H - (BTN.y * 4 + 3 * 8)) * 0.5)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 8)
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

	# the status window: the selected hero, the kingdom, or the date (a click shows the next)
	var sp := PanelContainer.new()
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0.03, 0.02, 0.015, 0.88)
	sst.border_color = UI.GOLD_DARK
	sst.set_border_width_all(2)
	sst.set_corner_radius_all(4)
	sst.content_margin_left = 10
	sst.content_margin_right = 10
	sst.content_margin_top = 8
	sst.content_margin_bottom = 8
	sp.add_theme_stylebox_override("panel", sst)
	sp.position = Vector2(x0, STATUS_Y)
	sp.size = Vector2(MINI, 1036 - PAD + 8 - STATUS_Y)
	sp.clip_contents = true
	sp.tooltip_text = "Click: show the hero, the kingdom or the date"
	sp.mouse_filter = Control.MOUSE_FILTER_STOP
	sp.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Audio.sfx("click", -6)
			show_view((_view + 1) % 3))
	root.add_child(sp)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 9)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(_detail)
	_view_dots = _Dots.new()
	_view_dots.position = Vector2(x0 + MINI - 74, 1036 - PAD - 14)
	_view_dots.size = Vector2(66, 18)
	_view_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_view_dots)

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
	_fill_list(_hero_list, me["heroes"], true)
	_fill_list(_town_list, me["towns"], false)
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var hero: Dictionary = adv.selected_hero()
	_view_dots.set("on", _view)
	_view_dots.queue_redraw()
	match _view:
		0:
			if hero.is_empty():
				_kingdom_view(me)
			else:
				_hero_view(hero)
		1:
			_kingdom_view(me)
		2:
			_date_view()
	if _sleep_btn:
		_sleep_btn.disabled = hero.is_empty()
	_mini_view.queue_redraw()

## Shows a status window view (0 the hero, 1 the kingdom, 2 the date).
func show_view(v: int) -> void:
	_view = v
	refresh()

## At the start of a day the status window shows the date for a while (as the classic panel), then the hero again.
func flash_date() -> void:
	show_view(2)
	await get_tree().create_timer(4.0).timeout
	if _view == 2:
		show_view(0)

## A list column: the up arrow, five slots from the scroll position (empty ones as recesses), the down arrow.
func _fill_list(lst: VBoxContainer, ids: Array, heroes: bool) -> void:
	for c in lst.get_children():
		lst.remove_child(c)
		c.queue_free()
	var off: int = clampi(_hero_off if heroes else _town_off, 0, maxi(0, ids.size() - SLOTS))
	if heroes:
		_hero_off = off
	else:
		_town_off = off
	lst.add_child(_arrow(true, off > 0, func(): _scroll(heroes, -1)))
	for i in SLOTS:
		var k := off + i
		if k < ids.size():
			lst.add_child(_hero_card(world["heroes"][ids[k]]) if heroes else _town_card(world["towns"][ids[k]]))
		else:
			lst.add_child(_empty_slot(SLOT_H))
	lst.add_child(_arrow(false, off + SLOTS < ids.size(), func(): _scroll(heroes, 1)))

func _scroll(heroes: bool, d: int) -> void:
	if heroes:
		_hero_off += d
	else:
		_town_off += d
	Audio.sfx("click", -6)
	refresh()

## A list's scroll arrow: a gold triangle on a small plate, dimmed when there is nothing more that way.
func _arrow(up: bool, live: bool, cb: Callable) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(COL_W, ARROW_H)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not live
	b.tooltip_text = "Scroll up" if up else "Scroll down"
	b.pressed.connect(cb)
	var t := _Tri.new()
	t.up = up
	t.live = live
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	return b

## The status window's hero view: portrait, name, movement and spell points, the primary skills, morale, luck and
## experience, the army and the secondary skills.
func _hero_view(hero: Dictionary) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(UI.icon(Assets.hero_portrait(hero["id"]), Vector2(84, 84)))
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
		g.add_child(box)
	_detail.add_child(g)
	var ml := HBoxContainer.new()  # morale, luck and experience (as the classic hero panel)
	ml.add_theme_constant_override("separation", 6)
	var mo: Array = HeroScreen._morale(hero)
	var lk := int(hero["skills"].get("luck", 0)) + GameState.hero_stat(hero, "luck")
	for e in [["skill_leadership", mo[0]], ["skill_luck", lk]]:
		ml.add_child(UI.icon(Assets.tex("icons/%s.png" % e[0]), Vector2(32, 32)))
		var val: int = e[1]
		ml.add_child(UI.label("%+d" % val if val != 0 else "0", 20, Color(0.6, 0.92, 0.5) if val > 0 else (Color(1, 0.55, 0.45) if val < 0 else UI.TEXT)))
	var nxt := 0
	for t in GameData.XP_LEVELS:
		if t > int(hero["xp"]):
			nxt = t
			break
	ml.add_child(UI.label("  Exp %d / %d" % [hero["xp"], nxt] if nxt > 0 else "  Exp %d" % hero["xp"], 17, Color(0.85, 0.8, 0.68)))
	_detail.add_child(ml)
	var army := ArmyStrip.new()
	army.slot_size = Vector2(40, 40)
	army.editable = false
	army.bind(hero["army"], {})
	army.add_theme_constant_override("separation", 3)
	_detail.add_child(army)
	var sk := HBoxContainer.new()  # its eight secondary skill sockets (the empty ones as recesses)
	sk.add_theme_constant_override("separation", 2)
	var ids: Array = hero["skills"].keys().filter(func(k): return int(hero["skills"][k]) > 0 and GameData.SKILLS.has(k))
	for i in 8:
		if i < ids.size():
			sk.add_child(UI.icon(Assets.tex("icons/skill_%s.png" % ids[i]), Vector2(35, 35)))
		else:
			var e := _empty_slot(35)
			e.custom_minimum_size = Vector2(35, 35)
			sk.add_child(e)
	_detail.add_child(sk)

## The status window's kingdom view: the day's income of every resource, and what the kingdom holds.
func _kingdom_view(me: Dictionary) -> void:
	_detail.add_child(UI.label("Kingdom", 22, UI.GOLD, true))
	var inc := {}
	for r in GameData.RESOURCES:
		inc[r] = 0
	for tid in me["towns"]:
		inc["gold"] += TownLogic.daily_income(world["towns"][tid])
	var mines := 0
	for o in world["objects"].values():
		if o["type"] == "mine" and o["owner"] == adv._human():
			mines += 1
			var m: Dictionary = GameData.MINES[o["mine"]]
			inc[m["resource"]] += m["amount"]
	_detail.add_child(UI.label("Income a day", 17, Color(0.85, 0.8, 0.68)))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 2)
	for r in GameData.RESOURCES:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.add_child(UI.icon(Assets.res_icon(r), Vector2(26, 26)))
		box.add_child(UI.label("+%d" % inc[r], 18, UI.GOLD if inc[r] > 0 else Color(0.6, 0.56, 0.5)))
		box.custom_minimum_size.x = 130
		g.add_child(box)
	_detail.add_child(g)
	_detail.add_child(UI.label("%d hero%s · %d town%s · %d mine%s" % [me["heroes"].size(), "" if me["heroes"].size() == 1 else "es",
		me["towns"].size(), "" if me["towns"].size() == 1 else "s", mines, "" if mines == 1 else "s"], 17, Color(0.85, 0.8, 0.68)))

## The status window's date view: the day, the week and the month, and the week's creature.
func _date_view() -> void:
	var d: int = world["day"]
	_detail.add_child(UI.label("Day %d" % ((d - 1) % 7 + 1), 34, UI.GOLD, true))
	_detail.add_child(UI.label("Week %d, Month %d" % [((d - 1) / 7) % 4 + 1, (d - 1) / 28 + 1], 22))
	var cal := _Calendar.new()  # the days of this week and the weeks of this month, today's lit
	cal.day = d
	cal.custom_minimum_size = Vector2(MINI - 24, 64)
	_detail.add_child(cal)
	_detail.add_child(UI.label("Day %d of the campaign" % d, 17, Color(0.85, 0.8, 0.68)))
	var cid: String = world.get("week_creature", "")
	if cid != "" and GameData.CREATURES.has(cid):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(UI.icon(Assets.creature_portrait(cid), Vector2(84, 84)))
		var l := UI.label("The Week of the\n%s" % GameData.CREATURES[cid]["name"], 19, UI.TEXT)
		h.add_child(l)
		_detail.add_child(h)
	else:
		_detail.add_child(UI.label("%d day%s to the next week" % [7 - (d - 1) % 7, "" if 7 - (d - 1) % 7 == 1 else "s"], 17))

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
	# the face band of the portrait (the name is in the tooltip and the status window), then the two bars
	var bw := 6.0
	var p := TextureRect.new()
	p.texture = Assets.hero_portrait(h["id"])
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	p.clip_contents = true
	p.position = Vector2(5, 5)
	p.size = Vector2(COL_W - 10 - 2 * bw - 8, SLOT_H - 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(p)
	var x := p.position.x + p.size.x + 3
	for bar in [[float(h["movement"]) / maxf(1.0, h["max_movement"]), Color(0.35, 0.82, 0.3)],
			[float(h["mana"]) / maxf(1.0, GameState.max_mana(h)), Color(0.35, 0.58, 1.0)]]:
		var c := _bar(bar[0], bar[1], bw)
		c.vertical = true
		c.position = Vector2(x, 5)
		c.size = Vector2(bw, SLOT_H - 10)
		b.add_child(c)
		x += bw + 3
	if h.get("asleep", false):  # dimmed, with the moon over the portrait
		p.modulate = Color(0.55, 0.55, 0.65)
		var z := UI.icon(Assets.tex("ui/btn_sleep.png"), Vector2(24, 24))
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
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED  # (the whole town, as the classic list: name in the tooltip)
	pic.position = Vector2(4, 3)
	pic.size = Vector2(COL_W - 8, SLOT_H - 6)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	return b

## A square panel button with a painted icon (and a tooltip naming it and its key).
func _icon_button(id: String, tip: String, cb: Callable) -> Button:
	var b := UI.button("", cb)
	b.custom_minimum_size = BTN
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var ic := UI.icon(Assets.tex("ui/btn_%s.png" % id), BTN - Vector2(8, 10))
	ic.position = Vector2(4, 5)
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

## The status window's view markers: one dot per view, the shown one lit.
class _Dots extends Control:
	var on := 0
	func _draw() -> void:
		for i in 3:
			var c := Vector2(9 + i * 22, size.y * 0.5)
			draw_circle(c, 7.5, Color(0, 0, 0, 0.75))
			draw_circle(c, 6.0, UI.GOLD if i == on else Color(0.42, 0.34, 0.22))
			draw_arc(c, 7.0, 0, TAU, 20, UI.GOLD_DARK, 1.2, true)

## A scroll arrow's triangle.
class _Tri extends Control:
	var up := true
	var live := true
	func _draw() -> void:
		var c := size * 0.5
		var w := 11.0
		var hgt := 7.0
		var pts := PackedVector2Array([c + Vector2(-w, hgt), c + Vector2(w, hgt), c + Vector2(0, -hgt)]) if up else \
			PackedVector2Array([c + Vector2(-w, -hgt), c + Vector2(w, -hgt), c + Vector2(0, hgt)])
		draw_colored_polygon(pts, UI.GOLD if live else Color(0.38, 0.32, 0.24))

## The date view's calendar: seven day stones (the days gone dim, today gold) over four week bars.
class _Calendar extends Control:
	var day := 1
	func _draw() -> void:
		var dw := (size.x - 6 * 6) / 7.0
		var di := (day - 1) % 7
		for i in 7:
			var r := Rect2(Vector2(i * (dw + 6), 0), Vector2(dw, 30))
			draw_rect(r, UI.GOLD if i == di else (Color(0.42, 0.34, 0.22) if i < di else Color(0.12, 0.09, 0.06)))
			draw_rect(r, UI.GOLD_DARK, false, 1.5)
			draw_string(UI.font(), r.position + Vector2(0, 22), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, dw, 18,
				Color(0.1, 0.06, 0.03) if i == di else Color(0.85, 0.8, 0.68))
		var ww := (size.x - 3 * 6) / 4.0
		var wi := ((day - 1) / 7) % 4
		for i in 4:
			var r := Rect2(Vector2(i * (ww + 6), 42), Vector2(ww, 14))
			draw_rect(r, UI.GOLD if i == wi else (Color(0.42, 0.34, 0.22) if i < wi else Color(0.12, 0.09, 0.06)))
			draw_rect(r, UI.GOLD_DARK, false, 1.5)
