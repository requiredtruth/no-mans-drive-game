extends RefCounted
## Builders for roadside locations. Local +Z faces the road.

const Loot = preload("res://scripts/loot.gd")
const Structure = preload("res://scripts/structure.gd")

static func build(parent: Node3D, poi: Dictionary) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = poi["pos"]
	root.rotation.y = poi["yaw"]
	var key := "poi%d" % int(poi["row"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	match str(poi["type"]):
		"gas_station": _gas_station(root, key, rng)
		"house": _house(root, key, rng)
		"wrecks": _wrecks(root, key, rng)
		"camp_ruin": _camp(root, key, rng)
		"farm": _farm(root, key, rng)
	return root

static func loot(parent: Node3D, pos: Vector3, size: Vector3, m: Material, key: String, label: String, table: String, mode := "loot", rot := 0.0) -> Node3D:
	var body := StaticBody3D.new()
	body.set_script(Loot)
	body.setup(key, label, table, mode)
	body.position = pos
	body.rotation.y = rot
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	Lib.box(body, Vector3(0, size.y * 0.5, 0), size, m)
	return body

## Wall segment along local X centered at pos, with optional opening.
static func wall(parent: Node3D, pos: Vector3, length: float, height: float, m: Material, along_z := false, hole_w := 0.0, hole_h := 0.0, hole_y := 0.0, t := 0.2) -> void:
	var holder := Node3D.new()
	holder.position = pos
	if along_z:
		holder.rotation.y = PI * 0.5
	parent.add_child(holder)
	if hole_w <= 0.0:
		Lib.box(holder, Vector3(0, height * 0.5, 0), Vector3(length, height, t), m, true)
		return
	var side := (length - hole_w) * 0.5
	Lib.box(holder, Vector3(-(hole_w + side) * 0.5, height * 0.5, 0), Vector3(side, height, t), m, true)
	Lib.box(holder, Vector3((hole_w + side) * 0.5, height * 0.5, 0), Vector3(side, height, t), m, true)
	var top := height - hole_y - hole_h
	if top > 0.01:
		Lib.box(holder, Vector3(0, hole_y + hole_h + top * 0.5, 0), Vector3(hole_w, top, t), m, true)
	if hole_y > 0.01:
		Lib.box(holder, Vector3(0, hole_y * 0.5, 0), Vector3(hole_w, hole_y, t), m, true)
		var g := Lib.box(holder, Vector3(0, hole_y + hole_h * 0.5, 0), Vector3(hole_w, hole_h, 0.03), Lib.glass_mat())
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func signpost(parent: Node3D, pos: Vector3, text: String, col: Color) -> void:
	Lib.box(parent, pos + Vector3(0, -2.2, 0), Vector3(0.18, 4.4, 0.18), Lib.mat("rust"), true)
	Lib.box(parent, pos + Vector3(0, 0.4, 0), Vector3(2.6, 1.1, 0.15), Lib.color_mat(col, 0.6))
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.006
	l.position = pos + Vector3(0, 0.4, 0.09)
	l.modulate = Color("f4ecd8")
	l.outline_size = 0
	parent.add_child(l)
	var back := l.duplicate()
	back.position.z = pos.z - 0.09
	back.rotation.y = PI
	parent.add_child(back)

static func _gas_station(root: Node3D, key: String, rng: RandomNumberGenerator) -> void:
	var concrete := Lib.mat("concrete", Color.WHITE, 0.25)
	var rust := Lib.mat("rust")
	var paint := Lib.mat("rv_paint", Color(0.85, 0.9, 0.95), 0.3)
	Lib.box(root, Vector3(0, 0.05, 2), Vector3(22, 0.2, 18), concrete, true)
	# canopy
	for x in [-4.5, 4.5]:
		for z in [5.0, 9.0]:
			Lib.box(root, Vector3(x, 2.3, z), Vector3(0.35, 4.5, 0.35), paint, true)
	Lib.box(root, Vector3(0, 4.7, 7), Vector3(12, 0.5, 7), paint, true)
	Lib.box(root, Vector3(0, 4.45, 7), Vector3(12.1, 0.12, 7.1), Lib.color_mat(Color("b23a2a"), 0.5))
	Lib.light(root, Vector3(0, 4.2, 7), Color(0.9, 0.95, 1.0), 0.0, 1.0)
	for x in [-2.0, 2.0]:
		Lib.box(root, Vector3(x, 0.25, 7), Vector3(1.6, 0.3, 0.9), concrete, true)
		var pump := loot(root, Vector3(x, 0.4, 7), Vector3(0.8, 1.7, 0.55), Lib.mat("rv_paint", Color(0.85, 0.3, 0.25), 0.4), "%s_pump%d" % [key, int(x)], "Fuel pump", "", "pump")
		Lib.box(pump, Vector3(0, 1.3, 0.29), Vector3(0.5, 0.3, 0.02), Lib.color_mat(Color(0.1, 0.12, 0.1), 0.2))
		Lib.cyl(pump, Vector3(0.45, 0.9, 0), 0.03, 0.03, 0.9, Lib.color_mat(Color(0.05, 0.05, 0.05)))
	# shop
	var walls := Lib.mat("concrete", Color(0.9, 0.85, 0.75), 0.3)
	var w := 10.0
	var d := 7.0
	var h := 3.4
	var cz := -4.0
	wall(root, Vector3(0, 0.15, cz + d * 0.5), w, h, walls, false, 1.4, 2.3, 0.0)
	wall(root, Vector3(0, 0.15, cz - d * 0.5), w, h, walls)
	wall(root, Vector3(-w * 0.5, 0.15, cz), d, h, walls, true, 2.0, 1.2, 1.0)
	wall(root, Vector3(w * 0.5, 0.15, cz), d, h, walls, true)
	Lib.box(root, Vector3(0, h + 0.25, cz), Vector3(w + 0.6, 0.3, d + 0.6), rust, true)
	# front windows
	for x in [-3.2, 3.2]:
		var g := Lib.box(root, Vector3(x, 1.7, cz + d * 0.5 + 0.12), Vector3(2.2, 1.4, 0.04), Lib.glass_mat())
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# interior
	Lib.box(root, Vector3(0, 0.2, cz), Vector3(w - 0.3, 0.1, d - 0.3), Lib.mat("planks", Color(0.6, 0.6, 0.6)), true)
	loot(root, Vector3(-2.5, 0.25, cz - 0.5), Vector3(2.4, 1.6, 0.6), Lib.mat("rust", Color(0.8, 0.8, 0.9)), key + "_s1", "Store shelf", "shelf")
	loot(root, Vector3(1.8, 0.25, cz - 0.5), Vector3(2.4, 1.6, 0.6), Lib.mat("rust", Color(0.8, 0.8, 0.9)), key + "_s2", "Store shelf", "shelf")
	loot(root, Vector3(3.5, 0.25, cz + 2.2), Vector3(1.8, 1.0, 0.7), Lib.mat("planks"), key + "_counter", "Counter", "shelf")
	loot(root, Vector3(-3.8, 0.25, cz - 2.8), Vector3(1.4, 1.0, 0.7), Lib.mat("rust"), key + "_back", "Back room toolbox", "backroom")
	signpost(root, Vector3(9.5, 5.5, 8.5), "FUEL  •  FOOD", Color("2f4f6f"))
	# debris
	for i in range(4):
		var p := Vector3(rng.randf_range(-9, 9), 0.25, rng.randf_range(-1, 10))
		Lib.box(root, p, Vector3(0.6, 0.12, 0.4), rust, false, Vector3(0, rng.randf() * TAU, 0))

static func _house(root: Node3D, key: String, rng: RandomNumberGenerator) -> void:
	var siding := Lib.mat("planks", Color(rng.randf_range(0.7, 1.0), rng.randf_range(0.75, 0.95), rng.randf_range(0.7, 0.9)), 0.33)
	var dark := Lib.mat("planks", Color(0.55, 0.5, 0.45), 0.33)
	var stone := Lib.mat("concrete", Color(0.8, 0.8, 0.8), 0.3)
	var w := 10.0
	var d := 8.0
	var h := 3.0
	Lib.box(root, Vector3(0, 0.25, 0), Vector3(w + 0.4, 0.6, d + 0.4), stone, true)
	Lib.box(root, Vector3(0, 0.56, 0), Vector3(w - 0.2, 0.04, d - 0.2), dark)
	var y := 0.55
	wall(root, Vector3(-2.5, y, d * 0.5), 5.0, h, siding, false, 1.1, 2.2, 0.0)
	wall(root, Vector3(2.5, y, d * 0.5), 5.0, h, siding, false, 1.6, 1.1, 1.0)
	wall(root, Vector3(0, y, -d * 0.5), w, h, siding, false, 1.6, 1.1, 1.0)
	wall(root, Vector3(-w * 0.5, y, 0), d, h, siding, true, 1.4, 1.1, 1.0)
	wall(root, Vector3(w * 0.5, y, 0), d, h, siding, true)
	wall(root, Vector3(0.5, y, 0), d, h, siding, true, 1.1, 2.2, 0.0)
	# pitched roof
	var ang := 0.55
	var rl := (d * 0.5 + 0.6) / cos(ang)
	for s in [-1.0, 1.0]:
		Lib.box(root, Vector3(0, y + h + tan(ang) * (d * 0.25 + 0.3) - 0.1, s * (d * 0.25 + 0.3)), Vector3(w + 0.8, 0.18, rl), Lib.mat("rust", Color(0.6, 0.55, 0.5), 0.5), true, Vector3(-s * ang, 0, 0))
	for s in [-1.0, 1.0]:
		for k in range(4):
			var gh := (tan(ang) * d * 0.5) * (1.0 - k / 4.0)
			Lib.box(root, Vector3(s * w * 0.5, y + h + gh * 0.5, -d * 0.5 + d * 0.5 * (k / 4.0) + d * 0.0625), Vector3(0.2, gh, d * 0.125), siding)
			Lib.box(root, Vector3(s * w * 0.5, y + h + gh * 0.5, d * 0.5 - d * 0.5 * (k / 4.0) - d * 0.0625), Vector3(0.2, gh, d * 0.125), siding)
	Lib.box(root, Vector3(0, y + h, 0), Vector3(w, 0.1, d), dark)
	# porch
	Lib.box(root, Vector3(-2.5, 0.3, d * 0.5 + 1.2), Vector3(4.0, 0.2, 2.2), dark, true)
	for x in [-4.3, -0.7]:
		Lib.box(root, Vector3(x, 1.7, d * 0.5 + 2.1), Vector3(0.15, 2.8, 0.15), dark, true)
	Lib.box(root, Vector3(-2.5, 3.1, d * 0.5 + 1.3), Vector3(4.4, 0.12, 2.4), Lib.mat("rust", Color(0.6, 0.55, 0.5)), true, Vector3(0.15, 0, 0))
	# furniture
	loot(root, Vector3(-3.6, y, -3.2), Vector3(2.4, 0.9, 0.6), Lib.mat("planks", Color(0.9, 0.9, 0.85)), key + "_kitchen", "Kitchen cabinets", "kitchen")
	loot(root, Vector3(4.0, y, -3.2), Vector3(1.2, 2.0, 0.6), dark, key + "_wardrobe", "Wardrobe", "wardrobe")
	var bed := loot(root, Vector3(3.2, y, 1.5), Vector3(1.4, 0.5, 2.1), dark, key + "_bed", "Bed", "", "bed")
	Lib.box(bed, Vector3(0, 0.6, 0), Vector3(1.3, 0.2, 2.0), Lib.mat("canvas", Color(0.7, 0.5, 0.5), 0.6, false))
	Lib.box(root, Vector3(-2.5, y + 0.4, -0.5), Vector3(1.6, 0.08, 1.0), dark, true)
	for x in [-3.1, -1.9]:
		Lib.box(root, Vector3(x, y + 0.2, -0.5), Vector3(0.08, 0.4, 0.9), dark)
	if rng.randf() < 0.7:
		loot(root, Vector3(-4.2, y, 2.6), Vector3(1.0, 0.8, 0.6), Lib.mat("rust"), key + "_garage", "Toolbox", "garage")

static func _car(root: Node3D, pos: Vector3, yaw: float, tint: Color, key: String) -> void:
	var car := Node3D.new()
	car.position = pos
	car.rotation = Vector3(randf_range(-0.04, 0.04), yaw, randf_range(-0.06, 0.06))
	root.add_child(car)
	var body := Lib.mat("rust", tint, 0.6)
	Lib.box(car, Vector3(0, 0.65, 0), Vector3(1.8, 0.7, 4.3), body, true)
	Lib.box(car, Vector3(0, 1.25, -0.2), Vector3(1.6, 0.55, 2.2), body, true)
	Lib.box(car, Vector3(0, 1.25, 0.92), Vector3(1.5, 0.45, 0.05), Lib.glass_mat(), false, Vector3(-0.5, 0, 0))
	for x in [-0.92, 0.92]:
		for z in [-1.35, 1.35]:
			Lib.cyl(car, Vector3(x, 0.33, z), 0.33, 0.33, 0.25, Lib.color_mat(Color(0.08, 0.08, 0.08), 0.9), Vector3(0, 0, PI * 0.5))
	loot(car, Vector3(0, 0.9, -2.0), Vector3(1.6, 0.35, 0.5), body, key, "Car trunk", "trunk")

static func _wrecks(root: Node3D, key: String, rng: RandomNumberGenerator) -> void:
	var tints := [Color(0.5, 0.6, 0.8), Color(0.9, 0.85, 0.7), Color(0.8, 0.4, 0.35), Color(0.6, 0.7, 0.55)]
	for i in range(rng.randi_range(2, 3)):
		_car(root, Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-3, 3) + i * 2.0), rng.randf() * TAU, tints[i % tints.size()], "%s_car%d" % [key, i])

