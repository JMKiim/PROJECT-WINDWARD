extends Node3D

## Stationary bilateral pose inspection. Side selection is NOT a tack/gybe.
const ACTOR := preload("res://src/boat/animation/rudder_clip_actor.gd")
const HULL := preload("res://src/boat/ilca_hull.gd")
const HARDWARE := preload("res://src/boat/ilca_hardware_part.gd")
const GRIP := preload("res://src/boat/animation/authored_grip_profile.gd")
const STROKE := preload("res://src/boat/animation/sheet_stroke_source.gd")
const TAIL_SEGMENTS := 10

var actor: Node3D
var camera: Camera3D
var rudder: Node3D
var extension: MeshInstance3D
var sheet: MeshInstance3D
var sheet_channel_lines: Array[MeshInstance3D] = []
var slider: HSlider
var hike_slider: HSlider
var status: Label
var play_button: Button
var sheet_status: Label
var sheet_slider: HSlider
var rudder_only: Array[Control] = []
var main_title: Label
var mode_hint: Label
var study_lines: Array[MeshInstance3D] = []
var autoplay := false
var slow := false
var cycle_time := 0.0
var selected_view := 0
var look_pitch := deg_to_rad(55.0)
var look_yaw := 0.0


func _ready() -> void:
	_create_stage()
	actor = ACTOR.new()
	actor.name = "AuthoredSailor"
	add_child(actor)
	_create_controls()
	set_view(0)
	set_amount(0.0)


func _process(delta: float) -> void:
	if actor.sheet_study.enabled:
		actor.sheet_study.advance(delta * (0.35 if slow else 1.0))
		set_amount(0.0)
	var hike_changed: bool = actor.grip_phase != "HOLD"
	var previous_hike: float = actor.hike
	actor.advance_hike(delta)
	if hike_changed:
		if selected_view == 3:
			look_pitch = clampf(look_pitch - deg_to_rad(20) * (actor.hike - previous_hike), deg_to_rad(5), deg_to_rad(80))
		set_amount(actor.amount)
		if selected_view != 3:
			set_view(selected_view)
	if selected_view == 3:
		look_yaw = clampf(look_yaw + (float(Input.is_key_pressed(KEY_LEFT)) - float(Input.is_key_pressed(KEY_RIGHT))) * delta, -0.9, 0.9)
		look_pitch = clampf(look_pitch + (float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))) * delta, deg_to_rad(5), deg_to_rad(80))
		_update_first_person_camera()
	if autoplay and not actor.sheet_study.enabled:
		cycle_time += delta * (0.35 if slow else 1.0)
		# Four eased strokes with explicit holds: neutral / push / neutral / pull.
		var phase := fmod(cycle_time, 8.0)
		var segment := mini(int(phase / 2.0), 3)
		var fraction := smoothstep(0.0, 1.2, fmod(phase, 2.0))
		var keys := [0.0, -1.0, 0.0, 1.0, 0.0]
		set_amount(lerpf(keys[segment], keys[segment + 1], fraction))
	else:
		var input := Input.get_axis("steer_port", "steer_starboard")
		if not is_zero_approx(input):
			set_amount(move_toward(actor.amount, input * actor.seat_side, delta * 1.5))


func set_amount(value: float) -> void:
	actor.set_amount(value)
	if slider:
		slider.set_value_no_signal(actor.amount)
	if hike_slider:
		hike_slider.set_value_no_signal(actor.hike_target)
	rudder.rotation.y = actor.rudder_angle()
	var joint: Vector3 = actor.joint_boat()
	var palm: Vector3 = actor.palm_boat()
	extension.position = joint
	extension.basis = Basis.looking_at(palm - joint)
	var channel: PackedVector3Array = actor.sheet_channel_boat()
	_place_line(sheet, Vector3(0, 0.39, 0.14), channel[0])
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
	_update_sheet_study()
	if selected_view == 3:
		_update_first_person_camera()
	var phase_name := "NEUTRAL" if absf(actor.amount) < 0.03 else ("PUSH" if actor.amount < 0.0 else "PULL")
	if status:
		status.text = "%s · %s %+.2f · Rudder %+.1f° · Hike %.0f%% · Grip %.0f mm / %s · Tiller %s / Sheet %s" % ["PORT" if actor.seat_side == -1 else "STARBOARD", phase_name, actor.amount, rad_to_deg(actor.rudder_angle()), actor.hike * 100.0, palm.distance_to(joint) * 1000.0, actor.grip_phase, actor.tiller_hand(), actor.sheet_hand()]


func set_side(side: int) -> void:
	if actor.sheet_study.enabled:
		return
	if side not in [-1, 1] or side == actor.seat_side:
		return
	# This is an explicit inspection cut, not an unfinished body-transfer blend.
	autoplay = false
	play_button.text = "Play cycle [Space]"
	actor.set_side(side)
	hike_slider.set_value_no_signal(actor.hike)
	set_amount(actor.amount)
	set_view(selected_view)


