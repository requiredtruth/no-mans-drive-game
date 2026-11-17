extends Node3D
## The playable world: streaming terrain, environment, day/night, weather, wildlife and structures.

const Data = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
const Pois = preload("res://scripts/pois.gd")
const Structure = preload("res://scripts/structure.gd")
const Player = preload("res://scripts/player.gd")
const RV = preload("res://scripts/rv.gd")
const Animal = preload("res://scripts/animal.gd")
const HUD = preload("res://scripts/hud.gd")
const Touch = preload("res://scripts/touch.gd")
const Car = preload("res://scripts/car.gd")
const Trailer = preload("res://scripts/trailer.gd")

var gen: WorldGen
var hud: CanvasLayer
var touch: CanvasLayer
var player: CharacterBody3D
var rv: VehicleBody3D

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var terrain_mat: ShaderMaterial
var road_mat: ShaderMaterial
var water_mat: ShaderMaterial
var rain: CPUParticles3D
var snow: CPUParticles3D

var chunks := {} # Vector2i -> {"node": Node3D, "res": {key: [kind, body, mmi, idx]}}
var _pending := {} # Vector2i -> task id
var _results := {}
var _mutex := Mutex.new()
var radius := 2
var structures := {} # id -> node
var occupancy := {} # key -> id
var animals: Array = []
var remote_players := {}
var vehicle_nodes := {} # id -> car / trailer node

var _spawn_timer := 0.0
var _autosave := 0.0
var _hour := -1
var _weather_timer := 0.0
var _cloud := 0.3
var _overcast := 0.0
var _wet := 0.0
var _lightning := 0.0
var _fires: Array = []
var _fire_scan := 0.0
var _amb_scan := 0.0
var _near_water := 0.0
var _anim_id := 0
var _shelter_timer := 0.0
var _cam_sheltered := false

func start(loaded: Dictionary) -> void:
	Game.world = self
	gen = WorldGen.new(Game.seed_value)
	radius = int(Game.settings["view_distance"]) + 1
	_setup_environment()
	_setup_materials()
	hud = CanvasLayer.new()
	hud.set_script(HUD)
	add_child(hud)
	if Game.use_touch():
		touch = CanvasLayer.new()
		touch.set_script(Touch)
		add_child(touch)
	# Initial chunks (blocking) around the start point.
	var start_pos := Vector3(gen.road_x(0.0), 0.0, 0.0)
	if not Game.rv_state.is_empty() and Game.rv_state.has("xform"):
		start_pos = Game.v3(Game.rv_state["xform"][0])
	if not loaded.is_empty() and loaded.has("player"):
		start_pos = Game.v3(loaded["player"])
	var c := _chunk_of(start_pos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			_instantiate(gen.build_chunk(k.x, k.y, Game.removed.duplicate(), true))
	# RV
	rv = VehicleBody3D.new()
	rv.set_script(RV)
	add_child(rv)
	Game.rv = rv
	if Game.rv_state.is_empty() or not Game.rv_state.has("xform"):
		var z := 0.0
		var dir := gen.road_dir(z)
		rv.global_position = Vector3(gen.road_x(z) + 1.8, gen.road_h(z) + 0.6, z)
		rv.rotation.y = atan2(dir.x, dir.z)
		rv.apply_state({})
	# Player
	player = CharacterBody3D.new()
	player.set_script(Player)
	add_child(player)
	Game.player = player
	if loaded.has("player"):
		player.global_position = Game.v3(loaded["player"]) + Vector3(0, 0.3, 0)
		player.rotation.y = float(loaded.get("player_yaw", 0.0))
	else:
		player.global_position = rv.to_global(Vector3(RV.W * 0.5 + 1.6, 0.0, 1.0))
		player.global_position.y = gen.height(player.global_position.x, player.global_position.z) + 0.2
		player.rotation.y = rv.rotation.y - PI * 0.5
	player.make_current()
	for id in Game.structures:
		spawn_structure(id, Game.structures[id])
	for vid in Game.vehicles:
		var st: Dictionary = Game.vehicles[vid]
		var xf: Array = st.get("xform", [[0, 0, 0], [0, 0, 0]])
		spawn_vehicle(vid, str(st.get("kind", "pickup")), Game.v3(xf[0]), Game.v3(xf[1]), st)
	if not Game.vehicles.has("trl_start"):
		# parked just behind the van with its tongue next to the hitch: press E at the tongue
		var tp: Vector3 = rv.to_global(Vector3(0, 0, RV.REAR_Z - 0.55 - 1.2 - 2.7))
		tp.y = gen.height(tp.x, tp.z) + 0.6
		spawn_vehicle("trl_start", "flatbed", tp, Vector3(0, rv.rotation.y, 0), {})
	for r in Game.pending_items:
		var it = Game.spawn_item(str(r["id"]), int(r["n"]), Game.v3(r["pos"]), Vector3.ZERO, float(r.get("l", -1.0)))
		if it:
			it.global_rotation = Game.v3(r["rot"])
			if r.has("c"):
				it.contents = r["c"]
			if r.get("placed", false):
				it.settle()
	Game.pending_items = []
	# saves from before 1.3: the old backpack contents become piles by the RV door
	if not Game.legacy_inventory.is_empty():
		var at: Vector3 = rv.to_global(Vector3(RV.W * 0.5 + 1.4, 0.0, 0.0))
		at.y = gen.height(at.x, at.z) + 0.5
		for k in Game.legacy_inventory:
			if Game.worn.has(k) or not Game.Data.ITEMS.has(k):
				continue
			Game.drop_pile(k, int(Game.legacy_inventory[k]), at)
		Game.legacy_inventory = {}
	if not loaded.has("player"):
		_starter_lot()
		_start_vehicles()
		if TEST_DEPOT:
			test_depot(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(-RV.W * 0.5 - 7.5, 0, 2.0)))
	Game.playing = true
	apply_settings()
	if loaded.get("in_rv", false):
		player.call_deferred("enter_vehicle", rv, true)
	if not loaded.has("player"):
		hud.show_intro()

func _exit_tree() -> void:
	for k in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()
	if Game.world == self:
		Game.world = null
		Game.player = null
		Game.rv = null
		Game.playing = false

# ------------------------------------------------------------------ environment
func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var cloud := NoiseTexture2D.new()
	cloud.width = 512
	cloud.height = 512
	cloud.seamless = true
	cloud.generate_mipmaps = true
	var n := FastNoiseLite.new()
	n.frequency = 0.008
	n.fractal_octaves = 5
	n.seed = Game.seed_value
	cloud.noise = n
	sky_mat.set_shader_parameter("cloud_tex", cloud)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	# four cascades packed tight near the player: crisp, smooth shadows up close, soft far away
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	add_child(sun)
	rain = _make_precip(false)
	snow = _make_precip(true)