static func _camp(root: Node3D, key: String, rng: RandomNumberGenerator) -> void:
	var canvas := Lib.mat("canvas", Color(0.75, 0.65, 0.55), 0.5, false)
	for i in range(2):
		var t := Node3D.new()
		t.position = Vector3(-4 + i * 7, 0, -3 + i)
		t.rotation.y = rng.randf() * TAU
		root.add_child(t)
		for s in [-1.0, 1.0]:
			Lib.box(t, Vector3(s * 0.62, 0.72, 0), Vector3(0.04, 1.75, 2.4), canvas, true, Vector3(0, 0, s * 0.62 + rng.randf_range(-0.15, 0.15)))
	var fire := StaticBody3D.new()
	fire.set_script(Structure)
	fire.persistent = false
	fire.setup("", {"type": "campfire", "pos": [0, 0, 0], "rot": 0.0, "data": {"fuel": 0.0}})
	root.add_child(fire)
	fire.position = Vector3(0, 0, 2)
	loot(root, Vector3(3, 0, -4), Vector3(1.1, 0.8, 0.7), Lib.mat("planks"), key + "_crate1", "Supply crate", "camp")
	loot(root, Vector3(-5, 0, 2), Vector3(1.1, 0.8, 0.7), Lib.mat("planks"), key + "_crate2", "Supply crate", "camp")
	for i in range(3):
		Lib.cyl(root, Vector3(rng.randf_range(-3, 3), 0.2, rng.randf_range(3, 5)), 0.2, 0.22, 1.6, Lib.mat("bark", Color.WHITE, 1.0, false), Vector3(0, rng.randf() * TAU, PI * 0.5))

