class_name OceanSurface
extends MeshInstance3D

@export var target_path: NodePath
@export var environment_path: NodePath

@onready var target: Node3D = get_node(target_path)
@onready var sailing_environment: SailingEnvironment = get_node(environment_path)
@onready var ocean_material: ShaderMaterial = material_override as ShaderMaterial


func _process(_delta: float) -> void:
	var target_position := target.global_position
	global_position = snapped_surface_center(target_position)

	var sea_state := sailing_environment.wave_sea_state(target_position)
	ocean_material.set_shader_parameter("wind_direction", sea_state["direction_a"])
	ocean_material.set_shader_parameter("secondary_wave_direction", sea_state["direction_b"])
	ocean_material.set_shader_parameter(
		"wave_amplitude_scale",
		sea_state["wave_amplitude_scale"]
	)
	ocean_material.set_shader_parameter(
		"surface_flow_offset",
		sailing_environment.surface_pattern_flow_offset()
	)
	ocean_material.set_shader_parameter("simulation_time", sailing_environment.simulation_time)
	ocean_material.set_shader_parameter("sea_level", sailing_environment.sea_level)
	ocean_material.set_shader_parameter("wave_amplitudes", sailing_environment.wave_amplitudes)
	ocean_material.set_shader_parameter("wave_numbers", sailing_environment.wave_numbers)
	ocean_material.set_shader_parameter(
		"wave_phase_offsets",
		sailing_environment.wave_phase_offsets
	)
	ocean_material.set_shader_parameter(
		"wave_angular_speeds",
		sea_state["angular_speeds"]
	)
	ocean_material.set_shader_parameter(
		"cross_swell_strength",
		sailing_environment.cross_swell_strength
	)


func ocean_grid_spacing() -> Vector2:
	var plane := mesh as PlaneMesh
	if not plane:
		return Vector2.ONE
	# PlaneMesh subdivision values count additional cuts. A value of zero still
	# creates one cell, hence the +1 when deriving the world-space vertex grid.
	return Vector2(
		plane.size.x / float(maxi(1, plane.subdivide_width + 1)),
		plane.size.y / float(maxi(1, plane.subdivide_depth + 1))
	)


func snapped_surface_center(world_position: Vector3) -> Vector3:
	# Keep the finite patch around the boat, but move it only by whole vertex
	# cells. Overlapping vertices then retain identical world coordinates and the
	# analytic waves/specular field cannot swim as the patch follows the boat.
	var spacing := ocean_grid_spacing()
	return Vector3(
		roundf(world_position.x / spacing.x) * spacing.x,
		0.0,
		roundf(world_position.z / spacing.y) * spacing.y
	)
