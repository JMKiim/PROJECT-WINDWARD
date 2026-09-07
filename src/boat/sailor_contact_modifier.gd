extends SkeletonModifier3D

# Final contact pass for terminal bones. TwoBoneIK3D solves only the end-bone
# position, so hands and bare feet otherwise retain arbitrary imported rolls.
# This modifier is appended after both arm IK modifiers and gives the owning
# sailor one deterministic place to align those terminal bones to controls.

var sailor: Node


func _process_modification() -> void:
	_apply_contact_pose()


func _process_modification_with_delta(_delta: float) -> void:
	_apply_contact_pose()


func _apply_contact_pose() -> void:
	if is_instance_valid(sailor) and sailor.has_method("_apply_terminal_contact_pose"):
		sailor.call("_apply_terminal_contact_pose")
