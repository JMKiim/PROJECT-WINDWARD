class_name IlcaHull
extends MeshInstance3D

const HULL_LENGTH_METERS := 4.23
const HULL_BEAM_METERS := 1.37
const TRIM_TUBE_SIDES := 16
const DECK_SPAN_SEGMENTS := 12
const HULL_SECTION_SEGMENTS := 24
const COCKPIT_FLOOR_SEGMENTS := 16
const HULL_LONGITUDINAL_SEGMENTS := 56
const COCKPIT_LONGITUDINAL_SEGMENTS := 72
const WATERLINE_DATUM_Y := -0.06
const CUTS := preload("res://src/boat/ilca_mesh_cut.gd")
const SLOT_CENTER_Z := -0.155
const SLOT_HALF_LENGTH := 0.220
const SLOT_HALF_WIDTH := 0.027
const MAST_CENTER_Z := -0.810
const MAST_SOCKET_RADIUS := 0.062
# Inspection fit estimate, not a certified builder mould dimension. The wider
# production socket remains until its older oversize spar is migrated together.
@export var inspection_mast_fit := false
const INSPECTION_SOCKET_WIDTH := .066
const INSPECTION_SOCKET_LENGTH := .075
const FORELAND_HEIGHT := 0.240
const FORELAND_STEP_START := 0.230
const FORELAND_STEP_END := 0.290
const RATCHET_ORIGIN := Vector3(0, FORELAND_HEIGHT + 0.050, 0.14)
const STRAP_FRONT_ORIGIN := Vector3(0, FORELAND_HEIGHT + 0.015, 0.207)
const DRAIN_INLET_X := 0.075
const DRAIN_INLET_Z := 1.355
const DRAIN_BORE_RADIUS := 0.012
var drain_frame := Transform3D.IDENTITY
var drain_outlet := Vector3.ZERO
var drain_inlet_ring := PackedVector3Array()
var drain_outlet_ring := PackedVector3Array()
var _drain_seat := Plane()
var _drain_seat_center := Vector3.ZERO
var _surface_kind := 0
var _face_normal := Vector3.ZERO

var _stations: Array[Dictionary] = [
	# C02 measurement reference, normalized to the public 4.23 m x 1.37 m
	# envelope. These are independent procedural control points, not source mesh
	# vertices. Absolute Y retains the game's established waterline/deck datum.
	{"z": -2.115, "width": 0.000, "deck": 0.330, "keel": 0.330},
	{"z": -2.030, "width": 0.062, "deck": 0.332, "keel": 0.250},
	{"z": -1.875, "width": 0.142, "deck": 0.334, "keel": 0.095},
	{"z": -1.650, "width": 0.249, "deck": 0.335, "keel": -0.027},
	{"z": -1.365, "width": 0.362, "deck": 0.336, "keel": -0.050},
	{"z": -1.020, "width": 0.471, "deck": 0.336, "keel": -0.068},
	{"z": -0.620, "width": 0.568, "deck": 0.335, "keel": -0.064},
	{"z": -0.180, "width": 0.637, "deck": 0.332, "keel": -0.054},
	{"z": 0.280, "width": 0.675, "deck": 0.326, "keel": -0.040},
	{"z": 0.635, "width": 0.685, "deck": 0.320, "keel": -0.029},
	{"z": 0.720, "width": 0.682, "deck": 0.318, "keel": -0.027},
	{"z": 1.100, "width": 0.666, "deck": 0.308, "keel": -0.009},
	{"z": 1.420, "width": 0.629, "deck": 0.298, "keel": 0.011},
	{"z": 1.700, "width": 0.587, "deck": 0.288, "keel": 0.033},
	{"z": 1.950, "width": 0.538, "deck": 0.279, "keel": 0.055},
	{"z": 2.115, "width": 0.521, "deck": 0.273, "keel": 0.056},
]

# The official transom-to-cockpit limits place the forward end near -0.39 m.
# Its narrow first section exposes the centreboard trunk before the moulding
# opens into the broad seating well measured from the C02 reference.
var _cockpit_z_positions := [-0.390, -0.310, -0.200, -0.120, 0.00, 0.17, 0.34, 0.82, 1.20, 1.32, 1.415]
var _cockpit_half_widths := [0.076, 0.120, 0.165, 0.205, 0.275, 0.350, 0.415, 0.425, 0.420, 0.390, 0.300]


func _ready() -> void:
	mesh = _build_hull_mesh()


