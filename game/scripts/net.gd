extends Node
## Online co-op (up to 4 players) over ENet. Autoloaded as "Net".
## Host is authoritative for the world snapshot, time and weather; whoever drives owns the RV.

const PORT := 24680
const MAX_CLIENTS := 3

signal joined_world(snapshot: Dictionary)
signal connection_failed(reason: String)

var player_name := "Nomad"
var _send_acc := 0.0
var _rv_acc := 0.0
var _peer_names := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit("Could not reach the host"))
	multiplayer.server_disconnected.connect(_on_server_lost)
	player_name = "Nomad-%d" % (randi() % 900 + 100)

func active() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_client() -> bool:
	return active() and not multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1

func host() -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		return "Could not open port %d (error %d)" % [PORT, err]
	multiplayer.multiplayer_peer = peer
	return ""

func join(ip: String) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return "Could not connect (error %d)" % err
	multiplayer.multiplayer_peer = peer
	return ""

func leave() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer_names.clear()

func local_ips() -> String:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append(ip)
	return ", ".join(out) if not out.is_empty() else "unknown"

func status_text() -> String:
	if not active():
		return ""
	var n := multiplayer.get_peers().size() + 1
	if multiplayer.is_server():
		return "Hosting co-op · %d/4 players · join address: %s" % [n, local_ips()]
	return "Connected to co-op host · %d players" % n

# ------------------------------------------------------------------ connection flow
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		Game.notify("A player joined")

func _on_peer_disconnected(id: int) -> void:
	if Game.world:
		Game.world.remove_remote_player(id)
	if Game.rv and Game.rv.driver == id:
		Game.rv.driver = 0
	Game.notify("%s left" % _peer_names.get(id, "A player"))

func _on_connected() -> void:
	_hello.rpc_id(1, player_name)

func _on_server_lost() -> void:
	leave()
	Game.notify("Lost connection to the host")
	if Game.world:
		get_tree().root.get_node("Main").quit_to_menu()

@rpc("any_peer", "reliable")
func _hello(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	_peer_names[from] = pname
	var snap := Game.world_snapshot() if Game.world else {}
	_welcome.rpc_id(from, snap)
	Game.notify("%s joined the convoy" % pname)

@rpc("authority", "reliable")
func _welcome(snapshot: Dictionary) -> void:
	joined_world.emit(snapshot)

# ------------------------------------------------------------------ per-frame sync
func _process(delta: float) -> void:
	if not active() or Game.player == null or Game.world == null:
		return
	_send_acc += delta
	if _send_acc >= 1.0 / 15.0:
		_send_acc = 0.0
		var p := Game.player
		_player_state.rpc(p.global_position, p.rotation.y, p.driving, player_name)
	_rv_acc += delta
	if multiplayer.is_server() and Game.rv and Game.rv.driver == 0 and _rv_acc > 0.2:
		_rv_acc = 0.0
		_rv_state.rpc(Game.rv.global_transform, Game.rv.save_state())

@rpc("any_peer", "unreliable_ordered")
func _player_state(pos: Vector3, yaw: float, in_vehicle: bool, pname: String) -> void:
	if Game.world:
		Game.world.update_remote_player(multiplayer.get_remote_sender_id(), pos, yaw, in_vehicle, pname)

func send_rv(xf: Transform3D, _vel: Vector3) -> void:
	if not active():
		return
	_rv_acc += get_physics_process_delta_time()
	if _rv_acc < 0.05:
		return
	_rv_acc = 0.0
	_rv_drive.rpc(xf)

@rpc("any_peer", "unreliable_ordered")
func _rv_drive(xf: Transform3D) -> void:
	if Game.rv:
		Game.rv.remote_transform(xf)

@rpc("authority", "unreliable_ordered")
func _rv_state(xf: Transform3D, state: Dictionary) -> void:
	if Game.rv and Game.rv.driver == 0:
		Game.rv.remote_transform(xf)
		Game.rv.fuel = float(state.get("fuel", Game.rv.fuel))
		Game.rv.water = float(state.get("water", Game.rv.water))
		# fitted modules and pulled parts follow the host's van
		var mods: Dictionary = state.get("modules", {})
		if mods != Game.rv.modules or state.get("missing", {}) != Game.rv.missing or state.get("module_xf", {}) != Game.rv.module_xf:
			Game.rv.modules = mods.duplicate()
			Game.rv.module_xf = state.get("module_xf", {}).duplicate(true)
			Game.rv.missing = state.get("missing", {}).duplicate()
			Game.rv.wheel_kind = state.get("wheel_kind", {}).duplicate()
			Game.rv._apply_visuals()

func claim_driver(on: bool) -> bool:
	if not active():
		return true
	if on and Game.rv.driver != 0 and Game.rv.driver != my_id():
		return false
	_set_driver.rpc(my_id() if on else 0, Game.rv.save_state() if not on else {})
	return true

@rpc("any_peer", "call_local", "reliable")
func _set_driver(id: int, state: Dictionary) -> void:
	if Game.rv:
		Game.rv.driver = id
		if not state.is_empty() and multiplayer.get_remote_sender_id() != multiplayer.get_unique_id():
			Game.rv.apply_state(state)

# ------------------------------------------------------------------ world edits
func mark_removed(key: String, value) -> void:
	_removed(key, value)
	if active():
		_removed.rpc(key, value)

@rpc("any_peer", "reliable")
func _removed(key: String, value) -> void:
	Game.removed[key] = value
	if Game.world and (typeof(value) == TYPE_BOOL or typeof(value) == TYPE_INT):
		Game.world.on_removed(key)

func place_structure(id: String, rec: Dictionary) -> void:
	_place(id, rec)
	if active():
		_place.rpc(id, rec)

@rpc("any_peer", "reliable")
func _place(id: String, rec: Dictionary) -> void:
	if Game.world:
		Game.world.spawn_structure(id, rec)

func remove_structure(id: String) -> void:
	_remove(id)
	if active():
		_remove.rpc(id)

@rpc("any_peer", "reliable")
func _remove(id: String) -> void:
	if Game.world:
		Game.world.remove_structure_local(id)

func sync_structure_data(id: String, data: Dictionary) -> void:
	if active():
		_sdata.rpc(id, data)

@rpc("any_peer", "reliable")
func _sdata(id: String, data: Dictionary) -> void:
	if Game.world:
		Game.world.structure_data(id, data)

func sync_weather() -> void:
	if active() and multiplayer.is_server():
		_weather.rpc(Game.weather, Game.time_of_day, Game.day)

func sync_time() -> void:
	if active():
		_weather.rpc(Game.weather, Game.time_of_day, Game.day)

@rpc("any_peer", "reliable")
func _weather(w: String, t: float, d: int) -> void:
	Game.weather = w
	Game.time_of_day = t
	Game.day = d

func animal_hit(_id: String, _amount: float) -> void:
	pass # wildlife is simulated per player
