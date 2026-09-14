class_name IlcaHardwarePart
extends MeshInstance3D

enum PartKind {
	DECK_RATCHET,
	BOOM_BLOCK,
	TRAVELLER_BLOCK,
	CONTROL_BLOCK,
	DAGGERBOARD_CASE,
	DAGGERBOARD_HEAD,
	DAGGERBOARD_HANDLE,
	GRAB_RAIL,
	CAM_CLEAT,
	SELF_BAILER,
	EYE_STRAP,
	GOOSENECK,
	SAIL_CRINGLE,
	CLEW_STRAP,
	BOOM_END_FITTING,
	RUDDER_HEAD,
	TILLER,
	TILLER_EXTENSION,
	TRAVELLER_FAIRLEAD,
	TRAVELLER_CLEAT,
	RUDDER_GUDGEON,
	HIKING_STRAP,
	HIKING_STRAP_PLATE,
	COCKPIT_DRAIN_BUNG,
}

@export var part_kind: PartKind = PartKind.DECK_RATCHET
@export var has_becket := false
@export var forward_tail_center := Vector3(0.0, -0.003, -0.545)
@export var forward_tail_length := 0.120
@export_range(.50,1.50,.01) var extension_tube_metres := 1.070

const ROUND_SEGMENTS := 16
const TILLER_EXTENSION_GRIP_MIN_DISTANCE := 0.60
const TILLER_EXTENSION_GRIP_MAX_DISTANCE := 1.04
const TILLER_EXTENSION_JOINT_METRES := .030
const TILLER_EXTENSION_END_HAND_MARGIN := .060
const DECK_RATCHET_SHEAVE_DIAMETER := 0.057
const BLOCK_SHEAVE_WIDTH := 0.013
const BLOCK_CHEEK_CLEARANCE := 0.001
const BLOCK_CHEEK_THICKNESS := 0.0035
const BLOCK_GROOVE_DEPTH := 0.0048
const BLOCK_GROOVE_HALF_WIDTH := 0.0055
const DECK_LEAD_PREFIX_POINTS := 26
const TRAVELLER_MAIN_SHEAVE_DIAMETER := 0.040
const TRAVELLER_LINE_SHEAVE_DIAMETER := 0.025
# The linked blocks articulate at right angles: the small sheave follows the
# deck traveller and the large sheave follows the vertical mainsheet purchase.
const TRAVELLER_LINE_SHEAVE_CENTER := Vector3(-0.002, 0.0, 0.0)
const TRAVELLER_MAIN_SHEAVE_CENTER := Vector3(0.045, 0.0, 0.0)

var _black := _material(Color(0.025, 0.030, 0.032), 0.42)
var _soft_black := _material(Color(0.055, 0.060, 0.062), 0.64)
var _white := _material(Color(0.88, 0.895, 0.875), 0.43)
var _stainless := _material(Color(0.54, 0.58, 0.60), 0.21, 0.88)
var _sheave := _material(Color(0.12, 0.13, 0.13), 0.34)
var _gold_sheave := _material(Color(0.80, 0.47, 0.08), 0.32, 0.48)
var _rubber := _material(Color(0.025, 0.027, 0.028), 0.88)
var _rope := _material(Color(0.08, 0.16, 0.22), 0.76)
var _label_blue := _material(Color(0.08, 0.30, 0.57), 0.50)
var _swivel_parts: Dictionary = {}
var _swivel_yaw := INF


func rope_anchor_local(anchor_name: StringName = &"sheave") -> Vector3:
	# A single hardware contract keeps the visible rope on the actual sheave,
	# becket, or bridge even when a fitting is translated or rotated in the
	# scene. Callers transform this local point through the fitting node.
	match part_kind:
		PartKind.DECK_RATCHET:
			var sheave_radius := DECK_RATCHET_SHEAVE_DIAMETER * 0.5
			return Vector3(0.0, sheave_radius * 2.55 * 0.48, 0.0)
		PartKind.BOOM_BLOCK:
			if anchor_name == &"becket" and has_becket:
				return Vector3(0.0, -0.025 * 0.32, 0.0)
			return Vector3(0.0, 0.025 * 2.55 * 0.48, 0.0)
		PartKind.TRAVELLER_BLOCK:
			if anchor_name == &"traveller_sheave":
				return TRAVELLER_LINE_SHEAVE_CENTER
			# The mainsheet and traveller line use separate linked blocks, not two
			# equal sheaves sharing one axle.
			return TRAVELLER_MAIN_SHEAVE_CENTER
		PartKind.CONTROL_BLOCK:
			return Vector3(0.0, 0.015 * 2.55 * 0.48, 0.0)
		PartKind.DAGGERBOARD_HANDLE:
			# Centre of the visible rope grip joining the two board-head holes.
			return Vector3(0.041, 0.050, -0.025)
		PartKind.CAM_CLEAT:
			if anchor_name == &"fairlead":
				return Vector3(0.0, 0.052, 0.028)
			# The working line is held between the two visible cam jaws.
			return Vector3(0.0, 0.031, -0.012)
		PartKind.EYE_STRAP:
			return Vector3(0.0, 0.038, 0.0)
		PartKind.SAIL_CRINGLE:
			return Vector3.ZERO
		PartKind.CLEW_STRAP:
			return Vector3(0.0, 0.068, 0.0)
		PartKind.BOOM_END_FITTING:
			return Vector3(0.0, 0.025, -0.012)
		PartKind.TRAVELLER_FAIRLEAD:
			return Vector3(0.0, 0.030, 0.0)
		PartKind.TRAVELLER_CLEAT:
			return Vector3(0.0, 0.028, -0.008)
		PartKind.GOOSENECK:
			return Vector3(0.0, 0.0, 0.105)
		PartKind.HIKING_STRAP:
			if anchor_name == &"aft_loop":
				return Vector3(0.0, 0.018, 0.555)
	return Vector3.ZERO


func rope_anchor_global(anchor_name: StringName = &"sheave") -> Vector3:
	return to_global(rope_anchor_local(anchor_name))


