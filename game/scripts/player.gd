extends CharacterBody3D
## First-person survivor: movement, tools, hunting, harvesting, fishing, survival needs.

const Data = preload("res://scripts/data.gd")
const Builder = preload("res://scripts/builder.gd")
const Arrow = preload("res://scripts/arrow.gd")
const RvPart = preload("res://scripts/rv_part.gd")
const Mounts = preload("res://scripts/mounts.gd")

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
var _binocs := false # looking through the binoculars
var _held_light: OmniLight3D # torch, flare, light stick or lantern in your hand
var _held_flicker := false
var _crank_radio: AudioStreamPlayer
var nav_text := "" # what a held compass, roadmap or GPS tells you (shown by the HUD)
var _nav_acc := 0.0

# Sit in first person at a lowered camera. Furniture may travel on vehicles:
# preserve the exit position in chair-local coordinates, not world coordinates.
const SEATED_EYE := 1.12
const REST_ENERGY_PER_SECOND := 1.5
var seated_at: Node3D
var _seat_entry_local := Vector3.ZERO
var _seat_exit_world := Vector3.ZERO
var _seat_last_yaw := 0.0

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
	# E/Jump leaves the chair; mouse, stick and touch look still work while seated.
	if seated_at != null:
		if event.is_action_pressed("interact") or event.is_action_pressed("jump"):
			stand_up()
		return
	if event.is_action_pressed("hotbar_next"):
		Game.select_slot(Game.selected_slot + 1)
	elif event.is_action_pressed("hotbar_prev"):
		Game.select_slot(Game.selected_slot - 1)
	for i in range(mini(10, Game.slots.size())):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			Game.select_slot(i)
	if event.is_action_pressed("interact"):
		_interact()
	if event.is_action_pressed("pickup"):
		place_or_grab()
	if event.is_action_pressed("drop") and not driving:
		throw_held()
	if event.is_action_pressed("rotate") and not driving and not builder.active:
		if look_target and look_target.has_method("cycle_recipe") and look_target.get("type") == "workbench":
			look_target.cycle_recipe()
		elif Game.equipped() != "":
			_place_rot = wrapf(_place_rot + (PI * 0.5 if _place_module != "" else PI * 0.25), 0.0, TAU)
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
	if not Game.worn.has("flashlight") and Game.carried("flashlight") <= 0 and not Game.wears_flag("headlamp"):
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
	if seated_at != null:
		_sit_tick(delta)
		_update_prompt()
		return
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
	_update_placement()

func _move(delta: float) -> void:
	if not Game.world.ground_ready(global_position):
		return
	if _climbing:
		velocity = Vector3.ZERO
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
			if not try_climb():
				velocity.y = JUMP
			crouching = false
	var was_air := not is_on_floor()
	var fall_speed := velocity.y
	_step_up(dir)
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

## Climbing: face a vehicle, trailer, crate or wall and press [Jump] to pull yourself up onto it
## (roofs up to about 3.6 m, e.g. the van roof by its rear ladder).
var _climbing := false
const CLIMB_MAX := 3.7

func climb_target() -> Vector3:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return Vector3.INF
	fwd = fwd.normalized()
	var space := get_world_3d().direct_space_state
	var hit := {}
	for hy in [1.2, 0.6]:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, hy, 0), global_position + Vector3(0, hy, 0) + fwd * 0.95, 1 | 16)
		q.exclude = [get_rid()]
		hit = space.intersect_ray(q)
		if not hit.is_empty():
			break
	if hit.is_empty():
		return Vector3.INF
	var over: Vector3 = hit["position"] + fwd * 0.45
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(over.x, global_position.y + CLIMB_MAX + 0.4, over.z), Vector3(over.x, global_position.y + 0.45, over.z), 1 | 16)
	q2.exclude = [get_rid()]
	var top := space.intersect_ray(q2)
	if top.is_empty() or (top["normal"] as Vector3).y < 0.7:
		return Vector3.INF
	var tp: Vector3 = top["position"]
	var h := tp.y - global_position.y
	if h < 0.5 or h > CLIMB_MAX:
		return Vector3.INF
	# room to stand on top?
	var q3 := PhysicsRayQueryParameters3D.create(tp + Vector3(0, 0.05, 0), tp + Vector3(0, 1.75, 0), 1 | 16)
	q3.exclude = [get_rid()]
	if not space.intersect_ray(q3).is_empty():
		return Vector3.INF
	return tp

