extends Node2D
## Battle scene: renders the hex field, animates BattleLogic events, handles player input and AI turns.

const HEX_W := 96.0
const ROW_STEP := 68.0
const X0 := 264.0
const Y0 := 272.0
const TIER_H := [120.0, 120.0, 128.0, 150.0, 150.0, 160.0, 185.0, 215.0]  # (tier 0: war machines)
## On-screen height of the solid figure per tier (sizes.json, without the cast shadow): higher tiers clearly dominate,
## yet the biggest stay within about two rows, so a melee of three stacks still reads as three figures.
const FIG_H := [112.0, 104.0, 110.0, 116.0, 120.0, 122.0, 126.0, 132.0]
## Obstacle pictures by battlefield terrain (assets/battle/obstacle_<kind>.png, tools/art/obstacle_paint.py).
const OBSTACLES := {
	"grass": ["boulders", "dead_tree", "log", "stump", "thorns", "pillar", "rock_spire"],
	"dirt": ["boulders", "crater", "dead_tree", "skull_pile", "rock_spire", "log", "pillar"],
	"snow": ["snow_boulders", "ice", "frozen_tree", "snow_boulders", "ice"],
	"sand": ["sandstone", "cactus", "bones", "crater", "skull_pile"],
	"swamp": ["swamp_tree", "rotten_log", "thorns", "dead_tree", "skull_pile"],
}
## Widest figure in hexes, wings and capes included: 1-hex and 2-hex units (a stack mustn't swallow its neighbours).
const VIS_MAX_W := [1.1, 2.2]

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

## Width with semi-transparent parts (bone wings, capes, pikes), above the shadow.
static func fig_vis_w(id: String) -> float:
	fig_size(id)
	var v = _sizes.get(id + ".png")
	return float(v[2]) if v != null and v.size() > 2 else fig_size(id).x

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
var _rings: Node2D  # every stack's ground ring, under all the figures (a ring never cuts across the stack behind)
var _corpses: Node2D
var _fx: Node2D
var _floats: Array = []
var _obstacle_rects: Array = []  # (field space) labels keep off them
var _low_obstacles: Array = []  # [sprite, rect]: the low ones on the ground, faded where a figure stands over them
var _log_hist: Array = []   # combat log lines, oldest first
var _log_scroll := 0        # how many lines back from the newest the bar shows
var _log_seen := 0          # L.log_lines already copied into the log
var _log_arrows: Array = []
const BAR_Y := 1002.0
const BTN := Vector2(78, 66)    # live damage / status labels (they keep clear of each other)
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
var _surrendered := false  # (with _retreated: that side paid to leave with its army)
var _surrender_gold := 0
var _ended := false
var _mouse := Vector2.ZERO
var _hero_rects := [Rect2(), Rect2()]
var _info_key := ""   # what the hover panel shows: "s<uid>" a stack, "h<side>" a hero, "" nothing

func _ready() -> void:
	HoverInfo.set_floor(BAR_Y - 70)  # (stack panels stay above the log bar)
	tree_exiting.connect(func():
		HoverInfo.set_floor(-1.0)
		Engine.time_scale = 1.0)
	Engine.time_scale = GameState.battle_speed
	setup_d = GameState.pending_battle
	if setup_d.is_empty():
		setup_d = _demo_setup()
	L = BattleLogic.new()
	L.setup(setup_d)
	_build_scene()
	if L.siege > 0 and Shot.args.has("broken"):  # (shots of a siege some turns in: --broken=1,3 breaches those segments)
		for t in str(Shot.args["broken"]).split(","):
			var i := int(t)
			if i >= 0 and i < L.walls.size() and L.walls[i]["kind"] != "tower":
				L.walls[i]["hp"] = 0
				_set_wall(i, true)
	_build_ui()
	Audio.music("battle")
	Audio.sfx("battle_start", -2)
	var who := []
	for side in 2:
		who.append(L.heroes[side]["name"] if L.heroes[side] != null else "the %s" % L._name(L.alive_stacks(side)[0]) if L.alive_stacks(side).size() > 0 else "?")
	_set_log("The battle begins: %s against %s." % who)
	await get_tree().create_timer(0.6).timeout
	_next()

func _demo_setup() -> Dictionary:
	var a := GameState.make_hero("sir_aldric", 0)
	var d := GameState.make_hero("lord_morthis", 1)
	for h in [a, d]:
		var c: Array = GameData.FACTIONS[h["faction"]]["upgrades" if Shot.setup == "upgraded" else "creatures"]
		for i in 7:
			h["army"][i] = {"id": c[i], "count": [30, 18, 9, 6, 4, 2, 1][i]}
		h["spells"] = GameData.SPELLS.keys() if Shot.setup == "all_spells" else ["magic_arrow", "bless", "lightning_bolt", "fireball", "haste", "cure"]
		h["power"] = 3
		h["knowledge"] = 4
		h["mana"] = 40
	var out := {"attacker_army": a["army"], "defender_army": d["army"], "attacker_hero": a, "defender_hero": d,
		"terrain": "grass", "attacker_player": 0, "defender_player": 1, "attacker_ai": false, "defender_ai": true,
		"context": {"type": "demo"}, "seed": int(Shot.args.get("seed", "7"))}
	if Shot.setup.begins_with("siege"):  # Sir Aldric with all his machines before a Necropolis citadel
		a["machines"] = GameData.WAR_MACHINES.duplicate()
		out["siege"] = 3
		out["siege_faction"] = "haven" if Shot.setup == "siege_haven" else "necropolis"
	return out

# ---------------------------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------------------------
static func hex_pos(h: Vector2i) -> Vector2:
	return Vector2(X0 + h.x * HEX_W + (HEX_W * 0.5 if h.y % 2 == 1 else 0.0), Y0 + h.y * ROW_STEP)

## Where a stack's feet stand with its head on `head`: the middle of its footprint (two hexes for large ones).
func stand_pos(st: Dictionary, head = null) -> Vector2:
	var h: Vector2i = st["hex"] if head == null else head
	var p := hex_pos(h) + Vector2(0, 24)
	if h.x < 0 or h.x >= BattleLogic.COLS:  # (the machines' back rank: a little further back, clear of the first column)
		p.x += -30.0 if h.x < 0 else 30.0
	if L.is_wide(st):
		p.x += BattleLogic.tail_dir(st["side"]).x * HEX_W * 0.5
	return p

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
		for x in range(-1, BattleLogic.COLS + 1):  # (with the machines' back rank)
			if (x < 0 or x >= BattleLogic.COLS) and L.stack_at(Vector2i(x, y)) == null:
				continue
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
	if L.siege > 0 and Assets.has("battle/bg_siege_%s.png" % L.siege_faction):
		bgp = "battle/bg_siege_%s.png" % L.siege_faction
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
	if L.siege > 0:
		_wall_layer = Node2D.new()  # breaches and cracks over the painted wall, under the grid and the stacks
		add_child(_wall_layer)
	_field = Node2D.new()
	add_child(_field)
	_grid = _Grid.new()
	_grid.b = self
	_field.add_child(_grid)
	if L.siege > 0:
		var moat := _Moat.new()
		moat.b = self
		_field.add_child(moat)
	_corpses = Node2D.new()  # dead stacks: above the ground and grid, below everything standing
	_corpses.y_sort_enabled = true
	_field.add_child(_corpses)
	var ground := Node2D.new()  # low obstacles (thorns, boulders, a crater): under every figure, never over one
	ground.y_sort_enabled = true
	_field.add_child(ground)
	_rings = Node2D.new()
	_field.add_child(_rings)
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	_field.add_child(_sorted)
	_fx = Node2D.new()
	_fx.z_index = 20
	_field.add_child(_fx)
	var kinds: Array = OBSTACLES.get(L.terrain, OBSTACLES["grass"])
	for h in L.obstacles:
		var kind: String = kinds[(L.obstacles[h] - 1 + h.x + h.y) % kinds.size()]
		var s := Sprite2D.new()
		if kind == "stump":  # the old painted stump: drawn by its width
			s.texture = Assets.tex("battle/obstacle_2.png", Vector2i(96, 72))
			s.scale = Vector2.ONE * (120.0 / s.texture.get_width())
			s.offset = Vector2(0, -s.texture.get_height() * 0.5)
		else:  # painted at twice their size, centred on their feet at the bottom of the canvas
			s.texture = Assets.tex("battle/obstacle_%s.png" % kind, Vector2i(96, 72))
			s.scale = Vector2.ONE * 0.38
			s.offset = Vector2(0, -s.texture.get_height() * 0.5 + 6)
		s.position = hex_pos(h) + Vector2(0, 22)
		var vis_h := Vector2(s.texture.get_size()).y * s.scale.y
		if vis_h < 90.0:  # a low one lies inside its own hex (its middle on the ground where the stacks stand), not up into the hex behind
			if kind != "stump":  # (and a little smaller: a lance or a head behind it stays clear of it)
				s.scale = Vector2.ONE * 0.33
				s.offset = Vector2(0, -s.texture.get_height() * 0.5 + 6)
				vis_h = Vector2(s.texture.get_size()).y * s.scale.y
			s.position.y = hex_pos(h).y + 14.0 + vis_h * 0.5 - (6.0 * s.scale.y if kind != "stump" else 0.0)
		(ground if vis_h < 90.0 else _sorted).add_child(s)
		var rr := s.get_rect()
		_obstacle_rects.append(Rect2(s.position + rr.position * s.scale, rr.size * s.scale).grow(-8))
		if vis_h < 90.0:
			_low_obstacles.append([s, _obstacle_rects[-1]])
	if L.siege > 0:
		_build_walls()
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
		var sz := Vector2(s.texture.get_size()) * sc
		_hero_rects[side] = Rect2(s.position - sz * 0.5, sz).grow(-sz.x * 0.12)
		var nl := UI.label(hh["name"], 22, UI.GOLD, true)
		var plate := StyleBoxFlat.new()  # dark plate: the name must read over any backdrop
		plate.bg_color = Color(0.05, 0.035, 0.02, 0.78)
		plate.border_color = Color(0.85, 0.25, 0.2, 0.9) if side == 0 else Color(0.3, 0.5, 1.0, 0.9)
		plate.border_width_bottom = 3
		plate.set_corner_radius_all(5)
		plate.content_margin_left = 12
		plate.content_margin_right = 12
		nl.add_theme_stylebox_override("normal", plate)
		nl.add_theme_constant_override("outline_size", 5)
		nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(nl)
		nl.size = nl.get_combined_minimum_size()
		nl.position = Vector2((110 if side == 0 else 1810) - nl.size.x * 0.5, 292)

func _make_unit(st: Dictionary) -> void:
	var c: Dictionary = GameData.CREATURES[st["id"]]
	var n := Node2D.new()
	n.position = stand_pos(st)
	var wide := L.is_wide(st)
	var shadow := _Shadow.new()
	shadow.big = wide
	shadow.side = st["side"]
	shadow.position = n.position
	_rings.add_child(shadow)
	n.set_meta("shadow", shadow)
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
			sc = FIG_H[c["tier"]] / fig.y
			# (but never below 85% of its tier's height: an archangel stays a big figure)
			sc = maxf(minf(sc, HEX_W * VIS_MAX_W[1 if wide else 0] / fig_vis_w(st["id"])), sc * 0.85)
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
	s.set_meta("home", s.position)
	n.add_child(s)
	var badge := _Badge.new()
	badge.name = "Badge"
	badge.st = st
	# beside the feet at the front of the footprint, facing the enemy (as the classic count plates): on the stack's
	# own ground, not on the figure in the row below; above floating numbers so a count is never hidden
	badge.position = Vector2((HEX_W * (0.5 if wide else 0.0) + 30) * (1 if st["side"] == 0 else -1), -2)
	badge.set_meta("home", badge.position)
	badge.z_index = 60
	n.add_child(badge)
	_sorted.add_child(n)
	units[st["uid"]] = n
	if st.get("machine", false):
		badge.visible = false  # (a machine is one piece, no count; its ring shows whose it is)
		if st.get("tower", false):  # an arrow tower: the crew behind the parapet of a painted tower
			shadow.on = false
			var spots: Dictionary = ARCHER_SPOTS.get(L.siege_faction, ARCHER_SPOTS["haven"])
			n.position = spots.get(st.get("seg", -1), Vector2(1760, 600))
			var ap := "battle/siege_%s_archer.png" % L.siege_faction
			if Assets.has(ap):
				# from the waist up: a cropped copy, not a region (the outline shader inked the hidden legs below the
				# parapet as a dark smudge)
				var img := Assets.tex(ap).get_image()
				img.decompress()
				img = img.get_region(Rect2i(0, 0, img.get_width(), int(img.get_height() * 0.56)))
				s.texture = ImageTexture.create_from_image(img)
				var tsz := Vector2(s.texture.get_size())
				s.centered = true
				s.scale = Vector2.ONE * 0.5
				s.offset = Vector2(0, -tsz.y * 0.5)
				s.remove_meta("anchor_x")
				s.flip_h = true
				s.material = null
				MapView.outline(s, 1.0)
				s.set_meta("home", s.position)
			else:
				s.visible = false
			n.set_meta("top", 60.0)
		return
	n.set_meta("full_scale", s.scale)
	_breathe(n, s.scale)