func _build_hull_mesh() -> ArrayMesh:
	var e := 0.0005
	_drain_seat_center = Vector3(DRAIN_INLET_X, _cockpit_base_y(DRAIN_INLET_X, 0, DRAIN_INLET_Z), DRAIN_INLET_Z)
	var dx := (_cockpit_base_y(DRAIN_INLET_X + e, 0, DRAIN_INLET_Z) - _cockpit_base_y(DRAIN_INLET_X - e, 0, DRAIN_INLET_Z)) / (2 * e)
	var dz := (_cockpit_base_y(DRAIN_INLET_X, 0, DRAIN_INLET_Z + e) - _cockpit_base_y(DRAIN_INLET_X, 0, DRAIN_INLET_Z - e)) / (2 * e)
	_drain_seat = Plane(Vector3(-dx, 1, -dz).normalized(), _drain_seat_center)
	var hull_mesh := ArrayMesh.new()
	_surface_kind = 0
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sampled_stations := _sampled_stations()
	for station_index in range(sampled_stations.size() - 1):
		var forward_ring := _station_ring(sampled_stations[station_index])
		var aft_ring := _station_ring(sampled_stations[station_index + 1])
		for ring_index in range(forward_ring.size() - 1):
			_add_quad(
				shell,
				forward_ring[ring_index],
				forward_ring[ring_index + 1],
				aft_ring[ring_index + 1],
				aft_ring[ring_index]
			)
	_add_transom(shell)
	shell.index()
	shell.commit(hull_mesh)
	hull_mesh.surface_set_name(0, "outer_shell")
	hull_mesh.surface_set_material(0, _make_material(Color(0.97, 0.975, 0.96), 0.38))

	var deck := SurfaceTool.new()
	_surface_kind = 1
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	deck.set_smooth_group(0)
	_add_closed_deck(deck, _range_positions(-2.115, float(_cockpit_z_positions.front()), 28))
	_add_side_decks_and_cockpit(deck)
	_add_closed_deck(deck, _range_positions(float(_cockpit_z_positions.back()), 2.115, 12))
	deck.index()
	deck.commit(hull_mesh)
	hull_mesh.surface_set_name(1, "deck")
	hull_mesh.surface_set_material(1, _make_material(Color(0.975, 0.978, 0.965), 0.54))

	var cockpit := SurfaceTool.new()
	_surface_kind = 2
	cockpit.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_cockpit_well(cockpit)
	cockpit.index()
	# _add_cockpit_well() authors the normals explicitly. Regenerating them here
	# would blend the floor and walls back together at their shared corners.
	cockpit.commit(hull_mesh)
	hull_mesh.surface_set_name(2, "cockpit")
	# The well and deck share a gelcoat tone. Lighting, rather than emission,
	# reveals the wall fillets and the forward moulding.
	var cockpit_material := _make_material(Color(0.975, 0.978, 0.965), 0.58)
	hull_mesh.surface_set_material(2, cockpit_material)

	var molded_edges := SurfaceTool.new()
	_surface_kind = 3
	molded_edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_gunwale_and_cockpit_coaming(molded_edges)
	molded_edges.index()
	molded_edges.commit(hull_mesh)
	hull_mesh.surface_set_name(3, "gunwale_lip")
	hull_mesh.surface_set_material(3, _make_material(Color(0.97, 0.97, 0.95), 0.42))

	var sheer_stripe := SurfaceTool.new()
	_surface_kind = 4
	sheer_stripe.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_sheer_stripes(sheer_stripe)
	sheer_stripe.index()
	sheer_stripe.generate_normals()
	sheer_stripe.commit(hull_mesh)
	hull_mesh.surface_set_name(4, "sheer_stripe")
	hull_mesh.surface_set_material(4, _make_material(Color(0.11, 0.13, 0.14), 0.5))

	# Non-slip detailing belongs to the moulding material, not a second sheet
	# of nearly coplanar triangles casting stripes across the deck.
	var slot := slot_outline()
	var mast := CUTS.circle(Vector2(0, MAST_CENTER_Z), MAST_SOCKET_RADIUS)
	if inspection_mast_fit:
		mast = CUTS.circle(Vector2.ZERO, .5)
		for index in mast.size():
			mast[index] = Vector2(mast[index].x * INSPECTION_SOCKET_WIDTH, MAST_CENTER_Z + mast[index].y * INSPECTION_SOCKET_LENGTH)
	var opened := CUTS.apply(hull_mesh, {0: [slot], 1: [mast], 2: [slot]})
	# One inclined passage joins the low aft-wall inlet to the underside.
	# The centre and angle are visual estimates; rims follow actual triangles.
	var inlet := _mesh_ray(hull_mesh, 2, Vector3(DRAIN_INLET_X, 1, DRAIN_INLET_Z), Vector3.DOWN)
	var axis := _surface_normal(inlet.x, inlet.z, 2)
	var tangent := Vector3.RIGHT.cross(axis).normalized()
	drain_frame = Transform3D(Basis(axis.cross(tangent), axis, tangent), inlet)
	drain_outlet = _mesh_ray(hull_mesh, 0, inlet + axis * 0.1, -axis)
	var drain := CUTS.circle(Vector2.ZERO, DRAIN_BORE_RADIUS)
	opened = CUTS.apply(opened, {0: [drain], 2: [drain]}, drain_frame)
	drain_inlet_ring = _drain_boundary(opened, 2, drain)
	drain_outlet_ring = _drain_boundary(opened, 0, drain)
	for index in hull_mesh.get_surface_count():
		opened.surface_set_name(index, hull_mesh.surface_get_name(index))
	var liners := SurfaceTool.new()
	liners.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_aperture_liner(liners, slot, false)
	_add_drain_liner(liners)
	_add_aperture_liner(liners, mast, true)
	liners.index()
	liners.commit(opened)
	opened.surface_set_name(5, "aperture_liners")
	opened.surface_set_material(5, _make_material(Color(0.88, 0.895, 0.875), 0.64))
	return opened


