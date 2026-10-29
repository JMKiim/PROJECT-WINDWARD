extends RefCounted
## Retained working grasp -> existing crossing endpoint. This is a finite
## pose bridge,not a new hand search or a source of logical sheet travel.
const BRIDGE := preload("res://src/preview/tack/endpoint_bridge.gd")
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const SECONDS := .32
static func ready(actor: Node3D,wheel: RefCounted) -> bool:
	# If the helper alone holds the sheet,finish only the actual main-hand
	# regrasp. Do not wait for its recovery clip or neutral work=.5 as well.
	return actor.hike<=.000001 and actor.grip_phase=="HOLD" and actor.sheet_control.weight>=.999999 and wheel.motion!=null and wheel.motion.contact_state().sheet_holds
static func retain(actor: Node3D) -> Dictionary:
	return {"work":actor.sheet_control.work,"clock":actor.sheet_control.regrip_time,"ease":actor.sheet_control.ease_relaxation,"yaw":actor.look_pose.yaw,"pitch":actor.look_pose.pitch,"look_enabled":actor.look_enabled,"side":actor.seat_side}
static func capture(model: RefCounted,u: float,state: Dictionary) -> Dictionary:
	var actor: Node3D=model.actor
	var data := BRIDGE.capture(model,u)
	var looked: bool=actor.look_enabled
	actor.seat_side=state.side
	actor.hike=0; actor.hike_target=0
	actor.sheet_control.work=state.work
	actor.sheet_control.regrip_time=state.clock
	actor.sheet_control.weight=1
	actor.sheet_control.ease_relaxation=state.ease
	actor.look_enabled=state.look_enabled
	actor.look_pose.yaw=state.yaw; actor.look_pose.pitch=state.pitch
	actor.set_amount(-float(state.side)*model.steering)
	var bones := []
	for index in actor.skeleton.get_bone_count(): bones.append(actor.skeleton.get_bone_pose(index))
	data.normal=bones
	data.normal_root=actor.get_node("Pose").transform
	actor.look_enabled=looked
	actor.sheet_control.work=.5
	actor.sheet_control.ease_relaxation=0
	return data
static func align_tool(model: RefCounted,weight: float) -> Dictionary:
	if weight<=.000001 or weight>=.999999: return {"valid":true}
	var actor: Node3D=model.actor
	var side: String=actor.tiller_hand()
	var hand: Transform3D=actor.bone_pose_boat(side+"Hand")
	var elbow: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var palm: Vector3=hand*CONTACT.TILLER_OFFSET
	var joint: Vector3=actor.joint_boat()
	var axis := (palm-joint).normalized()
	var frame: Basis=Basis(Quaternion((hand.basis*CONTACT.tiller_axis(side)).normalized(),axis))*hand.basis.orthonormalized()
	# Continue the current elbow on its exact two-bone reach circle. The
	# offline field constructor's extra reserve can reject an already valid
	# normal elbow;actual wrist/drop/body guards are checked independently.
	var plan: Dictionary=model._field_contact(side,axis,palm.distance_to(joint),frame,elbow)
	if not plan.valid: return plan
	# Preserve the bridge's existing forearm-roll distribution. Only the
	# tiny finite-shaft alignment is corrected inside this pose writer.
	var shared: bool=model.share_forearm_twist
	model.share_forearm_twist=false
	model._apply_arm(side,plan)
	model.share_forearm_twist=shared
	model.settle_upper_twist(side,weight)
	return plan
