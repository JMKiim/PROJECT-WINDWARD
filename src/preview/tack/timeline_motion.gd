extends "res://src/preview/tack/motion.gd"
const TIMELINE := preload("res://src/preview/tack/timeline.gd")
func sample(t: float) -> Dictionary:
	var phase: Dictionary=TIMELINE.state(t)
	incoming_open_override=phase.left_open
	outgoing_open_override=phase.right_open
	var result: Dictionary=super.sample(phase.u)
	result.geometry_u=phase.u
	result.handoff_stage=phase.stage
	result.elapsed_phase=t
	if phase.stage=="GRIP":
		result.ownership.tool_hands=["Right"]
		result.ownership.primary_tool="Right"
	elif phase.released:
		result.ownership.tool_hands=["Left"]
		result.ownership.primary_tool="Left"
	return result
