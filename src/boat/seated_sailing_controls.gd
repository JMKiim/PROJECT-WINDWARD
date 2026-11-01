extends Node3D

## Explicit bilateral sailing bridge. The same authored deck/session is used
## in the stationary inspection scene; no second animation or rope solver.
const DECK := preload("res://src/preview/rudder_motion_lab.tscn")
const STEERING := preload("res://src/boat/animation/wide_steering_config.gd")
const SAILING_TACK := preload("res://src/boat/sailing_tack_coordinator.gd")
const WET_FOIL := preload("res://src/sailing/submerged_foil.gd")
const SAILING_RIG := preload("res://src/boat/sailing_rig_display.gd")
var sailing_tack := SAILING_TACK.new()
var boat: Node3D
var deck: Node3D
var look := Vector2(0,deg_to_rad(20))
var first_person := false
var valid := false
var course_limited := false
var update_ms := 0.0
var controls_focused := true
var crew_center_boat := Vector3.ZERO
var sail_center_boat := Vector3.ZERO
var wet_foils := []
var water_center_boat := Vector3.ZERO
var wet_projected_area_m2 := 0.0

func setup(value: Node3D) -> bool:
	boat = value
	sailing_tack.setup(self)
	# Keep the old scene intact but inactive, including its unfinished maneuvers.
	for child in boat.get_children():
		if child==self or child is CollisionShape3D: continue
		if child.name in ["Daggerboard","DaggerboardHead","DaggerboardHandle"]: continue
		child.process_mode = Node.PROCESS_MODE_DISABLED
		if child is Node3D: child.visible = false
	deck = DECK.instantiate()
	deck.name = "SeatedDeck"
	deck.embedded_controls = true
	add_child(deck)
	if not deck.startup_ready or deck.complete_sheet==null or not deck.complete_sheet.configured: return false
	# The preserved visible daggerboard and the current embedded rudder are
	# different owners;never read the hidden legacy rudder assembly.
	for foil: MeshInstance3D in [boat.get_node("Daggerboard"),deck.rudder.get_node("RudderBladePivot/RudderBlade")]:
		var geometry := WET_FOIL.new()
		geometry.setup(foil)
		wet_foils.append({"foil":foil,"geometry":geometry})
	deck.tack.practice_cues=false
	sailing_tack.observe_course()
	# The current deck already owns the visible sail, clew, boom and purchase.
	# Its hidden CompletePurchase is an allocation container, not a built rig.
	# Initialize once from the sailing trim; do not graft legacy gear onto it.
	var ledger: RefCounted=deck.complete_sheet.ledger
	var maximum: float=_maximum_rig()
	var initial: float=lerpf(ledger.minimum_rig_metres,maximum,clampf(boat.sailing_state.sheet_position,0,1))
	ledger.transfer(ledger.rig_metres-initial)
	if not deck.session.wheel_pull.bind_length_budget(ledger): return false
	var sailing_display := SAILING_RIG.new()
	sailing_display.adopt(deck.rig_display,deck.tack)
	sailing_display.setup_sailing(boat)
	deck.rig_display=sailing_display
	deck._refresh_preview()
	valid = true
	_publish_state()
	return valid

func _maximum_rig() -> float:
	var ledger: RefCounted=deck.complete_sheet.ledger
	return ledger.total_metres-ledger.fixed_end_metres-ledger.free_end_metres-ledger.minimum_cockpit_metres

func water_reaction_moment(body_basis: Basis) -> float:
	# Uniform submerged planform weighting is an effective force allocation,
	# not a measured pressure center. Hull crossflow acts at the root pivot.
	var weighted := Vector3.ZERO
	wet_projected_area_m2=0
	var force_axis := Basis(Vector3.UP,boat.sailing_state.heading_radians)*Vector3.RIGHT
	var environment: Node=boat.sailing_environment
	var sea: Dictionary=environment.wave_sea_state(boat.global_position) if environment!=null else {}
	for item in wet_foils:
		var foil: MeshInstance3D=item.foil
		if not foil.is_visible_in_tree(): continue
		var frame := Transform3D.IDENTITY
		var node: Node3D=foil
		while node!=boat:
			frame=node.transform*frame; node=node.get_parent() as Node3D
		var offset := body_basis*frame.origin
		var point := Vector3(offset.x,-boat.global_position.y,offset.z)
		var normal := Vector3.UP
		if environment!=null:
			var surface: RefCounted=environment.water_surface_at(boat.global_position+offset,environment.simulation_time,sea)
			point.y=surface.height-boat.global_position.y; normal=surface.normal
		var wet: Dictionary=item.geometry.sample(frame,body_basis,point,normal)
		var projection := (body_basis*frame.basis*Vector3.RIGHT).normalized().dot(force_axis)
		var area: float=wet.area_m2*projection*projection
		weighted+=wet.center*area; wet_projected_area_m2+=area
	water_center_boat=weighted/wet_projected_area_m2 if wet_projected_area_m2>.000000001 else Vector3.ZERO
	var force_world: Vector3=force_axis*boat.sailing_state.lateral_foil_force_n
	return water_center_boat.cross(body_basis.inverse()*force_world).z

