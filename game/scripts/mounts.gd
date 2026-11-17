extends RefCounted
## Physical part replacement shared by the motorhome and every car.
## You don't repair from a menu: pull the worn battery or tire out with an empty hand (it lands
## in your hands as a real object), then carry the replacement over and fit it in that spot.
## Engine parts and scrap are worked in at the open hood. Tires, engine and body need a toolkit
## carried or lying within reach.

const Data = preload("res://scripts/data.gd")

static func _toolkit() -> bool:
	return Game.has_flag("toolkit")

static func _tk_hint() -> String:
	return "" if _toolkit() else "  (needs a Toolkit in hand or within reach)"

const TIRES := ["tire", "offroad_tire", "worn_tire"]

static func prompt(v: Node, action: String) -> String:
	var held := Game.equipped()
	var parts: Dictionary = v.parts
	if action == "battery":
		if v.missing.has("battery"):
			if held in ["car_battery", "worn_battery"]:
				return "[E] Fit the %s" % Data.item_name(held)
			return "Battery tray — empty. Carry a Car Battery here"
		if held == "":
			return "Battery %d%%   [G] Pull it out" % int(parts["battery"])
		return "Battery %d%%" % int(parts["battery"])
	if action == "hood":
		if held == "engine_parts":
			return "[E] Rebuild the engine with Engine Parts (engine %d%%)%s" % [int(parts["engine"]), _tk_hint()]
		if held == "scrap":
			return "[E] Weld Scrap Metal onto the body (body %d%%)%s" % [int(parts["body"]), _tk_hint()]
		if held == "duct_tape":
			return "[E] Patch the body with Duct Tape (body %d%%)" % int(parts["body"])
		return ""
	if action.begins_with("wheel"):
		if v.missing.has(action):
			if held in TIRES:
				return "[E] Fit the %s%s" % [Data.item_name(held), _tk_hint()]
			return "Bare wheel hub — carry a Spare Tire, Worn Tire or Off-Road Tire here"
		if held == "":
			return "Tire fitted (tires %d%%)   [G] Pull it off%s" % [int(parts["tires"]), _tk_hint()]
		return "Tire fitted (tires %d%%)" % int(parts["tires"])
	return ""

## Returns true when the action was handled here. [E] only ever fits parts; pulling a fitted
## battery or tire back off is [G] with empty hands (see pull), so it can't happen by accident.
static func act(v: Node, action: String) -> bool:
	var held := Game.equipped()
	var parts: Dictionary = v.parts
	if action == "battery":
		if v.missing.has("battery"):
			if held not in ["car_battery", "worn_battery"]:
				Game.notify("Carry a Car Battery in your hands to fit it here")
				return true
			Game.remove_item(held, 1)
			v.missing.erase("battery")
			parts["battery"] = 100.0 if held == "car_battery" else 25.0
			v.battery = parts["battery"]
			Audio.play_at("hammer", v.global_position, -4.0, 1.3)
			Game.notify("Battery fitted" if held == "car_battery" else "Dead battery fitted — it holds a little charge")
			v._apply_visuals()
		else:
			Game.notify("Battery %d%% — [G] with empty hands pulls it out" % int(parts["battery"]))
		return true
	if action == "hood":
		if held == "duct_tape":
			if parts["body"] >= 99.9:
				Game.notify("The body is in perfect shape")
				return true
			Game.remove_item("duct_tape", 1)
			parts["body"] = minf(parts["body"] + 8.0, 100.0)
			Audio.play_at("click", v.global_position, -2.0, 0.6)
			Game.notify("Taped up — body now %d%%" % int(parts["body"]))
			v._apply_visuals()
			return true
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
		if not v.missing.has(action):
			Game.notify("Tire fitted (tires %d%%) — [G] with empty hands pulls it off" % int(parts["tires"]))
			return true
		if held not in TIRES:
			Game.notify("Carry a Spare Tire in your hands to fit it here")
			return true
		if not _toolkit():
			Game.notify("You need a Toolkit in hand or lying within reach to work on wheels")
			return true
		var kinds = v.get("wheel_kind")
		Game.remove_item(held, 1)
		v.missing.erase(action)
		if kinds != null:
			if held == "offroad_tire":
				kinds[action] = "offroad_tire"
			else:
				kinds.erase(action)
		parts["tires"] = minf(parts["tires"] + (5.0 if held == "worn_tire" else 15.0), 100.0)
		Audio.play_at("hammer", v.global_position, -2.0, 0.9)
		Game.notify("%s fitted — tires now %d%%" % [Data.item_name(held), int(parts["tires"])])
		v._apply_visuals()
		return true
	return false

