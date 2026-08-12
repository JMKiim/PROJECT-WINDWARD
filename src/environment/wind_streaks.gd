class_name WindStreaks
extends MultiMeshInstance3D

const STREAK_COUNT := 36
const FIELD_SIZE := 54.0

@export var target_path: NodePath
@export var environment_path: NodePath

@onready var target: Node3D = get_node(target_path)
@onready var sailing_environment: SailingEnvironment = get_node(environment_path)

var _positions: Array[Vector3] = []
var _speed_scales: Array[float] = []


func _ready() -> void:
	var streak_material := StandardMaterial3D.new()
	streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_material.vertex_color_use_as_albedo = true
	streak_material.albedo_color = Color(0.72, 0.92, 0.98, 0.12)

	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.82, 0.006, 0.018)
	streak_mesh.material = streak_material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = streak_mesh
	multimesh.instance_count = STREAK_COUNT

	var random := RandomNumberGenerator.new()
	random.seed = 0x57494E44
	var center := target.global_position
	for index in STREAK_COUNT:
		_positions.append(Vector3(
			center.x + random.randf_range(-FIELD_SIZE * 0.5, FIELD_SIZE * 0.5),
			random.randf_range(0.055, 0.13),
			center.z + random.randf_range(-FIELD_SIZE * 0.5, FIELD_SIZE * 0.5)
		))
		_speed_scales.append(random.randf_range(0.72, 1.22))
		multimesh.set_instance_color(index, Color(0.72, 0.94, 1.0, random.randf_range(0.12, 0.32)))


func _process(delta: float) -> void:
	var center := target.global_position
	var wind := sailing_environment.true_wind_at(center)
	var wind_direction := wind.normalized()
	var yaw := -atan2(wind_direction.z, wind_direction.x)
	var half_field := FIELD_SIZE * 0.5

	for index in STREAK_COUNT:
		var position := _positions[index]
		position += wind * delta * 0.58 * _speed_scales[index]
		position.x = center.x + fposmod(position.x - center.x + half_field, FIELD_SIZE) - half_field
		position.z = center.z + fposmod(position.z - center.z + half_field, FIELD_SIZE) - half_field
		_positions[index] = position

		var length_scale := clampf(wind.length() / 6.0, 0.65, 1.65) * _speed_scales[index]
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(length_scale, 1.0, 1.0))
		multimesh.set_instance_transform(index, Transform3D(basis, position))