func _make_precip(is_snow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 900 if not is_snow else 700
	p.lifetime = 1.1 if not is_snow else 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 1, 22)
	p.direction = Vector3.DOWN
	p.spread = 4.0 if not is_snow else 25.0
	p.gravity = Vector3(1.5, -2.0, 0) if not is_snow else Vector3(0.4, -0.6, 0.2)
	p.initial_velocity_min = 18.0 if not is_snow else 1.2
	p.initial_velocity_max = 22.0 if not is_snow else 2.0
	p.local_coords = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_snow:
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 4
		sm.rings = 2
		m.albedo_color = Color(1, 1, 1, 0.9)
		sm.material = m
		p.mesh = sm
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.012, 0.55, 0.012)
		m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
		bm.material = m
		p.mesh = bm
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 60, 60))
	add_child(p)
	return p

func _setup_materials() -> void:
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	for pair in [["tex_grass", "grass"], ["tex_dirt", "dirt"], ["tex_sand", "sand"], ["tex_snow", "snow"], ["tex_rock", "rock"],
			["n_grass", "grass_n"], ["n_rock", "rock_n"], ["n_sand", "sand_n"]]:
		terrain_mat.set_shader_parameter(pair[0], Lib.tex(pair[1]))
	road_mat = ShaderMaterial.new()
	road_mat.shader = load("res://shaders/road.gdshader")
	road_mat.set_shader_parameter("tex_asphalt", Lib.tex("asphalt"))
	road_mat.set_shader_parameter("n_asphalt", Lib.tex("asphalt_n"))
	road_mat.set_shader_parameter("tex_dirt", Lib.tex("dirt"))
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("nmap", Lib.tex("water_n"))

func apply_settings() -> void:
	radius = int(Game.settings["view_distance"]) + 1
	sun.shadow_enabled = Game.settings["shadows"]
	if player:
		player.camera.fov = Game.settings["fov"]
		player.flashlight.shadow_enabled = Game.settings["shadows"]
	env.fog_density = 0.0025 if radius >= 3 else 0.0045
	for k in chunks:
		var g: Node = chunks[k]["node"].get_node_or_null("Grass")
		if g:
			g.visible = Game.settings["grass"]
	if touch and not Game.use_touch():
		touch.queue_free()
		touch = null
	elif touch == null and Game.use_touch() and hud:
		touch = CanvasLayer.new()
		touch.set_script(Touch)
		add_child(touch)

# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if not Game.playing:
		return
	_update_time(delta)
	_update_weather(delta)
	_stream_chunks()
	_spawn_animals(delta)
	_fire_scan -= delta
	if _fire_scan <= 0.0:
		_fire_scan = 1.0
		_fires = get_tree().get_nodes_in_group("structure").filter(func(s): return s.type == "campfire")
		_cook_tick(1.0)
	_ambience(delta)
	# keep physics bodies frozen until ground exists below them
	if rv and rv.is_authority():
		rv.freeze = not ground_ready(rv.global_position)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var cp := cam.global_position
		rain.global_position = cp + Vector3(0, 12, 0)
		snow.global_position = cp + Vector3(0, 10, 0)
	_autosave += delta
	if _autosave > 180.0 and not Net.is_client() and not player.dead:
		_autosave = 0.0
		Game.save_game()

func _update_time(delta: float) -> void:
	Game.time_of_day += delta * 24.0 / Game.DAY_LENGTH
	if Game.time_of_day >= 24.0:
		Game.time_of_day -= 24.0
		Game.day += 1
	var h := int(Game.time_of_day)
	if h != _hour:
		if _hour != -1:
			for s in get_tree().get_nodes_in_group("structure"):
				s.game_hour()
		_hour = h
	var a := (Game.time_of_day - 6.0) / 12.0 * PI
	var d := Vector3(cos(a) * 0.9, sin(a), 0.4).normalized()
	var day := smoothstep(-0.12, 0.25, d.y)
	var sunset := 1.0 - smoothstep(0.0, 0.35, absf(d.y))
	var light_dir := -d if d.y > -0.05 else d
	sun.basis = Basis.looking_at(light_dir, Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.FORWARD)
	var storm := _overcast
	sun.light_energy = lerpf(0.09, 1.35, day) * (1.0 - storm * 0.6)
	sun.light_color = Color(0.6, 0.7, 1.0).lerp(Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.35), sunset), day)
	sky_mat.set_shader_parameter("sun_dir", d)
	sky_mat.set_shader_parameter("daylight", day)
	sky_mat.set_shader_parameter("sunset", sunset * smoothstep(-0.2, 0.05, d.y))
	sky_mat.set_shader_parameter("cloud_cover", _cloud)
	sky_mat.set_shader_parameter("overcast", _overcast)
	var amb := Color(0.05, 0.06, 0.11).lerp(Color(0.55, 0.6, 0.68), day)
	amb = amb.lerp(Color(0.5, 0.5, 0.52) * day + Color(0.04, 0.04, 0.05), storm * 0.5)
	if _lightning > 0.0:
		_lightning -= delta
		amb = Color(0.9, 0.9, 1.0)
	env.ambient_light_color = amb
	env.ambient_light_energy = lerpf(0.5, 0.75, day)
	var fog := Color(0.06, 0.07, 0.11).lerp(Color(0.7, 0.78, 0.86), day).lerp(Color(0.95, 0.65, 0.45), sunset * 0.5 * day)
	fog = fog.lerp(Color(0.45, 0.47, 0.5) * maxf(day, 0.1), storm)
	env.fog_light_color = fog
	water_mat.set_shader_parameter("daylight", maxf(day, 0.08))

func _update_weather(delta: float) -> void:
	_weather_timer -= delta
	if _weather_timer <= 0.0 and not Net.is_client():
		_weather_timer = randf_range(150.0, 420.0)
		var b: Vector4 = gen.biome_weights(player.global_position.x, player.global_position.z)
		var r := randf()
		var rain_chance := 0.22 * (1.0 - b.x * 0.85)
		if r < rain_chance:
			Game.weather = "rain"
		elif r < rain_chance + 0.28:
			Game.weather = "cloudy"
		else:
			Game.weather = "clear"
		Net.sync_weather()
	var raining := Game.weather == "rain"
	var target_cloud := 0.25 if Game.weather == "clear" else (0.6 if Game.weather == "cloudy" else 0.85)
	_cloud = move_toward(_cloud, target_cloud, delta * 0.02)
	_overcast = move_toward(_overcast, 0.85 if raining else (0.25 if Game.weather == "cloudy" else 0.0), delta * 0.03)
	_wet = move_toward(_wet, 1.0 if raining else 0.0, delta * (0.05 if raining else 0.01))
	var tundra: bool = gen.biome_weights(player.global_position.x, player.global_position.z).w > 0.5
	_shelter_timer -= delta
	if _shelter_timer <= 0.0:
		_shelter_timer = 0.3
		var cam := get_viewport().get_camera_3d()
		_cam_sheltered = cam != null and (player.driving or (rv and rv.is_inside(cam.global_position)) or is_sheltered(cam.global_position - Vector3(0, 1.6, 0)))
	rain.emitting = raining and _overcast > 0.5 and not tundra and not _cam_sheltered
	snow.emitting = raining and _overcast > 0.5 and tundra and not _cam_sheltered

	terrain_mat.set_shader_parameter("wetness", _wet * (0.0 if tundra else 1.0))
	terrain_mat.set_shader_parameter("snow_cover", 0.0)
	road_mat.set_shader_parameter("wetness", _wet)
	env.fog_density = (0.0025 if radius >= 3 else 0.0045) + _overcast * 0.006 + (0.01 if snow.emitting else 0.0)
	if raining and _overcast > 0.7 and randf() < delta * 0.02:
		_lightning = 0.12
		get_tree().create_timer(randf_range(0.8, 3.0)).timeout.connect(func() -> void: Audio.play("gunshot", -6.0, 0.25, "Ambience"))

