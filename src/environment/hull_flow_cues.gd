class_name HullFlowCues
extends MeshInstance3D

const FLOW_ONSET_SPEED_MPS := 0.60
const FULL_FLOW_SPEED_MPS := 4.60
const MIN_RIBBON_LENGTH := 0.38
const MAX_RIBBON_LENGTH := 1.55
const MIN_RIBBON_WIDTH := 0.018
const MAX_RIBBON_WIDTH := 0.055
const BOW_SHOULDER_LOCAL := Vector3(0.30, 0.0, -1.40)
const SURFACE_CLEARANCE := 0.016
const RIBBON_SEGMENTS := 10

@export var boat_path: NodePath
@export var environment_path: NodePath

@onready var boat: WindwardBoat = get_node(boat_path) as WindwardBoat
@onready var sailing_environment: SailingEnvironment = (
	get_node(environment_path) as SailingEnvironment
)

var _flow_mesh := ImmediateMesh.new()
var _flow_material := StandardMaterial3D.new()


func _ready() -> void:
	_flow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flow_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_flow_material.vertex_color_use_as_albedo = true
	_flow_material.albedo_color = Color(0.78, 0.91, 0.94, 1.0)
	_flow_material.roughness = 0.48
	_flow_material.metallic = 0.0
	_flow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _flow_mesh


func _physics_process(_delta: float) -> void:
	_flow_mesh.clear_surfaces()

	# This cue describes water passing the hull, so neither ground speed nor
	# current may contribute to its intensity or dimensions.
	var water_velocity := boat.get_sailing_state().water_velocity_vector()
	water_velocity.y = 0.0
	var water_speed := water_velocity.length()
	if water_speed <= FLOW_ONSET_SPEED_MPS:
		return

	var speed_ratio := smoothstep(
		FLOW_ONSET_SPEED_MPS,
		FULL_FLOW_SPEED_MPS,
		water_speed
	)
	# Start at the physical bow shoulders and let the water peel aft along the
	# hull. Leeway still nudges the trail laterally, but it cannot make the cue
	# shoot forward across the bow.
	var boat_forward := -boat.global_basis.z
	boat_forward.y = 0.0
	boat_forward = boat_forward.normalized()
	var aft_direction := -boat_forward
	var lateral_water_velocity := water_velocity - boat_forward * water_velocity.dot(
		boat_forward
	)
	var flow_direction := (
		aft_direction + -lateral_water_velocity * 0.12
	).normalized()
	var flow_right := Vector3(-flow_direction.z, 0.0, flow_direction.x)
	var boat_outward := boat.global_basis.x
	boat_outward.y = 0.0
	boat_outward = boat_outward.normalized()
	var ribbon_length := lerpf(MIN_RIBBON_LENGTH, MAX_RIBBON_LENGTH, speed_ratio)
	var ribbon_width := lerpf(MIN_RIBBON_WIDTH, MAX_RIBBON_WIDTH, speed_ratio)
	var strength := speed_ratio * 0.42

	_build_ribbon(
		-1.0,
		flow_direction,
		flow_right,
		boat_outward,
		ribbon_length,
		ribbon_width,
		strength
	)
	_build_ribbon(
		1.0,
		flow_direction,
		flow_right,
		boat_outward,
		ribbon_length,
		ribbon_width,
		strength
	)


func _build_ribbon(
	side: float,
	flow_direction: Vector3,
	flow_right: Vector3,
	boat_outward: Vector3,
	ribbon_length: float,
	base_width: float,
	strength: float
) -> void:
	var shoulder_local := BOW_SHOULDER_LOCAL
	shoulder_local.x *= side
	var shoulder_world := boat.to_global(shoulder_local)
	var outward := boat_outward * side

	_flow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _flow_material)
	for segment in range(RIBBON_SEGMENTS + 1):
		var along := float(segment) / float(RIBBON_SEGMENTS)
		var profile := pow(maxf(0.0, sin(PI * along)), 0.70)
		var half_width := base_width * lerpf(0.32, 1.0, profile)
		var center := (
			shoulder_world
			+ flow_direction * ribbon_length * along
			+ outward * base_width * 0.35 * profile
		)
		var alpha := (
			strength
			* smoothstep(0.0, 0.14, along)
			* pow(1.0 - along, 1.65)
		)
		var color := Color(0.76, 0.94, 0.98, alpha)
		_add_surface_vertex(center - flow_right * half_width, color)
		_add_surface_vertex(center + flow_right * half_width, color)
	_flow_mesh.surface_end()


func _add_surface_vertex(world_position: Vector3, color: Color) -> void:
	var surface := sailing_environment.water_surface_at(world_position)
	var attached_position := world_position
	attached_position.y = surface.height + SURFACE_CLEARANCE
	_flow_mesh.surface_set_color(color)
	_flow_mesh.surface_set_normal(_world_normal_to_local(surface.normal))
	_flow_mesh.surface_add_vertex(to_local(attached_position))


func _world_normal_to_local(world_normal: Vector3) -> Vector3:
	# Vertices use to_local(), so their analytic water normals need the matching
	# inverse normal transform. The transpose also remains correct if this cue is
	# ever placed below a scaled parent rather than directly under the world root.
	return (global_basis.transposed() * world_normal).normalized()
