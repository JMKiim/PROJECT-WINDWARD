extends Node
## One authored pose writer and one display path. No material solver feedback.
const LIMB := preload("res://src/boat/sailor_leg_pose.gd")
const PROFILE := preload("res://src/preview/land_drill_visual_profile.gd")
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const ELBOW := preload("res://src/preview/land_drill_visual_elbow.gd")
const TILLER_PLAN := preload("res://src/preview/land_drill_tiller_contact.gd")
const HIKING_PROFILE := preload("res://src/preview/land_drill_hiking_profile.gd")
var actor: Node3D
var time := -1.0
var clip_section := "entry"
var clip_time := .5
var wrap_direction := {}
var wrap_sweep := {}
var contact_angles := {}
var reference_frames := {}
var seated_references := {}
var reach_errors := {}
var joint_witness := {}
var pose_points := {}
var profile := PROFILE.new()
var ease_relaxation := 0.0
var active_weight := 1.0
var hiking_profile: RefCounted=HIKING_PROFILE.new()
func working_goal(point: Vector3) -> Vector3:
	# The seated guides must travel with the unchanged hiking body. This
	# authors the working space; the finite grip is still solved on the shaft.
	if actor.hike>0:
		point+=Vector3(-.60,-.20,0)*actor.hike
	return actor.from_port(point)
func tiller_goal(point: Vector3) -> Vector3:
	var seated: Vector3=actor.from_port(point)
	if actor.hike<=0: return seated
	if hiking_profile!=null:
		var start: Vector3=profile.palm_at("helper","right",actor.amount,0)
		var delta: Vector3=profile.palm_at("helper","right",actor.amount,1)-start
		var progress := clampf((point-start).dot(delta)/delta.length_squared(),0,1)
		return actor.from_port(hiking_profile.tiller_at(actor.amount,actor.hike,progress))
	var joint: Vector3=actor.joint_boat()
	var axis: Vector3=actor.from_port(actor.rest_guide.sample(actor.amount,actor.hike))
	var offset: Vector3=point-profile.palm_at("helper","right",actor.amount,0)
	var goal: Vector3=joint+axis*actor.palm_boat().distance_to(joint)+actor.from_port(Vector3(-offset.x,offset.y*.3,offset.z*.3))
	return seated.lerp(goal,smoothstep(0,.5,actor.hike))
func setup(value: Node3D) -> void:
	actor=value
	# Each role reads its own authored seat, rather than reusing a sheet
	# hand's port orientation as the starboard tiller grip. Sample once only.
	var original_side: int=actor.seat_side
	for seat: int in [-1,1]:
		actor.seat_side=seat
		actor._sample_steering_pose()
		var frames := {}
		for hand in ["Left","Right"]: frames[hand]=actor.bone_pose_boat(hand+"Hand").basis.orthonormalized()
		seated_references[seat]=frames
	actor.seat_side=original_side
	actor._sample_steering_pose()
	select_reference(original_side)
func select_reference(seat: int) -> void:
	if seated_references.has(seat): reference_frames=seated_references[seat]
func prepare() -> void: pass
func sample_entry(work: float,_weight: float) -> void:
	time=-1
	clip_section="entry"
	clip_time=work
	_pose("work",work)
func sample(clock: float,_weight: float) -> void:
	time=clock
	clip_section="cycle"
	clip_time=clock
	_pose("helper" if clock>=1 else "recovery",clock-1 if clock>=1 else clock)
