class_name IlcaRigging
extends Node3D

@export var sail_pivot_path: NodePath

const TUBE_SIDES := 12
const ROPE_SAMPLE_SPACING := 0.075
const MIN_SAMPLES_PER_LEG := 3
const MAX_SAMPLES_PER_LEG := 32
const ROPE_UV_REPEAT_LENGTH := 0.12
const ROPE_GEOMETRY_EPSILON_SQUARED := 0.0000000001
const TRAVELLER_BLOCK_CENTER_POSITION := Vector3(0.0, 0.332, 1.46)
const TRAVELLER_BLOCK_MAX_TRAVEL := 0.360
const TRAVELLER_BLOCK_RESPONSE := 9.0
const TRAVELLER_LOOP_JOIN_OFFSET := Vector3(-0.055, 0.006, -0.012)
const TRAVELLER_FREE_END_OFFSET := Vector3(-0.090, 0.018, -0.035)
const SHEAVE_WRAP_SAMPLES := 7

@onready var sail_pivot: Node3D = get_node(sail_pivot_path) as Node3D
@onready var boom_pivot: Node3D = sail_pivot.get_node("BoomPivot") as Node3D
@onready var boat: Node3D = get_parent() as Node3D

var _rigging_mesh: MeshInstance3D
var _last_boom_angle := INF
var _last_boom_pitch := INF
var _last_mainsheet_route := PackedVector3Array()
var _traveller_block: IlcaHardwarePart


func _ready() -> void:
	_traveller_block = boat.get_node("TravellerBlock") as IlcaHardwarePart
	_rigging_mesh = MeshInstance3D.new()
	_rigging_mesh.name = "RunningRiggingMesh"
	add_child(_rigging_mesh)
	_rebuild_rigging()


func _process(delta: float) -> void:
	var traveller_moved := _update_traveller_block(delta)
	if (
		traveller_moved
		or absf(sail_pivot.rotation.y - _last_boom_angle) > deg_to_rad(0.08)
		or absf(boom_pivot.rotation.x - _last_boom_pitch) > deg_to_rad(0.04)
	):
		_rebuild_rigging()


func _update_traveller_block(delta: float) -> bool:
	if not is_instance_valid(_traveller_block):
		return false
	# The linked block is free to run along the taut stern loop.  Boom yaw is a
	# stable visual proxy for the mainsheet's lateral load, while the sine keeps
	# the fitting centred when the boom is centred and eases it into each eye.
	var target_x := clampf(
		sin(sail_pivot.rotation.y) * TRAVELLER_BLOCK_MAX_TRAVEL,
		-TRAVELLER_BLOCK_MAX_TRAVEL,
		TRAVELLER_BLOCK_MAX_TRAVEL
	)
	var previous_position := _traveller_block.position
	var response := 1.0 - exp(-TRAVELLER_BLOCK_RESPONSE * maxf(delta, 0.0))
	_traveller_block.position = Vector3(
		lerpf(_traveller_block.position.x, target_x, response),
		TRAVELLER_BLOCK_CENTER_POSITION.y,
		TRAVELLER_BLOCK_CENTER_POSITION.z
	)
	# Preserve the scene's upright, cross-deck block orientation. The linked
	# hardware itself provides the perpendicular articulation between its small
	# traveller sheave and large mainsheet sheave; yawing the complete assembly
	# would twist the deck line out of the small sheave plane.
	_traveller_block.rotation = Vector3(0.0, 0.0, PI * 0.5)
	return previous_position.distance_squared_to(_traveller_block.position) > 0.00000001


