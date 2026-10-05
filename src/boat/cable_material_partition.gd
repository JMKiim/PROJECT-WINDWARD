extends RefCounted

## Freely sliding, homogeneous cable split by fixed guide arcs. Each span
## has a gravity-normal flat support; folds, friction and moving guides are
## deliberately not inferred. The common variable is T - w*y, not H.
const SPAN := preload("res://src/boat/supported_cable_span.gd")
const LENGTH_TOLERANCE := .000015
const FORCE_TOLERANCE := .00002

static func solve(spans: Array,total_free_metres: float,gravity: Vector3,radius: float,kg_per_metre: float,sample_path := true) -> Dictionary:
	if spans.is_empty() or not gravity.is_finite() or gravity.length()<.0001 or not is_finite(total_free_metres) or not is_finite(radius) or radius<0 or not is_finite(kg_per_metre) or kg_per_metre<=0:
		return {"valid":false,"reason":"invalid sliding cable boundary"}
	var up := -gravity.normalized()
	var weight := gravity.length()*kg_per_metre
	var descriptions := []
	var minimum := 0.0
	var maximum := 0.0
	var floor_height := NAN
	for span in spans:
		if not span is Dictionary or not span.has_all(["first","last","floor"]) or not span.first is Vector3 or not span.last is Vector3 or not span.floor is Vector3 or not span.first.is_finite() or not span.last.is_finite() or not span.floor.is_finite():
			return {"valid":false,"reason":"invalid sliding span"}
		var h0: float=(span.first-span.floor).dot(up)-radius
		var h1: float=(span.last-span.floor).dot(up)-radius
		var delta: Vector3=span.last-span.first
		var width: float=(delta-up*delta.dot(up)).length()
		if minf(h0,h1)<-.000001 or width<.0001: return {"valid":false,"reason":"unsupported sliding span topology"}
		var direct: float=delta.length()
		var capacity: float=width+maxf(0,h0)+maxf(0,h1)
		var height: float=span.floor.dot(up)+radius
		if is_nan(floor_height): floor_height=height
		elif absf(height-floor_height)>.000001: return {"valid":false,"reason":"unequal support levels require supported folds and transfer topology"}
		var fixed := capacity-direct<.000002
		var lower: float=direct if fixed else direct+.0000011
		minimum+=lower
		maximum+=capacity
		descriptions.append({"first":span.first,"last":span.last,"floor":span.floor,"floor_height":height,"minimum":lower,"maximum":capacity,"fixed":fixed})
	if total_free_metres<=minimum+.000002: return {"valid":false,"reason":"taut sliding cable needs an external tension boundary"}
	if total_free_metres>maximum+LENGTH_TOLERANCE: return {"valid":false,"reason":"sliding material requires supported folds","maximum_unfolded_metres":maximum}
	var best := {}
	for seed in descriptions.size()+1:
		var lengths := PackedFloat64Array()
		for description: Dictionary in descriptions: lengths.append(description.minimum)
		var remaining := total_free_metres-minimum
		if seed==descriptions.size():
			for index in descriptions.size(): lengths[index]+=remaining*(descriptions[index].maximum-descriptions[index].minimum)/(maximum-minimum)
		else:
			for offset in descriptions.size():
				var index := (seed+offset)%descriptions.size()
				var allocated := minf(remaining,descriptions[index].maximum-lengths[index])
				lengths[index]+=allocated
				remaining-=allocated
		# The energy is not globally convex in length: a freely hanging bight
		# can transfer material to a supported leg. Minimize each pair across
		# all sampled stationary branches, not a monotone-lambda assumption.
		for iteration in 32:
			var moved := 0.0
			for first in descriptions.size():
				for last in range(first+1,descriptions.size()):
					var pair := _pair(descriptions[first],descriptions[last],lengths[first],lengths[first]+lengths[last],gravity,radius,kg_per_metre)
					if not pair.valid: return pair
					moved=maxf(moved,absf(pair.first-lengths[first]))
					lengths[last]+=lengths[first]-pair.first
					lengths[first]=pair.first
			if moved<.0000005: break
		var value := _assembled(descriptions,lengths,gravity,radius,kg_per_metre,false)
		if not value.valid: return value
		if best.is_empty() or value.energy_j<best.energy_j:
			best=value
			best["lengths"]=lengths.duplicate()
	var value := _assembled(descriptions,best.lengths,gravity,radius,kg_per_metre,sample_path)
	value["length_error_metres"]=value.metres-total_free_metres
	value["valid"]=value.valid and absf(value.length_error_metres)<=LENGTH_TOLERANCE and value.maximum_potential_error_n<=FORCE_TOLERANCE
	if not value.valid: value["reason"]="sliding material equilibrium did not converge"
	return value

