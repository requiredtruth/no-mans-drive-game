extends VehicleBody3D
## The player's motorhome: drivable, enterable, repairable and upgradeable.

const Data = preload("res://scripts/data.gd")
const Structure = preload("res://scripts/structure.gd")
const RvPart = preload("res://scripts/rv_part.gd")
const Shapes = preload("res://scripts/shapes.gd")
const Mounts = preload("res://scripts/mounts.gd")

const W := 2.4 # body width
const FLOOR_Y := 1.0
const ROOF_Y := 3.25
const DOOR_H := 2.05
const REAR_Z := -3.4
const FRONT_Z := 3.4
const DOOR_Z0 := 0.55
const DOOR_Z1 := 1.45

var fuel := 18.0
var water := 6.0
var battery := 45.0
var parts := {"engine": 38.0, "tires": 52.0, "battery": 48.0, "body": 55.0}
var upgrades := {}
var paint := 0
var fridge := {}
var cabinet := {}
var missing := {} # parts pulled out: "battery", "wheel0".."wheel3"
var pots := [{}, {}]
var interior_lights := false
var headlights := false
var engine_on := false
var driver := 0 # peer id of the driver (0 = nobody)
var odometer := 0.0
var attached: Array = [] # furniture placed inside / on top of the RV: {type, pos(local), rot(local), data}

var wheels: Array[VehicleWheel3D] = []
var cam_fp: Camera3D
var cam_tp: Camera3D
var use_tp := true
var fp_yaw := 0.0
var fp_pitch := 0.0
var tp_yaw := 0.0
var _paint_mats: Array[StandardMaterial3D] = []
var _head_spots: Array[SpotLight3D] = []
var _head_mats: Array[StandardMaterial3D] = []
var _tail_mat: StandardMaterial3D
var _interior_light: OmniLight3D
var _engine_audio: AudioStreamPlayer3D
var _door_panel: Node3D
var _prev_vel := Vector3.ZERO
var _throttle := 0.0
var _remote_target: Transform3D
var _remote_has := false
var _solar: Node3D
var _bullbar: Node3D
var _steer := 0.0

func _ready() -> void:
	mass = 3200.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.4, 0.2)
	collision_layer = 16
	collision_mask = 1 | 16
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = true
	angular_damp = 0.6
	_build_collision()
	_build_wheels()
	_build_exterior()
	_build_interior()
	_build_cameras()
	_engine_audio = Audio.looping_3d("engine_loop", self, -6.0, "Vehicle")
	_engine_audio.position = Vector3(0, 1.0, 3.5)
	_engine_audio.max_distance = 120.0
	_engine_audio.stop()
	var cargo := Node3D.new()
	cargo.name = "Cargo"
	add_child(cargo)
	apply_state(Game.rv_state)
	add_to_group("rv")

