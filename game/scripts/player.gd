extends CharacterBody3D
## First-person survivor: movement, tools, hunting, harvesting, fishing, survival needs.

const Data = preload("res://scripts/data.gd")
const Builder = preload("res://scripts/builder.gd")
const Arrow = preload("res://scripts/arrow.gd")

const WALK := 4.3
const SPRINT := 7.2
const CROUCH := 2.0
const JUMP := 4.8
const GRAVITY := 14.0
const EYE := 1.62

var head: Node3D
var camera: Camera3D
var ray: RayCast3D
var viewmodel: Node3D
var flashlight: SpotLight3D
var builder: Node3D
var pitch := 0.0
var driving := false
var vehicle: Node
var is_driver := false
var crouching := false
var dead := false
var look_target: Object = null
var prompt := ""

var _cooldown := 0.0
var _bob := 0.0
var _step_acc := 0.0
var _vm_kind := ""
var _swing := 0.0
var _aiming := false
var _fish_state := "" # "", "waiting", "bite"
var _fish_timer := 0.0
var _bobber: MeshInstance3D
var _fish_point := Vector3.ZERO
var _survival_acc := 0.0
var _howl_timer := 30.0
var _hurt_cd := 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 16
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.04
	camera.far = 1500.0
	camera.fov = Game.settings["fov"]
	head.add_child(camera)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -3.2)
	ray.collision_mask = 1 | 2 | 8 | 16 | 32
	ray.collide_with_areas = false
	ray.add_exception(self)
	camera.add_child(ray)
	viewmodel = Node3D.new()
	viewmodel.position = Vector3(0.32, -0.3, -0.55)
	camera.add_child(viewmodel)
	flashlight = SpotLight3D.new()
	flashlight.spot_range = 30.0
	flashlight.spot_angle = 26.0
	flashlight.light_energy = 3.5
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.25, -0.15, 0)
	flashlight.visible = false
	camera.add_child(flashlight)
	builder = Node3D.new()
	builder.set_script(Builder)
	builder.player = self
	add_child(builder)
	builder.top_level = true
	_bobber = Lib.sphere(self, Vector3.ZERO, 0.06, Lib.color_mat(Color(0.9, 0.15, 0.1), 0.4))
	_bobber.top_level = true
	_bobber.visible = false
	Game.hotbar_changed.connect(_refresh_viewmodel)
	Game.inventory_changed.connect(_refresh_viewmodel)
	_refresh_viewmodel()
	add_to_group("player")

func make_current() -> void:
	camera.make_current()

# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if Game.paused or Game.ui_open or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = Game.settings["sensitivity"] * 0.01
		look(event.relative * s)
	if event.is_action_pressed("hotbar_next"):
		Game.select_slot(Game.selected_slot + 1)
	elif event.is_action_pressed("hotbar_prev"):
		Game.select_slot(Game.selected_slot - 1)
	for i in range(6):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			Game.select_slot(i)
	if event.is_action_pressed("interact"):
		_interact()
	if event.is_action_pressed("pickup"):
		_pickup()
	if event.is_action_pressed("flashlight"):
		toggle_flashlight()
	if driving:
		if event.is_action_pressed("camera"):
			vehicle.set_camera(not vehicle.use_tp)
		if event.is_action_pressed("lights") and is_driver:
			vehicle.toggle_headlights()
	else:
		if event.is_action_pressed("crouch"):
			crouching = not crouching

func look(rel: Vector2) -> void:
	if Game.settings["invert_y"]:
		rel.y = -rel.y
	if driving:
		vehicle.look(rel)
		return
	rotate_y(-rel.x)
	pitch = clampf(pitch - rel.y, -1.5, 1.5)
	head.rotation.x = pitch

func toggle_flashlight() -> void:
	if Game.count("flashlight") <= 0:
		Game.notify("You don't have a flashlight")
		return
	flashlight.visible = not flashlight.visible
	Audio.play("click", -6.0)

# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if dead:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	# controller / touch look
	var stick := Vector2(Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
		Input.get_action_strength("look_down") - Input.get_action_strength("look_up"))
	if stick.length() > 0.05 and not Game.ui_open and not Game.paused:
		look(stick * delta * 2.6 * (Game.settings["sensitivity"] / 0.25))
	if Game.world.touch:
		var td: Vector2 = Game.world.touch.consume_look()
		if td != Vector2.ZERO and not Game.ui_open:
			look(td * Game.settings["sensitivity"] * 0.012)
	_survival(delta)
	if driving:
		if is_driver and Input.is_action_just_pressed("primary") and not vehicle.engine_on and not Game.ui_open:
			vehicle.try_start_engine()
		var seat: Vector3 = vehicle.seat_global(is_driver)
		global_position = seat
		velocity = Vector3.ZERO
		_update_prompt()
		return
	_move(delta)
	_update_prompt()
	_handle_tools(delta)
	_fishing(delta)

func _move(delta: float) -> void:
	if not Game.world.ground_ready(global_position):
		return
	var input := Vector2.ZERO
	if not Game.ui_open and not Game.paused:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var in_water: bool = Game.world.gen.is_water(global_position.x, global_position.z, 0.0) and global_position.y < Game.world.gen.water_level(global_position.x, global_position.z) - 0.4
	var sprint: bool = Input.is_action_pressed("sprint") and Game.stats["energy"] > 5.0 and input.y < 0.0
	if Game.world.touch and Game.world.touch.sprint_on:
		sprint = Game.stats["energy"] > 5.0 and input.length() > 0.6
	var speed := SPRINT if sprint else WALK
	if crouching:
		speed = CROUCH
	if in_water:
		speed *= 0.5
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var accel := 10.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	if in_water:
		var wl: float = Game.world.gen.water_level(global_position.x, global_position.z)
		velocity.y = move_toward(velocity.y, clampf((wl - 1.3 - global_position.y) * 3.0, -2.0, 2.0), delta * 8.0)
		if Input.is_action_pressed("jump"):
			velocity.y = 2.0
	else:
		velocity.y -= GRAVITY * delta
		if is_on_floor() and Input.is_action_just_pressed("jump") and not Game.ui_open:
			velocity.y = JUMP
			crouching = false
	var was_air := not is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()
	if was_air and is_on_floor() and fall_speed < -11.0:
		hurt((-fall_speed - 11.0) * 6.0, "fall")
	if sprint and input.length() > 0.1:
		Game.stats["energy"] = maxf(Game.stats["energy"] - delta * 0.35 * Game.diff("drain"), 0.0)
	# head bob & footsteps
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var eye := EYE - (0.6 if crouching else 0.0)
	if is_on_floor() and hspeed > 0.5:
		_bob += delta * hspeed * 1.9
		_step_acc += hspeed * delta
		if _step_acc > (1.9 if sprint else 1.5):
			_step_acc = 0.0
			_footstep()
	var bob_amt: float = 0.045 if Game.settings["head_bob"] else 0.0
	head.position.y = lerpf(head.position.y, eye + sin(_bob * 2.0) * bob_amt * minf(hspeed / WALK, 1.4), delta * 12.0)
	head.position.x = cos(_bob) * bob_amt * 0.5 * minf(hspeed / WALK, 1.0)
	if global_position.y < -200.0:
		teleport(Game.rv.global_position + Vector3(4, 3, 0))

func _footstep() -> void:
	var s := "step_ground"
	var below := get_last_slide_collision()
	if below and below.get_collider() and (below.get_collider().is_in_group("structure") or below.get_collider().is_in_group("rv")):
		s = "step_wood"
	elif Game.world.gen.biome_weights(global_position.x, global_position.z).w > 0.5:
		s = "step_snow"
	Audio.play(s, -10.0 if not crouching else -18.0, randf_range(0.9, 1.1))

func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO

# ------------------------------------------------------------------ interaction
func _find_interactable(n: Object) -> Object:
	var node := n as Node
	for i in range(4):
		if node == null:
			return null
		if node.has_meta("door_of"):
			return node.get_meta("door_of")
		if node.has_method("interact") or node.has_meta("res_kind"):
			return node
		node = node.get_parent()
	return null

func _update_prompt() -> void:
	look_target = null
	prompt = ""
	if driving:
		var spd: float = absf(vehicle.speed_kmh())
		prompt = "[E] Exit vehicle" if spd < 12.0 else ""
		return
	if ray.is_colliding():
		var t := _find_interactable(ray.get_collider())
		if t:
			look_target = t
			if t.has_method("get_prompt"):
				prompt = t.get_prompt()
			elif t.has_meta("res_kind"):
				prompt = _resource_prompt(t)
	if _fish_state == "bite":
		prompt = "A fish is biting! [Use] to reel in!"
	elif _fish_state == "waiting":
		prompt = "Waiting for a bite...  [Use] to reel in"

