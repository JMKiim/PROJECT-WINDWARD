extends "res://src/boat/mainsheet_supported_lead.gd"

## Main-thread incremental copy of the approved cold supported-lead solve.
## Each call completes one original projection/closure sweep. It neither
## changes the live actor nor introduces a different pose/contact search.
var fixed_count := 0
var fixed := PackedVector3Array()
var result := PackedVector3Array()
var curve := PackedVector3Array()
var segments := 0
var delta := 0.0
var warm := false
var temporal_centres := PackedVector3Array()
var supports := []
var prefix_remaining := PackedFloat32Array()
var fixed_groups := []
var support_bounds := []
var point_support_bounds := []
var hull: MeshInstance3D
var revision := -1
var expanded_contacts := false
var pass_index := 0
var sweep := 0
var phase := "idle"

func begin(prefix: PackedVector3Array,ground: Vector3,actor: Node3D,surface: MeshInstance3D,rig_path: PackedVector3Array=PackedVector3Array(),expanded := false) -> void:
	hull=surface
	revision=actor.sheet_study.manual_revision
	expanded_contacts=expanded
	pass_index=0
	sweep=0
	phase="projection"
	if trace_enabled: trace_steps.clear()
	fixed_count = actor.sheet_study.MANUAL_HELD_SEGMENTS+3
	fixed = prefix.slice(0,fixed_count)
	result = fixed.duplicate()
	var start := fixed[-1]
	var spline_start := prefix[-1]
	var tangent := (spline_start-prefix[-2]).normalized()
	var down: Vector3 = actor.sheet_study.gravity_boat()
	var first := spline_start+tangent*.060
	var outward := Vector3(float(actor.seat_side),0,0)
	# Seed the cold route outside the releasing fingers before it crosses
	# toward a floor inlet on the other side. This is an initial curve, not
	# an extra attachment; the same finite contact constraints apply below.
	if expanded_contacts: first += outward*.160*smoothstep(.050,.200,-(ground-spline_start).dot(outward))
	var second := ground-down*.250
	curve = prefix.slice(fixed_count-1)
	for index in range(1,SEGMENTS):
		var t := index/float(SEGMENTS)
		var u := 1.0-t
		curve.append(spline_start*u*u*u+first*3*u*u*t+second*3*u*t*t+ground*t*t*t)
	curve.append(ground)
	segments = curve.size()-1
	delta = clampf(actor.sheet_study.manual_delta,0,.067)
	warm = history.size()==curve.size() and history[0].distance_to(start)<.25
	temporal_centres = PackedVector3Array()
	if warm:
		temporal_centres = history.duplicate()
		var attachment := start-history[0]
		var follow := 1-exp(-5.0*delta)
		if last_revision==actor.sheet_study.manual_revision: follow = 0.0
		for index in range(1,segments):
			var t := index/float(segments)
			var retained := history[index]+attachment*pow(1-t,2)
			temporal_centres[index] = retained
			curve[index] = retained.lerp(curve[index],follow)
		temporal_centres[0] = curve[0]
		temporal_centres[-1] = curve[-1]
	_trace_step(history,curve,"follow")
	# One time-scaled smoothing pass retains the chosen side of each rounded
	# support. Rebuilding/projecting a fresh spline can switch across a leg.
	var smooth_weight := 1-exp(-8.0*delta)
	for index in range(2,segments-1):
		curve[index] = curve[index].lerp((curve[index-1]+curve[index+1])*.5,smooth_weight)
	var before_distribution := curve.duplicate() if trace_enabled else PackedVector3Array()
	curve = _redistribute(curve)
	_trace_step(before_distribution,curve,"redistribute")
	supports = actor.sheet_study._tail_supports()
	if expanded_contacts:
		# A loose line cannot thread through the tiny concave gaps between
		# overlapping finger capsules. Their closed-hand outer envelope gives
		# the projection a consistent outside surface; individual fingers are
		# still checked separately, with the original clearance requirements.
		for hand: String in [actor.sheet_hand(),actor.tiller_hand()]:
			var fingers: Array = actor.sheet_study._finger_supports(hand)
			var a: Vector3 = (fingers[0][0]+fingers[0][1]+fingers[1][1])/3.0
			var b: Vector3 = (fingers[6][0]+fingers[6][1]+fingers[7][1])/3.0
			var radius := .0
			for finger: Array in fingers:
				for point: Vector3 in [finger[0],finger[1]]:
					radius = maxf(radius,point.distance_to(Geometry3D.get_closest_point_to_segment(point,a,b))+.015)
			supports.append([a,b,radius])
	# The rig's incoming loaded leg can share the cockpit's airspace when
	# the sailor sits on the other side of the unchanged boom and floor lay.
	if expanded_contacts:
		var swept_bounds := _group_bounds(curve,0,curve.size()-1).grow(.20)
		for index in rig_path.size()-1:
			if swept_bounds.intersects(_bounds(rig_path[index],rig_path[index+1])):
				supports.append([rig_path[index],rig_path[index+1],.007])
	prefix_remaining = PackedFloat32Array()
	prefix_remaining.resize(fixed.size())
	for index in range(fixed.size()-2,-1,-1):
		prefix_remaining[index] = prefix_remaining[index+1]+fixed[index].distance_to(fixed[index+1])
	fixed_groups = _groups(fixed)
	support_bounds = []
	point_support_bounds = []
	for support in supports:
		support_bounds.append(_bounds(support[0],support[1]).grow(support[2]+.002))
		point_support_bounds.append(_bounds(support[0],support[1]).grow(support[2]+.003001))

