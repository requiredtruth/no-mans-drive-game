extends Node
## Automated smoke test & screenshot tour. Run: godot --path game -- --devtest=<out_dir>

var out := "user://shots"
var log_lines: Array[String] = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--devtest="):
			out = a.substr(10)
	DirAccess.make_dir_recursive_absolute(out)
	_run()

func _log(s: String) -> void:
	print("[devtest] ", s)
	log_lines.append(s)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	_log("shot " + name)

func _player_at(p: Vector3, yaw: float, pitch := -0.1) -> void:
	var pl = Game.player
	pl.teleport(p)
	pl.rotation.y = yaw
	pl.pitch = pitch
	pl.head.rotation.x = pitch

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, Game.world.gen.height(x, z) + 0.1, z)

func _settle(p: Vector3) -> void:
	# wait for chunks around p to stream in
	for i in range(240):
		if Game.world.ground_ready(p) and Game.world._pending.is_empty():
			break
		await get_tree().process_frame
	await _wait(0.6)

func _items_sheet() -> void:
	var Data = load("res://scripts/data.gd")
	var ids: Array = Data.ITEMS.keys()
	for id in ids:
		Items.icon(id)
	for i in range(600):
		var done := true
		for id in ids:
			if Items.icon(id) == null:
				done = false
		if done:
			break
		await get_tree().process_frame
	var cols := 9
	var sheet := Image.create(128 * cols, 128 * int(ceil(ids.size() / float(cols))), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.18, 0.2, 0.22))
	for i in range(ids.size()):
		var t: Texture2D = Items.icon(ids[i])
		if t:
			var img := t.get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(img, Rect2i(0, 0, 128, 128), Vector2i((i % cols) * 128, (i / cols) * 128))
	sheet.save_png("%s/items_sheet.png" % out)
	_log("items sheet: %d items" % ids.size())

func _viewmodels() -> void:
	for id in ["axe", "knife", "rifle", "bow", "fishing_rod", "pickaxe", "hammer", "flashlight", "canned_food"]:
		Game.add_item(id, 1, true)
		Game.assign_hotbar(id)
		await _wait(0.4)
		await _shot("vm_" + id)

func _vehicles() -> void:
	var w = Game.world
	var rv = Game.rv
	w.hud.close_modal()
	Game.time_of_day = 10.0
	var z0: float = rv.global_position.z - 30.0
	var gen = w.gen
	var kinds := ["pickup", "sedan", "box_truck", "offroader", "camper", "flatbed", "tanker"]
	var made := []
	for i in range(kinds.size()):
		var z := z0 - i * 9.0
		var x: float = gen.road_x(z) + 2.0
		var p := Vector3(x, gen.height(x, z) + 1.0, z)
		made.append(w.spawn_vehicle("test_%d" % i, kinds[i], p, Vector3(0, PI * 0.5, 0), {}))
	await _wait(2.5)
	for i in range(kinds.size()):
		var v: Node3D = made[i]
		var cam: Vector3 = v.global_position + Vector3(-5.5, 0.6, 5.0)
		_player_at(Vector3(cam.x, gen.height(cam.x, cam.z) + 0.1, cam.z), atan2(-(v.global_position - cam).x, -(v.global_position - cam).z), -0.12)
		await _wait(0.5)
		await _shot("veh_" + kinds[i])
	var rc: Vector3 = rv.to_global(Vector3(-7.0, 0, 7.0))
	_player_at(Vector3(rc.x, gen.height(rc.x, rc.z) + 0.1, rc.z), atan2(-(rv.global_position - rc).x, -(rv.global_position - rc).z), -0.08)
	await _wait(0.6)
	await _shot("veh_rv_front")
	rc = rv.to_global(Vector3(7.5, 0, -6.0))
	_player_at(Vector3(rc.x, gen.height(rc.x, rc.z) + 0.1, rc.z), atan2(-(rv.global_position - rc).x, -(rv.global_position - rc).z), -0.08)
	await _wait(0.6)
	await _shot("veh_rv_rear")
	# hitch flatbed to pickup and tow
	var pickup = made[0]
	var flat = made[5]
	flat.global_position = pickup.hitch_global() - (flat.tongue_global() - flat.global_position)
	flat.rotation = pickup.rotation
	await _wait(1.0)
	flat.hitch_to(pickup)
	for k in pickup.parts:
		pickup.parts[k] = 100.0
	pickup.fuel = 50.0
	pickup.battery = 100.0
	var t0: Vector3 = flat.global_position
	Game.player.enter_vehicle(pickup, true)
	Input.action_press("move_forward", 1.0)
	await _wait(5.0)
	Input.action_release("move_forward")
	_log("tow: pickup speed %.1f km/h, trailer moved %.1f m" % [pickup.speed_kmh(), flat.global_position.distance_to(t0)])
	await _shot("veh_towing")
	Game.player.exit_vehicle()

