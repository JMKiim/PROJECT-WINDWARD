extends Node3D

## Stationary bilateral pose inspection. Side selection is NOT a tack/gybe.
const ACTOR := preload("res://src/boat/animation/rudder_clip_actor.gd")
const HULL := preload("res://src/boat/ilca_hull.gd")
const HARDWARE := preload("res://src/boat/ilca_hardware_part.gd")
const GRIP := preload("res://src/boat/animation/authored_grip_profile.gd")
const STROKE := preload("res://src/boat/animation/sheet_stroke_source.gd")
const STROKE_PLAYER := preload("res://src/boat/animation/sheet_stroke_player.gd")
const TAIL_SEGMENTS := 10
const SESSION := preload("res://src/preview/motion_lab_session.gd")
const CONTROLS := preload("res://src/preview/motion_lab_controls.gd")
const COMPLETE_SHEET := preload("res://src/preview/training_mainsheet.gd")
@export var complete_mainsheet_enabled := false
@export var irregular_floor_enabled := false
@export var hiking_sheet_controls_enabled := false
@export var continuous_sheet_enabled := false
@export_range(.50,1.50,.01) var extension_tube_metres := 1.070
var complete_sheet: Node3D

var actor: Node3D
var camera: Camera3D
var rudder: Node3D
var extension: MeshInstance3D
var sheet: MeshInstance3D
var ratchet: MeshInstance3D
var sheet_channel_lines: Array[MeshInstance3D] = []
var slider: HSlider
var hike_slider: HSlider
var status: Label
var sheet_status: Label
var main_title: Label
var mode_hint: Label
var study_lines: Array[MeshInstance3D] = []
var block_lead_lines: Array[MeshInstance3D] = []
var displayed_sheet_route := PackedVector3Array()
var session := SESSION.new()
var controls := CONTROLS.new()
var follow_work_area := false
var frame_ms := 0.0
var update_ms := 0.0
var selected_view := 0
var look_pitch := deg_to_rad(55.0)
var look_yaw := 0.0
const MOUSE_LOOK_RADIANS := .0025
var inspection_yaw := 0.0
var inspection_pitch := 0.0


func _ready() -> void:
	_create_stage()
	actor = ACTOR.new()
	actor.name = "AuthoredSailor"
	actor.extension_span = extension.tiller_extension_span()
	add_child(actor)
	actor.sheet_study.block_anchor = to_local(ratchet.rope_anchor_global(&"sheave"))
	actor.sheet_study.floor_surface = get_node("Hull").cockpit_floor_y_at
	actor.sheet_study.deck_fitting = ratchet
	session.setup(actor)
	if hiking_sheet_controls_enabled:
		if not complete_mainsheet_enabled or not actor.prepare_hiking_sheet_controls():
			push_error("Expanded sheet controls require the authored bank, full rope and configured extension")
			set_process(false)
			return
	if complete_mainsheet_enabled:
		complete_sheet = COMPLETE_SHEET.new()
		complete_sheet.name = "TrainingMainsheet"
		add_child(complete_sheet)
		if not complete_sheet.setup(self):
			push_error("Complete mainsheet geometry could not be configured")
	_create_controls()
	set_view(0)
	set_amount(0.0)


