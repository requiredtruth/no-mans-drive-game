extends RefCounted
## Shared UI helpers: theme, item tiles, settings form.

const Data = preload("res://scripts/data.gd")

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.075, 0.08, 0.92)
	panel.border_color = Color(0.85, 0.65, 0.35, 0.5)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.2, 0.19, 0.17, 0.95)
	btn.set_corner_radius_all(7)
	btn.set_content_margin_all(10)
	btn.border_color = Color(0.5, 0.42, 0.3, 0.6)
	btn.set_border_width_all(1)
	var hov := btn.duplicate()
	hov.bg_color = Color(0.36, 0.28, 0.17, 1.0)
	var prs := btn.duplicate()
	prs.bg_color = Color(0.55, 0.38, 0.18, 1.0)
	var dis := btn.duplicate()
	dis.bg_color = Color(0.13, 0.13, 0.13, 0.8)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("focus", "Button", hov)
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", Color(0.95, 0.92, 0.85))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("font_color", "Label", Color(0.95, 0.93, 0.88))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", bg)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0.15, 0.15, 0.15)
	line.set_content_margin_all(8)
	line.set_corner_radius_all(5)
	t.set_stylebox("normal", "LineEdit", line)
	return t

static func bar(color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("fill", fill)
	pb.custom_minimum_size = Vector2(150, 12)
	return pb

static func label(text: String, size := 18, color := Color(0.95, 0.93, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	b.pressed.connect(func() -> void:
		Audio.play("click", -6.0, 1.0, "UI")
		cb.call())
	return b

const SHORT := {"knife": "Knife", "axe": "Hatchet", "pickaxe": "Pickaxe", "hammer": "Hammer", "fishing_rod": "Rod",
	"flashlight": "Light", "rifle": "Rifle", "bow": "Bow", "water_clean": "Water", "water_dirty": "Dirty\nwater",
	"canned_food": "Beans", "fuel_can": "Fuel", "engine_parts": "Engine\nparts", "car_battery": "Battery",
	"seeds_tomato": "Tomato\nseeds", "seeds_potato": "Seed\npotato", "seeds_coffee": "Coffee\nplant",
	"coffee_beans": "Coffee\nbeans", "raw_meat": "Raw\nmeat", "cooked_meat": "Cooked\nmeat", "raw_fish": "Raw\nfish",
	"cooked_fish": "Grilled\nfish", "roast_mushroom": "Roast\nshroom", "baked_potato": "Baked\npotato", "scrap": "Scrap",
	"ammo": "Ammo", "medkit": "Medkit", "jacket": "Jacket", "toolkit": "Toolkit", "tire": "Tire"}

static func abbrev(id: String) -> String:
	if SHORT.has(id):
		return SHORT[id]
	var n := Data.item_name(id)
	var words := n.split(" ")
	if words.size() >= 2:
		return words[0] + "\n" + words[1]
	return n

## Square item icon with count.
static func item_tile(id: String, n: int, size := 64.0) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	var c: Color = Data.ITEMS.get(id, {}).get("color", Color(0.3, 0.3, 0.3))
	sb.bg_color = c.darkened(0.35)
	sb.border_color = c.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var tex: Texture2D = Items.icon(id)
	if tex:
		sb.bg_color = Color(0.1, 0.1, 0.1, 0.55)
		sb.border_color = c.lightened(0.1)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(2, 2)
		tr.size = Vector2(size - 4, size - 4)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
	var l := label(abbrev(id) if tex == null else "", int(size * 0.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	p.add_child(l)
	if n > 1:
		var cl := label(str(n), int(size * 0.24))
		cl.position = Vector2(4, size - size * 0.34)
		cl.size = Vector2(size - 8, size * 0.3)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.add_theme_color_override("font_outline_color", Color.BLACK)
		cl.add_theme_constant_override("outline_size", 4)
		p.add_child(cl)
	p.tooltip_text = Data.item_name(id)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func build_settings(parent: Container) -> void:
	for c in parent.get_children():
		c.queue_free()
	var s := Game.settings
	parent.add_child(label("Audio", 22, Color(0.95, 0.75, 0.45)))
	for pair in [["master", "Master volume"], ["sfx", "Effects"], ["ambience", "Ambience"], ["vehicle", "Vehicle"], ["ui", "Interface"]]:
		_slider(parent, pair[1], pair[0], 0.0, 1.0, 0.05)
	parent.add_child(label("Controls & comfort", 22, Color(0.95, 0.75, 0.45)))
	_slider(parent, "Look sensitivity", "sensitivity", 0.05, 1.0, 0.01)
	_slider(parent, "Field of view", "fov", 55.0, 100.0, 1.0)
	_toggle(parent, "Invert look Y", "invert_y")
	_toggle(parent, "Head bob", "head_bob")
	_option(parent, "Touch controls", "touch_controls", ["auto", "on", "off"])
	_slider(parent, "Touch button size", "touch_size", 0.7, 1.5, 0.05)
	parent.add_child(label("Graphics", 22, Color(0.95, 0.75, 0.45)))
	_option(parent, "View distance", "view_distance", [1, 2, 3])
	_toggle(parent, "Shadows", "shadows")
	_toggle(parent, "Grass", "grass")
	_slider(parent, "Render scale", "render_scale", 0.5, 1.0, 0.05)
	_toggle(parent, "Show FPS", "show_fps")

static func _row(parent: Container, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(text)
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	parent.add_child(h)
	return h

static func _slider(parent: Container, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var h := _row(parent, text)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(Game.settings[key])
	sl.custom_minimum_size = Vector2(260, 36)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := label("%.2f" % sl.value)
	val.custom_minimum_size = Vector2(60, 0)
	sl.value_changed.connect(func(v: float) -> void:
		Game.settings[key] = v
		val.text = "%.2f" % v
		Game.save_settings())
	h.add_child(sl)
	h.add_child(val)

static func _toggle(parent: Container, text: String, key: String) -> void:
	var h := _row(parent, text)
	var cb := CheckButton.new()
	cb.button_pressed = bool(Game.settings[key])
	cb.toggled.connect(func(on: bool) -> void:
		Game.settings[key] = on
		Game.save_settings())
	h.add_child(cb)

static func _option(parent: Container, text: String, key: String, values: Array) -> void:
	var h := _row(parent, text)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(160, 40)
	for i in range(values.size()):
		ob.add_item(str(values[i]).capitalize() if typeof(values[i]) == TYPE_STRING else ["", "Near", "Medium", "Far"][int(values[i])])
		if str(values[i]) == str(Game.settings[key]):
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void:
		Game.settings[key] = values[i]
		Game.save_settings())
	h.add_child(ob)

const CONTROLS_TEXT := """KEYBOARD & MOUSE
WASD move · Mouse look · Shift sprint · Ctrl crouch (sneak up on game) · Space jump / handbrake
E pick up / interact / enter / exit · G place held item (or pick up furniture) · Q throw
Left click use / eat / wear · Right click aim / demolish (build) · R rotate what you place
1-4 or wheel switch hands · Tab crafting · B build menu
F flashlight · L headlights · C driving camera · Esc pause

CONTROLLER
Left stick move · Right stick look · RT use · LT aim / demolish · A jump · X interact
B place · Y crafting · LB/RB switch hands · D-pad: up rotate, down build menu, left lights, right flashlight
Back camera · Start pause

TOUCH
Left joystick move / drive · Drag right side to look · Buttons for use, aim, interact, jump,
sprint, place, throw, crafting, build, rotate, lights and camera. Tap a hand slot to switch."""