func try_climb() -> bool:
	if _climbing or driving:
		return false
	var tp := climb_target()
	if tp == Vector3.INF:
		return false
	_climbing = true
	velocity = Vector3.ZERO
	$CollisionShape3D.disabled = true
	var t := create_tween()
	var up := Vector3(global_position.x, tp.y + 0.1, global_position.z)
	var dur := clampf((tp.y - global_position.y) * 0.28, 0.35, 1.0)
	t.tween_property(self, "global_position", up, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", tp + Vector3(0, 0.08, 0), 0.25)
	t.tween_callback(func() -> void:
		$CollisionShape3D.disabled = false
		_climbing = false)
	Audio.play("step_wood", -6.0, 0.8)
	Game.stats["energy"] = maxf(Game.stats["energy"] - 0.5, 0.0)
	return true

## Walk up steps and kerbs (van and camper steps, door sills, porch edges) without jumping:
## when something low blocks the way, lift onto it if there is room above and floor on top.
const STEP_UP := 0.42
func _step_up(dir: Vector3) -> void:
	if not is_on_floor() or velocity.y > 0.5 or dir.length() < 0.1:
		return
	var probe := Vector3(dir.x, 0, dir.z).normalized() * 0.1
	var xf := global_transform
	if not test_move(xf, probe):
		return
	var up := Vector3(0, STEP_UP, 0)
	if test_move(xf, up):
		return
	var raised := xf.translated(up)
	if test_move(raised, probe):
		return
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), Vector3(0, -STEP_UP - 0.02, 0), col):
		return
	if col.get_normal().y < 0.7:
		return
	var rise := STEP_UP - col.get_travel().length()
	if rise < 0.04:
		return
	global_position.y += rise + 0.01

func _footstep() -> void:
	var s := "step_ground"
	var below := get_last_slide_collision()
	if below and below.get_collider() and (below.get_collider().is_in_group("structure") or below.get_collider().is_in_group("rv")):
		s = "step_wood"
	elif Game.world.gen.biome_weights(global_position.x, global_position.z).w > 0.5:
		s = "step_snow"
	Audio.play(s, -10.0 if not crouching else -18.0, randf_range(0.9, 1.1))

func sit_in(seat: Node3D) -> void:
	if dead or driving or _climbing or not is_instance_valid(seat):
		return
	if seated_at != null:
		stand_up()
	seated_at = seat
	_seat_entry_local = seat.to_local(global_position)
	_seat_exit_world = global_position
	_seat_last_yaw = seat.global_rotation.y
	crouching = false
	velocity = Vector3.ZERO
	$CollisionShape3D.disabled = true
	rotation.y = _seat_last_yaw
	global_position = seat.to_global(Vector3(0.0, 0.0, -0.06))
	head.position = Vector3(0.0, SEATED_EYE, 0.0)
	viewmodel.visible = false
	_set_highlight(null)
	Game.notify("Sitting — energy recovering. E or Jump to stand up.")

func _sit_tick(delta: float) -> void:
	if not is_instance_valid(seated_at) or seated_at.is_queued_for_deletion():
		stand_up()
		return
	var yaw := seated_at.global_rotation.y
	rotate_y(wrapf(yaw - _seat_last_yaw, -PI, PI))
	_seat_last_yaw = yaw
	global_position = seated_at.to_global(Vector3(0.0, 0.0, -0.06))
	_seat_exit_world = seated_at.to_global(_seat_entry_local)
	velocity = Vector3.ZERO
	if not Game.paused and not Game.ui_open:
		var multiplier := 1.4 if seated_at.has_method("aim_name") and str(seated_at.get("type")) == "sofa" else 1.0
		Game.stats["energy"] = minf(Game.stats["energy"] + delta * REST_ENERGY_PER_SECOND * multiplier, 100.0)

func stand_up() -> void:
	if seated_at == null:
		return
	if is_instance_valid(seated_at) and not seated_at.is_queued_for_deletion():
		_seat_exit_world = seated_at.to_global(_seat_entry_local)
	seated_at = null
	global_position = _seat_exit_world
	velocity = Vector3.ZERO
	$CollisionShape3D.disabled = false
	head.position = Vector3(0.0, EYE, 0.0)
	viewmodel.visible = true

