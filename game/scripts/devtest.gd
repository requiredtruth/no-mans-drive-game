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
	if DisplayServer.get_name() == "headless":
		_log("shot %s (skipped, headless)" % name)
		return
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
		Game.slots[0] = {"id": id, "n": 1}
		Game.select_slot(0)
		Game._changed()
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

func _find_loot(mode: String) -> Node:
	for n in Game.world.find_children("*", "StaticBody3D", true, false):
		if n.get_script() == load("res://scripts/loot.gd") and n.mode == mode and not Game.removed.has(n.key):
			return n
	return null

func _look_at_point(p: Vector3) -> void:
	var pl = Game.player
	var eye: Vector3 = pl.global_position + Vector3(0, pl.head.position.y, 0)
	var d := p - eye
	pl.rotation.y = atan2(-d.x, -d.z)
	pl.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	pl.head.rotation.x = pl.pitch

## Physical carrying, exact placement, glue-while-driving, part swaps, boxes, cab interior.
func _hands() -> void:
	var w = Game.world
	var rv = Game.rv
	var pl = Game.player
	w.hud.close_modal()
	Game.time_of_day = 10.5
	await _settle(pl.global_position)
	await _wait(1.5)
	_log("start slots %s worn %s" % [str(Game.slots), str(Game.worn)])
	var cargo: Node = rv.get_node("Cargo")
	_log("starter items glued in RV: %d" % cargo.get_child_count())
	_van_door(pl)
	rv.interior_lights = true
	rv._update_lights()
	await _wait(0.4)
	pl.rotation.y = rv.rotation.y + PI * 0.75
	pl.pitch = -0.35
	pl.head.rotation.x = -0.35
	await _wait(0.5)
	await _shot("h01_rv_interior_galley")
	pl.rotation.y = rv.rotation.y
	pl.pitch = -0.25
	pl.head.rotation.x = -0.25
	await _wait(0.4)
	await _shot("h02_rv_interior_rear")
	pl.rotation.y = rv.rotation.y + PI
	pl.pitch = -0.1
	pl.head.rotation.x = -0.1
	await _wait(0.4)
	await _shot("h03_rv_interior_cab")
	# pick up the canned food off the dinette table
	var can: Node = null
	for it in cargo.get_children():
		if it.is_in_group("world_item") and it.id == "canned_food":
			can = it
	_look_at_point(can.global_position)
	await _wait(0.3)
	pl._update_prompt()
	_log("looking at: %s / prompt '%s'" % [str(pl.look_target), pl.prompt])
	await _shot("h04_highlight_item")
	pl._interact()
	await _wait(0.2)
	_log("after pickup slots %s" % str(Game.slots))
	await _shot("h05_holding_can")
	var hb = w.hud.hotbar_box
	_log("hotbar rect %s children %d visible %s" % [str(hb.get_global_rect()), hb.get_child_count(), hb.is_visible_in_tree()])
	# place it on the counter with the preview
	_look_at_point(rv.to_global(Vector3(-rv.W * 0.5 + 0.4, rv.FLOOR_Y + 0.95, 0.0)))
	await _wait(0.3)
	pl._update_placement()
	_log("placement valid %s host %s" % [pl._place_valid, str(pl._place_host)])
	await _shot("h06_place_preview")
	pl.place_held()
	await _wait(0.2)
	var placed: Node = null
	for it in cargo.get_children():
		if it.is_in_group("world_item") and it.id == "canned_food":
			placed = it
	var lp0: Vector3 = placed.position if placed else Vector3.ZERO
	_log("placed on counter: %s local %s" % [placed != null, str(lp0)])
	# drive and check that items stay glued exactly
	_van_door(pl)
	await _wait(0.2)
	for k in rv.parts:
		rv.parts[k] = 100.0
	rv.battery = 100.0
	rv.fuel = 60.0
	pl.enter_vehicle(rv, true)
	Input.action_press("move_forward", 1.0)
	await _wait(6.0)
	Input.action_press("move_left", 1.0)
	await _wait(2.0)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	Input.action_press("jump")
	await _wait(2.5)
	Input.action_release("jump")
	_log("after drive: can local %s (moved %.3f m inside RV), glued items %d" % [str(placed.position), placed.position.distance_to(lp0), cargo.get_child_count()])
	pl.exit_vehicle()
	await _wait(0.6)
	# swap the battery by hand
	var bat_part: Node = null
	for ch in rv.get_children():
		if ch.get_script() == load("res://scripts/rv_part.gd") and ch.action == "battery":
			bat_part = ch
	var bp: Vector3 = bat_part.global_position + rv.global_transform.basis.x * -1.6
	_player_at(Vector3(bp.x, w.gen.height(bp.x, bp.z) + 0.1, bp.z), 0.0)
	await _wait(0.2)
	_look_at_point(bat_part.global_position)
	await _wait(0.3)
	pl._update_prompt()
	_log("battery prompt: %s" % pl.prompt)
	await _shot("h07_battery_tray")
	Game.select_slot(1)
	rv.Mounts.pull(rv, "battery")
	_log("pulled battery: missing %s, slots %s" % [str(rv.missing), str(Game.slots)])
	await _wait(0.3)
	await _shot("h08_battery_removed")
	rv.try_start_engine()
	Game.slots[1] = {"id": "car_battery", "n": 1}
	Game._changed()
	rv.do_action("battery", pl)
	_log("fitted battery: missing %s parts %s" % [str(rv.missing), str(rv.parts)])
	# tire swap (toolkit lies in the RV within reach? place one at our feet)
	Game.place_item("toolkit", 1, Transform3D(Basis.IDENTITY, _ground(pl.global_position.x + 0.5, pl.global_position.z)))
	Game.slots[1] = {"id": "", "n": 0}
	Game._changed()
	rv.parts["tires"] = 40.0
	rv.Mounts.pull(rv, "wheel0")
	_log("pulled tire: missing %s tires %.1f slots %s" % [str(rv.missing), rv.parts["tires"], str(Game.slots)])
	var wpos: Vector3 = rv.wheels[0].global_position
	var cam: Vector3 = wpos + rv.global_transform.basis.x * -2.2 + rv.global_transform.basis.z * 1.0
	_player_at(Vector3(cam.x, w.gen.height(cam.x, cam.z) + 0.1, cam.z), 0.0)
	_look_at_point(wpos)
	await _wait(0.4)
	await _shot("h09_wheel_removed")
	Game.slots[1] = {"id": "tire", "n": 1}
	Game._changed()
	rv.do_action("wheel0", pl)
	_log("fitted tire: missing %s tires %.1f" % [str(rv.missing), rv.parts["tires"]])
	# hands are limited: try picking up with full hands
	Game.slots = [{"id": "knife", "n": 1}, {"id": "rope", "n": 1}]
	Game._changed()
	var stone = Game.spawn_item("stone", 1, pl.global_position + Vector3(0, 0.5, 0))
	await _wait(0.5)
	var ok: bool = Game.pick_up(stone)
	_log("pick up with full hands -> %s (expected false)" % ok)
	Game.worn["backpack"] = true
	Game._fit_slots()
	ok = Game.pick_up(stone)
	_log("with backpack: slots %d, pick up -> %s" % [Game.slots.size(), ok])
	# crafting uses items lying within reach
	Game.drop_pile("fiber", 3, pl.global_position + Vector3(0.5, 0.4, 0))
	await _wait(0.6)
	_log("fiber in reach %d, can craft rope: %s" % [Game.count("fiber"), Game.has_cost({"fiber": 3})])
	Game.pay({"fiber": 3})
	_log("after crafting: fiber in reach %d" % Game.count("fiber"))
	# crate carries its contents
	var cpos := _ground(pl.global_position.x + 2.0, pl.global_position.z + 1.0)
	Net.place_structure(Game.new_struct_id(), {"type": "crate", "pos": Game.arr(cpos), "rot": 0.0, "data": {}})
	await _wait(0.3)
	Game.place_item("canned_food", 1, Transform3D(Basis.IDENTITY, cpos + Vector3(-0.2, 0.12, 0)))
	Game.place_item("bandage", 2, Transform3D(Basis.IDENTITY, cpos + Vector3(0.2, 0.12, 0)))
	var crate: Node = null
	for st in get_tree().get_nodes_in_group("placeable"):
		if st.type == "crate" and st.global_position.distance_to(cpos) < 0.5:
			crate = st
	_player_at(cpos + Vector3(-1.4, 0.1, 1.4), 0.0)
	_look_at_point(cpos + Vector3(0, 0.3, 0))
	await _wait(0.4)
	await _shot("h10_crate_with_items")
	Game.slots = [{"id": "", "n": 0}, {"id": "", "n": 0}, {"id": "", "n": 0}, {"id": "", "n": 0}]
	Game.select_slot(0)
	pl.look_target = crate
	pl.place_or_grab()
	_log("carry crate: slots %s" % str(Game.slots))
	pl.builder.stop()
	Game.slots = [{"id": "", "n": 0}, {"id": "", "n": 0}, {"id": "", "n": 0}, {"id": "", "n": 0}]
	Game._changed()
	# boxes at a location
	var gen = w.gen
	for row in range(2, 400):
		var poi: Dictionary = gen.poi_for_row(row)
		if not poi.is_empty() and poi["type"] == "gas_station":
			var pp: Vector3 = poi["pos"]
			_player_at(_ground(pp.x, pp.z + 10.0), 0.0)
			await _settle(pp)
			await _wait(1.0)
			break
	var box := _find_loot("box")
	if box:
		var bxp: Vector3 = box.global_position
		var dir: Vector3 = box.get_parent().global_transform.basis.z
		_player_at(bxp + dir * 1.2 + Vector3(0, 0.05, 0), 0.0)
		_look_at_point(bxp + Vector3(0, 0.2, 0))
		await _wait(0.4)
		pl._update_prompt()
		_log("box prompt: %s" % pl.prompt)
		await _shot("h11_box_closed")
		box.interact(pl)
		await _wait(0.8)
		await _shot("h12_box_open_items")
		for it in get_tree().get_nodes_in_group("world_item"):
			if it.global_position.distance_to(bxp) < 3.0:
				_log("  near box: %s x%d at %s (box at %s)" % [it.id, it.amount, str(it.global_position), str(bxp)])
		for n in Game.world.find_children("*", "StaticBody3D", true, false):
			if n.get_script() == load("res://scripts/loot.gd") and n.global_position.distance_to(bxp) < 8.0:
				_log("  loot nearby: %s mode %s at %s" % [n.label, n.mode, str(n.global_position)])
	else:
		_log("no cardboard box found")
	# truck cab interior
	var z: float = pl.global_position.z - 20.0
	var x: float = gen.road_x(z) + 3.0
	var truck = w.spawn_vehicle("cab_test", "pickup", Vector3(x, gen.height(x, z) + 1.0, z), Vector3(0, 0.3, 0), {})
	await _wait(1.5)
	pl.enter_vehicle(truck, true)
	truck.set_camera(false)
	truck.fp_yaw = 0.0
	truck.look(Vector2(0.0, 0.0))
	await _wait(0.5)
	await _shot("h13_pickup_cab_fp")
	truck.look(Vector2(-1.2, 0.0))
	await _wait(0.3)
	await _shot("h14_pickup_cab_side")
	pl.exit_vehicle()
	for kind in ["sedan", "box_truck", "offroader"]:
		var v = w.spawn_vehicle("cab_" + kind, kind, Vector3(x + 8.0, gen.height(x + 8.0, z) + 1.0, z), Vector3(0, 0.3, 0), {})
		await _wait(1.2)
		pl.enter_vehicle(v, true)
		v.set_camera(false)
		await _wait(0.4)
		await _shot("h15_cab_" + kind)
		pl.exit_vehicle()
		v.queue_free()
		await _wait(0.2)
	# HUD screens
	w.hud.open_book()
	await _wait(0.4)
	await _shot("h16_notebook")
	w.hud.close_modal()
	var ok_save := Game.save_game()
	var data := Game.load_game_data()
	_log("save ok %s, slots %s, worn %s, loose items %d" % [ok_save, str(data.get("slots")), str(data.get("worn")), data.get("items", []).size()])