func _ambience(delta: float) -> void:
	_amb_scan -= delta
	if _amb_scan <= 0.0:
		_amb_scan = 1.0
		_near_water = 0.0
		var p := player.global_position
		for k in range(8):
			var a := TAU * k / 8.0
			if gen.is_water(p.x + cos(a) * 20.0, p.z + sin(a) * 20.0, 0.5):
				_near_water = 1.0
				break
	var p2 := player.global_position
	var b: Vector4 = gen.biome_weights(p2.x, p2.z)
	var day := Game.time_of_day > 5.5 and Game.time_of_day < 20.0
	var raining := Game.weather == "rain"
	var inside: bool = rv and (player.driving or rv.is_inside(p2))
	var muffle := 0.45 if inside else 1.0
	_ambient_events(delta, b, day, raining, inside)
	var midday := Game.time_of_day > 10.0 and Game.time_of_day < 18.0
	Audio.set_ambience({
		"forest_bed_loop": 0.22 * (b.z + b.y * 0.5) * muffle,
		"insects_day_loop": (0.16 * (b.x + b.y) if day and midday and not raining else 0.0) * muffle,
		"crickets_loop": (0.28 * (1.0 - b.w) if not day and not raining else 0.0) * muffle,
		"wind_loop": (0.12 + 0.45 * b.w + 0.25 * b.x + _overcast * 0.2) * muffle,
		"rain_loop": (0.8 * _overcast if raining and b.w < 0.5 else 0.0) * (0.7 if inside else 1.0),
		"water_loop": 0.35 * _near_water * muffle,
	}, delta)

var _amb_event_timer := 3.0

## Random, biome- and time-aware one-shot calls placed around the player (no looping birdsong).
func _ambient_events(delta: float, b: Vector4, day: bool, raining: bool, inside: bool) -> void:
	_amb_event_timer -= delta
	if _amb_event_timer > 0.0:
		return
	var chorus := (Game.time_of_day > 5.0 and Game.time_of_day < 8.5) or (Game.time_of_day > 18.0 and Game.time_of_day < 20.5)
	var rate := 2.2 if chorus else 1.0
	if raining:
		rate *= 0.35
	_amb_event_timer = randf_range(2.0, 9.0) / rate
	var names := ["desert", "plains", "forest", "tundra"]
	var best := 0
	for i in range(4):
		if b[i] > b[best]:
			best = i
	var pools := [names[best] + ("_day" if day else "_night")]
	if _near_water > 0.5 and (not day or randf() < 0.3):
		pools.append("water")
	if raining and _overcast > 0.7:
		pools.append("storm")
	var ev := Audio.pick_event(pools)
	if ev == "":
		return
	var ang := randf() * TAU
	var dist := 150.0 if ev.begins_with("thunder") else randf_range(18.0, 70.0)
	var p := player.global_position + Vector3(cos(ang) * dist, randf_range(2.0, 12.0), sin(ang) * dist)
	var vol := randf_range(-8.0, 2.0) - (8.0 if inside else 0.0)
	var pitch := randf_range(0.9, 1.12)
	Audio.play_at(ev, p, vol, pitch, "Ambience")
	# sometimes another animal of the same kind answers from elsewhere
	var answers := ev.begins_with("bird") or ev.begins_with("owl") or ev.begins_with("crow") or ev.begins_with("frog")
	if answers and randf() < 0.35:
		var a2 := ang + randf_range(1.5, 4.5)
		var p2 := player.global_position + Vector3(cos(a2) * dist * 1.2, 4.0, sin(a2) * dist * 1.2)
		get_tree().create_timer(randf_range(1.2, 3.5)).timeout.connect(func() -> void:
			Audio.play_at(ev, p2, vol - 4.0, pitch * randf_range(0.93, 1.07), "Ambience"))

# ------------------------------------------------------------------ chunks
func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / WorldGen.CHUNK)), int(floor(p.z / WorldGen.CHUNK)))

func ground_ready(p: Vector3) -> bool:
	return chunks.has(_chunk_of(p))

func _gen_task(cx: int, cz: int, removed: Dictionary) -> void:
	var d := gen.build_chunk(cx, cz, removed, true)
	_mutex.lock()
	_results[Vector2i(cx, cz)] = d
	_mutex.unlock()

func _stream_chunks() -> void:
	var center := _chunk_of(player.global_position)
	# collect finished
	_mutex.lock()
	var done := _results.keys()
	_mutex.unlock()
	var made := 0
	for k in done:
		if _pending.has(k) and WorkerThreadPool.is_task_completed(_pending[k]):
			WorkerThreadPool.wait_for_task_completion(_pending[k])
			_pending.erase(k)
			_mutex.lock()
			var d: Dictionary = _results[k]
			_results.erase(k)
			_mutex.unlock()
			if maxi(absi(k.x - center.x), absi(k.y - center.y)) <= radius + 1 and not chunks.has(k):
				_instantiate(d)
				made += 1
				if made >= 1:
					break
	# request missing
	var wanted: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := Vector2i(center.x + dx, center.y + dz)
			if not chunks.has(k) and not _pending.has(k):
				wanted.append(k)
	wanted.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
	var removed_copy := {}
	var copied := false
	for k in wanted:
		if _pending.size() >= 3:
			break
		if not copied:
			removed_copy = Game.removed.duplicate()
			copied = true
		_pending[k] = WorkerThreadPool.add_task(_gen_task.bind(k.x, k.y, removed_copy))
	# unload far
	for k in chunks.keys():
		if maxi(absi(k.x - center.x), absi(k.y - center.y)) > radius + 1:
			chunks[k]["node"].queue_free()
			chunks.erase(k)

