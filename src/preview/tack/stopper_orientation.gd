extends RefCounted
## Finite rigid orientation candidates for a free stopper,not a bone or
## grasp solver. Its actual anchored endpoint remains fixed.
static func _gap(path: PackedVector3Array,caps: Array) -> float:
	var gap := INF
	for index in path.size()-1:
		for cap in caps:
			var pair := Geometry3D.get_closest_points_between_segments(path[index],path[index+1],cap[0],cap[1])
			gap=minf(gap,pair[0].distance_to(pair[1])-float(cap[2]))
	return gap
static func place(baseline: PackedVector3Array,endpoint: Vector3,hull: MeshInstance3D,caps: Array) -> PackedVector3Array:
	if _gap(baseline,caps)>=.002: return baseline
	var best := baseline
	var best_gap := _gap(baseline,caps)
	for degrees: float in [30,-30,60,-60,90,-90,120,-120,180]:
		for axis: Vector3 in [Vector3.UP,Vector3.RIGHT,Vector3.FORWARD]:
			var frame := Basis(axis,deg_to_rad(degrees))
			var path := PackedVector3Array([endpoint])
			for i in range(1,baseline.size()):
				var p: Vector3=endpoint+frame*(baseline[i]-endpoint)
				p.y=maxf(p.y,hull.cockpit_floor_y_at(p.x,p.z)+.005)
				path.append(p)
			var gap := _gap(path,caps)
			if gap>=.002: return path
			if gap>best_gap: best=path; best_gap=gap
	# Preserve the best measured failure for the independent acceptance.
	return best
