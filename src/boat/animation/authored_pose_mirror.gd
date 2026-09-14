extends RefCounted

## Fixed rest-space reflection of authored tracks. No runtime limb solver.
const LAYOUT := preload("res://src/boat/animation/rudder_layer_layout.gd")
const REFLECTION := Transform3D(Basis(Vector3(-1,0,0),Vector3.UP,Vector3.BACK),Vector3.ZERO)
var skeleton: Skeleton3D
var opposite := PackedInt32Array()
var maps: Array[Transform3D] = []
var parent_inverse: Array[Transform3D] = []

func setup(value: Skeleton3D) -> void:
	skeleton = value
	for bone in skeleton.get_bone_count():
		var other := skeleton.find_bone(LAYOUT.opposite(skeleton.get_bone_name(bone)))
		opposite.append(other)
		maps.append(skeleton.get_bone_global_rest(other).affine_inverse()*REFLECTION*skeleton.get_bone_global_rest(bone))
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		parent_inverse.append(REFLECTION if parent<0 else maps[parent].affine_inverse())

func capture(bones: PackedInt32Array, side: int) -> Dictionary:
	var result := {}
	for bone in bones:
		result[bone] = skeleton.get_bone_pose(bone)
		if side==1: result[opposite[bone]] = skeleton.get_bone_pose(opposite[bone])
	return result

func apply_sample(bones: PackedInt32Array, before: Dictionary, side: int, weight: float) -> void:
	var sampled: Array[Transform3D] = []
	for bone in bones: sampled.append(skeleton.get_bone_pose(bone))
	# Sampling a port track temporarily writes the source arm. Restore it as
	# well as the destination before applying the reflected, disjoint layer.
	for bone: int in before: skeleton.set_bone_pose(bone,before[bone])
	for index in bones.size():
		var source := bones[index]
		var target := source if side==-1 else opposite[source]
		var value := sampled[index]
		if side==1: value = parent_inverse[target]*value*maps[target]
		skeleton.set_bone_pose(target,(before[target] as Transform3D).interpolate_with(value,weight))

func source_frame(name: String, side: int) -> Transform3D:
	if side==-1: return Transform3D.IDENTITY
	var bone := skeleton.find_bone(LAYOUT.opposite(name))
	return maps[bone].affine_inverse()