func set_view(index: int) -> void:
	if index < 0 or index > 6:
		return
	selected_view = index
	actor.set_first_person(index == 3)
	camera.near = 0.025 if index >= 3 else 0.04
	if index == 3:
		look_pitch = deg_to_rad(lerpf(55.0, 35.0, actor.hike))
		look_yaw = 0.0
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
	var direction := head * Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch) * Vector3.BACK
	if actor.sheet_study.enabled:
		# Inspection-only gaze follows the work area without moving the lens.
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
		KEY_SPACE:
			if actor.sheet_study.enabled: _play_sheet()
			else: _toggle_play()
		KEY_R:
			_stop_and_set(0.0)
		KEY_8:
			set_side(-actor.seat_side)
		KEY_9:
			_toggle_sheet_study()
		KEY_W:
			if actor.sheet_study.enabled: _play_sheet()
		KEY_H:
			get_node("LabUI").visible = not get_node("LabUI").visible
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			set_view(event.keycode - KEY_1)


func _create_stage() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("172431")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c8def0")
	world.environment.ambient_light_energy = 0.65
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.25
	add_child(fill)
	var hull := HULL.new()
	hull.name = "Hull"
	add_child(hull)
	_hardware(HARDWARE.PartKind.HIKING_STRAP, Vector3(0, 0.075, 0.82), self)
	_hardware(HARDWARE.PartKind.HIKING_STRAP_PLATE, Vector3(0, 0.080, 0.275), self)
	_hardware(HARDWARE.PartKind.DECK_RATCHET, Vector3(0, 0.35, 0.14), self)
	rudder = Node3D.new()
	rudder.name = "RudderPivot"
	rudder.position = Vector3(0, 0, 2.171)
	add_child(rudder)
	var tiller := _hardware(HARDWARE.PartKind.TILLER, Vector3(0, 0.331476, -0.489529), rudder)
	tiller.rotation_degrees.x = 2.512
	_hardware(HARDWARE.PartKind.RUDDER_HEAD, Vector3(0, 0.18, -0.031), rudder)
	extension = _hardware(HARDWARE.PartKind.TILLER_EXTENSION, Vector3.ZERO, self)
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
	for segment in 52:
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


func _hardware(kind: int, location: Vector3, parent: Node) -> MeshInstance3D:
	var result := HARDWARE.new()
	result.part_kind = kind
	result.position = location
	parent.add_child(result)
	return result


func _place_line(mesh: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var vector := finish - start
	mesh.position = (start + finish) * 0.5
	mesh.basis = Basis(Quaternion(Vector3.UP, vector.normalized()))
	(mesh.mesh as CylinderMesh).height = vector.length()


func _create_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LabUI"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.10, 0.135, 0.94)
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	var title := Label.new()
	main_title = title
	title.text = "RUDDER + HIKING / MOTION STUDY 02"
	title.add_theme_font_size_override("font_size", 25)
	stack.add_child(title)
	var note := Label.new()
	note.text = "BILATERAL POSE LAB · FIXED FOOT SUPPORT · GUIDED GRIP SLIDE · NOT TACK/GYBE OR SAILING PHYSICS"
	note.add_theme_color_override("font_color", Color("9db5ca"))
	note.add_theme_font_size_override("font_size", 14)
	stack.add_child(note)
	rudder_only.append(note)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 18)
	stack.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	rudder_only.append(row)
	play_button = _button("Play cycle [Space]", _toggle_play, row)
	_button("Push", func(): _stop_and_set(-1.0), row)
	_button("Neutral [R]", func(): _stop_and_set(0.0), row)
	_button("Pull", func(): _stop_and_set(1.0), row)
	var slow_button := CheckButton.new()
	slow_button.focus_mode = Control.FOCUS_NONE
	slow_button.text = "Slow ×0.35"
	slow_button.toggled.connect(func(on: bool): slow = on)
	row.add_child(slow_button)
	_button("3/4 [1]", func(): set_view(0), row)
	_button("Front [2]", func(): set_view(1), row)
	_button("Top [3]", func(): set_view(2), row)
	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 8)
	stack.add_child(view_row)
	_button("First person [4]", func(): set_view(3), view_row)
	_button("Sheet grip [5]", func(): set_view(4), view_row)
	_button("Tiller grip [6]", func(): set_view(5), view_row)
	_button("Upper arm [7]", func(): set_view(6), view_row)
	_button("Switch side [8]", func(): set_side(-actor.seat_side), view_row)
	slider = HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.002
	slider.custom_minimum_size = Vector2(680, 26)
	slider.value_changed.connect(func(value: float): _stop_and_set(value))
	stack.add_child(slider)
	rudder_only.append(slider)
	var hike_row := HBoxContainer.new()
	hike_row.add_theme_constant_override("separation", 8)
	stack.add_child(hike_row)
	rudder_only.append(hike_row)
	_button("Seated", func(): _request_hike(0.0), hike_row)
	_button("Half hike", func(): _request_hike(0.5), hike_row)
	_button("Hike", func(): _request_hike(1.0), hike_row)
	hike_slider = HSlider.new()
	hike_slider.focus_mode = Control.FOCUS_NONE
	hike_slider.min_value = 0.0
	hike_slider.max_value = 1.0
	hike_slider.step = 0.01
	hike_slider.custom_minimum_size = Vector2(380, 26)
	hike_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hike_slider.value_changed.connect(_request_hike)
	hike_row.add_child(hike_slider)
	var hint := Label.new()
	mode_hint = hint
	hint.text = "Slider: PUSH ← → PULL | A/D: rudder direction (push/pull swaps by seat) | First person: arrows to look, [4] reset."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("9db5ca"))
	stack.add_child(hint)
	var sheet_row := HBoxContainer.new()
	sheet_row.add_theme_constant_override("separation", 8)
	stack.add_child(sheet_row)
	_button("Sheet study [9]", _toggle_sheet_study, sheet_row)
	_button("Pull / Pause [W]", _play_sheet, sheet_row)
	_button("Reset stroke", _reset_sheet, sheet_row)
	sheet_slider = HSlider.new()
	sheet_slider.focus_mode = Control.FOCUS_NONE
	sheet_slider.max_value = STROKE.DURATION
	sheet_slider.step = 0.01
	sheet_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_slider.custom_minimum_size = Vector2(240, 20)
	sheet_slider.value_changed.connect(func(value: float):
		if actor.sheet_study.enabled:
			actor.sheet_study.playing = false
			actor.sheet_study.seek(value)
			set_amount(0.0))
	sheet_row.add_child(sheet_slider)
	sheet_status = Label.new()
	sheet_status.add_theme_font_size_override("font_size", 14)
	stack.add_child(sheet_status)


