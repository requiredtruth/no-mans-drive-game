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

var _outline_mat: ShaderMaterial

func set_outline(n: Node, on: bool) -> void:
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = preload("res://shaders/item_outline.gdshader")
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = _outline_mat if on else null
	for child in n.get_children():
		set_outline(child, on)

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
		# 1.8 performance parts and van add-ons
		"vehicle_engine_block_t2": return _engine_block_tier(2)
		"vehicle_engine_block_t3": return _engine_block_tier(3)
		"vehicle_turbocharger": return _turbo()
		"vehicle_supercharger": return _supercharger()
		"vehicle_nos_kit": return _nos_kit()
		"vehicle_dual_fan_radiator": return _radiator_fans()
		"vehicle_armored_radiator": return _radiator_armored()
		"vehicle_suspension_part": return _coilover()
		"vehicle_leaf_spring": return _leaf_spring()
		"vehicle_lithium_battery": return _lithium_battery()
		"vehicle_tire_sand": return _tire_sand()
		"vehicle_tire_solid": return _tire_solid()
		"vehicle_roof_rack": return _roof_rack()
		"vehicle_mod_cargo_box": return _cargo_box()
		"vehicle_mod_roof_tent": return _roof_tent()
		"vehicle_side_panniers": return _panniers()
		"vehicle_mod_jerry_holder": return _jerry_holder()
		"vehicle_mod_spare_mount": return _spare_mount()
		"vehicle_mod_snorkel": return _snorkel()
		"vehicle_mod_winch": return _winch()
		"vehicle_mod_ram_plow": return _ram_plow()
		"vehicle_mod_windshield_mesh": return _windshield_mesh()
		"vehicle_mod_door_armor": return _door_armor()
		"vehicle_mod_mud_flaps": return _mud_flaps()
		"mod_underglow_neon_kit": return _underglow_kit()
		"vehicle_tow_hitch": return _tow_hitch()
		"chips": return _chips()
		"tinned_hotdogs": return _can(Color("c84a2a"), Color("f0d040"), 0.06, 0.13)
		"can_of_cashews": return _can(Color("d8b070"), Color("2a4a8a"), 0.05, 0.09)
		"peaches_oreilly": return _can(Color("f0a050"), Color("3a8a3a"), 0.055, 0.11)
		"berry_juice": return _bottle(Color(0.55, 0.12, 0.4, 0.8), Color("8a2a6a"))
		"mocha_cola": return _can(Color("5a3220"), Color("e8d8c0"), 0.033, 0.12)
		"emergency_ration_pack": return _wrapper(Color("6a7a40"), Color("e8e0c0"), Vector3(0.16, 0.035, 0.1))
		"jason_s_choccy_block": return _wrapper(Color("6a2a18"), Color("e8c040"), Vector3(0.15, 0.018, 0.07))
		"energy_bar": return _wrapper(Color("2a64b8"), Color("f0c020"), Vector3(0.13, 0.022, 0.045))
		"jerky": return _pouch(Color("5a2a14"), Color("d8a040"))
		"apple": return _apple()
		"bread": return _bread()
		"instant_noodles": return _noodle_cup(false)
		"hot_noodles": return _noodle_cup(true)
		"painkillers": return _pill_bottle()
		"duct_tape": return _duct_tape()
		"crowbar": return _crowbar()
		"binoculars": return _binoculars()
	var ext := _build17(id, rng)
	if ext:
		return ext
	var st := _st()
	box(st, Vector3(0, 0.05, 0), Vector3(0.1, 0.1, 0.1))
	return _mesh([[st, c(Color.GRAY)]])

# ------------------------------------------------------------------ snacks, supplies, tools
## A crinkled foil snack bag with crimped seams.
func _chips() -> Mesh:
	var bag := _st()
	ellipsoid(bag, Vector3(0, 0.1, 0), Vector3(0.085, 0.095, 0.032), 10, 18, 0.05, 7)
	var seams := _st()
	for y in [0.008, 0.192]:
		box(seams, Vector3(0, y, 0), Vector3(0.16, 0.016, 0.006))
		for k in range(8):
			box(seams, Vector3(-0.07 + k * 0.02, y, 0.0035), Vector3(0.004, 0.014, 0.001))
	var label := _st()
	ellipsoid(label, Vector3(0, 0.1, 0.0255), Vector3(0.05, 0.04, 0.008), 6, 14)
	return _mesh([[bag, m("metal", Color(0.95, 0.75, 0.15), 3.0, 0.3, 0.7)], [seams, m("metal", Color(0.9, 0.7, 0.2), 6.0, 0.35, 0.6)], [label, paint(Color(0.85, 0.15, 0.1))]])

## A wrapped bar: plastic wrapper, crimped ends, a printed band.
func _wrapper(col: Color, band: Color, sz: Vector3) -> Mesh:
	var w := _st()
	box(w, Vector3(0, sz.y * 0.5, 0), Vector3(sz.x - 0.02, sz.y, sz.z))
	ellipsoid(w, Vector3(0, sz.y * 0.55, 0), Vector3((sz.x - 0.02) * 0.5, sz.y * 0.5, sz.z * 0.48), 6, 14)
	var ends := _st()
	for s in [-1.0, 1.0]:
		taper(ends, 0.0, Vector2(0.004, sz.z * 0.9), sz.y, Vector2(0.004, sz.z * 0.9), Vector2(s * (sz.x * 0.5 - 0.006), 0), Vector2(s * (sz.x * 0.5 - 0.006), 0))
	var b := _st()
	box(b, Vector3(0, sz.y + 0.0005, 0), Vector3(sz.x * 0.4, 0.001, sz.z * 0.7))
	return _mesh([[w, m("paint", col, 3.0, 0.3, 0.4)], [ends, c(col.darkened(0.2), 0.4)], [b, paint(band)]])

## A resealable pouch standing on its gusset.
func _pouch(col: Color, window: Color) -> Mesh:
	var p := _st()
	taper(p, 0.0, Vector2(0.1, 0.04), 0.15, Vector2(0.1, 0.008))
	var top := _st()
	box(top, Vector3(0, 0.155, 0), Vector3(0.102, 0.012, 0.01))
	var win := _st()
	box(win, Vector3(0, 0.07, 0.0175), Vector3(0.06, 0.06, 0.002), Basis(Vector3.RIGHT, -0.2))
	return _mesh([[p, paint(col)], [top, c(col.darkened(0.3), 0.5)], [win, Lib.color_mat(window, 0.4)]])

func _apple() -> Mesh:
	var a := _st()
	lathe(a, [Vector2(0.0, 0.004), Vector2(0.018, 0.0), Vector2(0.036, 0.012), Vector2(0.044, 0.035), Vector2(0.042, 0.058), Vector2(0.03, 0.072), Vector2(0.012, 0.07), Vector2(0.0, 0.062)], 20)
	var stem := _st()
	Lib._tube(stem, Vector3(0, 0.06, 0), Vector3(0.004, 0.085, 0.002), 0.003, 0.0025, 6)
	var leaf := _st()
	ellipsoid(leaf, Vector3(0.016, 0.082, 0), Vector3(0.014, 0.002, 0.007), 4, 8)
	return _mesh([[a, m("paint", Color(0.78, 0.12, 0.1), 2.0, 0.35, 0.05)], [stem, c(Color(0.35, 0.22, 0.12))], [leaf, c(Color(0.25, 0.5, 0.18), 0.6)]])

func _bread() -> Mesh:
	var loaf := _st()
	ellipsoid(loaf, Vector3(0, 0.055, 0), Vector3(0.14, 0.06, 0.07), 10, 18, 0.03, 11)
	box(loaf, Vector3(0, 0.02, 0), Vector3(0.26, 0.04, 0.13))
	var cuts := _st()
	for k in range(4):
		box(cuts, Vector3(-0.075 + k * 0.05, 0.112, 0), Vector3(0.012, 0.006, 0.09), Basis(Vector3.UP, 0.5))
	return _mesh([[loaf, m("leather", Color(1.25, 0.85, 0.5), 3.0, 0.8)], [cuts, c(Color(0.95, 0.85, 0.6), 0.9)]])

func _noodle_cup(hot: bool) -> Mesh:
	var cup := _st()
	lathe(cup, [Vector2(0.0, 0.0), Vector2(0.038, 0.0), Vector2(0.05, 0.1), Vector2(0.052, 0.102)], 22, Vector3.ZERO, true, false)
	var band := _st()
	lathe(band, [Vector2(0.0425, 0.03), Vector2(0.0475, 0.075)], 22, Vector3.ZERO, false, false)
	var top := _st()
	if hot:
		_disc(top, Vector3(0, 0.092, 0), 0.048, Vector3.UP, 22)
		var noodles := _st()
		for k in range(9):
			var a := TAU * k / 9.0
			torus(noodles, Vector3(cos(a) * 0.022, 0.094, sin(a) * 0.022), 0.012, 0.003, 10, 4)
		return _mesh([[cup, white_plastic()], [band, paint(Color(0.85, 0.15, 0.1))], [top, Lib.color_mat(Color(0.8, 0.55, 0.25), 0.2)], [noodles, c(Color(0.95, 0.85, 0.55), 0.5)]])
	_disc(top, Vector3(0, 0.103, 0), 0.053, Vector3.UP, 22)
	return _mesh([[cup, white_plastic()], [band, paint(Color(0.85, 0.15, 0.1))], [top, m("metal", Color(0.9, 0.9, 0.92), 5.0, 0.3, 0.8)]])

func _pill_bottle() -> Mesh:
	var b := _st()
	lathe(b, [Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.026, 0.004), Vector2(0.026, 0.07), Vector2(0.02, 0.074)], 18)
	var cap := _st()
	lathe(cap, [Vector2(0.027, 0.072), Vector2(0.027, 0.092), Vector2(0.024, 0.095)], 18)
	var label := _st()
	lathe(label, [Vector2(0.0265, 0.015), Vector2(0.0265, 0.058)], 18, Vector3.ZERO, false, false)
	var amber := Lib.color_mat(Color(0.85, 0.42, 0.08, 0.8), 0.15)
	return _mesh([[b, amber], [cap, white_plastic()], [label, paint(Color(0.95, 0.95, 0.92))]])

func _duct_tape() -> Mesh:
	var roll := _st()
	lathe(roll, [Vector2(0.032, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.048), Vector2(0.032, 0.048)], 26, Vector3.ZERO, false, false)
	lathe(roll, [Vector2(0.032, 0.048), Vector2(0.032, 0.0)], 26, Vector3.ZERO, false, false)
	var core := _st()
	lathe(core, [Vector2(0.026, 0.0), Vector2(0.032, 0.0), Vector2(0.032, 0.049), Vector2(0.026, 0.049)], 22, Vector3.ZERO, false, false)
	var tail := _st()
	box(tail, Vector3(0.056, 0.024, 0.02), Vector3(0.002, 0.048, 0.04))
	return _mesh([[roll, m("metal", Color(0.72, 0.74, 0.76), 4.0, 0.5, 0.4)], [core, m("cardboard", Color.WHITE, 4.0)], [tail, m("metal", Color(0.7, 0.72, 0.74), 4.0, 0.5, 0.4)]])

func _crowbar() -> Mesh:
	var bar := _st()
	Lib._tube(bar, Vector3(0, 0.0, 0), Vector3(0, 0.62, 0), 0.011, 0.011, 8)
	# hooked claw at the top, flat chisel at the bottom
	var prev := Vector3(0, 0.62, 0)
	for k in range(1, 7):
		var a := PI * k / 6.0
		var p := Vector3(0.045 - cos(a) * 0.045, 0.62 + sin(a) * 0.05, 0)
		Lib._tube(bar, prev, p, 0.011, 0.011, 8)
		prev = p
	box(bar, Vector3(0.093, 0.6, 0), Vector3(0.012, 0.03, 0.024), Basis(Vector3.FORWARD, 0.4))
	box(bar, Vector3(0.012, -0.01, 0), Vector3(0.03, 0.02, 0.022), Basis(Vector3.FORWARD, 0.6))
	var grip := _st()
	Lib._tube(grip, Vector3(0, 0.05, 0), Vector3(0, 0.2, 0), 0.015, 0.015, 10)
	return _mesh([[bar, paint(Color(0.7, 0.12, 0.08))], [grip, rubber()]])

func _binoculars() -> Mesh:
	var body := _st()
	for x in [-0.035, 0.035]:
		Lib._tube(body, Vector3(x, 0.03, -0.04), Vector3(x, 0.03, 0.05), 0.026, 0.026, 16)
		Lib._tube(body, Vector3(x, 0.03, 0.05), Vector3(x, 0.03, 0.07), 0.026, 0.021, 16)
	box(body, Vector3(0, 0.03, 0.0), Vector3(0.05, 0.016, 0.05))
	var trim := _st()
	for x in [-0.035, 0.035]:
		Lib._tube(trim, Vector3(x, 0.03, -0.05), Vector3(x, 0.03, -0.04), 0.028, 0.028, 16)
	Lib._tube(trim, Vector3(0, 0.048, -0.02), Vector3(0, 0.048, 0.03), 0.008, 0.008, 10)
	var lens := _st()
	for x in [-0.035, 0.035]:
		_disc(lens, Vector3(x, 0.03, -0.0505), 0.022, Vector3.FORWARD, 16)
		_disc(lens, Vector3(x, 0.03, 0.0705), 0.017, Vector3.BACK, 16)
	return _mesh([[body, rubber()], [trim, dark_steel()], [lens, glass_m()]])

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
	if n is GeometryInstance3D:
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
	if _side_view(id):
		inst.rotation = Vector3(PI * 0.25, 0, 0)
	elif _is_long(id):
		inst.rotation = Vector3(0, 0, -PI * 0.25)
	_stage.add_child(inst)
	var acc := [null]
	for ch in inst.get_children():
		_aabb_of(ch, inst.transform, acc)
	var box_aabb: AABB = acc[0] if acc[0] != null else AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
	var center := box_aabb.get_center()
	var radius := box_aabb.size.length() * 0.5
	var dir := Vector3(0.55, 0.6, 1.0).normalized()
	if _side_view(id):
		dir = Vector3(1.0, 0.3, 0.12).normalized()
	elif _is_long(id):
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

## Guns, blades and axes read best seen from the side.
func _side_view(id: String) -> bool:
	var d: Dictionary = load("res://scripts/data.gd").ITEMS.get(id, {})
	return id != "fishing_rod" and d.get("kind", "") == "tool" and d.get("grip", "") != "bow" and (d.has("reach") or d.has("ammo")) and id != "rock"

func _is_long(id: String) -> bool:
	if id in ["axe", "pickaxe", "hammer", "knife", "bow", "rifle", "fishing_rod", "flashlight", "arrow"]:
		return true
	var d: Dictionary = load("res://scripts/data.gd").ITEMS.get(id, {})
	return d.get("kind", "") == "tool" and (d.has("reach") or d.get("grip", "") in ["gun", "bow", "pistol", "knife"]) and id != "rock"

func prewarm() -> void:
	var Data = load("res://scripts/data.gd")
	for id in Data.ITEMS:
		icon(id)

# ================================================================== 1.7: item backlog models
func _build17(id: String, rng: RandomNumberGenerator) -> Mesh:
	match id:
		# raw resources
		"seasoned_hardwood": return _split_log(Color(0.75, 0.52, 0.32), rng)
		"drift_wood": return _driftwood(rng)
		"stick": return _stick(rng)
		"rock": return _rock_tool(rng)
		"charcoal": return _lumps(rng, c(Color(0.07, 0.07, 0.075), 0.95), 5, 0.035)
		"copper_ore": return _ore(rng, Color(0.45, 0.42, 0.38), Color(0.25, 0.62, 0.45), true)
		"lead_ore": return _ore(rng, Color(0.42, 0.43, 0.46), Color(0.62, 0.64, 0.7), true)
		"sulphur_ore": return _ore(rng, Color(0.55, 0.5, 0.38), Color(0.95, 0.85, 0.2), false)
		"obsidian_chunk": return _obsidian(rng)
		"copper_ingot": return _ingot(Color(0.85, 0.45, 0.25))
		"lead_ingot": return _ingot(Color(0.5, 0.52, 0.56))
		"sulphur": return _powder_pile(Color(0.95, 0.85, 0.22))
		"saltpeter": return _powder_pile(Color(0.94, 0.93, 0.9))
		"gunpowder": return _powder_tin()
		"raw_rubber": return _rubber_ball()
		"cured_rubber_sheet": return _sheet_roll(c(Color(0.06, 0.06, 0.06), 0.8), 0.04)
		"heavy_canvas": return _folded(m("canvas", Color(0.72, 0.66, 0.5), 4.0, 0.95), 3)
		"cured_leather": return _folded(m("leather", Color(0.75, 0.5, 0.32), 4.0, 0.6), 2)
		"animal_fat": return _fat()
		"sinew": return _sinew(false)
		"hunt_sinew_cord": return _sinew(true)
		"bone_fragments": return _bones(rng)
		"empty_glass_jar": return _jar(Color(0, 0, 0, 0), Color(0.75, 0.75, 0.78))
		"hunt_animal_grease": return _jar(Color(0.92, 0.85, 0.6, 0.95), Color(0.55, 0.4, 0.25))
		"industrial_solvent": return _chem_jug(Color(0.25, 0.45, 0.75), Color(0.95, 0.75, 0.1))
		"brake_fluid": return _chem_bottle(Color(0.9, 0.9, 0.88), Color(0.85, 0.6, 0.1))
		"coolant_t1": return _chem_jug(Color(0.2, 0.75, 0.35), Color(0.95, 0.95, 0.9))
		"mod_coolant_jug_20l": return _big_jug(Color(0.2, 0.7, 0.35))
		"crude_oil": return _drum_can(Color(0.08, 0.08, 0.08))
		# hunting
		"hunt_deer_antlers": return _antlers()
		"hunt_wolf_pelt": return _pelt(Color(0.62, 0.6, 0.56), false)
		"hunt_cured_pelt": return _pelt(Color(0.78, 0.75, 0.7), true)
		"hunt_predator_claws": return _claws()
		"hunt_bone_needle": return _needles()
		"hunt_hide_strip": return _strips()
		"hunt_predator_skull": return _skull()
		# meat
		"raw_venison": return _steak(Color(0.62, 0.12, 0.15), Color(0.9, 0.82, 0.78))
		"cooked_venison": return _steak(Color(0.4, 0.2, 0.1), Color(0.7, 0.5, 0.3))
		"raw_wolf_meat": return _steak(Color(0.55, 0.14, 0.16), Color(0.8, 0.7, 0.65))
		"cooked_wolf_meat": return _steak(Color(0.32, 0.17, 0.09), Color(0.6, 0.42, 0.25))
		"raw_rabbit_meat": return _drumstick(Color(0.85, 0.5, 0.48), false)
		"cooked_rabbit_meat": return _drumstick(Color(0.62, 0.38, 0.18), true)
		"raw_bird_meat": return _drumstick(Color(0.92, 0.66, 0.58), false)
		"cooked_bird_meat": return _drumstick(Color(0.72, 0.45, 0.2), true)
		# produce
		"carrot": return _carrot()
		"corn_cob": return _corn(false)
		"roasted_corn": return _corn(true)
		"red_berry": return _berries_col(Color(0.78, 0.1, 0.14))
		"yellow_berry": return _berries_col(Color(0.95, 0.75, 0.15))
		"golden_mystic_berry": return _golden_berry()
		"carrot_seeds": return _packet(Color(0.9, 0.45, 0.12))
		"corn_seeds": return _packet(Color(0.9, 0.78, 0.2))
		# drinks and snacks
		"crimson_chaos_energy": return _tall_can(Color(0.65, 0.04, 0.08), Color(0.1, 0.1, 0.1))
		"digital_soda": return _can(Color(0.1, 0.55, 0.9), Color(0.95, 0.95, 0.95), 0.033, 0.12)
		"matrix_cola": return _can(Color(0.06, 0.08, 0.06), Color(0.1, 0.85, 0.25), 0.033, 0.12)
		"zap_power_juice": return _bottle(Color(0.95, 0.88, 0.15, 0.85), Color("1a1a1a"))
		"sterling_organic_milk": return _milk(Color(0.25, 0.5, 0.85), false)
		"spoiled_milk": return _milk(Color(0.55, 0.6, 0.3), true)
		"tommy_s_crunch": return _cereal_box(Color(0.9, 0.38, 0.1), Color(0.98, 0.85, 0.2))
		"feline_feast_cat_food": return _can(Color(0.55, 0.3, 0.65), Color(0.95, 0.85, 0.3), 0.042, 0.04)
		"canine_chow_dog_food": return _can(Color(0.65, 0.35, 0.12), Color(0.9, 0.9, 0.85), 0.05, 0.11)
		"thermos_coffee": return _thermos(true)
		"camp_insulated_thermos": return _thermos(false)
		# medical
		"sterile_gauze": return _gauze()
		"morphine_injector": return _injector(Color(0.25, 0.4, 0.75))
		"adrenaline_injector": return _injector(Color(0.95, 0.62, 0.1))
		"antidote": return _vial(Color(0.25, 0.7, 0.4, 0.8))
		"splint": return _splint()
		"advanced_trauma_kit": return _trauma_kit()
		"water_purification_tablets": return _tablets()
		"gear_hand_warmer": return _warmer()
		"gear_space_blanket": return _space_blanket()
		"camp_waterproof_matches": return _matches()
		# firearms and ammo
		"combat_19_pistol": return _pistol(Color(0.12, 0.12, 0.13), 0.13, false)
		"pocket_pistol": return _pistol(Color(0.6, 0.62, 0.65), 0.085, false)
		"magnum": return _pistol(Color(0.72, 0.74, 0.78), 0.16, true)
		"double_barrel_shotgun": return _shotgun()
		"compound_bow": return _compound_bow()
		"ammo_box_9mm": return _ammo_box(Color(0.15, 0.35, 0.65), Color(0.85, 0.7, 0.3))
		"ammo_box_25_acp": return _ammo_box(Color(0.6, 0.55, 0.15), Color(0.85, 0.75, 0.35))
		"ammo_box_44": return _ammo_box(Color(0.55, 0.12, 0.1), Color(0.8, 0.62, 0.3))
		"ammo_box_12_gauge": return _shells()
		# tools and melee
		"fire_axe": return _fire_axe()
		"stone_hatchet": return _stone_tool(false)
		"stone_pickaxe": return _stone_tool(true)
		"heavy_pickaxe": return _heavy_pick()
		"sledge_hammer": return _sledge()
		"metal_hammer": return _framing_hammer()
		"machete": return _blade_tool(0.42, 0.045, Color(0.12, 0.12, 0.12), true)
		"combat_knife": return _blade_tool(0.17, 0.03, Color(0.08, 0.08, 0.08), false)
		"kitchen_knife": return _blade_tool(0.19, 0.035, Color(0.1, 0.1, 0.1), false, true)
		"spiked_bat": return _spiked_bat()
		"saw": return _saw()
		"multi_tool_wrench": return _wrench()
		"torch": return _torch()
		"road_flare": return _flare()
		"chem_light_stick": return _glowstick()
		"camp_folding_lantern": return _camp_lantern()
		# navigation and electronics in the hand
		"nav_pocket_compass": return _compass()
		"nav_paper_roadmap": return _roadmap()
		"nav_wristwatch": return _watch(Color(0.75, 0.75, 0.78), Color(0.95, 0.94, 0.9))
		"nav_survival_watch": return _watch(Color(0.12, 0.12, 0.12), Color(0.2, 0.3, 0.25))
		"camp_handcrank_radio": return _crank_radio()
		"mod_retro_gps": return _gps()
		# camp cooking
		"camp_cast_iron_skillet": return _skillet()
		"camp_cooking_pot": return _pot()
		"camp_coffee_percolator": return _percolator()
		"camp_spork": return _spork()
		# apparel
		"ripped_t_shirt": return _folded_shirt(Color(0.82, 0.8, 0.74), true)
		"survivor_clothes": return _folded_shirt(Color(0.42, 0.42, 0.32), false)
		"construction_clothes": return _hivis()
		"red_jacket": return _jacket_col(Color(0.7, 0.14, 0.12))
		"blue_jacket": return _jacket_col(Color(0.16, 0.28, 0.55))
		"leather_vest": return _vest()
		"gear_wool_poncho": return _poncho(m("plaid", Color(0.75, 0.55, 0.4), 3.0, 1.0))
		"gear_rain_poncho": return _poncho(c(Color(0.95, 0.8, 0.1), 0.35))
		"tactical_helmet": return _helmet()
		"tactical_headlamp": return _headlamp()
		"gear_sandstorm_goggles": return _goggles()
		"makeshift_bag": return _sack_bag()
		"brown_rucksack": return _backpack_v(Color(0.45, 0.32, 0.2), 1.0, false)
		"hiking_backpack": return _backpack_v(Color(0.16, 0.42, 0.62), 1.15, true)
		"military_backpack": return _backpack_v(Color(0.3, 0.36, 0.24), 1.2, true)
		"expedition_pack": return _backpack_v(Color(0.72, 0.25, 0.12), 1.4, true)
		# electronics
		"elec_circuit_board": return _pcb()
		"elec_microchip": return _chip()
		"elec_relay_switch": return _relay()
		"elec_fuse": return _fuse()
		"elec_light_bulb": return _bulb()
		"elec_copper_spool": return _spool()
		# salvage and junk
		"salvage_license_plate": return _plate()
		"salvage_bent_spoon": return _silverware()
		"salvage_vintage_can": return _rusty_can()
		"salvage_old_magazine": return _magazine()
		"salvage_broken_watch": return _pocket_watch()
		"salvage_rusted_spring": return _spring()
		"salvage_wire_hanger": return _hanger()
		"salvage_empty_aerosol": return _aerosol()
		"salvage_shattered_glass": return _broken_bottle()
		# roadside and vehicle parts
		"hazard_triangle": return _triangle()
		"vehicle_hubcap": return _hubcap()
		"vehicle_side_mirror": return _side_mirror()
		"vehicle_taillight": return _taillight()
		"vehicle_alternator": return _alternator()
		"vehicle_starter_motor": return _starter()
		"vehicle_radiator": return _radiator()
		# cab decor
		"mod_decor_fuzzy_dice": return _dice()
		"mod_decor_cactus_freshener": return _freshener()
		"mod_decor_suncatcher": return _suncatcher()
		"mod_decor_brass_bells": return _bells()
		"mod_decor_dreamcatcher": return _dreamcatcher()
		"mod_decor_mirror_ball": return _mirror_ball()
		"mod_decor_wind_spinner": return _spinner()
		"mod_decor_spring_palm": return _palm()
		"mod_decor_mini_globe": return _globe()
		"mod_decor_hourglass": return _hourglass()
	return null