func teleport(p: Vector3) -> void:
	if seated_at != null:
		stand_up()
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
	if seated_at != null:
		_set_highlight(null)
		prompt = "Seated — energy recovering   [E] / [Jump] Stand up"
		return
	if driving:
		_set_highlight(null)
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
	_set_highlight(look_target)
	if prompt == "" and ray.is_colliding():
		var rc: Object = ray.get_collider()
		var in_van: bool = Game.rv != null and Game.rv.is_inside(global_position)
		if rc and not in_van and (rc.is_in_group("rv") or rc.is_in_group("vehicle")) and climb_target() != Vector3.INF:
			prompt = "[Space / JUMP] Climb up"
	var held := Game.equipped()
	if _place_module != "" and not builder.active:
		var nm: String = Data.VAN_SLOTS[_place_module]["name"]
		prompt = ("[G] Fit the %s here   [R] Turn it" % nm.to_lower()) if _module_plan.get("ok", false) else "%s — %s   [R] Turn it" % [nm, _module_plan.get("reason", "")]
	elif held != "" and not builder.active and _place_valid and (look_target == null or not look_target.is_in_group("world_item")):
		var hint := "[G] Place %s   [R] Rotate   [Q] Throw" % Data.item_name(held)
		prompt = hint if prompt == "" else prompt + "\n" + hint
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
	# fitting van furniture where you aim beats the hotspot under the crosshair
	if _place_module != "" and (look_target == null or (look_target.get_script() == RvPart and str(look_target.action).begins_with("mount:"))):
		place_held()
		return
	if look_target == null:
		return
	if look_target.has_method("interact"):
		look_target.interact(self)
	elif look_target.has_meta("res_kind") and look_target.get_meta("res_kind") == "bush":
		Game.world.harvest_bush(look_target)
	elif look_target.has_meta("res_kind") and look_target.get_meta("res_kind") == "pickup":
		var item: String = look_target.get_meta("item")
		if Game.hands_full_for(item):
			Game.notify("Your hands are full — place [G] or drop [Q] something first")
			return
		Game.add_item(item, 1)
		Audio.play("pickup", -6.0)
		Net.mark_removed(look_target.get_meta("res_key"), true)

var _hl_node: Node = null

func _set_highlight(t: Object) -> void:
	var n: Node = t as Node if is_instance_valid(t) and t.has_method("set_highlight") else null
	if n == _hl_node:
		return
	if _hl_node and is_instance_valid(_hl_node):
		_hl_node.set_highlight(false)
	_hl_node = n
	if n:
		n.set_highlight(true)

## G: place what you hold exactly where the preview shows, or — with empty hands — pick up
## placed furniture (crate, chair, campfire...) to carry it somewhere else.
func place_or_grab() -> void:
	if driving or dead:
		return
	if builder.active and builder.kit != "":
		builder.place()
		return
	if Game.equipped() != "":
		place_held()
		return
	if look_target == null:
		return
	var t := look_target as Node
	if t.is_in_group("world_item"):
		t.interact(self)
		return
	# pull a fitted battery or tire off a vehicle
	if t.get_script() == RvPart and t.action == "hood" and t.rv.has_method("remove_engine"):
		t.rv.remove_engine()
		return
	if t.get_script() == RvPart and (t.action == "battery" or t.action.begins_with("wheel")):
		Mounts.pull(t.rv, t.action)
		return
	# take a fitted module back out of the van
	if t.get_script() == RvPart and t.rv.has_method("slot_for"):
		var slot: String = t.rv.slot_for(t)
		if slot != "":
			t.rv.remove_module(slot)
		return
	if t.get_script() == Builder.Structure and t.is_in_group("placeable"):
		if Game.space_for(t.type) <= 0:
			Game.notify("Your hands are full — place [G] or drop [Q] something first")
			return
		var type: String = t.type
		# Carry a portable object's state with it, including liquids and live plants.
		var carried_state: Dictionary = t.data.duplicate(true)
		var contents: Array = []
		if type == "crate":
			contents = _crate_contents(t)
		if t.has_meta("rv_rec"):
			t.get_meta("host").detach_structure(t)
		elif t.persistent:
			Net.remove_structure(t.id)
		else:
			return
		Game.add_item(type, 1, true)
		if not carried_state.is_empty():
			for sl in Game.slots:
				if sl["id"] == type and not sl.has("sd") and not sl.has("c"):
					sl["sd"] = carried_state
					break
			Game._changed()
		if not contents.is_empty():
			for sl in Game.slots:
				if sl["id"] == "crate" and not sl.has("c"):
					sl["c"] = contents
					break
			Game.notify("Picked up the crate with %d things inside" % contents.size())
		else:
			Game.notify("Picked up %s" % Data.item_name(type))
		Audio.play("pickup")

