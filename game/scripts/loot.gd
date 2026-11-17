extends StaticBody3D
## A searchable container or utility at a roadside location (loot, fuel pump, well, bed).

const Data = preload("res://scripts/data.gd")

const TABLES := {
	"medical": [["bandage", 1, 3], ["medkit", 1, 1], ["water_clean", 1, 1], ["soda", 1, 1], ["bottle_empty", 1, 2], ["painkillers", 1, 2]],
	"living": [["canned_food", 1, 2], ["cloth", 1, 3], ["rope", 1, 1], ["ammo", 2, 6], ["coffee_beans", 1, 2], ["flashlight", 1, 1],
		["radio", 1, 1], ["ceiling_light", 1, 1], ["foam", 1, 2], ["glass", 1, 1], ["dinette_kit", 1, 1], ["mattress", 1, 1],
		["chips", 1, 2], ["binoculars", 1, 1], ["floor_lamp", 1, 1], ["rug", 1, 1], ["potted_plant", 1, 1], ["sofa", 1, 1], ["shelf_unit", 1, 1], ["chair", 1, 1]],
	"shelf": [["canned_food", 1, 3], ["soda", 1, 2], ["water_clean", 1, 3], ["coffee_beans", 1, 2], ["bandage", 1, 2], ["seeds_tomato", 1, 2],
		["bottle_empty", 1, 2], ["paint_can", 1, 1], ["chips", 1, 3], ["energy_bar", 1, 3], ["jerky", 1, 2], ["instant_noodles", 1, 3],
		["bread", 1, 1], ["apple", 1, 3], ["painkillers", 1, 1], ["duct_tape", 1, 1],
		["tinned_hotdogs", 1, 2], ["can_of_cashews", 1, 2], ["peaches_oreilly", 1, 2], ["berry_juice", 1, 2], ["mocha_cola", 1, 2],
		["emergency_ration_pack", 1, 1], ["jason_s_choccy_block", 1, 2]],
	"backroom": [["toolkit", 1, 1], ["engine_parts", 1, 2], ["car_battery", 1, 1], ["scrap", 2, 5], ["rope", 1, 3], ["fuel_can", 1, 1],
		["wire", 1, 3], ["bolts", 3, 8], ["pipe", 1, 2], ["fuel_can_empty", 1, 1], ["headlight", 1, 1], ["water_tank", 1, 1], ["tune_kit", 1, 1],
		["duct_tape", 1, 2], ["crowbar", 1, 1], ["tire", 1, 1]],
	"kitchen": [["canned_food", 1, 3], ["water_clean", 1, 2], ["coffee_beans", 1, 3], ["seeds_potato", 1, 2], ["seeds_tomato", 1, 2], ["soda", 1, 2],
		["stove_unit", 1, 1], ["sink_unit", 1, 1], ["coffee_maker", 1, 1], ["fridge_unit", 1, 1], ["kitchen_unit", 1, 1], ["bottle_empty", 1, 2], ["glass", 1, 1],
		["bread", 1, 1], ["apple", 1, 3], ["instant_noodles", 1, 2], ["chips", 1, 1], ["table", 1, 1], ["tinned_hotdogs", 1, 1], ["peaches_oreilly", 1, 1], ["berry_juice", 1, 1]],
	"wardrobe": [["cloth", 2, 5], ["rope", 1, 2], ["bandage", 1, 2], ["jacket", 1, 1], ["medkit", 1, 1], ["foam", 1, 3], ["mattress", 1, 1],
		["cupboard_unit", 1, 1], ["overhead_unit", 1, 1], ["bed_frame", 1, 1], ["rug", 1, 1]],
	"garage": [["scrap", 2, 6], ["toolkit", 1, 1], ["ammo", 3, 8], ["engine_parts", 1, 1], ["fuel_can", 1, 1], ["rifle", 1, 1], ["arrow", 4, 8],
		["bolts", 4, 8], ["wire", 1, 3], ["pipe", 1, 2], ["engine_block", 1, 1], ["car_seat", 1, 1], ["heater_unit", 1, 1], ["solar_panel", 1, 1],
		["bull_bar", 1, 1], ["fuel_tank_xl", 1, 1], ["paint_can", 1, 1], ["offroad_tire", 1, 1], ["wall_panels", 1, 1], ["floor_kit", 1, 1],
		["duct_tape", 1, 2], ["crowbar", 1, 1], ["tire", 1, 1], ["car_battery", 1, 1]],
	"trunk": [["scrap", 2, 5], ["tire", 1, 1], ["fuel_can", 1, 1], ["car_battery", 1, 1], ["engine_parts", 1, 1], ["cloth", 1, 2],
		["car_seat", 1, 1], ["steering_wheel", 1, 1], ["headlight", 1, 1], ["radio", 1, 1], ["wire", 1, 2], ["glass", 1, 1], ["fuel_can_empty", 1, 1],
		["duct_tape", 1, 1], ["energy_bar", 1, 2], ["chips", 1, 1]],
	"camp": [["rope", 1, 3], ["cloth", 1, 3], ["arrow", 3, 8], ["bow", 1, 1], ["canned_food", 1, 2], ["fishing_rod", 1, 1], ["feather", 2, 4],
		["bottle_empty", 1, 2], ["foam", 1, 2], ["toilet_unit", 1, 1], ["jerky", 1, 2], ["binoculars", 1, 1], ["chair", 1, 1]],
	"farm": [["seeds_potato", 1, 3], ["seeds_tomato", 1, 3], ["seeds_coffee", 1, 1], ["potato", 1, 4], ["fiber", 2, 6], ["rope", 1, 2], ["hide", 1, 2],
		["pipe", 1, 2], ["water_tank", 1, 1], ["bed_frame", 1, 1], ["wood", 2, 3], ["bolts", 2, 6], ["apple", 2, 5], ["bread", 1, 1]],
	"scrap_pile": [["scrap", 3, 7], ["engine_parts", 1, 1], ["tire", 1, 1], ["cloth", 1, 2], ["wire", 1, 2], ["bolts", 2, 6], ["pipe", 1, 1], ["glass", 1, 1],
		["worn_battery", 1, 1]],
}

