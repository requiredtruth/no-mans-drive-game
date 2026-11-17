extends VehicleBody3D
## The player's van. A new game starts with a stripped, rusty shell: no engine, battery, wheels,
## seats, steering wheel, door or furniture. Every part is a physical module: carry it to its
## spot on the van and press [E] to fit it, or [G] with empty hands to take it out again.
## While you hold a module, the empty spot it fits shows as a green outline.

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
const CAB_Z := FRONT_Z - 0.55 # where the full-height box ends and the sloped windshield begins
const DOOR_Z0 := 0.5
const DOOR_Z1 := 1.55
## Slots that become part of the van for good once fitted.
const FIXED := ["floor", "walls"]
## Furniture that goes anywhere you like on the van floor: hold it inside, aim at the floor,
## [R] turns it, [G] fits it. Each entry: the footprint centre on the floor in the default layout
## (the pivot everything is moved around), its footprint (x, z), and the wall its back sits
## against by default (-1 left, 1 right, 0 none) so it turns its back to the nearest wall.
const FREE := {
	"kitchen": [Vector3(-W * 0.5 + 0.42, FLOOR_Y, 0.65), Vector2(0.66, 1.74), -1],
	"fridge": [Vector3(-W * 0.5 + 0.44, FLOOR_Y, -0.67), Vector2(0.66, 0.7), -1],
	"cupboard": [Vector3(-W * 0.5 + 0.38, FLOOR_Y, -1.45), Vector2(0.6, 0.82), -1],
	"dinette": [Vector3(W * 0.5 - 0.47, FLOOR_Y, -0.5), Vector2(0.78, 1.96), 1],
	"toilet": [Vector3(0.68, FLOOR_Y, -2.21), Vector2(1.04, 0.94), 1],
	"bed": [Vector3(-0.27, FLOOR_Y, -2.75), Vector2(1.86, 1.22), 0],
	"heater": [Vector3(W * 0.5 - 0.25, FLOOR_Y, 1.85), Vector2(0.28, 0.42), 1],
}
## Modules that sit on another one and move with it.
const FOLLOW := {"stove": "kitchen", "sink": "kitchen", "coffee": "kitchen", "mattress": "bed"}

var fuel := 18.0
var water := 6.0
var battery := 45.0
var parts := {"engine": 38.0, "tires": 52.0, "battery": 48.0, "body": 55.0}
var upgrades := {}
var modules := {} # fitted module slots (see Data.VAN_SLOTS)
var module_xf := {} # free furniture slot -> [x, z, yaw] where it stands on the van floor
var wheel_kind := {} # "wheel0".."wheel3" -> "offroad_tire" when an off-road tire is fitted
var paint := 0
var fridge := {}
var cabinet := {}
var missing := {} # parts pulled out: "battery", "wheel0".."wheel3"
var pots := [{}, {}]
var interior_lights := false
var headlights := false
var engine_on := false
var stove_on := false
var radio_on := false
var radio_station := 0
var driver := 0 # peer id of the driver (0 = nobody)
var odometer := 0.0
var attached: Array = [] # furniture placed inside / on top of the van: {type, pos(local), rot(local), data}

var wheels: Array[VehicleWheel3D] = []
var cam_fp: Camera3D
var cam_tp: Camera3D
var use_tp := true
var fp_yaw := 0.0
var fp_pitch := 0.0
var tp_yaw := 0.0
var _paint_mats: Array[StandardMaterial3D] = []
var _body_mat: StandardMaterial3D
var _head_spots: Array[SpotLight3D] = []
var _head_mats: Array[StandardMaterial3D] = []
var _tail_mat: StandardMaterial3D
var _interior_light: OmniLight3D
var _engine_audio: AudioStreamPlayer3D
var _radio_audio: AudioStreamPlayer3D
var _door_panel: Node3D
var _door_home := Vector3.ZERO
var _door_shape: CollisionShape3D
var _door_tween: Tween
var door_open := false
var _prev_vel := Vector3.ZERO
var _throttle := 0.0
var _remote_target: Transform3D
var _remote_has := false
var _solar: Node3D
var _bullbar: Node3D
var _steer := 0.0
var _flames: Array[MeshInstance3D] = []

# module bookkeeping
var _grp := ""
var _mod_vis := {} # slot -> Node3D holding its visuals
var _mod_shapes := {} # slot -> Array of CollisionShape3D
var _mod_parts := {} # slot -> Array of interaction hotspots
var _mod_extra := {} # slot -> Array of other nodes to show/hide (pots)
var _mounts := {} # slot -> mount hotspot
var _ghosts := {} # slot -> translucent preview
var _ghost_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
var _base_xf := {} # node -> its transform in the default layout

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
	_build_mounts()
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
	Game.hotbar_changed.connect(_update_ghosts)

