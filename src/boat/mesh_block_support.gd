extends "res://src/boat/spatial_block_support.gd"
const PAIRS := preload("res://src/boat/mesh_pair_contact.gd")
var pairs := PAIRS.new()

func setup(faces: PackedVector3Array,obstacles: RefCounted,cancelled := Callable()) -> bool:
	return super.setup(faces,obstacles,cancelled) and pairs.setup(faces,cancelled)

func query(pose: Transform3D,maximum_gap := 1.0) -> Dictionary:
	# Signed point witnesses reject initial containment; exact surface pairs
	# catch crossings between those witnesses. Do not infer swept collision.
	var result := super.query(pose,maximum_gap)
	if not result.valid: return result
	for contact: Dictionary in pairs.contacts(pose,field,maxf(.0002,minf(.003,result.gap))):
		if contact.gap<result.gap: result.merge(contact,true)
	return result

func contact_constraints(pose: Transform3D,pivot: Vector3,maximum_gap: float) -> Array:
	var result := super.contact_constraints(pose,pivot,maximum_gap)
	for contact: Dictionary in pairs.contacts(pose,field,maximum_gap):
		var row := contact.duplicate()
		row["gradient"]=(row.point-pivot).cross(row.normal)
		result.append(row)
	return result
