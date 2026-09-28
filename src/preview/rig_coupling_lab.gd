extends Node3D

## Exact sheet/hand integration with a manually requested static load solve.
## The additional control is a test actuator, not an authored vang hand action.
const EQUILIBRIUM := preload("res://src/boat/rig_equilibrium.gd")
const TRAVELLER := preload("res://src/boat/traveller_equilibrium.gd")
const LINE := preload("res://src/boat/rope_view.gd")
const BLOCK_SUPPORT := preload("res://src/boat/traveller_block_support.gd")
const CONTACT_TASK := preload("res://src/boat/deck_contact_task.gd")
const SPATIAL_GUIDE := preload("res://src/boat/spatial_guide_state.gd")
const LEAD_PREPARATION := preload("res://src/boat/supported_lead_preparation.gd")
const PURCHASE_TASK := preload("res://src/boat/surface_purchase_task.gd")
var purchase_task := PURCHASE_TASK.new()
var purchase_ticket := []
var purchase_pending := false
var purchase_result := {}
var purchase_example := false
var purchase_example_angles := Vector2(deg_to_rad(25),deg_to_rad(-6))
var inspection_preset := 0
var purchase_applied_key := []
var purchase_focus := false
var purchase_focus_camera := Transform3D.IDENTITY
var spatial_contact_enabled := true
var deck: Node3D
var solver: RefCounted
var traveller_solver: RefCounted
var traveller_result := {}
var sliders: Array[HSlider]=[]
var status: Label
var mast: Node3D
var sail: MeshInstance3D
var result := {}
var solve_ms := 0.0
var message := "수동 조작 중 · 트래블러 검수 버튼으로 기준 연결부를 바로 볼 수 있어요."
var solved_key := []
var pending_action := ""
var pending_background := true
var last_action := {}
var diagram_enabled := false
var deformation_key := []
var details: Label
var vang_reference := 0.0
var deck_contact_preview := false
var block_support := BLOCK_SUPPORT.new()
var contact_task := CONTACT_TASK.new()
var contact_ticket := []
var contact_prepared := {}
var contact_cancelled := false
var contact_started_usec := 0

func setup(value: Node3D) -> void:
	deck=value
	set_process(false)
	var sheet: Node3D=deck.complete_sheet
	solver=EQUILIBRIUM.new(sheet.rig)
	vang_reference=solver.model.initial_vang_tail
	traveller_solver=TRAVELLER.new(solver)
	mast=LINE.new()
	mast.radius=.029
	mast.color=Color("919ca5")
	deck.add_child(mast)
	sail=MeshInstance3D.new()
	deck.add_child(sail)
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(.78,.82,.84,.65)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	sail.material_override=material
	_build_ui()
	set_diagram(false)
	_display_deformation()
	_refresh_status()

func _warm_block_contact() -> void:
	# Build the static neutral preset while the inspection scene is loading,
	# then restore all live geometry. No contact search runs in the frame loop.
	var rig: Node3D=deck.complete_sheet.rig
	var q: Vector2=deck.complete_sheet.rig_constraint.angles()
	var opening: float=rig.opening
	rig.set_angles(deg_to_rad(45),deg_to_rad(-6),false)
	block_support.settle(rig,Vector3(0,-9.81,0))
	rig.set_angles(q.x,q.y,false)
	rig.opening=opening

func prepare_geometry() -> void:
	# Release a static example before the first changed-input geometry pass,
	# not after paying for a supported solve that will be discarded anyway.
	if deck_contact_preview and solved_key!=_boundary_key(): _leave_changed_static()
	if not deck.complete_sheet.rig.coupled.is_empty() and purchase_applied_key!=_purchase_key(): _leave_changed_static()

func _leave_changed_static() -> void:
	var queued := pending_action
	clear_load()
	pending_action=queued
	message="조작 조건이 바뀌어 정적 검수를 해제했어요. 다시 계산해 주세요."

func advance() -> void:
	_advance_purchase()
	if not purchase_result.is_empty() and deck.complete_sheet.rig.coupled.is_empty():
		purchase_result.clear()
		message="손·시점 조건이 바뀌어 일반 검수로 복귀했어요. 줄 길이는 유지해요."
	_advance_contact()
	if (deck.complete_sheet.rig.traveller_override.is_finite() or deck_contact_preview) and solved_key!=_boundary_key():
		_leave_changed_static()
	elif not deck.complete_sheet.last_result.get("valid",false):
		deck.complete_sheet.clear_rig_pitch()
		message="현재 줄 길이는 이 높이와 함께 유지할 수 없어 기본 리그로 복귀했어요."
		result.clear()
	elif result.get("valid",false) and solved_key!=_boundary_key():
		message="시트/손 위치가 바뀌었어요. 아래 장력은 이전 조건이며 재계산이 필요해요."
	if not pending_action.is_empty() and deck.session.wheel_pull.state=="REST" and not contact_busy():
		var action := pending_action
		pending_action=""
		request_action(action,pending_background)
	_display_deformation()
	_refresh_status()

func request_action(action: String,background := true) -> Dictionary:
	if action not in ["center","load","purchase_example","purchase_contact","slack","deck"]:
		return {"valid":false,"reason":"unknown inspection request"}
	deck.session.wheel_pull.pause()
	if deck.session.wheel_pull.state!="REST":
		pending_action=action
		pending_background=background
		message="손 복귀 후 실행할게요. 다시 누를 필요 없어요. [대기 취소]로 취소 가능"
		_refresh_status()
		return {"valid":false,"queued":true,"reason":"wait for hand return"}
	pending_action=""
	if contact_busy():
		if action=="deck" and not contact_cancelled:
			return {"valid":false,"queued":true,"reason":"contact calculation in progress"}
		_cancel_contact()
		pending_action=action
		pending_background=background
		return {"valid":false,"queued":true,"reason":"wait for cancelled calculation"}
	if deck_contact_preview and action in ["center","load","purchase_example","purchase_contact"]: clear_load()
	if not deck.complete_sheet.rig.coupled.is_empty() and action!="load": clear_load()
	match action:
		"center": last_action=place_traveller_center()
		"load": last_action=begin_purchase()
		"purchase_example": last_action=begin_purchase(true)
		"purchase_contact": last_action=begin_purchase(true,true)
		"slack": last_action=show_slack_example()
		"deck": last_action=begin_deck_contact() if background else show_deck_contact_example()
	_refresh_status()
	return last_action.duplicate(true)

