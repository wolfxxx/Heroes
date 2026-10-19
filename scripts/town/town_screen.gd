extends Control
## Town screen: painted backdrop with composited buildings (hover/click), garrison + visiting hero
## armies, and dialogs for building, recruiting, tavern, marketplace, mage guild and blacksmith.

const RES_VALUE := {"gold": 1, "wood": 250, "ore": 250, "mercury": 500, "sulfur": 500, "crystal": 500, "gems": 500}

var world: Dictionary
var town: Dictionary
var player: Dictionary
var hero: Dictionary = {}
var _view: Control
var _bld_nodes: Array = []   # [{id, sprite: TextureRect, img: Image, layer}]
var _hover_id := ""
var _status: Label
var _info: VBoxContainer
var _armies: VBoxContainer
var _buttons: VBoxContainer
var _res_labels := {}
var _group := {}

func _ready() -> void:
	theme = UI.theme()
	_resolve_state()
	_build()
	refresh()
	Audio.music("town_%s" % town["faction"])

func _resolve_state() -> void:
	if GameState.world.is_empty():
		var s := GameState.new_game_settings.duplicate()
		s["seed"] = 12345
		if Shot.setup.contains("necro"):
			s["faction"] = "necropolis"
			s["hero"] = "lord_morthis"
		GameState.world = WorldGen.generate(s)
	world = GameState.world
	var uid: int = GameState.pending_town.get("town_uid", -1)
	if not world["towns"].has(uid):
		uid = world["players"][GameState.human_player_index()]["towns"][0]
		if Shot.setup.contains("rich") or Shot.setup.contains("max"):
			var t: Dictionary = world["towns"][uid]
			t["buildings"] = ["city_hall", "castle", "tavern", "marketplace", "mage_guild_2", "blacksmith",
				"dwelling_1u", "dwelling_2u", "dwelling_3u", "dwelling_4", "dwelling_5", "dwelling_6u", "dwelling_7"]
			t["buildings"].append_array(GameData.SPECIALS[t["faction"]])
			if Shot.setup.contains("max"):  # (with the Capitol)
				t["buildings"][0] = "capitol"
			TownLogic.learn_guild_spells(t)
			TownLogic.weekly_growth(t)
	town = world["towns"][uid]
	player = world["players"][town["owner"]] if town["owner"] >= 0 else world["players"][0]
	var huid: int = GameState.pending_town.get("hero_uid", -1)
	for h in world["heroes"].values():
		if h["pos"] == town["pos"] and h["owner"] == town["owner"]:
			hero = h
	if hero.is_empty() and world["heroes"].has(huid):
		hero = world["heroes"][huid]

# ---------------------------------------------------------------------------------------------
func _build() -> void:
	_view = Control.new()
	_view.position = Vector2.ZERO
	_view.size = Vector2(1920, TownLayout.VIEW_H)
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	_view.mouse_exited.connect(func(): _set_hover(""))
	add_child(_view)
	var bgp := "town/%s_bg.png" % town["faction"]
	if Assets.has(bgp):
		var bg := TextureRect.new()
		bg.texture = Assets.tex(bgp)
		bg.size = _view.size
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view.add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.size = _view.size
		var mat := ShaderMaterial.new()
		mat.shader = load("res://scripts/menu/menu_bg.gdshader")
		bg.material = mat
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view.add_child(bg)

	var title := UI.label(town["name"], 44, UI.GOLD, true)
	title.position = Vector2(30, 16)
	title.size = Vector2(800, 60)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.z_index = 5
	_view.add_child(title)
	_status = UI.label("", 24, UI.TEXT)
	_status.position = Vector2(0, TownLayout.VIEW_H - 44)
	_status.size = Vector2(1920, 40)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.z_index = 5
	_view.add_child(_status)

	# Bottom panel
	var panel := Panel.new()
	panel.position = Vector2(0, TownLayout.VIEW_H)
	panel.size = Vector2(1920, 1080 - TownLayout.VIEW_H)
	add_child(panel)
	_info = VBoxContainer.new()
	_info.position = Vector2(24, TownLayout.VIEW_H + 16)
	_info.size = Vector2(330, 200)
	add_child(_info)
	_armies = VBoxContainer.new()
	_armies.position = Vector2(380, TownLayout.VIEW_H + 12)
	_armies.add_theme_constant_override("separation", 6)
	add_child(_armies)
	_buttons = VBoxContainer.new()
	_buttons.position = Vector2(1330, TownLayout.VIEW_H + 14)
	_buttons.add_theme_constant_override("separation", 8)
	add_child(_buttons)

	var bar := HBoxContainer.new()
	bar.position = Vector2(24, 1080 - 42)
	bar.add_theme_constant_override("separation", 28)
	add_child(bar)
	for r in GameData.RESOURCES:
		var box := HBoxContainer.new()
		box.add_child(UI.icon(Assets.res_icon(r), Vector2(30, 30)))
		var l := UI.label("0", 21)
		box.add_child(l)
		_res_labels[r] = l
		bar.add_child(box)

