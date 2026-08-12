class_name SailingEnvironment
extends Node

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
@export var wave_angular_speeds := Vector3(1.18, 1.72, 2.55)
@export_range(0.0, 1.0, 0.01) var cross_wave_direction_offset := 0.18
@export_range(0.0, 1.0, 0.01) var cross_swell_strength := 0.36

var simulation_time := 0.0


func _physics_process(delta: float) -> void:
	simulation_time += delta


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
	return base_true_wind_velocity.normalized().rotated(Vector3.UP, direction_shift) * wind_speed


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
	world_position: Vector3,
	time_seconds: float = simulation_time
) -> Dictionary:
	var wind := true_wind_at(world_position, time_seconds)
	var direction := Vector2(wind.x, wind.z)
	if direction.length_squared() < 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	return {
		"direction_a": direction,
		"direction_b": (direction + perpendicular * cross_wave_direction_offset).normalized(),
		"wind_scale": clampf(wind.length() / 6.0, 0.55, 1.8),
		"wind_speed": wind.length(),
	}


func water_surface_at(
	world_position: Vector3,
	time_seconds: float = simulation_time,
	sea_state: Dictionary = {}
) -> WaterSurfaceSample:
	var state := sea_state if not sea_state.is_empty() else wave_sea_state(world_position, time_seconds)
	var direction_a: Vector2 = state["direction_a"]
	var direction_b: Vector2 = state["direction_b"]
	var wind_scale: float = state["wind_scale"]
	var position_xz := Vector2(world_position.x, world_position.z)
	var directions := [direction_a, direction_b, direction_a]
	var result := WaterSurfaceSample.new()
	result.height = sea_level
	var derivative_x := 0.0
	var derivative_z := 0.0
	for wave_index in range(3):
		var direction: Vector2 = directions[wave_index]
		var amplitude: float = wave_amplitudes[wave_index]
		if wave_index < 2:
			amplitude *= wind_scale
		if wave_index == 1:
			amplitude *= cross_swell_strength
		var wave_number: float = wave_numbers[wave_index]
		var angular_speed: float = wave_angular_speeds[wave_index] * wind_scale
		var phase := position_xz.dot(direction) * wave_number - time_seconds * angular_speed
		result.height += sin(phase) * amplitude
		var phase_cosine := cos(phase)
		derivative_x += phase_cosine * amplitude * wave_number * direction.x
		derivative_z += phase_cosine * amplitude * wave_number * direction.y
		result.vertical_velocity -= phase_cosine * amplitude * angular_speed
	result.normal = Vector3(-derivative_x, 1.0, -derivative_z).normalized()
	result.current_velocity = current_at(world_position, time_seconds)
	return result
