extends "res://src/preview/land_drill_runtime_sheet.gd"
const VISUAL_MOTION := preload("res://src/preview/land_drill_visual_motion.gd")
func setup(value: Node3D) -> bool:
	if not super.setup(value): return false
	var motion := VISUAL_MOTION.new()
	if not motion.configure_visual(): return false
	lab.session.wheel_pull.motion=motion
	lab.actor.sheet_control.motion=motion
	lab.actor.set_amount(lab.actor.amount)
	return true
