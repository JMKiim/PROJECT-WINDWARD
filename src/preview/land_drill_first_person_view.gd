extends RefCounted
## Camera-only presentation. The finalized skeleton/trim are read-only.
var follow_origin := Vector2.ZERO
func reset_follow(lab: Node3D) -> void:
	follow_origin=Vector2(lab.look_yaw,lab.look_pitch)
func update(lab: Node3D) -> void:
	var actor: Node3D=lab.actor
	var position: Vector3=lab.to_local(actor.to_global(actor.eye_boat()))
	var head: Basis=actor.bone_pose_boat("Head").basis.orthonormalized()
	var direction: Vector3=lab.global_basis.inverse()*actor.global_basis*head*actor.look_pose.eye_basis*Vector3.BACK
	if lab.follow_work_area:
		var centre: Vector3=(actor.palm_boat("Left")+actor.palm_boat("Right"))*.5
		var target: Vector3=lab.to_local(actor.to_global(centre))
		var forward := (target-position).normalized()
		var right := forward.cross(Vector3.UP).normalized()
		var offset := Vector2(lab.look_yaw,lab.look_pitch)-follow_origin
		direction=Basis(Vector3.UP,offset.x)*Basis(right,offset.y)*forward
	lab.camera.position=position
	lab.camera.look_at(lab.to_global(position+direction),lab.global_basis*Vector3.UP)
	lab.camera.fov=72