# ---- raw resources
func _split_log(col: Color, rng: RandomNumberGenerator) -> Mesh:
	var bark := _st()
	var faces := _st()
	for k in range(2):
		var y := 0.04 + k * 0.075
		var x := -0.045 + k * 0.09
		# a quarter-split billet: bark on the round side, bright split faces
		var pts := []
		for i in range(7):
			var a := PI * 0.5 * i / 6.0
			pts.append(Vector2(cos(a), sin(a)) * 0.075)
		for i in range(6):
			var a0: Vector2 = pts[i]
			var a1: Vector2 = pts[i + 1]
			hexa(bark, [Vector3(x + a0.x - 0.03, y + a0.y - 0.03, -0.2), Vector3(x + a1.x - 0.03, y + a1.y - 0.03, -0.2), Vector3(x + a1.x - 0.03, y + a1.y - 0.03, 0.2), Vector3(x + a0.x - 0.03, y + a0.y - 0.03, 0.2),
				Vector3(x + a0.x * 1.08 - 0.03, y + a0.y * 1.08 - 0.03, -0.2), Vector3(x + a1.x * 1.08 - 0.03, y + a1.y * 1.08 - 0.03, -0.2), Vector3(x + a1.x * 1.08 - 0.03, y + a1.y * 1.08 - 0.03, 0.2), Vector3(x + a0.x * 1.08 - 0.03, y + a0.y * 1.08 - 0.03, 0.2)])
		hexa(faces, [Vector3(x - 0.03, y - 0.03, -0.2), Vector3(x + 0.045, y - 0.03, -0.2), Vector3(x + 0.045, y - 0.03, 0.2), Vector3(x - 0.03, y - 0.03, 0.2),
			Vector3(x - 0.03, y + 0.045, -0.2), Vector3(x - 0.03, y + 0.045, -0.2), Vector3(x - 0.03, y + 0.045, 0.2), Vector3(x - 0.03, y + 0.045, 0.2)])
	return _mesh([[bark, m("bark", Color(0.8, 0.7, 0.62), 6.0, 0.9)], [faces, m("planks", col, 10.0, 0.75)]])

func _driftwood(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	var prev := Vector3(-0.22, 0.03, 0)
	for i in range(1, 7):
		var p := Vector3(-0.22 + i * 0.075, 0.03 + rng.randf_range(-0.01, 0.015), rng.randf_range(-0.03, 0.03))
		var r := lerpf(0.035, 0.018, i / 6.0)
		Lib._tube(s, prev, p, r + 0.004, r, 9, 2.0)
		prev = p
	Lib._tube(s, Vector3(0.0, 0.03, 0.0), Vector3(0.08, 0.04, 0.12), 0.016, 0.006, 7)
	return _mesh([[s, m("bark", Color(1.6, 1.55, 1.45), 4.0, 0.95)]])

func _stick(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	var prev := Vector3(-0.25, 0.012, 0)
	for i in range(1, 6):
		var p := Vector3(-0.25 + i * 0.1, 0.012, rng.randf_range(-0.012, 0.012))
		Lib._tube(s, prev, p, 0.011, 0.01, 7, 2.0)
		prev = p
	Lib._tube(s, Vector3(0.05, 0.012, 0), Vector3(0.12, 0.016, 0.06), 0.006, 0.003, 5)
	var ends := _st()
	_disc(ends, Vector3(-0.25, 0.012, 0), 0.011, Vector3.LEFT, 7)
	return _mesh([[s, m("bark", Color(0.85, 0.75, 0.65), 6.0, 0.9)], [ends, m("logs", Color(1.2, 1.1, 0.9), 12.0)]])

func _rock_tool(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.045, 0), Vector3(0.055, 0.045, 0.045), 8, 12, 0.22, 77)
	return _mesh([[s, m("rock", Color(0.9, 0.88, 0.85), 8.0, 0.9)]])

func _lumps(rng: RandomNumberGenerator, mat: Material, n: int, r: float) -> Mesh:
	var s := _st()
	for i in range(n):
		var a := TAU * i / n
		ellipsoid(s, Vector3(cos(a) * r * 1.3, r * (0.8 + (i % 2) * 0.9), sin(a) * r * 1.3), Vector3(r, r * 0.8, r * 1.1), 5, 8, 0.4, i + 3)
	return _mesh([[s, mat]])

func _ore(rng: RandomNumberGenerator, base: Color, fleck: Color, metallic: bool) -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.05, 0), Vector3(0.075, 0.05, 0.06), 8, 12, 0.35, rng.randi())
	var f := _st()
	for i in range(9):
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
		ellipsoid(f, Vector3(0, 0.05, 0) + d * Vector3(0.07, 0.045, 0.055), Vector3.ONE * rng.randf_range(0.008, 0.015), 4, 6, 0.3, i)
	return _mesh([[s, m("rock", base * 1.4, 6.0, 0.9)], [f, c(fleck, 0.35 if metallic else 0.7, 0.7 if metallic else 0.0)]])

func _obsidian(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	hexa(s, [Vector3(-0.05, 0, -0.04), Vector3(0.06, 0, -0.03), Vector3(0.05, 0, 0.05), Vector3(-0.04, 0, 0.04),
		Vector3(-0.02, 0.07, -0.01), Vector3(0.03, 0.09, -0.015), Vector3(0.02, 0.06, 0.02), Vector3(-0.025, 0.05, 0.015)])
	return _mesh([[s, c(Color(0.05, 0.05, 0.07), 0.05, 0.3)]])

func _ingot(col: Color) -> Mesh:
	var s := _st()
	taper(s, 0.0, Vector2(0.13, 0.06), 0.035, Vector2(0.11, 0.045))
	var st2 := _st()
	box(st2, Vector3(0, 0.0355, 0), Vector3(0.05, 0.001, 0.02))
	return _mesh([[s, m("metal", col * 1.1, 6.0, 0.3, 0.9)], [st2, c(col.darkened(0.4), 0.4, 0.8)]])

func _powder_pile(col: Color) -> Mesh:
	var pouch := _st()
	ellipsoid(pouch, Vector3(0, 0.05, 0), Vector3(0.06, 0.05, 0.05), 8, 12, 0.12, 5)
	lathe(pouch, [Vector2(0.025, 0.09), Vector2(0.018, 0.11), Vector2(0.03, 0.125)], 10)
	var tie := _st()
	torus(tie, Vector3(0, 0.105, 0), 0.02, 0.004, 10, 4)
	var spill := _st()
	ellipsoid(spill, Vector3(0.06, 0.005, 0.03), Vector3(0.035, 0.008, 0.03), 4, 10, 0.3, 2)
	return _mesh([[pouch, m("canvas", Color(0.8, 0.72, 0.55), 6.0, 0.95)], [tie, c(Color(0.4, 0.3, 0.2))], [spill, c(col, 0.9)]])

func _powder_tin() -> Mesh:
	var tin := _st()
	lathe(tin, [Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.045, 0.1), Vector2(0.03, 0.115), Vector2(0.012, 0.12)], 20)
	var cap := _st()
	lathe(cap, [Vector2(0.014, 0.118), Vector2(0.014, 0.135), Vector2(0.011, 0.137)], 12)
	var lab := _st()
	lathe(lab, [Vector2(0.0455, 0.02), Vector2(0.0455, 0.08)], 20, Vector3.ZERO, false, false)
	return _mesh([[tin, m("metal", Color(0.3, 0.3, 0.32), 5.0, 0.4, 0.8)], [cap, brass()], [lab, paint(Color(0.75, 0.12, 0.08))]])

func _rubber_ball() -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.05, 0), Vector3(0.06, 0.05, 0.055), 8, 14, 0.15, 9)
	return _mesh([[s, c(Color(0.82, 0.74, 0.55), 0.55)]])

func _sheet_roll(mat: Material, r: float) -> Mesh:
	var s := _st()
	Lib._tube(s, Vector3(-0.14, r, 0), Vector3(0.14, r, 0), r, r, 16)
	_disc(s, Vector3(-0.14, r, 0), r, Vector3.LEFT, 16)
	_disc(s, Vector3(0.14, r, 0), r, Vector3.RIGHT, 16)
	box(s, Vector3(0, 0.002, r + 0.05), Vector3(0.28, 0.003, 0.1))
	return _mesh([[s, mat]])

func _folded(mat: Material, layers: int) -> Mesh:
	var s := _st()
	for k in range(layers):
		box(s, Vector3(0, 0.012 + k * 0.022, 0), Vector3(0.24 - k * 0.012, 0.02, 0.16 - k * 0.008), Basis(Vector3.UP, k * 0.06 - 0.05))
	var fold := _st()
	for k in range(layers):
		Lib._tube(fold, Vector3(-0.12 + k * 0.006, 0.012 + k * 0.022, -0.08), Vector3(-0.12 + k * 0.006, 0.012 + k * 0.022, 0.08), 0.011, 0.011, 8)
	return _mesh([[s, mat], [fold, mat]])

func _fat() -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.03, 0), Vector3(0.07, 0.03, 0.05), 6, 12, 0.25, 4)
	var paper := _st()
	box(paper, Vector3(0, 0.002, 0), Vector3(0.18, 0.003, 0.14), Basis(Vector3.UP, 0.3))
	return _mesh([[s, c(Color(0.96, 0.9, 0.78), 0.35)], [paper, m("cardboard", Color(1.2, 1.15, 1.05), 6.0)]])

func _sinew(cord: bool) -> Mesh:
	var s := _st()
	if cord:
		for k in range(5):
			torus(s, Vector3(0, 0.006 + k * 0.009, 0), 0.04 - k * 0.0015, 0.004, 24, 5)
	else:
		for k in range(6):
			var o := float(k) * 0.008 - 0.02
			Lib._tube(s, Vector3(-0.12, 0.006, o), Vector3(0.12, 0.006 + sin(k) * 0.004, o * 1.4), 0.004, 0.0025, 5)
	return _mesh([[s, c(Color(0.88, 0.78, 0.6), 0.45)]])

func _bones(rng: RandomNumberGenerator) -> Mesh:
	var s := _st()
	for i in range(4):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var o := Vector3(rng.randf_range(-0.04, 0.04), 0.012, rng.randf_range(-0.04, 0.04))
		Lib._tube(s, o - d * 0.05, o + d * 0.05, 0.009, 0.008, 7)
		ellipsoid(s, o + d * 0.055, Vector3(0.014, 0.012, 0.014), 4, 6, 0.3, i)
	return _mesh([[s, c(Color(0.92, 0.88, 0.78), 0.6)]])

func _jar(fill: Color, lid: Color) -> Mesh:
	var glass := _st()
	lathe(glass, [Vector2(0.0, 0.0), Vector2(0.038, 0.0), Vector2(0.042, 0.01), Vector2(0.042, 0.09), Vector2(0.034, 0.1), Vector2(0.034, 0.11)], 22, Vector3.ZERO, false, false)
	var lidst := _st()
	lathe(lidst, [Vector2(0.036, 0.105), Vector2(0.036, 0.122), Vector2(0.03, 0.125)], 22)
	var gm := Lib.color_mat(Color(0.85, 0.92, 0.95, 0.2), 0.05, 0.1).duplicate()
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var parts := [[glass, gm], [lidst, m("metal", lid, 6.0, 0.35, 0.7)]]
	if fill.a > 0.0:
		var f := _st()
		lathe(f, [Vector2(0.0, 0.004), Vector2(0.038, 0.006), Vector2(0.039, 0.07), Vector2(0.0, 0.07)], 20)
		parts.append([f, c(fill, 0.3)])
	return _mesh(parts)

func _chem_jug(col: Color, label: Color) -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.1, 0), Vector3(0.12, 0.2, 0.08))
	lathe(body, [Vector2(0.02, 0.2), Vector2(0.02, 0.23)], 12, Vector3(0.03, 0, 0))
	var handle := _st()
	Lib._tube(handle, Vector3(-0.05, 0.2, 0), Vector3(-0.05, 0.12, 0), 0.012, 0.012, 8)
	Lib._tube(handle, Vector3(-0.05, 0.2, 0), Vector3(0.0, 0.2, 0), 0.012, 0.012, 8)
	var cap := _st()
	lathe(cap, [Vector2(0.024, 0.225), Vector2(0.024, 0.245), Vector2(0.02, 0.248)], 12, Vector3(0.03, 0, 0))
	var lab := _st()
	box(lab, Vector3(0.0, 0.1, 0.0405), Vector3(0.09, 0.1, 0.002))
	return _mesh([[body, c(col, 0.4)], [handle, c(col, 0.4)], [cap, black_plastic()], [lab, paint(label)]])

func _chem_bottle(col: Color, label: Color) -> Mesh:
	var b := _st()
	lathe(b, [Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.037, 0.01), Vector2(0.037, 0.13), Vector2(0.018, 0.155), Vector2(0.014, 0.17)], 18)
	var cap := _st()
	lathe(cap, [Vector2(0.017, 0.165), Vector2(0.017, 0.19), Vector2(0.012, 0.193)], 12)
	var lab := _st()
	lathe(lab, [Vector2(0.0375, 0.03), Vector2(0.0375, 0.11)], 18, Vector3.ZERO, false, false)
	return _mesh([[b, c(col, 0.35)], [cap, c(label.darkened(0.3), 0.4)], [lab, paint(label)]])

func _big_jug(col: Color) -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.19, 0), Vector3(0.25, 0.38, 0.17))
	var handle := _st()
	Lib._tube(handle, Vector3(-0.08, 0.38, 0), Vector3(0.04, 0.38, 0), 0.016, 0.016, 8)
	for x in [-0.08, 0.04]:
		Lib._tube(handle, Vector3(x, 0.38, 0), Vector3(x, 0.33, 0), 0.016, 0.016, 8)
	var cap := _st()
	lathe(cap, [Vector2(0.03, 0.375), Vector2(0.03, 0.41), Vector2(0.025, 0.415)], 14, Vector3(0.08, 0, 0))
	var lab := _st()
	box(lab, Vector3(0, 0.18, 0.0855), Vector3(0.2, 0.18, 0.002))
	return _mesh([[body, c(col, 0.45)], [handle, c(col, 0.45)], [cap, c(Color(0.9, 0.85, 0.1), 0.4)], [lab, paint(Color(0.95, 0.95, 0.92))]])

func _drum_can(col: Color) -> Mesh:
	var d := _st()
	lathe(d, [Vector2(0.0, 0.0), Vector2(0.065, 0.0), Vector2(0.068, 0.01), Vector2(0.068, 0.17), Vector2(0.065, 0.18), Vector2(0.0, 0.18)], 22)
	var rib := _st()
	for y in [0.06, 0.12]:
		torus(rib, Vector3(0, y, 0), 0.068, 0.004, 22, 5)
	var cap := _st()
	lathe(cap, [Vector2(0.012, 0.18), Vector2(0.012, 0.19)], 10, Vector3(0.035, 0, 0))
	var drip := _st()
	ellipsoid(drip, Vector3(0.05, 0.181, 0.01), Vector3(0.02, 0.002, 0.015), 3, 8)
	return _mesh([[d, m("rust", Color(0.4, 0.38, 0.36), 6.0, 0.6, 0.5)], [rib, dark_steel()], [cap, dark_steel()], [drip, c(col, 0.05, 0.3)]])

# ---- hunting byproducts
func _antlers() -> Mesh:
	var s := _st()
	var bone := Color(0.85, 0.78, 0.62)
	box(s, Vector3(0, 0.02, 0), Vector3(0.08, 0.04, 0.05))
	for side in [-1.0, 1.0]:
		var pts := [Vector3(side * 0.03, 0.03, 0), Vector3(side * 0.1, 0.1, -0.02), Vector3(side * 0.16, 0.2, -0.05), Vector3(side * 0.18, 0.32, -0.04), Vector3(side * 0.16, 0.42, 0.0)]
		for i in range(pts.size() - 1):
			Lib._tube(s, pts[i], pts[i + 1], lerpf(0.018, 0.008, i / 4.0), lerpf(0.018, 0.008, (i + 1) / 4.0), 8)
		for t in [[1, Vector3(side * 0.06, 0.12, 0.08)], [2, Vector3(side * 0.08, 0.3, 0.05)], [3, Vector3(side * 0.26, 0.4, -0.02)]]:
			var a: Vector3 = pts[t[0]]
			Lib._tube(s, a, a + t[1] * 0.6, 0.01, 0.004, 6)
	return _mesh([[s, c(bone, 0.6)]])

func _pelt(col: Color, cured: bool) -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.012, 0), Vector3(0.24, 0.014, 0.15), 6, 24, 0.3, 21)
	for side in [-1.0, 1.0]:
		ellipsoid(s, Vector3(side * 0.12, 0.01, 0.15), Vector3(0.03, 0.01, 0.06), 4, 8, 0.2, 3)
		ellipsoid(s, Vector3(side * 0.12, 0.01, -0.15), Vector3(0.03, 0.01, 0.06), 4, 8, 0.2, 4)
	ellipsoid(s, Vector3(0.28, 0.012, 0), Vector3(0.09, 0.016, 0.025), 4, 10, 0.2, 7)
	var parts := [[s, m("fur", col * 1.5, 4.0, 1.0)]]
	if not cured:
		var raw := _st()
		ellipsoid(raw, Vector3(0, 0.002, 0), Vector3(0.22, 0.004, 0.13), 4, 20, 0.3, 21)
		parts.append([raw, c(Color(0.7, 0.35, 0.32), 0.5)])
	return _mesh(parts)

