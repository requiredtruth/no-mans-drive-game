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
		"house":
			house(root, Vector3.ZERO, 0.0, key, rng, ["cottage", "brick", "log"][rng.randi() % 3])
		"cabin":
			house(root, Vector3.ZERO, 0.0, key, rng, "log", true)
		"hamlet":
			house(root, Vector3(-12, 0, -2), 0.25, key + "a", rng, ["cottage", "brick"][rng.randi() % 2])
			house(root, Vector3(12, 0, -3), -0.2, key + "b", rng, ["cottage", "log", "brick"][rng.randi() % 3])
			house(root, Vector3(0, 0, -16), 0.0, key + "c", rng, ["cottage", "log"][rng.randi() % 2])
			Lib.box(root, Vector3(0, 0.03, -2), Vector3(10, 0.06, 26), Lib.mat("asphalt", Color(0.9, 0.9, 0.9), 0.25), true)
		"truck_stop":
			_gas_station(root, key, rng)
		"wrecks": _wrecks(root, key, rng)
		"camp_ruin": _camp(root, key, rng)
		"farm": _farm(root, key, rng)
	return root

## A fuel pump's face: price window, a grey kick panel, a holster with the nozzle hanging in it and
## the hose coming out of the side (the hose follows you when you take the nozzle).
static func pump_details(pump: Node3D) -> void:
	var dark := Lib.mat("plastic", Color(0.12, 0.13, 0.13), 2.0, false, 0.5)
	var grime := Lib.mat("paint_grime", Color(0.9, 0.9, 0.9), 1.0, false, 0.6, 0.2)
	for zs in [1.0, -1.0]:
		Lib.box(pump, Vector3(0, 1.3, 0.285 * zs), Vector3(0.56, 0.34, 0.02), dark, false, Vector3.ZERO, 0.01)
		Lib.box(pump, Vector3(0, 1.3, 0.297 * zs), Vector3(0.46, 0.22, 0.004), Lib.color_mat(Color(0.12, 0.3, 0.2), 0.15))
		Lib.box(pump, Vector3(0, 0.3, 0.282 * zs), Vector3(0.72, 0.5, 0.015), grime, false, Vector3.ZERO, 0.01)
		var price := Label3D.new()
		price.text = "UNLEADED  1.87"
		price.font_size = 40
		price.pixel_size = 0.0016
		price.double_sided = false
		price.modulate = Color(0.55, 1.0, 0.6)
		price.outline_size = 0
		price.position = Vector3(0, 1.3, 0.301 * zs)
		price.rotation.y = 0.0 if zs > 0.0 else PI
		pump.add_child(price)
	Lib.box(pump, Vector3(0, 1.72, 0), Vector3(0.84, 0.06, 0.6), dark, false, Vector3.ZERO, 0.02)
	# holster on the side with the nozzle in it
	Lib.box(pump, Vector3(0.43, 1.0, 0.1), Vector3(0.06, 0.16, 0.12), dark, false, Vector3.ZERO, 0.01)
	var nz := Items.instance("pump_nozzle")
	nz.name = "Holster"
	nz.position = Vector3(0.47, 0.92, 0.1)
	nz.rotation = Vector3(0, PI * 0.5, 0.25)
	pump.add_child(nz)
	var hose := Lib.cyl(pump, Vector3(0.45, 0.7, -0.12), 0.022, 0.022, 0.9, Lib.mat("rubber", Color(0.25, 0.25, 0.25), 3.0, false, 0.85))
	hose.name = "Hose"

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

## A searchable slatted wooden crate (what you find is laid out in front of it).
static func crate_loot(parent: Node3D, pos: Vector3, size: Vector3, key: String, label: String, table: String, rot := 0.0) -> Node3D:
	var body := StaticBody3D.new()
	body.set_script(Loot)
	body.setup(key, label, table)
	body.position = pos
	body.rotation.y = rot
	parent.add_child(body)
	Structure.slatted_crate(body, size, maxi(int(size.y / 0.17), 3))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	return body

