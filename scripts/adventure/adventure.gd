extends Node2D
## Adventure map scene controller: input, camera, hero movement, visits, turns, AI turns.

const TILE := WorldGen.TILE
const MAP_VIEW_W := 1540.0   # visible map width (right panel covers the rest)
const MAP_VIEW_H := 1036.0

var world: Dictionary
var rules: AdvRules
var view: MapView
var hud: AdventureHUD
var ai: AdvAI
var cam: Camera2D
var busy := false
var _plan := {}
var _plan_target := Vector2i(-1, -1)
var _drag_from := Vector2.ZERO
var _dragging := false
var _drag_button := MOUSE_BUTTON_NONE  # the button driving the press/drag (left or middle)
var _drag_screen := Vector2i.ZERO      # last cursor position on the screen while it is held
var _press_screen := Vector2i.ZERO     # where on the screen the button went down
var _drag_synced := false              # a motion event moved the map this frame (the poll only resyncs)
var _left_down := false      # left button held on the map: a click on release, or a drag once it moves
var _left_tile := Vector2i(-1, -1)
var _info_tile := Vector2i(-2, -2)
var _pending_click := Vector2i(-1, -1)  # clicked while the hero was still moving: planned when it stops
const DRAG_START := 10.0
const EDGE := 14.0           # edge-scroll band (screen pixels), also just outside the window
var _cam_target := Vector2.ZERO
var _follow := -1            # the walking hero the camera rides along with (its sprite, not its tile)

func _ready() -> void:
	if GameState.world.is_empty():
		var s := GameState.new_game_settings.duplicate()
		if Shot.setup != "":
			s["seed"] = int(Shot.args.get("seed", "12345"))
			s["faction"] = Shot.args.get("faction", s.get("faction", "haven"))
		GameState.world = WorldGen.generate(s)
		if Shot.setup == "artifacts":  # (judge shot: one artifact of each tier laid out beside the first hero)
			_shot_artifacts(GameState.world)
		if Shot.setup == "all_spells":
			for h in GameState.world["heroes"].values():  # a seasoned hero: spells, skills and some gear
				h["spells"] = GameData.SPELLS.keys()
				h["skills"].merge({"wisdom": 2, "offense": 1, "logistics": 3})
				h["artifacts"] = []
				h["backpack"] = []
				# (every tier, and a combination: the dragon set merges as its last part arrives)
				for a in ["dragonbone_blade", "dragonscale_shield", "dragonskull_helm", "gravecloak", "pendant_of_clarity",
						"sunsteel_cuirass", "ring_of_vitality", "signet_of_coin", "travellers_boots", "orb_of_embers",
						"clover_of_fortune", "seers_spyglass", "banner_of_the_muster", "soldiers_shortsword",
						"bone_crown", "sun_pendant", "boots_of_speed", "seraphs_feather"]:
					GameState.give_artifact(h, a)  # (as found: worn while a slot is free, then the backpack)
				h["max_movement"] = GameState.hero_max_movement(h)
				h["movement"] = h["max_movement"]
	world = GameState.world
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.03))
	rules = AdvRules.new(world)
	ai = AdvAI.new(rules)

	view = MapView.new()
	add_child(view)
	view.setup(world)

	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	cam.zoom = Vector2.ONE * GameState.map_zoom
	add_child(cam)
	cam.make_current()

	hud = AdventureHUD.new()
	add_child(hud)
	hud.setup(self)

	for p in world["players"]:
		rules.reveal_all_for(p)
	_refresh_fog()

	var sel: int = world.get("selected_hero", -1)
	if not world["heroes"].has(sel) or world["heroes"][sel]["owner"] != _human():
		sel = _first_hero_with_mp()
	_select_hero(sel, true)
	_update_music()
	_post_ready.call_deferred()

func _post_ready() -> void:
	await get_tree().process_frame
	if Shot.active:
		_shot_view()
	if not GameState.battle_result.is_empty():
		var result := GameState.battle_result
		GameState.battle_result = {}
		var ev := rules.apply_battle(result)
		view.rebuild_objects()
		_refresh_fog()
		hud.refresh()
		if ev["hero"] >= 0 and world["heroes"].has(ev["hero"]):
			await _handle_level_ups(world["heroes"][ev["hero"]])
		if not world["heroes"].has(world.get("selected_hero", -1)):
			_select_hero(_first_hero_with_mp())
		if await _check_game_over():
			return
	if not world.get("intro_shown", false) and world.has("scenario") and not Shot.active:
		# the scenario's briefing, once, as the game begins
		world["intro_shown"] = true
		var sc: Dictionary = world["scenario"]
		await Modal.message(self, sc["name"], "%s\n\nVictory: %s.\nDefeat: %s." % [sc["desc"],
			GameData.victory_text(sc["victory"]), GameData.loss_text(sc["loss"])]).closed
	if world["players"][world["current_player"]]["is_ai"]:
		_run_ai_turns()
	elif world.get("pending_turn_banner", false):
		world["pending_turn_banner"] = false
		_turn_banner()

func _human() -> int:
	return GameState.human_player_index()

func human_player() -> Dictionary:
	return world["players"][_human()]

func selected_hero() -> Dictionary:
	return world["heroes"].get(world.get("selected_hero", -1), {})

