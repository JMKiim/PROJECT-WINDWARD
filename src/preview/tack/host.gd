extends "res://src/preview/land_drill_direct.gd"
const TACK := preload("res://src/preview/gybe/controller.gd")
var tack: RefCounted
var maneuver_hint: Label
func _new_maneuver() -> RefCounted: return TACK.new()
func _new_actor() -> Node3D: return preload("res://src/preview/tack/actor.gd").new()
func _ready() -> void:
	var started := Time.get_ticks_usec()
	super._ready()
	if not startup_ready: return
	tack=_new_maneuver()
	if not tack.setup(self):
		tack=null
		startup_ready=false
		set_process(false)
		return
	var sheet_model := preload("res://src/preview/tack/sheet.gd").new()
	sheet_model.adopt(review_options.model,tack)
	review_options.model=sheet_model
	var display := preload("res://src/preview/tack/rig_display.gd").new()
	display.adopt(rig_display,tack)
	rig_display=display
	# There are only two static fairlead patches. Prepare the opposite
	# cached contact once at startup, not in the first crossing frame.
	var rig: Node3D=rig_display.rig
	var opposite := Vector3(-rig.LOADED_TRAVELLER_X,rig.traveller_rest.y,rig.traveller_rest.z)
	if rig.traveller_fairlead_patches(opposite).is_empty():
		push_error("Opposite traveller contact could not be prepared")
		return
	startup_stages.tack_ms=(Time.get_ticks_usec()-started)/1000.0-startup_ms
	startup_ms=(Time.get_ticks_usec()-started)/1000.0
	if controls.lab!=null:
		controls.input_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		maneuver_hint=Label.new()
		maneuver_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		maneuver_hint.add_theme_font_size_override("font_size",16)
		maneuver_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
		maneuver_hint.text="T 양방향 태킹 · G 자이빙 준비/진행 · 준비·풀기 중 Backspace 종료"
		controls.input_hint.get_parent().add_child(maneuver_hint)
func _process(delta: float) -> void:
	if tack==null or not tack.busy(): super._process(delta); return
	if not is_finite(delta) or delta<=0: return
	var started := Time.get_ticks_usec()
	frame_ms=delta*1000
	var input := Input.get_axis("steer_port","steer_starboard")
	if not is_zero_approx(input):
		var cursor: float=-actor.seat_side*tack.steering_target if tack.phase in ["ENTRY","CROSS","EXIT"] else actor.steering_target
		session.set_rudder(move_toward(cursor,-input*actor.seat_side,delta*1.5))
	if tack.manual_trim_stage():
		var sheet_input := Input.get_axis("sheet_in","sheet_out")
		if not is_zero_approx(sheet_input): session.input_sheet_wheel(-sheet_input*30.0*delta)
	if tack.phase in ["PREP","POST"] or tack.manual_trim_stage(): session.advance(delta)
	tack.advance(delta)
	_refresh_preview()
	update_ms=(Time.get_ticks_usec()-started)/1000.0
func _update_sheet_study() -> void:
	if tack!=null and tack.phase=="CROSS":
		tack.update_geometry()
		return
	super._update_sheet_study()
func _refresh_preview() -> void:
	super._refresh_preview()
	if maneuver_hint!=null:
		maneuver_hint.text=session.notice if tack!=null and tack.is_gybe() else "T 양방향 태킹 · G 자이빙 준비/진행 · 준비·풀기 중 Backspace 종료"
	if tack!=null and tack.busy() and controls.lab!=null:
		var message: String=session.notice if not tack.is_gybe() else ("자이빙 준비" if tack.phase=="TRIM" else ("자이빙 풀기" if tack.phase=="EASE" else "자이빙 전환"))
		controls.summary.text="%s · 조타 %+.0f°%s"%[message,rad_to_deg(actor.rudder_angle()),"" if tack.manual_trim_stage() else " · 트림 유지"]
func _update_first_person_camera() -> void:
	if tack!=null and tack.busy(): tack.update_camera(); return
	super._update_first_person_camera()
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_G:
			if tack!=null: tack.request_gybe()
			return
		if key==KEY_BACKSPACE and tack!=null and tack.manual_trim_stage():
			tack.leave_trim_stage()
			return
		if key==KEY_T:
			if tack!=null: tack.request()
			return
		if tack!=null and tack.busy() and key in [KEY_R,KEY_8,KEY_1,KEY_2,KEY_3,KEY_4]:
			session.notice=tack.action_name()+" 중 현과 손 인계를 유지해요. 조타·시점은 조작할 수 있어요."
			return
	super._unhandled_key_input(event)
func _input(event: InputEvent) -> void:
	if tack!=null and tack.busy() and not tack.manual_trim_stage() and event is InputEventMouseButton and event.pressed and not event.ctrl_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		session.notice="손을 인계하는 동안 트림은 유지돼요. 완료 후 시트를 계속 조작할 수 있어요."
		get_viewport().set_input_as_handled()
		return
	super._input(event)
func _request_hike(value: float) -> void:
	if tack!=null and tack.busy(): return
	super._request_hike(value)
func set_side(value: int) -> void:
	if tack!=null and tack.busy(): return
	super.set_side(value)
func reset_action() -> void:
	if tack!=null and tack.busy(): return
	super.reset_action()
func select_system(value: int) -> void:
	if tack!=null and tack.busy(): return
	super.select_system(value)
func reset_scenario() -> void:
	if tack!=null: tack.cancel()
	super.reset_scenario()
