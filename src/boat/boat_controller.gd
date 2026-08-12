class_name WindwardBoat
extends CharacterBody3D

const MAX_RUDDER_VISUAL_ANGLE := deg_to_rad(12.0)
const MAX_TILLER_EXTENSION_JOINT_ANGLE := deg_to_rad(150.0)
const TILLER_HAND_ANCHOR := Vector3(0.52, 0.46, 0.58)
const FLOAT_ORIGIN_OFFSET := 0.06
const BOW_SAMPLE_DISTANCE := 1.65
const SIDE_SAMPLE_DISTANCE := 0.50
const HEAVE_STIFFNESS := 16.0
const HEAVE_DAMPING := 8.0
const PITCH_STIFFNESS := 20.0
const PITCH_DAMPING := 9.0
const ROLL_STIFFNESS := 25.0
const ROLL_DAMPING := 10.0
const MAX_PITCH_ANGLE := deg_to_rad(9.0)
const MAX_ROLL_ANGLE := deg_to_rad(14.0)

@export var environment_path: NodePath
@export_range(0.0, 1.0, 0.01) var vang_tension := 0.58

@onready var sail_pivot: Node3D = $SailPivot
@onready var boom_pivot: Node3D = $SailPivot/BoomPivot
@onready var rudder_pivot: Node3D = $RudderPivot
@onready var tiller_extension_pivot: Node3D = $RudderPivot/TillerExtensionPivot
@onready var sailor: WindwardSailor = $Sailor
@onready var sailing_environment: SailingEnvironment = get_node_or_null(environment_path) as SailingEnvironment

var sailing_state := SailingState.new()
var sailing_command := SailingCommand.new()
var _heave_position := FLOAT_ORIGIN_OFFSET
var _heave_velocity := 0.0
var _wave_pitch := 0.0
var _pitch_velocity := 0.0
var _wave_roll := 0.0
var _roll_velocity := 0.0


func _ready() -> void:
	sailing_state.heading_radians = rotation.y
	_heave_position = global_position.y
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func _physics_process(delta: float) -> void:
	if sailing_environment:
		sailing_state.true_wind_velocity = sailing_environment.true_wind_at(global_position)
		sailing_state.water_current_velocity = sailing_environment.current_at(global_position)

	sailing_command.rudder = Input.get_axis("steer_port", "steer_starboard")
	sailing_command.sheet_delta = Input.get_axis("sheet_in", "sheet_out")
	sailing_state.step(delta, sailing_command)

	velocity = sailing_state.velocity_vector()
	velocity.y = 0.0
	move_and_slide()
	_update_water_pose(delta)
	_update_sail_visual(delta)


func get_sailing_state() -> SailingState:
	return sailing_state


func wave_attitude_quaternion(gain: float = 1.0) -> Quaternion:
	# Presentation systems may attenuate the high-frequency wave attitude while
	# retaining authoritative yaw, translation and the sailor's local gaze. Keep
	# the multiplication order identical to the physical boat transform.
	var clamped_gain := clampf(gain, 0.0, 1.0)
	return (
		Quaternion(Vector3.RIGHT, _wave_pitch * clamped_gain)
		* Quaternion(Vector3.BACK, _wave_roll * clamped_gain)
	).normalized()


