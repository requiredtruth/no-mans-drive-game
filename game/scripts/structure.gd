extends StaticBody3D
## A player-built (or world-placed) structure: house pieces, campfire, tent, storage, planter...

const Data = preload("res://scripts/data.gd")
const GRID := 3.0

var id := ""
var type := ""
var data := {}
var persistent := true
var save_cb: Callable

var _fire: Node3D
var _fire_light: OmniLight3D
var _fire_audio: AudioStreamPlayer3D
var _door_pivot: Node3D
var _plant: Node3D
var _lamp: OmniLight3D
var _water_vis: MeshInstance3D

func setup(p_id: String, rec: Dictionary) -> void:
	id = p_id
	type = rec["type"]
	data = rec.get("data", {})
	position = Game.v3(rec["pos"])
	rotation.y = float(rec.get("rot", 0.0))
	collision_layer = 1
	add_to_group("structure")
	if type in ["roof", "roof_slope", "floor"]:
		add_to_group("roof")
	_build()

func record() -> Dictionary:
	return Game.structures.get(id, {})

func _save_data() -> void:
	if save_cb.is_valid():
		save_cb.call(data)
	if persistent and Game.structures.has(id):
		Game.structures[id]["data"] = data
		Net.sync_structure_data(id, data)

func remote_data(d: Dictionary) -> void:
	data = d
	_refresh()