func refresh() -> void:
	_rebuild_buildings()
	for c in _info.get_children():
		c.queue_free()
	# the hall (build) and the fort (all dwellings) as pictures, as on the classic town screen
	var pics := HBoxContainer.new()
	pics.add_theme_constant_override("separation", 12)
	var hall := "village_hall"
	for h in ["capitol", "city_hall", "town_hall"]:
		if TownLogic.has_building(town, h):
			hall = h
			break
	pics.add_child(_pic_button(_building_pic(hall), GameData.building_name(town["faction"], hall),
		"Build in %s (B)" % town["name"], _open_build))
	var fort := "castle" if TownLogic.has_building(town, "castle") else ("citadel" if TownLogic.has_building(town, "citadel") else "fort")
	pics.add_child(_pic_button(_building_pic(fort), GameData.building_name(town["faction"], fort) if TownLogic.has_building(town, fort) else "Dwellings",
		"All creature dwellings: recruit (R)", _open_recruit_all))
	_info.add_child(pics)
	_info.add_child(UI.label("Income: %d gold a day" % TownLogic.daily_income(town), 20))
	_info.add_child(UI.label("Already built today" if town["built_today"] else "You may build today", 19, Color(0.8, 0.6, 0.5) if town["built_today"] else Color(0.6, 0.9, 0.55)))

	for c in _armies.get_children():
		c.queue_free()
	_group = {}
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	var flag := _Banner.new()
	flag.custom_minimum_size = Vector2(92, 92)
	flag.color = GameData.PLAYER_COLORS[town["owner"]] if town["owner"] >= 0 else Color.GRAY
	if Assets.has("map/town_%s.png" % town["faction"]):
		flag.town_tex = Assets.tex("map/town_%s.png" % town["faction"])
	flag.tooltip_text = "Garrison"
	row1.add_child(flag)
	var g := ArmyStrip.new()
	g.upgrade_town = town
	g.upgrade_player = player
	g.bind(town["garrison"], _group, false)
	g.changed.connect(_on_army_changed)
	row1.add_child(g)
	_armies.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	if hero.is_empty():
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(92, 92)
		empty.tooltip_text = "No visiting hero"
		row2.add_child(empty)
		var l := UI.label("No hero is visiting. Hire one at the Tavern.", 20, Color(0.75, 0.7, 0.6))
		l.custom_minimum_size = Vector2(600, 92)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row2.add_child(l)
	else:
		var p := TextureButton.new()
		p.texture_normal = Assets.hero_portrait(hero["id"])
		p.ignore_texture_size = true
		p.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		p.custom_minimum_size = Vector2(92, 92)
		p.tooltip_text = "%s, level %d %s" % [hero["name"], hero["level"], hero["class"]]
		row2.add_child(p)
		var hs := ArmyStrip.new()
		hs.upgrade_town = town
		hs.upgrade_player = player
		hs.bind(hero["army"], _group, true)
		hs.changed.connect(_on_army_changed)
		row2.add_child(hs)
	_armies.add_child(row2)

	for c in _buttons.get_children():
		c.queue_free()
	# creatures available this week, one per dwelling (click to recruit), then the town's other places and Exit
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 5)
	_buttons.add_child(crow)
	for tier in range(1, 8):
		crow.add_child(_creature_cell(tier))
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	_buttons.add_child(brow)
	# the tavern, market and guild as pictures of their buildings (dimmed until built), then Exit
	var gl := TownLogic.mage_guild_level(town)
	var entries := [["Tavern", "tavern", _open_tavern, TownLogic.has_building(town, "tavern"), "Hire heroes"],
		["Market", "marketplace", _open_market, TownLogic.has_building(town, "marketplace"), "Trade resources"],
		["Mage Guild", "mage_guild_%d" % maxi(1, gl), _open_guild, gl > 0, "Spells of the guild"]]
	for e in entries:
		var b := _pic_button(_building_pic(e[1]), e[0], e[4] if e[3] else "%s: not built yet" % e[0], e[2], Vector2(132, 76))
		b.disabled = not e[3]
		if not e[3]:  # not built: the picture dark and the caption grey, as the unbuilt dwellings beside it
			b.get_meta("pic").modulate = Color(0.26, 0.25, 0.24)
			b.get_meta("band").add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
			b.get_meta("band").add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.48))
		brow.add_child(b)
	var ex := UI.button("Exit", _exit, 20)
	ex.custom_minimum_size = Vector2(132, 76)
	ex.tooltip_text = "Leave the town (Esc)"
	brow.add_child(ex)
	for r in GameData.RESOURCES:
		_res_labels[r].text = str(player["resources"].get(r, 0))

## A picture button for the bottom bar: the building's picture with its name on a band.
func _pic_button(tex: Texture2D, caption: String, tip: String, cb: Callable, sz := Vector2(156, 100)) -> Button:
	var b := UI.button("", cb)
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.clip_contents = true
	pic.position = Vector2(5, 5)
	pic.size = sz - Vector2(10, 10)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var band := Label.new()
	band.text = caption
	band.add_theme_font_size_override("font_size", 18)
	band.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.05, 0.035, 0.02, 0.85)
	band.add_theme_stylebox_override("normal", bs)
	band.position = Vector2(5, sz.y - 33)
	band.size = Vector2(sz.x - 10, 28)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(band)
	b.set_meta("pic", pic)
	b.set_meta("band", band)
	return b

## One dwelling in the bar: the creature's portrait and how many can be recruited (dimmed if not built).
func _creature_cell(tier: int) -> Button:
	var cid := TownLogic.dwelling_creature(town, tier)
	var built := TownLogic.has_building(town, "dwelling_%d" % tier)
	var b := Button.new()
	b.custom_minimum_size = Vector2(76, 100)
	b.focus_mode = Control.FOCUS_NONE
	var pic := UI.icon(Assets.creature_portrait(cid), Vector2(68, 68))
	pic.position = Vector2(4, 4)
	pic.size = pic.custom_minimum_size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not built:
		pic.modulate = Color(0.35, 0.33, 0.32)
	b.add_child(pic)
	var n := UI.label(str(town["available"][tier - 1]) if built else "-", 20, UI.GOLD if built else Color(0.55, 0.5, 0.45))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.position = Vector2(0, 72)
	n.size = Vector2(76, 26)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(n)
	var name := GameData.dwelling_name(town["faction"], tier, TownLogic.has_building(town, "dwelling_%du" % tier))
	HoverInfo.attach(b, func():
		var v := HoverInfo.creature(cid, -1, name)
		HoverInfo.line(v, ("%d available. Click to recruit." % town["available"][tier - 1]) if built else "Dwelling not built yet.", UI.GOLD, 18)
		return v)
	if built:
		b.pressed.connect(func():
			Audio.sfx("click", -6)
			_recruit_tier(tier))
	else:
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_PASS  # (still shows its info on hover)
	return b

func _on_army_changed() -> void:
	pass