## A road-trip destination (Data.OBJECTIVES): a big green road sign on two posts facing the
## oncoming traffic, and a slatted supply crate left for travellers.
static func destination(parent: Node3D, road_pt: Vector3, dir: Vector3, index: int, gen) -> void:
	var Data = load("res://scripts/data.gd")
	var perp := Vector3(-dir.z, 0, dir.x)
	var sp := road_pt + perp * 7.5
	sp.y = gen.height(sp.x, sp.z)
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = sp
	root.rotation.y = atan2(-dir.x, -dir.z)
	var post := Lib.mat("metal", Color(0.6, 0.62, 0.64), 4.0, false, 0.4, 0.8)
	for x in [-1.3, 1.3]:
		Lib.cyl(root, Vector3(x, 1.6, 0), 0.05, 0.05, 3.2, post, Vector3.ZERO, 10)
	var board := Lib.mat("paint_grime", Color(0.12, 0.42, 0.22), 1.0, false, 0.5, 0.2)
	Lib.box(root, Vector3(0, 2.55, 0.06), Vector3(3.4, 1.2, 0.05), board, true, Vector3.ZERO, 0.03)
	Lib.box(root, Vector3(0, 2.55, 0.088), Vector3(3.25, 1.06, 0.004), Lib.color_mat(Color(0.95, 0.95, 0.9), 0.4))
	Lib.box(root, Vector3(0, 2.55, 0.09), Vector3(3.17, 0.98, 0.004), board)
	var title := Label3D.new()
	title.text = str(Data.OBJECTIVES[index][0]).to_upper()
	title.font_size = 72
	title.pixel_size = 0.0055
	title.outline_size = 0
	title.modulate = Color(0.97, 0.97, 0.93)
	title.double_sided = false
	title.position = Vector3(0, 2.72, 0.095)
	root.add_child(title)
	var sub := Label3D.new()
	sub.text = "STOP %d OF %d" % [index + 1, Data.OBJECTIVES.size()]
	sub.font_size = 48
	sub.pixel_size = 0.0045
	sub.outline_size = 0
	sub.modulate = Color(0.97, 0.97, 0.93)
	sub.double_sided = false
	sub.position = Vector3(0, 2.3, 0.095)
	root.add_child(sub)
	# a supply crate by the sign posts
	var crate := StaticBody3D.new()
	crate.set_script(Loot)
	crate.setup("obj%d_crate" % index, "Supply crate", "camp")
	crate.position = Vector3(2.4, 0.0, 0.8)
	crate.rotation.y = 0.3
	root.add_child(crate)
	Structure.slatted_crate(crate, Vector3(0.9, 0.55, 0.6), 4)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.9, 0.55, 0.6)
	cs.shape = sh
	cs.position.y = 0.275
	crate.add_child(cs)

