class_name IlcaSevenSail
extends MeshInstance3D

const LUFF_LENGTH_METERS := 5.12
const FOOT_LENGTH_METERS := 2.75
const LEECH_LENGTH_METERS := 5.555
const BOOM_CENTER_HEIGHT_METERS := 1.21
const TACK_HEIGHT_METERS := 1.27
# The class-rule lengths above are measured along finished sail edges.  They
# must not also be used as Cartesian mast/chord projections: doing that made
# the old procedural leech about 5.78 m long.  These smaller construction
# spans leave room for the shaped foot while keeping every default edge inside
# the official ILCA 7 MKII maxima.
const LUFF_SPAN_METERS := 5.105
const FOOT_PROJECTION_METERS := 2.70
const CLEW_RISE_METERS := 0.30
const FOOT_ROACH_METERS := 0.11
const LEECH_ROACH_METERS := 0.035
const DEFAULT_CLEW_TARGET_LOCAL := Vector3(
	0.0,
	TACK_HEIGHT_METERS + CLEW_RISE_METERS,
	FOOT_PROJECTION_METERS
)
const ROWS := 48
const COLUMNS := 36
const LOWER_RADIAL_LUFF_HEIGHTS := [0.12, 0.23, 0.34, 0.47]
# Parametric coordinates always use Vector2(height_ratio, chord_ratio). They
# are deliberately not mesh UVs, whose axes are (chord, 1 - height).
const UPPER_RADIAL_ORIGIN_HC := Vector2(0.47, 0.20)
const UPPER_RADIAL_ENDS_HC := [
	Vector2(1.0, 0.0),
	Vector2(0.95, 0.34),
	Vector2(0.88, 0.62),
	Vector2(0.74, 1.0),
]
const CROSS_SEAMS_HEIGHT_CURVE := [Vector2(0.47, 0.035), Vector2(0.86, 0.025)]
const BATTEN_ANCHORS_HC := [Vector2(0.27, 0.63), Vector2(0.53, 0.55), Vector2(0.76, 0.42)]
# Stable semantic surface anchors for the later cloth solver. Telltales remain
# paired per sail side and will sample local airflow at these same HC points.
const TELLTALE_ANCHORS_HC := [Vector2(0.31, 0.20), Vector2(0.50, 0.20), Vector2(0.69, 0.20)]

@export_range(0.0, 1.0, 0.01) var outhaul_tension := 0.62
@export_range(0.0, 1.0, 0.01) var cunningham_tension := 0.55

var _last_outhaul_tension := INF
var _last_cunningham_tension := INF
var _clew_target_local := DEFAULT_CLEW_TARGET_LOCAL
var _geometry_dirty := false
var _surface_attachments: Array[Dictionary] = []


func _ready() -> void:
	mesh = _build_sail_mesh()
	_build_luff_sleeve()
	_register_surface_attachment("../ClassMark", Vector2(0.62, 0.49), -1.0)
	_register_surface_attachment("../ClassMarkStarboard", Vector2(0.62, 0.49), 1.0)
	_register_surface_attachment("../AuthorizedSailButton", Vector2(0.032, 0.035), -1.0)
	_register_surface_attachment("../AuthorizedSailButtonStarboard", Vector2(0.032, 0.035), 1.0)
	_update_surface_attachments()
	_last_outhaul_tension = outhaul_tension
	_last_cunningham_tension = cunningham_tension


func _process(_delta: float) -> void:
	if (
		_geometry_dirty
		or
		absf(outhaul_tension - _last_outhaul_tension) > 0.005
		or absf(cunningham_tension - _last_cunningham_tension) > 0.005
	):
		mesh = _build_sail_mesh()
		_last_outhaul_tension = outhaul_tension
		_last_cunningham_tension = cunningham_tension
		_geometry_dirty = false
		_update_surface_attachments()


func set_clew_target_local(target: Vector3) -> void:
	# The controller/rig pass can provide the actual boom/clew-strap anchor
	# without rotating the entire mast-sleeved sail as a rigid boom assembly.
	# The luff remains fixed; the Coons-style surface below distributes the new
	# clew into the foot and leech boundaries.
	if not target.is_finite() or target.distance_squared_to(_clew_target_local) < 0.00000001:
		return
	_clew_target_local = target
	_geometry_dirty = true


func clew_target_local() -> Vector3:
	return _clew_target_local