func _find_item(id: String) -> Node:
	var best: Node = null
	for it in get_tree().get_nodes_in_group("world_item"):
		if is_instance_valid(it) and not it.is_queued_for_deletion() and it.id == id:
			if best == null or it.global_position.distance_to(Game.player.global_position) < best.global_position.distance_to(Game.player.global_position):
				best = it
	return best

## Walk to an item lying in the world and pick it up for real.
func _fetch(id: String) -> bool:
	var it := _find_item(id)
	if it == null:
		_log("FAIL: no %s lying around" % id)
		return false
	var p: Vector3 = it.global_position
	_player_at(_ground(p.x + 0.9, p.z), 0.0)
	await _wait(0.1)
	_look_at_point(it.global_position)
	var ok: bool = Game.pick_up(it)
	await _wait(0.1)
	return ok

func _mount_node(slot: String) -> Node:
	return Game.rv._mounts.get(slot)

func _rv_part(action: String) -> Node:
	for ch in Game.rv.get_children():
		if ch.get_script() == load("res://scripts/rv_part.gd") and ch.action == action:
			return ch
	return null

func _aim_prompt(target: Vector3) -> String:
	_look_at_point(target)
	await _wait(0.15)
	Game.player._update_prompt()
	var lt = Game.player.look_target
	if lt == null:
		_log("  (aim hit: %s)" % str(Game.player.ray.get_collider()))
	return Game.player.prompt

## Test shortcut for the older tours: hop in or out of the van through the doorway.
func _van_door(pl: Node) -> void:
	var rv = Game.rv
	var zc: float = (rv.DOOR_Z0 + rv.DOOR_Z1) * 0.5
	if rv.is_inside(pl.global_position):
		pl.teleport(rv.to_global(Vector3(rv.W * 0.5 + 1.4, 0.2, zc)))
	else:
		pl.teleport(rv.to_global(Vector3(0.05, rv.FLOOR_Y + 0.1, zc - 0.1)))

## Hold a movement key for a while, like a player would.
func _walk(action: String, sec: float) -> void:
	Input.action_press(action)
	await _wait(sec)
	Input.action_release(action)
	await _wait(0.2)

## 1.5: the van is a real vehicle you walk into, and the camper too.
func _walkin() -> void:
	var w = Game.world
	var rv = Game.rv
	var pl = Game.player
	var gen = w.gen
	w.hud.close_modal()
	Game.time_of_day = 10.0
	Game.god_mode = true
	await _settle(pl.global_position)
	await _wait(2.0)
	var zc: float = (rv.DOOR_Z0 + rv.DOOR_Z1) * 0.5
	var below: Vector3 = rv.to_global(Vector3(rv.W * 0.5 + 1.0, 0, zc))
	var gl: Vector3 = rv.to_local(Vector3(below.x, gen.height(below.x, below.z), below.z))
	_log("ground under the doorway in van space: y=%.2f (floor %.2f)" % [gl.y, rv.FLOOR_Y])
	for v in [["w01_van_side_door", Vector3(7.0, 0, 3.5), Vector3(0, 1.6, 0.5)], ["w02_van_front34", Vector3(5.5, 0, 9.5), Vector3(0, 1.4, 2.0)],
			["w03_van_rear34", Vector3(-5.0, 0, -8.5), Vector3(0, 1.6, -2.0)], ["w04_van_driver_side", Vector3(-7.5, 0, 1.0), Vector3(0, 1.6, 0.0)],
			["w05_doorway_close", Vector3(3.2, 0, 1.0), Vector3(0, 1.7, 0.6)]]:
		var c: Vector3 = rv.to_global(v[1])
		_player_at(_ground(c.x, c.z), 0.0)
		_look_at_point(rv.to_global(v[2]))
		await _wait(0.5)
		await _shot(v[0])
	# walk in through the open doorway: no prompts, no teleport
	var start: Vector3 = rv.to_global(Vector3(rv.W * 0.5 + 2.6, 0, zc))
	_player_at(_ground(start.x, start.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 1.6, zc)))
	pl.pitch = -0.1
	pl.head.rotation.x = -0.1
	await _wait(0.3)
	Game.player._update_prompt()
	_log("prompt facing the empty doorway: '%s'" % Game.player.prompt)
	Input.action_press("move_forward")
	for k in range(11):
		await _wait(0.2)
		var lp: Vector3 = rv.to_local(pl.global_position)
		_log("  walk t=%.1f van-space %.2f %.2f %.2f floor=%s vel=%s" % [k * 0.2, lp.x, lp.y, lp.z, pl.is_on_floor(), str(pl.velocity)])
	Input.action_release("move_forward")
	await _wait(0.2)
	_log("walked in through the doorway: inside=%s y=%.2f" % [rv.is_inside(pl.global_position), rv.to_local(pl.global_position).y])
	await _shot("w06_walked_in")
	pl.rotation.y = rv.rotation.y
	await _wait(0.3)
	await _shot("w07_inside_rear")
	pl.rotation.y = rv.rotation.y + PI
	await _wait(0.3)
	await _shot("w08_inside_cab")
	_look_at_point(rv.to_global(Vector3(rv.W * 0.5 + 3.0, 1.2, zc)))
	await _wait(0.3)
	await _shot("w09_looking_out_doorway")
	await _walk("move_forward", 2.2)
	_log("walked out again: inside=%s" % rv.is_inside(pl.global_position))
	# fully fitted out, with the sliding door
	rv.modules = rv._all_modules()
	rv.missing = {}
	rv.paint = 3
	rv._apply_visuals()
	await _wait(0.5)
	var c2: Vector3 = rv.to_global(Vector3(7.0, 0, 3.5))
	_player_at(_ground(c2.x, c2.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 1.6, 0.5)))
	await _wait(0.5)
	await _shot("w10_fitted_door_closed")
	var c3: Vector3 = rv.to_global(Vector3(5.5, 0, 9.5))
	_player_at(_ground(c3.x, c3.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 1.4, 2.0)))
	await _wait(0.4)
	await _shot("w11_fitted_front34")
	_player_at(_ground(start.x, start.z), 0.0)
	var pr: String = await _aim_prompt(rv.to_global(Vector3(rv.W * 0.5, 1.9, zc)))
	_log("prompt at the closed door: '%s'" % pr)
	await _walk("move_forward", 1.2)
	_log("walking into the closed door: inside=%s" % rv.is_inside(pl.global_position))
	_player_at(_ground(start.x, start.z), 0.0)
	pr = await _aim_prompt(rv.to_global(Vector3(rv.W * 0.5, 1.9, zc)))
	var dp = pl.look_target
	if dp:
		dp.interact(pl)
	await _wait(1.0)
	_log("door open: %s, shape disabled: %s" % [rv.door_open, rv._door_shape.disabled])
	await _shot("w12_door_slid_open")
	_look_at_point(rv.to_global(Vector3(0, 1.6, zc)))
	pl.pitch = -0.1
	await _walk("move_forward", 2.2)
	_log("walked in through the open door: inside=%s" % rv.is_inside(pl.global_position))
	pl.rotation.y = rv.rotation.y
	rv.interior_lights = true
	rv._update_lights()
	await _wait(0.3)
	await _shot("w13_fitted_inside_rear")
	pl.rotation.y = rv.rotation.y + PI
	await _wait(0.3)
	await _shot("w14_fitted_inside_cab")
	pr = await _aim_prompt(rv.to_global(Vector3(rv.W * 0.5 - 0.12, rv.FLOOR_Y + 1.25, rv.DOOR_Z1 + 0.07)))
	_log("prompt at the inside grab handle: '%s'" % pr)
	# the camper trailer: walk in through its door too
	var tz: float = rv.global_position.z - 25.0
	var tx: float = gen.road_x(tz) + 2.0
	var cam = w.spawn_vehicle("walk_camper", "camper", Vector3(tx, gen.height(tx, tz) + 1.0, tz), Vector3(0, PI * 0.5, 0), {})
	await _wait(2.5)
	var cz: float = cam.DOOR_Z
	var cs: Vector3 = cam.to_global(Vector3(cam.spec["w"] * 0.5 + 4.0, 0, cz))
	_player_at(_ground(cs.x, cs.z), 0.0)
	_look_at_point(cam.to_global(Vector3(0, 1.4, cz)))
	await _wait(0.4)
	await _shot("w15_camper_outside")
	var cs2: Vector3 = cam.to_global(Vector3(cam.spec["w"] * 0.5 + 1.6, 0, cz))
	_player_at(_ground(cs2.x, cs2.z), 0.0)
	pr = await _aim_prompt(cam.to_global(Vector3(cam.spec["w"] * 0.5, 1.5, cz)))
	_log("camper door prompt: '%s'" % pr)
	if pl.look_target:
		pl.look_target.interact(pl)
	await _wait(0.8)
	_look_at_point(cam.to_global(Vector3(0, 1.3, cz)))
	pl.pitch = -0.1
	Input.action_press("move_forward")
	for k in range(10):
		await _wait(0.2)
		var cp: Vector3 = cam.to_local(pl.global_position)
		_log("  camper walk %.2f %.2f %.2f floor=%s" % [cp.x, cp.y, cp.z, pl.is_on_floor()])
	Input.action_release("move_forward")
	await _wait(0.2)
	_log("walked into the camper: inside=%s, trailer tilt %.1f deg" % [cam.is_inside(pl.global_position), rad_to_deg(cam.global_transform.basis.y.angle_to(Vector3.UP))])
	pl.rotation.y = cam.global_rotation.y
	await _wait(0.3)
	await _shot("w16_camper_inside")