func _pose(section: String,progress: float) -> void:
	reach_errors.clear()
	joint_witness.clear()
	var tiller: String=actor.tiller_hand()
	var start: Dictionary=_tiller_plan(tiller,tiller_goal(profile.palm_at("helper","right",actor.amount,0)))
	var finish: Dictionary=_tiller_plan(tiller,tiller_goal(profile.palm_at("helper","right",actor.amount,1)))
	pose_points.clear()
	if start.valid and actor.hike>0 and hiking_profile!=null:
		# The hiking low point is authored already. A future helper-end
		# calculation must not switch today's sheet hand to a different lane.
		pose_points={"catch":_catch_goal(start.helper),"low":actor.from_port(hiking_profile.low_at(actor.amount,actor.hike))}
	elif start.valid and finish.valid:
		var line: Vector3=finish.helper-actor.sheet_study.block_anchor
		var left: String=actor.sheet_hand()
		var shoulder: Vector3=actor.bone_pose_boat(left+"UpperArm").origin
		var elbow: Vector3=actor.bone_pose_boat(left+"LowerArm").origin
		var wrist: Vector3=actor.bone_pose_boat(left+"Hand").origin
		var maximum: float=shoulder.distance_to(elbow)+elbow.distance_to(wrist)+(actor.bone_pose_boat(left+"Hand").basis*CONTACT.SHEET_OFFSET).length()-.025
		var offset: Vector3=actor.sheet_study.block_anchor-shoulder
		var half := line.dot(offset)
		var discriminant: float=half*half-line.length_squared()*(offset.length_squared()-maximum*maximum)
		if discriminant>=0:
			var fraction: float=clampf((-half-sqrt(discriminant))/line.length_squared()+.015,0,.94)
			var knee_height: float=maxf(actor.bone_pose_boat("LeftLowerLeg").origin.y,actor.bone_pose_boat("RightLowerLeg").origin.y)+.17
			if line.y>0: fraction=maxf(fraction,(knee_height-actor.sheet_study.block_anchor.y)/line.y)
			fraction=clampf(fraction,0,.94)
			pose_points={"catch":_catch_goal(start.helper),"low":actor.sheet_study.block_anchor+line*fraction}
	for role in ["right","left"]:
		var side: String=actor.tiller_hand() if role=="right" else actor.sheet_hand()
		var goal: Vector3=working_goal(profile.palm_at(section,role,actor.amount,progress))
		if role=="right": goal=tiller_goal(profile.palm_at(section,role,actor.amount,progress))
		if role=="left" and not pose_points.is_empty():
			if section=="work":
				var ready: Vector3=pose_points.low.lerp(pose_points.catch,.45)
				goal=pose_points.low.lerp(ready,smoothstep(0,.5,progress)) if progress<.5 else ready.lerp(pose_points.catch,smoothstep(.5,1,progress))
			elif section=="helper":
				var u := smoothstep(.12,.85,progress)
				goal=pose_points.catch.lerp(pose_points.low,u)+actor.from_port(Vector3(.015,0,-.03))*sin(PI*u)
			else: goal=pose_points.low.lerp(pose_points.catch,smoothstep(0,1,progress))
			if actor.hike>0:
				var travel: Vector3=pose_points.catch-pose_points.low
				var fraction := clampf((goal-pose_points.low).dot(travel)/travel.length_squared(),0,1)
				# Knees enter this lane during the first eighth of hiking,
				# not only at the fully extended body posture.
				goal+=Vector3(0,0,-.07)*sin(PI*fraction)*smoothstep(0,.125,actor.hike)
		_solve(side,goal,role=="right")
	# Partial pressure release follows actual negative feed, not the idle
	# return flag. The palm and thumb keep their channel; no large arm gesture.
	var opening := ease_relaxation
	if section=="helper":
		# Close progressively during the approach while the helper holds trim.
		opening=maxf(opening,sin(PI*smoothstep(0,1,progress))*.30)
	for digit in ["Index","Middle","Ring","Little"]:
		for segment in ["Proximal","Intermediate","Distal"]:
			var bone: int=actor.skeleton.find_bone(actor.sheet_hand()+digit+segment)
			var closed: Quaternion=actor.skeleton.get_bone_pose_rotation(bone)
			var rest: Quaternion=actor.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			actor.skeleton.set_bone_pose_rotation(bone,closed.slerp(rest,opening))
func _catch_goal(helper: Vector3) -> Vector3:
	# Regrasp the loaded strand below the supporting thumb when hiking,
	# rather than forcing both arms to meet beyond it across the upper torso.
	var offset := .04
	offset=lerpf(.04,-.14,smoothstep(0,.125,actor.hike))
	return helper+(helper-actor.sheet_study.block_anchor).normalized()*offset
func _solve(side: String,palm: Vector3,tiller: bool) -> void:
	if tiller:
		_solve_tiller(side,palm)
		return
	_solve_sheet(side,palm)

func _skeleton_frame() -> Transform3D:
	return actor.skeleton_to_boat() if actor.has_method("skeleton_to_boat") else actor.global_transform.affine_inverse()*actor.skeleton.global_transform

