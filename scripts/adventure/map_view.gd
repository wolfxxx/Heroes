extends Node2D
class_name MapView
## Renders the adventure world: blended terrain, y-sorted decor/objects/heroes, path arrows, fog.

const TILE := WorldGen.TILE

var world: Dictionary
var _terrain: Node2D
var _ground: Node2D       # flat decor (flowers, pebbles)
var _sorted: Node2D       # y-sorted trees, mountains, objects, heroes
var _overlay: Node2D      # path arrows, hover
var _fog: Node2D
var _fog_img: Image
var _fog_tex: ImageTexture
var _object_nodes := {}   # uid -> Node2D
var _hero_nodes := {}     # uid -> Node2D
var _town_nodes := {}
var path_points: Array = []
var path_reach := 0
var path_end_kind := ""
var hover_tile := Vector2i(-1, -1)
var selected_hero := -1

func setup(w: Dictionary) -> void:
	world = w
	var size: Vector2i = world["size"]
	_terrain = _RectNode.new()
	_terrain.rect = Rect2(Vector2.ZERO, Vector2(size) * TILE)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/adventure/terrain.gdshader")
	mat.set_shader_parameter("terrain_tex", _terrain_array())
	mat.set_shader_parameter("index_map", _index_texture())
	mat.set_shader_parameter("map_size", Vector2(size))
	mat.set_shader_parameter("tile_px", float(TILE))
	mat.set_shader_parameter("water_index", WorldGen.T_WATER)
	mat.set_shader_parameter("road_map", _road_field())
	mat.set_shader_parameter("road_tex", Assets.tex("terrain/road.png"))
	_terrain.material = mat
	add_child(_terrain)

	_ground = Node2D.new()
	add_child(_ground)
	_overlay = _PathOverlay.new()
	_overlay.view = self
	add_child(_overlay)
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	add_child(_sorted)

	_fog = _RectNode.new()
	_fog.rect = Rect2(Vector2(-TILE * 16, -TILE * 16), Vector2(size + Vector2i(32, 32)) * TILE)  # (and the frame past the edge)
	_fog_img = Image.create(size.x, size.y, false, Image.FORMAT_L8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://scripts/adventure/fog.gdshader")
	fm.set_shader_parameter("fog_map", _fog_tex)
	fm.set_shader_parameter("map_size", Vector2(size))
	fm.set_shader_parameter("tile_px", float(TILE))
	_fog.material = fm
	_fog.z_index = 50
	add_child(_fog)

	_build_decor()
	_build_border()
	rebuild_objects()

# ---------------------------------------------------------------------------------------------
# Terrain textures
# ---------------------------------------------------------------------------------------------
func _terrain_array() -> Texture2DArray:
	var imgs: Array[Image] = []
	for t in WorldGen.TERRAIN_ORDER:
		var img: Image
		if Assets.has("terrain/%s.png" % t):
			img = Assets.tex("terrain/%s.png" % t).get_image()
		else:
			img = _procedural_terrain(t)
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.clear_mipmaps()
		if img.get_width() != 512 or img.get_height() != 512:
			img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		imgs.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr

func _procedural_terrain(t: String) -> Image:
	var base: Color = {"grass": Color(0.33, 0.52, 0.18), "dirt": Color(0.45, 0.35, 0.22), "sand": Color(0.82, 0.72, 0.48),
		"snow": Color(0.88, 0.91, 0.96), "swamp": Color(0.28, 0.33, 0.2), "water": Color(0.13, 0.33, 0.5), "road": Color(0.55, 0.47, 0.35)}[t]
	var n := FastNoiseLite.new()
	n.seed = t.hash()
	n.frequency = 0.02
	n.fractal_octaves = 5
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			# Seamless by blending four offset samples.
			var fx := x / 256.0
			var fy := y / 256.0
			var v := n.get_noise_2d(x, y) * (1 - fx) * (1 - fy) + n.get_noise_2d(x - 256, y) * fx * (1 - fy) \
				+ n.get_noise_2d(x, y - 256) * (1 - fx) * fy + n.get_noise_2d(x - 256, y - 256) * fx * fy
			img.set_pixel(x, y, base.lightened(v * 0.35) if v > 0 else base.darkened(-v * 0.45))
	return img

## One texel per tile. Road tiles take the ground around them: the road itself is drawn from _road_field().
func _index_texture() -> ImageTexture:
	var size: Vector2i = world["size"]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_R8)
	var terr: PackedByteArray = world["terrain"]
	for y in size.y:
		for x in size.x:
			var t: int = terr[y * size.x + x]
			if t == WorldGen.T_ROAD:
				t = _ground_under_road(Vector2i(x, y))
			img.set_pixel(x, y, Color(t / 255.0, 0, 0))
	return ImageTexture.create_from_image(img)

