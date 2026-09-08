class_name WindwardBoat
extends CharacterBody3D

const MAX_RUDDER_VISUAL_ANGLE := deg_to_rad(12.0)
const TILLER_EXTENSION_SHAFT_LENGTH := 1.10
const TILLER_EXTENSION_MIN_HAND_DISTANCE := IlcaHardwarePart.TILLER_EXTENSION_GRIP_MIN_DISTANCE
const TILLER_EXTENSION_MAX_HAND_DISTANCE := IlcaHardwarePart.TILLER_EXTENSION_GRIP_MAX_DISTANCE
const TILLER_EXTENSION_ENTRY_PREPOSITION_MIN_HAND_DISTANCE := TILLER_EXTENSION_MIN_HAND_DISTANCE
const TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE := 0.60
const TILLER_EXTENSION_NORMAL_FAR_HAND_DISTANCE := 0.80
const TILLER_EXTENSION_HAND_SLIDE_SPEED := 0.45
const TILLER_EXTENSION_HAND_DISTANCE_HYSTERESIS := 0.006
const TILLER_EXTENSION_HAND_CONTACT_CLEARANCE := 0.060
# Normal steering may use the whole foam contact range. Select the point from
# a chest-front working lane plus the live tiller-side shoulder instead of
# pinning every seated pose to 0.60m. Projecting this target onto the moving
# shaft produces a visible, useful hand slide while the wrist stays relaxed.
const TILLER_EXTENSION_WORKING_CONTACT_LATERAL := 0.30
const TILLER_EXTENSION_WORKING_CONTACT_HEIGHT := 0.78
const TILLER_EXTENSION_WORKING_CONTACT_AFT := 0.70
const TILLER_EXTENSION_WORKING_CONTACT_WEIGHT := 3.0
# Steering changes the chest-front contact in the sailor's forward direction.
# These are palm targets, not extra motion added after physical contact solving.
const TILLER_EXTENSION_STEERING_CONTACT_STROKE := 0.060
const TILLER_EXTENSION_STEERING_PULL_FORWARD_ARC := 0.10
const TILLER_EXTENSION_STEERING_PULL_LIFT := 0.12
const TILLER_EXTENSION_STEERING_PULL_LIFT_ENTRY := 0.02
const TILLER_EXTENSION_STEERING_NEUTRAL_LIFT_RESERVE := 0.006
const TILLER_EXTENSION_NEUTRAL_CATCHUP_DISTANCE := 0.060
const TILLER_EXTENSION_COMFORT_REACH_MIN := 0.30
const TILLER_EXTENSION_COMFORT_REACH_TARGET := 0.37
const TILLER_EXTENSION_COMFORT_REACH_MAX := 0.46
# This is shoulder-to-palm distance. The semantic palm anchor is roughly 10.6 cm
# beyond the wrist target, so a 27.5 cm contact reach leaves about 17 cm of inner
# two-bone reach instead of folding the wrist onto the shoulder. The hand remains
# free to slide anywhere on the usable foam to satisfy this guard.
const TILLER_EXTENSION_EXIT_REACH_MIN := 0.275
const TILLER_EXTENSION_EXIT_REACH_MAX := 0.50
const TILLER_EXTENSION_EXIT_DIRECTION_TOLERANCE := deg_to_rad(5.0)
const TILLER_EXTENSION_EXIT_DISTANCE_TOLERANCE := 0.030
const TILLER_EXTENSION_EXIT_COMPLETION_DIRECTION := deg_to_rad(1.0)
const TILLER_EXTENSION_EXIT_COMPLETION_DISTANCE := 0.002
const TILLER_EXTENSION_EXIT_READY_GENERATIONS := 2
const TILLER_EXTENSION_ENTRY_READY_GENERATIONS := 1
const TILLER_EXTENSION_EXIT_GUARD_CLEARANCE := 0.015
# A permitted three-to-five millimetre body step can consume several millimetres
# of wrist-annulus room before the next post-leg solve. Relocate the foam contact
# while the current pair is still safe instead of entering unsafe recovery.
const TILLER_EXTENSION_EXIT_WRIST_BODY_RESERVE := 0.006
const TILLER_EXTENSION_EXIT_WRIST_TARGET_RESERVE := 0.020
const TILLER_EXTENSION_ROUTE_GUARD_CLEARANCE := 0.002
const TILLER_EXTENSION_PATH_CLEARANCE := 0.0
const TILLER_EXTENSION_CENTRAL_BODY_CLEARANCE := 0.015
const TILLER_EXTENSION_COMFORT_BAND_WEIGHT := 5.0
const TILLER_EXTENSION_COMFORT_TARGET_WEIGHT := 0.55
const TILLER_EXTENSION_DISTANCE_CONTINUITY_WEIGHT := 0.04
const TILLER_EXTENSION_AUTHORED_DISTANCE_WEIGHT := 0.005
const TILLER_EXTENSION_HAND_SCORE_HYSTERESIS := 0.004
# Five-millimetre samples keep the collision-safe palm point visually stable;
# the former 27.5 mm grid made otherwise identical poses choose visibly
# different points on the foam grip.
const TILLER_EXTENSION_HAND_DISTANCE_SAMPLES := 89
const TILLER_EXTENSION_VISIBLE_TIP_LENGTH := 1.10
const TILLER_EXTENSION_SOFT_JOINT_ANGLE := deg_to_rad(68.0)
const TILLER_EXTENSION_HARD_JOINT_ANGLE := deg_to_rad(82.0)
const TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE := deg_to_rad(120.0)
const TILLER_EXTENSION_SPRING_STIFFNESS := 144.0
const TILLER_EXTENSION_SPRING_DAMPING := 24.0
const TILLER_EXTENSION_MAX_ANGULAR_SPEED := 1.8
const TILLER_EXTENSION_MAX_SUBSTEP := 1.0 / 120.0
# Bound the published pair by elapsed time as well as its collision-tested
# substeps. These match the former 2.5 degree / 12 mm limits at 60 Hz without
# halving the available movement at 30 Hz or doubling it at 120 Hz.
const TILLER_EXTENSION_VISIBLE_DIRECTION_SPEED := deg_to_rad(150.0)
const TILLER_EXTENSION_VISIBLE_DISTANCE_SPEED := 0.72
const TILLER_EXTENSION_PAIR_DIRECTION_COUPLING_EPSILON := deg_to_rad(0.10)
const TILLER_EXTENSION_PAIR_DISTANCE_COUPLING_EPSILON := 0.001
const TILLER_EXTENSION_SHAFT_CLEARANCE := 0.013
const TILLER_EXTENSION_TARGET_SWITCH_MARGIN := deg_to_rad(1.25)
const TILLER_EXTENSION_CLIPPED_VELOCITY_RETENTION := 0.35
const RUDDER_VISUAL_RESPONSE := 5.0
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

enum TillerExtensionPairMode {
	NONE,
	NORMAL,
	HANDOVER,
	EXIT,
}

@export var environment_path: NodePath
@export_range(0.0, 1.0, 0.01) var vang_tension := 0.58

@onready var sail_pivot: Node3D = $SailPivot
@onready var boom_pivot: Node3D = $SailPivot/BoomPivot
@onready var sail: IlcaSevenSail = $SailPivot/Sail
@onready var clew_strap: IlcaHardwarePart = $SailPivot/BoomPivot/ClewStrap
@onready var clew_grommet: Node3D = $SailPivot/ClewGrommet
@onready var rudder_pivot: Node3D = $RudderPivot
@onready var tiller_extension_pivot: Node3D = $RudderPivot/TillerExtensionPivot
@onready var sailor: WindwardSailor = $Sailor
@onready var sailing_environment: SailingEnvironment = get_node_or_null(environment_path) as SailingEnvironment

var sailing_state := SailingState.new()
var sailing_command := SailingCommand.new()
var _body_pose_search_cursors: Dictionary = {}
var _body_pose_skip_direct: Dictionary = {}
var maneuver_profile: Dictionary = {
	"resolve_us": 0,
	"preview_us": 0,
	"search_us": 0,
	"resolve_calls": 0,
	"preview_calls": 0,
	"search_calls": 0,
}
var _effective_sailing_command := SailingCommand.new()
var _heave_position := FLOAT_ORIGIN_OFFSET
var _heave_velocity := 0.0
var _wave_pitch := 0.0
var _pitch_velocity := 0.0
var _wave_roll := 0.0
var _roll_velocity := 0.0
var _tiller_extension_direction_rudder := Vector3.FORWARD
var _tiller_extension_angular_velocity := Vector3.ZERO
var _tiller_extension_last_safe_direction := Vector3.FORWARD
var _tiller_extension_last_rudder_basis := Basis.IDENTITY
var _tiller_extension_last_joint_boat := Vector3.ZERO
var _tiller_extension_rudder_basis_initialized := false
var _tiller_extension_hand_distance := TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
var _tiller_extension_last_safe_hand_distance := TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
var _tiller_extension_hand_distance_initialized := false
var _tiller_extension_initialized := false
var _tiller_extension_blocked := false
var _tiller_extension_active_joint_limit := TILLER_EXTENSION_HARD_JOINT_ANGLE
var _tiller_extension_normal_target_index := -1
var _tiller_extension_normal_target_initialized := false
var _tiller_extension_handover_route_active := false
var _tiller_extension_entry_align_active := false
var _tiller_extension_entry_ready_generations := 0
var _tiller_extension_entry_step_permit := false
var _tiller_extension_entry_bridge_active := false
var _tiller_extension_entry_bridge_direction_rudder := Vector3.FORWARD
var _tiller_extension_entry_bridge_distance := TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
var _tiller_extension_central_ready_generations := 0
var _tiller_extension_central_step_permit := false
var _tiller_extension_central_bridge_active := false
var _tiller_extension_central_bridge_direction_rudder := Vector3.FORWARD
var _tiller_extension_central_bridge_distance := TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
var _tiller_extension_central_bridge_side := 0.0
var _tiller_extension_exit_align_active := false
var _tiller_extension_exit_align_ready := true
var _tiller_extension_exit_ready_generations := 0
var _tiller_extension_exit_tracking := false
var _tiller_extension_exit_step_permit := false
var _tiller_extension_exit_target_direction_rudder := Vector3.FORWARD
var _tiller_extension_exit_target_distance := TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
var _tiller_extension_exit_bridge_active := false
var _tiller_extension_exit_bridge_direction_rudder := Vector3.FORWARD
var _tiller_extension_exit_bridge_distance := TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
var _tiller_extension_seated_return_step_permit := false
var _tiller_extension_driven_pair_mode := TillerExtensionPairMode.NONE
var _tiller_extension_driven_target_direction_rudder := Vector3.FORWARD
var _tiller_extension_driven_target_distance := TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
var _tiller_extension_maneuver_pair_delta := 0.0


func _ready() -> void:
	sailing_state.heading_radians = rotation.y
	_heave_position = global_position.y
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_sync_sail_clew_to_boom()


func _physics_process(delta: float) -> void:
	if sailing_environment:
		sailing_state.true_wind_velocity = sailing_environment.true_wind_at(global_position)
		sailing_state.water_current_velocity = sailing_environment.current_at(global_position)

	sailing_command.rudder = Input.get_axis("steer_port", "steer_starboard")
	sailing_command.sheet_delta = Input.get_axis("sheet_in", "sheet_out")
	# Keep the player command raw for presentation/IK. Sheet-in only changes the
	# loaded line during the primary pull; the extension hand holds tension while
	# the primary releases and reaches forward. Sheet-out remains a continuous,
	# metered slip. This separates line physics from the visible hand cycle without
	# hiding the input from the sailor state machine.
	if is_instance_valid(sailor):
		sailor.advance_sheet_handling(delta)
	_effective_sailing_command.rudder = sailing_command.rudder
	_effective_sailing_command.sheet_delta = (
		sailor.effective_sheet_delta(sailing_command.sheet_delta)
		if is_instance_valid(sailor)
		else sailing_command.sheet_delta
	)
	sailing_state.step(delta, _effective_sailing_command)

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
	# A real ILCA boom rises aft from the gooseneck. More vang lowers the clew
	# while the mast-sleeved luff stays fixed; the sail surface follows the actual
	# clew strap rather than remaining behind as a disconnected rigid triangle.
	var target_boom_pitch := deg_to_rad(lerpf(-7.0, -4.5, vang_tension))
	boom_pivot.rotation.x = lerp_angle(
		boom_pivot.rotation.x,
		target_boom_pitch,
		1.0 - exp(-7.0 * delta)
	)
	_sync_sail_clew_to_boom()
	var target_rudder_angle := sailing_command.rudder * MAX_RUDDER_VISUAL_ANGLE
	rudder_pivot.rotation.y = lerp_angle(
		rudder_pivot.rotation.y,
		target_rudder_angle,
		1.0 - exp(-RUDDER_VISUAL_RESPONSE * delta)
	)