## [G] with empty hands at a fitted battery or tire: take it off into your hands.
static func pull(v: Node, action: String) -> bool:
	var parts: Dictionary = v.parts
	if Game.equipped() != "":
		Game.notify("You need an empty hand to take that off")
		return true
	if action == "battery":
		if v.missing.has("battery"):
			return false
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
	if action.begins_with("wheel"):
		if v.missing.has(action):
			return false
		if not _toolkit():
			Game.notify("You need a Toolkit in hand or lying within reach to work on wheels")
			return true
		var kinds = v.get("wheel_kind")
		# a tire comes off as good as the set it belongs to; a worn one can still be refitted
		var item := "tire" if parts["tires"] >= 60.0 else "worn_tire"
		if kinds != null and kinds.get(action, "") == "offroad_tire" and parts["tires"] >= 50.0:
			item = "offroad_tire"
		Game.add_item(item, 1, true)
		parts["tires"] = maxf(parts["tires"] - 15.0, 0.0)
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
		# on a bare hub the vehicle sits down on its brake drums
		if not w.has_meta("radius"):
			w.set_meta("radius", w.wheel_radius)
		w.wheel_radius = float(w.get_meta("radius")) * (0.45 if gone else 1.0)
		var kinds = v.get("wheel_kind")
		var knob: bool = kinds != null and kinds.get("wheel%d" % i, "") == "offroad_tire"
		var tm = w.get_meta("tire_mesh") if w.has_meta("tire_mesh") else null
		if tm:
			tm.visible = not gone and not knob
		var km = w.get_meta("knobby_mesh") if w.has_meta("knobby_mesh") else null
		if km:
			km.visible = not gone and knob
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

## Car hoods: fit upgrade parts, spray paint, or check the car over.
static func car_hood(v: Node) -> bool:
	var held := Game.equipped()
	if Data.CAR_UPGRADE_ITEMS.has(held):
		var up: String = Data.CAR_UPGRADE_ITEMS[held]
		if v.upgrades.has(up):
			Game.notify("Already fitted")
			return true
		if not _toolkit():
			Game.notify("You need a Toolkit in hand or lying within reach")
			return true
		Game.remove_item(held, 1)
		v.upgrades[up] = true
		Audio.play_at("hammer", v.global_position)
		Game.notify("Fitted: %s" % Data.RV_UPGRADES[up]["name"])
		v._apply_visuals()
		return true
	if held == "paint_can":
		Game.remove_item("paint_can", 1)
		v.set_paint((int(v.paint) + 1) % v.paint_palette().size())
		Audio.play_at("splash", v.global_position, -6.0, 1.8)
		Game.notify("Fresh paint!")
		return true
	var p: Dictionary = v.parts
	Game.notify("%s: engine %d%% · tires %d%% · body %d%% · battery %d%% · fuel %d L" % [v.display_name(), int(p["engine"]), int(p["tires"]), int(p["body"]), int(v.battery), int(v.fuel)])
	return true

static func car_hood_prompt(v: Node) -> String:
	var held := Game.equipped()
	if Data.CAR_UPGRADE_ITEMS.has(held):
		return "[E] Fit the %s%s" % [Data.item_name(held), _tk_hint()]
	if held == "paint_can":
		return "[E] Spray-paint the %s" % v.display_name()
	return "[E] Check the %s over (hold Engine Parts or Scrap to repair, or an upgrade part to fit it)" % v.display_name()