func deck_lead_route(path: PackedVector3Array, rope_radius: float) -> PackedVector3Array:
	# Display-only fitting contact: retain every remote path point and the
	# authored axle datum, replacing only the first 10 cm with a groove exit.
	# Input and output are expressed in this fitting's parent coordinates.
	if part_kind != PartKind.DECK_RATCHET or path.size() < 2: return path
	var center := rope_anchor_local()
	var join := 1
	while join < path.size() - 1 and (transform.affine_inverse() * path[join]).distance_to(center) < 0.10:
		join += 1
	var target := transform.affine_inverse() * path[join]
	var preceding := transform.affine_inverse() * path[join - 1]
	var segment := target - preceding
	var finish_direction := segment.normalized()
	# A fixed-radius join stays continuous as authored samples cross 10 cm.
	if target.distance_to(center) > 0.10 and segment.length_squared() > 1e-12:
		var relative := preceding - center
		var projection := relative.dot(finish_direction)
		var along_segment := -projection + sqrt(maxf(0, projection * projection - relative.length_squared() + 0.01))
		target = preceding + finish_direction * clampf(along_segment, 0.0, segment.length())
	if target.distance_squared_to(transform.affine_inverse() * path[join]) < 1e-12 and join < path.size() - 1:
		join += 1
	var vector := target - center
	var horizontal := Vector3(vector.x, 0, vector.z).normalized()
	if horizontal.is_zero_approx(): horizontal = Vector3.BACK
	var yaw := atan2(horizontal.x, horizontal.z)
	var turn := Basis(Vector3.UP, yaw)
	if not is_equal_approx(yaw, _swivel_yaw):
		for part in _swivel_parts:
			var rest: Transform3D = _swivel_parts[part]
			part.transform = Transform3D(turn * rest.basis, center + turn * (rest.origin - center))
		_swivel_yaw = yaw
	var radius := DECK_RATCHET_SHEAVE_DIAMETER * 0.5 - BLOCK_GROOVE_DEPTH + rope_radius + 0.0003
	var distance := vector.length()
	if distance <= radius: return path
	var along := vector / distance
	var axle := turn.x
	var perpendicular := axle.cross(along).normalized()
	if perpendicular.y > 0: perpendicular = -perpendicular
	var radial := along * radius / distance + perpendicular * sqrt(1.0 - radius * radius / (distance * distance))
	var angle := atan2(radial.dot(horizontal), radial.y)
	# Reach the lower tangent around the opposite side of the upper rim.
	if angle > 0: angle -= TAU
	var result := PackedVector3Array()
	for index in 17:
		var theta := angle * float(index) / 16
		result.append(transform * (center + (Vector3.UP * cos(theta) + horizontal * sin(theta)) * radius))
	# Clear the rim along its tangent before blending back to the authored
	# lead. Matching the remote tangent avoids a sharp corner at the join.
	var tangent_start := center + radial * radius
	var exit_direction := (target - tangent_start).normalized()
	var start := tangent_start + exit_direction * minf(0.025, (target - tangent_start).length() * 0.3)
	result.append(transform * start)
	var handle := start.distance_to(target) / 3.0
	var control1 := start + exit_direction * handle
	var control2 := target - finish_direction * handle
	for index in range(1, 9):
		var t := float(index) / 8
		var u := 1.0 - t
		result.append(transform * (start * u * u * u + control1 * 3 * u * u * t + control2 * 3 * u * t * t + target * t * t * t))
	result.append_array(path.slice(join))
	return result


func _ready() -> void:
	mesh = null
	match part_kind:
		PartKind.DECK_RATCHET:
			_build_block(DECK_RATCHET_SHEAVE_DIAMETER * 0.5, true)
		PartKind.BOOM_BLOCK:
			_build_block(0.025, false)
		PartKind.TRAVELLER_BLOCK:
			_build_traveller_block()
		PartKind.CONTROL_BLOCK:
			_build_block(0.015, false)
		PartKind.DAGGERBOARD_CASE:
			_build_daggerboard_case()
		PartKind.DAGGERBOARD_HEAD:
			_build_daggerboard_head()
		PartKind.DAGGERBOARD_HANDLE:
			_build_daggerboard_handle()
		PartKind.GRAB_RAIL:
			_build_grab_rail()
		PartKind.CAM_CLEAT:
			_build_cam_cleat()
		PartKind.SELF_BAILER:
			_build_self_bailer()
		PartKind.EYE_STRAP:
			_build_eye_strap()
		PartKind.GOOSENECK:
			_build_gooseneck()
		PartKind.SAIL_CRINGLE:
			_build_sail_cringle()
		PartKind.CLEW_STRAP:
			_build_clew_strap()
		PartKind.BOOM_END_FITTING:
			_build_boom_end_fitting()
		PartKind.RUDDER_HEAD:
			_build_rudder_head()
		PartKind.TILLER:
			_build_tiller()
		PartKind.TILLER_EXTENSION:
			_build_tiller_extension()
		PartKind.TRAVELLER_FAIRLEAD:
			_build_traveller_fairlead()
		PartKind.TRAVELLER_CLEAT:
			_build_traveller_cleat()
		PartKind.RUDDER_GUDGEON:
			_build_rudder_gudgeon()
		PartKind.HIKING_STRAP:
			_build_hiking_strap()
		PartKind.HIKING_STRAP_PLATE:
			_build_hiking_strap_plate()
		PartKind.COCKPIT_DRAIN_BUNG:
			_build_cockpit_drain_bung()


func _build_block(sheave_radius: float, stand_up: bool) -> void:
	# Diameter, groove and cheek spacing are independent dimensions. The
	# swivel centre retains the existing boat and authored-motion datum.
	var center := rope_anchor_local()
	var small := part_kind == PartKind.CONTROL_BLOCK
	var width := 0.009 if small else BLOCK_SHEAVE_WIDTH
	var thickness := 0.0025 if small else BLOCK_CHEEK_THICKNESS
	var offset := width * 0.5 + BLOCK_CHEEK_CLEARANCE + thickness * 0.5
	var direction := -1.0 if stand_up else 1.0
	if stand_up:
		_add_box("EyeStrapBase", Vector3(0.054, 0.006, 0.024), Vector3(0, -0.047, 0), _stainless)
		for side in [-1.0, 1.0]:
			_add_cylinder("MountScrew%d" % int(side), 0.003, 0.004, Vector3(side * 0.019, -0.0425, 0), _stainless)
		_add_cylinder("StandUpBoot", 0.025, 0.015, Vector3(0, -0.0315, 0), _rubber, Vector3.ZERO, 0.010)
		for index in 48:
			var a := float(index) / 48.0
			var b := float(index + 1) / 48.0
			_add_tube_between("Spring%02d" % index, Vector3(cos(a * TAU * 3) * 0.009, -0.028 + a * 0.016, sin(a * TAU * 3) * 0.009), Vector3(cos(b * TAU * 3) * 0.009, -0.028 + b * 0.016, sin(b * TAU * 3) * 0.009), 0.0008, _stainless)
	var first_body := get_child_count()
	_add_grooved_sheave("Sheave", sheave_radius, width, center, _material(Color("aa9780"), 0.40, 0.65) if stand_up else _sheave)
	for side in [-1.0, 1.0]:
		var prefix := "Port" if side < 0 else "Starboard"
		var position_on_side := center + Vector3(side * offset, 0, 0)
		# Rounded cheek lobe and an open, ribbed neck leave actual windows.
		var profile := PackedVector2Array()
		for index in 48:
			var angle := TAU * float(index) / 48.0
			profile.append(Vector2(cos(angle), sin(angle)) * sheave_radius * 0.92)
		_add_profile_part(prefix + "Cheek", profile, thickness, position_on_side, _black, 0.00065)
		for edge in [-1.0, 1.0]:
			var rail := PackedVector2Array([Vector2(edge * 0.30, direction * 1.66), Vector2(edge * 0.46, direction * 1.66), Vector2(edge * 0.91, direction * 0.27), Vector2(edge * 0.67, direction * 0.35)])
			for index in rail.size(): rail[index] *= sheave_radius
			_add_profile_part(prefix + "Neck%d" % int(edge), rail, thickness, position_on_side, _black, 0.0004)
		_add_box(prefix + "NeckSpine", Vector3(thickness, sheave_radius * 1.1, sheave_radius * 0.14), position_on_side + Vector3(0, direction * sheave_radius * 1.10, 0), _black)
		_add_cylinder(prefix + "AxleCap", 0.0018, sheave_radius * 0.15, position_on_side + Vector3(side * (thickness * 0.5 + 0.0009), 0, 0), _stainless, Vector3(0, 0, PI * 0.5))
		if stand_up:
			_add_box(prefix + "RatchetSwitch", Vector3(0.002, 0.005, 0.012), position_on_side + Vector3(side * (thickness * 0.5 + 0.001), 0.011, 0), _soft_black, Vector3(deg_to_rad(-20), 0, 0))
	var neck := center + Vector3(0, direction * sheave_radius * 1.60, 0)
	_add_box("HeadBridge", Vector3(offset * 2 + thickness, sheave_radius * 0.18, sheave_radius * 0.85), neck, _black)
	_add_cylinder("Axle", offset * 2, 0.0025, center, _stainless, Vector3(0, 0, PI * 0.5))
	if not stand_up:
		_add_tube_between("AttachmentStrop", neck + Vector3(-0.006, 0.003, 0), neck + Vector3(0.006, 0.003, 0), 0.002, _stainless)
	if has_becket:
		var becket := rope_anchor_local(&"becket")
		_add_tube_between("Becket", becket - Vector3(0.008, 0, 0), becket + Vector3(0.008, 0, 0), 0.002, _stainless)
		for side in [-1.0, 1.0]:
			_add_tube_between("BecketLink%d" % int(side), center + Vector3(side * offset, -sheave_radius * 0.70, 0), becket + Vector3(side * 0.008, 0, 0), 0.0018, _stainless)
	if stand_up:
		for index in range(first_body, get_child_count()):
			var part := get_child(index) as Node3D
			_swivel_parts[part] = part.transform


