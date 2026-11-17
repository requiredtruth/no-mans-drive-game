extends VehicleBody3D
## Drivable road vehicles found along the highway: pickup, sedan, box truck, off-roader.
## Shares the RV's driving/part API so the player, HUD and workshop work with any vehicle.

const Data = preload("res://scripts/data.gd")
const Shapes = preload("res://scripts/shapes.gd")
const RvPart = preload("res://scripts/rv_part.gd")
const Mounts = preload("res://scripts/mounts.gd")
const Structure = preload("res://scripts/structure.gd")

const SPECS := {
	"pickup": {"name": "Pickup Truck", "mass": 2100.0, "power": 7200.0, "top": 33.0, "fuel": 75.0, "w": 1.95, "wr": 0.42, "wz": [-1.75, 1.6], "wx": 0.86, "awd": true, "grip": 3.2,
		"seat": Vector3(0.42, 1.15, 0.15), "cam": Vector3(0.42, 1.62, 0.12), "hitch": -2.85, "exit": Vector3(1.9, 0.0, 0.2), "cargo": [Vector3(0, 1.0, -1.7), Vector3(1.6, 1.4, 1.9)]},
	"work_truck": {"name": "Utility Work Truck", "mass": 3300.0, "power": 9800.0, "top": 29.0, "fuel": 110.0, "w": 2.05, "wr": 0.46, "wz": [-1.75, 1.6], "wx": 0.91, "awd": true, "grip": 3.2,
		"seat": Vector3(0.46, 1.19, 0.15), "cam": Vector3(0.46, 1.68, 0.12), "hitch": -2.85, "exit": Vector3(1.98, 0.0, 0.2), "cargo": [Vector3(0, 1.05, -1.7), Vector3(1.8, 1.4, 1.9)]},
	"semi": {"name": "Semi Tractor", "mass": 7600.0, "power": 20000.0, "top": 25.0, "fuel": 260.0, "w": 2.5, "wr": 0.54, "wz": [-4.0, 2.3], "wx": 1.1, "awd": false, "grip": 3.25,
		"seat": Vector3(0.53, 1.75, 1.6), "cam": Vector3(0.53, 2.25, 1.6), "hitch": -4.6, "exit": Vector3(2.3, 0.0, 1.6), "cargo": [Vector3(0, 1.26, -3.1), Vector3(2.1, 1.0, 2.7)]},
	"long_rv": {"name": "Extra-Long Bare RV", "mass": 6800.0, "power": 16500.0, "top": 23.0, "fuel": 210.0, "w": 2.48, "wr": 0.52, "wz": [-8.0, 1.85], "wx": 1.08, "awd": false, "grip": 3.3,
		"seat": Vector3(0.52, 1.35, 2.0), "cam": Vector3(0.52, 1.9, 2.0), "hitch": -10.95, "exit": Vector3(2.28, 0.0, 2.0), "cargo": [Vector3(0, 1.57, -4.6), Vector3(2.18, 2.3, 10.6)]},
	"sedan": {"name": "Sedan", "mass": 1350.0, "power": 5200.0, "top": 40.0, "fuel": 50.0, "w": 1.8, "wr": 0.34, "wz": [-1.4, 1.35], "wx": 0.78, "awd": false, "grip": 3.0,
		"seat": Vector3(0.38, 0.75, -0.15), "cam": Vector3(0.38, 1.18, -0.2), "hitch": -2.45, "exit": Vector3(1.7, 0.0, -0.1), "cargo": [Vector3(0, 0.75, -1.85), Vector3(1.4, 0.4, 0.8)]},
	"box_truck": {"name": "Box Truck", "mass": 4200.0, "power": 11500.0, "top": 26.0, "fuel": 130.0, "w": 2.3, "wr": 0.48, "wz": [-2.3, 2.1], "wx": 0.98, "awd": false, "grip": 3.1,
		"seat": Vector3(0.5, 1.45, 2.3), "cam": Vector3(0.5, 2.0, 2.3), "hitch": -3.75, "exit": Vector3(2.1, 0.0, 2.3), "cargo": [Vector3(0, 1.85, -1.15), Vector3(2.1, 2.2, 4.0)]},
	"mini_rv": {"name": "Compact RV", "mass": 2700.0, "power": 7600.0, "top": 28.0, "fuel": 85.0, "w": 2.05, "wr": 0.43, "wz": [-1.85, 1.55], "wx": 0.9, "awd": false, "grip": 3.2,
		"seat": Vector3(0.43, 1.15, 1.45), "cam": Vector3(0.43, 1.67, 1.45), "hitch": -2.75, "exit": Vector3(1.9, 0.0, 1.45), "cargo": [Vector3(0, 1.4, -0.8), Vector3(1.8, 2.0, 3.4)]},
	"mid_rv": {"name": "Touring RV", "mass": 3800.0, "power": 10500.0, "top": 27.0, "fuel": 120.0, "w": 2.28, "wr": 0.48, "wz": [-2.25, 1.85], "wx": 1.0, "awd": false, "grip": 3.2,
		"seat": Vector3(0.49, 1.28, 2.0), "cam": Vector3(0.49, 1.82, 2.0), "hitch": -3.45, "exit": Vector3(2.1, 0.0, 2.0), "cargo": [Vector3(0, 1.55, -1.1), Vector3(2.0, 2.2, 4.4)]},
	"offroader": {"name": "Off-Roader", "mass": 1900.0, "power": 6800.0, "top": 34.0, "fuel": 70.0, "w": 1.85, "wr": 0.46, "wz": [-1.35, 1.4], "wx": 0.84, "awd": true, "grip": 3.6,
		"seat": Vector3(0.4, 1.2, 0.05), "cam": Vector3(0.4, 1.7, 0.0), "hitch": -2.4, "exit": Vector3(1.8, 0.0, 0.0), "cargo": [Vector3(0, 1.35, -1.2), Vector3(1.5, 0.9, 1.0)]},
}

const COLORS := [Color("8a2b22"), Color("2f4a6a"), Color("d9d4c4"), Color("3f5a3a"), Color("c49a3a"), Color("5a5a5c"), Color("1e1e20"), Color("6a8aa0")]

var vid := ""
var kind := "pickup"
var spec := {}
var color := Color.WHITE
var fuel := 10.0
var battery := 40.0
var parts := {"engine": 40.0, "tires": 50.0, "battery": 40.0, "body": 50.0}
var missing := {}
var upgrades := {}
var paint := 0
var water := 0.0
var odometer := 0.0
var driver := 0
var engine_on := false
var headlights := false
var use_tp := true
var cam_fp: Camera3D
var cam_tp: Camera3D
var fp_yaw := 0.0
var fp_pitch := 0.0
var tp_yaw := 0.0
var wheels: Array[VehicleWheel3D] = []
var trailer: Node = null
var _steer := 0.0
var _prev_vel := Vector3.ZERO
var _paint_mat: StandardMaterial3D
var _head_spots: Array[SpotLight3D] = []
var _head_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _engine_audio: AudioStreamPlayer3D
var _passenger := false
var _battery_vis: MeshInstance3D
var rear_open := false
var _rear_gate: Node3D
var _rear_gate_shape: CollisionShape3D
var _rear_anim: Tween
var _rear_gate_home := Vector3.ZERO
var engine_kind := "engine_block"
var wheel_kind := {}
var _camper_seats := {} # local floor anchors for real sit-able camper benches
var _camper_drawers := {} # individually usable drawers
var _camper_drawer_state := {}
var attached: Array = [] # furniture fixed to the vehicle in vehicle-local coordinates

## Cab interior: carpet, door cards, pillars, headliner, rear wall and a gauge cluster, so from
## the driver's seat you sit inside a real cab instead of looking out through a glass shell.
const CABS := {
	# z_rear, z_ws_bottom, z_ws_top, belt, roof, floor, rear window [y0, y1, half-width] or [], pillars [[z, width]]
	"sedan": [-1.42, 1.15, 0.52, 1.0, 1.37, 0.42, [], [[-0.15, 0.08], [-1.38, 0.08]]],
	"pickup": [-0.72, 1.28, 0.74, 1.3, 1.88, 0.62, [1.38, 1.82, 0.7], [[-0.66, 0.12]]],
	"work_truck": [-0.72, 1.28, 0.74, 1.3, 1.96, 0.62, [1.38, 1.85, 0.75], [[-0.66, 0.12]]],
	"semi": [-1.72, 3.22, 2.55, 1.85, 3.48, 1.03, [], [[-1.64, 0.2]]],
	"long_rv": [1.0, 2.7, 1.7, 1.45, 2.55, 0.88, [], [[1.0, 0.12]]],
	"box_truck": [0.98, 2.95, 2.62, 1.55, 2.44, 1.02, [], [[1.2, 0.5]]],
	"offroader": [-1.98, 1.02, 0.77, 1.38, 1.94, 0.74, [], [[-0.26, 0.12], [-1.88, 0.2]]],
	"mini_rv": [0.62, 2.1, 1.3, 1.35, 2.25, 0.72, [], [[0.68, 0.12]]],
	"mid_rv": [1.0, 2.7, 1.7, 1.45, 2.5, 0.82, [], [[1.0, 0.12]]],
}

