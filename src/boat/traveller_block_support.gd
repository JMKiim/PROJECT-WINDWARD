extends RefCounted

## A constrained static upper-block swivel. The lower sheave remains supported
## by its locked traveller line; full two-body dynamics is not inferred here.
const SUPPORT := preload("res://src/boat/block_mesh_support.gd")
const HINGE := preload("res://src/boat/hinged_block_equilibrium.gd")
var support: RefCounted
var key := []
var result_key := []
var cached_result := {}
var solve_count := 0

func settle(rig: Node3D,gravity: Vector3) -> Dictionary:
	var started := Time.get_ticks_usec()
	var profile := []
	var inverse := rig.global_transform.affine_inverse()
	var request := [rig.hull.mesh,inverse*rig.hull.global_transform,rig.traveller_lower.transform,rig.tiller_angle,gravity.normalized()]
	var rest: Transform3D=rig.traveller.transform
	var boundary := [request,rest,gravity]
	if boundary==result_key and not cached_result.is_empty(): return cached_result.duplicate(true)
	if request!=key:
		support=SUPPORT.new()
		support.set_body(rig.traveller)
		profile.append({"stage":"body","ms":(Time.get_ticks_usec()-started)/1000.0})
		if not support.add_surface(rig.hull.mesh,inverse*rig.hull.global_transform,gravity,"hull"):
			return {"valid":false,"reason":"invalid block hull support"}
		profile.append({"stage":"hull","ms":(Time.get_ticks_usec()-started)/1000.0})
		var faces := PackedVector3Array()
		_collect(rig.traveller_lower,inverse,faces)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=faces
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		if not support.add_surface(mesh,Transform3D.IDENTITY,gravity,"lower block",.004):
			return {"valid":false,"reason":"invalid lower block support"}
		support.tiller_enabled=true
		support.tiller_inverse=rig.traveller_tiller_frame().affine_inverse()
		key=request
	profile.append({"stage":"setup","ms":(Time.get_ticks_usec()-started)/1000.0})
	var attachment: Vector3=rig.traveller.rope_anchor_local(&"attachment")
	solve_count+=1
	var result := HINGE.solve(rest,attachment,rest.basis.x,Vector3.ZERO,.12,gravity,[],support.query,1.0,support.interval_clear)
	profile.append({"stage":"solve","ms":(Time.get_ticks_usec()-started)/1000.0})
	result["profile"]=profile
	result["queries"]=support.queries
	if result.valid:
		result_key=boundary
		cached_result=result.duplicate(true)
	return result

func _collect(node: Node3D,inverse: Transform3D,faces: PackedVector3Array) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var frame := inverse*node.global_transform
		for point in node.mesh.get_faces(): faces.append(frame*point)
	for child in node.get_children():
		if child is Node3D: _collect(child,inverse,faces)
