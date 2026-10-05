extends "res://src/preview/land_drill/support/land_drill_unloaded_anatomical_volume_player.gd"
## Keep the proven contact projections unchanged. A manual input revision
## is not a pose revision: animation, fingers and look can move without it.
## Use exact current inputs, never quantized poses or synthetic revisions.
var current_pose_cache_key := []
var pose_cache_invalidations := 0
var pose_cache_hits := 0

func held_points() -> PackedVector3Array:
	var key := [actor.get_instance_id(),actor.sheet_study.manual_revision,time,clip_section,clip_time,actor.amount,actor.seat_side,actor.hike,actor.sheet_control.weight,actor.sheet_control.slip,actor.extension_span,actor.global_transform,actor.skeleton.global_transform,actor.sheet_study.block_anchor]
	# Include leaves as well as skin binds. The thirteen anatomical supports
	# use leaf endpoints; finger-only changes must invalidate a stationary hand.
	for bone in actor.skeleton.get_bone_count():
		key.append(actor.skeleton.get_bone_global_pose(bone))
	if key!=current_pose_cache_key:
		volume_revision=-1
		released_route_key.clear()
		held_cache_key.clear()
		current_pose_cache_key=key
		pose_cache_invalidations+=1
	else:
		pose_cache_hits+=1
	return super.held_points()

static func install_pose_cache(actor_value: Node3D) -> void:
	var old: Node=actor_value.sheet_control.regrip
	var bank: AnimationLibrary=old.authored_bank
	var candidate: Node=load("res://src/preview/land_drill/support/land_drill_unloaded_pose_cache_player.gd").new()
	actor_value.sheet_control.add_child(candidate)
	candidate.setup(actor_value)
	candidate.prepare()
	candidate.authored_bank=bank
	actor_value.sheet_control.regrip=candidate
	old.queue_free()
	actor_value.sheet_study.manual_cache.clear()
	actor_value.sheet_study.manual_revision+=1
	actor_value.set_amount(actor_value.amount)