func cancel_request() -> void:
	purchase_focus=false
	_cancel_contact()
	purchase_pending=false
	purchase_task.cancel()
	pending_action=""
	message="대기 요청을 취소했어요. 조작한 줄 길이는 유지해요."
	_refresh_status()

func inspect_traveller() -> void:
	deck._release_mouse()
	deck.controls.drawer.hide()
	deck.set_view(8)
	if not deck.session.sheet_pose_reason().is_empty():
		message="블록 확대 · 기준 계산은 좌현·앉은 자세에서 가능해요. 설정에서 자세를 확인해 주세요."
		_refresh_status()
		return
	deck.select_system(0)
	deck._stop_and_set(-.5 if inspection_preset==1 else 0.0)
	purchase_focus=true
	purchase_focus_camera=deck.camera.transform
	request_action("purchase_contact" if inspection_preset==1 else "purchase_example")

func solve_load() -> Dictionary:
	if deck.complete_sheet.rig.traveller_override.is_finite():
		var moving := solve_traveller()
		return moving.load if moving.valid else moving
	deck.session.wheel_pull.pause()
	if deck.session.wheel_pull.state!="REST":
		message="시트 동작을 멈췄어요. 손이 복귀한 뒤 다시 계산해 주세요."
		_refresh_status()
		return {"valid":false,"reason":"wait for hand return"}
	var started := Time.get_ticks_usec()
	var prior_mast: Vector2=solver.model.mast_tip
	var prior_loads: Dictionary=solver.model.last.duplicate(true)
	_set_external_loads()
	traveller_result.clear()
	result=solver.solve(deck.complete_sheet.ledger.rig_metres)
	if result.valid:
		var applied: Dictionary
		if result.get("branch","")=="slack":
			applied=deck.complete_sheet.try_free_rig(solver.model.yaw,solver.model.pitch,solver.model.effective_gravity())
		else:
			applied=deck.complete_sheet.try_rig_pitch(solver.model.pitch)
		if not applied.valid:
			result={"valid":false,"reason":"complete cockpit path rejected equilibrium"}
			var restored: Vector2=deck.complete_sheet.rig_constraint.angles()
			solver.model.yaw=restored.x
			solver.model.pitch=restored.y
			solver.model.mast_tip=prior_mast
			solver.model.last=prior_loads
			message="적용하지 않음: 전체 줄 경로를 유지할 수 없어 이전 표시로 복원했어요."
		else:
			deck.basis=solver.model.boat_frame
			message="정적 평형 적용 · 시트/손/외력을 바꾸면 다시 계산해야 해요."
			solved_key=_boundary_key()
	else:
		message=_failure_message(result)
	solve_ms=(Time.get_ticks_usec()-started)/1000.0
	deck.controls.refresh()
	_display_deformation()
	_refresh_status()
	return result

func _set_external_loads() -> void:
	solver.model.vang_tail=solver.model.initial_vang_tail+sliders[0].value
	solver.model.wind_world=Vector3(sliders[1].value,0,-2 if sliders[1].value>0 else 0)
	solver.model.boat_frame=Basis(Vector3.BACK,deg_to_rad(sliders[2].value))
	solver.model.boat_acceleration_world=Vector3(0,sliders[3].value,0)

func _traveller_snapshot() -> Dictionary:
	var sheet: Node3D=deck.complete_sheet
	return {"override":sheet.rig.traveller_override,"block_locked":sheet.rig.traveller_pose_locked,"block_pose":sheet.rig.traveller_pose_override,"block_boundary":sheet.rig.traveller_pose_boundary,"spatial_guide":sheet.rig_constraint.spatial_guide_state,"pitch":sheet.requested_rig_pitch,"free_yaw":sheet.free_rig_yaw,"gravity":sheet.free_rig_gravity,"angles":sheet.rig_constraint.angles(),"mast":solver.model.mast_tip,"loads":solver.model.last.duplicate(true),"last":solver.last.duplicate(true)}

func _restore_traveller(previous: Dictionary) -> bool:
	var sheet: Node3D=deck.complete_sheet
	sheet.rig.traveller_override=previous.override
	sheet.rig.traveller_pose_locked=previous.block_locked
	sheet.rig.traveller_pose_override=previous.block_pose
	sheet.rig.traveller_pose_boundary=previous.block_boundary
	sheet.rig_constraint.spatial_guide_state=previous.spatial_guide
	sheet.requested_rig_pitch=previous.pitch
	sheet.free_rig_yaw=previous.free_yaw
	sheet.free_rig_gravity=previous.gravity
	sheet.rig.set_angles(previous.angles.x,previous.angles.y,false)
	sheet.geometry_key.clear()
	var restored: bool=sheet.update_geometry()
	solver.model.yaw=previous.angles.x
	solver.model.pitch=previous.angles.y
	solver.model.mast_tip=previous.mast
	solver.model.last=previous.loads
	solver.last=previous.last
	return restored

func _traveller_ready() -> bool:
	deck.session.wheel_pull.pause()
	if deck.session.wheel_pull.state!="REST":
		message="트래블러 검수는 손이 기본 자세로 돌아온 뒤 눌러 주세요."
		_refresh_status()
		return false
	return true

func place_traveller_center() -> Dictionary:
	# Explicit fixture placement, not an equilibrium or automatic playback.
	if not _traveller_ready(): return {"valid":false,"reason":"wait for hand return"}
	var sheet: Node3D=deck.complete_sheet
	var previous := _traveller_snapshot()
	var applied: Dictionary=traveller_solver.line.fit(0,0)
	if applied.valid: applied=sheet.try_rig_pitch(previous.angles.y)
	if applied.valid: applied=traveller_solver.line.contact_check()
	if not applied.valid:
		applied["restore_failed"]=not _restore_traveller(previous)
		message=_failure_message(applied)
	else:
		result.clear()
		traveller_result.clear()
		solved_key=_boundary_key()
		message="트래블러 중앙 수동 배치 · 하중 평형은 아직 계산하지 않았어요."
	_refresh_status()
	return applied

