class_name IlcaHull
extends MeshInstance3D

const HULL_LENGTH_METERS := 4.23
const HULL_BEAM_METERS := 1.37
const TRIM_TUBE_SIDES := 12
const DECK_SPAN_SEGMENTS := 12
const HULL_SECTION_SEGMENTS := 24
const COCKPIT_FLOOR_SEGMENTS := 16

var _stations: Array[Dictionary] = [
	{"z": -2.115, "width": 0.005, "deck": 0.258, "keel": 0.258},
	{"z": -2.030, "width": 0.070, "deck": 0.294, "keel": 0.206},
	{"z": -1.875, "width": 0.215, "deck": 0.326, "keel": 0.110},
	{"z": -1.650, "width": 0.395, "deck": 0.348, "keel": 0.005},
	{"z": -1.365, "width": 0.565, "deck": 0.360, "keel": -0.050},
	{"z": -1.020, "width": 0.640, "deck": 0.362, "keel": -0.073},
	{"z": -0.620, "width": 0.680, "deck": 0.362, "keel": -0.085},
	{"z": -0.180, "width": 0.685, "deck": 0.360, "keel": -0.090},
	{"z": 0.280, "width": 0.680, "deck": 0.350, "keel": -0.088},
	{"z": 0.720, "width": 0.662, "deck": 0.338, "keel": -0.078},
	{"z": 1.100, "width": 0.630, "deck": 0.322, "keel": -0.060},
	{"z": 1.420, "width": 0.590, "deck": 0.305, "keel": -0.036},
	{"z": 1.700, "width": 0.555, "deck": 0.291, "keel": -0.010},
	{"z": 1.950, "width": 0.526, "deck": 0.281, "keel": 0.005},
	{"z": 2.115, "width": 0.508, "deck": 0.276, "keel": 0.012},
]

var _cockpit_z_positions := [-0.39, -0.31, -0.18, 0.28, 0.82, 1.22, 1.36, 1.43]
var _cockpit_half_widths := [0.14, 0.27, 0.325, 0.340, 0.340, 0.325, 0.255, 0.12]


func _ready() -> void:
	mesh = _build_hull_mesh()


func _build_hull_mesh() -> ArrayMesh:
	var hull_mesh := ArrayMesh.new()
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	for station_index in range(_stations.size() - 1):
		var forward_ring := _station_ring(_stations[station_index])
		var aft_ring := _station_ring(_stations[station_index + 1])
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
	shell.generate_normals()
	shell.commit(hull_mesh)
	hull_mesh.surface_set_material(0, _make_material(Color(0.82, 0.84, 0.835), 0.38))

	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	deck.set_smooth_group(0)
	_add_closed_deck(deck, [-2.115, -2.030, -1.875, -1.650, -1.365, -1.020, -0.620, -0.39])
	_add_side_decks_and_cockpit(deck)
	_add_closed_deck(deck, [1.43, 1.70, 1.950, 2.115])
	deck.index()
	deck.generate_normals()
	deck.commit(hull_mesh)
	hull_mesh.surface_set_material(1, _make_material(Color(0.86, 0.87, 0.84), 0.54))

	var cockpit := SurfaceTool.new()
	cockpit.begin(Mesh.PRIMITIVE_TRIANGLES)
	cockpit.set_smooth_group(0)
	_add_cockpit_well(cockpit)
	cockpit.index()
	cockpit.generate_normals()
	cockpit.commit(hull_mesh)
	hull_mesh.surface_set_material(2, _make_material(Color(0.73, 0.755, 0.75), 0.62))

	var molded_edges := SurfaceTool.new()
	molded_edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_gunwale_and_cockpit_coaming(molded_edges)
	molded_edges.index()
	molded_edges.generate_normals()
	molded_edges.commit(hull_mesh)
	hull_mesh.surface_set_material(3, _make_material(Color(0.88, 0.89, 0.865), 0.42))

	var sheer_stripe := SurfaceTool.new()
	sheer_stripe.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_sheer_stripes(sheer_stripe)
	sheer_stripe.index()
	sheer_stripe.generate_normals()
	sheer_stripe.commit(hull_mesh)
	hull_mesh.surface_set_material(4, _make_material(Color(0.11, 0.13, 0.14), 0.5))

	var nonskid := SurfaceTool.new()
	nonskid.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_nonskid_panels(nonskid)
	nonskid.generate_normals()
	nonskid.commit(hull_mesh)
	hull_mesh.surface_set_material(5, _make_material(Color(0.80, 0.81, 0.785), 0.92))
	return hull_mesh


