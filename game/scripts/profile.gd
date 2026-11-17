extends Node
## Saved character identity and a shared live wardrobe editor.
const UI = preload("res://scripts/ui.gd")
const PATH := "user://character.cfg"
const OPTIONS := {
	"gender": ["Female", "Male"],
	"build": ["Soft", "Athletic", "Broad", "Slender", "Curvy"],
	"skin": ["Porcelain", "Fair", "Warm ivory", "Light olive", "Golden", "Tan", "Bronze", "Deep brown", "Ebony", "Cool brown"],
	"hair": ["Pixie", "Bob", "Long straight", "Long wavy", "Ponytail", "High ponytail", "Twin tails", "French braid", "Twin braids", "Bun", "Space buns", "Short crop", "Messy", "Curly", "Afro", "Side part", "Undercut", "Mohawk", "Locs", "Loose curls"],
	"hair_color": ["Black", "Espresso", "Chestnut", "Caramel", "Honey", "Blonde", "Platinum", "Auburn", "Copper", "Red", "Pink", "Lavender", "Sky blue", "Teal", "Silver", "White"],
	"top": ["Classic T-shirt", "Fitted T-shirt", "Tank top", "Crop top", "Camisole", "Blouse", "Button shirt", "Flannel", "Sweater", "Cardigan", "Hoodie", "Sport jersey", "Turtleneck", "Vest", "Denim jacket", "Leather jacket", "Puffer jacket", "Long coat", "Sundress", "Maxi dress", "Party dress", "Overalls", "Kimono jacket", "Raincoat", "Work shirt"],
	"bottom": ["Jeans", "Skinny jeans", "Wide-leg jeans", "Denim shorts", "Cargo pants", "Leggings", "Yoga pants", "Joggers", "Sweatpants", "Pleated skirt", "Mini skirt", "Midi skirt", "Maxi skirt", "Floral skirt", "Overalls", "Chinos", "Hiking pants", "Work trousers", "Formal trousers", "Swim shorts", "Cycling shorts"],
	"shoes": ["Sneakers", "High-top sneakers", "Sandals", "Flip flops", "Ankle boots", "Hiking boots", "Cowboy boots", "Knee-high boots", "Rain boots", "Ballet flats", "Loafers", "Heels", "Platform shoes", "Slippers", "Barefoot"],
	"hat": ["None", "Baseball cap", "Beanie", "Sun hat", "Cowboy hat", "Bucket hat", "Beret", "Straw hat", "Visor", "Headband", "Flower crown", "Ribbon bow", "Tiara", "Helmet", "Winter hat"],
	"glasses": ["None", "Round glasses", "Square glasses", "Cat-eye glasses", "Sunglasses", "Aviators", "Heart sunglasses", "Sport shades", "Colored lenses"],
	"neckwear": ["None", "Silk scarf", "Wool scarf", "Bandana", "Choker", "Pendant necklace", "Pearl necklace", "Gold chain", "Necktie", "Bow tie"],
	"bag": ["None", "Backpack", "Mini backpack", "Crossbody bag", "Handbag", "Tote bag", "Satchel", "Messenger bag", "Fanny pack", "Camera bag"],
	"earrings": ["None", "Gold studs", "Silver studs", "Hoops", "Dangling earrings", "Flower earrings", "Star earrings", "Pearl earrings"],
	"makeup": ["Natural", "Rosy cheeks", "Pink lipstick", "Red lipstick", "Berry lipstick", "Winged eyeliner", "Smoky eyes", "Glitter", "Freckles", "Pastel look"],
	"outfit_color": ["Rose", "Sky", "Emerald", "Lavender", "Cream", "Black", "Red", "Amber", "Mint", "White", "Navy", "Coral", "Brown", "Pastel pink", "Purple", "Teal", "Bright pink"],
	"accent_color": ["Cream", "Pink", "Gold", "Silver", "Black", "Blue", "Mint", "Purple", "Red", "Orange", "White", "Brown"],
}
const SKINS := ["f5d9c4", "e9bc9e", "d9ae8d", "b58b64", "ce985e", "b3774b", "93603f", "6e452e", "412c24", "704934"]
const HAIRS := ["1b1518", "32201b", "5b3523", "8a5a39", "ad7938", "d4b367", "e9d8aa", "803921", "c85d32", "a82432", "e477a3", "ab88d8", "6b9dc4", "3a9b93", "a2a5ae", "e1ddcf"]
const PALETTE := ["d37c96", "629cce", "4a9972", "9977bd", "e2d6ba", "292b34", "c34d43", "c79548", "8fc5a0", "e4e4dc", "344c71", "e8997d", "74543c", "eab6ca", "7d55ac", "4b9f9b", "f36fae"]
const ACCENTS := ["e7ded0", "e3a6ba", "d8ac53", "aeb6c1", "323034", "659dc5", "9bd9be", "a584c0", "ce6659", "e8a058", "f9f7ef", "694d36"]
var appearance: Dictionary = {}
var created := false

