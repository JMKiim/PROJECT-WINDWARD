class_name IlcaHull
extends MeshInstance3D

const HULL_LENGTH_METERS := 4.23
const HULL_BEAM_METERS := 1.37
const TRIM_TUBE_SIDES := 16
const DECK_SPAN_SEGMENTS := 12
const HULL_SECTION_SEGMENTS := 24
const COCKPIT_FLOOR_SEGMENTS := 16
const HULL_LONGITUDINAL_SEGMENTS := 56
const COCKPIT_LONGITUDINAL_SEGMENTS := 32
const WATERLINE_DATUM_Y := -0.06

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
var _cockpit_half_widths := [0.076, 0.120, 0.165, 0.205, 0.275, 0.350, 0.415, 0.425, 0.420, 0.315, 0.070]


func _ready() -> void:
	mesh = _build_hull_mesh()


func _build_hull_mesh() -> ArrayMesh:
	var hull_mesh := ArrayMesh.new()
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
	shell.generate_normals()
	shell.commit(hull_mesh)
	hull_mesh.surface_set_material(0, _make_material(Color(0.97, 0.975, 0.96), 0.38))

	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	deck.set_smooth_group(0)
	_add_closed_deck(deck, _range_positions(-2.115, float(_cockpit_z_positions.front()), 28))
	_add_side_decks_and_cockpit(deck)
	_add_closed_deck(deck, _range_positions(float(_cockpit_z_positions.back()), 2.115, 12))
	deck.index()
	deck.generate_normals()
	deck.commit(hull_mesh)
	hull_mesh.surface_set_material(1, _make_material(Color(0.975, 0.978, 0.965), 0.54))

	var cockpit := SurfaceTool.new()
	cockpit.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_cockpit_well(cockpit)
	cockpit.index()
	# _add_cockpit_well() authors the normals explicitly. Regenerating them here
	# would blend the floor and walls back together at their shared corners.
	cockpit.commit(hull_mesh)
	# The cockpit is the same gel-coated GRP moulding as the deck.  Its slightly
	# higher roughness carries the non-slip/readability difference without the
	# old grey-blue colour break that made it look like a separate insert. A
	# restrained neutral bounce term compensates for this prototype's single sun:
	# otherwise the deep well receives mostly blue sky ambient.
	var cockpit_material := _make_material(Color(0.975, 0.978, 0.965), 0.58)
	cockpit_material.emission_enabled = true
	cockpit_material.emission = Color(0.975, 0.978, 0.965)
	cockpit_material.emission_energy_multiplier = 0.20
	hull_mesh.surface_set_material(2, cockpit_material)

	var molded_edges := SurfaceTool.new()
	molded_edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_gunwale_and_cockpit_coaming(molded_edges)
	molded_edges.index()
	molded_edges.generate_normals()
	molded_edges.commit(hull_mesh)
	hull_mesh.surface_set_material(3, _make_material(Color(0.97, 0.97, 0.95), 0.42))

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
	hull_mesh.surface_set_material(5, _make_material(Color(0.925, 0.93, 0.91), 0.94))
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
		# The measured ILCA sections read as a shallow elliptical bilge rather
		# than a flat pan with a hard chine. A small center flattening keeps the
		# planing run without turning the side profile into a barrel.
		var elliptical := 1.0 - sqrt(maxf(0.0, 1.0 - lateral_ratio * lateral_ratio))
		var center_flatten := 0.018 * pow(lateral_ratio, 1.7) * (1.0 - lateral_ratio)
		var height_ratio := clampf(elliptical + center_flatten, 0.0, 1.0)
		ring.append(Vector3(
			width * side_ratio,
			lerpf(keel_y, deck_y, height_ratio),
			z
		))
	return ring


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
	for sample_index in range(COCKPIT_LONGITUDINAL_SEGMENTS + 1):
		var z_position := lerpf(from_z, to_z, float(sample_index) / float(COCKPIT_LONGITUDINAL_SEGMENTS))
		samples.append({"z": z_position, "width": _cockpit_half_width_at(z_position)})
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
	var ring := _station_ring(_stations.back())
	var center := Vector3(0.0, (float(_stations.back()["deck"]) + float(_stations.back()["keel"])) * 0.5, 2.115)
	for index in range(ring.size() - 1):
		_add_triangle(surface, ring[index], ring[index + 1], center)
	_add_triangle(surface, ring[ring.size() - 1], ring[0], center)


