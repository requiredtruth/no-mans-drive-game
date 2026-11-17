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
	rv.do_action("battery", pl)
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
	rv.do_action("wheel0", pl)
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

func _run() -> void:
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