func _claws() -> Mesh:
	var s := _st()
	for k in range(4):
		var x := -0.045 + k * 0.03
		var prev := Vector3(x, 0.006, -0.02)
		for i in range(1, 6):
			var a := i / 5.0 * 1.4
			var p := Vector3(x, 0.006 + sin(a) * 0.025, -0.02 + (1.0 - cos(a)) * 0.0 + i * 0.01)
			Lib._tube(s, prev, p, lerpf(0.007, 0.002, (i - 1) / 5.0), lerpf(0.007, 0.0015, i / 5.0), 6)
			prev = p
	var cord := _st()
	Lib._tube(cord, Vector3(-0.07, 0.006, -0.022), Vector3(0.07, 0.006, -0.022), 0.002, 0.002, 4)
	return _mesh([[s, c(Color(0.12, 0.1, 0.08), 0.3)], [cord, c(Color(0.55, 0.4, 0.25))]])

func _needles() -> Mesh:
	var s := _st()
	for k in range(3):
		var z := -0.012 + k * 0.012
		Lib._tube(s, Vector3(-0.05, 0.003, z), Vector3(0.05, 0.003, z + 0.004), 0.0025, 0.0008, 6)
	var w := _st()
	box(w, Vector3(0, 0.001, 0), Vector3(0.06, 0.002, 0.05))
	return _mesh([[s, c(Color(0.95, 0.92, 0.84), 0.4)], [w, leather()]])

func _strips() -> Mesh:
	var s := _st()
	for k in range(4):
		box(s, Vector3(0, 0.002 + k * 0.003, -0.03 + k * 0.02), Vector3(0.26, 0.003, 0.014), Basis(Vector3.UP, k * 0.12 - 0.15))
	return _mesh([[s, m("leather", Color(1.1, 0.8, 0.55), 6.0, 0.7)]])

func _skull() -> Mesh:
	var bone := c(Color(0.9, 0.86, 0.75), 0.55)
	var s := _st()
	ellipsoid(s, Vector3(0, 0.06, -0.04), Vector3(0.06, 0.055, 0.07), 10, 14)
	taper(s, 0.015, Vector2(0.06, 0.05), 0.06, Vector2(0.04, 0.035), Vector2(0, 0.06), Vector2(0, 0.09))
	box(s, Vector3(0, 0.02, 0.08), Vector3(0.05, 0.02, 0.09))
	var teeth := _st()
	for side in [-1.0, 1.0]:
		tube(teeth, Vector3(side * 0.018, 0.02, 0.115), Vector3(side * 0.016, -0.008, 0.12), 0.005, 0.001, 6)
	var holes := _st()
	for side in [-1.0, 1.0]:
		ellipsoid(holes, Vector3(side * 0.03, 0.075, 0.02), Vector3(0.016, 0.014, 0.012), 5, 8)
	ellipsoid(holes, Vector3(0, 0.05, 0.125), Vector3(0.01, 0.008, 0.006), 4, 6)
	var stand := _st()
	box(stand, Vector3(0, -0.012, 0.02), Vector3(0.18, 0.02, 0.22))
	return _mesh([[s, bone], [teeth, c(Color(0.95, 0.92, 0.8), 0.35)], [holes, c(Color(0.05, 0.04, 0.03), 0.9)], [stand, dark_wood()]])

# ---- meat & produce
func _drumstick(col: Color, cooked: bool) -> Mesh:
	var meat := _st()
	ellipsoid(meat, Vector3(0.0, 0.035, 0), Vector3(0.06, 0.035, 0.04), 8, 12, 0.12, 5)
	var bone := _st()
	Lib._tube(bone, Vector3(0.04, 0.035, 0), Vector3(0.1, 0.04, 0), 0.008, 0.007, 8)
	ellipsoid(bone, Vector3(0.105, 0.04, 0), Vector3(0.012, 0.012, 0.014), 5, 8)
	return _mesh([[meat, m("skin", col * (1.0 if not cooked else 1.1), 5.0, 0.35 if cooked else 0.5)], [bone, c(Color(0.92, 0.88, 0.8), 0.5)]])

func _carrot() -> Mesh:
	var root := _st()
	lathe(root, [Vector2(0.0, -0.14), Vector2(0.006, -0.12), Vector2(0.014, -0.06), Vector2(0.019, 0.0), Vector2(0.016, 0.012), Vector2(0.0, 0.014)], 14)
	var tops := _st()
	for k in range(5):
		var a := TAU * k / 5.0
		Lib._tube(tops, Vector3(0, 0.012, 0), Vector3(cos(a) * 0.03, 0.1, sin(a) * 0.03), 0.004, 0.002, 5)
		ellipsoid(tops, Vector3(cos(a) * 0.03, 0.1, sin(a) * 0.03), Vector3(0.018, 0.022, 0.006), 4, 6, 0.3, k)
	var mi := _mesh([[root, m("skin", Color(1.6, 0.7, 0.2), 6.0, 0.6)], [tops, c(Color(0.25, 0.55, 0.18), 0.6)]])
	return _rotated(mi, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.02, 0))

## Lay a mesh on its side (rebuilds the surfaces with a transform).
func _rotated(mesh_in: ArrayMesh, b: Basis, off: Vector3) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in range(mesh_in.get_surface_count()):
		var st := SurfaceTool.new()
		st.create_from(mesh_in, si)
		var arr := st.commit_to_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in range(verts.size()):
			verts[i] = b * verts[i] + off
			norms[i] = b * norms[i]
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TANGENT] = null
		var st2 := SurfaceTool.new()
		st2.create_from_arrays(arr)
		st2.generate_tangents()
		st2.commit(out)
		out.surface_set_material(si, mesh_in.surface_get_material(si))
	return out

func _corn(roasted: bool) -> Mesh:
	var cob := _st()
	lathe(cob, [Vector2(0.0, -0.09), Vector2(0.02, -0.085), Vector2(0.026, -0.05), Vector2(0.027, 0.04), Vector2(0.02, 0.08), Vector2(0.0, 0.09)], 16)
	var kern := _st()
	for row in range(10):
		for k in range(8):
			var a := TAU * k / 8.0 + row * 0.39
			var y := -0.07 + row * 0.016
			var r := 0.027 if absf(y) < 0.05 else 0.022
			ellipsoid(kern, Vector3(cos(a) * r, y, sin(a) * r), Vector3(0.006, 0.006, 0.006), 3, 5)
	var husk := _st()
	for k in range(3):
		var a := TAU * k / 3.0
		hexa(husk, [Vector3(cos(a) * 0.02, -0.09, sin(a) * 0.02), Vector3(cos(a + 0.6) * 0.02, -0.09, sin(a + 0.6) * 0.02), Vector3(cos(a + 0.6) * 0.022, -0.09, sin(a + 0.6) * 0.022), Vector3(cos(a) * 0.022, -0.09, sin(a) * 0.022),
			Vector3(cos(a) * 0.05, -0.16, sin(a) * 0.05), Vector3(cos(a + 0.6) * 0.05, -0.16, sin(a + 0.6) * 0.05), Vector3(cos(a + 0.6) * 0.052, -0.16, sin(a + 0.6) * 0.052), Vector3(cos(a) * 0.052, -0.16, sin(a) * 0.052)])
	var kc := Color(0.95, 0.78, 0.2) if not roasted else Color(0.78, 0.52, 0.15)
	var mi := _mesh([[cob, c(Color(0.9, 0.85, 0.6), 0.7)], [kern, c(kc, 0.35)], [husk, c(Color(0.55, 0.65, 0.3) if not roasted else Color(0.35, 0.28, 0.15), 0.7)]])
	return _rotated(mi, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.03, 0))

func _berries_col(col: Color) -> Mesh:
	var s := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(col.to_html())
	for i in range(9):
		var a := TAU * i / 9.0
		var r := 0.02 + (i % 3) * 0.008
		ellipsoid(s, Vector3(cos(a) * r, 0.012 + (i % 2) * 0.012, sin(a) * r), Vector3.ONE * rng.randf_range(0.009, 0.012), 5, 8)
	var stems := _st()
	for i in range(3):
		var a := TAU * i / 3.0
		Lib._tube(stems, Vector3(0, 0.03, 0), Vector3(cos(a) * 0.025, 0.045, sin(a) * 0.025), 0.0015, 0.001, 4)
	ellipsoid(stems, Vector3(0.0, 0.045, 0.0), Vector3(0.025, 0.003, 0.012), 3, 8)
	return _mesh([[s, c(col, 0.2, 0.05)], [stems, c(Color(0.25, 0.45, 0.15), 0.7)]])

func _golden_berry() -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.03, 0), Vector3(0.028, 0.03, 0.028), 10, 14)
	var husk := _st()
	for k in range(5):
		var a := TAU * k / 5.0
		ellipsoid(husk, Vector3(cos(a) * 0.022, 0.05, sin(a) * 0.022), Vector3(0.016, 0.022, 0.004), 4, 6)
	return _mesh([[s, Lib.color_mat(Color(1.0, 0.78, 0.2), 0.15, 0.4, Color(1.0, 0.7, 0.2), 0.6)], [husk, c(Color(0.75, 0.62, 0.3), 0.8)]])

# ---- drinks & snacks
func _tall_can(col: Color, band: Color) -> Mesh:
	return _can(col, band, 0.028, 0.165)

func _milk(col: Color, spoiled: bool) -> Mesh:
	var carton := _st()
	box(carton, Vector3(0, 0.09, 0), Vector3(0.07, 0.18, 0.07))
	hexa(carton, [Vector3(-0.035, 0.18, -0.035), Vector3(0.035, 0.18, -0.035), Vector3(0.035, 0.18, 0.035), Vector3(-0.035, 0.18, 0.035),
		Vector3(-0.035, 0.22, -0.003), Vector3(0.035, 0.22, -0.003), Vector3(0.035, 0.22, 0.003), Vector3(-0.035, 0.22, 0.003)])
	box(carton, Vector3(0, 0.228, 0), Vector3(0.07, 0.016, 0.006))
	var band := _st()
	box(band, Vector3(0, 0.07, 0.0355), Vector3(0.07, 0.07, 0.002))
	box(band, Vector3(0.0355, 0.07, 0), Vector3(0.002, 0.07, 0.07))
	var cap := _st()
	lathe(cap, [Vector2(0.012, 0.195), Vector2(0.012, 0.207)], 12, Vector3(0, 0, 0.02))
	var white := m("cardboard", Color(1.5, 1.5, 1.45) if not spoiled else Color(1.25, 1.25, 1.0), 4.0, 0.6)
	return _mesh([[carton, white], [band, paint(col)], [cap, c(col, 0.4)]])

func _cereal_box(col: Color, accent: Color) -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.13, 0), Vector3(0.18, 0.26, 0.06))
	var front := _st()
	box(front, Vector3(0, 0.15, 0.0305), Vector3(0.14, 0.16, 0.001))
	var bowl := _st()
	ellipsoid(bowl, Vector3(0, 0.08, 0.031), Vector3(0.045, 0.02, 0.002), 4, 12)
	return _mesh([[b, paint(col)], [front, paint(accent)], [bowl, white_plastic()]])

func _thermos(full: bool) -> Mesh:
	var body := _st()
	lathe(body, [Vector2(0.0, 0.0), Vector2(0.036, 0.0), Vector2(0.038, 0.01), Vector2(0.038, 0.22), Vector2(0.032, 0.235)], 20)
	var cup := _st()
	lathe(cup, [Vector2(0.033, 0.232), Vector2(0.036, 0.235), Vector2(0.038, 0.3), Vector2(0.0, 0.302)], 20)
	var trim := _st()
	torus(trim, Vector3(0, 0.234, 0), 0.036, 0.003, 20, 4)
	lathe(trim, [Vector2(0.0385, 0.04), Vector2(0.0385, 0.06)], 20, Vector3.ZERO, false, false)
	var parts := [[body, m("paint", Color(0.18, 0.42, 0.3), 3.0, 0.5, 0.2)], [cup, steel()], [trim, black_plastic()]]
	if full:
		var steam := _st()
		ellipsoid(steam, Vector3(0, 0.33, 0), Vector3(0.02, 0.025, 0.02), 4, 8, 0.4, 3)
		parts.append([steam, Lib.color_mat(Color(1, 1, 1, 0.25), 0.9)])
	return _mesh(parts)

# ---- medical
func _gauze() -> Mesh:
	var roll := _st()
	lathe(roll, [Vector2(0.012, 0.0), Vector2(0.032, 0.0), Vector2(0.032, 0.06), Vector2(0.012, 0.06)], 20, Vector3.ZERO, false, false)
	var wrap := _st()
	lathe(wrap, [Vector2(0.0325, 0.005), Vector2(0.0325, 0.055)], 20, Vector3.ZERO, false, false)
	var tail := _st()
	box(tail, Vector3(0.04, 0.003, 0.02), Vector3(0.05, 0.002, 0.055))
	return _mesh([[roll, m("canvas", Color(1.4, 1.4, 1.4), 12.0, 0.95)], [wrap, Lib.color_mat(Color(0.9, 0.95, 1.0, 0.35), 0.1)], [tail, m("canvas", Color(1.4, 1.4, 1.4), 12.0, 0.95)]])

func _injector(col: Color) -> Mesh:
	var body := _st()
	Lib._tube(body, Vector3(-0.07, 0.014, 0), Vector3(0.06, 0.014, 0), 0.014, 0.014, 14)
	_disc(body, Vector3(-0.07, 0.014, 0), 0.014, Vector3.LEFT, 14)
	var cap := _st()
	Lib._tube(cap, Vector3(0.06, 0.014, 0), Vector3(0.085, 0.014, 0), 0.0145, 0.012, 14)
	_disc(cap, Vector3(0.085, 0.014, 0), 0.012, Vector3.RIGHT, 14)
	var win := _st()
	box(win, Vector3(0.0, 0.0285, 0), Vector3(0.04, 0.002, 0.012))
	var lab := _st()
	Lib._tube(lab, Vector3(-0.05, 0.014, 0), Vector3(-0.01, 0.014, 0), 0.0145, 0.0145, 14)
	return _mesh([[body, white_plastic()], [cap, c(col, 0.4)], [win, Lib.color_mat(Color(0.8, 0.9, 1.0, 0.5), 0.1)], [lab, paint(col)]])

func _vial(liquid: Color) -> Mesh:
	var g := _st()
	lathe(g, [Vector2(0.0, 0.0), Vector2(0.015, 0.0), Vector2(0.016, 0.005), Vector2(0.016, 0.06), Vector2(0.008, 0.068), Vector2(0.008, 0.075)], 14, Vector3.ZERO, false, false)
	var liq := _st()
	lathe(liq, [Vector2(0.0, 0.002), Vector2(0.014, 0.003), Vector2(0.014, 0.045), Vector2(0.0, 0.045)], 12)
	var cap := _st()
	lathe(cap, [Vector2(0.01, 0.072), Vector2(0.01, 0.085), Vector2(0.008, 0.087)], 12)
	var gm := Lib.color_mat(Color(0.9, 0.95, 1.0, 0.25), 0.05).duplicate()
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh([[g, gm], [liq, c(liquid, 0.1)], [cap, c(Color(0.75, 0.15, 0.12), 0.4)]])

func _splint() -> Mesh:
	var s := _st()
	for z in [-0.025, 0.025]:
		box(s, Vector3(0, 0.006, z), Vector3(0.3, 0.012, 0.022))
	var w := _st()
	for x in [-0.09, 0.0, 0.09]:
		box(w, Vector3(x, 0.006, 0), Vector3(0.025, 0.018, 0.08))
	return _mesh([[s, wood()], [w, m("canvas", Color(1.35, 1.3, 1.25), 10.0, 0.95)]])

func _trauma_kit() -> Mesh:
	var bag := _st()
	box(bag, Vector3(0, 0.07, 0), Vector3(0.3, 0.14, 0.18))
	ellipsoid(bag, Vector3(0, 0.14, 0), Vector3(0.15, 0.02, 0.09), 4, 14)
	var zip := _st()
	box(zip, Vector3(0, 0.155, 0), Vector3(0.28, 0.006, 0.01))
	Lib._tube(zip, Vector3(-0.08, 0.16, 0), Vector3(0.08, 0.16, 0), 0.008, 0.008, 6)
	var cross := _st()
	box(cross, Vector3(0, 0.08, 0.0905), Vector3(0.07, 0.022, 0.002))
	box(cross, Vector3(0, 0.08, 0.0905), Vector3(0.022, 0.07, 0.002))
	return _mesh([[bag, m("canvas", Color(0.35, 0.45, 0.3), 5.0, 0.9)], [zip, black_plastic()], [cross, paint(Color(0.85, 0.12, 0.1))]])

func _tablets() -> Mesh:
	var b := _st()
	lathe(b, [Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.018, 0.075), Vector2(0.0, 0.075)], 16)
	var cap := _st()
	lathe(cap, [Vector2(0.019, 0.07), Vector2(0.019, 0.088), Vector2(0.016, 0.09)], 16)
	var lab := _st()
	lathe(lab, [Vector2(0.0185, 0.012), Vector2(0.0185, 0.06)], 16, Vector3.ZERO, false, false)
	return _mesh([[b, white_plastic()], [cap, c(Color(0.2, 0.5, 0.85), 0.4)], [lab, paint(Color(0.25, 0.55, 0.9))]])

func _warmer() -> Mesh:
	var p := _st()
	ellipsoid(p, Vector3(0, 0.008, 0), Vector3(0.05, 0.009, 0.07), 4, 14)
	var edge := _st()
	box(edge, Vector3(0, 0.003, 0), Vector3(0.1, 0.004, 0.142))
	return _mesh([[p, paint(Color(0.92, 0.38, 0.18))], [edge, c(Color(0.95, 0.92, 0.88), 0.4)]])

func _space_blanket() -> Mesh:
	var p := _st()
	box(p, Vector3(0, 0.012, 0), Vector3(0.12, 0.024, 0.08))
	var foil := _st()
	box(foil, Vector3(0, 0.025, 0), Vector3(0.1, 0.002, 0.065))
	return _mesh([[p, Lib.color_mat(Color(0.9, 0.95, 1.0, 0.5), 0.1)], [foil, m("metal", Color(1.0, 0.8, 0.3), 3.0, 0.2, 0.95)]])

func _matches() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.012, 0), Vector3(0.06, 0.024, 0.04))
	var tray := _st()
	box(tray, Vector3(0.02, 0.012, 0), Vector3(0.05, 0.02, 0.036))
	var sticks := _st()
	for k in range(4):
		box(sticks, Vector3(0.03, 0.015, -0.012 + k * 0.008), Vector3(0.045, 0.004, 0.004))
	var heads := _st()
	for k in range(4):
		ellipsoid(heads, Vector3(0.054, 0.015, -0.012 + k * 0.008), Vector3(0.004, 0.003, 0.003), 3, 5)
	return _mesh([[b, paint(Color(0.75, 0.15, 0.1))], [tray, m("cardboard", Color.WHITE, 8.0)], [sticks, wood()], [heads, c(Color(0.6, 0.1, 0.08), 0.6)]])

# ---- firearms (modelled muzzle up +Y, origin at the grip, like the rifle)
func _pistol(col: Color, barrel: float, revolver: bool) -> Mesh:
	var frame := _st()
	var grip := _st()
	hexa(grip, [Vector3(-0.014, -0.09, -0.045), Vector3(0.014, -0.09, -0.045), Vector3(0.014, -0.09, -0.012), Vector3(-0.014, -0.09, -0.012),
		Vector3(-0.014, 0.0, -0.025), Vector3(0.014, 0.0, -0.025), Vector3(0.014, 0.0, 0.012), Vector3(-0.014, 0.0, 0.012)])
	var guard := _st()
	torus(guard, Vector3(0, 0.02, 0.02), 0.018, 0.003, 12, 4, Vector3.RIGHT)
	box(frame, Vector3(0, 0.035, -0.002), Vector3(0.02, 0.05, 0.04))
	if revolver:
		lathe(frame, [Vector2(0.022, 0.03), Vector2(0.024, 0.035), Vector2(0.024, 0.075), Vector2(0.02, 0.08)], 12, Vector3(0, 0, 0.005))
		Lib._tube(frame, Vector3(0, 0.08, 0.012), Vector3(0, 0.08 + barrel, 0.012), 0.009, 0.009, 12)
		box(frame, Vector3(0, 0.08 + barrel * 0.5, 0.0), Vector3(0.01, barrel, 0.012))
		var flutes := _st()
		for k in range(6):
			var a := TAU * k / 6.0
			box(flutes, Vector3(cos(a) * 0.024, 0.055, 0.005 + sin(a) * 0.024), Vector3(0.004, 0.035, 0.004))
		box(frame, Vector3(0, 0.075, -0.03), Vector3(0.008, 0.015, 0.02), Basis(Vector3.RIGHT, -0.5))
		return _mesh([[frame, m("metal", col, 6.0, 0.25, 0.9)], [flutes, dark_steel()], [grip, dark_wood()], [guard, m("metal", col, 6.0, 0.3, 0.9)]])
	var slide := _st()
	box(slide, Vector3(0, 0.03 + barrel * 0.5, 0.006), Vector3(0.022, barrel, 0.03))
	for k in range(5):
		box(slide, Vector3(0, 0.035 + k * 0.006, -0.0095), Vector3(0.0225, 0.002, 0.002))
	var bore := _st()
	_disc(bore, Vector3(0, 0.0302 + barrel, 0.008), 0.004, Vector3.UP, 8)
	box(bore, Vector3(0, 0.03 + barrel - 0.008, 0.022), Vector3(0.004, 0.006, 0.004))
	return _mesh([[slide, m("metal", col, 6.0, 0.35, 0.85)], [frame, c(col.darkened(0.2), 0.5, 0.3)], [grip, m("rubber", col * 1.4, 10.0, 0.8)], [guard, c(col.darkened(0.2), 0.5, 0.3)], [bore, c(Color(0.02, 0.02, 0.02))]])