static func prefix(actor: Node3D,state: Dictionary,weight: float) -> Dictionary:
	var sheet: PackedVector3Array=actor.sheet_channel_boat().slice(1,4)
	var helper := CONTACT.helper_channel(actor.bone_pose_boat(actor.tiller_hand()+"Hand"),actor.tiller_hand())
	var clock: float=state.clock
	var initial := 0.0
	if clock>=1: initial=smoothstep(1,1.1,clock)
	elif clock>=0 and clock<.5: initial=1-smoothstep(.15,.25,clock)
	# The main hand is already closed at admission. Withdraw the helper
	# display contact continuously;never replay a released-main-hand clock.
	var support := initial*(1-weight)
	# Same approved internal outlet freedom as the crossing display. The
	# grasp centre stays fixed;an exit guide may otherwise start inside the
	# adjacent tube and no exterior wrap can repair that fixed boundary.
	var joint: Vector3=actor.joint_boat()
	var tip: Vector3=joint+(actor.palm_boat()-joint).normalized()*actor.extension_span
	var nearest := Geometry3D.get_closest_point_to_segment(sheet[-1],joint,tip)
	var radial: Vector3=sheet[-1]-nearest
	if radial.length()<.021 and radial.length()>.000001: sheet[-1]=nearest+radial.normalized()*.021
	var path := PackedVector3Array([actor.sheet_study.block_anchor])
	path.append_array(sheet)
	for point in helper: path.append(sheet[-1].lerp(point,support))
	var knots := PackedInt32Array([0,1,2,3])
	if support>=.999999: knots.append_array(PackedInt32Array([4,5,6]))
	return {"path":path,"knots":knots}
static func clear_sheet_grasp(model: RefCounted,weight: float) -> Dictionary:
	if weight<=.000001 or weight>=.999999: return {"valid":true,"correction_m":0.0}
	var actor: Node3D=model.actor
	var side: String=actor.sheet_hand()
	var hand: Transform3D=actor.bone_pose_boat(side+"Hand")
	var palm: Vector3=hand*CONTACT.SHEET_OFFSET
	var joint: Vector3=actor.joint_boat()
	var axis: Vector3=(actor.palm_boat()-joint).normalized()
	var near := Geometry3D.get_closest_point_to_segment(palm,joint,joint+axis*actor.extension_span)
	var radial: Vector3=palm-near
	var depth := .021-radial.length()
	if depth<=0: return {"valid":true,"correction_m":0.0}
	if depth>.010 or radial.length()<.000001: return {"valid":false,"reason":"entry sheet centre outside bounded corridor","depth":depth}
	# A new intermediate grasp must not pass through the finite shaft.
	# Project this pose goal before any rope display runs,not vice versa.
	var wrist := hand.origin+radial.normalized()*depth
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var old_e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var a := s.distance_to(old_e); var b := old_e.distance_to(hand.origin)
	var distance := s.distance_to(wrist)
	if distance<=absf(a-b) or distance>=a+b: return {"valid":false,"reason":"entry sheet actual reach"}
	var along := (wrist-s)/distance
	var x := (a*a-b*b+distance*distance)/(2*distance)
	var centre := s+along*x
	var pole := old_e-centre
	pole-=along*pole.dot(along)
	if pole.length()<.000001: return {"valid":false,"reason":"entry sheet elbow circle"}
	var elbow := centre+pole.normalized()*sqrt(maxf(0,a*a-x*x))
	var plan := {"valid":true,"wrist":wrist,"elbow":elbow,"frame":hand.basis.orthonormalized(),"scale":hand.basis.get_scale(),"offset":CONTACT.SHEET_OFFSET,"correction_m":depth}
	var shared: bool=model.share_forearm_twist
	model.share_forearm_twist=false; model._apply_arm(side,plan); model.share_forearm_twist=shared
	model.settle_upper_twist(side,weight)
	return plan
static func park(wheel: RefCounted) -> void:
	# The maneuver writer owns the visible transition. Adopt its normal
	# destination clock without resetting metres,ledger or handover count.
	wheel.work=.5
	wheel.slip=0
	wheel.state="REST"
	wheel.since_input=wheel.IDLE_SECONDS
	wheel.regrip_required=false
	wheel.motion.bridge_time=-1
	wheel.motion.settling=false
	wheel.motion.last_feed=0
	wheel.motion.contact_slip=0
	wheel.motion.feed_rate=0