## Idle breathing about the scale `base` (the scale the poses and a death return to).
func _breathe(n: Node2D, base: Vector2) -> void:
	var s: Sprite2D = n.get_node("Sprite")
	var tw := s.create_tween().set_loops()
	tw.tween_property(s, "scale", base * Vector2(1.0, 1.025), 0.9 + randf() * 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "scale", base, 0.9 + randf() * 0.4).set_trans(Tween.TRANS_SINE)
	n.set_meta("breath", tw)
	n.set_meta("base_scale", base)

## A figure whose wings spread past its hexes draws a little smaller while another stack stands next to it (its
## wings no longer swallow the neighbour), and any figure in a melee of three or more stacks a little smaller; full
## size again in the open.
func _crowd() -> void:
	for k in units:
		var n: Node2D = units[k]
		var st: Dictionary = n.get_node("Badge").st
		if not n.has_meta("full_scale") or not st.get("alive", false) or st.get("machine", false):
			continue
		var full: Vector2 = n.get_meta("full_scale")
		var vis := fig_vis_w(st["id"]) * full.x
		var span := HEX_W * (2.0 if L.is_wide(st) else 1.0)
		var kk := 1.0
		var near := {}
		for c in L.cells(st):
			for h in BattleLogic.neighbors(c):
				var o = L.stack_at(h)
				if o != null and o != st and not o.get("machine", false):
					near[o["uid"]] = true
		if not near.is_empty() and vis > span:
			kk = clampf(span * 0.95 / vis, 0.88, 1.0)
		if near.size() >= 2:  # (in a melee of three or more: every figure a little smaller, each keeps to its hexes)
			kk = minf(kk, 0.9 if near.size() == 2 else 0.84)
		if is_equal_approx(kk, float(n.get_meta("crowd", 1.0))):
			continue
		var was: float = n.get_meta("crowd", 1.0)
		n.set_meta("crowd", kk)
		var br = n.get_meta("breath", null)
		if not (br is Tween and br.is_valid()):
			continue
		var running: bool = br.is_running()
		br.kill()
		var s: Sprite2D = n.get_node("Sprite")
		_breathe(n, full * kk)
		if running:
			s.scale = full * kk
		else:
			s.scale *= kk / was  # (a narrowed pose is showing: it changes size too, and returns to the new size)
			n.get_meta("breath").pause()

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
	var base: Vector2 = n.get_meta("base_scale", s.scale)
	var k := 1.0
	if pose != "" and not pose.begins_with("move") and pose != "dead":
		var cap := HEX_W * (2.15 if L.is_wide(st) else 1.25)
		var vw := fig_vis_w("%s_%s" % [st["id"], pose]) * base.x
		if vw > cap:
			k = maxf(0.78, cap / vw)
	# (the idle breathing animates the scale: it pauses while a narrowed pose shows)
	var br = n.get_meta("breath", null)
	if br is Tween and br.is_valid():
		if k < 1.0:
			br.pause()
			s.scale = base * k
		elif pose == "" and not br.is_running():
			s.scale = base
			br.play()
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

	# the classic combat bar: icon buttons at both ends, a two-line log you can scroll back through in the middle
	var bar := Panel.new()
	bar.position = Vector2(0, BAR_Y)
	bar.size = Vector2(1920, 1080 - BAR_Y)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.04, 0.95)
	st.border_color = UI.GOLD_DARK
	st.border_width_top = 2
	bar.add_theme_stylebox_override("panel", st)
	root.add_child(bar)
	var left := HBoxContainer.new()
	left.position = Vector2(12, BAR_Y + 7)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	var right := HBoxContainer.new()
	right.position = Vector2(1920 - 12 - 3 * BTN.x - 2 * 6, BAR_Y + 7)
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	for e in [["Options", "options", "Combat options (O)", _on_options, left],
			["Surrender", "surrender", "Surrender (U): pay gold to leave the field with your hero and army (only against a hero)", _on_surrender, left],
			["Retreat", "retreat", "Retreat (R): flee with your hero, losing the army", _on_retreat, left],
			["Auto: Off", "auto", "Auto combat (A): the computer fights for you until you turn it off", _on_auto, left],
			["Spells", "spellbook", "Cast a spell (S)", _on_spells, right],
			["Wait", "end_turn", "Wait (W): act later this round", _on_wait, right],
			["Defend", "defend", "Defend (D / Space): +defense until the next turn", _on_defend, right]]:
		var b := UI.button("", e[3])
		b.custom_minimum_size = BTN
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = e[2]
		var ic := UI.icon(Assets.tex("ui/btn_%s.png" % e[1]), BTN - Vector2(14, 10))
		ic.position = Vector2(7, 5)
		ic.size = ic.custom_minimum_size
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		# (unavailable: faded right back, so it can't pass for a darker style of button)
		b.draw.connect(func(): ic.modulate = Color(0.5, 0.48, 0.45, 0.4) if b.disabled else Color.WHITE)
		e[4].add_child(b)
		_btns[e[0]] = b
	_btns["Auto: Off"].toggle_mode = true
	UI.plate_toggle(_btns["Auto: Off"])

	var lx := 12 + 4 * BTN.x + 3 * 6 + 14
	var lw := right.position.x - 14 - lx
	var inset := Panel.new()
	inset.position = Vector2(lx, BAR_Y + 7)
	inset.size = Vector2(lw, BTN.y)
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color(0.03, 0.02, 0.015, 0.9)
	ist.border_color = Color(UI.GOLD_DARK, 0.8)
	ist.set_border_width_all(1)
	ist.set_corner_radius_all(4)
	inset.add_theme_stylebox_override("panel", ist)
	inset.mouse_filter = Control.MOUSE_FILTER_PASS
	inset.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_log(1)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_log(-1))
	root.add_child(inset)
	_log = UI.label("", 19)
	_log.position = inset.position + Vector2(16, 2)
	_log.size = Vector2(lw - 64, BTN.y - 4)
	_log.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_log.clip_text = true
	_log.add_theme_constant_override("line_spacing", -2)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_log)
	for k in 2:  # scroll the log: older (up) and newer (down)
		var a := _LogArrow.new()
		a.up = k == 0
		a.position = inset.position + Vector2(lw - 36, 4 + k * (BTN.y * 0.5 - 2))
		a.size = Vector2(28, BTN.y * 0.5 - 6)
		a.tooltip_text = "Earlier messages" if k == 0 else "Later messages"
		a.pressed.connect(_scroll_log.bind(1 if k == 0 else -1))
		root.add_child(a)
		_log_arrows.append(a)

	_status = UI.label("", 22, UI.GOLD)
	# what a click would do, in the bottom bar in place of the log line (not over the field)
	_status.position = _log.position
	_status.size = _log.size
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status)

	var qc := CenterContainer.new()
	qc.position = Vector2(0, 8)
	qc.size = Vector2(1920, 116)
	qc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(qc)
	var qp := PanelContainer.new()
	qp.custom_minimum_size.x = 1330  # (room for 14 icons and the round mark: the frame doesn't jump between turns)
	qc.add_child(qp)
	_queue_box = HBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 4)
	_queue_box.alignment = BoxContainer.ALIGNMENT_CENTER
	qp.add_child(_queue_box)

func _refresh_queue() -> void:
	for c in _queue_box.get_children():
		c.queue_free()
	var up := L.upcoming(14)
	var this_round := L.order.size() + L.waited.size()
	var slots := 0
	for i in up.size():
		var s: Dictionary = up[i]
		if i == this_round and i > 0:  # where the next round starts (in a card's slot: the frame never changes)
			var m := _RoundMark.new()
			m.num = L.round_num + 1
			m.tooltip_text = "Round %d starts here" % m.num
			m.custom_minimum_size = Vector2(84, 84)
			m.size_flags_vertical = Control.SIZE_SHRINK_END
			_queue_box.add_child(m)
			slots += 1
		if slots >= 14:
			break
		slots += 1
		var q := _QueueIcon.new()
		q.st = s
		q.first = i == 0
		if s.get("tower", false):
			q.tex = Assets.tex("battle/siege_%s_archer.png" % L.siege_faction)
		q.custom_minimum_size = Vector2(110 if i == 0 else 84, 110 if i == 0 else 84)
		_queue_box.add_child(q)
	while slots < 14:  # (an empty slot for each stack the queue is short of)
		var e := Control.new()
		e.custom_minimum_size = Vector2(110 if slots == 0 else 84, 84)
		_queue_box.add_child(e)
		slots += 1

## Adds a line to the combat log (the bar shows the last two; the arrows and the wheel scroll back).
func _set_log(t: String) -> void:
	if t == "" or (_log_hist.size() > 0 and _log_hist[-1] == t):
		return
	_log_hist.append(t)
	_log_scroll = 0
	_show_log()

func _scroll_log(d: int) -> void:
	_log_scroll = clampi(_log_scroll + d, 0, maxi(0, _log_hist.size() - 2))
	_show_log()

func _show_log() -> void:
	var end := _log_hist.size() - _log_scroll
	_log.text = "\n".join(_log_hist.slice(maxi(0, end - 2), end))
	# the older line dimmer, the newest bright (when scrolled back, both read as history)
	_log.add_theme_color_override("font_color", UI.TEXT if _log_scroll == 0 else Color(0.8, 0.74, 0.62))
	if _log_arrows.size() == 2:
		_log_arrows[0].disabled = end <= 2
		_log_arrows[1].disabled = _log_scroll == 0

func _set_status(t: String) -> void:
	_status.text = t
	_log.visible = t == ""

func _refresh_buttons(human_turn: bool) -> void:
	var cur = L.current()
	var side: int = cur["side"] if cur else 0
	_btns["Wait"].disabled = not human_turn or cur == null or cur["waited"]
	_btns["Defend"].disabled = not human_turn
	_btns["Spells"].disabled = not human_turn or not L.can_cast(side)
	_btns["Retreat"].disabled = not human_turn or L.heroes[side] == null
	_btns["Surrender"].disabled = not human_turn or L.heroes[side] == null or L.heroes[1 - side] == null
	_btns["Auto: Off"].set_pressed_no_signal(_auto)

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
	_reset_info()
	_update_info()  # stats may have changed: show the panel under the cursor again, up to date
	_grid.active = s
	for k in units:
		_ring(units[k]).active = k == s["uid"]
		var m: ShaderMaterial = units[k].get_node("Sprite").material
		if m:  # the active unit gets a thick gold outline instead of the ink one
			m.set_shader_parameter("ink", Color(1, 0.82, 0.25, 1) if k == s["uid"] else Color(0.09, 0.06, 0.03, 0.95))
			m.set_shader_parameter("width", 3.0 if k == s["uid"] else 1.2)
	if s.get("machine", false):  # war machines and towers act on their own, for either side
		_busy = true
		_reach = {}
		_grid.reach = {}
		_grid.queue_redraw()
		_refresh_buttons(false)
		await get_tree().create_timer(0.3).timeout
		await _play(L.machine_act(s))
		_next()
		return
	if L.check_fear(s):
		_set_log("%s freeze in fear!" % L._name(s))
		_float_text(Vector2(0, -_top(s) - 10), "Fear!", Color(0.8, 0.65, 1.0), 30, "", 0.0, _unit(s))
		L.finish_turn(s)
		await get_tree().create_timer(0.7).timeout
		_next()
		return
	if L.check_bad_morale(s):
		_set_log("Low morale: %s freeze and lose the turn." % L._name(s))
		_float_text(Vector2(0, -_top(s) - 10), "Low morale", Color(0.7, 0.75, 1.0), 28, "", 0.0, _unit(s))
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
			"wait":  # (the computer waits, as a player may: it acts again at the end of the round)
				if L.do_wait(s):
					_set_log("%s %s." % [L._name(s), "waits" if s["count"] == 1 else "wait"])
				else:
					ev = L.do_defend(s)
			_: ev = L.do_defend(s)
		await _play(ev)
		_next()