# ------------------------------------------------------------------ build helpers
func _shape(pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	cs.rotation = rot
	add_child(cs)
	if _grp != "":
		_mod_shapes[_grp].append(cs)
	return cs

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
	if _grp != "":
		b.set_meta("slot", _grp)
		_mod_parts[_grp].append(b)
	return b

## Start building the visuals of one module slot under parent.
func _begin(slot: String, parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.name = "Mod_" + slot
	parent.add_child(n)
	_grp = slot
	_mod_vis[slot] = n
	_mod_shapes[slot] = []
	_mod_parts[slot] = []
	_mod_extra[slot] = []
	return n

func _end() -> void:
	_grp = ""

func _mount(slot: String, pos: Vector3, size: Vector3) -> void:
	var b := _part(pos, size, "mount:" + slot)
	_mounts[slot] = b

# ------------------------------------------------------------------ exterior
func _build_collision() -> void:
	var L := FRONT_Z - REAR_Z
	var mid := (FRONT_Z + REAR_Z) * 0.5
	var h := ROOF_Y - FLOOR_Y
	_shape(Vector3(0, FLOOR_Y - 0.15, mid), Vector3(W, 0.3, L))
	_shape(Vector3(0, ROOF_Y + 0.08, (CAB_Z + REAR_Z) * 0.5), Vector3(W, 0.16, CAB_Z - REAR_Z))
	_shape(Vector3(-W * 0.5, FLOOR_Y + h * 0.5, mid), Vector3(0.12, h, L))
	var rear_len := DOOR_Z0 - REAR_Z
	_shape(Vector3(W * 0.5, FLOOR_Y + h * 0.5, REAR_Z + rear_len * 0.5), Vector3(0.12, h, rear_len))
	var front_len := FRONT_Z - DOOR_Z1
	_shape(Vector3(W * 0.5, FLOOR_Y + h * 0.5, DOOR_Z1 + front_len * 0.5), Vector3(0.12, h, front_len))
	_shape(Vector3(W * 0.5, FLOOR_Y + DOOR_H + (h - DOOR_H) * 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.12, h - DOOR_H, DOOR_Z1 - DOOR_Z0))
	_shape(Vector3(0, FLOOR_Y + h * 0.5, REAR_Z), Vector3(W, h, 0.12))
	_shape(Vector3(0, 1.45, FRONT_Z + 0.45), Vector3(W, 0.9, 0.12)) # firewall below the windshield
	_shape(Vector3(0, 2.33, FRONT_Z + 0.1), Vector3(W, 1.4, 0.1), Vector3(-0.61, 0, 0)) # windshield
	_shape(Vector3(0, 1.15, FRONT_Z + 0.85), Vector3(W - 0.1, 0.9, 0.9)) # hood/engine bay

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
		var knobby := MeshInstance3D.new()
		knobby.mesh = Items.mesh("offroad_tire")
		knobby.position.y = -0.12
		knobby.visible = false
		holder.add_child(knobby)
		w.set_meta("tire_mesh", tire)
		w.set_meta("knobby_mesh", knobby)
		w.set_meta("hub_mesh", Mounts.hub(holder))
		_part(Vector3(spec[0] + signf(spec[0]) * 0.12, 0.62, spec[1]), Vector3(0.4, 1.0, 1.1), "wheel%d" % wheels.size())
		wheels.append(w)

func _paint_mat() -> StandardMaterial3D:
	var m := Lib.mat("rv_paint", Color.WHITE, 0.35, false, 0.55).duplicate()
	_paint_mats.append(m)
	return m

## Every opening in the van's sides is a real hole: you see in and out through the glass and walk
## in through the side doorway. Rectangles are [z0, z1, y0, y1]; the interior walls use the same
## ones. The cab windows follow the A-pillar.
const WIN_L := [[0.0, 1.6, 2.05, 2.6], [-2.6, -1.6, 1.85, 2.55], [2.25, 2.75, 1.85, 2.55]]
const WIN_R := [[-1.1, 0.1, 1.85, 2.55], [DOOR_Z0, DOOR_Z1, 0.0, FLOOR_Y + DOOR_H], [-3.1, -2.2, 2.2, 2.6], [2.25, 2.75, 1.85, 2.55]]
const CAB_WIN := [Vector2(2.92, 1.9), Vector2(3.6, 1.9), Vector2(3.6, 1.98), Vector2(3.22, 2.56), Vector2(2.92, 2.56)]
const SKIN := W * 0.5 + 0.03 # outer face of the side panels
const REVEAL := W * 0.5 - 0.14 # inner face of the fitted wall panels

static func _rect(r: Array) -> PackedVector2Array:
	return PackedVector2Array([Vector2(r[0], r[2]), Vector2(r[1], r[2]), Vector2(r[1], r[3]), Vector2(r[0], r[3])])

## Openings through one side of the body (side -1 = driver/left, +1 = door side).
func _side_holes(side: float) -> Array:
	var out: Array = []
	for r in (WIN_L if side < 0.0 else WIN_R):
		out.append(_rect([r[0], r[1], maxf(r[2], FLOOR_Y - 0.02), r[3]]))
	out.append(PackedVector2Array(CAB_WIN))
	return out

## A thin strip from a to b on the body side (shut lines, rails, trim).
static func _strip(st: SurfaceTool, a: Vector2, b: Vector2, wdt: float, x: float, side: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * wdt * 0.5
	Shapes.side_panel(st, PackedVector2Array([a - n, b - n, b + n, a + n]), x, side)

## A box lying along the edge p->q of an opening, spanning the wall thickness x_a..x_b.
static func _edge_box(parent: Node3D, p: Vector2, q: Vector2, x_a: float, x_b: float, thick: float, m: Material) -> MeshInstance3D:
	var c := (p + q) * 0.5
	var d := q - p
	return Lib.box(parent, Vector3((x_a + x_b) * 0.5, c.y, c.x), Vector3(absf(x_b - x_a), thick, d.length() + thick), m, false, Vector3(atan2(-d.y, d.x), 0, 0), 0.008)

## A high-roof panel van modelled on the real thing: a sloped hood and raked windshield, cab doors,
## a sliding side door you walk through, barn doors at the back, black plastic bumpers, sills and
## arch flares, a chassis, axle and exhaust underneath, and glass you can see through.
func _build_exterior() -> void:
	_body_mat = Lib.mat("rv_paint", Color.WHITE, 0.35, false, 0.5).duplicate()
	_body_mat.clearcoat_enabled = true
	_body_mat.clearcoat = 0.5
	_body_mat.clearcoat_roughness = 0.3
	var paint_m := _body_mat
	var plastic := Lib.mat("rubber", Color(0.36, 0.36, 0.37), 2.5, false, 0.8)
	var dark := Lib.color_mat(Color(0.07, 0.07, 0.08), 0.6)
	var chrome := Lib.color_mat(Color(0.82, 0.82, 0.84), 0.15, 0.95)
	var steel := Lib.color_mat(Color(0.2, 0.2, 0.21), 0.55, 0.6)
	var rubber := Lib.color_mat(Color(0.05, 0.05, 0.05), 0.85)
	var amber := Lib.color_mat(Color(1.0, 0.55, 0.1, 0.85), 0.1, 0.0, Color(1.0, 0.45, 0.0), 0.25)
	var clear_lens := Lib.color_mat(Color(0.95, 0.95, 0.95, 0.7), 0.05)
	var vis := Node3D.new()
	vis.name = "Exterior"
	add_child(vis)
	var body := Shapes.st()
	var glass := Shapes.st()
	var trim := Shapes.st()
	var seam := Shapes.st()
	var lining := Shapes.st()
	var o := Shapes.arched_bottom(REAR_Z - 0.05, FRONT_Z + 1.28, 0.62, [[-2.35, 0.62], [2.55, 0.62]], 14)
	var ws_edge := o.size() + 4
	for pt in [Vector2(FRONT_Z + 1.3, 0.9), Vector2(FRONT_Z + 1.31, 1.38), Vector2(FRONT_Z + 1.23, 1.57), Vector2(FRONT_Z + 1.02, 1.66),
			Vector2(FRONT_Z + 0.5, 1.76), Vector2(FRONT_Z - 0.3, 2.9), Vector2(FRONT_Z - 0.46, ROOF_Y + 0.08), Vector2(FRONT_Z - 0.72, ROOF_Y + 0.18),
			Vector2(FRONT_Z - 1.1, ROOF_Y + 0.22), Vector2(REAR_Z + 0.3, ROOF_Y + 0.22), Vector2(REAR_Z + 0.04, ROOF_Y + 0.14), Vector2(REAR_Z - 0.05, ROOF_Y - 0.05)]:
		o.append(pt)
	var bevel := 0.14
	Shapes.extrude(body, glass, o, SKIN * 2.0, bevel, [ws_edge], 0.0, false)
	var flat := Shapes.inset_outline(o, bevel)
	for side in [-1.0, 1.0]:
		var holes := _side_holes(side)
		Shapes.side_with_holes(body, flat, holes, side * SKIN, side)
		Shapes.side_with_holes(lining, flat, holes, side * (SKIN - 0.025), -side)
		for hp in holes:
			var door_hole: bool = side > 0.0 and absf(hp[0].x - DOOR_Z0) < 0.01
			var n: int = hp.size()
			for i in range(n):
				var p: Vector2 = hp[i]
				var q: Vector2 = hp[(i + 1) % n]
				if door_hole:
					# painted jambs with a rubber seal, a steel threshold plate on the sill
					var is_sill := absf(p.y - q.y) < 0.01 and p.y < FLOOR_Y + 0.1
					_edge_box(vis, p, q, side * SKIN, side * (W * 0.5 - 0.1), 0.03, steel if is_sill else paint_m)
					if not is_sill:
						_edge_box(vis, p, q, side * (SKIN - 0.035), side * (SKIN - 0.06), 0.045, rubber)
				else:
					_edge_box(vis, p, q, side * (SKIN + 0.008), side * REVEAL, 0.035, rubber)
			if not door_hole:
				Shapes.side_panel(glass, hp, side * (SKIN - 0.015), side)
		# lower black cladding along the sills, following the wheel arches
		for pc in Geometry2D.intersect_polygons(flat, _rect([REAR_Z - 1.0, FRONT_Z + 2.0, 0.0, 0.92])):
			Shapes.side_panel(trim, pc, side * (SKIN + 0.004), side)
		# wheel-arch flares
		for arch in [[-2.35, 0.62], [2.55, 0.62]]:
			var ring := PackedVector2Array()
			var segs := 16
			for k in range(segs + 1):
				var ang := PI * k / segs
				ring.append(Vector2(arch[0] + cos(ang) * 0.74, 0.62 + sin(ang) * 0.74))
			for k in range(segs + 1):
				var ang := PI - PI * k / segs
				ring.append(Vector2(arch[0] + cos(ang) * 0.615, 0.62 + sin(ang) * 0.615))
			Shapes.side_panel(trim, ring, side * (SKIN + 0.012), side)
		var sx: float = side * (SKIN + 0.003)
		# cab door shut lines, the fuel-flap and the sliding-door rail
		_strip(seam, Vector2(2.86, 1.2), Vector2(2.86, 2.64), 0.012, sx, side)
		_strip(seam, Vector2(2.86, 2.64), Vector2(3.2, 2.64), 0.012, sx, side)
		_strip(seam, Vector2(3.86, 1.08), Vector2(3.86, 1.66), 0.012, sx, side)
		_strip(seam, Vector2(2.86, 0.86), Vector2(2.86, 1.2), 0.012, sx, side)
		Lib.box(vis, Vector3(side * (SKIN + 0.02), 1.72, 3.0), Vector3(0.03, 0.05, 0.2), dark, false, Vector3.ZERO, 0.02)
		Lib.cyl(vis, Vector3(side * (SKIN + 0.02), 1.72, 3.14), 0.012, 0.012, 0.02, chrome, Vector3(0, 0, PI * 0.5), 10)
		# side marker lights
		Lib.box(vis, Vector3(side * (SKIN + 0.008), 0.98, FRONT_Z + 1.05), Vector3(0.02, 0.05, 0.12), amber)
		Lib.box(vis, Vector3(side * (SKIN + 0.008), 0.98, REAR_Z + 0.35), Vector3(0.02, 0.05, 0.12), amber)
		# roof gutter / drip rail
		Lib.box(vis, Vector3(side * (SKIN - 0.03), ROOF_Y + 0.17, (FRONT_Z - 0.9 + REAR_Z + 0.25) * 0.5), Vector3(0.05, 0.035, FRONT_Z - 0.9 - REAR_Z - 0.25), plastic)
		# roof-corner marker lights
		Lib.box(vis, Vector3(side * 0.95, ROOF_Y + 0.21, FRONT_Z - 0.95), Vector3(0.14, 0.04, 0.06), amber)
		Lib.box(vis, Vector3(side * 0.95, ROOF_Y + 0.13, REAR_Z - 0.0), Vector3(0.14, 0.05, 0.04), _tail_mat_get())
		# mud flaps
		for zf in [1.82, -3.05]:
			Lib.box(vis, Vector3(side * 1.02, 0.36, zf), Vector3(0.36, 0.42, 0.02), rubber)
		# mirror: arm, housing and glass
		Lib.box(vis, Vector3(side * (SKIN + 0.1), 2.0, FRONT_Z + 0.22), Vector3(0.22, 0.035, 0.04), dark, false, Vector3.ZERO, 0.012)
		Lib.box(vis, Vector3(side * (SKIN + 0.24), 2.08, FRONT_Z + 0.2), Vector3(0.09, 0.4, 0.2), dark, false, Vector3.ZERO, 0.035)
		Lib.box(vis, Vector3(side * (SKIN + 0.24), 2.1, FRONT_Z + 0.095), Vector3(0.075, 0.36, 0.01), Lib.color_mat(Color(0.75, 0.8, 0.85), 0.02, 1.0))
	# sliding-door rail on the door side, behind the doorway
	_strip(seam, Vector2(-1.25, 1.77), Vector2(DOOR_Z0, 1.77), 0.05, SKIN + 0.004, 1.0)
	Lib.box(vis, Vector3(SKIN + 0.012, 1.795, (DOOR_Z0 - 1.25) * 0.5), Vector3(0.02, 0.012, DOOR_Z0 + 1.25), plastic)
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = Shapes.commit([[body, paint_m], [glass, Lib.glass_mat()], [trim, plastic], [seam, dark], [lining, Lib.color_mat(Color(0.23, 0.23, 0.24), 0.75)]])
	vis.add_child(shell)
	# ---- front: bumper, grille, fog lights, plate, wipers
	var fz := FRONT_Z + 1.3
	Lib.box(vis, Vector3(0, 0.8, fz + 0.06), Vector3(SKIN * 2.0 + 0.06, 0.34, 0.24), plastic, false, Vector3.ZERO, 0.08)
	Lib.box(vis, Vector3(0, 0.74, fz + 0.18), Vector3(1.3, 0.12, 0.02), dark)
	for x in [-0.82, 0.82]:
		Lib.cyl(vis, Vector3(x, 0.76, fz + 0.17), 0.06, 0.06, 0.03, clear_lens, Vector3(PI * 0.5, 0, 0))
		Lib.cyl(vis, Vector3(x, 0.76, fz + 0.16), 0.075, 0.075, 0.02, dark, Vector3(PI * 0.5, 0, 0))
	Lib.box(vis, Vector3(0, 0.82, fz + 0.185), Vector3(0.52, 0.12, 0.01), Lib.color_mat(Color(0.92, 0.92, 0.9), 0.5))
	Lib.box(vis, Vector3(0, 0.82, fz + 0.18), Vector3(0.55, 0.14, 0.01), dark)
	var gz := FRONT_Z + 1.345
	Lib.box(vis, Vector3(0, 1.2, gz), Vector3(1.22, 0.4, 0.03), chrome, false, Vector3.ZERO, 0.03)
	Lib.box(vis, Vector3(0, 1.2, gz + 0.008), Vector3(1.12, 0.32, 0.03), dark)
	for k in range(4):
		Lib.box(vis, Vector3(0, 1.08 + k * 0.08, gz + 0.025), Vector3(1.1, 0.022, 0.015), Lib.color_mat(Color(0.18, 0.18, 0.19), 0.4, 0.5))
	Lib.cyl(vis, Vector3(0, 1.2, gz + 0.04), 0.075, 0.075, 0.02, chrome, Vector3(PI * 0.5, 0, 0), 20)
	Lib.cyl(vis, Vector3(0, 1.2, gz + 0.045), 0.055, 0.055, 0.02, dark, Vector3(PI * 0.5, 0, 0), 20)
	for x in [-0.88, 0.88]:
		Lib.box(vis, Vector3(x, 1.08, FRONT_Z + 1.315), Vector3(0.3, 0.06, 0.04), amber)
	for x in [-0.45, 0.4]:
		Lib.box(vis, Vector3(x, 1.84, FRONT_Z + 0.44), Vector3(0.72, 0.02, 0.025), dark, false, Vector3(-0.6, 0, 0.18 * signf(x)))
		Lib.box(vis, Vector3(x * 1.55, 1.79, FRONT_Z + 0.5), Vector3(0.05, 0.04, 0.06), dark)
	# ---- rear: barn doors, hinges, handle, lights, bumper with step, plate
	var rz := REAR_Z - 0.052
	Lib.box(vis, Vector3(0, 1.95, rz), Vector3(0.012, 2.5, 0.01), dark)
	for x in [-1.06, 1.06]:
		Lib.box(vis, Vector3(x, 1.95, rz), Vector3(0.012, 2.5, 0.01), dark)
		for y in [1.15, 2.1, 2.95]:
			Lib.box(vis, Vector3(x * 1.08, y, rz - 0.02), Vector3(0.1, 0.12, 0.04), steel, false, Vector3.ZERO, 0.015)
	Lib.box(vis, Vector3(0, 3.2, rz), Vector3(2.14, 0.012, 0.01), dark)
	Lib.box(vis, Vector3(0.14, 1.65, rz - 0.03), Vector3(0.18, 0.05, 0.04), dark, false, Vector3.ZERO, 0.02)
	Lib.box(vis, Vector3(0, ROOF_Y + 0.02, rz - 0.01), Vector3(0.32, 0.05, 0.03), _tail_mat_get())
	Lib.box(vis, Vector3(0, 0.74, REAR_Z - 0.16), Vector3(SKIN * 2.0 + 0.04, 0.24, 0.24), plastic, false, Vector3.ZERO, 0.06)
	Lib.box(vis, Vector3(0, 0.865, REAR_Z - 0.2), Vector3(0.8, 0.012, 0.18), Lib.mat("rubber", Color(0.25, 0.25, 0.25), 6.0, false, 0.9))
	Lib.box(vis, Vector3(0, 1.0, rz - 0.01), Vector3(0.52, 0.12, 0.01), Lib.color_mat(Color(0.92, 0.92, 0.9), 0.5))
	Lib.box(vis, Vector3(0, 1.0, rz - 0.005), Vector3(0.55, 0.14, 0.01), dark)
	# tall rear light clusters on the corners: brake / indicator / reverse / brake
	_tail_mat = _tail_mat_get()
	for x in [-1.12, 1.12]:
		Lib.box(vis, Vector3(x, 1.3, REAR_Z - 0.06), Vector3(0.18, 0.74, 0.04), dark, false, Vector3.ZERO, 0.02)
		Lib.box(vis, Vector3(x, 1.55, REAR_Z - 0.08), Vector3(0.15, 0.22, 0.02), _tail_mat)
		Lib.box(vis, Vector3(x, 1.35, REAR_Z - 0.08), Vector3(0.15, 0.15, 0.02), amber)
		Lib.box(vis, Vector3(x, 1.2, REAR_Z - 0.08), Vector3(0.15, 0.12, 0.02), clear_lens)
		Lib.box(vis, Vector3(x, 1.05, REAR_Z - 0.08), Vector3(0.15, 0.15, 0.02), _tail_mat)
	# ---- roof: fan vent and antenna; rear ladder
	Lib.box(vis, Vector3(0, ROOF_Y + 0.26, 1.2), Vector3(0.6, 0.08, 0.6), dark, false, Vector3.ZERO, 0.03)
	Lib.box(vis, Vector3(0, ROOF_Y + 0.33, 1.2), Vector3(0.5, 0.08, 0.5), Lib.color_mat(Color(0.85, 0.87, 0.9, 0.6), 0.1), false, Vector3(0.12, 0, 0), 0.04)
	Lib.cyl(vis, Vector3(0.35, ROOF_Y + 0.45, FRONT_Z - 1.0), 0.004, 0.008, 0.5, dark, Vector3(-0.3, 0, 0), 6)
	for x in [0.55, 0.95]:
		Lib.box(vis, Vector3(x, 2.1, REAR_Z - 0.18), Vector3(0.04, 2.0, 0.04), steel)
	for k in range(6):
		Lib.box(vis, Vector3(0.75, 1.3 + k * 0.32, REAR_Z - 0.18), Vector3(0.4, 0.03, 0.03), steel)
	# ---- underneath: chassis rails, crossmembers, rear axle and diff, exhaust, spare wheel
	for x in [-0.52, 0.52]:
		Lib.box(vis, Vector3(x, 0.5, 0.35), Vector3(0.1, 0.18, 7.4), steel)
	for z in [-1.75, 0.45, 2.0]:
		Lib.box(vis, Vector3(0, 0.5, z), Vector3(1.04, 0.1, 0.1), steel)
	Lib.cyl(vis, Vector3(0, 0.62, -2.35), 0.06, 0.06, 1.95, steel, Vector3(0, 0, PI * 0.5), 10)
	Lib.sphere(vis, Vector3(0.1, 0.6, -2.35), 0.17, steel, Vector3(1.0, 0.9, 1.1))
	Lib.cyl(vis, Vector3(0.1, 0.6, -1.4), 0.04, 0.04, 1.9, steel, Vector3(PI * 0.5, 0, 0), 8)
	Lib.cyl(vis, Vector3(0.78, 0.42, -0.6), 0.04, 0.04, 5.4, Lib.color_mat(Color(0.35, 0.3, 0.27), 0.7, 0.5), Vector3(PI * 0.5, 0, 0), 10)
	Lib.cyl(vis, Vector3(0.78, 0.42, -0.4), 0.11, 0.11, 0.6, Lib.color_mat(Color(0.4, 0.38, 0.36), 0.5, 0.6), Vector3(PI * 0.5, 0, 0), 14)
	Lib.cyl(vis, Vector3(0.78, 0.42, -3.38), 0.045, 0.045, 0.12, chrome, Vector3(PI * 0.5, 0, 0), 10)
	var spare := MeshInstance3D.new()
	spare.mesh = Items.mesh("tire")
	spare.scale = Vector3.ONE * 1.1
	spare.position = Vector3(0, 0.42, -2.95)
	vis.add_child(spare)
	# ---- headlights (modules) in proper housings
	for i in range(2):
		var x: float = [-0.85, 0.85][i]
		Lib.box(vis, Vector3(x, 1.25, FRONT_Z + 1.26), Vector3(0.44, 0.27, 0.06), dark, false, Vector3.ZERO, 0.03)
		var hv := _begin("headlight_l" if i == 0 else "headlight_r", vis)
		var hm := Lib.color_mat(Color(0.95, 0.95, 0.9), 0.1, 0.0, Color(1.0, 0.95, 0.8), 0.0).duplicate()
		_head_mats.append(hm)
		Lib.box(hv, Vector3(x, 1.26, FRONT_Z + 1.3), Vector3(0.18, 0.16, 0.03), hm, false, Vector3.ZERO, 0.03)
		Lib.box(hv, Vector3(x, 1.25, FRONT_Z + 1.295), Vector3(0.4, 0.23, 0.04), Lib.color_mat(Color(0.75, 0.77, 0.8), 0.15, 0.9), false, Vector3.ZERO, 0.03)
		Lib.box(hv, Vector3(x, 1.25, FRONT_Z + 1.315), Vector3(0.41, 0.24, 0.02), clear_lens, false, Vector3.ZERO, 0.03)
		var sp := SpotLight3D.new()
		sp.position = Vector3(x, 1.25, FRONT_Z + 1.33)
		sp.rotation.x = deg_to_rad(-5)
		sp.rotation.y = PI
		sp.spot_range = 45.0
		sp.spot_angle = 32.0
		sp.light_energy = 6.0
		sp.light_color = Color(1.0, 0.95, 0.85)
		sp.shadow_enabled = false
		sp.visible = false
		hv.add_child(sp)
		_head_spots.append(sp)
		_end()
	# ---- sliding side door (module). With no door the doorway is simply open: walk in.
	var dw := DOOR_Z1 - DOOR_Z0
	var dv := _begin("door", vis)
	_door_home = Vector3(SKIN, FLOOR_Y - 0.02, DOOR_Z0)
	_door_panel = Node3D.new()
	_door_panel.name = "SlidingDoor"
	_door_panel.position = _door_home
	dv.add_child(_door_panel)
	var d_out := Shapes.st()
	var d_in := Shapes.st()
	var d_glass := Shapes.st()
	var dh := DOOR_H + 0.02
	var d_rect := _rect([0.0, dw, 0.0, dh])
	var d_win := _rect([0.1, dw - 0.1, 0.9, 1.56])
	Shapes.side_with_holes(d_out, d_rect, [d_win], 0.0, 1.0)
	Shapes.side_with_holes(d_in, d_rect, [d_win], -0.06, -1.0)
	Shapes.side_panel(d_glass, d_win, -0.015, 1.0)
	var dm := MeshInstance3D.new()
	dm.mesh = Shapes.commit([[d_out, paint_m], [d_in, Lib.color_mat(Color(0.3, 0.3, 0.31), 0.7)], [d_glass, Lib.glass_mat()]])
	_door_panel.add_child(dm)
	for e in [[Vector2(0, 0), Vector2(dw, 0)], [Vector2(dw, 0), Vector2(dw, dh)], [Vector2(dw, dh), Vector2(0, dh)], [Vector2(0, dh), Vector2(0, 0)]]:
		_edge_box(_door_panel, e[0], e[1], 0.0, -0.06, 0.02, paint_m)
	for e in [[Vector2(0.1, 0.9), Vector2(dw - 0.1, 0.9)], [Vector2(dw - 0.1, 0.9), Vector2(dw - 0.1, 1.56)], [Vector2(dw - 0.1, 1.56), Vector2(0.1, 1.56)], [Vector2(0.1, 1.56), Vector2(0.1, 0.9)]]:
		_edge_box(_door_panel, e[0], e[1], 0.008, -0.068, 0.03, rubber)
	Lib.box(_door_panel, Vector3(0.02, 1.0, dw - 0.14), Vector3(0.03, 0.05, 0.22), dark, false, Vector3.ZERO, 0.02)
	Lib.box(_door_panel, Vector3(-0.08, 1.0, dw - 0.14), Vector3(0.03, 0.05, 0.16), dark, false, Vector3.ZERO, 0.02)
	Lib.box(_door_panel, Vector3(-0.065, 0.45, dw * 0.5), Vector3(0.012, 0.7, dw - 0.2), Lib.color_mat(Color(0.22, 0.22, 0.23), 0.8))
	var dp := _part(Vector3.ZERO, Vector3(0.12, dh, dw), "door")
	remove_child(dp)
	_door_panel.add_child(dp)
	dp.position = Vector3(-0.03, dh * 0.5, dw * 0.5)
	_door_shape = _shape(Vector3(W * 0.5, FLOOR_Y + DOOR_H * 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.1, DOOR_H, dw))
	# inside grab handle on the pillar: open and close the door from inside
	_part(Vector3(W * 0.5 - 0.12, FLOOR_Y + 1.25, DOOR_Z1 + 0.07), Vector3(0.14, 0.5, 0.12), "door")
	_end()
	Lib.cyl(vis, Vector3(W * 0.5 - 0.12, FLOOR_Y + 1.25, DOOR_Z1 + 0.07), 0.016, 0.016, 0.42, dark, Vector3.ZERO, 8)
	for dy in [-0.21, 0.21]:
		Lib.box(vis, Vector3(W * 0.5 - 0.09, FLOOR_Y + 1.25 + dy, DOOR_Z1 + 0.07), Vector3(0.07, 0.03, 0.03), dark)
	_build_steps(vis, steel)
	# ---- solar panel, bull bar, water tank, long-range tank (modules)
	_solar = _begin("solar", vis)
	var sm := MeshInstance3D.new()
	sm.mesh = Items.mesh("solar_panel")
	sm.scale = Vector3(1.6, 1.0, 2.4)
	sm.position = Vector3(0, ROOF_Y + 0.26, -1.6)
	sm.rotation.y = PI * 0.5
	_solar.add_child(sm)
	for x in [-0.45, 0.45]:
		Lib.box(_solar, Vector3(x, ROOF_Y + 0.25, -1.6), Vector3(0.05, 0.06, 1.7), chrome)
	_end()
	_bullbar = _begin("bullbar", vis)
	var bm2 := MeshInstance3D.new()
	bm2.mesh = Items.mesh("bull_bar")
	bm2.scale = Vector3(2.0, 1.1, 1.0)
	bm2.position = Vector3(0, 0.62, FRONT_Z + 1.55)
	_bullbar.add_child(bm2)
	_end()
	var wt := _begin("water_tank", vis)
	var wtm := MeshInstance3D.new()
	wtm.mesh = Items.mesh("water_tank")
	wtm.position = Vector3(-0.35, 0.38, -1.2)
	wtm.rotation.y = PI * 0.5
	wt.add_child(wtm)
	_end()
	var bt := _begin("big_tank", vis)
	var btm := MeshInstance3D.new()
	btm.mesh = Items.mesh("fuel_tank_xl")
	btm.position = Vector3(0.35, 0.42, -0.2)
	btm.rotation.y = PI * 0.5
	bt.add_child(btm)
	_end()
	# battery box on the driver side, just behind the front wheel
	var tray := Vector3(-W * 0.5 - 0.22, 0.78, 1.35)
	Lib.box(vis, tray + Vector3(0, -0.04, 0), Vector3(0.42, 0.05, 0.56), steel)
	Lib.box(vis, tray + Vector3(0.2, 0.12, 0), Vector3(0.03, 0.3, 0.56), steel)
	for dz in [-0.26, 0.26]:
		Lib.box(vis, tray + Vector3(0, 0.03, dz), Vector3(0.42, 0.1, 0.03), steel)
	_battery_vis = Node3D.new()
	_battery_vis.position = tray + Vector3(-0.02, -0.015, 0)
	_battery_vis.rotation.y = PI * 0.5
	vis.add_child(_battery_vis)
	var bm := MeshInstance3D.new()
	bm.mesh = Items.mesh("car_battery")
	bm.scale = Vector3.ONE * 1.6
	_battery_vis.add_child(bm)
	_part(tray + Vector3(-0.02, 0.15, 0), Vector3(0.5, 0.42, 0.62), "battery")
	# fuel filler flap just ahead of the rear wheel
	Lib.box(vis, Vector3(-SKIN - 0.006, 1.12, -1.45), Vector3(0.02, 0.2, 0.2), paint_m, false, Vector3.ZERO, 0.03)
	_strip(seam, Vector2(-1.56, 1.01), Vector2(-1.34, 1.01), 0.01, -SKIN - 0.004, -1.0)
	_part(Vector3(-W * 0.5 - 0.1, 1.12, -1.45), Vector3(0.25, 0.4, 0.4), "fuel")
	_part(Vector3(0, 1.68, FRONT_Z + 0.85), Vector3(W, 0.3, 0.9), "hood")

func _tail_mat_get() -> StandardMaterial3D:
	if _tail_mat == null:
		_tail_mat = Lib.color_mat(Color(0.55, 0.04, 0.04), 0.2, 0.0, Color(1, 0.1, 0.05), 0.2).duplicate()
	return _tail_mat

## A two-tread entry step under the side doorway. It is its own body so it never drags on the
## ground or knocks the van about, and the player climbs it like stairs.
func _build_steps(vis: Node3D, m: Material) -> void:
	var sb := StaticBody3D.new()
	sb.name = "Steps"
	sb.collision_layer = 16
	sb.collision_mask = 0
	add_child(sb)
	add_collision_exception_with(sb)
	var zc := (DOOR_Z0 + DOOR_Z1) * 0.5
	var len := DOOR_Z1 - DOOR_Z0 - 0.08
	var tread := Lib.mat("metal", Color(0.62, 0.62, 0.64), 4.0, false, 0.45, 0.8)
	for s in [[FLOOR_Y - 0.36, 0.32], [FLOOR_Y - 0.72, 0.6]]:
		var top: float = s[0]
		var d: float = s[1]
		var c := Vector3(SKIN + d * 0.5 - 0.02, top - 0.025, zc)
		Lib.box(vis, c, Vector3(d, 0.05, len), tread, false, Vector3.ZERO, 0.012)
		Lib.box(vis, c + Vector3(d * 0.5 - 0.01, -0.04, 0), Vector3(0.02, 0.08, len), m)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(d, 0.05, len)
		cs.shape = sh
		cs.position = c
		sb.add_child(cs)
	for dz in [-len * 0.5 + 0.06, len * 0.5 - 0.06]:
		Lib.box(vis, Vector3(SKIN + 0.25, FLOOR_Y - 0.55, zc + dz), Vector3(0.5, 0.04, 0.04), m, false, Vector3(0, 0, -0.9))

## Wall along Z at x with rectangular holes [z0, z1, y0, y1] (absolute y), from z_a to z_b.
func _wall_x(parent: Node3D, x: float, m: Material, holes: Array, z_a := REAR_Z, z_b := CAB_Z, glass := true) -> void:
	var z_edges: Array[float] = [z_a, z_b]
	for hole in holes:
		if hole[0] < z_b and hole[1] > z_a:
			z_edges.append(clampf(hole[0], z_a, z_b))
			z_edges.append(clampf(hole[1], z_a, z_b))
	z_edges.sort()
	for i in range(z_edges.size() - 1):
		var z0 := z_edges[i]
		var z1 := z_edges[i + 1]
		if z1 - z0 < 0.001:
			continue
		var zc := (z0 + z1) * 0.5
		var ys: Array = [[FLOOR_Y, ROOF_Y]]
		for hole in holes:
			if zc > hole[0] and zc < hole[1]:
				ys = [[FLOOR_Y, maxf(hole[2], FLOOR_Y)], [hole[3], ROOF_Y]]
				if glass and hole[2] > FLOOR_Y + 0.1 and hole[3] - hole[2] < 2.0:
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

var _doors := {} # action -> {"pivot": Node3D, "open": bool}
var _battery_vis: Node3D

## Materials: the bare shell is ribbed sheet metal and primer; fitted panels bring off-white wall
## board, vinyl planks, laminate cabinetry and quilted upholstery.
func _interior_mats() -> Dictionary:
	return {
		"bare": Lib.mat("ribbed_metal", Color(0.85, 0.85, 0.85), 1.2, false, 0.6, 0.5),
		"bare_floor": Lib.mat("ribbed_metal", Color(0.55, 0.55, 0.56), 1.0, false, 0.7, 0.5),
		"wall": Lib.color_mat(Color(0.88, 0.86, 0.82), 0.8),
		"insul": Lib.mat("insulation", Color.WHITE, 1.5, false, 0.6, 0.5),
		"ceiling": Lib.color_mat(Color(0.93, 0.92, 0.9), 0.9),
		"floor": Lib.mat("vinyl", Color.WHITE, 0.9, false, 0.55),
		"cab": Lib.mat("laminate", Color.WHITE, 1.4, false, 0.45),
		"cab_trim": Lib.color_mat(Color(0.36, 0.35, 0.34), 0.5),
		"counter": Lib.mat("concrete", Color(0.55, 0.55, 0.56), 1.0, false, 0.35),
		"fabric": Lib.mat("upholstery", Color.WHITE, 0.45, false, 0.95),
		"fabric2": Lib.mat("plaid", Color(0.75, 0.75, 0.78), 2.0, false, 0.95),
		"metal": Lib.color_mat(Color(0.72, 0.72, 0.74), 0.3, 0.8),
		"plastic": Lib.color_mat(Color(0.14, 0.14, 0.15), 0.55),
		"black": Lib.color_mat(Color(0.06, 0.06, 0.06), 0.5),
	}

## A cupboard or fridge whose front faces +X, with shelves you can put things on and a
## door you open and close. center/size are the outer box in van space.
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
	if _grp != "":
		hs.set_meta("slot", _grp)
		_mod_parts[_grp].append(hs)
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
	# ---- the bare shell: ribbed sheet metal, exposed roof bows, a primer-grey dash
	Lib.box(vis, Vector3(0, FLOOR_Y + 0.005, mid), Vector3(W - 0.12, 0.01, L - 0.05), M["bare_floor"])
	Lib.box(vis, Vector3(0, ROOF_Y - 0.02, (CAB_Z + REAR_Z) * 0.5), Vector3(W - 0.12, 0.02, CAB_Z - REAR_Z), M["bare"])
	var bow := Lib.mat("primer", Color(0.75, 0.75, 0.75), 2.0, false, 0.7, 0.3)
	for z in [-2.6, -1.6, -0.6, 0.4, 1.4, 2.4]:
		Lib.box(vis, Vector3(0, ROOF_Y - 0.06, z), Vector3(W - 0.14, 0.06, 0.06), bow)
		for x in [-W * 0.5 + 0.1, W * 0.5 - 0.1]:
			if z > DOOR_Z0 - 0.1 and z < DOOR_Z1 + 0.1 and x > 0.0:
				continue
			Lib.box(vis, Vector3(x, FLOOR_Y + h * 0.5, z), Vector3(0.05, h - 0.1, 0.06), bow)
	_wall_x(vis, -W * 0.5 + 0.06, M["bare"], WIN_L, REAR_Z, CAB_Z, false)
	_wall_x(vis, W * 0.5 - 0.06, M["bare"], WIN_R, REAR_Z, CAB_Z, false)
	Lib.box(vis, Vector3(0, FLOOR_Y + h * 0.5, REAR_Z + 0.07), Vector3(W - 0.12, h, 0.03), M["bare"])
	# cab: door cards below the cab windows, sloped header above the windshield
	for sx in [-1.0, 1.0]:
		Lib.box(vis, Vector3(sx * (W * 0.5 - 0.07), FLOOR_Y + 0.43, (CAB_Z + FRONT_Z + 0.35) * 0.5), Vector3(0.05, 0.86, FRONT_Z + 0.35 - CAB_Z), M["plastic"])
	Lib.box(vis, Vector3(0, 3.05, FRONT_Z - 0.48), Vector3(W - 0.14, 0.03, 0.48), M["plastic"], false, Vector3(-2.19, 0, 0))
	# moulded dashboard, gauges, centre console
	var dash_c := Vector3(0, FLOOR_Y + 0.75, FRONT_Z + 0.02)
	Lib.box(vis, dash_c, Vector3(W - 0.15, 0.5, 0.64), M["plastic"], false, Vector3.ZERO, 0.06)
	Lib.box(vis, dash_c + Vector3(0, 0.26, -0.03), Vector3(W - 0.2, 0.03, 0.58), Lib.color_mat(Color(0.2, 0.2, 0.21), 0.7))
	_shape(dash_c, Vector3(W - 0.15, 0.5, 0.64))
	var cluster := Lib.box(vis, Vector3(-0.55, FLOOR_Y + 0.92, FRONT_Z - 0.31), Vector3(0.5, 0.18, 0.04), Lib.color_mat(Color(0.05, 0.05, 0.06), 0.3))
	cluster.rotation.x = -0.3
	for gx in [-0.68, -0.42]:
		var gg := Lib.cyl(vis, Vector3(gx, FLOOR_Y + 0.92, FRONT_Z - 0.335), 0.06, 0.06, 0.01, Lib.color_mat(Color(0.9, 0.9, 0.85), 0.3, 0.0, Color(0.5, 0.9, 1.0), 0.5), Vector3(PI * 0.5 - 0.3, 0, 0))
		gg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for vx in [-0.95, 0.35, 0.95]:
		Lib.box(vis, Vector3(vx, FLOOR_Y + 0.85, FRONT_Z - 0.31), Vector3(0.16, 0.08, 0.02), M["black"])
	Lib.box(vis, Vector3(0.05, FLOOR_Y + 0.85, FRONT_Z - 0.305), Vector3(0.2, 0.07, 0.02), M["black"]) # empty radio slot
	Lib.box(vis, Vector3(0, FLOOR_Y + 0.25, FRONT_Z - 0.75), Vector3(0.3, 0.5, 0.6), M["plastic"], false, Vector3.ZERO, 0.04)
	# bare seat pedestals (seats are modules)
	for x in [-0.55, 0.55]:
		Lib.box(vis, Vector3(x, FLOOR_Y + 0.2, FRONT_Z - 1.05), Vector3(0.4, 0.38, 0.4), M["black"])
		_shape(Vector3(x, FLOOR_Y + 0.2, FRONT_Z - 1.05), Vector3(0.4, 0.38, 0.4))
	# steering column stub
	Lib.cyl(vis, Vector3(-0.55, FLOOR_Y + 0.78, FRONT_Z - 0.28), 0.035, 0.035, 0.3, M["black"], Vector3(-1.1, 0, 0), 10)
	# light switch
	Lib.box(vis, Vector3(W * 0.5 - 0.1, FLOOR_Y + 1.4, DOOR_Z0 - 0.12), Vector3(0.03, 0.12, 0.08), Lib.color_mat(Color(0.9, 0.9, 0.85)))
	_part(Vector3(W * 0.5 - 0.12, FLOOR_Y + 1.4, DOOR_Z0 - 0.12), Vector3(0.1, 0.25, 0.2), "lights")
	_interior_light = Lib.light(vis, Vector3(0, ROOF_Y - 0.3, -0.5), Color(1.0, 0.86, 0.66), 1.4, 6.0, false)
	_interior_light.visible = false
	_build_modules(vis, M)

## Every fittable module, built hidden; _apply_modules shows the fitted ones.
func _build_modules(vis: Node3D, M: Dictionary) -> void:
	var L := FRONT_Z - REAR_Z
	var mid := (FRONT_Z + REAR_Z) * 0.5
	var h := ROOF_Y - FLOOR_Y
	# ---- flooring and wall panels
	var fl := _begin("floor", vis)
	Lib.box(fl, Vector3(0, FLOOR_Y + 0.02, (CAB_Z - 0.3 + REAR_Z) * 0.5), Vector3(W - 0.16, 0.02, CAB_Z - 0.3 - REAR_Z - 0.05), M["floor"])
	Lib.box(fl, Vector3(0.0, FLOOR_Y + 0.035, -0.3), Vector3(0.7, 0.01, 1.8), Lib.mat("carpet", Color(0.45, 0.42, 0.4), 1.5, false))
	_end()
	var wl := _begin("walls", vis)
	_wall_x(wl, -W * 0.5 + 0.11, M["wall"], WIN_L, REAR_Z, CAB_Z, false)
	_wall_x(wl, W * 0.5 - 0.11, M["wall"], WIN_R, REAR_Z, CAB_Z, false)
	Lib.box(wl, Vector3(0, FLOOR_Y + h * 0.5, REAR_Z + 0.1), Vector3(W - 0.18, h, 0.03), M["wall"])
	Lib.box(wl, Vector3(0, ROOF_Y - 0.1, (CAB_Z + REAR_Z) * 0.5), Vector3(W - 0.18, 0.03, CAB_Z - REAR_Z), M["ceiling"])
	for x in [-W * 0.5 + 0.13, W * 0.5 - 0.13]:
		Lib.box(wl, Vector3(x, FLOOR_Y + 0.05, (CAB_Z + REAR_Z) * 0.5), Vector3(0.02, 0.08, CAB_Z - REAR_Z - 0.1), M["cab_trim"])
		Lib.box(wl, Vector3(x, ROOF_Y - 0.14, (CAB_Z + REAR_Z) * 0.5), Vector3(0.03, 0.05, CAB_Z - REAR_Z - 0.1), M["cab_trim"])
	_end()
	# ---- cab: steering wheel, seats, radio
	var stv := _begin("steering", vis)
	var sw := MeshInstance3D.new()
	sw.mesh = Items.mesh("steering_wheel")
	sw.name = "SteeringWheel"
	sw.position = Vector3(-0.55, FLOOR_Y + 0.82, FRONT_Z - 0.42)
	sw.rotation = Vector3(-1.1, 0, 0)
	stv.add_child(sw)
	_end()
	for i in range(2):
		var x: float = [-0.55, 0.55][i]
		var sv := _begin("seat_driver" if i == 0 else "seat_passenger", vis)
		var seat := MeshInstance3D.new()
		seat.mesh = Items.mesh("car_seat")
		seat.position = Vector3(x, FLOOR_Y + 0.38, FRONT_Z - 1.1)
		seat.scale = Vector3(1.1, 1.0, 1.1)
		sv.add_child(seat)
		_part(Vector3(x, FLOOR_Y + 0.75, FRONT_Z - 1.1), Vector3(0.6, 0.8, 0.6), "drive" if i == 0 else "passenger")
		_end()
	var rd := _begin("radio", vis)
	var rm := MeshInstance3D.new()
	rm.mesh = Items.mesh("radio")
	rm.position = Vector3(0.05, FLOOR_Y + 0.82, FRONT_Z - 0.29)
	rm.rotation.y = PI
	rd.add_child(rm)
	_part(Vector3(0.05, FLOOR_Y + 0.85, FRONT_Z - 0.33), Vector3(0.28, 0.16, 0.12), "radio")
	_radio_audio = AudioStreamPlayer3D.new()
	_radio_audio.bus = "Vehicle"
	_radio_audio.unit_size = 4.0
	_radio_audio.max_distance = 30.0
	_radio_audio.volume_db = -8.0
	_radio_audio.position = Vector3(0, FLOOR_Y + 0.9, FRONT_Z - 0.3)
	rd.add_child(_radio_audio)
	_end()
	# ---- galley (left wall): counter, then stove, sink and coffee maker on it
	var kz0 := -0.2
	var kz1 := 1.5
	var kx := -W * 0.5 + 0.42
	var kt := _begin("kitchen", vis)
	Lib.box(kt, Vector3(kx, FLOOR_Y + 0.45, (kz0 + kz1) * 0.5), Vector3(0.6, 0.9, kz1 - kz0), M["cab"])
	for dz in [0.15, 0.55, 0.95, 1.3]:
		Lib.box(kt, Vector3(kx + 0.305, FLOOR_Y + 0.45, kz0 + dz), Vector3(0.01, 0.8, 0.005), M["cab_trim"])
		Lib.box(kt, Vector3(kx + 0.32, FLOOR_Y + 0.75, kz0 + dz - 0.12), Vector3(0.02, 0.02, 0.1), M["metal"])
	Lib.box(kt, Vector3(kx, FLOOR_Y + 0.92, (kz0 + kz1) * 0.5), Vector3(0.64, 0.05, kz1 - kz0 + 0.02), M["counter"])
	_shape(Vector3(kx, FLOOR_Y + 0.4725, (kz0 + kz1) * 0.5), Vector3(0.64, 0.945, kz1 - kz0 + 0.02))
	Lib.box(kt, Vector3(-W * 0.5 + 0.13, FLOOR_Y + 1.02, (kz0 + kz1) * 0.5), Vector3(0.01, 0.16, kz1 - kz0), Lib.mat("tiles", Color(0.85, 0.85, 0.82), 2.5, false, 0.3))
	_end()
	var stove := _begin("stove", vis)
	Lib.box(stove, Vector3(kx, FLOOR_Y + 0.955, 1.1), Vector3(0.5, 0.02, 0.55), M["black"])
	for p in [Vector2(-0.12, 0.95), Vector2(0.12, 0.95), Vector2(-0.12, 1.25), Vector2(0.12, 1.25)]:
		Lib.cyl(stove, Vector3(kx + p.x, FLOOR_Y + 0.97, p.y), 0.08, 0.08, 0.01, Lib.color_mat(Color(0.25, 0.25, 0.25), 0.4, 0.7))
		var fm := Lib.cyl(stove, Vector3(kx + p.x, FLOOR_Y + 0.985, p.y), 0.06, 0.07, 0.025, Lib.color_mat(Color(0.3, 0.5, 1.0), 0.2, 0.0, Color(0.35, 0.55, 1.0), 2.5))
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fm.visible = false
		_flames.append(fm)
	for z in [0.92, 1.28]:
		Lib.cyl(stove, Vector3(kx + 0.31, FLOOR_Y + 0.85, z), 0.02, 0.02, 0.03, M["metal"], Vector3(0, 0, PI * 0.5))
	_part(Vector3(kx, FLOOR_Y + 1.0, 1.1), Vector3(0.52, 0.12, 0.57), "stove")
	_end()
	var sink := _begin("sink", vis)
	Lib.box(sink, Vector3(kx, FLOOR_Y + 0.92, 0.35), Vector3(0.42, 0.06, 0.38), M["metal"])
	Lib.box(sink, Vector3(kx, FLOOR_Y + 0.9, 0.35), Vector3(0.34, 0.06, 0.3), Lib.color_mat(Color(0.35, 0.36, 0.38), 0.2, 0.9))
	Lib.cyl(sink, Vector3(-W * 0.5 + 0.2, FLOOR_Y + 1.06, 0.35), 0.015, 0.015, 0.24, M["metal"])
	Lib.cyl(sink, Vector3(-W * 0.5 + 0.28, FLOOR_Y + 1.17, 0.35), 0.012, 0.012, 0.18, M["metal"], Vector3(0, 0, PI * 0.5))
	_part(Vector3(kx, FLOOR_Y + 1.0, 0.35), Vector3(0.46, 0.14, 0.42), "sink")
	_part(Vector3(-W * 0.5 + 0.24, FLOOR_Y + 1.2, 0.35), Vector3(0.14, 0.3, 0.14), "sink")
	_end()
	var cof := _begin("coffee", vis)
	var cm := MeshInstance3D.new()
	cm.mesh = Items.mesh("coffee_maker")
	cm.position = Vector3(-W * 0.5 + 0.32, FLOOR_Y + 0.945, -0.05)
	cm.rotation.y = PI * 0.5
	cof.add_child(cm)
	_part(Vector3(-W * 0.5 + 0.32, FLOOR_Y + 1.08, -0.05), Vector3(0.24, 0.3, 0.22), "coffee")
	_end()
	var ov := _begin("overhead", vis)
	_cupboard(ov, "overhead", Vector3(-W * 0.5 + 0.34, ROOF_Y - 0.37, 0.65), Vector3(0.44, 0.5, 1.6), [], M["cab"], M["cab"], M["cab_trim"])
	_end()
	var fr := _begin("fridge", vis)
	_cupboard(fr, "fridge", Vector3(-W * 0.5 + 0.44, FLOOR_Y + 0.86, -0.67), Vector3(0.62, 1.7, 0.68), [FLOOR_Y + 0.5, FLOOR_Y + 0.95, FLOOR_Y + 1.35],
		Lib.color_mat(Color(0.93, 0.93, 0.91), 0.3), Lib.color_mat(Color(0.88, 0.88, 0.86), 0.25), Lib.color_mat(Color(0.8, 0.8, 0.78), 0.25))
	_end()
	var cu := _begin("cupboard", vis)
	_cupboard(cu, "cabinet", Vector3(-W * 0.5 + 0.38, FLOOR_Y + 0.5, -1.45), Vector3(0.56, 1.0, 0.8), [FLOOR_Y + 0.5], M["cab"], M["cab"], M["cab_trim"])
	for i in range(2):
		var pot := StaticBody3D.new()
		pot.set_script(Structure)
		pot.persistent = false
		var pot_index := i
		pot.save_cb = func(d: Dictionary) -> void: pots[pot_index] = d
		vis.add_child(pot)
		pot.setup("", {"type": "planter", "pos": [-W * 0.5 + 0.37, FLOOR_Y + 1.0, -1.65 + i * 0.42], "rot": PI * 0.5, "data": pots[i]})
		pot.scale = Vector3(0.25, 0.6, 0.45)
		pot.collision_layer = 2
		pot.collision_mask = 0
		pot.name = "Pot%d" % i
		_mod_extra["cupboard"].append(pot)
	_end()
	# ---- dinette (right side): table and two benches
	var tx := W * 0.5 - 0.47
	var dn := _begin("dinette", vis)
	Lib.box(dn, Vector3(tx, FLOOR_Y + 0.72, -0.5), Vector3(0.7, 0.04, 0.9), M["counter"], false, Vector3.ZERO, 0.015)
	Lib.box(dn, Vector3(tx, FLOOR_Y + 0.69, -0.5), Vector3(0.72, 0.02, 0.92), M["cab_trim"])
	_shape(Vector3(tx, FLOOR_Y + 0.72, -0.5), Vector3(0.7, 0.05, 0.9))
	Lib.cyl(dn, Vector3(tx, FLOOR_Y + 0.36, -0.5), 0.04, 0.04, 0.72, M["metal"])
	for z in [0.25, -1.25]:
		Lib.box(dn, Vector3(W * 0.5 - 0.44, FLOOR_Y + 0.22, z), Vector3(0.75, 0.44, 0.45), M["cab"])
		Lib.box(dn, Vector3(W * 0.5 - 0.44, FLOOR_Y + 0.5, z), Vector3(0.75, 0.12, 0.45), M["fabric"], false, Vector3.ZERO, 0.04)
		Lib.box(dn, Vector3(W * 0.5 - 0.44, FLOOR_Y + 0.85, z + signf(z) * 0.17), Vector3(0.75, 0.6, 0.1), M["fabric"], false, Vector3.ZERO, 0.04)
		_shape(Vector3(W * 0.5 - 0.44, FLOOR_Y + 0.28, z), Vector3(0.75, 0.56, 0.45))
	_end()
	# ---- bathroom cubicle (right rear)
	var tl := _begin("toilet", vis)
	Lib.box(tl, Vector3(W * 0.5 - 0.52, FLOOR_Y + h * 0.5, -1.75), Vector3(0.9, h, 0.05), M["wall"])
	Lib.box(tl, Vector3(0.16, FLOOR_Y + h * 0.5, -2.2), Vector3(0.05, h, 0.95), M["wall"])
	_shape(Vector3(W * 0.5 - 0.52, FLOOR_Y + h * 0.5, -1.75), Vector3(0.9, h, 0.05))
	var toil := MeshInstance3D.new()
	toil.mesh = Items.mesh("toilet_unit")
	toil.position = Vector3(W * 0.5 - 0.45, FLOOR_Y, -2.45)
	toil.rotation.y = -PI * 0.5
	tl.add_child(toil)
	_part(Vector3(W * 0.5 - 0.45, FLOOR_Y + 0.4, -2.45), Vector3(0.5, 0.8, 0.5), "toilet")
	_end()
	# ---- rear bed: laminate platform first, then a mattress, duvet and pillow on it
	var bd := _begin("bed", vis)
	Lib.box(bd, Vector3(-0.27, FLOOR_Y + 0.3, -2.75), Vector3(1.85, 0.6, 1.2), M["cab"])
	Lib.box(bd, Vector3(-0.27, FLOOR_Y + 0.605, -2.75), Vector3(1.8, 0.02, 1.15), Lib.mat("planks", Color(1.0, 0.9, 0.75), 2.0, false))
	_shape(Vector3(-0.27, FLOOR_Y + 0.31, -2.75), Vector3(1.85, 0.62, 1.2))
	_end()
	var mt := _begin("mattress", vis)
	Lib.box(mt, Vector3(-0.27, FLOOR_Y + 0.7, -2.75), Vector3(1.8, 0.18, 1.15), Lib.mat("upholstery", Color(1.6, 1.6, 1.55), 1.5, false, 0.95), false, Vector3.ZERO, 0.06)
	Lib.box(mt, Vector3(-0.87, FLOOR_Y + 0.84, -2.75), Vector3(0.35, 0.1, 0.8), Lib.color_mat(Color("eae6dd"), 0.95), false, Vector3.ZERO, 0.04)
	Lib.box(mt, Vector3(0.08, FLOOR_Y + 0.81, -2.75), Vector3(1.1, 0.06, 1.17), M["fabric2"], false, Vector3.ZERO, 0.02)
	_shape(Vector3(-0.27, FLOOR_Y + 0.7, -2.75), Vector3(1.85, 0.2, 1.2))
	_part(Vector3(-0.87, FLOOR_Y + 0.92, -2.75), Vector3(0.4, 0.15, 0.85), "bed")
	_end()
	# ---- ceiling lights, heater
	var lt := _begin("light", vis)
	for z in [-1.8, 0.6]:
		var lm := MeshInstance3D.new()
		lm.mesh = Items.mesh("ceiling_light")
		lm.position = Vector3(0, ROOF_Y - 0.03, z)
		lm.rotation.x = PI
		lt.add_child(lm)
	_end()
	var ht := _begin("heater", vis)
	var hm := MeshInstance3D.new()
	hm.mesh = Items.mesh("heater_unit")
	hm.position = Vector3(W * 0.5 - 0.25, FLOOR_Y, 1.85)
	hm.rotation.y = -PI * 0.5
	ht.add_child(hm)
	_shape(Vector3(W * 0.5 - 0.25, FLOOR_Y + 0.15, 1.85), Vector3(0.22, 0.3, 0.38))
	_end()

## Mount hotspots: where each module goes. They show what's missing and take the module in.
func _build_mounts() -> void:
	var tx := W * 0.5 - 0.47
	var kx := -W * 0.5 + 0.42
	_mount("steering", Vector3(-0.55, FLOOR_Y + 0.85, FRONT_Z - 0.45), Vector3(0.45, 0.35, 0.2))
	_mount("seat_driver", Vector3(-0.55, FLOOR_Y + 0.55, FRONT_Z - 1.1), Vector3(0.62, 0.35, 0.62))
	_mount("seat_passenger", Vector3(0.55, FLOOR_Y + 0.55, FRONT_Z - 1.1), Vector3(0.62, 0.35, 0.62))
	_mount("radio", Vector3(0.05, FLOOR_Y + 0.85, FRONT_Z - 0.33), Vector3(0.28, 0.16, 0.12))
	_mount("headlight_l", Vector3(-0.85, 1.25, FRONT_Z + 1.33), Vector3(0.46, 0.3, 0.12))
	_mount("headlight_r", Vector3(0.85, 1.25, FRONT_Z + 1.33), Vector3(0.46, 0.3, 0.12))
	_mount("bullbar", Vector3(0, 0.75, FRONT_Z + 1.5), Vector3(W, 0.4, 0.2))
	_mount("solar", Vector3(0.75, 2.6, REAR_Z - 0.25), Vector3(0.6, 1.0, 0.2))
	_mount("water_tank", Vector3(-W * 0.5 - 0.05, 0.65, -1.2), Vector3(0.3, 0.35, 0.8))
	_mount("big_tank", Vector3(W * 0.5 + 0.05, 0.65, -0.2), Vector3(0.3, 0.35, 0.9))
	_mount("floor", Vector3(0, FLOOR_Y + 0.03, -0.9), Vector3(W - 0.4, 0.04, 4.4))
	_mount("walls", Vector3(-W * 0.5 + 0.2, FLOOR_Y + 1.2, -2.0), Vector3(0.08, 1.2, 1.3))
	_mount("kitchen", Vector3(kx + 0.01, FLOOR_Y + 0.46, 0.65), Vector3(0.66, 0.92, 1.74))
	_mount("stove", Vector3(kx, FLOOR_Y + 1.0, 1.1), Vector3(0.5, 0.08, 0.55))
	_mount("sink", Vector3(kx, FLOOR_Y + 1.0, 0.35), Vector3(0.44, 0.08, 0.4))
	_mount("coffee", Vector3(-W * 0.5 + 0.32, FLOOR_Y + 1.05, -0.05), Vector3(0.26, 0.2, 0.24))
	_mount("overhead", Vector3(-W * 0.5 + 0.34, ROOF_Y - 0.37, 0.65), Vector3(0.46, 0.5, 1.6))
	_mount("fridge", Vector3(-W * 0.5 + 0.44, FLOOR_Y + 0.86, -0.67), Vector3(0.64, 1.7, 0.7))
	_mount("cupboard", Vector3(-W * 0.5 + 0.38, FLOOR_Y + 0.5, -1.45), Vector3(0.6, 1.0, 0.82))
	_mount("dinette", Vector3(tx, FLOOR_Y + 0.75, -0.5), Vector3(0.78, 0.12, 0.95))
	_mount("toilet", Vector3(W * 0.5 - 0.45, FLOOR_Y + 0.4, -2.45), Vector3(0.55, 0.8, 0.55))
	_mount("bed", Vector3(-0.27, FLOOR_Y + 0.35, -2.75), Vector3(1.9, 0.7, 1.25))
	_mount("mattress", Vector3(-0.27, FLOOR_Y + 0.66, -2.75), Vector3(1.85, 0.1, 1.2))
	_mount("light", Vector3(0, ROOF_Y - 0.12, -0.6), Vector3(0.5, 0.1, 0.5))
	_mount("heater", Vector3(W * 0.5 - 0.25, FLOOR_Y + 0.17, 1.85), Vector3(0.26, 0.34, 0.42))
	_mount("door", Vector3(W * 0.5, FLOOR_Y + DOOR_H * 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), Vector3(0.24, DOOR_H, DOOR_Z1 - DOOR_Z0))

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

# ------------------------------------------------------------------ modules
func has_mod(slot: String) -> bool:
	return modules.has(slot)

func _needs_met(slot: String) -> String:
	for n in Data.VAN_SLOTS[slot].get("needs", []):
		if not modules.has(n):
			return n
	return ""

# ------------------------------------------------------------------ free furniture placement
## Where a free slot's furniture stands: maps the default layout onto the chosen spot.
func _slot_offset(slot: String) -> Transform3D:
	var root: String = FOLLOW.get(slot, slot)
	if not FREE.has(root) or not module_xf.has(root):
		return Transform3D.IDENTITY
	var a: Vector3 = FREE[root][0]
	var m: Array = module_xf[root]
	return Transform3D(Basis(Vector3.UP, float(m[2])), Vector3(float(m[0]), FLOOR_Y, float(m[1]))) * Transform3D(Basis.IDENTITY, -a)

func _move_node(n: Node3D, off: Transform3D) -> void:
	if not _base_xf.has(n):
		_base_xf[n] = n.transform
	n.transform = off * (_base_xf[n] as Transform3D)

## Move every free module (visuals, collision, hotspots) to where it was placed.
func _apply_offsets() -> void:
	for slot in _mod_vis:
		var root: String = FOLLOW.get(slot, slot)
		if not FREE.has(root):
			continue
		var off := _slot_offset(slot)
		_move_node(_mod_vis[slot], off)
		for cs in _mod_shapes[slot]:
			_move_node(cs, off)
		for p in _mod_parts[slot]:
			if p.get_parent() == self:
				_move_node(p, off)
		for n in _mod_extra[slot]:
			_move_node(n, off)
		if _mounts.has(slot):
			_move_node(_mounts[slot], off)

## The free furniture slot this item can go into (empty string if none / already fitted).
func free_slot_for(item: String) -> String:
	for slot in FREE:
		if Data.VAN_SLOTS[slot]["item"] == item and not modules.has(slot):
			return slot
	return ""

static func _rect_of(slot: String, x: float, z: float, yaw: float) -> Rect2:
	var sz: Vector2 = FREE[slot][1]
	if absi(int(round(yaw / (PI * 0.5)))) % 2 == 1:
		sz = Vector2(sz.y, sz.x)
	return Rect2(Vector2(x, z) - sz * 0.5, sz)

## Work out where a piece of furniture would stand if placed at lp (van space) with the
## player's extra rotation. It slides flush against the walls rather than poking through.
func plan_free(slot: String, lp: Vector3, user_yaw: float, player_lp: Vector3) -> Dictionary:
	var side := int(FREE[slot][2])
	var yaw := snappedf(user_yaw, PI * 0.5)
	if side != 0 and signf(lp.x) != float(side) and absf(lp.x) > 0.15:
		yaw += PI
	yaw = wrapf(yaw, -PI * 0.25, TAU - PI * 0.25)
	var r := _rect_of(slot, 0.0, 0.0, yaw)
	var x0 := -W * 0.5 + 0.12 + r.size.x * 0.5
	var x1 := W * 0.5 - 0.12 - r.size.x * 0.5
	var z0 := REAR_Z + 0.1 + r.size.y * 0.5
	var z1 := FRONT_Z - 1.3 - r.size.y * 0.5
	var x := snappedf(clampf(lp.x, minf(x0, x1), maxf(x0, x1)), 0.05)
	var z := snappedf(clampf(lp.z, z0, z1), 0.05)
	var plan := {"x": x, "z": z, "yaw": yaw, "ok": true, "reason": ""}
	r = _rect_of(slot, x, z, yaw)
	var shrink := r.grow(-0.04)
	for other in FREE:
		if other == slot or not modules.has(other):
			continue
		var o: Array = module_xf.get(other, [FREE[other][0].x, FREE[other][0].z, 0.0])
		if shrink.intersects(_rect_of(other, float(o[0]), float(o[1]), float(o[2]))):
			plan["ok"] = false
			plan["reason"] = "In the way of the %s" % Data.VAN_SLOTS[other]["name"].to_lower()
			return plan
	if shrink.intersects(Rect2(W * 0.5 - 0.75, DOOR_Z0 - 0.05, 0.75, DOOR_Z1 - DOOR_Z0 + 0.1)):
		plan["ok"] = false
		plan["reason"] = "Keep the doorway clear"
		return plan
	if r.grow(0.3).has_point(Vector2(player_lp.x, player_lp.z)):
		plan["ok"] = false
		plan["reason"] = "Step back, you're standing there"
	return plan

func _free_ghost(slot: String) -> Node3D:
	if not _ghosts.has(slot):
		_ghosts[slot] = _make_ghost(slot)
	return _ghosts[slot]

## Show the translucent furniture where it would go (green if it fits there, red if not).
func preview_free(slot: String, plan: Dictionary) -> void:
	var g := _free_ghost(slot)
	var a: Vector3 = FREE[slot][0]
	g.transform = Transform3D(Basis(Vector3.UP, float(plan["yaw"])), Vector3(plan["x"], FLOOR_Y, plan["z"])) * Transform3D(Basis.IDENTITY, -a)
	g.visible = true
	_paint_ghost(g, _ghost_mat if plan["ok"] else _ghost_bad_mat)
	for other in FREE:
		if other != slot and _ghosts.has(other):
			(_ghosts[other] as Node3D).visible = false

func hide_free_preview() -> void:
	for slot in FREE:
		if _ghosts.has(slot):
			(_ghosts[slot] as Node3D).visible = false

func _paint_ghost(n: Node, m: Material) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).material_override = m
		_paint_ghost(ch, m)

## Fit held furniture at the planned spot.
func install_free(slot: String, plan: Dictionary) -> bool:
	if not plan.get("ok", false):
		Game.notify(str(plan.get("reason", "It doesn't fit there")))
		return false
	var prev = module_xf.get(slot)
	module_xf[slot] = [float(plan["x"]), float(plan["z"]), float(plan["yaw"])]
	if not install_module(slot):
		if prev == null:
			module_xf.erase(slot)
		else:
			module_xf[slot] = prev
		return false
	hide_free_preview()
	return true

## Show fitted modules, hide the rest, and switch their collisions and hotspots.
func _apply_modules() -> void:
	_apply_offsets()
	for slot in _mod_vis:
		var on := modules.has(slot)
		(_mod_vis[slot] as Node3D).visible = on
		for cs in _mod_shapes[slot]:
			(cs as CollisionShape3D).disabled = not on
		for p in _mod_parts[slot]:
			(p as CollisionObject3D).collision_layer = 2 if on else 0
		for n in _mod_extra[slot]:
			n.visible = on
			n.collision_layer = 2 if on else 0
	for slot in _mounts:
		var on := modules.has(slot)
		var own: bool = _mod_parts.has(slot) and not _mod_parts[slot].is_empty()
		var active: bool = (not on and _needs_met(slot) == "") or (on and not own and slot not in FIXED)
		if FREE.has(slot) and not on:
			active = false # free furniture is placed by aiming at the floor, not at a fixed spot
		if slot == "door":
			active = not on and Game.equipped() == "van_door"
		_mounts[slot].collision_layer = 2 if active else 0
	set_door(door_open, false)
	upgrades = {}
	for u in ["solar", "bullbar", "heater", "big_tank", "engine_tune", "water_tank"]:
		if modules.has(u):
			upgrades[u] = true
	var off := 0
	for i in range(4):
		if wheel_kind.get("wheel%d" % i, "") == "offroad_tire" and not missing.has("wheel%d" % i):
			off += 1
	if off == 4:
		upgrades["offroad_tires"] = true
	if not modules.has("light"):
		interior_lights = false
	if not modules.has("stove"):
		stove_on = false
	if not modules.has("radio"):
		_set_radio(false)
	if not (modules.has("headlight_l") or modules.has("headlight_r")):
		headlights = false
	fuel = minf(fuel, fuel_capacity())
	water = minf(water, water_capacity())
	if _interior_light:
		_update_lights()
	_update_ghosts()

## While you hold a module, outline the empty spots it fits in green.
func _update_ghosts() -> void:
	var held := Game.equipped()
	if _mounts.has("door"):
		_mounts["door"].collision_layer = 2 if held == "van_door" and not modules.has("door") else 0
	for slot in _mod_vis:
		if FREE.has(slot):
			continue # previewed where you aim (see preview_free)
		var want: bool = Data.VAN_SLOTS.has(slot) and Data.VAN_SLOTS[slot]["item"] == held and not modules.has(slot) and _needs_met(slot) == ""
		if want and not _ghosts.has(slot):
			_ghosts[slot] = _make_ghost(slot)
		if _ghosts.has(slot):
			(_ghosts[slot] as Node3D).visible = want

func _make_ghost(slot: String) -> Node3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.3)
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.no_depth_test = false
		_ghost_bad_mat = _ghost_mat.duplicate()
		_ghost_bad_mat.albedo_color = Color(1.0, 0.35, 0.3, 0.3)
	var src: Node3D = _mod_vis[slot]
	var g: Node3D = src.duplicate(0)
	g.name = "Ghost_" + slot
	src.get_parent().add_child(g)
	_ghostify(g)
	return g

func _ghostify(n: Node) -> void:
	for ch in n.get_children():
		if ch is CollisionObject3D or ch is Light3D or ch is AudioStreamPlayer3D:
			ch.queue_free()
			continue
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).material_override = _ghost_mat
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghostify(ch)

