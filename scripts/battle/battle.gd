extends Node2D
## Battle scene: renders the hex field, animates BattleLogic events, handles player input and AI turns.

const HEX_W := 96.0
const ROW_STEP := 68.0
const X0 := 264.0
const Y0 := 272.0
const TIER_H := [0, 120.0, 128.0, 150.0, 150.0, 160.0, 185.0, 215.0]
## On-screen height of the solid figure per tier (sizes.json, without the cast shadow): higher tiers clearly dominate.
const FIG_H := [0, 132.0, 138.0, 150.0, 158.0, 165.0, 220.0, 240.0]
const FIG_MAX_W := 2.6  # widest solid figure in hexes (1-hex units; 2-hex units get one more hex)

static var _sizes = null

## Solid figure size in texture pixels (assets/creatures/sizes.json, written by tools/art/sprite_sizes.py).
static func fig_size(id: String) -> Vector2:
	if _sizes == null:
		_sizes = {}
		var p := Assets.path("creatures/sizes.json")
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(d) == TYPE_DICTIONARY:
				_sizes = d
	var v = _sizes.get(id + ".png")
	return Vector2(v[0], v[1]) if v != null else Vector2.ZERO

## Flip a unit sprite horizontally while keeping its feet anchored.
static func _set_flip(s: Sprite2D, flip: bool) -> void:
	s.flip_h = flip
	if s.has_meta("anchor_x"):
		var ax: float = s.get_meta("anchor_x")
		s.offset.x = -ax if flip else ax

var L: BattleLogic
var setup_d: Dictionary
var units := {}            # uid -> Node2D
var _field: Node2D
var _grid: _Grid
var _sorted: Node2D
var _corpses: Node2D
var _fx: Node2D
var ui: CanvasLayer
var _queue_box: HBoxContainer
var _log: Label
var _status: Label
var _btns := {}
var _busy := false
var _auto := false
var _spell := ""
var _reach := {}
var _hover := Vector2i(-1, -1)
var _hover_action := {}
var _retreated := -1
var _ended := false
var _mouse := Vector2.ZERO

func _ready() -> void:
	setup_d = GameState.pending_battle
	if setup_d.is_empty():
		setup_d = _demo_setup()
	L = BattleLogic.new()
	L.setup(setup_d)
	_build_scene()
	_build_ui()
	Audio.music("battle")
	Audio.sfx("battle_start", -2)
	await get_tree().create_timer(0.6).timeout
	_next()

func _demo_setup() -> Dictionary:
	var a := GameState.make_hero("sir_aldric", 0)
	var d := GameState.make_hero("lord_morthis", 1)
	for h in [a, d]:
		var c: Array = GameData.FACTIONS[h["faction"]]["creatures"]
		for i in 7:
			h["army"][i] = {"id": c[i], "count": [30, 18, 9, 6, 4, 2, 1][i]}
		h["spells"] = ["magic_arrow", "bless", "lightning_bolt", "fireball", "haste", "cure"]
		h["power"] = 3
		h["knowledge"] = 4
		h["mana"] = 40
	return {"attacker_army": a["army"], "defender_army": d["army"], "attacker_hero": a, "defender_hero": d,
		"terrain": "grass", "attacker_player": 0, "defender_player": 1, "attacker_ai": false, "defender_ai": true,
		"context": {"type": "demo"}, "seed": 7}

# ---------------------------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------------------------
static func hex_pos(h: Vector2i) -> Vector2:
	return Vector2(X0 + h.x * HEX_W + (HEX_W * 0.5 if h.y % 2 == 1 else 0.0), Y0 + h.y * ROW_STEP)

static func hex_poly(c: Vector2, shrink := 0.0) -> PackedVector2Array:
	var r := HEX_W / sqrt(3.0) - shrink
	var sq := ROW_STEP / (1.5 * HEX_W / sqrt(3.0))
	var pts := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60.0 * k + 30.0)
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * sq))
	return pts