func solve_traveller() -> Dictionary:
	if not deck.complete_sheet.rig.coupled.is_empty(): clear_load()
	if not _traveller_ready(): return {"valid":false,"reason":"wait for hand return"}
	var sheet: Node3D=deck.complete_sheet
	var previous := _traveller_snapshot()
	_set_external_loads()
	var started := Time.get_ticks_usec()
	var candidate: Dictionary=traveller_solver.solve(sheet.ledger.rig_metres,sliders[4].value)
	if candidate.valid:
		var applied: Dictionary=sheet.try_rig_pitch(solver.model.pitch)
		if not applied.valid: candidate={"valid":false,"reason":"complete cockpit path rejected traveller equilibrium"}
	if not candidate.valid:
		candidate["restore_failed"]=not _restore_traveller(previous)
		message=_failure_message(candidate)
	else:
		traveller_result=candidate
		result=candidate.load
		deck.basis=solver.model.boat_frame
		solved_key=_boundary_key()
		var moved: float=candidate.start.distance_to(sheet.rig.traveller_lower.position)
		message="계산 완료 · 위치 변화 %.1f mm\n%s" % [moved*1000,"하중이 바깥쪽을 향해 현재 검수 경계에 머물러요." if candidate.state=="stop" else "마찰과 하중이 균형을 이루는 위치예요."]
	solve_ms=(Time.get_ticks_usec()-started)/1000.0
	deck.controls.refresh()
	_display_deformation()
	_refresh_status()
	return candidate.duplicate(true)

func _boundary_key() -> Array:
	return [deck.complete_sheet.ledger.rig_metres,deck.actor.amount,deck.actor.sheet_control.work,deck.actor.sheet_control.regrip_time,deck.actor.hike,deck.actor.seat_side]

func clear_load() -> void:
	_cancel_contact()
	purchase_pending=false
	purchase_task.cancel()
	purchase_result.clear()
	deck.complete_sheet.rig.release_purchase(false)
	pending_action=""
	deck_contact_preview=false
	deck.complete_sheet.rig_constraint.spatial_guide_state=null
	deck.complete_sheet.rig.traveller_pose_locked=false
	deck.complete_sheet.rig.traveller_override=Vector3(NAN,NAN,NAN)
	deck.complete_sheet.clear_rig_pitch()
	deck.basis=Basis.IDENTITY
	solver=EQUILIBRIUM.new(deck.complete_sheet.rig)
	solver.model.initial_vang_tail=vang_reference
	traveller_solver=TRAVELLER.new(solver)
	traveller_result.clear()
	result.clear()
	message="기본 메인시트 리그로 복귀했어요. 조작한 줄 길이는 유지해요."
	deck.controls.refresh()
	_display_deformation()
	_refresh_status()

func show_slack_example() -> Dictionary:
	# An explicit inspection preset, never automatic playback or steering.
	if deck.session.wheel_pull.state!="REST":
		deck.session.wheel_pull.pause()
		message="처짐 예제는 손이 기본 자세로 복귀한 뒤 눌러 주세요."
		_refresh_status()
		return {"valid":false,"reason":"wait for hand return"}
	clear_load()
	var sheet: Node3D=deck.complete_sheet
	sheet.rig.set_angles(deg_to_rad(65),deg_to_rad(-6),false)
	sheet.ledger.transfer(sheet.ledger.rig_metres-sheet.rig.length_metres())
	deck.session.wheel_pull.bind_length_budget(sheet.ledger)
	sheet.geometry_key.clear()
	sheet.update_geometry()
	for index in 4: sliders[index].value=[.4,5.0,0.0,0.0][index]
	sheet.rig.set_angles(deg_to_rad(65),deg_to_rad(-6),false)
	solver=EQUILIBRIUM.new(sheet.rig)
	vang_reference=solver.model.initial_vang_tail
	traveller_solver=TRAVELLER.new(solver)
	var applied := solve_load()
	show_rig()
	return applied

func show_rig() -> void:
	deck.set_view(7)

