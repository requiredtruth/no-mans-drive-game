extends StaticBody3D
## A searchable container or utility at a roadside location (loot, fuel pump, well, bed).

const Data = preload("res://scripts/data.gd")

const TABLES := {
	"medical": [["bandage", 1, 3], ["medkit", 1, 1], ["water_clean", 1, 1], ["soda", 1, 1]],
	"living": [["canned_food", 1, 2], ["cloth", 1, 3], ["rope", 1, 1], ["ammo", 2, 6], ["coffee_beans", 1, 2], ["flashlight", 1, 1]],
	"shelf": [["canned_food", 1, 3], ["soda", 1, 2], ["water_clean", 1, 3], ["coffee_beans", 1, 2], ["bandage", 1, 2], ["seeds_tomato", 1, 2]],
	"backroom": [["toolkit", 1, 1], ["engine_parts", 1, 2], ["car_battery", 1, 1], ["scrap", 2, 5], ["rope", 1, 3], ["fuel_can", 1, 1]],
	"kitchen": [["canned_food", 1, 3], ["water_clean", 1, 2], ["coffee_beans", 1, 3], ["seeds_potato", 1, 2], ["seeds_tomato", 1, 2], ["soda", 1, 2]],
	"wardrobe": [["cloth", 2, 5], ["rope", 1, 2], ["bandage", 1, 2], ["jacket", 1, 1], ["medkit", 1, 1]],
	"garage": [["scrap", 2, 6], ["toolkit", 1, 1], ["ammo", 3, 8], ["engine_parts", 1, 1], ["fuel_can", 1, 1], ["rifle", 1, 1], ["arrow", 4, 8]],
	"trunk": [["scrap", 2, 5], ["tire", 1, 1], ["fuel_can", 1, 1], ["car_battery", 1, 1], ["engine_parts", 1, 1], ["cloth", 1, 2]],
	"camp": [["rope", 1, 3], ["cloth", 1, 3], ["arrow", 3, 8], ["bow", 1, 1], ["canned_food", 1, 2], ["fishing_rod", 1, 1], ["feather", 2, 4]],
	"farm": [["seeds_potato", 1, 3], ["seeds_tomato", 1, 3], ["seeds_coffee", 1, 1], ["potato", 1, 4], ["fiber", 2, 6], ["rope", 1, 2], ["hide", 1, 2]],
	"scrap_pile": [["scrap", 3, 7], ["engine_parts", 1, 1], ["tire", 1, 1], ["cloth", 1, 2]],
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
			return "[E] Draw water from well"
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
			Game.add_item("water_dirty", 2)
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
	var entries: Array = TABLES.get(table, TABLES["shelf"])
	for i in range(maxi(rolls, 1)):
		var e: Array = entries[rng.randi() % entries.size()]
		var id: String = e[0]
		if Data.ITEMS[id]["kind"] == "tool" and (Game.count(id) > 0 or rng.randf() < 0.5):
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
		if mode == "box":
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
			Game.notify("The RV tank is already full")
			return
		rv.fuel += amount
		left -= amount
		Game.notify("Pumped %.0f L into the RV" % amount)
	else:
		var cans := mini(int(left / 10.0), 2)
		if cans <= 0:
			Game.notify("Not enough fuel left for a can")
			return
		Game.add_item("fuel_can", cans)
		left -= cans * 10.0
		Game.notify("Park the RV next to the pump to fill it directly")
	Audio.play_at("splash", global_position, -10.0, 0.6)
	Net.mark_removed(key, left)