func _ready() -> void:
	randomize()
	appearance = defaults()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in appearance:
			appearance[key] = cfg.get_value("character", key, appearance[key])
		# Existing female characters retain custom looks. Older untouched defaults
		# get the newly requested pink-dress, long-hair appearance once.
		if int(cfg.get_value("character", "schema_version", 1)) < 2:
			var previous_gender := int(appearance.get("gender", 0))
			if previous_gender == 2 or (previous_gender == 0 and int(appearance.get("hair", 0)) == 0 and int(appearance.get("top", 0)) == 0 and int(appearance.get("outfit_color", 1)) == 1):
				_female_preset(appearance)
			cfg.set_value("character", "schema_version", 2)
			for key in appearance:
				cfg.set_value("character", key, appearance[key])
			cfg.save(PATH)
		created = true
	normalize(appearance)

func defaults() -> Dictionary:
	var d := {"username": "Human %d" % randi_range(1, 999)}
	for key in OPTIONS:
		d[key] = 0
	d["skin"] = 3
	d["hair_color"] = 2
	_female_preset(d)
	return d

func _female_preset(d: Dictionary) -> void:
	d["gender"] = 0
	d["hair"] = OPTIONS["hair"].find("Long straight")
	d["top"] = OPTIONS["top"].find("Sundress")
	d["bottom"] = OPTIONS["bottom"].find("Denim shorts")
	d["outfit_color"] = OPTIONS["outfit_color"].find("Bright pink")
	d["accent_color"] = OPTIONS["accent_color"].find("Pink")

func _male_preset(d: Dictionary) -> void:
	d["gender"] = 1
	d["hair"] = OPTIONS["hair"].find("Short crop")
	d["top"] = OPTIONS["top"].find("Classic T-shirt")
	d["bottom"] = OPTIONS["bottom"].find("Jeans")
	d["outfit_color"] = OPTIONS["outfit_color"].find("Navy")
	d["accent_color"] = OPTIONS["accent_color"].find("Cream")

func normalize(d: Dictionary) -> void:
	d["username"] = clean_name(str(d.get("username", "")))
	# Migrate saved nonbinary index (2) to Female; only Female (0) and Male (1) remain.
	d["gender"] = 1 if int(d.get("gender", 0)) == 1 else 0
	for key in OPTIONS:
		d[key] = clampi(int(d.get(key, 0)), 0, OPTIONS[key].size() - 1)

func clean_name(s: String) -> String:
	s = s.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	if s.length() > 24:
		s = s.substr(0, 24)
	return s if s != "" else "Human %d" % randi_range(1, 999)

func public_data() -> Dictionary:
	return appearance.duplicate(true)

func save(d: Dictionary) -> void:
	appearance = d.duplicate(true)
	normalize(appearance)
	var cfg := ConfigFile.new()
	for key in appearance:
		cfg.set_value("character", key, appearance[key])
	cfg.set_value("character", "schema_version", 2)
	cfg.save(PATH)
	created = true
	if Net.active():
		Net.profile_changed()

func color_for(key: String, index: int) -> Color:
	var palette: Array = PALETTE
	if key == "skin":
		palette = SKINS
	elif key == "hair_color":
		palette = HAIRS
	elif key == "accent_color":
		palette = ACCENTS
	return Color(palette[clampi(index, 0, palette.size() - 1)])

## Shared editor for first launch, menu and in-game pause.
func build_editor(parent: Container, done: Callable) -> void:
	var draft := public_data()
	parent.add_child(UI.label("Choose your name, gender and look. You can change these again any time.", 14, Color(0.82, 0.83, 0.81)))
	parent.add_child(UI.label("Username", 17))
	var username := LineEdit.new()
	username.max_length = 24
	username.text = str(draft["username"])
	username.custom_minimum_size = Vector2(0, 44)
	parent.add_child(username)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(300, 245)
	parent.add_child(holder)
	var vp := SubViewport.new()
	vp.size = Vector2i(420, 340)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.18, 0.22)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.86)
	env.environment.ambient_light_energy = 0.8
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.65, -0.45, 0)
	vp.add_child(light)
	var cam := Camera3D.new()
	# Procedural avatars face -Z, so rotate the preview 180 degrees to face
	# the +Z camera. Previously the editor only showed the back of the hair!
	cam.position = Vector3(0, 1.40, 3.0)
	cam.fov = 52.0
	vp.add_child(cam)
	cam.look_at(Vector3(0, 1.18, 0), Vector3.UP)
	cam.current = true
	var avatar = load("res://scripts/avatar.gd").new()
	avatar.rotation.y = PI
	vp.add_child(avatar)
	avatar.rebuild(draft)
	var grid := GridContainer.new()
	var pickers: Dictionary = {}
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for field in OPTIONS:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		cell.add_child(UI.label(field.replace("_", " ").capitalize(), 15))
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(205, 42)
		for choice in OPTIONS[field]:
			pick.add_item(choice)
		pick.select(int(draft.get(field, 0)))
		cell.add_child(pick)
		pickers[field] = pick
		pick.item_selected.connect(func(idx: int) -> void:
			if field == "gender" and int(draft.get("gender", 0)) != idx:
				if idx == 0:
					_female_preset(draft)
				else:
					_male_preset(draft)
				for changed in ["hair", "top", "bottom", "outfit_color", "accent_color"]:
					(pickers[changed] as OptionButton).select(int(draft[changed]))
			else:
				draft[field] = idx
			avatar.rebuild(draft))
	parent.add_child(UI.button("Save character & username", func() -> void:
		draft["username"] = username.text
		save(draft)
		done.call()))