func _ground_under_road(p: Vector2i) -> int:
	var size: Vector2i = world["size"]
	var terr: PackedByteArray = world["terrain"]
	var count := {}
	for r in [1, 2, 3]:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y:
					continue
				var t: int = terr[q.y * size.x + q.x]
				if t != WorldGen.T_ROAD and t != WorldGen.T_WATER:
					count[t] = count.get(t, 0) + 1
		if not count.is_empty():
			break
	var best := WorldGen.T_GRASS
	for t in count:
		if count[t] > count.get(best, 0):
			best = t
	return best

# ---------------------------------------------------------------------------------------------
# Roads: road tiles -> smoothed polylines -> distance field (in tiles) the terrain shader paints cobbles from
# ---------------------------------------------------------------------------------------------
const ROAD_RES := 8      # distance-field texels per tile
const ROAD_REACH := 0.9  # distances are stored up to this many tiles

func _is_road(p: Vector2i) -> bool:
	var size: Vector2i = world["size"]
	return p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y and world["terrain"][p.y * size.x + p.x] == WorldGen.T_ROAD

## Road tiles linked to their road neighbours: straight neighbours always, diagonal ones only when no straight
## neighbour already joins them (so a stair step reads as one diagonal, not a zigzag).
func _road_links(p: Vector2i) -> Array:
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _is_road(p + d):
			out.append(p + d)
	for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if _is_road(p + d) and not _is_road(p + Vector2i(d.x, 0)) and not _is_road(p + Vector2i(0, d.y)):
			out.append(p + d)
	return out

## Chains of road tiles between junctions / ends (each link used once), as tile-centre polylines.
func road_polylines() -> Array:
	var size: Vector2i = world["size"]
	var links := {}
	for y in size.y:
		for x in size.x:
			var p := Vector2i(x, y)
			if _is_road(p):
				links[p] = _road_links(p)
	var used := {}
	var lines := []
	var starts: Array = links.keys().filter(func(p): return links[p].size() != 2)
	starts += links.keys()  # loops have no ends: any tile starts them
	for a in starts:
		for b in links[a]:
			if used.has(_lk(a, b)):
				continue
			var line := [a]
			var prev: Vector2i = a
			var cur: Vector2i = b
			used[_lk(a, b)] = true
			used[_lk(b, a)] = true
			while true:
				line.append(cur)
				if links[cur].size() != 2:
					break
				var nxt: Vector2i = links[cur][0] if links[cur][0] != prev else links[cur][1]
				if used.has(_lk(cur, nxt)):
					break
				used[_lk(cur, nxt)] = true
				used[_lk(nxt, cur)] = true
				prev = cur
				cur = nxt
			lines.append(line)
	for p in links:  # a lone road tile
		if links[p].is_empty():
			lines.append([p, p])
	return lines

static func _lk(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x, a.y, b.x, b.y)

## Corner cutting: rounds the bends while the ends stay where they are (junctions keep meeting).
static func _chaikin(pts: PackedVector2Array, rounds: int) -> PackedVector2Array:
	for r in rounds:
		if pts.size() < 3:
			return pts
		var out := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			if i > 0:
				out.append(a.lerp(b, 0.25))
			if i < pts.size() - 2:
				out.append(a.lerp(b, 0.75))
		out.append(pts[pts.size() - 1])
		pts = out
	return pts

func _road_field() -> ImageTexture:
	var size: Vector2i = world["size"]
	var fw := size.x * ROAD_RES
	var fh := size.y * ROAD_RES
	var dist := PackedFloat32Array()
	dist.resize(fw * fh)
	dist.fill(ROAD_REACH)
	var reach := ROAD_REACH * ROAD_RES
	for line in road_polylines():
		var pts := PackedVector2Array()
		for t in line:
			pts.append((Vector2(t) + Vector2(0.5, 0.5)) * ROAD_RES)
		pts = _chaikin(pts, 3)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 1e-6)
			var x0 := maxi(0, int(minf(a.x, b.x) - reach))
			var x1 := mini(fw - 1, int(maxf(a.x, b.x) + reach) + 1)
			var y0 := maxi(0, int(minf(a.y, b.y) - reach))
			var y1 := mini(fh - 1, int(maxf(a.y, b.y) + reach) + 1)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var q := Vector2(x + 0.5, y + 0.5)
					var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
					var d := q.distance_to(a + ab * t) / ROAD_RES
					var k := y * fw + x
					if d < dist[k]:
						dist[k] = d
	var bytes := PackedByteArray()
	bytes.resize(fw * fh)
	for k in dist.size():
		bytes[k] = int(dist[k] / ROAD_REACH * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(fw, fh, false, Image.FORMAT_L8, bytes))

