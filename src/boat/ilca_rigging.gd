class_name IlcaRigging
extends Node3D

@export var sail_pivot_path: NodePath

const TUBE_SIDES := 12

@onready var sail_pivot: Node3D = get_node(sail_pivot_path) as Node3D
@onready var boom_pivot: Node3D = sail_pivot.get_node("BoomPivot") as Node3D
@onready var boat: Node3D = get_parent() as Node3D

var _rigging_mesh: MeshInstance3D
var _last_boom_angle := INF
var _last_boom_pitch := INF
var _last_mainsheet_route := PackedVector3Array()


func _ready() -> void:
	_rigging_mesh = MeshInstance3D.new()
	_rigging_mesh.name = "RunningRiggingMesh"
	add_child(_rigging_mesh)
	_rebuild_rigging()


func _process(_delta: float) -> void:
	if (
		absf(sail_pivot.rotation.y - _last_boom_angle) > deg_to_rad(0.35)
		or absf(boom_pivot.rotation.x - _last_boom_pitch) > deg_to_rad(0.1)
	):
		_rebuild_rigging()


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
	_add_rope_surface(rig_mesh, [_last_mainsheet_route], 0.005, Color(0.88, 0.82, 0.63))

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
		hiking_support_route_points(),
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
	return PackedVector3Array([
		_hardware_anchor_in_rigging(port_fairlead, &"bridge"),
		_hardware_anchor_in_rigging(traveller, &"traveller_sheave"),
		_hardware_anchor_in_rigging(starboard_fairlead, &"bridge"),
	])


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


func vang_route_points() -> Array[PackedVector3Array]:
	var vang_block := boat.get_node("SailPivot/BoomPivot/VangBlock") as IlcaHardwarePart
	var vang_top := _hardware_anchor_in_rigging(vang_block, &"sheave")
	var routes: Array[PackedVector3Array] = []
	for lateral_offset in [-0.022, 0.0, 0.022]:
		routes.append(PackedVector3Array([
			Vector3(float(lateral_offset), 0.39, -0.78),
			vang_top,
		]))
	return routes


func outhaul_route_points() -> PackedVector3Array:
	var clew_grommet := boat.get_node("SailPivot/ClewGrommet") as IlcaHardwarePart
	return PackedVector3Array([
		_boom_point_in_rigging(Vector3(0.0, 0.045, 0.24)),
		_boom_point_in_rigging(Vector3(0.0, 0.045, 2.62)),
		_hardware_anchor_in_rigging(clew_grommet, &"bridge"),
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
	return PackedVector3Array([
		Vector3(0.0, 1.30, -0.79),
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


func hiking_support_route_points() -> Array[PackedVector3Array]:
	var port_eye := boat.get_node("PortHikingStrapEye") as IlcaHardwarePart
	var starboard_eye := boat.get_node("StarboardHikingStrapEye") as IlcaHardwarePart
	return [
		PackedVector3Array([
			Vector3(0.0, 0.095, 1.32),
			_hardware_anchor_in_rigging(port_eye, &"bridge"),
		]),
		PackedVector3Array([
			Vector3(0.0, 0.095, 1.32),
			_hardware_anchor_in_rigging(starboard_eye, &"bridge"),
		]),
	]


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
	for points in polylines:
		for index in range(points.size() - 1):
			_add_tube_segment(surface, points[index], points[index + 1], radius)
	surface.index()
	surface.generate_normals()
	surface.commit(target_mesh)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	target_mesh.surface_set_material(target_mesh.get_surface_count() - 1, material)


func _add_tube_segment(surface: SurfaceTool, from: Vector3, to: Vector3, radius: float) -> void:
	var direction := (to - from).normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(direction).normalized()
	for side_index in range(TUBE_SIDES):
		var next_side := (side_index + 1) % TUBE_SIDES
		var angle := TAU * float(side_index) / float(TUBE_SIDES)
		var next_angle := TAU * float(next_side) / float(TUBE_SIDES)
		var offset := (side * cos(angle) + up * sin(angle)) * radius
		var next_offset := (side * cos(next_angle) + up * sin(next_angle)) * radius
		_add_quad(surface, from + offset, from + next_offset, to + next_offset, to + offset)


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)
