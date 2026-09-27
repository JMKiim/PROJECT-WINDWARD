extends RefCounted

## Gravity-shaped free spans between finite, already fitted rope guides.
## Guide contact arcs and the hand lead are retained. Departure turns begin
## immediately; this is not a friction or rope-weight load solver.
const SAMPLES := 48
const LENGTH_EPS := .000015
const SUPPORTED := preload("res://src/boat/supported_catenary.gd")
static var exit_turn_metres := .060

static func length_of(path: PackedVector3Array) -> float:
	var result := 0.0
	for index in path.size()-1: result+=path[index].distance_to(path[index+1])
	return result

static func build(path: PackedVector3Array,wraps: Dictionary,target: float,gravity: Vector3,support: RefCounted=null,relaxed_spans: Array=[],exit_turn_override := NAN) -> Dictionary:
	var exit_turn: float=exit_turn_metres if is_nan(exit_turn_override) else exit_turn_override
	if not is_finite(exit_turn) or exit_turn<0: return {"valid":false,"reason":"invalid guide departure boundary"}
	if path.size()<6: return {"valid":false,"reason":"incomplete hanging route"}
	for point in path:
		if not point.is_finite(): return {"valid":false,"reason":"nonfinite hanging route"}
	for name in ["becket","traveller","aft","forward","deck"]:
		if not wraps.has(name) or not wraps[name].has_all(["begin","end"]):
			return {"valid":false,"reason":"missing hanging guide"}
	var direct := length_of(path)
	if not is_finite(target) or not gravity.is_finite() or target<direct-.00005:
		return {"valid":false,"reason":"hanging path cannot shorten its supports"}
	if target<=direct+LENGTH_EPS:
		return {"valid":true,"path":path.duplicate(),"slack_metres":0.0,"error_metres":direct-target,"curvature":0.0}
	if gravity.length()<.0001: return {"valid":false,"reason":"no effective gravity for hanging path"}
	var spans := {}
	for pair in [["becket","traveller"],["traveller","aft"],["aft","guide"],["guide","forward"],["forward","deck"]]:
		var begin: int=wraps.aft.end+1 if pair[0]=="guide" else wraps[pair[0]].end
		var end: int=wraps.aft.end+1 if pair[1]=="guide" else wraps[pair[1]].begin
		if end!=begin+1 or begin<0 or end>=path.size(): return {"valid":false,"reason":"unexpected free span topology"}
		spans[begin]=end
	var up := -gravity.normalized()
	var profiles := {}
	if support!=null:
		if not support.valid: return {"valid":false,"reason":"invalid hull contact surface"}
		for begin: int in spans:
			var first := path[begin]
			var last := path[spans[begin]]
			var flat := last-first-up*(last-first).dot(up)
			var samples := maxi(SAMPLES,ceili(flat.length()/.0015))
			var heights := PackedFloat64Array()
			var parameters := PackedFloat64Array()
			for sample in samples+1:
				var point := first.lerp(last,sample/float(samples))
				var height: float=support.height_at(point)
				if sample in [0,samples] and point.dot(up)<height-.000001:
					return {"valid":false,"reason":"fixed rope guide requires hull contact relocation"}
				heights.append(height)
				parameters.append(sample/float(samples))
			profiles[begin]={"heights":heights,"parameters":parameters}
	var candidate := PackedVector3Array()
	var curve := 0.0
	var refinements := 0
	for refinement in 16:
		var low := 0.0
		var high := .5
		candidate=_path(path,spans,up,high,profiles,relaxed_spans,exit_turn)
		for bracket in 12:
			if length_of(candidate)>=target: break
			high*=2
			candidate=_path(path,spans,up,high,profiles,relaxed_spans,exit_turn)
		if length_of(candidate)<target: return {"valid":false,"reason":"supported material requires folds or guide relocation" if support!=null else "hanging span allocation out of range"}
		curve=high
		for iteration in 28:
			curve=(low+high)*.5
			candidate=_path(path,spans,up,curve,profiles,relaxed_spans,exit_turn)
			var measured := length_of(candidate)
			if absf(measured-target)<LENGTH_EPS*.5: break
			if measured<target: low=curve
			else: high=curve
		if support==null or not _refine_profiles(path,spans,profiles,candidate,up,support): break
		refinements+=1
	var error := length_of(candidate)-target
	var result := {"valid":absf(error)<=LENGTH_EPS,"path":candidate,"slack_metres":target-direct,"error_metres":error,"curvature":curve}
	var ranges := {}
	var offset := 0
	for index in path.size()-1:
		if not spans.has(index):
			offset+=1
			continue
		var turn := minf(.3,exit_turn/maxf(path[index+1].distance_to(path[index]),.001))
		var count: int=profiles[index].parameters.size()-1 if profiles.has(index) else _free_parameters(turn).size()-1
		ranges[index]=Vector2i(offset,offset+count)
		offset+=count
	result["free_ranges"]=ranges
	if support!=null:
		result["hull_supported"]=true
		result["contact_refinements"]=refinements
		result["minimum_hull_gap_metres"]=support.clearance(candidate)
		if result.minimum_hull_gap_metres<-.0001:
			return {"valid":false,"reason":"supported rope leaves resolved hull contact domain","minimum_hull_gap_metres":result.minimum_hull_gap_metres,"contact_failure":support.last_clearance}
	return result

