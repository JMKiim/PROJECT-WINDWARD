class_name WakeTrail
extends MeshInstance3D

const WAKE_ONSET_SPEED_MPS := 0.45
const FULL_WAKE_SPEED_MPS := 4.6
const SAMPLE_DISTANCE := 0.20
const MAX_SAMPLE_INTERVAL := 0.16
const MIN_SAMPLE_LIFETIME := 1.8
const MAX_SAMPLE_LIFETIME := 4.8
const SURFACE_CLEARANCE := 0.014

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
var _sample_serial := 0


func _ready() -> void:
	_wake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wake_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_wake_material.vertex_color_use_as_albedo = true
	_wake_material.albedo_color = Color(0.78, 0.91, 0.94, 1.0)
	_wake_material.roughness = 0.46
	_wake_material.metallic = 0.0
	_wake_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _wake_mesh


func _physics_process(delta: float) -> void:
	_sample_timer += delta
	for index in range(_samples.size() - 1, -1, -1):
		_samples[index]["age"] += delta
		var sample_position: Vector3 = _samples[index]["position"]
		var current := sailing_environment.current_at(sample_position)
		sample_position += current * delta
		sample_position.y = _surface_height(sample_position)
		_samples[index]["position"] = sample_position
		if float(_samples[index]["age"]) > float(_samples[index]["lifetime"]):
			_samples.remove_at(index)

	var state := boat.get_sailing_state()
	var water_velocity := state.water_velocity_vector()
	water_velocity.y = 0.0
	var water_speed := water_velocity.length()
	var stern_position := boat.to_global(Vector3(0.0, -0.08, 1.92))
	stern_position.y = _surface_height(stern_position)
	var last_advected_position := _last_sample_position
	if not _samples.is_empty():
		last_advected_position = _samples[0]["position"]
	var distance_from_last := _horizontal_distance(
		stern_position,
		last_advected_position
	)
	if water_speed > WAKE_ONSET_SPEED_MPS and (
		not _has_sample
		or distance_from_last >= SAMPLE_DISTANCE
		or _sample_timer >= MAX_SAMPLE_INTERVAL
	):
		if not _has_sample:
			_sample_serial = 0
		var speed_ratio := smoothstep(
			WAKE_ONSET_SPEED_MPS,
			FULL_WAKE_SPEED_MPS,
			water_speed
		)
		var wake_tangent := water_velocity.normalized()
		if wake_tangent.length_squared() < 0.0001:
			wake_tangent = boat.get_sailing_state().forward_vector()
		wake_tangent.y = 0.0
		wake_tangent = wake_tangent.normalized()
		var wake_right := Vector3(-wake_tangent.z, 0.0, wake_tangent.x)
		_samples.push_front({
			"position": stern_position,
			"right": wake_right,
			"serial": _sample_serial,
			"age": 0.0,
			"speed_ratio": speed_ratio,
			"strength": smoothstep(
				WAKE_ONSET_SPEED_MPS,
				FULL_WAKE_SPEED_MPS,
				water_speed
			),
			"lifetime": lerpf(
				MIN_SAMPLE_LIFETIME,
				MAX_SAMPLE_LIFETIME,
				speed_ratio
			),
		})
		_sample_serial += 1
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
	# Independent quads allow truly transparent gaps. A single triangle strip
	# connected every sample into the long, straight "rail" silhouette that was
	# easy to mistake for water motion even when its alpha was reduced.
	# Build each cross-section once. Adjacent quads share it, so the two water
	# samples needed for its edges are not repeated for all six triangle vertices.
	var sections: Array[Dictionary] = []
	for sample in _samples:
		sections.append(_wake_section(sample, side))
	var visible_segments: Array[Dictionary] = []
	for index in range(sections.size() - 1):
		var near_section := sections[index]
		var far_section := sections[index + 1]
		if maxf(
			float(near_section["alpha"]),
			float(far_section["alpha"])
		) < 0.008:
			continue
		visible_segments.append({
			"near": near_section,
			"far": far_section,
		})

	# ImmediateMesh keeps an empty surface open after surface_end() rejects it.
	# Returning before surface_begin() avoids both the initial error and the
	# cascading "Already creating a new surface" failures on quiet-water frames.
	if visible_segments.is_empty():
		return

	_wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _wake_material)
	for segment in visible_segments:
		var near_section: Dictionary = segment["near"]
		var far_section: Dictionary = segment["far"]

		_add_wake_vertex(near_section["inner"], near_section["color"])
		_add_wake_vertex(near_section["outer"], near_section["color"])
		_add_wake_vertex(far_section["inner"], far_section["color"])
		_add_wake_vertex(near_section["outer"], near_section["color"])
		_add_wake_vertex(far_section["outer"], far_section["color"])
		_add_wake_vertex(far_section["inner"], far_section["color"])
	_wake_mesh.surface_end()