func _register_surface_attachment(path: NodePath, hc: Vector2, side: float) -> void:
	var attachment := get_node_or_null(path) as Node3D
	if attachment:
		_surface_attachments.append({"node": attachment, "hc": hc, "side": side})


func _update_surface_attachments() -> void:
	# Marks and the MKII button are semantic HC anchors, so future camber/twist
	# moves them with the cloth instead of leaving no-depth-test sprites floating.
	for attachment_data in _surface_attachments:
		var attachment := attachment_data["node"] as Node3D
		var hc := attachment_data["hc"] as Vector2
		var side := float(attachment_data["side"])
		var point := sail_surface_point(hc)
		var tangent_height := _sail_tangent_height(hc)
		var tangent_chord := _sail_tangent_chord(hc)
		var normal := tangent_height.cross(tangent_chord).normalized() * side
		attachment.position = point + normal * 0.004
		var up_axis := tangent_height
		var forward_axis := normal
		var right_axis := up_axis.cross(forward_axis).normalized()
		attachment.basis = Basis(right_axis, up_axis, forward_axis)


func _sail_tangent_height(hc: Vector2) -> Vector3:
	var epsilon := 0.002
	return (
		sail_surface_point(Vector2(minf(1.0, hc.x + epsilon), hc.y))
		- sail_surface_point(Vector2(maxf(0.0, hc.x - epsilon), hc.y))
	).normalized()


func _sail_tangent_chord(hc: Vector2) -> Vector3:
	var epsilon := 0.002
	return (
		sail_surface_point(Vector2(hc.x, minf(1.0, hc.y + epsilon)))
		- sail_surface_point(Vector2(hc.x, maxf(0.0, hc.y - epsilon)))
	).normalized()


func _sail_normal(hc: Vector2) -> Vector3:
	return _sail_tangent_height(hc).cross(_sail_tangent_chord(hc)).normalized()


func _build_sail_mesh() -> ArrayMesh:
	var sail_mesh := ArrayMesh.new()
	var cloth := SurfaceTool.new()
	var window := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	window.begin(Mesh.PRIMITIVE_TRIANGLES)
	var surface_grid := _build_surface_grid()

	for row in range(ROWS):
		for column in range(COLUMNS):
			_add_sail_grid_cell(cloth, surface_grid, row, column)

	# The transparent film uses its exact analytic HC boundary. It overlays the
	# cloth visually for now, which removes the old 10 cm stair steps without
	# giving up a canonical cloth lattice for the later panel/cloth solver.
	_add_window_film(window)

	cloth.index()
	cloth.generate_normals()
	cloth.commit(sail_mesh)
	sail_mesh.surface_set_material(0, _make_cloth_material())
	window.index()
	window.generate_normals()
	window.commit(sail_mesh)
	sail_mesh.surface_set_material(1, _make_window_material())

	var seams := SurfaceTool.new()
	seams.begin(Mesh.PRIMITIVE_LINES)
	_add_sail_edges(seams)
	_add_bi_radial_panel_lines(seams)
	seams.commit(sail_mesh)
	sail_mesh.surface_set_material(2, _make_seam_material())

	var battens := SurfaceTool.new()
	battens.begin(Mesh.PRIMITIVE_TRIANGLES)
	for batten_anchor in BATTEN_ANCHORS_HC:
		_add_batten(battens, batten_anchor.x, batten_anchor.y)
	battens.index()
	battens.generate_normals()
	battens.commit(sail_mesh)
	sail_mesh.surface_set_material(3, _make_batten_material())

	var window_grid := SurfaceTool.new()
	window_grid.begin(Mesh.PRIMITIVE_LINES)
	_add_window_grid(window_grid)
	window_grid.commit(sail_mesh)
	sail_mesh.surface_set_material(4, _make_window_grid_material())
	return sail_mesh


func _build_surface_grid() -> Array[PackedVector3Array]:
	# All visual surfaces originate from this one HC lattice. Cloth and window
	# still become separate Godot surfaces for their materials, but cells within
	# each surface are indexed and every seam/batten continues to query the same
	# `sail_surface_point()` evaluator.
	var grid: Array[PackedVector3Array] = []
	for row in range(ROWS + 1):
		var points := PackedVector3Array()
		var height_ratio := float(row) / float(ROWS)
		for column in range(COLUMNS + 1):
			var chord_ratio := float(column) / float(COLUMNS)
			points.append(sail_surface_point(Vector2(height_ratio, chord_ratio)))
		grid.append(points)
	return grid