# ---------------------------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------------------------
## Screenshot harness options: --reveal (no fog), --cam=x,y (tile to centre on), --zoom=z; with --setup also
## --seed=n and --faction=f for the generated map.
## Screenshot setup: a relic, a major, a minor and a treasure artifact and a set part on free tiles beside the first
## hero, so the judge sees how artifacts lie on the map.
static func _shot_artifacts(w: Dictionary) -> void:
	var p0: Dictionary = w["players"][0]
	var hero: Dictionary = w["heroes"][p0["heroes"][0]]
	var size: Vector2i = w["size"]
	var taken := {}
	for o in w["objects"].values():
		taken[o["pos"]] = true
	for t in w["towns"].values():
		for dy in range(-3, 2):
			for dx in range(-3, 4):
				taken[t["pos"] + Vector2i(dx, dy)] = true
	var picks := ["banner_of_the_muster", "orb_of_embers", "cape_of_courage", "soldiers_shortsword", "dragonskull_helm"]
	for r in range(2, 7):
		for dy in range(-r, 1):  # (beside and above the hero: below, the resource bar would cover them)
			for dx in range(-r, r + 1):
				if picks.is_empty():
					return
				var q: Vector2i = hero["pos"] + Vector2i(dx, dy)
				if q.x < 1 or q.y < 1 or q.x >= size.x - 1 or q.y >= size.y - 1 or taken.has(q):
					continue
				var i := q.y * size.x + q.x
				if w["blocked"][i] != 0 or w["terrain"][i] in [WorldGen.T_WATER, WorldGen.T_ROAD]:
					continue
				var near_tree := false  # (a tree's long shadow or a stump beside it read as a stain under the item)
				for d in w["decor"]:
					var dt := Vector2i(d["p"] / WorldGen.TILE)
					var k: String = d["k"]
					if absi(dt.x - q.x) <= 1 and dt.y - q.y >= -1 and dt.y - q.y <= 2 \
							and (k.begins_with("tree") or k.contains("stump") or k.begins_with("snow_pine")):
						near_tree = true
				if near_tree:
					continue
				var o := {"type": "artifact", "artifact": picks.pop_front(), "uid": GameState.next_uid(), "pos": q}
				w["objects"][o["uid"]] = o
				w["decor"] = w["decor"].filter(func(d): return Vector2i(d["p"] / WorldGen.TILE) != q)  # (flowers on it)
				for ddy in range(-1, 2):
					for ddx in range(-1, 2):
						taken[q + Vector2i(ddx, ddy)] = true

func _shot_view() -> void:
	if Shot.args.has("reveal"):
		human_player()["explored"].fill(1)
		_refresh_fog()
	if Shot.args.has("zoom"):
		cam.zoom = Vector2.ONE * float(Shot.args["zoom"])
	if Shot.args.has("cam"):
		var xy: PackedStringArray = Shot.args["cam"].split(",")
		center_on(Vector2i(int(xy[0]), int(xy[1])), true)

func center_on(tile: Vector2i, instant := false) -> void:
	var p := view.tile_center(tile)
	_cam_target = _clamp_cam(p - Vector2(MAP_VIEW_W, MAP_VIEW_H) * 0.5 / cam.zoom)
	if instant:
		cam.position = _cam_target

func center_on_world(p: Vector2) -> void:
	_cam_target = _clamp_cam(p - Vector2(MAP_VIEW_W, MAP_VIEW_H) * 0.5 / cam.zoom)

func _clamp_cam(p: Vector2) -> Vector2:
	var size: Vector2 = Vector2(world["size"]) * TILE
	var view_sz := Vector2(MAP_VIEW_W, MAP_VIEW_H) / cam.zoom
	var margin := 2.0 * TILE  # (as the classic map: the view runs a little past the edge, onto its rocky border)
	return Vector2(clampf(p.x, -margin, maxf(-margin, size.x - view_sz.x + margin)),
		clampf(p.y, -margin, maxf(-margin, size.y - view_sz.y + margin)))

func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if not _modal_open():
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A): move.x -= 1
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): move.x += 1
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W): move.y -= 1
		if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) and not Input.is_key_pressed(KEY_CTRL): move.y += 1
		if DisplayServer.window_is_focused() and not Shot.active and not _dragging:
			move += _edge_scroll()
	_poll_drag()
	if move != Vector2.ZERO:
		_cam_target = _clamp_cam(_cam_target + move.normalized() * 900.0 * delta / cam.zoom.x)
	var hn: Node2D = view.hero_node(_follow) if _follow >= 0 else null
	if hn:
		# glide with the figure as it walks: a target that moves smoothly, not one step a tile
		center_on_world(hn.position - Vector2(0, TILE * 0.5 - 6))
		cam.position = cam.position.lerp(_cam_target, minf(1.0, delta * 6.0))
	else:
		cam.position = cam.position.lerp(_cam_target, minf(1.0, delta * 10.0))
	var mpos := get_viewport().get_mouse_position()
	if _modal_open():
		if _info_tile != Vector2i(-3, -3):  # a window is up: the status line and tile highlight would show under it
			_info_tile = Vector2i(-3, -3)
			HoverInfo.hide_for(self)
			hud.set_status("")
			view.set_hover(Vector2i(-1, -1))
	elif _info_tile != Vector2i(-2, -2) and (busy or mpos.x > MAP_VIEW_W or mpos.y > MAP_VIEW_H or mpos.x < 0 or mpos.y < 0):
		_info_tile = Vector2i(-2, -2)
		HoverInfo.hide_for(self)
	hud.update_minimap_view(cam.position, Vector2(MAP_VIEW_W, MAP_VIEW_H) / cam.zoom)

## Edge scrolling, measured on the screen: the cursor at a window edge, or anywhere past it, scrolls that way
## (while the window has the focus).
func _edge_scroll() -> Vector2:
	var m := DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
	var ws := Vector2(DisplayServer.window_get_size())
	var v := Vector2.ZERO
	if m.x < EDGE: v.x -= 1
	if m.x > ws.x - EDGE: v.x += 1
	if m.y < EDGE: v.y -= 1
	if m.y > ws.y - EDGE: v.y += 1
	return v

