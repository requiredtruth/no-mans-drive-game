extends Node
## Detailed procedural 3D models for every item, plus rendered inventory icons.
## Autoloaded as "Items". Tools are modelled with the grip at the origin and the
## working end pointing up (+Y); small items rest on the origin.

signal icon_ready(id: String)

var _meshes := {}
var _icons := {}
var _queue: Array[String] = []
var _vp: SubViewport
var _stage: Node3D
var _cam: Camera3D
var _busy := false

# ------------------------------------------------------------------ materials
func m(tex: String, tint := Color.WHITE, scale := 4.0, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	return Lib.mat(tex, tint, scale, false, rough, metal)

func c(col: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	return Lib.color_mat(col, rough, metal)

func steel() -> StandardMaterial3D: return m("metal", Color(0.95, 0.95, 0.97), 6.0, 0.32, 0.85)
func dark_steel() -> StandardMaterial3D: return m("metal", Color(0.28, 0.29, 0.3), 6.0, 0.45, 0.8)
func wood() -> StandardMaterial3D: return m("planks", Color(1.0, 0.86, 0.68), 7.0, 0.65)
func dark_wood() -> StandardMaterial3D: return m("planks", Color(0.62, 0.42, 0.28), 7.0, 0.55)
func leather() -> StandardMaterial3D: return m("leather", Color.WHITE, 6.0, 0.6)
func rubber() -> StandardMaterial3D: return m("rubber", Color.WHITE, 5.0, 0.9)
func paint(col: Color) -> StandardMaterial3D: return m("paint", col, 4.0, 0.45, 0.3)
func brass() -> StandardMaterial3D: return m("metal", Color(0.95, 0.72, 0.35), 8.0, 0.3, 0.9)

# ------------------------------------------------------------------ geometry helpers
func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## Surface of revolution around Y. profile: Array of Vector2(radius, y) from bottom to top.
func lathe(st: SurfaceTool, profile: Array, segs := 24, offset := Vector3.ZERO, cap_bottom := true, cap_top := true) -> void:
	for i in range(profile.size() - 1):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var slope := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		for s in range(segs):
			var t0 := TAU * s / segs
			var t1 := TAU * (s + 1) / segs
			var d0 := Vector3(cos(t0), 0, sin(t0))
			var d1 := Vector3(cos(t1), 0, sin(t1))
			var n0 := (d0 * slope.x + Vector3.UP * slope.y).normalized()
			var n1 := (d1 * slope.x + Vector3.UP * slope.y).normalized()
			var p := [offset + d0 * a.x + Vector3(0, a.y, 0), offset + d1 * a.x + Vector3(0, a.y, 0), offset + d1 * b.x + Vector3(0, b.y, 0), offset + d0 * b.x + Vector3(0, b.y, 0)]
			var u0 := float(s) / segs
			var u1 := float(s + 1) / segs
			Lib._tri(st, [p[0], p[1], p[2]], [n0, n1, n1], [Vector2(u0, a.y), Vector2(u1, a.y), Vector2(u1, b.y)])
			Lib._tri(st, [p[0], p[2], p[3]], [n0, n1, n0], [Vector2(u0, a.y), Vector2(u1, b.y), Vector2(u0, b.y)])
	if cap_bottom and profile[0].x > 0.0:
		_disc(st, offset + Vector3(0, profile[0].y, 0), profile[0].x, Vector3.DOWN, segs)
	var last: Vector2 = profile[profile.size() - 1]
	if cap_top and last.x > 0.0:
		_disc(st, offset + Vector3(0, last.y, 0), last.x, Vector3.UP, segs)

func _disc(st: SurfaceTool, center: Vector3, r: float, n: Vector3, segs: int) -> void:
	var bs := Lib._basis_for(n)
	for s in range(segs):
		var t0 := TAU * s / segs
		var t1 := TAU * (s + 1) / segs
		var p0 := center + (bs.x * cos(t0) + bs.z * sin(t0)) * r
		var p1 := center + (bs.x * cos(t1) + bs.z * sin(t1)) * r
		Lib._tri(st, [center, p0, p1], [n, n, n], [Vector2(0.5, 0.5), Vector2(0.5 + cos(t0) * 0.5, 0.5 + sin(t0) * 0.5), Vector2(0.5 + cos(t1) * 0.5, 0.5 + sin(t1) * 0.5)])

## Generic 8-corner block: bottom 4 corners then top 4 corners (counter-clockwise from -x,-z).
func hexa(st: SurfaceTool, v: Array) -> void:
	var faces := [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	var center := Vector3.ZERO
	for p in v:
		center += p
	center /= 8.0
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var cc: Vector3 = v[f[2]]
		var d: Vector3 = v[f[3]]
		var n := (b - a).cross(d - a).normalized()
		if n.dot((a + b + cc + d) * 0.25 - center) < 0.0:
			n = -n
		if n == Vector3.ZERO:
			continue
		var bs := Lib._basis_for(n)
		var uv := func(p: Vector3) -> Vector2: return Vector2(p.dot(bs.x), p.dot(bs.z)) * 4.0
		Lib._tri(st, [a, b, cc], [n, n, n], [uv.call(a), uv.call(b), uv.call(cc)])
		Lib._tri(st, [a, cc, d], [n, n, n], [uv.call(a), uv.call(cc), uv.call(d)])

func box(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var v := []
	for y in [-1.0, 1.0]:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			v.append(center + basis * Vector3(corner.x * h.x, y * h.y, corner.y * h.z))
	hexa(st, v)

## Tapered block from a rectangle at y0 to another at y1 (sizes in x/z).
func taper(st: SurfaceTool, y0: float, s0: Vector2, y1: float, s1: Vector2, off0 := Vector2.ZERO, off1 := Vector2.ZERO) -> void:
	var v := []
	for pair in [[y0, s0, off0], [y1, s1, off1]]:
		var y: float = pair[0]
		var s: Vector2 = pair[1] * 0.5
		var o: Vector2 = pair[2]
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			v.append(Vector3(o.x + corner.x * s.x, y, o.y + corner.y * s.y))
	hexa(st, v)

func ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, rings := 10, segs := 16, noise_amt := 0.0, seed := 0) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 2.5
	var pts := []
	for r in range(rings + 1):
		var row := []
		var phi := PI * r / rings
		for s in range(segs + 1):
			var th := TAU * s / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var k := 1.0 + (n.get_noise_3dv(d * 1.5) * noise_amt if noise_amt > 0.0 else 0.0)
			row.append(d * k)
		pts.append(row)
	for r in range(rings):
		for s in range(segs):
			var quad := [pts[r][s], pts[r][s + 1], pts[r + 1][s + 1], pts[r + 1][s]]
			var ps := []
			var ns := []
			var uvs := []
			for q in quad:
				ps.append(center + q * radii)
				ns.append((q / radii).normalized())
				uvs.append(Vector2(atan2(q.z, q.x) / TAU, q.y) * 2.0)
			Lib._tri(st, [ps[0], ps[1], ps[2]], [ns[0], ns[1], ns[2]], [uvs[0], uvs[1], uvs[2]])
			Lib._tri(st, [ps[0], ps[2], ps[3]], [ns[0], ns[2], ns[3]], [uvs[0], uvs[2], uvs[3]])

func torus(st: SurfaceTool, center: Vector3, R: float, r: float, segs := 24, sides := 10, axis := Vector3.UP) -> void:
	var bs := Lib._basis_for(axis)
	for i in range(segs):
		for j in range(sides):
			var ps := []
			var ns := []
			for k in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u: float = TAU * k[0] / segs
				var v: float = TAU * k[1] / sides
				var ring := bs.x * cos(u) + bs.z * sin(u)
				var nrm := ring * cos(v) + bs.y * sin(v)
				ps.append(center + ring * R + nrm * r)
				ns.append(nrm)
			Lib._tri(st, [ps[0], ps[1], ps[2]], [ns[0], ns[1], ns[2]], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
			Lib._tri(st, [ps[0], ps[2], ps[3]], [ns[0], ns[2], ns[3]], [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])

func tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, segs := 12) -> void:
	Lib._tube(st, a, b, ra, rb, segs, 3.0)
	_disc(st, a, ra, (a - b).normalized(), segs)
	_disc(st, b, rb, (b - a).normalized(), segs)

func _mesh(parts: Array) -> ArrayMesh:
	return Lib._commit(parts)

# ------------------------------------------------------------------ public
func mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		_meshes[id] = _build(id)
	return _meshes[id]

## A Node3D showing the item (handles glTF-based items too).
func instance(id: String) -> Node3D:
	var root := Node3D.new()
	var Data = load("res://scripts/data.gd")
	if Data.ITEMS.get(id, {}).get("kind", "") == "placeable":
		var s := StaticBody3D.new()
		s.set_script(load("res://scripts/structure.gd"))
		s.persistent = false
		s.setup("", {"type": id, "pos": [0, 0, 0], "rot": 0.0, "data": {"fuel": 0.0}})
		s.collision_layer = 0
		s.collision_mask = 0
		s.process_mode = Node.PROCESS_MODE_DISABLED
		for g in ["structure", "roof", "placeable"]:
			s.remove_from_group(g)
		_strip_fx(s)
		root.add_child(s)
		return root
	if id in ["raw_fish", "cooked_fish"]:
		var fish_scene: PackedScene = load("res://assets/models/BarramundiFish.glb")
		if fish_scene:
			var f: Node3D = fish_scene.instantiate()
			f.scale = Vector3.ONE * 0.55
			f.rotation = Vector3(0, PI * 0.5, 0)
			f.position.y = 0.0
			root.add_child(f)
			if id == "cooked_fish":
				_overlay(f, Color(0.55, 0.3, 0.12, 0.65))
			return root
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(id)
	root.add_child(mi)
	return root

var _bounds := {}

## Raw model bounds (real-world size).
func bounds(id: String) -> AABB:
	if _bounds.has(id):
		return _bounds[id]
	var inst := instance(id)
	var acc := [null]
	for ch in inst.get_children():
		_aabb_of(ch, inst.transform, acc)
	inst.free()
	var bb: AABB = acc[0] if acc[0] != null else AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
	_bounds[id] = bb
	return bb

## Small things are shown a bit larger in the world so you can actually see and grab them.
func display_scale(id: String) -> float:
	var Data = load("res://scripts/data.gd")
	if Data.ITEMS.get(id, {}).get("kind", "") == "placeable":
		return 1.0
	var bb := bounds(id)
	var biggest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	return clampf(0.34 / maxf(biggest, 0.01), 1.0, 2.0)

func display_bounds(id: String) -> AABB:
	var bb := bounds(id)
	var k := display_scale(id)
	return AABB(bb.position * k, bb.size * k)

func display_instance(id: String) -> Node3D:
	var root := Node3D.new()
	var inst := instance(id)
	inst.scale = Vector3.ONE * display_scale(id)
	root.add_child(inst)
	return root

var _glow_mat: StandardMaterial3D

func set_glow(n: Node, on: bool) -> void:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.albedo_color = Color(0.35, 0.32, 0.2, 1.0)
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = _glow_mat if on else null
	for ch in n.get_children():
		set_glow(ch, on)

func _strip_fx(n: Node) -> void:
	for ch in n.get_children():
		if ch is Light3D or ch is CPUParticles3D or ch is AudioStreamPlayer3D or ch is CollisionShape3D:
			ch.queue_free()
		else:
			_strip_fx(ch)

func _overlay(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var om := StandardMaterial3D.new()
		om.albedo_color = col
		om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		(n as MeshInstance3D).material_overlay = om
	for ch in n.get_children():
		_overlay(ch, col)

func _build(id: String) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	match id:
		"axe": return _axe()
		"pickaxe": return _pickaxe()
		"hammer": return _hammer()
		"knife": return _knife()
		"bow": return _bow()
		"rifle": return _rifle()
		"fishing_rod": return _rod()
		"flashlight": return _flashlight()
		"arrow": return _arrow()
		"fuel_can": return _jerrycan()
		"canned_food": return _can(Color("c8a24a"), Color("8a2f22"), 0.075, 0.115)
		"soda": return _can(Color("c8302a"), Color("eeeeee"), 0.033, 0.12)
		"water_clean": return _bottle(Color(0.55, 0.8, 1.0, 0.55), Color("2a6fb0"))
		"water_dirty": return _bottle(Color(0.55, 0.5, 0.3, 0.75), Color("6a6a6a"))
		"coffee": return _mug()
		"coffee_beans": return _sack(Color("8a6a44"), Color("3a2414"))
		"stew": return _bowl(Color("8a4a22"))
		"raw_meat": return _steak(Color("b8383a"), Color("e8d0c0"))
		"cooked_meat": return _steak(Color("6a3a1e"), Color("b08050"))
		"berries": return _berries()
		"mushroom": return _mushroom(Color("b07a4a"))
		"roast_mushroom": return _mushroom(Color("5a3a20"))
		"tomato": return _tomato()
		"potato": return _potato(Color("b89060"), rng)
		"baked_potato": return _potato(Color("7a4a24"), rng)
		"bandage": return _bandage()
		"medkit": return _medkit()
		"seeds_tomato": return _packet(Color("d84a30"))
		"seeds_potato": return _packet(Color("b08a50"))
		"seeds_coffee": return _seedling()
		"ammo": return _ammo()
		"engine_parts": return _engine_parts()
		"tire": return _tire()
		"car_battery": return _battery()
		"toolkit": return _toolkit()
		"wood": return _logs(rng)
		"stone": return _stone(rng)
		"scrap": return _scrap(rng)
		"fiber": return _fiber(rng)
		"rope": return _rope()
		"cloth": return _cloth()
		"hide": return _hide(rng)
		"feather": return _feather()
		"jacket": return _jacket()
		"backpack": return _backpack()
		"worn_tire": return _tire(true)
		"worn_battery": return _battery(true)
		"wire": return _wire()
		"bolts": return _bolts(rng)
		"pipe": return _pipe()
		"foam": return _foam()
		"glass": return _glass_pane()
		"bottle_empty": return _bottle(Color(0.85, 0.92, 1.0, 0.22), Color("2a6fb0"))
		"fuel_can_empty": return _jerrycan(Color(0.42, 0.12, 0.1))
		"paint_can": return _spray()
		"engine_block": return _engine_block()
		"steering_wheel": return _steering_wheel()
		"car_seat": return _car_seat()
		"van_door": return _van_door()
		"headlight": return _headlight()
		"radio": return _radio()
		"floor_kit": return _floor_kit()
		"wall_panels": return _wall_panels()
		"kitchen_unit": return _kitchen_unit()
		"stove_unit": return _stove_unit()
		"sink_unit": return _sink_unit()
		"coffee_maker": return _coffee_maker()
		"fridge_unit": return _fridge_unit()
		"cupboard_unit": return _cupboard_unit(Vector3(0.56, 0.9, 0.7))
		"overhead_unit": return _cupboard_unit(Vector3(0.44, 0.45, 0.9))
		"dinette_kit": return _dinette_kit()
		"toilet_unit": return _toilet_unit()
		"bed_frame": return _bed_frame()
		"mattress": return _mattress()
		"ceiling_light": return _ceiling_light()
		"water_tank": return _water_tank()
		"solar_panel": return _solar_panel()
		"bull_bar": return _bull_bar()
		"heater_unit": return _heater_unit()
		"fuel_tank_xl": return _fuel_tank_xl()
		"tune_kit": return _tune_kit()
		"offroad_tire": return _tire(false, true)
	var st := _st()
	box(st, Vector3(0, 0.05, 0), Vector3(0.1, 0.1, 0.1))
	return _mesh([[st, c(Color.GRAY)]])

# ------------------------------------------------------------------ tools & weapons
func _handle(st: SurfaceTool, length: float, r0: float, r1: float) -> void:
	lathe(st, [Vector2(r0 * 1.15, -0.05), Vector2(r0, -0.03), Vector2(r0 * 0.95, length * 0.4), Vector2(r1, length)], 12)

func _axe() -> Mesh:
	var h := _st()
	_handle(h, 0.62, 0.02, 0.017)
	var head := _st()
	# eye block + bit wedge
	box(head, Vector3(0, 0.56, 0), Vector3(0.05, 0.08, 0.045))
	taper(head, 0.52, Vector2(0.03, 0.04), 0.6, Vector2(0.03, 0.04), Vector2(0.035, 0), Vector2(0.035, 0))
	hexa(head, [Vector3(0.05, 0.52, -0.02), Vector3(0.05, 0.52, 0.02), Vector3(0.05, 0.6, 0.02), Vector3(0.05, 0.6, -0.02),
		Vector3(0.17, 0.48, -0.002), Vector3(0.17, 0.48, 0.002), Vector3(0.17, 0.64, 0.002), Vector3(0.17, 0.64, -0.002)])
	taper(head, 0.53, Vector2(0.025, 0.035), 0.59, Vector2(0.02, 0.03), Vector2(-0.04, 0), Vector2(-0.055, 0))
	var edge := _st()
	hexa(edge, [Vector3(0.165, 0.48, -0.0025), Vector3(0.165, 0.48, 0.0025), Vector3(0.165, 0.64, 0.0025), Vector3(0.165, 0.64, -0.0025),
		Vector3(0.18, 0.475, -0.0005), Vector3(0.18, 0.475, 0.0005), Vector3(0.18, 0.645, 0.0005), Vector3(0.18, 0.645, -0.0005)])
	var wrap := _st()
	lathe(wrap, [Vector2(0.023, 0.0), Vector2(0.023, 0.12)], 12)
	return _mesh([[h, wood()], [head, dark_steel()], [edge, steel()], [wrap, leather()]])

func _pickaxe() -> Mesh:
	var h := _st()
	_handle(h, 0.72, 0.021, 0.019)
	var head := _st()
	box(head, Vector3(0, 0.68, 0), Vector3(0.06, 0.07, 0.05))
	for s in [-1.0, 1.0]:
		Lib._tube(head, Vector3(s * 0.03, 0.68, 0), Vector3(s * 0.15, 0.665, 0), 0.022, 0.016, 8)
		Lib._tube(head, Vector3(s * 0.15, 0.665, 0), Vector3(s * 0.25, 0.63, 0), 0.016, 0.003, 8)
	return _mesh([[h, wood()], [head, dark_steel()]])

func _hammer() -> Mesh:
	var h := _st()
	_handle(h, 0.36, 0.017, 0.015)
	var grip := _st()
	lathe(grip, [Vector2(0.021, -0.04), Vector2(0.022, 0.13), Vector2(0.019, 0.15)], 12)
	var head := _st()
	box(head, Vector3(0, 0.36, 0), Vector3(0.05, 0.05, 0.035))
	Lib._tube(head, Vector3(0.02, 0.36, 0), Vector3(0.075, 0.36, 0), 0.017, 0.019, 12)
	_disc(head, Vector3(0.075, 0.36, 0), 0.019, Vector3.RIGHT, 12)
	for z in [-0.008, 0.008]:
		Lib._tube(head, Vector3(-0.02, 0.37, z), Vector3(-0.08, 0.34, z * 2.0), 0.008, 0.003, 6)
		Lib._tube(head, Vector3(-0.08, 0.34, z * 2.0), Vector3(-0.105, 0.31, z * 2.5), 0.003, 0.0015, 6)
	return _mesh([[h, wood()], [grip, rubber()], [head, steel()]])

func _knife() -> Mesh:
	var handle := _st()
	taper(handle, -0.01, Vector2(0.022, 0.03), 0.11, Vector2(0.024, 0.032))
	var guard := _st()
	box(guard, Vector3(0, 0.115, 0), Vector3(0.03, 0.01, 0.05))
	box(guard, Vector3(0, -0.015, 0), Vector3(0.026, 0.01, 0.034))
	var blade := _st()
	hexa(blade, [Vector3(-0.002, 0.12, -0.014), Vector3(0.002, 0.12, -0.014), Vector3(0.002, 0.12, 0.016), Vector3(-0.002, 0.12, 0.016),
		Vector3(-0.0005, 0.29, 0.016), Vector3(0.0005, 0.29, 0.016), Vector3(0.0005, 0.29, 0.016), Vector3(-0.0005, 0.29, 0.016)])
	var rivets := _st()
	for y in [0.025, 0.08]:
		Lib._tube(rivets, Vector3(-0.0125, y, 0), Vector3(0.0125, y, 0), 0.004, 0.004, 8)
	return _mesh([[handle, dark_wood()], [guard, brass()], [blade, steel()], [rivets, brass()]])

func _bow() -> Mesh:
	var limbs := _st()
	var pts: Array[Vector3] = []
	for i in range(17):
		var t := -1.0 + i / 8.0
		pts.append(Vector3(0.12 * (1.0 - t * t) - 0.12 + absf(t) * absf(t) * t * t * -0.02, t * 0.62, 0))
	for i in range(pts.size() - 1):
		var r := lerpf(0.016, 0.007, absf(-1.0 + (i + 0.5) / 8.0))
		Lib._tube(limbs, pts[i], pts[i + 1], r, r, 8)
	var grip := _st()
	lathe(grip, [Vector2(0.021, -0.07), Vector2(0.023, 0.0), Vector2(0.021, 0.07)], 10, Vector3(0.002, 0, 0))
	var string := _st()
	Lib._tube(string, pts[0], pts[pts.size() - 1], 0.0015, 0.0015, 4)
	return _mesh([[limbs, dark_wood()], [grip, leather()], [string, c(Color(0.9, 0.88, 0.8))]])

func _rifle() -> Mesh:
	# Modelled along +Y (muzzle up). Origin at the pistol grip.
	var stock := _st()
	hexa(stock, [Vector3(-0.02, -0.38, -0.06), Vector3(0.02, -0.38, -0.06), Vector3(0.02, -0.38, 0.07), Vector3(-0.02, -0.38, 0.07),
		Vector3(-0.02, -0.05, -0.02), Vector3(0.02, -0.05, -0.02), Vector3(0.02, -0.05, 0.035), Vector3(-0.02, -0.05, 0.035)])
	taper(stock, -0.05, Vector2(0.04, 0.05), 0.42, Vector2(0.035, 0.035), Vector2(0, 0.01), Vector2(0, 0.03))
	var grip := _st()
	hexa(grip, [Vector3(-0.016, -0.08, -0.07), Vector3(0.016, -0.08, -0.07), Vector3(0.016, -0.04, -0.07), Vector3(-0.016, -0.04, -0.07),
		Vector3(-0.016, -0.02, 0.0), Vector3(0.016, -0.02, 0.0), Vector3(0.016, 0.01, 0.0), Vector3(-0.016, 0.01, 0.0)])
	var metal := _st()
	box(metal, Vector3(0, 0.06, 0.05), Vector3(0.03, 0.22, 0.035))
	Lib._tube(metal, Vector3(0, 0.15, 0.05), Vector3(0, 0.72, 0.05), 0.011, 0.009, 12)
	_disc(metal, Vector3(0, 0.72, 0.05), 0.009, Vector3.UP, 12)
	Lib._tube(metal, Vector3(0.015, 0.02, 0.06), Vector3(0.05, 0.0, 0.06), 0.004, 0.004, 6)
	metal_sphere(metal, Vector3(0.05, 0.0, 0.06), 0.008)
	box(metal, Vector3(0, 0.0, -0.025), Vector3(0.004, 0.05, 0.035))
	var scope := _st()
	lathe(scope, [Vector2(0.018, -0.02), Vector2(0.018, 0.02), Vector2(0.012, 0.04), Vector2(0.012, 0.16), Vector2(0.02, 0.2), Vector2(0.02, 0.23)], 16, Vector3(0, 0.0, 0.085))
	box(scope, Vector3(0, 0.03, 0.07), Vector3(0.01, 0.015, 0.02))
	box(scope, Vector3(0, 0.15, 0.07), Vector3(0.01, 0.015, 0.02))
	var lens := _st()
	_disc(lens, Vector3(0, 0.231, 0.085), 0.017, Vector3.UP, 16)
	_disc(lens, Vector3(0, -0.021, 0.085), 0.016, Vector3.DOWN, 16)
	var lens_mat := Lib.color_mat(Color(0.15, 0.3, 0.45), 0.05, 0.5, Color(0.2, 0.4, 0.6), 0.3)
	return _mesh([[stock, dark_wood()], [grip, dark_wood()], [metal, dark_steel()], [scope, c(Color(0.08, 0.08, 0.08), 0.4, 0.4)], [lens, lens_mat]])

func metal_sphere(st: SurfaceTool, at: Vector3, r: float) -> void:
	ellipsoid(st, at, Vector3.ONE * r, 6, 8)

func _rod() -> Mesh:
	var rod := _st()
	Lib._tube(rod, Vector3(0, 0.25, 0), Vector3(0, 1.6, 0), 0.008, 0.002, 8)
	var cork := _st()
	lathe(cork, [Vector2(0.015, -0.1), Vector2(0.017, 0.0), Vector2(0.016, 0.24), Vector2(0.011, 0.26)], 12)
	var reel := _st()
	lathe(reel, [Vector2(0.03, -0.02), Vector2(0.032, 0.0), Vector2(0.032, 0.035), Vector2(0.03, 0.04)], 16, Vector3(0.0, 0.0, 0.0))
	var reel_root := _st()
	box(reel_root, Vector3(0.0, 0.1, 0.025), Vector3(0.01, 0.06, 0.03))
	var guides := _st()
	for y in [0.55, 0.85, 1.12, 1.35, 1.52]:
		torus(guides, Vector3(0, y, 0.012), 0.008, 0.0015, 10, 4, Vector3.UP)
	var line := _st()
	Lib._tube(line, Vector3(0, 0.12, 0.03), Vector3(0, 1.6, 0.004), 0.0006, 0.0006, 3)
	# reel modelled on its side
	var reel_mesh := _mesh([[reel, m("metal", Color(0.85, 0.3, 0.2), 6.0, 0.35, 0.7)]])
	var out := _mesh([[rod, c(Color(0.12, 0.22, 0.16), 0.3, 0.2)], [cork, m("cardboard", Color(0.95, 0.8, 0.6), 10.0, 0.9)],
		[reel_root, dark_steel()], [guides, steel()], [line, c(Color(0.9, 0.9, 0.85), 0.5)]])
	# append rotated reel surface
	var st := _st()
	st.append_from(reel_mesh, 0, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.1, 0.06)))
	st.generate_tangents()
	st.commit(out)
	out.surface_set_material(out.get_surface_count() - 1, m("metal", Color(0.85, 0.3, 0.2), 6.0, 0.35, 0.7))
	return out

func _flashlight() -> Mesh:
	var body := _st()
	lathe(body, [Vector2(0.016, -0.02), Vector2(0.018, 0.0), Vector2(0.018, 0.13), Vector2(0.027, 0.17), Vector2(0.028, 0.2)], 18)
	var grip := _st()
	lathe(grip, [Vector2(0.0185, 0.02), Vector2(0.0185, 0.11)], 18)
	var lens := _st()
	_disc(lens, Vector3(0, 0.201, 0), 0.025, Vector3.UP, 18)
	var btn := _st()
	box(btn, Vector3(0, 0.08, 0.019), Vector3(0.008, 0.016, 0.006))
	return _mesh([[body, m("metal", Color(0.2, 0.2, 0.22), 6.0, 0.4, 0.8)], [grip, rubber()],
		[lens, Lib.color_mat(Color(1, 0.97, 0.85), 0.05, 0.0, Color(1, 0.95, 0.8), 0.6)], [btn, c(Color(0.7, 0.1, 0.1))]])

func _arrow() -> Mesh:
	var shaft := _st()
	Lib._tube(shaft, Vector3(0, -0.35, 0), Vector3(0, 0.35, 0), 0.0045, 0.0045, 6)
	var head := _st()
	hexa(head, [Vector3(-0.012, 0.35, -0.0015), Vector3(0.012, 0.35, -0.0015), Vector3(0.012, 0.35, 0.0015), Vector3(-0.012, 0.35, 0.0015),
		Vector3(0, 0.41, -0.0005), Vector3(0, 0.41, -0.0005), Vector3(0, 0.41, 0.0005), Vector3(0, 0.41, 0.0005)])
	var fl := _st()
	for k in range(3):
		var a := TAU * k / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		Lib._quad(fl, Vector3(0, -0.33, 0) + d * 0.012, d * 0.012, Vector3(0, 0.1, 0), d.cross(Vector3.UP))
	return _mesh([[shaft, wood()], [head, dark_steel()], [fl, c(Color(0.85, 0.2, 0.15), 0.8)]])

# ------------------------------------------------------------------ containers & consumables
func _jerrycan(col := Color(0.7, 0.1, 0.08)) -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.17, 0), Vector3(0.12, 0.32, 0.24))
	for s in [-1.0, 1.0]:
		box(body, Vector3(s * 0.061, 0.17, 0), Vector3(0.006, 0.26, 0.03), Basis(Vector3.RIGHT, 0.85))
		box(body, Vector3(s * 0.061, 0.17, 0), Vector3(0.006, 0.26, 0.03), Basis(Vector3.RIGHT, -0.85))
	for z in [-0.06, 0.0, 0.06]:
		box(body, Vector3(0, 0.36, z), Vector3(0.03, 0.04, 0.02))
	box(body, Vector3(0, 0.38, 0), Vector3(0.03, 0.015, 0.15))
	var spout := _st()
	lathe(spout, [Vector2(0.02, 0.33), Vector2(0.02, 0.37), Vector2(0.022, 0.37), Vector2(0.022, 0.38)], 14, Vector3(0, 0, 0.08))
	return _mesh([[body, paint(col)], [spout, dark_steel()]])