# ------------------------------------------------------------------ build
func _shape(pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	add_child(cs)

func _build_collision() -> void:
	var L := FRONT_Z - REAR_Z
	var mid := (FRONT_Z + REAR_Z) * 0.5
	var h := ROOF_Y - FLOOR_Y
	_shape(Vector3(0, FLOOR_Y - 0.15, mid), Vector3(W, 0.3, L))
	_shape(Vector3(0, ROOF_Y + 0.08, mid), Vector3(W, 0.16, L))
	_shape(Vector3(-W * 0.5, FLOOR_Y + h * 0.5, mid), Vector3(0.12, h, L))
	var rear_len := DOOR_Z0 - REAR_Z
	_shape(Vector3(W * 0.5, FLOOR_Y + h * 0.5, REAR_Z + rear_len * 0.5), Vector3(0.12, h, rear_len))
	var front_len := FRONT_Z - DOOR_Z1
	_shape(Vector3(W * 0.5, FLOOR_Y + h * 0.5, DOOR_Z1 + front_len * 0.5), Vector3(0.12, h, front_len))
	_shape(Vector3(W * 0.5, FLOOR_Y + DOOR_H + (h - DOOR_H) * 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.12, h - DOOR_H, DOOR_Z1 - DOOR_Z0))
	_shape(Vector3(0, FLOOR_Y + h * 0.5, REAR_Z), Vector3(W, h, 0.12))
	_shape(Vector3(0, FLOOR_Y + h * 0.5, FRONT_Z + 0.05), Vector3(W, h, 0.12))
	_shape(Vector3(0, 1.15, FRONT_Z + 0.6), Vector3(W - 0.1, 0.9, 1.2)) # hood/engine bay
	# door slab when closed
	_shape(Vector3(W * 0.5, FLOOR_Y + DOOR_H * 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.1, DOOR_H, DOOR_Z1 - DOOR_Z0))

func _build_wheels() -> void:
	for spec in [[-1.08, 2.55, true], [1.08, 2.55, true], [-1.08, -2.35, false], [1.08, -2.35, false]]:
		var w := VehicleWheel3D.new()
		w.position = Vector3(spec[0], 0.62, spec[1])
		w.use_as_steering = spec[2]
		w.use_as_traction = not spec[2]
		w.wheel_radius = 0.46
		w.wheel_rest_length = 0.32
		w.suspension_travel = 0.28
		w.suspension_stiffness = 50.0
		w.suspension_max_force = 80000.0
		w.damping_compression = 1.6
		w.damping_relaxation = 2.2
		w.wheel_friction_slip = 2.4
		w.wheel_roll_influence = 0.04
		add_child(w)
		var holder := Node3D.new()
		holder.rotation.z = -PI * 0.5 if spec[0] > 0.0 else PI * 0.5
		holder.scale = Vector3.ONE * 1.31
		w.add_child(holder)
		var tire := MeshInstance3D.new()
		tire.mesh = Items.mesh("tire")
		tire.position.y = -0.12
		holder.add_child(tire)
		w.set_meta("tire_mesh", tire)
		w.set_meta("hub_mesh", Mounts.hub(holder))
		_part(Vector3(spec[0] + signf(spec[0]) * 0.12, 0.62, spec[1]), Vector3(0.4, 1.0, 1.1), "wheel%d" % wheels.size())
		wheels.append(w)

func _paint_mat() -> StandardMaterial3D:
	var m := Lib.mat("rv_paint", Color.WHITE, 0.35, false, 0.55).duplicate()
	_paint_mats.append(m)
	return m

func _build_exterior() -> void:
	var white := Lib.mat("rv_paint", Color.WHITE, 0.35, false, 0.55)
	var stripe := _paint_mat()
	var dark := Lib.color_mat(Color(0.12, 0.12, 0.13), 0.6)
	var chrome := Lib.color_mat(Color(0.8, 0.8, 0.8), 0.2, 0.9)
	var L := FRONT_Z - REAR_Z
	var mid := (FRONT_Z + REAR_Z) * 0.5
	var h := ROOF_Y - FLOOR_Y
	var vis := Node3D.new()
	vis.name = "Exterior"
	add_child(vis)
	# Smooth Class-C motorhome shell: over-cab nose, sloped hood, wheel arches, rounded edges.
	var body := Shapes.st()
	var glass := Shapes.st()
	var trim := Shapes.st()
	var deco := Shapes.st()
	var o := Shapes.arched_bottom(REAR_Z - 0.05, FRONT_Z + 1.25, 0.72, [[-2.35, 0.6], [2.55, 0.6]])
	for pt in [Vector2(FRONT_Z + 1.32, 1.0), Vector2(FRONT_Z + 1.24, 1.6), Vector2(FRONT_Z + 0.22, 1.72), Vector2(FRONT_Z - 0.12, 2.5),
			Vector2(FRONT_Z + 0.45, 2.58), Vector2(FRONT_Z + 0.62, 2.88), Vector2(FRONT_Z + 0.5, 3.25), Vector2(FRONT_Z + 0.05, ROOF_Y + 0.2),
			Vector2(REAR_Z + 0.25, ROOF_Y + 0.2), Vector2(REAR_Z - 0.05, ROOF_Y - 0.1)]:
		o.append(pt)
	var ws_edge := o.size() - 8
	Shapes.extrude(body, glass, o, W + 0.06, 0.16, [ws_edge])
	var xo := W * 0.5 + 0.035
	for side in [-1.0, 1.0]:
		var wins: Array = [[0.0, 1.6, 1.75, 2.6], [-2.6, -1.6, 1.85, 2.55], [2.35, 3.25, 1.85, 2.5]] if side < 0.0 else [[-1.1, 0.1, 1.85, 2.55], [-3.1, -2.2, 2.2, 2.6], [2.35, 3.25, 1.85, 2.5]]
		for wn in wins:
			var poly := PackedVector2Array([Vector2(wn[0], wn[2]), Vector2(wn[1], wn[2]), Vector2(wn[1], wn[3]), Vector2(wn[0], wn[3])])
			Shapes.side_panel(trim, Shapes.shrink(poly, -0.05), side * (xo + 0.002), side)
			Shapes.side_panel(glass, poly, side * (xo + 0.006), side)
		# swoosh decals in the customizable paint colour
		Shapes.side_panel(deco, PackedVector2Array([Vector2(REAR_Z, 1.15), Vector2(FRONT_Z + 1.2, 1.15), Vector2(FRONT_Z + 1.2, 1.3), Vector2(REAR_Z, 1.3)]), side * (xo + 0.003), side)
		Shapes.side_panel(deco, PackedVector2Array([Vector2(REAR_Z, 1.38), Vector2(-0.5, 1.38), Vector2(1.5, 1.62), Vector2(FRONT_Z + 0.6, 1.62), Vector2(FRONT_Z + 0.6, 1.68), Vector2(1.5, 1.68), Vector2(-0.5, 1.44), Vector2(REAR_Z, 1.44)]), side * (xo + 0.003), side)
		Shapes.side_panel(trim, PackedVector2Array([Vector2(REAR_Z, 0.72), Vector2(FRONT_Z + 1.25, 0.72), Vector2(FRONT_Z + 1.25, 0.82), Vector2(REAR_Z, 0.82)]), side * (xo + 0.002), side)
	var shell := MeshInstance3D.new()
	shell.mesh = Shapes.commit([[body, white], [glass, Lib.glass_mat()], [trim, Lib.mat("rubber", Color(0.5, 0.5, 0.5), 2.0, false, 0.8)], [deco, stripe]])
	vis.add_child(shell)
	# inner face of the entry door (so the closed door isn't see-through from inside)
	Lib.box(vis, Vector3(W * 0.5 - 0.05, FLOOR_Y + DOOR_H * 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.03, DOOR_H, DOOR_Z1 - DOOR_Z0), Lib.color_mat(Color(0.88, 0.86, 0.82), 0.8))
	Lib.box(vis, Vector3(0, 1.2, FRONT_Z + 1.26), Vector3(1.3, 0.45, 0.04), dark)
	for k in range(5):
		Lib.box(vis, Vector3(0, 1.02 + k * 0.09, FRONT_Z + 1.28), Vector3(1.25, 0.025, 0.02), chrome)
	Lib.box(vis, Vector3(0, 0.75, FRONT_Z + 1.3), Vector3(W + 0.1, 0.22, 0.16), chrome)
	Lib.box(vis, Vector3(0, 0.75, REAR_Z - 0.12), Vector3(W + 0.1, 0.22, 0.16), chrome)
	# headlights + taillights
	for x in [-0.85, 0.85]:
		var hm := Lib.color_mat(Color(0.95, 0.95, 0.9), 0.1, 0.0, Color(1.0, 0.95, 0.8), 0.0).duplicate()
		_head_mats.append(hm)
		Lib.box(vis, Vector3(x, 1.25, FRONT_Z + 1.27), Vector3(0.4, 0.22, 0.04), hm)
		var sp := SpotLight3D.new()
		sp.position = Vector3(x, 1.25, FRONT_Z + 1.3)
		sp.rotation.x = deg_to_rad(-5)
		sp.rotation.y = PI
		sp.spot_range = 45.0
		sp.spot_angle = 32.0
		sp.light_energy = 6.0
		sp.light_color = Color(1.0, 0.95, 0.85)
		sp.shadow_enabled = false
		sp.visible = false
		vis.add_child(sp)
		_head_spots.append(sp)
	_tail_mat = Lib.color_mat(Color(0.5, 0.05, 0.05), 0.3, 0.0, Color(1, 0.1, 0.05), 0.2).duplicate()
	for x in [-1.0, 1.0]:
		Lib.box(vis, Vector3(x, 1.3, REAR_Z - 0.07), Vector3(0.18, 0.5, 0.04), _tail_mat)
	# mirrors
	for x in [-1.35, 1.35]:
		Lib.box(vis, Vector3(x, 2.2, FRONT_Z + 0.1), Vector3(0.06, 0.35, 0.2), dark)
	# roof AC, vent, ladder, spare tire, awning
	Lib.box(vis, Vector3(0, ROOF_Y + 0.38, -0.6), Vector3(0.9, 0.36, 1.1), white)
	Lib.box(vis, Vector3(0, ROOF_Y + 0.22, 1.6), Vector3(0.55, 0.08, 0.55), Lib.glass_mat())
	for x in [0.55, 0.95]:
		Lib.box(vis, Vector3(x, 2.1, REAR_Z - 0.18), Vector3(0.04, 2.0, 0.04), chrome)
	for k in range(6):
		Lib.box(vis, Vector3(0.75, 1.3 + k * 0.32, REAR_Z - 0.18), Vector3(0.4, 0.03, 0.03), chrome)
	var spare := Lib.cyl(vis, Vector3(-0.55, 1.5, REAR_Z - 0.28), 0.42, 0.42, 0.25, Lib.color_mat(Color(0.06, 0.06, 0.06), 0.95), Vector3(PI * 0.5, 0, 0))
	spare.name = "Spare"
	Lib.cyl(vis, Vector3(W * 0.5 + 0.12, 3.0, -1.2), 0.1, 0.1, 4.0, Lib.mat("canvas", Color(0.75, 0.5, 0.3), 0.6, false), Vector3(PI * 0.5, 0, 0))
	# door panel (exterior)
	_door_panel = Node3D.new()
	_door_panel.position = Vector3(W * 0.5 + 0.04, FLOOR_Y, DOOR_Z1)
	vis.add_child(_door_panel)
	Lib.box(_door_panel, Vector3(0, DOOR_H * 0.5, -(DOOR_Z1 - DOOR_Z0) * 0.5), Vector3(0.05, DOOR_H - 0.02, DOOR_Z1 - DOOR_Z0), white)
	Lib.box(_door_panel, Vector3(0.03, 1.6, -(DOOR_Z1 - DOOR_Z0) * 0.5), Vector3(0.02, 0.5, 0.5), Lib.glass_mat())
	Lib.box(_door_panel, Vector3(0.05, 1.0, -(DOOR_Z1 - DOOR_Z0) + 0.12), Vector3(0.04, 0.05, 0.14), chrome)
	# entry step
	Lib.box(vis, Vector3(W * 0.5 + 0.25, 0.55, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.45, 0.06, 0.8), Lib.color_mat(Color(0.3, 0.3, 0.3), 0.6, 0.6))
	# solar panel & bull bar (upgrades)
	_solar = Node3D.new()
	vis.add_child(_solar)
	Lib.box(_solar, Vector3(0, ROOF_Y + 0.28, -2.2), Vector3(1.6, 0.05, 1.6), Lib.color_mat(Color(0.08, 0.12, 0.25), 0.15, 0.6))
	_bullbar = Node3D.new()
	vis.add_child(_bullbar)
	for x in [-0.9, 0.9]:
		Lib.box(_bullbar, Vector3(x, 1.05, FRONT_Z + 1.45), Vector3(0.08, 0.8, 0.08), chrome)
	Lib.box(_bullbar, Vector3(0, 1.45, FRONT_Z + 1.45), Vector3(1.9, 0.08, 0.08), chrome)
	Lib.box(_bullbar, Vector3(0, 0.95, FRONT_Z + 1.45), Vector3(1.9, 0.08, 0.08), chrome)
	# battery tray on the driver side, just behind the front wheel: the battery sits in plain view
	var tray := Vector3(-W * 0.5 - 0.22, 0.78, 1.35)
	Lib.box(vis, tray + Vector3(0, -0.04, 0), Vector3(0.42, 0.05, 0.56), dark)
	Lib.box(vis, tray + Vector3(0.2, 0.12, 0), Vector3(0.03, 0.3, 0.56), dark)
	for dz in [-0.26, 0.26]:
		Lib.box(vis, tray + Vector3(0, 0.03, dz), Vector3(0.42, 0.1, 0.03), dark)
	_battery_vis = Node3D.new()
	_battery_vis.position = tray + Vector3(-0.02, -0.015, 0)
	_battery_vis.rotation.y = PI * 0.5
	vis.add_child(_battery_vis)
	var bm := MeshInstance3D.new()
	bm.mesh = Items.mesh("car_battery")
	bm.scale = Vector3.ONE * 1.6
	_battery_vis.add_child(bm)
	_part(tray + Vector3(-0.02, 0.15, 0), Vector3(0.5, 0.42, 0.62), "battery")
	# outside interactables
	_part(Vector3(0, 1.75, FRONT_Z + 0.7), Vector3(W, 0.3, 1.1), "hood")
	_part(Vector3(-W * 0.5 - 0.1, 1.2, -2.8), Vector3(0.25, 0.4, 0.4), "fuel")
	Lib.box(vis, Vector3(-W * 0.5 - 0.06, 1.2, -2.8), Vector3(0.04, 0.22, 0.22), dark)
	_part(Vector3(W * 0.5 + 0.12, FLOOR_Y + 1.0, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.14, 2.0, DOOR_Z1 - DOOR_Z0), "door")

## Wall along Z at x with rectangular holes [z0, z1, y0, y1] (absolute y).
func _wall_x(parent: Node3D, x: float, m: Material, holes: Array) -> void:
	var z_edges: Array[float] = [REAR_Z, FRONT_Z]
	for hole in holes:
		z_edges.append(hole[0])
		z_edges.append(hole[1])
	z_edges.sort()
	for i in range(z_edges.size() - 1):
		var z0 := z_edges[i]
		var z1 := z_edges[i + 1]
		if z1 - z0 < 0.001:
			continue
		var zc := (z0 + z1) * 0.5
		var ys: Array = [[FLOOR_Y - 0.0, ROOF_Y]]
		for hole in holes:
			if zc > hole[0] and zc < hole[1]:
				ys = [[FLOOR_Y, maxf(hole[2], FLOOR_Y)], [hole[3], ROOF_Y]]
				if hole[2] > FLOOR_Y + 0.1 and hole[3] - hole[2] < 2.0:
					var g := Lib.box(parent, Vector3(x, (hole[2] + hole[3]) * 0.5, zc), Vector3(0.03, hole[3] - hole[2], z1 - z0), Lib.glass_mat())
					g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					var trim := Lib.mat("rubber", Color(0.6, 0.6, 0.6), 2.0, false, 0.8)
					for yy in [hole[2], hole[3]]:
						Lib.box(parent, Vector3(x, yy, zc), Vector3(0.08, 0.05, z1 - z0 + 0.05), trim)
					for zz in [z0, z1]:
						Lib.box(parent, Vector3(x, (hole[2] + hole[3]) * 0.5, zz), Vector3(0.08, hole[3] - hole[2] + 0.05, 0.05), trim)
		for yr in ys:
			if yr[1] - yr[0] > 0.01:
				Lib.box(parent, Vector3(x, (yr[0] + yr[1]) * 0.5, zc), Vector3(0.06, yr[1] - yr[0], z1 - z0), m)

func _part(pos: Vector3, size: Vector3, action: String) -> StaticBody3D:
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
	return b

var _doors := {} # action -> {"pivot": Node3D, "open": bool, "angle": float}
var _battery_vis: Node3D

## Real RV materials: off-white wall board, vinyl plank floor, laminate cabinetry, fabric
## upholstery and a plastic dash — no bare lumber.
func _interior_mats() -> Dictionary:
	return {
		"wall": Lib.color_mat(Color(0.88, 0.86, 0.82), 0.8),
		"ceiling": Lib.color_mat(Color(0.93, 0.92, 0.9), 0.9),
		"floor": Lib.mat("tiles", Color(0.62, 0.58, 0.52), 1.1, false, 0.55),
		"cab": Lib.color_mat(Color(0.8, 0.78, 0.74), 0.4),
		"cab_trim": Lib.color_mat(Color(0.36, 0.35, 0.34), 0.5),
		"counter": Lib.mat("concrete", Color(0.55, 0.55, 0.56), 1.0, false, 0.35),
		"fabric": Lib.mat("denim", Color(0.62, 0.64, 0.68), 2.5, false, 0.95),
		"fabric2": Lib.mat("plaid", Color(0.75, 0.75, 0.78), 2.0, false, 0.95),
		"metal": Lib.color_mat(Color(0.72, 0.72, 0.74), 0.3, 0.8),
		"plastic": Lib.color_mat(Color(0.14, 0.14, 0.15), 0.55),
		"black": Lib.color_mat(Color(0.06, 0.06, 0.06), 0.5),
	}

## A cupboard or fridge whose front faces +X, with shelves you can put things on and a
## door you open and close. center/size are the outer box in RV space.
func _cupboard(vis: Node3D, action: String, center: Vector3, size: Vector3, shelves: Array, body_m: Material, door_m: Material, trim: Material) -> void:
	var t := 0.03
	var front := center.x + size.x * 0.5
	var back := center.x - size.x * 0.5
	var bottom := center.y - size.y * 0.5
	var top := center.y + size.y * 0.5
	var z0 := center.z - size.z * 0.5
	var z1 := center.z + size.z * 0.5
	var pieces := [
		[Vector3(back + t * 0.5, center.y, center.z), Vector3(t, size.y, size.z)],
		[Vector3(center.x, center.y, z0 + t * 0.5), Vector3(size.x, size.y, t)],
		[Vector3(center.x, center.y, z1 - t * 0.5), Vector3(size.x, size.y, t)],
		[Vector3(center.x, top - t * 0.5, center.z), Vector3(size.x, t, size.z)],
		[Vector3(center.x, bottom + t * 0.5, center.z), Vector3(size.x, t, size.z)],
	]
	for y in shelves:
		pieces.append([Vector3(center.x - 0.01, y, center.z), Vector3(size.x - 0.04, 0.02, size.z - 2 * t)])
	for pc in pieces:
		Lib.box(vis, pc[0], pc[1], body_m)
		_shape(pc[0], pc[1])
	# inside light colour for fridges, plain inside for cupboards
	Lib.box(vis, Vector3(back + t + 0.005, center.y, center.z), Vector3(0.01, size.y - 2 * t, size.z - 2 * t), Lib.color_mat(Color(0.95, 0.96, 0.97), 0.3) if action == "fridge" else body_m)
	var pivot := Node3D.new()
	pivot.position = Vector3(front, center.y, z0)
	vis.add_child(pivot)
	Lib.box(pivot, Vector3(0.02, 0, size.z * 0.5), Vector3(0.035, size.y, size.z), door_m)
	Lib.box(pivot, Vector3(0.045, 0, size.z * 0.5), Vector3(0.01, size.y - 0.04, size.z - 0.04), trim)
	Lib.box(pivot, Vector3(0.06, 0.0 if size.y < 0.8 else 0.1, size.z - 0.07), Vector3(0.025, minf(size.y * 0.4, 0.35), 0.025), Lib.color_mat(Color(0.75, 0.75, 0.78), 0.3, 0.8))
	var hs := StaticBody3D.new()
	hs.set_script(RvPart)
	hs.rv = self
	hs.action = action
	hs.collision_layer = 2
	hs.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.08, size.y, size.z)
	cs.shape = sh
	cs.position = Vector3(0.03, 0, size.z * 0.5)
	hs.add_child(cs)
	pivot.add_child(hs)
	_doors[action] = {"pivot": pivot, "open": false}