func _station_ring(station: Dictionary) -> PackedVector3Array:
	var z := float(station["z"])
	var width := float(station["width"])
	var deck_y := float(station["deck"])
	var keel_y := float(station["keel"])
	var ring := PackedVector3Array()
	for slice in range(HULL_SECTION_SEGMENTS + 1):
		var side_ratio := -1.0 + 2.0 * float(slice) / float(HULL_SECTION_SEGMENTS)
		var lateral_ratio := absf(side_ratio)
		# The independent entry/bilge/run family varies along the hull.
		var height_ratio := _section_height_ratio(lateral_ratio, z)
		ring.append(Vector3(
			width * side_ratio,
			lerpf(keel_y, deck_y, height_ratio),
			z
		))
	return ring


func _section_height_ratio(ratio: float, z: float) -> float:
	# Independently authored section family: fuller forward entry and flatter
	# aft run. Envelope and keel datum stay fixed; this is not a mould survey.
	var r := clampf(ratio, 0.0, 1.0)
	var exponent := lerpf(1.0, 1.18, smoothstep(0.25, 1.65, z))
	var q := pow(r, exponent)
	var bilge := 1.0 - sqrt(maxf(0.0, 1.0 - q * q))
	var rounded_entry := (sqrt(r * r + 0.01) - 0.1) / (sqrt(1.01) - 0.1)
	var entry_weight := 0.48 * (1.0 - smoothstep(-1.70, -0.35, z))
	return lerpf(bilge, rounded_entry, entry_weight)


func shell_y_at(x: float, z: float) -> float:
	var station := _station_at(z)
	return lerpf(station.keel, station.deck, _section_height_ratio(absf(x) / maxf(station.width, 0.002), z))


static func slot_outline() -> PackedVector2Array:
	return CUTS.capsule(Vector2(0, SLOT_CENTER_Z), SLOT_HALF_LENGTH, SLOT_HALF_WIDTH)


func _mesh_ray(source: ArrayMesh, surface_index: int, origin: Vector3, direction: Vector3) -> Vector3:
	var data := source.surface_get_arrays(surface_index)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	var nearest := INF
	var result := Vector3.INF
	for index in range(0, indices.size(), 3):
		# Evaluate in millimetres around the ray origin: metre-scale slivers
		# otherwise fall below the library's fixed intersection epsilon.
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3.ZERO, direction, (vertices[indices[index]] - origin) * 1000.0, (vertices[indices[index + 1]] - origin) * 1000.0, (vertices[indices[index + 2]] - origin) * 1000.0)
		if hit != null: hit = origin + hit / 1000.0
		if hit != null and origin.distance_squared_to(hit) < nearest:
			nearest = origin.distance_squared_to(hit)
			result = hit
	assert(result.is_finite(), "Drain axis must intersect the intended moulding surface")
	return result