func _rebuild_rigging() -> void:
	_last_boom_angle = sail_pivot.rotation.y
	_last_boom_pitch = boom_pivot.rotation.x
	var rig_mesh := ArrayMesh.new()

	_add_rope_surface(
		rig_mesh,
		[traveller_route_points()],
		0.006,
		Color(0.08, 0.12, 0.16)
	)

	# Rule 3(c) route: aft-block becket -> traveller block -> aft boom
	# sheave -> boom eye strap -> forward boom block -> deck ratchet block.
	# Small lateral offsets expose the two passes through the aft block instead
	# of collapsing them into one low-detail line.
	_last_mainsheet_route = mainsheet_route_points()
	_add_rope_surface(
		rig_mesh,
		[_mainsheet_render_route(_last_mainsheet_route)],
		0.005,
		Color(0.88, 0.82, 0.63)
	)

	_add_rope_surface(rig_mesh, vang_route_points(), 0.003, Color(0.82, 0.24, 0.18))

	# The outhaul runs along the boom, then rises to the clew.  Only this clew
	# connection and the tack hold the loose sail foot to the spar.
	_add_rope_surface(rig_mesh, [outhaul_route_points()], 0.003, Color(0.18, 0.48, 0.92))
	_add_rope_surface(
		rig_mesh,
		[outhaul_control_route_points()],
		0.003,
		Color(0.18, 0.48, 0.92)
	)

	# Cunningham starts at the tack/luff cringle and is led to the control
	# plate.  It is independent of the red vang purchase under the boom.
	_add_rope_surface(
		rig_mesh,
		[cunningham_route_points()],
		0.003,
		Color(0.20, 0.72, 0.42)
	)

	# Class-required centreboard retention shock cord and the hiking-strap
	# support line are conspicuous cockpit details on a fully rigged ILCA.
	_add_rope_surface(
		rig_mesh,
		[centreboard_retention_route_points()],
		0.003,
		Color(0.86, 0.22, 0.16)
	)
	_add_rope_surface(
		rig_mesh,
		[hiking_support_route_points()],
		0.004,
		Color(0.08, 0.10, 0.11)
	)

	_rigging_mesh.mesh = rig_mesh


func _boom_point_in_rigging(local_point: Vector3) -> Vector3:
	return to_local(boom_pivot.to_global(local_point))


func hardware_anchor_in_rigging(
	hardware: IlcaHardwarePart,
	anchor_name: StringName = &"sheave"
) -> Vector3:
	return _hardware_anchor_in_rigging(hardware, anchor_name)


func traveller_route_points() -> PackedVector3Array:
	var port_fairlead := boat.get_node("PortTravellerFairlead") as IlcaHardwarePart
	var traveller := boat.get_node("TravellerBlock") as IlcaHardwarePart
	var starboard_fairlead := boat.get_node("StarboardTravellerFairlead") as IlcaHardwarePart
	var traveller_cleat := boat.get_node_or_null("TravellerCleat") as IlcaHardwarePart
	var port_anchor := _hardware_anchor_in_rigging(port_fairlead, &"bridge")
	var traveller_anchor := _hardware_anchor_in_rigging(traveller, &"traveller_sheave")
	var starboard_anchor := _hardware_anchor_in_rigging(starboard_fairlead, &"bridge")
	# ILCA rule 3(h): one line forms a simple closed loop through both plastic
	# eyes and the small linked traveller sheave.  Start at the eye-splice join
	# on the starboard leg, follow the loop once, revisit that same join, then
	# lead the line's only free end through the clam cleat.
	var loop_join := starboard_anchor + TRAVELLER_LOOP_JOIN_OFFSET
	var points := PackedVector3Array([loop_join, starboard_anchor])
	_append_sheave_wrap(
		points,
		traveller_anchor,
		IlcaHardwarePart.TRAVELLER_LINE_SHEAVE_DIAMETER * 0.5,
		starboard_anchor,
		port_anchor,
		global_basis.inverse() * traveller.global_basis.z
	)
	points.append(port_anchor)
	points.append(loop_join)
	if traveller_cleat:
		var cleat_anchor := _hardware_anchor_in_rigging(traveller_cleat, &"cleat")
		points.append(cleat_anchor)
		points.append(cleat_anchor + TRAVELLER_FREE_END_OFFSET)
	return points