func _can(label: Color, band_col: Color, r: float, h: float) -> Mesh:
	var rim := _st()
	lathe(rim, [Vector2(r * 0.92, 0.0), Vector2(r, 0.006), Vector2(r, 0.012)], 24)
	lathe(rim, [Vector2(r, h - 0.012), Vector2(r, h - 0.006), Vector2(r * 0.92, h)], 24)
	var lab := _st()
	lathe(lab, [Vector2(r * 1.002, 0.012), Vector2(r * 1.002, h - 0.012)], 24, Vector3.ZERO, false, false)
	var bnd := _st()
	lathe(bnd, [Vector2(r * 1.004, h * 0.4), Vector2(r * 1.004, h * 0.6)], 24, Vector3.ZERO, false, false)
	return _mesh([[rim, steel()], [lab, paint(label)], [bnd, paint(band_col)]])

func _bottle(liquid: Color, cap: Color) -> Mesh:
	var body := _st()
	lathe(body, [Vector2(0.0, 0.0), Vector2(0.034, 0.002), Vector2(0.036, 0.02), Vector2(0.036, 0.15), Vector2(0.03, 0.18), Vector2(0.014, 0.21), Vector2(0.013, 0.225)], 20, Vector3.ZERO, false, false)
	var capst := _st()
	lathe(capst, [Vector2(0.015, 0.222), Vector2(0.015, 0.245), Vector2(0.012, 0.248)], 14)
	var label := _st()
	lathe(label, [Vector2(0.0365, 0.05), Vector2(0.0365, 0.11)], 20, Vector3.ZERO, false, false)
	var glass := Lib.color_mat(liquid, 0.05, 0.1)
	glass = glass.duplicate()
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh([[body, glass], [capst, c(cap, 0.5)], [label, paint(Color(0.95, 0.95, 0.9))]])