func _animals() -> void:
	var w = Game.world
	w.hud.close_modal()
	Game.time_of_day = 11.0
	var gen = w.gen
	var z: float = Game.player.global_position.z - 15.0
	var x: float = gen.road_x(z)
	var i := 0
	for sp in ["deer", "boar", "wolf", "bear", "rabbit"]:
		var p := Vector3(x - 4.0 + i * 2.2, 0, z)
		p.y = gen.height(p.x, p.z) + 0.3
		var a = w.spawn_animal(sp, p)
		a.state = "idle"
		a._timer = 99.0
		a.rotation.y = -PI * 0.5
		i += 1
	await _wait(1.0)
	for a in w.animals:
		a.set_physics_process(false)
	await _wait(0.3)
	_player_at(Vector3(x, gen.height(x, z + 5.5) + 0.1, z + 5.5), 0.0, -0.2)
	await _wait(0.5)
	await _shot("animals_side")
	_player_at(Vector3(x - 6.0, gen.height(x - 6.0, z + 3.0) + 0.1, z + 3.0), -0.9, -0.15)
	await _wait(0.5)
	await _shot("animals_front")

func _run() -> void:
	if "--animals" in OS.get_cmdline_user_args():
		var m2 := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		m2._start_world({})
		await _wait(1.5)
		await _animals()
		get_tree().quit()
		return
	if "--vehicles" in OS.get_cmdline_user_args():
		var main1 := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		main1._start_world({})
		await _wait(1.5)
		await _vehicles()
		get_tree().quit()
		return
	if "--items" in OS.get_cmdline_user_args():
		var main0 := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		main0._start_world({})
		await _wait(1.0)
		Game.world.hud.close_modal()
		await _items_sheet()
		Game.player.pitch = -0.1
		await _viewmodels()
		get_tree().quit()
		return
	var main := get_tree().root.get_node("Main")
	Game.new_game(4242, "Normal")
	main._start_world({})
	await _wait(1.0)
	var w = Game.world
	var rv = Game.rv
	w.hud.close_modal()
	_log("start inventory: %s" % str(Game.inventory))
	Game.time_of_day = 9.5
	await _settle(Game.player.global_position)
	await _wait(2.0)
	await _shot("01_start")
	# RV exterior
	var side: Vector3 = rv.to_global(Vector3(7.5, 0, 4.5))
	_player_at(_ground(side.x, side.z), rv.rotation.y + deg_to_rad(55), -0.12)
	await _wait(0.5)
	await _shot("02_rv_exterior")
	# RV interior
	rv.do_action("door", Game.player)
	await _wait(0.3)
	Game.player.rotation.y = rv.rotation.y + PI
	Game.player.pitch = -0.2
	Game.player.head.rotation.x = -0.2
	rv.interior_lights = true
	rv._update_lights()
	await _wait(0.5)
	await _shot("03_rv_interior")
	Game.player.rotation.y = rv.rotation.y
	await _wait(0.3)
	await _shot("04_rv_interior_rear")
	rv.do_action("door", Game.player)
	await _wait(0.3)
	# Furniture on the RV + loose cargo
	Game.add_item("crate", 1, true)
	rv.attach_structure({"type": "crate", "pos": Game.arr(rv.to_global(Vector3(0.3, rv.FLOOR_Y, -1.0))), "rot": rv.global_rotation.y, "data": {}})
	rv.attach_structure({"type": "chair", "pos": Game.arr(rv.to_global(Vector3(0.0, rv.ROOF_Y + 0.18, -2.0))), "rot": rv.global_rotation.y, "data": {}})
	Game.spawn_item("canned_food", 2, rv.to_global(Vector3(0.4, rv.FLOOR_Y + 0.5, -0.4)))
	await _wait(2.0)
	_log("rv attached: %d, cargo nodes: %d" % [rv.attached.size(), rv.get_node("Cargo").get_child_count()])
	for k in rv.parts:
		rv.parts[k] = 100.0
	rv.fuel = 60.0
	rv.battery = 100.0
	# Driving test
	Game.player.enter_vehicle(rv, true)
	rv.set_camera(true)
	var p0: Vector3 = rv.global_position
	Input.action_press("move_forward", 1.0)
	await _wait(8.0)
	var spd: float = rv.speed_kmh()
	Input.action_release("move_forward")
	_log("cargo after drive: %d" % rv.get_node("Cargo").get_child_count())
	_log("drive: speed after 8s %.1f km/h, moved %.1f m, fuel %.1f, engine_on %s" % [spd, rv.global_position.distance_to(p0), rv.fuel, rv.engine_on])
	await _shot("05_driving_tp")
	Input.action_press("move_left", 1.0)
	Input.action_press("move_forward", 0.6)
	await _wait(2.0)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	_log("steer: rotation y %.2f" % rv.rotation.y)
	rv.set_camera(false)
	await _wait(0.4)
	await _shot("06_driving_fp")
	Input.action_press("jump")
	await _wait(3.0)
	Input.action_release("jump")
	_log("braked: speed %.1f km/h" % rv.speed_kmh())
	Game.player.exit_vehicle()
	await _wait(0.5)
	# Loot as physical items
	var lootb = null
	for n in get_tree().get_nodes_in_group("world_item"):
		pass
	var before_items := get_tree().get_nodes_in_group("world_item").size()
	var any_loot: Node = null
	for n in w.get_children():
		if n.name.begins_with("Chunk"):
			for d in n.get_children():
				if d.get_script() == load("res://scripts/loot.gd") and d.mode == "loot":
					any_loot = d
	if any_loot == null:
		for n in w.find_children("*", "StaticBody3D", true, false):
			if n.get_script() == load("res://scripts/loot.gd") and n.mode == "loot":
				any_loot = n
				break
	if any_loot:
		any_loot.interact(Game.player)
		await _wait(1.5)
		var spawned := get_tree().get_nodes_in_group("world_item").size() - before_items
		var picked := 0
		for it in get_tree().get_nodes_in_group("world_item"):
			if it.get_parent() == w:
				it.interact(Game.player)
				picked += 1
		_log("loot spawned %d physical items, picked up %d" % [spawned, picked])
	else:
		_log("no loot container loaded nearby")
	# Build a small house next to the road
	var base: Vector3 = Game.player.global_position + Game.player.global_transform.basis.z * -14.0
	var gx: float = floor(base.x / 3.0) * 3.0
	var gz: float = floor(base.z / 3.0) * 3.0
	var hmax := -INF
	var hmin := INF
	for ox in [0, 3, 6]:
		for oz in [0, 3, 6]:
			var h: float = w.gen.height(gx + ox, gz + oz)
			hmax = maxf(hmax, h)
			hmin = minf(hmin, h)
	var y := snappedf(hmax + 0.25, 0.25)
	var pieces := []
	for cx in [0, 1]:
		for cz in [0, 1]:
			pieces.append({"type": "foundation", "pos": [gx + cx * 3 + 1.5, y, gz + cz * 3 + 1.5], "rot": 0.0, "data": {"depth": y - hmin + 0.8}})
			pieces.append({"type": "roof_slope" if cz == 0 else "roof", "pos": [gx + cx * 3 + 1.5, y + 3.0, gz + cz * 3 + 1.5], "rot": 0.0, "data": {}})
	pieces.append({"type": "wall", "pos": [gx + 1.5, y, gz], "rot": 0.0, "data": {}})
	pieces.append({"type": "window", "pos": [gx + 4.5, y, gz], "rot": 0.0, "data": {}})
	pieces.append({"type": "doorway", "pos": [gx + 1.5, y, gz + 6], "rot": 0.0, "data": {"open": true}})
	pieces.append({"type": "window", "pos": [gx + 4.5, y, gz + 6], "rot": 0.0, "data": {}})
	pieces.append({"type": "wall", "pos": [gx, y, gz + 1.5], "rot": PI * 0.5, "data": {}})
	pieces.append({"type": "wall", "pos": [gx, y, gz + 4.5], "rot": PI * 0.5, "data": {}})
	pieces.append({"type": "window", "pos": [gx + 6, y, gz + 1.5], "rot": PI * 0.5, "data": {}})
	pieces.append({"type": "wall", "pos": [gx + 6, y, gz + 4.5], "rot": PI * 0.5, "data": {}})
	pieces.append({"type": "campfire", "pos": Game.arr(_ground(gx + 3, gz + 10)), "rot": 0.0, "data": {"fuel": 600.0}})
	pieces.append({"type": "tent", "pos": Game.arr(_ground(gx + 8, gz + 11)), "rot": 0.6, "data": {}})
	pieces.append({"type": "planter", "pos": Game.arr(_ground(gx - 2.5, gz + 9)), "rot": 0.0, "data": {"crop": "tomato", "growth": 1.0, "water": 1.0}})
	pieces.append({"type": "crate", "pos": Game.arr(_ground(gx - 1, gz + 11.5)), "rot": 0.3, "data": {}})
	pieces.append({"type": "lantern", "pos": Game.arr(_ground(gx + 0.5, gz + 12.5)), "rot": 0.0, "data": {}})
	pieces.append({"type": "bed", "pos": [gx + 1.5, y, gz + 2.0], "rot": 0.0, "data": {}})
	pieces.append({"type": "workbench", "pos": [gx + 4.5, y, gz + 1.0], "rot": 0.0, "data": {}})
	for rec in pieces:
		Net.place_structure(Game.new_struct_id(), rec)
	_log("placed %d structures" % pieces.size())
	_player_at(_ground(gx + 3, gz + 19), 0.0, -0.12)
	Game.time_of_day = 17.8
	await _wait(1.0)
	await _shot("07_house_camp_evening")
	Game.time_of_day = 22.5
	await _wait(1.0)
	await _shot("08_camp_night")
	_player_at(Vector3(gx + 3, y + 0.2, gz + 4.5), PI, -0.05)
	await _wait(0.6)
	await _shot("09_house_inside_night")
	# Wildlife lineup
	Game.time_of_day = 10.0
	var pl = Game.player
	var origin: Vector3 = pl.global_position + Vector3(0, 0, -40)
	_player_at(_ground(origin.x, origin.z + 12), 0.0, -0.1)
	await _settle(origin)
	var i := 0
	for sp in ["deer", "boar", "wolf", "bear", "rabbit", "turkey", "fox"]:
		var p := _ground(origin.x - 9 + i * 3.0, origin.z)
		var a = w.spawn_animal(sp, p + Vector3(0, 0.3, 0))
		a.state = "idle"
		a._timer = 60.0
		a.rotation.y = PI * 0.5
		i += 1
	await _wait(1.2)
	await _shot("10_wildlife")
	# hunting check
	Game.add_item("rifle", 1)
	Game.add_item("ammo", 5)
	var deer = w.animals[w.animals.size() - 7]
	deer.take_damage(500, pl.global_position)
	_log("deer state after shot: %s" % deer.state)
	var before := Game.count("raw_meat")
	deer.interact(pl)
	_log("butchered: raw_meat %d -> %d, hide %d" % [before, Game.count("raw_meat"), Game.count("hide")])
	# Find POIs and biomes along the road
	var gen = w.gen
	var found := {}
	for row in range(2, 400):
		var poi: Dictionary = gen.poi_for_row(row)
		if poi.is_empty() or found.has(poi["type"]):
			continue
		found[poi["type"]] = poi
		if found.size() >= 9:
			break
	_log("poi types found: %s" % str(found.keys()))
	for t in ["gas_station", "house", "farm", "cabin", "hamlet", "truck_stop"]:
		if not found.has(t):
			continue
		var poi: Dictionary = found[t]
		var pp: Vector3 = poi["pos"]
		var road := Vector3(gen.road_x(pp.z), 0, pp.z)
		var dir := (pp - road).normalized()
		var cam: Vector3 = road - dir * 6.0 + gen.road_dir(pp.z) * 10.0
		_player_at(_ground(cam.x, cam.z), atan2(-(pp - cam).x, -(pp - cam).z), -0.08)
		await _settle(cam)
		await _wait(1.0)
		await _shot("11_poi_" + t)
		if t in ["house", "cabin"]:
			var bs := Basis(Vector3.UP, poi["yaw"])
			var inside: Vector3 = pp + bs * Vector3(-0.5, 0, 1.6)
			Game.player.teleport(Vector3(inside.x, gen.height(pp.x, pp.z) + 0.75, inside.z))
			Game.player.rotation.y = poi["yaw"] + 0.5
			Game.player.pitch = -0.15
			Game.player.head.rotation.x = -0.15
			Game.player.flashlight.visible = false
			await _wait(0.8)
			await _shot("11_poi_" + t + "_inside")
			Game.player.rotation.y = poi["yaw"] - 2.2
			await _wait(0.4)
			await _shot("11_poi_" + t + "_inside2")
	for target in [["desert", 0], ["tundra", 3], ["forest", 2], ["grassland", 1]]:
		var best := Vector3.ZERO
		var ok := false
		for k in range(1, 400):
			var z := -k * 160.0
			var x: float = gen.road_x(z)
			var bw: Vector4 = gen.biome_weights(x, z)
			if bw[target[1]] > 0.9:
				best = Vector3(x + 2.0, 0, z)
				ok = true
				break
		if ok:
			_player_at(_ground(best.x, best.z), 0.0, -0.05)
			await _settle(best)
			await _wait(1.5)
			await _shot("12_biome_" + target[0])
		else:
			_log("no %s found" % target[0])
	# Rain
	Game.weather = "rain"
	w._overcast = 0.9
	w._wet = 1.0
	await _wait(1.0)
	await _shot("13_rain")
	Game.weather = "clear"
	# Menus
	w.hud.open_inventory()
	await _wait(0.4)
	await _shot("14_inventory")
	w.hud.open_rv_menu(rv)
	await _wait(0.4)
	await _shot("15_rv_workshop")
	w.hud.open_build_menu()
	await _wait(0.4)
	await _shot("16_build_menu")
	w.hud.close_modal()
	# save/load round trip
	var ok_save := Game.save_game()
	var data := Game.load_game_data()
	_log("save ok %s, structures in save %d, inventory items %d" % [ok_save, data.get("structures", {}).size(), data.get("inventory", {}).size()])
	var f := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	get_tree().quit()
