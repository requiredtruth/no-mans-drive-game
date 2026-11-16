extends CanvasLayer
## Android / touchscreen controls: virtual joystick, drag-to-look and action buttons.

var sprint_on := false
var aim_on := false
var _look_delta := Vector2.ZERO
var _look_finger := -1
var _stick_finger := -1
var _stick_center := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _stick_base: Control
var _stick_knob: Control
var _foot_buttons: Array = []
var _drive_buttons: Array = []
var _all_buttons: Array = []
var _circle: Texture2D
var _scale := 1.0
var _labels := {}

const STICK_R := 90.0

func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scale = float(Game.settings["touch_size"])
	_circle = _make_circle(128)
	_stick_base = _ring(STICK_R * 2.0 * _scale, Color(1, 1, 1, 0.12))
	_stick_knob = _ring(STICK_R * 0.9 * _scale, Color(1, 1, 1, 0.3))
	add_child(_stick_base)
	add_child(_stick_knob)
	get_viewport().size_changed.connect(_layout)
	# Right cluster (on foot)
	_foot_buttons = [
		_btn("USE", "primary", Color(0.85, 0.35, 0.25), 1.25),
		_btn("E", "interact", Color(0.3, 0.6, 0.85), 1.05),
		_btn("JUMP", "jump", Color(0.45, 0.45, 0.45), 0.95),
		_btn("AIM", "", Color(0.45, 0.45, 0.45), 0.85, func() -> void: aim_on = not aim_on),
		_btn("RUN", "", Color(0.45, 0.45, 0.45), 0.85, func() -> void: sprint_on = not sprint_on),
		_btn("SNEAK", "crouch", Color(0.45, 0.45, 0.45), 0.8),
		_btn("BUILD", "build_menu", Color(0.7, 0.55, 0.25), 0.8),
		_btn("ROT", "rotate", Color(0.7, 0.55, 0.25), 0.7),
		_btn("LIGHT", "flashlight", Color(0.6, 0.6, 0.3), 0.7),
		_btn("GRAB", "pickup", Color(0.3, 0.6, 0.85), 0.85),
	]
	_drive_buttons = [
		_btn("EXIT", "interact", Color(0.3, 0.6, 0.85), 1.05),
		_btn("BRAKE", "jump", Color(0.85, 0.35, 0.25), 1.15),
		_btn("START", "primary", Color(0.35, 0.7, 0.35), 0.9),
		_btn("LIGHTS", "lights", Color(0.6, 0.6, 0.3), 0.8),
		_btn("CAM", "camera", Color(0.45, 0.45, 0.45), 0.8),
		_btn("GAS", "move_forward", Color(0.35, 0.75, 0.35), 1.25),
		_btn("REV", "move_back", Color(0.8, 0.45, 0.25), 1.0),
	]
	var bag := _btn("BAG", "inventory", Color(0.45, 0.45, 0.45), 0.75)
	var pause := _btn("II", "pause", Color(0.3, 0.3, 0.3), 0.6)
	_foot_buttons.append(bag)
	_drive_buttons.append(pause)
	_foot_buttons.append(pause)
	_layout()

func _make_circle(s: int) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in range(s):
		for x in range(s):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			var a := clampf((1.0 - d) * 24.0, 0.0, 1.0)
			var rim := clampf(1.0 - absf(d - 0.93) * 25.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * 0.55 + rim * 0.4))
	return ImageTexture.create_from_image(img)