func _station_ring(station: Dictionary) -> PackedVector3Array:
	var z := float(station["z"])
	var width := float(station["width"])
	var deck_y := float(station["deck"])
	var keel_y := float(station["keel"])
	var ring := PackedVector3Array()
	for slice in range(HULL_SECTION_SEGMENTS + 1):
		var side_ratio := -1.0 + 2.0 * float(slice) / float(HULL_SECTION_SEGMENTS)
		var lateral_ratio := absf(side_ratio)
		# A broad, shallow run transitions quickly into the topsides.  This avoids
		# the old barrel-shaped section and gives the hull its sharp ILCA silhouette.
		var height_ratio := 0.0
		if lateral_ratio <= 0.60:
			height_ratio = 0.10 * pow(lateral_ratio / 0.60, 1.8)
		else:
			var chine_ratio := (lateral_ratio - 0.60) / 0.40
			height_ratio = lerpf(0.10, 1.0, smoothstep(0.0, 1.0, chine_ratio))
		var chine_lift := pow(lateral_ratio, 8.0) * 0.010
		ring.append(Vector3(
			width * side_ratio,
			lerpf(keel_y, deck_y, height_ratio) + chine_lift,
			z
		))
	return ring


func _add_transom(surface: SurfaceTool) -> void:
	var ring := _station_ring(_stations.back())
	var center := Vector3(0.0, 0.08, 2.115)
	for index in range(ring.size() - 1):
		_add_triangle(surface, ring[index], center, ring[index + 1])


func _add_closed_deck(surface: SurfaceTool, z_positions: Array) -> void:
	for index in range(z_positions.size() - 1):
		var z_forward := float(z_positions[index])
		var z_aft := float(z_positions[index + 1])
		var forward := _deck_profile_at(z_forward)
		var aft := _deck_profile_at(z_aft)
		for span_index in range(DECK_SPAN_SEGMENTS):
			var ratio_left := -1.0 + 2.0 * float(span_index) / float(DECK_SPAN_SEGMENTS)
			var ratio_right := -1.0 + 2.0 * float(span_index + 1) / float(DECK_SPAN_SEGMENTS)
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
	for index in range(_cockpit_z_positions.size() - 1):
		var z_forward := float(_cockpit_z_positions[index])
		var z_aft := float(_cockpit_z_positions[index + 1])
		var forward := _deck_profile_at(z_forward)
		var aft := _deck_profile_at(z_aft)
		var inner_forward := float(_cockpit_half_widths[index])
		var inner_aft := float(_cockpit_half_widths[index + 1])
		_add_quad(
			surface,
			Vector3(-forward.x, _deck_surface_y(z_forward, -forward.x), z_forward),
			Vector3(-aft.x, _deck_surface_y(z_aft, -aft.x), z_aft),
			Vector3(-inner_aft, _deck_surface_y(z_aft, -inner_aft), z_aft),
			Vector3(-inner_forward, _deck_surface_y(z_forward, -inner_forward), z_forward)
		)
		_add_quad(
			surface,
			Vector3(inner_forward, _deck_surface_y(z_forward, inner_forward), z_forward),
			Vector3(inner_aft, _deck_surface_y(z_aft, inner_aft), z_aft),
			Vector3(aft.x, _deck_surface_y(z_aft, aft.x), z_aft),
			Vector3(forward.x, _deck_surface_y(z_forward, forward.x), z_forward)
		)


