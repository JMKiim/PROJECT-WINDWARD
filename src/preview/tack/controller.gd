extends RefCounted
const MODEL := preload("res://src/preview/tack/timeline_motion.gd")
const TIMELINE := preload("res://src/preview/tack/timeline.gd")
const DURATION := TIMELINE.DURATION
const CLOCK := preload("res://src/preview/tack/clock.gd")
const ROD_CONTACT := preload("res://src/preview/tack/rod_rope_contact.gd")
const BOOM := preload("res://src/preview/tack/boom.gd")
const ARC := preload("res://src/boat/mainsheet_stopper.gd")
const JOIN := preload("res://src/boat/mainsheet_deck_join.gd")
const BRIDGE := preload("res://src/preview/tack/endpoint_bridge.gd")
const BRIDGE_SECONDS := .18
var lab: Node3D
var actor: Node3D
var model: RefCounted
var phase := "IDLE"
var source_side := -1
var progress := 0.0
var clock_progress := 0.0
var steering := 0.0
var steering_target := 0.0
var sampled_steering := INF
var retained_trim := 0.0
var result := {}
var compose_ms := 0.0
var geometry_ms := 0.0
var geometry_valid := false
var display_total := 0.0
var geometry_error := ""
var initial_yaw := 0.0
var end_yaw := 0.0
var end_signature := []
var start_signature := []
var geometry_signature := []
var geometry_result := {}
var geometry_iterations := 0
var geometry_profile := {}
var gaze_weight := 1.0
var gaze_time := 0.0
const GAZE_SECONDS := .30
var bridge_time := 0.0
var bridge_data := {}
var bridge_steering := INF
var record_geometry_trace := false
func setup(value: Node3D) -> bool:
	lab=value
	actor=lab.actor
	actor.maneuver=self
	model=MODEL.new()
	model.setup(actor)
	var error: String=model.resources_error()
	if not error.is_empty():
		lab.session.notice=error
		push_error(error)
		return false
	return true
func busy() -> bool: return phase!="IDLE"
func manual_trim_stage() -> bool: return false
func is_gybe() -> bool: return false
func action_name() -> String: return "태킹"
func completion_fraction() -> float: return progress if source_side==-1 else 1-progress
func destination_name() -> String: return "우현" if source_side==-1 else "좌현"
func request() -> bool:
	if busy(): return false
	if lab.session.reference_fixture or lab.session.selected_system!=0:
		lab.session.notice="메인시트 수동 조작 상태에서 시작해 주세요."
		return false
	source_side=actor.seat_side
	retained_trim=lab.session.wheel_pull.metres
	lab.session.wheel_pull.pause()
	lab.session.request_hike(0)
	phase="PREP"
	gaze_time=0
	gaze_weight=1
	lab.review_options.model.display_budget=NAN
	lab.session.notice="태킹 준비 · 트림을 유지하며 손과 발을 복귀해요."
	return true
func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0: return
	if phase=="PREP":
		gaze_time=minf(GAZE_SECONDS,gaze_time+delta)
		gaze_weight=1-smoothstep(0,GAZE_SECONDS,gaze_time)
		actor.set_look(lab.look_yaw,lab.look_pitch)
		var wheel: RefCounted=lab.session.wheel_pull
		if gaze_weight>0 or actor.hike>.000001 or actor.grip_phase!="HOLD" or wheel.state!="REST" or absf(wheel.work-.5)>.000001 or actor.sheet_control.ease_relaxation>.000001: return
		# Steering is a boat-space coordinate. Normal seated controls use
		# opposite push/pull signs on the two sides of the cockpit.
		steering=-source_side*actor.amount
		steering_target=-source_side*actor.steering_target
		sampled_steering=INF
		progress=0 if source_side==-1 else 1
		clock_progress=progress
		initial_yaw=absf(lab.rig_display.fitted_yaw)
		end_yaw=-initial_yaw
		end_signature.clear()
		start_signature.clear()
		geometry_signature.clear()
		phase="ENTRY"
		bridge_time=0
		bridge_steering=INF
		compose_bridge()
		return
	if phase=="POST":
		gaze_time=minf(GAZE_SECONDS,gaze_time+delta)
		gaze_weight=smoothstep(0,GAZE_SECONDS,gaze_time)
		actor.set_look(lab.look_yaw,lab.look_pitch)
		if gaze_weight>=1:
			phase="IDLE"
			lab.session.notice=destination_name()+" 태킹 완료 · W/S·휠 시트와 X/Z 하이크를 계속 조작할 수 있어요."
		return
	if phase in ["ENTRY","EXIT"]:
		steering=move_toward(steering,steering_target,minf(delta,.1)*1.5)
		bridge_time=minf(BRIDGE_SECONDS,bridge_time+delta)
		compose_bridge()
		if bridge_time>=BRIDGE_SECONDS:
			if phase=="ENTRY":
				initial_yaw=absf(lab.rig_display.fitted_yaw)
				end_yaw=-initial_yaw
				phase="CROSS"
				sampled_steering=steering
			else:
				phase="POST"
				gaze_time=0
				gaze_weight=0
		return
	if phase!="CROSS": return
	steering=move_toward(steering,steering_target,minf(delta,.1)*1.5)
	clock_progress=move_toward(clock_progress,1.0 if source_side==-1 else 0.0,minf(delta,.1)/DURATION)
	compose()
	if source_side==-1 and clock_progress>=1 or source_side==1 and clock_progress<=0: finish()
