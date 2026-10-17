extends RefCounted
class_name HeroScreen
## The hero screen: portrait and primary skills, eight secondary-skill sockets, the paper-doll with the artifact
## sockets on the hero's body, the spellbook and the army.
##   var r = await HeroScreen.open(owner, hero).closed    # "close" or "dismiss"

const SKILL_LEVEL := ["", "Basic", "Advanced", "Expert"]
const DOLL := Vector2(390, 520)
## Artifact sockets on the paper-doll (fractions of the painting): over the body part they dress.
const SOCKETS := {"head": Vector2(0.5, 0.19), "misc": Vector2(0.5, 0.385), "weapon": Vector2(0.235, 0.555),
	"shield": Vector2(0.765, 0.555), "ring": Vector2(0.765, 0.72), "feet": Vector2(0.5, 0.875)}
const STAT_TIP := {"attack": "Attack: added to the Attack of every creature in the army.",
	"defense": "Defense: added to the Defense of every creature in the army.",
	"power": "Spell Power: how strong and how long-lasting the hero's spells are.",
	"knowledge": "Knowledge: 10 spell points per point."}

static func open(owner: Node, h: Dictionary) -> Modal:
	var m := Modal.custom(owner, "", 1240)
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
		v.custom_minimum_size.x = 150
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

	# the paper-doll, and the spellbook under it
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(_doll(h))
	var sb := HBoxContainer.new()
	sb.add_theme_constant_override("separation", 14)
	sb.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(sb)
	var n: int = h["spells"].size()
	sb.add_child(UI.label(("%d spell%s known" % [n, "" if n == 1 else "s"]) if n > 0 else "No spells known", 19, Color(0.85, 0.8, 0.68)))
	if n > 0:
		var bk := UI.button("Spellbook", func(): SpellBook.open(owner, h), 20)
		bk.custom_minimum_size = Vector2(160, 46)
		sb.add_child(bk)

	m.body.add_child(UI.label("Army  (click to move, shift+click to split, right click for info)", 20, UI.GOLD))
	var strip := ArmyStrip.new()
	strip.bind(h["army"], {}, true)
	m.body.add_child(strip)
	m.add_buttons([["Close", "close"], ["Dismiss Hero", "dismiss"]])
	m.set_meta("default", "close")
	m.set_meta("cancel", "close")
	return m

## A small labelled meter: title, value and a thin bar.
static func _meter(title: String, value: String, frac: float, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.custom_minimum_size.x = 150
	var t := HBoxContainer.new()
	t.add_child(UI.label(title, 16, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_child(sp)
	t.add_child(UI.label(value, 16))
	v.add_child(t)
	var bar := _Bar.new()
	bar.frac = frac
	bar.col = col
	bar.custom_minimum_size = Vector2(150, 8)
	v.add_child(bar)
	return v

static func _skill_cell(id: String, lvl: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size = Vector2(370, 76)
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
	v.add_child(UI.label(SKILL_LEVEL[mini(3, lvl)], 17, UI.GOLD))
	v.add_child(UI.label(GameData.SKILLS[id]["name"], 21))
	h.add_child(v)
	var tip := "%s %s\n%s" % [SKILL_LEVEL[mini(3, lvl)], GameData.SKILLS[id]["name"], GameData.SKILLS[id]["desc"]]
	HoverInfo.attach(h, func(): return tip)
	return h

## The painted figure with a socket on each body part; a second artifact for a taken slot goes below the figure.
static func _doll(h: Dictionary) -> Control:
	var doll := TextureRect.new()
	doll.texture = Assets.tex("ui/paperdoll.png")
	doll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	doll.custom_minimum_size = DOLL
	var by_slot := {}
	var extra := []
	for a in h["artifacts"]:
		var sl: String = GameData.ARTIFACTS[a]["slot"]
		if by_slot.has(sl):
			extra.append(a)
		else:
			by_slot[sl] = a
	for sl in SOCKETS:
		var so := _Socket.new()
		so.size = Vector2(68, 68)
		so.position = SOCKETS[sl] * DOLL - so.size * 0.5
		so.empty = not by_slot.has(sl)
		so.glass = true
		var tip := ""
		if by_slot.has(sl):
			var a: String = by_slot[sl]
			so.tex = Assets.artifact_icon(a)
			tip = "%s\n%s" % [GameData.ARTIFACTS[a]["name"], GameData.ARTIFACTS[a]["desc"]]
		else:
			tip = "%s: empty" % sl.capitalize()
		HoverInfo.attach(so, func(): return tip)
		doll.add_child(so)
	for i in extra.size():
		var a: String = extra[i]
		var so := _Socket.new()
		so.size = Vector2(56, 56)
		so.position = Vector2(14 + i * 62, DOLL.y - 70)
		so.tex = Assets.artifact_icon(a)
		var tip := "%s\n%s" % [GameData.ARTIFACTS[a]["name"], GameData.ARTIFACTS[a]["desc"]]
		HoverInfo.attach(so, func(): return tip)
		doll.add_child(so)
	return doll

## A recessed square socket: dark well, bevelled rim, thin gold frame; holds an icon (or nothing).
class _Socket extends Control:
	var tex: Texture2D
	var empty := false
	var glass := false  # on the paper-doll: a translucent well, so the figure shows through when empty
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.02, 0.025, (0.22 if glass else 0.4) if empty else 0.92))
		if tex and not empty:
			draw_texture_rect(tex, r.grow(-5), false)
		# bevel: shadowed top-left, lit bottom-right
		draw_line(Vector2(1, 1), Vector2(size.x - 1, 1), Color(0, 0, 0, 0.8), 3)
		draw_line(Vector2(1, 1), Vector2(1, size.y - 1), Color(0, 0, 0, 0.8), 3)
		draw_line(Vector2(2, size.y - 1), Vector2(size.x - 1, size.y - 1), Color(1, 0.9, 0.7, 0.18), 2)
		draw_line(Vector2(size.x - 1, 2), Vector2(size.x - 1, size.y - 1), Color(1, 0.9, 0.7, 0.18), 2)
		draw_rect(r.grow(1), UI.GOLD_DARK if empty else Color(0.82, 0.64, 0.3), false, 2.0)

class _Bar extends Control:
	var frac := 0.0
	var col := Color.WHITE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2)), col)