func show_deck_contact_example(settle_block := true,prepared: Dictionary={}) -> Dictionary:
	var transaction_started := Time.get_ticks_usec()
	var transaction_profile := []
	var application_hands := [deck.actor.palm_boat("Left"),deck.actor.palm_boat("Right")]
	if not prepared.is_empty():
		if not prepared.has_all(["block","rope","boundary","target"]) or not prepared.block.get("valid",false) or not prepared.rope.get("valid",false):
			return {"valid":false,"reason":"incomplete prepared contact result"}
	# Constrained upper swivel on the locked lower traveller, not full dynamics.
	if deck.session.wheel_pull.state!="REST" or not deck.session.support_reason().is_empty():
		message="갑판 접촉 예제는 좌현·앉은 기본 자세에서 손 복귀 후 확인해 주세요."
		return {"valid":false,"reason":"deck example requires supported resting posture"}
	var sheet: Node3D=deck.complete_sheet
	var previous := _traveller_snapshot()
	var previous_rig: float=sheet.ledger.rig_metres
	var old_solver: RefCounted=solver
	var old_traveller: RefCounted=traveller_solver
	var old_frame := deck.basis
	var old_result := result.duplicate(true)
	var old_traveller_result := traveller_result.duplicate(true)
	var old_preview := deck_contact_preview
	var old_key := solved_key.duplicate()
	clear_load()
	transaction_profile.append({"stage":"clear","ms":(Time.get_ticks_usec()-transaction_started)/1000.0})
	var yaw := deg_to_rad(45)
	var pitch := deg_to_rad(-6)
	sheet.rig.set_angles(yaw,pitch,false)
	var wanted: float=sheet.rig.length_metres()+1.0
	sheet.ledger.transfer(sheet.ledger.rig_metres-wanted)
	sheet.cockpit.reset_motion()
	transaction_profile.append({"stage":"setup","ms":(Time.get_ticks_usec()-transaction_started)/1000.0})
	if prepared.has("lead"):
		sheet.cockpit.supported_lead=prepared.lead
		sheet.cockpit.supported_lead.last_revision=deck.actor.sheet_study.manual_revision
	var resting: Dictionary=prepared.get("block",{})
	if resting.is_empty():
		if not settle_block: resting={"valid":true}
		elif spatial_contact_enabled: resting=CONTACT_TASK._block(_example_snapshot())
		else: resting=block_support.settle(sheet.rig,Vector3(0,-9.81,0))
	var applied := resting
	if resting.valid:
		if settle_block: sheet.rig.lock_traveller_pose(resting.pose)
		if resting.get("spatial",false):
			var state := SPATIAL_GUIDE.new()
			state.setup(resting.pose,yaw,pitch,sheet.rig.tiller_angle)
			sheet.rig_constraint.spatial_guide_state=state
		if settle_block and not prepared.has("rope"):
			# Synchronous diagnostics use the identical detached numeric solver.
			# Normal UI requests always prepare this on the owned worker.
			var snapshot := _example_snapshot(resting)
			prepared={"rope":CONTACT_TASK._rope(snapshot),"boundary":snapshot.path}
		if prepared.has("rope"):
			sheet.rig_constraint.prepare_drape_boundary(yaw,pitch)
			if not sheet.rig_constraint.accept_prepared(wanted,yaw,pitch,Vector3.DOWN,prepared.boundary,prepared.rope):
				resting={"valid":false,"reason":"prepared contact boundary changed"}
				applied=resting
	if resting.valid:
		applied=sheet.try_free_rig(yaw,pitch,Vector3.DOWN,false)
		transaction_profile.append({"stage":"apply","ms":(Time.get_ticks_usec()-transaction_started)/1000.0})
		transaction_profile.append({"stage":"cockpit","timings":sheet.cockpit.last_timings.duplicate(true)})
		if applied.valid: sheet.update_geometry(true)
		transaction_profile.append({"stage":"display","ms":(Time.get_ticks_usec()-transaction_started)/1000.0})
		if settle_block: applied["block_contact"]=resting
	if not applied.valid or not applied.get("hull_supported",false):
		sheet.ledger.transfer(sheet.ledger.rig_metres-previous_rig)
		solver=old_solver
		traveller_solver=old_traveller
		applied["valid"]=false
		applied["restore_failed"]=not _restore_traveller(previous)
		deck.basis=old_frame
		result=old_result
		traveller_result=old_traveller_result
		deck_contact_preview=old_preview
		solved_key=old_key
		message="갑판 접촉 예제를 적용하지 못해 이전 상태로 복원했어요." if not applied.restore_failed else "갑판 접촉 예제와 이전 경로 복원에 실패했어요. 트림 리셋 후 확인해 주세요."
	else:
		deck.session.wheel_pull.bind_length_budget(sheet.ledger)
		solver=EQUILIBRIUM.new(sheet.rig)
		solver.model.initial_vang_tail=vang_reference
		traveller_solver=TRAVELLER.new(solver)
		deck_contact_preview=true
		solved_key=_boundary_key()
		message="갑판 접촉 예제 · 위 블록 3축 자중·접촉 / 전체 줄 힘 평형 아님\n아래 블록·붐 지지 고정 · 조작하면 일반 검수로 복귀" if resting.get("spatial",false) else ("갑판 접촉 예제 · 위 블록 자중·접촉 / 전체 하중 평형 아님\n아래 블록·붐 지지 고정 · 조작하면 일반 검수로 복귀" if settle_block else "고정 블록 접촉 진단")
		# Keep the current view and authored hand sample. A camera change is
		# optional via the existing view controls, not part of material setup.
		applied["inspection_only"]=true
	deck.controls.refresh()
	_refresh_status()
	applied["transaction_profile"]=transaction_profile
	applied["hand_pose_unchanged"]=application_hands==[deck.actor.palm_boat("Left"),deck.actor.palm_boat("Right")]
	return applied

func _contact_key() -> Array:
	var sheet: Node3D=deck.complete_sheet
	return [_boundary_key(),deck.session.mode,deck.session.selected_system,deck.session.requested_hike,deck.session.requested_side,deck.session.wheel_pull.state,sheet.rig.hull.mesh,sheet.rig.global_transform.affine_inverse()*sheet.rig.hull.global_transform,sheet.rig.tiller_angle,sheet.rig_constraint.HANGING.exit_turn_metres,spatial_contact_enabled]

func _example_snapshot(block: Dictionary={}) -> Dictionary:
	# Temporarily calculate guide geometry without uploading any visible rope.
	# Restore the live rig before returning to the event loop.
	var rig: Node3D=deck.complete_sheet.rig
	var old := _traveller_snapshot()
	var old_path: PackedVector3Array=rig.route.duplicate()
	var old_fixed: PackedVector3Array=rig.fixed_end.duplicate()
	var old_opening: float=rig.opening
	var old_wraps: Dictionary=rig.wraps.duplicate(true)
	rig.traveller_override=Vector3(NAN,NAN,NAN)
	rig.traveller_pose_locked=false
	rig.set_angles(deg_to_rad(45),deg_to_rad(-6),false)
	var target: float=rig.length_metres()+1.0
	if not block.is_empty():
		if block.get("spatial",false):
			var moved := SPATIAL_GUIDE.MOVING.move(rig.route,rig.wraps,"traveller",rig.traveller.transform,block.pose)
			rig.traveller.transform=block.pose
			rig.lock_traveller_pose(block.pose)
			rig.route=moved.path
			rig.wraps=moved.wraps
		else:
			rig.lock_traveller_pose(block.pose)
			rig.set_angles(deg_to_rad(45),deg_to_rad(-6),false)
	var inverse: Transform3D=rig.global_transform.affine_inverse()
	var snapshot := {"target":target,"path":rig.route.duplicate(),"wraps":rig.wraps.duplicate(true),"gravity":Vector3.DOWN,"hull":rig.hull.mesh.get_faces(),"hull_frame":inverse*rig.hull.global_transform}
	snapshot["exit_turn"]=deck.complete_sheet.rig_constraint.HANGING.exit_turn_metres
	if block.is_empty():
		snapshot.merge({"rest":rig.traveller.transform,"attachment":rig.traveller.rope_anchor_local(&"attachment"),"tiller_inverse":rig.traveller_tiller_frame().affine_inverse(),"gravity":Vector3(0,-9.81,0)},true)
		if spatial_contact_enabled:
			var faces := PackedVector3Array()
			for record: Dictionary in CONTACT_TASK.OBSTACLE.capture_tree(rig.traveller,rig.traveller.global_transform.affine_inverse()):
				faces.append_array(record.frame*record.faces)
			var obstacles := CONTACT_TASK.OBSTACLE.capture_tree(rig.hull,inverse)
			obstacles.append_array(CONTACT_TASK.OBSTACLE.capture_tree(rig.traveller_lower,inverse))
			var tiller: Transform3D=rig.traveller_tiller_frame()
			snapshot.merge({"spatial":true,"body":faces,"block_obstacles":obstacles,"block_lines":[{"path":PackedVector3Array([tiller*Vector3(0,0,-.490),tiller*Vector3(0,0,.490)]),"radius":.0128,"label":"tiller"}]},true)
		else:
			snapshot.merge({"body":CONTACT_TASK.BLOCK.body_faces(rig.traveller),"lower":CONTACT_TASK.BLOCK.body_faces(rig.traveller_lower),"lower_frame":rig.traveller_lower.transform},true)
	else:
		var records := []
		for part in [rig.aft,rig.traveller,rig.traveller_lower,rig.traveller_link,rig.forward_block,rig.guide,deck.ratchet,rig.boom]:
			records.append_array(CONTACT_TASK.OBSTACLE.capture_tree(part,inverse))
		snapshot["obstacles"]=records
		# The first 30 mm adjoins the same material at the becket; all of the
		# separate stopper knot and blue traveller line remain obstacles.
		var fixed_start := 0
		var fixed_distance := 0.0
		while fixed_start<rig.fixed_end.size()-2 and fixed_distance<.030:
			fixed_distance+=rig.fixed_end[fixed_start].distance_to(rig.fixed_end[fixed_start+1])
			fixed_start+=1
		snapshot["contact_lines"]=[{"path":rig.traveller_path.duplicate(),"radius":.003,"label":"traveller line"},{"path":rig.fixed_end.slice(fixed_start),"radius":.004,"label":"fixed stopper"}]
	rig.traveller_override=old.override
	rig.traveller_pose_locked=old.block_locked
	rig.traveller_pose_override=old.block_pose
	rig.traveller_pose_boundary=old.block_boundary
	deck.complete_sheet.rig_constraint.prepare_drape_boundary(old.angles.x,old.angles.y)
	rig.route=old_path
	rig.wraps=old_wraps
	rig.fixed_end=old_fixed
	rig.opening=old_opening
	return snapshot