func _drain_boundary(source: ArrayMesh, surface_index: int, outline: PackedVector2Array) -> PackedVector3Array:
	var vertices: PackedVector3Array = source.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
	var projection := drain_frame.affine_inverse()
	var points: Array[Vector3] = []
	for point in vertices:
		if not CUTS._on_boundary(point, [outline], projection): continue
		# Normal-split copies can straddle a rounding cell by a few nanometres.
		# Distance deduplication avoids adding a zero-length liner edge.
		var duplicate := false
		for existing in points:
			if point.distance_squared_to(existing) < 1e-14:
				duplicate = true
				break
		if duplicate: continue
		points.append(point)
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _drain_angle(a) < _drain_angle(b))
	return PackedVector3Array(points)


func _drain_angle(point: Vector3) -> float:
	var local := drain_frame.affine_inverse() * point
	return fposmod(atan2(local.z, local.x), TAU)


func _add_drain_liner(surface: SurfaceTool) -> void:
	# Merge both actual cut-edge rings without assuming identical subdivisions.
	var upper := drain_inlet_ring
	var lower := drain_outlet_ring
	assert(upper.size() >= 16 and lower.size() >= 16, "Drain must have two complete cut rings")
	var i := 0
	var j := 0
	while i < upper.size() or j < lower.size():
		var next_i := _drain_angle(upper[(i + 1) % upper.size()]) if i + 1 < upper.size() else TAU
		var next_j := _drain_angle(lower[(j + 1) % lower.size()]) if j + 1 < lower.size() else TAU
		var a := upper[i % upper.size()]
		var b := lower[j % lower.size()]
		var c: Vector3
		if i < upper.size() and (j >= lower.size() or next_i <= next_j):
			i += 1
			c = upper[i % upper.size()]
		else:
			j += 1
			c = lower[j % lower.size()]
		var center := drain_frame.affine_inverse() * ((a + b + c) / 3.0)
		var normal := drain_frame.basis * -Vector3(center.x, 0, center.z).normalized()
		_add_triangle_with_normals(surface, a, normal, b, normal, c, normal)


func _surface_normal(x: float, z: float, kind: int) -> Vector3:
	var e := 0.0005
	var height := shell_y_at if kind == 0 else (deck_y_at if kind == 1 else cockpit_floor_y_at)
	var dx: float = (height.call(x + e, z) - height.call(x - e, z)) / (2 * e)
	var dz: float = (height.call(x, z + e) - height.call(x, z - e)) / (2 * e)
	var normal := Vector3(-dx, 1, -dz).normalized()
	return -normal if kind == 0 else normal


func _add_aperture_liner(surface: SurfaceTool, outline: PackedVector2Array, socket: bool) -> void:
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		var top_a := deck_y_at(a.x, a.y) if socket else cockpit_floor_y_at(a.x, a.y)
		var top_b := deck_y_at(b.x, b.y) if socket else cockpit_floor_y_at(b.x, b.y)
		var bottom_a := 0.005 if socket else shell_y_at(a.x, a.y)
		var bottom_b := 0.005 if socket else shell_y_at(b.x, b.y)
		var edge := b - a
		var inward := Vector3(-edge.y, 0, edge.x).normalized()
		var p := Vector3(a.x, top_a, a.y)
		var q := Vector3(b.x, top_b, b.y)
		var r := Vector3(b.x, bottom_b, b.y)
		var s := Vector3(a.x, bottom_a, a.y)
		if socket and inspection_mast_fit:
			var bottom_radius := INSPECTION_SOCKET_WIDTH * .5
			var bottom_a_xz := (a-Vector2(0,MAST_CENTER_Z)).normalized()*bottom_radius
			var bottom_b_xz := (b-Vector2(0,MAST_CENTER_Z)).normalized()*bottom_radius
			s = Vector3(bottom_a_xz.x,bottom_a,MAST_CENTER_Z+bottom_a_xz.y)
			r = Vector3(bottom_b_xz.x,bottom_b,MAST_CENTER_Z+bottom_b_xz.y)
		_add_triangle_with_normals(surface, p, inward, q, inward, r, inward)
		_add_triangle_with_normals(surface, p, inward, r, inward, s, inward)
		if socket:
			_add_triangle_with_normals(surface, Vector3(0, 0.005, MAST_CENTER_Z), Vector3.UP, s, Vector3.UP, r, Vector3.UP)


