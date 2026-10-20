extends HBoxContainer
class_name ArmyStrip
## 7 army slots bound to an army Array (7 entries, null or {"id","count"}).
## Strips sharing the same `group` Dictionary can exchange stacks:
##   click a stack to select, click another slot to move / merge / swap; shift+click an empty slot to split.
##   right click shows creature info.

signal changed

var army: Array = []
var group: Dictionary = {}
var keep_one := false   # hero armies must keep at least one stack
var slot_size := Vector2(92, 92)
var editable := true
var upgrade_town = null    # in a town: right click offers to upgrade a stack there (TownLogic.upgrade_stack)
var upgrade_player = null
var _slots: Array = []

func bind(a: Array, g: Dictionary = {}, keep := false) -> ArmyStrip:
	army = a
	group = g
	keep_one = keep
	if not group.has("strips"):
		group["strips"] = []
	group["strips"].append(self)
	add_theme_constant_override("separation", 6)
	_build()
	return self

func _exit_tree() -> void:
	if group.has("strips"):
		group["strips"].erase(self)

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_slots.clear()
	for i in 7:
		var s := _Slot.new()
		s.strip = self
		s.index = i
		s.custom_minimum_size = slot_size
		add_child(s)
		_slots.append(s)

func refresh() -> void:
	for s in _slots:
		s.queue_redraw()

func refresh_group() -> void:
	for s in group.get("strips", []):
		if is_instance_valid(s):
			s.refresh()

func _stacks() -> int:
	var n := 0
	for a in army:
		if a:
			n += 1
	return n

func _click(i: int, shift: bool) -> void:
	if not editable:
		return
	var sel = group.get("sel")
	if sel == null:
		if army[i]:
			group["sel"] = [self, i]
			Audio.sfx("click", -8)
		refresh_group()
		return
	var src: ArmyStrip = sel[0]
	var si: int = sel[1]
	group["sel"] = null
	if src == self and si == i:
		refresh_group()
		return
	var a = src.army[si]
	var b = army[i]
	if a == null:
		refresh_group()
		return
	if b == null:
		if shift and a["count"] > 1:
			var half: int = a["count"] / 2
			a["count"] -= half
			army[i] = {"id": a["id"], "count": half}
		else:
			if src != self and src.keep_one and src._stacks() <= 1:
				Audio.sfx("error")
				refresh_group()
				return
			army[i] = a
			src.army[si] = null
	elif b["id"] == a["id"]:
		if src != self and src.keep_one and src._stacks() <= 1:
			Audio.sfx("error")
			refresh_group()
			return
		b["count"] += a["count"]
		src.army[si] = null
	else:
		army[i] = a
		src.army[si] = b
	Audio.sfx("click", -6)
	refresh_group()
	for s in group.get("strips", []):
		if is_instance_valid(s):
			s.changed.emit()

func _info(i: int) -> void:
	var st = army[i]
	if st == null:
		return
	var up := TownLogic.upgrade_target(upgrade_town, st["id"]) if upgrade_town != null else ""
	if up == "":
		show_creature_info(self, st["id"], st["count"])
		return
	if await upgrade_dialog(self, st, up, upgrade_player) and TownLogic.upgrade_stack(upgrade_town, upgrade_player, st):
		Audio.sfx("build", -4)
		refresh_group()
		for s in group.get("strips", []):
			if is_instance_valid(s):
				s.changed.emit()

## Before and after: the stack now and as upgraded, side by side with their stats (better ones in green), and the
## price for the whole stack. True when the player chose to upgrade.
static func upgrade_dialog(owner_node: Node, st: Dictionary, up: String, player: Dictionary) -> bool:
	var a: Dictionary = GameData.CREATURES[st["id"]]
	var b: Dictionary = GameData.CREATURES[up]
	var n: int = st["count"]
	var m := Modal.custom(owner_node, "Upgrade %d %s" % [n, a["plural"] if n != 1 else a["name"]], 980)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 44)  # (the two columns fill the dialog: no bare wood at its sides)
	m.body.add_child(h)
	var rows := [["Attack", "attack"], ["Defense", "defense"], ["Damage", "dmg"], ["Health", "hp"], ["Speed", "speed"],
		["Shots", "shots"]]
	for k in 2:
		var c: Dictionary = a if k == 0 else b
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		var title := UI.label(c["plural"] if n != 1 else c["name"], 24, UI.GOLD, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
		col.add_child(UI.icon(Assets.creature_portrait(GameData.base_of(st["id"]) if k == 0 else up), Vector2(310, 310)))
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 40)
		g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for r in rows:
			g.add_child(UI.label(r[0], 22, UI.GOLD))
			var v = c[r[1]]
			var txt := ("%d - %d" % v) if r[1] == "dmg" else (str(v) if v != 0 else "-")
			var better: bool = k == 1 and (str(v) != str(a[r[1]]))
			g.add_child(UI.label(txt, 22, Color(0.6, 0.95, 0.5) if better else UI.TEXT))
		col.add_child(g)
		h.add_child(col)
		if k == 0:
			var arrow := _Arrow.new()  # (a bold gold arrow at the portraits' height: a » glyph was a small mark)
			arrow.custom_minimum_size = Vector2(110, 120)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(arrow)
	var cost := TownLogic.upgrade_cost(st["id"], up, n)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(UI.label("Cost for the whole stack:", 21, UI.GOLD))
	row.add_child(HoverInfo.cost_row(cost, player["resources"]))
	m.body.add_child(row)
	var btns := m.add_buttons([["Upgrade", "upgrade"], ["Cancel", ""]])
	btns.get_child(0).disabled = not TownLogic.can_afford(player, cost)
	m.set_meta("cancel", "")
	return await m.closed == "upgrade"

