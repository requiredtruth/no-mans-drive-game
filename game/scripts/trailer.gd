extends VehicleBody3D
## Hitchable trailers: camper (walk-in bedroom + storage), flatbed (cargo/furniture), fuel tanker.

const Shapes = preload("res://scripts/shapes.gd")
const RvPart = preload("res://scripts/rv_part.gd")
const Structure = preload("res://scripts/structure.gd")

const SPECS := {
	"camper": {"name": "Camper Trailer", "mass": 900.0, "len": 4.6, "w": 2.1, "tongue": 3.25},
	"flatbed": {"name": "Flatbed Trailer", "mass": 450.0, "len": 3.8, "w": 1.9, "tongue": 2.7},
	"tanker": {"name": "Fuel Tanker Trailer", "mass": 800.0, "len": 3.6, "w": 1.8, "tongue": 2.6},
}

var vid := ""
var kind := "camper"
var spec := {}
var tow: Node = null
var tow_id := ""
var fuel_store := 0.0
var storage := {}
var _joint: PinJoint3D
var _floor_y := 0.75

func setup(p_id: String, p_kind: String, state: Dictionary) -> void:
	vid = p_id
	kind = p_kind
	spec = SPECS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p_id)
	fuel_store = rng.randf_range(20.0, 120.0) if kind == "tanker" else 0.0
	if not state.is_empty():
		fuel_store = float(state.get("fuel_store", fuel_store))
		storage = state.get("storage", {})
		tow_id = str(state.get("tow", ""))

func save_state() -> Dictionary:
	var tid := ""
	if tow and is_instance_valid(tow):
		tid = "rv" if tow == Game.rv else str(tow.vid)
	return {"kind": kind, "xform": [Game.arr(global_position), Game.arr(rotation)], "fuel_store": fuel_store, "storage": storage, "tow": tid,
		"cargo": Game.world.cargo_records(self) if Game.world else [], "attached": attached}

# ------------------------------------------------------------------ furniture placed in the camper / on the flatbed
var attached: Array = []

func attach_structure(world_rec: Dictionary) -> void:
	var rec := world_rec.duplicate(true)
	rec["pos"] = Game.arr(to_local(Game.v3(rec["pos"])))
	rec["rot"] = float(rec["rot"]) - global_rotation.y
	attached.append(rec)
	_spawn_attached(rec)

func restore_attached(list: Array) -> void:
	for rec in list:
		attached.append(rec)
		_spawn_attached(rec)

func _spawn_attached(rec: Dictionary) -> void:
	var s := StaticBody3D.new()
	s.set_script(Structure)
	s.persistent = false
	get_node("Cargo").add_child(s)
	s.setup("", rec)
	s.collision_layer = 2
	s.collision_mask = 0
	s.remove_from_group("roof")
	s.set_meta("rv_rec", rec)
	s.set_meta("host", self)
	s.save_cb = func(d: Dictionary) -> void: rec["data"] = d

func detach_structure(s: Node) -> void:
	attached.erase(s.get_meta("rv_rec"))
	s.queue_free()

func _ready() -> void:
	mass = spec["mass"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.45, 0.25)
	collision_layer = 16
	collision_mask = 1 | 16
	angular_damp = 0.6
	add_to_group("vehicle")
	add_to_group("trailer")
	var cargo := Node3D.new()
	cargo.name = "Cargo"
	add_child(cargo)
	_build()
	brake = 30.0