## A cupboard you open by hand (house kitchens, wardrobes, fridges, medicine cabinets): a hollow
## carcass with shelves inside and doors that each swing on their own hinge. The front faces local
## +Z; size is width (x), height (y), depth (z). What it holds appears on the shelves the first time
## you open it, as real items you take out one by one.
static func cupboard(parent: Node3D, pos: Vector3, size: Vector3, key: String, label: String, table: String, style := "kitchen", rot := 0.0) -> Node3D:
	var body := StaticBody3D.new()
	body.set_script(Loot)
	body.setup(key, label, table, "cupboard")
	body.position = pos
	body.rotation.y = rot
	parent.add_child(body)
	var carcass: Material
	var door_m: Material
	var inside: Material
	var handle_m: Material = Items.steel()
	match style:
		"fridge":
			carcass = Lib.mat("paint_grime", Color(0.97, 0.97, 0.95), 1.4, false, 0.35, 0.1)
			door_m = carcass
			inside = Lib.mat("plastic", Color(0.95, 0.96, 0.97), 3.0, false, 0.3)
		"medical":
			carcass = Lib.mat("paint_grime", Color(0.95, 0.96, 0.95), 2.0, false, 0.3, 0.1)
			door_m = carcass
			inside = carcass
		"wardrobe":
			carcass = Lib.mat("wood_grain_v", Color(0.62, 0.48, 0.38), 1.2, false, 0.6)
			door_m = Lib.mat("wood_grain_v", Color(0.7, 0.55, 0.42), 1.2, false, 0.55)
			inside = Lib.mat("wood_grain", Color(0.85, 0.72, 0.58), 1.6, false, 0.7)
			handle_m = Items.brass()
		_:
			carcass = Lib.mat("wood_grain_v", Color(0.95, 0.86, 0.74), 1.4, false, 0.55)
			door_m = Lib.mat("wood_grain_v", Color(1.0, 0.9, 0.78), 1.4, false, 0.5)
			inside = Lib.mat("wood_grain", Color(1.0, 0.94, 0.86), 1.8, false, 0.6)
	var t := 0.025
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var feet := 0.06 if style in ["kitchen", "wardrobe", "fridge"] else 0.0
	var pieces := [
		[Vector3(0, size.y * 0.5, -hz + t * 0.5), Vector3(size.x, size.y, t), inside],
		[Vector3(-hx + t * 0.5, size.y * 0.5, 0), Vector3(t, size.y, size.z), carcass],
		[Vector3(hx - t * 0.5, size.y * 0.5, 0), Vector3(t, size.y, size.z), carcass],
		[Vector3(0, size.y - t * 0.5, 0), Vector3(size.x, t, size.z), carcass],
		[Vector3(0, feet + t * 0.5, 0), Vector3(size.x - 2 * t, t, size.z - t), inside],
	]
	if feet > 0.0:
		pieces.append([Vector3(0, feet * 0.5, hz - 0.05), Vector3(size.x - 2 * t, feet, 0.02), Lib.mat("plastic", Color(0.15, 0.13, 0.12), 3.0, false, 0.6)])
	var shelf_tops: Array = [feet + t]
	var n_shelves := maxi(int((size.y - feet) / 0.42) - 1, 0)
	if style == "wardrobe":
		n_shelves = 1
	for k in range(n_shelves):
		var y: float = feet + (size.y - feet) * (k + 1) / (n_shelves + 1)
		if style == "wardrobe":
			y = size.y - 0.38
		pieces.append([Vector3(0, y, 0), Vector3(size.x - 2 * t, 0.02, size.z - t - 0.02), inside])
		shelf_tops.append(y + 0.01)
	for pc in pieces:
		Lib.box(body, pc[0], pc[1], pc[2], false, Vector3.ZERO, 0.004)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = pc[1]
		cs.shape = sh
		cs.position = pc[0]
		body.add_child(cs)
	if style == "wardrobe":
		Lib.cyl(body, Vector3(0, size.y - 0.48, 0), 0.012, 0.012, size.x - 2 * t, Items.steel(), Vector3(0, 0, PI * 0.5), 10)
		for k in range(3):
			var hx2 := -hx + 0.25 + k * 0.18
			Lib.cyl(body, Vector3(hx2, size.y - 0.53, 0), 0.004, 0.004, 0.08, Items.steel())
			Lib.box(body, Vector3(hx2, size.y - 0.58, 0), Vector3(0.4, 0.015, 0.02), Items.steel(), false, Vector3(0, PI * 0.5, 0))
	if style == "fridge":
		Lib.box(body, Vector3(0, size.y - 0.35, -hz + 0.12), Vector3(size.x - 0.1, 0.12, 0.2), Lib.mat("plastic", Color(0.85, 0.88, 0.9), 3.0, false, 0.3))
	body.shelves = shelf_tops
	body.inner = Vector3(size.x - 2 * t, size.y - feet, size.z - t)
	# doors: one per ~0.6 m of width, hinged on the outer edges in pairs
	var n_doors := maxi(int(round(size.x / 0.6)), 1)
	if style in ["fridge", "medical"]:
		n_doors = 1
	var dw := size.x / n_doors
	var dh := size.y - feet - 0.01
	for i in range(n_doors):
		var hinge_left := (i % 2 == 0) if n_doors > 1 else true
		var x0 := -hx + dw * i
		var hinge_x := x0 if hinge_left else x0 + dw
		var pivot := Node3D.new()
		pivot.position = Vector3(hinge_x, feet + 0.005, hz + 0.01)
		body.add_child(pivot)
		var dir := 1.0 if hinge_left else -1.0
		var dc := Vector3(dir * (dw * 0.5 - 0.003), dh * 0.5, 0.0)
		Lib.box(pivot, dc, Vector3(dw - 0.006, dh, 0.02), door_m, false, Vector3.ZERO, 0.006)
		if style in ["kitchen", "wardrobe"]:
			# raised panel: a frame round a slightly sunk centre panel
			Lib.box(pivot, dc + Vector3(0, 0, 0.011), Vector3(dw - 0.12, dh - 0.14, 0.006), door_m, false, Vector3.ZERO, 0.004)
		if style == "medical":
			var mirror := StandardMaterial3D.new()
			mirror.albedo_color = Color(0.75, 0.8, 0.82)
			mirror.metallic = 1.0
			mirror.roughness = 0.04
			Lib.box(pivot, dc + Vector3(0, 0, 0.011), Vector3(dw - 0.06, dh - 0.06, 0.003), mirror)
		# handle near the free edge
		var hxp := dir * (dw - 0.06)
		var hy := dh * (0.82 if style in ["kitchen"] and size.y < 1.2 else 0.5)
		if style == "fridge":
			Lib.box(pivot, Vector3(hxp, dh * 0.62, 0.035), Vector3(0.025, 0.42, 0.03), handle_m, false, Vector3.ZERO, 0.01)
		else:
			Lib.box(pivot, Vector3(hxp, hy, 0.022), Vector3(0.012, 0.11, 0.014), handle_m, false, Vector3.ZERO, 0.004)
		# the door itself is what you aim at: its collision belongs to the cupboard
		var db := StaticBody3D.new()
		db.collision_layer = 1
		db.set_meta("door_of", body)
		var dcs := CollisionShape3D.new()
		var dsh := BoxShape3D.new()
		dsh.size = Vector3(dw - 0.006, dh, 0.025)
		dcs.shape = dsh
		dcs.position = dc
		db.add_child(dcs)
		pivot.add_child(db)
		body.doors.append([pivot, dir * 1.9])
	return body

