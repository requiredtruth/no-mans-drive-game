extends Node3D
## Ballistic arrow projectile.

var vel := Vector3.ZERO
var damage := 60.0
var shooter: Node
var stuck := false
var life := 25.0

func launch(from: Vector3, v: Vector3, dmg: float, by: Node) -> void:
	global_position = from
	vel = v
	damage = dmg
	shooter = by
	var shaft := Lib.box(self, Vector3(0, 0, 0), Vector3(0.015, 0.015, 0.75), Lib.color_mat(Color(0.55, 0.4, 0.25)))
	shaft.position.z = 0.0
	Lib.box(self, Vector3(0, 0, -0.38), Vector3(0.03, 0.03, 0.06), Lib.color_mat(Color(0.3, 0.3, 0.3), 0.3, 0.8))
	Lib.box(self, Vector3(0, 0, 0.33), Vector3(0.002, 0.06, 0.1), Lib.color_mat(Color(0.9, 0.9, 0.85)))
	look_at(global_position + vel, Vector3.UP)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if stuck:
		return
	vel.y -= 9.8 * delta
	var next := global_position + vel * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, next, 1 | 8 | 16)
	if shooter:
		q.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		stuck = true
		var col: Object = hit["collider"]
		if col.is_in_group("animal"):
			col.take_damage(damage * clampf(vel.length() / 50.0, 0.5, 1.2), shooter.global_position if shooter else global_position)
			Audio.play_at("hit", global_position)
			queue_free()
		else:
			Audio.play_at("hit", global_position, -8.0, 1.6)
			life = 15.0
		return
	if vel.length() > 0.1:
		look_at(next + vel, Vector3.UP)
	global_position = next
