extends CharacterBody3D
## Wildlife: wanders, grazes, flees or attacks; can be hunted and butchered.

const Data = preload("res://scripts/data.gd")

var species := "deer"
var spec := {}
var hp := 50.0
var state := "idle" # idle, wander, flee, chase, dead
var target := Vector3.ZERO
var threat := Vector3.ZERO
var _timer := 0.0
var _attack_cd := 0.0
var _phase := 0.0
var _legs: Array[Node3D] = []
var _model: Node3D
var _anim: AnimationPlayer
var _speed := 0.0
var _decay := 600.0
var net_id := ""
var _last_sound := 0.0

func setup(p_species: String, pos: Vector3) -> void:
	species = p_species
	spec = Data.ANIMALS[species]
	hp = float(spec["hp"])
	position = pos
	collision_layer = 8
	collision_mask = 1
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(55)
	add_to_group("animal")
	var s: float = spec["size"]
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 1.3, 1.5) * s
	cs.shape = sh
	cs.position.y = 0.65 * s + 0.02
	add_child(cs)
	_model = Node3D.new()
	add_child(_model)
	_build_model()
	_timer = randf_range(1.0, 4.0)

# ------------------------------------------------------------------ models
func _leg(pos: Vector3, length: float, r: float, m: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	_model.add_child(pivot)
	Lib.cyl(pivot, Vector3(0, -length * 0.5, 0), r * 0.7, r, length, m, Vector3.ZERO, 8)
	Lib.cyl(pivot, Vector3(0, -length + 0.03, 0), r * 0.75, r * 0.8, 0.06, Lib.color_mat(Color(0.1, 0.08, 0.06)), Vector3.ZERO, 8)
	_legs.append(pivot)

func _build_model() -> void:
	var c: Color = spec["color"]
	var fur := Lib.mat("fur", c.lightened(0.15), 3.0, false, 0.95)
	var light := Lib.mat("fur", c.lightened(0.5), 3.0, false, 0.95)
	var dark := Lib.mat("fur", c.darkened(0.35), 3.0, false, 0.9)
	var eye := Lib.color_mat(Color(0.03, 0.03, 0.03), 0.2)
	match species:
		"deer":
			Lib.sphere(_model, Vector3(0, 1.05, 0), 0.5, fur, Vector3(0.62, 0.68, 1.35))
			Lib.sphere(_model, Vector3(0, 0.95, 0.05), 0.45, light, Vector3(0.55, 0.45, 1.1))
			Lib.cyl(_model, Vector3(0, 1.38, -0.62), 0.11, 0.17, 0.7, fur, Vector3(-0.6, 0, 0))
			var head := Node3D.new()
			head.position = Vector3(0, 1.72, -0.85)
			_model.add_child(head)
			Lib.sphere(head, Vector3(0, 0, 0), 0.16, fur, Vector3(0.85, 0.9, 1.5))
			Lib.sphere(head, Vector3(0, -0.04, -0.22), 0.08, dark, Vector3(0.9, 0.8, 1.0))
			for x in [-0.08, 0.08]:
				Lib.sphere(head, Vector3(x, 0.05, -0.08), 0.025, eye)
				Lib.box(head, Vector3(x * 1.8, 0.14, 0.05), Vector3(0.05, 0.16, 0.03), fur, false, Vector3(0, 0, -signf(x) * 0.6))
			if randf() < 0.5:
				var antler := Lib.color_mat(Color(0.85, 0.78, 0.65), 0.7)
				for x in [-1.0, 1.0]:
					Lib.cyl(head, Vector3(x * 0.1, 0.3, 0.05), 0.012, 0.025, 0.45, antler, Vector3(0, 0, -x * 0.35))
					Lib.cyl(head, Vector3(x * 0.2, 0.42, -0.05), 0.01, 0.018, 0.25, antler, Vector3(-0.5, 0, -x * 0.5))
					Lib.cyl(head, Vector3(x * 0.25, 0.55, 0.1), 0.01, 0.015, 0.2, antler, Vector3(0.4, 0, -x * 0.7))
			Lib.sphere(_model, Vector3(0, 1.2, 0.68), 0.08, light, Vector3(1, 1.4, 0.6))
			for p in [Vector3(-0.17, 0.9, -0.45), Vector3(0.17, 0.9, -0.45), Vector3(-0.17, 0.9, 0.45), Vector3(0.17, 0.9, 0.45)]:
				_leg(p, 0.92, 0.055, fur)
		"rabbit":
			Lib.sphere(_model, Vector3(0, 0.2, 0), 0.17, fur, Vector3(0.9, 0.85, 1.25))
			Lib.sphere(_model, Vector3(0, 0.33, -0.17), 0.09, fur)
			for x in [-0.035, 0.035]:
				Lib.box(_model, Vector3(x, 0.48, -0.15), Vector3(0.035, 0.18, 0.02), fur, false, Vector3(0.2, 0, x * 3.0))
				Lib.sphere(_model, Vector3(x * 1.6, 0.35, -0.24), 0.012, eye)
			Lib.sphere(_model, Vector3(0, 0.22, 0.2), 0.05, light)
			for p in [Vector3(-0.07, 0.1, -0.08), Vector3(0.07, 0.1, -0.08), Vector3(-0.08, 0.1, 0.1), Vector3(0.08, 0.1, 0.1)]:
				_leg(p, 0.1, 0.025, fur)
		"boar":
			Lib.sphere(_model, Vector3(0, 0.62, 0), 0.5, fur, Vector3(0.75, 0.75, 1.3))
			Lib.box(_model, Vector3(0, 0.95, -0.05), Vector3(0.12, 0.12, 0.9), dark)
			var head := Node3D.new()
			head.position = Vector3(0, 0.6, -0.65)
			_model.add_child(head)
			Lib.sphere(head, Vector3.ZERO, 0.26, fur, Vector3(0.9, 0.9, 1.1))
			Lib.cyl(head, Vector3(0, -0.06, -0.3), 0.08, 0.12, 0.25, dark, Vector3(PI * 0.5, 0, 0))
			for x in [-0.09, 0.09]:
				Lib.cyl(head, Vector3(x, -0.08, -0.33), 0.008, 0.02, 0.14, Lib.color_mat(Color(0.95, 0.92, 0.85)), Vector3(-0.6, 0, 0))
				Lib.sphere(head, Vector3(x, 0.08, -0.18), 0.02, eye)
				Lib.box(head, Vector3(x * 1.5, 0.22, 0.0), Vector3(0.06, 0.1, 0.03), fur)
			for p in [Vector3(-0.2, 0.45, -0.35), Vector3(0.2, 0.45, -0.35), Vector3(-0.2, 0.45, 0.35), Vector3(0.2, 0.45, 0.35)]:
				_leg(p, 0.45, 0.07, dark)
		"wolf", "bear":
			var big := species == "bear"
			var sz := 1.0 if not big else 1.55
			var body_y := 0.72 * sz
			Lib.sphere(_model, Vector3(0, body_y, 0), 0.4 * sz, fur, Vector3(0.75 if not big else 0.95, 0.8, 1.45 if not big else 1.3))
			Lib.sphere(_model, Vector3(0, body_y + 0.05 * sz, -0.35 * sz), 0.33 * sz, fur)
			var head := Node3D.new()
			head.position = Vector3(0, body_y + 0.2 * sz, -0.72 * sz)
			_model.add_child(head)
			Lib.sphere(head, Vector3.ZERO, 0.2 * sz, fur)
			Lib.cyl(head, Vector3(0, -0.05 * sz, -0.2 * sz), 0.05 * sz, 0.1 * sz, (0.25 if not big else 0.18) * sz, light, Vector3(PI * 0.5, 0, 0))
			Lib.sphere(head, Vector3(0, -0.04 * sz, -0.34 * sz), 0.035 * sz, eye)
			for x in [-1.0, 1.0]:
				Lib.sphere(head, Vector3(x * 0.08 * sz, 0.07 * sz, -0.15 * sz), 0.022 * sz, Lib.color_mat(Color(0.8, 0.6, 0.1) if not big else Color(0.05, 0.05, 0.05), 0.2))
				if big:
					Lib.sphere(head, Vector3(x * 0.15 * sz, 0.17 * sz, 0.0), 0.06 * sz, fur)
				else:
					Lib.box(head, Vector3(x * 0.1, 0.2, 0.0), Vector3(0.07, 0.14, 0.03), fur, false, Vector3(0, 0, -x * 0.25))
			if not big:
				Lib.cyl(_model, Vector3(0, body_y - 0.05, 0.75), 0.04, 0.09, 0.5, fur, Vector3(-1.0, 0, 0))
			var lr := 0.07 * sz if not big else 0.13
			for p in [Vector3(-0.17, 0.62, -0.38), Vector3(0.17, 0.62, -0.38), Vector3(-0.17, 0.62, 0.38), Vector3(0.17, 0.62, 0.38)]:
				_leg(p * Vector3(sz, sz, sz), 0.62 * sz, lr, fur)
		"turkey":
			Lib.sphere(_model, Vector3(0, 0.5, 0), 0.25, fur, Vector3(0.9, 0.9, 1.1))
			Lib.sphere(_model, Vector3(0, 0.62, 0.28), 0.32, Lib.color_mat(Color(0.35, 0.25, 0.18), 0.8), Vector3(1.0, 0.9, 0.15))
			Lib.cyl(_model, Vector3(0, 0.78, -0.2), 0.03, 0.05, 0.3, Lib.color_mat(Color(0.55, 0.6, 0.7)), Vector3(-0.3, 0, 0))
			Lib.sphere(_model, Vector3(0, 0.95, -0.25), 0.06, Lib.color_mat(Color(0.75, 0.2, 0.2)))
			Lib.box(_model, Vector3(0, 0.93, -0.33), Vector3(0.02, 0.02, 0.06), Lib.color_mat(Color(0.8, 0.7, 0.3)))
			for p in [Vector3(-0.08, 0.35, 0.0), Vector3(0.08, 0.35, 0.0)]:
				_leg(p, 0.35, 0.02, Lib.color_mat(Color(0.65, 0.5, 0.35)))
		"fox":
			var fox_scene: PackedScene = load("res://assets/models/Fox.glb")
			if fox_scene:
				var fox: Node3D = fox_scene.instantiate()
				_model.add_child(fox)
				fox.scale = Vector3.ONE * 0.012
				fox.rotation.y = PI
				_anim = _find_anim(fox)
				if _anim:
					_anim.play(_anim_name("Survey"))

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null

func _anim_name(base: String) -> String:
	if _anim == null:
		return ""
	for a in _anim.get_animation_list():
		if a.to_lower().ends_with(base.to_lower()):
			return a
	return _anim.get_animation_list()[0] if _anim.get_animation_list().size() > 0 else ""

# ------------------------------------------------------------------ AI
func _physics_process(delta: float) -> void:
	if state == "dead":
		_decay -= delta
		if _decay <= 0.0:
			queue_free()
		if not is_on_floor():
			velocity.y -= 14.0 * delta
			move_and_slide()
		return
	var player: Node3D = Game.player
	var dist := global_position.distance_to(player.global_position) if player else 999.0
	if dist > 160.0:
		return # dormant far away
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_timer -= delta
	var night := Game.time_of_day < 5.5 or Game.time_of_day > 20.5
	var aggro: float = float(spec["aggro"]) * (1.5 if night else 1.0)
	var player_ok: bool = player and not player.dead and not player.driving
	var sneaking: bool = player_ok and player.crouching
	var flee_r: float = float(spec["flee"]) * (0.55 if sneaking else 1.0)
	if player_ok:
		if aggro > 0.0 and dist < aggro and state != "flee":
			state = "chase"
		elif flee_r > 0.0 and dist < flee_r and state != "chase":
			state = "flee"
			threat = player.global_position
			_timer = randf_range(5.0, 8.0)
	match state:
		"idle":
			_speed = 0.0
			if _timer <= 0.0:
				state = "wander"
				var a := randf() * TAU
				target = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 18.0)
				_timer = randf_range(5.0, 12.0)
		"wander":
			_speed = float(spec["walk"])
			if _timer <= 0.0 or Vector2(global_position.x - target.x, global_position.z - target.z).length() < 1.0:
				state = "idle"
				_timer = randf_range(2.0, 7.0)
		"flee":
			_speed = float(spec["run"])
			var away := (global_position - threat)
			away.y = 0
			target = global_position + away.normalized() * 10.0
			if _timer <= 0.0:
				state = "idle"
				_timer = 2.0
		"chase":
			_speed = float(spec["run"])
			if not player_ok or dist > aggro * 2.2:
				state = "idle"
				_timer = 3.0
			else:
				target = player.global_position
				var reach := 1.6 * float(spec["size"]) + 0.6
				if dist < reach:
					_speed = 0.0
					if _attack_cd <= 0.0:
						_attack_cd = 1.3
						player.hurt(float(spec["dmg"]) * Game.diff("damage"), species)
						Audio.play_at("growl", global_position, 2.0)
				elif Time.get_ticks_msec() * 0.001 - _last_sound > 6.0:
					_last_sound = Time.get_ticks_msec() * 0.001
					Audio.play_at("growl", global_position, 0.0, 0.8 if species == "bear" else 1.1)
	var to := target - global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.3 and _speed > 0.0 else Vector3.ZERO
	# avoid water
	if dir != Vector3.ZERO:
		var ahead := global_position + dir * 3.0
		if Game.world.gen.is_water(ahead.x, ahead.z, 0.2):
			dir = dir.rotated(Vector3.UP, PI * 0.6)
			target = global_position + dir * 8.0
	velocity.x = move_toward(velocity.x, dir.x * _speed, delta * 14.0)
	velocity.z = move_toward(velocity.z, dir.z * _speed, delta * 14.0)
	velocity.y = velocity.y - 14.0 * delta if not is_on_floor() else -1.0
	move_and_slide()
	if is_on_wall() and state in ["wander", "flee"]:
		target = global_position + get_wall_normal().rotated(Vector3.UP, randf_range(-1.0, 1.0)) * 8.0
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.2:
		var want := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, want, delta * 8.0)
	_animate(delta, hv.length())

