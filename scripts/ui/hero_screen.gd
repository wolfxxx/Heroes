extends RefCounted
class_name HeroScreen
## The hero screen: portrait and primary skills, eight secondary-skill sockets, the paper-doll with the artifact
## sockets on the hero's body, the spellbook and the army.
##   var r = await HeroScreen.open(owner, hero).closed    # "close" or "dismiss"

const SKILL_LEVEL := ["", "Basic", "Advanced", "Expert"]
const DOLL := Vector2(390, 520)
## Artifact sockets on the paper-doll (fractions of the painting): over the body part they dress.
const SOCKETS := {"head": Vector2(0.5, 0.19), "misc": Vector2(0.5, 0.385), "weapon": Vector2(0.235, 0.555),
	"shield": Vector2(0.765, 0.555), "ring": Vector2(0.765, 0.72), "ring2": Vector2(0.235, 0.72), "feet": Vector2(0.5, 0.875)}
const SOCKET_NAME := {"head": "Head", "misc": "Charm", "weapon": "Weapon", "shield": "Shield", "ring": "Ring", "ring2": "Ring", "feet": "Feet"}
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

	# the paper-doll, and the spellbook under it
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(_doll(h))
	right.add_child(_backpack(h))
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

	m.body.add_child(UI.label("Army", 22, UI.GOLD, true))
	var strip := ArmyStrip.new()
	strip.bind(h["army"], {}, true)
	strip.tooltip_text = "Click a stack, then another slot, to move or swap it. Shift+click to split. Right click: details."
	m.body.add_child(strip)
	m.add_buttons([["Close", "close"], ["Dismiss Hero", "dismiss"]])
	m.set_meta("default", "close")
	m.set_meta("cancel", "close")
	return m

## A small labelled meter: title, value and a thin bar.
static func _meter(title: String, value: String, frac: float, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.custom_minimum_size.x = 170
	var t := HBoxContainer.new()
	t.add_child(UI.label(title, 18, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_child(sp)
	t.add_child(UI.label(value, 18))
	v.add_child(t)
	var bar := _Bar.new()
	bar.frac = frac
	bar.col = col
	bar.custom_minimum_size = Vector2(170, 9)
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
	v.add_child(UI.label(SKILL_LEVEL[mini(3, lvl)], 19, UI.GOLD))
	v.add_child(UI.label(GameData.SKILLS[id]["name"], 23))
	h.add_child(v)
	var tip := "%s %s\n%s" % [SKILL_LEVEL[mini(3, lvl)], GameData.SKILLS[id]["name"], GameData.SKILLS[id]["desc"]]
	HoverInfo.attach(h, func(): return tip)
	return h

## Which socket each artifact sits in; the rest go into the backpack.
static func _placed(h: Dictionary) -> Array:
	var by_slot := {}
	var extra := []
	for a in h["artifacts"]:
		var sl: String = GameData.ARTIFACTS[a]["slot"]
		if by_slot.has(sl) and sl == "ring" and not by_slot.has("ring2"):
			sl = "ring2"
		if by_slot.has(sl):
			extra.append(a)
		else:
			by_slot[sl] = a
	return [by_slot, extra]

static func _artifact_tip(a: String) -> String:
	return "%s
%s" % [GameData.ARTIFACTS[a]["name"], GameData.ARTIFACTS[a]["desc"]]

## The painted figure with a socket on each body part.
static func _doll(h: Dictionary) -> Control:
	var doll := TextureRect.new()
	doll.texture = Assets.tex("ui/paperdoll.png")
	doll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	doll.custom_minimum_size = DOLL
	var by_slot: Dictionary = _placed(h)[0]
	for sl in SOCKETS:
		var so := _Socket.new()
		so.size = Vector2(68, 68)
		so.position = SOCKETS[sl] * DOLL - so.size * 0.5
		so.empty = not by_slot.has(sl)
		so.glass = true
		var tip: String = _artifact_tip(by_slot[sl]) if by_slot.has(sl) else "%s: empty" % SOCKET_NAME[sl]
		if by_slot.has(sl):
			so.tex = Assets.artifact_icon(by_slot[sl])
		HoverInfo.attach(so, func(): return tip)
		doll.add_child(so)
	return doll

## A row of backpack sockets under the figure, for artifacts with no free body slot.
static func _backpack(h: Dictionary) -> Control:
	var extra: Array = _placed(h)[1]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UI.label("Backpack", 18, UI.GOLD)
	l.custom_minimum_size.x = 92
	row.add_child(l)
	for i in maxi(BACKPACK, extra.size()):
		var so := _Socket.new()
		so.custom_minimum_size = Vector2(54, 54)
		so.empty = i >= extra.size()
		if not so.empty:
			so.tex = Assets.artifact_icon(extra[i])
			var tip := _artifact_tip(extra[i])
			HoverInfo.attach(so, func(): return tip)
		row.add_child(so)
	return row

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
		draw_rect(r.grow(1), Color(0.66, 0.5, 0.25) if empty else Color(0.86, 0.68, 0.32), false, 2.0)

class _Bar extends Control:
	var frac := 0.0
	var col := Color.WHITE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2)), col)