# ------------------------------------------------------------------ visuals
func _col(pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	cs.rotation = rot
	add_child(cs)
	return cs

func _solid(pos: Vector3, size: Vector3, m: Material, rot := Vector3.ZERO) -> void:
	Lib.box(self, pos, size, m, false, rot)
	_col(pos, size, rot)

func _wall_with_hole(m: Material, hole_w: float, hole_h: float, hole_y: float, h := GRID, t := 0.2) -> void:
	var side := (GRID - hole_w) * 0.5
	_solid(Vector3(-(hole_w + side) * 0.5, h * 0.5, 0), Vector3(side, h, t), m)
	_solid(Vector3((hole_w + side) * 0.5, h * 0.5, 0), Vector3(side, h, t), m)
	var top := h - (hole_y + hole_h)
	if top > 0.01:
		_solid(Vector3(0, hole_y + hole_h + top * 0.5, 0), Vector3(hole_w, top, t), m)
	if hole_y > 0.01:
		_solid(Vector3(0, hole_y * 0.5, 0), Vector3(hole_w, hole_y, t), m)

func _build() -> void:
	var planks := Lib.mat("planks", Color.WHITE, 0.33)
	var dark := Lib.mat("planks", Color(0.7, 0.62, 0.55), 0.33)
	var logs := Lib.mat("logs", Color.WHITE, 0.333)
	var shingle := Lib.mat("shingles", Color.WHITE, 0.4)
	var stone := Lib.mat("rock", Color(0.92, 0.9, 0.86), 0.7)
	var trim := Lib.mat("planks", Color(0.5, 0.4, 0.32), 1.0)
	match type:
		"foundation":
			var depth: float = float(data.get("depth", 1.2))
			_solid(Vector3(0, -depth * 0.5, 0), Vector3(GRID, depth, GRID), stone)
			Lib.box(self, Vector3(0, 0.01, 0), Vector3(GRID - 0.04, 0.02, GRID - 0.04), planks)
		"floor":
			_solid(Vector3(0, 0.1, 0), Vector3(GRID, 0.2, GRID), planks)
		"roof":
			_solid(Vector3(0, 0.1, 0), Vector3(GRID + 0.1, 0.2, GRID + 0.1), shingle)
		"roof_slope":
			var ang := atan2(1.5, GRID)
			var length := sqrt(GRID * GRID + 2.25) + 0.1
			_solid(Vector3(0, 0.75, 0), Vector3(GRID + 0.1, 0.2, length), shingle, Vector3(ang, 0, 0))
			# gable triangles approximated with stepped boards
			for s in [-1.0, 1.0]:
				for k in range(3):
					var hh := 1.5 * (1.0 - k / 3.0)
					Lib.box(self, Vector3(s * (GRID * 0.5 - 0.05), hh * 0.5, -GRID * 0.5 + 0.5 + k * 1.0), Vector3(0.1, hh, 1.0), logs)
		"wall":
			_solid(Vector3(0, GRID * 0.5, 0), Vector3(GRID, GRID, 0.24), logs)
			for x in [-GRID * 0.5, GRID * 0.5]:
				Lib.box(self, Vector3(x, GRID * 0.5, 0), Vector3(0.26, GRID, 0.3), trim)
		"window":
			_wall_with_hole(logs, 1.3, 1.1, 1.1)
			for y in [1.1, 2.2]:
				Lib.box(self, Vector3(0, y, 0), Vector3(1.45, 0.08, 0.3), trim)
			for x in [-0.68, 0.68]:
				Lib.box(self, Vector3(x, 1.65, 0), Vector3(0.08, 1.2, 0.3), trim)
			Lib.box(self, Vector3(0, 1.65, 0), Vector3(0.05, 1.1, 0.06), trim)
			Lib.box(self, Vector3(0, 1.65, 0), Vector3(1.3, 0.05, 0.06), trim)
			var g := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.3, 1.1, 0.04)
			g.mesh = bm
			g.material_override = Lib.glass_mat()
			g.position = Vector3(0, 1.65, 0)
			add_child(g)
			_col(Vector3(0, 1.65, 0), Vector3(1.3, 1.1, 0.06))
			Lib.box(self, Vector3(0, 1.1, 0.12), Vector3(1.5, 0.08, 0.2), dark)
		"doorway":
			_wall_with_hole(logs, 1.2, 2.3, 0.0)
			for x in [-0.64, 0.64]:
				Lib.box(self, Vector3(x, 1.15, 0), Vector3(0.08, 2.3, 0.3), trim)
			Lib.box(self, Vector3(0, 2.34, 0), Vector3(1.36, 0.1, 0.3), trim)
			_door_pivot = Node3D.new()
			_door_pivot.position = Vector3(-0.6, 0, 0)
			add_child(_door_pivot)
			var door := Lib.box(_door_pivot, Vector3(0.6, 1.15, 0), Vector3(1.18, 2.28, 0.08), dark)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(1.18, 2.28, 0.08)
			cs.shape = sh
			body.add_child(cs)
			body.set_meta("door_of", self)
			door.add_child(body)
			Lib.sphere(door, Vector3(0.45, 0.0, 0.07), 0.04, Lib.color_mat(Color("b08d3c"), 0.3, 0.8))
			_refresh()
		"stairs":
			for k in range(6):
				Lib.box(self, Vector3(0, 0.25 + k * 0.5, GRID * 0.5 - 0.25 - k * 0.5), Vector3(1.4, 0.15, 0.5), planks)
			for s in [-0.72, 0.72]:
				Lib.box(self, Vector3(s, 1.5, 0), Vector3(0.08, 0.3, 4.2), dark, false, Vector3(atan2(3.0, 3.0), 0, 0))
			_col(Vector3(0, 1.45, 0), Vector3(1.4, 0.2, 4.2), Vector3(atan2(3.0, 3.0), 0, 0))
		"fence":
			for x in [-1.4, 0.0, 1.4]:
				_solid(Vector3(x, 0.6, 0), Vector3(0.14, 1.2, 0.14), dark)
			for y in [0.45, 0.95]:
				Lib.box(self, Vector3(0, y, 0), Vector3(GRID, 0.12, 0.05), planks)
			_col(Vector3(0, 0.6, 0), Vector3(GRID, 1.2, 0.1))
		"campfire":
			_build_campfire()
		"tent":
			var canvas := Lib.mat("canvas", Color.WHITE, 0.5, false)
			canvas = canvas.duplicate()
			canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
			for s in [-1.0, 1.0]:
				Lib.box(self, Vector3(s * 0.62, 0.72, 0), Vector3(0.04, 1.75, 2.4), canvas, false, Vector3(0, 0, s * 0.62))
			Lib.box(self, Vector3(0, 0.02, 0), Vector3(2.0, 0.04, 2.4), Lib.mat("canvas", Color(0.6, 0.6, 0.6), 0.5, false))
			Lib.cyl(self, Vector3(0, 0.73, 1.2), 0.03, 0.03, 1.45, Lib.mat("bark"))
			Lib.cyl(self, Vector3(0, 0.73, -1.2), 0.03, 0.03, 1.45, Lib.mat("bark"))
			_col(Vector3(0, 0.6, 0), Vector3(1.8, 1.2, 2.4))
		"crate":
			# open-top crate: things you put in it physically sit inside and come along
			# when you carry the crate
			_solid(Vector3(0, 0.05, 0), Vector3(1.1, 0.1, 0.7), planks)
			for sx in [-1.0, 1.0]:
				_solid(Vector3(sx * 0.525, 0.4, 0), Vector3(0.05, 0.8, 0.7), planks)
				_solid(Vector3(0, 0.4, sx * 0.325), Vector3(1.0, 0.8, 0.05), planks)
				Lib.box(self, Vector3(sx * 0.53, 0.4, 0), Vector3(0.08, 0.82, 0.74), dark)
			for y in [0.06, 0.78]:
				for sz in [-1.0, 1.0]:
					Lib.box(self, Vector3(0, y, sz * 0.34), Vector3(1.12, 0.06, 0.04), dark)
			if persistent and data.has("items") and not (data["items"] as Dictionary).is_empty():
				call_deferred("_spill_legacy")
		"planter":
			_solid(Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 0.8), planks)
			Lib.box(self, Vector3(0, 0.5, 0), Vector3(1.45, 0.04, 0.65), Lib.mat("dirt", Color(0.7, 0.6, 0.5), 0.6))
			_water_vis = Lib.box(self, Vector3(0, 0.515, 0), Vector3(1.45, 0.01, 0.65), Lib.color_mat(Color(0.1, 0.12, 0.18, 0.55), 0.1))
			_plant = Node3D.new()
			_plant.position = Vector3(0, 0.52, 0)
			add_child(_plant)
			_refresh()
		"bed":
			_solid(Vector3(0, 0.25, 0), Vector3(1.1, 0.5, 2.1), dark)
			Lib.box(self, Vector3(0, 0.55, 0.05), Vector3(1.0, 0.16, 1.9), Lib.mat("canvas", Color(0.55, 0.65, 0.8), 0.6, false))
			Lib.box(self, Vector3(0, 0.66, -0.75), Vector3(0.7, 0.12, 0.35), Lib.color_mat(Color("e8e4dc")))
			Lib.box(self, Vector3(0, 0.75, -1.03), Vector3(1.1, 1.0, 0.08), dark)
		"workbench":
			_solid(Vector3(0, 0.88, 0), Vector3(2.0, 0.12, 0.9), dark)
			for x in [-0.9, 0.9]:
				for z in [-0.38, 0.38]:
					Lib.box(self, Vector3(x, 0.42, z), Vector3(0.1, 0.84, 0.1), planks)
			_col(Vector3(0, 0.45, 0), Vector3(2.0, 0.9, 0.9))
			Lib.box(self, Vector3(-0.5, 0.98, 0.1), Vector3(0.4, 0.08, 0.15), Lib.mat("rust"))
			Lib.cyl(self, Vector3(0.4, 0.97, -0.1), 0.02, 0.02, 0.4, Lib.color_mat(Color("6b4a2a")), Vector3(0, 0, PI * 0.5))
			Lib.box(self, Vector3(0.6, 0.98, -0.1), Vector3(0.08, 0.1, 0.12), Lib.color_mat(Color("555555"), 0.4, 0.8))
		"rain_collector":
			_solid(Vector3(0, 0.5, 0), Vector3(0.8, 1.0, 0.8), Lib.mat("rust", Color(0.6, 0.7, 0.9)))
			var funnel := Lib.cyl(self, Vector3(0, 1.2, 0), 0.75, 0.3, 0.4, Lib.mat("canvas", Color(0.7, 0.7, 0.75), 0.5, false))
			funnel.material_override = funnel.material_override.duplicate()
			funnel.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		"lantern":
			_solid(Vector3(0, 1.0, 0), Vector3(0.12, 2.0, 0.12), dark)
			Lib.box(self, Vector3(0.3, 1.95, 0), Vector3(0.6, 0.08, 0.08), dark)
			var lantern_scene: PackedScene = load("res://assets/models/Lantern.glb")
			if lantern_scene:
				var lan: Node3D = lantern_scene.instantiate()
				lan.scale = Vector3.ONE * 0.022
				lan.position = Vector3(0.55, 1.95 - 0.55, 0)
				add_child(lan)
			_lamp = Lib.light(self, Vector3(0.55, 1.55, 0), Color(1.0, 0.75, 0.45), 1.6, 12.0)
	match type:
		"chair":
			var canvas := Lib.mat("canvas", Color(0.6, 0.8, 0.65), 1.0, false)
			for x in [-0.22, 0.22]:
				for z in [-0.2, 0.2]:
					Lib.cyl(self, Vector3(x, 0.22, z), 0.018, 0.018, 0.48, Lib.mat("metal", Color(0.4, 0.4, 0.42), 2.0, false, 0.4, 0.8), Vector3(z * 0.8, 0, -x * 0.5))
			Lib.box(self, Vector3(0, 0.45, 0), Vector3(0.5, 0.05, 0.45), canvas)
			Lib.box(self, Vector3(0, 0.75, 0.22), Vector3(0.5, 0.55, 0.04), canvas, false, Vector3(-0.15, 0, 0))
			_col(Vector3(0, 0.35, 0), Vector3(0.5, 0.7, 0.45))
		"table":
			Lib.box(self, Vector3(0, 0.76, 0), Vector3(1.4, 0.06, 0.8), planks)
			for x in [-0.62, 0.62]:
				for z in [-0.32, 0.32]:
					Lib.box(self, Vector3(x, 0.37, z), Vector3(0.07, 0.74, 0.07), dark)
			_col(Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 0.8))
		"sofa":
			var fab := Lib.mat("upholstery", Color(0.55, 0.62, 0.8), 1.2, false, 0.95)
			var frame := Lib.mat("planks", Color(0.45, 0.33, 0.24), 1.0)
			Lib.box(self, Vector3(0, 0.2, 0), Vector3(1.7, 0.26, 0.8), fab, false, Vector3.ZERO, 0.05)
			for k in range(2):
				Lib.box(self, Vector3(-0.41 + k * 0.82, 0.39, 0.04), Vector3(0.8, 0.14, 0.68), fab, false, Vector3.ZERO, 0.06)
				Lib.box(self, Vector3(-0.41 + k * 0.82, 0.66, -0.3), Vector3(0.78, 0.44, 0.16), fab, false, Vector3(-0.12, 0, 0), 0.07)
			for x in [-0.8, 0.8]:
				Lib.box(self, Vector3(x, 0.4, 0), Vector3(0.14, 0.42, 0.8), fab, false, Vector3.ZERO, 0.06)
			for x in [-0.75, 0.75]:
				for z in [-0.32, 0.32]:
					Lib.cyl(self, Vector3(x, 0.04, z), 0.025, 0.02, 0.08, frame)
			_col(Vector3(0, 0.3, 0), Vector3(1.75, 0.6, 0.8))
			_col(Vector3(0, 0.66, -0.3), Vector3(1.7, 0.5, 0.18))
		"floor_lamp":
			var brass := Lib.mat("metal", Color(0.9, 0.7, 0.4), 2.0, false, 0.3, 0.9)
			Lib.cyl(self, Vector3(0, 0.015, 0), 0.16, 0.18, 0.03, brass)
			Lib.cyl(self, Vector3(0, 0.8, 0), 0.012, 0.012, 1.55, brass)
			var shade := Lib.cyl(self, Vector3(0, 1.58, 0), 0.13, 0.22, 0.26, Lib.mat("canvas", Color(0.98, 0.92, 0.78), 1.0, false))
			shade.material_override = shade.material_override.duplicate()
			shade.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
			var bulb := Lib.sphere(self, Vector3(0, 1.52, 0), 0.04, Lib.color_mat(Color(1, 0.95, 0.8), 0.2, 0.0, Color(1.0, 0.85, 0.6), 2.0))
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_lamp = Lib.light(self, Vector3(0, 1.45, 0), Color(1.0, 0.82, 0.6), 1.3, 7.0)
			_lamp.visible = data.get("on", true)
			_col(Vector3(0, 0.85, 0), Vector3(0.36, 1.7, 0.36))
		"rug":
			Lib.box(self, Vector3(0, 0.008, 0), Vector3(1.6, 0.012, 1.1), Lib.mat("carpet", Color(0.75, 0.35, 0.28), 1.2, false, 0.95), false, Vector3.ZERO, 0.004)
			Lib.box(self, Vector3(0, 0.0145, 0), Vector3(1.3, 0.002, 0.8), Lib.mat("plaid", Color(0.9, 0.75, 0.55), 2.0, false, 0.95))
			_col(Vector3(0, 0.01, 0), Vector3(1.6, 0.02, 1.1))
		"potted_plant":
			var pot := Lib.cyl(self, Vector3(0, 0.15, 0), 0.17, 0.13, 0.3, Lib.mat("brick", Color(0.85, 0.5, 0.35), 2.0, false, 0.8))
			pot.name = "Pot"
			Lib.cyl(self, Vector3(0, 0.29, 0), 0.155, 0.155, 0.02, Lib.color_mat(Color(0.2, 0.14, 0.09), 0.95))
			var leafm := Lib.color_mat(Color(0.22, 0.5, 0.2), 0.55)
			for k in range(9):
				var a := TAU * k / 9.0 + 0.3
				var lean := 0.35 + (k % 3) * 0.15
				var leaf := Lib.sphere(self, Vector3(cos(a) * 0.12, 0.5 + (k % 3) * 0.12, sin(a) * 0.12), 0.1, leafm, Vector3(0.5, 1.6, 0.18))
				leaf.rotation = Vector3(0, -a, lean)
			_col(Vector3(0, 0.35, 0), Vector3(0.36, 0.7, 0.36))
		"shelf_unit":
			var wd := Lib.mat("planks", Color(0.85, 0.7, 0.5), 1.5)
			for x in [-0.48, 0.48]:
				Lib.box(self, Vector3(x, 0.8, 0), Vector3(0.03, 1.6, 0.36), wd)
			Lib.box(self, Vector3(0, 0.8, -0.17), Vector3(0.96, 1.6, 0.015), wd)
			for y in [0.05, 0.45, 0.85, 1.25, 1.585]:
				_solid(Vector3(0, y, 0), Vector3(0.96, 0.03, 0.36), wd)
			_col(Vector3(-0.48, 0.8, 0), Vector3(0.03, 1.6, 0.36))
			_col(Vector3(0.48, 0.8, 0), Vector3(0.03, 1.6, 0.36))
			_col(Vector3(0, 0.8, -0.17), Vector3(0.96, 1.6, 0.015))
	if type in ["campfire", "tent", "crate", "planter", "bed", "workbench", "rain_collector", "lantern", "chair", "table",
			"sofa", "floor_lamp", "rug", "potted_plant", "shelf_unit"]:
		add_to_group("placeable")

