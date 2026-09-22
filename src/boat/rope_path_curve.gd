extends RefCounted

## Local centreline fillets. Existing finely sampled contact arcs stay intact.
static func round_corners(points: PackedVector3Array,setback: float) -> PackedVector3Array:
	if points.size()<3: return points.duplicate()
	var result := PackedVector3Array([points[0]])
	for index in range(1,points.size()-1):
		var p := points[index]
		var incoming := p-points[index-1]
		var outgoing := points[index+1]-p
		if incoming.length()<.0001 or outgoing.length()<.0001 or incoming.normalized().dot(outgoing.normalized())>cos(deg_to_rad(20)):
			result.append(p)
			continue
		var distance := minf(setback,minf(incoming.length(),outgoing.length())*.25)
		var a := p-incoming.normalized()*distance
		var b := p+outgoing.normalized()*distance
		for step in 7:
			var t := step/6.0
			result.append(a*(1-t)*(1-t)+p*2*t*(1-t)+b*t*t)
	result.append(points[-1])
	return result