func _shotgun() -> Mesh:
	var stock := _st()
	hexa(stock, [Vector3(-0.02, -0.36, -0.06), Vector3(0.02, -0.36, -0.06), Vector3(0.02, -0.36, 0.06), Vector3(-0.02, -0.36, 0.06),
		Vector3(-0.018, -0.04, -0.02), Vector3(0.018, -0.04, -0.02), Vector3(0.018, -0.04, 0.03), Vector3(-0.018, -0.04, 0.03)])
	box(stock, Vector3(0, 0.22, 0.038), Vector3(0.036, 0.2, 0.026))
	var metal := _st()
	box(metal, Vector3(0, 0.03, 0.03), Vector3(0.04, 0.12, 0.05))
	for x in [-0.011, 0.011]:
		Lib._tube(metal, Vector3(x, 0.08, 0.05), Vector3(x, 0.68, 0.05), 0.011, 0.011, 12)
		_disc(metal, Vector3(x, 0.68, 0.05), 0.011, Vector3.UP, 12)
	box(metal, Vector3(0, 0.38, 0.062), Vector3(0.006, 0.6, 0.006))
	Lib._tube(metal, Vector3(0, 0.07, 0.0), Vector3(0, 0.1, -0.02), 0.004, 0.004, 6)
	var bores := _st()
	for x in [-0.011, 0.011]:
		_disc(bores, Vector3(x, 0.6805, 0.05), 0.008, Vector3.UP, 10)
	return _mesh([[stock, dark_wood()], [metal, dark_steel()], [bores, c(Color(0.02, 0.02, 0.02))]])

func _compound_bow() -> Mesh:
	var riser := _st()
	hexa(riser, [Vector3(-0.012, -0.22, -0.02), Vector3(0.012, -0.22, -0.02), Vector3(0.012, -0.22, 0.02), Vector3(-0.012, -0.22, 0.02),
		Vector3(-0.012, 0.22, -0.02), Vector3(0.012, 0.22, -0.02), Vector3(0.012, 0.22, 0.02), Vector3(-0.012, 0.22, 0.02)])
	box(riser, Vector3(0.03, 0.0, 0), Vector3(0.04, 0.12, 0.03))
	var limbs := _st()
	var cams := _st()
	for s in [-1.0, 1.0]:
		Lib._tube(limbs, Vector3(0, s * 0.22, 0), Vector3(-0.08, s * 0.4, 0), 0.012, 0.009, 8)
		torus(cams, Vector3(-0.085, s * 0.42, 0), 0.03, 0.006, 16, 6, Vector3.FORWARD)
	var string := _st()
	Lib._tube(string, Vector3(-0.1, -0.42, 0), Vector3(-0.1, 0.42, 0), 0.0015, 0.0015, 4)
	Lib._tube(string, Vector3(-0.07, -0.42, 0), Vector3(-0.07, 0.42, 0), 0.0012, 0.0012, 4)
	var sight := _st()
	box(sight, Vector3(0.0, 0.08, 0.035), Vector3(0.03, 0.04, 0.03))
	return _mesh([[riser, m("metal", Color(0.2, 0.22, 0.2), 6.0, 0.45, 0.7)], [limbs, m("paint", Color(0.25, 0.3, 0.22), 3.0, 0.6)], [cams, steel()], [string, c(Color(0.1, 0.1, 0.1))], [sight, c(Color(0.9, 0.35, 0.1), 0.4)]])

func _ammo_box(col: Color, brass_col: Color) -> Mesh:
	var bx := _st()
	box(bx, Vector3(0, 0.022, 0), Vector3(0.1, 0.044, 0.065))
	var lid := _st()
	box(lid, Vector3(0, 0.046, 0), Vector3(0.102, 0.004, 0.067))
	var lab := _st()
	box(lab, Vector3(0, 0.025, 0.0326), Vector3(0.07, 0.025, 0.001))
	var rounds := _st()
	for k in range(3):
		var x := -0.04 + k * 0.016
		lathe(rounds, [Vector2(0.004, 0.0), Vector2(0.004, 0.018), Vector2(0.003, 0.024), Vector2(0.0, 0.027)], 8, Vector3(x, 0.048, 0.04))
	return _mesh([[bx, m("cardboard", col * 1.6, 5.0, 0.7)], [lid, m("cardboard", col * 1.3, 5.0, 0.7)], [lab, paint(Color(0.95, 0.93, 0.86))], [rounds, m("metal", brass_col, 8.0, 0.3, 0.9)]])

func _shells() -> Mesh:
	var hull := _st()
	var heads := _st()
	for k in range(4):
		var x := -0.03 + k * 0.02
		lathe(hull, [Vector2(0.0, 0.012), Vector2(0.0095, 0.012), Vector2(0.0095, 0.07), Vector2(0.006, 0.072), Vector2(0.0, 0.072)], 12, Vector3(x, 0, 0))
		lathe(heads, [Vector2(0.0, 0.0), Vector2(0.0105, 0.0), Vector2(0.0105, 0.012), Vector2(0.0, 0.012)], 12, Vector3(x, 0, 0))
	return _mesh([[hull, paint(Color(0.75, 0.12, 0.08))], [heads, brass()]])

# ---- tools & melee (grip at origin, working end up)
func _fire_axe() -> Mesh:
	var h := _st()
	_handle(h, 0.78, 0.017, 0.014)
	var head := _st()
	hexa(head, [Vector3(-0.012, 0.66, -0.03), Vector3(0.012, 0.66, -0.03), Vector3(0.012, 0.66, 0.03), Vector3(-0.012, 0.66, 0.03),
		Vector3(-0.012, 0.8, -0.035), Vector3(0.012, 0.8, -0.035), Vector3(0.012, 0.8, 0.03), Vector3(-0.012, 0.8, 0.03)])
	hexa(head, [Vector3(-0.012, 0.69, 0.03), Vector3(0.012, 0.69, 0.03), Vector3(0.012, 0.77, 0.03), Vector3(-0.012, 0.77, 0.03),
		Vector3(-0.002, 0.62, 0.17), Vector3(0.002, 0.62, 0.17), Vector3(0.002, 0.84, 0.17), Vector3(-0.002, 0.84, 0.17)])
	hexa(head, [Vector3(-0.012, 0.7, -0.035), Vector3(0.012, 0.7, -0.035), Vector3(0.012, 0.76, -0.035), Vector3(-0.012, 0.76, -0.035),
		Vector3(-0.003, 0.725, -0.15), Vector3(0.003, 0.725, -0.15), Vector3(0.003, 0.735, -0.15), Vector3(-0.003, 0.735, -0.15)])
	var edge := _st()
	box(edge, Vector3(0, 0.73, 0.168), Vector3(0.005, 0.2, 0.01))
	return _mesh([[h, m("paint", Color(0.85, 0.75, 0.3), 4.0, 0.5)], [head, paint(Color(0.75, 0.08, 0.06))], [edge, steel()]])

func _stone_tool(pick: bool) -> Mesh:
	var h := _st()
	_handle(h, 0.5, 0.016, 0.013)
	var head := _st()
	if pick:
		for s in [-1.0, 1.0]:
			hexa(head, [Vector3(-0.015, 0.44, 0), Vector3(0.015, 0.44, 0), Vector3(0.015, 0.48, 0), Vector3(-0.015, 0.48, 0),
				Vector3(-0.004, 0.42, s * 0.15), Vector3(0.004, 0.42, s * 0.15), Vector3(0.004, 0.43, s * 0.15), Vector3(-0.004, 0.43, s * 0.15)])
	else:
		ellipsoid(head, Vector3(0, 0.46, 0.05), Vector3(0.018, 0.045, 0.07), 6, 10, 0.25, 5)
	var lash := _st()
	for k in range(5):
		torus(lash, Vector3(0, 0.42 + k * 0.012, 0), 0.02, 0.004, 10, 4)
	return _mesh([[h, m("bark", Color(0.8, 0.7, 0.6), 6.0, 0.9)], [head, m("rock", Color(0.85, 0.85, 0.82), 8.0, 0.85)], [lash, c(Color(0.6, 0.5, 0.3), 0.9)]])

func _heavy_pick() -> Mesh:
	var h := _st()
	_handle(h, 0.85, 0.02, 0.017)
	var head := _st()
	box(head, Vector3(0, 0.8, 0), Vector3(0.05, 0.07, 0.07))
	for s in [-1.0, 1.0]:
		hexa(head, [Vector3(-0.02, 0.775, s * 0.035), Vector3(0.02, 0.775, s * 0.035), Vector3(0.02, 0.825, s * 0.035), Vector3(-0.02, 0.825, s * 0.035),
			Vector3(-0.004, 0.73, s * 0.27), Vector3(0.004, 0.73, s * 0.27), Vector3(0.004, 0.745, s * 0.27), Vector3(-0.004, 0.745, s * 0.27)])
	return _mesh([[h, wood()], [head, dark_steel()]])

func _sledge() -> Mesh:
	var h := _st()
	_handle(h, 0.8, 0.018, 0.016)
	var head := _st()
	box(head, Vector3(0, 0.82, 0), Vector3(0.075, 0.075, 0.2))
	var faces := _st()
	for s in [-1.0, 1.0]:
		box(faces, Vector3(0, 0.82, s * 0.104), Vector3(0.07, 0.07, 0.008))
	var grip := _st()
	Lib._tube(grip, Vector3(0, 0.0, 0), Vector3(0, 0.22, 0), 0.021, 0.021, 10)
	return _mesh([[h, wood()], [head, dark_steel()], [faces, steel()], [grip, rubber()]])

func _framing_hammer() -> Mesh:
	var h := _st()
	Lib._tube(h, Vector3(0, 0, 0), Vector3(0, 0.34, 0), 0.014, 0.012, 10)
	var grip := _st()
	Lib._tube(grip, Vector3(0, -0.01, 0), Vector3(0, 0.14, 0), 0.018, 0.017, 12)
	var head := _st()
	Lib._tube(head, Vector3(0, 0.35, -0.01), Vector3(0, 0.35, 0.07), 0.016, 0.018, 12)
	_disc(head, Vector3(0, 0.35, 0.07), 0.018, Vector3.BACK, 12)
	box(head, Vector3(0, 0.35, -0.005), Vector3(0.024, 0.04, 0.03))
	for s in [-1.0, 1.0]:
		hexa(head, [Vector3(s * 0.004 - 0.004, 0.34, -0.02), Vector3(s * 0.004 + 0.004, 0.34, -0.02), Vector3(s * 0.004 + 0.004, 0.36, -0.02), Vector3(s * 0.004 - 0.004, 0.36, -0.02),
			Vector3(s * 0.006 - 0.003, 0.32, -0.09), Vector3(s * 0.006 + 0.003, 0.32, -0.09), Vector3(s * 0.006 + 0.003, 0.33, -0.09), Vector3(s * 0.006 - 0.003, 0.33, -0.09)])
	return _mesh([[h, paint(Color(0.2, 0.35, 0.6))], [grip, rubber()], [head, steel()]])

func _blade_tool(length: float, width: float, handle_col: Color, curved: bool, kitchen := false) -> Mesh:
	var handle := _st()
	taper(handle, -0.01, Vector2(0.022, 0.03), 0.11, Vector2(0.024, 0.032))
	var guard := _st()
	if not kitchen:
		box(guard, Vector3(0, 0.115, 0), Vector3(0.03, 0.01, 0.06 if not curved else 0.04))
	var blade := _st()
	var tip_z := width * 0.5 if not curved else width * 0.9
	hexa(blade, [Vector3(-0.002, 0.12, -width * 0.45), Vector3(0.002, 0.12, -width * 0.45), Vector3(0.002, 0.12, width * 0.55), Vector3(-0.002, 0.12, width * 0.55),
		Vector3(-0.0005, 0.12 + length * 0.85, -width * 0.4), Vector3(0.0005, 0.12 + length * 0.85, -width * 0.4), Vector3(0.0005, 0.12 + length * 0.85, width * 0.6), Vector3(-0.0005, 0.12 + length * 0.85, width * 0.6)])
	hexa(blade, [Vector3(-0.0005, 0.12 + length * 0.85, -width * 0.4), Vector3(0.0005, 0.12 + length * 0.85, -width * 0.4), Vector3(0.0005, 0.12 + length * 0.85, width * 0.6), Vector3(-0.0005, 0.12 + length * 0.85, width * 0.6),
		Vector3(-0.0003, 0.12 + length, tip_z - width * 0.4), Vector3(0.0003, 0.12 + length, tip_z - width * 0.4), Vector3(0.0003, 0.12 + length, tip_z - width * 0.35), Vector3(-0.0003, 0.12 + length, tip_z - width * 0.35)])
	var rivets := _st()
	for y in [0.025, 0.08]:
		Lib._tube(rivets, Vector3(-0.0125, y, 0), Vector3(0.0125, y, 0), 0.004, 0.004, 8)
	var bm := steel() if not curved else m("metal", Color(0.75, 0.75, 0.72), 6.0, 0.45, 0.8)
	return _mesh([[handle, m("rubber", handle_col * 3.0, 12.0, 0.7) if not kitchen else c(handle_col, 0.35)], [guard, dark_steel()], [blade, bm], [rivets, steel()]])

func _spiked_bat() -> Mesh:
	var bat := _st()
	lathe(bat, [Vector2(0.0, -0.01), Vector2(0.018, -0.01), Vector2(0.014, 0.0), Vector2(0.013, 0.2), Vector2(0.022, 0.45), Vector2(0.032, 0.68), Vector2(0.03, 0.72), Vector2(0.0, 0.725)], 16)
	var tape := _st()
	Lib._tube(tape, Vector3(0, 0.01, 0), Vector3(0, 0.16, 0), 0.0155, 0.0155, 12)
	var nails := _st()
	for k in range(14):
		var a := k * 2.4
		var y := 0.48 + (k % 7) * 0.032
		var r := lerpf(0.024, 0.032, (y - 0.45) / 0.25)
		var d := Vector3(cos(a), 0, sin(a))
		Lib._tube(nails, Vector3(0, y, 0) + d * (r - 0.004), Vector3(0, y, 0) + d * (r + 0.035), 0.0018, 0.0008, 4)
	return _mesh([[bat, wood()], [tape, m("rubber", Color(0.5, 0.5, 0.52), 8.0, 0.8)], [nails, m("metal", Color(0.6, 0.55, 0.5), 8.0, 0.5, 0.7)]])

func _saw() -> Mesh:
	var handle := _st()
	hexa(handle, [Vector3(-0.012, -0.02, -0.05), Vector3(0.012, -0.02, -0.05), Vector3(0.012, -0.02, 0.04), Vector3(-0.012, -0.02, 0.04),
		Vector3(-0.012, 0.11, -0.05), Vector3(0.012, 0.11, -0.05), Vector3(0.012, 0.11, 0.06), Vector3(-0.012, 0.11, 0.06)])
	var hole := _st()
	box(hole, Vector3(0, 0.045, -0.01), Vector3(0.026, 0.05, 0.05))
	var blade := _st()
	hexa(blade, [Vector3(-0.001, 0.1, -0.04), Vector3(0.001, 0.1, -0.04), Vector3(0.001, 0.1, 0.06), Vector3(-0.001, 0.1, 0.06),
		Vector3(-0.001, 0.52, -0.02), Vector3(0.001, 0.52, -0.02), Vector3(0.001, 0.52, 0.01), Vector3(-0.001, 0.52, 0.01)])
	var teeth := _st()
	for k in range(26):
		var y := 0.11 + k * 0.016
		var z := lerpf(0.06, 0.01, (y - 0.1) / 0.42)
		hexa(teeth, [Vector3(-0.001, y, z), Vector3(0.001, y, z), Vector3(0.001, y + 0.008, z), Vector3(-0.001, y + 0.008, z),
			Vector3(-0.0005, y + 0.008, z + 0.006), Vector3(0.0005, y + 0.008, z + 0.006), Vector3(0.0005, y + 0.008, z + 0.006), Vector3(-0.0005, y + 0.008, z + 0.006)])
	return _mesh([[handle, dark_wood()], [hole, black_plastic()], [blade, steel()], [teeth, steel()]])

func _wrench() -> Mesh:
	var bar := _st()
	box(bar, Vector3(0, 0.12, 0), Vector3(0.008, 0.24, 0.022))
	var heads := _st()
	torus(heads, Vector3(0, 0.0, 0), 0.016, 0.006, 14, 6, Vector3.RIGHT)
	box(heads, Vector3(0, 0.265, 0), Vector3(0.012, 0.04, 0.05))
	for s in [-1.0, 1.0]:
		box(heads, Vector3(0, 0.295, s * 0.018), Vector3(0.012, 0.03, 0.012))
	Lib._tube(heads, Vector3(-0.008, 0.25, 0), Vector3(0.008, 0.25, 0), 0.009, 0.009, 10)
	var grip := _st()
	box(grip, Vector3(0, 0.1, 0), Vector3(0.012, 0.12, 0.026))
	return _mesh([[bar, steel()], [heads, steel()], [grip, paint(Color(0.8, 0.15, 0.1))]])

func _torch() -> Mesh:
	var h := _st()
	Lib._tube(h, Vector3(0, 0, 0), Vector3(0, 0.36, 0), 0.016, 0.019, 9, 2.0)
	var wrap := _st()
	ellipsoid(wrap, Vector3(0, 0.39, 0), Vector3(0.032, 0.06, 0.032), 6, 10, 0.25, 8)
	var flame := _st()
	ellipsoid(flame, Vector3(0, 0.46, 0), Vector3(0.025, 0.05, 0.025), 5, 8, 0.3, 2)
	return _mesh([[h, m("bark", Color(0.9, 0.8, 0.7), 6.0, 0.9)], [wrap, m("canvas", Color(0.45, 0.35, 0.25), 8.0, 0.95)], [flame, Lib.color_mat(Color(1.0, 0.6, 0.2, 0.85), 0.5, 0.0, Color(1.0, 0.55, 0.15), 4.0)]])

func _flare() -> Mesh:
	var tube_s := _st()
	Lib._tube(tube_s, Vector3(0, 0, 0), Vector3(0, 0.22, 0), 0.014, 0.014, 12)
	_disc(tube_s, Vector3(0, 0, 0), 0.014, Vector3.DOWN, 12)
	var cap := _st()
	lathe(cap, [Vector2(0.015, 0.2), Vector2(0.015, 0.235), Vector2(0.01, 0.24)], 12)
	var lab := _st()
	Lib._tube(lab, Vector3(0, 0.06, 0), Vector3(0, 0.14, 0), 0.0145, 0.0145, 12)
	var spark := _st()
	ellipsoid(spark, Vector3(0, 0.255, 0), Vector3(0.014, 0.022, 0.014), 4, 8, 0.3, 2)
	return _mesh([[tube_s, paint(Color(0.8, 0.08, 0.06))], [cap, black_plastic()], [lab, paint(Color(0.95, 0.85, 0.2))], [spark, Lib.color_mat(Color(1.0, 0.3, 0.25, 0.9), 0.5, 0.0, Color(1.0, 0.25, 0.2), 5.0)]])

func _glowstick() -> Mesh:
	var s := _st()
	lathe(s, [Vector2(0.0, 0.0), Vector2(0.008, 0.002), Vector2(0.008, 0.15), Vector2(0.0, 0.152)], 10)
	var caps := _st()
	lathe(caps, [Vector2(0.0085, 0.145), Vector2(0.0085, 0.16), Vector2(0.004, 0.162)], 8)
	torus(caps, Vector3(0, 0.168, 0), 0.006, 0.0015, 8, 4, Vector3.RIGHT)
	return _mesh([[s, Lib.color_mat(Color(0.4, 1.0, 0.5, 0.9), 0.2, 0.0, Color(0.3, 1.0, 0.4), 3.0)], [caps, c(Color(0.15, 0.6, 0.25), 0.4)]])

func _camp_lantern() -> Mesh:
	var base := _st()
	lathe(base, [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.05, 0.03), Vector2(0.04, 0.04)], 18)
	lathe(base, [Vector2(0.04, 0.15), Vector2(0.05, 0.16), Vector2(0.03, 0.175), Vector2(0.0, 0.178)], 18)
	var globe := _st()
	lathe(globe, [Vector2(0.036, 0.04), Vector2(0.042, 0.095), Vector2(0.036, 0.15)], 18, Vector3.ZERO, false, false)
	var bars := _st()
	for k in range(4):
		var a := TAU * k / 4.0
		Lib._tube(bars, Vector3(cos(a) * 0.044, 0.04, sin(a) * 0.044), Vector3(cos(a) * 0.044, 0.15, sin(a) * 0.044), 0.003, 0.003, 4)
	torus(bars, Vector3(0, 0.2, 0), 0.03, 0.004, 14, 5, Vector3.FORWARD)
	var glow := _st()
	ellipsoid(glow, Vector3(0, 0.095, 0), Vector3(0.012, 0.025, 0.012), 4, 8)
	return _mesh([[base, paint(Color(0.18, 0.45, 0.25))], [globe, Lib.color_mat(Color(1.0, 0.95, 0.85, 0.35), 0.1)], [bars, dark_steel()], [glow, Lib.color_mat(Color(1.0, 0.9, 0.7), 0.3, 0.0, Color(1.0, 0.85, 0.6), 3.0)]])

# ---- navigation & gadgets
func _compass() -> Mesh:
	var case_s := _st()
	lathe(case_s, [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.033, 0.006), Vector2(0.033, 0.014), Vector2(0.03, 0.016)], 24, Vector3.ZERO, true, false)
	torus(case_s, Vector3(0, 0.0, 0.038), 0.007, 0.002, 10, 4, Vector3.RIGHT)
	var face := _st()
	_disc(face, Vector3(0, 0.012, 0), 0.029, Vector3.UP, 24)
	var needle := _st()
	hexa(needle, [Vector3(-0.003, 0.013, 0), Vector3(0.003, 0.013, 0), Vector3(0.0, 0.013, 0.003), Vector3(0.0, 0.013, -0.003),
		Vector3(-0.0005, 0.0135, 0), Vector3(0.0005, 0.0135, 0), Vector3(0.0, 0.0135, 0.022), Vector3(0.0, 0.0135, 0.0)])
	var south := _st()
	hexa(south, [Vector3(-0.003, 0.013, 0), Vector3(0.003, 0.013, 0), Vector3(0.0, 0.013, -0.003), Vector3(0.0, 0.013, 0.003),
		Vector3(-0.0005, 0.0135, 0), Vector3(0.0005, 0.0135, 0), Vector3(0.0, 0.0135, -0.022), Vector3(0.0, 0.0135, 0.0)])
	var ticks := _st()
	for k in range(12):
		var a := TAU * k / 12.0
		box(ticks, Vector3(cos(a) * 0.025, 0.0125, sin(a) * 0.025), Vector3(0.004 if k % 3 == 0 else 0.002, 0.0005, 0.001), Basis(Vector3.UP, -a))
	var glass := _st()
	_disc(glass, Vector3(0, 0.0155, 0), 0.03, Vector3.UP, 24)
	return _mesh([[case_s, brass()], [face, c(Color(0.95, 0.93, 0.86), 0.5)], [needle, c(Color(0.85, 0.12, 0.1), 0.4)], [south, c(Color(0.9, 0.9, 0.92), 0.4)], [ticks, c(Color(0.1, 0.1, 0.1))], [glass, Lib.color_mat(Color(0.9, 0.95, 1.0, 0.18), 0.03)]])

