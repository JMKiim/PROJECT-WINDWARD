extends RefCounted
## A short authored neck nod while crossing under the spar. The eyes and
## body dimensions stay attached to their original bones.
static func apply(actor: Node3D,u: float) -> void:
	var weight := smoothstep(.12,.24,u)*(1-smoothstep(.76,.88,u))
	if weight<=0: return
	var sk: Skeleton3D=actor.skeleton
	var neck := sk.find_bone("Neck")
	var pose: Node3D=actor.get_node("Pose")
	var axis: Vector3=Vector3.UP.cross(pose.basis.z).normalized()
	var to_boat: Basis=actor.global_basis.inverse()*sk.global_basis
	var transform := sk.get_bone_global_pose(neck)
	transform.basis=to_boat.inverse()*Basis(axis,deg_to_rad(25)*weight)*to_boat*transform.basis
	sk.set_bone_global_pose(neck,transform)
	sk.force_update_bone_child_transform(neck)
