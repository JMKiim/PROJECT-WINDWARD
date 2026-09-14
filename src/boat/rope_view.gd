extends Node3D

## One instanced tube and one instanced joint mesh for an entire rope.
## Path length belongs to the material model, never to the draw calls.
var radius := 0.004
var color := Color("d8aa55")
var segments: MultiMeshInstance3D
var joints: MultiMeshInstance3D
var capacity := 0

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