func _toolkit_ok(slot: String) -> bool:
	return not Data.VAN_SLOTS[slot].get("toolkit", false) or Game.count("toolkit") > 0

func mount_prompt(slot: String) -> String:
	var spec: Dictionary = Data.VAN_SLOTS[slot]
	var item: String = spec["item"]
	var nm := Data.item_name(item)
	if modules.has(slot):
		return "%s  —  [G] Take it out" % nm
	var need := _needs_met(slot)
	if need != "":
		return "%s — fit the %s first" % [spec["name"], Data.VAN_SLOTS[need]["name"].to_lower()]
	if Game.equipped() == item:
		return "[E] Fit the %s%s" % [nm, "" if _toolkit_ok(slot) else "  (needs a Toolkit in hand or within reach)"]
	return "Empty: %s — carry a %s here" % [spec["name"].to_lower(), nm]

func install_module(slot: String) -> bool:
	var spec: Dictionary = Data.VAN_SLOTS[slot]
	var item: String = spec["item"]
	if modules.has(slot):
		return false
	var need := _needs_met(slot)
	if need != "":
		Game.notify("Fit the %s first" % Data.VAN_SLOTS[need]["name"].to_lower())
		return false
	if Game.equipped() != item:
		Game.notify("Carry a %s in your hands to fit it here" % Data.item_name(item))
		return false
	if not _toolkit_ok(slot):
		Game.notify("You need a Toolkit in hand or lying within reach")
		return false
	Game.remove_item(item, 1)
	modules[slot] = true
	match slot:
		"engine":
			parts["engine"] = maxf(parts["engine"], 45.0)
		"water_tank":
			water = minf(water, water_capacity())
	Audio.play_at("hammer", global_position, -4.0, 1.1)
	Game.notify("%s fitted" % Data.item_name(item))
	_apply_modules()
	Game._changed()
	return true