# ---------------------------------------------------------------------------------------------
# Buildings on the backdrop
# ---------------------------------------------------------------------------------------------
func _rebuild_buildings() -> void:
	for b in _bld_nodes:
		b["node"].queue_free()
	_bld_nodes.clear()
	var items := []
	for id in town["buildings"]:
		var slot := TownLayout.slot_of(id)
		if not TownLayout.POS.has(slot):
			continue
		items.append([id, slot])
	items.sort_custom(func(a, b):
		var la: Array = TownLayout.POS[a[1]]
		var lb: Array = TownLayout.POS[b[1]]
		return la[2] < lb[2] if la[2] != lb[2] else la[0].y < lb[0].y)
	# Rendered towns ship a layout (pixel rect per sprite); draw far-to-near by the rect's bottom edge, the fortress
	# always first (its wide walls reach low on screen, but everything else stands in front of them).
	var rendered := _rendered_layout()
	if not rendered.is_empty():
		var depth := func(id: String) -> float:
			if TownLayout.slot_of(id) == "fort":
				return -1.0
			var r = rendered.get(TownLayout.sprite_id(id), [0, 0, 0, 0])
			return r[1] + r[3]
		items.sort_custom(func(a, b): return depth.call(a[0]) < depth.call(b[0]))
	for it in items:
		var id: String = it[0]
		var lay: Array = TownLayout.POS[it[1]]
		var sid := TownLayout.sprite_id(id)
		if not Assets.has("town/%s_%s.png" % [town["faction"], sid]):
			sid = TownLayout.slot_of(id)
		var path := "town/%s_%s.png" % [town["faction"], sid]
		var tex := Assets.tex(path, Vector2i(200, 150))
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var rect = rendered.get(sid, rendered.get(TownLayout.slot_of(id)))
		if rect != null and Assets.has(path):
			tr.position = Vector2(rect[0], rect[1])
			tr.size = Vector2(rect[2], rect[3])
		else:
			var w: float = lay[1]
			var h := w * tex.get_height() / float(tex.get_width())
			tr.size = Vector2(w, h)
			tr.position = lay[0] - Vector2(w * 0.5, h)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view.add_child(tr)
		_view.move_child(tr, 1 + _bld_nodes.size())
		var img: Image = null
		if Assets.has(path):
			img = tex.get_image()
			if img and img.is_compressed():
				img = img.duplicate()
				img.decompress()
		_bld_nodes.append({"id": id, "node": tr, "img": img})

var _layout_cache = null
func _rendered_layout() -> Dictionary:
	if _layout_cache == null:
		_layout_cache = {}
		var p := Assets.path("town/layout_%s.json" % town["faction"])
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(d) == TYPE_DICTIONARY:
				_layout_cache = d
	return _layout_cache

func _building_at(p: Vector2) -> String:
	for i in range(_bld_nodes.size() - 1, -1, -1):
		var b: Dictionary = _bld_nodes[i]
		var tr: TextureRect = b["node"]
		var r := Rect2(tr.position, tr.size)
		if not r.has_point(p):
			continue
		var img: Image = b["img"]
		if img == null:
			return b["id"]
		var local := (p - tr.position) / tr.size * Vector2(img.get_width(), img.get_height())
		var px := Vector2i(clampi(int(local.x), 0, img.get_width() - 1), clampi(int(local.y), 0, img.get_height() - 1))
		if img.get_pixelv(px).a > 0.35:
			return b["id"]
	return ""

func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_set_hover(_building_at(e.position))
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := _building_at(e.position)
		if id != "":
			Audio.sfx("click", -6)
			_hover_id = ""  # show the info again when the dialog closes
			_open_building(id)

func _set_hover(id: String) -> void:
	if id == _hover_id:
		return
	_hover_id = id
	for b in _bld_nodes:
		b["node"].modulate = Color(1.25, 1.2, 1.05) if b["id"] == id else Color.WHITE
	_status.text = GameData.building_name(town["faction"], id) if id != "" else ""
	if id == "":
		HoverInfo.hide_for(self)
	else:
		# (over the town view: not over the bottom bar's armies and buttons)
		HoverInfo.show_for(self, _building_info(id, true), 0.0, 1, -1.0, Rect2(), Rect2(0, 0, 1920, TownLayout.VIEW_H))

const CLICK_HINT := {"hall": "Click to build.", "fort": "Click to see all dwellings.", "tavern": "Click to hire a hero.",
	"marketplace": "Click to trade resources.", "mage_guild": "Click to see the spells.",
	"blacksmith": "Click to buy the town's war machine for a visiting hero.",
	"skeleton_transformer": "Click to turn a visiting hero's creatures into Skeletons."}

## Hover panel for a building: what it does; until built its requirements, cost and status; in the town view
## (`in_town`) what clicking it does.
func _building_info(id: String, in_town := false) -> Control:
	var b: Dictionary = GameData.BUILDINGS[id]
	var built := TownLogic.has_building(town, id)
	var v: VBoxContainer
	if b.has("dwelling_tier"):
		var tier: int = b["dwelling_tier"]
		var cid := _dwelling_cid(id)
		var c: Dictionary = GameData.CREATURES[cid]
		v = HoverInfo.creature(cid, -1, GameData.building_name(town["faction"], id))
		HoverInfo.line(v, "Recruits %s, +%d per week." % [c["plural"], c["growth"]], UI.TEXT, 18)
		if b.has("replaces"):
			HoverInfo.line(v, "Upgrades %s to %s in this town." % [GameData.CREATURES[GameData.base_of(cid)]["plural"], c["plural"]],
				Color(0.75, 0.85, 1.0), 18)
		if built:
			HoverInfo.line(v, "%d available. Click to recruit." % town["available"][tier - 1] if in_town else
				"%d available." % town["available"][tier - 1], UI.GOLD, 18)
	else:
		v = HoverInfo.box(GameData.building_name(town["faction"], id))
		HoverInfo.line(v, b.get("desc", ""))
		if built and in_town:
			HoverInfo.line(v, CLICK_HINT.get(TownLayout.slot_of(id), ""), UI.GOLD, 18)
	if not built:
		for req in GameData.requires(town["faction"], id):
			var ok := TownLogic.has_building(town, req)
			HoverInfo.line(v, ("Has " if ok else "Requires ") + GameData.building_name(town["faction"], req),
				Color(0.6, 0.9, 0.55) if ok else Color(1, 0.55, 0.45), 18)
		var cr := HBoxContainer.new()
		cr.add_child(UI.label("Building cost ", 18, UI.GOLD))
		cr.add_child(HoverInfo.cost_row(b["cost"], player["resources"]))
		v.add_child(cr)
		var st := _build_status(id)
		HoverInfo.line(v, st[0], st[1].lightened(0.35), 19)
	return v

