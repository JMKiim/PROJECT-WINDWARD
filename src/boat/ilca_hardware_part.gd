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
}

@export var part_kind: PartKind = PartKind.DECK_RATCHET
@export var has_becket := false

const ROUND_SEGMENTS := 16
const DECK_RATCHET_SHEAVE_DIAMETER := 0.057
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
	return Vector3.ZERO


func rope_anchor_global(anchor_name: StringName = &"sheave") -> Vector3:
	return to_global(rope_anchor_local(anchor_name))


func _ready() -> void:
	mesh = null
	match part_kind:
		PartKind.DECK_RATCHET:
			_build_block(DECK_RATCHET_SHEAVE_DIAMETER * 0.5, true, false)
		PartKind.BOOM_BLOCK:
			_build_block(0.025, false, false)
		PartKind.TRAVELLER_BLOCK:
			_build_traveller_block()
		PartKind.CONTROL_BLOCK:
			_build_block(0.015, false, false)
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


func _build_block(sheave_radius: float, stand_up: bool, double_sheave: bool) -> void:
	var cheek_gap := sheave_radius * (1.05 if not double_sheave else 1.80)
	var block_height := sheave_radius * 2.55
	var block_depth := sheave_radius * 1.72
	var sheave_positions := [0.0]
	if double_sheave:
		sheave_positions = [-sheave_radius * 0.43, sheave_radius * 0.43]

	if stand_up:
		_add_cylinder(
			"StandUpBoot",
			0.048,
			0.046,
			Vector3(0.0, -0.020, 0.0),
			_rubber,
			Vector3.ZERO,
			0.032
		)
		for coil_index in range(3):
			_add_tube_between(
				"StandUpSpring%d" % coil_index,
				Vector3(-0.036, 0.002 + float(coil_index) * 0.010, -0.025),
				Vector3(0.036, 0.002 + float(coil_index) * 0.010, -0.025),
				0.003,
				_stainless
			)
		_add_box("EyeStrapBase", Vector3(0.102, 0.006, 0.052), Vector3(0.0, -0.047, 0.0), _stainless)

	for side in [-1.0, 1.0]:
		_add_box(
			"PortCheek" if side < 0.0 else "StarboardCheek",
			Vector3(sheave_radius * 0.30, block_height, block_depth),
			Vector3(side * cheek_gap, block_height * 0.48, 0.0),
			_black
		)

	for sheave_index in range(sheave_positions.size()):
		_add_cylinder(
			"Sheave" if sheave_positions.size() == 1 else "Sheave%d" % sheave_index,
			cheek_gap * 2.15,
			sheave_radius,
			Vector3(float(sheave_positions[sheave_index]), block_height * 0.48, 0.0),
			_gold_sheave if stand_up else _sheave,
			Vector3(0.0, 0.0, PI * 0.5)
		)
	_add_cylinder(
		"Axle",
		cheek_gap * 2.55,
		sheave_radius * 0.13,
		Vector3(0.0, block_height * 0.48, 0.0),
		_stainless,
		Vector3(0.0, 0.0, PI * 0.5)
	)
	_add_box(
		"HeadBridge",
		Vector3(cheek_gap * 2.30, sheave_radius * 0.28, block_depth),
		Vector3(0.0, block_height, 0.0),
		_black
	)

	if not stand_up:
		_add_tube_between(
			"AttachmentStrop",
			Vector3(-cheek_gap * 0.68, block_height + 0.002, 0.0),
			Vector3(cheek_gap * 0.68, block_height + 0.002, 0.0),
			sheave_radius * 0.13,
			_stainless
		)
	if has_becket:
		_add_tube_between(
			"Becket",
			Vector3(-cheek_gap * 0.72, -sheave_radius * 0.32, 0.0),
			Vector3(cheek_gap * 0.72, -sheave_radius * 0.32, 0.0),
			sheave_radius * 0.15,
			_stainless
		)


func _build_traveller_block() -> void:
	# Ronstan's class-approved ILCA traveller is a 40 mm mainsheet block linked
	# to a 25 mm traveller-line block. Their perpendicular axle directions let
	# each rope run in its own load plane while the stainless links articulate.
	var main_radius := TRAVELLER_MAIN_SHEAVE_DIAMETER * 0.5
	var line_radius := TRAVELLER_LINE_SHEAVE_DIAMETER * 0.5
	var main_cheek_offset := 0.012
	var line_cheek_offset := 0.010

	_add_cylinder(
		"MainsheetSheave",
		main_cheek_offset * 2.0,
		main_radius,
		TRAVELLER_MAIN_SHEAVE_CENTER,
		_sheave
	)
	for side in [-1.0, 1.0]:
		_add_box(
			"MainsheetPortCheek" if side < 0.0 else "MainsheetStarboardCheek",
			Vector3(main_radius * 2.55, 0.006, main_radius * 1.72),
			TRAVELLER_MAIN_SHEAVE_CENTER + Vector3(0.0, side * main_cheek_offset, 0.0),
			_black
		)
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
		_add_box(
			"TravellerPortCheek" if side < 0.0 else "TravellerStarboardCheek",
			Vector3(line_radius * 2.55, line_radius * 1.72, 0.006),
			TRAVELLER_LINE_SHEAVE_CENTER + Vector3(0.0, 0.0, side * line_cheek_offset),
			_black
		)
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