func _add_profile_part(part_name: String, outline: PackedVector2Array, thickness: float, origin: Vector3, material: Material, bevel := 0.0) -> MeshInstance3D:
	var profile := outline.duplicate()
	if Geometry2D.is_polygon_clockwise(profile): profile.reverse()
	var inset := PackedVector2Array()
	for index in profile.size():
		var previous := (profile[index] - profile[(index - 1 + profile.size()) % profile.size()]).normalized()
		var following := (profile[(index + 1) % profile.size()] - profile[index]).normalized()
		var inward := Vector2(-previous.y, previous.x) + Vector2(-following.y, following.x)
		inward = inward.normalized()
		var denominator := maxf(0.12, inward.dot(Vector2(-following.y, following.x)))
		inset.append(profile[index] + inward * bevel / denominator)
	# Millimetre coordinates keep the triangulator's epsilon below the small
	# concave insert throat. Geometry is still stored in metres.
	var triangulation_points := PackedVector2Array()
	for point in inset: triangulation_points.append(point * 1000.0)
	var triangles := Geometry2D.triangulate_polygon(triangulation_points)
	assert(not triangles.is_empty(), "Solid outline cannot be triangulated")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for index in range(0, triangles.size(), 3):
			var ids := [triangles[index], triangles[index + 1], triangles[index + 2]]
			if side < 0: ids.reverse()
			for id in ids:
				surface.set_normal(Vector3.RIGHT * side)
				surface.add_vertex(Vector3(side * thickness * 0.5, inset[id].y, inset[id].x))
		if bevel > 0:
			for index in profile.size():
				var next := (index + 1) % profile.size()
				_surface_quad(surface, Vector3(side * thickness * 0.5, inset[index].y, inset[index].x), Vector3(side * thickness * 0.5, inset[next].y, inset[next].x), Vector3(side * (thickness * 0.5 - bevel), profile[next].y, profile[next].x), Vector3(side * (thickness * 0.5 - bevel), profile[index].y, profile[index].x), Vector3.RIGHT * side)
	for index in profile.size():
		var next := (index + 1) % profile.size()
		var edge := profile[next] - profile[index]
		var normal := Vector3(0, -edge.x, edge.y).normalized()
		var half := thickness * 0.5 - bevel
		_surface_quad(surface, Vector3(-half, profile[index].y, profile[index].x), Vector3(-half, profile[next].y, profile[next].x), Vector3(half, profile[next].y, profile[next].x), Vector3(half, profile[index].y, profile[index].x), normal)
	surface.index()
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.position = origin
	add_child(instance)
	return instance


func _surface_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var points := [a, b, c, a, c, d]
	if normal.dot(outward) > 0:
		points = [a, c, b, a, d, c]
	else:
		normal = -normal
	for point in points:
		surface.set_normal(normal)
		surface.add_vertex(point)


func groove_radius_at(axial: float, radius: float, width: float) -> float:
	var half_groove := minf(BLOCK_GROOVE_HALF_WIDTH, width * 0.43)
	var depth := minf(BLOCK_GROOVE_DEPTH, half_groove * 0.873)
	var x := absf(axial)
	if x >= half_groove: return radius
	var curve := half_groove - sqrt(maxf(0, half_groove * half_groove - x * x))
	return minf(radius, radius - depth + curve)