func _mug() -> Mesh:
	var mug := _st()
	lathe(mug, [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.043, 0.09), Vector2(0.038, 0.09), Vector2(0.035, 0.01), Vector2(0.0, 0.01)], 22, Vector3.ZERO, false, false)
	torus(mug, Vector3(0.05, 0.048, 0), 0.025, 0.006, 14, 6, Vector3.FORWARD)
	var coffee := _st()
	_disc(coffee, Vector3(0, 0.075, 0), 0.037, Vector3.UP, 20)
	return _mesh([[mug, paint(Color(0.2, 0.35, 0.55))], [coffee, Lib.color_mat(Color(0.18, 0.09, 0.04), 0.1)]])

func _sack(col: Color, bean: Color) -> Mesh:
	var sack := _st()
	ellipsoid(sack, Vector3(0, 0.08, 0), Vector3(0.08, 0.08, 0.06), 8, 14, 0.18, 3)
	lathe(sack, [Vector2(0.035, 0.14), Vector2(0.025, 0.17), Vector2(0.04, 0.19)], 12)
	var tie := _st()
	torus(tie, Vector3(0, 0.155, 0), 0.03, 0.005, 14, 5)
	var beans := _st()
	for i in range(5):
		ellipsoid(beans, Vector3(0.09 + i * 0.012, 0.006, -0.03 + i * 0.015), Vector3(0.008, 0.006, 0.011), 4, 6)
	return _mesh([[sack, m("canvas", col, 8.0, 0.9)], [tie, m("cardboard", Color(0.9, 0.8, 0.6))], [beans, c(bean, 0.4)]])