func remove_module(slot: String) -> bool:
	if not modules.has(slot):
		return false
	var item: String = Data.VAN_SLOTS[slot]["item"]
	if slot in FIXED:
		Game.notify("The %s is part of the van now" % Data.VAN_SLOTS[slot]["name"].to_lower())
		return false
	for other in modules:
		if slot in Data.VAN_SLOTS.get(other, {}).get("needs", []):
			Game.notify("Take out the %s first" % Data.VAN_SLOTS[other]["name"].to_lower())
			return false
	if Game.space_for(item) <= 0:
		Game.notify("You need a free hand")
		return false
	if driver != 0 and slot in ["seat_driver", "steering", "engine"]:
		Game.notify("Not while someone is driving")
		return false
	modules.erase(slot)
	module_xf.erase(slot)
	if slot == "engine" and engine_on:
		stop_engine()
	Game.add_item(item, 1, true)
	for i in range(Game.slots.size()):
		if Game.slots[i]["id"] == item:
			Game.select_slot(i)
			break
	Audio.play_at("click", global_position, -2.0, 0.7)
	Game.notify("You took out the %s" % Data.item_name(item))
	_apply_modules()
	return true

## The module slot a hotspot belongs to (for [G] removal), or "".
func slot_for(part: Node) -> String:
	var a: String = part.action
	if a.begins_with("mount:"):
		return a.substr(6)
	if part.has_meta("slot"):
		return str(part.get_meta("slot"))
	if a == "door" and modules.has("door"):
		return "door"
	if a == "hood" and modules.has("engine"):
		return "engine"
	return ""