func _solve_sheet(side: String,palm: Vector3) -> void:
	var skeleton: Skeleton3D=actor.skeleton
	var upper := skeleton.find_bone(side+"UpperArm")
	var lower := skeleton.find_bone(side+"LowerArm")
	var hand := skeleton.find_bone(side+"Hand")
	var to_boat: Transform3D=_skeleton_frame()
	var inverse := to_boat.affine_inverse()
	var s: Vector3=(to_boat*skeleton.get_bone_global_pose(upper)).origin
	var e: Vector3=(to_boat*skeleton.get_bone_global_pose(lower)).origin
	var w: Vector3=(to_boat*skeleton.get_bone_global_pose(hand)).origin
	var scale: Vector3=(to_boat.basis*skeleton.get_bone_global_pose(hand).basis).get_scale()
	var hand_length: float=(CONTACT.SHEET_OFFSET*scale).length()
	var forward := lerpf(.85,1,smoothstep(0,1,actor.amount))
	var normal: Vector3=actor.from_port(Vector3(forward,0,-sqrt(maxf(0,1-forward*forward))))
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var support: float=maxf(hips.dot(normal),chest.dot(normal))+.195
	if actor.hike>0:
		# A hiker reaches above a sloping torso. A fixed inboard plane can
		# reject that clear space; use its actual capsule tangent instead.
		var near := Geometry3D.get_closest_point_to_segment(palm,hips,chest)
		normal=(palm-near).normalized()
		support=maxf(hips.dot(normal),chest.dot(normal))+.195
	var pole: Vector3=s+actor.from_port(Vector3(-.13,-.30,-.32))
	var plan := ELBOW.guide(s,palm,s.distance_to(e),e.distance_to(w)+hand_length,pole,normal,support)
	if actor.hike>0:
		var free := ELBOW.guide(s,palm,s.distance_to(e),e.distance_to(w)+hand_length,pole,Vector3.ZERO,0)
		if free.valid:
			var pair := Geometry3D.get_closest_points_between_segments(free.point,palm,hips,chest)
			if pair[0].distance_to(pair[1])>=.195: plan=free
	if not plan.valid:
		# A single fixed plane can reject a clear forearm on the other side
		# of the torso. Derive its tangent from the actual extended arm.
		var free := ELBOW.guide(s,palm,s.distance_to(e),e.distance_to(w)+hand_length,pole,Vector3.ZERO,0)
		if free.valid:
			var pair: PackedVector3Array=Geometry3D.get_closest_points_between_segments(free.point,palm,hips,chest)
			normal=(pair[0]-pair[1]).normalized()
			support=maxf(hips.dot(normal),chest.dot(normal))+.195
			plan=ELBOW.guide(s,palm,s.distance_to(e),e.distance_to(w)+hand_length,pole,normal,support)
	if not plan.valid:
		reach_errors[side]=1
		joint_witness[side]=plan
		return
	var fore: Vector3=(palm-plan.point).normalized()
	var wrist: Vector3=palm-fore*hand_length
	var frame: Basis=reference_frames[side]
	frame=Basis(Quaternion((frame*(CONTACT.SHEET_OFFSET*scale)).normalized(),fore))*frame
	# Share pronation with the forearm and keep the thin-sheet channel level.
	# This preserves palm position, bone lengths and the neutral wrist.
	var channel: PackedVector3Array=CONTACT.sheet_channel(side)
	var direction: Vector3=frame*((channel[-1]-channel[0])*scale)
	# A regularized local leveling turn has no competing +/-90-degree
	# roots. Choosing the nearest exact root flipped the fist at +.25 steer.
	var slope := fore.cross(direction).y
	var roll := -atan2(direction.y*slope,slope*slope+.12*direction.length_squared())
	roll=clampf(roll,-deg_to_rad(60),deg_to_rad(60))
	frame=Basis(Quaternion(fore,roll))*frame
	LIMB.solve(skeleton,upper,lower,hand,inverse*wrist,inverse*plan.point)
	var global_fore: Transform3D=skeleton.get_bone_global_pose(lower)
	var local_fore := (inverse.basis*fore).normalized()
	global_fore.basis=Basis(Quaternion(local_fore,roll))*global_fore.basis
	skeleton.set_bone_global_pose(lower,global_fore)
	skeleton.force_update_bone_child_transform(lower)
	var global_hand: Transform3D=skeleton.get_bone_global_pose(hand)
	global_hand.basis=to_boat.basis.inverse()*frame.scaled(scale)
	skeleton.set_bone_global_pose(hand,global_hand)
	skeleton.force_update_bone_child_transform(hand)
	reach_errors[side]=0
	joint_witness[side]={"wrist_goal":wrist,"elbow":plan.point,"wrist_deg":0}