func _build_campfire() -> void:
	var stone := Lib.mat("rock", Color(0.8, 0.8, 0.8), 1.0)
	for i in range(9):
		var a := TAU * i / 9.0
		var r := Lib.sphere(self, Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), 0.16, stone, Vector3(1.2, 0.7, 1.0))
		r.rotation.y = a
	var log_mat := Lib.mat("bark", Color(0.6, 0.55, 0.5), 1.5, false)
	for i in range(4):
		var a := TAU * i / 4.0 + 0.3
		Lib.cyl(self, Vector3(cos(a) * 0.15, 0.15, sin(a) * 0.15), 0.06, 0.07, 0.75, log_mat, Vector3(0.9, a, 0))
	Lib.box(self, Vector3(0, 0.02, 0), Vector3(0.8, 0.03, 0.8), Lib.color_mat(Color(0.08, 0.07, 0.06)))
	# a cooking grate over the flames: whatever sits on it cooks while the fire burns
	var grate := Lib.color_mat(Color(0.18, 0.18, 0.19), 0.5, 0.8)
	for k in range(7):
		Lib.cyl(self, Vector3(-0.3 + k * 0.1, 0.41, 0), 0.008, 0.008, 0.7, grate, Vector3(PI * 0.5, 0, 0), 6)
	for z in [-0.33, 0.33]:
		Lib.cyl(self, Vector3(0, 0.41, z), 0.012, 0.012, 0.7, grate, Vector3(0, 0, PI * 0.5), 6)
	for x in [-0.36, 0.36]:
		Lib.cyl(self, Vector3(x, 0.22, 0), 0.012, 0.012, 0.4, grate)
	_col(Vector3(0, 0.2, 0), Vector3(1.3, 0.4, 1.3))
	_fire = Node3D.new()
	add_child(_fire)
	var flames := CPUParticles3D.new()
	flames.amount = 40
	flames.lifetime = 0.8
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.18
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 2.2, 0)
	flames.initial_velocity_min = 0.3
	flames.initial_velocity_max = 0.8
	flames.scale_amount_min = 0.5
	flames.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	flames.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	grad.add_point(0.4, Color(1.0, 0.55, 0.12, 0.9))
	flames.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(0.35, 0.5)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 1))
	g2.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = g2
	fm.albedo_texture = gt
	qm.material = fm
	flames.mesh = qm
	flames.position = Vector3(0, 0.15, 0)
	_fire.add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.amount = 16
	smoke.lifetime = 4.0
	smoke.direction = Vector3.UP
	smoke.spread = 8.0
	smoke.gravity = Vector3(0.25, 0.6, 0)
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.0
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	var sgrad := Gradient.new()
	sgrad.set_color(0, Color(0.3, 0.3, 0.3, 0.35))
	sgrad.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	smoke.color_ramp = sgrad
	var sq := QuadMesh.new()
	sq.size = Vector2(0.8, 0.8)
	var sm := fm.duplicate()
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	sq.material = sm
	smoke.mesh = sq
	smoke.position = Vector3(0, 0.8, 0)
	_fire.add_child(smoke)
	_fire_light = Lib.light(self, Vector3(0, 0.7, 0), Color(1.0, 0.6, 0.3), 2.6, 11.0, false)
	_fire_audio = Audio.looping_3d("fire_loop", self, -4.0)
	if not data.has("fuel"):
		data["fuel"] = 240.0
	_refresh()