func _build_daggerboard_case() -> void:
	var case_mesh := ArrayMesh.new()
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := _capsule_outline(0.255, 0.070)
	var inner := _capsule_outline(0.220, 0.027)
	var top_y := 0.034
	var base_y := -0.012
	var slot_y := -0.018
	for index in range(outer.size()):
		var next := (index + 1) % outer.size()
		_add_quad(
			rim,
			Vector3(outer[index].x, top_y, outer[index].y),
			Vector3(outer[next].x, top_y, outer[next].y),
			Vector3(inner[next].x, top_y, inner[next].y),
			Vector3(inner[index].x, top_y, inner[index].y)
		)
		_add_quad(
			rim,
			Vector3(outer[index].x, base_y, outer[index].y),
			Vector3(outer[next].x, base_y, outer[next].y),
			Vector3(outer[next].x, top_y, outer[next].y),
			Vector3(outer[index].x, top_y, outer[index].y)
		)
		_add_quad(
			rim,
			Vector3(inner[next].x, slot_y, inner[next].y),
			Vector3(inner[index].x, slot_y, inner[index].y),
			Vector3(inner[index].x, top_y, inner[index].y),
			Vector3(inner[next].x, top_y, inner[next].y)
		)
	rim.index()
	rim.generate_normals()
	rim.commit(case_mesh)
	case_mesh.surface_set_material(0, _white)

	var slot := SurfaceTool.new()
	slot.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.0, slot_y, 0.0)
	for index in range(inner.size()):
		var next := (index + 1) % inner.size()
		slot.add_vertex(center)
		slot.add_vertex(Vector3(inner[index].x, slot_y, inner[index].y))
		slot.add_vertex(Vector3(inner[next].x, slot_y, inner[next].y))
	slot.commit(case_mesh)
	case_mesh.surface_set_material(1, _soft_black)
	mesh = case_mesh

	_add_box("BrakeHousing", Vector3(0.126, 0.052, 0.060), Vector3(0.0, 0.053, 0.206), _black)
	_add_box("BrakePad", Vector3(0.060, 0.036, 0.012), Vector3(0.0, 0.046, 0.171), _rubber)
	for side in [-1.0, 1.0]:
		_add_cylinder(
			"BrakeScrewPort" if side < 0.0 else "BrakeScrewStarboard",
			0.006,
			0.009,
			Vector3(side * 0.043, 0.082, 0.211),
			_stainless
		)


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
	_add_tube_between("Rail", Vector3(0.0, 0.050, -0.245), Vector3(0.0, 0.050, 0.245), 0.018, _black)
	for z_offset in [-0.205, 0.205]:
		_add_tube_between(
			"ForwardFoot" if z_offset < 0.0 else "AftFoot",
			Vector3(0.0, 0.006, float(z_offset)),
			Vector3(0.0, 0.050, float(z_offset)),
			0.022,
			_black
		)
		_add_cylinder(
			"ForwardFastener" if z_offset < 0.0 else "AftFastener",
			0.007,
			0.008,
			Vector3(0.0, 0.009, float(z_offset)),
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
	_add_box("BailerPlate", Vector3(0.112, 0.008, 0.178), Vector3(0.0, 0.0, 0.0), _stainless)
	_add_box("BailerOpening", Vector3(0.060, 0.010, 0.122), Vector3(0.0, 0.007, 0.0), _soft_black)
	_add_box(
		"BailerChute",
		Vector3(0.052, 0.030, 0.105),
		Vector3(0.0, 0.022, 0.012),
		_black,
		Vector3(deg_to_rad(-11.0), 0.0, 0.0)
	)
	_add_tube_between("BailerHandle", Vector3(-0.031, 0.046, -0.035), Vector3(0.031, 0.046, -0.035), 0.006, _stainless)


func _build_eye_strap() -> void:
	_add_box("EyeStrapPlate", Vector3(0.082, 0.007, 0.035), Vector3(0.0, 0.0, 0.0), _stainless)
	_add_tube_between("PortLeg", Vector3(-0.026, 0.004, 0.0), Vector3(-0.026, 0.038, 0.0), 0.005, _stainless)
	_add_tube_between("Bridge", Vector3(-0.026, 0.038, 0.0), Vector3(0.026, 0.038, 0.0), 0.005, _stainless)
	_add_tube_between("StarboardLeg", Vector3(0.026, 0.038, 0.0), Vector3(0.026, 0.004, 0.0), 0.005, _stainless)


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
	cylinder.radial_segments = 20
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
