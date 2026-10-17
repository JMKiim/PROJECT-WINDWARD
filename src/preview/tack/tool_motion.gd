extends RefCounted
const BODY := preload("res://src/preview/tack/body.gd")
const SHAFT := preload("res://src/preview/tack/shaft.gd")
const GRIP := preload("res://src/preview/tack/tool_grip.gd")
const LIMB := preload("res://src/boat/sailor_leg_pose.gd")
const DUCK := preload("res://src/preview/tack/duck.gd")
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const FIELD := "res://src/boat/animation/land_drill/tack_contact.res"
var actor: Node3D
var body := BODY.new()
var field: Resource
var steering := 0.0
var share_forearm_twist := true
var early_grip_bias := 0.0
var middle_grip_bias := 0.0
var middle_roll_bias := 0.0
var active_axis := Vector3.UP
func setup(value: Node3D) -> void:
	actor=value
	body.setup(actor)
	field=load(FIELD)
func set_steering(value: float) -> void:
	steering=value
	body.capture(value)
func sample(u: float) -> Dictionary:
	body.contact_offset_field=field.sample_body(steering,u)
	var pose: Dictionary=body.sample(u)
	pose.look_frame=actor.bone_pose_boat("Head").basis.orthonormalized()
	DUCK.apply(actor,u)
	var joint: Vector3=actor.joint_boat()
	var route: Dictionary=route_at(joint,u,pose.turn)
	active_axis=route.axis
	var plans := {}
	for side in ["Right","Left"]:
		if side=="Right" and u>.52 or side=="Left" and u<.50: continue
		var seat := -1 if side=="Right" else 1
		var key: Dictionary=field.sample(steering,u,side)
		var phase: float=u if side=="Right" else 1-u
		var s: float=steering if side=="Right" else -steering
		var weight: float=smoothstep(.0625,.125,s)*(1-smoothstep(.375,.4375,s))
		var early: float=smoothstep(0,.055,phase)*(1-smoothstep(.055,.11,phase))
		var middle: float=smoothstep(.12,.22,phase)*(1-smoothstep(.26,.38,phase))
		key.grip+=weight*(early_grip_bias*early+middle_grip_bias*middle)
		key.frame=Basis(route.axis,deg_to_rad(middle_roll_bias)*weight*middle*(1 if side=="Right" else -1))*key.frame
		var local_guide: Vector3=key.elbow
		var pole: Vector3=actor.bone_pose_boat(side+"UpperArm").origin+actor.bone_pose_boat("UpperChest").basis.orthonormalized()*local_guide
		var plan: Dictionary=GRIP._fixed_frame(actor,side,route.axis,key.grip,key.frame,pole)
		plan.authored_grip=key.grip
		plans[side]=plan
		if plan.valid:
			_apply_arm(side,plan)
			_tool_fingers(side,seat,u)
	return {"body":pose,"axis":route.axis,"plans":plans,"u":u,"primary":"Right" if u<.52 else "Left"}
func _field_contact(side: String,axis: Vector3,g: float,reference: Basis,pole: Vector3,swivel := NAN) -> Dictionary:
	# Follow the authored elbow guide continuously on the exact two-bone
	# reach circle. Do not choose another disconnected feasible interval
	# each frame. The independent replay still measures every original
	# wrist/drop/body guard; this is not an alternate acceptance threshold.
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var hand: Transform3D=actor.bone_pose_boat(side+"Hand")
	var a: float=s.distance_to(e)
	var b: float=e.distance_to(hand.origin)
	var frame: Basis=Basis(Quaternion((reference*CONTACT.tiller_axis(side)).normalized(),axis))*reference
	var scale: Vector3=hand.basis.get_scale()
	var offset: Vector3=preload("res://src/preview/tack/tool_surface.gd").offset(g)
	var palm: Vector3=actor.joint_boat()+axis*g
	var w: Vector3=palm-frame*(offset*scale)
	var d: float=w.distance_to(s)
	if d>=a+b or d<=absf(a-b): return {"valid":false,"reason":"authored contact outside actual reach","grip":g}
	var along: Vector3=(w-s)/d
	var x: float=(a*a-b*b+d*d)/(2*d)
	var centre: Vector3=s+along*x
	var radial: Vector3=pole-centre
	radial-=along*radial.dot(along)
	if is_finite(swivel):
		var outward: Vector3=s-actor.bone_pose_boat("UpperChest").origin
		outward-=along*outward.dot(along)
		outward=outward.normalized()
		radial=outward*cos(swivel)+along.cross(outward)*sin(swivel)
	if radial.length()<.000001: return {"valid":false,"reason":"authored elbow guide singular","grip":g}
	e=centre+radial.normalized()*sqrt(maxf(0,a*a-x*x))
	return {"valid":true,"palm":palm,"wrist":w,"elbow":e,"frame":frame,"scale":scale,"grip":g,"offset":offset,"wrist_offset":CONTACT.TILLER_OFFSET}