## Items lying inside a crate come along when you carry the crate.
func _crate_contents(crate: Node3D) -> Array:
	var out := []
	var inv := crate.global_transform.affine_inverse()
	for it in get_tree().get_nodes_in_group("world_item"):
		if not is_instance_valid(it) or it.is_queued_for_deletion():
			continue
		var l: Vector3 = inv * it.global_position
		if absf(l.x) < 0.56 and absf(l.z) < 0.36 and l.y > 0.0 and l.y < 0.95:
			var lx: Transform3D = inv * it.global_transform
			out.append({"id": it.id, "n": it.amount, "pos": Game.arr(lx.origin), "rot": Game.arr(lx.basis.get_euler())})
			it.queue_free()
	return out

func throw_held() -> void:
	if Game.equipped() == "":
		return
	if builder.active and builder.kit != "":
		builder.stop()
	var s := Game.take_held()
	if s["id"] == "":
		return
	var fwd := -camera.global_transform.basis.z
	var it = Game.spawn_item(s["id"], int(s["n"]), camera.global_position + fwd * 0.7 + Vector3(0, -0.25, 0), fwd * 4.0)
	if it and s.has("c"):
		it.contents = s["c"]
	Audio.play("click", -8.0, 0.7)

func drop_item(id: String, n := 1) -> void:
	if Game.carried(id) < n or not Game.remove_item(id, n):
		return
	var fwd := -camera.global_transform.basis.z
	Game.spawn_item(id, n, camera.global_position + fwd * 0.8 + Vector3(0, -0.3, 0), fwd * 1.5)

# ------------------------------------------------------------------ placing held items
var _place_ghost: Node3D
var _place_ghost_id := ""
var _place_rot := 0.0
var _place_valid := false
var _place_xf := Transform3D()
var _place_host: Node = null
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _place_module := "" # free van furniture being aimed at the van floor
var _module_plan := {}

func _host_of(n: Node) -> Node:
	for i in range(7):
		if n == null:
			return null
		if n.get_node_or_null("Cargo") != null and (n is VehicleBody3D or n.has_method("contains_point")):
			return n
		n = n.get_parent()
	return null

