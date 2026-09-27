extends RefCounted
const HANGING := preload("res://src/boat/rig_hanging_sheet.gd")
const SUPPORTED_OBSTACLE := preload("res://src/boat/supported_rope_obstacle.gd")

## Finite guide contact geometry, not a cable/body force equilibrium.
static func build(source: PackedVector3Array,wraps: Dictionary,target: float,gravity: Vector3,support: RefCounted,obstacle: RefCounted,exit_turn := NAN,cancelled := Callable()) -> Dictionary:
	if support==null or not support.valid or obstacle==null or not obstacle.valid:
		return {"valid":false,"reason":"invalid finite guide contact surface"}
	if not wraps.has_all(["becket","traveller"]) or not wraps.becket.has("end") or not wraps.traveller.has("end"):
		return {"valid":false,"reason":"missing finite guide boundary"}
	var free_target := target
	var history := []
	var warm := {}
	var supported := SUPPORTED_OBSTACLE.new()
	supported.setup(obstacle,support)
	for iteration in 5:
		if cancelled.is_valid() and cancelled.call(): return {"valid":false,"cancelled":true,"reason":"contact work cancelled"}
		var span_started := Time.get_ticks_usec()
		var cable := HANGING.build(source,wraps,free_target,gravity,support,[int(wraps.becket.end),int(wraps.traveller.end)],exit_turn)
		if not cable.valid: return cable
		var span_ms := (Time.get_ticks_usec()-span_started)/1000.0
		# Keep the accepted local guide geometry fixed during the outer material
		# root solve. Only its distant join follows the new free span, with a
		# sub-millimetre bounded deformation and a fresh full clearance check.
		# Continuing relaxation here would introduce a drifting length target.
		var contact := settle(cable.path,cable.get("free_ranges",{}),supported,warm,cancelled)
		if contact.get("cancelled",false): return contact
		warm=contact.patch_cache
		var error := HANGING.length_of(contact.path)-target
		history.append({"iteration":iteration,"error_metres":error,"patches":contact.patches,"span_ms":span_ms})
		if absf(error)<HANGING.LENGTH_EPS:
			var gap: float=support.clearance(contact.path)
			contact["valid"]=contact.valid and gap>=-.0001
			contact["hull_supported"]=true
			contact["minimum_hull_gap_metres"]=gap
			contact["slack_metres"]=target-HANGING.length_of(source)
			contact["curvature"]=cable.get("curvature",0.0)
			contact["finite_guide_contact"]=true
			contact["force_equilibrium"]=false
			contact.erase("patch_cache")
			contact["error_metres"]=error
			contact["history"]=history
			return contact
		free_target-=error
	return {"valid":false,"reason":"contact material did not converge","history":history}

static func settle(path: PackedVector3Array,ranges: Dictionary,obstacle: RefCounted,warm: Dictionary={},cancelled := Callable()) -> Dictionary:
	var patches := {}
	var patch_cache := {}
	var rows := []
	var valid := true
	for begin: int in ranges:
		var range: Vector2i=ranges[begin]
		var source := path.slice(range.x,range.y+1)
		var span_length := HANGING.length_of(source)
		if span_length<.03: continue
		for end in 2:
			var points := source.duplicate()
			if end==1: points.reverse()
			var stop := 1
			var distance := 0.0
			while stop<points.size()-1 and distance<minf(.12,span_length*.45):
				distance+=points[stop].distance_to(points[stop-1])
				stop+=1
			var patch := points.slice(0,stop+1)
			var penetration := false
			for point in patch:
				if obstacle.query(point,.004,.00005).gap<0: penetration=true
			if not penetration: continue
			var key := Vector2i(begin,end)
			var result := _relax(patch,obstacle,warm.get(key,PackedVector3Array()),cancelled)
			if result.get("cancelled",false): return result
			patch_cache[key]=result.path.duplicate()
			valid=valid and result.valid
			rows.append({"span":begin,"end":end,"valid":result.valid,"iterations":result.iterations,"moved_metres":result.moved,"minimum_gap":result.minimum_gap,"points":result.path.size(),"added_metres":HANGING.length_of(result.path)-HANGING.length_of(patch),"work_ms":result.work_ms,"retained_geometry":result.get("retained_geometry",false)})
			if end==1: result.path.reverse()
			var first: int=range.y-stop if end==1 else range.x
			patches[first]={"last":range.y if end==1 else range.x+stop,"path":result.path}
	var result := PackedVector3Array()
	var index := 0
	while index<path.size():
		if patches.has(index):
			result.append_array(patches[index].path)
			index=patches[index].last+1
		else:
			result.append(path[index])
			index+=1
	return {"valid":valid,"path":result,"patches":rows,"patch_cache":patch_cache,"added_metres":HANGING.length_of(result)-HANGING.length_of(path)}

