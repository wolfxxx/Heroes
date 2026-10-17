extends RefCounted
class_name SpellBook
## The hero's spellbook: an open leather book (assets/ui/spellbook.png, painted by tools/art/spellbook_paint.py)
## with school bookmark tabs on the right, six spells per page and page turning on the curled corners / mouse wheel.
##   var r = await SpellBook.open(self, hero, can_cast, detail).closed   ->  spell id, or "" when closed
## can_cast(spell) -> bool: whether the spell can be picked now; leave it empty to only read the book (adventure map).
## detail(spell) -> String: an extra hover line.

const SIZE := Vector2(1536, 1024)
# Inside the painted page borders (book texture pixels, measured from the painting).
const PAGES := [Rect2(182, 138, 478, 718), Rect2(794, 136, 490, 720)]
const TABS := ["all", "air", "fire", "water", "earth"]
const TAB_Y := [133, 291, 451, 611, 771]  # each tab is 130 tall; its visible part starts at TAB_X
const TAB_X := 1376.0
const CORNERS := [Rect2(100, 780, 160, 130), Rect2(1270, 790, 140, 120)]  # curled page corners: back, forward
const PER_PAGE := 6
const INK := Color(0.27, 0.15, 0.06)
const INK_RED := Color(0.5, 0.1, 0.04)
const SCHOOL := {"all": "All schools", "air": "Air magic", "fire": "Fire magic", "water": "Water magic", "earth": "Earth magic"}

static func open(owner: Node, hero: Dictionary, can_cast := Callable(), detail := Callable()) -> Modal:
	var m := Modal.custom(owner, "", SIZE.x)
	m.panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	m.panel.pivot_offset = SIZE * 0.5
	var b := _Book.new()
	b.m = m
	b.hero = hero
	b.can_cast = can_cast
	b.detail = detail
	m.body.add_child(b)
	b.build()
	m.set_meta("cancel", "")
	# a click outside the book closes it (the book itself stops its own clicks)
	m.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			m.close(""))
	Audio.sfx("page", -4)
	return m

static func ink(text: String, size: int, col := INK, title := false) -> Label:
	var l := UI.label(text, size, col, title)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