func _act(ev: Array) -> void:
	_busy = true
	_reach = {}
	_grid.reach = {}
	_grid.hover = Vector2i(-1, -1)
	_grid.queue_redraw()
	_set_status("")
	_refresh_buttons(false)
	_reset_info()
	var who = L.current()
	await _play(ev)
	if who != null and L.roll_good_morale(who):  # good morale: the same stack acts again
		_float_text(Vector2(0, -_top(who) - 10), "Morale!", Color(1, 0.85, 0.4), 30, "", 0.0, _unit(who))
		_set_log(L.log_lines[-1])
		_log_seen = L.log_lines.size()
		await get_tree().create_timer(0.5).timeout
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
		_update_info()
	elif e is InputEventMouseButton and e.pressed:
		_info_key = ""  # the click hides the panel; it comes back when the mouse moves on
		if e.button_index == MOUSE_BUTTON_LEFT and not _busy:
			_click()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			if _spell != "":
				_spell = ""
				_update_hover()
			else:
				var s = L.stack_at(pos_to_hex(get_viewport().get_canvas_transform().affine_inverse() * e.position))
				if s and not s.get("machine", false):
					ArmyStrip.show_creature_info(self, s["id"], s["count"])
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_A:
		_on_auto()  # (also while something is acting: it takes over from the next turn)
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_G:  # the full hex grid, any time
		GameState.show_grid = not GameState.show_grid
		_grid.queue_redraw()
		for m in _field.get_children():
			if m is _Moat:
				m.queue_redraw()
		_set_log("Hex grid shown." if GameState.show_grid else "Hex grid hidden: only where the active stack can go.")
	elif e is InputEventKey and e.pressed and not e.echo and not _busy:
		match e.keycode:
			KEY_W: _on_wait()
			KEY_U: _on_surrender()
			KEY_O: _on_options()
			KEY_D, KEY_SPACE: _on_defend()
			KEY_S: _on_spells()
			KEY_A: _on_auto()
			KEY_R: _on_retreat()
			KEY_ESCAPE:
				if _spell != "":
					_spell = ""
					_update_hover()

func _modal_open() -> bool:
	var l := get_tree().root.get_node_or_null("ModalLayer")
	return l != null and l.get_child_count() > 0

# ---------------------------------------------------------------------------------------------
# Hover info: stack and hero stats, base value with the battle value (hero, spells, defending) in brackets
# ---------------------------------------------------------------------------------------------
func _update_info() -> void:
	var key := ""
	if not _ended and not _modal_open() and not _auto:  # (in auto combat stacks walk under a resting cursor)
		var st = L.stack_at(_hover) if L.on_field(_hover) else null
		if st:
			key = "s%d" % st["uid"]
		else:
			for side in 2:
				if L.heroes[side] != null and _hero_rects[side].has_point(_mouse):
					key = "h%d" % side
	if key == _info_key:
		return
	_info_key = key
	if key == "":
		HoverInfo.hide_for(self)
	elif key.begins_with("s"):
		var st: Dictionary = L.stack_at(_hover)
		var side := -1 if stand_pos(st).x > 960 else 1
		# beside the stack, clear of the deployment columns (the panel mustn't hide the army you're looking at)
		var edge := stand_pos(st).x + side * (HEX_W * (1.0 if L.is_wide(st) else 0.5) + 30)
		var clear := maxf(edge, X0 + HEX_W * 2.2) if side > 0 else minf(edge, X0 + HEX_W * 11.8)
		HoverInfo.show_for(self, _stack_info(st), 0.25, side, clear)
	else:
		HoverInfo.show_for(self, _hero_info(int(key.substr(1))), 0.25, -1 if key == "h1" else 1)

## Forget the shown panel (the stats changed): the next mouse move builds it again.
func _reset_info() -> void:
	_info_key = ""
	HoverInfo.hide_for(self)

const _UP := Color(0.55, 0.95, 0.5)
const _DOWN := Color(1.0, 0.5, 0.42)

## "base (battle)": the bracket only when they differ, green when better, red when worse.
func _stat_cell(base, now, better := 0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UI.label(str(base), 18))
	if str(now) != str(base):
		if better == 0 and typeof(base) == TYPE_INT:
			better = 1 if now > base else -1
		h.add_child(UI.label("(%s)" % str(now), 18, _UP if better > 0 else (_DOWN if better < 0 else UI.TEXT)))
	return h

func _grid_row(g: GridContainer, label: String, cell: Control) -> void:
	g.add_child(UI.label(label, 18, UI.GOLD))
	g.add_child(cell)

func _stat_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 1)
	return g

const _EFFECT_NAMES := {"disease": "Diseased", "bless": "Blessed", "curse": "Cursed"}
const _SKILL_STEP := {"offense": 10, "archery": 15, "armorer": 7}

func _stack_info(st: Dictionary) -> Control:
	var c := L.cdata(st)
	var mine := _human_controls(st["side"])
	var v := HoverInfo.box("%d %s" % [st["count"], c["plural"] if st["count"] != 1 else c["name"]])
	var hh = L.heroes[st["side"]]
	HoverInfo.line(v, ("Your army" if mine else "Enemy") + ((", led by %s" % hh["name"]) if hh else ""),
		Color(0.6, 0.8, 1.0) if mine else Color(1.0, 0.6, 0.5), 17)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var pic := UI.icon(Assets.creature_portrait(st["id"]), Vector2(132, 132))  # (as tall as the stats beside it)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pic)
	var g := _stat_grid()
	_grid_row(g, "Attack", _stat_cell(c["attack"], L.attack_stat(st)))
	_grid_row(g, "Defense", _stat_cell(c["defense"], L.defense_stat(st)))
	var lo: int = c["dmg"][0]
	var hi: int = c["dmg"][1]
	var dmg := GameData.dmg_text(lo, hi)
	var dnow := dmg
	if st["effects"].has("bless"):
		dnow = GameData.dmg_text(hi, hi)
	elif st["effects"].has("curse"):
		dnow = GameData.dmg_text(lo, lo)
	_grid_row(g, "Damage", _stat_cell(dmg, dnow, 1 if st["effects"].has("bless") else -1))
	_grid_row(g, "Health", _stat_cell(c["hp"], L.max_hp(st)))
	var full: int = L.start_counts.get(st["uid"], st["count"]) * L.max_hp(st)
	_grid_row(g, "Total HP", UI.label("%d / %d" % [L.total_hp(st), full], 18))
	_grid_row(g, "Speed", _stat_cell(c["speed"], L.speed(st)))
	if c["shots"] > 0:
		_grid_row(g, "Shots", UI.label("%d / %d" % [st["shots"], c["shots"]], 18))
	row.add_child(g)
	v.add_child(row)
	# what changes the numbers
	var why := []
	if hh:
		var ha := GameState.hero_stat(hh, "attack")
		var hd := GameState.hero_stat(hh, "defense")
		if ha != 0 or hd != 0:
			why.append("%+d Attack, %+d Defense from %s" % [ha, hd, hh["name"]])
		for sk in ["offense", "archery", "armorer"]:
			var lvl := L.hero_skill(st["side"], sk)
			if lvl <= 0 or (sk == "archery" and c["shots"] == 0):
				continue
			var pct: int = lvl * _SKILL_STEP[sk]
			var what := "-%d%% damage taken" % pct if sk == "armorer" else "+%d%% %s damage" % [pct, "ranged" if sk == "archery" else "melee"]
			why.append("%s (%s)" % [what, GameData.SKILLS[sk]["name"]])
		var lk := L.luck(st["side"])
		if lk != 0:
			why.append("Luck %+d" % lk)
	for e in st["effects"]:
		var nm: String = _EFFECT_NAMES.get(e, GameData.SPELLS[e]["name"] if GameData.SPELLS.has(e) else String(e).capitalize())
		var n: int = st["effects"][e]
		why.append("%s (%d round%s left)" % [nm, n, "" if n == 1 else "s"])
	if st["defending"]:
		why.append("Defending: +20% Defense")
	if c["shots"] > 0:
		why.append("Shooter: half damage in melee and beyond 10 hexes")
	if why.size() > 0:
		HoverInfo.line(v, "\n".join(why), Color(0.85, 0.82, 0.72), 17)
	# (shooting is told above, with its rule)
	var ab: Array = c["abilities"].filter(func(a): return a != "ranged").map(func(a): return GameData.ABILITY_TEXT.get(a, a))
	if ab.size() > 0:
		HoverInfo.line(v, ", ".join(ab), Color(0.75, 0.85, 1.0), 17)
	if st["retaliations"] <= 0:
		HoverInfo.line(v, "No retaliation left this round.", _DOWN, 17)
	if _hover_action.get("target") == st:  # your unit's attack on it: damage and kills (as in the status line)
		HoverInfo.line(v, _status.text, UI.GOLD, 18)
	return v

func _hero_info(side: int) -> Control:
	var hh: Dictionary = L.heroes[side]
	var v := HoverInfo.box(hh["name"])
	HoverInfo.line(v, "Level %d %s" % [hh["level"], hh["class"]], UI.TEXT, 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(UI.icon(Assets.hero_portrait(hh["id"]), Vector2(84, 84)))
	var g := _stat_grid()
	for stat in ["attack", "defense", "power", "knowledge"]:
		_grid_row(g, stat.capitalize(), _stat_cell(int(hh.get(stat, 0)), GameState.hero_stat(hh, stat)))
	_grid_row(g, "Spell points", UI.label("%d / %d" % [hh["mana"], GameState.max_mana(hh)], 18))
	var lk := L.luck(side)
	if lk != 0:
		_grid_row(g, "Luck", UI.label("%+d" % lk, 18))
	row.add_child(g)
	v.add_child(row)
	HoverInfo.line(v, "Every creature in this army gets the hero's Attack and Defense.", Color(0.85, 0.82, 0.72), 17)
	var sk := []
	for k in hh.get("skills", {}):
		var lvl: int = hh["skills"][k]
		if lvl > 0 and GameData.SKILLS.has(k):
			sk.append("%s %s" % [["", "Basic", "Advanced", "Expert"][mini(3, lvl)], GameData.SKILLS[k]["name"]])
	if sk.size() > 0:
		HoverInfo.line(v, "Skills: " + ", ".join(sk), Color(0.75, 0.85, 1.0), 17)
	var arts: Array = hh.get("artifacts", []).map(func(a): return GameData.ARTIFACTS[a]["name"])
	if arts.size() > 0:
		HoverInfo.line(v, "Artifacts: " + ", ".join(arts), Color(1.0, 0.85, 0.5), 17)
	if L.hero_cast[side]:
		HoverInfo.line(v, "Has cast a spell this round.", Color(0.8, 0.75, 0.65), 17)
	return v

func _update_hover() -> void:
	_grid.hover = _hover
	_hover_action = {}
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]) or _modal_open():
		_grid.hover = Vector2i(-1, -1)
		_grid.attack_from = Vector2i(-1, -1)
		_grid.queue_redraw()
		_set_status("")
		return
	var txt := ""
	if _spell != "":
		var sp: Dictionary = GameData.SPELLS[_spell]
		if L.in_bounds(_hover) and L.spell_target_ok(cur["side"], _spell, _hover):
			_hover_action = {"type": "cast", "hex": _hover}
			txt = "Cast %s" % sp["name"]
			var t = L.stack_at(_hover)
			if sp["target"] == "area":
				var hit: Array = L.stacks_on([_hover] + L.neighbors(_hover)).map(func(s): return L._name(s))
				if hit.size() > 0:
					txt += " on %s" % ", ".join(hit) + (" (%d damage each)" % L.spell_damage(cur["side"], _spell) if sp.has("damage") else "")
			elif sp.has("damage") and t:
				txt += " on %s (%d damage)" % [L._name(t), L.spell_damage(cur["side"], _spell)]
		else:
			txt = "Select a target for %s (right click to cancel)" % sp["name"]
	elif L.on_field(_hover):
		var t = L.stack_at(_hover)
		if t and t["side"] != cur["side"]:
			if L.can_shoot(cur):
				var r := L.damage_range(cur, t, true)
				_hover_action = {"type": "shoot", "target": t}
				txt = "Shoot %s (damage %s, kills %s)%s" % [L._name(t), GameData.dmg_text(r[0], r[1]), _kills(t, r),
					"  [half damage: range]" if L.stack_distance(cur, t) > 10 else ""]
			else:
				var from := _attack_from(cur, t)
				if from != Vector2i(-1, -1):
					var moved: int = _reach.get(from, 0)
					var r := L.damage_range(cur, t, false, moved)
					_hover_action = {"type": "melee", "target": t, "from": from}
					txt = "Attack %s (damage %s, kills %s)" % [L._name(t), GameData.dmg_text(r[0], r[1]), _kills(t, r)]
				else:
					txt = "%s — out of reach" % L._name(t)
		elif t and t["side"] == cur["side"]:
			txt = "%d %s" % [t["count"], L._name(t)]
		elif _reach.has(_hover) or (L.is_wide(cur) and _reach.has(_hover - BattleLogic.tail_dir(cur["side"]))):
			_hover_action = {"type": "move", "hex": _hover if _reach.has(_hover) else _hover - BattleLogic.tail_dir(cur["side"])}
			txt = "Move here" if not L.is_flyer(cur) else "Fly here"
	_grid.attack_from = _hover_action.get("from", Vector2i(-1, -1))
	_grid.move_to = _hover_action.get("hex", Vector2i(-1, -1)) if _hover_action.get("type", "") == "move" else Vector2i(-1, -1)
	_grid.queue_redraw()
	_set_status(txt)

