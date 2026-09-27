extends RefCounted
const SEGMENTS := preload("res://src/boat/rope_contact_geometry.gd")
const POINT := preload("res://src/boat/mesh_rope_obstacle.gd")

## Witnesses are ordered [segment point, triangle point]. Condition the
## engine intersection query in millimetres around a local origin.
static func segment_triangle(a: Vector3,b: Vector3,p: Vector3,q: Vector3,r: Vector3) -> PackedVector3Array:
	var intersection: Variant=Geometry3D.segment_intersects_triangle(Vector3.ZERO,(b-a)*1000,(p-a)*1000,(q-a)*1000,(r-a)*1000)
	if intersection!=null:
		var hit: Vector3=a+intersection*.001
		return PackedVector3Array([hit,hit])
	var nearest := POINT._triangle_point(a,p,q,r)
	var pair := PackedVector3Array([a,nearest])
	var squared := a.distance_squared_to(nearest)
	nearest=POINT._triangle_point(b,p,q,r)
	if b.distance_squared_to(nearest)<squared:
		pair=PackedVector3Array([b,nearest])
		squared=b.distance_squared_to(nearest)
	for edge in [[p,q],[q,r],[r,p]]:
		var candidate := SEGMENTS.closest_segments(a,b,edge[0],edge[1])
		var distance := candidate[0].distance_squared_to(candidate[1])
		if distance<squared:
			pair=candidate
			squared=distance
	return pair

static func triangles(a: Vector3,b: Vector3,c: Vector3,p: Vector3,q: Vector3,r: Vector3) -> PackedVector3Array:
	# Two disjoint triangles attain their distance at a vertex/face or an
	# edge/edge pair. Enumerate each feature once: routing all six edges
	# through segment_triangle repeated vertices and every edge pair twice.
	# Intersections must still be tested first, including an edge piercing
	# the interior of the opposite face with no close endpoint.
	var first := [a,b,c]
	var last := [p,q,r]
	for index in 3:
		var origin: Vector3=first[index]
		var hit: Variant=Geometry3D.segment_intersects_triangle(Vector3.ZERO,(first[(index+1)%3]-origin)*1000,(p-origin)*1000,(q-origin)*1000,(r-origin)*1000)
		if hit!=null:
			var point: Vector3=origin+hit*.001
			return PackedVector3Array([point,point])
		origin=last[index]
		hit=Geometry3D.segment_intersects_triangle(Vector3.ZERO,(last[(index+1)%3]-origin)*1000,(a-origin)*1000,(b-origin)*1000,(c-origin)*1000)
		if hit!=null:
			var point: Vector3=origin+hit*.001
			return PackedVector3Array([point,point])
	var pair := PackedVector3Array([a,p])
	var squared := INF
	for vertex: Vector3 in first:
		var nearest := POINT._triangle_point(vertex,p,q,r)
		var distance := vertex.distance_squared_to(nearest)
		if distance<squared:
			pair=PackedVector3Array([vertex,nearest])
			squared=distance
		if squared<1e-20: return pair
	for vertex: Vector3 in last:
		var nearest := POINT._triangle_point(vertex,a,b,c)
		var distance := vertex.distance_squared_to(nearest)
		if distance<squared:
			pair=PackedVector3Array([nearest,vertex])
			squared=distance
		if squared<1e-20: return pair
	for i in 3:
		for j in 3:
			var candidate := SEGMENTS.closest_segments(first[i],first[(i+1)%3],last[j],last[(j+1)%3])
			var distance := candidate[0].distance_squared_to(candidate[1])
			if distance<squared:
				pair=candidate
				squared=distance
			if squared<1e-20: return pair
	return pair

static func box_distance_squared(first: AABB,last: AABB) -> float:
	var delta := Vector3.ZERO
	for axis in 3: delta[axis]=maxf(0,maxf(first.position[axis]-last.end[axis],last.position[axis]-first.end[axis]))
	return delta.length_squared()