func _bowl(stew: Color) -> Mesh:
	var bowl := _st()
	lathe(bowl, [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.075, 0.05), Vector2(0.07, 0.05), Vector2(0.035, 0.008), Vector2(0.0, 0.008)], 22, Vector3.ZERO, false, false)
	var food := _st()
	_disc(food, Vector3(0, 0.04, 0), 0.066, Vector3.UP, 22)
	var chunks := _st()
	for i in range(6):
		var a := TAU * i / 6.0
		box(chunks, Vector3(cos(a) * 0.03, 0.043, sin(a) * 0.03), Vector3(0.015, 0.012, 0.015), Basis(Vector3.UP, a))
	return _mesh([[bowl, wood()], [food, c(stew, 0.25)], [chunks, c(Color(0.85, 0.55, 0.25), 0.5)]])

func _steak(meat: Color, fat: Color) -> Mesh:
	var st := _st()
	ellipsoid(st, Vector3(0, 0.02, 0), Vector3(0.09, 0.022, 0.065), 6, 18, 0.12, 9)
	var f := _st()
	torus(f, Vector3(-0.01, 0.02, 0), 0.07, 0.01, 18, 6)
	var bone := _st()
	lathe(bone, [Vector2(0.012, -0.05), Vector2(0.012, 0.05)], 10, Vector3.ZERO)
	var bone_mesh := _mesh([[bone, c(Color(0.92, 0.88, 0.8))]])
	var out := _mesh([[st, m("leather", meat, 6.0, 0.35)], [f, c(fat, 0.4)]])
	var bst := _st()
	bst.append_from(bone_mesh, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.02, 0.025, 0)))
	bst.commit(out)
	out.surface_set_material(out.get_surface_count() - 1, c(Color(0.92, 0.88, 0.8)))
	return out

func _berries() -> Mesh:
	var b := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(14):
		var p := Vector3(rng.randf_range(-0.04, 0.04), 0.012 + rng.randf() * 0.03, rng.randf_range(-0.04, 0.04))
		ellipsoid(b, p, Vector3.ONE * 0.011, 5, 8)
	var leaves := _st()
	for i in range(3):
		var a := TAU * i / 3.0
		hexa(leaves, [Vector3(0, 0.05, 0), Vector3(0, 0.05, 0), Vector3(0, 0.051, 0), Vector3(0, 0.051, 0),
			Vector3(cos(a) * 0.05 - sin(a) * 0.015, 0.045, sin(a) * 0.05 + cos(a) * 0.015), Vector3(cos(a) * 0.05 + sin(a) * 0.015, 0.045, sin(a) * 0.05 - cos(a) * 0.015),
			Vector3(cos(a) * 0.08, 0.04, sin(a) * 0.08), Vector3(cos(a) * 0.08, 0.041, sin(a) * 0.08)])
	return _mesh([[b, c(Color(0.32, 0.1, 0.35), 0.25)], [leaves, c(Color(0.25, 0.45, 0.2), 0.7)]])

func _mushroom(cap: Color) -> Mesh:
	var stem := _st()
	lathe(stem, [Vector2(0.018, 0.0), Vector2(0.014, 0.05), Vector2(0.012, 0.08)], 12)
	var capst := _st()
	lathe(capst, [Vector2(0.012, 0.07), Vector2(0.05, 0.07), Vector2(0.052, 0.08), Vector2(0.04, 0.1), Vector2(0.015, 0.11), Vector2(0.0, 0.112)], 18, Vector3.ZERO, true, false)
	return _mesh([[stem, c(Color(0.92, 0.88, 0.78), 0.8)], [capst, m("leather", cap, 6.0, 0.6)]])

func _tomato() -> Mesh:
	var t := _st()
	ellipsoid(t, Vector3(0, 0.035, 0), Vector3(0.042, 0.035, 0.042), 10, 18, 0.06, 1)
	var calyx := _st()
	for i in range(5):
		var a := TAU * i / 5.0
		Lib._tube(calyx, Vector3(0, 0.07, 0), Vector3(cos(a) * 0.025, 0.066, sin(a) * 0.025), 0.004, 0.001, 4)
	Lib._tube(calyx, Vector3(0, 0.068, 0), Vector3(0, 0.085, 0.004), 0.003, 0.002, 5)
	return _mesh([[t, c(Color(0.8, 0.12, 0.08), 0.25)], [calyx, c(Color(0.25, 0.45, 0.18))]])

func _potato(col: Color, rng: RandomNumberGenerator) -> Mesh:
	var p := _st()
	ellipsoid(p, Vector3(0, 0.03, 0), Vector3(0.055, 0.03, 0.038), 8, 14, 0.18, rng.randi())
	return _mesh([[p, m("dirt", col.lightened(0.6), 10.0, 0.9)]])

func _bandage() -> Mesh:
	var r := _st()
	lathe(r, [Vector2(0.012, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.05), Vector2(0.012, 0.05)], 20, Vector3.ZERO, false, false)
	var tail := _st()
	box(tail, Vector3(0.03, 0.025, 0.04), Vector3(0.002, 0.05, 0.08))
	return _mesh([[r, m("cardboard", Color(1.9, 1.9, 1.85), 30.0, 0.9)], [tail, m("cardboard", Color(1.9, 1.9, 1.85), 30.0, 0.9)]])

func _medkit() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.06, 0), Vector3(0.22, 0.12, 0.08))
	var cross := _st()
	box(cross, Vector3(0, 0.06, 0.041), Vector3(0.07, 0.022, 0.002))
	box(cross, Vector3(0, 0.06, 0.041), Vector3(0.022, 0.07, 0.002))
	var handle := _st()
	torus(handle, Vector3(0, 0.12, 0), 0.035, 0.006, 14, 5, Vector3.FORWARD)
	return _mesh([[b, paint(Color(0.75, 0.12, 0.1))], [cross, c(Color(0.95, 0.95, 0.95))], [handle, c(Color(0.1, 0.1, 0.1))]])

func _packet(col: Color) -> Mesh:
	var p := _st()
	taper(p, 0.0, Vector2(0.09, 0.02), 0.13, Vector2(0.09, 0.006))
	var top := _st()
	box(top, Vector3(0, 0.135, 0), Vector3(0.092, 0.01, 0.004))
	var label := _st()
	box(label, Vector3(0, 0.06, 0.0105), Vector3(0.06, 0.06, 0.001))
	return _mesh([[p, m("cardboard", Color(1.1, 1.05, 1.0), 8.0)], [top, m("cardboard", Color(0.8, 0.7, 0.6))], [label, paint(col)]])

func _seedling() -> Mesh:
	var pot := _st()
	lathe(pot, [Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.045, 0.07), Vector2(0.048, 0.075)], 18)
	var soil := _st()
	_disc(soil, Vector3(0, 0.068, 0), 0.043, Vector3.UP, 18)
	var plant := _st()
	Lib._tube(plant, Vector3(0, 0.068, 0), Vector3(0, 0.14, 0), 0.003, 0.002, 5)
	for i in range(4):
		var a := TAU * i / 4.0
		var y := 0.1 + i * 0.012
		ellipsoid(plant, Vector3(cos(a) * 0.022, y, sin(a) * 0.022), Vector3(0.022, 0.003, 0.012), 3, 8)
	return _mesh([[pot, m("dirt", Color(1.6, 0.9, 0.7), 8.0)], [soil, m("dirt", Color.WHITE, 10.0)], [plant, c(Color(0.2, 0.5, 0.18), 0.5)]])

func _ammo() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.025, 0), Vector3(0.12, 0.05, 0.08))
	var brass_st := _st()
	var tips := _st()
	for i in range(3):
		var p := Vector3(-0.025 + i * 0.025, 0.05, 0.0)
		lathe(brass_st, [Vector2(0.005, 0.0), Vector2(0.005, 0.045), Vector2(0.0035, 0.052)], 10, p)
		lathe(tips, [Vector2(0.0035, 0.052), Vector2(0.003, 0.062), Vector2(0.0, 0.07)], 10, p, false, false)
	return _mesh([[b, m("cardboard", Color(0.6, 0.65, 0.5))], [brass_st, brass()], [tips, m("metal", Color(0.75, 0.5, 0.35), 8.0, 0.4, 0.8)]])

func _engine_parts() -> Mesh:
	var gear := _st()
	lathe(gear, [Vector2(0.015, 0.0), Vector2(0.06, 0.0), Vector2(0.06, 0.02), Vector2(0.015, 0.02)], 24, Vector3(-0.04, 0, 0), false, false)
	for i in range(14):
		var a := TAU * i / 14.0
		box(gear, Vector3(-0.04 + cos(a) * 0.066, 0.01, sin(a) * 0.066), Vector3(0.014, 0.02, 0.012), Basis(Vector3.UP, -a))
	var piston := _st()
	lathe(piston, [Vector2(0.03, 0.0), Vector2(0.032, 0.005), Vector2(0.032, 0.05), Vector2(0.03, 0.055)], 20, Vector3(0.06, 0, 0.0))
	Lib._tube(piston, Vector3(0.06, 0.03, 0), Vector3(0.06, 0.12, 0.05), 0.008, 0.008, 8)
	torus(piston, Vector3(0.06, 0.125, 0.052), 0.015, 0.006, 12, 6, Vector3.RIGHT)
	return _mesh([[gear, steel()], [piston, dark_steel()]])