## 1.4: start with a stripped van and put it together by hand.
func _assembly() -> void:
	var w = Game.world
	var rv = Game.rv
	var pl = Game.player
	w.hud.close_modal()
	Game.time_of_day = 10.0
	Game.god_mode = true
	Game.notified.connect(func(t: String) -> void: _log("  note: " + t))
	await _settle(pl.global_position)
	await _wait(1.5)
	_log("start modules %s missing %s" % [str(rv.modules), str(rv.missing)])
	_log("needs to drive: %s" % str(rv.missing_for_drive()))
	var lot := 0
	for it in get_tree().get_nodes_in_group("world_item"):
		if it.global_position.distance_to(rv.global_position) < 12.0:
			lot += 1
	_log("items lying on the starter lot: %d" % lot)
	var side: Vector3 = rv.to_global(Vector3(10.0, 0, 6.0))
	_player_at(_ground(side.x, side.z), 0.0)
	_look_at_point(rv.to_global(Vector3(2.0, 1.0, 0.0)))
	await _wait(0.6)
	await _shot("a01_stripped_van_lot")
	var front: Vector3 = rv.to_global(Vector3(3.5, 0, 8.5))
	_player_at(_ground(front.x, front.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 1.4, 3.0)))
	await _wait(0.4)
	await _shot("a02_stripped_van_front")
	_van_door(pl)
	await _wait(0.3)
	pl.rotation.y = rv.rotation.y + PI
	pl.pitch = -0.15
	pl.head.rotation.x = -0.15
	await _wait(0.4)
	await _shot("a03_bare_interior_cab")
	pl.rotation.y = rv.rotation.y
	await _wait(0.3)
	await _shot("a04_bare_interior_rear")
	_van_door(pl)
	await _wait(0.2)
	# put the knife down so both hands are free, carry the toolkit to the van
	pl._place_valid = true
	pl._place_xf = Transform3D(Basis.IDENTITY, _ground(pl.global_position.x + 0.5, pl.global_position.z) + Vector3(0, 0.02, 0))
	pl._place_host = null
	pl.place_held()
	await _fetch("toolkit")
	var hood: Vector3 = rv.to_global(Vector3(0.6, 0, 6.2))
	_player_at(_ground(hood.x, hood.z), 0.0)
	pl._place_xf = Transform3D(Basis.IDENTITY, _ground(hood.x + 0.3, hood.z))
	pl._place_valid = true
	pl.place_held()
	_log("toolkit set down at the hood: count %d" % Game.count("toolkit"))
	# engine
	await _fetch("engine_block")
	_player_at(_ground(hood.x, hood.z), 0.0)
	var pr: String = await _aim_prompt(rv.to_global(Vector3(0, 1.68, rv.FRONT_Z + 0.85)))
	_log("hood prompt holding engine: '%s'" % pr)
	rv.do_action("hood", pl)
	_log("engine fitted: %s (engine %d%%)" % [rv.modules.has("engine"), int(rv.parts["engine"])])
	# battery
	await _fetch("car_battery")
	var bat := _rv_part("battery")
	var bp: Vector3 = bat.global_position + rv.global_transform.basis.x * -1.4
	_player_at(_ground(bp.x, bp.z), 0.0)
	rv.do_action("battery", pl)
	_log("battery fitted: missing %s battery %d" % [str(rv.missing), int(rv.battery)])
	# carry the toolkit along to the wheels
	await _fetch("toolkit")
	Game.select_slot(0)
	for i in range(4):
		if Game.slots[0]["id"] != "" and Game.slots[1]["id"] != "":
			pass
		await _fetch("tire")
		var wp: Vector3 = rv.wheels[i].global_position
		var off: Vector3 = rv.global_transform.basis.x * (1.3 if i % 2 == 1 else -1.3)
		_player_at(_ground(wp.x + off.x, wp.z + off.z), 0.0)
		for k in range(Game.slots.size()):
			if Game.slots[k]["id"] == "tire":
				Game.select_slot(k)
		pr = await _aim_prompt(wp)
		if i == 0:
			_log("wheel prompt: '%s'" % pr)
		rv.do_action("wheel%d" % i, pl)
	_log("after tires: missing %s tires %d%%" % [str(rv.missing), int(rv.parts["tires"])])
	# set the toolkit down by the side door for the steering wheel and door
	var dpos: Vector3 = rv.to_global(Vector3(rv.W * 0.5 + 1.2, 0, 1.0))
	_player_at(_ground(dpos.x, dpos.z), 0.0)
	for k in range(Game.slots.size()):
		if Game.slots[k]["id"] == "toolkit":
			Game.select_slot(k)
	pl._place_xf = Transform3D(Basis.IDENTITY, _ground(dpos.x, dpos.z))
	pl._place_valid = true
	pl.place_held()
	await _fetch("van_door")
	_player_at(_ground(dpos.x, dpos.z), 0.0)
	pr = await _aim_prompt(rv.to_global(Vector3(rv.W * 0.5 + 0.12, rv.FLOOR_Y + 1.0, 1.0)))
	_log("door prompt holding door: '%s'" % pr)
	rv.install_module("door")
	_log("door hung: %s" % rv.modules.has("door"))
	# seat: inside, ghost outline shows where it goes
	await _fetch("car_seat")
	_player_at(_ground(dpos.x, dpos.z), 0.0)
	_van_door(pl)
	await _wait(0.3)
	pl.rotation.y = rv.rotation.y + PI
	pl.pitch = -0.3
	pl.head.rotation.x = -0.3
	await _wait(0.3)
	_log("ghosts visible: %s" % str(rv._ghosts.keys()))
	await _shot("a05_seat_ghost_outline")
	pr = await _aim_prompt(_mount_node("seat_driver").global_position)
	_log("seat mount prompt: '%s'" % pr)
	if pl.look_target:
		pl._interact()
	_log("driver seat fitted: %s" % rv.modules.has("seat_driver"))
	# steering wheel needs a toolkit within reach: bring it in
	_van_door(pl)
	await _wait(0.2)
	await _fetch("steering_wheel")
	await _fetch("toolkit")
	_van_door(pl)
	await _wait(0.2)
	for k in range(Game.slots.size()):
		if Game.slots[k]["id"] == "steering_wheel":
			Game.select_slot(k)
	rv.install_module("steering")
	_log("steering fitted: %s" % rv.modules.has("steering"))
	# headlight
	await _fetch("headlight")
	rv.install_module("headlight_l")
	_log("needs to drive now: %s" % str(rv.missing_for_drive()))
	# fuel
	for k in range(Game.slots.size()):
		if Game.slots[k]["id"] != "toolkit" and Game.slots[k]["id"] != "":
			Game.slots[k] = {"id": "", "n": 0}
	await _fetch("fuel_can")
	rv.do_action("fuel", pl)
	_log("fuel %d, holding %s" % [int(rv.fuel), str(Game.slots)])
	# drive away
	rv.do_action("drive", pl)
	await _wait(0.3)
	_log("driving %s" % pl.driving)
	rv.try_start_engine()
	if not rv.engine_on:
		rv.try_start_engine()
	if not rv.engine_on:
		rv.try_start_engine()
	_log("engine on %s" % rv.engine_on)
	var z0: Vector3 = rv.global_position
	Input.action_press("move_forward", 1.0)
	await _wait(5.0)
	Input.action_release("move_forward")
	Input.action_press("jump")
	await _wait(2.0)
	Input.action_release("jump")
	_log("drove %.1f m, speed now %.1f" % [rv.global_position.distance_to(z0), rv.speed_kmh()])
	await _shot("a06_driving_assembled")
	pl.exit_vehicle()
	await _wait(0.5)
	# workbench: bolts, then a kitchen counter
	var bench: Node = null
	for st in get_tree().get_nodes_in_group("structure"):
		if st.type == "workbench":
			bench = st
	_log("workbench on the lot: %s" % (bench != null))
	var bfront: Vector3 = bench.to_global(Vector3(0, 0, 1.6))
	_player_at(_ground(bfront.x, bfront.z), 0.0)
	Game.place_item("scrap", 2, bench.global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.4, 0.95, 0)))
	await _wait(0.2)
	pr = await _aim_prompt(bench.to_global(Vector3(0, 0.95, 0)))
	_log("bench prompt with scrap: '%s'" % pr)
	bench.assemble()
	await _wait(0.2)
	var bolts := 0
	for it in bench.bench_items():
		if it.id == "bolts":
			bolts += it.amount
	_log("bolts on the bench after assembling: %d" % bolts)
	Game.place_item("wood", 3, bench.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.5, 0.95, 0.1)))
	Game.place_item("wood", 1, bench.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.8, 0.95, -0.1)))
	await _wait(0.2)
	pr = await _aim_prompt(bench.to_global(Vector3(0, 0.95, 0)))
	_log("bench prompt with wood + bolts: '%s'" % pr)
	var m: Array = bench.bench_matches()
	for i in range(m.size()):
		if m[0]["out"] != "kitchen_unit":
			bench.cycle_recipe()
	var names := []
	for r in m:
		names.append(r["out"])
	_log("bench matches: %s" % str(names))
	while bench.bench_matches()[wrapi(bench._choice, 0, bench.bench_matches().size())]["out"] != "kitchen_unit":
		bench.cycle_recipe()
	bench.assemble()
	await _wait(0.3)
	_log("kitchen counter made: %s" % (_find_item("kitchen_unit") != null))
	_look_at_point(bench.to_global(Vector3(0, 0.6, 0.8)))
	await _wait(0.3)
	await _shot("a07_workbench_output")
	# fit counter + stove, cook on the stove
	Game.slots = [{"id": "", "n": 0}, {"id": "", "n": 0}]
	Game._changed()
	await _fetch("kitchen_unit")
	_van_door(pl)
	await _wait(0.2)
	for k in range(Game.slots.size()):
		if Game.slots[k]["id"] == "kitchen_unit":
			Game.select_slot(k)
	rv.install_module("kitchen")
	Game.slots[Game.selected_slot] = {"id": "stove_unit", "n": 1}
	Game._changed()
	await _wait(0.2)
	_log("stove ghost: %s" % str(rv._ghosts.get("stove") != null and rv._ghosts["stove"].visible))
	rv.install_module("stove")
	_log("kitchen %s stove %s" % [rv.modules.has("kitchen"), rv.modules.has("stove")])
	Game.slots[Game.selected_slot] = {"id": "raw_meat", "n": 1}
	Game._changed()
	rv.do_action("stove", pl)
	rv.do_action("stove", pl)
	_log("stove on %s, heat spots %d" % [rv.stove_on, rv.heat_spots().size()])
	pl.rotation.y = rv.rotation.y + PI * 0.6
	pl.pitch = -0.6
	pl.head.rotation.x = -0.6
	await _wait(17.0)
	var cooked := false
	for it in rv.get_node("Cargo").get_children():
		if it.is_in_group("world_item") and it.id == "cooked_meat":
			cooked = true
	_log("meat cooked on the stove: %s" % cooked)
	await _shot("a08_stove_cooking")
	rv.do_action("stove", pl)
	# sink: water tank, fill a bottle, drink it, keep the bottle
	rv.modules["water_tank"] = true
	rv._apply_modules()
	rv.water = 10.0
	Game.slots[Game.selected_slot] = {"id": "sink_unit", "n": 1}
	Game._changed()
	rv.install_module("sink")
	Game.slots[Game.selected_slot] = {"id": "bottle_empty", "n": 1}
	Game._changed()
	rv.do_action("sink", pl)
	_log("after filling at sink: held %s, tank %d" % [Game.equipped(), int(rv.water)])
	Game.consume(Game.equipped())
	_log("after drinking: held %s" % Game.equipped())
	# take the stove back out with G (empty hand)
	_van_door(pl)
	await _wait(0.2)
	# campfire: boil dirty water on the grill
	var cf: Vector3 = rv.to_global(Vector3(7.0, 0, -6.0))
	cf.y = w.gen.height(cf.x, cf.z)
	var cid := Game.new_struct_id()
	Net.place_structure(cid, {"type": "campfire", "pos": Game.arr(cf), "rot": 0.0, "data": {"fuel": 600.0}})
	await _wait(0.3)
	var fire: Node = w.structures[cid]
	_player_at(_ground(cf.x + 1.4, cf.z), 0.0)
	Game.slots[Game.selected_slot] = {"id": "water_dirty", "n": 1}
	Game._changed()
	pr = await _aim_prompt(cf + Vector3(0, 0.3, 0))
	_log("campfire prompt: '%s'" % pr)
	fire.interact(pl)
	Game.slots[Game.selected_slot] = {"id": "potato", "n": 2}
	Game._changed()
	fire.interact(pl)
	_look_at_point(cf + Vector3(0, 0.3, 0))
	await _wait(17.0)
	var boiled: bool = _find_item("water_clean") != null and _find_item("water_clean").global_position.distance_to(cf) < 1.0
	var baked := _find_item("baked_potato")
	_log("boiled on the campfire: %s, baked potatoes: %s" % [boiled, str(baked.amount) if baked else "none"])
	await _shot("a09_campfire_grill")
	# fit everything (cheat) for the full fit-out look
	for slot in Game.Data.VAN_SLOTS:
		rv.modules[slot] = true
	for i in range(4):
		rv.wheel_kind["wheel%d" % i] = "offroad_tire"
	rv.paint = 3
	rv._apply_visuals()
	rv.interior_lights = true
	rv._update_lights()
	var side2: Vector3 = rv.to_global(Vector3(7.5, 0, 4.5))
	_player_at(_ground(side2.x, side2.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 1.4, 0.5)))
	await _wait(0.6)
	await _shot("a10_fitted_van_exterior")
	_van_door(pl)
	await _wait(0.3)
	pl.rotation.y = rv.rotation.y + PI * 0.75
	pl.pitch = -0.3
	pl.head.rotation.x = -0.3
	await _wait(0.4)
	await _shot("a11_fitted_interior_galley")
	pl.rotation.y = rv.rotation.y
	pl.pitch = -0.2
	pl.head.rotation.x = -0.2
	await _wait(0.4)
	await _shot("a12_fitted_interior_rear")
	pl.rotation.y = rv.rotation.y + PI
	await _wait(0.4)
	await _shot("a13_fitted_interior_cab")
	# remove a module with G
	Game.slots = [{"id": "", "n": 0}, {"id": "", "n": 0}]
	Game.select_slot(0)
	Game._changed()
	var rp := _rv_part("radio")
	pr = await _aim_prompt(rp.global_position)
	_log("radio prompt: '%s'" % pr)
	if pl.look_target == rp:
		pl.place_or_grab()
	_log("radio removed: %s, holding %s" % [not rv.modules.has("radio"), Game.equipped()])
	w.hud.open_book()
	await _wait(0.5)
	await _shot("a14_notebook")
	w.hud.close_modal()
	# save, reload state, old-save compatibility
	var st: Dictionary = rv.save_state()
	var ok_save := Game.save_game()
	var data := Game.load_game_data()
	_log("save ok %s, saved modules %d" % [ok_save, data["rv"].get("modules", {}).size()])
	var legacy := st.duplicate(true)
	legacy.erase("modules")
	legacy.erase("wheel_kind")
	rv.apply_state(legacy)
	_log("old save without modules -> %d modules, can drive: %s" % [rv.modules.size(), str(rv.missing_for_drive())])

