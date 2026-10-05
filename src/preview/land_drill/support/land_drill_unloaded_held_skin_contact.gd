extends "res://src/preview/land_drill/support/land_drill_cached_bvh_skin_candidate.gd"
## Actual skin of the released mainsheet hand only. Loaded grip knots are
## separately pinned by the route owner, not projected as free contacts.
func _setup_skin() -> void:
	super._setup_skin()
	var side: String=mesh_actor.role_bone("LeftHand").trim_suffix("Hand")
	var chosen := {}
	var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	for vertex in selected:
		var total := 0.0
		for slot in 4:
			var at: int=vertex*4+slot
			var name := String(skin_body.skin.get_bind_name(bones[at]))
			if name==side+"Hand" or name.begins_with(side+"Thumb") or name.begins_with(side+"Index") or name.begins_with(side+"Middle") or name.begins_with(side+"Ring") or name.begins_with(side+"Little"): total+=weights[at]
		if total>.6: chosen[vertex]=true
	var released := []
	var used := {}
	for face in faces:
		if chosen.has(face[0]) and chosen.has(face[1]) and chosen.has(face[2]):
			released.append(face)
			for vertex in face: used[vertex]=true
	faces=released
	selected=PackedInt32Array(used.keys())
	assert(not faces.is_empty() and not selected.is_empty())