## The house up the road from the start always has these (plus a random find or two).
const GUARANTEED := {
	"poi1_kitchen": [["kitchen_unit", 1], ["canned_food", 2], ["water_clean", 1]],
	"poi1_fridge": [["fridge_unit", 1], ["soda", 1]],
	"poi1_wardrobe": [["bed_frame", 1], ["mattress", 1], ["cloth", 2]],
	"poi1_shelf": [["cupboard_unit", 1], ["ceiling_light", 1]],
	"poi1_mbox": [["chair", 1], ["bottle_empty", 2]],
	"poi1_med": [["bandage", 2], ["medkit", 1]],
}

var key := ""
var label := "Cabinet"
var table := "shelf"
var mode := "loot" # loot | box | pump | well | bed
var flaps: Array = [] # cardboard box flaps (open when searched)

func setup(p_key: String, p_label: String, p_table: String, p_mode := "loot") -> void:
	key = p_key
	label = p_label
	table = p_table
	mode = p_mode
	collision_layer = 1

func get_prompt() -> String:
	match mode:
		"pump":
			var left := pump_left()
			if left <= 0.0:
				return "Fuel pump (dry)"
			return "[E] Use fuel pump (%d L left)" % int(left)
		"well":
			return "[E] Fill the bottle from the well" if Game.equipped() == "bottle_empty" else "Well — hold an Empty Bottle to draw water"
		"bed":
			return "[E] Sleep in old bed"
	if Game.removed.has(key):
		return "%s (searched)" % label
	if mode == "box":
		return "[E] Open %s" % label
	return "[E] Search %s" % label

func pump_left() -> float:
	return float(Game.removed.get(key, 120.0 if hash(key) % 2 == 0 else 70.0))

func interact(_player: Node) -> void:
	match mode:
		"pump":
			_pump()
			return
		"well":
			if Game.equipped() != "bottle_empty":
				Game.notify("Hold an Empty Bottle to draw water")
				return
			var k: int = mini(int(Game.held()["n"]), 3)
			Game.remove_item("bottle_empty", k)
			Game.add_item("water_dirty", k, true)
			Audio.play_at("splash", global_position, -6.0)
			return
		"bed":
			Game.world.sleep(global_position + Vector3(0, 0.6, 0))
			return
	if Game.removed.has(key):
		Game.notify("Nothing left here")
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rolls := int(round(rng.randi_range(2, 3) * Game.diff("loot")))
	var found: Array = []
	if GUARANTEED.has(key):
		found = GUARANTEED[key].duplicate(true)
		rolls = 1
	var entries: Array = TABLES.get(table, TABLES["shelf"])
	for i in range(maxi(rolls, 1)):
		var e: Array = entries[rng.randi() % entries.size()]
		var id: String = e[0]
		if Data.ITEMS[id]["kind"] == "tool" and (Game.count(id) > 0 or rng.randf() < 0.5):
			continue
		if Data.ITEMS[id]["kind"] == "module" and rng.randf() < 0.45:
			continue
		found.append([id, rng.randi_range(e[1], e[2])])
	_reveal(found, rng)
	if found.is_empty():
		Game.notify("Found nothing useful")
	else:
		Game.notify("You found something — pick it up [E]")
	Audio.play_at("door" if mode == "box" else "pickup", global_position, -6.0, 1.5)
	Net.mark_removed(key, true)