func resolve_tiller_extension(
	delta: float,
	body_capsules: Array,
	immediate: bool = false
) -> void:
	# The A5198-style rubber joint articulates in every direction, but the carbon
	# shaft itself is fixed-length. Resolve a safe physical direction first; the
	# sailor's arm IK consumes the resulting grip later in the same post-leg-IK
	# skeleton modifier cycle.
	if not is_instance_valid(sailor) or not is_instance_valid(tiller_extension_pivot):
		return
	# One completed NORMAL solve authorizes at most one bounded Crouch->Seated
	# animation step. A new modifier generation must re-sample the moved body before
	# another step can be consumed.
	_tiller_extension_seated_return_step_permit = false
	var joint_boat := rudder_pivot.transform * tiller_extension_pivot.position
	_rebase_tiller_extension_state_to_current_rudder_basis(joint_boat)
	var handover_progress := sailor.hand_exchange_progress()
	var entry_preposition_requested := (
		sailor.tiller_handover_entry_preposition_requested()
	)
	var handover_requested := (
		entry_preposition_requested
		or (handover_progress > 0.001 and handover_progress < 0.999)
	)
	if handover_requested:
		_tiller_extension_handover_route_active = true
	if entry_preposition_requested:
		_tiller_extension_entry_align_active = true
	else:
		_tiller_extension_entry_align_active = false
		_tiller_extension_entry_ready_generations = 0
		_tiller_extension_entry_step_permit = false
		_tiller_extension_entry_bridge_active = false
	var is_handover := _tiller_extension_handover_route_active
	var central_route_requested := (
		is_handover
		and not entry_preposition_requested
		and handover_progress > 0.001
		and handover_progress < 0.72
	)
	if not central_route_requested:
		_tiller_extension_central_ready_generations = 0
		_tiller_extension_central_step_permit = false
		_tiller_extension_central_bridge_active = false
		_tiller_extension_central_bridge_side = 0.0
	var max_joint_angle := (
		TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
		if is_handover
		else TILLER_EXTENSION_HARD_JOINT_ANGLE
	)
	_tiller_extension_active_joint_limit = max_joint_angle
	# The capsules must be sampled inside the post-leg-IK modifier callback.
	# Refuse a pre-IK or incomplete solve rather than accepting a shaft direction
	# that can pass through the rendered thighs.
	if body_capsules.size() < 3:
		_tiller_extension_blocked = true
		return
	if sailor.maneuver_active():
		_resolve_maneuver_tiller_extension(delta, body_capsules, immediate)
		return
	# Direction and grip distance form one physical state during the route exit.
	# Starting at 72% keeps the torso from overtaking a centreline grip while the
	# old direction waits for a different distance (and vice versa). The generous
	# 120-degree joint envelope remains active until the visual handover has ended
	# and the resolved pair is genuinely back in the ordinary steering corridor.
	var exit_pair_requested := (
		_tiller_extension_handover_route_active
		and (handover_progress >= 0.72 or not handover_requested)
	)
	if handover_requested and handover_progress < 0.72:
		_tiller_extension_exit_align_active = false
		_tiller_extension_exit_align_ready = true
		_tiller_extension_exit_ready_generations = 0
		_tiller_extension_exit_tracking = false
		_tiller_extension_exit_step_permit = false
		_tiller_extension_exit_bridge_active = false
	elif exit_pair_requested:
		_tiller_extension_exit_align_active = true
	var desired_grip_boat := sailor.tiller_control_target_boat_position(
		sailing_command.rudder
	)
	var desired_boat := desired_grip_boat - joint_boat
	if desired_boat.length_squared() <= 0.000001:
		return
	var requested_hand_distance := clampf(
		desired_boat.length(),
		TILLER_EXTENSION_MIN_HAND_DISTANCE,
		TILLER_EXTENSION_MAX_HAND_DISTANCE
	)
	var desired_rudder := _clamp_tiller_extension_cone(
		(rudder_pivot.basis.inverse() * desired_boat).normalized(),
		max_joint_angle
	)
	if entry_preposition_requested:
		# Entry alignment is a coupled direction+grip problem. Solving direction
		# first left the old contact distance unsafe at the first angular microstep,
		# while solving distance first had the inverse dependency. Reuse the atomic
		# pair integrator already used by EXIT_ALIGN so neither degree of freedom
		# waits forever for the other.
		var entry_side := signf(sailor.seat_side)
		if is_zero_approx(entry_side):
			entry_side = signf(desired_boat.x)
		if is_zero_approx(entry_side):
			entry_side = -1.0
		var entry_pair := _find_safe_handover_tiller_extension_pair(
			desired_rudder,
			requested_hand_distance,
			joint_boat,
			body_capsules,
			entry_side,
			TILLER_EXTENSION_ENTRY_PREPOSITION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_ROUTE_GUARD_CLEARANCE
		)
		if entry_pair.is_empty():
			_tiller_extension_blocked = true
			_tiller_extension_entry_ready_generations = 0
			_tiller_extension_entry_step_permit = false
			return
		var entry_direction: Vector3 = entry_pair["direction"]
		var entry_distance: float = entry_pair["distance"]
		var current_entry_pair_is_safe := _tiller_extension_pair_is_safe(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			joint_boat,
			body_capsules,
			true,
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
			entry_side
		)
		if not current_entry_pair_is_safe:
			# A path planner cannot prove a route whose first sample is already inside
			# a live capsule. Drop any stale waypoint and let the bounded pair recovery
			# below improve the current direction/contact while the body stays gated.
			_tiller_extension_entry_bridge_active = false
		# A safe entry endpoint is not sufficient when the direct direction+distance
		# chord crosses a thigh. Plan an upper-hemisphere waypoint before advancing,
		# exactly as EXIT_ALIGN does, so a previously comfortable foam contact can
		# slide and rotate around the live body instead of deadlocking at t=0.
		if _tiller_extension_entry_bridge_active:
			var entry_bridge_reached := (
				_tiller_extension_direction_rudder.angle_to(
					_tiller_extension_entry_bridge_direction_rudder
				) <= TILLER_EXTENSION_EXIT_DIRECTION_TOLERANCE
				and absf(
					_tiller_extension_hand_distance
					- _tiller_extension_entry_bridge_distance
				) <= TILLER_EXTENSION_EXIT_DISTANCE_TOLERANCE
			)
			if (
				entry_bridge_reached
				and _tiller_extension_pair_path_is_safe(
					_tiller_extension_direction_rudder,
					_tiller_extension_hand_distance,
					entry_direction,
					entry_distance,
					joint_boat,
					body_capsules,
					entry_side,
					TILLER_EXTENSION_PATH_CLEARANCE
				)
			):
				_tiller_extension_entry_bridge_active = false
		if (
			current_entry_pair_is_safe
			and not _tiller_extension_entry_bridge_active
			and not _tiller_extension_pair_path_is_safe(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				entry_direction,
				entry_distance,
				joint_boat,
				body_capsules,
				entry_side,
				TILLER_EXTENSION_PATH_CLEARANCE
			)
		):
			var entry_bridge_pair := _find_safe_tiller_extension_exit_bridge_pair(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				entry_direction,
				entry_distance,
				joint_boat,
				body_capsules,
				entry_side,
				TILLER_EXTENSION_PATH_CLEARANCE
			)
			if entry_bridge_pair.is_empty():
				_tiller_extension_blocked = true
				_tiller_extension_entry_ready_generations = 0
				_tiller_extension_entry_step_permit = false
				_tiller_extension_angular_velocity = Vector3.ZERO
				return
			else:
				_tiller_extension_entry_bridge_active = true
				_tiller_extension_entry_bridge_direction_rudder = (
					entry_bridge_pair["direction"]
				)
				_tiller_extension_entry_bridge_distance = (
					entry_bridge_pair["distance"]
				)
		var driven_entry_direction := entry_direction
		var driven_entry_distance := entry_distance
		if _tiller_extension_entry_bridge_active:
			driven_entry_direction = _tiller_extension_entry_bridge_direction_rudder
			driven_entry_distance = _tiller_extension_entry_bridge_distance
		_record_tiller_extension_driven_pair(
			TillerExtensionPairMode.HANDOVER,
			driven_entry_direction,
			driven_entry_distance
		)
		if not _advance_tiller_extension_pair(
			delta,
			driven_entry_direction,
			driven_entry_distance,
			joint_boat,
			body_capsules,
			entry_side,
			true,
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
			immediate
		):
			_tiller_extension_blocked = true
			_tiller_extension_entry_ready_generations = 0
			_tiller_extension_entry_step_permit = false
			_publish_tiller_extension_pose()
			return
		_tiller_extension_blocked = false
		var entry_pair_ready := (
			not _tiller_extension_entry_bridge_active
			and _tiller_extension_direction_rudder.angle_to(entry_direction)
			<= deg_to_rad(1.0)
			and absf(_tiller_extension_hand_distance - entry_distance)
			<= 0.002
			and _tiller_extension_pair_is_safe(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules,
				true,
				TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
				entry_side
			)
			and _tiller_extension_pair_clearance_margin(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules
			) >= TILLER_EXTENSION_ROUTE_GUARD_CLEARANCE
		)
		if entry_pair_ready:
			_tiller_extension_entry_ready_generations += 1
		else:
			_tiller_extension_entry_ready_generations = 0
			_tiller_extension_entry_step_permit = false
		if (
			_tiller_extension_entry_ready_generations
			>= TILLER_EXTENSION_ENTRY_READY_GENERATIONS
		):
			_tiller_extension_entry_step_permit = true
		_publish_tiller_extension_pose()
		return
	if exit_pair_requested:
		var exit_side := signf(sailor.seat_side)
		if is_zero_approx(exit_side):
			exit_side = signf(desired_boat.x)
		if is_zero_approx(exit_side):
			exit_side = 1.0
		var exit_pair_is_normal := true
		var exit_pair := _find_safe_normal_tiller_extension_pair(
			joint_boat,
			body_capsules,
			exit_side,
			requested_hand_distance,
			handover_requested,
			true
		)
		if exit_pair.is_empty():
			exit_pair = _find_safe_tiller_extension_exit_tracking_pair(
				joint_boat,
				body_capsules,
				exit_side,
				not handover_requested
			)
			exit_pair_is_normal = false
		if exit_pair.is_empty():
			# No ordinary exit target exists yet, but the behind-the-back route may
			# still be physically safe. Keep the body gated without calling that
			# verified holding pose a collision.
			_tiller_extension_blocked = not _tiller_extension_pair_is_safe(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules,
				true,
				TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
				exit_side
			)
			_tiller_extension_exit_align_ready = false
			_tiller_extension_exit_ready_generations = 0
			_tiller_extension_exit_tracking = false
			_tiller_extension_exit_step_permit = false
			if _tiller_extension_blocked:
				_tiller_extension_angular_velocity = Vector3.ZERO
			return
		var exit_target_direction: Vector3 = exit_pair["direction"]
		var exit_target_distance: float = exit_pair["distance"]
		_tiller_extension_exit_target_direction_rudder = exit_target_direction
		_tiller_extension_exit_target_distance = exit_target_distance
		if _tiller_extension_exit_bridge_active:
			# A previous bridge can become stale after a tiny body move. If the live
			# pair is already the verified normal target, release the bridge first.
			if _tiller_extension_exit_pair_is_ready(
				joint_boat,
				body_capsules,
				exit_side,
				exit_target_direction,
				exit_target_distance,
				exit_pair_is_normal
			):
				_tiller_extension_exit_bridge_active = false
			elif (
				_tiller_extension_direction_rudder.angle_to(
					_tiller_extension_exit_bridge_direction_rudder
				) <= TILLER_EXTENSION_EXIT_DIRECTION_TOLERANCE
				and absf(
					_tiller_extension_hand_distance
					- _tiller_extension_exit_bridge_distance
				) <= TILLER_EXTENSION_EXIT_DISTANCE_TOLERANCE
				and _tiller_extension_pair_path_is_safe(
					_tiller_extension_direction_rudder,
					_tiller_extension_hand_distance,
					exit_target_direction,
					exit_target_distance,
					joint_boat,
					body_capsules,
					exit_side
				)
			):
				_tiller_extension_exit_bridge_active = false
		# A NORMAL endpoint can become available far from the still-safe foam contact.
		# If the current pair no longer carries enough wrist/capsule reserve for the
		# next body step, latch a nearby high-reserve tracking waypoint whose two legs
		# to the current and NORMAL pairs are both certified. This avoids collapsing
		# the old arm across a large distance jump while the body waits in place.
		var current_exit_pair_carries_body := (
			_tiller_extension_exit_pair_meets_readiness_prerequisites(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules,
				exit_side,
				false
			)
		)
		var exit_normal_endpoint_is_distant := (
			_tiller_extension_direction_rudder.angle_to(exit_target_direction)
			> TILLER_EXTENSION_EXIT_DIRECTION_TOLERANCE
			or absf(
				_tiller_extension_hand_distance - exit_target_distance
			) > TILLER_EXTENSION_EXIT_DISTANCE_TOLERANCE
		)
		if (
			not _tiller_extension_exit_bridge_active
			and exit_pair_is_normal
			and exit_normal_endpoint_is_distant
			and not current_exit_pair_carries_body
		):
			var reserve_tracking_pair := (
				_find_safe_tiller_extension_exit_tracking_pair(
					joint_boat,
					body_capsules,
					exit_side,
					not handover_requested,
					exit_target_direction,
					exit_target_distance
				)
			)
			if not reserve_tracking_pair.is_empty():
				_tiller_extension_exit_bridge_active = true
				_tiller_extension_exit_tracking = false
				_tiller_extension_exit_step_permit = false
				_tiller_extension_exit_bridge_direction_rudder = (
					reserve_tracking_pair["direction"]
				)
				_tiller_extension_exit_bridge_distance = (
					reserve_tracking_pair["distance"]
				)
		# Plan a connected direction+distance route before asking the spring to
		# rotate. Trying the blocked diagonal first can leave a barely-clear pair
		# exposed to the next idle-animation capsule sample.
		if (
			not _tiller_extension_exit_bridge_active
			and not _tiller_extension_pair_path_is_safe(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				exit_target_direction,
				exit_target_distance,
				joint_boat,
				body_capsules,
				exit_side
			)
		):
			var planned_bridge_pair := _find_safe_tiller_extension_exit_bridge_pair(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				exit_target_direction,
				exit_target_distance,
				joint_boat,
				body_capsules,
				exit_side
			)
			if not planned_bridge_pair.is_empty():
				_tiller_extension_exit_bridge_active = true
				_tiller_extension_exit_tracking = false
				_tiller_extension_exit_step_permit = false
				_tiller_extension_exit_bridge_direction_rudder = (
					planned_bridge_pair["direction"]
				)
				_tiller_extension_exit_bridge_distance = (
					planned_bridge_pair["distance"]
				)
			elif exit_pair_is_normal:
				# A safe NORMAL endpoint is not usable when the wrist/capsule-safe set is
				# disconnected from the current pair and no verified bridge joins them.
				# Driving that unreachable endpoint made recovery wait on numerical drift
				# inside the inner-wrist boundary. Prefer a connected EXIT tracking pair;
				# if none exists, hold the current pose and keep the body gated.
				var connected_tracking_pair := (
					_find_safe_tiller_extension_exit_tracking_pair(
						joint_boat,
						body_capsules,
						exit_side,
						not handover_requested,
						exit_target_direction,
						exit_target_distance
					)
				)
				if connected_tracking_pair.is_empty():
					_tiller_extension_blocked = not _tiller_extension_pair_is_safe(
						_tiller_extension_direction_rudder,
						_tiller_extension_hand_distance,
						joint_boat,
						body_capsules,
						true,
						TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
						exit_side
					)
					_tiller_extension_exit_align_ready = false
					_tiller_extension_exit_ready_generations = 0
					_tiller_extension_exit_tracking = false
					_tiller_extension_exit_step_permit = false
					if _tiller_extension_blocked:
						_tiller_extension_angular_velocity = Vector3.ZERO
					_publish_tiller_extension_pose()
					return
				_tiller_extension_exit_bridge_active = true
				_tiller_extension_exit_tracking = false
				_tiller_extension_exit_step_permit = false
				_tiller_extension_exit_bridge_direction_rudder = (
					connected_tracking_pair["direction"]
				)
				_tiller_extension_exit_bridge_distance = (
					connected_tracking_pair["distance"]
				)
		var driven_exit_direction := exit_target_direction
		var driven_exit_distance := exit_target_distance
		if _tiller_extension_exit_bridge_active:
			driven_exit_direction = _tiller_extension_exit_bridge_direction_rudder
			driven_exit_distance = _tiller_extension_exit_bridge_distance
		_record_tiller_extension_driven_pair(
			TillerExtensionPairMode.EXIT,
			driven_exit_direction,
			driven_exit_distance
		)
		var before_exit_direction := _tiller_extension_direction_rudder
		var before_exit_distance := _tiller_extension_hand_distance
		if not _advance_tiller_extension_pair(
			delta,
			driven_exit_direction,
			driven_exit_distance,
			joint_boat,
			body_capsules,
			exit_side,
			true,
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
			immediate
		):
			_tiller_extension_blocked = true
			_tiller_extension_exit_align_ready = false
			_tiller_extension_exit_ready_generations = 0
			_tiller_extension_exit_tracking = false
			_tiller_extension_exit_step_permit = false
			_publish_tiller_extension_pose()
			return
		# A guard-valid endpoint can sit exactly on the exit reserve boundary. The
		# damped spring then approaches its final degree
		# asymptotically, leaving the body gated even though the remaining complete
		# pair path is verified. Complete only that visually sub-threshold tail, and
		# only after revalidating both the path and every endpoint readiness guard.
		if (
			not _tiller_extension_exit_bridge_active
			and _tiller_extension_direction_rudder.angle_to(exit_target_direction)
			<= TILLER_EXTENSION_EXIT_COMPLETION_DIRECTION
			and absf(
				_tiller_extension_hand_distance - exit_target_distance
			) <= TILLER_EXTENSION_EXIT_COMPLETION_DISTANCE
			and _tiller_extension_pair_path_is_safe(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				exit_target_direction,
				exit_target_distance,
				joint_boat,
				body_capsules,
				exit_side
			)
			and _tiller_extension_exit_pair_meets_readiness_prerequisites(
				exit_target_direction,
				exit_target_distance,
				joint_boat,
				body_capsules,
				exit_side,
				exit_pair_is_normal
			)
		):
			_tiller_extension_direction_rudder = exit_target_direction.normalized()
			_tiller_extension_hand_distance = exit_target_distance
			_tiller_extension_angular_velocity = Vector3.ZERO
			_tiller_extension_last_safe_direction = (
				_tiller_extension_direction_rudder
			)
			_tiller_extension_last_safe_hand_distance = (
				_tiller_extension_hand_distance
			)
		var exit_made_progress := (
			before_exit_direction.angle_to(_tiller_extension_direction_rudder)
			> 0.00001
			or absf(
				before_exit_distance - _tiller_extension_hand_distance
			) > 0.0001
		)
		var exit_still_has_work := (
			_tiller_extension_direction_rudder.angle_to(exit_target_direction)
			> TILLER_EXTENSION_EXIT_DIRECTION_TOLERANCE
			or absf(
				_tiller_extension_hand_distance - exit_target_distance
			) > TILLER_EXTENSION_EXIT_DISTANCE_TOLERANCE
		)
		if (
			not _tiller_extension_exit_bridge_active
			and not exit_made_progress
			and exit_still_has_work
		):
			var bridge_pair := _find_safe_tiller_extension_exit_bridge_pair(
				before_exit_direction,
				before_exit_distance,
				exit_target_direction,
				exit_target_distance,
				joint_boat,
				body_capsules,
				exit_side
			)
			if not bridge_pair.is_empty():
				_tiller_extension_exit_bridge_active = true
				_tiller_extension_exit_tracking = false
				_tiller_extension_exit_step_permit = false
				_tiller_extension_exit_bridge_direction_rudder = (
					bridge_pair["direction"]
				)
				_tiller_extension_exit_bridge_distance = bridge_pair["distance"]
		_tiller_extension_blocked = false
		var exit_pair_ready := (
			not _tiller_extension_exit_bridge_active
			and _tiller_extension_exit_pair_is_ready(
			joint_boat,
			body_capsules,
			exit_side,
			exit_target_direction,
			exit_target_distance,
			exit_pair_is_normal
			)
		)
		var exit_bridge_step_ready := (
			_tiller_extension_exit_bridge_active
			and _tiller_extension_direction_rudder.angle_to(
				_tiller_extension_exit_bridge_direction_rudder
			) <= deg_to_rad(0.5)
			and absf(
				_tiller_extension_hand_distance
				- _tiller_extension_exit_bridge_distance
			) <= 0.002
			and _tiller_extension_pair_is_safe(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules,
				true,
				TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
				exit_side
			)
			and _tiller_extension_wrist_guard_has_exit_body_reserve(
				_tiller_extension_candidate_wrist_guard(
					_tiller_extension_direction_rudder,
					_tiller_extension_hand_distance,
					joint_boat
				)
			)
			and _tiller_extension_pair_clearance_margin(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules
			) >= TILLER_EXTENSION_EXIT_GUARD_CLEARANCE
		)
		# Body motion only needs a guard-valid current handover pair. Requiring the
		# pair to have already converged on its final NORMAL endpoint can turn a
		# harmless foam-grip relocation into a visible multi-frame tack pause. Keep
		# endpoint alignment and its debounce below as the stricter route-release
		# contract; this permit advances the body by one bounded step, after which
		# the new capsule pose is sampled and validated again.
		var exit_guarded_body_step_ready := (
			not _tiller_extension_exit_bridge_active
			and _tiller_extension_exit_pair_meets_readiness_prerequisites(
				_tiller_extension_direction_rudder,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules,
				exit_side,
				false
			)
		)
		if exit_pair_ready:
			_tiller_extension_exit_ready_generations += 1
		else:
			_tiller_extension_exit_ready_generations = 0
			_tiller_extension_exit_align_ready = false
			_tiller_extension_exit_step_permit = false
		var ready_generation_count := (
			1
			if _tiller_extension_exit_tracking
			else TILLER_EXTENSION_EXIT_READY_GENERATIONS
		)
		_tiller_extension_exit_align_ready = (
			_tiller_extension_exit_ready_generations
			>= ready_generation_count
		)
		if (
			_tiller_extension_exit_align_ready
			or exit_bridge_step_ready
			or exit_guarded_body_step_ready
		):
			_tiller_extension_exit_tracking = true
			_tiller_extension_exit_step_permit = true
		if (
			not handover_requested
			and exit_pair_is_normal
			and _tiller_extension_exit_align_ready
			and absf(sailor.seat_side - exit_side) <= 0.0035
		):
			_tiller_extension_handover_route_active = false
			_tiller_extension_exit_align_active = false
			_tiller_extension_exit_tracking = false
			_tiller_extension_exit_step_permit = false
			_tiller_extension_exit_bridge_active = false
			_tiller_extension_active_joint_limit = TILLER_EXTENSION_HARD_JOINT_ANGLE
		_publish_tiller_extension_pose()
		return
	if not is_handover:
		var normal_side := signf(sailor.seat_side)
		if is_zero_approx(normal_side):
			normal_side = signf(desired_boat.x)
		if is_zero_approx(normal_side):
			normal_side = 1.0
		var normal_pair := _find_safe_normal_tiller_extension_pair(
			joint_boat,
			body_capsules,
			normal_side,
			requested_hand_distance
		)
		_tiller_extension_seated_return_step_permit = _resolve_normal_tiller_extension_transaction(
			delta, joint_boat, body_capsules, normal_side, normal_pair, immediate
		)
		return
	# The remaining active route is the central 0..72% handover. Resolve shaft
	# direction and freely selected foam contact as one pair so neither hand is
	# forced through a folded or over-extended arm solution while the body crosses.
	var central_side := signf(desired_boat.x)
	if is_zero_approx(central_side):
		central_side = signf(sailor.seat_side)
	if is_zero_approx(central_side):
		central_side = signf(
			(rudder_pivot.basis * _tiller_extension_direction_rudder).x
		)
	if is_zero_approx(central_side):
		central_side = 1.0
	var central_pair := _find_safe_handover_tiller_extension_pair(
		desired_rudder,
		requested_hand_distance,
		joint_boat,
		body_capsules,
		central_side,
		TILLER_EXTENSION_MIN_HAND_DISTANCE,
		TILLER_EXTENSION_CENTRAL_BODY_CLEARANCE
	)
	if central_pair.is_empty():
		_tiller_extension_blocked = true
		_tiller_extension_central_ready_generations = 0
		_tiller_extension_central_step_permit = false
		_tiller_extension_angular_velocity = Vector3.ZERO
		return
	var central_direction: Vector3 = central_pair["direction"]
	var central_distance: float = central_pair["distance"]
	var current_central_pair_is_safe := _tiller_extension_pair_is_safe(
		_tiller_extension_direction_rudder,
		_tiller_extension_hand_distance,
		joint_boat,
		body_capsules,
		true,
		TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
		central_side
	)
	if (
		_tiller_extension_central_bridge_active
		and current_central_pair_is_safe
		and not is_equal_approx(
			_tiller_extension_central_bridge_side,
			central_side
		)
	):
		_tiller_extension_central_bridge_active = false
	if _tiller_extension_central_bridge_active and current_central_pair_is_safe:
		var central_bridge_path_is_live := _tiller_extension_pair_path_is_safe(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			_tiller_extension_central_bridge_direction_rudder,
			_tiller_extension_central_bridge_distance,
			joint_boat,
			body_capsules,
			central_side,
			TILLER_EXTENSION_PATH_CLEARANCE
		)
		if not central_bridge_path_is_live:
			_tiller_extension_central_bridge_active = false
		else:
			var central_bridge_reached := (
				_tiller_extension_direction_rudder.angle_to(
					_tiller_extension_central_bridge_direction_rudder
				) <= TILLER_EXTENSION_EXIT_DIRECTION_TOLERANCE
				and absf(
					_tiller_extension_hand_distance
					- _tiller_extension_central_bridge_distance
				) <= TILLER_EXTENSION_EXIT_DISTANCE_TOLERANCE
			)
			if (
				central_bridge_reached
				and _tiller_extension_pair_path_is_safe(
					_tiller_extension_direction_rudder,
					_tiller_extension_hand_distance,
					central_direction,
					central_distance,
					joint_boat,
					body_capsules,
					central_side,
					TILLER_EXTENSION_PATH_CLEARANCE
				)
			):
				_tiller_extension_central_bridge_active = false
	if (
		current_central_pair_is_safe
		and not _tiller_extension_central_bridge_active
		and not _tiller_extension_pair_path_is_safe(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			central_direction,
			central_distance,
			joint_boat,
			body_capsules,
			central_side,
			TILLER_EXTENSION_PATH_CLEARANCE
		)
	):
		var central_bridge_pair := _find_safe_tiller_extension_exit_bridge_pair(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			central_direction,
			central_distance,
			joint_boat,
			body_capsules,
			central_side,
			TILLER_EXTENSION_PATH_CLEARANCE
		)
		if central_bridge_pair.is_empty():
			_tiller_extension_blocked = true
			_tiller_extension_central_ready_generations = 0
			_tiller_extension_central_step_permit = false
			_tiller_extension_angular_velocity = Vector3.ZERO
			return
		_tiller_extension_central_bridge_active = true
		_tiller_extension_central_bridge_side = central_side
		_tiller_extension_central_bridge_direction_rudder = (
			central_bridge_pair["direction"]
		)
		_tiller_extension_central_bridge_distance = central_bridge_pair["distance"]
	var driven_central_direction := central_direction
	var driven_central_distance := central_distance
	if _tiller_extension_central_bridge_active:
		driven_central_direction = (
			_tiller_extension_central_bridge_direction_rudder
		)
		driven_central_distance = _tiller_extension_central_bridge_distance
	_record_tiller_extension_driven_pair(
		TillerExtensionPairMode.HANDOVER,
		driven_central_direction,
		driven_central_distance
	)
	if not _advance_tiller_extension_pair(
		delta,
		driven_central_direction,
		driven_central_distance,
		joint_boat,
		body_capsules,
		central_side,
		true,
		TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
		immediate
	):
		_tiller_extension_blocked = true
		_tiller_extension_central_ready_generations = 0
		_tiller_extension_central_step_permit = false
		_publish_tiller_extension_pose()
		return
	_tiller_extension_blocked = false
	# Body movement needs a guarded current pose, not a fully settled spring.
	# Waiting for the last half-degree of a critically damped route made the sailor
	# visibly freeze even though the shaft, contact and both wrists were already
	# safe. Each permit still advances only one bounded seat step, after which the
	# moved capsules are sampled again before another permit can be issued.
	var central_pair_ready := (
		_tiller_extension_pair_is_safe(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			joint_boat,
			body_capsules,
			true,
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
			central_side
		)
		and _tiller_extension_pair_clearance_margin(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			joint_boat,
			body_capsules
		) >= TILLER_EXTENSION_CENTRAL_BODY_CLEARANCE
	)
	if central_pair_ready:
		_tiller_extension_central_ready_generations += 1
	else:
		_tiller_extension_central_ready_generations = 0
		_tiller_extension_central_step_permit = false
	if (
		_tiller_extension_central_ready_generations
		>= TILLER_EXTENSION_ENTRY_READY_GENERATIONS
	):
		_tiller_extension_central_step_permit = true
	_publish_tiller_extension_pose()
	return


