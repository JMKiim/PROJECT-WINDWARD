class_name WindStreaks
extends MultiMeshInstance3D

const STREAK_COUNT := 28
const FIELD_SIZE := 54.0
const MIN_ALTITUDE := 1.5
const MAX_ALTITUDE := 4.0

@export var target_path: NodePath
@export var environment_path: NodePath

@onready var target: WindwardBoat = get_node(target_path) as WindwardBoat
@onready var sailing_environment: SailingEnvironment = get_node(environment_path)

var _offsets: Array[Vector3] = []
var _speed_scales: Array[float] = []


func _ready() -> void:
	var streak_material := StandardMaterial3D.new()
	streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_material.vertex_color_use_as_albedo = true
	streak_material.albedo_color = Color(0.76, 0.92, 1.0, 0.32)

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
	for index in STREAK_COUNT:
		_offsets.append(Vector3(
			random.randf_range(-FIELD_SIZE * 0.5, FIELD_SIZE * 0.5),
			random.randf_range(MIN_ALTITUDE, MAX_ALTITUDE),
			random.randf_range(-FIELD_SIZE * 0.5, FIELD_SIZE * 0.5)
		))
		_speed_scales.append(random.randf_range(0.72, 1.22))
		multimesh.set_instance_color(
			index,
			Color(0.72, 0.94, 1.0, random.randf_range(0.10, 0.24))
		)


func _process(delta: float) -> void:
	var center := target.global_position
	var apparent_wind := target.get_sailing_state().apparent_wind_velocity()
	apparent_wind.y = 0.0
	if apparent_wind.length_squared() < 0.0001:
		multimesh.visible_instance_count = 0
		return
	# Do not mutate this node's visibility: the main scene may deliberately hide
	# the optional cue. Instance count only handles the zero-airflow edge case.
	multimesh.visible_instance_count = STREAK_COUNT
	var wind_direction := apparent_wind.normalized()
	var yaw := -atan2(wind_direction.z, wind_direction.x)
	var half_field := FIELD_SIZE * 0.5

	for index in STREAK_COUNT:
		# Offsets live in the boat-relative field, so integrating apparent wind
		# once produces the correct perceived airflow without subtracting the
		# boat's ground velocity a second time. fposmod makes the constant-vector
		# integration independent of render-frame subdivision.
		var offset := _offsets[index]
		offset += apparent_wind * delta * _speed_scales[index]
		offset.x = fposmod(offset.x + half_field, FIELD_SIZE) - half_field
		offset.z = fposmod(offset.z + half_field, FIELD_SIZE) - half_field
		_offsets[index] = offset
		var position := Vector3(
			center.x + offset.x,
			sailing_environment.sea_level + offset.y,
			center.z + offset.z
		)

		var length_scale := clampf(
			apparent_wind.length() / 8.0,
			0.55,
			1.40
		) * _speed_scales[index]
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(length_scale, 1.0, 1.0))
		multimesh.set_instance_transform(index, Transform3D(basis, position))