## Map dragging: mouse motion over the map pans it (_unhandled_input); when the cursor goes over the side panel,
## the bottom bar or out of the window those events stop reaching the map, so the cursor's place on the screen
## keeps panning it until the button is let go anywhere.
func _poll_drag() -> void:
	if _drag_button == MOUSE_BUTTON_NONE:
		return
	if not Input.is_mouse_button_pressed(_drag_button):  # (released where the map never heard of it)
		_drag_button = MOUSE_BUTTON_NONE
		_left_down = false
		_dragging = false
		return
	var now := DisplayServer.mouse_get_position()
	if _drag_synced:
		_drag_synced = false
		_drag_screen = now
		return
	var ws := Vector2(DisplayServer.window_get_size())
	var vs := get_viewport().get_visible_rect().size
	var scale := minf(ws.x / vs.x, ws.y / vs.y)  # screen pixels per viewport pixel
	if scale <= 0.0:  # (no real window: headless runs)
		return
	if not _dragging:
		if Vector2(now - _press_screen).length() / scale <= DRAG_START:
			return
		_dragging = true
		HoverInfo.hide_for(self)
	var d := Vector2(now - _drag_screen) / scale
	_drag_screen = now
	if d != Vector2.ZERO:
		_cam_target = _clamp_cam(_cam_target - d / cam.zoom)
		cam.position = _cam_target

func _start_press(button: MouseButton) -> void:
	_drag_button = button
	_drag_screen = DisplayServer.mouse_get_position()
	_press_screen = _drag_screen

func _modal_open() -> bool:
	var l := get_tree().root.get_node_or_null("ModalLayer")
	return l != null and l.get_child_count() > 0

# ---------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------
func _unhandled_input(e: InputEvent) -> void:
	if _modal_open():
		return
	if e is InputEventMouseMotion:
		# left-drag (or middle-drag) pans the map; a left press that doesn't move is a click
		if _left_down and not _dragging and e.position.distance_to(_drag_from) > DRAG_START:
			_dragging = true
			HoverInfo.hide_for(self)
		if _dragging:
			_cam_target = _clamp_cam(_cam_target - e.relative / cam.zoom)
			cam.position = _cam_target
			_drag_synced = true
			return
		if e.position.x < 0 or e.position.y < 0:  # (a cursor off the window reads nothing)
			view.set_hover(Vector2i(-1, -1))
			hud.set_status("")
			HoverInfo.hide_for(self)
			_info_tile = Vector2i(-2, -2)
			return
		var t := _pick(view.tile_at(_event_world(e)), _event_world(e))
		view.set_hover(t if rules.inside(t) else Vector2i(-1, -1))
		hud.set_status(_describe_tile(t))
		if t != _info_tile and not busy:
			_info_tile = t
			# (inside the map view: not over the side panel)
			HoverInfo.show_for(self, _tile_info(t), 0.3, 1, -1.0, Rect2(), Rect2(0, 0, AdventureHUD.PANEL_X - 6, 1036))
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				_start_press(MOUSE_BUTTON_MIDDLE)
				_dragging = true
			else:
				_dragging = false
				_drag_button = MOUSE_BUTTON_NONE
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.1)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 1.1)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_left_down = true
				_drag_from = e.position
				_start_press(MOUSE_BUTTON_LEFT)
				_left_tile = _pick(view.tile_at(_event_world(e)), _event_world(e))
			elif _left_down:
				_left_down = false
				var was_drag := _dragging
				_dragging = false
				_drag_button = MOUSE_BUTTON_NONE
				_info_tile = Vector2i(-2, -2)
				if not was_drag:
					if busy:
						_pending_click = _left_tile
					else:
						_click(_left_tile, false)
		elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_right_click(_pick(view.tile_at(_event_world(e)), _event_world(e)))
	elif e is InputEventKey and e.pressed and not e.echo:
		if busy:
			return
		match e.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if not _plan.is_empty():
					_execute_move()
			KEY_E:
				end_turn()
			KEY_H, KEY_TAB:
				next_hero()
			KEY_K:
				hud.open_kingdom()
			KEY_I:
				if not selected_hero().is_empty():
					hud.open_hero_screen(selected_hero())
			KEY_Z:
				toggle_sleep()
			KEY_M:
				continue_move()
			KEY_C:
				if not selected_hero().is_empty():
					SpellBook.open(self, selected_hero())
			KEY_T:
				var p := human_player()
				if p["towns"].size() > 0:
					open_town(p["towns"][0])
			KEY_ESCAPE:
				hud.open_system_menu()
			KEY_S:
				if e.ctrl_pressed:
					GameState.save_game()
					hud.toast("Game saved")

## Creature, hero and treasure sprites stand above their tile: a point on a sprite means that unit (front-most
## first), otherwise the tile itself, or the unit below when the tile is empty.
func _pick(t: Vector2i, world_p = null) -> Vector2i:
	if world_p != null:
		var s := view.sprite_tile_at(world_p)
		if s != Vector2i(-1, -1):
			return s
	if not rules.inside(t) or not rules.at(t).is_empty() or not rules.town_covering(t).is_empty() or not rules.object_covering(t).is_empty():
		return t
	var below := t + Vector2i(0, 1)
	if rules.inside(below):
		var o := rules.at(below)
		if o.get("kind", "") == "hero" or (o.get("kind", "") == "object" and world["objects"][o["uid"]]["type"] == "monster"):
			return below
	return t