func _roadmap() -> Mesh:
	var s := _st()
	for k in range(4):
		box(s, Vector3(0, 0.002 + k * 0.0025, 0), Vector3(0.11, 0.002, 0.24), Basis(Vector3.UP, (k % 2) * 0.01))
	var cover := _st()
	box(cover, Vector3(0, 0.0115, 0), Vector3(0.11, 0.0012, 0.24))
	var roads := _st()
	box(roads, Vector3(0.01, 0.0123, 0.02), Vector3(0.006, 0.0005, 0.18), Basis(Vector3.UP, 0.2))
	box(roads, Vector3(-0.02, 0.0123, -0.04), Vector3(0.08, 0.0005, 0.005), Basis(Vector3.UP, -0.3))
	var title := _st()
	box(title, Vector3(0, 0.0123, -0.09), Vector3(0.09, 0.0005, 0.03))
	return _mesh([[s, m("cardboard", Color(1.4, 1.35, 1.2), 6.0, 0.9)], [cover, c(Color(0.72, 0.85, 0.65), 0.8)], [roads, c(Color(0.85, 0.25, 0.15))], [title, paint(Color(0.15, 0.3, 0.6))]])

func _watch(case_col: Color, face_col: Color) -> Mesh:
	var strap := _st()
	torus(strap, Vector3(0, 0.03, 0), 0.03, 0.005, 24, 6, Vector3.RIGHT)
	var case_s := _st()
	lathe(case_s, [Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.02, 0.005), Vector2(0.019, 0.011), Vector2(0.0, 0.012)], 20, Vector3(0, 0.055, 0))
	var face := _st()
	_disc(face, Vector3(0, 0.0675, 0), 0.016, Vector3.UP, 20)
	var hands := _st()
	box(hands, Vector3(0.004, 0.068, 0.0), Vector3(0.009, 0.0005, 0.0015), Basis(Vector3.UP, 0.4))
	box(hands, Vector3(0, 0.068, -0.005), Vector3(0.0012, 0.0005, 0.012))
	var crown := _st()
	Lib._tube(crown, Vector3(0.019, 0.061, 0), Vector3(0.024, 0.061, 0), 0.002, 0.002, 6)
	return _mesh([[strap, leather() if case_col.v > 0.5 else rubber()], [case_s, m("metal", case_col, 6.0, 0.25, 0.9)], [face, c(face_col, 0.4)], [hands, c(Color(0.05, 0.05, 0.05) if face_col.v > 0.5 else Color(0.5, 1.0, 0.6))], [crown, steel()]])

func _crank_radio() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.06, 0), Vector3(0.16, 0.11, 0.06))
	var grille := _st()
	for k in range(6):
		box(grille, Vector3(-0.035, 0.035 + k * 0.012, 0.031), Vector3(0.06, 0.004, 0.002))
	var dial := _st()
	box(dial, Vector3(0.04, 0.085, 0.031), Vector3(0.06, 0.025, 0.002))
	var knobs := _st()
	Lib._tube(knobs, Vector3(0.05, 0.045, 0.03), Vector3(0.05, 0.045, 0.04), 0.01, 0.01, 10)
	Lib._tube(knobs, Vector3(0.082, 0.06, 0), Vector3(0.09, 0.06, 0), 0.012, 0.012, 10)
	Lib._tube(knobs, Vector3(0.09, 0.06, 0), Vector3(0.09, 0.1, 0.0), 0.004, 0.004, 6)
	Lib._tube(knobs, Vector3(0.09, 0.1, 0.0), Vector3(0.1, 0.1, 0.0), 0.006, 0.006, 6)
	var handle := _st()
	Lib._tube(handle, Vector3(-0.06, 0.115, 0), Vector3(0.06, 0.115, 0), 0.006, 0.006, 8)
	Lib._tube(handle, Vector3(-0.06, 0.115, 0), Vector3(-0.07, 0.1, 0), 0.006, 0.006, 8)
	Lib._tube(handle, Vector3(0.06, 0.115, 0), Vector3(0.07, 0.1, 0), 0.006, 0.006, 8)
	var ant := _st()
	Lib._tube(ant, Vector3(-0.07, 0.11, -0.02), Vector3(-0.1, 0.3, -0.03), 0.002, 0.0015, 5)
	return _mesh([[body, paint(Color(0.8, 0.25, 0.12))], [grille, black_plastic()], [dial, Lib.color_mat(Color(0.9, 0.85, 0.6), 0.3, 0.0, Color(0.9, 0.75, 0.4), 0.3)], [knobs, black_plastic()], [handle, black_plastic()], [ant, steel()]])

func _gps() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.05, 0), Vector3(0.12, 0.08, 0.025))
	var screen := _st()
	box(screen, Vector3(-0.01, 0.052, 0.0131), Vector3(0.085, 0.06, 0.001))
	var btn := _st()
	for k in range(3):
		box(btn, Vector3(0.048, 0.03 + k * 0.02, 0.0131), Vector3(0.012, 0.012, 0.002))
	var mount := _st()
	Lib._tube(mount, Vector3(0, 0.01, -0.012), Vector3(0, 0.0, -0.03), 0.006, 0.006, 8)
	lathe(mount, [Vector2(0.03, 0.0), Vector2(0.03, 0.006), Vector2(0.0, 0.008)], 16, Vector3(0, -0.004, -0.03))
	return _mesh([[body, black_plastic()], [screen, Lib.color_mat(Color(0.35, 0.6, 0.35), 0.15, 0.0, Color(0.4, 0.7, 0.35), 0.8)], [btn, c(Color(0.3, 0.3, 0.32), 0.5)], [mount, black_plastic()]])

# ---- camp cooking
func _skillet() -> Mesh:
	var pan := _st()
	lathe(pan, [Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.115, 0.04), Vector2(0.108, 0.04), Vector2(0.094, 0.008), Vector2(0.0, 0.008)], 28, Vector3.ZERO, false, false)
	var handle := _st()
	box(handle, Vector3(0.18, 0.032, 0), Vector3(0.14, 0.014, 0.026))
	torus(handle, Vector3(0.25, 0.032, 0), 0.01, 0.004, 10, 4)
	return _mesh([[pan, m("metal", Color(0.18, 0.18, 0.19), 6.0, 0.6, 0.6)], [handle, m("metal", Color(0.18, 0.18, 0.19), 6.0, 0.6, 0.6)]])

func _pot() -> Mesh:
	var p := _st()
	lathe(p, [Vector2(0.0, 0.0), Vector2(0.08, 0.0), Vector2(0.082, 0.01), Vector2(0.082, 0.12), Vector2(0.078, 0.12), Vector2(0.076, 0.012), Vector2(0.0, 0.012)], 26, Vector3.ZERO, false, false)
	var lid := _st()
	lathe(lid, [Vector2(0.084, 0.12), Vector2(0.06, 0.135), Vector2(0.0, 0.14)], 26, Vector3.ZERO, false, false)
	Lib._tube(lid, Vector3(-0.015, 0.145, 0), Vector3(0.015, 0.145, 0), 0.005, 0.005, 6)
	var bail := _st()
	var prev := Vector3(-0.084, 0.1, 0)
	for k in range(1, 13):
		var a := PI * k / 12.0
		var pt := Vector3(-cos(a) * 0.084, 0.1 + sin(a) * 0.09, 0)
		Lib._tube(bail, prev, pt, 0.0025, 0.0025, 5)
		prev = pt
	return _mesh([[p, m("metal", Color(0.8, 0.8, 0.82), 6.0, 0.4, 0.8)], [lid, m("metal", Color(0.75, 0.76, 0.78), 6.0, 0.4, 0.8)], [bail, steel()]])

func _percolator() -> Mesh:
	var body := _st()
	lathe(body, [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.055, 0.05), Vector2(0.045, 0.16), Vector2(0.04, 0.17)], 22)
	var top := _st()
	lathe(top, [Vector2(0.04, 0.17), Vector2(0.03, 0.18), Vector2(0.018, 0.182)], 18)
	var knob := _st()
	lathe(knob, [Vector2(0.016, 0.18), Vector2(0.018, 0.19), Vector2(0.012, 0.21), Vector2(0.0, 0.212)], 14)
	var spout := _st()
	Lib._tube(spout, Vector3(0.04, 0.08, 0), Vector3(0.075, 0.16, 0), 0.012, 0.006, 10)
	var handle := _st()
	Lib._tube(handle, Vector3(-0.05, 0.14, 0), Vector3(-0.08, 0.12, 0), 0.008, 0.008, 8)
	Lib._tube(handle, Vector3(-0.08, 0.12, 0), Vector3(-0.075, 0.04, 0), 0.008, 0.008, 8)
	Lib._tube(handle, Vector3(-0.075, 0.04, 0), Vector3(-0.053, 0.03, 0), 0.008, 0.008, 8)
	return _mesh([[body, steel()], [top, steel()], [knob, Lib.color_mat(Color(0.85, 0.92, 1.0, 0.4), 0.05)], [spout, steel()], [handle, black_plastic()]])

func _spork() -> Mesh:
	var s := _st()
	box(s, Vector3(0.0, 0.003, 0), Vector3(0.11, 0.003, 0.012))
	ellipsoid(s, Vector3(0.075, 0.006, 0), Vector3(0.025, 0.006, 0.018), 4, 10)
	var tines := _st()
	for k in range(3):
		box(tines, Vector3(0.1, 0.008, -0.008 + k * 0.008), Vector3(0.012, 0.002, 0.003))
	return _mesh([[s, m("metal", Color(0.6, 0.62, 0.72), 6.0, 0.3, 0.9)], [tines, m("metal", Color(0.6, 0.62, 0.72), 6.0, 0.3, 0.9)]])

# ---- apparel
func _folded_shirt(col: Color, ripped: bool) -> Mesh:
	var s := _st()
	box(s, Vector3(0, 0.014, 0), Vector3(0.24, 0.028, 0.2))
	box(s, Vector3(0, 0.032, 0.06), Vector3(0.24, 0.012, 0.08))
	var collar := _st()
	torus(collar, Vector3(0, 0.03, -0.07), 0.035, 0.007, 16, 5)
	var parts := [[s, m("canvas", col * 1.25, 6.0, 0.95)], [collar, m("canvas", col * 1.1, 6.0, 0.95)]]
	if ripped:
		var tear := _st()
		box(tear, Vector3(0.06, 0.0285, 0.03), Vector3(0.05, 0.001, 0.012), Basis(Vector3.UP, 0.5))
		box(tear, Vector3(-0.07, 0.0285, -0.02), Vector3(0.03, 0.001, 0.008), Basis(Vector3.UP, -0.3))
		parts.append([tear, c(Color(0.15, 0.13, 0.12), 0.9)])
	else:
		var pocket := _st()
		box(pocket, Vector3(0.06, 0.039, 0.06), Vector3(0.05, 0.002, 0.05))
		parts.append([pocket, m("canvas", col * 0.95, 6.0, 0.95)])
	return _mesh(parts)

func _hivis() -> Mesh:
	var s := _st()
	box(s, Vector3(0, 0.014, 0), Vector3(0.24, 0.028, 0.2))
	var stripes := _st()
	for z in [-0.04, 0.04]:
		box(stripes, Vector3(0, 0.0285, z), Vector3(0.24, 0.001, 0.018))
	return _mesh([[s, m("canvas", Color(1.4, 0.65, 0.15), 6.0, 0.9)], [stripes, Lib.color_mat(Color(0.85, 0.88, 0.9), 0.2, 0.6)]])

func _jacket_col(col: Color) -> Mesh:
	var body := _st()
	taper(body, 0.0, Vector2(0.4, 0.2), 0.5, Vector2(0.44, 0.18))
	box(body, Vector3(0, 0.52, 0), Vector3(0.2, 0.07, 0.17))
	for s in [-1.0, 1.0]:
		Lib._tube(body, Vector3(s * 0.22, 0.46, 0), Vector3(s * 0.32, 0.05, 0.02), 0.062, 0.05, 12)
	var zip := _st()
	box(zip, Vector3(0, 0.25, 0.1), Vector3(0.012, 0.48, 0.006))
	var trim := _st()
	for s in [-1.0, 1.0]:
		Lib._tube(trim, Vector3(s * 0.31, 0.08, 0.02), Vector3(s * 0.325, 0.03, 0.02), 0.052, 0.052, 12)
	box(trim, Vector3(0, 0.02, 0), Vector3(0.41, 0.04, 0.205))
	var seams := _st()
	for k in range(4):
		var y := 0.1 + k * 0.1
		var wdt := lerpf(0.4, 0.44, y / 0.5)
		box(seams, Vector3(0, y, 0.0), Vector3(wdt + 0.006, 0.006, 0.006 + lerpf(0.2, 0.18, y / 0.5)))
	return _mesh([[body, m("canvas", col * 1.7, 3.0, 0.75)], [seams, m("canvas", col * 1.2, 3.0, 0.8)], [zip, dark_steel()], [trim, m("rubber", Color(0.5, 0.5, 0.52), 8.0, 0.8)]])

func _vest() -> Mesh:
	var body := _st()
	for s in [-1.0, 1.0]:
		taper(body, 0.0, Vector2(0.18, 0.04), 0.46, Vector2(0.1, 0.04), Vector2(s * 0.1, 0.06), Vector2(s * 0.13, 0.06))
		taper(body, 0.42, Vector2(0.08, 0.16), 0.48, Vector2(0.07, 0.16), Vector2(s * 0.14, 0), Vector2(s * 0.14, 0))
	taper(body, 0.0, Vector2(0.38, 0.04), 0.46, Vector2(0.36, 0.04), Vector2(0, -0.06), Vector2(0, -0.06))
	var lace := _st()
	for k in range(4):
		box(lace, Vector3(0, 0.08 + k * 0.08, 0.09), Vector3(0.05, 0.004, 0.004), Basis(Vector3.FORWARD, 0.4 if k % 2 == 0 else -0.4))
	var studs := _st()
	for k in range(4):
		metal_sphere(studs, Vector3(-0.02, 0.08 + k * 0.08, 0.092), 0.005)
		metal_sphere(studs, Vector3(0.02, 0.08 + k * 0.08, 0.092), 0.005)
	return _mesh([[body, m("leather", Color(0.85, 0.6, 0.4), 3.0, 0.6)], [lace, c(Color(0.3, 0.2, 0.12))], [studs, brass()]])

func _poncho(mat: Material) -> Mesh:
	var s := _st()
	taper(s, 0.0, Vector2(0.34, 0.24), 0.05, Vector2(0.3, 0.2))
	taper(s, 0.05, Vector2(0.3, 0.2), 0.09, Vector2(0.2, 0.14))
	var hood := _st()
	ellipsoid(hood, Vector3(0, 0.1, -0.06), Vector3(0.08, 0.03, 0.06), 6, 10)
	return _mesh([[s, mat], [hood, mat]])

func _helmet() -> Mesh:
	var shell := _st()
	var prof := []
	for i in range(10):
		var a := PI * 0.5 * i / 9.0
		prof.append(Vector2(cos(a) * 0.12 + (0.012 if i == 0 else 0.0), 0.03 + sin(a) * 0.12))
	prof[0] = Vector2(0.13, 0.03)
	prof.insert(0, Vector2(0.13, 0.02))
	lathe(shell, prof, 26, Vector3.ZERO, false, true)
	var inner := _st()
	lathe(inner, [Vector2(0.115, 0.02), Vector2(0.115, 0.06)], 26, Vector3.ZERO, false, false)
	var strap := _st()
	for s in [-1.0, 1.0]:
		Lib._tube(strap, Vector3(s * 0.11, 0.04, 0), Vector3(s * 0.04, -0.02, 0.05), 0.006, 0.006, 4)
	Lib._tube(strap, Vector3(-0.04, -0.02, 0.05), Vector3(0.04, -0.02, 0.05), 0.006, 0.006, 4)
	var mount := _st()
	box(mount, Vector3(0, 0.12, 0.09), Vector3(0.05, 0.03, 0.02))
	return _mesh([[shell, m("canvas", Color(0.5, 0.58, 0.4), 6.0, 0.8)], [inner, c(Color(0.12, 0.12, 0.12))], [strap, c(Color(0.25, 0.28, 0.2))], [mount, dark_steel()]])

func _headlamp() -> Mesh:
	var band := _st()
	torus(band, Vector3(0, 0.05, 0), 0.07, 0.008, 28, 4, Vector3.UP)
	var lamp := _st()
	box(lamp, Vector3(0, 0.05, 0.08), Vector3(0.05, 0.035, 0.03))
	var lens := _st()
	_disc(lens, Vector3(0, 0.05, 0.0955), 0.014, Vector3.BACK, 14)
	return _mesh([[band, m("canvas", Color(0.3, 0.3, 0.3), 12.0, 0.9)], [lamp, black_plastic()], [lens, Lib.color_mat(Color(0.95, 0.95, 0.9), 0.05, 0.3, Color(1, 1, 0.9), 0.4)]])

func _goggles() -> Mesh:
	var frame := _st()
	for s in [-1.0, 1.0]:
		lathe(frame, [Vector2(0.03, 0.0), Vector2(0.03, 0.025), Vector2(0.028, 0.03)], 16, Vector3(s * 0.035, 0, 0), false, false)
	Lib._tube(frame, Vector3(-0.005, 0.015, 0), Vector3(0.005, 0.015, 0), 0.006, 0.006, 6)
	var lens := _st()
	for s in [-1.0, 1.0]:
		_disc(lens, Vector3(s * 0.035, 0.028, 0), 0.027, Vector3.UP, 16)
	var strap := _st()
	box(strap, Vector3(0, 0.012, -0.04), Vector3(0.14, 0.018, 0.004))
	var mi := _mesh([[frame, m("leather", Color(0.8, 0.6, 0.4), 6.0, 0.6)], [lens, Lib.color_mat(Color(0.55, 0.4, 0.15, 0.6), 0.05, 0.3)], [strap, c(Color(0.25, 0.2, 0.15))]])
	return _rotated(mi, Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.035, 0))

func _sack_bag() -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.15, 0), Vector3(0.14, 0.15, 0.1), 8, 14, 0.15, 6)
	lathe(s, [Vector2(0.05, 0.27), Vector2(0.035, 0.31), Vector2(0.06, 0.34)], 12)
	var tie := _st()
	torus(tie, Vector3(0, 0.3, 0), 0.04, 0.006, 12, 4)
	Lib._tube(tie, Vector3(0.0, 0.3, -0.04), Vector3(0.0, 0.05, -0.1), 0.008, 0.008, 5)
	return _mesh([[s, m("canvas", Color(1.0, 0.85, 0.55), 2.0, 1.0)], [tie, c(Color(0.5, 0.4, 0.25))]])

func _backpack_v(col: Color, size: float, frame: bool) -> Mesh:
	var k := size
	var body := _st()
	ellipsoid(body, Vector3(0, 0.25 * k, 0), Vector3(0.17, 0.25 * k, 0.11 * k), 10, 16)
	var pocket := _st()
	ellipsoid(pocket, Vector3(0, 0.15 * k, 0.1 * k), Vector3(0.12, 0.1 * k, 0.05), 8, 12)
	for s in [-1.0, 1.0]:
		ellipsoid(pocket, Vector3(s * 0.165, 0.18 * k, 0.0), Vector3(0.035, 0.08 * k, 0.06), 6, 10)
	var lid := _st()
	ellipsoid(lid, Vector3(0, 0.48 * k, 0.01), Vector3(0.16, 0.05, 0.12 * k), 6, 14)
	var straps := _st()
	for x in [-0.08, 0.08]:
		Lib._tube(straps, Vector3(x, 0.46 * k, -0.09 * k), Vector3(x, 0.08, -0.12 * k), 0.018, 0.018, 6)
		box(straps, Vector3(x * 0.8, 0.35 * k, 0.12 * k), Vector3(0.022, 0.18 * k, 0.006))
	torus(straps, Vector3(0, 0.53 * k, 0), 0.04, 0.01, 12, 5, Vector3.RIGHT)
	var buckles := _st()
	for x in [-0.064, 0.064]:
		box(buckles, Vector3(x, 0.27 * k, 0.125 * k), Vector3(0.03, 0.02, 0.01))
	var parts := [[body, m("canvas", col * 1.6, 4.0, 0.9)], [pocket, m("canvas", col * 1.3, 4.0, 0.9)], [lid, m("canvas", col * 1.2, 4.0, 0.9)], [straps, c(Color(0.12, 0.12, 0.12), 0.8)], [buckles, black_plastic()]]
	if frame:
		var fr := _st()
		for x in [-0.12, 0.12]:
			Lib._tube(fr, Vector3(x, 0.0, -0.12 * k), Vector3(x, 0.6 * k, -0.12 * k), 0.008, 0.008, 6)
		Lib._tube(fr, Vector3(-0.12, 0.6 * k, -0.12 * k), Vector3(0.12, 0.6 * k, -0.12 * k), 0.008, 0.008, 6)
		var roll := _st()
		Lib._tube(roll, Vector3(-0.17, 0.05, 0.02), Vector3(0.17, 0.05, 0.02), 0.05, 0.05, 14)
		_disc(roll, Vector3(-0.17, 0.05, 0.02), 0.05, Vector3.LEFT, 14)
		_disc(roll, Vector3(0.17, 0.05, 0.02), 0.05, Vector3.RIGHT, 14)
		parts.append([fr, m("metal", Color(0.7, 0.72, 0.74), 6.0, 0.35, 0.8)])
		parts.append([roll, m("canvas", Color(0.5, 0.75, 0.55), 6.0, 0.9)])
	return _mesh(parts)