## A cardboard box you open to find real items inside (they stay in the box until you take them).
static func cardboard(parent: Node3D, pos: Vector3, key: String, table: String, rot := 0.0, label := "cardboard box") -> Node3D:
	var body := StaticBody3D.new()
	body.set_script(Loot)
	body.setup(key, label, table, "box")
	body.position = pos
	body.rotation.y = rot
	parent.add_child(body)
	var sz := Vector3(0.6, 0.42, 0.46)
	var cb := Lib.mat("cardboard", Color(1.0, 0.95, 0.85), 2.0, false, 0.95)
	var t := 0.015
	for pc in [[Vector3(0, t * 0.5, 0), Vector3(sz.x, t, sz.z)],
			[Vector3(-sz.x * 0.5 + t * 0.5, sz.y * 0.5, 0), Vector3(t, sz.y, sz.z)], [Vector3(sz.x * 0.5 - t * 0.5, sz.y * 0.5, 0), Vector3(t, sz.y, sz.z)],
			[Vector3(0, sz.y * 0.5, -sz.z * 0.5 + t * 0.5), Vector3(sz.x, sz.y, t)], [Vector3(0, sz.y * 0.5, sz.z * 0.5 - t * 0.5), Vector3(sz.x, sz.y, t)]]:
		Lib.box(body, pc[0], pc[1], cb)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = pc[1]
		cs.shape = sh
		cs.position = pc[0]
		body.add_child(cs)
	# a closed lid made of four flaps (closed = flat across the top)
	var lid := CollisionShape3D.new()
	var lsh := BoxShape3D.new()
	lsh.size = Vector3(sz.x, 0.02, sz.z)
	lid.shape = lsh
	lid.position = Vector3(0, sz.y, 0)
	lid.name = "Lid"
	body.add_child(lid)
	var tape := Lib.color_mat(Color(0.75, 0.62, 0.4), 0.6)
	for f in [[Vector3(-sz.x * 0.5, sz.y, 0), Vector3(sz.x * 0.25, 0, 0), Vector3(sz.x * 0.5, 0.008, sz.z), "z", 2.3],
			[Vector3(sz.x * 0.5, sz.y, 0), Vector3(-sz.x * 0.25, 0, 0), Vector3(sz.x * 0.5, 0.008, sz.z), "z", -2.3],
			[Vector3(0, sz.y + 0.008, -sz.z * 0.5), Vector3(0, 0, sz.z * 0.25), Vector3(sz.x, 0.008, sz.z * 0.5), "x", -2.1],
			[Vector3(0, sz.y + 0.008, sz.z * 0.5), Vector3(0, 0, -sz.z * 0.25), Vector3(sz.x, 0.008, sz.z * 0.5), "x", 2.1]]:
		var hinge := Node3D.new()
		hinge.position = f[0]
		hinge.set_meta("axis", f[3])
		hinge.set_meta("open", f[4])
		body.add_child(hinge)
		Lib.box(hinge, f[1], f[2], cb)
		body.flaps.append(hinge)
	Lib.box(body, Vector3(0, sz.y + 0.02, 0), Vector3(0.05, 0.004, sz.z + 0.01), tape)
	if Game.removed.has(key):
		lid.disabled = true
		body.open_flaps(false)
		body.get_child(body.get_child_count() - 1).visible = false
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
		pump_details(pump)
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
	cardboard(root, Vector3(-1.6, 0.25, cz - 2.9), key + "_box1", "shelf", 0.3)
	cardboard(root, Vector3(-1.0, 0.25, cz - 2.6), key + "_box2", "backroom", -0.4)
	cardboard(root, Vector3(3.6, 0.25, cz - 2.6), key + "_box3", "shelf", 1.2, "delivery box")
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
		Lib.box(root, Vector3(0, y + h + tan(ang) * (d * 0.25 + 0.3) - 0.1, s * (d * 0.25 + 0.3)), Vector3(w + 0.8, 0.18, rl), Lib.mat("shingles", Color.WHITE, 0.4), true, Vector3(s * ang, 0, 0))
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
	cupboard(root, Vector3(-3.6, y, -3.2), Vector3(2.4, 0.9, 0.6), key + "_kitchen", "Kitchen cabinets", "kitchen", "kitchen")
	cupboard(root, Vector3(4.0, y, -3.2), Vector3(1.2, 2.0, 0.6), key + "_wardrobe", "Wardrobe", "wardrobe", "wardrobe")
	var bed := loot(root, Vector3(3.2, y, 1.5), Vector3(1.4, 0.5, 2.1), dark, key + "_bed", "Bed", "", "bed")
	Lib.box(bed, Vector3(0, 0.6, 0), Vector3(1.3, 0.2, 2.0), Lib.mat("canvas", Color(0.7, 0.5, 0.5), 0.6, false))
	Lib.box(root, Vector3(-2.5, y + 0.4, -0.5), Vector3(1.6, 0.08, 1.0), dark, true)
	for x in [-3.1, -1.9]:
		Lib.box(root, Vector3(x, y + 0.2, -0.5), Vector3(0.08, 0.4, 0.9), dark)
	if rng.randf() < 0.7:
		loot(root, Vector3(-4.2, y, 2.6), Vector3(1.0, 0.8, 0.6), Lib.mat("rust"), key + "_garage", "Toolbox", "garage")
	cardboard(root, Vector3(-3.4, y, 1.6), key + "_box1", "living", rng.randf() * TAU, "moving box")

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
	# The crashed vehicles themselves are real (repairable) vehicles spawned by the world.
	var pile := loot(root, Vector3(0, 0, -2), Vector3(1.4, 0.5, 1.0), Lib.mat("rust"), key + "_pile", "Scrap pile", "scrap_pile")
	pile.rotation.y = rng.randf() * TAU
	loot(root, Vector3(2.5, 0, 1.5), Vector3(0.9, 0.6, 0.6), Lib.mat("paint", Color(0.3, 0.4, 0.3), 1.0, true, 0.5, 0.4), key + "_box", "Roadside toolbox", "trunk")
	cardboard(root, Vector3(1.2, 0, -3.0), key + "_cb", "scrap_pile", rng.randf() * TAU, "soggy box")
	for k in range(3):
		var t := MeshInstance3D.new()
		t.mesh = Items.mesh("tire")
		t.scale = Vector3.ONE * 1.25
		t.position = Vector3(-3.0, k * 0.28, 2.0)
		t.rotation.y = rng.randf() * TAU
		root.add_child(t)

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
	crate_loot(root, Vector3(3, 0, -4), Vector3(1.1, 0.8, 0.7), key + "_crate1", "Supply crate", "camp")
	crate_loot(root, Vector3(-5, 0, 2), Vector3(1.1, 0.8, 0.7), key + "_crate2", "Supply crate", "camp")
	cardboard(root, Vector3(1.5, 0, -2.5), key + "_cb", "camp", rng.randf() * TAU, "supply box")
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
	crate_loot(root, Vector3(-2.5, 0.2, -4.5), Vector3(1.2, 0.8, 0.8), key + "_c1", "Feed crate", "farm")
	crate_loot(root, Vector3(2.5, 0.2, -4.5), Vector3(1.2, 0.8, 0.8), key + "_c2", "Seed crate", "farm")
	loot(root, Vector3(3.5, 0.2, 0.0), Vector3(1.0, 0.8, 0.6), Lib.mat("rust"), key + "_tools", "Tool chest", "garage")
	cardboard(root, Vector3(3.3, 0.2, -1.4), key + "_cb", "farm", 0.2, "seed box")
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


