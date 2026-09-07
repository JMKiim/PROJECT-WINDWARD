class_name SailingEnvironment
extends Node

const GRAVITY_ACCELERATION_MPS2 := 9.81
const REFERENCE_WIND_SPEED_MPS := 6.0
const MIN_HORIZONTAL_DIRECTION_SQUARED := 0.0001

class WaterSurfaceSample:
	extends RefCounted
	var height := 0.0
	var normal := Vector3.UP
	var vertical_velocity := 0.0
	var current_velocity := Vector3.ZERO

@export var base_true_wind_velocity := Vector3(6.0, 0.0, 0.0)
@export_range(0.0, 4.0, 0.05) var gust_strength_mps := 1.15
@export_range(0.0, 30.0, 0.5) var direction_shift_degrees := 7.0
@export var base_current_velocity := Vector3(0.16, 0.0, -0.05)
@export_range(0.0, 1.0, 0.01) var current_variation_mps := 0.06
@export var sea_level := 0.0
@export var wave_amplitudes := Vector3(0.105, 0.034, 0.010)
@export var wave_numbers := Vector3(0.34, 0.68, 1.48)
# Fixed, non-aligned phases keep the three deterministic wave trains from
# repeatedly stacking into one artificial moving stripe.
@export var wave_phase_offsets := Vector3(0.47, 2.19, 4.03)
@export_range(0.0, 1.0, 0.01) var cross_wave_direction_offset := 0.18
@export_range(0.0, 1.0, 0.01) var cross_swell_strength := 0.36

var simulation_time := 0.0
var surface_flow_offset := Vector2.ZERO

# Compatibility-facing access remains available, but frequency now has one
# physical source of truth: the configured wave number and deep-water gravity
# dispersion. It is deliberately not an exported tuning knob anymore.
var wave_angular_speeds: Vector3:
	get:
		return deep_water_wave_angular_speeds()

var _stable_wave_direction := Vector2.RIGHT
var _stable_cross_wave_direction := Vector2.RIGHT
var _stable_wave_amplitude_scale := 1.0
var _stable_wave_state_initialized := false


func _ready() -> void:
	initialize_stable_wave_state()


func _physics_process(delta: float) -> void:
	advance_simulation(delta)


func advance_simulation(delta: float) -> void:
	# Visual surface detail is advected by an integrated offset. Multiplying an
	# absolute clock by a current sampled at this frame would retroactively move
	# the complete noise field whenever current changed.
	simulation_time += delta
	surface_flow_offset += stable_surface_current_velocity() * delta


func reset_simulation(time_seconds: float = 0.0) -> void:
	# Tests and deterministic replays can reset both clocks atomically. Starting
	# at a non-zero time reconstructs the stable base-current offset exactly.
	simulation_time = time_seconds
	surface_flow_offset = stable_surface_current_velocity() * time_seconds


func initialize_stable_wave_state() -> void:
	# Waves describe one global sea state. Local gusts may still drive the sail,
	# but they must not rotate or retime an already existing wave field.
	var base_direction := Vector2(
		base_true_wind_velocity.x,
		base_true_wind_velocity.z
	)
	if base_direction.length_squared() < MIN_HORIZONTAL_DIRECTION_SQUARED:
		base_direction = Vector2.RIGHT
	_stable_wave_direction = base_direction.normalized()
	var perpendicular := Vector2(-_stable_wave_direction.y, _stable_wave_direction.x)
	_stable_cross_wave_direction = (
		_stable_wave_direction + perpendicular * cross_wave_direction_offset
	).normalized()
	_stable_wave_amplitude_scale = clampf(
		base_true_wind_velocity.length() / REFERENCE_WIND_SPEED_MPS,
		0.55,
		1.8
	)
	_stable_wave_state_initialized = true


func stable_wave_direction() -> Vector2:
	_ensure_stable_wave_state()
	return _stable_wave_direction


func stable_cross_wave_direction() -> Vector2:
	_ensure_stable_wave_state()
	return _stable_cross_wave_direction


func stable_wave_amplitude_scale() -> float:
	_ensure_stable_wave_state()
	return _stable_wave_amplitude_scale


func stable_surface_current_velocity() -> Vector2:
	return Vector2(base_current_velocity.x, base_current_velocity.z)


func surface_pattern_flow_offset() -> Vector2:
	return surface_flow_offset


func deep_water_angular_speed(wave_number: float) -> float:
	return sqrt(maxf(0.0, GRAVITY_ACCELERATION_MPS2 * wave_number))


func deep_water_wave_angular_speeds() -> Vector3:
	return Vector3(
		deep_water_angular_speed(wave_numbers.x),
		deep_water_angular_speed(wave_numbers.y),
		deep_water_angular_speed(wave_numbers.z)
	)


func _ensure_stable_wave_state() -> void:
	if not _stable_wave_state_initialized:
		initialize_stable_wave_state()