static func show_creature_info(owner_node: Node, cid: String, count: int, buttons := [["OK", true]]) -> Modal:
	var c: Dictionary = GameData.CREATURES[cid]
	var m := Modal.custom(owner_node, "%d %s" % [count, c["plural"] if count != 1 else c["name"]], 620)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.add_child(UI.icon(Assets.creature(cid), Vector2(220, 220)))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	for row in [["Attack", c["attack"]], ["Defense", c["defense"]], ["Damage", "%d - %d" % c["dmg"]], ["Health", c["hp"]],
			["Speed", c["speed"]], ["Shots", c["shots"] if c["shots"] > 0 else "-"], ["Growth", "%d / week" % c["growth"]], ["Cost", UI.format_cost(c["cost"])]]:
		g.add_child(UI.label(row[0], 21, UI.GOLD))
		g.add_child(UI.label(str(row[1]), 21))
	h.add_child(g)
	m.body.add_child(h)
	var ab: Array = c["abilities"].map(func(a): return GameData.ABILITY_TEXT.get(a, a))
	if ab.size() > 0:
		m.add_text(", ".join(ab), 20)
	m.set_meta("buttons", m.add_buttons(buttons))
	m.set_meta("default", true)
	m.set_meta("cancel", true)
	return m

## Head-and-shoulders crop of each portrait (x, y, size as fractions of it) for the small slots of the adventure panel.
const FOCUS := {"angel": [0.39, 0.46, 0.36], "archer": [0.27, 0.27, 0.36], "bone_dragon": [0.32, 0.22, 0.36],
	"cavalier": [0.24, 0.36, 0.36], "dread_knight": [0.25, 0.33, 0.36], "ghost": [0.37, 0.27, 0.36], "griffin": [0.38, 0.2, 0.36],
	"lich": [0.25, 0.32, 0.36], "monk": [0.32, 0.32, 0.36], "pikeman": [0.32, 0.4, 0.36], "skeleton": [0.32, 0.32, 0.36],
	"swordsman": [0.3, 0.3, 0.36], "vampire": [0.37, 0.31, 0.36], "zombie": [0.32, 0.32, 0.36]}

class _Slot extends Control:
	var strip: ArmyStrip
	var index := 0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		HoverInfo.attach(self, func():
			var st = strip.army[index] if index < strip.army.size() else null
			return HoverInfo.creature(st["id"], st["count"]) if st else null)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				strip._click(index, e.shift_pressed)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				strip._info(index)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.06, 0.05, 0.04, 0.9))
		var st = strip.army[index] if index < strip.army.size() else null
		if st:
			var tex := Assets.creature_portrait(st["id"])
			var small := size.y < 56
			var fk: String = st["id"] if FOCUS.has(st["id"]) else GameData.base_of(st["id"])  # (upgrades: same framing)
			if small and FOCUS.has(fk):
				var f: Array = FOCUS[fk]
				var ts := Vector2(tex.get_size())
				draw_texture_rect_region(tex, r.grow(-3), Rect2(Vector2(f[0], f[1]) * ts, Vector2(f[2], f[2]) * ts), Color(1.3, 1.25, 1.2))
			else:
				draw_texture_rect(tex, r.grow(-3), false, Color(1.3, 1.25, 1.2) if small else Color.WHITE)
			var txt := str(st["count"])
			var f := UI.font()
			var fs := 13 if small else 20
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var p := Vector2(size.x - tw - (4 if small else 6), size.y - (4 if small else 6))
			var pad := 2.0 if small else 3.0
			draw_rect(Rect2(p - Vector2(pad, fs - 3), Vector2(tw + pad * 2, fs)), Color(0.04, 0.03, 0.02, 0.85 if small else 0.6))
			draw_string(f, p + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
			draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT)
		var sel = strip.group.get("sel")
		var selected: bool = sel != null and sel[0] == strip and sel[1] == index
		draw_rect(r, UI.GOLD if selected else UI.GOLD_DARK, false, 3.0 if selected else 2.0)

## The upgrade dialog's arrow from the stack as it is to the stack upgraded.
class _Arrow extends Control:
	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, -60)
		var pts := PackedVector2Array([c + Vector2(-48, -16), c + Vector2(8, -16), c + Vector2(8, -38), c + Vector2(50, 0),
			c + Vector2(8, 38), c + Vector2(8, 16), c + Vector2(-48, 16)])
		draw_colored_polygon(pts, Color(1.0, 0.82, 0.32))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.35, 0.2, 0.05), 3.0, true)