# ------------------------------------------------------------------ procedural furnished houses
## Wall along local X from x0 to x1 at z, outer skin facing +z if face_out > 0. holes: [[x_center, width, y0, height, kind]]
static func wall_run(parent: Node3D, x0: float, x1: float, z: float, y: float, h: float, outer: Material, inner: Material, holes: Array, face_out := 1.0, along_z := false) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0, y, z) if not along_z else Vector3(z, y, 0)
	if along_z:
		holder.rotation.y = -PI * 0.5
	parent.add_child(holder)
	var edges: Array[float] = [x0, x1]
	for hl in holes:
		edges.append(hl[0] - hl[1] * 0.5)
		edges.append(hl[0] + hl[1] * 0.5)
	edges.sort()
	var t := 0.11
	var trim := Lib.mat("planks", Color(0.92, 0.9, 0.85), 1.0)
	for i in range(edges.size() - 1):
		var a := edges[i]
		var b := edges[i + 1]
		if b - a < 0.01:
			continue
		var c := (a + b) * 0.5
		var spans := [[0.0, h]]
		for hl in holes:
			if c > hl[0] - hl[1] * 0.5 and c < hl[0] + hl[1] * 0.5:
				spans = [[0.0, hl[2]], [hl[2] + hl[3], h]]
				if hl[4] == "window":
					var g := Lib.box(holder, Vector3(c, hl[2] + hl[3] * 0.5, 0), Vector3(b - a, hl[3], 0.03), Lib.glass_mat(), true)
					g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					for yy in [hl[2], hl[2] + hl[3]]:
						Lib.box(holder, Vector3(c, yy, 0), Vector3(b - a + 0.12, 0.08, 0.3), trim)
					for xx in [a, b]:
						Lib.box(holder, Vector3(xx, hl[2] + hl[3] * 0.5, 0), Vector3(0.08, hl[3] + 0.08, 0.3), trim)
					Lib.box(holder, Vector3(c, hl[2] + hl[3] * 0.5, 0), Vector3(0.04, hl[3], 0.05), trim)
					Lib.box(holder, Vector3(c, hl[2] - 0.06, face_out * 0.14), Vector3(b - a + 0.2, 0.05, 0.12), trim)
				else:
					for xx in [a, b]:
						Lib.box(holder, Vector3(xx, hl[3] * 0.5, 0), Vector3(0.1, hl[3], 0.3), trim)
					Lib.box(holder, Vector3(c, hl[3], 0), Vector3(b - a + 0.2, 0.12, 0.3), trim)
		for sp in spans:
			var hh: float = sp[1] - sp[0]
			if hh < 0.01:
				continue
			var cy: float = sp[0] + hh * 0.5
			Lib.box(holder, Vector3(c, cy, face_out * t * 0.5), Vector3(b - a, hh, t), outer, true, Vector3.ZERO, 0.0)
			Lib.box(holder, Vector3(c, cy, -face_out * t * 0.5), Vector3(b - a, hh, t), inner, false, Vector3.ZERO, 0.0)

static func _decor(parent: Node3D, pos: Vector3, id: String, rot := 0.0, s := 1.0) -> void:
	var n := Items.instance(id)
	n.position = pos
	n.rotation.y = rot
	n.scale = Vector3.ONE * s
	parent.add_child(n)

## Free-standing furniture in a house is real, movable furniture: it is spawned once as a
## normal placeable (saved with the game) and never comes back once you've taken it.
static func _furn(parent: Node3D, pos: Vector3, rot: float, type: String, id: String) -> void:
	var xf: Transform3D = parent.global_transform * Transform3D(Basis(Vector3.UP, rot), pos)
	var rec := {"type": type, "pos": Game.arr(xf.origin), "rot": xf.basis.get_euler().y, "data": {}}
	if Game.world:
		Game.world.call_deferred("spawn_poi_furniture", id, rec)

