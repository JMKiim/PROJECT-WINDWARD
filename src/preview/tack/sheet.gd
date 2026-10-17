extends "res://src/preview/land_drill_cockpit_sheet.gd"
## Finalized hands are inputs. This display never changes a bone or ledger.
var maneuver: RefCounted
var display_budget := NAN
var floor_cap_signature := []
var floor_caps := []
var floor_polygon := PackedVector2Array()
var floor_winding := 0
var floor_reference := PackedVector2Array()
var floor_reference_signature := []
var floor_sign := 1.0
const CORRIDOR := preload("res://src/preview/tack/floor_corridor.gd")
const FLOOR := preload("res://src/preview/tack/floor_support.gd")
const ACTUAL_CORRIDOR := preload("res://src/preview/tack/actual_floor_corridor.gd")
var actual_corridor: RefCounted=ACTUAL_CORRIDOR.new()
const ROD := preload("res://src/preview/tack/rod_rope_contact.gd")
var rod_unresolved := []
func _place_end(endpoint: Vector3) -> PackedVector3Array:
	var baseline: PackedVector3Array=super._place_end(endpoint)
	if not crossing(): return baseline
	var caps := _caps([["Hips","UpperChest",.164],["LeftUpperLeg","LeftLowerLeg",.104],["RightUpperLeg","RightLowerLeg",.104],["LeftLowerLeg","LeftFoot",.080],["RightLowerLeg","RightFoot",.080],["LeftFoot","LeftToes",.066],["RightFoot","RightToes",.066]])
	var joint: Vector3=actor.joint_boat()
	caps.append([joint,joint+maneuver.result.axis*actor.extension_span,.018,"Extension"])
	return preload("res://src/preview/tack/stopper_orientation.gd").place(baseline,endpoint,hull,caps)
func _prepare_floor() -> void:
	var signature := [maneuver.progress,maneuver.steering]
	if signature==floor_cap_signature: return
	floor_caps=_caps([["Hips","UpperChest",.176],["LeftUpperLeg","LeftLowerLeg",.116],["RightUpperLeg","RightLowerLeg",.116],["LeftLowerLeg","LeftFoot",.092],["RightLowerLeg","RightFoot",.092],["LeftFoot","LeftToes",.078],["RightFoot","RightToes",.078]])
	floor_polygon=CORRIDOR.outline(floor_caps,hull,false)
	# One floor-supported entry in front of the loose pile. Replacing a
	# boundary tangent separately for every pile cut changes topology and
	# makes the material inverse discontinuous. This is a display corridor,
	# not an extra physical fairlead or a change to the logical sheet.
	var entry := Vector3(0,0,.25)
	entry.y=hull.cockpit_floor_y_at(entry.x,entry.z)+RADIUS+.002
	actual_corridor.setup(hull,floor_caps,floor_polygon,entry)
	floor_cap_signature=signature
var fall_ms := 0.0
var route_ms := 0.0
var floor_ms := 0.0
var floor_evaluations := 0
func _fall_path(outlet: Vector3,touch: Vector3,caps: Array) -> PackedVector3Array:
	if not crossing(): return super._fall_path(outlet,touch,caps)
	var started := Time.get_ticks_usec()
	var result := preload("res://src/preview/tack/gravity_strand.gd").fall(outlet,touch,caps,hull,_away())
	result=FLOOR.path(result,hull)
	var supported := ROD.route(result,actor.joint_boat(),maneuver.result.axis,actor.extension_span,caps,true)
	result=supported.path
	rod_unresolved.append_array(supported.unresolved)
	fall_ms=(Time.get_ticks_usec()-started)/1000.0
	return result
func adopt(source: RefCounted,controller: RefCounted) -> void:
	hull=source.hull
	actor=source.actor
	ground=source.ground
	arc=source.arc
	end_shape=source.end_shape
	end_path=source.end_path
	maneuver=controller