func _tire(worn := false, knobby := false) -> Mesh:
	var t := _st()
	torus(t, Vector3(0, 0.12, 0), 0.24, 0.11, 32, 14, Vector3.UP)
	if knobby:
		for i in range(28):
			var a := TAU * i / 28.0
			for side in [-1.0, 1.0]:
				box(t, Vector3(cos(a) * 0.345, 0.12 + side * 0.045, sin(a) * 0.345), Vector3(0.03, 0.05, 0.05), Basis(Vector3.UP, -a + side * 0.25))
	var rim := _st()
	lathe(rim, [Vector2(0.0, 0.08), Vector2(0.17, 0.07), Vector2(0.17, 0.17), Vector2(0.0, 0.16)], 24, Vector3.ZERO, false, false)
	for i in range(5):
		var a := TAU * i / 5.0
		Lib._tube(rim, Vector3(cos(a) * 0.08, 0.17, sin(a) * 0.08), Vector3(cos(a) * 0.08, 0.18, sin(a) * 0.08), 0.01, 0.008, 6)
	if worn:
		return _mesh([[t, m("rubber", Color(0.75, 0.7, 0.62), 5.0, 1.0)], [rim, m("rust", Color.WHITE, 4.0, 0.8, 0.4)]])
	return _mesh([[t, rubber()], [rim, m("metal", Color(0.7, 0.7, 0.72), 4.0, 0.35, 0.8)]])

func _battery(worn := false) -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.09, 0), Vector3(0.24, 0.18, 0.17))
	var top := _st()
	box(top, Vector3(0, 0.185, 0), Vector3(0.235, 0.012, 0.165))
	var label := _st()
	box(label, Vector3(0, 0.1, 0.0855), Vector3(0.18, 0.08, 0.001))
	var pos := _st()
	lathe(pos, [Vector2(0.012, 0.19), Vector2(0.01, 0.215)], 12, Vector3(0.08, 0, 0.04))
	var neg := _st()
	lathe(neg, [Vector2(0.012, 0.19), Vector2(0.01, 0.215)], 12, Vector3(-0.08, 0, 0.04))
	if worn:
		return _mesh([[b, m("rust", Color(0.45, 0.42, 0.4), 4.0, 0.9)], [top, c(Color(0.3, 0.28, 0.26))], [label, paint(Color(0.45, 0.4, 0.3))],
			[pos, m("rust", Color.WHITE, 8.0)], [neg, m("rust", Color.WHITE, 8.0)]])
	return _mesh([[b, m("paint", Color(0.12, 0.12, 0.13), 4.0, 0.6)], [top, c(Color(0.18, 0.18, 0.2))], [label, paint(Color(0.2, 0.45, 0.8))],
		[pos, c(Color(0.8, 0.15, 0.1), 0.4, 0.5)], [neg, dark_steel()]])

func _toolkit() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.07, 0), Vector3(0.36, 0.14, 0.16))
	taper(b, 0.14, Vector2(0.36, 0.16), 0.17, Vector2(0.34, 0.12))
	var hw := _st()
	for x in [-0.1, 0.1]:
		box(hw, Vector3(x, 0.215, 0), Vector3(0.012, 0.05, 0.012))
		box(hw, Vector3(x * 1.5, 0.13, 0.081), Vector3(0.03, 0.03, 0.006))
	box(hw, Vector3(0, 0.24, 0), Vector3(0.22, 0.016, 0.02))
	return _mesh([[b, paint(Color(0.75, 0.12, 0.1))], [hw, dark_steel()]])

# ------------------------------------------------------------------ materials (resources)
func _logs(rng: RandomNumberGenerator) -> Mesh:
	var bark := _st()
	var ends := _st()
	var spots := [Vector3(-0.07, 0.06, 0), Vector3(0.07, 0.06, 0), Vector3(0.0, 0.17, 0)]
	for p in spots:
		var r := rng.randf_range(0.055, 0.065)
		var a: Vector3 = p + Vector3(0, 0, -0.22)
		var b: Vector3 = p + Vector3(0, 0, 0.22)
		Lib._tube(bark, a, b, r, r * 0.95, 12, 3.0)
		_disc(ends, a, r * 0.98, Vector3.BACK, 12)
		_disc(ends, b, r * 0.93, Vector3.FORWARD, 12)
	return _mesh([[bark, m("bark", Color.WHITE, 6.0, 0.9)], [ends, m("logs", Color(1.3, 1.2, 1.0), 12.0, 0.8)]])

func _stone(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.05, 0), Vector3(0.08, 0.05, 0.065), 8, 12, 0.3, rng.randi())
	return _mesh([[s, m("rock", Color.WHITE, 6.0, 0.9)]])

func _scrap(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	for i in range(4):
		box(s, Vector3(rng.randf_range(-0.05, 0.05), 0.01 + i * 0.012, rng.randf_range(-0.05, 0.05)), Vector3(rng.randf_range(0.1, 0.2), 0.006, rng.randf_range(0.06, 0.14)),
			Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))))
	var bolts := _st()
	for i in range(4):
		lathe(bolts, [Vector2(0.008, 0.0), Vector2(0.008, 0.008), Vector2(0.004, 0.008), Vector2(0.004, 0.04)], 6, Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08)))
	return _mesh([[s, m("rust", Color.WHITE, 8.0, 0.8, 0.4)], [bolts, dark_steel()]])

func _fiber(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	for i in range(26):
		var o := Vector3(rng.randf_range(-0.02, 0.02), 0, rng.randf_range(-0.02, 0.02))
		Lib._tube(s, Vector3(-0.15, 0.02, 0) + o, Vector3(0.15, 0.02 + rng.randf_range(-0.01, 0.02), 0) + o * 1.5, 0.003, 0.0015, 4)
	var tie := _st()
	torus(tie, Vector3(0, 0.02, 0), 0.026, 0.004, 12, 4, Vector3.RIGHT)
	return _mesh([[s, c(Color(0.55, 0.62, 0.32), 0.8)], [tie, c(Color(0.45, 0.35, 0.2))]])

func _rope() -> Mesh:
	var s := _st()
	for k in range(4):
		torus(s, Vector3(0, 0.012 + k * 0.016, 0), 0.07 - k * 0.002, 0.008, 28, 6)
	return _mesh([[s, m("cardboard", Color(1.15, 0.95, 0.7), 30.0, 0.9)]])

func _cloth() -> Mesh:
	var s := _st()
	for k in range(3):
		box(s, Vector3(0, 0.01 + k * 0.02, 0), Vector3(0.2 - k * 0.01, 0.018, 0.14 - k * 0.005), Basis(Vector3.UP, k * 0.08))
	return _mesh([[s, m("plaid", Color.WHITE, 6.0, 0.9)]])

func _hide(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.01, 0), Vector3(0.2, 0.012, 0.14), 6, 20, 0.35, rng.randi())
	return _mesh([[s, m("fur", Color(0.8, 0.6, 0.42), 4.0, 1.0)]])

func _feather() -> Mesh:
	var vane := _st()
	hexa(vane, [Vector3(-0.001, 0.0, 0.0), Vector3(0.001, 0.0, 0.0), Vector3(0.001, 0.0, 0.0), Vector3(-0.001, 0.0, 0.0),
		Vector3(-0.022, 0.09, -0.001), Vector3(0.022, 0.09, -0.001), Vector3(0.012, 0.16, 0.001), Vector3(-0.012, 0.16, 0.001)])
	var quill := _st()
	Lib._tube(quill, Vector3(0, -0.03, 0), Vector3(0, 0.16, 0), 0.0018, 0.0006, 5)
	return _mesh([[vane, m("fur", Color(0.9, 0.85, 0.75), 20.0, 0.9)], [quill, c(Color(0.95, 0.92, 0.85))]])

func _jacket() -> Mesh:
	var body := _st()
	taper(body, 0.0, Vector2(0.4, 0.2), 0.5, Vector2(0.44, 0.18))
	box(body, Vector3(0, 0.52, 0), Vector3(0.18, 0.06, 0.16))
	for s in [-1.0, 1.0]:
		Lib._tube(body, Vector3(s * 0.22, 0.46, 0), Vector3(s * 0.32, 0.05, 0.02), 0.06, 0.05, 10)
	var buttons := _st()
	for y in [0.12, 0.24, 0.36]:
		ellipsoid(buttons, Vector3(0, y, 0.1), Vector3(0.012, 0.012, 0.004), 4, 8)
	return _mesh([[body, m("leather", Color(1.0, 0.9, 0.8), 3.0, 0.7)], [buttons, brass()]])

func _backpack() -> Mesh:
	var body := _st()
	ellipsoid(body, Vector3(0, 0.24, 0), Vector3(0.17, 0.24, 0.11), 10, 16)
	var pocket := _st()
	ellipsoid(pocket, Vector3(0, 0.15, 0.1), Vector3(0.12, 0.1, 0.05), 8, 12)
	var straps := _st()
	for x in [-0.08, 0.08]:
		Lib._tube(straps, Vector3(x, 0.44, -0.09), Vector3(x, 0.08, -0.12), 0.018, 0.018, 6)
	torus(straps, Vector3(0, 0.49, 0), 0.04, 0.01, 12, 5, Vector3.RIGHT)
	var buckles := _st()
	box(buckles, Vector3(0, 0.22, 0.152), Vector3(0.05, 0.03, 0.01))
	return _mesh([[body, m("canvas", Color(0.55, 0.62, 0.45), 4.0, 0.9)], [pocket, m("canvas", Color(0.45, 0.5, 0.36), 4.0, 0.9)],
		[straps, leather()], [buckles, dark_steel()]])

# ------------------------------------------------------------------ 1.4: materials, containers, van modules
func laminate() -> StandardMaterial3D: return m("laminate", Color.WHITE, 3.0, 0.45)
func upholstery() -> StandardMaterial3D: return m("upholstery", Color.WHITE, 0.9, 0.95)
func white_plastic() -> StandardMaterial3D: return c(Color(0.92, 0.92, 0.9), 0.35)
func black_plastic() -> StandardMaterial3D: return c(Color(0.08, 0.08, 0.09), 0.5)
func glass_m() -> StandardMaterial3D:
	var g := Lib.color_mat(Color(0.7, 0.85, 0.95, 0.35), 0.05, 0.2).duplicate()
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g

func _wire() -> Mesh:
	var s := _st()
	for k in range(5):
		torus(s, Vector3(0, 0.008 + k * 0.009, 0), 0.075 - (k % 2) * 0.004, 0.0045, 30, 5)
	Lib._tube(s, Vector3(0.075, 0.04, 0), Vector3(0.14, 0.01, 0.05), 0.004, 0.004, 5)
	var spool := _st()
	lathe(spool, [Vector2(0.035, 0.0), Vector2(0.035, 0.05)], 16, Vector3.ZERO, false, false)
	return _mesh([[s, m("metal", Color(0.95, 0.55, 0.3), 8.0, 0.3, 0.9)], [spool, black_plastic()]])

