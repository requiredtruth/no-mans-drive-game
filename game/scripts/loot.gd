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
var mode := "loot" # loot | pump | well | bed

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
	var got := false
	var entries: Array = TABLES.get(table, TABLES["shelf"])
	for i in range(maxi(rolls, 1)):
		var e: Array = entries[rng.randi() % entries.size()]
		var id: String = e[0]
		if Data.ITEMS[id]["kind"] == "tool" and (Game.count(id) > 0 or rng.randf() < 0.5):
			continue
		var top := 1.0
		for ch in get_children():
			if ch is CollisionShape3D and ch.shape is BoxShape3D:
				top = ch.position.y + ch.shape.size.y * 0.5
		var toward: Vector3 = (Game.player.global_position - global_position) * Vector3(1, 0, 1)
		toward = toward.normalized() * 0.25 if toward.length() > 0.01 else Vector3.ZERO
		var spot := global_position + Vector3(0, top + 0.15 + i * 0.12, 0) + toward + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		Game.spawn_item(id, rng.randi_range(e[1], e[2]), spot)
		got = true
	if not got:
		Game.notify("Found nothing useful")
	else:
		Game.notify("You found something — pick it up")
	Audio.play("pickup")
	Net.mark_removed(key, true)

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