func _wake_section(sample: Dictionary, side: float) -> Dictionary:
	var lifetime: float = sample["lifetime"]
	var age_ratio: float = clampf(sample["age"] / lifetime, 0.0, 1.0)
	var speed_ratio: float = sample["speed_ratio"]
	var right: Vector3 = sample["right"]
	var serial: int = sample["serial"]

	# The broad sine groups foam into short clumps; the stable detail channel
	# roughens their edges. Both are keyed to sample creation, so current
	# advection moves the existing foam without making it shimmer or re-roll.
	# Start both shoulders with a visible patch, then let their independently
	# phased gaps prevent a mirrored railroad-track pattern farther astern.
	var side_phase := 1.37 if side > 0.0 else 0.20
	var broad_noise := 0.5 + 0.5 * sin(float(serial) * 0.71 + side_phase)
	var detail_noise := _stable_noise(serial, side, 17)
	var breakup := smoothstep(0.28, 0.80, broad_noise * 0.72 + detail_noise * 0.28)
	# Hard deterministic gaps are what break the former continuous rail. The
	# neighbouring quad is skipped only when both endpoint sections are gaps.
	if broad_noise * 0.72 + detail_noise * 0.28 < 0.37:
		breakup = 0.0
	var width_noise := _stable_noise(serial, side, 43)
	var lateral_noise := _stable_noise(serial, side, 79) * 2.0 - 1.0

	# A Laser wake begins close to the transom and opens modestly. Both its
	# persistence and divergence grow with through-water energy rather than
	# with ground speed or a fixed nine-second ribbon.
	var near_spread := lerpf(0.18, 0.28, speed_ratio)
	var spread := near_spread + age_ratio * lerpf(0.25, 0.65, speed_ratio)
	var ribbon_width := lerpf(0.025, 0.055, speed_ratio) + age_ratio * lerpf(
		0.035,
		0.080,
		speed_ratio
	)
	ribbon_width *= lerpf(0.42, 1.28, width_noise)
	var ribbon_center: Vector3 = sample["position"] + right * side * spread
	ribbon_center += right * lateral_noise * ribbon_width * 0.72

	var emergence := smoothstep(0.0, 0.10, age_ratio)
	var alpha: float = (
		sample["strength"]
		* emergence
		* pow(1.0 - age_ratio, 1.7)
		* 0.56
		* pow(breakup, 1.35)
	)
	var brightness := lerpf(0.0, 0.08, breakup)
	var color := Color(
		0.78 + brightness,
		0.93 + brightness * 0.55,
		0.98,
		alpha
	)
	var inner_position := ribbon_center - right * ribbon_width
	var outer_position := ribbon_center + right * ribbon_width
	return {
		"inner": _attached_wake_vertex(inner_position),
		"outer": _attached_wake_vertex(outer_position),
		"color": color,
		"alpha": alpha,
	}


func _stable_noise(serial: int, side: float, channel: int) -> float:
	var side_seed := 101 if side > 0.0 else 211
	var phase := float(serial * 37 + side_seed + channel * 131) * 0.01745329252
	return 0.5 + 0.5 * sin(phase * 7.13 + sin(phase * 2.71) * 1.83)


func _attached_wake_vertex(world_position: Vector3) -> Dictionary:
	var surface := sailing_environment.water_surface_at(world_position)
	var attached_position := world_position
	attached_position.y = surface.height + SURFACE_CLEARANCE
	return {
		"position": to_local(attached_position),
		"normal": _world_normal_to_local(surface.normal),
	}


func _add_wake_vertex(vertex_data: Dictionary, color: Color) -> void:
	_wake_mesh.surface_set_color(color)
	_wake_mesh.surface_set_normal(vertex_data["normal"])
	_wake_mesh.surface_add_vertex(vertex_data["position"])


func _surface_height(world_position: Vector3) -> float:
	return (
		sailing_environment.water_surface_at(world_position).height
		+ SURFACE_CLEARANCE
	)


func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))


func _world_normal_to_local(world_normal: Vector3) -> Vector3:
	return (global_basis.transposed() * world_normal).normalized()