func _refresh() -> void:
	match type:
		"campfire":
			var lit: bool = float(data.get("fuel", 0.0)) > 0.0
			_fire.visible = lit
			_fire_light.visible = lit
			if lit and not _fire_audio.playing:
				_fire_audio.play()
			elif not lit:
				_fire_audio.stop()
		"doorway":
			var open: bool = data.get("open", false)
			_door_pivot.rotation.y = -1.6 if open else 0.0
		"floor_lamp":
			if _lamp:
				_lamp.visible = data.get("on", true)
		"planter":
			for c in _plant.get_children():
				c.queue_free()
			_water_vis.visible = float(data.get("water", 0.0)) > 0.05
			var crop: String = data.get("crop", "")
			if crop == "":
				return
			var g: float = clampf(float(data.get("growth", 0.0)), 0.0, 1.0)
			for k in range(3):
				var x := -0.5 + k * 0.5
				var sprout := MeshInstance3D.new()
				sprout.mesh = Lib.mesh("bush_berry") if crop == "tomato" else Lib.mesh("bush_fiber")
				var s := lerpf(0.1, 0.55 if crop != "coffee_beans" else 0.7, g)
				sprout.scale = Vector3(s, s, s)
				sprout.position = Vector3(x, 0, 0)
				_plant.add_child(sprout)
				if g >= 1.0:
					var fruit_col := Color("d6402f") if crop == "tomato" else (Color("b03a2a") if crop == "coffee_beans" else Color("b89060"))
					for f in range(3):
						Lib.sphere(_plant, Vector3(x + randf_range(-0.12, 0.12), 0.25 + f * 0.08, randf_range(-0.12, 0.12)), 0.05, Lib.color_mat(fruit_col, 0.4))

