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
		if not storage.is_empty():
			call_deferred("_spill_legacy")
		tow_id = str(state.get("tow", ""))

## Older saves kept camper storage as a list: lay those items on the shelves.
func _spill_legacy() -> void:
	var L: float = spec["len"]
	var w: float = spec["w"]
	var i := 0
	for k in storage:
		var n := int(storage[k])
		while n > 0 and i < 12:
			var take := mini(n, Game.Data.stack(k))
			var lp := Vector3(-w * 0.5 + 0.4, 0.72 if i < 6 else 1.33, -L * 0.5 + 0.35 + (i % 6) * 0.1)
			var bb: AABB = Items.display_bounds(k)
			Game.place_item(k, take, global_transform * Transform3D(Basis.IDENTITY, lp - Vector3(0, bb.position.y, 0)), self)
			n -= take
			i += 1
	storage = {}

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

## The camper's side door and window: real openings. [z0, z1, y0, y1]
const DOOR := [-1.25, -0.4, 0.68, 2.64]
const WIN := [0.4, 1.6, 1.65, 2.3]
const DOOR_Z := -0.825
var door_open := false
var _door_pivot: Node3D
var _door_shape: CollisionShape3D
var _jack: CollisionShape3D

## Wall board along Z at x with rectangular holes, from z_a to z_b.
func _wall(x: float, m: Material, holes: Array, z_a: float, z_b: float) -> void:
	var y0 := 0.7
	var y1 := 2.85
	var cuts: Array[float] = [z_a, z_b]
	for h in holes:
		cuts.append(clampf(h[0], z_a, z_b))
		cuts.append(clampf(h[1], z_a, z_b))
	cuts.sort()
	for i in range(cuts.size() - 1):
		var a := cuts[i]
		var b := cuts[i + 1]
		if b - a < 0.001:
			continue
		var zc := (a + b) * 0.5
		var spans: Array = [[y0, y1]]
		for h in holes:
			if zc > h[0] and zc < h[1]:
				spans = [[y0, maxf(h[2], y0)], [h[3], y1]]
		for sp in spans:
			if sp[1] - sp[0] > 0.01:
				Lib.box(self, Vector3(x, (sp[0] + sp[1]) * 0.5, zc), Vector3(0.02, sp[1] - sp[0], b - a), m)