func _resource_prompt(t: Node) -> String:
	match str(t.get_meta("res_kind")):
		"tree": return "Tree — chop with a hatchet [Use]"
		"rock": return "Rock — mine with a pickaxe [Use]"
		"pickup":
			return "[E] Pick up %s" % ("branch (wood)" if t.get_meta("item") == "wood" else "stone")
		"bush":
			var k: String = t.get_meta("bush_kind")
			return "[E] Gather %s" % {"fiber": "plant fiber", "berry": "berries", "mushroom": "mushrooms"}.get(k, k)
	return ""

func _interact() -> void:
	if driving:
		if absf(vehicle.speed_kmh()) < 12.0:
			exit_vehicle()
		return
	if look_target == null:
		return
	if look_target.has_method("interact"):
		look_target.interact(self)
	elif look_target.has_meta("res_kind") and look_target.get_meta("res_kind") == "bush":
		Game.world.harvest_bush(look_target)
	elif look_target.has_meta("res_kind") and look_target.get_meta("res_kind") == "pickup":
		Game.add_item(look_target.get_meta("item"), 1)
		Audio.play("pickup", -6.0)
		Net.mark_removed(look_target.get_meta("res_key"), true)

## Grab a loose item, or pick a placed object (crate, campfire, chair...) back up to move it.
func _pickup() -> void:
	if driving or look_target == null:
		return
	var t := look_target as Node
	if t.is_in_group("world_item"):
		t.interact(self)
		return
	if t.get_script() == Builder.Structure and t.is_in_group("placeable"):
		var type: String = t.type
		if type == "crate" and t.data.has("items"):
			for k in t.data["items"]:
				Game.add_item(k, int(t.data["items"][k]), true)
		if t.has_meta("rv_rec"):
			t.get_meta("host").detach_structure(t)
		elif t.persistent:
			Net.remove_structure(t.id)
		else:
			return
		Game.add_item(type, 1)
		Audio.play("pickup")

func drop_item(id: String, n := 1) -> void:
	if not Game.remove_item(id, n):
		return
	var fwd := -camera.global_transform.basis.z
	Game.spawn_item(id, n, camera.global_position + fwd * 0.8 + Vector3(0, -0.3, 0), fwd * 1.5)

func enter_vehicle(rv: Node, as_driver: bool) -> void:
	if as_driver and rv == Game.rv and not Net.claim_driver(true):
		Game.notify("Someone else is driving")
		return
	driving = true
	is_driver = as_driver
	vehicle = rv
	if as_driver:
		rv.driver = Net.my_id()
		rv.try_start_engine()
	$CollisionShape3D.disabled = true
	visible = false
	viewmodel.visible = false
	rv.fp_yaw = 0.0
	rv.fp_pitch = 0.0
	rv.look(Vector2.ZERO)
	rv.set_seat(as_driver)
	rv.set_camera(rv.use_tp if as_driver else false)
	builder.set_active(false)

func exit_vehicle() -> void:
	if not driving:
		return
	var rv := vehicle
	if is_driver:
		rv.stop_engine()
		rv.driver = 0
		if rv == Game.rv:
			Net.claim_driver(false)
	rv.set_seat(true)
	driving = false
	is_driver = false
	$CollisionShape3D.disabled = false
	visible = true
	viewmodel.visible = true
	teleport(rv.exit_global())
	rotation.y = rv.global_rotation.y + PI
	camera.make_current()

