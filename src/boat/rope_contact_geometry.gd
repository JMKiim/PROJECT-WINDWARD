extends RefCounted

## The engine's segment solver compares a fourth-power determinant with an
## absolute tolerance. Millimetre-scale rope links must be conditioned before
## that query or nonparallel chords can be treated as parallel. Translate to
## a local origin first so the scale change does not magnify world offsets.
static func closest_segments(a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> PackedVector3Array:
	var pair := Geometry3D.get_closest_points_between_segments(Vector3.ZERO,(b-a)*1000.0,(c-a)*1000.0,(d-a)*1000.0)
	pair[0] = a+pair[0]*.001
	pair[1] = a+pair[1]*.001
	return pair