func _process(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	var started := Time.get_ticks_usec()
	frame_ms = delta * 1000.0
	var previous_hike: float = actor.hike
	var input := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	if not is_zero_approx(input):
		session.set_rudder(move_toward(actor.amount, input * actor.seat_side, delta * 1.5))
	var hike_input := float(Input.is_physical_key_pressed(KEY_X)) - float(Input.is_physical_key_pressed(KEY_Z))
	if not is_zero_approx(hike_input):
		session.request_hike(session.requested_hike + hike_input * delta * 0.5)
	# The distance profile must see this frame's steering, not the previous
	# frame's angle. Posture and hand state are evaluated together afterward.
	session.advance(delta)
	_refresh_preview()
	if not is_equal_approx(previous_hike, actor.hike) and selected_view != 3:
		set_view(selected_view, false)
	update_ms = float(Time.get_ticks_usec() - started) / 1000.0


func set_amount(value: float) -> void:
	actor.set_amount(value)
	_refresh_preview()

func _refresh_preview() -> void:
	if slider:
		slider.set_value_no_signal(actor.amount)
	if hike_slider:
		hike_slider.set_value_no_signal(session.requested_hike)
	rudder.rotation.y = actor.rudder_angle()
	var joint: Vector3 = actor.joint_boat()
	var palm: Vector3 = actor.palm_boat()
	extension.position = joint
	extension.basis = Basis.looking_at(palm - joint)
	if complete_sheet==null or session.reference_fixture: _update_legacy_sheet()
	_update_sheet_study()
	if selected_view == 3:
		_update_first_person_camera()
	var phase_name := "NEUTRAL" if absf(actor.amount) < 0.03 else ("PUSH" if actor.amount < 0.0 else "PULL")
	if status:
		status.text = "%s · %s %+.2f · Rudder %+.1f° · Hike %.0f%% · Grip %.0f mm / %s · Tiller %s / Sheet %s" % ["PORT" if actor.seat_side == -1 else "STARBOARD", phase_name, actor.amount, rad_to_deg(actor.rudder_angle()), actor.hike * 100.0, palm.distance_to(joint) * 1000.0, actor.grip_phase, actor.tiller_hand(), actor.sheet_hand()]
	if controls.lab != null:
		controls.refresh()


func _update_legacy_sheet() -> void:
	var channel: PackedVector3Array = actor.sheet_channel_boat()
	if not actor.sheet_study.enabled:
		var lead: PackedVector3Array = ratchet.deck_lead_route(PackedVector3Array([to_local(ratchet.rope_anchor_global(&"sheave")), channel[0]]), GRIP.SHEET_RADIUS)
		_place_line(sheet, lead[-2], lead[-1])
		for index in block_lead_lines.size():
			_place_line(block_lead_lines[index], lead[index], lead[index + 1])
	for segment in channel.size() - 1:
		_place_line(sheet_channel_lines[segment], channel[segment], channel[segment + 1])
	var start := channel[-1]
	var control1 := start + (start - channel[-2]).normalized() * 0.045
	var control2: Vector3 = start + actor.from_port(Vector3(0.06, -0.04, -0.04))
	var finish: Vector3 = start + actor.from_port(Vector3(0.04, -0.18, -0.03))
	var previous := start
	for segment in TAIL_SEGMENTS:
		var t := float(segment + 1) / TAIL_SEGMENTS
		var u := 1.0 - t
		var point := start * u * u * u + control1 * 3.0 * u * u * t + control2 * 3.0 * u * t * t + finish * t * t * t
		_place_line(sheet_channel_lines[channel.size() - 1 + segment], previous, point)
		previous = point


func set_side(side: int) -> void:
	var before: int = actor.seat_side
	session.request_side(side)
	set_amount(actor.amount)
	if actor.seat_side != before:
		set_view(selected_view, false)


func set_view(index: int, reset_look: bool = true) -> void:
	if index < 0 or index > 6:
		return
	if reset_look:
		inspection_yaw = 0.0
		inspection_pitch = 0.0
	_set_view_base(index, reset_look)
	if index != 3:
		var turn := Basis(Vector3.UP, inspection_yaw) * Basis(camera.basis.x, inspection_pitch)
		camera.basis = turn * camera.basis
	if controls.lab != null:
		controls.refresh()


func _set_view_base(index: int, reset_look: bool) -> void:
	selected_view = index
	actor.set_first_person(index == 3)
	camera.near = 0.025 if index >= 3 else 0.04
	if index == 3:
		if reset_look:
			look_pitch = deg_to_rad(lerpf(55.0, 35.0, actor.hike))
			look_yaw = 0.0
		actor.set_look(look_yaw,look_pitch)
		_update_first_person_camera()
		return
	if index == 6:
		# Side-on framing exposes the ribcage/upper-arm gap hidden by the fist
		# in the frontal view. Keep the camera fixed while scrubbing the stroke.
		var offset := Vector3(-0.60, -0.08, 0) * float(actor.hike)
		camera.position = actor.from_port(Vector3(0.15, 1.04, 1.85) + offset)
		camera.look_at(actor.from_port(Vector3(-0.39, 0.84, 0.72) + offset))
		camera.fov = 42.0
		return
	if index >= 4:
		var palm: Vector3 = actor.palm_boat(actor.sheet_hand() if index == 4 else actor.tiller_hand())
		camera.position = palm + actor.from_port(Vector3(0.32, 0.18, 0.22))
		camera.look_at(palm)
		camera.fov = 42.0
		return
	var positions := [Vector3(1.70, 1.40, 2.10), Vector3(1.75, 1.08, 0.55), Vector3(-0.10, 3.20, 0.72)]
	var offset := Vector3(-0.30, 0, 0) * float(actor.hike)
	camera.position = actor.from_port(positions[index] + offset)
	camera.look_at(actor.from_port(Vector3(-0.25, 0.80 + 0.10 * actor.hike, 0.65) + offset), Vector3.FORWARD if index == 2 else Vector3.UP)
	camera.fov = lerpf(39.0, 50.0, actor.hike) if index < 2 else 46.0


func _update_first_person_camera() -> void:
	camera.position = actor.eye_boat()
	var head: Basis = actor.bone_pose_boat("Head").basis.orthonormalized()
	var direction: Vector3 = head * actor.look_pose.eye_basis * Vector3.BACK
	if follow_work_area:
		# Explicit inspection option; independent of selected operation mode.
		var target: Vector3 = (actor.palm_boat("Left") + actor.palm_boat("Right")) * 0.5 + Vector3(0, 0.06, 0)
		var forward := (target - camera.position).normalized()
		var right := forward.cross(Vector3.UP).normalized()
		direction = Basis(Vector3.UP, look_yaw) * Basis(right, look_pitch - deg_to_rad(55)) * forward
	camera.look_at(camera.position + direction, Vector3.UP)
	camera.fov = 72.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_S:
			_stop_and_set(0.0)
		KEY_R:
			reset_action()
		KEY_8:
			set_side(-actor.seat_side)
		KEY_H:
			get_node("LabUI").visible = not get_node("LabUI").visible
		KEY_1, KEY_2, KEY_3, KEY_4:
			select_system(event.keycode - KEY_1)
		KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7:
			set_view(event.keycode - KEY_F1)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_release_mouse()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# Screen-relative pixels avoid viewport stretch and frame-rate scaling.
			apply_mouse_look(event.screen_relative)
			get_viewport().set_input_as_handled()
		return
	# Labels and panel background do not swallow trim input. Actual selectors
	# and sliders keep their wheel events, including an open popup.
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_get_hovered_control() == null:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if controls.system_select.get_popup().visible or controls.view_select.get_popup().visible: return
	var hovered: Node = null if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered is Range or hovered is OptionButton: return
		hovered = hovered.get_parent()
	if not is_finite(event.factor) or event.factor < 0.0:
		return
	var notches: float = event.factor if event.factor > 0.0 else 1.0
	session.input_sheet_wheel(notches if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -notches,event.shift_pressed)
	get_viewport().set_input_as_handled()
	controls.refresh()


func apply_mouse_look(pixels: Vector2) -> void:
	if not pixels.is_finite(): return
	if selected_view == 3:
		look_yaw = clampf(look_yaw - pixels.x * MOUSE_LOOK_RADIANS, -actor.LOOK_POSE.MAX_YAW, actor.LOOK_POSE.MAX_YAW)
		look_pitch = clampf(look_pitch + pixels.y * MOUSE_LOOK_RADIANS, deg_to_rad(-60), deg_to_rad(85))
	else:
		inspection_yaw = wrapf(inspection_yaw - pixels.x * MOUSE_LOOK_RADIANS, -PI, PI)
		inspection_pitch = clampf(inspection_pitch - pixels.y * MOUSE_LOOK_RADIANS, -1.2, 1.2)
	set_view(selected_view, false)


func _release_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_mouse()


func _exit_tree() -> void:
	_release_mouse()


func select_system(value: int) -> void:
	session.select_system(value)
	controls.refresh()


func select_mode(value: int) -> void:
	session.select_mode(value)
	controls.refresh()


func seek_action(value: float) -> void:
	session.seek_action(value)
	set_amount(actor.amount)


func reset_action() -> void:
	session.reset_action()
	set_amount(actor.amount)


func reset_sheet_action() -> void:
	session.reset_sheet_action()
	set_amount(actor.amount)


func reset_scenario() -> void:
	session.reset_scenario()
	follow_work_area = false
	look_yaw = 0.0
	look_pitch = deg_to_rad(55.0)
	set_view(0)
	set_amount(actor.amount)


func load_sheet_reference() -> void:
	session.load_sheet_reference()
	set_amount(actor.amount)


func prepare_sheet_control() -> void:
	session.prepare_sheet_control()
	set_amount(actor.amount)


func set_follow_work(value: bool) -> void:
	follow_work_area = value
	if selected_view == 3:
		_update_first_person_camera()
	controls.refresh()


func reset_view() -> void:
	set_view(selected_view)
	controls.refresh()


func inspection_snapshot() -> Dictionary:
	var result := session.snapshot()
	result["view"] = selected_view
	result["look_yaw"] = look_yaw
	result["look_pitch"] = look_pitch
	result["follow_work_area"] = follow_work_area
	result["camera_position"] = [camera.position.x, camera.position.y, camera.position.z]
	result["frame_ms"] = frame_ms
	result["update_ms"] = update_ms
	result["sheet_palm_error_mm"] = actor.palm_boat("Left").distance_to(STROKE.palm(actor.sheet_study.time, actor.sheet_study.helper_boat())) * 1000.0 if actor.sheet_study.enabled else null
	result["tiller_hand"] = actor.tiller_hand()
	result["sheet_hand"] = actor.sheet_hand()
	result["tiller_grip_mm"] = actor.palm_boat().distance_to(actor.joint_boat()) * 1000.0
	return result


func _create_stage() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("172431")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c8def0")
	world.environment.ambient_light_energy = 0.35
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.70
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.12
	add_child(fill)
	var hull := HULL.new()
	hull.inspection_mast_fit = true
	hull.name = "Hull"
	add_child(hull)
	_hardware(HARDWARE.PartKind.HIKING_STRAP, Vector3(0, 0.075, 0.82), self, {"name": "HikingStrap", "forward_tail_center": Vector3(0, HULL.FORELAND_HEIGHT - 0.070, -0.613), "forward_tail_length": 0.060})
	_hardware(HARDWARE.PartKind.HIKING_STRAP_PLATE, HULL.STRAP_FRONT_ORIGIN, self, {"name": "HikingStrapForwardPlate"})
	ratchet = _hardware(HARDWARE.PartKind.DECK_RATCHET, HULL.RATCHET_ORIGIN, self, {"name": "RatchetBlock"})
	_hardware(HARDWARE.PartKind.DAGGERBOARD_CASE, Vector3(0, 0.058, -0.155), self, {"name": "DaggerboardCase"})
	for index in HARDWARE.DECK_LEAD_PREFIX_POINTS - 1:
		var line := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = GRIP.SHEET_RADIUS
		cylinder.bottom_radius = GRIP.SHEET_RADIUS
		cylinder.radial_segments = 10
		line.mesh = cylinder
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.88, 0.82, 0.63)
		line.material_override = material
		add_child(line)
		block_lead_lines.append(line)
	_hardware(HARDWARE.PartKind.SELF_BAILER, Vector3.ZERO, self, {"name": "SelfBailer"})
	_hardware(HARDWARE.PartKind.COCKPIT_DRAIN_BUNG, Vector3.ZERO, self, {"name": "CockpitDrainBung"})
	rudder = Node3D.new()
	rudder.name = "RudderPivot"
	rudder.position = Vector3(0, 0, 2.171)
	add_child(rudder)
	var tiller := _hardware(HARDWARE.PartKind.TILLER, Vector3(0, 0.331476, -0.489529), rudder)
	tiller.rotation_degrees.x = 2.512
	_hardware(HARDWARE.PartKind.RUDDER_HEAD, Vector3(0, 0.18, -0.031), rudder)
	extension = _hardware(HARDWARE.PartKind.TILLER_EXTENSION, Vector3.ZERO, self,{"extension_tube_metres":extension_tube_metres})
	sheet = MeshInstance3D.new()
	var rope := CylinderMesh.new()
	rope.top_radius = GRIP.SHEET_RADIUS
	rope.bottom_radius = GRIP.SHEET_RADIUS
	rope.radial_segments = 12
	sheet.mesh = rope
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = Color("d8aa55")
	rope_material.roughness = 0.95
	sheet.material_override = rope_material
	add_child(sheet)
	for segment in GRIP.sheet_channel().size() - 1 + TAIL_SEGMENTS:
		var line := MeshInstance3D.new()
		line.mesh = rope.duplicate()
		line.material_override = rope_material
		add_child(line)
		sheet_channel_lines.append(line)
	for segment in STROKE_PLAYER.ROPE_SEGMENTS:
		var line := MeshInstance3D.new()
		line.mesh = rope.duplicate()
		line.material_override = rope_material
		line.visible = false
		add_child(line)
		study_lines.append(line)
	camera = Camera3D.new()
	camera.near = 0.04
	camera.current = true
	add_child(camera)


