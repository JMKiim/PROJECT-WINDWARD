class_name IlcaFoil
extends MeshInstance3D

enum FoilKind {
	CENTREBOARD,
	RUDDER,
}

@export var foil_kind: FoilKind = FoilKind.CENTREBOARD
@export_range(0.1, 2.0, 0.01) var span := 0.95
@export_range(0.1, 1.0, 0.001) var root_chord := 0.38
@export_range(0.03, 1.0, 0.001) var tip_chord := 0.25
@export_range(0.004, 0.08, 0.001) var maximum_thickness := 0.033
@export_range(-0.5, 0.5, 0.001) var aft_sweep := 0.07

# The public measurement drawing does not define the scene's origin at the
# centreboard stopper or the rudder bolt.  Its dimensions are therefore used
# as normalized silhouette landmarks rather than forcing span to 680/635 mm.
const CENTREBOARD_CORNER_RADIUS_RATIO := 60.0 / 680.0
const RUDDER_STRAIGHT_TRAILING_EDGE_RATIO := 527.0 / 635.0
const RUDDER_CORNER_RADIUS_RATIO := 60.0 / 635.0

const CENTREBOARD_MAXIMUM_THICKNESS := 0.033
const RUDDER_MAXIMUM_THICKNESS := 0.020
const PROFILE_SEGMENTS := 24
const SPAN_STATIONS := 25
const NACA_UNIT_HALF_THICKNESS_MAX := 0.50005926


func _ready() -> void:
	# Existing scenes used deliberately exaggerated values for the old generic
	# fin.  Clamp them at runtime so an older scene cannot create a board too
	# thick for its case or a rudder too thick for its head.
	maximum_thickness = clampf(
		maximum_thickness,
		0.004,
		_maximum_allowed_thickness()
	)
	mesh = _build_foil_mesh()


func effective_maximum_thickness() -> float:
	return minf(maximum_thickness, _maximum_allowed_thickness())


func _maximum_allowed_thickness() -> float:
	return (
		RUDDER_MAXIMUM_THICKNESS
		if foil_kind == FoilKind.RUDDER
		else CENTREBOARD_MAXIMUM_THICKNESS
	)


func _build_foil_mesh() -> ArrayMesh:
	var foil_mesh := ArrayMesh.new()
	var rings: Array[PackedVector3Array] = []
	for station_index in range(SPAN_STATIONS):
		var span_ratio := float(station_index) / float(SPAN_STATIONS - 1)
		rings.append(_airfoil_ring(span_ratio))

	# The foil body is one indexed smoothing island.  Root and tip are committed
	# as a second surface so their normals stay flat instead of rounding over the
	# perimeter and producing the inflated-plastic look of the old mesh.
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	body.set_smooth_group(0)
	for station_index in range(rings.size() - 1):
		var upper_ring := rings[station_index]
		var lower_ring := rings[station_index + 1]
		for profile_index in range(upper_ring.size()):
			var next_profile := (profile_index + 1) % upper_ring.size()
			_add_quad(
				body,
				upper_ring[profile_index],
				upper_ring[next_profile],
				lower_ring[next_profile],
				lower_ring[profile_index]
			)
	body.index()
	body.generate_normals()
	body.commit(foil_mesh)
	foil_mesh.surface_set_material(0, _make_material(Color(0.945, 0.952, 0.935), 0.34))

	var caps := SurfaceTool.new()
	caps.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_cap(caps, rings.front(), true)
	_add_cap(caps, rings.back(), false)
	caps.index()
	caps.commit(foil_mesh)
	foil_mesh.surface_set_material(1, _make_material(Color(0.925, 0.932, 0.915), 0.39))
	return foil_mesh


func _airfoil_ring(span_ratio: float) -> PackedVector3Array:
	var outline := _side_outline(span_ratio)
	var leading_edge := outline.x
	var trailing_edge := outline.y
	var chord := maxf(trailing_edge - leading_edge, 0.02)
	var vertical_position := span * (0.5 - span_ratio)
	var span_thickness := _span_thickness_factor(span_ratio)
	var ring := PackedVector3Array()

	# A symmetric closed-trailing-edge NACA 00xx distribution.  Thickness is
	# absolute, not a chord percentage, because the class drawing specifies a
	# maximum thickness for each foil.
	for profile_index in range(PROFILE_SEGMENTS + 1):
		var chord_ratio := float(profile_index) / float(PROFILE_SEGMENTS)
		ring.append(_profile_point(
			chord_ratio,
			1.0,
			leading_edge,
			chord,
			vertical_position,
			span_thickness
		))
	for profile_index in range(PROFILE_SEGMENTS - 1, 0, -1):
		var chord_ratio := float(profile_index) / float(PROFILE_SEGMENTS)
		ring.append(_profile_point(
			chord_ratio,
			-1.0,
			leading_edge,
			chord,
			vertical_position,
			span_thickness
		))
	return ring


