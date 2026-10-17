extends RefCounted
## The non-tool arm is composed by the same final writer. A released hand
## may orient freely; its actual final wrist still obeys the original cone.
const LIMB := preload("res://src/boat/sailor_leg_pose.gd")
const ELBOW := preload("res://src/preview/land_drill_visual_elbow.gd")
const EXACT := preload("res://src/preview/tack/elbow_exact.gd")
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const UNIT := preload("res://src/preview/tack/unit_caps.gd")
static func _plane(actor: Node3D,a: String,b: String,origin: Vector3,radius: float) -> Dictionary:
	var first: Vector3=actor.bone_pose_boat(a).origin
	var last: Vector3=actor.bone_pose_boat(b).origin
	var n: Vector3=(origin-Geometry3D.get_closest_point_to_segment(origin,first,last)).normalized()
	return {"n":n,"support":maxf(first.dot(n),last.dot(n))+radius}
static func _segment_plane(actor: Node3D,a: String,b: String,origin: Vector3,end: Vector3,radius: float) -> Dictionary:
	var first: Vector3=actor.bone_pose_boat(a).origin
	var last: Vector3=actor.bone_pose_boat(b).origin
	var pair := Geometry3D.get_closest_points_between_segments(origin,end,first,last)
	var n: Vector3=(pair[0]-pair[1]).normalized()
	if n.length()<.000001: n=(origin-Geometry3D.get_closest_point_to_segment(origin,first,last)).normalized()
	var caps := []
	for point: Vector3 in [first,last]:
		var delta: Vector3=origin-point
		caps.append({"n":delta.normalized(),"k":radius/maxf(.000001,delta.length())})
	var fit := UNIT.closest(n,caps)
	if not fit.valid: return {"valid":false,"reason":"released segment separating normal","detail":fit}
	n=fit.point
	return {"valid":true,"n":n,"support":maxf(first.dot(n),last.dot(n))+radius}
static func source_arm(writer: RefCounted,side: String,seat: int) -> Dictionary:
	# The source is its actual endpoint world arm, not source local rotations
	# resampled in the currently leaning chest (which raises the elbow).
	var source: Dictionary=writer.body.endpoints[seat]
	return {"shoulder":source.shoulders[side],"elbow":source.elbows[side],"hand":source.hands[side]}
static func common_goal(writer: RefCounted,side: String) -> Dictionary:
	return writer.common_goals[side]
static func forearm_frame(direction: Vector3) -> Basis:
	var first := direction.normalized()
	var second := (Vector3.UP-first*first.y).normalized()
	return Basis(first,second,first.cross(second)).orthonormalized()
static func swivel(s: Vector3,e: Vector3,w: Vector3) -> float:
	var axis := (w-s).normalized()
	var down := (Vector3.DOWN-axis*axis.dot(Vector3.DOWN)).normalized()
	var across := axis.cross(down)
	return atan2((e-s).dot(across),(e-s).dot(down))
static func elbow_pole(s: Vector3,w: Vector3,angle: float) -> Vector3:
	var axis := (w-s).normalized()
	var down := (Vector3.DOWN-axis*axis.dot(Vector3.DOWN)).normalized()
	return s+down*cos(angle)+axis.cross(down)*sin(angle)
static func separating_normal(e: Vector3,w: Vector3,hips: Vector3,chest: Vector3) -> Vector3:
	var pair := Geometry3D.get_closest_points_between_segments(e,w,hips,chest)
	return (pair[0]-pair[1]).normalized()
static func plane_route(first: Vector3,middle: Vector3,last: Vector3,t: float) -> Vector3:
	return first.slerp(middle,smoothstep(0,.5,t)).normalized() if t<.5 else middle.slerp(last,smoothstep(.5,1,t)).normalized()
static func arc(a: Vector3,b: Vector3,centre: Vector3,outward: Vector3,t: float) -> Vector3:
	var first := a-centre
	var last := b-centre
	first.y=0
	last.y=0
	if first.length()<.01 or last.length()<.01: return a.lerp(b,t)
	# Port-to-starboard: front->left->back for the incoming hand and
	# back->right->front for the outgoing hand both turn positively about
	# boat UP. Fix that anatomical winding; a per-frame midpoint-side test
	# switches the arc while the trunk moves and teleports the released hand.
	var angle := fposmod(first.signed_angle_to(last,Vector3.UP),TAU)
	var radial := Basis(Vector3.UP,angle*t)*first.normalized()
	var radius := lerpf(first.length(),last.length(),t)+.080*sin(PI*t)
	var result := centre+radial*radius
	result.y=lerpf(a.y,b.y,t)-.015*sin(PI*t)
	return result
