extends "res://src/preview/land_drill/support/land_drill_skin_mesh_chain_candidate.gd"

## Exact broad phase only: contiguous leaves preserve the original face
## order, and every retained face uses the original triangle test/projection.
var skin_groups := []
var skin_clusters := []
func _prepare_contact_frame(supports: Array) -> void:
	super._prepare_contact_frame(supports)
	_build_contact_index()

func _build_contact_index() -> void:
	skin_groups.clear()
	skin_clusters.clear()
	for first in range(0,faces.size(),16):
		var last := mini(first+16,faces.size())
		var box: AABB=skin_bounds[first]
		for index in range(first+1,last): box=box.merge(skin_bounds[index])
		skin_groups.append({"first":first,"last":last,"box":box})
	for first in range(0,skin_groups.size(),8):
		var last := mini(first+8,skin_groups.size())
		var box: AABB=skin_groups[first].box
		for index in range(first+1,last): box=box.merge(skin_groups[index].box)
		skin_clusters.append({"first":first,"last":last,"box":box})

func _candidate_faces(box: AABB) -> PackedInt32Array:
	var result := PackedInt32Array()
	for cluster in skin_clusters:
		if not box.intersects(cluster.box): continue
		for group_index in range(cluster.first,cluster.last):
			var group: Dictionary=skin_groups[group_index]
			if not box.intersects(group.box): continue
			for index in range(group.first,group.last): result.append(index)
	return result

func _project_skin(curve: PackedVector3Array) -> void:
	for index in curve.size()-1:
		var start := curve[index]
		var end := curve[index+1]
		var box := _bounds(start,end).grow(.0045)
		if not box.intersects(hand_bounds): continue
		var best := {"distance":.0045}
		for face_index: int in _candidate_faces(box):
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