func pos_to_hex(p: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for y in BattleLogic.ROWS:
		for x in BattleLogic.COLS:
			var c := hex_pos(Vector2i(x, y))
			var d := Vector2(p.x - c.x, (p.y - c.y) * 1.25).length()
			if d < bd:
				bd = d
				best = Vector2i(x, y)
	return best if bd < HEX_W * 0.6 else Vector2i(-1, -1)

# ---------------------------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------------------------
func _build_scene() -> void:
	var bgp := "battle/bg_%s.png" % L.terrain
	if Assets.has(bgp):
		var bg := Sprite2D.new()
		bg.texture = Assets.tex(bgp)
		bg.centered = false
		bg.scale = Vector2(1920.0 / bg.texture.get_width(), 1080.0 / bg.texture.get_height())
		add_child(bg)
	else:
		var bg := _Fallback.new()
		bg.terrain = L.terrain
		add_child(bg)
	_field = Node2D.new()
	add_child(_field)
	_grid = _Grid.new()
	_grid.b = self
	_field.add_child(_grid)
	_corpses = Node2D.new()  # dead stacks: above the ground and grid, below everything standing
	_corpses.y_sort_enabled = true
	_field.add_child(_corpses)
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	_field.add_child(_sorted)
	_fx = Node2D.new()
	_fx.z_index = 20
	_field.add_child(_fx)
	for h in L.obstacles:
		var s := Sprite2D.new()
		s.texture = Assets.tex("battle/obstacle_%d.png" % L.obstacles[h], Vector2i(96, 72))
		var sc := 120.0 / s.texture.get_width()
		s.scale = Vector2(sc, sc)
		s.offset = Vector2(0, -s.texture.get_height() * 0.5)
		s.position = hex_pos(h) + Vector2(0, 22)
		_sorted.add_child(s)
	for st in L.stacks:
		_make_unit(st)
	for side in 2:
		var hh = L.heroes[side]
		if hh == null:
			continue
		var s := Sprite2D.new()
		s.texture = Assets.tex("heroes/battle_%s.png" % hh["faction"], Vector2i(200, 200))
		var sc := 230.0 / s.texture.get_height()
		s.scale = Vector2(sc, sc)
		s.flip_h = side == 1
		s.position = Vector2(110 if side == 0 else 1810, 175)
		add_child(s)
		var nl := UI.label(hh["name"], 20, UI.GOLD)
		nl.position = Vector2(10 if side == 0 else 1710, 292)
		nl.size = Vector2(200, 30)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(nl)

func _make_unit(st: Dictionary) -> void:
	var c: Dictionary = GameData.CREATURES[st["id"]]
	var n := Node2D.new()
	n.position = hex_pos(st["hex"]) + Vector2(0, 24)
	var shadow := _Shadow.new()
	shadow.big = "two_hex" in c["abilities"]
	shadow.name = "Shadow"
	n.add_child(shadow)
	var s := Sprite2D.new()
	s.name = "Sprite"
	s.texture = Assets.creature(st["id"])
	var anc := Assets.anchor("creatures/%s.png" % st["id"])
	if anc.x >= 0.0:
		# Blender renders: fixed world scale, anchored at the feet (flip mirrors the anchor).
		s.centered = true
		var tsz := Vector2(s.texture.get_size())
		# size by tier on the solid figure, so a dragon towers over a pikeman; cap very wide figures (wings)
		var fig := fig_size(st["id"])
		var sc := 0.5
		if fig.y > 0:
			var max_w := HEX_W * (FIG_MAX_W + (1.0 if "two_hex" in c["abilities"] else 0.0))
			sc = minf(FIG_H[c["tier"]] / fig.y, max_w / fig.x)
			if "two_hex" in c["abilities"]:  # long lances / necks: a 2-hex unit should still span about two hexes
				sc = clampf(2.0 * HEX_W / fig.x, sc, 1.35 * FIG_H[c["tier"]] / fig.y)
		s.scale = Vector2.ONE * sc
		s.offset = (Vector2(0.5, 0.5) - anc) * tsz
		s.set_meta("anchor_x", (0.5 - anc.x) * tsz.x)
		n.set_meta("top", fig.y * sc if fig.y > 0 else TIER_H[c["tier"]])
	else:
		var h: float = TIER_H[c["tier"]]
		var sc := h / s.texture.get_height()
		s.scale = Vector2(sc, sc)
		s.offset = Vector2(0, -s.texture.get_height() * 0.5)
		n.set_meta("top", h)
	_set_flip(s, st["side"] == 1)
	MapView.outline(s, 1.2)
	if "two_hex" in c["abilities"]:
		s.position.x = -26 if st["side"] == 0 else 26
	n.add_child(s)
	var badge := _Badge.new()
	badge.name = "Badge"
	badge.st = st
	badge.position = Vector2(28, 14)
	badge.z_index = 5
	n.add_child(badge)
	_sorted.add_child(n)
	units[st["uid"]] = n
	# idle breathing
	var tw := s.create_tween().set_loops()
	var base := s.scale
	tw.tween_property(s, "scale", base * Vector2(1.0, 1.025), 0.9 + randf() * 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "scale", base, 0.9 + randf() * 0.4).set_trans(Tween.TRANS_SINE)
	n.set_meta("breath", tw)
	n.set_meta("base_scale", base)

func _unit(st: Dictionary) -> Node2D:
	return units.get(st["uid"])

## Height of the unit's figure on screen (for text and projectiles above it).
func _top(st: Dictionary) -> float:
	return _unit(st).get_meta("top", 150.0)

## Swap a unit to one of its painted poses ("attack", "hit", "dead"; "" = idle), keeping its feet on the hex.
## Poses come from tools/art/pose_paint.py; units without one simply keep their idle sprite.
## With hold > 0 the unit returns to idle afterwards, unless a newer pose (e.g. death) replaced it meanwhile.
func _pose(st: Dictionary, pose: String, hold := 0.0) -> bool:
	var n := _unit(st)
	if n == null:
		return false
	var rel := "creatures/%s.png" % st["id"] if pose == "" else "creatures/%s_%s.png" % [st["id"], pose]
	if not Assets.has(rel) or Assets.anchor(rel).x < 0.0:
		return false
	var s: Sprite2D = n.get_node("Sprite")
	var anc := Assets.anchor(rel)
	s.texture = Assets.tex(rel)
	var tsz := Vector2(s.texture.get_size())
	s.offset = (Vector2(0.5, 0.5) - anc) * tsz
	s.set_meta("anchor_x", (0.5 - anc.x) * tsz.x)
	_set_flip(s, s.flip_h)
	var token: int = n.get_meta("pose_token", 0) + 1
	n.set_meta("pose_token", token)
	n.set_meta("pose", pose)
	if hold > 0.0:
		get_tree().create_timer(hold).timeout.connect(func():
			if is_instance_valid(n) and n.get_meta("pose_token", 0) == token and st.get("alive", false):
				_pose(st, ""))
	return true

# ---------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var bar := Panel.new()
	bar.position = Vector2(0, 1012)
	bar.size = Vector2(1920, 68)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.04, 0.94)
	st.border_color = UI.GOLD_DARK
	st.border_width_top = 2
	bar.add_theme_stylebox_override("panel", st)
	root.add_child(bar)
	var left := HBoxContainer.new()
	left.position = Vector2(10, 1018)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	var right := HBoxContainer.new()
	right.position = Vector2(1460, 1018)
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	for e in [["Retreat", _on_retreat, left], ["Auto: Off", _on_auto, left], ["Spells", _on_spells, right], ["Wait", _on_wait, right], ["Defend", _on_defend, right]]:
		var b := UI.button(e[0], e[1], 21)
		b.custom_minimum_size = Vector2(140, 56)
		b.focus_mode = Control.FOCUS_NONE
		e[2].add_child(b)
		_btns[e[0]] = b
	_btns["Spells"].tooltip_text = "Cast a spell (S)"
	_btns["Wait"].tooltip_text = "Wait (W)"
	_btns["Defend"].tooltip_text = "Defend (D / Space)"
	_btns["Auto: Off"].tooltip_text = "Auto combat (A)"

	_log = UI.label("", 19)
	_log.position = Vector2(320, 1016)
	_log.size = Vector2(1120, 60)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_log)

	_status = UI.label("", 22, UI.GOLD)
	_status.position = Vector2(0, 966)
	_status.size = Vector2(1920, 36)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status)

	var qc := CenterContainer.new()
	qc.position = Vector2(0, 8)
	qc.size = Vector2(1920, 116)
	qc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(qc)
	var qp := PanelContainer.new()
	qc.add_child(qp)
	_queue_box = HBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 4)
	qp.add_child(_queue_box)