func _add_grooved_sheave(part_name: String, radius: float, width: float, center: Vector3, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 24:
		var x0 := lerpf(-width * 0.5, width * 0.5, float(row) / 24)
		var x1 := lerpf(-width * 0.5, width * 0.5, float(row + 1) / 24)
		for index in 96:
			var a := TAU * float(index) / 96
			var b := TAU * float(index + 1) / 96
			var r0 := groove_radius_at(x0, radius, width)
			var r1 := groove_radius_at(x1, radius, width)
			var normal := Vector3(0, cos((a + b) * 0.5), sin((a + b) * 0.5))
			_surface_quad(surface, Vector3(x0, cos(a) * r0, sin(a) * r0), Vector3(x1, cos(a) * r1, sin(a) * r1), Vector3(x1, cos(b) * r1, sin(b) * r1), Vector3(x0, cos(b) * r0, sin(b) * r0), normal)
	for side in [-1.0, 1.0]:
		for index in 96:
			var a := TAU * float(index) / 96
			var b := TAU * float(index + 1) / 96
			_surface_quad(surface, Vector3(side * width * 0.5, cos(a) * 0.003, sin(a) * 0.003), Vector3(side * width * 0.5, cos(a) * radius, sin(a) * radius), Vector3(side * width * 0.5, cos(b) * radius, sin(b) * radius), Vector3(side * width * 0.5, cos(b) * 0.003, sin(b) * 0.003), Vector3.RIGHT * side)
	surface.index()
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.position = center
	add_child(instance)


func _build_traveller_block() -> void:
	# Ronstan's class-approved ILCA traveller is a 40 mm mainsheet block linked
	# to a 25 mm traveller-line block. Their perpendicular axle directions let
	# each rope run in its own load plane while the stainless links articulate.
	var main_radius := TRAVELLER_MAIN_SHEAVE_DIAMETER * 0.5
	var line_radius := TRAVELLER_LINE_SHEAVE_DIAMETER * 0.5
	var main_cheek_offset := 0.012
	var line_cheek_offset := 0.010
	var main_cheek_profile := _block_cheek_profile(main_radius, main_radius * 1.72)
	var line_cheek_profile := _block_cheek_profile(line_radius, line_radius * 1.72)

	_add_cylinder(
		"MainsheetSheave",
		main_cheek_offset * 2.0,
		main_radius,
		TRAVELLER_MAIN_SHEAVE_CENTER,
		_sheave
	)
	for side in [-1.0, 1.0]:
		var main_cheek := _add_extruded_profile(
			"MainsheetPortCheek" if side < 0.0 else "MainsheetStarboardCheek",
			main_cheek_profile,
			0.006,
			_black
		)
		# Profile extrusion is along local X; rotate it so the linked mainsheet
		# block cheeks sit either side of the Y-axis sheave.
		main_cheek.rotation.z = PI * 0.5
		main_cheek.position = TRAVELLER_MAIN_SHEAVE_CENTER + Vector3(0.0, side * main_cheek_offset, 0.0)
	_add_cylinder(
		"MainsheetAxle",
		main_cheek_offset * 2.5,
		main_radius * 0.13,
		TRAVELLER_MAIN_SHEAVE_CENTER,
		_stainless
	)
	_add_box(
		"MainsheetHeadBridge",
		Vector3(main_radius * 0.30, main_cheek_offset * 2.35, main_radius * 1.72),
		TRAVELLER_MAIN_SHEAVE_CENTER + Vector3(main_radius * 1.20, 0.0, 0.0),
		_black
	)

	_add_cylinder(
		"TravellerSheave",
		line_cheek_offset * 2.0,
		line_radius,
		TRAVELLER_LINE_SHEAVE_CENTER,
		_sheave,
		Vector3(PI * 0.5, 0.0, 0.0)
	)
	for side in [-1.0, 1.0]:
		var line_cheek := _add_extruded_profile(
			"TravellerPortCheek" if side < 0.0 else "TravellerStarboardCheek",
			line_cheek_profile,
			0.006,
			_black
		)
		# This smaller linked block is perpendicular to the mainsheet block.
		line_cheek.rotation.y = PI * 0.5
		line_cheek.position = TRAVELLER_LINE_SHEAVE_CENTER + Vector3(0.0, 0.0, side * line_cheek_offset)
	_add_cylinder(
		"TravellerAxle",
		line_cheek_offset * 2.5,
		line_radius * 0.13,
		TRAVELLER_LINE_SHEAVE_CENTER,
		_stainless,
		Vector3(PI * 0.5, 0.0, 0.0)
	)
	_add_box(
		"TravellerFootBridge",
		Vector3(line_radius * 0.30, line_radius * 1.72, line_cheek_offset * 2.35),
		TRAVELLER_LINE_SHEAVE_CENTER - Vector3(line_radius * 1.20, 0.0, 0.0),
		_black
	)

	# Twin stainless straps make the linked, articulating construction legible
	# at cockpit viewing distance without fusing the blocks into one housing.
	for link_side in [-1.0, 1.0]:
		_add_tube_between(
			"PortArticulationLink" if link_side < 0.0 else "StarboardArticulationLink",
			TRAVELLER_MAIN_SHEAVE_CENTER
				- Vector3(main_radius * 1.12, 0.0, 0.0)
				+ Vector3(0.0, link_side * 0.007, 0.0),
			TRAVELLER_LINE_SHEAVE_CENTER
				+ Vector3(line_radius * 1.12, 0.0, 0.0)
				+ Vector3(0.0, link_side * 0.007, 0.0),
			0.0035,
			_stainless
		)


func _block_cheek_profile(sheave_radius: float, block_depth: float) -> PackedVector2Array:
	var block_height := sheave_radius * 2.55
	return PackedVector2Array([
		Vector2(-block_depth * 0.48, sheave_radius * 0.10),
		Vector2(-block_depth * 0.56, block_height * 0.32),
		Vector2(-block_depth * 0.44, block_height * 0.82),
		Vector2(-block_depth * 0.24, block_height * 1.04),
		Vector2(block_depth * 0.24, block_height * 1.04),
		Vector2(block_depth * 0.44, block_height * 0.82),
		Vector2(block_depth * 0.56, block_height * 0.32),
		Vector2(block_depth * 0.48, sheave_radius * 0.10),
	])


func _case_surface_height(point: Vector2) -> float:
	var hull := get_parent().get_node_or_null("Hull") as IlcaHull
	if hull == null: return 0.031
	var x := position.x + point.x
	var z := position.z + point.y
	var inside := z >= float(hull._cockpit_z_positions.front()) and z <= float(hull._cockpit_z_positions.back()) and absf(x) < hull._cockpit_half_width_at(z)
	return (hull.cockpit_floor_y_at(x, z) if inside else hull.deck_y_at(x, z)) - position.y


func _build_daggerboard_case() -> void:
	var case_mesh := ArrayMesh.new()
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := IlcaHull.CUTS.capsule(Vector2.ZERO, 0.255, 0.050)
	var inner := IlcaHull.CUTS.capsule(Vector2.ZERO, IlcaHull.SLOT_HALF_LENGTH, IlcaHull.SLOT_HALF_WIDTH)
	for index in outer.size():
		var next := (index + 1) % outer.size()
		var a := Vector3(outer[index].x, _case_surface_height(outer[index]) + 0.002, outer[index].y)
		var b := Vector3(outer[next].x, _case_surface_height(outer[next]) + 0.002, outer[next].y)
		var c := Vector3(inner[next].x, _case_surface_height(inner[next]) + 0.002, inner[next].y)
		var d := Vector3(inner[index].x, _case_surface_height(inner[index]) + 0.002, inner[index].y)
		_add_quad(rim, a, d, c, b)
	rim.index()
	rim.generate_normals()
	rim.commit(case_mesh)
	case_mesh.surface_set_material(0, _white)
	var lining := SurfaceTool.new()
	lining.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inset := IlcaHull.CUTS.capsule(Vector2.ZERO, IlcaHull.SLOT_HALF_LENGTH - 0.0008, IlcaHull.SLOT_HALF_WIDTH - 0.0008)
	for index in inner.size():
		var next := (index + 1) % inner.size()
		# The replaceable dark lip sits inside the structural trunk wall, not
		# exactly on top of its triangles where both surfaces would flicker.
		var a := Vector3(inset[index].x, _case_surface_height(inner[index]) + 0.002, inset[index].y)
		var b := Vector3(inset[next].x, _case_surface_height(inner[next]) + 0.002, inset[next].y)
		_add_quad(lining, a, b, b - Vector3.UP * 0.018, a - Vector3.UP * 0.018)
	lining.index()
	lining.generate_normals()
	lining.commit(case_mesh)
	case_mesh.surface_set_material(1, _soft_black)
	mesh = case_mesh

	_build_friction_pad()


func _build_friction_pad() -> void:
	# A cantilevered U-shaped replaceable insert, not a sheet cleat. Both
	# screw lands rest on the case lip; the open throat faces the board.
	var plane := Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT)
	var base_y := _case_surface_height(Vector2(0, 0.213)) + 0.002
	var foot := PackedVector2Array([Vector2(-0.030, 0.229), Vector2(0.030, 0.229), Vector2(0.034, 0.227), Vector2(0.036, 0.223), Vector2(0.035, 0.206), Vector2(0.016, 0.155), Vector2(0.010, 0.148), Vector2(0.006, 0.150), Vector2(0.0035, 0.1685)])
	for index in range(1, 13):
		var angle := PI * float(index) / 12
		foot.append(Vector2(cos(angle) * 0.0035, 0.1685 + sin(angle) * 0.0035))
	foot.append_array(PackedVector2Array([Vector2(-0.006, 0.150), Vector2(-0.010, 0.148), Vector2(-0.016, 0.155), Vector2(-0.035, 0.206), Vector2(-0.036, 0.223), Vector2(-0.034, 0.227)]))
	var base := _add_profile_part("BrakeHousing", foot, 0.004, Vector3(0, base_y + 0.002, 0), _black, 0.0004)
	base.basis = plane
	var housing := _u_pad_profile(0.018, 0.165, 0.0115, 0.164, 0.145)
	var rim := _add_profile_part("BrakeInsertCradle", housing, 0.014, Vector3(0, base_y + 0.011, 0), _soft_black, 0.0006)
	rim.basis = plane
	var rubber := _u_pad_profile(0.011, 0.164, 0.003, 0.1685, 0.145)
	var pad := _add_profile_part("BrakePad", rubber, 0.013, Vector3(0, base_y + 0.0115, 0), _material(Color("c8ccc3"), 0.92), 0.0003)
	pad.basis = plane
	for side in [-1.0, 1.0]:
		var center := Vector3(side * 0.0275, base_y + 0.005, 0.213)
		_add_cylinder("BrakeWasher%d" % int(side), 0.002, 0.006, center, _soft_black)
		_add_cylinder("BrakeScrewPort" if side < 0 else "BrakeScrewStarboard", 0.002, 0.0035, center + Vector3.UP * 0.002, _stainless)
		_add_box("BrakeScrewSlot%d" % int(side), Vector3(0.0045, 0.0002, 0.0007), center + Vector3.UP * 0.0031, _black)