func _request_hike(value: float) -> void:
	hike_slider.set_value_no_signal(value)
	actor.request_hike(value)

func _toggle_sheet_study() -> void:
	autoplay = false
	play_button.text = "Play cycle [Space]"
	if actor.sheet_study.enabled:
		actor.sheet_study.leave()
	else:
		actor.set_side(-1)
		actor.set_hike(0.0)
		actor.set_amount(0.0)
		actor.sheet_study.enter()
	set_amount(actor.amount)
	set_view(selected_view)

func _play_sheet() -> void:
	if not actor.sheet_study.enabled: return
	if actor.sheet_study.time >= STROKE.DURATION: return
	actor.sheet_study.playing = not actor.sheet_study.playing

func _reset_sheet() -> void:
	if not actor.sheet_study.enabled: return
	actor.sheet_study.playing = false
	actor.sheet_study.seek(0.0)
	set_amount(0.0)

func _update_sheet_study() -> void:
	var enabled: bool = actor.sheet_study.enabled
	sheet.visible = not enabled
	for line in sheet_channel_lines: line.visible = not enabled
	for line in study_lines: line.visible = enabled
	if not sheet_status: return
	for control in rudder_only: control.visible = not enabled
	main_title.text = "SHEET / ONE STROKE STUDY 03" if enabled else "RUDDER + HIKING / MOTION STUDY 02"
	mode_hint.text = "W / Space: play-pause · Slider: inspect phase · 4: first person · Arrows: look · H: hide/show UI · 9: exit" if enabled else "Slider: PUSH ← → PULL | A/D: rudder direction | First person: arrows to look, [4] reset. H: hide/show UI."
	if not enabled:
		sheet_status.text = "[9] Sheet study: one seated port stroke. Steering/hiking study remains separate."
		return
	var time: float = actor.sheet_study.time
	var points: PackedVector3Array = actor.sheet_study.rope_points()
	for index in study_lines.size(): _place_line(study_lines[index], points[index], points[index + 1])
	sheet_slider.set_value_no_signal(time)
	var holder := "BOTH" if STROKE.sheet_owns_load(time) and STROKE.helper_owns_load(time) else ("SHEET HAND" if STROKE.sheet_owns_load(time) else "TILLER HAND PIN")
	sheet_status.text = "PORT / SEATED / RUDDER NEUTRAL · %s · Holder: %s · Feed %.0f mm · Inspection only; [9] exit" % [STROKE.phase(time), holder, STROKE.pulled_metres(time) * 1000]


func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _toggle_play() -> void:
	autoplay = not autoplay
	if autoplay:
		# Start a new cycle at the matching point, never jump from the held pose.
		cycle_time = _cycle_time_for_amount(actor.amount)
	play_button.text = "Pause [Space]" if autoplay else "Play cycle [Space]"


func _cycle_time_for_amount(value: float) -> float:
	# Invert smoothstep with a bounded bisection, used only when Play is clicked.
	var low := 0.0
	var high := 1.2
	for iteration in 20:
		var midpoint := (low + high) * 0.5
		if smoothstep(0.0, 1.2, midpoint) < absf(value):
			low = midpoint
		else:
			high = midpoint
	return (4.0 if value > 0.0 else 0.0) + (low + high) * 0.5


func _stop_and_set(value: float) -> void:
	autoplay = false
	play_button.text = "Play cycle [Space]"
	set_amount(value)