func _tangent_contact(side: String,axis: Vector3,g: float,reference: Basis,pole: Vector3) -> Dictionary:
	var raw := _field_contact(side,axis,g,reference,pole)
	if not raw.valid: return raw
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var old_e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var old_w: Vector3=actor.bone_pose_boat(side+"Hand").origin
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var near: Vector3=Geometry3D.get_closest_point_to_segment(raw.wrist,hips,chest)
	var normal: Vector3=(raw.wrist-near).normalized()
	var support: float=maxf(hips.dot(normal),chest.dot(normal))+.1905
	var fore_normal: Vector3=(raw.frame*(CONTACT.TILLER_OFFSET*raw.scale)).normalized()
	var b: float=old_e.distance_to(old_w)
	var cone := {"normal":fore_normal,"maximum":raw.wrist.dot(fore_normal)-b*cos(deg_to_rad(44.5))}
	var solved: Dictionary=preload("res://src/preview/land_drill_visual_elbow.gd").guide(s,raw.wrist,s.distance_to(old_e),b,pole,normal,support,[cone,{"normal":Vector3.UP,"maximum":s.y-.085}])
	if not solved.valid: return {"valid":false,"reason":"wrist tangent elbow corridor","grip":g}
	raw.elbow=solved.point
	return raw
func route_at(joint: Vector3,u: float,turn: float) -> Dictionary:
	return SHAFT.sample(body,joint,u,turn,actor)
func _apply_arm(side: String,plan: Dictionary) -> void:
	var sk: Skeleton3D=actor.skeleton
	var conversion: Transform3D=actor.global_transform.affine_inverse()*sk.global_transform
	var inverse := conversion.affine_inverse()
	var upper := sk.find_bone(side+"UpperArm")
	var lower := sk.find_bone(side+"LowerArm")
	var hand := sk.find_bone(side+"Hand")
	LIMB.solve(sk,upper,lower,hand,inverse*plan.wrist,inverse*plan.elbow)
	var frame: Basis=conversion.basis.inverse()*plan.frame.scaled(plan.scale)
	if share_forearm_twist:
		var fore := sk.get_bone_global_pose(lower)
		var axis: Vector3=(inverse.basis*(plan.wrist-plan.elbow)).normalized()
		var neutral: Vector3=(fore.basis*sk.get_bone_rest(hand).basis).z
		var desired: Vector3=frame.z
		neutral=(neutral-axis*neutral.dot(axis)).normalized()
		desired=(desired-axis*desired.dot(axis)).normalized()
		if not neutral.is_zero_approx() and not desired.is_zero_approx():
			fore.basis=Basis(axis,neutral.signed_angle_to(desired,axis))*fore.basis
			sk.set_bone_global_pose(lower,fore)
			sk.force_update_bone_child_transform(lower)
	var transform := sk.get_bone_global_pose(hand)
	transform.basis=frame
	sk.set_bone_global_pose(hand,transform)
	sk.force_update_bone_child_transform(hand)
func _tool_fingers(side: String,seat: int,u: float) -> void:
	for digit in ["Thumb","Index","Middle","Ring","Little"]:
		for segment in ["Metacarpal","Proximal","Intermediate","Distal"]:
			var bone: int=actor.skeleton.find_bone(side+digit+segment)
			if bone<0: continue
			var pose: Transform3D=body.endpoints[seat].bones[bone]
			var held := pose.basis.get_rotation_quaternion()
			var release := .85*smoothstep(.52,.56,u) if side=="Right" and digit!="Thumb" else 0.0
			actor.skeleton.set_bone_pose_rotation(bone,held.slerp(actor.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion(),release))
