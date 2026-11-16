extends Node
## Global game state, settings, input map and save/load. Autoloaded as "Game".

const Data = preload("res://scripts/data.gd")
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
var inventory := {}
var hotbar: Array = ["knife", "axe", "hammer", "fishing_rod", "", ""]
var selected_slot := 0
var stats := {"health": 100.0, "food": 80.0, "water": 80.0, "energy": 90.0, "warmth": 100.0}
var structures := {} # id -> {type, pos:[x,y,z], rot, level, base_y, data:{}}
var removed := {} # resource keys removed from the world (trees, rocks, loot)
var spawn_point = null # Vector3 of last slept bed/tent
var next_struct_id := 1
var rv_state := {}
var playing := false
var paused := false
var ui_open := false

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
	for i in range(6):
		_key("slot_%d" % (i + 1), [KEY_1 + i])

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

# ---------------------------------------------------------------- inventory
func count(id: String) -> int:
	return int(inventory.get(id, 0))

func add_item(id: String, n: int = 1, quiet := false) -> void:
	if n <= 0:
		return
	inventory[id] = count(id) + n
	if Data.ITEMS.get(id, {}).get("kind", "") == "tool" and not hotbar.has(id):
		for i in range(hotbar.size()):
			if hotbar[i] == "":
				hotbar[i] = id
				hotbar_changed.emit()
				break
	if not quiet:
		notify("+%d %s" % [n, Data.item_name(id)])
	inventory_changed.emit()

func remove_item(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	inventory[id] = count(id) - n
	if inventory[id] <= 0:
		inventory.erase(id)
		var i := hotbar.find(id)
		if i >= 0 and Data.ITEMS.get(id, {}).get("kind", "") == "tool":
			hotbar[i] = ""
			hotbar_changed.emit()
	inventory_changed.emit()
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

func equipped() -> String:
	var id: String = hotbar[selected_slot]
	if id != "" and count(id) <= 0:
		return ""
	return id

func select_slot(i: int) -> void:
	selected_slot = wrapi(i, 0, hotbar.size())
	hotbar_changed.emit()

func assign_hotbar(id: String) -> void:
	var existing := hotbar.find(id)
	if existing >= 0:
		hotbar[existing] = ""
	hotbar[selected_slot] = id
	hotbar_changed.emit()

func notify(text: String) -> void:
	notified.emit(text)

func diff(key: String) -> float:
	return float(Data.DIFFICULTY[difficulty][key])

# ---------------------------------------------------------------- consume
func consume(id: String) -> bool:
	var it: Dictionary = Data.ITEMS.get(id, {})
	if it.is_empty() or not (it["kind"] in ["food", "medical"]):
		return false
	if not remove_item(id, 1):
		return false
	stats["food"] = clamp(stats["food"] + it.get("food", 0), 0, 100)
	stats["water"] = clamp(stats["water"] + it.get("water", 0), 0, 100)
	stats["health"] = clamp(stats["health"] + it.get("health", 0), 0, 100)
	stats["energy"] = clamp(stats["energy"] + it.get("energy", 0), 0, 100)
	stats["warmth"] = clamp(stats["warmth"] + it.get("warmth", 0), 0, 100)
	if id in ["tomato", "berries", "water_clean", "water_dirty", "coffee", "soda", "canned_food"]:
		pass
	Audio.play("eat")
	notify("Consumed %s" % Data.item_name(id))
	if id == "canned_food" or id == "stew":
		pass
	return true

# ---------------------------------------------------------------- new / save / load
func new_game(seed_in: int, diff_in: String) -> void:
	seed_value = seed_in
	difficulty = diff_in
	time_of_day = 8.0
	day = 1
	weather = "clear"
	inventory = {"knife": 1, "axe": 1, "hammer": 1, "fishing_rod": 1, "flashlight": 1,
		"canned_food": 3, "water_clean": 4, "wood": 10, "stone": 6, "cloth": 4, "rope": 2,
		"seeds_tomato": 2, "seeds_potato": 2, "seeds_coffee": 1, "coffee_beans": 2, "fuel_can": 1,
		"engine_parts": 1, "scrap": 4, "bandage": 2}
	hotbar = ["knife", "axe", "hammer", "fishing_rod", "flashlight", ""]
	selected_slot = 0
	stats = {"health": 100.0, "food": 80.0, "water": 80.0, "energy": 90.0, "warmth": 100.0}
	structures = {}
	removed = {}
	spawn_point = null
	next_struct_id = 1
	rv_state = {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func world_snapshot() -> Dictionary:
	return {
		"seed": seed_value, "difficulty": difficulty, "time": time_of_day, "day": day,
		"weather": weather, "structures": structures, "removed": removed, "next_id": next_struct_id,
		"rv": rv.save_state() if rv else rv_state,
	}

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

func save_game() -> bool:
	if not playing or not world:
		return false
	var d := world_snapshot()
	d["version"] = 1
	d["inventory"] = inventory
	d["hotbar"] = hotbar
	d["stats"] = stats
	d["player"] = arr(player.global_position) if player else [0, 5, 0]
	d["player_yaw"] = player.rotation.y if player else 0.0
	d["in_rv"] = player.driving if player else false
	d["spawn"] = arr(spawn_point) if spawn_point != null else null
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		notify("Could not save game")
		return false
	f.store_string(JSON.stringify(d))
	notify("Game saved")
	return true

func load_game_data() -> Dictionary:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	apply_world_snapshot(d)
	inventory = {}
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		inventory[k] = int(inv[k])
	hotbar = d.get("hotbar", hotbar)
	while hotbar.size() < 6:
		hotbar.append("")
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = float(st[k])
	spawn_point = v3(d["spawn"]) if d.get("spawn") != null else null
	return d

func new_struct_id() -> String:
	var id := "%d_%d" % [Net.my_id(), next_struct_id]
	next_struct_id += 1
	return id
