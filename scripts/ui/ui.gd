class_name UI
extends RefCounted
## Shared UI styling helpers. Every screen should build its widgets through these so the look stays
## consistent and automatically upgrades when ui/*.png art lands.

const GOLD := Color(0.95, 0.80, 0.45)
const GOLD_DARK := Color(0.55, 0.40, 0.15)
const TEXT := Color(0.96, 0.92, 0.82)
const PANEL_BG := Color(0.10, 0.08, 0.06, 0.94)

static var _theme: Theme
static var _font: Font
static var _font_title: Font

static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists("res://assets/fonts/body.ttf"):
			_font = load("res://assets/fonts/body.ttf")
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
			_font = f
	return _font

static func title_font() -> Font:
	if _font_title == null:
		if ResourceLoader.exists("res://assets/fonts/title.ttf"):
			_font_title = load("res://assets/fonts/title.ttf")
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Trajan Pro", "Cinzel", "Palatino Linotype", "Georgia", "serif"])
			f.font_weight = 700
			_font_title = f
	return _font_title

static func panel_style(alpha := 0.94) -> StyleBox:
	if Assets.has("ui/panel.png"):
		var sb := StyleBoxTexture.new()
		sb.texture = Assets.tex("ui/panel.png")
		sb.set_texture_margin_all(30)
		sb.set_content_margin_all(30)
		sb.modulate_color = Color(1, 1, 1, alpha)
		return sb
	var f := StyleBoxFlat.new()
	f.bg_color = Color(PANEL_BG, alpha)
	f.border_color = GOLD_DARK
	f.set_border_width_all(3)
	f.set_corner_radius_all(6)
	f.set_content_margin_all(16)
	f.shadow_color = Color(0, 0, 0, 0.5)
	f.shadow_size = 8
	return f

static func _button_style(state: String) -> StyleBox:
	var file: String = {"normal": "ui/button.png", "hover": "ui/button_hover.png", "pressed": "ui/button_selected.png",
		"hover_pressed": "ui/button_selected.png", "disabled": "ui/button.png"}[state]
	if Assets.has(file):
		var sb := StyleBoxTexture.new()
		sb.texture = Assets.tex(file)
		sb.set_texture_margin_all(12)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		if state == "disabled":
			sb.modulate_color = Color(0.5, 0.5, 0.5)
		return sb
	var f := StyleBoxFlat.new()
	f.bg_color = {"normal": Color(0.28, 0.18, 0.08), "hover": Color(0.42, 0.28, 0.12), "pressed": Color(0.5, 0.36, 0.12), "hover_pressed": Color(0.55, 0.4, 0.14), "disabled": Color(0.2, 0.18, 0.16)}[state]
	f.border_color = GOLD if state == "hover" else GOLD_DARK
	f.set_border_width_all(2)
	f.set_corner_radius_all(4)
	f.content_margin_left = 18
	f.content_margin_right = 18
	f.content_margin_top = 8
	f.content_margin_bottom = 8
	return f

## The look of a selected toggle (option, card): a dark plate in a bright gold frame with a soft glow. Light text
## stays readable on it, unlike on the gold "selected" button texture.
static func selected_plate(margin := 18.0) -> StyleBoxFlat:
	var on := StyleBoxFlat.new()
	on.bg_color = Color(0.2, 0.13, 0.06, 0.97)
	on.border_color = Color(1.0, 0.82, 0.38)
	on.set_border_width_all(3)
	on.set_corner_radius_all(5)
	on.shadow_color = Color(1.0, 0.75, 0.3, 0.4)
	on.shadow_size = 8
	on.content_margin_left = margin
	on.content_margin_right = margin
	return on

## Use selected_plate() for a toggle button's pressed states, with gold text.
static func plate_toggle(b: BaseButton) -> void:
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, selected_plate())
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color(1.0, 0.88, 0.55))

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "Button", _button_style(st))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.7))
	# pressed/selected buttons use the bright gold texture: dark ink text stays readable on it
	t.set_color("font_pressed_color", "Button", Color(0.2, 0.1, 0.03))
	t.set_color("font_hover_pressed_color", "Button", Color(0.16, 0.08, 0.02))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.45))
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_font_size("normal_font_size", "RichTextLabel", 20)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.08, 0.06, 0.04, 0.96)
	tip.border_color = GOLD_DARK
	tip.set_border_width_all(2)
	tip.set_content_margin_all(10)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return t

static func label(text: String, size := 22, color := TEXT, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# explicit font: labels placed outside a themed Control (e.g. on a Node2D) would fall back to Godot's sans-serif
	l.add_theme_font_override("font", title_font() if title else font())
	return l

static func button(text: String, cb: Callable = Callable(), size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func(): Audio.sfx("click", -6))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

## A picture set in the carved button frame (as the panel's other buttons), brighter under the pointer; `selected`
## adds a gold edge. The picture is inset `inset` px and covers its area.
static func pic_button(tex: Texture2D, size: Vector2, inset := 6.0, selected := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.clip_contents = true
	pic.position = Vector2(inset, inset)
	pic.size = size - Vector2(inset, inset) * 2.0
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var edge := _PicEdge.new()
	edge.selected = selected
	edge.inset = inset
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(edge)
	b.mouse_entered.connect(func():
		pic.modulate = Color(1.18, 1.14, 1.05)
		edge.hover = true
		edge.queue_redraw())
	b.mouse_exited.connect(func():
		pic.modulate = Color.WHITE
		edge.hover = false
		edge.queue_redraw())
	b.set_meta("pic", pic)
	b.set_meta("edge", edge)
	return b

static func icon(tex: Texture2D, size := Vector2(48, 48)) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r

static func format_cost(cost: Dictionary) -> String:
	var parts := []
	for r in GameData.RESOURCES:
		if cost.get(r, 0) > 0:
			parts.append("%d %s" % [cost[r], GameData.RESOURCE_NAMES[r]])
	return ", ".join(parts) if parts.size() > 0 else "Free"

## HoMM-style army size description for enemy stacks.
static func count_word(n: int) -> String:
	if n < 5: return "A few"
	if n < 10: return "Several"
	if n < 20: return "A pack of"
	if n < 50: return "Lots of"
	if n < 100: return "A horde of"
	if n < 250: return "A throng of"
	if n < 500: return "A swarm of"
	if n < 1000: return "Zounds of"
	return "A legion of"

## The rim drawn over a pic_button's picture: a thin dark line inside the carved frame, gold when selected, light
## under the pointer.
class _PicEdge extends Control:
	var selected := false
	var hover := false
	var inset := 6.0
	func _draw() -> void:
		var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		draw_rect(r, Color(0.08, 0.05, 0.02, 0.9), false, 2.0)
		if selected:
			draw_rect(r.grow(1), Color(1.0, 0.84, 0.38), false, 3.0)
		elif hover:
			draw_rect(r.grow(1), Color(1.0, 0.92, 0.7, 0.7), false, 2.0)
