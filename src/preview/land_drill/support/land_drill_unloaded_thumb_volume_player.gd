extends "res://src/preview/land_drill/support/land_drill_unloaded_held_contact_player.gd"
## Surface witnesses alone can alternate between the opposite faces of an
## already penetrated thumb. Reuse the existing two finite anatomical thumb
## supports ONLY on the fully released hand; no whole-hand shell/new radii.
func _project_unloaded_span(span: PackedVector3Array) -> void:
	for cap in [["Metacarpal","Proximal",.030],["Proximal","Distal",.014]]:
		var first: Vector3=actor.bone_pose_boat(actor.role_bone("LeftThumb"+cap[0])).origin
		var last: Vector3=actor.bone_pose_boat(actor.role_bone("LeftThumb"+cap[1])).origin
		for index in span.size()-1: unloaded_skin._project_link(span,index,first,last,cap[2]+.004)
	super._project_unloaded_span(span)
static func install_thumb_volume(actor_value: Node3D) -> void:
	var old: Node=actor_value.sheet_control.regrip
	var bank: AnimationLibrary=old.authored_bank
	var candidate: Node=load("res://src/preview/land_drill/support/land_drill_unloaded_thumb_volume_player.gd").new()
	actor_value.sheet_control.add_child(candidate)
	candidate.setup(actor_value)
	candidate.prepare()
	candidate.authored_bank=bank
	actor_value.sheet_control.regrip=candidate
	old.queue_free()
	actor_value.sheet_study.manual_cache.clear()
	actor_value.sheet_study.manual_revision+=1
	actor_value.set_amount(actor_value.amount)