func _update_placement() -> void:
	var id := Game.equipped()
	var kind: String = Data.ITEMS.get(id, {}).get("kind", "")
	_place_valid = false
	var was_module := _place_module
	_place_module = ""
	if was_module != "":
		viewmodel.visible = true
	_module_plan = {}
	if id == "" or kind == "placeable" or builder.active or Game.ui_open or _fish_state != "":
		if _place_ghost:
			_place_ghost.visible = false
		if was_module != "" and Game.rv:
			Game.rv.hide_free_preview()
		return
	if _place_ghost_id != id:
		if _place_ghost:
			_place_ghost.queue_free()
		_place_ghost = Items.display_instance(id)
		_place_ghost.top_level = true
		_set_no_shadow(_place_ghost)
		add_child(_place_ghost)
		_place_ghost_id = id
		if _ghost_ok == null:
			_ghost_ok = StandardMaterial3D.new()
			_ghost_ok.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
			_ghost_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ghost_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_ghost_bad = _ghost_ok.duplicate()
			_ghost_bad.albedo_color = Color(1.0, 0.35, 0.3, 0.4)
	# cast from the eyes, skipping interaction hotspots (seats, stove...) so you can set
	# things on the counter, dashboard, shelves, table or the floor of any vehicle
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 3.4
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 16 | 32)
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	var hit := {}
	for k in range(6):
		hit = space.intersect_ray(q)
		if hit.is_empty():
			break
		var col: Object = hit["collider"]
		if col.get_script() == RvPart or col.is_in_group("animal") or (col is Area3D):
			ex.append(col.get_rid())
			q.exclude = ex
			continue
		break
	# van furniture: aim at the van floor and it goes exactly there
	var free_slot: String = Game.rv.free_slot_for(id) if Game.rv and kind == "module" else ""
	if free_slot != "" and not hit.is_empty() and _host_of(hit["collider"] as Node) == Game.rv and Game.rv.is_inside(hit["position"]) and (hit["normal"] as Vector3).y > 0.6:
		var rv = Game.rv
		var lp: Vector3 = rv.to_local(hit["position"])
		if lp.y < rv.FLOOR_Y + 0.4:
			_place_module = free_slot
			_module_plan = rv.plan_free(free_slot, lp, _place_rot, rv.to_local(global_position))
			_place_valid = _module_plan["ok"]
			_place_ghost.visible = false
			rv.preview_free(free_slot, _module_plan)
			viewmodel.visible = false # the big piece in your arms would hide the preview
			return
	if was_module != "" and Game.rv:
		Game.rv.hide_free_preview()
	if hit.is_empty():
		_place_ghost.visible = false
		return
	var n: Vector3 = hit["normal"]
	var bb: AABB = Items.display_bounds(id)
	var basis := Basis(Vector3.UP, rotation.y + PI + _place_rot)
	var pos: Vector3 = hit["position"]
	if n.y > 0.6:
		pos -= Vector3(0, bb.position.y - 0.005, 0)
		_place_valid = true
	elif n.y < -0.6 and Data.ITEMS.get(id, {}).get("hang", false):
		# hang cab decor from the ceiling or the mirror
		pos -= Vector3(0, bb.end.y + 0.005, 0)
		_place_valid = true
	else:
		# against a wall: stand it on the floor next to the wall would be guesswork — show red
		pos += n * (maxf(bb.size.x, bb.size.z) * 0.5)
	_place_host = _host_of(hit["collider"] as Node)
	_place_xf = Transform3D(basis, pos)
	_place_ghost.global_transform = _place_xf
	# only show where it would go; a red ghost stuck to walls was just in the way
	_place_ghost.visible = _place_valid
	_paint_ghost(_place_ghost, _ghost_ok)

