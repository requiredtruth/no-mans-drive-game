extends Node
## Entry point: main menu, loading, starting/joining worlds.

const UI = preload("res://scripts/ui.gd")
const World = preload("res://scripts/world.gd")

var menu_layer: CanvasLayer
var menu_root: Control
var content: VBoxContainer
var world: Node3D
var _bg_time := 0.0
var _bg: ColorRect

func _ready() -> void:
	name = "Main"
	Net.joined_world.connect(_on_joined_world)
	Net.connection_failed.connect(func(r: String) -> void: _show_message("Co-op", r))
	_build_menu()
	_show_main()
	if OS.has_feature("mobile") and not FileAccess.file_exists(Game.SETTINGS_PATH):
		Game.settings["view_distance"] = 1
		Game.settings["render_scale"] = 0.85
		Game.save_settings()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--devtest"):
			var t := Node.new()
			t.set_script(load("res://scripts/devtest.gd"))
			add_child(t)
			return
	if "--autostart" in args:
		Game.new_game(4242, "Normal")
		_start_world({})

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = UI.make_theme()
	menu_layer.add_child(menu_root)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float t;
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
void fragment(){
	vec2 uv = UV;
	vec3 top = vec3(0.10, 0.12, 0.22);
	vec3 hor = vec3(0.95, 0.55, 0.28);
	vec3 col = mix(hor, top, smoothstep(0.35, 0.95, 1.0 - uv.y));
	float sun = smoothstep(0.16, 0.15, distance(uv * vec2(1.6, 1.0), vec2(0.8 * 1.6 * 0.5 + 0.35, 0.6)));
	col = mix(col, vec3(1.0, 0.85, 0.55), sun * step(uv.y, 0.66));
	float hills = 0.66 + 0.04 * sin(uv.x * 9.0 + 1.0) + 0.025 * sin(uv.x * 23.0 + t * 0.05);
	float hills2 = 0.72 + 0.03 * sin(uv.x * 14.0 + 3.0);
	col = mix(col, vec3(0.16, 0.12, 0.13), step(hills, uv.y));
	col = mix(col, vec3(0.08, 0.07, 0.08), step(hills2, uv.y));
	float road = step(0.72, uv.y) * step(abs(uv.x - 0.5), (uv.y - 0.72) * 1.3);
	col = mix(col, vec3(0.13, 0.13, 0.14), road);
	float dash = step(abs(uv.x - 0.5), 0.004 + (uv.y - 0.72) * 0.02) * step(0.5, fract(1.0 / max(uv.y - 0.7, 0.01) * 0.6 - t * 0.6)) * step(0.73, uv.y);
	col = mix(col, vec3(0.95, 0.8, 0.3), dash);
	col *= 0.9 + 0.1 * hash(uv * 400.0 + t);
	COLOR = vec4(col, 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_bg.material = m
	menu_root.add_child(_bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := UI.label("NO MAN'S DRIVE", 48, Color(1.0, 0.78, 0.42))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("an open-road survival journey", 18, Color(0.85, 0.82, 0.76))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	var ver := UI.label("v%s" % ProjectSettings.get_setting("application/config/version", "1.0"), 12, Color(0.6, 0.6, 0.6))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(ver)

func _process(delta: float) -> void:
	if menu_layer.visible:
		_bg_time += delta
		(_bg.material as ShaderMaterial).set_shader_parameter("t", _bg_time)

func _clear() -> void:
	for c in content.get_children():
		c.queue_free()

func _show_main() -> void:
	_clear()
	if Game.has_save():
		content.add_child(UI.button("Continue journey", _continue))
	content.add_child(UI.button("New journey", _show_new))
	content.add_child(UI.button("Co-op (up to 4 players)", _show_coop))
	content.add_child(UI.button("Settings", func() -> void:
		_clear()
		UI.build_settings(content)
		content.add_child(UI.button("Back", _show_main))))
	content.add_child(UI.button("Controls", func() -> void: _show_message("Controls", UI.CONTROLS_TEXT)))
	content.add_child(UI.button("Credits & licenses", func() -> void: _show_message("Credits", CREDITS)))
	if not OS.has_feature("web"):
		content.add_child(UI.button("Quit", func() -> void: get_tree().quit()))

func _show_message(title: String, text: String) -> void:
	_clear()
	content.add_child(UI.label(title, 24, Color(1.0, 0.8, 0.5)))
	var l := UI.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	content.add_child(l)
	content.add_child(UI.button("Back", _show_main))

func _show_new() -> void:
	_clear()
	content.add_child(UI.label("New journey", 24, Color(1.0, 0.8, 0.5)))
	if Game.has_save():
		content.add_child(UI.label("Starting a new journey replaces your current save.", 14, Color(1, 0.7, 0.6)))
	var diff := OptionButton.new()
	for d in ["Relaxed", "Normal", "Hard"]:
		diff.add_item(d)
	diff.select(1)
	diff.custom_minimum_size = Vector2(0, 44)
	content.add_child(UI.label("Difficulty", 16))
	content.add_child(diff)
	content.add_child(UI.label("World seed", 16))
	var seed_edit := LineEdit.new()
	seed_edit.text = str(randi() % 999999)
	seed_edit.custom_minimum_size = Vector2(0, 44)
	content.add_child(seed_edit)
	content.add_child(UI.button("Start", func() -> void:
		Game.new_game(int(seed_edit.text.hash() if not seed_edit.text.is_valid_int() else seed_edit.text.to_int()), diff.get_item_text(diff.selected))
		_start_world({})))
	content.add_child(UI.button("Back", _show_main))

func _show_coop() -> void:
	_clear()
	content.add_child(UI.label("Co-op", 24, Color(1.0, 0.8, 0.5)))
	content.add_child(UI.label("Play together on the same Wi-Fi/LAN or over the internet (forward UDP port %d on the host)." % Net.PORT, 14))
	content.add_child(UI.label("Your name", 16))
	var name_edit := LineEdit.new()
	name_edit.text = Net.player_name
	name_edit.custom_minimum_size = Vector2(0, 44)
	content.add_child(name_edit)
	content.add_child(UI.button("Host — continue my journey" if Game.has_save() else "Host — new journey", func() -> void:
		Net.player_name = name_edit.text
		if Game.has_save():
			var d := Game.load_game_data()
			_start_world(d)
		else:
			Game.new_game(randi() % 999999, "Normal")
			_start_world({})
		var err := Net.host()
		if err != "":
			Game.notify(err)
		else:
			Game.notify("Hosting. Friends can join at %s" % Net.local_ips())))
	content.add_child(UI.label("Host address", 16))
	var ip := LineEdit.new()
	ip.text = "192.168.1.2"
	ip.custom_minimum_size = Vector2(0, 44)
	content.add_child(ip)
	content.add_child(UI.button("Join", func() -> void:
		Net.player_name = name_edit.text
		var err := Net.join(ip.text)
		if err != "":
			_show_message("Co-op", err)
		else:
			_show_message("Co-op", "Connecting to %s ..." % ip.text)))
	content.add_child(UI.button("Back", _show_main))

func _continue() -> void:
	var d := Game.load_game_data()
	if d.is_empty():
		_show_message("Continue", "The save file could not be read.")
		return
	_start_world(d)

func _on_joined_world(snapshot: Dictionary) -> void:
	Game.new_game(int(snapshot.get("seed", 1)), str(snapshot.get("difficulty", "Normal")))
	Game.apply_world_snapshot(snapshot)
	_start_world({})

func _start_world(loaded: Dictionary) -> void:
	_clear()
	content.add_child(UI.label("Generating the road ahead...", 22))
	await get_tree().process_frame
	await get_tree().process_frame
	if world:
		world.queue_free()
	world = Node3D.new()
	world.set_script(World)
	world.name = "World"
	add_child(world)
	world.start(loaded)
	menu_layer.visible = false
	if not Game.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func quit_to_menu() -> void:
	Net.leave()
	Audio.stop_ambience()
	if world:
		world.queue_free()
		world = null
	Game.playing = false
	Game.ui_open = false
	Game.paused = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_layer.visible = true
	_show_main()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if Game.playing and not Net.is_client() and Game.player and not Game.player.dead:
			Game.save_game()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and Game.world and Game.world.hud:
		if Game.world.hud.modal:
			Game.world.hud.close_modal()
		else:
			Game.world.hud.open_pause()

const CREDITS := """No Man's Drive — an original open-road survival game.

Code, terrain, vegetation, buildings, RV, animals (except the fox), shaders, textures and sound effects were created for this project and are released as CC0.

Fox model — glTF Sample Assets (Khronos Group). Model by PixelMannen (CC0); rigging and animation by tomkranis (CC BY 4.0); glTF conversion by AsoboStudio and scurest (CC BY 4.0).

Lantern model — glTF Sample Assets (Khronos Group), CC0.

Barramundi fish model — glTF Sample Assets (Khronos Group), by Microsoft, CC0.

Built with the Godot Engine (MIT license)."""