func seek(u: float) -> void:
	clock_progress=TIMELINE.time_for(u)
	compose()
func compose() -> void:
	if phase in ["ENTRY","EXIT"]: compose_bridge(); return
	if phase!="CROSS": return
	var started := Time.get_ticks_usec()
	if not is_equal_approx(steering,sampled_steering):
		actor.endpoint_sampling=true
		var looked: bool=actor.look_enabled
		actor.look_enabled=false
		model.set_steering(steering)
		actor.look_enabled=looked
		actor.endpoint_sampling=false
		sampled_steering=steering
	# The authored path is in the same boat-space frame in both directions.
	# No mirrored skeleton, handedness swap or inspection cut is involved.
	actor.seat_side=-1
	actor.amount=steering
	actor.steering_target=steering_target
	result=model.sample(clock_progress)
	if source_side==1:
		# Reversing the actual hand phases closes the incoming right hand
		# before opening the outgoing left hand. Relabel the phase, not the
		# physical contacts, fingers or sheet-support channels.
		result.elapsed_phase=1-clock_progress
		if result.handoff_stage=="GRIP": result.handoff_stage="RELEASE"
		elif result.handoff_stage=="RELEASE": result.handoff_stage="GRIP"
	progress=result.geometry_u
	if actor.neck_cap!=null and actor.neck_cap.visible: actor.neck_cap.update_pose()
	lab.session.notice="%s 태킹 %.0f%% · 트림 유지 · A/D 조타와 시점은 계속 조작할 수 있어요."%[destination_name(),completion_fraction()*100]
	compose_ms=(Time.get_ticks_usec()-started)/1000.0
func finish() -> void:
	phase="EXIT"
	bridge_time=0
	bridge_steering=INF
	gaze_time=0
	gaze_weight=0
	lab.review_options.model.display_budget=NAN
	actor.endpoint_sampling=true
	actor.set_side(-source_side)
	actor.set_amount(source_side*steering)
	actor.request_amount(source_side*steering_target)
	actor.endpoint_sampling=false
	lab.session.requested_side=-source_side
	lab.session.requested_hike=0
	lab.session.posture_pending=false
	compose_bridge()
	lab.session.notice=destination_name()+" 자세와 시선을 연결하고 있어요."
func compose_bridge() -> void:
	if phase not in ["ENTRY","EXIT"]: return
	var u := 0.0 if phase=="ENTRY" else 1.0
	if source_side==1: u=1-u
	if not is_equal_approx(steering,bridge_steering):
		actor.endpoint_sampling=true
		var looked: bool=actor.look_enabled
		actor.look_enabled=false
		model.set_steering(steering)
		bridge_data=BRIDGE.capture(model,u)
		actor.look_enabled=looked
		actor.endpoint_sampling=false
		bridge_steering=steering
	result=bridge_data.result
	var weight: float=smoothstep(0,BRIDGE_SECONDS,bridge_time)
	if phase=="EXIT": weight=1-weight
	BRIDGE.apply(actor,bridge_data,weight)
	for side in ["Left","Right"]: model.settle_upper_twist(side,weight)
	actor.seat_side=source_side if phase=="ENTRY" else -source_side
	actor.amount=-actor.seat_side*steering
	actor.steering_target=-actor.seat_side*steering_target