func _tiller_plan(side: String,guide: Vector3) -> Dictionary:
	var skeleton: Skeleton3D=actor.skeleton
	var upper := skeleton.find_bone(side+"UpperArm")
	var lower := skeleton.find_bone(side+"LowerArm")
	var hand := skeleton.find_bone(side+"Hand")
	var to_boat: Transform3D=_skeleton_frame()
	var inverse := to_boat.affine_inverse()
	var s: Vector3=(to_boat*skeleton.get_bone_global_pose(upper)).origin
	var e: Vector3=(to_boat*skeleton.get_bone_global_pose(lower)).origin
	var w: Vector3=(to_boat*skeleton.get_bone_global_pose(hand)).origin
	var first := s.distance_to(e)
	var second := e.distance_to(w)
	var joint: Vector3=actor.joint_boat()
	# Elevate the authored shaft direction over the actual thigh envelope.
	# This changes its guide, not its length, the input range or the anatomy.
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
			# Exact sphere-to-line clearance, not vertical clearance at Z.
			guide.y=maxf(guide.y,joint.y+(-half+sqrt(discriminant))/a+.005)
	if actor.hike>0:
		var hiking_axis := (guide-joint).normalized()
		var neck: Vector3=actor.bone_pose_boat("Neck").origin
		var head: Vector3=actor.bone_pose_boat("Head").origin
		var hips: Vector3=actor.bone_pose_boat("Hips").origin
		var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
		var caps := [[neck,head,.114],[head,head,.154],[hips,chest,.177]]
		for limb in ["Left","Right"]: caps.append([actor.bone_pose_boat(limb+"UpperLeg").origin,actor.bone_pose_boat(limb+"LowerLeg").origin,.114])
		# One bounded contact-cone projection includes knees and upper body.
		# Using the actual closest point avoids aiming past a capsule end;
		# revisiting all caps prevents a face fix undoing leg clearance.
		for iteration in 8:
			var changed := false
			for cap in caps:
				var pair := Geometry3D.get_closest_points_between_segments(joint,joint+hiking_axis*actor.extension_span,cap[0],cap[1])
				if pair[0].distance_to(pair[1])>=float(cap[2])-.000001: continue
				var centre: Vector3=pair[1]-joint
				var centre_axis := centre.normalized()
				var tangent := hiking_axis-centre_axis*hiking_axis.dot(centre_axis)
				if tangent.is_zero_approx():
					var preferred: Vector3=actor.from_port(Vector3.RIGHT)
					tangent=preferred-centre_axis*preferred.dot(centre_axis)
				var half := asin(clampf(float(cap[2])/centre.length(),0,1))
				hiking_axis=centre_axis*cos(half)+tangent.normalized()*sin(half)
				changed=true
			if not changed: break
		guide=joint+hiking_axis*guide.distance_to(joint)
		var held: Transform3D=actor.bone_pose_boat(side+"Hand")
		var plan := TILLER_PLAN._shared_plan(actor,side,guide,held,s,e,w,true)
		if plan.valid: plan.helper=plan.wrist+plan.frame*(CONTACT.assist_local(side)*plan.scale)
		return plan
	var axis := (guide-joint).normalized()
	var scale: Vector3=(to_boat.basis*skeleton.get_bone_global_pose(hand).basis).get_scale()
	var frame: Basis=reference_frames[side]
	frame=Basis(Quaternion((frame*CONTACT.tiller_axis(side)).normalized(),axis))*frame
	var offset: Vector3=frame*(CONTACT.TILLER_OFFSET*scale)
	var radial: Vector3=offset-axis*offset.dot(axis)
	var toward: Vector3=s-joint-axis*(s-joint).dot(axis)
	var roll := atan2((-toward).dot(axis.cross(radial)),(-toward).dot(radial))
	frame=Basis(Quaternion(axis,roll))*frame
	offset=frame*(CONTACT.TILLER_OFFSET*scale)
	var palm_direction := offset.normalized()
	var along := (axis-palm_direction*axis.dot(palm_direction)).normalized()
	var fore := palm_direction*cos(deg_to_rad(44))+along*sin(deg_to_rad(44))
	# Match the approved wrist cone with a one-degree safety reserve. Grip slides;
	# upper-arm reach is a quadratic with only two analytic roots, no search.
	var base := joint-offset-second*fore-s
	var half := base.dot(axis)
	var discriminant := half*half-base.length_squared()+first*first
	if discriminant<0:
		return {"valid":false,"reason":"tiller grip quadratic has no reach"}
	var selected := INF
	var selected_elbow := Vector3.ZERO
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var roots := []
	for grip in [-half-sqrt(discriminant),-half+sqrt(discriminant)]:
		var palm: Vector3=joint+axis*grip
		var wrist: Vector3=palm-offset
		var elbow: Vector3=wrist-second*fore
		var pair: PackedVector3Array=Geometry3D.get_closest_points_between_segments(elbow,wrist,hips,chest)
		roots.append({"grip":grip,"drop":s.y-elbow.y,"body":pair[0].distance_to(pair[1])})
		if grip<.25 or grip>actor.extension_span-.045 or s.y-elbow.y<.0805 or pair[0].distance_to(pair[1])<.190: continue
		if not is_finite(selected) or elbow.y<selected_elbow.y:
			selected=grip
			selected_elbow=elbow
	if not is_finite(selected):
		return {"valid":false,"reason":"tiller roots violate body/drop/span","roots":roots}
	var palm: Vector3=joint+axis*selected
	var wrist: Vector3=palm-offset
	return {"valid":true,"palm":palm,"wrist":wrist,"elbow":selected_elbow,"frame":frame,"scale":scale,"helper":wrist+frame*(CONTACT.assist_local(side)*scale),"grip_metres":selected,"guide_adjustment_m":palm.distance_to(guide)}

