class_name IlcaSevenSail
extends MeshInstance3D

const LUFF_LENGTH_METERS := 5.12
const FOOT_LENGTH_METERS := 2.75
const BOOM_CENTER_HEIGHT_METERS := 1.21
const TACK_HEIGHT_METERS := 1.27
const CLEW_RISE_METERS := 0.04
const FOOT_ROACH_METERS := 0.11
const ROWS := 48
const COLUMNS := 36

@export_range(0.0, 1.0, 0.01) var outhaul_tension := 0.62
@export_range(0.0, 1.0, 0.01) var cunningham_tension := 0.55

var _last_outhaul_tension := INF
var _last_cunningham_tension := INF


func _ready() -> void:
	mesh = _build_sail_mesh()
	_build_luff_sleeve()
	_last_outhaul_tension = outhaul_tension
	_last_cunningham_tension = cunningham_tension


func _process(_delta: float) -> void:
	if (
		absf(outhaul_tension - _last_outhaul_tension) > 0.005
		or absf(cunningham_tension - _last_cunningham_tension) > 0.005
	):
		mesh = _build_sail_mesh()
		_last_outhaul_tension = outhaul_tension
		_last_cunningham_tension = cunningham_tension


func _build_sail_mesh() -> ArrayMesh:
	var sail_mesh := ArrayMesh.new()
	var cloth := SurfaceTool.new()
	var window := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	window.begin(Mesh.PRIMITIVE_TRIANGLES)

	for row in range(ROWS):
		var t0 := float(row) / float(ROWS)
		var t1 := float(row + 1) / float(ROWS)
		for column in range(COLUMNS):
			var u0 := float(column) / float(COLUMNS)
			var u1 := float(column + 1) / float(COLUMNS)
			var center_t := (t0 + t1) * 0.5
			var center_u := (u0 + u1) * 0.5
			var surface := window if _is_window_panel(center_t, center_u) else cloth
			_add_sail_quad(surface, t0, t1, u0, u1)

	cloth.generate_normals()
	cloth.commit(sail_mesh)
	sail_mesh.surface_set_material(0, _make_cloth_material())
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
	_add_batten(battens, 0.27, 0.63)
	_add_batten(battens, 0.53, 0.55)
	_add_batten(battens, 0.76, 0.42)
	battens.generate_normals()
	battens.commit(sail_mesh)
	sail_mesh.surface_set_material(3, _make_batten_material())

	var window_grid := SurfaceTool.new()
	window_grid.begin(Mesh.PRIMITIVE_LINES)
	_add_window_grid(window_grid)
	window_grid.commit(sail_mesh)
	sail_mesh.surface_set_material(4, _make_window_grid_material())
	return sail_mesh


func _add_sail_quad(surface: SurfaceTool, t0: float, t1: float, u0: float, u1: float) -> void:
	_add_sail_vertex(surface, t0, u0)
	_add_sail_vertex(surface, t1, u0)
	_add_sail_vertex(surface, t1, u1)
	_add_sail_vertex(surface, t0, u0)
	_add_sail_vertex(surface, t1, u1)
	_add_sail_vertex(surface, t0, u1)


func _add_sail_vertex(surface: SurfaceTool, height_ratio: float, chord_ratio: float) -> void:
	surface.set_uv(Vector2(chord_ratio, 1.0 - height_ratio))
	surface.add_vertex(_sail_point(height_ratio, chord_ratio))


