class_name OceanSurface
extends MeshInstance3D

@export var target_path: NodePath
@export var environment_path: NodePath

@onready var target: Node3D = get_node(target_path)
@onready var sailing_environment: SailingEnvironment = get_node(environment_path)
@onready var ocean_material: ShaderMaterial = material_override as ShaderMaterial


func _process(_delta: float) -> void:
	var target_position := target.global_position
	global_position = Vector3(target_position.x, 0.0, target_position.z)

	var wind := sailing_environment.true_wind_at(target_position)
	var current := sailing_environment.current_at(target_position)
	var sea_state := sailing_environment.wave_sea_state(target_position)
	ocean_material.set_shader_parameter("wind_direction", sea_state["direction_a"])
	ocean_material.set_shader_parameter("wind_speed", wind.length())
	ocean_material.set_shader_parameter("current_velocity", Vector2(current.x, current.z))
	ocean_material.set_shader_parameter("simulation_time", sailing_environment.simulation_time)
	ocean_material.set_shader_parameter("sea_level", sailing_environment.sea_level)
	ocean_material.set_shader_parameter("wave_amplitudes", sailing_environment.wave_amplitudes)
	ocean_material.set_shader_parameter("wave_numbers", sailing_environment.wave_numbers)
	ocean_material.set_shader_parameter(
		"wave_angular_speeds",
		sailing_environment.wave_angular_speeds
	)
	ocean_material.set_shader_parameter(
		"cross_wave_direction_offset",
		sailing_environment.cross_wave_direction_offset
	)
	ocean_material.set_shader_parameter(
		"cross_swell_strength",
		sailing_environment.cross_swell_strength
	)