# ---- electronics
func _pcb() -> Mesh:
	var board := _st()
	box(board, Vector3(0, 0.002, 0), Vector3(0.12, 0.003, 0.08))
	var comps := _st()
	box(comps, Vector3(-0.02, 0.007, 0.0), Vector3(0.03, 0.006, 0.03))
	for k in range(5):
		lathe(comps, [Vector2(0.004, 0.0035), Vector2(0.004, 0.016), Vector2(0.0, 0.017)], 8, Vector3(0.03 + (k % 2) * 0.012, 0, -0.025 + k * 0.012))
	var traces := _st()
	for k in range(7):
		box(traces, Vector3(0, 0.0036, -0.03 + k * 0.01), Vector3(0.1, 0.0002, 0.0015))
	var solder := _st()
	for k in range(8):
		box(solder, Vector3(-0.04 + k * 0.004, 0.006, 0.018), Vector3(0.002, 0.004, 0.002))
	return _mesh([[board, c(Color(0.12, 0.45, 0.22), 0.5)], [comps, black_plastic()], [traces, c(Color(0.85, 0.65, 0.3), 0.3, 0.8)], [solder, steel()]])

func _chip() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.003, 0), Vector3(0.04, 0.005, 0.04))
	var pins := _st()
	for k in range(8):
		for s in [-1.0, 1.0]:
			box(pins, Vector3(-0.0175 + k * 0.005, 0.002, s * 0.023), Vector3(0.0022, 0.002, 0.008))
			box(pins, Vector3(s * 0.023, 0.002, -0.0175 + k * 0.005), Vector3(0.008, 0.002, 0.0022))
	var die := _st()
	box(die, Vector3(0, 0.0058, 0), Vector3(0.02, 0.0005, 0.02))
	return _mesh([[b, c(Color(0.08, 0.08, 0.09), 0.4)], [pins, m("metal", Color(0.9, 0.85, 0.7), 8.0, 0.3, 0.9)], [die, c(Color(0.25, 0.25, 0.3), 0.2, 0.5)]])

func _relay() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.02, 0), Vector3(0.035, 0.04, 0.03))
	var pins := _st()
	for x in [-0.01, 0.01]:
		for z in [-0.008, 0.008]:
			box(pins, Vector3(x, -0.005, z), Vector3(0.004, 0.012, 0.0015))
	return _mesh([[b, c(Color(0.2, 0.35, 0.7), 0.3)], [pins, m("metal", Color(0.9, 0.85, 0.7), 8.0, 0.3, 0.9)]])

func _fuse() -> Mesh:
	var body := _st()
	Lib._tube(body, Vector3(-0.025, 0.008, 0), Vector3(0.025, 0.008, 0), 0.008, 0.008, 12)
	var caps := _st()
	for s in [-1.0, 1.0]:
		tube(caps, Vector3(s * 0.025, 0.008, 0), Vector3(s * 0.035, 0.008, 0), 0.0085, 0.0085, 12)
	var wire := _st()
	Lib._tube(wire, Vector3(-0.024, 0.008, 0), Vector3(0.024, 0.008, 0), 0.0008, 0.0008, 4)
	return _mesh([[body, Lib.color_mat(Color(0.9, 0.95, 1.0, 0.35), 0.05)], [caps, m("metal", Color(0.95, 0.75, 0.35), 8.0, 0.3, 0.9)], [wire, steel()]])

func _bulb() -> Mesh:
	var glass := _st()
	lathe(glass, [Vector2(0.012, 0.03), Vector2(0.022, 0.045), Vector2(0.03, 0.07), Vector2(0.026, 0.095), Vector2(0.0, 0.103)], 18, Vector3.ZERO, false, true)
	var base := _st()
	lathe(base, [Vector2(0.0, 0.0), Vector2(0.006, 0.0), Vector2(0.012, 0.005), Vector2(0.013, 0.03)], 14)
	var thread := _st()
	for k in range(4):
		torus(thread, Vector3(0, 0.009 + k * 0.006, 0), 0.0128, 0.0015, 14, 4)
	var fil := _st()
	Lib._tube(fil, Vector3(-0.006, 0.035, 0), Vector3(-0.006, 0.065, 0), 0.0008, 0.0008, 4)
	Lib._tube(fil, Vector3(0.006, 0.035, 0), Vector3(0.006, 0.065, 0), 0.0008, 0.0008, 4)
	Lib._tube(fil, Vector3(-0.006, 0.065, 0), Vector3(0.006, 0.065, 0), 0.0012, 0.0012, 4)
	var gm := Lib.color_mat(Color(0.95, 0.97, 1.0, 0.3), 0.02, 0.1).duplicate()
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh([[glass, gm], [base, steel()], [thread, steel()], [fil, c(Color(0.4, 0.35, 0.3))]])

func _spool() -> Mesh:
	var flange := _st()
	for y in [0.0, 0.08]:
		lathe(flange, [Vector2(0.012, y), Vector2(0.06, y), Vector2(0.06, y + 0.008), Vector2(0.012, y + 0.008)], 22)
	var core := _st()
	lathe(core, [Vector2(0.045, 0.008), Vector2(0.045, 0.08)], 22, Vector3.ZERO, false, false)
	var wraps := _st()
	for k in range(10):
		torus(wraps, Vector3(0, 0.012 + k * 0.0072, 0), 0.046, 0.0036, 22, 4)
	return _mesh([[flange, black_plastic()], [core, c(Color(0.8, 0.45, 0.2), 0.35, 0.8)], [wraps, m("metal", Color(0.95, 0.55, 0.3), 8.0, 0.3, 0.9)]])

# ---- salvage & junk
func _plate() -> Mesh:
	var p := _st()
	box(p, Vector3(0, 0.002, 0), Vector3(0.3, 0.003, 0.15))
	var rim := _st()
	for z in [-0.072, 0.072]:
		box(rim, Vector3(0, 0.004, z), Vector3(0.3, 0.003, 0.006))
	for x in [-0.147, 0.147]:
		box(rim, Vector3(x, 0.004, 0), Vector3(0.006, 0.003, 0.15))
	var chars := _st()
	for k in range(6):
		box(chars, Vector3(-0.1 + k * 0.04, 0.0045, 0.005), Vector3(0.022, 0.002, 0.07))
	var rust := _st()
	ellipsoid(rust, Vector3(0.11, 0.0036, -0.04), Vector3(0.04, 0.001, 0.03), 3, 10, 0.4, 3)
	ellipsoid(rust, Vector3(-0.12, 0.0036, 0.05), Vector3(0.03, 0.001, 0.02), 3, 10, 0.4, 5)
	return _mesh([[p, paint(Color(0.92, 0.9, 0.8))], [rim, paint(Color(0.2, 0.3, 0.55))], [chars, paint(Color(0.15, 0.2, 0.45))], [rust, m("rust", Color.WHITE, 8.0, 0.9)]])

func _silverware() -> Mesh:
	var s := _st()
	Lib._tube(s, Vector3(-0.08, 0.004, 0), Vector3(0.0, 0.01, 0), 0.004, 0.003, 6)
	Lib._tube(s, Vector3(0.0, 0.01, 0), Vector3(0.05, 0.004, 0.01), 0.003, 0.003, 6)
	ellipsoid(s, Vector3(0.07, 0.006, 0.015), Vector3(0.022, 0.006, 0.015), 4, 10)
	Lib._tube(s, Vector3(-0.07, 0.004, 0.04), Vector3(0.04, 0.012, 0.03), 0.003, 0.003, 6)
	for k in range(3):
		box(s, Vector3(0.06, 0.012, 0.022 + k * 0.007), Vector3(0.03, 0.002, 0.002), Basis(Vector3.FORWARD, 0.3))
	return _mesh([[s, m("metal", Color(0.8, 0.8, 0.82), 6.0, 0.35, 0.85)]])

func _rusty_can() -> Mesh:
	var c0 := _st()
	lathe(c0, [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.042, 0.005), Vector2(0.041, 0.1)], 20, Vector3.ZERO, true, false)
	var lid := _st()
	box(lid, Vector3(0.01, 0.112, 0.02), Vector3(0.07, 0.002, 0.06), Basis(Vector3.RIGHT, -0.9))
	var lab := _st()
	lathe(lab, [Vector2(0.0415, 0.02), Vector2(0.0415, 0.08)], 20, Vector3.ZERO, false, false)
	return _mesh([[c0, m("rust", Color.WHITE, 8.0, 0.8, 0.3)], [lid, m("rust", Color.WHITE, 8.0, 0.8, 0.3)], [lab, m("cardboard", Color(1.1, 0.55, 0.4), 6.0, 0.9)]])

func _magazine() -> Mesh:
	var s := _st()
	for k in range(3):
		box(s, Vector3(0, 0.002 + k * 0.003, 0), Vector3(0.21, 0.003, 0.28), Basis(Vector3.UP, k * 0.03))
	var cover := _st()
	box(cover, Vector3(0, 0.0105, 0), Vector3(0.21, 0.001, 0.28))
	var art := _st()
	box(art, Vector3(0, 0.0112, 0.02), Vector3(0.16, 0.0005, 0.16))
	box(art, Vector3(0, 0.0112, -0.11), Vector3(0.18, 0.0005, 0.04))
	return _mesh([[s, m("cardboard", Color(1.2, 1.15, 1.0), 6.0, 0.95)], [cover, m("cardboard", Color(1.2, 1.1, 1.0), 4.0, 0.7)], [art, m("paint", Color(0.35, 0.55, 0.7), 2.0, 0.8)]])

func _pocket_watch() -> Mesh:
	var case_s := _st()
	lathe(case_s, [Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.027, 0.006), Vector2(0.024, 0.012)], 22, Vector3.ZERO, true, false)
	lathe(case_s, [Vector2(0.004, 0.0), Vector2(0.004, 0.01)], 8, Vector3(0, 0, 0.03))
	torus(case_s, Vector3(0, 0.005, 0.038), 0.006, 0.0018, 10, 4, Vector3.RIGHT)
	var face := _st()
	_disc(face, Vector3(0, 0.0105, 0), 0.022, Vector3.UP, 22)
	var crack := _st()
	box(crack, Vector3(0.003, 0.0112, 0.002), Vector3(0.03, 0.0004, 0.001), Basis(Vector3.UP, 0.7))
	box(crack, Vector3(-0.006, 0.0112, -0.004), Vector3(0.018, 0.0004, 0.001), Basis(Vector3.UP, -0.4))
	var chain := _st()
	for k in range(8):
		torus(chain, Vector3(0.0, 0.002, 0.048 + k * 0.007), 0.004, 0.0012, 8, 3, Vector3.UP if k % 2 == 0 else Vector3.RIGHT)
	return _mesh([[case_s, brass()], [face, c(Color(0.92, 0.9, 0.82), 0.5)], [crack, c(Color(0.2, 0.2, 0.2))], [chain, brass()]])

func _spring() -> Mesh:
	var s := _st()
	var prev := Vector3(0.018, 0.0, 0)
	for k in range(1, 73):
		var a := TAU * k / 12.0
		var p := Vector3(cos(a) * 0.018, k * 0.0014, sin(a) * 0.018)
		Lib._tube(s, prev, p, 0.0025, 0.0025, 5)
		prev = p
	return _mesh([[s, m("rust", Color(1.0, 0.9, 0.85), 10.0, 0.7, 0.5)]])

func _hanger() -> Mesh:
	var s := _st()
	var pts := [Vector3(-0.2, 0.004, 0.0), Vector3(0.2, 0.004, 0.0), Vector3(0.0, 0.004, -0.13), Vector3(-0.2, 0.004, 0.0)]
	for i in range(3):
		Lib._tube(s, pts[i], pts[i + 1], 0.0022, 0.0022, 5)
	var prev := Vector3(0.0, 0.004, -0.13)
	for k in range(1, 9):
		var a := PI * 1.3 * k / 8.0
		var p := Vector3(sin(a) * 0.02, 0.004, -0.15 - (1.0 - cos(a)) * 0.02 + 0.02)
		Lib._tube(s, prev, p, 0.0022, 0.0022, 5)
		prev = p
	return _mesh([[s, m("metal", Color(0.75, 0.75, 0.78), 6.0, 0.4, 0.8)]])

func _aerosol() -> Mesh:
	var b := _st()
	lathe(b, [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.032, 0.006), Vector2(0.032, 0.16), Vector2(0.024, 0.175), Vector2(0.012, 0.18)], 20)
	var nozzle := _st()
	lathe(nozzle, [Vector2(0.008, 0.18), Vector2(0.008, 0.192), Vector2(0.0, 0.193)], 10)
	var lab := _st()
	lathe(lab, [Vector2(0.0325, 0.03), Vector2(0.0325, 0.13)], 20, Vector3.ZERO, false, false)
	var dent := _st()
	ellipsoid(dent, Vector3(0.028, 0.09, 0.012), Vector3(0.008, 0.02, 0.012), 4, 8)
	return _mesh([[b, steel()], [nozzle, white_plastic()], [lab, paint(Color(0.3, 0.5, 0.75))], [dent, m("rust", Color.WHITE, 10.0)]])

func _broken_bottle() -> Mesh:
	var b := _st()
	lathe(b, [Vector2(0.0, 0.0), Vector2(0.034, 0.002), Vector2(0.036, 0.02), Vector2(0.036, 0.08)], 18, Vector3.ZERO, true, false)
	var shards := _st()
	for k in range(5):
		var a := TAU * k / 5.0
		hexa(shards, [Vector3(cos(a) * 0.034, 0.08, sin(a) * 0.034), Vector3(cos(a + 0.5) * 0.034, 0.08, sin(a + 0.5) * 0.034), Vector3(cos(a + 0.5) * 0.031, 0.08, sin(a + 0.5) * 0.031), Vector3(cos(a) * 0.031, 0.08, sin(a) * 0.031),
			Vector3(cos(a + 0.25) * 0.034, 0.1 + (k % 3) * 0.012, sin(a + 0.25) * 0.034), Vector3(cos(a + 0.26) * 0.034, 0.1 + (k % 3) * 0.012, sin(a + 0.26) * 0.034), Vector3(cos(a + 0.26) * 0.032, 0.1 + (k % 3) * 0.012, sin(a + 0.26) * 0.032), Vector3(cos(a + 0.25) * 0.032, 0.1 + (k % 3) * 0.012, sin(a + 0.25) * 0.032)])
		ellipsoid(shards, Vector3(cos(a) * 0.07, 0.003, sin(a) * 0.06), Vector3(0.012, 0.002, 0.008), 2, 5, 0.4, k)
	var gm := Lib.color_mat(Color(0.3, 0.55, 0.3, 0.45), 0.05, 0.1).duplicate()
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh([[b, gm], [shards, gm]])

# ---- roadside & vehicle parts
func _triangle() -> Mesh:
	var fr := _st()
	var pts := [Vector3(-0.2, 0.03, 0), Vector3(0.2, 0.03, 0), Vector3(0.0, 0.38, 0)]
	for i in range(3):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 3]
		var mid := (a + b) * 0.5
		var dir := (b - a)
		box(fr, mid, Vector3(dir.length(), 0.035, 0.012), Basis(Vector3.BACK, atan2(dir.y, dir.x)))
	var inner := _st()
	for i in range(3):
		var a: Vector3 = pts[i] * 0.7 + Vector3(0, 0.03 + 0.06, 0.002)
		var b: Vector3 = pts[(i + 1) % 3] * 0.7 + Vector3(0, 0.09, 0.002)
		var mid := (a + b) * 0.5
		var dir := (b - a)
		box(inner, mid, Vector3(dir.length(), 0.02, 0.012), Basis(Vector3.BACK, atan2(dir.y, dir.x)))
	var stand := _st()
	box(stand, Vector3(0, 0.01, 0.05), Vector3(0.32, 0.012, 0.012))
	Lib._tube(stand, Vector3(-0.15, 0.01, 0.0), Vector3(-0.15, 0.01, 0.1), 0.005, 0.005, 6)
	Lib._tube(stand, Vector3(0.15, 0.01, 0.0), Vector3(0.15, 0.01, 0.1), 0.005, 0.005, 6)
	return _mesh([[fr, Lib.color_mat(Color(0.9, 0.08, 0.06), 0.25, 0.1, Color(0.6, 0.05, 0.03), 0.3)], [inner, Lib.color_mat(Color(1.0, 0.45, 0.1), 0.3)], [stand, dark_steel()]])

func _hubcap() -> Mesh:
	var s := _st()
	lathe(s, [Vector2(0.0, 0.045), Vector2(0.04, 0.042), Vector2(0.12, 0.03), Vector2(0.18, 0.012), Vector2(0.19, 0.0)], 32, Vector3.ZERO, false, true)
	var spokes := _st()
	for k in range(8):
		var a := TAU * k / 8.0
		box(spokes, Vector3(cos(a) * 0.1, 0.035, sin(a) * 0.1), Vector3(0.13, 0.008, 0.02), Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -0.15))
	var rust := _st()
	ellipsoid(rust, Vector3(0.12, 0.028, 0.05), Vector3(0.04, 0.004, 0.03), 3, 8, 0.4, 2)
	return _mesh([[s, steel()], [spokes, m("metal", Color(0.75, 0.76, 0.78), 6.0, 0.3, 0.9)], [rust, m("rust", Color.WHITE, 8.0)]])

func _side_mirror() -> Mesh:
	var h := _st()
	ellipsoid(h, Vector3(0, 0.09, 0), Vector3(0.11, 0.07, 0.045), 8, 14)
	var arm := _st()
	box(arm, Vector3(0.07, 0.03, 0.0), Vector3(0.12, 0.03, 0.03), Basis(Vector3.BACK, 0.5))
	box(arm, Vector3(0.13, 0.0, 0), Vector3(0.06, 0.02, 0.07))
	var glass := _st()
	ellipsoid(glass, Vector3(0, 0.09, 0.03), Vector3(0.095, 0.058, 0.018), 6, 14)
	return _mesh([[h, black_plastic()], [arm, black_plastic()], [glass, m("metal", Color(0.85, 0.9, 0.95), 2.0, 0.02, 1.0)]])

func _taillight() -> Mesh:
	var hous := _st()
	box(hous, Vector3(0, 0.04, -0.01), Vector3(0.12, 0.08, 0.04))
	var lens := _st()
	box(lens, Vector3(0, 0.05, 0.012), Vector3(0.11, 0.05, 0.008))
	var amber := _st()
	box(amber, Vector3(0, 0.017, 0.012), Vector3(0.11, 0.016, 0.008))
	return _mesh([[hous, black_plastic()], [lens, Lib.color_mat(Color(0.75, 0.05, 0.05, 0.85), 0.1, 0.2)], [amber, Lib.color_mat(Color(1.0, 0.6, 0.1, 0.85), 0.1, 0.2)]])

func _alternator() -> Mesh:
	var body := _st()
	lathe(body, [Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.065, 0.02), Vector2(0.065, 0.1), Vector2(0.055, 0.12), Vector2(0.0, 0.12)], 20)
	var fins := _st()
	for k in range(12):
		var a := TAU * k / 12.0
		box(fins, Vector3(cos(a) * 0.06, 0.06, sin(a) * 0.06), Vector3(0.006, 0.08, 0.016), Basis(Vector3.UP, -a))
	var pulley := _st()
	lathe(pulley, [Vector2(0.008, 0.12), Vector2(0.03, 0.12), Vector2(0.025, 0.135), Vector2(0.03, 0.15), Vector2(0.008, 0.15)], 18)
	var ears := _st()
	for s in [-1.0, 1.0]:
		box(ears, Vector3(s * 0.075, 0.03, 0), Vector3(0.03, 0.02, 0.025))
	return _mesh([[body, m("metal", Color(0.75, 0.76, 0.78), 6.0, 0.5, 0.7)], [fins, dark_steel()], [pulley, dark_steel()], [ears, m("metal", Color(0.75, 0.76, 0.78), 6.0, 0.5, 0.7)]])

func _starter() -> Mesh:
	var motor := _st()
	Lib._tube(motor, Vector3(-0.08, 0.045, 0), Vector3(0.05, 0.045, 0), 0.045, 0.045, 18)
	_disc(motor, Vector3(-0.08, 0.045, 0), 0.045, Vector3.LEFT, 18)
	var sol := _st()
	Lib._tube(sol, Vector3(-0.05, 0.1, 0), Vector3(0.05, 0.1, 0), 0.022, 0.022, 14)
	_disc(sol, Vector3(-0.05, 0.1, 0), 0.022, Vector3.LEFT, 14)
	var nose := _st()
	lathe(nose, [Vector2(0.045, 0.0), Vector2(0.04, 0.03), Vector2(0.012, 0.035), Vector2(0.012, 0.06)], 14)
	var mi := _mesh([[motor, paint(Color(0.15, 0.15, 0.17))], [sol, steel()]])
	var nm := _mesh([[nose, m("metal", Color(0.7, 0.7, 0.72), 6.0, 0.5, 0.7)]])
	var rn := _rotated(nm, Basis(Vector3.BACK, -PI * 0.5), Vector3(0.05, 0.045, 0))
	var out := mi
	var stn := SurfaceTool.new()
	stn.create_from(rn, 0)
	stn.commit(out)
	out.surface_set_material(out.get_surface_count() - 1, rn.surface_get_material(0))
	return out

