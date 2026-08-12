class_name SailingState
extends RefCounted

const HEAD_TO_WIND_ZERO_DRIVE_DEGREES := 20.0
const CLOSE_HAULED_REFERENCE_DEGREES := 42.0
const MAX_SHEET_RATE := 0.45
const MAX_TURN_RATE := deg_to_rad(42.0)
const BOOM_SPRING_STRENGTH := 20.0
const BOOM_DAMPING := 5.8
const MAX_BOOM_SPEED := deg_to_rad(260.0)
const LATERAL_LINEAR_DRAG := 2.4
const LATERAL_QUADRATIC_DRAG := 1.1

var heading_radians: float = 0.0
var speed_mps: float = 0.0
var sheet_position: float = 0.45
var true_wind_velocity := Vector3(6.0, 0.0, 0.0)
var water_current_velocity := Vector3.ZERO
var boom_angle_radians := deg_to_rad(38.0)
var boom_angular_velocity := 0.0
var water_relative_velocity := Vector3.ZERO

var _boom_side := 1.0
var _water_velocity_initialized := false


func step(delta: float, command: SailingCommand) -> void:
	_initialize_water_velocity_from_legacy_speed()
	sheet_position = clampf(
		sheet_position + command.sheet_delta * MAX_SHEET_RATE * delta,
		0.0,
		1.0
	)

	var forward_before_turn := forward_vector()
	var through_water_forward_speed := maxf(
		0.0,
		water_relative_velocity.dot(forward_before_turn)
	)
	var steering_authority := clampf(through_water_forward_speed / 3.0, 0.0, 1.0)
	heading_radians = wrapf(
		heading_radians - command.rudder * MAX_TURN_RATE * steering_authority * delta,
		-PI,
		PI
	)

	var target_speed := _calculate_target_speed()
	if target_speed > speed_mps:
		speed_mps = move_toward(speed_mps, target_speed, 0.65 * delta)
	else:
		# Pointing too high removes drive, but the hull keeps its momentum and
		# slows progressively from hydrodynamic drag instead of hitting a brake.
		var drag_rate := 0.11 + speed_mps * speed_mps * 0.024
		speed_mps = maxf(target_speed, speed_mps - drag_rate * delta)
	_update_water_relative_velocity(delta)
	_update_boom(delta)


func forward_vector() -> Vector3:
	return Vector3(-sin(heading_radians), 0.0, -cos(heading_radians))


func velocity_vector() -> Vector3:
	return ground_velocity_vector()


func water_velocity_vector() -> Vector3:
	_initialize_water_velocity_from_legacy_speed()
	return water_relative_velocity


func ground_velocity_vector() -> Vector3:
	return water_velocity_vector() + water_current_velocity


func ground_speed_mps() -> float:
	return ground_velocity_vector().length()


func apparent_wind_velocity() -> Vector3:
	return true_wind_velocity - ground_velocity_vector()


func wind_angle_degrees() -> float:
	var wind_from := -true_wind_velocity.normalized()
	var alignment := clampf(forward_vector().dot(wind_from), -1.0, 1.0)
	return rad_to_deg(acos(alignment))


func apparent_wind_speed_mps() -> float:
	return apparent_wind_velocity().length()


func optimal_sheet_position() -> float:
	return clampf(remap(wind_angle_degrees(), 30.0, 180.0, 0.08, 1.0), 0.08, 1.0)


func boom_angle_degrees() -> float:
	return rad_to_deg(boom_angle_radians)


func _update_boom(delta: float) -> void:
	var apparent_wind := apparent_wind_velocity()
	if apparent_wind.length_squared() > 0.001:
		var apparent_wind_from := -apparent_wind.normalized()
		var side_signal := forward_vector().cross(apparent_wind_from).y
		if absf(side_signal) > 0.025:
			_boom_side = signf(side_signal)

	var maximum_angle := deg_to_rad(lerpf(5.0, 84.0, sheet_position))
	var target_angle := _boom_side * maximum_angle
	var angular_acceleration := (
		(target_angle - boom_angle_radians) * BOOM_SPRING_STRENGTH
		- boom_angular_velocity * BOOM_DAMPING
	)
	boom_angular_velocity = clampf(
		boom_angular_velocity + angular_acceleration * delta,
		-MAX_BOOM_SPEED,
		MAX_BOOM_SPEED
	)
	boom_angle_radians = clampf(
		boom_angle_radians + boom_angular_velocity * delta,
		-maximum_angle,
		maximum_angle
	)


func _initialize_water_velocity_from_legacy_speed() -> void:
	# Existing callers and saved tests still seed scalar speed directly. Treat it
	# as an initial through-water velocity, then retain vector momentum thereafter.
	if _water_velocity_initialized:
		return
	if water_relative_velocity.length_squared() < 0.000001 and speed_mps > 0.0001:
		water_relative_velocity = forward_vector() * speed_mps
	_water_velocity_initialized = true


func _update_water_relative_velocity(delta: float) -> void:
	var forward := forward_vector()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var forward_speed := water_relative_velocity.dot(forward)
	var lateral_speed := water_relative_velocity.dot(right)
	forward_speed = move_toward(forward_speed, speed_mps, 1.35 * delta)
	var lateral_drag := (
		lateral_speed * LATERAL_LINEAR_DRAG
		+ lateral_speed * absf(lateral_speed) * LATERAL_QUADRATIC_DRAG
	)
	var new_lateral_speed := move_toward(
		lateral_speed,
		0.0,
		absf(lateral_drag) * delta
	)
	water_relative_velocity = (
		forward * forward_speed
		+ right * new_lateral_speed
	)
	speed_mps = maxf(0.0, water_relative_velocity.dot(forward))


func _calculate_target_speed() -> float:
	var angle := wind_angle_degrees()
	var polar_efficiency: float
	if angle <= HEAD_TO_WIND_ZERO_DRIVE_DEGREES:
		polar_efficiency = 0.0
	elif angle < CLOSE_HAULED_REFERENCE_DEGREES:
		var close_reach_ratio := smoothstep(
			HEAD_TO_WIND_ZERO_DRIVE_DEGREES,
			CLOSE_HAULED_REFERENCE_DEGREES,
			angle
		)
		polar_efficiency = lerpf(0.0, 0.70, close_reach_ratio)
	elif angle <= 100.0:
		polar_efficiency = remap(angle, CLOSE_HAULED_REFERENCE_DEGREES, 100.0, 0.70, 1.0)
	else:
		polar_efficiency = remap(angle, 100.0, 180.0, 1.0, 0.72)

	var trim_error := absf(sheet_position - optimal_sheet_position())
	var trim_efficiency := 1.0 - clampf(trim_error / 0.65, 0.0, 1.0)
	return true_wind_velocity.length() * 0.72 * polar_efficiency * lerpf(0.2, 1.0, trim_efficiency)