func tiller_extension_joint_angle() -> float:
	return Vector3.FORWARD.angle_to(_tiller_extension_direction_rudder)


func tiller_extension_is_blocked() -> bool:
	return _tiller_extension_blocked


func tiller_extension_active_joint_limit() -> float:
	return _tiller_extension_active_joint_limit


func tiller_extension_direction_boat() -> Vector3:
	return (rudder_pivot.basis * _tiller_extension_direction_rudder).normalized()


func tiller_extension_hand_distance() -> float:
	return _tiller_extension_hand_distance


func tiller_extension_handover_route_active() -> bool:
	return _tiller_extension_handover_route_active


func tiller_extension_exit_alignment_ready() -> bool:
	return (
		not _tiller_extension_exit_align_active
		or _tiller_extension_exit_align_ready
	)


func consume_tiller_extension_exit_step_permission() -> bool:
	# This is an edge-triggered permission, not a level signal. The sailor may
	# move once, then the next post-leg-IK modifier generation must validate the
	# new body capsules before another millimetre of the tack is allowed.
	if (
		not _tiller_extension_exit_align_active
		or not _tiller_extension_exit_tracking
		or not _tiller_extension_exit_step_permit
	):
		return false
	_tiller_extension_exit_step_permit = false
	_tiller_extension_exit_align_ready = false
	_tiller_extension_exit_ready_generations = 0
	return true


func consume_tiller_extension_entry_step_permission() -> bool:
	if (
		not _tiller_extension_entry_align_active
		or not _tiller_extension_entry_step_permit
	):
		return false
	_tiller_extension_entry_step_permit = false
	_tiller_extension_entry_ready_generations = 0
	return true


func consume_tiller_extension_central_step_permission() -> bool:
	# Central crossing uses the same edge-triggered handshake as entry and exit.
	# One verified pair permits one bounded body step; the next modifier generation
	# must re-sample the moved shoulders and thighs before movement can continue.
	if not _tiller_extension_central_step_permit:
		return false
	_tiller_extension_central_step_permit = false
	_tiller_extension_central_ready_generations = 0
	return true


func consume_tiller_extension_seated_return_step_permission() -> bool:
	if not _tiller_extension_seated_return_step_permit:
		return false
	_tiller_extension_seated_return_step_permit = false
	return true


func prepare_tiller_extension_body_pose_frame() -> void:
	if (
		not is_instance_valid(rudder_pivot)
		or not is_instance_valid(tiller_extension_pivot)
		or not _tiller_extension_initialized
		or not _tiller_extension_hand_distance_initialized
		or not _tiller_extension_rudder_basis_initialized
	):
		return
	# Physics can move the rudder before the body tests its next pose. Prepare the
	# shared coordinate frame explicitly before any read-only trial or pair commit.
	_rebase_tiller_extension_state_to_current_rudder_basis(
		rudder_pivot.transform * tiller_extension_pivot.position
	)


func capture_tiller_extension_body_pose_pair_state() -> Dictionary:
	if (
		not is_instance_valid(rudder_pivot)
		or not is_instance_valid(tiller_extension_pivot)
		or not _tiller_extension_initialized
		or not _tiller_extension_hand_distance_initialized
		or not _tiller_extension_rudder_basis_initialized
	):
		return {}
	return {
		"direction": _tiller_extension_direction_rudder,
		"distance": _tiller_extension_hand_distance,
		"last_safe_direction": _tiller_extension_last_safe_direction,
		"last_safe_distance": _tiller_extension_last_safe_hand_distance,
		"angular_velocity": _tiller_extension_angular_velocity,
		"initialized": _tiller_extension_initialized,
		"distance_initialized": _tiller_extension_hand_distance_initialized,
		"rudder_basis": _tiller_extension_last_rudder_basis,
		"joint_boat": _tiller_extension_last_joint_boat,
		"basis_initialized": _tiller_extension_rudder_basis_initialized,
		"driven_mode": _tiller_extension_driven_pair_mode,
		"driven_direction": _tiller_extension_driven_target_direction_rudder,
		"driven_distance": _tiller_extension_driven_target_distance,
		"active_joint_limit": _tiller_extension_active_joint_limit,
		"route_active": _tiller_extension_handover_route_active,
		"exit_ready": _tiller_extension_exit_align_ready,
	}


func restore_tiller_extension_body_pose_pair_state(
	snapshot: Dictionary,
	body_capsules: Array,
	side: float,
	handover: bool
) -> bool:
	# This restores a coupled body/shaft trial inside one prepared physics frame.
	# A snapshot from a different rudder frame cannot rewind the rudder itself.
	for key in [
		"direction", "distance", "last_safe_direction", "last_safe_distance",
		"angular_velocity", "initialized", "distance_initialized", "rudder_basis",
		"joint_boat", "basis_initialized", "driven_mode", "driven_direction",
		"driven_distance", "active_joint_limit", "route_active", "exit_ready",
	]:
		if not snapshot.has(key):
			_tiller_extension_blocked = true
			_tiller_extension_maneuver_pair_delta = 0.0
			return false
	if (
		not is_instance_valid(rudder_pivot)
		or not is_instance_valid(tiller_extension_pivot)
		or not bool(snapshot["initialized"])
		or not bool(snapshot["distance_initialized"])
		or not bool(snapshot["basis_initialized"])
		or snapshot["rudder_basis"] != rudder_pivot.basis.orthonormalized()
		or snapshot["joint_boat"] != rudder_pivot.transform * tiller_extension_pivot.position
		or not tiller_extension_pair_accepts_body_pose(body_capsules, side, handover, snapshot)
	):
		_tiller_extension_blocked = true
		_tiller_extension_maneuver_pair_delta = 0.0
		return false
	_tiller_extension_direction_rudder = snapshot["direction"]
	_tiller_extension_hand_distance = float(snapshot["distance"])
	_tiller_extension_last_safe_direction = snapshot["last_safe_direction"]
	_tiller_extension_last_safe_hand_distance = float(snapshot["last_safe_distance"])
	_tiller_extension_angular_velocity = snapshot["angular_velocity"]
	_tiller_extension_initialized = bool(snapshot["initialized"])
	_tiller_extension_hand_distance_initialized = bool(snapshot["distance_initialized"])
	_tiller_extension_last_rudder_basis = snapshot["rudder_basis"]
	_tiller_extension_last_joint_boat = snapshot["joint_boat"]
	_tiller_extension_rudder_basis_initialized = bool(snapshot["basis_initialized"])
	_tiller_extension_driven_pair_mode = int(snapshot["driven_mode"]) as TillerExtensionPairMode
	_tiller_extension_driven_target_direction_rudder = snapshot["driven_direction"]
	_tiller_extension_driven_target_distance = float(snapshot["driven_distance"])
	_tiller_extension_active_joint_limit = float(snapshot["active_joint_limit"])
	_tiller_extension_handover_route_active = bool(snapshot["route_active"])
	_tiller_extension_exit_align_ready = bool(snapshot["exit_ready"])
	_tiller_extension_maneuver_pair_delta = 0.0
	_tiller_extension_seated_return_step_permit = false
	_publish_tiller_extension_pose()
	_tiller_extension_blocked = true
	return true


func _resolve_normal_tiller_extension_transaction(
	delta: float,
	joint_boat: Vector3,
	body_capsules: Array,
	side: float,
	target_pair: Dictionary,
	immediate: bool
) -> bool:
	# An active-to-normal transition can commit its last body/shaft step before
	# reaching this solve. Ordinary steering may spend only that frame's remainder.
	var pair_delta := maxf(delta - _tiller_extension_maneuver_pair_delta, 0.0)
	_tiller_extension_maneuver_pair_delta = 0.0
	var previous_direction := _tiller_extension_direction_rudder
	var previous_distance := _tiller_extension_hand_distance
	var previous_safe_direction := _tiller_extension_last_safe_direction
	var previous_safe_distance := _tiller_extension_last_safe_hand_distance
	var previous_velocity := _tiller_extension_angular_velocity
	var previous_initialized := _tiller_extension_initialized
	var previous_distance_initialized := _tiller_extension_hand_distance_initialized
	var previous_pair := {"direction": previous_direction, "distance": previous_distance}
	# Capture eligibility before either spring or recovery routine mutates the
	# current pair. Unsafe starting poses still retain their full recovery path.
	var require_neutral_progress := (
		not target_pair.is_empty()
		and not sailor.maneuver_active()
		and absf(sailing_command.rudder) <= 0.001
		and absf(rudder_pivot.rotation.y) <= deg_to_rad(1.0)
		and previous_initialized and previous_distance_initialized
		and tiller_extension_pair_accepts_body_pose(body_capsules, side, false, previous_pair)
	)
	if not target_pair.is_empty():
		_record_tiller_extension_driven_pair(
			TillerExtensionPairMode.NORMAL, target_pair["direction"], target_pair["distance"]
		)
		var return_pair := _normal_tiller_neutral_return_pair(pair_delta, joint_boat, target_pair)
		if (
			not return_pair.is_empty()
			and tiller_extension_pair_accepts_body_pose(body_capsules, side, false, return_pair)
			and _tiller_extension_body_pose_pair_midpoint_is_safe(return_pair, body_capsules, side, false)
			and commit_tiller_extension_body_pose_pair(return_pair)
		):
			_tiller_extension_maneuver_pair_delta = 0.0
			return true
		_advance_tiller_extension_pair(
			pair_delta, target_pair["direction"], target_pair["distance"], joint_boat,
			body_capsules, side, false, TILLER_EXTENSION_HARD_JOINT_ANGLE, immediate
		)
		var proposed := {
			"direction": _tiller_extension_direction_rudder,
			"distance": _tiller_extension_hand_distance,
			"from_direction": previous_direction,
			"from_distance": previous_distance,
		}
		var proposed_progresses := (
			not require_neutral_progress
			or _normal_tiller_fallback_reduces_contact_error(
				previous_pair, proposed, target_pair, joint_boat, rudder_pivot.basis
			)
		)
		if (
			proposed_progresses
			and tiller_extension_pair_accepts_body_pose(body_capsules, side, false, proposed)
			and (
				not previous_initialized
				or not previous_distance_initialized
				or _tiller_extension_body_pose_pair_midpoint_is_safe(proposed, body_capsules, side, false)
			)
		):
			_tiller_extension_last_safe_direction = _tiller_extension_direction_rudder
			_tiller_extension_last_safe_hand_distance = _tiller_extension_hand_distance
			_tiller_extension_blocked = false
			_publish_tiller_extension_pose()
			return true
	# The spring and recovery routines may change several coupled fields before
	# returning. Roll all of them back before seeking a strict bounded alternative.
	_tiller_extension_direction_rudder = previous_direction
	_tiller_extension_hand_distance = previous_distance
	_tiller_extension_last_safe_direction = previous_safe_direction
	_tiller_extension_last_safe_hand_distance = previous_safe_distance
	_tiller_extension_angular_velocity = previous_velocity
	_tiller_extension_initialized = previous_initialized
	_tiller_extension_hand_distance_initialized = previous_distance_initialized
	var alternative := preview_tiller_extension_pair_for_body_pose(body_capsules, side, false, pair_delta, 0, target_pair)
	var alternative_progresses := (
		not require_neutral_progress
		or _normal_tiller_fallback_reduces_contact_error(
			previous_pair, alternative, target_pair, joint_boat, rudder_pivot.basis
		)
	)
	if (
		not alternative.is_empty()
		and alternative_progresses
		and _tiller_extension_body_pose_pair_midpoint_is_safe(alternative, body_capsules, side, false)
		and commit_tiller_extension_body_pose_pair(alternative)
	):
		_tiller_extension_initialized = true
		_tiller_extension_hand_distance_initialized = true
		_tiller_extension_maneuver_pair_delta = 0.0
		_tiller_extension_blocked = false
		return true
	_tiller_extension_angular_velocity = Vector3.ZERO
	_tiller_extension_blocked = not (
		previous_initialized
		and previous_distance_initialized
		and tiller_extension_pair_accepts_body_pose(body_capsules, side, false)
	)
	if not _tiller_extension_blocked:
		_publish_tiller_extension_pose()
		return true
	return false


static func _normal_tiller_fallback_reduces_contact_error(
	current_pair: Dictionary,
	candidate_pair: Dictionary,
	target_pair: Dictionary,
	joint_boat: Vector3,
	rudder_basis: Basis
) -> bool:
	# A safe neutral hold must not chase a rejected target by sliding farther
	# away from it. Compare the actual palm contact, not independent angle and
	# distance scores which can improve one coordinate while worsening the grip.
	if current_pair.is_empty() or candidate_pair.is_empty() or target_pair.is_empty():
		return false
	var current_contact := joint_boat + rudder_basis * Vector3(current_pair["direction"]) * float(current_pair["distance"])
	var candidate_contact := joint_boat + rudder_basis * Vector3(candidate_pair["direction"]) * float(candidate_pair["distance"])
	var target_contact := joint_boat + rudder_basis * Vector3(target_pair["direction"]) * float(target_pair["distance"])
	if not current_contact.is_finite() or not candidate_contact.is_finite() or not target_contact.is_finite():
		return false
	return candidate_contact.distance_to(target_contact) < current_contact.distance_to(target_contact) - 0.00001


func _normal_tiller_neutral_return_pair(delta: float, joint_boat: Vector3, target_pair: Dictionary) -> Dictionary:
	# The rudder already eases to neutral. Near its endpoint, a second angular
	# spring can leave the coupled hand contact drifting long after release.
	# Complete only that small remainder at the existing physical slide speed.
	if (
		delta <= 0.0 or not _tiller_extension_initialized or not _tiller_extension_hand_distance_initialized
		or absf(sailing_command.rudder) > 0.001 or absf(rudder_pivot.rotation.y) > deg_to_rad(1.0)
		or sailor.maneuver_active()
	):
		return {}
	var from_direction := _tiller_extension_direction_rudder
	var from_distance := _tiller_extension_hand_distance
	var target_direction: Vector3 = target_pair["direction"]
	var target_distance := float(target_pair["distance"])
	var from_contact := joint_boat + rudder_pivot.basis * from_direction * from_distance
	var target_contact := joint_boat + rudder_pivot.basis * target_direction * target_distance
	var contact_error := from_contact.distance_to(target_contact)
	if contact_error > TILLER_EXTENSION_NEUTRAL_CATCHUP_DISTANCE:
		return {}
	var fraction := 1.0
	var direction_error := from_direction.angle_to(target_direction)
	var distance_error := absf(target_distance - from_distance)
	if direction_error > 0.000001:
		fraction = minf(fraction, _tiller_extension_direction_step_budget(delta) / direction_error)
	if distance_error > 0.000001:
		fraction = minf(fraction, _tiller_extension_distance_step_budget(delta) / distance_error)
	if contact_error > 0.000001:
		fraction = minf(fraction, TILLER_EXTENSION_HAND_SLIDE_SPEED * minf(delta, 0.10) / contact_error)
	return {
		"from_direction": from_direction, "from_distance": from_distance,
		"direction": from_direction.slerp(target_direction, fraction).normalized(),
		"distance": lerpf(from_distance, target_distance, fraction), "delta": delta,
	}


func _tiller_extension_body_pose_pair_midpoint_is_safe(
	pair: Dictionary,
	body_capsules: Array,
	side: float,
	handover: bool
) -> bool:
	var from_direction: Vector3 = pair.get("from_direction", _tiller_extension_direction_rudder)
	var target_direction: Vector3 = pair["direction"]
	var midpoint := {
		"direction": from_direction.slerp(target_direction, 0.5).normalized(),
		"distance": lerpf(float(pair.get("from_distance", _tiller_extension_hand_distance)), float(pair["distance"]), 0.5),
	}
	return tiller_extension_pair_accepts_body_pose(body_capsules, side, handover, midpoint)


func tiller_extension_pair_accepts_body_pose(
	body_capsules: Array,
	side: float,
	handover: bool,
	pair: Dictionary = {}
) -> bool:
	# The caller applies a complete trial body pose before this read-only check.
	# Wrist prediction therefore reads the same shoulders as these capsules.
	if body_capsules.size() < 3 or not is_instance_valid(sailor):
		return false
	var direction: Vector3 = pair.get("direction", _tiller_extension_direction_rudder)
	var distance := float(pair.get("distance", _tiller_extension_hand_distance))
	if (
		not direction.is_finite()
		or direction.length_squared() <= 0.000001
		or not is_finite(distance)
		or distance < TILLER_EXTENSION_MIN_HAND_DISTANCE
		or distance > TILLER_EXTENSION_MAX_HAND_DISTANCE
	):
		return false
	var joint_boat := rudder_pivot.transform * tiller_extension_pivot.position
	var max_angle := (
		TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
		if handover
		else TILLER_EXTENSION_HARD_JOINT_ANGLE
	)
	return (
		_tiller_extension_pair_is_safe(
			direction, distance, joint_boat, body_capsules, handover, max_angle, side
		)
		and _tiller_extension_pair_clearance_margin(
			direction, distance, joint_boat, body_capsules
		) >= TILLER_EXTENSION_CENTRAL_BODY_CLEARANCE
		and bool(_tiller_extension_candidate_wrist_guard(
			direction, distance, joint_boat, true
		).get("safe", false))
	)


func preview_tiller_extension_pair_for_body_pose(
	body_capsules: Array,
	side: float,
	handover: bool,
	delta: float,
	search_channel: int = 0,
	target_hint: Dictionary = {}
) -> Dictionary:
	var started_us := Time.get_ticks_usec()
	var result := _preview_tiller_extension_pair_for_body_pose_impl(
		body_capsules, side, handover, delta, search_channel, target_hint
	)
	maneuver_profile["preview_us"] = int(maneuver_profile["preview_us"]) + Time.get_ticks_usec() - started_us
	maneuver_profile["preview_calls"] = int(maneuver_profile["preview_calls"]) + 1
	return result


func _preview_tiller_extension_pair_for_body_pose_impl(
	body_capsules: Array,
	side: float,
	handover: bool,
	delta: float,
	search_channel: int,
	target_hint: Dictionary
) -> Dictionary:
	# Return a bounded proposal only. The body owner verifies the coupled body /
	# shaft sweep before committing; a safe future endpoint alone is insufficient.
	if body_capsules.size() < 3 or delta <= 0.0:
		return {}
	var joint_boat := rudder_pivot.transform * tiller_extension_pivot.position
	var desired_contact := sailor.tiller_control_target_boat_position(
		sailing_command.rudder
	)
	var desired_vector := desired_contact - joint_boat
	if desired_vector.length_squared() <= 0.000001:
		return {}
	var target_direction := (
		rudder_pivot.basis.inverse() * desired_vector.normalized()
	).normalized()
	var target_distance := clampf(
		desired_vector.length(),
		TILLER_EXTENSION_MIN_HAND_DISTANCE,
		TILLER_EXTENSION_MAX_HAND_DISTANCE
	)
	var normal_requested := not handover or sailor.maneuver_phase_name() == &"sit"
	var target_pair: Dictionary = target_hint
	if target_pair.is_empty() and not normal_requested:
		var raw_pair := {"direction": target_direction, "distance": target_distance}
		if tiller_extension_pair_accepts_body_pose(body_capsules, side, handover, raw_pair):
			target_pair = raw_pair
	if normal_requested and target_pair.is_empty():
		target_pair = _find_safe_normal_tiller_extension_pair(
			joint_boat, body_capsules, side, target_distance, false, false, false
		)
	if target_pair.is_empty() and handover:
		target_pair = _find_safe_handover_tiller_extension_pair(
			target_direction, target_distance, joint_boat, body_capsules, side,
			TILLER_EXTENSION_MIN_HAND_DISTANCE, TILLER_EXTENSION_CENTRAL_BODY_CLEARANCE
		)
	if not target_pair.is_empty():
		target_direction = target_pair["direction"]
		target_distance = float(target_pair["distance"])
	var direction_budget := _tiller_extension_direction_step_budget(delta)
	var distance_budget := _tiller_extension_distance_step_budget(delta)
	var current_direction := _tiller_extension_direction_rudder.normalized()
	var current_distance := _tiller_extension_hand_distance
	var target_angle := current_direction.angle_to(target_direction)
	var target_fraction := 1.0
	if target_angle > 0.000001:
		target_fraction = minf(target_fraction, direction_budget / target_angle)
	if absf(target_distance - current_distance) > 0.000001:
		target_fraction = minf(
			target_fraction, distance_budget / absf(target_distance - current_distance)
		)
	var direct_pair := {
		"direction": current_direction.slerp(target_direction, clampf(target_fraction, 0.0, 1.0)).normalized(),
		"distance": lerpf(current_distance, target_distance, clampf(target_fraction, 0.0, 1.0)),
		"from_direction": current_direction, "from_distance": current_distance, "delta": delta,
		"search_channel": search_channel,
	}
	if not bool(_body_pose_skip_direct.get(search_channel, false)) and tiller_extension_pair_accepts_body_pose(body_capsules, side, handover, direct_pair):
		return direct_pair
	var directions: Array[Vector3] = [
		current_direction,
		current_direction.slerp(target_direction, clampf(target_fraction, 0.0, 1.0)).normalized(),
		current_direction.slerp(
			target_direction, minf(1.0, direction_budget / maxf(target_angle, 0.000001))
		).normalized(),
	]
	var tangent_up := Vector3.UP - current_direction * current_direction.dot(Vector3.UP)
	if tangent_up.length_squared() <= 0.000001:
		tangent_up = Vector3.RIGHT - current_direction * current_direction.dot(Vector3.RIGHT)
	tangent_up = tangent_up.normalized()
	var tangent_side := current_direction.cross(tangent_up).normalized()
	for sample_index in range(8):
		var angle := float(sample_index) * TAU / 8.0
		var tangent := tangent_up * cos(angle) + tangent_side * sin(angle)
		directions.append((
			current_direction * cos(direction_budget) + tangent * sin(direction_budget)
		).normalized())
	var distances: Array[float] = [
		current_distance,
		lerpf(current_distance, target_distance, clampf(target_fraction, 0.0, 1.0)),
		move_toward(current_distance, target_distance, distance_budget),
	]
	for amount in [-1.0, -0.5, 0.5, 1.0]:
		distances.append(clampf(
			current_distance + float(amount) * distance_budget,
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE
		))
	var candidates: Array[Dictionary] = []
	for direction in directions:
		for distance in distances:
			var pair := {"direction": direction, "distance": distance}
			var score := (
				direction.angle_to(target_direction) * 2.0
				+ absf(distance - target_distance)
				+ direction.angle_to(current_direction) * 0.05
				+ absf(distance - current_distance) * 0.10
			)
			if not score < INF:
				continue
			candidates.append({"pair": pair, "score": score, "order": candidates.size()})
	# The score is independent of the expensive arm guard. Start each search in
	# ascending order, retaining first occurrence order for equal scores.
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if float(first["score"]) == float(second["score"]):
			return int(first["order"]) < int(second["order"])
		return float(first["score"]) < float(second["score"])
	)
	# A rejected sweep resumes after its last endpoint candidate. Only the index
	# survives; every pair is checked against the live body, contact and history.
	var visit_count := mini(4, candidates.size())
	var cursor := int(_body_pose_search_cursors.get(search_channel, 0))
	for visit in range(visit_count):
		var index := (cursor + visit) % candidates.size()
		var pair: Dictionary = candidates[index]["pair"]
		var candidate_direction: Vector3 = pair["direction"]
		if candidate_direction.angle_to(current_direction) < 0.000001 and absf(float(pair["distance"]) - current_distance) < 0.000001:
			# Holding is the caller's fallback, not progress toward an unreachable
			# target. Returning it here restarted the same search every frame.
			continue
		if not tiller_extension_pair_accepts_body_pose(body_capsules, side, handover, pair):
			continue
		_body_pose_search_cursors[search_channel] = (index + 1) % candidates.size()
		pair["from_direction"] = current_direction
		pair["from_distance"] = current_distance
		pair["delta"] = delta
		pair["search_channel"] = search_channel
		return pair
	if not candidates.is_empty():
		_body_pose_search_cursors[search_channel] = (cursor + visit_count) % candidates.size()
	return {}