func _paint_ghost(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m
	for c in n.get_children():
		_paint_ghost(c, m)

func place_held() -> void:
	if _place_module != "":
		if Game.rv.install_free(_place_module, _module_plan):
			_place_module = ""
		return
	if not _place_valid:
		Game.notify("Aim at a flat surface within reach to place it")
		return
	var s := Game.take_held()
	if s["id"] == "":
		return
	Game.place_item(s["id"], int(s["n"]), _place_xf, _place_host, s.get("c", []))
	Audio.play_at("pickup", _place_xf.origin, -6.0, 0.8)

func enter_vehicle(rv: Node, as_driver: bool) -> void:
	if seated_at != null:
		stand_up()
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
	_binocs = false
	for c in viewmodel.get_children():
		c.queue_free()
	_aiming = false
	# grip pose per item: [position, rotation, scale]
	var pose := [Vector3(0.0, 0.0, 0.0), Vector3(-0.35, 0.15, 0.08), 1.0]
	var grip: String = Data.ITEMS.get(id, {}).get("grip", "")
	if grip == "" and Data.ITEMS.get(id, {}).has("reach"):
		grip = "long"
	match grip:
		"long":
			pose = [Vector3(0, 0, 0), Vector3(-0.45, 0.2, 0.15), 1.0]
		"knife":
			pose = [Vector3(0, 0, 0), Vector3(-0.75, 0.25, 0.1), 1.2 if id == "knife" else 0.9]
		"gun":
			pose = [Vector3(-0.1, 0.04, -0.2), Vector3(-PI * 0.5, 0.0, 0.0), 1.0]
		"pistol":
			pose = [Vector3(-0.12, 0.0, -0.16), Vector3(-PI * 0.5, 0.0, 0.0), 1.15]
		"bow":
			pose = [Vector3(-0.2, 0.08, -0.08), Vector3(-0.05, 0.0, 0.25), 1.0]
		"small":
			pose = [Vector3(0, 0.0, -0.02), Vector3(-0.3, 0.2, 0.0), 1.0]
	if Data.ITEMS.get(id, {}).has("light") and grip == "":
		pose = [Vector3(0, -0.02, 0), Vector3(-0.25, 0.1, 0.05), 1.0]
	match id:
		"axe", "pickaxe", "hammer", "crowbar":
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
			# carried objects: held out in front, big enough to see what you have
			# (tools, guns and lights keep the grip pose chosen above)
			if grip == "" and not Data.ITEMS.get(id, {}).has("light"):
				var bb: AABB = Items.bounds(id)
				var big := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
				var k := clampf(0.2 / maxf(big, 0.01), 0.35, 1.5)
				pose = [Vector3(-0.1 - big * k * 0.25, -0.05, -0.08 - big * k * 0.2), Vector3(0.15, 0.5, 0.0), k]
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
	_held_light = null
	var lit: Dictionary = Data.ITEMS.get(id, {})
	if lit.has("light"):
		var bbl: AABB = Items.bounds(id)
		_held_light = Lib.light(viewmodel, Vector3(0, bbl.end.y * 0.8, -0.1), lit["light"], float(lit.get("light_energy", 2.0)), float(lit.get("light_range", 9.0)))
		_held_flicker = lit.get("flicker", false)
		if id in ["torch", "road_flare"]:
			var fl := CPUParticles3D.new()
			fl.amount = 18
			fl.lifetime = 0.35
			fl.local_coords = true
			fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			fl.emission_sphere_radius = 0.02
			fl.direction = Vector3.UP
			fl.spread = 18.0
			fl.gravity = Vector3(0, 0.6, 0)
			fl.initial_velocity_min = 0.08
			fl.initial_velocity_max = 0.2
			fl.scale_amount_min = 0.5
			fl.scale_amount_max = 1.0
			var qm := QuadMesh.new()
			qm.size = Vector2(0.035, 0.035)
			var fm := StandardMaterial3D.new()
			var soft := GradientTexture2D.new()
			soft.fill = GradientTexture2D.FILL_RADIAL
			soft.fill_from = Vector2(0.5, 0.5)
			soft.fill_to = Vector2(1.0, 0.5)
			var sg := Gradient.new()
			sg.set_color(0, Color(1, 1, 1, 1))
			sg.set_color(1, Color(1, 1, 1, 0))
			soft.gradient = sg
			soft.width = 32
			soft.height = 32
			fm.albedo_texture = soft
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			fm.vertex_color_use_as_albedo = true
			fm.albedo_color = Color(1.0, 0.55, 0.2) if id == "torch" else Color(1.0, 0.25, 0.2)
			qm.material = fm
			fl.mesh = qm
			fl.position = Vector3(0, bbl.end.y - 0.02, 0)
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 0.9, 0.5, 1))
			grad.set_color(1, Color(1, 0.2, 0.05, 0))
			fl.color_ramp = grad
			viewmodel.add_child(fl)
	if _crank_radio and id != "camp_handcrank_radio":
		_crank_radio.stop()
	nav_text = ""
	var grip2: String = Data.ITEMS.get(id, {}).get("grip", "")
	if id in ["bow", "rifle"] or grip2 in ["gun", "bow"]:
		var left := MeshInstance3D.new()
		left.mesh = Items.arm_mesh()
		left.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		left.scale = Vector3(-1, 1, 1)
		left.position = Vector3(-0.3, 0.06, -0.12) if grip2 == "bow" else Vector3(-0.1, 0.03, -0.32)
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
	var it_d: Dictionary = Data.ITEMS.get(id, {})
	var can_aim: bool = id == "binoculars" or it_d.has("ammo") or it_d.get("grip", "") == "bow"
	var aiming := Input.is_action_pressed("secondary") and can_aim and not Game.ui_open
	if Game.world.touch and Game.world.touch.aim_on and can_aim:
		aiming = true
	if id == "binoculars" and _binocs:
		aiming = true
	var target_fov: float = Game.settings["fov"] * (float(it_d.get("zoom", 0.8)) if aiming and it_d.has("ammo") else (0.25 if aiming and id == "binoculars" else (0.8 if aiming else 1.0)))
	if _held_light and _held_flicker:
		_held_light.light_energy = float(it_d.get("light_energy", 2.0)) * (0.85 + randf() * 0.3)
	_nav_acc -= delta
	if _nav_acc <= 0.0:
		_nav_acc = 0.5
		nav_text = _nav_reading(id)
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
	if it.has("ammo"):
		var am: String = it["ammo"]
		if Game.remove_item(am, 1):
			for k in range(int(it.get("pellets", 1))):
				_shoot(float(it["damage"]), float(it.get("spread", 0.012)), k == 0)
		else:
			Audio.play("click")
			Game.notify("Out of ammo: needs %s" % Data.item_name(am))
		_cooldown = float(it.get("rate", 1.0))
		return
	if it.get("grip", "") == "bow":
		if Game.remove_item("arrow", 1):
			var a := Node3D.new()
			a.set_script(Arrow)
			Game.world.add_child(a)
			a.launch(camera.global_position + camera.global_transform.basis * Vector3(0, -0.05, -0.4), -camera.global_transform.basis.z * float(it.get("arrow_speed", 58.0)), float(it["damage"]), self)
			Audio.play("bow")
			_swing = 0.3
		else:
			Game.notify("No arrows. Craft some from wood, stone and feathers.")
		_cooldown = 0.9 if id == "bow" else 0.7
		return
	if it.has("nav"):
		if it["nav"] == "radio":
			_toggle_crank_radio()
		elif it["nav"] == "map":
			Game.notify(_map_reading())
		_cooldown = 0.4
		return
	if it.has("reach"):
		_melee(float(it["damage"]), float(it.get("reach", 2.4)), id)
		_cooldown = 0.45 if it.get("grip", "") == "knife" else (0.9 if float(it["damage"]) >= 40.0 else 0.6)
		return
	match id:
		"fishing_rod":
			_cast()
			_cooldown = 0.6
		"flashlight":
			toggle_flashlight()
			_cooldown = 0.3
		"binoculars":
			_binocs = not _binocs
			_cooldown = 0.3
		_:
			if it.get("kind", "") in ["food", "medical", "purify"]:
				Game.consume(id)
				_cooldown = 0.8
			elif it.get("kind", "") == "wear":
				Game.wear(id)
				_cooldown = 0.5
			elif id == "bottle_empty":
				_fill_bottle()
				_cooldown = 0.6
			else:
				_cooldown = 0.3