func _kills(t: Dictionary, r: Array) -> String:
	var hp: int = L.max_hp(t)
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
		var d := (stand_pos(cur, h) - Vector2(0, 24) - m).length()
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
			_grid.hover = Vector2i(-1, -1)
			_grid.queue_redraw()
			_set_status("")
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
	_btns["Auto: Off"].set_pressed_no_signal(_auto)
	_update_info()
	if _auto and not _busy:
		_next()

func _on_retreat() -> void:
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]) or L.heroes[cur["side"]] == null:
		return
	if await Modal.confirm(self, "Retreat", "Retreat from battle? Your army will be lost, but your hero will survive to be hired again.").closed:
		_retreated = cur["side"]
		_end_battle(1 - cur["side"])

## What surrendering costs a side: the price of every creature still standing in its army (as the classic game).
func _surrender_cost(side: int) -> int:
	var g := 0
	for st in L.stacks:
		if st["side"] == side and st["alive"] and not st.get("machine", false) and not st.get("tower", false):
			g += int(GameData.CREATURES[st["id"]]["cost"].get("gold", 0)) * int(st["count"])
	return g

## Surrender to an enemy hero: pay for the army and leave the field with the hero and all of it; the hero waits in
## the taverns, army and all, to be hired again.
func _on_surrender() -> void:
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]):
		return
	var side: int = cur["side"]
	if L.heroes[side] == null or L.heroes[1 - side] == null:
		return
	var cost := _surrender_cost(side)
	var have := 20000  # (a test battle launched on its own: no kingdom, a starting treasury)
	if not GameState.world.is_empty() and L.players[side] >= 0:
		have = int(GameState.world["players"][L.players[side]]["resources"]["gold"])
	var foe: String = L.heroes[1 - side]["name"]
	if have < cost:
		Audio.sfx("error")
		await Modal.message(self, "Surrender", "%s asks %d gold to let your army go, and you have only %d." % [foe, cost, have]).closed
		return
	if await Modal.confirm(self, "Surrender", "%s will let you leave with your hero and army for %d gold.\nYour treasury holds %d. Accept?" % [foe, cost, have],
			"Pay %d" % cost, "Fight on").closed:
		_retreated = side
		_surrendered = true
		_surrender_gold = cost
		_end_battle(1 - side)