func true_wind_at(
	world_position: Vector3,
	time_seconds: float = simulation_time
) -> Vector3:
	var broad_gust := sin(
		world_position.x * 0.032
		+ world_position.z * 0.018
		- time_seconds * 0.42
	)
	var fine_gust := sin(
		-world_position.x * 0.074
		+ world_position.z * 0.058
		- time_seconds * 0.91
	)
	var gust := broad_gust * 0.7 + fine_gust * 0.3
	var wind_speed := maxf(0.5, base_true_wind_velocity.length() + gust * gust_strength_mps)

	var direction_shift := deg_to_rad(direction_shift_degrees) * sin(
		world_position.x * 0.017
		- world_position.z * 0.024
		+ time_seconds * 0.16
	)
	var base_direction := base_true_wind_velocity.normalized()
	if base_direction.length_squared() < MIN_HORIZONTAL_DIRECTION_SQUARED:
		base_direction = Vector3.RIGHT
	return base_direction.rotated(Vector3.UP, direction_shift) * wind_speed


func current_at(
	world_position: Vector3,
	time_seconds: float = simulation_time
) -> Vector3:
	var current_wave := sin(
		world_position.x * 0.011
		+ world_position.z * 0.016
		- time_seconds * 0.08
	)
	var variation_direction := Vector3(-0.35, 0.0, 0.94).normalized()
	return base_current_velocity + variation_direction * current_wave * current_variation_mps


func wave_sea_state(
	_world_position: Vector3,
	_time_seconds: float = simulation_time
) -> Dictionary:
	var direction_a := stable_wave_direction()
	var direction_b := stable_cross_wave_direction()
	var amplitude_scale := stable_wave_amplitude_scale()
	return {
		"direction_a": direction_a,
		"direction_b": direction_b,
		# Preserve the original key for callers while exposing the physical name.
		"wind_scale": amplitude_scale,
		"wave_amplitude_scale": amplitude_scale,
		"wind_speed": base_true_wind_velocity.length(),
		"angular_speeds": deep_water_wave_angular_speeds(),
		"phase_offsets": wave_phase_offsets,
		"flow_offset": _flow_offset_at_time(_time_seconds),
		"flow_velocity": stable_surface_current_velocity(),
	}


func water_surface_at(
	world_position: Vector3,
	time_seconds: float = simulation_time,
	sea_state: Dictionary = {}
) -> WaterSurfaceSample:
	var state := sea_state if not sea_state.is_empty() else wave_sea_state(world_position, time_seconds)
	var direction_a: Vector2 = state["direction_a"]
	var direction_b: Vector2 = state["direction_b"]
	var amplitude_scale: float = state.get(
		"wave_amplitude_scale",
		state.get("wind_scale", 1.0)
	)
	var angular_speeds: Vector3 = state.get(
		"angular_speeds",
		deep_water_wave_angular_speeds()
	)
	var phase_offsets: Vector3 = state.get("phase_offsets", wave_phase_offsets)
	var flow_offset: Vector2 = state.get(
		"flow_offset",
		_flow_offset_at_time(time_seconds)
	)
	var flow_velocity: Vector2 = state.get(
		"flow_velocity",
		stable_surface_current_velocity()
	)
	var position_xz := Vector2(world_position.x, world_position.z) - flow_offset
	var directions := [direction_a, direction_b, direction_a]
	var result := WaterSurfaceSample.new()
	result.height = sea_level
	var derivative_x := 0.0
	var derivative_z := 0.0
	for wave_index in range(3):
		var direction: Vector2 = directions[wave_index]
		var amplitude: float = wave_amplitudes[wave_index]
		if wave_index < 2:
			amplitude *= amplitude_scale
		if wave_index == 1:
			amplitude *= cross_swell_strength
		var wave_number: float = wave_numbers[wave_index]
		var angular_speed: float = angular_speeds[wave_index]
		var phase := (
			position_xz.dot(direction) * wave_number
			- time_seconds * angular_speed
			+ phase_offsets[wave_index]
		)
		result.height += sin(phase) * amplitude
		var phase_cosine := cos(phase)
		derivative_x += phase_cosine * amplitude * wave_number * direction.x
		derivative_z += phase_cosine * amplitude * wave_number * direction.y
		# A uniformly advected wave changes at a fixed world point with both its
		# intrinsic frequency and the current's phase rate. At the moving boat the
		# same current then cancels out, so encounter motion follows through-water
		# speed instead of an accidental ground-frame mixture.
		var observed_angular_speed := (
			angular_speed
			+ wave_number * direction.dot(flow_velocity)
		)
		result.vertical_velocity -= (
			phase_cosine * amplitude * observed_angular_speed
		)
	result.normal = Vector3(-derivative_x, 1.0, -derivative_z).normalized()
	result.current_velocity = current_at(world_position, time_seconds)
	return result


func _flow_offset_at_time(time_seconds: float) -> Vector2:
	# Explicit samples continue from the integrated live reference. This avoids
	# retroactively relocating the entire field when a configured current changes.
	return (
		surface_flow_offset
		+ stable_surface_current_velocity() * (time_seconds - simulation_time)
	)
