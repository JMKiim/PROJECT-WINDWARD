extends RefCounted

## Exact interpolation between owned authored tracks. This replays clips;
## it does not construct joint targets, search poses or change limb lengths.
var skeleton: Skeleton3D
var pose_root: Node3D
var track_cache := {}

func configure(value: Skeleton3D, root_pose: Node3D=null) -> void:
	skeleton=value
	pose_root=root_pose
	track_cache.clear()

func _tracks(clip: Animation) -> Array:
	var identity := clip.get_instance_id()
	if track_cache.has(identity): return track_cache[identity]
	var result := []
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var kind := clip.track_get_type(track)
		if kind==Animation.TYPE_VALUE:
			assert(pose_root!=null and path in [^"Pose:position",^"Pose:rotation"])
			result.append({"track":track,"kind":kind,"property":path.get_subname(0)})
		else:
			assert(kind in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D])
			var bone := skeleton.find_bone(path.get_subname(0))
			assert(bone>=0)
			result.append({"track":track,"kind":kind,"bone":bone})
	track_cache[identity]=result
	return result

func sample_pair(low: Animation, high: Animation, time: float, blend: float) -> void:
	assert(low.get_track_count()==high.get_track_count())
	var fraction := clampf(blend,0,1)
	for owned in _tracks(low):
		var track: int=owned.track
		assert(low.track_get_path(track)==high.track_get_path(track) and low.track_get_type(track)==high.track_get_type(track))
		match owned.kind:
			Animation.TYPE_VALUE:
				var a: Vector3=low.value_track_interpolate(track,time)
				var b: Vector3=high.value_track_interpolate(track,time)
				pose_root.set(owned.property,a.lerp(b,fraction))
			Animation.TYPE_POSITION_3D:
				var a := low.position_track_interpolate(track,time)
				var b := high.position_track_interpolate(track,time)
				skeleton.set_bone_pose_position(owned.bone,a.lerp(b,fraction))
			Animation.TYPE_ROTATION_3D:
				var a := low.rotation_track_interpolate(track,time).normalized()
				var b := high.rotation_track_interpolate(track,time).normalized()
				skeleton.set_bone_pose_rotation(owned.bone,a.slerp(b,fraction).normalized())