func _open_building(id: String) -> void:
	var b: Dictionary = GameData.BUILDINGS[id]
	if b.has("dwelling_tier"):
		await _recruit_tier(b["dwelling_tier"])
	elif id in ["village_hall", "town_hall", "city_hall", "capitol"]:
		await _open_build()
	elif id == "skeleton_transformer":
		await _open_transformer()
	elif id in ["stables", "brotherhood", "necromancy_amplifier"]:
		await Modal.message(self, GameData.BUILDINGS[id]["name"], GameData.BUILDINGS[id]["desc"]).closed
	elif id in ["fort", "citadel", "castle"]:
		await _open_recruit_all()
	elif id == "tavern":
		await _open_tavern()
	elif id == "marketplace":
		await _open_market()
	elif id.begins_with("mage_guild"):
		await _open_guild()
	elif id == "blacksmith":
		await _open_smith()

# ---------------------------------------------------------------------------------------------
# Dialogs
# ---------------------------------------------------------------------------------------------
## Building picture for dialogs (tools/art/building_cards.py), falling back to the town sprite.
func _building_pic(id: String) -> Texture2D:
	for sid in [id, TownLayout.sprite_id(id), TownLayout.slot_of(id)]:  # (a Castle has its own card, not a sprite)
		for p in ["icons/building_%s_%s.png" % [town["faction"], sid], "town/%s_%s.png" % [town["faction"], sid]]:
			if Assets.has(p):
				return Assets.tex(p)
	return Assets.tex("town/%s_%s.png" % [town["faction"], TownLayout.sprite_id(id)])

## The creature a dwelling building recruits (an upgraded dwelling: the upgraded creature).
func _dwelling_cid(id: String) -> String:
	var b: Dictionary = GameData.BUILDINGS[id]
	if b.has("replaces"):
		return GameData.FACTIONS[town["faction"]]["upgrades"][b["dwelling_tier"] - 1]
	return GameData.faction_creature(town["faction"], b["dwelling_tier"])

## Status of a building for this player: [label, colour]. Colours follow the classic hall screen.
func _build_status(id: String) -> Array:
	if TownLogic.has_building(town, id):
		return ["Built", Color(0.95, 0.78, 0.4)]
	var reason := TownLogic.build_block_reason(town, player, id)
	if reason == "":
		return ["Can build", Color(0.5, 0.88, 0.42)]
	if reason == "Not enough resources":
		return ["Need resources", Color(1.0, 0.7, 0.3)]
	if reason == "Already built today":
		return ["Built today", Color(0.7, 0.7, 0.75)]
	return [reason, Color(1.0, 0.48, 0.4)]

## The Town Hall rows (as the classic hall screen): each card is a chain of levels and shows the next one to build
## (or the top one, once all are built): town buildings, then magic and the faction's specials, then the dwellings.
func _hall_rows() -> Array:
	var dw := func(t: int) -> Array: return ["dwelling_%d" % t, "dwelling_%du" % t]
	return [
		[["village_hall", "town_hall", "city_hall", "capitol"], ["fort", "citadel", "castle"], ["tavern"], ["marketplace"],
			["blacksmith"]],
		[["mage_guild_1", "mage_guild_2", "mage_guild_3", "mage_guild_4"]] + GameData.SPECIALS[town["faction"]].map(
			func(s): return [s]),
		[dw.call(1), dw.call(2), dw.call(3), dw.call(4)],
		[dw.call(5), dw.call(6), dw.call(7)],
	]

func _open_build() -> void:
	var m := Modal.custom(self, "Build in %s" % town["name"], 1400)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	m.body.add_child(rows)
	for row in _hall_rows():
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		rows.add_child(h)
		for chain in row:
			var id: String = chain[-1]
			for c in chain:
				if not TownLogic.has_building(town, c):
					id = c
					break
			h.add_child(_hall_card(id, m))
		var two := false  # (a long price takes two rows: the whole row of cards keeps its caption bars level)
		for card in h.get_children():
			two = two or card.price_rows() > 1
		for card in h.get_children():
			card.min_rows = 2 if two else 1
	m.add_buttons([["Close", ""]])
	m.set_meta("cancel", "")
	var r = await m.closed
	if r == null or r == "":
		return
	await _building_detail(r)

func _hall_card(id: String, m: Modal) -> Control:
	var st := _build_status(id)
	var card := _BuildCard.new()
	card.pic = _building_pic(id)
	card.title = GameData.building_name(town["faction"], id)
	card.status = st[0]
	card.status_col = st[1]
	if st[0] in ["Can build", "Need resources"]:  # the price on the card, short amounts in red
		card.cost = GameData.BUILDINGS[id]["cost"]
		card.have = player["resources"]
	card.custom_minimum_size = Vector2(250, 196)
	var bid: String = id
	HoverInfo.attach(card, func(): return _building_info(bid), 0.0, true)
	card.pressed.connect(func(): m.close(bid))
	return card

