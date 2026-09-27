extends RefCounted
static var geometry_cache := {}

## Read render vertices/indices without TriangleMesh's 0.1 mm weld grid.
## Call on the main thread; workers receive only the returned numeric copy.
static func faces(mesh: Mesh) -> PackedVector3Array:
	var result := PackedVector3Array()
	if mesh==null: return result
	var identity := mesh.get_rid().get_id()
	var sources := []
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: return PackedVector3Array()
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return PackedVector3Array()
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant=arrays[Mesh.ARRAY_INDEX]
		sources.append([vertices,indices])
	# Compare the real source arrays, not only RID/count/AABB. A mutable mesh
	# can change without replacing its resource or its bounds. Packed-array
	# equality is native and preserves exact geometry-cache invalidation.
	if geometry_cache.has(identity) and geometry_cache[identity].sources==sources:
		return geometry_cache[identity].faces.duplicate()
	for source in sources:
		var vertices: PackedVector3Array=source[0]
		var indices: Variant=source[1]
		if indices is PackedInt32Array and not indices.is_empty():
			if indices.size()%3!=0: return PackedVector3Array()
			for index: int in indices:
				if index<0 or index>=vertices.size(): return PackedVector3Array()
				result.append(vertices[index])
		else:
			if vertices.size()%3!=0: return PackedVector3Array()
			result.append_array(vertices)
	if geometry_cache.size()>=256: geometry_cache.erase(geometry_cache.keys()[0])
	geometry_cache[identity]={"sources":sources,"faces":result.duplicate()}
	return result