## A hinged entry door that swings out, plus a step below it.
func _build_camper_door(paint_m: Material) -> void:
	var w: float = spec["w"]
	var dw: float = DOOR[1] - DOOR[0]
	var dh: float = DOOR[3] - DOOR[2]
	_door_pivot = Node3D.new()
	_door_pivot.name = "DoorPivot"
	_door_pivot.position = Vector3(w * 0.5, DOOR[2], DOOR[0])
	add_child(_door_pivot)
	var st_out := Shapes.st()
	var st_in := Shapes.st()
	var st_glass := Shapes.st()
	var rect := PackedVector2Array([Vector2(0, 0), Vector2(dw, 0), Vector2(dw, dh), Vector2(0, dh)])
	var win := PackedVector2Array([Vector2(0.15, 1.2), Vector2(dw - 0.15, 1.2), Vector2(dw - 0.15, 1.7), Vector2(0.15, 1.7)])
	Shapes.side_with_holes(st_out, rect, [win], 0.0, 1.0)
	Shapes.side_with_holes(st_in, rect, [win], -0.05, -1.0)
	Shapes.side_panel(st_glass, win, -0.025, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = Shapes.commit([[st_out, Lib.mat("paint", Color(0.9, 0.88, 0.82), 0.6, false, 0.4, 0.3)], [st_in, Lib.color_mat(Color(0.82, 0.8, 0.76), 0.8)], [st_glass, Lib.glass_mat()]])
	_door_pivot.add_child(mi)
	for e in [[Vector2(0, 0), Vector2(dw, 0)], [Vector2(dw, 0), Vector2(dw, dh)], [Vector2(dw, dh), Vector2(0, dh)], [Vector2(0, dh), Vector2(0, 0)]]:
		var c: Vector2 = (e[0] + e[1]) * 0.5
		var d: Vector2 = e[1] - e[0]
		Lib.box(_door_pivot, Vector3(-0.025, c.y, c.x), Vector3(0.05, 0.02, d.length() + 0.02), paint_m, false, Vector3(atan2(-d.y, d.x), 0, 0), 0.006)
	Lib.box(_door_pivot, Vector3(0.025, 0.95, dw - 0.1), Vector3(0.04, 0.05, 0.12), Items.steel(), false, Vector3.ZERO, 0.015)
	Lib.box(_door_pivot, Vector3(-0.075, 0.95, dw - 0.1), Vector3(0.04, 0.05, 0.12), Items.steel(), false, Vector3.ZERO, 0.015)
	var b := StaticBody3D.new()
	b.set_script(RvPart)
	b.rv = self
	b.action = "door"
	b.collision_layer = 2
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.2, dh, dw)
	cs.shape = sh
	b.add_child(cs)
	b.position = Vector3(-0.025, dh * 0.5, dw * 0.5)
	_door_pivot.add_child(b)
	_door_shape = CollisionShape3D.new()
	var dsh := BoxShape3D.new()
	dsh.size = Vector3(0.08, dh, dw)
	_door_shape.shape = dsh
	_door_shape.position = Vector3(w * 0.5, DOOR[2] + dh * 0.5, (DOOR[0] + DOOR[1]) * 0.5)
	add_child(_door_shape)
	# entry step: its own body so it never drags on the ground
	var sb := StaticBody3D.new()
	sb.collision_layer = 16
	sb.collision_mask = 0
	add_child(sb)
	add_collision_exception_with(sb)
	var sc := Vector3(w * 0.5 + 0.22, 0.33, DOOR_Z)
	Lib.box(self, sc, Vector3(0.4, 0.05, dw - 0.06), Lib.mat("metal", Color(0.62, 0.62, 0.64), 4.0, false, 0.45, 0.8), false, Vector3.ZERO, 0.012)
	for dz in [-dw * 0.5 + 0.08, dw * 0.5 - 0.08]:
		Lib.box(self, Vector3(w * 0.5 + 0.1, 0.45, DOOR_Z + dz), Vector3(0.3, 0.04, 0.04), Items.dark_steel(), false, Vector3(0, 0, -0.7))
	var scs := CollisionShape3D.new()
	var ssh := BoxShape3D.new()
	ssh.size = Vector3(0.4, 0.05, dw - 0.06)
	scs.shape = ssh
	scs.position = sc
	sb.add_child(scs)

