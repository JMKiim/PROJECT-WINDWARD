extends RefCounted

## Open four-crossing stopper centerline. Both tails are part of the same
## material path; no closed decorative loop is counted as a rope end.
const RADIUS := .004
const SCALE := .0082
const CUT := .50
const SAMPLES := 192

static func points(tail_length: float = .060,standing_length: float = .035) -> PackedVector3Array:
	var core := PackedVector3Array()
	for index in SAMPLES+1:
		var t := lerpf(CUT,TAU-CUT,float(index)/SAMPLES)
		core.append(Vector3((2+cos(2*t))*cos(3*t),(2+cos(2*t))*sin(3*t),sin(4*t))*SCALE)
	var direction := (core[1]-core[0]).normalized()
	var first := core[0]-direction*standing_length
	var result := PackedVector3Array([first])
	result.append_array(core)
	result.append(core[-1]+(core[-1]-core[-2]).normalized()*tail_length)
	# Standing-leg origin and axis make orientation/attachment independent of
	# the knot's decorative bounding box.
	var frame := Basis(Quaternion(direction,Vector3.FORWARD))
	for index in result.size(): result[index] = frame*(result[index]-first)
	return result

static func length_of(path: PackedVector3Array) -> float:
	var result := 0.0
	for index in path.size()-1: result += path[index].distance_to(path[index+1])
	return result

static func grounded_points(standing_length: float = .065,tail_length: float = .060) -> PackedVector3Array:
	# The same open knot laid on its side. Its standing end is on the floor,
	# and the crossings retain the rope's thickness rather than flattening.
	var core := PackedVector3Array()
	for index in SAMPLES+1:
		var t := lerpf(CUT,TAU-CUT,float(index)/SAMPLES)
		core.append(Vector3((2+cos(2*t))*cos(3*t),sin(4*t),(2+cos(2*t))*sin(3*t))*SCALE)
	var entry := (core[1]-core[0]).normalized()
	var exit_direction := (core[-1]-core[-2]).normalized()
	var result := PackedVector3Array()
	# Preserve the clear tangent tails in plan view. A straight inlet through
	# the centre would intersect the knot even though its core is valid.
	for index in 13:
		var fraction := float(index)/12
		var point := core[0]-entry*standing_length*(1-fraction)
		point.y = (point.y+SCALE)*smoothstep(0,1,fraction)
		result.append(point)
	for point in core.slice(1): result.append(point+Vector3.UP*SCALE)
	for index in range(1,21):
		var fraction := float(index)/20
		var point := core[-1]+exit_direction*tail_length*fraction
		point.y = (core[-1].y+SCALE)*pow(1-fraction,2)
		result.append(point)
	var first := result[0]
	for index in result.size(): result[index] -= first
	return result

static func placed(path: PackedVector3Array, origin: Vector3, direction: Vector3, roll: float = 0.0) -> PackedVector3Array:
	var basis := Basis(Quaternion(Vector3.FORWARD,direction.normalized()))*Basis(Vector3.FORWARD,roll)
	var result := PackedVector3Array()
	for point in path: result.append(origin+basis*point)
	return result
