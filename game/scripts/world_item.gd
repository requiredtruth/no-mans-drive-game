extends RigidBody3D
## A physical item in the world. Look at it and press E to pick it up into your hands.
## Items you place with G stay exactly where you put them; items placed (or that come to rest)
## inside a vehicle or trailer are glued to it and ride along while you drive.

var id := ""
var amount := 1
var placed := false # set down on purpose: frozen in place
var contents: Array = [] # a carried crate's contents (unused for most items)
var _check := 0.0
var _attached := false
var _model: Node3D
var _hl := false
var _label: Label3D

func setup(p_id: String, n: int) -> void:
	id = p_id
	amount = n
	collision_layer = 32
	collision_mask = 1 | 16 | 32
	mass = 2.0
	continuous_cd = false
	can_sleep = true
	add_to_group("world_item")
	_model = Items.display_instance(id)
	add_child(_model)
	var bb: AABB = Items.display_bounds(id)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bb.size.max(Vector3.ONE * 0.08)
	cs.shape = sh
	cs.position = bb.get_center()
	add_child(cs)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 42
	_label.outline_size = 10
	_label.pixel_size = 0.0022
	_label.position = Vector3(0, bb.end.y + 0.12, 0)
	_label.visible = false
	add_child(_label)
	refresh_label()

func refresh_label() -> void:
	if _label:
		_label.text = Game.Data.item_name(id) + ((" ×%d" % amount) if amount > 1 else "")

## Highlight while the player looks at it, so small things are easy to spot.
func set_highlight(on: bool) -> void:
	if on == _hl:
		return
	_hl = on
	_label.visible = on
	Items.set_glow(_model, on)

func get_prompt() -> String:
	var nm := "%s%s" % [Game.Data.item_name(id), (" ×%d" % amount) if amount > 1 else ""]
	if Game.hands_full_for(id):
		return "%s — hands full ([G] place / [Q] drop what you hold)" % nm
	return "[E] Pick up %s" % nm

func interact(_player: Node) -> void:
	if Game.pick_up(self):
		Audio.play_at("pickup", global_position, -4.0)

## Freeze in place, glued to a vehicle if one is given (or found under the item).
func settle(host: Node = null) -> void:
	placed = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if host == null:
		host = _vehicle_at(global_position)
	if host and host.get_node_or_null("Cargo"):
		_glue(host)

func _glue(host: Node) -> void:
	_attached = true
	var xf := global_transform
	if get_parent():
		get_parent().remove_child(self)
	host.get_node("Cargo").add_child(self)
	global_transform = xf
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_mask = 0

func _vehicle_at(p: Vector3) -> Node:
	for v in [Game.rv] + get_tree().get_nodes_in_group("vehicle"):
		if v and is_instance_valid(v) and v.has_method("contains_point") and v.contains_point(p):
			return v
	return null

func _physics_process(delta: float) -> void:
	if _attached or placed or Game.world == null:
		return
	if not Game.world.ground_ready(global_position):
		freeze = true
		return
	elif freeze:
		freeze = false
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if global_position.y < -300.0:
		queue_free()
		return
	# Thrown items that come to rest inside or on a vehicle ride along with it.
	if linear_velocity.length() > 0.2:
		return
	var host := _vehicle_at(global_position)
	if host:
		_glue(host)

# ---- hanging cab decor (dice, dreamcatcher, bells...) swings as the vehicle moves
var _hung := -1 # -1 unknown, 0 no, 1 yes
var _sway := Vector2.ZERO
var _sway_v := Vector2.ZERO
var _last_host_pos := Vector3.ZERO
var _last_host_vel := Vector3.ZERO

func _process(delta: float) -> void:
	if not placed or _model == null or delta <= 0.0:
		return
	if _hung == -1:
		_hung = 0
		if Game.Data.ITEMS.get(id, {}).get("hang", false):
			var bb: AABB = Items.display_bounds(id)
			var top := global_position + global_transform.basis.y * bb.end.y
			var q := PhysicsRayQueryParameters3D.create(top - Vector3(0, 0.02, 0), top + Vector3(0, 0.08, 0), 1 | 16)
			q.exclude = [get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				_hung = 1
				set_meta("top", bb.end.y)
	if _hung != 1:
		return
	var host: Node3D = get_parent().get_parent() if _attached else null
	var acc := Vector3.ZERO
	if host:
		var hv := (host.global_position - _last_host_pos) / delta
		if _last_host_pos != Vector3.ZERO and hv.length() < 80.0:
			acc = (hv - _last_host_vel) / delta
			_last_host_vel = hv
		_last_host_pos = host.global_position
	var la := global_transform.basis.inverse() * acc
	# a damped pendulum pushed by the vehicle's acceleration (and a little road shake)
	var push := Vector2(la.z, -la.x) * 0.012
	if host and _last_host_vel.length() > 2.0:
		push += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 0.04
	_sway_v += (push - _sway * 14.0) * delta * 6.0
	_sway_v *= exp(-delta * 1.6)
	_sway += _sway_v * delta
	_sway = _sway.clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
	var top_y: float = get_meta("top", 0.0)
	var b := Basis.from_euler(Vector3(_sway.x, 0, _sway.y))
	var pivot := Vector3(0, top_y, 0)
	_model.transform = Transform3D(b, pivot - b * pivot)

func save_record() -> Dictionary:
	var r := {"id": id, "n": amount, "pos": Game.arr(global_position), "rot": Game.arr(global_rotation)}
	if placed:
		r["placed"] = true
	if not contents.is_empty():
		r["c"] = contents
	return r
