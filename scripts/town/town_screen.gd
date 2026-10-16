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
		if Shot.setup.contains("rich"):
			var t: Dictionary = world["towns"][uid]
			t["buildings"] = ["city_hall", "citadel", "tavern", "marketplace", "mage_guild_2", "blacksmith",
				"dwelling_1", "dwelling_2", "dwelling_3", "dwelling_4", "dwelling_5", "dwelling_6", "dwelling_7"]
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
	_info.add_child(UI.label("%s town" % GameData.FACTIONS[town["faction"]]["name"], 24, UI.GOLD))
	_info.add_child(UI.label("Income: %d gold / day" % TownLogic.daily_income(town), 21))
	var gl := TownLogic.mage_guild_level(town)
	_info.add_child(UI.label("Mage Guild: %s" % ("level %d" % gl if gl > 0 else "none"), 21))
	_info.add_child(UI.label("Fortifications: %s" % ("Citadel" if TownLogic.has_building(town, "citadel") else ("Fort" if TownLogic.has_building(town, "fort") else "none")), 21))
	_info.add_child(UI.label("Already built today" if town["built_today"] else "You may build today", 20, Color(0.8, 0.6, 0.5) if town["built_today"] else Color(0.6, 0.9, 0.55)))

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
		hs.bind(hero["army"], _group, true)
		hs.changed.connect(_on_army_changed)
		row2.add_child(hs)
	_armies.add_child(row2)

	for c in _buttons.get_children():
		c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_buttons.add_child(grid)
	var entries := [["Build", _open_build, true], ["Recruit", _open_recruit_all, true],
		["Tavern", _open_tavern, TownLogic.has_building(town, "tavern")],
		["Market", _open_market, TownLogic.has_building(town, "marketplace")],
		["Mage Guild", _open_guild, TownLogic.mage_guild_level(town) > 0],
		["Exit", _exit, true]]
	for e in entries:
		var b := UI.button(e[0], e[1], 21)
		b.custom_minimum_size = Vector2(178, 58)
		b.disabled = not e[2]
		grid.add_child(b)
	for r in GameData.RESOURCES:
		_res_labels[r].text = str(player["resources"].get(r, 0))

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
	# Rendered towns ship a layout (pixel rect per sprite); draw far-to-near by the rect's bottom edge.
	var rendered := _rendered_layout()
	if not rendered.is_empty():
		items.sort_custom(func(a, b):
			var ra = rendered.get(TownLayout.sprite_id(a[0]), [0, 0, 0, 0])
			var rb = rendered.get(TownLayout.sprite_id(b[0]), [0, 0, 0, 0])
			return ra[1] + ra[3] < rb[1] + rb[3])
	for it in items:
		var id: String = it[0]
		var lay: Array = TownLayout.POS[it[1]]
		var path := "town/%s_%s.png" % [town["faction"], TownLayout.sprite_id(id)]
		var tex := Assets.tex(path, Vector2i(200, 150))
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var rect = rendered.get(TownLayout.sprite_id(id))
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
			_open_building(id)

func _set_hover(id: String) -> void:
	if id == _hover_id:
		return
	_hover_id = id
	for b in _bld_nodes:
		b["node"].modulate = Color(1.25, 1.2, 1.05) if b["id"] == id else Color.WHITE
	_status.text = GameData.building_name(town["faction"], id) if id != "" else ""

func _open_building(id: String) -> void:
	var b: Dictionary = GameData.BUILDINGS[id]
	if b.has("dwelling_tier"):
		await _recruit_tier(b["dwelling_tier"])
	elif id in ["village_hall", "town_hall", "city_hall"]:
		await _open_build()
	elif id in ["fort", "citadel"]:
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
	var sid := TownLayout.sprite_id(id)
	var p := "icons/building_%s_%s.png" % [town["faction"], sid]
	return Assets.tex(p if Assets.has(p) else "town/%s_%s.png" % [town["faction"], sid])

