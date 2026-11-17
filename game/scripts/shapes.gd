extends RefCounted
## Smooth vehicle/building body builders: side-silhouette extrusion with rounded edges.
## Silhouettes are given in the (z, y) plane: Vector2(z, y). Width is along X.

static func _ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var area := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		poly = poly.duplicate()
		poly.reverse()
	return poly

static func _p3(p: Vector2, x: float) -> Vector3:
	return Vector3(x, p.y, p.x)

static func _n3(n: Vector2, x: float) -> Vector3:
	return Vector3(x, n.y, n.x)

## Extrude a side silhouette into a solid with rounded (bevelled, smooth-shaded) edges.
## glass_edges: indices of outline edges (i -> i+1) whose centre strip uses the second surface.
## caps = false leaves the two flat sides open so they can be built with real openings
## (side_with_holes on the polygon returned by inset_outline).
static func extrude(body: SurfaceTool, glass: SurfaceTool, outline: PackedVector2Array, width: float, bevel: float, glass_edges: Array = [], x0 := 0.0, caps := true) -> void:
	var poly := _ccw(outline)
	var n := poly.size()
	# outward edge normals (CCW polygon: outward = rotate edge direction clockwise)
	var en: Array[Vector2] = []
	for i in range(n):
		var d := (poly[(i + 1) % n] - poly[i]).normalized()
		en.append(Vector2(d.y, -d.x))
	var vn: Array[Vector2] = []
	var inset: Array[Vector2] = []
	for i in range(n):
		var a := en[(i - 1 + n) % n]
		var b := en[i]
		var avg := (a + b).normalized()
		if avg == Vector2.ZERO:
			avg = b
		vn.append(avg)
		var k := maxf(avg.dot(b), 0.35)
		inset.append(poly[i] - avg * bevel / k)
	var hw := width * 0.5
	var xs := [x0 - hw, x0 - hw + bevel, x0 + hw - bevel, x0 + hw]
	for i in range(n):
		var j := (i + 1) % n
		# sharp corners keep their own edge normal so they don't look melted
		var ni := vn[i] if vn[i].dot(en[i]) > 0.8 else en[i]
		var nj := vn[j] if vn[j].dot(en[i]) > 0.8 else en[i]
		var rings_i := [_p3(inset[i], xs[0]), _p3(poly[i], xs[1]), _p3(poly[i], xs[2]), _p3(inset[i], xs[3])]
		var rings_j := [_p3(inset[j], xs[0]), _p3(poly[j], xs[1]), _p3(poly[j], xs[2]), _p3(inset[j], xs[3])]
		var norm_i := [(_n3(ni, 0.0) + Vector3(-1, 0, 0)).normalized(), _n3(ni, 0.0), _n3(ni, 0.0), (_n3(ni, 0.0) + Vector3(1, 0, 0)).normalized()]
		var norm_j := [(_n3(nj, 0.0) + Vector3(-1, 0, 0)).normalized(), _n3(nj, 0.0), _n3(nj, 0.0), (_n3(nj, 0.0) + Vector3(1, 0, 0)).normalized()]
		for r in range(3):
			var st := glass if (r == 1 and glass_edges.has(i) and glass != null) else body
			var a: Vector3 = rings_i[r]
			var b: Vector3 = rings_i[r + 1]
			var c: Vector3 = rings_j[r + 1]
			var d: Vector3 = rings_j[r]
			var uv := func(p: Vector3) -> Vector2: return Vector2(p.z + p.x, p.y)
			Lib._tri(st, [a, b, c], [norm_i[r], norm_i[r + 1], norm_j[r + 1]], [uv.call(a), uv.call(b), uv.call(c)])
			Lib._tri(st, [a, c, d], [norm_i[r], norm_j[r + 1], norm_j[r]], [uv.call(a), uv.call(c), uv.call(d)])
	if not caps:
		return
	# flat sides
	var inset_poly := PackedVector2Array(inset)
	var tris := Geometry2D.triangulate_polygon(inset_poly)
	for side in [-1.0, 1.0]:
		var x: float = x0 + side * hw
		var nrm := Vector3(side, 0, 0)
		for t in range(0, tris.size(), 3):
			var pa := _p3(inset_poly[tris[t]], x)
			var pb := _p3(inset_poly[tris[t + 1]], x)
			var pc := _p3(inset_poly[tris[t + 2]], x)
			Lib._tri(body, [pa, pb, pc], [nrm, nrm, nrm], [Vector2(pa.z, pa.y), Vector2(pb.z, pb.y), Vector2(pc.z, pc.y)])