## Combat options (as the classic dialog): the hex grid, and how fast the battle plays.
func _on_options() -> void:
	if _busy and not _auto:
		return
	var m := Modal.custom(self, "Combat Options", 620)
	var grid := CheckBox.new()
	grid.text = "Show the whole hex grid (G)"
	grid.button_pressed = GameState.show_grid
	grid.add_theme_font_size_override("font_size", 22)
	m.body.add_child(grid)
	m.body.add_child(UI.label("Animation speed", 22, UI.GOLD))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	m.body.add_child(row)
	var group := ButtonGroup.new()
	for e in [["Normal", 1.0], ["Fast", 1.5], ["Very fast", 2.0]]:
		var b := Button.new()
		b.text = e[0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = is_equal_approx(GameState.battle_speed, e[1])
		b.custom_minimum_size = Vector2(170, 52)
		b.add_theme_font_size_override("font_size", 21)
		UI.plate_toggle(b)
		var v: float = e[1]
		b.pressed.connect(func(): GameState.battle_speed = v)
		row.add_child(b)
	m.add_buttons([["OK", true]])
	m.set_meta("default", true)
	m.set_meta("cancel", true)
	await m.closed
	if grid.button_pressed != GameState.show_grid:
		GameState.show_grid = grid.button_pressed
		_grid.queue_redraw()
		for n in _field.get_children():
			if n is _Moat:
				n.queue_redraw()
	Engine.time_scale = GameState.battle_speed

func _on_spells() -> void:
	var cur = L.current()
	if _busy or cur == null or not _human_controls(cur["side"]) or not L.can_cast(cur["side"]):
		return
	var side: int = cur["side"]
	var h = L.heroes[side]
	var r = await SpellBook.open(self, h, func(sp): return GameData.SPELLS[sp]["mana"] <= h["mana"],
		func(sp): return ("Now: %d damage." % L.spell_damage(side, sp)) if GameData.SPELLS[sp].has("damage") else "").closed
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
				var keep: Dictionary = _grid.active
				_grid.active = {}  # (it would mark the end of the path before the stack gets there)
				_grid.queue_redraw()
				await _anim_move(ev["s"], ev["path"])
				_grid.active = keep
				_grid.queue_redraw()
			"attack":
				await _anim_attack(ev)
			"spell":
				await _anim_spell(ev)
			"catapult":
				await _anim_catapult(ev)
			"death":
				if not _unit(ev["s"]).has_meta("fallen"):  # (most fall with their blow)
					_anim_death(ev["s"])
					await get_tree().create_timer(0.25).timeout
			"heal":
				_float_text(Vector2(0, -_top(ev["s"]) - 10), "+%d" % ev["amount"], Color(0.5, 1, 0.5), 30, "", 0.0, _unit(ev["s"]))
				_refresh_badge(ev["s"])
			"text":
				_set_log(ev["text"])
	for k in range(_log_seen, L.log_lines.size()):  # every line, not just the last (an attack before a spell)
		_set_log(L.log_lines[k])
	_log_seen = L.log_lines.size()
	for k in units:
		units[k].get_node("Badge").queue_redraw()

## Shows the log up to an attack / spell event's own line: called as its blow lands, with its label and new count.
func _flush_log(ev: Dictionary) -> void:
	if ev.has("log"):
		for k in range(_log_seen, mini(int(ev["log"]), L.log_lines.size())):
			_set_log(L.log_lines[k])
		_log_seen = maxi(_log_seen, int(ev["log"]))

func _anim_move(st: Dictionary, path: Array) -> void:
	var n := _unit(st)
	var spr: Sprite2D = n.get_node("Sprite")
	var cycle := Assets.has("creatures/%s_move0.png" % st["id"])  # 4-frame walk / flap / gallop (tools/art/cycle_paint.py)
	if L.is_flyer(st):
		Audio.sfx("wings", -4)
		var target := stand_pos(st, path[path.size() - 1])
		if absf(target.x - n.position.x) > 2:
			_set_flip(spr, target.x < n.position.x)
		var dur := clampf(n.position.distance_to(target) / 700.0, 0.45, 1.1)
		var tw := n.create_tween()
		tw.tween_property(n, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var tw2 := spr.create_tween()
		tw2.tween_property(spr, "position:y", -60.0, dur * 0.5).set_ease(Tween.EASE_OUT)
		tw2.tween_property(spr, "position:y", 0.0, dur * 0.5).set_ease(Tween.EASE_IN)
		if cycle:
			_play_cycle(st, dur, 11.0)
		await tw.finished
	else:
		var step := 0.2 if cycle else 0.13
		var frame := 0
		for i in range(1, path.size()):
			var target := stand_pos(st, path[i])
			if absf(target.x - n.position.x) > 2:
				_set_flip(spr, target.x < n.position.x)
			Audio.sfx("move_step", -10, 0.15)
			var tw := n.create_tween()
			tw.tween_property(n, "position", target, step)
			if cycle:  # two frames of the cycle per hex
				_pose(st, "move%d" % (frame % 4))
				get_tree().create_timer(step * 0.5).timeout.connect(_pose.bind(st, "move%d" % ((frame + 1) % 4)))
				frame += 2
			var bob := spr.create_tween()  # a small step bob per hex
			bob.tween_property(spr, "position:y", -5.0 if cycle else -7.0, step * 0.5).set_ease(Tween.EASE_OUT)
			bob.tween_property(spr, "position:y", 0.0, step * 0.5).set_ease(Tween.EASE_IN)
			await tw.finished
	if cycle:
		_pose(st, "")
	_set_flip(spr, st["side"] == 1)
	_face_enemies(st)

## Loop the unit's 4 movement frames for `dur` seconds at `fps` (flyers).
func _play_cycle(st: Dictionary, dur: float, fps: float) -> void:
	var count := maxi(4, int(dur * fps))
	for i in count:
		get_tree().create_timer(i / fps).timeout.connect(func():
			if st.get("alive", false):
				_pose(st, "move%d" % (i % 4)))

func _face_enemies(st: Dictionary) -> void:
	# Face the nearest enemy horizontally.
	var n := _unit(st)
	var best = null
	var bd := 1e9
	for e in L.alive_stacks(1 - st["side"]):
		var d := L.stack_distance(st, e)
		if d < bd:
			bd = d
			best = e
	if best:
		_set_flip(n.get_node("Sprite"), stand_pos(best).x < stand_pos(st).x)

func _anim_attack(ev: Dictionary) -> void:
	var a: Dictionary = ev["a"]
	var d: Dictionary = ev["d"]
	var na := _unit(a)
	var nd := _unit(d)
	var spr: Sprite2D = na.get_node("Sprite")
	_set_flip(spr, nd.position.x < na.position.x)
	var dir := (nd.position - na.position).normalized()
	var big: bool = ev["killed"] > 0 or L.cdata(a)["tier"] >= 6
	var home: Vector2 = spr.get_meta("home", Vector2.ZERO)
	if ev["ranged"]:
		_pose(a, "attack", 0.55)
		var proj := _Projectile.new()
		proj.kind = "magic" if GameData.base_of(a["id"]) in ["monk", "lich"] else "arrow"
		proj.from = na.position + Vector2(0, -_top(a) * 0.6)
		proj.to = nd.position + Vector2(0, -60)
		_fx.add_child(proj)
		Audio.sfx("magic_arrow" if proj.kind == "magic" else "arrow_shot", -2)
		var tw := spr.create_tween()  # recoil
		tw.tween_property(spr, "position", home - dir * 10, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "position", home, 0.25).set_trans(Tween.TRANS_SINE)
		await proj.fly(0.28)
		Audio.sfx("magic_hit" if proj.kind == "magic" else "arrow_hit", -2)
	else:
		# wind-up: draw back and lean away
		var lean := signf(dir.x) if dir.x != 0.0 else 1.0
		var tw := spr.create_tween().set_parallel(true)
		tw.tween_property(spr, "position", home - dir * 14, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "rotation", -0.07 * lean, 0.13)
		await tw.finished
		# strike in the attack pose
		_pose(a, "attack", 0.45)
		var tw2 := spr.create_tween().set_parallel(true)
		tw2.tween_property(spr, "position", home + dir * 24, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw2.tween_property(spr, "rotation", 0.05 * lean, 0.08)
		await tw2.finished
		Audio.creature_sfx(a["id"], "attack", "claw_hit" if GameData.base_of(a["id"]) in ["griffin", "bone_dragon", "ghost", "vampire"] else ("blunt_hit" if GameData.base_of(a["id"]) in ["zombie", "monk"] else "sword_hit"))
		_hit_flash(d, dir, big)
		await get_tree().create_timer(0.07).timeout  # hit-stop: let the blow land
		var tw3 := spr.create_tween().set_parallel(true)
		tw3.tween_property(spr, "position", home, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw3.tween_property(spr, "rotation", 0.0, 0.24)
	if ev["ranged"]:
		_hit_flash(d, dir, big)
	if big:
		_shake(7.0 if ev["killed"] > 0 else 4.0)
	var txt := "-%d" % ev["dmg"]
	if ev["lucky"]:
		txt = "Lucky! " + txt
	_flush_log(ev)
	_damage_text(d, txt, ev["killed"], ev["lucky"])
	_refresh_badge(d)
	if not d["alive"]:
		_anim_death(d)
	await get_tree().create_timer(0.3).timeout

## Red flash + hit pose; with a direction the unit is knocked back and springs home, otherwise it shudders.
func _hit_flash(d: Dictionary, dir := Vector2.ZERO, big := false) -> void:
	if d.get("alive", false):
		_pose(d, "hit", 0.45)
	var nd := _unit(d)
	var s: Sprite2D = nd.get_node("Sprite")
	var tw := s.create_tween()
	tw.tween_property(s, "modulate", Color(1.4, 1.25, 1.2), 0.05)
	tw.tween_property(s, "modulate", Color.WHITE, 0.22)
	var home: Vector2 = s.get_meta("home", Vector2.ZERO)
	var tw2 := s.create_tween()
	if dir != Vector2.ZERO:
		var push := Vector2(dir.x, dir.y * 0.4).normalized() * (22.0 if big else 14.0)
		tw2.set_parallel(true)
		tw2.tween_property(s, "position", home + push, 0.07).set_ease(Tween.EASE_OUT)
		tw2.tween_property(s, "rotation", 0.06 * signf(push.x), 0.07)
		tw2.chain().tween_property(s, "position", home, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw2.parallel().tween_property(s, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	else:
		for i in 3:
			tw2.tween_property(s, "position:x", home.x + (6 if i % 2 == 0 else -6), 0.04)
		tw2.tween_property(s, "position:x", home.x, 0.04)

## Short screen shake for heavy blows (the UI layer stays put).
func _shake(strength: float) -> void:
	var tw := create_tween()
	for i in 6:
		var k := strength * (1.0 - i / 6.0)
		tw.tween_property(self, "position", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.035)
	tw.tween_property(self, "position", Vector2.ZERO, 0.04)

func _anim_death(st: Dictionary) -> void:
	var n := _unit(st)
	if n.has_meta("fallen"):
		return
	n.set_meta("fallen", true)
	var c := L.cdata(st)
	Audio.creature_sfx(st["id"], "death", "death_undead" if "undead" in c["abilities"] else ("death_beast" if GameData.base_of(st["id"]) in ["griffin"] else "death_human"))
	var s: Sprite2D = n.get_node("Sprite")
	n.get_node("Badge").visible = false
	_ring(n).on = false
	_drop_from_queue(st)
	if n.has_meta("breath"):
		n.get_meta("breath").kill()
		s.scale = n.get_meta("base_scale")
	if st.get("tower", false):  # a tower's crew falls with its tower: gone, no body left on the ruin
		s.create_tween().tween_property(s, "modulate:a", 0.0, 0.4)
		return
	# (a negative z_index would hide the body behind the battlefield background)
	n.reparent(_corpses)
	if _pose(st, "dead"):
		# the corpse stays on its hex, a little darker, as in the classics: it drops in with a puff of dust
		s.modulate = Color(1.6, 0.7, 0.7)
		s.rotation = 0.0
		var home: Vector2 = s.get_meta("home", Vector2.ZERO)
		s.position = home + Vector2(0, -16)
		var tw0 := s.create_tween().set_parallel(true)
		tw0.tween_property(s, "modulate", Color(0.5, 0.5, 0.5), 0.5)  # (dark: never read as a living stack)
		var cm := s.material as ShaderMaterial
		if cm:  # (and grey, low in contrast: the classic's dull heaps)
			cm.set_shader_parameter("saturation", 0.25)
		tw0.tween_property(s, "position", home, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var dust := _Dust.new()
		dust.position = n.position + Vector2(0, -4)
		dust.big = "two_hex" in c["abilities"]
		_fx.add_child(dust)
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
		_flush_log(ev)  # (its log line with its banner, not only when it lands)
	var targets: Array = ev["targets"]
	var centers := []
	var area: bool = sp == "death_cloud" or (GameData.SPELLS.has(sp) and GameData.SPELLS[sp]["target"] == "area")
	if area:  # one effect sized to the blast (a hex and its ring), not one more over every target
		centers.append(hex_pos(ev["hex"]) + Vector2(0, -24))
	else:
		for t in targets:
			centers.append(_unit(t).position + Vector2(0, -70))
	var fx: String = FX_OF.get(sp, "arcane")
	for c in centers:
		var p: Vector2 = c
		if sp == "lightning_bolt":
			var burst := _Burst.new()  # the bolt from the sky; the painted sparks are the impact, at the feet
			burst.bolt = true
			burst.slant = 1.0 if (c.x > 960 and c.x < 1400) or c.x < 560 else -1.0  # (clear of the name plates)
			burst.position = c + Vector2(0, 62)
			_rings.add_child(burst)  # (behind the figures: the bolt passes behind the stacks between it and the sky)
			p = c + Vector2(0, 40)
		if fx == "holy":
			p += Vector2(0, -20)  # a column rising from the feet: its ring sits at the bottom of the frame
		if area:
			# in the field's depth order, just in front of the blast's last row: stacks further forward stand over it
			var layer := Node2D.new()
			layer.position = Vector2(p.x, hex_pos(ev["hex"]).y + ROW_STEP + 1)
			_sorted.add_child(layer)
			_play_fx(fx, p - layer.position, Vector2(1.3, 0.95), 1.1, 1.0, layer)
			get_tree().create_timer(1.3).timeout.connect(layer.queue_free)
		else:
			_play_fx(fx, p, Vector2.ONE * (0.75 if fx == "spark" else 0.95), 0.8, 0.5 if fx == "spark" else 1.0)
	await get_tree().create_timer(0.35).timeout
	_flush_log(ev)
	for t in targets:
		if ev["dmg"].has(t["uid"]):
			_hit_flash(t)
			_damage_text(t, "-%d" % ev["dmg"][t["uid"]], ev["killed"].get(t["uid"], 0), false, targets.find(t) * 0.14)
			_refresh_badge(t)
			if not t["alive"]:
				_anim_death(t)
		else:
			var s: Sprite2D = _unit(t).get_node("Sprite")
			var tw := s.create_tween()
			tw.tween_property(s, "modulate", col.lightened(0.5) * 1.25, 0.15)
			tw.tween_property(s, "modulate", Color.WHITE, 0.4)
	await get_tree().create_timer(0.45).timeout

## Painted spell effects (assets/battle/fx_<name>.png, 4x4 flipbooks on black, drawn additively).
const FX_OF := {"fireball": "fire", "meteor_shower": "fire", "frost_ring": "frost", "ice_bolt": "frost",
	"lightning_bolt": "spark", "magic_arrow": "arcane", "bless": "holy", "cure": "holy", "resurrection": "holy",
	"shield": "holy", "stone_skin": "holy", "haste": "holy", "curse": "dark", "slow": "dark", "weakness": "dark",
	"death_ripple": "dark", "death_cloud": "dark"}

func _play_fx(fx: String, p: Vector2, sc: Vector2, dur := 0.8, alpha := 1.0, parent: Node2D = null) -> void:
	if not Assets.has("battle/fx_%s.png" % fx):
		return
	var s := Sprite2D.new()
	s.texture = Assets.tex("battle/fx_%s.png" % fx)
	s.hframes = 4
	s.vframes = 4
	s.position = p
	s.scale = sc
	s.modulate.a = alpha  # (additive: lower alpha is a fainter glow, the figures show through)
	s.z_index = 0 if parent else 25
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	(parent if parent else _fx).add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "frame", 15, dur)
	tw.tween_callback(s.queue_free)

# ---------------------------------------------------------------------------------------------
# Siege
# ---------------------------------------------------------------------------------------------
# The wall, moat, towers and keep are painted into the siege backdrop (tools/art/siege_wall_paint.py); a breached
# segment shows its band of the ruined painting, a cracked one painted cracks.
var _wall_layer: Node2D
var _ruins: Array = []     # per wall segment: the overlay of its ruin (hidden while it stands)
var _cracks: _Cracks
## The band of the screen (y) each wall segment owns in the painting (as tools/art/siege_wall_paint.py BANDS).
const WALL_BANDS := [[0, 270], [270, 400], [400, 470], [470, 645], [645, 750], [750, 885], [885, 1080]]
## Where each arrow tower's crew stands on the painted towers (by wall segment; -1: the keep).
const ARCHER_SPOTS := {
	"haven": {0: Vector2(1300, 418), 6: Vector2(1338, 800), -1: Vector2(1742, 660)},
	"necropolis": {0: Vector2(1300, 418), 6: Vector2(1338, 800), -1: Vector2(1742, 660)},
}

func _build_walls() -> void:
	var mp := Assets.path("battle/siege.json")  # (where each segment's ruin overlay sits, from the paint script)
	var meta = JSON.parse_string(FileAccess.get_file_as_string(mp)) if FileAccess.file_exists(mp) else null
	var spots: Array = meta.get(L.siege_faction, []) if meta is Dictionary else []
	for i in L.walls.size():
		var s := Sprite2D.new()
		var p := "battle/siege_%s_ruin_%d.png" % [L.siege_faction, i]
		if Assets.has(p) and i < spots.size():
			s.texture = Assets.tex(p)
			s.centered = false
			s.position = Vector2(spots[i][0], spots[i][1])
		s.visible = false
		_wall_layer.add_child(s)
		_ruins.append(s)
	_cracks = _Cracks.new()
	_cracks.b = self
	_wall_layer.add_child(_cracks)
	for i in L.walls.size():  # (labels keep off the standing wall)
		var r: Array = L.walls[i]["rows"]
		var top := hex_pos(Vector2i(BattleLogic.WALL_X, r[0])).y - 150
		var bot := hex_pos(Vector2i(BattleLogic.WALL_X, r[-1])).y + 20
		_obstacle_rects.append(Rect2(1290, top, 110, bot - top))

## Shows a wall segment intact or breached.
func _set_wall(i: int, broken: bool) -> void:
	if i < _ruins.size() and _ruins[i].texture:
		var s: Sprite2D = _ruins[i]
		s.visible = broken
		if broken:
			s.modulate.a = 0.0
			s.create_tween().tween_property(s, "modulate:a", 1.0, 0.25)
	# a crew stood where this breach tears the stone out: the lower tower's up to its parapet, the upper tower's (on
	# the gatehouse battlements) up into the tower's window
	var moves := {5: [6, Vector2(1338, 758)], 2: [0, Vector2(1337, 232)]}
	if broken and moves.has(i):
		for st in L.stacks:
			if st.get("tower", false) and st.get("seg", -1) == moves[i][0] and units.has(st["uid"]):
				units[st["uid"]].position = moves[i][1]
	_cracks.queue_redraw()

## The catapult's boulder: a high arc onto a wall segment; a hit throws up dust, a breach turns it to rubble.
func _anim_catapult(ev: Dictionary) -> void:
	var n := _unit(ev["s"])
	var band: Array = WALL_BANDS[ev["seg"]]
	var to := Vector2(1340, maxf(210.0, (band[0] + band[1]) * 0.5))  # (the painted wall's face)
	if not ev["hit"]:
		to += Vector2(-HEX_W * 0.9, 50)  # short: into the moat
	var spr: Sprite2D = n.get_node("Sprite")
	var tw := spr.create_tween()
	tw.tween_property(spr, "rotation", 0.12, 0.12)
	tw.tween_property(spr, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK)
	Audio.sfx("arrow_shot", -2)
	var rock := _Boulder.new()
	rock.from = n.position + Vector2(20, -90)
	rock.to = to
	_fx.add_child(rock)
	await rock.fly(0.75)
	_flush_log(ev)
	Audio.sfx("blunt_hit", 0)
	var dust := _Dust.new()
	dust.position = to + Vector2(0, 40)
	dust.big = true
	_fx.add_child(dust)
	if ev["hit"]:
		_shake(8.0 if ev["destroyed"] else 4.0)
		if ev["destroyed"]:
			_set_wall(ev["seg"], true)
			for k in 2:
				var d2 := _Dust.new()
				d2.position = to + Vector2(randf_range(-40, 40), 50 + k * 20)
				d2.big = true
				_fx.add_child(d2)
		else:  # cracked
			_cracks.queue_redraw()
	await get_tree().create_timer(0.35).timeout

## A slain stack leaves the turn queue at once (not with the next turn).
func _drop_from_queue(st: Dictionary) -> void:
	# the cards after it move up and an empty slot pads the end (the frame keeps its width); if it was the head,
	# the next card becomes the big one
	for q in _queue_box.get_children():
		if q is _QueueIcon and q.st["uid"] == st["uid"] and not q.is_queued_for_deletion():
			var w: float = q.custom_minimum_size.x
			_queue_box.remove_child(q)
			q.queue_free()
			if q.first:
				for n in _queue_box.get_children():
					if n is _QueueIcon:
						n.first = true
						n.custom_minimum_size = Vector2(110, 110)
						n.queue_redraw()
						w = 84.0
						break
			var e := Control.new()
			e.custom_minimum_size = Vector2(w, 84)
			_queue_box.add_child(e)

func _refresh_badge(st: Dictionary) -> void:
	var n := _unit(st)
	if n:
		n.get_node("Badge").queue_redraw()
	for q in _queue_box.get_children():
		q.queue_redraw()
	if not st["alive"]:
		_drop_from_queue(st)
		if n:
			var m = n.get_node("Sprite").material
			if m is ShaderMaterial:
				m.set_shader_parameter("ink", Color(0.09, 0.06, 0.03, 0.95))
			_ring(n).active = false
	if _info_key == "s%d" % st["uid"]:  # its hover panel shows the old numbers: rebuild it
		_reset_info()
		_update_info()

## Damage to a stack: one compact label, "-45  2 slain", at its feet behind the figure (opposite its count badge, away
## from the enemy that struck it) and moving with it, so it can't be read as another stack's.
func _damage_text(d: Dictionary, txt: String, killed: int, lucky := false, delay := 0.0) -> void:
	var n := _unit(d)
	var home: Vector2 = n.get_node("Badge").get_meta("home")
	_float_text(Vector2.ZERO, txt, Color(1, 0.85, 0.3) if lucky else Color(1, 0.95, 0.85), 34,
		("%d slain" % killed) if killed > 0 else "", delay, n, Vector2(-home.x, home.y), -1 if d["side"] == 0 else 1)

## Keeps count badges of neighbouring stacks from touching ("2" and "4" side by side read as "24"): a badge that
## would overlap one placed before it steps aside toward its own stack.
func _settle_badges() -> void:
	var placed: Array = []
	var keys := units.keys()
	keys.sort()
	var bodies := []  # [unit, the middle of its figure, waist to chest]: a plate there reads as that stack's
	for k in keys:
		var n: Node2D = units[k]
		if n.visible and n.get_node("Badge").st.get("alive", false):
			var top := float(n.get_meta("top", 120.0))
			var hw := HEX_W * (0.4 if L.is_wide(n.get_node("Badge").st) else 0.25)
			bodies.append([n, Rect2(n.position.x - hw, n.position.y - top * 0.85, hw * 2.0, top * 0.85 - 18.0)])
	for k in keys:
		var n: Node2D = units[k]
		var b: Node2D = n.get_node("Badge")
		if not b.visible or not b.st.get("alive", false):
			continue
		var home: Vector2 = b.get_meta("home")
		# (as the classic plates: with another stack on the hex in front, the plate moves in under its own figure, so
		# two facing stacks' plates never sit side by side between them; a stack on a front diagonal stands there too)
		var st: Dictionary = b.st
		var corner := home
		if st.has("hex") and not st.get("tower", false):
			var fx := 1.0 if st["side"] == 0 else -1.0
			var hp := hex_pos(st["hex"])
			for h in BattleLogic.neighbors(st["hex"]):
				if (hex_pos(h).x - hp.x) * fx <= 0.0:
					continue
				var o = L.stack_at(h)
				if o != null and o != st:
					home = Vector2(home.x - 40.0 * signf(home.x), home.y + 16.0)
					break
		# (an enemy badge facing it read as one number, "2 6"; one on another stack's figure read as that stack's):
		# its usual corner, else the other side, else lower down at its feet, else further out; the first that is clear
		# (as the classic plates: always at the front corner of the stack's own hex; only a plate it would touch
		# moves it, a little lower)
		var spots := [home, home + Vector2(0, 22)]
		if corner != home:  # (moved in, unless that lands on another stack's figure: then back at its ring corner)
			spots = [home, corner, home + Vector2(0, 22), corner + Vector2(0, 22)]
		# (last, the back corner of its own ring: the free side, when another figure covers the front one)
		spots.append(Vector2(-corner.x, corner.y))
		spots.append(Vector2(-corner.x, corner.y + 22))
		# (and in a crowd, where a figure in front covers its feet: up on its own figure, beside its legs)
		for up in [-54.0, -76.0]:
			spots.append(Vector2(corner.x * 0.6, up))
			spots.append(Vector2(-corner.x * 0.6, up))
		spots.append(Vector2(corner.x * 1.3, -30))
		spots.append(Vector2(-corner.x * 1.3, -30))
		var hit := func(q: Rect2) -> float:
			var c := 0.0
			for o in placed:
				if q.grow(4).intersects(o):
					c += 1000.0
			for f in bodies:
				if f[0] != n and q.intersects(f[1]):
					c += 300.0
			return c
		var r := Rect2(n.position + home - Vector2(24, 14), Vector2(48, 28))
		var best := INF
		for j in spots.size():
			var q := Rect2(n.position + spots[j] - Vector2(24, 14), Vector2(48, 28))
			var c: float = hit.call(q) + j * 20.0  # (ties keep the usual corner)
			if c < best:
				best = c
				r = q
		for i in 3:
			var moved := false
			for o in placed:
				if r.intersects(o):
					# aside, toward its own stack
					if n.position.x >= o.get_center().x:
						r.position.x = o.end.x + 6
					else:
						r.position.x = o.position.x - r.size.x - 6
					moved = true
			if not moved:
				break
		placed.append(r)
		b.position = r.position + Vector2(24, 14) - n.position

func _process(_d: float) -> void:
	_follow_rings()
	if _grid and _grid.hover.x >= 0 and _modal_open():  # (a window is up: no hex lit under it)
		_update_hover()
	_crowd()
	_settle_badges()
	_see_through()
	_under_figures()

func _ring(n: Node2D) -> _Shadow:
	return n.get_meta("shadow")

## The rings live on their own layer under the figures: each follows its stack (moving, flying, fading).
func _follow_rings() -> void:
	for k in units:
		var n: Node2D = units[k]
		var r := _ring(n)
		r.global_position = n.global_position
		r.visible = r.on and n.is_visible_in_tree()
		r.modulate.a = n.modulate.a

## Where a figure in front rises well over a stack standing behind it (the row above), it turns see-through around
## that stack's feet: the one behind keeps its ring, legs and badge readable instead of seeming to stand on the other.
## The stack in play (the active one, the one under the pointer, one being struck) shows whole: a figure that covers
## much of it fades evenly over its whole body (never one in play itself).
func _see_through() -> void:
	var focus := {}
	var cur = L.current()
	if cur != null:
		focus[cur["uid"]] = true
	var hs = L.stack_at(_hover) if _hover.x >= 0 else null
	if hs != null:
		focus[hs["uid"]] = true
	var now := Time.get_ticks_msec()
	var info := []
	for k in units:
		var n: Node2D = units[k]
		if n.get_node("Badge").st.get("alive", false):
			if _ring(n).hit_until > now:
				focus[k] = true
			info.append([n, n.global_position, float(n.get_meta("top", 120.0)), HEX_W * (0.95 if L.is_wide(n.get_node("Badge").st) else 0.5), focus.has(k),
				cur != null and cur["uid"] == k])
	for k in units:
		var n: Node2D = units[k]
		var holes := PackedVector4Array()
		var fade := 1.0
		for f in info:
			if f[0] != n:
				continue
			for bk in info:
				var dy: float = f[1].y - bk[1].y
				# (a much bigger figure just behind the stack whose turn it is: its wings and body fill the space
				# around that stack's figure, which drowned in them; it fades too)
				if bk != f and bk[5] and not f[4] and -dy >= 20.0 and -dy < bk[2] * 0.9 and f[2] > bk[2] * 1.15 \
						and absf(f[1].x - bk[1].x) < (f[3] + bk[3]) * 0.6:
					fade = 0.55
					continue
				if bk == f or dy < 20.0 or f[2] - dy < 36.0 or absf(f[1].x - bk[1].x) > (f[3] + bk[3]) * 0.75:
					continue
				if bk[4] and not f[4]:
					# (it covers a good part of the stack in play: well up its body and across its middle)
					if f[2] - dy >= 0.3 * bk[2] and absf(f[1].x - bk[1].x) < (f[3] + bk[3]) * 0.7:
						fade = 0.55
				elif holes.size() < 4:
					holes.append(Vector4(bk[1].x, bk[1].y - 26.0, bk[3] * 0.95, 52.0))
		var m := n.get_node("Sprite").material as ShaderMaterial
		if m == null:
			continue
		# the stack whose turn it is: a bright halo pulsing outside its gold outline (as the classic's pulsing
		# outline), so it stands out in a crowd too
		var act: bool = cur != null and cur["uid"] == k
		if act:
			m.set_shader_parameter("team", Color(1.0, 0.93, 0.6, 0.55 + 0.4 * sin(now * 0.006)))
		if n.get_meta("lit", false) != act:
			n.set_meta("lit", act)
			if not act:
				m.set_shader_parameter("team", Color(0, 0, 0, 0))
		var was: float = n.get_meta("body_alpha", 1.0)
		var to := move_toward(was, fade, get_process_delta_time() * 4.0)
		if to != was:
			n.set_meta("body_alpha", to)
			m.set_shader_parameter("body_alpha", to)
		var key := str(holes)
		if n.get_meta("holes_key", "") == key:
			continue
		n.set_meta("holes_key", key)
		m.set_shader_parameter("hole_count", holes.size())
		while holes.size() < 4:
			holes.append(Vector4(0, 0, 1, 1))
		m.set_shader_parameter("holes", holes)

## A low obstacle (a thorn bush, boulders) lies on the ground under the figures: where a figure standing in front rises
## over it (a lance, a wing, a head) the obstacle fades, so it never seems to sit on the figure (a bush on a lance tip).
func _under_figures() -> void:
	for o in _low_obstacles:
		var s: Sprite2D = o[0]
		var r: Rect2 = o[1]
		var to := 1.0
		for k in units:
			var n: Node2D = units[k]
			if not n.visible or not n.get_node("Badge").st.get("alive", false) or n.position.y <= r.end.y - 4.0:
				continue
			var hw := HEX_W * (0.45 if L.is_wide(n.get_node("Badge").st) else 0.3)
			var fig := Rect2(n.position.x - hw, n.position.y - float(n.get_meta("top", 120.0)), hw * 2.0, float(n.get_meta("top", 120.0)) - 30.0)
			if fig.intersects(r):
				to = 0.6
				break
		s.modulate.a = move_toward(s.modulate.a, to, get_process_delta_time() * 3.0)

## A floating label at `p` (field space), or, with `follow`, beside the point `at` of that unit (toward `dir`) and
## moving with it.
func _float_text(p: Vector2, t: String, col: Color, size := 30, sub := "", delay := 0.0, follow: Node2D = null,
		at := Vector2.ZERO, dir := 0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var box := PanelContainer.new()
	var bg := StyleBoxFlat.new()  # soft dark backing so numbers stay readable over busy sprites
	bg.bg_color = Color(0.05, 0.03, 0.02, 0.72) if follow else Color(0, 0, 0, 0.42)
	bg.set_corner_radius_all(8)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	box.add_theme_stylebox_override("panel", bg)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for part in [[t, size, col], [sub, 22, Color(1, 0.88, 0.72)]]:
		if part[0] == "":
			continue
		var l := Label.new()
		l.text = part[0]
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UI.title_font())
		l.add_theme_font_size_override("font_size", part[1])
		l.add_theme_color_override("font_color", part[2])
		l.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.0, 1.0))
		l.add_theme_constant_override("outline_size", 9 if part[1] > 26 else 6)
		row.add_child(l)
	box.z_index = 50 if follow else 30  # (over spell effects, which draw at 45; under count badges at 60)
	(follow if follow else _fx).add_child(box)
	box.reset_size()
	var origin: Vector2 = follow.position if follow else Vector2.ZERO
	var r := Rect2(p - Vector2(box.size.x * 0.5, 0), box.size)
	var now := Time.get_ticks_msec()
	_floats = _floats.filter(func(o): return is_instance_valid(o) and now - int(o.get_meta("born")) < 1500)
	if follow and dir != 0:
		r = _label_spot(follow, origin, at, dir, box.size)
	elif follow:
		r.position += origin
	# don't land on a label that just appeared or on another stack's count badge: step aside (outward from the stack
	# for a damage label), never up into the next row where it would read as that stack's
	var step := dir if dir != 0 else (1 if p.x < 960 else -1)
	for k in (0 if follow and dir != 0 else 4):
		var hit = null
		for o in _floats:
			if r.intersects(o.get_meta("float_rect").grow(-2)):
				hit = o.get_meta("float_rect")
		for u in units:
			var b: Node2D = units[u].get_node("Badge")
			if units[u] != follow and b.visible and b.st.get("alive", false):
				var br := Rect2(units[u].position + b.position - Vector2(20, 13), Vector2(40, 26))
				if r.intersects(br):
					hit = br
		if hit == null:
			break
		r.position.x = hit.end.x + 4 if step > 0 else hit.position.x - r.size.x - 4
	box.set_meta("float_rect", r)
	box.set_meta("born", now)
	_floats.append(box)
	box.position = r.position - origin
	if follow and dir != 0:
		var tip := _LabelTip.new()
		tip.color = Color(0.85, 0.3, 0.25) if dir < 0 else Color(0.35, 0.5, 1.0)
		var sh = follow.get_meta("shadow", null)
		if sh:
			sh.hit_until = Time.get_ticks_msec() + 1200  # (its ring flashes: the label is this stack's, in a crowd too)
		tip.position = Vector2(box.size.x * 0.5, box.size.y)
		if r.end.x < origin.x - 8:  # left of the stack: points right
			tip.side = 1
			tip.rotation = -PI * 0.5
			tip.position = Vector2(box.size.x, box.size.y * 0.5)
		elif r.position.x > origin.x + 8:
			tip.side = -1
			tip.rotation = PI * 0.5
			tip.position = Vector2(0, box.size.y * 0.5)
		box.add_child(tip)
		# a leader from the pointer to the figure's chest, when the label had to sit off it (higher up or aside)
		var chest: Vector2 = origin + Vector2(0, -float(follow.get_meta("top", 120.0)) * 0.7)
		tip.reach = chest - (r.position + tip.position)
		bg.border_color = tip.color
		bg.set_border_width_all(2)
	var tw := box.create_tween().set_parallel(true)
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(0.6, 0.6)
	tw.tween_property(box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "position:y", box.position.y - (6 if dir != 0 else 40), 1.3).set_ease(Tween.EASE_OUT)
	# (then gone at once, as a log line is replaced: a fading plate turned into a half-seen smear over the next stack)
	tw.tween_callback(box.queue_free).set_delay(1.2)

## Where a damage label for the stack of `n` goes: centred over its head, or higher up the same column when another
## stack, badge or label is there, else beside its head; the first spot that covers nothing, else the one that covers
## least.
func _label_spot(n: Node2D, origin: Vector2, at: Vector2, dir: int, sz: Vector2) -> Rect2:
	var top: float = n.get_meta("top", 120.0)
	var cands := []
	for k in 3:  # over the head, then higher up the same column
		cands.append(Rect2(origin + Vector2(-sz.x * 0.5, -top - sz.y - 6 - k * 30.0), sz))
	# beside the head, pointing in at it (never over its own body: the label hid the figure)
	var own_half := HEX_W * (0.7 if L.is_wide(n.get_node("Badge").st) else 0.36)
	var hy := -top * 0.8 - sz.y * 0.5
	cands.append(Rect2(origin + Vector2(own_half + 14, hy), sz))
	cands.append(Rect2(origin + Vector2(-own_half - 14 - sz.x, hy), sz))
	var blocks := []
	for u in units:
		var o: Node2D = units[u]
		var b: Node2D = o.get_node("Badge")
		if not b.st.get("alive", false):
			continue
		if o != n:
			var half := HEX_W * (0.95 if L.is_wide(b.st) else 0.45)
			var t: float = o.get_meta("top", 120.0)
			blocks.append(Rect2(o.position.x - half, o.position.y - t, half * 2, t + 10))
		var br := Rect2(o.position + b.position - Vector2(20, 13), Vector2(40, 26))
		for k in 3:  # (a badge under a label read as part of it: "-34 / 2")
			blocks.append(br)
	for f in _floats:
		blocks.append(f.get_meta("float_rect"))
	var light := blocks.size()  # (obstacles count less: a label centred over its stack still reads as that stack's)
	blocks.append_array(_obstacle_rects)
	var best: Rect2 = cands[0]
	var best_cost := INF
	for i in cands.size():
		var c: Rect2 = cands[i]
		if c.position.y < 150 or c.end.y > BAR_Y - 4 or c.position.x < 4 or c.end.x > 1916:
			continue
		var cost := i * 150.0  # (the lowest free spot wins, then beside the head)
		var hit := c.grow_individual(0, 0, 0, 14) if i < 3 else c  # (with the pointer under it)
		for j in blocks.size():
			var bl: Rect2 = blocks[j]
			if hit.intersects(bl):
				cost += hit.intersection(bl).get_area() * (0.15 if j >= light else 1.0)
		if cost < best_cost:
			best_cost = cost
			best = c
	return best

## Small triangle under a damage label, pointing down at the stack it belongs to.
class _LabelTip extends Node2D:
	var color := Color.WHITE
	var side := 0  # 0: under the label pointing down; 1 / -1: at its right / left edge pointing out
	var reach := Vector2.ZERO  # (unrotated) from the pointer to the figure it belongs to
	func _draw() -> void:
		var to := reach.rotated(-rotation)
		if to.length() > 40.0:
			var from := Vector2(0, 12)
			draw_line(from, to, Color(0, 0, 0, 0.55), 5.0, true)
			draw_line(from, to, color, 2.5, true)
			draw_circle(to, 5.0, Color(0, 0, 0, 0.6))
			draw_circle(to, 3.5, color)
		draw_colored_polygon(PackedVector2Array([Vector2(-13, -1), Vector2(13, -1), Vector2(0, 14)]), Color(0, 0, 0, 0.6))
		draw_colored_polygon(PackedVector2Array([Vector2(-10, -1), Vector2(10, -1), Vector2(0, 11)]), color)

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
	l.position = Vector2(960 - l.size.x * 0.5, 182)
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
	var raise_id := "skeleton"
	var wh = L.heroes[winner]
	if wh and int(wh["skills"].get("necromancy", 0)) > 0:
		var cas := L.casualties(loser)
		var living := 0
		for id in cas:
			if not "undead" in GameData.CREATURES[id]["abilities"]:
				living += cas[id]
		var amp := 0.1 if TownLogic.player_has(L.players[winner], "necromancy_amplifier") else 0.0
		amp += GameState.hero_stat(wh, "necromancy") / 100.0  # (a gravecloak, the lich king's mantle)
		raised = int(living * (0.1 * int(wh["skills"]["necromancy"]) + amp))
		if "zombie" in GameState.hero_flags(wh, "raise"):  # (as many zombies as the skeletons' health allows)
			raise_id = "zombie"
			raised = int(raised * GameData.CREATURES["skeleton"]["hp"] / float(GameData.CREATURES["zombie"]["hp"]))
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
	if _surrendered:
		msg = "%s surrenders, paying %d gold, and leaves the field with the army." % [who[_retreated], _surrender_gold]
	elif _retreated >= 0:
		msg = "%s retreats from the battlefield." % who[_retreated]
	else:
		msg = "%s is victorious." % who[winner]
	m.add_text(msg, 24)
	for side in 2:
		m.body.add_child(UI.label("%s — casualties" % who[side], 22, UI.GOLD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var cas := L.casualties(side)
		if _retreated == side and not _surrendered:
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
		m.add_text("Necromancy raises %d %s from the fallen." % [raised, GameData.CREATURES[raise_id]["plural"].to_lower()], 22)
	m.add_buttons([["OK", true]])
	m.set_meta("default", true)
	await m.closed

	for side in 2:
		if L.heroes[side] != null:
			L.heroes[side]["machines"] = L.machines_left(side)
	var result := {
		"winner": "attacker" if winner == 0 else "defender",
		"attacker_army": L.army_out(0) if _retreated != 0 or _surrendered else [null, null, null, null, null, null, null],
		"defender_army": L.army_out(1) if _retreated != 1 or _surrendered else [null, null, null, null, null, null, null],
		"xp": xp, "retreated": _retreated >= 0, "raised": raised, "raised_id": raise_id, "fled": _retreated,
		"surrendered": _surrendered, "surrender_gold": _surrender_gold,
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
	var move_to := Vector2i(-1, -1)
	func _process(_d: float) -> void:
		if not active.is_empty():
			queue_redraw()  # pulse the active hex
	## The hexes the active stack would cover with its head on h.
	func _body(h: Vector2i) -> Array:
		return b.L.cells(active, h) if not active.is_empty() else [h]
	func _fill(hexes: Array, col: Color, line := Color(0, 0, 0, 0), width := 2.0) -> void:
		for h in hexes:
			if not BattleLogic.in_bounds(h):
				continue
			var poly: PackedVector2Array = b.hex_poly(b.hex_pos(h), 3.0)
			draw_colored_polygon(poly, col)
			if line.a > 0.0:
				var closed := poly.duplicate()
				closed.append(poly[0])
				draw_polyline(closed, line, width, true)
	## As the classic: only the hexes the active stack can reach are shaded and outlined (the "movement shadow");
	## the full grid is an option (G). The castle wall never gets hexes drawn over it.
	## Each hex edge's neighbour (edges run between hex_poly's corners k and k+1; odd rows sit half a hex right).
	const EDGE_EVEN := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, 0)]
	const EDGE_ODD := [Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)]
	## A firm gold line around the whole area the active stack can reach (its own hexes inside it).
	func _draw_reach_edge() -> void:
		if reach.is_empty():
			return
		var inside := reach.duplicate()
		if not active.is_empty():
			for c in b.L.cells(active):
				inside[c] = 0
		for h in inside:
			var poly: PackedVector2Array = b.hex_poly(b.hex_pos(h), 0.0)
			var nb: Array = EDGE_ODD if h.y % 2 == 1 else EDGE_EVEN
			for k in 6:
				if inside.has(h + nb[k]):
					continue
				var p0: Vector2 = poly[k]
				var p1: Vector2 = poly[(k + 1) % 6]
				draw_line(p0, p1, Color(0, 0, 0, 0.5), 6.5, true)
				draw_line(p0, p1, Color(1, 0.86, 0.4, 0.95), 3.5, true)

	func _draw() -> void:
		for y in BattleLogic.ROWS:
			for x in BattleLogic.COLS:
				var h := Vector2i(x, y)
				if not reach.has(h) and (not GameState.show_grid or b.L.wall_seg(h) >= 0):
					continue
				var c: Vector2 = b.hex_pos(h)
				var poly: PackedVector2Array = b.hex_poly(c, 2.0)
				# where the active stack can go: shaded (as the classic game), with a brighter outline
				if reach.has(h):
					draw_colored_polygon(poly, Color(0.04, 0.025, 0.0, 0.24))
				var closed := poly.duplicate()
				closed.append(poly[0])
				draw_polyline(closed, Color(0, 0, 0, 0.18), 3.0, true)  # dark under-line keeps the grid visible on light ground
				draw_polyline(closed, Color(1, 0.95, 0.72, 0.3 if reach.has(h) else 0.34), 1.5, true)
		_draw_reach_edge()
		if not active.is_empty() and active.get("alive", false):
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
			_fill(_body(active["hex"]), Color(1, 0.85, 0.3, 0.22 + 0.18 * pulse), Color(1, 0.9, 0.4, 0.75 + 0.25 * pulse), 4.0)
		if hover.x >= 0:
			var under = b.L.stack_at(hover)
			var hexes: Array = b.L.cells(under) if under != null else (_body(move_to) if move_to.x >= 0 else [hover])
			_fill(hexes, Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.7))
		if attack_from.x >= 0:
			_fill(_body(attack_from), Color(1, 0.4, 0.2, 0.25))

class _Shadow extends Node2D:
	var on := true  # (off: the stack has fallen, or is a tower's crew)
	var big := false
	var side := 0
	var hit_until := 0  # (msec) its ring flashes while a damage label of this stack shows
	var active := false:
		set(v):
			active = v
			queue_redraw()
	func _process(_d: float) -> void:
		if active or hit_until > 0:
			queue_redraw()
	func _draw() -> void:
		var w := 84.0 if big else 44.0
		draw_set_transform(Vector2(0, -2), 0, Vector2(1, 0.32))
		draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.45))
		# side colour (as the count badge): whose stack is whose, even when sprites overlap
		draw_arc(Vector2.ZERO, w - 2, 0, TAU, 40, Color(0.85, 0.25, 0.2, 0.75) if side == 0 else Color(0.3, 0.5, 1.0, 0.75), 5.0, true)
		if active:
			var a := 0.55 + 0.35 * sin(Time.get_ticks_msec() / 160.0)
			draw_arc(Vector2.ZERO, w + 4, 0, TAU, 40, Color(1, 0.85, 0.3, a), 4.0, true)
		var left := hit_until - Time.get_ticks_msec()
		if left > 0:
			var k := minf(1.0, left / 400.0)
			# (struck: its own side's colour flaring, not white, which read as the gold ring of the stack in play)
			var hc := Color(1.0, 0.42, 0.32) if side == 0 else Color(0.5, 0.72, 1.0)
			draw_arc(Vector2.ZERO, w - 2, 0, TAU, 40, Color(hc, 0.95 * k), 9.0, true)
		elif hit_until > 0:
			hit_until = 0

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
	var tex: Texture2D = null  # (instead of the creature's sprite: an arrow tower's archer)
	static var _crops := {}
	const HEAD := {"vampire_lord": Rect2(192, 44, 136, 136)}  # (sprite pixels: the wings rise above the head)

	## The head and shoulders of a creature's battle sprite: a square at the top of its figure, centred on the
	## solid pixels of its upper part (a dragon's head is at the front, not over the middle of the canvas).
	static func head_crop(id: String, tex: Texture2D) -> Rect2:
		if _crops.has(id):
			return _crops[id]
		if HEAD.has(id):
			return HEAD[id]
		var r := Rect2(Vector2.ZERO, tex.get_size())
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			var used := _solid_rect(img)
			var side := minf(maxf(used.size.x, used.size.y) * 0.5, maxf(used.size.x, used.size.y * 0.45))
			# start where the figure gets wide (a head), not at the tip of a lance, spear or staff
			var top := used.position.y
			var need := used.size.y * 0.06
			for y in range(used.position.y, used.end.y, 2):
				var c := 0
				for x in range(used.position.x, used.end.x, 2):
					if img.get_pixel(x, y).a > 0.7:
						c += 2
				if c >= need:
					top = y
					break
			var sx := 0.0
			var n := 0
			for y in range(top, top + int(side * 0.6), 3):
				for x in range(used.position.x, used.end.x, 3):
					if img.get_pixel(x, y).a > 0.6:
						sx += x
						n += 1
			var cx: float = sx / n if n > 0 else used.get_center().x
			r = Rect2(cx - side * 0.5, top - side * 0.06, side, side)
		_crops[id] = r
		return r

	static func _solid_rect(img: Image) -> Rect2i:
		var x0 := img.get_width()
		var y0 := img.get_height()
		var x1 := 0
		var y1 := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if img.get_pixel(x, y).a > 0.7:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0)) if x1 > x0 else img.get_used_rect()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var col := Color(0.85, 0.22, 0.16) if st["side"] == 0 else Color(0.27, 0.45, 1.0)
		# the side's colour as a lit backdrop (bright behind the head, dark at the edges), the creature's own head
		# cut from its battle sprite over it, facing the way it faces on the field
		draw_rect(r, col.darkened(0.72))
		var inner := r.grow(-4)
		for k in 6:
			var g := inner.grow(-k * inner.size.x * 0.07)
			g.position.y -= k * 3
			draw_rect(g, Color(col.darkened(0.35), 0.16))
		var t2: Texture2D = tex if tex else Assets.creature(st["id"])
		var whole: bool = st.get("machine", false) or tex != null
		var band := 30.0 if first else 26.0
		if st["side"] == 1:
			draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		if whole:
			# a war machine or a tower's archer: the whole figure fitted above the band (a head crop of a ballista
			# was bare beams; a tent and a cart could not be told apart)
			var key := "whole_%d" % t2.get_instance_id()
			if not _crops.has(key):
				var img := t2.get_image()
				if img and img.is_compressed():
					img.decompress()
				_crops[key] = Rect2(_solid_rect(img)) if img else Rect2(Vector2.ZERO, t2.get_size())
			var src: Rect2 = _crops[key]
			var area := Rect2(inner.position, Vector2(inner.size.x, inner.size.y - band + 2))
			# (filling the cell's height: a wide machine is cut at its ends rather than drawn as a thin smudge)
			var sc := minf(area.size.y / src.size.y, area.size.x * 1.5 / src.size.x)
			if src.size.x * sc > area.size.x:
				src = Rect2(src.get_center().x - area.size.x / sc * 0.5, src.position.y, area.size.x / sc, src.size.y)
			var dsz := src.size * sc
			draw_texture_rect_region(t2, Rect2(area.position + Vector2((area.size.x - dsz.x) * 0.5, area.size.y - dsz.y), dsz), src)
		else:
			draw_texture_rect_region(t2, inner, head_crop(st["id"], t2))
		draw_set_transform(Vector2.ZERO)
		# (a machine and a tower named in the band: they have no count)
		var txt: String = ("Tower" if tex != null else {"first_aid_tent": "Tent", "ammo_cart": "Cart"}.get(st["id"], GameData.CREATURES[st["id"]]["name"])) if whole else str(st["count"])
		var f := UI.title_font()
		var fs := (28 if first else 23) if not whole else (21 if first else 18)
		draw_rect(Rect2(Vector2(4, size.y - band - 3), Vector2(size.x - 8, band)), Color(col.darkened(0.5), 0.9))
		draw_rect(r, col, false, 4.0)
		if first:  # whose turn: a bright gold frame around the side colour
			draw_rect(r.grow(-1), UI.GOLD, false, 3.0)
			draw_rect(r.grow(-5), Color(1, 0.9, 0.5, 0.5), false, 1.5)
		while fs > 12 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 8:  # (a long name a size smaller)
			fs -= 1
		draw_string_outline(f, Vector2(0, size.y - 9), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 5, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(0, size.y - 9), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(1, 0.96, 0.85))