func crossing() -> bool: return maneuver!=null and maneuver.phase=="CROSS"
func build(cockpit_metres: float) -> Dictionary:
	var desired := display_budget if crossing() and is_finite(display_budget) else cockpit_metres
	var result: Dictionary=super.build(desired)
	if result.get("valid",false):
		result.logical_cockpit_metres=cockpit_metres
		result.display_budget_metres=desired
		result.presentation_extra_metres=desired-cockpit_metres
		result.display_error_m=STOPPER.length_of(result.path)-cockpit_metres
	return result
func _prefix() -> PackedVector3Array:
	if not crossing() or maneuver.result.is_empty(): return super._prefix()
	var u: float=maneuver.progress
	var owner: Dictionary=maneuver.result.ownership
	var old_sheet := PackedVector3Array()
	var new_sheet := PackedVector3Array()
	for point in CONTACT.sheet_channel("Left").slice(1,4): old_sheet.append(actor.bone_pose_boat("LeftHand")*point)
	for point in CONTACT.sheet_channel("Right").slice(1,4): new_sheet.append(actor.bone_pose_boat("RightHand")*point)
	var helper := CONTACT.helper_channel(actor.bone_pose_boat("RightHand"),"Right")
	var old_weight: float=owner.old_sheet_weight
	var helper_weight: float=owner.helper_weight
	var new_weight: float=owner.new_sheet_weight
	var anchor: Vector3=helper[0].lerp(new_sheet[0],smoothstep(.92,.96,u))
	var path := PackedVector3Array([actor.sheet_study.block_anchor])
	grasp_knots=PackedInt32Array([0])
	for point in old_sheet: path.append(anchor.lerp(point,old_weight))
	var helper_base: Vector3=old_sheet[-1] if u<.5 else new_sheet[0]
	for point in helper: path.append(helper_base.lerp(point,helper_weight))
	var new_base: Vector3=path[-1]
	for point in new_sheet: path.append(new_base.lerp(point,new_weight))
	if u<.20: grasp_knots.append_array(PackedInt32Array([1,2,3]))
	if helper_weight>=.999999: grasp_knots.append_array(PackedInt32Array([4,5,6]))
	if new_weight>=.999999: grasp_knots.append_array(PackedInt32Array([7,8,9]))
	# Zero-weight guides collapse onto the actual grasp. They are not
	# independent free vertices that contact projection may push away.
	var compact := PackedVector3Array([path[0]])
	var fixed := PackedInt32Array([0])
	for index in range(1,path.size()):
		if path[index].distance_squared_to(compact[-1])>.000000000001: compact.append(path[index])
		var target: int=compact.size()-1
		if grasp_knots.has(index) and not fixed.has(target): fixed.append(target)
	# The exit guide is an internal hand-display datum,not another bone.
	# At the normal endpoint it can lie inside the adjacent tiller tube.
	# Use the approved internal-grip freedom for this outlet only; retain
	# the actual grasp centre,all joint poses and the unchanged normal mode.
	var joint: Vector3=actor.joint_boat()
	var tip: Vector3=joint+maneuver.result.axis*actor.extension_span
	var nearest := Geometry3D.get_closest_point_to_segment(compact[-1],joint,tip)
	var radial: Vector3=compact[-1]-nearest
	if radial.length()<.021 and radial.length()>.000001:
		compact[-1]=nearest+radial.normalized()*.021
	grasp_knots=fixed
	return compact
func _away() -> Vector3:
	if not crossing(): return actor.from_port(Vector3.RIGHT)
	var t := smoothstep(.64,.92,maneuver.progress)
	return Vector3(cos(PI*t),0,-sin(PI*t))
