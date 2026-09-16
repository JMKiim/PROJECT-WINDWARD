extends "res://src/boat/mainsheet_supported_lead.gd"

const FREE_MATERIAL_SPEED := 5.8

## Retain the previous material route across real grip changes, then
## damp its motion toward a supported gravity guide without elastic energy.
var full_history := PackedVector3Array()
var rest_length := 0.0
var previous_cockpit := NAN
var previous_fixed_length := 0.0
var previous_holder := false
var cockpit_length := 0.0
var last_rest_error := 0.0
var reference_overrun := 0.0
var last_timings := {}
var contact_stretch := {}
var contact_context := ""
var floor_entry := PackedVector3Array()
var floor_entry_bounds := []
var floor_entry_distances := PackedFloat32Array()
var floor_bounds := AABB()
var floor_history := PackedVector3Array()
var floor_material_rate := 0.0
var hand_shells := []

func set_material_budget(value: float,entry: PackedVector3Array,laid: PackedVector3Array) -> void:
	cockpit_length = value
	floor_history = laid if laid.size()>1 else entry
	if floor_entry==entry: return
	floor_entry = entry
	floor_entry_distances = _distances(entry)
	floor_bounds = _group_bounds(entry,0,entry.size()-1).grow(.02)
	floor_entry_bounds.clear()
	for index in entry.size()-1: floor_entry_bounds.append(_bounds(entry[index],entry[index+1]))

func needs_full_prefix() -> bool:
	return full_history.is_empty()

func contact_prefix(held: PackedVector3Array,actor: Node3D) -> PackedVector3Array:
	var result := held.duplicate()
	var player: Node = actor.sheet_control.regrip
	var helper: bool = player.time>=.8 and player.time<2.0
	var channel: PackedVector3Array = player.helper_channel() if helper else actor.sheet_channel_boat()
	var tangent := (channel[-1]-channel[-2]).normalized()
	var down: Vector3 = actor.sheet_study.gravity_boat()
	var bend := .025 if helper else .050
	var start := held[-1]
	var finish: Vector3 = start+tangent*bend+down*.012+actor.sheet_study._outlet_turn_offset(start,tangent,down,bend)
	var first := start+tangent*.018
	var second := finish-down*.012
	var supports: Array = actor.sheet_study._tail_supports()
	var previous := start
	for index in range(1,3):
		var u := index/8.0
		var v := 1-u
		var point := start*v*v*v+first*3*v*v*u+second*3*v*u*u+finish*u*u*u
		var length := previous.distance_to(point)
		previous = point
		result.append(player._supported_tail_link(result[-1],point,length,supports))
	return result

func reset() -> void:
	super.reset()
	full_history.clear()
	previous_cockpit = NAN
	rest_length = 0.0
	floor_material_rate = 0.0

func build(prefix: PackedVector3Array,ground: Vector3,actor: Node3D,hull: MeshInstance3D,rig_path: PackedVector3Array = PackedVector3Array(),expanded_contacts := false) -> PackedVector3Array:
	var began := Time.get_ticks_usec()
	contact_stretch = {"supports":0.0,"self":0.0,"floor":0.0,"pushes":{}}
	var fixed_count: int = actor.sheet_study.MANUAL_HELD_SEGMENTS+3
	var fixed := prefix.slice(0,fixed_count)
	var fixed_length := _length(fixed)
	var helper: bool = actor.sheet_control.regrip.time>=.8 and actor.sheet_control.regrip.time<2
	var dt: float = clampf(actor.sheet_study.manual_delta,0,.067)
	if full_history.is_empty():
		full_history = super.build(prefix,ground,actor,hull,rig_path,expanded_contacts)
		history = full_history.slice(fixed_count-1)
		rest_length = _length(history)
		previous_cockpit = cockpit_length
		previous_fixed_length = fixed_length
		previous_holder = helper
		return full_history
	if last_revision==actor.sheet_study.manual_revision: return full_history
	var feed := cockpit_length-previous_cockpit
	var old_length := _length(full_history)
	var prior := full_history.duplicate()
	var floor_distance := 0.0
	for index in range(1,floor_history.size()):
		prior.append(floor_history[index])
		floor_distance += floor_history[index-1].distance_to(floor_history[index])
		if floor_distance>.5: break
	var prior_distances := _distances(prior)
	var offset := fixed_length-feed
	# While easing through the same holder the line slides through its
	# moving guide. Advect material, not the spatial bend: pulling the
	# old curve forward and then pinning it back accumulates a kink against
	# the fingers and expels floor material in a burst.
	var shape_offset := offset
	if feed<0 and helper==previous_holder:
		shape_offset = previous_fixed_length
	var retained := PackedVector3Array([_point_at(prior,prior_distances,shape_offset)])
	for index in full_history.size():
		if prior_distances[index]>shape_offset+.000001: retained.append(full_history[index])
	if retained.size()<2: retained.append(ground)
	retained = _densify(_simplify(retained,.00025),.035)
	var distances := _distances(retained)
	var attachment := fixed[-1]-retained[0]
	# Spread endpoint motion over the hanging span. Concentrating a 19mm
	# hand step into its first 80mm creates a folded kink and artificial
	# contact stretch even during an ordinary uninterrupted first pull.
	for index in retained.size(): retained[index] += attachment*(1-distances[index]/maxf(.00001,distances[-1]))
	retained[0] = fixed[-1]
	retained[-1] = ground
	var curve := retained.duplicate()
	var tangent := (fixed[-1]-fixed[-2]).normalized()
	var down: Vector3 = actor.sheet_study.gravity_boat()
	var first := fixed[-1]+tangent*.08+Vector3(float(actor.seat_side)*.07,0,0)
	var second := ground-down*.25
	var follow := 1-exp(-5.0*dt)
	for index in range(1,curve.size()-1):
		var t := distances[index]/maxf(.00001,distances[-1])
		var u := 1-t
		var guide := fixed[-1]*u*u*u+first*3*u*u*t+second*3*u*t*t+ground*t*t*t
		curve[index] = curve[index].lerp(guide,follow)
	var unsmoothed := curve.duplicate()
	var smooth_weight := 1-exp(-12.0*dt)
	for index in range(1,curve.size()-1): curve[index] = curve[index].lerp((unsmoothed[index-1]+unsmoothed[index+1])*.5,smooth_weight)
	var supports: Array = actor.sheet_study._tail_supports()
	var span_bounds := _group_bounds(curve,0,curve.size()-1).grow(.15)
	hand_shells.clear()
	# A loaded haul keeps its real open channels. Slip blends the loose-line
	# guide continuously during easing/return, including a relay-to-entry seam;
	# switching it on by clip name would push the line abruptly at that seam.
	var shell_weight: float = smoothstep(0,.6,actor.sheet_control.slip)
	for hand: String in ([actor.sheet_hand(),actor.tiller_hand()] if shell_weight>0 else []):
		var fingers: Array = actor.sheet_study._finger_supports(hand)
		var a: Vector3 = (fingers[0][0]+fingers[0][1]+fingers[1][1])/3
		var b: Vector3 = (fingers[6][0]+fingers[6][1]+fingers[7][1])/3
		var radius := 0.0
		for finger: Array in fingers:
			for point: Vector3 in [finger[0],finger[1]]:
				radius = maxf(radius,point.distance_to(Geometry3D.get_closest_point_to_segment(point,a,b))+.018)
		hand_shells.append([a,b,radius*shell_weight])
	for index in rig_path.size()-1:
		if span_bounds.intersects(_bounds(rig_path[index],rig_path[index+1])):
			supports.append([rig_path[index],rig_path[index+1],.007])
	var support_bounds := []
	for support in supports: support_bounds.append(_bounds(support[0],support[1]).grow(support[2]+.004))
	var collision_fixed := _simplify(fixed,.0001)
	var fixed_groups := _groups(collision_fixed)
	var remaining := PackedFloat32Array()
	remaining.resize(collision_fixed.size())
	for index in range(collision_fixed.size()-2,-1,-1): remaining[index] = remaining[index+1]+collision_fixed[index].distance_to(collision_fixed[index+1])
	var transported := old_length+feed-fixed_length
	var prepared := Time.get_ticks_usec()
	contact_stretch["transport_step_mm"] = _material_step(retained,prior,prior_distances,offset)*1000
	for sweep in 6:
		var before := curve.duplicate()
		contact_context = "guide"
		_contacts(curve,collision_fixed,fixed_groups,remaining,supports,support_bounds,hull)
		last_pass_count = sweep+1
		var changed := 0.0
		for index in range(1,curve.size()-1): changed = maxf(changed,before[index].distance_squared_to(curve[index]))
		if changed<.000025*.000025: break
	var contacts_done := Time.get_ticks_usec()
	reference_overrun = 0.0
	var needs_reference := not _within_budget(curve,prior,prior_distances,offset,transported,dt)
	# A contact-clear candidate already inside the material budget needs no
	# second solution of last frame's route. Only prepare that reference when
	# a temporal blend is actually required, so the blend cannot restore a
	# former position inside the current moving hand or shaft.
	if needs_reference:
		contact_context = "retained"
		for sweep in 6:
			var before := retained.duplicate()
			_contacts(retained,collision_fixed,fixed_groups,remaining,supports,support_bounds,hull)
			var changed := 0.0
			for index in range(1,retained.size()-1): changed = maxf(changed,before[index].distance_squared_to(retained[index]))
			if changed<.000025*.000025: break
		reference_overrun = maxf(0,_material_step(retained,prior,prior_distances,offset)-FREE_MATERIAL_SPEED*dt)
	var retained_done := Time.get_ticks_usec()
	if needs_reference:
		_bound_material(curve,retained,prior,prior_distances,offset,transported,dt)
		contact_context = "closure"
		for sweep in 2:
			var before := curve.duplicate()
			_contacts(curve,collision_fixed,fixed_groups,remaining,supports,support_bounds,hull)
			var changed := 0.0
			for index in range(1,curve.size()-1): changed = maxf(changed,before[index].distance_squared_to(curve[index]))
			if changed<.000025*.000025: break
	rest_length = _length(curve)
	last_rest_error = 0.0
	floor_material_rate = (transported-rest_length)/maxf(dt,.000001)
	history = curve
	full_history = fixed.duplicate()
	full_history.append_array(curve.slice(1))
	previous_cockpit = cockpit_length
	previous_fixed_length = fixed_length
	previous_holder = helper
	last_revision = actor.sheet_study.manual_revision
	last_timings = {"prepare_ms":(prepared-began)/1000.0,"retained_ms":(retained_done-contacts_done)/1000.0,"contact_ms":(contacts_done-prepared)/1000.0,"bound_ms":(Time.get_ticks_usec()-retained_done)/1000.0,"reference_used":needs_reference}
	return full_history

func _bound_material(curve: PackedVector3Array,reference: PackedVector3Array,prior: PackedVector3Array,distances: PackedFloat32Array,offset: float,transported: float,dt: float) -> bool:
	if _within_budget(curve,prior,distances,offset,transported,dt): return false
	var candidate := curve.duplicate()
	var low := 0.0
	var high := 1.0
	for iteration in 9:
		var fraction := (low+high)*.5
		for index in range(1,curve.size()-1): curve[index] = reference[index].lerp(candidate[index],fraction)
		if _within_budget(curve,prior,distances,offset,transported,dt): low = fraction
		else: high = fraction
	for index in range(1,curve.size()-1): curve[index] = reference[index].lerp(candidate[index],low)
	return true

func _within_budget(curve: PackedVector3Array,prior: PackedVector3Array,distances: PackedFloat32Array,offset: float,transported: float,dt: float) -> bool:
	return absf(transported-_length(curve))<=FREE_MATERIAL_SPEED*dt and _material_step(curve,prior,distances,offset)<=FREE_MATERIAL_SPEED*dt

func _material_step(curve: PackedVector3Array,prior: PackedVector3Array,distances: PackedFloat32Array,offset: float) -> float:
	var travelled := 0.0
	var largest := 0.0
	var cursor := 0
	for index in curve.size()-1:
		var length := curve[index].distance_to(curve[index+1])
		for half in 2:
			var target := offset+travelled+length*half*.5
			while cursor<prior.size()-2 and distances[cursor+1]<target: cursor += 1
			var previous := prior[cursor].lerp(prior[cursor+1],clampf((target-distances[cursor])/maxf(.0000001,distances[cursor+1]-distances[cursor]),0,1))
			largest = maxf(largest,curve[index].lerp(curve[index+1],half*.5).distance_to(previous))
		travelled += length
	return maxf(largest,curve[-1].distance_to(_point_at(prior,distances,offset+travelled)))

func _contacts(curve: PackedVector3Array,fixed: PackedVector3Array,fixed_groups: Array,remaining: PackedFloat32Array,supports: Array,support_bounds: Array,hull: MeshInstance3D) -> void:
	var before_length := _length(curve)
	var travelled := 0.0
	var nearby_supports := []
	var nearby_fixed := []
	for first in range(0,curve.size()-1,8):
		var group_bounds := _group_bounds(curve,first,mini(first+8,curve.size()-1)).grow(.05)
		var support_indices := PackedInt32Array()
		for index in supports.size():
			if group_bounds.intersects(support_bounds[index]): support_indices.append(index)
		nearby_supports.append(support_indices)
		var groups := []
		for group: Array in fixed_groups:
			if group_bounds.intersects(group[2]): groups.append(group)
		nearby_fixed.append(groups)
	for index in curve.size()-1:
		var bounds := _bounds(curve[index],curve[index+1]).grow(.025)
		# Preserve the actual holder's outlet channel. Beyond that short
		# exit, the loose span stays outside the finger group's convex shell
		# instead of entering concave gaps that disappear as the hand closes.
		if travelled>.035:
			for shell: Array in hand_shells:
				_project_link(curve,index,shell[0],shell[1],shell[2])
		for support_index: int in nearby_supports[index/8]:
			if not bounds.intersects(support_bounds[support_index]): continue
			var support: Array = supports[support_index]
			var a := curve[index]
			var b := curve[index+1]
			_project_link(curve,index,support[0],support[1],support[2]+.003)
			if trace_enabled: _note_push(curve,index,a,b,"support "+str(support_index))
		for group: Array in nearby_fixed[index/8]:
			if not bounds.intersects(group[2]): continue
			for segment in range(group[0],group[1]):
				var a := curve[index]
				var b := curve[index+1]
				_project_free_bend(curve,index,fixed[segment],fixed[segment+1],travelled+remaining[segment+1])
				if trace_enabled: _note_push(curve,index,a,b,"held "+str(segment))
		if index>0: curve[index].y = maxf(curve[index].y,hull.cockpit_floor_y_at(curve[index].x,curve[index].z)+.007)
		travelled += curve[index].distance_to(curve[index+1])
	var supported_length := _length(curve)
	_clear_free_self_contact(curve)
	var self_length := _length(curve)
	_clear_floor_entry(curve)
	contact_stretch.supports += supported_length-before_length
	contact_stretch.self += self_length-supported_length
	contact_stretch.floor += _length(curve)-self_length
	for index in range(1,curve.size()-1):
		curve[index].y = maxf(curve[index].y,hull.cockpit_floor_y_at(curve[index].x,curve[index].z)+.007)

func _note_push(curve: PackedVector3Array,index: int,a: Vector3,b: Vector3,kind: String) -> void:
	var amount := maxf(a.distance_to(curve[index]),b.distance_to(curve[index+1]))
	if amount<=contact_stretch.pushes.get(contact_context,{}).get("metres",0.0): return
	contact_stretch.pushes[contact_context] = {"metres":amount,"kind":kind,"index":index,"a":str(a),"b":str(b)}

func _clear_free_self_contact(curve: PackedVector3Array) -> void:
	var groups := _groups(curve)
	var travelled := 0.0
	var material := PackedFloat32Array([0.0])
	for index in curve.size()-1:
		var before_start := curve[index]
		var before_end := curve[index+1]
		var search := _bounds(before_start,before_end).grow(.030)
		for group: Array in groups:
			if group[0]>=index-1: break
			if not search.intersects(group[2]): continue
			for segment in range(group[0],mini(group[1],index-1)):
				_project_link(curve,index,curve[segment],curve[segment+1],.009,0.0,travelled-material[segment+1])
		if index>0 and curve[index-1].distance_to(curve[index])>.010 and curve[index].distance_to(curve[index+1])>.010:
			_project_link(curve,index,curve[index-1],curve[index].move_toward(curve[index-1],.010),.009,.010)
		travelled += curve[index].distance_to(curve[index+1])
		material.append(travelled)
		# Empty broad-phase queries cannot change these boxes. Rebuilding
		# sixteen point bounds for every untouched link dominated each pass.
		if curve[index]==before_start and curve[index+1]==before_end: continue
		for group_index in range(maxi(0,(index-1)/8),mini(groups.size(),(index+1)/8+1)):
			var group: Array = groups[group_index]
			group[2] = _group_bounds(curve,group[0],group[1])

func _project_free_bend(curve: PackedVector3Array,index: int,a: Vector3,b: Vector3,gap: float) -> void:
	var first := curve[index]
	var last := curve[index+1]
	_project_link(curve,index,a,b,.010,0.0,gap)
	var first_shift := curve[index]-first
	var last_shift := curve[index+1]-last
	if first_shift.length_squared()+last_shift.length_squared()<.000000000001: return
	# A contact reaction bends a short span, not just one sampled vertex.
	# Isolated endpoint corrections otherwise accumulate saw-tooth length
	# while the loaded strand slides past its hanging neighbour.
	for direction in [-1,1]:
		var shift := first_shift if direction<0 else last_shift
		if shift.length_squared()<.000000000001: continue
		var previous := index if direction<0 else index+1
		var distance := 0.0
		for step in range(1,13):
			var at: int = previous+direction
			if at<=0 or at>=curve.size()-1: break
			distance += curve[at].distance_to(curve[previous])
			if distance>=.065: break
			curve[at] += shift*pow(1-distance/.065,2)
			previous = at

func _clear_floor_entry(curve: PackedVector3Array) -> void:
	if floor_entry.size()<2: return
	var reverse := curve.duplicate()
	reverse.reverse()
	var travelled := 0.0
	for index in curve.size()-1:
		var bounds := _bounds(reverse[index],reverse[index+1]).grow(.012)
		if bounds.intersects(floor_bounds):
			for segment in floor_entry.size()-1:
				if not bounds.intersects(floor_entry_bounds[segment]): continue
				_project_link(reverse,index,floor_entry[segment+1],floor_entry[segment],.010,0.0,travelled+floor_entry_distances[segment])
		travelled += reverse[index].distance_to(reverse[index+1])
	for index in curve.size(): curve[index] = reverse[reverse.size()-1-index]

func _distances(path: PackedVector3Array) -> PackedFloat32Array:
	var result := PackedFloat32Array([0.0])
	for index in path.size()-1: result.append(result[-1]+path[index].distance_to(path[index+1]))
	return result

func _point_at(path: PackedVector3Array,distances: PackedFloat32Array,distance: float) -> Vector3:
	if distance<=0: return path[0]
	if distance>=distances[-1]: return path[-1]
	var low := 0
	var high := path.size()-1
	while high-low>1:
		var middle := (low+high)/2
		if distances[middle]<distance: low = middle
		else: high = middle
	return path[low].lerp(path[high],(distance-distances[low])/maxf(.0000001,distances[high]-distances[low]))

func _simplify(path: PackedVector3Array,tolerance: float) -> PackedVector3Array:
	if path.size()<3: return path
	var keep := PackedByteArray()
	keep.resize(path.size())
	keep[0] = 1
	keep[-1] = 1
	var stack := [Vector2i(0,path.size()-1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var largest := tolerance*tolerance
		var farthest := -1
		for index in range(span.x+1,span.y):
			var closest := Geometry3D.get_closest_point_to_segment(path[index],path[span.x],path[span.y])
			var error := path[index].distance_squared_to(closest)
			if error>largest:
				largest = error
				farthest = index
		if farthest<0: continue
		keep[farthest] = 1
		stack.append(Vector2i(span.x,farthest))
		stack.append(Vector2i(farthest,span.y))
	var result := PackedVector3Array()
	for index in path.size():
		if keep[index]: result.append(path[index])
	return result

func _densify(path: PackedVector3Array,maximum: float) -> PackedVector3Array:
	var result := PackedVector3Array([path[0]])
	var travelled := 0.0
	for index in path.size()-1:
		var length := path[index].distance_to(path[index+1])
		var spacing := .009 if travelled<.12 else maximum
		var count := maxi(1,ceili(length/spacing))
		for step in range(1,count+1): result.append(path[index].lerp(path[index+1],step/float(count)))
		travelled += length
	return result