func _arrays_mesh(arrays: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _instantiate(d: Dictionary) -> void:
	var key := Vector2i(d["cx"], d["cz"])
	if chunks.has(key):
		return
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	root.position = Vector3(key.x * WorldGen.CHUNK, 0, key.y * WorldGen.CHUNK)
	add_child(root)
	var info := {"node": root, "res": {}}
	chunks[key] = info
	var tm := MeshInstance3D.new()
	tm.mesh = _arrays_mesh(d["terrain"])
	tm.material_override = terrain_mat
	root.add_child(tm)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = WorldGen.COL + 1
	hm.map_depth = WorldGen.COL + 1
	hm.map_data = d["heights"]
	cs.shape = hm
	cs.position = Vector3(WorldGen.CHUNK * 0.5, 0, WorldGen.CHUNK * 0.5)
	body.add_child(cs)
	body.set_meta("terrain", true)
	root.add_child(body)
	if d.has("road"):
		var rm := MeshInstance3D.new()
		rm.mesh = _arrays_mesh(d["road"])
		rm.material_override = road_mat
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rm)
	if d.has("water"):
		var wm := MeshInstance3D.new()
		wm.mesh = _arrays_mesh(d["water"])
		wm.material_override = water_mat
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wm)
	# trees grouped into multimeshes
	var by_kind := {}
	for f in d["features"]:
		if f["t"] == "tree":
			if not by_kind.has(f["kind"]):
				by_kind[f["kind"]] = []
			by_kind[f["kind"]].append(f)
	for kind in by_kind:
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Lib.mesh(kind)
		mm.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
		for i in range(list.size()):
			var f: Dictionary = list[i]
			var s: float = f["scale"]
			var lp: Vector3 = f["pos"] - root.position
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, f["rot"]).scaled(Vector3.ONE * s), lp))
			var t: float = f["tint"]
			mm.set_instance_color(i, Color(t * 0.95, t, t * 0.88))
			var tb := StaticBody3D.new()
			var tcs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = (0.3 if kind != "cactus" else 0.4) * s
			cyl.height = 6.0 * s
			tcs.shape = cyl
			tcs.position.y = 3.0 * s
			tb.add_child(tcs)
			tb.position = lp
			tb.set_meta("res_kind", "tree")
			tb.set_meta("res_key", f["key"])
			tb.set_meta("tree_kind", kind)
			tb.set_meta("hits", 0)
			root.add_child(tb)
			info["res"][f["key"]] = [tb, mmi, i]
	for f in d["features"]:
		var lp: Vector3 = f["pos"] - root.position
		match f["t"]:
			"rock":
				var s: float = f["scale"]
				var rb := StaticBody3D.new()
				rb.position = lp
				rb.rotation.y = f["rot"]
				var mi := MeshInstance3D.new()
				mi.mesh = Lib.mesh("rock%d" % int(f["variant"]))
				mi.scale = Vector3.ONE * s
				rb.add_child(mi)
				var rcs := CollisionShape3D.new()
				var sph := SphereShape3D.new()
				sph.radius = 0.85 * s
				rcs.shape = sph
				rcs.position.y = 0.15 * s
				rb.add_child(rcs)
				rb.set_meta("res_kind", "rock")
				rb.set_meta("res_key", f["key"])
				rb.set_meta("hits", 0)
				root.add_child(rb)
				info["res"][f["key"]] = [rb, null, -1]
			"bush":
				var bkey: String = f["key"]
				if Game.removed.has(bkey) and Game.day - int(Game.removed[bkey]) < 2:
					continue
				var bb := StaticBody3D.new()
				bb.collision_layer = 2
				bb.collision_mask = 0
				bb.position = lp
				bb.rotation.y = f["rot"]
				var bm := MeshInstance3D.new()
				bm.mesh = Lib.mesh("bush_" + str(f["kind"]))
				bm.scale = Vector3.ONE * float(f["scale"])
				bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bb.add_child(bm)
				var bcs := CollisionShape3D.new()
				var bs := SphereShape3D.new()
				bs.radius = 0.6
				bcs.shape = bs
				bcs.position.y = 0.4
				bb.add_child(bcs)
				bb.set_meta("res_kind", "bush")
				bb.set_meta("bush_kind", f["kind"])
				bb.set_meta("res_key", bkey)
				root.add_child(bb)
				info["res"][bkey] = [bb, null, -1]
			"pickup":
				var pk: String = f["key"]
				var pb := StaticBody3D.new()
				pb.collision_layer = 2
				pb.collision_mask = 0
				pb.position = lp
				pb.rotation.y = f["rot"]
				var model := Items.instance(str(f["item"]))
				if f["item"] == "wood":
					model.scale = Vector3(0.6, 0.6, 1.4)
				pb.add_child(model)
				var pcs := CollisionShape3D.new()
				var psh := SphereShape3D.new()
				psh.radius = 0.35
				pcs.shape = psh
				pcs.position.y = 0.1
				pb.add_child(pcs)
				pb.set_meta("res_kind", "pickup")
				pb.set_meta("res_key", pk)
				pb.set_meta("item", f["item"])
				root.add_child(pb)
				info["res"][pk] = [pb, null, -1]
			"scrap":
				var pile := Pois.loot(root, lp, Vector3(1.4, 0.5, 1.0), Lib.mat("rust"), f["key"], "Scrap pile", "scrap_pile")
				pile.rotation.y = f["rot"]
				Lib.box(pile, Vector3(0.3, 0.6, 0.1), Vector3(0.8, 0.25, 0.5), Lib.mat("rust", Color(0.7, 0.7, 0.8)), false, Vector3(0.3, 0.5, 0.2))
	# grass
	if d.has("grass") and d["grass"].size() > 0:
		var gp: PackedVector3Array = d["grass"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Lib.mesh("grass")
		mm.instance_count = gp.size()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		for i in range(gp.size()):
			var s := rng.randf_range(0.6, 1.3)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s)), gp[i] - root.position))
			var t := rng.randf_range(0.8, 1.1)
			mm.set_instance_color(i, Color(t, t, t * 0.9))
		var gmi := MultiMeshInstance3D.new()
		gmi.name = "Grass"
		gmi.multimesh = mm
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gmi.visibility_range_end = 95.0
		gmi.visibility_range_end_margin = 10.0
		gmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		gmi.visible = Game.settings["grass"]
		root.add_child(gmi)
		info["grass"] = gp
		info["grass_mm"] = mm
		for id in structures:
			var s: Node3D = structures[id]
			if is_instance_valid(s):
				_clear_grass_at(s.global_position, s.type, info)
	# roadside location
	var poi := gen.poi_for_row(key.y)
	if not poi.is_empty() and _chunk_of(poi["pos"]) == key:
		Pois.build(root, poi)
		_poi_vehicles(poi)
	# road-trip destinations: a sign and a supply crate at the roadside
	for i in range(Data.OBJECTIVES.size()):
		var oz := -float(Data.OBJECTIVES[i][1])
		var dp := Vector3(gen.road_x(oz), gen.road_h(oz), oz)
		if _chunk_of(dp) == key:
			Pois.destination(root, dp, gen.road_dir(oz), i, gen)