static func house(root: Node3D, offset: Vector3, yaw: float, key: String, rng: RandomNumberGenerator, style: String, small := false) -> void:
	var hn := Node3D.new()
	hn.position = offset
	hn.rotation.y = yaw
	root.add_child(hn)
	var w := rng.randf_range(7.5, 11.0) if not small else 6.0
	var d := rng.randf_range(7.0, 9.5) if not small else 5.5
	var h := 2.8
	var fy := 0.6
	var pastel := [Color(0.95, 0.92, 0.82), Color(0.75, 0.85, 0.9), Color(0.85, 0.9, 0.78), Color(0.95, 0.85, 0.75), Color(0.9, 0.8, 0.85), Color(0.98, 0.98, 0.95)]
	var ext: Material
	match style:
		"brick": ext = Lib.mat("brick", Color.WHITE, 0.45)
		"log": ext = Lib.mat("logs", Color.WHITE, 0.333)
		_: ext = Lib.mat("siding", pastel[rng.randi() % pastel.size()], 0.35)
	var paper := Lib.mat("wallpaper", [Color.WHITE, Color(0.9, 1.0, 0.95), Color(1.0, 0.92, 0.9)][rng.randi() % 3], 0.6)
	var inner: Material = paper if style != "log" else Lib.mat("logs", Color(1.1, 1.05, 1.0), 0.333)
	var wood_floor := Lib.mat("planks", Color(0.8, 0.7, 0.6), 0.5)
	var tile := Lib.mat("tiles_cracked", Color.WHITE, 0.55)
	var dark := Lib.mat("planks", Color(0.5, 0.4, 0.32), 1.0)
	var fabric := Lib.mat("canvas", [Color(0.6, 0.7, 0.9), Color(0.85, 0.6, 0.5), Color(0.6, 0.8, 0.6)][rng.randi() % 3], 1.5, false)
	# foundation & floors
	Lib.box(hn, Vector3(0, fy * 0.5 - 0.3, 0), Vector3(w + 0.3, fy + 0.6, d + 0.3), Lib.mat("rock", Color(0.85, 0.83, 0.8), 0.6), true, Vector3.ZERO, 0.04)
	Lib.box(hn, Vector3(0, fy + 0.01, 0), Vector3(w - 0.2, 0.02, d - 0.2), wood_floor)
	var split_z := -d * 0.12
	var split_x := w * 0.18
	Lib.box(hn, Vector3(split_x + (w * 0.5 - split_x) * 0.5, fy + 0.025, split_z - (d * 0.5 + split_z) * 0.5), Vector3(w * 0.5 - split_x - 0.2, 0.02, d * 0.5 + split_z - 0.2), tile)
	# exterior walls with windows / door
	var door_x := -w * 0.22
	wall_run(hn, -w * 0.5, w * 0.5, d * 0.5, fy, h, ext, inner, [[door_x, 1.05, 0.0, 2.15, "door"], [w * 0.22, 1.4, 1.0, 1.2, "window"]] if not small else [[door_x, 1.05, 0.0, 2.15, "door"], [w * 0.2, 1.1, 1.0, 1.1, "window"]], 1.0)
	wall_run(hn, -w * 0.5, w * 0.5, -d * 0.5, fy, h, ext, inner, [[-w * 0.25, 1.2, 1.0, 1.2, "window"], [w * 0.3, 0.7, 1.4, 0.7, "window"]], -1.0)
	wall_run(hn, -d * 0.5, d * 0.5, -w * 0.5, fy, h, ext, inner, [[d * 0.15, 1.3, 1.0, 1.2, "window"]], -1.0, true)
	wall_run(hn, -d * 0.5, d * 0.5, w * 0.5, fy, h, ext, inner, [[d * 0.2, 1.1, 1.0, 1.2, "window"]], 1.0, true)
	if not small:
		# interior partitions with doorways
		wall_run(hn, -w * 0.5 + 0.1, w * 0.5 - 0.1, split_z, fy, h, inner, inner, [[-w * 0.3, 0.9, 0.0, 2.1, "door"], [w * 0.36, 0.8, 0.0, 2.1, "door"]], 1.0)
		wall_run(hn, -d * 0.5 + 0.1, split_z, split_x, fy, h, inner, inner, [], 1.0, true)
	# ceiling and pitched roof with gables
	Lib.box(hn, Vector3(0, fy + h + 0.03, 0), Vector3(w, 0.06, d), Lib.mat("planks", Color(0.95, 0.93, 0.88), 0.5))
	var pitch := 0.5
	var rise := tan(pitch) * (d * 0.5 + 0.5)
	var slab := (d * 0.5 + 0.55) / cos(pitch)
	var roof_m := Lib.mat("shingles", [Color.WHITE, Color(0.8, 0.55, 0.45), Color(0.6, 0.7, 0.8), Color(0.6, 0.75, 0.55)][rng.randi() % 4], 0.4)
	for s in [-1.0, 1.0]:
		Lib.box(hn, Vector3(0, fy + h + rise * 0.5 + 0.05, s * (d * 0.25 + 0.25)), Vector3(w + 0.8, 0.14, slab), roof_m, true, Vector3(s * pitch, 0, 0), 0.03)
		Lib.box(hn, Vector3(0, fy + h - 0.05, s * (d * 0.5 + 0.5)), Vector3(w + 0.8, 0.18, 0.06), Lib.mat("planks", Color(0.9, 0.9, 0.88), 1.0))
	Lib.box(hn, Vector3(0, fy + h + rise + 0.08, 0), Vector3(w + 0.85, 0.1, 0.22), roof_m)
	var gable_body := load("res://scripts/shapes.gd")
	for s in [-1.0, 1.0]:
		var gst: SurfaceTool = gable_body.st()
		var tri := PackedVector2Array([Vector2(-d * 0.5, 0.0), Vector2(d * 0.5, 0.0), Vector2(0.0, rise - 0.05)])
		gable_body.extrude(gst, null, tri, 0.18, 0.0)
		var gm := MeshInstance3D.new()
		gm.mesh = gable_body.commit([[gst, ext]])
		gm.position = Vector3(s * (w * 0.5 - 0.08), fy + h, 0)
		hn.add_child(gm)
	if rng.randf() < 0.6 or style == "log":
		Lib.box(hn, Vector3(w * 0.3, fy + h + rise * 0.6, -d * 0.15), Vector3(0.7, rise * 1.2 + 0.8, 0.7), Lib.mat("brick", Color(0.85, 0.8, 0.8), 0.45), true, Vector3.ZERO, 0.03)
	# porch, steps, mailbox
	var porch := rng.randf() < 0.7 or small
	if porch:
		Lib.box(hn, Vector3(door_x, fy - 0.05, d * 0.5 + 1.1), Vector3(3.2, 0.12, 2.0), dark, true, Vector3.ZERO, 0.02)
		for x in [door_x - 1.5, door_x + 1.5]:
			Lib.box(hn, Vector3(x, fy + 1.2, d * 0.5 + 2.0), Vector3(0.14, 2.4, 0.14), Lib.mat("planks", Color(0.95, 0.95, 0.9), 1.0), true)
		Lib.box(hn, Vector3(door_x, fy + 2.45, d * 0.5 + 1.15), Vector3(3.6, 0.1, 2.3), roof_m, true, Vector3(0.12, 0, 0))
	for k in range(3):
		Lib.box(hn, Vector3(door_x, fy - 0.15 - k * 0.15, d * 0.5 + (2.2 if porch else 0.3) + k * 0.3), Vector3(1.4, 0.15, 0.3), Lib.mat("concrete"), true, Vector3.ZERO, 0.02)
	Lib.box(hn, Vector3(w * 0.5 + 1.5, 0.6, d * 0.5 + 3.5), Vector3(0.08, 1.2, 0.08), dark)
	Lib.box(hn, Vector3(w * 0.5 + 1.5, 1.25, d * 0.5 + 3.5), Vector3(0.25, 0.22, 0.45), Lib.mat("paint", Color(0.3, 0.35, 0.4), 2.0, true, 0.4, 0.4), false, Vector3.ZERO, 0.03)
	var y := fy + 0.02
	# contact shadow and dirt along the skirting all round the inside
	Lib.room_grime(hn, Vector3(-w * 0.5 + 0.11, y + 0.006, -d * 0.5 + 0.11), Vector3(w * 0.5 - 0.11, y + 0.006, d * 0.5 - 0.11), 0.35, 0.18)
	# --- living room (front left)
	var lx := -w * 0.25
	var lz := (d * 0.5 + split_z) * 0.5 + 0.2
	if not small:
		# movable furniture: sofa against the side wall, a rug, and a spare shelf unit
		_furn(hn, Vector3(-w * 0.5 + 0.55, y, lz), PI * 0.5, "sofa", key + "_f_sofa")
		_furn(hn, Vector3(lx + 0.4, y, lz), PI * 0.5, ["rug", "mod_rug_persian", "mod_rug_braided", "mod_rug_woven", "mod_rug_cowhide"][rng.randi() % 5], key + "_f_rug")
		_furn(hn, Vector3(lx + 0.9, y, lz - 0.7), PI * 0.5, "chair", key + "_f_armchair")
		# bookshelf (searchable) against the partition wall, clear of every doorway
		var shelf := loot(hn, Vector3(-w * 0.3 + 1.4, y, split_z + 0.25), Vector3(1.4, 1.9, 0.35), dark, key + "_shelf", "Bookshelf", "living")
		cardboard(hn, Vector3(lx + 1.1, y, lz + 1.15), key + "_mbox", "living" if rng.randf() < 0.6 else "kitchen", rng.randf() * TAU, "moving box")
		for k in range(4):
			Lib.box(shelf, Vector3(0, 0.3 + k * 0.45, 0.02), Vector3(1.3, 0.03, 0.3), dark)
		for k in range(5):
			_decor(shelf, Vector3(-0.5 + k * 0.25, 0.75, 0.0), ["canned_food", "soda", "water_clean", "coffee_beans", "bandage"][k], k * 0.7, 0.9)
		for k in range(8):
			Lib.box(shelf, Vector3(-0.55 + k * 0.08, 1.4, 0.0), Vector3(0.05, 0.28, 0.22), Lib.color_mat(Color.from_hsv(rng.randf(), 0.5, 0.5), 0.8), false, Vector3(0, 0, rng.randf_range(-0.1, 0.1)))
	# --- kitchen (front right)
	var kx := w * 0.28
	var kz := (d * 0.5 + split_z) * 0.5
	var counter_z := d * 0.5 - 0.42
	if small:
		counter_z = -d * 0.5 + 0.42
	var cab := cupboard(hn, Vector3(kx + 0.3, y, counter_z), Vector3(2.4, 0.9, 0.62), key + "_kitchen", "Kitchen cabinets", "kitchen", "kitchen", PI if counter_z > 0.0 else 0.0)
	Lib.box(cab, Vector3(0, 0.92, 0), Vector3(2.45, 0.05, 0.66), Lib.mat("concrete", Color(0.95, 0.95, 0.95), 1.0), false, Vector3.ZERO, 0.02)
	Lib.box(cab, Vector3(-0.6, 0.93, 0), Vector3(0.6, 0.04, 0.45), Items.steel())
	Lib.box(cab, Vector3(0.6, 0.94, 0), Vector3(0.6, 0.02, 0.55), Lib.color_mat(Color(0.08, 0.08, 0.08), 0.3))
	for k in range(4):
		Lib.cyl(cab, Vector3(0.45 + (k % 2) * 0.3, 0.955, -0.12 + (k / 2) * 0.24), 0.08, 0.08, 0.01, Items.dark_steel())
	_decor(cab, Vector3(0.0, 0.95, 0.05), "canned_food", 0.3)
	_decor(cab, Vector3(-0.2, 0.95, -0.1), "water_dirty", 0.0)
	cupboard(hn, Vector3(kx + 1.9 if kx + 1.9 < w * 0.5 - 0.4 else kx - 1.3, y, counter_z), Vector3(0.75, 1.8, 0.7), key + "_fridge", "Old fridge", "kitchen", "fridge", PI if counter_z > 0.0 else 0.0)
	if not small:
		# movable kitchen table and chairs
		_furn(hn, Vector3(kx, y, kz - 0.4), 0.0, "table", key + "_f_table")
		_furn(hn, Vector3(kx - 0.35, y, kz - 1.25), PI, "chair", key + "_f_chair1")
		_furn(hn, Vector3(kx + 0.35, y, kz + 0.45), 0.0, "chair", key + "_f_chair2")
	else:
		_furn(hn, Vector3(0.3, y, 0.4), 0.0, "camp_folding_chair", key + "_f_chair1")
	# --- bedroom (back left)
	var bx := -w * 0.2
	var bz := -d * 0.5 + 1.25
	var bed := loot(hn, Vector3(bx, y, bz), Vector3(1.5, 0.5, 2.1), dark, key + "_bed", "Bed", "", "bed", PI * 0.5)
	Lib.box(bed, Vector3(0, 0.58, 0.05), Vector3(1.42, 0.18, 1.95), Lib.mat("canvas", Color(0.95, 0.95, 0.92), 2.0, false), false, Vector3.ZERO, 0.06)
	Lib.box(bed, Vector3(0, 0.7, 0.25), Vector3(1.44, 0.06, 1.3), Lib.mat("plaid", Color.WHITE, 1.2, false), false, Vector3.ZERO, 0.03)
	for xx in [-0.35, 0.35]:
		Lib.box(bed, Vector3(xx, 0.72, -0.75), Vector3(0.55, 0.12, 0.35), Lib.color_mat(Color(0.95, 0.95, 0.93)), false, Vector3.ZERO, 0.05)
	Lib.box(bed, Vector3(0, 0.75, -1.03), Vector3(1.55, 1.0, 0.08), dark, false, Vector3.ZERO, 0.02)
	if not small:
		cupboard(hn, Vector3(-w * 0.5 + 0.4, y, split_z - 0.6), Vector3(1.2, 2.0, 0.6), key + "_wardrobe", "Wardrobe", "wardrobe", "wardrobe", PI * 0.5)
		# bathroom (back right)
		var tx := w * 0.5 - 0.5
		var tz := -d * 0.5 + 0.5
		Lib.box(hn, Vector3(tx, y + 0.22, tz + 0.2), Vector3(0.4, 0.44, 0.5), Lib.color_mat(Color(0.96, 0.96, 0.96), 0.15), true, Vector3.ZERO, 0.06)
		Lib.box(hn, Vector3(tx + 0.12, y + 0.65, tz + 0.2), Vector3(0.15, 0.45, 0.45), Lib.color_mat(Color(0.96, 0.96, 0.96), 0.15), false, Vector3.ZERO, 0.05)
		var tub_x := split_x + 1.0
		Lib.box(hn, Vector3(tub_x, y + 0.28, -d * 0.5 + 0.45), Vector3(1.6, 0.56, 0.75), Lib.color_mat(Color(0.96, 0.96, 0.96), 0.15), true, Vector3.ZERO, 0.1)
		cupboard(hn, Vector3(tx, y + 1.2, split_z - 0.15), Vector3(0.6, 0.6, 0.18), key + "_med", "Medicine cabinet", "medical", "medical", PI)
	else:
		# cabin wood stove
		Lib.box(hn, Vector3(w * 0.32, y + 0.4, -d * 0.5 + 0.6), Vector3(0.7, 0.8, 0.6), Items.dark_steel(), true, Vector3.ZERO, 0.05)
		Lib.cyl(hn, Vector3(w * 0.32, y + 2.0, -d * 0.5 + 0.6), 0.09, 0.09, 2.4, Items.dark_steel())
		loot(hn, Vector3(-w * 0.5 + 0.4, y, 0.3), Vector3(0.6, 0.9, 1.0), dark, key + "_chest", "Old chest", "camp")