func _event_world(e: InputEventMouse) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * e.position

func _zoom(f: float) -> void:
	var center := cam.position + Vector2(MAP_VIEW_W, MAP_VIEW_H) * 0.5 / cam.zoom
	cam.zoom = (cam.zoom * f).clamp(Vector2(0.55, 0.55), Vector2(1.4, 1.4))
	GameState.map_zoom = cam.zoom.x
	_cam_target = _clamp_cam(center - Vector2(MAP_VIEW_W, MAP_VIEW_H) * 0.5 / cam.zoom)
	cam.position = _cam_target

func _click(t: Vector2i, _dbl: bool) -> void:
	if not rules.inside(t):
		return
	var me := _human()
	if not rules.is_explored(human_player(), t):
		return
	var hh := rules.hero_at(t)
	if not hh.is_empty() and hh["owner"] == me:
		if hh["uid"] == world["selected_hero"]:
			hud.open_hero_screen(hh)
		else:
			_select_hero(hh["uid"])
		return
	var town := rules.town_covering(t)
	var hero := selected_hero()
	if not town.is_empty() and town["owner"] == me and t != town["pos"]:
		open_town(town["uid"])
		return
	if hero.is_empty():
		if not town.is_empty() and town["owner"] == me:
			open_town(town["uid"])
		return
	if t == _plan_target and not _plan.is_empty():
		_execute_move()
		return
	_make_plan(t)

func _make_plan(t: Vector2i) -> void:
	var hero := selected_hero()
	if hero.is_empty():
		return
	var p := rules.plan(hero, t)
	if p["path"].is_empty():
		_plan = {}
		_plan_target = Vector2i(-1, -1)
		view.clear_path()
		return
	_plan = p
	_plan_target = t
	view.set_path(p["path"], p["reach"], p["kind"])
	hero["dest"] = t

func _right_click(t: Vector2i) -> void:
	if not rules.inside(t) or not rules.is_explored(human_player(), t):
		return
	var o := rules.object_covering(t)
	if not o.is_empty():
		if o["type"] == "monster":
			var c: Dictionary = GameData.CREATURES[o["creature"]]
			hud.toast("%s %s" % [UI.count_word(o["count"]), c["plural"]])
		else:
			hud.toast(_describe_tile(t))
		return
	var hh := rules.hero_at(t)
	if not hh.is_empty():
		hud.toast("%s (Level %d %s), %s" % [hh["name"], hh["level"], hh["class"], world["players"][hh["owner"]]["name"]])

## Hover panel for a map tile: what the hero, town or object there is and what visiting it does (null: nothing).
func _tile_info(t: Vector2i):
	if not rules.inside(t) or not rules.is_explored(human_player(), t):
		return null
	var hh := rules.hero_at(t)
	if not hh.is_empty():
		var v := HoverInfo.box(hh["name"])
		HoverInfo.line(v, "Level %d %s" % [hh["level"], hh["class"]])
		HoverInfo.line(v, world["players"][hh["owner"]]["name"], Color(0.8, 0.75, 0.65))
		return v
	var town := rules.town_covering(t)
	if not town.is_empty():
		var v := HoverInfo.box(town["name"])
		HoverInfo.line(v, "%s town" % GameData.FACTIONS[town["faction"]]["name"])
		HoverInfo.line(v, "Neutral" if town["owner"] < 0 else world["players"][town["owner"]]["name"], Color(0.8, 0.75, 0.65))
		return v
	var o := rules.object_covering(t)
	var me: int = human_player()["index"]
	var hero := selected_hero()
	if o.is_empty():
		if rules.is_guarded(t):
			return "Guarded: stepping here means a fight with the monsters next to it."
		return null
	match o["type"]:
		"monster":
			var v := HoverInfo.creature(o["creature"], -1, "%s %s" % [UI.count_word(o["count"]), GameData.CREATURES[o["creature"]]["plural"]])
			HoverInfo.line(v, "Click to attack.", Color(1, 0.6, 0.5), 18)
			return v
		"resource":
			var v := HoverInfo.box(GameData.RESOURCE_NAMES[o["res"]])
			HoverInfo.line(v, "A pile of %s. Walk over it to pick it up." % GameData.RESOURCE_NAMES[o["res"]].to_lower())
			return v
		"campfire":
			var v := HoverInfo.box("Campfire")
			HoverInfo.line(v, "Abandoned supplies: gold and %s." % GameData.RESOURCE_NAMES[o["res"]].to_lower())
			return v
		"chest":
			var v := HoverInfo.box("Treasure Chest")
			HoverInfo.line(v, "Keep the gold, or give it away for experience.")
			return v
		"artifact":  # (named, with its tier and effect, as the classic's right-click)
			var d: Dictionary = GameData.ARTIFACTS[o["artifact"]]
			var v := HoverInfo.box(d["name"])
			var tr: Array = GameData.ARTIFACT_TIERS[d["tier"]]
			HoverInfo.line(v, "%s artifact" % tr[0], tr[1])
			HoverInfo.line(v, d["desc"])
			if d.has("set"):
				HoverInfo.line(v, "Part of the %s" % GameData.ARTIFACTS[d["set"]]["name"], Color(0.8, 0.65, 1.0))
			return v
		"mine":
			var m: Dictionary = GameData.MINES[o["mine"]]
			var v := HoverInfo.box(m["name"])
			var row := HBoxContainer.new()
			row.add_child(UI.icon(Assets.res_icon(m["resource"]), Vector2(26, 26)))
			row.add_child(UI.label(" +%d %s per day" % [m["amount"], GameData.RESOURCE_NAMES[m["resource"]].to_lower()], 19))
			v.add_child(row)
			HoverInfo.line(v, "Unclaimed: visit to claim it." if o["owner"] < 0 else "Owned by %s." % world["players"][o["owner"]]["name"],
				Color(0.8, 0.75, 0.65))
			return v
		"dwelling":
			var c: Dictionary = GameData.CREATURES[o["creature"]]
			var v := HoverInfo.creature(o["creature"], -1, "%s dwelling" % c["name"])
			HoverInfo.line(v, "%d available to recruit." % o["available"], UI.GOLD, 18)
			var own: int = o.get("owner", -1)
			_visit_line(v, own == me, "Yours: new recruits every week." if own == me else
				("Not visited." if own < 0 else "Owned by %s." % world["players"][own]["name"]))
			return v
		"shrine":
			var sp: Dictionary = GameData.SPELLS[o["spell"]]
			var v := HoverInfo.box("Shrine of Magic")
			HoverInfo.line(v, "Teaches %s (level %d): %s" % [sp["name"], sp["level"], sp["desc"]])
			if not hero.is_empty():
				if o["spell"] in hero["spells"]:
					_visit_line(v, true, "%s already knows it." % hero["name"])
				elif sp["level"] > rules.max_spell_level(hero):
					_visit_line(v, true, "%s needs more Wisdom to learn a level %d spell." % [hero["name"], sp["level"]])
				else:
					_visit_line(v, false, "%s can learn it." % hero["name"])
			return v
		"learning_stone":
			var v := HoverInfo.box("Learning Stone")
			HoverInfo.line(v, "+1000 experience, once per hero.")
			if not hero.is_empty():
				var seen: bool = hero["uid"] in o.get("visited", [])
				_visit_line(v, seen, "%s: %s" % [hero["name"], "already visited." if seen else "not visited yet."])
			return v
		"windmill":
			var v := HoverInfo.box("Windmill")
			HoverInfo.line(v, "The miller shares resources once a week.")
			if me in o.get("visited_week", []):
				var left: int = 7 - (int(world["day"]) - 1) % 7
				_visit_line(v, true, "Visited this week. More in %d day%s." % [left, "" if left == 1 else "s"])
			else:
				_visit_line(v, false, "Not visited this week.")
			return v
		"watchtower":
			var v := HoverInfo.box("Watchtower")
			HoverInfo.line(v, "Reveals the land around it.")
			var seen: bool = me in o.get("visited_by", [])
			_visit_line(v, seen, "Visited." if seen else "Not visited.")
			return v
	return _describe_tile(t)

