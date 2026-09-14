extends RefCounted

# Subtract convex footprints from a triangle without filling an interior hole.
# Split points retain the original surface height and interpolated normal.
static func subtract_triangle(points: Array, outline: PackedVector2Array, projection := Transform3D.IDENTITY) -> Array:
	var kept := []
	var remaining := points
	for edge_index in outline.size():
		var origin := outline[edge_index]
		var direction := outline[(edge_index + 1) % outline.size()] - origin
		var wholly_outside := true
		for point in points:
			var projected: Vector3 = projection * point.p
			if direction.cross(Vector2(projected.x, projected.z) - origin) >= 0.0:
				wholly_outside = false
				break
		if wholly_outside: return [points]
	for edge_index in outline.size():
		if remaining.size() < 3: break
		var a := outline[edge_index]
		var edge := outline[(edge_index + 1) % outline.size()] - a
		var inside := []
		var outside := []
		for index in remaining.size():
			var first: Dictionary = remaining[index]
			var second: Dictionary = remaining[(index + 1) % remaining.size()]
			var p0: Vector3 = projection * first.p
			var p1: Vector3 = projection * second.p
			var d0 := edge.cross(Vector2(p0.x, p0.z) - a)
			var d1 := edge.cross(Vector2(p1.x, p1.z) - a)
			if d0 >= 0.0: inside.append(first)
			else: outside.append(first)
			if (d0 < 0.0) != (d1 < 0.0):
				var t := d0 / (d0 - d1)
				var cut := {"p": (first.p as Vector3).lerp(second.p, t), "n": (first.n as Vector3).lerp(second.n, t).normalized()}
				inside.append(cut)
				outside.append(cut)
		if outside.size() >= 3: kept.append(outside)
		remaining = inside
	return kept

static func apply(source: ArrayMesh, surface_holes: Dictionary, cut_frame := Transform3D.IDENTITY) -> ArrayMesh:
	var result := ArrayMesh.new()
	var projection := cut_frame.affine_inverse()
	for surface_index in source.get_surface_count():
		var data := source.surface_get_arrays(surface_index)
		if not surface_holes.has(surface_index):
			_repair_slivers(data, [], projection)
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
			result.surface_set_material(surface_index, source.surface_get_material(surface_index))
			continue
		var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for offset in range(0, count, 3):
			var triangle := []
			var bounds := Rect2()
			for corner in 3:
				var index := indices[offset + corner] if not indices.is_empty() else offset + corner
				triangle.append({"p": vertices[index], "n": normals[index]})
				var projected: Vector3 = projection * vertices[index]
				var point := Vector2(projected.x, projected.z)
				bounds = Rect2(point, Vector2.ZERO) if corner == 0 else bounds.expand(point)
			var polygons := [triangle]
			for outline: PackedVector2Array in surface_holes.get(surface_index, []):
				var hole_bounds := Rect2(outline[0], Vector2.ZERO)
				for point in outline: hole_bounds = hole_bounds.expand(point)
				if not bounds.intersects(hole_bounds): continue
				var next := []
				for polygon in polygons: next.append_array(subtract_triangle(polygon, outline, projection))
				polygons = next
			for polygon in polygons:
				for index in range(1, polygon.size() - 1):
					var a: Vector3 = polygon[0].p
					var b: Vector3 = polygon[index].p
					var c: Vector3 = polygon[index + 1].p
					if (b - a).cross(c - a).length_squared() < 1e-18: continue
					for corner in [polygon[0], polygon[index], polygon[index + 1]]:
						surface.set_normal(corner.n)
						surface.add_vertex(corner.p)
		surface.index()
		var arrays := surface.commit_to_arrays()
		_repair_slivers(arrays, surface_holes.get(surface_index, []), projection)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface_index, source.surface_get_material(surface_index))
	return result

