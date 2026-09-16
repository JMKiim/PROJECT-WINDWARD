extends MeshInstance3D

## Close each head-mask boundary on the already deformed body. Interpolating
## bind weights first is not equivalent to the renderer's deformed edge.
var source_body: MeshInstance3D
var source_skeleton: Skeleton3D
var source_skin: Skin
var vertices := PackedVector3Array()
var weights := PackedFloat32Array()
var binds := PackedInt32Array()
var influences := 4
var groups := []
var bind_bones := PackedInt32Array()

func setup(body: MeshInstance3D, head_bind: int, threshold := .05) -> bool:
	source_body = body
	source_skin = body.skin
	source_skeleton = body.get_node(body.skeleton) as Skeleton3D
	var data := body.mesh.surface_get_arrays(0)
	vertices = data[Mesh.ARRAY_VERTEX]
	weights = data[Mesh.ARRAY_WEIGHTS]
	binds = data[Mesh.ARRAY_BONES]
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = data[Mesh.ARRAY_TEX_UV]
	influences = binds.size()/vertices.size()
	for index in source_skin.get_bind_count():
		bind_bones.append(source_skeleton.find_bone(source_skin.get_bind_name(index)))
	var segments := []
	for triangle in indices.size()/3:
		var corners := []
		for edge in 3:
			var a := indices[triangle*3+edge]
			var b := indices[triangle*3+(edge+1)%3]
			var wa := _head_weight(a,head_bind)
			var wb := _head_weight(b,head_bind)
			if (wa<threshold)==(wb<threshold): continue
			var u := (threshold-wa)/(wb-wa)
			var point := vertices[a].lerp(vertices[b],u)
			corners.append({"a":a,"b":b,"u":u,"uv":uv[a].lerp(uv[b],u),"key":point.snapped(Vector3.ONE*.00001)})
		if corners.size()==2: segments.append(corners)
	if segments.is_empty(): return false
	# UV seams may duplicate vertices. Geometric edge keys join the same
	# boundary, while disconnected contours receive independent closures.
	while not segments.is_empty():
		var group := [segments.pop_back()]
		var keys := {group[0][0].key:true,group[0][1].key:true}
		var changed := true
		while changed:
			changed = false
			for index in range(segments.size()-1,-1,-1):
				var segment: Array = segments[index]
				if not keys.has(segment[0].key) and not keys.has(segment[1].key): continue
				group.append(segment)
				keys[segment[0].key] = true
				keys[segment[1].key] = true
				segments.remove_at(index)
				changed = true
		groups.append(group)
	transform = body.transform
	var material: StandardMaterial3D = body.mesh.surface_get_material(0).duplicate()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = ArrayMesh.new()
	update_pose()
	return true

func update_pose() -> void:
	var transforms := {}
	var skinned := {}
	var conversion := source_body.global_transform.affine_inverse()*source_skeleton.global_transform
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var coords := PackedVector2Array()
	for group: Array in groups:
		var center := Vector3.ZERO
		var center_uv := Vector2.ZERO
		var edges := []
		for segment: Array in group:
			var edge := []
			for corner: Dictionary in segment:
				for vertex: int in [corner.a,corner.b]:
					if skinned.has(vertex): continue
					var position := Vector3.ZERO
					for influence in influences:
						var slot := vertex*influences+influence
						if weights[slot]<=0.0: continue
						var bind := binds[slot]
						if not transforms.has(bind):
							transforms[bind] = conversion*source_skeleton.get_bone_global_pose(bind_bones[bind])*source_skin.get_bind_pose(bind)
						position += (transforms[bind]*vertices[vertex])*weights[slot]
					skinned[vertex] = position
				var position: Vector3 = skinned[corner.a].lerp(skinned[corner.b],corner.u)
				center += position/(group.size()*2.0)
				center_uv += corner.uv/(group.size()*2.0)
				edge.append({"point":position,"uv":corner.uv})
			edges.append(edge)
		for edge: Array in edges:
			var normal: Vector3 = (edge[0].point-center).cross(edge[1].point-center).normalized()
			for corner: Dictionary in [{"point":center,"uv":center_uv},edge[0],edge[1]]:
				points.append(corner.point)
				normals.append(normal)
				coords.append(corner.uv)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = coords
	var surface := mesh as ArrayMesh
	surface.clear_surfaces()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

func _head_weight(vertex: int, head: int) -> float:
	var result := 0.0
	for influence in influences:
		var index := vertex*influences+influence
		if binds[index]==head: result += weights[index]
	return result
