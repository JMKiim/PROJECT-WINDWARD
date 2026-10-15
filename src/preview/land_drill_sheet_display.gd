extends "res://src/preview/land_drill/support/held_sheet_display.gd"
const FLOOR_VIEW := preload("res://src/boat/rope_view.gd")
const END_VIEW := preload("res://src/boat/rope_tube_view.gd")
const FLOOR := preload("res://src/preview/land_drill_cockpit_sheet.gd")
var end_tube: Node3D
var pile: Node3D
var model := FLOOR.new()
func setup(lab: Node3D) -> void:
	message="육상 연습 · 콕핏 여유 줄 표현"
	model.setup(lab.get_node("Hull"))
	model.actor=lab.actor
	tube=FLOOR_VIEW.new()
	tube.name="CockpitSheetDisplay"
	lab.add_child(tube)
	pile=FLOOR_VIEW.new()
	pile.name="StoredCockpitSheet"
	lab.add_child(pile)
	pile.show_path(model.ground)
	pile.segments.multimesh.visible_instance_count=0
	pile.joints.multimesh.visible_instance_count=0
	end_tube=END_VIEW.new()
	end_tube.name="FreeSheetStopper"
	lab.add_child(end_tube)
func activate(_lab: Node3D) -> bool: return active
func show_held(lab: Node3D) -> void:
	lab.complete_sheet.hide()
	for lines in [lab.sheet_channel_lines,lab.study_lines,lab.block_lead_lines]:
		for line: MeshInstance3D in lines: line.hide()
	lab.sheet.hide()
	var result := model.build(lab.complete_sheet.ledger.cockpit_metres)
	if not result.valid: return
	tube.show_path(result.dynamic_path)
	pile.segments.multimesh.visible_instance_count=maxi(0,result.pile_points-1)
	pile.joints.multimesh.visible_instance_count=result.pile_points
	end_tube.show_path(result.end_path)
	lab.displayed_sheet_route=result.path
func set_full_rope(_lab: Node3D,_value: bool) -> void: held_only=true
