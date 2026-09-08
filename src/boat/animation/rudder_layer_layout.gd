extends RefCounted

## Anatomical ownership stays disjoint even when the hands exchange tool roles.
## Body-relative contact means the four steering layers still share a coordinate;
## independent sheet actions need authored contact transitions, not arbitrary mixing.
const LAYERS := [&"base", &"body", &"left_arm", &"right_arm"]
const PORT := -1
const STARBOARD := 1
const DIRECTORY := "res://src/boat/animation/"

static func side_name(side: int) -> String:
	return "port" if side == PORT else "starboard"

static func path(side: int, layer: StringName, hike_level: int = 0) -> String:
	var suffix := "" if hike_level == 0 else "_hike%d" % hike_level
	return DIRECTORY + "rudder_" + side_name(side) + "_" + String(layer) + suffix + ".tres"

static func owner(skeleton: Skeleton3D, path: NodePath) -> StringName:
	if String(path).begins_with("Pose:"):
		return &"base"
	var name := String(path.get_subname(0))
	if name in ["Spine", "Chest", "UpperChest", "Neck", "Head"]:
		return &"body"
	var bone := skeleton.find_bone(name)
	while bone >= 0:
		var ancestor := skeleton.get_bone_name(bone)
		if ancestor == "LeftShoulder":
			return &"left_arm"
		if ancestor == "RightShoulder":
			return &"right_arm"
		bone = skeleton.get_bone_parent(bone)
	return &"base"

static func opposite(name: String) -> String:
	if name.begins_with("Left"):
		return "Right" + name.substr(4)
	if name.begins_with("Right"):
		return "Left" + name.substr(5)
	if name.ends_with("_l"):
		return name.left(-2) + "_r"
	if name.ends_with("_r"):
		return name.left(-2) + "_l"
	return name