func _add_cockpit_well(surface: SurfaceTool) -> void:
	for index in range(_cockpit_z_positions.size() - 1):
		var forward_z := float(_cockpit_z_positions[index])
		var aft_z := float(_cockpit_z_positions[index + 1])
		var forward_width := float(_cockpit_half_widths[index])
		var aft_width := float(_cockpit_half_widths[index + 1])
		var forward_floor_width := maxf(0.07, forward_width - 0.055)
		var aft_floor_width := maxf(0.07, aft_width - 0.055)
		var forward_deck_left := _deck_surface_y(forward_z, -forward_width)
		var aft_deck_left := _deck_surface_y(aft_z, -aft_width)
		var forward_deck_right := _deck_surface_y(forward_z, forward_width)
		var aft_deck_right := _deck_surface_y(aft_z, aft_width)

		var floor_left_forward := Vector3(
			-forward_floor_width,
			_cockpit_floor_y(-forward_floor_width, forward_floor_width, forward_z),
			forward_z
		)
		var floor_left_aft := Vector3(
			-aft_floor_width,
			_cockpit_floor_y(-aft_floor_width, aft_floor_width, aft_z),
			aft_z
		)
		var floor_right_aft := Vector3(
			aft_floor_width,
			_cockpit_floor_y(aft_floor_width, aft_floor_width, aft_z),
			aft_z
		)
		var floor_right_forward := Vector3(
			forward_floor_width,
			_cockpit_floor_y(forward_floor_width, forward_floor_width, forward_z),
			forward_z
		)
		# The moulded cockpit is subtly dished toward its centre and self-bailer;
		# it is not a single perfectly flat quad. More lateral strips also keep the
		# close first-person view from reading as a low-poly tray.
		for floor_index in range(COCKPIT_FLOOR_SEGMENTS):
			var left_ratio := -1.0 + 2.0 * float(floor_index) / float(COCKPIT_FLOOR_SEGMENTS)
			var right_ratio := -1.0 + 2.0 * float(floor_index + 1) / float(COCKPIT_FLOOR_SEGMENTS)
			var forward_left_x := forward_floor_width * left_ratio
			var forward_right_x := forward_floor_width * right_ratio
			var aft_left_x := aft_floor_width * left_ratio
			var aft_right_x := aft_floor_width * right_ratio
			_add_quad(
				surface,
				Vector3(forward_left_x, _cockpit_floor_y(forward_left_x, forward_floor_width, forward_z), forward_z),
				Vector3(aft_left_x, _cockpit_floor_y(aft_left_x, aft_floor_width, aft_z), aft_z),
				Vector3(aft_right_x, _cockpit_floor_y(aft_right_x, aft_floor_width, aft_z), aft_z),
				Vector3(forward_right_x, _cockpit_floor_y(forward_right_x, forward_floor_width, forward_z), forward_z)
			)
		_add_quad(
			surface,
			Vector3(-forward_width, forward_deck_left, forward_z),
			Vector3(-aft_width, aft_deck_left, aft_z),
			floor_left_aft,
			floor_left_forward
		)
		_add_quad(
			surface,
			floor_right_forward,
			floor_right_aft,
			Vector3(aft_width, aft_deck_right, aft_z),
			Vector3(forward_width, forward_deck_right, forward_z)
		)

	var front_z := float(_cockpit_z_positions.front())
	var rear_z := float(_cockpit_z_positions.back())
	var front_width := float(_cockpit_half_widths.front())
	var rear_width := float(_cockpit_half_widths.back())
	var front_floor_width := maxf(0.07, front_width - 0.055)
	var rear_floor_width := maxf(0.07, rear_width - 0.055)
	_add_quad(
		surface,
		Vector3(-front_width, _deck_surface_y(front_z, -front_width), front_z),
		Vector3(-front_floor_width, _cockpit_floor_y(-front_floor_width, front_floor_width, front_z), front_z),
		Vector3(front_floor_width, _cockpit_floor_y(front_floor_width, front_floor_width, front_z), front_z),
		Vector3(front_width, _deck_surface_y(front_z, front_width), front_z)
	)
	_add_quad(
		surface,
		Vector3(-rear_floor_width, _cockpit_floor_y(-rear_floor_width, rear_floor_width, rear_z), rear_z),
		Vector3(-rear_width, _deck_surface_y(rear_z, -rear_width), rear_z),
		Vector3(rear_width, _deck_surface_y(rear_z, rear_width), rear_z),
		Vector3(rear_floor_width, _cockpit_floor_y(rear_floor_width, rear_floor_width, rear_z), rear_z)
	)


func _cockpit_floor_y(x_position: float, half_width: float, z_position: float) -> float:
	var lateral_ratio := clampf(absf(x_position) / maxf(half_width, 0.001), 0.0, 1.0)
	var center_dish := (1.0 - smoothstep(0.0, 1.0, lateral_ratio)) * 0.004
	var bailer_fall := smoothstep(0.45, 1.20, z_position) * 0.002
	return 0.045 - center_dish - bailer_fall


func _deck_profile_at(z_position: float) -> Vector2:
	for index in range(_stations.size() - 1):
		var first := _stations[index]
		var second := _stations[index + 1]
		var first_z := float(first["z"])
		var second_z := float(second["z"])
		if z_position >= first_z and z_position <= second_z:
			var ratio := inverse_lerp(first_z, second_z, z_position)
			return Vector2(
				lerpf(float(first["width"]), float(second["width"]), ratio),
				lerpf(float(first["deck"]), float(second["deck"]), ratio)
			)
	var last: Dictionary = _stations.back()
	return Vector2(float(last["width"]), float(last["deck"]))


func _deck_surface_y(z_position: float, x_position: float) -> float:
	var profile := _deck_profile_at(z_position)
	var lateral_ratio := clampf(absf(x_position) / maxf(profile.x, 0.001), 0.0, 1.0)
	return profile.y + pow(1.0 - lateral_ratio, 1.65) * 0.024