func _side_outline(span_ratio: float) -> Vector2:
	var ratio := clampf(span_ratio, 0.0, 1.0)
	var safe_root_chord := maxf(root_chord, 0.10)
	var safe_tip_chord := clampf(tip_chord, 0.03, safe_root_chord)
	if foil_kind == FoilKind.RUDDER:
		return _rudder_outline(ratio, safe_root_chord, safe_tip_chord)
	return _centreboard_outline(ratio, safe_root_chord, safe_tip_chord)


func _centreboard_outline(
	span_ratio: float,
	board_chord: float,
	bottom_chord: float
) -> Vector2:
	# Nearly parallel working edges end in the measurement drawing's rounded
	# lower corners.  A smoothstep approximates the moulded R60 transition while
	# retaining a finite bottom edge for a closed, non-degenerate cap.
	var round_start := 1.0 - CENTREBOARD_CORNER_RADIUS_RATIO
	var round_amount := smoothstep(round_start, 1.0, span_ratio)
	var chord := lerpf(board_chord, bottom_chord, round_amount)
	var center := aft_sweep * pow(span_ratio, 1.35)
	return Vector2(center - chord * 0.5, center + chord * 0.5)


func _rudder_outline(
	span_ratio: float,
	blade_chord: float,
	bottom_chord: float
) -> Vector2:
	# The rudder has a relieved leading shoulder inside the head, then a long
	# straight trailing edge before the lower R60 region.  This is deliberately
	# different from the rectangular centreboard silhouette.
	var shoulder_amount := 1.0 - smoothstep(0.0, 0.18, span_ratio)
	var round_start := minf(
		RUDDER_STRAIGHT_TRAILING_EDGE_RATIO,
		1.0 - RUDDER_CORNER_RADIUS_RATIO
	)
	var round_amount := smoothstep(round_start, 1.0, span_ratio)
	var chord := lerpf(blade_chord, bottom_chord, round_amount)
	var center := aft_sweep * span_ratio
	var leading_edge := center - chord * 0.5 + blade_chord * 0.10 * shoulder_amount
	var trailing_edge := center + chord * 0.5
	return Vector2(leading_edge, trailing_edge)


func _profile_point(
	chord_ratio: float,
	side: float,
	leading_edge: float,
	chord: float,
	vertical_position: float,
	span_thickness: float
) -> Vector3:
	var half_thickness := (
		effective_maximum_thickness()
		* _naca_half_thickness_shape(chord_ratio)
		* span_thickness
	)
	return Vector3(
		half_thickness * side,
		vertical_position,
		leading_edge + chord_ratio * chord
	)


func _naca_half_thickness_shape(chord_ratio: float) -> float:
	var ratio := clampf(chord_ratio, 0.0, 1.0)
	if is_zero_approx(ratio) or is_equal_approx(ratio, 1.0):
		return 0.0
	# The -0.1036 term closes the trailing edge.  Normalize the sampled unit
	# NACA curve to an exact 0.5 maximum so the requested total thickness remains
	# a strict upper bound rather than exceeding the class limit by rounding.
	var raw_half_shape := maxf(
		0.0,
		5.0 * (
			0.2969 * sqrt(ratio)
			- 0.1260 * ratio
			- 0.3516 * pow(ratio, 2.0)
			+ 0.2843 * pow(ratio, 3.0)
			- 0.1036 * pow(ratio, 4.0)
		)
	)
	return raw_half_shape * 0.5 / NACA_UNIT_HALF_THICKNESS_MAX


func _span_thickness_factor(span_ratio: float) -> float:
	# Keep both end rings finite for valid flat caps while softening the moulded
	# perimeter.  The maximum-thickness contract is reached through the working
	# middle of the blade.
	var root_blend := smoothstep(0.0, 0.08, span_ratio)
	var root_factor := lerpf(0.82, 1.0, root_blend)
	var tip_start := (
		RUDDER_STRAIGHT_TRAILING_EDGE_RATIO
		if foil_kind == FoilKind.RUDDER
		else 1.0 - CENTREBOARD_CORNER_RADIUS_RATIO
	)
	var tip_blend := smoothstep(tip_start, 1.0, span_ratio)
	var tip_factor := lerpf(1.0, 0.58, tip_blend)
	return minf(root_factor, tip_factor)


func _add_cap(surface: SurfaceTool, ring: PackedVector3Array, upper: bool) -> void:
	var center := Vector3.ZERO
	for point in ring:
		center += point
	center /= float(ring.size())
	var normal := Vector3.UP if upper else Vector3.DOWN
	for index in range(ring.size()):
		var next_index := (index + 1) % ring.size()
		if upper:
			_add_triangle_with_normal(surface, center, ring[next_index], ring[index], normal)
		else:
			_add_triangle_with_normal(surface, center, ring[index], ring[next_index], normal)


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(surface, a, b, c)
	_add_triangle(surface, a, c, d)


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _add_triangle_with_normal(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3
) -> void:
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.add_vertex(c)


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