# ------------------------------------------------------------------ tools
func _refresh_viewmodel() -> void:
	var id := Game.equipped()
	if id == _vm_kind:
		return
	_vm_kind = id
	for c in viewmodel.get_children():
		c.queue_free()
	_aiming = false
	# grip pose per item: [position, rotation, scale]
	var pose := [Vector3(0.0, 0.0, 0.0), Vector3(-0.35, 0.15, 0.08), 1.0]
	match id:
		"axe", "pickaxe", "hammer":
			pose = [Vector3(0, 0, 0), Vector3(-0.45, 0.2, 0.15), 1.0]
		"knife":
			pose = [Vector3(0, 0, 0), Vector3(-0.75, 0.25, 0.1), 1.2]
		"rifle":
			pose = [Vector3(-0.1, 0.04, -0.2), Vector3(-PI * 0.5, 0.0, 0.0), 1.0]
		"bow":
			pose = [Vector3(-0.2, 0.08, -0.08), Vector3(-0.05, 0.0, 0.25), 1.0]
		"fishing_rod":
			pose = [Vector3(0, 0, 0), Vector3(-0.95, 0.1, 0.0), 1.0]
		"flashlight":
			pose = [Vector3(0, 0.02, 0), Vector3(-1.1, 0.1, 0.0), 1.2]
		"arrow":
			pose = [Vector3(0, 0, 0), Vector3(-PI * 0.5, 0.0, 0.0), 1.0]
		"":
			pose = [Vector3(0, 0, 0), Vector3.ZERO, 1.0]
		_:
			pose = [Vector3(0, -0.02, -0.03), Vector3(0.2, 0.6, 0.0), 0.9]
	if id != "":
		var item := Items.instance(id)
		item.position = pose[0]
		item.rotation = pose[1]
		item.scale = Vector3.ONE * pose[2]
		_set_no_shadow(item)
		viewmodel.add_child(item)
	var arm := MeshInstance3D.new()
	arm.mesh = Items.arm_mesh()
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.rotation = Vector3(0.0, 0.0, 0.25 if id != "" else 0.0)
	viewmodel.add_child(arm)
	if id in ["bow", "rifle"]:
		var left := MeshInstance3D.new()
		left.mesh = Items.arm_mesh()
		left.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		left.scale = Vector3(-1, 1, 1)
		left.position = Vector3(-0.3, 0.06, -0.12) if id == "bow" else Vector3(-0.1, 0.03, -0.32)
		left.rotation = Vector3(0.3, 0.3, -0.2)
		viewmodel.add_child(left)
	if builder:
		if Data.ITEMS.get(id, {}).get("kind", "") == "placeable" and not driving:
			builder.place_kit(id)
		elif builder.kit != "":
			builder.stop()

func _set_no_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_set_no_shadow(ch)

func _handle_tools(delta: float) -> void:
	_swing = maxf(_swing - delta * 4.0, 0.0)
	viewmodel.rotation.x = -sin(_swing * PI) * 1.1
	viewmodel.position.z = -0.55 + sin(_swing * PI) * -0.15
	var id := Game.equipped()
	var aiming := Input.is_action_pressed("secondary") and id in ["bow", "rifle"] and not Game.ui_open
	if Game.world.touch and Game.world.touch.aim_on and id in ["bow", "rifle"]:
		aiming = true
	var target_fov: float = Game.settings["fov"] * (0.45 if aiming and id == "rifle" else (0.8 if aiming else 1.0))
	camera.fov = lerpf(camera.fov, target_fov, delta * 10.0)
	viewmodel.position.x = lerpf(viewmodel.position.x, 0.05 if aiming else 0.32, delta * 10.0)
	if Game.ui_open or Game.paused:
		return
	if builder.active:
		return
	if Input.is_action_pressed("primary") and _cooldown <= 0.0:
		use_primary()

func use_primary() -> void:
	var id := Game.equipped()
	if _fish_state != "":
		_reel()
		return
	if id == "":
		_melee(5.0, 1.8, "")
		_cooldown = 0.6
		return
	var it: Dictionary = Data.ITEMS.get(id, {})
	match id:
		"axe", "pickaxe", "knife", "hammer":
			_melee(float(it["damage"]), float(it.get("reach", 2.4)), id)
			_cooldown = 0.6 if id != "knife" else 0.45
		"bow":
			if Game.remove_item("arrow", 1):
				var a := Node3D.new()
				a.set_script(Arrow)
				Game.world.add_child(a)
				a.launch(camera.global_position + camera.global_transform.basis * Vector3(0, -0.05, -0.4), -camera.global_transform.basis.z * 58.0, float(it["damage"]), self)
				Audio.play("bow")
				_swing = 0.3
			else:
				Game.notify("No arrows. Craft some from wood, stone and feathers.")
			_cooldown = 0.9
		"rifle":
			if Game.remove_item("ammo", 1):
				_shoot(float(it["damage"]))
			else:
				Audio.play("click")
				Game.notify("Out of ammo")
			_cooldown = 1.3
		"fishing_rod":
			_cast()
			_cooldown = 0.6
		"flashlight":
			toggle_flashlight()
			_cooldown = 0.3
		_:
			if it.get("kind", "") in ["food", "medical"]:
				Game.consume(id)
				_cooldown = 0.8
			elif it.get("kind", "") == "fuel" and Game.rv.global_position.distance_to(global_position) < 6.0:
				Game.rv.do_action("fuel", self)
				_cooldown = 0.8
			else:
				_cooldown = 0.3