func rudder_command(delta := 0.0) -> float:
	# Normalize the actual displayed blade against its authored 24-degree range,
	# not the obsolete twelve-degree visual constant in the legacy controller.
	var command := clampf(deck.actor.rudder_angle()/deg_to_rad(STEERING.DEGREES),-1,1) if valid else 0.0
	return sailing_tack.limit_rudder(command,delta)

func _publish_state() -> void:
	var display: RefCounted=deck.rig_display
	valid=deck.tack.geometry_valid if deck.tack.phase=="CROSS" else display!=null and display.valid and deck.review_options.model.last_result.get("valid",false)
	if not valid:
		push_error("Seated sailing stopped: visible mainsheet geometry invalid")
		return
	var ledger: RefCounted=deck.complete_sheet.ledger
	# The ledger alone owns trim. Gaze, hand recovery and a read-only display
	# inverse must never feed extra metres or a new aerodynamic trim back.
	boat.sailing_state.sheet_position=inverse_lerp(ledger.minimum_rig_metres,_maximum_rig(),ledger.rig_metres)
	# CROSS has its own fitted opening; the normal display cache is stale
	# there. Publish the actual final spar, not the temporary seat convention.
	var rig: Node3D=display.rig
	var yaw := atan2(rig.boom_pivot.basis.z.x,rig.boom_pivot.basis.z.z)
	if absf(yaw)>.00000001: boat.sailing_state.fixed_boom_side=signf(yaw)
	boat.sailing_state.geometric_boom_limit_radians=absf(display.fitted_yaw)
	boat.sailing_state.installed_boom_yaw_radians=yaw
	boat.sailing_state.boom_angle_radians=yaw
	# Read the finalized sail's actual tack/head/clew representative plane.
	# Compose local bases to avoid world-translation cancellation; no cloth,
	# hand,ledger or rig property is modified by the pressure input.
	var cloth: Node3D=rig.sail_mount.cloth
	var frame := Transform3D.IDENTITY
	var node: Node3D=cloth
	while node!=null and node!=boat:
		frame=node.transform*frame
		node=node.get_parent() as Node3D
	var tack: Vector3=cloth.luff_boundary_point(0)
	var chord: Vector3=frame.basis*(cloth.clew_target_local()-tack)
	var span: Vector3=frame.basis*(cloth.luff_boundary_point(1)-tack)
	sail_center_boat=frame*((tack+cloth.luff_boundary_point(1)+cloth.clew_target_local())/3)
	if node!=boat or not boat.sailing_state.set_sail_frame(chord,span):
		valid=false
		push_error("Seated sailing stopped: invalid representative sail plane")
		return
	crew_center_boat=_crew_center_of_mass()

func _crew_center_of_mass() -> Vector3:
	# Coarse declared mass lumps,not validated anthropometry.No bone writes.
	var actor: Node3D=deck.actor
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var center: Vector3=hips*.15+(hips+chest)*.175+actor.bone_pose_boat("Head").origin*.08
	for side in ["Left","Right"]:
		var thigh: Vector3=actor.bone_pose_boat(side+"UpperLeg").origin
		var knee: Vector3=actor.bone_pose_boat(side+"LowerLeg").origin
		var foot: Vector3=actor.bone_pose_boat(side+"Foot").origin
		center+=(thigh+knee)*.06+(knee+foot)*.03
		center+=(actor.bone_pose_boat(side+"UpperArm").origin+actor.bone_pose_boat(side+"Hand").origin)*.015
	var frame := Transform3D.IDENTITY
	var node: Node3D=actor
	while node!=boat:
		frame=node.transform*frame
		node=node.get_parent() as Node3D
	return frame*center

