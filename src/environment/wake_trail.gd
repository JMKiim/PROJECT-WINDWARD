class_name WakeTrail
extends MeshInstance3D

const MAX_SAMPLE_AGE := 9.0
const SAMPLE_DISTANCE := 0.16
const SAMPLE_INTERVAL := 0.09

@export var boat_path: NodePath
@export var environment_path: NodePath

@onready var boat: WindwardBoat = get_node(boat_path)
@onready var sailing_environment: SailingEnvironment = get_node(environment_path)

var _wake_mesh := ImmediateMesh.new()
var _wake_material := StandardMaterial3D.new()
var _samples: Array[Dictionary] = []
var _last_sample_position := Vector3.ZERO
var _sample_timer := 0.0
var _has_sample := false


func _ready() -> void:
	_wake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wake_material.vertex_color_use_as_albedo = true
	_wake_material.albedo_color = Color(0.72, 0.94, 1.0, 1.0)
	_wake_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh = _wake_mesh


func _physics_process(delta: float) -> void:
	_sample_timer += delta
	for index in range(_samples.size() - 1, -1, -1):
		_samples[index]["age"] += delta
		var sample_position: Vector3 = _samples[index]["position"]
		var current := sailing_environment.current_at(sample_position)
		sample_position += current * delta
		var surface := sailing_environment.water_surface_at(sample_position)
		sample_position.y = surface.height + 0.012
		_samples[index]["position"] = sample_position
		if _samples[index]["age"] > MAX_SAMPLE_AGE:
			_samples.remove_at(index)

	var state := boat.get_sailing_state()
	var stern_position := boat.to_global(Vector3(0.0, -0.08, 1.92))
	stern_position.y = sailing_environment.water_surface_at(stern_position).height + 0.012
	var distance_from_last := stern_position.distance_to(_last_sample_position)
	if state.speed_mps > 0.28 and (
		not _has_sample
		or distance_from_last >= SAMPLE_DISTANCE
		or _sample_timer >= SAMPLE_INTERVAL
	):
		_samples.push_front({
			"position": stern_position,
			"right": boat.global_basis.x.normalized(),
			"age": 0.0,
			"strength": clampf(state.speed_mps / 4.5, 0.12, 1.0)
		})
		_last_sample_position = stern_position
		_sample_timer = 0.0
		_has_sample = true

	_rebuild_mesh()


func _rebuild_mesh() -> void:
	_wake_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_build_ribbon(-1.0)
	_build_ribbon(1.0)


func _build_ribbon(side: float) -> void:
	_wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _wake_material)
	for index in _samples.size():
		var sample := _samples[index]
		var age_ratio: float = clampf(sample["age"] / MAX_SAMPLE_AGE, 0.0, 1.0)
		var right: Vector3 = sample["right"]
		var spread := 0.34 + age_ratio * 1.6
		var ribbon_width := 0.05 + age_ratio * 0.18
		var ribbon_center: Vector3 = sample["position"] + right * side * spread
		var emergence := clampf(float(index) / 3.0, 0.0, 1.0)
		var alpha: float = sample["strength"] * emergence * pow(1.0 - age_ratio, 1.5) * 0.86
		var color := Color(0.72, 0.95, 1.0, alpha)

		_wake_mesh.surface_set_color(color)
		_wake_mesh.surface_set_normal(Vector3.UP)
		_wake_mesh.surface_add_vertex(ribbon_center - right * ribbon_width)
		_wake_mesh.surface_set_color(color)
		_wake_mesh.surface_set_normal(Vector3.UP)
		_wake_mesh.surface_add_vertex(ribbon_center + right * ribbon_width)
	_wake_mesh.surface_end()