func _u_pad_profile(outer: float, outer_z: float, inner: float, inner_z: float, front_z: float) -> PackedVector2Array:
	var result := PackedVector2Array([Vector2(outer, front_z), Vector2(outer, outer_z)])
	for index in range(1, 25):
		var angle := PI * float(index) / 24
		result.append(Vector2(cos(angle) * outer, outer_z + sin(angle) * outer))
	result.append(Vector2(-outer, front_z))
	result.append(Vector2(-minf(outer - 0.002, inner + 0.006), front_z + 0.001))
	result.append(Vector2(-inner, inner_z))
	for index in range(1, 25):
		var angle := PI - PI * float(index) / 24
		result.append(Vector2(cos(angle) * inner, inner_z + sin(angle) * inner))
	result.append(Vector2(minf(outer - 0.002, inner + 0.006), front_z + 0.001))
	return result


func _build_daggerboard_head() -> void:
	var profile := PackedVector2Array([
		Vector2(-0.182, -0.095),
		Vector2(0.182, -0.095),
		Vector2(0.182, 0.060),
		Vector2(0.120, 0.095),
		Vector2(-0.145, 0.095),
		Vector2(-0.182, 0.052),
	])
	_add_extruded_profile("BoardHead", profile, 0.058, _white)
	_add_box("CertificationLabel", Vector3(0.004, 0.042, 0.064), Vector3(0.031, 0.015, 0.075), _label_blue)
	for z_offset in [-0.105, 0.055]:
		_add_cylinder(
			"HandleHoleForward" if z_offset < 0.0 else "HandleHoleAft",
			0.066,
			0.014,
			Vector3(0.0, 0.072, float(z_offset)),
			_soft_black,
			Vector3(0.0, 0.0, PI * 0.5)
		)


func _build_daggerboard_handle() -> void:
	var forward := Vector3(0.041, -0.035, -0.105)
	var aft := Vector3(0.041, -0.035, 0.055)
	var forward_top := forward + Vector3(0.0, 0.085, 0.015)
	var aft_top := aft + Vector3(0.0, 0.085, -0.015)
	_add_tube_between("HandleForwardLeg", forward, forward_top, 0.008, _rope)
	_add_tube_between("HandleGrip", forward_top, aft_top, 0.010, _rope)
	_add_tube_between("HandleAftLeg", aft_top, aft, 0.008, _rope)


func _build_grab_rail() -> void:
	# The production ILCA grabrail is a low plastic strip screwed to the upper
	# inside face of each cockpit wall. It is not an elevated handrail on the
	# side-deck seating surface. Three joined rail sections and five countersunk
	# fasteners read like the production multi-piece moulding without recreating
	# the old elevated bar.
	var rail_length := 0.82
	var section_count := 3
	var section_length := rail_length / float(section_count)
	for section_index in range(section_count):
		var section_z := -rail_length * 0.5 + section_length * (float(section_index) + 0.5)
		_add_box(
			"RailSection%d" % section_index,
			Vector3(0.020, 0.026, section_length - 0.004),
			Vector3(0.0, 0.0, section_z),
			_black
		)
	for fastener_index in range(5):
		var fastener_z := lerpf(-rail_length * 0.44, rail_length * 0.44, float(fastener_index) / 4.0)
		_add_cylinder(
			"Fastener%d" % fastener_index,
			0.022,
			0.004,
			Vector3(0.0, 0.0, fastener_z),
			_stainless,
			Vector3(0.0, 0.0, PI * 0.5)
		)


func _build_hiking_strap() -> void:
	# The padded working section narrows into a webbing tail at the forward
	# pressure plate and a sewn loop at the aft support line. This is one strap,
	# not a rigid black box spanning the entire cockpit floor.
	#
	# The node itself sits at boat-local y=0.075 m. The actual skinned bare-foot
	# dorsum rises about 20 mm above its semantic centreline, so the 18 mm pad
	# centre is raised to local y=0.062 m. Its underside is boat-local y=0.128 m,
	# leaving visible clearance without detaching either end fitting.
	_add_box(
		"PaddedWebbing",
		Vector3(0.120, 0.018, 0.700),
		Vector3(0.0, 0.062, -0.035),
		_rubber
	)
	_add_box(
		"ForwardTail",
		Vector3(0.044, 0.010, forward_tail_length),
		forward_tail_center,
		_soft_black
	)
	_add_tapered_webbing_between(
		"ForwardTransition",
		forward_tail_center + Vector3.BACK * forward_tail_length * 0.5,
		Vector3(0.0, 0.062, -0.385),
		0.044,
		0.120,
		0.010,
		0.018,
		_rubber
	)
	_add_tapered_webbing_between(
		"AftTransition",
		Vector3(0.0, 0.062, 0.315),
		Vector3(0.0, -0.003, 0.415),
		0.120,
		0.050,
		0.018,
		0.010,
		_rubber
	)
	_add_box(
		"AftTail",
		Vector3(0.050, 0.010, 0.090),
		Vector3(0.0, -0.003, 0.460),
		_soft_black
	)
	for side in [-1.0, 1.0]:
		_add_tube_between(
			"AftLoopPort" if side < 0.0 else "AftLoopStarboard",
			Vector3(side * 0.026, 0.005, 0.490),
			Vector3(side * 0.026, 0.018, 0.555),
			0.005,
			_soft_black
		)
	_add_tube_between(
		"AftLoopBridge",
		Vector3(-0.026, 0.018, 0.555),
		Vector3(0.026, 0.018, 0.555),
		0.005,
		_soft_black
	)