## What still has to go in before the van will drive.
func missing_for_drive() -> Array:
	var out := []
	for slot in Data.VAN_SLOTS:
		if Data.VAN_SLOTS[slot].get("drive", false) and not modules.has(slot):
			out.append(Data.VAN_SLOTS[slot]["name"])
	if missing.has("battery"):
		out.append("Battery")
	var bare := Mounts.missing_count(self)
	if bare > 0:
		out.append("%d wheel%s" % [bare, "s" if bare > 1 else ""])
	return out

func _set_radio(on: bool) -> void:
	radio_on = on
	if _radio_audio == null:
		return
	if on:
		_radio_audio.stream = Audio.stream("radio_%d" % radio_station, true)
		_radio_audio.play(randf() * 20.0)
	else:
		_radio_audio.stop()

## Burner spots (global) while the stove is lit: food set on them cooks.
func heat_spots() -> Array:
	var out := []
	if stove_on and modules.has("stove"):
		var kx := -W * 0.5 + 0.42
		var off := _slot_offset("stove")
		for p in [Vector2(-0.12, 0.95), Vector2(0.12, 0.95), Vector2(-0.12, 1.25), Vector2(0.12, 1.25)]:
			out.append(to_global(off * Vector3(kx + p.x, FLOOR_Y + 0.97, p.y)))
	return out

