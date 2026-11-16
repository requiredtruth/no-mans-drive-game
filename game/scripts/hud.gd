extends CanvasLayer
## In-game HUD and all gameplay menus.

const Data = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")

var root: Control
var bars := {}
var clock: Label
var info: Label
var prompt_label: Label
var crosshair: Control
var hotbar_box: HBoxContainer
var notes: VBoxContainer
var build_info: Label
var dash: PanelContainer
var dash_label: Label
var dash_fuel: ProgressBar
var compass: Control
var damage_rect: ColorRect
var cold_rect: ColorRect
var fade_rect: ColorRect
var fps_label: Label
var modal: Control
var _modal_kind := ""
var _modal_ctx = null
var _note_items: Array = []
var _icon_dirty := false
var _icon_timer := 0.0

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make_theme()
	add_child(root)
	_build_overlays()
	_build_stats()
	_build_top_right()
	_build_center()
	_build_hotbar()
	_build_notes()
	_build_dash()
	Game.notified.connect(_on_note)
	Game.hotbar_changed.connect(_refresh_hotbar)
	Game.inventory_changed.connect(_on_inventory)
	Items.icon_ready.connect(func(_id: String) -> void: _icon_dirty = true)
	Items.prewarm()
	_refresh_hotbar()

func _build_overlays() -> void:
	cold_rect = ColorRect.new()
	cold_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	cold_rect.color = Color(0.6, 0.8, 1.0, 0.0)
	cold_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cold_rect)
	damage_rect = ColorRect.new()
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.color = Color(0.7, 0.0, 0.0, 0.0)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)

func _build_stats() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(18, 16)
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	for spec in [["health", "HEALTH", Color("d04a3c")], ["food", "FOOD", Color("d39a3c")], ["water", "WATER", Color("4a9ad8")],
			["energy", "ENERGY", Color("d8cf4a")], ["warmth", "WARMTH", Color("e07a3a")]]:
		var h := HBoxContainer.new()
		var l := UI.label(spec[1], 13, Color(0.9, 0.9, 0.85))
		l.custom_minimum_size = Vector2(70, 0)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		h.add_child(l)
		var b := UI.bar(spec[2])
		h.add_child(b)
		box.add_child(h)
		bars[spec[0]] = b
	fps_label = UI.label("", 14)
	box.add_child(fps_label)

func _build_top_right() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	v.position = Vector2(-300, 14)
	v.custom_minimum_size = Vector2(280, 0)
	v.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(v)
	clock = UI.label("", 22)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info = UI.label("", 15, Color(0.85, 0.85, 0.8))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l in [clock, info]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		v.add_child(l)
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-220, 10)
	compass.custom_minimum_size = Vector2(440, 34)
	compass.size = Vector2(440, 34)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)

func _build_center() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func() -> void:
		crosshair.draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.85))
		crosshair.draw_arc(Vector2.ZERO, 4.5, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.5))
	root.add_child(crosshair)
	prompt_label = UI.label("", 20)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(-400, 40)
	prompt_label.custom_minimum_size = Vector2(800, 0)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 6)
	root.add_child(prompt_label)
	build_info = UI.label("", 17, Color(0.7, 1.0, 0.75))
	build_info.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_info.position = Vector2(-400, -150)
	build_info.custom_minimum_size = Vector2(800, 0)
	build_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_info.add_theme_color_override("font_outline_color", Color.BLACK)
	build_info.add_theme_constant_override("outline_size", 5)
	root.add_child(build_info)

func _build_hotbar() -> void:
	hotbar_box = HBoxContainer.new()
	hotbar_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_box.position = Vector2(-225, -90)
	hotbar_box.add_theme_constant_override("separation", 6)
	root.add_child(hotbar_box)