func _add_sail_grid_cell(
	surface: SurfaceTool,
	grid: Array[PackedVector3Array],
	row: int,
	column: int
) -> void:
	var t0 := float(row) / float(ROWS)
	var t1 := float(row + 1) / float(ROWS)
	var u0 := float(column) / float(COLUMNS)
	var u1 := float(column + 1) / float(COLUMNS)
	if row == ROWS - 1:
		# The MKII head closes to one physical point. One indexed fan triangle
		# per column keeps that closure explicit without a collapsed companion
		# triangle or zero-area face.
		_add_grid_vertex(surface, grid[row][column], t0, u0)
		_add_grid_vertex(surface, grid[ROWS][0], 1.0, 0.0)
		_add_grid_vertex(surface, grid[row][column + 1], t0, u1)
		return
	_add_grid_vertex(surface, grid[row][column], t0, u0)
	_add_grid_vertex(surface, grid[row + 1][column], t1, u0)
	_add_grid_vertex(surface, grid[row + 1][column + 1], t1, u1)
	_add_grid_vertex(surface, grid[row][column], t0, u0)
	_add_grid_vertex(surface, grid[row + 1][column + 1], t1, u1)
	_add_grid_vertex(surface, grid[row][column + 1], t0, u1)


func _add_grid_vertex(
	surface: SurfaceTool,
	point: Vector3,
	height_ratio: float,
	chord_ratio: float
) -> void:
	surface.set_uv(Vector2(chord_ratio, 1.0 - height_ratio))
	surface.add_vertex(point)


func _add_window_film(surface: SurfaceTool) -> void:
	const WINDOW_SEGMENTS := 36
	for segment in range(WINDOW_SEGMENTS):
		var ratio0 := float(segment) / float(WINDOW_SEGMENTS)
		var ratio1 := float(segment + 1) / float(WINDOW_SEGMENTS)
		var u0 := lerpf(0.17, 0.62, ratio0)
		var u1 := lerpf(0.17, 0.62, ratio1)
		var bottom0 := _window_bottom(ratio0)
		var bottom1 := _window_bottom(ratio1)
		var top0 := _window_top(ratio0)
		var top1 := _window_top(ratio1)
		_add_hc_triangle(surface, Vector2(bottom0, u0), Vector2(top0, u0), Vector2(top1, u1))
		_add_hc_triangle(surface, Vector2(bottom0, u0), Vector2(top1, u1), Vector2(bottom1, u1))


