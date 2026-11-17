extends RefCounted
## Checked replacement with one previous valid save; interrupted .tmp files are never loaded.
static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var value: Variant = parser.data
	if not value is Dictionary or not value.has("seed") or not typeof(value["seed"]) in [TYPE_INT, TYPE_FLOAT]:
		return {}
	for key in ["structures", "removed", "rv", "vehicles", "worn", "stats"]:
		if value.has(key) and not value[key] is Dictionary:
			return {}
	for key in ["slots", "items"]:
		if value.has(key) and not value[key] is Array:
			return {}
	for slot in value.get("slots", []):
		if not slot is Dictionary:
			return {}
	return value

static func recover(path: String) -> Dictionary:
	var current := read(path)
	return current if not current.is_empty() else read(path + ".bak")

static func write(path: String, data: Dictionary) -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or read(temp).is_empty():
		return false
	# Never replace the recovery copy with a corrupt main save.
	if not read(path).is_empty():
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			return false
	return DirAccess.rename_absolute(temp, path) == OK