func mainsheet_route_points() -> PackedVector3Array:
	var aft_block := boat.get_node("SailPivot/BoomPivot/AftBoomBlock") as IlcaHardwarePart
	var traveller := boat.get_node("TravellerBlock") as IlcaHardwarePart
	var eye_strap := boat.get_node("SailPivot/BoomPivot/BoomEyeStrap") as IlcaHardwarePart
	var forward_block := boat.get_node("SailPivot/BoomPivot/ForwardBoomBlock") as IlcaHardwarePart
	var deck_ratchet := boat.get_node("RatchetBlock") as IlcaHardwarePart
	var aft_boom_becket := _hardware_anchor_in_rigging(aft_block, &"becket")
	var aft_boom_block := _hardware_anchor_in_rigging(aft_block, &"sheave")
	# Two passes through the aft block use small lateral offsets expressed in
	# this rigging node's coordinate space, never a mixed global basis.
	var aft_axis := (global_basis.inverse() * aft_block.global_basis.x).normalized()
	aft_boom_becket += aft_axis * 0.020
	aft_boom_block -= aft_axis * 0.020
	return PackedVector3Array([
		aft_boom_becket,
		_hardware_anchor_in_rigging(traveller, &"mainsheet_sheave"),
		aft_boom_block,
		_hardware_anchor_in_rigging(eye_strap, &"bridge"),
		_hardware_anchor_in_rigging(forward_block, &"sheave"),
		_hardware_anchor_in_rigging(deck_ratchet, &"sheave"),
	])


func _mainsheet_render_route(anchors: PackedVector3Array) -> PackedVector3Array:
	var route := PackedVector3Array([anchors[0]])
	_append_sheave_wrap(
		route,
		anchors[1],
		IlcaHardwarePart.TRAVELLER_MAIN_SHEAVE_DIAMETER * 0.5,
		anchors[0],
		anchors[2],
		(anchors[2] - anchors[0]).cross(Vector3.UP),
		false
	)
	_append_sheave_wrap(
		route,
		anchors[2],
		0.025,
		route[-1],
		anchors[3],
		global_basis.inverse()
			* boat.get_node("SailPivot/BoomPivot/AftBoomBlock").global_basis.x,
		false
	)
	route.append(anchors[3])
	_append_sheave_wrap(
		route,
		anchors[4],
		0.025,
		route[-1],
		anchors[5],
		global_basis.inverse()
			* boat.get_node("SailPivot/BoomPivot/ForwardBoomBlock").global_basis.x,
		false
	)
	route.append(anchors[5])
	return route


func _append_sheave_wrap(
	route: PackedVector3Array,
	center: Vector3,
	radius: float,
	incoming: Vector3,
	outgoing: Vector3,
	axle_hint := Vector3.ZERO,
	prefer_long_arc := true
) -> void:
	# Project both legs into the sheave plane, derive their contact directions,
	# then sample the loaded visible arc.  This keeps rope on the circumference
	# rather than passing through the axle or cutting across the sheave face.
	var incoming_direction := incoming - center
	var outgoing_direction := outgoing - center
	var axle := axle_hint
	if axle.length_squared() <= ROPE_GEOMETRY_EPSILON_SQUARED:
		axle = incoming_direction.cross(outgoing_direction)
	if axle.length_squared() <= ROPE_GEOMETRY_EPSILON_SQUARED:
		axle = Vector3.RIGHT
	axle = axle.normalized()
	incoming_direction -= axle * incoming_direction.dot(axle)
	outgoing_direction -= axle * outgoing_direction.dot(axle)
	if (
		incoming_direction.length_squared() <= ROPE_GEOMETRY_EPSILON_SQUARED
		or outgoing_direction.length_squared() <= ROPE_GEOMETRY_EPSILON_SQUARED
	):
		route.append(center)
		return
	incoming_direction = incoming_direction.normalized()
	outgoing_direction = outgoing_direction.normalized()
	var signed_angle := atan2(
		axle.dot(incoming_direction.cross(outgoing_direction)),
		clampf(incoming_direction.dot(outgoing_direction), -1.0, 1.0)
	)
	if prefer_long_arc and absf(signed_angle) < PI * 0.5:
		signed_angle -= signf(signed_angle if absf(signed_angle) > 0.001 else 1.0) * TAU
	for sample_index in range(SHEAVE_WRAP_SAMPLES):
		var sample_ratio := float(sample_index) / float(SHEAVE_WRAP_SAMPLES - 1)
		var direction := Basis(axle, signed_angle * sample_ratio) * incoming_direction
		route.append(center + direction * radius)