func _bolts(rng: RandomNumberGenerator) -> Mesh:
	var tray := _st()
	box(tray, Vector3(0, 0.005, 0), Vector3(0.16, 0.01, 0.11))
	for sx in [-1.0, 1.0]:
		box(tray, Vector3(sx * 0.078, 0.02, 0), Vector3(0.006, 0.03, 0.11))
	for sz in [-1.0, 1.0]:
		box(tray, Vector3(0, 0.02, sz * 0.053), Vector3(0.16, 0.03, 0.006))
	var hw := _st()
	for i in range(9):
		var p := Vector3(rng.randf_range(-0.06, 0.06), 0.012, rng.randf_range(-0.035, 0.035))
		if i % 3 == 0:
			torus(hw, p + Vector3(0, 0.004, 0), 0.009, 0.004, 6, 4)
		else:
			var b := Basis.from_euler(Vector3(PI * 0.5, rng.randf() * TAU, 0))
			lathe(hw, [Vector2(0.01, 0.0), Vector2(0.01, 0.007)], 6, p)
			Lib._tube(hw, p + Vector3(0, 0.004, 0), p + b * Vector3(0, 0.05, 0) + Vector3(0, 0.004, 0), 0.005, 0.005, 6)
	return _mesh([[tray, m("cardboard", Color(0.8, 0.75, 0.65), 6.0)], [hw, steel()]])

func _pipe() -> Mesh:
	var s := _st()
	Lib._tube(s, Vector3(-0.3, 0.03, 0), Vector3(0.24, 0.03, 0), 0.026, 0.026, 14)
	Lib._tube(s, Vector3(0.24, 0.03, 0), Vector3(0.3, 0.03, 0.06), 0.026, 0.026, 14)
	var ends := _st()
	torus(ends, Vector3(-0.3, 0.03, 0), 0.026, 0.006, 16, 5, Vector3.RIGHT)
	torus(ends, Vector3(-0.26, 0.03, 0), 0.027, 0.005, 16, 5, Vector3.RIGHT)
	return _mesh([[s, m("metal", Color(0.7, 0.72, 0.74), 6.0, 0.35, 0.85)], [ends, m("rust", Color.WHITE, 6.0)]])

func _foam() -> Mesh:
	var s := _st()
	for k in range(3):
		box(s, Vector3(0, 0.025 + k * 0.05, 0), Vector3(0.36 - k * 0.01, 0.045, 0.26), Basis(Vector3.UP, k * 0.06 - 0.06))
	return _mesh([[s, m("insulation", Color(1.0, 0.92, 0.6), 2.0, 1.0)]])

func _glass_pane() -> Mesh:
	var g := _st()
	box(g, Vector3(0, 0.008, 0), Vector3(0.4, 0.006, 0.3))
	var edge := _st()
	for sz in [-1.0, 1.0]:
		box(edge, Vector3(0, 0.008, sz * 0.15), Vector3(0.41, 0.014, 0.012))
	for sx in [-1.0, 1.0]:
		box(edge, Vector3(sx * 0.2, 0.008, 0), Vector3(0.012, 0.014, 0.3))
	return _mesh([[g, glass_m()], [edge, m("rubber", Color(0.4, 0.4, 0.4), 4.0)]])

func _spray() -> Mesh:
	var b := _st()
	lathe(b, [Vector2(0.03, 0.0), Vector2(0.032, 0.005), Vector2(0.032, 0.15), Vector2(0.024, 0.17), Vector2(0.012, 0.175)], 20)
	var cap := _st()
	lathe(cap, [Vector2(0.031, 0.165), Vector2(0.031, 0.2), Vector2(0.026, 0.21)], 18)
	var lab := _st()
	lathe(lab, [Vector2(0.0325, 0.04), Vector2(0.0325, 0.11)], 20, Vector3.ZERO, false, false)
	return _mesh([[b, steel()], [cap, c(Color(0.25, 0.55, 0.8), 0.3)], [lab, paint(Color(0.9, 0.85, 0.2))]])

func _engine_block() -> Mesh:
	var blk := _st()
	taper(blk, 0.0, Vector2(0.5, 0.3), 0.12, Vector2(0.56, 0.36))
	box(blk, Vector3(0, 0.25, 0), Vector3(0.56, 0.26, 0.36))
	taper(blk, 0.38, Vector2(0.56, 0.36), 0.44, Vector2(0.5, 0.28))
	var cover := _st()
	box(cover, Vector3(0, 0.47, 0), Vector3(0.48, 0.06, 0.22))
	for i in range(4):
		lathe(cover, [Vector2(0.016, 0.5), Vector2(0.016, 0.53)], 10, Vector3(-0.18 + i * 0.12, 0, 0))
	var pulleys := _st()
	for p in [[Vector3(-0.29, 0.2, 0.05), 0.08], [Vector3(-0.29, 0.38, -0.08), 0.05], [Vector3(-0.29, 0.34, 0.12), 0.04]]:
		var bs := Basis(Vector3.FORWARD, PI * 0.5)
		Lib._tube(pulleys, p[0] + Vector3(0.02, 0, 0), p[0] - Vector3(0.02, 0, 0), p[1], p[1], 20)
		_disc(pulleys, p[0] - Vector3(0.02, 0, 0), p[1], Vector3.LEFT, 20)
	var exh := _st()
	for i in range(4):
		var z0 := -0.18 + i * 0.12
		Lib._tube(exh, Vector3(z0, 0.32, 0.18), Vector3(z0 * 0.4, 0.2, 0.25), 0.022, 0.022, 8)
	Lib._tube(exh, Vector3(-0.08, 0.2, 0.25), Vector3(0.1, 0.12, 0.26), 0.03, 0.03, 10)
	var filt := _st()
	lathe(filt, [Vector2(0.04, 0.0), Vector2(0.042, 0.01), Vector2(0.042, 0.1), Vector2(0.035, 0.11)], 16, Vector3(0.2, 0.08, -0.2))
	return _mesh([[blk, m("metal", Color(0.42, 0.44, 0.46), 4.0, 0.6, 0.6)], [cover, paint(Color(0.65, 0.12, 0.1))], [pulleys, dark_steel()],
		[exh, m("rust", Color.WHITE, 5.0, 0.8, 0.5)], [filt, paint(Color(0.15, 0.3, 0.7))]])

func _steering_wheel() -> Mesh:
	var rim := _st()
	torus(rim, Vector3(0, 0.03, 0), 0.19, 0.018, 36, 10)
	var hub := _st()
	lathe(hub, [Vector2(0.05, 0.0), Vector2(0.055, 0.03), Vector2(0.045, 0.06)], 18)
	for a in [PI * 0.5, PI * 0.5 + 2.2, PI * 0.5 - 2.2]:
		Lib._tube(hub, Vector3(0, 0.035, 0), Vector3(cos(a) * 0.18, 0.03, sin(a) * 0.18), 0.016, 0.012, 8)
	return _mesh([[rim, m("leather", Color(0.25, 0.25, 0.27), 8.0, 0.6)], [hub, black_plastic()]])

func _car_seat() -> Mesh:
	var cush := _st()
	box(cush, Vector3(0, 0.16, 0.0), Vector3(0.5, 0.12, 0.5))
	box(cush, Vector3(0, 0.5, -0.24), Vector3(0.5, 0.62, 0.13), Basis(Vector3.RIGHT, -0.18))
	box(cush, Vector3(0, 0.89, -0.31), Vector3(0.28, 0.16, 0.1), Basis(Vector3.RIGHT, -0.18))
	for sx in [-1.0, 1.0]:
		box(cush, Vector3(sx * 0.24, 0.2, 0.0), Vector3(0.06, 0.1, 0.48))
		box(cush, Vector3(sx * 0.24, 0.5, -0.22), Vector3(0.06, 0.55, 0.15), Basis(Vector3.RIGHT, -0.18))
	var frame := _st()
	for sx in [-0.18, 0.18]:
		box(frame, Vector3(sx, 0.02, 0), Vector3(0.03, 0.03, 0.5))
		box(frame, Vector3(sx, 0.07, 0.15), Vector3(0.03, 0.09, 0.03))
		box(frame, Vector3(sx, 0.07, -0.15), Vector3(0.03, 0.09, 0.03))
		box(frame, Vector3(sx, 0.81, -0.31), Vector3(0.012, 0.1, 0.012))
	return _mesh([[cush, m("denim", Color(0.6, 0.62, 0.68), 2.5, 0.95)], [frame, dark_steel()]])

func _van_door() -> Mesh:
	var panel := _st()
	box(panel, Vector3(0, 0.62, 0), Vector3(0.88, 1.2, 0.06))
	box(panel, Vector3(0, 1.82, 0), Vector3(0.88, 0.12, 0.06))
	for sx in [-1.0, 1.0]:
		box(panel, Vector3(sx * 0.41, 1.5, 0), Vector3(0.06, 0.55, 0.06))
	var glass := _st()
	box(glass, Vector3(0, 1.5, 0), Vector3(0.78, 0.52, 0.01))
	var hw := _st()
	box(hw, Vector3(0.32, 1.0, 0.04), Vector3(0.14, 0.04, 0.03))
	for y in [0.3, 1.55]:
		box(hw, Vector3(-0.45, y, 0), Vector3(0.03, 0.14, 0.04))
	var seal := _st()
	box(seal, Vector3(0, 1.22, 0.031), Vector3(0.82, 0.03, 0.004))
	return _mesh([[panel, m("primer", Color.WHITE, 1.0, 0.7, 0.3)], [glass, glass_m()], [hw, steel()], [seal, rubber()]])

func _headlight() -> Mesh:
	var house := _st()
	box(house, Vector3(0, 0.07, -0.03), Vector3(0.26, 0.14, 0.1))
	var bezel := _st()
	box(bezel, Vector3(0, 0.07, 0.025), Vector3(0.28, 0.16, 0.02))
	var reflector := _st()
	lathe(reflector, [Vector2(0.0, 0.0), Vector2(0.05, 0.02), Vector2(0.06, 0.04)], 18, Vector3(-0.06, 0.07, 0.0))
	var lens := _st()
	box(lens, Vector3(0, 0.07, 0.037), Vector3(0.25, 0.13, 0.006))
	return _mesh([[house, black_plastic()], [bezel, steel()], [reflector, m("metal", Color(1, 1, 1), 4.0, 0.1, 1.0)], [lens, glass_m()]])

func _radio() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.03, -0.06), Vector3(0.18, 0.05, 0.16))
	var face := _st()
	box(face, Vector3(0, 0.03, 0.025), Vector3(0.19, 0.055, 0.012))
	var disp := _st()
	box(disp, Vector3(0.0, 0.035, 0.032), Vector3(0.08, 0.018, 0.002))
	var knobs := _st()
	for i in range(2):
		var x := -0.07 + i * 0.14
		Lib._tube(knobs, Vector3(x, 0.03, 0.03), Vector3(x, 0.03, 0.045), 0.011, 0.01, 14)
	for i in range(5):
		box(knobs, Vector3(-0.04 + i * 0.02, 0.012, 0.033), Vector3(0.014, 0.008, 0.004))
	return _mesh([[body, dark_steel()], [face, black_plastic()], [disp, Lib.color_mat(Color(0.2, 0.6, 0.3), 0.2, 0.0, Color(0.3, 1.0, 0.5), 0.6)], [knobs, steel()]])

