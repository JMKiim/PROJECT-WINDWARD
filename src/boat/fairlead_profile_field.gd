extends RefCounted

## Analytic extrusion of the fitting's central profile. The screw seats and
## rounded footprint ends remove material outside this routing envelope;
## full rendered mesh clearance remains an independent obligation.
const FITTING := preload("res://src/boat/traveller_fairlead.gd")

static func _segment(p: Vector2,a: Vector2,b: Vector2) -> Vector2:
	var d := b-a
	return a+d*clampf((p-a).dot(d)/d.length_squared(),0,1)

static func _roof_edge(angle: float) -> Vector3:
	var x := FITTING.END_CENTRE+FITTING.HALF_DEPTH*cos(angle)
	return Vector3(x,FITTING.roof(x),FITTING.HALF_DEPTH*sin(angle))

static func _edge_nearest(p: Vector3) -> Vector3:
	# The rounded plan end intersects a planar sloping shoulder. The nearest
	# point on this smooth roof edge is a bounded one-dimensional minimum.
	var angle := clampf(atan2(p.z,p.x-FITTING.END_CENTRE),0,PI*.5)
	var radius := FITTING.HALF_DEPTH
	for iteration in 12:
		var q := _roof_edge(angle)
		var first := Vector3(-radius*sin(angle),.75*radius*sin(angle),radius*cos(angle))
		var second := Vector3(-radius*cos(angle),.75*radius*cos(angle),-radius*sin(angle))
		var gradient := (q-p).dot(first)
		var hessian := first.length_squared()+(q-p).dot(second)
		if hessian<=1e-12: break
		var next := clampf(angle-gradient/hessian,0,PI*.5)
		if absf(next-angle)<1e-10: break
		angle=next
	var best := _roof_edge(angle)
	for end in [0.0,PI*.5]:
		var q := _roof_edge(end)
		if q.distance_squared_to(p)<best.distance_squared_to(p): best=q
	return best

static func query(point: Vector3) -> Dictionary:
	var x := absf(point.x)
	var p := Vector2(x,point.y)
	var half := FITTING.LENGTH*.5
	var h := FITTING.roof(half)
	var candidates := PackedVector2Array()
	for edge in [[Vector2(.005,0),Vector2(half,0)],[Vector2(half,0),Vector2(half,h)],[Vector2(half,h),Vector2(.006,.016)],[Vector2(.005,0),Vector2(.005,.008)]]:
		candidates.append(_segment(p,edge[0],edge[1]))
	var angle := clampf(atan2(p.y-.008,p.x),0,PI*.5)
	candidates.append(Vector2(cos(angle)*.005,.008+sin(angle)*.005))
	angle=clampf(atan2(p.y-.008,p.x),acos(.6),PI*.5)
	candidates.append(Vector2(cos(angle)*.01,.008+sin(angle)*.01))
	var folded := Vector3(x,point.y,absf(point.z))
	var surfaces := PackedVector3Array()
	for q in candidates:
		var depth := FITTING.HALF_DEPTH if q.x<=FITTING.END_CENTRE else sqrt(maxf(0,pow(FITTING.HALF_DEPTH,2)-pow(q.x-FITTING.END_CENTRE,2)))
		surfaces.append(Vector3(q.x,q.y,minf(folded.z,depth)))
	# The rear/front flat face ends at the capsule's tangent line.
	var cap_x := minf(x,FITTING.END_CENTRE)
	var lower := .008+sqrt(maxf(0,.000025-cap_x*cap_x)) if cap_x<.005 else 0.0
	surfaces.append(Vector3(cap_x,clampf(point.y,lower,FITTING.roof(cap_x)),FITTING.HALF_DEPTH))
	if folded.x>=.010:
		var wall_angle := clampf(atan2(folded.z,folded.x-FITTING.END_CENTRE),0,PI*.5)
		var wall := _roof_edge(wall_angle)
		wall.y=clampf(folded.y,0,wall.y)
		surfaces.append(wall)
		surfaces.append(_edge_nearest(folded))
	var nearest := Vector3.ZERO
	var distance := INF
	for q in surfaces:
		var d := folded.distance_to(q)
		if d<distance:
			distance=d
			nearest=q
	var inside := p.y>=0 and x<=half and p.y<=FITTING.roof(x)
	if x<.005 and p.y<.008+sqrt(maxf(0,.000025-x*x)): inside=false
	var cap_depth := FITTING.HALF_DEPTH if x<=FITTING.END_CENTRE else sqrt(maxf(0,pow(FITTING.HALF_DEPTH,2)-pow(x-FITTING.END_CENTRE,2)))
	inside=inside and absf(point.z)<=cap_depth
	var sign_x := -1.0 if point.x<0 else 1.0
	var side := Vector3(nearest.x*sign_x,nearest.y,nearest.z*(-1.0 if point.z<0 else 1.0))
	return {"distance":-distance if inside else distance,"point":side,"normal":(point-side).normalized()*(-1.0 if inside else 1.0)}

static func project(point: Vector3,radius: float) -> Vector3:
	for iteration in 6:
		var contact := query(point)
		if contact.distance>=radius-1e-9: return point
		point=contact.point+contact.normal*radius
	return point