## "Visited" status line on a map site's hover panel: grey once used up, green while there is something to get.
func _visit_line(v: VBoxContainer, done: bool, text: String) -> void:
	HoverInfo.line(v, text, Color(0.62, 0.6, 0.56) if done else Color(0.55, 0.95, 0.5), 18)

func _describe_tile(t: Vector2i) -> String:
	if not rules.inside(t):
		return ""
	if not rules.is_explored(human_player(), t):
		return "Uncharted territory"
	var hh := rules.hero_at(t)
	if not hh.is_empty():
		return "%s — %s" % [hh["name"], world["players"][hh["owner"]]["name"]]
	var town := rules.town_covering(t)
	if not town.is_empty():
		var owner: String = "Neutral" if town["owner"] < 0 else world["players"][town["owner"]]["name"]
		return "%s (%s) — %s" % [town["name"], GameData.FACTIONS[town["faction"]]["name"], owner]
	var o := rules.object_covering(t)
	if not o.is_empty():
		match o["type"]:
			"monster":
				return "%s %s" % [UI.count_word(o["count"]), GameData.CREATURES[o["creature"]]["plural"]]
			"resource":
				return GameData.RESOURCE_NAMES[o["res"]]
			"mine":
				var owner: String = "unclaimed" if o["owner"] < 0 else world["players"][o["owner"]]["name"]
				return "%s (%s)" % [GameData.MINES[o["mine"]]["name"], owner]
			"dwelling":
				return "%s dwelling (%d available)" % [GameData.CREATURES[o["creature"]]["name"], o["available"]]
			"shrine":
				return "Shrine of Magic (%s)" % GameData.SPELLS[o["spell"]]["name"]
			"learning_stone":
				var sel := selected_hero()
				return "Learning Stone" + ("" if sel.is_empty() else (" (visited)" if sel["uid"] in o.get("visited", []) else " (not visited)"))
			"windmill":
				return "Windmill (%s)" % ("visited this week" if human_player()["index"] in o.get("visited_week", []) else "not visited this week")
			"watchtower":
				return "Watchtower (%s)" % ("visited" if human_player()["index"] in o.get("visited_by", []) else "not visited")
			_:
				return o["type"].capitalize()
	if rules.is_guarded(t):
		return "Guarded by monsters"
	var tn: String = WorldGen.TERRAIN_ORDER[rules.terrain_at(t)]
	return GameData.TERRAINS[tn]["name"]

# ---------------------------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------------------------
func _select_hero(uid: int, instant := false) -> void:
	world["selected_hero"] = uid
	view.set_selected(uid)
	_plan = {}
	_plan_target = Vector2i(-1, -1)
	view.clear_path()
	var hero := selected_hero()
	if not hero.is_empty():
		center_on(hero["pos"], instant)
		if hero.has("dest") and hero["dest"] != hero["pos"]:
			_make_plan(hero["dest"])
	elif human_player()["towns"].size() > 0:
		center_on(world["towns"][human_player()["towns"][0]]["pos"], instant)
	hud.refresh()

