extends Node
## Shared materials and procedurally built meshes. Autoloaded as "Lib".

var _tex := {}
var _mats := {}
var _meshes := {}
var foliage_shader: Shader = preload("res://shaders/foliage.gdshader")

func tex(tex_name: String) -> Texture2D:
	if not _tex.has(tex_name):
		_tex[tex_name] = load("res://assets/textures/%s.png" % tex_name)
	return _tex[tex_name]

## Triplanar PBR material using one of the generated textures.
func mat(tex_name: String, tint := Color.WHITE, scale := 0.4, world := true, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [tex_name, tint.to_html(), scale, world, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if tex_name != "":
		m.albedo_texture = tex(tex_name)
		if ResourceLoader.exists("res://assets/textures/%s_n.png" % tex_name):
			m.normal_enabled = true
			m.normal_texture = tex(tex_name + "_n")
			m.normal_scale = 0.8
		m.uv1_triplanar = true
		m.uv1_world_triplanar = world
		m.uv1_scale = Vector3.ONE * scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m

func color_mat(c: Color, rough := 0.7, metal := 0.0, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var key := "c|%s|%s|%s|%s|%s" % [c.to_html(), rough, metal, emission.to_html(), emission_energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

func glass_mat() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.16, 0.18, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.6
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["glass"] = m
	return _mats["glass"]

func foliage_mat(tex_name: String, wind := 0.12, sway := 1.0, tint := Color.WHITE) -> ShaderMaterial:
	var key := "f|%s|%s|%s|%s" % [tex_name, wind, sway, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = foliage_shader
	m.set_shader_parameter("tex", tex(tex_name))
	m.set_shader_parameter("wind_strength", wind)
	m.set_shader_parameter("sway_height", sway)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_mats[key] = m
	return m

# ------------------------------------------------------------------ node helpers
## Adds a textured box. Returns the MeshInstance3D. If solid, also adds a StaticBody3D collider.
func box(parent: Node3D, pos: Vector3, size: Vector3, material: Material, solid := false, rot := Vector3.ZERO, bevel := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = rounded_box(size, bevel)
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

## Box mesh with softened (bevelled, smooth-shaded) edges. Cached by size.
func rounded_box(size: Vector3, bevel := -1.0) -> Mesh:
	var r := bevel
	if r < 0.0:
		r = clampf(minf(minf(size.x, size.y), size.z) * 0.18, 0.0, 0.035)
	if r < 0.004:
		var bm := BoxMesh.new()
		bm.size = size
		return bm
	var key := "rb|%.3f|%.3f|%.3f|%.3f" % [size.x, size.y, size.z, r]
	if _meshes.has(key):
		return _meshes[key]
	var h := size * 0.5
	var inner := h - Vector3.ONE * r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for ai in range(3):
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = axes[ai] * sgn
			var u: Vector3 = axes[(ai + 1) % 3]
			var v: Vector3 = axes[(ai + 2) % 3]
			var hu: float = absf(h.dot(u))
			var hv: float = absf(h.dot(v))
			var hn: float = absf(h.dot(axes[ai]))
			var ru: float = minf(r, hu)
			var rv: float = minf(r, hv)
			var us := [-hu, -hu + ru, hu - ru, hu]
			var vs := [-hv, -hv + rv, hv - rv, hv]
			var grid := []
			var norms := []
			for i in range(4):
				var row := []
				var nrow := []
				for j in range(4):
					var p: Vector3 = n * hn + u * us[i] + v * vs[j]
					var cl := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
					var d := p - cl
					var nn := d.normalized() if d.length() > 0.00001 else n
					row.append(cl + nn * r)
					nrow.append(nn)
				grid.append(row)
				norms.append(nrow)
			for i in range(3):
				for j in range(3):
					var a: Vector3 = grid[i][j]
					var b: Vector3 = grid[i + 1][j]
					var c: Vector3 = grid[i + 1][j + 1]
					var d2: Vector3 = grid[i][j + 1]
					var na: Vector3 = norms[i][j]
					var nb: Vector3 = norms[i + 1][j]
					var nc: Vector3 = norms[i + 1][j + 1]
					var nd: Vector3 = norms[i][j + 1]
					if (b - a).length() < 0.00001 and (d2 - a).length() < 0.00001:
						continue
					_tri(st, [a, b, c], [na, nb, nc], [Vector2(a.x + a.z, a.y), Vector2(b.x + b.z, b.y), Vector2(c.x + c.z, c.y)])
					_tri(st, [a, c, d2], [na, nc, nd], [Vector2(a.x + a.z, a.y), Vector2(c.x + c.z, c.y), Vector2(d2.x + d2.z, d2.y)])
	var m := st.commit()
	_meshes[key] = m
	return m

func cyl(parent: Node3D, pos: Vector3, r_top: float, r_bot: float, h: float, material: Material, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func sphere(parent: Node3D, pos: Vector3, r: float, material: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi

func static_box(parent: Node3D, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	sb.rotation = rot
	parent.add_child(sb)
	return sb

func light(parent: Node3D, pos: Vector3, color: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.position = pos
	parent.add_child(l)
	return l

func label3d(parent: Node3D, pos: Vector3, text: String, size := 48) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 8
	parent.add_child(l)
	return l

# ------------------------------------------------------------------ procedural geometry
func _basis_for(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	return Basis(x, dir.normalized(), z)

func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, segs := 10, v_scale := 1.0) -> void:
	var dir := b - a
	var bs := _basis_for(dir)
	var length := dir.length()
	for i in range(segs):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var n0 := bs.x * cos(a0) + bs.z * sin(a0)
		var n1 := bs.x * cos(a1) + bs.z * sin(a1)
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var p := [a + n0 * ra, a + n1 * ra, b + n1 * rb, b + n0 * rb]
		var n := [n0, n1, n1, n0]
		var uv := [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, length * v_scale), Vector2(u0, length * v_scale)]
		_tri(st, [p[0], p[1], p[2]], [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]])
		_tri(st, [p[0], p[2], p[3]], [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]])

## Adds a triangle, fixing winding so its front face points along the given normals.
func _tri(st: SurfaceTool, p: Array, n: Array, uv: Array) -> void:
	var gn: Vector3 = (p[2] - p[0]).cross(p[1] - p[0])
	var order := [0, 1, 2] if gn.dot(n[0] + n[1] + n[2]) >= 0.0 else [0, 2, 1]
	for k in order:
		st.set_normal(n[k])
		st.set_uv(uv[k])
		st.add_vertex(p[k])

func _quad(st: SurfaceTool, c: Vector3, ax: Vector3, ay: Vector3, normal: Vector3, flip_v := false) -> void:
	# ax: half-width vector, ay: full length vector from c (base) to tip
	var p := [c - ax, c + ax, c + ax + ay, c - ax + ay]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	if flip_v:
		uv = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(uv[k])
		st.add_vertex(p[k])

func _commit(surfaces: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in surfaces:
		var st: SurfaceTool = s[0]
		var probe := st.commit_to_arrays()
		if probe[Mesh.ARRAY_VERTEX] == null or (probe[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, s[1])
	return mesh

func mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		_meshes[id] = _build(id)
	return _meshes[id]

func _build(id: String) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	match id:
		"pine": return _pine(rng)
		"broadleaf": return _broadleaf(rng)
		"dead": return _dead(rng)
		"cactus": return _cactus(rng)
		"bush_fiber": return _grass_clump(rng, 1.1, 14)
		"bush_berry": return _bush(rng, true)
		"bush_mushroom": return _mushrooms(rng)
		"grass": return _grass_clump(rng, 0.7, 3)
		"rock0", "rock1", "rock2": return _rock(rng)
	return BoxMesh.new()

func _pine(rng: RandomNumberGenerator) -> Mesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(bark, Vector3(0, -0.5, 0), Vector3(0, 11.5, 0), 0.32, 0.04, 10, 0.3)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers := 11
	for l in range(layers):
		var t := float(l) / (layers - 1)
		var y := lerpf(1.6, 11.0, t)
		var radius := lerpf(3.3, 0.5, pow(t, 0.9))
		var count := int(lerpf(9, 4, t))
		var off := rng.randf() * TAU
		for b in range(count):
			var ang := off + TAU * b / count + rng.randf_range(-0.2, 0.2)
			var d := Vector3(cos(ang), 0, sin(ang))
			var droop := -0.45 * radius + rng.randf_range(-0.2, 0.2)
			var ay := d * radius + Vector3(0, droop, 0)
			var side := Vector3(-d.z, 0.35, d.x).normalized() * radius * 0.45
			var n := (d + Vector3(0, 0.6, 0)).normalized()
			_quad(leaves, Vector3(0, y, 0), side, ay, n)
	# top spire cards
	for k in range(2):
		var a := k * PI * 0.5
		_quad(leaves, Vector3(0, 9.8, 0), Vector3(cos(a), 0, sin(a)) * 0.55, Vector3(0, 2.4, 0), Vector3.UP)
	return _commit([[bark, mat("bark", Color(0.9, 0.85, 0.8), 1.0, false)], [leaves, foliage_mat("needle_card", 0.18, 10.0)]])

func _broadleaf(rng: RandomNumberGenerator) -> Mesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(bark, Vector3(0, -0.5, 0), Vector3(0, 4.2, 0), 0.34, 0.2, 10, 0.3)
	var tips: Array[Vector3] = []
	for i in range(5):
		var ang := TAU * i / 5.0 + rng.randf() * 0.5
		var start := Vector3(0, rng.randf_range(3.0, 4.2), 0)
		var tip := start + Vector3(cos(ang) * rng.randf_range(1.6, 2.6), rng.randf_range(1.8, 3.0), sin(ang) * rng.randf_range(1.6, 2.6))
		_tube(bark, start, tip, 0.15, 0.05, 7, 0.3)
		tips.append(tip)
	_tube(bark, Vector3(0, 4.0, 0), Vector3(0, 7.2, 0), 0.2, 0.05, 7, 0.3)
	tips.append(Vector3(0, 7.0, 0))
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 6.2, 0)
	for i in range(70):
		var base: Vector3 = tips[i % tips.size()]
		var p := base + Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.0, 1.2), rng.randf_range(-1.4, 1.4))
		var ang := rng.randf() * TAU
		var tilt := rng.randf_range(-0.6, 0.6)
		var ax := Vector3(cos(ang), tilt, sin(ang)).normalized() * 1.25
		var ay := Vector3(-sin(ang) * 0.3, 1.0, cos(ang) * 0.3).normalized() * 2.5
		var n := (p - center).normalized()
		_quad(leaves, p - ay * 0.5, ax, ay, n)
	return _commit([[bark, mat("bark", Color.WHITE, 1.0, false)], [leaves, foliage_mat("leaf_card", 0.22, 8.0)]])

func _dead(rng: RandomNumberGenerator) -> Mesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(bark, Vector3(0, -0.5, 0), Vector3(0.2, 6.0, 0), 0.28, 0.06, 9, 0.3)
	for i in range(6):
		var y := rng.randf_range(2.0, 5.5)
		var ang := rng.randf() * TAU
		var start := Vector3(0.03 * y, y, 0)
		_tube(bark, start, start + Vector3(cos(ang) * 1.8, rng.randf_range(0.5, 1.6), sin(ang) * 1.8), 0.09, 0.02, 6, 0.3)
	return _commit([[bark, mat("bark", Color(0.75, 0.72, 0.7), 1.0, false)]])

func _cactus(rng: RandomNumberGenerator) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, Vector3(0, -0.3, 0), Vector3(0, 4.2, 0), 0.38, 0.3, 12, 0.5)
	_tube(st, Vector3(0, 4.2, 0), Vector3(0, 4.5, 0), 0.3, 0.05, 12, 0.5)
	for side in [-1.0, 1.0]:
		var y := rng.randf_range(1.4, 2.6)
		var a := Vector3(side * 0.3, y, 0)
		var b := Vector3(side * 1.1, y + 0.1, 0)
		var c := Vector3(side * 1.1, y + rng.randf_range(1.0, 1.7), 0)
		_tube(st, a, b, 0.2, 0.2, 10, 0.5)
		_tube(st, b, c, 0.2, 0.17, 10, 0.5)
	return _commit([[st, mat("grass", Color(0.45, 0.7, 0.45), 1.6, false, 0.6)]])

func _grass_clump(rng: RandomNumberGenerator, size: float, cards: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(cards):
		var a := TAU * i / cards + rng.randf() * 0.4
		var off := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)) * size * (0.0 if cards <= 3 else 1.0)
		var ax := Vector3(cos(a), 0, sin(a)) * size * 0.6
		_quad(st, off + Vector3(0, -0.05, 0), ax, Vector3(0, size, 0), Vector3.UP)
	return _commit([[st, foliage_mat("grass_card", 0.12, size)]])

func _bush(rng: RandomNumberGenerator, berries: bool) -> Mesh:
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.6, 0)
	for i in range(22):
		var p := center + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.7, 0.7))
		var ang := rng.randf() * TAU
		var ax := Vector3(cos(ang), rng.randf_range(-0.5, 0.5), sin(ang)).normalized() * 0.55
		var ay := Vector3(0, 1.1, 0)
		_quad(leaves, p - ay * 0.5, ax, ay, (p - center + Vector3(0, 0.3, 0)).normalized())
	var surfaces := [[leaves, foliage_mat("leaf_card", 0.06, 1.2, Color(0.85, 0.95, 0.8))]]
	if berries:
		var b := SurfaceTool.new()
		b.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(26):
			var p := center + Vector3(rng.randf_range(-0.75, 0.75), rng.randf_range(-0.3, 0.5), rng.randf_range(-0.75, 0.75))
			_tube(b, p, p + Vector3(0, 0.07, 0), 0.04, 0.04, 6)
		surfaces.append([b, color_mat(Color("6a1e5a"), 0.35)])
	return _commit(surfaces)

func _mushrooms(rng: RandomNumberGenerator) -> Mesh:
	var stem := SurfaceTool.new()
	stem.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var p := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var h := rng.randf_range(0.12, 0.26)
		_tube(stem, p, p + Vector3(0, h, 0), 0.03, 0.025, 8)
		_tube(cap, p + Vector3(0, h - 0.02, 0), p + Vector3(0, h + 0.06, 0), 0.11, 0.01, 10)
	return _commit([[stem, color_mat(Color("e8e0cc"))], [cap, color_mat(Color("9a5a32"), 0.6)]])

func _rock(rng: RandomNumberGenerator) -> Mesh:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var segs := 16
	var stretch := Vector3(rng.randf_range(1.0, 1.6), rng.randf_range(0.55, 0.9), rng.randf_range(0.9, 1.4))
	var pts := []
	for r in range(rings + 1):
		var row := []
		var phi := PI * r / rings
		for s in range(segs + 1):
			var th := TAU * s / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var k := 1.0 + noise.get_noise_3dv(d * 1.3) * 0.35
			var p := d * k * stretch
			p.y = maxf(p.y, -0.25)
			row.append(p)
		pts.append(row)
	for r in range(rings):
		for s in range(segs):
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s + 1]
			var c: Vector3 = pts[r + 1][s + 1]
			var d: Vector3 = pts[r + 1][s]
			for tri in [[a, b, c], [a, c, d]]:
				var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				var centroid: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				if n.dot(centroid) < 0.0:
					n = -n
				_tri(st, tri, [n, n, n], [Vector2(tri[0].x + tri[0].z, tri[0].y), Vector2(tri[1].x + tri[1].z, tri[1].y), Vector2(tri[2].x + tri[2].z, tri[2].y)])
	return _commit([[st, mat("rock", Color.WHITE, 0.5, true, 0.9)]])
