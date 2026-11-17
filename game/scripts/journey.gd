extends RefCounted
## Nine deterministic roadside destinations, tied to the world's seed.
## Completion belongs to the local traveller; it is not overwritten by co-op snapshots.
const NAMES := {"house": "Roadside house", "gas_station": "Fuel station", "wrecks": "Salvage stop", "camp_ruin": "Old campsite", "cabin": "Woodland cabin", "farm": "Farmstead", "hamlet": "Roadside hamlet", "truck_stop": "Truck stop"}
const COUNT := 9
var stops: Array[Dictionary] = []
var completed := 0
var _seed := -1

func reset() -> void:
	completed = 0
	stops.clear()
	_seed = -1

func prepare(gen: RefCounted, world_seed: int) -> void:
	if _seed == world_seed and not stops.is_empty():
		return
	_seed = world_seed
	stops.clear()
	stops.append(gen.poi_for_row(1))
	var last_row := 1
	for row in range(8, 600):
		if row - last_row < 8:
			continue
		var poi: Dictionary = gen.poi_for_row(row)
		if poi.is_empty():
			continue
		stops.append(poi)
		last_row = row
		if stops.size() == COUNT:
			break

func restore(value: Variant) -> void:
	completed = clampi(int(value), 0, COUNT) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0

func current() -> Dictionary:
	return stops[completed] if completed < stops.size() else {}

func distance_to(pos: Vector3) -> float:
	var target := current()
	if target.is_empty():
		return 0.0
	var p: Vector3 = target["pos"]
	return Vector2(p.x - pos.x, p.z - pos.z).length()

func visit(pos: Vector3) -> String:
	var target := current()
	if target.is_empty():
		return ""
	# Use the POI's actual radius, including big hamlets. Don't credit flying overhead.
	if distance_to(pos) > float(target["radius"]) + 8.0 or absf(pos.y - target["pos"].y) > 12.0:
		return ""
	completed += 1
	return "Destination %d/%d reached: %s" % [completed, COUNT, NAMES.get(target["type"], "Roadside stop")]

func title() -> String:
	var target := current()
	return "The open road is yours" if target.is_empty() else str(NAMES.get(target["type"], "Roadside stop"))

func guidance(pos: Vector3) -> String:
	if current().is_empty():
		return "Journey complete · keep exploring"
	var to: Vector3 = current()["pos"] - pos
	var bearing := wrapf(rad_to_deg(atan2(to.x, -to.z)), 0, 360)
	var cardinal: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(bearing / 45.0)) % 8]
	var metres := distance_to(pos)
	return "%s %s · %03d°" % [("%.1f km" % (metres / 1000.0)) if metres >= 1000 else ("%d m" % int(metres)), cardinal, int(bearing)]