func _toggle_crank_radio() -> void:
	if _crank_radio == null:
		_crank_radio = AudioStreamPlayer.new()
		_crank_radio.bus = "Vehicle"
		_crank_radio.volume_db = -8.0
		add_child(_crank_radio)
	if _crank_radio.playing:
		_crank_radio.stop()
		Game.notify("Radio off")
		return
	Audio.play("click", -4.0)
	_crank_radio.stream = Audio.stream("radio_%d" % (randi() % 3), true)
	_crank_radio.play(randf() * 20.0)
	Game.notify("You wind the crank and the radio crackles into life")

const _POI_NAMES := {"gas_station": "Gas station", "house": "House", "wrecks": "Car wrecks", "camp_ruin": "Old camp", "cabin": "Cabin",
	"farm": "Farm", "hamlet": "Hamlet", "truck_stop": "Truck stop"}

## The roadmap shows the stops marked along the highway near you.
func _map_reading() -> String:
	var gen = Game.world.gen
	var here := int(floor(global_position.z / gen.CHUNK))
	var found := []
	for d in range(0, 40):
		for ci in [here + d, here - d]:
			if d == 0 and ci != here:
				continue
			var poi: Dictionary = gen.poi_for_row(ci)
			if poi.is_empty():
				continue
			var to: Vector3 = poi["pos"] - global_position
			found.append("%s %.1f km %s" % [_POI_NAMES.get(poi["type"], "Stop"), to.length() / 1000.0, "north" if to.z < 0.0 else "south"])
		if found.size() >= 4:
			break
	if found.is_empty():
		return "The map shows nothing but road for miles"
	return "Roadmap: " + " · ".join(found.slice(0, 4))

