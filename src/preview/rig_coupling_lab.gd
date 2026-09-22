extends Node3D

## Exact sheet/hand integration with a manually requested static load solve.
## The additional control is a test actuator, not an authored vang hand action.
const EQUILIBRIUM := preload("res://src/boat/rig_equilibrium.gd")
const TRAVELLER := preload("res://src/boat/traveller_equilibrium.gd")
const LINE := preload("res://src/boat/rope_view.gd")
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
var message := "설정 후 '하중 평형 계산'을 눌러 주세요."
var solved_key := []
var pending_action := ""
var last_action := {}
var diagram_enabled := false
var deformation_key := []
var details: Label
var vang_reference := 0.0

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

func advance() -> void:
	if deck.complete_sheet.rig.traveller_override.is_finite() and solved_key!=_boundary_key():
		var queued := pending_action
		clear_load()
		pending_action=queued
		message="조작 조건이 바뀌어 트래블러 정적 검수를 해제했어요. 다시 계산해 주세요."
	elif not deck.complete_sheet.last_result.get("valid",false):
		deck.complete_sheet.clear_rig_pitch()
		message="현재 줄 길이는 이 높이와 함께 유지할 수 없어 기본 리그로 복귀했어요."
		result.clear()
	elif result.get("valid",false) and solved_key!=_boundary_key():
		message="시트/손 위치가 바뀌었어요. 아래 장력은 이전 조건이며 재계산이 필요해요."
	if not pending_action.is_empty() and deck.session.wheel_pull.state=="REST":
		var action := pending_action
		pending_action=""
		request_action(action)
	_display_deformation()
	_refresh_status()

func request_action(action: String) -> Dictionary:
	if action not in ["center","load","slack"]:
		return {"valid":false,"reason":"unknown inspection request"}
	deck.session.wheel_pull.pause()
	if deck.session.wheel_pull.state!="REST":
		pending_action=action
		message="손 복귀 후 실행할게요. 다시 누를 필요 없어요. [대기 취소]로 취소 가능"
		_refresh_status()
		return {"valid":false,"queued":true,"reason":"wait for hand return"}
	pending_action=""
	match action:
		"center": last_action=place_traveller_center()
		"load": last_action=solve_traveller()
		"slack": last_action=show_slack_example()
	_refresh_status()
	return last_action.duplicate(true)

func cancel_request() -> void:
	pending_action=""
	message="대기 요청을 취소했어요. 조작한 줄 길이는 유지해요."
	_refresh_status()

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
	return {"override":sheet.rig.traveller_override,"pitch":sheet.requested_rig_pitch,"free_yaw":sheet.free_rig_yaw,"gravity":sheet.free_rig_gravity,"angles":sheet.rig_constraint.angles(),"mast":solver.model.mast_tip,"loads":solver.model.last.duplicate(true),"last":solver.last.duplicate(true)}

func _restore_traveller(previous: Dictionary) -> bool:
	var sheet: Node3D=deck.complete_sheet
	sheet.rig.traveller_override=previous.override
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
	pending_action=""
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
	var sheet: Node3D=deck.complete_sheet
	var q: Vector2=sheet.rig_constraint.angles()
	status.text=message
	details.text="전체 %.3f m · 길이 오차 %.3f mm\n붐 좌우 %.2f° / 높이 %.2f°" % [sheet.ledger.total_metres,sheet.last_result.get("total_error_metres",0.0)*1000,rad_to_deg(q.x),rad_to_deg(q.y)]
	if result.get("valid",false): details.text+="\n직전 해: 시트 %.2f N / 붐뱅 %.1f N · %.0f ms" % [result.sheet_tension_n,result.loads.cascade.boom_tension_n,solve_ms]
	if is_finite(sheet.free_rig_yaw):
		details.text+="\n중력 처짐 · 줄 자체 무게의 장력은 미포함"
	if traveller_result.get("valid",false):
		var names := {"stick":"마찰 유지","slip settled":"이동 후 정지","stop":"검수 경계 도달"}
		details.text+="\n트래블러 %s / x %.3f m\n장착 줄 %.4f m" % [names.get(traveller_result.state,traveller_result.state),traveller_result.x,traveller_result.rest_length]
	details.text+="\n정적 시험 / 실시간 항해 미적용\n질량·마찰·±0.455 m 한계는 잠정.\n세일/마스트는 변형 도식, 손 조작 미연결."

func _build_ui() -> void:
	var column: VBoxContainer=deck.controls.rig_column
	status=Label.new()
	status.add_theme_font_size_override("font_size",16)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	var settings := Label.new()
	settings.text="설정 변경 후 계산 · 시트 길이는 그대로 유지"
	column.add_child(settings)
	var row := HBoxContainer.new()
	column.add_child(row)
	for entry in [["중앙 배치",func(): request_action("center")],["하중 계산",func(): request_action("load")]]:
		_button(row,entry[0],entry[1])
	row=HBoxContainer.new()
	column.add_child(row)
	_button(row,"정적 검수 해제",clear_load)
	_button(row,"대기 취소",cancel_request)
	_slider(column,"붐뱅 회수량 (m)",-.15,.45,0)
	_slider(column,"바람 X 성분 (m/s)",0,8,5)
	_slider(column,"선체 기울기 (°)",-25,25,0)
	_slider(column,"상하 가속도 (m/s²)",-2,2,0)
	_slider(column,"트래블러 정지 마찰 (잠정)",0,1,.2)
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
	_button(extra,"처짐 예제 (트림·설정 변경)",func(): request_action("slack"))

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
	if "hull contact" in reason or "deck/support contact" in reason:
		return "적용 불가 · 풀린 줄/블록의 갑판 지지 계산이 아직 없어요.\n현재 트림과 표시를 유지했어요. 줄을 조금 당기고 다시 계산해 주세요."
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
