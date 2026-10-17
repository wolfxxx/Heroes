extends RefCounted
class_name WorldGen
## Random map generator. generate(settings) -> world dict (schema in ARCHITECTURE.md / adventure.gd).
##
## Tiles are 64px. Objects have an action tile "pos" (where the hero stands to visit) and an optional
## footprint of blocked offsets. Sprites are anchored at the bottom-centre of the action tile.

const TILE := 64
const TERRAIN_ORDER := ["grass", "dirt", "sand", "snow", "swamp", "water", "road"]
const T_GRASS := 0
const T_DIRT := 1
const T_SAND := 2
const T_SNOW := 3
const T_SWAMP := 4
const T_WATER := 5
const T_ROAD := 6

const FOOT_BUILDING := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0)]
const FOOT_SMALL := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0)]

static func town_footprint() -> Array:
	var out := []
	for y in range(-2, 1):
		for x in range(-2, 3):
			if not (x == 0 and y == 0):
				out.append(Vector2i(x, y))
	return out

static func footprint_for(type: String) -> Array:
	match type:
		"mine", "dwelling", "shrine", "windmill", "watchtower", "learning_stone":
			return FOOT_BUILDING
	return []

# ---------------------------------------------------------------------------------------------
static func generate(settings: Dictionary) -> Dictionary:
	var g := WorldGen.new()
	return g._generate(settings)

var rng := RandomNumberGenerator.new()
var w := 0
var h := 0
var terrain := PackedByteArray()
var blocked := PackedByteArray()   # 1 = obstacle/footprint, cannot be entered
var occupied := {}                 # Vector2i -> uid of object on its action tile
var keep_clear := PackedByteArray() # tiles that must stay free of obstacles (roads, town aprons)
var decor := []
var world := {}

func idx(p: Vector2i) -> int:
	return p.y * w + p.x