func _refresh_queue() -> void:
	for c in _queue_box.get_children():
		c.queue_free()
	var up := L.upcoming(14)
	for i in up.size():
		var s: Dictionary = up[i]
		var q := _QueueIcon.new()
		q.st = s
		q.first = i == 0
		q.custom_minimum_size = Vector2(92 if i == 0 else 80, 92 if i == 0 else 80)
		_queue_box.add_child(q)

func _set_log(t: String) -> void:
	_log.text = t

func _refresh_buttons(human_turn: bool) -> void:
	var cur = L.current()
	var side: int = cur["side"] if cur else 0
	_btns["Wait"].disabled = not human_turn or cur == null or cur["waited"]
	_btns["Defend"].disabled = not human_turn
	_btns["Spells"].disabled = not human_turn or not L.can_cast(side)
	_btns["Retreat"].disabled = not human_turn or L.heroes[side] == null
	_btns["Auto: Off"].text = "Auto: On" if _auto else "Auto: Off"

# ---------------------------------------------------------------------------------------------
# Turn flow
# ---------------------------------------------------------------------------------------------
func _human_controls(side: int) -> bool:
	return not L.ai_side[side] and not _auto

func _next() -> void:
	if _ended:
		return
	var win := L.is_over()
	if win >= 0:
		_end_battle(win)
		return
	var s = L.current()
	if s == null:
		_end_battle(L.is_over())
		return
	_refresh_queue()
	_grid.active = s
	for k in units:
		units[k].get_node("Shadow").active = k == s["uid"]
		var m: ShaderMaterial = units[k].get_node("Sprite").material
		if m:  # the active unit gets a thick gold outline instead of the ink one
			m.set_shader_parameter("ink", Color(1, 0.82, 0.25, 1) if k == s["uid"] else Color(0.09, 0.06, 0.03, 0.95))
			m.set_shader_parameter("width", 3.0 if k == s["uid"] else 1.2)
	if L.check_fear(s):
		_set_log("%s freeze in fear!" % L._name(s))
		_float_text(_unit(s).position + Vector2(0, -_top(s) - 10), "Fear!", Color(0.8, 0.65, 1.0))
		L.finish_turn(s)
		await get_tree().create_timer(0.7).timeout
		_next()
		return
	if _human_controls(s["side"]):
		_busy = false
		_reach = L.reachable(s)
		_grid.reach = _reach
		_grid.queue_redraw()
		_refresh_buttons(true)
		_update_hover()
	else:
		_busy = true
		_reach = {}
		_grid.reach = {}
		_grid.queue_redraw()
		_refresh_buttons(false)
		await get_tree().create_timer(0.35).timeout
		if not L.hero_cast[s["side"]]:
			var sp := BattleAI.decide_spell(L, s["side"])
			if not sp.is_empty():
				await _play(L.cast(s["side"], sp["spell"], sp["hex"]))
				if L.is_over() >= 0 or not s["alive"]:
					_next()
					return
		var act := BattleAI.decide(L, s)
		var ev := []
		match act["type"]:
			"shoot": ev = L.do_shoot(s, act["target"])
			"melee": ev = L.do_melee(s, act["target"], act["from"])
			"move": ev = L.do_move(s, act["hex"])
			_: ev = L.do_defend(s)
		await _play(ev)
		_next()

func _act(ev: Array) -> void:
	_busy = true
	_reach = {}
	_grid.reach = {}
	_grid.hover = Vector2i(-1, -1)
	_grid.queue_redraw()
	_status.text = ""
	_refresh_buttons(false)
	await _play(ev)
	_next()

# ---------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------
func _unhandled_input(e: InputEvent) -> void:
	if _ended or _modal_open():
		return
	if e is InputEventMouseMotion:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * e.position
		var h := pos_to_hex(_mouse)
		if h != _hover:
			_hover = h
			_update_hover()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and not _busy:
			_click()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			if _spell != "":
				_spell = ""
				_update_hover()
			else:
				var s = L.stack_at(pos_to_hex(get_viewport().get_canvas_transform().affine_inverse() * e.position))
				if s:
					ArmyStrip.show_creature_info(self, s["id"], s["count"])
	elif e is InputEventKey and e.pressed and not e.echo and not _busy:
		match e.keycode:
			KEY_W: _on_wait()
			KEY_D, KEY_SPACE: _on_defend()
			KEY_S: _on_spells()
			KEY_A: _on_auto()
			KEY_ESCAPE:
				if _spell != "":
					_spell = ""
					_update_hover()

func _modal_open() -> bool:
	var l := get_tree().root.get_node_or_null("ModalLayer")
	return l != null and l.get_child_count() > 0