func _floor_kit() -> Mesh:
	var planks := _st()
	for k in range(5):
		box(planks, Vector3(0, 0.012 + k * 0.022, 0), Vector3(0.9, 0.02, 0.18))
	var straps := _st()
	for x in [-0.3, 0.3]:
		box(straps, Vector3(x, 0.056, 0), Vector3(0.03, 0.118, 0.186))
	return _mesh([[planks, m("vinyl", Color.WHITE, 1.0, 0.6)], [straps, m("canvas", Color(0.2, 0.3, 0.7), 4.0)]])

func _wall_panels() -> Mesh:
	var face := _st()
	var core := _st()
	for k in range(3):
		var y := 0.03 + k * 0.05
		box(core, Vector3(0, y, 0), Vector3(1.0, 0.035, 0.6))
		box(face, Vector3(0, y + 0.02, 0), Vector3(1.0, 0.006, 0.6))
	return _mesh([[core, m("insulation", Color.WHITE, 1.5, 0.6, 0.6)], [face, c(Color(0.9, 0.88, 0.84), 0.8)]])

func _kitchen_unit() -> Mesh:
	var carc := _st()
	box(carc, Vector3(0, 0.44, 0), Vector3(1.0, 0.84, 0.56))
	var top := _st()
	box(top, Vector3(0, 0.88, 0.01), Vector3(1.04, 0.05, 0.6))
	var doors := _st()
	for i in range(3):
		box(doors, Vector3(-0.33 + i * 0.33, 0.44, 0.285), Vector3(0.31, 0.78, 0.012))
	var hw := _st()
	for i in range(3):
		box(hw, Vector3(-0.22 + i * 0.33, 0.7, 0.296), Vector3(0.1, 0.015, 0.015))
	box(hw, Vector3(0, 0.02, 0.27), Vector3(1.0, 0.04, 0.02))
	return _mesh([[carc, laminate()], [top, m("concrete", Color(0.6, 0.6, 0.62), 2.0, 0.3)], [doors, laminate()], [hw, steel()]])

func _stove_unit() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.05, 0), Vector3(0.5, 0.1, 0.42))
	var grates := _st()
	for x in [-0.12, 0.12]:
		torus(grates, Vector3(x, 0.115, 0), 0.08, 0.006, 20, 5)
		for k in range(4):
			var a := TAU * k / 4.0 + 0.4
			box(grates, Vector3(x + cos(a) * 0.06, 0.115, sin(a) * 0.06), Vector3(0.06, 0.008, 0.01), Basis(Vector3.UP, -a))
	var burners := _st()
	for x in [-0.12, 0.12]:
		lathe(burners, [Vector2(0.04, 0.1), Vector2(0.035, 0.112)], 16, Vector3(x, 0, 0))
	var knobs := _st()
	for x in [-0.12, 0.12]:
		Lib._tube(knobs, Vector3(x, 0.05, 0.21), Vector3(x, 0.05, 0.235), 0.018, 0.015, 12)
	return _mesh([[body, c(Color(0.12, 0.12, 0.13), 0.3, 0.4)], [grates, dark_steel()], [burners, brass()], [knobs, steel()]])

func _sink_unit() -> Mesh:
	var basin := _st()
	lathe(basin, [Vector2(0.0, 0.02), Vector2(0.15, 0.03), Vector2(0.17, 0.16), Vector2(0.2, 0.17)], 28, Vector3.ZERO, false, false)
	var deck := _st()
	box(deck, Vector3(0, 0.17, 0), Vector3(0.46, 0.012, 0.42))
	var tap := _st()
	Lib._tube(tap, Vector3(0, 0.17, -0.17), Vector3(0, 0.35, -0.17), 0.012, 0.012, 10)
	Lib._tube(tap, Vector3(0, 0.35, -0.17), Vector3(0, 0.33, -0.05), 0.011, 0.009, 10)
	box(tap, Vector3(0.05, 0.2, -0.17), Vector3(0.05, 0.015, 0.015))
	var drain := _st()
	Lib._tube(drain, Vector3(0, 0.02, 0), Vector3(0, -0.06, 0), 0.02, 0.02, 10)
	return _mesh([[basin, m("metal", Color(0.9, 0.9, 0.92), 3.0, 0.2, 0.9)], [deck, m("metal", Color(0.85, 0.85, 0.87), 3.0, 0.3, 0.8)], [tap, steel()], [drain, black_plastic()]])

func _coffee_maker() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.02, 0), Vector3(0.2, 0.04, 0.2))
	box(body, Vector3(0, 0.15, -0.07), Vector3(0.2, 0.3, 0.06))
	box(body, Vector3(0, 0.28, 0.0), Vector3(0.2, 0.06, 0.2))
	var jug := _st()
	lathe(jug, [Vector2(0.0, 0.04), Vector2(0.06, 0.045), Vector2(0.065, 0.1), Vector2(0.05, 0.16), Vector2(0.045, 0.17)], 18, Vector3(0, 0, 0.03), false, false)
	var coffee := _st()
	lathe(coffee, [Vector2(0.0, 0.045), Vector2(0.058, 0.05), Vector2(0.062, 0.09), Vector2(0.0, 0.09)], 18, Vector3(0, 0, 0.03), false, true)
	var light := _st()
	box(light, Vector3(0.07, 0.03, 0.101), Vector3(0.015, 0.01, 0.002))
	return _mesh([[body, black_plastic()], [jug, glass_m()], [coffee, c(Color(0.18, 0.09, 0.04), 0.1)], [light, Lib.color_mat(Color(1, 0.2, 0.1), 0.3, 0.0, Color(1, 0.2, 0.1), 1.0)]])

func _fridge_unit() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.6, -0.01), Vector3(0.56, 1.2, 0.56))
	var door := _st()
	box(door, Vector3(0, 0.8, 0.28), Vector3(0.55, 0.78, 0.03))
	box(door, Vector3(0, 0.2, 0.28), Vector3(0.55, 0.36, 0.03))
	var hw := _st()
	box(hw, Vector3(0.22, 0.9, 0.305), Vector3(0.025, 0.3, 0.025))
	box(hw, Vector3(0.22, 0.3, 0.305), Vector3(0.025, 0.14, 0.025))
	var vent := _st()
	for k in range(5):
		box(vent, Vector3(0, 1.1 + k * 0.012, -0.29), Vector3(0.4, 0.006, 0.004))
	return _mesh([[body, white_plastic()], [door, c(Color(0.88, 0.88, 0.86), 0.25)], [hw, steel()], [vent, black_plastic()]])

func _cupboard_unit(sz: Vector3) -> Mesh:
	var carc := _st()
	box(carc, Vector3(0, sz.y * 0.5, 0), sz)
	var door := _st()
	box(door, Vector3(0, sz.y * 0.5, sz.z * 0.5 + 0.008), Vector3(sz.x - 0.03, sz.y - 0.03, 0.014))
	var hw := _st()
	box(hw, Vector3(sz.x * 0.38, sz.y * 0.55, sz.z * 0.5 + 0.022), Vector3(0.018, minf(sz.y * 0.3, 0.2), 0.018))
	return _mesh([[carc, laminate()], [door, laminate()], [hw, steel()]])

func _dinette_kit() -> Mesh:
	var top := _st()
	box(top, Vector3(0, 0.02, 0), Vector3(0.9, 0.04, 0.7))
	var cush := _st()
	for k in range(2):
		box(cush, Vector3(0, 0.1 + k * 0.12, 0), Vector3(0.8, 0.11, 0.42), Basis(Vector3.UP, k * 0.1 - 0.05))
	var leg := _st()
	Lib._tube(leg, Vector3(-0.3, 0.33, 0.2), Vector3(0.35, 0.33, 0.2), 0.025, 0.025, 10)
	lathe(leg, [Vector2(0.12, 0.29), Vector2(0.12, 0.305)], 18, Vector3(0.38, 0, -0.1))
	return _mesh([[top, m("concrete", Color(0.6, 0.6, 0.62), 2.0, 0.3)], [cush, upholstery()], [leg, steel()]])

func _toilet_unit() -> Mesh:
	var bowl := _st()
	lathe(bowl, [Vector2(0.12, 0.0), Vector2(0.15, 0.05), Vector2(0.17, 0.3), Vector2(0.19, 0.38)], 22)
	var tank := _st()
	box(tank, Vector3(0, 0.26, -0.2), Vector3(0.36, 0.52, 0.12))
	var seat := _st()
	torus(seat, Vector3(0, 0.395, 0.0), 0.15, 0.025, 22, 6)
	box(seat, Vector3(0, 0.55, -0.12), Vector3(0.34, 0.3, 0.025), Basis(Vector3.RIGHT, -0.25))
	var btn := _st()
	lathe(btn, [Vector2(0.02, 0.52), Vector2(0.02, 0.53)], 12, Vector3(0, 0, -0.2))
	return _mesh([[bowl, c(Color(0.96, 0.96, 0.96), 0.12)], [tank, c(Color(0.94, 0.94, 0.94), 0.15)], [seat, c(Color(0.9, 0.9, 0.88), 0.3)], [btn, steel()]])

func _bed_frame() -> Mesh:
	var slats := _st()
	for k in range(4):
		box(slats, Vector3(0, 0.015 + k * 0.03, 0), Vector3(1.2, 0.025, 0.12), Basis(Vector3.UP, (k - 1.5) * 0.04))
	var sides := _st()
	for z in [-0.22, 0.22]:
		box(sides, Vector3(0, 0.07, z), Vector3(1.3, 0.14, 0.08))
	var hw := _st()
	for x in [-0.5, 0.5]:
		box(hw, Vector3(x, 0.15, 0), Vector3(0.03, 0.02, 0.52))
	return _mesh([[slats, wood()], [sides, laminate()], [hw, dark_steel()]])

func _mattress() -> Mesh:
	var s := _st()
	box(s, Vector3(0, 0.09, 0), Vector3(0.95, 0.16, 0.65))
	ellipsoid(s, Vector3(0, 0.25, 0), Vector3(0.45, 0.1, 0.32), 6, 14)
	var tie := _st()
	for x in [-0.3, 0.3]:
		box(tie, Vector3(x, 0.17, 0), Vector3(0.03, 0.34, 0.67))
	return _mesh([[s, m("upholstery", Color(1.6, 1.6, 1.55), 3.0, 0.95)], [tie, m("canvas", Color(0.7, 0.3, 0.2), 4.0)]])

