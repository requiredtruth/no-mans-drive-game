extends RigidBody3D
## A physical item lying in the world. Pick it up with E (interact) or G (grab).

var id := ""
var amount := 1
var _check := 0.0
var _attached := false

func setup(p_id: String, n: int) -> void:
	id = p_id
	amount = n
	collision_layer = 32
	collision_mask = 1 | 16 | 32
	mass = 2.0
	continuous_cd = false
	can_sleep = true
	add_to_group("world_item")
	var model := Items.instance(id)
	add_child(model)
	var acc := [null]
	for ch in model.get_children():
		Items._aabb_of(ch, model.transform, acc)
	var bb: AABB = acc[0] if acc[0] != null else AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
	var size := bb.size.max(Vector3.ONE * 0.06)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = bb.get_center()
	add_child(cs)

func get_prompt() -> String:
	return "[E] Pick up %s%s" % [Game.Data.item_name(id), (" ×%d" % amount) if amount > 1 else ""]

func interact(_player: Node) -> void:
	Game.add_item(id, amount)
	Audio.play("pickup", -4.0)
	queue_free()

func _physics_process(delta: float) -> void:
	if _attached or Game.world == null:
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
	# Items that come to rest inside or on the RV ride along with it.
	var rv = Game.rv
	if rv and linear_velocity.length() < 0.2 and rv.contains_point(global_position):
		_attached = true
		var xf := global_transform
		get_parent().remove_child(self)
		rv.get_node("Cargo").add_child(self)
		global_transform = xf
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
		collision_mask = 0

func save_record() -> Dictionary:
	return {"id": id, "n": amount, "pos": Game.arr(global_position), "rot": Game.arr(global_rotation)}