static func solve(writer: RefCounted,side: String,wrist: Vector3,reference: Basis,pole: Vector3,offset: Vector3,maximum_degrees := 44.5,support_normal := Vector3.ZERO,reserve := 0.0) -> Dictionary:
	var actor: Node3D=writer.actor
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var old_e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var old_w: Vector3=actor.bone_pose_boat(side+"Hand").origin
	var a := s.distance_to(old_e)
	var b := old_e.distance_to(old_w)
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var normal_plane := support_normal.normalized()
	var support := maxf(hips.dot(normal_plane),chest.dot(normal_plane))+.191
	if not normal_plane.is_zero_approx():
		var distance := maxf(0,support+reserve-wrist.dot(normal_plane))
		if distance>.05: return {"valid":false,"reason":"free wrist plane corridor","distance":distance}
		wrist+=normal_plane*distance
	var result := ELBOW.guide(s,wrist,a,b,pole,normal_plane,support if not normal_plane.is_zero_approx() else 0)
	if result.valid:
		var pair := Geometry3D.get_closest_points_between_segments(result.point,wrist,hips,chest)
		if pair[0].distance_to(pair[1])<.191: result={"valid":false}
	# The free hand's orientation is chosen AFTER the arm. 180 here removes
	# only that unknown orientation from the elbow construction; the actual
	# wrist is then clamped to <=44.5 and independently measured afterward.
	if not result.valid and normal_plane.is_zero_approx(): result=EXACT.guide(s,wrist,a,b,pole,Vector3.ZERO,hips,chest,.191,.085,180)
	if not result.valid: return result
	var fore: Vector3=(wrist-result.point).normalized()
	# Interpolate wrist attitude in the forearm frame, not two unrelated
	# world hand frames that can pass through an antipodal palm direction.
	var frame := forearm_frame(fore)*reference
	var scale: Vector3=actor.bone_pose_boat(side+"Hand").basis.get_scale()
	var normal := (frame*(offset*scale)).normalized()
	var limit := deg_to_rad(maximum_degrees)
	if normal.dot(fore)<cos(limit):
		var radial: Vector3=(normal-fore*normal.dot(fore)).normalized()
		if radial.is_zero_approx(): radial=fore.cross(Vector3.UP).normalized()
		var clamped: Vector3=fore*cos(limit)+radial*sin(limit)
		frame=Basis(Quaternion(normal,clamped))*frame
	var plan := {"valid":true,"wrist":wrist,"elbow":result.point,"frame":frame,"scale":scale,"offset":offset,"palm":wrist+frame*(offset*scale)}
	writer._apply_arm(side,plan)
	return plan
static func fingers(writer: RefCounted,side: String,from_seat: int,to_seat: int,t: float,open_weight: float,thumb_t := -1.0) -> void:
	var sk: Skeleton3D=writer.actor.skeleton
	for digit in ["Thumb","Index","Middle","Ring","Little"]:
		for segment in ["Metacarpal","Proximal","Intermediate","Distal"]:
			var bone := sk.find_bone(side+digit+segment)
			if bone<0: continue
			var a: Transform3D=writer.body.endpoints[from_seat].bones[bone]
			var b: Transform3D=writer.body.endpoints[to_seat].bones[bone]
			var blend := thumb_t if digit=="Thumb" and thumb_t>=0 else t
			var rotation := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(),blend)
			if digit!="Thumb" or thumb_t<0: rotation=rotation.slerp(sk.get_bone_rest(bone).basis.get_rotation_quaternion(),open_weight)
			sk.set_bone_pose_rotation(bone,rotation)
