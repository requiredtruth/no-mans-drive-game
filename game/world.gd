extends Node3D

var camera := Camera3D.new()
var player := Vector3(0, 1.7, 2)
var rv := Node3D.new()
var sun := DirectionalLight3D.new()
var hud := Label.new()
var notice := ""
var yaw := 0.0
var pitch := 0.0
var fuel := 35.0
var hunger := 100.0
var wood := 0
var stone := 0
var meat := 0
var driving := false
var animals: Array[Node3D] = []
var resources: Array[Node3D] = []
var held := {}
var rng := RandomNumberGenerator.new()
var recipes := ["Campfire", "Floor", "Wall", "Doorway", "Window", "Roof"]
var selected := 0
var clock := 0.0

func block(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

func _ready() -> void:
	rng.seed = 49286
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c1cce0")
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_light_color = Color("a9b9c2")
	environment.fog_density = 0.003
	world.environment = environment
	add_child(world)
	add_child(sun)
	sun.shadow_enabled = true
	block(self, Vector3(0,-0.55,-260), Vector3(680,1,660), Color("65744b"))
	block(self, Vector3(0,-0.02,-260), Vector3(8,0.08,660), Color("393c3c"))
	for z in range(-580, 65, 8):
		block(self, Vector3(0,0.026,z), Vector3(0.13,0.01,3), Color("d4bf81"))
	add_child(rv)
	rv.position = Vector3(0,0,-4)
	block(rv, Vector3(0,1.15,0), Vector3(2.35,1.9,5), Color("d8cdb5"))
	block(rv, Vector3(0,0.78,0), Vector3(2.38,0.27,5.03), Color("a85232"))
	block(rv, Vector3(0,1.6,-2.51), Vector3(2.05,0.65,0.03), Color("435a63"))
	for x in [-1.19, 1.19]:
		for z in [-1.55,1.55]:
			var wheel := block(rv, Vector3(x,0.39,z), Vector3.ONE, Color("292a28"))
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.38
			cylinder.bottom_radius = 0.38
			cylinder.height = 0.27
			wheel.mesh = cylinder
			wheel.rotation_degrees.z = 90
	for i in range(100):
		var x := rng.randf_range(10,100) * (-1 if i % 2 == 0 else 1)
		var z := rng.randf_range(-560,24)
		var tree := Node3D.new()
		add_child(tree)
		tree.position = Vector3(x,0,z)
		block(tree, Vector3(0,1.5,0), Vector3(0.46,3,0.46), Color("554739"))
		var crown := block(tree, Vector3(0,3.6,0), Vector3.ONE, Color("394f35"))
		var shape := CylinderMesh.new()
		shape.top_radius = 0
		shape.bottom_radius = 1.6
		shape.height = 3.6
		crown.mesh = shape
	for i in range(45):
		var item := block(self, Vector3(rng.randf_range(5,20) * (-1 if i % 2 == 0 else 1),0.23,-i * 6 + 3), Vector3(0.65,0.38,0.46), Color("986e4a") if i % 3 else Color("999c92"))
		item.set_meta("wood", i % 3 != 0)
		resources.append(item)
	for i in range(12):
		var animal := Node3D.new()
		add_child(animal)
		animal.position = Vector3(8 + i % 3 * 2,0,-12 - i * 23)
		block(animal, Vector3(0,0.92,0), Vector3(0.46,0.54,1.05), Color("966743"))
		block(animal, Vector3(0,1.23,-0.53), Vector3(0.28,0.42,0.36), Color("a5724c"))
		for x in [-0.16,0.16]:
			for z in [-0.35,0.35]:
				block(animal, Vector3(x,0.38,z), Vector3(0.1,0.75,0.1), Color("73503b"))
		animals.append(animal)
	add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(hud)
	hud.position = Vector2(18,12)
	hud.add_theme_font_size_override("font_size", 21)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar := HBoxContainer.new()
	layer.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -486
	bar.offset_top = -73
	for caption in ["Left","Forward","Back","Right","RV","Gather","Hunt","Plan","Build","Cook"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size = Vector2(93,59)
		bar.add_child(button)
		button.button_down.connect(func(): held[caption] = true)
		button.button_up.connect(func(): held.erase(caption))
		if caption not in ["Left","Forward","Back","Right"]:
			button.pressed.connect(act.bind(caption))

func act(action: String) -> void:
	match action:
		"RV":
			if driving:
				driving = false
				player = rv.position + Vector3(2.1,1.7,0)
			elif player.distance_to(rv.position) < 8:
				driving = true
				yaw = rv.rotation.y
		"Gather":
			for item in resources:
				if player.distance_to(item.position) < 4.5:
					if item.get_meta("wood"):
						wood += 3
					else:
						stone += 3
					resources.erase(item)
					item.queue_free()
					return
			notice = "Move closer to wood or stone beside the road."
		"Hunt":
			for animal in animals:
				var offset := animal.position + Vector3.UP - camera.position
				if offset.length() < 26 and offset.normalized().dot(-camera.global_basis.z) > 0.985:
					animals.erase(animal)
					animal.queue_free()
					meat += 2
					notice = "Venison collected."
					return
			notice = "Aim the crosshair at nearby wildlife."
		"Plan":
			selected = (selected + 1) % recipes.size()
		"Build":
			build_piece()
		"Cook":
			for node in get_tree().get_nodes_in_group("campfires"):
				if node.position.distance_to(player) < 5 and meat > 0:
					hunger = minf(100, hunger + 35)
					meat -= 1
					return
			notice = "Bring venison to a campfire."

func build_piece() -> void:
	if wood < 2 or (selected == 0 and stone < 2):
		notice = "Building needs 2 wood. Campfires also need 2 stone."
		return
	var dest := player + Basis(Vector3.UP,yaw) * Vector3(0,0,-4)
	dest = Vector3(snappedf(dest.x,3),0,snappedf(dest.z,3))
	var piece := Node3D.new()
	add_child(piece)
	piece.position = dest
	piece.rotation.y = snappedf(yaw, PI / 2)
	var timber := Color("9d754e")
	match selected:
		0:
			stone -= 2
			piece.add_to_group("campfires")
			block(piece,Vector3(0,0.09,0),Vector3(1,0.18,1),Color("626564"))
			block(piece,Vector3(0,0.29,0),Vector3(0.32,0.37,0.32),Color("ed7625"))
			var fire := OmniLight3D.new()
			fire.position.y = 0.7
			fire.light_color = Color("ff914c")
			fire.light_energy = 2.2
			piece.add_child(fire)
		1:
			block(piece,Vector3(0,0.06,0),Vector3(3,0.12,3),timber)
		2:
			block(piece,Vector3(0,1.4,-1.5),Vector3(3,2.8,0.16),timber)
		3,4:
			for x in [-1.08,1.08]:
				block(piece,Vector3(x,1.4,-1.5),Vector3(0.84,2.8,0.16),timber)
			block(piece,Vector3(0,2.48,-1.5),Vector3(1.32,0.64,0.16),timber)
			if selected == 4:
				block(piece,Vector3(0,0.5,-1.5),Vector3(1.32,1,0.16),timber)
		5:
			block(piece,Vector3(0,2.9,0),Vector3(3.2,0.2,3.2),Color("613e35"))
	wood -= 2

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.004
		pitch = clampf(pitch - event.relative.y * 0.004,-1.3,1.3)
	if event is InputEventKey and event.pressed and not event.echo:
		var shortcuts := {KEY_E:"RV",KEY_F:"Gather",KEY_H:"Hunt",KEY_Q:"Plan",KEY_B:"Build",KEY_C:"Cook"}
		if shortcuts.has(event.physical_keycode):
			act(shortcuts[event.physical_keycode])

func movement(key: Key, button: String) -> int:
	return int(Input.is_physical_key_pressed(key) or held.has(button))

func _process(delta: float) -> void:
	clock += delta
	sun.rotation_degrees = Vector3(-32 - sin(clock / 38.0) * 46, -35, 0)
	hunger = maxf(0,hunger - delta * 0.085)
	var forward := movement(KEY_W,"Forward") - movement(KEY_S,"Back")
	var strafe := movement(KEY_D,"Right") - movement(KEY_A,"Left")
	if driving:
		if forward and fuel > 0:
			yaw -= strafe * delta * 1.12
			rv.rotation.y = yaw
			rv.position += rv.basis * Vector3(0,0,-forward * 14 * delta)
			fuel = maxf(0,fuel - delta * 0.13)
		player = rv.position + rv.basis * Vector3(0,2.6,3.9)
	else:
		player += Basis(Vector3.UP,yaw) * Vector3(strafe,0,-forward).limit_length() * delta * (4.7 if hunger > 0 else 2.0)
	player.x = clampf(player.x,-110,110)
	player.z = clampf(player.z,-575,45)
	camera.position = player
	camera.rotation = Vector3(pitch,yaw,0)
	for animal in animals:
		var away := animal.position - player
		away.y = 0
		if away.length() < 12:
			animal.position += away.normalized() * 3.2 * delta
		else:
			animal.position.x += sin(clock * 0.6 + animal.position.z) * delta * 0.62
	hud.text = "NO MAN’S DRIVE    •    %s\nFood %d%%    Fuel %.1f L    Wood %d    Stone %d    Venison %d\nBuilding plan · %s\n%s" % ["Driving" if driving else "On foot", hunger, fuel, wood, stone, meat, recipes[selected], notice]
