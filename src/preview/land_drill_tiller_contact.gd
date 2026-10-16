extends RefCounted
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const LIMB := preload("res://src/boat/sailor_leg_pose.gd")
const HIKING_GRIP := preload("res://src/preview/land_drill_hiking_grip.gd")
static func _same_signature(a: Array,b: Array) -> bool:
	if a.size()!=b.size(): return false
	for index in a.size():
		if a[index] is Transform3D:
			if not (a[index] as Transform3D).is_equal_approx(b[index]): return false
		elif a[index]!=b[index]: return false
	return true
static func _shared_plan(actor: Node3D,side: String,guide: Vector3,held: Transform3D,s: Vector3,e: Vector3,w: Vector3,working_hike := false) -> Dictionary:
	var joint: Vector3=actor.joint_boat()
	var axis := (guide-joint).normalized()
	var scale := held.basis.get_scale()
	var canonical: Basis=actor.sheet_control.regrip.reference_frames[side]
	canonical=Basis(Quaternion((canonical*CONTACT.tiller_axis(side)).normalized(),axis))*canonical
	var offset: Vector3=canonical*(CONTACT.TILLER_OFFSET*scale)
	var radial := offset-axis*offset.dot(axis)
	var toward := s-joint-axis*(s-joint).dot(axis)
	var roll := atan2((-toward).dot(axis.cross(radial)),(-toward).dot(radial))
	canonical=Basis(axis,roll)*canonical
	var alignment := Basis(Quaternion((held.basis*CONTACT.tiller_axis(side)).normalized(),axis))
	var base := (alignment*held.basis).orthonormalized()
	var mix := smoothstep(.2,.7,actor.hike)
	var frame := canonical.slerp(base,mix)
	var palm_direction := (frame*(CONTACT.TILLER_OFFSET*scale)).normalized()
	var along := (axis-palm_direction*axis.dot(palm_direction)).normalized()
	var forward := palm_direction*cos(deg_to_rad(44))+along*sin(deg_to_rad(44))
	var relative := frame*base.inverse()
	var original_fore := relative*alignment*(w-e).normalized()
	var angle := original_fore.angle_to(palm_direction)
	if angle>deg_to_rad(44.5): original_fore=palm_direction.slerp(original_fore,deg_to_rad(44.5)/angle)
	var fore := forward.slerp(original_fore,mix).normalized()
	offset=frame*(CONTACT.TILLER_OFFSET*scale)
	var b := e.distance_to(w)
	var shift := joint-offset-b*fore-s
	var half := shift.dot(axis)
	var discriminant := half*half-shift.length_squared()+s.distance_squared_to(e)
	if working_hike:
		return HIKING_GRIP.plan(actor,s,e,w,joint,axis,frame,scale,offset,fore,half,discriminant)
	if discriminant<0: return {"valid":false,"reason":"grip quadratic"}
	var selected := INF
	var selected_elbow := Vector3.ZERO
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var roots := []
	for grip in [-half-sqrt(discriminant),-half+sqrt(discriminant)]:
		var palm: Vector3=joint+axis*grip
		var wrist: Vector3=palm-offset
		var elbow: Vector3=wrist-b*fore
		var pair: PackedVector3Array=Geometry3D.get_closest_points_between_segments(elbow,wrist,hips,chest)
		roots.append({"grip":grip,"drop":s.y-elbow.y,"body":pair[0].distance_to(pair[1])})
		if grip<.25 or grip>actor.extension_span-.045 or s.y-elbow.y<.0805 or pair[0].distance_to(pair[1])<.190: continue
		if not is_finite(selected) or elbow.y<selected_elbow.y:
			selected=grip
			selected_elbow=elbow
	if not is_finite(selected): return {"valid":false,"reason":"finite grip/drop/body","roots":roots}
	return {"valid":true,"palm":joint+axis*selected,"wrist":joint+axis*selected-offset,"elbow":selected_elbow,"frame":frame,"scale":scale}