func _sampled_stations() -> Array[Dictionary]:
	var sampled: Array[Dictionary] = []
	for sample_index in range(HULL_LONGITUDINAL_SEGMENTS + 1):
		var z_position := lerpf(-HULL_LENGTH_METERS * 0.5, HULL_LENGTH_METERS * 0.5, float(sample_index) / float(HULL_LONGITUDINAL_SEGMENTS))
		var station := _station_at(z_position)
		# The shell uses a tiny finite bow ring to avoid collapsed quads and bad
		# normals. The deck still closes on the exact 4.23 m centerline apex.
		if sample_index == 0:
			station["width"] = 0.002
			station["keel"] = float(station["deck"]) - 0.002
		sampled.append(station)
	return sampled


func _station_at(z_position: float) -> Dictionary:
	if z_position <= float(_stations.front()["z"]):
		return _stations.front().duplicate()
	if z_position >= float(_stations.back()["z"]):
		return _stations.back().duplicate()
	for index in range(_stations.size() - 1):
		var first: Dictionary = _stations[index]
		var second: Dictionary = _stations[index + 1]
		var first_z := float(first["z"])
		var second_z := float(second["z"])
		if z_position < first_z or z_position > second_z:
			continue
		var ratio := inverse_lerp(first_z, second_z, z_position)
		var previous: Dictionary = _stations[maxi(0, index - 1)]
		var following: Dictionary = _stations[mini(_stations.size() - 1, index + 2)]
		var width := cubic_interpolate(
			float(first["width"]),
			float(second["width"]),
			float(previous["width"]),
			float(following["width"]),
			ratio
		)
		return {
			"z": z_position,
			"width": clampf(width, 0.0, HULL_BEAM_METERS * 0.5),
			"deck": cubic_interpolate(float(first["deck"]), float(second["deck"]), float(previous["deck"]), float(following["deck"]), ratio),
			"keel": cubic_interpolate(float(first["keel"]), float(second["keel"]), float(previous["keel"]), float(following["keel"]), ratio),
		}
	return _stations.back().duplicate()


func _range_positions(from_z: float, to_z: float, segments: int) -> Array[float]:
	var positions: Array[float] = []
	for index in range(segments + 1):
		positions.append(lerpf(from_z, to_z, float(index) / float(segments)))
	return positions


func _cockpit_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var from_z := float(_cockpit_z_positions.front())
	var to_z := float(_cockpit_z_positions.back())
	var positions := _range_positions(from_z, to_z, COCKPIT_LONGITUDINAL_SEGMENTS)
	positions.append_array(_range_positions(FORELAND_STEP_START - 0.010, FORELAND_STEP_END + 0.010, 16))
	positions.append_array(_range_positions(1.335, 1.380, 18))
	positions.append_array([0.110, 0.170, 0.177, 0.237])
	positions.sort()
	var previous := -INF
	for z_position in positions:
		if z_position - previous < 0.00005: continue
		samples.append({"z": z_position, "width": _cockpit_half_width_at(z_position)})
		previous = z_position
	return samples


func _cockpit_half_width_at(z_position: float) -> float:
	if z_position <= float(_cockpit_z_positions.front()):
		return float(_cockpit_half_widths.front())
	if z_position >= float(_cockpit_z_positions.back()):
		return float(_cockpit_half_widths.back())
	for index in range(_cockpit_z_positions.size() - 1):
		var first_z := float(_cockpit_z_positions[index])
		var second_z := float(_cockpit_z_positions[index + 1])
		if z_position < first_z or z_position > second_z:
			continue
		var ratio := inverse_lerp(first_z, second_z, z_position)
		var previous := float(_cockpit_half_widths[maxi(0, index - 1)])
		var first := float(_cockpit_half_widths[index])
		var second := float(_cockpit_half_widths[index + 1])
		var following := float(_cockpit_half_widths[mini(_cockpit_half_widths.size() - 1, index + 2)])
		return maxf(0.0, cubic_interpolate(first, second, previous, following, ratio))
	return 0.0


func _add_transom(surface: SurfaceTool) -> void:
	_face_normal = Vector3.BACK
	var ring := _station_ring(_stations.back())
	var center := Vector3(0.0, (float(_stations.back()["deck"]) + float(_stations.back()["keel"])) * 0.5, 2.115)
	for index in range(ring.size() - 1):
		_add_triangle(surface, ring[index], ring[index + 1], center)
	_add_triangle(surface, ring[ring.size() - 1], ring[0], center)
	_face_normal = Vector3.ZERO