func _touch_point(outlet: Vector3) -> Vector3:
	if not crossing(): return super._touch_point(outlet)
	_prepare_floor()
	var x := clampf(outlet.x,-.55,.55)
	var z := clampf(outlet.z,.25,1.30)
	var point := Vector3(x,hull.cockpit_floor_y_at(x,z)+RADIUS+.002,z)
	var caps: Array=floor_caps
	for pass_index in 4:
		for cap in caps:
			var near := Geometry3D.get_closest_point_to_segment(point,cap[0],cap[1])
			var influence: float=1-smoothstep(float(cap[2]),float(cap[2])+.060,point.distance_to(near))
			var front: float=minf(cap[0].z,cap[1].z)-float(cap[2])-.012
			point.z-=maxf(0,point.z-front)*influence
		point.y=hull.cockpit_floor_y_at(point.x,point.z)+RADIUS+.002
	var xz := CORRIDOR.outside(Vector2(point.x,point.z),floor_polygon)
	return Vector3(xz.x,hull.cockpit_floor_y_at(xz.x,xz.y)+RADIUS+.002,xz.y)
func _surface_line(a: Vector3,b: Vector3) -> PackedVector3Array:
	if not crossing(): return super._surface_line(a,b)
	_prepare_floor()
	return actual_corridor.path(a,b)
func _needed_floor(touch: Vector3,coordinate: float) -> Dictionary:
	floor_evaluations+=1
	var sample := _at(coordinate)
	_prepare_floor()
	var surface: Dictionary=actual_corridor.measure(touch,sample.point)
	var raised: Vector3=surface.end
	# The rendered surface line lifts an interpolated pile point. Include
	# that actual join,not the unlifted partial arc used by the old inverse.
	return {"sample":sample,"length":arc[sample.index]+raised.distance_to(ground[sample.index])+surface.length}
