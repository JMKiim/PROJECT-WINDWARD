extends Node3D

## Limited seated-port sailing bridge. The same authored deck/session is used
## in the stationary inspection scene; no second animation or rope solver.
const DECK := preload("res://src/preview/rudder_motion_lab.tscn")
var boat: Node3D
var deck: Node3D
var look := Vector2(0,deg_to_rad(20))
var first_person := false
var valid := false
var course_limited := false
var update_ms := 0.0

func setup(value: Node3D) -> bool:
	boat = value
	# Keep the old scene intact but inactive, including its unfinished maneuvers.
	for child in boat.get_children():
		if child==self or child is CollisionShape3D: continue
		if child.name in ["Daggerboard","DaggerboardHead","DaggerboardHandle"]: continue
		child.process_mode = Node.PROCESS_MODE_DISABLED
		if child is Node3D: child.visible = false
	deck = DECK.instantiate()
	deck.name = "SeatedDeck"
	deck.embedded_controls = true
	# Production dynamics still use the original twelve-degree bridge.
	# The wider authored deck is validated separately before that migration.
	deck.wide_steering_enabled = false
	deck.extension_tube_metres = 1.070
	add_child(deck)
	if deck.complete_sheet==null or not deck.complete_sheet.configured: return false
	var rig: Node3D = deck.complete_sheet.rig
	# Reuse the existing sail, marks and clew; the obsolete boom and ropes
	# remain hidden, so there cannot be two competing trim representations.
	# The shared deck owns its complete rudder. Keep the legacy foil hidden,
	# rather than grafting a second blade onto the inspection assembly.
	boat.clew_strap.reparent(rig.boom_pivot,false)
	boat.clew_strap.process_mode = Node.PROCESS_MODE_INHERIT
	boat.clew_strap.visible = true
	boat.sail_pivot.visible = true
	boat.sail_pivot.position.y = rig.MAST_BASE_Y+rig.GOOSENECK_ABOVE_BASE+.060-boat.sail.TACK_HEIGHT_METERS
	boat.sail_pivot.get_node("BoomPivot").visible = false
	boat.sail_pivot.get_node("Gooseneck").visible = false
	var sheet: Node3D = deck.complete_sheet
	rig.set_opening((PI*.5-rig.minimum_yaw)/(deg_to_rad(175)-rig.minimum_yaw),false)
	var maximum_rig: float = rig.length_metres()
	var reserve: float = sheet.ledger.total_metres-sheet.ledger.fixed_end_metres-sheet.ledger.free_end_metres-maximum_rig
	if not sheet.ledger.set_cockpit_minimum(maxf(reserve,sheet.ledger.minimum_cockpit_metres)): return false
	rig.set_opening((deg_to_rad(40)-rig.minimum_yaw)/(deg_to_rad(175)-rig.minimum_yaw),false)
	sheet.ledger.transfer(sheet.ledger.rig_metres-rig.length_metres())
	deck.session.wheel_pull.bind_length_budget(sheet.ledger)
	sheet.cockpit.reset_motion()
	sheet.geometry_key.clear()
	boat.sailing_state.fixed_boom_side = 1.0
	valid = true
	advance_controls(1.0/60,0,0)
	return valid

func advance_controls(delta: float, rudder_input: float, sheet_input: float) -> void:
	if not valid: return
	var began := Time.get_ticks_usec()
	if not is_zero_approx(rudder_input):
		deck.session.set_rudder(move_toward(deck.actor.amount,rudder_input,delta*1.5))
	if not is_zero_approx(sheet_input): deck.session.input_sheet_wheel(-sheet_input*30*delta)
	if first_person: deck.actor.set_look(look.x,look.y)
	deck.session.advance(delta)
	deck._refresh_preview()
	valid = deck.complete_sheet.last_result.get("valid",false)
	if not valid:
		push_error("Seated sailing stopped: complete mainsheet geometry invalid")
		return
	var rig: Node3D = deck.complete_sheet.rig
	var yaw := atan2(rig.boom_pivot.basis.z.x,rig.boom_pivot.basis.z.z)
	boat.sailing_state.geometric_boom_limit_radians = yaw
	boat.sailing_state.sheet_position = clampf(inverse_lerp(deg_to_rad(5),deg_to_rad(84),yaw),0,1)
	boat.sailing_state.boom_angle_radians = yaw
	boat.sailing_state.boom_angular_velocity = 0
	boat.sail_pivot.rotation.y = yaw
	boat._sync_sail_clew_to_boom()
	update_ms = (Time.get_ticks_usec()-began)/1000.0

func guard_course() -> void:
	var state: RefCounted = boat.sailing_state
	if state.true_wind_velocity.length_squared()<.0001:
		course_limited = false
		return
	var wind_from: Vector3 = -state.true_wind_velocity.normalized()
	var signed_course: float = state.forward_vector().signed_angle_to(wind_from,Vector3.UP)
	var permitted := clampf(signed_course,deg_to_rad(35),deg_to_rad(165))
	course_limited = absf(signed_course-permitted)>.000001
	state.heading_radians = wrapf(state.heading_radians+signed_course-permitted,-PI,PI)

func set_first_person(enabled: bool) -> void:
	first_person = enabled
	deck.actor.set_first_person(enabled)
	if enabled: deck.actor.set_look(look.x,look.y)
	deck._refresh_preview()

func gaze_global_transform() -> Transform3D:
	var actor: Node3D = deck.actor
	var direction: Vector3 = actor.bone_pose_boat("Head").basis.orthonormalized()*actor.look_pose.eye_basis*Vector3.BACK
	return Transform3D(Basis.looking_at(actor.global_basis*direction,actor.global_basis*Vector3.UP),actor.to_global(actor.eye_boat()))

func apply_look(pixels: Vector2) -> void:
	if not pixels.is_finite(): return
	look.x = clampf(look.x-pixels.x*.0025,-deck.actor.LOOK_POSE.MAX_YAW,deck.actor.LOOK_POSE.MAX_YAW)
	look.y = clampf(look.y+pixels.y*.0025,deg_to_rad(-60),deg_to_rad(85))

func _input(event: InputEvent) -> void:
	if not valid: return
	if event is InputEventMouseButton and event.pressed and not event.ctrl_pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if not is_finite(event.factor) or event.factor<0: return
			var amount: float = event.factor if event.factor>0 else 1.0
			deck.session.input_sheet_wheel(amount if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -amount,event.shift_pressed,Time.get_ticks_usec()/1000000.0)
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_SPACE:
			deck.session.set_rudder(0)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:
			deck.session.select_system(event.physical_keycode-KEY_1)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		if deck!=null: deck.session.wheel_pull.pause()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func status_text() -> String:
	if not valid: return "기본 항해 중지: 줄 형상 검사 실패"
	var status := "좌현·앉음 / 풍각 35–165° · 태킹·자이빙 미지원"
	if course_limited: status += "\n기본 항해 코스 한계"
	if deck.session.selected_system!=0: status += "\n선택한 트림 장치는 아직 조작 미지원"
	return status
