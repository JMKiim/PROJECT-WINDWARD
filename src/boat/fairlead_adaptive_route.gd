extends RefCounted
const BASE := preload("res://src/boat/fairlead_cable_route.gd")
const FIELD := BASE.FIELD
const OFFSET := BASE.RADIUS+BASE.GUARD
static func _redistribute(path: PackedVector3Array,spacing: float) -> PackedVector3Array:
	var distance := PackedFloat64Array([0])
	for i in range(1,path.size()-2): distance.append(distance[-1]+path[i].distance_to(path[i+1]))
	var count := mini(1600,maxi(2,ceili(distance[-1]/spacing)))
	var next := PackedVector3Array([path[0]])
	var segment := 0
	for i in count+1:
		var target := distance[-1]*i/count
		while segment<distance.size()-2 and distance[segment+1]<target: segment+=1
		var t := (target-distance[segment])/maxf(distance[segment+1]-distance[segment],1e-12)
		var p := path[segment+1].lerp(path[segment+2],clampf(t,0,1))
		next.append(FIELD.project(p,OFFSET))
	next.append(path[-1])
	return next
static func solve(a: Vector3,b: Vector3,spacing := .0003,limit := 160,cancelled := Callable(),early_stop := true) -> Dictionary:
	var began := Time.get_ticks_usec()
	if not a.is_finite() or not b.is_finite() or not is_finite(spacing) or spacing<.00005 or spacing>.001 or limit<1 or limit>512:
		return {"valid":false,"reason":"invalid adaptive fairlead request"}
	if cancelled.is_valid() and cancelled.call(): return {"valid":false,"reason":"adaptive fairlead cancelled"}
	var seed := BASE.route(Transform3D.IDENTITY,a,b,8,PackedVector3Array(),80)
	if not seed.valid: return seed
	var path: PackedVector3Array=seed.path
	# A safe installed-side initial bend, not a retained waypoint or force.
	# Close forward/above endpoints otherwise cross the crown on their first
	# straight segment before the constrained string has a valid topology.
	if absf(b.x)<.025 and b.y>BASE.FITTING.HEIGHT:
		var bend := Vector3(path[-2].x,BASE.FITTING.HEIGHT+OFFSET+.001,BASE.FITTING.HALF_DEPTH+OFFSET)
		path.insert(path.size()-1,bend)
	path=BASE._refine(path)
	for i in range(1,path.size()-1): path[i]=FIELD.project(path[i],OFFSET)
	path=_redistribute(path,spacing)
	var trace := []
	var previous := PackedVector3Array()
	var stable_epochs := 0
	var iterations := 0
	for iteration in limit:
		if cancelled.is_valid() and cancelled.call(): return {"valid":false,"reason":"adaptive fairlead cancelled"}
		iterations=iteration+1
		var movement := 0.0
		var polished := BASE._newton(path) if iteration>=12 else {"valid":false}
		if polished.valid:
			path=polished.path
			movement=polished.movement
		else:
			for order in 2:
				for j in range(1,path.size()-1):
					var i := j if order==0 else path.size()-1-j
					var left := maxf(path[i].distance_to(path[i-1]),1e-9)
					var right := maxf(path[i].distance_to(path[i+1]),1e-9)
					var target := (path[i-1]/left+path[i+1]/right)/(1/left+1/right)
					var next := FIELD.project(path[i]+(target-path[i]).limit_length(spacing),OFFSET)
					movement=maxf(movement,next.distance_to(path[i]))
					path[i]=next
		if iteration%4==3:
			path=_redistribute(path,spacing)
			var change := INF
			if previous.size()==path.size():
				change=0
				for i in path.size(): change=maxf(change,path[i].distance_to(previous[i]))
			stable_epochs=stable_epochs+1 if change<1e-8 and movement<1e-8 and iteration>=19 else 0
			previous=path.duplicate()
			if early_stop and stable_epochs>=3: break
		if iteration%8==7: trace.append({"iteration":iteration,"residual":BASE._residual(path),"length":BASE._energy(path),"movement":movement})
		if iteration>20 and BASE._residual(path)<1e-5: break
	# Reprojection after subdivision is part of the method, including the
	# final iteration. A small vertex movement is not a force certificate.
	path=_redistribute(path,spacing)
	var gap := INF
	for i in path.size()-1:
		var count := maxi(2,ceili(path[i].distance_to(path[i+1])/.00015))
		for j in count+1:
			var p := path[i].lerp(path[i+1],j/float(count))
			if p.length()<.04: gap=minf(gap,FIELD.query(p).distance-BASE.RADIUS)
	return {"valid":gap>.00025,"stationary":BASE._residual(path)<1e-5,"geometric_settled":stable_epochs>=3,"geometry_certified":false,"minimum_gap":gap,"residual_per_n":BASE._residual(path),"profile":path,"path":path,"length":BASE._energy(path),"trace":trace,"iterations":iterations,"elapsed_ms":(Time.get_ticks_usec()-began)/1000.0}
