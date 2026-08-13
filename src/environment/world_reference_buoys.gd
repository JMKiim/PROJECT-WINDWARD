class_name WorldReferenceBuoys
extends MultiMeshInstance3D

# These are scale and ground-speed references, not race marks. Their X/Z
# coordinates remain world-fixed while only Y follows the analytic water. The
# ring surrounds the starting area instead of existing only down one course, so
# at least one fixed reference remains useful after a tack or broad turn.
var buoy_positions := PackedVector2Array([
	Vector2(-18.0, -24.0),
	Vector2(21.0, -41.0),
	Vector2(-34.0, -58.0),
	Vector2(46.0, -77.0),
	Vector2(-61.0, -92.0),
	Vector2(34.0, 24.0),
	Vector2(-48.0, 38.0),
	Vector2(71.0, 6.0),
	Vector2(-82.0, -8.0),
	Vector2(12.0, 91.0),
])
const FLOAT_CLEARANCE := 0.18

@export var environment_path: NodePath

@onready var sailing_environment: SailingEnvironment = get_node(environment_path)


func _ready() -> void:
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.95, 0.48, 0.08)
	body_material.roughness = 0.72
	body_material.metallic = 0.0

	var body := CapsuleMesh.new()
	body.radius = 0.13
	body.height = 0.52
	body.radial_segments = 20
	body.rings = 8
	body.material = body_material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = body
	multimesh.instance_count = buoy_positions.size()
	_update_buoys()


func _physics_process(_delta: float) -> void:
	_update_buoys()


func _update_buoys() -> void:
	if not multimesh or not is_instance_valid(sailing_environment):
		return
	for index in buoy_positions.size():
		var fixed_xz := buoy_positions[index]
		var world_position := Vector3(fixed_xz.x, 0.0, fixed_xz.y)
		var surface := sailing_environment.water_surface_at(world_position)
		world_position.y = surface.height + FLOAT_CLEARANCE
		var up := surface.normal.normalized()
		var tangent := Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
		tangent = tangent.normalized()
		var right := up.cross(tangent).normalized()
		multimesh.set_instance_transform(
			index,
			Transform3D(Basis(right, up, tangent), to_local(world_position))
		)