func _floor_parameter(touch: Vector3,available: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := _floor_parameter_impl(touch,available)
	floor_ms+=(Time.get_ticks_usec()-started)/1000.0
	return result
func _floor_parameter_impl(touch: Vector3,available: float) -> Dictionary:
	if not crossing(): return super._floor_parameter(touch,available)
	var low := 0.0
	var high: float=minf(arc[-1],available)
	var below: float=_needed_floor(touch,low).length-available
	var above: float=_needed_floor(touch,high).length-available
	var previous_side := 0
	for iteration in 24:
		var coordinate: float=(low+high)*.5
		if above>0 and below<0 and above-below>.000000001:
			coordinate=clampf((low*above-high*below)/(above-below),low,high)
		var measured := _needed_floor(touch,coordinate)
		var value: float=measured.length-available
		if absf(value)<=.000002: return measured.sample
		if value<0:
			low=coordinate
			below=value
			if previous_side==-1: above*=.5
			previous_side=-1
		else:
			high=coordinate
			above=value
			if previous_side==1: below*=.5
			previous_side=1
	return _at((low+high)*.5)
func _route_prefix(path: PackedVector3Array,caps: Array) -> PackedVector3Array:
	if not crossing(): return super._route_prefix(path,caps)
	var started := Time.get_ticks_usec()
	rod_unresolved.clear()
	var body_caps := caps.duplicate()
	caps=caps.duplicate()
	var joint: Vector3=actor.joint_boat()
	var axis: Vector3=maneuver.result.axis
	caps.append([joint+axis*.03,joint+axis*actor.extension_span,.015,"Extension"])
	const DIVISIONS := 4
	var points := PackedVector3Array([path[0]])
	for segment in path.size()-1:
		for division in range(1,DIVISIONS+1): points.append(path[segment].lerp(path[segment+1],division/float(DIVISIONS)))
	var bounds := []
	for cap in caps:
		var pad := Vector3.ONE*(float(cap[2])+.022)
		bounds.append([cap[0].min(cap[1])-pad,cap[0].max(cap[1])+pad])
	var away := _away()
	for index in range(1,points.size()):
		if index%DIVISIONS==0 and grasp_knots.has(index/DIVISIONS): continue
		for cap in caps:
			var near := Geometry3D.get_closest_point_to_segment(points[index],cap[0],cap[1])
			var influence := 1-smoothstep(float(cap[2])+.02,float(cap[2])+.08,points[index].distance_to(near))
			var support: float=maxf(cap[0].dot(away),cap[1].dot(away))+float(cap[2])+.022
			points[index]+=away*maxf(0,support-points[index].dot(away))*influence
		points[index].y=maxf(points[index].y,hull.cockpit_floor_y_at(points[index].x,points[index].z)+RADIUS+.002)
	for iteration in 16:
		var changed := false
		for segment in points.size()-1:
			var free_a: bool=segment%DIVISIONS!=0 or not grasp_knots.has(segment/DIVISIONS)
			var free_b: bool=(segment+1)%DIVISIONS!=0 or not grasp_knots.has((segment+1)/DIVISIONS)
			if not free_a and not free_b: continue
			var low := points[segment].min(points[segment+1])
			var high := points[segment].max(points[segment+1])
			for cap_index in caps.size():
				var cap_low: Vector3=bounds[cap_index][0]
				var cap_high: Vector3=bounds[cap_index][1]
				if low.x>cap_high.x or high.x<cap_low.x or low.y>cap_high.y or high.y<cap_low.y or low.z>cap_high.z or high.z<cap_low.z: continue
				var cap: Array=caps[cap_index]
				var pair := Geometry3D.get_closest_points_between_segments(points[segment],points[segment+1],cap[0],cap[1])
				var delta := pair[0]-pair[1]
				var edge := points[segment+1]-points[segment]
				var fraction := clampf((pair[0]-points[segment]).dot(edge)/maxf(.0000000001,edge.length_squared()),0,1)
				var depth: float=float(cap[2])+.016-delta.length()
				if depth<=.00001: continue
				var a: float=1-fraction if free_a else 0
				var b: float=fraction if free_b else 0
				var denominator := a*a+b*b
				if denominator<.0000001: continue
				var shift: Vector3=(delta.normalized() if delta.length()>.000001 else away)*depth/denominator
				if shift.length()>.04: shift=shift.normalized()*.04
				points[segment]+=shift*a
				points[segment+1]+=shift*b
				low=points[segment].min(points[segment+1])
				high=points[segment].max(points[segment+1])
				changed=true
		for index in range(1,points.size()):
			if index%DIVISIONS==0 and grasp_knots.has(index/DIVISIONS): continue
			var floor_y: float=hull.cockpit_floor_y_at(points[index].x,points[index].z)+RADIUS+.002
			if points[index].y<floor_y: points[index].y=floor_y; changed=true
		if not changed: break
	var fixed := []
	for index in points.size(): fixed.append(index==0 or index==points.size()-1 or index%DIVISIONS==0 and grasp_knots.has(index/DIVISIONS))
	# Contact projection can leave a free corner suspended after it has
	# cleared the obstacle. Remove only shortcuts independently clear of
	# every capsule; actual hand/block knots remain pinned.
	for pass_index in 3:
		var shorter := PackedVector3Array([points[0]])
		var kept := [true]
		for index in range(1,points.size()):
			var needed: bool=fixed[index] or index==points.size()-1
			if not needed:
				for cap in caps:
					var pair := Geometry3D.get_closest_points_between_segments(shorter[-1],points[index+1],cap[0],cap[1])
					if pair[0].distance_to(pair[1])<float(cap[2])+.012: needed=true; break
				if not needed:
					var distance: float=shorter[-1].distance_to(points[index+1])
					var steps := maxi(2,ceili(distance/.008))
					for part in range(1,steps):
						var p: Vector3=shorter[-1].lerp(points[index+1],part/float(steps))
						if p.y<hull.cockpit_floor_y_at(p.x,p.z)+RADIUS+.001: needed=true; break
			if needed: shorter.append(points[index]); kept.append(fixed[index])
		if shorter.size()==points.size(): break
		points=shorter
		fixed=kept
	points=FLOOR.path(points,hull)
	var supported := ROD.route(points,actor.joint_boat(),maneuver.result.axis,actor.extension_span,body_caps)
	rod_unresolved.append_array(supported.unresolved)
	route_ms+=(Time.get_ticks_usec()-started)/1000.0
	return supported.path