func reject_tiller_extension_body_pose_pair(pair: Dictionary) -> void:
	# Endpoint approval is not sweep approval. Do not retry the same direct
	# endpoint forever when the caller rejects its intervening body path.
	_body_pose_skip_direct[int(pair.get("search_channel", 0))] = true


func mark_tiller_extension_control_pose_blocked() -> void:
	_tiller_extension_blocked = true
	_tiller_extension_maneuver_pair_delta = 0.0


func tiller_extension_body_pose_pair_path_is_safe(
	pair: Dictionary,
	body_capsules: Array,
	side: float,
	handover: bool
) -> bool:
	if not pair.has("direction") or not pair.has("distance"):
		return false
	var target_direction: Vector3 = pair["direction"]
	var target_distance := float(pair["distance"])
	for sample_index in range(9):
		var amount := float(sample_index) / 8.0
		var sample := {
			"direction": _tiller_extension_direction_rudder.slerp(target_direction, amount).normalized(),
			"distance": lerpf(_tiller_extension_hand_distance, target_distance, amount),
		}
		if not tiller_extension_pair_accepts_body_pose(body_capsules, side, handover, sample):
			return false
	return true


func commit_tiller_extension_body_pose_pair(pair: Dictionary) -> bool:
	# Only proposals derived from the still-current pair can be committed. The
	# caller has already validated the old, midpoint and future body poses.
	if not pair.has("from_direction") or not pair.has("from_distance"):
		return false
	var from_direction: Vector3 = pair["from_direction"]
	if (
		from_direction.angle_to(_tiller_extension_direction_rudder) > 0.00001
		or absf(float(pair["from_distance"]) - _tiller_extension_hand_distance) > 0.00001
	):
		return false
	var direction: Vector3 = pair.get("direction", Vector3.ZERO)
	var distance := float(pair.get("distance", -1.0))
	var delta := float(pair.get("delta", 0.0))
	if (
		not direction.is_finite()
		or direction.length_squared() <= 0.000001
		or not is_finite(distance)
		or distance < TILLER_EXTENSION_MIN_HAND_DISTANCE
		or distance > TILLER_EXTENSION_MAX_HAND_DISTANCE
		or from_direction.angle_to(direction) > _tiller_extension_direction_step_budget(delta) + 0.00001
		or absf(distance - float(pair["from_distance"])) > _tiller_extension_distance_step_budget(delta) + 0.00001
	):
		return false
	_tiller_extension_direction_rudder = direction.normalized()
	_tiller_extension_hand_distance = distance
	_tiller_extension_last_safe_direction = _tiller_extension_direction_rudder
	_tiller_extension_last_safe_hand_distance = distance
	_tiller_extension_angular_velocity = Vector3.ZERO
	_tiller_extension_blocked = false
	_tiller_extension_maneuver_pair_delta += delta
	var search_channel := int(pair.get("search_channel", 0))
	_body_pose_search_cursors[search_channel] = 0
	_body_pose_skip_direct[search_channel] = false
	_publish_tiller_extension_pose()
	return true


func _resolve_maneuver_tiller_extension(
	delta: float,
	body_capsules: Array,
	immediate: bool
) -> void:
	var started_us := Time.get_ticks_usec()
	_resolve_maneuver_tiller_extension_impl(delta, body_capsules, immediate)
	maneuver_profile["resolve_us"] = int(maneuver_profile["resolve_us"]) + Time.get_ticks_usec() - started_us
	maneuver_profile["resolve_calls"] = int(maneuver_profile["resolve_calls"]) + 1


func _resolve_maneuver_tiller_extension_impl(
	delta: float,
	body_capsules: Array,
	immediate: bool
) -> void:
	# Trial-pose transactions and this final modifier solve share one time budget.
	# Reset before target selection so a rejected target cannot retain spent time
	# into the following render generation.
	var pair_delta := maxf(delta - _tiller_extension_maneuver_pair_delta, 0.0)
	_tiller_extension_maneuver_pair_delta = 0.0
	# Time-driven body poses already own entry, crossing and seating. The shaft
	# follows their anatomical target without restarting the old upper route or
	# demanding one fully settled endpoint before every body movement.
	_tiller_extension_entry_align_active = false
	_tiller_extension_entry_step_permit = false
	_tiller_extension_entry_bridge_active = false
	_tiller_extension_central_step_permit = false
	_tiller_extension_central_bridge_active = false
	_tiller_extension_exit_align_active = false
	_tiller_extension_exit_step_permit = false
	_tiller_extension_exit_bridge_active = false
	var joint_boat := rudder_pivot.transform * tiller_extension_pivot.position
	var side := signf(sailor.seat_side)
	if is_zero_approx(side):
		side = signf(tiller_extension_direction_boat().x)
	if is_zero_approx(side):
		side = 1.0
	if sailor.maneuver_phase_name() == &"sit" and tiller_extension_pair_accepts_body_pose(body_capsules, side, false):
		# A handover ends at a certified normal working pose, not only at one
		# preferred grip sample. Ordinary steering can refine that pose afterward;
		# an unreachable aesthetic target must not hold the completed body in EXIT.
		_tiller_extension_blocked = false
		_tiller_extension_exit_align_ready = true
		_tiller_extension_handover_route_active = false
		_tiller_extension_active_joint_limit = TILLER_EXTENSION_HARD_JOINT_ANGLE
		_record_tiller_extension_driven_pair(TillerExtensionPairMode.NORMAL, _tiller_extension_direction_rudder, _tiller_extension_hand_distance)
		_publish_tiller_extension_pose()
		return
	if pair_delta <= 0.000001 and tiller_extension_pair_accepts_body_pose(body_capsules, side, true):
		# The body's swept commit has already spent this frame's shaft motion.
		# Revalidate its final contact once; another target search cannot move it.
		_tiller_extension_blocked = false
		_publish_tiller_extension_pose()
		return
	var desired_vector := sailor.tiller_control_target_boat_position(sailing_command.rudder) - joint_boat
	if desired_vector.length_squared() <= 0.000001:
		_tiller_extension_blocked = true
		return
	var desired_direction := (rudder_pivot.basis.inverse() * desired_vector.normalized()).normalized()
	var desired_distance := clampf(
		desired_vector.length(), TILLER_EXTENSION_MIN_HAND_DISTANCE, TILLER_EXTENSION_MAX_HAND_DISTANCE
	)
	var normal_requested := sailor.maneuver_phase_name() == &"sit"
	var normal_pair := false
	var target_pair: Dictionary = {}
	if not normal_requested:
		var raw_pair := {"direction": desired_direction, "distance": desired_distance}
		if tiller_extension_pair_accepts_body_pose(body_capsules, side, true, raw_pair):
			target_pair = raw_pair
	if normal_requested:
		target_pair = _find_safe_normal_tiller_extension_pair(
			joint_boat, body_capsules, side, desired_distance
		)
		normal_pair = not target_pair.is_empty()
	if target_pair.is_empty():
		target_pair = _find_safe_handover_tiller_extension_pair(
			desired_direction, desired_distance, joint_boat, body_capsules, side,
			TILLER_EXTENSION_MIN_HAND_DISTANCE, TILLER_EXTENSION_CENTRAL_BODY_CLEARANCE
		)
	if target_pair.is_empty():
		_tiller_extension_blocked = true
		return
	var target_direction: Vector3 = target_pair["direction"]
	var target_distance := float(target_pair["distance"])
	_record_tiller_extension_driven_pair(
		TillerExtensionPairMode.EXIT if normal_requested else TillerExtensionPairMode.HANDOVER,
		target_direction, target_distance
	)
	_tiller_extension_active_joint_limit = TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
	_tiller_extension_handover_route_active = true
	if pair_delta > 0.000001:
		# Target selection already used these same final body capsules. Reuse the
		# goal, not a safety certificate; step endpoint and midpoint stay strict.
		var step_pair := preview_tiller_extension_pair_for_body_pose(body_capsules, side, true, pair_delta, 0, target_pair)
		if (
			not step_pair.is_empty()
			and _tiller_extension_body_pose_pair_midpoint_is_safe(step_pair, body_capsules, side, true)
		):
			_tiller_extension_blocked = not commit_tiller_extension_body_pose_pair(step_pair)
			_tiller_extension_maneuver_pair_delta = 0.0
		else:
			_tiller_extension_blocked = not tiller_extension_pair_accepts_body_pose(body_capsules, side, true)
	else:
		_tiller_extension_blocked = not tiller_extension_pair_accepts_body_pose(body_capsules, side, true)
	var normal_ready := (
		normal_pair
		and not _tiller_extension_blocked
		and _tiller_extension_direction_rudder.angle_to(target_direction) <= TILLER_EXTENSION_EXIT_COMPLETION_DIRECTION
		and absf(_tiller_extension_hand_distance - target_distance) <= TILLER_EXTENSION_EXIT_COMPLETION_DISTANCE
		and tiller_extension_pair_accepts_body_pose(body_capsules, side, false)
	)
	_tiller_extension_exit_align_ready = normal_ready
	if normal_ready:
		_tiller_extension_handover_route_active = false
		_tiller_extension_active_joint_limit = TILLER_EXTENSION_HARD_JOINT_ANGLE
		_record_tiller_extension_driven_pair(TillerExtensionPairMode.NORMAL, target_direction, target_distance)
	if not _tiller_extension_blocked:
		_publish_tiller_extension_pose()


func _find_safe_normal_tiller_extension_pair(
	joint_boat: Vector3,
	body_capsules: Array,
	new_side: float,
	requested_distance: float,
	prefer_current_pair: bool = false,
	require_exit_target_reserve: bool = false,
	remember_choice: bool = true
) -> Dictionary:
	var side := signf(new_side)
	if is_zero_approx(side):
		return {}
	var shoulder_boat := _find_tiller_shoulder_for_side_boat(
		body_capsules,
		side
	)
	if not shoulder_boat.is_finite():
		return {}
	var current_recovery_pair: Dictionary = {}
	if _tiller_extension_hand_distance_initialized:
		var current_direction := _tiller_extension_direction_rudder.normalized()
		var current_boat := (
			rudder_pivot.basis * current_direction
		).normalized()
		var current_contact := (
			joint_boat + current_boat * _tiller_extension_hand_distance
		)
		var current_reach := shoulder_boat.distance_to(current_contact)
		var current_wrist_guard := _tiller_extension_candidate_wrist_guard(
			current_direction,
			_tiller_extension_hand_distance,
			joint_boat
		)
		if (
			current_reach >= TILLER_EXTENSION_EXIT_REACH_MIN
			and current_reach <= TILLER_EXTENSION_EXIT_REACH_MAX
			and bool(current_wrist_guard.get("safe", false))
			and (
				(not prefer_current_pair and not require_exit_target_reserve)
				or _tiller_extension_wrist_guard_has_exit_body_reserve(
					current_wrist_guard
				)
			)
			and _tiller_extension_pair_clearance_margin(
				current_direction,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules
			) >= TILLER_EXTENSION_EXIT_GUARD_CLEARANCE
			and _tiller_extension_pair_is_safe(
				current_direction,
				_tiller_extension_hand_distance,
				joint_boat,
				body_capsules,
				false,
				TILLER_EXTENSION_HARD_JOINT_ANGLE,
				side
			)
		):
			current_recovery_pair = {
				"direction": current_direction,
				"distance": _tiller_extension_hand_distance,
				"candidate_index": _tiller_extension_normal_target_index,
			}
			if prefer_current_pair:
				return current_recovery_pair
	var working_contact := _normal_tiller_working_contact_boat(side)
	var authored_boat := (working_contact - joint_boat).normalized()
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-side * 0.015, -0.015, -0.010),
		Vector3(side * 0.015, -0.015, -0.010),
		Vector3(-side * 0.030, -0.030, -0.020),
		Vector3(side * 0.030, -0.030, -0.020),
		Vector3(0.0, -0.045, -0.030),
	]
	var distance_candidates: Array[float] = [clampf(
		requested_distance,
		TILLER_EXTENSION_MIN_HAND_DISTANCE,
		TILLER_EXTENSION_MAX_HAND_DISTANCE
	)]
	if _tiller_extension_hand_distance_initialized:
		distance_candidates.append(_tiller_extension_hand_distance)
		distance_candidates.append(_tiller_extension_last_safe_hand_distance)
	var previous_normal_target_available := (
		_tiller_extension_driven_pair_mode == TillerExtensionPairMode.NORMAL
	)
	var previous_normal_target_distance := _tiller_extension_driven_target_distance
	if previous_normal_target_available:
		# Retain the previously driven foam contact as a first-class candidate.
		# The ordinary five-millimetre lattice alone can otherwise alternate across
		# a moving score boundary during a port-to-starboard rudder transition.
		distance_candidates.append(previous_normal_target_distance)
	for sample_index in range(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES):
		var ratio := (
			float(sample_index)
			/ float(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES - 1)
		)
		distance_candidates.append(lerpf(
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE,
			ratio
		))
	var best_pair: Dictionary = {}
	var best_score := INF
	var best_direction_error := INF
	var incumbent_branch_pair: Dictionary = {}
	var incumbent_branch_score := INF
	var incumbent_branch_direction_error := INF
	var incumbent_distance_pair: Dictionary = {}
	var incumbent_distance_score := INF
	for candidate_index in range(offsets.size()):
		var candidate_boat := authored_boat
		if candidate_index > 0:
			candidate_boat = (
				authored_boat * TILLER_EXTENSION_SHAFT_LENGTH
				+ offsets[candidate_index]
			).normalized()
		var candidate_rudder := _soften_tiller_extension_target(
			(rudder_pivot.basis.inverse() * candidate_boat).normalized(),
			TILLER_EXTENSION_HARD_JOINT_ANGLE
		)
		var resolved_boat := (
			rudder_pivot.basis * candidate_rudder
		).normalized()
		if not _normal_extension_direction_preserves_side(resolved_boat, side):
			continue
		if not _extension_direction_is_within_cone(
			candidate_rudder,
			TILLER_EXTENSION_HARD_JOINT_ANGLE
		):
			continue
		if not _extension_direction_is_safe(
			candidate_rudder,
			joint_boat,
			body_capsules
		):
			continue
		var candidate_direction_error := resolved_boat.angle_to(authored_boat)
		for candidate_distance in distance_candidates:
			if not _tiller_extension_hand_contact_is_safe(
				joint_boat,
				resolved_boat,
				body_capsules,
				candidate_distance
			):
				continue
			if _tiller_extension_pair_clearance_margin(
				candidate_rudder,
				candidate_distance,
				joint_boat,
				body_capsules
			) < TILLER_EXTENSION_EXIT_GUARD_CLEARANCE:
				continue
			var candidate_wrist_guard := _tiller_extension_candidate_wrist_guard(
				candidate_rudder,
				candidate_distance,
				joint_boat
			)
			if not bool(candidate_wrist_guard.get("safe", false)):
				continue
			if (
				require_exit_target_reserve
				and not _tiller_extension_wrist_guard_has_exit_target_reserve(
					candidate_wrist_guard
				)
			):
				continue
			var contact := joint_boat + resolved_boat * candidate_distance
			var shoulder_reach := shoulder_boat.distance_to(contact)
			if (
				shoulder_reach < TILLER_EXTENSION_EXIT_REACH_MIN
				or shoulder_reach > TILLER_EXTENSION_EXIT_REACH_MAX
			):
				continue
			var score := (
				resolved_boat.angle_to(authored_boat) * 2.0
				+ candidate_rudder.angle_to(
					_tiller_extension_direction_rudder
				) * 0.08
				+ _tiller_extension_hand_distance_score(
					joint_boat,
					resolved_boat,
					candidate_distance,
					requested_distance,
					shoulder_boat,
					working_contact
				)
			)
			if score < best_score:
				best_score = score
				best_direction_error = candidate_direction_error
				best_pair = {
					"direction": candidate_rudder,
					"distance": candidate_distance,
					"candidate_index": candidate_index,
				}
			if candidate_index == _tiller_extension_normal_target_index:
				if score < incumbent_branch_score:
					incumbent_branch_score = score
					incumbent_branch_direction_error = candidate_direction_error
					incumbent_branch_pair = {
						"direction": candidate_rudder,
						"distance": candidate_distance,
						"candidate_index": candidate_index,
					}
				if (
					previous_normal_target_available
					and is_equal_approx(
						candidate_distance,
						previous_normal_target_distance
					)
					and score < incumbent_distance_score
				):
					incumbent_distance_score = score
					incumbent_distance_pair = {
						"direction": candidate_rudder,
						"distance": candidate_distance,
						"candidate_index": candidate_index,
					}
	if best_pair.is_empty():
		# A bounded EXIT tracking pose can be ordinary-corridor safe even while the
		# crouched body temporarily blocks every authored normal lattice point. Certify
		# that already-rendered pair as NORMAL only as a recovery fallback; this breaks
		# the route-release/Seated-pose cycle without preferring it over a canonical
		# candidate or moving the shaft to an unverified state.
		return current_recovery_pair
	var selected_pair := best_pair
	var selected_score := best_score
	var retained_incumbent_branch := false
	# Reconstruct the incumbent offset against this generation's authored ray.
	# Keep that live direction while it remains safe unless another branch improves
	# authored alignment by the full Schmitt margin; never freeze an old local ray.
	if (
		not incumbent_branch_pair.is_empty()
		and (
			incumbent_branch_direction_error - best_direction_error
			< TILLER_EXTENSION_TARGET_SWITCH_MARGIN
		)
	):
		selected_pair = incumbent_branch_pair
		selected_score = incumbent_branch_score
		retained_incumbent_branch = true
	# Distance hysteresis is valid only while the same direction branch survives.
	# A genuinely unsafe old contact or a branch switch adopts the new best point
	# immediately; a sub-threshold score change keeps the prior driven foam point.
	if (
		retained_incumbent_branch
		and not incumbent_distance_pair.is_empty()
		and incumbent_distance_score <= (
			selected_score + TILLER_EXTENSION_HAND_SCORE_HYSTERESIS
		)
	):
		selected_pair = incumbent_distance_pair
	if remember_choice and not selected_pair.is_empty():
		_tiller_extension_normal_target_index = int(
			selected_pair.get("candidate_index", 0)
		)
		_tiller_extension_normal_target_initialized = true
	return selected_pair