# ---------------------------------------------------------------------------------------------
# Sprites
# ---------------------------------------------------------------------------------------------
## Sprites rendered by the Blender pipeline carry an anchor and are drawn at a fixed world scale
## (RENDER_SCALE * mult); placeholders fall back to display_w / display_h sizing.
const RENDER_SCALE := 0.5

func _sprite(tex_path: String, foot: Vector2, display_w: float, flip := false, display_h := 0.0, mult := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex_path, Vector2i(96, 96))
	var tw := float(s.texture.get_width())
	var th := float(s.texture.get_height())
	var anc := Assets.anchor(tex_path)
	s.position = foot
	s.flip_h = flip
	if anc.x >= 0.0:
		s.centered = false
		s.scale = Vector2.ONE * RENDER_SCALE * mult
		var ax := (1.0 - anc.x) if flip else anc.x
		s.offset = -Vector2(ax * tw, anc.y * th)
		return s
	var sc := display_w / tw if display_h <= 0.0 else display_h / th
	s.scale = Vector2(sc, sc)
	s.centered = true
	s.offset = Vector2(0, -th * 0.5)
	return s

const DECOR_REF_W := {"mountain": 256.0, "tree": 150.0, "snow": 150.0, "rock": 90.0, "bush": 90.0, "flowers": 80.0, "decor": 100.0}

const OUTLINE_SHADER := preload("res://scripts/ui/sprite_outline.gdshader")

## Ink outline + rim light so 3D renders match the outlined map art.
static func outline(s: Sprite2D, width := 2.0) -> void:
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("px", 1.0 / maxf(0.05, s.scale.x))
	m.set_shader_parameter("width", width)
	s.material = m

func _build_decor() -> void:
	for d in world["decor"]:
		var k: String = d["k"]
		var ref: float = DECOR_REF_W.get(k.split("_")[0], 120.0)
		var s := _sprite("map/%s.png" % k, d["p"], ref * float(d["s"]), d.get("flip", false), 0.0, float(d.get("m", 1.0)))
		if d.get("flat", false):
			_ground.add_child(s)
		else:
			_sorted.add_child(s)