func _ring(size: float, col: Color) -> Control:
	var t := TextureRect.new()
	t.texture = _circle
	t.modulate = col
	t.size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _btn(text: String, action: String, col: Color, size_mul: float, cb: Callable = Callable()) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle
	var px := 88.0 * size_mul * _scale
	b.scale = Vector2.ONE * (px / 128.0)
	b.modulate = col
	if action != "":
		b.action = action
	if cb.is_valid():
		b.pressed.connect(cb)
	var shape := CircleShape2D.new()
	shape.radius = 64.0
	b.shape = shape
	b.shape_centered = true
	add_child(b)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(17 * _scale))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(px, px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	_labels[b] = l
	_all_buttons.append(b)
	return b

func _place(b: TouchScreenButton, pos: Vector2) -> void:
	b.position = pos
	var l: Label = _labels[b]
	l.position = pos
	var px := 128.0 * b.scale.x
	l.size = Vector2(px, px)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var r := vp.x - 24.0
	var b := vp.y - 24.0
	var px := func(btn: TouchScreenButton) -> float: return 128.0 * btn.scale.x
	# foot layout
	var f := _foot_buttons
	_place(f[0], Vector2(r - px.call(f[0]), b - px.call(f[0]) - 40))
	_place(f[1], Vector2(r - px.call(f[0]) - px.call(f[1]) - 14, b - px.call(f[1]) - 10))
	_place(f[2], Vector2(r - px.call(f[2]) - 6, b - px.call(f[0]) - px.call(f[2]) - 56))
	_place(f[3], Vector2(r - px.call(f[0]) - px.call(f[3]) - 20, b - px.call(f[1]) - px.call(f[3]) - 26))
	_place(f[4], Vector2(r - px.call(f[0]) - px.call(f[1]) - px.call(f[4]) - 30, b - px.call(f[4])))
	_place(f[5], Vector2(r - px.call(f[2]) - px.call(f[5]) - 20, b - px.call(f[0]) - px.call(f[2]) - px.call(f[5]) - 40))
	_place(f[6], Vector2(r - px.call(f[6]), vp.y * 0.3))
	_place(f[7], Vector2(r - px.call(f[6]) - px.call(f[7]) - 10, vp.y * 0.3))
	_place(f[8], Vector2(r - px.call(f[8]), vp.y * 0.3 - px.call(f[8]) - 10))
	_place(f[9], Vector2(r - px.call(f[9]), vp.y * 0.3 + px.call(f[6]) + 10))
	_place(f[10], Vector2(24, vp.y * 0.42))
	_place(f[11], Vector2(vp.x * 0.5 + 250, 14))
	var d := _drive_buttons
	_place(d[5], Vector2(r - px.call(d[5]), b - px.call(d[5])))
	_place(d[6], Vector2(r - px.call(d[5]) - px.call(d[6]) - 16, b - px.call(d[6])))
	_place(d[1], Vector2(r - px.call(d[5]) - px.call(d[6]) - px.call(d[1]) - 32, b - px.call(d[1])))
	_place(d[0], Vector2(r - px.call(d[0]), b - px.call(d[5]) - px.call(d[0]) - 20))
	_place(d[2], Vector2(r - px.call(d[0]) - px.call(d[2]) - 16, b - px.call(d[5]) - px.call(d[2]) - 20))
	_place(d[3], Vector2(r - px.call(d[3]), vp.y * 0.3))
	_place(d[4], Vector2(r - px.call(d[3]) - px.call(d[4]) - 10, vp.y * 0.3))
	_place(d[7], Vector2(vp.x * 0.5 + 250, 14))
	_stick_center = Vector2(40 + STICK_R * _scale + 30, vp.y - STICK_R * _scale - 60)
	_update_stick_visual()

func _update_stick_visual() -> void:
	_stick_base.position = _stick_center - _stick_base.size * 0.5
	_stick_knob.position = _stick_center + _stick_vec * STICK_R * _scale - _stick_knob.size * 0.5

func _process(_delta: float) -> void:
	var p: Node = Game.player
	var driving: bool = p != null and p.driving
	var hide_all: bool = Game.ui_open or p == null or p.dead
	for btn in _all_buttons:
		var show: bool = not hide_all and ((btn in _drive_buttons) if driving else (btn in _foot_buttons))
		btn.visible = show
		_labels[btn].visible = show
	_stick_base.visible = not hide_all
	_stick_knob.visible = not hide_all
	var aim_lbl: Label = _labels[_foot_buttons[3]]
	aim_lbl.modulate = Color(1, 1, 0.4) if aim_on else Color.WHITE
	var run_lbl: Label = _labels[_foot_buttons[4]]
	run_lbl.modulate = Color(1, 1, 0.4) if sprint_on else Color.WHITE
	_apply_stick()

func _on_button(pos: Vector2) -> bool:
	for btn in _all_buttons:
		if not btn.visible:
			continue
		var px: float = 128.0 * btn.scale.x
		if Rect2(btn.position, Vector2(px, px)).grow(6).has_point(pos):
			return true
	return false

func _input(event: InputEvent) -> void:
	if Game.ui_open:
		_stick_finger = -1
		_look_finger = -1
		_stick_vec = Vector2.ZERO
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if _on_button(event.position):
				return
			if event.position.x < vp.x * 0.4 and event.position.y > vp.y * 0.35 and _stick_finger == -1:
				_stick_finger = event.index
				_stick_center = event.position
				_stick_vec = Vector2.ZERO
			elif event.position.x >= vp.x * 0.4 and _look_finger == -1:
				_look_finger = event.index
		else:
			if event.index == _stick_finger:
				_stick_finger = -1
				_stick_vec = Vector2.ZERO
				_layout()
			if event.index == _look_finger:
				_look_finger = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_finger:
			_stick_vec = ((event.position - _stick_center) / (STICK_R * _scale)).limit_length(1.0)
		elif event.index == _look_finger:
			_look_delta += event.relative
	_update_stick_visual()

func _apply_stick() -> void:
	var v := _stick_vec
	_set_action("move_left", maxf(-v.x, 0.0))
	_set_action("move_right", maxf(v.x, 0.0))
	_set_action("move_forward", maxf(-v.y, 0.0))
	_set_action("move_back", maxf(v.y, 0.0))

var _held := {}

func _set_action(a: String, s: float) -> void:
	if s > 0.08:
		Input.action_press(a, s)
		_held[a] = true
	elif _held.get(a, false):
		Input.action_release(a)
		_held[a] = false

func consume_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d