func cancel() -> void:
	phase="IDLE"
	gaze_weight=1
	gaze_time=0
	result.clear()
	geometry_signature.clear()
	geometry_valid=false
	bridge_data.clear()
	if lab!=null and lab.review_options.model.get("display_budget")!=null: lab.review_options.model.display_budget=NAN
func _fit_end_yaw() -> bool:
	var signature := [steering,lab.session.wheel_pull.metres]
	if source_side==1: signature=[retained_trim]
	if signature==end_signature: return true
	var saved_progress := progress
	var sheet_model: RefCounted=lab.review_options.model
	var budget: float=sheet_model.display_budget
	progress=1
	result=model.sample(1)
	actor.seat_side=1
	actor.amount=-steering
	sheet_model.display_budget=NAN
	var end_path: Dictionary=sheet_model.build(lab.complete_sheet.ledger.cockpit_metres)
	var valid: bool=end_path.get("valid",false) and lab.rig_display.fit_normal()
	if valid: end_yaw=lab.rig_display.fitted_yaw
	actor.seat_side=-1
	actor.amount=steering
	actor.steering_target=steering_target
	progress=saved_progress
	result=model.sample(clock_progress)
	sheet_model.display_budget=budget
	if valid: end_signature=signature
	return valid
func _fit_start_yaw() -> bool:
	# The starting opening belongs to this maneuver,not to each later
	# steering frame. Re-fitting the hypothetical source every frame both
	# changes the intended spar path and repeats expensive rig work.
	var signature := [retained_trim]
	if source_side==1: signature=[steering,lab.session.wheel_pull.metres]
	if signature==start_signature: return true
	var saved_progress := progress
	var sheet_model: RefCounted=lab.review_options.model
	var budget: float=sheet_model.display_budget
	progress=0
	result=model.sample(0)
	sheet_model.display_budget=NAN
	var start_path: Dictionary=sheet_model.build(lab.complete_sheet.ledger.cockpit_metres)
	var valid: bool=start_path.get("valid",false) and lab.rig_display.fit_normal()
	if valid: initial_yaw=absf(lab.rig_display.fitted_yaw)
	progress=saved_progress
	result=model.sample(clock_progress)
	sheet_model.display_budget=budget
	if valid: start_signature=signature
	return valid