func _toggle_door(action: String) -> void:
	var d: Dictionary = _doors[action]
	d["open"] = not d["open"]
	var tw := create_tween()
	tw.tween_property(d["pivot"], "rotation:y", -1.75 if d["open"] else 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	Audio.play_at("door", d["pivot"].global_position, -10.0, 1.4)

func _build_interior() -> void:
	var M := _interior_mats()
	var L := FRONT_Z - REAR_Z
	var mid := (FRONT_Z + REAR_Z) * 0.5
	var h := ROOF_Y - FLOOR_Y
	var vis := Node3D.new()
	vis.name = "Interior"
	add_child(vis)
	Lib.box(vis, Vector3(0, FLOOR_Y + 0.01, mid), Vector3(W - 0.14, 0.02, L - 0.1), M["floor"])
	Lib.box(vis, Vector3(0, ROOF_Y - 0.03, mid), Vector3(W - 0.14, 0.04, L - 0.1), M["ceiling"])
	_wall_x(vis, -W * 0.5 + 0.08, M["wall"], [[0.0, 1.6, 1.75, 2.6], [-2.6, -1.6, 1.85, 2.55], [2.35, 3.25, 1.85, 2.5]])
	_wall_x(vis, W * 0.5 - 0.08, M["wall"], [[-1.1, 0.1, 1.85, 2.55], [DOOR_Z0, DOOR_Z1, 0.0, FLOOR_Y + DOOR_H], [-3.1, -2.2, 2.2, 2.6], [2.35, 3.25, 1.85, 2.5]])
	Lib.box(vis, Vector3(0, FLOOR_Y + h * 0.5, REAR_Z + 0.08), Vector3(W - 0.14, h, 0.04), M["wall"])
	# baseboards / trim lines along the walls
	for x in [-W * 0.5 + 0.11, W * 0.5 - 0.11]:
		Lib.box(vis, Vector3(x, FLOOR_Y + 0.05, mid), Vector3(0.02, 0.08, L - 0.2), M["cab_trim"])
		Lib.box(vis, Vector3(x, ROOF_Y - 0.08, mid), Vector3(0.03, 0.05, L - 0.2), M["cab_trim"])
	# ---- cab: moulded dashboard with gauges, centre console, captain's seats
	var dash_c := Vector3(0, FLOOR_Y + 0.75, FRONT_Z - 0.05)
	Lib.box(vis, dash_c, Vector3(W - 0.15, 0.5, 0.5), M["plastic"], false, Vector3.ZERO, 0.06)
	Lib.box(vis, dash_c + Vector3(0, 0.26, -0.05), Vector3(W - 0.2, 0.03, 0.45), Lib.color_mat(Color(0.2, 0.2, 0.21), 0.7))
	_shape(dash_c, Vector3(W - 0.15, 0.5, 0.5))
	var cluster := Lib.box(vis, Vector3(-0.55, FLOOR_Y + 0.92, FRONT_Z - 0.31), Vector3(0.5, 0.18, 0.04), Lib.color_mat(Color(0.05, 0.05, 0.06), 0.3))
	cluster.rotation.x = -0.3
	for gx in [-0.68, -0.42]:
		var g := Lib.cyl(vis, Vector3(gx, FLOOR_Y + 0.92, FRONT_Z - 0.335), 0.06, 0.06, 0.01, Lib.color_mat(Color(0.9, 0.9, 0.85), 0.3, 0.0, Color(0.5, 0.9, 1.0), 0.5), Vector3(PI * 0.5 - 0.3, 0, 0))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Lib.box(vis, Vector3(0.05, FLOOR_Y + 0.85, FRONT_Z - 0.31), Vector3(0.22, 0.14, 0.03), Lib.color_mat(Color(0.1, 0.15, 0.12), 0.3, 0.0, Color(0.4, 0.9, 0.5), 0.5))
	for vx in [-0.95, 0.35, 0.95]:
		Lib.box(vis, Vector3(vx, FLOOR_Y + 0.85, FRONT_Z - 0.31), Vector3(0.16, 0.08, 0.02), M["black"])
	var sw := Lib.cyl(vis, Vector3(-0.55, FLOOR_Y + 0.82, FRONT_Z - 0.42), 0.17, 0.17, 0.03, M["black"], Vector3(-1.1, 0, 0), 20)
	sw.name = "SteeringWheel"
	Lib.box(vis, Vector3(0, FLOOR_Y + 0.25, FRONT_Z - 0.75), Vector3(0.3, 0.5, 0.6), M["plastic"], false, Vector3.ZERO, 0.04)
	for x in [-0.55, 0.55]:
		Lib.box(vis, Vector3(x, FLOOR_Y + 0.45, FRONT_Z - 1.05), Vector3(0.58, 0.14, 0.58), M["fabric"], false, Vector3.ZERO, 0.05)
		Lib.box(vis, Vector3(x, FLOOR_Y + 0.92, FRONT_Z - 1.35), Vector3(0.56, 0.85, 0.14), M["fabric"], false, Vector3(-0.15, 0, 0), 0.05)
		Lib.box(vis, Vector3(x, FLOOR_Y + 1.42, FRONT_Z - 1.42), Vector3(0.3, 0.16, 0.1), M["fabric"], false, Vector3(-0.15, 0, 0), 0.04)
		Lib.box(vis, Vector3(x, FLOOR_Y + 0.2, FRONT_Z - 1.05), Vector3(0.4, 0.38, 0.4), M["black"])
	_part(Vector3(-0.55, FLOOR_Y + 0.6, FRONT_Z - 1.1), Vector3(0.6, 0.9, 0.6), "drive")
	_part(Vector3(0.55, FLOOR_Y + 0.6, FRONT_Z - 1.1), Vector3(0.6, 0.9, 0.6), "passenger")
	# over-cab bunk shelf (you can store things up there)
	Lib.box(vis, Vector3(0, ROOF_Y - 0.55, FRONT_Z + 0.25), Vector3(W - 0.2, 0.06, 0.9), M["cab"])
	_shape(Vector3(0, ROOF_Y - 0.55, FRONT_Z + 0.25), Vector3(W - 0.2, 0.06, 0.9))
	Lib.box(vis, Vector3(0, ROOF_Y - 0.47, FRONT_Z - 0.19), Vector3(W - 0.2, 0.12, 0.03), M["cab_trim"])
	# ---- galley (left wall): counter, stove, sink, coffee maker
	var kz0 := -0.2
	var kz1 := 1.5
	var kx := -W * 0.5 + 0.38
	Lib.box(vis, Vector3(kx, FLOOR_Y + 0.45, (kz0 + kz1) * 0.5), Vector3(0.6, 0.9, kz1 - kz0), M["cab"])
	for dz in [0.15, 0.55, 0.95, 1.3]:
		Lib.box(vis, Vector3(kx + 0.305, FLOOR_Y + 0.45, kz0 + dz), Vector3(0.01, 0.8, 0.005), M["cab_trim"])
		Lib.box(vis, Vector3(kx + 0.32, FLOOR_Y + 0.75, kz0 + dz - 0.12), Vector3(0.02, 0.02, 0.1), M["metal"])
	Lib.box(vis, Vector3(kx, FLOOR_Y + 0.92, (kz0 + kz1) * 0.5), Vector3(0.64, 0.05, kz1 - kz0 + 0.02), M["counter"])
	_shape(Vector3(kx, FLOOR_Y + 0.4725, (kz0 + kz1) * 0.5), Vector3(0.64, 0.945, kz1 - kz0 + 0.02))
	Lib.box(vis, Vector3(-W * 0.5 + 0.1, FLOOR_Y + 1.15, (kz0 + kz1) * 0.5), Vector3(0.01, 0.4, kz1 - kz0), Lib.mat("tiles", Color(0.85, 0.85, 0.82), 2.5, false, 0.3))
	Lib.box(vis, Vector3(kx, FLOOR_Y + 0.95, 1.1), Vector3(0.5, 0.02, 0.55), M["black"])
	for p in [Vector2(-0.12, 0.95), Vector2(0.12, 0.95), Vector2(-0.12, 1.25), Vector2(0.12, 1.25)]:
		Lib.cyl(vis, Vector3(kx + p.x, FLOOR_Y + 0.965, p.y), 0.08, 0.08, 0.01, Lib.color_mat(Color(0.25, 0.25, 0.25), 0.4, 0.7))
	_part(Vector3(kx, FLOOR_Y + 0.98, 1.1), Vector3(0.5, 0.06, 0.55), "stove")
	Lib.box(vis, Vector3(kx, FLOOR_Y + 0.92, 0.35), Vector3(0.42, 0.06, 0.38), M["metal"])
	Lib.cyl(vis, Vector3(-W * 0.5 + 0.18, FLOOR_Y + 1.12, 0.35), 0.015, 0.015, 0.35, M["metal"])
	_part(Vector3(-W * 0.5 + 0.2, FLOOR_Y + 1.12, 0.35), Vector3(0.12, 0.35, 0.3), "sink")
	Lib.box(vis, Vector3(-W * 0.5 + 0.3, FLOOR_Y + 1.08, -0.05), Vector3(0.2, 0.28, 0.2), M["black"])
	Lib.cyl(vis, Vector3(-W * 0.5 + 0.34, FLOOR_Y + 1.0, -0.05), 0.06, 0.05, 0.12, Lib.glass_mat())
	_part(Vector3(-W * 0.5 + 0.3, FLOOR_Y + 1.08, -0.05), Vector3(0.24, 0.3, 0.22), "coffee")
	# overhead cupboard above the galley
	_cupboard(vis, "overhead", Vector3(-W * 0.5 + 0.3, ROOF_Y - 0.33, 0.65), Vector3(0.44, 0.5, 1.6), [], M["cab"], M["cab"], M["cab_trim"])
	# fridge
	_cupboard(vis, "fridge", Vector3(-W * 0.5 + 0.42, FLOOR_Y + 0.86, -0.67), Vector3(0.62, 1.7, 0.68), [FLOOR_Y + 0.5, FLOOR_Y + 0.95, FLOOR_Y + 1.35],
		Lib.color_mat(Color(0.93, 0.93, 0.91), 0.3), Lib.color_mat(Color(0.88, 0.88, 0.86), 0.25), Lib.color_mat(Color(0.8, 0.8, 0.78), 0.25))
	# storage cupboard (plant pots on top)
	_cupboard(vis, "cabinet", Vector3(-W * 0.5 + 0.36, FLOOR_Y + 0.5, -1.45), Vector3(0.56, 1.0, 0.8), [FLOOR_Y + 0.5], M["cab"], M["cab"], M["cab_trim"])
	for i in range(2):
		var pot := StaticBody3D.new()
		pot.set_script(Structure)
		pot.persistent = false
		var pot_index := i
		pot.save_cb = func(d: Dictionary) -> void: pots[pot_index] = d
		vis.add_child(pot)
		pot.setup("", {"type": "planter", "pos": [-W * 0.5 + 0.35, FLOOR_Y + 1.0, -1.65 + i * 0.42], "rot": PI * 0.5, "data": pots[i]})
		pot.scale = Vector3(0.25, 0.6, 0.45)
		pot.collision_layer = 2
		pot.collision_mask = 0
		pot.name = "Pot%d" % i
	# ---- dinette (right side): table and two benches
	var tx := W * 0.5 - 0.45
	Lib.box(vis, Vector3(tx, FLOOR_Y + 0.72, -0.5), Vector3(0.7, 0.04, 0.9), M["counter"], false, Vector3.ZERO, 0.015)
	Lib.box(vis, Vector3(tx, FLOOR_Y + 0.69, -0.5), Vector3(0.72, 0.02, 0.92), M["cab_trim"])
	_shape(Vector3(tx, FLOOR_Y + 0.72, -0.5), Vector3(0.7, 0.05, 0.9))
	Lib.cyl(vis, Vector3(tx, FLOOR_Y + 0.36, -0.5), 0.04, 0.04, 0.72, M["metal"])
	for z in [0.25, -1.25]:
		Lib.box(vis, Vector3(W * 0.5 - 0.42, FLOOR_Y + 0.22, z), Vector3(0.75, 0.44, 0.45), M["cab"])
		Lib.box(vis, Vector3(W * 0.5 - 0.42, FLOOR_Y + 0.5, z), Vector3(0.75, 0.12, 0.45), M["fabric"], false, Vector3.ZERO, 0.04)
		Lib.box(vis, Vector3(W * 0.5 - 0.42, FLOOR_Y + 0.85, z + signf(z) * 0.17), Vector3(0.75, 0.6, 0.1), M["fabric"], false, Vector3.ZERO, 0.04)
		_shape(Vector3(W * 0.5 - 0.42, FLOOR_Y + 0.28, z), Vector3(0.75, 0.56, 0.45))
	# ---- bathroom cubicle (right rear)
	Lib.box(vis, Vector3(W * 0.5 - 0.5, FLOOR_Y + h * 0.5, -1.75), Vector3(0.9, h, 0.05), M["wall"])
	Lib.box(vis, Vector3(0.18, FLOOR_Y + h * 0.5, -2.2), Vector3(0.05, h, 0.95), M["wall"])
	var porcelain := Lib.color_mat(Color(0.95, 0.95, 0.95), 0.15)
	Lib.box(vis, Vector3(W * 0.5 - 0.45, FLOOR_Y + 0.22, -2.45), Vector3(0.38, 0.44, 0.45), porcelain, false, Vector3.ZERO, 0.08)
	Lib.box(vis, Vector3(W * 0.5 - 0.45, FLOOR_Y + 0.45, -2.45), Vector3(0.4, 0.04, 0.48), porcelain, false, Vector3.ZERO, 0.02)
	Lib.box(vis, Vector3(W * 0.5 - 0.3, FLOOR_Y + 0.7, -2.45), Vector3(0.12, 0.45, 0.4), porcelain, false, Vector3.ZERO, 0.03)
	_part(Vector3(W * 0.5 - 0.45, FLOOR_Y + 0.4, -2.45), Vector3(0.5, 0.8, 0.5), "toilet")
	# ---- rear bed: laminate platform, mattress, duvet, pillows
	Lib.box(vis, Vector3(-0.25, FLOOR_Y + 0.3, -2.75), Vector3(1.85, 0.6, 1.2), M["cab"])
	Lib.box(vis, Vector3(-0.25, FLOOR_Y + 0.68, -2.75), Vector3(1.8, 0.18, 1.15), Lib.color_mat(Color(0.92, 0.92, 0.9), 0.95), false, Vector3.ZERO, 0.06)
	Lib.box(vis, Vector3(-0.85, FLOOR_Y + 0.82, -2.75), Vector3(0.35, 0.1, 0.8), Lib.color_mat(Color("eae6dd"), 0.95), false, Vector3.ZERO, 0.04)
	Lib.box(vis, Vector3(0.1, FLOOR_Y + 0.79, -2.75), Vector3(1.1, 0.06, 1.17), M["fabric2"], false, Vector3.ZERO, 0.02)
	_shape(Vector3(-0.25, FLOOR_Y + 0.385, -2.75), Vector3(1.85, 0.77, 1.2))
	_part(Vector3(-0.85, FLOOR_Y + 0.9, -2.75), Vector3(0.4, 0.15, 0.85), "bed")
	# light switch + interior lights
	Lib.box(vis, Vector3(W * 0.5 - 0.1, FLOOR_Y + 1.4, DOOR_Z0 - 0.12), Vector3(0.03, 0.12, 0.08), Lib.color_mat(Color(0.9, 0.9, 0.85)))
	_part(Vector3(W * 0.5 - 0.12, FLOOR_Y + 1.4, DOOR_Z0 - 0.12), Vector3(0.1, 0.25, 0.2), "lights")
	_part(Vector3(W * 0.5 - 0.15, FLOOR_Y + 1.0, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.12, 2.0, DOOR_Z1 - DOOR_Z0), "door")
	for z in [-1.8, 0.6]:
		Lib.cyl(vis, Vector3(0, ROOF_Y - 0.06, z), 0.17, 0.17, 0.03, Lib.color_mat(Color(1, 0.95, 0.85), 0.5, 0.0, Color(1, 0.9, 0.7), 1.0))
	_interior_light = Lib.light(vis, Vector3(0, ROOF_Y - 0.3, -0.5), Color(1.0, 0.86, 0.66), 1.4, 6.0, false)
	_interior_light.visible = false
	# runner rug
	Lib.box(vis, Vector3(0.0, FLOOR_Y + 0.025, -0.3), Vector3(0.7, 0.01, 1.8), Lib.mat("carpet", Color(0.45, 0.42, 0.4), 1.5, false))

## Your few starting supplies sit in the RV — pick them up when you need them.
func stock_starter_supplies() -> void:
	_stock("water_clean", 1, Vector3(-W * 0.5 + 0.36, FLOOR_Y + 0.945, 0.7))
	_stock("water_clean", 1, Vector3(-W * 0.5 + 0.36, FLOOR_Y + 0.945, 0.86))
	_stock("canned_food", 1, Vector3(W * 0.5 - 0.5, FLOOR_Y + 0.745, -0.35))
	_stock("rope", 1, Vector3(W * 0.5 - 0.42, FLOOR_Y + 0.745, -0.7))
	_stock("bandage", 1, Vector3(-W * 0.5 + 0.32, FLOOR_Y + 1.01, -1.35))
	_stock("seeds_tomato", 1, Vector3(-W * 0.5 + 0.32, FLOOR_Y + 0.52, -1.5))
	_stock("toolkit", 1, Vector3(0.25, FLOOR_Y + 0.015, -1.9))

func _stock(id: String, n: int, lp: Vector3, yaw := 0.0) -> void:
	var bb: AABB = Items.display_bounds(id)
	var xf := global_transform * Transform3D(Basis(Vector3.UP, yaw), lp - Vector3(0, bb.position.y, 0))
	Game.place_item(id, n, xf, self)

## Older saves kept the fridge/cabinet as item lists: put those items on the shelves.
func _spill_legacy() -> void:
	var spots := {"fridge": [Vector3(-W * 0.5 + 0.42, FLOOR_Y + 0.52, -0.67), Vector3(-W * 0.5 + 0.42, FLOOR_Y + 0.97, -0.67), Vector3(-W * 0.5 + 0.42, FLOOR_Y + 1.37, -0.67)],
		"cabinet": [Vector3(-W * 0.5 + 0.36, FLOOR_Y + 0.04, -1.45), Vector3(-W * 0.5 + 0.36, FLOOR_Y + 0.52, -1.45)]}
	for which in ["fridge", "cabinet"]:
		var items: Dictionary = fridge if which == "fridge" else cabinet
		var i := 0
		for k in items:
			var n := int(items[k])
			while n > 0 and i < 18:
				var take := mini(n, Data.stack(k))
				var base: Vector3 = spots[which][i % spots[which].size()]
				_stock(k, take, base + Vector3(0, 0, -0.22 + (i / spots[which].size()) % 3 * 0.22))
				n -= take
				i += 1
		items.clear()

func _build_cameras() -> void:
	cam_fp = Camera3D.new()
	cam_fp.position = Vector3(-0.55, FLOOR_Y + 1.38, FRONT_Z - 1.2)
	cam_fp.rotation.y = PI
	cam_fp.near = 0.05
	cam_fp.far = 1200.0
	add_child(cam_fp)
	cam_tp = Camera3D.new()
	cam_tp.top_level = true
	cam_tp.far = 1500.0
	add_child(cam_tp)

# ------------------------------------------------------------------ state
func fuel_capacity() -> float:
	return 140.0 if upgrades.has("big_tank") else 80.0

func water_capacity() -> float:
	return 80.0 if upgrades.has("water_tank") else 40.0

func save_state() -> Dictionary:
	return {"xform": [Game.arr(global_position), [rotation.x, rotation.y, rotation.z]], "fuel": fuel, "water": water,
		"battery": battery, "parts": parts, "upgrades": upgrades, "paint": paint, "fridge": fridge,
		"cabinet": cabinet, "pots": pots, "odometer": odometer, "missing": missing, "attached": attached, "cargo": _cargo_records()}

func apply_state(s: Dictionary) -> void:
	if s.is_empty():
		_apply_visuals()
		return
	var xf: Array = s.get("xform", [])
	if xf.size() == 2:
		global_position = Game.v3(xf[0])
		rotation = Game.v3(xf[1])
	fuel = float(s.get("fuel", fuel))
	water = float(s.get("water", water))
	battery = float(s.get("battery", battery))
	var p: Dictionary = s.get("parts", {})
	for k in p:
		parts[k] = float(p[k])
	upgrades = s.get("upgrades", {})
	paint = int(s.get("paint", 0))
	fridge = s.get("fridge", fridge)
	cabinet = s.get("cabinet", cabinet)
	missing = s.get("missing", {})
	var sp: Array = s.get("pots", pots)
	pots = sp if sp.size() == 2 else pots
	odometer = float(s.get("odometer", 0.0))
	for ch in get_node("Cargo").get_children():
		ch.queue_free()
	attached = []
	for rec in s.get("attached", []):
		_spawn_attached(rec)
		attached.append(rec)
	for it in s.get("cargo", []):
		_spawn_cargo(it)
	for i in range(2):
		var pot := get_node_or_null("Interior/Pot%d" % i)
		if pot:
			pot.remote_data(pots[i])
	if not fridge.is_empty() or not cabinet.is_empty():
		call_deferred("_spill_legacy")
	_apply_visuals()

func _apply_visuals() -> void:
	var c: Color = Data.RV_PAINTS[paint % Data.RV_PAINTS.size()]
	for m in _paint_mats:
		m.albedo_color = c
	_solar.visible = upgrades.has("solar")
	_bullbar.visible = upgrades.has("bullbar")
	var grip := 3.0 if not upgrades.has("offroad_tires") else 3.6
	grip *= lerpf(0.55, 1.0, parts["tires"] / 100.0)
	Mounts.apply_wheels(self, grip)
	if _battery_vis:
		_battery_vis.visible = not missing.has("battery")

# ------------------------------------------------------------------ driving
func is_driven_locally() -> bool:
	return driver != 0 and driver == Net.my_id()

func speed_kmh() -> float:
	return linear_velocity.dot(global_transform.basis.z) * 3.6

func try_start_engine() -> void:
	if engine_on:
		return
	if fuel <= 0.1:
		Game.notify("Out of fuel! Use a fuel can on the fuel cap.")
		return
	if missing.has("battery"):
		Game.notify("There's no battery fitted. Carry a Car Battery to the battery tray.")
		return
	if battery < 5.0 or parts["battery"] < 5.0:
		Game.notify("The battery is dead. Pull it out of its tray and fit a Car Battery (or wait for the solar panel).")
		return
	if parts["engine"] <= 1.0:
		Game.notify("The engine is wrecked. Repair it at the hood.")
		return
	if parts["engine"] < 25.0 and randf() < 0.35:
		Audio.play_at("engine_start", global_position, 0.0, 0.8)
		Game.notify("The engine sputters... try again.")
		battery -= 2.0
		return
	engine_on = true
	battery -= 3.0
	Audio.play_at("engine_start", global_position)
	_engine_audio.play()

func stop_engine() -> void:
	engine_on = false
	_engine_audio.stop()

## The peer that simulates the RV: its driver, or the host while it is parked.
func is_authority() -> bool:
	if driver != 0:
		return driver == Net.my_id()
	return not Net.is_client()

func _physics_process(delta: float) -> void:
	if not is_authority():
		# Remote simulation: follow the network transform.
		freeze = true
		if _remote_has:
			global_transform = global_transform.interpolate_with(_remote_target, clampf(delta * 10.0, 0.0, 1.0))
		return
	var throttle := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var handbrake := false
	if is_driven_locally() and not Game.ui_open and not Game.paused:
		throttle = Input.get_action_strength("move_forward")
		brake_in = Input.get_action_strength("move_back")
		steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		handbrake = Input.is_action_pressed("jump")
	var fwd_speed := linear_velocity.dot(global_transform.basis.z)
	var power := 9500.0 * (1.35 if upgrades.has("engine_tune") else 1.0) * lerpf(0.65, 1.0, parts["engine"] / 100.0)
	power *= maxf(1.0 - 0.3 * Mounts.missing_count(self), 0.1)
	var top := 27.0 * (1.12 if upgrades.has("engine_tune") else 1.0)
	var force := 0.0
	var brk := 0.0
	if engine_on and fuel > 0.0:
		if throttle > 0.05:
			force = power * throttle * clampf(1.0 - fwd_speed / top, 0.0, 1.0)
		if brake_in > 0.05:
			if fwd_speed > 1.0:
				brk = 140.0 * brake_in
			else:
				force = -power * 0.6 * brake_in * clampf(1.0 + fwd_speed / 8.0, 0.0, 1.0)
	else:
		brk = 8.0 + brake_in * 60.0
	if driver == 0:
		brk = 90.0
	if handbrake:
		brk = 120.0
	engine_force = force
	brake = brk
	var steer_limit := lerpf(0.6, 0.2, clampf(absf(fwd_speed) / 25.0, 0.0, 1.0))
	_steer = move_toward(_steer, steer_in * steer_limit, delta * (3.5 if absf(steer_in) > 0.05 else 5.0))
	if throttle < 0.05 and brake_in < 0.05 and brk < 10.0:
		brk = 6.0 # engine braking when coasting
		brake = brk
	# Arcade stability: bleed off sideways slide and excess spin, keep the RV upright.
	if driver != 0:
		var lateral := linear_velocity.dot(global_transform.basis.x)
		apply_central_force(-global_transform.basis.x * lateral * mass * 1.8)
		var yaw_rate := angular_velocity.y
		if absf(steer_in) < 0.05:
			apply_torque(Vector3(0, -yaw_rate * mass * 2.5, 0))
		var up := global_transform.basis.y
		if up.y < 0.5 and linear_velocity.length() < 3.0:
			rotation = Vector3(0, rotation.y, 0)
			global_position += Vector3(0, 1.0, 0)
			angular_velocity = Vector3.ZERO
			Game.notify("The RV was set back on its wheels")
	steering = _steer
	_throttle = throttle
	var sw := get_node_or_null("Interior/SteeringWheel")
	if sw:
		sw.rotation = Vector3(-1.1, 0, -_steer * 4.0)
	# consumption & wear
	var spd := linear_velocity.length()
	if engine_on:
		var use := (0.0025 + 0.07 * throttle * clampf(spd / 22.0, 0.25, 1.0)) * Game.diff("fuel") * delta
		fuel = maxf(fuel - use, 0.0)
		battery = minf(battery + delta * 0.5, 100.0)
		if fuel <= 0.0:
			stop_engine()
			Game.notify("The engine dies — out of fuel.")
	var dist := spd * delta
	odometer += dist
	if dist > 0.0:
		var off_road := absf(global_position.x - Game.world.gen.road_x(global_position.z)) > 6.0
		var tire_wear := (0.25 if upgrades.has("offroad_tires") else 0.6) * (3.0 if off_road else 1.0)
		parts["tires"] = maxf(parts["tires"] - dist / 1000.0 * tire_wear, 0.0)
		parts["engine"] = maxf(parts["engine"] - dist / 1000.0 * 0.35, 0.0)
		if Engine.get_physics_frames() % 60 == 0:
			_apply_visuals()
	if headlights:
		battery = maxf(battery - delta * (0.02 if engine_on else 0.06), 0.0)
	if interior_lights:
		battery = maxf(battery - delta * 0.03, 0.0)
	if upgrades.has("solar") and not missing.has("battery") and Game.time_of_day > 7.0 and Game.time_of_day < 18.0 and Game.weather != "rain":
		battery = minf(battery + delta * 0.08, 100.0)
	if battery <= 0.0:
		headlights = false
		interior_lights = false
		_update_lights()
	# crash damage
	var dv := (_prev_vel - linear_velocity).length()
	if dv > 7.0 and driver != 0:
		var dmg := (dv - 7.0) * 2.5 * Game.diff("damage") * (0.4 if upgrades.has("bullbar") else 1.0)
		parts["body"] = maxf(parts["body"] - dmg, 0.0)
		parts["engine"] = maxf(parts["engine"] - dmg * 0.5, 0.0)
		Audio.play_at("hit", global_position, 6.0, 0.6)
		Game.notify("Crash! Body -%d%%" % int(dmg))
		if Game.player and Game.player.driving:
			Game.player.hurt(dmg * 0.5, "crash")
	_prev_vel = linear_velocity
	# engine sound
	if _engine_audio.playing:
		var rpm := 0.75 + clampf(absf(fwd_speed) / top, 0.0, 1.0) * 1.1 + throttle * 0.25
		_engine_audio.pitch_scale = lerpf(_engine_audio.pitch_scale, rpm, delta * 4.0)
		_engine_audio.volume_db = -8.0 + throttle * 4.0
	_tail_mat.emission_energy_multiplier = 2.5 if brk > 20.0 and driver != 0 else (0.8 if headlights else 0.1)
	if is_driven_locally():
		Net.send_rv(global_transform, linear_velocity)

func remote_transform(xf: Transform3D) -> void:
	_remote_target = xf
	_remote_has = true

func _process(delta: float) -> void:
	if cam_tp.current:
		var target := global_position + Vector3(0, 2.4, 0)
		var behind := -global_transform.basis.z
		behind.y = 0
		behind = behind.normalized().rotated(Vector3.UP, tp_yaw)
		var want := target + behind * 11.0 + Vector3(0, 3.0, 0)
		var gh: float = Game.world.gen.height(want.x, want.z) + 1.0
		want.y = maxf(want.y, gh)
		cam_tp.global_position = cam_tp.global_position.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
		cam_tp.look_at(target, Vector3.UP)

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
		cam_tp.global_position = global_position + global_transform.basis.z * -10.0 + Vector3(0, 4, 0)
		cam_tp.make_current()
	else:
		cam_fp.make_current()
	cam_fp.fov = Game.settings["fov"]
	cam_tp.fov = Game.settings["fov"]

func toggle_headlights() -> void:
	if battery <= 0.0:
		Game.notify("Battery is flat")
		return
	headlights = not headlights
	_update_lights()
	Audio.play("click", -4.0)

func _update_lights() -> void:
	for s in _head_spots:
		s.visible = headlights
	for m in _head_mats:
		m.emission_energy_multiplier = 3.0 if headlights else 0.0
	_interior_light.visible = interior_lights

func is_inside(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < W * 0.5 and l.z > REAR_Z and l.z < FRONT_Z and l.y > FLOOR_Y - 0.5 and l.y < ROOF_Y

func door_open_anim() -> void:
	var tw := create_tween()
	tw.tween_property(_door_panel, "rotation:y", 1.6, 0.25)
	tw.tween_interval(0.5)
	tw.tween_property(_door_panel, "rotation:y", 0.0, 0.3)
	Audio.play_at("door", global_position + global_transform.basis.x * 1.2)

# ------------------------------------------------------------------ interaction
func prompt_for(action: String) -> String:
	if action.begins_with("wheel"):
		return Mounts.prompt(self, action)
	match action:
		"drive": return "[E] Drive" if driver == 0 else "Someone is driving"
		"passenger": return "[E] Sit in passenger seat"
		"stove": return "[E] Cook on stove"
		"sink": return "[E] Use sink  (tank %d/%d L)" % [int(water), int(water_capacity())]
		"coffee": return "[E] Brew coffee (beans + 1 L water)"
		"fridge", "cabinet", "overhead":
			var nm: String = {"fridge": "fridge", "cabinet": "cupboard", "overhead": "overhead cupboard"}[action]
			return "[E] %s %s" % ["Close" if _doors[action]["open"] else "Open", nm]
		"battery":
			return Mounts.prompt(self, action)
		"bed": return "[E] Sleep in bed"
		"toilet": return "[E] Use toilet"
		"lights": return "[E] Interior lights %s" % ("off" if interior_lights else "on")
		"door":
			var p := Game.player
			if p and is_inside(p.global_position):
				return "[E] Exit RV"
			return "[E] Enter RV"
		"hood":
			var mp := Mounts.prompt(self, "hood")
			return mp if mp != "" else "[E] Open hood — condition, upgrades & paint"
		"fuel": return "[E] Refuel (%d/%d L)" % [int(fuel), int(fuel_capacity())]
	return ""

func do_action(action: String, player: Node) -> void:
	if action == "battery" or action.begins_with("wheel") or action == "hood":
		if Mounts.act(self, action):
			return
	match action:
		"drive":
			if driver == 0:
				player.enter_vehicle(self, true)
		"passenger":
			player.enter_vehicle(self, false)
		"stove":
			Game.world.hud.open_cooking(null)
		"sink":
			Game.world.hud.open_sink(self)
		"coffee":
			if Game.count("coffee_beans") <= 0:
				Game.notify("You need coffee beans")
			elif water < 1.0:
				Game.notify("The water tank is empty")
			else:
				Game.remove_item("coffee_beans", 1)
				water -= 1.0
				Game.add_item("coffee", 1)
				Audio.play("pickup")
		"fridge", "cabinet", "overhead":
			_toggle_door(action)
		"bed":
			Game.world.sleep(player.global_position)
		"toilet":
			Game.notify("Much better.")
			Game.stats["water"] = maxf(Game.stats["water"] - 5.0, 0.0)
			Audio.play_at("splash", global_position, -6.0)
		"lights":
			interior_lights = not interior_lights and battery > 0.0
			_update_lights()
			Audio.play("click")
		"door":
			door_open_anim()
			if is_inside(player.global_position):
				player.teleport(to_global(Vector3(W * 0.5 + 1.0, 0.4, (DOOR_Z0 + DOOR_Z1) * 0.5)))
			else:
				player.teleport(to_global(Vector3(0.05, FLOOR_Y + 0.1, (DOOR_Z0 + DOOR_Z1) * 0.5 - 0.1)))
		"hood":
			Game.world.hud.open_rv_menu(self)
		"fuel":
			if Game.count("fuel_can") <= 0:
				Game.notify("You need a fuel can")
			elif fuel > fuel_capacity() - 1.0:
				Game.notify("The tank is full")
			else:
				Game.remove_item("fuel_can", 1)
				fuel = minf(fuel + 10.0, fuel_capacity())
				Audio.play_at("splash", global_position, -8.0, 0.7)
				Game.notify("Refueled: %d L" % int(fuel))

func repair(part: String) -> void:
	var spec: Dictionary = Data.RV_PARTS[part]
	if spec["needs_toolkit"] and Game.count("toolkit") <= 0:
		Game.notify("You need a toolkit")
		return
	if not Game.pay(spec["repair"]):
		Game.notify("Missing: %s" % Data.cost_text(spec["repair"]))
		return
	parts[part] = minf(parts[part] + float(spec["amount"]), 100.0)
	if part == "battery":
		battery = 100.0
	Audio.play("hammer")
	_apply_visuals()
	Game.notify("%s repaired to %d%%" % [spec["name"], int(parts[part])])

func install(upgrade: String) -> void:
	if upgrades.has(upgrade):
		return
	var spec: Dictionary = Data.RV_UPGRADES[upgrade]
	if Game.count("toolkit") <= 0:
		Game.notify("You need a toolkit")
		return
	if not Game.pay(spec["cost"]):
		Game.notify("Missing: %s" % Data.cost_text(spec["cost"]))
		return
	upgrades[upgrade] = true
	Audio.play("hammer")
	_apply_visuals()
	Game.notify("Installed: %s" % spec["name"])

## Bounding test used for items and furniture riding inside or on the roof.
func contains_point(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < W * 0.5 + 0.1 and l.z > REAR_Z - 0.2 and l.z < FRONT_Z + 1.4 and l.y > FLOOR_Y - 0.3 and l.y < ROOF_Y + 1.6

func attach_structure(world_rec: Dictionary) -> void:
	var rec := world_rec.duplicate(true)
	var lp := to_local(Game.v3(rec["pos"]))
	rec["pos"] = Game.arr(lp)
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
	s.save_cb = func(d: Dictionary) -> void: rec["data"] = d
	return s

func detach_structure(s: Node) -> void:
	var rec: Dictionary = s.get_meta("rv_rec")
	attached.erase(rec)
	s.queue_free()

func _cargo_records() -> Array:
	var out := []
	for ch in get_node("Cargo").get_children():
		if ch.is_in_group("world_item") and is_instance_valid(ch):
			out.append({"id": ch.id, "n": ch.amount, "pos": Game.arr(ch.position), "rot": Game.arr(ch.rotation)})
	return out

func _spawn_cargo(r: Dictionary) -> void:
	var it := RigidBody3D.new()
	it.set_script(load("res://scripts/world_item.gd"))
	it.setup(str(r["id"]), int(r["n"]))
	it._attached = true
	it.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	it.freeze = true
	it.collision_mask = 0
	get_node("Cargo").add_child(it)
	it.position = Game.v3(r["pos"])
	it.rotation = Game.v3(r["rot"])

var trailer: Node = null

func display_name() -> String:
	return "Motorhome"

func seat_global(as_driver: bool) -> Vector3:
	return to_global(Vector3(-0.55 if as_driver else 0.55, 1.0, 2.3))

func exit_global() -> Vector3:
	return to_global(Vector3(0.05, FLOOR_Y + 0.1, FRONT_Z - 1.9))

func set_seat(as_driver: bool) -> void:
	cam_fp.position.x = -0.55 if as_driver else 0.55

func hitch_global() -> Vector3:
	return to_global(Vector3(0, 0.75, REAR_Z - 0.55))

func paint_palette() -> Array:
	return Data.RV_PAINTS

func upgrade_list() -> Array:
	return Data.RV_UPGRADES.keys()

func set_paint(i: int) -> void:
	paint = i
	_apply_visuals()

func heater_on() -> bool:
	return upgrades.has("heater") and (engine_on or battery > 10.0)
