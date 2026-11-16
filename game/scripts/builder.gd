extends Node3D
## Building mode: ghost preview, grid snapping, rotation, placement and demolition.

const Data = preload("res://scripts/data.gd")
const Structure = preload("res://scripts/structure.gd")
const GRID := 3.0
const EDGE_TYPES := ["wall", "doorway", "window", "fence"]
const FLOOR_TYPES := ["foundation", "floor", "roof", "roof_slope", "stairs"]

var player: Node
var active := false
var piece_index := 0
var user_rot := 0.0
var _ghost: Node3D
var _ghost_type := ""
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var valid := false
var reason := ""
var placement := {}
var _cd := 0.0

func _ready() -> void:
	_ok_mat = StandardMaterial3D.new()
	_ok_mat.albedo_color = Color(0.3, 0.9, 0.4, 0.4)
	_ok_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ok_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bad_mat = _ok_mat.duplicate()
	_bad_mat.albedo_color = Color(0.95, 0.25, 0.2, 0.4)

func piece() -> String:
	return Data.PIECE_ORDER[piece_index]

var kit := "" # when placing a carried object instead of paying the build cost

## Start building the given piece (from the build menu).
func select(i: int) -> void:
	piece_index = wrapi(i, 0, Data.PIECE_ORDER.size())
	kit = ""
	active = true

## Start placing a carried object (crate, campfire...) from the inventory.
func place_kit(id: String) -> void:
	var idx := Data.PIECE_ORDER.find(id)
	if idx < 0:
		return
	piece_index = idx
	kit = id
	active = true

func stop() -> void:
	active = false
	kit = ""
	if _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_type = ""

func set_active(on: bool) -> void:
	if not on:
		stop()

func _make_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
	var g := StaticBody3D.new()
	g.set_script(Structure)
	g.persistent = false
	g.setup("", {"type": piece(), "pos": [0, 0, 0], "rot": 0.0, "data": {"depth": 1.2, "fuel": 0.0}})
	g.collision_layer = 0
	g.collision_mask = 0
	g.process_mode = Node.PROCESS_MODE_DISABLED
	g.remove_from_group("structure")
	g.remove_from_group("roof")
	g.remove_from_group("placeable")
	add_child(g)
	_strip(g)
	_ghost = g
	_ghost_type = piece()

func _strip(n: Node) -> void:
	for c in n.get_children():
		if c is Light3D or c is CPUParticles3D or c is AudioStreamPlayer3D:
			c.queue_free()
			continue
		if c is CollisionObject3D:
			(c as CollisionObject3D).collision_layer = 0
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_strip(c)

func _paint(n: Node, m: Material) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = m
		_paint(c, m)

func _process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	if not active or player.driving or player.dead:
		if _ghost:
			_ghost.visible = false
		return
	if _ghost_type != piece():
		_make_ghost()
	_compute()
	_ghost.visible = not placement.is_empty()
	if not placement.is_empty():
		_ghost.global_position = placement["pos"]
		_ghost.rotation = Vector3(0, placement["rot"], 0)
		_paint(_ghost, _ok_mat if valid else _bad_mat)
	if Game.ui_open or Game.paused:
		return
	if Input.is_action_just_pressed("rotate"):
		user_rot = wrapf(user_rot + PI * 0.25, 0.0, TAU)
	if Input.is_action_pressed("primary") and _cd <= 0.0:
		place()
		_cd = 0.35
	if Input.is_action_just_pressed("secondary") and _cd <= 0.0:
		demolish()
		_cd = 0.35

func _ray() -> Dictionary:
	var cam: Camera3D = player.camera
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 9.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 16)
	q.exclude = [player.get_rid()]
	return space.intersect_ray(q)

func _structure_of(col: Object) -> Node:
	var n := col as Node
	for i in range(3):
		if n == null:
			return null
		if n.get_script() == Structure and n.persistent:
			return n
		n = n.get_parent()
	return null