# Prefer diagonal flips. Sub-millimetre remnants at clip intersections are then
# welded consistently across their incident faces, never just left as holes.
static func _repair_slivers(data: Array, outlines: Array, projection := Transform3D.IDENTITY) -> void:
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	var position_ids := {}
	var ids := PackedInt32Array()
	for point in vertices:
		var key := point.snapped(Vector3.ONE * 0.000001)
		if not position_ids.has(key): position_ids[key] = position_ids.size()
		ids.append(position_ids[key])
	var edges := {}
	var small := []
	for face in range(0, indices.size(), 3):
		var cross := (vertices[indices[face + 1]] - vertices[indices[face]]).cross(vertices[indices[face + 2]] - vertices[indices[face]])
		if cross.length_squared() <= 1e-14: small.append(face)
		_register_edges(edges, ids, indices, face, true)
	for face: int in small:
		var old := PackedInt32Array([indices[face], indices[face + 1], indices[face + 2]])
		var normal := (vertices[old[1]] - vertices[old[0]]).cross(vertices[old[2]] - vertices[old[0]]).normalized()
		for edge in 3:
			var s := old[edge]
			var t := old[(edge + 1) % 3]
			var a := old[(edge + 2) % 3]
			var neighbours: Array = edges.get(_edge_key(ids[s], ids[t]), [])
			if neighbours.size() != 2: continue
			var other: int = neighbours[1] if neighbours[0] == face else neighbours[0]
			var b := -1
			for corner in 3:
				var candidate := indices[other + corner]
				if ids[candidate] != ids[s] and ids[candidate] != ids[t]: b = candidate
			if b < 0 or absf((vertices[b] - vertices[a]).dot(normal)) > 0.00001: continue
			var cross0 := (vertices[s] - vertices[a]).cross(vertices[b] - vertices[a])
			var cross1 := (vertices[b] - vertices[a]).cross(vertices[t] - vertices[a])
			if minf(cross0.length_squared(), cross1.length_squared()) <= 1e-14: continue
			if cross0.normalized().dot(normal) < 0.999 or cross1.normalized().dot(normal) < 0.999: continue
			_register_edges(edges, ids, indices, face, false)
			_register_edges(edges, ids, indices, other, false)
			indices[face] = a
			indices[face + 1] = s
			indices[face + 2] = b
			indices[other] = a
			indices[other + 1] = b
			indices[other + 2] = t
			_register_edges(edges, ids, indices, face, true)
			_register_edges(edges, ids, indices, other, true)
			break
	data[Mesh.ARRAY_INDEX] = indices
	_weld_short_edges(data, outlines, projection)

static func _weld_short_edges(data: Array, outlines: Array, projection := Transform3D.IDENTITY) -> void:
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	# Each contraction is at most 0.5 mm; retain an aperture-boundary endpoint
	# when the other endpoint is interior. All copies of either endpoint move.
	for pass_index in 4:
		var changed := false
		for face in range(0, indices.size(), 3):
			var p := PackedVector3Array([vertices[indices[face]], vertices[indices[face + 1]], vertices[indices[face + 2]]])
			var area := (p[1] - p[0]).cross(p[2] - p[0]).length_squared()
			if area <= 1e-18 or area > 1e-14: continue
			var shortest := 0
			for edge in range(1, 3):
				if p[edge].distance_squared_to(p[(edge + 1) % 3]) < p[shortest].distance_squared_to(p[(shortest + 1) % 3]): shortest = edge
			var a := p[shortest]
			var b := p[(shortest + 1) % 3]
			if a.distance_to(b) > 0.0005: continue
			var target := (a + b) * 0.5
			if _on_boundary(a, outlines, projection): target = a
			elif _on_boundary(b, outlines, projection): target = b
			for index in vertices.size():
				if vertices[index].distance_squared_to(a) < 1e-12 or vertices[index].distance_squared_to(b) < 1e-12: vertices[index] = target
			changed = true
		if not changed: break
	var kept := PackedInt32Array()
	for face in range(0, indices.size(), 3):
		var a := vertices[indices[face]]
		var b := vertices[indices[face + 1]]
		var c := vertices[indices[face + 2]]
		if (b - a).cross(c - a).length_squared() <= 1e-18: continue
		kept.append_array(PackedInt32Array([indices[face], indices[face + 1], indices[face + 2]]))
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_INDEX] = kept

static func _on_boundary(point: Vector3, outlines: Array, projection := Transform3D.IDENTITY) -> bool:
	var projected := projection * point
	var p := Vector2(projected.x, projected.z)
	for outline: PackedVector2Array in outlines:
		for index in outline.size():
			var a := outline[index]
			var d := outline[(index + 1) % outline.size()] - a
			var t := clampf((p - a).dot(d) / maxf(d.length_squared(), 1e-12), 0.0, 1.0)
			if p.distance_squared_to(a + d * t) <= 1e-12: return true
	return false

static func _edge_key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))

static func _register_edges(edges: Dictionary, ids: PackedInt32Array, indices: PackedInt32Array, face: int, add: bool) -> void:
	for corner in 3:
		var key := _edge_key(ids[indices[face + corner]], ids[indices[face + (corner + 1) % 3]])
		if not edges.has(key): edges[key] = []
		if add: edges[key].append(face)
		else: edges[key].erase(face)

static func capsule(center: Vector2, half_length: float, radius: float, steps := 16) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for end in [-1.0, 1.0]:
		for index in range(steps + 1):
			var angle := PI * float(index) / float(steps) + (PI if end < 0.0 else 0.0)
			outline.append(center + Vector2(cos(angle) * radius, end * (half_length - radius) + sin(angle) * radius))
		# Shared longitudinal subdivisions let the rim and liner follow a
		# curved foreland instead of bridging it with one long flat polygon.
		for index in range(1, steps):
			var z: float = lerpf(end * (half_length - radius), -end * (half_length - radius), float(index) / steps)
			outline.append(center + Vector2(-end * radius, z))
	return outline

static func circle(center: Vector2, radius: float, steps := 40) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for index in steps:
		var angle := TAU * float(index) / float(steps)
		outline.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return outline