## Divider in the turn queue before the stacks of the next round.
class _RoundMark extends Control:
	var num := 2
	func _draw() -> void:
		# a gold rule through a medallion with the round number
		var c := size * 0.5
		draw_rect(Rect2(c.x - 2, 0, 4, size.y), UI.GOLD)
		draw_rect(Rect2(c.x - 1, 0, 1, size.y), Color(1, 0.95, 0.75))
		draw_circle(c, 19, Color(0.12, 0.08, 0.04))
		draw_arc(c, 19, 0, TAU, 32, UI.GOLD, 3.0, true)
		var f := UI.title_font()
		var t := str(num)
		draw_string_outline(f, Vector2(0, c.y + 9), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, 4, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(0, c.y + 9), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color(1, 0.88, 0.5))

## A small gold triangle button scrolling the combat log.
class _LogArrow extends BaseButton:
	var up := true
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
	func _draw() -> void:
		var c := size * 0.5
		var w := minf(size.x, size.y * 1.6) * 0.42
		var h := w * 0.8
		var pts := PackedVector2Array([c + Vector2(-w, h * 0.5), c + Vector2(w, h * 0.5), c + Vector2(0, -h * 0.5)]) if up \
			else PackedVector2Array([c + Vector2(-w, -h * 0.5), c + Vector2(w, -h * 0.5), c + Vector2(0, h * 0.5)])
		var col := UI.GOLD if not disabled else Color(0.35, 0.3, 0.24)
		if is_hovered() and not disabled:
			col = Color(1, 0.92, 0.6)
		draw_colored_polygon(pts, col)

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

