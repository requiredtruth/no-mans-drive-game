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
	var top_name: String = Profile.OPTIONS["top"][clampi(int(a.get("top", 0)), 0, Profile.OPTIONS["top"].size() - 1)]
	var wearing_dress := "dress" in top_name.to_lower()
	var pants_name: String = Profile.OPTIONS["bottom"][clampi(int(a.get("bottom", 0)), 0, Profile.OPTIONS["bottom"].size() - 1)]
	if "skirt" in pants_name.to_lower() and not wearing_dress:
		Lib.cyl(self, Vector3(0, 0.78, 0), 0.26, 0.40 if "Maxi" in pants_name else 0.33, 0.63, Lib.color_mat(cloth.lightened(0.1)))
	elif "shorts" in pants_name.to_lower() and not wearing_dress:
		for x in [-0.155, 0.155]:
			Lib.cyl(self, Vector3(x, 0.85, 0), 0.15, 0.15, 0.26, legs)
	for x in [-0.155, 0.155]:
		Lib.cyl(self, Vector3(x, 0.47, 0), 0.12, 0.12, 0.75, skin_mat if wearing_dress or "skirt" in pants_name.to_lower() or "shorts" in pants_name.to_lower() else legs)
		var shoe_name: String = Profile.OPTIONS["shoes"][clampi(int(a.get("shoes", 0)), 0, Profile.OPTIONS["shoes"].size() - 1)]
		if shoe_name != "Barefoot":
			Lib.box(self, Vector3(x, 0.10, -0.06), Vector3(0.255, 0.18, 0.39), black if shoe_name in ["Hiking boots", "Loafers", "Cowboy boots"] else trim_mat)
		if "boots" in shoe_name.to_lower():
			Lib.cyl(self, Vector3(x, 0.30, 0), 0.135, 0.135, 0.36, black)
	# A single smoothly sculpted garment surface avoids separate circular chest
	# pieces, which looked unnatural from the front and side. All tops use it.
	if gender == 0:
		_female_upper_body(body_mat, shoulders, build)
	else:
		Lib.cyl(self, Vector3(0, 1.22, 0), shoulders * 0.86, 0.23, 0.72, body_mat)
	if wearing_dress:
		# Smooth flared fabric, fitted waist and a contrasting neckline;
		# pants are hidden under the dress instead of clipping through it.
		Lib.cyl(self, Vector3(0, 0.88, 0), 0.20, 0.46 if "Maxi" in top_name else 0.39, 0.80, body_mat, Vector3.ZERO, 28)
		Lib.cyl(self, Vector3(0, 1.14, 0), 0.225, 0.225, 0.055, trim_mat, Vector3.ZERO, 28)
		Lib.box(self, Vector3(0, 1.48, -0.225), Vector3(0.22, 0.055, 0.045), trim_mat)
	elif "Overalls" in top_name:
		Lib.cyl(self, Vector3(0, 0.82, 0), 0.235, 0.37, 0.58, body_mat)
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
	# Sculpt readable front-facing eyes, brows, nose and mouth. The original
	# eyes were tiny dark dots that disappeared behind the hair at game scale.
	_add_face(skin, hair, gender, int(a.get("makeup", 0)))
	var hairstyle: String = Profile.OPTIONS["hair"][clampi(int(a.get("hair", 0)), 0, Profile.OPTIONS["hair"].size() - 1)]
	# Keep the forehead/hairline above the eyes so the face stays uncovered.
	Lib.sphere(self, Vector3(0, 2.065, 0.047), 0.220, hair_mat, Vector3(1.0, 0.50, 1.0))
	if hairstyle in ["Long straight", "Long wavy", "Loose curls", "Locs", "Curly", "Afro"]:
		# Shoulder-to-midback length, with visible strands and a clean face.
		Lib.sphere(self, Vector3(0, 1.74, 0.145), 0.235, hair_mat, Vector3(1.1, 1.9, 0.8))
		if hairstyle in ["Long straight", "Long wavy", "Loose curls"]:
			for i in range(7):
				var x := (float(i) - 3.0) * 0.067
				Lib.cyl(self, Vector3(x, 1.49, 0.17), 0.045, 0.032, 0.54, hair_mat, Vector3(0.10 if i % 2 == 0 else -0.10, 0, 0), 10)
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