func _radiator() -> Mesh:
	var core := _st()
	box(core, Vector3(0, 0.15, 0), Vector3(0.5, 0.26, 0.04))
	var tanks := _st()
	for x in [-0.27, 0.27]:
		box(tanks, Vector3(x, 0.15, 0), Vector3(0.04, 0.3, 0.06))
	Lib._tube(tanks, Vector3(0.27, 0.27, 0.0), Vector3(0.27, 0.3, 0.0), 0.012, 0.012, 10)
	Lib._tube(tanks, Vector3(-0.27, 0.06, 0.0), Vector3(-0.32, 0.06, 0.0), 0.018, 0.018, 10)
	Lib._tube(tanks, Vector3(0.27, 0.24, 0.0), Vector3(0.32, 0.24, 0.0), 0.018, 0.018, 10)
	var fins := _st()
	for k in range(24):
		box(fins, Vector3(-0.23 + k * 0.02, 0.15, 0.0205), Vector3(0.004, 0.25, 0.001))
	return _mesh([[core, dark_steel()], [tanks, black_plastic()], [fins, m("metal", Color(0.7, 0.7, 0.72), 4.0, 0.4, 0.8)]])

# ------------------------------------------------------------------ 1.8 performance parts and van add-ons
func _engine_block_tier(tier: int) -> Mesh:
	var blk := _st()
	taper(blk, 0.0, Vector2(0.5, 0.3), 0.12, Vector2(0.56, 0.36))
	box(blk, Vector3(0, 0.25, 0), Vector3(0.56, 0.26, 0.36))
	if tier == 3:
		# V8: two angled cylinder banks
		for sx in [-1.0, 1.0]:
			box(blk, Vector3(0, 0.42, sx * 0.12), Vector3(0.54, 0.12, 0.16), Basis(Vector3.RIGHT, sx * 0.45))
	else:
		taper(blk, 0.38, Vector2(0.56, 0.36), 0.44, Vector2(0.5, 0.28))
	var cover := _st()
	if tier == 3:
		for sx in [-1.0, 1.0]:
			box(cover, Vector3(0, 0.5, sx * 0.16), Vector3(0.5, 0.05, 0.13), Basis(Vector3.RIGHT, sx * 0.45))
	else:
		box(cover, Vector3(0, 0.47, 0), Vector3(0.48, 0.06, 0.22))
		for i in range(4):
			lathe(cover, [Vector2(0.016, 0.5), Vector2(0.016, 0.53)], 10, Vector3(-0.18 + i * 0.12, 0, 0))
	var pulleys := _st()
	for p in [[Vector3(-0.29, 0.2, 0.05), 0.08], [Vector3(-0.29, 0.38, -0.08), 0.05], [Vector3(-0.29, 0.34, 0.12), 0.04]]:
		Lib._tube(pulleys, p[0] + Vector3(0.02, 0, 0), p[0] - Vector3(0.02, 0, 0), p[1], p[1], 20)
		_disc(pulleys, p[0] - Vector3(0.02, 0, 0), p[1], Vector3.LEFT, 20)
	var extra := _st()
	if tier == 3:
		# the blower on top with its intake scoop
		box(extra, Vector3(0, 0.6, 0), Vector3(0.4, 0.12, 0.18))
		for k in range(6):
			box(extra, Vector3(-0.15 + k * 0.06, 0.67, 0), Vector3(0.012, 0.03, 0.2))
		taper(extra, 0.68, Vector2(0.22, 0.16), 0.8, Vector2(0.18, 0.12))
	else:
		# a polished intake plenum
		Lib._tube(extra, Vector3(-0.2, 0.55, 0), Vector3(0.2, 0.55, 0), 0.05, 0.05, 16)
		lathe(extra, [Vector2(0.0, 0.5), Vector2(0.06, 0.5), Vector2(0.07, 0.58), Vector2(0.0, 0.6)], 16, Vector3(0.24, 0, 0))
	var col := Color(0.15, 0.32, 0.6) if tier == 2 else Color(0.75, 0.1, 0.06)
	return _mesh([[blk, m("metal", Color(0.36, 0.38, 0.4), 4.0, 0.5, 0.7)], [cover, paint(col)], [pulleys, dark_steel()],
		[extra, m("metal", Color(0.92, 0.92, 0.95), 6.0, 0.2, 0.95)]])

func _turbo() -> Mesh:
	var snail := _st()
	torus(snail, Vector3(0, 0.12, 0), 0.07, 0.045, 22, 10, Vector3.FORWARD)
	lathe(snail, [Vector2(0.0, -0.04), Vector2(0.06, -0.04), Vector2(0.06, 0.04), Vector2(0.0, 0.04)], 20, Vector3.ZERO)
	var outlet := _st()
	Lib._tube(outlet, Vector3(0.07, 0.15, 0), Vector3(0.2, 0.17, 0), 0.035, 0.035, 14)
	Lib._tube(outlet, Vector3(0, 0.12, 0.04), Vector3(0, 0.12, 0.12), 0.05, 0.055, 18)
	var cold := _st()
	torus(cold, Vector3(0, 0.12, -0.09), 0.06, 0.04, 20, 10, Vector3.FORWARD)
	Lib._tube(cold, Vector3(0, 0.12, -0.04), Vector3(0, 0.12, -0.09), 0.03, 0.03, 12)
	var flange := _st()
	box(flange, Vector3(0, 0.03, 0.0), Vector3(0.1, 0.02, 0.08))
	return _mesh([[snail, m("rust", Color(0.55, 0.45, 0.4), 6.0, 0.6, 0.6)], [outlet, steel()], [cold, m("metal", Color(0.85, 0.85, 0.88), 6.0, 0.3, 0.9)], [flange, dark_steel()]])

func _supercharger() -> Mesh:
	var body := _st()
	box(body, Vector3(0, 0.09, 0), Vector3(0.36, 0.14, 0.2))
	for sz in [-1.0, 1.0]:
		Lib._tube(body, Vector3(-0.18, 0.09, sz * 0.05), Vector3(0.18, 0.09, sz * 0.05), 0.07, 0.07, 18)
	var fins := _st()
	for k in range(9):
		box(fins, Vector3(-0.16 + k * 0.04, 0.17, 0), Vector3(0.012, 0.04, 0.22))
	var pulley := _st()
	Lib._tube(pulley, Vector3(-0.2, 0.09, 0), Vector3(-0.25, 0.09, 0), 0.06, 0.06, 20)
	var scoop := _st()
	taper(scoop, 0.19, Vector2(0.16, 0.12), 0.27, Vector2(0.12, 0.08))
	return _mesh([[body, m("metal", Color(0.9, 0.9, 0.93), 6.0, 0.22, 0.95)], [fins, m("metal", Color(0.8, 0.8, 0.84), 6.0, 0.3, 0.9)], [pulley, dark_steel()], [scoop, black_plastic()]])

func _nos_kit() -> Mesh:
	var bottle := _st()
	lathe(bottle, [Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.075, 0.02), Vector2(0.075, 0.48), Vector2(0.05, 0.53), Vector2(0.02, 0.55), Vector2(0.0, 0.55)], 20)
	var valve := _st()
	lathe(valve, [Vector2(0.018, 0.55), Vector2(0.018, 0.6), Vector2(0.03, 0.6), Vector2(0.03, 0.62), Vector2(0.0, 0.62)], 12)
	Lib._tube(valve, Vector3(0, 0.59, 0), Vector3(0.08, 0.59, 0), 0.008, 0.008, 8)
	var label := _st()
	Lib._tube(label, Vector3(0, 0.2, 0), Vector3(0, 0.32, 0), 0.077, 0.077, 20)
	var hose := _st()
	Lib._tube(hose, Vector3(0.08, 0.59, 0), Vector3(0.14, 0.4, 0.04), 0.008, 0.008, 8)
	Lib._tube(hose, Vector3(0.14, 0.4, 0.04), Vector3(0.12, 0.05, 0.06), 0.008, 0.008, 8)
	return _mesh([[bottle, paint(Color(0.12, 0.3, 0.75))], [valve, steel()], [label, c(Color(0.92, 0.92, 0.9), 0.4)], [hose, rubber()]])

func _radiator_fans() -> Mesh:
	var core := _st()
	box(core, Vector3(0, 0.17, 0), Vector3(0.56, 0.3, 0.05))
	var shroud := _st()
	for x in [-0.14, 0.14]:
		torus(shroud, Vector3(x, 0.17, -0.05), 0.12, 0.012, 24, 6, Vector3.FORWARD)
		box(shroud, Vector3(x, 0.17, -0.05), Vector3(0.04, 0.04, 0.03))
	box(shroud, Vector3(0, 0.17, -0.035), Vector3(0.58, 0.32, 0.01))
	var blades := _st()
	for x in [-0.14, 0.14]:
		for k in range(7):
			var a := TAU * k / 7.0
			box(blades, Vector3(x + cos(a) * 0.06, 0.17 + sin(a) * 0.06, -0.055), Vector3(0.1, 0.03, 0.004), Basis(Vector3.FORWARD, a) * Basis(Vector3.RIGHT, 0.4))
	var tanks := _st()
	for x in [-0.3, 0.3]:
		box(tanks, Vector3(x, 0.17, 0), Vector3(0.04, 0.34, 0.07))
	return _mesh([[core, m("metal", Color(0.75, 0.75, 0.78), 4.0, 0.4, 0.8)], [shroud, black_plastic()], [blades, c(Color(0.15, 0.15, 0.17), 0.5)], [tanks, dark_steel()]])

func _radiator_armored() -> Mesh:
	var core := _st()
	box(core, Vector3(0, 0.16, 0), Vector3(0.52, 0.28, 0.05))
	var cage := _st()
	box(cage, Vector3(0, 0.16, 0.05), Vector3(0.58, 0.32, 0.015))
	for k in range(6):
		box(cage, Vector3(0, 0.03 + k * 0.052, 0.065), Vector3(0.6, 0.02, 0.02))
	for x in [-0.3, 0.3]:
		box(cage, Vector3(x, 0.16, 0.02), Vector3(0.03, 0.34, 0.1))
	var bolts := _st()
	for x in [-0.28, 0.28]:
		for y in [0.02, 0.3]:
			lathe(bolts, [Vector2(0.012, 0.0), Vector2(0.012, 0.012)], 6, Vector3(x, y, 0.075))
	return _mesh([[core, dark_steel()], [cage, m("metal", Color(0.4, 0.42, 0.38), 4.0, 0.55, 0.7)], [bolts, steel()]])

func _coilover() -> Mesh:
	var spring := _st()
	var turns := 7
	var pts := 70
	for i in range(pts):
		var a0 := TAU * turns * i / float(pts)
		var a1 := TAU * turns * (i + 1) / float(pts)
		var p0 := Vector3(cos(a0) * 0.06, 0.06 + 0.32 * i / float(pts), sin(a0) * 0.06)
		var p1 := Vector3(cos(a1) * 0.06, 0.06 + 0.32 * (i + 1) / float(pts), sin(a1) * 0.06)
		Lib._tube(spring, p0, p1, 0.011, 0.011, 6)
	var damper := _st()
	lathe(damper, [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.26), Vector2(0.012, 0.27), Vector2(0.012, 0.44), Vector2(0.0, 0.44)], 14)
	var mounts := _st()
	for y in [0.05, 0.39]:
		lathe(mounts, [Vector2(0.0, y), Vector2(0.075, y), Vector2(0.075, y + 0.015), Vector2(0.0, y + 0.015)], 18)
	torus(mounts, Vector3(0, -0.01, 0), 0.025, 0.01, 12, 6, Vector3.FORWARD)
	return _mesh([[spring, paint(Color(0.85, 0.65, 0.1))], [damper, m("metal", Color(0.85, 0.85, 0.88), 6.0, 0.2, 0.95)], [mounts, dark_steel()]])

func _leaf_spring() -> Mesh:
	var leaves := _st()
	for k in range(5):
		var half := 0.45 - k * 0.07
		var y := 0.04 - k * 0.018
		var segs := 10
		for i in range(segs):
			var x0 := -half + 2.0 * half * i / segs
			var x1 := -half + 2.0 * half * (i + 1) / segs
			var y0 := y + 0.08 * (1.0 - pow(x0 / 0.45, 2.0))
			var y1 := y + 0.08 * (1.0 - pow(x1 / 0.45, 2.0))
			var mid := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0)
			var ang := atan2(y1 - y0, x1 - x0)
			box(leaves, mid, Vector3(x1 - x0 + 0.004, 0.014, 0.07), Basis(Vector3.BACK, ang))
	var eyes := _st()
	for x in [-0.46, 0.46]:
		torus(eyes, Vector3(x, 0.045, 0), 0.025, 0.01, 14, 6, Vector3.FORWARD)
	var clamp := _st()
	for x in [-0.06, 0.06]:
		box(clamp, Vector3(x, 0.08, 0), Vector3(0.02, 0.12, 0.09))
	return _mesh([[leaves, m("metal", Color(0.25, 0.26, 0.27), 6.0, 0.5, 0.7)], [eyes, steel()], [clamp, m("rust", Color.WHITE, 6.0, 0.8, 0.4)]])

func _lithium_battery() -> Mesh:
	var b := _st()
	box(b, Vector3(0, 0.09, 0), Vector3(0.26, 0.18, 0.17))
	var top := _st()
	box(top, Vector3(0, 0.185, 0), Vector3(0.255, 0.012, 0.165))
	var face := _st()
	box(face, Vector3(0, 0.1, 0.0855), Vector3(0.2, 0.1, 0.001))
	var leds := _st()
	for i in range(4):
		box(leds, Vector3(-0.05 + i * 0.033, 0.16, 0.086), Vector3(0.02, 0.01, 0.002))
	var term := _st()
	for x in [-0.09, 0.09]:
		lathe(term, [Vector2(0.014, 0.19), Vector2(0.012, 0.21)], 12, Vector3(x, 0, 0.03))
	return _mesh([[b, c(Color(0.92, 0.93, 0.94), 0.35)], [top, c(Color(0.12, 0.12, 0.14), 0.4)], [face, paint(Color(0.1, 0.55, 0.35))],
		[leds, Lib.color_mat(Color(0.3, 1.0, 0.5), 0.2, 0.0, Color(0.3, 1.0, 0.5), 2.0)], [term, brass()]])

func _tire_sand() -> Mesh:
	var t := _st()
	torus(t, Vector3(0, 0.12, 0), 0.24, 0.12, 32, 14, Vector3.UP)
	for i in range(16):
		var a := TAU * i / 16.0
		box(t, Vector3(cos(a) * 0.35, 0.12, sin(a) * 0.35), Vector3(0.05, 0.2, 0.03), Basis(Vector3.UP, -a))
	var rim := _st()
	lathe(rim, [Vector2(0.0, 0.08), Vector2(0.17, 0.07), Vector2(0.17, 0.17), Vector2(0.0, 0.16)], 24, Vector3.ZERO, false, false)
	for i in range(8):
		var a := TAU * i / 8.0
		box(rim, Vector3(cos(a) * 0.12, 0.172, sin(a) * 0.12), Vector3(0.05, 0.01, 0.02), Basis(Vector3.UP, -a))
	return _mesh([[t, m("rubber", Color(0.9, 0.82, 0.7), 5.0, 0.95)], [rim, paint(Color(0.85, 0.7, 0.3))]])

func _tire_solid() -> Mesh:
	var t := _st()
	lathe(t, [Vector2(0.17, 0.02), Vector2(0.32, 0.02), Vector2(0.35, 0.06), Vector2(0.35, 0.18), Vector2(0.32, 0.22), Vector2(0.17, 0.22)], 32, Vector3.ZERO, false, false)
	for i in range(20):
		var a := TAU * i / 20.0
		box(t, Vector3(cos(a) * 0.352, 0.12, sin(a) * 0.352), Vector3(0.012, 0.13, 0.04), Basis(Vector3.UP, -a))
	var rim := _st()
	lathe(rim, [Vector2(0.0, 0.08), Vector2(0.17, 0.06), Vector2(0.17, 0.18), Vector2(0.0, 0.16)], 24, Vector3.ZERO, false, false)
	for i in range(6):
		var a := TAU * i / 6.0
		_disc(rim, Vector3(cos(a) * 0.1, 0.171, sin(a) * 0.1), 0.025, Vector3.UP, 10)
	return _mesh([[t, m("rubber", Color(0.7, 0.7, 0.72), 5.0, 0.85)], [rim, paint(Color(0.9, 0.75, 0.1))]])

func _roof_rack() -> Mesh:
	var rails := _st()
	for sx in [-1.0, 1.0]:
		Lib._tube(rails, Vector3(sx * 0.55, 0.1, -0.7), Vector3(sx * 0.55, 0.1, 0.7), 0.02, 0.02, 10)
		for z in [-0.6, 0.0, 0.6]:
			box(rails, Vector3(sx * 0.55, 0.05, z), Vector3(0.05, 0.1, 0.06))
	var bars := _st()
	for k in range(5):
		box(bars, Vector3(0, 0.1, -0.6 + k * 0.3), Vector3(1.1, 0.025, 0.05))
	var basket := _st()
	for sx in [-1.0, 1.0]:
		Lib._tube(basket, Vector3(sx * 0.55, 0.22, -0.7), Vector3(sx * 0.55, 0.22, 0.7), 0.012, 0.012, 8)
		for k in range(6):
			var z := -0.7 + k * 0.28
			Lib._tube(basket, Vector3(sx * 0.55, 0.1, z), Vector3(sx * 0.55, 0.22, z), 0.01, 0.01, 6)
	return _mesh([[rails, m("metal", Color(0.12, 0.12, 0.13), 6.0, 0.5, 0.6)], [bars, m("metal", Color(0.18, 0.18, 0.2), 6.0, 0.45, 0.6)], [basket, m("metal", Color(0.12, 0.12, 0.13), 6.0, 0.5, 0.6)]])

func _cargo_box() -> Mesh:
	var shell := _st()
	taper(shell, 0.0, Vector2(0.9, 0.7), 0.06, Vector2(0.94, 0.74))
	taper(shell, 0.06, Vector2(0.94, 0.74), 0.24, Vector2(0.86, 0.66))
	taper(shell, 0.24, Vector2(0.86, 0.66), 0.32, Vector2(0.7, 0.5))
	var seam := _st()
	box(seam, Vector3(0, 0.13, 0), Vector3(0.95, 0.012, 0.75))
	var lock := _st()
	box(lock, Vector3(0.0, 0.13, 0.378), Vector3(0.08, 0.04, 0.012))
	return _mesh([[shell, c(Color(0.12, 0.12, 0.14), 0.3)], [seam, c(Color(0.25, 0.25, 0.27), 0.5)], [lock, steel()]])

func _roof_tent() -> Mesh:
	var base := _st()
	box(base, Vector3(0, 0.04, 0), Vector3(1.2, 0.08, 0.7))
	var cover := _st()
	taper(cover, 0.08, Vector2(1.22, 0.72), 0.3, Vector2(1.18, 0.68))
	var straps := _st()
	for x in [-0.4, 0.4]:
		box(straps, Vector3(x, 0.19, 0), Vector3(0.05, 0.23, 0.73))
	var ladder := _st()
	for x in [-0.15, 0.15]:
		Lib._tube(ladder, Vector3(x, 0.32, 0.2), Vector3(x, 0.32, -0.2), 0.012, 0.012, 8)
	return _mesh([[base, m("metal", Color(0.2, 0.2, 0.22), 6.0, 0.5, 0.6)], [cover, m("canvas", Color(0.55, 0.62, 0.38), 4.0, 0.9)], [straps, c(Color(0.1, 0.1, 0.1), 0.8)], [ladder, steel()]])

func _panniers() -> Mesh:
	var boxes := _st()
	for sx in [-1.0, 1.0]:
		box(boxes, Vector3(sx * 0.22, 0.2, 0), Vector3(0.18, 0.4, 0.6))
	var lids := _st()
	for sx in [-1.0, 1.0]:
		box(lids, Vector3(sx * 0.22, 0.41, 0), Vector3(0.2, 0.025, 0.62))
		box(lids, Vector3(sx * 0.315, 0.25, 0), Vector3(0.01, 0.05, 0.12))
	var strap := _st()
	box(strap, Vector3(0, 0.38, 0), Vector3(0.28, 0.02, 0.06))
	return _mesh([[boxes, m("metal", Color(0.55, 0.56, 0.5), 5.0, 0.55, 0.6)], [lids, m("metal", Color(0.3, 0.31, 0.28), 5.0, 0.5, 0.6)], [strap, c(Color(0.08, 0.08, 0.08), 0.8)]])

func _jerry_holder() -> Mesh:
	var frame := _st()
	box(frame, Vector3(0, 0.02, 0), Vector3(0.36, 0.03, 0.2))
	for sx in [-1.0, 1.0]:
		box(frame, Vector3(sx * 0.18, 0.25, -0.09), Vector3(0.025, 0.5, 0.025))
	box(frame, Vector3(0, 0.5, -0.09), Vector3(0.38, 0.025, 0.025))
	box(frame, Vector3(0, 0.3, 0.1), Vector3(0.38, 0.025, 0.01))
	var cans := _st()
	for sx in [-1.0, 1.0]:
		box(cans, Vector3(sx * 0.085, 0.24, 0), Vector3(0.15, 0.42, 0.16))
		box(cans, Vector3(sx * 0.085, 0.48, -0.03), Vector3(0.03, 0.05, 0.03))
	return _mesh([[frame, m("metal", Color(0.12, 0.12, 0.13), 6.0, 0.5, 0.6)], [cans, paint(Color(0.6, 0.12, 0.08))]])

func _spare_mount() -> Mesh:
	var frame := _st()
	box(frame, Vector3(0, 0.02, 0), Vector3(0.6, 0.03, 0.08))
	box(frame, Vector3(0, 0.02, 0), Vector3(0.08, 0.03, 0.6))
	Lib._tube(frame, Vector3(0, 0.0, 0), Vector3(0, 0.14, 0), 0.025, 0.025, 10)
	var nut := _st()
	lathe(nut, [Vector2(0.0, 0.14), Vector2(0.05, 0.14), Vector2(0.05, 0.17), Vector2(0.0, 0.17)], 6)
	return _mesh([[frame, m("metal", Color(0.12, 0.12, 0.13), 6.0, 0.5, 0.6)], [nut, steel()]])

