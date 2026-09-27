extends RefCounted

## Exact displayed mainsheet boundary. This solves boom geometry, not a hand
## pose or a material transfer. Infeasible requests restore the previous rig.
const MAX_YAW := deg_to_rad(175)
const MIN_PITCH := deg_to_rad(-15)
const MAX_PITCH := deg_to_rad(18)
const LENGTH_TOLERANCE := .00005
const DERIVATIVE_STEP := .0015
const HANGING := preload("res://src/boat/rig_hanging_sheet.gd")
const SUPPORT := preload("res://src/boat/hull_rope_support.gd")
var rig: Node3D
var evaluations := 0
var hull_support: RefCounted
var support_key := []
var drape_key := []
var drape_boundary := PackedVector3Array()
var drape_result := {}
var drape_solves := 0
var drape_cache_hits := 0
var spatial_guide_state: RefCounted

func _init(value: Node3D) -> void:
	rig=value

func angles() -> Vector2:
	var axis: Vector3=rig.boom_pivot.basis.z
	return Vector2(atan2(axis.x,axis.z),atan2(-axis.y,Vector2(axis.x,axis.z).length()))

func _length(yaw: float,pitch: float) -> float:
	evaluations += 1
	rig.set_angles(yaw,pitch,false)
	return rig.length_metres()

func minimum_yaw() -> float:
	# The old lower angle aligns the boom with a block at the fixed corner.
	# A relocated block must use its own alignment, not that legacy corner.
	if rig.traveller_override.is_finite():
		return absf(atan2(rig.traveller_override.x,rig.traveller_override.z-rig.boom_pivot.position.z))
	return rig.minimum_yaw

func fit(target: float,pitch: float,display := true,tolerance := LENGTH_TOLERANCE) -> Dictionary:
	if not is_finite(target) or not is_finite(pitch) or not is_finite(tolerance) or tolerance<=0 or tolerance>LENGTH_TOLERANCE or target<=0 or pitch<MIN_PITCH or pitch>MAX_PITCH:
		return {"valid":false,"reason":"outside independent rig request bounds"}
	var previous := angles()
	var side := -1.0 if previous.x<0 else 1.0
	var low := minimum_yaw()
	var high := MAX_YAW
	evaluations=0
	var low_length := _length(low*side,pitch)
	var high_length := _length(high*side,pitch)
	if not is_finite(low_length) or not is_finite(high_length) or low_length>=high_length or target<low_length-tolerance or target>high_length+tolerance:
		rig.set_angles(previous.x,previous.y,display)
		return {"valid":false,"reason":"requested pitch cannot retain this sheet allocation","minimum":low_length,"maximum":high_length,"target":target,"evaluations":evaluations}
	var candidate := clampf(absf(previous.x),low,high)
	var measured := 0.0
	for iteration in 24:
		measured=_length(candidate*side,pitch)
		if absf(measured-target)<=tolerance*.5: break
		if measured<target:
			low=candidate
			low_length=measured
		else:
			high=candidate
			high_length=measured
		var next := lerpf(low,high,(target-low_length)/maxf(.000001,high_length-low_length))
		candidate=clampf(next,low+(high-low)*.001,high-(high-low)*.001)
	var valid := is_finite(measured) and absf(measured-target)<=tolerance
	if not valid:
		rig.set_angles(previous.x,previous.y,display)
		return {"valid":false,"reason":"independent rig did not converge","error_metres":measured-target,"evaluations":evaluations}
	if display: rig.set_angles(candidate*side,pitch,true)
	return {"valid":true,"yaw":candidate*side,"pitch":pitch,"error_metres":measured-target,"evaluations":evaluations,"target":target,"opening":rig.opening}