## 1.6: five hand slots, free furniture placement in the van, spare tire, start trailer,
## a house up the road, predators kept in the woods, and the new items.
func _v16() -> void:
	var w = Game.world
	var rv = Game.rv
	var pl = Game.player
	w.hud.close_modal()
	Game.time_of_day = 10.0
	Game.god_mode = true
	Game.notified.connect(func(t: String) -> void: _log("  note: " + t))
	await _settle(pl.global_position)
	await _wait(1.0)
	_log("hand slots: %d (expect 5) -> %s" % [Game.slots.size(), str(Game.slots)])
	var tires := 0
	for it in get_tree().get_nodes_in_group("world_item"):
		if it.id == "tire" and it.global_position.distance_to(rv.global_position) < 14.0:
			tires += 1
	_log("tires on the lot: %d for %d bare hubs" % [tires, rv.Mounts.missing_count(rv)])
	await _shot("v01_start_view")
	# --- the starting trailer hitches to the van
	var trl = w.vehicle_nodes.get("trl_start")
	_log("start trailer: %s, tongue-to-hitch %.2f m" % [trl.kind, trl.tongue_global().distance_to(rv.hitch_global())])
	_log("hitch prompt: '%s'" % trl.prompt_for("hitch"))
	trl.do_action("hitch", pl)
	await _wait(0.5)
	_log("hitched to the van: %s" % str(trl.tow == rv))
	var tv: Vector3 = rv.to_global(Vector3(5.0, 0, -6.0))
	_player_at(_ground(tv.x, tv.z), 0.0)
	_look_at_point(rv.hitch_global())
	await _wait(0.5)
	await _shot("v02_trailer_hitched")
	# --- predators: spawn many times, none near the player or the start
	Game.time_of_day = 23.0
	var near := 0
	var preds := 0
	var min_d := 9999.0
	for i in range(400):
		w._spawn_timer = 0.0
		w._spawn_animals(0.1)
	for a in w.animals:
		if is_instance_valid(a) and float(a.spec["aggro"]) > 0.0:
			preds += 1
			var d: float = a.global_position.distance_to(pl.global_position)
			min_d = minf(min_d, d)
			if d < 90.0:
				near += 1
	_log("predators spawned on day 1 at the start: %d (closer than 90 m: %d, nearest %.0f m), animals %d" % [preds, near, min_d, w.animals.size()])
	for a in w.animals:
		if is_instance_valid(a):
			a.queue_free()
	w.animals = []
	Game.time_of_day = 10.0
	# --- the house up the road
	var poi: Dictionary = w.gen.poi_for_row(1)
	_log("start house: %s at %.0f m from the van" % [poi.get("type", "none"), (poi["pos"] as Vector3).distance_to(rv.global_position)])
	var hp: Vector3 = poi["pos"]
	var bs := Basis(Vector3.UP, float(poi["yaw"]))
	var view: Vector3 = hp + bs * Vector3(2.0, 0, 16.0)
	_player_at(_ground(view.x, view.z), 0.0)
	await _settle(view)
	_look_at_point(hp + Vector3(0, 2.0, 0))
	await _wait(1.0)
	await _shot("v03_start_house")
	var found := []
	for lt in _all_loot():
		if str(lt.key).begins_with("poi1_") and lt.mode in ["loot", "box"]:
			_player_at(lt.global_position + bs * Vector3(0, 0.2, 1.5), 0.0)
			await _wait(0.1)
			lt.interact(pl)
			found.append(lt.key)
	await _wait(0.5)
	var loot_ids := {}
	for it in get_tree().get_nodes_in_group("world_item"):
		if it.global_position.distance_to(hp) < 12.0:
			loot_ids[it.id] = int(loot_ids.get(it.id, 0)) + it.amount
	_log("searched %s -> found %s" % [str(found), str(loot_ids)])
	var inside: Vector3 = hp + bs * Vector3(0, 0.7, 1.0)
	_player_at(inside, 0.0)
	_look_at_point(hp + bs * Vector3(3.0, 0.8, 3.0))
	await _wait(0.5)
	await _shot("v04_house_loot")
	# --- free furniture placement in the van
	_van_door(pl)
	await _wait(0.2)
	pl.teleport(rv.to_global(Vector3(-0.2, rv.FLOOR_Y + 0.05, 1.6)))
	var toolkit = Game.place_item("toolkit", 1, rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.2, rv.FLOOR_Y + 0.05, 2.2)), rv)
	Game.slots[0] = {"id": "fridge_unit", "n": 1}
	Game.select_slot(0)
	Game._changed()
	_look_at_point(rv.to_global(Vector3(0.6, rv.FLOOR_Y, -1.2)))
	await _wait(0.3)
	pl._update_prompt()
	_log("fridge plan %s, prompt '%s'" % [str(pl._module_plan), pl.prompt])
	await _shot("v05_fridge_ghost_right_wall")
	pl.place_or_grab()
	await _wait(0.2)
	_log("fridge fitted: %s at %s" % [rv.modules.has("fridge"), str(rv.module_xf.get("fridge"))])
	var piv: Vector3 = rv.to_local(rv._doors["fridge"]["pivot"].global_position)
	_log("fridge door now at local %s (default was x -0.86)" % str(piv))
	# cupboard on top of the fridge spot should be refused
	Game.slots[0] = {"id": "cupboard_unit", "n": 1}
	Game._changed()
	_look_at_point(rv.to_global(Vector3(0.55, rv.FLOOR_Y, -0.45)))
	await _wait(0.3)
	_log("cupboard against the fridge: ok=%s reason '%s'" % [pl._module_plan.get("ok"), pl._module_plan.get("reason")])
	_look_at_point(rv.to_global(Vector3(-0.8, rv.FLOOR_Y, -0.4)))
	await _wait(0.3)
	pl.place_or_grab()
	_log("cupboard fitted on the left: %s at %s" % [rv.modules.has("cupboard"), str(rv.module_xf.get("cupboard"))])
	# bed across the back, turned 90 degrees
	Game.slots[0] = {"id": "bed_frame", "n": 1}
	Game._changed()
	pl._place_rot = 0.0
	pl.teleport(rv.to_global(Vector3(-0.2, rv.FLOOR_Y + 0.05, -0.9)))
	_look_at_point(rv.to_global(Vector3(0.0, rv.FLOOR_Y, -2.8)))
	await _wait(0.3)
	_log("bed plan %s" % str(pl._module_plan))
	pl.place_or_grab()
	_log("bed fitted: %s at %s" % [rv.modules.has("bed"), str(rv.module_xf.get("bed"))])
	Game.slots[0] = {"id": "mattress", "n": 1}
	Game._changed()
	await _wait(0.2)
	var mm = _mount_node("mattress")
	_log("mattress mount follows the bed: local %s" % str(rv.to_local(mm.global_position)))
	rv.install_module("mattress")
	_log("mattress fitted: %s" % rv.modules.has("mattress"))
	# kitchen against the right wall at the front, then the stove on it
	Game.slots[0] = {"id": "kitchen_unit", "n": 1}
	Game._changed()
	pl.teleport(rv.to_global(Vector3(-0.2, rv.FLOOR_Y + 0.05, -0.3)))
	_look_at_point(rv.to_global(Vector3(0.8, rv.FLOOR_Y, 1.1)))
	await _wait(0.3)
	_log("kitchen near the door: ok=%s reason '%s'" % [pl._module_plan.get("ok"), pl._module_plan.get("reason")])
	_look_at_point(rv.to_global(Vector3(-0.8, rv.FLOOR_Y, 1.4)))
	await _wait(0.3)
	_log("kitchen plan %s" % str(pl._module_plan))
	pl.place_or_grab()
	_log("kitchen fitted: %s at %s" % [rv.modules.has("kitchen"), str(rv.module_xf.get("kitchen"))])
	Game.slots[0] = {"id": "stove_unit", "n": 1}
	Game._changed()
	rv.install_module("stove")
	_log("stove on the moved counter: %s, burner 0 at local %s" % [rv.modules.has("stove"), str(rv.to_local(rv.heat_spots()[0]) if rv.stove_on else rv._slot_offset("stove") * Vector3(-0.9, rv.FLOOR_Y + 0.98, 0.95))])
	Game.slots[0] = {"id": "", "n": 0}
	Game._changed()
	rv.interior_lights = true
	rv.modules["light"] = true
	rv._apply_modules()
	rv.interior_lights = true
	rv._update_lights()
	pl.teleport(rv.to_global(Vector3(0.0, rv.FLOOR_Y + 0.05, 1.7)))
	pl.rotation.y = rv.rotation.y
	pl.pitch = -0.35
	pl.head.rotation.x = -0.35
	await _wait(0.5)
	await _shot("v06_custom_layout_rear")
	pl.teleport(rv.to_global(Vector3(0.0, rv.FLOOR_Y + 0.05, -1.9)))
	pl.rotation.y = rv.rotation.y + PI
	await _wait(0.5)
	await _shot("v07_custom_layout_front")
	# saved and restored where they were put
	var st: Dictionary = JSON.parse_string(JSON.stringify(rv.save_state()))
	rv.module_xf = {}
	rv._apply_modules()
	rv.apply_state(st)
	_log("after save/load: bed %s fridge %s kitchen %s" % [str(rv.module_xf.get("bed")), str(rv.module_xf.get("fridge")), str(rv.module_xf.get("kitchen"))])
	# take the fridge back out with G
	pl.teleport(rv.to_global(Vector3(-0.2, rv.FLOOR_Y + 0.05, -0.4)))
	var fr_hot = rv._doors["fridge"]["pivot"].get_child(rv._doors["fridge"]["pivot"].get_child_count() - 1)
	_log("fridge slot from its door: '%s'" % rv.slot_for(fr_hot))
	rv.remove_module("fridge")
	_log("fridge removed: %s, holding %s, xf kept: %s" % [not rv.modules.has("fridge"), Game.equipped(), str(rv.module_xf.has("fridge"))])
	# --- tires: E never pulls a fitted tire; G does; a worn tire can go back on
	_van_door(pl)
	Game.slots[0] = {"id": "tire", "n": 1}
	Game._changed()
	rv.do_action("wheel0", pl)
	_log("fitted wheel0: missing %s" % str(rv.missing.has("wheel0")))
	Game.slots[0] = {"id": "", "n": 0}
	Game._changed()
	rv.do_action("wheel0", pl)
	_log("E on a fitted tire leaves it on: %s" % str(not rv.missing.has("wheel0")))
	rv.Mounts.pull(rv, "wheel0")
	_log("G pulled it: missing %s, holding %s" % [str(rv.missing.has("wheel0")), Game.equipped()])
	Game.slots[0] = {"id": "worn_tire", "n": 1}
	Game._changed()
	rv.do_action("wheel0", pl)
	_log("worn tire refitted: %s" % str(not rv.missing.has("wheel0")))
	# --- new items
	var Data = load("res://scripts/data.gd")
	for id in ["chips", "energy_bar", "jerky", "apple", "bread", "instant_noodles", "hot_noodles", "painkillers", "duct_tape", "crowbar", "binoculars", "sofa", "floor_lamp", "rug", "potted_plant", "shelf_unit"]:
		var bb: AABB = Items.bounds(id)
		_log("item %s '%s' size %s" % [id, Data.item_name(id), str(bb.size)])
	var row := 0
	for id in ["sofa", "floor_lamp", "rug", "potted_plant", "shelf_unit", "chair", "table"]:
		var gp: Vector3 = rv.to_global(Vector3(6.0, 0, -6.0 - row * 1.9))
		gp.y = w.gen.height(gp.x, gp.z)
		Net.place_structure(Game.new_struct_id(), {"type": id, "pos": Game.arr(gp), "rot": rv.rotation.y - PI * 0.5, "data": {}})
		row += 1
	var k := 0
	for id in ["chips", "energy_bar", "jerky", "apple", "bread", "instant_noodles", "hot_noodles", "painkillers", "duct_tape", "crowbar", "binoculars"]:
		var gp2: Vector3 = rv.to_global(Vector3(4.2, 0, -6.0 - k * 0.5))
		var bb2: AABB = Items.display_bounds(id)
		gp2.y = w.gen.height(gp2.x, gp2.z) - bb2.position.y + 0.01
		Game.place_item(id, 1, Transform3D(Basis(Vector3.UP, rv.rotation.y), gp2))
		k += 1
	var vp: Vector3 = rv.to_global(Vector3(1.6, 0, -9.0))
	_player_at(_ground(vp.x, vp.z), 0.0, -0.3)
	_look_at_point(rv.to_global(Vector3(5.0, 0.4, -10.0)))
	await _wait(1.0)
	await _shot("v08_new_items")
	Game.slots[0] = {"id": "binoculars", "n": 1}
	Game._changed()
	await _wait(0.1)
	pl.use_primary()
	await _wait(0.6)
	_log("binoculars zoom fov %.1f" % pl.camera.fov)

