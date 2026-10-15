extends Node
## Music + SFX manager. Audio.music("battle"), Audio.sfx("sword_hit").
## Files: res://assets/audio/music/<name>.mp3, res://assets/audio/sfx/<name>.mp3

var music_volume_db := -8.0
var sfx_volume_db := -2.0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_is_a := true
var _current := ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _last_played := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for p in [_music_a, _music_b]:
		p.bus = "Master"
		p.volume_db = -80
		add_child(p)
		p.finished.connect(_on_music_finished.bind(p))
	for i in 16:
		var s := AudioStreamPlayer.new()
		add_child(s)
		_sfx_pool.append(s)

func music(name: String, fade := 1.5) -> void:
	if name == _current:
		return
	_current = name
	var stream := Assets.sound("audio/music/%s.mp3" % name)
	var incoming := _music_b if _active_is_a else _music_a
	var outgoing := _music_a if _active_is_a else _music_b
	_active_is_a = not _active_is_a
	var tw := create_tween().set_parallel(true)
	tw.tween_property(outgoing, "volume_db", -80.0, fade)
	if stream:
		incoming.stream = stream
		incoming.volume_db = -60
		incoming.play()
		tw.tween_property(incoming, "volume_db", music_volume_db, fade)
	tw.chain().tween_callback(outgoing.stop)

func stop_music(fade := 1.0) -> void:
	_current = ""
	var tw := create_tween().set_parallel(true)
	for p in [_music_a, _music_b]:
		tw.tween_property(p, "volume_db", -80.0, fade)

func _on_music_finished(p: AudioStreamPlayer) -> void:
	# Loop music tracks except stings.
	if _current != "" and not _current in ["victory", "defeat"] and p.stream:
		p.play()

func sfx(name: String, volume_offset := 0.0, pitch_var := 0.06) -> void:
	var now := Time.get_ticks_msec()
	if _last_played.get(name, -1000) > now - 40:
		return # de-duplicate identical sounds in the same frame
	_last_played[name] = now
	var stream := Assets.sound("audio/sfx/%s.mp3" % name)
	if stream == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = sfx_volume_db + volume_offset
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return

func creature_sfx(creature_id: String, kind: String, fallback: String) -> void:
	if Assets.has("audio/sfx/%s_%s.mp3" % [creature_id, kind]):
		sfx("%s_%s" % [creature_id, kind])
	else:
		sfx(fallback)
