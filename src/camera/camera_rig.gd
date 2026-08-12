class_name WindwardCameraRig
extends Node3D

const MOUSE_SENSITIVITY := 0.0022
const MIN_LOOK_PITCH := WindwardSailor.MIN_TOTAL_LOOK_PITCH
const MAX_LOOK_PITCH := WindwardSailor.MAX_TOTAL_LOOK_PITCH
const MIN_LOOK_YAW := WindwardSailor.MIN_TOTAL_LOOK_YAW
const MAX_LOOK_YAW := WindwardSailor.MAX_TOTAL_LOOK_YAW
const TOP_DOWN_DIRECTION := Vector3(0.0, 0.8, 0.6)
const DEFAULT_TOP_DOWN_DISTANCE := 17.5
const MIN_TOP_DOWN_DISTANCE := 7.5
const MAX_TOP_DOWN_DISTANCE := 32.5
const TOP_DOWN_ZOOM_STEP := 2.5
const TOP_DOWN_HEADING_FOLLOW_SPEED := 2.2
const DEFAULT_LOOK_PITCH := deg_to_rad(-16.0)
const FIRST_PERSON_NEAR_PLANE := 0.06
const FIRST_PERSON_WAVE_ROTATION_GAIN := 0.30
const CAMERA_PROCESS_PRIORITY := 10

@export var target_path: NodePath
@export_range(0.0, 1.0, 0.01) var first_person_wave_rotation_gain := (
	FIRST_PERSON_WAVE_ROTATION_GAIN
)

@onready var target: Node3D = get_node(target_path)
@onready var top_down_camera: Camera3D = $TopDownCamera
@onready var first_person_camera: Camera3D = $FirstPersonCamera
@onready var sailor: WindwardSailor = target.get_node("Sailor") as WindwardSailor

var first_person_enabled := false
var _look_yaw := 0.0
var _look_pitch := DEFAULT_LOOK_PITCH
var _top_down_distance := DEFAULT_TOP_DOWN_DISTANCE
var _target_top_down_distance := DEFAULT_TOP_DOWN_DISTANCE
var _top_down_follow_yaw := 0.0


func _enter_tree() -> void:
	# The sailor's manual animation/head update runs first. This node then derives
	# the presentation camera from the completed anatomical eye transform.
	process_priority = CAMERA_PROCESS_PRIORITY


func _ready() -> void:
	_top_down_follow_yaw = target.global_rotation.y
	first_person_camera.near = FIRST_PERSON_NEAR_PLANE
	_sync_first_person_camera()
	_apply_camera_mode()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_camera"):
		first_person_enabled = not first_person_enabled
		_apply_camera_mode()

	var target_position := target.global_position
	_top_down_distance = lerpf(
		_top_down_distance,
		_target_top_down_distance,
		1.0 - exp(-9.0 * delta)
	)
	# Translation follows immediately, while heading is deliberately damped. This
	# preserves the behind-the-boat view without snapping on every rudder input.
	_top_down_follow_yaw = lerp_angle(
		_top_down_follow_yaw,
		target.global_rotation.y,
		1.0 - exp(-TOP_DOWN_HEADING_FOLLOW_SPEED * delta)
	)
	var target_basis := Basis(Vector3.UP, _top_down_follow_yaw)
	var desired_top_down := (
		target_position
		+ target_basis * TOP_DOWN_DIRECTION * _top_down_distance
	)
	top_down_camera.global_position = desired_top_down
	top_down_camera.look_at(target_position, Vector3.UP)

	var boat := target as WindwardBoat
	var sailing_state := boat.get_sailing_state()
	var speed_ratio := clampf(sailing_state.speed_mps / 5.5, 0.0, 1.0)
	top_down_camera.fov = lerpf(54.0, 58.0, speed_ratio)
	first_person_camera.fov = lerpf(76.0, 80.0, speed_ratio)

	# The camera remains at the anatomical eye and preserves the sailor-relative
	# tack/gaze transform. Only high-frequency wave rotation is presentation-only
	# attenuated below, so the view still follows a rotating body during a tack.
	_sync_first_person_camera()


func _sync_first_person_camera() -> void:
	var applied_look := sailor.set_head_look(_look_yaw, _look_pitch)
	_look_yaw = applied_look.x
	_look_pitch = applied_look.y
	var raw_gaze := sailor.gaze_global_transform()
	var boat := target as WindwardBoat
	var boat_quaternion := boat.global_basis.orthonormalized().get_rotation_quaternion()
	var full_wave := boat.wave_attitude_quaternion()
	var comfort_wave := boat.wave_attitude_quaternion(first_person_wave_rotation_gain)
	# Decompose the physical boat into its non-wave base and wave attitude. The
	# sailor-relative gaze retains seat/tack, torso, neck and requested look while
	# only the presentation camera's wave rotation is attenuated.
	var base_quaternion := (boat_quaternion * full_wave.inverse()).normalized()
	var raw_gaze_quaternion := raw_gaze.basis.orthonormalized().get_rotation_quaternion()
	var relative_gaze := (boat_quaternion.inverse() * raw_gaze_quaternion).normalized()
	var presentation_quaternion := (
		base_quaternion * comfort_wave * relative_gaze
	).normalized()
	first_person_camera.global_transform = Transform3D(
		Basis(presentation_quaternion),
		raw_gaze.origin
	)


func _unhandled_input(event: InputEvent) -> void:
	if not first_person_enabled:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_top_down_distance = maxf(
					MIN_TOP_DOWN_DISTANCE,
					_target_top_down_distance - TOP_DOWN_ZOOM_STEP
				)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_top_down_distance = minf(
					MAX_TOP_DOWN_DISTANCE,
					_target_top_down_distance + TOP_DOWN_ZOOM_STEP
				)
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_look(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func apply_mouse_look(relative: Vector2) -> void:
	# Kept separate from OS capture state so input direction and anatomical
	# limits can be regression-tested deterministically in headless builds.
	_look_yaw = clampf(
		_look_yaw + relative.x * MOUSE_SENSITIVITY,
		MIN_LOOK_YAW,
		MAX_LOOK_YAW
	)
	_look_pitch = clampf(
		_look_pitch - relative.y * MOUSE_SENSITIVITY,
		MIN_LOOK_PITCH,
		MAX_LOOK_PITCH
	)


func _apply_camera_mode() -> void:
	top_down_camera.current = not first_person_enabled
	first_person_camera.current = first_person_enabled
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED
		if first_person_enabled
		else Input.MOUSE_MODE_VISIBLE
	)