func _add_gunwale_and_cockpit_coaming(surface: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		for index in range(_stations.size() - 1):
			var forward := _stations[index]
			var aft := _stations[index + 1]
			_add_tube_segment(
				surface,
				Vector3(
					float(forward["width"]) * float(side),
					float(forward["deck"]) + 0.012,
					float(forward["z"])
				),
				Vector3(
					float(aft["width"]) * float(side),
					float(aft["deck"]) + 0.012,
					float(aft["z"])
				),
				0.016
			)

	var coaming := PackedVector3Array()
	for index in range(_cockpit_z_positions.size()):
		var z_position := float(_cockpit_z_positions[index])
		coaming.append(Vector3(
			-float(_cockpit_half_widths[index]),
			_deck_surface_y(z_position, -float(_cockpit_half_widths[index])) + 0.018,
			z_position
		))
	for index in range(_cockpit_z_positions.size() - 1, -1, -1):
		var z_position := float(_cockpit_z_positions[index])
		coaming.append(Vector3(
			float(_cockpit_half_widths[index]),
			_deck_surface_y(z_position, float(_cockpit_half_widths[index])) + 0.018,
			z_position
		))
	for index in range(coaming.size()):
		_add_tube_segment(surface, coaming[index], coaming[(index + 1) % coaming.size()], 0.022)


func _add_sheer_stripes(surface: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		for index in range(1, _stations.size() - 1):
			var forward := _stations[index]
			var aft := _stations[index + 1]
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


func _add_nonskid_panels(surface: SurfaceTool) -> void:
	# The real deck is moulded rather than painted. A shallow, rough overlay
	# supplies the characteristic foredeck and side-deck breakup at game scale.
	var foredeck_z := [-1.86, -1.58, -1.26, -0.92, -0.62, -0.43]
	var lateral_ratios := [-0.80, -0.40, 0.0, 0.40, 0.80]
	for index in range(foredeck_z.size() - 1):
		var z_forward := float(foredeck_z[index])
		var z_aft := float(foredeck_z[index + 1])
		var forward := _deck_profile_at(z_forward)
		var aft := _deck_profile_at(z_aft)
		for span_index in range(lateral_ratios.size() - 1):
			var forward_left_x := forward.x * float(lateral_ratios[span_index])
			var forward_right_x := forward.x * float(lateral_ratios[span_index + 1])
			var aft_left_x := aft.x * float(lateral_ratios[span_index])
			var aft_right_x := aft.x * float(lateral_ratios[span_index + 1])
			_add_quad(
				surface,
				Vector3(forward_left_x, _deck_surface_y(z_forward, forward_left_x) + 0.004, z_forward),
				Vector3(aft_left_x, _deck_surface_y(z_aft, aft_left_x) + 0.004, z_aft),
				Vector3(aft_right_x, _deck_surface_y(z_aft, aft_right_x) + 0.004, z_aft),
				Vector3(forward_right_x, _deck_surface_y(z_forward, forward_right_x) + 0.004, z_forward)
			)

	for side in [-1.0, 1.0]:
		for index in range(_cockpit_z_positions.size() - 1):
			var z_forward := float(_cockpit_z_positions[index])
			var z_aft := float(_cockpit_z_positions[index + 1])
			var forward := _deck_profile_at(z_forward)
			var aft := _deck_profile_at(z_aft)
			var inner_forward := float(_cockpit_half_widths[index]) + 0.055
			var inner_aft := float(_cockpit_half_widths[index + 1]) + 0.055
			var outer_forward := forward.x - 0.060
			var outer_aft := aft.x - 0.060
			_add_quad(
				surface,
				Vector3(side * inner_forward, _deck_surface_y(z_forward, side * inner_forward) + 0.004, z_forward),
				Vector3(side * inner_aft, _deck_surface_y(z_aft, side * inner_aft) + 0.004, z_aft),
				Vector3(side * outer_aft, _deck_surface_y(z_aft, side * outer_aft) + 0.004, z_aft),
				Vector3(side * outer_forward, _deck_surface_y(z_forward, side * outer_forward) + 0.004, z_forward)
			)


func _add_tube_segment(surface: SurfaceTool, from: Vector3, to: Vector3, radius: float) -> void:
	var direction := (to - from).normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(direction).normalized()
	for side_index in range(TRIM_TUBE_SIDES):
		var next_side := (side_index + 1) % TRIM_TUBE_SIDES
		var angle := TAU * float(side_index) / float(TRIM_TUBE_SIDES)
		var next_angle := TAU * float(next_side) / float(TRIM_TUBE_SIDES)
		var offset := (side * cos(angle) + up * sin(angle)) * radius
		var next_offset := (side * cos(next_angle) + up * sin(next_angle)) * radius
		_add_quad(surface, from + offset, from + next_offset, to + next_offset, to + offset)


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(surface, a, b, c)
	_add_triangle(surface, a, c, d)


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