static func released_arm(writer: RefCounted,side: String,source: Dictionary,goal: Dictionary,t: float,incoming: bool,offset: Vector3,wrist_offset: Vector3,u: float) -> Dictionary:
	if writer.get("open_hand_patch")!=null and writer.open_hand_patch.active(u,side):
		return patched_arm(writer,side,source,offset,wrist_offset,u)
	var actor: Node3D=writer.actor
	var chest: Transform3D=actor.bone_pose_boat("UpperChest")
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var transport: Basis=chest.basis.orthonormalized()*(goal.chest as Transform3D).basis.orthonormalized().inverse()
	var source_upper: Vector3=source.elbow-source.shoulder
	var goal_upper: Vector3=transport*(goal.elbow-goal.shoulder)
	var source_fore: Vector3=source.hand.origin-source.elbow
	var goal_fore: Vector3=transport*(goal.wrist-goal.elbow)
	var outward: Vector3=s-chest.origin
	outward.y=0
	outward=outward.normalized()
	# A released hand has no fixed wrist target. Compose two bone directions
	# directly through an authored low/outboard rest, rather than selecting
	# discontinuous components of a constrained elbow circle each frame.
	var upper_mid := (outward*.65+Vector3.DOWN*.76).normalized()
	# Carry the free wrist above the moving legs. Down/out and inward/up
	# were nearly antipodal; this raised rest has a fixed anatomical winding.
	var fore_mid := (outward*.95+Vector3.UP*.312).normalized()
	var first_upper := source_upper if incoming else goal_upper
	var last_upper := goal_upper if incoming else source_upper
	var first_fore := source_fore if incoming else goal_fore
	var last_fore := goal_fore if incoming else source_fore
	var upper_t := smoothstep(.25,.75,t)
	var upper: Vector3=plane_route(first_upper.normalized(),upper_mid,last_upper.normalized(),upper_t)
	var fore_t := smoothstep(0,.35,t) if t<.5 else smoothstep(.65,1,t)
	var fore: Vector3=first_fore.normalized().slerp(fore_mid,fore_t) if t<.5 else fore_mid.slerp(last_fore.normalized(),fore_t)
	var upper_length: float=source_upper.length()
	var fore_length: float=source_fore.length()
	var trial_e: Vector3=s+upper*upper_length
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest_tip: Vector3=chest.origin
	var upper_pair := Geometry3D.get_closest_points_between_segments(s.lerp(trial_e,.35),trial_e,hips,chest_tip)
	var upper_normal: Vector3=(upper_pair[0]-upper_pair[1]).normalized()
	if upper_normal.length()<.000001: upper_normal=(s-Geometry3D.get_closest_point_to_segment(s,hips,chest_tip)).normalized()
	var body_plane := {"n":upper_normal,"support":maxf(hips.dot(upper_normal),chest_tip.dot(upper_normal))+.213}
	var body_k: float=(body_plane.support-s.dot(body_plane.n))/upper_length
	var upper_constraints := [{"n":Vector3.DOWN,"k":.086/upper_length},{"n":body_plane.n,"k":maxf(body_k,body_k/.35)}]
	for leg in ["Left","Right"]:
		var plane := _plane(actor,leg+"UpperLeg",leg+"LowerLeg",trial_e,.128)
		upper_constraints.append({"n":plane.n,"k":(plane.support-s.dot(plane.n))/upper_length})
	var upper_fit := UNIT.closest(upper,upper_constraints)
	if not upper_fit.valid: return {"valid":false,"reason":"released upper cap", "detail":upper_fit}
	upper=upper_fit.point
	var e := s+upper*upper_length
	var minimum_distance: float=.200+.005*sin(PI*t)
	var minimum_dot: float=clampf((minimum_distance*minimum_distance-upper_length*upper_length-fore_length*fore_length)/(2*upper_length*fore_length),-1,1)
	var fore_constraints := [{"n":upper,"k":minimum_dot}]
	for spec in [["Hips","UpperChest",.192],["LeftUpperLeg","LeftLowerLeg",.124],["RightUpperLeg","RightLowerLeg",.124]]:
		var plane := _segment_plane(actor,spec[0],spec[1],e,e+fore*fore_length,spec[2])
		if not plane.valid: return plane
		fore_constraints.append({"n":plane.n,"k":(plane.support-e.dot(plane.n))/fore_length})
	var fore_fit := UNIT.closest(fore,fore_constraints)
	if not fore_fit.valid: return {"valid":false,"reason":"released forearm cap","detail":fore_fit}
	fore=fore_fit.point
	var w := e+fore*source_fore.length()
	var first_hand: Basis=source.hand.basis.orthonormalized() if incoming else transport*goal.frame
	var last_hand: Basis=transport*goal.frame if incoming else source.hand.basis.orthonormalized()
	var first_axis := first_fore.normalized()
	var last_axis := last_fore.normalized()
	var frame_radial := (first_hand.z-first_axis*first_axis.dot(first_hand.z)).normalized()
	var first_basis := Basis(first_axis,frame_radial,first_axis.cross(frame_radial)).orthonormalized()
	var middle_basis: Basis=Basis(Quaternion(first_axis,fore_mid))*first_basis
	var last_basis: Basis=Basis(Quaternion(fore_mid,last_axis))*middle_basis
	var current: Basis=Basis(Quaternion(first_axis,fore))*first_basis if t<.5 else Basis(Quaternion(fore_mid,fore))*middle_basis
	var scale: Vector3=actor.bone_pose_boat(side+"Hand").basis.get_scale()
	# Interpolate the anatomical palm normal inside the original wrist cone.
	# Clamping a freely slerped attitude after it crosses the antipode makes
	# its radial direction flip, despite a continuous wrist target.
	var first_offset: Vector3=CONTACT.SHEET_OFFSET if incoming else CONTACT.TILLER_OFFSET
	var last_offset: Vector3=CONTACT.TILLER_OFFSET if incoming else CONTACT.SHEET_OFFSET
	var first_local: Basis=first_basis.inverse()*first_hand
	var last_local: Basis=last_basis.inverse()*last_hand
	var first_normal: Vector3=(first_local*(first_offset*scale)).normalized()
	var last_normal: Vector3=(last_local*(last_offset*scale)).normalized()
	var normal: Vector3=first_normal.slerp(last_normal,t).normalized()
	var first_tangent: Vector3=(first_local.x-first_normal*first_normal.dot(first_local.x)).normalized()
	var last_tangent: Vector3=(last_local.x-last_normal*last_normal.dot(last_local.x)).normalized()
	var transported_end: Vector3=Quaternion(first_normal,last_normal)*first_tangent
	var twist: float=transported_end.signed_angle_to(last_tangent,last_normal)
	# The incoming hand rolls around the outside. Keep that authored winding
	# when signed_angle crosses +/-PI as the shoulder transports with the
	# chest, rather than reversing a half-completed roll.
	if incoming: twist=wrapf(twist,-PI*.25,PI*1.75)
	var tangent: Vector3=Basis(normal,twist*t)*(Quaternion(first_normal,normal)*first_tangent)
	var datum: Vector3=(wrist_offset*scale).normalized()
	var datum_tangent: Vector3=(Vector3.RIGHT-datum*datum.x).normalized()
	var datum_frame := Basis(datum,datum_tangent,datum.cross(datum_tangent))
	var target_frame := Basis(normal,tangent,normal.cross(tangent))
	var frame: Basis=current*target_frame*datum_frame.inverse()
	if writer.get("hand_frames")!=null: frame=writer.hand_frames.sample(writer.steering,u,side)
	var plan := {"valid":true,"elbow":e,"wrist":w,"frame":frame,"scale":scale,"offset":offset,"wrist_offset":wrist_offset,"palm":w+frame*(offset*scale)}
	plan.debug={"first_upper":first_upper,"last_upper":last_upper,"first_fore":first_fore,"last_fore":last_fore,"mid_fore":fore_mid,"mid_upper":upper_mid,"s":s,"e":e,"w":w,"chest":chest.origin,"transport":transport}
	writer._apply_arm(side,plan)
	return plan
