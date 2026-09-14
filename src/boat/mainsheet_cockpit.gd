extends RefCounted

## Length-driven authored floor folds joined to the verified hanging lead.
const STOPPER := preload("res://src/boat/mainsheet_stopper.gd")
const LAY := preload("res://src/boat/mainsheet_floor_lay.gd")
const PILE := preload("res://src/boat/mainsheet_pile_lay.gd")
const JOIN := preload("res://src/boat/mainsheet_deck_join.gd")
const SUPPORTED := preload("res://src/boat/mainsheet_supported_lead.gd")
const RADIUS := .004
var actor: Node3D
var hull: MeshInstance3D
var floor_lay: RefCounted = LAY.new()
var ground_end := PackedVector3Array()
var end_shape := PackedVector3Array()
var ground_end_length := 0.0
var last_path := PackedVector3Array()
var last_partition := {}
var floor_supports := []
var end_rotation := Quaternion.IDENTITY
var end_origin := Vector3.ZERO
var end_rotation_initialized := false
var current_outlet := Vector3.ZERO
var end_debug := {}
var diagnostics_enabled := false
var purchase_join := false
var supported_lead := SUPPORTED.new()
var last_timings := {}
var resting_end_key := []
var resting_end := PackedVector3Array()
var rig_clearance_path := PackedVector3Array()
var expanded_contact_support := false
var end_lead := PackedVector3Array()

func setup(value: Node3D, floor_mesh: MeshInstance3D) -> void:
	actor = value
	hull = floor_mesh
	floor_lay.setup(hull)
	var authored_end := STOPPER.grounded_points()
	var direction := (authored_end[1]-authored_end[0]).normalized()
	var flat := Vector3(direction.x,0,direction.z).normalized()
	var rotation := Basis(Vector3.UP,flat.signed_angle_to(Vector3.RIGHT,Vector3.UP))
	for point in authored_end: end_shape.append(rotation*point)
	ground_end_length = STOPPER.length_of(end_shape)
	ground_end = _end_at(floor_lay.minimum_path[-1],Vector3.BACK)
	reset_motion()

func reset_motion() -> void:
	end_rotation_initialized = false
	resting_end_key.clear()
	resting_end.clear()
	supported_lead.reset()

func use_pile_bank() -> bool:
	var candidate := PILE.new()
	if not candidate.load_bank(hull): return false
	floor_lay = candidate
	expanded_contact_support = true
	ground_end = _end_at(floor_lay.minimum_path[-1],Vector3.BACK)
	reset_motion()
	return true

