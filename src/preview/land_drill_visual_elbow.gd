extends RefCounted
## Closed-form elbow-circle support planes, not a sampled pose search.
static func guide(s: Vector3,w: Vector3,a: float,b: float,pole: Vector3,normal: Vector3,support: float,planes: Array=[]) -> Dictionary:
	var distance := s.distance_to(w)
	if distance>=a+b or distance<=absf(a-b): return {"valid":false,"reason":"reach"}
	if w.dot(normal)<support: return {"valid":false,"reason":"wrist inside torso support plane"}
	var axis := (w-s)/distance
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var centre := s+axis*along
	var radius := sqrt(maxf(0,a*a-along*along))
	var u := pole-centre
	u=(u-axis*u.dot(axis)).normalized()
	if u.is_zero_approx(): return {"valid":false,"reason":"elbow guide singular"}
	var v := axis.cross(u)
	var rows := [{"a":-radius*u.dot(normal),"b":-radius*v.dot(normal),"bound":centre.dot(normal)-support},{"a":radius*u.y,"b":radius*v.y,"bound":s.y-.085-centre.y}]
	for plane in planes:
		rows.append({"a":radius*u.dot(plane.normal),"b":radius*v.dot(plane.normal),"bound":plane.maximum-centre.dot(plane.normal)})
	var cuts := [0.0,TAU]
	for row in rows:
		var magnitude: float=sqrt(row.a*row.a+row.b*row.b)
		if magnitude<1e-12:
			if row.bound<0: return {"valid":false,"reason":"fixed elbow support"}
			continue
		if row.bound < -magnitude: return {"valid":false,"reason":"elbow support intersection empty"}
		if row.bound>=magnitude: continue
		var middle: float=atan2(row.b,row.a)
		var half: float=acos(row.bound/magnitude)
		cuts.append(fposmod(middle-half,TAU))
		cuts.append(fposmod(middle+half,TAU))
	cuts.sort()
	var selected := INF
	for i in cuts.size()-1:
		var middle: float=(cuts[i]+cuts[i+1])*.5
		var valid := true
		for row in rows:
			if row.a*cos(middle)+row.b*sin(middle)>row.bound: valid=false
		if not valid: continue
		var low: float=cuts[i]
		var high: float=cuts[i+1]
		var padding: float=minf(.00001,(high-low)*.1)
		var angle: float=low+padding if low<TAU-high else high-padding-TAU
		if absf(angle)<absf(selected): selected=angle
	if not is_finite(selected): return {"valid":false,"reason":"elbow support intersection empty"}
	return {"valid":true,"point":centre+radius*(u*cos(selected)+v*sin(selected))}