func _find_safe_tiller_extension_exit_tracking_pair(
	joint_boat: Vector3,
	body_capsules: Array,
	new_side: float,
	require_normal_recovery: bool = false,
	connected_target_direction_rudder: Vector3 = Vector3.ZERO,
	connected_target_distance: float = -1.0
) -> Dictionary:
	var side := signf(new_side)
	var shoulder_boat := _find_tiller_shoulder_for_side_boat(
		body_capsules,
		side
	)
	if is_zero_approx(side) or not shoulder_boat.is_finite():
		return {}
	var current_direction := _tiller_extension_direction_rudder.normalized()
	var current_boat := (
		rudder_pivot.basis * current_direction
	).normalized()
	var current_pair_is_safe := _tiller_extension_pair_is_safe(
		current_direction,
		_tiller_extension_hand_distance,
		joint_boat,
		body_capsules,
		true,
		TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
		side
	)
	var has_connected_target := (
		connected_target_direction_rudder.length_squared() > 0.000001
		and connected_target_distance >= TILLER_EXTENSION_MIN_HAND_DISTANCE
	)
	# These are safe tracking lanes, not authored hand poses. The current lane is
	# always considered first; the others raise the fixed shaft around the torso
	# only when its existing foam contact can no longer carry the moving body.
	var tracking_vectors_boat: Array[Vector3] = [
		current_boat,
		Vector3(side * 0.10, 0.84, -0.53),
		Vector3(side * 0.22, 0.84, -0.50),
		Vector3(side * 0.34, 0.80, -0.49),
		Vector3(-side * 0.08, 0.86, -0.50),
		Vector3(side * 0.15, 0.92, -0.36),
		Vector3(side * 0.28, 0.88, -0.38),
	]
	var distance_candidates: Array[float] = [
		_tiller_extension_hand_distance,
		_tiller_extension_last_safe_hand_distance,
	]
	for sample_index in range(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES):
		var ratio := (
			float(sample_index)
			/ float(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES - 1)
		)
		distance_candidates.append(lerpf(
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE,
			ratio
		))
	var best_pair: Dictionary = {}
	var best_score := INF
	for tracking_vector_boat in tracking_vectors_boat:
		var candidate_direction := _clamp_tiller_extension_cone(
			(
				rudder_pivot.basis.inverse()
				* tracking_vector_boat.normalized()
			).normalized(),
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
		)
		var candidate_boat := (
			rudder_pivot.basis * candidate_direction
		).normalized()
		for candidate_distance in distance_candidates:
			if not _tiller_extension_pair_is_safe(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules,
				true,
				TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
				side
			):
				continue
			var candidate_wrist_guard := _tiller_extension_candidate_wrist_guard(
				candidate_direction,
				candidate_distance,
				joint_boat
			)
			var candidate_is_current := (
				current_direction.angle_to(candidate_direction) <= 0.00001
				and absf(
					_tiller_extension_hand_distance - candidate_distance
				) <= 0.0001
			)
			var candidate_has_exit_reserve := (
				_tiller_extension_wrist_guard_has_exit_body_reserve(
					candidate_wrist_guard
				)
				if candidate_is_current
				else _tiller_extension_wrist_guard_has_exit_target_reserve(
					candidate_wrist_guard
				)
			)
			if not candidate_has_exit_reserve:
				continue
			# Once both hands have completed the exchange, an EXIT tracking lane is
			# useful only if it can become an ordinary new-side steering pose. Without
			# this filter the closest wrong-side lane selected itself forever: Crouch
			# waited for route release while route release waited for a NORMAL lane.
			if require_normal_recovery and not _tiller_extension_pair_is_safe(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules,
				false,
				TILLER_EXTENSION_HARD_JOINT_ANGLE,
				side
			):
				continue
			if _tiller_extension_pair_clearance_margin(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules
			) < TILLER_EXTENSION_EXIT_GUARD_CLEARANCE:
				continue
			var contact := joint_boat + candidate_boat * candidate_distance
			var shoulder_reach := shoulder_boat.distance_to(contact)
			if (
				shoulder_reach < TILLER_EXTENSION_EXIT_REACH_MIN
				or shoulder_reach > TILLER_EXTENSION_EXIT_REACH_MAX
			):
				continue
			var score := (
				current_direction.angle_to(candidate_direction) * 2.0
				+ absf(
					_tiller_extension_hand_distance - candidate_distance
				) * 0.8
				+ absf(
					shoulder_reach - TILLER_EXTENSION_COMFORT_REACH_TARGET
				) * 0.25
			)
			# Path probes dominate this search. Once a connected candidate exists,
			# candidates that cannot beat its geometry score cannot affect selection.
			if score >= best_score:
				continue
			if current_pair_is_safe and not _tiller_extension_pair_path_is_safe(
				current_direction,
				_tiller_extension_hand_distance,
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules,
				side
			):
				continue
			if has_connected_target:
				if not current_pair_is_safe:
					continue
				if not _tiller_extension_pair_path_is_safe(
					candidate_direction,
					candidate_distance,
					connected_target_direction_rudder,
					connected_target_distance,
					joint_boat,
					body_capsules,
					side
				):
					continue
			best_score = score
			best_pair = {
				"direction": candidate_direction,
				"distance": candidate_distance,
			}
	return best_pair


func _find_tiller_shoulder_for_side_boat(
	body_capsules: Array,
	seat_side_value: float
) -> Vector3:
	var shoulder_label: StringName = (
		&"left_shoulder" if seat_side_value > 0.0 else &"right_shoulder"
	)
	for capsule_variant in body_capsules:
		var capsule: Dictionary = capsule_variant
		if StringName(capsule.get("label", &"")) != shoulder_label:
			continue
		var shoulder_from: Vector3 = capsule.get("from", Vector3.INF)
		var shoulder_to: Vector3 = capsule.get("to", shoulder_from)
		return (shoulder_from + shoulder_to) * 0.5
	return Vector3.INF


func _find_safe_tiller_extension_exit_bridge_pair(
	current_direction: Vector3,
	current_distance: float,
	target_direction: Vector3,
	target_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	new_side: float,
	minimum_clearance: float = 0.0
) -> Dictionary:
	var side := signf(new_side)
	var shoulder_boat := _find_tiller_shoulder_for_side_boat(
		body_capsules,
		side
	)
	if is_zero_approx(side) or not shoulder_boat.is_finite():
		return {}
	# The common real-world escape is to keep the rubber-joint direction still,
	# slide the hand along the foam, then rotate. Prefer that exact two-leg route
	# before searching a different upper-hemisphere shaft direction.
	var shared_distance := _find_tiller_extension_pair_bridge_distance(
		current_direction,
		target_direction,
		current_distance,
		target_distance,
		joint_boat,
		body_capsules,
		side,
		true,
		TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
	)
	if (
		shared_distance >= 0.0
		and absf(shared_distance - current_distance) > 0.0005
		and _tiller_extension_pair_path_is_safe(
			current_direction,
			current_distance,
			current_direction,
			shared_distance,
			joint_boat,
			body_capsules,
			side,
			minimum_clearance
		)
		and _tiller_extension_pair_path_is_safe(
			current_direction,
			shared_distance,
			target_direction,
			target_distance,
			joint_boat,
			body_capsules,
			side,
			minimum_clearance
		)
	):
		return {
			"direction": current_direction,
			"distance": shared_distance,
		}
	# Raise the fixed shaft around the live capsule obstacle before descending to
	# the ordinary steering ray. Candidate legs are verified end-to-end below;
	# these vectors are merely a compact upper-hemisphere search lattice.
	var bridge_vectors_boat: Array[Vector3] = [
		Vector3(side * 0.10, 0.84, -0.53),
		Vector3(side * 0.22, 0.84, -0.50),
		Vector3(0.0, 0.88, -0.48),
		Vector3(side * 0.34, 0.80, -0.49),
		Vector3(-side * 0.08, 0.86, -0.50),
		Vector3(side * 0.15, 0.92, -0.36),
		Vector3(0.0, 0.94, -0.34),
	]
	var best_pair: Dictionary = {}
	var best_score := INF
	for bridge_vector_boat in bridge_vectors_boat:
		var bridge_direction := _clamp_tiller_extension_cone(
			(rudder_pivot.basis.inverse() * bridge_vector_boat.normalized()).normalized(),
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
		)
		if not _extension_direction_is_safe(
			bridge_direction,
			joint_boat,
			body_capsules
		):
			continue
		for sample_index in range(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES):
			var ratio := (
				float(sample_index)
				/ float(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES - 1)
			)
			var bridge_distance := lerpf(
				TILLER_EXTENSION_MIN_HAND_DISTANCE,
				TILLER_EXTENSION_MAX_HAND_DISTANCE,
				ratio
			)
			if not _tiller_extension_pair_is_safe(
				bridge_direction,
				bridge_distance,
				joint_boat,
				body_capsules,
				true,
				TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
				side
			):
				continue
			if _tiller_extension_pair_clearance_margin(
				bridge_direction,
				bridge_distance,
				joint_boat,
				body_capsules
			) < minimum_clearance:
				continue
			var bridge_boat := (
				rudder_pivot.basis * bridge_direction
			).normalized()
			var bridge_contact := joint_boat + bridge_boat * bridge_distance
			var shoulder_reach := shoulder_boat.distance_to(bridge_contact)
			if (
				shoulder_reach < TILLER_EXTENSION_EXIT_REACH_MIN
				or shoulder_reach > TILLER_EXTENSION_EXIT_REACH_MAX
			):
				continue
			if not _tiller_extension_pair_path_is_safe(
				current_direction,
				current_distance,
				bridge_direction,
				bridge_distance,
				joint_boat,
				body_capsules,
				side,
				minimum_clearance
			):
				continue
			if not _tiller_extension_pair_path_is_safe(
				bridge_direction,
				bridge_distance,
				target_direction,
				target_distance,
				joint_boat,
				body_capsules,
				side,
				minimum_clearance
			):
				continue
			var score := (
				current_direction.angle_to(bridge_direction)
				+ bridge_direction.angle_to(target_direction)
				+ absf(current_distance - bridge_distance) * 0.35
				+ absf(bridge_distance - target_distance) * 0.20
				+ absf(shoulder_reach - TILLER_EXTENSION_COMFORT_REACH_TARGET)
			)
			if score < best_score:
				best_score = score
				best_pair = {
					"direction": bridge_direction,
					"distance": bridge_distance,
				}
	return best_pair


func _tiller_extension_pair_path_is_safe(
	from_direction: Vector3,
	from_distance: float,
	to_direction: Vector3,
	to_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	side: float,
	minimum_clearance: float = 0.0
) -> bool:
	# A 12-segment probe skipped the narrow unsafe interval near t=0.10 in the
	# measured tack-exit path and could therefore select the incumbent as its own
	# useless bridge. Forty-eight segments include that interval while this helper
	# remains confined to rare route planning, not the ordinary steering loop.
	for sample_index in range(49):
		var amount := float(sample_index) / 48.0
		var candidate_direction := from_direction.slerp(
			to_direction,
			amount
		).normalized()
		var candidate_distance := lerpf(from_distance, to_distance, amount)
		if not _tiller_extension_pair_is_safe(
			candidate_direction,
			candidate_distance,
			joint_boat,
			body_capsules,
			true,
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
			side
		):
			return false
		if _tiller_extension_pair_clearance_margin(
			candidate_direction,
			candidate_distance,
			joint_boat,
			body_capsules
		) < minimum_clearance:
			return false
	return true


func _normal_tiller_extension_pair_path_is_safe(
	from_direction: Vector3,
	from_distance: float,
	to_direction: Vector3,
	to_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	side: float,
	max_joint_angle: float
) -> bool:
	# Normal steering uses the stricter side corridor and joint cone. A direct
	# route is coupled only after every sampled pair satisfies those same rules.
	for sample_index in range(33):
		var amount := float(sample_index) / 32.0
		var candidate_direction := from_direction.slerp(
			to_direction,
			amount
		).normalized()
		var candidate_distance := lerpf(from_distance, to_distance, amount)
		if not _tiller_extension_pair_is_safe(
			candidate_direction,
			candidate_distance,
			joint_boat,
			body_capsules,
			false,
			max_joint_angle,
			side
		):
			return false
	return true


func _recover_unsafe_tiller_extension_pair(
	target_direction_rudder: Vector3,
	target_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	side: float,
	max_joint_angle: float,
	is_handover: bool,
	delta: float
) -> Dictionary:
	var direction_step_budget := _tiller_extension_direction_step_budget(delta)
	var distance_step_budget := _tiller_extension_distance_step_budget(delta)
	var current_direction := _tiller_extension_direction_rudder.normalized()
	var current_distance := _tiller_extension_hand_distance
	var direction_error := current_direction.angle_to(target_direction_rudder)
	var bounded_direction := target_direction_rudder.normalized()
	if direction_error > direction_step_budget:
		bounded_direction = current_direction.slerp(
			target_direction_rudder,
			direction_step_budget / direction_error
		).normalized()
	var bounded_distance := move_toward(
		current_distance,
		target_distance,
		distance_step_budget
	)
	var distance_has_work := absf(target_distance - current_distance) > 0.000001
	var direction_has_work := direction_error > 0.000001
	var current_margin := _tiller_extension_pair_clearance_margin(
		current_direction,
		current_distance,
		joint_boat,
		body_capsules
	)
	var current_wrist_violation := _tiller_extension_pair_wrist_violation(
		current_direction,
		current_distance,
		joint_boat,
		is_handover
	)
	var best_safe_pair: Dictionary = {}
	var best_safe_progress := -INF
	var best_safe_margin := -INF
	var best_recovery_pair: Dictionary = {}
	var best_recovery_defect := (
		maxf(-current_margin, 0.0) + current_wrist_violation
	)
	var best_recovery_progress := -INF
	# Search a small two-dimensional budget rather than assuming direction and
	# contact distance encounter the capsule boundary at the same normalized time.
	# The selected values are still committed atomically as one physical pair.
	for direction_index in range(9):
		var direction_amount := float(direction_index) / 8.0
		var candidate_direction := current_direction.slerp(
			bounded_direction,
			direction_amount
		).normalized()
		var candidate_boat := (
			rudder_pivot.basis * candidate_direction
		).normalized()
		if is_handover:
			var candidate_side := signf(candidate_boat.x)
			var preserves_normal := (
				not is_zero_approx(candidate_side)
				and _normal_extension_direction_preserves_side(
					candidate_boat,
					candidate_side
				)
			)
			if (
				not preserves_normal
				and not _handover_direction_preserves_route(
					candidate_boat,
					side,
					true
				)
			):
				continue
		elif not _normal_extension_direction_preserves_side(candidate_boat, side):
			continue
		if not _extension_direction_is_within_cone(
			candidate_direction,
			max_joint_angle
		):
			continue
		for distance_index in range(9):
			if direction_index == 0 and distance_index == 0:
				continue
			var distance_amount := float(distance_index) / 8.0
			var candidate_distance := lerpf(
				current_distance,
				bounded_distance,
				distance_amount
			)
			# When only direction or only distance has work, several lattice indices
			# collapse back onto the incumbent. Do not report that zero-motion duplicate
			# as a recovery step; doing so prevents the local escape fallback below from
			# ever running on exactly the one-dimensional EXIT stall it is meant to solve.
			if (
				candidate_direction.is_equal_approx(current_direction)
				and is_equal_approx(candidate_distance, current_distance)
			):
				continue
			var direction_progress := (
				direction_amount if direction_has_work else 1.0
			)
			var distance_progress := (
				distance_amount if distance_has_work else 1.0
			)
			var pair_progress := minf(
				direction_progress,
				distance_progress
			)
			var candidate_margin := _tiller_extension_pair_clearance_margin(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules
			)
			var candidate_wrist_violation := (
				_tiller_extension_pair_wrist_violation(
					candidate_direction,
					candidate_distance,
					joint_boat,
					is_handover
				)
			)
			if _tiller_extension_pair_is_safe(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules,
				is_handover,
				max_joint_angle,
				side
			):
				# Every candidate in this tier already satisfies the complete hard-safety
				# contract. Spend the bounded resolve budget toward the selected pair;
				# prioritizing a marginally larger capsule gap repeatedly chose the first
				# 1.5 mm grid point and turned a 12-generation foam slide into a long pause.
				if (
					pair_progress > best_safe_progress + 0.0001
					or (
						absf(pair_progress - best_safe_progress) <= 0.0001
						and candidate_margin > best_safe_margin
					)
				):
					best_safe_progress = pair_progress
					best_safe_margin = candidate_margin
					best_safe_pair = {
						"direction": candidate_direction,
						"distance": candidate_distance,
						"safe": true,
					}
				continue
			# Recovery must be monotonic in both independent safety dimensions. The
			# former clearance-only score could not move when the shaft was clear but a
			# wrist alone had crossed its annulus, so EXIT waited forever. Never trade a
			# better wrist for deeper collision (or vice versa); among non-worsening
			# states, minimize their combined remaining defect and then prefer route
			# progress. Allowing an equal-defect step is essential on the numerically
			# flat inner-wrist boundary, where a safe foam contact may be several bounded
			# steps away but no individual step improves the measured violation yet.
			# Once the shaft/contact already has positive clearance, that clearance is
			# a usable budget rather than a value that must never decrease. The old
			# comparison froze a 0.60 m folded-wrist contact despite 33 mm of free space
			# and an explicitly safe 0.925 m foam point. Preserve non-penetration in that
			# case; require monotonic clearance only while recovering a real collision.
			var collision_floor := (
				current_margin - 0.0001
				if current_margin < 0.0
				else -0.0001
			)
			var collision_not_worse := candidate_margin >= collision_floor
			var wrist_not_worse := (
				candidate_wrist_violation
				<= current_wrist_violation + 0.0001
			)
			var candidate_defect := (
				maxf(-candidate_margin, 0.0) + candidate_wrist_violation
			)
			if (
				collision_not_worse
				and wrist_not_worse
				and (
					candidate_defect < best_recovery_defect - 0.0001
					or (
						absf(candidate_defect - best_recovery_defect) <= 0.0001
						and pair_progress > best_recovery_progress
					)
				)
			):
				best_recovery_defect = candidate_defect
				best_recovery_progress = pair_progress
				best_recovery_pair = {
					"direction": candidate_direction,
					"distance": candidate_distance,
					"safe": false,
				}
	if not best_safe_pair.is_empty():
		return best_safe_pair
	if not best_recovery_pair.is_empty():
		return best_recovery_pair

	# The target chord can initially deepen a folded wrist even though a nearby
	# tangent step would go around the same capsule. Probe a deterministic local
	# neighbourhood only after that chord has no admissible recovery at all. Every
	# candidate remains inside the same elapsed-time visible-pose budget; this
	# is a bounded escape step, not a second global route planner.
	var current_boat := (
		rudder_pivot.basis * current_direction
	).normalized()
	var tangent_up_boat := (
		Vector3.UP - current_boat * current_boat.dot(Vector3.UP)
	)
	if tangent_up_boat.length_squared() <= 0.000001:
		tangent_up_boat = (
			Vector3.RIGHT - current_boat * current_boat.dot(Vector3.RIGHT)
		)
	tangent_up_boat = tangent_up_boat.normalized()
	var tangent_side_boat := current_boat.cross(tangent_up_boat).normalized()
	var escape_directions: Array[Vector3] = [current_direction]
	var local_tangents_boat: Array[Vector3] = [
		tangent_up_boat,
		-tangent_up_boat,
		tangent_side_boat,
		-tangent_side_boat,
	]
	var escape_angle := direction_step_budget
	for tangent_boat in local_tangents_boat:
		var candidate_boat := (
			current_boat * cos(escape_angle)
				+ tangent_boat * sin(escape_angle)
		).normalized()
		escape_directions.append((
			rudder_pivot.basis.inverse() * candidate_boat
		).normalized())

	# These are the same connected upper EXIT lanes used by the route tracker. A
	# capped slerp toward each lane supplies stable diagonal escape directions that
	# the two orthogonal tangent probes alone can miss near a capsule end cap.
	var route_side := signf(side)
	if is_zero_approx(route_side):
		route_side = signf(current_boat.x)
	if is_zero_approx(route_side):
		route_side = 1.0
	var escape_route_vectors_boat: Array[Vector3] = [
		Vector3(route_side * 0.10, 0.84, -0.53),
		Vector3(route_side * 0.22, 0.84, -0.50),
		Vector3(route_side * 0.34, 0.80, -0.49),
		Vector3(-route_side * 0.08, 0.86, -0.50),
		Vector3(route_side * 0.15, 0.92, -0.36),
		Vector3(route_side * 0.28, 0.88, -0.38),
	]
	for route_vector_boat in escape_route_vectors_boat:
		var route_direction := (
			rudder_pivot.basis.inverse() * route_vector_boat.normalized()
		).normalized()
		var route_angle := current_direction.angle_to(route_direction)
		if route_angle <= 0.000001:
			continue
		escape_directions.append(current_direction.slerp(
			route_direction,
			minf(1.0, escape_angle / route_angle)
		).normalized())

	var escape_distances: Array[float] = [
		current_distance,
		clampf(
			current_distance - distance_step_budget,
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE
		),
		clampf(
			current_distance + distance_step_budget,
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE
		),
	]
	var collision_floor := (
		current_margin - 0.0001
		if current_margin < 0.0
		else -0.0001
	)
	var current_defect := maxf(-current_margin, 0.0) + current_wrist_violation
	var best_escape_pair: Dictionary = {}
	var best_escape_is_safe := false
	var best_escape_defect := current_defect
	var best_escape_target_error := INF
	for candidate_direction in escape_directions:
		if (
			current_direction.angle_to(candidate_direction)
			> direction_step_budget + 0.00001
		):
			continue
		var candidate_boat := (
			rudder_pivot.basis * candidate_direction
		).normalized()
		if is_handover:
			var candidate_side := signf(candidate_boat.x)
			var preserves_normal := (
				not is_zero_approx(candidate_side)
					and _normal_extension_direction_preserves_side(
						candidate_boat,
						candidate_side
					)
			)
			if (
				not preserves_normal
					and not _handover_direction_preserves_route(
						candidate_boat,
						side,
						true
					)
			):
				continue
		elif not _normal_extension_direction_preserves_side(candidate_boat, side):
			continue
		if not _extension_direction_is_within_cone(
			candidate_direction,
			max_joint_angle
		):
			continue
		for candidate_distance in escape_distances:
			if (
				absf(candidate_distance - current_distance)
				> distance_step_budget + 0.00001
			):
				continue
			if (
				candidate_direction.is_equal_approx(current_direction)
				and is_equal_approx(candidate_distance, current_distance)
			):
				continue
			var candidate_margin := _tiller_extension_pair_clearance_margin(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules
			)
			var candidate_wrist_violation := (
				_tiller_extension_pair_wrist_violation(
					candidate_direction,
					candidate_distance,
					joint_boat,
					is_handover
				)
			)
			if candidate_margin < collision_floor:
				continue
			if (
				candidate_wrist_violation
				> current_wrist_violation + 0.0001
			):
				continue
			var candidate_defect := (
				maxf(-candidate_margin, 0.0) + candidate_wrist_violation
			)
			var candidate_is_safe := _tiller_extension_pair_is_safe(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules,
				is_handover,
				max_joint_angle,
				side
			)
			# Unlike target-chord progress, an off-target tangent step may not use
			# a flat defect plateau: that would permit lateral wandering or a +/-
			# oscillation. Even a safe candidate must make a measurable reduction in
			# the same combined hard-safety defect before it can be selected.
			if candidate_defect >= current_defect - 0.0001:
				continue
			var candidate_target_error := (
				candidate_direction.angle_to(target_direction_rudder)
					+ absf(candidate_distance - target_distance)
			)
			if (
				(candidate_is_safe and not best_escape_is_safe)
				or (
					candidate_is_safe == best_escape_is_safe
					and (
						candidate_defect < best_escape_defect - 0.0001
						or (
							absf(candidate_defect - best_escape_defect) <= 0.0001
							and candidate_target_error < best_escape_target_error
						)
					)
				)
			):
				best_escape_is_safe = candidate_is_safe
				best_escape_defect = candidate_defect
				best_escape_target_error = candidate_target_error
				best_escape_pair = {
					"direction": candidate_direction,
					"distance": candidate_distance,
					"safe": candidate_is_safe,
				}
	return best_escape_pair


