extends RefCounted

## Four-neighbour interpolation of fixed authored bone tracks. No pose search.
const BANK := preload("res://src/boat/animation/hiking_sheet_bank.gd")
const CONTROL := preload("res://src/boat/animation/sheet_control_source.gd")
const REGRIP := preload("res://src/boat/animation/sheet_regrip_source.gd")
var actor: Node3D
var clips := {&"work":[],&"left_arm":[],&"right_arm":[]}
var tracks := {}
var layer_bones := {}
var ready := false
var last_level := 0

func setup(value: Node3D,highest_level := BANK.LEVELS-1) -> bool:
	actor = value
	if ready: return highest_level==last_level
	if highest_level<1 or highest_level>=BANK.LEVELS: return false
	for level in range(0,highest_level+1):
		if not ResourceLoader.exists(BANK.path(level)): return false
	var references := {}
	for key: StringName in clips:
		clips[key].clear()
		references[key] = load(CONTROL.path(0) if key==&"work" else REGRIP.path(0,key)) as Animation
	for level in range(0,highest_level+1):
		var library := load(BANK.path(level)) as AnimationLibrary
		if library==null or not is_equal_approx(float(library.get_meta("hike",-1)),level/float(BANK.LEVELS-1)): return false
		for key: StringName in clips:
			var row := []
			for index in (CONTROL.STEERING_SAMPLES if key==&"work" else REGRIP.STEERING_SAMPLES):
				var name := "%s_%d" % [key,index]
				if not library.has_animation(name): return false
				row.append(library.get_animation(name))
			clips[key].append(row)
	for key: StringName in clips:
		var reference: Animation = references[key]
		var track_bones := PackedInt32Array()
		var bones := PackedInt32Array()
		for track in reference.get_track_count():
			var path := reference.track_get_path(track)
			if path.get_subname_count()!=1: return false
			var bone: int = actor.skeleton.find_bone(path.get_subname(0))
			if bone<0: return false
			track_bones.append(bone)
			if bone not in bones: bones.append(bone)
		for row: Array in clips[key]:
			for clip: Animation in row:
				if clip==null or clip.get_track_count()!=reference.get_track_count(): return false
				for track in clip.get_track_count():
					if clip.track_get_path(track)!=reference.track_get_path(track) or clip.track_get_type(track)!=reference.track_get_type(track): return false
		tracks[key] = track_bones
		layer_bones[key] = bones
	last_level = highest_level
	ready = true
	return true

func sample(work: float,bridge: float,weight: float) -> bool:
	if not ready or actor.hike>last_level/float(BANK.LEVELS-1)+.000001: return false
	var keys := [&"work"] if bridge<0 else [&"left_arm",&"right_arm"]
	var bones := PackedInt32Array()
	for key: StringName in keys:
		for bone: int in layer_bones[key]:
			if bone not in bones: bones.append(bone)
	var previous: Dictionary = actor.pose_mirror.capture(bones,actor.seat_side)
	for key: StringName in keys: _sample_layer(key,work if bridge<0 else bridge)
	actor.pose_mirror.apply_sample(bones,previous,actor.seat_side,weight)
	return true

func _sample_layer(key: StringName,time: float) -> void:
	var h: float = clampf(actor.hike,0,1)*(BANK.LEVELS-1)
	var lo_h := mini(int(h),last_level-1)
	var hs := h-lo_h
	var count: int = clips[key][0].size()
	var steering: float = (clampf(actor.amount,-1,1)+1)*.5*(count-1)
	var lo_s := mini(int(steering),count-2)
	var ss := steering-lo_s
	var a: Animation = clips[key][lo_h][lo_s]
	var b: Animation = clips[key][lo_h][lo_s+1]
	var c: Animation = clips[key][lo_h+1][lo_s]
	var d: Animation = clips[key][lo_h+1][lo_s+1]
	for track in a.get_track_count():
		var bone: int = tracks[key][track]
		if a.track_get_type(track)==Animation.TYPE_POSITION_3D:
			var lower := a.position_track_interpolate(track,time).lerp(b.position_track_interpolate(track,time),ss)
			var upper := c.position_track_interpolate(track,time).lerp(d.position_track_interpolate(track,time),ss)
			actor.skeleton.set_bone_pose_position(bone,lower.lerp(upper,hs))
		elif a.track_get_type(track)==Animation.TYPE_ROTATION_3D:
			var lower := a.rotation_track_interpolate(track,time).slerp(b.rotation_track_interpolate(track,time),ss)
			var upper := c.rotation_track_interpolate(track,time).slerp(d.rotation_track_interpolate(track,time),ss)
			actor.skeleton.set_bone_pose_rotation(bone,lower.slerp(upper,hs))