func _animate(delta: float, spd: float) -> void:
	if _anim:
		var want := _anim_name("Survey") if spd < 0.3 else (_anim_name("Walk") if spd < 3.0 else _anim_name("Run"))
		if _anim.current_animation != want and want != "":
			_anim.play(want, 0.2)
		return
	_phase += delta * spd * (3.2 / maxf(float(spec["size"]), 0.4))
	var amp := clampf(spd / 3.0, 0.0, 1.0) * 0.6
	for i in range(_legs.size()):
		var off := 0.0 if i in [0, 3] else PI
		_legs[i].rotation.x = sin(_phase + off) * amp
	if species == "rabbit":
		_model.position.y = absf(sin(_phase)) * 0.12 * clampf(spd, 0.0, 1.0)
	else:
		_model.position.y = absf(sin(_phase * 2.0)) * 0.03 * amp

func alert(from: Vector3) -> void:
	if state == "dead":
		return
	if float(spec["aggro"]) > 0.0 and global_position.distance_to(from) < 40.0:
		state = "chase"
		return
	state = "flee"
	threat = from
	_timer = randf_range(6.0, 10.0)

func take_damage(amount: float, from: Vector3) -> void:
	if state == "dead":
		return
	hp -= amount
	_blood()
	Net.animal_hit(net_id, amount)
	if hp <= 0.0:
		_die()
		return
	if species == "boar" or float(spec["aggro"]) > 0.0:
		state = "chase"
	else:
		state = "flee"
		threat = from
		_timer = 8.0

func _blood() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.06
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = Lib.color_mat(Color(0.45, 0.02, 0.02), 0.4)
	p.mesh = bm
	add_child(p)
	p.position = Vector3(0, 0.8 * float(spec["size"]), 0)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _die() -> void:
	state = "dead"
	velocity = Vector3.ZERO
	_model.rotation.z = PI * 0.5
	_model.position.y = 0.35 * float(spec["size"])
	if _anim:
		_anim.pause()
	collision_layer = 2
	Game.notify("You killed a %s" % species)

func get_prompt() -> String:
	if state != "dead":
		return ""
	if Game.count("knife") <= 0:
		return "%s carcass — you need a knife to butcher" % species.capitalize()
	return "[E] Butcher %s" % species

func interact(_player: Node) -> void:
	if state != "dead":
		return
	if Game.count("knife") <= 0:
		Game.notify("You need a knife")
		return
	var drops: Dictionary = spec["drops"]
	for k in drops:
		Game.add_item(k, int(drops[k]))
	Audio.play_at("chop", global_position, 0.0, 0.8)
	queue_free()