## Past the map's edge, as the classic map's mountain border: a range of the map's own mountains standing around it
## on the rocky ridge and the map's outermost row, over the void (above the fog layer: nothing out there is
## unexplored).
func _build_border() -> void:
	var size: Vector2i = world["size"]
	var border := Node2D.new()
	border.y_sort_enabled = true
	border.z_index = 51
	add_child(border)
	var rock_mat := ShaderMaterial.new()  # (rock, not grass, at their feet)
	rock_mat.shader = load("res://scripts/adventure/border_rock.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = size.x * 7919 + size.y
	var snowy := func(t: Vector2i) -> bool:
		var c := Vector2i(clampi(t.x, 0, size.x - 1), clampi(t.y, 0, size.y - 1))
		return world["terrain"][c.y * size.x + c.x] == WorldGen.T_SNOW
	# (a range, not a row: sizes vary, now and then a smaller peak beside the first and a few boulders in the gaps; the
	# along-edge step `ax` sets which way they spread)
	var put := func(foot: Vector2, m: float, near: Vector2i, ax: Vector2) -> void:
		var mount := func(f: Vector2, mm: float) -> void:
			var k := ("mountain_snow_%d" % rng.randi_range(1, 2)) if snowy.call(near) else ("mountain_%d" % rng.randi_range(1, 3))
			var sp := _sprite("map/%s.png" % k, f, 256.0, rng.randf() < 0.5, 0.0, mm)
			sp.material = rock_mat
			border.add_child(sp)
		m *= rng.randf_range(0.85, 1.4) * (1.75 if rng.randf() < 0.22 else 1.0)  # (now and then a great massif)
		mount.call(foot, m)
		if rng.randf() < 0.35:
			mount.call(foot + ax * rng.randf_range(0.9, 1.3) * TILE + Vector2(ax.y, ax.x).abs() * rng.randf_range(-6, 14), m * rng.randf_range(0.6, 0.75))
		for i in rng.randi_range(0, 2):
			var r := _sprite("map/rock_%d.png" % rng.randi_range(1, 3), foot - ax * rng.randf_range(1.0, 1.9) * TILE + Vector2(ax.y, ax.x).abs() * rng.randf_range(-4, 14),
				90.0, rng.randf() < 0.5, 0.0, rng.randf_range(0.6, 1.05))
			r.material = rock_mat
			border.add_child(r)
	# (standing on the map's outermost row, which the generator fills with rocks and trees anyway: the view runs only two
	# tiles past the edge, a range further out showed as slivers)
	var x := -2.0
	while x < size.x + 2.0:  # along the top and the bottom
		put.call(Vector2(x * TILE, 0.15 * TILE + rng.randf_range(-30, 44)), rng.randf_range(0.6, 0.7), Vector2i(int(x), 0), Vector2.RIGHT)
		x += rng.randf_range(1.6, 7.6)  # (fewer, larger peaks, bare rock between, never evenly spaced)
	x = -2.0
	while x < size.x + 2.0:
		put.call(Vector2(x * TILE, (size.y + 1.3) * TILE + rng.randf_range(-6, 8)), rng.randf_range(0.58, 0.68), Vector2i(int(x), size.y - 1), Vector2.RIGHT)
		x += rng.randf_range(1.6, 7.6)  # (fewer, larger peaks, bare rock between, never evenly spaced)
	var y := 1.0
	while y < size.y + 1.0:  # down the sides
		put.call(Vector2(-1.2 * TILE + rng.randf_range(-22, 6), y * TILE), rng.randf_range(0.5, 0.58), Vector2i(0, int(y)), Vector2.DOWN)
		put.call(Vector2((size.x + 1.2) * TILE + rng.randf_range(-6, 22), y * TILE), rng.randf_range(0.5, 0.58), Vector2i(size.x - 1, int(y)), Vector2.DOWN)
		y += rng.randf_range(1.6, 5.2)

func rebuild_objects() -> void:
	for n in _object_nodes.values():
		n.queue_free()
	for n in _hero_nodes.values():
		n.queue_free()
	for n in _town_nodes.values():
		n.queue_free()
	_object_nodes.clear()
	_hero_nodes.clear()
	_town_nodes.clear()
	for t in world["towns"].values():
		var n := Node2D.new()
		n.position = foot_of(t["pos"])
		n.add_child(_sprite("map/town_%s.png" % t["faction"], Vector2.ZERO, 5.6 * TILE))
		if t["owner"] >= 0:
			_add_flag(n, Vector2(-1.9 * TILE, -1.9 * TILE), t["owner"], 64.0)
		_sorted.add_child(n)
		_town_nodes[t["uid"]] = n
	for o in world["objects"].values():
		var n := _object_node(o)
		if n:
			_sorted.add_child(n)
			_object_nodes[o["uid"]] = n
	for h in world["heroes"].values():
		if h.get("in_town", false):
			continue
		var n := _hero_node(h)
		_sorted.add_child(n)
		_hero_nodes[h["uid"]] = n

func _object_node(o: Dictionary) -> Node2D:
	var n := Node2D.new()
	n.position = foot_of(o["pos"])
	match o["type"]:
		"resource":
			n.add_child(_sprite("map/res_%s.png" % o["res"], Vector2(0, -6), 70))
		"chest":
			n.add_child(_sprite("map/chest.png", Vector2(0, -6), 62))
		"campfire":
			n.add_child(_sprite("map/campfire.png", Vector2(0, -4), 70))
		"artifact":
			# (as the classic map: the artifact itself lies there, on a glow of its tier's colour)
			var tier: String = GameData.ARTIFACTS[o["artifact"]]["tier"]
			var glow := _ArtifactGlow.new()
			glow.col = GameData.ARTIFACT_TIERS[tier][1]
			glow.strong = tier in ["major", "relic"]
			n.add_child(glow)
			var s := Sprite2D.new()  # (tools/art/artifact_map_sprites.py: the item cut out of its painting, with a shadow)
			s.texture = Assets.tex("map/art_%s.png" % o["artifact"], Vector2i(96, 96))
			# (the better, the bigger; by area, so a tall thin banner is not the smallest item there)
			var want: float = {"treasure": 46.0, "minor": 50.0, "major": 56.0, "relic": 64.0}.get(tier, 50.0)
			var ts := Vector2(s.texture.get_size())
			s.scale = Vector2.ONE * minf(want / sqrt(ts.x * ts.y), 86.0 / ts.y)
			s.offset = Vector2(0, -s.texture.get_height() * 0.5 + 8)
			s.position = Vector2(0, -2)
			outline(s, 1.6)
			n.add_child(s)
		"mine":
			n.add_child(_sprite("map/%s.png" % o["mine"], Vector2.ZERO, 3.1 * TILE))
			if o["owner"] >= 0:
				_add_flag(n, Vector2(-1.25 * TILE, -1.0 * TILE), o["owner"], 60.0)
		"shrine":
			n.add_child(_sprite("map/shrine.png", Vector2.ZERO, 2.6 * TILE))
		"windmill":
			n.add_child(_sprite("map/windmill.png", Vector2.ZERO, 2.6 * TILE))
		"watchtower":
			n.add_child(_sprite("map/watchtower.png", Vector2.ZERO, 2.2 * TILE))
		"learning_stone":
			n.add_child(_sprite("map/obelisk.png", Vector2.ZERO, 1.8 * TILE))
		"dwelling":
			n.add_child(_sprite("map/dwelling_neutral.png", Vector2.ZERO, 2.8 * TILE))
		"monster":
			var path := "map/monster_%s.png" % o["creature"]
			if not Assets.has(path):
				path = "creatures/%s.png" % o["creature"]
			var big: bool = "two_hex" in GameData.CREATURES[o["creature"]]["abilities"]
			# creature renders are 150 px/unit vs 64 for map art; draw them a bit larger than true scale
			var ms := _sprite(path, Vector2(0, -WorldGen.TILE * 0.5 + 6), 0, o.get("flip", false), 92.0 if big else 72.0, 0.72)
			var fig := _monster_fig(path.get_file())
			if not ms.centered and fig.y > 0.0:
				# one scale for all guards: height by tier, the visible width (wings, horses) kept to about two tiles
				var sc: float = (88.0 + 5.0 * GameData.CREATURES[o["creature"]]["tier"]) / fig.y
				sc = minf(sc, (2.4 if big else 1.9) * TILE / fig.x)
				ms.scale = Vector2.ONE * sc
			outline(ms)
			n.add_child(ms)
		_:
			return null
	return n

func _hero_node(h: Dictionary) -> Node2D:
	var n := Node2D.new()
	n.position = hero_foot(h["pos"])
	var ring := _Ring.new()
	ring.name = "Ring"
	ring.visible = h["uid"] == selected_hero
	n.add_child(ring)
	# the banner stands behind the hero, flying away from the horse
	_add_flag(n, Vector2(-24, -16), h["owner"], 100.0, true)
	var spr := _sprite("heroes/map_%s.png" % h["faction"], Vector2(0, 4), 0, h.get("face_left", false), 118.0, 1.35)
	spr.name = "Sprite"
	spr.set_meta("faction", h["faction"])
	outline(spr)
	var tc: Color = GameData.PLAYER_COLORS[h["owner"]]
	spr.material.set_shader_parameter("team", Color(tc.r, tc.g, tc.b, 0.85))  # owner colour ring: whose hero at a glance
	n.add_child(spr)
	return n

## Owner banner, painted (tools/art/flag_paint.py): pos = foot of the pole, h = drawn height.
func _add_flag(parent: Node2D, pos: Vector2, owner: int, h := 60.0, fly_left := false) -> void:
	var f := _Flag.new()
	f.color = GameData.PLAYER_COLORS[owner]
	f.position = pos
	var sc := h / float(_Flag.FH)
	f.scale = Vector2(-sc if fly_left else sc, sc)
	parent.add_child(f)

func foot_of(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TILE, (tile.y + 1.0) * TILE - 6)

## Where a hero stands on a tile: at a town's gate it steps out onto the road, in front of the wall (not into it).
func hero_foot(tile: Vector2i) -> Vector2:
	for t in world["towns"].values():
		if t["pos"] == tile:
			return foot_of(tile) + Vector2(0, 0.42 * TILE)
	return foot_of(tile)

func tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TILE

func tile_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))