func build(cockpit_metres: float, end_metres: float) -> PackedVector3Array:
	var began := Time.get_ticks_usec()
	# The original local tail is kept as motion history. It is not the whole
	# rope and is never counted in addition to the displayed material path.
	actor.sheet_study.manual_cache_revision = -1
	var raw: PackedVector3Array
	var local_trim := .16 if purchase_join else 1.8
	if actor.sheet_control.regrip_time>=0:
		raw = actor.sheet_control.regrip.rope_points(local_trim)
	else: raw = actor.sheet_study.manual_points(local_trim)
	var local_done := Time.get_ticks_usec()
	var held_index: int = actor.sheet_study.MANUAL_HELD_SEGMENTS
	if purchase_join and expanded_contact_support and not rig_clearance_path.is_empty(): _clear_loaded_rig_contact(raw,held_index)
	var outlet := raw[held_index]
	current_outlet = outlet
	if purchase_join:
		# Preserve the held path, outlet turn and first 100mm of local drape.
		# The far span shares the floor lay's fixed inlet; a newly discovered
		# earlier floor touch must not teleport all the later rope onto a coil.
		raw = supported_lead.build(raw.slice(0,held_index+21),floor_lay.minimum_path[0],actor,hull,rig_clearance_path,expanded_contact_support)
	var supported_done := Time.get_ticks_usec()
	if actor.sheet_study.deck_fitting!=null:
		raw = JOIN.remote(raw,actor.sheet_study.block_anchor) if purchase_join else actor.sheet_study.deck_fitting.deck_lead_route(raw,RADIUS)
		for index in raw.size():
			if raw[index].distance_squared_to(outlet)<.000000000001:
				held_index = index
				break
	var floor_index := -1
	for index in range(raw.size()-1 if purchase_join else held_index+9,raw.size()):
		if raw[index].y <= hull.cockpit_floor_y_at(raw[index].x,raw[index].z)+RADIUS+.003:
			floor_index = index
			break
	var result := raw.duplicate()
	var contact_length := INF
	if floor_index>=0:
		result = raw.slice(0,floor_index+1)
		contact_length = STOPPER.length_of(result)
	var total := cockpit_metres+end_metres
	var held_length := STOPPER.length_of(raw.slice(0,held_index+1))
	if absf(end_metres-ground_end_length)>.0001: return PackedVector3Array()
	var lead_length := total-ground_end_length
	var grounded := floor_index>=0 and lead_length>=contact_length
	if not grounded:
		if lead_length<held_length: return PackedVector3Array()
		result = actor.sheet_study._truncate_path(raw,lead_length)
		if absf(STOPPER.length_of(result)-lead_length)>.001: return PackedVector3Array()
		var landing := raw[floor_index] if floor_index>=0 else result[-1]
		var landing_tangent := _floor_control1(landing)-landing
		landing_tangent.y = 0.0
		end_lead = result
		var knot := _end_at(result[-1],landing_tangent)
		result.append_array(knot.slice(1))
		last_partition = {"held":held_length,"suspended":lead_length-held_length,"floor":0.0,"end":ground_end_length,"valid":true}
	else:
		_update_supports()
		var ground_budget := total-contact_length-ground_end_length
		var connector := _floor_connector(result[-1],floor_lay.minimum_path[0])
		var connector_length := STOPPER.length_of(connector)
		if ground_budget<connector_length:
			connector = LAY._prefix(connector,ground_budget)
			result.append_array(connector.slice(1))
		else:
			result.append_array(connector.slice(1))
			var laid: PackedVector3Array = floor_lay.build(ground_budget-connector_length)
			if laid.is_empty(): return PackedVector3Array()
			result.append_array(laid.slice(1))
		end_lead = result
		var knot := _end_at(result[-1],result[-1]-result[-2])
		result.append_array(knot.slice(1))
		last_partition = {"held":held_length,"suspended":contact_length-held_length,"floor":ground_budget,"end":ground_end_length,"valid":true,"floor_start_index":floor_index}
	last_timings = {"local_ms":(local_done-began)/1000.0,"supported_ms":(supported_done-local_done)/1000.0,"remainder_ms":(Time.get_ticks_usec()-supported_done)/1000.0,"passes":supported_lead.last_pass_count}
	return _finish(result,total,grounded)

func _clear_loaded_rig_contact(raw: PackedVector3Array,held_index: int) -> void:
	# Two tensioned legs may touch when the sailor is on the boom side.
	# Deflect only the free loaded lead, never its real hand channel or the
	# fitting's shared 100mm boundary. No human joint or rope budget changes.
	var first := 0
	var travelled := 0.0
	while first<held_index-1 and travelled<.125:
		travelled += raw[first].distance_to(raw[first+1])
		first += 1
	var last := held_index
	travelled = 0.0
	while last>first+1 and travelled<.080:
		travelled += raw[last].distance_to(raw[last-1])
		last -= 1
	if last<=first+1: return
	var lead := raw.slice(first,last+1)
	var bounds := supported_lead._group_bounds(lead,0,lead.size()-1).grow(.10)
	var nearby := []
	for segment in rig_clearance_path.size()-1:
		if bounds.intersects(supported_lead._bounds(rig_clearance_path[segment],rig_clearance_path[segment+1])):
			nearby.append(segment)
	if nearby.is_empty(): return
	for sweep in 8:
		var before := lead.duplicate()
		for index in lead.size()-1:
			for segment: int in nearby:
				supported_lead._project_link(lead,index,rig_clearance_path[segment],rig_clearance_path[segment+1],.009)
		var change := 0.0
		for index in range(1,lead.size()-1): change = maxf(change,lead[index].distance_squared_to(before[index]))
		if change<.000025*.000025: break
	for index in lead.size(): raw[first+index] = lead[index]

func _finish(result: PackedVector3Array,total: float,grounded: bool) -> PackedVector3Array:
	last_path = result
	last_partition["displayed_total"] = STOPPER.length_of(result)
	last_partition["requested_total"] = total
	last_partition["grounded_end"] = grounded
	return result