func update_geometry() -> bool:
	if phase!="CROSS" or result.is_empty(): return false
	var signature := [progress,steering,lab.session.wheel_pull.metres]
	if signature==geometry_signature: return geometry_valid
	var started := Time.get_ticks_usec()
	geometry_valid=false
	geometry_error=""
	geometry_profile={"build_ms":0.0,"rig_ms":0.0,"show_ms":0.0,"end_fit_ms":0.0}
	if record_geometry_trace: geometry_profile.iterations=[]
	var fit_started := Time.get_ticks_usec()
	var source_fitted: bool=_fit_start_yaw() if source_side==-1 else _fit_end_yaw()
	if not source_fitted:
		geometry_error="태킹 시작 리그 연결을 확인해 주세요."
		return false
	var target_needed: bool=progress>=.96 if source_side==-1 else progress<=.04
	var target_fitted: bool=true
	if target_needed: target_fitted=_fit_end_yaw() if source_side==-1 else _fit_start_yaw()
	if not target_fitted:
		geometry_error="태킹 끝 리그 연결을 확인해 주세요."
		return false
	geometry_profile.end_fit_ms=(Time.get_ticks_usec()-fit_started)/1000.0
	var yaw := _prescribed_yaw()
	var rig: Node3D=lab.rig_display.rig
	var sheet_model: RefCounted=lab.review_options.model
	var ledger: RefCounted=lab.complete_sheet.ledger
	sheet_model.route_ms=0
	sheet_model.floor_ms=0
	sheet_model.floor_evaluations=0
	if not is_finite(sheet_model.display_budget): sheet_model.display_budget=ledger.cockpit_metres
	var build_started := Time.get_ticks_usec()
	var local_result: Dictionary=sheet_model.build(ledger.cockpit_metres)
	geometry_profile.build_ms+=(Time.get_ticks_usec()-build_started)/1000.0
	var previous_budget := NAN
	var previous_error := NAN
	var bracket_low := NAN
	var bracket_high := NAN
	for iteration in 24:
		geometry_iterations=iteration+1
		if not local_result.get("valid",false): geometry_error="태킹 줄 경로를 확인해 주세요."; break
		var dynamic: PackedVector3Array=local_result.dynamic_path
		var remote := JOIN.remote(dynamic,lab.to_local(lab.ratchet.rope_anchor_global()))
		if remote.size()<2: geometry_error="태킹 데크 줄 연결을 확인해 주세요."; break
		rig.tiller_angle=actor.rudder_angle()
		rig.cockpit_lead=remote
		var rig_started := Time.get_ticks_usec()
		rig.set_angles(yaw,rig.minimum_pitch,false)
		if not rig.geometry_valid:
			geometry_profile.pin_failure_reason=rig.pin_result.get("reason","")
			# A sparse seek can invalidate the previous nonlinear seed.
			# Recompute the same geometry,with all original pin tolerances.
			rig.pin_geometry.seed=Vector2.ZERO
			rig.set_angles(yaw,rig.minimum_pitch,false)
		var supported := ROD_CONTACT.route(rig.route,actor.joint_boat(),result.axis,actor.extension_span)
		rig.route=supported.path
		geometry_profile.rod_unresolved=supported.unresolved
		geometry_profile.rig_ms+=(Time.get_ticks_usec()-rig_started)/1000.0
		if not rig.geometry_valid: geometry_error="태킹 중 리그 연결부를 확인해 주세요."; break
		var cropped := ARC.length_of(dynamic)-ARC.length_of(remote)
		display_total=rig.length_metres()+ARC.length_of(rig.local_fixed_end)+ARC.length_of(local_result.path)-cropped+ARC.length_of(local_result.end_path)
		var error: float=display_total-ledger.total_metres
		if record_geometry_trace: geometry_profile.iterations.append({"budget":sheet_model.display_budget,"total":display_total,"error":error,"held":local_result.held_metres,"suspended":local_result.suspended_metres,"grounded":local_result.grounded,"path_length":ARC.length_of(local_result.path),"end_length":ARC.length_of(local_result.end_path),"rig_length":rig.length_metres(),"cropped":cropped,"remote":ARC.length_of(remote)})
		if absf(error)<=.00005:
			geometry_valid=true
			break
		var budget: float=sheet_model.display_budget
		if error<0: bracket_low=budget
		else: bracket_high=budget
		var slope := 1.0
		if is_finite(previous_budget) and absf(budget-previous_budget)>.00000001:
			var measured: float=(error-previous_error)/(budget-previous_budget)
			if measured>.1 and measured<10: slope=measured
		previous_budget=budget
		previous_error=error
		# This is an internal scalar inverse,not a displayed motion. A
		# sparse seek or trim reset may need an8m budget change; a .5m
		# per-iteration cap falsely exhausted the solve before reaching it.
		var proposed := budget-error/slope
		# A hanging stopper can change its supported length nonlinearly at
		# the moulded floor. Keep a valid sign bracket instead of cycling
		# through the same unguarded Newton guesses near that transition.
		if is_finite(bracket_low) and is_finite(bracket_high) and bracket_low<bracket_high:
			var inset: float=(bracket_high-bracket_low)*.05
			if proposed<=bracket_low+inset or proposed>=bracket_high-inset:
				proposed=(bracket_low+bracket_high)*.5
		sheet_model.display_budget=clampf(proposed,.05,ledger.total_metres)
		build_started=Time.get_ticks_usec()
		local_result=sheet_model.build(ledger.cockpit_metres)
		geometry_profile.build_ms+=(Time.get_ticks_usec()-build_started)/1000.0
	if not geometry_valid and geometry_error.is_empty():
		# A discrete stopper/floor branch can leave a millimetre-scale
		# budget residual. Fit only the read-only spar opening within half
		# a degree; never alter a hand,trim or the14m acceptance threshold.
		var prescribed := yaw
		for refinement in 3:
			var actual := _probe_display(local_result,yaw)
			if not actual.valid: break
			display_total=actual.total
			var error: float=display_total-ledger.total_metres
			if absf(error)<=.00005: geometry_valid=true; break
			var epsilon := .0001*(-1 if yaw<0 else 1)
			var nearby := _probe_display(local_result,yaw+epsilon)
			if not nearby.valid: break
			var slope: float=(nearby.total-display_total)/epsilon
			if absf(slope)<.1: break
			yaw=clampf(yaw-error/slope,prescribed-deg_to_rad(.5),prescribed+deg_to_rad(.5))
		geometry_profile.opening_correction_degrees=rad_to_deg(yaw-prescribed)
	if geometry_valid:
		var show_started := Time.get_ticks_usec()
		rig.show_geometry()
		lab.review_options.show_held(lab)
		geometry_profile.show_ms=(Time.get_ticks_usec()-show_started)/1000.0
		geometry_result={"yaw":yaw,"total":display_total,"display_budget":sheet_model.display_budget,"logical_cockpit":ledger.cockpit_metres,"path":local_result.path,"dynamic_path":local_result.dynamic_path,"end_path":local_result.end_path}
	else:
		if geometry_error.is_empty(): geometry_error=" 태킹 표시 길이를 확인해 주세요."
		lab.session.notice=geometry_error
	geometry_signature=signature
	geometry_ms=(Time.get_ticks_usec()-started)/1000.0
	geometry_profile.route_ms=sheet_model.route_ms
	geometry_profile.floor_ms=sheet_model.floor_ms
	geometry_profile.floor_evaluations=sheet_model.floor_evaluations
	geometry_profile.cockpit_rod_unresolved=sheet_model.rod_unresolved.duplicate()
	return geometry_valid
