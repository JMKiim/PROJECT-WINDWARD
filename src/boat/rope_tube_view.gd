extends Node3D

## A continuous swept surface for short, closely dressed rope ends.
var radius := .004
var color := Color("d8aa55")
var surface: MeshInstance3D
var previous := PackedVector3Array()

func _ready() -> void:
	surface = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .95
	surface.material_override = material
	add_child(surface)

func show_path(points: PackedVector3Array) -> void:
	if surface==null or points.size()<2 or points==previous: return
	previous = points.duplicate()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var u := Vector3.ZERO
	const SIDES := 16
	for index in points.size():
		var tangent := (points[mini(index+1,points.size()-1)]-points[maxi(0,index-1)]).normalized()
		u -= tangent*u.dot(tangent)
		if u.length_squared()<.000001: u = tangent.cross(Vector3.UP if absf(tangent.y)<.9 else Vector3.RIGHT)
		u = u.normalized()
		var v := tangent.cross(u).normalized()
		for side in SIDES:
			var angle := TAU*side/SIDES
			var normal := u*cos(angle)+v*sin(angle)
			vertices.append(points[index]+normal*radius)
			normals.append(normal)
			if index==0: continue
			var a := (index-1)*SIDES+side
			var b := (index-1)*SIDES+(side+1)%SIDES
			var c := index*SIDES+(side+1)%SIDES
			var d := index*SIDES+side
			indices.append_array(PackedInt32Array([a,c,b,a,d,c]))
	for end: int in [0,points.size()-1]:
		var normal := (points[0]-points[1]).normalized() if end==0 else (points[-1]-points[-2]).normalized()
		var centre := vertices.size()
		vertices.append(points[end])
		normals.append(normal)
		for side in SIDES:
			var a := end*SIDES+side
			var b := end*SIDES+(side+1)%SIDES
			indices.append_array(PackedInt32Array([centre,a,b] if end==0 else [centre,b,a]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	surface.mesh = mesh