## Swing the camper door open (outwards, towards the back) or shut.
func set_door(open: bool) -> void:
	door_open = open
	if _door_shape:
		_door_shape.disabled = open
	if _door_pivot:
		var tw := create_tween()
		tw.tween_property(_door_pivot, "rotation:y", 1.75 if open else 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	Audio.play_at("door", to_global(Vector3(spec["w"] * 0.5, 1.4, DOOR_Z)), -2.0)

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
	Lib.box(self, Vector3(0, 0.02, L * 0.5 + 0.5), Vector3(0.16, 0.03, 0.16), Items.dark_steel())
	# the tongue jack holds the trailer level when it's unhitched, and is wound up for towing
	_jack = CollisionShape3D.new()
	var jsh := BoxShape3D.new()
	jsh.size = Vector3(0.16, 0.5, 0.16)
	_jack.shape = jsh
	_jack.position = Vector3(0, 0.26, L * 0.5 + 0.5)
	add_child(_jack)
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
			var o := PackedVector2Array([Vector2(-L * 0.5, 0.62), Vector2(L * 0.5, 0.62), Vector2(L * 0.5 + 0.1, 1.4), Vector2(L * 0.5 - 0.2, 2.65),
				Vector2(L * 0.5 - 0.7, 2.95), Vector2(-L * 0.5 + 0.6, 2.97), Vector2(-L * 0.5 + 0.05, 2.65), Vector2(-L * 0.5 - 0.05, 1.3)])
			Shapes.extrude(body, glass, o, w, 0.18, [], 0.0, false)
			var flat := Shapes.inset_outline(o, 0.18)
			var lining := Shapes.st()
			var rubber := Lib.color_mat(Color(0.05, 0.05, 0.05), 0.85)
			var paint_m := Lib.mat("rv_paint", Color(1.0, 0.97, 0.9), 0.4, false, 0.55)
			for s in [-1.0, 1.0]:
				var holes: Array = [WIN]
				if s > 0.0:
					holes.append(DOOR)
				var hp: Array = []
				for r in holes:
					hp.append(PackedVector2Array([Vector2(r[0], r[2]), Vector2(r[1], r[2]), Vector2(r[1], r[3]), Vector2(r[0], r[3])]))
				Shapes.side_with_holes(body, flat, hp, s * w * 0.5, s)
				Shapes.side_with_holes(lining, flat, hp, s * (w * 0.5 - 0.02), -s)
				var stripe := PackedVector2Array([Vector2(L * 0.5, 1.2), Vector2(L * 0.5, 1.35), Vector2(-L * 0.5, 1.35), Vector2(-L * 0.5, 1.2)])
				for pc in (Geometry2D.clip_polygons(stripe, hp[hp.size() - 1]) if s > 0.0 else [stripe]):
					Shapes.side_panel(trim, pc, s * (w * 0.5 + 0.003), s)
				for k in range(hp.size()):
					var poly: PackedVector2Array = hp[k]
					var is_door: bool = s > 0.0 and k == 1
					for i in range(4):
						var a: Vector2 = poly[i]
						var b: Vector2 = poly[(i + 1) % 4]
						var c := (a + b) * 0.5
						var d := b - a
						var m: Material = rubber if not is_door else paint_m
						if is_door and i == 0:
							m = Items.steel()
						Lib.box(self, Vector3(s * (w * 0.5 - 0.06), c.y, c.x), Vector3(0.14, 0.03, d.length() + 0.03), m, false, Vector3(atan2(-d.y, d.x), 0, 0), 0.008)
					if not is_door:
						Shapes.side_panel(glass, poly, s * (w * 0.5 - 0.01), s)
			var mesh := Shapes.commit([[body, paint_m], [glass, Lib.glass_mat()],
				[trim, Lib.mat("paint", Color(0.55, 0.75, 0.75), 0.6, false, 0.4, 0.3)], [lining, Lib.color_mat(Color(0.85, 0.83, 0.79), 0.8)]])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			add_child(mi)
			_build_camper_door(paint_m)
			# interior: vinyl floor, wall board, laminate bed base and an open shelf unit
			var wall := Lib.color_mat(Color(0.88, 0.86, 0.82), 0.8)
			var lam := Lib.color_mat(Color(0.8, 0.78, 0.74), 0.4)
			var trim_m := Lib.color_mat(Color(0.36, 0.35, 0.34), 0.5)
			Lib.box(self, Vector3(0, 0.68, 0), Vector3(w - 0.3, 0.04, L - 0.4), Lib.mat("tiles", Color(0.62, 0.58, 0.52), 1.1, false, 0.55))
			for sx in [-1.0, 1.0]:
				_wall(sx * (w * 0.5 - 0.09), wall, [WIN, DOOR] if sx > 0.0 else [WIN], -L * 0.5 + 0.15, L * 0.5 - 0.15)
			Lib.box(self, Vector3(0, 2.82, 0), Vector3(w - 0.2, 0.02, L - 0.3), Lib.color_mat(Color(0.93, 0.92, 0.9), 0.9))
			Lib.box(self, Vector3(0, 0.95, L * 0.5 - 0.75), Vector3(w - 0.35, 0.5, 1.2), lam)
			Lib.box(self, Vector3(0, 1.25, L * 0.5 - 0.75), Vector3(w - 0.4, 0.15, 1.15), Lib.color_mat(Color(0.92, 0.92, 0.9), 0.95), false, Vector3.ZERO, 0.05)
			Lib.box(self, Vector3(0.1, 1.34, L * 0.5 - 0.75), Vector3(w - 0.6, 0.05, 1.17), Lib.mat("plaid", Color(0.75, 0.75, 0.78), 2.0, false, 0.95))
			_shape(Vector3(0, 1.0, L * 0.5 - 0.75), Vector3(w - 0.35, 0.65, 1.2))
			var sc := Vector3(-w * 0.5 + 0.4, 1.3, -L * 0.5 + 0.6)
			var ss := Vector3(0.5, 1.2, 0.9)
			for pc in [[sc + Vector3(-ss.x * 0.5 + 0.015, 0, 0), Vector3(0.03, ss.y, ss.z)], [sc + Vector3(0, 0, -ss.z * 0.5 + 0.015), Vector3(ss.x, ss.y, 0.03)],
					[sc + Vector3(0, 0, ss.z * 0.5 - 0.015), Vector3(ss.x, ss.y, 0.03)], [sc + Vector3(0, ss.y * 0.5 - 0.015, 0), Vector3(ss.x, 0.03, ss.z)],
					[sc + Vector3(0, -ss.y * 0.5 + 0.015, 0), Vector3(ss.x, 0.03, ss.z)], [sc + Vector3(0, 0.0, 0), Vector3(ss.x, 0.025, ss.z)]]:
				Lib.box(self, pc[0], pc[1], lam)
				_shape(pc[0], pc[1])
			Lib.box(self, sc + Vector3(ss.x * 0.5, 0.0, 0), Vector3(0.02, 0.04, ss.z), trim_m)
			Lib.light(self, Vector3(0, 2.65, 0), Color(1.0, 0.86, 0.66), 0.8, 5.0)
			_part(Vector3(0, 1.38, L * 0.5 - 0.35), Vector3(w - 0.6, 0.12, 0.35), "bed")
			_floor_y = 0.7
			# hollow collision: floor, walls, roof (door gap on the right)
			_shape(Vector3(0, 0.6, 0), Vector3(w, 0.15, L))
			_shape(Vector3(0, 2.9, 0), Vector3(w, 0.15, L))
			_shape(Vector3(-w * 0.5, 1.75, 0), Vector3(0.1, 2.3, L))
			_shape(Vector3(w * 0.5, 1.75, (DOOR[1] + L * 0.5) * 0.5), Vector3(0.1, 2.3, L * 0.5 - DOOR[1]))
			_shape(Vector3(w * 0.5, 1.75, (DOOR[0] - L * 0.5) * 0.5), Vector3(0.1, 2.3, DOOR[0] + L * 0.5))
			_shape(Vector3(w * 0.5, (DOOR[3] + 2.9) * 0.5, (DOOR[0] + DOOR[1]) * 0.5), Vector3(0.1, 2.9 - DOOR[3], DOOR[1] - DOOR[0]))
			_shape(Vector3(0, 1.75, L * 0.5), Vector3(w, 2.3, 0.1))
			_shape(Vector3(0, 1.75, -L * 0.5), Vector3(w, 2.3, 0.1))
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
	var bd := 4.5
	var my := tongue_global()
	for v in get_tree().get_nodes_in_group("vehicle") + [Game.rv]:
		if v == self or v == null or v.is_in_group("trailer") or not v.has_method("hitch_global"):
			continue
		if v.has_method("can_tow") and not v.can_tow():
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
	if _jack:
		_jack.disabled = true
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
	if _jack:
		_jack.disabled = false
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
	return absf(l.x) < w * 0.5 and absf(l.z) < L * 0.5 and l.y > _floor_y - 0.2 and l.y < 3.0

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
		"door": return "[E] %s the door" % ("Close" if door_open else "Open")
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
		"door":
			set_door(not door_open)
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