func _solve_tiller(side: String,guide: Vector3) -> void:
	var plan := _tiller_plan(side,guide)
	joint_witness[side]=plan
	reach_errors[side]=0 if plan.valid else 1
	if not plan.valid: return
	var skeleton: Skeleton3D=actor.skeleton
	var upper := skeleton.find_bone(side+"UpperArm")
	var lower := skeleton.find_bone(side+"LowerArm")
	var hand := skeleton.find_bone(side+"Hand")
	var to_boat: Transform3D=_skeleton_frame()
	var inverse := to_boat.affine_inverse()
	LIMB.solve(skeleton,upper,lower,hand,inverse*plan.wrist,inverse*plan.elbow)
	var global_hand: Transform3D=skeleton.get_bone_global_pose(hand)
	global_hand.basis=to_boat.basis.inverse()*plan.frame.scaled(plan.scale)
	skeleton.set_bone_global_pose(hand,global_hand)
	skeleton.force_update_bone_child_transform(hand)
func held_points() -> PackedVector3Array:
	var sheet: PackedVector3Array=actor.sheet_channel_boat()
	# The occluded grip interior uses the central60mm, not an artificial
	# 116mm straight channel protruding past both sides of the closed fist.
	sheet=sheet.slice(1,4)
	var helper: PackedVector3Array=CONTACT.helper_channel(actor.bone_pose_boat(actor.tiller_hand()+"Hand"),actor.tiller_hand())
	var right := time>=1
	var path := PackedVector3Array([actor.sheet_study.block_anchor])
	if right:
		var weight := 1-smoothstep(0,.15,time-1)
		for point in sheet:
			var settled := Geometry3D.get_closest_point_to_segment(point,path[0],helper[0])
			path.append(settled.lerp(point,weight))
		path.append_array(helper)
	else:
		path.append_array(sheet)
		if time>=0 and time<.15: path.append_array(helper)
		elif active_weight>0 and time<0 and clip_time>=.98 and helper[0].y<sheet[-1].y: path.append_array(helper)
	# The short displayed outlet falls under gravity; never drives trim.
	path.append(path[-1]+Vector3(0,-.25,0))
	return _clear_body_path(path)

func _clear_body_path(path: PackedVector3Array) -> PackedVector3Array:
	var capsules := []
	for cap in [["Hips","UpperChest",.156],["LeftUpperLeg","LeftLowerLeg",.096],["RightUpperLeg","RightLowerLeg",.096],["LeftLowerLeg","LeftFoot",.064],["RightLowerLeg","RightFoot",.064]]:
		capsules.append([actor.bone_pose_boat(cap[0]).origin,actor.bone_pose_boat(cap[1]).origin,float(cap[2])])
	# Only the loose tail endpoint is movable. Actual grasp knots stay fixed.
	for capsule in capsules:
		var nearest := Geometry3D.get_closest_point_to_segment(path[-1],capsule[0],capsule[1])
		var direction: Vector3=path[-1]-nearest
		if direction.length()<capsule[2]+.004:
			path[-1]=nearest+(direction.normalized() if not direction.is_zero_approx() else actor.from_port(Vector3.RIGHT))*(capsule[2]+.004)
	# One display-route construction may add contact bends around a leg.
	# Neither this length nor these points feed the logical trim or pose.
	for iteration in 24:
		var changed := false
		for segment in path.size()-1:
			for capsule in capsules:
				var pair: PackedVector3Array=Geometry3D.get_closest_points_between_segments(path[segment],path[segment+1],capsule[0],capsule[1])
				var direction: Vector3=pair[0]-pair[1]
				if direction.length()>=capsule[2]+.001: continue
				if direction.is_zero_approx(): direction=actor.from_port(Vector3.RIGHT)
				var point: Vector3=pair[1]+direction.normalized()*(capsule[2]+.006)
				path.insert(segment+1,point)
				changed=true
				break
			if changed: break
		if not changed: break
	return path