## Status of a building for this player: [label, colour]. Colours follow the classic hall screen.
func _build_status(id: String) -> Array:
	if TownLogic.has_building(town, id):
		return ["Built", Color(0.85, 0.68, 0.22)]
	var reason := TownLogic.build_block_reason(town, player, id)
	if reason == "":
		return ["Can build", Color(0.25, 0.62, 0.22)]
	if reason == "Not enough resources":
		return ["Need resources", Color(0.75, 0.55, 0.15)]
	if reason == "Already built today":
		return ["Built today", Color(0.4, 0.4, 0.45)]
	return [reason, Color(0.62, 0.2, 0.16)]

func _open_build() -> void:
	var m := Modal.custom(self, "Build in %s" % town["name"], 1660)
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	m.body.add_child(g)
	var ids: Array = TownLogic.buildable_list(town)
	for id in town["buildings"]:
		if not id in ids:
			ids.append(id)
	# buildable first, then can't-afford, then blocked, then built; data order within each group
	var rank := func(id: String) -> int:
		if id in town["buildings"]:
			return 3
		var rs := TownLogic.build_block_reason(town, player, id)
		return 0 if rs == "" else (1 if rs == "Not enough resources" else 2)
	ids.sort_custom(func(a, b):
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		return ra < rb if ra != rb else GameData.BUILDINGS.keys().find(a) < GameData.BUILDINGS.keys().find(b))
	for id in ids:
		var st := _build_status(id)
		var card := _BuildCard.new()
		card.pic = _building_pic(id)
		card.title = GameData.building_name(town["faction"], id)
		card.status = st[0]
		card.status_col = st[1]
		card.custom_minimum_size = Vector2(262, 226)
		card.tooltip_text = GameData.BUILDINGS[id].get("desc", "")
		var bid: String = id
		card.pressed.connect(func(): m.close(bid))
		g.add_child(card)
	m.add_buttons([["Close", ""]])
	m.set_meta("cancel", "")
	var r = await m.closed
	if r == null or r == "":
		return
	await _building_detail(r)

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
		var cid := GameData.faction_creature(town["faction"], b["dwelling_tier"])
		var c: Dictionary = GameData.CREATURES[cid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(UI.icon(Assets.creature_portrait(cid), Vector2(72, 72)))
		row.add_child(UI.label("Recruits %s.\n+%d per week." % [c["plural"], c["growth"]], 21))
		v.add_child(row)
	elif b.get("desc", "") != "":
		var dl := UI.label(b["desc"], 21)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(dl)
	if b["requires"].size() > 0:
		v.add_child(UI.label("Requires", 21, UI.GOLD))
		for req in b["requires"]:
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
	var cid := GameData.faction_creature(town["faction"], tier)
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
		var cid := GameData.faction_creature(town["faction"], tier)
		var built := TownLogic.has_building(town, "dwelling_%d" % tier)
		var card := _DwellingCard.new()
		card.pic = _building_pic("dwelling_%d" % tier)
		card.creature = Assets.creature(cid)
		card.anchor = Assets.anchor("creatures/%s.png" % cid)
		card.title = GameData.dwelling_name(town["faction"], tier)
		card.c = GameData.CREATURES[cid]
		card.available = town["available"][tier - 1] if built else -1
		card.custom_minimum_size = Vector2(372, 262)
		card.disabled = not built
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

func _open_smith() -> void:
	if hero.is_empty():
		await Modal.message(self, "Blacksmith", "The smith can hone the weapons of a visiting hero (+1 Attack for 1500 gold).").closed
		return
	if hero.get("smith", false):
		await Modal.message(self, "Blacksmith", "%s's weapons are already as sharp as they can be." % hero["name"]).closed
		return
	if await Modal.confirm(self, "Blacksmith", "Hone %s's weapons for 1500 gold? (+1 Attack)" % hero["name"], "Hone", "No").closed:
		if player["resources"]["gold"] >= 1500:
			player["resources"]["gold"] -= 1500
			hero["attack"] += 1
			hero["smith"] = true
			Audio.sfx("sword_hit")
			refresh()
		else:
			Audio.sfx("error")

func _exit() -> void:
	GameState.change_scene(GameState.SCENE_ADVENTURE)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		var l := get_tree().root.get_node_or_null("ModalLayer")
		if l == null or l.get_child_count() == 0:
			_exit()

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
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.07, 0.05, 0.03))
		var pr := Rect2(Vector2(5, 5), Vector2(size.x - 10, size.y - 66))
		if pic:
			var ts := Vector2(pic.get_size())
			var sc := maxf(pr.size.x / ts.x, pr.size.y / ts.y)
			draw_texture_rect_region(pic, pr, Rect2((ts - pr.size / sc) * 0.5, pr.size / sc),
				Color(1.15, 1.12, 1.05) if is_hovered() else Color.WHITE)
		var f := UI.font()
		draw_rect(Rect2(Vector2(5, size.y - 61), Vector2(size.x - 10, 30)), Color(0.12, 0.09, 0.06))
		draw_string(f, Vector2(5, size.y - 39), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 19, UI.GOLD)
		var sb := Rect2(Vector2(5, size.y - 31), Vector2(size.x - 10, 26))
		draw_rect(sb, status_col)
		draw_rect(sb, Color(0, 0, 0, 0.5), false, 1.0)
		var txt := status
		while txt.length() > 4 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > sb.size.x - 10:
			txt = txt.left(txt.length() - 2)
		if txt != status:
			txt += "..."
		draw_string(f, Vector2(5, size.y - 12), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 17, Color(1, 0.97, 0.9))
		draw_rect(r, UI.GOLD if is_hovered() else UI.GOLD_DARK, false, 2.0 if is_hovered() else 1.5)