func _update_hover() -> void:
	_grid.hover = _hover
	_hover_action = {}
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]):
		_grid.hover = Vector2i(-1, -1)
		_grid.attack_from = Vector2i(-1, -1)
		_grid.queue_redraw()
		_status.text = ""
		return
	var txt := ""
	if _spell != "":
		var sp: Dictionary = GameData.SPELLS[_spell]
		if L.in_bounds(_hover) and L.spell_target_ok(cur["side"], _spell, _hover):
			_hover_action = {"type": "cast", "hex": _hover}
			txt = "Cast %s" % sp["name"]
			var t = L.stack_at(_hover)
			if sp.has("damage") and t:
				txt += " on %s (%d damage)" % [L._name(t), L.spell_damage(cur["side"], _spell)]
		else:
			txt = "Select a target for %s (right click to cancel)" % sp["name"]
	elif L.in_bounds(_hover):
		var t = L.stack_at(_hover)
		if t and t["side"] != cur["side"]:
			if L.can_shoot(cur):
				var r := L.damage_range(cur, t, true)
				_hover_action = {"type": "shoot", "target": t}
				txt = "Shoot %s (damage %d-%d, kills %s)%s" % [L._name(t), r[0], r[1], _kills(t, r),
					"  [half damage: range]" if L.distance(cur["hex"], t["hex"]) > 10 else ""]
			else:
				var from := _attack_from(cur, t)
				if from != Vector2i(-1, -1):
					var moved: int = _reach.get(from, 0)
					var r := L.damage_range(cur, t, false, moved)
					_hover_action = {"type": "melee", "target": t, "from": from}
					txt = "Attack %s (damage %d-%d, kills %s)" % [L._name(t), r[0], r[1], _kills(t, r)]
				else:
					txt = "%s — out of reach" % L._name(t)
		elif t and t["side"] == cur["side"]:
			txt = "%d %s" % [t["count"], L._name(t)]
		elif _reach.has(_hover):
			_hover_action = {"type": "move", "hex": _hover}
			txt = "Move here" if not L.is_flyer(cur) else "Fly here"
	_grid.attack_from = _hover_action.get("from", Vector2i(-1, -1))
	_grid.queue_redraw()
	_status.text = txt

func _kills(t: Dictionary, r: Array) -> String:
	var hp: int = L.cdata(t)["hp"]
	var top: int = t["hp_top"]
	var k0: int = 0 if r[0] < top else 1 + (r[0] - top) / hp
	var k1: int = 0 if r[1] < top else 1 + (r[1] - top) / hp
	k0 = mini(k0, t["count"])
	k1 = mini(k1, t["count"])
	return str(k0) if k0 == k1 else "%d-%d" % [k0, k1]

## Choose the hex to attack from based on which side of the target the mouse is on.
func _attack_from(cur: Dictionary, t: Dictionary) -> Vector2i:
	var opts := L.attack_positions(cur, t, _reach)
	if opts.is_empty():
		return Vector2i(-1, -1)
	var m := _mouse
	var best: Vector2i = opts[0]
	var bd := 1e9
	for h in opts:
		var d := (hex_pos(h) - m).length()
		if d < bd:
			bd = d
			best = h
	return best

func _click() -> void:
	var cur = L.current()
	if cur == null or not _human_controls(cur["side"]) or _hover_action.is_empty():
		return
	match _hover_action["type"]:
		"move":
			_act(L.do_move(cur, _hover_action["hex"]))
		"melee":
			_act(L.do_melee(cur, _hover_action["target"], _hover_action["from"]))
		"shoot":
			_act(L.do_shoot(cur, _hover_action["target"]))
		"cast":
			var sp := _spell
			_spell = ""
			_btns["Spells"].disabled = true
			_busy = true
			await _play(L.cast(cur["side"], sp, _hover_action["hex"]))
			_busy = false
			if L.is_over() >= 0 or not cur["alive"]:
				_next()
			else:
				_reach = L.reachable(cur)
				_grid.reach = _reach
				_refresh_buttons(true)
				_update_hover()

func _on_wait() -> void:
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]):
		return
	if L.do_wait(cur):
		_set_log("%s %s." % [L._name(cur), "waits" if cur["count"] == 1 else "wait"])
		_act([])

func _on_defend() -> void:
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]):
		return
	_act(L.do_defend(cur))

func _on_auto() -> void:
	_auto = not _auto
	_btns["Auto: Off"].text = "Auto: On" if _auto else "Auto: Off"
	if _auto and not _busy:
		_next()

func _on_retreat() -> void:
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]) or L.heroes[cur["side"]] == null:
		return
	if await Modal.confirm(self, "Retreat", "Retreat from battle? Your army will be lost, but your hero will survive to be hired again.").closed:
		_retreated = cur["side"]
		_end_battle(1 - cur["side"])

func _on_spells() -> void:
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]) or not L.can_cast(cur["side"]):
		return
	var side: int = cur["side"]
	var h = L.heroes[side]
	# A two-page parchment spellbook, like HoMM's.
	var m := Modal.custom(self, "", 1180)
	if Assets.has("ui/parchment.png"):
		var sb := StyleBoxTexture.new()
		sb.texture = Assets.tex("ui/parchment.png")
		sb.set_texture_margin_all(40)
		sb.set_content_margin_all(40)
		m.panel.add_theme_stylebox_override("panel", sb)
	var ink := Color(0.25, 0.14, 0.06)
	var title := UI.label("%s's Spellbook  —  %d mana" % [h["name"], h["mana"]], 30, Color(0.45, 0.1, 0.05), true)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(title)
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 30)
	m.body.add_child(pages)
	var spells: Array = h["spells"].duplicate()
	spells.sort_custom(func(a, b): return GameData.SPELLS[a]["level"] < GameData.SPELLS[b]["level"])
	var half := int(ceil(spells.size() / 2.0))
	for page in 2:
		var g := GridContainer.new()
		g.columns = 2
		g.custom_minimum_size = Vector2(520, 360)
		g.add_theme_constant_override("h_separation", 16)
		g.add_theme_constant_override("v_separation", 14)
		pages.add_child(g)
		if page == 0:
			var spine := ColorRect.new()
			spine.color = Color(0.45, 0.32, 0.18, 0.6)
			spine.custom_minimum_size = Vector2(3, 360)
			pages.add_child(spine)
		for s in spells.slice(page * half, (page + 1) * half):
			var sp: Dictionary = GameData.SPELLS[s]
			var b := Button.new()
			b.flat = true
			b.custom_minimum_size = Vector2(250, 170)
			b.text = "%s\nLevel %d  ·  %d mana" % [sp["name"], sp["level"], sp["mana"]]
			b.icon = Assets.spell_icon(s)
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.add_theme_constant_override("icon_max_width", 90)
			b.add_theme_font_size_override("font_size", 19)
			for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(st, ink if st == "font_color" else Color(0.55, 0.12, 0.05))
			b.add_theme_color_override("font_disabled_color", Color(0.45, 0.4, 0.35, 0.7))
			b.tooltip_text = sp["desc"]
			b.disabled = sp["mana"] > h["mana"]
			var sid: String = s
			b.pressed.connect(func(): m.close(sid))
			g.add_child(b)
	m.add_buttons([["Close", ""]])
	m.set_meta("cancel", "")
	var r = await m.closed
	if r == null or r == "":
		return
	if GameData.SPELLS[r]["target"] == "all_living":
		_busy = true
		await _play(L.cast(side, r, Vector2i(7, 5)))
		_busy = false
		if L.is_over() >= 0 or not cur["alive"]:
			_next()
		else:
			_reach = L.reachable(cur)
			_grid.reach = _reach
			_refresh_buttons(true)
		return
	_spell = r
	_update_hover()

