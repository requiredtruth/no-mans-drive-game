extends Node3D
## Original lightweight procedural 3D avatar; built identically on every multiplayer client.
var display_name := ""

func rebuild(a: Dictionary) -> void:
	for child in get_children():
		child.free()
	var skin: Color = Profile.color_for("skin", int(a.get("skin", 3)))
	var hair: Color = Profile.color_for("hair_color", int(a.get("hair_color", 2)))
	var cloth: Color = Profile.color_for("outfit_color", int(a.get("outfit_color", 1)))
	var trim: Color = Profile.color_for("accent_color", int(a.get("accent_color", 0)))
	var dark := cloth.darkened(0.26)
	var body_mat := Lib.color_mat(cloth, 0.75)
	var trim_mat := Lib.color_mat(trim, 0.7)
	var skin_mat := Lib.color_mat(skin, 0.85)
	var hair_mat := Lib.color_mat(hair, 0.85)
	var black := Lib.color_mat(Color("29262d"))
	var gender: int = int(a.get("gender", 0))
	var build: int = int(a.get("build", 0))
	var shoulders := 0.34 if gender == 1 else 0.285
	if build == 2:
		shoulders += 0.065
	elif build == 3:
		shoulders -= 0.04
	var legs := Lib.color_mat(dark, 0.9)
	var pants_name: String = Profile.OPTIONS["bottom"][clampi(int(a.get("bottom", 0)), 0, Profile.OPTIONS["bottom"].size() - 1)]
	if "skirt" in pants_name.to_lower():
		Lib.cyl(self, Vector3(0, 0.78, 0), 0.26, 0.40 if "Maxi" in pants_name else 0.33, 0.63, Lib.color_mat(cloth.lightened(0.1)))
	elif "shorts" in pants_name.to_lower():
		for x in [-0.155, 0.155]:
			Lib.cyl(self, Vector3(x, 0.85, 0), 0.15, 0.15, 0.26, legs)
	for x in [-0.155, 0.155]:
		Lib.cyl(self, Vector3(x, 0.47, 0), 0.12, 0.12, 0.75, skin_mat if "skirt" in pants_name.to_lower() or "shorts" in pants_name.to_lower() else legs)
		var shoe_name: String = Profile.OPTIONS["shoes"][clampi(int(a.get("shoes", 0)), 0, Profile.OPTIONS["shoes"].size() - 1)]
		if shoe_name != "Barefoot":
			Lib.box(self, Vector3(x, 0.10, -0.06), Vector3(0.255, 0.18, 0.39), black if shoe_name in ["Hiking boots", "Loafers", "Cowboy boots"] else trim_mat)
		if "boots" in shoe_name.to_lower():
			Lib.cyl(self, Vector3(x, 0.30, 0), 0.135, 0.135, 0.36, black)
	var top_name: String = Profile.OPTIONS["top"][clampi(int(a.get("top", 0)), 0, Profile.OPTIONS["top"].size() - 1)]
	Lib.cyl(self, Vector3(0, 1.22, 0), shoulders * 0.86, 0.23, 0.72, body_mat)
	if "dress" in top_name.to_lower() or "Overalls" in top_name:
		Lib.cyl(self, Vector3(0, 0.82, 0), 0.235, 0.46 if "Maxi" in top_name else 0.37, 0.58, body_mat)
	if "coat" in top_name.to_lower() or "jacket" in top_name.to_lower() or "Raincoat" in top_name:
		Lib.box(self, Vector3(0, 1.14, 0.205), Vector3(shoulders * 1.8, 0.7, 0.10), trim_mat)
	if "Cardigan" in top_name or "Hoodie" in top_name:
		Lib.box(self, Vector3(0, 1.37, 0.24), Vector3(0.14, 0.43, 0.04), trim_mat)
	for x in [-1.0, 1.0]:
		var sleeve: bool = "Tank" not in top_name and "Camisole" not in top_name
		Lib.cyl(self, Vector3(x * (shoulders + 0.09), 1.31, 0), 0.105, 0.095, 0.35, body_mat if sleeve else skin_mat, Vector3(0, 0, x * 0.12))
		Lib.cyl(self, Vector3(x * (shoulders + 0.10), 0.99, 0), 0.085, 0.075, 0.32, skin_mat)
		Lib.sphere(self, Vector3(x * (shoulders + 0.10), 0.81, 0), 0.105, skin_mat)
	Lib.cyl(self, Vector3(0, 1.62, 0), 0.09, 0.09, 0.16, skin_mat)
	Lib.sphere(self, Vector3(0, 1.87, 0), 0.225, skin_mat, Vector3(0.93, 1.14, 0.93))
	for x in [-0.085, 0.085]:
		Lib.sphere(self, Vector3(x, 1.895, -0.201), 0.028, black)
	Lib.box(self, Vector3(0, 1.757, -0.205), Vector3(0.10, 0.012, 0.013), Lib.color_mat(Color("9e5b5d")))
	var hairstyle: String = Profile.OPTIONS["hair"][clampi(int(a.get("hair", 0)), 0, Profile.OPTIONS["hair"].size() - 1)]
	Lib.sphere(self, Vector3(0, 2.027, 0.015), 0.222, hair_mat, Vector3(1.0, 0.59, 1.0))
	if hairstyle in ["Long straight", "Long wavy", "Loose curls", "Locs", "Curly", "Afro"]:
		Lib.sphere(self, Vector3(0, 1.79, 0.135), 0.235, hair_mat, Vector3(1.13, 1.6, 0.75))
	elif hairstyle in ["Ponytail", "High ponytail", "French braid"]:
		Lib.cyl(self, Vector3(0, 1.69, 0.23), 0.08, 0.045, 0.44, hair_mat)
	elif hairstyle in ["Twin tails", "Twin braids", "Space buns"]:
		for x in [-0.23, 0.23]:
			Lib.sphere(self, Vector3(x, 1.97, 0.07), 0.105, hair_mat, Vector3(0.8, 1.3, 0.8))
	var hat: String = Profile.OPTIONS["hat"][clampi(int(a.get("hat", 0)), 0, Profile.OPTIONS["hat"].size() - 1)]
	if hat != "None":
		Lib.cyl(self, Vector3(0, 2.12, 0), 0.19, 0.24, 0.16, trim_mat)
		if hat in ["Sun hat", "Cowboy hat", "Straw hat", "Flower crown"]:
			Lib.cyl(self, Vector3(0, 2.055, 0), 0.33, 0.33, 0.02, trim_mat)
		elif hat in ["Baseball cap", "Visor"]:
			Lib.box(self, Vector3(0, 2.05, -0.25), Vector3(0.35, 0.03, 0.26), trim_mat)
	var glasses: String = Profile.OPTIONS["glasses"][clampi(int(a.get("glasses", 0)), 0, Profile.OPTIONS["glasses"].size() - 1)]
	if glasses != "None":
		for x in [-0.105, 0.105]:
			Lib.box(self, Vector3(x, 1.89, -0.23), Vector3(0.16, 0.10, 0.023), black)
		Lib.box(self, Vector3(0, 1.90, -0.235), Vector3(0.07, 0.02, 0.02), black)
	var neck: String = Profile.OPTIONS["neckwear"][clampi(int(a.get("neckwear", 0)), 0, Profile.OPTIONS["neckwear"].size() - 1)]
	if neck != "None":
		Lib.cyl(self, Vector3(0, 1.56, 0), 0.16, 0.16, 0.07, trim_mat)
	var bag: String = Profile.OPTIONS["bag"][clampi(int(a.get("bag", 0)), 0, Profile.OPTIONS["bag"].size() - 1)]
	if bag != "None":
		Lib.box(self, Vector3(0.30 if "bag" in bag.to_lower() else 0.0, 1.14, 0.22), Vector3(0.31, 0.43, 0.19), trim_mat)
	if int(a.get("earrings", 0)) != 0:
		for x in [-0.22, 0.22]:
			Lib.sphere(self, Vector3(x, 1.82, 0), 0.045, trim_mat)
	if int(a.get("makeup", 0)) in [1, 2, 3, 4]:
		for x in [-0.15, 0.15]:
			Lib.sphere(self, Vector3(x, 1.82, -0.165), 0.04, Lib.color_mat(Color("df8996")), Vector3(1.0, 0.6, 0.3))
	if display_name != "":
		Lib.label3d(self, Vector3(0, 2.36, 0), display_name, 36)