class _Book extends Control:
	var m: Modal
	var hero: Dictionary
	var can_cast: Callable
	var detail: Callable
	var school := "all"
	var spread := 0
	var _content: Control
	var _tabs: Array = []

	func build() -> void:
		custom_minimum_size = SpellBook.SIZE
		mouse_filter = MOUSE_FILTER_STOP
		var bg := TextureRect.new()
		bg.texture = Assets.tex("ui/spellbook.png")
		bg.size = SpellBook.SIZE
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(bg)
		for i in SpellBook.TABS.size():
			_add_tab(i)
		for i in 2:
			var c := Button.new()
			_plain(c)
			c.position = SpellBook.CORNERS[i].position
			c.size = SpellBook.CORNERS[i].size
			c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			c.pressed.connect(_turn.bind(-1 if i == 0 else 1))
			add_child(c)
		_content = Control.new()
		_content.mouse_filter = MOUSE_FILTER_IGNORE
		_content.size = SpellBook.SIZE
		add_child(_content)
		_refresh()

	## A tab: the painted tab cut out of the book texture, so it can be dimmed or lit with its own alpha.
	func _add_tab(i: int) -> void:
		var at := AtlasTexture.new()
		at.atlas = Assets.tex("ui/spellbook.png")
		at.region = Rect2(SpellBook.TAB_X, SpellBook.TAB_Y[i], SpellBook.SIZE.x - SpellBook.TAB_X, 130)
		var t := TextureButton.new()
		t.texture_normal = at
		t.position = at.region.position
		t.size = at.region.size
		t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sch: String = SpellBook.TABS[i]
		t.pressed.connect(func():
			if school != sch:
				school = sch
				spread = 0
				Audio.sfx("page", -6)
				_refresh())
		t.mouse_entered.connect(func(): _light_tabs(sch))
		t.mouse_exited.connect(func(): _light_tabs(""))
		var tip := func():
			var v := HoverInfo.box(SpellBook.SCHOOL[sch])
			HoverInfo.line(v, "%d known" % _spells(sch).size())
			return v
		HoverInfo.attach(t, tip, 0.3)
		add_child(t)
		_tabs.append(t)

	func _light_tabs(hover: String) -> void:
		for i in _tabs.size():
			var sch: String = SpellBook.TABS[i]
			_tabs[i].modulate = Color(1.12, 1.1, 1.05) if sch == school else (Color(0.85, 0.85, 0.85) if sch == hover else Color(0.55, 0.52, 0.5))

	func _spells(sch: String) -> Array:
		var r: Array = hero["spells"].filter(func(s): return sch == "all" or GameData.SPELLS[s]["school"] == sch)
		r.sort_custom(func(a, b):
			var la: int = GameData.SPELLS[a]["level"]
			var lb: int = GameData.SPELLS[b]["level"]
			return la < lb if la != lb else GameData.SPELLS[a]["name"] < GameData.SPELLS[b]["name"])
		return r

	func _spreads() -> int:
		return maxi(1, ceili(_spells(school).size() / float(2 * SpellBook.PER_PAGE)))

	func _turn(d: int) -> void:
		var s := clampi(spread + d, 0, _spreads() - 1)
		if s != spread:
			spread = s
			Audio.sfx("page", -6)
			_refresh()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			match e.button_index:
				MOUSE_BUTTON_WHEEL_DOWN:
					_turn(1)
				MOUSE_BUTTON_WHEEL_UP:
					_turn(-1)
				MOUSE_BUTTON_RIGHT:
					m.close("")
			accept_event()

	func _refresh() -> void:
		_light_tabs("")
		for c in _content.get_children():
			c.queue_free()
		var list := _spells(school)
		var p0: Rect2 = SpellBook.PAGES[0]
		var p1: Rect2 = SpellBook.PAGES[1]
		_text("%s's Spellbook" % hero["name"], Rect2(p0.position, Vector2(p0.size.x, 44)), 28, SpellBook.INK_RED, true)
		_text(SpellBook.SCHOOL[school], Rect2(p1.position, Vector2(p1.size.x, 44)), 28, SpellBook.INK_RED, true)
		_rule(p0)
		_rule(p1)
		_text("Spell points:  %d / %d" % [hero["mana"], GameState.max_mana(hero)], Rect2(p0.position.x, p0.end.y - 36, p0.size.x, 32), 21)
		var n := _spreads()
		_text("Page %d of %d" % [spread + 1, n] if n > 1 else "", Rect2(p1.position.x, p1.end.y - 36, p1.size.x, 32), 19)
		if list.is_empty():
			_text("No %s spells known." % ("" if school == "all" else school), Rect2(p0.position.x, 380, p0.size.x, 40), 22)
		for i in range(spread * 2 * SpellBook.PER_PAGE, mini(list.size(), (spread + 1) * 2 * SpellBook.PER_PAGE)):
			var k := i - spread * 2 * SpellBook.PER_PAGE
			var page: Rect2 = SpellBook.PAGES[k / SpellBook.PER_PAGE]
			var j := k % SpellBook.PER_PAGE
			var cw := page.size.x / 2.0
			var ch := (page.size.y - 96) / 3.0
			_entry(list[i], Rect2(page.position.x + (j % 2) * cw, page.position.y + 54 + (j / 2) * ch, cw, ch))
		for i in 2:  # the curled corners only respond where there is a page to turn to
			get_child(SpellBook.TABS.size() + 1 + i).visible = (spread > 0) if i == 0 else (spread < n - 1)

	func _text(t: String, r: Rect2, size: int, col := SpellBook.INK, title := false) -> void:
		var l := SpellBook.ink(t, size, col, title)
		l.position = r.position
		l.size = r.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_content.add_child(l)

	func _rule(page: Rect2) -> void:
		var r := ColorRect.new()
		r.color = Color(0.4, 0.25, 0.1, 0.35)
		r.position = Vector2(page.position.x + 60, page.position.y + 46)
		r.size = Vector2(page.size.x - 120, 2)
		r.mouse_filter = MOUSE_FILTER_IGNORE
		_content.add_child(r)

	func _entry(s: String, r: Rect2) -> void:
		var sp: Dictionary = GameData.SPELLS[s]
		var pick := can_cast.is_valid()
		var ok: bool = can_cast.call(s) if pick else true
		var b := Button.new()
		_plain(b)
		b.position = r.position
		b.size = r.size
		b.disabled = not ok
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ok and pick else Control.CURSOR_ARROW
		var frame := Panel.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color(0.1, 0.06, 0.03)
		fs.border_color = Color(0.36, 0.24, 0.1)
		fs.set_border_width_all(3)
		fs.set_corner_radius_all(3)
		fs.shadow_color = Color(0.2, 0.1, 0, 0.35)
		fs.shadow_size = 4
		frame.add_theme_stylebox_override("panel", fs)
		frame.size = Vector2(112, 112)
		frame.position = Vector2((r.size.x - 112) / 2.0, 4)
		frame.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(frame)
		var ic := TextureRect.new()
		ic.texture = Assets.spell_icon(s)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_SCALE
		ic.position = Vector2(3, 3)
		ic.size = Vector2(106, 106)
		ic.mouse_filter = MOUSE_FILTER_IGNORE
		frame.add_child(ic)
		var nm := SpellBook.ink(sp["name"], 23, SpellBook.INK, true)
		var info := SpellBook.ink("Level %d  ·  %d mana" % [sp["level"], sp["mana"]], 18)
		for l in [nm, info]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(r.size.x, 28)
			b.add_child(l)
		nm.position.y = 120
		info.position.y = 150
		if not ok:
			frame.modulate = Color(0.55, 0.52, 0.5, 0.85)
			nm.modulate = Color(1, 1, 1, 0.5)
			info.modulate = Color(1, 1, 1, 0.5)
		elif pick:
			b.mouse_entered.connect(func():
				nm.add_theme_color_override("font_color", SpellBook.INK_RED)
				fs.border_color = Color(0.85, 0.62, 0.2))
			b.mouse_exited.connect(func():
				nm.add_theme_color_override("font_color", SpellBook.INK)
				fs.border_color = Color(0.36, 0.24, 0.1))
			b.pressed.connect(func(): m.close(s))
		b.mouse_filter = MOUSE_FILTER_STOP
		var tip := func():
			var v := HoverInfo.box(sp["name"])
			HoverInfo.line(v, "Level %d %s spell  ·  %d mana" % [sp["level"], String(sp["school"]).capitalize(), sp["mana"]], UI.GOLD, 18)
			HoverInfo.line(v, sp["desc"])
			if detail.is_valid():
				var d: String = detail.call(s)
				if d != "":
					HoverInfo.line(v, d, Color(0.55, 0.95, 0.5), 18)
			if not ok and sp["mana"] > hero["mana"]:
				HoverInfo.line(v, "Not enough spell points.", Color(1, 0.45, 0.4), 18)
			return v
		HoverInfo.attach(b, tip, 0.3)
		_content.add_child(b)

	func _plain(b: Button) -> void:
		b.flat = true
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