## Detail panel: big picture, what it does, requirements, cost against what you have, and a Build button.
func _building_detail(id: String) -> void:
	var b: Dictionary = GameData.BUILDINGS[id]
	var m := Modal.custom(self, GameData.building_name(town["faction"], id), 980)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	m.body.add_child(h)
	var frame := PanelContainer.new()
	h.add_child(frame)
	frame.add_child(UI.icon(_building_pic(id), Vector2(448, 280)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(440, 0)
	h.add_child(v)
	if b.has("dwelling_tier"):
		var cid := _dwelling_cid(id)
		var c: Dictionary = GameData.CREATURES[cid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(UI.icon(Assets.creature_portrait(cid), Vector2(72, 72)))
		var what := "Recruits %s.\n+%d per week." % [c["plural"], c["growth"]]
		if b.has("replaces"):
			what = "Recruits %s, and upgrades your %s\nhere. +%d per week." % [c["plural"],
				GameData.CREATURES[GameData.base_of(cid)]["plural"], c["growth"]]
		row.add_child(UI.label(what, 21))
		v.add_child(row)
	elif b.get("desc", "") != "":
		var dl := UI.label(b["desc"], 21)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(dl)
	var reqs := GameData.requires(town["faction"], id)
	if reqs.size() > 0:
		v.add_child(UI.label("Requires", 21, UI.GOLD))
		for req in reqs:
			var ok := TownLogic.has_building(town, req)
			v.add_child(UI.label(("+  " if ok else "-  ") + GameData.building_name(town["faction"], req), 19,
				Color(0.6, 0.9, 0.55) if ok else Color(1, 0.55, 0.45)))
	if not TownLogic.has_building(town, id):
		v.add_child(UI.label("Cost", 21, UI.GOLD))
		var cost := GridContainer.new()
		cost.columns = 4
		cost.add_theme_constant_override("h_separation", 14)
		v.add_child(cost)
		if b["cost"].is_empty():
			cost.add_child(UI.label("Free", 19))
		for r in GameData.RESOURCES:
			var need: int = b["cost"].get(r, 0)
			if need <= 0:
				continue
			var have: int = player["resources"].get(r, 0)
			var cell := HBoxContainer.new()
			cell.add_child(UI.icon(Assets.res_icon(r), Vector2(30, 30)))
			cell.add_child(UI.label(str(need), 20, UI.TEXT if have >= need else Color(1, 0.5, 0.4)))
			cell.tooltip_text = "%s: need %d, have %d" % [GameData.RESOURCE_NAMES[r], need, have]
			cost.add_child(cell)
	var st := _build_status(id)
	v.add_child(UI.label(st[0], 22, st[1].lightened(0.35)))
	var reason := TownLogic.build_block_reason(town, player, id)
	var btns := m.add_buttons([["Build", "build"], ["Close", ""]])
	btns.get_child(0).disabled = reason != ""
	m.set_meta("cancel", "")
	if reason == "":
		m.set_meta("default", "build")
	var res = await m.closed
	if res != "build":
		return
	if TownLogic.build(town, player, id):
		Audio.sfx("build")
		if hero.size() > 0 and id.begins_with("mage_guild"):
			for sp in town["mage_spells"]:
				if not sp in hero["spells"] and GameData.SPELLS[sp]["level"] <= 2 + int(hero["skills"].get("wisdom", 0)):
					hero["spells"].append(sp)
		refresh()
		_flash_building(id)

func _flash_building(id: String) -> void:
	for b in _bld_nodes:
		if b["id"] == id:
			var n: TextureRect = b["node"]
			n.modulate = Color(2, 1.8, 1.2, 0)
			var tw := n.create_tween()
			tw.tween_property(n, "modulate", Color.WHITE, 0.9)

func _recruit_tier(tier: int) -> void:
	var cid := TownLogic.dwelling_creature(town, tier)
	await AdventureHUD.recruit_dialog(self, cid, town["available"][tier - 1], player, town["garrison"], func(n): town["available"][tier - 1] -= n)
	refresh()

func _open_recruit_all() -> void:
	var m := Modal.custom(self, "Creature Dwellings", 1560)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	m.body.add_child(g)
	for tier in range(1, 8):
		var cid := TownLogic.dwelling_creature(town, tier)
		var built := TownLogic.has_building(town, "dwelling_%d" % tier)
		var upg := TownLogic.has_building(town, "dwelling_%du" % tier)
		var card := _DwellingCard.new()
		card.pic = _building_pic("dwelling_%d%s" % [tier, "u" if upg else ""])
		card.creature = Assets.creature(cid)
		card.anchor = Assets.anchor("creatures/%s.png" % cid)
		card.title = GameData.dwelling_name(town["faction"], tier, upg)
		card.c = GameData.CREATURES[cid]
		card.available = town["available"][tier - 1] if built else -1
		card.growth = int(card.c["growth"] * TownLogic.growth_mult(town))
		card.custom_minimum_size = Vector2(372, 300)
		card.disabled = not built
		HoverInfo.attach(card, func():
			var v := HoverInfo.creature(cid, -1, card.title)
			HoverInfo.line(v, ("%d available. Click to recruit." % card.available) if built else "Not built yet.", UI.GOLD, 18)
			return v)
		var t := tier
		card.pressed.connect(func(): m.close(t))
		g.add_child(card)
	m.add_buttons([["Close", 0]])
	m.set_meta("cancel", 0)
	var r = await m.closed
	if r is int and r > 0:
		await _recruit_tier(r)

func _tavern_offers() -> Array:
	var pool: Array = world["tavern"].duplicate()
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = town["uid"] * 31 + (world["day"] - 1) / 7
	var out := []
	# Prefer one hero of the town's faction.
	var own := pool.filter(func(h): return GameData.HEROES[h]["faction"] == town["faction"])
	if own.size() > 0:
		out.append(own[rng.randi() % own.size()])
	var rest := pool.filter(func(h): return not h in out)
	if rest.size() > 0:
		out.append(rest[rng.randi() % rest.size()])
	return out

func _open_tavern() -> void:
	var offers := _tavern_offers()
	var m := Modal.custom(self, "Tavern", 900)
	if offers.is_empty():
		m.add_text("No heroes are looking for work this week.")
	else:
		m.add_text("Heroes for hire (2500 gold):")
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 30)
	m.body.add_child(h)
	for hid in offers:
		var d: Dictionary = GameData.HEROES[hid]
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 326)
		b.focus_mode = Control.FOCUS_NONE
		var v := VBoxContainer.new()
		v.position = Vector2(10, 10)
		v.size = Vector2(340, 300)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var ic := UI.icon(Assets.hero_portrait(hid), Vector2(340, 170))
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		for t in [d["name"], "%s — %s" % [d["class"], GameData.FACTIONS[d["faction"]]["name"]], "Specialty: %s" % d["specialty"],
				"Atk %d  Def %d  Pow %d  Kno %d" % [d["attack"], d["defense"], d["power"], d["knowledge"]]]:
			var l := UI.label(t, 18)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(l)
		var id: String = hid
		b.pressed.connect(func(): m.close(id))
		h.add_child(b)
	m.add_buttons([["Leave", ""]])
	m.set_meta("cancel", "")
	var r = await m.closed
	if r == null or r == "":
		return
	if not hero.is_empty() or _hero_at_gate():
		await Modal.message(self, "Tavern", "A hero is already standing at the town gate. Send them out first.").closed
		return
	if player["resources"]["gold"] < 2500:
		Audio.sfx("error")
		await Modal.message(self, "Tavern", "You cannot afford the 2500 gold.").closed
		return
	player["resources"]["gold"] -= 2500
	world["tavern"].erase(r)
	var nh := GameState.make_hero(r, town["owner"])
	nh["pos"] = town["pos"]
	world["heroes"][nh["uid"]] = nh
	player["heroes"].append(nh["uid"])
	for s in town["mage_spells"]:
		if not s in nh["spells"] and GameData.SPELLS[s]["level"] <= 2:
			nh["spells"].append(s)
	hero = nh
	world["selected_hero"] = nh["uid"]
	Audio.sfx("recruit")
	refresh()

func _hero_at_gate() -> bool:
	for h in world["heroes"].values():
		if h["pos"] == town["pos"]:
			return true
	return false

func _open_market() -> void:
	var m := Modal.custom(self, "Marketplace", 1000)
	m.add_text("Choose what to give and what to receive.")
	var state := {"give": "wood", "get": "gold"}
	var rows := {}
	for side in ["give", "get"]:
		m.body.add_child(UI.label("You give:" if side == "give" else "You receive:", 22, UI.GOLD))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		m.body.add_child(h)
		var btns := []
		for r in GameData.RESOURCES:
			var b := Button.new()
			b.toggle_mode = true
			b.icon = Assets.res_icon(r)
			b.expand_icon = true
			b.custom_minimum_size = Vector2(120, 78)
			b.text = str(player["resources"][r]) if side == "give" else GameData.RESOURCE_NAMES[r]
			b.add_theme_font_size_override("font_size", 16)
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.add_theme_constant_override("icon_max_width", 40)
			b.set_meta("res", r)
			h.add_child(b)
			btns.append(b)
		rows[side] = btns
	var rate_l := UI.label("", 22)
	m.body.add_child(rate_l)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(900, 30)
	m.body.add_child(slider)
	var amount_l := UI.label("", 22, UI.GOLD)
	m.body.add_child(amount_l)
	var rate := func(give: String, get: String) -> float:
		return float(RES_VALUE[give]) * 0.5 / float(RES_VALUE[get])
	var upd := func(_v = 0):
		for side in rows:
			for b in rows[side]:
				b.button_pressed = b.get_meta("res") == state[side]
		var g: String = state["give"]
		var gt: String = state["get"]
		if g == gt:
			rate_l.text = "Pick two different resources."
			slider.max_value = 0
			amount_l.text = ""
			return
		var rt: float = rate.call(g, gt)
		var unit := 1
		if rt < 1.0:
			unit = int(ceil(1.0 / rt))
		rate_l.text = "Rate: %d %s for %d %s" % [unit, GameData.RESOURCE_NAMES[g], int(unit * rt), GameData.RESOURCE_NAMES[gt]]
		slider.step = unit
		slider.max_value = int(player["resources"][g] / unit) * unit
		var n := int(slider.value)
		amount_l.text = "Trade %d %s for %d %s" % [n, GameData.RESOURCE_NAMES[g], int(n * rt), GameData.RESOURCE_NAMES[gt]]
	for side in rows:
		for b in rows[side]:
			var sd: String = side
			b.pressed.connect(func():
				state[sd] = b.get_meta("res")
				slider.value = 0
				upd.call())
	slider.value_changed.connect(upd)
	upd.call()
	m.add_buttons([["Trade", "trade"], ["Done", "done"]])
	m.set_meta("cancel", "done")
	var r = await m.closed
	if r == "trade" and slider.value > 0 and state["give"] != state["get"]:
		var n := int(slider.value)
		var got := int(n * rate.call(state["give"], state["get"]))
		player["resources"][state["give"]] -= n
		player["resources"][state["get"]] += got
		Audio.sfx("gold_pickup")
		refresh()
		await _open_market()

func _open_guild() -> void:
	var m := Modal.custom(self, "Mage Guild (level %d)" % TownLogic.mage_guild_level(town), 1100)
	for lvl in range(1, 5):
		var spells: Array = town["mage_spells"].filter(func(s): return GameData.SPELLS[s]["level"] == lvl)
		if spells.is_empty():
			continue
		m.body.add_child(UI.label("Level %d" % lvl, 22, UI.GOLD))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		m.body.add_child(h)
		for s in spells:
			var sp: Dictionary = GameData.SPELLS[s]
			var v := VBoxContainer.new()
			v.custom_minimum_size = Vector2(240, 0)
			v.add_child(UI.icon(Assets.spell_icon(s), Vector2(80, 80)))
			var nl := UI.label("%s (%d mana)" % [sp["name"], sp["mana"]], 18, UI.GOLD)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(nl)
			var d := UI.label(sp["desc"], 16)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			d.custom_minimum_size = Vector2(240, 0)
			v.add_child(d)
			h.add_child(v)
	if not hero.is_empty():
		m.add_text("Visiting heroes learn every spell their wisdom allows and regain all their mana.", 18)
	m.add_buttons([["Close", true]])
	m.set_meta("cancel", true)
	await m.closed

## The Skeleton Transformer: each living stack of the visiting hero (or the garrison) can be turned into Skeletons.
func _open_transformer() -> void:
	while true:
		var m := Modal.custom(self, "Skeleton Transformer", 1100)
		m.body.add_child(UI.label("Living creatures thrown in come out as as many Skeletons.", 20))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 14)
		row.add_theme_constant_override("v_separation", 10)
		row.custom_minimum_size.x = 1040
		m.body.add_child(row)
		var any := false
		for army in ([hero["army"]] if not hero.is_empty() else []) + [town["garrison"]]:
			for st in army:
				if st == null or "undead" in GameData.CREATURES[st["id"]]["abilities"]:
					continue
				any = true
				var v := VBoxContainer.new()
				v.add_child(UI.icon(Assets.creature_portrait(st["id"]), Vector2(150, 150)))
				var c: Dictionary = GameData.CREATURES[st["id"]]
				var t := UI.label("%d %s" % [st["count"], c["plural"] if st["count"] != 1 else c["name"]], 18)
				t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				t.custom_minimum_size.x = 150
				v.add_child(t)
				var s2: Dictionary = st
				v.add_child(UI.button("Transform", func(): m.close(s2), 19))
				row.add_child(v)
		if not any:
			row.add_child(UI.label("There are no living creatures here.", 20, Color(0.8, 0.7, 0.6)))
		m.add_buttons([["Close", ""]])
		m.set_meta("cancel", "")
		var r = await m.closed
		if not r is Dictionary:
			break
		if TownLogic.transform_to_skeletons(r):
			Audio.sfx("magic_hit", -4)
		refresh()