func _snorkel() -> Mesh:
	var pipe := _st()
	Lib._tube(pipe, Vector3(0, 0.0, 0), Vector3(0, 0.12, 0.08), 0.045, 0.045, 14)
	Lib._tube(pipe, Vector3(0, 0.12, 0.08), Vector3(0, 0.95, 0.12), 0.045, 0.045, 14)
	Lib._tube(pipe, Vector3(0, 0.95, 0.12), Vector3(0, 1.02, 0.2), 0.045, 0.05, 14)
	var head := _st()
	ellipsoid(head, Vector3(0, 1.04, 0.24), Vector3(0.07, 0.06, 0.09), 8, 14)
	var grille := _st()
	for k in range(4):
		box(grille, Vector3(0, 1.01 + k * 0.018, 0.32), Vector3(0.1, 0.008, 0.01))
	var brackets := _st()
	for y in [0.35, 0.75]:
		box(brackets, Vector3(-0.05, y, 0.11), Vector3(0.06, 0.03, 0.03))
	return _mesh([[pipe, c(Color(0.06, 0.06, 0.07), 0.6)], [head, c(Color(0.08, 0.08, 0.09), 0.55)], [grille, dark_steel()], [brackets, steel()]])

func _winch() -> Mesh:
	var drum := _st()
	Lib._tube(drum, Vector3(-0.16, 0.1, 0), Vector3(0.16, 0.1, 0), 0.065, 0.065, 18)
	var cable := _st()
	for k in range(14):
		var x := -0.14 + k * 0.021
		torus(cable, Vector3(x, 0.1, 0), 0.07, 0.008, 14, 4, Vector3.RIGHT)
	var motor := _st()
	Lib._tube(motor, Vector3(-0.17, 0.1, 0), Vector3(-0.32, 0.1, 0), 0.07, 0.07, 18)
	_disc(motor, Vector3(-0.32, 0.1, 0), 0.07, Vector3.LEFT, 18)
	box(motor, Vector3(0.22, 0.1, 0), Vector3(0.12, 0.15, 0.15))
	var hook := _st()
	torus(hook, Vector3(0, 0.1, 0.16), 0.03, 0.009, 12, 6, Vector3.UP)
	Lib._tube(hook, Vector3(0, 0.1, 0.07), Vector3(0, 0.1, 0.13), 0.01, 0.01, 6)
	return _mesh([[drum, dark_steel()], [cable, steel()], [motor, paint(Color(0.75, 0.15, 0.1))], [hook, m("metal", Color(0.85, 0.75, 0.2), 6.0, 0.4, 0.8)]])

func _ram_plow() -> Mesh:
	var plate := _st()
	for k in range(6):
		var y := 0.06 + k * 0.08
		var z := 0.12 - 0.012 * k * k * 0.5
		box(plate, Vector3(0, y, z), Vector3(1.2, 0.085, 0.03), Basis(Vector3.RIGHT, -0.25 + k * 0.1))
	var ribs := _st()
	for x in [-0.45, -0.15, 0.15, 0.45]:
		box(ribs, Vector3(x, 0.25, 0.0), Vector3(0.04, 0.48, 0.2))
	var arms := _st()
	for x in [-0.35, 0.35]:
		box(arms, Vector3(x, 0.25, -0.2), Vector3(0.06, 0.06, 0.4))
	return _mesh([[plate, m("rust", Color(0.8, 0.8, 0.82), 4.0, 0.6, 0.6)], [ribs, dark_steel()], [arms, m("metal", Color(0.12, 0.12, 0.13), 6.0, 0.5, 0.6)]])

func _windshield_mesh() -> Mesh:
	# fine expanded-metal guard: thin wires so you can still see out
	var grid := _st()
	for k in range(17):
		var x := -0.6 + k * 0.075
		box(grid, Vector3(x, 0.35, 0), Vector3(0.0022, 0.7, 0.003))
	for k in range(11):
		var y := 0.0 + k * 0.07
		box(grid, Vector3(0, y, 0), Vector3(1.2, 0.002, 0.003))
	var frame := _st()
	for x in [-0.61, 0.61]:
		box(frame, Vector3(x, 0.35, 0), Vector3(0.02, 0.72, 0.02))
	for y in [-0.01, 0.71]:
		box(frame, Vector3(0, y, 0), Vector3(1.24, 0.02, 0.02))
	return _mesh([[grid, m("metal", Color(0.22, 0.23, 0.24), 6.0, 0.5, 0.7)], [frame, m("metal", Color(0.12, 0.12, 0.13), 6.0, 0.5, 0.6)]])

func _door_armor() -> Mesh:
	var plates := _st()
	box(plates, Vector3(0, 0.25, 0), Vector3(0.7, 0.5, 0.02))
	box(plates, Vector3(0, 0.25, 0.04), Vector3(0.7, 0.5, 0.02))
	var rivets := _st()
	for x in [-0.32, -0.16, 0.0, 0.16, 0.32]:
		for y in [0.03, 0.47]:
			lathe(rivets, [Vector2(0.01, 0.0), Vector2(0.006, 0.008)], 6, Vector3(x, y, 0.05))
	var slits := _st()
	box(slits, Vector3(0, 0.38, 0.051), Vector3(0.3, 0.02, 0.002))
	return _mesh([[plates, m("rust", Color(0.7, 0.7, 0.66), 4.0, 0.65, 0.6)], [rivets, steel()], [slits, c(Color(0.05, 0.05, 0.05), 0.9)]])

func _mud_flaps() -> Mesh:
	var flaps := _st()
	for sx in [-1.0, 1.0]:
		box(flaps, Vector3(sx * 0.16, 0.18, 0), Vector3(0.28, 0.36, 0.012))
	var plates := _st()
	for sx in [-1.0, 1.0]:
		box(plates, Vector3(sx * 0.16, 0.35, 0.01), Vector3(0.26, 0.03, 0.01))
		box(plates, Vector3(sx * 0.16, 0.1, 0.008), Vector3(0.18, 0.06, 0.002))
	return _mesh([[flaps, rubber()], [plates, steel()]])

func _underglow_kit() -> Mesh:
	var tubes := _st()
	for z in [-0.06, 0.06]:
		Lib._tube(tubes, Vector3(-0.35, 0.025, z), Vector3(0.35, 0.025, z), 0.018, 0.018, 12)
	var caps := _st()
	for x in [-0.36, 0.36]:
		for z in [-0.06, 0.06]:
			lathe(caps, [Vector2(0.0, 0.0), Vector2(0.02, 0.0), Vector2(0.02, 0.04), Vector2(0.0, 0.04)], 10, Vector3(x, 0.005, z))
	var box_ := _st()
	box(box_, Vector3(0, 0.03, 0), Vector3(0.1, 0.05, 0.08))
	return _mesh([[tubes, Lib.color_mat(Color(0.85, 0.3, 1.0), 0.2, 0.0, Color(0.85, 0.3, 1.0), 1.5)], [caps, black_plastic()], [box_, black_plastic()]])

func _tow_hitch() -> Mesh:
	var tube := _st()
	box(tube, Vector3(0, 0.05, 0), Vector3(0.07, 0.07, 0.45))
	box(tube, Vector3(0, 0.05, -0.2), Vector3(0.7, 0.06, 0.06))
	var ball := _st()
	ellipsoid(ball, Vector3(0, 0.17, 0.2), Vector3(0.025, 0.025, 0.025), 8, 12)
	Lib._tube(ball, Vector3(0, 0.09, 0.2), Vector3(0, 0.15, 0.2), 0.012, 0.012, 8)
	box(ball, Vector3(0, 0.09, 0.2), Vector3(0.08, 0.02, 0.1))
	var pin := _st()
	Lib._tube(pin, Vector3(-0.05, 0.05, 0.05), Vector3(0.05, 0.05, 0.05), 0.008, 0.008, 6)
	return _mesh([[tube, m("metal", Color(0.12, 0.12, 0.13), 6.0, 0.5, 0.6)], [ball, steel()], [pin, m("metal", Color(0.85, 0.75, 0.2), 6.0, 0.4, 0.8)]])

# ---- cab decor. Hanging pieces have a cord on top so they hang from the ceiling or the mirror.
func _cord(st: SurfaceTool, from_y: float, length: float) -> void:
	Lib._tube(st, Vector3(0, from_y, 0), Vector3(0, from_y + length, 0), 0.0015, 0.0015, 4)
	torus(st, Vector3(0, from_y + length + 0.006, 0), 0.006, 0.0015, 8, 3, Vector3.FORWARD)

func _dice() -> Mesh:
	var fuzz := _st()
	var pips := _st()
	for s in [-1.0, 1.0]:
		var ctr := Vector3(s * 0.035, 0.035 + (0.012 if s > 0 else 0.0), 0)
		ellipsoid(fuzz, ctr, Vector3(0.032, 0.032, 0.032), 8, 12, 0.12, int(s * 3) + 5)
		box(fuzz, ctr, Vector3(0.056, 0.056, 0.056), Basis(Vector3.UP, s * 0.3))
		for p in [Vector3(0, 0, 0.0285), Vector3(0.012, 0.012, 0.0285), Vector3(-0.012, -0.012, 0.0285)]:
			ellipsoid(pips, ctr + Basis(Vector3.UP, s * 0.3) * p, Vector3(0.006, 0.006, 0.003), 3, 6)
	var cord := _st()
	Lib._tube(cord, Vector3(-0.035, 0.065, 0), Vector3(0.0, 0.13, 0), 0.0018, 0.0018, 4)
	Lib._tube(cord, Vector3(0.035, 0.077, 0), Vector3(0.0, 0.13, 0), 0.0018, 0.0018, 4)
	_cord(cord, 0.13, 0.06)
	return _mesh([[fuzz, m("fur", Color(1.6, 0.35, 0.35), 8.0, 1.0)], [pips, c(Color(0.95, 0.95, 0.95), 0.6)], [cord, c(Color(0.9, 0.9, 0.85))]])

func _freshener() -> Mesh:
	var card := _st()
	box(card, Vector3(0, 0.06, 0), Vector3(0.03, 0.09, 0.002))
	for s in [-1.0, 1.0]:
		box(card, Vector3(s * 0.025, 0.075, 0), Vector3(0.02, 0.012, 0.002))
		box(card, Vector3(s * 0.033, 0.088, 0), Vector3(0.008, 0.025, 0.002))
	ellipsoid(card, Vector3(0, 0.105, 0), Vector3(0.015, 0.006, 0.0012), 3, 8)
	var pot := _st()
	taper(pot, 0.0, Vector2(0.026, 0.002), 0.018, Vector2(0.036, 0.002))
	var flower := _st()
	ellipsoid(flower, Vector3(0, 0.112, 0.0015), Vector3(0.008, 0.008, 0.001), 3, 8)
	var cord := _st()
	_cord(cord, 0.11, 0.07)
	return _mesh([[card, c(Color(0.25, 0.6, 0.25), 0.8)], [pot, c(Color(0.8, 0.45, 0.25), 0.8)], [flower, c(Color(0.95, 0.4, 0.6))], [cord, c(Color(0.9, 0.85, 0.7))]])

func _suncatcher() -> Mesh:
	var crystals := _st()
	var y := 0.02
	for k in range(3):
		var r := 0.012 - k * 0.002
		hexa(crystals, [Vector3(-r, y, -r), Vector3(r, y, -r), Vector3(r, y, r), Vector3(-r, y, r),
			Vector3(-r * 0.2, y + r * 2.2, -r * 0.2), Vector3(r * 0.2, y + r * 2.2, -r * 0.2), Vector3(r * 0.2, y + r * 2.2, r * 0.2), Vector3(-r * 0.2, y + r * 2.2, r * 0.2)])
		hexa(crystals, [Vector3(-r * 0.2, y - r * 1.6, -r * 0.2), Vector3(r * 0.2, y - r * 1.6, -r * 0.2), Vector3(r * 0.2, y - r * 1.6, r * 0.2), Vector3(-r * 0.2, y - r * 1.6, r * 0.2),
			Vector3(-r, y, -r), Vector3(r, y, -r), Vector3(r, y, r), Vector3(-r, y, r)])
		y += r * 2.2 + 0.012
	var ring := _st()
	torus(ring, Vector3(0, y + 0.02, 0), 0.022, 0.0025, 18, 4, Vector3.FORWARD)
	var cord := _st()
	Lib._tube(cord, Vector3(0, 0.02, 0), Vector3(0, y + 0.0, 0), 0.0008, 0.0008, 4)
	_cord(cord, y + 0.042, 0.05)
	var cm := Lib.color_mat(Color(0.85, 0.92, 1.0, 0.45), 0.02, 0.4, Color(0.7, 0.8, 1.0), 0.3)
	return _mesh([[crystals, cm], [ring, brass()], [cord, c(Color(0.9, 0.9, 0.9))]])

func _bells() -> Mesh:
	var bells := _st()
	for k in range(3):
		var y := 0.0 + k * 0.035
		lathe(bells, [Vector2(0.018, y), Vector2(0.016, y + 0.004), Vector2(0.011, y + 0.018), Vector2(0.006, y + 0.026), Vector2(0.0, y + 0.027)], 14, Vector3.ZERO, false, false)
	var clap := _st()
	for k in range(3):
		metal_sphere(clap, Vector3(0, k * 0.035 + 0.004, 0), 0.004)
	var cord := _st()
	Lib._tube(cord, Vector3(0, 0.004, 0), Vector3(0, 0.1, 0), 0.0025, 0.0025, 5)
	for k in range(4):
		ellipsoid(cord, Vector3(0, 0.11 + k * 0.012, 0), Vector3.ONE * 0.005, 3, 6)
	_cord(cord, 0.15, 0.04)
	var bm := brass()
	bm = bm.duplicate()
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh([[bells, bm], [clap, dark_steel()], [cord, c(Color(0.6, 0.15, 0.1), 0.8)]])

func _dreamcatcher() -> Mesh:
	var hoop := _st()
	torus(hoop, Vector3(0, 0.1, 0), 0.045, 0.004, 24, 5, Vector3.FORWARD)
	var web := _st()
	for k in range(8):
		var a := TAU * k / 8.0
		var b := TAU * (k + 3) / 8.0
		var p0 := Vector3(cos(a) * 0.045, 0.1 + sin(a) * 0.045, 0)
		var p1 := Vector3(cos(b) * 0.045, 0.1 + sin(b) * 0.045, 0)
		Lib._tube(web, p0, p1, 0.0006, 0.0006, 3)
	var feathers := _st()
	for x in [-0.03, 0.0, 0.03]:
		Lib._tube(web, Vector3(x * 1.2, 0.06 + absf(x) * 0.3, 0), Vector3(x, 0.035, 0), 0.0008, 0.0008, 3)
		hexa(feathers, [Vector3(x - 0.0005, 0.035, 0), Vector3(x + 0.0005, 0.035, 0), Vector3(x + 0.0005, 0.035, 0), Vector3(x - 0.0005, 0.035, 0),
			Vector3(x - 0.008, -0.01, -0.0005), Vector3(x + 0.008, -0.01, -0.0005), Vector3(x + 0.004, -0.03, 0.0005), Vector3(x - 0.004, -0.03, 0.0005)])
	var beads := _st()
	for x in [-0.036, 0.0, 0.036]:
		ellipsoid(beads, Vector3(x, 0.045, 0), Vector3.ONE * 0.004, 3, 6)
	var cord := _st()
	_cord(cord, 0.145, 0.05)
	var mi := _mesh([[hoop, leather()], [web, c(Color(0.9, 0.85, 0.75))], [feathers, m("fur", Color(1.0, 0.95, 0.85), 20.0, 0.9)], [beads, c(Color(0.2, 0.55, 0.75), 0.3)], [cord, c(Color(0.55, 0.38, 0.22))]])
	return _rotated(mi, Basis.IDENTITY, Vector3(0, 0.03, 0))

func _mirror_ball() -> Mesh:
	var s := _st()
	ellipsoid(s, Vector3(0, 0.035, 0), Vector3.ONE * 0.032, 10, 16)
	var tiles := _st()
	for r in range(1, 9):
		var phi := PI * r / 9.0
		var n := int(4 + sin(phi) * 12)
		for k in range(n):
			var th := TAU * k / n + r * 0.2
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var b := Lib._basis_for(d)
			box(tiles, Vector3(0, 0.035, 0) + d * 0.0325, Vector3(0.008, 0.001, 0.008), b)
	var cap := _st()
	lathe(cap, [Vector2(0.006, 0.065), Vector2(0.006, 0.072)], 8)
	_cord(cap, 0.072, 0.06)
	return _mesh([[s, c(Color(0.2, 0.2, 0.22), 0.5)], [tiles, m("metal", Color(1.0, 1.0, 1.0), 4.0, 0.02, 1.0)], [cap, steel()]])

func _spinner() -> Mesh:
	var s := _st()
	var prev := Vector3(0.03, 0.0, 0)
	for k in range(1, 49):
		var a := TAU * k / 12.0
		var r := 0.03 * (1.0 - k / 60.0)
		var p := Vector3(cos(a) * r, k * 0.0022, sin(a) * r)
		box(s, (prev + p) * 0.5, Vector3(prev.distance_to(p), 0.012, 0.001), Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, 0.5))
		prev = p
	var cord := _st()
	Lib._tube(cord, Vector3(0, 0.0, 0), Vector3(0, 0.106, 0), 0.0012, 0.0012, 4)
	_cord(cord, 0.106, 0.04)
	return _mesh([[s, m("metal", Color(0.3, 0.65, 0.95), 4.0, 0.2, 0.9)], [cord, steel()]])

func _palm() -> Mesh:
	var base := _st()
	lathe(base, [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.026, 0.02), Vector2(0.0, 0.022)], 16)
	var spring := _st()
	var prev := Vector3(0.006, 0.022, 0)
	for k in range(1, 25):
		var a := TAU * k / 6.0
		var p := Vector3(cos(a) * 0.006, 0.022 + k * 0.0018, sin(a) * 0.006)
		Lib._tube(spring, prev, p, 0.0012, 0.0012, 4)
		prev = p
	var trunk := _st()
	Lib._tube(trunk, Vector3(0, 0.065, 0), Vector3(0.004, 0.11, 0), 0.006, 0.004, 8)
	var leaves := _st()
	for k in range(6):
		var a := TAU * k / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		hexa(leaves, [Vector3(0, 0.112, 0) - d.cross(Vector3.UP) * 0.004, Vector3(0, 0.112, 0) + d.cross(Vector3.UP) * 0.004, Vector3(0, 0.114, 0) + d.cross(Vector3.UP) * 0.004, Vector3(0, 0.114, 0) - d.cross(Vector3.UP) * 0.004,
			d * 0.045 + Vector3(0, 0.095, 0) - d.cross(Vector3.UP) * 0.006, d * 0.045 + Vector3(0, 0.095, 0) + d.cross(Vector3.UP) * 0.006, d * 0.045 + Vector3(0, 0.097, 0) + d.cross(Vector3.UP) * 0.006, d * 0.045 + Vector3(0, 0.097, 0) - d.cross(Vector3.UP) * 0.006])
	var nuts := _st()
	for k in range(3):
		ellipsoid(nuts, Vector3(cos(k * 2.1) * 0.006, 0.106, sin(k * 2.1) * 0.006), Vector3.ONE * 0.004, 3, 6)
	return _mesh([[base, c(Color(0.95, 0.85, 0.5), 0.6)], [spring, steel()], [trunk, c(Color(0.55, 0.38, 0.2), 0.7)], [leaves, c(Color(0.2, 0.7, 0.25), 0.5)], [nuts, c(Color(0.4, 0.25, 0.1))]])

func _globe() -> Mesh:
	var base := _st()
	lathe(base, [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.008), Vector2(0.008, 0.014), Vector2(0.006, 0.03)], 16)
	var arc := _st()
	var prev := Vector3(0, 0.02, 0.0)
	for k in range(1, 13):
		var a := PI * k / 12.0
		var p := Vector3(0, 0.06 - cos(a) * 0.042, sin(a) * 0.042)
		Lib._tube(arc, prev, p, 0.0015, 0.0015, 4)
		prev = p
	var ball := _st()
	ellipsoid(ball, Vector3(0, 0.06, 0), Vector3.ONE * 0.036, 12, 18)
	var land := _st()
	for k in range(7):
		var d := Vector3(cos(k * 2.3) * 0.8, sin(k * 1.7) * 0.6, sin(k * 2.3) * 0.8).normalized()
		ellipsoid(land, Vector3(0, 0.06, 0) + d * 0.0355, Vector3(0.012, 0.009, 0.012) * (0.7 + (k % 3) * 0.3), 4, 8, 0.3, k)
	var mi := _mesh([[base, brass()], [arc, brass()], [ball, paint(Color(0.18, 0.4, 0.75))], [land, c(Color(0.45, 0.65, 0.3), 0.6)]])
	return mi

func _hourglass() -> Mesh:
	var frame := _st()
	for y in [0.0, 0.12]:
		lathe(frame, [Vector2(0.0, y), Vector2(0.035, y), Vector2(0.035, y + 0.01), Vector2(0.0, y + 0.01)], 18)
	for k in range(3):
		var a := TAU * k / 3.0
		Lib._tube(frame, Vector3(cos(a) * 0.03, 0.01, sin(a) * 0.03), Vector3(cos(a) * 0.03, 0.12, sin(a) * 0.03), 0.003, 0.003, 6)
	var glass := _st()
	lathe(glass, [Vector2(0.0, 0.01), Vector2(0.022, 0.012), Vector2(0.024, 0.03), Vector2(0.004, 0.065), Vector2(0.024, 0.1), Vector2(0.022, 0.118), Vector2(0.0, 0.12)], 16)
	var sand := _st()
	lathe(sand, [Vector2(0.0, 0.012), Vector2(0.02, 0.013), Vector2(0.012, 0.03), Vector2(0.0, 0.034)], 14)
	lathe(sand, [Vector2(0.0, 0.07), Vector2(0.01, 0.08), Vector2(0.02, 0.095), Vector2(0.0, 0.097)], 14)
	var gm := Lib.color_mat(Color(0.9, 0.95, 1.0, 0.25), 0.02).duplicate()
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh([[frame, dark_wood()], [glass, gm], [sand, c(Color(0.92, 0.8, 0.5), 0.9)]])