func _tiller_extension_pair_wrist_violation(
	direction_rudder: Vector3,
	hand_distance: float,
	joint_boat: Vector3,
	is_handover: bool
) -> float:
	if not is_handover:
		return 0.0
	return maxf(
		float(_tiller_extension_candidate_wrist_guard(
			direction_rudder,
			hand_distance,
			joint_boat
		).get("violation_m", INF)),
		0.0
	)


func _advance_tiller_extension_pair(
	delta: float,
	target_direction_rudder: Vector3,
	target_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	side: float,
	is_handover: bool,
	max_joint_angle: float,
	immediate: bool
) -> bool:
	var direction_step_budget := _tiller_extension_direction_step_budget(delta)
	var distance_step_budget := _tiller_extension_distance_step_budget(delta)
	if (
		immediate
		or not _tiller_extension_initialized
		or not _tiller_extension_hand_distance_initialized
	):
		_tiller_extension_direction_rudder = target_direction_rudder
		_tiller_extension_hand_distance = target_distance
		_tiller_extension_last_safe_direction = target_direction_rudder
		_tiller_extension_last_safe_hand_distance = target_distance
		_tiller_extension_angular_velocity = Vector3.ZERO
		_tiller_extension_initialized = true
		_tiller_extension_hand_distance_initialized = true
		return true
	# A parent RudderPivot update changes both the rubber-joint frame and the joint
	# position before this deferred modifier solve. Rebasing preserves the shaft's
	# boat-space direction, but it cannot preserve clearance when the joint itself
	# has moved. Recover an invalid NORMAL pair as one bounded direction+distance
	# transaction. If one visible-pose budget cannot reach safety, retain only a
	# clearance-improving internal step and keep the published pose blocked; this
	# avoids both an unbounded snap and the former permanent deadlock.
	var current_pair_is_safe := _tiller_extension_pair_is_safe(
		_tiller_extension_direction_rudder,
		_tiller_extension_hand_distance,
		joint_boat,
		body_capsules,
		is_handover,
		max_joint_angle,
		side
	)
	if not is_handover and not current_pair_is_safe:
		var normal_recovery := _recover_unsafe_tiller_extension_pair(
			target_direction_rudder,
			target_distance,
			joint_boat,
			body_capsules,
			side,
			max_joint_angle,
			false,
			delta
		)
		if normal_recovery.is_empty():
			_tiller_extension_angular_velocity = Vector3.ZERO
			return false
		_tiller_extension_direction_rudder = normal_recovery["direction"]
		_tiller_extension_hand_distance = normal_recovery["distance"]
		_tiller_extension_angular_velocity = Vector3.ZERO
		if not bool(normal_recovery.get("safe", false)):
			return false
		_tiller_extension_last_safe_direction = (
			_tiller_extension_direction_rudder
		)
		_tiller_extension_last_safe_hand_distance = (
			_tiller_extension_hand_distance
		)
		return true
	# An idle-animation capsule can move a few millimetres across a handover pair
	# that was safe in the previous modifier generation. Carry direction and foam
	# contact together inside one visible-pose budget. If safety needs several
	# generations, publish only clearance-improving bounded states while the body
	# remains gated instead of retrying the same unsafe pair forever.
	if is_handover and not current_pair_is_safe:
		var handover_recovery := _recover_unsafe_tiller_extension_pair(
			target_direction_rudder,
			target_distance,
			joint_boat,
			body_capsules,
			side,
			max_joint_angle,
			true,
			delta
		)
		if handover_recovery.is_empty():
			_tiller_extension_angular_velocity = Vector3.ZERO
			return false
		_tiller_extension_direction_rudder = handover_recovery["direction"]
		_tiller_extension_hand_distance = handover_recovery["distance"]
		_tiller_extension_angular_velocity = Vector3.ZERO
		if not bool(handover_recovery.get("safe", false)):
			return false
		_tiller_extension_last_safe_direction = _tiller_extension_direction_rudder
		_tiller_extension_last_safe_hand_distance = _tiller_extension_hand_distance
		return true
	var couple_pair_progress := is_handover
	if not is_handover:
		# When the complete normal route is safe, direction and foam contact are one
		# path coordinate. Advancing both with the same normalized progress prevents
		# a fast angular spring from leaving its still-old contact distance behind.
		# Keep the existing distance-bridge fallback for a route that is not directly
		# connected, rather than forcing its diagonal through a capsule.
		couple_pair_progress = _normal_tiller_extension_pair_path_is_safe(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			target_direction_rudder,
			target_distance,
			joint_boat,
			body_capsules,
			side,
			max_joint_angle
		)
	var resolve_start_direction := _tiller_extension_direction_rudder
	var resolve_start_distance := _tiller_extension_hand_distance
	var remaining := clampf(delta, 0.0, 0.10)
	while remaining > 0.000001:
		var step := minf(remaining, TILLER_EXTENSION_MAX_SUBSTEP)
		var current_direction := _tiller_extension_direction_rudder
		var current_distance := _tiller_extension_hand_distance
		var raw_proposed_direction := _spring_tiller_extension_direction(
			target_direction_rudder,
			step,
			max_joint_angle
		)
		var raw_proposed_distance := move_toward(
			current_distance,
			target_distance,
			TILLER_EXTENSION_HAND_SLIDE_SPEED * step
		)
		var proposed_direction := raw_proposed_direction
		var proposed_distance := raw_proposed_distance
		if couple_pair_progress:
			# Direction and foam contact distance are one route coordinate on every
			# verified direct path. Advancing them at unrelated rates leaves the
			# collision-probed slerp/lerp path.
			var direction_error := current_direction.angle_to(target_direction_rudder)
			var distance_error := absf(target_distance - current_distance)
			var direction_fraction := 1.0
			if (
				direction_error
				> TILLER_EXTENSION_PAIR_DIRECTION_COUPLING_EPSILON
			):
				direction_fraction = clampf(
					current_direction.angle_to(raw_proposed_direction) / direction_error,
					0.0,
					1.0
				)
			var distance_fraction := 1.0
			if (
				distance_error
				> TILLER_EXTENSION_PAIR_DISTANCE_COUPLING_EPSILON
			):
				distance_fraction = clampf(
					absf(raw_proposed_distance - current_distance) / distance_error,
					0.0,
					1.0
				)
			var pair_fraction := minf(direction_fraction, distance_fraction)
			proposed_direction = current_direction.slerp(
				target_direction_rudder,
				pair_fraction
			).normalized()
			proposed_distance = lerpf(
				current_distance,
				target_distance,
				pair_fraction
			)
			if proposed_direction.angle_to(raw_proposed_direction) > 0.00001:
				_retain_clipped_tiller_extension_velocity(
					current_direction,
					proposed_direction,
					step
				)
		var resolve_direction_angle := resolve_start_direction.angle_to(
			proposed_direction
		)
		var resolve_distance_delta := absf(
			proposed_distance - resolve_start_distance
		)
		if couple_pair_progress:
			# Preserve the verified slerp/lerp route when the visible-pose budget is
			# reached. Clamping angle and grip distance independently would move the
			# pair off that route on a slow modifier generation.
			var resolve_pair_fraction := 1.0
			if resolve_direction_angle > 0.000001:
				resolve_pair_fraction = minf(
					resolve_pair_fraction,
					direction_step_budget
					/ resolve_direction_angle
				)
			if resolve_distance_delta > 0.000001:
				resolve_pair_fraction = minf(
					resolve_pair_fraction,
					distance_step_budget
					/ resolve_distance_delta
				)
			resolve_pair_fraction = clampf(resolve_pair_fraction, 0.0, 1.0)
			proposed_direction = resolve_start_direction.normalized().slerp(
				proposed_direction.normalized(),
				resolve_pair_fraction
			).normalized()
			proposed_distance = lerpf(
				resolve_start_distance,
				proposed_distance,
				resolve_pair_fraction
			)
		else:
			if (
				resolve_direction_angle
				> direction_step_budget
			):
				proposed_direction = resolve_start_direction.slerp(
					proposed_direction,
					direction_step_budget
					/ resolve_direction_angle
				).normalized()
			proposed_distance = clampf(
				proposed_distance,
				resolve_start_distance - distance_step_budget,
				resolve_start_distance + distance_step_budget
			)
		var accepted_pair := _furthest_safe_tiller_extension_pair_step(
			current_direction,
			current_distance,
			proposed_direction,
			proposed_distance,
			joint_boat,
			body_capsules,
			side,
			is_handover,
			max_joint_angle
		)
		if not accepted_pair.is_empty():
			var accepted_probe_direction: Vector3 = accepted_pair["direction"]
			var accepted_probe_distance: float = accepted_pair["distance"]
			var made_progress := (
				current_direction.angle_to(accepted_probe_direction) > 0.00001
				or absf(current_distance - accepted_probe_distance) > 0.0001
			)
			var still_has_work := (
				current_direction.angle_to(target_direction_rudder) > 0.0001
				or absf(current_distance - target_distance) > 0.0005
			)
			if not made_progress and still_has_work:
				# If rotation at the incumbent grip is blocked, first slide along the
				# same fixed shaft to a distance that is safe both here and at this
				# angular microstep. This resolves the direction<->distance ordering
				# deadlock without ever teleporting either state.
				var bridge_distance := _find_tiller_extension_pair_bridge_distance(
					current_direction,
					proposed_direction,
					current_distance,
					target_distance,
					joint_boat,
					body_capsules,
					side,
					is_handover,
					max_joint_angle
				)
				if bridge_distance >= 0.0:
					proposed_direction = current_direction
					proposed_distance = move_toward(
						current_distance,
						bridge_distance,
						TILLER_EXTENSION_HAND_SLIDE_SPEED * step
					)
					accepted_pair = _furthest_safe_tiller_extension_pair_step(
						current_direction,
						current_distance,
						proposed_direction,
						proposed_distance,
						joint_boat,
						body_capsules,
						side,
						is_handover,
						max_joint_angle
					)
			if not accepted_pair.is_empty():
				var post_bridge_direction: Vector3 = accepted_pair["direction"]
				var post_bridge_distance: float = accepted_pair["distance"]
				var post_bridge_made_progress := (
					current_direction.angle_to(post_bridge_direction) > 0.00001
					or absf(current_distance - post_bridge_distance) > 0.0001
				)
				if not post_bridge_made_progress and still_has_work:
					accepted_pair = {}
		if accepted_pair.is_empty():
			_tiller_extension_angular_velocity = Vector3.ZERO
			return false
		var accepted_direction: Vector3 = accepted_pair["direction"]
		var accepted_distance: float = accepted_pair["distance"]
		if accepted_direction.angle_to(proposed_direction) > 0.00001:
			_retain_clipped_tiller_extension_velocity(
				current_direction,
				accepted_direction,
				step
			)
		_tiller_extension_direction_rudder = accepted_direction
		_tiller_extension_hand_distance = accepted_distance
		if _tiller_extension_pair_is_safe(
			accepted_direction,
			accepted_distance,
			joint_boat,
			body_capsules,
			is_handover,
			max_joint_angle,
			side
		):
			_tiller_extension_last_safe_direction = accepted_direction
			_tiller_extension_last_safe_hand_distance = accepted_distance
		remaining -= step
	return true


func _tiller_extension_direction_step_budget(delta: float) -> float:
	return TILLER_EXTENSION_VISIBLE_DIRECTION_SPEED * clampf(delta, 0.0, 0.10)


func _tiller_extension_distance_step_budget(delta: float) -> float:
	return TILLER_EXTENSION_VISIBLE_DISTANCE_SPEED * clampf(delta, 0.0, 0.10)


func _record_tiller_extension_driven_pair(
	mode: TillerExtensionPairMode,
	target_direction_rudder: Vector3,
	target_distance: float
) -> void:
	_tiller_extension_driven_pair_mode = mode
	_tiller_extension_driven_target_direction_rudder = (
		target_direction_rudder.normalized()
	)
	_tiller_extension_driven_target_distance = target_distance


func tiller_extension_driven_pair() -> Dictionary:
	return {
		"mode": _tiller_extension_driven_pair_mode,
		"direction_rudder": _tiller_extension_driven_target_direction_rudder,
		"distance": _tiller_extension_driven_target_distance,
	}


func _rebase_tiller_extension_state_to_current_rudder_basis(
	current_joint_boat: Vector3
) -> void:
	# Physics moves the RudderPivot before the deferred sailor modifier resolves the
	# extension. Preserving only the shaft's boat-space direction lets the translated
	# joint drag the held grip laterally, after which the spring has to undo that move
	# on the next pose. Preserve each resolved grip contact instead: reconstruct its
	# direction and selectable foam distance from the new joint. Route goals remain
	# boat-direction states and therefore keep the original basis-only re-expression.
	var current_basis := rudder_pivot.basis.orthonormalized()
	if not _tiller_extension_rudder_basis_initialized:
		_tiller_extension_last_rudder_basis = current_basis
		_tiller_extension_last_joint_boat = current_joint_boat
		_tiller_extension_rudder_basis_initialized = true
		return
	if (
		current_basis == _tiller_extension_last_rudder_basis
		and current_joint_boat == _tiller_extension_last_joint_boat
	):
		return
	var previous_basis := _tiller_extension_last_rudder_basis
	var previous_to_current := (
		current_basis.inverse() * previous_basis
	).orthonormalized()
	var fallback_direction := (
		previous_to_current * _tiller_extension_direction_rudder
	).normalized()
	var fallback_last_safe_direction := (
		previous_to_current * _tiller_extension_last_safe_direction
	).normalized()
	var can_preserve_grip_contacts := (
		_tiller_extension_initialized
		and _tiller_extension_hand_distance_initialized
		and current_joint_boat.is_finite()
		and _tiller_extension_last_joint_boat.is_finite()
	)
	var current_contact_distance_clamped := false
	var current_contact_rebase_degenerate := false
	if can_preserve_grip_contacts:
		var previous_direction_boat := (
			previous_basis * _tiller_extension_direction_rudder
		).normalized()
		var previous_contact_boat := (
			_tiller_extension_last_joint_boat
			+ previous_direction_boat * _tiller_extension_hand_distance
		)
		var current_contact_vector := previous_contact_boat - current_joint_boat
		if (
			current_contact_vector.is_finite()
			and current_contact_vector.length_squared() > 0.000001
		):
			var raw_contact_distance := current_contact_vector.length()
			var clamped_contact_distance := clampf(
				raw_contact_distance,
				TILLER_EXTENSION_MIN_HAND_DISTANCE,
				TILLER_EXTENSION_MAX_HAND_DISTANCE
			)
			current_contact_distance_clamped = not is_equal_approx(
				raw_contact_distance,
				clamped_contact_distance
			)
			_tiller_extension_direction_rudder = (
				current_basis.inverse() * current_contact_vector.normalized()
			).normalized()
			_tiller_extension_hand_distance = clamped_contact_distance
		else:
			_tiller_extension_direction_rudder = fallback_direction
			current_contact_rebase_degenerate = true

		var previous_last_safe_boat := (
			previous_basis * _tiller_extension_last_safe_direction
		).normalized()
		var previous_last_safe_contact_boat := (
			_tiller_extension_last_joint_boat
			+ previous_last_safe_boat * _tiller_extension_last_safe_hand_distance
		)
		var current_last_safe_vector := (
			previous_last_safe_contact_boat - current_joint_boat
		)
		if (
			current_last_safe_vector.is_finite()
			and current_last_safe_vector.length_squared() > 0.000001
		):
			_tiller_extension_last_safe_direction = (
				current_basis.inverse() * current_last_safe_vector.normalized()
			).normalized()
			_tiller_extension_last_safe_hand_distance = clampf(
				current_last_safe_vector.length(),
				TILLER_EXTENSION_MIN_HAND_DISTANCE,
				TILLER_EXTENSION_MAX_HAND_DISTANCE
			)
		else:
			_tiller_extension_last_safe_direction = fallback_last_safe_direction
	else:
		# Before the physical pair exists (or for a degenerate joint/contact), retain
		# the previous direction-only behavior and leave both distances untouched.
		_tiller_extension_direction_rudder = fallback_direction
		_tiller_extension_last_safe_direction = fallback_last_safe_direction
	_tiller_extension_entry_bridge_direction_rudder = (
		previous_to_current * _tiller_extension_entry_bridge_direction_rudder
	).normalized()
	_tiller_extension_central_bridge_direction_rudder = (
		previous_to_current * _tiller_extension_central_bridge_direction_rudder
	).normalized()
	_tiller_extension_exit_target_direction_rudder = (
		previous_to_current * _tiller_extension_exit_target_direction_rudder
	).normalized()
	_tiller_extension_exit_bridge_direction_rudder = (
		previous_to_current * _tiller_extension_exit_bridge_direction_rudder
	).normalized()
	_tiller_extension_driven_target_direction_rudder = (
		previous_to_current * _tiller_extension_driven_target_direction_rudder
	).normalized()
	var rebased_angular_velocity := (
		previous_to_current * _tiller_extension_angular_velocity
	)
	var tangent_direction := _tiller_extension_direction_rudder.normalized()
	if (
		not rebased_angular_velocity.is_finite()
		or not tangent_direction.is_finite()
		or tangent_direction.length_squared() <= 0.000001
		or current_contact_rebase_degenerate
		or current_contact_distance_clamped
	):
		# A clamped grip no longer represents the exact previous contact. Carrying the
		# old spring impulse into that shortened/extended pair produces a residual kick.
		_tiller_extension_angular_velocity = Vector3.ZERO
	else:
		# Angular velocity is an axis tangent to the resolved direction sphere. Contact
		# preservation changes that direction independently of the parent-basis rotation,
		# so discard only the now-radial component and keep normal-range momentum.
		rebased_angular_velocity -= tangent_direction * rebased_angular_velocity.dot(
			tangent_direction
		)
		_tiller_extension_angular_velocity = (
			rebased_angular_velocity
			if rebased_angular_velocity.is_finite()
			else Vector3.ZERO
		)
	_tiller_extension_last_rudder_basis = current_basis
	_tiller_extension_last_joint_boat = current_joint_boat