func begin_deck_contact() -> Dictionary:
	if contact_busy(): return {"valid":false,"queued":true,"reason":"contact calculation in progress"}
	if deck.session.wheel_pull.state!="REST" or not deck.session.support_reason().is_empty():
		message="갑판 접촉 예제는 좌현·앉은 기본 자세에서 손 복귀 후 확인해 주세요."
		return {"valid":false,"reason":"deck example requires supported resting posture"}
	contact_ticket=_contact_key()
	contact_cancelled=false
	contact_prepared.clear()
	contact_started_usec=Time.get_ticks_usec()
	# The first raw render-array read can be cold. Keep it off the input
	# dispatch frame and separate it from the pose/material snapshot work.
	contact_task.stage="snapshot_geometry" if spatial_contact_enabled else "snapshot"
	message="블록 접촉 계산 중 · 시점 이동 가능 / 조작하면 취소"
	return {"valid":false,"queued":true,"reason":"contact calculation in progress"}

func _cancel_contact() -> void:
	purchase_pending=false
	purchase_task.cancel()
	if contact_busy():
		contact_cancelled=true
		contact_task.cancel()

func contact_busy() -> bool:
	return purchase_pending or purchase_task.worker!=null or contact_task.worker!=null or contact_task.stage in ["snapshot_geometry","snapshot","cockpit","commit"]

func _purchase_key() -> Array:
	var sheet: Node3D=deck.complete_sheet
	# Use the independent requested controls, not a reconstructed Euler angle
	# after the temporary numeric snapshot round-trips a float32 basis.
	return [_boundary_key(),sheet.requested_rig_pitch if is_finite(sheet.requested_rig_pitch) else "manual",sheet.free_rig_yaw if is_finite(sheet.free_rig_yaw) else "taut",deck.basis,deck.actor.rudder_angle(),deck.session.mode,deck.session.selected_system,deck.session.wheel_pull.state,deck.actor.look_enabled,deck.actor.look_pose.yaw,deck.actor.look_pose.pitch]

func begin_purchase(example := false,contact_example := false) -> Dictionary:
	if not deck.session.support_reason().is_empty(): return {"valid":false,"reason":"supported resting posture required"}
	var steering := -.5 if contact_example else 0.0
	if example and absf(deck.actor.amount-steering)>.000001:
		message="기준 검수의 조타 조건이 달라요. 상단 검수 버튼으로 시작해 주세요."
		return {"valid":false,"reason":"reference inspection steering mismatch"}
	if not deck.complete_sheet.rig.coupled.is_empty():
		message="현재 조건의 줄·블록 정적 평형이 적용되어 있어요. 조작하면 해제돼요."
		return purchase_result.duplicate(true)
	purchase_ticket=_purchase_key()
	purchase_pending=true
	purchase_example=example
	purchase_example_angles=Vector2(deg_to_rad(45 if contact_example else 25),deg_to_rad(-6))
	message="줄·블록 평형 계산 준비 중 · 조작/대기 취소 시 이전 표시 유지"
	return {"valid":false,"queued":true,"reason":"purchase calculation queued"}

func _advance_purchase() -> void:
	if not purchase_pending and purchase_task.worker==null: return
	if purchase_ticket!=_purchase_key():
		purchase_pending=false
		purchase_task.cancel()
	if purchase_pending:
		purchase_pending=false
		var rig: Node3D=deck.complete_sheet.rig
		var previous: Vector2=deck.complete_sheet.rig_constraint.angles()
		if purchase_example: rig.set_angles(purchase_example_angles.x,purchase_example_angles.y,false)
		var snapshot: Dictionary=rig.purchase_snapshot(5.0)
		snapshot.load.gravity=rig.global_basis.inverse()*Vector3(0,-9.81,0)
		if purchase_example: rig.set_angles(previous.x,previous.y,false)
		if purchase_task.start(snapshot)!=OK:
			last_action={"valid":false,"reason":"purchase worker could not start"}
			message="계산을 시작하지 못해 이전 표시를 유지했어요."
		else: message="줄·블록 평형/간섭 계산 중 · 시트 5 N 시험 하중 / 조작하면 취소"
		return
	if not purchase_task.ready(): return
	var calculated: Dictionary=purchase_task.take()
	if not calculated.get("accepted",false) or purchase_ticket!=_purchase_key():
		last_action=calculated
		var reason: String=calculated.get("reason","")
		var description := "현재 조건에서 평형·정밀도 검사를 통과하지 못했어요."
		if "finite geometry" in reason: description="줄·부품 간섭이 있어 접촉 평형이 더 필요한 조건이에요."
		elif "cancel" in reason or purchase_ticket!=_purchase_key(): description="조건 변경 또는 취소 요청을 반영했어요."
		message="새 평형 미적용 · 현재 조작과 표시 유지\n"+description
		return
	contact_ticket=_contact_key()
	contact_cancelled=false
	contact_prepared={"purchase":calculated,"rope":{"path":calculated.path},"target":calculated.rig_metres}
	contact_task.stage="cockpit"
	message="평형 통과 · 손·콕핏 줄 경로 준비 중 / 조작하면 취소"

