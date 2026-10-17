extends RefCounted
const HEAD_ARC := preload("res://src/preview/tack/head_arc.gd")
static var bypass_height := .51
static func common_axis(actor: Node3D) -> Vector3:
	var physical: float=-actor.seat_side*actor.amount if actor!=null else 0.0
	return Vector3(-physical*.15,.35,.55).normalized()
## Aft preposition before the body turns; no direct sweep through the neck.
static func sample(body: RefCounted,joint: Vector3,u: float,cross: float,actor: Node3D=null) -> Dictionary:
	var start: Vector3=body.endpoints[-1].palms.Right
	var finish: Vector3=body.endpoints[1].palms.Left
	var entry := joint+Vector3(-.25,.35,-.065)
	var centre := joint+common_axis(actor)*.34
	var exit := joint+Vector3(.25,.35,-.065)
	var support: Vector3=body.tool_support("Right" if u<=.5 else "Left") if body.has_method("tool_support") else entry if u<=.5 else exit
	if u<=.5: return _outboard_arc(start,entry,centre,joint,u,cross*2,-1,body.endpoints[-1].head,support)
	return _outboard_arc(finish,exit,centre,joint,1-u,(1-cross)*2,1,body.endpoints[1].head,support)
static func _outboard_arc(start: Vector3,entry: Vector3,centre: Vector3,joint: Vector3,u: float,body_progress: float,side: int,head: Vector3,support: Vector3) -> Dictionary:
	var bypass := Vector3(side*.86,bypass_height,0).normalized()
	var aft := Vector3(side*.10,.35,.55).normalized()
	var axis: Vector3
	var grip: float
	if u<.1:
		var t := smoothstep(0,.1,u)
		axis=HEAD_ARC.sample((start-joint).normalized(),bypass,head-joint,.18,t)
		grip=lerpf(start.distance_to(joint),(start.distance_to(joint)+entry.distance_to(joint))*.5,t)
	elif u<.28:
		var t := smoothstep(.1,.28,u)
		axis=bypass.slerp(aft,t)
		grip=lerpf((start.distance_to(joint)+entry.distance_to(joint))*.5,.35,t)
	else:
		# Keep the carrying hand on its OWN anatomical shoulder side while
		# the trunk turns. A fixed old-side waypoint forces it across the
		# back onto the opposite elbow branch before the shared grip.
		var return_inboard := smoothstep(.28,.40,u)
		var settle := smoothstep(.40,.46,u)
		axis=aft.slerp((support-joint).normalized(),return_inboard)
		axis=axis.slerp((centre-joint).normalized(),settle)
		grip=lerpf(.35,support.distance_to(joint),return_inboard)
		grip=lerpf(grip,centre.distance_to(joint),settle)
	return {"axis":axis,"grip":grip}
static func _outside_body(actor: Node3D,axis: Vector3,preferred: Vector3) -> Vector3:
	var joint: Vector3=actor.joint_boat()
	# One consistent outboard hemisphere routes the bar around the entire
	# sailor. Fixing the head alone by dipping it would cut through the trunk.
	for iteration in 4:
		for cap in [["Hips","UpperChest",.192],["Neck","Head",.129],["Head","Head",.174],["LeftUpperLeg","LeftLowerLeg",.129],["RightUpperLeg","RightLowerLeg",.129]]:
			var a: Vector3=actor.bone_pose_boat(cap[0]).origin-joint
			var b: Vector3=actor.bone_pose_boat(cap[1]).origin-joint
			var pair := Geometry3D.get_closest_points_between_segments(Vector3.ZERO,axis*actor.extension_span,a,b)
			var centre: Vector3=pair[1]
			var radial: float=cap[2]
			var distance := pair[0].distance_to(centre)
			if distance>=radial+.03: continue
			var normal := centre.normalized()
			var angle := acos(clampf(axis.dot(normal),-1,1))
			var half := asin(clampf(radial/centre.length(),0,1))
			var outside := preferred-normal*normal.dot(preferred)
			var tangent := axis-normal*axis.dot(normal)
			tangent+=outside.normalized()*2*(1-smoothstep(radial,radial+.03,distance))
			if tangent.is_zero_approx(): tangent=normal.cross(Vector3.RIGHT)
			angle=maxf(angle,half+.005)
			axis=normal*cos(angle)+tangent.normalized()*sin(angle)
	return axis.normalized()
static func obstacles(actor: Node3D,axis: Vector3) -> Array:
	var failures := []
	var joint: Vector3=actor.joint_boat()
	var tip: Vector3=joint+axis*actor.extension_span
	for cap in [["Hips","UpperChest",.177],["Neck","Head",.114],["Head","Head",.154],["LeftUpperLeg","LeftLowerLeg",.114],["RightUpperLeg","RightLowerLeg",.114]]:
		var a: Vector3=actor.bone_pose_boat(cap[0]).origin
		var b: Vector3=actor.bone_pose_boat(cap[1]).origin
		var pair := Geometry3D.get_closest_points_between_segments(joint,tip,a,b)
		var gap: float=pair[0].distance_to(pair[1])-float(cap[2])
		if gap<0: failures.append({"cap":cap[0],"gap":gap})
	return failures