func _find_tiller_extension_pair_bridge_distance(
	current_direction: Vector3,
	proposed_direction: Vector3,
	current_distance: float,
	target_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	side: float,
	is_handover: bool,
	max_joint_angle: float
) -> float:
	var best_distance := -1.0
	var best_score := INF
	for sample_index in range(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES):
		var ratio := (
			float(sample_index)
			/ float(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES - 1)
		)
		var candidate_distance := lerpf(
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE,
			ratio
		)
		if not _tiller_extension_pair_is_safe(
			current_direction,
			candidate_distance,
			joint_boat,
			body_capsules,
			is_handover,
			max_joint_angle,
			side
		):
			continue
		if not _tiller_extension_pair_is_safe(
			proposed_direction,
			candidate_distance,
			joint_boat,
			body_capsules,
			is_handover,
			max_joint_angle,
			side
		):
			continue
		var score := (
			absf(candidate_distance - current_distance)
			+ absf(candidate_distance - target_distance) * 0.25
		)
		if score < best_score:
			best_score = score
			best_distance = candidate_distance
	return best_distance


func _furthest_safe_tiller_extension_pair_step(
	current_direction: Vector3,
	current_distance: float,
	proposed_direction: Vector3,
	proposed_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	side: float,
	is_handover: bool,
	max_joint_angle: float
) -> Dictionary:
	if _tiller_extension_pair_is_safe(
		proposed_direction,
		proposed_distance,
		joint_boat,
		body_capsules,
		is_handover,
		max_joint_angle,
		side
	):
		return {
			"direction": proposed_direction,
			"distance": proposed_distance,
		}
	var current_is_safe := _tiller_extension_pair_is_safe(
		current_direction,
		current_distance,
		joint_boat,
		body_capsules,
		is_handover,
		max_joint_angle,
		side
	)
	if not current_is_safe:
		# A live capsule may invalidate yesterday's pair. Search only inside this
		# substep budget and accept the first verified state; never jump to a distant
		# sample on the foam or to another angular branch.
		for scan_index in range(1, 17):
			var amount := float(scan_index) / 16.0
			var candidate_direction := current_direction.slerp(
				proposed_direction,
				amount
			).normalized()
			var candidate_distance := lerpf(
				current_distance,
				proposed_distance,
				amount
			)
			if _tiller_extension_pair_is_safe(
				candidate_direction,
				candidate_distance,
				joint_boat,
				body_capsules,
				is_handover,
				max_joint_angle,
				side
			):
				return {
					"direction": candidate_direction,
					"distance": candidate_distance,
				}
		return {}
	var safe_amount := 0.0
	var unsafe_amount := 1.0
	for _iteration in range(10):
		var amount := (safe_amount + unsafe_amount) * 0.5
		var candidate_direction := current_direction.slerp(
			proposed_direction,
			amount
		).normalized()
		var candidate_distance := lerpf(
			current_distance,
			proposed_distance,
			amount
		)
		if _tiller_extension_pair_is_safe(
			candidate_direction,
			candidate_distance,
			joint_boat,
			body_capsules,
			is_handover,
			max_joint_angle,
			side
		):
			safe_amount = amount
		else:
			unsafe_amount = amount
	return {
		"direction": current_direction.slerp(
			proposed_direction,
			safe_amount
		).normalized(),
		"distance": lerpf(current_distance, proposed_distance, safe_amount),
	}


func _tiller_extension_pair_is_safe(
	direction_rudder: Vector3,
	hand_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	is_handover: bool,
	max_joint_angle: float,
	side: float
) -> bool:
	if not _extension_direction_is_within_cone(direction_rudder, max_joint_angle):
		return false
	var direction_boat := (
		rudder_pivot.basis * direction_rudder
	).normalized()
	if is_handover:
		var self_side := signf(direction_boat.x)
		var preserves_normal := (
			not is_zero_approx(self_side)
			and _normal_extension_direction_preserves_side(direction_boat, self_side)
		)
		if (
			not preserves_normal
			and not _handover_direction_preserves_route(direction_boat, side, true)
		):
			return false
	elif not _normal_extension_direction_preserves_side(direction_boat, side):
		return false
	var geometry_is_safe := (
		_extension_direction_is_safe(direction_rudder, joint_boat, body_capsules)
		and _tiller_extension_hand_contact_is_safe(
			joint_boat,
			direction_boat,
			body_capsules,
			hand_distance
		)
	)
	if not geometry_is_safe:
		return false
	if is_handover:
		return bool(_tiller_extension_candidate_wrist_guard(
			direction_rudder,
			hand_distance,
			joint_boat
		).get("safe", false))
	return true


func _tiller_extension_candidate_wrist_guard(
	direction_rudder: Vector3,
	hand_distance: float,
	joint_boat: Vector3,
	validate_arm: bool = false
) -> Dictionary:
	if not is_instance_valid(sailor):
		return {"safe": false, "violation_m": INF}
	var direction_boat := (
		rudder_pivot.basis * direction_rudder
	).normalized()
	var contact_boat := joint_boat + direction_boat * hand_distance
	return sailor.preview_tiller_extension_pair_wrist_guard(
		contact_boat,
		direction_boat,
		validate_arm
	)


func _tiller_extension_wrist_guard_has_exit_body_reserve(
	wrist_guard: Dictionary
) -> bool:
	return (
		bool(wrist_guard.get("safe", false))
		and float(wrist_guard.get("reserve_m", -INF))
		>= TILLER_EXTENSION_EXIT_WRIST_BODY_RESERVE
	)


func _tiller_extension_wrist_guard_has_exit_target_reserve(
	wrist_guard: Dictionary
) -> bool:
	return (
		bool(wrist_guard.get("safe", false))
		and float(wrist_guard.get("reserve_m", -INF))
		>= TILLER_EXTENSION_EXIT_WRIST_TARGET_RESERVE
	)


func _tiller_extension_pair_clearance_margin(
	direction_rudder: Vector3,
	hand_distance: float,
	joint_boat: Vector3,
	body_capsules: Array
) -> float:
	var direction_boat := (
		rudder_pivot.basis * direction_rudder
	).normalized()
	var shaft_far := joint_boat + direction_boat * TILLER_EXTENSION_SHAFT_LENGTH
	var contact := joint_boat + direction_boat * hand_distance
	var minimum_margin := INF
	for capsule_variant in body_capsules:
		var capsule: Dictionary = capsule_variant
		var capsule_from: Vector3 = capsule["from"]
		var capsule_to: Vector3 = capsule["to"]
		var body_clearance := float(capsule["clearance"])
		minimum_margin = minf(
			minimum_margin,
			_segment_segment_distance(
				joint_boat,
				shaft_far,
				capsule_from,
				capsule_to
			) - body_clearance - TILLER_EXTENSION_SHAFT_CLEARANCE
		)
		minimum_margin = minf(
			minimum_margin,
			_segment_segment_distance(
				contact,
				contact,
				capsule_from,
				capsule_to
			) - body_clearance - TILLER_EXTENSION_HAND_CONTACT_CLEARANCE
		)
	return minimum_margin


func _tiller_extension_exit_pair_meets_readiness_prerequisites(
	direction_rudder: Vector3,
	hand_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	new_side: float,
	require_normal: bool = true
) -> bool:
	var direction_boat := (
		rudder_pivot.basis * direction_rudder
	).normalized()
	var shoulder_boat := _find_tiller_shoulder_for_side_boat(
		body_capsules,
		new_side
	)
	if not shoulder_boat.is_finite():
		return false
	var contact := joint_boat + direction_boat * hand_distance
	var shoulder_reach := shoulder_boat.distance_to(contact)
	var pair_max_angle := (
		TILLER_EXTENSION_HARD_JOINT_ANGLE
		if require_normal
		else TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
	)
	var route_is_ready := true
	if require_normal:
		route_is_ready = _normal_extension_direction_preserves_side(
			direction_boat,
			new_side
		)
	var wrist_guard := _tiller_extension_candidate_wrist_guard(
		direction_rudder,
		hand_distance,
		joint_boat
	)
	return (
		_extension_direction_is_within_cone(
			direction_rudder,
			pair_max_angle
		)
		and route_is_ready
		and shoulder_reach >= TILLER_EXTENSION_EXIT_REACH_MIN
		and shoulder_reach <= TILLER_EXTENSION_EXIT_REACH_MAX
		and _tiller_extension_wrist_guard_has_exit_body_reserve(wrist_guard)
		and _tiller_extension_pair_clearance_margin(
			direction_rudder,
			hand_distance,
			joint_boat,
			body_capsules
		) >= TILLER_EXTENSION_EXIT_GUARD_CLEARANCE
		and _tiller_extension_pair_is_safe(
			direction_rudder,
			hand_distance,
			joint_boat,
			body_capsules,
			not require_normal,
			pair_max_angle,
			new_side
		)
	)


func _tiller_extension_exit_pair_is_ready(
	joint_boat: Vector3,
	body_capsules: Array,
	new_side: float,
	target_direction: Vector3,
	target_distance: float,
	require_normal: bool = true
) -> bool:
	return (
		_tiller_extension_direction_rudder.angle_to(target_direction)
		<= TILLER_EXTENSION_EXIT_DIRECTION_TOLERANCE
		and absf(_tiller_extension_hand_distance - target_distance)
		<= TILLER_EXTENSION_EXIT_DISTANCE_TOLERANCE
		and _tiller_extension_exit_pair_meets_readiness_prerequisites(
			_tiller_extension_direction_rudder,
			_tiller_extension_hand_distance,
			joint_boat,
			body_capsules,
			new_side,
			require_normal
		)
	)


func _publish_tiller_extension_pose() -> void:
	var desired_extension_basis := Basis.looking_at(
		_tiller_extension_direction_rudder.normalized(),
		Vector3.UP
	)
	tiller_extension_pivot.quaternion = (
		desired_extension_basis.get_rotation_quaternion()
	)
	var tiller_grip := tiller_extension_pivot.get_node("TillerGrip") as Node3D
	tiller_grip.position = Vector3(0.0, 0.0, -_tiller_extension_hand_distance)
	var visible_extension := (
		tiller_extension_pivot.get_node("TillerJoint") as IlcaHardwarePart
	)
	visible_extension.set_tiller_extension_grip_distance(
		_tiller_extension_hand_distance
	)


func _find_safe_tiller_extension_hand_distance(
	joint_boat: Vector3,
	direction_boat: Vector3,
	body_capsules: Array,
	desired_distance: float,
	tiller_shoulder_boat: Vector3 = Vector3.INF
) -> float:
	var clamped_desired := clampf(
		desired_distance,
		TILLER_EXTENSION_MIN_HAND_DISTANCE,
		TILLER_EXTENSION_MAX_HAND_DISTANCE
	)
	var best_distance := -1.0
	var best_score := INF
	var incumbent_is_safe := false
	var incumbent_score := INF
	var candidates: Array[float] = [clamped_desired]
	if _tiller_extension_hand_distance_initialized:
		candidates.append(_tiller_extension_hand_distance)
		candidates.append(_tiller_extension_last_safe_hand_distance)
	for sample_index in range(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES):
		var ratio := (
			float(sample_index)
			/ float(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES - 1)
		)
		candidates.append(lerpf(
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE,
			ratio
		))
	for candidate_distance in candidates:
		if not _tiller_extension_hand_contact_is_safe(
			joint_boat,
			direction_boat,
			body_capsules,
			candidate_distance
		):
			continue
		if tiller_shoulder_boat.is_finite():
			var candidate_contact := (
				joint_boat + direction_boat.normalized() * candidate_distance
			)
			var candidate_reach := tiller_shoulder_boat.distance_to(
				candidate_contact
			)
			if (
				candidate_reach < TILLER_EXTENSION_EXIT_REACH_MIN
				or candidate_reach > TILLER_EXTENSION_EXIT_REACH_MAX
			):
				continue
		var candidate_score := _tiller_extension_hand_distance_score(
			joint_boat,
			direction_boat,
			candidate_distance,
			clamped_desired,
			tiller_shoulder_boat
		)
		if candidate_score < best_score:
			best_score = candidate_score
			best_distance = candidate_distance
		if (
			_tiller_extension_hand_distance_initialized
			and is_equal_approx(
				candidate_distance,
				_tiller_extension_hand_distance
			)
		):
			incumbent_is_safe = true
			incumbent_score = candidate_score
	# A five-millimetre collision-search sample must not beat a still-safe
	# incumbent merely because the desired point lies four millimetres away.
	# This Schmitt margin makes 0.600 <-> 0.605 a stable choice while still
	# allowing intentional, larger hand slides.
	if (
		incumbent_is_safe
		and incumbent_score <= (
			best_score + TILLER_EXTENSION_HAND_SCORE_HYSTERESIS
		)
	):
		return _tiller_extension_hand_distance
	return best_distance


func _find_tiller_shoulder_boat(
	body_capsules: Array,
	direction_boat: Vector3
) -> Vector3:
	# Outside handover, the extension remains in the same-side working
	# hemisphere as its anatomical hand: positive boat X uses LeftUpperArm and
	# negative boat X uses RightUpperArm in this rig's mirrored seated pose.
	var shoulder_label: StringName = (
		&"left_shoulder" if direction_boat.x >= 0.0 else &"right_shoulder"
	)
	for capsule_variant in body_capsules:
		var capsule: Dictionary = capsule_variant
		if StringName(capsule.get("label", &"")) != shoulder_label:
			continue
		var shoulder_from: Vector3 = capsule.get("from", Vector3.INF)
		var shoulder_to: Vector3 = capsule.get("to", shoulder_from)
		return (shoulder_from + shoulder_to) * 0.5
	return Vector3.INF


func _tiller_extension_hand_distance_score(
	joint_boat: Vector3,
	direction_boat: Vector3,
	candidate_distance: float,
	authored_distance: float,
	tiller_shoulder_boat: Vector3,
	working_target_boat: Vector3 = Vector3.INF
) -> float:
	var continuity_error := 0.0
	if _tiller_extension_hand_distance_initialized:
		continuity_error = absf(
			candidate_distance - _tiller_extension_hand_distance
		)
	var score := (
		continuity_error * TILLER_EXTENSION_DISTANCE_CONTINUITY_WEIGHT
		+ absf(candidate_distance - authored_distance)
		* TILLER_EXTENSION_AUTHORED_DISTANCE_WEIGHT
	)
	var contact := (
		joint_boat + direction_boat.normalized() * candidate_distance
	)
	var contact_side := signf(direction_boat.x)
	if is_zero_approx(contact_side):
		contact_side = signf(contact.x)
	if is_zero_approx(contact_side):
		contact_side = 1.0
	var working_contact := Vector3(
		contact_side * TILLER_EXTENSION_WORKING_CONTACT_LATERAL,
		TILLER_EXTENSION_WORKING_CONTACT_HEIGHT,
		TILLER_EXTENSION_WORKING_CONTACT_AFT
	)
	if working_target_boat.is_finite():
		working_contact = working_target_boat
	score += contact.distance_to(working_contact) * (
		TILLER_EXTENSION_WORKING_CONTACT_WEIGHT
	)
	if tiller_shoulder_boat.is_finite():
		var shoulder_reach := tiller_shoulder_boat.distance_to(contact)
		var band_error := maxf(
			maxf(
				TILLER_EXTENSION_COMFORT_REACH_MIN - shoulder_reach,
				shoulder_reach - TILLER_EXTENSION_COMFORT_REACH_MAX
			),
			0.0
		)
		score += (
			band_error * TILLER_EXTENSION_COMFORT_BAND_WEIGHT
			+ absf(
				shoulder_reach - TILLER_EXTENSION_COMFORT_REACH_TARGET
			) * TILLER_EXTENSION_COMFORT_TARGET_WEIGHT
		)
	return score


func _normal_tiller_working_contact_boat(side: float) -> Vector3:
	# Follow the already-smoothed physical rudder. Deriving the shaft direction
	# from this same moving contact avoids cancelling the joint's translation
	# with an independently authored direction while the hand stays nearly still.
	var rudder_input := clampf(
		rudder_pivot.rotation.y / maxf(MAX_RUDDER_VISUAL_ANGLE, 0.0001), -1.0, 1.0
	)
	return _normal_tiller_working_contact_for_input(side, rudder_input)


func _normal_tiller_working_contact_for_input(side: float, rudder_input: float) -> Vector3:
	# Lift leads the inward pull so the full shaft clears the opposite shoulder
	# before the contact approaches the torso. Both arcs end with zero slope.
	rudder_input = clampf(rudder_input, -1.0, 1.0)
	var away_amount := signf(side) * rudder_input
	var pull_amount := maxf(away_amount, 0.0)
	var pull_arc := smoothstep(0.0, 1.0, pull_amount)
	var pull_lift := sin(pull_amount * PI * 0.5) * smoothstep(
		0.0, TILLER_EXTENSION_STEERING_PULL_LIFT_ENTRY, pull_amount
	)
	return Vector3(
		signf(side) * (TILLER_EXTENSION_WORKING_CONTACT_LATERAL
			+ away_amount * TILLER_EXTENSION_STEERING_CONTACT_STROKE),
		TILLER_EXTENSION_WORKING_CONTACT_HEIGHT
			+ TILLER_EXTENSION_STEERING_NEUTRAL_LIFT_RESERVE * (1.0 - pull_lift)
			+ pull_lift * TILLER_EXTENSION_STEERING_PULL_LIFT,
		# Pull around the chest-front lane: moving only toward the torso in X
		# leaves the extra shaft beyond the palm aimed through the upper body.
		TILLER_EXTENSION_WORKING_CONTACT_AFT - pull_arc * TILLER_EXTENSION_STEERING_PULL_FORWARD_ARC
	)


func _retain_clipped_tiller_extension_velocity(
	from_direction: Vector3,
	to_direction: Vector3,
	delta: float
) -> void:
	var accepted_angle := from_direction.angle_to(to_direction)
	var accepted_axis := from_direction.cross(to_direction)
	if accepted_angle <= 0.000001 or accepted_axis.length_squared() <= 0.000001:
		_tiller_extension_angular_velocity = Vector3.ZERO
		return
	var accepted_speed := minf(
		accepted_angle / maxf(delta, 0.000001),
		TILLER_EXTENSION_MAX_ANGULAR_SPEED
	)
	_tiller_extension_angular_velocity = (
		accepted_axis.normalized()
		* accepted_speed
		* TILLER_EXTENSION_CLIPPED_VELOCITY_RETENTION
	)


func _tiller_extension_hand_contact_is_safe(
	joint_boat: Vector3,
	direction_boat: Vector3,
	body_capsules: Array,
	hand_distance: float
) -> bool:
	if (
		hand_distance < TILLER_EXTENSION_MIN_HAND_DISTANCE - 0.00001
		or hand_distance > TILLER_EXTENSION_MAX_HAND_DISTANCE + 0.00001
	):
		return false
	var contact := joint_boat + direction_boat.normalized() * hand_distance
	for capsule in body_capsules:
		var clearance := (
			float(capsule["clearance"])
			+ TILLER_EXTENSION_HAND_CONTACT_CLEARANCE
		)
		if _segment_segment_distance(
			contact,
			contact,
			capsule["from"],
			capsule["to"]
		) < clearance:
			return false
	return true


func _spring_tiller_extension_direction(
	target: Vector3,
	delta: float,
	max_joint_angle: float
) -> Vector3:
	var current := _tiller_extension_direction_rudder.normalized()
	var angle := current.angle_to(target)
	if angle <= 0.000001:
		_tiller_extension_angular_velocity *= exp(
			-TILLER_EXTENSION_SPRING_DAMPING * delta
		)
		return current
	var axis := current.cross(target)
	if axis.length_squared() <= 0.000001:
		axis = Vector3.UP
	else:
		axis = axis.normalized()
	var error := axis * angle
	_tiller_extension_angular_velocity += (
		error * TILLER_EXTENSION_SPRING_STIFFNESS
		- _tiller_extension_angular_velocity * TILLER_EXTENSION_SPRING_DAMPING
	) * delta
	if _tiller_extension_angular_velocity.length() > TILLER_EXTENSION_MAX_ANGULAR_SPEED:
		_tiller_extension_angular_velocity = (
			_tiller_extension_angular_velocity.normalized()
			* TILLER_EXTENSION_MAX_ANGULAR_SPEED
		)
	var step_vector := _tiller_extension_angular_velocity * delta
	var step_angle := minf(step_vector.length(), angle)
	if step_angle <= 0.000001:
		return current
	return _clamp_tiller_extension_cone(
		Quaternion(step_vector.normalized(), step_angle) * current,
		max_joint_angle
	).normalized()


