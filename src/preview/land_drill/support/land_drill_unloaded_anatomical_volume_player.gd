extends "res://src/preview/land_drill/support/land_drill_unloaded_thumb_volume_player.gd"
## Reuse the existing thirteen narrow anatomical supports for the released
## port sheet hand, rather than a new convex shell or larger contact radius.
var volume_revision := -1
func _project_unloaded_span(span: PackedVector3Array) -> void:
	var revision: int=actor.sheet_study.manual_revision
	if revision!=volume_revision:
		unloaded_skin.surfaces._prepare_anatomy(actor)
		volume_revision=revision
	var first: int=unloaded_skin.surfaces.original_support_count-2
	for at in range(first,first+13):
		var cap: Array=unloaded_skin.surfaces.anatomy[at]
		for index in span.size()-1: unloaded_skin._project_link(span,index,cap[0],cap[1],cap[2]+.004)
	unloaded_skin._project_skin(span)
static func install_anatomical_volume(actor_value: Node3D) -> void:
	var old: Node=actor_value.sheet_control.regrip
	var bank: AnimationLibrary=old.authored_bank
	var candidate: Node=load("res://src/preview/land_drill/support/land_drill_unloaded_anatomical_volume_player.gd").new()
	actor_value.sheet_control.add_child(candidate)
	candidate.setup(actor_value)
	candidate.prepare()
	candidate.authored_bank=bank
	actor_value.sheet_control.regrip=candidate
	old.queue_free()
	actor_value.sheet_study.manual_cache.clear()
	actor_value.sheet_study.manual_revision+=1
	actor_value.set_amount(actor_value.amount)