func _all_loot() -> Array:
	var out := []
	var Loot = load("res://scripts/loot.gd")
	for n in _walk_tree(get_tree().root):
		if n.get_script() == Loot:
			out.append(n)
	return out

func _walk_tree(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk_tree(c))
	return out

func _hold(id: String, n := 1) -> void:
	Game.slots[Game.selected_slot] = {"id": id, "n": n}
	Game._changed()

func _v17() -> void:
	var w = Game.world
	var rv = Game.rv
	var pl = Game.player
	var D = Game.Data
	w.hud.close_modal()
	Game.time_of_day = 10.0
	Game.notified.connect(func(t: String) -> void: _log("  note: " + t))
	await _settle(pl.global_position)
	await _wait(1.0)
	_log("start worn: %s, clock '%s'" % [str(Game.worn.keys()), w.hud.clock.text])
	# --- wearables: one per body slot, backpacks add carry slots
	_hold("hiking_backpack")
	Game.wear("hiking_backpack")
	_log("hiking backpack -> slots %d (expect 8)" % Game.slots.size())
	_hold("military_backpack")
	Game.wear("military_backpack")
	_log("military backpack -> slots %d (expect 9), worn %s, hiking pack back in hands: %s" % [Game.slots.size(), str(Game.worn.keys()), Game.carried("hiking_backpack") > 0])
	_hold("red_jacket")
	Game.wear("red_jacket")
	_hold("tactical_helmet")
	Game.wear("tactical_helmet")
	_log("insulation %.0f, armor %.2f" % [Game.worn_stat("insulation"), Game.worn_stat("armor")])
	var h0: float = Game.stats["health"]
	pl.hurt(10.0, "wolf")
	_log("wolf bite of 10 with a helmet took %.1f health (expect 8)" % (h0 - float(Game.stats["health"])))
	Game.take_off("nav_wristwatch")
	await _wait(0.2)
	_log("clock without a watch: '%s'" % w.hud.clock.text)
	_hold("nav_wristwatch")
	Game.wear("nav_wristwatch")
	# --- data flags
	_hold("multi_tool_wrench")
	_log("multi-tool counts as toolkit: %s; machete butchers: %s" % [Game.has_flag("toolkit"), D.ITEMS["machete"].get("butcher", false)])
	# --- guns use their own ammo
	_hold("double_barrel_shotgun")
	Game.slots[1] = {"id": "ammo_box_12_gauge", "n": 6}
	Game._changed()
	pl._cooldown = 0.0
	pl.use_primary()
	_log("shotgun fired: shells left %d (expect 5)" % Game.carried("ammo_box_12_gauge"))
	_hold("magnum")
	pl.use_primary()
	Game.slots[1] = {"id": "", "n": 0}
	# --- purification tablets
	_hold("water_purification_tablets", 2)
	Game.slots[1] = {"id": "water_dirty", "n": 2}
	Game._changed()
	pl.use_primary()
	_log("tablets: clean %d, dirty %d, tablets %d" % [Game.carried("water_clean"), Game.carried("water_dirty"), Game.carried("water_purification_tablets")])
	Game.slots[1] = {"id": "", "n": 0}
	# --- tools: chop power and ore
	var tree: Node3D = null
	var rockb: Node3D = null
	for n in get_tree().root.find_children("*", "StaticBody3D", true, false):
		if n.has_meta("res_kind") and is_instance_valid(n):
			if n.get_meta("res_kind") == "tree" and tree == null and str(n.get_meta("tree_kind")) != "cactus":
				tree = n
			elif n.get_meta("res_kind") == "rock" and rockb == null:
				rockb = n
	if tree:
		var tpos: Vector3 = tree.global_position
		w.hit_resource(tree, tpos + Vector3(0, 1, 0), 2.0)
		w.hit_resource(tree, tpos + Vector3(0, 1, 0), 2.0)
		await _wait(0.3)
		var drops := {}
		for it in get_tree().get_nodes_in_group("world_item"):
			if it.global_position.distance_to(tpos) < 4.0:
				drops[it.id] = int(drops.get(it.id, 0)) + it.amount
		_log("fire axe felled a tree in 2 swings: %s" % str(drops))
	if rockb:
		var rpos: Vector3 = rockb.global_position
		for k in range(4):
			w.hit_resource(rockb, rpos + Vector3(0, 0.5, 0), 1.0)
		await _wait(0.3)
		var drops2 := {}
		for it in get_tree().get_nodes_in_group("world_item"):
			if it.global_position.distance_to(rpos) < 4.0:
				drops2[it.id] = int(drops2.get(it.id, 0)) + it.amount
		_log("broke a rock: %s" % str(drops2))
	# --- skillet speeds up cooking
	var cf: Vector3 = rv.to_global(Vector3(7.0, 0, -6.0))
	cf.y = w.gen.height(cf.x, cf.z)
	var cid := Game.new_struct_id()
	Net.place_structure(cid, {"type": "campfire", "pos": Game.arr(cf), "rot": 0.0, "data": {"fuel": 600.0}})
	await _wait(0.3)
	var fire: Node = w.structures[cid]
	_player_at(_ground(cf.x + 1.4, cf.z), 0.0)
	_hold("raw_venison")
	fire.interact(pl)
	_hold("camp_cast_iron_skillet")
	fire._set_on_grill()
	_hold("seasoned_hardwood")
	fire.interact(pl)
	_log("hardwood added: fuel %.0f s" % float(fire.data["fuel"]))
	_look_at_point(cf + Vector3(0, 0.3, 0))
	await _wait(8.5)
	_log("venison steak after 8.5 s with a skillet: %s" % str(_find_item("cooked_venison") != null))
	await _shot("x01_campfire_skillet")
	# --- new furniture in a row
	var bz: float = rv.global_position.z - 26.0
	var base: Vector3 = Vector3(w.gen.road_x(bz) - 6.0, 0, bz)
	var types: Array = ["mod_rug_persian", "mod_rug_braided", "mod_rug_japanese_wave", "mod_rug_cowhide", "mod_rug_woven", "camp_folding_chair", "camp_canvas_bedroll", "deployable_tarp", "mod_retro_tv", "mod_led_wall_clock", "mod_weather_station", "mod_cassette_travel_case"]
	var made := []
	for i in range(types.size()):
		var gp: Vector3 = base + Vector3((i % 6) * 2.4, 0, (i / 6) * 3.2)
		gp.y = w.gen.height(gp.x, gp.z)
		var sid := Game.new_struct_id()
		Net.place_structure(sid, {"type": types[i], "pos": Game.arr(gp), "rot": PI, "data": {}})
		made.append(sid)
	await _wait(0.5)
	for sid in made:
		var st = w.structures.get(sid)
		_log("  %s -> prompt '%s'" % [st.type if st else "?", st.get_prompt() if st else ""])
		if st and st.type == "mod_retro_tv":
			st.interact(pl)
	var view: Vector3 = base + Vector3(6.0, 0.0, 9.0)
	_player_at(_ground(view.x, view.z), PI, -0.35)
	await _settle(view)
	_look_at_point(base + Vector3(6.0, 0.0, 1.2))
	await _wait(1.5)
	await _shot("x02_new_furniture")
	# --- hand items laid out on a table
	var tp: Vector3 = rv.to_global(Vector3(9.0, 0, -12.0))
	tp.y = w.gen.height(tp.x, tp.z)
	var tid := Game.new_struct_id()
	Net.place_structure(tid, {"type": "table", "pos": Game.arr(tp), "rot": 0.0, "data": {}})
	await _wait(0.3)
	var show := ["combat_19_pistol", "magnum", "nav_pocket_compass", "mod_decor_fuzzy_dice", "camp_coffee_percolator", "elec_circuit_board", "salvage_license_plate", "hunt_predator_skull", "mod_decor_mini_globe", "camp_cast_iron_skillet"]
	for i in range(show.size()):
		var ip: Vector3 = tp + Vector3(-0.55 + (i % 5) * 0.27, 0.8, -0.2 + (i / 5) * 0.38)
		Game.place_item(show[i], 1, Transform3D(Basis(Vector3.UP, 0.4), ip - Vector3(0, Items.display_bounds(show[i]).position.y, 0)))
	_player_at(_ground(tp.x, tp.z + 1.3), 0.0, -0.6)
	_look_at_point(tp + Vector3(0, 0.8, 0))
	await _wait(1.0)
	await _shot("x03_items_on_table")
	# --- hanging decor in the van cab
	rv.modules["walls"] = true
	rv._apply_visuals()
	_van_door(pl)
	await _wait(0.2)
	pl.teleport(rv.to_global(Vector3(0.0, rv.FLOOR_Y + 0.05, 0.6)))
	_hold("mod_decor_dreamcatcher")
	_look_at_point(rv.to_global(Vector3(0.0, rv.ROOF_Y + 2.0, -0.2)))
	await _wait(0.3)
	pl._update_placement()
	_log("aim at the ceiling: valid %s" % str(pl._place_valid))
	pl.place_or_grab()
	await _wait(0.5)
	var dc = _find_item("mod_decor_dreamcatcher")
	_log("dreamcatcher hung: %s (hung flag %s, placed %s) at local %s, roof %.2f" % [dc != null, str(dc._hung) if dc else "-", str(dc.placed) if dc else "-", str(rv.to_local(dc.global_position)) if dc else "-", rv.ROOF_Y])
	if dc:
		pl.teleport(rv.to_global(rv.to_local(dc.global_position) * Vector3(1, 0, 1) + Vector3(0.0, rv.FLOOR_Y + 0.05, 1.3)))
		await _wait(0.2)
		_look_at_point(dc.global_position + Vector3(0, 0.1, 0))
	await _wait(0.5)
	await _shot("x04_dreamcatcher")
	_van_door(pl)
	# --- viewmodels at dusk
	var vp: Vector3 = rv.to_global(Vector3(14.0, 0, 0.0))
	_player_at(_ground(vp.x, vp.z), 0.0, -0.1)
	for id in ["torch", "combat_19_pistol", "double_barrel_shotgun", "fire_axe", "nav_pocket_compass", "camp_folding_lantern", "compound_bow", "machete"]:
		Game.time_of_day = 20.8 if id in ["torch", "camp_folding_lantern"] else 11.0
		_hold(id)
		await _wait(0.5)
		await _shot("vm17_" + id)
		_log("  holding %s: nav '%s'" % [id, pl.nav_text])
	_hold("nav_paper_roadmap")
	pl._cooldown = 0.0
	pl.use_primary()