## The Blacksmith sells the town's own war machine to a visiting hero, who can field one of each kind (as the classic
## towns: the Castle's smith forges ballistas, the Necropolis's first aid tents).
func _open_smith() -> void:
	var id: String = GameData.SMITH_MACHINE.get(town["faction"], "ballista")
	var c: Dictionary = GameData.CREATURES[id]
	var m := Modal.custom(self, "Blacksmith", 560)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.body.add_child(v)
	var t := UI.label(c["name"], 28, UI.GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var pic := UI.icon(Assets.creature_portrait(id), Vector2(300, 300))
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	var d := UI.label(GameData.MACHINE_TEXT[id], 20)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(500, 0)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	var cr := HoverInfo.cost_row(c["cost"], player["resources"])
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(cr)
	var why := ""
	if hero.is_empty():
		why = "A hero must visit the town to take a war machine."
	elif id in hero.get("machines", []):
		why = "%s already has a %s." % [hero["name"], c["name"]]
	elif not TownLogic.can_afford(player, c["cost"]):
		why = "Not enough gold."
	if why != "":
		var w := UI.label(why, 19, Color(1, 0.6, 0.5))
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(w)
	var btns := m.add_buttons([["Buy", "buy"], ["Close", ""]])
	btns.get_child(0).disabled = why != ""
	m.set_meta("cancel", "")
	if await m.closed == "buy":
		TownLogic.pay(player, c["cost"])
		if not hero.has("machines"):
			hero["machines"] = []
		hero["machines"].append(id)
		Audio.sfx("build", -4)
		refresh()

func _exit() -> void:
	GameState.change_scene(GameState.SCENE_ADVENTURE)

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var l := get_tree().root.get_node_or_null("ModalLayer")
	if l != null and l.get_child_count() > 0:
		return
	match e.keycode:
		KEY_ESCAPE:
			_exit()
		KEY_B:
			_open_build()
		KEY_R:
			_open_recruit_all()

class _Banner extends Control:
	var color := Color.RED
	var town_tex: Texture2D = null  # the town's map picture, with a small owner pennant
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.04))
		if town_tex:
			var ts := Vector2(town_tex.get_size())
			var sc := minf((size.x - 6) / ts.x, (size.y - 6) / ts.y) * 1.25  # the map sprite has empty margins
			var ds := ts * sc
			draw_texture_rect(town_tex, Rect2((size - ds) * 0.5 + Vector2(0, 6), ds), false)
			draw_colored_polygon(PackedVector2Array([Vector2(6, 6), Vector2(30, 6), Vector2(30, 34), Vector2(18, 28), Vector2(6, 34)]), color)
			draw_rect(Rect2(Vector2.ZERO, size), UI.GOLD_DARK, false, 2.0)
			return
		var pts := PackedVector2Array([Vector2(18, 8), Vector2(size.x - 18, 8), Vector2(size.x - 18, size.y - 22), Vector2(size.x * 0.5, size.y - 8), Vector2(18, size.y - 22)])
		draw_colored_polygon(pts, color)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, UI.GOLD, 2.0)
		draw_rect(Rect2(Vector2.ZERO, size), UI.GOLD_DARK, false, 2.0)