# ------------------------------------------------------------------ simulation
func _process(delta: float) -> void:
	match type:
		"campfire":
			var fuel: float = float(data.get("fuel", 0.0))
			if fuel > 0.0:
				var rate := 1.0
				if Game.weather == "rain" and not is_sheltered():
					rate = 2.5
				fuel = maxf(fuel - delta * rate, 0.0)
				data["fuel"] = fuel
				_fire_light.light_energy = 2.4 + sin(Time.get_ticks_msec() * 0.013) * 0.35 + randf() * 0.25
				if fuel <= 0.0:
					_refresh()
					_save_data()
		"lantern":
			var night := Game.time_of_day < 6.5 or Game.time_of_day > 19.0
			_lamp.visible = night

## Called by the world once per in-game hour.
func game_hour() -> void:
	match type:
		"planter":
			var crop: String = data.get("crop", "")
			var water: float = float(data.get("water", 0.0))
			if Game.weather == "rain":
				water = 1.0
			if crop != "" and water > 0.0 and float(data.get("growth", 0.0)) < 1.0:
				data["growth"] = minf(float(data.get("growth", 0.0)) + 1.0 / 30.0, 1.0)
			data["water"] = maxf(water - 1.0 / 20.0, 0.0)
			_refresh()
			_save_data()
		"rain_collector":
			if Game.weather == "rain":
				data["water"] = mini(int(data.get("water", 0)) + 1, 6)
				_save_data()