func _add_closed_deck(surface: SurfaceTool, z_positions: Array) -> void:
	# Use the same central 48 columns and 12 side strips as the well boundary.
	# Matching positions matter even when both surfaces sample the same curve.
	var boundary_z: float = z_positions.back() if float(z_positions.back()) <= float(_cockpit_z_positions.front()) + 0.0001 else z_positions.front()
	var inner_ratio := _cockpit_half_width_at(boundary_z) / _deck_profile_at(boundary_z).x
	var ratios := PackedFloat32Array()
	for column in DECK_SPAN_SEGMENTS: ratios.append(lerpf(-1.0, -inner_ratio, float(column) / DECK_SPAN_SEGMENTS))
	for column in 48: ratios.append(lerpf(-inner_ratio, inner_ratio, float(column) / 48.0))
	for column in range(DECK_SPAN_SEGMENTS + 1): ratios.append(lerpf(inner_ratio, 1.0, float(column) / DECK_SPAN_SEGMENTS))
	for index in range(z_positions.size() - 1):
		var z_forward := float(z_positions[index])
		var z_aft := float(z_positions[index + 1])
		var forward := _deck_profile_at(z_forward)
		var aft := _deck_profile_at(z_aft)
		if forward.x <= 0.0001:
			var apex := Vector3(0.0, _deck_surface_y(z_forward, 0.0), z_forward)
			for span_index in range(ratios.size() - 1):
				var ratio_left := ratios[span_index]
				var ratio_right := ratios[span_index + 1]
				var aft_left_x := aft.x * ratio_left
				var aft_right_x := aft.x * ratio_right
				_add_triangle(
					surface,
					apex,
					Vector3(aft_left_x, _deck_surface_y(z_aft, aft_left_x), z_aft),
					Vector3(aft_right_x, _deck_surface_y(z_aft, aft_right_x), z_aft)
				)
			continue
		for span_index in range(ratios.size() - 1):
			var ratio_left := ratios[span_index]
			var ratio_right := ratios[span_index + 1]
			var forward_left_x := forward.x * ratio_left
			var forward_right_x := forward.x * ratio_right
			var aft_left_x := aft.x * ratio_left
			var aft_right_x := aft.x * ratio_right
			_add_quad(
				surface,
				Vector3(forward_left_x, _deck_surface_y(z_forward, forward_left_x), z_forward),
				Vector3(aft_left_x, _deck_surface_y(z_aft, aft_left_x), z_aft),
				Vector3(aft_right_x, _deck_surface_y(z_aft, aft_right_x), z_aft),
				Vector3(forward_right_x, _deck_surface_y(z_forward, forward_right_x), z_forward)
			)


func _add_side_decks_and_cockpit(surface: SurfaceTool) -> void:
	var cockpit_samples := _cockpit_samples()
	for index in range(cockpit_samples.size() - 1):
		var z_forward := float(cockpit_samples[index]["z"])
		var z_aft := float(cockpit_samples[index + 1]["z"])
		var forward := _deck_profile_at(z_forward)
		var aft := _deck_profile_at(z_aft)
		var inner_forward := float(cockpit_samples[index]["width"])
		var inner_aft := float(cockpit_samples[index + 1]["width"])
		for side in [-1.0, 1.0]:
			for strip in DECK_SPAN_SEGMENTS:
				var u := float(strip) / DECK_SPAN_SEGMENTS
				var v := float(strip + 1) / DECK_SPAN_SEGMENTS
				var x0: float = side * lerpf(inner_forward, forward.x, u)
				var x1: float = side * lerpf(inner_aft, aft.x, u)
				var x2: float = side * lerpf(inner_aft, aft.x, v)
				var x3: float = side * lerpf(inner_forward, forward.x, v)
				_add_quad(surface, Vector3(x0, deck_y_at(x0, z_forward), z_forward), Vector3(x1, deck_y_at(x1, z_aft), z_aft), Vector3(x2, deck_y_at(x2, z_aft), z_aft), Vector3(x3, deck_y_at(x3, z_forward), z_forward))