# ---------------------------------------------------------------------------------------------
# Event animation
# ---------------------------------------------------------------------------------------------
func _play(events: Array) -> void:
	for ev in events:
		match ev["t"]:
			"move":
				await _anim_move(ev["s"], ev["path"])
			"attack":
				await _anim_attack(ev)
			"spell":
				await _anim_spell(ev)
			"death":
				_anim_death(ev["s"])
				await get_tree().create_timer(0.25).timeout
			"heal":
				_float_text(_unit(ev["s"]).position + Vector2(0, -_top(ev["s"]) - 10), "+%d" % ev["amount"], Color(0.5, 1, 0.5))
				_refresh_badge(ev["s"])
			"text":
				_set_log(ev["text"])
	if L.log_lines.size() > 0:
		_set_log(L.log_lines[L.log_lines.size() - 1])
	for k in units:
		units[k].get_node("Badge").queue_redraw()

func _anim_move(st: Dictionary, path: Array) -> void:
	var n := _unit(st)
	var spr: Sprite2D = n.get_node("Sprite")
	if L.is_flyer(st):
		Audio.sfx("wings", -4)
		var target := hex_pos(path[path.size() - 1]) + Vector2(0, 24)
		if absf(target.x - n.position.x) > 2:
			_set_flip(spr, target.x < n.position.x)
		var dur := clampf(n.position.distance_to(target) / 900.0, 0.3, 0.8)
		var tw := n.create_tween()
		tw.tween_property(n, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var tw2 := spr.create_tween()
		tw2.tween_property(spr, "position:y", -50.0, dur * 0.5).set_ease(Tween.EASE_OUT)
		tw2.tween_property(spr, "position:y", 0.0, dur * 0.5).set_ease(Tween.EASE_IN)
		await tw.finished
	else:
		for i in range(1, path.size()):
			var target := hex_pos(path[i]) + Vector2(0, 24)
			if absf(target.x - n.position.x) > 2:
				_set_flip(spr, target.x < n.position.x)
			Audio.sfx("move_step", -10, 0.15)
			var tw := n.create_tween()
			tw.tween_property(n, "position", target, 0.13)
			var bob := spr.create_tween()  # a small step bob per hex so walkers don't glide
			bob.tween_property(spr, "position:y", -7.0, 0.065).set_ease(Tween.EASE_OUT)
			bob.tween_property(spr, "position:y", 0.0, 0.065).set_ease(Tween.EASE_IN)
			await tw.finished
	_set_flip(spr, st["side"] == 1)
	_face_enemies(st)

func _face_enemies(st: Dictionary) -> void:
	# Face the nearest enemy horizontally.
	var n := _unit(st)
	var best = null
	var bd := 1e9
	for e in L.alive_stacks(1 - st["side"]):
		var d := L.distance(st["hex"], e["hex"])
		if d < bd:
			bd = d
			best = e
	if best:
		_set_flip(n.get_node("Sprite"), hex_pos(best["hex"]).x < hex_pos(st["hex"]).x)

func _anim_attack(ev: Dictionary) -> void:
	var a: Dictionary = ev["a"]
	var d: Dictionary = ev["d"]
	var na := _unit(a)
	var nd := _unit(d)
	var spr: Sprite2D = na.get_node("Sprite")
	_set_flip(spr, nd.position.x < na.position.x)
	_pose(a, "attack", 0.55 if ev["ranged"] else 0.42)
	if ev["ranged"]:
		var proj := _Projectile.new()
		proj.kind = "magic" if a["id"] in ["monk", "lich"] else "arrow"
		proj.from = na.position + Vector2(0, -_top(a) * 0.6)
		proj.to = nd.position + Vector2(0, -60)
		_fx.add_child(proj)
		Audio.sfx("magic_arrow" if proj.kind == "magic" else "arrow_shot", -2)
		var tw := na.create_tween()
		tw.tween_property(spr, "rotation", -0.06 if spr.flip_h else 0.06, 0.1)
		tw.tween_property(spr, "rotation", 0.0, 0.1)
		await proj.fly(0.28)
		Audio.sfx("magic_hit" if proj.kind == "magic" else "arrow_hit", -2)
	else:
		var dir := (nd.position - na.position).normalized()
		var home := spr.position
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", home + dir * 34, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "position", home, 0.18)
		await get_tree().create_timer(0.11).timeout
		Audio.creature_sfx(a["id"], "attack", "claw_hit" if a["id"] in ["griffin", "bone_dragon", "ghost", "vampire"] else ("blunt_hit" if a["id"] in ["zombie", "monk"] else "sword_hit"))
	_hit_flash(d)
	var col := Color(1, 0.85, 0.3) if ev["lucky"] else Color(1, 0.35, 0.3)
	var txt := "-%d" % ev["dmg"]
	if ev["killed"] > 0:
		txt += "  (%d)" % ev["killed"]
	if ev["lucky"]:
		txt = "Lucky! " + txt
	_float_text(nd.position + Vector2(0, -_top(d) - 10), txt, col)
	_refresh_badge(d)
	await get_tree().create_timer(0.3).timeout

func _hit_flash(d: Dictionary) -> void:
	if d.get("alive", false):
		_pose(d, "hit", 0.45)
	var nd := _unit(d)
	var s: Sprite2D = nd.get_node("Sprite")
	var tw := s.create_tween()
	tw.tween_property(s, "modulate", Color(1.8, 0.6, 0.6), 0.06)
	tw.tween_property(s, "modulate", Color.WHITE, 0.2)
	var base := s.position.x
	var tw2 := s.create_tween()
	for i in 3:
		tw2.tween_property(s, "position:x", base + (6 if i % 2 == 0 else -6), 0.04)
	tw2.tween_property(s, "position:x", base, 0.04)

func _anim_death(st: Dictionary) -> void:
	var n := _unit(st)
	var c := L.cdata(st)
	Audio.creature_sfx(st["id"], "death", "death_undead" if "undead" in c["abilities"] else ("death_beast" if st["id"] in ["griffin"] else "death_human"))
	var s: Sprite2D = n.get_node("Sprite")
	n.get_node("Badge").visible = false
	n.get_node("Shadow").visible = false
	if n.has_meta("breath"):
		n.get_meta("breath").kill()
		s.scale = n.get_meta("base_scale")
	# (a negative z_index would hide the body behind the battlefield background)
	n.reparent(_corpses)
	if _pose(st, "dead"):
		# the corpse stays on its hex, a little darker, as in the classics
		s.modulate = Color(1.6, 0.7, 0.7)
		var tw0 := s.create_tween()
		tw0.tween_property(s, "modulate", Color(0.78, 0.74, 0.72), 0.5)
		var m: ShaderMaterial = s.material
		if m:
			m.set_shader_parameter("ink", Color(0.09, 0.06, 0.03, 0.95))
			m.set_shader_parameter("width", 1.2)
		return
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate", Color(0.35, 0.3, 0.3, 0.55), 0.5)
	tw.tween_property(s, "rotation", (PI * 0.5) * (-1 if s.flip_h else 1), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "position:y", 10.0, 0.45)

func _anim_spell(ev: Dictionary) -> void:
	var sp: String = ev["spell"]
	var colors := {"fire": Color(1, 0.5, 0.15), "air": Color(0.6, 0.85, 1.0), "water": Color(0.45, 0.75, 1.0), "earth": Color(0.75, 0.55, 0.3)}
	var school: String = GameData.SPELLS[sp]["school"] if GameData.SPELLS.has(sp) else "earth"
	var col: Color = colors.get(school, Color(0.7, 0.4, 1.0))
	if sp == "death_cloud":
		col = Color(0.5, 0.9, 0.4)
	var sfx_map := {"magic_arrow": "magic_arrow", "lightning_bolt": "lightning", "fireball": "fireball", "bless": "bless", "curse": "curse",
		"cure": "heal", "resurrection": "heal", "meteor_shower": "meteor", "death_ripple": "curse", "frost_ring": "magic_hit", "ice_bolt": "magic_hit"}
	Audio.sfx(sfx_map.get(sp, "spell_cast"))
	if sp != "death_cloud" and L.heroes[ev["side"]] != null:
		_spell_banner(GameData.SPELLS[sp]["name"], ev["side"])
	var targets: Array = ev["targets"]
	var centers := []
	if GameData.SPELLS.has(sp) and GameData.SPELLS[sp]["target"] == "area" or sp == "death_cloud":
		centers.append(hex_pos(ev["hex"]) + Vector2(0, -30))
	for t in targets:
		centers.append(_unit(t).position + Vector2(0, -70))
	for c in centers:
		var burst := _Burst.new()
		burst.color = col
		burst.position = c
		burst.bolt = sp == "lightning_bolt"
		burst.radius = 150.0 if (GameData.SPELLS.has(sp) and GameData.SPELLS[sp]["target"] == "area") else 70.0
		_fx.add_child(burst)
	await get_tree().create_timer(0.35).timeout
	for t in targets:
		if ev["dmg"].has(t["uid"]):
			_hit_flash(t)
			var txt := "-%d" % ev["dmg"][t["uid"]]
			if ev["killed"].get(t["uid"], 0) > 0:
				txt += "  (%d)" % ev["killed"][t["uid"]]
			_float_text(_unit(t).position + Vector2(0, -_top(t) - 10), txt, Color(1, 0.4, 0.35))
			_refresh_badge(t)
		else:
			var s: Sprite2D = _unit(t).get_node("Sprite")
			var tw := s.create_tween()
			tw.tween_property(s, "modulate", col.lightened(0.4) * 1.5, 0.15)
			tw.tween_property(s, "modulate", Color.WHITE, 0.4)
	await get_tree().create_timer(0.45).timeout

func _refresh_badge(st: Dictionary) -> void:
	var n := _unit(st)
	if n:
		n.get_node("Badge").queue_redraw()

func _float_text(p: Vector2, t: String, col: Color) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UI.title_font())
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	var bg := StyleBoxFlat.new()  # soft dark backing so numbers stay readable over busy sprites
	bg.bg_color = Color(0, 0, 0, 0.42)
	bg.set_corner_radius_all(8)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	l.add_theme_stylebox_override("normal", bg)
	l.z_index = 30
	_fx.add_child(l)
	l.reset_size()
	l.position = p - Vector2(l.size.x * 0.5, 0)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", p.y - 70, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)

