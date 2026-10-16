extends Node
## Asset loader with placeholder fallback. Use Assets.tex("creatures/pikeman.png").
## Loads from res://assets/. If the file does not exist yet, returns a coloured placeholder so the
## game remains runnable while art is being produced.

var _cache := {}

func path(rel: String) -> String:
	return "res://assets/" + rel

func has(rel: String) -> bool:
	return ResourceLoader.exists(path(rel)) or FileAccess.file_exists(path(rel))

func tex(rel: String, placeholder_size := Vector2i(64, 64)) -> Texture2D:
	if _cache.has(rel):
		return _cache[rel]
	var t: Texture2D = null
	var p := path(rel)
	if ResourceLoader.exists(p):
		t = load(p)
	elif FileAccess.file_exists(p):
		# Not yet imported by the editor: load raw image.
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	if t == null:
		t = _placeholder(rel, placeholder_size)
	_cache[rel] = t
	return t

func sound(rel: String) -> AudioStream:
	if _cache.has(rel):
		return _cache[rel]
	var p := path(rel)
	var s: AudioStream = null
	if ResourceLoader.exists(p):
		s = load(p)
	elif FileAccess.file_exists(p):
		if p.ends_with(".mp3"):
			s = AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(p))
		elif p.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(p))
		elif p.ends_with(".wav"):
			s = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(p))
	_cache[rel] = s
	return s

func _placeholder(rel: String, size: Vector2i) -> Texture2D:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var h := float(abs(rel.hash()) % 1000) / 1000.0
	var c := Color.from_hsv(h, 0.55, 0.8)
	img.fill(Color(0, 0, 0, 0))
	var m := 2
	for y in range(m, size.y - m):
		for x in range(m, size.x - m):
			var edge := x < m + 3 or y < m + 3 or x > size.x - m - 4 or y > size.y - m - 4
			img.set_pixel(x, y, c.darkened(0.5) if edge else c)
	return ImageTexture.create_from_image(img)

## Pixel anchor (normalised 0..1, from the top-left) of a rendered sprite's foot point, written by the
## Blender pipeline to <dir>/anchors.json. Returns Vector2(-1, -1) when the sprite has no anchor.
var _anchors := {}
func anchor(rel: String) -> Vector2:
	var dir := rel.get_base_dir()
	if not _anchors.has(dir):
		var d := {}
		var p := path(dir + "/anchors.json")
		if FileAccess.file_exists(p):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(parsed) == TYPE_DICTIONARY:
				d = parsed
		_anchors[dir] = d
	var a = _anchors[dir].get(rel.get_file())
	if a == null or not has(rel):
		return Vector2(-1, -1)
	return Vector2(a[0], a[1])

# Convenience helpers -------------------------------------------------------------------------
func creature(id: String) -> Texture2D: return tex("creatures/%s.png" % id, Vector2i(256, 256))
func creature_portrait(id: String) -> Texture2D:
	if has("creatures/portraits/%s.png" % id):
		return tex("creatures/portraits/%s.png" % id)
	return creature(id)
func hero_portrait(id: String) -> Texture2D: return tex("heroes/portraits/%s.png" % id, Vector2i(128, 128))
func res_icon(r: String) -> Texture2D: return tex("icons/res_%s.png" % r, Vector2i(32, 32))
func spell_icon(s: String) -> Texture2D: return tex("icons/spell_%s.png" % s, Vector2i(64, 64))
func artifact_icon(a: String) -> Texture2D: return tex("icons/artifact_%s.png" % a, Vector2i(64, 64))
func skill_icon(s: String) -> Texture2D: return tex("icons/skill_%s.png" % s, Vector2i(48, 48))
