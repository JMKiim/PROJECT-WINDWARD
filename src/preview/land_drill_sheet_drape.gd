extends RefCounted
const RADIUS := .004
static func fall(outlet: Vector3,touch: Vector3,caps: Array,hull: MeshInstance3D,away: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for step in 33: points.append(outlet.lerp(touch,step/32.0))
	# Seed the leg approach on the forward side before radial contact.
	# Otherwise a millimetre of outlet motion can select opposite sides of a
	# thigh and move the displayed free strand across it in one sample.
	# This deterministic geometry boundary has no temporal state or hand/trim
	# feedback. Endpoints and the existing contact radii remain unchanged.
	for index in range(1,points.size()-1):
		for cap_index in range(1,caps.size()):
			var cap: Array=caps[cap_index]
			var nearest := Geometry3D.get_closest_point_to_segment(points[index],cap[0],cap[1])
			var radius: float=float(cap[2])+.010
			var influence := 1-smoothstep(radius+.015,radius+.065,points[index].distance_to(nearest))
			var forward_z: float=minf(cap[0].z,cap[1].z)-radius-.006
			points[index].z-=maxf(0,points[index].z-forward_z)*influence
	for iteration in 20:
		for index in range(1,points.size()-1):
			var point := points[index].lerp((points[index-1]+points[index+1])*.5,.35)
			point.y-=.004
			for cap in caps:
				var nearest := Geometry3D.get_closest_point_to_segment(point,cap[0],cap[1])
				var delta := point-nearest
				var radius: float=float(cap[2])+.010
				if delta.length()<radius: point=nearest+(delta.normalized() if delta.length()>.000001 else away)*radius
			point.y=maxf(point.y,hull.cockpit_floor_y_at(point.x,point.z)+RADIUS+.002)
			points[index]=point
		for segment in points.size()-1:
			for cap in caps:
				var pair: PackedVector3Array=Geometry3D.get_closest_points_between_segments(points[segment],points[segment+1],cap[0],cap[1])
				var delta := pair[0]-pair[1]
				var depth: float=float(cap[2])+.008-delta.length()
				if depth<=0: continue
				var shift := (delta.normalized() if delta.length()>.000001 else away)*depth
				if segment>0: points[segment]+=shift
				if segment+1<points.size()-1: points[segment+1]+=shift
	return points