## (visible width, solid height) of a creature render, from creatures/sizes.json
static var _fig_sizes = null
static func _monster_fig(file: String) -> Vector2:
	if _fig_sizes == null:
		_fig_sizes = {}
		var p := Assets.path("creatures/sizes.json")
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(d) == TYPE_DICTIONARY:
				_fig_sizes = d
	var v = _fig_sizes.get(file)
	if v == null:
		return Vector2.ZERO
	return Vector2(float(v[2]) if v.size() > 2 else float(v[0]), float(v[1]))

const PICKABLE := ["monster", "resource", "chest", "campfire", "artifact"]
var _alpha_cache := {}

## The tile of the hero or small map object (monster, pickup) whose sprite has a solid pixel at world point p,
## front-most first; (-1, -1) if none. Sprites are taller than their tile, so tile_at() alone misses them.
func sprite_tile_at(p: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_y := -INF
	var cands := []
	for uid in _object_nodes:
		var o: Dictionary = world["objects"].get(uid, {})
		if o.get("type", "") in PICKABLE:
			cands.append([_object_nodes[uid], o["pos"]])
	for uid in _hero_nodes:
		if world["heroes"].has(uid):
			cands.append([_hero_nodes[uid], world["heroes"][uid]["pos"]])
	# only the object's own column, up to two tiles above it: a click beside a sprite still means that tile
	var pt := tile_at(p)
	for c in cands:
		var n: Node2D = c[0]
		var pos: Vector2i = c[1]
		if not is_instance_valid(n) or n.position.y <= best_y or pt.x != pos.x or pt.y > pos.y or pt.y < pos.y - 2:
			continue
		for s in n.get_children():
			if s is Sprite2D and _solid(s, p):
				best = c[1]
				best_y = n.position.y
				break
	return best

func _solid(s: Sprite2D, p: Vector2) -> bool:
	var lp: Vector2 = s.get_global_transform().affine_inverse() * p
	var r := s.get_rect()
	if not r.has_point(lp):
		return false
	var tex := s.texture
	if not _alpha_cache.has(tex):
		var img := tex.get_image()
		if img and img.is_compressed():
			img.decompress()
		_alpha_cache[tex] = img
	var img: Image = _alpha_cache[tex]
	if img == null:
		return true
	var px := Vector2i(((lp - r.position) / r.size * Vector2(img.get_size())).floor())
	if s.flip_h:
		px.x = img.get_width() - 1 - px.x
	px = px.clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)
	return img.get_pixelv(px).a > 0.5