func _end_at(origin: Vector3,tangent: Vector3) -> PackedVector3Array:
	var floor_y: float = hull.cockpit_floor_y_at(origin.x,origin.z)+RADIUS+.002
	var height := maxf(0,origin.y-floor_y)
	var standing := (end_shape[1]-end_shape[0]).normalized()
	standing.y = 0.0
	standing = standing.normalized()
	var down: Vector3 = actor.sheet_study.gravity_boat()
	var resting_key := [origin,tangent,down,floor_y,actor.hike,actor.seat_side]
	if height<.0001 and resting_key==resting_end_key and not resting_end.is_empty():
		return resting_end
	var horizontal := Vector3(tangent.x,0,tangent.z).normalized()
	if horizontal.is_zero_approx(): horizontal = Vector3.RIGHT
	var lifted := smoothstep(0,.16,height)
	var desired := horizontal.slerp(down,lifted)
	var yaw := Quaternion(Vector3.UP,standing.signed_angle_to(horizontal,Vector3.UP))
	var near_hand := 1-smoothstep(.14,.35,origin.distance_to(current_outlet))
	# A tangent plane on the convex side fillet lies beneath the flatter
	# cockpit. Support the finite knot itself instead of tilting it into it.
	var rotation := Quaternion(desired,PI*.5*lifted*near_hand)*Quaternion(horizontal,desired)*yaw
	if purchase_join and height>.10:
		rotation = _end_body_roll(origin,rotation,desired)
		if floor_lay is PILE:
			rotation = _end_contact_tilt(origin,rotation)
	if end_rotation_initialized and origin.distance_to(end_origin)<.25:
		var angle := end_rotation.angle_to(rotation)
		if angle>.00001:
			rotation = end_rotation.slerp(rotation,minf(1,6.0*clampf(actor.sheet_study.manual_delta,0,.067)/angle))
	if height<.16:
		rotation = _supported_end_roll(origin,rotation)
		if _end_floor_gap(origin,rotation)<-.0001:
			# Contact can stop the free angular motion. Find the first clear
			# rigid orientation toward the local resting pose, retaining length.
			var resting := _supported_end_roll(origin,yaw)
			var low := 0.0
			var high := 1.0
			for iteration in 9:
				var fraction := (low+high)*.5
				if _end_floor_gap(origin,rotation.slerp(resting,fraction))<-.0001: low = fraction
				else: high = fraction
			rotation = rotation.slerp(resting,high)
	var settled := end_rotation_initialized and end_rotation.angle_to(rotation)<.00001
	end_rotation = rotation
	end_origin = origin
	end_rotation_initialized = true
	if diagnostics_enabled:
		end_debug = {"origin":str(origin),"height":height,"landing":str(horizontal),"rotation":str(rotation),"gap":_end_floor_gap(origin,rotation)}
	var result := PackedVector3Array()
	for point in end_shape: result.append(origin+rotation*point)
	if height<.0001 and settled:
		resting_end_key = resting_key
		resting_end = result
	else:
		resting_end_key.clear()
		resting_end.clear()
	return result

func _end_contact_tilt(origin: Vector3,rotation: Quaternion) -> Quaternion:
	var supports: Array = actor.sheet_study._tail_supports()
	var material := 0.0
	for index in range(end_lead.size()-2,-1,-1):
		material += end_lead[index].distance_to(end_lead[index+1])
		if material<.040: continue
		if supported_lead._bounds(end_lead[index],end_lead[index+1]).grow(.22).has_point(origin):
			supports.append([end_lead[index],end_lead[index+1],.002])
	for iteration in 10:
		var largest := 0.0
		var before := Vector3.ZERO
		var after := Vector3.ZERO
		for index in range(1,end_shape.size(),3):
			var relative := rotation*end_shape[index]
			var point := origin+relative
			for support in supports:
				var near := Geometry3D.get_closest_point_to_segment(point,support[0],support[1])
				var offset := point-near
				var penetration: float = support[2]+.008-offset.length()
				if penetration>largest and relative.length()>.015 and offset.length()>.0001:
					largest = penetration
					before = relative.normalized()
					after = (relative+offset.normalized()*penetration).normalized()
		if largest<.000025: break
		rotation = Quaternion(before,after)*rotation
	return rotation