static func patched_arm(writer: RefCounted,side: String,source: Dictionary,offset: Vector3,wrist_offset: Vector3,u: float) -> Dictionary:
	var actor: Node3D=writer.actor
	var sample: Dictionary=writer.open_hand_patch.sample(writer.steering,u,side)
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var w: Vector3=sample.wrist
	var a: float=(source.elbow-source.shoulder).length()
	var b: float=(source.hand.origin-source.elbow).length()
	var d: float=s.distance_to(w)
	if d<=absf(a-b) or d>=a+b: return {"valid":false,"reason":"open hand patch actual reach"}
	var axis: Vector3=(w-s)/d
	var along: float=(a*a-b*b+d*d)/(2*d)
	var centre: Vector3=s+axis*along
	var guide: Vector3=actor.bone_pose_boat("UpperChest").basis.orthonormalized()*sample.elbow
	var radial: Vector3=guide-axis*guide.dot(axis)
	if radial.length()<.000001: return {"valid":false,"reason":"open hand patch elbow guide"}
	var e: Vector3=centre+radial.normalized()*sqrt(maxf(0,a*a-along*along))
	var scale: Vector3=actor.bone_pose_boat(side+"Hand").basis.get_scale()
	var plan := {"valid":true,"wrist":w,"elbow":e,"frame":sample.frame,"scale":scale,"offset":offset,"wrist_offset":wrist_offset,"palm":w+sample.frame*(offset*scale)}
	writer._apply_arm(side,plan)
	return plan