func _prescribed_yaw() -> float:
	var yaw := BOOM.yaw(initial_yaw,-initial_yaw,progress)
	if source_side==1:
		yaw=BOOM.yaw(-end_yaw,end_yaw,progress)
		if progress<=.04: yaw=lerpf(yaw,initial_yaw,1-smoothstep(0,.04,progress))
	elif progress>=.96: yaw=lerpf(yaw,end_yaw,smoothstep(.96,1,progress))
	return yaw
func _probe_display(local_result: Dictionary,yaw: float) -> Dictionary:
	var rig: Node3D=lab.rig_display.rig
	var dynamic: PackedVector3Array=local_result.dynamic_path
	var remote := JOIN.remote(dynamic,lab.to_local(lab.ratchet.rope_anchor_global()))
	if remote.size()<2: return {"valid":false}
	rig.tiller_angle=actor.rudder_angle(); rig.cockpit_lead=remote
	rig.set_angles(yaw,rig.minimum_pitch,false)
	if not rig.geometry_valid: return {"valid":false}
	var supported := ROD_CONTACT.route(rig.route,actor.joint_boat(),result.axis,actor.extension_span)
	rig.route=supported.path
	var cropped := ARC.length_of(dynamic)-ARC.length_of(remote)
	return {"valid":true,"total":rig.length_metres()+ARC.length_of(rig.local_fixed_end)+ARC.length_of(local_result.path)-cropped+ARC.length_of(local_result.end_path)}
func update_camera() -> void:
	if lab.follow_work_area: lab.first_person_view.update(lab); return
	var basis: Basis
	if phase=="CROSS" and not result.is_empty(): basis=result.body.look_frame
	else:
		var view: Basis=(actor.bone_pose_boat("Head").basis.orthonormalized()*actor.look_pose.eye_basis).orthonormalized()
		basis=view*Basis(Vector3.RIGHT,-actor.look_pose.pitch)*Basis(Vector3.UP,-actor.look_pose.yaw)
	var desired := basis*Basis(Vector3.UP,lab.look_yaw)*Basis(Vector3.RIGHT,lab.look_pitch)
	var eye: Vector3=lab.to_local(actor.to_global(actor.eye_boat()))
	lab.camera.position=eye
	# Keep the full transported eye frame. Rebuilding roll from world UP
	# becomes singular when a high glance crosses the vertical during lean.
	lab.camera.basis=(desired*Basis(Vector3.UP,PI)).orthonormalized()
	lab.camera.fov=72