func _refresh_hotbar() -> void:
	for c in hotbar_box.get_children():
		c.queue_free()
	for i in range(Game.hotbar.size()):
		var id: String = Game.hotbar[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(70, 70)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45)
		sb.set_corner_radius_all(8)
		sb.border_color = Color(1.0, 0.8, 0.4) if i == Game.selected_slot else Color(1, 1, 1, 0.2)
		sb.set_border_width_all(3 if i == Game.selected_slot else 1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		if id != "" and Game.count(id) > 0:
			var t := UI.item_tile(id, Game.count(id), 58)
			t.position = Vector2(6, 6)
			b.add_child(t)
			b.tooltip_text = Data.item_name(id)
		var n := UI.label(str(i + 1), 12, Color(1, 1, 1, 0.6))
		n.position = Vector2(4, 0)
		b.add_child(n)
		var idx := i
		b.pressed.connect(func() -> void:
			if Game.selected_slot == idx and Game.player:
				Game.player.use_primary()
			Game.select_slot(idx))
		hotbar_box.add_child(b)

func _on_inventory() -> void:
	_refresh_hotbar()
	if modal and _modal_kind in ["inventory", "cooking", "storage", "rv", "crafting"]:
		_reopen()

func _build_notes() -> void:
	notes = VBoxContainer.new()
	notes.position = Vector2(18, 200)
	notes.add_theme_constant_override("separation", 2)
	notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notes)

func _on_note(text: String) -> void:
	var l := UI.label(text, 16)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	notes.add_child(l)
	_note_items.append([l, 4.0])
	while notes.get_child_count() > 7:
		var c := notes.get_child(0)
		notes.remove_child(c)
		c.queue_free()

func _build_dash() -> void:
	dash = PanelContainer.new()
	dash.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dash.position = Vector2(-260, -205)
	dash.custom_minimum_size = Vector2(520, 0)
	root.add_child(dash)
	var v := VBoxContainer.new()
	dash.add_child(v)
	dash_label = UI.label("", 17)
	dash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(dash_label)
	dash_fuel = UI.bar(Color("d8a03a"))
	dash_fuel.custom_minimum_size = Vector2(480, 10)
	v.add_child(dash_fuel)
	dash.visible = false

func _draw_compass() -> void:
	var p: Node3D = Game.player
	if p == null:
		return
	var w := compass.size.x
	compass.draw_rect(Rect2(0, 0, w, 30), Color(0, 0, 0, 0.35))
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	var heading := atan2(fwd.x, -fwd.z) # 0 = north (-z)
	var font := ThemeDB.fallback_font
	var marks := {0.0: "N", PI * 0.5: "E", PI: "S", -PI * 0.5: "W", PI * 0.25: "NE", PI * 0.75: "SE", -PI * 0.25: "NW", -PI * 0.75: "SW"}
	for a in marks:
		var d := wrapf(a - heading, -PI, PI)
		if absf(d) < 1.2:
			var x := w * 0.5 + d / 1.2 * w * 0.5
			var s: String = marks[a]
			compass.draw_string(font, Vector2(x - 8 * s.length(), 22), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if s.length() == 1 else 12, Color(1, 1, 1, 0.9))
	var rv: Node3D = Game.rv
	if rv and not p.driving:
		var to := rv.global_position - p.global_position
		var ra := atan2(to.x, -to.z)
		var d := wrapf(ra - heading, -PI, PI)
		var x := clampf(w * 0.5 + d / 1.2 * w * 0.5, 6, w - 6)
		compass.draw_rect(Rect2(x - 5, 2, 10, 8), Color(1.0, 0.75, 0.3))
		compass.draw_string(font, Vector2(x - 12, 40), "RV %dm" % int(to.length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.8, 0.4))
	compass.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, 30), Color(1, 1, 1, 0.5), 1.0)

# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	var st := Game.stats
	for k in bars:
		bars[k].value = st[k]
	var h := int(Game.time_of_day)
	var m := int((Game.time_of_day - h) * 60.0)
	clock.text = "Day %d   %02d:%02d" % [Game.day, h, m]
	var p: Node3D = Game.player
	if p and Game.world:
		var w = Game.world
		info.text = "%s · %s · %d°C" % [w.gen.biome_name(p.global_position.x, p.global_position.z), Game.weather.capitalize(), int(round(p.effective_temp()))]
		prompt_label.text = p.prompt
		var b = p.builder
		if b.active and not p.driving:
			var pc: String = b.piece()
			var cost_txt: String = ("carried ×%d" % Game.count(b.kit)) if b.kit != "" else Data.cost_text(Data.PIECES[pc]["cost"])
			build_info.text = "PLACING: %s  (%s) — %s\n[USE] place · [R/ROT] rotate · [RMB] demolish · [B/BUILD] stop" % [Data.PIECES[pc]["name"], cost_txt, b.reason if not b.valid else "ready"]
		else:
			build_info.text = ""
		dash.visible = p.driving
		hotbar_box.visible = not p.driving
		crosshair.visible = not p.driving
		if p.driving:
			var rv = p.vehicle
			var spd: float = rv.speed_kmh()
			dash_label.text = "%3d km/h   %s   Fuel %d/%d L   Battery %d%%   Engine %d%%   Tires %d%%%s" % [int(absf(spd)), "R" if spd < -0.5 else "D",
				int(rv.fuel), int(rv.fuel_capacity()), int(rv.battery), int(rv.parts["engine"]), int(rv.parts["tires"]), "   LIGHTS" if rv.headlights else ""]
			if not rv.engine_on and p.is_driver:
				dash_label.text += "\nEngine off — press USE (left click / RT) to start"
			dash_fuel.max_value = rv.fuel_capacity()
			dash_fuel.value = rv.fuel
		var warmth: float = st["warmth"]
		cold_rect.color.a = clampf((40.0 - warmth) / 40.0, 0.0, 1.0) * 0.25
	damage_rect.color.a = maxf(damage_rect.color.a - delta * 1.5, 0.0)
	fps_label.text = "FPS %d" % Engine.get_frames_per_second() if Game.settings["show_fps"] else ""
	for item in _note_items.duplicate():
		item[1] -= delta
		if item[1] <= 0.0:
			_note_items.erase(item)
			if is_instance_valid(item[0]):
				item[0].queue_free()
		elif item[1] < 1.0 and is_instance_valid(item[0]):
			item[0].modulate.a = item[1]
	compass.queue_redraw()
	_icon_timer -= delta
	if _icon_dirty and _icon_timer <= 0.0:
		_icon_dirty = false
		_icon_timer = 0.5
		_refresh_hotbar()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if modal:
			close_modal()
		else:
			open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		if modal and _modal_kind in ["inventory", "storage", "cooking", "crafting", "rv", "build", "sink"]:
			close_modal()
		elif not modal and Game.player and not Game.player.dead:
			open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_menu") and Game.player and not Game.player.dead and not Game.player.driving:
		if modal and _modal_kind == "build":
			close_modal()
		elif Game.player.builder.active:
			Game.player.builder.stop()
			Game.notify("Stopped building")
		elif not modal:
			if Game.count("hammer") > 0:
				open_build_menu()
			else:
				Game.notify("Craft a Builder's Hammer first (2 Wood, 1 Stone, 1 Rope)")
		get_viewport().set_input_as_handled()

func flash_damage() -> void:
	damage_rect.color.a = 0.45
	Audio.play("hit", -4.0, 0.7)

# ------------------------------------------------------------------ modal framework
func _open_modal(kind: String, title: String, ctx = null, width := 900.0) -> VBoxContainer:
	if modal:
		modal.queue_free()
	_modal_kind = kind
	_modal_ctx = ctx
	Game.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	modal = dim
	if kind != "death":
		dim.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				close_modal())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var panel := PanelContainer.new()
	var vp := get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(minf(width, vp.x - 40), minf(560, vp.y - 40))
	center.add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var t := UI.label(title, 26, Color(1.0, 0.8, 0.5))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UI.button("Close ✕", close_modal))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	return body

func close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null
	_modal_kind = ""
	Game.ui_open = false
	Game.paused = false
	get_tree().paused = false
	if Game.player and not Game.player.dead and not Game.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _reopen() -> void:
	match _modal_kind:
		"inventory": open_inventory()
		"crafting": open_crafting(_modal_ctx)
		"cooking": open_cooking(_modal_ctx)
		"rv": open_rv_menu(_modal_ctx)
		"storage": open_storage(_modal_ctx[0], _modal_ctx[1], _modal_ctx[2])