func _end_body_roll(origin: Vector3,rotation: Quaternion,axis: Vector3) -> Quaternion:
	var supports: Array = actor.sheet_study._tail_supports()
	var outward := Vector3.ZERO
	for support in supports:
		var near := Geometry3D.get_closest_point_to_segment(origin,support[0],support[1])
		var offset := origin-near
		var clearance: float = offset.length()-support[2]
		var radial := offset-axis*offset.dot(axis)
		if clearance<.15 and not radial.is_zero_approx():
			outward += radial.normalized()*pow(.15-clearance,2)
	if outward.is_zero_approx(): return rotation
	var center := Vector3.ZERO
	for point in end_shape: center += point
	center = rotation*(center/end_shape.size())
	var lobe := center-axis*center.dot(axis)
	if lobe.is_zero_approx(): return rotation
	var candidate := Quaternion(axis,lobe.signed_angle_to(outward,axis))*rotation
	var best := candidate
	var best_gap := _end_support_gap(origin,candidate,supports)
	if best_gap>=.006: return candidate
	# The knot is a finite rigid end, not a point. Check a bounded set of
	# rolls about its unchanged standing axis only when near a body surface.
	# Existing temporal rotation limits still govern the chosen orientation.
	for index in range(1,9):
		for sign_value: float in [-1,1]:
			var tested := Quaternion(axis,sign_value*PI*index/8.0)*candidate
			var gap := _end_support_gap(origin,tested,supports)
			if gap>best_gap:
				best_gap = gap
				best = tested
			if gap>=.006: return tested
	return best

func _end_support_gap(origin: Vector3,rotation: Quaternion,supports: Array) -> float:
	var gap := INF
	for index in range(0,end_shape.size(),4):
		var point := origin+rotation*end_shape[index]
		for support in supports:
			var near := Geometry3D.get_closest_point_to_segment(point,support[0],support[1])
			gap = minf(gap,point.distance_to(near)-support[2])
	var tip := origin+rotation*end_shape[-1]
	for support in supports:
		var near := Geometry3D.get_closest_point_to_segment(tip,support[0],support[1])
		gap = minf(gap,tip.distance_to(near)-support[2])
	return gap

func _end_floor_gap(origin: Vector3,rotation: Quaternion) -> float:
	var gap := INF
	for point in end_shape:
		var world := origin+rotation*point
		gap = minf(gap,world.y-hull.cockpit_floor_y_at(world.x,world.z)-RADIUS)
	return gap

func _supported_end_roll(origin: Vector3,rotation: Quaternion) -> Quaternion:
	var angle := 0.0
	for pass_index in 3:
		var adjustment := 0.0
		var rolled := rotation*Quaternion(Vector3.RIGHT,-angle)
		for point in end_shape:
			if point.z<.003: continue
			var world := origin+rolled*point
			var required: float = hull.cockpit_floor_y_at(world.x,world.z)+RADIUS+.0005-world.y
			adjustment = maxf(adjustment,required/point.z)
		if adjustment<.00001: break
		angle = minf(deg_to_rad(75),angle+adjustment)
	return rotation*Quaternion(Vector3.RIGHT,-angle)

func _update_supports() -> void:
	floor_supports = actor.sheet_study._tail_supports()
	for side in ["Left","Right"]:
		floor_supports.append([actor.bone_pose_boat(side+"Foot").origin,actor.bone_pose_boat(side+"Toes").origin,.055])

func _floor_control1(start: Vector3) -> Vector3:
	var inboard := smoothstep(-.27,-.21,start.x)
	return start+Vector3(lerpf(.10,-.09,inboard),0,lerpf(.02,.15,inboard))

func _floor_connector(start: Vector3,finish: Vector3) -> PackedVector3Array:
	if start.distance_squared_to(finish)<.000000001: return PackedVector3Array([start])
	var control1 := _floor_control1(start)
	var control2 := finish-Vector3.RIGHT*.080
	var result := PackedVector3Array([start])
	var count := maxi(8,ceili((start.distance_to(control1)+control1.distance_to(control2)+control2.distance_to(finish))/.008))
	for index in range(1,count+1):
		var u := float(index)/count
		var v := 1.0-u
		var point := start*v*v*v+control1*3*v*v*u+control2*3*v*u*u+finish*u*u*u
		point.y = hull.cockpit_floor_y_at(point.x,point.z)+RADIUS+.002
		for surface in floor_supports:
			var a: Vector3 = surface[0]
			var b: Vector3 = surface[1]
			var near := Geometry3D.get_closest_point_to_segment(point,a,b)
			if point.distance_to(near)>=surface[2]: continue
			var flat := Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
			var horizontal := Vector2(point.x,point.z).distance_to(flat)
			if horizontal>=surface[2]: continue
			var fraction := clampf(Vector2(a.x,a.z).distance_to(flat)/maxf(.000001,Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))),0,1)
			point.y = maxf(point.y,lerpf(a.y,b.y,fraction)+sqrt(surface[2]*surface[2]-horizontal*horizontal)+.002)
		result.append(point)
	result[-1] = finish
	return result