## Dwelling card: the building as backdrop, the creature standing in front, availability and cost.
class _DwellingCard extends Button:
	var pic: Texture2D
	var creature: Texture2D
	var anchor := Vector2(0.5, 0.9)
	var title := ""
	var c: Dictionary
	var available := -1
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var dim := Color.WHITE if available >= 0 else Color(0.38, 0.36, 0.36)
		draw_rect(r, Color(0.07, 0.05, 0.03))
		var pr := Rect2(Vector2(5, 5), Vector2(size.x - 10, size.y - 64))
		if pic:
			var ts := Vector2(pic.get_size())
			var sc := maxf(pr.size.x / ts.x, pr.size.y / ts.y)
			draw_texture_rect_region(pic, pr, Rect2((ts - pr.size / sc) * 0.5, pr.size / sc), dim * Color(0.78, 0.78, 0.78))
		if creature:
			var cs := Vector2(creature.get_size())
			var sc2 := minf(pr.size.y * 0.95 / cs.y, pr.size.x * 0.8 / cs.x)
			var feet := Vector2(pr.position.x + pr.size.x * 0.5, pr.end.y - 4)
			draw_texture_rect(creature, Rect2(feet - anchor * cs * sc2, cs * sc2), false, dim)
		var f := UI.font()
		draw_rect(Rect2(Vector2(5, 5), Vector2(size.x - 10, 28)), Color(0, 0, 0, 0.55))
		draw_string(f, Vector2(5, 26), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 19, UI.GOLD)
		draw_rect(Rect2(Vector2(5, size.y - 59), Vector2(size.x - 10, 54)), Color(0.12, 0.09, 0.06))
		var avail := ("Available: %d" % available) if available >= 0 else "Not built"
		draw_string(f, Vector2(14, size.y - 36), c.get("plural", ""), HORIZONTAL_ALIGNMENT_LEFT, 200, 18, UI.TEXT)
		draw_string(f, Vector2(size.x - 214, size.y - 36), avail, HORIZONTAL_ALIGNMENT_RIGHT, 200, 18,
			UI.GOLD if available > 0 else Color(0.75, 0.7, 0.6))
		var x := 14.0
		for res in c.get("cost", {}):
			draw_texture_rect(Assets.res_icon(res), Rect2(Vector2(x, size.y - 30), Vector2(22, 22)), false)
			var amt := str(c["cost"][res])
			draw_string(f, Vector2(x + 26, size.y - 12), amt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UI.TEXT)
			x += 34 + f.get_string_size(amt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_rect(r, UI.GOLD if is_hovered() and available >= 0 else UI.GOLD_DARK, false, 1.5)
