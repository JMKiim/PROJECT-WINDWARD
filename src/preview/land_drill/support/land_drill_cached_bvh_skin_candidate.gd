extends "res://src/preview/land_drill/support/land_drill_bvh_skin_chain_candidate.gd"
## Cache only conservative candidate sets inside one current skin frame.
## Grid cells are broad-phase keys, not quantized geometry or witnesses.
var candidate_cache := {}
var cache_hits := 0
func _build_contact_index() -> void:
	candidate_cache.clear()
	super._build_contact_index()
func _candidate_faces(box: AABB) -> PackedInt32Array:
	var lower := Vector3.ZERO
	var upper := Vector3.ZERO
	for axis in 3:
		lower[axis]=floorf(box.position[axis]/.020)*.020-.000001
		upper[axis]=ceilf(box.end[axis]/.020)*.020+.000001
	var region := AABB(lower,upper-lower)
	var candidates: PackedInt32Array
	if candidate_cache.has(region):
		candidates=candidate_cache[region]
		cache_hits+=1
	else:
		candidates=super._candidate_faces(region)
		candidate_cache[region]=candidates
	var result := PackedInt32Array()
	for face in candidates:
		if box.intersects(skin_bounds[face]): result.append(face)
	return result