func advance_controls(delta: float, rudder_input: float, sheet_input: float) -> void:
	if not valid: return
	if not is_finite(delta) or delta<=0 or not is_finite(rudder_input) or not is_finite(sheet_input): return
	var began := Time.get_ticks_usec()
	var previous_boom: float=boat.sailing_state.boom_angle_radians
	deck.rig_display.prepare(delta)
	sailing_tack.observe_course()
	if not controls_focused:
		rudder_input=0
		sheet_input=0
	if not is_zero_approx(rudder_input):
		var target: float=-deck.actor.seat_side*clampf(rudder_input,-1,1)
		var cursor: float=-deck.actor.seat_side*deck.tack.steering_target if deck.actor.crossing() else deck.actor.steering_target
		deck.session.set_rudder(move_toward(cursor,target,delta*1.5))
	var busy: bool=deck.tack.busy()
	var manual_trim: bool=deck.tack.manual_trim_stage()
	if (not busy or manual_trim) and not is_zero_approx(sheet_input): deck.session.input_sheet_wheel(-sheet_input*30*delta)
	# These actions are installed by the shared deck's X/Z bindings. Only
	# this physics owner accumulates posture; the embedded lab never ticks.
	var hike_input := Input.get_axis("land_hike_in","land_hike_out") if controls_focused else 0.0
	if not busy and not is_zero_approx(hike_input):
		deck.session.request_hike(deck.session.requested_hike+hike_input*delta*.5)
	# Set the gaze target before the session's one combined pose sample.
	deck.look_yaw=look.x; deck.look_pitch=look.y
	if first_person and (not busy or manual_trim): deck.actor.look_pose.set_target(look.x,look.y)
	if not busy or manual_trim or deck.tack.phase in ["PREP","POST"]: deck.session.advance(delta)
	if busy and controls_focused:
		sailing_tack.prepare_tick()
		deck.tack.advance(delta)
	deck._refresh_preview()
	_publish_state()
	if valid: boat.sailing_state.boom_angular_velocity=wrapf(boat.sailing_state.boom_angle_radians-previous_boom,-PI,PI)/delta
	update_ms = (Time.get_ticks_usec()-began)/1000.0

func guard_course() -> void:
	# Read-only after the physical step. No hidden heading correction.
	course_limited=sailing_tack.course_limited

func set_first_person(enabled: bool) -> void:
	first_person = enabled
	deck.actor.set_first_person(enabled)
	if enabled: deck.actor.set_look(look.x,look.y)
	deck._refresh_preview()

func gaze_global_transform() -> Transform3D:
	var actor: Node3D = deck.actor
	if deck.tack.busy():
		var frame: Basis
		if deck.tack.manual_trim_stage():
			var manual_direction: Vector3=actor.bone_pose_boat("Head").basis.orthonormalized()*actor.look_pose.eye_basis*Vector3.BACK
			return Transform3D(Basis.looking_at(actor.global_basis*manual_direction,actor.global_basis*Vector3.UP),actor.to_global(actor.eye_boat()))
		if deck.tack.phase=="CROSS" and not deck.tack.result.is_empty(): frame=deck.tack.result.body.look_frame
		else:
			var view: Basis=(actor.bone_pose_boat("Head").basis.orthonormalized()*actor.look_pose.eye_basis).orthonormalized()
			frame=view*Basis(Vector3.RIGHT,-actor.look_pose.pitch)*Basis(Vector3.UP,-actor.look_pose.yaw)
		var desired := frame*Basis(Vector3.UP,look.x)*Basis(Vector3.RIGHT,look.y)*Basis(Vector3.UP,PI)
		return Transform3D((actor.global_basis*desired).orthonormalized(),actor.to_global(actor.eye_boat()))
	var direction: Vector3 = actor.bone_pose_boat("Head").basis.orthonormalized()*actor.look_pose.eye_basis*Vector3.BACK
	return Transform3D(Basis.looking_at(actor.global_basis*direction,actor.global_basis*Vector3.UP),actor.to_global(actor.eye_boat()))

func apply_look(pixels: Vector2) -> void:
	if not pixels.is_finite(): return
	look.x = clampf(look.x-pixels.x*.0025,-deck.actor.LOOK_POSE.MAX_YAW,deck.actor.LOOK_POSE.MAX_YAW)
	look.y = clampf(look.y+pixels.y*.0025,deg_to_rad(-60),deg_to_rad(85))