func _add_cockpit_well(surface: SurfaceTool) -> void:
	var samples := _cockpit_samples()
	var columns := 48
	for row in range(samples.size() - 1):
		var z0 := float(samples[row].z)
		var z1 := float(samples[row + 1].z)
		var w0 := _cockpit_half_width_at(z0)
		var w1 := _cockpit_half_width_at(z1)
		for column in columns:
			var u := -1.0 + 2.0 * float(column) / columns
			var v := -1.0 + 2.0 * float(column + 1) / columns
			_add_quad(surface,
				Vector3(w0 * u, cockpit_floor_y_at(w0 * u, z0), z0),
				Vector3(w1 * u, cockpit_floor_y_at(w1 * u, z1), z1),
				Vector3(w1 * v, cockpit_floor_y_at(w1 * v, z1), z1),
				Vector3(w0 * v, cockpit_floor_y_at(w0 * v, z0), z0))


func _cockpit_base_y(x_position: float, _half_width: float, z_position: float) -> float:
	var z := clampf(z_position, float(_cockpit_z_positions.front()), float(_cockpit_z_positions.back()))
	var width := _cockpit_half_width_at(z)
	var core := maxf(0.020, width - 0.100)
	var dish := 0.004 * smoothstep(0.0, core, absf(x_position))
	var floor_y := 0.041 + dish - 0.002 * smoothstep(0.45, 1.20, z)
	# Raised slot landing, then a short rounded riser into the low well.
	# Height and fillet widths remain explicitly estimated, not surveyed data.
	var landing := lerpf(deck_y_at(x_position, z), FORELAND_HEIGHT, smoothstep(-0.390, -0.080, z))
	var foreland := 1.0 - smoothstep(FORELAND_STEP_START, FORELAND_STEP_END, z)
	floor_y = lerpf(floor_y, landing, foreland)
	var side := clampf((absf(x_position) - core) / maxf(width - core, 0.001), 0.0, 1.0)
	var side_round := smoothstep(0.0, 1.0, pow(side, 1.6))
	var aft_round := smoothstep(1.340, 1.415, z)
	var wall := 1.0 - (1.0 - side_round) * (1.0 - aft_round)
	return lerpf(floor_y, deck_y_at(x_position, z), wall)


func _cockpit_floor_y(x_position: float, half_width: float, z_position: float) -> float:
	var height := _cockpit_base_y(x_position, half_width, z_position)
	if absf(x_position - DRAIN_INLET_X) > 0.030 or absf(z_position - DRAIN_INLET_Z) > 0.020 or _drain_seat.normal.y <= 0.0:
		return height
	# A small flat fitting seat blends into the moulded wall; do not bend a
	# rigid brass flange around the wall-to-floor fillet.
	var plane_y := (_drain_seat.d - _drain_seat.normal.x * x_position - _drain_seat.normal.z * z_position) / _drain_seat.normal.y
	var radius := Vector3(x_position, plane_y, z_position).distance_to(_drain_seat_center)
	return lerpf(plane_y, height, smoothstep(0.021, 0.030, radius))


func _cockpit_floor_surface_y(x_position: float, z_position: float) -> float:
	return cockpit_floor_y_at(x_position, z_position)


func _cockpit_floor_normal(position: Vector3) -> Vector3:
	return _surface_normal(position.x, position.z, 2)


func cockpit_floor_y_at(x_position: float, z_position: float) -> float:
	var half_width := maxf(0.015, _cockpit_half_width_at(z_position) - 0.055)
	return _cockpit_floor_y(x_position, half_width, z_position)


func deck_y_at(x_position: float, z_position: float) -> float:
	return _deck_surface_y(z_position, x_position)


func _deck_profile_at(z_position: float) -> Vector2:
	var station := _station_at(z_position)
	return Vector2(float(station["width"]), float(station["deck"]))


func _deck_surface_y(z_position: float, x_position: float) -> float:
	var profile := _deck_profile_at(z_position)
	var lateral_ratio := clampf(absf(x_position) / maxf(profile.x, 0.001), 0.0, 1.0)
	var foredeck_influence := 1.0 - smoothstep(-0.25, 0.55, z_position)
	var crown := lerpf(0.006, 0.011, foredeck_influence)
	return profile.y + pow(1.0 - lateral_ratio, 1.7) * crown


