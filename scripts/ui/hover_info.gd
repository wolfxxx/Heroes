extends RefCounted
class_name HoverInfo
## An info panel that follows the cursor while it rests on something: buildings, build cards, creature stacks,
## map objects. Unlike tooltips it appears at once (or after a short `delay`) and can hold icons and colour.
##   HoverInfo.attach(control, func(): return HoverInfo.creature("skeleton", 12))
##   HoverInfo.show_for(owner, content, delay, side) / HoverInfo.hide_for(owner)   for things that aren't Controls
## side: 1 = right of the cursor (default), -1 = left of it (each falls back to the other if there's no room).
## clear_x (>= 0): keep the panel on that side of this screen x (e.g. clear of a battle stack and its neighbours).
## Content is a Control, a String, or null (nothing to show).

const WIDTH := 400.0

static func _layer() -> _Layer:
	var tree := Engine.get_main_loop() as SceneTree
	var l = tree.root.get_node_or_null("HoverLayer")
	if l == null:
		l = _Layer.new()
		l.name = "HoverLayer"
		tree.root.add_child(l)
	return l

static func attach(c: Control, build: Callable, delay := 0.0) -> void:
	_layer()  # exist before the first mouse event, to know where the cursor is
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_entered.connect(func(): show_for(c, build.call(), delay))
	c.mouse_exited.connect(func(): hide_for(c))
	c.tree_exiting.connect(func(): hide_for(c))

static func show_for(owner: Object, content, delay := 0.0, side := 1, clear_x := -1.0) -> void:
	_layer().side = side
	_layer().clear_x = clear_x
	_layer().present(owner, content, delay)

static func hide_for(owner: Object) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var l = tree.root.get_node_or_null("HoverLayer")
	if l:
		l.dismiss(owner)

# ---------------------------------------------------------------------------------------------
# Content builders
# ---------------------------------------------------------------------------------------------
static func box(title: String, title_color := UI.GOLD) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	if title != "":
		v.add_child(UI.label(title, 22, title_color, true))
	return v

static func line(v: VBoxContainer, text: String, color := UI.TEXT, size := 19) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 24
	v.add_child(l)
	return l

## Resource icons with amounts; amounts the player can't afford in red when `have` is given.
static func cost_row(cost: Dictionary, have = null) -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 12)
	h.custom_minimum_size.x = WIDTH - 90  # a flow box has no width of its own: it would stack one per line
	if cost.is_empty():
		h.add_child(UI.label("Free", 19))
	for r in GameData.RESOURCES:
		var need: int = cost.get(r, 0)
		if need <= 0:
			continue
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(UI.icon(Assets.res_icon(r), Vector2(26, 26)))
		var ok: bool = have == null or have.get(r, 0) >= need
		cell.add_child(UI.label(str(need), 19, UI.TEXT if ok else Color(1, 0.5, 0.4)))
		h.add_child(cell)
	return h

## Creature stats: portrait, attack/defense/damage/health/speed/growth, abilities, cost.
static func creature(cid: String, count := -1, title := "") -> VBoxContainer:
	var c: Dictionary = GameData.CREATURES[cid]
	if title == "":
		title = c["plural"] if count != 1 else c["name"]
		if count > 0:
			title = "%d %s" % [count, title]
	var v := box(title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.add_child(UI.icon(Assets.creature_portrait(cid), Vector2(84, 84)))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 2)
	for row in [["Attack", c["attack"]], ["Defense", c["defense"]], ["Damage", "%d-%d" % c["dmg"]], ["Health", c["hp"]],
			["Speed", c["speed"]], ["Growth", "%d/wk" % c["growth"]]] + ([["Shots", c["shots"]]] if c["shots"] > 0 else []):
		g.add_child(UI.label(row[0], 18, UI.GOLD))
		g.add_child(UI.label(str(row[1]), 18))
	h.add_child(g)
	v.add_child(h)
	var ab: Array = c["abilities"].map(func(a): return GameData.ABILITY_TEXT.get(a, a))
	if ab.size() > 0:
		line(v, ", ".join(ab), Color(0.75, 0.85, 1.0), 18)
	var cr := HBoxContainer.new()
	cr.add_child(UI.label("Cost ", 18, UI.GOLD))
	cr.add_child(cost_row(c["cost"]))
	v.add_child(cr)
	return v

# ---------------------------------------------------------------------------------------------
class _Layer extends CanvasLayer:
	var panel: PanelContainer
	var owner_obj = null
	var content: Control
	var wait := 0.0
	var mouse := Vector2.ZERO  # from motion events (follows simulated input too, unlike the OS cursor)
	var side := 1
	var clear_x := -1.0

	func _init() -> void:
		layer = 120
		panel = PanelContainer.new()
		panel.theme = UI.theme()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.055, 0.04, 0.96)
		sb.border_color = UI.GOLD_DARK
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(12)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 6
		panel.add_theme_stylebox_override("panel", sb)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.visible = false
		add_child(panel)

	func present(o, c, delay: float) -> void:
		if mouse == Vector2.ZERO:
			mouse = get_viewport().get_mouse_position()
		if content:
			content.queue_free()
			content = null
		owner_obj = o
		if c == null or (c is String and c == "") or _under_modal(o):
			panel.visible = false
			return
		if c is String:
			var v := HoverInfo.box("")
			HoverInfo.line(v, c)
			c = v
		content = c
		_ignore_mouse(content)
		panel.add_child(content)
		panel.reset_size()
		wait = delay
		panel.visible = false
		if delay <= 0.0:
			_place()
			panel.visible = true

	func dismiss(o) -> void:
		if o == owner_obj:
			owner_obj = null
			panel.visible = false
			if content:
				content.queue_free()
				content = null

	## Owner hidden behind an open dialog (e.g. the map tile under a hero screen): its panel must not show.
	func _under_modal(o) -> bool:
		var ml := get_tree().root.get_node_or_null("ModalLayer")
		if ml == null or ml.get_child_count() == 0:
			return false
		return not (o is Node and ml.get_child(ml.get_child_count() - 1).is_ancestor_of(o))

	func _ignore_mouse(n: Node) -> void:
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in n.get_children():
			_ignore_mouse(k)

	func _process(delta: float) -> void:
		if content == null:
			return
		if owner_obj != null and owner_obj is Object and not is_instance_valid(owner_obj):
			dismiss(owner_obj)
			return
		if _under_modal(owner_obj):
			dismiss(owner_obj)
			return
		if wait > 0.0:
			wait -= delta
			if wait <= 0.0:
				panel.visible = true
		if panel.visible:
			_place()

	func _place() -> void:
		var vp := get_viewport()
		var m := mouse
		var vs := vp.get_visible_rect().size
		var sz := panel.get_combined_minimum_size()
		panel.size = sz
		var p := m + Vector2(26, 26)
		var left := m.x - sz.x - 16
		if clear_x >= 0.0:
			p.x = clampf(maxf(p.x, clear_x) if side > 0 else minf(left, clear_x - sz.x), 8, vs.x - sz.x - 8)
		elif (side < 0 and left >= 8) or p.x + sz.x > vs.x - 8:
			p.x = left
		if p.y + sz.y > vs.y - 8:
			p.y = maxf(8, vs.y - sz.y - 8)
		panel.position = p

	func _input(e: InputEvent) -> void:
		if e is InputEventMouse:
			mouse = e.position
		# a click starts something else (a dialog, a move): get out of the way
		# (also one still waiting out its delay, or it would pop up afterwards with what the click just changed)
		if e is InputEventMouseButton and e.pressed and content != null:
			dismiss(owner_obj)