func _ceiling_light() -> Mesh:
	var base := _st()
	lathe(base, [Vector2(0.15, 0.0), Vector2(0.155, 0.02)], 22)
	var dome := _st()
	lathe(dome, [Vector2(0.14, 0.02), Vector2(0.12, 0.05), Vector2(0.06, 0.075), Vector2(0.0, 0.08)], 22, Vector3.ZERO, false, false)
	return _mesh([[base, white_plastic()], [dome, Lib.color_mat(Color(1, 0.97, 0.88), 0.2, 0.0, Color(1, 0.92, 0.75), 0.3)]])

func _water_tank() -> Mesh:
	var t := _st()
	box(t, Vector3(0, 0.18, 0), Vector3(0.7, 0.32, 0.4))
	for sx in [-1.0, 1.0]:
		Lib._tube(t, Vector3(sx * 0.35, 0.02, 0.2), Vector3(sx * 0.35, 0.34, 0.2), 0.02, 0.02, 8)
		Lib._tube(t, Vector3(sx * 0.35, 0.02, -0.2), Vector3(sx * 0.35, 0.34, -0.2), 0.02, 0.02, 8)
	var cap := _st()
	lathe(cap, [Vector2(0.045, 0.34), Vector2(0.045, 0.37), Vector2(0.04, 0.375)], 16, Vector3(0.2, 0, 0))
	Lib._tube(cap, Vector3(-0.35, 0.06, 0), Vector3(-0.42, 0.06, 0), 0.015, 0.015, 8)
	return _mesh([[t, c(Color(0.92, 0.92, 0.9, 1.0), 0.5)], [cap, c(Color(0.2, 0.4, 0.75), 0.4)]])

func _solar_panel() -> Mesh:
	var cells := _st()
	for i in range(6):
		for j in range(4):
			box(cells, Vector3(-0.42 + i * 0.168, 0.032, -0.21 + j * 0.14), Vector3(0.16, 0.004, 0.132))
	var back := _st()
	box(back, Vector3(0, 0.02, 0), Vector3(1.0, 0.02, 0.6))
	var frame := _st()
	for sz in [-1.0, 1.0]:
		box(frame, Vector3(0, 0.025, sz * 0.3), Vector3(1.02, 0.04, 0.02))
	for sx in [-1.0, 1.0]:
		box(frame, Vector3(sx * 0.5, 0.025, 0), Vector3(0.02, 0.04, 0.6))
	return _mesh([[cells, Lib.color_mat(Color(0.06, 0.1, 0.26), 0.12, 0.6)], [back, c(Color(0.85, 0.85, 0.85), 0.6)], [frame, m("metal", Color(0.85, 0.86, 0.88), 6.0, 0.3, 0.9)]])

func _bull_bar() -> Mesh:
	var s := _st()
	for x in [-0.45, 0.45]:
		Lib._tube(s, Vector3(x, 0.0, 0), Vector3(x, 0.62, 0), 0.03, 0.03, 12)
		torus(s, Vector3(x, 0.62, 0), 0.0, 0.03, 4, 6)
	Lib._tube(s, Vector3(-0.5, 0.6, 0), Vector3(0.5, 0.6, 0), 0.03, 0.03, 12)
	Lib._tube(s, Vector3(-0.5, 0.2, 0), Vector3(0.5, 0.2, 0), 0.03, 0.03, 12)
	Lib._tube(s, Vector3(-0.45, 0.62, 0), Vector3(-0.2, 0.75, 0), 0.025, 0.025, 10)
	Lib._tube(s, Vector3(0.45, 0.62, 0), Vector3(0.2, 0.75, 0), 0.025, 0.025, 10)
	Lib._tube(s, Vector3(-0.2, 0.75, 0), Vector3(0.2, 0.75, 0), 0.025, 0.025, 10)
	var plate := _st()
	box(plate, Vector3(0, 0.1, -0.06), Vector3(0.8, 0.02, 0.12))
	return _mesh([[s, m("metal", Color(0.9, 0.9, 0.92), 6.0, 0.18, 0.95)], [plate, dark_steel()]])

func _heater_unit() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.15, 0), Vector3(0.36, 0.3, 0.2))
	var grille := _st()
	for k in range(7):
		box(grille, Vector3(0, 0.06 + k * 0.032, 0.102), Vector3(0.3, 0.012, 0.006))
	var knob := _st()
	Lib._tube(knob, Vector3(0.14, 0.27, 0.1), Vector3(0.14, 0.27, 0.12), 0.015, 0.013, 12)
	var hose := _st()
	Lib._tube(hose, Vector3(-0.18, 0.1, 0), Vector3(-0.3, 0.05, 0.08), 0.03, 0.03, 10)
	return _mesh([[body, paint(Color(0.55, 0.2, 0.14))], [grille, steel()], [knob, black_plastic()], [hose, m("metal", Color(0.8, 0.8, 0.8), 12.0, 0.4, 0.8)]])

func _fuel_tank_xl() -> Mesh:
	var t := _st()
	box(t, Vector3(0, 0.12, 0), Vector3(0.9, 0.22, 0.5))
	ellipsoid(t, Vector3(-0.45, 0.12, 0), Vector3(0.03, 0.11, 0.25), 6, 10)
	ellipsoid(t, Vector3(0.45, 0.12, 0), Vector3(0.03, 0.11, 0.25), 6, 10)
	var straps := _st()
	for x in [-0.25, 0.25]:
		box(straps, Vector3(x, 0.12, 0), Vector3(0.04, 0.24, 0.52))
	var neck := _st()
	Lib._tube(neck, Vector3(0.3, 0.22, 0.15), Vector3(0.38, 0.3, 0.15), 0.03, 0.03, 10)
	return _mesh([[t, m("metal", Color(0.3, 0.31, 0.32), 4.0, 0.5, 0.7)], [straps, m("rust", Color.WHITE, 6.0)], [neck, steel()]])

func _tune_kit() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.05, 0), Vector3(0.34, 0.1, 0.22))
	var turbo := _st()
	torus(turbo, Vector3(0, 0.15, 0), 0.06, 0.035, 18, 8, Vector3.FORWARD)
	Lib._tube(turbo, Vector3(0, 0.15, 0.0), Vector3(0, 0.15, 0.08), 0.03, 0.035, 12)
	Lib._tube(turbo, Vector3(0.06, 0.15, 0), Vector3(0.14, 0.17, 0), 0.025, 0.025, 10)
	var plugs := _st()
	for i in range(4):
		lathe(plugs, [Vector2(0.008, 0.1), Vector2(0.008, 0.13), Vector2(0.004, 0.15)], 8, Vector3(-0.12 + i * 0.025, 0, 0.07))
	return _mesh([[b, m("cardboard", Color(1.0, 0.45, 0.35), 4.0)], [turbo, m("metal", Color(0.75, 0.75, 0.78), 6.0, 0.3, 0.9)], [plugs, c(Color(0.9, 0.9, 0.88), 0.3)]])

# ------------------------------------------------------------------ first-person arm
## Right forearm + hand gripping at the origin; the forearm runs back toward +Z/-Y.
func arm_mesh() -> Mesh:
	if _meshes.has("__arm"):
		return _meshes["__arm"]
	var skin := _st()
	# closed fist around the grip: palm block, four knuckles and a thumb over the front
	ellipsoid(skin, Vector3(0.012, -0.005, 0.012), Vector3(0.042, 0.052, 0.038), 8, 12)
	for i in range(4):
		var y := 0.032 - i * 0.021
		ellipsoid(skin, Vector3(-0.012, y, -0.03), Vector3(0.022, 0.012, 0.016), 5, 8)
		ellipsoid(skin, Vector3(0.022, y, -0.022), Vector3(0.014, 0.011, 0.02), 5, 8)
	Lib._tube(skin, Vector3(0.03, 0.035, 0.01), Vector3(0.0, 0.045, -0.035), 0.012, 0.01, 8)
	Lib._tube(skin, Vector3(0, -0.02, 0.03), Vector3(0.0, -0.09, 0.15), 0.033, 0.036, 12)
	var sleeve := _st()
	Lib._tube(sleeve, Vector3(0.0, -0.08, 0.13), Vector3(0.02, -0.22, 0.42), 0.05, 0.065, 14)
	var cuff_mesh := _mesh([[sleeve, m("plaid", Color.WHITE, 6.0, 0.9)]])
	var out := _mesh([[skin, m("skin", Color(0.74, 0.6, 0.5), 8.0, 0.55)]])
	var st := _st()
	st.append_from(cuff_mesh, 0, Transform3D.IDENTITY)
	st.generate_tangents()
	st.commit(out)
	out.surface_set_material(1, m("plaid", Color.WHITE, 6.0, 0.9))
	_meshes["__arm"] = out
	return out

# ------------------------------------------------------------------ icons
func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	if not _queue.has(id) and Data_has(id):
		_queue.append(id)
	return null

func Data_has(id: String) -> bool:
	return id != ""

func _ensure_stage() -> void:
	if _vp:
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(128, 128)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.7, 0.6, 0)
	key.light_energy = 1.4
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, -2.4, 0)
	fill.light_energy = 0.5
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)

func _process(_d: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render_next()

func _aabb_of(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		var a := (xf * vi.transform) * vi.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for ch in n.get_children():
		if ch is Node3D:
			_aabb_of(ch, xf * (n as Node3D).transform if n is Node3D else xf, acc)

func _render_next() -> void:
	_busy = true
	_ensure_stage()
	var id: String = _queue.pop_front()
	for ch in _stage.get_children():
		ch.queue_free()
	var inst := instance(id)
	# lay long tools diagonally for a classic inventory look
	if id in ["axe", "pickaxe", "hammer", "knife", "bow", "rifle", "fishing_rod", "flashlight", "arrow"]:
		inst.rotation = Vector3(0, 0, -PI * 0.25)
	_stage.add_child(inst)
	var acc := [null]
	for ch in inst.get_children():
		_aabb_of(ch, inst.transform, acc)
	var box_aabb: AABB = acc[0] if acc[0] != null else AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
	var center := box_aabb.get_center()
	var radius := box_aabb.size.length() * 0.5
	var dir := Vector3(0.55, 0.6, 1.0).normalized()
	if id in ["axe", "pickaxe", "hammer", "knife", "bow", "rifle", "fishing_rod", "flashlight", "arrow"]:
		dir = Vector3(0.15, 0.25, 1.0).normalized()
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) * 1.05
	_cam.position = center + dir * dist
	_cam.look_at(center, Vector3.UP)
	_cam.near = dist * 0.05
	_cam.far = dist * 4.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img and not img.is_empty():
		img.generate_mipmaps()
		_icons[id] = ImageTexture.create_from_image(img)
		icon_ready.emit(id)
	_busy = false

func prewarm() -> void:
	var Data = load("res://scripts/data.gd")
	for id in Data.ITEMS:
		icon(id)
