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

func save_record() -> Dictionary:
	var r := {"id": id, "n": amount, "pos": Game.arr(global_position), "rot": Game.arr(global_rotation)}
	if placed:
		r["placed"] = true
	if not contents.is_empty():
		r["c"] = contents
	return r
