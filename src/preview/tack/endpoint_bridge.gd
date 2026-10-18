extends RefCounted
## Explicit endpoint settling,not a change to the normal IDLE pose. The
## authored crossing has its stricter arm reserve; normal endpoints keep
## their existing forearm twist distribution and are joined continuously.
static func capture(model: RefCounted,u: float) -> Dictionary:
	var actor: Node3D=model.actor
	var seat := -1 if u<.5 else 1
	# Capture the original articulated bridge, not compensated local
	# upper/lower rotations whose interpolation would move the grasp.
	var surface_enabled: bool=model.upper_surface_enabled
	model.upper_surface_enabled=false
	var result: Dictionary=model.sample(u)
	model.upper_surface_enabled=surface_enabled
	var bones := []
	for index in actor.skeleton.get_bone_count(): bones.append(actor.skeleton.get_bone_pose(index))
	return {"normal":model.body.endpoints[seat].bones,"normal_root":model.body.endpoints[seat].root,"crossing":bones,"crossing_root":actor.get_node("Pose").transform,"result":result}
static func apply(actor: Node3D,data: Dictionary,weight: float) -> void:
	var sk: Skeleton3D=actor.skeleton
	for index in sk.get_bone_count():
		var a: Transform3D=data.normal[index]
		var b: Transform3D=data.crossing[index]
		sk.set_bone_pose_position(index,a.origin.lerp(b.origin,weight))
		sk.set_bone_pose_rotation(index,a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(),weight))
		sk.set_bone_pose_scale(index,a.basis.get_scale().lerp(b.basis.get_scale(),weight))
	var a: Transform3D=data.normal_root
	var b: Transform3D=data.crossing_root
	actor.get_node("Pose").transform=a.interpolate_with(b,weight)
