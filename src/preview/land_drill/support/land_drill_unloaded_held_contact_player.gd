extends "res://src/preview/land_drill/support/land_drill_preserved_hand_frame_candidate.gd"
## Tests-only finite skin reactions on an UNLOADED hand. Keep the authored
## actor pose and every protected load-bearing route knot exactly. This is
## a geometry candidate and still needs new envelope/feed/time regressions.
var unloaded_skin := preload("res://src/preview/land_drill/support/land_drill_unloaded_held_skin_contact.gd").new()
var released_route_key := []
var released_route_cache := PackedVector3Array()
var released_route_diagnostic := {}
func _project_unloaded_span(span: PackedVector3Array) -> void: unloaded_skin._project_skin(span)
func held_points() -> PackedVector3Array:
	var path := super.held_points()
	if time<1.0 or time>=1.75: return path
	var key := [actor.sheet_study.manual_revision,time,clip_time,actor.amount,actor.seat_side,actor.hike]
	if key==released_route_key and not released_route_cache.is_empty(): return released_route_cache.duplicate()
	unloaded_skin.mesh_actor=actor
	unloaded_skin._prepare_contact_frame([])
	var before := path.duplicate()
	var largest := 0.0
	for iteration in 12:
		var prior := path.duplicate()
		for span_index in route_knots.size()-1:
			var first: int=route_knots[span_index]
			var last: int=route_knots[span_index+1]
			if last-first<2: continue
			var span := path.slice(first,last+1)
			_project_unloaded_span(span)
			for index in range(1,span.size()-1): path[first+index]=span[index]
		var change := 0.0
		for index in path.size(): change=maxf(change,path[index].distance_squared_to(prior[index]))
		if change<1e-10: break
	for index in path.size(): largest=maxf(largest,path[index].distance_to(before[index]))
	for at in route_knots: assert(path[at]==before[at])
	released_route_diagnostic={"maximum_displacement":largest,"protected_knots":route_knots.duplicate(),"unloaded_faces":unloaded_skin.faces.size(),"time":time,"clock":clip_time}
	released_route_key=key
	released_route_cache=path.duplicate()
	return path
static func install_unloaded(actor_value: Node3D) -> void:
	var old: Node=actor_value.sheet_control.regrip
	var bank: AnimationLibrary=old.authored_bank
	var candidate: Node=load("res://src/preview/land_drill/support/land_drill_unloaded_held_contact_player.gd").new()
	actor_value.sheet_control.add_child(candidate)
	candidate.setup(actor_value)
	candidate.prepare()
	candidate.authored_bank=bank
	actor_value.sheet_control.regrip=candidate
	old.queue_free()
	actor_value.sheet_study.manual_cache.clear()
	actor_value.sheet_study.manual_revision+=1
	actor_value.set_amount(actor_value.amount)