func _melee(dmg: float, reach: float, tool: String) -> void:
	_swing = 1.0
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 8)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	if col.is_in_group("animal"):
		col.take_damage(dmg, global_position)
		Audio.play_at("hit", hit["position"])
		return
	if col.has_meta("res_kind"):
		var kind: String = col.get_meta("res_kind")
		if kind == "tree":
			if tool != "axe":
				Game.notify("You need a hatchet to chop trees")
				Audio.play_at("hit", hit["position"], -6.0)
				return
			Audio.play_at("chop", hit["position"])
			Game.world.hit_resource(col, hit["position"])
		elif kind == "rock":
			if tool != "pickaxe":
				Game.notify("You need a pickaxe to mine rock")
				Audio.play_at("hit", hit["position"], -6.0, 1.4)
				return
			Audio.play_at("hit", hit["position"], 0.0, 1.5)
			Game.world.hit_resource(col, hit["position"])
		elif kind == "bush":
			Game.world.harvest_bush(col)
		return
	Audio.play_at("hit", hit["position"], -8.0, 1.2)

func _shoot(dmg: float) -> void:
	Audio.play("gunshot")
	_swing = 0.35
	var flash := Lib.light(camera, Vector3(0, 0, -1), Color(1, 0.8, 0.5), 4.0, 8.0)
	get_tree().create_timer(0.06).timeout.connect(flash.queue_free)
	Game.world.alert_animals(global_position, 110.0)
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * (0.002 if Input.is_action_pressed("secondary") else 0.012)
	var dir := (camera.global_transform.basis * (Vector3(0, 0, -1) + spread)).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0, 1 | 8 | 16)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	if col.is_in_group("animal"):
		col.take_damage(dmg, global_position)
	Game.world.impact_puff(hit["position"])

# ------------------------------------------------------------------ fishing
func _cast() -> void:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 22.0, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var p: Vector3
	if hit.is_empty():
		p = from + dir * 14.0
	else:
		p = hit["position"]
	var gen = Game.world.gen
	if not gen.is_water(p.x, p.z, 0.4):
		# try to find the water surface along the ray
		var found := false
		for k in range(4, 22):
			var t: Vector3 = from + dir * float(k)
			if gen.is_water(t.x, t.z, 0.4) and t.y <= gen.water_level(t.x, t.z) + 0.3:
				p = t
				found = true
				break
		if not found:
			Game.notify("Cast into deeper water (aim at a lake)")
			return
	_fish_point = Vector3(p.x, gen.water_level(p.x, p.z), p.z)
	_bobber.global_position = _fish_point
	_bobber.visible = true
	_fish_state = "waiting"
	_fish_timer = randf_range(4.0, 11.0)
	_swing = 0.6
	Audio.play_at("splash", _fish_point, -6.0, 1.3)

func _fishing(delta: float) -> void:
	if _fish_state == "":
		return
	if Game.equipped() != "fishing_rod" or global_position.distance_to(_fish_point) > 26.0:
		_end_fishing()
		return
	_fish_timer -= delta
	var t := Time.get_ticks_msec() * 0.003
	_bobber.global_position = _fish_point + Vector3(0, sin(t) * 0.03 - (0.12 if _fish_state == "bite" else 0.0), 0)
	if _fish_state == "waiting" and _fish_timer <= 0.0:
		_fish_state = "bite"
		_fish_timer = 1.4
		Audio.play_at("splash", _fish_point, 0.0, 1.6)
		Input.vibrate_handheld(150)
	elif _fish_state == "bite" and _fish_timer <= 0.0:
		Game.notify("The fish got away...")
		_end_fishing()