## What a held compass or GPS reads right now.
func _nav_reading(id: String) -> String:
	var it: Dictionary = Data.ITEMS.get(id, {})
	var nav: String = it.get("nav", "")
	var fwd := -camera.global_transform.basis.z
	var deg := int(round(rad_to_deg(wrapf(atan2(fwd.x, -fwd.z), 0.0, TAU)))) % 360
	match nav:
		"compass":
			var to: Vector3 = (Game.rv.global_position - global_position) if Game.rv else Vector3.ZERO
			var vd := int(round(rad_to_deg(wrapf(atan2(to.x, -to.z), 0.0, TAU)))) % 360
			return "Compass: heading %03d°   ·   van bearing %03d°, %d m" % [deg, vd, int(to.length())]
		"gps":
			var gen = Game.world.gen
			var here := int(floor(global_position.z / gen.CHUNK))
			var best := ""
			var best_d := INF
			for d in range(-30, 31):
				var poi: Dictionary = gen.poi_for_row(here + d)
				if not poi.is_empty() and poi["type"] in ["gas_station", "truck_stop"]:
					var dd: float = (poi["pos"] - global_position).length()
					if dd < best_d:
						best_d = dd
						best = "%s %.1f km %s" % [_POI_NAMES[poi["type"]], dd / 1000.0, "north" if poi["pos"].z < global_position.z else "south"]
			return "GPS: %03d°   ·   nearest fuel: %s" % [deg, best if best != "" else "none in range"]
	if Game.wears_flag("altimeter"):
		return ""
	return ""

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
		var td: Dictionary = Data.ITEMS.get(tool, {})
		if kind == "tree":
			if float(td.get("chop", 0.0)) <= 0.0:
				Game.notify("You need a hatchet, axe or saw to chop trees")
				Audio.play_at("hit", hit["position"], -6.0)
				return
			Audio.play_at("chop", hit["position"])
			Game.world.hit_resource(col, hit["position"], float(td["chop"]))
		elif kind == "rock":
			if float(td.get("mine", 0.0)) <= 0.0:
				Game.notify("You need a pickaxe or sledge hammer to break rock")
				Audio.play_at("hit", hit["position"], -6.0, 1.4)
				return
			Audio.play_at("hit", hit["position"], 0.0, 1.5)
			Game.world.hit_resource(col, hit["position"], float(td["mine"]))
		elif kind == "bush":
			Game.world.harvest_bush(col)
		return
	Audio.play_at("hit", hit["position"], -8.0, 1.2)

func _shoot(dmg: float, base_spread := 0.012, fx := true) -> void:
	if fx:
		Audio.play("gunshot")
		_swing = 0.35
		var flash := Lib.light(camera, Vector3(0, 0, -1), Color(1, 0.8, 0.5), 4.0, 8.0)
		get_tree().create_timer(0.06).timeout.connect(flash.queue_free)
		Game.world.alert_animals(global_position, 110.0)
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * (base_spread * 0.2 if Input.is_action_pressed("secondary") and base_spread < 0.03 else base_spread)
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

## Use an empty bottle while standing at a lake or river: it fills with dirty water.
func _fill_bottle() -> void:
	var gen = Game.world.gen
	var fwd := -camera.global_transform.basis.z
	for k in range(0, 5):
		var t: Vector3 = global_position + Vector3(fwd.x, 0, fwd.z).normalized() * float(k) * 0.8
		if gen.is_water(t.x, t.z, 0.2):
			Game.remove_item("bottle_empty", 1)
			Game.add_item("water_dirty", 1, true)
			Audio.play_at("splash", t, -6.0, 1.2)
			Game.notify("Filled the bottle with lake water. Boil it on a fire or filter it into the van's tank.")
			return
	Game.notify("Stand at the water's edge to fill the bottle (or use a sink, well or rain collector)")

# ------------------------------------------------------------------ survival
func temperature() -> float:
	return Game.world.temperature_at(global_position)

func effective_temp() -> float:
	var t := temperature()
	var near_fire: float = Game.world.fire_heat(global_position)
	t += near_fire
	var rv = Game.rv
	if rv and (driving or rv.is_inside(global_position)):
		t += rv.shelter_bonus() if rv.has_method("shelter_bonus") else 8.0
		if rv.heater_on():
			t += 14.0
	elif Game.world.is_sheltered(global_position):
		t += 6.0
	t += Game.worn_stat("insulation")
	if Game.weather == "rain" and Game.wears_flag("rain"):
		t += 5.0
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
	if cause != "exposure":
		amount *= 1.0 - minf(Game.worn_stat("armor"), 0.6)
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
	if seated_at != null:
		stand_up()
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
	for i in range(Game.slots.size()):
		if Game.slots[i]["id"] in ["raw_meat", "cooked_meat", "raw_fish", "cooked_fish", "berries"]:
			Game.slots[i] = {"id": "", "n": 0}
	Game._changed()
	camera.make_current()