# ------------------------------------------------------------------ resources
func _find_res(key: String) -> Array:
	for k in chunks:
		var r: Dictionary = chunks[k]["res"]
		if r.has(key):
			return r[key]
	return []

func on_removed(key: String) -> void:
	var r := _find_res(key)
	if r.is_empty():
		return
	var body: Node3D = r[0]
	if r[1] != null:
		var mmi: MultiMeshInstance3D = r[1]
		mmi.multimesh.set_instance_transform(r[2], Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -50, 0)))
	if is_instance_valid(body):
		body.queue_free()

## Harvested materials fall to the ground as physical items you pick up.
func _drop(body: Node3D, id: String, n: int) -> void:
	var p: Vector3 = body.global_position
	if Game.player:
		var toward: Vector3 = (Game.player.global_position - p) * Vector3(1, 0, 1)
		if toward.length() > 0.1:
			p += toward.normalized() * minf(toward.length() * 0.5, 1.2)
	p.y = maxf(p.y, gen.height(p.x, p.z)) + 0.6
	Game.drop_pile(id, n, p)

func hit_resource(body: Node3D, at: Vector3, power := 1.0) -> void:
	var hits: float = float(body.get_meta("hits")) + power
	body.set_meta("hits", hits)
	impact_puff(at, body.get_meta("res_kind") == "tree")
	var key: String = body.get_meta("res_key")
	if body.get_meta("res_kind") == "tree":
		var kind: String = body.get_meta("tree_kind")
		if hits >= (3 if kind in ["dead", "cactus"] else 4):
			if kind == "cactus":
				_drop(body, "fiber", randi_range(2, 4))
				_drop(body, "water_dirty", 1)
			else:
				_drop(body, "wood", randi_range(4, 6))
				if randf() < 0.5:
					_drop(body, "fiber", randi_range(1, 2))
				if randf() < 0.6:
					_drop(body, "stick", randi_range(1, 3))
				if kind == "dead" or randf() < 0.2:
					_drop(body, "seasoned_hardwood", randi_range(1, 2))
				if kind == "palm" or randf() < 0.06:
					_drop(body, "raw_rubber", 1)
			Audio.play_at("chop", at, 4.0, 0.6)
			Net.mark_removed(key, true)
	else:
		if hits >= 4:
			_drop(body, "stone", randi_range(3, 5))
			if randf() < 0.25:
				_drop(body, "scrap", 1)
			# ore seams: what you find depends on the land
			var bw: Vector4 = gen.biome_weights(at.x, at.z)
			var roll := randf()
			if roll < 0.22:
				_drop(body, "copper_ore", randi_range(1, 2))
			elif roll < 0.4:
				_drop(body, "lead_ore", randi_range(1, 2))
			elif roll < 0.4 + 0.25 * (bw.x + 0.3):
				_drop(body, "sulphur_ore", randi_range(1, 2))
			elif roll < 0.75:
				_drop(body, "saltpeter", 1)
			if randf() < 0.05:
				_drop(body, "obsidian_chunk", 1)
			if randf() < 0.3:
				_drop(body, "rock", 1)
			Net.mark_removed(key, true)
		elif randf() < 0.35:
			_drop(body, "stone", 1)

func harvest_bush(body: Node3D) -> void:
	var kind: String = body.get_meta("bush_kind")
	match kind:
		"berry":
			var bh := hash(body.get_meta("res_key"))
			var berry: String = ["berries", "berries", "red_berry", "yellow_berry"][absi(bh) % 4]
			_drop(body, berry, randi_range(2, 4))
			if randf() < 0.15:
				_drop(body, "seeds_tomato", 1)
			if randf() < 0.02:
				_drop(body, "golden_mystic_berry", 1)
		"mushroom":
			_drop(body, "mushroom", randi_range(1, 3))
		_:
			_drop(body, "fiber", randi_range(2, 3))
			if randf() < 0.35:
				_drop(body, "wood", 1)
			if randf() < 0.08:
				_drop(body, ["seeds_potato", "carrot_seeds", "corn_seeds"][randi() % 3], 1)
	Audio.play("pickup", -4.0)
	Net.mark_removed(body.get_meta("res_key"), Game.day)