func select_hero(uid: int) -> void:
	if not busy:
		_select_hero(uid)

func _first_hero_with_mp() -> int:
	var p := human_player()
	for hid in p["heroes"]:
		if world["heroes"][hid]["movement"] > 0 and not world["heroes"][hid].get("asleep", false):
			return hid
	return p["heroes"][0] if p["heroes"].size() > 0 else -1

func next_hero() -> void:
	var p := human_player()
	if p["heroes"].is_empty():
		return
	var i: int = p["heroes"].find(world["selected_hero"])
	for k in p["heroes"].size():
		var hid: int = p["heroes"][(i + 1 + k) % p["heroes"].size()]
		var h: Dictionary = world["heroes"][hid]
		if (h["movement"] > 0 and not h.get("asleep", false)) or k == p["heroes"].size() - 1:
			_select_hero(hid)
			return

## Sleep / wake the selected hero: Next Hero passes over sleeping heroes (they wake when moved).
func toggle_sleep() -> void:
	var h := selected_hero()
	if h.is_empty():
		return
	h["asleep"] = not h.get("asleep", false)
	hud.toast("%s %s" % [h["name"], "sleeps" if h["asleep"] else "wakes"])
	hud.refresh()

## Walks the selected hero on along the route already shown (or toward the destination it was heading for).
func continue_move() -> void:
	var h := selected_hero()
	if busy or h.is_empty():
		return
	if _plan.is_empty() and h.has("dest") and h["dest"] != h["pos"]:
		_make_plan(h["dest"])
	if _plan.is_empty():
		hud.toast("No route planned: click a destination first")
		return
	_execute_move()

# ---------------------------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------------------------
func _execute_move() -> void:
	var hero := selected_hero()
	if hero.is_empty() or _plan.is_empty():
		return
	if _plan["reach"] == 0:
		Audio.sfx("error")
		hud.toast("Not enough movement points left today")
		return
	busy = true
	hero["asleep"] = false
	view.clear_path()
	_follow = hero["uid"]
	await move_hero(hero, _plan, true)
	_follow = -1
	busy = false
	if not is_inside_tree():
		return
	if world["heroes"].has(hero["uid"]):
		if hero.has("dest") and hero["dest"] != hero["pos"] and not _plan.is_empty():
			_make_plan(hero["dest"])
		else:
			_plan = {}
			_plan_target = Vector2i(-1, -1)
			view.clear_path()
		if _pending_click != Vector2i(-1, -1) and not _modal_open():
			_make_plan(_pending_click)  # only show the path: walking needs a second click as always
	_pending_click = Vector2i(-1, -1)
	hud.refresh()

## Moves a hero along plan up to its reach, performing the final interaction.
## Returns "battle" if a scene change to battle happened, else "".
func move_hero(hero: Dictionary, plan: Dictionary, animate: bool) -> String:
	var path: Array = plan["path"]
	var costs: Array = plan["costs"]
	var reach: int = plan["reach"]
	var player := rules.player_of(hero)
	var human: bool = not player["is_ai"]
	var visible_move := animate or _visible_to_human(hero["pos"])
	for i in range(1, reach + 1):
		var p: Vector2i = path[i]
		var last := i == path.size() - 1
		var occ := rules.at(p)
		if occ.get("kind", "") == "hero" or (occ.get("kind", "") == "object" and world["objects"][occ["uid"]]["type"] == "monster"):
			# The pseudo-step onto an enemy/ally.
			hero.erase("dest")
			return await _interact_with(hero, occ, human)
		hero["movement"] = maxi(0, hero["movement"] - (costs[i] - costs[i - 1]))
		var prev: Vector2i = hero["pos"]
		_move_hero_tile(hero, p)
		if p.x != prev.x:
			hero["face_left"] = p.x < prev.x
		if visible_move or _visible_to_human(p):
			view.move_hero_step(hero["uid"], p, 0.14 if human else 0.09)
			if human or _visible_to_human(p):
				Audio.sfx("footstep_horse", -12, 0.12)
				if human and _follow != hero["uid"]:
					center_on(p)
			await get_tree().create_timer(0.14 if human else 0.09).timeout
			if not is_inside_tree():
				return ""
		else:
			var n := view.hero_node(hero["uid"])
			if n:
				n.position = view.foot_of(p)
		rules.reveal(player, p, rules.hero_scout_radius(hero))
		if human:
			_refresh_fog()
		var gs := rules.guards(p)
		if gs.size() > 0:
			hero.erase("dest")
			var tgt: Dictionary = plan["target"] if plan["target"] in gs else gs[0]
			return await _interact_with(hero, {"kind": "object", "uid": tgt["uid"]}, human)
		if last:
			hero.erase("dest")
			if occ.get("kind", "") != "":
				return await _interact_with(hero, occ, human)
	return ""

func _move_hero_tile(hero: Dictionary, p: Vector2i) -> void:
	var old: Vector2i = hero["pos"]
	hero["pos"] = p
	rules.refresh_tile(old)
	rules.refresh_tile(p)

func _visible_to_human(p: Vector2i) -> bool:
	return rules.is_explored(human_player(), p)