func _build_hiking_strap_plate() -> void:
	# Approved-builder parts use a small two-screw pressure plate. The 47 mm
	# plate length and 28 mm hole spacing follow the published ILCA toe-strap
	# plate dimensions; the strap's narrow forward tail passes beneath it.
	_add_box(
		"PressurePlate",
		Vector3(0.047, 0.010, 0.032),
		Vector3.ZERO,
		_black
	)
	for side in [-1.0, 1.0]:
		_add_cylinder(
			"PortScrew" if side < 0.0 else "StarboardScrew",
			0.012,
			0.004,
			Vector3(side * 0.014, 0.003, 0.0),
			_stainless
		)


func _build_cam_cleat() -> void:
	_add_box("CleatBase", Vector3(0.074, 0.010, 0.068), Vector3(0.0, 0.004, 0.0), _black)
	for side in [-1.0, 1.0]:
		_add_cylinder(
			"PortCam" if side < 0.0 else "StarboardCam",
			0.034,
			0.021,
			Vector3(side * 0.021, 0.025, -0.004),
			_black
		)
		_add_box(
			"PortJaw" if side < 0.0 else "StarboardJaw",
			Vector3(0.024, 0.032, 0.050),
			Vector3(side * 0.020, 0.031, -0.012),
			_black,
			Vector3(0.0, side * deg_to_rad(18.0), 0.0)
		)
		_add_cylinder(
			"PortAxle" if side < 0.0 else "StarboardAxle",
			0.038,
			0.006,
			Vector3(side * 0.021, 0.028, -0.004),
			_stainless
		)
	_add_tube_between("FairleadBridge", Vector3(-0.038, 0.052, 0.028), Vector3(0.038, 0.052, 0.028), 0.005, _stainless)


func _build_self_bailer() -> void:
	var hull := get_parent().get_node_or_null("Hull") as IlcaHull
	if hull == null: return
	var up := -hull._surface_normal(hull.drain_outlet.x, hull.drain_outlet.z, 0)
	var aft := Vector3.RIGHT.cross(up).normalized()
	transform = Transform3D(Basis(up.cross(aft), up, aft), hull.drain_outlet)
	# Closed, low-profile external unit; the operating plug is inside the well.
	# This is a static assembly, not an implemented opening or water-flow model.
	_add_box("BailerPlate", Vector3(0.074, 0.003, 0.156), Vector3(0, -0.0015, 0), _black)
	_add_box("BailerChute", Vector3(0.046, 0.004, 0.108), Vector3(0, -0.006, 0.012), _soft_black)
	for side in [-1.0, 1.0]:
		_add_box("PortRunner" if side < 0 else "StarboardRunner", Vector3(0.006, 0.004, 0.112), Vector3(side * 0.027, -0.006, 0.010), _black)
	_add_cylinder("PivotPin", 0.062, 0.0025, Vector3(0, -0.007, -0.035), _stainless, Vector3(0, 0, PI * 0.5))


func _build_cockpit_drain_bung() -> void:
	var hull := get_parent().get_node_or_null("Hull") as IlcaHull
	if hull == null: return
	transform = hull.drain_frame
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axis := transform.basis.y
	var projection := transform.affine_inverse()
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	for index in 40:
		var angle := TAU * float(index) / 40.0
		for radius in [0.0127, 0.019]:
			var origin := transform * Vector3(cos(angle) * radius, 0.04, sin(angle) * radius)
			var point := projection * (hull._mesh_ray(hull.mesh, 2, origin, -axis) + axis * 0.0005)
			if radius < 0.015: inner.append(point)
			else: outer.append(point)
	for index in 40:
		var next := (index + 1) % 40
		_add_quad(surface, outer[index], outer[next], inner[next], inner[index])
	surface.index()
	surface.generate_normals()
	var flange := ArrayMesh.new()
	surface.commit(flange)
	flange.surface_set_material(0, _material(Color(0.59, 0.39, 0.12), 0.33, 0.72))
	mesh = flange
	_add_cylinder("RubberPlug", 0.016, 0.0116, Vector3(0, 0.003, 0), _rubber)
	_add_cylinder("PlugHead", 0.006, 0.013, Vector3(0, 0.014, 0), _black)
	_add_tube_between("OperatingStem", Vector3(0, -0.004, 0), Vector3(0, -0.034, 0), 0.002, _stainless)


func _build_eye_strap() -> void:
	_add_box("EyeStrapPlate", Vector3(0.082, 0.007, 0.035), Vector3(0.0, 0.0, 0.0), _stainless)
	_add_tube_between("PortLeg", Vector3(-0.026, 0.004, 0.0), Vector3(-0.026, 0.038, 0.0), 0.005, _stainless)
	_add_tube_between("Bridge", Vector3(-0.026, 0.038, 0.0), Vector3(0.026, 0.038, 0.0), 0.005, _stainless)
	_add_tube_between("StarboardLeg", Vector3(0.026, 0.038, 0.0), Vector3(0.026, 0.004, 0.0), 0.005, _stainless)


func _build_gooseneck() -> void:
	# The gooseneck is a mast band, twin lug and transverse pin—not a deck eye.
	_add_cylinder("MastBand", 0.060, 0.061, Vector3(0.0, 0.0, 0.0), _stainless)
	for side in [-1.0, 1.0]:
		_add_box(
			"PortLug" if side < 0.0 else "StarboardLug",
			Vector3(0.010, 0.050, 0.105),
			Vector3(side * 0.027, 0.0, 0.080),
			_stainless
		)
	_add_cylinder(
		"BoomPin", 0.074, 0.010, Vector3(0.0, 0.0, 0.105), _black,
		Vector3(0.0, 0.0, PI * 0.5)
	)
	_add_box("BoomJaw", Vector3(0.044, 0.039, 0.100), Vector3(0.0, 0.0, 0.142), _black)