## Hall-screen card: building picture, name, and a coloured status bar.
class _BuildCard extends Button:
	var pic: Texture2D
	var title := ""
	var status := ""
	var status_col := Color.GRAY
	var cost := {}
	var have := {}
	var min_rows := 1
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
	func price_rows() -> int:
		var n := 0
		for res in GameData.RESOURCES:
			if cost.get(res, 0) > 0:
				n += 1
		return 2 if n > 3 else 1
	## The caption bar takes the status colour, as on the classic hall plates: green to build, red when blocked or
	## short of resources, gold once built (its picture dimmed, with a tick); the price under it, in two rows if long.
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.07, 0.05, 0.03))
		var f := UI.font()
		var items := []
		for res in GameData.RESOURCES:
			if cost.get(res, 0) > 0:
				items.append([res, str(cost[res])])
		var rows: Array = [items]
		if items.size() > 3:
			rows = [items.slice(0, (items.size() + 1) / 2), items.slice((items.size() + 1) / 2)]
		var strip_h := 26.0 * maxi(rows.size(), min_rows)
		var bottom := 35.0 + strip_h + 5.0
		var built := status == "Built"
		var pr := Rect2(Vector2(5, 5), Vector2(size.x - 10, size.y - bottom - 5))
		if pic:
			var ts := Vector2(pic.get_size())
			var sc := maxf(pr.size.x / ts.x, pr.size.y / ts.y)
			var tint := Color(0.55, 0.53, 0.5) if built else Color.WHITE
			if is_hovered():
				tint *= Color(1.15, 1.12, 1.05)
			draw_texture_rect_region(pic, pr, Rect2((ts - pr.size / sc) * 0.5, pr.size / sc), tint)
		if built:  # a gold tick in the corner of the picture
			var c := pr.end - Vector2(24, 22)
			draw_circle(c, 15, Color(0.1, 0.07, 0.03, 0.85))
			draw_arc(c, 15, 0, TAU, 24, UI.GOLD, 2.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 6), c + Vector2(8, -6)]), UI.GOLD, 3.5, true)
		var tb := Rect2(Vector2(5, size.y - bottom), Vector2(size.x - 10, 30))
		var bar := Color(0.4, 0.11, 0.07)
		match status:
			"Can build": bar = Color(0.13, 0.32, 0.1)
			"Built": bar = Color(0.42, 0.33, 0.1)
			"Built today": bar = Color(0.24, 0.23, 0.25)
		draw_rect(tb, bar)
		draw_rect(Rect2(tb.position, Vector2(tb.size.x, 2)), bar.lightened(0.35))
		draw_string_outline(f, Vector2(5, tb.position.y + 22), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 19, 3, Color(0, 0, 0, 0.75))
		draw_string(f, Vector2(5, tb.position.y + 22), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 19, Color(1, 0.93, 0.75))
		# status: a dark strip with a coloured gem and coloured text (or the price)
		var sb := Rect2(Vector2(5, size.y - 5 - strip_h), Vector2(size.x - 10, strip_h))
		draw_rect(sb, Color(0.1, 0.075, 0.05))
		var gem := sb.position + Vector2(14, strip_h * 0.5)
		draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -7), gem + Vector2(7, 0), gem + Vector2(0, 7), gem + Vector2(-7, 0)]), status_col)
		draw_polyline(PackedVector2Array([gem + Vector2(0, -7), gem + Vector2(7, 0), gem + Vector2(0, 7), gem + Vector2(-7, 0), gem + Vector2(0, -7)]), Color(0, 0, 0, 0.7), 1.0)
		var x0 := sb.position.x + 28
		var room := sb.end.x - 6 - x0
		if not items.is_empty():
			var ic := 20.0
			var fs := 17
			for k in rows.size():
				var row: Array = rows[k]
				var w := 0.0
				for it in row:
					w += ic + 3 + f.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12
				w -= 12
				var x := x0 + maxf(0.0, (room - w) * 0.5)
				var cy := sb.position.y + 13 + 26 * k + 13.0 * (maxi(rows.size(), min_rows) - rows.size())
				for it in row:
					draw_texture_rect(Assets.res_icon(it[0]), Rect2(Vector2(x, cy - ic * 0.5), Vector2(ic, ic)), false)
					var ok: bool = have.get(it[0], 0) >= cost[it[0]]
					draw_string(f, Vector2(x + ic + 3, cy + 6), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.9, 0.8) if ok else Color(1, 0.48, 0.4))
					x += ic + 3 + f.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12
		else:
			var txt := status
			while txt.length() > 4 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > room:
				txt = txt.left(txt.length() - 2)
			if txt != status:
				txt += "..."
			draw_string(f, Vector2(x0, sb.position.y + strip_h * 0.5 + 6), txt, HORIZONTAL_ALIGNMENT_CENTER, room, 17, status_col)
		draw_rect(r, UI.GOLD if is_hovered() else UI.GOLD_DARK, false, 2.0 if is_hovered() else 1.5)