static func _span(description: Dictionary,metres: float,gravity: Vector3,radius: float,kg_per_metre: float,sampled := false) -> Dictionary:
	return SPAN.solve(description.first,description.last,metres,description.floor,-gravity.normalized(),gravity,radius,kg_per_metre,sampled)

static func _pair(a: Dictionary,b: Dictionary,current: float,total: float,gravity: Vector3,radius: float,kg_per_metre: float) -> Dictionary:
	var low: float=maxf(a.minimum,total-b.maximum)
	var high: float=minf(a.maximum,total-b.minimum)
	if high-low<.0000001: return {"valid":true,"first":low}
	var fractions := PackedFloat64Array([0,.00001,.0001,.001,.005,.995,.999,.9999,.99999,1])
	for index in range(1,32): fractions.append(index/32.0)
	fractions.append(clampf((current-low)/(high-low),0,1))
	fractions.sort()
	var best := {"valid":true,"first":current,"energy":INF}
	var previous := {}
	for fraction in fractions:
		var x := lerpf(low,high,fraction)
		var value := _pair_value(a,b,x,total,gravity,radius,kg_per_metre)
		if not value.valid: return value
		if value.energy<best.energy: best={"valid":true,"first":x,"energy":value.energy}
		if not previous.is_empty() and previous.derivative<0 and value.derivative>0:
			var left: float=previous.x
			var right := x
			for iteration in 40:
				var middle := (left+right)*.5
				var candidate := _pair_value(a,b,middle,total,gravity,radius,kg_per_metre)
				if not candidate.valid: return candidate
				if candidate.energy<best.energy: best={"valid":true,"first":middle,"energy":candidate.energy}
				if absf(candidate.derivative)<FORCE_TOLERANCE*.01: break
				if candidate.derivative<0: left=middle
				else: right=middle
		previous=value
		previous["x"]=x
	return best

static func _pair_value(a: Dictionary,b: Dictionary,first: float,total: float,gravity: Vector3,radius: float,kg_per_metre: float) -> Dictionary:
	var left := _span(a,first,gravity,radius,kg_per_metre)
	var right := _span(b,total-first,gravity,radius,kg_per_metre)
	if not left.valid or not right.valid: return {"valid":false,"reason":"invalid pair material boundary"}
	return {"valid":true,"energy":left.energy_j+right.energy_j,"derivative":right.tension_potential_n-left.tension_potential_n}

static func _assembled(descriptions: Array,lengths: PackedFloat64Array,gravity: Vector3,radius: float,kg_per_metre: float,sampled: bool) -> Dictionary:
	var rows := []
	var total := 0.0
	var energy := 0.0
	var maximum_error := 0.0
	var weight := gravity.length()*kg_per_metre
	var tension := NAN
	for index in descriptions.size():
		if descriptions[index].fixed: continue
		var span := _span(descriptions[index],lengths[index],gravity,radius,kg_per_metre)
		if not span.valid: return span
		tension=span.tension_potential_n
		break
	if is_nan(tension): tension=-weight*descriptions[0].floor_height
	for index in descriptions.size():
		var description: Dictionary=descriptions[index]
		var metres: float=lengths[index]
		var result := _span(description,metres,gravity,radius,kg_per_metre,sampled)
		if not result.valid: return {"valid":false,"reason":"sliding span resolution failed: "+result.get("reason","")}
		if description.fixed:
			# A straight supported run has no length freedom, but transmits the
			# tension imposed by its adjoining suspended portions.
			var horizontal := maxf(0,tension+weight*description.floor_height)
			var axis: Vector3=(description.last-description.first).normalized()
			result.first_force_n=axis*horizontal
			result.last_force_n=-axis*horizontal
			result.horizontal_tension_n=horizontal
			result.tension_potential_n=tension
		result["metres"]=metres
		total+=metres
		energy+=result.energy_j
		maximum_error=maxf(maximum_error,absf(result.tension_potential_n-tension))
		rows.append(result)
	return {"valid":true,"spans":rows,"metres":total,"energy_j":energy,"maximum_potential_error_n":maximum_error,"tension_potential_n":tension}