func is_sheltered() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), global_position + Vector3(0, 20, 0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return not hit.is_empty()

# ------------------------------------------------------------------ interaction
func get_prompt() -> String:
	var p := _prompt()
	if is_in_group("placeable") and type not in ["chair", "table", "sofa", "floor_lamp", "rug", "potted_plant", "shelf_unit"] and p != "":
		p += "   [G] Pick up"
	return p

func _prompt() -> String:
	match type:
		"campfire":
			var fuel: float = float(data.get("fuel", 0.0))
			var held := Game.equipped()
			if fuel > 0.0:
				if held == "wood":
					return "[E] Add wood  (%d min of fuel)" % int(fuel / 60.0 + 1)
				if _cookable(held):
					return "[E] Set the %s on the grill" % Data.item_name(held)
				return "Campfire (%d min of fuel) — hold food or dirty water and [E] to set it on the grill" % int(fuel / 60.0 + 1)
			return "[E] Light campfire (1 Wood)"
		"doorway":
			return "[E] %s door" % ("Close" if data.get("open", false) else "Open")
		"tent", "bed":
			return "[E] Sleep"
		"crate":
			return "Storage crate — put things inside with [G]"
		"planter":
			var crop: String = data.get("crop", "")
			if crop == "":
				return "[E] Plant seeds"
			if float(data.get("growth", 0.0)) >= 1.0:
				return "[E] Harvest %s" % Data.item_name(crop)
			return "[E] Water plants  (%s %d%%, water %d%%)" % [Data.item_name(crop), int(float(data.get("growth", 0.0)) * 100), int(float(data.get("water", 0.0)) * 100)]
		"workbench":
			return _bench_prompt()
		"rain_collector":
			if Game.equipped() == "bottle_empty":
				return "[E] Fill the bottle (%d L collected)" % int(data.get("water", 0))
			return "Rain collector (%d L) — hold an Empty Bottle to fill it" % int(data.get("water", 0))
		"chair":
			return "[E] Sit and rest   [G] Pick up"
		"table":
			return "Wooden table   [G] Pick up"
		"sofa":
			return "[E] Sit down and rest   [G] Pick up"
		"floor_lamp":
			return "[E] Turn the lamp %s   [G] Pick up" % ("off" if data.get("on", true) else "on")
		"rug":
			return "Rug   [G] Pick up"
		"potted_plant":
			return "Potted plant   [G] Pick up"
		"shelf_unit":
			return "Shelf unit: set things on the shelves   [G] Pick up"
	return ""

func interact(player: Node) -> void:
	match type:
		"campfire":
			if float(data.get("fuel", 0.0)) <= 0.0:
				if Game.remove_item("wood", 1):
					data["fuel"] = 240.0
					_refresh()
					_save_data()
					Audio.play_at("chop", global_position)
				else:
					Game.notify("You need wood to light the fire")
			elif Game.equipped() == "wood":
				add_fuel()
				Audio.play_at("chop", global_position, -6.0, 1.3)
			elif _cookable(Game.equipped()):
				_set_on_grill()
			else:
				Game.notify("Hold food (raw meat, fish, potatoes, mushrooms) or dirty water and press [E] to set it on the grill. It cooks by itself.")
		"doorway":
			data["open"] = not data.get("open", false)
			Audio.play_at("door", global_position)
			_refresh()
			_save_data()
		"tent", "bed":
			Game.world.sleep(global_position + Vector3(0, 0.5, 0))
		"crate":
			Game.notify("Hold something and press [G] to put it in the crate. Pick the crate up with [G] (empty hands) to carry everything at once.")
		"planter":
			_planter_interact()
		"workbench":
			assemble()
		"chair", "sofa":
			Game.stats["energy"] = minf(Game.stats["energy"] + (5.0 if type == "chair" else 8.0), 100.0)
			Game.notify("You rest for a moment")
		"floor_lamp":
			data["on"] = not data.get("on", true)
			Audio.play_at("click", global_position, -6.0)
			_refresh()
			_save_data()
		"rain_collector":
			var w := int(data.get("water", 0))
			if Game.equipped() != "bottle_empty":
				Game.notify("Hold an Empty Bottle to fill it here")
			elif w > 0:
				Game.remove_item("bottle_empty", 1)
				Game.add_item("water_clean", 1, true)
				data["water"] = w - 1
				_save_data()
				Audio.play_at("splash", global_position, -10.0, 1.4)
			else:
				Game.notify("The collector is empty. Wait for rain.")

## Crates from older saves stored an item list: lay those items inside for real.
func _spill_legacy() -> void:
	var items: Dictionary = data.get("items", {})
	var i := 0
	for k in items:
		var n := int(items[k])
		while n > 0:
			var lim := Data.stack(k)
			var take := mini(n, lim)
			var lp := Vector3(-0.3 + (i % 3) * 0.3, 0.12 + (i / 6) * 0.2, -0.13 + ((i / 3) % 2) * 0.26)
			Game.place_item(k, take, global_transform * Transform3D(Basis.IDENTITY, lp))
			n -= take
			i += 1
	data.erase("items")
	_save_data()

func add_fuel() -> bool:
	if not Game.remove_item("wood", 1):
		Game.notify("You need wood")
		return false
	data["fuel"] = minf(float(data.get("fuel", 0.0)) + 180.0, 1200.0)
	_refresh()
	_save_data()
	return true

func _planter_interact() -> void:
	var crop: String = data.get("crop", "")
	if crop == "":
		for seed_id in ["seeds_tomato", "seeds_potato", "seeds_coffee"]:
			if Game.count(seed_id) > 0:
				Game.remove_item(seed_id, 1)
				data["crop"] = Data.ITEMS[seed_id]["grows"]
				data["growth"] = 0.0
				Game.notify("Planted %s" % Data.item_name(seed_id))
				_refresh()
				_save_data()
				return
		Game.notify("You have no seeds")
		return
	if float(data.get("growth", 0.0)) >= 1.0:
		var n := randi_range(3, 5)
		Game.add_item(crop, n)
		if randf() < 0.6:
			var seed_for := {"tomato": "seeds_tomato", "potato": "seeds_potato", "coffee_beans": "seeds_coffee"}
			Game.add_item(seed_for[crop], randi_range(1, 2))
		data["crop"] = ""
		data["growth"] = 0.0
		Audio.play("pickup")
		_refresh()
		_save_data()
		return
	for w in ["water_clean", "water_dirty"]:
		if Game.count(w) > 0:
			var in_hand := Game.carried(w) > 0
			Game.remove_item(w, 1)
			if in_hand:
				Game.add_item("bottle_empty", 1, true)
			data["water"] = 1.0
			Audio.play_at("splash", global_position, -8.0)
			Game.notify("Watered the planter")
			_refresh()
			_save_data()
			return
	Game.notify("You need water to water the plants")

func warmth_radius() -> float:
	if type == "campfire" and float(data.get("fuel", 0.0)) > 0.0:
		return 7.0
	return 0.0

# ------------------------------------------------------------------ cooking on the campfire
func _cookable(id: String) -> bool:
	if id == "":
		return false
	for r in Data.COOKING:
		if r["cost"].has(id):
			return true
	return false

## Grill spots on top of the fire (local).
const GRILL := [Vector3(-0.2, 0.42, -0.2), Vector3(0.2, 0.42, -0.2), Vector3(-0.2, 0.42, 0.2), Vector3(0.2, 0.42, 0.2), Vector3(0.0, 0.42, 0.0)]

func _set_on_grill() -> void:
	for lp in GRILL:
		var gp: Vector3 = to_global(lp)
		var busy := false
		for it in get_tree().get_nodes_in_group("world_item"):
			if is_instance_valid(it) and Vector2(it.global_position.x - gp.x, it.global_position.z - gp.z).length() < 0.12 and absf(it.global_position.y - gp.y) < 0.4:
				busy = true
				break
		if busy:
			continue
		var s := Game.take_held()
		var bb: AABB = Items.display_bounds(s["id"])
		Game.place_item(s["id"], int(s["n"]), Transform3D(global_transform.basis, gp - Vector3(0, bb.position.y, 0)), get_meta("host") if has_meta("host") else null)
		Audio.play_at("pickup", gp, -8.0, 0.8)
		return
	Game.notify("The grill is full")

## World positions that cook what sits on them while the fire burns.
func heat_spots() -> Array:
	if type != "campfire" or float(data.get("fuel", 0.0)) <= 0.0:
		return []
	return [to_global(Vector3(0, 0.42, 0))]

# ------------------------------------------------------------------ workbench: assemble what lies on it
var _choice := 0

## Items lying on the bench top.
func bench_items() -> Array:
	var out := []
	var inv := global_transform.affine_inverse()
	for it in get_tree().get_nodes_in_group("world_item"):
		if not is_instance_valid(it) or it.is_queued_for_deletion():
			continue
		var l: Vector3 = inv * it.global_position
		if absf(l.x) < 1.08 and absf(l.z) < 0.52 and l.y > 0.8 and l.y < 1.7:
			out.append(it)
	return out

func _bench_counts(items: Array) -> Dictionary:
	var d := {}
	for it in items:
		d[it.id] = int(d.get(it.id, 0)) + int(it.amount)
	return d

## Recipes whose ingredients all lie on the bench, most specific first.
func bench_matches() -> Array:
	var have := _bench_counts(bench_items())
	var out := []
	for r in Data.RECIPES:
		var ok := true
		for k in r["cost"]:
			if int(have.get(k, 0)) < int(r["cost"][k]):
				ok = false
				break
		if ok:
			out.append(r)
	out.sort_custom(func(a, b):
		if a["cost"].size() != b["cost"].size():
			return a["cost"].size() > b["cost"].size()
		var ta := 0
		var tb := 0
		for k in a["cost"]:
			ta += int(a["cost"][k])
		for k in b["cost"]:
			tb += int(b["cost"][k])
		return ta > tb)
	return out

func _bench_prompt() -> String:
	var m := bench_matches()
	if m.is_empty():
		var n := bench_items().size()
		if n == 0:
			return "Workbench — set materials on top [G], then [E] to put them together   (Tab: recipe book)"
		return "Workbench — nothing to make from what's on it yet   (Tab: recipe book)"
	_choice = wrapi(_choice, 0, m.size())
	var r: Dictionary = m[_choice]
	var more := ("\n[R] %d other thing%s you could make" % [m.size() - 1, "s" if m.size() > 2 else ""]) if m.size() > 1 else ""
	return "[E] Make %s%s  (uses %s)%s" % [Data.item_name(r["out"]), (" ×%d" % r["n"]) if int(r["n"]) > 1 else "", Data.cost_text(r["cost"]), more]

func cycle_recipe() -> void:
	_choice += 1
	Audio.play("click", -8.0)

func assemble() -> void:
	var m := bench_matches()
	if m.is_empty():
		Game.notify("Lay the ingredients on the bench first. Press Tab for the recipe book.")
		return
	_choice = wrapi(_choice, 0, m.size())
	var r: Dictionary = m[_choice]
	var items := bench_items()
	var inv := global_transform.affine_inverse()
	items.sort_custom(func(a, b): return absf((inv * a.global_position).x) > absf((inv * b.global_position).x))
	for k in r["cost"]:
		var left := int(r["cost"][k])
		for it in items:
			if left <= 0:
				break
			if it.id != k or it.amount <= 0:
				continue
			var take := mini(int(it.amount), left)
			it.amount -= take
			left -= take
			if it.amount <= 0:
				it.queue_free()
			else:
				it.refresh_label()
	var out: String = r["out"]
	var n := int(r["n"])
	var bb: AABB = Items.display_bounds(out)
	var host = get_meta("host") if has_meta("host") else null
	if maxf(bb.size.x, bb.size.z) < 0.9 and bb.size.y < 0.8:
		var lp := Vector3(randf_range(-0.25, 0.25), 0.94 - bb.position.y + 0.005, randf_range(-0.12, 0.12))
		while n > 0:
			var k := mini(n, Data.stack(out))
			Game.place_item(out, k, global_transform * Transform3D(Basis(Vector3.UP, randf() * TAU), lp), host)
			n -= k
			lp.x += 0.2
	else:
		var front: Vector3 = to_global(Vector3(0, 0, 1.25))
		if host == null and Game.world:
			front.y = Game.world.gen.height(front.x, front.z) - bb.position.y + 0.02
		Game.place_item(out, n, Transform3D(global_transform.basis, front), host)
	Audio.play_at("hammer", global_position, -3.0)
	Game.notify("You made %s%s" % [Data.item_name(out), (" ×%d" % int(r["n"])) if int(r["n"]) > 1 else ""])