func _apply_purchase(calculated: Dictionary) -> Dictionary:
	var sheet: Node3D=deck.complete_sheet
	var before: float=sheet.ledger.rig_metres
	var previous_angles: Vector2=sheet.rig_constraint.angles()
	var transfer: float=before-calculated.rig_metres
	if absf(sheet.ledger.transferable(transfer)-transfer)>.0000001:
		message="콕핏 여유 줄이 부족해 적용하지 않았어요. 기존 트림 유지"
		return {"valid":false,"reason":"complete material allocation rejected"}
	var hands := [deck.actor.palm_boat("Left"),deck.actor.palm_boat("Right")]
	var prior_lead: RefCounted=sheet.cockpit.supported_lead
	# Keep the rollback history untouched while building the candidate tail.
	sheet.cockpit.supported_lead=contact_prepared.get("lead",prior_lead.get_script().new())
	sheet.ledger.transfer(transfer)
	sheet.rig.set_angles(calculated.angles.x,calculated.angles.y,false)
	calculated=calculated.duplicate(true)
	calculated["hand_boundary"]=sheet.coupled_hand_boundary()
	sheet.rig.install_purchase(calculated,false)
	sheet.geometry_key.clear()
	if not sheet.update_geometry(false):
		sheet.rig.release_purchase(false)
		sheet.rig.set_angles(previous_angles.x,previous_angles.y,false)
		sheet.ledger.transfer(sheet.ledger.rig_metres-before)
		sheet.cockpit.supported_lead=prior_lead
		sheet.geometry_key.clear()
		var restored: bool=sheet.update_geometry()
		message="전체 줄 경로가 맞지 않아 이전 상태로 복원했어요."
		return {"valid":false,"reason":"complete cockpit rejected purchase","restore_failed":not restored}
	sheet.update_geometry(true)
	deck.session.wheel_pull.bind_length_budget(sheet.ledger)
	purchase_result=calculated.duplicate(true)
	purchase_result["hand_pose_unchanged"]=hands==[deck.actor.palm_boat("Left"),deck.actor.palm_boat("Right")]
	solved_key=_boundary_key()
	purchase_applied_key=_purchase_key()
	# Reframe the newly moved pair only if the user has not navigated while
	# waiting. Camera-only input must neither cancel nor restart the solve.
	if purchase_focus and deck.selected_view==8 and deck.camera.transform==purchase_focus_camera:
		deck.set_view(8)
	purchase_focus=false
	message="줄·블록 정적 평형 적용 · 전체 14 m\n콕핏 배분 %+.3f m · 시트 5 N 시험\n조작하면 일반 검수로 복귀" % transfer
	deck.controls.refresh()
	return purchase_result.duplicate(true)

func _contact_look_key() -> Array:
	return [deck.actor.look_enabled,deck.actor.look_pose.yaw,deck.actor.look_pose.pitch]

func _prepare_contact_lead() -> void:
	# The approved cold lead projection is kept unchanged, but prepared in
	# bounded sweeps across frames. No live material or visible rope changes.
	if contact_prepared.has("lead_steps") and contact_prepared.look_key==_contact_look_key():
		_advance_contact_lead()
		return
	contact_task.stage="cockpit"
	var cockpit: RefCounted=deck.complete_sheet.cockpit
	var actor: Node3D=deck.actor
	var candidate: RefCounted=cockpit.supported_lead.get_script().new()
	var target: float=contact_prepared.target
	var budget: float=deck.complete_sheet.ledger.cockpit_metres+deck.complete_sheet.ledger.rig_metres-target
	var raw: PackedVector3Array
	actor.sheet_study.manual_cache_revision=-1
	if candidate.has_method("needs_full_prefix") and not candidate.needs_full_prefix() and actor.sheet_control.continuous_relay:
		raw=candidate.contact_prefix(actor.sheet_control.regrip.held_points(),actor)
	elif actor.sheet_control.regrip_time>=0: raw=actor.sheet_control.regrip.rope_points(.16)
	else: raw=actor.sheet_study.manual_points(.16)
	var held: int=actor.sheet_study.MANUAL_HELD_SEGMENTS
	if cockpit.expanded_contact_support:
		var previous_path: PackedVector3Array=cockpit.rig_clearance_path
		cockpit.rig_clearance_path=contact_prepared.rope.path
		cockpit._clear_loaded_rig_contact(raw,held)
		cockpit.rig_clearance_path=previous_path
	if candidate.has_method("set_material_budget"):
		candidate.set_material_budget(budget,cockpit.floor_lay.minimum_path.slice(0,17),cockpit.material_floor_path)
	var steps := LEAD_PREPARATION.new()
	steps.begin(raw.slice(0,held+21),cockpit.floor_lay.minimum_path[0],actor,cockpit.hull,contact_prepared.rope.path,cockpit.expanded_contact_support)
	contact_prepared["lead"]=candidate
	contact_prepared["lead_steps"]=steps
	contact_prepared["lead_holder"]=actor.sheet_control.regrip.time>=.8 and actor.sheet_control.regrip.time<2
	contact_prepared["look_key"]=_contact_look_key()
	_advance_contact_lead()

