extends RefCounted
## Preserve the endpoint/hand knots and add only terrain support,not a
## spring curve. Near-floor segments are sampled at4mm before tube output.
static func path(points: PackedVector3Array,hull: MeshInstance3D) -> PackedVector3Array:
	if points.size()<2: return points
	var result := PackedVector3Array([points[0]])
	for index in points.size()-1:
		var count := maxi(1,ceili(points[index].distance_to(points[index+1])/.004))
		for part in range(1,count+1):
			var p: Vector3=points[index].lerp(points[index+1],part/float(count))
			var floor_y: float=hull.cockpit_floor_y_at(p.x,p.z)
			var endpoint: bool=part==count
			if endpoint and index==points.size()-2: result.append(p); continue
			if endpoint or p.y-floor_y<.012:
				p.y=maxf(p.y,floor_y+.006)
				result.append(p)
	return result
