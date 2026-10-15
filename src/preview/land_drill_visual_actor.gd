extends "res://src/preview/land_drill_runtime_actor.gd"
const VISUAL_CONTROL := preload("res://src/preview/land_drill_visual_control.gd")
const TILLER_CONTACT := preload("res://src/preview/land_drill_tiller_contact.gd")
const REST_GUIDE := preload("res://src/preview/land_drill_tiller_guide.gd")
var transition_witness := {}
var transition_history := {}
var rest_guide: RefCounted=REST_GUIDE.new()
var guard_reserve := 0.0
var composing_transition := false
var pose_defaults: Array[Transform3D]=[]
func _ready() -> void:
	super._ready()
	for bone in skeleton.get_bone_count(): pose_defaults.append(skeleton.get_bone_pose(bone))
func _new_sheet_control() -> Node: return VISUAL_CONTROL.new()

func _sample_final_pose(value: float) -> void:
	if not is_finite(value) or not wide_bank_ready: return
	amount=clampf(value,-1,1)
	if steering_phase=="HOLD": steering_target=amount
	# The base bank owns rotation/position tracks, but no scale tracks.
	# Restore untracked components before composing: never accumulate IK,
	# finger release or the authored trunk turn between display frames.
	for bone in pose_defaults.size():
		var pose: Transform3D=pose_defaults[bone]
		skeleton.set_bone_pose_position(bone,pose.origin)
		skeleton.set_bone_pose_rotation(bone,pose.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone,pose.basis.get_scale())
	_sample_steering_pose()
	# Body placement and gaze precede the sole final arm/contact writer.
	if seat_contact!=null:
		look_pose.shoulder_follow_weight=0
		seat_contact.apply()
	if sheet_control!=null and sheet_control.weight>0 and seat_side==-1 and hike<.16:
		var chest: int=skeleton.find_bone("UpperChest")
		var transform: Transform3D=skeleton.get_bone_global_pose(chest)
		var to_boat: Basis=global_basis.inverse()*skeleton.global_basis
		var turn := deg_to_rad(30)*lerpf(1,-1,smoothstep(0,1,amount))
		transform.basis=to_boat.inverse()*Basis(Vector3.UP,turn)*to_boat*transform.basis
		skeleton.set_bone_global_pose(chest,transform)
		skeleton.force_update_bone_child_transform(chest)
	if look_enabled: look_pose.apply(skeleton,tiller_hand(),1.0)
	if sheet_control!=null: sheet_control.sample()
	_settle_idle_sheet_hand()
	if neck_cap!=null and neck_cap.visible and not composing_transition: neck_cap.update_pose()

func _settle_idle_sheet_hand() -> void:
	if sheet_control==null or sheet_control.weight>0 or hike<.6: return
	var side: String=sheet_hand()
	var player: Node=sheet_control.regrip
	var bones := []
	var base := []
	for suffix in ["UpperArm","LowerArm","Hand"]:
		var bone: int=skeleton.find_bone(side+suffix)
		bones.append(bone)
		base.append(skeleton.get_bone_pose(bone))
	var old: Basis=player.reference_frames[side]
	player.reference_frames[side]=bone_pose_boat(side+"Hand").basis.orthonormalized()
	player._solve_sheet(side,palm_boat(side)+Vector3(0,0,-.075))
	player.reference_frames[side]=old
	var blend := smoothstep(.6,.9,hike)
	for index in bones.size():
		var before: Transform3D=base[index]
		var after: Transform3D=skeleton.get_bone_pose(bones[index])
		skeleton.set_bone_pose_position(bones[index],before.origin.lerp(after.origin,blend))
		skeleton.set_bone_pose_rotation(bones[index],before.basis.get_rotation_quaternion().slerp(after.basis.get_rotation_quaternion(),blend))
		skeleton.set_bone_pose_scale(bones[index],before.basis.get_scale().lerp(after.basis.get_scale(),blend))

func set_amount(value: float) -> void:
	if not is_finite(value): return
	if not wide_bank_ready or pose_defaults.is_empty():
		_sample_final_pose(value)
		return
	if sheet_control==null or sheet_control.weight<=0 or sheet_control.weight>=1 or hike>=.16 or seat_side!=-1:
		_sample_final_pose(value)
		if sheet_control!=null and sheet_control.weight<=0: transition_witness=TILLER_CONTACT.settle(self)
		_release_tiller()
		return
	var weight: float=sheet_control.weight
	composing_transition=true
	sheet_control.weight=0
	_sample_final_pose(value)
	var base := []
	for bone in skeleton.get_bone_count(): base.append(skeleton.get_bone_pose(bone))
	var head := skeleton.find_bone("Head")
	var base_eye: Basis=(skeleton.get_bone_global_pose(head).basis*look_pose.eye_basis).orthonormalized()
	sheet_control.weight=1
	_sample_final_pose(value)
	var full_eye: Basis=(skeleton.get_bone_global_pose(head).basis*look_pose.eye_basis).orthonormalized()
	var blend := smoothstep(0,1,weight)
	for bone in skeleton.get_bone_count():
		var pose: Transform3D=base[bone]
		var final: Transform3D=skeleton.get_bone_pose(bone)
		skeleton.set_bone_pose_position(bone,pose.origin.lerp(final.origin,blend))
		skeleton.set_bone_pose_rotation(bone,pose.basis.get_rotation_quaternion().slerp(final.basis.get_rotation_quaternion(),blend))
		skeleton.set_bone_pose_scale(bone,pose.basis.get_scale().lerp(final.basis.get_scale(),blend))
	look_pose.eye_basis=skeleton.get_bone_global_pose(head).basis.inverse()*base_eye.slerp(full_eye,blend)
	sheet_control.weight=weight
	sheet_control.set_display_weight(weight)
	composing_transition=false
	transition_witness=TILLER_CONTACT.settle(self)
	_release_tiller()
	if neck_cap!=null and neck_cap.visible: neck_cap.update_pose()

func _release_tiller() -> void:
	var release := maxf(grip_loosen,steering_release)
	if release<=0: return
	for digit in ["Index","Middle","Ring","Little"]:
		for segment in ["Proximal","Intermediate","Distal"]:
			var bone := skeleton.find_bone(tiller_hand()+digit+segment)
			var held := skeleton.get_bone_pose_rotation(bone)
			var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bone,held.slerp(rest,_grip_release_for_segment(segment)*release))