func fit_pitch(target: float,yaw: float,display := false,tolerance := LENGTH_TOLERANCE) -> Dictionary:
	# At a close-hauled length the yaw derivative approaches zero. Use the
	# descending pitch branch instead of dividing by that near-zero slope.
	# This is a coordinate change on the same measured material constraint.
	if not is_finite(target) or target<=0 or not is_finite(yaw) or absf(yaw)<minimum_yaw() or absf(yaw)>MAX_YAW or not is_finite(tolerance) or tolerance<=0 or tolerance>LENGTH_TOLERANCE:
		return {"valid":false,"reason":"outside pitch inverse bounds"}
	var previous := angles()
	evaluations=0
	var low := MIN_PITCH
	var high := low
	var a := _length(yaw,low)
	var b := a
	var bracketed := false
	# Stop before a possible block-to-block fold: only a decreasing length
	# bracket is admissible. Collision acceptance remains a separate check.
	for sample in range(1,49):
		high=lerpf(MIN_PITCH,MAX_PITCH,sample/48.0)
		b=_length(yaw,high)
		if b<a and target<=a+tolerance and target>=b-tolerance:
			bracketed=true
			break
		low=high
		a=b
	if not bracketed:
		rig.set_angles(previous.x,previous.y,display)
		return {"valid":false,"reason":"yaw cannot retain sheet on descending pitch branch"}
	var pitch := clampf(previous.y,low,high)
	var measured := 0.0
	for iteration in 24:
		measured=_length(yaw,pitch)
		if absf(measured-target)<=tolerance*.5: break
		if measured>target:
			low=pitch
			a=measured
		else:
			high=pitch
			b=measured
		pitch=clampf(lerpf(low,high,(a-target)/maxf(.000001,a-b)),low+(high-low)*.001,high-(high-low)*.001)
	if absf(measured-target)>tolerance:
		rig.set_angles(previous.x,previous.y,display)
		return {"valid":false,"reason":"pitch inverse did not converge","error_metres":measured-target}
	if display: rig.set_angles(yaw,pitch,true)
	return {"valid":true,"yaw":yaw,"pitch":pitch,"error_metres":measured-target,"target":target,"evaluations":evaluations,"opening":rig.opening}

func jacobian(dependent_axis := 0) -> Dictionary:
	var q := angles()
	var length: float = rig.length_metres()
	evaluations=0
	var hy := minf(.0015,maxf(.000002,absf(q.x)*.24))
	var dy := local_derivative(q,0,hy)
	var dp := local_derivative(q,1,DERIVATIVE_STEP)
	rig.set_angles(q.x,q.y,false)
	var gradient := Vector2(dy,dp)
	var valid := gradient.is_finite() and absf(gradient[dependent_axis])>.001
	return {"valid":valid,"length":length,"gradient":gradient,"dyaw_dpitch":-dp/dy if absf(dy)>.001 else 0.0,"dpitch_dyaw":-dy/dp if absf(dp)>.001 else 0.0,"evaluations":evaluations}

func local_derivative(q: Vector2,axis: int,h: float) -> float:
	# Cubic fit on nine local samples, differentiated at the centre. Exact
	# length fitting remains unchanged. Avoid distant fitting/contact branches
	# and suppress single-sample float noise without weakening force checks.
	var sum := 0.0
	var weights := [126.0,193.0,142.0,-86.0]
	for index in 4:
		var first := q
		var last := q
		first[axis]-=(index+1)*h
		last[axis]+=(index+1)*h
		sum+=weights[index]*(_length(last.x,last.y)-_length(first.x,first.y))
	return sum/(1188*h)

func drape(target: float,yaw: float,pitch: float,gravity: Vector3,display := true) -> Dictionary:
	var previous := angles()
	var previous_path: PackedVector3Array=rig.route.duplicate()
	var previous_static: bool=rig.rope_view.static_display
	if not is_finite(yaw) or not is_finite(pitch) or absf(yaw)<rig.minimum_yaw or absf(yaw)>MAX_YAW or pitch<MIN_PITCH or pitch>MAX_PITCH:
		return {"valid":false,"reason":"outside hanging rig angle bounds"}
	prepare_drape_boundary(yaw,pitch)
	var frame: Transform3D=rig.global_transform.affine_inverse()*rig.hull.global_transform
	var request := [target,yaw,pitch,gravity,rig.hull.mesh,frame,rig.tiller_angle,HANGING.exit_turn_metres]
	var boundary: PackedVector3Array=rig.route.duplicate()
	if request==drape_key and _same_drape_boundary(boundary):
		drape_cache_hits+=1
		rig.route=drape_result.path
		if display: _display_drape(drape_result.get("surface_arrays",[]))
		return drape_result.duplicate(true)
	drape_solves+=1
	var result: Dictionary=HANGING.build(rig.route,rig.wraps,target,gravity)
	if result.valid and not _clear_of_hull(result.path):
		var key := [rig.hull.mesh,frame,gravity.normalized()]
		if key!=support_key:
			hull_support=SUPPORT.new()
			hull_support.setup(rig.hull.mesh,frame,gravity,.004)
			support_key=key
		if not hull_support.valid:
			result={"valid":false,"reason":"invalid hull contact surface"}
		elif hull_support.clearance(result.path)<0:
			result=HANGING.build(rig.route,rig.wraps,target,gravity,hull_support)
	if not result.valid:
		prepare_drape_boundary(previous.x,previous.y)
		rig.route=previous_path
		if display:
			if previous_static: _display_drape()
			else:
				rig.rope_view.show_path(rig.route)
				rig.fixed_view.show_path(rig.fixed_end)
				rig._draw_traveller()
		return result
	rig.route=result.path
	if display: _display_drape()
	result["yaw"]=yaw
	result["pitch"]=pitch
	drape_key=request
	drape_boundary=boundary
	drape_result=result.duplicate(true)
	return result

