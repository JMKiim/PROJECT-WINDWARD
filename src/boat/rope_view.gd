extends Node3D

const CONTINUOUS := preload("res://src/boat/rope_tube_view.gd")

## One instanced tube and one instanced joint mesh for an entire rope.
## Path length belongs to the material model, never to the draw calls.
var radius := 0.004
var color := Color("d8aa55")
var segments: MultiMeshInstance3D
var joints: MultiMeshInstance3D
var capacity := 0
var displayed_points := PackedVector3Array()
var has_displayed_path := false
var path_updates := 0
var static_surface: Node3D
var static_display := false

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .95
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = 1.0
	tube.radial_segments = 10
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius*2
	ball.radial_segments = 10
	ball.rings = 4
	segments = _instances(tube,material)
	joints = _instances(ball,material)

func _instances(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var view := MultiMeshInstance3D.new()
	view.multimesh = MultiMesh.new()
	view.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	view.multimesh.mesh = mesh
	view.material_override = material
	add_child(view)
	return view

func show_path(points: PackedVector3Array) -> void:
	if segments==null: return
	if static_display:
		static_display=false
		has_displayed_path=false
		static_surface.hide()
		segments.show()
		joints.show()
	if has_displayed_path and points==displayed_points: return
	displayed_points=points.duplicate()
	has_displayed_path=true
	path_updates+=1
	if points.size()>capacity:
		capacity = maxi(256,int(ceil(points.size()/256.0))*256)
		segments.multimesh.instance_count = capacity
		joints.multimesh.instance_count = capacity
	segments.multimesh.visible_instance_count = maxi(0,points.size()-1)
	joints.multimesh.visible_instance_count = points.size()
	if not points.is_empty():
		var bounds := AABB(points[0],Vector3.ZERO)
		for point in points: bounds = bounds.expand(point)
		# Update culling bounds together with the moving instance transforms.
		# A previous frame's bounds may be outside a close inspection camera.
		segments.multimesh.custom_aabb = bounds.grow(radius)
		joints.multimesh.custom_aabb = bounds.grow(radius)
	for index in points.size():
		joints.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,points[index]))
		if index==0: continue
		var difference := points[index]-points[index-1]
		var basis := Basis.IDENTITY
		if difference.length()>.0000001: basis = Basis(Quaternion(Vector3.UP,difference.normalized()))
		basis.y *= difference.length()
		segments.multimesh.set_instance_transform(index-1,Transform3D(basis,(points[index]+points[index-1])*.5))

func show_static_path(points: PackedVector3Array,prepared: Array=[]) -> void:
	# Closely sampled contact curves otherwise overlap hundreds of spheres
	# and cylinders. A single continuous skin retains the same centreline.
	if segments==null: return
	if static_display and has_displayed_path and points==displayed_points: return
	if static_surface==null:
		static_surface=CONTINUOUS.new()
		static_surface.radius=radius
		static_surface.color=color
		add_child(static_surface)
	static_display=true
	has_displayed_path=true
	displayed_points=points.duplicate()
	path_updates+=1
	segments.hide()
	joints.hide()
	static_surface.visible=points.size()>=2
	if points.size()>=2: static_surface.show_path(points,prepared)