static func _path(path: PackedVector3Array,spans: Dictionary,up: Vector3,curve: float,profiles: Dictionary={},relaxed_spans: Array=[],exit_turn_override := NAN) -> PackedVector3Array:
	var exit_turn: float=exit_turn_metres if is_nan(exit_turn_override) else exit_turn_override
	var result := PackedVector3Array([path[0]])
	for index in path.size()-1:
		if not spans.has(index):
			result.append(path[index+1])
			continue
		var first := path[index]
		var last := path[index+1]
		var delta := last-first
		var rise := delta.dot(up)
		var flat := delta-up*rise
		var width := flat.length()
		var turn := minf(.3,exit_turn/maxf(delta.length(),.001))
		var departure_turn := 0.0 if index in relaxed_spans else turn
		var profile: Dictionary=profiles.get(index,{})
		var heights: PackedFloat64Array=profile.get("heights",PackedFloat64Array())
		var parameters: PackedFloat64Array=profile.get("parameters",PackedFloat64Array())
		if parameters.is_empty(): parameters=_free_parameters(turn)
		var samples := parameters.size()-1
		var span_heights := PackedFloat64Array([first.dot(up)])
		for sample in range(1,samples+1):
			var t: float=parameters[sample]
			var drop := 0.0
			if width>.0001 and curve>0:
				var k := minf(curve,16.0/width)
				if k*width<.005:
					drop=k*width*width*t*(1-t)*.5*sqrt(1+rise*rise/(width*width))
				else:
					var a := 1.0/k
					var ratio := rise/(2*a*sinh(width/(2*a)))
					var offset := width*.5-a*log(ratio+sqrt(ratio*ratio+1))
					var y := a*(cosh((width*t-offset)/a)-cosh(offset/a))
					drop=maxf(0,rise*t-y)
				# No rigid straight mouth: departure starts at the guide. A short
				# tangent transition retains finite sheave clearance, not stiffness.
				if departure_turn>0: drop*=smoothstep(0,departure_turn,t)*smoothstep(0,departure_turn,1-t)
			span_heights.append(first.dot(up)+rise*t-drop)
		if not heights.is_empty() and width>.0001:
			var obstacles := heights.duplicate()
			for sample in samples+1:
				var t: float=parameters[sample]
				# Keep the established finite-guide departure boundary. Its
				# contact-angle/force coupling is a separate unresolved freedom.
				if t<departure_turn or 1-t<departure_turn: obstacles[sample]=maxf(obstacles[sample],span_heights[sample])
			var supported := SUPPORTED.solve(parameters,obstacles,width,span_heights[0],span_heights[-1],minf(curve,16.0/width))
			if supported.valid: span_heights=supported.heights
		for sample in range(1,samples+1):
			var t: float=parameters[sample]
			var point := first.lerp(last,t)
			point+=up*(span_heights[sample]-point.dot(up))
			result.append(point)
	return result

static func _free_parameters(turn: float) -> PackedFloat64Array:
	# Long free spans still need short chords at a finite sheave. Uniform
	# whole-span sampling can cut through it despite a clear smooth tangent.
	var values := PackedFloat64Array()
	for sample in SAMPLES+1: values.append(sample/float(SAMPLES))
	for sample in range(1,13):
		values.append(turn*sample/12.0)
		values.append(1.0-turn*sample/12.0)
	values.sort()
	var result := PackedFloat64Array()
	for value in values:
		if result.is_empty() or value-result[-1]>1e-8: result.append(value)
	return result

static func _refine_profiles(path: PackedVector3Array,spans: Dictionary,profiles: Dictionary,candidate: PackedVector3Array,up: Vector3,support: RefCounted) -> bool:
	# Resolve convex edges and support/no-support boundaries in the actual
	# polyline, then solve its entire material length again with the new nodes.
	var changed := false
	var offset := 0
	for index in path.size()-1:
		if not spans.has(index):
			offset+=1
			continue
		var old: Dictionary=profiles[index]
		var parameters := PackedFloat64Array()
		var heights := PackedFloat64Array()
		for sample in old.parameters.size()-1:
			parameters.append(old.parameters[sample])
			heights.append(old.heights[sample])
			var a := candidate[offset+sample]
			var b := candidate[offset+sample+1]
			for fraction in [.25,.5,.75]:
				var point := a.lerp(b,fraction)
				var floor: float=support.height_at(point)
				if point.dot(up)>=floor-.000025: continue
				var t: float=lerpf(old.parameters[sample],old.parameters[sample+1],fraction)
				parameters.append(t)
				heights.append(support.height_at(path[index].lerp(path[index+1],t)))
				changed=true
		parameters.append(old.parameters[-1])
		heights.append(old.heights[-1])
		offset+=old.parameters.size()-1
		profiles[index]={"parameters":parameters,"heights":heights}
	return changed