func _build_sail_cringle() -> void:
	# Two shallow discs leave a dark centre that reads as the punched eye while
	# keeping this procedural fitting robust from both sides of the cloth.
	_add_cylinder("Grommet", 0.008, 0.023, Vector3.ZERO, _stainless, Vector3(0.0, 0.0, PI * 0.5))
	for side in [-1.0, 1.0]:
		_add_cylinder(
			"PortEye" if side < 0.0 else "StarboardEye",
			0.002,
			0.012,
			Vector3(side * 0.005, 0.0, 0.0),
			_soft_black,
			Vector3(0.0, 0.0, PI * 0.5)
		)


func _build_clew_strap() -> void:
	# Webbing embraces the loose-footed boom and carries the sail's metal eye.
	_add_box("WebbingPort", Vector3(0.010, 0.092, 0.030), Vector3(-0.036, 0.010, 0.0), _soft_black)
	_add_box("WebbingStarboard", Vector3(0.010, 0.092, 0.030), Vector3(0.036, 0.010, 0.0), _soft_black)
	_add_box("WebbingCrown", Vector3(0.082, 0.012, 0.030), Vector3(0.0, 0.052, 0.0), _soft_black)
	_add_cylinder("ClewEye", 0.010, 0.023, Vector3(0.0, 0.068, 0.0), _stainless, Vector3(0.0, 0.0, PI * 0.5))
	_add_cylinder("ClewOpening", 0.012, 0.011, Vector3(0.0, 0.068, 0.0), _soft_black, Vector3(0.0, 0.0, PI * 0.5))


func _build_boom_end_fitting() -> void:
	_add_cylinder("EndPlug", 0.080, 0.030, Vector3(0.0, 0.0, 0.0), _black, Vector3(PI * 0.5, 0.0, 0.0))
	_add_cylinder("OuthaulSheave", 0.020, 0.017, Vector3(0.0, 0.025, -0.012), _sheave, Vector3(0.0, 0.0, PI * 0.5))
	_add_cylinder("SheaveAxle", 0.050, 0.004, Vector3(0.0, 0.025, -0.012), _stainless, Vector3(0.0, 0.0, PI * 0.5))


func _build_rudder_head() -> void:
	var cheek_profile := PackedVector2Array([
		Vector2(-0.115, -0.115), Vector2(0.090, -0.115),
		Vector2(0.115, -0.070), Vector2(0.105, 0.095),
		Vector2(0.055, 0.125), Vector2(-0.095, 0.110),
	])
	# Two genuinely separate aluminium cheeks leave the blade gap visible at
	# first-person distance. The old solid 44 mm extrusion read as one black box.
	for side in [-1.0, 1.0]:
		var cheek := _add_extruded_profile(
			"PortCheek" if side < 0.0 else "StarboardCheek",
			cheek_profile,
			0.006,
			_black
		)
		cheek.position.x = side * 0.022
	_add_cylinder("BladeBolt", 0.052, 0.012, Vector3(0.0, -0.025, 0.025), _stainless, Vector3(0.0, 0.0, PI * 0.5))
	_add_cylinder("UpperSpacingPin", 0.052, 0.006, Vector3(0.0, 0.078, -0.045), _stainless, Vector3(0.0, 0.0, PI * 0.5))
	_add_cylinder("LowerSpacingPin", 0.052, 0.006, Vector3(0.0, -0.078, -0.065), _stainless, Vector3(0.0, 0.0, PI * 0.5))
	_add_cylinder("DownhaulHole", 0.054, 0.007, Vector3(0.0, -0.070, 0.070), _soft_black, Vector3(0.0, 0.0, PI * 0.5))


func _build_tiller() -> void:
	# Representative ILCA replacement tillers are about one metre overall. Keep
	# the extension joint at the inboard tube end instead of extending the tiller
	# into the hiking-strap and leg workspace.
	_add_tube_between("CarbonTiller", Vector3(0.0, 0.0, -0.490), Vector3(0.0, 0.0, 0.490), 0.012, _soft_black)
	_add_box("HeadSocket", Vector3(0.034, 0.029, 0.090), Vector3(0.0, 0.0, 0.440), _black)
	_add_box("ExtensionBase", Vector3(0.030, 0.026, 0.075), Vector3(0.0, 0.0, -0.450), _rubber)


func _build_tiller_extension() -> void:
	# Tube length excludes the separately modelled rubber joint. The sailor may slide
	# their hand along the foam grip, but neither the carbon tube nor its grip
	# telescopes when the rubber universal joint articulates.
	var span := tiller_extension_span()
	_add_tube_between("CarbonShaft", Vector3(0.0, 0.0, -TILLER_EXTENSION_JOINT_METRES), Vector3(0.0, 0.0, -span), 0.011, _soft_black)
	# A Laser/ILCA flexi joint is a short rubber web, not a rigid metal hinge.
	# Three overlapping sections make its bend readable while the parent pivot
	# supplies full multi-axis articulation.
	_add_cylinder("UniversalJointBase", 0.044, 0.016, Vector3(0.0, 0.0, 0.004), _rubber)
	_add_tube_between("UniversalJointWeb", Vector3(0.0, 0.0, -0.004), Vector3(0.0, 0.0, -0.040), 0.011, _rubber)
	_add_cylinder("UniversalJointCollar", 0.031, 0.014, Vector3(0.0, 0.0, -0.043), _rubber)
	_add_tube_between("Grip", Vector3(0.0, 0.0, -0.560), Vector3(0.0, 0.0, -span), 0.014, _rubber)
	for ring_index in range(5):
		var rib := _add_tube_between(
			"GripRib%d" % ring_index,
			Vector3(0.0, 0.0, -0.005),
			Vector3(0.0, 0.0, 0.005),
			0.015,
			_rubber
		)
		rib.position.z = -lerpf(.600,span-.020,ring_index/4.0)

func tiller_extension_span() -> float:
	return extension_tube_metres+TILLER_EXTENSION_JOINT_METRES

func tiller_extension_grip_max() -> float:
	return tiller_extension_span()-TILLER_EXTENSION_END_HAND_MARGIN


func set_tiller_extension_grip_distance(distance: float) -> void:
	if part_kind != PartKind.TILLER_EXTENSION:
		return
	# Keep the rendered hardware immutable. This metadata describes only the
	# semantic point currently held by the sailor's palm on the fixed foam grip.
	set_meta("hand_contact_valid",distance>=TILLER_EXTENSION_GRIP_MIN_DISTANCE and distance<=tiller_extension_grip_max())
	set_meta(
		"hand_contact_distance",
		clampf(
			distance,
			TILLER_EXTENSION_GRIP_MIN_DISTANCE,
			tiller_extension_grip_max()
		)
	)


func _build_traveller_fairlead() -> void:
	_add_box("PlasticBase", Vector3(0.072, 0.010, 0.042), Vector3.ZERO, _black)
	_add_tube_between("PortLeg", Vector3(-0.023, 0.006, 0.0), Vector3(-0.023, 0.030, 0.0), 0.006, _black)
	_add_tube_between("Bridge", Vector3(-0.023, 0.030, 0.0), Vector3(0.023, 0.030, 0.0), 0.006, _black)
	_add_tube_between("StarboardLeg", Vector3(0.023, 0.030, 0.0), Vector3(0.023, 0.006, 0.0), 0.006, _black)