func impact_puff(at: Vector3, wood := false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.5
	p.explosiveness = 0.95
	p.spread = 70.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var bm := BoxMesh.new()
	bm.material = Lib.color_mat(Color(0.55, 0.42, 0.28) if wood else Color(0.6, 0.58, 0.55))
	p.mesh = bm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# ------------------------------------------------------------------ survival helpers
func temperature_at(p: Vector3) -> float:
	var w := gen.biome_weights(p.x, p.z)
	var day_t := w.x * 35.0 + w.y * 23.0 + w.z * 19.0 + w.w * -3.0
	var night_t := w.x * 5.0 + w.y * 9.0 + w.z * 7.0 + w.w * -17.0
	var k := 0.5 + 0.5 * sin((Game.time_of_day - 9.0) / 24.0 * TAU)
	var t := lerpf(night_t, day_t, k)
	if Game.weather == "rain":
		t -= 5.0
	t -= maxf(p.y - 12.0, 0.0) * 0.05
	return t

# ------------------------------------------------------------------ cooking on heat
## Food and water set on a burning campfire or a lit stove cook by themselves.
func _cook_tick(dt: float) -> void:
	var spots := []
	for f in _fires:
		if is_instance_valid(f):
			for hp in f.heat_spots():
				spots.append([hp, 0.42])
	for f in get_tree().get_nodes_in_group("placeable"):
		if is_instance_valid(f) and f.get("type") == "campfire" and f.has_meta("host"):
			for hp in f.heat_spots():
				spots.append([hp, 0.42])
	if rv:
		for hp in rv.heat_spots():
			spots.append([hp, 0.15])
	if spots.is_empty():
		return
	var items := get_tree().get_nodes_in_group("world_item")
	for sp in spots:
		var here := []
		for it in items:
			if not is_instance_valid(it) or it.is_queued_for_deletion():
				continue
			var d: Vector3 = it.global_position - sp[0]
			if Vector2(d.x, d.z).length() < sp[1] and d.y > -0.15 and d.y < 0.45:
				here.append(it)
		if here.is_empty():
			continue
		# a skillet, pot or percolator on the heat cooks everything with it faster
		var boost := 1.0
		for it in here:
			boost = maxf(boost, float(Data.ITEMS.get(it.id, {}).get("cook_boost", 1.0)))
		for it in here:
			it.set_meta("cook", float(it.get_meta("cook", 0.0)) + dt * boost)
		_cook_here(here)

func _cook_here(here: Array) -> void:
	for r in Data.COOKING:
		var used := []
		var ok := true
		for k in r["cost"]:
			var found = null
			for it in here:
				if it.id == k and not used.has(it) and int(it.amount) >= int(r["cost"][k]) and float(it.get_meta("cook", 0.0)) >= Data.COOK_TIME:
					found = it
					break
			if found == null:
				ok = false
				break
			used.append(found)
		if not ok:
			continue
		var first: Node = used[0]
		var n := 1
		if r["cost"].size() == 1:
			n = int(first.amount) / int(r["cost"][first.id]) * int(r["n"])
		var xf: Transform3D = first.global_transform
		xf.origin.y += Items.display_bounds(first.id).position.y - Items.display_bounds(r["out"]).position.y
		var par: Node = first.get_parent()
		var host: Node = par.get_parent() if par and par.name == "Cargo" else null
		var k0 := 0
		for it in used:
			var need := int(r["cost"][it.id]) * (n if r["cost"].size() == 1 else 1)
			it.amount -= need
			if it.amount <= 0:
				it.queue_free()
			else:
				it.set_meta("cook", 0.0)
				it.refresh_label()
			k0 += 1
		Game.place_item(r["out"], n, xf, host)
		Audio.play_at("pickup", xf.origin, -6.0, 1.4)
		if player and player.global_position.distance_to(xf.origin) < 15.0:
			Game.notify("%s is ready" % Data.item_name(r["out"]))
		return

## A new game: the stripped van sits on a rough lot with the parts to get it running lying
## around it, a workbench, and a few supplies. Everything else has to be found on the road.
func _starter_lot() -> void:
	var lot := [
		["engine_block", 1, Vector3(4.0, 0, 3.8), 0.4],
		["car_battery", 1, Vector3(3.1, 0, 2.6), 1.2],
		["tire", 1, Vector3(5.6, 0, 1.6), 0.0],
		["tire", 1, Vector3(6.4, 0, 0.9), 0.7],
		["tire", 1, Vector3(5.5, 0, 0.2), 1.9],
		["tire", 1, Vector3(6.3, 0, -0.5), 2.6],
		["tire", 1, Vector3(7.2, 0, 0.5), 1.2], # a spare, in case one gets damaged
		["steering_wheel", 1, Vector3(5.6, 0, 1.6), 0.3, "tire"], # lying on top of the first tire
		["car_seat", 1, Vector3(4.3, 0, 1.0), -1.4],
		["van_door", 1, Vector3(2.8, 0, -1.2), PI * 0.5],
		["toolkit", 1, Vector3(3.4, 0, -0.4), 0.9],
		["fuel_can", 1, Vector3(2.4, 0, -3.1), 0.2],
		["headlight", 1, Vector3(3.9, 0, 2.0), 0.5],
		["scrap", 4, Vector3(5.6, 0, -2.0), 0.0],
		["bolts", 6, Vector3(5.2, 0, -3.6), 0.4],
		["wood", 3, Vector3(6.2, 0, -3.0), 1.1],
		["water_clean", 2, Vector3(2.6, 0, -2.2), 0.0],
		["canned_food", 1, Vector3(2.9, 0, -2.4), 0.0],
		["bandage", 1, Vector3(2.5, 0, -2.6), 0.6],
		["seeds_tomato", 1, Vector3(2.9, 0, -2.75), 0.3],
		["rope", 1, Vector3(3.3, 0, -2.6), 0.0],
	]
	for e in lot:
		var gp: Vector3 = rv.to_global(e[2])
		var bb: AABB = Items.display_bounds(e[0])
		gp.y = gen.height(gp.x, gp.z) - bb.position.y + 0.01
		if e.size() > 4:
			gp.y += Items.display_bounds(e[4]).size.y
		Game.place_item(e[0], e[1], Transform3D(Basis(Vector3.UP, rv.rotation.y + e[3]), gp))
	var bp: Vector3 = rv.to_global(Vector3(4.9, 0, -2.9))
	bp.y = gen.height(bp.x, bp.z)
	Net.place_structure(Game.new_struct_id(), {"type": "workbench", "pos": Game.arr(bp), "rot": rv.rotation.y - PI * 0.5, "data": {}})

## A car and two trucks parked up the road from the van, ready to drive.
func _start_vehicles() -> void:
	var good := {"fuel": 40.0, "battery": 90.0, "parts": {"engine": 85.0, "tires": 85.0, "battery": 90.0, "body": 80.0}}
	var specs := [["start_car", "sedan", 9.5], ["start_truck", "pickup", 16.5], ["start_boxtruck", "box_truck", 25.0]]
	for e in specs:
		if Game.vehicles.has(e[0]):
			continue
		var p: Vector3 = rv.to_global(Vector3(0.2, 0, RV.FRONT_Z + float(e[2])))
		p.y = gen.height(p.x, p.z) + 1.0
		spawn_vehicle(e[0], e[1], p, Vector3(0, rv.rotation.y, 0), good.duplicate(true))

## For testing: while the game is in development a new game starts with a pile of every item in
## the game laid out in rows next to the lot (also on the cheats menu).
const TEST_DEPOT := true
func test_depot(xf: Transform3D) -> void:
	var groups := {}
	for id in Data.ITEMS:
		var k: String = Data.ITEMS[id]["kind"]
		var g := "big" if k in ["placeable", "module"] else k
		if not groups.has(g):
			groups[g] = []
		groups[g].append(id)
	var order := ["tool", "ammo", "wear", "food", "medical", "purify", "material", "container", "fuel", "paint", "seed", "junk", "decor", "big"]
	for g in groups:
		if not order.has(g):
			order.append(g)
	var row_z := 0.0
	var row_w := 16.0
	for g in order:
		if not groups.has(g):
			continue
		var x := 0.0
		var depth := 0.0
		for id in groups[g]:
			var bb: AABB = Items.display_bounds(id)
			var wdt := maxf(bb.size.x, 0.35) + 0.3
			if x + wdt > row_w:
				x = 0.0
				row_z -= depth + 0.35
				depth = 0.0
			var lp := Vector3(-x - wdt * 0.5, 0, row_z - maxf(bb.size.z, 0.35) * 0.5)
			var gp: Vector3 = xf * lp
			gp.y = gen.height(gp.x, gp.z) - bb.position.y + 0.02
			var n := Data.stack(id) * (3 if Data.stack(id) > 1 else 1)
			Game.place_item(id, mini(n, 60), Transform3D(xf.basis, gp))
			x += wdt
			depth = maxf(depth, maxf(bb.size.z, 0.35))
		row_z -= depth + 0.9

func fire_heat(p: Vector3) -> float:
	var best := 0.0
	for f in _fires:
		if not is_instance_valid(f):
			continue
		var r: float = f.warmth_radius()
		if r > 0.0:
			var d: float = f.global_position.distance_to(p)
			if d < r:
				best = maxf(best, 28.0 * (1.0 - d / r))
	return best

func is_sheltered(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.7, 0), p + Vector3(0, 30, 0), 1 | 16)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	return not (hit["collider"] as Node).has_meta("res_kind")