static func apply(writer: RefCounted,u: float) -> Dictionary:
	var actor: Node3D=writer.actor
	var plans := {}
	if u<.50:
		var source := source_arm(writer,"Left",-1)
		var goal := common_goal(writer,"Left")
		if not goal.valid: return {"Left":goal}
		var t := smoothstep(.12,.50,u)
		var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
		var outward: Vector3=source.shoulder-chest
		outward.y=0
		# Before contact, carry the common pose in the moving chest frame.
		# A frozen future world point can pass from back to front as the
		# sailor crosses and force a full-circle azimuth wrap.
		var transport: Transform3D=actor.bone_pose_boat("UpperChest")*(goal.chest as Transform3D).affine_inverse()
		var wrist := arc(source.hand.origin,transport*goal.wrist,chest,outward.normalized(),t)
		var first: Basis=forearm_frame(source.hand.origin-source.elbow).inverse()*source.hand.basis.orthonormalized()
		var last: Basis=forearm_frame(goal.wrist-goal.elbow).inverse()*goal.frame
		var frame: Basis=first.slerp(last,t)
		var theta := lerp_angle(swivel(source.shoulder,source.elbow,source.hand.origin),swivel(goal.shoulder,goal.elbow,goal.wrist),t)
		var pole := elbow_pole(actor.bone_pose_boat("LeftUpperArm").origin,wrist,theta)
		var offset := CONTACT.SHEET_OFFSET.lerp(goal.offset,t)
		var wrist_offset := CONTACT.SHEET_OFFSET.lerp(CONTACT.TILLER_OFFSET,t)
		var source_normal := separating_normal(source.elbow,source.hand.origin,actor.bone_pose_boat("Hips").origin,chest)
		var goal_normal: Vector3=transport.basis*separating_normal(goal.elbow,goal.wrist,goal.hips,goal.chest.origin)
		var plane := plane_route(source_normal,outward.normalized(),goal_normal.normalized(),t)
		plans.Left=released_arm(writer,"Left",source,goal,t,true,offset,wrist_offset,u)
		var open_weight := .85*smoothstep(.16,.20,u)
		fingers(writer,"Left",-1,1,smoothstep(.20,.50,u),open_weight)
	if u>.52:
		var source := source_arm(writer,"Right",1)
		var goal := common_goal(writer,"Right")
		if not goal.valid: return {"Right":goal}
		var t := smoothstep(.52,.92,u)
		var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
		var outward: Vector3=source.shoulder-chest
		outward.y=0
		var transport: Transform3D=actor.bone_pose_boat("UpperChest")*(goal.chest as Transform3D).affine_inverse()
		var wrist := arc(transport*goal.wrist,source.hand.origin,chest,outward.normalized(),t)
		var first: Basis=forearm_frame(goal.wrist-goal.elbow).inverse()*goal.frame
		var last: Basis=forearm_frame(source.hand.origin-source.elbow).inverse()*source.hand.basis.orthonormalized()
		var frame: Basis=first.slerp(last,t)
		var theta := lerp_angle(swivel(goal.shoulder,goal.elbow,goal.wrist),swivel(source.shoulder,source.elbow,source.hand.origin),t)
		var pole := elbow_pole(actor.bone_pose_boat("RightUpperArm").origin,wrist,theta)
		var grip_t := smoothstep(.52,.92,u)
		var offset: Vector3=(goal.offset as Vector3).lerp(CONTACT.SHEET_OFFSET,grip_t)
		var wrist_offset := CONTACT.TILLER_OFFSET.lerp(CONTACT.SHEET_OFFSET,grip_t)
		var source_normal := separating_normal(source.elbow,source.hand.origin,actor.bone_pose_boat("Hips").origin,chest)
		var goal_normal: Vector3=transport.basis*separating_normal(goal.elbow,goal.wrist,goal.hips,goal.chest.origin)
		var plane := plane_route(goal_normal.normalized(),outward.normalized(),source_normal,t)
		plans.Right=released_arm(writer,"Right",source,goal,t,false,offset,wrist_offset,u)
		var open_weight := .85*(1-smoothstep(.89,.92,u))
		fingers(writer,"Right",-1,1,grip_t,open_weight,smoothstep(.92,.96,u))
	return plans
