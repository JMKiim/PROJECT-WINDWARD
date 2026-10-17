extends "res://src/preview/tack/tool_motion.gd"
const FREE := preload("res://src/preview/tack/free_hand.gd")
const HAND_FRAMES := "res://src/boat/animation/land_drill/tack_hand_frames.res"
const OPEN_HAND_PATCH := "res://src/boat/animation/land_drill/tack_hand_approach.res"
var common_goals := {}
var hand_frames: Resource
var use_authored_hand_frames := true
var open_hand_patch: Resource
var use_open_hand_patch := true
var incoming_open_override := NAN
var outgoing_open_override := NAN
var approach_authoring := false
func _tool_fingers(side: String,seat: int,u: float) -> void:
	super._tool_fingers(side,seat,u)
	var weight: float=incoming_open_override if side=="Left" else outgoing_open_override
	if approach_authoring and (side=="Left" and is_equal_approx(u,.5) or side=="Right" and is_equal_approx(u,.52)): weight=.85
	if is_finite(weight) and weight>0:
		FREE.fingers(self,side,seat,seat,0,weight,-1 if side=="Left" else 0)
func setup(value: Node3D) -> void:
	super.setup(value)
	if use_authored_hand_frames: hand_frames=load(HAND_FRAMES)
	if use_open_hand_patch and not OPEN_HAND_PATCH.is_empty(): open_hand_patch=load(OPEN_HAND_PATCH)
func resources_error() -> String:
	if field==null or not field.error().is_empty(): return "태킹 접촉 자료를 확인해 주세요."
	if hand_frames==null or not hand_frames.error().is_empty(): return "손 회전 자료를 확인해 주세요."
	if hand_frames.tool_field_sha256!=FileAccess.get_sha256(field.resource_path): return "몸·봉·손 회전 자료의 버전이 서로 다릅니다."
	if use_open_hand_patch and (open_hand_patch==null or not open_hand_patch.error().is_empty() or open_hand_patch.tool_field_sha256!=FileAccess.get_sha256(field.resource_path)): return "손 접근 자료의 버전을 확인해 주세요."
	return ""
func set_steering(value: float) -> void:
	super.set_steering(value)
	body.contact_offset_field=Vector3.ZERO
	body.sample(.5)
	common_goals.clear()
	var axis: Vector3=SHAFT.common_axis(actor)
	for side in ["Right","Left"]:
		var key: Dictionary=field.sample(steering,.5,side)
		var pole: Vector3=actor.bone_pose_boat(side+"UpperArm").origin+actor.bone_pose_boat("UpperChest").basis.orthonormalized()*key.elbow
		var plan: Dictionary=GRIP._fixed_frame(actor,side,axis,key.grip,key.frame,pole)
		if plan.valid:
			plan.guide=plan.elbow
			plan.shoulder=actor.bone_pose_boat(side+"UpperArm").origin
			plan.chest=actor.bone_pose_boat("UpperChest")
			plan.hips=actor.bone_pose_boat("Hips").origin
		common_goals[side]=plan
func sample(u: float) -> Dictionary:
	var result: Dictionary=super.sample(u)
	result.free=FREE.apply(self,u)
	result.ownership={
		"tool_hands":["Right"] if u<.50 else (["Right","Left"] if u<=.52 else ["Left"]),
		"primary_tool":"Right" if u<.52 else "Left",
		"sheet_hand":"Left" if u<.20 else ("Right" if u>=.92 else ""),
		"helper_hand":"Right" if u>=.16 and u<.92 else "",
		"old_sheet_weight":1-smoothstep(.20,.24,u),
		"helper_weight":smoothstep(.10,.16,u)*(1-smoothstep(.92,.96,u)),
		"new_sheet_weight":smoothstep(.86,.92,u),
	}
	return result