func _hardware(kind: int, location: Vector3, parent: Node, parameters: Dictionary = {}) -> MeshInstance3D:
	var result := HARDWARE.new()
	result.part_kind = kind
	result.position = location
	for key in parameters: result.set(key, parameters[key])
	parent.add_child(result)
	return result


func _place_line(mesh: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var vector := finish - start
	mesh.position = (start + finish) * 0.5
	mesh.basis = Basis(Quaternion(Vector3.UP, vector.normalized()))
	(mesh.mesh as CylinderMesh).height = vector.length()


func _create_controls() -> void:
	controls.build(self)


func _request_hike(value: float) -> void:
	session.request_hike(value)
	set_amount(actor.amount)


func _toggle_sheet_study() -> void:
	# Legacy reference fixture cut, retained for existing geometry/pose tests.
	# Interactive mode selection uses select_mode and never calls this reset.
	if actor.sheet_study.enabled:
		actor.sheet_study.leave()
		session.reference_fixture = false
		session.select_mode(SESSION.Mode.RUDDER)
		follow_work_area = false
	else:
		session.load_sheet_reference()
		follow_work_area = true
	set_amount(actor.amount)
	set_view(selected_view)


func _reset_sheet() -> void:
	reset_sheet_action()


func _update_sheet_study() -> void:
	var enabled: bool = actor.sheet_study.enabled
	sheet.visible = false
	for line in sheet_channel_lines: line.visible = false
	for line in block_lead_lines: line.visible = false
	if complete_sheet!=null and not session.reference_fixture:
		for line in study_lines: line.visible = false
		if not complete_sheet.update_geometry():
			session.wheel_pull.pause()
			session.notice = "Sheet geometry needs inspection; requested trim paused."
		displayed_sheet_route = complete_sheet.displayed
		return
	var points: PackedVector3Array
	if enabled:
		points = actor.sheet_study.rope_points()
	elif actor.sheet_control.regrip_time >= 0.0:
		points = actor.sheet_control.regrip.rope_points(session.wheel_pull.metres)
	else:
		points = actor.sheet_study.manual_points(session.wheel_pull.metres)
	displayed_sheet_route = ratchet.deck_lead_route(points, GRIP.SHEET_RADIUS)
	while study_lines.size() < displayed_sheet_route.size() - 1:
		var line := study_lines[0].duplicate() as MeshInstance3D
		line.mesh = study_lines[0].mesh.duplicate()
		add_child(line)
		study_lines.append(line)
	for index in study_lines.size():
		study_lines[index].visible = index < displayed_sheet_route.size() - 1
		if study_lines[index].visible: _place_line(study_lines[index], displayed_sheet_route[index], displayed_sheet_route[index + 1])


func _stop_and_set(value: float) -> void:
	session.set_rudder(value)
	set_amount(actor.amount)