func prepare_drape_boundary(yaw: float,pitch: float) -> void:
	if spatial_guide_state!=null and spatial_guide_state.matches(rig,yaw,pitch):
		if spatial_guide_state.apply(rig,yaw,pitch): return
	rig.set_angles(yaw,pitch,false)

func _same_drape_boundary(path: PackedVector3Array) -> bool:
	if path.size()!=drape_boundary.size() or drape_result.is_empty(): return false
	# Repeated authored pose evaluation has sub-micrometre float noise. This
	# cache bound is independent of (and much tighter than) contact acceptance.
	for index in path.size():
		if path[index].distance_squared_to(drape_boundary[index])>4e-12: return false
	return true

func accept_prepared(target: float,yaw: float,pitch: float,gravity: Vector3,boundary: PackedVector3Array,result: Dictionary) -> bool:
	# Only the main-thread transaction can publish a detached worker result.
	# Validate the exact source path again; do not attach it to a new trim.
	if not result.get("valid",false) or not result.has("path") or boundary.size()!=rig.route.size(): return false
	if not is_finite(target) or result.path.size()<2: return false
	for point: Vector3 in result.path:
		if not point.is_finite(): return false
	for index in boundary.size():
		if boundary[index].distance_squared_to(rig.route[index])>4e-12: return false
	if absf(HANGING.length_of(result.path)-target)>HANGING.LENGTH_EPS: return false
	var frame: Transform3D=rig.global_transform.affine_inverse()*rig.hull.global_transform
	drape_key=[target,yaw,pitch,gravity,rig.hull.mesh,frame,rig.tiller_angle,HANGING.exit_turn_metres]
	drape_boundary=boundary.duplicate()
	drape_result=result.duplicate(true)
	return true

func _display_drape(prepared: Array=[]) -> void:
	rig.rope_view.show_static_path(rig.route,prepared)
	rig.fixed_view.show_path(rig.fixed_end)
	rig._draw_traveller()

func _clear_of_hull(path: PackedVector3Array) -> bool:
	# Conservative broad phase, including the rolled lip and well boundary.
	# Near misses still use the unchanged free path after the actual mesh check.
	const MARGIN := .025
	var frame: Transform3D=rig.hull.global_transform.affine_inverse()*rig.global_transform
	for index in path.size()-1:
		var a: Vector3=frame*path[index]
		var b: Vector3=frame*path[index+1]
		var samples := maxi(1,ceili(a.distance_to(b)/.015))
		for sample in samples+1:
			var p := a.lerp(b,sample/float(samples))
			if absf(p.z)>rig.HULL.HULL_LENGTH_METERS*.5+MARGIN: continue
			var width: float=rig.hull._deck_profile_at(p.z).x
			if absf(p.x)>width+MARGIN: continue
			var surface: float=rig.hull.deck_y_at(p.x,p.z)
			if p.z>=-.390+MARGIN and p.z<=1.415-MARGIN and absf(p.x)<rig.hull._cockpit_half_width_at(p.z)-MARGIN:
				surface=rig.hull.cockpit_floor_y_at(p.x,p.z)
			if p.y-.004<surface+MARGIN: return false
	return true