static func _farm(root: Node3D, key: String, rng: RandomNumberGenerator) -> void:
	var red := Lib.mat("planks", Color(0.75, 0.3, 0.25), 0.33)
	var w := 9.0
	var d := 8.0
	var h := 4.2
	Lib.box(root, Vector3(0, 0.1, -2), Vector3(w, 0.2, d), Lib.mat("concrete"), true)
	wall(root, Vector3(0, 0.2, -2 + d * 0.5), w, h, red, false, 3.4, 3.2, 0.0)
	wall(root, Vector3(0, 0.2, -2 - d * 0.5), w, h, red)
	wall(root, Vector3(-w * 0.5, 0.2, -2), d, h, red, true)
	wall(root, Vector3(w * 0.5, 0.2, -2), d, h, red, true)
	for s in [-1.0, 1.0]:
		Lib.box(root, Vector3(s * w * 0.27, h + 1.1, -2), Vector3(w * 0.6, 0.2, d + 0.6), Lib.mat("rust", Color(0.5, 0.5, 0.55)), true, Vector3(0, 0, -s * 0.5))
	loot(root, Vector3(-2.5, 0.2, -4.5), Vector3(1.2, 0.8, 0.8), Lib.mat("planks"), key + "_c1", "Feed crate", "farm")
	loot(root, Vector3(2.5, 0.2, -4.5), Vector3(1.2, 0.8, 0.8), Lib.mat("planks"), key + "_c2", "Seed crate", "farm")
	loot(root, Vector3(3.5, 0.2, 0.0), Vector3(1.0, 0.8, 0.6), Lib.mat("rust"), key + "_tools", "Tool chest", "garage")
	# well
	var well := loot(root, Vector3(-7.5, 0, 5), Vector3(1.4, 0.9, 1.4), Lib.mat("rock", Color.WHITE, 0.6), key + "_well", "Well", "", "well")
	for x in [-0.6, 0.6]:
		Lib.box(well, Vector3(x, 1.4, 0), Vector3(0.1, 1.2, 0.1), Lib.mat("planks"))
	Lib.box(well, Vector3(0, 2.05, 0), Vector3(1.6, 0.1, 1.2), Lib.mat("planks", Color(0.6, 0.5, 0.4)), false, Vector3(0, 0, 0.2))
	# fence rows
	var dark := Lib.mat("planks", Color(0.6, 0.55, 0.5), 0.33)
	for i in range(8):
		Lib.box(root, Vector3(6.5, 0.6, -6 + i * 2.0), Vector3(0.12, 1.2, 0.12), dark, true)
	Lib.box(root, Vector3(6.5, 0.9, 1.0), Vector3(0.06, 0.1, 14), dark)
