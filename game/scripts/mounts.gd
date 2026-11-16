extends RefCounted
## Physical part replacement shared by the motorhome and every car.
## You don't repair from a menu: pull the worn battery or tire out with an empty hand (it lands
## in your hands as a real object), then carry the replacement over and fit it in that spot.
## Engine parts and scrap are worked in at the open hood. Tires, engine and body need a toolkit
## carried or lying within reach.

const Data = preload("res://scripts/data.gd")

static func _toolkit() -> bool:
	return Game.count("toolkit") > 0

static func _tk_hint() -> String:
	return "" if _toolkit() else "  (needs a Toolkit in hand or within reach)"

static func prompt(v: Node, action: String) -> String:
	var held := Game.equipped()
	var parts: Dictionary = v.parts
	if action == "battery":
		if v.missing.has("battery"):
			if held == "car_battery":
				return "[E] Fit the Car Battery"
			return "Battery tray — empty. Carry a Car Battery here"
		if held == "car_battery":
			return "Battery (%d%%) — pull the old one out first with an empty hand" % int(parts["battery"])
		return "[E] Pull out the battery (%d%%)" % int(parts["battery"])
	if action == "hood":
		if held == "engine_parts":
			return "[E] Rebuild the engine with Engine Parts (engine %d%%)%s" % [int(parts["engine"]), _tk_hint()]
		if held == "scrap":
			return "[E] Weld Scrap Metal onto the body (body %d%%)%s" % [int(parts["body"]), _tk_hint()]
		return ""
	if action.begins_with("wheel"):
		if v.missing.has(action):
			if held == "tire":
				return "[E] Fit the Spare Tire%s" % _tk_hint()
			return "Bare wheel hub — carry a Spare Tire here"
		if held == "tire":
			return "Tires %d%% — pull this one off first with an empty hand" % int(parts["tires"])
		return "[E] Pull off this tire (tires %d%%)%s" % [int(parts["tires"]), _tk_hint()]
	return ""

## Returns true when the action was handled here.
static func act(v: Node, action: String) -> bool:
	var held := Game.equipped()
	var parts: Dictionary = v.parts
	if action == "battery":
		if v.missing.has("battery"):
			if held != "car_battery":
				Game.notify("Carry a Car Battery in your hands to fit it here")
				return true
			Game.remove_item("car_battery", 1)
			v.missing.erase("battery")
			parts["battery"] = 100.0
			v.battery = 100.0
			Audio.play_at("hammer", v.global_position, -4.0, 1.3)
			Game.notify("Battery fitted")
		else:
			if held != "":
				Game.notify("You need an empty hand to pull the battery out")
				return true
			var item := "car_battery" if parts["battery"] >= 70.0 else "worn_battery"
			Game.add_item(item, 1, true)
			v.missing["battery"] = true
			parts["battery"] = 0.0
			v.battery = 0.0
			if v.engine_on:
				v.stop_engine()
			Audio.play_at("click", v.global_position, 0.0, 0.6)
			Game.notify("You pulled out the %s" % Data.item_name(item))
		v._apply_visuals()
		return true
	if action == "hood":
		if held == "engine_parts" or held == "scrap":
			if not _toolkit():
				Game.notify("You need a Toolkit in hand or lying within reach")
				return true
			var part := "engine" if held == "engine_parts" else "body"
			if parts[part] >= 99.9:
				Game.notify("The %s is in perfect shape" % part)
				return true
			Game.remove_item(held, 1)
			parts[part] = minf(parts[part] + float(Data.RV_PARTS[part]["amount"]), 100.0)
			Audio.play_at("hammer", v.global_position)
			Game.notify("%s now %d%%" % [Data.RV_PARTS[part]["name"], int(parts[part])])
			v._apply_visuals()
			return true
		return false
	if action.begins_with("wheel"):
		if not _toolkit():
			Game.notify("You need a Toolkit in hand or lying within reach to work on wheels")
			return true
		if v.missing.has(action):
			if held != "tire":
				Game.notify("Carry a Spare Tire in your hands to fit it here")
				return true
			Game.remove_item("tire", 1)
			v.missing.erase(action)
			parts["tires"] = minf(parts["tires"] + 25.0, 100.0)
			Audio.play_at("hammer", v.global_position, -2.0, 0.9)
			Game.notify("Tire fitted — tires now %d%%" % int(parts["tires"]))
		else:
			if held != "":
				Game.notify("You need an empty hand to pull the tire off")
				return true
			var item := "tire" if parts["tires"] >= 90.0 else "worn_tire"
			Game.add_item(item, 1, true)
			parts["tires"] = maxf(parts["tires"] - parts["tires"] * 0.25, 0.0)
			v.missing[action] = true
			Audio.play_at("hammer", v.global_position, -2.0, 0.7)
			Game.notify("You pulled off a %s" % Data.item_name(item))
		v._apply_visuals()
		return true
	return false

## Wheel visuals and grip for missing tires.
static func apply_wheels(v: Node, grip: float) -> void:
	for i in range(v.wheels.size()):
		var w: VehicleWheel3D = v.wheels[i]
		var gone: bool = v.missing.has("wheel%d" % i)
		w.wheel_friction_slip = grip * (0.25 if gone else 1.0)
		var tm = w.get_meta("tire_mesh") if w.has_meta("tire_mesh") else null
		if tm:
			tm.visible = not gone
		var hub = w.get_meta("hub_mesh") if w.has_meta("hub_mesh") else null
		if hub:
			hub.visible = gone

static func missing_count(v: Node) -> int:
	var n := 0
	for k in v.missing:
		if str(k).begins_with("wheel"):
			n += 1
	return n

static func hub(holder: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.17
	cm.height = 0.1
	mi.mesh = cm
	mi.material_override = Items.dark_steel()
	mi.visible = false
	holder.add_child(mi)
	return mi