func shelter_bonus() -> float:
	return 2.0 + (3.0 if modules.has("door") and not door_open else 0.0) + (4.0 if modules.has("walls") else 0.0)

## The stripped van a new game starts with.
func _starter_state() -> void:
	modules = {}
	module_xf = {}
	wheel_kind = {}
	missing = {"battery": true, "wheel0": true, "wheel1": true, "wheel2": true, "wheel3": true}
	parts = {"engine": 0.0, "tires": 40.0, "battery": 0.0, "body": 45.0}
	fuel = 6.0
	water = 0.0
	battery = 0.0
	paint = Data.PRIMER

## Older saves had a fully fitted motorhome: keep it that way.
func _all_modules() -> Dictionary:
	var d := {}
	for slot in Data.VAN_SLOTS:
		if slot in ["solar", "bullbar", "heater", "big_tank", "engine_tune", "water_tank"]:
			continue
		d[slot] = true
	return d

## Kept for older callers: a new game's supplies now lie around the van (see world.gd).
func stock_starter_supplies() -> void:
	pass

func _stock(id: String, n: int, lp: Vector3, yaw := 0.0) -> void:
	var bb: AABB = Items.display_bounds(id)
	var xf := global_transform * Transform3D(Basis(Vector3.UP, yaw), lp - Vector3(0, bb.position.y, 0))
	Game.place_item(id, n, xf, self)