## A flat polygon (window, decal, door seam) placed on the side of a body at x, facing ±X.
static func side_panel(st: SurfaceTool, poly: PackedVector2Array, x: float, facing: float) -> void:
	var p := _ccw(poly)
	var tris := Geometry2D.triangulate_polygon(p)
	var nrm := Vector3(facing, 0, 0)
	for t in range(0, tris.size(), 3):
		var pa := _p3(p[tris[t]], x)
		var pb := _p3(p[tris[t + 1]], x)
		var pc := _p3(p[tris[t + 2]], x)
		Lib._tri(st, [pa, pb, pc], [nrm, nrm, nrm], [Vector2(pa.z, pa.y), Vector2(pb.z, pb.y), Vector2(pc.z, pc.y)])

## Polygon offset helper (shrinks a window outline etc).
static func shrink(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var r := Geometry2D.offset_polygon(_ccw(poly), -d, Geometry2D.JOIN_MITER)
	return r[0] if r.size() > 0 else poly

## Bottom edge with semicircular wheel arches. arches: Array of [z_center, radius]. Returns points from z_rear to z_front at y.
static func arched_bottom(z_rear: float, z_front: float, y: float, arches: Array, segs := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(z_rear, y))
	var sorted := arches.duplicate()
	sorted.sort_custom(func(a, b): return a[0] < b[0])
	for a in sorted:
		var zc: float = a[0]
		var r: float = a[1]
		for k in range(segs + 1):
			var ang := PI - PI * k / segs
			pts.append(Vector2(zc + cos(ang) * r, y + maxf(sin(ang) * r, 0.0)))
	pts.append(Vector2(z_front, y))
	return pts

static func commit(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in parts:
		var st: SurfaceTool = s[0]
		var probe := st.commit_to_arrays()
		if probe[Mesh.ARRAY_VERTEX] == null or (probe[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, s[1])
	return mesh

static func st() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	return s

## The flat-side outline extrude() uses for an outline and bevel.
static func inset_outline(outline: PackedVector2Array, bevel: float) -> PackedVector2Array:
	var poly := _ccw(outline)
	var n := poly.size()
	var en: Array[Vector2] = []
	for i in range(n):
		var d := (poly[(i + 1) % n] - poly[i]).normalized()
		en.append(Vector2(d.y, -d.x))
	var out := PackedVector2Array()
	for i in range(n):
		var a := en[(i - 1 + n) % n]
		var b := en[i]
		var avg := (a + b).normalized()
		if avg == Vector2.ZERO:
			avg = b
		var k := maxf(avg.dot(b), 0.35)
		out.append(poly[i] - avg * bevel / k)
	return out

## A flat side skin with real openings cut through it. Each hole is a convex polygon in (z, y),
## or a rectangle [z0, z1, y0, y1]. The outline is cut into vertical strips at every hole corner
## and the holes are clipped out of each strip, so every piece is a simple polygon.
static func side_with_holes(st: SurfaceTool, outline: PackedVector2Array, holes: Array, x: float, facing: float) -> void:
	var poly := _ccw(outline)
	var hp: Array[PackedVector2Array] = []
	for h in holes:
		if h is PackedVector2Array:
			hp.append(_ccw(h))
		else:
			hp.append(PackedVector2Array([Vector2(h[0], h[2]), Vector2(h[1], h[2]), Vector2(h[1], h[3]), Vector2(h[0], h[3])]))
	var zmin := INF
	var zmax := -INF
	var ymin := INF
	var ymax := -INF
	for p in poly:
		zmin = minf(zmin, p.x)
		zmax = maxf(zmax, p.x)
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	var cuts: Array[float] = [zmin, zmax]
	for h in hp:
		for v in h:
			if v.x > zmin and v.x < zmax:
				cuts.append(v.x)
	cuts.sort()
	for i in range(cuts.size() - 1):
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		if b - a < 0.0005:
			continue
		var strip := PackedVector2Array([Vector2(a, ymin - 1.0), Vector2(b, ymin - 1.0), Vector2(b, ymax + 1.0), Vector2(a, ymax + 1.0)])
		var parts: Array = Geometry2D.intersect_polygons(poly, strip)
		for h in hp:
			for hs in Geometry2D.intersect_polygons(h, strip):
				# stretch the hole slice past the strip edges so it cuts clean through
				var cut := PackedVector2Array()
				for v in hs:
					var vz := v.x
					if absf(vz - a) < 0.002:
						vz = a - 0.01
					elif absf(vz - b) < 0.002:
						vz = b + 0.01
					cut.append(Vector2(vz, v.y))
				var next: Array = []
				for pc in parts:
					next.append_array(Geometry2D.clip_polygons(pc, cut))
				parts = next
		for pc in parts:
			if pc.size() >= 3:
				side_panel(st, pc, x, facing)
