extends Node3D
const GEOMETRY := preload("res://src/boat/rope_tube_geometry.gd")

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

func show_path(points: PackedVector3Array,prepared: Array=[]) -> bool:
	if surface==null or points.size()<2: return false
	if points==previous: return true
	var arrays: Array=prepared if not prepared.is_empty() else GEOMETRY.build(points,radius)
	if arrays.is_empty(): return false
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	surface.mesh=mesh
	previous=points.duplicate()
	return true