class _Boulder extends Node2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var t := 0.0
	func fly(dur: float) -> void:
		var tw := create_tween()
		tw.tween_property(self, "t", 1.0, dur).set_trans(Tween.TRANS_LINEAR)
		await tw.finished
		queue_free()
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var p := from.lerp(to, t) + Vector2(0, -320.0 * 4.0 * t * (1.0 - t))
		draw_circle(p + Vector2(4, 5), 15, Color(0, 0, 0, 0.3))
		draw_circle(p, 15, Color(0.36, 0.32, 0.28))
		draw_circle(p + Vector2(-4, -4), 8, Color(0.55, 0.5, 0.44))

## Painted cracks on the face of each cracked (hit once) wall segment.
class _Cracks extends Node2D:
	var b
	func _draw() -> void:
		for i in b.L.walls.size():
			var w: Dictionary = b.L.walls[i]
			if w["hp"] != 1:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = 77 + i
			var band: Array = b.WALL_BANDS[i]
			var y0: float = maxf(200.0, band[0])
			var y1: float = band[1]
			for k in 2:  # (an impact: short jagged cracks branching out from a chipped, darker spot)
				var c := Vector2(1310 + rng.randf() * 60, y0 + 14 + rng.randf() * maxf(10.0, (y1 - y0) - 60))
				draw_circle(c, 7.0, Color(0.06, 0.05, 0.05, 0.55))
				draw_circle(c + Vector2(-2, -2), 3.0, Color(1, 0.95, 0.85, 0.18))
				var rays := 4 + rng.randi() % 2
				for j in rays:
					var ang := TAU * (j + rng.randf_range(-0.3, 0.3)) / rays
					var p := c
					var pts := PackedVector2Array([p])
					for q in 3:
						ang += rng.randf_range(-0.6, 0.6)
						p += Vector2.from_angle(ang) * rng.randf_range(6, 12)
						pts.append(p)
					draw_polyline(pts, Color(0.06, 0.05, 0.05, 0.85), 2.5)
					draw_polyline(pts, Color(1, 0.95, 0.85, 0.22), 0.8)

