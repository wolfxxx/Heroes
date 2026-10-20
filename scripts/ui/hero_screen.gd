extends RefCounted
class_name HeroScreen
## The hero screen: portrait and primary skills, eight secondary-skill sockets and the army; the paper-doll with every
## classic artifact socket on the hero's body, the war machines and the spellbook down its sides, and a scrolling
## backpack under it. Click an artifact to take it off into the backpack, or to put it on from the backpack.
##   var r = await HeroScreen.open(owner, hero).closed    # "close" or "dismiss"

const SKILL_LEVEL := ["", "Basic", "Advanced", "Expert"]
const DOLL := Vector2(450, 600)
const SOCK := 58.0
## Artifact sockets on the paper-doll (fractions of the painting): over the body part they dress, the five misc
## sockets down the left edge (as the classic hero screen). [where, slot kind, which one of that kind]
const SOCKETS := {
	"head": [Vector2(0.5, 0.15), "head", 0], "cape": [Vector2(0.29, 0.25), "cape", 0], "neck": [Vector2(0.5, 0.28), "neck", 0],
	"torso": [Vector2(0.5, 0.41), "torso", 0], "weapon": [Vector2(0.27, 0.53), "weapon", 0],
	"shield": [Vector2(0.73, 0.53), "shield", 0], "ring": [Vector2(0.27, 0.69), "ring", 0],
	"ring2": [Vector2(0.73, 0.69), "ring", 1], "feet": [Vector2(0.5, 0.88), "feet", 0],
	"misc1": [Vector2(0.08, 0.1), "misc", 0], "misc2": [Vector2(0.08, 0.23), "misc", 1],
	"misc3": [Vector2(0.08, 0.36), "misc", 2], "misc4": [Vector2(0.08, 0.49), "misc", 3],
	"misc5": [Vector2(0.08, 0.62), "misc", 4]}
const SLOT_NAME := {"head": "Head", "cape": "Shoulders", "neck": "Neck", "torso": "Torso", "weapon": "Right hand",
	"shield": "Left hand", "ring": "Ring", "feet": "Feet", "misc": "Miscellaneous"}
## The war machines down the doll's right edge, the spellbook at its foot (as the classic hero screen).
const MACHINES := ["ballista", "ammo_cart", "first_aid_tent", "catapult"]
const BACKPACK := 5
const STAT_TIP := {"attack": "Attack: added to the Attack of every creature in the army.",
	"defense": "Defense: added to the Defense of every creature in the army.",
	"power": "Spell Power: how strong and how long-lasting the hero's spells are.",
	"knowledge": "Knowledge: 10 spell points per point."}

## The hero's morale out of battle: [value, explanation]. Leadership and artifacts, -1 for each extra faction in the
## army (undead are never affected, so an all-undead army reads as neutral).
static func _morale(h: Dictionary) -> Array:
	var lead := int(h["skills"].get("leadership", 0))
	var art := GameState.hero_stat(h, "morale")
	var factions := {}
	var living := false
	for sl in h["army"]:
		if sl != null and sl.get("count", 0) > 0:
			var c: Dictionary = GameData.CREATURES[sl["id"]]
			factions[c.get("faction", "")] = true
			living = living or not ("undead" in c["abilities"])
	var mixed := maxi(0, factions.size() - 1)
	var v := clampi(lead + art - mixed, -3, 3)
	var why := "Morale: good morale may give a stack an extra action (1 in 24 per point); bad morale may make it " \
		+ "freeze (1 in 12 per point).\nLeadership %+d, artifacts %+d" % [lead, art]
	if mixed > 0:
		why += ", mixed factions in the army %+d" % -mixed
	why += "."
	if not living and factions.size() > 0:
		return [0, why + "\nUndead are not affected by morale."]
	return [v, why]

static func open(owner: Node, h: Dictionary) -> Modal:
	var m := Modal.custom(owner, "", 1240)
	m.set_meta("bp", 0)  # (the backpack's scroll)
	_fill(m, owner, h)
	m.set_meta("default", "close")
	m.set_meta("cancel", "close")
	return m