## Eyes and expression, positioned on the front (-Z) of the actual head.
## Works for both genders, all skin tones, and wardrobe/makeup choices.
func _add_face(skin: Color, hair: Color, gender: int, makeup: int) -> void:
	var white := Lib.color_mat(Color("f9f4eb"))
	var iris := Lib.color_mat(Color("597f80") if gender == 0 else Color("6b5140"))
	var pupil := Lib.color_mat(Color("171b25"))
	var brow := Lib.color_mat(hair.darkened(0.27))
	var lip_color := Color("b85d76") if gender == 0 else Color("9b6260")
	if makeup == 2:
		lip_color = Color("e979a1")
	elif makeup == 3:
		lip_color = Color("c73753")
	elif makeup == 4:
		lip_color = Color("853858")
	var lips := Lib.color_mat(lip_color)
	var nose := Lib.color_mat(skin.lightened(0.045))
	for sign in [-1.0, 1.0]:
		var x: float = sign * 0.085
		# Head surface at eye height is just behind -0.18. Layer the
		# white/iris/pupil slightly forward to be legible from a few metres.
		Lib.sphere(self, Vector3(x, 1.921, -0.192), 0.043, brow, Vector3(1.22, 0.80, 0.38))
		Lib.sphere(self, Vector3(x, 1.922, -0.206), 0.038, white, Vector3(1.0, 0.77, 0.48))
		Lib.sphere(self, Vector3(x, 1.922, -0.225), 0.021, iris, Vector3(0.94, 1.0, 0.52))
		Lib.sphere(self, Vector3(x, 1.922, -0.237), 0.011, pupil)
		Lib.sphere(self, Vector3(x - 0.008, 1.932, -0.246), 0.006, white)
		Lib.box(self, Vector3(x, 1.996, -0.183), Vector3(0.095, 0.018, 0.023), brow,
			false, Vector3(0, 0, sign * 0.10))
	Lib.sphere(self, Vector3(0, 1.827, -0.215), 0.037, nose, Vector3(0.65, 1.05, 0.85))
	Lib.sphere(self, Vector3(0, 1.767, -0.206), 0.056, lips, Vector3(1.0, 0.19, 0.22))
	Lib.sphere(self, Vector3(0, 1.752, -0.207), 0.047, lips, Vector3(1.0, 0.18, 0.22))


## Female clothing torso is one continuous smooth-shaded mesh, not two glued-on spheres.
## The shallow paired front contour follows the clothing material; no exposed anatomy.
## All outfit types, hairstyles and multiplayer avatars share the same geometry.
func _female_upper_body(material: Material, shoulder_width: float, body_build: int) -> void:
	var rings := 18
	var sides := 40
	var y_min := 0.90
	var y_max := 1.58
	var fullness := 0.105
	if body_build == 3:
		fullness = 0.080
	elif body_build == 4:
		fullness = 0.120
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in range(rings + 1):
		var y: float = lerpf(y_min, y_max, float(r) / float(rings))
		var upper: float = smoothstep(1.02, 1.52, y)
		var width: float = lerpf(0.190, shoulder_width * 0.86, upper)
		var depth: float = lerpf(0.197, 0.226, upper)
		for i in range(sides):
			var theta: float = TAU * float(i) / float(sides)
			var x: float = cosf(theta) * width
			var z: float = sinf(theta) * depth
			# The avatar faces negative Z. Add a soft symmetrical silhouette
			# at chest height, fading continuously into waist/shoulders/sides.
			var front: float = pow(maxf(-sinf(theta), 0.0), 2.0)
			var lateral: float = exp(-pow((absf(x) - 0.112) / 0.137, 2.0))
			var vertical: float = exp(-pow((y - 1.385) / 0.148, 2.0))
			z -= fullness * front * lateral * vertical
			st.add_vertex(Vector3(x, y, z))
	for r in range(rings):
		for i in range(sides):
			var nxt: int = (i + 1) % sides
			var lo: int = r * sides + i
			var hi: int = (r + 1) * sides + i
			var lo_next: int = r * sides + nxt
			var hi_next: int = (r + 1) * sides + nxt
			st.add_index(lo)
			st.add_index(hi)
			st.add_index(lo_next)
			st.add_index(hi)
			st.add_index(hi_next)
			st.add_index(lo_next)
	# Close the top of the clothing with a smooth shoulder surface.
	var crown: int = (rings + 1) * sides
	st.add_vertex(Vector3(0, y_max, 0))
	for i in range(sides):
		var top: int = rings * sides + i
		var next_top: int = rings * sides + (i + 1) % sides
		st.add_index(crown)
		st.add_index(next_top)
		st.add_index(top)
	st.generate_normals()
	var torso := MeshInstance3D.new()
	torso.mesh = st.commit()
	torso.material_override = material
	add_child(torso)