func _advance_contact_lead() -> void:
	var steps: RefCounted=contact_prepared.lead_steps
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<3000:
		if not steps.advance(): continue
		var candidate: RefCounted=contact_prepared.lead
		candidate.history=steps.history
		candidate.last_revision=steps.last_revision
		candidate.last_pass_count=steps.last_pass_count
		if candidate.has_method("set_material_budget"):
			candidate.full_history=steps.result
			candidate.rest_length=candidate._length(steps.history)
			candidate.previous_cockpit=candidate.cockpit_length
			candidate.previous_fixed_length=candidate._length(steps.fixed)
			candidate.previous_holder=contact_prepared.lead_holder
			candidate.contact_stretch={"supports":0.0,"self":0.0,"floor":0.0,"pushes":{}}
		contact_task.stage="commit"
		return

func _advance_contact() -> void:
	# The purchase worker has its own ticket. Do not cancel it by comparing
	# an unrelated, inactive deck-contact ticket with the current scene.
	if contact_task.worker==null and contact_task.stage not in ["snapshot_geometry","snapshot","cockpit","commit"]: return
	if contact_ticket!=_contact_key(): _cancel_contact()
	if contact_task.stage in ["snapshot_geometry","snapshot"]:
		if contact_cancelled:
			contact_task.stage=""
			last_action={"valid":false,"cancelled":true,"reason":"contact snapshot cancelled"}
			message="접촉 계산 취소 · 현재 조작과 표시를 유지했어요."
		elif contact_task.stage=="snapshot_geometry":
			var rig: Node3D=deck.complete_sheet.rig
			for part in [rig.hull,rig.traveller,rig.traveller_lower]:
				CONTACT_TASK.OBSTACLE.capture_tree(part,Transform3D.IDENTITY)
			contact_task.stage="snapshot"
		elif contact_task.start_block(_example_snapshot())!=OK:
			contact_task.stage=""
			last_action={"valid":false,"reason":"contact worker could not start"}
		return
	if contact_task.stage in ["cockpit","commit"]:
		if contact_cancelled:
			contact_task.stage=""
			contact_prepared.clear()
			last_action={"valid":false,"cancelled":true,"reason":"contact request cancelled or boundary changed"}
			message="접촉 계산 취소 · 현재 조작과 표시를 유지했어요."
		elif contact_task.stage=="cockpit" or contact_prepared.look_key!=_contact_look_key():
			_prepare_contact_lead()
		else:
			contact_task.stage=""
			last_action=_apply_purchase(contact_prepared.purchase) if contact_prepared.has("purchase") else show_deck_contact_example(true,contact_prepared)
			solve_ms=(Time.get_ticks_usec()-contact_started_usec)/1000.0
			contact_prepared.clear()
		return
	if not contact_task.ready(): return
	var phase: String=contact_task.stage
	var calculated: Dictionary=contact_task.take()
	if contact_cancelled:
		contact_prepared.clear()
		last_action={"valid":false,"cancelled":true,"reason":"contact request cancelled or boundary changed"}
		message="접촉 계산 취소 · 현재 조작과 표시를 유지했어요."
		return
	if not calculated.get("valid",false):
		last_action=calculated
		message="접촉 계산을 적용하지 않았어요. 현재 표시를 유지해요."
		return
	if phase=="block":
		contact_prepared["block"]=calculated
		var snapshot := _example_snapshot(calculated)
		contact_prepared["boundary"]=snapshot.path
		contact_prepared["target"]=snapshot.target
		if contact_task.start_rope(snapshot)!=OK:
			last_action={"valid":false,"reason":"rope worker could not start"}
			message="줄 계산을 시작하지 못해 현재 표시를 유지했어요."
		else: message="시트 접촉 계산 중 · 시점 이동 가능 / 조작하면 취소"
	else:
		contact_prepared["rope"]=calculated
		contact_task.stage="cockpit"
		message="접촉 결과 준비 중 · 시점 이동 가능 / 조작하면 취소"

func _exit_tree() -> void:
	contact_task.finish()
	purchase_task.finish()

func set_diagram(value: bool) -> void:
	diagram_enabled=value
	mast.visible=value
	sail.visible=value
	for part in ["LowerMast","UpperMast"]: deck.complete_sheet.rig.get_node(part).visible=not value
	if value: _display_deformation()

func _mast_at(height: float) -> Vector3:
	return EQUILIBRIUM.LOAD.MAST.point_at(solver.model.mast_tip,height)

func _display_deformation() -> void:
	if mast==null or not diagram_enabled: return
	var key := [solver.model.mast_tip,deck.complete_sheet.rig.boom_pivot.transform]
	if key==deformation_key: return
	deformation_key=key
	var contract=EQUILIBRIUM.LOAD.CONTRACT
	var points := PackedVector3Array()
	for index in 49: points.append(_mast_at(contract.MAST_BASE.y+6.155*index/48.0))
	mast.show_path(points)
	var clew: Vector3=deck.complete_sheet.rig.boom_pivot.transform*contract.CLEW_LOCAL
	var head: Vector3=_mast_at(contract.SAIL_HEAD.y)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 24:
		var h0 := row/24.0
		var h1 := (row+1)/24.0
		var vertices := [_mast_at(lerpf(contract.GOOSE.y+.060,contract.SAIL_HEAD.y,h0)),clew.lerp(head,h0),clew.lerp(head,h1),_mast_at(lerpf(contract.GOOSE.y+.060,contract.SAIL_HEAD.y,h1))]
		for index in [0,1,2,0,2,3]: builder.add_vertex(vertices[index])
	builder.generate_normals()
	sail.mesh=builder.commit()