func _v171() -> void:
	var w = Game.world
	var rv = Game.rv
	var pl = Game.player
	w.hud.close_modal()
	Game.time_of_day = 11.0
	Game.weather = "clear"
	Game.notified.connect(func(t: String) -> void: _log("  note: " + t))
	await _settle(pl.global_position)
	await _wait(1.5)
	var vk := []
	for vid in w.vehicle_nodes:
		vk.append("%s:%s %.0fm" % [vid, w.vehicle_nodes[vid].kind, w.vehicle_nodes[vid].global_position.distance_to(rv.global_position)])
	_log("vehicles: %s" % str(vk))
	_log("world items: %d" % get_tree().get_nodes_in_group("world_item").size())
	var ov: Vector3 = rv.to_global(Vector3(-4.0, 0, 6.0))
	_player_at(_ground(ov.x, ov.z), 0.0)
	_look_at_point(rv.to_global(Vector3(-16.0, 0.0, -12.0)))
	await _wait(0.8)
	await _shot("y01_depot")
	_look_at_point(rv.to_global(Vector3(0.0, 1.0, 14.0)))
	await _wait(0.5)
	await _shot("y02_vehicles")
	var tv: Vector3 = rv.to_global(Vector3(8.0, 0, 3.0))
	_player_at(_ground(tv.x, tv.z), 0.0)
	_look_at_point(rv.to_global(Vector3(5.9, 0.0, 1.0)))
	await _wait(0.4)
	await _shot("y02b_tires_and_wheel")
	for it in get_tree().get_nodes_in_group("world_item"):
		if it.id in ["steering_wheel", "tire"] and it.global_position.distance_to(rv.global_position) < 20.0:
			_log("  %s at van-local %s" % [it.id, str(rv.to_local(it.global_position))])
	# --- shadows close up
	var sp: Vector3 = rv.to_global(Vector3(RV_W() * 0.5 + 3.0, 0, -1.0))
	_player_at(_ground(sp.x, sp.z), 0.0, -0.5)
	_look_at_point(rv.to_global(Vector3(RV_W() * 0.5 + 0.5, 0.0, 0.5)))
	await _wait(0.6)
	await _shot("y03_shadows")
	# --- rear doors and climbing
	var back: Vector3 = rv.to_global(Vector3(0.0, 0, rv.REAR_Z - 3.0))
	_player_at(_ground(back.x, back.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 1.8, rv.REAR_Z)))
	await _wait(0.4)
	await _shot("y04_rear_closed")
	rv.do_action("rear_door", pl)
	await _wait(1.2)
	_log("rear open: %s" % rv.rear_open)
	await _shot("y05_rear_open")
	# walk in through the back
	var p0: Vector3 = rv.to_global(Vector3(0.0, 0, rv.REAR_Z - 1.0))
	_player_at(_ground(p0.x, p0.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 1.6, 0)))
	Input.action_press("move_forward")
	await _wait(2.5)
	Input.action_release("move_forward")
	_log("walked in the back: inside %s, local %s" % [rv.is_inside(pl.global_position), str(rv.to_local(pl.global_position))])
	await _shot("y06_inside_from_back")
	rv.set_rear(false)
	await _wait(0.8)
	# climb the ladder at the back
	var lp: Vector3 = rv.to_global(Vector3(0.6, 0, rv.REAR_Z - 0.75))
	_player_at(_ground(lp.x, lp.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0.6, 1.6, rv.REAR_Z)))
	await _wait(0.3)
	pl._update_prompt()
	_log("prompt at the back: '%s'" % pl.prompt)
	var climbed: bool = pl.try_climb()
	await _wait(1.6)
	_log("climb started %s; feet now %.2f m above van origin (roof at %.2f)" % [climbed, rv.to_local(pl.global_position).y, rv.ROOF_Y])
	_look_at_point(rv.to_global(Vector3(0, rv.ROOF_Y, 3.0)))
	await _wait(0.4)
	await _shot("y07_on_roof")
	# climb onto the pickup
	var tr = w.vehicle_nodes.get("start_truck")
	if tr:
		var tp: Vector3 = tr.global_transform * Vector3(0, 0, -3.1)
		_player_at(_ground(tp.x, tp.z), 0.0)
		_look_at_point(tr.global_position + Vector3(0, 0.8, 0))
		await _wait(0.3)
		var c2: bool = pl.try_climb()
		await _wait(1.5)
		_log("climb onto the pickup: %s, feet %.2f above ground" % [c2, pl.global_position.y - w.gen.height(pl.global_position.x, pl.global_position.z)])
	# --- steering wheel from the driver's seat (first person)
	for slot in Game.Data.VAN_SLOTS:
		rv.modules[slot] = true
	rv._apply_visuals()
	for k in rv.parts:
		rv.parts[k] = 100.0
	pl.enter_vehicle(rv, true)
	rv.set_camera(false)
	await _wait(0.8)
	await _shot("y08_driver_view")
	pl.exit_vehicle()
	await _wait(0.5)
	# --- the house up the road
	var poi: Dictionary = w.gen.poi_for_row(1)
	var hp: Vector3 = poi["pos"]
	var bs := Basis(Vector3.UP, float(poi["yaw"]))
	var view: Vector3 = hp + bs * Vector3(-6.0, 0, 15.0)
	_player_at(_ground(view.x, view.z), 0.0)
	await _settle(view)
	_look_at_point(hp + Vector3(0, 2.5, 0))
	await _wait(1.0)
	await _shot("y09_house_roof")
	var furn := []
	for sid in w.structures:
		if str(sid).begins_with("poi1_"):
			furn.append("%s:%s" % [sid, w.structures[sid].type])
	_log("house furniture: %s" % str(furn))
	var inside: Vector3 = hp + bs * Vector3(0, 0.7, 2.5)
	_player_at(inside, 0.0)
	_look_at_point(hp + bs * Vector3(-3.0, 0.8, 1.0))
	await _wait(0.6)
	await _shot("y10_house_living")
	_look_at_point(hp + bs * Vector3(0.0, 1.0, 6.0))
	await _wait(0.4)
	await _shot("y11_house_door_from_inside")
	var sofa = w.structures.get("poi1_f_sofa")
	Game.select_slot(1)
	if sofa:
		_player_at(sofa.global_position + bs * Vector3(1.6, 0.1, 0.0), 0.0)
		_look_at_point(sofa.global_position + Vector3(0, 0.4, 0))
		await _wait(0.3)
		pl._update_prompt()
		_log("sofa prompt '%s'" % pl.prompt)
		pl.place_or_grab()
		await _wait(0.3)
		_log("carrying the sofa: %s; removed flag %s" % [Game.carried("sofa") > 0, Game.removed.has("poi1_f_sofa")])

## 1.8: performance parts, engine heat, nitrous, tire types, lithium battery and the body add-ons.
func _hold18(id: String) -> void:
	Game.slots[0] = {"id": id, "n": 1}
	Game.slots[1] = {"id": "toolkit", "n": 1}
	Game.select_slot(0)
	Game._changed()