func _input(event: InputEvent) -> void:
	if not valid or not controls_focused: return
	if event is InputEventMouseButton and event.pressed and not event.ctrl_pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if deck.tack.busy() and not deck.tack.manual_trim_stage():
				deck.session.notice="전환 중 트림 유지 · 완료 후 시트를 계속 조작할 수 있어요."
				get_viewport().set_input_as_handled()
				return
			if not is_finite(event.factor) or event.factor<0: return
			var amount: float = event.factor if event.factor>0 else 1.0
			deck.session.input_sheet_wheel(amount if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -amount,event.shift_pressed,Time.get_ticks_usec()/1000000.0)
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_SPACE:
			deck.session.set_rudder(0)
			get_viewport().set_input_as_handled()
		elif key==KEY_T:
			sailing_tack.request()
			get_viewport().set_input_as_handled()
		elif key==KEY_G:
			sailing_tack.request_gybe()
			get_viewport().set_input_as_handled()
		elif key==KEY_BACKSPACE:
			sailing_tack.cancel_preparation()
			get_viewport().set_input_as_handled()
		elif key in [KEY_1,KEY_2,KEY_3,KEY_4] and not deck.tack.busy():
			deck.session.select_system(key-KEY_1)
			get_viewport().set_input_as_handled()
		elif key==KEY_8:
			deck.session.notice="항해 중 검수 현 교체는 사용하지 않아요. T/G로 전환해 주세요."
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		controls_focused=false
		if deck!=null:
			deck.session.wheel_pull.pause()
			if not deck.tack.busy(): deck.session.request_hike(deck.actor.hike)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:
		controls_focused=true

func status_text() -> String:
	if not valid: return "기본 항해 중지: 줄 형상 검사 실패"
	var posture := "착석" if deck.actor.hike<=.000001 else "하이크 %.0f%%" % (deck.actor.hike*100)
	var status := "%s·%s · X/Z 하이크" % ["좌현" if deck.actor.seat_side==-1 else "우현",posture]
	status += "\nT 풍상 전환 · G 풍하 준비/확정/마감 · A/D 조타"
	if deck.tack.busy(): status += "\n%s %s · %s" % [deck.tack.action_name(),deck.tack.phase,"W/S·휠 시트 조절" if deck.tack.manual_trim_stage() else "트림 유지"]
	status += "\n조타 %+.0f° · 메인시트 %.2fm / 14m" % [rad_to_deg(deck.actor.rudder_angle()),deck.complete_sheet.ledger.rig_metres]
	if deck.rig_display.slack_metres>.01 and deck.tack.phase!="CROSS":
		status += "\n붐 %.0f° / 시트 한계 %.0f° · 여유 줄 %.2fm" % [absf(boat.sailing_state.boom_angle_degrees()),rad_to_deg(boat.sailing_state.geometric_boom_limit_radians),deck.rig_display.slack_metres]
	var pressure: RefCounted=boat.sailing_state.sail_pressure
	if pressure.valid:
		status += "\n세일 %s · 입사 %.0f° · 구동 %.0f%%" % [pressure.condition,pressure.incidence_degrees,pressure.speed_factor(boat.sailing_state.true_wind_velocity.length())*100]
	status += "\n힐 %+.1f° · 풍압 %+.0f / 체중 %+.0f N·m" % [boat.sailing_roll_degrees(),boat.sailing_heel.wind_moment_nm,boat.sailing_heel.crew_moment_nm]
	status += "\n수중 반력 %+.0f N·m" % boat.sailing_heel.water_moment_nm
	status += "\n횡속도 %+.2fm/s" % boat.sailing_state.lateral_water_speed_mps()
	if absf(boat.sailing_state.forward_water_speed_mps())>.05:
		status += " · 리웨이 %+.1f°" % boat.sailing_state.leeway_degrees()
	if course_limited: status += "\n전환 지원 경계 · 선수 T / 풍하 G · 방향 보정 없음"
	var forward_speed: float=boat.sailing_state.forward_water_speed_mps()
	if forward_speed<-.001:
		var backing := "미세 후진" if forward_speed>-.01 else "후진 %.2fm/s" % -forward_speed
		status += "\n%s · A/D 조타 효과가 전진과 반대예요." % backing
		status += "\n공기력 %+.1fN · 후진저항 %.1fN" % [boat.sailing_state.axial_air_force_n,boat.sailing_state.reverse_water_force_n]
	elif boat.sailing_state.wind_angle_degrees()<=20 and absf(forward_speed)<.05:
		status += "\n노고존 · 뒤로 밀리면 A/D로 바람에서 벗어나세요."
	if not deck.session.notice.is_empty(): status += "\n"+deck.session.notice
	if deck.session.selected_system!=0: status += "\n선택한 트림 장치는 아직 조작 미지원"
	return status