## (Re)builds the whole screen: after an artifact moves, every number that depends on it shows afresh.
static func _fill(m: Modal, owner: Node, h: Dictionary) -> void:
	for c in m.body.get_children():
		m.body.remove_child(c)
		c.queue_free()
	var redo := func(): _fill.call_deferred(m, owner, h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	m.body.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	# portrait, name, class, specialty
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	left.add_child(top)
	var pf := _Socket.new()
	pf.custom_minimum_size = Vector2(150, 150)
	pf.tex = Assets.hero_portrait(h["id"])
	top.add_child(pf)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	top.add_child(info)
	info.add_child(UI.label(h["name"], 36, UI.GOLD, true))
	info.add_child(UI.label("Level %d %s" % [h["level"], h["class"]], 22))
	info.add_child(UI.label("Specialty: %s" % GameData.HEROES[h["id"]]["specialty"], 20, Color(0.85, 0.8, 0.68)))
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", 14)
	info.add_child(meters)
	var next_xp: int = GameData.XP_LEVELS[mini(h["level"], GameData.XP_LEVELS.size() - 1)]
	meters.add_child(_meter("Experience", "%d / %d" % [h["xp"], next_xp], clampf(float(h["xp"]) / maxf(1.0, next_xp), 0, 1), Color(0.85, 0.7, 0.3)))
	meters.add_child(_meter("Spell points", "%d / %d" % [h["mana"], GameState.max_mana(h)],
		clampf(float(h["mana"]) / maxf(1.0, GameState.max_mana(h)), 0, 1), Color(0.35, 0.55, 1.0)))
	meters.add_child(_meter("Movement", "%d / %d" % [h["movement"], h["max_movement"]],
		clampf(float(h["movement"]) / maxf(1.0, h["max_movement"]), 0, 1), Color(0.45, 0.8, 0.4)))

	# primary skills
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	left.add_child(stats)
	for s in ["attack", "defense", "power", "knowledge"]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.custom_minimum_size.x = 112
		var so := _Socket.new()
		so.custom_minimum_size = Vector2(76, 76)
		so.tex = Assets.tex("icons/stat_%s.png" % s)
		so.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(so)
		var nl := UI.label("Spell Power" if s == "power" else s.capitalize(), 18, UI.GOLD)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nl)
		var vl := UI.label(str(GameState.hero_stat(h, s)), 30, UI.TEXT, true)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(vl)
		var tip: String = STAT_TIP[s]
		HoverInfo.attach(v, func(): return tip)
		stats.add_child(v)
	# morale and luck, as in the classic hero screen: what they are now and why
	var mo := _morale(h)
	var lk := int(h["skills"].get("luck", 0)) + GameState.hero_stat(h, "luck")
	for e in [["Morale", mo[0], "skill_leadership", mo[1]], ["Luck", lk, "skill_luck",
			"Luck: a chance of double damage on each attack (1 in 24 per point).\nLuck skill %+d, artifacts %+d." % [
				int(h["skills"].get("luck", 0)), GameState.hero_stat(h, "luck")]]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.custom_minimum_size.x = 100
		var so := _Socket.new()
		so.custom_minimum_size = Vector2(76, 76)
		so.tex = Assets.tex("icons/%s.png" % e[2])
		so.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(so)
		var nl := UI.label(e[0], 18, UI.GOLD)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nl)
		var val: int = e[1]
		var vl := UI.label(("%+d" % val) if val != 0 else "0", 30,
			Color(0.6, 0.92, 0.5) if val > 0 else (Color(1, 0.55, 0.45) if val < 0 else UI.TEXT), true)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(vl)
		var tip: String = e[3]
		HoverInfo.attach(v, func(): return tip)
		stats.add_child(v)

	# secondary skills: 8 sockets in two columns, as in the classic hero screen
	left.add_child(UI.label("Secondary Skills", 24, UI.GOLD, true))
	var sk := GridContainer.new()
	sk.columns = 2
	sk.add_theme_constant_override("h_separation", 16)
	sk.add_theme_constant_override("v_separation", 8)
	left.add_child(sk)
	var ids: Array = h["skills"].keys().filter(func(k): return int(h["skills"][k]) > 0)
	for i in 8:
		sk.add_child(_skill_cell(ids[i] if i < ids.size() else "", int(h["skills"].get(ids[i], 0)) if i < ids.size() else 0))

	# the army
	left.add_child(UI.label("Army", 24, UI.GOLD, true))
	var strip := ArmyStrip.new()
	strip.bind(h["army"], {}, true)
	strip.tooltip_text = "Click a stack, then another slot, to move or swap it. Shift+click to split. Right click: details."
	left.add_child(strip)

	# the paper-doll (machines and spellbook on its edges), the backpack under it
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(_doll(owner, h, redo))
	right.add_child(_backpack(m, h, redo))
	right.add_child(_formation(h, redo))
	m.add_buttons([["Close", "close"], ["Dismiss Hero", "dismiss"]])