func _add_gunwale_and_cockpit_coaming(surface: SurfaceTool) -> void:
	# A continuous rolled edge replaces independently capped pipe segments.
	# The cockpit edge is already rounded into the deck by the well surface.
	var path := PackedVector3Array()
	var stations := _sampled_stations()
	for sample in stations:
		path.append(Vector3(-sample.width, sample.deck, sample.z))
	for index in range(stations.size() - 1, -1, -1):
		var sample := stations[index]
		path.append(Vector3(sample.width, sample.deck, sample.z))
	for index in path.size():
		var next := (index + 1) % path.size()
		var rings := []
		var normals := []
		for point_index in [index, next]:
			var tangent := path[(point_index + 1) % path.size()] - path[(point_index - 1 + path.size()) % path.size()]
			var outward := Vector3(tangent.z, 0, -tangent.x).normalized()
			# The path travels clockwise in plan, with the hull on its right.
			outward = -outward
			var ring := PackedVector3Array()
			var ring_normals := PackedVector3Array()
			var taper := lerpf(0.20, 1.0, smoothstep(-2.115, -2.000, path[point_index].z))
			for step in range(9):
				var angle := PI * float(step) / 8.0
				var normal := outward * -cos(angle) + Vector3.UP * sin(angle)
				ring.append(path[point_index] + (outward * (-0.002 - 0.010 * cos(angle)) + Vector3.UP * (0.008 * sin(angle) - 0.003)) * taper)
				ring_normals.append(normal)
			rings.append(ring)
			normals.append(ring_normals)
		for step in 8:
			_add_triangle_with_normals(surface, rings[0][step], normals[0][step], rings[1][step], normals[1][step], rings[1][step + 1], normals[1][step + 1])
			_add_triangle_with_normals(surface, rings[0][step], normals[0][step], rings[1][step + 1], normals[1][step + 1], rings[0][step + 1], normals[0][step + 1])


func _add_sheer_stripes(surface: SurfaceTool) -> void:
	var sampled_stations := _sampled_stations()
	for side in [-1.0, 1.0]:
		for index in range(1, sampled_stations.size() - 1):
			var forward := sampled_stations[index]
			var aft := sampled_stations[index + 1]
			var side_value := float(side)
			var forward_outer := float(forward["width"]) + 0.004
			var aft_outer := float(aft["width"]) + 0.004
			_add_quad(
				surface,
				Vector3(side_value * forward_outer, float(forward["deck"]) - 0.012, float(forward["z"])),
				Vector3(side_value * aft_outer, float(aft["deck"]) - 0.012, float(aft["z"])),
				Vector3(side_value * aft_outer, float(aft["deck"]) - 0.028, float(aft["z"])),
				Vector3(side_value * forward_outer, float(forward["deck"]) - 0.028, float(forward["z"]))
			)




func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(surface, a, b, c)
	_add_triangle(surface, a, c, d)


func _add_cockpit_floor_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle_with_normals(
		surface,
		a, _cockpit_floor_normal(a),
		b, _cockpit_floor_normal(b),
		c, _cockpit_floor_normal(c)
	)
	_add_triangle_with_normals(
		surface,
		a, _cockpit_floor_normal(a),
		c, _cockpit_floor_normal(c),
		d, _cockpit_floor_normal(d)
	)


func _add_quad_with_face_normal(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var longitudinal := ((b - a) + (c - d)) * 0.5
	var transverse := ((d - a) + (c - b)) * 0.5
	var normal := longitudinal.cross(transverse).normalized()
	if normal.y < 0.0:
		normal = -normal
	_add_triangle_with_normals(surface, a, normal, b, normal, c, normal)
	_add_triangle_with_normals(surface, a, normal, c, normal, d, normal)


func _add_triangle_with_normals(
	surface: SurfaceTool,
	a: Vector3,
	normal_a: Vector3,
	b: Vector3,
	normal_b: Vector3,
	c: Vector3,
	normal_c: Vector3
) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-18: return
	# Godot front faces are clockwise relative to their outward normal.
	if (b - a).cross(c - a).dot(normal_a + normal_b + normal_c) > 0:
		var point_swap := b
		b = c
		c = point_swap
		var normal_swap := normal_b
		normal_b = normal_c
		normal_c = normal_swap
	surface.set_normal(normal_a)
	surface.add_vertex(a)
	surface.set_normal(normal_b)
	surface.add_vertex(b)
	surface.set_normal(normal_c)
	surface.add_vertex(c)


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if _surface_kind <= 2:
		var na := _face_normal if not _face_normal.is_zero_approx() else _surface_normal(a.x, a.z, _surface_kind)
		var nb := _face_normal if not _face_normal.is_zero_approx() else _surface_normal(b.x, b.z, _surface_kind)
		var nc := _face_normal if not _face_normal.is_zero_approx() else _surface_normal(c.x, c.z, _surface_kind)
		_add_triangle_with_normals(surface, a, na, b, nb, c, nc)
		return
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