func _add_hc_triangle(surface: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
	for hc in [a, b, c]:
		surface.set_uv(Vector2(hc.y, 1.0 - hc.x))
		# A sub-millimetre normal offset avoids coplanar depth flicker while the
		# film still follows the exact same parametric surface as the cloth.
		surface.add_vertex(sail_surface_point(hc) + _sail_normal(hc) * 0.0008)


func _sail_point(height_ratio: float, chord_ratio: float) -> Vector3:
	return sail_surface_point(Vector2(height_ratio, chord_ratio))


func sail_surface_point(hc: Vector2) -> Vector3:
	var height_ratio := clampf(hc.x, 0.0, 1.0)
	var chord_ratio := clampf(hc.y, 0.0, 1.0)
	var luff_point := luff_boundary_point(height_ratio)
	var leech_point := leech_boundary_point(height_ratio)
	var surface_point := luff_point.lerp(leech_point, chord_ratio)

	# A transfinite/Coons-style lower-boundary correction makes the t=0 row
	# exactly equal to the shaped loose foot while leaving both luff and leech
	# boundaries exact.  Its influence fades smoothly before the upper panels.
	var straight_foot := luff_boundary_point(0.0).lerp(
		leech_boundary_point(0.0),
		chord_ratio
	)
	var foot_correction := foot_boundary_point(chord_ratio) - straight_foot
	surface_point += foot_correction * pow(1.0 - height_ratio, 2.65)

	var outhaul_shape := lerpf(1.18, 0.62, outhaul_tension)
	var camber := (
		sin(chord_ratio * PI)
		* sin(height_ratio * PI)
		* 0.075
		* outhaul_shape
	)
	# x is normal to the undeformed sail plane.  Keeping all boundary camber at
	# zero preserves measured edge lengths and provides a stable displacement
	# channel for the later apparent-wind/wrinkle solver.
	surface_point.x += camber
	return surface_point


func luff_boundary_point(height_ratio: float) -> Vector3:
	var t := clampf(height_ratio, 0.0, 1.0)
	return Vector3(0.0, TACK_HEIGHT_METERS + LUFF_SPAN_METERS * t, 0.0)


func foot_boundary_point(chord_ratio: float) -> Vector3:
	var u := clampf(chord_ratio, 0.0, 1.0)
	var point := luff_boundary_point(0.0).lerp(_clew_target_local, u)
	var outhaul_shape := lerpf(1.18, 0.62, outhaul_tension)
	var cunningham_shape := lerpf(1.10, 0.86, cunningham_tension)
	var lower_luff_influence := lerpf(cunningham_shape, 1.0, u)
	# The ILCA sail is loose-footed: only tack and clew meet the boom.  The
	# sinusoidal shelf is zero at both fittings and lowers under either control,
	# preserving the established visual response without confusing edge length
	# with a Cartesian foot projection.
	point.y += (
		sin(u * PI)
		* FOOT_ROACH_METERS
		* outhaul_shape
		* lower_luff_influence
	)
	return point


func leech_boundary_point(height_ratio: float) -> Vector3:
	var t := clampf(height_ratio, 0.0, 1.0)
	var point := _clew_target_local.lerp(luff_boundary_point(1.0), t)
	# A small aft roach gives the leech a cloth silhouette without spending the
	# large, incorrect pseudo-chord used by the old power curve.  The offset is
	# zero at clew/head, so both named attachment points remain exact.
	point.z += sin(t * PI) * LEECH_ROACH_METERS
	return point


func boundary_arc_length(boundary: StringName, segments := 256) -> float:
	# Public diagnostic for geometry tests and future control solvers. Default
	# values resolve to approximately 5.105 m luff, 2.72 m foot and 5.52 m leech,
	# all below the official 5.120/2.750/5.555 m maxima.
	var sample_count := maxi(segments, 2)
	var previous := _boundary_sample(boundary, 0.0)
	var length := 0.0
	for sample_index in range(1, sample_count + 1):
		var ratio := float(sample_index) / float(sample_count)
		var current := _boundary_sample(boundary, ratio)
		length += previous.distance_to(current)
		previous = current
	return length


func _boundary_sample(boundary: StringName, ratio: float) -> Vector3:
	match boundary:
		&"luff":
			return luff_boundary_point(ratio)
		&"foot":
			return foot_boundary_point(ratio)
		&"leech":
			return leech_boundary_point(ratio)
	push_error("Unknown sail boundary: %s" % boundary)
	return Vector3.ZERO


func _build_luff_sleeve() -> void:
	# The sail wraps around the mast in a cloth luff sleeve.  This rotating tube
	# hides the spar wherever the sail is fitted while leaving the aluminium mast
	# visible below the tack and just above the head.
	var sleeve_mesh := CylinderMesh.new()
	sleeve_mesh.top_radius = 0.047
	sleeve_mesh.bottom_radius = 0.064
	sleeve_mesh.height = LUFF_SPAN_METERS + 0.035
	sleeve_mesh.radial_segments = 24
	sleeve_mesh.rings = 8
	var sleeve := MeshInstance3D.new()
	sleeve.name = "LuffSleeve"
	sleeve.position = Vector3(
		0.0,
		TACK_HEIGHT_METERS + sleeve_mesh.height * 0.5 - 0.012,
		0.0
	)
	sleeve.mesh = sleeve_mesh
	sleeve.material_override = _make_cloth_material()
	add_child(sleeve)


func _is_window_panel(height_ratio: float, chord_ratio: float) -> bool:
	if chord_ratio < 0.17 or chord_ratio > 0.62:
		return false
	var window_ratio := inverse_lerp(0.17, 0.62, chord_ratio)
	var bottom_edge := 0.018 + sin(window_ratio * PI) * 0.006
	var top_edge := 0.095 + sin(window_ratio * PI) * 0.050 - window_ratio * 0.008
	return height_ratio >= bottom_edge and height_ratio <= top_edge


func _add_sail_edges(surface: SurfaceTool) -> void:
	var segments := 36
	for segment in range(segments):
		var t0 := float(segment) / float(segments)
		var t1 := float(segment + 1) / float(segments)
		_add_line(surface, _sail_point(t0, 0.0), _sail_point(t1, 0.0))
		_add_line(surface, _sail_point(t0, 1.0), _sail_point(t1, 1.0))
	for segment in range(segments):
		var u0 := float(segment) / float(segments)
		var u1 := float(segment + 1) / float(segments)
		_add_line(surface, _sail_point(0.0, u0), _sail_point(0.0, u1))


func _add_window_grid(surface: SurfaceTool) -> void:
	var outline_segments := 20
	for segment in range(outline_segments):
		var ratio0 := float(segment) / float(outline_segments)
		var ratio1 := float(segment + 1) / float(outline_segments)
		var u0 := lerpf(0.17, 0.62, ratio0)
		var u1 := lerpf(0.17, 0.62, ratio1)
		_add_line(surface, _sail_point(_window_bottom(ratio0), u0), _sail_point(_window_bottom(ratio1), u1))
		_add_line(surface, _sail_point(_window_top(ratio0), u0), _sail_point(_window_top(ratio1), u1))

	_add_line(surface, _sail_point(_window_bottom(0.0), 0.17), _sail_point(_window_top(0.0), 0.17))
	_add_line(surface, _sail_point(_window_bottom(1.0), 0.62), _sail_point(_window_top(1.0), 0.62))

	# The transparent film is not a wire lattice. Keep only its sewn outline;
	# panel reinforcements will be represented by the shared topology pass.


func _window_bottom(window_ratio: float) -> float:
	return 0.018 + sin(window_ratio * PI) * 0.006


func _window_top(window_ratio: float) -> float:
	return 0.095 + sin(window_ratio * PI) * 0.050 - window_ratio * 0.008


func _add_bi_radial_panel_lines(surface: SurfaceTool) -> void:
	# MK2 lower panels fan from the clew, then the upper radial group fans
	# upward from the broad middle seam.
	for luff_height in LOWER_RADIAL_LUFF_HEIGHTS:
		_add_hc_line(surface, Vector2(0.0, 1.0), Vector2(float(luff_height), 0.0), 18)

	for radial_end in UPPER_RADIAL_ENDS_HC:
		_add_hc_line(surface, UPPER_RADIAL_ORIGIN_HC, radial_end, 18)

	for cross_seam in CROSS_SEAMS_HEIGHT_CURVE:
		_add_curved_cross_seam(surface, cross_seam.x, cross_seam.y)


func _add_hc_line(surface: SurfaceTool, from_hc: Vector2, to_hc: Vector2, segments: int) -> void:
	for segment in range(segments):
		var ratio0 := float(segment) / float(segments)
		var ratio1 := float(segment + 1) / float(segments)
		var hc0 := from_hc.lerp(to_hc, ratio0)
		var hc1 := from_hc.lerp(to_hc, ratio1)
		_add_line(surface, _sail_point(hc0.x, hc0.y), _sail_point(hc1.x, hc1.y))


func _add_curved_cross_seam(surface: SurfaceTool, base_height: float, curve: float) -> void:
	var segments := 18
	for segment in range(segments):
		var u0 := float(segment) / float(segments)
		var u1 := float(segment + 1) / float(segments)
		var t0 := base_height + sin(u0 * PI) * curve
		var t1 := base_height + sin(u1 * PI) * curve
		_add_line(surface, _sail_point(t0, u0), _sail_point(t1, u1))


func _add_batten(surface: SurfaceTool, height_ratio: float, start_chord_ratio: float) -> void:
	var half_height := 0.009
	var offset := Vector3(0.008, 0.0, 0.0)
	var a := _sail_point(height_ratio - half_height, start_chord_ratio) + offset
	var b := _sail_point(height_ratio + half_height, start_chord_ratio) + offset
	var c := _sail_point(height_ratio + half_height, 0.985) + offset
	var d := _sail_point(height_ratio - half_height, 0.985) + offset
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)


func _add_line(surface: SurfaceTool, from: Vector3, to: Vector3) -> void:
	surface.add_vertex(from + Vector3(0.004, 0.0, 0.0))
	surface.add_vertex(to + Vector3(0.004, 0.0, 0.0))


func _make_cloth_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.84, 0.855, 0.80, 1.0)
	material.roughness = 0.68
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.backlight_enabled = true
	material.backlight = Color(0.86, 0.88, 0.84, 1.0)
	return material


func _make_window_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.58, 0.62, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.32
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.backlight_enabled = true
	material.backlight = Color(0.55, 0.72, 0.75, 1.0)
	return material


func _make_window_grid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.14, 0.21, 0.22, 0.58)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _make_seam_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.27, 0.27, 0.72)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _make_batten_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.2, 0.2, 0.9)
	material.roughness = 0.7
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
