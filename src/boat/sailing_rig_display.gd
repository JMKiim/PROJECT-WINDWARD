extends "res://src/preview/tack/rig_display.gd"
## F5-only display:taut inverse defines the sheet limit,wind defines the
## actual opening. Extra rig length is displayed by the existing floor lay.
const RESPONSE := preload("res://src/sailing/boom_response.gd")
const ROD := preload("res://src/preview/tack/rod_rope_contact.gd")
var response := RESPONSE.new()
var boat: Node3D
var pending_delta := 0.0
var actual_yaw := 0.0
var display_total := 14.0
var slack_metres := 0.0
var budget_iterations := 0
var limit_valid := true
var limit_error := 0.0
var record_budget_trace := false
var budget_trace := []
var measure_key := []
var measured_rig_length := 0.0
var geometry_evaluations := 0
var normal_seed_resets := 0
var free_seed_resets := 0
var limit_pin_seed := Vector2.ZERO
var free_pin_seed := Vector2.ZERO
func setup_sailing(value: Node3D) -> void:
	boat=value; response.synchronize(fitted_yaw); actual_yaw=fitted_yaw
	limit_valid=valid
	limit_pin_seed=rig.pin_geometry.seed
func prepare(delta: float) -> void:
	pending_delta=delta
	var model: RefCounted=lab.review_options.model
	model.sailing_display_budget_active=false
	if maneuver.phase!="CROSS": model.display_budget=NAN
func maneuver_entry_ready() -> bool:
	return absf(response.magnitude-absf(fitted_yaw))<.00000001
func fit_normal() -> bool:
	valid=limit_valid; error_m=limit_error
	rig.pin_geometry.seed=limit_pin_seed
	var ok := super.fit_normal()
	if not ok:
		# Wind opening and sheet-limit fitting now alternate geometries.
		# Like the established crossing solver,restart an invalid nonlinear
		# pin seed once;recompute the same geometry with unchanged tolerances.
		rig.pin_geometry.seed=Vector2.ZERO; signature.clear()
		normal_seed_resets+=1
		ok=super.fit_normal()
	limit_valid=ok; limit_error=error_m
	if ok: limit_pin_seed=rig.pin_geometry.seed
	return ok