## Spell name as a banner under the turn queue (not over the units), tinted by the caster's side.
func _spell_banner(t: String, side: int) -> void:
	var l := UI.label(t, 34, UI.GOLD, true)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.05, 0.03, 0.8)
	bg.border_color = Color(0.8, 0.25, 0.2) if side == 0 else Color(0.3, 0.45, 0.95)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 24
	bg.content_margin_right = 24
	l.add_theme_stylebox_override("normal", bg)
	ui.add_child(l)
	l.reset_size()
	l.position = Vector2(960 - l.size.x * 0.5, 140)
	var tw := l.create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)

# ---------------------------------------------------------------------------------------------
# End of battle
# ---------------------------------------------------------------------------------------------
func _end_battle(winner: int) -> void:
	if _ended:
		return
	_ended = true
	_busy = true
	_queue_box.get_parent().visible = false
	_grid.hover = Vector2i(-1, -1)
	_grid.reach = {}
	_grid.active = {}
	_grid.queue_redraw()
	var loser := 1 - winner
	var xp := L.killed_hp(loser)
	var raised := 0
	var wh = L.heroes[winner]
	if wh and int(wh["skills"].get("necromancy", 0)) > 0:
		var cas := L.casualties(loser)
		var living := 0
		for id in cas:
			if not "undead" in GameData.CREATURES[id]["abilities"]:
				living += cas[id]
		raised = int(living * 0.1 * int(wh["skills"]["necromancy"]))
	var human_side := 0 if not L.ai_side[0] else (1 if not L.ai_side[1] else -1)
	var human_won := human_side == winner
	Audio.music("victory" if human_won or human_side < 0 else "defeat")
	await get_tree().create_timer(0.8).timeout

	var m := Modal.custom(self, "Victory!" if human_won else ("Defeat" if human_side >= 0 else "Battle Over"), 900)
	var who := ["Attacker", "Defender"]
	for side in 2:
		var hh = L.heroes[side]
		who[side] = hh["name"] if hh else "Neutral creatures"
	var msg := ""
	if _retreated >= 0:
		msg = "%s retreats from the battlefield." % who[_retreated]
	else:
		msg = "%s is victorious." % who[winner]
	m.add_text(msg, 24)
	for side in 2:
		m.body.add_child(UI.label("%s — casualties" % who[side], 22, UI.GOLD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var cas := L.casualties(side)
		if _retreated == side:
			for st in L.stacks:
				if st["side"] == side and st["alive"]:
					cas[st["id"]] = cas.get(st["id"], 0) + st["count"]
		for id in cas:
			var v := VBoxContainer.new()
			v.add_child(UI.icon(Assets.creature_portrait(id), Vector2(64, 64)))
			var l := UI.label(str(cas[id]), 20)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(l)
			row.add_child(v)
		if cas.is_empty():
			row.add_child(UI.label("None", 20))
		m.body.add_child(row)
	if wh:
		m.add_text("%s gains %d experience." % [wh["name"], xp], 22)
	if raised > 0:
		m.add_text("Necromancy raises %d skeletons from the fallen." % raised, 22)
	m.add_buttons([["OK", true]])
	m.set_meta("default", true)
	await m.closed

	var result := {
		"winner": "attacker" if winner == 0 else "defender",
		"attacker_army": L.army_out(0) if _retreated != 0 else [null, null, null, null, null, null, null],
		"defender_army": L.army_out(1) if _retreated != 1 else [null, null, null, null, null, null, null],
		"xp": xp, "retreated": _retreated >= 0, "raised": raised,
	}
	if GameState.pending_battle.is_empty():
		GameState.pending_battle = setup_d
		if GameState.return_scene == GameState.SCENE_ADVENTURE and GameState.world.is_empty():
			GameState.return_scene = GameState.SCENE_MENU
	GameState.finish_battle(result)

# ---------------------------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------------------------
class _Grid extends Node2D:
	var b
	var reach := {}
	var hover := Vector2i(-1, -1)
	var active := {}
	var attack_from := Vector2i(-1, -1)
	func _process(_d: float) -> void:
		if not active.is_empty():
			queue_redraw()  # pulse the active hex
	func _draw() -> void:
		for y in BattleLogic.ROWS:
			for x in BattleLogic.COLS:
				var h := Vector2i(x, y)
				var c: Vector2 = b.hex_pos(h)
				var poly: PackedVector2Array = b.hex_poly(c, 2.0)
				if reach.has(h):
					draw_colored_polygon(poly, Color(0.05, 0.03, 0.0, 0.3))
				var closed := poly.duplicate()
				closed.append(poly[0])
				draw_polyline(closed, Color(0, 0, 0, 0.22), 3.0, true)  # dark under-line keeps the grid visible on light ground
				draw_polyline(closed, Color(1, 0.97, 0.8, 0.34), 1.5, true)
		if not active.is_empty() and active.get("alive", false):
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
			var poly: PackedVector2Array = b.hex_poly(b.hex_pos(active["hex"]), 3.0)
			draw_colored_polygon(poly, Color(1, 0.85, 0.3, 0.22 + 0.18 * pulse))
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, Color(1, 0.9, 0.4, 0.75 + 0.25 * pulse), 4.0, true)
		if hover.x >= 0:
			var poly: PackedVector2Array = b.hex_poly(b.hex_pos(hover), 3.0)
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_colored_polygon(poly, Color(1, 1, 1, 0.12))
			draw_polyline(closed, Color(1, 1, 1, 0.7), 2.0, true)
		if attack_from.x >= 0:
			var poly: PackedVector2Array = b.hex_poly(b.hex_pos(attack_from), 3.0)
			draw_colored_polygon(poly, Color(1, 0.4, 0.2, 0.25))

class _Shadow extends Node2D:
	var big := false
	var active := false:
		set(v):
			active = v
			queue_redraw()
	func _process(_d: float) -> void:
		if active:
			queue_redraw()
	func _draw() -> void:
		var w := 62.0 if big else 44.0
		draw_set_transform(Vector2(0, -2), 0, Vector2(1, 0.32))
		draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.35))
		if active:
			var a := 0.55 + 0.35 * sin(Time.get_ticks_msec() / 160.0)
			draw_arc(Vector2.ZERO, w + 4, 0, TAU, 40, Color(1, 0.85, 0.3, a), 4.0, true)

