extends RefCounted
## Closest unit direction in linear spherical caps. Finite analytic plane
## events,not angular pose sampling or an iterative body search.
static func closest(desired: Vector3,constraints: Array) -> Dictionary:
	var planes := []
	var candidates := [desired.normalized()]
	for constraint: Dictionary in constraints:
		var n: Vector3=constraint.n.normalized()
		var k: float=constraint.k
		if k>1: return {"valid":false,"reason":"unit cap empty","constraint":constraint}
		if k<=-1: continue
		planes.append({"n":n,"k":k})
		var tangent: Vector3=desired-n*desired.dot(n)
		if tangent.length()<.000001: tangent=n.cross(Vector3.FORWARD)
		if tangent.length()<.000001: tangent=n.cross(Vector3.RIGHT)
		for inset: float in [0,.000002]:
			var event_k: float=minf(1,k+inset)
			candidates.append(n*event_k+tangent.normalized()*sqrt(maxf(0,1-event_k*event_k)))
	for i in planes.size():
		for j in range(i+1,planes.size()):
			var a: Dictionary=planes[i]
			var b: Dictionary=planes[j]
			var dot: float=a.n.dot(b.n)
			var denominator: float=1-dot*dot
			if denominator<.00000001: continue
			# A rounded boundary must not discard the whole nearest branch.
			# Also construct a tiny INSIDE event;validate against the original
			# planes below. No clearance/physical acceptance is reduced.
			for inset: float in [0,.000002]:
				var ak: float=minf(1,a.k+inset)
				var bk: float=minf(1,b.k+inset)
				var centre: Vector3=a.n*((ak-dot*bk)/denominator)+b.n*((bk-dot*ak)/denominator)
				var radius_squared: float=1-centre.length_squared()
				if radius_squared<0: continue
				var radial: Vector3=(a.n as Vector3).cross(b.n).normalized()*sqrt(radius_squared)
				candidates.append_array([centre+radial,centre-radial])
	var best := INF
	var selected := Vector3.ZERO
	for d: Vector3 in candidates:
		var valid := true
		for plane: Dictionary in planes:
			if d.dot(plane.n)<plane.k-.0000001: valid=false; break
		if not valid: continue
		var score: float=d.distance_squared_to(desired)
		if score<best: best=score; selected=d
	return {"valid":is_finite(best),"point":selected,"reason":"unit cap intersection"}