## Older saves kept the fridge/cabinet as item lists: put those items on the shelves.
func _spill_legacy() -> void:
	var spots := {"fridge": [Vector3(-W * 0.5 + 0.44, FLOOR_Y + 0.52, -0.67), Vector3(-W * 0.5 + 0.44, FLOOR_Y + 0.97, -0.67), Vector3(-W * 0.5 + 0.44, FLOOR_Y + 1.37, -0.67)],
		"cabinet": [Vector3(-W * 0.5 + 0.38, FLOOR_Y + 0.04, -1.45), Vector3(-W * 0.5 + 0.38, FLOOR_Y + 0.52, -1.45)]}
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

# ------------------------------------------------------------------ state
func fuel_capacity() -> float:
	return 140.0 if upgrades.has("big_tank") else 80.0

func water_capacity() -> float:
	return 60.0 if modules.has("water_tank") else 0.0

func save_state() -> Dictionary:
	return {"xform": [Game.arr(global_position), [rotation.x, rotation.y, rotation.z]], "fuel": fuel, "water": water,
		"battery": battery, "parts": parts, "upgrades": upgrades, "paint": paint, "fridge": fridge,
		"cabinet": cabinet, "pots": pots, "odometer": odometer, "missing": missing, "attached": attached, "cargo": _cargo_records(),
		"modules": modules, "module_xf": module_xf, "wheel_kind": wheel_kind, "radio_station": radio_station, "door_open": door_open}

func apply_state(s: Dictionary) -> void:
	if s.is_empty():
		_starter_state()
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
	if s.has("modules"):
		modules = s["modules"].duplicate()
		module_xf = s.get("module_xf", {}).duplicate(true)
		wheel_kind = s.get("wheel_kind", {}).duplicate()
	else:
		modules = _all_modules()
		var old: Dictionary = s.get("upgrades", {})
		for u in old:
			if Data.VAN_SLOTS.has(u):
				modules[u] = true
		if old.has("offroad_tires"):
			for i in range(4):
				wheel_kind["wheel%d" % i] = "offroad_tire"
		modules["water_tank"] = true
	paint = int(s.get("paint", 0))
	radio_station = int(s.get("radio_station", 0))
	door_open = bool(s.get("door_open", false))
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
	if _body_mat:
		var primer := paint == Data.PRIMER
		_body_mat.albedo_texture = Lib.tex("primer" if primer else "rv_paint")
		_body_mat.albedo_color = Color.WHITE if primer else c.lerp(Color.WHITE, 0.55)
		_body_mat.uv1_scale = Vector3.ONE * (0.6 if primer else 0.35)
	_apply_modules()
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
	if not modules.has("engine"):
		Game.notify("There's no engine. Lower an Engine Block in at the hood.")
		return
	if fuel <= 0.1:
		Game.notify("Out of fuel! Pour a fuel can in at the fuel cap.")
		return
	if missing.has("battery"):
		Game.notify("There's no battery fitted. Carry a Car Battery to the battery tray.")
		return
	if battery < 5.0 or parts["battery"] < 5.0:
		Game.notify("The battery is dead. Pull it out of its tray and fit a Car Battery (or wait for the solar panel).")
		return
	if parts["engine"] <= 1.0:
		Game.notify("The engine is wrecked. Rebuild it with Engine Parts at the hood.")
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
			Game.notify("The van was set back on its wheels")
	steering = _steer
	_throttle = throttle
	var sw := get_node_or_null("Interior/Mod_steering/SteeringWheel")
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
	if not (modules.has("headlight_l") or modules.has("headlight_r")):
		Game.notify("There are no headlights fitted")
		return
	headlights = not headlights
	_update_lights()
	Audio.play("click", -4.0)

