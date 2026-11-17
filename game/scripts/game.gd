extends Node
## Global game state, settings, input map and save/load. Autoloaded as "Game".

const Data = preload("res://scripts/data.gd")
const WorldItem = preload("res://scripts/world_item.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"
const DAY_LENGTH := 1440.0 # real seconds per in-game day (24 minutes)

signal inventory_changed
signal notified(text: String)
signal hotbar_changed

var world: Node3D
var player: CharacterBody3D
var rv: VehicleBody3D

var settings := {
	"master": 0.9, "sfx": 0.9, "ambience": 0.8, "vehicle": 0.8, "ui": 0.8,
	"sensitivity": 0.25, "invert_y": false, "fov": 75.0, "head_bob": true,
	"view_distance": 2, "shadows": true, "grass": true, "render_scale": 1.0,
	"touch_controls": "auto", "touch_size": 1.0, "show_fps": false,
}

# --- Runtime/saved state ---
var seed_value := 1234
var difficulty := "Normal"
var time_of_day := 8.0 # hours 0..24
var day := 1
var weather := "clear"
var slots: Array = [] # hand/backpack slots: {"id", "n", optional "c": contents of a carried crate}
var worn := {} # jacket, backpack, flashlight
var selected_slot := 0
var stats := {"health": 100.0, "food": 80.0, "water": 80.0, "energy": 90.0, "warmth": 100.0}
var structures := {} # id -> {type, pos:[x,y,z], rot, level, base_y, data:{}}
var removed := {} # resource keys removed from the world (trees, rocks, loot)
var spawn_point = null # Vector3 of last slept bed/tent
var next_struct_id := 1
var rv_state := {}
var vehicles := {} # id -> saved state of cars and trailers
var journey := preload("res://scripts/journey.gd").new()
var playing := false
var paused := false
var ui_open := false
var god_mode := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_setup_buses()
	load_settings()

# ---------------------------------------------------------------- input map
func _key(action: String, keys: Array, pads: Array = [], axes: Array = [], mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in pads:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = a[0]
		m.axis_value = a[1]
		InputMap.action_add_event(action, m)
	for mb in mouse:
		var me := InputEventMouseButton.new()
		me.button_index = mb
		InputMap.action_add_event(action, me)

func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_key("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_key("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_key("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_key("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_key("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_key("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_key("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_key("jump", [KEY_SPACE], [JOY_BUTTON_A])
	_key("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	_key("interact", [KEY_E], [JOY_BUTTON_X])
	_key("primary", [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [MOUSE_BUTTON_LEFT])
	_key("secondary", [], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [MOUSE_BUTTON_RIGHT])
	_key("inventory", [KEY_TAB, KEY_I], [JOY_BUTTON_Y])
	_key("rotate", [KEY_R], [JOY_BUTTON_DPAD_UP])
	_key("build_menu", [KEY_B], [JOY_BUTTON_DPAD_DOWN])
	_key("hotbar_next", [], [JOY_BUTTON_RIGHT_SHOULDER], [], [MOUSE_BUTTON_WHEEL_DOWN])
	_key("hotbar_prev", [], [JOY_BUTTON_LEFT_SHOULDER], [], [MOUSE_BUTTON_WHEEL_UP])
	_key("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_key("camera", [KEY_C], [JOY_BUTTON_BACK])
	_key("lights", [KEY_L], [JOY_BUTTON_DPAD_LEFT])
	_key("flashlight", [KEY_F], [JOY_BUTTON_DPAD_RIGHT])
	_key("crouch", [KEY_CTRL], [JOY_BUTTON_RIGHT_STICK])
	_key("pickup", [KEY_G], [JOY_BUTTON_B]) # place the held item / grab placed furniture
	_key("drop", [KEY_Q], [JOY_BUTTON_MISC1]) # throw the held item
	for i in range(10): # 1-9 and 0: up to five hand slots plus an expedition pack's five
		_key("slot_%d" % (i + 1), [KEY_1 + i if i < 9 else KEY_0])

func _setup_buses() -> void:
	for bus_name in ["SFX", "Ambience", "Vehicle", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

# ---------------------------------------------------------------- settings
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])
	apply_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)
	apply_settings()

func apply_settings() -> void:
	var map := {"Master": "master", "SFX": "sfx", "Ambience": "ambience", "Vehicle": "vehicle", "UI": "ui"}
	for bus in map:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var v: float = settings[map[bus]]
			AudioServer.set_bus_volume_db(idx, linear_to_db(max(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
	get_viewport().scaling_3d_scale = settings["render_scale"]
	if world and world.has_method("apply_settings"):
		world.apply_settings()

func use_touch() -> bool:
	match str(settings["touch_controls"]):
		"on": return true
		"off": return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

# ---------------------------------------------------------------- hands & carrying
## There is no abstract inventory: you carry a few items in hand slots (more with a backpack).
## Everything else is a physical object in the world. Crafting, cooking and repairs use what
## you carry plus anything lying within reach (NEAR) — e.g. a pile of logs next to the workbench.
const NEAR := 3.2
const BASE_SLOTS := 5

func slot_count() -> int:
	var extra := 0
	for w in worn:
		extra = maxi(extra, int(Data.ITEMS.get(w, {}).get("carry", 0)))
	return BASE_SLOTS + extra

## Total of a numeric stat over everything you wear (insulation, armor).
func worn_stat(key: String) -> float:
	var t := 0.0
	for w in worn:
		t += float(Data.ITEMS.get(w, {}).get(key, 0.0))
	return t

func wears_flag(key: String) -> bool:
	for w in worn:
		if Data.ITEMS.get(w, {}).get(key, false):
			return true
	return false

var _flag_ids := {}
## True if anything you carry, wear or have within reach has this data flag (e.g. "toolkit",
## "builds", "butcher"): a multi-tool counts as a toolkit, a machete butchers like a knife.
func has_flag(key: String) -> bool:
	if not _flag_ids.has(key):
		var ids: Array = []
		for id in Data.ITEMS:
			if Data.ITEMS[id].get(key, false):
				ids.append(id)
		_flag_ids[key] = ids
	for id in _flag_ids[key]:
		if count(id) > 0:
			return true
	return false

func _fit_slots() -> void:
	while slots.size() < slot_count():
		slots.append({"id": "", "n": 0})
	while slots.size() > slot_count():
		var s: Dictionary = slots.pop_back()
		if s["id"] != "" and player and world:
			drop_pile(s["id"], s["n"], player.global_position + Vector3(0, 0.5, 0), s.get("c", []))
	selected_slot = clampi(selected_slot, 0, slots.size() - 1)

func _empty_slot(i: int) -> void:
	slots[i] = {"id": "", "n": 0}

func carried(id: String) -> int:
	var n := 0
	for s in slots:
		if s["id"] == id:
			n += int(s["n"])
	return n

func hands_full_for(id: String) -> bool:
	return space_for(id) <= 0

func space_for(id: String) -> int:
	var lim := Data.stack(id)
	var room := 0
	for s in slots:
		if s["id"] == "":
			room += lim
		elif s["id"] == id and not s.has("c"):
			room += maxi(lim - int(s["n"]), 0)
	return room

var _near_cache := {}
var _near_frame := -1

## Loose items lying within reach of the player (in the world or glued inside a vehicle).
func nearby_items(id := "") -> Array:
	var out := []
	if world == null or player == null:
		return out
	var p := player.global_position + Vector3(0, 0.8, 0)
	for it in world.get_tree().get_nodes_in_group("world_item"):
		if is_instance_valid(it) and not it.is_queued_for_deletion() and (id == "" or it.id == id) and it.global_position.distance_to(p) < NEAR:
			out.append(it)
	out.sort_custom(func(a, b): return a.global_position.distance_squared_to(p) < b.global_position.distance_squared_to(p))
	return out

func nearby(id: String) -> int:
	var f := Engine.get_physics_frames()
	if f != _near_frame:
		_near_frame = f
		_near_cache = {}
		for it in nearby_items():
			_near_cache[it.id] = int(_near_cache.get(it.id, 0)) + int(it.amount)
	return int(_near_cache.get(id, 0))

## Everything usable right now: what you carry, wear, and what lies within reach.
func count(id: String) -> int:
	if world == null:
		return carried(id)
	return carried(id) + nearby(id) + (1 if worn.has(id) else 0)

## Put items into your hands. What doesn't fit is dropped in front of you as a physical pile.
func add_item(id: String, n: int = 1, quiet := false) -> void:
	if n <= 0:
		return
	var left := n
	var lim := Data.stack(id)
	for i in range(slots.size()):
		if left > 0 and slots[i]["id"] == id and not slots[i].has("c") and int(slots[i]["n"]) < lim:
			var k := mini(lim - int(slots[i]["n"]), left)
			slots[i]["n"] = int(slots[i]["n"]) + k
			left -= k
	var order := [selected_slot]
	for i in range(slots.size()):
		if i != selected_slot:
			order.append(i)
	for i in order:
		if left > 0 and slots[i]["id"] == "":
			var k := mini(lim, left)
			slots[i] = {"id": id, "n": k}
			left -= k
	if left > 0 and player and world:
		var fwd: Vector3 = -player.camera.global_transform.basis.z * Vector3(1, 0, 1)
		drop_pile(id, left, player.global_position + fwd.normalized() * 0.7 + Vector3(0, 0.6, 0))
		if not quiet:
			notify("Hands full — %d %s set down at your feet" % [left, Data.item_name(id)])
	if not quiet and left < n:
		notify("+%d %s" % [n - left, Data.item_name(id)])
	_changed()

func _changed() -> void:
	_near_frame = -1
	inventory_changed.emit()
	hotbar_changed.emit()

## Use up items: from your hands first, then from items lying within reach.
func remove_item(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	var left := n
	if worn.has(id) and carried(id) + nearby(id) < n:
		worn.erase(id)
		left -= 1
	for i in range(slots.size() - 1, -1, -1):
		if left > 0 and slots[i]["id"] == id:
			var k := mini(int(slots[i]["n"]), left)
			slots[i]["n"] = int(slots[i]["n"]) - k
			left -= k
			if int(slots[i]["n"]) <= 0:
				_empty_slot(i)
	if left > 0:
		for it in nearby_items(id):
			if left <= 0:
				break
			var k := mini(int(it.amount), left)
			it.amount -= k
			left -= k
			if it.amount <= 0:
				it.queue_free()
	_changed()
	return true

func has_cost(cost: Dictionary) -> bool:
	for k in cost:
		if count(k) < int(cost[k]):
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not has_cost(cost):
		return false
	for k in cost:
		remove_item(k, int(cost[k]))
	return true

func held() -> Dictionary:
	if selected_slot < 0 or selected_slot >= slots.size():
		return {"id": "", "n": 0}
	return slots[selected_slot]

func equipped() -> String:
	return str(held()["id"])

## Take the item out of the selected hand slot (for placing or throwing it).
func take_held() -> Dictionary:
	var s := held().duplicate(true)
	if s["id"] != "":
		_empty_slot(selected_slot)
		_changed()
	return s

func select_slot(i: int) -> void:
	selected_slot = wrapi(i, 0, slots.size())
	hotbar_changed.emit()

## Pick a physical item up into your hands (as much of the pile as fits).
func pick_up(it: Node) -> bool:
	var id: String = it.id
	var room := space_for(id)
	if room <= 0:
		notify("Your hands are full — place [G] or drop [Q] something first")
		Audio.play("click", -6.0)
		return false
	var k := mini(room, int(it.amount))
	it.amount -= k
	add_item(id, k, true)
	# what you just picked up is what you're now holding
	if equipped() != id:
		for i in range(slots.size()):
			if slots[i]["id"] == id:
				select_slot(i)
				break
	notify("Picked up %s%s" % [Data.item_name(id), (" ×%d" % k) if k > 1 else ""])
	if it.amount <= 0:
		it.queue_free()
	return true

## Put on wearables (jacket, backpack, flashlight) so they stop taking up a hand.
func wear(id: String) -> bool:
	if worn.has(id) or not (Data.ITEMS.get(id, {}).get("kind", "") == "wear" or id == "flashlight"):
		return false
	if carried(id) <= 0:
		return false
	for i in range(slots.size()):
		if slots[i]["id"] == id:
			slots[i]["n"] = int(slots[i]["n"]) - 1
			if slots[i]["n"] <= 0:
				_empty_slot(i)
			break
	# one thing per body slot: what was there comes off into your hands
	var body_slot: String = Data.ITEMS[id].get("slot", "")
	if body_slot != "":
		for w in worn.keys():
			if Data.ITEMS.get(w, {}).get("slot", "") == body_slot:
				worn.erase(w)
				_fit_slots()
				add_item(w, 1, true)
	worn[id] = true
	_fit_slots()
	notify("You put on the %s" % Data.item_name(id))
	Audio.play("pickup", -4.0)
	_changed()
	return true

func take_off(id: String) -> void:
	if not worn.has(id):
		return
	worn.erase(id)
	_fit_slots()
	add_item(id, 1, true)
	_changed()

func notify(text: String) -> void:
	notified.emit(text)

func diff(key: String) -> float:
	return float(Data.DIFFICULTY[difficulty][key])

# ---------------------------------------------------------------- consume
func consume(id: String) -> bool:
	var it: Dictionary = Data.ITEMS.get(id, {})
	if it.is_empty() or not (it["kind"] in ["food", "medical"]):
		if not it.is_empty() and it["kind"] == "purify":
			return purify_water()
		return false
	var in_hand := carried(id) > 0
	if not remove_item(id, 1):
		return false
	if in_hand and Data.LEAVES.has(id):
		add_item(Data.LEAVES[id], 1, true)
	stats["food"] = clamp(stats["food"] + it.get("food", 0), 0, 100)
	stats["water"] = clamp(stats["water"] + it.get("water", 0), 0, 100)
	stats["health"] = clamp(stats["health"] + it.get("health", 0), 0, 100)
	stats["energy"] = clamp(stats["energy"] + it.get("energy", 0), 0, 100)
	stats["warmth"] = clamp(stats["warmth"] + it.get("warmth", 0), 0, 100)
	Audio.play("eat")
	notify("%s %s" % ["Drank" if id in Data.DRINKS else "Ate", Data.item_name(id)] if it["kind"] == "food" else "Used %s" % Data.item_name(id))
	return true

## Purification tablets: drop one into the dirty water you're carrying (or that lies within reach).
func purify_water() -> bool:
	var n := mini(count("water_dirty"), 3)
	if n <= 0:
		notify("Hold or set down Dirty Water first, then use a tablet on it")
		return false
	if not remove_item("water_purification_tablets", 1):
		return false
	remove_item("water_dirty", n)
	add_item("water_clean", n, true)
	Audio.play("click", -6.0, 1.4)
	notify("The tablet fizzes: %d bottle%s of clean water" % [n, "s" if n > 1 else ""])
	return true

# ---------------------------------------------------------------- new / save / load
func new_game(seed_in: int, diff_in: String) -> void:
	journey.reset()
	seed_value = seed_in
	difficulty = diff_in
	time_of_day = 8.0
	day = 1
	weather = "clear"
	# A rough start: a pocket knife in hand and a flashlight clipped on. The stripped van and the
	# parts to get it going lie around the starting lot (see world.gd); the rest is scavenged.
	worn = {"flashlight": true, "nav_wristwatch": true}
	slots = [{"id": "knife", "n": 1}]
	selected_slot = 0
	_fit_slots()
	stats = {"health": 100.0, "food": 80.0, "water": 80.0, "energy": 90.0, "warmth": 100.0}
	structures = {}
	removed = {}
	spawn_point = null
	next_struct_id = 1
	rv_state = {}
	pending_items = []
	vehicles = {}

func has_save() -> bool:
	return not SaveStore.recover(SAVE_PATH).is_empty()

func v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func world_snapshot() -> Dictionary:
	return {
		"seed": seed_value, "difficulty": difficulty, "time": time_of_day, "day": day,
		"weather": weather, "structures": structures, "removed": removed, "next_id": next_struct_id,
		"rv": rv.save_state() if rv else rv_state,
		"items": _loose_items(),
		"vehicles": world.vehicle_states() if world else vehicles,
	}

var pending_items: Array = []
var legacy_inventory := {}

func _loose_items() -> Array:
	var out := []
	if world == null:
		return pending_items
	for it in world.get_tree().get_nodes_in_group("world_item"):
		if is_instance_valid(it) and it.get_parent() == world:
			out.append(it.save_record())
	return out

func apply_world_snapshot(d: Dictionary) -> void:
	seed_value = int(d["seed"])
	difficulty = str(d.get("difficulty", "Normal"))
	time_of_day = float(d.get("time", 8.0))
	day = int(d.get("day", 1))
	weather = str(d.get("weather", "clear"))
	structures = {}
	var s: Dictionary = d.get("structures", {})
	for k in s:
		structures[str(k)] = s[k]
	removed = d.get("removed", {})
	next_struct_id = int(d.get("next_id", 1))
	rv_state = d.get("rv", {})
	pending_items = d.get("items", [])
	vehicles = d.get("vehicles", {})

func save_game() -> bool:
	if not playing or not world:
		return false
	var d := world_snapshot()
	d["journey_completed"] = journey.completed
	d["version"] = 1
	d["v17"] = true
	d["slots"] = slots
	d["worn"] = worn
	d["stats"] = stats
	d["player"] = arr(player.global_position) if player else [0, 5, 0]
	d["player_yaw"] = player.rotation.y if player else 0.0
	d["in_rv"] = player.driving if player else false
	d["spawn"] = arr(spawn_point) if spawn_point != null else null
	if not SaveStore.write(SAVE_PATH, d):
		notify("Could not save game — previous save kept")
		return false
	notify("Game saved")
	return true

func load_game_data() -> Dictionary:
	var d := SaveStore.recover(SAVE_PATH)
	if d.is_empty():
		return {}
	apply_world_snapshot(d)
	journey.reset()
	journey.restore(d.get("journey_completed", 0))
	worn = d.get("worn", {})
	if not d.has("v17"):
		worn["nav_wristwatch"] = true # saves from before 1.7 always showed the exact time
	slots = []
	for s in d.get("slots", []):
		var rec := {"id": str(s.get("id", "")), "n": int(s.get("n", 0))}
		if s.has("c"):
			rec["c"] = s["c"]
		slots.append(rec)
	_fit_slots()
	# saves from before 1.3 had an abstract inventory: it becomes a pile next to you
	legacy_inventory = d.get("inventory", {})
	if d.has("inventory") and not d.has("slots"):
		worn = {"flashlight": true} if int(legacy_inventory.get("flashlight", 0)) > 0 else {}
		for k in ["jacket", "backpack"]:
			if int(legacy_inventory.get(k, 0)) > 0:
				worn[k] = true
		_fit_slots()
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = float(st[k])
	spawn_point = v3(d["spawn"]) if d.get("spawn") != null else null
	return d

## Drop a physical item into the world.
func spawn_item(id: String, n: int, pos: Vector3, impulse := Vector3.ZERO) -> Node:
	if world == null:
		return null
	var it := RigidBody3D.new()
	it.set_script(WorldItem)
	it.setup(id, n)
	world.add_child(it)
	it.global_position = pos
	it.rotation.y = randf() * TAU
	if impulse != Vector3.ZERO:
		it.apply_central_impulse(impulse)
	return it

## Drop a pile of items near a spot (harvest, butchering, overflow), split into hand-sized piles.
func drop_pile(id: String, n: int, pos: Vector3, contents: Array = []) -> void:
	var lim := maxi(Data.stack(id), 1)
	var piles := 0
	while n > 0 and piles < 8:
		var k := mini(n, lim * 2)
		var off := Vector3(randf_range(-0.35, 0.35), piles * 0.15, randf_range(-0.35, 0.35))
		var it := spawn_item(id, k, pos + off)
		if it and not contents.is_empty():
			it.contents = contents
			contents = []
		n -= k
		piles += 1

## Place an item exactly (it stays put). host: a vehicle/trailer to glue it to, or null for the world.
func place_item(id: String, n: int, xf: Transform3D, host: Node = null, contents: Array = []) -> Node:
	if world == null:
		return null
	var it := RigidBody3D.new()
	it.set_script(WorldItem)
	it.setup(id, n)
	it.contents = contents
	world.add_child(it)
	it.global_transform = xf
	it.settle(host)
	return it

func new_struct_id() -> String:
	var id := "%d_%d" % [Net.my_id(), next_struct_id]
	next_struct_id += 1
	return id