static func settle(actor: Node3D) -> Dictionary:
	var side: String=actor.tiller_hand()
	var skeleton: Skeleton3D=actor.skeleton
	var upper := skeleton.find_bone(side+"UpperArm")
	var lower := skeleton.find_bone(side+"LowerArm")
	var hand := skeleton.find_bone(side+"Hand")
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var w: Vector3=actor.bone_pose_boat(side+"Hand").origin
	var held: Transform3D=actor.bone_pose_boat(side+"Hand")
	var history: Dictionary=actor.transition_history
	var revision: int=actor.sheet_study.manual_revision
	var signature := [actor.amount,actor.hike,actor.sheet_control.weight,actor.seat_side,held,actor.bone_pose_boat(side+"UpperArm"),actor.bone_pose_boat("Hips"),actor.bone_pose_boat("Head")]
	if history.get("revision",-1)==revision and _same_signature(history.get("signature",[]),signature):
		for index in 3:
			var bone: int=[upper,lower,hand][index]
			var pose: Transform3D=history.poses[index]
			skeleton.set_bone_pose_position(bone,pose.origin)
			skeleton.set_bone_pose_rotation(bone,pose.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(bone,pose.basis.get_scale())
		skeleton.force_update_bone_child_transform(upper)
		return history.witness.duplicate(true)
	var moving := false
	var guide: Vector3=actor.palm_boat()
	var original := guide
	var joint: Vector3=actor.joint_boat()
	if actor.rest_guide!=null:
		var rest_axis: Vector3=actor.from_port(actor.rest_guide.sample(actor.amount,actor.hike))
		var current_axis := (original-joint).normalized()
		guide=joint+rest_axis.slerp(current_axis,smoothstep(0,1,actor.sheet_control.weight))*original.distance_to(joint)
	# Same finite-thigh sphere-to-line construction as the active haul pose.
	for limb in ["Left","Right"]:
		var hip: Vector3=actor.bone_pose_boat(limb+"UpperLeg").origin
		var knee: Vector3=actor.bone_pose_boat(limb+"LowerLeg").origin
		for sample in 5:
			var point: Vector3=hip.lerp(knee,sample/4.0)
			var fraction: float=(joint.z-point.z)/(joint.z-guide.z)
			if fraction<=0 or fraction>=1: continue
			var delta := point-joint
			var vx := guide.x-joint.x
			var vz := guide.z-joint.z
			var radius := .117
			var a := delta.x*delta.x+delta.z*delta.z-radius*radius
			var k := delta.x*vx+delta.z*vz
			var half := -delta.y*k
			var c := (delta.length_squared()-radius*radius)*(vx*vx+vz*vz)-k*k
			var discriminant := half*half-a*c
			if a<=0 or discriminant<0: continue
			guide.y=maxf(guide.y,joint.y+(-half+sqrt(discriminant))/a+.005)
	var axis := (guide-joint).normalized()
	# Project the finite shaft out of the neck capsule. The sampled base
	# bank itself has a face intrusion at negative steering; interpolation
	# must not reinstate it. This is a contact cone, not an action-pose search.
	var neck: Vector3=actor.bone_pose_boat("Neck").origin
	var head: Vector3=actor.bone_pose_boat("Head").origin
	var hips_guard: Vector3=actor.bone_pose_boat("Hips").origin
	var chest_guard: Vector3=actor.bone_pose_boat("UpperChest").origin
	var outward: Vector3=actor.from_port(Vector3.RIGHT)
	for iteration in 3:
		for capsule in [[neck,head,.114+actor.guard_reserve],[head,head,.154+actor.guard_reserve],[hips_guard,chest_guard,.177+actor.guard_reserve]]:
			var tip: Vector3=joint+axis*actor.extension_span
			var closest: PackedVector3Array=Geometry3D.get_closest_points_between_segments(joint,tip,capsule[0],capsule[1])
			if closest[0].distance_to(closest[1])>=capsule[2]-.001: continue
			var toward: Vector3=closest[1]-joint
			var distance := toward.length()
			var centre_axis := toward/distance
			# All nearby capsules use the same clear side. A closest tangent
			# toward the chest can undo the preceding face clearance.
			var preferred: Vector3=history.axis if moving else axis
			var original_tangent := preferred-centre_axis*preferred.dot(centre_axis)
			var outside_tangent := outward-centre_axis*outward.dot(centre_axis)
			var penetration: float=float(capsule[2])-closest[0].distance_to(closest[1])
			var steering_blend := 0.0 if moving else smoothstep(0,.045,penetration)
			var tangent := original_tangent.normalized().lerp(outside_tangent.normalized(),steering_blend)
			if tangent.is_zero_approx(): tangent=centre_axis.cross(Vector3.UP)
			var half := asin(clampf(float(capsule[2])/distance,0,1))
			axis=centre_axis*cos(half)+tangent.normalized()*sin(half)
			guide=joint+axis*original.distance_to(joint)
	var shared: Dictionary=_shared_plan(actor,side,guide,held,s,e,w)
	if shared.valid:
		var conversion: Transform3D=actor.global_transform.affine_inverse()*skeleton.global_transform
		var inverse := conversion.affine_inverse()
		LIMB.solve(skeleton,upper,lower,hand,inverse*shared.wrist,inverse*shared.elbow)
		var result: Transform3D=skeleton.get_bone_global_pose(hand)
		result.basis=conversion.basis.inverse()*shared.frame.scaled(shared.scale)
		skeleton.set_bone_global_pose(hand,result)
		skeleton.force_update_bone_child_transform(hand)
		var witness := {"valid":true,"guide_adjustment_m":original.distance_to(shared.palm),"grip_twist_deg":0,"wrist_error_m":actor.bone_pose_boat(side+"Hand").origin.distance_to(shared.wrist),"temporal_contact":moving,"shared_tiller_plan":true}
		history.revision=revision
		history.signature=signature
		history.axis=(shared.palm-joint).normalized()
		history.elbow=shared.elbow
		history.poses=[skeleton.get_bone_pose(upper),skeleton.get_bone_pose(lower),skeleton.get_bone_pose(hand)]
		history.witness=witness.duplicate(true)
		return witness
	return {"valid":false,"reason":"shared tiller plan rejected","plan":shared}