func _shape(pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	add_child(cs)

func _part(pos: Vector3, size: Vector3, action: String) -> void:
	var b := StaticBody3D.new()
	b.set_script(RvPart)
	b.rv = self
	b.action = action
	b.collision_layer = 2
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	add_child(b)

func _build() -> void:
	var L: float = spec["len"]
	var w: float = spec["w"]
	var frame := Items.dark_steel()
	# chassis, axle, tongue
	Lib.box(self, Vector3(0, 0.55, 0), Vector3(w - 0.3, 0.12, L), frame)
	Lib.box(self, Vector3(0, 0.5, L * 0.5 + 0.6), Vector3(0.12, 0.1, 1.4), frame, false, Vector3(0, 0, 0))
	for s in [-1.0, 1.0]:
		Lib.box(self, Vector3(s * 0.35, 0.5, L * 0.5 + 0.35), Vector3(0.08, 0.08, 1.0), frame, false, Vector3(0, -s * 0.4, 0))
	Lib.cyl(self, Vector3(0, 0.5, float(spec["tongue"])), 0.06, 0.06, 0.12, Items.steel())
	Lib.cyl(self, Vector3(0, 0.25, L * 0.5 + 0.5), 0.03, 0.03, 0.5, Items.steel())
	for s in [-1.0, 1.0]:
		var vw := VehicleWheel3D.new()
		vw.position = Vector3(s * (w * 0.5 - 0.15), 0.5, -0.2)
		vw.wheel_radius = 0.36
		vw.wheel_rest_length = 0.15
		vw.suspension_travel = 0.15
		vw.suspension_stiffness = 60.0
		vw.suspension_max_force = mass * 40.0
		vw.wheel_friction_slip = 3.0
		vw.wheel_roll_influence = 0.05
		add_child(vw)
		var holder := Node3D.new()
		holder.rotation.z = -PI * 0.5 if s > 0.0 else PI * 0.5
		holder.scale = Vector3.ONE * (0.36 / 0.35)
		vw.add_child(holder)
		var tire := MeshInstance3D.new()
		tire.mesh = Items.mesh("tire")
		tire.position.y = -0.12
		holder.add_child(tire)
		Lib.box(self, Vector3(s * (w * 0.5 - 0.1), 1.0, -0.2), Vector3(0.3, 0.06, 1.0), frame)
	match kind:
		"camper":
			var body := Shapes.st()
			var glass := Shapes.st()
			var trim := Shapes.st()
			var o := PackedVector2Array([Vector2(-L * 0.5, 0.62), Vector2(L * 0.5, 0.62), Vector2(L * 0.5 + 0.1, 1.4), Vector2(L * 0.5 - 0.2, 2.35),
				Vector2(L * 0.5 - 0.7, 2.6), Vector2(-L * 0.5 + 0.6, 2.62), Vector2(-L * 0.5 + 0.05, 2.3), Vector2(-L * 0.5 - 0.05, 1.3)])
			Shapes.extrude(body, glass, o, w, 0.18, [])
			for s in [-1.0, 1.0]:
				var win := PackedVector2Array([Vector2(1.6, 1.55), Vector2(1.6, 2.15), Vector2(0.4, 2.15), Vector2(0.4, 1.55)])
				Shapes.side_panel(trim, Shapes.shrink(win, -0.04), s * (w * 0.5 + 0.004), s)
				Shapes.side_panel(glass, win, s * (w * 0.5 + 0.008), s)
				var stripe := PackedVector2Array([Vector2(L * 0.5, 1.2), Vector2(L * 0.5, 1.35), Vector2(-L * 0.5, 1.35), Vector2(-L * 0.5, 1.2)])
				Shapes.side_panel(trim, stripe, s * (w * 0.5 + 0.003), s)
			var door := PackedVector2Array([Vector2(-0.4, 0.8), Vector2(-0.4, 2.3), Vector2(-1.2, 2.3), Vector2(-1.2, 0.8)])
			Shapes.side_panel(trim, Shapes.shrink(door, -0.03), w * 0.5 + 0.004, 1.0)
			var door_st := Shapes.st()
			Shapes.side_panel(door_st, door, w * 0.5 + 0.008, 1.0)
			var mesh := Shapes.commit([[body, Lib.mat("rv_paint", Color(1.0, 0.97, 0.9), 0.4, false, 0.55)], [glass, Lib.glass_mat()],
				[trim, Lib.mat("paint", Color(0.55, 0.75, 0.75), 0.6, false, 0.4, 0.3)], [door_st, Lib.mat("paint", Color(0.9, 0.88, 0.82), 0.6, false, 0.4, 0.3)]])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			add_child(mi)
			Lib.box(self, Vector3(w * 0.5 + 0.02, 1.5, -0.6), Vector3(0.04, 0.04, 0.14), Items.steel())
			# interior (seen after stepping in): floor, bed, table, cabinet, lamp
			var panel := Lib.mat("planks", Color(0.95, 0.88, 0.78), 1.1, false)
			Lib.box(self, Vector3(0, 0.68, 0), Vector3(w - 0.3, 0.04, L - 0.4), Lib.mat("planks", Color(0.6, 0.48, 0.38), 1.0, false))
			Lib.box(self, Vector3(0, 0.95, L * 0.5 - 0.75), Vector3(w - 0.35, 0.5, 1.2), panel)
			Lib.box(self, Vector3(0, 1.25, L * 0.5 - 0.75), Vector3(w - 0.4, 0.15, 1.15), Lib.mat("canvas", Color(0.75, 0.55, 0.45), 0.8, false))
			Lib.box(self, Vector3(-w * 0.5 + 0.45, 1.05, -L * 0.5 + 0.6), Vector3(0.6, 0.7, 0.9), panel)
			Lib.light(self, Vector3(0, 2.3, 0), Color(1.0, 0.86, 0.66), 0.8, 5.0)
			_part(Vector3(0, 1.3, L * 0.5 - 0.75), Vector3(w - 0.4, 0.4, 1.2), "bed")
			_part(Vector3(-w * 0.5 + 0.45, 1.1, -L * 0.5 + 0.6), Vector3(0.65, 0.8, 0.95), "cabinet")
			_part(Vector3(w * 0.5 + 0.1, 1.5, -0.8), Vector3(0.15, 1.5, 0.8), "door")
			_part(Vector3(w * 0.5 - 0.3, 1.5, -0.8), Vector3(0.15, 1.5, 0.8), "door")
			_floor_y = 0.7
			# hollow collision: floor, walls, roof (door gap on the right)
			_shape(Vector3(0, 0.6, 0), Vector3(w, 0.15, L))
			_shape(Vector3(0, 2.55, 0), Vector3(w, 0.15, L))
			_shape(Vector3(-w * 0.5, 1.6, 0), Vector3(0.1, 2.0, L))
			_shape(Vector3(w * 0.5, 1.6, (L * 0.5 - 0.4) * 0.5 + 0.2), Vector3(0.1, 2.0, L * 0.5 + 0.4))
			_shape(Vector3(w * 0.5, 1.6, -L * 0.5 + 0.4), Vector3(0.1, 2.0, 0.8))
			_shape(Vector3(0, 1.6, L * 0.5), Vector3(w, 2.0, 0.1))
			_shape(Vector3(0, 1.6, -L * 0.5), Vector3(w, 2.0, 0.1))
		"flatbed":
			Lib.box(self, Vector3(0, 0.68, 0), Vector3(w, 0.08, L), Lib.mat("planks", Color(0.75, 0.65, 0.55), 1.0, false))
			for s in [-1.0, 1.0]:
				Lib.box(self, Vector3(s * (w * 0.5 - 0.03), 0.95, 0), Vector3(0.05, 0.05, L), Items.dark_steel())
				for k in range(5):
					Lib.box(self, Vector3(s * (w * 0.5 - 0.03), 0.82, -L * 0.5 + 0.2 + k * (L - 0.4) / 4.0), Vector3(0.04, 0.3, 0.04), Items.dark_steel())
			Lib.box(self, Vector3(0, 0.95, -L * 0.5 + 0.03), Vector3(w, 0.5, 0.05), Lib.mat("metal", Color(0.4, 0.4, 0.42), 1.0, false, 0.5, 0.7))
			_shape(Vector3(0, 0.66, 0), Vector3(w, 0.12, L))
			_floor_y = 0.72
		"tanker":
			var tank := Shapes.st()
			Items.lathe(tank, [Vector2(0.0, -L * 0.5 + 0.1), Vector2(0.55, -L * 0.5 + 0.12), Vector2(0.72, -L * 0.5 + 0.35), Vector2(0.75, 0.0), Vector2(0.72, L * 0.5 - 0.35), Vector2(0.55, L * 0.5 - 0.12), Vector2(0.0, L * 0.5 - 0.1)], 28, Vector3.ZERO, false, false)
			var tm := MeshInstance3D.new()
			tm.mesh = Shapes.commit([[tank, Lib.mat("metal", Color(0.85, 0.86, 0.88), 0.8, false, 0.25, 0.9)]])
			tm.rotation.x = PI * 0.5
			tm.position.y = 1.4
			add_child(tm)
			for z in [-1.0, 0.0, 1.0]:
				Lib.cyl(self, Vector3(0, 1.4, z), 0.77, 0.77, 0.06, Items.dark_steel(), Vector3(PI * 0.5, 0, 0), 28)
			Lib.cyl(self, Vector3(0, 2.18, 0.4), 0.2, 0.2, 0.08, Items.dark_steel())
			var lbl := Lib.label3d(self, Vector3(0.79, 1.4, 0), "FUEL", 64)
			lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			lbl.rotation.y = PI * 0.5
			_part(Vector3(0.8, 1.0, -L * 0.5 + 0.4), Vector3(0.3, 0.5, 0.5), "tank_valve")
			_shape(Vector3(0, 1.4, 0), Vector3(1.5, 1.5, L - 0.2))
			_shape(Vector3(0, 0.6, 0), Vector3(w - 0.3, 0.15, L))
	_part(Vector3(0, 0.6, float(spec["tongue"]) - 0.1), Vector3(0.6, 0.5, 0.6), "hitch")

# ------------------------------------------------------------------ hitching
func _nearest_tow() -> Node:
	var best: Node = null
	var bd := 3.2
	var my := tongue_global()
	for v in get_tree().get_nodes_in_group("vehicle") + [Game.rv]:
		if v == self or v == null or v.is_in_group("trailer") or not v.has_method("hitch_global"):
			continue
		var d: float = v.hitch_global().distance_to(my)
		if d < bd:
			bd = d
			best = v
	return best

func tongue_global() -> Vector3:
	return to_global(Vector3(0, 0.5, float(spec["tongue"])))

func hitch_to(v: Node) -> void:
	if v == null:
		return
	tow = v
	v.trailer = self
	# snap the tongue to the hitch before joining
	var offset: Vector3 = v.hitch_global() - tongue_global()
	global_position += offset
	_joint = PinJoint3D.new()
	Game.world.add_child(_joint)
	_joint.global_position = v.hitch_global()
	_joint.node_a = _joint.get_path_to(v)
	_joint.node_b = _joint.get_path_to(self)
	brake = 0.0
	Audio.play_at("hammer", global_position, -2.0, 0.7)

func unhitch() -> void:
	if _joint:
		_joint.queue_free()
		_joint = null
	if tow and is_instance_valid(tow):
		tow.trailer = null
	tow = null
	brake = 30.0
	Audio.play_at("hammer", global_position, -2.0, 0.7)

func _physics_process(_delta: float) -> void:
	if Game.world == null:
		return
	freeze = not Game.world.ground_ready(global_position) and tow == null
	if tow_id != "" and tow == null:
		var v: Node = Game.rv if tow_id == "rv" else Game.world.vehicle_nodes.get(tow_id)
		if v and Game.world.ground_ready(global_position):
			tow_id = ""
			hitch_to(v)

func contains_point(p: Vector3) -> bool:
	var l := to_local(p)
	var L: float = spec["len"]
	var w: float = spec["w"]
	return absf(l.x) < w * 0.5 and absf(l.z) < L * 0.5 and l.y > _floor_y - 0.2 and l.y < 2.7

func is_inside(p: Vector3) -> bool:
	return kind == "camper" and contains_point(p)

func prompt_for(action: String) -> String:
	match action:
		"hitch":
			if tow:
				return "[E] Unhitch %s" % spec["name"]
			var v := _nearest_tow()
			return ("[E] Hitch to %s" % v.display_name()) if v else "%s — back a vehicle's hitch up to the tongue" % spec["name"]
		"bed": return "[E] Sleep"
		"cabinet": return "[E] Open storage"
		"door": return "[E] Exit camper" if is_inside(Game.player.global_position) else "[E] Enter camper"
		"tank_valve":
			return "[E] Fuel tank %d L — transfer 20 L to the towing vehicle / fill cans" % int(fuel_store)
	return ""

func do_action(action: String, player: Node) -> void:
	match action:
		"hitch":
			if tow:
				unhitch()
			else:
				var v := _nearest_tow()
				if v:
					hitch_to(v)
				else:
					Game.notify("Back a vehicle up so its hitch is next to the trailer tongue")
		"bed":
			Game.world.sleep(player.global_position)
		"cabinet":
			Game.world.hud.open_storage(storage, "Camper storage", func() -> void: pass)
		"door":
			if is_inside(player.global_position):
				player.teleport(to_global(Vector3(spec["w"] * 0.5 + 0.9, 0.2, -0.8)))
			else:
				player.teleport(to_global(Vector3(spec["w"] * 0.5 - 0.6, _floor_y + 0.05, -0.8)))
			Audio.play_at("door", global_position)
		"tank_valve":
			if fuel_store < 1.0:
				Game.notify("The tank is empty")
				return
			var v: Node = tow if tow and is_instance_valid(tow) else null
			if v:
				var amt := minf(minf(20.0, fuel_store), v.fuel_capacity() - v.fuel)
				v.fuel += amt
				fuel_store -= amt
				Game.notify("Transferred %d L" % int(amt))
			elif fuel_store >= 10.0:
				fuel_store -= 10.0
				Game.add_item("fuel_can", 1)
			Audio.play_at("splash", global_position, -6.0, 0.7)

func display_name() -> String:
	return spec["name"]