func _refresh_status() -> void:
	if status==null: return
	deck.controls.refresh()
	var sheet: Node3D=deck.complete_sheet
	var q: Vector2=sheet.rig_constraint.angles()
	status.text=message
	details.text="전체 %.3f m · 길이 오차 %.3f mm\n붐 좌우 %.2f° / 높이 %.2f°" % [sheet.ledger.total_metres,sheet.last_result.get("total_error_metres",0.0)*1000,rad_to_deg(q.x),rad_to_deg(q.y)]
	if result.get("valid",false): details.text+="\n직전 해: 시트 %.2f N / 붐뱅 %.1f N · %.0f ms" % [result.sheet_tension_n,result.loads.cascade.boom_tension_n,solve_ms]
	if not sheet.rig.coupled.is_empty():
		details.text+="\n하부/상부·붐 뒤 정적 평형 · %.2f N\n트래블러 전체 %.6f m · 표시 오차 %.3f mm\n블록 지지 반력 %.3f N · 뒤 구간129표본\n아이 안쪽 줄은 기하 경로 / 마찰·안정성·동역학 미인증" % [purchase_result.support_tension,purchase_result.traveller_material_metres,purchase_result.traveller_render_error_m*1000,purchase_result.get("lower_contact_n",0.0)]
	if is_finite(sheet.free_rig_yaw):
		details.text+="\n중력 처짐 · 줄 자체 무게의 장력은 미포함"
	if sheet.last_result.get("hull_supported",false):
		details.text+="\n실제 갑판 메시 접촉 · 줄 길이 보존\n위 블록 정적 접촉 / 고리 표면 접촉은 미적용\n전체 마찰·실시간 이동 미연결"
	if traveller_result.get("valid",false):
		var names := {"stick":"마찰 유지","slip settled":"이동 후 정지","stop":"검수 경계 도달"}
		details.text+="\n트래블러 %s / x %.3f m\n장착 줄 %.4f m" % [names.get(traveller_result.state,traveller_result.state),traveller_result.x,traveller_result.rest_length]
	details.text+="\n정적 시험 / 실시간 항해 미적용\n연결부 치수·질량은 잠정, 시트 5 N 검수용.\n기존 세일 진단의 마찰·±0.455 m 한계는 별도.\n세일/마스트는 변형 도식, 손 조작 미연결."

func _build_ui() -> void:
	var column: VBoxContainer=deck.controls.rig_column
	status=Label.new()
	status.add_theme_font_size_override("font_size",16)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	var settings := Label.new()
	settings.text="연결부 검수: 5 N 시험 하중 · 전체 줄 14 m 유지"
	column.add_child(settings)
	var preset := OptionButton.new()
	preset.name="TravellerCondition"
	preset.focus_mode=Control.FOCUS_NONE
	preset.add_item("기준: 붐 25° · 중립 조타")
	preset.add_item("접촉: 붐 45° · 조타 −6°")
	preset.tooltip_text="상단 검수 버튼이 이 조건을 준비해요. 트림과 조타가 바뀌며 5 N 정적 시험이에요."
	preset.item_selected.connect(func(index: int):
		inspection_preset=index
		deck.controls.refresh())
	column.add_child(preset)
	var row := HBoxContainer.new()
	column.add_child(row)
	for entry in [["연결부 확인 (트림 변경)",inspect_traveller],["현재 조건 계산",func(): request_action("load")]]:
		_button(row,entry[0],entry[1])
	row=HBoxContainer.new()
	column.add_child(row)
	_button(row,"정적 검수 해제",clear_load)
	_button(row,"대기 취소",cancel_request)
	row=HBoxContainer.new()
	column.add_child(row)
	_button(row,"전체 리그 보기",show_rig)
	_button(row,"선미 확대",show_traveller)
	var diagram := CheckButton.new()
	diagram.text="세일·마스트 변형 도식 표시"
	diagram.focus_mode=Control.FOCUS_NONE
	diagram.toggled.connect(set_diagram)
	column.add_child(diagram)
	var extra := VBoxContainer.new()
	extra.visible=false
	var toggle := CheckButton.new()
	toggle.text="진단 수치 / 예제"
	toggle.focus_mode=Control.FOCUS_NONE
	toggle.toggled.connect(func(value: bool): extra.visible=value)
	column.add_child(toggle)
	column.add_child(extra)
	details=Label.new()
	details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	extra.add_child(details)
	var legacy := Label.new()
	legacy.text="아래 설정: 기존 세일 하중 진단 전용"
	extra.add_child(legacy)
	_slider(extra,"붐뱅 회수량 (m)",-.15,.45,0)
	_slider(extra,"바람 X 성분 (m/s)",0,8,5)
	_slider(extra,"선체 기울기 (°)",-25,25,0)
	_slider(extra,"상하 가속도 (m/s²)",-2,2,0)
	_slider(extra,"트래블러 정지 마찰 (잠정)",0,1,.2)
	_button(extra,"기존 트래블러 중앙 배치",func(): request_action("center"))
	_button(extra,"처짐 예제 (트림·설정 변경)",func(): request_action("slack"))
	_button(extra,"갑판 접촉 예제 (트림 변경)",func(): request_action("deck"))
	_button(extra,"기존 세일 하중 진단",solve_traveller)

func show_traveller() -> void:
	deck.set_view(8)

func _button(parent: Node,title: String,callback: Callable) -> void:
	var button := Button.new()
	button.text=title
	button.focus_mode=Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)

func _failure_message(failure: Dictionary) -> String:
	var reason: String=failure.get("reason","")
	if "deck/support contact" in reason:
		return "적용 불가 · 무하중 블록/트래블러의 갑판 지지는 아직 미지원이에요.\n현재 트림과 표시를 유지했어요. 줄을 조금 당기고 다시 계산해 주세요."
	if "hull contact" in reason or "requires folds" in reason:
		return "적용 불가 · 이 접촉에서는 줄 접힘이나 블록 위치 조정이 더 필요해요.\n현재 트림과 표시를 유지했어요."
	if "allocation" in reason or "geometric domain" in reason:
		return "적용 불가 · 이 트림에서는 요청 위치의 줄 길이/각도 조건이 맞지 않아요.\n현재 트림과 표시를 유지했어요. 시트를 조금 풀고 다시 시도해 주세요."
	if "residual" in reason or "iteration" in reason:
		return "적용 불가 · 현재 극단 트림/하중 조합에서는 계산이 수렴하지 않았어요.\n트림과 표시를 유지했어요. 시트를 조금 풀거나 하중 설정을 바꿔 주세요."
	return "적용 불가 · 현재 조건의 정적 평형을 구하지 못했어요.\n트림과 표시 유지 · 원인: "+reason

func _slider(parent: Node,title: String,low: float,high: float,value: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text=title
	label.custom_minimum_size.x=185
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value=low
	slider.max_value=high
	slider.step=.01
	slider.value=value
	slider.custom_minimum_size.x=140
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	slider.focus_mode=Control.FOCUS_NONE
	row.add_child(slider)
	var number := Label.new()
	number.custom_minimum_size.x=50
	number.text="%.2f" % value
	row.add_child(number)
	slider.value_changed.connect(func(current: float): number.text="%.2f" % current)
	sliders.append(slider)
