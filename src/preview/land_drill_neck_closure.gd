extends "res://src/preview/review_neck_closure.gd"
var relevant_binds := PackedInt32Array()
var previous_pose := []
var cache_ready := false
var mesh_builds := 0
func setup(body: MeshInstance3D,head_bind: int,threshold := .05) -> bool:
	if not super.setup(body,head_bind,threshold): return false
	var used := {}
	for group: Array in groups:
		for segment: Array in group:
			for corner: Dictionary in segment:
				for vertex: int in [corner.a,corner.b]:
					for influence in influences:
						var slot: int=vertex*influences+influence
						if weights[slot]>0: used[binds[slot]]=true
	for bind: int in used: relevant_binds.append(bind)
	relevant_binds.sort()
	cache_ready=true
	previous_pose=_signature()
	return true
func _signature() -> Array:
	var result := [source_body.global_transform.affine_inverse()*source_skeleton.global_transform]
	for bind in relevant_binds: result.append(source_skeleton.get_bone_global_pose(bind_bones[bind]))
	return result
func update_pose() -> void:
	if cache_ready:
		var signature := _signature()
		if signature==previous_pose: return
		previous_pose=signature
	super.update_pose()
	mesh_builds+=1