func _build_cab(w: float, _light_y: float) -> void:
	var c: Array = CABS[kind]
	var zr: float = c[0]
	var zb: float = c[1]
	var zt: float = c[2]
	var belt: float = c[3]
	var roof: float = c[4]
	var fl: float = c[5]
	var liner := Lib.mat("canvas", Color(0.55, 0.53, 0.5), 2.0, false, 0.95)
	var card := Lib.mat("leather", Color(0.32, 0.31, 0.3), 2.0, false, 0.75)
	var plastic := Lib.color_mat(Color(0.13, 0.13, 0.14), 0.6)
	var carpet := Lib.mat("carpet", Color(0.28, 0.28, 0.29), 2.0, false)
	var iw := w * 0.5 - 0.07
	Lib.box(self, Vector3(0, fl, (zr + zb) * 0.5), Vector3(w - 0.14, 0.03, zb - zr), carpet)
	for s in [-1.0, 1.0]:
		var x: float = s * iw
		Lib.box(self, Vector3(x, (fl + belt) * 0.5, (zr + zb) * 0.5), Vector3(0.04, belt - fl, zb - zr), card)
		Lib.box(self, Vector3(x - s * 0.04, belt - 0.12, (zr + zb) * 0.5 + 0.1), Vector3(0.06, 0.05, (zb - zr) * 0.5), plastic)
		Lib.box(self, Vector3(x, belt, (zr + zb) * 0.5), Vector3(0.06, 0.03, zb - zr), plastic)
		for pl in c[7]:
			Lib.box(self, Vector3(x, (belt + roof) * 0.5, pl[0]), Vector3(0.05, roof - belt, pl[1]), liner)
		# A-pillar along the windscreen edge
		var a := Vector3(x, belt, zb)
		var b := Vector3(x, roof, zt)
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var ap := Lib.box(self, mid, Vector3(0.06, len, 0.07), plastic)
		ap.rotation.x = atan2(zt - zb, roof - belt)
	Lib.box(self, Vector3(0, roof - 0.04, (zr + zt) * 0.5), Vector3(w - 0.12, 0.03, zt - zr), liner)
	# rear wall of the cab (with the rear window cut out where there is one)
	var rw: Array = c[6]
	if rw.is_empty():
		Lib.box(self, Vector3(0, (fl + roof) * 0.5, zr + 0.03), Vector3(w - 0.12, roof - fl, 0.03), liner)
	else:
		Lib.box(self, Vector3(0, (fl + rw[0]) * 0.5, zr + 0.03), Vector3(w - 0.12, rw[0] - fl, 0.03), card)
		Lib.box(self, Vector3(0, (rw[1] + roof) * 0.5, zr + 0.03), Vector3(w - 0.12, roof - rw[1], 0.03), liner)
		var side_w: float = (w - 0.12) * 0.5 - rw[2]
		for s in [-1.0, 1.0]:
			Lib.box(self, Vector3(s * (rw[2] + side_w * 0.5), (rw[0] + rw[1]) * 0.5, zr + 0.03), Vector3(side_w, rw[1] - rw[0], 0.03), liner)
	# gauge cluster + centre stack on the dash
	var sp_seat: Vector3 = spec["seat"]
	var gy: float = sp_seat.y + 0.3
	var gz: float = sp_seat.z + 0.66
	var hood := Lib.box(self, Vector3(sp_seat.x, gy + 0.02, gz + 0.04), Vector3(0.42, 0.16, 0.12), plastic)
	hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for gx in [-0.1, 0.1]:
		Lib.cyl(self, Vector3(sp_seat.x + gx, gy, gz - 0.025), 0.042, 0.042, 0.01, Lib.color_mat(Color(0.08, 0.08, 0.09), 0.3, 0.0, Color(1.0, 0.55, 0.2), 0.35), Vector3(PI * 0.5, 0, 0))
		Lib.box(self, Vector3(sp_seat.x + gx + 0.012, gy + 0.012, gz - 0.032), Vector3(0.004, 0.034, 0.003), Lib.color_mat(Color(1, 0.4, 0.2), 0.3, 0.0, Color(1, 0.3, 0.1), 1.0), false, Vector3(0, 0, -0.6))
	Lib.box(self, Vector3(0, gy - 0.08, gz + 0.02), Vector3(0.2, 0.2, 0.05), plastic)
	Lib.box(self, Vector3(0, gy - 0.03, gz - 0.005), Vector3(0.14, 0.07, 0.01), Lib.color_mat(Color(0.1, 0.15, 0.12), 0.3, 0.0, Color(0.4, 0.9, 0.5), 0.4))
	Lib.box(self, Vector3(0, fl + 0.15, (zr + zb) * 0.5 + 0.3), Vector3(0.22, 0.28, 0.6), plastic)

func setup(p_id: String, p_kind: String, state: Dictionary) -> void:
	vid = p_id
	kind = p_kind
	spec = SPECS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p_id)
	paint = rng.randi() % COLORS.size()
	fuel = rng.randf_range(2.0, 18.0)
	battery = rng.randf_range(10.0, 60.0)
	for k in parts:
		parts[k] = rng.randf_range(15.0, 60.0)
	_apply_state(state)

func _ready() -> void:
	mass = spec["mass"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0.1)
	collision_layer = 16
	collision_mask = 1 | 16
	angular_damp = 0.8
	add_to_group("vehicle")
	_build()
	_restore_camper_drawers()
	set_rear_open(rear_open, false)
	_engine_audio = Audio.looping_3d("engine_loop", self, -8.0, "Vehicle")
	_engine_audio.stop()
	var cargo := Node3D.new()
	cargo.name = "Cargo"
	add_child(cargo)
	_apply_visuals()

func _apply_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	fuel = float(s.get("fuel", fuel))
	battery = float(s.get("battery", battery))
	var p: Dictionary = s.get("parts", {})
	for k in p:
		parts[k] = float(p[k])
	upgrades = s.get("upgrades", {})
	paint = int(s.get("paint", paint))
	odometer = float(s.get("odometer", 0.0))
	missing = s.get("missing", {})
	wheel_kind = s.get("wheel_kind", {}).duplicate()
	rear_open = bool(s.get("rear_open", false))
	engine_kind = str(s.get("engine_kind", "engine_block"))
	_camper_drawer_state = s.get("camper_drawers", {}).duplicate(true)

func save_state() -> Dictionary:
	return {"kind": kind, "xform": [Game.arr(global_position), Game.arr(rotation)], "fuel": fuel, "battery": battery,
		"parts": parts, "upgrades": upgrades, "paint": paint, "odometer": odometer, "missing": missing,
		"rear_open": rear_open, "engine_kind": engine_kind, "wheel_kind": wheel_kind,
		"camper_drawers": _camper_drawer_saved(), "attached": attached.duplicate(true),
		"trailer": trailer.vid if trailer and is_instance_valid(trailer) else "",
		"cargo": Game.world.cargo_records(self) if Game.world else []}

# ------------------------------------------------------------------ geometry
func _paint() -> StandardMaterial3D:
	if _paint_mat == null:
		_paint_mat = Lib.mat("paint", Color.WHITE, 0.6, false, 0.35, 0.35).duplicate()
	return _paint_mat

func _glass() -> StandardMaterial3D:
	return Lib.glass_mat()

