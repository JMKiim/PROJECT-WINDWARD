extends RefCounted

## A supported hanging span ending at the fixed inlet of the authored floor
## lay. Hand-local motion stays in its verified short material fixture.
const SEGMENTS := 64
const CONTACT := preload("res://src/boat/rope_contact_geometry.gd")
var history := PackedVector3Array()
var last_revision := -1
var last_pass_count := 0

func reset() -> void:
	history.clear()
	last_revision = -1

func build(prefix: PackedVector3Array,ground: Vector3,actor: Node3D,hull: MeshInstance3D,rig_path: PackedVector3Array = PackedVector3Array(),expanded_contacts := false) -> PackedVector3Array:
	var fixed_count: int = actor.sheet_study.MANUAL_HELD_SEGMENTS+3
	var fixed := prefix.slice(0,fixed_count)
	var result := fixed.duplicate()
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
	var curve := prefix.slice(fixed_count-1)
	for index in range(1,SEGMENTS):
		var t := index/float(SEGMENTS)
		var u := 1.0-t
		curve.append(spline_start*u*u*u+first*3*u*u*t+second*3*u*t*t+ground*t*t*t)
	curve.append(ground)
	var segments := curve.size()-1
	var delta: float = clampf(actor.sheet_study.manual_delta,0,.067)
	var warm := history.size()==curve.size() and history[0].distance_to(start)<.25
	if warm:
		var attachment := start-history[0]
		var follow := 1-exp(-5.0*delta)
		if last_revision==actor.sheet_study.manual_revision: follow = 0.0
		for index in range(1,segments):
			var t := index/float(segments)
			var retained := history[index]+attachment*pow(1-t,2)
			curve[index] = retained.lerp(curve[index],follow)
	# One time-scaled smoothing pass retains the chosen side of each rounded
	# support. Rebuilding/projecting a fresh spline can switch across a leg.
	var smooth_weight := 1-exp(-8.0*delta)
	for index in range(2,segments-1):
		curve[index] = curve[index].lerp((curve[index-1]+curve[index+1])*.5,smooth_weight)
	curve = _redistribute(curve)
	var supports: Array = actor.sheet_study._tail_supports()
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
	var prefix_remaining := PackedFloat32Array()
	prefix_remaining.resize(fixed.size())
	for index in range(fixed.size()-2,-1,-1):
		prefix_remaining[index] = prefix_remaining[index+1]+fixed[index].distance_to(fixed[index+1])
	var fixed_groups := _groups(fixed)
	var support_bounds := []
	for support in supports:
		support_bounds.append(_bounds(support[0],support[1]).grow(support[2]+.002))
	for pass_index in 12:
		var before_pass := curve.duplicate()
		# A cold pose may have long, uneven support chords. An already
		# continuous span gets one midpoint redistribution if contacts still
		# need work. Repeating it every pass releases material in a burst.
		if pass_index>0 and (not warm or (not expanded_contacts and pass_index==6)): curve = _redistribute(curve)
		for index in range(1,segments):
			var point := curve[index]
			for support in supports:
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
		var largest_change := 0.0
		for index in range(1,segments):
			largest_change = maxf(largest_change,curve[index].distance_squared_to(before_pass[index]))
		# Expanded warm contact uses one redistribution per frame. Contact
		# convergence must not conditionally introduce another material shift.
		if largest_change<.000025*.000025: break
	# Corrections of a later loose link can move the shared end of a link
	# already checked against the held rope. Resolve that boundary and the
	# adjacent fingers together: a held-rope correction must not push the
	# loose strand into a hand on the opposite seat.
	for sweep in (12 if expanded_contacts else 2):
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
		var closure_change := 0.0
		for index in range(1,segments): closure_change = maxf(closure_change,curve[index].distance_squared_to(before_closure[index]))
		if expanded_contacts and closure_change<.000025*.000025: break
	history = curve.duplicate()
	last_revision = actor.sheet_study.manual_revision
	result.append_array(curve.slice(1))
	return result

func _clear_free_self_contact(curve: PackedVector3Array) -> void:
	# A final hand/support correction can fold two loose links together after
	# the main self-contact pass. Close that same constraint in the final sweep.
	var groups := _groups(curve)
	var travelled := 0.0
	var material := PackedFloat32Array([0.0])
	for index in curve.size()-1:
		var search := _bounds(curve[index],curve[index+1]).grow(.030)
		for group: Array in groups:
			if group[0]>=index-1: break
			if not search.intersects(group[2]): continue
			for segment in range(group[0],mini(group[1],index-1)):
				_project_link(curve,index,curve[segment],curve[segment+1],.009,0.0,travelled-material[segment+1])
		if index>0 and curve[index-1].distance_to(curve[index])>.010 and curve[index].distance_to(curve[index+1])>.010:
			_project_link(curve,index,curve[index-1],curve[index].move_toward(curve[index-1],.010),.009,.010)
		travelled += curve[index].distance_to(curve[index+1])
		material.append(travelled)
		for group_index in range(maxi(0,(index-1)/8),mini(groups.size(),(index+1)/8+1)):
			var group: Array = groups[group_index]
			group[2] = _group_bounds(curve,group[0],group[1])

