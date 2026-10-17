extends RefCounted
## A free strand begins as a gravity-aligned line. Only actual contact
## adds a detour; there is no always-on elastic relaxation loop.
static func fall(outlet: Vector3,touch: Vector3,caps: Array,hull: MeshInstance3D,away: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var count := clampi(int(ceil(outlet.distance_to(touch)/.025)),16,64)
	for index in count+1:
		var p := outlet.lerp(touch,index/float(count))
		p.y=maxf(p.y,hull.cockpit_floor_y_at(p.x,p.z)+.006)
		points.append(p)
	var bounds := []
	for cap in caps:
		var pad := Vector3.ONE*(float(cap[2])+.02)
		bounds.append([cap[0].min(cap[1])-pad,cap[0].max(cap[1])+pad])
	# The same outboard/front winding throughout the step, not the side
	# selected by a millimetre of penetration into a moving calf.
	for index in range(1,points.size()-1):
		for cap in caps:
			var nearest := Geometry3D.get_closest_point_to_segment(points[index],cap[0],cap[1])
			var radius: float=float(cap[2])+.010
			var influence: float=1-smoothstep(radius+.015,radius+.065,points[index].distance_to(nearest))
			var support: float=maxf(cap[0].dot(away),cap[1].dot(away))+radius+.006
			points[index]+=away*maxf(0,support-points[index].dot(away))*influence
	for iteration in 16:
		var changed := false
		for segment in points.size()-1:
			var low := points[segment].min(points[segment+1])
			var high := points[segment].max(points[segment+1])
			for index in caps.size():
				var cap_low: Vector3=bounds[index][0]
				var cap_high: Vector3=bounds[index][1]
				if low.x>cap_high.x or high.x<cap_low.x or low.y>cap_high.y or high.y<cap_low.y or low.z>cap_high.z or high.z<cap_low.z: continue
				var cap: Array=caps[index]
				var pair := Geometry3D.get_closest_points_between_segments(points[segment],points[segment+1],cap[0],cap[1])
				var delta := pair[0]-pair[1]
				var depth: float=float(cap[2])+.008-delta.length()
				if depth<=.00001: continue
				var edge := points[segment+1]-points[segment]
				var fraction: float=clampf((pair[0]-points[segment]).dot(edge)/maxf(.0000000001,edge.length_squared()),0,1)
				var a: float=1-fraction if segment>0 else 0
				var b: float=fraction if segment+1<points.size()-1 else 0
				var denominator: float=a*a+b*b
				if denominator<.0000001: continue
				var shift: Vector3=(delta.normalized() if delta.length()>.000001 else away)*minf(.04,depth/denominator)
				points[segment]+=shift*a
				points[segment+1]+=shift*b
				low=points[segment].min(points[segment+1])
				high=points[segment].max(points[segment+1])
				changed=true
		for index in range(1,points.size()-1):
			var floor_y: float=hull.cockpit_floor_y_at(points[index].x,points[index].z)+.006
			if points[index].y<floor_y: points[index].y=floor_y; changed=true
		if not changed: break
	return points