## Lay what you found out for real: inside an opened box, on top of low furniture, or on the
## floor in front of tall cupboards. Items stay where they appear until you pick them up.
func _reveal(found: Array, rng: RandomNumberGenerator) -> void:
	var size := Vector3(1, 1, 1)
	for ch in get_children():
		if ch is CollisionShape3D and ch.shape is BoxShape3D:
			size = ch.shape.size
			break
	if mode == "box":
		open_flaps(true)
		var lid := get_node_or_null("Lid")
		if lid:
			lid.set_deferred("disabled", true)
	var toward: Vector3 = to_local(Game.player.global_position) * Vector3(1, 0, 1)
	var front := Vector3(0, 0, 1) if absf(toward.z) >= absf(toward.x) else Vector3(1, 0, 0)
	if front.dot(toward) < 0.0:
		front = -front
	for i in range(found.size()):
		var id: String = found[i][0]
		var n: int = found[i][1]
		var bb: AABB = Items.display_bounds(id)
		var lp: Vector3
		var spread := (i - (found.size() - 1) * 0.5)
		var big := maxf(bb.size.x, bb.size.z) > 0.5 or bb.size.y > 0.6
		if big:
			# furniture and van parts are too big for a box or shelf: they stand in front of it
			var across0 := Vector3(front.z, 0, front.x)
			lp = front * ((size.x if front.x != 0.0 else size.z) * 0.5 + maxf(bb.size.x, bb.size.z) * 0.5 + 0.25) + across0 * spread * 0.6
		elif mode == "box":
			lp = Vector3(spread * 0.14, 0.04, rng.randf_range(-0.06, 0.06))
		elif size.y < 1.3:
			var across := Vector3(front.z, 0, front.x)
			lp = across * spread * minf(0.35, (maxf(size.x, size.z) - 0.2) / maxf(found.size(), 1)) + front * rng.randf_range(-0.05, 0.08) + Vector3(0, size.y, 0)
		else:
			var across := Vector3(front.z, 0, front.x)
			lp = front * ((size.x if front.x != 0.0 else size.z) * 0.5 + 0.3) + across * spread * 0.35
		var xf := global_transform * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), lp - Vector3(0, bb.position.y, 0))
		Game.place_item(id, n, xf)

func open_flaps(animate := false) -> void:
	for f in flaps:
		var target: float = f.get_meta("open")
		if animate:
			create_tween().tween_property(f, "rotation:" + str(f.get_meta("axis")), target, 0.35).set_trans(Tween.TRANS_BACK)
		else:
			f.set_indexed("rotation:" + str(f.get_meta("axis")), target)

func _pump() -> void:
	var left := pump_left()
	if left <= 0.0:
		Game.notify("The underground tank is empty")
		return
	var rv := Game.rv
	if rv and rv.global_position.distance_to(global_position) < 14.0:
		var need: float = rv.fuel_capacity() - rv.fuel
		var amount := minf(need, left)
		if amount < 0.5:
			Game.notify("The van's tank is already full")
			return
		rv.fuel += amount
		left -= amount
		Game.notify("Pumped %.0f L into the van" % amount)
	elif Game.equipped() == "fuel_can_empty":
		var cans := mini(int(left / 10.0), int(Game.held()["n"]))
		if cans <= 0:
			Game.notify("Not enough fuel left for a can")
			return
		Game.remove_item("fuel_can_empty", cans)
		Game.add_item("fuel_can", cans, true)
		left -= cans * 10.0
		Game.notify("Filled the fuel can. Park the van next to the pump to fill it directly.")
	else:
		Game.notify("Hold an Empty Fuel Can to fill it, or park the van next to the pump")
		return
	Audio.play_at("splash", global_position, -10.0, 0.6)
	Net.mark_removed(key, left)
