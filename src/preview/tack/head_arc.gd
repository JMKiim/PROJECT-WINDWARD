extends RefCounted
## Fixed spherical detour, evaluated by arc length. The obstacle and the
## endpoints are captured at the start of the gesture, not re-projected
## from a moving instantaneous pose.
static func sample(start: Vector3,finish: Vector3,centre: Vector3,radius: float,t: float) -> Vector3:
	var n := centre.normalized()
	var half := asin(clampf(radius/centre.length(),0,.95))
	var cosine := cos(half)
	var sine := sin(half)
	var a_dot := start.dot(n)
	var b_dot := finish.dot(n)
	if a_dot>=cosine or b_dot>=cosine: return start.slerp(finish,t)
	var plane := start.cross(finish).normalized()
	var projected := (n-plane*n.dot(plane)).normalized()
	var between := start.angle_to(projected)+projected.angle_to(finish)<=start.angle_to(finish)+.00001
	if not between or projected.dot(n)<=cosine: return start.slerp(finish,t)
	var best := INF
	var selected := {}
	var up := (Vector3.UP-n*n.y).normalized()
	for a: Vector3 in tangents(start,n,half):
		for b: Vector3 in tangents(finish,n,half):
			var ra := (a-n*cosine)/sine
			var rb := (b-n*cosine)/sine
			var angle := ra.signed_angle_to(rb,n)
			for delta: float in [angle,angle-TAU if angle>=0 else angle+TAU]:
				var sign_value := signf(delta)
				var incoming := (a*a.dot(start)-start).normalized()
				var outgoing := (finish-b*b.dot(finish)).normalized()
				if incoming.dot(n.cross(a).normalized()*sign_value)<.99 or outgoing.dot(n.cross(b).normalized()*sign_value)<.99: continue
				var first := start.angle_to(a)
				var middle := absf(delta)*sine
				var last := b.angle_to(finish)
				var radial_middle := Basis(n,delta*.5)*ra
				var score := first+middle+last+4*(1-radial_middle.dot(up))
				if score<best:
					best=score
					selected={"a":a,"b":b,"radial":ra,"delta":delta,"first":first,"middle":middle,"last":last}
	if selected.is_empty(): return start.slerp(finish,t)
	var distance: float=t*(selected.first+selected.middle+selected.last)
	if distance<selected.first: return start.slerp(selected.a,distance/selected.first)
	distance-=selected.first
	if distance<selected.middle: return n*cosine+(Basis(n,selected.delta*distance/selected.middle)*selected.radial)*sine
	return (selected.b as Vector3).slerp(finish,(distance-selected.middle)/selected.last)
static func tangents(point: Vector3,n: Vector3,half: float) -> Array[Vector3]:
	var dot := point.dot(n)
	var radial := (point-n*dot).normalized()
	var cosine := clampf(dot*tan(half)/sqrt(maxf(1e-12,1-dot*dot)),-1,1)
	var sine := sqrt(maxf(0,1-cosine*cosine))
	var other := n.cross(radial)
	return [n*cos(half)+(radial*cosine+other*sine)*sin(half),n*cos(half)+(radial*cosine-other*sine)*sin(half)]