func _bounds(a: Vector3,b: Vector3) -> AABB:
	return AABB(a.min(b),(b-a).abs()).grow(.000001)

func _group_bounds(path: PackedVector3Array,first: int,last: int) -> AABB:
	var bounds := AABB(path[first],Vector3.ZERO)
	for index in range(first+1,last+1): bounds = bounds.expand(path[index])
	return bounds.grow(.009)

func _groups(path: PackedVector3Array) -> Array:
	var result := []
	for first in range(0,path.size()-1,8):
		var last := mini(first+8,path.size()-1)
		result.append([first,last,_group_bounds(path,first,last)])
	return result

func _redistribute(path: PackedVector3Array) -> PackedVector3Array:
	# Contact can lengthen one chord while bunching its neighbours. Keep
	# sampling uniform along the same polyline before the next projection;
	# otherwise a long chord can cut across a rounded leg support.
	var distances := PackedFloat32Array([0.0])
	for index in path.size()-1:
		distances.append(distances[-1]+path[index].distance_to(path[index+1]))
	var result := PackedVector3Array([path[0]])
	var segment := 0
	for index in range(1,path.size()-1):
		var target := distances[-1]*index/float(path.size()-1)
		while segment<path.size()-2 and distances[segment+1]<target: segment += 1
		var weight := (target-distances[segment])/maxf(.000001,distances[segment+1]-distances[segment])
		result.append(path[segment].lerp(path[segment+1],weight))
	result.append(path[-1])
	return result

func _project_link(curve: PackedVector3Array,index: int,a: Vector3,b: Vector3,radius: float,trim_start := 0.0,material_gap := INF) -> void:
	# Point-only projection can put neighbouring vertices on opposite sides
	# of a calf while their chord cuts through it. Constrain the chord too.
	var start := curve[index]
	var end := curve[index+1]
	if minf(start.x,end.x)>maxf(a.x,b.x)+radius or maxf(start.x,end.x)<minf(a.x,b.x)-radius: return
	if minf(start.y,end.y)>maxf(a.y,b.y)+radius or maxf(start.y,end.y)<minf(a.y,b.y)-radius: return
	if minf(start.z,end.z)>maxf(a.z,b.z)+radius or maxf(start.z,end.z)<minf(a.z,b.z)-radius: return
	var test_start := start.move_toward(end,trim_start)
	var near := CONTACT.closest_segments(test_start,end,a,b)
	# Neighbour distance belongs to the closest points, not segment starts.
	# Long support chords can fold across several much shorter following links.
	if material_gap+near[0].distance_to(start)+near[1].distance_to(b)<.025:
		var first_length := start.distance_to(end)
		var second_length := a.distance_to(b)
		var required := .025-material_gap
		if required>first_length+second_length or minf(first_length,second_length)<.000001: return
		# The unconstrained nearest pair may be an innocent shared bend while
		# a farther part of those same links overlaps. Minimize separation on
		# the material-distance boundary instead of ignoring the whole pair.
		var low := maxf(0,(required-second_length)/first_length)
		var high := minf(1,required/first_length)
		var previous_direction := (b-a)/second_length
		var difference := start-b+previous_direction*required
		var slope := end-start-previous_direction*first_length
		var fraction := clampf(-difference.dot(slope)/maxf(.000000001,slope.length_squared()),low,high)
		near[0] = start+(end-start)*fraction
		near[1] = b-previous_direction*(required-fraction*first_length)
	var offset := near[0]-near[1]
	var distance := offset.length()
	if distance>=radius: return
	if distance<.000001:
		offset = start-Geometry3D.get_closest_point_to_segment(start,a,b)
		if offset.is_zero_approx(): offset = Vector3.LEFT
	var t := clampf((near[0]-start).dot(end-start)/maxf(.0000001,start.distance_squared_to(end)),0,1)
	var first := 1.0-t if index>0 else 0.0
	var last := t if index+1<curve.size()-1 else 0.0
	var divisor := first*first+last*last
	if divisor<.000001: return
	var correction := offset.normalized()*(radius-distance)/divisor
	correction = correction.limit_length(.010/maxf(first,last))
	if first>0: curve[index] += correction*first
	if last>0: curve[index+1] += correction*last