func sleep(at: Vector3) -> void:
	for a in animals:
		if is_instance_valid(a) and a.state != "dead" and float(a.spec["aggro"]) > 0.0 and a.global_position.distance_to(at) < 30.0:
			Game.notify("You can't sleep with predators nearby!")
			return
	var t := Game.time_of_day
	var hours := 0.0
	if t >= 19.0:
		hours = 24.0 - t + 7.0
	elif t < 7.0:
		hours = 7.0 - t
	else:
		hours = 3.0
	hud.fade_sleep(hours)
	Game.time_of_day += hours
	while Game.time_of_day >= 24.0:
		Game.time_of_day -= 24.0
		Game.day += 1
	var st := Game.stats
	st["energy"] = minf(st["energy"] + hours * 12.0, 100.0)
	st["food"] = maxf(st["food"] - hours * 2.0, 0.0)
	st["water"] = maxf(st["water"] - hours * 2.5, 0.0)
	st["health"] = minf(st["health"] + hours * 3.0, 100.0)
	st["warmth"] = 100.0
	Game.spawn_point = at
	for i in range(int(hours)):
		for s in get_tree().get_nodes_in_group("structure"):
			s.game_hour()
	Net.sync_time()
	if not Net.is_client():
		Game.save_game()

# ------------------------------------------------------------------ wildlife
func _spawn_animals(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = 2.0
	var p := player.global_position
	animals = animals.filter(func(a): return is_instance_valid(a))
	for a in animals:
		if a.global_position.distance_to(p) > 180.0:
			a.queue_free()
	var cap := 9 if OS.has_feature("mobile") else 14
	if animals.size() >= cap:
		return
	var ang := randf() * TAU
	var dist := randf_range(45.0, 110.0)
	var sp := p + Vector3(cos(ang), 0, sin(ang)) * dist
	if not ground_ready(sp) or gen.is_water(sp.x, sp.z, 0.0):
		return
	sp.y = gen.height(sp.x, sp.z) + 0.3
	var w := gen.biome_weights(sp.x, sp.z)
	var night := Game.time_of_day < 6.0 or Game.time_of_day > 20.0
	var table := {
		"rabbit": w.x * 0.5 + w.y * 0.3 + w.z * 0.08 + w.w * 0.25,
		"wolf": (w.x * 0.15 + w.z * 0.14 + w.w * 0.35) * (1.6 if night else 0.6),
		"fox": w.x * 0.2 + w.y * 0.15 + w.z * 0.1,
		"turkey": w.x * 0.05 + w.y * 0.2 + w.z * 0.1,
		"deer": w.y * 0.35 + w.z * 0.3 + w.w * 0.3,
		"boar": w.z * 0.2,
		"bear": (w.z * 0.06 + w.w * 0.1),
	}
	var total := 0.0
	for k in table:
		total += table[k]
	var r := randf() * total
	var species := "deer"
	for k in table:
		r -= table[k]
		if r <= 0.0:
			species = k
			break
	# Wolves and bears live deep in the woods: never right next to you, never on open ground or
	# by the road, and not around the starting lot on the first day.
	if float(Data.ANIMALS[species]["aggro"]) > 0.0:
		if dist < 90.0 or not _is_woods(sp):
			return
		var home := Vector3(gen.road_x(0.0), 0.0, 0.0)
		if Game.day <= 1 and Vector2(sp.x - home.x, sp.z - home.z).length() < 350.0:
			return
	var n := randi_range(2, 3) if species == "wolf" else (randi_range(1, 3) if species in ["deer", "turkey"] else 1)
	for i in range(n):
		var off := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		spawn_animal(species, sp + off)

## Forest well away from the road and any roadside buildings.
func _is_woods(p: Vector3) -> bool:
	var w := gen.biome_weights(p.x, p.z)
	if w.z + w.w < 0.45:
		return false
	if absf(p.x - gen.road_x(p.z)) < 35.0 or gen._near_poi(p.x, p.z, 25.0):
		return false
	var trees := 0
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 14.0
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 2, 0))
	q.collision_mask = 1
	for r in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c: Object = r["collider"]
		if c and (c as Node).has_meta("res_kind") and (c as Node).get_meta("res_kind") == "tree":
			trees += 1
	return trees >= 3

func spawn_animal(species: String, pos: Vector3) -> Node:
	var a := CharacterBody3D.new()
	a.set_script(Animal)
	a.setup(species, pos)
	_anim_id += 1
	a.net_id = "%d_%d" % [Net.my_id(), _anim_id]
	add_child(a)
	animals.append(a)
	return a

func alert_animals(at: Vector3, r: float) -> void:
	for a in animals:
		if is_instance_valid(a) and a.global_position.distance_to(at) < r:
			a.alert(at)

# ------------------------------------------------------------------ structures
func _occ_key(t: String, pos: Vector3, rot: float) -> String:
	var cls := "edge" if t in ["wall", "doorway", "window", "fence"] else ("cell" if t in ["foundation", "stairs"] else ("level" if t in ["floor", "roof", "roof_slope"] else "free"))
	if cls == "free":
		return ""
	var r := int(round(fposmod(rot, PI) / (PI * 0.5))) % 2
	return "%s|%d|%d|%d|%d" % [cls, roundi(pos.x * 2.0), roundi(pos.y * 2.0), roundi(pos.z * 2.0), r if cls == "edge" else 0]

func occupied(t: String, pos: Vector3, rot: float) -> bool:
	var k := _occ_key(t, pos, rot)
	if k == "":
		for id in structures:
			var s: Node3D = structures[id]
			if is_instance_valid(s) and s.global_position.distance_to(pos) < 0.8:
				return true
		return false
	return occupancy.has(k)

func _clear_grass_at(p: Vector3, t: String, info: Dictionary) -> void:
	if not info.has("grass"):
		return
	var half := 1.7 if t in ["foundation", "floor", "stairs"] else (1.3 if t in ["tent", "bed", "workbench", "planter"] else 0.0)
	if half <= 0.0 or t in ["wall", "doorway", "window", "fence", "roof", "roof_slope", "lantern"]:
		return
	var gp: PackedVector3Array = info["grass"]
	var mm: MultiMesh = info["grass_mm"]
	var root: Node3D = info["node"]
	for i in range(gp.size()):
		var g := gp[i]
		if absf(g.x - p.x) < half and absf(g.z - p.z) < half and g.y < p.y + 1.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), g - root.position))