func _add_closed_deck(surface: SurfaceTool, z_positions: Array) -> void:
	for index in range(z_positions.size() - 1):
		var z_forward := float(z_positions[index])
		var z_aft := float(z_positions[index + 1])
		var forward := _deck_profile_at(z_forward)
		var aft := _deck_profile_at(z_aft)
		if forward.x <= 0.0001:
			var apex := Vector3(0.0, _deck_surface_y(z_forward, 0.0), z_forward)
			for span_index in range(DECK_SPAN_SEGMENTS):
				var ratio_left := -1.0 + 2.0 * float(span_index) / float(DECK_SPAN_SEGMENTS)
				var ratio_right := -1.0 + 2.0 * float(span_index + 1) / float(DECK_SPAN_SEGMENTS)
				var aft_left_x := aft.x * ratio_left
				var aft_right_x := aft.x * ratio_right
				_add_triangle(
					surface,
					apex,
					Vector3(aft_left_x, _deck_surface_y(z_aft, aft_left_x), z_aft),
					Vector3(aft_right_x, _deck_surface_y(z_aft, aft_right_x), z_aft)
				)
			continue
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
	var cockpit_samples := _cockpit_samples()
	for index in range(cockpit_samples.size() - 1):
		var z_forward := float(cockpit_samples[index]["z"])
		var z_aft := float(cockpit_samples[index + 1]["z"])
		var forward := _deck_profile_at(z_forward)
		var aft := _deck_profile_at(z_aft)
		var inner_forward := float(cockpit_samples[index]["width"])
		var inner_aft := float(cockpit_samples[index + 1]["width"])
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
	var cockpit_samples := _cockpit_samples()
	for index in range(cockpit_samples.size() - 1):
		var forward_z := float(cockpit_samples[index]["z"])
		var aft_z := float(cockpit_samples[index + 1]["z"])
		var forward_width := float(cockpit_samples[index]["width"])
		var aft_width := float(cockpit_samples[index + 1]["width"])
		var forward_floor_width := maxf(0.015, forward_width - 0.055)
		var aft_floor_width := maxf(0.015, aft_width - 0.055)
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
			_add_cockpit_floor_quad(
				surface,
				Vector3(forward_left_x, _cockpit_floor_y(forward_left_x, forward_floor_width, forward_z), forward_z),
				Vector3(aft_left_x, _cockpit_floor_y(aft_left_x, aft_floor_width, aft_z), aft_z),
				Vector3(aft_right_x, _cockpit_floor_y(aft_right_x, aft_floor_width, aft_z), aft_z),
				Vector3(forward_right_x, _cockpit_floor_y(forward_right_x, forward_floor_width, forward_z), forward_z)
			)
		_add_quad_with_face_normal(
			surface,
			Vector3(-forward_width, forward_deck_left, forward_z),
			Vector3(-aft_width, aft_deck_left, aft_z),
			floor_left_aft,
			floor_left_forward
		)
		_add_quad_with_face_normal(
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
	var front_floor_width := maxf(0.015, front_width - 0.055)
	var rear_floor_width := maxf(0.015, rear_width - 0.055)
	_add_quad_with_face_normal(
		surface,
		Vector3(-front_width, _deck_surface_y(front_z, -front_width), front_z),
		Vector3(-front_floor_width, _cockpit_floor_y(-front_floor_width, front_floor_width, front_z), front_z),
		Vector3(front_floor_width, _cockpit_floor_y(front_floor_width, front_floor_width, front_z), front_z),
		Vector3(front_width, _deck_surface_y(front_z, front_width), front_z)
	)
	_add_quad_with_face_normal(
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


func _cockpit_floor_surface_y(x_position: float, z_position: float) -> float:
	var half_width := maxf(0.015, _cockpit_half_width_at(z_position) - 0.055)
	return _cockpit_floor_y(clampf(x_position, -half_width, half_width), half_width, z_position)


func _cockpit_floor_normal(position: Vector3) -> Vector3:
	var epsilon := 0.002
	var front_z := float(_cockpit_z_positions.front())
	var rear_z := float(_cockpit_z_positions.back())
	var z_before := maxf(front_z, position.z - epsilon)
	var z_after := minf(rear_z, position.z + epsilon)
	var slope_x := (
		_cockpit_floor_surface_y(position.x + epsilon, position.z)
		- _cockpit_floor_surface_y(position.x - epsilon, position.z)
	) / (2.0 * epsilon)
	var slope_z := (
		_cockpit_floor_surface_y(position.x, z_after)
		- _cockpit_floor_surface_y(position.x, z_before)
	) / maxf(z_after - z_before, epsilon)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()


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
	var sampled_stations := _sampled_stations()
	for side in [-1.0, 1.0]:
		# Let the gunwale taper into the pointed bow instead of overlapping two
		# full-radius tubes at the 2 mm numerical shell ring.
		for index in range(1, sampled_stations.size() - 1):
			var forward := sampled_stations[index]
			var aft := sampled_stations[index + 1]
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
				0.010
			)
	_add_tube_segment(
		surface,
		Vector3(-float(_stations.back()["width"]), float(_stations.back()["deck"]) + 0.012, 2.115),
		Vector3(float(_stations.back()["width"]), float(_stations.back()["deck"]) + 0.012, 2.115),
		0.009
	)

	var cockpit_samples := _cockpit_samples()
	var coaming := PackedVector3Array()
	for index in range(cockpit_samples.size()):
		var z_position := float(cockpit_samples[index]["z"])
		var half_width := float(cockpit_samples[index]["width"])
		coaming.append(Vector3(
			-half_width,
			_deck_surface_y(z_position, -half_width) + 0.015,
			z_position
		))
	for index in range(cockpit_samples.size() - 1, -1, -1):
		var z_position := float(cockpit_samples[index]["z"])
		var half_width := float(cockpit_samples[index]["width"])
		coaming.append(Vector3(
			half_width,
			_deck_surface_y(z_position, half_width) + 0.015,
			z_position
		))
	for index in range(coaming.size()):
		_add_tube_segment(surface, coaming[index], coaming[(index + 1) % coaming.size()], 0.010)


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
				Vector3(forward_left_x, _deck_surface_y(z_forward, forward_left_x) + 0.001, z_forward),
				Vector3(aft_left_x, _deck_surface_y(z_aft, aft_left_x) + 0.001, z_aft),
				Vector3(aft_right_x, _deck_surface_y(z_aft, aft_right_x) + 0.001, z_aft),
				Vector3(forward_right_x, _deck_surface_y(z_forward, forward_right_x) + 0.001, z_forward)
			)

	var cockpit_samples := _cockpit_samples()
	for side in [-1.0, 1.0]:
		for index in range(cockpit_samples.size() - 1):
			var z_forward := float(cockpit_samples[index]["z"])
			var z_aft := float(cockpit_samples[index + 1]["z"])
			var forward := _deck_profile_at(z_forward)
			var aft := _deck_profile_at(z_aft)
			var inner_forward := float(cockpit_samples[index]["width"]) + 0.045
			var inner_aft := float(cockpit_samples[index + 1]["width"]) + 0.045
			var outer_forward := forward.x - 0.060
			var outer_aft := aft.x - 0.060
			_add_quad(
				surface,
				Vector3(side * inner_forward, _deck_surface_y(z_forward, side * inner_forward) + 0.001, z_forward),
				Vector3(side * inner_aft, _deck_surface_y(z_aft, side * inner_aft) + 0.001, z_aft),
				Vector3(side * outer_aft, _deck_surface_y(z_aft, side * outer_aft) + 0.001, z_aft),
				Vector3(side * outer_forward, _deck_surface_y(z_forward, side * outer_forward) + 0.001, z_forward)
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
	surface.set_normal(normal_a)
	surface.add_vertex(a)
	surface.set_normal(normal_b)
	surface.add_vertex(b)
	surface.set_normal(normal_c)
	surface.add_vertex(c)


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