func _sail_point(height_ratio: float, chord_ratio: float) -> Vector3:
	var chord := FOOT_LENGTH_METERS * pow(1.0 - height_ratio, 0.96)
	var outhaul_shape := lerpf(1.18, 0.62, outhaul_tension)
	var cunningham_shape := lerpf(1.10, 0.86, cunningham_tension)
	var lower_luff_influence := lerpf(cunningham_shape, 1.0, chord_ratio)
	var camber := (
		sin(chord_ratio * PI)
		* sin(height_ratio * PI)
		* 0.075
		* outhaul_shape
	)
	# The ILCA sail is loose-footed: only the tack and clew are attached to the
	# boom.  Bowing the lower panels keeps the cloth visibly clear of the spar.
	var lower_panel_influence := pow(1.0 - height_ratio, 3.0)
	var foot_lift := (
		sin(chord_ratio * PI) * FOOT_ROACH_METERS
		+ chord_ratio * CLEW_RISE_METERS
	) * lower_panel_influence * outhaul_shape * lower_luff_influence
	return Vector3(
		camber,
		TACK_HEIGHT_METERS + LUFF_LENGTH_METERS * height_ratio + foot_lift,
		chord * chord_ratio
	)


func _build_luff_sleeve() -> void:
	# The sail wraps around the mast in a cloth luff sleeve.  This rotating tube
	# hides the spar wherever the sail is fitted while leaving the aluminium mast
	# visible below the tack and just above the head.
	var sleeve_mesh := CylinderMesh.new()
	sleeve_mesh.top_radius = 0.047
	sleeve_mesh.bottom_radius = 0.064
	sleeve_mesh.height = LUFF_LENGTH_METERS + 0.035
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

	for diagonal_index in range(9):
		var base_height := -0.055 + float(diagonal_index) * 0.030
		_add_clipped_window_line(
			surface,
			Vector2(base_height, 0.15),
			Vector2(base_height + 0.18, 0.64),
			36
		)
		_add_clipped_window_line(
			surface,
			Vector2(base_height + 0.18, 0.15),
			Vector2(base_height, 0.64),
			36
		)


func _window_bottom(window_ratio: float) -> float:
	return 0.018 + sin(window_ratio * PI) * 0.006


func _window_top(window_ratio: float) -> float:
	return 0.095 + sin(window_ratio * PI) * 0.050 - window_ratio * 0.008


func _add_clipped_window_line(
	surface: SurfaceTool,
	from_uv: Vector2,
	to_uv: Vector2,
	segments: int
) -> void:
	for segment in range(segments):
		var ratio0 := float(segment) / float(segments)
		var ratio1 := float(segment + 1) / float(segments)
		var uv0 := from_uv.lerp(to_uv, ratio0)
		var uv1 := from_uv.lerp(to_uv, ratio1)
		if _is_window_panel(uv0.x, uv0.y) and _is_window_panel(uv1.x, uv1.y):
			_add_line(surface, _sail_point(uv0.x, uv0.y), _sail_point(uv1.x, uv1.y))


func _add_bi_radial_panel_lines(surface: SurfaceTool) -> void:
	# MK2 lower panels fan from the clew, then the upper radial group fans
	# upward from the broad middle seam.
	for luff_height in [0.12, 0.23, 0.34, 0.47]:
		_add_uv_line(surface, Vector2(0.0, 1.0), Vector2(float(luff_height), 0.0), 18)

	var radial_origin := Vector2(0.47, 0.20)
	for radial_end in [
		Vector2(1.0, 0.0),
		Vector2(0.95, 0.34),
		Vector2(0.88, 0.62),
		Vector2(0.74, 1.0),
	]:
		_add_uv_line(surface, radial_origin, radial_end, 18)

	_add_curved_cross_seam(surface, 0.47, 0.035)
	_add_curved_cross_seam(surface, 0.86, 0.025)


func _add_uv_line(surface: SurfaceTool, from_uv: Vector2, to_uv: Vector2, segments: int) -> void:
	for segment in range(segments):
		var ratio0 := float(segment) / float(segments)
		var ratio1 := float(segment + 1) / float(segments)
		var uv0 := from_uv.lerp(to_uv, ratio0)
		var uv1 := from_uv.lerp(to_uv, ratio1)
		_add_line(surface, _sail_point(uv0.x, uv0.y), _sail_point(uv1.x, uv1.y))


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