func spawn_structure(id: String, rec: Dictionary) -> void:
	if structures.has(id):
		return
	Game.structures[id] = rec
	var s := StaticBody3D.new()
	s.set_script(Structure)
	add_child(s)
	s.setup(id, rec)
	structures[id] = s
	var ck := _chunk_of(s.global_position)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if chunks.has(k):
				_clear_grass_at(s.global_position, s.type, chunks[k])
	var k := _occ_key(rec["type"], Game.v3(rec["pos"]), float(rec.get("rot", 0.0)))
	if k != "":
		occupancy[k] = id

## House furniture (see Pois._furn): spawned the first time its house loads.
func spawn_poi_furniture(id: String, rec: Dictionary) -> void:
	if Game.structures.has(id) or Game.removed.has(id) or structures.has(id):
		return
	Net.place_structure(id, rec)

func remove_structure_local(id: String) -> void:
	if id.begins_with("poi"):
		Game.removed[id] = true # taken from a house: don't put it back there
	if structures.has(id):
		var s: Node = structures[id]
		var rec: Dictionary = Game.structures.get(id, {})
		if not rec.is_empty():
			occupancy.erase(_occ_key(rec["type"], Game.v3(rec["pos"]), float(rec.get("rot", 0.0))))
		if is_instance_valid(s):
			s.queue_free()
		structures.erase(id)
	Game.structures.erase(id)

func structure_data(id: String, d: Dictionary) -> void:
	if Game.structures.has(id):
		Game.structures[id]["data"] = d
	if structures.has(id) and is_instance_valid(structures[id]):
		structures[id].remote_data(d)

# ------------------------------------------------------------------ vehicles
func spawn_vehicle(vid: String, kind: String, pos: Vector3, rot: Vector3, state: Dictionary) -> Node:
	if vehicle_nodes.has(vid):
		return vehicle_nodes[vid]
	var v: VehicleBody3D
	if Trailer.SPECS.has(kind):
		v = VehicleBody3D.new()
		v.set_script(Trailer)
	else:
		v = VehicleBody3D.new()
		v.set_script(Car)
	v.setup(vid, kind, state)
	add_child(v)
	v.global_position = pos
	v.rotation = rot
	vehicle_nodes[vid] = v
	restore_cargo(v, state.get("cargo", []))
	if v.has_method("restore_attached"):
		v.restore_attached(state.get("attached", []))
	Game.vehicles[vid] = v.save_state()
	return v

func cargo_records(v: Node) -> Array:
	var out := []
	var cargo := v.get_node_or_null("Cargo")
	if cargo == null:
		return out
	for ch in cargo.get_children():
		if ch.is_in_group("world_item") and is_instance_valid(ch):
			out.append({"id": ch.id, "n": ch.amount, "pos": Game.arr(ch.position), "rot": Game.arr(ch.rotation)})
	return out

func restore_cargo(v: Node, list: Array) -> void:
	var cargo := v.get_node_or_null("Cargo")
	if cargo == null:
		return
	for r in list:
		var it := RigidBody3D.new()
		it.set_script(load("res://scripts/world_item.gd"))
		it.setup(str(r["id"]), int(r["n"]))
		it._attached = true
		it.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		it.freeze = true
		it.collision_mask = 0
		cargo.add_child(it)
		it.position = Game.v3(r["pos"])
		it.rotation = Game.v3(r["rot"])

func vehicle_states() -> Dictionary:
	var out := {}
	for vid in vehicle_nodes:
		var v = vehicle_nodes[vid]
		if is_instance_valid(v):
			out[vid] = v.save_state()
	return out

## Abandoned vehicles that belong to a roadside location (spawned once, then saved).
func _poi_vehicles(poi: Dictionary) -> void:
	var row := int(poi["row"])
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.hash3(row, 4242, 9)
	var base: Vector3 = poi["pos"]
	var yaw: float = poi["yaw"]
	var bs := Basis(Vector3.UP, yaw)
	var plan := []
	match str(poi["type"]):
		"wrecks":
			plan.append(["veh_%d" % row, ["pickup", "sedan", "offroader"][rng.randi() % 3], Vector3(-6, 0, 5)])
			plan.append(["veh_%db" % row, ["sedan", "pickup", "box_truck"][rng.randi() % 3], Vector3(1, 0, -5)])
			if rng.randf() < 0.5:
				plan.append(["trl_%d" % row, ["camper", "flatbed", "tanker"][rng.randi() % 3], Vector3(6, 0, 4)])
		"house", "cabin":
			if rng.randf() < 0.55:
				plan.append(["veh_%d" % row, ["sedan", "pickup", "offroader"][rng.randi() % 3], Vector3(7.5, 0, 4)])
		"truck_stop":
			plan.append(["veh_%d" % row, "box_truck", Vector3(-7, 0, 3)])
			plan.append(["trl_%d" % row, ["tanker", "camper"][rng.randi() % 2], Vector3(5, 0, 6)])
		"farm":
			if rng.randf() < 0.6:
				plan.append(["veh_%d" % row, "pickup", Vector3(-4, 0, 7)])
			if rng.randf() < 0.5:
				plan.append(["trl_%d" % row, "flatbed", Vector3(3, 0, 8)])
	for p in plan:
		if Game.vehicles.has(p[0]) or vehicle_nodes.has(p[0]):
			continue
		var wp: Vector3 = base + bs * (p[2] as Vector3)
		wp.y = gen.height(wp.x, wp.z) + 0.7
		spawn_vehicle(p[0], p[1], wp, Vector3(0, yaw + rng.randf_range(-0.6, 0.6), 0), {})

# ------------------------------------------------------------------ co-op puppets
func update_remote_player(peer: int, pos: Vector3, yaw: float, in_vehicle: bool, pname: String) -> void:
	var p: Node3D = remote_players.get(peer)
	if p == null:
		p = Node3D.new()
		var body := Lib.cyl(p, Vector3(0, 0.85, 0), 0.3, 0.3, 1.3, Lib.mat("canvas", Color(0.4, 0.55, 0.8), 0.6, false))
		body.name = "Body"
		Lib.sphere(p, Vector3(0, 1.65, 0), 0.2, Lib.color_mat(Color(0.85, 0.7, 0.55)))
		Lib.box(p, Vector3(0, 1.66, -0.18), Vector3(0.25, 0.06, 0.05), Lib.color_mat(Color(0.1, 0.1, 0.1)))
		Lib.label3d(p, Vector3(0, 2.15, 0), pname, 40)
		add_child(p)
		remote_players[peer] = p
	p.visible = not in_vehicle
	p.global_position = p.global_position.lerp(pos, 0.5) if p.global_position.distance_to(pos) < 10.0 else pos
	p.rotation.y = yaw

func remove_remote_player(peer: int) -> void:
	if remote_players.has(peer):
		remote_players[peer].queue_free()
		remote_players.erase(peer)