func _furthest_safe_tiller_extension_step(
	current_rudder: Vector3,
	proposed_rudder: Vector3,
	recovery_target_rudder: Vector3,
	joint_boat: Vector3,
	body_capsules: Array,
	is_handover: bool,
	max_joint_angle: float,
	desired_side: float,
	max_recovery_angle: float
) -> Vector3:
	# A spring substep is a local motion, not a request to re-run the authored
	# endpoint selector. Re-solving an unsafe intermediate to the final endpoint
	# made the rubber joint teleport by roughly 50 degrees in one frame. Binary
	# search the actual spherical segment and retain only its safe prefix.
	var current := _clamp_tiller_extension_cone(current_rudder, max_joint_angle)
	var proposed := _clamp_tiller_extension_cone(proposed_rudder, max_joint_angle)
	var side := desired_side
	if is_zero_approx(side):
		side = signf(sailor.seat_side)
	if is_zero_approx(side):
		side = 1.0
	if _tiller_extension_step_is_safe(
		proposed,
		joint_boat,
		body_capsules,
		is_handover,
		max_joint_angle,
		side
	):
		return proposed
	var current_is_safe := _tiller_extension_step_is_safe(
		current,
		joint_boat,
		body_capsules,
		is_handover,
		max_joint_angle,
		side
	)
	if not current_is_safe:
		# A moving body capsule can make the previously rendered direction marginally
		# unsafe. Search only inside this substep's angular budget; the former scan
		# searched all the way to the first distant safe point and teleported the
		# 1.10 m shaft by 25-31 degrees in one frame.
		var recovery_target := _clamp_tiller_extension_cone(
			recovery_target_rudder,
			max_joint_angle
		)
		var recovery_angle := current.angle_to(recovery_target)
		if recovery_angle <= 0.000001 or max_recovery_angle <= 0.000001:
			return Vector3.ZERO
		var capped_target := current.slerp(
			recovery_target,
			minf(1.0, max_recovery_angle / recovery_angle)
		).normalized()
		var unsafe_amount := 0.0
		var safe_amount := -1.0
		for scan_index in range(1, 17):
			var amount := float(scan_index) / 16.0
			var candidate := current.slerp(capped_target, amount).normalized()
			if _tiller_extension_step_is_safe(
				candidate,
				joint_boat,
				body_capsules,
				is_handover,
				max_joint_angle,
				side
			):
				safe_amount = amount
				break
			unsafe_amount = amount
		if safe_amount < 0.0:
			return Vector3.ZERO
		for _iteration in range(8):
			var middle_amount := (unsafe_amount + safe_amount) * 0.5
			var middle := current.slerp(capped_target, middle_amount).normalized()
			if _tiller_extension_step_is_safe(
				middle,
				joint_boat,
				body_capsules,
				is_handover,
				max_joint_angle,
				side
			):
				safe_amount = middle_amount
			else:
				unsafe_amount = middle_amount
		return current.slerp(capped_target, safe_amount).normalized()
	var safe_amount := 0.0
	var unsafe_amount := 1.0
	var safe_direction := current
	for _iteration in range(8):
		var amount := (safe_amount + unsafe_amount) * 0.5
		var candidate := current.slerp(proposed, amount).normalized()
		if _tiller_extension_step_is_safe(
			candidate,
			joint_boat,
			body_capsules,
			is_handover,
			max_joint_angle,
			side
		):
			safe_amount = amount
			safe_direction = candidate
		else:
			unsafe_amount = amount
	return safe_direction


func _tiller_extension_step_is_safe(
	direction_rudder: Vector3,
	joint_boat: Vector3,
	body_capsules: Array,
	is_handover: bool,
	max_joint_angle: float,
	side: float
) -> bool:
	if not _extension_direction_is_within_cone(direction_rudder, max_joint_angle):
		return false
	var direction_boat := (
		rudder_pivot.basis * direction_rudder
	).normalized()
	if is_handover:
		# Entry and exit overlap the normal front/chest corridor. The old disjoint
		# switch invalidated a still-safe current direction as soon as handover began
		# and recovery jumped directly to the first aft-route point.
		var self_side := signf(direction_boat.x)
		var preserves_normal := (
			not is_zero_approx(self_side)
			and _normal_extension_direction_preserves_side(direction_boat, self_side)
		)
		if (
			not preserves_normal
			and not _handover_direction_preserves_route(direction_boat, side, true)
		):
			return false
	elif not _normal_extension_direction_preserves_side(direction_boat, side):
		return false
	if not _extension_direction_is_safe(
		direction_rudder,
		joint_boat,
		body_capsules
	):
		return false
	if (
		_tiller_extension_hand_distance_initialized
		and not _tiller_extension_hand_contact_is_safe(
			joint_boat,
			direction_boat,
			body_capsules,
			_tiller_extension_hand_distance
		)
	):
		return false
	return true


func _clamp_tiller_extension_cone(
	direction: Vector3,
	max_joint_angle: float
) -> Vector3:
	var normalized := direction.normalized()
	var angle := Vector3.FORWARD.angle_to(normalized)
	if angle <= max_joint_angle:
		return normalized
	var axis := Vector3.FORWARD.cross(normalized)
	if axis.length_squared() <= 0.000001:
		axis = Vector3.UP
	return (
		Quaternion(axis.normalized(), max_joint_angle)
		* Vector3.FORWARD
	).normalized()


func _extension_direction_is_within_cone(
	direction: Vector3,
	max_joint_angle: float
) -> bool:
	if direction.length_squared() <= 0.000001:
		return false
	return (
		Vector3.FORWARD.angle_to(direction.normalized())
		<= max_joint_angle + 0.00001
	)


func _soften_tiller_extension_target(
	direction: Vector3,
	max_joint_angle: float
) -> Vector3:
	var normalized := _clamp_tiller_extension_cone(direction, max_joint_angle)
	var angle := Vector3.FORWARD.angle_to(normalized)
	if angle <= TILLER_EXTENSION_SOFT_JOINT_ANGLE:
		return normalized
	var soft_span := maxf(
		max_joint_angle - TILLER_EXTENSION_SOFT_JOINT_ANGLE,
		0.0001
	)
	var load := clampf(
		(angle - TILLER_EXTENSION_SOFT_JOINT_ANGLE) / soft_span,
		0.0,
		1.0
	)
	# Increasing rubber resistance near the hard stop gently biases the unloaded
	# extension back toward the soft cone without removing full articulation.
	var resisted_angle := lerpf(
		angle,
		TILLER_EXTENSION_SOFT_JOINT_ANGLE,
		0.35 * load * load
	)
	var axis := Vector3.FORWARD.cross(normalized)
	if axis.length_squared() <= 0.000001:
		return normalized
	return (
		Quaternion(axis.normalized(), resisted_angle) * Vector3.FORWARD
	).normalized()


func _find_safe_tiller_extension_direction(
	desired_rudder: Vector3,
	joint_boat: Vector3,
	body_capsules: Array,
	is_handover: bool,
	max_joint_angle: float
) -> Vector3:
	var desired_boat := (rudder_pivot.basis * desired_rudder).normalized()
	var side := signf(desired_boat.x)
	if is_zero_approx(side):
		side = signf(sailor.seat_side)
	if is_zero_approx(side):
		side = 1.0
	if is_handover:
		return _find_safe_handover_tiller_extension_direction(
			desired_boat,
			desired_rudder,
			side,
			joint_boat,
			body_capsules,
			max_joint_angle
		)
	# Normal contact selection and direction recovery share one steering stroke.
	# The unchanged guards below certify its contact, shaft and joint corridor.
	var authored_boat := (_normal_tiller_working_contact_boat(side) - joint_boat).normalized()
	var authored_rudder := (
		rudder_pivot.basis.inverse() * authored_boat
	).normalized()
	# A compact local lattice tolerates small animation/capsule drift. Every
	# candidate remains in the same forward component; there is deliberately no
	# opposite-side or aft emergency direction. Keep the previously selected
	# branch while it remains safe unless another branch improves alignment by a
	# meaningful Schmitt margin. This prevents the authored and first offset
	# branches alternating at a live capsule boundary under held input.
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-side * 0.015, -0.015, -0.010),
		Vector3(side * 0.015, -0.015, -0.010),
		Vector3(-side * 0.030, -0.030, -0.020),
		Vector3(side * 0.030, -0.030, -0.020),
		Vector3(0.0, -0.045, -0.030),
	]
	var best_candidate := Vector3.ZERO
	var best_error: float = INF
	var best_index := -1
	var incumbent_candidate := Vector3.ZERO
	var incumbent_error: float = INF
	for candidate_index in range(offsets.size()):
		var offset := offsets[candidate_index]
		var candidate_rudder := authored_rudder
		if candidate_index > 0:
			var candidate_boat := (
				authored_boat * TILLER_EXTENSION_SHAFT_LENGTH + offset
			).normalized()
			var raw_candidate := (
				rudder_pivot.basis.inverse() * candidate_boat
			).normalized()
			candidate_rudder = _soften_tiller_extension_target(
				raw_candidate,
				max_joint_angle
			)
		var resolved_boat := (rudder_pivot.basis * candidate_rudder).normalized()
		if not _normal_extension_direction_preserves_side(resolved_boat, side):
			continue
		if not _extension_direction_is_within_cone(candidate_rudder, max_joint_angle):
			continue
		if not _extension_direction_is_safe(
			candidate_rudder,
			joint_boat,
			body_capsules
		):
			continue
		var candidate_error := resolved_boat.angle_to(authored_boat)
		if candidate_error < best_error:
			best_error = candidate_error
			best_candidate = candidate_rudder
			best_index = candidate_index
		if (
			_tiller_extension_normal_target_initialized
			and candidate_index == _tiller_extension_normal_target_index
		):
			incumbent_candidate = candidate_rudder
			incumbent_error = candidate_error
	if best_candidate.is_zero_approx():
		return Vector3.ZERO
	if (
		not incumbent_candidate.is_zero_approx()
		and incumbent_error <= (
			best_error + TILLER_EXTENSION_TARGET_SWITCH_MARGIN
		)
	):
		return incumbent_candidate
	_tiller_extension_normal_target_index = best_index
	_tiller_extension_normal_target_initialized = true
	return best_candidate


func _find_safe_handover_tiller_extension_pair(
	desired_rudder: Vector3,
	requested_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	route_side: float,
	minimum_distance: float = TILLER_EXTENSION_MIN_HAND_DISTANCE,
	minimum_clearance: float = 0.0
) -> Dictionary:
	var started_us := Time.get_ticks_usec()
	var result := _find_safe_handover_tiller_extension_pair_impl(
		desired_rudder, requested_distance, joint_boat, body_capsules,
		route_side, minimum_distance, minimum_clearance
	)
	maneuver_profile["search_us"] = int(maneuver_profile["search_us"]) + Time.get_ticks_usec() - started_us
	maneuver_profile["search_calls"] = int(maneuver_profile["search_calls"]) + 1
	return result


func _find_safe_handover_tiller_extension_pair_impl(
	desired_rudder: Vector3,
	requested_distance: float,
	joint_boat: Vector3,
	body_capsules: Array,
	route_side: float,
	minimum_distance: float = TILLER_EXTENSION_MIN_HAND_DISTANCE,
	minimum_clearance: float = 0.0
) -> Dictionary:
	# Direction and foam contact are one ergonomic state. Choosing a shaft ray
	# first and freezing the distance through the centre of a tack left one hand
	# at 11 cm of wrist reach and the other beyond the 52.8 cm arm length even
	# though a neighbouring contact on the same foam was available.
	var side := signf(route_side)
	var desired_boat := (rudder_pivot.basis * desired_rudder).normalized()
	if is_zero_approx(side):
		side = signf(desired_boat.x)
	if is_zero_approx(side):
		side = signf(sailor.seat_side)
	if is_zero_approx(side):
		side = 1.0
	var directions: Array[Vector3] = []
	var authored_offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(side * 0.02, 0.04, 0.04),
		Vector3(-side * 0.02, 0.06, 0.06),
		Vector3(side * 0.04, 0.08, 0.08),
		Vector3(-side * 0.04, 0.10, 0.12),
	]
	for offset in authored_offsets:
		var candidate_boat := (
			desired_boat * TILLER_EXTENSION_SHAFT_LENGTH + offset
		).normalized()
		directions.append(_clamp_tiller_extension_cone(
			(rudder_pivot.basis.inverse() * candidate_boat).normalized(),
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
		))
	var upper_route_vectors: Array[Vector3] = [
		Vector3(side * 0.22, 0.60, -0.54),
		Vector3(side * 0.14, 0.64, -0.56),
		Vector3(side * 0.06, 0.68, -0.58),
		Vector3(0.0, 0.70, -0.60),
		Vector3(-side * 0.06, 0.68, -0.58),
		Vector3(-side * 0.14, 0.64, -0.56),
		Vector3(-side * 0.22, 0.60, -0.54),
	]
	for route_vector_boat in upper_route_vectors:
		directions.append(_clamp_tiller_extension_cone(
			(
				rudder_pivot.basis.inverse()
				* route_vector_boat.normalized()
			).normalized(),
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE
		))
	var distances: Array[float] = [
		clampf(
			requested_distance,
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE
		),
		_tiller_extension_hand_distance,
		_tiller_extension_last_safe_hand_distance,
	]
	for sample_index in range(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES):
		var ratio := (
			float(sample_index)
			/ float(TILLER_EXTENSION_HAND_DISTANCE_SAMPLES - 1)
		)
		distances.append(lerpf(
			TILLER_EXTENSION_MIN_HAND_DISTANCE,
			TILLER_EXTENSION_MAX_HAND_DISTANCE,
			ratio
		))
	var candidates: Array[Dictionary] = []
	var minimum_candidate_distance := clampf(
		minimum_distance,
		TILLER_EXTENSION_MIN_HAND_DISTANCE,
		TILLER_EXTENSION_MAX_HAND_DISTANCE
	)
	for candidate_direction in directions:
		if candidate_direction.length_squared() <= 0.000001:
			continue
		var candidate_boat := (
			rudder_pivot.basis * candidate_direction
		).normalized()
		if not _handover_direction_preserves_route(candidate_boat, side, true):
			continue
		if not _extension_direction_is_safe(
			candidate_direction,
			joint_boat,
			body_capsules
		):
			continue
		for candidate_distance in distances:
			if candidate_distance < minimum_candidate_distance - 0.00001:
				continue
			var score := (
				candidate_direction.angle_to(desired_rudder) * 2.0
				+ candidate_direction.angle_to(
					_tiller_extension_direction_rudder
				) * 0.12
				+ absf(candidate_distance - requested_distance) * 0.04
				+ absf(
					candidate_distance - _tiller_extension_hand_distance
				) * 0.08
			)
			if not score < INF:
				continue
			candidates.append({
				"direction": candidate_direction,
				"distance": candidate_distance,
				"score": score,
				"order": candidates.size(),
			})
	# Direction-only rejection above remains unchanged. Score ordering avoids
	# repeating contact, wrist and clearance checks for every worse grip sample.
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if float(first["score"]) == float(second["score"]):
			return int(first["order"]) < int(second["order"])
		return float(first["score"]) < float(second["score"])
	)
	for candidate in candidates:
		var candidate_direction: Vector3 = candidate["direction"]
		var candidate_distance := float(candidate["distance"])
		if not _tiller_extension_pair_is_safe(
			candidate_direction,
			candidate_distance,
			joint_boat,
			body_capsules,
			true,
			TILLER_EXTENSION_HANDOVER_HARD_JOINT_ANGLE,
			side
		):
			continue
		if _tiller_extension_pair_clearance_margin(
			candidate_direction,
			candidate_distance,
			joint_boat,
			body_capsules
		) < minimum_clearance:
			continue
		return {"direction": candidate_direction, "distance": candidate_distance}
	return {}


func _normal_extension_direction_preserves_side(
	direction_boat: Vector3,
	side: float
) -> bool:
	# Ordinary steering may perturb only inside the measured front/chest corridor.
	# In particular, z >= 0 is the disconnected behind-the-sailor component used
	# only by the dedicated handover solver below.
	return (
		direction_boat.x * side >= 0.05
		and direction_boat.y >= 0.32
		and direction_boat.z <= -0.30
	)


func _find_safe_handover_tiller_extension_direction(
	desired_boat: Vector3,
	desired_rudder: Vector3,
	side: float,
	joint_boat: Vector3,
	body_capsules: Array,
	max_joint_angle: float
) -> Vector3:
	# Preserve the authored behind-the-sailor hand path in boat space. With the
	# shorter tiller, that same body-space path lies slightly forward of the joint;
	# route validity therefore cannot use the old joint-relative +Z shortcut.
	var authored_offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(side * 0.02, 0.04, 0.04),
		Vector3(-side * 0.02, 0.06, 0.06),
		Vector3(side * 0.04, 0.08, 0.08),
		Vector3(-side * 0.04, 0.10, 0.12),
	]
	for offset in authored_offsets:
		var candidate_boat := (
			desired_boat * TILLER_EXTENSION_SHAFT_LENGTH + offset
		).normalized()
		var candidate_rudder := _clamp_tiller_extension_cone(
			(rudder_pivot.basis.inverse() * candidate_boat).normalized(),
			max_joint_angle
		)
		var resolved_boat := (rudder_pivot.basis * candidate_rudder).normalized()
		if not _handover_direction_preserves_route(resolved_boat, side, true):
			continue
		if _extension_direction_is_safe(candidate_rudder, joint_boat, body_capsules):
			return candidate_rudder

	# Compact upper/central alternatives keep the grip inside both arm-reach
	# spheres as the torso starts crossing. The former x=.50..68 lattice aimed the
	# shaft at an obsolete far-aft handover and left the extension blocked while a
	# shoulder moved over the stationary grip. Pick the safe vector closest to the
	# authored request; there is deliberately no distant/opposite-side fallback.
	var aft_upper_route_vectors: Array[Vector3] = [
		Vector3(side * 0.22, 0.60, -0.54),
		Vector3(side * 0.14, 0.64, -0.56),
		Vector3(side * 0.06, 0.68, -0.58),
		Vector3(0.0, 0.70, -0.60),
		Vector3(-side * 0.06, 0.68, -0.58),
	]
	var best_candidate := Vector3.ZERO
	var best_error: float = INF
	for route_vector_boat in aft_upper_route_vectors:
		var candidate_rudder := _clamp_tiller_extension_cone(
			(rudder_pivot.basis.inverse() * route_vector_boat.normalized()).normalized(),
			max_joint_angle
		)
		var resolved_boat := (rudder_pivot.basis * candidate_rudder).normalized()
		if not _handover_direction_preserves_route(resolved_boat, side, true):
			continue
		if not _extension_direction_is_safe(candidate_rudder, joint_boat, body_capsules):
			continue
		var candidate_error := candidate_rudder.angle_to(desired_rudder)
		if candidate_error < best_error:
			best_error = candidate_error
			best_candidate = candidate_rudder
	return best_candidate


func _handover_direction_preserves_route(
	direction_boat: Vector3,
	_side: float,
	require_aft: bool
) -> bool:
	var self_side := signf(direction_boat.x)
	if (
		not is_zero_approx(self_side)
		and _normal_extension_direction_preserves_side(direction_boat, self_side)
	):
		return true
	# The sailor turns toward the stern while crossing in front of the controls.
	# A low centreline handover therefore uses the same upward, forward shaft
	# hemisphere as ordinary steering. The old arbitrary z > -0.72 cut forced a
	# valid chest-height centre target upward even when the whole shaft was clear.
	# Joint cone, complete shaft capsules and wrist reach still certify every pair.
	return direction_boat.y >= 0.32 and (not require_aft or direction_boat.z <= 0.15)


func _extension_direction_is_safe(
	direction_rudder: Vector3,
	joint_boat: Vector3,
	body_capsules: Array
) -> bool:
	var direction_boat := (rudder_pivot.basis * direction_rudder).normalized()
	var visible_tip := joint_boat + direction_boat * TILLER_EXTENSION_VISIBLE_TIP_LENGTH
	# A raised joint-to-grip segment stays clear of the cockpit floor and rails.
	if minf(joint_boat.y, visible_tip.y) < 0.285:
		return false
	for capsule in body_capsules:
		var distance := _segment_segment_distance(
			joint_boat,
			visible_tip,
			capsule["from"],
			capsule["to"]
		)
		if distance < float(capsule["clearance"]) + TILLER_EXTENSION_SHAFT_CLEARANCE:
			return false
	return true


func _segment_segment_distance(
	p1: Vector3,
	q1: Vector3,
	p2: Vector3,
	q2: Vector3
) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var epsilon := 0.000001
	var s := 0.0
	var t := 0.0
	if a <= epsilon and e <= epsilon:
		return p1.distance_to(p2)
	if a <= epsilon:
		t = clampf(d2.dot(r) / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= epsilon:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denominator := a * e - b * b
			if not is_zero_approx(denominator):
				s = clampf((b * d2.dot(r) - c * e) / denominator, 0.0, 1.0)
			t = (b * s + d2.dot(r)) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


func _sync_sail_clew_to_boom() -> void:
	if (
		not is_instance_valid(sail)
		or not is_instance_valid(clew_strap)
		or not is_instance_valid(clew_grommet)
	):
		return
	# The sail clew and the outhaul meet the visible metal eye at the top of the
	# webbing, not the ClewStrap node origin on the boom centreline.
	var clew_eye_global := clew_strap.rope_anchor_global(&"bridge")
	clew_grommet.global_position = clew_eye_global
	sail.set_clew_target_local(sail.to_local(clew_eye_global))