func vang_route_points() -> Array[PackedVector3Array]:
	var vang_block := boat.get_node("SailPivot/BoomPivot/VangBlock") as IlcaHardwarePart
	var lower_block := boat.get_node("VangLowerBlock") as IlcaHardwarePart
	var vang_top := _hardware_anchor_in_rigging(vang_block, &"sheave")
	var vang_bottom := _hardware_anchor_in_rigging(lower_block, &"sheave")
	var routes: Array[PackedVector3Array] = []
	for lateral_offset in [-0.022, 0.0, 0.022]:
		var purchase_offset := Vector3(float(lateral_offset), 0.0, 0.0)
		routes.append(PackedVector3Array([
			vang_bottom + purchase_offset,
			vang_top + purchase_offset,
		]))
	return routes


func outhaul_route_points() -> PackedVector3Array:
	var clew_strap := boat.get_node("SailPivot/BoomPivot/ClewStrap") as IlcaHardwarePart
	var boom_end := boat.get_node("SailPivot/BoomPivot/BoomEndFitting") as IlcaHardwarePart
	return PackedVector3Array([
		_boom_point_in_rigging(Vector3(0.0, 0.045, 0.24)),
		_hardware_anchor_in_rigging(boom_end, &"sheave"),
		_hardware_anchor_in_rigging(clew_strap, &"bridge"),
	])


func outhaul_control_route_points() -> PackedVector3Array:
	var deck_block := boat.get_node("StarboardDeckBlock") as IlcaHardwarePart
	var cleat := boat.get_node("StarboardControlCleat") as IlcaHardwarePart
	return PackedVector3Array([
		Vector3(0.025, 1.20, -0.78),
		Vector3(0.10, 0.43, -0.75),
		_hardware_anchor_in_rigging(deck_block, &"sheave"),
		_hardware_anchor_in_rigging(cleat, &"cleat"),
		Vector3(0.17, 0.38, -0.36),
	])


func cunningham_route_points() -> PackedVector3Array:
	var deck_block := boat.get_node("PortDeckBlock") as IlcaHardwarePart
	var cleat := boat.get_node("PortControlCleat") as IlcaHardwarePart
	var tack := boat.get_node("SailPivot/TackGrommet") as IlcaHardwarePart
	return PackedVector3Array([
		_hardware_anchor_in_rigging(tack, &"eye"),
		Vector3(-0.04, 0.42, -0.77),
		_hardware_anchor_in_rigging(deck_block, &"sheave"),
		_hardware_anchor_in_rigging(cleat, &"cleat"),
		Vector3(-0.17, 0.38, -0.36),
	])


func centreboard_retention_route_points() -> PackedVector3Array:
	var board_handle := boat.get_node("DaggerboardHandle") as IlcaHardwarePart
	return PackedVector3Array([
		_hardware_anchor_in_rigging(board_handle, &"grip"),
		Vector3(0.18, 0.38, -0.58),
		Vector3(0.03, 0.40, -0.75),
	])