func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func _generate(settings: Dictionary) -> Dictionary:
	var seed_v: int = settings.get("seed", 0)
	if seed_v == 0:
		seed_v = randi()
	rng.seed = seed_v
	seed(seed_v)
	var n: int = settings.get("map_size", 48)
	w = n
	h = n
	terrain.resize(w * h)
	blocked.resize(w * h)
	keep_clear.resize(w * h)
	blocked.fill(0)
	keep_clear.fill(0)

	var human_faction: String = settings.get("faction", "haven")
	var opponents: int = clampi(int(settings.get("opponents", 1)), 1, 3)
	var nplayers := opponents + 1
	var difficulty: int = settings.get("difficulty", 1)

	world = {
		"seed": seed_v, "size": Vector2i(w, h), "day": 1, "current_player": 0,
		"players": [], "heroes": {}, "towns": {}, "objects": {},
		"terrain": terrain, "blocked": blocked, "decor": decor, "difficulty": difficulty,
		"tavern": [], "selected_hero": -1, "game_over": false,
	}

	# ---- players & start positions -------------------------------------------------------
	var starts := _start_positions(nplayers)
	var factions := []
	for i in nplayers:
		if i == 0:
			factions.append(human_faction)
		else:
			factions.append(GameData.FACTIONS.keys()[rng.randi() % GameData.FACTIONS.size()])

	# ---- terrain zones --------------------------------------------------------------------
	var zone_centers := []
	var zone_terrain := []
	for i in nplayers:
		zone_centers.append(Vector2(starts[i]))
		zone_terrain.append(TERRAIN_ORDER.find(GameData.FACTIONS[factions[i]]["terrain"]))
	var extra := 3 + n / 16
	var tries := 0
	while zone_centers.size() < nplayers + extra and tries < 500:
		tries += 1
		var c := Vector2(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
		var ok := true
		for z in zone_centers:
			if z.distance_to(c) < n * 0.22:
				ok = false
				break
		if ok:
			zone_centers.append(c)
			zone_terrain.append([T_GRASS, T_GRASS, T_DIRT, T_SAND, T_SNOW, T_SWAMP][rng.randi() % 6])

	var warp := FastNoiseLite.new()
	warp.seed = rng.randi()
	warp.frequency = 0.06
	var lake := FastNoiseLite.new()
	lake.seed = rng.randi()
	lake.frequency = 0.07
	var obst := FastNoiseLite.new()
	obst.seed = rng.randi()
	obst.frequency = 0.11
	obst.fractal_octaves = 3
	var forest_kind := FastNoiseLite.new()
	forest_kind.seed = rng.randi()
	forest_kind.frequency = 0.05

	for y in h:
		for x in w:
			var p := Vector2(x, y) + Vector2(warp.get_noise_2d(x, y), warp.get_noise_2d(x + 500, y)) * 6.0
			var best := 0
			var bd := 1e9
			for i in zone_centers.size():
				var d: float = p.distance_squared_to(zone_centers[i])
				if d < bd:
					bd = d
					best = i
			terrain[y * w + x] = zone_terrain[best]

	# ---- water -------------------------------------------------------------------------
	for y in h:
		for x in w:
			var v := lake.get_noise_2d(x, y)
			var near_start := false
			for s in starts:
				if Vector2(s).distance_to(Vector2(x, y)) < 9:
					near_start = true
			if v > 0.42 and not near_start:
				terrain[y * w + x] = T_WATER

	# ---- towns ---------------------------------------------------------------------------
	var town_list := []
	for i in nplayers:
		var t := TownLogic.make_town(factions[i], i, starts[i], "", true)
		_place_town(t)
		town_list.append(t)
	# neutral towns
	var neutral_count := 1 + n / 32
	for k in neutral_count:
		var pos := _find_far_spot(town_list, n * 0.3)
		if pos == Vector2i(-1, -1):
			continue
		var f: String = GameData.FACTIONS.keys()[rng.randi() % GameData.FACTIONS.size()]
		var t := TownLogic.make_town(f, -1, pos, "", false)
		t["buildings"] = ["village_hall", "fort", "dwelling_1"]
		t["available"] = [0, 0, 0, 0, 0, 0, 0]
		TownLogic.weekly_growth(t)
		var c: Array = GameData.FACTIONS[f]["creatures"]
		t["garrison"][0] = {"id": c[0], "count": rng.randi_range(20, 35)}
		t["garrison"][1] = {"id": c[1], "count": rng.randi_range(8, 14)}
		t["garrison"][2] = {"id": c[2], "count": rng.randi_range(3, 6)}
		_place_town(t)
		town_list.append(t)

	# ---- roads between towns (nearest-neighbour chain + loop) ---------------------------
	var connected := [town_list[0]]
	var remaining := town_list.slice(1)
	while remaining.size() > 0:
		var bestpair := []
		var bestd := 1e9
		for a in connected:
			for b in remaining:
				var d := Vector2(a["pos"]).distance_to(Vector2(b["pos"]))
				if d < bestd:
					bestd = d
					bestpair = [a, b]
		_carve_road(bestpair[0]["pos"] + Vector2i(0, 1), bestpair[1]["pos"] + Vector2i(0, 1))
		connected.append(bestpair[1])
		remaining.erase(bestpair[1])
	if town_list.size() > 2:
		_carve_road(town_list[town_list.size() - 1]["pos"] + Vector2i(0, 1), town_list[0]["pos"] + Vector2i(0, 1))

	# ---- obstacles ---------------------------------------------------------------------
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			var i := idx(p)
			if keep_clear[i] or blocked[i] or terrain[i] == T_WATER:
				continue
			var edge: int = mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			var v := obst.get_noise_2d(x, y)
			var thresh := 0.18
			if edge < 2:
				thresh = -0.6
			elif edge < 4:
				thresh = -0.1
			if v > thresh:
				blocked[i] = 2  # 2 = natural obstacle (decor drawn later)

	# Mountains: replace some obstacle blobs with big mountain sprites.
	_place_mountains()
	_place_forests(forest_kind)

	# ---- objects ------------------------------------------------------------------------
	var reach := _reachable(town_list[0]["pos"] + Vector2i(0, 1))
	for i in nplayers:
		var tp: Vector2i = starts[i]
		_place_obj({"type": "mine", "mine": "sawmill", "owner": -1}, tp, 4, 9, reach)
		_place_obj({"type": "mine", "mine": "ore_mine", "owner": -1}, tp, 4, 9, reach)
		_place_obj({"type": "resource", "res": "wood", "amount": rng.randi_range(5, 10)}, tp, 3, 7, reach)
		_place_obj({"type": "resource", "res": "ore", "amount": rng.randi_range(5, 10)}, tp, 3, 7, reach)
		_place_obj({"type": "resource", "res": "gold", "amount": rng.randi_range(5, 10) * 100}, tp, 3, 8, reach)
		_place_obj({"type": "chest"}, tp, 4, 10, reach)
		_place_obj({"type": "campfire"}, tp, 4, 10, reach)
		_place_obj({"type": "windmill", "visited_week": []}, tp, 6, 12, reach)
		_place_obj({"type": "dwelling", "creature": GameData.faction_creature(factions[i], rng.randi_range(1, 3)), "available": 0}, tp, 7, 13, reach, true)
		_place_obj({"type": "monster"}, tp, 5, 9, reach)

	var rare_mines := ["gold_mine", "crystal_cavern", "gem_pond", "alchemist_lab", "sulfur_dune"]
	var area_scale := float(w * h) / (48.0 * 48.0)
	for k in int(round(5 * area_scale)):
		_place_obj({"type": "mine", "mine": rare_mines[k % rare_mines.size()], "owner": -1}, Vector2i(w / 2, h / 2), 0, n, reach, true, 10)
	for k in int(round(5 * area_scale)):
		_place_obj({"type": "mine", "mine": ["sawmill", "ore_mine"][k % 2], "owner": -1}, Vector2i(w / 2, h / 2), 0, n, reach, true, 9)
	for k in int(round(26 * area_scale)):
		var r: String = GameData.RESOURCES[rng.randi() % GameData.RESOURCES.size()]
		var amt: int = rng.randi_range(5, 10) * 100 if r == "gold" else (rng.randi_range(5, 10) if r in ["wood", "ore"] else rng.randi_range(3, 6))
		_place_obj({"type": "resource", "res": r, "amount": amt}, Vector2i(w / 2, h / 2), 0, n, reach, false, 6)
	for k in int(round(12 * area_scale)):
		_place_obj({"type": "chest"}, Vector2i(w / 2, h / 2), 0, n, reach, rng.randf() < 0.4, 7)
	for k in int(round(5 * area_scale)):
		_place_obj({"type": "campfire"}, Vector2i(w / 2, h / 2), 0, n, reach, false, 7)
	var arts := GameData.ARTIFACTS.keys()
	arts.shuffle()
	for k in mini(int(round(7 * area_scale)), arts.size()):
		_place_obj({"type": "artifact", "artifact": arts[k]}, Vector2i(w / 2, h / 2), 0, n, reach, true, 9)
	var spells := GameData.SPELLS.keys()
	for k in int(round(4 * area_scale)):
		_place_obj({"type": "shrine", "spell": spells[rng.randi() % spells.size()]}, Vector2i(w / 2, h / 2), 0, n, reach, false, 8)
	for k in int(round(3 * area_scale)):
		_place_obj({"type": "learning_stone", "visited": []}, Vector2i(w / 2, h / 2), 0, n, reach, false, 8)
	for k in int(round(2 * area_scale)):
		_place_obj({"type": "watchtower"}, Vector2i(w / 2, h / 2), 0, n, reach, false, 8)
	for k in int(round(4 * area_scale)):
		var f: String = GameData.FACTIONS.keys()[rng.randi() % GameData.FACTIONS.size()]
		_place_obj({"type": "dwelling", "creature": GameData.faction_creature(f, rng.randi_range(2, 5)), "available": 0}, Vector2i(w / 2, h / 2), 0, n, reach, true, 9)
	for k in int(round(22 * area_scale)):
		_place_obj({"type": "monster"}, Vector2i(w / 2, h / 2), 0, n, reach, false, 7)

	for o in world["objects"].values():
		if o["type"] == "dwelling":
			o["available"] = GameData.CREATURES[o["creature"]]["growth"]

	# ---- small non-blocking decorations ---------------------------------------------------
	var clump := FastNoiseLite.new()
	clump.seed = rng.randi()
	clump.frequency = 0.12
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			var i := idx(p)
			if blocked[i] or terrain[i] in [T_WATER, T_ROAD] or occupied.has(p) or keep_clear[i]:
				continue
			# denser in clumps (and next to woods), sparse in between
			var dens := 0.08 + 0.2 * clampf(clump.get_noise_2d(x, y) + 0.3, 0.0, 1.0) + (0.04 if _near_obstacle(p) else 0.0)
			if rng.randf() < dens:
				var k := _pick_weighted(DECOR_KINDS.get(terrain[i], DECOR_KINDS[T_GRASS]))
				var upright: bool = k in DECOR_UPRIGHT
				decor.append({"k": k, "p": Vector2((x + rng.randf_range(0.2, 0.8)) * TILE, (y + rng.randf_range(0.5, 0.95)) * TILE), "s": rng.randf_range(0.45, 0.7),
					"m": rng.randf_range(0.8, 1.05) if k.begins_with("decor_") else rng.randf_range(0.7, 1.0), "flip": rng.randf() < 0.5, "flat": not upright})

	# ---- players -------------------------------------------------------------------------
	var res_amounts: Array = [[30000, 30, 15], [20000, 20, 10], [15000, 15, 7]][clampi(difficulty, 0, 2)]
	var ai_amounts: Array = [[15000, 15, 7], [20000, 20, 10], [30000, 30, 15]][clampi(difficulty, 0, 2)]
	var used_heroes := []
	for i in nplayers:
		var amounts: Array = res_amounts if i == 0 else ai_amounts
		var resources := {}
		for r in GameData.RESOURCES:
			resources[r] = amounts[0] if r == "gold" else (amounts[1] if r in ["wood", "ore"] else amounts[2])
		var player := {
			"index": i, "name": "You" if i == 0 else "%s Lord" % GameData.PLAYER_COLOR_NAMES[i],
			"color": GameData.PLAYER_COLORS[i], "is_ai": i != 0, "faction": factions[i],
			"resources": resources, "heroes": [], "towns": [town_list[i]["uid"]], "alive": true,
			"explored": PackedByteArray(),
		}
		player["explored"].resize(w * h)
		player["explored"].fill(0)
		world["players"].append(player)
		var hid: String = settings.get("hero", "") if i == 0 else ""
		if hid == "" or GameData.HEROES.get(hid, {}).get("faction", "") != factions[i]:
			var cands := []
			for k in GameData.HEROES:
				if GameData.HEROES[k]["faction"] == factions[i] and not k in used_heroes:
					cands.append(k)
			hid = cands[rng.randi() % cands.size()]
		used_heroes.append(hid)
		var hero := GameState.make_hero(hid, i)
		hero["pos"] = town_list[i]["pos"]  # heroes start inside their town (at the gate), as in HoMM
		world["heroes"][hero["uid"]] = hero
		player["heroes"].append(hero["uid"])
	for t in town_list:
		world["towns"][t["uid"]] = t
	for k in GameData.HEROES:
		if not k in used_heroes:
			world["tavern"].append(k)
	world["selected_hero"] = world["players"][0]["heroes"][0]
	return world

# ---------------------------------------------------------------------------------------------
func _start_positions(np: int) -> Array:
	var m := 7
	var corners := [Vector2i(m, m + 1), Vector2i(w - 1 - m, h - 1 - m), Vector2i(w - 1 - m, m + 1), Vector2i(m, h - 1 - m)]
	if np == 3:
		corners = [Vector2i(m, m + 1), Vector2i(w - 1 - m, m + 1), Vector2i(w / 2, h - 1 - m)]
	var out := []
	for i in np:
		var c: Vector2i = corners[i]
		c += Vector2i(rng.randi_range(-2, 2), rng.randi_range(-1, 1))
		out.append(c)
	return out

func _find_far_spot(towns: Array, min_d: float) -> Vector2i:
	for attempt in 400:
		var p := Vector2i(rng.randi_range(6, w - 7), rng.randi_range(6, h - 6))
		var ok := true
		for t in towns:
			if Vector2(t["pos"]).distance_to(Vector2(p)) < min_d:
				ok = false
				break
		if ok:
			return p
	return Vector2i(-1, -1)

func _place_town(t: Dictionary) -> void:
	var pos: Vector2i = t["pos"]
	# Dry land around the town.
	for y in range(-4, 5):
		for x in range(-5, 6):
			var p := pos + Vector2i(x, y)
			if inside(p):
				if terrain[idx(p)] == T_WATER:
					terrain[idx(p)] = TERRAIN_ORDER.find(GameData.FACTIONS[t["faction"]]["terrain"])
				if abs(x) <= 4 and y >= -3 and y <= 3:
					keep_clear[idx(p)] = 1
	for off in town_footprint():
		var p: Vector2i = pos + off
		if inside(p):
			blocked[idx(p)] = 1
	occupied[pos] = t["uid"]

func _carve_road(a: Vector2i, b: Vector2i) -> void:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	# diagonals let roads run at an angle instead of in long stair steps; the noise cost makes them wander
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	var wander := FastNoiseLite.new()
	wander.seed = rng.randi()
	wander.frequency = 0.07
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			var i := idx(p)
			if blocked[i] == 1 and p != a and p != b:
				astar.set_point_solid(p, true)
			elif terrain[i] == T_WATER:
				astar.set_point_weight_scale(p, 12.0)
			elif terrain[i] == T_ROAD:
				astar.set_point_weight_scale(p, 0.3)
			else:
				astar.set_point_weight_scale(p, 2.2 + 2.0 * wander.get_noise_2d(x, y))
	var path := astar.get_id_path(a, b)
	for p in path:
		var i := idx(p)
		if blocked[i] == 1:
			continue
		terrain[i] = T_ROAD
		keep_clear[i] = 1
		# keep a 1 tile apron free on most of the road so it reads as a road, not a corridor
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if inside(q) and rng.randf() < 0.6:
				keep_clear[idx(q)] = 1

func _place_mountains() -> void:
	# Look for 3x2 / 4x3 blocks fully covered by natural obstacle and turn them into mountains.
	for y in range(1, h - 2):
		for x in range(1, w - 3):
			var size := Vector2i(4, 3) if rng.randf() < 0.45 else Vector2i(3, 2)
			if x + size.x >= w or y + size.y >= h:
				continue
			var ok := true
			for yy in size.y:
				for xx in size.x:
					if blocked[idx(Vector2i(x + xx, y + yy))] != 2:
						ok = false
			if not ok or rng.randf() < 0.35:
				continue
			for yy in size.y:
				for xx in size.x:
					blocked[idx(Vector2i(x + xx, y + yy))] = 3  # 3 = covered by mountain sprite
			var t: int = terrain[idx(Vector2i(x + size.x / 2, y + size.y - 1))]
			var kind := "mountain_%d" % rng.randi_range(1, 3)
			if t == T_SNOW:
				kind = "mountain_snow_%d" % rng.randi_range(1, 2)
			var sc := (size.x * TILE) / 256.0 * rng.randf_range(1.05, 1.2)
			var m := (0.8 if size.x == 3 else 1.0) * rng.randf_range(1.0, 1.12)
			decor.append({"k": kind, "p": Vector2((x + size.x * 0.5) * TILE, (y + size.y * 0.5) * TILE), "s": sc, "m": m, "flip": rng.randf() < 0.5})

func _place_forests(kind_noise: FastNoiseLite) -> void:
	for y in h:
		for x in w:
			var i := idx(Vector2i(x, y))
			if blocked[i] != 2:
				continue
			blocked[i] = 1
			var t: int = terrain[i]
			var choices: Array
			match t:
				T_SNOW: choices = ["snow_pine_1", "snow_pine_2", "tree_pine_1"]
				T_SAND: choices = ["rock_1", "rock_2", "rock_3", "tree_dead_1"]
				T_SWAMP: choices = ["tree_dead_1", "tree_dead_2", "tree_oak_3", "bush_2"]
				T_DIRT: choices = ["tree_dead_1", "tree_dead_2", "tree_pine_2", "rock_2"] if kind_noise.get_noise_2d(x, y) > 0.0 else ["tree_pine_1", "tree_pine_2", "tree_pine_3"]
				_: choices = ["tree_oak_1", "tree_oak_2", "tree_oak_3", "tree_oak_4"] if kind_noise.get_noise_2d(x, y) > -0.1 else ["tree_pine_1", "tree_pine_2", "tree_pine_3"]
			var count := 2 if rng.randf() < 0.6 else 1
			for c in count:
				var k: String = choices[rng.randi() % choices.size()]
				var s := rng.randf_range(0.55, 0.75)
				if k.begins_with("rock"):
					s = rng.randf_range(0.7, 0.95)
				decor.append({"k": k, "p": Vector2((x + rng.randf_range(0.2, 0.8)) * TILE, (y + rng.randf_range(0.55, 1.0)) * TILE), "s": s, "m": rng.randf_range(0.8, 1.1), "flip": rng.randf() < 0.5})

## Ground details per terrain: [sprite, weight]. Upright ones are depth-sorted with trees and heroes.
const DECOR_KINDS := {
	T_GRASS: [["flowers_1", 0.6], ["flowers_2", 0.6], ["bush_1", 0.8], ["bush_2", 0.8], ["decor_tuft", 2.0], ["decor_wildflowers", 1.4],
		["decor_fern", 1.0], ["decor_toadstools", 0.8], ["decor_stump", 0.8], ["decor_log", 0.5], ["decor_twigs", 0.6],
		["decor_boulders", 0.6], ["decor_thorns", 0.4], ["decor_menhir", 0.2], ["decor_pillar", 0.15]],
	T_DIRT: [["rock_1", 0.6], ["rock_2", 0.6], ["rock_3", 0.6], ["decor_twigs", 1.0], ["decor_bones", 0.7], ["decor_thorns", 1.0],
		["decor_dry_grass", 1.2], ["decor_tuft", 0.8], ["decor_stump", 0.8], ["decor_boulders", 0.7], ["decor_menhir", 0.3], ["decor_pillar", 0.2]],
	T_SAND: [["rock_1", 0.5], ["rock_3", 0.5], ["decor_cactus", 1.2], ["decor_horn_skull", 0.6], ["decor_dry_grass", 1.6], ["decor_sandstone", 1.0],
		["decor_bones", 0.5]],
	T_SNOW: [["rock_1", 0.4], ["rock_2", 0.4], ["decor_snow_rock", 1.2], ["decor_ice", 0.8], ["decor_snow_stump", 1.0], ["decor_frost_shrub", 1.2]],
	T_SWAMP: [["bush_1", 0.6], ["bush_2", 0.6], ["decor_reeds", 2.0], ["decor_swamp_caps", 1.0], ["decor_mossy_log", 0.7], ["decor_swamp_shrub", 1.0],
		["decor_toadstools", 0.4], ["decor_fern", 0.6], ["decor_tuft", 0.8]],
}
const DECOR_UPRIGHT := ["decor_stump", "decor_log", "decor_boulders", "decor_thorns", "decor_menhir", "decor_pillar", "decor_cactus",
	"decor_sandstone", "decor_snow_rock", "decor_ice", "decor_snow_stump", "decor_frost_shrub", "decor_reeds", "decor_mossy_log", "decor_swamp_shrub"]

func _pick_weighted(items: Array) -> String:
	var total := 0.0
	for it in items:
		total += it[1]
	var r := rng.randf() * total
	for it in items:
		r -= it[1]
		if r <= 0.0:
			return it[0]
	return items[0][0]

func _near_obstacle(p: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if inside(p + d) and blocked[idx(p + d)] == 2:
			return true
	return false

func _passable(p: Vector2i) -> bool:
	if not inside(p):
		return false
	var i := idx(p)
	return blocked[i] == 0 and terrain[i] != T_WATER

func _reachable(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var stack := [from]
	while stack.size() > 0:
		var p: Vector2i = stack.pop_back()
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := p + Vector2i(dx, dy)
				if not seen.has(q) and _passable(q):
					seen[q] = true
					stack.append(q)
	return seen

func _place_obj(o: Dictionary, center: Vector2i, rmin: int, rmax: int, reach: Dictionary, guarded := false, min_town_dist := 0) -> Dictionary:
	var foot := footprint_for(o["type"])
	for attempt in 300:
		var p: Vector2i
		if rmax >= w:
			p = Vector2i(rng.randi_range(2, w - 3), rng.randi_range(2, h - 3))
		else:
			var ang := rng.randf() * TAU
			var r := rng.randf_range(rmin, rmax)
			p = center + Vector2i(roundi(cos(ang) * r), roundi(sin(ang) * r))
		if not inside(p) or not reach.has(p) or occupied.has(p) or not _passable(p):
			continue
		if terrain[idx(p)] == T_ROAD and foot.size() > 0:
			continue
		# keep entrances free: the tile below the action tile must be walkable for buildings
		if foot.size() > 0 and not _passable(p + Vector2i(0, 1)):
			continue
		var ok := true
		for off in foot:
			var q: Vector2i = p + off
			if not inside(q) or not _passable(q) or occupied.has(q) or keep_clear[idx(q)] or terrain[idx(q)] == T_ROAD:
				ok = false
				break
		if not ok:
			continue
		# don't crowd other objects
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if occupied.has(p + Vector2i(dx, dy)) and not (dx == 0 and dy == 0):
					ok = false
		if not ok:
			continue
		if min_town_dist > 0:
			for s in _town_positions():
				if Vector2(s).distance_to(Vector2(p)) < min_town_dist:
					ok = false
			if not ok:
				continue
		o["uid"] = GameState.next_uid()
		o["pos"] = p
		if o["type"] == "monster":
			_fill_monster(o)
		elif o["type"] == "chest":
			o["gold"] = [1000, 1500, 2000][rng.randi() % 3]
		elif o["type"] == "campfire":
			o["gold"] = rng.randi_range(4, 6) * 100
			o["res"] = ["wood", "ore", "mercury", "sulfur", "crystal", "gems"][rng.randi() % 6]
			o["amount"] = rng.randi_range(4, 6)
		world["objects"][o["uid"]] = o
		occupied[p] = o["uid"]
		for off in foot:
			blocked[idx(p + off)] = 1
		if foot.size() > 0:
			keep_clear[idx(p + Vector2i(0, 1))] = 1
		if guarded:
			_guard(o)
		return o
	return {}

var _town_pos_cache := []
func _town_positions() -> Array:
	if _town_pos_cache.is_empty():
		for p in occupied:
			var uid: int = occupied[p]
			if not world["objects"].has(uid):
				_town_pos_cache.append(p)
	return _town_pos_cache

func _guard(o: Dictionary) -> void:
	var p: Vector2i = o["pos"]
	var cands := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, 0), Vector2i(-1, 0)]
	if footprint_for(o["type"]).is_empty():
		cands = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	for d in cands:
		var q: Vector2i = p + d
		if inside(q) and _passable(q) and not occupied.has(q) and terrain[idx(q)] != T_ROAD:
			var m := {"type": "monster", "uid": GameState.next_uid(), "pos": q, "strength_bonus": 1.6}
			_fill_monster(m)
			world["objects"][m["uid"]] = m
			occupied[q] = m["uid"]
			return

func _fill_monster(o: Dictionary) -> void:
	var p: Vector2i = o["pos"]
	var d := 1e9
	for s in _town_positions():
		d = minf(d, Vector2(s).distance_to(Vector2(p)))
	var dn := clampf(d / (w * 0.6), 0.0, 1.0)
	var diff_mult: float = [0.75, 1.0, 1.35][clampi(int(world.get("difficulty", 1)), 0, 2)]
	var power := lerpf(700.0, 14000.0, dn * dn) * diff_mult * float(o.get("strength_bonus", 1.0))
	var tier_lo := 1 + int(dn * 4.0)
	var tier_hi := mini(7, tier_lo + 2)
	var cands := []
	for cid in GameData.CREATURES:
		var t: int = GameData.CREATURES[cid]["tier"]
		if t >= tier_lo and t <= tier_hi:
			cands.append(cid)
	var cid: String = cands[rng.randi() % cands.size()]
	o["creature"] = cid
	o["count"] = maxi(1, int(power / float(GameData.CREATURES[cid]["ai_value"]) * rng.randf_range(0.8, 1.2)))
	o["flip"] = rng.randf() < 0.5