func _shape(pos: Vector3, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	add_child(cs)
	return cs

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

func _mesh_node(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	return mi

func _build() -> void:
	var w: float = spec["w"]
	var wr: float = spec["wr"]
	var wz: Array = spec["wz"]
	var body := Shapes.st()
	var glass := Shapes.st()
	var trim := Shapes.st()
	var chrome_st := Shapes.st()
	var arches := [[wz[0], wr + 0.06], [wz[1], wr + 0.06]]
	var by := wr * 0.85 # body bottom height
	match kind:
		"sedan":
			var o := Shapes.arched_bottom(-2.3, 2.3, by, arches)
			for p in [Vector2(2.35, 0.55), Vector2(2.25, 0.78), Vector2(1.2, 0.95), Vector2(0.5, 1.38), Vector2(-0.75, 1.4), Vector2(-1.45, 1.0), Vector2(-2.3, 0.95), Vector2(-2.35, 0.6)]:
				o.append(p)
			var n := o.size()
			Shapes.extrude(body, glass, o, w, 0.12, [n - 6, n - 4])
			for s in [-1.0, 1.0]:
				var win := PackedVector2Array([Vector2(1.12, 1.0), Vector2(0.48, 1.33), Vector2(-0.72, 1.35), Vector2(-1.35, 1.02)])
				Shapes.side_panel(trim, Shapes.shrink(win, -0.03), s * (w * 0.5 + 0.004), s)
				Shapes.side_panel(glass, win, s * (w * 0.5 + 0.008), s)
				for z in [-0.15]:
					Shapes.side_panel(trim, PackedVector2Array([Vector2(z - 0.03, by + 0.15), Vector2(z + 0.03, by + 0.15), Vector2(z + 0.03, 1.36), Vector2(z - 0.03, 1.36)]), s * (w * 0.5 + 0.01), s)
				for z in [0.55, -0.85]:
					Lib.box(self, Vector3(s * (w * 0.5 + 0.02), 0.92, z), Vector3(0.03, 0.04, 0.16), Items.steel())
			_shape(Vector3(0, 0.75, 0), Vector3(w, 0.6, 4.6))
			_shape(Vector3(0, 1.2, -0.15), Vector3(w - 0.1, 0.4, 2.0))
		"pickup", "work_truck":
			var o := Shapes.arched_bottom(-0.75, 2.7, by, [arches[1]])
			for p in [Vector2(2.78, 0.75), Vector2(2.7, 1.15), Vector2(1.35, 1.25), Vector2(0.72, 1.9), Vector2(-0.55, 1.92), Vector2(-0.75, 1.25)]:
				o.append(p)
			var n := o.size()
			Shapes.extrude(body, glass, o, w, 0.1, [n - 4])
			var rear := Shapes.arched_bottom(-2.8, -0.72, by, [arches[0]])
			for p in [Vector2(-0.72, 0.95), Vector2(-2.8, 0.95)]:
				rear.append(p)
			Shapes.extrude(body, null, rear, w, 0.06)
			# bed walls and tailgate
			for s in [-1.0, 1.0]:
				Lib.box(self, Vector3(s * (w * 0.5 - 0.05), 1.15, -1.76), Vector3(0.1, 0.42, 2.08), _paint())
				Lib.box(self, Vector3(s * (w * 0.5 - 0.05), 1.38, -1.76), Vector3(0.14, 0.05, 2.08), Items.dark_steel())
				var win := PackedVector2Array([Vector2(1.2, 1.3), Vector2(0.68, 1.82), Vector2(-0.45, 1.84), Vector2(-0.6, 1.3)])
				Shapes.side_panel(trim, Shapes.shrink(win, -0.03), s * (w * 0.5 + 0.004), s)
				Shapes.side_panel(glass, win, s * (w * 0.5 + 0.008), s)
				Lib.box(self, Vector3(s * (w * 0.5 + 0.02), 1.2, 0.95), Vector3(0.03, 0.04, 0.16), Items.steel())
			_rear_gate = Node3D.new()
			_rear_gate.name = "PickupTailgate"
			_rear_gate_home = Vector3(0, 0.95, -2.78)
			_rear_gate.position = _rear_gate_home
			add_child(_rear_gate)
			Lib.box(_rear_gate, Vector3(0, 0.2, 0), Vector3(w - 0.1, 0.42, 0.08), _paint())
			Lib.box(self, Vector3(0, 0.98, -1.76), Vector3(w - 0.2, 0.04, 2.0), Lib.mat("metal", Color(0.5, 0.5, 0.52), 1.5, false, 0.5, 0.7))
			var rw := Lib.box(self, Vector3(0, 1.6, -0.76), Vector3(1.4, 0.45, 0.03), _glass())
			rw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_shape(Vector3(0, 0.75, 0.0), Vector3(w, 0.5, 5.6))
			_shape(Vector3(0, 1.5, 0.95), Vector3(w - 0.1, 0.8, 3.4))
			for s in [-1.0, 1.0]:
				_shape(Vector3(s * (w * 0.5 - 0.05), 1.15, -1.76), Vector3(0.1, 0.42, 2.08))
			_rear_gate_shape = _shape(Vector3(0, 1.15, -2.78), Vector3(w, 0.42, 0.08))
			_part(Vector3(0, 1.14, -2.93), Vector3(w * 0.72, 0.5, 0.2), "rear")
			if kind == "work_truck":
				# Separate fleet work truck: flatbed guard rails, rack and commercial light bar.
				for side in [-1.0, 1.0]:
					Lib.box(self, Vector3(side * (w * 0.5 - 0.12), 1.6, -1.82), Vector3(0.06, 0.5, 1.8), Items.steel())
				Lib.box(self, Vector3(0, 2.04, 0.4), Vector3(w - 0.2, 0.08, 0.12), Items.dark_steel())
				for side in [-1.0, 1.0]:
					Lib.box(self, Vector3(side * (w * 0.5 - 0.24), 2.10, 0.4), Vector3(0.26, 0.1, 0.15), Lib.color_mat(Color(1.0, 0.56, 0.11), 0.2, 0.0, Color(1.0, 0.46, 0.08), 1.3))
		"box_truck":
			var o := Shapes.arched_bottom(0.9, 3.45, by, [arches[1]])
			for p in [Vector2(3.55, 0.8), Vector2(3.5, 1.35), Vector2(3.0, 1.45), Vector2(2.6, 2.45), Vector2(1.0, 2.5), Vector2(0.9, 1.0)]:
				o.append(p)
			var n := o.size()
			Shapes.extrude(body, glass, o, w, 0.12, [n - 4])
			var chassis := Shapes.arched_bottom(-3.7, 0.95, by, [arches[0]])
			for p in [Vector2(0.95, 0.85), Vector2(-3.7, 0.85)]:
				chassis.append(p)
			Shapes.extrude(trim, null, chassis, w - 0.2, 0.04)
			var box_m := Lib.mat("rv_paint", Color(0.95, 0.95, 0.93), 0.4, false, 0.6)
			# Actual empty cargo hold: four walls + floor/ceiling, never a filled solid box.
			Lib.box(self, Vector3(0, 0.89, -1.4), Vector3(w + 0.1, 0.13, 4.6), box_m)
			Lib.box(self, Vector3(0, 3.14, -1.4), Vector3(w + 0.1, 0.13, 4.6), box_m)
			for side in [-1.0, 1.0]:
				Lib.box(self, Vector3(side * (w * 0.5), 2.02, -1.4), Vector3(0.09, 2.27, 4.6), box_m)
			Lib.box(self, Vector3(0, 2.02, 0.85), Vector3(w, 2.27, 0.1), box_m)
			_rear_gate = Node3D.new()
			_rear_gate.name = "TruckRollerShutter"
			add_child(_rear_gate)
			for k in range(10):
				Lib.box(_rear_gate, Vector3(0, 0.99 + k * 0.22, -3.72), Vector3(w - 0.15, 0.215, 0.035), Lib.mat("ribbed_metal", Color(0.74, 0.78, 0.8), 1.0, false, 0.56))
			for side in [-1.0, 1.0]:
				Lib.box(self, Vector3(side * (w * 0.5 - 0.05), 2.02, -3.76), Vector3(0.05, 2.35, 0.05), Items.steel())
			for s in [-1.0, 1.0]:
				var win := PackedVector2Array([Vector2(2.75, 1.55), Vector2(2.45, 2.35), Vector2(1.45, 2.38), Vector2(1.45, 1.55)])
				Shapes.side_panel(trim, Shapes.shrink(win, -0.03), s * (w * 0.5 + 0.004), s)
				Shapes.side_panel(glass, win, s * (w * 0.5 + 0.008), s)
			_shape(Vector3(0, 1.6, 2.2), Vector3(w, 1.8, 2.6))
			_shape(Vector3(0, 0.91, -1.4), Vector3(w + 0.1, 0.15, 4.6))
			_shape(Vector3(0, 3.12, -1.4), Vector3(w + 0.1, 0.15, 4.6))
			for side in [-1.0, 1.0]:
				_shape(Vector3(side * (w * 0.5), 2.02, -1.4), Vector3(0.1, 2.2, 4.6))
			_shape(Vector3(0, 2.02, 0.85), Vector3(w, 2.2, 0.1))
			_rear_gate_shape = _shape(Vector3(0, 2.01, -3.72), Vector3(w, 2.2, 0.08))
			_part(Vector3(0, 1.8, -3.86), Vector3(w * 0.73, 1.65, 0.18), "rear")
		"semi":
			# Open rear tractor chassis, a separate high sleeper cab and visible fifth-wheel plate.
			var body_m := Lib.mat("rv_paint", Color(0.65, 0.72, 0.79), 0.55, false, 0.56)
			Lib.box(self, Vector3(0, 0.91, -1.4), Vector3(w * 0.77, 0.28, 7.8), Items.dark_steel())
			Lib.box(self, Vector3(0, 2.15, 1.05), Vector3(w, 2.65, 4.9), body_m, false, Vector3.ZERO, 0.12)
			Lib.box(self, Vector3(0, 3.5, 0.5), Vector3(w + 0.18, 0.12, 3.8), body_m)
			for side in [-1.0, 1.0]:
				var x: float = side * (w * 0.5 + 0.018)
				Lib.box(self, Vector3(x, 2.49, 1.65), Vector3(0.02, 0.78, 1.35), _glass(), false, Vector3.ZERO, 0.03)
				Lib.box(self, Vector3(x, 1.64, -0.72), Vector3(0.08, 0.12, 0.52), Items.dark_steel())
				Lib.cyl(self, Vector3(side * (w * 0.5 + 0.15), 2.02, -0.4), 0.13, 0.13, 3.1, Items.steel())
			Lib.box(self, Vector3(0, 2.53, 3.53), Vector3(w * 0.85, 1.0, 0.04), _glass())
			Lib.box(self, Vector3(0, 1.05, 3.59), Vector3(w * 0.8, 0.9, 0.26), Items.steel())
			Lib.box(self, Vector3(0, 1.2, -3.05), Vector3(1.2, 0.11, 1.5), Items.dark_steel())
			Lib.cyl(self, Vector3(0, 1.33, -3.02), 0.58, 0.58, 0.10, Items.steel())
			_shape(Vector3(0, 1.86, 1.05), Vector3(w, 2.6, 4.9))
			_shape(Vector3(0, 0.92, -2.05), Vector3(w * 0.8, 0.25, 6.4))
			_rear_gate = Node3D.new()
			_rear_gate.name = "SemiToolLocker"
			_rear_gate_home = Vector3(0, 1.4, -4.45)
			_rear_gate.position = _rear_gate_home
			add_child(_rear_gate)
			Lib.box(_rear_gate, Vector3(0, 0.15, 0), Vector3(w * 0.6, 0.36, 0.07), body_m)
			_rear_gate_shape = _shape(Vector3(0, 1.55, -4.45), Vector3(w * 0.6, 0.36, 0.08))
			_part(Vector3(0, 1.55, -4.62), Vector3(w * 0.55, 0.5, 0.22), "rear")
		"mini_rv", "mid_rv", "long_rv":
			var is_mini := kind == "mini_rv"
			var is_long := kind == "long_rv"
			var rz := -10.6 if is_long else (-2.65 if is_mini else -3.35)
			var fz := 2.75 if is_mini else 3.18
			var length := fz - rz
			var top_y := 2.75 if is_mini else (3.15 if is_long else 3.05)
			var floor_y := 0.88 if is_mini else 0.98
			var wall := Lib.mat("rv_paint", Color(0.92, 0.9, 0.81), 0.4, false, 0.6)
			var inside := Lib.mat("vinyl", Color(0.66, 0.65, 0.6), 2.0, false, 0.9)
			var center_z := (fz + rz) * 0.5
			Lib.box(self, Vector3(0, floor_y, center_z), Vector3(w, 0.12, length), inside)
			Lib.box(self, Vector3(0, top_y, center_z), Vector3(w, 0.1, length), wall)
			for side in [-1.0, 1.0]:
				var x: float = float(side) * w * 0.5
				Lib.box(self, Vector3(x, (floor_y + top_y) * 0.5, center_z), Vector3(0.08, top_y - floor_y, length), wall)
				# Glazed side panels with trim and separate interior furnishings.
				Lib.box(self, Vector3(x + side * 0.045, 2.08, -1.1), Vector3(0.014, 0.55, 1.2), Items.dark_steel())
				Lib.box(self, Vector3(x + side * 0.053, 2.08, -1.1), Vector3(0.015, 0.48, 1.1), _glass())
				_shape(Vector3(x, (floor_y + top_y) * 0.5, center_z), Vector3(0.09, top_y - floor_y, length))
			Lib.box(self, Vector3(0, (floor_y + top_y) * 0.5, fz), Vector3(w, top_y - floor_y, 0.09), wall)
			_shape(Vector3(0, floor_y, center_z), Vector3(w, 0.12, length))
			_shape(Vector3(0, top_y, center_z), Vector3(w, 0.1, length))
			_shape(Vector3(0, (floor_y + top_y) * 0.5, fz), Vector3(w, top_y - floor_y, 0.09))
			_rear_gate = Node3D.new()
			_rear_gate.name = "CamperRearHatch"
			_rear_gate_home = Vector3(0, top_y, rz - 0.02)
			_rear_gate.position = _rear_gate_home
			add_child(_rear_gate)
			Lib.box(_rear_gate, Vector3(0, -(top_y - floor_y) * 0.5, 0), Vector3(w - 0.1, top_y - floor_y, 0.06), wall)
			_rear_gate_shape = _shape(Vector3(0, (floor_y + top_y) * 0.5, rz), Vector3(w, top_y - floor_y, 0.08))
			_part(Vector3(0, 1.65, rz - 0.2), Vector3(w * 0.7, 1.4, 0.22), "rear")
			# The double-long body deliberately ships BARE so it can be furnished physically.
			# Compact and touring campers keep working beds, seating and storage drawers.
			if not is_long:
				Lib.box(self, Vector3(-0.32, floor_y + 0.28, rz + 1.0), Vector3(w - 0.38, 0.23, 1.38), Lib.mat("upholstery", Color(0.43, 0.49, 0.58), 1.3, false))
				Lib.box(self, Vector3(-w * 0.5 + 0.27, floor_y + 0.48, 0.3), Vector3(0.46, 0.9, 0.92), Lib.mat("laminate", Color(0.65, 0.53, 0.43), 1.4, false))
				Lib.box(self, Vector3(w * 0.5 - 0.3, floor_y + 0.4, 0.35), Vector3(0.52, 0.76, 0.8), Lib.mat("laminate", Color(0.6, 0.54, 0.47), 1.4, false))
				_part(Vector3(0, floor_y + 0.72, rz + 1.0), Vector3(0.98, 0.28, 0.95), "sleep")
				for i in range(2):
					var sz := -0.4 + float(i) * 0.9
					Lib.box(self, Vector3(w * 0.5 - 0.44, floor_y + 0.32, sz), Vector3(0.66, 0.19, 0.5), Lib.mat("upholstery", Color(0.51, 0.54, 0.58), 1.4, false))
					var anchor := Node3D.new()
					anchor.position = Vector3(w * 0.5 - 0.44, floor_y, sz)
					anchor.rotation.y = PI * 0.5
					anchor.set_meta("seat_type", "bench")
					add_child(anchor)
					_camper_seats["sit_bench:%d" % i] = anchor
					_part(Vector3(w * 0.5 - 0.83, floor_y + 0.49, sz), Vector3(0.16, 0.5, 0.48), "sit_bench:%d" % i)
				for i in range(3):
					var dz := -0.12 + float(i) * 0.27
					var slide := Node3D.new()
					slide.position = Vector3(-w * 0.5 + 0.51, floor_y + 0.53, dz)
					add_child(slide)
					Lib.box(slide, Vector3.ZERO, Vector3(0.035, 0.21, 0.22), Items.steel())
					Lib.box(slide, Vector3(0.03, 0.03, 0), Vector3(0.02, 0.028, 0.13), Items.dark_steel())
					_camper_drawers[str(i)] = {"pivot": slide, "home": slide.position.x, "open": false, "items": []}
					_part(Vector3(-w * 0.5 + 0.61, floor_y + 0.53, dz), Vector3(0.16, 0.22, 0.23), "camper_drawer:%d" % i)
		"offroader":
			var o := Shapes.arched_bottom(-2.0, 2.05, by, arches)
			for p in [Vector2(2.12, 0.8), Vector2(2.05, 1.25), Vector2(1.05, 1.32), Vector2(0.75, 1.95), Vector2(-1.9, 1.98), Vector2(-2.05, 1.25)]:
				o.append(p)
			var n := o.size()
			Shapes.extrude(body, glass, o, w, 0.09, [n - 4])
			for s in [-1.0, 1.0]:
				var win := PackedVector2Array([Vector2(0.95, 1.38), Vector2(0.7, 1.86), Vector2(-0.2, 1.88), Vector2(-0.2, 1.38)])
				Shapes.side_panel(trim, Shapes.shrink(win, -0.03), s * (w * 0.5 + 0.004), s)
				Shapes.side_panel(glass, win, s * (w * 0.5 + 0.008), s)
				var win2 := PackedVector2Array([Vector2(-0.32, 1.38), Vector2(-0.32, 1.88), Vector2(-1.75, 1.9), Vector2(-1.8, 1.38)])
				Shapes.side_panel(trim, Shapes.shrink(win2, -0.03), s * (w * 0.5 + 0.004), s)
				Shapes.side_panel(glass, win2, s * (w * 0.5 + 0.008), s)
				Lib.box(self, Vector3(s * (w * 0.5 + 0.02), 1.22, 0.7), Vector3(0.03, 0.04, 0.16), Items.steel())
			for z in [-1.4, -0.6, 0.2]:
				Lib.box(self, Vector3(0, 2.05, z), Vector3(w - 0.1, 0.04, 0.05), Items.dark_steel())
			for s in [-1.0, 1.0]:
				Lib.box(self, Vector3(s * (w * 0.5 - 0.08), 2.05, -0.6), Vector3(0.05, 0.08, 1.7), Items.dark_steel())
			var spare := MeshInstance3D.new()
			spare.mesh = Items.mesh("tire")
			spare.rotation.x = PI * 0.5
			spare.scale = Vector3.ONE * (wr / 0.35)
			spare.position = Vector3(0, 1.4, -2.08 - 0.15)
			add_child(spare)
			_shape(Vector3(0, 0.95, 0), Vector3(w, 1.0, 4.1))
			_shape(Vector3(0, 1.65, -0.5), Vector3(w - 0.1, 0.6, 2.9))
	if kind in ["sedan", "offroader"]:
		var r := -2.36 if kind == "sedan" else -2.08
		_rear_gate = Node3D.new()
		_rear_gate.name = "RearCargoHatch"
		_rear_gate_home = Vector3(0, 1.35, r - 0.03)
		_rear_gate.position = _rear_gate_home
		add_child(_rear_gate)
		Lib.box(_rear_gate, Vector3(0, -0.3, 0), Vector3(w - 0.15, 0.57, 0.06), _paint())
		_rear_gate_shape = _shape(Vector3(0, 1.05, r), Vector3(w - 0.15, 0.57, 0.08))
		_part(Vector3(0, 1.1, r - 0.15), Vector3(w * 0.7, 0.65, 0.2), "rear")
	# lights, grille, bumpers (front at the largest z of the body)
	var front_z: float = {"sedan": 2.36, "pickup": 2.8, "work_truck": 2.8, "box_truck": 3.57, "semi": 3.62, "offroader": 2.13, "mini_rv": 2.77, "mid_rv": 3.2, "long_rv": 3.2}[kind]
	var rear_z: float = {"sedan": -2.36, "pickup": -2.84, "work_truck": -2.84, "box_truck": -3.75, "semi": -5.3, "offroader": -2.08, "mini_rv": -2.67, "mid_rv": -3.37, "long_rv": -10.62}[kind]
	var light_y: float = {"sedan": 0.72, "pickup": 1.0, "work_truck": 1.05, "box_truck": 1.1, "semi": 1.42, "offroader": 1.05, "mini_rv": 1.06, "mid_rv": 1.16, "long_rv": 1.16}[kind]
	_head_mat = Lib.color_mat(Color(0.95, 0.95, 0.9), 0.05, 0.0, Color(1, 0.95, 0.8), 0.01).duplicate()
	_tail_mat = Lib.color_mat(Color(0.6, 0.05, 0.05), 0.2, 0.0, Color(1, 0.1, 0.05), 0.2).duplicate()
	for s in [-1.0, 1.0]:
		var x: float = s * (w * 0.5 - 0.28)
		Lib.box(self, Vector3(x, light_y, front_z), Vector3(0.36, 0.18, 0.05), _head_mat, false, Vector3.ZERO, 0.03)
		Lib.box(self, Vector3(x, light_y, front_z - 0.01), Vector3(0.4, 0.22, 0.05), Items.steel(), false, Vector3.ZERO, 0.03)
		Lib.box(self, Vector3(x, light_y, rear_z), Vector3(0.3, 0.2, 0.05), _tail_mat, false, Vector3.ZERO, 0.03)
		var sp := SpotLight3D.new()
		sp.position = Vector3(x, light_y, front_z + 0.05)
		sp.rotation.y = PI
		sp.rotation.x = deg_to_rad(-4)
		sp.spot_range = 40.0
		sp.spot_angle = 30.0
		sp.light_energy = 5.0
		sp.visible = false
		add_child(sp)
		_head_spots.append(sp)
		# mirrors
		Lib.box(self, Vector3(s * (w * 0.5 + 0.12), {"sedan": 1.0, "pickup": 1.38, "work_truck": 1.46, "box_truck": 1.85, "semi": 2.0, "offroader": 1.45, "mini_rv": 1.4, "mid_rv": 1.55, "long_rv": 1.6}[kind], {"sedan": 0.95, "pickup": 1.15, "work_truck": 1.15, "box_truck": 2.85, "semi": 2.6, "offroader": 0.85, "mini_rv": 1.65, "mid_rv": 2.1, "long_rv": 2.1}[kind]), Vector3(0.06, 0.16, 0.2), Items.dark_steel(), false, Vector3.ZERO, 0.02)
	Lib.box(self, Vector3(0, light_y, front_z + 0.005), Vector3(w * 0.5, 0.26, 0.04), Lib.color_mat(Color(0.06, 0.06, 0.06), 0.4), false, Vector3.ZERO, 0.02)
	for k in range(4):
		Lib.box(self, Vector3(0, light_y - 0.09 + k * 0.06, front_z + 0.03), Vector3(w * 0.48, 0.015, 0.02), Items.steel())
	Lib.box(self, Vector3(0, by + 0.12, front_z + 0.06), Vector3(w + 0.04, 0.2, 0.16), Items.dark_steel() if kind != "sedan" else _paint(), false, Vector3.ZERO, 0.05)
	Lib.box(self, Vector3(0, by + 0.12, rear_z - 0.06), Vector3(w + 0.04, 0.2, 0.16), Items.dark_steel() if kind != "sedan" else _paint(), false, Vector3.ZERO, 0.05)
	# licence plate
	Lib.box(self, Vector3(0, by + 0.32, rear_z - 0.04), Vector3(0.52, 0.12, 0.01), Lib.color_mat(Color(0.92, 0.9, 0.8)))
	var plate := Label3D.new()
	plate.text = "NMD-%03d" % (absi(hash(vid)) % 1000)
	plate.font_size = 40
	plate.pixel_size = 0.0018
	plate.modulate = Color(0.1, 0.15, 0.4)
	plate.outline_size = 0
	plate.position = Vector3(0, by + 0.32, rear_z - 0.05)
	plate.rotation.y = PI
	add_child(plate)
	# interior: seats, dash and wheel (visible through the glass)
	var seat_m := Lib.mat("leather", Color(0.6, 0.55, 0.5), 2.0, false, 0.7)
	var sp_seat: Vector3 = spec["seat"]
	for s in [-1.0, 1.0]:
		var sx: float = absf(sp_seat.x) * s
		Lib.box(self, Vector3(sx, sp_seat.y - 0.2, sp_seat.z - 0.05), Vector3(0.5, 0.14, 0.5), seat_m, false, Vector3.ZERO, 0.05)
		Lib.box(self, Vector3(sx, sp_seat.y + 0.15, sp_seat.z - 0.32), Vector3(0.5, 0.65, 0.12), seat_m, false, Vector3(-0.2, 0, 0), 0.05)
	Lib.box(self, Vector3(0, sp_seat.y + 0.15, sp_seat.z + 0.85), Vector3(w - 0.25, 0.25, 0.4), Lib.color_mat(Color(0.12, 0.12, 0.12), 0.6), false, Vector3.ZERO, 0.05)
	var wheel_st := Shapes.st()
	Items.torus(wheel_st, Vector3.ZERO, 0.17, 0.018, 20, 6, Vector3.UP)
	var sw := _mesh_node(Shapes.commit([[wheel_st, Lib.color_mat(Color(0.08, 0.08, 0.08), 0.5)]]))
	sw.name = "SteeringWheel"
	sw.position = Vector3(sp_seat.x, sp_seat.y + 0.3, sp_seat.z + 0.5)
	sw.rotation.x = -1.1
	var mesh := Shapes.commit([[body, _paint()], [glass, _glass()], [trim, Lib.color_mat(Color(0.05, 0.05, 0.05), 0.5)], [chrome_st, Items.steel()]])
	_mesh_node(mesh)
	# wheels
	for i in range(6 if kind in ["semi", "long_rv"] else 4):
		var front := i < 2
		var sx := -1.0 if i % 2 == 0 else 1.0
		var axle_z: float = float(wz[1]) if front else (float(wz[0]) + 1.45 if i >= 4 else float(wz[0]))
		var vw := VehicleWheel3D.new()
		vw.position = Vector3(sx * float(spec["wx"]), wr + 0.12, axle_z)
		vw.use_as_steering = front
		vw.use_as_traction = (not front) or spec["awd"]
		vw.wheel_radius = wr
		vw.wheel_rest_length = 0.2
		vw.suspension_travel = 0.22
		vw.suspension_stiffness = 55.0
		vw.suspension_max_force = mass * 30.0
		vw.damping_compression = 1.6
		vw.damping_relaxation = 2.3
		vw.wheel_friction_slip = spec["grip"]
		vw.wheel_roll_influence = 0.05
		add_child(vw)
		var holder := Node3D.new()
		holder.rotation.z = -PI * 0.5 if sx > 0.0 else PI * 0.5
		holder.scale = Vector3.ONE * (wr / 0.35)
		vw.add_child(holder)
		var tire := MeshInstance3D.new()
		tire.mesh = Items.mesh("tire")
		tire.position.y = -0.12
		holder.add_child(tire)
		vw.set_meta("tire_mesh", tire)
		vw.set_meta("hub_mesh", Mounts.hub(holder))
		_part(Vector3(sx * (float(spec["wx"]) + 0.12), wr + 0.12, axle_z), Vector3(0.35, wr * 2.2, wr * 2.4), "wheel%d" % wheels.size())
		wheels.append(vw)
	# interaction hotspots
	# Vehicles face +Z. Viewed facing forward, +X is the American driver's LEFT.
	# Keep the drive hotspot, wheel, cab camera and seat together.
	_part(Vector3(w * 0.5 + 0.1, sp_seat.y + 0.2, sp_seat.z), Vector3(0.25, 1.0, 1.0), "drive")
	_part(Vector3(-w * 0.5 - 0.1, sp_seat.y + 0.2, sp_seat.z), Vector3(0.25, 1.0, 1.0), "passenger")
	_part(Vector3(0, light_y + 0.35, front_z - 0.5), Vector3(w - 0.2, 0.2, 0.9), "hood")
	# battery under a flip-up cover at the front corner of the hood
	var bpos := Vector3(w * 0.3, light_y + 0.47, front_z - 0.4)
	if kind == "box_truck":
		bpos = Vector3(-w * 0.5 - 0.15, 0.9, 1.25)
	_battery_vis = MeshInstance3D.new()
	_battery_vis.mesh = Items.mesh("car_battery")
	_battery_vis.scale = Vector3.ONE * 1.2
	# sits down in the engine bay (only the box truck's hangs on the chassis, in view)
	_battery_vis.position = bpos + (Vector3(0, -0.12, 0) if kind == "box_truck" else Vector3(0, -0.62, 0))
	add_child(_battery_vis)
	_part(bpos + Vector3(0, 0.08, 0), Vector3(0.38, 0.2, 0.32), "battery")
	_build_cab(w, light_y)
	# Cargo can be placed physically in every vehicle; this hotspot also makes loading
	# accessible from outside without an abstract inventory screen.
	_part(Vector3(0, maxf(by + 0.55, 1.12), rear_z - 0.25), Vector3(w * 0.6, 0.5, 0.18), "cargo")
	_part(Vector3(-w * 0.5 - 0.08, by + 0.55, rear_z + 0.7), Vector3(0.2, 0.3, 0.3), "fuel")
	# cameras
	cam_fp = Camera3D.new()
	cam_fp.position = spec["cam"]
	cam_fp.rotation.y = PI
	cam_fp.near = 0.05
	cam_fp.far = 1200.0
	add_child(cam_fp)
	cam_tp = Camera3D.new()
	cam_tp.top_level = true
	cam_tp.far = 1500.0
	add_child(cam_tp)

func _apply_visuals() -> void:
	if _paint_mat:
		_paint_mat.albedo_color = COLORS[paint % COLORS.size()]
	var grip: float = float(spec["grip"]) * (1.15 if upgrades.has("offroad_tires") else 1.0) * lerpf(0.6, 1.0, parts["tires"] / 100.0)
	Mounts.apply_wheels(self, grip)
	if _battery_vis:
		_battery_vis.visible = not missing.has("battery")

# ------------------------------------------------------------------ shared vehicle API
func fuel_capacity() -> float:
	return float(spec["fuel"]) * (1.6 if upgrades.has("big_tank") else 1.0)

func water_capacity() -> float:
	return 0.0

func speed_kmh() -> float:
	return linear_velocity.dot(global_transform.basis.z) * 3.6

func is_authority() -> bool:
	return true

func is_driven_locally() -> bool:
	return driver != 0 and driver == Net.my_id()

func heater_on() -> bool:
	return engine_on

func is_inside(_p: Vector3) -> bool:
	return false

func display_name() -> String:
	return spec["name"]

func seat_global(as_driver: bool) -> Vector3:
	var s: Vector3 = spec["seat"]
	return to_global(Vector3(s.x if as_driver else -s.x, s.y - 0.4, s.z))

func exit_global() -> Vector3:
	var e: Vector3 = spec["exit"]
	var p := to_global(e)
	p.y = Game.world.gen.height(p.x, p.z) + 0.3
	return p

func set_seat(as_driver: bool) -> void:
	var c: Vector3 = spec["cam"]
	cam_fp.position = Vector3(c.x if as_driver else -c.x, c.y, c.z)

func contains_point(p: Vector3) -> bool:
	var c: Array = spec["cargo"]
	var l := to_local(p) - (c[0] as Vector3)
	var h: Vector3 = (c[1] as Vector3) * 0.5
	return absf(l.x) < h.x and absf(l.y) < h.y and absf(l.z) < h.z

func hitch_global() -> Vector3:
	return to_global(Vector3(0, float(spec["wr"]) + 0.15, float(spec["hitch"])))

func try_start_engine() -> void:
	if engine_on:
		return
	if fuel <= 0.1:
		Game.notify("The tank is empty. Pour in a fuel can at the filler cap.")
		return
	if missing.has("battery"):
		Game.notify("There's no battery fitted. Carry a Car Battery to the battery tray.")
		return
	if battery < 5.0 or parts["battery"] < 5.0:
		Game.notify("Dead battery. Pull it out under the hood and fit a Car Battery.")
		return
	if missing.has("engine"):
		Game.notify("Engine bay is empty. Carry an engine block to the hood.")
		return
	if parts["engine"] <= 1.0:
		Game.notify("The engine is seized. Repair it at the hood.")
		return
	if parts["engine"] < 25.0 and randf() < 0.4:
		Audio.play_at("engine_start", global_position, 0.0, 0.85)
		Game.notify("It cranks but won't catch... try again.")
		battery -= 2.0
		return
	engine_on = true
	battery -= 3.0
	Audio.play_at("engine_start", global_position, 0.0, 1.2 if kind == "sedan" else 1.0)
	_engine_audio.play()

func stop_engine() -> void:
	engine_on = false
	_engine_audio.stop()

func toggle_headlights() -> void:
	if battery <= 0.0:
		return
	headlights = not headlights
	for s in _head_spots:
		s.visible = headlights
	_head_mat.emission_energy_multiplier = 3.0 if headlights else 0.01
	Audio.play("click", -4.0)

func look(rel: Vector2) -> void:
	if cam_tp.current:
		tp_yaw = wrapf(tp_yaw - rel.x, -PI, PI)
	else:
		fp_yaw = clampf(fp_yaw - rel.x, -2.2, 2.2)
		fp_pitch = clampf(fp_pitch - rel.y, -1.2, 1.0)
		cam_fp.rotation = Vector3(-fp_pitch, PI + fp_yaw, 0)

func set_camera(third_person: bool) -> void:
	use_tp = third_person
	if third_person:
		cam_tp.global_position = global_position - global_transform.basis.z * 8.0 + Vector3(0, 3, 0)
		cam_tp.make_current()
	else:
		cam_fp.make_current()
	cam_fp.fov = Game.settings["fov"]
	cam_tp.fov = Game.settings["fov"]

func _process(delta: float) -> void:
	if cam_tp and cam_tp.current:
		var target := global_position + Vector3(0, 1.6, 0)
		var behind := -global_transform.basis.z
		behind.y = 0
		behind = behind.normalized().rotated(Vector3.UP, tp_yaw)
		var dist := 8.0 if kind != "box_truck" else 11.0
		if trailer and is_instance_valid(trailer):
			dist += 5.0
		var want := target + behind * dist + Vector3(0, 2.6, 0)
		want.y = maxf(want.y, Game.world.gen.height(want.x, want.z) + 1.0)
		cam_tp.global_position = cam_tp.global_position.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
		cam_tp.look_at(target, Vector3.UP)

func _physics_process(delta: float) -> void:
	if Game.world == null:
		return
	if not Game.world.ground_ready(global_position):
		freeze = true
		return
	freeze = false
	var throttle := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var handbrake := false
	if is_driven_locally() and not Game.ui_open and not Game.paused:
		throttle = Input.get_action_strength("move_forward")
		brake_in = Input.get_action_strength("move_back")
		steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		handbrake = Input.is_action_pressed("jump")
	var fwd := linear_velocity.dot(global_transform.basis.z)
	var tow := 0.75 if trailer and is_instance_valid(trailer) else 1.0
	var power: float = float(spec["power"]) * (1.3 if upgrades.has("engine_tune") else 1.0) * (1.25 if upgrades.has("turbo") else 1.0) * lerpf(0.6, 1.0, parts["engine"] / 100.0) * tow * maxf(1.0 - 0.3 * Mounts.missing_count(self), 0.1)
	var top: float = spec["top"]
	var force := 0.0
	var brk := 0.0
	if engine_on and fuel > 0.0:
		if throttle > 0.05:
			force = power * throttle * clampf(1.0 - fwd / top, 0.0, 1.0)
		if brake_in > 0.05:
			if fwd > 1.0:
				brk = mass * 0.045 * brake_in
			else:
				force = -power * 0.6 * brake_in * clampf(1.0 + fwd / 8.0, 0.0, 1.0)
		if throttle < 0.05 and brake_in < 0.05:
			brk = mass * 0.002
	else:
		brk = mass * 0.004 + brake_in * mass * 0.03
	if driver == 0:
		brk = mass * 0.03
	if handbrake:
		brk = mass * 0.05
	engine_force = force
	brake = brk
	var limit := lerpf(0.62, 0.2, clampf(absf(fwd) / 25.0, 0.0, 1.0))
	_steer = move_toward(_steer, steer_in * limit, delta * (3.5 if absf(steer_in) > 0.05 else 5.0))
	steering = _steer
	var sw := get_node_or_null("SteeringWheel")
	if sw:
		sw.rotation = Vector3(-1.1, -_steer * 3.0, 0)
	if driver != 0:
		var lateral := linear_velocity.dot(global_transform.basis.x)
		apply_central_force(-global_transform.basis.x * lateral * mass * 1.6)
		if absf(steer_in) < 0.05:
			apply_torque(Vector3(0, -angular_velocity.y * mass * 2.0, 0))
		if global_transform.basis.y.y < 0.5 and linear_velocity.length() < 3.0:
			rotation = Vector3(0, rotation.y, 0)
			global_position += Vector3(0, 1.0, 0)
			angular_velocity = Vector3.ZERO
	var spd := linear_velocity.length()
	if engine_on:
		fuel = maxf(fuel - (0.0018 + 0.05 * throttle * clampf(spd / 22.0, 0.25, 1.0)) * Game.diff("fuel") * delta * (mass / 2500.0), 0.0)
		battery = minf(battery + delta * 0.5, 100.0)
		if fuel <= 0.0:
			stop_engine()
			Game.notify("Out of fuel.")
		var rpm := 0.8 + clampf(absf(fwd) / top, 0.0, 1.0) * 1.0 + throttle * 0.25
		_engine_audio.pitch_scale = lerpf(_engine_audio.pitch_scale, rpm * (1.25 if kind == "sedan" else 1.0), delta * 4.0)
	odometer += spd * delta
	var dist := spd * delta
	parts["tires"] = maxf(parts["tires"] - dist / 1000.0 * 0.5, 0.0)
	parts["engine"] = maxf(parts["engine"] - dist / 1000.0 * 0.3, 0.0)
	var dv := (_prev_vel - linear_velocity).length()
	if dv > 7.0 and driver != 0:
		var dmg := (dv - 7.0) * 2.5 * Game.diff("damage") * (0.4 if upgrades.has("bullbar") else 1.0) * (0.5 if upgrades.has("ram_plow") else 1.0)
		parts["body"] = maxf(parts["body"] - dmg, 0.0)
		parts["engine"] = maxf(parts["engine"] - dmg * 0.5, 0.0)
		Audio.play_at("hit", global_position, 6.0, 0.7)
		if Game.player and Game.player.driving and Game.player.vehicle == self:
			Game.player.hurt(dmg * 0.5, "crash")
	_prev_vel = linear_velocity
	_tail_mat.emission_energy_multiplier = 2.5 if brk > mass * 0.01 and driver != 0 else (0.8 if headlights else 0.1)

func set_rear_open(open: bool, animate := true) -> void:
	rear_open = open
	if _rear_gate_shape:
		_rear_gate_shape.set_deferred("disabled", open)
	if _rear_anim:
		_rear_anim.kill()
		_rear_anim = null
	if _rear_gate == null:
		return
	var target := Vector3(0, 2.45 if kind == "box_truck" and open else 0, 0)
	var angle := (1.4 if kind in ["pickup", "work_truck"] else -1.4) if open and kind != "box_truck" else 0.0
	if not animate:
		_rear_gate.position = target + _rear_gate_home
		_rear_gate.rotation.x = angle
	else:
		_rear_anim = create_tween().set_parallel(true)
		_rear_anim.tween_property(_rear_gate, "position", target + _rear_gate_home, 0.35)
		_rear_anim.tween_property(_rear_gate, "rotation:x", angle, 0.35)
		Audio.play_at("door", global_position, -5.0, 0.9)

## Camper drawers are physical pull-out compartments; stacks survive save and reload.
func _camper_drawer_saved() -> Dictionary:
	var out := {}
	for key in _camper_drawers:
		var drawer: Dictionary = _camper_drawers[key]
		out[key] = {"open": bool(drawer["open"]), "items": (drawer["items"] as Array).duplicate(true)}
	return out

func _restore_camper_drawers() -> void:
	for key in _camper_drawers:
		var drawer: Dictionary = _camper_drawers[key]
		var saved: Dictionary = _camper_drawer_state.get(key, {})
		drawer["open"] = bool(saved.get("open", false))
		drawer["items"] = (saved.get("items", []) as Array).duplicate(true)
		(drawer["pivot"] as Node3D).position.x = float(drawer["home"]) + (0.28 if drawer["open"] else 0.0)

func drawer_transfer(action: String) -> void:
	if action.begins_with("camper_drawer:"):
		_camper_drawer_action(action.substr(14), true)

func _camper_drawer_action(key: String, transfer := false) -> void:
	if not _camper_drawers.has(key):
		return
	var drawer: Dictionary = _camper_drawers[key]
	if not drawer["open"]:
		drawer["open"] = true
		create_tween().tween_property(drawer["pivot"], "position:x", float(drawer["home"]) + 0.28, 0.25)
		Audio.play_at("door", global_position, -12.0)
		return
	if not transfer:
		drawer["open"] = false
		create_tween().tween_property(drawer["pivot"], "position:x", float(drawer["home"]), 0.25)
		Audio.play_at("door", global_position, -12.0)
		return
	if Game.equipped() != "":
		var stack: Dictionary = Game.take_held()
		if str(stack.get("id", "")) != "":
			(drawer["items"] as Array).append(stack.duplicate(true))
			Game.notify("Item stored in camper drawer")
		return
	var items: Array = drawer["items"]
	if not items.is_empty():
		var stack: Dictionary = items[items.size() - 1]
		var item_id: String = str(stack["id"])
		if Game.space_for(item_id) < int(stack["n"]):
			Game.notify("Clear hand space to retrieve the stored item")
			return
		Game.add_item(item_id, int(stack["n"]), true)
		items.pop_back()
		if stack.has("c") or stack.has("sd"):
			for sl in Game.slots:
				if sl["id"] == item_id and not sl.has("c") and not sl.has("sd"):
					if stack.has("c"):
						sl["c"] = stack["c"]
					if stack.has("sd"):
						sl["sd"] = stack["sd"]
					break
		Game.notify("Item retrieved from camper drawer")
		return
	Game.notify("The camper drawer is empty")

## Attach furniture, chairs, beds and storage to ANY driveable vehicle.
func attach_structure(world_rec: Dictionary) -> void:
	var rec := world_rec.duplicate(true)
	rec["pos"] = Game.arr(to_local(Game.v3(rec["pos"])))
	rec["rot"] = float(rec["rot"]) - global_rotation.y
	attached.append(rec)
	_spawn_attached(rec)

func _spawn_attached(rec: Dictionary) -> Node:
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
	s.save_cb = func(state: Dictionary) -> void: rec["data"] = state
	return s

func restore_attached(list: Array) -> void:
	for rec in list:
		var local_rec: Dictionary = rec.duplicate(true)
		attached.append(local_rec)
		_spawn_attached(local_rec)

func detach_structure(s: Node) -> void:
	var rec: Dictionary = s.get_meta("rv_rec")
	attached.erase(rec)
	s.queue_free()

func cargo_store() -> void:
	if not rear_open:
		set_rear_open(true)
		Game.notify("Rear cargo access opened")
		return
	var cargo: Node = get_node("Cargo")
	if Game.equipped() != "":
		if cargo.get_child_count() >= 24:
			Game.notify("The cargo area is full")
			return
		var s := Game.take_held()
		var c: Array = spec["cargo"]
		var center: Vector3 = c[0]
		var span: Vector3 = c[1]
		var i := cargo.get_child_count()
		var cols := 4
		var lp := center + Vector3(((i % cols) - 1.5) * minf(span.x * 0.23, 0.42),
			-span.y * 0.5 + 0.22 + (i / cols / 4) * 0.45,
			-span.z * 0.45 + ((i / cols) % 4) * minf(span.z * 0.23, 0.55))
		Game.place_item(s["id"], int(s["n"]), global_transform * Transform3D(Basis.IDENTITY, lp), self, s.get("c", []))
		Game.notify("%s stored in %s — it travels with the vehicle" % [Data.item_name(s["id"]), display_name()])
	else:
		for ch in cargo.get_children():
			if ch.is_in_group("world_item"):
				if Game.pick_up(ch):
					Game.notify("Retrieved cargo from %s" % display_name())
				return
		Game.notify("Cargo area is empty")

func remove_engine() -> void:
	if missing.has("engine"):
		return
	if not Game.has_flag("toolkit"):
		Game.notify("A Toolkit is needed to remove an engine")
		return
	if Game.space_for(engine_kind) <= 0:
		Game.notify("Clear a hand to lift out the engine")
		return
	stop_engine()
	Game.add_item(engine_kind, 1, true)
	missing["engine"] = true
	parts["engine"] = 0.0
	Game.notify("Engine removed; fit another engine block at the hood")

func fit_engine() -> bool:
	var held := Game.equipped()
	if held not in ["engine_block", "vehicle_engine_block_t1", "vehicle_engine_block_t2", "vehicle_engine_block_t3"]:
		return false
	if not missing.has("engine"):
		Game.notify("Remove the current engine with G before swapping engines")
		return true
	if not Game.has_flag("toolkit"):
		Game.notify("A Toolkit is needed to fit the engine")
		return true
	Game.remove_item(held, 1)
	engine_kind = held
	parts["engine"] = 100.0
	missing.erase("engine")
	Audio.play_at("hammer", global_position, -4.0)
	Game.notify("%s fitted in %s" % [Data.item_name(held), display_name()])
	return true

# ------------------------------------------------------------------ interaction (same names as the RV)
func prompt_for(action: String) -> String:
	if action == "battery" or action.begins_with("wheel"):
		return Mounts.prompt(self, action)
	if action == "hood" and Mounts.prompt(self, "hood") != "":
		return Mounts.prompt(self, "hood")
	match action:
		"drive": return "[E] Drive %s" % spec["name"] if driver == 0 else "Occupied"
		"passenger": return "[E] Ride as passenger"
		"hood": return ("[E] Fit engine block" if missing.has("engine") and Game.equipped() != "" else "[G] Swap engine (Toolkit needed)" if Game.equipped() == "" else Mounts.car_hood_prompt(self))
		"fuel": return "[E] Refuel (%d/%d L)" % [int(fuel), int(fuel_capacity())]
		"rear": return "[E] %s rear cargo door" % ("Close" if rear_open else "Open")
		"cargo": return ("[E] Store held item in %s" % display_name() if Game.equipped() != "" else "[E] Take an item from vehicle cargo") if rear_open else "[E] Open rear cargo door"
		"sleep": return "[E] Sleep in the camper bed"
		"sit_bench:0", "sit_bench:1": return "[E] Sit in camper bench (recover energy)"
		"camper_drawer:0", "camper_drawer:1", "camper_drawer:2":
			var drawer: Dictionary = _camper_drawers[action.substr(14)]
			if not drawer["open"]:
				return "[E] Open camper drawer"
			if Game.equipped() != "":
				return "[E] Close drawer   [G] Store held item"
			if not (drawer["items"] as Array).is_empty():
				return "[E] Close drawer   [G] Take stored item"
			return "[E] Close camper drawer"
	return ""

func do_action(action: String, player: Node) -> void:
	if action == "battery" or action.begins_with("wheel") or (action == "hood" and Game.equipped() not in ["engine_block", "vehicle_engine_block_t1", "vehicle_engine_block_t2", "vehicle_engine_block_t3"]):
		if Mounts.act(self, action):
			return
	match action:
		"drive":
			if driver == 0:
				player.enter_vehicle(self, true)
		"passenger":
			player.enter_vehicle(self, false)
		"hood":
			if not fit_engine():
				Mounts.car_hood(self)
		"rear":
			set_rear_open(not rear_open)
		"cargo":
			cargo_store()
		"sleep":
			Game.world.sleep(player.global_position)
		"sit_bench:0", "sit_bench:1":
			if _camper_seats.has(action):
				player.sit_in(_camper_seats[action])
		"camper_drawer:0", "camper_drawer:1", "camper_drawer:2":
			_camper_drawer_action(action.substr(14))
		"fuel":
			if Game.equipped() != "fuel_can":
				Game.notify("Carry a full Fuel Can here to pour it in")
			elif fuel > fuel_capacity() - 1.0:
				Game.notify("The tank is full")
			else:
				Game.remove_item("fuel_can", 1)
				Game.add_item("fuel_can_empty", 1, true)
				fuel = minf(fuel + 10.0, fuel_capacity())
				Audio.play_at("splash", global_position, -8.0, 0.7)

func set_paint(i: int) -> void:
	paint = i
	_apply_visuals()

func paint_palette() -> Array:
	return COLORS

func upgrade_list() -> Array:
	return ["engine_tune", "offroad_tires", "big_tank", "bullbar", "turbo", "ram_plow"]