func _v18() -> void:
	var w = Game.world
	var rv = Game.rv
	var pl = Game.player
	w.hud.close_modal()
	Game.time_of_day = 11.0
	Game.weather = "clear"
	Game.notified.connect(func(t: String) -> void: _log("  note: " + t))
	await _settle(pl.global_position)
	var item_origin: Vector3 = pl.global_position - Vector3(0, 0, 1.8)
	item_origin.y = w.gen.height(item_origin.x, item_origin.z) + 0.35
	var item := Game.place_item("fuel_can", 2, Transform3D(Basis.IDENTITY, item_origin))
	var item_center := item_origin + Vector3.UP * 0.15
	var item_prompt: String = await _aim_prompt(item_center)
	await get_tree().process_frame
	if pl.look_target != item or not item._hl or w.hud.aim_label.text != item.aim_name():
		_log("FAIL: aimed item outline or name missing (%s)" % item_prompt)
	elif w.hud.action_hints.get_child_count() != 1:
		_log("FAIL: pickup action hint missing (%s)" % item_prompt)
	else:
		_log("PASS: aimed stack shows outline, name, quantity and pickup action")
	await _shot("z00_item_aim")
	await _aim_prompt(item_origin + Vector3.UP * 4.0)
	if item._hl:
		_log("FAIL: item outline did not clear after looking away")
	item.queue_free()
	# make the van road-ready the quick way
	rv.modules = rv._all_modules()
	rv.missing = {}
	for k in rv.parts:
		rv.parts[k] = 100.0
	rv.battery = 100.0
	rv.fuel = 60.0
	rv._apply_visuals()
	await _wait(0.5)
	# fit hood parts through the real hood action
	var hood: Vector3 = rv.to_global(Vector3(0, 1.68, rv.FRONT_Z + 0.85))
	var hp: Vector3 = rv.to_global(Vector3(0, 0, rv.FRONT_Z + 2.6))
	_player_at(_ground(hp.x, hp.z), 0.0)
	for id in ["vehicle_turbocharger", "vehicle_supercharger", "vehicle_nos_kit", "vehicle_dual_fan_radiator", "vehicle_alternator", "vehicle_starter_motor", "vehicle_suspension_part"]:
		_hold18(id)
		var pr: String = await _aim_prompt(hood)
		_log("hood prompt holding %s: '%s'" % [id, pr])
		rv.do_action("hood", pl)
	_log("hood modules: %s kinds %s" % [str(rv.modules.keys().filter(func(k): return Game.Data.VAN_SLOTS[k].get("hood", false))), str(rv.module_kind)])
	# take the last one back out with [G] and refit it
	Game.slots[0] = {"id": "", "n": 0}
	Game.select_slot(0)
	_look_at_point(hood)
	await _wait(0.15)
	pl._update_prompt()
	_log("hood prompt empty-handed: '%s'" % pl.prompt)
	pl.place_or_grab()
	_log("after [G]: suspension fitted %s, holding %s" % [rv.modules.has("suspension"), Game.equipped()])
	rv.do_action("hood", pl)
	# body add-ons through their mounts
	for slot in ["roof_rack", "cargo_box", "roof_tent", "spare_mount", "panniers", "jerry_holder", "snorkel", "winch", "ram_plow", "windshield_mesh", "door_armor", "mud_flaps", "underglow", "tow_hitch"]:
		_hold18(Game.Data.VAN_SLOTS[slot]["item"])
		var ok: bool = rv.install_module(slot)
		if not ok:
			_log("  could not fit %s" % slot)
	_log("fuel capacity with jerry cans: %d" % int(rv.fuel_capacity()))
	_log("can tow: %s" % rv.can_tow())
	# tires: sand on the back, solid on the front
	for i in range(4):
		rv.missing["wheel%d" % i] = true
	for i in range(4):
		_hold18("vehicle_tire_solid" if i < 2 else "vehicle_tire_sand")
		rv.Mounts.act(rv, "wheel%d" % i)
	_log("wheel kinds: %s" % str(rv.wheel_kind))
	_log("grip on road: %s" % str([rv.wheel_grip(0), rv.wheel_grip(2)]))
	# lithium battery
	Game.slots[0] = {"id": "", "n": 0}
	rv.Mounts.pull(rv, "battery")
	_log("pulled battery: holding %s" % Game.equipped())
	_hold18("vehicle_lithium_battery")
	rv.Mounts.act(rv, "battery")
	_log("battery kind %s, charge %d" % [rv.battery_kind, int(rv.battery)])
	# spare on the roof
	_hold18("tire")
	rv._spare_action()
	_log("spare tire: %s" % rv.spare_tire)
	Game.slots[0] = {"id": "", "n": 0}
	Game.select_slot(0)
	rv.headlights = true
	rv._apply_visuals()
	await _wait(0.6)
	# --- pictures
	for v in [["z01_front", Vector3(-5.5, 0, 8.5), Vector3(0, 1.4, 2.0)], ["z02_rear", Vector3(5.0, 0, -9.0), Vector3(0, 1.4, -2.0)],
			["z03_side_right", Vector3(7.5, 0, 0.5), Vector3(0, 1.6, 0.0)], ["z04_side_left", Vector3(-7.5, 0, -0.5), Vector3(0, 1.6, 0.0)]]:
		var cp: Vector3 = rv.to_global(v[1])
		_player_at(_ground(cp.x, cp.z), 0.0)
		_look_at_point(rv.to_global(v[2]))
		await _wait(0.5)
		await _shot(v[0])
	# on the roof
	var rp: Vector3 = rv.to_global(Vector3(-0.1, rv.ROOF_Y + 0.5, 0.05))
	_player_at(rp, 0.0)
	await _wait(0.6)
	var rpr: String = await _aim_prompt(rv.to_global(Vector3(0.52, rv.ROOF_Y + 0.88, 1.15)))
	_log("roof prompt: '%s' (feet %.2f above van origin)" % [rpr, rv.to_local(pl.global_position).y])
	var tpr: String = await _aim_prompt(rv.to_global(Vector3(-0.52, rv.ROOF_Y + 0.75, 1.2)))
	_log("tent prompt: '%s'" % tpr)
	_look_at_point(rv.to_global(Vector3(0.3, rv.ROOF_Y + 0.5, 1.6)))
	rv.do_action("cargo_box", pl)
	await _wait(0.6)
	await _shot("z05_roof_rack")
	rv.do_action("cargo_box", pl)
	# panniers open
	var pp: Vector3 = rv.to_global(Vector3(rv.W * 0.5 + 1.6, 0, -0.95))
	_player_at(_ground(pp.x, pp.z), 0.0)
	var pr2: String = await _aim_prompt(rv.to_global(Vector3(rv.W * 0.5 + 0.32, rv.FLOOR_Y + 0.3, -0.95)))
	_log("pannier prompt: '%s'" % pr2)
	rv.do_action("pannier_r", pl)
	await _wait(0.6)
	await _shot("z06_pannier_open")
	rv.do_action("pannier_r", pl)
	# night: underglow
	Game.time_of_day = 22.5
	var np: Vector3 = rv.to_global(Vector3(-6.0, 0, 5.0))
	_player_at(_ground(np.x, np.z), 0.0)
	_look_at_point(rv.to_global(Vector3(0, 0.6, 0)))
	await _wait(0.8)
	await _shot("z07_underglow_night")
	Game.time_of_day = 11.0
	rv.headlights = false
	# drive: heat, nitrous (out on the open road, clear of the parked test cars)
	var gz: float = rv.global_position.z + 160.0
	var gx: float = w.gen.road_x(gz) - 1.8
	rv.global_position = Vector3(gx, w.gen.height(gx, gz) + 1.0, gz)
	rv.rotation = Vector3(0, atan2(w.gen.road_x(gz + 5.0) - w.gen.road_x(gz), 5.0), 0)
	pl.teleport(rv.global_position + Vector3(3, 0, 0))
	await _settle(rv.global_position)
	pl.enter_vehicle(rv, true)
	rv.set_camera(false)
	await _wait(0.6)
	await _shot("z08_driver_view")
	rv.set_camera(true)
	rv.try_start_engine()
	_log("engine on %s (starter fitted)" % rv.engine_on)
	Input.action_press("move_forward", 1.0)
	await _wait(5.0)
	_log("after 5 s full throttle: %d km/h, %d°C (force %.0f brake %.0f driver %s trailer %s ui %s)" % [int(rv.speed_kmh()), int(rv.engine_heat), rv.engine_force, rv.brake, rv.driver, rv.trailer, Game.ui_open])
	Input.action_press("sprint")
	await _wait(3.0)
	_log("after 3 s nitrous: %d km/h, %d°C, NOS %d%%, boosting %s" % [int(rv.speed_kmh()), int(rv.engine_heat), int(rv.nitrous), rv.boosting])
	await _shot("z09_nitrous")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	_log("dash: %s" % rv.dash_extra())
	# no radiator, no coolant: does it cook?
	rv.modules.erase("radiator")
	rv.coolant = 20.0
	Input.action_press("move_forward", 1.0)
	Input.action_press("sprint")
	await _wait(8.0)
	_log("no radiator, low coolant, full boost 8 s: %d°C, engine on %s, engine %d%%" % [int(rv.engine_heat), rv.engine_on, int(rv.parts["engine"])])
	Input.action_release("sprint")
	Input.action_release("move_forward")
	Input.action_press("jump")
	await _wait(2.0)
	Input.action_release("jump")
	pl.exit_vehicle()
	await _wait(0.5)
	rv.engine_heat = 112.0
	rv._overheated = true
	rv.try_start_engine()
	_log("restart while hot: engine on %s" % rv.engine_on)
	_hold18("mod_coolant_jug_20l")
	rv.do_action("hood", pl)
	Game.slots[0] = {"id": "", "n": 0}
	Game.select_slot(0)
	var hp2: Vector3 = rv.to_global(Vector3(0, 0, rv.FRONT_Z + 2.6))
	_player_at(_ground(hp2.x, hp2.z), 0.0)
	var hpr: String = await _aim_prompt(rv.to_global(Vector3(0, 1.68, rv.FRONT_Z + 0.85)))
	_log("hood prompt empty-handed: '%s'" % hpr)
	_log("after coolant: %d°C coolant %d%%" % [int(rv.engine_heat), int(rv.coolant)])
	# winch: drag the van off into the field, then winch it back
	var off: Vector3 = rv.global_position + Vector3(18.0, 0, 0)
	rv.global_position = Vector3(off.x, w.gen.height(off.x, off.z) + 1.5, off.z)
	rv.linear_velocity = Vector3.ZERO
	await _wait(1.0)
	var d0: float = absf(rv.global_position.x - w.gen.road_x(rv.global_position.z))
	Game.slots[0] = {"id": "", "n": 0}
	Game.select_slot(0)
	rv.do_action("winch", pl)
	await _wait(0.5)
	_log("winch: %.1f m from the road -> %.1f m" % [d0, absf(rv.global_position.x - w.gen.road_x(rv.global_position.z))])
	# save round trip
	var st: Dictionary = rv.save_state()
	rv.apply_state(st)
	_log("after save/load: kinds %s battery %s spare %s tires %s" % [str(rv.module_kind), rv.battery_kind, rv.spare_tire, str(rv.wheel_kind)])
	# the new items' icons
	if DisplayServer.get_name() != "headless":
		await _items_sheet()

func _drive18() -> void:
	var rv = Game.rv
	var pl = Game.player
	Game.world.hud.close_modal()
	await _settle(pl.global_position)
	rv.modules = rv._all_modules()
	rv.missing = {}
	for k in rv.parts:
		rv.parts[k] = 100.0
	rv.battery = 100.0
	rv.fuel = 60.0
	rv._apply_visuals()
	var extra: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fit="):
			extra = a.substr(6).split(",")
	for slot in extra:
		if slot.begins_with("engine="):
			rv.module_kind["engine"] = slot.substr(7)
		elif slot.begins_with("tire="):
			for i in range(4):
				rv.wheel_kind["wheel%d" % i] = slot.substr(5)
		elif slot == "lithium":
			rv.battery_kind = "vehicle_lithium_battery"
		else:
			rv.modules[slot] = true
	rv._apply_visuals()
	var gen = Game.world.gen
	var z: float = rv.global_position.z + 160.0
	var x: float = gen.road_x(z) - 1.8
	rv.global_position = Vector3(x, gen.height(x, z) + 1.0, z)
	rv.rotation = Vector3(0, atan2(gen.road_x(z + 5.0) - gen.road_x(z), 5.0), 0)
	pl.teleport(rv.global_position + Vector3(3, 0, 0))
	await _settle(rv.global_position)
	await _wait(1.0)
	pl.enter_vehicle(rv, true)
	await _wait(0.5)
	rv.try_start_engine()
	Input.action_press("move_forward", 1.0)
	if "--nos" in OS.get_cmdline_user_args():
		Input.action_press("sprint")
	for i in range(6):
		await _wait(1.0)
		_log("fit %s t=%d: %d km/h, engine_force %.0f brake %.0f sleeping %s freeze %s driver %s heat %d" % [str(extra), i + 1, int(rv.speed_kmh()), rv.engine_force, rv.brake, rv.sleeping, rv.freeze, rv.driver, int(rv.engine_heat)])
	Input.action_release("move_forward")
	Input.action_release("sprint")

func RV_W() -> float:
	return Game.rv.W

var quality_failures := 0

