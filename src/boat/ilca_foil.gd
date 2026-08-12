class_name IlcaFoil
extends MeshInstance3D

@export_range(0.1, 2.0, 0.01) var span := 0.95
@export_range(0.1, 1.0, 0.01) var root_chord := 0.38
@export_range(0.1, 1.0, 0.01) var tip_chord := 0.25
@export_range(0.01, 0.2, 0.005) var maximum_thickness := 0.06
@export_range(-0.5, 0.5, 0.01) var aft_sweep := 0.07

const PROFILE_SEGMENTS := 12
const SPAN_STATIONS := 7
const EDGE_TUBE_SIDES := 7


func _ready() -> void:
	mesh = _build_foil_mesh()


func _build_foil_mesh() -> ArrayMesh:
	var foil_mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for station_index in range(SPAN_STATIONS):
		var ratio := float(station_index) / float(SPAN_STATIONS - 1)
		rings.append(_airfoil_ring(ratio))

	for station_index in range(rings.size() - 1):
		var upper_ring := rings[station_index]
		var lower_ring := rings[station_index + 1]
		for profile_index in range(upper_ring.size()):
			var next_profile := (profile_index + 1) % upper_ring.size()
			_add_quad(
				surface,
				upper_ring[profile_index],
				upper_ring[next_profile],
				lower_ring[next_profile],
				lower_ring[profile_index]
			)

	_add_cap(surface, rings.front(), true)
	_add_cap(surface, rings.back(), false)
	surface.index()
	surface.generate_normals()
	surface.commit(foil_mesh)
	foil_mesh.surface_set_material(0, _make_material(Color(0.91, 0.925, 0.9), 0.42))

	var trailing_edge := SurfaceTool.new()
	trailing_edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	for station_index in range(SPAN_STATIONS - 1):
		var upper_ratio := float(station_index) / float(SPAN_STATIONS - 1)
		var lower_ratio := float(station_index + 1) / float(SPAN_STATIONS - 1)
		_add_tube_segment(
			trailing_edge,
			_trailing_edge_point(upper_ratio),
			_trailing_edge_point(lower_ratio),
			0.008
		)
	trailing_edge.index()
	trailing_edge.generate_normals()
	trailing_edge.commit(foil_mesh)
	foil_mesh.surface_set_material(1, _make_material(Color(0.035, 0.045, 0.05), 0.5))
	return foil_mesh


func _airfoil_ring(span_ratio: float) -> PackedVector3Array:
	var chord := lerpf(root_chord, tip_chord, smoothstep(0.0, 1.0, span_ratio))
	var vertical_position := span * (0.5 - span_ratio)
	var chord_center := aft_sweep * span_ratio
	var ring := PackedVector3Array()
	for profile_index in range(PROFILE_SEGMENTS + 1):
		var chord_ratio := float(profile_index) / float(PROFILE_SEGMENTS)
		ring.append(_profile_point(chord_ratio, 1.0, chord, chord_center, vertical_position, span_ratio))
	for profile_index in range(PROFILE_SEGMENTS - 1, 0, -1):
		var chord_ratio := float(profile_index) / float(PROFILE_SEGMENTS)
		ring.append(_profile_point(chord_ratio, -1.0, chord, chord_center, vertical_position, span_ratio))
	return ring


func _profile_point(
	chord_ratio: float,
	side: float,
	chord: float,
	chord_center: float,
	vertical_position: float,
	span_ratio: float
) -> Vector3:
	var edge_taper := sin(chord_ratio * PI)
	var tip_taper := sqrt(maxf(0.0, 1.0 - pow(span_ratio, 6.0)))
	var half_thickness := maximum_thickness * 0.5 * edge_taper * tip_taper
	return Vector3(
		half_thickness * side,
		vertical_position,
		chord_center + (chord_ratio - 0.5) * chord
	)


func _trailing_edge_point(span_ratio: float) -> Vector3:
	var chord := lerpf(root_chord, tip_chord, smoothstep(0.0, 1.0, span_ratio))
	return Vector3(
		0.0,
		span * (0.5 - span_ratio),
		aft_sweep * span_ratio + chord * 0.5
	)


func _add_cap(surface: SurfaceTool, ring: PackedVector3Array, upper: bool) -> void:
	var center := Vector3.ZERO
	for point in ring:
		center += point
	center /= float(ring.size())
	for index in range(ring.size()):
		var next_index := (index + 1) % ring.size()
		if upper:
			_add_triangle(surface, center, ring[next_index], ring[index])
		else:
			_add_triangle(surface, center, ring[index], ring[next_index])


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(surface, a, b, c)
	_add_triangle(surface, a, c, d)


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _add_tube_segment(surface: SurfaceTool, from: Vector3, to: Vector3, radius: float) -> void:
	var direction := (to - from).normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(direction).normalized()
	for side_index in range(EDGE_TUBE_SIDES):
		var next_side := (side_index + 1) % EDGE_TUBE_SIDES
		var angle := TAU * float(side_index) / float(EDGE_TUBE_SIDES)
		var next_angle := TAU * float(next_side) / float(EDGE_TUBE_SIDES)
		var offset := (side * cos(angle) + up * sin(angle)) * radius
		var next_offset := (side * cos(next_angle) + up * sin(next_angle)) * radius
		_add_quad(surface, from + offset, from + next_offset, to + next_offset, to + offset)


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