func _reel() -> void:
	if _fish_state == "bite":
		var r := randf()
		if r < 0.85:
			Game.add_item("raw_fish", 1)
		elif r < 0.95:
			Game.add_item("scrap", 1)
		else:
			Game.add_item("cloth", 1)
		Audio.play("reel")
	else:
		Game.notify("Reeled in too early")
	_end_fishing()
	_cooldown = 0.8

func _end_fishing() -> void:
	_fish_state = ""
	_bobber.visible = false

# ------------------------------------------------------------------ survival
func temperature() -> float:
	return Game.world.temperature_at(global_position)

func effective_temp() -> float:
	var t := temperature()
	var near_fire: float = Game.world.fire_heat(global_position)
	t += near_fire
	var rv = Game.rv
	if rv and (driving or rv.is_inside(global_position)):
		t += 8.0
		if rv.heater_on():
			t += 14.0
	elif Game.world.is_sheltered(global_position):
		t += 6.0
	if Game.count("jacket") > 0:
		t += 12.0
	return t

func _survival(delta: float) -> void:
	_survival_acc += delta
	if _survival_acc < 0.25:
		return
	var dt := _survival_acc
	_survival_acc = 0.0
	var dr := Game.diff("drain")
	var st := Game.stats
	st["food"] = maxf(st["food"] - dt * 0.055 * dr, 0.0)
	st["water"] = maxf(st["water"] - dt * 0.075 * dr * (1.5 if temperature() > 30.0 else 1.0), 0.0)
	st["energy"] = maxf(st["energy"] - dt * 0.06 * dr, 0.0)
	var et := effective_temp()
	if et < 10.0:
		st["warmth"] = maxf(st["warmth"] - dt * (10.0 - et) * 0.05 * dr, 0.0)
	elif et > 15.0:
		st["warmth"] = minf(st["warmth"] + dt * 2.0, 100.0)
	var dmg := 0.0
	if st["food"] <= 0.0:
		dmg += 0.25
	if st["water"] <= 0.0:
		dmg += 0.4
	if st["warmth"] <= 0.0:
		dmg += 0.5
	if dmg > 0.0:
		hurt(dmg * dt * Game.diff("damage"), "exposure", false)
	elif st["food"] > 45.0 and st["water"] > 45.0 and st["warmth"] > 30.0:
		st["health"] = minf(st["health"] + dt * 0.12, 100.0)
	# night ambience
	_howl_timer -= dt
	if _howl_timer <= 0.0:
		_howl_timer = randf_range(40.0, 120.0)
		if Game.time_of_day > 20.0 or Game.time_of_day < 5.0:
			var w: Vector4 = Game.world.gen.biome_weights(global_position.x, global_position.z)
			if w.z + w.w > 0.4:
				var a := randf() * TAU
				Audio.play_at("howl", global_position + Vector3(cos(a), 0, sin(a)) * 120.0, 4.0)

func hurt(amount: float, cause: String, flash := true) -> void:
	if dead or amount <= 0.0 or Game.god_mode:
		return
	Game.stats["health"] = maxf(Game.stats["health"] - amount, 0.0)
	if flash and _hurt_cd <= 0.0:
		_hurt_cd = 0.3
		Game.world.hud.flash_damage()
		Input.vibrate_handheld(80)
	if Game.stats["health"] <= 0.0:
		die(cause)

func die(cause: String) -> void:
	if dead:
		return
	if driving:
		exit_vehicle()
	dead = true
	_end_fishing()
	Game.world.hud.show_death(cause)

func respawn() -> void:
	dead = false
	var p: Vector3
	if Game.spawn_point != null:
		p = Game.spawn_point
	else:
		p = Game.rv.global_position + Game.rv.global_transform.basis.x * 4.0 + Vector3(0, 1.5, 0)
	teleport(p + Vector3(0, 0.5, 0))
	Game.stats = {"health": 60.0, "food": 50.0, "water": 50.0, "energy": 70.0, "warmth": 80.0}
	# lose some perishables
	for k in ["raw_meat", "cooked_meat", "raw_fish", "cooked_fish", "berries"]:
		if Game.count(k) > 0:
			Game.remove_item(k, Game.count(k))
	camera.make_current()