func _compute() -> void:
	placement = {}
	valid = false
	reason = ""
	var hit := _ray()
	var t := piece()
	var snap: String = Data.PIECES[t]["snap"]
	var gen = Game.world.gen
	if hit.is_empty():
		reason = "Aim at the ground"
		return
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var s := _structure_of(hit["collider"])
	var on_rv := _is_rv(hit["collider"])
	if on_rv and snap != "free":
		reason = "Only furniture and camp items can go on the RV"
		return
	var cam_fwd: Vector3 = -player.camera.global_transform.basis.z
	match snap:
		"free":
			placement = {"pos": p, "rot": player.rotation.y + PI + user_rot, "rv": on_rv, "host": _host_of(hit["collider"])}
			valid = n.y > 0.7
			if not valid:
				reason = "Too steep"
		"cell":
			var q := p + cam_fwd * 0.05
			var cx := floorf(q.x / GRID)
			var cz := floorf(q.z / GRID)
			var center := Vector3(cx * GRID + GRID * 0.5, 0, cz * GRID + GRID * 0.5)
			if t == "foundation":
				if s and s.type in ["foundation", "floor"]:
					center.y = s.position.y
					if s.type == "floor":
						center.y += 0.2
					placement = {"pos": center, "rot": 0.0, "depth": 1.2 + maxf(center.y - _min_corner(center), 0.0)}
				else:
					var hmax := -INF
					var hmin := INF
					for o in [Vector2(-1.5, -1.5), Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5), Vector2.ZERO]:
						var h: float = gen.height(center.x + o.x, center.z + o.y)
						hmax = maxf(hmax, h)
						hmin = minf(hmin, h)
					center.y = snappedf(hmax + 0.25, 0.25)
					placement = {"pos": center, "rot": 0.0, "depth": center.y - hmin + 0.8}
					if hmax - hmin > 3.5:
						reason = "Ground is too uneven"
						return
			else: # stairs
				if not s or not (s.type in ["foundation", "floor"]):
					reason = "Stairs need a foundation or floor"
					return
				center.y = s.position.y + (0.2 if s.type == "floor" else 0.0)
				placement = {"pos": center, "rot": snappedf(player.rotation.y + PI + user_rot, PI * 0.5)}
			valid = true
		"cell_level":
			if not s:
				reason = "Place on top of walls or next to floors"
				return
			var q := p + cam_fwd * 0.05
			var y: float = s.position.y
			if s.type in EDGE_TYPES:
				y += GRID
				q = s.global_position + (p - s.global_position) * Vector3(1, 0, 1)
				# pick the cell on the side the player is looking toward
				q += cam_fwd * Vector3(1, 0, 1) * 0.6
			elif s.type == "foundation":
				y += 0.0
			var cx := floorf(q.x / GRID)
			var cz := floorf(q.z / GRID)
			placement = {"pos": Vector3(cx * GRID + GRID * 0.5, y, cz * GRID + GRID * 0.5), "rot": snappedf(user_rot, PI * 0.5) if t == "roof_slope" else 0.0}
			valid = true
		"edge":
			var y := 0.0
			if s:
				y = s.position.y
				if s.type == "floor":
					y += 0.2
				elif s.type in EDGE_TYPES and p.y > s.position.y + GRID * 0.6 and t != "fence":
					y += GRID
			elif t == "fence":
				y = p.y - 0.05
			else:
				reason = "Walls need a foundation or floor"
				return
			var cx := floorf(p.x / GRID)
			var cz := floorf(p.z / GRID)
			var fx := p.x - cx * GRID
			var fz := p.z - cz * GRID
			var d := [fz, GRID - fz, fx, GRID - fx]
			var best := 0
			for i in range(4):
				if d[i] < d[best]:
					best = i
			var pos := Vector3.ZERO
			var rot := 0.0
			match best:
				0: pos = Vector3(cx * GRID + GRID * 0.5, y, cz * GRID)
				1: pos = Vector3(cx * GRID + GRID * 0.5, y, cz * GRID + GRID)
				2:
					pos = Vector3(cx * GRID, y, cz * GRID + GRID * 0.5)
					rot = PI * 0.5
				3:
					pos = Vector3(cx * GRID + GRID, y, cz * GRID + GRID * 0.5)
					rot = PI * 0.5
			if user_rot >= PI:
				rot += PI
			placement = {"pos": pos, "rot": rot}
			valid = true
	if valid and Game.world.occupied(t, placement["pos"], placement["rot"]):
		valid = false
		reason = "Something is already built here"
	if valid and kit == "" and not Game.has_cost(Data.PIECES[t]["cost"]):
		valid = false
		reason = "Need: " + Data.cost_text(Data.PIECES[t]["cost"])
	if valid and not Game.has_cost(Data.PIECES[t]["cost"]) and kit != "":
		valid = true
	if valid and Game.rv and not placement.get("rv", false) and Game.rv.global_position.distance_to(placement["pos"]) < 4.5 and not (t in ["fence", "chair", "table", "lantern", "crate"]):
		valid = false
		reason = "Too close to the RV"

func _host_of(col: Object) -> Node:
	var n := col as Node
	for i in range(4):
		if n == null:
			return null
		if n.has_method("attach_structure"):
			return n
		n = n.get_parent()
	return null

func _is_rv(col: Object) -> bool:
	return _host_of(col) != null

func _min_corner(center: Vector3) -> float:
	var gen = Game.world.gen
	var hmin := INF
	for o in [Vector2(-1.5, -1.5), Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5)]:
		hmin = minf(hmin, gen.height(center.x + o.x, center.z + o.y))
	return hmin

func place() -> void:
	if placement.is_empty():
		return
	if not valid:
		Game.notify(reason)
		return
	var t := piece()
	if kit != "":
		if not Game.remove_item(kit, 1):
			stop()
			return
	elif not Game.pay(Data.PIECES[t]["cost"]):
		return
	var rec := {"type": t, "pos": Game.arr(placement["pos"]), "rot": placement["rot"], "data": {}}
	if placement.has("depth"):
		rec["data"]["depth"] = placement["depth"]
	if t == "campfire":
		rec["data"]["fuel"] = 240.0
	if placement.get("rv", false):
		placement["host"].attach_structure(rec)
	else:
		Net.place_structure(Game.new_struct_id(), rec)
	Audio.play_at("hammer", placement["pos"])
	if kit != "" and Game.count(kit) <= 0:
		stop()

func demolish() -> void:
	var hit := _ray()
	if hit.is_empty():
		return
	var s := _structure_of(hit["collider"])
	if s == null:
		return
	var cost: Dictionary = Data.PIECES[s.type]["cost"]
	for k in cost:
		var back := int(ceil(int(cost[k]) * 0.5))
		if back > 0:
			Game.add_item(k, back, true)
	if s.type == "crate" and s.data.has("items"):
		for k in s.data["items"]:
			Game.add_item(k, int(s.data["items"][k]), true)
	Game.notify("Demolished %s (50%% refunded)" % Data.PIECES[s.type]["name"])
	Audio.play_at("chop", s.global_position, 0.0, 0.7)
	Net.remove_structure(s.id)