# ------------------------------------------------------------------ inventory & crafting
func open_inventory() -> void:
	open_crafting("")

func open_crafting(station) -> void:
	var st: String = station if station != null else ""
	var body := _open_modal("inventory" if st == "" else "crafting", "Backpack & Crafting" if st == "" else "Workbench", st, 1100.0)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	body.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UI.label("Inventory — tap an item to use it or assign it to the selected hotbar slot (%d)" % (Game.selected_slot + 1), 15, Color(0.8, 0.8, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	var keys := Game.inventory.keys()
	keys.sort()
	for id in keys:
		var b := Button.new()
		b.custom_minimum_size = Vector2(76, 76)
		b.focus_mode = Control.FOCUS_NONE
		var t := UI.item_tile(id, Game.count(id), 64)
		t.position = Vector2(6, 6)
		b.add_child(t)
		b.tooltip_text = Data.item_name(id)
		b.pressed.connect(_item_menu.bind(id))
		grid.add_child(b)
	var detail := VBoxContainer.new()
	detail.name = "Detail"
	left.add_child(detail)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UI.label("Crafting" + (" (workbench recipes unlocked)" if st == "workbench" else " — build a Workbench for advanced recipes"), 18, Color(1.0, 0.8, 0.5)))
	for r in Data.RECIPES:
		if r["station"] == "workbench" and st != "workbench":
			continue
		var row := HBoxContainer.new()
		var can := Game.has_cost(r["cost"])
		var l := UI.label("%s ×%d\n%s" % [Data.item_name(r["out"]), r["n"], Data.cost_text(r["cost"])], 15, Color(0.95, 0.93, 0.88) if can else Color(0.6, 0.6, 0.58))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var btn := UI.button("Craft", func() -> void:
			if Game.pay(r["cost"]):
				Game.add_item(r["out"], r["n"])
				Audio.play("hammer", -4.0), 90)
		btn.disabled = not can
		row.add_child(btn)
		right.add_child(row)
	var info_l := UI.label("Equipped: %s   ·   Jacket: %s" % [Data.item_name(Game.equipped()) if Game.equipped() != "" else "Bare hands", "yes" if Game.count("jacket") > 0 else "no"], 14, Color(0.75, 0.75, 0.7))
	left.add_child(info_l)

func _item_menu(id: String) -> void:
	if modal == null:
		return
	var detail: Node = modal.find_child("Detail", true, false)
	if detail == null:
		return
	for c in detail.get_children():
		c.queue_free()
	var it: Dictionary = Data.ITEMS.get(id, {})
	var desc := "%s — %d" % [Data.item_name(id), Game.count(id)]
	if it.get("kind", "") == "food":
		desc += "   (food %+d, water %+d%s)" % [it.get("food", 0), it.get("water", 0), (", health %+d" % it["health"]) if it.has("health") else ""]
	detail.add_child(UI.label(desc, 17))
	var row := HBoxContainer.new()
	detail.add_child(row)
	if it.get("kind", "") in ["food", "medical"]:
		row.add_child(UI.button("Eat / Use", func() -> void: Game.consume(id)))
	row.add_child(UI.button("Put in hotbar slot %d" % (Game.selected_slot + 1), func() -> void:
		Game.assign_hotbar(id)
		Game.notify("%s → slot %d" % [Data.item_name(id), Game.selected_slot + 1])))
	row.add_child(UI.button("Drop 1", func() -> void: Game.player.drop_item(id, 1)))
	if it.get("kind", "") == "placeable":
		row.add_child(UI.button("Place it", func() -> void:
			Game.assign_hotbar(id)
			close_modal()
			Game.player.builder.place_kit(id)))

# ------------------------------------------------------------------ cooking
func open_cooking(fire) -> void:
	var body := _open_modal("cooking", "Campfire" if fire else "RV Stove", fire, 760.0)
	if fire:
		var row := HBoxContainer.new()
		row.add_child(UI.label("Fuel: %d min    " % int(float(fire.data.get("fuel", 0.0)) / 60.0), 18))
		row.add_child(UI.button("Add wood (+3 min)", func() -> void:
			fire.add_fuel()
			_reopen()))
		body.add_child(row)
	elif Game.rv and Game.rv.battery < 1.0:
		body.add_child(UI.label("The stove igniter needs battery power.", 18, Color(1, 0.6, 0.5)))
		return
	for r in Data.COOKING:
		var row := HBoxContainer.new()
		var can := Game.has_cost(r["cost"])
		var l := UI.label("%s\n%s" % [Data.item_name(r["out"]), Data.cost_text(r["cost"])], 16, Color.WHITE if can else Color(0.6, 0.6, 0.6))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var cook_one := UI.button("Cook", func() -> void:
			if Game.pay(r["cost"]):
				Game.add_item(r["out"], r["n"])
				Audio.play("pickup"), 90)
		cook_one.disabled = not can
		row.add_child(cook_one)
		var cook_all := UI.button("Cook all", func() -> void:
			var n := 0
			while Game.pay(r["cost"]) and n < 50:
				n += 1
			if n > 0:
				Game.add_item(r["out"], r["n"] * n)
				Audio.play("pickup"), 90)
		cook_all.disabled = not can
		row.add_child(cook_all)
		body.add_child(row)

# ------------------------------------------------------------------ storage
func open_storage(items: Dictionary, title: String, on_change: Callable) -> void:
	var body := _open_modal("storage", title, [items, title, on_change], 1000.0)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	body.add_child(cols)
	var mine := VBoxContainer.new()
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var theirs := VBoxContainer.new()
	theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(mine)
	cols.add_child(theirs)
	mine.add_child(UI.label("Backpack", 20, Color(1.0, 0.8, 0.5)))
	theirs.add_child(UI.label(title, 20, Color(1.0, 0.8, 0.5)))
	var keys := Game.inventory.keys()
	keys.sort()
	for id in keys:
		if Data.ITEMS.get(id, {}).get("kind", "") == "tool" and Game.hotbar.has(id):
			continue
		var row := HBoxContainer.new()
		var l := UI.label("%s ×%d" % [Data.item_name(id), Game.count(id)], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		for amt in [1, -1]:
			row.add_child(UI.button("→1" if amt == 1 else "→All", func() -> void:
				var n := 1 if amt == 1 else Game.count(id)
				if Game.remove_item(id, n):
					items[id] = int(items.get(id, 0)) + n
					on_change.call()
					_reopen(), 64))
		mine.add_child(row)
	var ckeys := items.keys()
	ckeys.sort()
	for id in ckeys:
		if int(items[id]) <= 0:
			continue
		var row := HBoxContainer.new()
		for amt in [1, -1]:
			row.add_child(UI.button("1←" if amt == 1 else "All←", func() -> void:
				var have := int(items.get(id, 0))
				var n := 1 if amt == 1 else have
				n = mini(n, have)
				if n > 0:
					items[id] = have - n
					if items[id] <= 0:
						items.erase(id)
					on_change.call()
					Game.add_item(id, n, true), 64))
		var l := UI.label("%s ×%d" % [Data.item_name(id), int(items[id])], 16)
		row.add_child(l)
		theirs.add_child(row)
	if ckeys.is_empty():
		theirs.add_child(UI.label("(empty)", 16, Color(0.6, 0.6, 0.6)))

# ------------------------------------------------------------------ RV
func open_rv_menu(rv) -> void:
	var body := _open_modal("rv", "%s Workshop" % rv.display_name(), rv, 1000.0)
	body.add_child(UI.label("%s · Odometer %.1f km · Fuel %d/%d L%s · Battery charge %d%%" % [rv.display_name(), rv.odometer / 1000.0, int(rv.fuel), int(rv.fuel_capacity()), (" · Water %d/%d L" % [int(rv.water), int(rv.water_capacity())]) if rv.water_capacity() > 0.0 else "", int(rv.battery)], 16, Color(0.85, 0.85, 0.8)))
	body.add_child(UI.label("Parts", 20, Color(1.0, 0.8, 0.5)))
	for part in Data.RV_PARTS:
		var spec: Dictionary = Data.RV_PARTS[part]
		var row := HBoxContainer.new()
		var l := UI.label(spec["name"], 17)
		l.custom_minimum_size = Vector2(170, 0)
		row.add_child(l)
		var b := UI.bar(Color("6ab04c") if rv.parts[part] > 50 else (Color("e0a030") if rv.parts[part] > 20 else Color("d04030")))
		b.value = rv.parts[part]
		b.custom_minimum_size = Vector2(200, 16)
		row.add_child(b)
		row.add_child(UI.label("  %d%%  " % int(rv.parts[part]), 16))
		var cost := "Repair: %s%s" % [Data.cost_text(spec["repair"]), " + toolkit" if spec["needs_toolkit"] else ""]
		var rb := UI.button(cost, func() -> void: rv.repair(part))
		rb.disabled = rv.parts[part] >= 99.9
		row.add_child(rb)
		body.add_child(row)
	body.add_child(UI.label("Upgrades (toolkit required)", 20, Color(1.0, 0.8, 0.5)))
	for up in rv.upgrade_list():
		var spec: Dictionary = Data.RV_UPGRADES[up]
		var row := HBoxContainer.new()
		var have: bool = rv.upgrades.has(up)
		var l := UI.label(spec["name"] + ("  ✔ installed" if have else "\n" + Data.cost_text(spec["cost"])), 16, Color(0.6, 1.0, 0.6) if have else Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if not have:
			var ib := UI.button("Install", func() -> void: rv.install(up), 100)
			ib.disabled = not Game.has_cost(spec["cost"])
			row.add_child(ib)
		body.add_child(row)
	body.add_child(UI.label("Paint job", 20, Color(1.0, 0.8, 0.5)))
	var prow := HBoxContainer.new()
	var palette: Array = rv.paint_palette()
	for i in range(palette.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 44)
		var sb := StyleBoxFlat.new()
		sb.bg_color = palette[i]
		sb.set_corner_radius_all(6)
		sb.border_color = Color.WHITE if rv.paint == i else Color(0, 0, 0, 0.5)
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		var idx := i
		b.pressed.connect(func() -> void:
			rv.set_paint(idx)
			_reopen())
		prow.add_child(b)
	body.add_child(prow)

func open_sink(rv) -> void:
	var body := _open_modal("sink", "Sink & Water Tank", rv, 640.0)
	body.add_child(UI.label("Tank: %d / %d L" % [int(rv.water), int(rv.water_capacity())], 18))
	var refresh := func() -> void: open_sink(rv)
	body.add_child(UI.button("Drink from tap (1 L)", func() -> void:
		if rv.water >= 1.0:
			rv.water -= 1.0
			Game.stats["water"] = minf(Game.stats["water"] + 30.0, 100.0)
			Audio.play("eat")
		else:
			Game.notify("The tank is empty")
		refresh.call()))
	body.add_child(UI.button("Fill a bottle (1 L → Clean Water)", func() -> void:
		if rv.water >= 1.0:
			rv.water -= 1.0
			Game.add_item("water_clean", 1)
		else:
			Game.notify("The tank is empty")
		refresh.call()))
	body.add_child(UI.button("Pour clean water into tank (+1 L)", func() -> void:
		if rv.water <= rv.water_capacity() - 1.0 and Game.remove_item("water_clean", 1):
			rv.water += 1.0
		refresh.call()))
	body.add_child(UI.button("Filter dirty water into tank (+1 L)", func() -> void:
		if rv.water <= rv.water_capacity() - 1.0 and Game.remove_item("water_dirty", 1):
			rv.water += 1.0
		refresh.call()))
	body.add_child(UI.button("Wash up (+5 warmth, +5 energy)", func() -> void:
		if rv.water >= 2.0:
			rv.water -= 2.0
			Game.stats["energy"] = minf(Game.stats["energy"] + 5.0, 100.0)
			Game.stats["warmth"] = minf(Game.stats["warmth"] + 5.0, 100.0)
		refresh.call()))

# ------------------------------------------------------------------ building
func open_build_menu() -> void:
	var body := _open_modal("build", "Build", null, 980.0)
	body.add_child(UI.label("Choose what to build. Foundations snap to a 3 m grid; walls, doors and windows snap to foundation edges; floors and roofs go on top of walls.", 15, Color(0.8, 0.8, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for i in range(Data.PIECE_ORDER.size()):
		var t: String = Data.PIECE_ORDER[i]
		var spec: Dictionary = Data.PIECES[t]
		var can := Game.has_cost(spec["cost"])
		var b := UI.button("%s\n%s" % [spec["name"], Data.cost_text(spec["cost"])], func() -> void:
			Game.player.builder.select(i)
			close_modal(), 290)
		b.custom_minimum_size = Vector2(290, 64)
		if not can:
			b.modulate = Color(1, 1, 1, 0.55)
		grid.add_child(b)

# ------------------------------------------------------------------ pause / settings / death
func open_pause() -> void:
	var body := _open_modal("pause", "Paused", null, 640.0)
	Game.paused = true
	if not Net.active():
		get_tree().paused = true
	body.add_child(UI.button("Resume", close_modal))
	if not Net.is_client():
		body.add_child(UI.button("Save game", func() -> void: Game.save_game()))
	body.add_child(UI.button("Settings", open_settings))
	body.add_child(UI.button("Cheats / testing", open_cheats))
	body.add_child(UI.button("Controls", func() -> void:
		var b := _open_modal("controls", "Controls", null, 900.0)
		b.add_child(UI.label(UI.CONTROLS_TEXT, 16))))
	if Net.active():
		body.add_child(UI.label(Net.status_text(), 15, Color(0.7, 0.9, 1.0)))
	body.add_child(UI.label("Difficulty: %s · Seed %d" % [Game.difficulty, Game.seed_value], 14, Color(0.7, 0.7, 0.7)))
	body.add_child(UI.button("Save & quit to menu", func() -> void:
		if not Net.is_client():
			Game.save_game()
		get_tree().paused = false
		Game.paused = false
		Game.ui_open = false
		get_tree().root.get_node("Main").quit_to_menu()))

func open_cheats() -> void:
	var body := _open_modal("cheats", "Cheats & testing", null, 820.0)
	Game.paused = true
	var Data_ = Data
	var grid := GridContainer.new()
	grid.columns = 2
	body.add_child(grid)
	var add := func(label: String, cb: Callable) -> void:
		grid.add_child(UI.button(label, func() -> void:
			cb.call()
			Game.notify("Cheat: " + label), 360))
	add.call("Give every item ×5", func() -> void:
		for id in Data_.ITEMS:
			Game.add_item(id, 1 if Data_.ITEMS[id]["kind"] == "tool" else 5, true))
	add.call("Building materials +50", func() -> void:
		for id in ["wood", "stone", "cloth", "rope", "scrap", "fiber"]:
			Game.add_item(id, 50, true))
	add.call("All tools & weapons", func() -> void:
		for id in ["knife", "axe", "pickaxe", "hammer", "bow", "rifle", "fishing_rod", "flashlight"]:
			if Game.count(id) == 0:
				Game.add_item(id, 1, true)
		Game.add_item("arrow", 30, true)
		Game.add_item("ammo", 30, true))
	add.call("Restore health & needs", func() -> void:
		for k in Game.stats:
			Game.stats[k] = 100.0)
	add.call("God mode " + ("OFF" if Game.god_mode else "ON"), func() -> void:
		Game.god_mode = not Game.god_mode
		open_cheats())
	add.call("Repair RV fully", func() -> void:
		var rv = Game.rv
		for k in rv.parts:
			rv.parts[k] = 100.0
		rv.battery = 100.0
		rv._apply_visuals())
	add.call("Fill fuel & water", func() -> void:
		Game.rv.fuel = Game.rv.fuel_capacity()
		Game.rv.water = Game.rv.water_capacity())
	add.call("Install all RV upgrades", func() -> void:
		for u in Data_.RV_UPGRADES:
			Game.rv.upgrades[u] = true
		Game.rv._apply_visuals())
	add.call("Skip 3 hours", func() -> void:
		Game.time_of_day = fmod(Game.time_of_day + 3.0, 24.0))
	add.call("Set noon", func() -> void: Game.time_of_day = 12.0)
	add.call("Set night", func() -> void: Game.time_of_day = 22.0)
	add.call("Next weather", func() -> void:
		var order := ["clear", "cloudy", "rain"]
		Game.weather = order[(order.find(Game.weather) + 1) % order.size()])
	for sp in ["deer", "wolf", "bear", "boar", "rabbit", "turkey", "fox"]:
		add.call("Spawn " + sp, func() -> void:
			var p: Vector3 = Game.player.global_position - Game.player.global_transform.basis.z * 12.0
			p.y = Game.world.gen.height(p.x, p.z) + 0.5
			Game.world.spawn_animal(sp, p))
	add.call("Teleport to next location", func() -> void:
		var gen = Game.world.gen
		var row := int(floor(Game.player.global_position.z / gen.CHUNK))
		for k in range(1, 200):
			var poi: Dictionary = gen.poi_for_row(row - k)
			if not poi.is_empty():
				var p: Vector3 = poi["pos"]
				var road := Vector3(gen.road_x(p.z), 0, p.z)
				road.y = gen.height(road.x, road.z) + 1.0
				Game.player.teleport(road)
				break)
	add.call("Bring RV to me", func() -> void:
		var p: Vector3 = Game.player.global_position + Game.player.global_transform.basis.x * 5.0
		p.y = Game.world.gen.height(p.x, p.z) + 1.0
		Game.rv.global_position = p
		Game.rv.linear_velocity = Vector3.ZERO
		Game.rv.angular_velocity = Vector3.ZERO
		Game.rv.rotation = Vector3(0, Game.rv.rotation.y, 0))

func open_settings() -> void:
	var body := _open_modal("settings", "Settings", null, 820.0)
	Game.paused = true
	UI.build_settings(body)

func show_death(cause: String) -> void:
	var body := _open_modal("death", "You died", null, 560.0)
	body.add_child(UI.label("Cause: %s" % cause.capitalize(), 20, Color(1, 0.6, 0.5)))
	body.add_child(UI.label("You will wake at your last bed or tent, or beside the RV.\nPerishable food is lost.", 16))
	body.add_child(UI.button("Respawn", func() -> void:
		Game.player.respawn()
		close_modal()))

func show_intro() -> void:
	var body := _open_modal("intro", "The road goes on", null, 900.0)
	body.add_child(UI.label("""The world went quiet. You have an old motorhome, a few tools and an endless highway.

• Keep your health, food, water, energy and warmth up. Nights are cold; tundra is colder.
• Search gas stations, houses, farms and wrecks along the road for fuel, food and parts.
• Repair and upgrade the RV at its hood. Refuel at pumps or with fuel cans.
• Hunt deer, boar, turkey and rabbits. Wolves and bears will hunt you back.
• Build a camp: campfires for heat and cooking, tents and beds to sleep and save,
  planters for crops, and full houses from foundations, walls, doors, windows and roofs.
• Grow tomatoes, potatoes and coffee in the RV's plant pots or in garden planters.

Equip the Builder's Hammer and press B (or the BUILD button) to start building.""", 16))
	body.add_child(UI.button("Hit the road", close_modal))

func fade_sleep(hours: float) -> void:
	if fade_rect == null:
		fade_rect = ColorRect.new()
		fade_rect.color = Color(0, 0, 0, 0)
		fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(fade_rect)
	var tw := create_tween()
	fade_rect.color.a = 1.0
	tw.tween_interval(0.6)
	tw.tween_property(fade_rect, "color:a", 0.0, 1.2)
	Game.notify("You slept for %d hours" % int(round(hours)))