func hiking_support_route_points() -> PackedVector3Array:
	var hiking_strap := boat.get_node("HikingStrap") as IlcaHardwarePart
	var port_eye := boat.get_node("PortHikingStrapEye") as IlcaHardwarePart
	var starboard_eye := boat.get_node("StarboardHikingStrapEye") as IlcaHardwarePart
	var aft_loop := _hardware_anchor_in_rigging(hiking_strap, &"aft_loop")
	# ILCA Rule 17(c) permits one supporting line between the aft strap end and
	# the two aft-cockpit eye straps. Keep it one continuous route rather than
	# rendering two independent ropes, with a short pass through the sewn loop.
	return PackedVector3Array([
		_hardware_anchor_in_rigging(port_eye, &"bridge"),
		aft_loop + Vector3(-0.026, 0.0, 0.0),
		aft_loop + Vector3(0.026, 0.0, 0.0),
		_hardware_anchor_in_rigging(starboard_eye, &"bridge"),
	])


func last_mainsheet_route() -> PackedVector3Array:
	return _last_mainsheet_route.duplicate()


func _hardware_anchor_in_rigging(
	hardware: IlcaHardwarePart,
	anchor_name: StringName = &"sheave"
) -> Vector3:
	return to_local(hardware.rope_anchor_global(anchor_name))


func _add_rope_surface(
	target_mesh: ArrayMesh,
	polylines: Array[PackedVector3Array],
	radius: float,
	color: Color
) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_geometry := false
	for points in polylines:
		var smooth_points := _resample_rope_path(points)
		if smooth_points.size() < 2:
			continue
		_add_swept_tube(surface, smooth_points, radius)
		has_geometry = true
	if not has_geometry:
		return
	# Explicit per-vertex normals keep adjacent rings visually continuous. Keep
	# this surface non-indexed: cap vertices intentionally share positions with
	# the side wall while carrying different normals and UVs.
	surface.commit(target_mesh)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	target_mesh.surface_set_material(target_mesh.get_surface_count() - 1, material)


func _resample_rope_path(control_points: PackedVector3Array) -> PackedVector3Array:
	# Cubic Hermite interpolation keeps every hardware anchor exact while sharing
	# a tangent at either side of it.  This rounds the visible rope path without
	# changing the public route functions used by rigging and physics tests.
	var points := PackedVector3Array()
	for point in control_points:
		if (
			points.is_empty()
			or points[-1].distance_squared_to(point) > ROPE_GEOMETRY_EPSILON_SQUARED
		):
			points.append(point)
	if points.size() < 2:
		return points

	var control_tangents := PackedVector3Array()
	for index in range(points.size()):
		var tangent: Vector3
		if index == 0:
			tangent = points[1] - points[0]
		elif index == points.size() - 1:
			tangent = points[-1] - points[-2]
		else:
			var incoming := points[index] - points[index - 1]
			var outgoing := points[index + 1] - points[index]
			tangent = (points[index + 1] - points[index - 1]) * 0.5
			# Short legs around compact deck fittings must not produce a spline
			# overshoot that leaves the fitting completely behind the rope.
			var maximum_tangent_length := minf(incoming.length(), outgoing.length())
			if tangent.length() > maximum_tangent_length:
				tangent = tangent.normalized() * maximum_tangent_length
		control_tangents.append(tangent)

	var result := PackedVector3Array([points[0]])
	for segment_index in range(points.size() - 1):
		var start := points[segment_index]
		var finish := points[segment_index + 1]
		var leg_length := start.distance_to(finish)
		var subdivisions := clampi(
			ceili(leg_length / ROPE_SAMPLE_SPACING),
			MIN_SAMPLES_PER_LEG,
			MAX_SAMPLES_PER_LEG
		)
		for sample_index in range(1, subdivisions + 1):
			var t := float(sample_index) / float(subdivisions)
			var t_squared := t * t
			var t_cubed := t_squared * t
			var point := (
				start * (2.0 * t_cubed - 3.0 * t_squared + 1.0)
				+ control_tangents[segment_index]
					* (t_cubed - 2.0 * t_squared + t)
				+ finish * (-2.0 * t_cubed + 3.0 * t_squared)
				+ control_tangents[segment_index + 1] * (t_cubed - t_squared)
			)
			if result[-1].distance_squared_to(point) > ROPE_GEOMETRY_EPSILON_SQUARED:
				result.append(point)
	# Avoid accumulated interpolation error at the two externally visible ends.
	result[0] = points[0]
	result[-1] = points[-1]
	return result


