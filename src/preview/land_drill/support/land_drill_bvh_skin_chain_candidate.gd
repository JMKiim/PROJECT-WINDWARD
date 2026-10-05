extends "res://src/preview/land_drill/support/land_drill_grouped_skin_chain_candidate.gd"
## Exact spatial broad phase. Build a topology once, then refit its bounds
## to the actual animated triangles. Returned face indices are sorted back
## into the original order, including ties. Contact geometry is unchanged.
var contact_tree := []
var face_centres := PackedVector3Array()
var tree_queries := 0
var tree_candidates := 0

func _build_contact_index() -> void:
	if contact_tree.is_empty():
		face_centres.clear()
		var indices := []
		for index in faces.size():
			face_centres.append(skin_bounds[index].get_center())
			indices.append(index)
		_build_node(indices)
	_refit_node(0)

func _build_node(indices: Array) -> int:
	var node := contact_tree.size()
	contact_tree.append({"left":-1,"right":-1,"faces":PackedInt32Array(),"box":AABB()})
	if indices.size()<=8:
		contact_tree[node].faces=PackedInt32Array(indices)
		return node
	var box := AABB(face_centres[indices[0]],Vector3.ZERO)
	for index: int in indices: box=box.expand(face_centres[index])
	var axis := box.get_longest_axis_index()
	indices.sort_custom(func(a: int,b: int) -> bool:
		var first := face_centres[a][axis]
		var last := face_centres[b][axis]
		return a<b if first==last else first<last)
	var middle := indices.size()/2
	contact_tree[node].left=_build_node(indices.slice(0,middle))
	contact_tree[node].right=_build_node(indices.slice(middle))
	return node

func _refit_node(index: int) -> AABB:
	var node: Dictionary=contact_tree[index]
	var box: AABB
	if node.left<0:
		box=skin_bounds[node.faces[0]]
		for face: int in node.faces: box=box.merge(skin_bounds[face])
	else:
		box=_refit_node(node.left).merge(_refit_node(node.right))
	# Bounds only: conservative numerical padding cannot alter a narrow-
	# phase witness, radius, correction or accepted penetration criterion.
	node.box=box.grow(.000001)
	return node.box

func _candidate_faces(box: AABB) -> PackedInt32Array:
	var result := PackedInt32Array()
	var pending := PackedInt32Array([0])
	while not pending.is_empty():
		var node: Dictionary=contact_tree[pending[-1]]
		pending.resize(pending.size()-1)
		if not box.intersects(node.box): continue
		if node.left<0:
			for face: int in node.faces:
				if box.intersects(skin_bounds[face]): result.append(face)
		else:
			pending.append(node.left)
			pending.append(node.right)
	result.sort()
	tree_queries+=1
	tree_candidates+=result.size()
	return result