func hero_node(uid: int) -> Node2D:
	return _hero_nodes.get(uid)

func set_selected(uid: int) -> void:
	selected_hero = uid
	for k in _hero_nodes:
		var r: Node = _hero_nodes[k].get_node_or_null("Ring")
		if r:
			r.visible = k == uid

func remove_object(uid: int) -> void:
	if _object_nodes.has(uid):
		var n: Node2D = _object_nodes[uid]
		_object_nodes.erase(uid)
		var tw := n.create_tween()
		tw.tween_property(n, "modulate:a", 0.0, 0.3)
		tw.tween_callback(n.queue_free)

func refresh_object(uid: int) -> void:
	if _object_nodes.has(uid):
		_object_nodes[uid].queue_free()
		_object_nodes.erase(uid)
	if world["objects"].has(uid):
		var n := _object_node(world["objects"][uid])
		if n:
			_sorted.add_child(n)
			_object_nodes[uid] = n

func refresh_town(uid: int) -> void:
	rebuild_objects()

func move_hero_step(uid: int, to_tile: Vector2i, dur: float) -> void:
	var n: Node2D = _hero_nodes.get(uid)
	if n == null:
		return
	var target := hero_foot(to_tile)
	var spr: Sprite2D = n.get_node("Sprite")
	var flip := spr.flip_h
	if absf(target.x - n.position.x) > 1.0:
		flip = target.x < n.position.x
	var tw := n.create_tween()
	tw.tween_property(n, "position", target, dur)
	# gallop: two frames of the 4-frame cycle per tile, a rocking stride and a little dust
	var fac: String = spr.get_meta("faction", "")
	var frame: int = spr.get_meta("run_frame", 0)
	var has_run := Assets.has("heroes/map_%s_run0.png" % fac)
	# (the timers hold the sprite's id, not the sprite: the map may rebuild its objects before they fire)
	var sid := spr.get_instance_id()
	for i in 2:
		var k := (frame + i) % 4
		if has_run:
			get_tree().create_timer(dur * 0.5 * i).timeout.connect(func():
				var s2 = instance_from_id(sid)
				if s2 is Sprite2D:
					_set_hero_tex(s2, "heroes/map_%s_run%d.png" % [fac, k], flip))
	spr.set_meta("run_frame", (frame + 2) % 4)
	if not has_run:
		_set_hero_tex(spr, "heroes/map_%s.png" % fac, flip)
	var tw2 := spr.create_tween().set_parallel(true)
	var lean := -0.05 if flip else 0.05
	tw2.tween_property(spr, "position:y", -2.0, dur * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw2.tween_property(spr, "rotation", lean if frame % 4 == 0 else -lean * 0.4, dur * 0.5)
	tw2.chain().tween_property(spr, "position:y", 4.0, dur * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw2.parallel().tween_property(spr, "rotation", 0.0, dur * 0.5)
	if frame % 4 == 0:
		var dust := _HoofDust.new()
		dust.position = n.position + Vector2(-26 if not flip else 26, -2)
		_sorted.add_child(dust)
	# back to the standing sprite once no newer step has arrived
	var token: int = spr.get_meta("step_token", 0) + 1
	spr.set_meta("step_token", token)
	get_tree().create_timer(dur + 0.12).timeout.connect(func():
		var s2 = instance_from_id(sid)
		if s2 is Sprite2D and s2.get_meta("step_token", 0) == token:
			s2.rotation = 0.0
			_set_hero_tex(s2, "heroes/map_%s.png" % fac, flip))

## Swap a hero's texture keeping the feet anchored, mirrored when facing left.
func _set_hero_tex(spr: Sprite2D, rel: String, flip: bool) -> void:
	if not Assets.has(rel):
		return
	spr.texture = Assets.tex(rel)
	spr.flip_h = flip
	var anc := Assets.anchor(rel)
	if anc.x >= 0.0:
		var ax := (1.0 - anc.x) if flip else anc.x
		spr.offset = -Vector2(ax * spr.texture.get_width(), anc.y * spr.texture.get_height())

func update_fog(player: Dictionary) -> void:
	var size: Vector2i = world["size"]
	var ex: PackedByteArray = player["explored"]
	var data := PackedByteArray()
	data.resize(size.x * size.y)
	for i in ex.size():
		data[i] = 255 if ex[i] else 0
	var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, data)  # fog.gdshader rounds the edge
	if _fog_img.get_width() != img.get_width():
		_fog_img = img
		_fog_tex = ImageTexture.create_from_image(_fog_img)
		(_fog.material as ShaderMaterial).set_shader_parameter("fog_map", _fog_tex)
	else:
		_fog_img = img
		_fog_tex.update(_fog_img)

func set_path(points: Array, reach: int, end_kind: String) -> void:
	path_points = points
	path_reach = reach
	path_end_kind = end_kind
	_overlay.queue_redraw()

func clear_path() -> void:
	set_path([], 0, "")

func set_hover(t: Vector2i) -> void:
	if t != hover_tile:
		hover_tile = t
		_overlay.queue_redraw()

# ---------------------------------------------------------------------------------------------
# Inner helper nodes
# ---------------------------------------------------------------------------------------------
## The ground under an artifact lying on the map: a dark contact shadow, a faint soft light of its tier's colour
## (no plate: the classic shows just the item) and, for the better ones, a slow twinkle.
class _ArtifactGlow extends Node2D:
	var col := Color.WHITE
	var strong := false
	var t := randf() * 10.0
	func _process(d: float) -> void:
		if strong:
			t += d
			queue_redraw()
	func _draw() -> void:
		draw_set_transform(Vector2(0, -2), 0, Vector2(1, 0.38))
		for i in 6:  # (a soft falloff, faint at the middle too)
			draw_circle(Vector2.ZERO, 34 - i * 4, Color(col, 0.025 + i * 0.008))
		draw_circle(Vector2.ZERO, 14, Color(0, 0, 0, 0.32))
		draw_set_transform(Vector2.ZERO)
		if strong:
			for k in 2:
				var a := 0.5 + 0.5 * sin(t * 2.2 + k * 2.6)
				var p := Vector2(-16 + k * 30, -40 - k * 14)
				var c := Color(1.0, 0.96, 0.85, 0.75 * a)
				draw_line(p - Vector2(5, 0), p + Vector2(5, 0), c, 1.5, true)
				draw_line(p - Vector2(0, 5), p + Vector2(0, 5), c, 1.5, true)

class _RectNode extends Node2D:
	var rect := Rect2()
	func _draw() -> void:
		draw_rect(rect, Color.WHITE)

class _HoofDust extends Node2D:
	var t := 0.0
	var _p := []
	func _ready() -> void:
		for i in 5:
			_p.append([randf_range(-1, 1), randf_range(0.6, 1.2)])
		var tw := create_tween()
		tw.tween_property(self, "t", 1.0, 0.55).set_ease(Tween.EASE_OUT)
		tw.tween_callback(queue_free)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		for p in _p:
			draw_set_transform(Vector2(p[0] * 22.0 * (0.4 + t), -10.0 * t), 0, Vector2(1, 0.55))
			draw_circle(Vector2.ZERO, 9.0 * p[1] * (0.5 + t), Color(0.6, 0.52, 0.4, 0.38 * (1.0 - t)))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

class _Ring extends Node2D:
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var a := 0.55 + 0.25 * sin(t * 4.0)
		draw_set_transform(Vector2(0, -4), 0, Vector2(1, 0.45))
		draw_circle(Vector2.ZERO, 34, Color(1, 0.85, 0.3, 0.18 * a))
		draw_arc(Vector2.ZERO, 34, 0, TAU, 48, Color(1, 0.85, 0.35, a), 3.0, true)

class _Flag extends Node2D:
	const FW := 91  # one frame of map/flag_pole.png and map/flag_cloth.png (4 frames side by side)
	const FH := 112
	const POLE_X := 4.0  # the pole's x in a frame
	var color := Color.RED
	var _frame := -1
	func _process(_d: float) -> void:
		var f := int(Time.get_ticks_msec() / 150.0 + get_instance_id() % 4) % 4
		if f != _frame:
			_frame = f
			queue_redraw()
	func _draw() -> void:
		var src := Rect2(_frame * FW, 0, FW, FH)
		var dst := Rect2(-POLE_X, -FH, FW, FH)
		draw_texture_rect_region(Assets.tex("map/flag_pole.png"), dst, src)
		draw_texture_rect_region(Assets.tex("map/flag_cloth.png"), dst, src, color.lightened(0.1))

class _PathOverlay extends Node2D:
	var view
	func _draw() -> void:
		var T := float(WorldGen.TILE)
		if view.hover_tile.x >= 0:
			# corner brackets around the tile under the cursor (a filled square read as a stray patch on the art)
			var o := Vector2(view.hover_tile) * T
			var k := T * 0.24
			for c in [[o, Vector2(1, 1)], [o + Vector2(T, 0), Vector2(-1, 1)], [o + Vector2(0, T), Vector2(1, -1)], [o + Vector2(T, T), Vector2(-1, -1)]]:
				var p: Vector2 = c[0]
				var d: Vector2 = c[1]
				var pts := PackedVector2Array([p + Vector2(d.x * k, 0), p, p + Vector2(0, d.y * k)])
				draw_polyline(pts, Color(0, 0, 0, 0.45), 4.0)
				draw_polyline(pts, Color(1, 0.95, 0.75, 0.75), 2.0)
		var pts: Array = view.path_points
		for i in range(1, pts.size()):
			var p: Vector2 = (Vector2(pts[i]) + Vector2(0.5, 0.5)) * T
			var ok: bool = i <= view.path_reach
			var col := Color(0.35, 0.95, 0.35) if ok else Color(0.95, 0.3, 0.25)
			if i == pts.size() - 1:
				# Destination marker: cross for battle, X for end.
				var r := 14.0
				if view.path_end_kind == "attack":
					draw_line(p + Vector2(-r, -r), p + Vector2(r, r), Color(0, 0, 0, 0.6), 7.0)
					draw_line(p + Vector2(-r, r), p + Vector2(r, -r), Color(0, 0, 0, 0.6), 7.0)
					draw_line(p + Vector2(-r, -r), p + Vector2(r, r), col, 4.0)
					draw_line(p + Vector2(-r, r), p + Vector2(r, -r), col, 4.0)
				else:
					draw_circle(p, 11, Color(0, 0, 0, 0.5))
					draw_circle(p, 8, col)
				continue
			var nxt: Vector2 = (Vector2(pts[i + 1]) + Vector2(0.5, 0.5)) * T
			var dir := (nxt - p).normalized()
			var side := Vector2(-dir.y, dir.x)
			var tip := p + dir * 13
			var tri := PackedVector2Array([tip, p - dir * 9 + side * 10, p - dir * 4, p - dir * 9 - side * 10])
			var shadow := PackedVector2Array()
			for q in tri:
				shadow.append(q + Vector2(2, 2))
			draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
			draw_colored_polygon(tri, col)