func _build_traveller_cleat() -> void:
	_add_box("ClamBase", Vector3(0.062, 0.010, 0.072), Vector3.ZERO, _black)
	for side in [-1.0, 1.0]:
		_add_box(
			"PortJaw" if side < 0.0 else "StarboardJaw",
			Vector3(0.018, 0.034, 0.058),
			Vector3(side * 0.014, 0.022, -0.006),
			_black,
			Vector3(0.0, side * deg_to_rad(10.0), side * deg_to_rad(-7.0))
		)
	_add_tube_between("Guide", Vector3(-0.029, 0.036, 0.026), Vector3(0.029, 0.036, 0.026), 0.004, _black)


func _build_rudder_gudgeon() -> void:
	_add_box("TransomPlate", Vector3(0.105, 0.070, 0.008), Vector3(0.0, 0.0, 0.0), _stainless)
	for side in [-1.0, 1.0]:
		_add_box(
			"PortEar" if side < 0.0 else "StarboardEar",
			Vector3(0.020, 0.040, 0.055),
			Vector3(side * 0.031, 0.0, 0.028),
			_stainless
		)
	_add_cylinder("PintleBarrel", 0.052, 0.009, Vector3(0.0, 0.0, 0.052), _stainless)
	_add_cylinder("PintleOpening", 0.054, 0.004, Vector3(0.0, 0.0, 0.052), _soft_black)


func _capsule_outline(half_length: float, half_width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var end_center := half_length - half_width
	for index in range(ROUND_SEGMENTS + 1):
		var angle := PI + PI * float(index) / float(ROUND_SEGMENTS)
		points.append(Vector2(cos(angle) * half_width, -end_center + sin(angle) * half_width))
	for index in range(ROUND_SEGMENTS + 1):
		var angle := PI * float(index) / float(ROUND_SEGMENTS)
		points.append(Vector2(cos(angle) * half_width, end_center + sin(angle) * half_width))
	return points


func _add_box(
	part_name: String,
	size: Vector3,
	part_position: Vector3,
	material: Material,
	part_rotation := Vector3.ZERO
) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = box
	instance.position = part_position
	instance.rotation = part_rotation
	instance.material_override = material
	add_child(instance)
	return instance


func _add_cylinder(
	part_name: String,
	height: float,
	radius: float,
	part_position: Vector3,
	material: Material,
	part_rotation := Vector3.ZERO,
	top_radius := -1.0
) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.height = height
	cylinder.bottom_radius = radius
	cylinder.top_radius = radius if top_radius < 0.0 else top_radius
	cylinder.radial_segments = 28
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = cylinder
	instance.position = part_position
	instance.rotation = part_rotation
	instance.material_override = material
	add_child(instance)
	return instance


func _add_tube_between(
	part_name: String,
	from: Vector3,
	to: Vector3,
	radius: float,
	material: Material
) -> MeshInstance3D:
	var direction := to - from
	var cylinder := CylinderMesh.new()
	cylinder.height = direction.length()
	cylinder.bottom_radius = radius
	cylinder.top_radius = radius
	cylinder.radial_segments = 14
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = cylinder
	instance.position = (from + to) * 0.5
	instance.basis = _basis_with_y(direction.normalized())
	instance.material_override = material
	add_child(instance)
	return instance


func _add_tapered_webbing_between(
	part_name: String,
	from_center: Vector3,
	to_center: Vector3,
	from_width: float,
	to_width: float,
	from_thickness: float,
	to_thickness: float,
	material: Material
) -> MeshInstance3D:
	var direction := (to_center - from_center).normalized()
	var width_axis := Vector3.RIGHT
	var thickness_axis := direction.cross(width_axis).normalized()
	var from_half_width := from_width * 0.5
	var to_half_width := to_width * 0.5
	var from_half_thickness := from_thickness * 0.5
	var to_half_thickness := to_thickness * 0.5

	var from_left_bottom := from_center - width_axis * from_half_width - thickness_axis * from_half_thickness
	var from_right_bottom := from_center + width_axis * from_half_width - thickness_axis * from_half_thickness
	var from_left_top := from_center - width_axis * from_half_width + thickness_axis * from_half_thickness
	var from_right_top := from_center + width_axis * from_half_width + thickness_axis * from_half_thickness
	var to_left_bottom := to_center - width_axis * to_half_width - thickness_axis * to_half_thickness
	var to_right_bottom := to_center + width_axis * to_half_width - thickness_axis * to_half_thickness
	var to_left_top := to_center - width_axis * to_half_width + thickness_axis * to_half_thickness
	var to_right_top := to_center + width_axis * to_half_width + thickness_axis * to_half_thickness

	var webbing_mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(surface, from_left_top, to_left_top, to_right_top, from_right_top)
	_add_quad(surface, from_right_bottom, to_right_bottom, to_left_bottom, from_left_bottom)
	_add_quad(surface, from_left_bottom, to_left_bottom, to_left_top, from_left_top)
	_add_quad(surface, from_right_top, to_right_top, to_right_bottom, from_right_bottom)
	_add_quad(surface, from_left_bottom, from_left_top, from_right_top, from_right_bottom)
	_add_quad(surface, to_left_top, to_left_bottom, to_right_bottom, to_right_top)
	surface.index()
	surface.generate_normals()
	surface.commit(webbing_mesh)
	webbing_mesh.surface_set_material(0, material)

	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = webbing_mesh
	add_child(instance)
	return instance


func _add_extruded_profile(
	part_name: String,
	profile: PackedVector2Array,
	thickness: float,
	material: Material
) -> MeshInstance3D:
	var profile_mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_thickness := thickness * 0.5
	for side in [-1.0, 1.0]:
		var center := Vector3(side * half_thickness, 0.0, 0.0)
		for index in range(profile.size()):
			var next := (index + 1) % profile.size()
			var first := Vector3(side * half_thickness, profile[index].y, profile[index].x)
			var second := Vector3(side * half_thickness, profile[next].y, profile[next].x)
			if side < 0.0:
				surface.add_vertex(center)
				surface.add_vertex(second)
				surface.add_vertex(first)
			else:
				surface.add_vertex(center)
				surface.add_vertex(first)
				surface.add_vertex(second)
	for index in range(profile.size()):
		var next := (index + 1) % profile.size()
		_add_quad(
			surface,
			Vector3(-half_thickness, profile[index].y, profile[index].x),
			Vector3(-half_thickness, profile[next].y, profile[next].x),
			Vector3(half_thickness, profile[next].y, profile[next].x),
			Vector3(half_thickness, profile[index].y, profile[index].x)
		)
	surface.index()
	surface.generate_normals()
	surface.commit(profile_mesh)
	profile_mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = profile_mesh
	add_child(instance)
	return instance


func _basis_with_y(direction: Vector3) -> Basis:
	var reference := Vector3.FORWARD
	if absf(direction.dot(reference)) > 0.94:
		reference = Vector3.RIGHT
	var x_axis := direction.cross(reference).normalized()
	var z_axis := x_axis.cross(direction).normalized()
	return Basis(x_axis, direction, z_axis)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)