func update() -> bool:
	var dt := pending_delta; pending_delta=0
	if maneuver.phase=="CROSS":
		actual_yaw=atan2(rig.boom_pivot.basis.z.x,rig.boom_pivot.basis.z.z)
		response.synchronize(actual_yaw)
		return super.update()
	var started := Time.get_ticks_usec()
	var model: RefCounted=lab.review_options.model
	var ledger: RefCounted=lab.complete_sheet.ledger
	if model.sailing_display_budget_active:
		model.sailing_display_budget_active=false; model.display_budget=NAN
		model.build(ledger.cockpit_metres)
	if not fit_normal(): return false
	var direction: float=-lab.actor.seat_side
	var state: RefCounted=boat.sailing_state
	var body_frame: Basis=Basis(Vector3.UP,state.heading_radians)*state.sail_attitude_basis
	var air: Vector3=body_frame.inverse()*state.apparent_wind_velocity()
	actual_yaw=response.advance(dt,absf(fitted_yaw),direction,air,maneuver.phase!="IDLE")
	if absf(actual_yaw-fitted_yaw)<.00000001:
		# A taut sail is the established normal display,not a new floor
		# inverse every frame. Restore it once if a cached limit fit left
		# the previously free boom in the scene;do not reuse a stale pose.
		var visible := atan2(rig.boom_pivot.basis.z.x,rig.boom_pivot.basis.z.z)
		if absf(visible-fitted_yaw)>.00000001:
			signature.clear()
			if not fit_normal(): return false
		response.magnitude=absf(fitted_yaw); actual_yaw=fitted_yaw
		display_total=ledger.total_metres+error_m; slack_metres=0; budget_iterations=0; geometry_evaluations=0
		update_ms=(Time.get_ticks_usec()-started)/1000.0
		return valid
	# Keep the confirmed knot/sheave handedness at the exact centerline.
	var geometry_yaw := direction*maxf(absf(actual_yaw),.000000001)
	# A per-update cache only:changing the rope's floor budget cannot
	# change its first two deck leads or the finalized spar/tool pose.
	# Drop it after every taut fit;never reuse it across physical frames.
	measure_key.clear(); geometry_evaluations=0
	model.sailing_display_budget_active=true
	model.display_budget=ledger.cockpit_metres
	var local_result: Dictionary=model.build(ledger.cockpit_metres)
	var probe := _measure(local_result,geometry_yaw)
	if not probe.valid: valid=false; return false
	var budget: float=ledger.cockpit_metres+ledger.total_metres-probe.total
	var previous_budget := NAN; var previous_error := NAN
	var low := NAN; var high := NAN
	valid=false; budget_iterations=0; budget_trace.clear()
	for iteration in 24:
		budget_iterations=iteration+1
		if iteration>0:
			model.display_budget=clampf(budget,.05,ledger.total_metres)
			local_result=model.build(ledger.cockpit_metres)
			probe=_measure(local_result,geometry_yaw)
			if not probe.valid: break
		display_total=probe.total; error_m=display_total-ledger.total_metres
		if record_budget_trace: budget_trace.append({"budget":model.display_budget,"error":error_m,"floor_points":local_result.floor_points,"end":str(local_result.end_path[0])})
		if absf(error_m)<=.00005: valid=true; break
		var current: float=model.display_budget
		if error_m<0: low=current
		else: high=current
		var slope := 1.0
		if is_finite(previous_budget) and absf(current-previous_budget)>.00000001:
			var measured: float=(error_m-previous_error)/(current-previous_budget)
			if measured>.1 and measured<10: slope=measured
		previous_budget=current; previous_error=error_m
		budget=current-error_m/slope
		if is_finite(low) and is_finite(high) and low<high:
			var inset: float=(high-low)*.05
			if budget<=low+inset or budget>=high-inset: budget=(low+high)*.5
	slack_metres=model.display_budget-ledger.cockpit_metres
	if valid:
		rig.show_geometry(); lab.review_options.show_held(lab)
	update_ms=(Time.get_ticks_usec()-started)/1000.0
	return valid
func _measure(result: Dictionary,yaw: float) -> Dictionary:
	if not result.get("valid",false): return {"valid":false}
	var dynamic: PackedVector3Array=result.dynamic_path
	var remote := JOIN.remote(dynamic,lab.to_local(lab.ratchet.rope_anchor_global()))
	if remote.size()<2: return {"valid":false}
	var axis: Vector3=(lab.actor.palm_boat()-lab.actor.joint_boat()).normalized()
	var key := [yaw,lab.actor.rudder_angle(),remote[0],remote[1],lab.actor.joint_boat(),axis,lab.actor.extension_span]
	if key!=measure_key:
		rig.tiller_angle=lab.actor.rudder_angle(); rig.cockpit_lead=remote
		# The limit and the wind opening are different geometric closures.
		# Never warm-start one from the other;this is not a pose search.
		rig.pin_geometry.seed=free_pin_seed
		rig.set_angles(yaw,rig.minimum_pitch,false)
		geometry_evaluations+=1
		if not rig.geometry_valid:
			rig.pin_geometry.seed=Vector2.ZERO; free_seed_resets+=1
			rig.set_angles(yaw,rig.minimum_pitch,false)
			geometry_evaluations+=1
		if not rig.geometry_valid: return {"valid":false}
		free_pin_seed=rig.pin_geometry.seed
		var supported: Dictionary=ROD.route(rig.route,lab.actor.joint_boat(),axis,lab.actor.extension_span)
		if not supported.unresolved.is_empty(): return {"valid":false}
		rig.route=supported.path
		measured_rig_length=rig.length_metres()+ARC.length_of(rig.local_fixed_end)
		measure_key=key
	var cropped := ARC.length_of(dynamic)-ARC.length_of(remote)
	return {"valid":true,"total":measured_rig_length+ARC.length_of(result.path)-cropped+ARC.length_of(result.end_path)}