func _add_swept_tube(
	surface: SurfaceTool,
	points: PackedVector3Array,
	radius: float
) -> void:
	var tangents := _rope_tangents(points)
	var normals := PackedVector3Array()
	var binormals := PackedVector3Array()
	var cumulative_lengths := PackedFloat32Array([0.0])

	var normal := _initial_rope_normal(tangents[0])
	for index in range(points.size()):
		if index > 0:
			normal = _transport_rope_normal(tangents[index - 1], tangents[index], normal)
		var binormal := tangents[index].cross(normal).normalized()
		# Re-orthogonalise after transport so numerical drift cannot twist or
		# collapse a ring on a long, multi-corner mainsheet route.
		normal = binormal.cross(tangents[index]).normalized()
		normals.append(normal)
		binormals.append(binormal)
		if index > 0:
			cumulative_lengths.append(
				cumulative_lengths[-1] + points[index - 1].distance_to(points[index])
			)

	for path_index in range(points.size() - 1):
		var start_v := cumulative_lengths[path_index] / ROPE_UV_REPEAT_LENGTH
		var finish_v := cumulative_lengths[path_index + 1] / ROPE_UV_REPEAT_LENGTH
		for side_index in range(TUBE_SIDES):
			var next_side := side_index + 1
			var start_direction := _rope_ring_direction(
				normals[path_index], binormals[path_index], side_index
			)
			var start_next_direction := _rope_ring_direction(
				normals[path_index], binormals[path_index], next_side
			)
			var finish_direction := _rope_ring_direction(
				normals[path_index + 1], binormals[path_index + 1], side_index
			)
			var finish_next_direction := _rope_ring_direction(
				normals[path_index + 1], binormals[path_index + 1], next_side
			)
			var start_u := float(side_index) / float(TUBE_SIDES)
			var next_u := float(next_side) / float(TUBE_SIDES)
			_add_rope_triangle(
				surface,
				points[path_index] + start_direction * radius,
				start_direction,
				Vector2(start_u, start_v),
				points[path_index] + start_next_direction * radius,
				start_next_direction,
				Vector2(next_u, start_v),
				points[path_index + 1] + finish_next_direction * radius,
				finish_next_direction,
				Vector2(next_u, finish_v)
			)
			_add_rope_triangle(
				surface,
				points[path_index] + start_direction * radius,
				start_direction,
				Vector2(start_u, start_v),
				points[path_index + 1] + finish_next_direction * radius,
				finish_next_direction,
				Vector2(next_u, finish_v),
				points[path_index + 1] + finish_direction * radius,
				finish_direction,
				Vector2(start_u, finish_v)
			)

	_add_rope_cap(
		surface,
		points[0],
		-tangents[0],
		normals[0],
		binormals[0],
		radius,
		true
	)
	_add_rope_cap(
		surface,
		points[-1],
		tangents[-1],
		normals[-1],
		binormals[-1],
		radius,
		false
	)


func _rope_tangents(points: PackedVector3Array) -> PackedVector3Array:
	var tangents := PackedVector3Array()
	for index in range(points.size()):
		var tangent: Vector3
		if index == 0:
			tangent = points[1] - points[0]
		elif index == points.size() - 1:
			tangent = points[-1] - points[-2]
		else:
			tangent = points[index + 1] - points[index - 1]
		if tangent.length_squared() <= ROPE_GEOMETRY_EPSILON_SQUARED:
			tangent = tangents[-1] if not tangents.is_empty() else Vector3.FORWARD
		else:
			tangent = tangent.normalized()
		tangents.append(tangent)
	return tangents