class _Badge extends Node2D:
	var st: Dictionary
	func _draw() -> void:
		if not st.get("alive", false):
			return
		var txt := str(st["count"])
		var f := UI.font()
		var fs := 19
		var tw := maxf(30.0, f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12)
		var r := Rect2(Vector2(-tw * 0.5, -12), Vector2(tw, 24))
		var col := Color(0.45, 0.12, 0.1) if st["side"] == 0 else Color(0.12, 0.2, 0.5)
		if st["effects"].size() > 0:
			var good: bool = st["effects"].has("bless") or st["effects"].has("haste") or st["effects"].has("shield") or st["effects"].has("stone_skin")
			var bad: bool = st["effects"].has("curse") or st["effects"].has("slow") or st["effects"].has("weakness") or st["effects"].has("disease")
			if good and not bad:
				col = Color(0.15, 0.45, 0.15)
			elif bad and not good:
				col = Color(0.4, 0.15, 0.45)
		draw_rect(r, col)
		draw_rect(r, UI.GOLD, false, 1.5)
		draw_string(f, Vector2(r.position.x, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, fs, Color.WHITE)

class _QueueIcon extends Control:
	var st: Dictionary
	var first := false
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.05, 0.04, 0.03))
		draw_texture_rect(Assets.creature_portrait(st["id"]), r.grow(-3), false, Color(1.25, 1.2, 1.15))  # portraits are dark at this size
		var col := Color(0.8, 0.2, 0.15) if st["side"] == 0 else Color(0.25, 0.4, 0.95)
		draw_rect(r, UI.GOLD if first else col, false, 4.0 if first else 3.0)
		var txt := str(st["count"])
		var f := UI.font()
		draw_rect(Rect2(Vector2(0, size.y - 20), Vector2(size.x, 20)), Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(0, size.y - 4), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color.WHITE)