## A small labelled meter: title, value and a thin bar.
## A labelled meter: its name over the value in large figures, a bar under them (as the classic screen's boxes).
static func _meter(title: String, value: String, frac: float, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.custom_minimum_size.x = 170
	v.add_child(UI.label(title, 16, UI.GOLD))
	v.add_child(UI.label(value, 22))
	var bar := _Bar.new()
	bar.frac = frac
	bar.col = col
	bar.custom_minimum_size = Vector2(170, 11)
	v.add_child(bar)
	return v

static func _skill_cell(id: String, lvl: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size = Vector2(340, 76)
	var so := _Socket.new()
	so.custom_minimum_size = Vector2(72, 72)
	h.add_child(so)
	if id == "":
		so.empty = true
		return h
	so.tex = Assets.skill_icon(id)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.add_child(UI.label(SKILL_LEVEL[mini(3, lvl)], 19, UI.GOLD))
	v.add_child(UI.label(GameData.SKILLS[id]["name"], 23))
	h.add_child(v)
	var tip := "%s %s\n%s" % [SKILL_LEVEL[mini(3, lvl)], GameData.SKILLS[id]["name"], GameData.SKILLS[id]["desc"]]
	HoverInfo.attach(h, func(): return tip)
	return h

## The worn artifact in each doll socket (rings and misc fill their sockets in order).
static func _placed(h: Dictionary) -> Dictionary:
	var seen := {}
	var out := {}
	for a in h["artifacts"]:
		var kind: String = GameData.ARTIFACTS[a]["slot"]
		var k: int = seen.get(kind, 0)
		seen[kind] = k + 1
		for sl in SOCKETS:
			if SOCKETS[sl][1] == kind and SOCKETS[sl][2] == k:
				out[sl] = a
	return out

static func _artifact_tip(a: String, hint := "") -> String:
	var t := "%s\n%s" % [GameData.ARTIFACTS[a]["name"], GameData.ARTIFACTS[a]["desc"]]
	return t + ("\n" + hint if hint != "" else "")

## The painted figure with a socket on each body part, the misc sockets down its left edge, the war machines and the
## spellbook down its right.
static func _doll(owner: Node, h: Dictionary, redo: Callable) -> Control:
	var doll := TextureRect.new()
	doll.texture = Assets.tex("ui/paperdoll.png")
	doll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	doll.custom_minimum_size = DOLL
	doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # (the sockets are placed on the painting at this size)
	var worn := _placed(h)
	for sl in SOCKETS:
		var so := _sock(doll, SOCKETS[sl][0])
		var kind: String = SOCKETS[sl][1]
		so.glass = true
		if worn.has(sl):
			var a: String = worn[sl]
			so.tex = Assets.artifact_icon(a)
			so.inner = true
			var tip := _artifact_tip(a, "Click: take it off into the backpack.")
			HoverInfo.attach(so, func(): return tip)
			so.pressed = func():
				GameState.swap_artifact(h, a, true)
				Audio.sfx("click")
				redo.call()
		else:
			so.empty = true
			var tip := "%s: empty" % SLOT_NAME[kind]
			HoverInfo.attach(so, func(): return tip)
	var have: Array = h.get("machines", [])
	for i in MACHINES.size():
		var id: String = MACHINES[i]
		var so := _sock(doll, Vector2(0.92, 0.1 + 0.13 * i))
		so.empty = not (id in have or id == "catapult")
		so.tex = Assets.creature_portrait(id)
		var c: Dictionary = GameData.CREATURES[id]
		var tip: String = "%s%s\n%s" % [c["name"], "" if not so.empty else " (not owned: buy one at a Blacksmith)",
			GameData.MACHINE_TEXT[id]]
		HoverInfo.attach(so, func(): return tip)
	var bk := _sock(doll, Vector2(0.92, 0.88))
	bk.tex = Assets.tex("icons/stat_knowledge.png")
	var n: int = h["spells"].size()
	var btip := ("Spellbook: %d spell%s known. Click to open." % [n, "" if n == 1 else "s"]) if n > 0 else "Spellbook: no spells known."
	HoverInfo.attach(bk, func(): return btip)
	if n > 0:
		bk.pressed = func(): SpellBook.open(owner, h)
	return doll

static func _sock(doll: Control, at: Vector2) -> _Socket:
	var so := _Socket.new()
	so.size = Vector2(SOCK, SOCK)
	so.position = at * DOLL - so.size * 0.5
	doll.add_child(so)
	return so

## The backpack: five sockets with arrows to scroll through the rest, as the classic hero screen.
static func _backpack(m: Modal, h: Dictionary, redo: Callable) -> Control:
	var pack: Array = h.get("backpack", [])
	var off: int = clampi(int(m.get_meta("bp", 0)), 0, maxi(0, pack.size() - BACKPACK))
	m.set_meta("bp", off)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UI.label("Backpack", 18, UI.GOLD)
	l.custom_minimum_size.x = 84
	row.add_child(l)
	var arrow := func(d: int) -> Button:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, SOCK)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = off + d < 0 or off + d > pack.size() - BACKPACK
		b.pressed.connect(func():
			m.set_meta("bp", off + d)
			Audio.sfx("click", -6)
			redo.call())
		var t := _Arrow.new()
		t.dir = d
		t.live = not b.disabled
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
		return b
	row.add_child(arrow.call(-1))
	for i in BACKPACK:
		var so := _Socket.new()
		so.custom_minimum_size = Vector2(SOCK, SOCK)
		so.empty = off + i >= pack.size()
		if not so.empty:
			var a: String = pack[off + i]
			so.tex = Assets.artifact_icon(a)
			so.inner = true
			var hint := "Click: put it on." if GameState.can_wear(h, a) else "Click: put it on in place of the one worn there."
			var tip := _artifact_tip(a, hint)
			HoverInfo.attach(so, func(): return tip)
			so.pressed = func():
				GameState.swap_artifact(h, a, false)
				Audio.sfx("click")
				redo.call()
		row.add_child(so)
	row.add_child(arrow.call(1))
	var out := VBoxContainer.new()
	out.add_theme_constant_override("separation", 2)
	out.add_child(row)
	if pack.size() > BACKPACK:  # (how far along the scroll is)
		var cnt := UI.label("%d-%d of %d" % [off + 1, off + BACKPACK, pack.size()], 16, Color(0.85, 0.8, 0.68))
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		out.add_child(cnt)
	return out

## The army's battle formation (as the classic hero screen): spread along the whole edge, or grouped in the middle.
static func _formation(h: Dictionary, redo: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UI.label("Formation", 18, UI.GOLD)
	l.custom_minimum_size.x = 84
	row.add_child(l)
	var cur: String = h.get("formation", "spread")
	for e in [["spread", "Spread", "The stacks take the field spread along the whole edge."],
			["grouped", "Grouped", "The stacks take the field side by side in the middle of the edge."]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = cur == e[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 50)
		b.text = e[1]
		b.add_theme_font_size_override("font_size", 19)
		var on := UI.selected_plate(4)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		var ink := Color(1.0, 0.88, 0.55)  # (bright on the dark selected plate)
		b.add_theme_color_override("font_pressed_color", ink)
		b.add_theme_color_override("font_hover_pressed_color", ink)
		var ic := _Formation.new()
		ic.grouped = e[0] == "grouped"
		ic.col = ink if cur == e[0] else Color(0.9, 0.78, 0.5)
		ic.position = Vector2(10, 9)
		ic.size = Vector2(22, 32)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var tip: String = e[2]
		HoverInfo.attach(b, func(): return tip)
		var id: String = e[0]
		b.pressed.connect(func():
			h["formation"] = id
			Audio.sfx("click", -6)
			redo.call())
		row.add_child(b)
	return row

## A recessed square socket: dark well, bevelled rim, thin gold frame; holds an icon (or nothing).
class _Socket extends Control:
	var tex: Texture2D
	var empty := false
	var glass := false  # on the paper-doll: a translucent well, so the figure shows through when empty
	var pressed := Callable()  # (a left click on it)
	var inner := false  # an artifact icon: drawn without its own frame, filling the socket
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
	func _gui_input(e: InputEvent) -> void:
		if pressed.is_valid() and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.call()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.02, 0.025, (0.22 if glass else 0.4) if empty else 0.92))
		if tex and not empty and inner:
			var ts := tex.get_size()
			draw_texture_rect_region(tex, r.grow(-3), Rect2(ts * 0.07, ts * 0.86))
		elif tex and not empty:
			draw_texture_rect(tex, r.grow(-5), false)
		elif tex:  # a machine not owned: its picture greyed out in the empty socket
			draw_texture_rect(tex, r.grow(-5), false, Color(0.3, 0.29, 0.28, 0.75))
		# bevel: shadowed top-left, lit bottom-right
		draw_line(Vector2(1, 1), Vector2(size.x - 1, 1), Color(0, 0, 0, 0.8), 3)
		draw_line(Vector2(1, 1), Vector2(1, size.y - 1), Color(0, 0, 0, 0.8), 3)
		draw_line(Vector2(2, size.y - 1), Vector2(size.x - 1, size.y - 1), Color(1, 0.9, 0.7, 0.18), 2)
		draw_line(Vector2(size.x - 1, 2), Vector2(size.x - 1, size.y - 1), Color(1, 0.9, 0.7, 0.18), 2)
		var lit := pressed.is_valid() and get_global_rect().has_point(get_global_mouse_position())
		draw_rect(r.grow(1), Color(1, 0.9, 0.5) if lit else (Color(0.66, 0.5, 0.25) if empty else Color(0.86, 0.68, 0.32)),
			false, 3.0 if lit else 2.0)

class _Bar extends Control:
	var frac := 0.0
	var col := Color.WHITE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2)), col)
		draw_rect(Rect2(Vector2.ZERO, size), UI.GOLD_DARK, false, 1.0)

## A backpack scroll arrow: a gold triangle, dimmed when there is nothing more that way.
class _Arrow extends Control:
	var dir := 1
	var live := true
	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array([c + Vector2(-6 * dir, -11), c + Vector2(-6 * dir, 11), c + Vector2(7 * dir, 0)])
		draw_colored_polygon(pts, UI.GOLD if live else Color(0.38, 0.32, 0.24))

## The formation buttons' little picture: three stacks spread apart, or close together.
class _Formation extends Control:
	var grouped := false
	var col := Color.WHITE
	func _draw() -> void:
		var gap := 4.0 if grouped else 9.0
		var y0 := size.y * 0.5 - gap - 4
		for i in 3:
			draw_rect(Rect2(Vector2(4, y0 + i * (gap + 4) - 4), Vector2(12, 7)), col)
