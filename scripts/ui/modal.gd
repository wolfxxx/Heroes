extends Control
class_name Modal
## Modal dialogs.  `var r = await Modal.message(self, "Title", "Text").closed`
## Every factory adds the dialog to the top-most CanvasLayer of `owner_node`'s scene (layer 90).

signal closed(result)

var panel: PanelContainer
var body: VBoxContainer
var _result = null

static func _host(owner_node: Node) -> Node:
	var tree := owner_node.get_tree()
	var layer: CanvasLayer = tree.root.get_node_or_null("ModalLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "ModalLayer"
		layer.layer = 90
		tree.root.add_child(layer)
	return layer

static func _make(owner_node: Node, title: String, width := 640.0) -> Modal:
	var m := Modal.new()
	m.theme = UI.theme()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	m.panel = PanelContainer.new()
	m.panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(m.panel)
	m.body = VBoxContainer.new()
	m.body.add_theme_constant_override("separation", 14)
	m.panel.add_child(m.body)
	if title != "":
		var t := UI.label(title, 32, UI.GOLD, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.body.add_child(t)
	_host(owner_node).add_child(m)
	m.panel.scale = Vector2(0.92, 0.92)
	m.panel.pivot_offset = Vector2(width * 0.5, 120)
	m.modulate.a = 0.0
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "modulate:a", 1.0, 0.15)
	tw.tween_property(m.panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return m

func close(result = null) -> void:
	_result = result
	closed.emit(result)
	queue_free()

func add_text(text: String, size := 22) -> Label:
	var l := UI.label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(panel.custom_minimum_size.x - 40, 0)
	body.add_child(l)
	return l

## icons: Array of [Texture2D, caption]
func add_icons(icons: Array, icon_size := Vector2(72, 72)) -> void:
	if icons.is_empty():
		return
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	for ic in icons:
		var v := VBoxContainer.new()
		v.add_child(UI.icon(ic[0], icon_size))
		var l := UI.label(str(ic[1]), 20)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		h.add_child(v)
	body.add_child(h)

func add_buttons(options: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	for o in options:
		var val = o[1]
		var b := UI.button(o[0], func(): close(val), 24)
		b.custom_minimum_size = Vector2(160, 54)
		h.add_child(b)
	body.add_child(h)
	return h

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and has_meta("default"):
			get_viewport().set_input_as_handled()
			close(get_meta("default"))
		elif e.keycode == KEY_ESCAPE and has_meta("cancel"):
			get_viewport().set_input_as_handled()
			close(get_meta("cancel"))

# ---------------------------------------------------------------------------------------------
static func message(owner_node: Node, title: String, text: String, icons: Array = [], width := 640.0) -> Modal:
	var m := _make(owner_node, title, width)
	m.add_text(text)
	m.add_icons(icons)
	m.add_buttons([["OK", true]])
	m.set_meta("default", true)
	m.set_meta("cancel", true)
	return m

static func confirm(owner_node: Node, title: String, text: String, yes := "Yes", no := "No") -> Modal:
	var m := _make(owner_node, title)
	m.add_text(text)
	m.add_buttons([[yes, true], [no, false]])
	m.set_meta("default", true)
	m.set_meta("cancel", false)
	return m

## options: Array of [label, value, texture or null, caption]
static func choice(owner_node: Node, title: String, text: String, options: Array) -> Modal:
	var m := _make(owner_node, title, 720)
	m.add_text(text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 30)
	for o in options:
		var val = o[1]
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 150)
		b.text = o[0]
		if o.size() > 2 and o[2]:
			b.icon = o[2]
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 80)
		b.pressed.connect(func():
			Audio.sfx("click", -6)
			m.close(val))
		h.add_child(b)
	m.body.add_child(h)
	m.set_meta("default", options[0][1])
	return m

static func custom(owner_node: Node, title: String, width := 800.0) -> Modal:
	return _make(owner_node, title, width)