func _interact_with(hero: Dictionary, occ: Dictionary, human: bool) -> String:
	match occ.get("kind", ""):
		"object":
			var o: Dictionary = world["objects"][occ["uid"]]
			if o["type"] == "monster":
				return await _start_battle(rules.battle_vs_monster(hero, o), human)
			var ev := rules.visit(hero, o)
			await _show_event(hero, ev, human)
		"town":
			var town: Dictionary = world["towns"][occ["uid"]]
			if town["owner"] == hero["owner"]:
				var learned := rules.hero_in_town(hero, town)
				if human:
					if learned.size() > 0:
						hud.toast("Learned: " + ", ".join(learned.map(func(s): return GameData.SPELLS[s]["name"])))
					open_town(town["uid"])
				return ""
			if GameState.army_is_empty(town["garrison"]) and rules.town_defender(town, hero).is_empty():
				rules.capture_town(town, hero["owner"])
				Audio.sfx("flag_capture")
				view.rebuild_objects()
				rules.check_eliminations()
				if human:
					await Modal.message(self, town["name"], "The town of %s opens its gates to you." % town["name"]).closed
				await _check_game_over()
				return ""
			var with_human := human
			if town["owner"] >= 0 and not world["players"][town["owner"]]["is_ai"]:
				with_human = true
			return await _start_battle(rules.battle_vs_town(hero, town), with_human)
		"hero":
			var other: Dictionary = world["heroes"][occ["uid"]]
			if other["owner"] == hero["owner"]:
				if human:
					hud.open_exchange(hero, other)
				return ""
			var involves_human: bool = human or not rules.player_of(other)["is_ai"]
			for t in world["towns"].values():
				if t["pos"] == other["pos"] and t["owner"] != hero["owner"]:
					return await _start_battle(rules.battle_vs_town(hero, t), involves_human)
			return await _start_battle(rules.battle_vs_hero(hero, other), involves_human)
	return ""

func _start_battle(setup: Dictionary, involves_human: bool) -> String:
	if involves_human:
		Audio.sfx("battle_start")
		GameState.return_scene = GameState.SCENE_ADVENTURE
		world["selected_hero"] = world.get("selected_hero", -1)
		GameState.start_battle(setup)
		busy = true
		return "battle"
	var result := rules.quick_resolve(setup)
	if Engine.time_scale > 1.0:  # soak-test diagnostics (tools/sim_test.gd)
		print("SIMBATTLE day %d %s P%d str %d vs %d -> %s" % [world["day"], setup["context"]["type"], setup["attacker_player"],
			GameState.army_strength(setup["attacker_army"]), GameState.army_strength(setup["defender_army"]), result["winner"]])
	var ev := rules.apply_battle(result)
	if ev["hero"] >= 0 and world["heroes"].has(ev["hero"]):
		await _handle_level_ups(world["heroes"][ev["hero"]])
	view.rebuild_objects()
	return ""

func _show_event(hero: Dictionary, ev: Dictionary, human: bool) -> void:
	if ev.get("sfx", "") != "" and (human or _visible_to_human(hero["pos"])):
		Audio.sfx(ev["sfx"])
	for uid in world.get("_removed", []):
		view.remove_object(uid)
	world["_removed"] = []
	if ev.has("refresh"):
		view.refresh_object(ev["refresh"])
	if ev.get("fog", false) and human:
		_refresh_fog()
	if ev.has("choice"):
		var c: Dictionary = ev["choice"]
		if human:
			var r = await Modal.choice(self, ev["title"], ev["text"], [
				["%d Gold" % c["gold"], "gold", Assets.res_icon("gold")],
				["%d Experience" % c["xp"], "xp", Assets.tex("icons/stat_xp.png")]]).closed
			var lv := rules.resolve_chest(hero, str(r), c["gold"], c["xp"])
			if lv > 0:
				await _handle_level_ups(hero)
		else:
			var lv := rules.resolve_chest(hero, "gold" if rules.player_of(hero)["resources"]["gold"] < 10000 else "xp", c["gold"], c["xp"])
			if lv > 0:
				await _handle_level_ups(hero)
	elif ev.has("dwelling"):
		if human:
			await hud.open_dwelling(hero, world["objects"][ev["dwelling"]])
		else:
			ai.recruit_from_dwelling(hero, world["objects"][ev["dwelling"]])
	elif human and ev["title"] != "":
		if ev.has("float"):
			hud.float_text(view.foot_of(hero["pos"]) - Vector2(0, 120), ev["float"])
		else:
			await Modal.message(self, ev["title"], ev["text"], ev["icons"]).closed
	if ev.get("levels", 0) > 0:
		await _handle_level_ups(hero)
	hud.refresh()

func _handle_level_ups(hero: Dictionary) -> void:
	var human: bool = not rules.player_of(hero)["is_ai"]
	while int(hero.get("pending_levels", 0)) > 0:
		var roll := rules.roll_level_up(hero)
		var skill := ""
		if human:
			Audio.sfx("level_up")
			var opts := []
			for s in roll["options"]:
				var lvl := int(hero["skills"].get(s, 0)) + 1
				opts.append(["%s %s" % [["", "Basic", "Advanced", "Expert"][lvl], GameData.SKILLS[s]["name"]], s, Assets.skill_icon(s)])
			var text := "%s has gained a level! (%s +1)\n%s" % [hero["name"], roll["stat"].capitalize(), "Choose a skill to learn:" if opts.size() > 0 else ""]
			if opts.size() > 0:
				skill = await Modal.choice(self, "Level %d" % (hero["level"] - int(hero["pending_levels"]) + 1), text, opts).closed
			else:
				await Modal.message(self, "Level up", text).closed
		elif roll["options"].size() > 0:
			skill = roll["options"][randi() % roll["options"].size()]
		rules.apply_level_up(hero, roll, skill)
	hud.refresh()