func _initial_rope_normal(tangent: Vector3) -> Vector3:
	var reference := Vector3.UP
	if absf(tangent.dot(reference)) > 0.92:
		reference = Vector3.RIGHT
	return (reference - tangent * tangent.dot(reference)).normalized()


func _transport_rope_normal(
	previous_tangent: Vector3,
	tangent: Vector3,
	previous_normal: Vector3
) -> Vector3:
	var axis := previous_tangent.cross(tangent)
	var alignment := clampf(previous_tangent.dot(tangent), -1.0, 1.0)
	var transported := previous_normal
	if axis.length_squared() > ROPE_GEOMETRY_EPSILON_SQUARED:
		var angle := atan2(axis.length(), alignment)
		transported = Basis(Quaternion(axis.normalized(), angle)) * previous_normal
	elif alignment < 0.0:
		# A mathematically exact reversal has no unique transport axis.  Pick the
		# existing ring normal, which keeps the tube finite and visually stable.
		transported = previous_normal
	transported -= tangent * transported.dot(tangent)
	if transported.length_squared() <= ROPE_GEOMETRY_EPSILON_SQUARED:
		return _initial_rope_normal(tangent)
	return transported.normalized()


func _rope_ring_direction(normal: Vector3, binormal: Vector3, side_index: int) -> Vector3:
	var angle := TAU * float(side_index) / float(TUBE_SIDES)
	return (normal * cos(angle) + binormal * sin(angle)).normalized()


func _add_rope_cap(
	surface: SurfaceTool,
	center: Vector3,
	cap_normal: Vector3,
	ring_normal: Vector3,
	ring_binormal: Vector3,
	radius: float,
	is_start: bool
) -> void:
	for side_index in range(TUBE_SIDES):
		var next_side := side_index + 1
		var current_direction := _rope_ring_direction(ring_normal, ring_binormal, side_index)
		var next_direction := _rope_ring_direction(ring_normal, ring_binormal, next_side)
		var current_uv := Vector2(
			0.5 + current_direction.dot(ring_normal) * 0.5,
			0.5 + current_direction.dot(ring_binormal) * 0.5
		)
		var next_uv := Vector2(
			0.5 + next_direction.dot(ring_normal) * 0.5,
			0.5 + next_direction.dot(ring_binormal) * 0.5
		)
		if is_start:
			_add_rope_triangle(
				surface,
				center,
				cap_normal,
				Vector2(0.5, 0.5),
				center + next_direction * radius,
				cap_normal,
				next_uv,
				center + current_direction * radius,
				cap_normal,
				current_uv
			)
		else:
			_add_rope_triangle(
				surface,
				center,
				cap_normal,
				Vector2(0.5, 0.5),
				center + current_direction * radius,
				cap_normal,
				current_uv,
				center + next_direction * radius,
				cap_normal,
				next_uv
			)


func _add_rope_triangle(
	surface: SurfaceTool,
	a: Vector3,
	a_normal: Vector3,
	a_uv: Vector2,
	b: Vector3,
	b_normal: Vector3,
	b_uv: Vector2,
	c: Vector3,
	c_normal: Vector3,
	c_uv: Vector2
) -> void:
	surface.set_normal(a_normal)
	surface.set_uv(a_uv)
	surface.add_vertex(a)
	surface.set_normal(b_normal)
	surface.set_uv(b_uv)
	surface.add_vertex(b)
	surface.set_normal(c_normal)
	surface.set_uv(c_uv)
	surface.add_vertex(c)


func _add_tube_segment(surface: SurfaceTool, from: Vector3, to: Vector3, radius: float) -> void:
	# Retained for compatibility with any local diagnostic scripts. New runtime
	# rendering adds one swept tube per complete route instead of per leg.
	if from.distance_squared_to(to) <= ROPE_GEOMETRY_EPSILON_SQUARED:
		return
	_add_swept_tube(surface, PackedVector3Array([from, to]), radius)