static func _relax(source: PackedVector3Array,obstacle: RefCounted,warm: PackedVector3Array=PackedVector3Array(),cancelled := Callable()) -> Dictionary:
	var started := Time.get_ticks_usec()
	var region := AABB(source[0],Vector3.ZERO)
	for point in source: region=region.expand(point)
	region=region.grow(.030)
	var bounded: RefCounted=obstacle.restricted(region.grow(.0041))
	var path := _resample(source,.006)
	var reused := warm.size()>2 and warm[0].distance_to(source[0])<.000001 and warm[-1].distance_to(source[-1])<.001
	if reused:
		path=warm.duplicate()
		var delta := source[-1]-path[-1]
		# Preserve the fitting-side third exactly; deformation belongs only
		# to the outer join, never the existing fixed wrap or contact turn.
		for index in path.size(): path[index]+=delta*smoothstep(.35,1,index/float(path.size()-1))
		path[0]=source[0]
		path[-1]=source[-1]
		var gap := _minimum_gap(path,obstacle)
		if gap>=-.00005:
			return {"valid":true,"path":path,"iterations":0,"moved":delta.length(),"minimum_gap":gap,"work_ms":(Time.get_ticks_usec()-started)/1000.0,"retained_geometry":true}
		# A changed support boundary is not repaired with a looser guard.
		# Fall back to the full local projection using the new free span.
		path=_resample(source,.006)
		reused=false
	var iterations := 0
	var moved := INF
	var all_projected := true
	for iteration in (40 if reused else 160):
		if cancelled.is_valid() and cancelled.call(): return {"valid":false,"cancelled":true,"reason":"contact patch cancelled"}
		iterations=iteration+1
		moved=0.0
		all_projected=true
		if not reused and iteration==60: path=_resample(path,.003)
		if not reused and iteration==100: path=_resample(path,.001)
		if (reused or iteration>=100) and iteration%8==0: path=_refine(path)
		for index in range(1,path.size()-1):
			var first := path[index-1]
			var last := path[index+1]
			var a := maxf(.00001,first.distance_to(path[index]))
			var b := maxf(.00001,last.distance_to(path[index]))
			var target := (first/a+last/b)/(1/a+1/b)
			var proposed := path[index].lerp(target,.55)
			var projected: Dictionary=bounded.project(proposed,.004) if region.has_point(proposed) else obstacle.project(proposed,.004)
			if not region.has_point(projected.point): projected=obstacle.project(projected.point,.004)
			all_projected=all_projected and projected.valid
			moved=maxf(moved,path[index].distance_to(projected.point))
			path[index]=projected.point
		if moved<.000002 and (reused or iteration>110): break
	var minimum := _minimum_gap(path,obstacle)
	return {"valid":all_projected and minimum>=-.00005,"path":path,"iterations":iterations,"moved":moved,"minimum_gap":minimum,"work_ms":(Time.get_ticks_usec()-started)/1000.0}

static func _minimum_gap(path: PackedVector3Array,obstacle: RefCounted) -> float:
	var minimum := INF
	for index in path.size()-1:
		for fraction in [0.0,.25,.5,.75,1.0]: minimum=minf(minimum,obstacle.query(path[index].lerp(path[index+1],fraction),.004,.0001).gap)
	return minimum

static func _refine(source: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array([source[0]])
	for index in source.size()-1:
		var count := maxi(1,ceili(source[index].distance_to(source[index+1])/.0015))
		for sample in range(1,count+1): result.append(source[index].lerp(source[index+1],sample/float(count)))
	return result

static func _resample(source: PackedVector3Array,spacing: float) -> PackedVector3Array:
	var cumulative := PackedFloat64Array([0.0])
	for index in source.size()-1: cumulative.append(cumulative[-1]+source[index].distance_to(source[index+1]))
	var count := maxi(2,ceili(cumulative[-1]/spacing))
	var result := PackedVector3Array([source[0]])
	var edge := 0
	for index in range(1,count):
		var distance: float=cumulative[-1]*index/count
		while edge<cumulative.size()-2 and cumulative[edge+1]<distance: edge+=1
		var t: float=(distance-cumulative[edge])/maxf(.0000001,cumulative[edge+1]-cumulative[edge])
		result.append(source[edge].lerp(source[edge+1],t))
	result.append(source[-1])
	return result