func _check_quality(condition: bool, message: String) -> void:
	_log(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		quality_failures += 1

func _v110() -> void:
	var Journey = load("res://scripts/journey.gd")
	var SaveStore = load("res://scripts/save_store.gd")
	var route = Journey.new()
	route.prepare(Game.world.gen, Game.seed_value)
	_check_quality(route.stops.size() == 9, "nine actual generated destinations")
	var twin = Journey.new()
	twin.prepare(Game.world.gen, Game.seed_value)
	_check_quality(route.stops == twin.stops, "route deterministic for the same seed")
	var start: Vector3 = route.current()["pos"]
	_check_quality(route.visit(start + Vector3(0, 30, 0)) == "", "flying above a stop does not complete it")
	_check_quality(route.visit(start + Vector3(200, 0, 0)) == "", "far-away stop is not completed")
	_check_quality(route.visit(start) != "" and route.completed == 1, "arrival advances the route once")
	_check_quality(route.visit(start) == "" and route.completed == 1, "revisiting does not duplicate progress")
	twin.restore(route.completed)
	_check_quality(twin.current() == route.current(), "progress restores to the correct destination")
	for i in range(1, 9):
		route.visit(route.current()["pos"])
	_check_quality(route.completed == 9 and route.current().is_empty(), "all destinations complete without overflow")
	route.restore(999)
	_check_quality(route.completed == 9, "invalid saved progress is clamped")
	route.reset()
	_check_quality(route.completed == 0 and route.stops.is_empty(), "new game clears journey")
	var path: String = out + "/save-test.json"
	var old := {"seed": 4242, "journey_completed": 2, "slots": [{"id": "canned_food", "n": 1}]}
	var newer := {"seed": 4242, "journey_completed": 3, "slots": []}
	_check_quality(SaveStore.write(path, old), "first checked save")
	_check_quality(SaveStore.write(path, newer), "replace existing save")
	_check_quality(SaveStore.recover(path).get("journey_completed") == 3, "newest save loads")
	_check_quality(SaveStore.read(path + ".bak").get("journey_completed") == 2, "previous save retained")
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{interrupted")
	broken.close()
	_check_quality(SaveStore.recover(path).get("journey_completed") == 2, "corrupt main recovers previous save")
	_check_quality(SaveStore.write(path, newer) and SaveStore.read(path + ".bak").get("journey_completed") == 2, "recovery save keeps valid backup")
	var invalid := FileAccess.open(path, FileAccess.WRITE)
	invalid.store_string('{"seed": 42, "slots": [null]}')
	invalid.close()
	_check_quality(SaveStore.read(path).is_empty(), "malformed slots rejected before state mutation")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(path + suffix)
	var pl = Game.player
	var rv = Game.rv
	Game.god_mode = true
	Game.world.hud.close_modal()
	Game.time_of_day = 11.0
	await _settle(pl.global_position)
	rv.modules = rv._all_modules()
	rv._apply_visuals()
	await _wait(0.5)
	var door = rv._doors["cabinet"]["pivot"]
	var hot: Node
	for child in door.get_children():
		if child.has_method("set_highlight"):
			hot = child
	pl._set_highlight(hot)
	_check_quality(hot != null and hot._hl and hot.aim_name() == "Pantry cupboard", "individual cupboard door has outline and aim name")
	pl._set_highlight(null)
	_check_quality(not hot._hl, "cupboard outline clears")
	var cp: Vector3 = rv.to_global(Vector3(0.48, rv.FLOOR_Y + 0.08, -0.8))
	_player_at(cp, 0)
	_look_at_point(rv.to_global(Vector3(-rv.W * 0.5 + 0.7, rv.FLOOR_Y + 0.5, -1.45)))
	await _wait(0.3)
	await _shot("quality_cupboard_closed")
	rv.do_action("cabinet", pl)
	await _wait(0.4)
	await _shot("quality_cupboard_open")
	# A close, uncluttered product display uses the real item meshes and materials.
	var stage := Node3D.new()
	Game.world.add_child(stage)
	stage.position = Vector3(0, 100, 0)
	Lib.box(stage, Vector3(0, -0.08, 0), Vector3(5, 0.12, 3), Lib.mat("planks", Color.WHITE, 2.0, false))
	var products := ["canned_food", "water_clean", "paint_can", "soda", "water_dirty"]
	for i in range(products.size()):
		var item := Items.display_instance(products[i])
		stage.add_child(item)
		item.position = Vector3(-0.8 + i * 0.4, 0, 0)
		item.rotation.y = PI
		_check_quality(ResourceLoader.exists("res://assets/textures/label_%s.png" % products[i]), "label imported: " + products[i])
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.position = Vector3(0, 0.8, 1.75)
	cam.look_at(stage.global_position + Vector3(0, 0.15, 0))
	cam.make_current()
	Game.world.hud.root.hide()
	await _wait(0.4)
	await _shot("quality_printed_labels")
	var crate := StaticBody3D.new()
	crate.set_script(load("res://scripts/structure.gd"))
	crate.persistent = false
	crate.setup("", {"type": "crate", "pos": [0, 0, 0], "data": {}})
	stage.add_child(crate)
	for child in stage.get_children():
		if child != crate and child != cam:
			child.hide()
	cam.position = Vector3(1.6, 1.5, 1.8)
	cam.look_at(crate.global_position + Vector3(0, 0.3, 0))
	pl._set_highlight(crate)
	_check_quality(crate._hl, "furniture outline enabled")
	pl._set_highlight(null)
	await _wait(0.3)
	await _shot("quality_slatted_crate")
	Game.world.hud.root.show()
	pl.camera.make_current()
	stage.queue_free()
	var hp: Vector3 = Game.world.gen.poi_for_row(1)["pos"] + Vector3(0, 0.2, 22)
	_player_at(hp, 0)
	await _settle(hp)
	_look_at_point(Game.world.gen.poi_for_row(1)["pos"] + Vector3.UP)
	await _wait(0.4)
	await _shot("quality_journey_hud")
	Game.world.hud.open_book()
	await _wait(0.4)
	await _shot("quality_route_notebook")
	Game.world.hud.close_modal()
	await _v111()
	await _v112()
	_log("Quality checks: %d failure(s)" % quality_failures)

func _v111() -> void:
	var w = Game.world
	var pl = Game.player
	var prev_animals: Array = w.animals.duplicate()
	var prev_time := Game.time_of_day
	var prev_day := Game.day
	var prev_stats: Dictionary = Game.stats.duplicate(true)
	var prev_spawn = Game.spawn_point
	w.animals = [] # keep gameplay predator safety; isolate the clock assertions
	_check_quality(not Audio._ambient.has("crickets_loop"), "night cricket loop is not instantiated")
	Game.time_of_day = 23.5
	Game.day = 6
	w.sleep(pl.global_position)
	_check_quality(is_equal_approx(Game.time_of_day, 5.0) and Game.day == 7, "sleep at night advances instantly to 05:00 tomorrow")
	Game.time_of_day = 3.0
	Game.day = 7
	w.sleep(pl.global_position)
	_check_quality(is_equal_approx(Game.time_of_day, 5.0) and Game.day == 7, "sleep before dawn wakes at 05:00 the same day")
	Game.time_of_day = 11.0
	w.sleep(pl.global_position)
	_check_quality(is_equal_approx(Game.time_of_day, 14.0), "daytime nap still advances three hours")
	for seat_type in ["chair", "sofa", "camp_folding_chair"]:
		var chair := StaticBody3D.new()
		chair.set_script(load("res://scripts/structure.gd"))
		w.add_child(chair)
		chair.persistent = false
		var origin: Vector3 = pl.global_position
		chair.setup("", {"type": seat_type, "pos": Game.arr(origin + Vector3(2.0, 0.0, 0.0)), "rot": 0.3, "data": {}})
		Game.stats["energy"] = 20.0
		chair.interact(pl)
		_check_quality(pl.seated_at == chair and pl.get_node("CollisionShape3D").disabled, seat_type + " enters first-person sitting")
		_check_quality(absf(pl.camera.global_position.y - (chair.global_position.y + pl.SEATED_EYE)) < 0.05, seat_type + " has true seated eye height")
		pl._update_prompt()
		_check_quality(pl.prompt.contains("Stand up"), seat_type + " exposes the exit action")
		await _wait(1.0)
		_check_quality(Game.stats["energy"] > 20.5, seat_type + " restores energy continuously")
		chair.global_position += Vector3(1.0, 0.0, 0.0)
		await _wait(0.12)
		_check_quality(pl.global_position.distance_to(chair.to_global(Vector3(0.0, 0.0, -0.06))) < 0.05, seat_type + " carries the viewpoint as furniture moves")
		if seat_type == "chair":
			await _shot("quality_first_person_seated")
		pl.stand_up()
		_check_quality(pl.seated_at == null and not pl.get_node("CollisionShape3D").disabled and is_equal_approx(pl.head.position.y, pl.EYE), seat_type + " stands with collision restored")
		chair.queue_free()
		await get_tree().process_frame
	Game.time_of_day = prev_time
	Game.day = prev_day
	Game.stats = prev_stats
	Game.spawn_point = prev_spawn
	w.animals = prev_animals

func _run() -> void:
	if "--v111" in OS.get_cmdline_user_args() or "--v110" in OS.get_cmdline_user_args():
		Game.new_game(4242, "Normal")
		get_tree().root.get_node("Main")._start_world({})
		await _wait(1.5)
		await _v110()
		var log_file := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		log_file.store_string("\n".join(log_lines))
		log_file.close()
		get_tree().quit(1 if quality_failures else 0)
		return
	if "--drive18" in OS.get_cmdline_user_args():
		var md := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		md._start_world({})
		await _wait(1.5)
		await _drive18()
		get_tree().quit()
		return
	if "--v18" in OS.get_cmdline_user_args():
		var m18 := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		m18._start_world({})
		await _wait(1.5)
		await _v18()
		var f18 := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		f18.store_string("\n".join(log_lines))
		f18.close()
		get_tree().quit()
		return
	if "--v171" in OS.get_cmdline_user_args():
		var m171 := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		m171._start_world({})
		await _wait(1.5)
		await _v171()
		var f171 := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		f171.store_string("\n".join(log_lines))
		f171.close()
		get_tree().quit()
		return
	if "--v17" in OS.get_cmdline_user_args():
		var m17 := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		m17._start_world({})
		await _wait(1.5)
		await _v17()
		var f17 := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		f17.store_string("\n".join(log_lines))
		f17.close()
		get_tree().quit()
		return
	if "--v16" in OS.get_cmdline_user_args():
		var m16 := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		m16._start_world({})
		await _wait(1.5)
		await _v16()
		var f16 := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		f16.store_string("\n".join(log_lines))
		f16.close()
		get_tree().quit()
		return
	if "--walkin" in OS.get_cmdline_user_args():
		var mw := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		mw._start_world({})
		await _wait(1.5)
		await _walkin()
		var fw := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		fw.store_string("\n".join(log_lines))
		fw.close()
		get_tree().quit()
		return
	if "--assembly" in OS.get_cmdline_user_args():
		var ma := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		ma._start_world({})
		await _wait(1.5)
		await _assembly()
		var fa := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		fa.store_string("\n".join(log_lines))
		fa.close()
		get_tree().quit()
		return
	if "--hands" in OS.get_cmdline_user_args():
		var mh := get_tree().root.get_node("Main")
		Game.new_game(4242, "Normal")
		mh._start_world({})
		await _wait(1.5)
		await _hands()
		var fh := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
		fh.store_string("\n".join(log_lines))
		fh.close()
		get_tree().quit()
		return
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
	_log("start hands: %s worn %s" % [str(Game.slots), str(Game.worn)])
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
	_van_door(Game.player)
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
	_van_door(Game.player)
	await _wait(0.3)
	# Furniture on the RV + loose cargo
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
	w.hud.open_book()
	await _wait(0.4)
	await _shot("15_rv_workshop")
	w.hud.open_build_menu()
	await _wait(0.4)
	await _shot("16_build_menu")
	w.hud.close_modal()
	# save/load round trip
	var ok_save := Game.save_game()
	var data := Game.load_game_data()
	_log("save ok %s, structures in save %d, slots %s" % [ok_save, data.get("structures", {}).size(), str(data.get("slots", []))])
	var f := FileAccess.open("%s/devtest.log" % out, FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	get_tree().quit()


## 1.12 vehicle doors, cargo, map state and two extra drivable motorhomes.
func _v112() -> void:
	var w = Game.world
	var before := Game.map_mode
	var pl = Game.player
	Game.map_mode = "everything"
	_check_quality(Game.map_mode == "everything", "Everything selection state is available")
	var types := ["pickup", "sedan", "box_truck", "offroader", "mini_rv", "mid_rv"]
	for i in range(types.size()):
		var kind: String = types[i]
		var z: float = -100.0 - float(i) * 11.0
		var x: float = w.gen.road_x(z)
		var v = w.spawn_vehicle("quality_v112_" + kind, kind, Vector3(x, w.gen.height(x, z) + 1.3, z), Vector3.ZERO, {"fuel": 60.0, "battery": 90.0})
		_check_quality(v != null and v.get_node_or_null("Cargo") != null, "cargo component: " + kind)
		_check_quality(v._rear_gate != null and v._rear_gate_shape != null, "working rear hatch: " + kind)
		v.set_rear_open(true, false)
		_check_quality(v.rear_open and v._rear_gate.visible, "rear access opens: " + kind)
		Game.slots[0] = {"id": "scrap", "n": 1}
		Game.selected_slot = 0
		v.cargo_store()
		_check_quality(w.cargo_records(v).size() == 1, "real physical item stored: " + kind)
		var saved: Dictionary = v.save_state()
		_check_quality(saved["rear_open"] and saved["cargo"].size() == 1, "cargo/door persisted: " + kind)
		v.set_rear_open(false, false)
		_check_quality(not v.rear_open, "rear access closes: " + kind)
		v.cargo_store()
		_check_quality(v.rear_open, "cargo interaction opens rear access: " + kind)
	var a = w.vehicle_nodes["quality_v112_box_truck"]
	_player_at(a.global_position + Vector3(3, 0.2, -5), -0.4)
	await _settle(a.global_position)
	_look_at_point(a.global_position + Vector3(0, 1.8, 0))
	await _wait(0.5)
	await _shot("quality_everything_garage")
	var state: Dictionary = load("res://scripts/rv.gd").complete_starter_state()
	_check_quality(state["modules"].has("bed") and state["modules"].has("engine") and state["missing"].is_empty(), "big RV fully furnished and drivable")
	Game.map_mode = before
