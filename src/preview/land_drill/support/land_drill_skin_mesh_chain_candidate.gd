extends "res://src/preview/land_drill/support/land_drill_material_chain_v2.gd"

## Diagnostic substitution of actual animated skin for hand capsule proxies.
## Body, legs, finite shaft, rig, self/floor contacts and independent gates
## remain unchanged. No radius/tolerance increase or final output truncation.
const TRIANGLE := preload("res://src/boat/triangle_contact_geometry.gd")
var mesh_actor: Node3D
var skin_body: MeshInstance3D
var arrays: Array
var bind_ids := PackedInt32Array()
var selected := PackedInt32Array()
var faces := []
var skin_points := PackedVector3Array()
var skin_normals := PackedVector3Array()
var skin_bounds := []
var hand_bounds: AABB
var excluded := PackedInt32Array()

func contact_prefix(held: PackedVector3Array,actor: Node3D) -> PackedVector3Array:
	mesh_actor=actor
	return super.contact_prefix(held,actor)

func _prepare_contact_frame(_supports: Array) -> void:
	if skin_body==null: _setup_skin()
	var maps: Array[Transform3D]=[]
	for bind in bind_ids.size(): maps.append(mesh_actor.skeleton.global_transform*mesh_actor.skeleton.get_bone_global_pose(bind_ids[bind])*skin_body.skin.get_bind_pose(bind))
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	skin_points.resize(vertices.size())
	skin_normals.resize(vertices.size())
	for vertex in selected:
		var point := Vector3.ZERO
		var normal := Vector3.ZERO
		for slot in 4:
			var at: int=vertex*4+slot
			point+=(maps[bones[at]]*vertices[vertex])*weights[at]
			normal+=(maps[bones[at]].basis*normals[vertex])*weights[at]
		skin_points[vertex]=point
		skin_normals[vertex]=normal.normalized()
	hand_bounds=AABB(skin_points[selected[0]],Vector3.ZERO)
	for vertex in selected: hand_bounds=hand_bounds.expand(skin_points[vertex])
	hand_bounds=hand_bounds.grow(.008)
	skin_bounds.clear()
	for face in faces: skin_bounds.append(AABB(skin_points[face[0]],Vector3.ZERO).expand(skin_points[face[1]]).expand(skin_points[face[2]]).grow(.0045))

func _setup_skin() -> void:
	skin_body=mesh_actor.skeleton.get_node("SuperHero_Male")
	arrays=skin_body.mesh.surface_get_arrays(0)
	for bind in skin_body.skin.get_bind_count(): bind_ids.append(mesh_actor.skeleton.find_bone(skin_body.skin.get_bind_name(bind)))
	var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var chosen := {}
	for vertex in arrays[Mesh.ARRAY_VERTEX].size():
		var total := 0.0
		for slot in 4:
			var at: int=vertex*4+slot
			var name := String(skin_body.skin.get_bind_name(bones[at]))
			for side in ["Left","Right"]:
				if name==side+"Hand" or name.begins_with(side+"Thumb") or name.begins_with(side+"Index") or name.begins_with(side+"Middle") or name.begins_with(side+"Ring") or name.begins_with(side+"Little"): total+=weights[at]
		if total>.6: selected.append(vertex); chosen[vertex]=true
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for offset in range(0,indices.size(),3):
		if chosen.has(indices[offset]) and chosen.has(indices[offset+1]) and chosen.has(indices[offset+2]): faces.append([indices[offset],indices[offset+1],indices[offset+2]])
	var profile := preload("res://src/preview/land_drill/support/rope_hand_contact_profile.gd").new()
	profile.prepare(mesh_actor)
	for side in ["Left","Right"]: excluded.append_array(profile.hand_indices(mesh_actor,side))
	assert(not faces.is_empty() and not selected.is_empty())

func _contacts(curve: PackedVector3Array,fixed: PackedVector3Array,fixed_groups: Array,remaining: PackedFloat32Array,supports: Array,_support_bounds: Array,hull: MeshInstance3D) -> void:
	var finite := []
	var bounds := []
	for index in supports.size():
		if index in excluded: continue
		var support: Array=supports[index]
		finite.append(support)
		bounds.append(_bounds(support[0],support[1]).grow(support[2]+.004))
	super._contacts(curve,fixed,fixed_groups,remaining,finite,bounds,hull)
	_project_skin(curve)

func _project_skin(curve: PackedVector3Array) -> void:
	for index in curve.size()-1:
		var start := curve[index]
		var end := curve[index+1]
		var box := _bounds(start,end).grow(.0045)
		if not box.intersects(hand_bounds): continue
		var best := {"distance":.0045}
		for face_index in faces.size():
			if not box.intersects(skin_bounds[face_index]): continue
			var face: Array=faces[face_index]
			var pair := TRIANGLE.segment_triangle(start,end,skin_points[face[0]],skin_points[face[1]],skin_points[face[2]])
			var distance := pair[0].distance_to(pair[1])
			if distance>=best.distance: continue
			var normal: Vector3=(skin_points[face[1]]-skin_points[face[0]]).cross(skin_points[face[2]]-skin_points[face[0]]).normalized()
			if normal.dot(skin_normals[face[0]]+skin_normals[face[1]]+skin_normals[face[2]])<0: normal=-normal
			var delta := pair[0]-pair[1]
			var signed_distance := delta.dot(normal)
			if signed_distance>0 and distance>.000001: normal=delta/distance
			best={"distance":distance,"signed_distance":signed_distance,"normal":normal,"point":pair[0]}
		if not best.has("point"): continue
		var fraction: float=clampf((best.point-start).dot(end-start)/maxf(.0000001,start.distance_squared_to(end)),0,1)
		var first := 0.0 if index==0 else 1.0-fraction
		var last := 0.0 if index+1==curve.size()-1 else fraction
		var divisor := first*first+last*last
		if divisor<.000001: continue
		var depth: float=.0045-(best.distance if best.signed_distance>=0 else -best.distance)
		var correction: Vector3=(best.normal*depth/divisor).limit_length(.010/maxf(first,last))
		curve[index]+=correction*first
		curve[index+1]+=correction*last