func _update_lights() -> void:
	for s in _head_spots:
		s.visible = headlights
	for f in _flames:
		f.visible = stove_on
	for m in _head_mats:
		m.emission_energy_multiplier = 3.0 if headlights else 0.0
	_interior_light.visible = interior_lights

func is_inside(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < W * 0.5 and l.z > REAR_Z and l.z < FRONT_Z and l.y > FLOOR_Y - 0.5 and l.y < ROOF_Y

## Slide the side door open (out and back along its rail) or shut. An open or missing door
## leaves the doorway clear to walk through.
func set_door(open: bool, animate := true) -> void:
	door_open = open and modules.has("door")
	if _door_shape:
		_door_shape.disabled = not modules.has("door") or door_open
	if _door_panel == null:
		return
	var target := _door_home + (Vector3(0.1, 0, -(DOOR_Z1 - DOOR_Z0) + 0.1) if door_open else Vector3.ZERO)
	if _door_tween:
		_door_tween.kill()
		_door_tween = null
	if not animate:
		_door_panel.position = target
		return
	var out_x := _door_home.x + 0.1
	_door_tween = create_tween()
	_door_tween.tween_property(_door_panel, "position", Vector3(out_x, _door_home.y, _door_panel.position.z), 0.12)
	_door_tween.tween_property(_door_panel, "position", Vector3(out_x, _door_home.y, target.z), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_door_tween.tween_property(_door_panel, "position", target, 0.12)
	Audio.play_at("door", to_global(Vector3(W * 0.5, FLOOR_Y + 1.0, (DOOR_Z0 + DOOR_Z1) * 0.5)), -2.0, 0.8 if door_open else 1.0)

# ------------------------------------------------------------------ interaction
const COOKABLE := ["raw_meat", "raw_fish", "mushroom", "potato", "water_dirty", "coffee_beans", "water_clean", "tomato", "instant_noodles"]

func prompt_for(action: String) -> String:
	var held := Game.equipped()
	if action.begins_with("mount:"):
		return mount_prompt(action.substr(6))
	if action.begins_with("wheel"):
		return Mounts.prompt(self, action)
	var take := "   [G] Take it out" if held == "" else ""
	match action:
		"drive":
			if driver != 0:
				return "Someone is driving"
			if not modules.has("steering"):
				return "Driver's seat — there's no steering wheel yet" + take
			return "[E] Drive" + take
		"passenger": return "[E] Sit in passenger seat" + take
		"stove":
			if held in COOKABLE:
				return "[E] Set the %s on a burner" % Data.item_name(held)
			return "[E] %s the stove%s" % ["Turn off" if stove_on else "Light", take]
		"sink":
			if water_capacity() <= 0.0:
				return "Sink — no water tank fitted under the van" + take
			if held == "bottle_empty":
				return "[E] Fill the bottle (tank %d/%d L)" % [int(water), int(water_capacity())]
			if held in ["water_clean", "water_dirty"]:
				return "[E] Pour the water into the tank (%d/%d L)" % [int(water), int(water_capacity())]
			return "[E] Drink from the tap (tank %d/%d L)%s" % [int(water), int(water_capacity()), take]
		"coffee":
			if held == "coffee_beans":
				return "[E] Brew coffee (uses 1 L from the tank)"
			return "Coffee maker — hold Coffee Beans to brew%s" % take
		"radio":
			return "[E] Radio %s%s" % ["next station / off" if radio_on else "on", take]
		"fridge", "cabinet", "overhead":
			var nm: String = {"fridge": "fridge", "cabinet": "cupboard", "overhead": "overhead cabinet"}[action]
			return "[E] %s %s%s" % ["Close" if _doors[action]["open"] else "Open", nm, take]
		"battery":
			return Mounts.prompt(self, action)
		"bed": return "[E] Sleep in bed" + take
		"toilet": return "[E] Use toilet" + take
		"lights":
			if not modules.has("light"):
				return "Light switch — no ceiling light fitted"
			return "[E] Interior lights %s" % ("off" if interior_lights else "on")
		"door":
			if not modules.has("door"):
				return ""
			return "[E] %s the sliding door%s" % ["Close" if door_open else "Open", take]
		"hood":
			if not modules.has("engine"):
				if held == "engine_block":
					return "[E] Lower the Engine Block in%s" % ("" if _toolkit_ok("engine") else "  (needs a Toolkit in hand or within reach)")
				return "Empty engine bay — carry an Engine Block here.  [E] Check what the van still needs"
			if held == "tune_kit":
				return mount_prompt("engine_tune") if not modules.has("engine_tune") else "The engine is already tuned"
			if held == "paint_can":
				return "[E] Spray-paint the van"
			var mp := Mounts.prompt(self, "hood")
			return mp if mp != "" else "[E] Check the van over%s" % ("   [G] Hoist the engine out" if held == "" else "")
		"fuel":
			if held == "fuel_can":
				return "[E] Pour in the fuel (%d/%d L)" % [int(fuel), int(fuel_capacity())]
			return "Fuel cap (%d/%d L) — carry a full Fuel Can here" % [int(fuel), int(fuel_capacity())]
	return ""

func do_action(action: String, player: Node) -> void:
	var held := Game.equipped()
	if action.begins_with("mount:"):
		install_module(action.substr(6))
		return
	if action == "battery" or action.begins_with("wheel") or (action == "hood" and modules.has("engine") and held in ["engine_parts", "scrap", "duct_tape"]):
		if Mounts.act(self, action):
			return
	match action:
		"drive":
			if driver == 0:
				if not modules.has("steering"):
					Game.notify("There's no steering wheel. Fit one to the column first.")
					return
				player.enter_vehicle(self, true)
		"passenger":
			player.enter_vehicle(self, false)
		"stove":
			if held in COOKABLE:
				_set_on_burner(player)
				return
			if not stove_on and battery < 1.0:
				Game.notify("The igniter needs battery power")
				return
			stove_on = not stove_on
			_update_lights()
			Audio.play_at("click", global_position, -4.0, 0.8)
			Game.notify("Stove lit — set food on the burners and it cooks by itself" if stove_on else "Stove off")
		"sink":
			_use_sink()
		"coffee":
			if held != "coffee_beans":
				Game.notify("Hold Coffee Beans to brew coffee")
			elif water < 1.0:
				Game.notify("The water tank is empty")
			else:
				Game.remove_item("coffee_beans", 1)
				water -= 1.0
				Game.add_item("coffee", 1)
				Audio.play("pickup")
		"radio":
			if not radio_on:
				_set_radio(true)
			elif radio_station < 2:
				radio_station += 1
				_set_radio(true)
			else:
				radio_station = 0
				_set_radio(false)
			Audio.play("click", -6.0)
		"fridge", "cabinet", "overhead":
			_toggle_door(action)
		"bed":
			Game.world.sleep(player.global_position)
		"toilet":
			Game.notify("Much better.")
			Game.stats["water"] = maxf(Game.stats["water"] - 5.0, 0.0)
			Audio.play_at("splash", global_position, -6.0)
		"lights":
			if not modules.has("light"):
				Game.notify("There's no ceiling light to switch on")
				return
			interior_lights = not interior_lights and battery > 0.0
			_update_lights()
			Audio.play("click")
		"door":
			if modules.has("door"):
				set_door(not door_open)
		"hood":
			if not modules.has("engine"):
				if held == "engine_block":
					install_module("engine")
				else:
					_report()
				return
			if held == "tune_kit":
				install_module("engine_tune")
				return
			if held == "paint_can":
				Game.remove_item("paint_can", 1)
				paint = (paint + 1) % (Data.RV_PAINTS.size() - 1) if paint != Data.PRIMER else 0
				_apply_visuals()
				Audio.play_at("splash", global_position, -6.0, 1.8)
				Game.notify("Fresh paint!")
				return
			_report()
		"fuel":
			if held != "fuel_can":
				Game.notify("Carry a full Fuel Can here to pour it in")
			elif fuel > fuel_capacity() - 1.0:
				Game.notify("The tank is full")
			else:
				Game.remove_item("fuel_can", 1)
				Game.add_item("fuel_can_empty", 1, true)
				fuel = minf(fuel + 10.0, fuel_capacity())
				Audio.play_at("splash", global_position, -8.0, 0.7)
				Game.notify("Refueled: %d L" % int(fuel))

## Hold a cookable item at the stove: it goes onto a free burner.
func _set_on_burner(_player: Node) -> void:
	var spots := []
	var kx := -W * 0.5 + 0.42
	var off := _slot_offset("stove")
	for p in [Vector2(-0.12, 0.95), Vector2(0.12, 0.95), Vector2(-0.12, 1.25), Vector2(0.12, 1.25)]:
		spots.append(off * Vector3(kx + p.x, FLOOR_Y + 0.98, p.y))
	var cargo := get_node("Cargo")
	for lp in spots:
		var busy := false
		for it in cargo.get_children():
			if it.is_in_group("world_item") and Vector2(it.position.x - lp.x, it.position.z - lp.z).length() < 0.1:
				busy = true
				break
		if busy:
			continue
		var s := Game.take_held()
		var bb: AABB = Items.display_bounds(s["id"])
		Game.place_item(s["id"], int(s["n"]), global_transform * Transform3D(Basis.IDENTITY, lp - Vector3(0, bb.position.y, 0)), self)
		Audio.play_at("pickup", global_position, -8.0, 0.8)
		if not stove_on:
			Game.notify("Light the stove [E] with an empty hand to start cooking")
		return
	Game.notify("All four burners are taken")

func _use_sink() -> void:
	var held := Game.equipped()
	if water_capacity() <= 0.0:
		Game.notify("No water tank is fitted under the van")
		return
	if held == "bottle_empty":
		if water < 1.0:
			Game.notify("The tank is empty")
			return
		water -= 1.0
		Game.remove_item("bottle_empty", 1)
		Game.add_item("water_clean", 1, true)
		Audio.play_at("splash", global_position, -10.0, 1.4)
		Game.notify("Filled a bottle with clean water")
	elif held in ["water_clean", "water_dirty"]:
		if water > water_capacity() - 1.0:
			Game.notify("The tank is full")
			return
		Game.remove_item(held, 1)
		Game.add_item("bottle_empty", 1, true)
		water += 1.0
		Audio.play_at("splash", global_position, -10.0, 0.9)
		Game.notify("Poured into the tank%s (%d L)" % [" through the filter" if held == "water_dirty" else "", int(water)])
	else:
		if water < 1.0:
			Game.notify("The tank is empty")
			return
		water -= 1.0
		Game.stats["water"] = minf(Game.stats["water"] + 30.0, 100.0)
		Audio.play("eat")

func _report() -> void:
	var need := missing_for_drive()
	var lines: Array[String] = []
	if need.is_empty():
		lines.append("Ready to drive. Engine %d%% · Tires %d%% · Body %d%% · Battery %d%% · Fuel %d L" % [int(parts["engine"]), int(parts["tires"]), int(parts["body"]), int(battery), int(fuel)])
	else:
		lines.append("To drive, the van still needs: " + ", ".join(need))
	var interior := 0
	for slot in Data.VAN_SLOTS:
		if modules.has(slot):
			interior += 1
	lines.append("%d of %d modules fitted. Hold a part to see where it goes; furniture goes anywhere on the floor." % [interior, Data.VAN_SLOTS.size()])
	for l in lines:
		Game.notify(l)

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
	return "Van"

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