# ---------------------------------------------------------------------------------------------
# Towns
# ---------------------------------------------------------------------------------------------
func open_town(uid: int) -> void:
	var town: Dictionary = world["towns"][uid]
	var visitor := rules.hero_at(town["pos"])
	if not visitor.is_empty() and visitor["owner"] == town["owner"]:
		rules.hero_in_town(visitor, town)
	GameState.pending_town = {"town_uid": uid, "hero_uid": visitor.get("uid", -1)}
	GameState.change_scene(GameState.SCENE_TOWN)

# ---------------------------------------------------------------------------------------------
# Turns
# ---------------------------------------------------------------------------------------------
func end_turn() -> void:
	if busy:
		return
	var p := human_player()
	var idle := 0
	for hid in p["heroes"]:
		if world["heroes"][hid]["movement"] >= 300:
			idle += 1
	if idle > 0:
		var ok = await Modal.confirm(self, "End Turn", "One or more heroes can still move. End your turn anyway?").closed
		if not ok:
			return
	_advance_player()
	_run_ai_turns()

func _advance_player() -> void:
	var n: int = world["players"].size()
	var cur: int = world["current_player"]
	for k in n:
		cur = (cur + 1) % n
		if cur == 0:
			var info := rules.new_day()
			world["pending_week"] = info
		if world["players"][cur]["alive"]:
			break
	world["current_player"] = cur

func _run_ai_turns() -> void:
	busy = true
	hud.refresh()
	while world["players"][world["current_player"]]["is_ai"] and not world.get("game_over", false):
		var p: Dictionary = world["players"][world["current_player"]]
		hud.set_turn_label("%s is moving..." % p["name"])
		var r := await ai.run_turn(self, p)
		if r == "battle" or not is_inside_tree():
			return  # battle scene takes over; we resume in _post_ready
		if await _check_game_over():
			return
		_advance_player()
		# (one frame per turn: with nothing to animate, e.g. a lone computer player left in an all-computer game, the
		# days would otherwise spin within one frame and overflow the engine's message queue)
		await get_tree().process_frame
		if not is_inside_tree():
			return
	busy = false
	hud.set_turn_label("")
	await _start_human_turn()

func _start_human_turn() -> void:
	_refresh_fog()
	view.rebuild_objects()
	_select_hero(_first_hero_with_mp())
	hud.refresh()
	if await _check_game_over():
		return
	await _turn_banner()

func _turn_banner() -> void:
	var info: Dictionary = world.get("pending_week", {})
	world["pending_week"] = {}
	Audio.sfx("new_day", -4)
	hud.flash_date()
	if info.get("new_week", false):
		Audio.sfx("new_week")
		var cid: String = info.get("week_creature", "")
		var text := "Astrologers proclaim the Week of the %s.\nAll dwellings increase their population." % (GameData.CREATURES[cid]["name"] if cid != "" else "Peasant")
		await Modal.message(self, "A New Week", text, [[Assets.creature_portrait(cid), GameData.CREATURES[cid]["plural"]]] if cid != "" else []).closed
	else:
		hud.banner("Day %d" % world["day"])
		hud.toast(rules.date_string())

func _check_game_over() -> bool:
	if world.get("game_over", false):
		return true
	var me := human_player()
	var others_alive := false
	for p in world["players"]:
		if p["is_ai"] and p["alive"]:
			others_alive = true
	# the scenario's own conditions (a capture, a hoard of gold, the starting hero, a deadline)
	var sc: Dictionary = world.get("scenario", {})
	var vic: Dictionary = sc.get("victory", {})
	var loss: Dictionary = sc.get("loss", {})
	var lost := ""
	if not me["alive"]:
		lost = "Your last hero has fallen and your towns are lost. The Shattered Crown will never be whole again."
	elif loss.get("type", "") == "hero" and not world["heroes"].has(world.get("start_hero", -1)):
		lost = "Your champion has fallen, and with them the last hope of the old order."
	elif loss.get("type", "") == "days" and world["day"] > int(loss.get("days", 112)):
		lost = "The snows have melted and your enemies' hosts have joined together. Time has run out."
	if lost != "":
		world["game_over"] = true
		Audio.music("defeat")
		await Modal.message(self, "Defeat", lost).closed
		GameState.world = {}
		GameState.change_scene(GameState.SCENE_MENU)
		return true
	var won := ""
	if not others_alive:
		won = "All your enemies have been vanquished. The lands bow before you, and the Shattered Crown is yours."
	elif vic.get("type", "") == "capture":
		for t in world["towns"].values():
			if t["owner"] == me["index"] and t.get("start_owner", -1) > 0:
				won = "%s is yours. With the enemy's stronghold taken, the border is secure." % t["name"]
	elif vic.get("type", "") == "gold" and me["resources"]["gold"] >= int(vic.get("amount", 0)):
		won = "Your treasury overflows with the gold of the old kings. The realm's lords flock to your banner."
	if won != "":
		world["game_over"] = true
		Audio.music("victory")
		await Modal.message(self, "Victory!", won).closed
		GameState.world = {}
		GameState.change_scene(GameState.SCENE_MENU)
		return true
	return false

# ---------------------------------------------------------------------------------------------
func _refresh_fog() -> void:
	view.update_fog(human_player())
	hud.refresh_minimap()

func refresh_after_change() -> void:
	rules.rebuild()
	view.rebuild_objects()
	view.set_selected(world.get("selected_hero", -1))
	hud.refresh()

func _update_music() -> void:
	var hero := selected_hero()
	var t := "grass"
	if not hero.is_empty():
		t = WorldGen.TERRAIN_ORDER[rules.terrain_at(hero["pos"])]
	Audio.music("adventure_dirt" if t in ["dirt", "swamp", "snow"] else "adventure_grass")