## Dwelling card: the building as backdrop, the creature standing in front, availability and cost.
class _DwellingCard extends Button:
	var pic: Texture2D
	var creature: Texture2D
	var anchor := Vector2(0.5, 0.9)
	var title := ""
	var c: Dictionary
	var available := -1
	var growth := 0
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
	## Title band on top, the dwelling art with its creature, and under it: creature, stats, cost and growth.
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var dim := Color.WHITE if available >= 0 else Color(0.38, 0.36, 0.36)
		draw_rect(r, Color(0.07, 0.05, 0.03))
		var f := UI.font()
		var tf := UI.title_font()
		draw_rect(Rect2(Vector2(5, 5), Vector2(size.x - 10, 30)), Color(0.15, 0.1, 0.05))
		draw_string(tf, Vector2(5, 28), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 20, UI.GOLD)
		var pr := Rect2(Vector2(5, 37), Vector2(size.x - 10, size.y - 37 - 92))
		if pic:
			var ts := Vector2(pic.get_size())
			var sc := maxf(pr.size.x / ts.x, pr.size.y / ts.y)
			draw_texture_rect_region(pic, pr, Rect2((ts - pr.size / sc) * 0.5, pr.size / sc), dim * Color(0.78, 0.78, 0.78))
		if creature:
			var cs := Vector2(creature.get_size())
			var sc2 := minf(pr.size.y * 0.95 / cs.y, pr.size.x * 0.8 / cs.x)
			var feet := Vector2(pr.position.x + pr.size.x * 0.5, pr.end.y - 4)
			draw_texture_rect(creature, Rect2(feet - anchor * cs * sc2, cs * sc2), false, dim)
		var y0 := size.y - 90
		draw_rect(Rect2(Vector2(5, y0), Vector2(size.x - 10, 85)), Color(0.12, 0.09, 0.06))
		draw_string(tf, Vector2(14, y0 + 22), c.get("plural", ""), HORIZONTAL_ALIGNMENT_LEFT, 200, 20, UI.TEXT)
		var avail := ("Available: %d" % available) if available >= 0 else "Not built"
		draw_string(f, Vector2(size.x - 214, y0 + 21), avail, HORIZONTAL_ALIGNMENT_RIGHT, 200, 18,
			UI.GOLD if available > 0 else Color(0.75, 0.7, 0.6))
		var d: Array = c.get("dmg", [0, 0])
		var stats := "Att %d   Def %d   Dmg %s   HP %d   Spd %d" % [c.get("attack", 0), c.get("defense", 0), GameData.dmg_text(d[0], d[1]), c.get("hp", 0), c.get("speed", 0)]
		draw_string(f, Vector2(14, y0 + 47), stats, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 16, Color(0.82, 0.78, 0.68))
		var x := 14.0
		for res in c.get("cost", {}):
			draw_texture_rect(Assets.res_icon(res), Rect2(Vector2(x, y0 + 57), Vector2(22, 22)), false)
			var amt := str(c["cost"][res])
			draw_string(f, Vector2(x + 26, y0 + 75), amt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UI.TEXT)
			x += 34 + f.get_string_size(amt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(f, Vector2(size.x - 214, y0 + 75), "+%d / week" % growth, HORIZONTAL_ALIGNMENT_RIGHT, 200, 17,
			Color(0.55, 0.9, 0.5) if available >= 0 else Color(0.6, 0.58, 0.52))
		draw_rect(r, UI.GOLD if is_hovered() and available >= 0 else UI.GOLD_DARK, false, 1.5)
