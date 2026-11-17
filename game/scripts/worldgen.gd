extends RefCounted
## Deterministic, thread-safe procedural world generation.

const CHUNK := 64.0
const RES := 32 # render grid cells per chunk (2 m)
const COL := 64 # collision cells per chunk (1 m)
const ROAD_HALF := 4.6

var seed_value := 0
var n_low := FastNoiseLite.new()
var n_mid := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_biome := FastNoiseLite.new()
var n_mtn := FastNoiseLite.new()
var n_lake := FastNoiseLite.new()
var n_dune := FastNoiseLite.new()
var n_grove := FastNoiseLite.new()
var n_species := FastNoiseLite.new()

func _init(s: int) -> void:
	seed_value = s
	var all := [n_low, n_mid, n_detail, n_biome, n_mtn, n_lake, n_dune, n_grove, n_species]
	for i in range(all.size()):
		var n: FastNoiseLite = all[i]
		n.seed = s + i * 7919
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_low.frequency = 0.0022
	n_low.fractal_octaves = 2
	n_mid.frequency = 0.011
	n_mid.fractal_octaves = 3
	n_detail.frequency = 0.05
	n_detail.fractal_octaves = 2
	n_grove.frequency = 0.018
	n_grove.fractal_octaves = 3
	n_species.frequency = 0.012
	n_species.fractal_octaves = 1
	n_biome.frequency = 0.00045
	n_biome.fractal_octaves = 2
	n_mtn.frequency = 0.004
	n_mtn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_mtn.fractal_octaves = 4
	n_lake.frequency = 0.0055
	n_lake.fractal_octaves = 1
	n_dune.frequency = 0.018
	n_dune.fractal_octaves = 2

# ------------------------------------------------------------------ fields
func road_x(z: float) -> float:
	return 70.0 * sin(z * 0.0031) + 28.0 * sin(z * 0.0097 + 1.3) + 9.0 * sin(z * 0.023 + 0.4)

func road_dir(z: float) -> Vector3:
	return Vector3(road_x(z - 1.0) - road_x(z + 1.0), 0, -2.0).normalized()

func base_low(x: float, z: float) -> float:
	return n_low.get_noise_2d(x, z) * 13.0

func road_h(z: float) -> float:
	return base_low(road_x(z), z)

func biome_weights(x: float, z: float) -> Vector4:
	var b := n_biome.get_noise_2d(x, z) * 1.6
	# Start area (around origin) is always temperate forest/plains.
	var start := clampf(1.0 - Vector2(x, z).length() / 500.0, 0.0, 1.0)
	b = lerpf(b, 0.05, start)
	var desert := 1.0 - smoothstep(-0.42, -0.26, b)
	var tundra := smoothstep(0.34, 0.5, b)
	var forest := smoothstep(-0.06, 0.1, b) * (1.0 - tundra)
	var plains := maxf(0.0, 1.0 - desert - forest - tundra)
	return Vector4(desert, plains, forest, tundra)

func biome_name(x: float, z: float) -> String:
	var w := biome_weights(x, z)
	var names := ["Desert", "Grassland", "Forest", "Tundra"]
	var best := 0
	for i in range(4):
		if w[i] > w[best]:
			best = i
	return names[best]

func raw_height(x: float, z: float, w: Vector4) -> float:
	var h := base_low(x, z)
	h += n_mid.get_noise_2d(x, z) * (3.0 + 3.0 * w.z)
	h += maxf(n_mtn.get_noise_2d(x, z), 0.0) * 34.0 * w.w
	h += n_dune.get_noise_2d(x, z) * 3.2 * w.x
	h += n_detail.get_noise_2d(x, z) * 0.45
	return h

func water_level(x: float, z: float) -> float:
	return base_low(x, z) - 1.2

func lake_mask(x: float, z: float, w: Vector4) -> float:
	var d := absf(x - road_x(z))
	var m := smoothstep(0.36, 0.52, n_lake.get_noise_2d(x, z))
	return m * smoothstep(34.0, 62.0, d) * (1.0 - w.x) * (1.0 - w.w * 0.7)

func height(x: float, z: float) -> float:
	var w := biome_weights(x, z)
	var raw := raw_height(x, z, w)
	var d := absf(x - road_x(z))
	var rh := road_h(z)
	var h := lerpf(rh, raw, smoothstep(ROAD_HALF + 2.0, 30.0, d))
	var lm := lake_mask(x, z, w)
	if lm > 0.0:
		h = lerpf(h, minf(h, water_level(x, z) - 4.5 * lm), smoothstep(0.0, 0.35, lm))
	# Flatten roadside locations.
	var ci := int(floor(z / CHUNK))
	for k in [ci - 1, ci, ci + 1]:
		var poi := poi_for_row(k)
		if not poi.is_empty():
			var p: Vector3 = poi["pos"]
			var r: float = poi["radius"]
			var dd := Vector2(x - p.x, z - p.z).length()
			if dd < r + 14.0:
				h = lerpf(p.y, h, smoothstep(r, r + 14.0, dd))
	return h

