extends "res://src/preview/land_drill/support/wide_steering_relay.gd"

## Known-track replay only. Local arm interpolation must not rotate the
## original world hand frame between keys. No IK, pose search or time warp.
const ORIGINAL_PATH := "res://src/boat/animation/land_drill/base_pose_bank.res"
const ORIGINAL_SHA := "96b95e3e64d4da63e33deac35015032dc9891c60fa6e0eba0816f31a089dfb24"
var original_bank: AnimationLibrary
var reference_tracks := {}

func _reference_tracks(clip: Animation) -> Array:
	var identity := clip.get_instance_id()
	if reference_tracks.has(identity): return reference_tracks[identity]
	var result := []
	for track in clip.get_track_count():
		if clip.track_get_type(track)!=Animation.TYPE_ROTATION_3D: continue
		var name := String(clip.track_get_path(track).get_subname(0))
		if name in ["LeftUpperArm","LeftLowerArm","LeftHand"]:
			result.append([track,actor.skeleton.find_bone(name)])
	assert(result.size()==3)
	reference_tracks[identity]=result
	return result

func _sample(weight: float) -> void:
	if weight<=0: return
	prepare()
	if original_bank==null:
		assert(FileAccess.get_sha256(ORIGINAL_PATH)==ORIGINAL_SHA)
		original_bank=load(ORIGINAL_PATH)
	var previous: Dictionary=actor.pose_mirror.capture(bones,actor.seat_side)
	var coordinate: float=(actor.amount+1)*.5*(CONFIG.STEERING_SAMPLES-1)
	var low := mini(int(coordinate),CONFIG.STEERING_SAMPLES-2)
	var first := CONFIG.relay_name(clip_section,low)
	var second := CONFIG.relay_name(clip_section,low+1)
	var blend := clampf(coordinate-low,0,1)
	track_sampler.sample_pair(authored_bank.get_animation(first),authored_bank.get_animation(second),clip_time,blend)
	if authored_bank.resource_path!=ORIGINAL_PATH:
		var original_low: Animation=original_bank.get_animation(first)
		var original_high: Animation=original_bank.get_animation(second)
		var owned := _reference_tracks(original_low)
		var saved := []
		for item in owned:
			saved.append(actor.skeleton.get_bone_pose_rotation(item[1]))
			var a := original_low.rotation_track_interpolate(item[0],clip_time).normalized()
			var b := original_high.rotation_track_interpolate(item[0],clip_time).normalized()
			actor.skeleton.set_bone_pose_rotation(item[1],a.slerp(b,blend).normalized())
		var hand: int=actor.skeleton.find_bone("LeftHand")
		var expected: Basis=actor.skeleton.get_bone_global_pose(hand).basis
		for index in owned.size(): actor.skeleton.set_bone_pose_rotation(owned[index][1],saved[index])
		var parent: int=actor.skeleton.get_bone_parent(hand)
		var local_basis: Basis=actor.skeleton.get_bone_global_pose(parent).basis.inverse()*expected
		actor.skeleton.set_bone_pose_rotation(hand,local_basis.orthonormalized().get_rotation_quaternion())
	actor.pose_mirror.apply_sample(bones,previous,actor.seat_side,weight)

static func install(actor_value: Node3D) -> void:
	var old: Node=actor_value.sheet_control.regrip
	var bank: AnimationLibrary=old.authored_bank
	var candidate: Node=load("res://src/preview/land_drill/support/land_drill_preserved_hand_frame_candidate.gd").new()
	actor_value.sheet_control.add_child(candidate)
	candidate.setup(actor_value)
	candidate.prepare()
	candidate.authored_bank=bank
	actor_value.sheet_control.regrip=candidate
	old.queue_free()
	actor_value.sheet_study.manual_cache.clear()
	actor_value.sheet_study.manual_revision+=1
	actor_value.set_amount(actor_value.amount)
