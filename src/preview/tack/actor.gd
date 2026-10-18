extends "res://src/preview/land_drill_visual_actor.gd"
## Same-scene composition hook for the same F6 scene. Endpoint sampling calls
## the normal writer; only the active crossing owns the displayed skeleton.
var maneuver: RefCounted
var endpoint_sampling := false
func set_look(horizontal: float,vertical: float) -> void:
	var weight: float=maneuver.gaze_weight if maneuver!=null and maneuver.busy() else 1.0
	super.set_look(horizontal*weight,vertical*weight)
func crossing() -> bool:
	return maneuver!=null and maneuver.phase in ["ENTRY","CROSS","EXIT"] and not endpoint_sampling
func set_amount(value: float) -> void:
	if not crossing(): super.set_amount(value); return
	if not is_finite(value): return
	maneuver.steering=clampf(value,-1,1)*-seat_side
	maneuver.compose()
func request_amount(value: float) -> void:
	if not crossing(): super.request_amount(value); return
	if is_finite(value): maneuver.steering_target=clampf(value,-1,1)*-seat_side
func tiller_hand() -> String:
	if crossing() and not maneuver.result.is_empty(): return maneuver.result.ownership.primary_tool
	return super.tiller_hand()
func sheet_hand() -> String:
	if crossing() and not maneuver.result.is_empty():
		var ownership: Dictionary=maneuver.result.ownership
		return ownership.sheet_hand if not ownership.sheet_hand.is_empty() else ownership.helper_hand
	return super.sheet_hand()
func palm_boat(prefix: String="") -> Vector3:
	if not crossing() or maneuver.result.is_empty(): return super.palm_boat(prefix)
	var side := tiller_hand() if prefix.is_empty() else prefix
	var offset: Vector3=authored_grip.TILLER_OFFSET
	if maneuver.result.plans.has(side): offset=maneuver.result.plans[side].offset
	if maneuver.result.free.has(side): offset=maneuver.result.free[side].offset
	return bone_pose_boat(side+"Hand")*offset