func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

# ------------------------------------------------------------------ POIs
func hash3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (seed_value * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

func poi_for_row(ci: int) -> Dictionary:
	if ci == 1:
		return _start_house()
	if absi(ci) < 2:
		return {}
	var h := hash3(ci, 999, 17)
	if h % 3 != 0:
		return {}
	var types := ["gas_station", "house", "wrecks", "house", "camp_ruin", "cabin", "farm", "hamlet", "truck_stop", "house", "gas_station", "wrecks"]
	var t: String = types[(h >> 4) % types.size()]
	var z := ci * CHUNK + CHUNK * 0.5
	var side := 1.0 if (h >> 9) % 2 == 0 else -1.0
	var rx := road_x(z)
	var dir := road_dir(z)
	var perp := Vector3(-dir.z, 0, dir.x)
	var offset: float = {"wrecks": 9.0, "hamlet": 26.0, "truck_stop": 20.0}.get(t, 18.0)
	var pos := Vector3(rx, 0, z) + perp * side * offset
	pos.y = road_h(z) + 0.05
	return {"type": t, "pos": pos, "radius": {"wrecks": 6.0, "hamlet": 30.0, "truck_stop": 20.0}.get(t, 16.0), "side": side,
		"yaw": atan2(dir.x, dir.z) + (PI * 0.5 if side > 0.0 else -PI * 0.5), "row": ci}

## A house just up the road from the starting lot, across the road from it, stocked with the
## first pieces of furniture for the van (see Loot.GUARANTEED).
func _start_house() -> Dictionary:
	var z := CHUNK + 14.0
	var side := 1.0
	var dir := road_dir(z)
	var perp := Vector3(-dir.z, 0, dir.x)
	var pos := Vector3(road_x(z), 0, z) + perp * side * 18.0
	pos.y = road_h(z) + 0.05
	return {"type": "house", "pos": pos, "radius": 16.0, "side": side,
		"yaw": atan2(dir.x, dir.z) + PI * 0.5, "row": 1, "start": true}

# ------------------------------------------------------------------ chunk data (thread-safe)
func build_chunk(cx: int, cz: int, removed: Dictionary, detail: bool) -> Dictionary:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	var out := {"cx": cx, "cz": cz}
	# Heights at 1 m for collision; render mesh uses every 2nd sample.
	var hs := PackedFloat32Array()
	hs.resize((COL + 1) * (COL + 1))
	var lakes := PackedFloat32Array()
	lakes.resize((RES + 1) * (RES + 1))
	for j in range(COL + 1):
		for i in range(COL + 1):
			hs[j * (COL + 1) + i] = height(ox + i, oz + j)
	out["heights"] = hs
	# Terrain mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var step := CHUNK / RES
	var has_water := false
	for j in range(RES + 1):
		for i in range(RES + 1):
			var x := ox + i * step
			var z := oz + j * step
			var y := hs[(j * 2) * (COL + 1) + i * 2]
			verts.append(Vector3(i * step, y, j * step))
			var hi := i * 2
			var hj := j * 2
			if hi > 0 and hi < COL and hj > 0 and hj < COL:
				var dx := hs[hj * (COL + 1) + hi + 1] - hs[hj * (COL + 1) + hi - 1]
				var dz := hs[(hj + 1) * (COL + 1) + hi] - hs[(hj - 1) * (COL + 1) + hi]
				norms.append(Vector3(-dx, 2.0, -dz).normalized())
			else:
				norms.append(normal_at(x, z))
			var w := biome_weights(x, z)
			var lm := lake_mask(x, z, w)
			lakes[j * (RES + 1) + i] = lm
			if lm > 0.02 and y < water_level(x, z):
				has_water = true
			# alpha channel: wetness near water / roadside dirt
			var rd := absf(x - road_x(z))
			var dirt := maxf(1.0 - smoothstep(ROAD_HALF, ROAD_HALF + 4.0, rd), lm)
			cols.append(Color(w.x, w.z, w.w, dirt))
			uvs.append(Vector2(x, z))
	for j in range(RES):
		for i in range(RES):
			var a := j * (RES + 1) + i
			idx.append_array([a, a + 1, a + RES + 1, a + 1, a + RES + 2, a + RES + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	out["terrain"] = arrays
	if has_water:
		out["water"] = _water_mesh(ox, oz, lakes)
	# Road
	if absf(road_x(oz + CHUNK * 0.5) - (ox + CHUNK * 0.5)) < CHUNK * 0.5 + 40.0:
		var road := _road_mesh(ox, oz)
		if not road.is_empty():
			out["road"] = road
	# Vegetation & features
	var rng := RandomNumberGenerator.new()
	rng.seed = hash3(cx, cz, 1)
	var cw := biome_weights(ox + 32.0, oz + 32.0)
	var feats := []
	# Trees grow in groves with clearings between them; species form stands rather than a random mix.
	for t in range(140):
		var lx := rng.randf() * CHUNK
		var lz := rng.randf() * CHUNK
		var x := ox + lx
		var z := oz + lz
		var key := "t%d_%d_%d" % [cx, cz, t]
		var w := biome_weights(x, z)
		var grove := smoothstep(-0.25, 0.35, n_grove.get_noise_2d(x, z))
		var density := w.z * (0.05 + 0.55 * grove) + w.w * 0.28 * grove + w.y * 0.035 * grove + w.x * 0.012
		if rng.randf() > density:
			continue
		if absf(x - road_x(z)) < ROAD_HALF + 6.5 or removed.has(key):
			continue
		var y := hs_sample(hs, lx, lz)
		var slope := Vector2(hs_sample(hs, lx + 1.0, lz) - hs_sample(hs, lx - 1.0, lz), hs_sample(hs, lx, lz + 1.0) - hs_sample(hs, lx, lz - 1.0)).length() * 0.5
		if slope > 0.75:
			continue
		if lake_mask(x, z, w) > 0.05 and y < water_level(x, z) + 0.4:
			continue
		if _near_poi(x, z, 4.0):
			continue
		var sp := n_species.get_noise_2d(x, z)
		var r := rng.randf()
		var kind := "broadleaf"
		if w.x > 0.5:
			kind = "cactus" if r < 0.75 else "dead"
		elif w.w > 0.5:
			kind = "pine" if r < 0.92 else "dead"
		elif w.z > 0.4:
			kind = ("pine" if sp > 0.0 else "broadleaf") if r < 0.9 else ("broadleaf" if sp > 0.0 else "pine")
			if r > 0.98:
				kind = "dead"
		else:
			kind = "broadleaf" if sp < 0.25 else "pine"
		var s := lerpf(0.75, 1.3, grove) * rng.randf_range(0.85, 1.15)
		feats.append({"t": "tree", "kind": kind, "pos": Vector3(x, y - 0.1, z), "rot": rng.randf() * TAU,
			"scale": s, "key": key, "tint": rng.randf_range(0.85, 1.1)})
	# Fallen sticks and loose stones you can pick up by hand.
	for t in range(int(3 + cw.z * 8 + cw.w * 3)):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var key := "p%d_%d_%d" % [cx, cz, t]
		if removed.has(key) or absf(x - road_x(z)) < ROAD_HALF + 1.0 or _near_poi(x, z, 1.0) or is_water(x, z, 0.0):
			continue
		var item := "wood" if rng.randf() < 0.6 + cw.z * 0.3 - cw.x * 0.5 else "stone"
		feats.append({"t": "pickup", "item": item, "pos": Vector3(x, hs_sample(hs, x - ox, z - oz), z), "rot": rng.randf() * TAU, "key": key})
	var rock_count := int(3 + cw.w * 8 + cw.x * 5)
	for t in range(rock_count):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var key := "r%d_%d_%d" % [cx, cz, t]
		if absf(x - road_x(z)) < ROAD_HALF + 2.0 or removed.has(key) or _near_poi(x, z, 3.0):
			continue
		feats.append({"t": "rock", "variant": rng.randi() % 3, "pos": Vector3(x, hs_sample(hs, x - ox, z - oz) - 0.2, z),
			"rot": rng.randf() * TAU, "scale": rng.randf_range(0.6, 1.8), "key": key})
	var bush_count := int(4 + cw.y * 10 + cw.z * 10)
	for t in range(bush_count):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var key := "b%d_%d_%d" % [cx, cz, t]
		var w := biome_weights(x, z)
		if absf(x - road_x(z)) < ROAD_HALF + 1.5 or _near_poi(x, z, 2.0) or lake_mask(x, z, w) > 0.2:
			continue
		var kind := "fiber"
		var r := rng.randf()
		if w.x > 0.5:
			kind = "fiber"
		elif r < 0.35:
			kind = "berry"
		elif r < 0.5 and w.z > 0.3:
			kind = "mushroom"
		feats.append({"t": "bush", "kind": kind, "pos": Vector3(x, hs_sample(hs, x - ox, z - oz), z), "rot": rng.randf() * TAU,
			"scale": rng.randf_range(0.8, 1.3), "key": key})
	# scrap piles / loot in the wild
	if rng.randf() < 0.18:
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var key := "s%d_%d" % [cx, cz]
		if not removed.has(key) and absf(x - road_x(z)) > 8.0:
			feats.append({"t": "scrap", "pos": Vector3(x, hs_sample(hs, x - ox, z - oz), z), "rot": rng.randf() * TAU, "key": key})
	out["features"] = feats
	# Grass cards
	if detail:
		var grass := PackedVector3Array()
		var gcount := int(cw.y * 3000 + cw.z * 1500 + cw.w * 300)
		for g in range(gcount):
			var x := ox + rng.randf() * CHUNK
			var z := oz + rng.randf() * CHUNK
			if absf(x - road_x(z)) < ROAD_HALF + 0.8 or _near_poi(x, z, 1.0):
				continue
			var w := biome_weights(x, z)
			var patch := 0.3 + 0.7 * smoothstep(-0.35, 0.25, n_species.get_noise_2d(x * 2.0, z * 2.0))
			var under_canopy := smoothstep(-0.25, 0.35, n_grove.get_noise_2d(x, z)) * w.z
			if rng.randf() > (w.y + w.z * 0.7 + w.w * 0.15) * patch * (1.0 - under_canopy * 0.6):
				continue
			var y := hs_sample(hs, x - ox, z - oz)
			if lake_mask(x, z, w) > 0.05 and y < water_level(x, z) + 0.1:
				continue
			grass.append(Vector3(x, y, z))
		out["grass"] = grass
	return out

## Bilinear height lookup from a chunk's 1 m height grid (local coords).
func hs_sample(hs: PackedFloat32Array, lx: float, lz: float) -> float:
	lx = clampf(lx, 0.0, COL - 0.001)
	lz = clampf(lz, 0.0, COL - 0.001)
	var i := int(lx)
	var j := int(lz)
	var fx := lx - i
	var fz := lz - j
	var w := COL + 1
	var a := lerpf(hs[j * w + i], hs[j * w + i + 1], fx)
	var b := lerpf(hs[(j + 1) * w + i], hs[(j + 1) * w + i + 1], fx)
	return lerpf(a, b, fz)

func is_water(x: float, z: float, depth := 0.3) -> bool:
	var w := biome_weights(x, z)
	return lake_mask(x, z, w) > 0.02 and height(x, z) < water_level(x, z) - depth

func _near_poi(x: float, z: float, margin: float) -> bool:
	var ci := int(floor(z / CHUNK))
	for k in [ci - 1, ci, ci + 1]:
		var poi := poi_for_row(k)
		if not poi.is_empty():
			var p: Vector3 = poi["pos"]
			if Vector2(x - p.x, z - p.z).length() < float(poi["radius"]) + margin:
				return true
	return false

func _water_mesh(ox: float, oz: float, lakes: PackedFloat32Array) -> Array:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var step := CHUNK / RES
	for j in range(RES + 1):
		for i in range(RES + 1):
			var x := ox + i * step
			var z := oz + j * step
			verts.append(Vector3(i * step, water_level(x, z), j * step))
	for j in range(RES):
		for i in range(RES):
			var a := j * (RES + 1) + i
			var m := maxf(maxf(lakes[a], lakes[a + 1]), maxf(lakes[a + RES + 1], lakes[a + RES + 2]))
			if m > 0.01:
				idx.append_array([a, a + 1, a + RES + 1, a + 1, a + RES + 2, a + RES + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays

func _road_mesh(ox: float, oz: float) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var segs := 32
	var half := ROAD_HALF + 0.6
	for s in range(segs + 1):
		var z := oz + s * (CHUNK / segs)
		var rx := road_x(z)
		var dir := road_dir(z)
		var perp := Vector3(-dir.z, 0, dir.x)
		for k in range(5):
			var t := -1.0 + k * 0.5
			var p := Vector3(rx, 0, z) + perp * t * half
			p.y = height(p.x, p.z) + 0.06 + (0.03 if absf(t) < 0.9 else 0.0)
			verts.append(Vector3(p.x - ox, p.y, p.z - oz))
			norms.append(Vector3.UP)
			uvs.append(Vector2((t + 1.0) * 0.5, z / 8.0))
	for s in range(segs):
		for k in range(4):
			var a := s * 5 + k
			idx.append_array([a, a + 1, a + 5, a + 1, a + 6, a + 5])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays
