extends "res://src/boat/mainsheet_material_lead.gd"

## Diagnostic material-coordinate chain. One solve owns length, motion and
## finite contact; no post-solve unconstrained contact closure is appended.
const SPACING := .025
func _spacing() -> float: return SPACING
var surfaces := preload("res://src/preview/land_drill/support/land_drill_anatomical_material_candidate.gd").new()
var link_rest := PackedFloat32Array()
var material_offsets := PackedFloat32Array()
var centres := PackedVector3Array()

func _target_length(retained: float,transported: float,fixed: PackedVector3Array,ground: Vector3,_actor: Node3D,dt: float,cold: bool) -> float:
	var target := retained
	if not cold: target=clampf(target,transported-FREE_MATERIAL_SPEED*dt*.75,transported+FREE_MATERIAL_SPEED*dt*.75)
	return maxf(target,fixed[-1].distance_to(ground)+.00001)

func _remember_target(_target: float) -> void: pass
func _prepare_contact_frame(_supports: Array) -> void: pass
func _finish_contact_frame(_supports: Array) -> void: pass
func _gravity_distance(dt: float,_cold: bool) -> float: return .6*dt
func _cold_first(start: Vector3,tangent: Vector3,down: Vector3) -> Vector3: return start+tangent*.012+down*.055
func _cold_second(ground: Vector3,down: Vector3) -> Vector3: return ground-down*.12
func _bound_temporal(curve: PackedVector3Array,_prior: PackedVector3Array,_distances: PackedFloat32Array,_offset: float,dt: float) -> void:
	for index in range(1,curve.size()-1): curve[index]=centres[index]+(curve[index]-centres[index]).limit_length(FREE_MATERIAL_SPEED*dt)

func contact_prefix(held: PackedVector3Array,actor: Node3D) -> PackedVector3Array:
	return surfaces.contact_prefix(held,actor)

func build(prefix: PackedVector3Array,ground: Vector3,actor: Node3D,hull: MeshInstance3D,rig_path: PackedVector3Array=PackedVector3Array(),expanded_contacts := false) -> PackedVector3Array:
	if last_revision==actor.sheet_study.manual_revision and not full_history.is_empty(): return full_history
	var began := Time.get_ticks_usec()
	floor_samples.clear()
	hand_shells.clear()
	contact_stretch={"supports":0.0,"self":0.0,"floor":0.0,"pushes":{}}
	var count: int=actor.sheet_study.MANUAL_HELD_SEGMENTS+1
	var physical := contact_prefix(prefix.slice(0,count),actor)
	var fixed := physical.slice(0,count+2)
	var fixed_length := _length(fixed)
	var dt: float=clampf(actor.sheet_study.manual_delta,0,.067)
	var cold := full_history.is_empty()
	var feed := 0.0 if cold else cockpit_length-previous_cockpit
	var old := full_history.duplicate()
	var floor_distance := 0.0
	if not cold:
		for index in range(1,floor_history.size()):
			old.append(floor_history[index])
			floor_distance+=floor_history[index-1].distance_to(floor_history[index])
			if floor_distance>.5: break
	var old_distances := _distances(old) if not cold else PackedFloat32Array()
	var offset := fixed_length-feed
	var transported := _length(full_history)+feed-fixed_length if not cold else 0.0
	var retained := PackedVector3Array()
	if cold:
		var start := fixed[-1]
		var tangent := (fixed[-1]-fixed[-2]).normalized()
		var down: Vector3=actor.sheet_study.gravity_boat()
		var first := _cold_first(start,tangent,down)
		var second := _cold_second(ground,down)
		for index in 65:
			var t := index/64.0
			var u := 1-t
			retained.append(start*u*u*u+first*3*u*u*t+second*3*u*t*t+ground*t*t*t)
	else:
		retained.append(_point_at(old,old_distances,offset))
		for index in full_history.size():
			if old_distances[index]>offset+.000001: retained.append(full_history[index])
		if retained.size()<2: retained.append(ground)
		var distances := _distances(retained)
		var attachment := fixed[-1]-retained[0]
		for index in retained.size(): retained[index]+=attachment*(1-distances[index]/maxf(distances[-1],.000001))
		retained[0]=fixed[-1]
		retained[-1]=ground
	var retained_distances := _distances(retained)
	var target := _target_length(retained_distances[-1],transported,fixed,ground,actor,dt,cold)
	material_offsets=PackedFloat32Array([0.0])
	# The interior grid belongs to absolute rope material, not visual indices.
	var origin := fixed_length-cockpit_length
	var spacing := _spacing()
	var at := (floorf(origin/spacing)+1)*spacing-origin
	while at<target-.002:
		if at>.002: material_offsets.append(at)
		at+=spacing
	material_offsets.append(target)
	link_rest.clear()
	centres.clear()
	var curve := PackedVector3Array()
	for distance in material_offsets:
		curve.append(_point_at(retained,retained_distances,distance*retained_distances[-1]/target))
		centres.append(_point_at(old,old_distances,offset+distance) if not cold else curve[-1])
	for index in material_offsets.size()-1: link_rest.append(material_offsets[index+1]-material_offsets[index])
	var down: Vector3=actor.sheet_study.gravity_boat()
	var gravity_distance := _gravity_distance(dt,cold)
	for index in range(1,curve.size()-1): curve[index]+=down*gravity_distance
	var supports: Array=surfaces.anatomy.duplicate()
	var span := _group_bounds(curve,0,curve.size()-1).grow(.15)
	for index in rig_path.size()-1:
		if span.intersects(_bounds(rig_path[index],rig_path[index+1])): supports.append([rig_path[index],rig_path[index+1],.007])
	var support_bounds := []
	for support in supports: support_bounds.append(_bounds(support[0],support[1]).grow(support[2]+.004))
	_prepare_contact_frame(supports)
	var collision_fixed := _simplify(fixed,.0001)
	var groups := _groups(collision_fixed)
	held_link_bounds.clear()
	for index in collision_fixed.size()-1: held_link_bounds.append(_bounds(collision_fixed[index],collision_fixed[index+1]).grow(.010))
	var remaining := PackedFloat32Array()
	remaining.resize(collision_fixed.size())
	for index in range(collision_fixed.size()-2,-1,-1): remaining[index]=remaining[index+1]+collision_fixed[index].distance_to(collision_fixed[index+1])
	var prepared := Time.get_ticks_usec()
	for iteration in (24 if cold else 12):
		var before := curve.duplicate()
		_project_chain_lengths(curve)
		if not cold: _bound_temporal(curve,old,old_distances,offset,dt)
		contact_context="coupled"
		_contacts(curve,collision_fixed,groups,remaining,supports,support_bounds,hull)
		last_pass_count=iteration+1
		var change := 0.0
		for index in range(1,curve.size()-1): change=maxf(change,curve[index].distance_squared_to(before[index]))
		if change<1e-10: break
	rest_length=_length(curve)
	_remember_target(target)
	_finish_contact_frame(supports)
	floor_material_rate=0.0 if cold else (transported-rest_length)/maxf(dt,.000001)
	reference_overrun=0.0 if cold else maxf(0,_material_step(curve,old,old_distances,offset)-FREE_MATERIAL_SPEED*dt)
	var residual := 0.0
	for index in link_rest.size(): residual=maxf(residual,absf(curve[index].distance_to(curve[index+1])-link_rest[index]))
	contact_stretch["maximum_link_residual"]=residual
	contact_stretch["material_step_mm"]=0.0 if cold else _material_step(curve,old,old_distances,offset)*1000
	history=curve
	full_history=fixed.duplicate()
	full_history.append_array(curve.slice(1))
	previous_cockpit=cockpit_length
	previous_fixed_length=fixed_length
	previous_holder=actor.sheet_control.regrip.time>=.8 and actor.sheet_control.regrip.time<2
	last_revision=actor.sheet_study.manual_revision
	last_timings={"prepare_ms":(prepared-began)/1000.0,"contact_ms":(Time.get_ticks_usec()-prepared)/1000.0,"cold":cold,"points":curve.size()}
	return full_history

func _project_chain_lengths(curve: PackedVector3Array) -> void:
	var count := link_rest.size()
	for iteration in 3:
		var directions := PackedVector3Array()
		var diagonal := PackedFloat64Array()
		var off_diagonal := PackedFloat64Array()
		var rhs := PackedFloat64Array()
		var largest := 0.0
		for index in count:
			var delta := curve[index+1]-curve[index]
			var length := delta.length()
			directions.append(delta/maxf(length,.0000001))
			var error := length-link_rest[index]
			largest=maxf(largest,absf(error))
			diagonal.append((0.0 if index==0 else 1.0)+(0.0 if index==count-1 else 1.0)+.000001)
			rhs.append(-error)
		if largest<.000002: return
		for index in count-1: off_diagonal.append(-directions[index].dot(directions[index+1]))
		for index in range(1,count):
			var factor := off_diagonal[index-1]/maxf(diagonal[index-1],.0000001)
			diagonal[index]-=factor*off_diagonal[index-1]
			rhs[index]-=factor*rhs[index-1]
		var multipliers := PackedFloat64Array()
		multipliers.resize(count)
		multipliers[-1]=rhs[-1]/maxf(diagonal[-1],.0000001)
		for index in range(count-2,-1,-1): multipliers[index]=(rhs[index]-off_diagonal[index]*multipliers[index+1])/maxf(diagonal[index],.0000001)
		for index in range(1,curve.size()-1): curve[index]+=(directions[index-1]*multipliers[index-1]-directions[index]*multipliers[index]).limit_length(.025)
