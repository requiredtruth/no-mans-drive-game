extends Node
## Sound playback helpers and ambience. Autoloaded as "Audio".

var _cache := {}
var _ambient := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for loop_name in ["insects_day_loop", "forest_bed_loop", "wind_loop", "rain_loop", "water_loop"]:
		var p := AudioStreamPlayer.new()
		p.stream = stream(loop_name, true)
		p.bus = "Ambience"
		p.volume_db = -80.0
		add_child(p)
		_ambient[loop_name] = p

func stream(sound: String, loop := false) -> AudioStream:
	var key := sound + ("_L" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/audio/%s.ogg" % sound
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if loop and s is AudioStreamOggVorbis:
		s = s.duplicate()
		(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s

func play(sound: String, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	var s := stream(sound)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.bus = bus
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	if Game.world == null:
		play(sound, volume_db, pitch)
		return
	var s := stream(sound)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.bus = bus
	p.max_distance = 200.0
	p.unit_size = 8.0
	Game.world.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

func looping_3d(sound: String, parent: Node3D, volume_db := 0.0, bus := "SFX") -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound, true)
	p.volume_db = volume_db
	p.bus = bus
	p.unit_size = 6.0
	p.max_distance = 60.0
	parent.add_child(p)
	if p.is_inside_tree():
		p.play()
	else:
		p.autoplay = true
	return p

## Fade ambience loops toward target linear volumes (0..1).
func set_ambience(targets: Dictionary, delta: float) -> void:
	for k in _ambient:
		var p: AudioStreamPlayer = _ambient[k]
		var target: float = targets.get(k, 0.0)
		var cur := db_to_linear(p.volume_db)
		cur = move_toward(cur, target, delta * 0.4)
		p.volume_db = linear_to_db(max(cur, 0.0001))
		if cur > 0.001 and not p.playing:
			p.play()
		elif cur <= 0.001 and p.playing:
			p.stop()

func stop_ambience() -> void:
	for k in _ambient:
		_ambient[k].stop()
		_ambient[k].volume_db = -80.0

# ------------------------------------------------------------------ ambient events
## [sound family, number of variants, weight]
const POOLS := {
	"forest_day": [["bird_chip", 4, 3.0], ["bird_warble", 4, 3.0], ["bird_trill", 3, 2.0], ["bird_whistle", 3, 1.5], ["woodpecker", 2, 1.0], ["dove", 2, 0.8], ["crow", 3, 0.7], ["leaves", 3, 1.2], ["gust", 4, 0.5]],
	"plains_day": [["bird_song", 2, 2.5], ["bird_chip", 4, 2.0], ["bird_whistle", 3, 1.5], ["dove", 2, 1.0], ["hawk", 2, 0.6], ["crow", 3, 0.8], ["gust", 4, 1.0]],
	"desert_day": [["hawk", 2, 1.5], ["gust", 4, 3.0], ["crow", 3, 0.6], ["bird_chip", 4, 0.5]],
	"tundra_day": [["crow", 3, 1.5], ["gust", 4, 3.0], ["bird_whistle", 3, 0.5]],
	"forest_night": [["owl", 3, 2.0], ["leaves", 3, 1.0], ["gust", 4, 0.6]],
	"plains_night": [["owl", 3, 0.8], ["gust", 4, 1.0]],
	"desert_night": [["coyote", 2, 1.5], ["gust", 4, 1.5]],
	"tundra_night": [["gust", 4, 2.5], ["owl", 3, 0.4]],
	"water": [["frog", 3, 3.0]],
	"storm": [["thunder", 2, 1.0], ["gust", 4, 2.0]],
}

var _recent: Array[String] = []

## Pick a varied ambient one-shot for the context; never repeats any of the last few.
func pick_event(pool_names: Array) -> String:
	var options := []
	var total := 0.0
	for pn in pool_names:
		for e in POOLS.get(pn, []):
			for v in range(int(e[1])):
				var nm := "%s_%d" % [e[0], v]
				if _recent.has(nm):
					continue
				var wgt := float(e[2]) / float(e[1])
				options.append([nm, wgt])
				total += wgt
	if options.is_empty():
		return ""
	var r := randf() * total
	var chosen: String = options[0][0]
	for o in options:
		r -= o[1]
		if r <= 0.0:
			chosen = o[0]
			break
	_recent.append(chosen)
	while _recent.size() > 6:
		_recent.pop_front()
	return chosen
