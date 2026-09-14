extends RefCounted

## Split at a fixed sphere outside the fitting. The remote authored lead is
## retained; the purchase owns the complete swivel wrap before this point.
const DISTANCE := .10

static func remote(path: PackedVector3Array,center: Vector3) -> PackedVector3Array:
	for index in range(1,path.size()):
		if path[index].distance_to(center)<DISTANCE: continue
		var start := path[index-1]
		var direction := (path[index]-start).normalized()
		var relative := start-center
		var projected := relative.dot(direction)
		var distance := -projected+sqrt(maxf(0,projected*projected-relative.length_squared()+DISTANCE*DISTANCE))
		var point := start+direction*clampf(distance,0,start.distance_to(path[index]))
		var result := PackedVector3Array([point])
		if point.distance_squared_to(path[index])>.000000000001: result.append(path[index])
		result.append_array(path.slice(index+1))
		return result
	return PackedVector3Array()