func _update_water_pose(delta: float) -> void:
	if not sailing_environment:
		rotation = Vector3(0.0, sailing_state.heading_radians, 0.0)
		return
	var yaw_basis := Basis(Vector3.UP, sailing_state.heading_radians)
	var forward := yaw_basis * Vector3.FORWARD
	var right := yaw_basis * Vector3.RIGHT
	var origin := global_position
	var sea_state := sailing_environment.wave_sea_state(origin)
	var center := sailing_environment.water_surface_at(origin, sailing_environment.simulation_time, sea_state)
	var bow := sailing_environment.water_surface_at(
		origin + forward * BOW_SAMPLE_DISTANCE,
		sailing_environment.simulation_time,
		sea_state
	)
	var stern := sailing_environment.water_surface_at(
		origin - forward * BOW_SAMPLE_DISTANCE,
		sailing_environment.simulation_time,
		sea_state
	)
	var port := sailing_environment.water_surface_at(
		origin - right * SIDE_SAMPLE_DISTANCE,
		sailing_environment.simulation_time,
		sea_state
	)
	var starboard := sailing_environment.water_surface_at(
		origin + right * SIDE_SAMPLE_DISTANCE,
		sailing_environment.simulation_time,
		sea_state
	)
	var target_height := (
		center.height * 2.0 + bow.height + stern.height + port.height + starboard.height
	) / 6.0 + FLOAT_ORIGIN_OFFSET
	var target_vertical_velocity := (
		center.vertical_velocity * 2.0
		+ bow.vertical_velocity + stern.vertical_velocity
		+ port.vertical_velocity + starboard.vertical_velocity
	) / 6.0
	_heave_velocity += (
		(target_height - _heave_position) * HEAVE_STIFFNESS
		- (_heave_velocity - target_vertical_velocity) * HEAVE_DAMPING
	) * delta
	_heave_position += _heave_velocity * delta
	var target_pitch := clampf(
		atan2(bow.height - stern.height, BOW_SAMPLE_DISTANCE * 2.0),
		-MAX_PITCH_ANGLE,
		MAX_PITCH_ANGLE
	)
	var target_roll := clampf(
		atan2(starboard.height - port.height, SIDE_SAMPLE_DISTANCE * 2.0),
		-MAX_ROLL_ANGLE,
		MAX_ROLL_ANGLE
	)
	_pitch_velocity += (
		(target_pitch - _wave_pitch) * PITCH_STIFFNESS
		- _pitch_velocity * PITCH_DAMPING
	) * delta
	_roll_velocity += (
		(target_roll - _wave_roll) * ROLL_STIFFNESS
		- _roll_velocity * ROLL_DAMPING
	) * delta
	_wave_pitch = clampf(
		_wave_pitch + _pitch_velocity * delta,
		-MAX_PITCH_ANGLE,
		MAX_PITCH_ANGLE
	)
	_wave_roll = clampf(
		_wave_roll + _roll_velocity * delta,
		-MAX_ROLL_ANGLE,
		MAX_ROLL_ANGLE
	)
	global_position.y = _heave_position
	quaternion = (
		Quaternion(Vector3.UP, sailing_state.heading_radians)
		* wave_attitude_quaternion()
	).normalized()


func _update_sail_visual(delta: float) -> void:
	sail_pivot.rotation.y = sailing_state.boom_angle_radians
	# Vang load has its own boom pivot. The sail remains on the mast sleeve;
	# only its tack and outhaul-held clew meet the boom at the ends.
	var target_boom_pitch := deg_to_rad(lerpf(-1.0, 2.0, vang_tension))
	boom_pivot.rotation.x = lerp_angle(
		boom_pivot.rotation.x,
		target_boom_pitch,
		1.0 - exp(-7.0 * delta)
	)
	var target_rudder_angle := sailing_command.rudder * MAX_RUDDER_VISUAL_ANGLE
	rudder_pivot.rotation.y = lerp_angle(
		rudder_pivot.rotation.y,
		target_rudder_angle,
		1.0 - exp(-14.0 * delta)
	)
	# The tiller extension leads the interaction: rudder input sweeps its grip
	# through a push/pull arc and the sailor's anatomical arm IK follows that
	# physical grip. During a tack this target also visits the behind-the-back
	# handover point so the two hands can exchange controls on the extension.
	var desired_grip_position := sailor.tiller_control_target_boat_position(
		sailing_command.rudder
	)
	var extension_joint_position := rudder_pivot.transform * tiller_extension_pivot.position
	var grip_direction_in_boat := desired_grip_position - extension_joint_position
	var grip_direction_in_rudder := rudder_pivot.basis.inverse() * grip_direction_in_boat
	if grip_direction_in_rudder.length_squared() > 0.0001:
		var desired_extension_basis := Basis.looking_at(
			grip_direction_in_rudder.normalized(),
			Vector3.UP
		)
		var desired_extension_rotation := desired_extension_basis.get_rotation_quaternion()
		# The hand target already moves continuously with the connected body. A
		# rigid tiller extension must follow it exactly rather than lag and detach.
		tiller_extension_pivot.quaternion = desired_extension_rotation
