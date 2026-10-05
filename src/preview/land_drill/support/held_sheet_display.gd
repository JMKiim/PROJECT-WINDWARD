extends RefCounted
## Display only the measured held strand; complete free rope is not approved.
const VIEW := preload("res://src/boat/rope_tube_view.gd")
var active := true
var held_only := true
var tube: Node3D
var message := "육상 연습 · 전체 자유 줄 접촉 검증 중"
func activate(_lab: Node3D) -> bool: return active
func show_held(lab: Node3D) -> void:
	lab.complete_sheet.hide()
	for lines in [lab.sheet_channel_lines,lab.study_lines,lab.block_lead_lines]:
		for line: MeshInstance3D in lines: line.hide()
	lab.sheet.hide()
	var path: PackedVector3Array=lab.actor.sheet_control.regrip.held_points()
	tube.show()
	tube.show_path(path)
	lab.displayed_sheet_route=path
func set_full_rope(_lab: Node3D,_value: bool) -> void:
	# An unvalidated full path must not be enabled by a legacy UI callback.
	held_only=true
	if tube!=null: tube.show()