## Where the moat stops a move: a light wash over the painted water (none before the gate: the bridge).
class _Moat extends Node2D:
	var b
	func _draw() -> void:
		if not GameState.show_grid:  # (the painted water says it all; outlined only with the full grid)
			return
		for y in BattleLogic.ROWS:
			var h := Vector2i(BattleLogic.MOAT_X, y)
			if not b.L.is_moat(h):
				continue
			var poly: PackedVector2Array = b.hex_poly(b.hex_pos(h), 3.0)
			draw_colored_polygon(poly, Color(0.3, 0.6, 0.8, 0.13))
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, Color(0.55, 0.85, 1.0, 0.4), 1.5, true)

class _Burst extends Node2D:
	var color := Color.WHITE
	var radius := 70.0
	var bolt := false
	var slant := 1.0  # the bolt comes down slanted from this side (the field's outer edge), not through the stacks above
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
		if bolt and t < 0.8:  # (the cloud lingers a little after the bolt)
			# (from a dark storm cloud just under the turn queue: from higher up it seemed to come out of the queue's frame)
			# straight down onto the target, as the classic's bolt (a slant crossed the stacks around it)
			var top_y := minf(-160.0, 215.0 - global_position.y)
			var p := Vector2(0.0, top_y)
			var a0 := clampf((0.8 - t) / 0.3, 0.0, 1.0)  # (solid while it flashes, then gone)
			for c in [[-68.0, 10.0, 44.0], [-24.0, -10.0, 54.0], [28.0, -8.0, 52.0], [72.0, 10.0, 42.0], [-40.0, 20.0, 44.0],
					[6.0, 22.0, 50.0], [46.0, 20.0, 42.0]]:
				draw_set_transform(p + Vector2(c[0], c[1]), 0, Vector2(1, 0.62))
				draw_circle(Vector2.ZERO, c[2], Color(0.16, 0.17, 0.24) if a0 >= 1.0 else Color(0.16, 0.17, 0.24, a0))
			for c in [[-34.0, 38.0, 38.0], [12.0, 42.0, 44.0], [52.0, 36.0, 30.0]]:  # its underside lit by the bolt
				draw_set_transform(p + Vector2(c[0], c[1]), 0, Vector2(1, 0.28))
				draw_circle(Vector2.ZERO, c[2], Color(0.7, 0.85, 1.0, 0.95 * maxf(0.0, 1.0 - t * 2.0)))
			draw_set_transform(Vector2.ZERO)
			var rng := RandomNumberGenerator.new()
			rng.seed = get_instance_id()  # (the same zig-zag every frame of its flash)
			var pts := PackedVector2Array([p + Vector2(0, 24)])
			var q: Vector2 = pts[0]
			for i in 11:
				q = q.lerp(Vector2.ZERO, 1.0 / (11 - i)) + Vector2(rng.randf_range(-34, 34), rng.randf_range(-10, 10)) * (1.0 if i < 10 else 0.0)
				pts.append(q)
			var a2 := maxf(0.0, 1.0 - t * 2.0)
			for line in [pts]:
				var wk := 1.0
				draw_polyline(line, Color(0.45, 0.65, 1.0, 0.22 * a2), 40.0 * wk)  # outer glow
				draw_polyline(line, Color(0.6, 0.8, 1.0, 0.55 * a2), 18.0 * wk)
				draw_polyline(line, Color(0.88, 0.96, 1.0, a2), 9.0 * wk)
				draw_polyline(line, Color(1, 1, 1, a2), 4.5 * wk)
			draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.35))  # impact flash on the ground
			draw_circle(Vector2.ZERO, 70.0 * (1.0 - t), Color(0.9, 0.95, 1.0, 0.45 * a2))
			draw_set_transform(Vector2.ZERO)
		if bolt:
			return
		draw_circle(Vector2.ZERO, radius * (0.3 + t * 0.9), Color(color, 0.35 * a))
		draw_arc(Vector2.ZERO, radius * (0.2 + t), 0, TAU, 48, Color(color.lightened(0.4), a), 4.0 * a + 1.0)
		for s in _seeds:
			var d: float = radius * s[1] * (0.2 + t * 1.1)
			draw_circle(Vector2(cos(s[0]), sin(s[0]) * 0.6) * d, s[2] * a, Color(color.lightened(0.3), a))

class _Dust extends Node2D:
	var big := false
	var t := 0.0
	var _puffs := []
	func _ready() -> void:
		z_index = -1  # in front of the corpse layer but behind standing units' text
		for i in 9:
			_puffs.append([randf_range(-1, 1), randf_range(0.5, 1.0), randf_range(0.6, 1.2)])
		var tw := create_tween()
		tw.tween_property(self, "t", 1.0, 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_callback(queue_free)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var w := 90.0 if big else 55.0
		for p in _puffs:
			var c := Vector2(p[0] * w * (0.4 + t), -p[1] * 18.0 * t)
			draw_set_transform(c, 0, Vector2(1, 0.55))
			draw_circle(Vector2.ZERO, 14.0 * p[2] * (0.5 + t), Color(0.55, 0.47, 0.36, 0.45 * (1.0 - t)))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

class _Fallback extends Node2D:
	var terrain := "grass"
	func _draw() -> void:
		var ground: Color = {"grass": Color(0.3, 0.45, 0.18), "dirt": Color(0.42, 0.33, 0.2), "sand": Color(0.75, 0.65, 0.42),
			"snow": Color(0.85, 0.88, 0.92), "swamp": Color(0.26, 0.32, 0.2)}.get(terrain, Color(0.3, 0.45, 0.18))
		for i in 40:
			var y := i * 27.0
			var c: Color = Color(0.45, 0.6, 0.85).lerp(Color(0.85, 0.75, 0.6), i / 10.0) if y < 260 else ground.darkened(0.15 - (y - 260) / 820.0 * 0.3)
			draw_rect(Rect2(0, y, 1920, 28), c)