func _projection_step() -> void:
	var before_pass := curve.duplicate()
	# A cold pose may have long, uneven support chords. An already
	# continuous span gets one midpoint redistribution if contacts still
	# need work. Repeating it every pass releases material in a burst.
	if pass_index>0 and (not warm or (not expanded_contacts and pass_index==6)): curve = _redistribute(curve)
	for index in range(1,segments):
		var point := curve[index]
		for support_index in supports.size():
			# Exact capsule projection only inside its conservative box.
			# Keep original order: each correction changes the next query.
			if not point_support_bounds[support_index].has_point(point): continue
			var support: Array=supports[support_index]
			var nearest := Geometry3D.get_closest_point_to_segment(point,support[0],support[1])
			var offset := point-nearest
			var radius: float = support[2]+.003
			if offset.length_squared()<radius*radius:
				if offset.is_zero_approx(): offset = Vector3.LEFT
				point = nearest+offset.normalized()*radius
		point.y = maxf(point.y,hull.cockpit_floor_y_at(point.x,point.z)+.006)
		curve[index] = point
	var travelled := 0.0
	var material := PackedFloat32Array([0.0])
	var curve_groups := _groups(curve)
	for index in segments:
		var search := _bounds(curve[index],curve[index+1]).grow(.030)
		for support_index in supports.size():
			if not search.intersects(support_bounds[support_index]): continue
			var support: Array = supports[support_index]
			_project_link(curve,index,support[0],support[1],support[2]+.002)
		search = _bounds(curve[index],curve[index+1]).grow(.030)
		for group: Array in fixed_groups:
			if not search.intersects(group[2]): continue
			for segment in range(group[0],group[1]):
				var gap := travelled+prefix_remaining[segment+1]
				_project_link(curve,index,fixed[segment],fixed[segment+1],.009,0.0,gap)
		search = _bounds(curve[index],curve[index+1]).grow(.030)
		for group: Array in curve_groups:
			if group[0]>=index-1: break
			if not search.intersects(group[2]): continue
			for segment in range(group[0],mini(group[1],index-1)):
				var gap := travelled-material[segment+1]
				_project_link(curve,index,curve[segment],curve[segment+1],.009,0.0,gap)
		if index>0 and curve[index-1].distance_to(curve[index])>.010 and curve[index].distance_to(curve[index+1])>.010:
			# Adjacent long links can fold back along each other. Ignore
			# only their shared 10mm ends, not the entire neighbouring pair.
			var previous_end := curve[index].move_toward(curve[index-1],.010)
			_project_link(curve,index,curve[index-1],previous_end,.009,.010)
		travelled += curve[index].distance_to(curve[index+1])
		material.append(travelled)
		for group_index in range(maxi(0,(index-1)/8),mini(curve_groups.size(),(index+1)/8+1)):
			var group: Array = curve_groups[group_index]
			group[2] = _group_bounds(curve,group[0],group[1])
	last_pass_count = pass_index+1
	if expanded_contacts: _bound_corrections(curve,temporal_centres,delta)
	_trace_step(before_pass,curve,"projection "+str(pass_index))
	var largest_change := 0.0
	for index in range(1,segments):
		largest_change = maxf(largest_change,curve[index].distance_squared_to(before_pass[index]))
	# Expanded warm contact uses one redistribution per frame. Contact
	# convergence must not conditionally introduce another material shift.
	if largest_change<.000025*.000025: phase="closure"
	pass_index+=1
	if pass_index>=12: phase="closure"

func _closure_step() -> void:
	var before_closure := curve.duplicate()
	if expanded_contacts:
		for index in range(1,segments):
			var incoming := curve[index]-curve[index-1]
			var outgoing := curve[index+1]-curve[index]
			if minf(incoming.length(),outgoing.length())>.010 and incoming.dot(outgoing)<0:
				var reversal := -incoming.normalized().dot(outgoing.normalized())
				curve[index] = curve[index].lerp((curve[index-1]+curve[index+1])*.5,.5*smoothstep(0,.6,reversal))
	var travelled := 0.0
	for index in segments:
		var search := _bounds(curve[index],curve[index+1]).grow(.030)
		for group: Array in fixed_groups:
			if not search.intersects(group[2]): continue
			for segment in range(group[0],group[1]):
				_project_link(curve,index,fixed[segment],fixed[segment+1],.009,0.0,travelled+prefix_remaining[segment+1])
		if expanded_contacts:
			search = _bounds(curve[index],curve[index+1]).grow(.030)
			for support_index in supports.size():
				if not search.intersects(support_bounds[support_index]): continue
				var support: Array = supports[support_index]
				_project_link(curve,index,support[0],support[1],support[2]+.002)
		travelled += curve[index].distance_to(curve[index+1])
	if expanded_contacts: _clear_free_self_contact(curve)
	if expanded_contacts: _bound_corrections(curve,temporal_centres,delta)
	_trace_step(before_closure,curve,"closure "+str(sweep))
	var closure_change := 0.0
	for index in range(1,segments): closure_change = maxf(closure_change,curve[index].distance_squared_to(before_closure[index]))
	if expanded_contacts and closure_change<.000025*.000025: phase="finish"
	sweep+=1
	if sweep>=(12 if expanded_contacts else 2): phase="finish"

func advance() -> bool:
	if phase=="projection": _projection_step()
	elif phase=="closure": _closure_step()
	if phase=="finish":
		history=curve.duplicate()
		last_revision=revision
		result.append_array(curve.slice(1))
		phase="done"
	return phase=="done"