class _Projectile extends Node2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var kind := "arrow"
	var t := 0.0
	func fly(dur: float) -> void:
		var tw := create_tween()
		tw.tween_property(self, "t", 1.0, dur)
		tw.tween_callback(queue_free)
		await tw.finished
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var p := from.lerp(to, t) + Vector2(0, -sin(t * PI) * 60.0 * (1.0 if kind == "arrow" else 0.3))
		if kind == "arrow":
			var dir := (to - from).normalized().rotated(-cos(t * PI) * 0.35 * signf(to.x - from.x))
			draw_line(p - dir * 26, p, Color(0.35, 0.22, 0.1), 3.0)
			draw_line(p - dir * 26, p - dir * 20, Color(0.9, 0.9, 0.85), 5.0)
			draw_circle(p, 3, Color(0.7, 0.7, 0.75))
		else:
			for i in 5:
				draw_circle(p - (to - from).normalized() * i * 9, 12 - i * 2, Color(0.75, 0.6, 1.0, 0.8 - i * 0.15))

class _Burst extends Node2D:
	var color := Color.WHITE
	var radius := 70.0
	var bolt := false
	var t := 0.0
	var _seeds := []
	func _ready() -> void:
		for i in 26:
			_seeds.append([randf() * TAU, randf_range(0.4, 1.0), randf_range(3.0, 8.0)])
		var tw := create_tween()
		tw.tween_property(self, "t", 1.0, 0.75)
		tw.tween_callback(queue_free)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var a := 1.0 - t
		if bolt and t < 0.5:
			var p := Vector2(0, -700)
			var pts := PackedVector2Array([p])
			for i in 8:
				p = p.lerp(Vector2.ZERO, 1.0 / (8 - i)) + Vector2(randf_range(-30, 30), 0)
				pts.append(p)
			var a2 := 1.0 - t * 2.0
			draw_polyline(pts, Color(0.45, 0.65, 1.0, 0.22 * a2), 34.0)  # outer glow
			draw_polyline(pts, Color(0.6, 0.8, 1.0, 0.5 * a2), 16.0)
			draw_polyline(pts, Color(0.85, 0.95, 1.0, a2), 7.0)
			draw_polyline(pts, Color(1, 1, 1, a2), 3.0)
			draw_circle(Vector2.ZERO, 60.0 * (1.0 - t), Color(0.9, 0.95, 1.0, 0.55 * a2))  # impact flash
		draw_circle(Vector2.ZERO, radius * (0.3 + t * 0.9), Color(color, 0.35 * a))
		draw_arc(Vector2.ZERO, radius * (0.2 + t), 0, TAU, 48, Color(color.lightened(0.4), a), 4.0 * a + 1.0)
		for s in _seeds:
			var d: float = radius * s[1] * (0.2 + t * 1.1)
			draw_circle(Vector2(cos(s[0]), sin(s[0]) * 0.6) * d, s[2] * a, Color(color.lightened(0.3), a))

class _Fallback extends Node2D:
	var terrain := "grass"
	func _draw() -> void:
		var ground: Color = {"grass": Color(0.3, 0.45, 0.18), "dirt": Color(0.42, 0.33, 0.2), "sand": Color(0.75, 0.65, 0.42),
			"snow": Color(0.85, 0.88, 0.92), "swamp": Color(0.26, 0.32, 0.2)}.get(terrain, Color(0.3, 0.45, 0.18))
		for i in 40:
			var y := i * 27.0
			var c: Color = Color(0.45, 0.6, 0.85).lerp(Color(0.85, 0.75, 0.6), i / 10.0) if y < 260 else ground.darkened(0.15 - (y - 260) / 820.0 * 0.3)
			draw_rect(Rect2(0, y, 1920, 28), c)
